







local ADDON_NAME, FGPS = ...

local L = FGPS.L
local pairs, ipairs, type = pairs, ipairs, type

local DataLoad = {


    CATALOGUE = {
        [0] = { graph = "Cabbie_Data_EK", landmarks = "Cabbie_Landmarks_EK" },
        [1] = { graph = "Cabbie_Data_Kalimdor", landmarks = "Cabbie_Landmarks_Kalimdor" },
        [2991] = { graph = "Cabbie_Data_Zephras" },
    },
    parts = {},
    byInst = {},
}
FGPS.DataLoad = DataLoad

local function buildParts(catalogue)
    local parts, byInst = {}, {}
    for inst, folders in pairs(catalogue) do
        byInst[inst] = {}
        for _, part in ipairs({ "graph", "landmarks" }) do
            local addon = folders[part]
            if addon then
                local entry = { addon = addon, inst = inst, part = part }
                parts[addon] = entry
                byInst[inst][part] = entry
            end
        end
    end
    DataLoad.parts, DataLoad.byInst = parts, byInst
end
buildParts(DataLoad.CATALOGUE)

local function manifestVersion()
    local manifest = FGPS.Data and FGPS.Data.manifest
    return manifest and manifest.dataVersion
end

local function present(entry)
    local graphs = FGPS.Data and FGPS.Data.graphs
    local g = graphs and graphs[entry.inst]
    if type(g) ~= "table" then return false end
    if entry.part == "graph" then return type(g.x) == "table" and type(g.y) == "table" end
    return g.lm ~= nil
end


local function shipped(entry)
    local manifest = FGPS.Data and FGPS.Data.manifest
    local instances = manifest and manifest.instances
    return type(instances) ~= "table" or instances[entry.inst] ~= nil
end




function DataLoad:PartOf(addon)
    return self.parts[addon]
end

function DataLoad:Folder(inst, part)
    local row = self.byInst[inst]
    local entry = row and row[part or "graph"]
    return entry and entry.addon or nil
end


function DataLoad:Knows(inst)
    return self.byInst[inst] ~= nil and self.byInst[inst].graph ~= nil
end



function DataLoad:State(addon)
    local entry = self.parts[addon]
    if not entry then return nil end
    if present(entry) then return "loaded" end
    if entry.state then return entry.state end
    if not shipped(entry) then return "absent" end
    return "unloaded"
end

function DataLoad:IsLoaded(inst, part)
    local row = self.byInst[inst]
    local entry = row and row[part or "graph"]
    return entry ~= nil and present(entry)
end






function DataLoad:RegisterData(addonName, dataVersion, data)
    local entry = self.parts[addonName]
    if not entry then return false, "UNKNOWN" end
    if dataVersion ~= manifestVersion() then
        entry.state, entry.reason = "stale", "STALE"
        return false, "STALE"
    end
    if present(entry) then return true end
    local graphs = type(data) == "table" and type(data.graphs) == "table" and data.graphs or nil
    local g = graphs and graphs[entry.inst]
    if type(g) ~= "table" then return false, "BAD_DATA" end
    FGPS.Data.graphs = FGPS.Data.graphs or {}
    if entry.part == "graph" then
        if type(g.x) ~= "table" or type(g.y) ~= "table" then return false, "BAD_DATA" end
        FGPS.Data.graphs[entry.inst] = g



        local Graph = FGPS.Graph
        if Graph and Graph.Ensure and not coroutine.running()
            and not (InCombatLockdown and InCombatLockdown()) then
            Graph:Ensure(entry.inst)
        end
    else
        local graph = self.byInst[entry.inst].graph
        if not (graph and present(graph)) then return false, "NO_GRAPH" end
        if type(g.lm) ~= "table" then return false, "BAD_DATA" end
        FGPS.Data.graphs[entry.inst].lm = g.lm
    end
    entry.state, entry.reason = nil, nil
    if FGPS.Events then FGPS.Events:Fire("DATA_PART_LOADED", entry.inst, entry.part) end
    return true
end


function FGPS.RegisterData(addonName, dataVersion, data)
    return DataLoad:RegisterData(addonName, dataVersion, data)
