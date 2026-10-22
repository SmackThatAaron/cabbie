








local ADDON_NAME, FGPS = ...

local L = FGPS.L
local sqrt, floor, max, min = math.sqrt, math.floor, math.max, math.min
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
}
FGPS.UI.Minimap = Minimap

local MAX_DOTS = 40
local THROTTLE_SECONDS = 0.5
local RADIUS_FACTOR = 1.2
local DEFAULT_VIEW_RADIUS = 233.3
local MIN_SPACING = 8
local MAX_WALK_FACTOR = 4
local MOVE_EPSILON_YARDS = 1
local REF = "Cabbie"

local function settings()
    return FGPS.DB and FGPS.DB.settings or nil
end

local function now()
    return GetTime and GetTime() or 0
end

local function skinColor(name, dr, dg, db, da)
    local Skins = FGPS.UI.Skins
    if Skins and Skins.Current then
        local ok, skin = pcall(Skins.Current)
        local c = ok and type(skin) == "table" and type(skin.colors) == "table" and skin.colors[name] or nil
        if type(c) == "table" then
            local r, g, b, a = c[1] or c.r, c[2] or c.g, c[3] or c.b, c[4] or c.a
            if r and g and b then return r, g, b, a or 1 end
        end
    end
    return dr, dg, db, da
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




local function makeIcon(size, r, g, b, a, withBorder)
    local parent = _G and _G.Minimap or UIParent
    local icon = CreateFrame("Frame", nil, parent)
    icon:SetSize(size, size)
    icon:EnableMouse(false)
    icon.border = icon:CreateTexture(nil, "BACKGROUND")
    icon.border:SetAllPoints(icon)
    icon.border:SetTexture("Interface\\Buttons\\WHITE8X8")
    icon.border:SetVertexColor(0, 0, 0, withBorder and 0.8 or 0)
    icon.fill = icon:CreateTexture(nil, "ARTWORK")
    icon.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    icon.fill:SetVertexColor(r, g, b, a)
    icon.fgpsInset = nil
    if withBorder then
        icon.fill:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, -1)
        icon.fill:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
        icon.fgpsInset = 1
    else
        icon.fill:SetAllPoints(icon)
    end
    icon:Hide()
    return icon
end




local DOT_SIZE, DOT_INSET = 5, 1
local DOT_SIZE_UNVERIFIED, DOT_INSET_UNVERIFIED = 8, 2

local function setDotInset(icon, inset)
    if icon.fgpsInset == inset then return end
    icon.fgpsInset = inset
    icon.fill:ClearAllPoints()
    icon.fill:SetPoint("TOPLEFT", icon, "TOPLEFT", inset, -inset)
    icon.fill:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -inset, inset)
end



local function styleDot(icon, unverified, vr, vg, vb, ur, ug, ub)
    icon.unverified = unverified and true or false
    if unverified then
        icon:SetSize(DOT_SIZE_UNVERIFIED, DOT_SIZE_UNVERIFIED)
        setDotInset(icon, DOT_INSET_UNVERIFIED)
        icon.border:SetVertexColor(ur, ug, ub, 0.95)
        icon.fill:SetVertexColor(0, 0, 0, 0.55)
    else
        icon:SetSize(DOT_SIZE, DOT_SIZE)
        setDotInset(icon, DOT_INSET)
        icon.border:SetVertexColor(0, 0, 0, 0.8)
        icon.fill:SetVertexColor(vr, vg, vb, 0.9)
    end
end
Minimap.StyleDot = styleDot

local function ensureIcons()
    if Minimap.dotPool then return true end
    if not CreateObjectPool then return false end
    Minimap.dotPool = CreateObjectPool(function()
        local r, g, b = skinColor("routeVerified", 0.25, 0.80, 1.00)
        return makeIcon(DOT_SIZE, r, g, b, 0.9, true)
    end, function(_, icon)
        icon:Hide()
    end)
    local ar, ag, ab = skinColor("accent", 0.31, 0.76, 0.97)
    Minimap.nextPin = makeIcon(9, 1, 1, 1, 0.95, true)
    Minimap.destPin = makeIcon(12, ar, ag, ab, 1, true)
    return true
