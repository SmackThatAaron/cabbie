
























local ADDON_NAME, FGPS = ...

local Coords = {}
FGPS.Coords = Coords

local math_atan2, math_sqrt, math_floor, math_pi = math.atan2, math.sqrt, math.floor, math.pi
local type, pairs, ipairs, tonumber = type, pairs, ipairs, tonumber
local TWO_PI = 2 * math_pi




do
    local hbd
    if LibStub then
        local ok, lib = pcall(LibStub, "HereBeDragons-2.0", true)
        if ok then hbd = lib end
    end
    Coords.HBD = hbd
end



local function plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end


function Coords.IsSecret(v)
    return v ~= nil and issecretvalue ~= nil and issecretvalue(v) == true
end




function Coords.Distance(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    return math_sqrt(dx * dx + dy * dy)
end

function Coords.DistanceSq(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    return dx * dx + dy * dy
end


function Coords.WorldDistance(inst1, x1, y1, inst2, x2, y2)
    if inst1 ~= inst2 then return nil end
    return Coords.Distance(x1, y1, x2, y2)
end



function Coords.Bearing(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    if dx == 0 and dy == 0 then return 0 end
    local angle = math_atan2(dx, dy)
    if angle < 0 then angle = angle + TWO_PI end
    if angle >= TWO_PI then angle = angle - TWO_PI end
    return angle
end


function Coords.AngleDelta(a, b)
    local d = b - a
    while d > math_pi do d = d - TWO_PI end
    while d <= -math_pi do d = d + TWO_PI end
    return d
end

local COMPASS = { "north", "north-west", "west", "south-west", "south", "south-east", "east", "north-east" }

function Coords.CompassName(bearing)
    local sector = math_floor((bearing / TWO_PI) * 8 + 0.5) % 8
    return COMPASS[sector + 1]
end




local zoneLists = {}
local zoneById = {}
local zoneListsBuilt = false
local lastZone = {}

local function mapArea(m)
    return (m.maxX - m.minX) * (m.maxY - m.minY)
end

local function hasBounds(m)
    return type(m) == "table" and m.minX ~= nil and m.maxX ~= nil and m.minY ~= nil and m.maxY ~= nil
end

local function buildZoneLists()
    zoneLists = {}
    zoneById = {}
    lastZone = {}
    local maps = FGPS.Data and FGPS.Data.maps
    if type(maps) == "table" then
        for id, m in pairs(maps) do
            if hasBounds(m) and m.kind == 3 and m.inst ~= nil and m.inst >= 0 and not m.sys then
                local list = zoneLists[m.inst]
                if not list then
                    list = {}
                    zoneLists[m.inst] = list
                end
                local record = { id = id, minX = m.minX, maxX = m.maxX, minY = m.minY, maxY = m.maxY, name = m.name, area = mapArea(m) }
                list[#list + 1] = record
                local byId = zoneById[m.inst]
                if not byId then
                    byId = {}
                    zoneById[m.inst] = byId
                end
                byId[id] = record
            end
        end
        for _, list in pairs(zoneLists) do
            table.sort(list, function(a, b)
                if a.area ~= b.area then return a.area < b.area end
                return a.id < b.id
            end)
        end
    end
    zoneListsBuilt = true
end

local function contains(m, x, y)
    return x >= m.minX and x <= m.maxX and y >= m.minY and y <= m.maxY
end



function Coords.ZoneAt(inst, x, y)
    if inst == nil or x == nil or y == nil then return nil end
    if not zoneListsBuilt then buildZoneLists() end
    local G = FGPS.Graph
    if G and G.Nearest and G.NodeZone then
        local ok, near = pcall(G.Nearest, G, inst, x, y, 25, 1)
        local hit = ok and type(near) == "table" and near[1]
        local mapId = hit and hit.key and G:NodeZone(hit.key)
        local named = mapId and zoneById[inst] and zoneById[inst][mapId]


        if named and contains(named, x, y) then
            lastZone[inst] = named
            return named.id, named.name
        end
    end
    local last = lastZone[inst]
    local list = zoneLists[inst]
    if not list then return nil end
    if last and contains(last, x, y) then


        for i = 1, #list do
            local m = list[i]
            if m == last then return last.id, last.name end
            if contains(m, x, y) then
                lastZone[inst] = m
                return m.id, m.name
            end
        end
    end
    for i = 1, #list do
        local m = list[i]
        if contains(m, x, y) then
            lastZone[inst] = m
            return m.id, m.name
        end
    end
    return nil
end


function Coords.MapName(uiMapID)
    if uiMapID == nil then return nil end
    local maps = FGPS.Data and FGPS.Data.maps
    local m = maps and maps[uiMapID]
    if m and m.name then return m.name end
    if C_Map and C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, uiMapID)
        if ok and type(info) == "table" then return info.name end
    end
    return nil
end


function Coords.ResetZoneIndex()
    zoneListsBuilt = false
    zoneLists = {}
    zoneById = {}
    lastZone = {}
end




local function dataMap(uiMapID)
    local maps = FGPS.Data and FGPS.Data.maps
    local m = maps and maps[uiMapID]
    if hasBounds(m) and m.inst ~= nil and m.inst >= 0 then return m end
    return nil
end

local worldMapSpot



function Coords.MapToWorld(uiMapID, mx, my)
    if uiMapID == nil or mx == nil or my == nil then return nil end
    local inst, x, y, rows = worldMapSpot(uiMapID, mx, my)
    if inst or rows then return inst, x, y end
    local hbd = Coords.HBD
    if hbd then
        local x, y, inst = hbd:GetWorldCoordinatesFromZone(mx, my, uiMapID)
        if x and y and inst and inst >= 0 then return inst, x, y end
    end
    local m = dataMap(uiMapID)
    if m then
        return m.inst, m.maxX - mx * (m.maxX - m.minX), m.maxY - my * (m.maxY - m.minY)
    end
    return nil
end



local hbdZoneCache = {}
local function bestMapFor(inst, x, y)
    local id = Coords.ZoneAt(inst, x, y)
    if id then return id end
    local instances = FGPS.Data and FGPS.Data.instances
    local rec = instances and instances[inst]
    if rec and rec.continentMap then
        local m = dataMap(rec.continentMap)
        if m and contains(m, x, y) then return rec.continentMap end
    end
    local hbd = Coords.HBD
    if hbd then
        local list = hbdZoneCache[inst]
        if not list then
            list = {}
            hbdZoneCache[inst] = list
            local ok, ids = pcall(hbd.GetAllMapIDs, hbd)
            if ok and type(ids) == "table" then
                for _, mapID in ipairs(ids) do
                    local px, py, mapInst = hbd:GetWorldCoordinatesFromZone(0.5, 0.5, mapID)
                    if px and mapInst == inst then list[#list + 1] = mapID end
                end
            end
        end
        local best, bestArea
        for _, mapID in ipairs(list) do
            local zx, zy = hbd:GetZoneCoordinatesFromWorld(x, y, mapID)
            if zx and zy then
                local w, h = hbd:GetZoneSize(mapID)
                local area = (w or 0) * (h or 0)
                if area > 0 and (not bestArea or area < bestArea) then best, bestArea = mapID, area end
            end
        end
        return best
    end
    return nil
end







local WORLD_MAP_ID = 947

local function worldMapRow(inst)
    local maps = FGPS.Data and FGPS.Data.maps
    local m = maps and maps[WORLD_MAP_ID]
    if type(m) ~= "table" or type(m.rects) ~= "table" then return nil end
    for _, r in ipairs(m.rects) do
        if r.inst == inst and hasBounds(r) and r.maxX > r.minX and r.maxY > r.minY
            and type(r.uiMinX) == "number" and type(r.uiMaxX) == "number"
            and type(r.uiMinY) == "number" and type(r.uiMaxY) == "number" then
            return r
        end
    end
    return nil
end




worldMapSpot = function(uiMapID, mx, my)
    if uiMapID ~= WORLD_MAP_ID or type(mx) ~= "number" or type(my) ~= "number" then return nil end
    local maps = FGPS.Data and FGPS.Data.maps
    local m = maps and maps[WORLD_MAP_ID]
    if type(m) ~= "table" or type(m.rects) ~= "table" then return nil end
    for _, r in ipairs(m.rects) do
        if worldMapRow(r.inst) == r and r.uiMaxX > r.uiMinX and r.uiMaxY > r.uiMinY
            and mx >= r.uiMinX and mx <= r.uiMaxX and my >= r.uiMinY and my <= r.uiMaxY then
            return r.inst, r.maxX - (mx - r.uiMinX) / (r.uiMaxX - r.uiMinX) * (r.maxX - r.minX),
                r.maxY - (my - r.uiMinY) / (r.uiMaxY - r.uiMinY) * (r.maxY - r.minY), true
        end
    end
    return nil, nil, nil, true
end



function Coords.WorldToMap(inst, x, y, uiMapID)
    if inst == nil or x == nil or y == nil then return nil end
    local target = uiMapID or bestMapFor(inst, x, y)
    if not target then return nil end
    if target == WORLD_MAP_ID then
        local r = worldMapRow(inst)
        if r then
            return target, r.uiMinX + (r.maxX - x) / (r.maxX - r.minX) * (r.uiMaxX - r.uiMinX),
                r.uiMinY + (r.maxY - y) / (r.maxY - r.minY) * (r.uiMaxY - r.uiMinY)
        end
    end
    local hbd = Coords.HBD
    if hbd then
        local mx, my = hbd:GetZoneCoordinatesFromWorldInstance(x, y, inst, target, true)
        if mx and my then return target, mx, my end
    end
    local m = dataMap(target)
    if m and m.inst == inst then
        return target, (m.maxX - x) / (m.maxX - m.minX), (m.maxY - y) / (m.maxY - m.minY)
    end
    return nil
end






local function playerXY()
    local x, y, inst
    local hbd = Coords.HBD
    if hbd then
        x, y, inst = hbd:GetPlayerWorldPosition()
    elseif UnitPosition then
        local posX, posY, _, instID = UnitPosition("player")
        if posX and posY then x, y, inst = posY, posX, instID end
    end
    x, y, inst = plain(x), plain(y), plain(inst)
    if type(x) ~= "number" or type(y) ~= "number" or type(inst) ~= "number" or inst < 0 then return nil end
    return x, y, inst
end
Coords.PlayerXY = playerXY


function Coords.PlayerPos()
    local x, y, inst = playerXY()
    if not x then return nil end
    local map
    if C_Map and C_Map.GetBestMapForUnit then
        local ok, best = pcall(C_Map.GetBestMapForUnit, "player")
        if ok then map = plain(best) end
    end
    local mx, my
    if map then
        local _, zx, zy = Coords.WorldToMap(inst, x, y, map)
        mx, my = zx, zy
    else
        map, mx, my = Coords.WorldToMap(inst, x, y)
    end
    return { inst = inst, x = x, y = y, map = map, mx = mx, my = my }
end

function Coords.PlayerFacing()
    if not GetPlayerFacing then return nil end
    local ok, facing = pcall(GetPlayerFacing)
    if not ok then return nil end
    facing = plain(facing)
    if type(facing) ~= "number" then return nil end
    return facing
end




function Coords.PlayerSpeed()
    local const = FGPS.Const
    if GetUnitSpeed then
        local ok, current, run, _, swim = pcall(GetUnitSpeed, "player")
        if ok then
            current, run, swim = plain(current), plain(run), plain(swim)
            current, run, swim = tonumber(current), tonumber(run), tonumber(swim)
            if not run or run <= 0 then run = const.RUN_SPEED end
            if not swim or swim <= 0 then swim = const.SWIM_SPEED end
            return current or 0, run, swim
        end
    end
    return 0, const.RUN_SPEED, const.SWIM_SPEED
end





local function readText(fn)
    if not fn then return nil end
    local ok, text = pcall(fn)
    text = ok and plain(text) or nil
    return type(text) == "string" and text or nil
end

function Coords.PlayerPlace()
    local indoor
    if IsIndoors then

        local ok, v = pcall(IsIndoors)
        if ok and not Coords.IsSecret(v) then indoor = v and true or false end
    end
    local name = readText(GetSubZoneText)
    if name then name = name:match("^%s*(.-)%s*$") end
    if name == "" or (name and name == readText(GetZoneText)) then name = nil end
    return { indoor = indoor, name = name }
end


function Coords.IsInstanced()
    if not IsInInstance then return false, "none" end
    local ok, inInstance, instanceType = pcall(IsInInstance)
    if not ok then return false, "none" end
    instanceType = plain(instanceType) or "none"
    return (inInstance and instanceType ~= "none") and true or false, instanceType
end

function Coords:Init()
    if not self.HBD and LibStub then
        local ok, lib = pcall(LibStub, "HereBeDragons-2.0", true)
        if ok then self.HBD = lib end
    end
    if not self.HBD and FGPS.Log then
        FGPS.Log:Warn("HereBeDragons-2.0 is not available; map conversions use compiled bounds only")
    end
    zoneListsBuilt = false
    hbdZoneCache = {}
    self.initialized = true
end
