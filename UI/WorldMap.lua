

























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
    distanceTicker = nil,
    route = nil,
    routeIsPreview = false,
    attached = false,
    clickHandler = nil,
    lastSegmentCount = 0,
    lastDrawMapID = nil,




    OTHER_LEVEL_ALPHA = 0.4,
    OTHER_LEVEL_YARDS = 6,


    LEVEL_REDRAW_SECONDS = 1,
    drawnLevelZ = nil,
    levelBandLow = nil,
    levelBandHigh = nil,
    levelRedrawAt = nil,
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
local PIN_SIZE = 28
local NUMBER_FONT = "GameFontNormalSmall"
local PIN_TEXTURE = "Interface\\AddOns\\Cabbie\\Media\\pin"
local PIN_GLOW_TEXTURE = "Interface\\AddOns\\Cabbie\\Media\\dot"


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

local DEFAULT_COLORS = {
    routeVerified = { 0.25, 0.80, 1.00, 0.95 },
    routeUnverified = { 1.00, 0.55, 0.10, 0.95 },
    routeTransport = { 0.80, 0.65, 1.00, 0.85 },
    accent = { 0.31, 0.76, 0.97, 1.0 },
}




local function settings()
    return FGPS.DB and FGPS.DB.settings or nil
end

local function skinColor(name)
    local Skins = FGPS.UI.Skins
    if Skins and Skins.Current then
        local ok, skin = pcall(Skins.Current)
        if ok and type(skin) == "table" and type(skin.colors) == "table" then
            local c = skin.colors[name]
            if type(c) == "table" then
                local r, g, b, a = c[1] or c.r, c[2] or c.g, c[3] or c.b, c[4] or c.a
                if r and g and b then return r, g, b, a or 1 end
            end
        end
    end
    local d = DEFAULT_COLORS[name] or DEFAULT_COLORS.routeVerified
    return d[1], d[2], d[3], d[4]
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












