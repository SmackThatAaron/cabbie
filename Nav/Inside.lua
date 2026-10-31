






local ADDON_NAME, FGPS = ...

local Events = FGPS.Events
local type, pairs, ipairs, tonumber, pcall, select = type, pairs, ipairs, tonumber, pcall, select

local Inside = {
    map = nil,
    mode = nil,
    names = {},
}
FGPS.Inside = Inside

local function listed(map)
    local maps = FGPS.Data and FGPS.Data.insideMaps
    return type(maps) == "table" and map ~= nil and maps[map] or nil
end



local function instanceMap()
    local C = FGPS.Coords
    if not (C and C.IsInstanced and GetInstanceInfo) or not C.IsInstanced() then return nil end
    local ok, _, _, _, _, _, _, _, map = pcall(GetInstanceInfo)
    if not ok or (C.IsSecret and C.IsSecret(map)) then return nil end
    return tonumber(map)
end



function Inside.Map()
    local map = instanceMap()
    if listed(map) then return map end
    return nil
end

local function modeOf(map)
    local C = FGPS.Coords
    local inst
    if C.PlayerXY then
        inst = select(3, C.PlayerXY())
    elseif C.PlayerPos then
        local pos = C.PlayerPos()
        inst = pos and pos.inst
    end
    return inst == map and "position" or "rooms"
end



function Inside.Mode()
    local map = Inside.Map()
    return map and modeOf(map) or nil
end





local function roomsByName(map)
    local C = FGPS.Coords
    local locale = C.ClientLocale and C.ClientLocale() or false
    local source = listed(map)
    local kept = Inside.names[map]
    if kept and kept.locale == locale and kept.source == source then return kept.byClient end
    local byClient = {}
    for _, room in ipairs(source.rooms or {}) do
        local name = type(room.name) == "string" and C.LocalRoomName and C.LocalRoomName(room.name, room.area) or nil
        if name then
            if byClient[name] == nil then
                byClient[name] = room.name
            elseif byClient[name] ~= room.name then
                byClient[name] = false
            end
        end
    end
    Inside.names[map] = { locale = locale, source = source, byClient = byClient }
    return byClient
end







function Inside.Room()
    local map = Inside.Map()
    local C = FGPS.Coords
    if not map or not (C and C.SubZoneText) then return nil end
    local name = C.SubZoneText()
    if not name then return nil end
    return roomsByName(map)[name] or nil
end




Inside.FLOOR_YARDS = 4





