-- Cabbie/Nav/Transport.lua
-- Runtime transport state. Taxi flights are detected through UnitOnTaxi (with PLAYER_CONTROL_LOST /
-- GAINED as hints); boats, zeppelins and the tram cannot be detected directly (the client offers no
-- "standing on a transport" API), so a heuristic is used: the player was at the departure dock of
-- the route's transport leg and then left the dock area faster than any ground speed while not on
-- a taxi. The ride ends when the player is near the arrival dock. A lift (elevator) moves nobody
-- sideways and the client gives no height, so none of this applies to it: the Navigator holds
-- its leg until the ride has happened (Navigator:HoldLift).
--
-- Three things the heuristic cannot see are covered separately. A player who boards without
-- coming near the stop position is recognised by moving like a vehicle along the way out of the
-- transport for UNSEEN_RIDE_SECONDS (suspectUnseenRide). A ride that was missed all the same is
-- proved by the change of continent itself (Transport.ConfirmRide, called by the Navigator, which
-- first checks that both sides of the loading screen lie on the path). And every tower
-- and most harbours have two transports: once the position is further than WRONG_RIDE_YARDS from
-- the path of the route's transport, the ride is an unknown one (state.unknown), which ends when
-- the player stops moving like a vehicle; the Navigator then asks for a route from there.
--
-- Flight map. TAXIMAP_OPENED(system) is handled for both flight UIs of the Forever client (the
-- Mainline event router shows the classic TaxiFrame when system == Enum.UIMapSystem.Taxi and the
-- load-on-demand FlightMapFrame otherwise):
--   * classic TaxiFrame: NumTaxiNodes / TaxiNodeName / TaxiNodeGetType slots;
--   * FlightMapFrame: C_TaxiMap.GetAllTaxiNodes(GetTaxiMapID()) -> TaxiNodeInfo with
--     state = Enum.FlightPathState (Current 0, Reachable 1, Unreachable 2).
-- Whichever UI is open, the exact node name to click is said in the call-out (a notice of
-- UI/Guide.lua, never a chat line); the other API is tried when the first one lists nothing.
-- The line stands until TAXIMAP_CLOSED takes it down. TakeTaxiNode is never called (the player
-- selects the node).
--
-- Secret values: speeds come from FGPS.Coords.PlayerSpeed (issecretvalue-guarded with constant
-- fallbacks); taxi node fields read from the client pass through the same guard, and a secret
-- value simply means "unknown" (no arithmetic or comparison is done on it).
local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Events = FGPS.Events
local Const = FGPS.Const
local sqrt, type, pairs, ipairs, tostring, pcall, tonumber = math.sqrt, type, pairs, ipairs, tostring, pcall, tonumber

