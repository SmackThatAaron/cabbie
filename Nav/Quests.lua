-- Cabbie/Nav/Quests.lua
-- Quest log access for navigation. Quests are read live from C_QuestLog (the build has no useful
-- QuestPOI tables). The list is cached; QUEST_LOG_UPDATE, QUEST_POI_UPDATE, SUPER_TRACKING_CHANGED
-- and friends only mark it stale, and it is rebuilt when somebody asks for it (List, Get,
-- DestinationFor). A refresh is pushed (QUESTS_UPDATED, at most once per second) only while some
-- module listens to that event or a quest stop is set.
-- Locations come from GetQuestsOnMap for the player's map, for the map the quest log currently
-- shows POIs for and, failing both, for the quest's own map, plus C_QuestLog.GetNextWaypoint, the
-- client's own "next step" hint. A hint that coincides with a POI marks the objective the client
-- points at and that POI is preferred. A hint
-- anywhere else is an intermediate hop on the client's own way to the quest (a zone exit, a dock,
-- a portal); this addon routes across zones and continents by itself, so such a hint is used only
-- when no POI is known, and the destination then says so ("next waypoint") instead of posing as
-- the quest itself. A location on a dungeon-type map is a position inside, which no route reaches:
-- it is gone to through the dungeon's recorded door (Data/Interiors.lua) when nothing outdoors is
-- reported, with a name that says so, and it is refused with the reason "interior" when no door is
-- recorded. Among several outdoor POIs the nearest by straight line wins unless the caller names
-- one (DestinationFor(questID, locationIndex)).
--
-- What the client answers for is always preferred, because it is this build speaking about itself.
-- What it does not answer for is where a quest was given and where it is handed in, and those are
-- the two ends of the journey. Nav/QuestData.lua has both from the bundled 1.12 records (and, for
-- 22 of Forever's own quests, from the client's own tables, shipped in the Forever layer), so each
-- quest also carries q.bundled: the giver, the turn-in, the measured objective areas and the marks
-- that say how much any of it is worth. It is kept apart from q.locations on purpose, so that no
-- caller can mistake a 1.12 record for something the client said. DestinationFor routes to a
-- stage of it through the handles "giver", "turnin" and "objective:<n>".
--
-- The client answers for the map it is asked about, and the only maps this module used to name
-- were the one the player stands on and the one the quest log happens to show. Standing in
-- Orgrimmar with three quests in Tirisfal Glades that was nothing at all, and "no map location is
-- known" was the answer for every one of them. Two things answer now. A quest none of those maps
-- knows is looked up on its own map (GetQuestUiMapID), which is the only source there is for a
-- quest the dataset has no record of, or a partial record with no place for the objective. (1821
-- "Agamand Heirlooms" was such a quest until the builder learned to find its weapon racks.) And
-- the next thing to do
-- (Quests.NextStep, and DestinationFor without a handle) falls back to the bundled record when the
-- client has no position: the nearest objective area that is still open, else where the quest is
-- handed in, and never the giver of a quest that is already in the log. The destination keeps
-- source = "bundled" and its stage in the name, so it never poses as something the client said.
--
-- Some records are partial rows: the giver and the turn-in are known and an objective has no known
-- place (docs/QUEST_DATASET.md section 3.1). While such an objective may be open and the client
-- names no position either, there is no next step at all: the reason is "objective_unknown", the
-- words are "objective place not known", and the quest is never walked to a turn-in that will
-- not take it. Once the quest is complete the turn-in is the next step like for any other. An
-- escort or a scripted event is such a row too: its record lists nothing to kill, use or collect,
-- which is what a delivery looks like, and the builder marks it from the flag that says the quest
-- is completed by an event. Such a row does have somewhere to go while it is not done: an escort
-- begins where the quest is given, so the next step is that place, named "<quest> (where it
-- starts)" (nextStep's stage "start"). "objective_unknown" is also the answer when the client
-- lists an unfinished objective the record has no entry for (unrecordedOpen), whatever the builder
-- marked.
--
-- A route to a quest follows what happens to the quest (the last section of this file): a quest
-- stop ends when the client says the quest was handed in or removed, and it moves on when the
-- stage it led to is done, whether it is the only stop of a journey or one of several.
local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Events = FGPS.Events
local sqrt, floor, type, pairs, ipairs, tonumber, tostring, format = math.sqrt, math.floor, type, pairs, ipairs, tonumber, tostring, string.format
local huge = math.huge

local Quests = {
    THROTTLE_SECONDS = 1,
    NEWS_HOLD = 8,               -- seconds the call-out says what became of a route to a quest
    cache = nil,
    byID = nil,
    dirty = true,
    lastRefresh = -1e9,
    timer = nil,
    order = nil,                 -- questID -> list of location keys, in the order of the last build
    lastInst = nil,              -- the continent the player stood on at the last rebuild (FollowProgress)
}
FGPS.Quests = Quests

local DUNGEON_MAP_TYPE = 4   -- Enum.UIMapType.Dungeon

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

-- True when the map is a dungeon / interior floor (positions there are not routable outdoors).
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

-------------------------------------------------------------------------------
-- Location helpers
-------------------------------------------------------------------------------
-- The client marks what GetQuestsOnMap and GetNextWaypoint return as secret when the calling code
-- is tainted (warcraft.wiki.gg: SecretWhenTainted / AllowedWhenUntainted). A secret number still
-- says "number" to type(), and the first comparison or sum with it raises an error, which inside
-- Quests.Refresh would cost the player the whole quest list. A value the client will not let this
-- addon read is a value the client did not give: the quest then has no position from the client,
-- and everything that answers for a silent client (the bundled record, "place not known") applies.
-- Same test as Coords.IsSecret; nil-guarded because only the 12.x clients have the function.
local function isSecret(value)
    return value ~= nil and issecretvalue ~= nil and issecretvalue(value) == true