end








local function loadAddOn(name)
    if coroutine.running() then return false, "IN_COROUTINE" end
    if InCombatLockdown and InCombatLockdown() then return false, "COMBAT" end
    local api = C_AddOns and C_AddOns.LoadAddOn
    if type(api) ~= "function" then return false, "NO_API" end
    local started = debugprofilestop and debugprofilestop()
    local ok, loaded, reason = pcall(api, name)
    local ms = started and (debugprofilestop() - started)
    if not ok then return false, "ERROR", ms end
    return loaded and true or false, reason, ms
end

local function addonMetadata(name, field)
    local api = C_AddOns and C_AddOns.GetAddOnMetadata
    if type(api) ~= "function" then return nil end
    local ok, value = pcall(api, name, field)
    return ok and value or nil
end

local function addonExists(name)
    local api = C_AddOns and C_AddOns.DoesAddOnExist
    if type(api) ~= "function" then return true end
    local ok, exists = pcall(api, name)
    return not ok or exists and true or false
end

local function fail(entry, state, reason)
    entry.state, entry.reason = state, reason
    return false, reason
end




function DataLoad:Load(addon)
    local entry = self.parts[addon]
    if not entry then return false, "UNKNOWN" end
    local state = self:State(addon)
    if state == "loaded" then return true end
    if state == "absent" then return false, "ABSENT" end
    if state ~= "unloaded" then return false, entry.reason end
    if coroutine.running() then
        if FGPS.Log then FGPS.Log:Error("DataLoad: %s was asked for inside a coroutine", addon) end
        return false, "IN_COROUTINE"
    end
    if InCombatLockdown and InCombatLockdown() then return false, "COMBAT" end
    if not addonExists(addon) then return fail(entry, "missing", "MISSING") end
    local stamp = addonMetadata(addon, "X-Cabbie-DataVersion")
    if stamp and stamp ~= manifestVersion() then return fail(entry, "stale", "STALE") end
    local loaded, reason, ms = loadAddOn(addon)
    if ms then
        entry.ms = ms
        if FGPS.Perf and FGPS.Perf.Record then FGPS.Perf:Record("data_load " .. addon, ms) end
    end
    if present(entry) then
        entry.state, entry.reason = nil, nil
        return true
    end
    if entry.state == "stale" then return false, "STALE" end
    if not loaded and reason == "DISABLED" then return fail(entry, "disabled", reason) end
    if not loaded and reason == "MISSING" then return fail(entry, "missing", reason) end
    return fail(entry, "broken", loaded and "NOT_REGISTERED" or (reason or "NOT_LOADED"))
end




local function continentName(inst)
    local instances = FGPS.Data and FGPS.Data.instances
    local rec = instances and instances[inst]
    if rec and rec.name then return rec.name end
    return string.format(L["instance %d"], inst)
end
DataLoad.ContinentName = continentName


function DataLoad:Message(addon)
    local entry = self.parts[addon]
    if not entry then return nil end
    local state, where = self:State(addon), continentName(entry.inst)
    if state == "missing" then
        return string.format(L["Cabbie cannot route in %s: its map add-on, %s, is not installed. Reinstall Cabbie with all its folders."], where, addon)
    elseif state == "disabled" then
        return string.format(L["Cabbie cannot route in %s: %s is turned off. Turn it on in the AddOns list at character select."], where, addon)
    elseif state == "stale" then
        return string.format(L["%s is from another version of Cabbie. Reinstall Cabbie so that all its folders match."], addon)
    elseif state == "broken" then
        return string.format(L["The map of %s did not finish loading. Type /reload to try again."], where)
    end
    return nil
end

DataLoad.announced = {}


function DataLoad:Announce(addon)
    local message = self:Message(addon)
    if not message or self.announced[addon] then return end
    self.announced[addon] = true
    FGPS:Print(message)
end




local combatWaiters = {}