-- nil for secret values (docs/ARCHITECTURE.md section 6).
local function plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local Transport = {
    DOCK_RADIUS = 40,         -- within this distance of the departure dock we are "waiting at the dock"
    LEAVE_RADIUS = 60,        -- boarding is assumed once this far from the dock at transport speed
    -- The ride ends within this distance of the arrival dock. The Navigator counts the leg as
    -- reached within the same radius; with a smaller one of its own it saw a ride that had ended
    -- but a leg that had not, and called the docking ship "off route".
    ARRIVE_RADIUS = Const.TRANSPORT_ARRIVE_YARDS or 60,
    FORGET_RADIUS = 200,      -- walking this far from the dock forgets the dock visit; a ride that slows down this near its arrival stop has arrived
    SPEED_FACTOR = 1.3,       -- transport speed must exceed this multiple of the best ground speed
    MAX_RIDE_FACTOR = 2.5,    -- safety: a ride longer than leg seconds x this is considered over
    WRONG_RIDE_YARDS = 500,   -- this far from the path of the route's transport, the player is on another one
    SLOW_SECONDS = 5,         -- a ride without a known stop is over after this long at ground speed or slower
    -- For this long after a ride is seen, a ground speed at boarding lower than the player's own is
    -- the measure of "slow" (slowedDown): a boat seen at 9-11 yd/s passes 18.2 yd/s within it.
    BOARDING_SECONDS = 10,
    -- The first seconds of a slow stretch are still judged by that measure: one position that did
    -- not move (a stalled reading, a step against the deck) is not yet "the ride has been slow".
    STILL_SECONDS = 1,
    UNKNOWN_RIDE_SECONDS = 600, -- safety: a ride on an unknown transport is considered over after this long
    UNSEEN_RIDE_SECONDS = 2,  -- moving like a vehicle along the transport path for this long is a ride, stop visit or not
    -- Seconds the line about the wrong transport stays in the call-out: it must not be missed.
    NOTICE_HOLD = 8,
    -- The flight to take, and why a flight cannot be taken here, stand while the flight map is
    -- open: the close takes the line down (Transport.OnTaxiMapClosed). This is how long it
    -- stays when no close is ever reported, so that it cannot stay up for good.
    FLIGHT_MAP_HOLD = 120,
    -- unknown = true: the player is being carried, but not by the transport of the route (the other
    -- zeppelin at the same tower). transportID and stopIndex are nil then.
    state = { onTaxi = false, onTransport = false, transportID = nil, destinationTaxiNode = nil, since = nil, stopIndex = nil,
              unknown = false },
    phases = {},              -- transportID -> { [stopIndex] = observed departure time }
    dock = nil,               -- { transportID, stopIndex, time, leg }
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

-- Calls a function of UI/Guide.lua and answers what it answers. That module loads after this
-- one, so it is looked up at the call. A line is a courtesy and what follows the call is not (the
-- ride's state is fired, the flight map's answer is given): the guide is called under pcall, and
-- a raise in it goes to the log.
local function guide(method, ...)
    local Guide = FGPS.UI and FGPS.UI.Guide
    if not (Guide and Guide[method]) then return nil end
    local ok, answer = pcall(Guide[method], ...)
    if ok then return answer end
    if FGPS.Log and FGPS.Log.Error then FGPS.Log:Error("Transport: the guide's %s failed: %s", method, tostring(answer)) end
    return nil
end

-- Says a line on the screen in answer to what the player just did (opened the flight map,
-- boarded another transport than the route's): a notice of UI/Guide.lua, in the call-out, and
-- nothing in chat. Returns the words.
local function notice(hold, fmt, ...)
    local text = FGPS.Util.SafeFormat(fmt, ...)
    guide("Say", text, hold)
    return text
end

-- A line about the open flight map. It stands until the map closes, and its words are kept so
-- that the close takes down this line and no other (Transport.OnTaxiMapClosed).
local function flightNotice(fmt, ...)
    Transport.flightLine = notice(Transport.FLIGHT_MAP_HOLD, fmt, ...)
end

function Transport.State()
    return Transport.state
end

-------------------------------------------------------------------------------
-- Route inspection
-------------------------------------------------------------------------------
local function activeRoute()
    local Nav = FGPS.Navigator
    if not Nav or not Nav.GetRoute then return nil end
    local state = Nav:GetState()
    if state ~= "active" and state ~= "paused" and state ~= "in_transit" then return nil end
    return Nav:GetRoute(), Nav:GetProgress()
end

-- First leg of the given kind set at or after the current leg.
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

-- Numeric index of a leg's departure ("stopFrom") or arrival ("stopTo") stop in the transport
-- record's stops list. The Router writes the stop NAME into leg.stopFrom / leg.stopTo (they are
-- display text); observed departures and Transport.NextDeparture are keyed by the numeric index.
-- An explicit leg.stopFromIndex / leg.stopToIndex wins, then a numeric stopFrom / stopTo, then the
-- stop with that name (the one nearest to the leg's own end point when a name repeats; a stop with
-- no position is nearest only when no stop of that name has one).
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

-------------------------------------------------------------------------------
-- Taxi map
-------------------------------------------------------------------------------
local function taxiNodeName(taxiNodeID)
    local taxi = FGPS.Data and FGPS.Data.taxi
    local node = taxi and taxi.nodes and taxi.nodes[taxiNodeID]
    return node and node.name or nil
end

local function baseName(name)
    return (tostring(name or ""):gsub(",.*$", ""))
end

-- Classic TaxiFrame: finds the slot whose name matches (full name first, then the part before the
-- comma). Returns slot, slotName, slotType ("CURRENT" | "REACHABLE" | "DISTANT" | "UNREACHABLE" |
-- nil when TaxiNodeGetType is unavailable). nil when the classic slot list is empty or missing.
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

-- FlightMapFrame: finds the TaxiNodeInfo whose name (or nodeID) matches in
-- C_TaxiMap.GetAllTaxiNodes(GetTaxiMapID()). Returns { nodeID, name, state, slotIndex } or nil when
-- the API is unavailable or lists nothing.
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

-- system: the TAXIMAP_OPENED payload (Enum.UIMapSystem; Taxi = 1 means the classic TaxiFrame).
-- Says in the call-out the exact node name to select for the route's next flight, or why it
-- cannot be selected here. Returns a result table { ui = "taxi"|"flightmap", name, slot?,
-- nodeID?, state? } or nil when no flight leg is pending. Never calls TakeTaxiNode.
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

-- The flight map closed (the player picked a flight, walked away or closed it): the line that
-- was said when it opened is taken down, if it is still the one shown. A line said since then
-- stays. True when a line was taken down.
function Transport.OnTaxiMapClosed()
    local text = Transport.flightLine
    Transport.flightLine = nil
    return text ~= nil and guide("Unsay", text) == true
end

-------------------------------------------------------------------------------
-- Position updates (4 Hz from the Navigator while navigating)
-------------------------------------------------------------------------------
-- Fastest speed the character could reach on the ground right now (secret-safe: Coords.PlayerSpeed
-- returns the constants when the client hides the values).
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

-- A departure this session, used by NextDeparture below.
local function recordPhase(transportID, stopIndex, departureTime)
    if not transportID or not stopIndex then return end
    local t = Transport.phases[transportID]
    if not t then t = {} Transport.phases[transportID] = t end
    t[stopIndex] = departureTime
end

-- Nav/Calibrate.lua stores the departure of a ride on the wall clock, so the next session starts
-- out knowing the schedule instead of assuming half a period. Only once the ride has arrived where
-- the route's transport arrives: at boarding the other boat or zeppelin of the same stop looks the
-- same, and a store written then kept that one's departure for every later session.
local function storeDeparture(phase)
    local Calibrate = FGPS.Calibrate
    if phase and Calibrate and Calibrate.NoteDeparture then
        pcall(Calibrate.NoteDeparture, phase.transportID, phase.stopIndex, phase.at)
    end
end

-- The departure written down at boarding was not one of the route's transport (the ride was
-- another one, or none at all): this session's goes back to what was known before.
local function forgetDeparture()
    local phase = Transport.ridePhase
    if phase and Transport.phases[phase.transportID] then
        Transport.phases[phase.transportID][phase.stopIndex] = phase.previous
    end
    Transport.ridePhase = nil
