


















local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local type, pairs, ipairs, tostring, tonumber, pcall = type, pairs, ipairs, tostring, tonumber, pcall
local format, sort, concat = string.format, table.sort, table.concat


local STATUS_TAG = {
    pass = "|cff40ff40pass|r",
    warn = "|cffffd100warn|r",
    note = "|cffccccccnote|r",
    fail = "|cffff4040FAIL|r",
    skip = "|cff999999skip|r",
    pending = "|cff999999....|r",
}

local SelfTest = {
    ROUTE_YARDS = 300,
    ROUTE_TIMEOUT = 5,
    COORD_TOLERANCE = 5,
    LOG_LINES = 10,
    last = nil,
    lastRoute = nil,
    sessionStart = nil,
}
FGPS.SelfTest = SelfTest




local function stamp()
    if date then
        local ok, s = pcall(date, "%Y-%m-%d %H:%M:%S")
        if ok and type(s) == "string" then return s end
    end
    if time then
        local ok, t = pcall(time)
        if ok and t then return tostring(t) end
    end
    return "unknown"
end

local function round1(n)
    if type(n) ~= "number" then return nil end
    return Util.Round(n, 1)
end


local function nameList(names, limit)
    sort(names)
    limit = limit or 8
    if #names <= limit then return concat(names, ", ") end
    local head = {}
    for i = 1, limit do head[i] = names[i] end
    return format("%s and %d more", concat(head, ", "), #names - limit)
end


local function clientBuildString()
    local b = FGPS.build
    if not b or not b.version then return nil end
    if b.buildNumber == nil or b.buildNumber == "" then return tostring(b.version) end
    return tostring(b.version) .. "." .. tostring(b.buildNumber)
end






local REQUIRED_GLOBALS = {
    "CreateFrame", "UIParent", "WorldFrame", "Minimap", "GetTime", "GetBuildInfo", "GetLocale",
    "UnitPosition", "GetPlayerFacing", "GetUnitSpeed", "UnitFactionGroup", "UnitClass", "UnitLevel",
    "IsMounted", "UnitOnTaxi", "InCombatLockdown", "GetScreenWidth", "GetScreenHeight",
    "collectgarbage", "debugprofilestop", "geterrorhandler", "LibStub", "SlashCmdList", "Enum",
}
local OPTIONAL_GLOBALS = {
    "WorldMapFrame", "MinimapCluster", "GameTooltip", "Settings", "EventRegistry", "hooksecurefunc",
    "UpdateAddOnMemoryUsage", "GetAddOnMemoryUsage", "GetFramerate", "GetCVar", "IsIndoors", "IsSwimming",
}
local REQUIRED_MEMBERS = {
    { "C_Map", "GetBestMapForUnit", "GetMapInfo", "GetPlayerMapPosition", "GetWorldPosFromMapPos", "GetMapPosFromWorldPos" },
    { "C_Timer", "After", "NewTimer", "NewTicker" },
    { "C_AddOns", "GetAddOnMetadata" },
}
local OPTIONAL_MEMBERS = {
    { "C_TaxiMap", "GetTaxiNodesForMap", "GetAllTaxiNodes" },
    { "C_VoiceChat", "SpeakText", "GetTtsVoices" },
    { "C_TTSSettings", "GetVoiceOptionID" },
    { "C_SuperTrack", "SetSuperTrackedUserWaypoint" },
    { "C_Map", "SetUserWaypoint", "GetUserWaypoint", "CanSetUserWaypointOnMap", "GetMapChildrenInfo" },
    { "WorldMapFrame", "GetCanvasScale", "GetViewRect", "ZoomMapTo", "PanMapTo" },
    { "C_SkillInfo", "GetSkillLineInfoByID" },
    { "C_MountJournal", "GetMountIDs", "GetMountInfoByID" },
    { "C_QuestLog", "GetNumQuestLogEntries", "GetInfo" },
    { "C_Container", "PlayerHasHearthstone", "GetItemCooldown" },
    { "C_Minimap", "GetViewRadius" },
    { "C_AddOnProfiler", "GetAddOnMetric" },
    { "C_EditMode", "GetLayouts" },
    { "C_Spell", "GetSpellName", "GetSpellCooldown" },
    { "C_SpellBook", "IsSpellKnown" },
    { "C_Texture", "GetAtlasInfo" },
    { "C_GossipInfo", "GetOptions" },
}


local BOOT_EVENTS = {
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
}




local probeFrame
function SelfTest.ProbeEvent(name)
    if not CreateFrame then return false, "CreateFrame is missing" end
    if not probeFrame then
        local ok, frame = pcall(CreateFrame, "Frame")
        if not ok or not frame then return false, "cannot create a probe frame" end
        probeFrame = frame
    end
    local ok, err = pcall(probeFrame.RegisterEvent, probeFrame, name)
    if ok then
        pcall(probeFrame.UnregisterEvent, probeFrame, name)
        return true
    end
    return false, tostring(err)
end



local function registeredEvents()
    local seen, out = {}, {}
    local handlers = FGPS.Events and FGPS.Events.wowHandlers
    if type(handlers) == "table" then
        for name in pairs(handlers) do
            if not seen[name] then seen[name] = true out[#out + 1] = name end
        end
    end
    for _, name in ipairs(BOOT_EVENTS) do
        if not seen[name] then seen[name] = true out[#out + 1] = name end
    end
    sort(out)
    return out
end

local function checkApi()
    local missing, degraded, checked = {}, {}, 0

    for _, name in ipairs(REQUIRED_GLOBALS) do
        checked = checked + 1
        if _G[name] == nil then missing[#missing + 1] = name end
    end
    for _, name in ipairs(OPTIONAL_GLOBALS) do
        checked = checked + 1
        if _G[name] == nil then degraded[#degraded + 1] = name end
    end

    local function members(groups, out)
        for _, group in ipairs(groups) do
            local namespace = _G[group[1]]
            for i = 2, #group do
                checked = checked + 1
                if type(namespace) ~= "table" or namespace[group[i]] == nil then
                    out[#out + 1] = group[1] .. "." .. group[i]
                end
            end
        end
    end
    members(REQUIRED_MEMBERS, missing)
    members(OPTIONAL_MEMBERS, degraded)

    local events = registeredEvents()
    for _, name in ipairs(events) do
        checked = checked + 1
        if not SelfTest.ProbeEvent(name) then missing[#missing + 1] = "event " .. name end
    end

    if #missing > 0 then
        return "fail", format("%d name(s) this addon needs are missing: %s", #missing, nameList(missing))
    end
    if #degraded > 0 then
        return "warn", format("%d optional name(s) missing, those features stay off: %s", #degraded, nameList(degraded))
    end
    return "pass", format("%d names present, including %d registered event(s)", checked, #events)
end




local function checkModules()
    local report = FGPS.Boot and FGPS.Boot.report
    if type(report) ~= "table" then return "fail", "Core/Boot.lua produced no boot report" end
    if #report.failed > 0 then
        local names = {}
        for i, entry in ipairs(report.failed) do names[i] = entry.name end
        return "fail", format("%d module(s) failed to initialise: %s (type /cabbie log)", #report.failed, nameList(names))
    end
    if #report.skipped > 0 then
        local names = {}
        for i, name in ipairs(report.skipped) do names[i] = name end
        return "warn", format("%d module(s) are not installed: %s", #report.skipped, nameList(names))
    end
    return "pass", format("%d module(s) initialised", #report.initialised)
end




local function checkData()
    local Data = FGPS.Data
    local manifest = Data and Data.manifest
    if type(manifest) ~= "table" then
        return "fail", "Data/Manifest.lua did not load (FGPS.Data.manifest is missing)"
    end
    local counts = manifest.counts or {}
    if (tonumber(counts.nodes) or 0) <= 0 then
        return "fail", "the bundled route graph is empty (manifest reports no nodes)"
    end
    local graphs, maps = 0, 0
    for _ in pairs(Data.graphs or {}) do graphs = graphs + 1 end
    for _ in pairs(Data.maps or {}) do maps = maps + 1 end


    local DataLoad = FGPS.DataLoad
    local folders, loadedFolders, wrong, loadable = 0, 0, {}, 0
    local WRONG = { missing = "is not installed", disabled = "is turned off", stale = "is from another version",
                    broken = "did not finish loading" }
    if DataLoad then
        local names = {}
        for addon in pairs(DataLoad.parts) do names[#names + 1] = addon end
        table.sort(names)
        for _, addon in ipairs(names) do
            local state = DataLoad:State(addon)
            if state ~= "absent" then folders = folders + 1 end
            if state == "loaded" then loadedFolders = loadedFolders + 1 end
            if state == "loaded" or state == "unloaded" then loadable = loadable + 1 end
            if WRONG[state] then wrong[#wrong + 1] = addon .. " " .. WRONG[state] end
        end
    end
    if graphs == 0 and loadable == 0 then return "fail", "no graph loaded and no map folder can load (Cabbie_Data_*)" end
    if maps == 0 then return "fail", "Data/Maps.lua did not load, no zone bounds are known" end
    if #wrong > 0 then
        return "warn", format("%s; reinstall Cabbie with all its folders and turn them on in the AddOns list", table.concat(wrong, ", "))
    end



    local clientBuild = clientBuildString()
    local dataBuild = manifest.clientBuild and tostring(manifest.clientBuild) or nil
    if dataBuild and clientBuild and dataBuild ~= clientBuild then
        return "warn", format("data was generated for client build %s, this client is %s: coordinates and flight points may be stale",
            dataBuild, clientBuild)
    end
    local dataInterface, clientInterface = tonumber(manifest.interface), FGPS.build and FGPS.build.interface
    if dataInterface and clientInterface and dataInterface ~= clientInterface then
        return "warn", format("data was generated for interface %d, this client reports %d", dataInterface, clientInterface)
    end
    return "pass", format("version %s for build %s: %d nodes, %d POI, %d taxi node(s) over %d instance(s), %d zone map(s), %d of %d map folder(s) loaded",
        tostring(manifest.dataVersion), tostring(dataBuild or "unknown"), tonumber(counts.nodes) or 0,
        tonumber(counts.poi) or 0, tonumber(counts.taxiNodes) or 0, graphs, maps, loadedFolders, folders)
end







local function checkCoords()
    local Coords = FGPS.Coords
    if not Coords then return "fail", "Nav/Coords.lua is not loaded" end
    local pos = Coords.PlayerPos()
    if not pos then
        return "warn", "the client reports no player position here (normal inside some instances)"
    end
    local uiMapID, mx, my = Coords.WorldToMap(pos.inst, pos.x, pos.y)
    if not uiMapID then
        return "fail", format("no map covers world position (%.1f, %.1f) on instance %s", pos.x, pos.y, tostring(pos.inst))
    end
    local inst, x, y = Coords.MapToWorld(uiMapID, mx, my)
    if inst == nil or x == nil or y == nil then
        return "fail", format("map %d could not be converted back to world coordinates", uiMapID)
    end
    if inst ~= pos.inst then
        return "fail", format("the round trip changed instance %s -> %s", tostring(pos.inst), tostring(inst))
    end
    local drift = Coords.Distance(x, y, pos.x, pos.y) or 0
    local zone = Coords.MapName and Coords.MapName(uiMapID) or tostring(uiMapID)
    if drift > SelfTest.COORD_TOLERANCE then
        return "fail", format("world -> map -> world moved the player %.1f yd in %s (map %d), tolerance %.0f yd",
            drift, tostring(zone), uiMapID, SelfTest.COORD_TOLERANCE)
    end
    return "pass", format("%s (map %d) at %.1f, %.1f; round trip off by %.2f yd", tostring(zone), uiMapID,
        mx * 100, my * 100, drift)
end




local VALID_FACTIONS = { Alliance = true, Horde = true, Neutral = true }
local VALID_MOUNT_SPEEDS = { [0] = true, [0.6] = true, [1.0] = true }

local function checkAccess()
    local Access = FGPS.Access
    if not Access then return "fail", "Nav/Access.lua is not loaded" end
    local access = Access:Snapshot()
    if type(access) ~= "table" then return "fail", "Access:Snapshot() returned nothing" end
    if not VALID_FACTIONS[access.faction] then
        return "fail", format("the client reports an unusable faction: %s", tostring(access.faction))
    end
    if not VALID_MOUNT_SPEEDS[access.mountSpeed] then
        return "fail", format("riding skill produced an impossible mount speed: %s", tostring(access.mountSpeed))
    end
    local known = 0
    for _ in pairs(access.knownTaxi or {}) do known = known + 1 end


    local listed = 0
    local char = FGPS.DB and FGPS.DB.char
    for _, flag in pairs((char and char.knownTaxi) or {}) do
        if flag then listed = listed + 1 end
    end


    if access.taxiUnconfirmed then

        local _, where = Access:FlightsLeftOut()
        if type(where) == "string" then
            return "note", format("Flight paths: talk to a flight master in %s once so routes there can use flights (the world map lists %d as discovered for everybody on this client)",
                where, listed)
        end
        return "note", format("Flight paths: talk to any flight master once so routes can use flights (the world map lists %d as discovered for everybody on this client)",
            listed)
    end
    if known == 0 then
        return "note", "Flight paths: talk to any flight master once so routes can use flights"
    end
    return "pass", format("%s level %d, %d flight point(s) usable (%d read at a flight master, %d from the world map's list), mount speed +%d%%",
        tostring(access.faction), tonumber(access.level) or 0, known, access.taxiConfirmedCount or 0, access.taxiListedCount or 0,
        (access.mountSpeed or 0) * 100)
end




local function checkVoice()
    local Voice = FGPS.UI and FGPS.UI.Voice
    if not Voice then return "skip", "UI/Voice.lua is not installed" end
    if not Voice:IsEnabled() then return "skip", "voice is turned off in the settings" end
    local voices = Voice:GetVoices() or {}
    if #voices == 0 then
        return "fail", "voice is on but the client reports no text-to-speech voice; install a system voice or turn voice off"
    end
    if not Voice:IsAvailable() then
        return "fail", "voice is on and voices exist, but the client has no SpeakText function"
    end
    local id = Voice:GetVoiceID()
    return "pass", format("%d voice(s) available, using %s", #voices, tostring(Voice:GetVoiceName(id) or id))
end








function SelfTest.CountSession()
    local account = FGPS.DB and FGPS.DB.account
    if type(account) ~= "table" then return nil end
    local record = account.selftest
    if type(record) ~= "table" then
        record = { sessions = 0, firstSeen = stamp() }
        account.selftest = record
    end
    record.sessions = (tonumber(record.sessions) or 0) + 1
    record.lastSeen = stamp()
    return record
end

local function savedSessions()
    local account = FGPS.DB and FGPS.DB.account
    local record = type(account) == "table" and account.selftest or nil
    return tonumber(type(record) == "table" and record.sessions or nil) or 0, record
end









local function onWorldEntered(_, isInitialLogin, isReloadingUi)
    if SelfTest.sessionStart then return end
    if isReloadingUi then
        SelfTest.sessionStart = "reload"
    elseif isInitialLogin then
        SelfTest.sessionStart = "login"
    else
        return
    end
    if SelfTest.sessionStart == "reload" and savedSessions() <= 1 and FGPS.Log then
        FGPS.Log:Info("The interface was reloaded and the saved data came back empty: the client did not keep SavedVariables\\Cabbie.lua, unless Cabbie was switched on just before the /reload")
    end
end

local function checkSaved()
    local DB = FGPS.DB
    if not (DB and DB.initialized) then return "fail", "Core/DB.lua never initialised the saved variables" end
    if type(DB.settings) ~= "table" then return "fail", "CabbieDB.settings is missing" end
    local sessions, record = savedSessions()
    if sessions >= 2 then
        return "pass", format("read back from disk: %d session(s) recorded since %s", sessions, tostring(record.firstSeen))
    end



    if SelfTest.sessionStart == "reload" then return "skip", L.SELFTEST_SAVED_RELOAD_LOST end


    return "skip", L.SELFTEST_SAVED_FIRST
end






local function checkPositions()
    local Positions = FGPS.UI and FGPS.UI.Positions
    if not Positions then return "skip", "UI/Positions.lua is not installed" end
    local offScreen, checked = {}, 0
    local uw = (UIParent and UIParent.GetWidth and UIParent:GetWidth()) or (GetScreenWidth and GetScreenWidth()) or 0
    local uh = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or (GetScreenHeight and GetScreenHeight()) or 0
    if uw <= 0 or uh <= 0 then return "warn", "the client reports no screen size yet" end
    for key, entry in pairs(Positions.registry or {}) do
        local frame = entry and entry.frame
        local record = frame and Positions.ToRecord(frame)
        if record then
            checked = checked + 1
            local dx, dy = record.fx * uw, record.fy * uh
            local w, h = record.w or 0, record.h or 0
            local cx, cy = Positions.ClampCenter(dx, dy, w, h)
            if math.abs(cx - dx) > 0.5 or math.abs(cy - dy) > 0.5 then
                offScreen[#offScreen + 1] = tostring(key)
            end
        end
    end
    if checked == 0 then return "skip", "no positioned element is registered yet" end
    if #offScreen > 0 then
        return "fail", format("%d element(s) sit outside the screen: %s (type /cabbie reset positions)",
            #offScreen, nameList(offScreen))
    end
    return "pass", format("%d positioned element(s), all fully on screen", checked)
end




local function checkRoute(finish)
    local Coords, Router, Access = FGPS.Coords, FGPS.Router, FGPS.Access
    if not (Coords and Router and Access) then
        finish("skip", "the routing modules are not installed")
        return
    end
    local pos = Coords.PlayerPos()
    if not pos then
        finish("skip", "no player position to route from")
        return
    end



    local gx, gy = pos.x, pos.y + SelfTest.ROUTE_YARDS
    local Graph = FGPS.Graph
    if Graph and Graph.Nearest and Graph.NodePos then
        if Graph.Ensure then pcall(Graph.Ensure, Graph, pos.inst) end
        local ok, near = pcall(Graph.Nearest, Graph, pos.inst, gx, gy, SelfTest.ROUTE_YARDS, 8)
        for _, entry in ipairs(ok and near or {}) do
            local _, nx, ny = Graph:NodePos(entry.key)
            if nx and Coords.Distance(pos.x, pos.y, nx, ny) >= SelfTest.ROUTE_YARDS / 3 then
                gx, gy = nx, ny
                break
            end
        end
    end
    local dest = { kind = "coord", inst = pos.inst, x = gx, y = gy, map = pos.map }
    local answered, handle = false, nil
    local started = GetTime and GetTime() or 0

    local function answer(status, detail)
        if answered then return end
        answered = true
        finish(status, detail)
    end

    handle = Router:RequestRoute({ origin = pos, stops = { dest }, access = Access:Snapshot(), reason = "preview" },
        function(route, err)
            if route then
                local elapsed = (GetTime and GetTime() or 0) - started
                local kinds = {}
                for i, leg in ipairs(route.legs or {}) do kinds[i] = leg.kind end
                if route.fallback == "straight" then

                    answer("note", format("Sample route: %d yd with no road on file here, so the line points the direction only",
                        Util.Round(route.totalYards or 0)))
                else
                    answer("pass", format("%d yd over %d leg(s) [%s] in %.2f s, %d yd verified",
                        Util.Round(route.totalYards or 0), #kinds, concat(kinds, ", "), elapsed,
                        Util.Round(route.verifiedYards or 0)))
                end
            else
                answer("warn", format("no route %d yd north: %s (%s)", SelfTest.ROUTE_YARDS,
                    tostring(err and err.message or "unknown"), tostring(err and err.code or "?")))
            end
        end)

    if answered then return end

    if not (C_Timer and C_Timer.After) then
        if handle then pcall(Router.Cancel, Router, handle) end
        answer("fail", "the router did not answer at once and C_Timer is missing, so there is no way to wait")
        return
    end
    C_Timer.After(SelfTest.ROUTE_TIMEOUT, function()
        if answered then return end
        if handle then pcall(Router.Cancel, Router, handle) end
        answer("fail", format("the router did not answer within %d s", SelfTest.ROUTE_TIMEOUT))
    end)
end




SelfTest.checks = {
    { id = "api",       label = "client API",   fn = checkApi },
    { id = "modules",   label = "modules",      fn = checkModules },
    { id = "data",      label = "bundled data", fn = checkData },
    { id = "coords",    label = "coordinates",  fn = checkCoords },
    { id = "access",    label = "access",       fn = checkAccess },
    { id = "voice",     label = "voice",        fn = checkVoice },
    { id = "saved",     label = "saved vars",   fn = checkSaved },
    { id = "positions", label = "frames",       fn = checkPositions },
    { id = "route",     label = "sample route", fn = checkRoute, async = true },
}

local function record(result, entry, status, detail)
    if entry.status ~= "pending" then return end
    if not STATUS_TAG[status] or status == "pending" then
        detail = detail or format("the check returned %s", tostring(status))
        status = "fail"
    end
    entry.status = status
    entry.detail = detail and tostring(detail) or nil
    result[status] = result[status] + 1
end

local function maybeFinish(result)
    if result.done or result.launching or result.pending > 0 then return end
    result.done = true
    result.ok = result.fail == 0
    result.finished = stamp()
    local callback = result.onDone
    result.onDone = nil
    if callback then pcall(callback, result) end
end



function SelfTest:Run(opts)
    opts = opts or {}
    local result = {
        started = stamp(), entries = {}, byId = {},
        pass = 0, warn = 0, note = 0, fail = 0, skip = 0,
        pending = 0, launching = true, done = false, onDone = opts.onDone,
    }
    self.last = result
    for _, check in ipairs(self.checks) do
        local entry = { id = check.id, label = check.label, status = "pending" }
        result.entries[#result.entries + 1] = entry
        result.byId[check.id] = entry
        if check.async then
            result.pending = result.pending + 1
            local ok, err = pcall(check.fn, function(status, detail)
                if entry.status == "pending" then
                    result.pending = result.pending - 1
                    record(result, entry, status, detail)
                    maybeFinish(result)
                end
            end)
            if not ok and entry.status == "pending" then
                result.pending = result.pending - 1
                record(result, entry, "fail", err)
            end
        else
            local ok, status, detail = pcall(check.fn)
            if ok then record(result, entry, status, detail) else record(result, entry, "fail", status) end
        end
    end
    result.launching = false
    maybeFinish(result)
    return result
end

function SelfTest:Print(result)
    result = result or self.last
    if not result then return nil end
    FGPS:Print(L.SELFTEST_HEADER, #result.entries, result.pass, result.note or 0, result.warn, result.fail, result.skip)
    for _, entry in ipairs(result.entries) do
        FGPS:Print(L.SELFTEST_LINE, STATUS_TAG[entry.status] or entry.status, entry.label, entry.detail or "")
    end
    return result
end




local function summariseRoute(route)
    if type(route) ~= "table" then return nil end
    local legs = {}
    for i, leg in ipairs(route.legs or {}) do
        legs[i] = {
            kind = leg.kind, label = leg.label,
            yards = round1(leg.yards), seconds = round1(leg.seconds),
            verifiedYards = round1(leg.verifiedYards), unverifiedYards = round1(leg.unverifiedYards),
            straight = leg.straight or nil,
        }
    end
    return {
        at = stamp(), variant = route.variant, legs = legs,
        totalYards = round1(route.totalYards), totalSeconds = round1(route.totalSeconds),
        verifiedYards = round1(route.verifiedYards), unverifiedYards = round1(route.unverifiedYards),
        transfers = route.transfers, fallback = route.fallback,
    }
end
SelfTest.SummariseRoute = summariseRoute










local TRIP_RING = 8
local openTrip
SelfTest.trips = {}

local function yardsByKind(route)
    local out = {}
    for _, leg in ipairs(route.legs or {}) do
        local kind = leg.kind or "walk"
        out[kind] = (out[kind] or 0) + (tonumber(leg.yards) or 0)
    end
    return out
end

local function longestStraight(route)
    local best = 0
    for _, leg in ipairs(route.legs or {}) do
        local pts = leg.points
        if pts then
            for i = 2, #pts do
                local a, b = pts[i - 1], pts[i]
                if a and b and a.x and b.x then
                    local dx, dy = b.x - a.x, b.y - a.y
                    local d = (dx * dx + dy * dy) ^ 0.5
                    if d > best then best = d end
                end
            end
        end
    end
    return best
end

local function tripText(trip)
    local parts = {}
    for kind, yards in pairs(trip.yards or {}) do
        parts[#parts + 1] = format("%s %d yd", kind, yards)
    end
    sort(parts)
    local line = format(L.TRIP_SUMMARY, table.concat(parts, ", "), trip.longest or 0, trip.offRoute or 0, trip.recalc or 0)
    if trip.fallback then line = line .. " " .. format("Fallback: %s.", tostring(trip.fallback)) end
    if trip.note then line = line .. " " .. format("Note: %s.", trip.note) end
    return line
end

local function rememberTrip(route)
    if not openTrip or type(route) ~= "table" then return end
    openTrip.yards = yardsByKind(route)
    openTrip.longest = round1(longestStraight(route))
    openTrip.fallback = route.fallback
end

local function closeTrip()
    if not openTrip then return end
    local trip = openTrip
    openTrip = nil
    local ring = SelfTest.trips
    ring[#ring + 1] = trip
    while #ring > TRIP_RING do table.remove(ring, 1) end
end

function SelfTest.NoteTrip(route)
    if not openTrip then
        openTrip = { yards = {}, longest = 0, fallback = nil, offRoute = 0, recalc = 0 }
    end
    rememberTrip(route)
end

function SelfTest.CountOffRoute()
    if openTrip then openTrip.offRoute = openTrip.offRoute + 1 end
end

function SelfTest.CountRecalc()
    if openTrip then openTrip.recalc = openTrip.recalc + 1 end
end

function SelfTest.CloseTrip()
    closeTrip()
end

function SelfTest.MarkTrip(note)
    local trip = openTrip or SelfTest.trips[#SelfTest.trips]
    if not trip then
        FGPS:Print(L.TRIP_NO_MARK)
        return false
    end
    trip.note = note
    FGPS:Print(L.TRIP_MARKED, note)
    return true
end




local function savedTrips()
    local trips = Util.DeepCopy(SelfTest.trips) or {}
    if openTrip then
        local current = Util.DeepCopy(openTrip)
        current.open = true
        trips[#trips + 1] = current
    end
    return trips
end

function SelfTest.PrintTrips()
    if #SelfTest.trips == 0 and not openTrip then
        FGPS:Print(L.TRIP_NONE)
        return
    end
    for _, trip in ipairs(SelfTest.trips) do FGPS:Print("%s", tripText(trip)) end
    if openTrip then FGPS:Print("%s", tripText(openTrip)) end
end






local function settingDiff(current, defaults, prefix, out)
    for key, want in pairs(defaults) do
        local path = prefix and (prefix .. "." .. tostring(key)) or tostring(key)
        local have = current and current[key]
        if type(want) == "table" then
            if type(have) == "table" then
                settingDiff(have, want, path, out)
            elseif have ~= nil then
                out[#out + 1] = format("%s = %s (default: a table)", path, tostring(have))
            end
        elseif have ~= want then
            out[#out + 1] = format("%s = %s (default %s)", path, tostring(have), tostring(want))
        end
    end
    return out
end

local function nonDefaultSettings()
    local DB = FGPS.DB
    if not (DB and DB.settings and DB.defaults) then return {} end
    local out = settingDiff(DB.settings, DB.defaults.settings, nil, {})
    sort(out)
    return out
end

local function lastLogLines(count)
    local Log = FGPS.Log
    if not Log then return {} end
    local lines = Log:Lines() or {}
    local out = {}
    local first = #lines - count + 1
    if first < 1 then first = 1 end
    for i = first, #lines do
        local entry = lines[i]
        out[#out + 1] = format("[%.1f] %s %s", entry.time or 0, entry.level or "?", entry.text or "")
    end
    return out
end

local function perfCounters()
    local Perf = FGPS.Perf
    if not Perf then return nil end
    local ok, report = pcall(Perf.Report, Perf)
    if not ok or type(report) ~= "table" then return nil end
    local labels = {}
    for i, entry in ipairs(report.labels) do
        labels[i] = format("%s: %d calls, %.2f ms total, %.3f ms avg, %.3f ms max",
            entry.label, entry.count, entry.totalMs, entry.avgMs, entry.maxMs)
    end
    return {
        labels = labels,
        addonKB = report.memory and round1(report.memory.addonKB) or nil,
        luaKB = report.memory and round1(report.memory.luaKB) or nil,
        journeys = report.tripCount,

        allocatedPerJourneyKB = round1(report.tripAllocatedAvgKB),
        worstAllocatedJourneyKB = round1(report.tripAllocatedMaxKB),
        retainedBaselineKB = round1(report.retainedBaselineKB),
        frameBudgetMs = report.frameBudgetMs,
        uptimeSeconds = round1(report.uptime),
    }
end

local function compactResult(result)
    if type(result) ~= "table" then return nil end
    local lines = {}
    for i, entry in ipairs(result.entries) do
        lines[i] = format("%s %s: %s", entry.status, entry.label, entry.detail or "")
    end
    return { pass = result.pass, note = result.note or 0, warn = result.warn, fail = result.fail, skip = result.skip, checks = lines }
end



local function characterSummary()
    local class, faction
    if UnitClass then
        local ok, localised, token = pcall(UnitClass, "player")
        if ok then class = token or localised end
    end
    if UnitFactionGroup then
        local ok, group = pcall(UnitFactionGroup, "player")
        if ok then faction = group end
    end
    return { class = class or "unknown", faction = faction or "unknown" }
end

function SelfTest:BuildSnapshot(result)
    local build = FGPS.build or {}
    local manifest = FGPS.Data and FGPS.Data.manifest
    return {
        generated = stamp(),
        addon = { name = FGPS.name, version = FGPS.version },
        client = {
            version = build.version, build = build.buildNumber, interface = build.interface,
            isForever = build.isForever and true or false,
            locale = GetLocale and GetLocale() or nil,
        },
        character = characterSummary(),
        data = manifest and {
            dataVersion = manifest.dataVersion, clientBuild = manifest.clientBuild,
            interface = manifest.interface, generated = manifest.generated,
            nodes = manifest.counts and manifest.counts.nodes or nil,
            verifiedYards = manifest.counts and manifest.counts.verifiedYards or nil,
        } or nil,
        settings = nonDefaultSettings(),
        lastRoute = self.lastRoute and Util.DeepCopy(self.lastRoute) or nil,
        trips = savedTrips(),
        log = lastLogLines(self.LOG_LINES),
        perf = perfCounters(),
        selfTest = compactResult(result),
    }
end


function SelfTest:WriteReport(result)
    local account = FGPS.DB and FGPS.DB.account
    if type(account) ~= "table" then
        FGPS:Print(L.REPORT_NO_DB)
        return nil
    end
    local snapshot = self:BuildSnapshot(result)
    account.report = snapshot
    FGPS:Print(L.REPORT_WRITTEN, #snapshot.settings, #snapshot.log,
        result and result.pass or 0, result and result.warn or 0, result and result.fail or 0)
    self.PrintTrips()
    return snapshot
end









SelfTest.CLIENT_NOTICE_LIMIT = 20
SelfTest.SESSION_LOG_LINES = 60

local function mentionsAddon(text)
    return type(text) == "string" and text:lower():find(ADDON_NAME:lower(), 1, true) ~= nil
end

local function recordClientNotice(fmt, ...)
    SelfTest.clientNotices = (SelfTest.clientNotices or 0) + 1
    if SelfTest.clientNotices > SelfTest.CLIENT_NOTICE_LIMIT or not FGPS.Log then return end


    FGPS.Log:Warn(fmt, ...)
end

local function onActionBlocked(event, addon, func)
    if addon ~= ADDON_NAME then return end
    recordClientNotice("The client blocked a protected call by this addon: %s (%s)", tostring(func), tostring(event))
end

local function onLuaWarning(_, warnType, text)
    if mentionsAddon(text) then recordClientNotice("Client Lua warning (type %s): %s", tostring(warnType), tostring(text)) end
end





local function chainErrorHandler()
    if SelfTest.errorHandlerChained or not (geterrorhandler and seterrorhandler) then return end
    local previous = geterrorhandler()
    if type(previous) ~= "function" then return end
    SelfTest.errorHandlerChained = true
    seterrorhandler(function(message, ...)
        local forwarded = FGPS.Log and FGPS.Log.forwarding
        if mentionsAddon(message) and not forwarded then pcall(recordClientNotice, "Lua error: %s", tostring(message)) end
        return previous(message, ...)
    end)
end









SelfTest.PLACE_LOG_MAX = 200
SelfTest.PLACE_EVENTS = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "NEW_WMO_CHUNK", "ZONE_CHANGED_NEW_AREA" }
SelfTest.places = {}

local function clientText(fn)
    if type(fn) ~= "function" then return nil end
    local ok, text = pcall(fn)
    if not ok or (issecretvalue and issecretvalue(text)) then return nil end
    return type(text) == "string" and text or nil
end

local function onPlaceChanged(event)
    local entry = { t = round1(GetTime and GetTime() or nil), ev = event,
                    sub = clientText(GetSubZoneText), mini = clientText(GetMinimapZoneText), zone = clientText(GetZoneText) }
    if IsIndoors then
        local ok, v = pcall(IsIndoors)
        if ok and not (issecretvalue and issecretvalue(v)) then entry.indoor = v and true or false end
    end
    local Coords = FGPS.Coords
    if Coords and Coords.PlayerPos then
        local ok, pos = pcall(Coords.PlayerPos)
        if ok and type(pos) == "table" then
            entry.inst, entry.x, entry.y, entry.map = pos.inst, round1(pos.x), round1(pos.y), pos.map
        end
    end

    if Coords and Coords.PlayerPlace then
        local ok, place = pcall(Coords.PlayerPlace)
        if ok and type(place) == "table" then entry.name = place.name end
    end
    local log = SelfTest.places
    log[#log + 1] = entry
    while #log > SelfTest.PLACE_LOG_MAX do table.remove(log, 1) end
end

local function onLogout()
    local account = FGPS.DB and FGPS.DB.account
    if type(account) ~= "table" then return end
    local boot = FGPS.Boot and FGPS.Boot.report
    account.lastSession = {
        began = SelfTest.sessionStart,
        ended = stamp(),
        version = FGPS.version,
        modulesFailed = type(boot) == "table" and boot.failed or nil,
        clientNotices = SelfTest.clientNotices or 0,
        log = lastLogLines(SelfTest.SESSION_LOG_LINES),
        trips = savedTrips(),
        places = Util.DeepCopy(SelfTest.places) or {},
    }
end




local function onRoute(event, route)
    local summary = summariseRoute(route)
    if summary then SelfTest.lastRoute = summary end
    if event == "ROUTE_STARTED" or event == "ROUTE_UPDATED" then SelfTest.NoteTrip(route) end
end

local function onArrived(_, _, isFinal)
    if isFinal then SelfTest.CloseTrip() end
end

local function onCancelled()
    SelfTest.CloseTrip()
end

function SelfTest:Init()
    if not self.sessionCounted then
        self.sessionCounted = true
        SelfTest.CountSession()
    end
    if FGPS.Events and not self.eventsBound then
        self.eventsBound = true
        FGPS.Events:Register("ROUTE_STARTED", onRoute, self)
        FGPS.Events:Register("ROUTE_UPDATED", onRoute, self)
        FGPS.Events:Register("ROUTE_PREVIEW", onRoute, self)
        FGPS.Events:Register("NAV_OFF_ROUTE", function() SelfTest.CountOffRoute() end, self)
        FGPS.Events:Register("NAV_RECALC_DONE", function() SelfTest.CountRecalc() end, self)
        FGPS.Events:Register("NAV_ARRIVED", onArrived, self)
        FGPS.Events:Register("NAV_CANCELLED", onCancelled, self)
        FGPS.Events:Register("WORLD_ENTERED", onWorldEntered, self)
        FGPS.Events:RegisterWoW("ADDON_ACTION_BLOCKED", onActionBlocked, self)
        FGPS.Events:RegisterWoW("ADDON_ACTION_FORBIDDEN", onActionBlocked, self)
        FGPS.Events:RegisterWoW("LUA_WARNING", onLuaWarning, self)
        FGPS.Events:RegisterWoW("PLAYER_LOGOUT", onLogout, self)
        for _, event in ipairs(SelfTest.PLACE_EVENTS) do FGPS.Events:RegisterWoW(event, onPlaceChanged, self) end
        chainErrorHandler()
    end
end




function SelfTest:IsRunning()
    return self.last ~= nil and not self.last.done
end

local function start(onDone)
    if SelfTest:IsRunning() then
        FGPS:Print(L.SELFTEST_RUNNING)
        return
    end
    SelfTest:Run({ onDone = onDone })
end

FGPS.Slash.Register("selftest", function()
    start(function(result) SelfTest:Print(result) end)
end, L.HELP_SELFTEST)

FGPS.Slash.Register("report", function()
    start(function(result)
        SelfTest:Print(result)
        SelfTest:WriteReport(result)
    end)
end, L.HELP_REPORT)

FGPS.Slash.Register("mark", function(args)
    local note = type(args) == "string" and args:match("^%s*(.-)%s*$") or ""
    if note == "" then note = "marked" end
    SelfTest.MarkTrip(note)
end, L.HELP_MARK)
