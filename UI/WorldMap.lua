
































local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local floor, ceil, sqrt = math.floor, math.ceil, math.sqrt
local type, ipairs, tostring = type, ipairs, tostring

local WorldMap = {
    provider = nil,
    overlay = nil,
    linePool = nil,
    pinPool = nil,
    button = nil,
    BUTTON_SIZE = 32,
    PIN_LAYER_LEVELS = 5000,
    markers = nil,
    BUTTON_ICON = "Interface\\AddOns\\Cabbie\\Media\\icon",
    clearButton = nil,
    CLEAR_BUTTON_SIZE = 22,
    CLEAR_BUTTON_GAP = 4,

    CLEAR_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
    CLEAR_ICON_DOWN = "Interface\\Buttons\\UI-GroupLoot-Pass-Down",



    DISTANCE_POLL_SECONDS = 5,


    DISTANCE_POLL_STILL_YARDS = 5,
    pollPos = nil,
    distanceTicker = nil,
    route = nil,
    routeIsPreview = false,
    attached = false,
    clickHandler = nil,
    lastSegmentCount = 0,
    lastDrawMapID = nil,




    OTHER_LEVEL_ALPHA = 0.4,
    OTHER_LEVEL_YARDS = 6,


    PROGRESS_REDRAW_SECONDS = 1,


    PROGRESS_MOVE_YARDS = 10,
    progressRedrawAt = nil,
    progress = nil,
    drawnFromLeg = nil,
    drawnFromPoint = nil,
    drawnFromInst = nil,
    drawnFromX = nil,
    drawnFromY = nil,
    drawnLevelZ = nil,
    levelBandLow = nil,
    levelBandHigh = nil,


    drawInPending = false,


    drawInSupport = nil,
    drawInUntil = nil,
}
FGPS.UI.WorldMap = WorldMap





local MAX_SEGMENTS = 400
WorldMap.SIMPLIFY_TOLERANCE_YARDS = 2



local SIMPLIFY_MAX_POINTS = 150

local SIMPLIFY_MAX_TOLERANCE_YARDS = 8
local LINE_THICKNESS = 3
local DASH_ON, DASH_OFF = 9, 6



local DASH_UNDERLAY_ALPHA = 0.35
local CLICK_PRIORITY = 95




WorldMap.STOP_RING = "Interface\\AddOns\\Cabbie\\Media\\stop_ring"
WorldMap.MAP_X = "Interface\\AddOns\\Cabbie\\Media\\map_x"
local STOP_GROUND_TEXTURE = "Interface\\AddOns\\Cabbie\\Media\\dot"
local PIN_SIZE = 32
local RING_SIZE = 24


WorldMap.RING_BOX = PIN_SIZE / RING_SIZE


local TELEPORT_KINDS = { hearth = true, spell = true, portal = true }






local TRACKLESS_KINDS = { tram = true, elevator = true }

local TRANSPORT_KINDS = { taxi = true, boat = true, zeppelin = true, tram = true, elevator = true }


local DOCK_ICONS = {
    boat = "Interface\\AddOns\\Cabbie\\Media\\place_boat",
    zeppelin = "Interface\\AddOns\\Cabbie\\Media\\place_zeppelin",
}
local DOCK_ICON_SIZE = 18



FGPS.UI.AddSettingDefault("worldMapLegend", true)


FGPS.UI.AddSettingDefault("openWithMap", false)




local function settings()
    return FGPS.DB and FGPS.DB.settings or nil
end


local function colorOf(c)
    if type(c) ~= "table" then return nil end
    local r, g, b, a = c[1] or c.r, c[2] or c.g, c[3] or c.b, c[4] or c.a
    if r and g and b then return r, g, b, a or 1 end
    return nil
end


local function ownSkinColor(name)
    local Skins = FGPS.UI.Skins
    if Skins and Skins.Current then
        local ok, skin = pcall(Skins.Current)
        if ok and type(skin) == "table" and type(skin.colors) == "table" then return colorOf(skin.colors[name]) end
    end
    return nil
end


local STROKE_INK_ALPHA = { routeVerified = 0.95, routeUnverified = 0.95, routeTransport = 0.85 }








local function strokeColor(name)
    local Skins = FGPS.UI.Skins
    if Skins and Skins.ColorScheme then
        local ok, scheme = pcall(Skins.ColorScheme)
        if ok and type(scheme) == "table" and type(scheme.colors) == "table" then
            local r, g, b, a = ownSkinColor(name)
            if r then return r, g, b, a end
            r, g, b, a = colorOf(scheme.colors[name])
            if r then return r, g, b, a end
        end
    end
    local r, g, b = FGPS.UI.Look.Color("route")
    return r, g, b, STROKE_INK_ALPHA[name]
end







local UNVERIFIED_KINDS = { [3] = true, [14] = true, [15] = true, [19] = true }

local function unverifiedKinds()
    local Route = FGPS.Route
    if Route and type(Route.DashedKinds) == "function" then return Route.DashedKinds() end
    if Route and type(Route.UNVERIFIED_KINDS) == "table" then return Route.UNVERIFIED_KINDS end
    return UNVERIFIED_KINDS
end

local function mapInstance(mapID)
    local maps = FGPS.Data and FGPS.Data.maps
    local m = maps and maps[mapID]
    if m and type(m.inst) == "number" and m.inst >= 0 then return m.inst end
    local HBD = FGPS.Coords and FGPS.Coords.HBD
    if not HBD and LibStub then HBD = LibStub("HereBeDragons-2.0", true) end
    local data = HBD and HBD.mapData and HBD.mapData[mapID]
    if data and type(data.instance) == "number" and data.instance >= 0 then return data.instance end
    return nil
end

local function mapRow(mapID)
    local maps = FGPS.Data and FGPS.Data.maps
    return maps and maps[mapID]
end

local function continentMap(inst)
    local instances = FGPS.Data and FGPS.Data.instances
    local rec = instances and instances[inst]
    return rec and rec.continentMap
end


local zoneCrop












local function fromContinent(inst, x, y, mapID)
    local continent = continentMap(inst)
    local row = mapRow(mapID)
    if not continent or continent == mapID or not row or row.kind ~= 3 then return nil end
    if not (C_Map and C_Map.GetMapRectOnMap) then return nil end
    local Coords = FGPS.Coords
    if not (Coords and Coords.WorldToMap) then return nil end
    local _, cx, cy = Coords.WorldToMap(inst, x, y, continent)
    if not cx or not cy then return nil end
    local minX, maxX, minY, maxY
    local crop = zoneCrop


    if crop and crop.mapID == mapID then
        minX, maxX, minY, maxY = crop.minX, crop.maxX, crop.minY, crop.maxY
    else
        local ok
        ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, mapID, continent)
        if not ok then return nil end
    end
    if type(minX) ~= "number" or type(maxX) ~= "number" or type(minY) ~= "number" or type(maxY) ~= "number" then
        return nil
    end
    if maxX <= minX or maxY <= minY then return nil end
    return (cx - minX) / (maxX - minX), (cy - minY) / (maxY - minY)
end




local function toMap(inst, x, y, mapID)
    local zx, zy = fromContinent(inst, x, y, mapID)
    if zx then return zx, zy end
    local Coords = FGPS.Coords
    if Coords and Coords.WorldToMap then
        local id, mx, my = Coords.WorldToMap(inst, x, y, mapID)
        if mx and my and (id == nil or id == mapID) then return mx, my end
    end
    local HBD = Coords and Coords.HBD
    if not HBD and LibStub then HBD = LibStub("HereBeDragons-2.0", true) end
    if HBD and HBD.GetZoneCoordinatesFromWorldInstance then
        local mx, my = HBD:GetZoneCoordinatesFromWorldInstance(x, y, inst, mapID, true)
        if mx and my then return mx, my end
    end
    return nil
end



local function clipEdge(p, q, t0, t1)
    if p == 0 then
        if q < 0 then return false end
        return true, t0, t1
    end
    local r = q / p
    if p < 0 then
        if r > t1 then return false end
        if r > t0 then t0 = r end
    else
        if r < t0 then return false end
        if r < t1 then t1 = r end
    end
    return true, t0, t1
end

