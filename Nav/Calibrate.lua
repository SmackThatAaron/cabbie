





































local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local Events = FGPS.Events
local Const = FGPS.Const
local sqrt, floor, format, type, pairs, ipairs, tonumber, tostring = math.sqrt, math.floor, string.format, type, pairs, ipairs, tonumber, tostring

local Calibrate = {
    SAMPLES = 12,
    MIN_GROUND_SAMPLES = 8,
    MIN_RIDE_SAMPLES = 1,
    MAX_FLIGHTS = 400,
    MAX_TELEPORTS = 32,
    GROUND_MIN_DT = 0.15,
    GROUND_MAX_DT = 2.0,
    GROUND_MIN_YARDS = 2,
    GROUND_STILL_YARDS = 0.25,
    GROUND_PACE_SHARE = 0.9,
    GROUND_MIN_FACTOR = 0.4,
    GROUND_MAX_FACTOR = 1.25,
    RIDE_MIN_SECONDS = 8,
    RIDE_MAX_SECONDS = 3600,
    LANDING_YARDS = 100,
    TAKEOFF_YARDS = 60,
    CAST_MAX_SECONDS = 60,
    LOAD_MAX_SECONDS = 180,
    PHASE_MAX_AGE = 2 * 3600,
    TELEPORT_SPELLS = {
        [8690] = "hearth",
        [556] = 556,
        [3561] = 3561, [3562] = 3562, [3563] = 3563, [3565] = 3565, [3566] = 3566, [3567] = 3567,
        [18960] = 18960,
    },
    ground = nil,
    flight = nil,
    cast = nil,
}
FGPS.Calibrate = Calibrate

local function now() return GetTime and GetTime() or 0 end



local function serverNow()
    if GetServerTime then
        local ok, v = pcall(GetServerTime)
        if ok and type(v) == "number" and v > 0 then return v end
    end
    if time then
        local ok, v = pcall(time)
        if ok and type(v) == "number" and v > 0 then return v end
    end
    return nil
end

