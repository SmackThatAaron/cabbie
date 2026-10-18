































local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Events = FGPS.Events
local Const = FGPS.Const
local sqrt, type, pairs, ipairs, tostring, pcall, tonumber = math.sqrt, type, pairs, ipairs, tostring, pcall, tonumber


local function plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local Transport = {
    DOCK_RADIUS = 40,
    LEAVE_RADIUS = 60,



    ARRIVE_RADIUS = Const.TRANSPORT_ARRIVE_YARDS or 60,
    FORGET_RADIUS = 200,
    SPEED_FACTOR = 1.3,
    MAX_RIDE_FACTOR = 2.5,
    WRONG_RIDE_YARDS = 500,
    SLOW_SECONDS = 5,


    BOARDING_SECONDS = 10,


    STILL_SECONDS = 1,
    UNKNOWN_RIDE_SECONDS = 600,
    UNSEEN_RIDE_SECONDS = 2,

    NOTICE_HOLD = 8,



    FLIGHT_MAP_HOLD = 120,


    state = { onTaxi = false, onTransport = false, transportID = nil, destinationTaxiNode = nil, since = nil, stopIndex = nil,
              unknown = false },
    phases = {},
    dock = nil,
    lastPos = nil,
    rideStart = nil,
}
FGPS.Transport = Transport

local TRANSPORT_KINDS = { boat = true, zeppelin = true, tram = true, elevator = true, ferry = true }

local function now() return GetTime and GetTime() or 0 end

