










local ADDON_NAME, FGPS = ...

local L = FGPS.L
local sqrt, floor, max, min, pi = math.sqrt, math.floor, math.max, math.min, math.pi
local type, ipairs, pairs = type, ipairs, pairs

local Minimap = {
    pins = nil,
    dotPool = nil,
    nextPin = nil,
    destPin = nil,
    route = nil,
    progress = nil,
    lastRefresh = -math.huge,
    pendingTimer = nil,
    inCombat = false,
    active = false,
    lastDotCount = 0,
    drawn = nil,
    OTHER_LEVEL_YARDS = 8,
    OTHER_LEVEL_ALPHA = 0.35,
}
FGPS.UI.Minimap = Minimap

local MAX_DOTS = 40
local HIGHRES_MAX_DOTS = 64
local THROTTLE_SECONDS = 0.5
local HIGHRES_THROTTLE_SECONDS = 0.2
local RADIUS_FACTOR = 1.2
local DEFAULT_VIEW_RADIUS = 233.3
local MIN_SPACING = 8
local HIGHRES_MIN_SPACING = 5
local MAX_WALK_FACTOR = 4
local MOVE_EPSILON_YARDS = 1
local HIGHRES_MOVE_EPSILON_YARDS = 0.5
local REF = "Cabbie"

local function settings()
    return FGPS.DB and FGPS.DB.settings or nil
end

local function highResMode()
    local s = settings()
    local r = s and s.routing
    return type(r) == "table" and r.highRes == true
end

local function now()
    return GetTime and GetTime() or 0
end

local function viewRadius()
    if C_Minimap and C_Minimap.GetViewRadius then
        local ok, r = pcall(C_Minimap.GetViewRadius)
        if ok and type(r) == "number" and r > 0 then return r end
    end
    return DEFAULT_VIEW_RADIUS
end

local function combatPolicy()
    local Navigator = FGPS.Navigator
    if Navigator and Navigator.CombatPolicy then
        local ok, policy = pcall(Navigator.CombatPolicy, Navigator)
        if ok and type(policy) == "string" then return policy end
    end
    local s = settings()
    return s and s.combatMode or "visuals_only"
end


function Minimap:IsAllowed()
    if not self.pins or not self.route then return false end
    local s = settings()
    if s and s.minimapLine == false then return false end
    if FGPS.Perf and FGPS.Perf.guidanceEnabled == false then return false end
    if self.inCombat and combatPolicy() == "hide_all" then return false end
    return true
end












local DOT_SIZE = 5
local DOT_SIZE_UNVERIFIED = 8
local NEXT_PIN_SIZE = 9
local NEXT_MARK_SIZE = 4
local NEXT_LEVEL_SIZE = 7
local DEST_PIN_SIZE = 15
local DEST_MARK_SIZE = 10
local DEST_LEVEL_SIZE = 9
local HALO_GROWTH = 2




local DOT_TEXTURE = "Interface\\AddOns\\Cabbie\\Media\\dot"
local LEVEL_CHEVRON_TEXTURE = "Interface\\AddOns\\Cabbie\\Media\\arrow_chevron"
local INK_ALPHA = 0.95

local function makeDot()
    local parent = _G and _G.Minimap or UIParent
    local icon = CreateFrame("Frame", nil, parent)
    icon:SetSize(DOT_SIZE, DOT_SIZE)
    icon:EnableMouse(false)
    local ring = FGPS.UI.WorldMap.STOP_RING

    icon.Halo = icon:CreateTexture(nil, "BACKGROUND")
    icon.Halo:SetPoint("CENTER", icon, "CENTER", 0, 0)
    icon.Halo:SetTexture(ring)
    icon.Fill = icon:CreateTexture(nil, "BORDER")
    icon.Fill:SetPoint("CENTER", icon, "CENTER", 0, 0)
    icon.Fill:SetTexture(DOT_TEXTURE)

    icon.Ring = icon:CreateTexture(nil, "ARTWORK")
    icon.Ring:SetPoint("CENTER", icon, "CENTER", 0, 0)
    icon.Ring:SetTexture(ring)
    icon:Hide()
    return icon
end





