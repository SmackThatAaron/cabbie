
























































local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Events = FGPS.Events
local sqrt, floor, type, pairs, ipairs, tonumber, tostring, format = math.sqrt, math.floor, type, pairs, ipairs, tonumber, tostring, string.format
local huge = math.huge

local Quests = {
    THROTTLE_SECONDS = 1,
    NEWS_HOLD = 8,
    cache = nil,
    byID = nil,
    dirty = true,
    lastRefresh = -1e9,
    timer = nil,
    order = nil,
    lastInst = nil,
}
FGPS.Quests = Quests

local DUNGEON_MAP_TYPE = 4

local function now() return GetTime and GetTime() or 0 end

local function dist(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return sqrt(dx * dx + dy * dy)
end

local function playerPos()
    local D = FGPS.Destinations
    if D and D.PlayerPos then return D.PlayerPos() end
    return nil
end

local function mapToWorld(uiMapID, mx, my)
    local D = FGPS.Destinations
    if D and D.MapToWorld then return D.MapToWorld(uiMapID, mx, my) end
    return nil
end

local function mapName(uiMapID)
    local D = FGPS.Destinations
    if D and D.MapName then return D.MapName(uiMapID) end
    return nil
end


local function isInteriorMap(uiMapID)
    if not uiMapID then return false end
    local data = FGPS.Data and FGPS.Data.maps and FGPS.Data.maps[uiMapID]
    if data and data.kind == DUNGEON_MAP_TYPE then return true end
    local dungeonType = Enum and Enum.UIMapType and Enum.UIMapType.Dungeon or DUNGEON_MAP_TYPE
    if C_Map and C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, uiMapID)
        if ok and info and info.mapType == dungeonType then return true end
    end
    return false
end
Quests.IsInteriorMap = isInteriorMap

local function currentMap()
    local pos = playerPos()
    if pos and pos.map then return pos.map end
    if C_Map and C_Map.GetBestMapForUnit then return C_Map.GetBestMapForUnit("player") end
    return nil
end











local function isSecret(value)
    return value ~= nil and issecretvalue ~= nil and issecretvalue(value) == true
end







local function entranceOfMap(mapID)
    local QuestData = FGPS.QuestData
    if not (QuestData and QuestData.EntranceFor) then return nil end
    local inst = mapToWorld(mapID, 0.5, 0.5)
    if inst == nil and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
        local ok, id = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(0.5, 0.5))
        if ok and type(id) == "number" and not isSecret(id) then inst = id end
    end
    if inst == nil then return nil end
    local ok, record = pcall(QuestData.EntranceFor, inst)
    local door = ok and type(record) == "table" and record.entrance or nil
    if type(door) ~= "table" or not (door.inst and door.x and door.y) then return nil end
    return { name = record.name, inst = door.inst, x = door.x, y = door.y, map = door.map, instanceMap = inst }
end

local function makeLocation(mapID, mx, my, source)
    if isSecret(mapID) or isSecret(mx) or isSecret(my) then return nil end
    if type(mapID) ~= "number" or type(mx) ~= "number" or type(my) ~= "number" then return nil end
    local loc = { map = mapID, mx = mx, my = my, source = source }
    if isInteriorMap(mapID) then


        loc.interior = true
        loc.entrance = entranceOfMap(mapID)
        return loc
    end
    local inst, x, y = mapToWorld(mapID, mx, my)
    if inst then loc.inst, loc.x, loc.y = inst, x, y end
    return loc
end






local SAME_PLACE_YARDS = 25

local function sameLocation(a, b)
    local world = a.inst and b.inst and a.x and b.x and a.y and b.y


    if a.map == b.map and not world then
        return math.abs(a.mx - b.mx) < 0.002 and math.abs(a.my - b.my) < 0.002
    end
    if not world or a.inst ~= b.inst then return false end
    return dist(a.x, a.y, b.x, b.y) <= SAME_PLACE_YARDS
end

Quests._sameLocation = sameLocation