function DataLoad:LoadPlayerContinent()
    local Coords = FGPS.Coords
    local inst = Coords and Coords.PlayerXY and select(3, Coords.PlayerXY())
    local addon = inst and self:Folder(inst, "graph")
    if not addon or self:State(addon) ~= "unloaded" then return end
    if InCombatLockdown and InCombatLockdown() then
        if not self.worldWaiting then
            self.worldWaiting = true
            combatWaiters[#combatWaiters + 1] = function()
                self.worldWaiting = nil
                self:LoadPlayerContinent()
            end
        end
        return
    end
    if not self:Load(addon) then self:Announce(addon) end
end









function DataLoad:PartsFor(handle)
    local insts, seen = {}, {}
    local function add(inst)
        if inst ~= nil and not seen[inst] and self:Knows(inst) then
            seen[inst] = true
            insts[#insts + 1] = inst
        end
    end
    local origin, stops = handle.origin, handle.stops or {}
    local request = handle.request or {}
    local access = handle.access or request.access or {}
    local G = FGPS.Graph
    local ends = { origin }
    for _, stop in ipairs(stops) do ends[#ends + 1] = stop end
    local leaves = false
    for _, p in ipairs(ends) do
        add(p.inst)
        if origin and p.inst ~= origin.inst then leaves = true end
    end
    local function joined(inst)
        for _, p in ipairs(ends) do
            if G and G:InstancesConnected(p.inst, inst) then return true end
        end
        return false
    end
    local t = access.transports or {}
    local teleports = {}
    if access.hearth and t.hearth ~= false then teleports[#teleports + 1] = access.hearth end
    if t.spells ~= false and type(access.spells) == "table" then
        for _, sp in ipairs(access.spells) do teleports[#teleports + 1] = sp end
    end
    local maxWait = FGPS.Const and FGPS.Const.TELEPORT_MAX_WAIT or 120
    for _, e in ipairs(teleports) do
        local remaining = e.ready and 0 or (tonumber(e.cdRemaining) or math.huge)
        if e.inst and remaining < maxWait and joined(e.inst) then
            add(e.inst)
            leaves = true
        end
    end
    if leaves or handle.needsJoined then
        local all = {}
        for inst in pairs(self.byInst) do all[#all + 1] = inst end
        table.sort(all)
        for _, inst in ipairs(all) do
            if joined(inst) then add(inst) end
        end
    end
    local out = {}
    for _, inst in ipairs(insts) do out[#out + 1] = self.byInst[inst].graph.addon end
    local Router = FGPS.Router
    if Router and Router.UsesLandmarks and Router.UsesLandmarks(access, request.variant) then
        for _, inst in ipairs(insts) do
            local marks = self.byInst[inst].landmarks
            if marks then out[#out + 1] = marks.addon end
        end
    end
    return out
end

local function after(fn)
    C_Timer.After(0, fn)
end


local function waitForCombat(handle, addon, resume)
    if handle.waitingForData ~= "combat" then
        handle.waitingForData = "combat"
        if FGPS.Events then FGPS.Events:Fire("ROUTE_WAITING", handle, "combat") end
        local entry = DataLoad.parts[addon]
        if entry and handle.request and handle.request.reason ~= "alt" then
            FGPS:Print(L["Loading the map of %s when you leave combat."], continentName(entry.inst))
        end
    end
    combatWaiters[#combatWaiters + 1] = resume
end







function DataLoad:Hold(handle, onReady)
    if not (C_Timer and C_Timer.After) then return false end
    local need = {}
    for _, addon in ipairs(self:PartsFor(handle)) do
        if self:State(addon) ~= "loaded" then need[#need + 1] = addon end
    end
    if #need == 0 then return false end
    local ends = {}
    if handle.origin then ends[handle.origin.inst] = true end
    for _, stop in ipairs(handle.stops or {}) do ends[stop.inst] = true end
    local function gone() return handle.cancelled or handle.done end
    local step
    step = function()
        if gone() then return end
        if InCombatLockdown and InCombatLockdown() then return waitForCombat(handle, need[1], step) end
        handle.waitingForData = true
        local addon = table.remove(need, 1)
        local ok = self:Load(addon)
        local entry = self.parts[addon]
        if not ok and entry.part == "graph" then
            self:Announce(addon)
            if ends[entry.inst] then
                local message = self:Message(addon) or string.format(L["No navigation data is available for %s."],
                    continentName(entry.inst))
                handle.waitingForData = nil
                return onReady({ code = "NO_DATA", message = message, folder = addon })
            end
        end
        if #need > 0 then return after(step) end
        after(function()
            if gone() then return end
            handle.waitingForData = nil
            onReady(nil)
        end)
    end
    handle.waitingForData = true
    after(step)
    return true
end






local function crossingSeconds(link, access, variant)
    local C, A = FGPS.Cost, FGPS.Access
    if link.kind == 9 and variant == "no_boat" then return nil end
    local transports = FGPS.Data and FGPS.Data.transports
    local rec = link.transportID and transports and transports[link.transportID]
    if rec and A and not A:CanUseTransport(access, rec) then return nil end
    return C.EdgeSeconds(link.kind, nil, access, link.seconds, rec)
end






function DataLoad.DetourBound(inst, a, b, access, variant)
    local G, C = FGPS.Graph, FGPS.Cost
    local cross = G and G.CrossLinks and G:CrossLinks(inst)
    if not (cross and C) then return math.huge end
    local speed = variant == "no_flight" and C.GroundSpeed(access) or C.MaxSpeed(access)
    local function quickest(links, p)
        local low = math.huge
        for _, link in ipairs(links) do
            local s = crossingSeconds(link, access, variant)
            if s then
                local dx, dy = link.x - p.x, link.y - p.y
                s = s + math.sqrt(dx * dx + dy * dy) / speed
                if s < low then low = s end
            end
        end
        return low
    end
    return quickest(cross.out, a) + quickest(cross.into, b)
end






function DataLoad:WantsJoined(handle, route)
    if handle.needsJoined or type(route) ~= "table" or type(route.totalSeconds) ~= "number" then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    local origin, stops = handle.origin, handle.stops or {}
    local request = handle.request or {}
    local access = handle.access or request.access or {}
    local variant = request.variant
    if not origin or variant == "no_boat" then return false end
    for _, stop in ipairs(stops) do
        if stop.inst ~= origin.inst then return false end
    end
    local G = FGPS.Graph
    local waiting = false
    for inst, row in pairs(self.byInst) do
        if inst ~= origin.inst and row.graph and self:State(row.graph.addon) == "unloaded"
            and G and G:InstancesConnected(origin.inst, inst) then
            waiting = true
        end
    end
    if not waiting then return false end
    local low, prev = math.huge, origin
    for _, stop in ipairs(stops) do
        local bound = DataLoad.DetourBound(origin.inst, prev, stop, access, variant)
        if bound < low then low = bound end
        prev = stop
    end
    if low >= route.totalSeconds then return false end
    handle.needsJoined = true
    return true
end





function DataLoad:UseCatalogueForTest(catalogue)
    local saved = self.CATALOGUE
    self.CATALOGUE = catalogue
    buildParts(catalogue)
    return function()
        self.CATALOGUE = saved
        buildParts(saved)
    end
end




function DataLoad:ForgetForTest(inst, part)
    local graphs = FGPS.Data and FGPS.Data.graphs
    local g = graphs and graphs[inst]
    if type(g) ~= "table" then return function() end end
    local G = FGPS.Graph
    local function drop()
        if G then G._taxiIndex, G._transportIndex = nil, nil end
        g._lm, g._lmCells = nil, nil
    end
    if part == "landmarks" then
        local lm = g.lm
        g.lm = nil
        drop()
        return function() g.lm = lm drop() end
    end
    graphs[inst] = nil
    if G then G.loaded[inst] = nil end
    drop()
    return function()
        graphs[inst] = g
        drop()
    end
end

function DataLoad:Init()
    if self.initialized then return end
    self.initialized = true
    if FGPS.Events then
        FGPS.Events:Register("WORLD_ENTERED", function() DataLoad:LoadPlayerContinent() end, self)
        FGPS.Events:Register("COMBAT_STATE", function(_, inCombat)
            if inCombat or #combatWaiters == 0 then return end
            local waiters = combatWaiters
            combatWaiters = {}
            for _, resume in ipairs(waiters) do after(resume) end
        end, self)
    end
end