local function makeMark(size, markTexture, markSize, levelSize)
    local parent = _G and _G.Minimap or UIParent
    local icon = CreateFrame("Frame", nil, parent)
    local WorldMap = FGPS.UI.WorldMap
    local ring = WorldMap.STOP_RING
    local ringBox = WorldMap.RING_BOX
    icon:SetSize(size, size)
    icon:EnableMouse(false)
    icon.Halo = icon:CreateTexture(nil, "BACKGROUND")
    icon.Halo:SetPoint("CENTER", icon, "CENTER", 0, 0)
    icon.Halo:SetSize((size + HALO_GROWTH) * ringBox, (size + HALO_GROWTH) * ringBox)
    icon.Halo:SetTexture(ring)
    icon.Fill = icon:CreateTexture(nil, "BORDER")
    icon.Fill:SetPoint("CENTER", icon, "CENTER", 0, 0)
    icon.Fill:SetSize(size, size)
    icon.Fill:SetTexture(DOT_TEXTURE)
    icon.Ring = icon:CreateTexture(nil, "ARTWORK")
    icon.Ring:SetPoint("CENTER", icon, "CENTER", 0, 0)
    icon.Ring:SetSize(size * ringBox, size * ringBox)
    icon.Ring:SetTexture(ring)
    icon.Mark = icon:CreateTexture(nil, "OVERLAY")
    icon.Mark:SetPoint("CENTER", icon, "CENTER", 0, 0)
    icon.Mark:SetSize(markSize, markSize)
    icon.Mark:SetTexture(markTexture)
    local lvSize = levelSize or NEXT_LEVEL_SIZE
    icon.LevelHalo = icon:CreateTexture(nil, "OVERLAY", nil, 1)
    icon.LevelHalo:SetSize(lvSize + 2, lvSize + 2)
    icon.LevelHalo:SetTexture(DOT_TEXTURE)
    icon.LevelHalo:Hide()
    icon.LevelMark = icon:CreateTexture(nil, "OVERLAY", nil, 2)
    icon.LevelMark:SetSize(lvSize, lvSize)
    icon.LevelMark:SetTexture(LEVEL_CHEVRON_TEXTURE)
    icon.LevelMark:Hide()
    icon.fgpsLevelDir = false
    icon:Hide()
    return icon
end

local function tintMark(icon, vr, vg, vb, pr, pg, pb)
    if not icon then return end
    icon.Halo:SetVertexColor(pr, pg, pb, 1)
    icon.Fill:SetVertexColor(pr, pg, pb, 1)
    icon.Ring:SetVertexColor(vr, vg, vb, INK_ALPHA)
    icon.Mark:SetVertexColor(vr, vg, vb, INK_ALPHA)
    if icon.LevelHalo then icon.LevelHalo:SetVertexColor(pr, pg, pb, 1) end
    if icon.LevelMark then icon.LevelMark:SetVertexColor(vr, vg, vb, INK_ALPHA) end
end

local function setLevelMark(icon, dir)
    if not (icon and icon.LevelMark and icon.LevelHalo) then return end
    dir = (dir == "up" or dir == "down") and dir or false
    if icon.fgpsLevelDir == dir then return end
    icon.fgpsLevelDir = dir
    if not dir then
        icon.LevelHalo:Hide()
        icon.LevelMark:Hide()
        return
    end
    icon.LevelMark:ClearAllPoints()
    icon.LevelHalo:ClearAllPoints()
    if dir == "up" then
        icon.LevelMark:SetPoint("BOTTOM", icon, "TOP", 0, -1)
        if icon.LevelMark.SetRotation then icon.LevelMark:SetRotation(0) end
    else
        icon.LevelMark:SetPoint("TOP", icon, "BOTTOM", 0, 1)
        if icon.LevelMark.SetRotation then icon.LevelMark:SetRotation(pi) end
    end
    icon.LevelHalo:SetPoint("CENTER", icon.LevelMark, "CENTER", 0, 0)
    icon.LevelHalo:Show()
    icon.LevelMark:Show()
end




local function raiseOverDots(icon, offset)
    if not (icon and icon.SetFrameLevel) then return end
    local parent = icon.GetParent and icon:GetParent() or (_G and _G.Minimap)
    local base = parent and parent.GetFrameLevel and parent:GetFrameLevel() or 1
    icon:SetFrameLevel(base + offset)
end