local function floorOf(points, run)
    local zs = {}
    for i = run.first, run.last do
        local pt = points[i]
        if pt.room == run.room and type(pt.z) == "number" then zs[#zs + 1] = pt.z end
    end
    if #zs == 0 then return nil end
    table.sort(zs)
    local mid = (#zs + 1) / 2
    local lo, hi = zs[math.floor(mid)], zs[math.ceil(mid)]
    return (lo + hi) / 2
end









function Inside.Runs(leg)
    local C = FGPS.Coords
    local locale = C and C.ClientLocale and C.ClientLocale() or false
    local source = listed(leg.inst)
    local runs = leg._roomRuns
    if runs and leg._roomRunsLocale == locale and leg._roomRunsSource == source then return runs end
    local named = {}
    if source then
        for client, room in pairs(roomsByName(leg.inst)) do
            if room then named[room] = client end
        end
    end
    runs = {}
    local cur
    local points = leg.points or {}
    for i, pt in ipairs(points) do
        local room = pt.room
        if room then
            if cur and cur.room == room then
                cur.last = i
            else
                cur = { room = room, name = named[room], first = i, last = i }
                runs[#runs + 1] = cur
            end
        end
    end



    for _, run in ipairs(runs) do run.z = floorOf(points, run) end
    for j, run in ipairs(runs) do
        local before
        for k = j - 1, 1, -1 do
            if runs[k].name then before = runs[k] break end
        end
        if not before and j > 1 then before = runs[1] end
        if run.z and before and before.z then
            local rise = run.z - before.z
            if rise >= Inside.FLOOR_YARDS then run.climb = "up" elseif rise <= -Inside.FLOOR_YARDS then run.climb = "down" end
        end
    end
    leg._roomRuns, leg._roomRunsLocale, leg._roomRunsSource = runs, locale, source
    return runs
end






function Inside.Origin(inside)
    local map = Inside.Map()
    if not map then return nil end
    local room = Inside.Room()
    if room then
        for _, r in ipairs(listed(map).rooms or {}) do
            if r.name == room then
                return { inst = map, x = r.x, y = r.y, z = r.z, inferred = true, place = { indoor = true, name = room } }
            end
        end
    end
    local door = type(inside) == "table" and inside.map == map and inside.door or nil
    if type(door) == "table" and type(door.x) == "number" and type(door.y) == "number" then
        return { inst = map, x = door.x, y = door.y, inferred = true }
    end
    return nil
end




function Inside:Refresh()
    local map = Inside.Map()
    local mode = map and modeOf(map) or nil
    if map ~= self.map or mode ~= self.mode then
        self.map, self.mode = map, mode
        Events:Fire("INSIDE_CHANGED", map, mode)
    end
    return map, mode
end



local function followsInto(map)
    local Nav = FGPS.Navigator
    if not (Nav and Nav.GetState and Nav.GetRoute) then return false end
    local state = Nav:GetState()
    if state ~= "active" and state ~= "paused" and state ~= "in_transit" then return false end
    local route = Nav:GetRoute()
    for _, leg in ipairs(type(route) == "table" and route.legs or {}) do
        if leg.inst == map or leg.toInst == map then return true end
    end
    return false
end












Inside.VISITS_MAX = 20
Inside.visits = {}
Inside.outdoor = nil

local function round1(n)
    return type(n) == "number" and FGPS.Util.Round(n, 1) or nil
end

local function answered(v)
    local C = FGPS.Coords
    if C and C.IsSecret and C.IsSecret(v) then return nil end
    return v
end


local function positionNow()
    local C = FGPS.Coords
    if not (C and C.PlayerPos) then return nil end
    local ok, pos = pcall(C.PlayerPos)
    if not ok or type(pos) ~= "table" or type(pos.x) ~= "number" or type(pos.y) ~= "number" then return nil end
    return { inst = pos.inst, x = round1(pos.x), y = round1(pos.y) }
end



local function noteOutdoor(from)
    if not FGPS:IsOwnerInstall() then return end
    local C = FGPS.Coords
    if C and C.IsInstanced and C.IsInstanced() then return end
    local pos = positionNow()
    if pos then
        pos.t, pos.from = GetTime and GetTime() or 0, from
        Inside.outdoor = pos
    end
end



local function nearestDoor(inst, x, y)
    local best, bestD
    for _, rec in ipairs(FGPS.Data and FGPS.Data.interiors or {}) do
        local e = rec.entrance
        if type(e) == "table" and e.inst == inst and type(e.x) == "number" and type(e.y) == "number" then
            local d = FGPS.Coords.Distance(x, y, e.x, e.y)
            if not bestD or d < bestD then best, bestD = rec, d end
        end
    end
    if not best then return nil end
    return best.name, best.instanceMap, round1(bestD)
end


local function readAnswers(visit)
    if visit.position == false then visit.position = positionNow() or false end
    local C = FGPS.Coords
    if visit.facing == false and C.PlayerFacing and C.PlayerFacing() ~= nil then visit.facing = true end
end






Inside.ROOM_TEXTS_MAX = 60

local function noteRoomText(visit)
    local C = FGPS.Coords
    local text = C.SubZoneText and C.SubZoneText()
    if not text then return end
    local rooms = visit.rooms
    for _, entry in ipairs(rooms) do
        if entry.text == text then
            entry.seen = entry.seen + 1
            return
        end
    end
    if #rooms >= Inside.ROOM_TEXTS_MAX then
        visit.roomsMore = (visit.roomsMore or 0) + 1
        return
    end
    rooms[#rooms + 1] = { text = text, seen = 1, room = Inside.Room() or false }
end


local function currentVisit()
    local visit = Inside.visits[#Inside.visits]
    if not visit or not FGPS:IsOwnerInstall() then return nil end
    local map = instanceMap()
    if map == nil or map ~= visit.map then return nil end
    return visit
end

local function noteVisit()
    if not FGPS:IsOwnerInstall() or not GetInstanceInfo then return end
    local C = FGPS.Coords
    if not (C and C.IsInstanced) then return end

    local instanced, instanceType = C.IsInstanced()
    if not instanced or (instanceType ~= "party" and instanceType ~= "raid") then return end
    local ok, name, kind, difficulty, _, _, _, _, map = pcall(GetInstanceInfo)
    if not ok then return end
    local now = GetTime and GetTime() or 0
    local visit = { t = round1(now), name = answered(name), type = answered(kind), difficulty = tonumber(answered(difficulty)),
                    map = tonumber(answered(map)), mode = Inside.Mode() or false, position = false, facing = false,
                    locale = C.ClientLocale and C.ClientLocale() or nil, rooms = {} }
    readAnswers(visit)
    noteRoomText(visit)
    local out = Inside.outdoor
    if out then
        local door, doorMap, yards = nearestDoor(out.inst, out.x, out.y)
        visit.outdoor = { inst = out.inst, x = out.x, y = out.y, from = out.from, seconds = round1(now - out.t),
                          door = door, doorMap = doorMap, yards = yards }
    end
    local visits = Inside.visits
    visits[#visits + 1] = visit
    while #visits > Inside.VISITS_MAX do table.remove(visits, 1) end
end



local function onPlaceChanged()
    Inside:Refresh()
    noteOutdoor("place")
    local visit = currentVisit()
    if visit then
        readAnswers(visit)
        noteRoomText(visit)
    end
end




local function onWorldEntered()
    local map = Inside:Refresh()
    noteVisit()

    Inside.outdoor = nil
    local DataLoad = FGPS.DataLoad
    if map and DataLoad and DataLoad.LoadInside and followsInto(map) then DataLoad:LoadInside(map, followsInto) end
end

function Inside:Init()
    if self.initialized then return end
    self.initialized = true
    Events:Register("WORLD_ENTERED", onWorldEntered, self)
    for _, event in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "NEW_WMO_CHUNK", "ZONE_CHANGED_NEW_AREA" }) do
        Events:RegisterWoW(event, onPlaceChanged, self)
    end
    Events:RegisterWoW("PLAYER_LEAVING_WORLD", function() noteOutdoor("leaving") end, self)
    self:Refresh()
end
