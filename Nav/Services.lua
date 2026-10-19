-- Cabbie/Nav/Services.lua
-- "Nearest service" search and runtime discovery of services. Candidates come from the compiled
-- POI table (vendors, repair, flight masters, inns, mailboxes, banks, auction houses, trainers,
-- stable masters) plus services the player actually used (learned at MERCHANT_SHOW, GOSSIP_SHOW
-- with an innkeeper option, MAIL_SHOW, BANKFRAME_OPENED, TAXIMAP_OPENED, TRAINER_SHOW). Nearest()
-- first ranks by straight-line distance, then routes the closest few in one search toward all of
-- them and returns them sorted by routed travel time; a candidate the router could not route is
-- kept with a flagged straight-line estimate. A router without that search still asks for them
-- one after another, with a shrinking maxSeconds bound.
-- Only one search runs at a time and it never competes with guidance: ServiceSearch.Cancel() stops
-- it (the Router request in flight is cancelled, candidates not routed yet get the straight-line
-- estimate and the callback still fires once, with err "cancelled"). A new Nearest() call, a
-- started journey (ROUTE_STARTED) and a recalculation (NAV_RECALC_START) cancel it automatically.
local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local Events = FGPS.Events
local Const = FGPS.Const
local sqrt, floor, type, pairs, ipairs, tostring = math.sqrt, math.floor, type, pairs, ipairs, tostring

local ServiceSearch = {
    Types = { "vendor", "repair", "flightmaster", "inn", "mailbox", "bank", "auction", "trainer", "stable" },
    MAX_LEARNED = 600,             -- ~210 bytes of saved variables per entry: well inside the 200 KB budget
    DEDUPE_YARDS = 10,
    KNOWN_YARDS = 25,              -- a bundled row of the same name this near a recorded service is that service (InData)
    MAX_CANDIDATES = 8,
    DEFAULT_LIMIT = 5,
    DEFAULT_MAX_STRAIGHT = 4000,
    BINDER_ICON = 132052,          -- Interface\GossipFrame\BinderGossipIcon
    STRAIGHT_FACTOR = 1.35,        -- unverified straight estimate factor (matches Cost kind 14)
    -- The shared search is the one the player gets. opts.joint = false keeps the old requests,
    -- which is how the two were compared (360 nearest services, the same winner each time).
    JOINT = true,
    index = nil,
    indexSource = nil,             -- the POI table (and its length) the index was built from
    indexCount = nil,
    active = nil,                  -- the running Nearest() search: { cancelled, done, handle, finish }
}
FGPS.ServiceSearch = ServiceSearch

-- Service type -> POI type codes (DATA_FORMAT.md). A repairer also sells, and the data already
-- gives every repair spawn its own vendor row (one row per service, at the same name and spot), so
-- "vendor" is 8 alone: with 9 as well each repairer was a candidate twice. tests/test_services.lua
-- fails when a repair row without its vendor row appears in the data.
local TYPE_CODES = {
    vendor = { 8 }, repair = { 9 }, flightmaster = { 6 }, inn = { 7 }, mailbox = { 10 }, bank = { 11 },
    auction = { 12 }, trainer = { 13 }, stable = { 20 },
}
ServiceSearch.TypeCodes = TYPE_CODES

local TYPE_SET = {}
for _, t in ipairs(ServiceSearch.Types) do TYPE_SET[t] = true end