end


local function applyColors()
    if not Minimap.dotPool then return end
    local vr, vg, vb = skinColor("routeVerified", 0.25, 0.80, 1.00)
    local ur, ug, ub = skinColor("routeUnverified", 1.00, 0.55, 0.10)
    for icon in Minimap.dotPool:EnumerateActive() do
        styleDot(icon, icon.unverified, vr, vg, vb, ur, ug, ub)
    end
    local ar, ag, ab = skinColor("accent", 0.31, 0.76, 0.97)
    if Minimap.destPin then Minimap.destPin.fill:SetVertexColor(ar, ag, ab, 1) end
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


local TELEPORT_KINDS = { hearth = true, spell = true, portal = true }



local function onLegWithoutWay(route, progress)
    local legs = type(route) == "table" and route.legs
    local leg = type(legs) == "table" and type(progress) == "table" and legs[progress.legIndex or 1] or nil
    return type(leg) == "table" and (TELEPORT_KINDS[leg.kind] == true or leg.kind == "elevator")
end
































function Minimap.SampleDots(route, progress, pos, radius, maxDots, out)
    local dots = out or {}
    local count = 0
    if type(route) ~= "table" or type(route.legs) ~= "table" or not pos then return dots, count end
    maxDots = maxDots or MAX_DOTS
    local spacing = max(MIN_SPACING, (radius * 2) / maxDots)
    local walkLimit = radius * MAX_WALK_FACTOR
    local legStart = progress and progress.legIndex or 1
    local pointStart = progress and progress.pointIndex or 1
    local carry = 0
    local walked = 0
    local px, py = pos.x, pos.y
    local first = true
    local UNVERIFIED = unverifiedKinds()
    local inst = pos.inst

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
            local from = (legIndex == legStart) and pointStart or 1
            local to = #points
            if halfFrom then
                to = halfTo
                from = first and pointAhead(points, halfFrom, halfTo, px, py) or halfFrom
            elseif kind ~= "walk" and first then
                from = pointAhead(points, 1, to, px, py, leg.split)
            end
            if from < 1 then from = 1 end


            local alongNow = first and progress and progress.alongYards
            if type(alongNow) == "number" and FGPS.Route and FGPS.Route.Cumulative and #points >= 2 then
                local cum = FGPS.Route.Cumulative(leg)
                local i = 1
                while i < #points and (cum[i + 1] or 0) <= alongNow do i = i + 1 end
                if from > i + 1 then from = i + 1 end
            end

            local cx, cy
            if first then cx, cy = px, py else
                local p0 = points[from]
                cx, cy = p0.x or p0[1], p0.y or p0[2]
                from = from + 1
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
                cx, cy = nx, ny
            end

            if leg.toInst ~= nil and leg.toInst ~= pos.inst then return dots, count end
        elseif points and leg.inst ~= nil and leg.inst ~= pos.inst then

            if not first then return dots, count end
        end
    end
    return dots, count
end