end

-- The previous position, kept in one table that is written in place: this runs four times a
-- second for the whole journey.
local function rememberPosition(pos, t)
    local last = Transport.lastPos
    if not last then
        last = {}
        Transport.lastPos = last
    end
    last.x, last.y, last.inst, last.time = pos.x, pos.y, pos.inst, t
end

-- arrived: the ride ended where the route's transport arrives (its stop, or near it or on its
-- arrival continent once it stopped moving), which shows it was that transport. Any other end shows nothing of the
-- kind, and its departure is not kept.
local function endRide(t, arrived)
    if arrived then storeDeparture(Transport.ridePhase) else forgetDeparture() end
    local state = Transport.state
    state.onTransport, state.unknown, state.transportID, state.stopIndex = false, false, nil, nil
    state.since = t
    Transport.rideStart, Transport.slowSince, Transport.ridePhase, Transport.rideGround = nil, nil, nil, nil
    Transport.suspectSince = nil
    fireState()
end

-- True once the player has moved at ground speed or slower for SLOW_SECONDS: whatever carried
-- them has stopped, or they got off. speed is nil when it could not be measured on this tick
-- (the first position after a loading screen), which changes nothing. Until the ride has been
-- slow for STILL_SECONDS, and for its first BOARDING_SECONDS only, the measure is the ground speed
-- it was last seen faster than (Transport.rideGround, set at boarding) when that is lower: a mount
-- got onto on the deck just after the boat pulled away raised the line above a transport still
-- speeding up out of its stop, and the ride was over on the departure side; one still tick after
-- that mount put the mount's line in place at once and did the same. Without the time limit a
-- burst at the pier followed by a faster run (travel form) was a ride for as long as the run lasted.
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