end

-- The recorded door of the dungeon a map belongs to, as { name, inst, x, y, map, instanceMap }, or
-- nil. Which instance a dungeon's map shows is the client's to say: Nav/Coords.lua answers when
-- it knows the map, else the "continent" C_Map.GetWorldPosFromMapPos names for it, which for a
-- dungeon is its instance. The door is Cabbie's own record (Data/Interiors.lua), the one the
-- bundled record's path leads to for an objective inside (QuestData.EntranceFor): the game says
-- that the place is in that dungeon, and the record says where the dungeon is entered.
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
        -- No place of its own that a route could end at; the door of the dungeon when that is
        -- recorded (loc.entrance), which is as far as a route can lead.
        loc.interior = true
        loc.entrance = entranceOfMap(mapID)
        return loc
    end
    local inst, x, y = mapToWorld(mapID, mx, my)
    if inst then loc.inst, loc.x, loc.y = inst, x, y end
    return loc
end

-- Two reports of one place. The client reports a quest once per map it is asked about, so with the
-- world map open on the continent the same objective arrives a second time in the continent's
-- coordinates: two rows and two "Go" buttons for one place. Reports on different maps are
-- therefore compared where they meet, in world yards. The first report is the one that is kept,
-- and the maps are read finest first (see mapReader).
local SAME_PLACE_YARDS = 25

local function sameLocation(a, b)
    local world = a.inst and b.inst and a.x and b.x and a.y and b.y
    -- On one map the fraction is a fallback only: 0.002 of a continent map is some 80 yd, and two
    -- objectives a short walk apart were one row.
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

-- Quest POIs of a map grouped by questID (one call per map).
local function poisByQuest(mapID)
    local out = {}
    if not mapID or not (C_QuestLog and C_QuestLog.GetQuestsOnMap) then return out end
    local ok, list = pcall(C_QuestLog.GetQuestsOnMap, mapID)
    if not ok or type(list) ~= "table" then return out end
    for _, info in ipairs(list) do
        -- A secret quest identifier cannot be a table key and a secret map cannot be tested, so
        -- such an entry is left out whole; secret coordinates are left to makeLocation.
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

-- The client's own objectives, with the progress it reports. The counts are kept rather than
-- dropped: "3 of 10" is the one part of a quest's state that only the client can answer, and the
-- panel and the pins both want it. A count that is a secret value (the client may restrict unit
-- statistics) is left out rather than compared.
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

-- How many of a quest's objectives the client reports finished.
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

-- Whether the client calls the quest failed: a timed quest that ran out, an escort that died. Such
-- a quest stays in the log until the player drops it, and nothing of it can be done any more. A
-- client that cannot say (no such function, a value it will not let this addon read) has no
-- failed quest as far as this module is concerned.
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

-- The map a quest belongs to, as the client names it, or nil. This is what lets a quest be found
-- from another continent: GetQuestsOnMap answers for whichever map it is asked about, and until
-- this was asked the only maps ever named were the player's own and the one the quest log shows.
-- The function is a plain global of the client (it is in the captured Forever baseline and in
-- .luacheckrc), read like every other client function in this file: by its name, behind a nil
-- test, so that a client without it is simply a client that cannot say.
--
-- The second argument is ignoreWaypoints (warcraft.wiki.gg, GetQuestUiMapID). Without it the
-- client names the map of its next waypoint whenever it has one, and for a quest on another
-- continent that is the map of the zeppelin tower the player is standing next to: a map the quest
-- is not placed on, asked about in exactly the case this lookup exists for. Only when the client
-- has no answer with the flag set is the plain question asked, for a client that reads the flag
-- differently; a waypoint's map is still better than no map.
local function usableMapID(ok, id)
    if not ok or type(id) ~= "number" or (issecretvalue and issecretvalue(id)) or id <= 0 then return nil end
    return id
end

local function questOwnMap(questID)
    if type(GetQuestUiMapID) ~= "function" then return nil end
    return usableMapID(pcall(GetQuestUiMapID, questID, true)) or usableMapID(pcall(GetQuestUiMapID, questID))
end

-- Reads each map's quest POIs at most once per rebuild of the list. `always` are the maps every
-- quest is looked up on, finest first: the player's own map, then the map the quest log shows.
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

-- Collects the locations of one quest: map POIs first, then the client's next-waypoint hint. A hint
-- on top of a POI marks that POI (waypoint = true); a hint elsewhere becomes a location of its own
-- with source "nextWaypoint" (an intermediate hop, or the only thing known about the quest).
-- A quest none of the usual maps answered for is looked up on its own map: one more client call
-- for the quest, and one more map read for every distinct map such quests belong to.
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

