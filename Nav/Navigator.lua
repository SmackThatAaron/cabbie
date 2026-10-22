
























local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local Events = FGPS.Events
local Const = FGPS.Const
local sqrt, floor, format, type, pairs, ipairs, tostring = math.sqrt, math.floor, string.format, type, pairs, ipairs, tostring
local huge = math.huge

local Navigator = {
    state = "idle",
    route = nil,
    progress = nil,
    variant = "fastest",
    ticker = nil,
    inflight = nil,
    requestToken = 0,
    lastRecalcAt = nil,
    offRouteTicks = 0,
    inCombat = false,
    pendingAnnounce = false,
    pauseReason = nil,
    quiet = false,
    askedBy = "player",
    alternatives = nil,
    alternativesAt = nil,
    altHandle = nil,
    altToken = 0,
    itineraryRev = 0,
    riding = false,
    lastPos = nil,
    tripOpen = false,
    pendingReroute = nil,
    pendingAskedBy = nil,
    questHop = nil,
    QUEST_HOP_SECONDS = 900,


    TRANSPORT_ARRIVE_YARDS = Const.TRANSPORT_ARRIVE_YARDS or 60,
    TRANSPORT_DEPART_YARDS = 60,
    LIFT_YARDS = 25,
    RESYNC_MAX_YARDS = 400,
    TELEPORT_JUMP_YARDS = 100,
    PROGRESS_YARDS = 0.5,
    FOLLOW_BAND_FACTOR = 2,


    CONTINUITY_SLACK_YARDS = 10,


    CONTINUITY_TICKS = 12,
    KEPT_RETRY_YARDS = 50,
    KEPT_RETRY_SECONDS = 60,
    STAY_FIRST_YARDS = 50,
    STAY_LEAVE_YARDS = 20,
    ALTERNATIVES_TTL = 60,



    place = {},
    PLACE_HINT_SECONDS = 60,
    PLACE_HINT_YARDS = 40,
    WRONG_LEVEL_TICKS = 2,
    WRONG_LEVEL_ROOM_YARDS = 30,
    wrongLevelTicks = 0,
}
FGPS.Navigator = Navigator

local STATES = { idle = true, previewing = true, active = true, paused = true, in_transit = true, arrived = true }
Navigator.STATES = STATES




local function now() return GetTime and GetTime() or 0 end

local function setting(path, default)
    local DB = FGPS.DB
    if DB and DB.initialized then
        local v = DB:Get(path)
        if v ~= nil then return v end
    end
    return default
end