local function dist(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return sqrt(dx * dx + dy * dy)
end

local function fireState()
    Events:Fire("TRANSPORT_STATE", Transport.state)
end





local function guide(method, ...)
    local Guide = FGPS.UI and FGPS.UI.Guide
    if not (Guide and Guide[method]) then return nil end
    local ok, answer = pcall(Guide[method], ...)
    if ok then return answer end
    if FGPS.Log and FGPS.Log.Error then FGPS.Log:Error("Transport: the guide's %s failed: %s", method, tostring(answer)) end
    return nil
end




local function notice(hold, fmt, ...)
    local text = FGPS.Util.SafeFormat(fmt, ...)
    guide("Say", text, hold)
    return text
end



local function flightNotice(fmt, ...)
    Transport.flightLine = notice(Transport.FLIGHT_MAP_HOLD, fmt, ...)
end

function Transport.State()
    return Transport.state
end




local function activeRoute()
    local Nav = FGPS.Navigator
    if not Nav or not Nav.GetRoute then return nil end
    local state = Nav:GetState()
    if state ~= "active" and state ~= "paused" and state ~= "in_transit" then return nil end
    return Nav:GetRoute(), Nav:GetProgress()
end


local function nextLegOfKind(kinds)
    local route, progress = activeRoute()
    if not route or not route.legs then return nil end
    local from = progress and progress.legIndex or 1
    for i = from, #route.legs do
        local leg = route.legs[i]
        if kinds[leg.kind] then return leg, i end
    end
    return nil
end

function Transport.NextTaxiLeg()
    return nextLegOfKind({ taxi = true })
end

function Transport.NextTransportLeg()
    return nextLegOfKind(TRANSPORT_KINDS)
end

local function transportRecord(transportID)
    local records = FGPS.Data and FGPS.Data.transports
    return records and transportID and records[transportID] or nil
end







local function legStopIndex(leg, field)
    local explicit = leg[field .. "Index"]
    if type(explicit) == "number" then return explicit end
    local value = leg[field]
    if type(value) == "number" then return value end
    local rec = transportRecord(leg.transportID)
    if type(value) ~= "string" or not (rec and type(rec.stops) == "table") then return nil end
    local pts = leg.points or {}
    local anchor = field == "stopFrom" and pts[1] or pts[#pts]
    local best, bestD
    for i, stop in ipairs(rec.stops) do
        if type(stop) == "table" and stop.name == value then
            local d = math.huge
            if stop.x and stop.y then
                d = (anchor and anchor.x and anchor.y) and dist(anchor.x, anchor.y, stop.x, stop.y) or 0
            end
            if not bestD or d < bestD then best, bestD = i, d end
        end
    end
    return best
end
Transport.LegStopIndex = legStopIndex

local function legDocks(leg)
    local rec = transportRecord(leg.transportID)
    local from, to
    if rec and type(rec.stops) == "table" then
        local fromIndex, toIndex = legStopIndex(leg, "stopFrom"), legStopIndex(leg, "stopTo")
        from, to = fromIndex and rec.stops[fromIndex] or nil, toIndex and rec.stops[toIndex] or nil
    end
    local pts = leg.points or {}
    from = from or pts[1]
    to = to or pts[#pts]
    return from, to
end




local function taxiNodeName(taxiNodeID)
    local taxi = FGPS.Data and FGPS.Data.taxi
    local node = taxi and taxi.nodes and taxi.nodes[taxiNodeID]
    return node and node.name or nil
end

local function baseName(name)
    return (tostring(name or ""):gsub(",.*$", ""))
end




function Transport.FindTaxiSlot(name)
    if not name or not (NumTaxiNodes and TaxiNodeName) then return nil end
    local ok, n = pcall(NumTaxiNodes)
    n = ok and plain(n) or nil
    if type(n) ~= "number" or n <= 0 then return nil end
    local wanted = baseName(name)
    local partial
    local function slotType(i)
        if not TaxiNodeGetType then return nil end
        local okType, t = pcall(TaxiNodeGetType, i)
        t = okType and plain(t) or nil
        return type(t) == "string" and t or nil
    end
    for i = 1, n do
        local okName, slotName = pcall(TaxiNodeName, i)
        slotName = okName and plain(slotName) or nil
        if type(slotName) == "string" then
            if slotName == name then return i, slotName, slotType(i) end
            if not partial and baseName(slotName) == wanted then partial = i end
        end
    end
    if partial then
        local _, slotName = pcall(TaxiNodeName, partial)
        return partial, plain(slotName), slotType(partial)
    end
    return nil
end




function Transport.FindFlightMapNode(name, taxiNodeID)
    if not (C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and GetTaxiMapID) then return nil end
    local okMap, mapID = pcall(GetTaxiMapID)
    mapID = okMap and plain(mapID) or nil
    if type(mapID) ~= "number" then return nil end
    local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, mapID)
    if not ok or type(nodes) ~= "table" or #nodes == 0 then return nil end
    local wanted = name and baseName(name) or nil
    local byID, exact, partial
    for _, node in ipairs(nodes) do
        if type(node) == "table" then
            local id, nodeName = plain(node.nodeID), plain(node.name)
            local info = { nodeID = id, name = nodeName, state = plain(node.state), slotIndex = plain(node.slotIndex) }
            if taxiNodeID and id == taxiNodeID and not byID then byID = info end
            if type(nodeName) == "string" and name then
                if nodeName == name and not exact then exact = info end
                if not partial and wanted and baseName(nodeName) == wanted then partial = info end
            end
        end
    end
    return byID or exact or partial
end

local function flightState(state)
    local E = Enum and Enum.FlightPathState
    local current = E and E.Current or 0
    local reachable = E and E.Reachable or 1
    local unreachable = E and E.Unreachable or 2
    if state == current then return "current" end
    if state == reachable then return "reachable" end
    if state == unreachable then return "unreachable" end
    return nil
end





function Transport.OnTaxiMapOpened(system)
    local leg = Transport.NextTaxiLeg()
    if not leg then return nil end
    local name = (leg.taxiTo and taxiNodeName(leg.taxiTo)) or leg.label
    if not name then return nil end
    Transport.state.destinationTaxiNode = leg.taxiTo
    local taxiSystem = Enum and Enum.UIMapSystem and Enum.UIMapSystem.Taxi or 1
    local classicFirst = (system == nil) or (system == taxiSystem)
    local result
    local function tryClassic()
        local slot, slotName, slotType = Transport.FindTaxiSlot(name)
        if slot then
            result = { ui = "taxi", name = slotName or name, slot = slot, state = slotType and slotType:lower() or nil }
            if slotType == "DISTANT" or slotType == "UNREACHABLE" then result.unavailable = true end
            return true
        end
        return false
    end
    local function tryFlightMap()
        local info = Transport.FindFlightMapNode(name, leg.taxiTo)
        if info then
            local state = flightState(info.state)
            result = { ui = "flightmap", name = info.name or name, nodeID = info.nodeID, slot = info.slotIndex, state = state }
            if state == "unreachable" then result.unavailable = true end
            return true
        end
        return false
    end
    local found
    if classicFirst then found = tryClassic() or tryFlightMap() else found = tryFlightMap() or tryClassic() end
    if not found then
        flightNotice(L["Your route continues by flight to %s, which this flight master does not offer."], name)
        return nil
    end
    if result.state == "current" then
        flightNotice(L["You are already at %s; continue your route on foot."], result.name)
    elseif result.unavailable then
        flightNotice(L["Your route continues by flight to %s, but this flight master cannot take you there (undiscovered or not connected)."], result.name)
    else
        flightNotice(L["Select %s to continue your route."], result.name)
    end
    return result
end




function Transport.OnTaxiMapClosed()
    local text = Transport.flightLine
    Transport.flightLine = nil
    return text ~= nil and guide("Unsay", text) == true
end






local function bestGroundSpeed()
    local run = Const.RUN_SPEED or 7
    local Coords = FGPS.Coords
    if Coords and Coords.PlayerSpeed then
        local _, runSpeed = Coords.PlayerSpeed()
        if type(runSpeed) == "number" and runSpeed > 0 then run = runSpeed end
    end
    if IsMounted then
        local ok, mounted = pcall(IsMounted)
        if ok and plain(mounted) == true then
            local mount = Const.MOUNT_100 or 14
            if mount > run then run = mount end
        end
    end
    return run
end


local function recordPhase(transportID, stopIndex, departureTime)
    if not transportID or not stopIndex then return end
    local t = Transport.phases[transportID]
    if not t then t = {} Transport.phases[transportID] = t end
    t[stopIndex] = departureTime
end





local function storeDeparture(phase)
    local Calibrate = FGPS.Calibrate
    if phase and Calibrate and Calibrate.NoteDeparture then
        pcall(Calibrate.NoteDeparture, phase.transportID, phase.stopIndex, phase.at)
    end
end



local function forgetDeparture()
    local phase = Transport.ridePhase
    if phase and Transport.phases[phase.transportID] then
        Transport.phases[phase.transportID][phase.stopIndex] = phase.previous
    end
    Transport.ridePhase = nil
end



local function rememberPosition(pos, t)
    local last = Transport.lastPos
    if not last then
        last = {}
        Transport.lastPos = last
    end
    last.x, last.y, last.inst, last.time = pos.x, pos.y, pos.inst, t
end




local function endRide(t, arrived)
    if arrived then storeDeparture(Transport.ridePhase) else forgetDeparture() end
    local state = Transport.state
    state.onTransport, state.unknown, state.transportID, state.stopIndex = false, false, nil, nil
    state.since = t
    Transport.rideStart, Transport.slowSince, Transport.ridePhase, Transport.rideGround = nil, nil, nil, nil
    Transport.suspectSince = nil
    fireState()
end










local function slowedDown(speed, t)
    if speed == nil then return false end
    local ground = bestGroundSpeed()
    if speed > Transport.SPEED_FACTOR * ground then Transport.rideGround = ground end
    if (not Transport.slowSince or t - Transport.slowSince < Transport.STILL_SECONDS)
        and Transport.rideGround and Transport.rideGround < ground
        and t - (Transport.rideStart or t) < Transport.BOARDING_SECONDS then
        ground = Transport.rideGround
    end
    if speed > Transport.SPEED_FACTOR * ground then
        Transport.slowSince = nil
        return false
    end
    Transport.slowSince = Transport.slowSince or t
    return t - Transport.slowSince >= Transport.SLOW_SECONDS
end















function Transport.DepartureCount(leg)
    local n = (type(leg) == "table" and type(leg.points) == "table") and #leg.points or 0
    if leg == nil or leg.toInst == nil or leg.toInst == leg.inst then return n end
    local split = leg.split
    if type(split) == "number" and split >= 1 and split < n then return split end
    return n - 1
end

local function offThePath(leg, pos, judgeStops)
    local pts = leg.points
    local n = pts and #pts or 0
    local legInst, toInst = leg.inst, leg.toInst or leg.inst
    if legInst == nil then return judgeStops == true end
    if pos.inst ~= legInst and pos.inst ~= toInst then return true end
    if n <= 2 and not judgeStops then return false end
    if n < 1 then return true end
    local from, to = 1, n
    if toInst ~= legInst then
        local split = Transport.DepartureCount(leg)
        if pos.inst == legInst then to = split else from = split + 1 end
    end
    local limit2 = Transport.WRONG_RIDE_YARDS * Transport.WRONG_RIDE_YARDS
    if to - from < 1 then
        if not judgeStops then return false end
        local only = pts[from]
        local ex, ey = only.x - pos.x, only.y - pos.y
        return ex * ex + ey * ey > limit2
    end
    for i = from, to - 1 do

        if not (toInst == legInst and leg.split == i) then
            local a, b = pts[i], pts[i + 1]
            local dx, dy = b.x - a.x, b.y - a.y
            local len2 = dx * dx + dy * dy
            local s = 0
            if len2 > 0 then
                s = ((pos.x - a.x) * dx + (pos.y - a.y) * dy) / len2
                if s < 0 then s = 0 elseif s > 1 then s = 1 end
            end
            local ex, ey = a.x + s * dx - pos.x, a.y + s * dy - pos.y
            if ex * ex + ey * ey <= limit2 then return false end
        end
    end
    return true
end






local function becomeUnknownRide(leg, t)
    local state = Transport.state
    forgetDeparture()
    state.unknown, state.transportID, state.stopIndex = true, nil, nil
    state.since = t
    Transport.rideStart, Transport.slowSince = t, nil
    notice(Transport.NOTICE_HOLD, L["This is not the transport of your route (%s). A new route follows as soon as you get off."], leg.label or L["Transport"])
    fireState()
end




function Transport.OnThePath(leg, pos)
    if type(leg) ~= "table" or type(pos) ~= "table" or not pos.x or not pos.y then return false end
    return not offThePath(leg, pos, true)
end



local function beginUnseenRide(leg, t)
    local state = Transport.state
    state.onTransport, state.unknown = true, false
    state.transportID = leg.transportID
    state.stopIndex = legStopIndex(leg, "stopFrom")
    state.since = t
    Transport.rideStart, Transport.slowSince, Transport.ridePhase, Transport.rideGround = t, nil, nil, bestGroundSpeed()
    Transport.dock, Transport.suspectSince = nil, nil
    fireState()
end






function Transport.ConfirmRide(leg, legIndex)
    local state = Transport.state
    if state.onTransport or type(leg) ~= "table" then return false end
    beginUnseenRide(leg, now())
    return true
end

local function flying()
    if not IsFlying then return false end
    local ok, value = pcall(IsFlying)
    return ok and plain(value) == true
end







local function suspectUnseenRide(leg, pos, fast, dDock, t)
    if fast and dDock > Transport.LEAVE_RADIUS and not flying() and not offThePath(leg, pos, true) then
        Transport.suspectSince = Transport.suspectSince or t
        if t - Transport.suspectSince >= Transport.UNSEEN_RIDE_SECONDS then
            beginUnseenRide(leg, t)
        end
    else
        Transport.suspectSince = nil
    end
end

function Transport.OnPosition(pos)
    if not pos or not pos.x then return end
    local state = Transport.state
    local t = now()
    local onTaxi = UnitOnTaxi and UnitOnTaxi("player") or false
    if onTaxi ~= state.onTaxi then
        state.onTaxi = onTaxi
        state.since = t
        if not onTaxi then state.destinationTaxiNode = nil end
        fireState()
    end
    if onTaxi then
        rememberPosition(pos, t)
        return
    end

    local last = Transport.lastPos
    local speed
    if last and last.inst == pos.inst and last.time and t > last.time then
        speed = dist(pos.x, pos.y, last.x, last.y) / (t - last.time)
    end

    if state.onTransport and state.unknown then
        if slowedDown(speed, t) or (Transport.rideStart and t - Transport.rideStart > Transport.UNKNOWN_RIDE_SECONDS) then
            endRide(t)
        end
        rememberPosition(pos, t)
        return
    end

    local leg, legIndex = Transport.NextTransportLeg()





    if not leg or leg.kind == "elevator" then
        if state.onTransport then endRide(t) end
        Transport.dock, Transport.suspectSince = nil, nil
        rememberPosition(pos, t)
        return
    end
    local from, to = legDocks(leg)


    local fromInst = from and (from.inst or leg.inst) or nil
    local toInst = to and (to.inst or leg.toInst or leg.inst) or nil
    if not state.onTransport then
        local stopIndex = legStopIndex(leg, "stopFrom") or 1



        local dock = Transport.dock
        if dock and (dock.transportID ~= leg.transportID or dock.stopIndex ~= stopIndex) then Transport.dock = nil end
        if from and from.x and (fromInst == nil or fromInst == pos.inst) then
            local dDock = dist(pos.x, pos.y, from.x, from.y)
            if dDock <= Transport.DOCK_RADIUS then
                Transport.dock = { transportID = leg.transportID, stopIndex = stopIndex, time = t, legIndex = legIndex }
            elseif Transport.dock and dDock > Transport.FORGET_RADIUS then
                Transport.dock = nil
            end
            local fast = speed ~= nil and speed > Transport.SPEED_FACTOR * bestGroundSpeed()
            if not Transport.dock then
                suspectUnseenRide(leg, pos, fast, dDock, t)
            else
                Transport.suspectSince = nil
            end
            if Transport.dock and fast and dDock > Transport.LEAVE_RADIUS then
                state.onTransport, state.unknown = true, false
                state.transportID = leg.transportID
                state.stopIndex = stopIndex
                state.since = t
                Transport.rideStart, Transport.slowSince, Transport.rideGround = t, nil, bestGroundSpeed()
                local known = Transport.phases[leg.transportID]
                local departure = t - dDock / speed
                Transport.ridePhase = { transportID = leg.transportID, stopIndex = stopIndex, previous = known and known[stopIndex] or nil,
                                        at = departure }
                recordPhase(leg.transportID, stopIndex, departure)
                Transport.dock, Transport.suspectSince = nil, nil
                fireState()
            end
        else
            Transport.suspectSince = nil
        end
    else


        local crossed = toInst ~= nil and fromInst ~= nil and toInst ~= fromInst and pos.inst == toInst
            and leg.points ~= nil and #leg.points > 2
        if to and to.x and (toInst == nil or toInst == pos.inst) and dist(pos.x, pos.y, to.x, to.y) <= Transport.ARRIVE_RADIUS then
            endRide(t, true)
        elseif Transport.rideStart and leg.seconds and t - Transport.rideStart > (leg.seconds * Transport.MAX_RIDE_FACTOR + 60) then
            endRide(t)
        elseif offThePath(leg, pos) then
            becomeUnknownRide(leg, t)
        elseif slowedDown(speed, t) then








            local near = to and to.x and (toInst == nil or toInst == pos.inst) and dist(pos.x, pos.y, to.x, to.y) <= Transport.FORGET_RADIUS
            endRide(t, crossed or near == true)
        end
    end
    rememberPosition(pos, t)
end






function Transport.NextDeparture(transportID, stopIndex, atTime)
    local rec = FGPS.Data and FGPS.Data.transports and FGPS.Data.transports[transportID]
    if not rec or type(rec.period) ~= "number" or rec.period <= 0 then return nil end
    local phases = Transport.phases[transportID]
    local departure = phases and phases[stopIndex]
    if not departure then return nil end
    atTime = atTime or now()
    local elapsed = (atTime - departure) % rec.period
    return rec.period - elapsed
end

function Transport.Reset()
    local state = Transport.state
    state.onTaxi, state.onTransport, state.transportID, state.destinationTaxiNode, state.since, state.stopIndex = false, false, nil, nil, nil, nil
    state.unknown = false
    Transport.dock, Transport.lastPos, Transport.rideStart = nil, nil, nil
    Transport.slowSince, Transport.ridePhase, Transport.rideGround = nil, nil, nil
    Transport.suspectSince = nil
end




function Transport:Init()
    if self.initialised then return end
    self.initialised = true
    Events:Register("POSITION_UPDATE", function(_, pos) Transport.OnPosition(pos) end, self)
    Events:Register("NAV_CANCELLED", function() Transport.Reset() end, self)


    Events:Register("NAV_STATE", function(_, new) if new == "idle" then Transport.Reset() end end, self)
    Events:RegisterWoW("TAXIMAP_OPENED", function(_, system) Transport.OnTaxiMapOpened(plain(system)) end, self)
    Events:RegisterWoW("TAXIMAP_CLOSED", function() Transport.OnTaxiMapClosed() end, self)
    Events:RegisterWoW("PLAYER_CONTROL_LOST", function()
        local state = Transport.state
        if UnitOnTaxi and UnitOnTaxi("player") and not state.onTaxi then
            state.onTaxi, state.since = true, now()
            fireState()
        end
    end, self)
    Events:RegisterWoW("PLAYER_CONTROL_GAINED", function()
        local state = Transport.state
        if state.onTaxi and not (UnitOnTaxi and UnitOnTaxi("player")) then
            state.onTaxi, state.since, state.destinationTaxiNode = false, now(), nil
            fireState()
        end
    end, self)
end