local function styleDot(icon, unverified, vr, vg, vb, ur, ug, ub, pr, pg, pb)
    unverified = unverified and true or false
    icon.unverified = unverified
    if pr == nil then pr, pg, pb = FGPS.UI.Look.Color("paleRing") end
    if icon.fgpsKind ~= unverified then
        icon.fgpsKind = unverified
        local size = unverified and DOT_SIZE_UNVERIFIED or DOT_SIZE
        local ringBox = FGPS.UI.WorldMap.RING_BOX
        icon:SetSize(size, size)
        icon.Fill:SetSize(size, size)
        icon.Ring:SetSize(size * ringBox, size * ringBox)
        icon.Halo:SetSize((size + HALO_GROWTH) * ringBox, (size + HALO_GROWTH) * ringBox)
        icon.Fill:SetShown(not unverified)
        icon.Halo:SetShown(unverified)
    end
    if unverified then
        icon.Ring:SetVertexColor(ur, ug, ub, INK_ALPHA)
        icon.Halo:SetVertexColor(pr, pg, pb, 1)
    else
        icon.Fill:SetVertexColor(vr, vg, vb, INK_ALPHA)
        icon.Ring:SetVertexColor(pr, pg, pb, 1)
    end
end
Minimap.StyleDot = styleDot





local function dotColors()
    local Look = FGPS.UI.Look
    local vr, vg, vb = Look.RouteColor("routeVerified")
    local ur, ug, ub = Look.RouteColor("routeUnverified")
    local pr, pg, pb = Look.Color("paleRing")
    return vr, vg, vb, ur, ug, ub, pr, pg, pb
end

local function ensureIcons()
    if Minimap.dotPool then return true end
    if not CreateObjectPool then return false end
    Minimap.dotPool = CreateObjectPool(makeDot, function(_, icon)
        icon:SetAlpha(1)
        icon:Hide()
    end)
    local Look = FGPS.UI.Look
    local vr, vg, vb = Look.RouteColor("routeVerified")
    local pr, pg, pb = Look.Color("paleRing")
    Minimap.nextPin = makeMark(NEXT_PIN_SIZE, DOT_TEXTURE, NEXT_MARK_SIZE, NEXT_LEVEL_SIZE)
    Minimap.destPin = makeMark(DEST_PIN_SIZE, FGPS.UI.WorldMap.MAP_X, DEST_MARK_SIZE, DEST_LEVEL_SIZE)
    tintMark(Minimap.nextPin, vr, vg, vb, pr, pg, pb)
    tintMark(Minimap.destPin, vr, vg, vb, pr, pg, pb)
    return true
end


local function applyColors()
    if not Minimap.dotPool then return end
    local vr, vg, vb, ur, ug, ub, pr, pg, pb = dotColors()
    for icon in Minimap.dotPool:EnumerateActive() do
        styleDot(icon, icon.unverified, vr, vg, vb, ur, ug, ub, pr, pg, pb)
    end
    tintMark(Minimap.nextPin, vr, vg, vb, pr, pg, pb)
    tintMark(Minimap.destPin, vr, vg, vb, pr, pg, pb)
end








local UNVERIFIED_KINDS = { [3] = true, [14] = true, [15] = true, [19] = true }

local function unverifiedKinds()
    local Route = FGPS.Route
    if Route and type(Route.DashedKinds) == "function" then return Route.DashedKinds() end
    if Route and type(Route.UNVERIFIED_KINDS) == "table" then return Route.UNVERIFIED_KINDS end
    return UNVERIFIED_KINDS
end





local function crossingHalf(leg, count, inst)
    if leg.toInst == nil or leg.inst == nil or leg.toInst == leg.inst then return nil end
    local split = leg.split
    if type(split) ~= "number" or split < 1 or split >= count then split = count - 1 end
    if inst == leg.inst then return 1, split end
    if inst == leg.toInst then return split + 1, count end
    return nil
end




local function pointAhead(points, lo, hi, x, y, skip)
    local best, bestD2 = lo, nil
    for i = lo, hi - 1 do
        if i ~= skip then
            local a, b = points[i], points[i + 1]
            local ax, ay = a.x or a[1], a.y or a[2]
            local dx, dy = (b.x or b[1]) - ax, (b.y or b[2]) - ay
            local len2 = dx * dx + dy * dy
            local t = 0
            if len2 > 0 then
                t = ((x - ax) * dx + (y - ay) * dy) / len2
                if t < 0 then t = 0 elseif t > 1 then t = 1 end
            end
            local ex, ey = ax + t * dx - x, ay + t * dy - y
            local d2 = ex * ex + ey * ey
            if not bestD2 or d2 < bestD2 then best, bestD2 = i + 1, d2 end
        end
    end
    return best
end