local function dist(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return sqrt(dx * dx + dy * dy)
end




local lastMoveYps
local function liveGroundYps()
    local fallback = (FGPS.Const and FGPS.Const.RUN_SPEED) or 7
    local Coords = FGPS.Coords
    local current, run
    if Coords and Coords.PlayerSpeed then
        local ok, c, r = pcall(Coords.PlayerSpeed)
        if ok then current, run = c, r end
    end
    local riding = UnitOnTaxi and UnitOnTaxi("player")
    local transport = FGPS.Transport and FGPS.Transport.State and FGPS.Transport.State()
    if transport and transport.onTransport then riding = true end
    if not riding and type(current) == "number" and current > 1 then
        lastMoveYps = current
    end
    if lastMoveYps and lastMoveYps > 1 then return lastMoveYps end
    if type(run) == "number" and run > 1 then return run end
    return fallback
end

local function legYardsLeft(leg, segIndex, x, y, current)
    if not current then return leg.yards or 0 end
    local R = FGPS.Route
    if R and R.RemainingYards then
        local ok, v = pcall(R.RemainingYards, { legs = { leg } }, 1, segIndex, x, y)
        if ok and type(v) == "number" then return v end
    end
    return leg.yards or 0
end




local function liveWalkDelta(route, legIndex, segIndex, x, y)
    local legs = route and route.legs
    if not legs then return 0 end
    local ground = liveGroundYps()
    local delta = 0
    for i = legIndex, #legs do
        local leg = legs[i]
        if leg and (leg.kind or "walk") == "walk" then
            local yards = legYardsLeft(leg, segIndex, x, y, i == legIndex)
            local total = leg.yards or 0
            local share = 1
            if i == legIndex and total > 0 then
                share = yards / total
                if share > 1 then share = 1 elseif share < 0 then share = 0 end
            end
            local model = (leg.seconds or 0) * share
            local live = (ground > 0) and (yards / ground) or model
            delta = delta + (live - model)
        end
    end
    return delta
end

local function charDB()
    local DB = FGPS.DB
    if not DB or not DB.char then return nil end
    return DB.char
end






local rekeyedStops = setmetatable({}, { __mode = "k" })
local function rekeyStops(list)
    local D, P = FGPS.Destinations, FGPS.Data and FGPS.Data.poi
    if not (D and D.Rekey and P) or rekeyedStops[list] == P then return end
    for i = 1, #list do D.Rekey(list[i]) end
    rekeyedStops[list] = P
end


local function stopsTable()
    local char = charDB()
    if not char then
        Navigator.volatileStops = Navigator.volatileStops or {}
        return Navigator.volatileStops
    end
    if type(char.itinerary) ~= "table" then char.itinerary = {} end
    rekeyStops(char.itinerary)
    return char.itinerary
end

local function plainDest(dest)
    local D = FGPS.Destinations
    if D and D.Plain then return D.Plain(dest) end
    return Util.ShallowCopy(dest)
end

local function describe(dest)
    local D = FGPS.Destinations
    if D and D.Describe then return D.Describe(dest) end
    return dest and dest.name or "?"
end



local function sameDest(a, b)
    if a == nil or b == nil then return false end
    if a == b then return true end
    local D = FGPS.Destinations
    if D and D.Equal then return D.Equal(a, b) end
    return a.inst == b.inst and a.x == b.x and a.y == b.y
end

local function playerPos()
    local C = FGPS.Coords
    if C and C.PlayerPos then return C.PlayerPos() end
    local D = FGPS.Destinations
    if D and D.PlayerPos then return D.PlayerPos() end
    return nil
end
Navigator.PlayerPos = playerPos

local function isMounted()
    return IsMounted and IsMounted() or false
end

local function onTaxi()
    return UnitOnTaxi and UnitOnTaxi("player") or false
end






local GUESSED_KINDS = { [3] = true, [4] = true, [14] = true, [15] = true, [19] = true }



local TELEPORT_KINDS = { hearth = true, spell = true }

local function errorMessage(err)
    if type(err) ~= "table" then return L.ROUTE_NO_PATH end
    local code = err.code
    if code == "NO_ORIGIN" then return L.ROUTE_NO_ORIGIN end
    if code == "UNREACHABLE" then return err.message and err.message ~= "" and err.message or L.ROUTE_UNREACHABLE end
    if code == "NO_DATA" then return L.ROUTE_NO_DATA end
    if code == "CANCELLED" then return L.ROUTE_CANCELLED end
    return err.message and err.message ~= "" and err.message or L.ROUTE_NO_PATH
end


local function reportError(err, quiet)
    if type(err) == "table" and err.code == "CANCELLED" then return end
    if not quiet then FGPS:Print("%s", errorMessage(err)) end
    if FGPS.Log then FGPS.Log:Warn("Route request failed: %s (%s)", tostring(err and err.code), tostring(err and err.message)) end
end



local function namedRoute(route, err)
    if type(route) == "table" and type(route.legs) == "table" and #route.legs > 0 then
        return route, err
    end
    if route ~= nil then
        return nil, { code = "NO_PATH", message = L.ROUTE_NO_PATH }
    end
    return nil, err
end




local function projectLocal(leg, x, y)
    local points = leg.points
    local n = #points
    if n == 0 then return nil end
    if n == 1 then return 1, 0, dist(x, y, points[1].x, points[1].y), 0 end
    local bestI, bestT, bestD2, bestAlong = 1, 0, nil, 0
    local along = 0
    for i = 1, n - 1 do
        local a, b = points[i], points[i + 1]
        local dx, dy = b.x - a.x, b.y - a.y
        local len2 = dx * dx + dy * dy
        local t = 0
        if len2 > 0 then
            t = ((x - a.x) * dx + (y - a.y) * dy) / len2
            if t < 0 then t = 0 elseif t > 1 then t = 1 end
        end
        local px, py = a.x + t * dx, a.y + t * dy
        local d2 = (x - px) * (x - px) + (y - py) * (y - py)
        local segLen = sqrt(len2)
        if not bestD2 or d2 < bestD2 then bestI, bestT, bestD2, bestAlong = i, t, d2, along + t * segLen end
        along = along + segLen
    end
    return bestI, bestT, sqrt(bestD2), bestAlong
end


local function cumulative(leg)
    local cum = leg._cum
    if cum then return cum end
    cum = { 0 }
    local pts = leg.points
    for i = 2, #pts do cum[i] = cum[i - 1] + dist(pts[i - 1].x, pts[i - 1].y, pts[i].x, pts[i].y) end
    leg._cum = cum
    return cum
end






local function alongSegment(leg, along)
    local cum = cumulative(leg)
    local last = #leg.points - 1
    local reached = (along or 0) + 1e-6
    local i = 1
    while i < last and cum[i + 1] <= reached do i = i + 1 end
    return i
end


local function project(leg, x, y)
    local R = FGPS.Route
    if R and R.Project then
        local ok, i, t, d, along = pcall(R.Project, leg, x, y)
        if ok and type(i) == "number" and i >= 1 and i <= #leg.points and type(d) == "number" then
            return i, t or 0, d, along or 0
        end
    end
    return projectLocal(leg, x, y)
end












local function projectNear(leg, x, y, fromIndex, sinceAlong, bandYards)
    local R = FGPS.Route
    if R and R.ProjectWindow then
        local band = R.WINDOW_BAND_YARDS
        if bandYards and not (band and band >= bandYards) then band = bandYards end
        local ok, i, t, d, along = pcall(R.ProjectWindow, leg, x, y, fromIndex, R.WINDOW_AHEAD_YARDS, band, sinceAlong)
        if ok and type(i) == "number" and i >= 1 and i <= #leg.points and type(d) == "number" then
            local narrow = R.WINDOW_BAND_YARDS

            if narrow and d > narrow and d <= band then
                local wi, wt, wd, walong = project(leg, x, y)
                if wi and wd and wd <= narrow then return wi, wt or 0, wd, walong or 0 end
            end
            return i, t or 0, d, along or 0
        end
    end
    return project(leg, x, y)
end



local function alongSegmentCos(leg, i, mx, my, moved)
    local a, b = leg.points[i], leg.points[i + 1]
    if not (a and b) then return 0 end
    local vx, vy = b.x - a.x, b.y - a.y
    local len = sqrt(vx * vx + vy * vy)
    if len <= 0 or moved <= 0 then return 0 end
    return (mx * vx + my * vy) / (len * moved)
end












local function keepContinuous(self, leg, pos, segIndex, perp, along, held)
    local p = self.progress
    local m = p.match
    local R = FGPS.Route
    local t = now()
    local accept = not (m and m.leg == p.legIndex and type(along) == "number" and type(perp) == "number"
        and R and R.ProjectRange)
    local reach, ri, rd, ralong, _
    if not accept then
        local dt = t - m.at
        if dt < 0 then dt = 0 end
        reach = liveGroundYps() * dt + self.CONTINUITY_SLACK_YARDS
        accept = math.abs(along - m.along) <= reach
    end
    if not accept then
        local mx, my = pos.x - m.x, pos.y - m.y
        local moved = sqrt(mx * mx + my * my)
        ri, _, rd, ralong = R.ProjectRange(leg, pos.x, pos.y, m.along - reach, m.along + reach)


        if not ri or rd > held or moved > reach then
            accept = true
        else
            if moved >= self.PROGRESS_YARDS then
                local there = alongSegmentCos(leg, segIndex, mx, my, moved)
                if there > 0.5 and there > alongSegmentCos(leg, ri, mx, my, moved) + 0.5 then
                    m.toward = m.toward + 1
                else
                    m.toward = 0
                end
            end
            accept = m.toward >= self.CONTINUITY_TICKS
        end
    end
    if accept then
        p.match = { leg = p.legIndex, along = along, at = t, x = pos.x, y = pos.y, toward = 0 }
        return segIndex, perp, along
    end
    m.along, m.at, m.x, m.y = ralong, t, pos.x, pos.y
    return ri, rd, ralong
end



local function remainingYardsLocal(route, legIndex, segIndex, x, y, suffixYards)
    local leg = route.legs[legIndex]
    local rest = suffixYards[legIndex + 1] or 0
    if not leg then return 0, rest end
    local pts = leg.points
    local n = #pts
    if n == 0 then return 0, rest end
    local ahead = segIndex + 1
    if ahead > n then ahead = n end
    if ahead < 1 then ahead = 1 end
    local cum = cumulative(leg)
    local remaining = dist(x, y, pts[ahead].x, pts[ahead].y) + (cum[n] - cum[ahead])
    return remaining, remaining + rest
end









local function arrivalInst(leg)
    return leg.toInst or leg.inst
end

local function crossesInstances(leg)
    return leg.kind ~= "walk" and leg.toInst ~= nil and leg.toInst ~= leg.inst
end



local function departureCount(leg)
    return FGPS.Transport.DepartureCount(leg)
end












local function transportTarget(leg, pos, riding)
    local n = #leg.points
    if pos and crossesInstances(leg) and pos.inst == leg.inst then
        if not riding then return 1 end
        local wayOut = departureCount(leg)
        if wayOut >= 2 then return wayOut end
    elseif pos and n > 2 and pos.inst == leg.inst and not crossesInstances(leg) then
        if not riding then return 1 end
        local i = project(leg, pos.x, pos.y)
        if i and i < n then return i + 1 end
    end
    return n
end

local function pathYards(pts, from, to)
    local yards = 0
    for i = from, to - 1 do yards = yards + dist(pts[i].x, pts[i].y, pts[i + 1].x, pts[i + 1].y) end
    return yards
end





local function crossingShareAhead(leg, pos)
    local pts = leg.points
    local n = #pts
    local split = departureCount(leg)
    if not leg._departYards then
        leg._departYards, leg._arriveYards = pathYards(pts, 1, split), pathYards(pts, split + 1, n)
    end
    local from, to, beyond
    if pos.inst == leg.inst then
        from, to, beyond = 1, split, leg._arriveYards
    elseif pos.inst == leg.toInst then
        from, to, beyond = split + 1, n, 0
    else
        return nil
    end
    local total = leg._departYards + leg._arriveYards
    local ahead
    if to > from then

        local bestD2
        local behindEnd = 0
        for i = to - 1, from, -1 do
            local a, b = pts[i], pts[i + 1]
            local dx, dy = b.x - a.x, b.y - a.y
            local len2 = dx * dx + dy * dy
            local t = 0
            if len2 > 0 then
                t = ((pos.x - a.x) * dx + (pos.y - a.y) * dy) / len2
                if t < 0 then t = 0 elseif t > 1 then t = 1 end
            end
            local ex, ey = a.x + t * dx - pos.x, a.y + t * dy - pos.y
            local d2 = ex * ex + ey * ey
            local segLen = sqrt(len2)
            if not bestD2 or d2 < bestD2 then bestD2, ahead = d2, behindEnd + (1 - t) * segLen end
            behindEnd = behindEnd + segLen
        end
    elseif pos.inst == leg.toInst then


        local yards = leg.yards or 0
        if yards <= 0 then return 0 end
        local share = dist(pos.x, pos.y, pts[n].x, pts[n].y) / yards
        if share > 1 then share = 1 end
        return share
    else
        ahead = 0
    end
    if total <= 0 then return pos.inst == leg.inst and 1 or 0 end
    local share = (ahead + beyond) / total
    if share > 1 then share = 1 end
    return share
end







local function rideSeconds(leg)
    if leg.measured == "flight" then return leg.seconds or 0 end
    local wait = leg.measured == "transport" and leg.waitSeconds or leg.wait
    local seconds = (leg.seconds or 0) - (wait or 0) - (leg.penaltySeconds or 0)
    if seconds < 0 then seconds = 0 end
    return seconds
end




function Navigator:GetState() return self.state end
function Navigator:GetRoute() return self.route end
function Navigator:GetProgress() return self.progress end

function Navigator:CombatPolicy()
    local policy = setting("combatMode", "visuals_only")
    if policy ~= "all" and policy ~= "visuals_only" and policy ~= "hide_all" then policy = "visuals_only" end
    return policy
end

function Navigator:IsJourney()
    local s = self.state
    return s == "active" or s == "paused" or s == "in_transit"
end



function Navigator:UpdateTicker()
    local need = self:IsJourney()
    if need and not self.ticker then
        if C_Timer and C_Timer.NewTicker then
            self.ticker = C_Timer.NewTicker(1 / (Const.POS_HZ or 4), function() Navigator:Tick() end)
        end
    elseif not need and self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
end

function Navigator:SetState(new)
    assert(STATES[new], "Navigator: unknown state " .. tostring(new))
    local old = self.state
    if old == new then return end
    self.state = new
    Events:Fire("NAV_STATE", new, old)
    self:UpdateTicker()
end




function Navigator:GetStops()
    local list = stopsTable()
    local out = {}
    for i = 1, #list do out[i] = list[i] end
    return out
end

function Navigator:StopCount()
    return #stopsTable()
end

local hideKeptPopup




local function fireItinerary(reason)
    Navigator.itineraryRev = Navigator.itineraryRev + 1
    Navigator:DropAlternatives()
    if Navigator.keptRev then hideKeptPopup() end
    Events:Fire("ITINERARY_CHANGED", Navigator:GetStops(), reason)
end

local function validDest(dest)
    return type(dest) == "table" and type(dest.inst) == "number" and type(dest.x) == "number" and type(dest.y) == "number"
end




function Navigator:AfterItineraryChange(reason)
    if #stopsTable() == 0 then
        if self.state ~= "idle" or self.inflight then self:Cancel("no_stops") end
        return
    end
    if self:IsJourney() then
        self:Reroute(reason)
    elseif self.state == "previewing" then
        self:Preview("navigator")
    end
end




function Navigator:SetDestination(dest, opts)
    opts = opts or {}
    if not validDest(dest) then return nil, "invalid_destination" end
    local D = FGPS.Destinations
    if D and D.Resolve then D.Resolve(dest) end
    local plain = plainDest(dest)
    local list = stopsTable()
    if opts.addStop then
        list[#list + 1] = plain
    else
        wipe(list)
        list[1] = plain

        self.variant = "fastest"
        self.questHop = nil


        if opts.askedBy ~= "navigator" then self.stayedAt, self.hopAsked = nil, nil end
    end
    local char = charDB()
    if char then char.lastDestination = plainDest(plain) end
    Events:Fire("DESTINATION_SET", plain)
    fireItinerary(opts.addStop and "added" or "set")



    if not opts.quiet then FGPS:Print(L.DESTINATION_SET, describe(plain)) end



    local heldPause = self.state == "paused" and not self.pauseReason and not opts.start
    if self:IsJourney() and not heldPause then
        self.quiet = opts.quiet == true
        self:Reroute(opts.addStop and "added" or "destination", opts.askedBy or "player")
    elseif opts.start then



        if self.state == "previewing" then
            self:DropRoute()
            self.progress = nil
            self:SetState("idle")
        end
        self:Start(nil, opts.quiet, true, opts.askedBy)
    elseif self.state == "previewing" then
        self:Preview(opts.askedBy)
    end
    return plain
end

function Navigator:AddStop(dest, opts)
    opts = opts or {}
    opts.addStop = true

    if opts.start == nil then
        local list = stopsTable()
        opts.start = (not self:IsJourney()) and (type(list) ~= "table" or #list == 0)
    end
    return self:SetDestination(dest, opts)
end

function Navigator:RemoveStop(i)
    local list = stopsTable()
    if type(i) ~= "number" or not list[i] then return false end
    table.remove(list, i)
    fireItinerary("removed")
    self:AfterItineraryChange("itinerary")
    return true
end

function Navigator:MoveStop(i, j)
    local list = stopsTable()
    local n = #list
    if type(i) ~= "number" or type(j) ~= "number" or i < 1 or j < 1 or i > n or j > n or i == j then return false end
    local item = table.remove(list, i)
    table.insert(list, j, item)
    fireItinerary("moved")
    self:AfterItineraryChange("itinerary")
    return true
end


function Navigator:SkipStop()
    local list = stopsTable()
    if #list == 0 then return false end
    table.remove(list, 1)
    fireItinerary("skipped")
    if #list == 0 then
        if self.state ~= "idle" or self.inflight then self:Cancel("skipped_last_stop") end
    else
        self:AfterItineraryChange("skip")
    end
    return true
end

function Navigator:ClearStops()
    local list = stopsTable()
    local had = #list > 0
    wipe(list)
    fireItinerary("cleared")
    if self.state ~= "idle" or self.inflight then self:Cancel("cleared") end
    return had
end



local function straightCost(a, b)
    if a.inst ~= b.inst then return 1e7 + dist(a.x, a.y, b.x, b.y) end
    return dist(a.x, a.y, b.x, b.y)
end


function Navigator.OptimizeOrder(origin, stops)
    local n = #stops
    if n < 2 then
        local out = {}
        for i = 1, n do out[i] = i end
        return out
    end
    local start = origin or stops[1]
    local used, order = {}, {}
    local current = start
    for _ = 1, n do
        local bestI, bestD
        for i = 1, n do
            if not used[i] then
                local d = straightCost(current, stops[i])
                if not bestD or d < bestD then bestI, bestD = i, d end
            end
        end
        used[bestI] = true
        order[#order + 1] = bestI
        current = stops[bestI]
    end
    local function pathCost(seq)
        local total = straightCost(start, stops[seq[1]])
        for i = 1, #seq - 1 do total = total + straightCost(stops[seq[i]], stops[seq[i + 1]]) end
        return total
    end
    local improved, guard = true, 0
    local best = pathCost(order)
    while improved and guard < 50 do
        improved = false
        guard = guard + 1
        for i = 1, n - 1 do
            for j = i + 1, n do
                local candidate = {}
                for k = 1, i - 1 do candidate[#candidate + 1] = order[k] end
                for k = j, i, -1 do candidate[#candidate + 1] = order[k] end
                for k = j + 1, n do candidate[#candidate + 1] = order[k] end
                local cost = pathCost(candidate)
                if cost + 1e-6 < best then
                    order, best, improved = candidate, cost, true
                end
            end
        end
    end
    return order
end


function Navigator:OptimizeStops()
    local list = stopsTable()
    if #list < 2 then return false end
    local origin = playerPos()
    local order = Navigator.OptimizeOrder(origin, list)
    local reordered = {}
    for i, idx in ipairs(order) do reordered[i] = list[idx] end
    for i = 1, #list do list[i] = reordered[i] end
    fireItinerary("optimized")
    self:AfterItineraryChange("optimized")
    return true
end




local function accessSnapshot()
    local Access = FGPS.Access
    if Access and Access.Snapshot then
        local ok, access = pcall(Access.Snapshot, Access)
        if ok then return access end
    end
    return nil
end



local function straightFallback(route)
    return type(route) == "table" and route.fallback == "straight"
end


local function matchedPoint(self)
    local route, p = self.route, self.progress
    if not route or not p then return nil end
    local leg = route.legs and route.legs[p.legIndex or 1]
    local pts = leg and leg.points
    if not pts then return nil end
    local idx = p.pointIndex or 1
    if not pts[idx] then idx = pts[idx - 1] and idx - 1 or 1 end
    local pt = pts[idx]
    if type(pt) ~= "table" then return nil end
    return pt, idx, leg
end




local function levelHint(self)
    local pt = matchedPoint(self)
    if pt and type(pt.z) == "number" then return pt.z end
    return nil
end


local function readPlace(self)
    local C = FGPS.Coords
    if not (C and C.PlayerPlace) then return self.place end
    local ok, got = pcall(C.PlayerPlace)
    if ok and type(got) == "table" then self.place.indoor, self.place.name = got.indoor, got.name end
    return self.place
end

function Navigator:CurrentPlace()
    local p = self.place
    return { indoor = p.indoor, name = p.name, z = p.z, at = p.at, x = p.x, y = p.y, inst = p.inst }
end



function Navigator:LevelZ()
    if self.state ~= "active" and self.state ~= "paused" then return nil end
    if (self.offRouteTicks or 0) >= (Const.OFFROUTE_TICKS or 3) then return nil end
    return levelHint(self)
end



local function freshHint(self, origin)
    local p = self.place
    if type(p.z) ~= "number" or not p.at or p.inst ~= origin.inst then return nil end
    if now() - p.at > self.PLACE_HINT_SECONDS then return nil end
    if dist(origin.x, origin.y, p.x, p.y) > self.PLACE_HINT_YARDS then return nil end
    return p.z
end

function Navigator:BuildRequest(reason, variant)
    local origin = playerPos()
    if origin then
        local place = readPlace(self)
        origin.place = { indoor = place.indoor, name = place.name }


        local hint
        if reason == "recalc" or reason == "reroute" then
            hint = levelHint(self)
        elseif reason ~= "level" then
            hint = freshHint(self, origin)
        end
        if hint then origin.zHint = hint end
    end
    return {
        origin = origin,
        stops = self:GetStops(),
        access = accessSnapshot(),
        variant = variant or self.variant or "fastest",
        reason = reason,
    }
end

function Navigator:CancelInflight()
    local entry = self.inflight
    self.inflight = nil
    if entry and entry.handle then
        local Router = FGPS.Router
        if Router and Router.Cancel then pcall(Router.Cancel, Router, entry.handle) end
    end

    self.requestToken = self.requestToken + 1
end









function Navigator:Request(kind, reason, variant, onResult, askedBy)
    local owed = self.inflight ~= nil and self.inflight.askedBy == "player"
    self:CancelInflight()
    askedBy = (owed or askedBy ~= "navigator") and "player" or "navigator"
    self.askedBy = askedBy
    local Router = FGPS.Router
    if not (Router and Router.RequestRoute) then
        onResult(nil, { code = "NO_DATA", message = L.ROUTE_NO_DATA })
        return nil
    end
    local request = self:BuildRequest(reason, variant)



    if kind == "recalc" and self.route and not straightFallback(self.route) then
        request.fallbackCapYards = Const.RECALC_FALLBACK_CAP_YARDS or 150
    end


    if kind == "recalc" then request.bypassCache = true end
    if not request.origin then
        onResult(nil, { code = "NO_ORIGIN", message = L.ROUTE_NO_ORIGIN })
        return nil
    end
    if #request.stops == 0 then
        onResult(nil, { code = "NO_PATH", message = L["No destination set."] })
        return nil
    end
    local token = self.requestToken
    local entry = { kind = kind, token = token, reason = reason, request = request, itineraryRev = self.itineraryRev,
                    askedBy = askedBy }
    self.inflight = entry
    local ok, handle = pcall(Router.RequestRoute, Router, request, function(route, err)
        if self.inflight == entry then self.inflight = nil end
        if token ~= self.requestToken then return end
        entry.delivered = true
        if entry.itineraryRev ~= self.itineraryRev and not (type(err) == "table" and err.code == "CANCELLED") and #stopsTable() > 0 then



            self:Request(kind, reason, variant, onResult, askedBy)
            return
        end
        onResult(route, err, request)
    end)
    if not ok then
        if self.inflight == entry then self.inflight = nil end
        if entry.delivered then

            if FGPS.Log then FGPS.Log:Error("Route result handling failed: %s", tostring(handle)) end
        else
            onResult(nil, { code = "NO_DATA", message = tostring(handle) })
        end
        return nil
    end
    entry.handle = handle
    return handle
end




local function stopIndexForLeg(route, legIndex)
    local stops = route.stops
    if type(stops) ~= "table" then
        if legIndex == #route.legs then return 1 end
        return nil
    end
    for k = 1, #stops do
        if stops[k].legTo == legIndex then return k end
    end
    return nil
end

function Navigator:PrepareRoute(route)
    lastMoveYps = nil



    local Calibrate = FGPS.Calibrate
    if Calibrate and Calibrate.ApplyToRoute then pcall(Calibrate.ApplyToRoute, route) end
    local legs = route.legs or {}
    local suffixYards, suffixSeconds = {}, {}
    local yards, seconds = 0, 0
    for i = #legs, 1, -1 do
        yards = yards + (legs[i].yards or 0)
        seconds = seconds + (legs[i].seconds or 0)
        suffixYards[i], suffixSeconds[i] = yards, seconds
    end
    self.suffixYards, self.suffixSeconds = suffixYards, suffixSeconds
    if (not route.steps or #route.steps == 0) and FGPS.Instructions and FGPS.Instructions.Build then
        pcall(FGPS.Instructions.Build, route)
    end
end

function Navigator:DropRoute()
    self.route = nil
    self.suffixYards, self.suffixSeconds = nil, nil
    self.currentStepIndex = nil
    self.departLeg = nil
end

local function initialTarget(leg)
    if not leg then return 1 end
    local n = #leg.points
    if leg.kind ~= "walk" then return n end
    return n >= 2 and 2 or 1
end

function Navigator:ResetProgress()
    local route = self.route
    local leg = route and route.legs[1]
    self.progress = {
        legIndex = 1,
        pointIndex = initialTarget(leg),
        stopIndex = 1,
        nextX = leg and leg.points[initialTarget(leg)] and leg.points[initialTarget(leg)].x or nil,
        nextY = leg and leg.points[initialTarget(leg)] and leg.points[initialTarget(leg)].y or nil,
        distToNext = nil, remainingYards = route and route.totalYards or 0, remainingSeconds = route and route.totalSeconds or 0,
        currentStep = nil, nextStep = nil, offRouteYards = 0, pos = self.lastPos, arrivedStopIndex = nil,
        legKind = leg and leg.kind or nil, state = self.state,



        nextInst = leg and leg.inst or nil, statusText = nil, statusSeconds = nil,


        alongYards = 0, positionAvailable = true,
    }
    self.statusKey = nil
    self.lastInst, self.lastX, self.lastY = nil, nil, nil
    self.currentStepIndex = nil
    self.departLeg = 1
    self.offRouteTicks = 0
    self.wrongLevelTicks = 0
    self.pendingAnnounce = false
    self.lastAlong = nil
    self.riddenLeg = nil
    self.rodePaused = nil
    self.landedAt = nil
    self.lift = nil
    self.keptAt = nil
    self.stayYards = nil


    local at, stops = self.stayedAt, route and route.stops
    local d = stops and stops[#stops] and stops[#stops].dest
    if at and not (type(d) == "table" and d.questID == at.questID and d.inst == at.inst and d.x == at.x and d.y == at.y) then
        self.stayedAt = nil
    end
    return self.progress
end




local legDepartStep

function Navigator:Announce(step, isNew)
    if not step then return end
    if self.inCombat and self:CombatPolicy() ~= "all" then
        self.pendingAnnounce = true


        if step.kind == "depart" then self.heldDepart = step end
        return
    end
    Events:Fire("NAV_INSTRUCTION", step, isNew and true or false, false)
end

function Navigator:Repeat()
    local step = self.progress and self.progress.currentStep
    if not step then return false end
    Events:Fire("NAV_INSTRUCTION", step, false, false)
    return true
end

function Navigator:OnCombat(inCombat)
    inCombat = inCombat and true or false
    if self.inCombat == inCombat then return end
    self.inCombat = inCombat
    if inCombat then return end


    local wanted = self.pendingAnnounce or self:CombatPolicy() ~= "all"
    local held = self.heldDepart
    self.pendingAnnounce, self.heldDepart = false, nil
    local p = self:IsJourney() and self.progress or nil





    local depart = held and p and self.state ~= "paused" and (p.pointIndex or 1) <= 2 and legDepartStep(self.route, p.legIndex) or nil
    if depart and depart.text == held.text then Events:Fire("NAV_INSTRUCTION", depart, true, false) end
    if wanted and p and p.currentStep then
        Events:Fire("NAV_INSTRUCTION", p.currentStep, false, true)
    end
end




local function stepsOf(route)
    return route and route.steps or nil
end



local stepQuery = { legIndex = 1, pointIndex = 1 }

local function nextActionable(route, legIndex, segIndex)
    local I = FGPS.Instructions
    if I and I.NextActionable then
        stepQuery.legIndex, stepQuery.pointIndex = legIndex, segIndex
        local ok, step = pcall(I.NextActionable, route, stepQuery)
        if ok and (step == nil or type(step) == "table") then return step end
    end
    local steps = stepsOf(route)
    if not steps then return nil end
    for i = 1, #steps do
        local s = steps[i]
        if s.legIndex > legIndex or (s.legIndex == legIndex and s.pointIndex > segIndex) then
            return s
        end
    end
    return steps[#steps]
end


function legDepartStep(route, legIndex)
    local steps = stepsOf(route)
    if not steps then return nil end
    for i = 1, #steps do
        local s = steps[i]
        if s.legIndex == legIndex then
            if s.kind == "depart" and s.pointIndex == 1 then return s end
            return nil
        elseif s.legIndex > legIndex then
            return nil
        end
    end
    return nil
end

local function stepAfter(route, step)
    local steps = stepsOf(route)
    if not steps or not step then return nil end
    local idx = step.index
    if not idx then
        for i = 1, #steps do if steps[i] == step then idx = i break end end
    end
    return idx and steps[idx + 1] or nil
end


function Navigator:Activate(route, why, keepAlternatives)
    if type(route) ~= "table" or type(route.legs) ~= "table" or #route.legs == 0 then
        reportError({ code = "NO_PATH", message = L.ROUTE_NO_PATH })
        return false
    end
    local wasJourney = self:IsJourney()
    local previous = wasJourney and self.route or nil
    if self.route ~= route then self:DropRoute() end
    self.route = route
    if not keepAlternatives then self:DropAlternatives() end
    self:PrepareRoute(route)
    self:ResetProgress()
    self.pauseReason = nil
    self.hopAsked = nil


    if self.flightsOwed ~= self.requestToken then self.flightsOwed = nil end
    if not wasJourney then
        if FGPS.Perf and FGPS.Perf.StartTripCounter then pcall(FGPS.Perf.StartTripCounter, FGPS.Perf) end
        self.tripOpen = true
        self.lastRecalcAt = nil
        self.recalcWanted = false
    end
    self:SetState("active")
    if wasJourney then
        Events:Fire("ROUTE_UPDATED", route, why or "updated")
    else
        Events:Fire("ROUTE_STARTED", route)
    end








    local steps = stepsOf(route)
    local depart
    if steps and steps[1] and steps[1].kind == "depart" then
        self.currentStepIndex = steps[1].index or 1
        local said = (why == "recalc" or why == "level") and stepsOf(previous) and stepsOf(previous)[1] or nil
        if not (said and said.kind == "depart" and said.text == steps[1].text) then depart = steps[1] end
    end
    local staying = self.stayedAt ~= nil and self.stayedAt.inside
    if depart and not staying then self:Announce(depart, true) end
    self:Tick(true)
    if depart and staying and self.route == route and self:IsJourney() and not (self.progress and self.progress.parked) then
        self:Announce(depart, true)
    end
    return true
end

function Navigator:Preview(askedBy)
    if #stopsTable() == 0 then
        FGPS:Print(L["No destination set."])
        return false
    end



    self.previewRev = nil
    self:Request("preview", "preview", self.variant, function(route, err)
        route, err = namedRoute(route, err)
        if route then
            if not self:IsJourney() then
                if self.route ~= route then self:DropRoute() end
                self.route = route
                self.previewRev = self.itineraryRev
                self:PrepareRoute(route)
                self:ResetProgress()
                self:DropAlternatives()
                self:SetState("previewing")
            end
            Events:Fire("ROUTE_PREVIEW", route, nil)
        else


            reportError(err, self.askedBy == "navigator")
            Events:Fire("ROUTE_PREVIEW", nil, nil, err)
        end
    end, askedBy)
    return true
end












function Navigator:Start(route, quiet, announced, askedBy, keepStops)
    local list = stopsTable()
    if route == nil and #list > 0 and self:IsJourney() and (self.state == "in_transit" or self.riding) then
        return self:Reroute("destination", askedBy or "player")
    end
    self.quiet = quiet == true




    if self.state == "previewing" and self.route and (route == nil or route == self.route) then
        if self.previewRev == self.itineraryRev and not (self.inflight and self.inflight.kind == "preview") then
            route = self.route
        else
            route = nil
            self:DropRoute()
            self.progress = nil
            self:SetState("idle")
        end
    end
    if route ~= nil then



        if self.inflight and self.inflight.kind ~= "alt" then self:CancelInflight() end
        return self:Activate(route, "start")
    end
    if #list == 0 then
        FGPS:Print(L["No destination set."])
        return false
    end



    if not announced then Events:Fire("DESTINATION_SET", list[#list]) end
    self:Request("start", "start", self.variant, function(r, err)
        r, err = namedRoute(r, err)
        if r then
            self:Activate(r, "start")
        else
            reportError(err, self.quiet)

            if not (self.hopAsked and self.hopAsked.told) then Events:Fire("NAV_RECALC_DONE", nil, err) end








            if self.quiet and keepStops ~= true and self.state == "idle" and not (type(err) == "table" and err.code == "CANCELLED") then
                self:Cancel("no_way")
            end
        end
    end, askedBy)
    return true
end














function Navigator:Reroute(why, askedBy)
    if not self:IsJourney() then return false end
    askedBy = askedBy or "navigator"
    if self.pendingReroute and self.pendingAskedBy == "player" then askedBy = "player" end
    if self.state == "in_transit" or self.riding then
        self.pendingReroute, self.pendingAskedBy = why or "itinerary", askedBy
        return true
    end
    self.pendingReroute = nil

    self:Request("reroute", why == "level" and "level" or "recalc", self.variant, function(route, err)
        route, err = namedRoute(route, err)
        if route then
            self:Activate(route, why or "itinerary")
        else
            reportError(err, self.quiet)
            Events:Fire("NAV_RECALC_DONE", nil, err)
            if err and (err.code == "UNREACHABLE" or err.code == "NO_PATH" or err.code == "NO_DATA") then
                self.pauseReason = err.code
                self:SetState("paused")
            end
        end
    end, askedBy)
    return true
end

function Navigator:Pause()
    if self.state ~= "active" and self.state ~= "in_transit" then return false end
    if self.state == "in_transit" then self.rodePaused = true end
    self.pauseReason = nil
    self:SetState("paused")
    return true
end

function Navigator:Resume()
    if self.state ~= "paused" then return false end
    local reason = self.pauseReason
    self.pauseReason = nil
    local list, ends = stopsTable(), self.route and self.route.stops
    local last = type(ends) == "table" and ends[#ends] or nil
    local replaced = #list > 0 and last ~= nil and not sameDest(last.dest, list[#list])
    self:SetState("active")
    if reason then


        self.lastRecalcAt = nil
        self:RequestRecalc("player")
    elseif self.flightsOwed then

        self.flightsOwed = nil
        self:Reroute("flights")
    elseif replaced and not self.pendingReroute then


        self:Reroute("destination", "player")
    else
        self:Tick(true)


        self:RecheckStay()
    end
    return true
end

function Navigator:Cancel(reason)
    reason = reason or "user"


    local hadSomething = self.route ~= nil or self.state ~= "idle" or self.inflight ~= nil
    self:CancelInflight()
    local wasJourney = self:IsJourney()
    self:DropRoute()
    self.progress = nil
    self:DropAlternatives()
    self.variant = "fastest"
    self.pauseReason = nil
    self.flightsOwed = nil
    self.quiet = false
    self.askedBy = "player"
    self.offRouteTicks = 0
    self.wrongLevelTicks = 0
    self.pendingAnnounce = false
    self.lastRecalcAt = nil
    self.recalcWanted = false
    self.riding = false
    self.pendingReroute = nil


    self.questHop = reason == "no_way" and self.hopAsked or nil
    if self.questHop then self.questHop.told = true end
    self.hopAsked = nil
    self.stayedAt = nil
    local list = stopsTable()
    local hadStops = #list > 0
    wipe(list)
    self:SetState("idle")
    if wasJourney or self.tripOpen then
        if FGPS.Perf and FGPS.Perf.EndTrip then pcall(FGPS.Perf.EndTrip, FGPS.Perf) end
        self.tripOpen = false
    end
    if hadStops then fireItinerary("cancelled") end
    if hadSomething then Events:Fire("NAV_CANCELLED", reason) end
    return hadSomething
end





function Navigator:HasAnythingSet()
    return self.state ~= "idle" or self.route ~= nil or self.inflight ~= nil or #stopsTable() > 0
end













Navigator.UNDO_SECONDS = 30

local function snapshotForUndo()
    local list = stopsTable()
    if #list == 0 and not Navigator.route then return nil end
    local stops = {}
    for i = 1, #list do
        stops[i] = Util.DeepCopy(list[i])
    end
    return {
        stops = stops,
        variant = Navigator.variant,
        savedAt = (GetTime and GetTime()) or 0,
    }
end

function Navigator:Clear(reason, opts)
    reason = reason or "user"
    local hadLooseEnds = self.inflight ~= nil or #stopsTable() > 0
    local snap = snapshotForUndo()
    local cancelled = self:Cancel(reason)
    if not cancelled and not hadLooseEnds then return false end
    if not cancelled then Events:Fire("NAV_CANCELLED", reason) end
    if snap then self.undo = snap end
    if not (type(opts) == "table" and opts.quiet == true) then
        FGPS:Print(L["Cleared. No route and no stops are set. Undo for %d seconds (/cabbie undo)."], Navigator.UNDO_SECONDS)
    end
    return true
end




function Navigator:UndoClear(opts)
    local quiet = type(opts) == "table" and opts.quiet == true
    local snap = self.undo
    if type(snap) ~= "table" or type(snap.stops) ~= "table" or #snap.stops == 0 then
        return false, "nothing"
    end
    local now = (GetTime and GetTime()) or 0
    if (now - (snap.savedAt or 0)) > (self.UNDO_SECONDS or 30) then
        self.undo = nil
        return false, "expired"
    end
    self.undo = nil
    local list = stopsTable()
    wipe(list)
    for i = 1, #snap.stops do
        list[i] = snap.stops[i]
    end
    if snap.variant then self.variant = snap.variant end
    fireItinerary("undo")
    if not quiet then FGPS:Print(L["Restored the cleared route."]) end
    if self.Start then self:Start(nil, quiet) end
    return true
end









function Navigator:DropAlternatives()
    self.alternatives, self.alternativesAt = nil, nil
    self.altToken = self.altToken + 1
    local handle = self.altHandle
    self.altHandle = nil
    if handle then
        local Router = FGPS.Router
        if Router and Router.Cancel then pcall(Router.Cancel, Router, handle) end
    end
end

function Navigator:RequestAlternatives(cb)
    cb = cb or function() end
    if self.alternatives and self.alternativesAt and now() - self.alternativesAt <= self.ALTERNATIVES_TTL then
        cb(self.alternatives)
        return true
    end
    local Router = FGPS.Router
    if not (Router and Router.Alternatives) or #stopsTable() == 0 then
        cb({})
        return false
    end
    local request = self:BuildRequest("alt", self.variant)
    if not request.origin then cb({}) return false end
    self:DropAlternatives()
    local token = self.altToken
    local finished = false
    local ok, handle = pcall(Router.Alternatives, Router, request, function(list)
        finished = true
        if token ~= self.altToken then return end
        self.altHandle = nil
        self.alternatives = type(list) == "table" and list or {}
        self.alternativesAt = now()
        cb(self.alternatives)
    end)
    if not ok then
        if FGPS.Log then FGPS.Log:Warn("Alternatives failed: %s", tostring(handle)) end
        cb({})
        return false
    end
    if not finished and token == self.altToken then self.altHandle = handle end
    return true
end

function Navigator:SwapRoute(route, why)
    if type(route) ~= "table" or type(route.legs) ~= "table" or #route.legs == 0 then
        reportError({ code = "NO_PATH", message = L.ROUTE_NO_PATH })
        return false
    end
    if self:IsJourney() then


        if self.inflight then self:CancelInflight() end
        return self:Activate(route, why, true)
    end
    if self.route ~= route then self:DropRoute() end
    self.route = route
    self.previewRev = self.itineraryRev
    self:PrepareRoute(route)
    self:ResetProgress()
    if self.state == "idle" then self:SetState("previewing") end
    Events:Fire("ROUTE_UPDATED", route, why)
    if self.state == "previewing" then Events:Fire("ROUTE_PREVIEW", route, self.alternatives) end
    return true
end



function Navigator:SelectAlternative(variant)
    if type(variant) ~= "string" then return false end
    if self.alternatives then
        for _, route in ipairs(self.alternatives) do
            if route.variant == variant then
                self.variant = variant
                return self:SwapRoute(route, "alternative")
            end
        end
    end
    if #stopsTable() == 0 then return false end
    self:Request("alt", "alt", variant, function(route, err)
        route, err = namedRoute(route, err)
        if route then
            self.variant = variant
            self:SwapRoute(route, "alternative")
        else
            reportError(err)
        end
    end)
    return true
end



local NAVIGATOR_ONLY_KEYS = {
    ["routing.arrivalRadius"] = true, ["routing.offRouteYards"] = true, ["routing.recalcMinSeconds"] = true,
}

function Navigator:OnSettingsChanged(key)
    if type(key) ~= "string" or NAVIGATOR_ONLY_KEYS[key] then return false end
    if key ~= "*" and key:sub(1, 10) ~= "transports" and key:sub(1, 7) ~= "routing" then return false end
    self:DropAlternatives()
    if self:IsJourney() then
        self:Reroute("settings")
    elseif self.state == "previewing" then
        self:Preview("navigator")
    end
    return true
end












function Navigator:OnFlightsKnown()
    self:DropAlternatives()
    if self.state == "paused" and not self.pauseReason then
        self.flightsOwed = self.inflight and self.inflight.token or true
    elseif self:IsJourney() then
        self:Reroute("flights")
    end
end







function Navigator:RecalcAllowed()
    local minSeconds = setting("routing.recalcMinSeconds", Const.RECALC_MIN_SECONDS or 5)
    local since = self.lastRecalcAt and now() - self.lastRecalcAt
    if since and since < minSeconds then return false end
    local kept, pos = self.keptAt, self.lastPos
    if kept and since and since < self.KEPT_RETRY_SECONDS and pos and pos.inst == kept.inst
            and dist(pos.x, pos.y, kept.x, kept.y) < self.KEPT_RETRY_YARDS then
        return false
    end
    return true
end
















function Navigator:RequestRecalc(askedBy)
    if self.state ~= "active" then return false end
    if self.riding then return self:Reroute(self.pendingReroute or "recalc", askedBy) end
    if onTaxi() then return false end
    if not self:RecalcAllowed() then
        self.recalcWanted = true
        return false
    end
    self.lastRecalcAt = now()
    self.recalcWanted = false
    Events:Fire("NAV_RECALC_START", "recalc")
    self:Request("recalc", "recalc", self.variant, function(route, err, request)









        local current = self.route
        local list = stopsTable()
        local real = current ~= nil and not straightFallback(current)
            and type(current.stops) == "table" and #current.stops > 0
            and sameDest(current.stops[#current.stops].dest, list[#list])
        local refused = not route and type(err) == "table" and err.code == "NO_PATH" and err.reason == "FALLBACK_CAPPED"
        if real and (straightFallback(route) or refused) then
            if FGPS.Log then FGPS.Log:Info("Recalculation kept the current route (%s)", route and "straight fallback" or "fallback refused") end
            local from = request and request.origin or self.lastPos
            self.keptAt = from and { inst = from.inst, x = from.x, y = from.y } or nil
            Events:Fire("NAV_RECALC_DONE", current, nil, "kept")
            return
        end
        route, err = namedRoute(route, err)
        if route then
            self:Activate(route, "recalc")
            Events:Fire("NAV_RECALC_DONE", route, nil)
        else
            Events:Fire("NAV_RECALC_DONE", nil, err)
            if err and err.code == "CANCELLED" then return end
            if err and (err.code == "UNREACHABLE" or err.code == "NO_PATH" or err.code == "NO_DATA") then
                reportError(err, self.quiet)
                self.pauseReason = err.code
                self:SetState("paused")
            end
        end
    end, askedBy or "navigator")
    return true
end




function Navigator:ArriveRadius(isFinal, dest)
    local radius = isFinal and setting("routing.arrivalRadius", Const.ARRIVE_YARDS or 10)
        or (Const.INTERMEDIATE_ARRIVE_YARDS or 15)

    local area = type(dest) == "table" and tonumber(dest.areaRadius)
    if area and area > radius then radius = area end
    return radius
end









function Navigator:OffRouteThreshold(leg, segIndex)
    local yards = setting("routing.offRouteYards", Const.OFFROUTE_YARDS or 40)
    if isMounted() then yards = yards * 1.5 end
    local pts = leg and leg.points
    local a, b = pts and segIndex and pts[segIndex], pts and segIndex and pts[segIndex + 1]
    if not (a and b and GUESSED_KINDS[b.k]) then return yards, false end
    local band = (Const.OFFROUTE_GUESS_SHARE or 0.15) * dist(a.x, a.y, b.x, b.y)
    local cap = Const.OFFROUTE_GUESS_MAX_YARDS or 150
    if band > cap then band = cap end
    if band > yards then yards = band end
    return yards, true
end








local STATUS_RIDE, STATUS_WAIT, STATUS_WRONG = 1, 2, 3
local STATUS_BUILDERS = { [STATUS_RIDE] = "RideText", [STATUS_WAIT] = "WaitText", [STATUS_WRONG] = "WrongRideText" }
Navigator.STATUS_STEP_SECONDS = 10

function Navigator:UpdateStatus(p, leg, pos, legSeconds, crossed)
    local I = FGPS.Instructions
    local T = FGPS.Transport
    local mode, seconds
    if I and leg.kind ~= "walk" then
        local ride = T and T.State and T.State() or nil
        if self.riding and ride and ride.unknown then
            mode = STATUS_WRONG
        elseif self.riding or crossed then
            mode, seconds = STATUS_RIDE, legSeconds
        elseif T and T.NextDeparture and T.dock and T.dock.legIndex == p.legIndex and leg.transportID then

            seconds = T.NextDeparture(leg.transportID, T.dock.stopIndex)
            if seconds then mode = STATUS_WAIT end
        end
    end
    local builder = mode and I[STATUS_BUILDERS[mode]] or nil
    if not builder then
        p.statusText, p.statusSeconds, self.statusKey = nil, nil, nil
        return
    end
    local step = self.STATUS_STEP_SECONDS
    local bucket = type(seconds) == "number" and floor(seconds / step + 0.5) or 0
    local key = p.legIndex * 1e6 + mode * 1e5 + bucket
    if key == self.statusKey then return end
    self.statusKey = key
    local shown = type(seconds) == "number" and bucket * step or nil
    local ok, text = pcall(builder, leg, shown)
    p.statusSeconds = shown
    p.statusText = ok and type(text) == "string" and text or nil
end


function Navigator:UpdateProgress(pos)
    local route, p = self.route, self.progress
    if not route or not p then return end
    local leg = route.legs[p.legIndex]
    if not leg then return end
    local pts = leg.points
    local onRide = leg.kind ~= "walk" and (self.state == "in_transit" or self.riding or self.riddenLeg == p.legIndex)
    if leg.kind ~= "walk" and #pts > 0 then
        p.pointIndex = transportTarget(leg, pos, onRide)
    end
    local target = p.pointIndex
    if target > #pts then target = #pts end
    local tp = pts[target]
    local crossing = crossesInstances(leg)





    local targetInst = leg.inst
    if crossing and target > departureCount(leg) then
        targetInst = leg.toInst
        local wayOut = departureCount(leg)
        if pos and pos.inst == leg.inst and wayOut >= 2 then tp, targetInst = pts[wayOut], leg.inst end
    end
    p.pos = pos
    p.state = self.state
    p.legKind = leg.kind
    p.nextX, p.nextY, p.nextInst = tp and tp.x or nil, tp and tp.y or nil, targetInst
    if tp and pos and pos.inst == targetInst and not (crossing and pos.inst ~= leg.toInst) then
        p.distToNext = dist(pos.x, pos.y, tp.x, tp.y)
    else

        p.distToNext = nil
    end
    local R = FGPS.Route
    local x, y = pos and pos.x or (tp and tp.x) or 0, pos and pos.y or (tp and tp.y) or 0
    if pos and pos.inst ~= leg.inst then x, y = pts[1].x, pts[1].y end

    local segIndex = target > 1 and target - 1 or 1
    local remainingYards, remainingSeconds
    local share = crossing and pos and crossingShareAhead(leg, pos) or nil
    if share then



        local laterYards = (self.suffixYards or {})[p.legIndex + 1] or 0
        local laterSeconds = (self.suffixSeconds or {})[p.legIndex + 1] or 0
        local waiting = (not self.riding and pos.inst == leg.inst) and ((leg.seconds or 0) - rideSeconds(leg)) or 0
        remainingYards = (leg.yards or 0) * share + laterYards
        remainingSeconds = rideSeconds(leg) * share + waiting + laterSeconds
    end
    if not share and R and R.RemainingYards then
        local ok, v = pcall(R.RemainingYards, route, p.legIndex, segIndex, x, y)
        if ok and type(v) == "number" then remainingYards = v end
    end
    if not share and R and R.RemainingSeconds then
        local ok, v = pcall(R.RemainingSeconds, route, p.legIndex, segIndex, x, y)
        if ok and type(v) == "number" then remainingSeconds = v end
    end
    if not remainingYards or not remainingSeconds then
        local legRemaining, total = remainingYardsLocal(route, p.legIndex, segIndex, x, y, self.suffixYards or {})
        remainingYards = remainingYards or total
        if not remainingSeconds then
            local legSeconds = (leg.yards and leg.yards > 0) and (leg.seconds or 0) * (legRemaining / leg.yards) or (leg.seconds or 0)
            remainingSeconds = legSeconds + ((self.suffixSeconds or {})[p.legIndex + 1] or 0)
        end
    end



    if not share and onRide and (leg.seconds or 0) > 0 then
        local later = (self.suffixSeconds or {})[p.legIndex + 1] or 0
        remainingSeconds = later + (remainingSeconds - later) * rideSeconds(leg) / leg.seconds
    end
    p.remainingYards, p.remainingSeconds = remainingYards, remainingSeconds





    local stepSeg = segIndex
    local crossed = crossing and pos ~= nil and pos.inst == leg.toInst
    if leg.kind ~= "walk" and not self.riding and not crossed then
        stepSeg = 0
    elseif leg.kind == "walk" and #pts >= 2 then
        stepSeg = alongSegment(leg, p.alongYards)
    end
    local step = nextActionable(route, p.legIndex, stepSeg)
    p.currentStep = step
    p.nextStep = stepAfter(route, step)
    self:UpdateStatus(p, leg, pos, remainingSeconds - ((self.suffixSeconds or {})[p.legIndex + 1] or 0), crossed)
    local live = liveWalkDelta(route, p.legIndex, segIndex, x, y)
    if type(live) == "number" then p.remainingSeconds = (p.remainingSeconds or 0) + live end
    Events:Fire("ROUTE_PROGRESS", p)
    if self.state ~= "active" then return end
    if self.departLeg ~= p.legIndex then



        self.departLeg = p.legIndex
        local depart = legDepartStep(route, p.legIndex)
        if depart and depart.index ~= self.currentStepIndex then self:Announce(depart, true) end
    end
    if step and step.index ~= self.currentStepIndex then
        self.currentStepIndex = step.index
        self:Announce(step, true)
    end
end






local function questHold(dest)
    local Quests = FGPS.Quests
    if not (Quests and Quests.StaysAt) then return nil end
    local ok, yards = pcall(Quests.StaysAt, dest)
    if ok then
        Navigator.holdError = nil
        if type(yards) == "number" and yards > 0 then return yards end
    elseif Navigator.holdError ~= tostring(yards) then
        Navigator.holdError = tostring(yards)
        if FGPS.Log then FGPS.Log:Error("Navigator: the quest module could not say whether the route stays: %s", Navigator.holdError) end
    end
    return nil
end





local function stayCircle(route)
    local stops = route.stops
    local dest = stops and stops[#stops] and stops[#stops].dest
    if type(dest) ~= "table" or (tonumber(dest.areaRadius) or 0) > 0 then return false end
    local yards = questHold(dest)
    return yards ~= nil and yards < math.huge and yards or false
end


function Navigator:CompleteLeg(legIndex, pos)
    local route, p = self.route, self.progress
    local stopIdx = stopIndexForLeg(route, legIndex)
    if stopIdx then
        local stop = route.stops and route.stops[stopIdx]
        local dest = stop and stop.dest
        local isFinal = (route.stops == nil) or stopIdx >= #route.stops
        if isFinal and p.parked then return true end




        if isFinal and type(dest) == "table" and (self.inflight or self.pendingReroute) then
            local list = stopsTable()
            if #list > 0 and not sameDest(list[#list], dest) then return true end
        end




        local park = isFinal and type(dest) == "table" and type(dest.areaRadius) == "number" and dest.areaRadius > 0
        local hold = isFinal and not park and questHold(dest) or nil
        park = park or hold ~= nil


        if hold and self.stayedAt and self.stayedAt.inside then
            p.parked, p.holdYards, p.arrivedStopIndex = true, hold, stopIdx
            return true
        end
        if dest and not p.parked then
            local D = FGPS.Destinations



            local gone = dest.type == "corpse" or dest.type == "player" or (dest.type == "graveyard" and dest.kind == "custom")
            if D and D.AddRecent and not gone then D.AddRecent(dest) end



            if not self.quiet then FGPS:Print(L.ARRIVED_AT, describe(dest)) end
        end
        p.arrivedStopIndex = stopIdx
        Events:Fire("NAV_ARRIVED", stopIdx, isFinal and not park)
        if park then
            p.parked, p.holdYards = true, hold
            if hold then self.stayedAt = { questID = dest.questID, inst = dest.inst, x = dest.x, y = dest.y, inside = true } end
            return true
        end
        if isFinal then
            self:Finish()
            self:NoteQuestHop(dest)
            return true
        end



        local list = stopsTable()
        local at
        if dest then
            for i = 1, #list do
                if sameDest(list[i], dest) then at = i break end
            end
        elseif list[1] then
            at = 1
        end
        if at then
            table.remove(list, at)
            fireItinerary("arrived")
        end
        p.stopIndex = stopIdx + 1
    end
    if legIndex >= #route.legs then
        self:Finish()
        return true
    end



    local done = route.legs[legIndex]
    if done and done.kind ~= "walk" and not TELEPORT_KINDS[done.kind] and #done.points > 0 then
        local last = done.points[#done.points]
        local inst = arrivalInst(done)
        local d = (pos and pos.inst == inst) and dist(pos.x, pos.y, last.x, last.y) or nil
        self.landedAt = { inst = inst, x = last.x, y = last.y, d = d }
    else
        self.landedAt = nil
    end
    p.legIndex = legIndex + 1
    p.pointIndex = initialTarget(route.legs[p.legIndex])
    p.alongYards, self.lastAlong = 0, nil
    self.offRouteTicks = 0
    return false
end














function Navigator:RecheckStay()

    self.stayYards = nil
    local p, route = self.progress, self.route
    if self.state ~= "active" or not (p and p.parked and p.holdYards and route and route.stops)
        or self.inflight or self.pendingReroute then return false end
    local last = #route.stops
    local stop = route.stops[last]
    if questHold(stop and stop.dest) then return false end
    p.parked, p.holdYards = nil, nil
    local Quests = FGPS.Quests
    if Quests and Quests.FollowsMine and Quests.FollowsMine() then return false end
    Events:Fire("NAV_ARRIVED", last, true)
    self:Finish()
    return true
end







function Navigator:NoteQuestHop(dest)
    self.questHop = nil
    if type(dest) ~= "table" or dest.kind ~= "quest" or dest.source ~= "nextWaypoint" or not dest.questID then return false end
    self.questHop = { questID = dest.questID, inst = dest.inst, x = dest.x, y = dest.y, at = now() }
    return self:ContinueQuestHop()
end

function Navigator:ContinueQuestHop()
    local hop = self.questHop
    if not hop then return false end
    if self.state ~= "idle" or now() - hop.at > self.QUEST_HOP_SECONDS then
        self.questHop = nil
        return false
    end
    hop.air = nil
    local Quests = FGPS.Quests
    if not (Quests and Quests.DestinationFor) then return false end
    if Quests.Refresh then pcall(Quests.Refresh) end
    local ok, dest = pcall(Quests.DestinationFor, hop.questID)
    if not ok or type(dest) ~= "table" or not dest.x or not dest.y then return false end
    if dest.inst == hop.inst and hop.x and hop.y and dist(dest.x, dest.y, hop.x, hop.y) <= self:ArriveRadius(true) then
        return false
    end



    if onTaxi() then hop.air = true return false end
    if not playerPos() then return false end
    self.questHop = nil


    self.hopAsked = hop

    return self:SetDestination(dest, { start = true, quiet = true, askedBy = "navigator" }) ~= nil
end


function Navigator:Finish()
    self:CancelInflight()

    self.quiet = false
    if self.progress then self.progress.arrivedStopIndex = nil end
    self:SetState("arrived")
    local list = stopsTable()
    if #list > 0 then
        wipe(list)
        fireItinerary("arrived")
    end
    self:DropRoute()
    self.progress = nil
    self:DropAlternatives()
    self.variant = "fastest"
    self.offRouteTicks = 0
    self.pendingAnnounce = false
    self.riding = false
    self.pendingReroute = nil
    self.stayedAt = nil
    if self.tripOpen and FGPS.Perf and FGPS.Perf.EndTrip then pcall(FGPS.Perf.EndTrip, FGPS.Perf) end
    self.tripOpen = false
    self:SetState("idle")
end




local function passesStop(route, from, to, ridden)
    for li = from, to - 1 do
        if stopIndexForLeg(route, li) and li ~= ridden and li + 1 ~= ridden then return true end
    end
    return false
end
















function Navigator:Resync(pos)
    local route, p = self.route, self.progress
    if not route or not p or not pos then return false end
    local bestLeg, bestIdx, bestD, bestAlong
    for li = p.legIndex, #route.legs do
        local leg = route.legs[li]



        if leg.inst == pos.inst and #leg.points > 0 and not crossesInstances(leg) then
            if leg.kind == "walk" then
                local i, _, d, along = project(leg, pos.x, pos.y)
                if i and d and (not bestD or d <= bestD) then

                    local target = i + 1
                    if target > #leg.points then target = #leg.points end
                    if li == p.legIndex and target < p.pointIndex then target = p.pointIndex end
                    bestLeg, bestIdx, bestD, bestAlong = li, target, d, along
                end
            else
                local last = leg.points[#leg.points]
                local d = dist(pos.x, pos.y, last.x, last.y)
                if not bestD or d <= bestD then bestLeg, bestIdx, bestD, bestAlong = li, #leg.points, d, nil end
            end
        end
        if leg.kind == "elevator" or passesStop(route, li, li + 1, self.riddenLeg) then break end
    end
    if not bestLeg or bestD > self.RESYNC_MAX_YARDS then return false end
    if bestLeg > p.legIndex then

        while p.legIndex < bestLeg do
            if self:CompleteLeg(p.legIndex, pos) then return true end
        end
        p.pointIndex = bestIdx
    elseif bestIdx > p.pointIndex then
        p.pointIndex = bestIdx
    end
    if bestAlong and bestAlong > (p.alongYards or 0) then p.alongYards = bestAlong end

    p.match = nil
    return true
end




function Navigator:NoteOffRoute(yards)



    local T = FGPS.Transport
    if T and T.suspectSince then
        self.offRouteTicks = 0
        return
    end
    self.offRouteTicks = self.offRouteTicks + 1
    if self.progress then self.progress.offRouteYards = yards end
    local needed = Const.OFFROUTE_TICKS or 3
    if self.offRouteTicks == needed then
        Events:Fire("NAV_OFF_ROUTE", yards)
        self:RequestRecalc()
    elseif self.offRouteTicks > needed and (self.recalcWanted or not self.inflight) then
        self:RequestRecalc()
    end
end


local before = { inst = nil, x = nil, y = nil }









function Navigator:Teleported(leg, pos)
    if not TELEPORT_KINDS[leg.kind] or before.inst == nil or pos.inst ~= arrivalInst(leg) then return false end
    local Social = FGPS.Social
    if Social and Social.IsDead and Social.IsDead() then return false end
    local last = leg.points[#leg.points]
    if dist(pos.x, pos.y, last.x, last.y) > self.RESYNC_MAX_YARDS then return false end
    if before.inst ~= pos.inst then return true end
    return dist(before.x, before.y, pos.x, pos.y) > self.TELEPORT_JUMP_YARDS
        and dist(pos.x, pos.y, last.x, last.y) < dist(before.x, before.y, last.x, last.y)
end









function Navigator:AtLandingStop(pos)
    local stop = self.landedAt
    if not stop or stop.inst ~= pos.inst then return false end
    local d = dist(pos.x, pos.y, stop.x, stop.y)
    if d > self.TRANSPORT_ARRIVE_YARDS and stop.min ~= nil and d > stop.min + self.TRANSPORT_ARRIVE_YARDS then
        self.landedAt = nil
        return false
    end
    local closer = stop.d ~= nil and d < stop.d - self.PROGRESS_YARDS
    stop.d = d
    if not stop.min or d < stop.min then stop.min = d end
    return d <= self.TRANSPORT_ARRIVE_YARDS or closer
end


local function legStepOfKind(route, legIndex, kind)
    local steps = stepsOf(route)
    if not steps then return nil end
    for i = 1, #steps do
        local s = steps[i]
        if s.legIndex == legIndex and s.kind == kind then return s end
        if s.legIndex > legIndex then return nil end
    end
    return nil
end











function Navigator:HoldLift(leg, pos)
    local route, p = self.route, self.progress
    local shaft = leg.points[1]
    p.pointIndex = #leg.points
    local away = dist(pos.x, pos.y, shaft.x, shaft.y)
    local inShaft = away <= self.LIFT_YARDS
    local lift = self.lift
    if lift and lift.legIndex ~= p.legIndex then lift = nil end
    if not lift and inShaft then lift = { legIndex = p.legIndex, at = now() } end




    local moved = false
    if lift and pos.map ~= nil then
        if not lift.settled then
            lift.settled = lift.map == pos.map
            lift.map = pos.map
        elseif pos.map == lift.map then
            lift.next = nil
        elseif lift.next == pos.map then
            moved = true
        else
            lift.next = pos.map
        end
    end
    local seconds = rideSeconds(leg)
    if seconds <= 0 then seconds = Const.ELEVATOR_SECONDS or 20 end
    local ridden = lift ~= nil and (moved or (not inShaft and now() - lift.at >= seconds))
    if not ridden and not inShaft then lift = nil end
    self.lift = lift
    if ridden then
        self.lift = nil
        self.offRouteTicks, p.offRouteYards = 0, 0
        local leave = legStepOfKind(route, p.legIndex, "disembark")
        if leave then
            self.currentStepIndex = leave.index
            self:Announce(leave, true)
        end
        self:CompleteLeg(p.legIndex, pos)
    elseif away > self.TRANSPORT_DEPART_YARDS then
        self:NoteOffRoute(away)
    else
        self.offRouteTicks, p.offRouteYards = 0, 0
    end
end


function Navigator:Advance(pos)
    local route, p = self.route, self.progress
    local leg = route.legs[p.legIndex]
    if not leg then return end













    if leg.kind ~= "walk" and leg.kind ~= "elevator" and #leg.points > 0 and pos.inst == arrivalInst(leg) then
        local first, last = leg.points[1], leg.points[#leg.points]
        local d = dist(pos.x, pos.y, last.x, last.y)
        local crossed = arrivalInst(leg) ~= leg.inst or d < dist(pos.x, pos.y, first.x, first.y)
        p.pointIndex = #leg.points
        if (d <= self.TRANSPORT_ARRIVE_YARDS and crossed) or self:Teleported(leg, pos)
                or (self.riddenLeg == p.legIndex and d <= self.RESYNC_MAX_YARDS) then
            self.offRouteTicks = 0
            p.offRouteYards = 0
            self:CompleteLeg(p.legIndex, pos)
            return
        end
    end
    if leg.inst ~= pos.inst then
        self:Resync(pos)
        leg = route.legs[p.legIndex]
        if not leg or leg.inst ~= pos.inst then





            if self:CanRouteFrom(route, p, pos) then
                self:NoteOffRoute(nil)
            else
                self.offRouteTicks = 0
            end
            return
        end
    end
    local pts = leg.points
    local n = #pts
    if TELEPORT_KINDS[leg.kind] then




        p.pointIndex = n
        self.offRouteTicks = 0
        p.offRouteYards = 0
        local nextLeg = route.legs[p.legIndex + 1]
        if nextLeg and nextLeg.kind == "walk" and nextLeg.inst == pos.inst and #nextLeg.points >= 2 then
            local i, _, d = project(nextLeg, pos.x, pos.y)
            if d and d <= self:OffRouteThreshold(nextLeg, i) then self:CompleteLeg(p.legIndex, pos) end
        end
        return
    end
    if leg.kind == "elevator" then
        self:HoldLift(leg, pos)
        return
    end
    if leg.kind ~= "walk" then

        local first = pts[1]
        p.pointIndex = n










        local T = FGPS.Transport
        local boarding = T ~= nil and T.dock ~= nil and T.dock.legIndex == p.legIndex
        local away = dist(pos.x, pos.y, first.x, first.y)
        if away > self.TRANSPORT_DEPART_YARDS and not boarding then
            self:NoteOffRoute(away)
        else
            self.offRouteTicks = 0
            p.offRouteYards = 0
        end
        return
    end










    local lastLeg = p.legIndex == #route.legs
    if lastLeg and self.stayYards == nil and not p.parked then self.stayYards = stayCircle(route) end
    local stay = self.stayedAt
    local circle = p.holdYards and p.holdYards + self.STAY_LEAVE_YARDS or (lastLeg and self.stayYards)
    if circle and not p.parked and not stay and circle > self.STAY_FIRST_YARDS then circle = self.STAY_FIRST_YARDS end

    if circle and not p.parked and stay and stay.inside then circle = circle + self.STAY_LEAVE_YARDS end
    if circle then
        if dist(pos.x, pos.y, pts[n].x, pts[n].y) <= circle then
            self.offRouteTicks, p.offRouteYards = 0, 0
            if not p.parked then self:CompleteLeg(p.legIndex, pos) end
            return
        end
        p.parked, p.holdYards = nil, nil
        if stay then stay.inside = nil end
    end



    local held, heldGuessed = self:OffRouteThreshold(leg, p.pointIndex > 1 and p.pointIndex - 1 or 1)
    if heldGuessed then held = self.FOLLOW_BAND_FACTOR * held end
    local segIndex, _, perp, along = projectNear(leg, pos.x, pos.y, p.pointIndex, p.alongYards, held)
    segIndex, perp, along = keepContinuous(self, leg, pos, segIndex, perp, along, held)
    local threshold, guessed = self:OffRouteThreshold(leg, segIndex)
    local onRoute = perp ~= nil and perp <= threshold





    local lastAlong = self.lastAlong
    self.lastAlong = along
    local advancing = guessed and perp ~= nil and perp <= self.FOLLOW_BAND_FACTOR * threshold
        and along ~= nil and lastAlong ~= nil and along > lastAlong + self.PROGRESS_YARDS
    local following = onRoute or advancing
    if following and along and along > (p.alongYards or 0) then p.alongYards = along end
    local landing = self:AtLandingStop(pos)
    local target = p.pointIndex
    if target < 1 then target = 1 end
    while target <= n do
        local pt = pts[target]
        local isLegEnd = target == n
        local radius
        if isLegEnd then
            local stopIdx = stopIndexForLeg(route, p.legIndex)
            local isFinal = stopIdx ~= nil and ((route.stops == nil) or stopIdx >= #route.stops)
            local stop = stopIdx and route.stops and route.stops[stopIdx]
            radius = stopIdx and self:ArriveRadius(isFinal, stop and stop.dest) or (Const.INTERMEDIATE_ARRIVE_YARDS or 15)
        else
            radius = Const.INTERMEDIATE_ARRIVE_YARDS or 15
        end
        local d = dist(pos.x, pos.y, pt.x, pt.y)



        local pointAlong = cumulative(leg)[target] or 0
        local alongOk = along ~= nil and pointAlong <= along + radius
        local passed = (not isLegEnd) and following and alongOk and segIndex ~= nil and segIndex >= target
        if (d <= radius and alongOk) or passed then
            if isLegEnd then
                if self:CompleteLeg(p.legIndex, pos) then return end

                self.offRouteTicks = 0
                return
            end
            target = target + 1
        else
            break
        end
    end
    p.pointIndex = target
    if following or perp == nil or landing then
        self.offRouteTicks = 0
        p.offRouteYards = perp or 0
        if self.recalcWanted then self.recalcWanted = false end
    else
        self:NoteOffRoute(perp)
    end
end


local RIDE_KINDS = { boat = true, zeppelin = true, tram = true, elevator = true, ferry = true }





local function transportLegAhead(route, fromIndex)
    for li = fromIndex, #route.legs do
        local leg = route.legs[li]
        if leg.kind ~= "walk" then
            if RIDE_KINDS[leg.kind] then return leg, li end
            return nil
        end
    end
    return nil
end







function Navigator:CanRouteFrom(route, p, pos)
    local leg = transportLegAhead(route, p.legIndex)
    if leg and leg.kind == "tram" and pos.inst ~= leg.inst and pos.inst ~= arrivalInst(leg) then return false end
    local G = FGPS.Graph
    if G and G.HasData then
        local ok, has = pcall(G.HasData, G, pos.inst)
        if ok and not has then return false end
    end
    return true
end






















function Navigator:NoteCrossing(pos)
    local previous = self.lastInst
    before.inst, before.x, before.y = previous, self.lastX, self.lastY
    self.lastInst, self.lastX, self.lastY = pos.inst, pos.x, pos.y
    if previous == nil or previous == pos.inst then return false end
    local route, p = self.route, self.progress
    local leg, index = transportLegAhead(route, p.legIndex)
    if not leg or leg.inst ~= previous or leg.toInst ~= pos.inst then return false end
    if passesStop(route, p.legIndex, index, index) then return false end
    local T = FGPS.Transport
    local riding = T and T.State and T.State().onTransport == true
    if not riding and T and T.OnThePath and not (T.OnThePath(leg, before) and T.OnThePath(leg, pos)) then return false end
    while p.legIndex < index do
        if self:CompleteLeg(p.legIndex, pos) then return true end
    end
    p.pointIndex = #leg.points
    self.riddenLeg = index
    self.offRouteTicks = 0
    if T and T.ConfirmRide then pcall(T.ConfirmRide, leg, index) end
    return true
end








function Navigator:CatchUpWithRide(transport, pos)
    local route, p = self.route, self.progress
    local current = route.legs[p.legIndex]
    if not current or current.kind ~= "walk" then return false end
    local flight = route.legs[p.legIndex + 1]
    if onTaxi() and flight and flight.kind == "taxi" and #flight.points > 0 and flight.inst == pos.inst
            and dist(pos.x, pos.y, flight.points[1].x, flight.points[1].y) <= self.TRANSPORT_DEPART_YARDS then
        if self:CompleteLeg(p.legIndex, pos) then return true end
        p.pointIndex = #flight.points
        return true
    end
    if not (transport and transport.onTransport) or transport.transportID == nil then return false end
    local leg, index = transportLegAhead(route, p.legIndex)
    if not leg or leg.transportID ~= transport.transportID then return false end
    if passesStop(route, p.legIndex, index, index) then return false end
    while p.legIndex < index do
        if self:CompleteLeg(p.legIndex, pos) then return true end
    end
    p.pointIndex = #leg.points
    return true
end






function Navigator:NoteRide(transport)
    local route, p = self.route, self.progress
    local index = p.legIndex
    local leg = route.legs[index]
    local taxi = onTaxi()
    if taxi and leg and leg.kind == "walk" and route.legs[index + 1] and route.legs[index + 1].kind == "taxi" then
        index, leg = index + 1, route.legs[index + 1]
    end
    if not leg or leg.kind == "walk" then return end
    if not taxi and transport and transport.unknown then
        if self.riddenLeg == index then self.riddenLeg = nil end
    elseif (taxi and leg.kind == "taxi") or (transport and transport.onTransport
            and transport.transportID ~= nil and transport.transportID == leg.transportID) then
        self.riddenLeg = index
    end
end


local function roomNearby(self, leg, idx, name)
    local pts, cum = leg.points, cumulative(leg)
    local here, reach = cum[idx] or 0, self.WRONG_LEVEL_ROOM_YARDS
    for j = idx, 1, -1 do
        if here - (cum[j] or 0) > reach then break end
        if pts[j].room == name then return true end
    end
    for j = idx + 1, #pts do
        if (cum[j] or 0) - here > reach then break end
        if pts[j].room == name then return true end
    end
    return false
end








local function noteLevel(self, pos)
    local pt, idx, leg = matchedPoint(self)
    if not pt or leg.kind ~= "walk" then
        self.wrongLevelTicks = 0
        return
    end
    local place = self.place

    if type(pt.z) == "number" and self.offRouteTicks == 0 then
        place.z, place.at, place.x, place.y, place.inst = pt.z, now(), pos.x, pos.y, pos.inst
    end
    if not (pt.stacked and place.name) or roomNearby(self, leg, idx, place.name) then
        self.wrongLevelTicks = 0
        return
    end
    self.wrongLevelTicks = self.wrongLevelTicks + 1
    if self.wrongLevelTicks < self.WRONG_LEVEL_TICKS then return end
    self.wrongLevelTicks = 0
    if self.inflight or not self:RecalcAllowed() then return end
    self.lastRecalcAt = now()
    self:Reroute("level")
end


function Navigator:Tick(force)
    local state = self.state
    if state == "idle" or state == "arrived" then return end
    local pos = playerPos()
    local p = self.progress
    if not pos then


        if p and p.positionAvailable ~= false then
            p.positionAvailable = false
            Events:Fire("ROUTE_PROGRESS", p)
        end
        return
    end
    if p then p.positionAvailable = true end
    self.lastPos = pos


    if state ~= "previewing" and self.route and self.progress then
        self:NoteCrossing(pos)
        if not self.route then return end
    end
    Events:Fire("POSITION_UPDATE", pos)
    if state == "previewing" then return end
    local route = self.route
    if not route or not self.progress then return end
    local transport = FGPS.Transport and FGPS.Transport.State and FGPS.Transport.State() or nil
    local inTransit = onTaxi() or (transport ~= nil and transport.onTransport == true)
    self.riding = inTransit and true or false
    if inTransit then
        self:CatchUpWithRide(transport, pos)
        if not self.route then return end
    end
    if inTransit then
        self:NoteRide(transport)
        if state == "active" then
            self:SetState("in_transit")
            state = "in_transit"
        elseif state == "paused" then
            self.rodePaused = true
        end
    elseif state == "in_transit" or (state == "active" and self.rodePaused) then



        self.rodePaused = nil
        if state == "in_transit" then self:SetState("active") end
        state = "active"
        self.offRouteTicks = 0
        local placed = self:Resync(pos)
        if self.state ~= "active" then return end



        if not placed and not self.pendingReroute then self:RequestRecalc() end
    end




    if state == "active" and self.pendingReroute and not self.riding then
        local pending = self.pendingReroute
        self.pendingReroute = nil
        if pending == "recalc" then




            self.lastRecalcAt = nil
            self:RequestRecalc(self.pendingAskedBy)
        else
            self:Reroute(pending, self.pendingAskedBy)
        end
        if self.state ~= "active" then return end
    end
    if state == "active" then
        self:Advance(pos)
        if self.state ~= "active" and self.state ~= "paused" then return end
        if self.state == "active" and self.route and self.progress then noteLevel(self, pos) end
    end
    if self.route and self.progress then self:UpdateProgress(pos) end
end








local KEPT_POPUP = "CABBIE_KEPT_TRIP"

Navigator.CLEARED_HOLD = 6




function hideKeptPopup()
    Navigator.keptRev = nil
    if type(StaticPopup_Hide) == "function" then StaticPopup_Hide(KEPT_POPUP) end
end


local function keptStillAsked()
    local asked = Navigator.keptRev ~= nil and Navigator.keptRev == Navigator.itineraryRev
    Navigator.keptRev = nil
    return asked
end

local function ensureKeptPopup()
    if type(StaticPopupDialogs) ~= "table" then return false end
    if StaticPopupDialogs[KEPT_POPUP] then return true end
    StaticPopupDialogs[KEPT_POPUP] = {
        text = "%s",
        button1 = L["Continue"],
        button2 = L["Clear"],
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,






        noCancelOnEscape = 1,






        OnAccept = function()
            if Navigator:IsJourney() then
                keptStillAsked()
                return
            end
            local Guide = FGPS.UI and FGPS.UI.Guide
            if not keptStillAsked() or #stopsTable() == 0 then
                if #stopsTable() == 0 and Guide and Guide.Say then
                    Guide.Say(L["No destination set."], Guide.HOLD_FAILED)
                end
                return
            end
            if Navigator.Start then Navigator:Start(nil, true, nil, nil, true) end
        end,







        OnCancel = function(_, _, reason)
            if reason ~= "clicked" or not keptStillAsked() then return end
            if not (Navigator.Clear and Navigator:Clear("user", { quiet = true })) then return end
            local Guide = FGPS.UI and FGPS.UI.Guide
            if Guide and Guide.Say then
                Guide.Say((L["Cleared. No route and no stops are set. Undo for %d seconds (/cabbie undo)."]):format(Navigator.UNDO_SECONDS),
                    Navigator.CLEARED_HOLD)
            end
        end,
    }
    return true
end

function Navigator:AnnounceKeptItinerary()
    if self.keptItineraryChecked then return false end
    self.keptItineraryChecked = true
    local count = #stopsTable()
    if count == 0 or self.state ~= "idle" then return false end




    self.keptRev = self.itineraryRev
    local shown = ensureKeptPopup() and type(StaticPopup_Show) == "function"
        and StaticPopup_Show(KEPT_POPUP, (L["Your route from last time is still set (%d stop(s)). Continue or clear?"]):format(count))
    if not shown then
        FGPS:Print(L["Your stops from last time are still set (%d stop(s)). Type /cabbie start to continue or /cabbie cancel to clear them."], count)
    end
    Events:Fire("KEPT_ITINERARY", count)
    return true
end

function Navigator:Init()
    if self.initialised then return end
    self.initialised = true
    stopsTable()
    if FGPS.Slash and FGPS.Slash.Register then
        FGPS.Slash.Register("undo", function()
            local ok, why = Navigator:UndoClear()
            if not ok then
                if why == "expired" then
                    FGPS:Print(L["Nothing to undo (the clear is older than 30 seconds)."])
                else
                    FGPS:Print(L["Nothing to undo."])
                end
            end
        end, L["Restore the route cleared in the last 30 seconds"])
    end
    Events:Register("COMBAT_STATE", function(_, inCombat) Navigator:OnCombat(inCombat) end, self)
    Events:Register("SETTINGS_CHANGED", function(_, key) Navigator:OnSettingsChanged(key) end, self)
    Events:Register("FLIGHTS_KNOWN", function() Navigator:OnFlightsKnown() end, self)
    Events:Register("WORLD_ENTERED", function()




        local fighting = (InCombatLockdown and InCombatLockdown()) and true or false
        if fighting then Navigator:OnCombat(true) end
        if Navigator.ticker then Navigator:Tick() end
        Navigator:OnCombat(fighting)
        Navigator:AnnounceKeptItinerary()
        Navigator:ContinueQuestHop()
    end, self)
    Events:RegisterWoW("ZONE_CHANGED_NEW_AREA", function()
        if Navigator.ticker then Navigator:Tick() end
        Navigator:ContinueQuestHop()
    end, self)

    readPlace(self)
    for _, event in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "NEW_WMO_CHUNK" }) do
        Events:RegisterWoW(event, function() readPlace(Navigator) end, self)
    end



    Events:RegisterWoW("PLAYER_CONTROL_GAINED", function()
        if Navigator.ticker then Navigator:Tick() end
        if Navigator.questHop and Navigator.questHop.air then Navigator:ContinueQuestHop() end
    end, self)
    if InCombatLockdown and InCombatLockdown() then self.inCombat = true end
end
