













local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local Events = FGPS.Events
local Const = FGPS.Const
local sqrt, floor, type, pairs, ipairs, tostring = math.sqrt, math.floor, type, pairs, ipairs, tostring

local ServiceSearch = {
    Types = { "vendor", "repair", "flightmaster", "inn", "mailbox", "bank", "auction", "trainer", "stable", "dummy" },
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
    auction = { 12 }, trainer = { 13 }, stable = { 20 }, dummy = { 22 },
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




local TRAINER_TITLES = {
    WARRIOR = "Warrior Trainer", PALADIN = "Paladin Trainer", HUNTER = "Hunter Trainer", ROGUE = "Rogue Trainer",
    PRIEST = "Priest Trainer", SHAMAN = "Shaman Trainer", MAGE = "Mage Trainer", WARLOCK = "Warlock Trainer",
    DRUID = "Druid Trainer",
    alchemy = "Alchemy Trainer", blacksmithing = "Blacksmithing Trainer", cooking = "Cooking Trainer",
    enchanting = "Enchanting Trainer", engineering = "Engineering Trainer", firstaid = "First Aid Trainer",
    fishing = "Fishing Trainer", herbalism = "Herbalism Trainer", leatherworking = "Leatherworking Trainer",
    mining = "Mining Trainer", skinning = "Skinning Trainer", tailoring = "Tailoring Trainer",
    pet = "Pet Trainer", riding = "Riding Trainer",
}






function ServiceSearch.EntryName(s)
    if type(s) ~= "table" then return nil end
    local title = s.kind == "trainer" and TRAINER_TITLES[s.trainer] or nil
    if s.source == "questie" then
        title = title or (type(s.sub) == "string" and s.sub ~= "" and s.sub) or nil
        if s.replacesPOI then
            if title then return s.name .. " (" .. title .. ")" end
            return s.name
        end
        if title then return s.name .. " (" .. title .. ", " .. L["from Questie"] .. ")" end
        return s.name .. " (" .. L["from Questie"] .. ")"
    end
    if title then return s.name .. " (" .. title .. ")" end
    return s.name
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


local function clientLocale()
    if not GetLocale then return nil end
    local ok, loc = pcall(GetLocale)
    return ok and type(loc) == "string" and loc ~= "" and loc or nil
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
            if not ServiceSearch.IsShadowedPOI(i) and P.inst[i] == s.inst
                and dx > -near and dx < near and dy > -near and dy < near
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



























ServiceSearch.QUESTIE_CONTRACT = 4
ServiceSearch.QUESTIE_DELAY = 10
ServiceSearch.QUESTIE_SLICE_MS = 2
ServiceSearch.QUESTIE_ROWS_PER_YIELD = 25
ServiceSearch.QUESTIE_PLACES_PER_YIELD = 200
ServiceSearch.QUESTIE_SAME_YARDS = 60


ServiceSearch.questie = {
    rows = {}, rev = 0, state = nil, stats = nil, task = nil, waiting = nil,
    shadowedPOI = {}, shadowedForRows = nil,
}

function ServiceSearch.IsShadowedPOI(poiIndex)
    local q = ServiceSearch.questie
    if type(q) ~= "table" or type(q.shadowedPOI) ~= "table" or poiIndex == nil then return false end
    if q.shadowedForRows ~= nil and q.rows ~= q.shadowedForRows then return false end
    return q.shadowedPOI[poiIndex] == true
end

function ServiceSearch.Reset()
    local q = ServiceSearch.questie
    if type(q) == "table" then
        q.state, q.rows, q.stats, q.task, q.waiting = nil, {}, nil, nil, nil
        q.shadowedPOI, q.shadowedForRows = {}, nil
        q.rev = (q.rev or 0) + 1
    end
    inDataIndex = nil
    ServiceSearch.Cancel()
    local D = FGPS.Destinations
    if D and D.InvalidateIndex then D.InvalidateIndex() end
    local MP = FGPS.UI and FGPS.UI.MapPlaces
    if MP and MP.InvalidateCache then MP.InvalidateCache() end
end

local QUESTIE_SIDES = { A = 1, H = 2, AH = 0 }
local QUESTIE_WHY = {
    absent = "QuestieDB is not loaded",
    contract = "QuestieDB's contract is not the one this reader was written for",
    api = "QuestieDB does not offer the reads this needs",
    locale = "QuestieDB's names are in the client's language, the bundled data's in English",
    cancelled = "the read was stopped",
}

local QUESTIE_ENGLISH = { enUS = true, enGB = true }






local QUESTIE_SEASONAL = {
    "lunar festival", "coin of ancestry", "smokywood", "winter veil", "hallow's end", "sweet treats", "darkmoon",
    "brewfest", "midsummer", "love is in the air", "noblegarden", "children's week", "harvest festival",
}

local function seasonal(name, sub)
    for _, text in ipairs({ name, sub }) do
        if type(text) == "string" then
            local lower = Util.Lower(text)
            for _, word in ipairs(QUESTIE_SEASONAL) do
                if lower:find(word, 1, true) then return true end
            end
        end
    end
    return false
end



local QUESTIE_FLAGS = {
    { "VENDOR", "vendor" }, { "REPAIR", "repair" }, { "FLIGHT_MASTER", "flightmaster" }, { "INNKEEPER", "inn" },
    { "BANKER", "bank" }, { "AUCTIONEER", "auction" }, { "STABLEMASTER", "stable" }, { "TRAINER", "trainer" },
}



local QUESTIE_MAILBOX = "Mailbox"
local MAILBOX_KINDS = { "mailbox" }

local QUESTIE_KINDS = { "mailbox" }
for _, flag in ipairs(QUESTIE_FLAGS) do QUESTIE_KINDS[#QUESTIE_KINDS + 1] = flag[2] end



local areaMaps = { maps = nil, byArea = nil }
local function mapOfArea(area)
    local maps = FGPS.Data and FGPS.Data.maps
    if areaMaps.maps ~= maps then
        local byArea = {}
        for id, m in pairs(type(maps) == "table" and maps or {}) do
            if type(m) == "table" and type(m.areaID) == "number" and m.sys ~= 1
                and (not byArea[m.areaID] or id < byArea[m.areaID]) then
                byArea[m.areaID] = id
            end
        end
        areaMaps.maps, areaMaps.byArea = maps, byArea
    end
    return areaMaps.byArea[area]
end







local function recordStandsFor(s, kind, trainer, name, inst, x, y, code)
    return (s.kind == kind or (kind == "vendor" and s.kind == "repair")) and (kind ~= "trainer" or s.trainer == trainer)
        and s.inst == inst and factionAllowed(s.fac, code)
        and dist(s.x, s.y, x, y) <= ServiceSearch.QUESTIE_SAME_YARDS and baseName(s.name) == baseName(name)
end





local rowOfRecord = setmetatable({}, { __mode = "k" })





local NO_ROWS = {}

local function cellKey(kind, inst, cx, cy)
    return kind .. ":" .. inst .. ":" .. cx .. ":" .. cy
end

local function addToCell(cells, kind, inst, x, y, v)
    local size = ServiceSearch.QUESTIE_SAME_YARDS
    local key = cellKey(kind, inst, floor(x / size), floor(y / size))
    local cell = cells[key]
    if not cell then cell = {} cells[key] = cell end
    cell[#cell + 1] = v
end




local function namedAfterPerson(P, i)
    local src = P.src and P.src[i]
    return type(src) ~= "string" or src:find("^cmangos:creature:") ~= nil
end

local function isCreaturePOI(P, i)
    local src = P and P.src and P.src[i]
    return type(src) == "string" and src:find("^cmangos:creature:") ~= nil
end

local function personKey(kind, trainer, inst, name)
    return kind .. "|" .. (kind == "trainer" and (trainer or "") or "") .. "|" .. tostring(inst) .. "|" .. baseName(name)
end


local function knownPlaces(Yield)
    local index, P = ensureIndex(), FGPS.Data and FGPS.Data.poi
    local bundled, records, byPerson, n = {}, {}, {}, 0
    local function step()
        n = n + 1
        return n % ServiceSearch.QUESTIE_PLACES_PER_YIELD ~= 0 or Yield()
    end
    for _, kind in ipairs(P and QUESTIE_KINDS or NO_ROWS) do
        for _, i in ipairs(index[TYPE_CODES[kind][1]] or NO_ROWS) do
            addToCell(bundled, kind, P.inst[i], P.x[i], P.y[i], i)
            if isCreaturePOI(P, i) and type(P.name[i]) == "string" then
                local teaches = kind == "trainer" and ServiceSearch.TrainerKind(P.name[i]) or nil
                local pkey = personKey(kind, teaches, P.inst[i], P.name[i])
                local list = byPerson[pkey]
                if not list then list = {} byPerson[pkey] = list end
                list[#list + 1] = i
            end
            if not step() then return nil end
        end
    end
    for _, s in ipairs(learnedList()) do
        if type(s.inst) == "number" then
            addToCell(records, s.kind, s.inst, s.x, s.y, s)
            if s.kind == "repair" then addToCell(records, "vendor", s.inst, s.x, s.y, s) end
        end
        if not step() then return nil end
    end
    return {
        bundled = bundled, records = records, byPerson = byPerson,
        matchedBundled = {}, shadowedPOI = {},
    }
end








local function serviceKnownAt(known, kind, trainer, name, inst, x, y, code, fac)
    local key, near = baseName(name), ServiceSearch.QUESTIE_SAME_YARDS
    local P = FGPS.Data and FGPS.Data.poi
    local cx, cy = floor(x / near), floor(y / near)
    local shadowedRow
    for dx = -1, 1 do
        for dy = -1, 1 do
            for _, i in ipairs(P and known.bundled[cellKey(kind, inst, cx + dx, cy + dy)] or NO_ROWS) do
                if dist(P.x[i], P.y[i], x, y) <= near and (not namedAfterPerson(P, i) or baseName(P.name[i]) == key)
                    and (kind ~= "trainer" or ServiceSearch.TrainerKind(P.name[i]) == trainer) then
                    known.matchedBundled[i] = true
                    if factionAllowed(P.fac[i], code) then
                        return true
                    elseif fac == 0 and (P.fac[i] == 1 or P.fac[i] == 2) and isCreaturePOI(P, i) then
                        known.shadowedPOI[i] = true
                        shadowedRow = shadowedRow or i
                    end
                end
            end
        end
    end
    for dx = -1, 1 do
        for dy = -1, 1 do
            for _, s in ipairs(known.records[cellKey(kind, inst, cx + dx, cy + dy)] or NO_ROWS) do
                if recordStandsFor(s, kind, trainer, name, inst, x, y, code) then return true, s, shadowedRow end
            end
        end
    end
    return false, nil, shadowedRow
end


local function shadowQuestie(entry)
    local q = ServiceSearch.questie
    if #q.rows == 0 then return end
    local code, kept = playerFactionCode(), {}
    for _, row in ipairs(q.rows) do
        if recordStandsFor(entry, row.kind, row.trainer, row.name, row.inst, row.x, row.y, code) then
            rowOfRecord[entry] = row
        else
            kept[#kept + 1] = row
        end
    end
    if #kept ~= #q.rows then q.rows, q.rev = kept, q.rev + 1 end
end



local function readField(Npc, id, key)
    local ok, v = pcall(Npc.Get, id, key)
    if ok then return v end
    return nil
end
ServiceSearch.QuestieRead = readField



function ServiceSearch.QuestieLib()
    if type(LibQuestieDB) ~= "table" then return nil, "absent" end
    local lib = LibQuestieDB
    local ok, fits = pcall(lib.RequireContract, ServiceSearch.QUESTIE_CONTRACT)
    if not ok or fits ~= true then return nil, "contract" end
    return lib
end


local function middleSpot(group)
    local best, bestSum
    for i = 1, #group do
        local sum = 0
        for j = 1, #group do sum = sum + dist(group[i].x, group[i].y, group[j].x, group[j].y) end
        if not bestSum or sum < bestSum then best, bestSum = group[i], sum end
    end
    return best
end




function ServiceSearch.QuestieSpots(spawns)
    local out = {}
    if type(spawns) ~= "table" then return out end
    local areas = {}
    for area in pairs(spawns) do
        if type(area) == "number" then areas[#areas + 1] = area end
    end
    table.sort(areas)
    local Coords = FGPS.Coords
    for _, area in ipairs(areas) do
        local map, spots = mapOfArea(area), spawns[area]
        for _, spot in ipairs(map and type(spots) == "table" and spots or {}) do
            local sx, sy = type(spot) == "table" and spot[1], type(spot) == "table" and spot[2]
            if type(sx) == "number" and type(sy) == "number" and sx >= 0 and sx <= 100 and sy >= 0 and sy <= 100 then
                local inst, x, y = Coords.MapToWorld(map, sx / 100, sy / 100)
                if inst then out[#out + 1] = { inst = inst, x = x, y = y, map = map } end
            end
        end
    end
    return out
end





function ServiceSearch.QuestieGroups(spots)
    local groups = {}
    for _, spot in ipairs(spots) do
        local group
        for _, g in ipairs(groups) do
            if g.inst == spot.inst and dist(g[1].x, g[1].y, spot.x, spot.y) <= ServiceSearch.QUESTIE_SAME_YARDS then group = g break end
        end
        if not group then
            group = { inst = spot.inst }
            groups[#groups + 1] = group
        end
        group[#group + 1] = { x = spot.x, y = spot.y, map = spot.map }
    end
    for _, group in ipairs(groups) do group.middle = middleSpot(group) end
    return groups
end









local function placeRows(field, id, name, sub, fac, spawns, kinds, trainer, code, out, known)
    for _, group in ipairs(ServiceSearch.QuestieGroups(ServiceSearch.QuestieSpots(spawns))) do
        local spot = group.middle
        for _, kind in ipairs(kinds) do
            local teaches = kind == "trainer" and trainer or nil
            local isKnown, record, shadowedRow = serviceKnownAt(known, kind, teaches, name, group.inst, spot.x, spot.y, code, fac)
            if not isKnown or record then
                local row = { kind = kind, trainer = teaches, name = name, sub = sub, inst = group.inst,
                              x = floor(spot.x * 10 + 0.5) / 10, y = floor(spot.y * 10 + 0.5) / 10, map = spot.map, fac = fac,
                              source = "questie", spots = #group > 1 and group or nil, replacesPOI = shadowedRow }
                row[field] = id
                if record then rowOfRecord[record] = row else out[#out + 1] = row end
            end
        end
    end
end





local function questieRows(Npc, id, kinds, class, code, out, state, known)
    local name = readField(Npc, id, "name")
    local sub = readField(Npc, id, "subName")
    if type(sub) ~= "string" or sub == "" then sub = nil end
    if seasonal(name, sub) then
        state.seasonal = state.seasonal + 1
        return
    end
    local trainer = nil
    for _, kind in ipairs(kinds) do
        if kind == "trainer" then trainer = ServiceSearch.TrainerKind(sub) end
    end
    if trainer and trainer == class then state.classTrainers = state.classTrainers + 1 end
    local fac = QUESTIE_SIDES[readField(Npc, id, "friendlyToFaction")]
    if type(name) ~= "string" or name == "" or not fac or not factionAllowed(fac, code) then return end
    local spawns = readField(Npc, id, "spawns")
    if type(spawns) ~= "table" then return end
    placeRows("npc", id, name, sub, fac, spawns, kinds, trainer, code, out, known)
end



local function questieMailboxes(lib, code, out, state, known, Yield)
    local Object = lib.Object
    if type(Object) ~= "table" or type(Object.Get) ~= "function" or type(Object.GetAllIds) ~= "function" then return nil end
    local ok, ids = pcall(Object.GetAllIds)
    if not ok or type(ids) ~= "table" then return nil end
    for i = 1, #ids do
        local id = ids[i]
        if readField(Object, id, "name") == QUESTIE_MAILBOX then
            state.mailboxes = state.mailboxes + 1
            state.read.mailbox = (state.read.mailbox or 0) + 1
            local spawns = readField(Object, id, "spawns")
            if type(spawns) == "table" then
                placeRows("object", id, QUESTIE_MAILBOX, nil, 0, spawns, MAILBOX_KINDS, nil, code, out, known)
            end
        end
        state.objects = i
        if i % ServiceSearch.QUESTIE_ROWS_PER_YIELD == 0 and not Yield() then return "cancelled" end
    end
    return nil
end








local function questiePlace(row)
    if row.placeRead or type(row.spots) ~= "table" then return end
    local G = FGPS.Graph
    if not (G and G.NearestKey and G.NodePlace and G.IsSurfaceNode and G.IsLoaded and G:IsLoaded(row.inst)) then return end
    row.placeRead = true
    local function onSurface(key) return G:IsSurfaceNode(key) end
    local votes, indoors, best = {}, {}, nil
    for _, spot in ipairs(row.spots) do
        local name, indoor, stacked = G:NodePlace(G:NearestKey(row.inst, spot.x, spot.y, G.SURFACE_ATTACH_RADIUS, onSurface))
        if name and stacked then
            votes[name] = (votes[name] or 0) + 1
            if indoor then indoors[name] = (indoors[name] or 0) + 1 end
            if not best or votes[name] > votes[best] then best = name end
        end
    end
    local n = best and votes[best] or 0
    if n * 2 > #row.spots then row.place = { indoor = (indoors[best] or 0) * 2 > n, name = best } end
end


local function scanQuestie(state)
    local lib, why = ServiceSearch.QuestieLib()
    if not lib then return why end
    local Npc, flags = lib.Npc, type(lib.Enum) == "table" and lib.Enum.npcFlags or nil
    local offered = {}
    for _, flag in ipairs(QUESTIE_FLAGS) do
        local bit = type(flags) == "table" and flags[flag[1]] or nil
        if type(bit) == "number" and bit >= 1 then offered[#offered + 1] = { bit = bit, kind = flag[2] } end
    end
    if type(Npc) ~= "table" or type(Npc.Get) ~= "function" or type(Npc.GetAllIds) ~= "function" or #offered == 0 then
        return "api"
    end
    local loc = clientLocale()
    if loc and not QUESTIE_ENGLISH[loc] then return "locale" end
    local okIds, ids = pcall(Npc.GetAllIds)
    if not okIds or type(ids) ~= "table" then return "api" end
    local class, code = ServiceSearch.PlayerClass(), playerFactionCode()
    local Yield, rows = FGPS.Scheduler.Yield, {}

    local known = knownPlaces(Yield)
    if not known then return "cancelled" end
    for i = 1, #ids do
        local id = ids[i]
        local f = readField(Npc, id, "npcFlags")
        local kinds
        if type(f) == "number" and f > 0 then
            for _, flag in ipairs(offered) do

                if floor(f / flag.bit) % 2 == 1 then
                    kinds = kinds or {}
                    kinds[#kinds + 1] = flag.kind
                    state.read[flag.kind] = (state.read[flag.kind] or 0) + 1
                    if flag.kind == "trainer" then state.trainers = state.trainers + 1 end
                end
            end
        end
        state.scanned = i
        if kinds then
            state.services = state.services + 1
            questieRows(Npc, id, kinds, class, code, rows, state, known)


            if not Yield() then return "cancelled" end
        elseif i % ServiceSearch.QUESTIE_ROWS_PER_YIELD == 0 and not Yield() then
            return "cancelled"
        end
    end
    local stopped = questieMailboxes(lib, code, rows, state, known, Yield)
    if stopped then return stopped end
    for _, row in ipairs(rows) do
        if row.npc then
            local pkey = personKey(row.kind, row.trainer, row.inst, row.name)
            for _, poiIndex in ipairs(known.byPerson[pkey] or NO_ROWS) do
                if not known.matchedBundled[poiIndex] then
                    known.shadowedPOI[poiIndex] = true
                    row.replacesPOI = row.replacesPOI or poiIndex
                end
            end
        end
    end
    state.rows = rows
    state.shadowedPOI = known.shadowedPOI
    return "done"
end



function ServiceSearch.ReadQuestie()
    local q = ServiceSearch.questie
    local Scheduler = FGPS.Scheduler
    if q.state ~= nil or not (Scheduler and Scheduler.Run) then return false end
    q.state = "running"

    local state = { scanned = 0, services = 0, seasonal = 0, trainers = 0, classTrainers = 0, objects = 0, mailboxes = 0,
                    read = {} }
    q.stats = state

    local started = time and time() or 0
    q.task = Scheduler:Run(function() return scanQuestie(state) end, {
        label = "questie", budgetMs = ServiceSearch.QUESTIE_SLICE_MS,
        onDone = function(ok, answer)
            local task = q.task
            q.task = nil
            state.ms, state.slices = task and task.elapsedMs, task and task.slices
            q.state = ok and type(answer) == "string" and answer or "failed"
            areaMaps.maps, areaMaps.byArea = nil, nil
            if q.state == "done" then
                q.rows, state.rows = state.rows or {}, nil
                q.shadowedPOI, state.shadowedPOI = state.shadowedPOI or {}, nil
                q.shadowedForRows = q.rows
                inDataIndex = nil
                q.rev = q.rev + 1
                if next(q.shadowedPOI) ~= nil then
                    local D = FGPS.Destinations
                    if D and D.InvalidateIndex then D.InvalidateIndex() end
                    local MP = FGPS.UI and FGPS.UI.MapPlaces
                    if MP and MP.InvalidateCache then MP.InvalidateCache() end
                end
                for _, s in ipairs(learnedList()) do
                    if (tonumber(s.time) or 0) >= started then shadowQuestie(s) end
                end
                FGPS.Log:Info("Questie: %d place(s) kept of %d NPC(s) with a service (%d NPCs read) and %d of %d objects "
                    .. "named Mailbox in %.1f ms", #q.rows, state.services, state.scanned, state.mailboxes, state.objects, state.ms or 0)
            elseif QUESTIE_WHY[q.state] then
                FGPS.Log:Info("Questie: no services read: %s", QUESTIE_WHY[q.state])
            end
        end,
    })
    return true
end



function ServiceSearch.OnWorldEntered()
    local q = ServiceSearch.questie
    if q.state ~= nil or q.waiting then return end
    if type(LibQuestieDB) ~= "table" then
        q.state = "absent"
        FGPS.Log:Info("Questie: no services read: %s", QUESTIE_WHY.absent)
        return
    end
    if not (C_Timer and C_Timer.After) then
        ServiceSearch.ReadQuestie()
        return
    end
    q.waiting = true
    C_Timer.After(ServiceSearch.QUESTIE_DELAY, function()
        q.waiting = nil
        ServiceSearch.ReadQuestie()
    end)
end


function ServiceSearch.QuestieRows()
    return ServiceSearch.questie.rows, ServiceSearch.questie.rev
end




function ServiceSearch.Learned()
    return learnedList()
end

local function placeCopy(p)
    if type(p) ~= "table" then return nil end
    local indoor, name = p.indoor, p.name
    if type(indoor) ~= "boolean" then indoor = nil end
    if type(name) ~= "string" or name == "" then name = nil end
    if indoor == nil and name == nil then return nil end
    return { indoor = indoor, name = name }
end







function ServiceSearch.EntryPlace(s)
    if type(s) ~= "table" then return nil end
    if s.source == "questie" then questiePlace(s) end
    local p = placeCopy(s.place)
    local row = not p and rowOfRecord[s]
    if row then
        questiePlace(row)
        p = placeCopy(row.place)
    end
    return p
end














function ServiceSearch.Remember(kind, name, pos, trainer, place)
    if type(kind) ~= "string" or not TYPE_SET[kind] then return nil, "bad_kind" end
    if kind ~= "trainer" or type(trainer) ~= "string" or trainer == "" then trainer = nil end
    place = ServiceSearch.EntryPlace({ place = place })
    pos = pos or playerPos()
    if not pos or not pos.inst or not pos.x or not pos.y then return nil, "no_position" end
    name = Util.Trim(tostring(name or ""))
    if name == "" then name = L[kind:sub(1, 1):upper() .. kind:sub(2)] end
    local list = learnedList()
    local stamp = time and time() or 0
    local loc, fac = clientLocale(), playerFactionCode()
    if fac == 3 then fac = 0 end
    local same, other, otherD
    local near = kind == "dummy" and ServiceSearch.DUMMY_SAME_YARDS or ServiceSearch.DEDUPE_YARDS
    for i = 1, #list do
        local s = list[i]
        local d = s.kind == kind and s.inst == pos.inst and dist(s.x, s.y, pos.x, pos.y)
        if d and d <= near then
            if s.name == name then same = s break end
            if loc and s.loc and s.loc ~= loc and (not otherD or d < otherD) then other, otherD = s, d end
        end
    end
    same = same or other
    if same then
        local changed = same.name ~= name
        same.name, same.loc = name, loc or same.loc
        if fac ~= 0 and (same.fac or 0) ~= 0 and same.fac ~= fac then same.fac, changed = 0, true end


        if trainer and same.trainer ~= trainer and (trainer ~= "other" or same.trainer == nil) then
            same.trainer, changed = trainer, true
        end
        same.place = place or same.place
        same.time = stamp
        same.seen = (same.seen or 1) + 1
        shadowQuestie(same)
        if changed then Events:Fire("LEARNED_SERVICES_CHANGED", same) end
        return same, false
    end
    local entry = {
        kind = kind, name = name, inst = pos.inst, x = floor(pos.x * 10 + 0.5) / 10, y = floor(pos.y * 10 + 0.5) / 10,
        map = pos.map, fac = fac, loc = loc, time = stamp, seen = 1, trainer = trainer, place = place,
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
    shadowQuestie(entry)
    Events:Fire("LEARNED_SERVICES_CHANGED", entry)
    return entry, true
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
    return { kind = "service", name = ServiceSearch.EntryName(s), inst = s.inst, x = s.x, y = s.y, map = s.map, mx = mx, my = my,
             type = s.kind, serviceKind = s.kind, zoneName = zoneName, faction = (s.fac ~= 0) and s.fac or nil,
             learned = true, learnedIndex = i, place = ServiceSearch.EntryPlace(s) }
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
                if not ServiceSearch.IsShadowedPOI(i) and P.inst[i] == pos.inst and factionAllowed(P.fac[i], code)
                    and (sub == nil or ServiceSearch.TrainerKind(P.name[i]) == sub) then
                    local d = dist(P.x[i], P.y[i], pos.x, pos.y)
                    if d <= maxStraight then out[#out + 1] = { poiIndex = i, straightYards = d } end
                end
            end
        end
    end
    for i, s in ipairs(learnedList()) do



        local matches
        if sub == nil then
            matches = s.kind == serviceType or (serviceType == "vendor" and s.kind == "repair")
        else
            matches = s.kind == serviceType and s.trainer == sub
        end
        if matches and s.inst == pos.inst and s.x and s.y and factionAllowed(s.fac, code) then
            local d = dist(s.x, s.y, pos.x, pos.y)
            if d <= maxStraight and not ServiceSearch.InData(s, code) then
                out[#out + 1] = { learned = s, learnedIndex = i, straightYards = d }
            end
        end
    end



    for _, s in ipairs(ServiceSearch.questie.rows) do
        if s.kind == serviceType and (sub == nil or s.trainer == sub) and s.inst == pos.inst and factionAllowed(s.fac, code) then
            local d = dist(s.x, s.y, pos.x, pos.y)
            if d <= maxStraight then out[#out + 1] = { learned = s, questie = true, straightYards = d } end
        end
    end
    table.sort(out, function(a, b) return a.straightYards < b.straightYards end)
    while maxCount and #out > maxCount do out[#out] = nil end
    return out
end





function ServiceSearch.GuardedLeftOut(guarded, inst, x, y, ownFac)
    local Cost = FGPS.Cost
    if not guarded or not (Cost and Cost.GuardedAt) then return false end
    local code = playerFactionCode()
    if ownFac and code ~= 3 and ownFac == code then return false end
    return Cost.GuardedAt(guarded, inst, x, y) ~= nil
end




function ServiceSearch.GuardedIndexAt(access, pos)
    local Cost = FGPS.Cost
    local guarded = Cost and Cost.GuardedIndex and Cost.GuardedIndex(access)
    if not guarded or not (pos and pos.inst and Cost.GuardedHold and Cost.GuardedExcept) then return guarded end
    local held = {}
    Cost.GuardedHold(guarded, pos.inst, pos.x, pos.y, held)
    return Cost.GuardedExcept(guarded, held)
end







function ServiceSearch.OutsideGuarded(candidates, access, pos)
    local guarded = ServiceSearch.GuardedIndexAt(access, pos)
    if not guarded then return candidates end
    local P = FGPS.Data and FGPS.Data.poi
    local outside = {}
    for _, c in ipairs(candidates) do
        local s = c.learned
        local inst, x, y, fac
        if s then
            inst, x, y, fac = s.inst, s.x, s.y, c.questie and s.fac or nil
        elseif P and c.poiIndex then
            inst, x, y, fac = P.inst[c.poiIndex], P.x[c.poiIndex], P.y[c.poiIndex], P.fac[c.poiIndex]
        end
        if not ServiceSearch.GuardedLeftOut(guarded, inst, x, y, fac) then outside[#outside + 1] = c end
    end
    if #outside == 0 then return candidates, false end
    return outside, true
end



function ServiceSearch.AnyOutsideGuarded(serviceType, access)
    local pos = playerPos()
    if not pos or not pos.inst then return false end
    local _, any = ServiceSearch.OutsideGuarded(ServiceSearch.Candidates(serviceType, pos, ServiceSearch.DEFAULT_MAX_STRAIGHT), access, pos)
    return any == true
end





function ServiceSearch.TrainerKinds(pos, maxStraight)
    pos = pos or playerPos()
    maxStraight = maxStraight or ServiceSearch.DEFAULT_MAX_STRAIGHT
    local byKind, list = {}, {}
    for _, c in ipairs(ServiceSearch.Candidates("trainer", pos, maxStraight)) do
        local kind
        if c.poiIndex then
            kind = ServiceSearch.TrainerKind(FGPS.Data.poi.name[c.poiIndex])
        elseif c.learned and type(c.learned.trainer) == "string" then
            kind = c.learned.trainer
        end
        if kind then
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
    local stops, otherwise = {}, {}
    for i, e in ipairs(entries) do stops[i], otherwise[i] = e.dest, straightSeconds(e) end


    local request = { origin = pos, stops = stops, access = access, variant = "fastest", reason = "service", service = search.serviceType,
                      goalLimit = search.limit, goalOtherwise = otherwise }
    local delivered = false
    local ok, handle = pcall(Router.RequestGoals, Router, request, function(route, routeErr)
        delivered = true
        search.handle = nil
        if search.cancelled or search.done then return end
        local results = route and route.results
        if results then
            for i, e in ipairs(entries) do
                local one = results[i]
                local cut = route.cut and route.cut[i]
                if one and type(one.totalSeconds) == "number" then
                    e.route, e.seconds, e.yards = one, one.totalSeconds, one.totalYards
                    e.straight = one.fallback == "straight"
                elseif cut then

                    local s = straightSeconds(e)
                    e.straight, e.seconds, e.bounded = true, (s > cut) and s or cut, true
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



    ServiceSearch.Cancel()
    if not resolveType(serviceType) then callback({}, "bad_type") return false end
    local pos = playerPos()
    if not pos or not pos.inst then callback({}, "no_position") return false end
    local limit = opts.limit or ServiceSearch.DEFAULT_LIMIT
    local maxStraight = opts.maxStraightYards or ServiceSearch.DEFAULT_MAX_STRAIGHT
    local access = opts.access
    if not access and FGPS.Access and FGPS.Access.Snapshot then
        local ok, snap = pcall(FGPS.Access.Snapshot, FGPS.Access)
        if ok then access = snap end
    end
    local candidates = ServiceSearch.OutsideGuarded(ServiceSearch.Candidates(serviceType, pos, maxStraight), access, pos)
    while #candidates > ServiceSearch.MAX_CANDIDATES do candidates[#candidates] = nil end
    if #candidates == 0 then callback({}, "none") return true end
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



    local base, sub = resolveType(serviceType)
    local named = (sub and (TRAINER_TITLES[sub] or sub == "weapons" or sub == "portal")) and serviceType or base
    local search = { cancelled = false, done = false, handle = nil, serviceType = named, limit = limit }
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
        local request = { origin = pos, stops = { e.dest }, access = access, variant = "fastest", reason = "service", service = named,
                          maxSeconds = currentBound() }
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






ServiceSearch.SUMMONED_MERCHANTS = { [14337] = true }

local function summonedMerchant()
    if not UnitGUID then return false end
    local ok, guid = pcall(UnitGUID, "npc")
    if not ok or type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then return false end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    return (kind == "Creature" or kind == "Vehicle") and ServiceSearch.SUMMONED_MERCHANTS[tonumber(id)] == true
end

function ServiceSearch.OnMerchantShow()
    if summonedMerchant() then return nil, "summoned" end
    local repair = false
    if CanMerchantRepair then
        local ok, v = pcall(CanMerchantRepair)
        repair = ok and v and true or false
    end
    return ServiceSearch.Remember(repair and "repair" or "vendor", npcName(L[repair and "Repair vendor" or "Vendor"]))
end

function ServiceSearch.OnGossipShow()

    ServiceSearch.gossipOpen, ServiceSearch.gossipAt = true, GetTime and GetTime() or 0
    if not (C_GossipInfo and C_GossipInfo.GetOptions) then return nil end
    local ok, options = pcall(C_GossipInfo.GetOptions)
    if not ok or type(options) ~= "table" then return nil end
    for _, opt in ipairs(options) do
        if isInnkeeperOption(opt) then return ServiceSearch.Remember("inn", npcName(L["Innkeeper"])) end
    end
    return nil
end


ServiceSearch.MAX_TRAINER_SERVICES = 60

local PROFESSION_SET = {}
for _, key in ipairs(ServiceSearch.TRAINER_PROFESSIONS) do PROFESSION_SET[key] = true end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil
end










function ServiceSearch.WindowTrainerKind()
    local types = type(Enum) == "table" and type(Enum.TrainerType) == "table" and Enum.TrainerType or {}
    local trainerType = C_Trainer and call(C_Trainer.GetTrainerType) or nil
    if call(IsTradeskillTrainer) or trainerType == (types.Tradeskills or 2) then
        local count = tonumber(call(GetNumTrainerServices)) or 0
        for i = 1, math.min(count, ServiceSearch.MAX_TRAINER_SERVICES) do
            local line = call(GetTrainerServiceSkillLine, i)
            local kind = type(line) == "string" and ServiceSearch.TrainerKind(line) or nil
            if PROFESSION_SET[kind] then return kind end
        end
        return "other"
    end
    if trainerType == (types.Pet or 3) then return "pet" end
    if trainerType == (types.TalentsObsolete or 1) then return "riding" end
    if trainerType == (types.General or 0) then return ServiceSearch.PlayerClass() or "other" end
    return "other"
end





local function playerPlace(inst)
    local C, G = FGPS.Coords, FGPS.Graph
    if not (C and C.PlayerPlace) then return nil end
    local ok, got = pcall(C.PlayerPlace)
    if not ok or type(got) ~= "table" then return nil end
    local name = got.name
    if type(name) == "string" and inst ~= nil and G and G.RoomKey and not (G.IsLoaded and not G:IsLoaded(inst)) then
        name = G:RoomKey(inst, name) or name
    end
    return { indoor = got.indoor, name = name }
end



function ServiceSearch.OnTrainerShow()
    local pos = playerPos()
    return ServiceSearch.Remember("trainer", npcName(L["Trainer"]), pos, ServiceSearch.WindowTrainerKind(),
        pos and playerPlace(pos.inst))
end






ServiceSearch.TRAINER_ROUTE_RING = 10
ServiceSearch.trainerRoutes = {}

function ServiceSearch.NoteTrainerRoute(route)
    if type(route) ~= "table" or type(route.stops) ~= "table" or type(route.legs) ~= "table" then return end
    local ring = ServiceSearch.trainerRoutes
    for _, stop in ipairs(route.stops) do
        local dest = type(stop) == "table" and stop.dest
        local leg = type(dest) == "table" and (dest.serviceKind == "trainer" or dest.type == "trainer") and route.legs[stop.legTo]
        if type(leg) == "table" then
            local last
            for _, pt in ipairs(type(leg.points) == "table" and leg.points or {}) do
                if type(pt) == "table" and type(pt.z) == "number" then last = pt end
            end
            local place = type(dest.place) == "table" and dest.place or {}
            ring[#ring + 1] = { name = dest.name, told = place.name, toldIndoor = place.indoor, z = last and floor(last.z + 0.5),
                                room = last and last.room, indoor = last and last.indoor, stacked = last and last.stacked }
            while #ring > ServiceSearch.TRAINER_ROUTE_RING do table.remove(ring, 1) end
        end
    end
end















ServiceSearch.GUARD_SECONDS = 30
ServiceSearch.GUARD_MAP_STEPS = 6
ServiceSearch.GUARD_SAME_YARDS = 5
ServiceSearch.guardOffer = nil
ServiceSearch.gossipOpen = false
ServiceSearch.gossipAt = nil

ServiceSearch.guardStats = { offered = 0, taken = 0 }

local function plainValue(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end


local function parentMap(uiMapID)
    local info = C_Map and call(C_Map.GetMapInfo, uiMapID)
    if type(info) ~= "table" or type(info.mapType) ~= "number" or info.mapType <= 2 then return nil end
    local parent = info.parentMapID
    if type(parent) ~= "number" or parent == 0 then return nil end
    return parent
end



function ServiceSearch.GuardPoint()
    local api = C_GossipInfo
    if not (api and api.GetPoiForUiMapID and api.GetPoiInfo) then return nil end
    local pos = playerPos()
    local map = pos and pos.map
    if not map and C_Map then map = call(C_Map.GetBestMapForUnit, "player") end
    for _ = 1, ServiceSearch.GUARD_MAP_STEPS do
        if type(map) ~= "number" then return nil end
        local id = plainValue(call(api.GetPoiForUiMapID, map))
        local info = type(id) == "number" and call(api.GetPoiInfo, map, id) or nil
        local where = type(info) == "table" and info.position or nil
        if type(where) == "table" then
            local mx, my, name = plainValue(where.x), plainValue(where.y), plainValue(info.name)
            if type(mx) == "number" and type(my) == "number" then
                return map, mx, my, (type(name) == "string" and name ~= "") and name or nil
            end
        end
        map = parentMap(map)
    end
    return nil
end

local function hideGuardOffer()
    local had = ServiceSearch.guardOffer ~= nil
    ServiceSearch.guardOffer = nil
    local Question = FGPS.UI and FGPS.UI.Question
    if had and Question and Question.Close then Question.Close("guard") end
end


local function guardDest(map, mx, my, name)
    local Coords = FGPS.Coords
    local inst, x, y
    if Coords and Coords.MapToWorld then inst, x, y = Coords.MapToWorld(map, mx, my) end
    if not inst then return nil end
    local D = FGPS.Destinations
    return { kind = "custom", type = "custom", name = name or L["The spot the guard marked"], inst = inst,
             x = floor(x * 10 + 0.5) / 10, y = floor(y * 10 + 0.5) / 10, map = map, mx = mx, my = my,
             zoneName = D and D.MapName and D.MapName(map) or nil }
end


function ServiceSearch.OnGossipPoi()
    local map, mx, my, name = ServiceSearch.GuardPoint()
    if not map then
        hideGuardOffer()
        return nil
    end
    local asked = ServiceSearch.gossipAt
    if not ServiceSearch.gossipOpen
        and (not asked or (GetTime and GetTime() or 0) - asked > ServiceSearch.GUARD_SECONDS) then
        return nil
    end
    local dest = guardDest(map, mx, my, name)
    if not dest then return nil end
    local before = ServiceSearch.guardOffer
    if before and before.dest.name == dest.name and before.dest.inst == dest.inst
        and dist(before.dest.x, before.dest.y, dest.x, dest.y) <= ServiceSearch.GUARD_SAME_YARDS then
        return nil
    end
    hideGuardOffer()
    local Question = FGPS.UI and FGPS.UI.Question
    if not (Question and Question.Ask) then return nil end
    local offer = { dest = dest }
    ServiceSearch.guardOffer = offer

    local function over()
        if ServiceSearch.guardOffer == offer then ServiceSearch.guardOffer = nil end
    end
    local shown = Question.Ask({
        id = "guard",
        text = string.format(L["Want me to take you to %s?"], name or L["the spot the guard marked"]),
        buttons = {
            { label = L["Take Me There"], answer = "taken", onClick = function() ServiceSearch.AcceptGuardOffer() end },
            { label = L["No Thanks"], answer = "declined", onClick = over },
        },
        onClose = over,
    })
    if not shown then
        over()
        return nil
    end
    ServiceSearch.guardStats.offered = ServiceSearch.guardStats.offered + 1
    return offer
end



function ServiceSearch.AcceptGuardOffer()
    local offer = ServiceSearch.guardOffer
    ServiceSearch.guardOffer = nil
    local Nav = FGPS.Navigator
    if not (offer and Nav and Nav.SetDestination) then return false end
    local set = Nav:SetDestination(offer.dest, { start = true, quiet = true }) ~= nil
    if set then ServiceSearch.guardStats.taken = ServiceSearch.guardStats.taken + 1 end
    return set
end





















ServiceSearch.DUMMY_RANGE_INDEX = 3
ServiceSearch.DUMMY_SAME_YARDS = 40
ServiceSearch.SUMMONED_DUMMIES = { [2673] = true, [2674] = true, [12426] = true }
ServiceSearch.DUMMY_PLACE_RING = 10


ServiceSearch.dummyStats = { learned = 0, again = 0, skipped = {}, places = {} }
ServiceSearch.dummyTargetDone = nil

local function dummySkipped(why)
    local skipped = ServiceSearch.dummyStats.skipped
    skipped[why] = (skipped[why] or 0) + 1
    return nil, why
end





function ServiceSearch.OnDummyTarget(stopped)
    if not (UnitExists and UnitName) or not plainValue(call(UnitExists, "target")) then return nil, "no_target" end
    local name = plainValue(call(UnitName, "target"))
    if type(name) ~= "string" or not Util.Lower(name):find("dummy", 1, true) then return nil, "not_a_dummy" end
    local guid = UnitGUID and plainValue(call(UnitGUID, "target")) or nil
    if type(guid) ~= "string" then guid = nil end
    if stopped and (guid or true) == ServiceSearch.dummyTargetDone then return nil, "done" end
    if InCombatLockdown and InCombatLockdown() then return dummySkipped("combat") end
    if not (UnitCanAttack and CheckInteractDistance) then return dummySkipped("no_api") end
    if UnitIsPlayer and plainValue(call(UnitIsPlayer, "target")) then return dummySkipped("player") end
    if UnitPlayerControlled and plainValue(call(UnitPlayerControlled, "target")) then return dummySkipped("controlled") end
    local unitKind, id = (guid or ""):match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if unitKind and unitKind ~= "Creature" then return dummySkipped("controlled") end
    if ServiceSearch.SUMMONED_DUMMIES[tonumber(id)] then return dummySkipped("summoned") end
    if plainValue(call(UnitCanAttack, "player", "target")) ~= true then return dummySkipped("not_attackable") end
    if plainValue(call(CheckInteractDistance, "target", ServiceSearch.DUMMY_RANGE_INDEX)) ~= true then
        return dummySkipped("too_far")
    end
    local pos = playerPos()
    if not pos then return dummySkipped("no_position") end
    local entry, new = ServiceSearch.Remember("dummy", name, pos, nil, playerPlace(pos.inst))
    if not entry then return dummySkipped(new or "not_recorded") end
    ServiceSearch.dummyTargetDone = guid or true
    local stats = ServiceSearch.dummyStats
    if new then stats.learned = stats.learned + 1 else stats.again = stats.again + 1 end
    local ring = stats.places
    ring[#ring + 1] = { name = entry.name, inst = entry.inst, x = entry.x, y = entry.y, new = new }
    while #ring > ServiceSearch.DUMMY_PLACE_RING do table.remove(ring, 1) end
    return entry, new
end

function ServiceSearch:Init()
    if self.initialised then return end
    self.initialised = true
    Events:RegisterWoW("MERCHANT_SHOW", function() ServiceSearch.OnMerchantShow() end, self)
    Events:RegisterWoW("GOSSIP_SHOW", function() ServiceSearch.OnGossipShow() end, self)
    Events:RegisterWoW("GOSSIP_CLOSED", function()
        ServiceSearch.gossipOpen, ServiceSearch.gossipAt = false, GetTime and GetTime() or 0
    end, self)
    Events:RegisterWoW("MAIL_SHOW", function() ServiceSearch.Remember("mailbox", L["Mailbox"]) end, self)
    Events:RegisterWoW("BANKFRAME_OPENED", function() ServiceSearch.Remember("bank", npcName(L["Bank"])) end, self)
    Events:RegisterWoW("TAXIMAP_OPENED", function() ServiceSearch.Remember("flightmaster", npcName(L["Flight master"])) end, self)
    Events:RegisterWoW("TRAINER_SHOW", function() ServiceSearch.OnTrainerShow() end, self)
    Events:RegisterWoW("DYNAMIC_GOSSIP_POI_UPDATED", function() ServiceSearch.OnGossipPoi() end, self)
    Events:RegisterWoW("PLAYER_TARGET_CHANGED", function()
        ServiceSearch.dummyTargetDone = nil
        ServiceSearch.OnDummyTarget(false)
    end, self)
    Events:RegisterWoW("PLAYER_STOPPED_MOVING", function() ServiceSearch.OnDummyTarget(true) end, self)


    Events:Register("ROUTE_STARTED", function(_, route)
        ServiceSearch.Cancel()
        ServiceSearch.NoteTrainerRoute(route)
    end, self)
    Events:Register("NAV_RECALC_START", function() ServiceSearch.Cancel() end, self)
    Events:Register("WORLD_ENTERED", function() ServiceSearch.OnWorldEntered() end, self)
end