local function dist(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return sqrt(dx * dx + dy * dy)
end








local function charStore()
    local DB = FGPS.DB
    local root = DB and DB.char
    if type(root) ~= "table" then
        Calibrate.volatileChar = Calibrate.volatileChar or {}
        root = Calibrate.volatileChar
    end
    if type(root.calibration) ~= "table" then root.calibration = {} end
    local c = root.calibration
    if type(c.ground) ~= "table" then c.ground = {} end
    if type(c.teleport) ~= "table" then c.teleport = {} end
    return c
end

local function accountStore()
    local DB = FGPS.DB
    local root = DB and DB.account
    if type(root) ~= "table" then
        Calibrate.volatileAccount = Calibrate.volatileAccount or {}
        root = Calibrate.volatileAccount
    end
    if type(root.calibration) ~= "table" then root.calibration = {} end
    local c = root.calibration
    if type(c.flights) ~= "table" then c.flights = {} end
    if type(c.transports) ~= "table" then c.transports = {} end
    return c
end
Calibrate.CharStore, Calibrate.AccountStore = charStore, accountStore








local function median(values)
    local n = #values
    if n == 0 then return nil end
    local sorted = {}
    for i = 1, n do sorted[i] = values[i] end
    table.sort(sorted)
    local mid = floor(n / 2)
    if n % 2 == 1 then return sorted[mid + 1] end
    return (sorted[mid] + sorted[mid + 1]) / 2
end
Calibrate.Median = median

local function record(container, key, value)
    if type(value) ~= "number" or value ~= value then return nil end
    local est = container[key]
    if type(est) ~= "table" or type(est.s) ~= "table" then est = { s = {}, i = 0, n = 0 } container[key] = est end
    est.i = (tonumber(est.i) or 0) % Calibrate.SAMPLES + 1
    est.s[est.i] = value
    est.n = (tonumber(est.n) or 0) + 1
    est.v = median(est.s)
    return est
end

local function valueOf(est, minSamples)
    if type(est) ~= "table" then return nil end
    local v, n = tonumber(est.v), tonumber(est.n) or 0
    if not v or n < (minSamples or 1) then return nil end
    return v, n
end



local function capEntries(container, cap)
    local keys, n = {}, 0
    for k in pairs(container) do n = n + 1 keys[n] = k end
    if n <= cap then return 0 end
    table.sort(keys, function(a, b)
        local na = (type(container[a]) == "table" and tonumber(container[a].n)) or 0
        local nb = (type(container[b]) == "table" and tonumber(container[b].n)) or 0
        if na ~= nb then return na < nb end
        return tostring(a) < tostring(b)
    end)
    local removed = 0
    for i = 1, n - cap do
        container[keys[i]] = nil
        removed = removed + 1
    end
    return removed
end


local function invalidateRoutes()
    local Router = FGPS.Router
    if Router and Router.InvalidateCache then pcall(Router.InvalidateCache, Router) end
end







local function stateOf(mounted)
    return mounted and "mounted" or "foot"
end

local function accessState(access)
    if access and access.hasMount and access.canMount ~= false and (tonumber(access.mountSpeed) or 0) >= 0.6 then
        return "mounted"
    end
    return "foot"
end
Calibrate.AccessState = accessState



function Calibrate.GroundSpeed(access)
    local state = accessState(access)
    local v, n = valueOf(charStore().ground[state], Calibrate.MIN_GROUND_SAMPLES)
    if not v then return nil end


    local modelled = Calibrate.ModelledGroundSpeed(access)
    local low, high = modelled * Calibrate.GROUND_MIN_FACTOR, modelled * Calibrate.GROUND_MAX_FACTOR
    if v < low then v = low elseif v > high then v = high end
    return v, n, state
end


function Calibrate.ModelledGroundSpeed(access)
    local Cost = FGPS.Cost
    if Cost and Cost.GroundSpeed then
        local ok, v = pcall(Cost.GroundSpeed, access)
        if ok and type(v) == "number" and v > 0 then return v end
    end
    return Const.RUN_SPEED or 7
end



function Calibrate.NotePosition(pos)
    if not pos or not pos.inst or not pos.x or not pos.y then Calibrate.ground = nil return nil end
    local t = now()
    local previous = Calibrate.ground
    Calibrate.ground = { inst = pos.inst, x = pos.x, y = pos.y, t = t, state = nil }



    if UnitOnTaxi and UnitOnTaxi("player") then return nil end
    local Transport = FGPS.Transport
    local ride = Transport and Transport.State and Transport.State() or nil
    if ride and (ride.onTaxi or ride.onTransport) then return nil end
    if IsSwimming then
        local ok, swimming = pcall(IsSwimming)
        if ok and swimming then return nil end
    end
    if IsFalling then
        local ok, falling = pcall(IsFalling)
        if ok and falling then return nil end
    end

    local Social = FGPS.Social
    if Social and Social.IsDead and Social.IsDead() then return nil end




    if InCombatLockdown and InCombatLockdown() then return nil end
    local Coords = FGPS.Coords
    local current, run = 0, 0
    if Coords and Coords.PlayerSpeed then current, run = Coords.PlayerSpeed() end
    if (current or 0) > 0 and current < Calibrate.GROUND_PACE_SHARE * (run or 0) then return nil end
    local mounted = false
    if IsMounted then
        local ok, v = pcall(IsMounted)
        if ok then mounted = v and true or false end
    end
    local state = stateOf(mounted)
    Calibrate.ground.state = state
    if not previous or previous.inst ~= pos.inst or previous.state ~= state then return nil end
    local dt = t - previous.t
    if dt < Calibrate.GROUND_MIN_DT or dt > Calibrate.GROUND_MAX_DT then return nil end
    local moved = dist(pos.x, pos.y, previous.x, previous.y)



    if previous.still then
        if moved < Calibrate.GROUND_STILL_YARDS then Calibrate.ground.still = true end
        return nil
    end
    if moved < Calibrate.GROUND_MIN_YARDS then




        local stepped = dist(pos.x, pos.y, previous.lx or previous.x, previous.ly or previous.y)
        if stepped >= Calibrate.GROUND_STILL_YARDS then
            previous.lx, previous.ly = pos.x, pos.y
            Calibrate.ground = previous
        else
            Calibrate.ground.still = true
        end
        return nil
    end
    local speed = moved / dt


    local ceiling = (Const.MOUNT_100 or 14) * 1.6
    if speed > ceiling then return nil end
    local store = charStore().ground
    local before = tonumber(store[state] and store[state].v)
    local est = record(store, state, speed)
    local after = est and tonumber(est.v)

    if after and (not before or math.abs(after - before) > 0.25) then invalidateRoutes() end
    return speed, state
end




local function flightKey(from, to)
    if not from or not to then return nil end
    return tostring(from) .. ">" .. tostring(to)
end
Calibrate.FlightKey = flightKey



function Calibrate.FlightSeconds(from, to)
    local key = flightKey(from, to)
    if not key then return nil end
    return valueOf(accountStore().flights[key], Calibrate.MIN_RIDE_SAMPLES)
end


local function pendingFlightLeg()
    local Transport = FGPS.Transport
    if not (Transport and Transport.NextTaxiLeg) then return nil end
    local ok, leg = pcall(Transport.NextTaxiLeg)
    if not ok or type(leg) ~= "table" then return nil end
    return leg
end


local function playerNear(inst, point, yards)
    if type(point) ~= "table" or type(point.x) ~= "number" or type(point.y) ~= "number" then return false end
    local Coords = FGPS.Coords
    if not (Coords and Coords.PlayerPos) then return false end
    local ok, pos = pcall(Coords.PlayerPos)
    if not ok or type(pos) ~= "table" or not pos.x or not pos.y then return false end
    if pos.inst ~= inst then return false end
    return dist(pos.x, pos.y, point.x, point.y) <= yards
end

function Calibrate.OnTaxiState(onTaxi)
    if onTaxi then
        if Calibrate.flight then return nil end
        local leg = pendingFlightLeg()
        local pts = leg and type(leg.points) == "table" and leg.points or nil



        if not (pts and playerNear(leg.inst, pts[1], Calibrate.TAKEOFF_YARDS)) then leg, pts = nil, nil end
        local last = pts and pts[#pts]
        Calibrate.flight = { from = leg and leg.taxiFrom, to = leg and leg.taxiTo, start = now(),
                             inst = leg and leg.inst, landing = last and { x = last.x, y = last.y } or nil }
        return nil
    end
    local ride = Calibrate.flight
    Calibrate.flight = nil
    if not ride then return nil end
    local seconds = now() - ride.start
    if seconds < Calibrate.RIDE_MIN_SECONDS or seconds > Calibrate.RIDE_MAX_SECONDS then return nil end
    local key = flightKey(ride.from, ride.to)
    if not key then return nil end


    if not playerNear(ride.inst, ride.landing, Calibrate.LANDING_YARDS) then return nil end
    local flights = accountStore().flights
    record(flights, key, seconds)
    capEntries(flights, Calibrate.MAX_FLIGHTS)
    invalidateRoutes()
    return seconds, key
end





local function plainString(fn)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn)
    if not ok or v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return type(v) == "string" and v ~= "" and v or nil
end




local function realmName()
    return plainString(GetRealmName) or plainString(GetNormalizedRealmName)
end




function Calibrate.NoteDeparture(transportID, stopIndex, departureTime)
    if transportID == nil or stopIndex == nil then return nil end



    local records = FGPS.Data and FGPS.Data.transports
    if type(records) == "table" and records[transportID] == nil then return nil end
    local wall = serverNow()
    if not wall then return nil end
    local elapsed = now() - (tonumber(departureTime) or now())
    local store = accountStore().transports
    local perStop = store[transportID]
    if type(perStop) ~= "table" then perStop = {} store[transportID] = perStop end
    local entry = perStop[stopIndex]
    if type(entry) ~= "table" then entry = { n = 0 } perStop[stopIndex] = entry end
    entry.at = wall - elapsed
    entry.n = (tonumber(entry.n) or 0) + 1
    entry.realm = realmName()
    invalidateRoutes()
    return entry.at
end







function Calibrate.SeedTransportPhases()
    local Transport = FGPS.Transport
    if not Transport or type(Transport.phases) ~= "table" then return 0 end
    local wall = serverNow()
    if not wall then return 0 end
    local offset = now() - wall
    local realm = realmName()
    local seeded = 0
    for transportID, byStop in pairs(accountStore().transports) do
        if type(byStop) == "table" then
            for stopIndex, entry in pairs(byStop) do
                local at = type(entry) == "table" and tonumber(entry.at) or nil
                if at and (wall - at > Calibrate.PHASE_MAX_AGE or entry.realm ~= realm) then at = nil end
                if at then
                    local phases = Transport.phases[transportID]
                    if type(phases) ~= "table" then phases = {} Transport.phases[transportID] = phases end
                    if phases[stopIndex] == nil then
                        phases[stopIndex] = at + offset
                        seeded = seeded + 1
                    end
                end
            end
        end
    end
    return seeded
end






function Calibrate.TeleportSeconds(id)
    local est = charStore().teleport[id]
    if type(est) ~= "table" then return nil end
    local cast = valueOf(est.cast, Calibrate.MIN_RIDE_SAMPLES)
    local load = valueOf(est.load, Calibrate.MIN_RIDE_SAMPLES)
    return cast, load
end

local function teleportEntry(id)
    local store = charStore().teleport
    local entry = store[id]
    if type(entry) ~= "table" then entry = {} store[id] = entry end
    return entry, store
end

function Calibrate.OnSpellcastStart(unit, _, spellID)
    if unit ~= "player" then return nil end
    local id = Calibrate.TELEPORT_SPELLS[tonumber(spellID) or 0]
    if not id then return nil end
    Calibrate.cast = { id = id, start = now() }
    return id
end





function Calibrate.OnSpellcastSucceeded(unit, _, spellID)
    if unit ~= "player" then return nil end
    local id = Calibrate.TELEPORT_SPELLS[tonumber(spellID) or 0]
    if not id then return nil end
    local pending = Calibrate.cast
    local t = now()
    if not pending or pending.id ~= id then

        Calibrate.cast = { id = id, start = t, done = t }
        return nil
    end
    pending.done = t
    return t - pending.start
end



function Calibrate.OnWorldEntered()
    local pending = Calibrate.cast
    Calibrate.cast = nil
    if not pending or not pending.done then return nil end
    local load = now() - pending.done
    local cast = pending.done - pending.start
    if load < 0 or load > Calibrate.LOAD_MAX_SECONDS then return nil end
    local entry, store = teleportEntry(pending.id)
    if cast >= 0 and cast <= Calibrate.CAST_MAX_SECONDS then record(entry, "cast", cast) end
    record(entry, "load", load)
    capEntries(store, Calibrate.MAX_TELEPORTS)
    invalidateRoutes()
    return load, cast
end




local function transportRecord(transportID)
    local records = FGPS.Data and FGPS.Data.transports
    return records and transportID ~= nil and records[transportID] or nil
end










function Calibrate.ApplyToRoute(route)
    if type(route) ~= "table" or type(route.legs) ~= "table" then return route end
    if route.calibrated then return route end
    route.calibrated = true
    local Transport = FGPS.Transport
    local Cost = FGPS.Cost
    local used = { flights = 0, transports = 0, teleports = 0, ground = false }


    local a = type(route.assumptions) == "table" and route.assumptions or nil
    local conditions = a and { hasMount = a.hasMount, mountSpeed = a.mountSpeed, canMount = true } or nil
    local groundSpeed, groundSamples, groundState = Calibrate.GroundSpeed(conditions)
    local groundFactor
    if groundSpeed then
        local modelled = tonumber(a and a.groundSpeed) or Calibrate.ModelledGroundSpeed(conditions)
        if modelled and modelled > 0 then
            groundFactor = modelled / groundSpeed
            used.ground = { speed = groundSpeed, samples = groundSamples, state = groundState, modelled = modelled }
        end
    end


    local reachAt = now()
    for _, leg in ipairs(route.legs) do
        local before = tonumber(leg.seconds) or 0
        local after = before
        if leg.kind == "walk" then
            if groundFactor then
                after = before * groundFactor
                leg.measured = "ground"
            end
        elseif leg.kind == "taxi" then
            local seconds = Calibrate.FlightSeconds(leg.taxiFrom, leg.taxiTo)
            if seconds then
                after = seconds + (Const.TAXI_BOARD_SECONDS or 0)
                leg.measured = "flight"

                leg.penaltySeconds = 0
                used.flights = used.flights + 1
            end
        elseif leg.kind == "boat" or leg.kind == "zeppelin" or leg.kind == "ferry" then
            local rec = transportRecord(leg.transportID)
            local period = rec and tonumber(rec.period)
            local stopIndex = Transport and Transport.LegStopIndex and Transport.LegStopIndex(leg, "stopFrom") or nil
            if period and stopIndex and Transport.NextDeparture then
                local okWait, wait = pcall(Transport.NextDeparture, leg.transportID, stopIndex, reachAt)
                local modelled = Cost and Cost.ExpectedWait and Cost.ExpectedWait(period) or nil
                if okWait and type(wait) == "number" and modelled then
                    after = before - modelled + wait
                    leg.measured = "transport"

                    leg.waitSeconds, leg.wait = wait, wait
                    used.transports = used.transports + 1
                end
            end
        elseif leg.kind == "hearth" or leg.kind == "spell" then
            local id = leg.kind == "hearth" and "hearth" or (leg.option and tonumber(leg.option.id)) or nil
            if id then
                local cast, load = Calibrate.TeleportSeconds(id)
                if cast or load then
                    local modelledCast = tonumber(leg.castSeconds) or Const.HEARTH_CAST_SECONDS or 10
                    local modelledLoad = Const.HEARTH_LOAD_SECONDS or 5
                    after = before - modelledCast - modelledLoad + (cast or modelledCast) + (load or modelledLoad)
                    leg.measured = "teleport"
                    used.teleports = used.teleports + 1
                end
            end
        end
        if after ~= before and after >= 0 then
            leg.seconds = after
            route.totalSeconds = (tonumber(route.totalSeconds) or 0) + (after - before)
        end
        reachAt = reachAt + (tonumber(leg.seconds) or 0)
    end
    route.measured = used
    local sentence = Calibrate.ExplainSentence(used)
    if sentence and type(route.explain) == "string" and not route.explain:find(sentence, 1, true) then
        route.explain = route.explain .. " " .. sentence
    end
    return route
end



function Calibrate.ExplainSentence(used)
    if type(used) ~= "table" then return nil end
    local parts = {}
    local g = used.ground
    if type(g) == "table" then
        local label = g.state == "mounted" and L["mounted"] or L["on foot"]
        parts[#parts + 1] = format(L["your own speed %s (%.1f instead of %.1f yards per second, over %d samples)"],
            label, g.speed, g.modelled, g.samples)
    elseif g then
        parts[#parts + 1] = L["your own ground speed"]
    end
    if (used.flights or 0) > 0 then parts[#parts + 1] = L["flights you have taken before"] end
    if (used.transports or 0) > 0 then parts[#parts + 1] = L["the real departure times of the boats on this route"] end
    if (used.teleports or 0) > 0 then parts[#parts + 1] = L["your own cast and loading times"] end
    if #parts == 0 then return nil end
    local list
    if #parts == 1 then
        list = parts[1]
    else
        local last = table.remove(parts)
        list = table.concat(parts, ", ") .. " " .. L["and"] .. " " .. last
    end
    return format(L["Measured rather than modelled: %s."], list)
end




function Calibrate.Report()
    local char, account = charStore(), accountStore()
    local out = { ground = {}, flights = 0, flightSamples = 0, transports = 0, teleports = {} }
    for _, state in ipairs({ "foot", "mounted" }) do
        local est = char.ground[state]
        if type(est) == "table" and tonumber(est.v) then
            out.ground[state] = { speed = est.v, samples = tonumber(est.n) or 0,
                                  enough = (tonumber(est.n) or 0) >= Calibrate.MIN_GROUND_SAMPLES }
        end
    end
    for _, est in pairs(account.flights) do
        out.flights = out.flights + 1
        out.flightSamples = out.flightSamples + ((type(est) == "table" and tonumber(est.n)) or 0)
    end
    for _, byStop in pairs(account.transports) do
        if type(byStop) == "table" then for _ in pairs(byStop) do out.transports = out.transports + 1 end end
    end
    for id, entry in pairs(char.teleport) do
        if type(entry) == "table" then
            local cast, load = Calibrate.TeleportSeconds(id)
            out.teleports[id] = { cast = cast, load = load }
        end
    end
    return out
end

local RESET_TARGETS = { ground = true, flights = true, transports = true, teleports = true }



function Calibrate.Reset(what)
    what = (what == nil or what == "") and "all" or Util.Lower(Util.Trim(tostring(what)))
    if what ~= "all" and not RESET_TARGETS[what] then return nil, what end
    local char, account = charStore(), accountStore()
    local done = {}
    if what == "all" or what == "ground" then
        wipe(char.ground)
        Calibrate.ground = nil
        done[#done + 1] = "ground"
    end
    if what == "all" or what == "flights" then
        wipe(account.flights)
        Calibrate.flight = nil
        done[#done + 1] = "flights"
    end
    if what == "all" or what == "transports" then
        wipe(account.transports)
        local Transport = FGPS.Transport
        if Transport and type(Transport.phases) == "table" then wipe(Transport.phases) end
        done[#done + 1] = "transports"
    end
    if what == "all" or what == "teleports" then
        wipe(char.teleport)
        Calibrate.cast = nil
        done[#done + 1] = "teleports"
    end
    invalidateRoutes()
    return done
end

local function printReport()
    local r = Calibrate.Report()
    FGPS:Print(L["Measured travel times (everything else comes from the model):"])
    for _, state in ipairs({ "foot", "mounted" }) do
        local g = r.ground[state]
        local label = state == "mounted" and L["mounted"] or L["on foot"]
        if g then
            if g.enough then
                FGPS:Print(L["  %s: %.1f yards per second over %d samples"], label, g.speed, g.samples)
            else
                FGPS:Print(L["  %s: %.1f yards per second over %d samples (not used yet, %d needed)"],
                    label, g.speed, g.samples, Calibrate.MIN_GROUND_SAMPLES)
            end
        else
            FGPS:Print(L["  %s: nothing measured yet"], label)
        end
    end
    FGPS:Print(L["  flights: %d path(s) timed from %d real ride(s)"], r.flights, r.flightSamples)
    FGPS:Print(L["  transports: departure times known for %d dock(s)"], r.transports)
    local teleports = 0
    for _ in pairs(r.teleports) do teleports = teleports + 1 end
    FGPS:Print(L["  teleports: cast and loading times for %d of them"], teleports)
    FGPS:Print(L["Use /cabbie calibrate reset [ground|flights|transports|teleports] to forget measurements."])
end

local function slash(args)
    local text = Util.Trim(args or "")
    local word, rest = text:match("^(%S+)%s*(.*)$")
    word = word and Util.Lower(word) or ""
    if word == "reset" then
        local done, bad = Calibrate.Reset(rest)
        if not done then
            FGPS:Print(L["There is nothing measured called '%s'. Try ground, flights, transports or teleports."], tostring(bad))
            return
        end
        FGPS:Print(L["Forgot the measurements for: %s."], table.concat(done, ", "))
        return
    end
    printReport()
end




function Calibrate:Init()
    if self.initialised then return end
    self.initialised = true
    Calibrate.SeedTransportPhases()
    Events:Register("POSITION_UPDATE", function(_, pos) Calibrate.NotePosition(pos) end, self)
    Events:Register("TRANSPORT_STATE", function(_, state)
        Calibrate.OnTaxiState(type(state) == "table" and state.onTaxi == true)
    end, self)

    Events:RegisterUnitWoW("UNIT_SPELLCAST_START", "player", function(_, unit, castGUID, spellID)
        Calibrate.OnSpellcastStart(unit, castGUID, spellID)
    end, self)
    Events:RegisterUnitWoW("UNIT_SPELLCAST_SUCCEEDED", "player", function(_, unit, castGUID, spellID)
        Calibrate.OnSpellcastSucceeded(unit, castGUID, spellID)
    end, self)
    Events:Register("WORLD_ENTERED", function() Calibrate.OnWorldEntered() end, self)




    local function journeyStopped() Calibrate.ground, Calibrate.flight = nil, nil end
    Events:Register("NAV_CANCELLED", journeyStopped, self)
    Events:Register("NAV_STATE", function(_, new) if new == "idle" then journeyStopped() end end, self)
    if FGPS.Slash and FGPS.Slash.Register then
        FGPS.Slash.Register("calibrate", slash, L["Measured travel times: calibrate [reset ...]"])
    end
end