function Minimap.PointAhead(leg, pointIndex, alongYards, pos)
    local points = leg.points
    local n = #points
    local from = pointIndex or 1
    local walk = (leg.kind or "walk") == "walk"
    if not walk then
        local halfFrom, halfTo = crossingHalf(leg, n, pos.inst)
        if halfFrom then
            from = pointAhead(points, halfFrom, halfTo, pos.x, pos.y)
        else
            from = pointAhead(points, 1, n, pos.x, pos.y, leg.split)
        end
    end
    if from < 1 then from = 1 end
    if walk and type(alongYards) == "number" and FGPS.Route and FGPS.Route.Cumulative and n >= 2 then
        local cum = FGPS.Route.Cumulative(leg)
        local i = 1
        while i < n and (cum[i + 1] or 0) <= alongYards do i = i + 1 end
        if from > i + 1 then from = i + 1 end
    end
    return from
end


local TELEPORT_KINDS = { hearth = true, spell = true, portal = true }



local function onLegWithoutWay(route, progress)
    local legs = type(route) == "table" and route.legs
    local leg = type(legs) == "table" and type(progress) == "table" and legs[progress.legIndex or 1] or nil
    return type(leg) == "table" and (TELEPORT_KINDS[leg.kind] == true or leg.kind == "elevator")
end
































local function activeLevelZ(progress, pos)
    if pos and not pos.zInferred and type(pos.z) == "number" then return pos.z end
    if type(progress) == "table" then
        if type(progress.playerZ) == "number" then return progress.playerZ end
        if type(progress.levelZ) == "number" then return progress.levelZ end
        if type(progress.level) == "number" then return progress.level end
    end
    return nil
end

local function levelDirForDelta(targetZ, levelZ)
    if type(targetZ) ~= "number" or type(levelZ) ~= "number" then return false end
    local dz = targetZ - levelZ
    local limit = Minimap.OTHER_LEVEL_YARDS
    if dz > limit then return "up" end
    if dz < -limit then return "down" end
    return false
end

