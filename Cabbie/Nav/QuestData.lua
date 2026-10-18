


























local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local floor, sqrt = math.floor, math.sqrt
local type, ipairs, pairs, tonumber, tostring, format = type, ipairs, pairs, tonumber, tostring, string.format

local QuestData = {



    LOOKUP_SESSION_BUDGET = 60,
    LOOKUP_MIN_SECONDS = 2,
    SWEEP_CHUNK = 100,
    SEARCH_LIMIT = 100,
    initialised = false,
    available = false,

    lookups = { used = 0, inFlight = nil, lastAt = -1e9, failed = 0, refused = {} },
    stats = { titlesLearned = 0, lookupsSpent = 0 },
}
FGPS.QuestData = QuestData



local KIND_KILL, KIND_INTERACT, KIND_COLLECT, KIND_CAST, KIND_EXPLORE = 1, 2, 3, 4, 5
local KIND_FALLBACK = { [KIND_KILL] = "kill", [KIND_INTERACT] = "interact", [KIND_COLLECT] = "collect",
                        [KIND_CAST] = "cast", [KIND_EXPLORE] = "explore" }




local RACE_BIT = { Human = 1, Orc = 2, Dwarf = 4, NightElf = 8, Scourge = 16, Undead = 16,
                   Tauren = 32, Gnome = 64, Troll = 128 }
local CLASS_BIT = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64,
                    MAGE = 128, WARLOCK = 256, DRUID = 1024 }



QuestData.FAR_ABOVE_LEVELS = 5

local function now() return GetTime and GetTime() or 0 end


local function hasBit(mask, bit)
    mask = tonumber(mask) or 0
    if mask <= 0 then return false end
    return floor(mask / bit) % 2 == 1
end
QuestData.HasBit = hasBit






local function dataset()
    local D = FGPS.Data
    if not D then return nil end
    local quests, givers = D.quests, D.questGivers
    if type(quests) ~= "table" or type(givers) ~= "table" then return nil end
    if type(quests.id) ~= "table" or type(quests.n) ~= "number" or quests.n <= 0 then return nil end
    if type(givers.inst) ~= "table" or type(givers.n) ~= "number" or givers.n <= 0 then return nil end
    return quests, givers, (type(D.questAreas) == "table" and D.questAreas or nil),
           (type(D.questIndex) == "table" and D.questIndex or nil),
           (type(D.questsForever) == "table" and D.questsForever or nil)
end
QuestData.Dataset = dataset

function QuestData.Available()
    return dataset() ~= nil
end



function QuestData.Stats()
    local quests, givers, areas, index, forever = dataset()
    local out = {
        available = quests ~= nil,
        shipped = quests and quests.n or 0,
        positions = givers and givers.n or 0,
        objectives = quests and quests.no or 0,
        foreverRows = forever and forever.n or 0,
        titlesKnown = QuestData.KnownTitleCount(),
        lookupsUsed = QuestData.lookups.used,
        lookupBudget = QuestData.LOOKUP_SESSION_BUDGET,
    }
    local n = 0
    if areas then
        for _, table_ in pairs(areas) do
            if type(table_) == "table" and type(table_.n) == "number" then n = n + table_.n end
        end
    end
    out.areas = n
    if index and type(index.dataset) == "table" then
        out.dataset = index.dataset
        out.dropped = index.dropped
        out.partialReasons = index.partial
        out.limits = index.limits
    end


    local counted = out.dataset or {}
    out.partial = type(counted.partial) == "number" and counted.partial or 0
    out.oneEnded = type(counted.oneEnded) == "number" and counted.oneEnded or 0
    out.full = type(counted.full) == "number" and counted.full or (out.shipped - out.partial - out.oneEnded)
    out.oneEndedReasons = index and index.oneEnded or nil
    return out
end

local function routableCount()
    return QuestData.Stats().full
end

local function kindName(kind)


    if kind == nil then return L["objective"] end
    local _, _, _, index = dataset()
    local names = index and index.kindNames
    local name = names and names[kind] or KIND_FALLBACK[kind]
    return name and L[name] or tostring(kind)
end
QuestData.KindName = kindName

local function sourceName(code)
    local _, _, _, index = dataset()
    local names = index and index.srcNames
    local name = names and names[code or 1]
    return name and L[name] or nil
end
QuestData.SourceName = sourceName




local function binarySearch(quests, questID)
    local ids, low, high = quests.id, 1, quests.n
    while low <= high do
        local mid = floor((low + high) / 2)
        local value = ids[mid]
        if value == questID then return mid
        elseif value < questID then low = mid + 1
        else high = mid - 1 end
    end
    return nil
end

local masksAllow





function QuestData.AliasOf(questID)
    questID = tonumber(questID)
    local quests = dataset()
    local list = quests and questID and type(quests.alias) == "table" and quests.alias[questID] or nil
    if type(list) ~= "table" or #list == 0 then return nil end
    for _, old in ipairs(list) do
        local row = binarySearch(quests, old)
        if row and masksAllow(quests, row) then return old end
    end
    return list[1]
end