-- What there is to do at the quest's locations: "Ready to turn in" for a complete quest, otherwise
-- the unfinished objectives ("0/10 Kobolds slain; 2/5 Candles"). Returns text|nil, finished.
local function objectiveSummary(q)
    if q.complete then return L["Ready to turn in"], true end
    local open = {}
    for _, o in ipairs(q.objectives or {}) do
        if not o.finished and type(o.text) == "string" and o.text ~= "" then open[#open + 1] = o.text end
    end
    if #open == 0 then return nil, false end
    return table.concat(open, "; "), false
end

-- A handle for one location that does not depend on where the player is standing. The client only
-- reports quest POIs for the map it is showing, so both the membership and the order of
-- q.locations change with the zone; anything that remembers a position in that list (the Search
-- window stores one when it draws a row and resolves it when the row is clicked) would otherwise
-- resolve to a different place after a zone change.
local function locationKey(loc)
    return format("%d:%d:%d", loc.map or 0, floor((loc.mx or 0) * 1000), floor((loc.my or 0) * 1000))
end
Quests.LocationKey = locationKey

-- Puts the locations of one quest back into the order of the previous build wherever the same
-- keys are still there, and appends the rest. Positions in the list therefore survive a rebuild
-- that only reorders or adds locations, which is what a zone change does. `nextOrder` collects the
-- keys of this build; Quests.Refresh swaps it in when the whole list is built.
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

-- Fills in what a list (one row per location) needs: every location gets its stable key, its index
-- (both are accepted as the locationIndex of DestinationFor), zone name, outdoor flag, objective
-- text and finished state; q.outdoor lists the routable ones. The client does not say which
-- objective belongs to which POI, so the objective text is the quest's open objectives for every
-- POI; a bare next-waypoint hop carries the client's waypoint text instead.
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

-------------------------------------------------------------------------------
-- The bundled record behind an accepted quest
-------------------------------------------------------------------------------
-- The client answers for where a quest's objectives are right now, and that answer is always
-- preferred: it is this build speaking about itself. What it does not answer for is where the
-- quest was given and where it is handed in, and those are the two ends of the journey a player
-- most often wants to route to. Nav/QuestData.lua has both from the shipped records, so they
-- are attached here as a separate block rather than mixed into q.locations: everything in
-- q.bundled shipped with Cabbie (a 1.12 record, or for 22 of Forever's own quests the places of
-- the client's own tables, block.layer "forever"), everything in q.locations is what the client
-- answered while the player plays, and no caller can confuse the two. A Forever row is attached
-- only when it says where the quest is handed in or where its objectives are done (the client's
-- own table, AllTheThings' spots): its start alone is nothing to go to for a quest that is already
-- in the log. A row with objective places and no hand-in leads to its objectives; once the quest
-- is ready, the game's own places lead to the hand-in, else where the quest was picked up
-- (nextStep's last resort), else nothing.
local function foreverBlock(QuestData, questID)
    if not QuestData.ForeverInfo then return nil end
    local ok, info = pcall(QuestData.ForeverInfo, questID)
    if not ok or type(info) ~= "table" then return nil end
    local areas = type(info.areas) == "table" and info.areas or {}
    if not info.turnIn and #areas == 0 then return nil end
    -- The objectives the sources number: the client's table in the client's own order, and
    -- AllTheThings in its own numbering, which is taken to be the client's (seen to agree on the
    -- few quests both place, 92742 and 92745 for the order; inferred for the rest); 0 when they
    -- place none, and then an objective the client lists open has no known place. A number up to that count with no place of its own is an objective nobody places,
    -- as an unplaced objective of a partial 1.12 row is.
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
        -- How many objectives the 1.12 record has. Forever rewrote some quests, so an objective of
        -- the record is only matched to one of the client's when both lists are the same length.
        objectiveCount = (okCount and type(objectiveCount) == "number") and objectiveCount or 0,
        unverified = (info.mark or 0) <= 0,
        -- A partial row: both ends of the journey are known and an objective has no place. Which
        -- objectives those are is only worked out for such a row (one in seven of the dataset).
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

-------------------------------------------------------------------------------
-- Cache
-------------------------------------------------------------------------------
local function questPOIMap()
    if C_QuestLog and C_QuestLog.GetMapForQuestPOIs then
        local ok, id = pcall(C_QuestLog.GetMapForQuestPOIs)
        if ok and type(id) == "number" and id > 0 then return id end
    end
    return nil
end

-- The name of a quest in the log: what the client says, else what this character has already
-- seen (the saved names behind QuestData.Title), else a stand-in. The second value says whether it
-- is a real name, because a stand-in must never be written into the saved names as if it were one.
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
        -- A quest the log lists twice is one quest: a second entry would be a second row, a second
        -- set of pins and a second "Go" for the same thing.
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

-- What this module answers for the place a route stays at (Quests.StaysAt) may have changed: the
-- navigator is asked to look again, and lets go of a place that is no longer held
-- (Navigator:RecheckStay). Under pcall: a raise there must not cost the rest of a rebuild.
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
    -- The order memory is replaced wholesale, so it only ever holds the quests of the current log.
    local order, mapsRead
    Quests.cache, Quests.byID, order, mapsRead = buildList()
    Quests.order = order
    -- Which maps the client was asked about in this build (map -> what it listed). The route
    -- follow-up needs it: "the quest is not marked on this map" only means something for a map
    -- that was read. It is the reader's own table, so keeping it costs nothing.
    Quests.mapsRead = mapsRead or {}
    Quests.dirty = false
    Quests.lastRefresh = now()
    Events:Fire("QUESTS_UPDATED", #Quests.cache)
    -- The list is whole and announced; now a route that leads to a finished stage can move on.
    local ok, err = pcall(Quests.FollowProgress)
    if not ok and FGPS.Log then FGPS.Log:Error("Quests.FollowProgress failed: %s", tostring(err)) end
    -- And a place the route stays at that is held no longer (the quest is ready and the game's
    -- marker did not move) is let go of.
    recheckStay()
    return Quests.cache
end

local questStops                       -- the quest stops that are set; defined with the follow-up, below

-- Marks the cache stale. Nothing is rebuilt here: the quest events arrive in bursts while questing
-- (kills, loot, zone changes, login) and a rebuild costs several client calls per quest, while the
-- list is only needed when somebody asks for it; List / Get / DestinationFor rebuild a stale cache
-- on demand. A refresh is pushed (now, or within the throttle window once it expires) while some
-- module listens to QUESTS_UPDATED, and while a quest stop is set: a route moves on with its quest
-- at a rebuild (FollowProgress), and it must not hang on whoever else happens to listen.
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

-- The quest list, rebuilt first when it is stale (a pending pushed refresh is overtaken).
-- Entries: { questID, title, titleKnown, logIndex, level, complete, onMap,
--            objectives = { { text, finished, type, have, need } }, objectiveText, finished,
--            locations = { loc }, outdoor = { loc }, bundled = the 1.12 record | nil } with
-- loc = { key, index, map, mx, my, inst?, x?, y?, zoneName, source = "poi"|"nextWaypoint", waypoint?,
--         interior?, outdoor, objectiveText, finished }. q.outdoor holds the routable locations;
-- Quests.DestinationFor accepts either loc.key (stable across rebuilds: keep this one when a row
-- is drawn now and resolved later) or loc.index (its position in this list).
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

-------------------------------------------------------------------------------
-- Where a quest was picked up
-------------------------------------------------------------------------------
-- One small note of Cabbie's own for each quest that is in the log: where the character stood
-- when the quest was accepted. Instance and position, nothing else, kept per character
-- (CabbieCharDB.questPickups[questID] = { inst, x, y }) and dropped when the client says that the
-- quest left the log. It is the last resort for the hand-in of a quest nothing else places
-- (nextStep's stage "pickup"), and it is named for what it is, "<quest> (where you picked it
-- up)": many quests are handed in where they were given, and many are not.
-- It is a note about the player's own quest log. It is no record of the world: it corrects
-- nothing, is compared with nothing and outlives nothing.
Quests.PICKUP_LIMIT = 50     -- more notes than a quest log holds: some are leftovers (see NotePickup)

local function pickupNotes(create)
    local char = FGPS.DB and FGPS.DB.char
    if type(char) ~= "table" then return nil end
    if type(char.questPickups) ~= "table" then
        if not create then return nil end
        char.questPickups = {}
    end
    return char.questPickups
end

-- The client said that a quest was accepted: note where the character stands. Without a position
-- (inside some instances) nothing is noted, and nothing is invented for it later.
-- The notes go with their quests (DropPickup). Should that word have been missed (the addon was
-- switched off when a quest was dropped), there are in time more notes than a quest log can
-- hold; those of quests that are not in the log as it was read last are leftovers and go.
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

-- Where the quest was picked up, as a place a route can lead to: { inst, x, y }, or nil. A note
-- taken somewhere routes do not reach (inside a dungeon, on the tram) is not such a place.
local function pickupOf(questID)
    local notes = pickupNotes(false)
    local note = notes and notes[questID]
    if type(note) ~= "table" or type(note.inst) ~= "number" or type(note.x) ~= "number" or type(note.y) ~= "number" then return nil end
    local instances = FGPS.Data and FGPS.Data.instances
    local record = type(instances) == "table" and instances[note.inst] or nil
    if not (type(record) == "table" and record.continentMap) then return nil end
    return note
end

-------------------------------------------------------------------------------
-- Destinations
-------------------------------------------------------------------------------
-- Picks the best routable location the client reports: the POI its next-waypoint hint points at,
-- else the nearest outdoor POI (same instance first). A bare next-waypoint hop is returned apart
-- from it, because a known objective of the bundled record beats a hop (see nextStep).
-- Returns location | nil, hop | nil, reason.
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
    -- Nothing outdoors: a place inside a dungeon whose door is recorded is gone to through that
    -- door (the nearest door, when the game marks the quest in several dungeons). It used to be
    -- refused outright, and the bundled record with it. A dungeon with no recorded door still is.
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

-- The objective areas of the bundled record that are still somewhere to go, as
-- { index = position in q.bundled.areas (what "objective:<n>" takes), area = the area }.
-- A complete quest has none. An area is dropped when the client reports its objective finished,
-- and only when the record and the client list the same number of objectives: Forever rewrote
-- some quests, and dropping an area on a guess would send the player past work that is still open.
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

-- True while an objective of a partial row that has no known place may still be open. A complete
-- quest has nothing open. Otherwise the client's own list decides, and only when it can be matched
-- one for one with the record's (the same rule openAreas follows): every objective without a place
-- reported finished means what is left needs no place. A list that cannot be matched is never
-- read as "done", because the mistake on that side walks the player to a turn-in that will not
-- take the quest.
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

-- True while the client lists an unfinished objective the record has no entry for. The builder
-- marks an escort or a scripted event as a partial row, because its 1.12 record lists nothing to
-- kill, use or collect and would otherwise read as a delivery. This is the same doubt for the rows
-- the builder cannot know about: a quest Forever gave an objective the 1.12 record never had. The
-- two lists cannot be matched then, what is open has no place in the record, and a walk to the
-- turn-in is a walk to somebody who will not take the quest. A record whose list does match the
-- client's is left to openAreas, and a client that lists nothing open is believed.
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

-- The next thing to do for an accepted quest, without asking the graph anything, so a list can
-- call it for every row. What the client reports comes first; the bundled record answers when the
-- client is silent, which it is whenever the quest is not on the player's own map; a bare hop of
-- the client is the last resort. The giver is never an answer: the quest is already in the log.
-- The turn-in is an answer for a complete quest and for a record in which nothing needs a place (a
-- delivery, a "speak to"). It is never an answer while an objective of a partial row may be open:
-- nobody knows where that objective is, and the honest reply is the reason "objective_unknown"
-- ("objective place not known") with nowhere to go, not a walk to somebody who will say "come
-- back when you have it".
--   step = { stage = "client" | "objective" | "turnin" | "start" | "waypoint", inst, x, y, map, zoneName,
--            location = the client location | nil, areaIndex = n | nil, objective = n | nil }
-- "start" is where an escort or a scripted event begins (the record's giver), for a row that
-- lists nothing to do and is flagged all the same.
-- Returns step, or nil plus a reason code.
local function nextStep(q)
    -- A failed quest has no next thing to do: whatever was to be done can no longer be done.
    if q.failed then return nil, "failed" end
    local loc, hop, reason = chooseLocation(q)
    if loc then
        -- A place inside a dungeon is where its door is, as far as going there is concerned.
        local at = loc.entrance or loc
        return { stage = "client", location = loc, inst = at.inst, x = at.x, y = at.y, map = at.map,
                 zoneName = loc.entrance and mapName(at.map) or loc.zoneName }
    end
    -- "It is inside a dungeon" is the client speaking about this build, and it is not overruled by
    -- a 1.12 record that remembers the objective somewhere outdoors.
    local bundled = reason ~= "interior" and q.bundled or nil
    if bundled then
        -- The record came from Nav/QuestData.lua (bundledFor), so the module is there.
        local QuestData = FGPS.QuestData
        local pos = QuestData.PlayerPos()
        local best, bestAt, bestD, inside = nil, nil, nil, false
        for _, entry in ipairs(openAreas(q)) do
            -- An area inside a dungeon is gone to through the dungeon's entrance and is measured
            -- from there, like any other place to go.
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
        -- Everything that is left is inside a dungeon whose entrance is not known: say so instead
        -- of walking to the turn-in of a quest that is not done.
        local unknown = unplacedOpen(q) or unrecordedOpen(q)
        -- An escort or a scripted event: a row the builder flagged although it lists nothing to
        -- kill, use or collect. Where it is done nobody recorded, but it does begin where the
        -- quest is given, and that is somewhere to go while it is not done.
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
    -- The last resort, for the hand-in alone: a quest that is ready, whose record names no hand-in
    -- (Cabbie has no record of it, or a one-ended record with only the giver) and for which the
    -- game names no place at all. Where it was picked up is somewhere it may be handed in, and it
    -- is offered under that name and no other. Not when the game said that the place is inside a
    -- dungeon: that is an answer, and this would contradict it.
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

-- Finds the location a caller named. `handle` is either the stable key (loc.key, which survives a
-- rebuild and is what a UI that remembers a row should keep) or a position in q.locations
-- (loc.index, which only means anything for the list as it is right now).
local function locationFor(q, handle)
    local list = q.locations or {}
    for _, loc in ipairs(list) do
        if loc.key == handle then return loc end
    end
    local i = tonumber(handle)
    if i then return list[i] end
    return nil
end

-- A handle naming one of the bundled stages rather than a client location: "giver", "turnin",
-- "objective" or "objective:3". These are the stages the client itself does not answer for, so a
-- player can route to the right place at every point of a quest and not only to whatever the
-- quest log happens to be pointing at.
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

-- Every destination handed out says what it leads to, in plain fields the navigator's copy keeps
-- (Destinations.Plain): questTarget is the stage, and questChosen is true when this module picked
-- the stage (the next thing to do) and false when the player named it; only a chosen stage is
-- ever moved on (see the last section of this file). The fields travel with the destination, so
-- asking where a quest leads without going there cannot change what an existing stop says.
local function stamp(dest, stage, chosen)
    dest.questTarget = stage
    dest.questChosen = chosen and true or false
    dest.complete = dest.complete and true or false
    return dest
end

-- A destination without a place is not a route. Callers must see a named reason, never an
-- empty destination that looks like success (experience side of engine E-0016).
local function usableDestination(dest)
    return type(dest) == "table"
        and type(dest.inst) == "number"
        and type(dest.x) == "number"
        and type(dest.y) == "number"
end

-- One stage of the bundled record as a destination. The quest log is read first on purpose: that
-- is what puts the quest's name into the saved names, and QuestData.DestinationFor names the
-- stage from those. Asked in the other order the player got "Quest 362 (turn-in)" for a quest
-- whose name the log knew all along.
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

-- Where an escort or a scripted event begins, as the next thing to do for a quest in the log
-- (nextStep's stage "start"): the place of the record's giver, named "<quest> (where it starts)".
-- The stop is of the stage "objective", because what is done from there is the quest's
-- objective: it is moved on when the quest is ready, like any objective stop. It carries no
-- objective number and no area, which is how StaysAt knows it.
local function eventStart(questID, q)
    local QuestData = FGPS.QuestData
    local dest, reason = QuestData.DestinationFor(questID, "event")
    if not usableDestination(dest) then return nil, reason or "no_location" end
    dest.complete, dest.objectiveText = q.complete, q.objectiveText
    return stamp(dest, "objective", true)
end

-- DestinationFor(questID)                 the next thing to do (see nextStep)
-- DestinationFor(questID, locationIndex)  the location the user picked: loc.key of a list entry
--                                         (stable) or loc.index (its position in q.locations), or
--                                         one of the bundled stage handles above
-- Returns dest, or nil plus a reason code: "no_quest", "not_in_log", "no_location", "interior",
-- "bad_location", "no_data", "objective_unknown" (Quests.ReasonText turns the code into a
-- sentence).
function Quests.DestinationFor(questID, locationIndex)
    questID = tonumber(questID)
    if not questID then return nil, "no_quest" end
    local target, which = bundledHandle(locationIndex)
    if target then
        -- A bundled stage is answered whether or not the quest is in the log: the search result of
        -- a quest nobody has accepted has to be routable to its start, which is the whole point of
        -- "they can search it to navigate to where to start it".
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
            -- Where the quest was picked up, standing in for a hand-in nobody places. The name
            -- says what it is, and dest.source says it to code. It stands for the hand-in, so
            -- the stop is of that stage: the route ends there and is not moved on.
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
    -- A bare next-waypoint hop is not the quest itself: the name says so, so that "You have arrived
    -- at ..." is not mistaken for reaching the objective (dest.source tells code the same).
    local isHop = loc.source == "nextWaypoint"
    local dest
    local door = loc.entrance
    if door then
        -- Inside a dungeon: the route ends at the dungeon's recorded door, and the name says so,
        -- in the words the bundled record's path uses for an objective inside. The dungeon is
        -- kept beside it (dest.interior), the door in dest.entrance, as that path keeps them.
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
    -- What was finished when the stop was made: the marker goes with its objective, and a marker
    -- gone from a map that was read, after one more objective is done, has moved on (stageDone).
    dest.finishedCount = finishedCount(q)
    return stamp(dest, "client", locationIndex == nil)
end

-- User-facing sentence for a reason code returned by DestinationFor / SuperTrackedDestination.
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

-- Whether the bundled record has a hand-in for this quest of the log that a route can lead to
-- (outdoors, or inside a dungeon whose entrance is recorded). It is what a notice may promise for
-- a quest whose open objective has no known place (UI/Menus.lua).
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

-------------------------------------------------------------------------------
-- A route to a quest follows what happens to the quest
-------------------------------------------------------------------------------
-- A route that still leads to the collect area of a quest that was handed in ten minutes ago is
-- the stale entry a player calls "messed up". Two things keep it honest, for every quest stop of
-- the itinerary: the only stop of a journey, or one stop among several. In a longer itinerary only
-- the quest stop is touched. It is moved on in its own place or taken out, and every other stop
-- and the order the player gave them stay as they are.
--
-- The stop ends when the client says the quest is gone (QUEST_TURNED_IN, QUEST_REMOVED), and the
-- stop at a giver ends when the quest is accepted. It is the client's event that decides and
-- never the quest log reading empty, because the log reads empty for a moment on every loading
-- screen and a zeppelin ride must not cost the player their route.
--
-- The stop moves on when the stage it leads to is done: the objective the client now reports
-- finished, the client's own marker once the client has moved it somewhere else, or any objective
-- once the quest is complete. Only a stage this module chose is moved;
-- one the player picked by hand stays. "Follow my quests" switched off (Quests.FollowsMine)
-- switches it off.
--
-- What a stop leads to is written on the stop itself: questTarget (the stage), questChosen (this
-- module picked the stage, as opposed to the player naming it), objectiveIndex and complete (what
-- the quest was when the stop was made). Destinations.Plain keeps all four, and the navigator
-- keeps its stops in the character's saved variables, so the follow-up survives a reload and a
-- logout with the itinerary, works for any number of stops, and cannot be disturbed by somebody
-- merely asking where a quest leads. A stop without a stage (a favourite saved by an older
-- version) is left alone, which is the safe side.
local SAME_STOP_YARDS = 5
local STAGES = { client = true, objective = true, turnin = true, giver = true }

-- Every quest stop of the itinerary, first to last, as { index = its position, stop = the stop }.
-- StopCount is asked first because GetStops copies the list and this runs on every rebuild of
-- the quest list and on every quest event (Invalidate), nearly always for an itinerary that is empty.
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

-- "Follow my quests", the one quest switch (native UI design 12.4): a route to a quest moves on
-- with the quest. It is on unless the saved setting says false. The key, quests.followProgress,
-- is older than the name and is kept, so no save has to be moved. Every module asks here and
-- none reads the setting.
function Quests.FollowsMine()
    local s = FGPS.DB and FGPS.DB.settings
    return not (s and type(s.quests) == "table" and s.quests.followProgress == false)
end

-- Switches it, as any setting is written (SETTINGS_CHANGED fires). False without saved settings.
function Quests.SetFollowsMine(on)
    local DB = FGPS.DB
    if not (DB and DB.Set and DB.settings) then return false end
    DB:Set("quests.followProgress", on and true or false)
    return true
end

-- True while what is set leads to quests and to nothing else: there are stops, and every one of
-- them is a quest stop. That is the route "Follow my quests" is about. One other stop among them
-- makes it a list the player put together, which nothing here replaces.
function Quests.IsQuestRoute()
    local stops, Navigator = questStops()
    return #stops > 0 and Navigator:StopCount() == #stops
end

-- The stage a stop leads to, or nil for a stop that does not say. Saved variables can hold
-- anything, so the value is checked before it is believed.
local function stageOf(stop)
    local stage = stop.questTarget
    if type(stage) == "string" and STAGES[stage] then return stage end
    return nil
end

-- A route that led to a quest's place used to end there, unless the place was a wide objective
-- area of the bundled record, and a route that has ended cannot move on: the marker the game
-- reports is a point, and so is one spawn of the record. The navigator asks here when a route
-- reaches its last stop (Navigator:CompleteLeg), and UI/Guide.lua asks for the line it shows
-- there. The route stays at a place this module chose, of a quest that is in the log and not
-- yet ready to hand in, while "Follow my quests" is on: FollowProgress moves such a stop on when
-- that part of the quest is done. Not at the hand-in and not where a quest starts (the walk was
-- what was asked for, and it is done), not at a place the player picked by hand (nothing moves
-- that on), and not at the game's hop on the way to a quest (the navigator asks the quest again
-- there, Navigator:NoteQuestHop).
-- The answer is how far from the place the player still counts as being there, in yards, or nil.
-- The game reports a point and no size, so the number is assumed, not measured: wide enough for
-- a camp, small enough that somebody who walked on is led back.
-- The quest list is read as it was built last. Asking for a rebuild here would run
-- FollowProgress, and with it the navigator, in the middle of the arrival it is working on.
Quests.STAY_YARDS = 150

function Quests.StaysAt(stop)
    if type(stop) ~= "table" or stop.kind ~= "quest" or stop.questChosen ~= true or stop.source == "nextWaypoint" then return nil end
    local stage = stageOf(stop)
    if stage ~= "client" and stage ~= "objective" then return nil end
    if not Quests.FollowsMine() then return nil end
    local q = Quests.byID and Quests.byID[stop.questID]
    if not q or q.complete or q.failed then return nil end
    -- Where an escort or a scripted event starts (eventStart: an objective stop with no objective
    -- number and no area): what happens next leads the player away from there, nobody recorded
    -- where to. They are with it wherever it takes them, and a route that pointed back to the
    -- start would be in the way. So it is held without a limit, until the quest is ready or gone.
    if stage == "objective" and stop.objectiveIndex == nil and stop.areaIndex == nil then return huge end
    return Quests.STAY_YARDS
end

-- Takes one quest stop out. The only stop of a journey ends the journey; one stop among several
-- leaves the others, and the navigator routes on to them.
local function endStop(Navigator, index)
    if Navigator:StopCount() <= 1 then
        Navigator:Cancel("quest")
    else
        Navigator:RemoveStop(index)
    end
end

-- Puts `dest` where the stop at `index` was. A single stop is simply set again, which keeps a
-- journey a journey (it is re-routed) and a preview a preview. Among several stops the navigator
-- has no "replace", so the new stop is added at the end, the old one is taken out and the new one
-- is moved into the gap: the list is never empty on the way, and each of the three steps is one
-- the navigator already announces and re-routes for (a request in flight is cancelled by the next,
-- so one route is computed and not three). An itinerary that already holds this very stop (the
-- player queued the objective and the turn-in of one quest) only loses the finished one.
local function replaceStop(Navigator, index, dest)
    local count = Navigator:StopCount()
    if count <= 1 then
        -- Quietly, as below: this module moves the route on by itself, and says so in its own words.
        -- For the same reason the request is the navigator's own and not the player's (askedBy).
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
    -- The new stop stood at count + 1 and slid down to count when the old one left.
    if index < count then Navigator:MoveStop(count, index) end
end

-- What became of a route to a quest is news: this module ended the route by itself, and nothing
-- the player typed or clicked is answered by it. So it is told in the call-out, as one of the
-- guide's own lines, and never in chat. UI/Guide.lua loads after this file and is looked up when
-- the line is told. Tell it after the navigator was asked to end the route: the end of a route
-- hushes the call-out, and a line told before it would go with it.
-- Under pcall: the line is a courtesy, and a raise in the guide must not skip what follows the
-- call (the rest of the quest stops in FollowProgress, the answer of OnQuestChanged).
local function tell(fmt, ...)
    local Guide = FGPS.UI and FGPS.UI.Guide
    if not (Guide and Guide.Tell) then return end
    local ok, err = pcall(Guide.Tell, FGPS.Util.SafeFormat(fmt, ...), Quests.NEWS_HOLD)
    if not ok and FGPS.Log and FGPS.Log.Error then FGPS.Log:Error("Quests: the guide could not tell a line: %s", tostring(err)) end
end

-- The client said this quest has left the log, or has just entered it (accepted = true). A
-- re-issued quest is the old quest taken under a new id: the zone and level search list it under
-- the old id its record has, so a stop of an old version (QuestData.OlderVersions) is this quest's.
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
    -- Last to first, so that taking one out does not shift the ones still to be looked at.
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

-- Whether the stage a stop leads to is done. Returns done, completed (the quest became complete
-- after the stop was made).
local function stageDone(q, stop, stage)
    local completed = q.complete and not stop.complete
    if completed then return true, true end
    if stage == "objective" and stop.objectiveIndex then
        -- Still one of the open areas? openAreas only drops one when the client's list and the
        -- record's can be matched, so an unmatched quest never moves on a guess.
        for _, entry in ipairs(openAreas(q)) do
            if entry.area.objective == stop.objectiveIndex then return false, false end
        end
        return true, false
    end
    if stage == "client" then
        -- The client moves its marker when the objective it stood for is done. "Moved" means three
        -- things at once: the map the stop is on was read in this rebuild, no marker of the quest
        -- is at the stop any more, and the client marks the quest somewhere else. The client
        -- reports a quest once per map, so a marker that moved into the neighbouring zone leaves
        -- the stop's map without the quest on it; that map having been read is what tells it apart
        -- from a marker that is merely not reported (the player walked into the next zone, a
        -- loading screen), and then the route stays.
        -- The marker is compared with where the client put it and not with where the route ends:
        -- a stop off the roads is moved onto the nearest node, up to 400 yards away, and keeps
        -- the client's position in originalX / originalY. Compared with the moved position, every
        -- such stop looked abandoned on every rebuild.
        -- The next objective may be marked on a map nobody read, or not at all; then nothing marks
        -- the quest elsewhere, and one more objective finished than when the stop was made
        -- (finishedCount) is what says the marker went with its objective. A loading screen
        -- finishes nothing.
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

-- A stop worked out again from where the player stands now: the next thing to do for a stop this
-- module chose, the same area for one the player named.
local function resolvedAgain(stop)
    if stop.questChosen == true then return Quests.DestinationFor(stop.questID) end
    if stop.areaIndex then return Quests.DestinationFor(stop.questID, "objective:" .. tostring(stop.areaIndex)) end
    return nil
end

local function sameStop(dest, stop)
    return dest.inst == stop.inst and dist(dest.x, dest.y, stop.x, stop.y) <= SAME_STOP_YARDS
end

-- Whether the client says it no longer holds a quest the walk of the log did not meet. That walk
-- reads the rows the log shows, and a zone header the player collapsed may hide its quests from
-- it (Forever's client has CollapseQuestHeader; how its log walk treats one is not known), so a
-- quest missing from the list is asked about by its id. Only a readable "no" counts: a client
-- without the function, one that raises or one whose answer is secret keeps the stop, because
-- ending a route the player did not end is worse than a stop that stays.
local function leftTheLog(questID)
    if not (C_QuestLog and C_QuestLog.IsOnQuest) then return false end
    local ok, on = pcall(C_QuestLog.IsOnQuest, questID)
    return ok and not isSecret(on) and on == false
end

-- Called after every rebuild of the quest list.
function Quests.FollowProgress()
    local stops, Navigator = questStops()
    local failedOne = false
    -- A quest that failed stays in the log, so no event of the client's ends the route to it as
    -- one ends the route to a quest that was dropped. It is read here: such a stop ends, at
    -- whatever stage it was, and the call-out says why. Whatever "Follow my quests" says: that
    -- switch is about a route that moves on, and this one has nowhere left to lead.
    -- The stops come back from the saved variables, which can be older than the server's log (a
    -- crash, a session with Cabbie switched off, a rollback): a quest that left the log then sent
    -- no event. A stop made from the log (one this module chose, or a place the game reported)
    -- ends when the log is read with quests in it, its quest is not there, and the client, asked
    -- by the quest's id, says it does not hold the quest (leftTheLog: a collapsed header may hide
    -- a quest from the walk). A log that reads empty proves nothing (a loading screen), and a
    -- stage the player named of a quest found by searching never needed the log.
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
    -- The positions of the stops that are left may have moved.
    if failedOne then stops, Navigator = questStops() end
    -- An objective stop made from another continent aims at the spawn nearest the middle of its
    -- area (Nav/QuestData.lua), because nobody could tell yet which side the player would arrive
    -- on. Arriving on that continent is when the nearest spawn can be told, so such a stop is
    -- worked out once more then, and only then: walking about must not move it every second. A
    -- loading screen has no position and changes nothing.
    local pos = playerPos()
    local inst = pos and pos.inst
    local before = Quests.lastInst
    local arrived = inst ~= nil and before ~= nil and inst ~= before
    if inst ~= nil then Quests.lastInst = inst end
    -- A stop this module chose is worked out from the quest log, and the log reads empty for a
    -- moment on a loading screen: a rebuild without the quest does not spend the arrival.
    local waiting = false
    local changed = failedOne
    -- Bounded by the itinerary as it stood when the rebuild finished, and walked last to first so
    -- that a stop taken out does not shift the ones still to be looked at.
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
                    -- Nothing is said about it: the game itself says that the objective is done,
                    -- and the Route block shows where the route leads now.
                    replaceStop(Navigator, index, dest)
                    changed = true
                elseif not dest then
                    -- Nothing that is left can be routed to: an objective nobody can place, or a
                    -- dungeon whose entrance is not known. A stop that stays on a finished spot
                    -- is the stale entry this section exists to remove. Why the route ended is
                    -- news the player would not learn otherwise: told in the call-out, after the
                    -- stop has ended.
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
        -- A stop the player named needs no quest log: it is the same area of the record, looked
        -- for again from where they arrived.
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
    -- Asked again at the next rebuild, with the quest in the list.
    if waiting then Quests.lastInst = before end
    return changed
end

-------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------
-- An older version kept what a route leads to in one record beside the itinerary
-- (CabbieCharDB.questRoute). The stop says it itself now, and the record would only ever describe
-- a route that is gone.
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
    -- QUEST_ACCEPTED carries (questLogIndex, questID) on the Classic-shaped clients and (questID) on
    -- the modern ones: the identifier is the last number either way.
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
    -- "Follow my quests" switched off: a place a route stays at is no longer held, and is let go of.
    Events:Register("SETTINGS_CHANGED", function(_, key)
        if key == "quests.followProgress" or key == "*" then recheckStay() end
    end, self)
    Quests.DropLegacyRecord()
end