-- True when the position cannot be on the transport of this leg: an instance the leg never
-- visits, or further than WRONG_RIDE_YARDS from the part of its path that lies in the player's
-- instance. Two zeppelins leave from every Horde tower and two boats from Menethil Harbor, and the
-- boarding heuristic cannot tell them apart at the stop; their paths can, soon after. A leg
-- without a path (two points: nothing but the stops is known) or whose path in this instance is a
-- single point is never judged.
--
-- With judgeStops the question is the opposite one, "is there evidence that the player IS on this
-- transport" (a ride nobody saw begin), and then too little data must not count as a yes: what
-- little is known is judged, a single stop as a path without length.
-- The number of leading points of a leg in its departure frame: all of them for a leg that stays on
-- one continent; for a crossing leg (toInst set apart from inst) its split, or, where it does not say
-- where the jump is, all but the last, the one point that can be trusted about the arrival side. The
-- one reading the maps, the Navigator and the in-world pin share.
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
        -- The jump of a path that teleports inside one instance is not a stretch of the path.
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

-- The ride turned out not to be the one the route asked for. The player is still being carried,
-- so the state stays "on a transport" (no off-route alarm, no route computed from mid-air), but
-- nothing is known about where it ends: it is over when the player slows down. The departure that
-- was written down for the route's transport at boarding was not its departure, so that goes
-- back to what was known before.
local function becomeUnknownRide(leg, t)
    local state = Transport.state
    forgetDeparture()
    state.unknown, state.transportID, state.stopIndex = true, nil, nil
    state.since = t
    Transport.rideStart, Transport.slowSince = t, nil
    notice(Transport.NOTICE_HOLD, L["This is not the transport of your route (%s). A new route follows as soon as you get off."], leg.label or L["Transport"])
    fireState()
end

-- True when pos lies within WRONG_RIDE_YARDS of the part of the leg's path that is in the player's
-- instance (a stop alone counts as a path without length): the evidence asked for before a ride
-- that nobody saw begin is believed.
function Transport.OnThePath(leg, pos)
    if type(leg) ~= "table" or type(pos) ~= "table" or not pos.x or not pos.y then return false end
    return not offThePath(leg, pos, true)
end

-- A ride that began without a remembered visit to the stop. No departure is written down: when
-- the transport left is not known.
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

-- The Navigator saw the player change continent exactly as the route's transport leg does, which
-- proves a ride the boarding heuristic did not notice (the player never came within DOCK_RADIUS
-- of the stop's position, or the transport pulled away too slowly). The Navigator checks that
-- both sides of the loading screen lie on the leg's path before it calls this (a hearthstone or a
-- portal changes continent as well).
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