local function fromContinent(inst, x, y, mapID)
    local continent = continentMap(inst)
    local row = mapRow(mapID)
    if not continent or continent == mapID or not row or row.kind ~= 3 then return nil end
    if not (C_Map and C_Map.GetMapRectOnMap) then return nil end
    local Coords = FGPS.Coords
    if not (Coords and Coords.WorldToMap) then return nil end
    local _, cx, cy = Coords.WorldToMap(inst, x, y, continent)
    if not cx or not cy then return nil end
    local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, mapID, continent)
    if not ok or type(minX) ~= "number" or type(maxX) ~= "number" or type(minY) ~= "number" or type(maxY) ~= "number" then
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
    if row and row.kind == 3 and continent and continent ~= mapID and C_Map and C_Map.GetMapRectOnMap then
        local c = mapRow(continent)
        local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, mapID, continent)
        if ok and c and c.minX and type(maxX) == "number" and maxX > minX and maxY > minY then
            mapW = (maxX - minX) * math.abs(c.maxX - c.minX)
            mapH = (maxY - minY) * math.abs(c.maxY - c.minY)
        end
    end
    if not mapW and row and row.minX and row.maxX and row.minY and row.maxY then
        mapW = math.abs(row.maxX - row.minX)
        mapH = math.abs(row.maxY - row.minY)
    end


    local prepared, candidates = {}, 0
    for legIndex, leg in ipairs(route.legs) do
        local points = type(leg) == "table" and leg.points or nil
        if type(points) == "table" and #points >= 2 and not TELEPORT_KINDS[leg.kind or ""]
            and not TRACKLESS_KINDS[leg.kind or ""]
            and (inst == nil or leg.inst == nil or leg.inst == inst or leg.toInst == inst) then
            local jump = jumpIndex(leg, points)
            local pts, thinned = points, false


            if not jump then pts, thinned = simplify(leg, points, tolerance) end
            if thinned then info.truncated = true end
            prepared[#prepared + 1] = { leg = leg, index = legIndex, points = pts, jump = jump }
            candidates = candidates + (#pts - 1)
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
        local legInst = leg.inst or inst
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
                    pins[#pins + 1] = { x = mx, y = my, index = i, name = dest.name, isFinal = (i == #stops) }
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









function WorldMap.ComputeTransportLabels(route, mapID)
    local labels = {}
    if type(route) ~= "table" or type(route.legs) ~= "table" or type(mapID) ~= "number" then return labels end
    local inst = mapInstance(mapID)
    local Route = FGPS.Route
    for legIndex, leg in ipairs(route.legs) do
        local points = type(leg) == "table" and leg.points or nil
        if type(points) == "table" and #points >= 2 and TRANSPORT_KINDS[leg.kind or ""] and leg.inst ~= nil
            and ((leg.toInst ~= nil and leg.toInst ~= leg.inst) or TRACKLESS_KINDS[leg.kind]) then
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

    if self.legend then self.legend:Hide() end
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
        placeLine(pool:Acquire(), canvas, w, h,
            x1 + (x2 - x1) * t0, y1 + (y2 - y1) * t0,
            x1 + (x2 - x1) * t1, y1 + (y2 - y1) * t1, r, g, b, a, thickness)
    end
    return pieces
end

local function setupPin(pin)
    if pin.fgpsReady then return end
    pin.fgpsReady = true
    pin:SetSize(PIN_SIZE, PIN_SIZE)


    pin.glow = pin:CreateTexture(nil, "BACKGROUND")
    pin.glow:SetSize(PIN_SIZE * 1.7, PIN_SIZE * 1.7)
    pin.glow:SetPoint("CENTER", pin, "TOP", 0, -PIN_SIZE * 0.36)
    pin.glow:SetTexture(PIN_GLOW_TEXTURE)
    pin.bg = pin:CreateTexture(nil, "ARTWORK")
    pin.bg:SetAllPoints(pin)
    pin.bg:SetTexture(PIN_TEXTURE)
    pin.number = pin:CreateFontString(nil, "OVERLAY", NUMBER_FONT)

    pin.number:SetPoint("CENTER", pin, "TOP", 0, -PIN_SIZE * 0.36)
    pin.number:SetTextColor(0.08, 0.10, 0.14, 1)



    pin:EnableMouse(true)
    pin:RegisterForClicks("RightButtonUp")
    pin:SetScript("OnClick", function(self, button)
        if button ~= "RightButton" then return end
        if not (IsShiftKeyDown and IsShiftKeyDown()) then return end
        local index = self.fgpsIndex
        local Navigator = FGPS.Navigator
        if type(index) == "number" and Navigator and Navigator.RemoveStop then
            local ok, err = pcall(Navigator.RemoveStop, Navigator, index)
            if not ok then FGPS.Log:Error("RemoveStop failed: %s", tostring(err)) end
        end
    end)
    pin:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        local name = self.fgpsName or L["Stop"]
        local index = self.fgpsIndex or "?"
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(format(L["Stop %s: %s"], tostring(index), name))
        GameTooltip:AddLine(L["Shift+Right-click to remove"], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function(self)
        if GameTooltip and (not GameTooltip.IsOwned or GameTooltip:IsOwned(self)) then GameTooltip:Hide() end
    end)
end

local function placePin(pin, canvas, w, h, scale, entry)
    pin.normalizedX, pin.normalizedY = entry.x, entry.y
    pin.fgpsIndex, pin.fgpsName = entry.index, entry.name
    pin:SetScale(1 / scale)
    pin:ClearAllPoints()

    pin:SetPoint("BOTTOM", canvas, "TOPLEFT", (entry.x * w) * scale, -(entry.y * h) * scale)
    pin.number:SetText(tostring(entry.index))
    local r, g, b = skinColor("accent")
    if entry.isFinal then
        pin.bg:SetVertexColor(r, g, b, 1)
        pin.glow:SetVertexColor(r, g, b, 0.55)
    else

        pin.bg:SetVertexColor(0.92, 0.94, 0.98, 1)
        pin.glow:SetVertexColor(r, g, b, 0.30)
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
    label.text = label:CreateFontString(nil, "OVERLAY", NUMBER_FONT)
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
    local r, g, b = skinColor("routeTransport")
    label.text:SetTextColor(r, g, b, 1)
    label:Show()
end


function WorldMap:Redraw()
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
    local segments, segInfo = {}, nil
    if drawRoute then segments, segInfo = WorldMap.ComputeSegments(self.route, mapID, { levelZ = levelZ }) end
    self.drawnLevelZ = levelZ
    self.levelBandLow = segInfo and segInfo.levelLow
    self.levelBandHigh = segInfo and segInfo.levelHigh
    local vr, vg, vb, va = skinColor("routeVerified")
    local ur, ug, ub, ua = skinColor("routeUnverified")
    local tr, tg, tb, ta = skinColor("routeTransport")
    if self.routeIsPreview then va, ua, ta = va * 0.8, ua * 0.8, ta * 0.8 end
    local fade = WorldMap.OTHER_LEVEL_ALPHA

    local used = 0
    local budget = MAX_SEGMENTS




    local spareDashes = budget - #segments
    if spareDashes < 0 then spareDashes = 0 end
    for _, seg in ipairs(segments) do
        if used >= budget then break end
        local x1, y1, x2, y2 = seg[1], seg[2], seg[3], seg[4]

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

    for _, entry in ipairs(WorldMap.ComputeStops(markerSource, mapID)) do
        local pin = self.pinPool:Acquire()
        setupPin(pin)
        placePin(pin, canvas, w, h, scale, entry)
    end
    for _, entry in ipairs(drawRoute and WorldMap.ComputeTransportLabels(self.route, mapID) or {}) do
        local label = self.labelPool:Acquire()
        setupLabel(label)
        placeLabel(label, canvas, w, h, scale, entry)
    end
    self.lastSegmentCount = used
    self.lastDrawMapID = mapID
    self:UpdateLegend()
    if Perf then Perf:End("mapRedraw") end
end


function WorldMap:OnScaleChanged()


    self:Redraw()
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
    function provider:OnMapChanged() WorldMap:Redraw() end
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
    function provider:OnCanvasPanChanged() WorldMap:Redraw() end
    function provider:OnCanvasSizeChanged() WorldMap:Redraw() end
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
    local Search = FGPS.UI.Search
    if Search and Search.GoTo then
        local mode = addStop and "addStop" or (startNow and "start" or nil)
        return Search.GoTo(dest, mode)
    end
    if addStop and Navigator.AddStop then
        Navigator:AddStop(dest)
        return true
    end
    if startNow then
        Navigator:SetDestination(dest, { start = true })
        return true
    end
    local Preview = FGPS.UI.Preview


    local journey = Navigator.IsJourney and Navigator:IsJourney()
    if journey and Preview and Preview.ShowCalculating then Preview:ShowCalculating(dest) end
    Navigator:SetDestination(dest, { start = false })
    if journey then return true end
    if Preview and Preview.ShowCalculating then Preview:ShowCalculating(dest) end
    if Navigator.Preview then Navigator:Preview() end
    return true
end



function WorldMap.IsGoClick(button)
    return button == "LeftButton" and IsShiftKeyDown ~= nil and IsShiftKeyDown() == true
end



WorldMap.GO_REFUSED_SECONDS = 4

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
                Guide.Say((L["That map position cannot be used as a destination%s"]):format(err and (": " .. tostring(err)) or "."),
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














WorldMap.LEGEND = {
    { style = "solid", color = "routeVerified", text = "Solid line: road or walkable ground" },
    { style = "dashed", color = "routeUnverified", text = "Dashed line: open ground or a guess" },
    { style = "transport", color = "routeTransport", text = "Dotted coloured line: flight, boat or zeppelin" },
    { style = "icon", icon = DOCK_ICONS.boat, color = "routeTransport",
      text = "Boat or zeppelin icon: where you board; the label beside it names the far side" },
}

WorldMap.LEGEND_MINIMAP = "On the minimap a solid dot is a road or walkable ground, and a larger hollow dot is open ground or a guess."

local function colorEscape(colorName)
    local r, g, b = skinColor(colorName)
    local function byte(v) return floor(Util.Clamp(v or 1, 0, 1) * 255 + 0.5) end
    return string.format("|cff%02x%02x%02x", byte(r), byte(g), byte(b))
end




function WorldMap.TooltipLines()
    local lines = {
        L.ADDON_TITLE,
        L["Open the Cabbie destination search"],
        L["Right-click: clear the route and every stop"],
        L["Route lines on the map:"],
    }
    for _, entry in ipairs(WorldMap.LEGEND) do
        local icon = entry.icon and ("|T" .. entry.icon .. ":14|t ") or ""
        lines[#lines + 1] = icon .. colorEscape(entry.color) .. L[entry.text] .. "|r"
    end
    lines[#lines + 1] = L[WorldMap.LEGEND_MINIMAP]
    return lines
end




local LEGEND_SAMPLE_WIDTH = 26
local LEGEND_ROW_HEIGHT = 26
local LEGEND_WIDTH = 300




local function buildLegendRow(parent, index, entry)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(LEGEND_WIDTH - 12, LEGEND_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, -(4 + (index - 1) * LEGEND_ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, -(4 + (index - 1) * LEGEND_ROW_HEIGHT))
    row.samples = {}
    if entry.style == "icon" then
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetTexture(entry.icon)
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", row, "LEFT", (LEGEND_SAMPLE_WIDTH - 16) / 2, 0)
    else
        local pieces = (entry.style == "dashed") and 3 or 1
        local gap = (entry.style == "dashed") and 3 or 0
        local width = (LEGEND_SAMPLE_WIDTH - gap * (pieces - 1)) / pieces
        for i = 1, pieces do
            local tex = row:CreateTexture(nil, "ARTWORK")
            tex:SetTexture("Interface\\Buttons\\WHITE8X8")
            tex:SetSize(width, 2)
            tex:SetPoint("LEFT", row, "LEFT", (i - 1) * (width + gap), 0)
            row.samples[i] = tex
        end
    end
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row, "LEFT", LEGEND_SAMPLE_WIDTH + 6, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetJustifyV("MIDDLE")
    if row.text.SetWordWrap then row.text:SetWordWrap(true) end
    row.text:SetText(L[entry.text])
    row.color = entry.color
    return row
end

local function applyLegendColors(legend)
    for _, row in ipairs(legend.rows or {}) do
        local r, g, b, a = skinColor(row.color)
        for _, tex in ipairs(row.samples) do tex:SetVertexColor(r, g, b, a or 1) end
    end
end

local function ensureLegend()
    if WorldMap.legend then return WorldMap.legend end
    local map = WorldMapFrame
    if not map then return nil end


    local anchor = map.ScrollContainer or map.BorderFrame or map
    local legend = CreateFrame("Frame", nil, anchor)
    legend:SetSize(LEGEND_WIDTH, 10 + LEGEND_ROW_HEIGHT * #WorldMap.LEGEND + 32)
    legend:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 16, 28)
    legend:EnableMouse(false)
    if anchor.GetFrameStrata then
        pcall(legend.SetFrameStrata, legend, "HIGH")
        pcall(legend.SetFrameLevel, legend, (WorldMap.overlay and WorldMap.overlay:GetFrameLevel() or anchor:GetFrameLevel()) + 2)
    end
    legend.bg = legend:CreateTexture(nil, "BACKGROUND")
    legend.bg:SetAllPoints(legend)
    legend.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    legend.bg:SetVertexColor(0, 0, 0, 0.55)
    legend.rows = {}
    for i, entry in ipairs(WorldMap.LEGEND) do
        legend.rows[i] = buildLegendRow(legend, i, entry)
    end
    legend.note = legend:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    legend.note:SetPoint("TOPLEFT", legend, "TOPLEFT", 6, -(4 + #WorldMap.LEGEND * LEGEND_ROW_HEIGHT))
    legend.note:SetPoint("TOPRIGHT", legend, "TOPRIGHT", -6, -(4 + #WorldMap.LEGEND * LEGEND_ROW_HEIGHT))
    legend.note:SetJustifyH("LEFT")
    legend.note:SetText(L[WorldMap.LEGEND_MINIMAP])
    if legend.note.SetWordWrap then legend.note:SetWordWrap(true) end


    legend.close = FGPS.UI.Look.CloseButton(legend, function()
        if GameTooltip then GameTooltip:Hide() end
        if FGPS.DB then FGPS.DB:Set("worldMapLegend", false) end
    end)
    legend.close:EnableMouse(true)
    legend.close:SetSize(22, 22)
    legend.close:SetPoint("TOPRIGHT", legend, "TOPRIGHT", 2, 2)
    legend.close:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Hide the map legend"])
        GameTooltip:AddLine(L["Turn it back on in Cabbie's settings, or with /cabbie legend on."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    legend.close:SetScript("OnLeave", function(self)
        if GameTooltip and (not GameTooltip.IsOwned or GameTooltip:IsOwned(self)) then GameTooltip:Hide() end
    end)
    legend:Hide()
    WorldMap.legend = legend
    return legend
end


function WorldMap.LegendWanted()
    local s = settings()
    if s and s.worldMapLegend == false then return false end
    if not WorldMap.route then return false end
    if s and s.worldMapLine == false then return false end
    if FGPS.Perf and FGPS.Perf.guidanceEnabled == false then return false end
    return WorldMap.lastSegmentCount > 0
end

function WorldMap:UpdateLegend()
    local wanted = WorldMap.LegendWanted()
    local legend = WorldMap.legend
    if not wanted then
        if legend then legend:Hide() end
        return false
    end
    legend = ensureLegend()
    if not legend then return false end
    applyLegendColors(legend)
    legend:Show()
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
        L["Clear Cabbie"],
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
    local Frames = FGPS.UI.Frames


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
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then WorldMap:ClearAll() else WorldMap:ToggleSearch() end
    end)

    local anchor = map.BorderFrame or map
    button:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -8, -26)
    raiseAboveBorder(button, anchor)
    if Frames and Frames.Tooltip then

        pcall(Frames.Tooltip, button, WorldMap.TooltipLines, "ANCHOR_LEFT")
    else
        button:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            for i, line in ipairs(WorldMap.TooltipLines()) do
                if i == 1 then GameTooltip:AddLine(line) else GameTooltip:AddLine(line, 1, 1, 1, true) end
            end
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
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


function WorldMap:PollDistances()
    local Search = FGPS.UI.Search
    if Search and Search.IsShown and Search:IsShown() and Search.RefreshDistances then
        pcall(Search.RefreshDistances, Search)
    end
    local QuestPanel = FGPS.UI.QuestPanel
    if QuestPanel and QuestPanel.IsShown and QuestPanel:IsShown() and QuestPanel.Refresh then
        pcall(QuestPanel.Refresh, QuestPanel)
    end
    local MapPlaces = FGPS.UI.MapPlaces
    if MapPlaces and MapPlaces.RefreshOpenTooltip then
        pcall(MapPlaces.RefreshOpenTooltip, MapPlaces)
    end
end

function WorldMap:StartDistancePoll()
    if self.distanceTicker then return end
    if not (C_Timer and C_Timer.NewTicker) then return end
    local seconds = self.DISTANCE_POLL_SECONDS or 5
    self.distanceTicker = C_Timer.NewTicker(seconds, function()
        WorldMap:PollDistances()
    end)
end

function WorldMap:StopDistancePoll()
    local ticker = self.distanceTicker
    self.distanceTicker = nil
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

local function onRouteEvent(event, route)
    if event == "ROUTE_PREVIEW" then

        WorldMap.route = route
        WorldMap.routeIsPreview = route ~= nil
    elseif event == "ROUTE_STARTED" or event == "ROUTE_UPDATED" then
        WorldMap.route = route or WorldMap.route
        WorldMap.routeIsPreview = false
    elseif event == "NAV_CANCELLED" then
        WorldMap.route = nil
        WorldMap.routeIsPreview = false
        WorldMap.markers = nil
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





function WorldMap:OnRouteProgress()
    local route = self.route
    if not route or self.routeIsPreview then return end
    if self.levelsRoute ~= route then self.levelsRoute, self.routeHasLevels = route, hasLevels(route) end
    if not self.routeHasLevels then return end
    local map = WorldMapFrame

    if not (map and map.IsShown and map:IsShown()) then return end
    local Navigator = FGPS.Navigator
    local z
    if Navigator and Navigator.LevelZ then
        local ok, got = pcall(Navigator.LevelZ, Navigator)
        if ok and type(got) == "number" then z = got end
    end
    local drawn = self.drawnLevelZ
    if z == nil and drawn == nil then return end
    if z and drawn then
        local low, high = self.levelBandLow, self.levelBandHigh
        if (low == nil or z > low) and (high == nil or z < high) then return end
    end
    local t = GetTime and GetTime() or 0
    if self.levelRedrawAt and t - self.levelRedrawAt < self.LEVEL_REDRAW_SECONDS then return end
    self.levelRedrawAt = t
    self:Redraw()
end

local function onArrived(_, stopIndex, isFinal)
    if isFinal ~= false then
        WorldMap.route = nil
        WorldMap.routeIsPreview = false
        WorldMap.markers = nil
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
            WorldMap.route, WorldMap.routeIsPreview = nil, false
            WorldMap:Redraw()
        end
    end
    WorldMap:UpdateClearButton()
end



function WorldMap:SetMarkers(stops)
    local markers
    if type(stops) == "table" and #stops > 0 then
        markers = {}
        for i, dest in ipairs(stops) do
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
        Events:Register("ROUTE_PROGRESS", function() WorldMap:OnRouteProgress() end, self)
        Events:Register("NAV_STATE", onNavState, self)
        Events:Register("ITINERARY_CHANGED", onItineraryChanged, self)
        Events:Register("SETTINGS_CHANGED", onSettingsChanged, self)
        Events:Register("UI_PRESET_APPLIED", function() WorldMap:Redraw() end, self)

        Events:Register("ADDON_READY", function() WorldMap:Attach() end, self)
        if not WorldMapFrame then
            Events:RegisterWoW("ADDON_LOADED", function(_, name)
                if name == "Blizzard_WorldMap" and FGPS.ready then WorldMap:Attach() end
            end, self)
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