local function destinationOf(route)
    local stops = route.stops
    if type(stops) == "table" and #stops > 0 then
        local last = stops[#stops]
        local dest = last.dest or last
        if type(dest) == "table" and dest.x and dest.y and dest.inst then return dest.inst, dest.x, dest.y end
    end
    local legs = route.legs
    local leg = type(legs) == "table" and legs[#legs] or nil
    local p = leg and leg.points and leg.points[#leg.points]
    if p and leg.inst then return leg.inst, p.x or p[1], p.y or p[2] end
    return nil
end

local function nextPointOf(route, progress, pos)
    if not progress then return nil end


    if onLegWithoutWay(route, progress) then return nil end
    local step = progress.currentStep
    if type(step) == "table" and step.x and step.y and (step.inst == nil or step.inst == pos.inst) then
        return pos.inst, step.x, step.y
    end



    if progress.nextX and progress.nextY and (progress.nextInst == nil or progress.nextInst == pos.inst) then
        return pos.inst, progress.nextX, progress.nextY
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
    if self.nextPin then self.nextPin:Hide() end
    if self.destPin then self.destPin:Hide() end
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
    if self.active then pins:RemoveAllMinimapIcons(REF) end
    self.dotPool:ReleaseAll()
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
    drawn.inst, drawn.x, drawn.y = nil, nil, nil
    if pos then drawn.inst, drawn.x, drawn.y = pos.inst, pos.x, pos.y end
    if pos and pos.inst then


        self.dotBuffer = self.dotBuffer or {}
        local dots, dotCount = Minimap.SampleDots(route, self.progress, pos, radius, MAX_DOTS, self.dotBuffer)
        local vr, vg, vb = skinColor("routeVerified", 0.25, 0.80, 1.00)
        local ur, ug, ub = skinColor("routeUnverified", 1.00, 0.55, 0.10)
        for i = 1, dotCount do
            local dot = dots[i]
            local icon = self.dotPool:Acquire()
            styleDot(icon, dot.unverified, vr, vg, vb, ur, ug, ub)
            pins:AddMinimapIconWorld(REF, icon, dot.inst, dot.x, dot.y, false)
            placed = placed + 1
        end
        local ninst, nx, ny = nextPointOf(route, self.progress, pos)
        if ninst then
            pins:AddMinimapIconWorld(REF, self.nextPin, ninst, nx, ny, false)
            placed = placed + 1
        else
            self.nextPin:Hide()
        end
    end
    local dinst, dx, dy = destinationOf(route)
    if dinst then
        pins:AddMinimapIconWorld(REF, self.destPin, dinst, dx, dy, true)
        placed = placed + 1
    else
        self.destPin:Hide()
    end
    self.active = placed > 0
    self.lastDotCount = placed
    if Perf then Perf:End("minimap") end
end


function Minimap:RequestRefresh()
    local elapsed = now() - self.lastRefresh
    if elapsed >= THROTTLE_SECONDS then
        self:Refresh()
        return
    end
    if self.pendingTimer then return end
    if C_Timer and C_Timer.NewTimer then
        self.pendingTimer = C_Timer.NewTimer(THROTTLE_SECONDS - elapsed, function() Minimap:Refresh() end)
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
    Minimap.route = route or Minimap.route
    if event ~= "ROUTE_PREVIEW" then

        Minimap.progress = nil
    end
    Minimap:Refresh()
end





local function needsRefresh(progress)
    local drawn = Minimap.drawn
    if not drawn or drawn.route ~= Minimap.route or type(progress) ~= "table" then return true end
    if drawn.leg ~= progress.legIndex or drawn.point ~= progress.pointIndex or drawn.step ~= progress.currentStep then return true end
    if drawn.radius ~= viewRadius() * RADIUS_FACTOR then return true end
    local pos = playerPos(progress)
    if not pos or not pos.x or not pos.y then return drawn.x ~= nil end
    if drawn.inst ~= pos.inst or not drawn.x then return true end
    local dx, dy = pos.x - drawn.x, pos.y - drawn.y
    return dx * dx + dy * dy >= MOVE_EPSILON_YARDS * MOVE_EPSILON_YARDS
end

local function onProgress(_, progress)
    Minimap.progress = progress
    if not Minimap.route then
        local Navigator = FGPS.Navigator
        if Navigator and Navigator.GetRoute then
            local ok, route = pcall(Navigator.GetRoute, Navigator)
            if ok then Minimap.route = route end
        end
    end
    if not Minimap:IsAllowed() then

        if Minimap.active then Minimap:Clear() end
        return
    end
    if needsRefresh(progress) then Minimap:RequestRefresh() end
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

local function onCombat(_, inCombat)
    Minimap.inCombat = inCombat and true or false
    if Minimap.route then Minimap:Refresh() end
end

local function onSettingsChanged(_, key)
    if key == "minimapLine" or key == "combatMode" or key == "*" or key == "perf.guidanceEnabled" then
        if Minimap.route then Minimap:Refresh() end
    elseif key == "preset" or key == "accessibility.colorScheme" then
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
        Events:Register("COMBAT_STATE", onCombat, self)
        Events:Register("SETTINGS_CHANGED", onSettingsChanged, self)
        Events:Register("UI_PRESET_APPLIED", function() applyColors() end, self)
    end
end