-------------------------------------------------------------------------------
-- Trainer kinds
-------------------------------------------------------------------------------
-- "Trainer" is 493 people of 25 trades. Asked for the nearest five of the lot, a warrior in
-- Orgrimmar got enchanters and cooks and never his own trainer. The role is already in the data:
-- a bundled trainer is named "Grezz Ragefist (Warrior Trainer)" (tools/build_services.py appends
-- the SubName), so the kind is read from that subtitle. A search may name the kind after a colon,
-- "trainer:WARRIOR" or "trainer:mining"; plain "trainer" still means any of them.
-- The subtitles are English whatever the client language, because the data names are.
local CLASS_WORDS = {
    warrior = "WARRIOR", paladin = "PALADIN", hunter = "HUNTER", rogue = "ROGUE", priest = "PRIEST",
    shaman = "SHAMAN", mage = "MAGE", warlock = "WARLOCK", druid = "DRUID",
}
-- First match wins, so "Weapon Master" and "Weapon Crafter" are settled before anything looser.
local TRAINER_RULES = {
    { "weapon master", "weapons" }, { "riding", "riding" }, { "pilot", "riding" },
    { "pet trainer", "pet" }, { "portal", "portal" },
    { "alchem", "alchemy" },
    { "blacksmith", "blacksmithing" }, { "armorsmith", "blacksmithing" }, { "weaponsmith", "blacksmithing" },
    { "armor crafter", "blacksmithing" }, { "weapon crafter", "blacksmithing" },
    { "enchant", "enchanting" }, { "engineer", "engineering" }, { "leather", "leatherworking" },
    { "tailor", "tailoring" }, { "herbal", "herbalism" }, { "mining", "mining" }, { "miner", "mining" },
    { "skinn", "skinning" }, { "cook", "cooking" }, { "fish", "fishing" },
    { "first aid", "firstaid" }, { "physician", "firstaid" }, { "surgeon", "firstaid" },
}
ServiceSearch.TRAINER_PROFESSIONS = { "alchemy", "blacksmithing", "cooking", "enchanting", "engineering", "firstaid", "fishing",
    "herbalism", "leatherworking", "mining", "skinning", "tailoring" }

-- Kind of a trainer from its display name: a class token ("WARRIOR"), a profession ("mining"),
-- "weapons", "riding", "pet", "portal", or "other" when the name says nothing.
function ServiceSearch.TrainerKind(name)
    if type(name) ~= "string" then return "other" end
    local text = (name:match("%((.-)%)%s*$") or name):lower()
    for word in text:gmatch("%a+") do
        if CLASS_WORDS[word] then return CLASS_WORDS[word] end
    end
    for _, rule in ipairs(TRAINER_RULES) do
        if text:find(rule[1], 1, true) then return rule[2] end
    end
    return "other"
end

-- "trainer:mining" -> "trainer", "mining"; "bank" -> "bank", nil; anything unknown -> nil.
local function resolveType(serviceType)
    if type(serviceType) ~= "string" then return nil end
    if TYPE_CODES[serviceType] then return serviceType, nil end
    local base, sub = serviceType:match("^(%a+):(.+)$")
    if base == "trainer" and sub ~= "" then return base, sub end
    return nil
end
ServiceSearch.ResolveType = resolveType

-- The player's class token ("WARRIOR"), or nil when the client does not say.
function ServiceSearch.PlayerClass()
    if not UnitClass then return nil end
    local ok, _, token = pcall(UnitClass, "player")
    if ok and type(token) == "string" and token ~= "" then return token end
    return nil
end