local function addLocation(list, loc)
    if not loc then return end
    for _, existing in ipairs(list) do
        if sameLocation(existing, loc) then return end
    end
    list[#list + 1] = loc
end


local function poisByQuest(mapID)
    local out = {}
    if not mapID or not (C_QuestLog and C_QuestLog.GetQuestsOnMap) then return out end
    local ok, list = pcall(C_QuestLog.GetQuestsOnMap, mapID)
    if not ok or type(list) ~= "table" then return out end
    for _, info in ipairs(list) do


        local questID, poiMap = info.questID, info.mapID
        if not isSecret(questID) and not isSecret(poiMap) and questID then
            local bucket = out[questID]
            if not bucket then bucket = {} out[questID] = bucket end
            bucket[#bucket + 1] = { map = poiMap or mapID, x = info.x, y = info.y }
        end
    end
    return out
end

local function nextWaypoint(questID)
    if not (C_QuestLog and C_QuestLog.GetNextWaypoint) then return nil end
    local ok, mapID, x, y = pcall(C_QuestLog.GetNextWaypoint, questID)
    if not ok or isSecret(mapID) or isSecret(x) or isSecret(y) then return nil end
    if mapID and x and y then return mapID, x, y end
    return nil
end





local function objectiveNumber(value)
    if type(value) ~= "number" then return nil end
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

local function objectivesOf(questID)
    local out = {}
    if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return out end
    local ok, list = pcall(C_QuestLog.GetQuestObjectives, questID)
    if ok and type(list) == "table" then
        for i, o in ipairs(list) do
            out[i] = {
                text = o.text, finished = o.finished and true or false, type = o.type,
                have = objectiveNumber(o.numFulfilled), need = objectiveNumber(o.numRequired),
            }
        end
    end
    return out
end


local function finishedCount(q)
    local n = 0
    for _, o in ipairs(q.objectives or {}) do
        if o.finished then n = n + 1 end
    end
    return n
end

local function isComplete(questID)
    if C_QuestLog then
        if C_QuestLog.ReadyForTurnIn then
            local ok, v = pcall(C_QuestLog.ReadyForTurnIn, questID)
            if ok and v then return true end
        end
        if C_QuestLog.IsComplete then
            local ok, v = pcall(C_QuestLog.IsComplete, questID)
            if ok and v then return true end
        end
    end
    return false
end





local function isFailed(questID)
    if not (C_QuestLog and C_QuestLog.IsFailed) then return false end
    local ok, failed = pcall(C_QuestLog.IsFailed, questID)
    return ok and not isSecret(failed) and failed == true
end

local function nextWaypointText(questID)
    if not (C_QuestLog and C_QuestLog.GetNextWaypointText) then return nil end
    local ok, text = pcall(C_QuestLog.GetNextWaypointText, questID)
    if ok and type(text) == "string" and text ~= "" and not (issecretvalue and issecretvalue(text)) then return text end
    return nil
end














local function usableMapID(ok, id)
    if not ok or type(id) ~= "number" or (issecretvalue and issecretvalue(id)) or id <= 0 then return nil end
    return id
end

local function questOwnMap(questID)
    if type(GetQuestUiMapID) ~= "function" then return nil end
    return usableMapID(pcall(GetQuestUiMapID, questID, true)) or usableMapID(pcall(GetQuestUiMapID, questID))
end



local function mapReader(always)
    return { always = always, byMap = {} }
end

local function poisOn(reader, mapID)
    local bucket = reader.byMap[mapID]
    if not bucket then
        bucket = poisByQuest(mapID)
        reader.byMap[mapID] = bucket
    end
    return bucket
end






local function locationsFor(questID, reader)
    local list = {}
    for _, mapID in ipairs(reader.always) do
        for _, p in ipairs(poisOn(reader, mapID)[questID] or {}) do addLocation(list, makeLocation(p.map, p.x, p.y, "poi")) end
    end
    if #list == 0 then
        local own = questOwnMap(questID)
        if own then
            for _, p in ipairs(poisOn(reader, own)[questID] or {}) do addLocation(list, makeLocation(p.map, p.x, p.y, "poi")) end
        end
    end
    local wpMap, wx, wy = nextWaypoint(questID)
    local hint = wpMap and makeLocation(wpMap, wx, wy, "nextWaypoint") or nil
    if hint then
        local same
        for _, existing in ipairs(list) do
            if sameLocation(existing, hint) then same = existing break end
        end
        if same then
            same.waypoint = true
        else
            hint.waypoint = true
            list[#list + 1] = hint
        end
    end
    return list
end



local function objectiveSummary(q)
    if q.complete then return L["Ready to turn in"], true end
    local open = {}
    for _, o in ipairs(q.objectives or {}) do
        if not o.finished and type(o.text) == "string" and o.text ~= "" then open[#open + 1] = o.text end
    end
    if #open == 0 then return nil, false end
    return table.concat(open, "; "), false
end






local function locationKey(loc)
    return format("%d:%d:%d", loc.map or 0, floor((loc.mx or 0) * 1000), floor((loc.my or 0) * 1000))
end
Quests.LocationKey = locationKey





local function stableOrder(questID, locations, nextOrder)
    local previous = Quests.order and Quests.order[questID]
    if previous then
        local byKey, taken, out = {}, {}, {}
        for _, loc in ipairs(locations) do
            if byKey[loc.key] == nil then byKey[loc.key] = loc end
        end
        for _, key in ipairs(previous) do
            local loc = byKey[key]
            if loc and not taken[loc] then
                taken[loc] = true
                out[#out + 1] = loc
            end
        end
        for _, loc in ipairs(locations) do
            if not taken[loc] then
                taken[loc] = true
                out[#out + 1] = loc
            end
        end
        locations = out
    end
    if nextOrder then
        local keys = {}
        for i, loc in ipairs(locations) do keys[i] = loc.key end
        nextOrder[questID] = keys
    end
    return locations
end






local function describeLocations(q, nextOrder)
    local text, finished = objectiveSummary(q)
    q.objectiveText, q.finished = text, finished
    for _, loc in ipairs(q.locations) do loc.key = locationKey(loc) end
    q.locations = stableOrder(q.questID, q.locations, nextOrder)
    local outdoor = {}
    for i, loc in ipairs(q.locations) do
        loc.index = i
        loc.zoneName = mapName(loc.map)
        loc.outdoor = (not loc.interior and loc.inst ~= nil and loc.x ~= nil and loc.y ~= nil) and true or false
        loc.finished = finished
        if loc.source == "nextWaypoint" then
            loc.objectiveText = nextWaypointText(q.questID) or L["Next waypoint on the way to the quest"]
        else
            loc.objectiveText = text
        end
        if loc.outdoor then outdoor[#outdoor + 1] = loc end
    end
    q.outdoor = outdoor
end

















local function foreverBlock(QuestData, questID)
    if not QuestData.ForeverInfo then return nil end
    local ok, info = pcall(QuestData.ForeverInfo, questID)
    if not ok or type(info) ~= "table" then return nil end
    local areas = type(info.areas) == "table" and info.areas or {}
    if not info.turnIn and #areas == 0 then return nil end





    local objectiveCount = type(info.objectiveCount) == "number" and info.objectiveCount or 0
    local placed, unplaced = {}, {}
    for _, area in ipairs(areas) do
        if area.objective then placed[area.objective] = true end
    end
    for n = 1, objectiveCount do
        if not placed[n] then unplaced[#unplaced + 1] = n end
    end
    return {
        layer = "forever", mark = info.mark, quality = 2, qualityReasons = {},
        level = info.level, giver = info.start, turnIn = info.turnIn,
        areas = areas, objectiveCount = objectiveCount,
        unverified = (info.mark or 0) <= 0, partial = #unplaced > 0, unplaced = unplaced,
    }
end

local function bundledFor(questID)
    local QuestData = FGPS.QuestData
    if not (QuestData and QuestData.Available and QuestData.Available()) then return nil end
    local ok, info = pcall(QuestData.Info, questID)
    if ok and info == nil then
        local block = foreverBlock(QuestData, questID)
        local D = FGPS.Destinations
        if block and block.turnIn and block.turnIn.map and D and D.MapName then block.turnInZone = D.MapName(block.turnIn.map) end
        if block and block.giver and block.giver.map and D and D.MapName then block.giverZone = D.MapName(block.giver.map) end
        return block
    end
    if not ok or type(info) ~= "table" then return nil end
    local okAreas, areas = pcall(QuestData.AreasFor, questID)
    local okCount, objectiveCount = pcall(QuestData.ObjectiveCount, questID)
    local block = {
        mark = info.mark, quality = info.quality, qualityReasons = info.qualityReasons,
        level = info.level, minLevel = info.minLevel,
        giver = info.start, turnIn = info.turnIn,
        areas = (okAreas and type(areas) == "table") and areas or {},


        objectiveCount = (okCount and type(objectiveCount) == "number") and objectiveCount or 0,
        unverified = (info.mark or 0) <= 0,


        partial = info.partial and true or false,
    }
    if block.partial and QuestData.UnplacedObjectives then
        local okUnplaced, unplaced = pcall(QuestData.UnplacedObjectives, questID)
        block.unplaced = (okUnplaced and type(unplaced) == "table") and unplaced or {}
    end
    local D = FGPS.Destinations
    if block.giver and block.giver.map and D and D.MapName then block.giverZone = D.MapName(block.giver.map) end
    if block.turnIn and block.turnIn.map and D and D.MapName then block.turnInZone = D.MapName(block.turnIn.map) end
    return block
end
Quests.BundledFor = bundledFor




local function questPOIMap()
    if C_QuestLog and C_QuestLog.GetMapForQuestPOIs then
        local ok, id = pcall(C_QuestLog.GetMapForQuestPOIs)
        if ok and type(id) == "number" and id > 0 then return id end
    end
    return nil
end




local function titleOf(questID, fromClient)
    if type(fromClient) == "string" and fromClient ~= "" and not (issecretvalue and issecretvalue(fromClient)) then
        return fromClient, true
    end
    local QuestData = FGPS.QuestData
    if QuestData and QuestData.Title then
        local ok, title = pcall(QuestData.Title, questID)
        if ok and type(title) == "string" and title ~= "" then return title, true end
    end
    return format(L["Quest %d"], questID), false
end

local function buildList()
    local out, byID, nextOrder = {}, {}, {}
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then return out, byID, nextOrder end
    local okN, n = pcall(C_QuestLog.GetNumQuestLogEntries)
    if not okN or type(n) ~= "number" then return out, byID, nextOrder end
    local playerMap = currentMap()
    local poiMap = questPOIMap()
    local always = {}
    if playerMap then always[#always + 1] = playerMap end
    if poiMap and poiMap ~= playerMap then always[#always + 1] = poiMap end
    local reader = mapReader(always)
    for i = 1, n do
        local ok, info = pcall(C_QuestLog.GetInfo, i)


        if ok and type(info) == "table" and not info.isHeader and type(info.questID) == "number" and info.questID > 0 and not info.isHidden
            and not byID[info.questID] then
            local questID = info.questID
            local title, titleKnown = titleOf(questID, info.title)
            local onMap = info.isOnMap and true or false
            if C_QuestLog.IsOnMap then
                local okOn, on = pcall(C_QuestLog.IsOnMap, questID)
                if okOn and on ~= nil then onMap = on and true or false end
            end
            local q = {
                questID = questID, title = title, titleKnown = titleKnown, logIndex = i, level = info.level,
                complete = isComplete(questID), failed = isFailed(questID), onMap = onMap, objectives = objectivesOf(questID),
                locations = locationsFor(questID, reader),
            }
            describeLocations(q, nextOrder)
            q.bundled = bundledFor(questID)
            out[#out + 1] = q
            byID[questID] = q
        end
    end
    return out, byID, nextOrder, reader.byMap
end




local function recheckStay()
    local Navigator = FGPS.Navigator
    if not (Navigator and Navigator.RecheckStay) then return end
    local ok, err = pcall(Navigator.RecheckStay, Navigator)
    if not ok and FGPS.Log then FGPS.Log:Error("Quests: the place a route stays at could not be asked again: %s", tostring(err)) end
end

function Quests.Refresh()
    if Quests.timer then
        Quests.timer:Cancel()
        Quests.timer = nil
    end

    local order, mapsRead
    Quests.cache, Quests.byID, order, mapsRead = buildList()
    Quests.order = order



    Quests.mapsRead = mapsRead or {}
    Quests.dirty = false
    Quests.lastRefresh = now()
    Events:Fire("QUESTS_UPDATED", #Quests.cache)

    local ok, err = pcall(Quests.FollowProgress)
    if not ok and FGPS.Log then FGPS.Log:Error("Quests.FollowProgress failed: %s", tostring(err)) end


    recheckStay()
    return Quests.cache
end

local questStops







function Quests.Invalidate()
    Quests.dirty = true
    if not (Events:HasHandlers("QUESTS_UPDATED") or #questStops() > 0) then return end
    local elapsed = now() - Quests.lastRefresh
    if elapsed >= Quests.THROTTLE_SECONDS then
        Quests.Refresh()
    elseif not Quests.timer and C_Timer and C_Timer.NewTimer then
        Quests.timer = C_Timer.NewTimer(Quests.THROTTLE_SECONDS - elapsed, function()
            Quests.timer = nil
            if Quests.dirty then Quests.Refresh() end
        end)
    end
end









function Quests.List()
    if not Quests.cache or Quests.dirty then Quests.Refresh() end
    return Quests.cache
end

function Quests.Get(questID)
    questID = tonumber(questID)
    if not questID then return nil end
    Quests.List()
    return Quests.byID and Quests.byID[questID] or nil
end












Quests.PICKUP_LIMIT = 50

local function pickupNotes(create)
    local char = FGPS.DB and FGPS.DB.char
    if type(char) ~= "table" then return nil end
    if type(char.questPickups) ~= "table" then
        if not create then return nil end
        char.questPickups = {}
    end
    return char.questPickups
end






function Quests.NotePickup(questID)
    questID = tonumber(questID)
    local pos = playerPos()
    local notes = pickupNotes(true)
    if not (questID and notes and pos and type(pos.inst) == "number" and type(pos.x) == "number" and type(pos.y) == "number") then return false end
    notes[questID] = { inst = pos.inst, x = pos.x, y = pos.y }
    local count = 0
    for _ in pairs(notes) do count = count + 1 end
    if count > Quests.PICKUP_LIMIT and Quests.byID then
        for id in pairs(notes) do
            if id ~= questID and not Quests.byID[id] then notes[id] = nil end
        end
    end
    return true
end

function Quests.DropPickup(questID)
    questID = tonumber(questID)
    local notes = pickupNotes(false)
    if not (questID and notes and notes[questID]) then return false end
    notes[questID] = nil
    return true
end



local function pickupOf(questID)
    local notes = pickupNotes(false)
    local note = notes and notes[questID]
    if type(note) ~= "table" or type(note.inst) ~= "number" or type(note.x) ~= "number" or type(note.y) ~= "number" then return nil end
    local instances = FGPS.Data and FGPS.Data.instances
    local record = type(instances) == "table" and instances[note.inst] or nil
    if not (type(record) == "table" and record.continentMap) then return nil end
    return note
end








local function chooseLocation(q)
    local pois, hop, interiorSeen, doors = {}, nil, false, {}
    for _, loc in ipairs(q.locations or {}) do
        if loc.interior then
            interiorSeen = true
            if loc.entrance then doors[#doors + 1] = loc end
        elseif loc.inst and loc.x and loc.y then
            if loc.source == "nextWaypoint" then hop = hop or loc else pois[#pois + 1] = loc end
        end
    end



    local inside = #pois == 0
    if inside then pois = doors end
    if #pois == 0 then
        return nil, hop, interiorSeen and "interior" or "no_location"
    end
    for _, loc in ipairs(pois) do
        if loc.waypoint then return loc end
    end
    local pos = playerPos()
    local best, bestD
    for _, loc in ipairs(pois) do
        local at = inside and loc.entrance or loc
        local d
        if pos and pos.inst == at.inst then d = dist(pos.x, pos.y, at.x, at.y) else d = 1e9 end
        if not bestD or d < bestD then best, bestD = loc, d end
    end
    return best
end






local function openAreas(q)
    local out = {}
    local bundled = q and q.bundled
    if not bundled or q.complete then return out end
    local objectives = q.objectives or {}
    local agree = (bundled.objectiveCount or 0) > 0 and bundled.objectiveCount == #objectives
    for index, area in ipairs(bundled.areas or {}) do
        local objective = agree and objectives[area.objective] or nil
        if not (objective and objective.finished) then out[#out + 1] = { index = index, area = area } end
    end
    return out
end

function Quests.OpenAreas(questID)
    return openAreas(Quests.Get(questID))
end







local function unplacedOpen(q)
    local bundled = q and q.bundled
    if not (bundled and bundled.partial) or q.complete then return false end
    local unplaced = bundled.unplaced or {}
    local objectives = q.objectives or {}
    if #unplaced == 0 or (bundled.objectiveCount or 0) == 0 or bundled.objectiveCount ~= #objectives then return true end
    for _, index in ipairs(unplaced) do
        local objective = objectives[index]
        if not (objective and objective.finished) then return true end
    end
    return false
end








local function unrecordedOpen(q)
    local bundled = q and q.bundled
    if not bundled or q.complete then return false end
    local objectives = q.objectives or {}
    if (bundled.objectiveCount or 0) == #objectives then return false end
    for _, objective in ipairs(objectives) do
        if not objective.finished then return true end
    end
    return false
end















local function nextStep(q)

    if q.failed then return nil, "failed" end
    local loc, hop, reason = chooseLocation(q)
    if loc then

        local at = loc.entrance or loc
        return { stage = "client", location = loc, inst = at.inst, x = at.x, y = at.y, map = at.map,
                 zoneName = loc.entrance and mapName(at.map) or loc.zoneName }
    end


    local bundled = reason ~= "interior" and q.bundled or nil
    if bundled then

        local QuestData = FGPS.QuestData
        local pos = QuestData.PlayerPos()
        local best, bestAt, bestD, inside = nil, nil, nil, false
        for _, entry in ipairs(openAreas(q)) do


            local at = QuestData.ReachedAt(entry.area)
            if not at then
                if entry.area.interior then inside = true end
            elseif at.y then
                local d = 1e9
                if pos and pos.inst == at.inst and pos.x and pos.y then d = dist(pos.x, pos.y, at.x, at.y) end
                if not bestD or d < bestD then best, bestAt, bestD = entry, at, d end
            end
        end
        if best then
            return { stage = "objective", areaIndex = best.index, objective = best.area.objective, inst = bestAt.inst, x = bestAt.x, y = bestAt.y,
                     map = bestAt.map, zoneName = bestAt.map and mapName(bestAt.map) or nil }
        end


        local unknown = unplacedOpen(q) or unrecordedOpen(q)



        if not inside and unknown and bundled.partial and (bundled.objectiveCount or 0) == 0 and bundled.giver then
            local at = QuestData.ReachedAt(bundled.giver)
            if at and at.y then
                return { stage = "start", inst = at.inst, x = at.x, y = at.y, map = at.map, zoneName = at.map and mapName(at.map) or nil }
            end
        end
        if inside then
            reason = "interior"
        elseif unknown then
            reason = "objective_unknown"
        end
        local turnIn = bundled.turnIn
        if not inside and not unknown and turnIn then
            local at = QuestData.ReachedAt(turnIn)
            if at and at.y then
                return { stage = "turnin", inst = at.inst, x = at.x, y = at.y, map = at.map,
                         zoneName = at.map and mapName(at.map) or nil }
            end
            if turnIn.interior then reason = "interior" end
        end
    end
    if hop then
        return { stage = "waypoint", location = hop, inst = hop.inst, x = hop.x, y = hop.y, map = hop.map, zoneName = hop.zoneName }
    end





    if q.complete and not (q.bundled and q.bundled.turnIn) and reason ~= "interior" then
        local note = pickupOf(q.questID)
        if note then
            local map = FGPS.Coords and FGPS.Coords.WorldToMap and FGPS.Coords.WorldToMap(note.inst, note.x, note.y) or nil
            return { stage = "pickup", inst = note.inst, x = note.x, y = note.y, map = map, zoneName = map and mapName(map) or nil }
        end
    end
    return nil, reason
end

function Quests.NextStep(questID)
    local q = Quests.Get(questID)
    if not q then return nil, "not_in_log" end
    return nextStep(q)
end




local function locationFor(q, handle)
    local list = q.locations or {}
    for _, loc in ipairs(list) do
        if loc.key == handle then return loc end
    end
    local i = tonumber(handle)
    if i then return list[i] end
    return nil
end





local BUNDLED_TARGET = { giver = "giver", start = "giver", turnin = "turnin", ["turn-in"] = "turnin",
                         objective = "objective" }
local function bundledHandle(handle)
    if type(handle) ~= "string" then return nil end
    local word, index = handle:match("^(%a[%a%-]*):(%d+)$")
    if not word then word = handle end
    local target = BUNDLED_TARGET[word]
    if not target then return nil end
    return target, tonumber(index) or 1
end
Quests.BundledHandle = bundledHandle






local function stamp(dest, stage, chosen)
    dest.questTarget = stage
    dest.questChosen = chosen and true or false
    dest.complete = dest.complete and true or false
    return dest
end



local function usableDestination(dest)
    return type(dest) == "table"
        and type(dest.inst) == "number"
        and type(dest.x) == "number"
        and type(dest.y) == "number"
end





local function bundledDestination(questID, target, which, chosen)
    local QuestData = FGPS.QuestData
    if not (QuestData and QuestData.DestinationFor) then return nil, "no_data" end
    local q = Quests.Get(questID)
    local dest, reason = QuestData.DestinationFor(questID, target, which)
    if not usableDestination(dest) then return nil, reason or "no_location" end
    if q then
        dest.complete = q.complete
        dest.objectiveText = q.objectiveText
    end
    return stamp(dest, target, chosen)
end






local function eventStart(questID, q)
    local QuestData = FGPS.QuestData
    local dest, reason = QuestData.DestinationFor(questID, "event")
    if not usableDestination(dest) then return nil, reason or "no_location" end
    dest.complete, dest.objectiveText = q.complete, q.objectiveText
    return stamp(dest, "objective", true)
end








function Quests.DestinationFor(questID, locationIndex)
    questID = tonumber(questID)
    if not questID then return nil, "no_quest" end
    local target, which = bundledHandle(locationIndex)
    if target then



        return bundledDestination(questID, target, which, false)
    end
    local q = Quests.Get(questID)
    if not q then return nil, "not_in_log" end
    local loc
    if locationIndex ~= nil then
        loc = locationFor(q, locationIndex)
        if not loc then return nil, "bad_location" end
        if loc.interior and not loc.entrance then return nil, "interior" end
        if not loc.entrance and not (loc.inst and loc.x and loc.y) then return nil, "no_location" end
    else
        local step, reason = nextStep(q)
        if not step then return nil, reason end
        if step.stage == "objective" then return bundledDestination(questID, "objective", step.areaIndex, true) end
        if step.stage == "turnin" then return bundledDestination(questID, "turnin", 1, true) end
        if step.stage == "start" then return eventStart(questID, q) end
        if step.stage == "pickup" then



            local dest = {
                kind = "quest", questID = questID, type = "quest", name = format(L["%s (where you picked it up)"], q.title),
                inst = step.inst, x = step.x, y = step.y, map = step.map, zoneName = step.zoneName,
                complete = q.complete, source = "pickup", objectiveText = q.objectiveText,
            }
            local D = FGPS.Destinations
            if D and D.ApplyReachability then D.ApplyReachability(dest) end
            if not usableDestination(dest) then return nil, "no_location" end
            return stamp(dest, "turnin", true)
        end
        loc = step.location
    end


    local isHop = loc.source == "nextWaypoint"
    local dest
    local door = loc.entrance
    if door then



        dest = {
            kind = "quest", questID = questID, name = format(L["%s, at the entrance of %s"], q.title, tostring(door.name)), type = "quest",
            inst = door.inst, x = door.x, y = door.y, map = door.map, zoneName = mapName(door.map),
            complete = q.complete, source = loc.source, locationIndex = loc.index, locationKey = loc.key,
            objectiveText = loc.objectiveText,
            entrance = { name = door.name, inst = door.inst, x = door.x, y = door.y, map = door.map },
            interior = { inst = door.instanceMap, map = loc.map },
        }
    else
        dest = {
            kind = "quest", questID = questID, name = isHop and format(L["%s (next waypoint)"], q.title) or q.title, type = "quest",
            inst = loc.inst, x = loc.x, y = loc.y, map = loc.map, mx = loc.mx, my = loc.my, zoneName = loc.zoneName or mapName(loc.map),
            complete = q.complete, source = loc.source, locationIndex = loc.index, locationKey = loc.key,
            objectiveText = loc.objectiveText,
        }
    end
    local D = FGPS.Destinations
    if D and D.ApplyReachability then D.ApplyReachability(dest) end
    if not usableDestination(dest) then return nil, "no_location" end


    dest.finishedCount = finishedCount(q)
    return stamp(dest, "client", locationIndex == nil)
end


local REASON_TEXT = {
    no_quest = "no quest was given",
    not_in_log = "this quest is not in your quest log",
    no_location = "no map location is known for this quest",
    interior = "the objective is inside a dungeon or building; navigate to its entrance instead",
    bad_location = "that quest location is no longer listed",
    none = "no quest is being tracked",
    no_api = "quest tracking is not available in this client",
    no_data = "the bundled quest records are not installed in this copy of Cabbie",
    objective_unknown = "objective place not known: the 1.12 records do not say where it is found, and the client names no position from here",
    failed = "this quest has failed",
}
function Quests.ReasonText(code)
    if code == "no_path" then return L.ROUTE_NO_PATH end
    return L[REASON_TEXT[code] or REASON_TEXT.no_location]
end




function Quests.HandInKnown(questID)
    local q = Quests.Get(questID)
    local turnIn = q and q.bundled and q.bundled.turnIn
    local QuestData = FGPS.QuestData
    if not (turnIn and QuestData and QuestData.Routable) then return false end
    local ok, routable = pcall(QuestData.Routable, turnIn)
    return ok and routable == true
end

function Quests.SuperTrackedDestination()
    if not (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID) then return nil, "no_api" end
    local ok, questID = pcall(C_SuperTrack.GetSuperTrackedQuestID)
    if not ok or type(questID) ~= "number" or questID == 0 then return nil, "none" end
    return Quests.DestinationFor(questID)
end




























local SAME_STOP_YARDS = 5
local STAGES = { client = true, objective = true, turnin = true, giver = true }




function questStops()
    local Navigator = FGPS.Navigator
    local out = {}
    if not (Navigator and Navigator.StopCount and Navigator.GetStops) then return out, nil end
    if Navigator:StopCount() == 0 then return out, Navigator end
    for index, stop in ipairs(Navigator:GetStops()) do
        if type(stop) == "table" and stop.kind == "quest" and type(stop.questID) == "number" then
            out[#out + 1] = { index = index, stop = stop }
        end
    end
    return out, Navigator
end





function Quests.FollowsMine()
    local s = FGPS.DB and FGPS.DB.settings
    return not (s and type(s.quests) == "table" and s.quests.followProgress == false)
end


function Quests.SetFollowsMine(on)
    local DB = FGPS.DB
    if not (DB and DB.Set and DB.settings) then return false end
    DB:Set("quests.followProgress", on and true or false)
    return true
end




function Quests.IsQuestRoute()
    local stops, Navigator = questStops()
    return #stops > 0 and Navigator:StopCount() == #stops
end



local function stageOf(stop)
    local stage = stop.questTarget
    if type(stage) == "string" and STAGES[stage] then return stage end
    return nil
end
















Quests.STAY_YARDS = 150

function Quests.StaysAt(stop)
    if type(stop) ~= "table" or stop.kind ~= "quest" or stop.questChosen ~= true or stop.source == "nextWaypoint" then return nil end
    local stage = stageOf(stop)
    if stage ~= "client" and stage ~= "objective" then return nil end
    if not Quests.FollowsMine() then return nil end
    local q = Quests.byID and Quests.byID[stop.questID]
    if not q or q.complete or q.failed then return nil end




    if stage == "objective" and stop.objectiveIndex == nil and stop.areaIndex == nil then return huge end
    return Quests.STAY_YARDS
end



local function endStop(Navigator, index)
    if Navigator:StopCount() <= 1 then
        Navigator:Cancel("quest")
    else
        Navigator:RemoveStop(index)
    end
end








local function replaceStop(Navigator, index, dest)
    local count = Navigator:StopCount()
    if count <= 1 then


        Navigator:SetDestination(dest, { start = false, quiet = true, askedBy = "navigator" })
        return
    end
    local D = FGPS.Destinations
    for i, other in ipairs(Navigator:GetStops()) do
        if i ~= index and D and D.Equal and D.Equal(other, dest) then
            Navigator:RemoveStop(index)
            return
        end
    end
    Navigator:SetDestination(dest, { addStop = true, start = false, quiet = true, askedBy = "navigator" })
    Navigator:RemoveStop(index)

    if index < count then Navigator:MoveStop(count, index) end
end








local function tell(fmt, ...)
    local Guide = FGPS.UI and FGPS.UI.Guide
    if not (Guide and Guide.Tell) then return end
    local ok, err = pcall(Guide.Tell, FGPS.Util.SafeFormat(fmt, ...), Quests.NEWS_HOLD)
    if not ok and FGPS.Log and FGPS.Log.Error then FGPS.Log:Error("Quests: the guide could not tell a line: %s", tostring(err)) end
end




function Quests.OnQuestChanged(questID, accepted)
    questID = tonumber(questID)
    if not questID then return false end
    local stops, Navigator = questStops()
    local ended = false
    local mine = { [questID] = true }
    local QuestData = FGPS.QuestData
    if #stops > 0 and QuestData and QuestData.OlderVersions then
        for _, old in ipairs(QuestData.OlderVersions(questID)) do mine[old] = true end
    end

    for i = #stops, 1, -1 do
        local stop, index = stops[i].stop, stops[i].index
        if mine[stop.questID] and (not accepted or stageOf(stop) == "giver") then
            endStop(Navigator, index)
            if accepted then
                tell(L["%s is in your quest log now, so the route to where it starts has ended."], tostring(stop.name or questID))
            else
                tell(L["%s has left your quest log, so the route to it has ended."], tostring(stop.name or questID))
            end
            ended = true
        end
    end
    return ended
end



local function stageDone(q, stop, stage)
    local completed = q.complete and not stop.complete
    if completed then return true, true end
    if stage == "objective" and stop.objectiveIndex then


        for _, entry in ipairs(openAreas(q)) do
            if entry.area.objective == stop.objectiveIndex then return false, false end
        end
        return true, false
    end
    if stage == "client" then















        local sx, sy = stop.originalX or stop.x, stop.originalY or stop.y
        if type(sx) ~= "number" or type(sy) ~= "number" then return false, false end
        local still, elsewhere = false, false
        for _, loc in ipairs(q.outdoor or {}) do
            if loc.source == "poi" then
                if loc.inst == stop.inst and dist(loc.x, loc.y, sx, sy) <= SAME_PLACE_YARDS then still = true break end
                elsewhere = true
            end
        end
        local read = Quests.mapsRead ~= nil and Quests.mapsRead[stop.map] ~= nil
        local further = type(stop.finishedCount) == "number" and finishedCount(q) > stop.finishedCount
        return (not still and read and (elsewhere or further)) and true or false, false
    end
    return false, false
end



local function resolvedAgain(stop)
    if stop.questChosen == true then return Quests.DestinationFor(stop.questID) end
    if stop.areaIndex then return Quests.DestinationFor(stop.questID, "objective:" .. tostring(stop.areaIndex)) end
    return nil
end

local function sameStop(dest, stop)
    return dest.inst == stop.inst and dist(dest.x, dest.y, stop.x, stop.y) <= SAME_STOP_YARDS
end







local function leftTheLog(questID)
    if not (C_QuestLog and C_QuestLog.IsOnQuest) then return false end
    local ok, on = pcall(C_QuestLog.IsOnQuest, questID)
    return ok and not isSecret(on) and on == false
end


function Quests.FollowProgress()
    local stops, Navigator = questStops()
    local failedOne = false











    local logRead = Quests.cache ~= nil and #Quests.cache > 0
    for i = #stops, 1, -1 do
        local stop = stops[i].stop
        local q = Quests.byID and Quests.byID[stop.questID]
        local stage = stageOf(stop)
        if q and q.failed then
            endStop(Navigator, stops[i].index)
            tell(L["%s has failed, so the route to it has ended."], q.title)
            failedOne = true
        elseif not q and logRead and stage and stage ~= "giver" and (stop.questChosen == true or stage == "client")
            and leftTheLog(stop.questID) then
            endStop(Navigator, stops[i].index)
            tell(L["%s has left your quest log, so the route to it has ended."], tostring(stop.name or stop.questID))
            failedOne = true
        end
    end
    if not Quests.FollowsMine() then return failedOne end

    if failedOne then stops, Navigator = questStops() end





    local pos = playerPos()
    local inst = pos and pos.inst
    local before = Quests.lastInst
    local arrived = inst ~= nil and before ~= nil and inst ~= before
    if inst ~= nil then Quests.lastInst = inst end


    local waiting = false
    local changed = failedOne


    for i = #stops, 1, -1 do
        local stop, index = stops[i].stop, stops[i].index
        local stage = stageOf(stop)
        local q = Quests.byID and Quests.byID[stop.questID]
        local done, completed = false, false
        if q and stage and stop.questChosen == true and stage ~= "turnin" and stage ~= "giver"
            and type(stop.x) == "number" and type(stop.y) == "number" then
            done, completed = stageDone(q, stop, stage)
            if done then
                local dest, reason = Quests.DestinationFor(stop.questID)
                if dest and not usableDestination(dest) then
                    dest, reason = nil, reason or "no_location"
                end
                if dest and not sameStop(dest, stop) then


                    replaceStop(Navigator, index, dest)
                    changed = true
                elseif not dest then





                    endStop(Navigator, index)
                    if reason == "objective_unknown" then
                        tell(L["%s: that objective is done. Where the next one is found is not known, so the route to it has ended."], q.title)
                    elseif completed then
                        tell(L["%s is complete, but no route can lead to where it is handed in: %s. The route to it has ended."], q.title, Quests.ReasonText(reason))
                    else
                        tell(L["%s: that objective is done, but no route can lead to the next step: %s. The route to it has ended."], q.title, Quests.ReasonText(reason))
                    end
                    changed = true
                end
            end
        end


        if not done and arrived and stage == "objective" and stop.inst == inst
            and type(stop.x) == "number" and type(stop.y) == "number" then
            if stop.questChosen == true and not q then
                waiting = true
            else
                local dest = resolvedAgain(stop)
                if dest and not sameStop(dest, stop) then
                    replaceStop(Navigator, index, dest)
                    changed = true
                end
            end
        end
    end

    if waiting then Quests.lastInst = before end
    return changed
end







function Quests.DropLegacyRecord()
    local char = FGPS.DB and FGPS.DB.char
    if type(char) == "table" then char.questRoute = nil end
end

function Quests:Init()
    if self.initialised then return end
    self.initialised = true
    local function invalidate() Quests.Invalidate() end
    for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_POI_UPDATE", "SUPER_TRACKING_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" }) do
        Events:RegisterWoW(event, invalidate, self)
    end
    Events:RegisterWoW("ZONE_CHANGED_NEW_AREA", invalidate, self)


    Events:RegisterWoW("QUEST_ACCEPTED", function(_, a, b)
        local questID = tonumber(b) or tonumber(a)
        Quests.NotePickup(questID)
        Quests.OnQuestChanged(questID, true)
    end, self)
    local function left(_, questID)
        Quests.DropPickup(questID)
        Quests.OnQuestChanged(questID, false)
    end
    Events:RegisterWoW("QUEST_TURNED_IN", left, self)
    Events:RegisterWoW("QUEST_REMOVED", left, self)

    Events:Register("SETTINGS_CHANGED", function(_, key)
        if key == "quests.followProgress" or key == "*" then recheckStay() end
    end, self)
    Quests.DropLegacyRecord()
end