function QuestData.OlderVersions(questID)
    questID = tonumber(questID)
    local quests = dataset()
    local list = quests and questID and type(quests.alias) == "table" and quests.alias[questID] or nil
    local out = {}
    for _, old in ipairs(type(list) == "table" and list or {}) do out[#out + 1] = old end
    return out
end


function QuestData.RowFor(questID)
    questID = tonumber(questID)
    local quests = dataset()
    if not quests or not questID then return nil end
    local row = binarySearch(quests, questID)
    if row then return row end
    local old = QuestData.AliasOf(questID)
    return old and binarySearch(quests, old) or nil
end

function QuestData.IdAt(row)
    local quests = dataset()
    if not quests or type(row) ~= "number" or row < 1 or row > quests.n then return nil end
    return quests.id[row]
end

function QuestData.Has(questID)
    return QuestData.RowFor(questID) ~= nil
end







local function positionAt(i)
    local _, givers = dataset()
    if not givers or type(i) ~= "number" or i < 1 or i > givers.n then return nil end
    local map = givers.map[i]
    if map == 0 then map = nil end
    local src = givers.src and givers.src[i] or 1
    return {
        index = i, inst = givers.inst[i], x = givers.x[i], y = givers.y[i], map = map,
        interior = map == nil,
        wander = givers.r and givers.r[i] or nil,


        src = src, later = src == 9 or nil,
    }
end
QuestData.PositionAt = positionAt



local function positionRange(row)
    local quests = dataset()
    if not quests or not row then return nil end
    local first, last = quests.p0[row], quests.p0[row + 1] - 1
    local giverCount = quests.gn[row]
    return first, last, giverCount
end

function QuestData.Givers(questID)
    local row = QuestData.RowFor(questID)
    local first, last, giverCount = positionRange(row)
    if not first then return {} end
    local out = {}
    for i = first, first + giverCount - 1 do
        if i <= last then out[#out + 1] = positionAt(i) end
    end
    return out
end

function QuestData.TurnIns(questID)
    local row = QuestData.RowFor(questID)
    local first, last, giverCount = positionRange(row)
    if not first then return {} end
    local out = {}
    for i = first + giverCount, last do out[#out + 1] = positionAt(i) end
    return out
end














local function otherSidesCapital(position, playerSide)
    local D = FGPS.Destinations
    if playerSide == 3 or not (position.map and D and D.CapitalFaction and D.MapName) then return false end
    local side = D.CapitalFaction(D.MapName(position.map))
    return side ~= nil and side ~= playerSide
end

local function nearest(list)
    if #list < 2 then return list[1] end
    local D = FGPS.Destinations
    local playerSide = D and D.PlayerFactionCode and D.PlayerFactionCode() or 3
    local welcome = {}
    for _, position in ipairs(list) do
        if not otherSidesCapital(position, playerSide) then welcome[#welcome + 1] = position end
    end
    if #welcome > 0 then list = welcome end
    if #list < 2 then return list[1] end
    local pos = QuestData.PlayerPos()
    if not (pos and pos.inst ~= nil and pos.x and pos.y) then return list[1] end
    local best, bestD
    for _, position in ipairs(list) do
        local at = QuestData.ReachedAt(position)
        if at and at.inst == pos.inst and at.x and at.y then
            local dx, dy = at.x - pos.x, at.y - pos.y
            local d = dx * dx + dy * dy
            if not bestD or d < bestD then best, bestD = position, d end
        end
    end
    return best or list[1]
end



function QuestData.Start(questID)
    local start = nearest(QuestData.Givers(questID))
    if start then return start end
    local info = not QuestData.RowFor(questID) and QuestData.ForeverInfo(questID) or nil
    return info and info.start or nil
end



function QuestData.TurnIn(questID)
    local turnIn = nearest(QuestData.TurnIns(questID))
    if turnIn then return turnIn end
    local info = not QuestData.RowFor(questID) and QuestData.ForeverInfo(questID) or nil
    return info and info.turnIn or nil
end








local GIVER_REF_BASE = 65536
local function giversIndex()
    if QuestData.giversOnMapBuilt then return QuestData.giversOnMapBuilt end
    local quests, givers, _, _, forever = dataset()
    local index = {}
    local function add(map, ref)
        local bucket = index[map]
        if not bucket then bucket = {} index[map] = bucket end
        bucket[#bucket + 1] = ref
    end
    if quests then
        for row = 1, quests.n do
            local first, last, giverCount = positionRange(row)
            for i = first, first + giverCount - 1 do
                local map = i <= last and givers.map[i] or 0
                if map ~= 0 then add(map, quests.id[row] * GIVER_REF_BASE + i) end
            end
        end
    end
    if forever and type(forever.sinst) == "table" and type(forever.smap) == "table" then
        for i = 1, (forever.n or #forever.id) do
            local map = forever.smap[i]
            if forever.sinst[i] and map and map ~= 0 and not QuestData.RowFor(forever.id[i]) then
                add(map, -(forever.id[i] * GIVER_REF_BASE + i))
            end
        end
    end
    QuestData.giversOnMapBuilt = index
    return index
end







function QuestData.GiversOnMap(uiMapID)
    local quests, _, _, _, forever = dataset()
    local bucket = quests and giversIndex()[tonumber(uiMapID)] or nil
    local out = {}
    if not bucket then return out end
    for k = 1, #bucket do
        local ref = bucket[k]
        local packed = ref < 0 and -ref or ref
        local at = packed % GIVER_REF_BASE
        local id = (packed - at) / GIVER_REF_BASE
        if ref > 0 then
            local row = binarySearch(quests, id)
            out[#out + 1] = { id = id, position = positionAt(at), giver = at - quests.p0[row] + 1 }
        else
            out[#out + 1] = { id = id, giver = 1, position = {
                inst = forever.sinst[at], x = forever.sx[at], y = forever.sy[at], map = forever.smap[at], interior = false,
                src = forever.ssrc and forever.ssrc[at] or nil } }
        end
    end
    return out
end









local AREA_REF_BASE = 65536
QuestData.AREA_REF_BASE = AREA_REF_BASE
local function areaIndex()
    if QuestData.areaIndexBuilt then return QuestData.areaIndexBuilt end
    local _, _, areas = dataset()
    local index = {}
    if areas then
        for inst, table_ in pairs(areas) do
            if type(table_) == "table" and type(table_.qi) == "table" then
                local qi = table_.qi
                for i = 1, (table_.n or #qi) do
                    local row = qi[i]
                    local bucket = index[row]
                    if not bucket then bucket = {} index[row] = bucket end
                    bucket[#bucket + 1] = inst * AREA_REF_BASE + i
                end
            end
        end
    end
    QuestData.areaIndexBuilt = index
    return index
end
QuestData.AreaIndex = areaIndex




local function samplePoints(table_, at)
    local text = table_.pts and table_.pts[at]
    if type(text) ~= "string" or text == "" then return nil end
    local out, n = {}, 0
    for value in text:gmatch("-?%d+") do
        n = n + 1
        out[n] = tonumber(value)
    end
    if n < 2 or n % 2 ~= 0 then return nil end
    return out
end



local SRC_LATER_RECORDS = 9
QuestData.SRC_LATER_RECORDS = SRC_LATER_RECORDS



local SRC_REPORTED = 10
QuestData.SRC_REPORTED = SRC_REPORTED

local function areaAt(inst, at)
    local _, _, areas = dataset()
    local table_ = areas and areas[inst]
    if type(table_) ~= "table" or type(at) ~= "number" then return nil end
    local map = table_.map[at]
    if map == 0 then map = nil end
    local src = table_.src and table_.src[at] or nil
    return {
        inst = inst, at = at, quest = table_.qi[at], objective = table_.obj[at], kind = table_.k[at],
        x = table_.cx[at], y = table_.cy[at], map = map, interior = map == nil,
        r68 = table_.r68[at], r = table_.r[at], spawns = table_.cn[at],
        points = samplePoints(table_, at),
        src = src, later = src == SRC_LATER_RECORDS or nil, reported = src == SRC_REPORTED or nil,
    }
end
QuestData.AreaAt = areaAt

local foreverAreas, foreverObjectiveCount




function QuestData.AreasFor(questID)
    local row = QuestData.RowFor(questID)
    if not row then return foreverAreas(questID) end
    local out = {}
    for _, ref in ipairs(areaIndex()[row] or {}) do
        local at = ref % AREA_REF_BASE
        local area = areaAt((ref - at) / AREA_REF_BASE, at)
        if area then out[#out + 1] = area end
    end
    return out
end





function QuestData.ObjectiveCount(questID)
    local quests = dataset()
    local row = QuestData.RowFor(questID)
    if not quests then return 0 end
    if not row then return foreverObjectiveCount(questID) end
    return quests.oo[row + 1] - quests.oo[row]
end




function QuestData.AreaLabel(area)
    local width = ((area and area.r68) or 0) * 2
    local label
    if width <= 0 then
        label = format(L["%s spot"], kindName(area and area.kind))
    else
        label = format(L["%s area, about %d yd across"], kindName(area.kind), width)
    end
    if area and area.later then label = format(L["%s, from later records"], label) end
    if area and area.reported then label = format(L["%s, reported by another source"], label) end
    return label
end




function QuestData.Objectives(questID)
    local quests = dataset()
    local row = QuestData.RowFor(questID)
    if not quests or not row then return {} end
    local first, last = quests.oo[row], quests.oo[row + 1] - 1
    local byObjective = {}
    for _, area in ipairs(QuestData.AreasFor(questID)) do
        local bucket = byObjective[area.objective]
        if not bucket then bucket = {} byObjective[area.objective] = bucket end
        bucket[#bucket + 1] = area
    end
    local out = {}
    for i = first, last do
        local n = i - first + 1
        out[n] = {
            index = n, kind = quests.ok[i], kindName = kindName(quests.ok[i]),
            need = quests.on[i], provided = (quests.op and quests.op[i] == 1) or false,
            areas = byObjective[n] or {},
        }
    end
    return out
end








local QR_OBJECTIVE_UNPLACED = 32
QuestData.QR_OBJECTIVE_UNPLACED = QR_OBJECTIVE_UNPLACED

QuestData.QR_ONE_ENDED = 128

function QuestData.IsPartial(questID)
    local quests = dataset()
    local row = QuestData.RowFor(questID)
    if not quests or not row then return false end
    return hasBit(quests.qr and quests.qr[row] or 0, QR_OBJECTIVE_UNPLACED)
end



function QuestData.UnplacedObjectives(questID)
    local out = {}
    if not QuestData.IsPartial(questID) then return out end
    for _, objective in ipairs(QuestData.Objectives(questID)) do
        if not objective.provided and #objective.areas == 0 then out[#out + 1] = objective.index end
    end
    return out
end






function QuestData.QualityReasons(questID)
    local quests = dataset()
    local row = QuestData.RowFor(questID)
    if not quests or not row then return {} end
    local mask = quests.qr and quests.qr[row] or 0
    if not mask or mask == 0 then return {} end
    local _, _, _, index = dataset()
    local names = index and index.qualityNames or {}
    local out = {}
    for bit = 0, 8 do
        local value = 2 ^ bit
        if hasBit(mask, value) and names[value] then out[#out + 1] = L[names[value]] end
    end
    return out
end



function QuestData.Info(questID)
    local quests = dataset()
    local row = QuestData.RowFor(questID)
    if not quests or not row then return nil end
    local start = QuestData.Start(questID)

    local own = quests.id[row]
    local aliasOf = tonumber(questID) ~= own and own or nil
    return {
        id = tonumber(questID), aliasOf = aliasOf, row = row, layer = "vanilla",
        level = quests.lvl[row], minLevel = quests.min[row],
        races = quests.races[row] or 0, classes = (quests.classes and quests.classes[row]) or 0,
        quality = (quests.q and quests.q[row]) or 2,
        qualityReasons = QuestData.QualityReasons(questID),

        partial = hasBit(quests.qr and quests.qr[row] or 0, QR_OBJECTIVE_UNPLACED),


        oneEnded = hasBit(quests.qr and quests.qr[row] or 0, QuestData.QR_ONE_ENDED),
        start = start, turnIn = QuestData.TurnIn(questID),
        startMap = start and start.map or nil,
        mark = QuestData.Mark(questID),
    }
end





local function foreverIndex()
    if QuestData.foreverIndexBuilt then return QuestData.foreverIndexBuilt end
    local _, _, _, _, forever = dataset()
    local index = {}
    if forever and type(forever.id) == "table" then
        for i = 1, (forever.n or #forever.id) do index[forever.id[i]] = i end
    end
    QuestData.foreverIndexBuilt = index
    return index
end

function QuestData.ForeverInfo(questID)
    questID = tonumber(questID)
    local _, _, _, _, forever = dataset()
    if not forever or not questID then return nil end
    local i = foreverIndex()[questID]
    if not i then return nil end
    local info = {
        id = questID, row = i, layer = "forever",
        level = forever.lvl and forever.lvl[i] or nil,
        title = forever.title and forever.title[i] or nil,
        questLine = forever.ql and forever.ql[i] or nil,
        startItem = forever.item and forever.item[i] or nil,
        startItemName = forever.iname and forever.iname[i] or nil,
        shipped = forever.v and forever.v[i] or 0,
    }
    local text = forever.obj and forever.obj[i]
    if type(text) == "string" and text ~= "" then
        info.objectiveText = {}
        for piece in text:gmatch("[^|]+") do info.objectiveText[#info.objectiveText + 1] = piece end
    end
    local inst = forever.sinst and forever.sinst[i]
    if inst then
        local map = forever.smap and forever.smap[i] or nil
        info.start = { inst = inst, x = forever.sx[i], y = forever.sy[i], map = map, interior = map == nil,
                       src = forever.ssrc and forever.ssrc[i] or nil }
    end
    local endInst = forever.tinst and forever.tinst[i]
    if endInst then
        local map = forever.tmap and forever.tmap[i] or nil
        info.turnIn = { inst = endInst, x = forever.tx[i], y = forever.ty[i], map = map, interior = map == nil,
                        src = forever.tsrc and forever.tsrc[i] or nil }
    end
    info.areas = foreverAreas(questID)
    info.objectiveCount = foreverObjectiveCount(questID)
    info.mark = QuestData.Mark(questID)
    return info
end






function foreverAreas(questID)
    local _, _, _, _, forever = dataset()
    local i = forever and foreverIndex()[tonumber(questID)]
    if not i then return {} end
    local list = forever.areas and forever.areas[i]
    local out = {}
    for at, a in ipairs(type(list) == "table" and list or {}) do
        local map = a.map
        if map == 0 then map = nil end
        local points
        if type(a.pts) == "string" and a.pts ~= "" then
            points = {}
            for value in a.pts:gmatch("-?%d+") do points[#points + 1] = tonumber(value) end
            if #points < 2 or #points % 2 ~= 0 then points = nil end
        end
        out[#out + 1] = {
            inst = a.inst, at = at, objective = a.obj, x = a.cx, y = a.cy, map = map, interior = map == nil,
            r68 = a.r68, r = a.r, spawns = a.cn, points = points, src = a.src, layer = "forever",
        }
    end
    local spots = forever.ao and forever.ao[i]
    if type(spots) == "string" then
        for spot in spots:gmatch("[^;]+") do
            local obj, inst, x, y, map = spot:match("^(%d+),(%d+),(-?[%d.]+),(-?[%d.]+),(%d+)$")
            obj, inst, x, y, map = tonumber(obj), tonumber(inst), tonumber(x), tonumber(y), tonumber(map)
            if obj and inst and x and y and map then
                if map == 0 then map = nil end
                out[#out + 1] = {
                    inst = inst, at = #out + 1, objective = obj, x = x, y = y, map = map, interior = map == nil,
                    r68 = 0, r = 0, spawns = 1, src = SRC_REPORTED, reported = true, layer = "forever",
                }
            end
        end
    end
    return out
end

function foreverObjectiveCount(questID)
    local _, _, _, _, forever = dataset()
    local i = forever and forever.nobj and foreverIndex()[tonumber(questID)]
    return (i and forever.nobj[i]) or 0
end


function QuestData.Lookup(questID)
    return QuestData.Info(questID) or QuestData.ForeverInfo(questID)
end









QuestData.MARK_UNVERIFIED, QuestData.MARK_REPORTED, QuestData.MARK_CONFIRMED = 0, 1, 2


function QuestData.Mark(questID)
    questID = tonumber(questID)
    if not questID then return QuestData.MARK_UNVERIFIED end

    if QuestData.AliasOf(questID) then return QuestData.MARK_UNVERIFIED end
    local _, _, _, _, forever = dataset()
    if forever then
        local i = foreverIndex()[questID]
        if i and forever.v then return forever.v[i] or 0 end
    end
    return QuestData.MARK_UNVERIFIED
end



local MARK_TEXT = {
    [0] = "From 1.12 records. Not confirmed in Forever - it may have moved or changed.",
    [1] = "Reported for Forever by another source, not confirmed on this client.",
    [2] = "Confirmed on this client.",
}
function QuestData.MarkText(mark)
    return L[MARK_TEXT[mark] or MARK_TEXT[0]]
end



local MARK_LABEL = { [0] = "1.12 record", [1] = "reported", [2] = "confirmed" }
function QuestData.MarkLabel(mark)
    return L[MARK_LABEL[mark] or MARK_LABEL[0]]
end




local function playerRaceBit()
    if not UnitRace then return nil end
    local ok, _, token = pcall(UnitRace, "player")
    if ok and type(token) == "string" then return RACE_BIT[token] end
    return nil
end

local function playerClassBit()
    if not UnitClass then return nil end
    local ok, _, token = pcall(UnitClass, "player")
    if ok and type(token) == "string" then return CLASS_BIT[token] end
    return nil
end



function masksAllow(quests, row)
    local race, class = playerRaceBit(), playerClassBit()
    local races = quests.races[row] or 0
    local classes = quests.classes and quests.classes[row] or 0
    if race and races ~= 0 and not hasBit(races, race) then return false end
    if class and classes ~= 0 and not hasBit(classes, class) then return false end
    return true
end

local function playerLevel()
    if not UnitLevel then return nil end
    local ok, level = pcall(UnitLevel, "player")
    if ok and type(level) == "number" and level > 0 then return level end
    return nil
end
QuestData.PlayerLevel = playerLevel




function QuestData.AllowedForPlayer(questID)
    local info = QuestData.Info(questID)
    if not info then return true end

    if info.aliasOf then return true end
    local race = playerRaceBit()
    if race and info.races and info.races ~= 0 and not hasBit(info.races, race) then
        return false, L["another race starts this quest"]
    end
    local class = playerClassBit()
    if class and info.classes and info.classes ~= 0 and not hasBit(info.classes, class) then
        return false, L["another class starts this quest"]
    end
    return true
end















local CAN_TAKE_TEXT = {
    done = "you have done this quest",
    done_unknown = "whether you have done this quest cannot be told",
    in_log = "it is in your quest log",
    no_record = "nothing is known of this quest",
    reissued = "this quest was issued again, and who may take the new version is not known",
    race = "another race takes this quest",
    race_unknown = "the record's rule for races does not know your race",
    race_doubtful = "the record's rule for races is doubtful for this quest",
    class = "another class takes this quest",
    class_unknown = "the record's rule for classes does not know your class",
    side = "the other side takes this quest",
    side_unknown = "whether your side may take this quest cannot be told",
    level = "needs level %d",
    level_max = "is for characters up to level %d",
    level_unknown = "your level cannot be told",
    earlier = "needs another quest done first: %s",
    earlier_log = "needs another quest in your quest log: %s",
    earlier_one = "needs one of %d other quests done first",
    exclusive = "another quest of its group is done or taken",
    skill = "needs %s at %d",
    skill_unknown = "needs a skill, and whether you have it cannot be told",
    reputation = "needs a standing with a faction, and how much is not known",
    season = "is given during a holiday only",
    forever_incomplete = "the source for Forever's own quests may not list every condition",
}
QuestData.CAN_TAKE_TEXT = CAN_TAKE_TEXT

local function canSay(code, ...)
    local text = CAN_TAKE_TEXT[code]
    if select("#", ...) > 0 then return format(L[text], ...) end
    return L[text]
end


local function isDone(questID)
    if not (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) then return nil end
    local ok, value = pcall(C_QuestLog.IsQuestFlaggedCompleted, questID)
    if not ok or (issecretvalue and issecretvalue(value)) then return nil end
    return value == true
end

local function inLog(questID)
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        local ok, index = pcall(C_QuestLog.GetLogIndexForQuestID, questID)
        if ok and type(index) == "number" and not (issecretvalue and issecretvalue(index)) then return index > 0 end
    end


    if C_QuestLog and C_QuestLog.IsOnQuest then
        local ok, on = pcall(C_QuestLog.IsOnQuest, questID)
        if ok and not (issecretvalue and issecretvalue(on)) and on == true then return true end
    end
    local Quests = FGPS.Quests
    return Quests and Quests.byID and Quests.byID[questID] ~= nil or false
end

local function questName(questID)
    return QuestData.Title(questID) or format(L["Quest %d"], questID)
end



local function listOf(value)
    if type(value) == "number" then return { value } end
    if type(value) == "table" then return value end
    return {}
end


local function groupIndex()
    if QuestData.groupIndexBuilt then return QuestData.groupIndexBuilt end
    local quests = dataset()
    local index = {}
    if quests and type(quests.xg) == "table" then
        for row, group in pairs(quests.xg) do
            local bucket = index[group]
            if not bucket then bucket = {} index[group] = bucket end
            bucket[#bucket + 1] = quests.id[row]
        end
    end
    QuestData.groupIndexBuilt = index
    return index
end


local function skillAtLeast(skill, value)
    if not (C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID) then return nil end
    local ok, info = pcall(C_SkillInfo.GetSkillLineInfoByID, skill)
    if not ok or type(info) ~= "table" then return nil end
    local rank = tonumber(info.rank)
    if not rank or (issecretvalue and issecretvalue(info.rank)) then return nil end
    if rank > 0 and rank >= (value or 1) then return true end
    if rank > 0 then return false, info.name end
    return nil
end



local function commonFacts(questID)
    local done = isDone(questID)
    if done then return "no", "done" end
    if inLog(questID) then return "no", "in_log" end
    if done == nil then return "unknown", "done_unknown" end
    return nil
end




local function giversSide(questID)
    local D = FGPS.Destinations
    if not (D and D.CapitalFaction and D.MapName and D.PlayerFactionCode) then return nil, true end
    local side
    for _, giver in ipairs(QuestData.Givers(questID)) do
        local here = giver.map and D.CapitalFaction(D.MapName(giver.map)) or nil
        if not here or (side and here ~= side) then return nil end
        side = here
    end
    return side
end

local function vanillaFacts(questID, info)
    local quests = dataset()
    local row = info.row
    local unknown
    local function maybe(code) unknown = unknown or code end
    local level = playerLevel()
    if info.aliasOf then


        if level and info.minLevel and info.minLevel > level then return "no", "level", info.minLevel end
        return "unknown", "reissued"
    end
    local race, class = playerRaceBit(), playerClassBit()
    if quests.ru and quests.ru[row] then


        maybe("race_doubtful")
    elseif info.races and info.races ~= 0 then
        if race == nil then maybe("race_unknown")
        elseif not hasBit(info.races, race) then return "no", "race" end
    end
    if info.classes and info.classes ~= 0 then
        if class == nil then maybe("class_unknown")
        elseif not hasBit(info.classes, class) then return "no", "class" end
    end
    if (info.races or 0) == 0 then



        local side, cannot = giversSide(questID)
        if cannot then maybe("side_unknown")
        elseif side then
            local mine = FGPS.Destinations.PlayerFactionCode()
            if mine ~= 1 and mine ~= 2 then maybe("side_unknown")
            elseif mine ~= side then return "no", "side" end
        end
    end
    if info.minLevel and info.minLevel > 0 then
        if not level then maybe("level_unknown")
        elseif info.minLevel > level then return "no", "level", info.minLevel end
    end
    for _, id in ipairs(listOf(quests.pq and quests.pq[row])) do
        if id > 0 then
            local done = isDone(id)
            if done == nil then maybe("done_unknown")
            elseif not done then return "no", "earlier", questName(id) end
        elseif not inLog(-id) then
            return "no", "earlier_log", questName(-id)
        end
    end


    local anyOf = quests.pqa and quests.pqa[row] and listOf(quests.pqa[row]) or nil
    if anyOf then
        local one, cannot = false, false
        for _, id in ipairs(anyOf) do
            if id > 0 then
                local done = isDone(id)
                if done then one = true elseif done == nil then cannot = true end
            elseif inLog(-id) then
                one = true
            end
        end
        if not one then
            if cannot then maybe("done_unknown") else return "no", "earlier_one", #anyOf end
        end
    end
    local group = quests.xg and quests.xg[row]
    if group then
        for _, other in ipairs(groupIndex()[group] or {}) do
            if other ~= quests.id[row] then
                local done = isDone(other)
                if done or inLog(other) then return "no", "exclusive" end

                if done == nil then maybe("done_unknown") end
            end
        end
    end
    local skill = quests.sk and quests.sk[row]
    if type(skill) == "number" then
        local line, value = floor(skill / 1000), skill % 1000
        local has, name = skillAtLeast(line, value)
        if has == false then return "no", "skill", tostring(name), value end
        if has == nil then maybe("skill_unknown") end
    end
    if quests.rp and quests.rp[row] then maybe("reputation") end
    if quests.ev and quests.ev[row] then maybe("season") end
    if unknown then return "unknown", unknown end
    return nil
end

local SIDE_CODE = { Alliance = 1, Horde = 2 }

local SIDE_RACES = { { RACE_BIT.Human, RACE_BIT.Dwarf, RACE_BIT.NightElf, RACE_BIT.Gnome },
                     { RACE_BIT.Orc, RACE_BIT.Undead, RACE_BIT.Tauren, RACE_BIT.Troll } }


local function playerSide()
    if not UnitFactionGroup then return nil end
    local ok, mine = pcall(UnitFactionGroup, "player")
    return ok and SIDE_CODE[mine] or nil
end




local function questSide(questID)
    local quests, _, _, _, forever = dataset()
    local i = forever and foreverIndex()[questID]
    if i and forever.gside and forever.gside[i] then return forever.gside[i] end
    local row = quests and QuestData.RowFor(questID)
    if not row or quests.id[row] ~= questID or (quests.ru and quests.ru[row]) then return nil end
    local found
    for side, bits in ipairs(SIDE_RACES) do
        for _, bit in ipairs(bits) do
            if hasBit(quests.races[row], bit) then
                if found then return nil end
                found = side
                break
            end
        end
    end
    return found
end





local function foreverMasksAllow(questID)
    local _, _, _, _, forever = dataset()
    local i = forever and foreverIndex()[questID]
    if not i then return true end
    local function at(name) local t = forever[name] return t and t[i] end
    local side, mine = at("gside"), playerSide()
    if side and mine and mine ~= side then return false, "side" end
    local races = at("graces")
    if races and UnitRace then
        local ok, _, _, raceID = pcall(UnitRace, "player")
        if ok and type(raceID) == "number" then
            local listed = false
            for _, r in ipairs(listOf(races)) do if r == raceID then listed = true end end
            if not listed then return false, "race" end
        end
    end
    local classes = at("gclasses")
    if classes and UnitClass then
        local ok, _, _, classID = pcall(UnitClass, "player")
        if ok and type(classID) == "number" and classID >= 1 and not hasBit(classes, 2 ^ (classID - 1)) then
            return false, "class"
        end
    end
    return true
end

local function foreverFacts(questID)
    local _, _, _, _, forever = dataset()
    local i = forever and foreverIndex()[questID]
    if not i then return "unknown", "no_record" end
    local function at(name) local t = forever[name] return t and t[i] end
    local allowed, why = foreverMasksAllow(questID)
    if not allowed then return "no", why end
    local level = playerLevel()
    if level and at("gmin") and at("gmin") > level then return "no", "level", at("gmin") end
    if level and at("gmax") and at("gmax") < level then return "no", "level_max", at("gmax") end
    local first = at("gpq") and listOf(at("gpq")) or nil
    if first and not at("gpqn") then




        local sideOf, seen = {}, {}
        for k, id in ipairs(first) do
            sideOf[k] = questSide(id)
            if sideOf[k] then seen[sideOf[k]] = true end
        end
        if seen[1] and seen[2] then
            local mine, own = playerSide(), {}
            for k, id in ipairs(first) do
                if sideOf[k] == nil or sideOf[k] == mine then own[#own + 1] = id end
            end
            first = own[1] and own or nil
        end
    end
    if first then
        local need, have = at("gpqn") or #first, 0
        for _, id in ipairs(first) do if isDone(id) then have = have + 1 end end
        if have < need and isDone(first[1]) ~= nil then
            if need == #first then
                for _, id in ipairs(first) do
                    if not isDone(id) then return "no", "earlier", questName(id) end
                end
            end
            return "no", "earlier_one", #first
        end
    end
    local skill = at("gsk")
    if skill and skillAtLeast(skill, 1) == nil then return "unknown", "skill_unknown" end
    return "unknown", "forever_incomplete"
end

function QuestData.CanTake(questID)
    questID = tonumber(questID)
    if not questID then return "unknown", canSay("no_record"), "no_record" end
    local answer, code, a, b = commonFacts(questID)
    if answer == "no" then return "no", canSay(code), code end
    local unknown = answer == "unknown" and code or nil
    local info = QuestData.Info(questID)
    local verdict, vcode
    if info then
        verdict, vcode, a, b = vanillaFacts(questID, info)
    else
        verdict, vcode, a, b = foreverFacts(questID)
    end
    if verdict == "no" then
        if a ~= nil then return "no", canSay(vcode, a, b), vcode end
        return "no", canSay(vcode), vcode
    end
    unknown = unknown or (verdict == "unknown" and vcode) or nil
    if unknown then return "unknown", canSay(unknown), unknown end
    return "yes", nil, nil
end



function QuestData.LevelNote(questID)
    local info = QuestData.Lookup(questID)
    local level = playerLevel()
    if not info or not level or not info.level or info.level <= 0 then return nil end
    if info.minLevel and info.minLevel > level then
        return format(L["needs level %d"], info.minLevel)
    end
    if info.level - level >= QuestData.FAR_ABOVE_LEVELS then
        return format(L["%d levels above you"], info.level - level)
    end
    return nil
end




local function playerPos()
    local Coords = FGPS.Coords
    if Coords and Coords.PlayerPos then
        local ok, pos = pcall(Coords.PlayerPos)
        if ok and type(pos) == "table" then return pos end
    end
    local D = FGPS.Destinations
    if D and D.PlayerPos then
        local ok, pos = pcall(D.PlayerPos)
        if ok and type(pos) == "table" then return pos end
    end
    return nil
end
QuestData.PlayerPos = playerPos

local function distanceTo(pos, inst, x, y)
    if not pos or not pos.x or not pos.y or pos.inst == nil then return nil end
    if inst == nil or x == nil or y == nil or inst ~= pos.inst then return nil end
    local dx, dy = x - pos.x, y - pos.y
    return sqrt(dx * dx + dy * dy)
end
QuestData.DistanceTo = distanceTo




function QuestData.DistanceToStart(questID, pos)
    local info = QuestData.Lookup(questID)
    local start = info and info.start
    if not start then return nil end
    return distanceTo(pos or playerPos(), start.inst, start.x, start.y)
end











function QuestData.EntranceFor(inst)
    if inst == nil then return nil end
    local pos = playerPos()
    local best, bestD
    local D = FGPS.Data
    local index = D and D.questIndex
    for _, list in ipairs({ D and D.interiors or {}, type(index) == "table" and index.doors or {} }) do
        if type(list) == "table" then
            for _, record in ipairs(list) do
                local entrance = type(record) == "table" and record.instanceMap == inst and record.entrance or nil
                if type(entrance) == "table" and entrance.inst and entrance.x and entrance.y then
                    local d = distanceTo(pos, entrance.inst, entrance.x, entrance.y) or 1e9
                    if not bestD or d < bestD then best, bestD = record, d end
                end
            end
        end
    end
    return best
end




function QuestData.ReachedAt(position)
    if type(position) ~= "table" or not position.inst or not position.x then return nil end
    if not position.interior then return position end
    local record = QuestData.EntranceFor(position.inst)
    return record and record.entrance or nil
end

function QuestData.Routable(position)
    return QuestData.ReachedAt(position) ~= nil
end

local function destFrom(questID, position, what, label, mark)
    if not position or not position.inst or not position.x then return nil, "no_location" end



    local entrance, inside
    if position.interior then
        local record = QuestData.EntranceFor(position.inst)
        if not record then return nil, "interior" end
        local door = record.entrance
        inside = { inst = position.inst, x = position.x, y = position.y }
        entrance = { name = record.name, inst = door.inst, x = door.x, y = door.y, map = door.map }
        label = format(L["%s, at the entrance of %s"], label, record.name)
        position = door
    end

    local older = QuestData.AliasOf(questID)
    if older then label = format(L["%s, from the older version of this quest"], label) end
    local D = FGPS.Destinations
    local dest = {
        kind = "quest", questID = questID, questTarget = what, type = "quest",
        name = label, inst = position.inst, x = position.x, y = position.y, map = position.map,
        unverified = mark <= 0,
        mark = mark,
        wander = position.wander,
        source = "bundled",
        entrance = entrance, interior = inside,
        olderVersion = older,
    }
    if D and D.MapName and position.map then dest.zoneName = D.MapName(position.map) end
    if D and D.ApplyReachability then pcall(D.ApplyReachability, dest) end
    return dest
end



local SRC_ITEM_DROP = 3
function QuestData.StartLabel(title, start)
    if type(start) == "table" and start.src == SRC_ITEM_DROP then
        return format(L["%s (where the item that starts it drops)"], title)
    end
    return format(L["%s (start)"], title)
end











function QuestData.DestinationFor(questID, what, index, exact)
    questID = tonumber(questID)
    if not questID then return nil, "no_quest" end
    if not QuestData.Available() then return nil, "no_data" end
    local title = QuestData.Title(questID) or format(L["Quest %d"], questID)
    what = what or "giver"
    if what == "giver" or what == "start" then


        local wanted = tonumber(index) or 1
        local start
        if wanted == 1 and not exact then start = QuestData.Start(questID) else start = QuestData.Givers(questID)[wanted] end
        if not start then
            local info = QuestData.ForeverInfo(questID)
            start = info and info.start or nil
        end


        return destFrom(questID, start, "giver", QuestData.StartLabel(title, start), QuestData.Mark(questID))
    elseif what == "turnin" then
        local wanted = tonumber(index) or 1
        local turnIn
        if wanted == 1 then turnIn = QuestData.TurnIn(questID) else turnIn = QuestData.TurnIns(questID)[wanted] end
        local label = format(turnIn and turnIn.later and L["%s (turn-in, from later records)"] or L["%s (turn-in)"], title)
        local dest, reason = destFrom(questID, turnIn, "turnin", label, QuestData.Mark(questID))
        if dest and turnIn.later then dest.laterRecords = true end
        return dest, reason
    elseif what == "event" then




        local start = QuestData.Start(questID)
        return destFrom(questID, start, "objective", format(L["%s (where it starts)"], title), QuestData.Mark(questID))
    elseif what == "objective" then
        local areas = QuestData.AreasFor(questID)
        local area = areas[tonumber(index) or 1]
        if not area then return nil, "no_location" end
        local x, y = area.x, area.y
        if area.points and not area.interior then
            local pos = playerPos()
            local fromX, fromY = area.x, area.y
            if pos and pos.inst == area.inst and pos.x and pos.y then fromX, fromY = pos.x, pos.y end
            local bestD
            for i = 1, #area.points - 1, 2 do
                local px, py = area.points[i], area.points[i + 1]
                local dx, dy = px - fromX, py - fromY
                local d = dx * dx + dy * dy
                if not bestD or d < bestD then bestD, x, y = d, px, py end
            end
        end



        local wide = (area.r68 or 0) > 0
        local pattern
        if area.later then
            pattern = wide and L["%s (%s area, from later records)"] or L["%s (%s spot, from later records)"]
        elseif area.reported then
            pattern = wide and L["%s (%s area, reported by another source)"] or L["%s (%s spot, reported by another source)"]
        else
            pattern = wide and L["%s (%s area)"] or L["%s (%s spot)"]
        end
        local dest, reason = destFrom(questID, { inst = area.inst, x = x, y = y, map = area.map, interior = area.interior },
            "objective", format(pattern, title, kindName(area.kind)), QuestData.Mark(questID))
        if dest and area.later then dest.laterRecords = true end
        if dest and area.reported then dest.reportedPlace = true end
        if dest then


            if not area.interior then
                dest.areaRadius = area.r68
                dest.areaReach = area.r
            end
            dest.objectiveIndex = area.objective


            dest.areaIndex = tonumber(index) or 1
            dest.objectiveKind = area.kind
        end
        return dest, reason
    end
    return nil, "bad_location"
end






local function titleStore()
    local DB = FGPS.DB
    local root = DB and DB.quests or nil
    if type(root) ~= "table" then
        if type(CabbieQuests) ~= "table" then CabbieQuests = {} end
        root = CabbieQuests
    end
    if type(root.titles) ~= "table" then root.titles = {} end




    local locale = GetLocale and GetLocale()
    if type(locale) == "string" and root.locale ~= locale then
        if root.locale ~= nil then
            root.titles = {}
            QuestData.titleIndexBuilt = nil
        end
        root.locale = locale
    end
    return root.titles
end
QuestData.TitleStore = titleStore





function QuestData.Title(questID)
    questID = tonumber(questID)
    if not questID then return nil end
    local stored = titleStore()[questID]
    if type(stored) == "string" and stored ~= "" then
        if stored ~= "Quest " .. questID then return stored end


        titleStore()[questID] = nil
    end
    local info = QuestData.ForeverInfo(questID)
    if info and info.title then return info.title end
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, title = pcall(C_QuestLog.GetTitleForQuestID, questID)
        if ok and type(title) == "string" and title ~= "" and not (issecretvalue and issecretvalue(title)) then
            QuestData.RememberTitle(questID, title)
            return title
        end
    end
    return nil
end



function QuestData.RememberTitle(questID, title)
    questID = tonumber(questID)
    if not questID or type(title) ~= "string" or title == "" then return false end
    if issecretvalue and issecretvalue(title) then return false end


    if title == "Quest " .. questID or title == format(L["Quest %d"], questID) then return false end
    local store = titleStore()
    if store[questID] == title then return false end
    store[questID] = title
    QuestData.stats.titlesLearned = QuestData.stats.titlesLearned + 1
    QuestData.titleIndexBuilt = nil
    return true
end

function QuestData.KnownTitleCount()
    local n = 0
    for _ in pairs(titleStore()) do n = n + 1 end
    local _, _, _, _, forever = dataset()
    if forever and type(forever.title) == "table" then
        local store = titleStore()
        for i, title in pairs(forever.title) do
            local id = forever.id[i]
            if id and store[id] == nil and type(title) == "string" then n = n + 1 end
        end
    end
    return n
end




local function titleIndex()
    if QuestData.titleIndexBuilt then return QuestData.titleIndexBuilt end
    local index = {}
    local _, _, _, _, forever = dataset()
    if forever and type(forever.title) == "table" then
        for i, title in pairs(forever.title) do
            local id = forever.id[i]
            if id and type(title) == "string" then index[#index + 1] = { id = id, title = title, folded = Util.Lower(title) } end
        end
    end
    for id, title in pairs(titleStore()) do
        if type(title) == "string" then index[#index + 1] = { id = id, title = title, folded = Util.Lower(title) } end
    end
    QuestData.titleIndexBuilt = index
    return index
end
QuestData.TitleIndex = titleIndex









function QuestData.SweepTitles(ids, onDone)
    if type(ids) ~= "table" or #ids == 0 then
        if onDone then onDone(0) end
        return nil
    end
    local function sweep()
        local found, yield = 0, FGPS.Scheduler and FGPS.Scheduler.Yield
        for i = 1, #ids do
            local id = ids[i]
            if titleStore()[id] == nil and C_QuestLog and C_QuestLog.GetTitleForQuestID then
                local ok, title = pcall(C_QuestLog.GetTitleForQuestID, id)
                if ok and type(title) == "string" and title ~= "" then
                    if QuestData.RememberTitle(id, title) then found = found + 1 end
                end
            end
            if i % QuestData.SWEEP_CHUNK == 0 and yield and not yield() then break end
        end
        return found
    end
    local Scheduler = FGPS.Scheduler
    if not (Scheduler and Scheduler.Run) then
        local found = sweep()
        if onDone then onDone(found) end
        return found
    end
    return Scheduler:Run(sweep, {
        label = "quest-titles",
        onDone = function(ok, found) if onDone then onDone(ok and found or 0) end end,
    })
end




function QuestData.LookupsLeft()
    local left = QuestData.LOOKUP_SESSION_BUDGET - QuestData.lookups.used
    if left < 0 then return 0 end
    return left
end




function QuestData.CanLookup()
    if not (C_QuestLog and C_QuestLog.RequestLoadQuestByID) then return false, "no_api" end
    local s = FGPS.DB and FGPS.DB.settings
    if s and s.quests and s.quests.serverLookup == false then return false, "disabled" end
    if QuestData.LookupsLeft() <= 0 then return false, "budget" end
    if QuestData.lookups.inFlight then return false, "in_flight" end
    if InCombatLockdown and InCombatLockdown() then return false, "combat" end
    if now() - QuestData.lookups.lastAt < QuestData.LOOKUP_MIN_SECONDS then return false, "too_soon" end
    return true
end





function QuestData.RequestTitle(questID, onAnswer)
    questID = tonumber(questID)
    if not questID then return false, "no_quest" end
    local allowed, why = QuestData.CanLookup()
    if not allowed then return false, why end
    QuestData.lookups.inFlight = { id = questID, at = now(), onAnswer = onAnswer }
    QuestData.lookups.used = QuestData.lookups.used + 1
    QuestData.lookups.lastAt = now()
    QuestData.stats.lookupsSpent = QuestData.stats.lookupsSpent + 1
    local ok = pcall(C_QuestLog.RequestLoadQuestByID, questID)
    if not ok then
        QuestData.lookups.inFlight = nil
        return false, "no_api"
    end
    return true
end

local function onQuestDataLoaded(_, questID, success)
    questID = tonumber(questID)
    local pending = QuestData.lookups.inFlight
    if pending and pending.id == questID then QuestData.lookups.inFlight = nil end
    if not questID then return end
    if success == false then

        if pending and pending.id == questID then
            QuestData.lookups.failed = QuestData.lookups.failed + 1
            QuestData.lookups.refused[questID] = true
        end
    else
        QuestData.Title(questID)
    end
    if pending and pending.id == questID and pending.onAnswer then
        pcall(pending.onAnswer, questID, success ~= false)
    end
    FGPS.Events:Fire("QUEST_TITLE_RESOLVED", questID, success ~= false)
end





local function zoneIndex()
    if QuestData.zoneIndexBuilt then return QuestData.zoneIndexBuilt end
    local quests = dataset()
    local index = {}
    if quests then
        for row = 1, quests.n do
            local first, _, giverCount = positionRange(row)
            if first and giverCount and giverCount > 0 then




                for i = first, first + giverCount - 1 do
                    local pos = positionAt(i)
                    local map = pos and pos.map
                    if map then
                        local bucket = index[map]
                        if not bucket then bucket = {} index[map] = bucket end
                        bucket[#bucket + 1] = row
                        break
                    end
                end
            end
        end
    end
    QuestData.zoneIndexBuilt = index
    return index
end
QuestData.ZoneIndex = zoneIndex




function QuestData.ParseQuery(text)
    local out = { text = "" }
    text = Util.Trim(tostring(text or ""))
    if text == "" then return out end
    local rest = text

    local low, high = rest:match("(%d+)%s*%-%s*(%d+)")
    if low then
        out.minLevel, out.maxLevel = tonumber(low), tonumber(high)
        rest = rest:gsub("%d+%s*%-%s*%d+", " ", 1)
    else
        local one = rest:match("^%s*level%s+(%d+)%s*$") or rest:match("^%s*(%d+)%s*$")
        if one then
            out.minLevel, out.maxLevel = tonumber(one), tonumber(one)
            rest = ""
        end
    end
    rest = Util.Trim((rest:gsub("^%s*level%s+", " "):gsub("%s*quests?%s*", " "):gsub("%s*in%s+", " ")))
    if rest ~= "" then
        local D = FGPS.Destinations
        if D and D.ResolveZoneName then
            local ok, mapID = pcall(D.ResolveZoneName, rest)
            if ok and type(mapID) == "number" and zoneIndex()[mapID] then
                out.zone = mapID
                out.zoneName = D.MapName and D.MapName(mapID) or nil
                rest = ""
            end
        end
    end
    out.text = rest
    return out
end

local function levelMatches(query, level, minLevel)
    if not query.minLevel then return true end
    local value = level
    if not value or value <= 0 then value = minLevel end
    if not value or value <= 0 then return false end
    return value >= query.minLevel and value <= (query.maxLevel or query.minLevel)
end



local function searchRow(questID, pos, layer)
    local info = layer == "forever" and QuestData.ForeverInfo(questID) or QuestData.Info(questID)
    if not info then return nil end
    local start = info.start
    local D = FGPS.Destinations
    local row = {
        questID = questID, layer = info.layer, level = info.level, minLevel = info.minLevel,
        quality = info.quality, qualityReasons = info.qualityReasons, mark = info.mark,
        partial = info.partial or false, oneEnded = info.oneEnded or false,
        title = QuestData.Title(questID),
        startMap = start and start.map or nil,
        startInterior = start and start.interior or false,
        hasStart = start ~= nil,
        yards = start and distanceTo(pos, start.inst, start.x, start.y) or nil,
        routable = info.layer == "vanilla",
        levelNote = QuestData.LevelNote(questID),
    }
    if row.startMap and D and D.MapName then row.startName = D.MapName(row.startMap) end
    return row
end



local function sortRows(rows)
    table.sort(rows, function(a, b)
        local ay, by = a.yards, b.yards
        if ay and by then
            if ay ~= by then return ay < by end
        elseif ay then return true
        elseif by then return false end
        return a.questID < b.questID
    end)
    return rows
end







function QuestData.Search(text, opts)
    opts = opts or {}
    local quests = dataset()
    if not quests then return {}, L["Quest data is not installed in this copy of Cabbie."], {} end
    local query = QuestData.ParseQuery(text)
    local limit = opts.limit or QuestData.SEARCH_LIMIT
    local pos = playerPos()
    local rows, seen, refused = {}, {}, 0
    local settings = FGPS.DB and FGPS.DB.settings
    local includeForever = opts.includeForever
    if includeForever == nil then
        includeForever = not (settings and settings.quests and settings.quests.searchForever == false)
    end

    local function consider(questID, layer)
        if seen[questID] then return end
        if layer == "vanilla" and not opts.ignoreEligibility then
            local allowed = QuestData.AllowedForPlayer(questID)
            if not allowed then refused = refused + 1 return end
        end
        local row = searchRow(questID, pos, layer)
        if not row then return end
        if not levelMatches(query, row.level, row.minLevel) then return end
        seen[questID] = true
        rows[#rows + 1] = row
    end

    if query.zone then


        for _, row in ipairs(zoneIndex()[query.zone] or {}) do consider(quests.id[row], "vanilla") end
    elseif query.text ~= "" then


        local needle = Util.Lower(query.text)
        for _, entry in ipairs(titleIndex()) do
            if entry.folded:find(needle, 1, true) then
                local layer = "forever"
                if QuestData.RowFor(entry.id) then layer = "vanilla" end
                if layer == "vanilla" or includeForever then consider(entry.id, layer) end
            end
        end
    elseif query.minLevel then
        for row = 1, quests.n do consider(quests.id[row], "vanilla") end
    end

    sortRows(rows)
    while #rows > limit do rows[#rows] = nil end

    local status
    if #rows > 0 then


        local partial, oneEnded = 0, 0
        for _, row in ipairs(rows) do
            if row.oneEnded then oneEnded = oneEnded + 1
            elseif row.partial then partial = partial + 1 end
        end
        if query.zone then
            status = format(L["%d routable quests start in %s."], #rows - partial - oneEnded, query.zoneName or tostring(query.zone))
        else
            status = format(L["%d quests found."], #rows)
        end
        if partial > 0 then
            status = status .. " " .. format(query.zone and L["%d more have an objective whose place is not known."]
                or L["%d of them have an objective whose place is not known."], partial)
        end
        if oneEnded > 0 then

            status = status .. " " .. format(query.zone and L["%d more have no known hand-in."]
                or L["%d of them have no known giver or no known hand-in."], oneEnded)
        end
        if refused > 0 then
            status = status .. " " .. format(L["%d more start with another race or class."], refused)
        end
    elseif query.text ~= "" then
        status = format(L["Cabbie does not ship quest names for vanilla quests - the client supplies them, in Forever's own wording. Search by zone or by level, or open a quest once and Cabbie will remember its name. Names known so far: %d of %d."],
            QuestData.KnownTitleCount(), quests.n)
    elseif query.zone or query.minLevel then
        status = L["No routable quest matches that."]
    else
        status = format(L["Search by zone (\"Westfall\"), by level (\"24\" or \"20-30\"), or by a quest name you have already seen. %d routable quests are bundled."], routableCount())
    end
    return rows, status, query
end










function QuestData.SearchTitles(text, opts)
    opts = opts or {}
    local needle = Util.Lower(Util.Trim(tostring(text or "")))
    if needle == "" or not dataset() then return {} end
    local includeForever = opts.includeForever
    if includeForever == nil then
        local settings = FGPS.DB and FGPS.DB.settings
        includeForever = not (settings and settings.quests and settings.quests.searchForever == false)
    end
    local D = FGPS.Destinations
    local score = D and D.ScoreName
    local hits = {}
    for _, entry in ipairs(titleIndex()) do
        if entry.folded:find(needle, 1, true) then
            local layer = QuestData.RowFor(entry.id) and "vanilla" or "forever"
            if layer == "vanilla" or includeForever then
                hits[#hits + 1] = { id = entry.id, layer = layer, folded = entry.folded, score = score and score(entry.folded, needle) or 40 }
            end
        end
    end
    table.sort(hits, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.folded ~= b.folded then return a.folded < b.folded end
        return a.id < b.id
    end)
    local limit = opts.limit or QuestData.SEARCH_LIMIT
    local pos = playerPos()
    local rows, seen = {}, {}
    for _, hit in ipairs(hits) do
        if #rows >= limit then break end
        local allowed = (hit.layer == "vanilla" and QuestData.AllowedForPlayer(hit.id))
            or (hit.layer == "forever" and foreverMasksAllow(hit.id))
        if not seen[hit.id] and allowed then
            local row = searchRow(hit.id, pos, hit.layer)
            if row then
                seen[hit.id] = true
                row.score = hit.score
                rows[#rows + 1] = row
            end
        end
    end
    return rows
end



function QuestData.UnnamedIn(rows)
    local out = {}
    local refused = QuestData.lookups.refused
    for _, row in ipairs(rows or {}) do
        if not row.title and row.questID and not refused[row.questID] then out[#out + 1] = row.questID end
    end
    return out
end




function QuestData:Init()
    if self.initialised then return end
    self.initialised = true
    self.available = QuestData.Available()

    self.zoneIndexBuilt, self.areaIndexBuilt, self.foreverIndexBuilt, self.titleIndexBuilt = nil, nil, nil, nil
    self.groupIndexBuilt, self.giversOnMapBuilt = nil, nil
    local Events = FGPS.Events
    Events:RegisterWoW("QUEST_DATA_LOAD_RESULT", onQuestDataLoaded, self)


    Events:Register("QUESTS_UPDATED", function()
        local Quests = FGPS.Quests
        if not (Quests and Quests.List) then return end
        local ok, list = pcall(Quests.List)
        if not ok then return end
        for _, q in ipairs(list or {}) do

            if q.title and q.questID and q.titleKnown ~= false then QuestData.RememberTitle(q.questID, q.title) end
        end
    end, self)
    if not self.available then
        FGPS.Log:Info("Quest data files are not installed; the quest panel reports the feature as unavailable")
    end
end