local function dist(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return sqrt(dx * dx + dy * dy)
end

local function playerPos()
    local D = FGPS.Destinations
    if D and D.PlayerPos then return D.PlayerPos() end
    return nil
end

local function playerFactionCode()
    local D = FGPS.Destinations
    if D and D.PlayerFactionCode then return D.PlayerFactionCode() end
    return 3
end

local function factionAllowed(fac, code)
    local D = FGPS.Destinations
    if D and D.FactionAllowed then return D.FactionAllowed(fac, code, false) end
    return not fac or fac == 0 or fac == code
end

-- An entry as Remember writes it, in the fields every reader computes with. The list is saved, so a
-- hand-edited file or another add-on can leave anything in it, and one number in the list made the
-- place search, the nearest search and the recording at a merchant raise.
local function usableEntry(s)
    return type(s) == "table" and type(s.kind) == "string" and type(s.name) == "string"
        and type(s.x) == "number" and type(s.y) == "number"
end

local function learnedList()
    local DB = FGPS.DB
    if not DB or not DB.account then
        ServiceSearch.volatileLearned = ServiceSearch.volatileLearned or {}
        return ServiceSearch.volatileLearned
    end
    if type(DB.account.learnedServices) ~= "table" then DB.account.learnedServices = {} end
    local list = DB.account.learnedServices
    for i = #list, 1, -1 do
        if not usableEntry(list[i]) then table.remove(list, i) end
    end
    return list
end

-------------------------------------------------------------------------------
-- POI index per type code (one scan, built lazily)
-------------------------------------------------------------------------------
-- The compiled POI table never changes in the client, so the index is built once; it is rebuilt
-- only when the table itself was replaced or grew (tests, a data reload), not on DATA_LOADED, which
-- fires every time another instance graph is indexed.
local function ensureIndex()
    local P = FGPS.Data and FGPS.Data.poi
    if ServiceSearch.index and ServiceSearch.indexSource == P and ServiceSearch.indexCount == (P and P.n) then
        return ServiceSearch.index
    end
    local index = {}
    ServiceSearch.indexSource, ServiceSearch.indexCount = P, P and P.n
    if P then
        local types = P.type
        for i = 1, P.n do
            local code = types[i]
            local bucket = index[code]
            if not bucket then bucket = {} index[code] = bucket end
            bucket[#bucket + 1] = i
        end
    end
    ServiceSearch.index = index
    return index
end

function ServiceSearch.InvalidateIndex()
    ServiceSearch.index = nil
end

-- Kinds whose bundled rows are not named after a person: a flight master's row carries the name of
-- its node, and a mailbox is nobody. Their spot alone says that the data has them.
local SPOT_ONLY_KINDS = { flightmaster = true, mailbox = true }

local function baseName(name)
    return Util.Lower((name:gsub("%s*%b()%s*$", "")))
end

-- True when the bundled data already holds the service of a recorded entry. Nearly every merchant,
-- innkeeper or flight master a player opens is a row of Data/POI.lua, and the record of the visit,
-- listed beside it, showed one NPC twice in the nearest list and in the search. A row of the
-- entry's kind within KNOWN_YARDS is the same service when its name without the "(subtitle)" is the
-- entry's name (the data names "Jessica Chambers (Innkeeper)", the client "Jessica Chambers"), and
-- for a kind of SPOT_ONLY_KINDS whatever the name. The spot alone does not decide for the others: a
-- merchant the data lacks can stand beside one it has. The data's names are English, so on a
-- client in another language a recorded merchant the data has is still listed beside it. A row
-- stands in for the entry only when it is offered to side (the side that looks: 1, 2, or 3 when not
-- known; by default the side the entry was recorded for, fac): a merchant the data gives to the
-- other side but who served this one is shown by the record alone, and a record both sides used is
-- shown only to the side the row leaves out. The answer is kept per entry and side for the POI
-- table indexed now: a full list of 600 entries costs about 30 ms under desktop lua5.1, and the
-- search index is built again after every new entry.
local inDataMemo, inDataIndex
function ServiceSearch.InData(s, side)
    local codes = usableEntry(s) and TYPE_CODES[s.kind]
    local P = FGPS.Data and FGPS.Data.poi
    if not codes or not P then return false end
    side = side or s.fac or 0
    local index = ensureIndex()
    if inDataIndex ~= index then inDataMemo, inDataIndex = setmetatable({}, { __mode = "k" }), index end
    local memo = inDataMemo[s]
    if not (memo and memo.kind == s.kind and memo.name == s.name and memo.inst == s.inst and memo.x == s.x
        and memo.y == s.y) then
        memo = { kind = s.kind, name = s.name, inst = s.inst, x = s.x, y = s.y, known = {} }
        inDataMemo[s] = memo
    end
    if memo.known[side] ~= nil then return memo.known[side] end
    local near, known = ServiceSearch.KNOWN_YARDS, false
    local name, spotOnly = baseName(s.name), SPOT_ONLY_KINDS[s.kind]
    for _, code in ipairs(codes) do
        for _, i in ipairs(index[code] or {}) do
            local dx, dy = P.x[i] - s.x, P.y[i] - s.y
            if P.inst[i] == s.inst and dx > -near and dx < near and dy > -near and dy < near
                and dx * dx + dy * dy <= near * near and (spotOnly or baseName(P.name[i]) == name)
                and factionAllowed(P.fac[i], side) then
                known = true
                break
            end
        end
        if known then break end
    end
    memo.known[side] = known
    return known
end

-------------------------------------------------------------------------------
-- Learned services
-------------------------------------------------------------------------------
function ServiceSearch.Learned()
    return learnedList()
end

-- The client's language ("deDE"), or nil when the client does not say.
local function clientLocale()
    if not GetLocale then return nil end
    local ok, loc = pcall(GetLocale)
    return ok and type(loc) == "string" and loc ~= "" and loc or nil
end

-- Records a service the player used. The same service is an entry of the same kind within
-- DEDUPE_YARDS with the same name or, when none has it, the nearest one recorded under another
-- client language (loc), which takes the name of now: a client switched to another language names
-- the same NPC and the same mailbox anew. An entry saved without its language is matched by its
-- name alone. The list is shared by the account's characters and an entry carries the side of the
-- one who recorded it (fac); a character of the other side who uses it too shows that it serves
-- both, and it becomes fac 0. The list is capped at MAX_LEARNED; beyond that the entry used longest
-- ago goes first (the earliest of several equally old ones). Map coordinates and the zone name are
-- not stored: they follow from inst/x/y and the map when an entry is read.
function ServiceSearch.Remember(kind, name, pos)
    if type(kind) ~= "string" or not TYPE_SET[kind] then return nil, "bad_kind" end
    pos = pos or playerPos()
    if not pos or not pos.inst or not pos.x or not pos.y then return nil, "no_position" end
    name = Util.Trim(tostring(name or ""))
    if name == "" then name = L[kind:sub(1, 1):upper() .. kind:sub(2)] end
    local list = learnedList()
    local stamp = time and time() or 0
    local loc, fac = clientLocale(), playerFactionCode()
    if fac == 3 then fac = 0 end
    local same, other, otherD
    for i = 1, #list do
        local s = list[i]
        local d = s.kind == kind and s.inst == pos.inst and dist(s.x, s.y, pos.x, pos.y)
        if d and d <= ServiceSearch.DEDUPE_YARDS then
            if s.name == name then same = s break end
            if loc and s.loc and s.loc ~= loc and (not otherD or d < otherD) then other, otherD = s, d end
        end
    end
    same = same or other
    if same then
        local changed = same.name ~= name
        same.name, same.loc = name, loc or same.loc
        if fac ~= 0 and (same.fac or 0) ~= 0 and same.fac ~= fac then same.fac, changed = 0, true end
        same.time = stamp
        same.seen = (same.seen or 1) + 1
        if changed then Events:Fire("LEARNED_SERVICES_CHANGED", same) end
        return same, false
    end
    local entry = {
        kind = kind, name = name, inst = pos.inst, x = floor(pos.x * 10 + 0.5) / 10, y = floor(pos.y * 10 + 0.5) / 10,
        map = pos.map, fac = fac, loc = loc, time = stamp, seen = 1,
    }
    list[#list + 1] = entry
    while #list > ServiceSearch.MAX_LEARNED do
        local oldest, oldestTime = 1, tonumber(list[1].time) or 0
        for i = 2, #list - 1 do                     -- never the entry just added
            local t = tonumber(list[i].time) or 0
            if t < oldestTime then oldest, oldestTime = i, t end
        end
        table.remove(list, oldest)
    end
    Events:Fire("LEARNED_SERVICES_CHANGED", entry)
    return entry, true
end

function ServiceSearch.ClearLearned()
    wipe(learnedList())
    Events:Fire("LEARNED_SERVICES_CHANGED")
end

-------------------------------------------------------------------------------
-- Nearest
-------------------------------------------------------------------------------
local function learnedDest(s, i)
    -- Entries saved by earlier versions still carry mx / my / zoneName; newer ones derive them here.
    local mx, my, zoneName = s.mx, s.my, s.zoneName
    local D = FGPS.Destinations
    if D and s.map then
        if not zoneName and D.MapName then zoneName = D.MapName(s.map) end
        if (not mx or not my) and D.WorldToMap then
            local map, zx, zy = D.WorldToMap(s.inst, s.x, s.y, s.map)
            if map then mx, my = zx, zy end
        end
    end
    return { kind = "service", name = s.name, inst = s.inst, x = s.x, y = s.y, map = s.map, mx = mx, my = my,
             type = s.kind, serviceKind = s.kind, zoneName = zoneName, faction = (s.fac ~= 0) and s.fac or nil,
             learned = true, learnedIndex = i }
end

local function poiDest(i)
    local D = FGPS.Destinations
    if D and D.FromPOI then
        local dest = D.FromPOI(i)
        if dest then return dest end
    end
    local P = FGPS.Data.poi
    return { kind = "poi", poiIndex = i, name = P.name[i], inst = P.inst[i], x = P.x[i], y = P.y[i], map = P.map[i], typeCode = P.type[i] }
end

local function groundSpeed(access)
    local Cost = FGPS.Cost
    if Cost and Cost.GroundSpeed then
        local ok, v = pcall(Cost.GroundSpeed, access)
        if ok and type(v) == "number" and v > 0 then return v end
    end
    if IsMounted and IsMounted() then return Const.MOUNT_100 or 14 end
    return Const.RUN_SPEED or 7
end

-- Straight-line candidates of a service type around the player (same instance, faction allowed).
function ServiceSearch.Candidates(serviceType, pos, maxStraight, maxCount)
    local out = {}
    local base, sub = resolveType(serviceType)
    if not pos or not base then return out end
    serviceType = base
    local code = playerFactionCode()
    local P = FGPS.Data and FGPS.Data.poi
    if P then
        local index = ensureIndex()
        for _, typeCode in ipairs(TYPE_CODES[serviceType]) do
            for _, i in ipairs(index[typeCode] or {}) do
                if P.inst[i] == pos.inst and factionAllowed(P.fac[i], code)
                    and (sub == nil or ServiceSearch.TrainerKind(P.name[i]) == sub) then
                    local d = dist(P.x[i], P.y[i], pos.x, pos.y)
                    if d <= maxStraight then out[#out + 1] = { poiIndex = i, straightYards = d } end
                end
            end
        end
    end
    for i, s in ipairs(learnedList()) do
        -- A trainer the player visited is remembered by name only, which says nothing about the
        -- trade, so it answers the plain "trainer" search and no search for one kind.
        local matches = sub == nil and (s.kind == serviceType or (serviceType == "vendor" and s.kind == "repair"))
        if matches and s.inst == pos.inst and s.x and s.y and factionAllowed(s.fac, code) then
            local d = dist(s.x, s.y, pos.x, pos.y)
            if d <= maxStraight and not ServiceSearch.InData(s, code) then
                out[#out + 1] = { learned = s, learnedIndex = i, straightYards = d }
            end
        end
    end
    table.sort(out, function(a, b) return a.straightYards < b.straightYards end)
    while maxCount and #out > maxCount do out[#out] = nil end
    return out
end

-- Trainer kinds that exist around the player (same instance, faction allowed, within range), for
-- the menu: { { kind, count, nearestYards }, ... }. The player's own class comes first, then the
-- professions, the weapon masters and riding instructors, the rest, and "other" last; inside a
-- group the nearer kind comes first.
function ServiceSearch.TrainerKinds(pos, maxStraight)
    pos = pos or playerPos()
    maxStraight = maxStraight or ServiceSearch.DEFAULT_MAX_STRAIGHT
    local byKind, list = {}, {}
    for _, c in ipairs(ServiceSearch.Candidates("trainer", pos, maxStraight)) do
        if c.poiIndex then
            local kind = ServiceSearch.TrainerKind(FGPS.Data.poi.name[c.poiIndex])
            local entry = byKind[kind]
            if not entry then
                entry = { kind = kind, count = 0, nearestYards = c.straightYards }
                byKind[kind] = entry
                list[#list + 1] = entry
            end
            entry.count = entry.count + 1
        end
    end
    local mine = ServiceSearch.PlayerClass()
    local professions = {}
    for _, key in ipairs(ServiceSearch.TRAINER_PROFESSIONS) do professions[key] = true end
    local function rank(kind)
        if kind == mine then return 1 end
        if professions[kind] then return 2 end
        if kind == "weapons" or kind == "riding" then return 3 end
        if kind == "other" then return 5 end
        return 4
    end
    table.sort(list, function(a, b)
        local ra, rb = rank(a.kind), rank(b.kind)
        if ra ~= rb then return ra < rb end
        if a.nearestYards ~= b.nearestYards then return a.nearestYards < b.nearestYards end
        return a.kind < b.kind
    end)
    return list
end

-- Stops the running Nearest() search, if any: the Router request in flight is cancelled, no further
-- request is issued and the search's callback fires right away with what is known (candidates not
-- routed yet carry the flagged straight-line estimate) and err "cancelled". Returns true when a
-- search was running.
function ServiceSearch.Cancel()
    local search = ServiceSearch.active
    if not search then return false end
    ServiceSearch.active = nil
    search.cancelled = true
    local Router = FGPS.Router
    local handle = search.handle
    search.handle = nil
    if handle and Router and Router.Cancel then pcall(Router.Cancel, Router, handle) end
    search.finish("cancelled")
    return true
end

function ServiceSearch.IsSearching()
    return ServiceSearch.active ~= nil
end

-- One Router request for every candidate still waiting. The callback contract of Nearest is
-- unchanged: finish() sorts by routed time and calls the caller once.
function ServiceSearch._routeJoint(search, entries, pos, access, straightSeconds, finish)
    local Router = FGPS.Router
    local stops = {}
    for _, e in ipairs(entries) do stops[#stops + 1] = e.dest end
    local request = { origin = pos, stops = stops, access = access, variant = "fastest", reason = "service" }
    local delivered = false
    local ok, handle = pcall(Router.RequestGoals, Router, request, function(route, routeErr)
        delivered = true
        search.handle = nil
        if search.cancelled or search.done then return end
        local results = route and route.results
        if results then
            for i, e in ipairs(entries) do
                local one = results[i]
                if one and type(one.totalSeconds) == "number" then
                    e.route, e.seconds, e.yards = one, one.totalSeconds, one.totalYards
                    e.straight = one.fallback == "straight"
                else
                    e.straight, e.seconds, e.err = true, straightSeconds(e), routeErr
                end
            end
            entries.jointExp = route.expansions
        else
            for _, e in ipairs(entries) do
                if not e.seconds then e.straight, e.seconds, e.err = true, straightSeconds(e), routeErr end
            end
        end
        finish()
    end)
    if not ok then
        if delivered then
            if FGPS.Log then FGPS.Log:Error("Service search result handling failed: %s", tostring(handle)) end
            finish()
        else
            for _, e in ipairs(entries) do
                e.straight, e.seconds, e.err = true, straightSeconds(e), { code = "NO_DATA", message = tostring(handle) }
            end
            finish()
        end
    elseif not delivered then
        search.handle = handle
    end
end

-- Nearest(type, { access, limit = 5, maxStraightYards = 4000 }, callback(list, err))
-- list entries: { dest, straightYards, seconds, yards?, route?, straight = bool, err?, bounded? }
-- The callback fires exactly once; err is nil, "bad_type", "no_position", "none" or "cancelled".
function ServiceSearch.Nearest(serviceType, opts, callback)
    if type(opts) == "function" then opts, callback = nil, opts end
    opts = opts or {}
    callback = callback or function() end
    if not resolveType(serviceType) then callback({}, "bad_type") return false end
    local pos = playerPos()
    if not pos or not pos.inst then callback({}, "no_position") return false end
    local limit = opts.limit or ServiceSearch.DEFAULT_LIMIT
    local maxStraight = opts.maxStraightYards or ServiceSearch.DEFAULT_MAX_STRAIGHT
    local candidates = ServiceSearch.Candidates(serviceType, pos, maxStraight, ServiceSearch.MAX_CANDIDATES)
    if #candidates == 0 then callback({}, "none") return true end

    local access = opts.access
    if not access and FGPS.Access and FGPS.Access.Snapshot then
        local ok, snap = pcall(FGPS.Access.Snapshot, FGPS.Access)
        if ok then access = snap end
    end
    local speed = groundSpeed(access)
    local entries = {}
    for _, c in ipairs(candidates) do
        local dest = c.learned and learnedDest(c.learned, c.learnedIndex) or poiDest(c.poiIndex)
        if dest then
            entries[#entries + 1] = { dest = dest, straightYards = c.straightYards, seconds = nil, straight = false }
        end
    end

    local Router = FGPS.Router
    local canRoute = Router ~= nil and Router.RequestRoute ~= nil and opts.route ~= false
    local function straightSeconds(e) return e.straightYards / speed * ServiceSearch.STRAIGHT_FACTOR end

    local search = { cancelled = false, done = false, handle = nil }
    local function finish(err)
        if search.done then return end
        search.done = true
        if ServiceSearch.active == search then ServiceSearch.active = nil end
        for _, e in ipairs(entries) do
            -- Not routed (the search was cancelled before its turn): straight-line estimate.
            if not e.seconds then e.straight, e.seconds = true, straightSeconds(e) end
        end
        table.sort(entries, function(a, b)
            if a.seconds ~= b.seconds then return a.seconds < b.seconds end
            if a.straight ~= b.straight then return not a.straight end      -- a routed time beats an equal estimate
            return a.straightYards < b.straightYards
        end)
        while #entries > limit do entries[#entries] = nil end
        callback(entries, err)
    end
    search.finish = finish
    ServiceSearch.Cancel()      -- one search at a time: a new query replaces the running one
    ServiceSearch.active = search

    -- One search toward every candidate (Router:RequestGoals). The requests below stay for a
    -- router that has no shared search, and for opts.joint = false.
    local useJoint = Router and Router.RequestGoals and (opts.joint == true or (opts.joint ~= false and ServiceSearch.JOINT))
    if useJoint and canRoute then
        ServiceSearch._routeJoint(search, entries, pos, access, straightSeconds, finish)
        return true
    end

    -- Bound for the next request: the limit-th best routed time so far (later candidates only
    -- matter when they beat it).
    local function currentBound()
        local routed = {}
        for _, e in ipairs(entries) do if e.seconds and not e.straight then routed[#routed + 1] = e.seconds end end
        if #routed < limit then return nil end
        table.sort(routed)
        return routed[limit]
    end

    -- Requests run one after the other; search.handle is the Router handle in flight so that
    -- ServiceSearch.Cancel() can stop it.
    local i = 0
    local function step()
        if search.cancelled or search.done then return end
        i = i + 1
        local e = entries[i]
        if not e then finish() return end
        if not canRoute then
            e.straight, e.seconds = true, straightSeconds(e)
            return step()
        end
        local request = { origin = pos, stops = { e.dest }, access = access, variant = "fastest", reason = "service", maxSeconds = currentBound() }
        local delivered = false
        local ok, handle = pcall(Router.RequestRoute, Router, request, function(route, routeErr)
            delivered = true
            search.handle = nil
            if search.cancelled or search.done then return end      -- Cancel() reports for every candidate itself
            if route and type(route.totalSeconds) == "number" then
                e.route, e.seconds, e.yards = route, route.totalSeconds, route.totalYards
                e.straight = route.fallback == "straight"
            else
                -- Failed candidates stay in the list with the flagged straight-line estimate.
                e.straight, e.seconds, e.err = true, straightSeconds(e), routeErr
                -- A search cut off by maxSeconds proves the real time is at least the bound: the
                -- (optimistic) straight-line figure must not put this candidate ahead of routed ones.
                local partial = type(routeErr) == "table" and routeErr.partial or nil
                local bound = type(partial) == "table" and partial.bound or nil
                if type(bound) == "number" and bound > e.seconds then e.seconds, e.bounded = bound, true end
            end
            step()
        end)
        if not ok then
            if delivered then
                -- The router delivered and the handling above raised: log it and close the search
                -- (a no-op when the error came from the caller's own callback).
                if FGPS.Log then FGPS.Log:Error("Service search result handling failed: %s", tostring(handle)) end
                finish()
            else
                e.straight, e.seconds, e.err = true, straightSeconds(e), { code = "NO_DATA", message = tostring(handle) }
                step()
            end
        elseif not delivered then
            search.handle = handle
        end
    end
    step()
    return true
end

-------------------------------------------------------------------------------
-- Discovery events
-------------------------------------------------------------------------------
local function npcName(fallback)
    if UnitName then
        local ok, name = pcall(UnitName, "npc")
        if ok and type(name) == "string" and name ~= "" and not (issecretvalue and issecretvalue(name)) then return name end
    end
    return fallback
end

local function isInnkeeperOption(opt)
    if type(opt) ~= "table" then return false end
    if opt.type == "binder" then return true end
    if opt.icon == ServiceSearch.BINDER_ICON or opt.overrideIconID == ServiceSearch.BINDER_ICON then return true end
    local name = type(opt.name) == "string" and Util.Lower(opt.name) or ""
    if name:find("inn your home", 1, true) or name:find(Util.Lower(L["Make this inn your home"]), 1, true) then return true end
    return false
end
ServiceSearch.IsInnkeeperOption = isInnkeeperOption

function ServiceSearch.OnMerchantShow()
    local repair = false
    if CanMerchantRepair then
        local ok, v = pcall(CanMerchantRepair)
        repair = ok and v and true or false
    end
    return ServiceSearch.Remember(repair and "repair" or "vendor", npcName(L[repair and "Repair vendor" or "Vendor"]))
end

function ServiceSearch.OnGossipShow()
    if not (C_GossipInfo and C_GossipInfo.GetOptions) then return nil end
    local ok, options = pcall(C_GossipInfo.GetOptions)
    if not ok or type(options) ~= "table" then return nil end
    for _, opt in ipairs(options) do
        if isInnkeeperOption(opt) then return ServiceSearch.Remember("inn", npcName(L["Innkeeper"])) end
    end
    return nil
end

function ServiceSearch:Init()
    if self.initialised then return end
    self.initialised = true
    Events:RegisterWoW("MERCHANT_SHOW", function() ServiceSearch.OnMerchantShow() end, self)
    Events:RegisterWoW("GOSSIP_SHOW", function() ServiceSearch.OnGossipShow() end, self)
    Events:RegisterWoW("MAIL_SHOW", function() ServiceSearch.Remember("mailbox", L["Mailbox"]) end, self)
    Events:RegisterWoW("BANKFRAME_OPENED", function() ServiceSearch.Remember("bank", npcName(L["Bank"])) end, self)
    Events:RegisterWoW("TAXIMAP_OPENED", function() ServiceSearch.Remember("flightmaster", npcName(L["Flight master"])) end, self)
    Events:RegisterWoW("TRAINER_SHOW", function() ServiceSearch.Remember("trainer", npcName(L["Trainer"])) end, self)
    -- Guidance comes first: a starting journey or a recalculation must not wait behind (or run
    -- next to) up to eight service route requests.
    Events:Register("ROUTE_STARTED", function() ServiceSearch.Cancel() end, self)
    Events:Register("NAV_RECALC_START", function() ServiceSearch.Cancel() end, self)
end