function Minimap.SampleDots(route, progress, pos, radius, maxDots, out)
    local dots = out or {}
    local count = 0
    if type(route) ~= "table" or type(route.legs) ~= "table" or not pos then return dots, count end
    local useHighRes = maxDots == nil and highResMode()
    maxDots = maxDots or (useHighRes and HIGHRES_MAX_DOTS or MAX_DOTS)
    local minSpacing = useHighRes and HIGHRES_MIN_SPACING or MIN_SPACING
    local spacing = max(minSpacing, (radius * 2) / maxDots)
    local walkLimit = radius * MAX_WALK_FACTOR
    local legStart = progress and progress.legIndex or 1
    local pointStart = progress and progress.pointIndex or 1
    local carry = 0
    local walked = 0
    local px, py = pos.x, pos.y
    local first = true
    local UNVERIFIED = unverifiedKinds()
    local inst = pos.inst
    local levelZ = activeLevelZ(progress, pos)
    local insideMaps = levelZ ~= nil and FGPS.Data and FGPS.Data.insideMaps or nil
    local levelLimit = Minimap.OTHER_LEVEL_YARDS

    for legIndex = legStart, #route.legs do
        local leg = route.legs[legIndex]
        local points = type(leg) == "table" and leg.points or nil
        local kind = leg and leg.kind or "walk"
        local teleportLeg = TELEPORT_KINDS[kind] == true
        if teleportLeg and first then return dots, count end



        if kind == "elevator" then return dots, count end
        local halfFrom, halfTo
        if points and #points >= 1 and kind ~= "walk" then halfFrom, halfTo = crossingHalf(leg, #points, pos.inst) end
        if points and #points == 2 and kind ~= "walk" and not teleportLeg and (leg.inst == nil or leg.inst == pos.inst) then


            first, carry = false, 0
            if leg.toInst ~= nil and leg.toInst ~= pos.inst then return dots, count end
        elseif points and #points >= 1 and (leg.inst == nil or leg.inst == pos.inst or halfFrom ~= nil) and not teleportLeg then
            local legUnverified = leg.unverified == true
            local from, to = halfFrom or 1, halfTo or #points
            if first then
                from = Minimap.PointAhead(leg, legIndex == legStart and pointStart or nil, progress and progress.alongYards, pos)
            end
            local insideLeg = type(insideMaps) == "table" and leg.inst ~= nil and insideMaps[leg.inst] ~= nil



            local cx, cy, cz, cStacked
            if first then
                cx, cy, cz, cStacked = px, py, levelZ, true
                if kind == "walk" and not leg.split and FGPS.Route and FGPS.Route.Cumulative
                    and #points >= 2 and points[1].x ~= nil then
                    local cum = FGPS.Route.Cumulative(leg)
                    local pf = points[from]
                    if pf and cum and type(cum[from]) == "number" then
                        local fdx, fdy = (pf.x or pf[1]) - px, (pf.y or pf[2]) - py
                        local firstSegLen = sqrt(fdx * fdx + fdy * fdy)
                        carry = (cum[from] - firstSegLen) % spacing
                        if carry >= spacing - 1e-9 then carry = 0 end
                    end
                end
            else
                local p0 = points[from]
                cx, cy, cz, cStacked = p0.x or p0[1], p0.y or p0[2], p0.z, p0.stacked
                from = from + 1
                if kind == "walk" and not leg.split then carry = 0 end
            end
            first = false
            for i = from, to do
                local p = points[i]
                local nx, ny = p.x or p[1], p.y or p[2]


                local teleport = not halfFrom and leg.split ~= nil and (i - 1) == leg.split
                if teleport then


                    if leg.toInst ~= nil and leg.toInst ~= pos.inst then return dots, count end
                    carry = 0
                else
                    local segUnverified = legUnverified
                    if p.k ~= nil then segUnverified = UNVERIFIED[p.k] == true end
                    local segOtherLevel = nil
                    if levelZ ~= nil and (insideLeg or (cStacked and p.stacked and (p.k == 22 or p.k == 23 or p.k == 16)))
                            and type(cz) == "number" and type(p.z) == "number" then
                        local d0, d1 = cz - levelZ, p.z - levelZ
                        if (d0 > levelLimit or d0 < -levelLimit) and (d1 > levelLimit or d1 < -levelLimit) then
                            segOtherLevel = true
                        end
                    end
                    local dx, dy = nx - cx, ny - cy
                    local segLen = sqrt(dx * dx + dy * dy)
                    if segLen > 0 then
                        local t = spacing - carry
                        while t <= segLen do
                            local sx, sy = cx + dx * (t / segLen), cy + dy * (t / segLen)
                            local ex, ey = sx - px, sy - py
                            if sqrt(ex * ex + ey * ey) <= radius then
                                count = count + 1
                                local entry = dots[count]
                                if type(entry) ~= "table" then
                                    entry = {}
                                    dots[count] = entry
                                end
                                entry.inst, entry.x, entry.y = inst, sx, sy
                                entry.unverified = segUnverified
                                entry.otherLevel = segOtherLevel
                                entry.k = p.k
                                if count >= maxDots then return dots, count end
                            end
                            t = t + spacing
                        end
                        carry = segLen - (t - spacing)
                        walked = walked + segLen
                        if walked > walkLimit then return dots, count end
                    end
                end
                cx, cy, cz, cStacked = nx, ny, p.z, p.stacked
            end

            if leg.toInst ~= nil and leg.toInst ~= pos.inst then return dots, count end
        elseif points and leg.inst ~= nil and leg.inst ~= pos.inst then

            if not first then return dots, count end
        end
    end
    return dots, count
end