local function clipSegment(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    local ok, t0, t1 = true, 0, 1
    ok, t0, t1 = clipEdge(-dx, x1, t0, t1)
    if not ok then return nil end
    ok, t0, t1 = clipEdge(dx, 1 - x1, t0, t1)
    if not ok then return nil end
    ok, t0, t1 = clipEdge(-dy, y1, t0, t1)
    if not ok then return nil end
    ok, t0, t1 = clipEdge(dy, 1 - y1, t0, t1)
    if not ok then return nil end
    return x1 + t0 * dx, y1 + t0 * dy, x1 + t1 * dx, y1 + t1 * dy
end
WorldMap.ClipSegment = clipSegment


local function clipRect(x1, y1, x2, y2, left, top, right, bottom)
    local w, h = right - left, bottom - top
    if w <= 0 or h <= 0 then return nil end
    local cx1, cy1, cx2, cy2 = clipSegment((x1 - left) / w, (y1 - top) / h, (x2 - left) / w, (y2 - top) / h)
    if not cx1 then return nil end
    return left + cx1 * w, top + cy1 * h, left + cx2 * w, top + cy2 * h
end




local function decimate(points, stride)
    if stride <= 1 then return points end
    local Route = FGPS.Route
    local mustKeep = Route and Route.MustKeep
    local out = { points[1] }
    local n = #points
    for i = 2, n - 1 do
        if (i - 1) % stride == 0 or (mustKeep and mustKeep(points, i)) then out[#out + 1] = points[i] end
    end
    out[#out + 1] = points[n]
    return out
end





















local function simplify(leg, points, tolerance)
    if type(leg) == "table" and leg._fgpsSimplifiedTol == tolerance and type(leg._fgpsSimplified) == "table" then
        return leg._fgpsSimplified, leg._fgpsSimplifiedThinned == true
    end
    local result, thinned = points, false
    local Route = FGPS.Route
    if #points > SIMPLIFY_MAX_POINTS then
        local tol = tolerance
        while Route and Route.SimplifyLinear do
            local ok, simplified = pcall(Route.SimplifyLinear, points, tol)
            if ok and type(simplified) == "table" and #simplified >= 2 then result = simplified end
            if #result <= SIMPLIFY_MAX_POINTS or tol * 2 > SIMPLIFY_MAX_TOLERANCE_YARDS then break end
            tol, thinned = tol * 2, true
        end
        if #result > SIMPLIFY_MAX_POINTS then
            result = decimate(result, ceil(#result / SIMPLIFY_MAX_POINTS))
            thinned = true
        end
    elseif Route and Route.Simplify and #result > 2 then
        local ok, simplified = pcall(Route.Simplify, result, tolerance)
        if ok and type(simplified) == "table" and #simplified >= 2 then result = simplified end
    end
    if type(leg) == "table" then
        leg._fgpsSimplified, leg._fgpsSimplifiedTol, leg._fgpsSimplifiedThinned = result, tolerance, thinned
    end
    return result, thinned
end










local function jumpIndex(leg, points)
    local n = #points
    local split = leg.split
    if type(split) == "number" and split >= 1 and split < n then return split end
    if leg.toInst ~= nil and leg.toInst ~= leg.inst then return n - 1 end
    return nil
end



local function keptIndices(leg, kept, points)
    if leg._fgpsKeptFor == kept and type(leg._fgpsKept) == "table" then return leg._fgpsKept end
    local indices, i, n = {}, 1, #points
    for j = 1, #kept do
        while i <= n and points[i] ~= kept[j] do i = i + 1 end
        indices[j] = i
        i = i + 1
    end
    leg._fgpsKept, leg._fgpsKeptFor = indices, kept
    return indices
end





local function remainingPoints(leg, points, pts, jump, from, pos)
    local out, frame = {}, nil
    if jump and from > jump then

        if leg.toInst ~= nil and leg.toInst ~= leg.inst then frame = leg.toInst end
        jump = nil
    end
    local frameInst = frame or leg.inst
    if type(pos) == "table" and pos.x and pos.y and (frameInst == nil or pos.inst == nil or pos.inst == frameInst) then

        local behind = points[from - 1]
        out[1] = { x = pos.x, y = pos.y, z = behind and behind.z, stacked = behind and behind.stacked }
    end
    local lead = #out
    if pts == points then
        for i = from, #points do out[#out + 1] = points[i] end
    else
        local kept = keptIndices(leg, pts, points)
        for j = 1, #pts do
            if kept[j] >= from then out[#out + 1] = pts[j] end
        end
    end

    if jump then jump = lead + jump - from + 1 end
    return out, jump, frame
end



































local function widen(z, levelZ, low, high)
    if z <= levelZ and (low == nil or z > low) then low = z end
    if z >= levelZ and (high == nil or z < high) then high = z end
    return low, high
end

local function levelOf(seg, a, b, levelZ, info)
    seg.z = b.z
    if not (a.stacked and b.stacked) then return end
    seg.stacked = true
    if not levelZ or b.k ~= 22 or type(a.z) ~= "number" or type(b.z) ~= "number" then return end
    local yards = WorldMap.OTHER_LEVEL_YARDS
    local low, high = widen(a.z - yards, levelZ, info.levelLow, info.levelHigh)
    low, high = widen(a.z + yards, levelZ, low, high)
    low, high = widen(b.z - yards, levelZ, low, high)
    info.levelLow, info.levelHigh = widen(b.z + yards, levelZ, low, high)
    if math.abs(a.z - levelZ) > yards and math.abs(b.z - levelZ) > yards then seg.otherLevel = true end
end

function WorldMap.ComputeSegments(route, mapID, opts)
    local segments = {}
    local info = { legs = 0, points = 0, truncated = false }
    if type(route) ~= "table" or type(route.legs) ~= "table" or type(mapID) ~= "number" then
        return segments, info
    end
    opts = opts or {}
    local levelZ = type(opts.levelZ) == "number" and opts.levelZ or nil
    local maxSegments = opts.maxSegments or MAX_SEGMENTS
    local tolerance = opts.tolerance or WorldMap.SIMPLIFY_TOLERANCE_YARDS
    local inst = mapInstance(mapID)



    local mapW, mapH
    local continent = continentMap(inst)
    local row = mapRow(mapID)
    zoneCrop = nil
    if row and row.kind == 3 and continent and continent ~= mapID and C_Map and C_Map.GetMapRectOnMap then
        local c = mapRow(continent)
        local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, mapID, continent)
        if ok and type(minX) == "number" and type(maxX) == "number" and type(minY) == "number" and type(maxY) == "number" then
            zoneCrop = { mapID = mapID, minX = minX, maxX = maxX, minY = minY, maxY = maxY }
            if c and c.minX and maxX > minX and maxY > minY then
                mapW = (maxX - minX) * math.abs(c.maxX - c.minX)
                mapH = (maxY - minY) * math.abs(c.maxY - c.minY)
            end
        end
    end
    if not mapW and row and row.minX and row.maxX and row.minY and row.maxY then
        mapW = math.abs(row.maxX - row.minX)
        mapH = math.abs(row.maxY - row.minY)
    end



    local startLeg = type(opts.startLeg) == "number" and opts.startLeg or nil
    local startPoint = startLeg and type(opts.startPoint) == "number" and opts.startPoint or nil


    local prepared, candidates = {}, 0
    for legIndex, leg in ipairs(route.legs) do
        local points = type(leg) == "table" and leg.points or nil
        if type(points) == "table" and #points >= 2 and not TELEPORT_KINDS[leg.kind or ""]
            and not TRACKLESS_KINDS[leg.kind or ""]
            and (inst == nil or leg.inst == nil or leg.inst == inst or leg.toInst == inst)
            and not (startLeg and legIndex < startLeg) then
            local jump = jumpIndex(leg, points)
            local pts, thinned = points, false


            if not jump then pts, thinned = simplify(leg, points, tolerance) end
            if thinned then info.truncated = true end
            local frame
            if legIndex == startLeg and startPoint then
                pts, jump, frame = remainingPoints(leg, points, pts, jump, startPoint, opts.startPos)
            end
            if #pts >= 2 then
                prepared[#prepared + 1] = { leg = leg, index = legIndex, points = pts, jump = jump, inst = frame }
                candidates = candidates + (#pts - 1)
            end
        end
    end
    info.legs = #prepared
    local stride = 1
    if candidates > maxSegments then



        local reserved = #prepared
        local mustKeep = FGPS.Route and FGPS.Route.MustKeep
        for _, entry in ipairs(prepared) do
            if mustKeep and not entry.jump then
                for i = 2, #entry.points - 1 do
                    if mustKeep(entry.points, i) then reserved = reserved + 1 end
                end
            end
        end
        stride = ceil(candidates / math.max(1, maxSegments - reserved))
        info.truncated = true
    end


    local UNVERIFIED = unverifiedKinds()
    for _, entry in ipairs(prepared) do
        local leg = entry.leg
        local jump = entry.jump
        local pts = jump and entry.points or decimate(entry.points, stride)
        local legInst = entry.inst or leg.inst or inst
        local crossesInstances = jump ~= nil and leg.toInst ~= nil and leg.toInst ~= leg.inst
        local legUnverified = leg.unverified == true
        local transport = TRANSPORT_KINDS[leg.kind or ""] == true
        local px, py, wx, wy
        local pp
        local broke = false
        for i = 1, #pts do
            local p = pts[i]
            local x, y = p.x or p[1], p.y or p[2]



            local unverified = legUnverified
            if p.k ~= nil then unverified = UNVERIFIED[p.k] == true end

            local pointInst = legInst
            if crossesInstances and i > jump then pointInst = leg.toInst end
            local crossing = false
            if jump and i == jump + 1 then


                if crossesInstances and inst == nil then crossing = true else px, py, wx, wy = nil, nil, nil, nil end
            end
            local mx, my
            if pointInst and x and y and (inst == nil or pointInst == inst) then mx, my = toMap(pointInst, x, y, mapID) end
            if mx then info.points = info.points + 1 end
            local stretched = false
            if mx and px and mapW and mapH and wx and wy and x and y then
                local worldDist = sqrt((x - wx) * (x - wx) + (y - wy) * (y - wy))
                local mapDist = sqrt(((mx - px) * mapW) ^ 2 + ((my - py) * mapH) ^ 2)



                if mapDist > math.max(worldDist * 3, 250) then stretched = true end
            end
            if mx and px and not stretched then
                local cx1, cy1, cx2, cy2 = clipSegment(px, py, mx, my)
                if cx1 and (cx1 ~= cx2 or cy1 ~= cy2) then
                    local seg = { cx1, cy1, cx2, cy2, unverified = unverified, transport = transport,
                                  kind = leg.kind, edgeKind = p.k, legIndex = entry.index, crossing = crossing or nil }
                    levelOf(seg, pp, p, levelZ, info)
                    segments[#segments + 1] = seg
                    if #segments >= maxSegments then
                        info.truncated = true
                        zoneCrop = nil
                        return segments, info
                    end
                end
            elseif mx and px and stretched then


                local outside = mx < 0 or mx > 1 or my < 0 or my > 1
                if outside and not broke then
                    local cx1, cy1, cx2, cy2 = clipSegment(px, py, mx, my)
                    if cx1 and (cx1 ~= cx2 or cy1 ~= cy2) then
                        local seg = { cx1, cy1, cx2, cy2, unverified = unverified, transport = transport,
                                      kind = leg.kind, edgeKind = p.k, legIndex = entry.index, crossing = crossing or nil }
                        levelOf(seg, pp, p, levelZ, info)
                        segments[#segments + 1] = seg
                        if #segments >= maxSegments then
                            info.truncated = true
                            zoneCrop = nil
                            return segments, info
                        end
                    end
                end
                broke = true
                mx = nil
            end


            if mx then
                px, py = mx, my
                wx, wy = x, y
                pp = p
            end
        end
    end
    zoneCrop = nil
    return segments, info
end



function WorldMap.ComputeStops(route, mapID)
    local pins = {}
    if type(route) ~= "table" or type(mapID) ~= "number" then return pins end
    local inst = mapInstance(mapID)
    local stops = route.stops
    if type(stops) == "table" and #stops > 0 then
        for i, stop in ipairs(stops) do
            local dest = stop.dest or stop
            if type(dest) == "table" and dest.x and dest.y and (inst == nil or dest.inst == nil or dest.inst == inst) then
                local mx, my = toMap(dest.inst or inst, dest.x, dest.y, mapID)
                if mx and mx >= 0 and mx <= 1 and my >= 0 and my <= 1 then
                    pins[#pins + 1] = { x = mx, y = my, index = i, name = dest.name, isFinal = (i == #stops), dest = dest }
                end
            end
        end
        return pins
    end

    local legs = route.legs
    if type(legs) == "table" and #legs > 0 then
        local last = legs[#legs]
        local p = last and last.points and last.points[#last.points]
        if p and (inst == nil or last.inst == nil or last.inst == inst) then
            local mx, my = toMap(last.inst or inst, p.x or p[1], p.y or p[2], mapID)
            if mx and mx >= 0 and mx <= 1 and my >= 0 and my <= 1 then
                pins[1] = { x = mx, y = my, index = 1, name = last.label, isFinal = true }
            end
        end
    end
    return pins
end











function WorldMap.ComputeTransportLabels(route, mapID, startLeg)
    local labels = {}
    if type(route) ~= "table" or type(route.legs) ~= "table" or type(mapID) ~= "number" then return labels end
    local inst = mapInstance(mapID)
    local Route = FGPS.Route
    for legIndex, leg in ipairs(route.legs) do
        local points = type(leg) == "table" and leg.points or nil
        if type(points) == "table" and #points >= 2 and TRANSPORT_KINDS[leg.kind or ""] and leg.inst ~= nil
            and ((leg.toInst ~= nil and leg.toInst ~= leg.inst) or TRACKLESS_KINDS[leg.kind])
            and not (type(startLeg) == "number" and legIndex < startLeg) then
            local vehicle = Route and Route.LegLabel and Route.LegLabel(leg.kind) or leg.kind
            local first, last = points[1], points[#points]
            local arrivalInst = leg.toInst or leg.inst
            if inst == nil or inst == leg.inst then
                local mx, my = toMap(leg.inst, first.x or first[1], first.y or first[2], mapID)
                if mx and mx >= 0 and mx <= 1 and my >= 0 and my <= 1 then
                    labels[#labels + 1] = { x = mx, y = my, legIndex = legIndex, arrival = false,
                                            text = string.format(L["%s to %s"], vehicle, leg.stopTo or leg.label or L["the far side"]),
                                            icon = DOCK_ICONS[leg.kind] }
                end
            end
            if leg.kind ~= "elevator" and (inst == nil or inst == arrivalInst) then
                local mx, my = toMap(arrivalInst, last.x or last[1], last.y or last[2], mapID)
                if mx and mx >= 0 and mx <= 1 and my >= 0 and my <= 1 then
                    labels[#labels + 1] = { x = mx, y = my, legIndex = legIndex, arrival = true,
                                            text = string.format(L["%s from %s"], vehicle, leg.stopFrom or leg.label or L["the far side"]) }
                end
            end
        end
    end
    return labels
end




local function ensurePools()
    if WorldMap.linePool then return true end
    local overlay = WorldMap.overlay
    if not overlay or not CreateObjectPool then return false end
    WorldMap.linePool = CreateObjectPool(function()
        return overlay:CreateLine(nil, "ARTWORK")
    end, function(_, line)
        line:Hide()
        line:ClearAllPoints()
        line.normalizedX1, line.normalizedY1, line.normalizedX2, line.normalizedY2 = nil, nil, nil, nil



        local drawIn = line.DrawIn
        if drawIn then drawIn:Stop() end
        line:SetAlpha(1)
    end)


    WorldMap.pinPool = CreateFramePool("Button", WorldMap.pinLayer or overlay, nil, function(_, pin)
        pin:Hide()
        pin:ClearAllPoints()
    end)
    WorldMap.labelPool = CreateFramePool("Frame", WorldMap.pinLayer or overlay, nil, function(_, label)
        label:Hide()
        label:ClearAllPoints()
    end)
    return true
end

local function canvasScale()
    local map = WorldMapFrame
    if map and map.GetCanvasScale then
        local ok, scale = pcall(map.GetCanvasScale, map)
        if ok and type(scale) == "number" and scale > 0 then return scale end
    end
    return 1
end

local function lineThickness(scale)
    return Util.Clamp(LINE_THICKNESS / scale, 0.75, 8)
end

function WorldMap:ClearDrawing()
    if self.linePool then self.linePool:ReleaseAll() end
    if self.pinPool then self.pinPool:ReleaseAll() end
    if self.labelPool then self.labelPool:ReleaseAll() end
    self.lastSegmentCount = 0
    self.lastDrawMapID = nil
    self.drawnView = nil

    self.drawInUntil = nil

    self.finalPinShown = false
    if self.cartouche then self.cartouche:Hide() end
end



local MAX_LINE_PIXELS = 256

local function placeLine(line, canvas, w, h, x1, y1, x2, y2, r, g, b, a, thickness)

    line.normalizedX1, line.normalizedY1, line.normalizedX2, line.normalizedY2 = x1, y1, x2, y2
    line:SetStartPoint("TOPLEFT", canvas, x1 * w, -y1 * h)
    line:SetEndPoint("TOPLEFT", canvas, x2 * w, -y2 * h)
    line:SetColorTexture(r, g, b, a)
    line:SetThickness(thickness)
    line:Show()
end















local drawInOrder = {}
local drawInAt = {}
local drawInLength = {}
local collectDrawIn = false





local inkFromX, inkFromY, inkFrom, inkLength, inkPer, inkOnX = nil, nil, 0, 0, 0, true

local function clearList(list)
    for i = #list, 1, -1 do list[i] = nil end
end


local function inkSegment(x1, y1, x2, y2, w, h)
    local left, top, right, bottom = WorldMap._viewL, WorldMap._viewT, WorldMap._viewR, WorldMap._viewB
    if left then
        x1, y1, x2, y2 = clipRect(x1, y1, x2, y2, left, top, right, bottom)
        if not x1 then
            inkFromX = nil
            return
        end
    end
    local dx, dy = (x2 - x1) * w, (y2 - y1) * h
    local length = sqrt(dx * dx + dy * dy)
    inkFromX, inkFromY, inkFrom = x1, y1, inkLength
    inkLength = inkLength + length


    inkOnX = (dx < 0 and -dx or dx) >= (dy < 0 and -dy or dy)
    local axis = inkOnX and (x2 - x1) or (y2 - y1)
    inkPer = axis ~= 0 and length / axis or 0
end


local function newDrawIn(line)
    local group = line:CreateAnimationGroup()
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(0)
    fade:SetToAlpha(1)
    group.fade = fade
    if group.SetToFinalAlpha then group:SetToFinalAlpha(true) end
    return group
end





local function addGrow(group)
    local scale = group:CreateAnimation("LineScale")
    if type(scale) ~= "table" then error("no LineScale animation", 0) end
    group.grow = scale
    scale:SetOrigin("LEFT", 0, 0)
    scale:SetScaleFrom(0.001, 1)
    scale:SetScaleTo(1, 1)
end



local function wholeAgain(group) group:GetParent():SetAlpha(1) end





local function drawInGroup(line)
    local group = line.DrawIn
    if group ~= nil then return group or nil end
    line.DrawIn = false
    local support = WorldMap.drawInSupport
    if support == false then return nil end
    local Look = FGPS.UI.Look
    if type(line.CreateAnimationGroup) ~= "function" then
        WorldMap.drawInSupport = false
        Look.NoteOnce("map:drawIn", "Map draw-in: none (no CreateAnimationGroup); a new route appears at once")
        return nil
    end
    local ok, made = pcall(newDrawIn, line)
    local refused
    if ok and support ~= "fade" then
        local grown, why = pcall(addGrow, made)
        if not grown then
            refused = why



            if made.grow then ok, made = pcall(newDrawIn, line) end
        end
    end
    if not ok then
        WorldMap.drawInSupport = false
        Look.NoteOnce("map:drawIn", "Map draw-in: none (%s); a new route appears at once", tostring(made))
        return nil
    end
    if refused == nil and support ~= "fade" then
        WorldMap.drawInSupport = "grow"
        Look.NoteOnce("map:drawIn", "Map draw-in: fade and LineScale")
    else
        WorldMap.drawInSupport = "fade"
        if refused then Look.NoteOnce("map:drawIn", "Map draw-in: fade only (LineScale: %s)", tostring(refused)) end
    end
    made:SetScript("OnFinished", wholeAgain)
    made:SetScript("OnStop", wholeAgain)
    line.DrawIn = made
    return made
end





local function playDrawIn(lines, total)
    if WorldMap.drawInSupport == false then return 0 end
    local played = 0
    local n = #lines
    local span = FGPS.UI.Look.TOKENS.drawIn
    for i = 1, n do
        local line = lines[i]
        local group = drawInGroup(line)
        if group then
            local delay, share
            if total > 0 then
                delay = drawInAt[i] / total * span
                share = drawInLength[i] / total * span
                if delay > span then delay = span end


                if delay < 0 then delay = 0 end
                if delay + share > span then share = span - delay end
            else
                delay, share = (i - 1) / n * span, span / n
            end
            group.fade:SetStartDelay(delay)
            group.fade:SetDuration(share)
            local grow = group.grow
            if grow then
                grow:SetStartDelay(delay)
                grow:SetDuration(share)
            end
            line:SetAlpha(0)
            group:Play()
            played = played + 1
        end
    end
    return played
end




local function startDrawIn(lines, total)
    local ok, played = pcall(playDrawIn, lines, total)
    if ok then
        if played > 0 then WorldMap.drawInUntil = (GetTime and GetTime() or 0) + FGPS.UI.Look.TOKENS.drawIn end
        return
    end
    local err = played
    WorldMap.drawInSupport = false
    FGPS.UI.Look.NoteOnce("map:drawIn:play", "Map draw-in failed (%s); the line is drawn whole", tostring(err))
    for i = 1, #lines do
        local line = lines[i]
        local group = line.DrawIn
        if group then group:Stop() end
        line:SetAlpha(1)
    end
end



local function validNormRect(rect)
    if type(rect) ~= "table" then return nil end
    local left, right = rect.left, rect.right
    local top, bottom = rect.top, rect.bottom
    if type(left) == "number" and type(right) == "number"
        and type(top) == "number" and type(bottom) == "number"
        and right > left and bottom > top
        and right > 0 and bottom > 0 and left < 1 and top < 1 then
        return left, top, right, bottom
    end
end

local function visibleNormRect(map)
    local scroll = map and (map.ScrollContainer or (map.GetCanvasContainer and map:GetCanvasContainer()))


    if scroll and scroll.CalculateViewRect then
        local ok, rect = pcall(scroll.CalculateViewRect, scroll, canvasScale())
        if ok then
            local left, top, right, bottom = validNormRect(rect)
            if left then return left, top, right, bottom end
        end
    end
    if map and map.GetViewRect then
        local ok, rect = pcall(map.GetViewRect, map)
        if ok then
            local left, top, right, bottom = validNormRect(rect)
            if left then return left, top, right, bottom end
        end
    end
    if scroll and scroll.GetViewRect then
        local ok, rect = pcall(scroll.GetViewRect, scroll)
        if ok then
            local left, top, right, bottom = validNormRect(rect)
            if left then return left, top, right, bottom end
        end
    end
    return 0, 0, 1, 1
end

local function emitLine(pool, canvas, w, h, scale, x1, y1, x2, y2, r, g, b, a, thickness)
    local left, top, right, bottom = WorldMap._viewL, WorldMap._viewT, WorldMap._viewR, WorldMap._viewB
    if left then
        local cx1, cy1, cx2, cy2 = clipRect(x1, y1, x2, y2, left, top, right, bottom)
        if not cx1 then return 0 end
        x1, y1, x2, y2 = cx1, cy1, cx2, cy2
    end


    local dx, dy = (x2 - x1) * w, (y2 - y1) * h
    local localLen = sqrt(dx * dx + dy * dy)
    local pixels = localLen * (scale > 1 and scale or 1)
    local pieces = ceil(pixels / MAX_LINE_PIXELS)
    if pieces < 1 then pieces = 1 end




    if pieces > 128 then pieces = 128 end
    for i = 1, pieces do
        local t0, t1 = (i - 1) / pieces, i / pieces
        local line = pool:Acquire()
        local px, py = x1 + (x2 - x1) * t0, y1 + (y2 - y1) * t0
        placeLine(line, canvas, w, h, px, py, x1 + (x2 - x1) * t1, y1 + (y2 - y1) * t1, r, g, b, a, thickness)
        if collectDrawIn then

            local n = #drawInOrder + 1
            local at = inkFrom
            if inkFromX then at = at + (inkOnX and px - inkFromX or py - inkFromY) * inkPer end
            drawInOrder[n], drawInAt[n], drawInLength[n] = line, at, localLen / pieces
        end
    end
    return pieces
end






local function itineraryIndex(Navigator, index, dest)
    if type(dest) ~= "table" or not Navigator.GetStops then return nil end
    local ok, stops = pcall(Navigator.GetStops, Navigator)
    if not ok or type(stops) ~= "table" then return nil end
    local D = FGPS.Destinations
    local function same(stop)
        return stop == dest or (D ~= nil and D.Equal ~= nil and D.Equal(stop, dest) == true)
    end
    if type(index) == "number" and stops[index] ~= nil and same(stops[index]) then return index end
    for i = 1, #stops do
        if same(stops[i]) then return i end
    end
    return nil
end


local PIN_HINTS = { L["Shift+Right-click to remove"], L["Right-click for options"] }

local function setupPin(pin)
    if pin.fgpsReady then return end
    pin.fgpsReady = true
    local Look = FGPS.UI.Look
    pin:SetSize(PIN_SIZE, PIN_SIZE)

    pin.Fill = pin:CreateTexture(nil, "BACKGROUND")
    pin.Fill:SetSize(RING_SIZE, RING_SIZE)
    pin.Fill:SetPoint("CENTER", pin, "CENTER", 0, 0)
    pin.Fill:SetTexture(STOP_GROUND_TEXTURE)
    pin.Ring = pin:CreateTexture(nil, "ARTWORK")
    pin.Ring:SetAllPoints(pin)
    pin.Ring:SetTexture(WorldMap.STOP_RING)
    pin.Number = pin:CreateFontString(nil, "OVERLAY", Look.Font("rowSmall"))
    pin.Number:SetPoint("CENTER", pin, "CENTER", 0, 0)

    pin.Label = pin:CreateFontString(nil, "OVERLAY", Look.Font("rowSmall"))
    pin.Label:SetPoint("LEFT", pin, "RIGHT", Look.TOKENS.gap - (PIN_SIZE - RING_SIZE) / 2, 0)


    pin.Mark = pin:CreateTexture(nil, "ARTWORK")
    pin.Mark:SetAllPoints(pin)
    pin.Mark:SetTexture(WorldMap.MAP_X)
    pin.Name = pin:CreateFontString(nil, "OVERLAY", Look.Font("mapLabel"))
    pin.Name:SetPoint("TOP", pin, "BOTTOM", 0, 0)
    pin.Sub = pin:CreateFontString(nil, "OVERLAY", Look.Font("hint"))
    pin.Sub:SetPoint("TOP", pin.Name, "BOTTOM", 0, 0)





    pin:EnableMouse(true)
    pin:RegisterForClicks("RightButtonUp")
    pin:SetScript("OnClick", function(self, button)
        if button ~= "RightButton" then return end
        if not (IsShiftKeyDown and IsShiftKeyDown()) then
            if (IsControlKeyDown and IsControlKeyDown()) or (IsAltKeyDown and IsAltKeyDown()) then return end
            if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
            local Menus = FGPS.UI.Menus
            if Menus and Menus.OpenRouteMenu then
                local ok, err = pcall(Menus.OpenRouteMenu, self)
                if not ok then FGPS.Log:Error("OpenRouteMenu failed: %s", tostring(err)) end
            end
            return
        end
        local Navigator = FGPS.Navigator
        if not (Navigator and Navigator.RemoveStop) then return end
        local index = itineraryIndex(Navigator, self.fgpsIndex, self.fgpsDest)
        if index then
            local ok, err = pcall(Navigator.RemoveStop, Navigator, index)
            if not ok then FGPS.Log:Error("RemoveStop failed: %s", tostring(err)) end
        end
    end)
    pin:SetScript("OnEnter", function(self)
        local title = format(L["Stop %s: %s"], tostring(self.fgpsIndex or "?"), self.fgpsName or L["Stop"])
        FGPS.UI.Look.Tooltip(self, title, nil, PIN_HINTS)
    end)
    pin:SetScript("OnLeave", function(self)
        if GameTooltip and (not GameTooltip.IsOwned or GameTooltip:IsOwned(self)) then GameTooltip:Hide() end
    end)
end





local function wayLeft(route, progress)
    if type(route) ~= "table" then return nil end
    local yards, seconds
    if type(progress) == "table" then yards, seconds = progress.remainingYards, progress.remainingSeconds end
    if type(yards) ~= "number" then yards = route.totalYards end
    if type(seconds) ~= "number" then seconds = route.totalSeconds end
    local Look = FGPS.UI.Look
    local distance = type(yards) == "number" and Look.Distance(yards) or nil
    local about = Look.About(seconds)
    if distance and about then return distance .. " \194\183 " .. about end
    return distance or about
end


local function placePin(pin, canvas, w, h, scale, entry, way)
    local Look = FGPS.UI.Look
    pin.normalizedX, pin.normalizedY = entry.x, entry.y
    pin.fgpsIndex, pin.fgpsName, pin.fgpsDest = entry.index, entry.name, entry.dest
    pin:SetScale(1 / scale)
    pin:ClearAllPoints()

    pin:SetPoint("CENTER", canvas, "TOPLEFT", (entry.x * w) * scale, -(entry.y * h) * scale)
    local final = entry.isFinal == true
    pin.Fill:SetShown(not final)
    pin.Ring:SetShown(not final)
    pin.Number:SetShown(not final)
    pin.Label:SetShown(not final)
    pin.Mark:SetShown(final)
    pin.Name:SetShown(final)
    pin.Sub:SetShown(final and way ~= nil)
    if final then
        pin.Mark:SetVertexColor(Look.Color("route"))
        pin.Name:SetText(entry.name or "")
        pin.Name:SetTextColor(Look.Color("gilt"))
        pin.Sub:SetText(way or "")
        pin.Sub:SetTextColor(Look.Color("grey"))
    else
        pin.Fill:SetVertexColor(Look.Color("paleRing"))
        pin.Ring:SetVertexColor(Look.Color("route"))
        pin.Number:SetText(tostring(entry.index))
        pin.Number:SetTextColor(Look.Color("rubric"))
        pin.Label:SetText(entry.name or "")
        pin.Label:SetTextColor(Look.Color("gilt"))
    end
    pin:Show()
end




local LABEL_OFFSET = 8

local function setupLabel(label)
    if label.fgpsReady then return end
    label.fgpsReady = true
    label:SetSize(1, 1)
    label.icon = label:CreateTexture(nil, "ARTWORK")
    label.icon:SetSize(DOCK_ICON_SIZE, DOCK_ICON_SIZE)
    label.icon:SetPoint("CENTER", label, "CENTER", 0, 0)
    label.icon:Hide()

    label.text = label:CreateFontString(nil, "OVERLAY", FGPS.UI.Look.Font("mapLabel"))
    label.text:SetJustifyH("LEFT")
    label:EnableMouse(false)
end

local function placeLabel(label, canvas, w, h, scale, entry)
    label.normalizedX, label.normalizedY = entry.x, entry.y
    label:SetScale(1 / scale)
    label:ClearAllPoints()
    label:SetPoint("CENTER", canvas, "TOPLEFT", (entry.x * w) * scale, -(entry.y * h) * scale)

    label.icon:SetShown(entry.icon ~= nil)
    if entry.icon then label.icon:SetTexture(entry.icon) end
    label.text:ClearAllPoints()
    label.text:SetPoint("LEFT", label, "CENTER", entry.icon and (DOCK_ICON_SIZE / 2 + 3) or LABEL_OFFSET, 0)
    label.text:SetText(entry.text)
    label.text:SetTextColor(FGPS.UI.Look.Color("gilt"))
    label:Show()
end




local function lineStart(route, progress)
    if type(route) ~= "table" or type(route.legs) ~= "table" or type(progress) ~= "table" then return nil end
    local legIndex, pos = progress.legIndex, progress.pos
    local leg = type(legIndex) == "number" and route.legs[legIndex] or nil
    if type(leg) ~= "table" or type(leg.points) ~= "table" or #leg.points < 1 then return nil end
    if type(pos) ~= "table" or type(pos.x) ~= "number" or type(pos.y) ~= "number" then return nil end
    local Minimap = FGPS.UI.Minimap
    if not (Minimap and Minimap.PointAhead) then return nil end

    local ok, from = pcall(Minimap.PointAhead, leg, progress.pointIndex, progress.alongYards, pos)
    if not ok or type(from) ~= "number" then return nil end
    return legIndex, from, pos
end



function WorldMap:Redraw()




    local drawIn = self.drawInPending == true
    self.drawInPending = false
    local map = WorldMapFrame
    if not map or not self.overlay then return end
    if not ensurePools() then return end
    self:ClearDrawing()
    local s = settings()



    local drawRoute = self.route ~= nil and not (s and s.worldMapLine == false)
    local markerSource = (drawRoute and self.route) or (self.markers and { stops = self.markers }) or nil
    if not drawRoute and not markerSource then return end
    if FGPS.Perf and FGPS.Perf.guidanceEnabled == false then return end
    if map.IsShown and not map:IsShown() then return end
    local mapID = map:GetMapID()
    if not mapID then return end

    local Perf = FGPS.Perf
    if Perf then Perf:Begin("mapRedraw") end
    local canvas = map:GetCanvas()
    self._viewL, self._viewT, self._viewR, self._viewB = visibleNormRect(map)
    if self.overlay and canvas and canvas.GetFrameLevel then


        self.overlay:SetFrameStrata("HIGH")
        local level = (canvas:GetFrameLevel() or 1) + 200
        if level > 4000 then level = 4000 end
        self.overlay:SetFrameLevel(level)
        if self.pinLayer then self.pinLayer:SetFrameStrata("HIGH") end
    end
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    local scale = canvasScale()
    local thickness = lineThickness(scale)


    local Navigator = FGPS.Navigator
    local levelZ
    if drawRoute and not self.routeIsPreview and Navigator and Navigator.LevelZ then
        local ok, z = pcall(Navigator.LevelZ, Navigator)
        if ok and type(z) == "number" then levelZ = z end
    end

    local fromLeg, fromPoint, fromPos
    if drawRoute and not self.routeIsPreview then fromLeg, fromPoint, fromPos = lineStart(self.route, self.progress) end
    self.drawnFromLeg, self.drawnFromPoint = fromLeg, fromPoint
    self.drawnFromInst, self.drawnFromX, self.drawnFromY = nil, nil, nil
    if fromPos then self.drawnFromInst, self.drawnFromX, self.drawnFromY = fromPos.inst, fromPos.x, fromPos.y end
    local segments, segInfo = {}, nil
    if drawRoute then



        local cache = self.segmentCache
        local posInst = fromPos and fromPos.inst or nil
        local posX = fromPos and fromPos.x or nil
        local posY = fromPos and fromPos.y or nil
        if cache and cache.route == self.route and cache.mapID == mapID and cache.levelZ == levelZ
            and cache.startLeg == fromLeg and cache.startPoint == fromPoint
            and cache.inst == posInst and cache.x == posX and cache.y == posY then
            segments, segInfo = cache.segments, cache.info
        else
            segments, segInfo = WorldMap.ComputeSegments(self.route, mapID,
                { levelZ = levelZ, startLeg = fromLeg, startPoint = fromPoint, startPos = fromPos })
            self.segmentCache = {
                route = self.route, mapID = mapID, levelZ = levelZ,
                startLeg = fromLeg, startPoint = fromPoint,
                inst = posInst, x = posX, y = posY,
                segments = segments, info = segInfo,
            }
        end
    end
    self.drawnLevelZ = levelZ
    self.levelBandLow = segInfo and segInfo.levelLow
    self.levelBandHigh = segInfo and segInfo.levelHigh
    local vr, vg, vb, va = strokeColor("routeVerified")
    local ur, ug, ub, ua = strokeColor("routeUnverified")
    local tr, tg, tb, ta = strokeColor("routeTransport")
    if self.routeIsPreview then va, ua, ta = va * 0.8, ua * 0.8, ta * 0.8 end
    local fade = WorldMap.OTHER_LEVEL_ALPHA

    local used = 0
    local budget = MAX_SEGMENTS




    local spareDashes = budget - #segments
    if spareDashes < 0 then spareDashes = 0 end


    drawIn = drawIn and drawRoute
    if drawIn then
        clearList(drawInOrder)
        clearList(drawInAt)
        clearList(drawInLength)
        inkFromX, inkFromY, inkFrom, inkLength, inkPer, inkOnX = nil, nil, 0, 0, 0, true
    end
    collectDrawIn = drawIn
    for _, seg in ipairs(segments) do
        if used >= budget then break end
        local x1, y1, x2, y2 = seg[1], seg[2], seg[3], seg[4]
        if drawIn then inkSegment(x1, y1, x2, y2, w, h) end

        local f = seg.otherLevel and fade or 1
        if seg.unverified then


            local dx, dy = (x2 - x1) * w * scale, (y2 - y1) * h * scale
            local length = sqrt(dx * dx + dy * dy)
            local period = DASH_ON + DASH_OFF
            local dashes = floor(length / period)
            if dashes > spareDashes then dashes = spareDashes end
            if dashes > 12 then dashes = 12 end





            local underAlpha = dashes > 1 and ua * DASH_UNDERLAY_ALPHA or ua
            emitLine(self.linePool, canvas, w, h, scale, x1, y1, x2, y2, ur, ug, ub, underAlpha * f, thickness)
            used = used + 1
            if dashes > 1 then
                spareDashes = spareDashes - dashes
                local onFrac = DASH_ON / period
                for d = 0, dashes - 1 do
                    local t0 = d / dashes
                    local t1 = (d + onFrac) / dashes
                    if d == dashes - 1 then t1 = 1 end
                    if t1 > 1 then t1 = 1 end
                    emitLine(self.linePool, canvas, w, h, scale,
                        x1 + (x2 - x1) * t0, y1 + (y2 - y1) * t0,
                        x1 + (x2 - x1) * t1, y1 + (y2 - y1) * t1, ur, ug, ub, ua * f, thickness)
                end
            end
        elseif seg.transport then

            local period = 8
            local onFrac = 0.45

            local dx, dy = (x2 - x1) * w * scale, (y2 - y1) * h * scale
            local len = sqrt(dx * dx + dy * dy)
            local dots = math.max(2, math.floor(len / period + 0.5))
            if dots > 24 then dots = 24 end



            if dots - 1 > spareDashes then dots = spareDashes + 1 end
            used = used + 1
            if dots < 2 then
                emitLine(self.linePool, canvas, w, h, scale, x1, y1, x2, y2, tr, tg, tb, ta * f, thickness)
            else
                spareDashes = spareDashes - (dots - 1)
                for d = 0, dots - 1 do
                    local t0 = d / dots
                    local t1 = (d + onFrac) / dots
                    if t1 > 1 then t1 = 1 end
                    if t1 > t0 then
                        emitLine(self.linePool, canvas, w, h, scale,
                            x1 + (x2 - x1) * t0, y1 + (y2 - y1) * t0,
                            x1 + (x2 - x1) * t1, y1 + (y2 - y1) * t1, tr, tg, tb, ta * f, thickness)
                    end
                end
            end
        else
            emitLine(self.linePool, canvas, w, h, scale, x1, y1, x2, y2, vr, vg, vb, va * f, thickness)
            used = used + 1
        end
    end
    collectDrawIn = false

    local stops = WorldMap.ComputeStops(markerSource, mapID)
    local way
    if #stops > 0 and drawRoute then way = wayLeft(self.route, not self.routeIsPreview and self.progress or nil) end

    self.finalPinShown = false
    for _, entry in ipairs(stops) do
        local pin = self.pinPool:Acquire()
        setupPin(pin)
        placePin(pin, canvas, w, h, scale, entry, way)
        if entry.isFinal then self.finalPinShown = true end
    end
    for _, entry in ipairs(drawRoute and WorldMap.ComputeTransportLabels(self.route, mapID, fromLeg) or {}) do
        local label = self.labelPool:Acquire()
        setupLabel(label)
        placeLabel(label, canvas, w, h, scale, entry)
    end
    self.lastSegmentCount = used
    self.lastDrawMapID = mapID
    self.drawnView = { mapID = mapID, scale = scale, w = w, h = h,
                       l = self._viewL, t = self._viewT, r = self._viewR, b = self._viewB }
    self:UpdateCartouche()

    if drawIn and #drawInOrder > 0 then
        startDrawIn(drawInOrder, inkLength)
        clearList(drawInOrder)
    end
    if Perf then Perf:End("mapRedraw") end
end





function WorldMap:RedrawForCanvas()
    local v, map = self.drawnView, WorldMapFrame
    local canvas = v and map and map.GetCanvas and map:GetCanvas()
    if canvas and map:GetMapID() == v.mapID and canvasScale() == v.scale
        and canvas:GetWidth() == v.w and canvas:GetHeight() == v.h then
        local l, t, r, b = visibleNormRect(map)
        if l == v.l and t == v.t and r == v.r and b == v.b then return end
    end
    self:Redraw()
end


function WorldMap:OnScaleChanged()


    self:RedrawForCanvas()
end




local function createProvider()
    local base = MapCanvasDataProviderMixin or {}
    local provider = CreateFromMixins(base)
    function provider:OnAdded(owningMap)
        if base.OnAdded then base.OnAdded(self, owningMap) else self.owningMap = owningMap end
        if not WorldMap.overlay then
            local canvas = owningMap:GetCanvas()
            local overlay = CreateFrame("Frame", nil, canvas)
            overlay:SetAllPoints(canvas)


            overlay:SetFrameStrata("HIGH")
            overlay:SetFrameLevel((canvas:GetFrameLevel() or 1) + 40)
            overlay:EnableMouse(false)
            WorldMap.overlay = overlay




            local pinLayer = CreateFrame("Frame", nil, canvas)
            pinLayer:SetAllPoints(canvas)
            pinLayer:SetFrameStrata("HIGH")
            pinLayer:SetFrameLevel(math.min(9000, (canvas:GetFrameLevel() or 1) + WorldMap.PIN_LAYER_LEVELS))
            pinLayer:EnableMouse(false)
            WorldMap.pinLayer = pinLayer
        end
    end
    function provider:OnRemoved(owningMap)
        WorldMap:ClearDrawing()
        if base.OnRemoved then pcall(base.OnRemoved, self, owningMap) else self.owningMap = nil end
    end
    function provider:RemoveAllData() WorldMap:ClearDrawing() end
    function provider:RefreshAllData() WorldMap:Redraw() end
    function provider:OnMapChanged()
        WorldMap:Redraw()

        local SearchLine = FGPS.UI.SearchLine
        if SearchLine and SearchLine.PlaceField then SearchLine.PlaceField() end
    end
    function provider:OnShow()
        WorldMap:Redraw()
        WorldMap:UpdateClearButton()
        WorldMap:OnMapShown()
        WorldMap:StartDistancePoll()
    end
    function provider:OnHide()
        WorldMap:StopDistancePoll()
        WorldMap:ClearDrawing()
        WorldMap:OnMapHidden()
    end
    function provider:OnCanvasScaleChanged() WorldMap:OnScaleChanged() end
    function provider:OnCanvasPanChanged() WorldMap:RedrawForCanvas() end
    function provider:OnCanvasSizeChanged() WorldMap:RedrawForCanvas() end
    return provider
end





function WorldMap.ClickMatches(button, modifier)
    modifier = modifier or (settings() and settings().mapClickModifier) or "CTRL_RIGHT"
    if modifier == "NONE" then return false end
    if modifier == "CTRL_RIGHT" then
        return button == "RightButton" and IsControlKeyDown and IsControlKeyDown() == true
    elseif modifier == "ALT_LEFT" then
        return button == "LeftButton" and IsAltKeyDown and IsAltKeyDown() == true
    elseif modifier == "SHIFT_RIGHT" then
        return button == "RightButton" and IsShiftKeyDown and IsShiftKeyDown() == true
    end
    return false
end




function WorldMap.GoTo(dest, opts)
    local Navigator = FGPS.Navigator
    if not dest or not Navigator or not Navigator.SetDestination then return false end
    local addStop = opts and opts.addStop or false
    local startNow = opts and opts.start == true


    local quiet = opts and opts.quiet == true
    local Search = FGPS.UI.Search
    if Search and Search.GoTo then
        local mode = addStop and "addStop" or (startNow and "start" or nil)
        return Search.GoTo(dest, mode, { quiet = quiet })
    end
    if addStop and Navigator.AddStop then
        Navigator:AddStop(dest, { quiet = quiet })
        return true
    end
    if startNow then
        Navigator:SetDestination(dest, { start = true, quiet = quiet })
        return true
    end
    local Preview = FGPS.UI.Preview


    local journey = Navigator.IsJourney and Navigator:IsJourney()
    if journey and Preview and Preview.ShowCalculating then Preview:ShowCalculating(dest) end
    Navigator:SetDestination(dest, { start = false, quiet = quiet })
    if journey then return true end
    if Preview and Preview.ShowCalculating then Preview:ShowCalculating(dest) end
    if Navigator.Preview then Navigator:Preview() end
    return true
end



function WorldMap.IsGoClick(button)
    return button == "LeftButton" and IsShiftKeyDown ~= nil and IsShiftKeyDown() == true
end



WorldMap.GO_REFUSED_SECONDS = 4

local function reasonText(err)
    local C = FGPS.UI and FGPS.UI.Compat
    if C and C.ReasonText then return C.ReasonText(err, L["unknown reason"]) end
    return tostring(err)
end

function WorldMap:OnCanvasClick(mapCanvas, button, cursorX, cursorY)
    local goNow = WorldMap.IsGoClick(button)
    if not (goNow or WorldMap.ClickMatches(button)) then return false end
    local Destinations = FGPS.Destinations
    if not Destinations or not Destinations.FromMapClick then return false end
    local mapID = mapCanvas and mapCanvas.GetMapID and mapCanvas:GetMapID() or (WorldMapFrame and WorldMapFrame:GetMapID())
    if not mapID then return false end
    if type(cursorX) ~= "number" or type(cursorY) ~= "number" then
        if mapCanvas and mapCanvas.GetNormalizedCursorPosition then cursorX, cursorY = mapCanvas:GetNormalizedCursorPosition() end
    end
    if type(cursorX) ~= "number" or type(cursorY) ~= "number" then return false end



    local ok, dest, err = pcall(Destinations.FromMapClick, mapID, cursorX, cursorY)
    if not ok then
        FGPS.Log:Error("FromMapClick failed: %s", tostring(dest))
        return goNow
    end
    if not dest then
        if goNow then

            local Guide = FGPS.UI.Guide
            if Guide and Guide.Say then Guide.Say(L["That spot cannot be reached"], WorldMap.GO_REFUSED_SECONDS) end
        else

            local Guide = FGPS.UI and FGPS.UI.Guide
            if Guide and Guide.Say then
                Guide.Say((L["That map position cannot be used as a destination%s"]):format(err and (": " .. reasonText(err)) or "."),
                    WorldMap.GO_REFUSED_SECONDS)
            end
        end
        return true
    end
    if goNow then


        local Go = FGPS.UI.Go
        if Go and Go.Start then Go.Start(dest) end
        return true
    end
    local addStop = FGPS.UI.Search and FGPS.UI.Search.addStopMode == true
    WorldMap.GoTo(dest, { addStop = addStop })
    return true
end














function WorldMap.TooltipLines()
    local Launcher = FGPS.UI.Launcher
    local hint
    if Launcher and type(Launcher.ClickHint) == "function" then
        hint = Launcher.ClickHint()
    else
        hint = L["Click to open"] .. " \194\183 " .. L["Right-click for options"]
    end
    return {
        L.ADDON_TITLE,
        L["A solid line is a road or walkable ground, a dashed line open ground or a guess."],
        hint,
    }
end

local function showCompassTooltip(button)
    local lines = WorldMap.TooltipLines()
    FGPS.UI.Look.Tooltip(button, lines[1], lines[2], lines[3], "ANCHOR_LEFT")
end




























WorldMap.CARTOUCHE_MAX_WIDTH = 260



local function inkEdges(frame)
    if not (type(PixelUtil) == "table" and type(PixelUtil.SetHeight) == "function"
        and type(PixelUtil.SetWidth) == "function") then
        return nil
    end
    local Look = FGPS.UI.Look
    local edges = {}
    local function edge(horizontal, a, b)
        local tex = frame:CreateTexture(nil, "BORDER")
        tex:SetColorTexture(Look.Color("ink"))
        tex:SetPoint(a, frame, a, 0, 0)
        tex:SetPoint(b, frame, b, 0, 0)
        if horizontal then PixelUtil.SetHeight(tex, 1, 1) else PixelUtil.SetWidth(tex, 1, 1) end
        edges[#edges + 1] = tex
    end
    edge(true, "TOPLEFT", "TOPRIGHT")
    edge(true, "BOTTOMLEFT", "BOTTOMRIGHT")
    edge(false, "TOPLEFT", "BOTTOMLEFT")
    edge(false, "TOPRIGHT", "BOTTOMRIGHT")
    return edges
end

local function ensureCartouche()
    if WorldMap.cartouche then return WorldMap.cartouche end
    local map = WorldMapFrame
    if not map then return nil end
    local picture = map.ScrollContainer or (map.GetCanvasContainer and map:GetCanvasContainer()) or map
    local Look = FGPS.UI.Look
    local tokens = Look.TOKENS
    local frame = CreateFrame("Frame", nil, picture)
    frame:EnableMouse(false)
    frame:SetPoint("TOPRIGHT", picture, "TOPRIGHT", -tokens.gapWide, -tokens.gapWide)







    if frame.SetFrameStrata then pcall(frame.SetFrameStrata, frame, "HIGH") end
    if frame.SetFrameLevel and WorldMap.overlay and WorldMap.overlay.GetFrameLevel then
        pcall(frame.SetFrameLevel, frame, (WorldMap.overlay:GetFrameLevel() or 1) + 2)
    end
    frame.Ground = frame:CreateTexture(nil, "BACKGROUND")
    frame.Ground:SetAllPoints(frame)
    frame.Ground:Hide()
    frame.Edges = inkEdges(frame)
    frame.Line1 = frame:CreateFontString(nil, "OVERLAY", Look.Font("pageBody"))
    frame.Line1:SetPoint("TOPLEFT", frame, "TOPLEFT", tokens.gapWide, -tokens.gap)
    frame.Line1:SetJustifyH("LEFT")
    frame.Line1:SetWordWrap(false)
    frame.Line2 = frame:CreateFontString(nil, "OVERLAY", Look.Font("pageSub"))
    frame.Line2:SetPoint("TOPLEFT", frame.Line1, "BOTTOMLEFT", 0, -tokens.gap)
    frame.Line2:SetJustifyH("LEFT")
    frame.Line2:SetWordWrap(false)
    frame:Hide()
    WorldMap.cartouche = frame
    return frame
end




local function paintGround(frame)
    local Look = FGPS.UI.Look
    if Look.TomeHas("atlas", Look.PARCHMENT_ATLAS) then
        if frame.Ground._fgpsAtlas ~= Look.PARCHMENT_ATLAS then
            frame.Ground:SetAtlas(Look.PARCHMENT_ATLAS)
            frame.Ground._fgpsAtlas = Look.PARCHMENT_ATLAS
        end
        frame.Ground:Show()
    else
        frame.Ground:Hide()
        Look.NoteOnce("map:cartouche", "World map label: atlas %s missing; the words show with no ground", Look.PARCHMENT_ATLAS)
    end
end



local function cartoucheWords(route, xShown)
    local stops = type(route.stops) == "table" and route.stops or {}
    local last = stops[#stops]
    local dest = type(last) == "table" and (last.dest or last) or nil
    local name = type(dest) == "table" and dest.name or nil
    if not (type(name) == "string" and name ~= "") then
        local legs = type(route.legs) == "table" and route.legs or {}
        local leg = legs[#legs]
        name = type(leg) == "table" and leg.label or nil
    end
    local first = (type(name) == "string" and name ~= "") and format(L["Route to %s"], name) or L["Route"]
    local count = math.max(1, #stops)
    local second = format(count == 1 and L["%d stop"] or L["%d stops"], count)
    if xShown then second = second .. " \194\183 " .. L["Right-click the X for options"] end
    return first, second
end



local function setWords(frame, first, second)
    if frame.fgpsFirst == first and frame.fgpsSecond == second then return end
    frame.fgpsFirst, frame.fgpsSecond = first, second
    local tokens = FGPS.UI.Look.TOKENS
    frame.Line1:SetWidth(0)
    frame.Line2:SetWidth(0)
    frame.Line1:SetText(first)
    frame.Line2:SetText(second)
    local wide = math.max(frame.Line1:GetStringWidth() or 0, frame.Line2:GetStringWidth() or 0)
    local width = math.min(ceil(wide), WorldMap.CARTOUCHE_MAX_WIDTH)
    frame.Line1:SetWidth(width)
    frame.Line2:SetWidth(width)
    local height = (frame.Line1:GetStringHeight() or 0) + tokens.gap + (frame.Line2:GetStringHeight() or 0)
    frame:SetSize(width + 2 * tokens.gapWide, ceil(height) + 2 * tokens.gap)
end



function WorldMap.CartoucheWanted()
    local s = settings()
    if s and s.worldMapLegend == false then return false end
    if not WorldMap.route then return false end
    if s and s.worldMapLine == false then return false end
    if FGPS.Perf and FGPS.Perf.guidanceEnabled == false then return false end
    return WorldMap.lastSegmentCount > 0
end

function WorldMap:UpdateCartouche()


    if FGPS.MapShot and FGPS.MapShot.IsRunning and FGPS.MapShot.IsRunning() then
        if WorldMap.cartouche then WorldMap.cartouche:Hide() end
        return false
    end
    if not WorldMap.CartoucheWanted() then
        if WorldMap.cartouche then WorldMap.cartouche:Hide() end
        return false
    end
    local frame = ensureCartouche()
    if not frame then return false end
    local Look = FGPS.UI.Look
    paintGround(frame)
    frame.Line1:SetTextColor(Look.Color("ink"))
    frame.Line2:SetTextColor(Look.Color("inkGrey"))
    setWords(frame, cartoucheWords(WorldMap.route, WorldMap.finalPinShown == true))
    frame:Show()
    return true
end



local function raiseAboveBorder(button, anchor)
    if not anchor.GetFrameStrata then return end
    pcall(button.SetFrameStrata, button, "HIGH")
    pcall(button.SetFrameLevel, button, (WorldMap.overlay and WorldMap.overlay:GetFrameLevel() or anchor:GetFrameLevel()) + 2)
end






function WorldMap.SomethingIsSet()
    local Navigator = FGPS.Navigator
    if Navigator and Navigator.HasAnythingSet then
        local ok, set = pcall(Navigator.HasAnythingSet, Navigator)
        if ok and set then return true end
    end
    return WorldMap.route ~= nil or WorldMap.markers ~= nil
end





function WorldMap:ClearAll()
    local Navigator = FGPS.Navigator
    local cleared = false
    if Navigator and Navigator.Clear then
        local ok, result = pcall(Navigator.Clear, Navigator, "user", { quiet = true })
        if ok then
            cleared = result and true or false
        elseif FGPS.Log then
            FGPS.Log:Error("Navigator:Clear failed: %s", tostring(result))
        end
    end
    if self.route or self.markers then
        self.route, self.routeIsPreview, self.markers = nil, false, nil
        self:Redraw()
    end
    self:UpdateClearButton()


    if cleared then
        local Guide = FGPS.UI and FGPS.UI.Guide
        if Guide and Guide.Say then
            Guide.Say((L["Cleared. No route and no stops are set. Undo for %d seconds (/cabbie undo)."]):format(Navigator.UNDO_SECONDS),
                Navigator.CLEARED_HOLD)
        end
    end
end



function WorldMap:UpdateClearButton()
    local button = self.clearButton
    if not button then return false end
    local show = WorldMap.SomethingIsSet()
    if show ~= button:IsShown() then
        button:SetShown(show)

        if show then button.Icon:SetTexture(WorldMap.CLEAR_ICON) end

        if not show and GameTooltip and (not GameTooltip.IsOwned or GameTooltip:IsOwned(button)) then GameTooltip:Hide() end
    end
    return show
end


function WorldMap.ClearTooltipLines()
    return {
        L["Stop Route"],
        L["Removes the route, the preview, every stop and their markers. Nothing stays set."],
    }
end




local function createClearButton(compass, anchor)
    if WorldMap.clearButton then return WorldMap.clearButton end
    local button = CreateFrame("Button", nil, compass:GetParent())
    button:SetSize(WorldMap.CLEAR_BUTTON_SIZE, WorldMap.CLEAR_BUTTON_SIZE)
    button.Icon = button:CreateTexture(nil, "ARTWORK")
    button.Icon:SetAllPoints(button)
    button.Icon:SetTexture(WorldMap.CLEAR_ICON)
    if button.SetHighlightTexture then
        pcall(button.SetHighlightTexture, button, "Interface\\Buttons\\ButtonHilight-Square", "ADD")
    end
    button:SetScript("OnMouseDown", function(self) self.Icon:SetTexture(WorldMap.CLEAR_ICON_DOWN) end)
    button:SetScript("OnMouseUp", function(self) self.Icon:SetTexture(WorldMap.CLEAR_ICON) end)
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", function() WorldMap:ClearAll() end)
    button:SetPoint("RIGHT", compass, "LEFT", -WorldMap.CLEAR_BUTTON_GAP, 0)
    raiseAboveBorder(button, anchor)
    local Frames = FGPS.UI.Frames
    if Frames and Frames.Tooltip then
        pcall(Frames.Tooltip, button, WorldMap.ClearTooltipLines, "ANCHOR_LEFT")
    else
        button:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            for i, line in ipairs(WorldMap.ClearTooltipLines()) do
                if i == 1 then GameTooltip:AddLine(line) else GameTooltip:AddLine(line, 1, 1, 1, true) end
            end
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    button:Hide()
    WorldMap.clearButton = button
    return button
end

local function createMapButton()
    local map = WorldMapFrame
    if not map or WorldMap.button then return WorldMap.button end


    local button = CreateFrame("Button", nil, map)
    button:SetSize(WorldMap.BUTTON_SIZE, WorldMap.BUTTON_SIZE)
    button.Icon = button:CreateTexture(nil, "ARTWORK")
    button.Icon:SetAllPoints(button)
    button.Icon:SetTexture(WorldMap.BUTTON_ICON)
    if button.SetHighlightTexture then

        pcall(button.SetHighlightTexture, button, "Interface\\Buttons\\ButtonHilight-Square", "ADD")
    end

    button:SetScript("OnMouseDown", function(self) self.Icon:SetPoint("TOPLEFT", self, "TOPLEFT", 1, -1) self.Icon:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 1, -1) end)
    button:SetScript("OnMouseUp", function(self) self.Icon:ClearAllPoints() self.Icon:SetAllPoints(self) end)



    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            local Launcher = FGPS.UI.Launcher
            if Launcher and Launcher.OpenMenu then Launcher:OpenMenu(self) end
        else
            WorldMap:ToggleSearch()
        end
    end)

    local anchor = map.BorderFrame or map
    button:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -8, -26)
    raiseAboveBorder(button, anchor)

    button:SetScript("OnEnter", showCompassTooltip)
    button:SetScript("OnLeave", function(self)
        if GameTooltip and (not GameTooltip.IsOwned or GameTooltip:IsOwned(self)) then GameTooltip:Hide() end
    end)
    WorldMap.button = button
    createClearButton(button, anchor)
    return button
end

function WorldMap:ToggleSearch()
    local Search = FGPS.UI.Search
    if Search and Search.IsShown and Search.Show and Search.Hide then

        if Search:IsShown() then
            self.compassOpenedSearch = false
            Search:Hide()
        else
            Search:Show({ dock = WorldMapFrame })
            self.compassOpenedSearch = true
        end
    elseif Search and Search.Toggle then
        Search:Toggle()
    elseif FGPS.Slash then
        FGPS.Slash.Help()
    end
end




function WorldMap:OnMapShown()


    FGPS.Events:Fire("MAP_SHOWN")
    local s = settings()
    if s and s.openWithMap == false then return end
    local Search = FGPS.UI.Search
    if not (Search and Search.Show and Search.IsShown) or Search:IsShown() then return end

    local Tome = FGPS.UI.Tome
    if Tome and Tome.window and Tome.window:IsShown() then return end
    local ok, shown = pcall(Search.Show, Search, { dock = WorldMapFrame, noFocus = true })
    self.autoOpenedSearch = ok and shown == true
    if not ok and FGPS.Log then FGPS.Log:Error("Opening the search with the map failed: %s", tostring(shown)) end
end

function WorldMap:OnMapHidden()
    FGPS.Events:Fire("MAP_HIDDEN")
    local Search = FGPS.UI.Search


    if not (self.autoOpenedSearch or self.compassOpenedSearch) then return end
    self.autoOpenedSearch = false
    self.compassOpenedSearch = false
    if Search and Search.Hide then pcall(Search.Hide, Search) end
end


local function pollPosition()
    local Coords = FGPS.Coords
    if not (Coords and Coords.PlayerPos) then return nil end
    local ok, pos = pcall(Coords.PlayerPos)
    if not ok or type(pos) ~= "table" or pos.inst == nil or not pos.x or not pos.y then return nil end
    return pos
end

local function stoodStill()
    local prev = WorldMap.pollPos
    local pos = pollPosition()
    local Coords = FGPS.Coords
    if not prev or not pos or not (Coords and Coords.WorldDistance) then return false end
    local yards = Coords.WorldDistance(prev.inst, prev.x, prev.y, pos.inst, pos.x, pos.y)
    local limit = WorldMap.DISTANCE_POLL_STILL_YARDS or 5
    return type(yards) == "number" and yards < limit
end



function WorldMap:PollDistances()
    if stoodStill() then return end
    self.pollPos = pollPosition()
    local Search = FGPS.UI.Search
    if Search and Search.IsShown and Search:IsShown() and Search.RefreshDistances then
        pcall(Search.RefreshDistances, Search)
    end
    local QuestPanel = FGPS.UI.QuestPanel
    if QuestPanel and QuestPanel.IsShown and QuestPanel:IsShown() and QuestPanel.RefreshDistances then



        pcall(QuestPanel.RefreshDistances, QuestPanel)
    end
    local MapPlaces = FGPS.UI.MapPlaces
    if MapPlaces and MapPlaces.RefreshOpenTooltip then
        pcall(MapPlaces.RefreshOpenTooltip, MapPlaces)
    end
end

function WorldMap:StartDistancePoll()
    if self.distanceTicker then return end
    if not (C_Timer and C_Timer.NewTicker) then return end


    self.pollPos = pollPosition()
    local seconds = self.DISTANCE_POLL_SECONDS or 5
    self.distanceTicker = C_Timer.NewTicker(seconds, function()
        WorldMap:PollDistances()
    end)
end

function WorldMap:StopDistancePoll()
    local ticker = self.distanceTicker
    self.distanceTicker = nil
    self.pollPos = nil
    if ticker and ticker.Cancel then pcall(ticker.Cancel, ticker) end
end




function WorldMap:Attach()
    if self.attached then return true end
    local map = WorldMapFrame
    if not map or not map.AddDataProvider or not CreateFromMixins then
        FGPS.Log:Warn("WorldMapFrame data providers unavailable; map route drawing disabled")
        return false
    end
    self.provider = self.provider or createProvider()
    local ok, err = pcall(map.AddDataProvider, map, self.provider)
    if not ok then
        FGPS.Log:Error("WorldMapFrame:AddDataProvider failed: %s", tostring(err))
        return false
    end


    if map.AddCanvasClickHandler then
        local handler = self.clickHandler or function(mapCanvas, button, cursorX, cursorY)
            return WorldMap:OnCanvasClick(mapCanvas, button, cursorX, cursorY)
        end
        local added, addErr = pcall(map.AddCanvasClickHandler, map, handler, CLICK_PRIORITY)
        if added then
            self.clickHandler = handler
        else
            FGPS.Log:Error("WorldMapFrame:AddCanvasClickHandler failed: %s", tostring(addErr))
        end
    end
    createMapButton()
    self.attached = true
    self:SyncWithNavigator()
    return true
end




function WorldMap:SyncWithNavigator()
    local Navigator = FGPS.Navigator
    if not self.markers and Navigator and Navigator.GetStops then
        local ok, stops = pcall(Navigator.GetStops, Navigator)
        if ok then self:SetMarkers(stops) end
    end
    self:UpdateClearButton()
end


local function followedRoute()
    local Navigator = FGPS.Navigator
    if not (Navigator and Navigator.IsJourney and Navigator.GetRoute) then return nil end
    local ok, journey = pcall(Navigator.IsJourney, Navigator)
    if not (ok and journey) then return nil end
    local okRoute, route = pcall(Navigator.GetRoute, Navigator)
    return okRoute and type(route) == "table" and route or nil
end

local function onRouteEvent(event, route)


    WorldMap.segmentCache = nil
    if event == "ROUTE_PREVIEW" then


        WorldMap.route = route or followedRoute()
        WorldMap.routeIsPreview = route ~= nil
    elseif event == "ROUTE_STARTED" or event == "ROUTE_UPDATED" then
        WorldMap.route = route or WorldMap.route
        WorldMap.routeIsPreview = false

        WorldMap.progress = nil

        if event == "ROUTE_STARTED" then WorldMap.drawInPending = true end
    elseif event == "NAV_CANCELLED" then
        WorldMap.route = nil
        WorldMap.routeIsPreview = false
        WorldMap.markers = nil
        WorldMap.progress = nil
    end
    WorldMap:Redraw()
    WorldMap:UpdateClearButton()
end




local function hasLevels(route)
    for _, leg in ipairs(route.legs or {}) do
        local points = type(leg) == "table" and leg.points
        if type(points) == "table" then
            for i = 2, #points do
                local p, q = points[i - 1], points[i]
                if type(q) == "table" and q.k == 22 and q.stacked and type(p) == "table" and p.stacked then return true end
            end
        end
    end
    return false
end




local function levelChanged(route)
    if WorldMap.levelsRoute ~= route then WorldMap.levelsRoute, WorldMap.routeHasLevels = route, hasLevels(route) end
    if not WorldMap.routeHasLevels then return false end
    local Navigator = FGPS.Navigator
    local z
    if Navigator and Navigator.LevelZ then
        local ok, got = pcall(Navigator.LevelZ, Navigator)
        if ok and type(got) == "number" then z = got end
    end
    local drawn = WorldMap.drawnLevelZ
    if z == nil and drawn == nil then return false end
    if z and drawn then
        local low, high = WorldMap.levelBandLow, WorldMap.levelBandHigh
        if (low == nil or z > low) and (high == nil or z < high) then return false end
    end
    return true
end


local function movedOn(pos)
    local x, y = WorldMap.drawnFromX, WorldMap.drawnFromY
    if not pos or not x or pos.inst ~= WorldMap.drawnFromInst then return false end
    local dx, dy, yards = pos.x - x, pos.y - y, WorldMap.PROGRESS_MOVE_YARDS
    return dx * dx + dy * dy >= yards * yards
end










function WorldMap:OnRouteProgress(progress)
    if progress ~= nil then self.progress = progress end
    local route = self.route
    if not route or self.routeIsPreview then return end
    local map = WorldMapFrame
    if not (map and map.IsShown and map:IsShown()) then return end
    local s = settings()
    if (s and s.worldMapLine == false) or (FGPS.Perf and FGPS.Perf.guidanceEnabled == false) then return end
    local leg, point, pos = lineStart(route, self.progress)
    if leg == self.drawnFromLeg and point == self.drawnFromPoint and not movedOn(pos) and not levelChanged(route) then return end
    local t = GetTime and GetTime() or 0


    if self.drawInUntil and t < self.drawInUntil then return end
    if self.progressRedrawAt and t - self.progressRedrawAt < self.PROGRESS_REDRAW_SECONDS then return end
    self.progressRedrawAt = t
    self:Redraw()
end

local function onArrived(_, stopIndex, isFinal)
    if isFinal ~= false then
        WorldMap.route = nil
        WorldMap.routeIsPreview = false
        WorldMap.markers = nil
        WorldMap.progress = nil
        WorldMap:Redraw()
    end
    WorldMap:UpdateClearButton()
end








local function onNavState(_, state)
    if state == "idle" and WorldMap.route then
        local Navigator = FGPS.Navigator
        local held
        if Navigator and Navigator.GetRoute then
            local ok, route = pcall(Navigator.GetRoute, Navigator)
            if ok then held = route end
        end
        if held == nil then
            WorldMap.route, WorldMap.routeIsPreview, WorldMap.progress = nil, false, nil
            WorldMap:Redraw()
        end
    end
    WorldMap:UpdateClearButton()
end



function WorldMap:SetMarkers(stops)
    local markers
    if type(stops) == "table" and #stops > 0 then
        markers = {}
        for _, dest in ipairs(stops) do
            if type(dest) == "table" then
                markers[#markers + 1] = { inst = dest.inst, x = dest.x, y = dest.y, name = dest.name }
            end
        end
        if #markers == 0 then markers = nil end
    end
    self.markers = markers
    self:Redraw()
    self:UpdateClearButton()
end

local function onItineraryChanged(_, stops)
    WorldMap:SetMarkers(stops)
end

local function onSettingsChanged(_, key)
    if key == "worldMapLine" or key == "worldMapLegend" or key == "*" or key == "perf.guidanceEnabled"
        or key == "preset" or key == "accessibility.colorScheme" then
        WorldMap.segmentCache = nil
        WorldMap:Redraw()
    end
end

function WorldMap:Init()
    if not self.eventsBound then
        self.eventsBound = true
        local Events = FGPS.Events
        Events:Register("ROUTE_PREVIEW", onRouteEvent, self)
        Events:Register("ROUTE_STARTED", onRouteEvent, self)
        Events:Register("ROUTE_UPDATED", onRouteEvent, self)
        Events:Register("NAV_CANCELLED", onRouteEvent, self)
        Events:Register("NAV_ARRIVED", onArrived, self)
        Events:Register("ROUTE_PROGRESS", function(_, progress) WorldMap:OnRouteProgress(progress) end, self)
        Events:Register("NAV_STATE", onNavState, self)
        Events:Register("ITINERARY_CHANGED", onItineraryChanged, self)
        Events:Register("SETTINGS_CHANGED", onSettingsChanged, self)
        Events:Register("UI_PRESET_APPLIED", function() WorldMap:Redraw() end, self)

        Events:Register("ADDON_READY", function() WorldMap:Attach() end, self)
        if not WorldMapFrame then
            local onAddonLoaded
            onAddonLoaded = function(_, name)
                if name ~= "Blizzard_WorldMap" then return end

                Events:UnregisterWoW("ADDON_LOADED", onAddonLoaded)
                if FGPS.ready then WorldMap:Attach() end
            end
            Events:RegisterWoW("ADDON_LOADED", onAddonLoaded, self)
        end
    end

    local Navigator = FGPS.Navigator
    if not self.route and Navigator and Navigator.GetRoute then
        local ok, route = pcall(Navigator.GetRoute, Navigator)
        if ok and type(route) == "table" then
            self.route = route
            local okState, state = pcall(Navigator.GetState, Navigator)
            self.routeIsPreview = okState and state == "previewing" or false
        end
    end
    if FGPS.ready then self:Attach() end
end