-- The player is moving like a vehicle along the way out of the route's transport, but was never
-- seen at its stop (the stop's position is the middle of the deck; someone who boards from the far
-- end of the platform never comes within DOCK_RADIUS of it). One fast tick is a Blink or a Charge,
-- so the ride is believed only after UNSEEN_RIDE_SECONDS of it without a break. Until then
-- Transport.suspectSince tells the Navigator not to count these ticks as walking off the route:
-- at four ticks a second it would otherwise recalculate from the deck first.
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
    -- A lift carries the player straight up or down, and UnitPosition gives no height: nothing in
    -- the position shows that ride. A burst of speed beside the shaft (a Blink, a Charge) is none,
    -- and taken for one it kept the journey "in transit", with no off-route check, for a minute or
    -- more. The Navigator holds a lift leg itself (Navigator:HoldLift: a change of map, or the
    -- ride's seconds at the landing), so no ride is ever detected for one here.
    if not leg or leg.kind == "elevator" then
        if state.onTransport then endRide(t) end
        Transport.dock, Transport.suspectSince = nil, nil
        rememberPosition(pos, t)
        return
    end
    local from, to = legDocks(leg)
    -- A stop taken from the leg's own points carries no instance; it is in the leg's departure or
    -- arrival instance. Without this an Eastern Kingdoms stop was compared with a Kalimdor position.
    local fromInst = from and (from.inst or leg.inst) or nil
    local toInst = to and (to.inst or leg.toInst or leg.inst) or nil
    if not state.onTransport then
        local stopIndex = legStopIndex(leg, "stopFrom") or 1
        -- A visit remembered for another leg's stop is none to this one's: the route changed at a
        -- tower or harbour with two transports, whose stops are 50 yd apart. Kept, it gave the
        -- ride the other record's stop index, and the departure was written down under it.
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
        -- A leg of two points (no path, so offThePath never judges it) has docked only near its stop:
        -- taken on the crossing alone, a slow-down anywhere on that continent kept the departure.
        local crossed = toInst ~= nil and fromInst ~= nil and toInst ~= fromInst and pos.inst == toInst
            and leg.points ~= nil and #leg.points > 2
        if to and to.x and (toInst == nil or toInst == pos.inst) and dist(pos.x, pos.y, to.x, to.y) <= Transport.ARRIVE_RADIUS then
            endRide(t, true)
        elseif Transport.rideStart and leg.seconds and t - Transport.rideStart > (leg.seconds * Transport.MAX_RIDE_FACTOR + 60) then
            endRide(t)
        elseif offThePath(leg, pos) then
            becomeUnknownRide(leg, t)
        elseif slowedDown(speed, t) then
            -- No longer moving like a vehicle, but not within ARRIVE_RADIUS of where the data puts
            -- the stop. Within FORGET_RADIUS of it, or on the arrival continent after the crossing,
            -- the transport has docked all the same: a boat or zeppelin slows down into its stop
            -- at 1 yd/s^2, and for a mounted player it is no faster than the ground some 165 yd
            -- out. Anywhere else the ride ends the same way: a transport does not slow down between
            -- its stops, so whatever was fast is over. A ride believed on speed alone, and one
            -- begun on a single fast tick near the stop (a Blink, a Charge, a knock-back off the
            -- pier), was otherwise "in transit" until the safety time above.
            local near = to and to.x and (toInst == nil or toInst == pos.inst) and dist(pos.x, pos.y, to.x, to.y) <= Transport.FORGET_RADIUS
            endRide(t, crossed or near == true)
        end
    end
    rememberPosition(pos, t)
end

-------------------------------------------------------------------------------
-- Departure estimate
-------------------------------------------------------------------------------
-- Seconds until the next departure from a stop, from an observed departure and the period;
-- nil when the phase was never observed.
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

-------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------
function Transport:Init()
    if self.initialised then return end
    self.initialised = true
    Events:Register("POSITION_UPDATE", function(_, pos) Transport.OnPosition(pos) end, self)
    Events:Register("NAV_CANCELLED", function() Transport.Reset() end, self)
    -- A journey that ends by arriving goes idle without NAV_CANCELLED and POSITION_UPDATE stops, so
    -- nothing else would ever clear a ride flag again.
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