local function destinationOf(route)
    local legs = route.legs
    local lastLeg = type(legs) == "table" and legs[#legs] or nil
    local lastPt = lastLeg and lastLeg.points and lastLeg.points[#lastLeg.points] or nil
    local stops = route.stops
    if type(stops) == "table" and #stops > 0 then
        local last = stops[#stops]
        local dest = last.dest or last
        if type(dest) == "table" and dest.x and dest.y and dest.inst then
            local dz = type(dest.z) == "number" and dest.z or nil
            if dz == nil and lastPt and lastLeg.inst == dest.inst and type(lastPt.z) == "number" then
                local px, py = lastPt.x or lastPt[1], lastPt.y or lastPt[2]
                if type(px) == "number" and type(py) == "number" then
                    local ex, ey = px - dest.x, py - dest.y
                    if ex * ex + ey * ey <= 6400 then dz = lastPt.z end
                end
            end
            return dest.inst, dest.x, dest.y, dz
        end
    end
    if lastPt and lastLeg.inst then
        return lastLeg.inst, lastPt.x or lastPt[1], lastPt.y or lastPt[2],
            type(lastPt.z) == "number" and lastPt.z or nil
    end
    return nil
end

local function stepVerticalDir(step)
    if step.kind == "level" or step.kind == "ramp" then
        if step.up ~= nil or type(step.dz) == "number" then
            local down = step.up == false or (step.up == nil and type(step.dz) == "number" and step.dz < 0)
            return down and "down" or "up"
        end
    elseif type(step.joined) == "table" and #step.joined > 0 then
        local j1 = step.joined[1]
        if type(j1) == "table" and (j1.kind == "level" or j1.kind == "ramp") and j1.up ~= nil then
            return j1.up == false and "down" or "up"
        end
    end
    return nil
end

local function legPointZ(route, legIndex, pointIndex)
    local legs = type(route) == "table" and route.legs or nil
    local leg = type(legs) == "table" and type(legIndex) == "number" and legs[legIndex] or nil
    local pts = type(leg) == "table" and leg.points or nil
    local pt = type(pts) == "table" and type(pointIndex) == "number" and pts[pointIndex] or nil
    return type(pt) == "table" and type(pt.z) == "number" and pt.z or nil
end

local function nextPointOf(route, progress, pos)
    if not progress then return nil end


    if onLegWithoutWay(route, progress) then return nil end
    local step = progress.currentStep
    if type(step) == "table" and step.x and step.y and (step.inst == nil or step.inst == pos.inst) then
        local nz = type(step.z) == "number" and step.z
            or legPointZ(route, step.legIndex or progress.legIndex, step.pointIndex)
        return pos.inst, step.x, step.y, nz, stepVerticalDir(step)
    end



    if progress.nextX and progress.nextY and (progress.nextInst == nil or progress.nextInst == pos.inst) then
        local nz = legPointZ(route, progress.legIndex, progress.pointIndex)
        return pos.inst, progress.nextX, progress.nextY, nz, nil
    end
    return nil
end




function Minimap:Clear()
    if self.pendingTimer then
        self.pendingTimer:Cancel()
        self.pendingTimer = nil
    end
    if self.pins and self.active then
        self.pins:RemoveAllMinimapIcons(REF)
    end
    if self.dotPool then self.dotPool:ReleaseAll() end
    if self.nextPin then
        setLevelMark(self.nextPin, false)
        self.nextPin:Hide()
    end
    if self.destPin then
        setLevelMark(self.destPin, false)
        self.destPin:Hide()
    end
    self.placedDots, self.placedNext, self.placedDest, self.placedWith = nil, nil, nil, nil
    self.active = false
    self.lastDotCount = 0
    self.drawn = nil
end

local function playerPos(progress)
    if progress and progress.pos and progress.pos.x then return progress.pos end
    local Coords = FGPS.Coords
    if Coords and Coords.PlayerPos then
        local ok, pos = pcall(Coords.PlayerPos)
        if ok and type(pos) == "table" then return pos end
    end
    return nil
end


local function trimDots(pins, pool, placedDots, keep)
    for i = #placedDots, keep + 1, -1 do
        local icon = placedDots[i]
        placedDots[i] = nil
        pins:RemoveMinimapIcon(REF, icon)
        pool:Release(icon)
    end
end

function Minimap:Refresh()



    if self.pendingTimer then
        self.pendingTimer:Cancel()
        self.pendingTimer = nil
    end
    self.lastRefresh = now()
    if not self:IsAllowed() then
        self:Clear()
        return
    end
    if not ensureIcons() then return end
    local Perf = FGPS.Perf
    if Perf then Perf:Begin("minimap") end
    local pins = self.pins




    local placedDots = self.placedDots
    local pool = self.dotPool
    if not (self.active and placedDots and self.placedWith == pins and pins.RemoveMinimapIcon
            and pool.GetNumActive and pool:GetNumActive() == #placedDots) then
        if self.active then pins:RemoveAllMinimapIcons(REF) end
        pool:ReleaseAll()
        placedDots = {}
        self.placedNext, self.placedDest = nil, nil
    end
    self.placedDots, self.placedWith = placedDots, pins
    local route = self.route
    local progress = self.progress
    local pos = playerPos(progress)
    local placed = 0
    local radius = viewRadius() * RADIUS_FACTOR

    local drawn = self.drawn or {}
    self.drawn = drawn
    drawn.route, drawn.radius = route, radius
    drawn.leg, drawn.point, drawn.step = nil, nil, nil
    if type(progress) == "table" then
        drawn.leg, drawn.point, drawn.step = progress.legIndex, progress.pointIndex, progress.currentStep
    end
    local levelZ = activeLevelZ(progress, pos)
    drawn.levelBucket = levelZ ~= nil and floor(levelZ / 4 + 0.5) or nil
    drawn.inst, drawn.x, drawn.y = nil, nil, nil
    if pos then drawn.inst, drawn.x, drawn.y = pos.inst, pos.x, pos.y end
    if pos and pos.inst then


        self.dotBuffer = self.dotBuffer or {}
        local dots, dotCount = Minimap.SampleDots(route, self.progress, pos, radius, nil, self.dotBuffer)
        local vr, vg, vb, ur, ug, ub, pr, pg, pb = dotColors()
        local otherAlpha = Minimap.OTHER_LEVEL_ALPHA
        for i = 1, dotCount do
            local dot = dots[i]
            local icon = placedDots[i]
            if not icon then
                icon = pool:Acquire()
                placedDots[i] = icon
            end
            styleDot(icon, dot.unverified, vr, vg, vb, ur, ug, ub, pr, pg, pb)
            icon:SetAlpha(dot.otherLevel and otherAlpha or 1)
            pins:AddMinimapIconWorld(REF, icon, dot.inst, dot.x, dot.y, false)
            placed = placed + 1
        end
        trimDots(pins, pool, placedDots, dotCount)
        local ninst, nx, ny, nz, nstepDir = nextPointOf(route, self.progress, pos)
        if ninst then
            setLevelMark(self.nextPin, nstepDir or levelDirForDelta(nz, levelZ))
            pins:AddMinimapIconWorld(REF, self.nextPin, ninst, nx, ny, false)
            raiseOverDots(self.nextPin, 2)
            self.placedNext = true
            placed = placed + 1
        else
            setLevelMark(self.nextPin, false)
            if self.placedNext then pins:RemoveMinimapIcon(REF, self.nextPin) end
            self.placedNext = nil
            self.nextPin:Hide()
        end
    else
        trimDots(pins, pool, placedDots, 0)
        setLevelMark(self.nextPin, false)
        if self.placedNext then pins:RemoveMinimapIcon(REF, self.nextPin) end
        self.placedNext = nil
        self.nextPin:Hide()
    end
    local dinst, dx, dy, dz = destinationOf(route)
    local was = self.placedDest
    if dinst then
        local destDir = (pos and pos.inst == dinst) and levelDirForDelta(dz, levelZ) or false
        setLevelMark(self.destPin, destDir)

        if not (was and was.inst == dinst and was.x == dx and was.y == dy) then
            pins:AddMinimapIconWorld(REF, self.destPin, dinst, dx, dy, true)
            self.placedDest = { inst = dinst, x = dx, y = dy }
        end
        raiseOverDots(self.destPin, 3)
        placed = placed + 1
    else
        setLevelMark(self.destPin, false)
        if was then pins:RemoveMinimapIcon(REF, self.destPin) end
        self.placedDest = nil
        self.destPin:Hide()
    end
    self.active = placed > 0
    self.lastDotCount = placed
    if Perf then Perf:End("minimap") end
end


function Minimap:RequestRefresh()
    local throttle = highResMode() and HIGHRES_THROTTLE_SECONDS or THROTTLE_SECONDS
    local elapsed = now() - self.lastRefresh
    if elapsed >= throttle then
        self:Refresh()
        return
    end
    if self.pendingTimer then return end
    if C_Timer and C_Timer.NewTimer then
        self.pendingTimer = C_Timer.NewTimer(throttle - elapsed, function() Minimap:Refresh() end)
    end
end




local function onRoute(event, route)
    if event == "NAV_CANCELLED" then
        Minimap.route = nil
        Minimap.progress = nil
        Minimap:Clear()
        return
    end
    if event == "ROUTE_PREVIEW" and route == nil then

        Minimap.route = nil
        Minimap.progress = nil
        Minimap:Clear()
        return
    end
    if event ~= "ROUTE_PREVIEW" or route ~= Minimap.route then


        Minimap.progress = nil
    end
    Minimap.route = route or Minimap.route
    Minimap:Refresh()
end







local positionOnly = {}
local function progressFor(route, progress)
    local Navigator = FGPS.Navigator
    if type(progress) ~= "table" or not (Navigator and Navigator.GetRoute) then return progress end
    local ok, held = pcall(Navigator.GetRoute, Navigator)
    if not ok or held == nil or held == route then return progress end
    positionOnly.pos = progress.pos
    return positionOnly
end





local function needsRefresh(progress)
    local drawn = Minimap.drawn
    if not drawn or drawn.route ~= Minimap.route or type(progress) ~= "table" then return true end
    if drawn.leg ~= progress.legIndex or drawn.point ~= progress.pointIndex or drawn.step ~= progress.currentStep then return true end
    if drawn.radius ~= viewRadius() * RADIUS_FACTOR then return true end
    local pos = playerPos(progress)
    local levelZ = activeLevelZ(progress, pos)
    if drawn.levelBucket ~= (levelZ ~= nil and floor(levelZ / 4 + 0.5) or nil) then return true end
    if not pos or not pos.x or not pos.y then return drawn.x ~= nil end
    if drawn.inst ~= pos.inst or not drawn.x then return true end
    local dx, dy = pos.x - drawn.x, pos.y - drawn.y
    local eps = highResMode() and HIGHRES_MOVE_EPSILON_YARDS or MOVE_EPSILON_YARDS
    return dx * dx + dy * dy >= eps * eps
end





local function firstOfLeg(progress)
    local drawn = Minimap.drawn
    return drawn ~= nil and drawn.route == Minimap.route and type(progress) == "table"
        and progress.legIndex ~= nil and drawn.leg ~= progress.legIndex
end

local function onProgress(_, progress)
    if not Minimap.route then
        local Navigator = FGPS.Navigator
        if Navigator and Navigator.GetRoute then
            local ok, route = pcall(Navigator.GetRoute, Navigator)
            if ok then Minimap.route = route end
        end
    end
    progress = progressFor(Minimap.route, progress)
    Minimap.progress = progress
    if not Minimap:IsAllowed() then

        if Minimap.active then Minimap:Clear() end
        return
    end
    if firstOfLeg(progress) then
        Minimap:Refresh()
    elseif needsRefresh(progress) then
        Minimap:RequestRefresh()
    end
end

local function onArrived(_, stopIndex, isFinal)
    if isFinal ~= false then
        Minimap.route = nil
        Minimap.progress = nil
        Minimap:Clear()
    end
end



local function onNavState(_, state)
    if state ~= "idle" or not Minimap.route then return end
    local Navigator = FGPS.Navigator
    if Navigator and Navigator.GetRoute then
        local ok, route = pcall(Navigator.GetRoute, Navigator)
        if ok and route ~= nil then return end
    end
    Minimap.route = nil
    Minimap.progress = nil
    Minimap:Clear()
end







local function onRecalcDone(_, route, err)
    if route ~= nil or Minimap.route == nil then return end
    if type(err) == "table" and err.code == "CANCELLED" then return end
    local Navigator = FGPS.Navigator
    if not (Navigator and Navigator.GetRoute) then return end
    local ok, held = pcall(Navigator.GetRoute, Navigator)
    if not ok or held == Minimap.route then return end
    local progress
    if held and Navigator.GetProgress then
        local okProgress, p = pcall(Navigator.GetProgress, Navigator)
        if okProgress and type(p) == "table" then progress = p end
    end
    Minimap.route, Minimap.progress = held, progress
    if held then Minimap:Refresh() else Minimap:Clear() end
end

local function onCombat(_, inCombat)
    Minimap.inCombat = inCombat and true or false
    if Minimap.route then Minimap:Refresh() end
end

local function onSettingsChanged(_, key)
    if key == "*" then applyColors() end
    if key == "minimapLine" or key == "combatMode" or key == "*" or key == "perf.guidanceEnabled"
        or key == "routing.highRes" then
        if Minimap.route then Minimap:Refresh() end
    elseif key == "accessibility.colorScheme" then
        applyColors()
    end
end

function Minimap:Init()
    if LibStub and not self.pins then
        self.pins = LibStub("HereBeDragons-Pins-2.0", true)
        if not self.pins then FGPS.Log:Warn("HereBeDragons-Pins-2.0 not found; minimap route hints disabled") end
    end
    if InCombatLockdown then self.inCombat = InCombatLockdown() and true or false end
    if not self.eventsBound then
        self.eventsBound = true
        local Events = FGPS.Events
        Events:Register("ROUTE_PREVIEW", onRoute, self)
        Events:Register("ROUTE_STARTED", onRoute, self)
        Events:Register("ROUTE_UPDATED", onRoute, self)
        Events:Register("NAV_CANCELLED", onRoute, self)
        Events:Register("ROUTE_PROGRESS", onProgress, self)
        Events:Register("NAV_ARRIVED", onArrived, self)
        Events:Register("NAV_STATE", onNavState, self)
        Events:Register("NAV_RECALC_DONE", onRecalcDone, self)
        Events:Register("COMBAT_STATE", onCombat, self)



        Events:Register("WORLD_ENTERED", function()
            if not InCombatLockdown then return end
            local fighting = InCombatLockdown() and true or false
            if fighting ~= Minimap.inCombat then onCombat(nil, fighting) end
        end, self)
        Events:Register("SETTINGS_CHANGED", onSettingsChanged, self)
        Events:Register("UI_PRESET_APPLIED", function() applyColors() end, self)
    end
end
