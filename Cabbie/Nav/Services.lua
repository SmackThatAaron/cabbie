












local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local Events = FGPS.Events
local Const = FGPS.Const
local sqrt, floor, type, pairs, ipairs, tostring = math.sqrt, math.floor, type, pairs, ipairs, tostring

local ServiceSearch = {
    Types = { "vendor", "repair", "flightmaster", "inn", "mailbox", "bank", "auction", "trainer", "stable" },
    MAX_LEARNED = 600,
    DEDUPE_YARDS = 10,
    KNOWN_YARDS = 25,
    MAX_CANDIDATES = 8,
    DEFAULT_LIMIT = 5,
    DEFAULT_MAX_STRAIGHT = 4000,
    BINDER_ICON = 132052,
    STRAIGHT_FACTOR = 1.35,


    JOINT = true,
    index = nil,
    indexSource = nil,
    indexCount = nil,
    active = nil,
}
FGPS.ServiceSearch = ServiceSearch





local TYPE_CODES = {
    vendor = { 8 }, repair = { 9 }, flightmaster = { 6 }, inn = { 7 }, mailbox = { 10 }, bank = { 11 },
    auction = { 12 }, trainer = { 13 }, stable = { 20 },
}
ServiceSearch.TypeCodes = TYPE_CODES

local TYPE_SET = {}
for _, t in ipairs(ServiceSearch.Types) do TYPE_SET[t] = true end










local CLASS_WORDS = {
    warrior = "WARRIOR", paladin = "PALADIN", hunter = "HUNTER", rogue = "ROGUE", priest = "PRIEST",
    shaman = "SHAMAN", mage = "MAGE", warlock = "WARLOCK", druid = "DRUID",
}

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


local function resolveType(serviceType)
    if type(serviceType) ~= "string" then return nil end
    if TYPE_CODES[serviceType] then return serviceType, nil end
    local base, sub = serviceType:match("^(%a+):(.+)$")
    if base == "trainer" and sub ~= "" then return base, sub end
    return nil
end
ServiceSearch.ResolveType = resolveType


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



local SPOT_ONLY_KINDS = { flightmaster = true, mailbox = true }

local function baseName(name)
    return Util.Lower((name:gsub("%s*%b()%s*$", "")))
end















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




function ServiceSearch.Learned()
    return learnedList()
end


local function clientLocale()
    if not GetLocale then return nil end
    local ok, loc = pcall(GetLocale)
    return ok and type(loc) == "string" and loc ~= "" and loc or nil
end










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
        for i = 2, #list - 1 do
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




local function learnedDest(s, i)

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

            if not e.seconds then e.straight, e.seconds = true, straightSeconds(e) end
        end
        table.sort(entries, function(a, b)
            if a.seconds ~= b.seconds then return a.seconds < b.seconds end
            if a.straight ~= b.straight then return not a.straight end
            return a.straightYards < b.straightYards
        end)
        while #entries > limit do entries[#entries] = nil end
        callback(entries, err)
    end
    search.finish = finish
    ServiceSearch.Cancel()
    ServiceSearch.active = search



    local useJoint = Router and Router.RequestGoals and (opts.joint == true or (opts.joint ~= false and ServiceSearch.JOINT))
    if useJoint and canRoute then
        ServiceSearch._routeJoint(search, entries, pos, access, straightSeconds, finish)
        return true
    end



    local function currentBound()
        local routed = {}
        for _, e in ipairs(entries) do if e.seconds and not e.straight then routed[#routed + 1] = e.seconds end end
        if #routed < limit then return nil end
        table.sort(routed)
        return routed[limit]
    end



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
            if search.cancelled or search.done then return end
            if route and type(route.totalSeconds) == "number" then
                e.route, e.seconds, e.yards = route, route.totalSeconds, route.totalYards
                e.straight = route.fallback == "straight"
            else

                e.straight, e.seconds, e.err = true, straightSeconds(e), routeErr


                local partial = type(routeErr) == "table" and routeErr.partial or nil
                local bound = type(partial) == "table" and partial.bound or nil
                if type(bound) == "number" and bound > e.seconds then e.seconds, e.bounded = bound, true end
            end
            step()
        end)
        if not ok then
            if delivered then


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


    Events:Register("ROUTE_STARTED", function() ServiceSearch.Cancel() end, self)
    Events:Register("NAV_RECALC_START", function() ServiceSearch.Cancel() end, self)
end
