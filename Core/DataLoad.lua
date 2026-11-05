












local ADDON_NAME, FGPS = ...

local L = FGPS.L
local pairs, ipairs, type = pairs, ipairs, type

local DataLoad = {





    CATALOGUE = {
        [0] = { graph = { "Cabbie_Data_EK", "Cabbie_Data_EK_2", "Cabbie_Data_EK_3", "Cabbie_Data_EK_4", "Cabbie_Data_EK_5" },
                landmarks = { "Cabbie_Landmarks_EK", "Cabbie_Landmarks_EK_2" } },
        [1] = { graph = { "Cabbie_Data_Kalimdor", "Cabbie_Data_Kalimdor_2", "Cabbie_Data_Kalimdor_3",
                          "Cabbie_Data_Kalimdor_4", "Cabbie_Data_Kalimdor_5", "Cabbie_Data_Kalimdor_6" },
                landmarks = { "Cabbie_Landmarks_Kalimdor", "Cabbie_Landmarks_Kalimdor_2" } },
        [2991] = { graph = "Cabbie_Data_Zephras" },
    },



    INSIDE = "Cabbie_Data_Dungeons",


    parts = {},
    byInst = {},
    staging = {},
    indexOwed = {},
}
FGPS.DataLoad = DataLoad



local function addInside(parts, byInst)
    local entry = { addon = DataLoad.INSIDE, part = "inside", maps = {}, index = 1 }
    entry.chain = { entry }
    local listed = FGPS.Data and FGPS.Data.insideMaps
    if type(listed) == "table" then
        for map in pairs(listed) do
            if type(map) == "number" and not byInst[map] then
                entry.maps[map] = true
                byInst[map] = { graph = entry }
            end
        end
    end
    parts[DataLoad.INSIDE] = entry
end

local function buildParts(catalogue)
    local parts, byInst = {}, {}
    for inst, folders in pairs(catalogue) do
        byInst[inst] = {}
        for _, part in ipairs({ "graph", "landmarks" }) do
            local names = folders[part]
            if type(names) == "string" then names = { names } end
            if names then
                local chain = {}
                for k, addon in ipairs(names) do
                    local entry = { addon = addon, inst = inst, part = part, index = k, chain = chain }
                    chain[k] = entry
                    parts[addon] = entry
                end
                byInst[inst][part] = chain[1]
            end
        end
    end
    addInside(parts, byInst)
    DataLoad.parts, DataLoad.byInst, DataLoad.staging = parts, byInst, {}
end
buildParts(DataLoad.CATALOGUE)

local function manifestVersion()
    local manifest = FGPS.Data and FGPS.Data.manifest
    return manifest and manifest.dataVersion
end


local function partPresent(entry)
    local graphs = FGPS.Data and FGPS.Data.graphs
    if entry.part == "inside" then
        if type(graphs) ~= "table" or next(entry.maps) == nil then return false end
        for map in pairs(entry.maps) do
            local g = graphs[map]
            if type(g) ~= "table" or type(g.x) ~= "table" or type(g.y) ~= "table" then return false end
        end
        return true
    end
    local g = graphs and graphs[entry.inst]
    if type(g) ~= "table" then return false end
    if entry.part == "graph" then return type(g.x) == "table" and type(g.y) == "table" end
    return g.lm ~= nil
end



local function present(entry)
    return partPresent(entry) or entry.staged == true
end



local function shipped(entry)
    if entry.part == "inside" then return next(entry.maps) ~= nil end
    local manifest = FGPS.Data and FGPS.Data.manifest
    local instances = manifest and manifest.instances
    return type(instances) ~= "table" or instances[entry.inst] ~= nil
end


local function isInside(inst)
    local row = inst ~= nil and DataLoad.byInst[inst]
    return row and row.graph and row.graph.part == "inside" or false
end



local function homeOf(inst)
    if not isInside(inst) then return inst end
    for _, rec in ipairs(FGPS.Data and FGPS.Data.interiors or {}) do
        if rec.instanceMap == inst and rec.entrance and rec.entrance.inst then return rec.entrance.inst end
    end
    return inst
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
    return entry ~= nil and partPresent(entry)
end


function DataLoad:PartWaiting(entry)
    if partPresent(entry) then return false end
    local unloaded = false
    for _, e in ipairs(entry.chain) do
        local state = self:State(e.addon)
        if state == "unloaded" then
            unloaded = true
        elseif state ~= "loaded" then
            return false
        end
    end
    return unloaded
end


function DataLoad:Folders(inst, part)
    local row = self.byInst[inst]
    local entry = row and row[part or "graph"]
    local out = {}
    for k, e in ipairs(entry and entry.chain or {}) do out[k] = e.addon end
    return out
end








function DataLoad:RegisterData(addonName, dataVersion, data)
    local entry = self.parts[addonName]
    if not entry then return false, "UNKNOWN" end
    if dataVersion ~= manifestVersion() then
        entry.state, entry.reason = "stale", "STALE"
        return false, "STALE"
    end
    if present(entry) then return true end
    local chain = entry.chain
    if #chain > 1 then
        local stage = self.staging[chain]
        if entry.index == 1 then
            local graphs = type(data) == "table" and type(data.graphs) == "table" and data.graphs or nil
            if not (graphs and type(graphs[entry.inst]) == "table") then return false, "BAD_DATA" end
            stage = { data = data, upTo = 1 }
            self.staging[chain] = stage
        elseif not (stage and stage.upTo == entry.index - 1 and stage.data == data) then


            return false, "BAD_DATA"
        else
            stage.upTo = entry.index
        end
        if entry.index < #chain then
            entry.staged, entry.state, entry.reason = true, nil, nil
            return true
        end
        self.staging[chain] = nil
    end
    local graphs = type(data) == "table" and type(data.graphs) == "table" and data.graphs or nil
    if entry.part == "inside" then


        if not graphs or next(entry.maps) == nil then return false, "BAD_DATA" end
        for map in pairs(entry.maps) do
            local g = graphs[map]
            if type(g) ~= "table" or type(g.x) ~= "table" or type(g.y) ~= "table" then return false, "BAD_DATA" end
        end
        FGPS.Data.graphs = FGPS.Data.graphs or {}
        for map in pairs(entry.maps) do FGPS.Data.graphs[map] = graphs[map] end
        entry.state, entry.reason = nil, nil
        if FGPS.Events then FGPS.Events:Fire("DATA_PART_LOADED", nil, "inside") end
        return true
    end
    local g = graphs and graphs[entry.inst]
    if type(g) ~= "table" then return false, "BAD_DATA" end
    FGPS.Data.graphs = FGPS.Data.graphs or {}
    if entry.part == "graph" then
        if type(g.x) ~= "table" or type(g.y) ~= "table" then return false, "BAD_DATA" end
        FGPS.Data.graphs[entry.inst] = g




        local Graph = FGPS.Graph
        if Graph and Graph.Ensure and self.indexLater then
            self.indexOwed[entry.inst] = true
        elseif Graph and Graph.Ensure and not coroutine.running()
            and not (InCombatLockdown and InCombatLockdown()) then
            Graph:Ensure(entry.inst)
        end
    else
        local graph = self.byInst[entry.inst].graph
        if not (graph and partPresent(graph)) then return false, "NO_GRAPH" end
        if type(g.lm) ~= "table" then return false, "BAD_DATA" end
        FGPS.Data.graphs[entry.inst].lm = g.lm
    end
    entry.state, entry.reason = nil, nil
    if FGPS.Events then FGPS.Events:Fire("DATA_PART_LOADED", entry.inst, entry.part) end
    return true
end




function DataLoad:ResumeData(addonName, dataVersion)
    local entry = self.parts[addonName]
    if not entry or (entry.index or 1) < 2 or dataVersion ~= manifestVersion() then return nil end
    local stage = self.staging[entry.chain]
    if not stage or stage.upTo ~= entry.index - 1 then return nil end
    return stage.data
end


function FGPS.RegisterData(addonName, dataVersion, data)
    return DataLoad:RegisterData(addonName, dataVersion, data)
end

function FGPS.ResumeData(addonName, dataVersion)
    return DataLoad:ResumeData(addonName, dataVersion)
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


local function loadNow(entry, addon)
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
        return true, nil, ms
    end
    if entry.state == "stale" then return false, "STALE", ms end
    if not loaded and reason == "DISABLED" then return fail(entry, "disabled", reason), reason, ms end
    if not loaded and reason == "MISSING" then return fail(entry, "missing", reason), reason, ms end
    reason = loaded and "NOT_REGISTERED" or (reason or "NOT_LOADED")
    return fail(entry, "broken", reason), reason, ms
end





function DataLoad:Load(addon, why, position)
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
    local ok, reason, ms = loadNow(entry, addon)
    self.loadFrame = GetTime and GetTime() or nil
    if FGPS.Perf and FGPS.Perf.NoteLoad then
        FGPS.Perf:NoteLoad({ folder = addon, ms = ms, why = why, state = self:State(addon),
                             loading = self.loadingScreen, position = position })
    end
    return ok, reason
end




local function continentName(inst)
    local instances = FGPS.Data and FGPS.Data.instances
    local rec = instances and instances[inst]
    if rec and rec.name then return rec.name end
    return string.format(L["instance %d"], inst)
end
DataLoad.ContinentName = continentName


local function whereOf(entry)
    if entry.part == "inside" then return L["dungeons and raids"] end
    return continentName(entry.inst)
end




local OUT_OF_DATE = { INTERFACE_VERSION = true, DEP_INTERFACE_VERSION = true }
local REFUSED = { CORRUPT = true, BANNED = true, INCOMPATIBLE = true, INSECURE = true,
                  NOT_DEMAND_LOADED = true }

local function brokenMessage(entry, where, addon)
    local reason = entry.reason
    if OUT_OF_DATE[reason] then
        return string.format(L["Cabbie cannot route in %s: the game marks %s as out of date. Tick \"Load out of date AddOns\" in the AddOns list at character select, or install the Cabbie made for this version of the game."], where, addon)
    elseif type(reason) == "string" and reason:sub(1, 4) == "DEP_" then
        return string.format(L["Cabbie cannot route in %s: %s needs another of Cabbie's folders, which is missing or turned off. Reinstall Cabbie with all its folders and turn them all on in the AddOns list at character select."], where, addon)
    elseif REFUSED[reason] then
        return string.format(L["Cabbie cannot route in %s: the game would not load %s. Reinstall Cabbie with all its folders."], where, addon)
    elseif reason == "NO_API" then
        return string.format(L["Cabbie cannot route in %s: this version of the game gives Cabbie no way to load %s."], where, addon)
    end
    return string.format(L["The map of %s did not finish loading. Type /reload to try again."], where)
end


function DataLoad:Message(addon)
    local entry = self.parts[addon]
    if not entry then return nil end
    local state, where = self:State(addon), whereOf(entry)
    if state == "missing" then
        return string.format(L["Cabbie cannot route in %s: its map add-on, %s, is not installed. Reinstall Cabbie with all its folders."], where, addon)
    elseif state == "disabled" then
        return string.format(L["Cabbie cannot route in %s: %s is turned off. Turn it on in the AddOns list at character select."], where, addon)
    elseif state == "stale" then
        return string.format(L["%s is from another version of Cabbie. Reinstall Cabbie so that all its folders match."], addon)
    elseif state == "broken" then
        return brokenMessage(entry, where, addon)
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

local function after(fn)
    C_Timer.After(0, fn)
end



local function frameTaken(self)
    return self.loadFrame ~= nil and GetTime ~= nil and self.loadFrame == GetTime()
end


local function payIndex(self, inst)
    local G = FGPS.Graph
    if self.indexOwed[inst] and G and G.Ensure then
        self.indexOwed[inst] = nil
        if not G:IsLoaded(inst) then
            G:Ensure(inst)
            self.loadFrame = GetTime and GetTime() or nil
        end
    end
end






function DataLoad:LoadPlayerContinent(spread)
    local Coords = FGPS.Coords
    local inst = Coords and Coords.PlayerXY and select(3, Coords.PlayerXY())


    if inst == nil and FGPS.Perf and FGPS.Perf.NoteLoad and not (Coords and Coords.IsInstanced and Coords.IsInstanced()) then
        FGPS.Perf:NoteLoad({ why = "world", position = false, loading = self.loadingScreen })
    end

    local first = inst and not isInside(inst) and self.byInst[inst] and self.byInst[inst].graph
    if not first then return end
    local need = {}
    for _, entry in ipairs(first.chain) do
        local state = self:State(entry.addon)
        if state ~= "loaded" then
            if state ~= "unloaded" then return end
            need[#need + 1] = entry.addon
        end
    end
    if #need == 0 and not self.indexOwed[inst] then return end
    if InCombatLockdown and InCombatLockdown() then
        if not self.worldWaiting then
            self.worldWaiting = true
            combatWaiters[#combatWaiters + 1] = function()
                self.worldWaiting = nil
                self:LoadPlayerContinent(true)
            end
        end
        return
    end
    if not spread then
        for _, addon in ipairs(need) do
            if not self:Load(addon, "world", true) then
                self.staging[first.chain] = nil
                self:Announce(addon)
                return
            end
        end
        return payIndex(self, inst)
    end


    local spreading = self.worldSpreading or {}
    self.worldSpreading = spreading
    if spreading[inst] then return end
    spreading[inst] = true
    local k = 0
    local step
    step = function()

        if InCombatLockdown and InCombatLockdown() then
            combatWaiters[#combatWaiters + 1] = step
            return
        end
        local nextUp = need[k + 1]
        local work = nextUp and self:State(nextUp) == "unloaded" or not nextUp and self.indexOwed[inst]
        if work and frameTaken(self) then return after(step) end
        k = k + 1
        local addon = need[k]
        if not addon then
            spreading[inst] = nil
            return payIndex(self, inst)
        end
        self.indexLater = true
        local ok = self:Load(addon, "world", true)
        self.indexLater = nil
        if not ok then
            spreading[inst] = nil
            self.staging[first.chain] = nil
            return self:Announce(addon)
        end
        after(step)
    end
    after(step)
end







function DataLoad:LoadInside(map, wanted)
    if not isInside(map) then return end
    local addon = self.INSIDE
    if self:State(addon) ~= "unloaded" then return end
    if InCombatLockdown and InCombatLockdown() then
        local waiting = self.insideWaiting
        self.insideWaiting = { map = map, wanted = wanted }
        if not waiting then
            combatWaiters[#combatWaiters + 1] = function()
                local last = self.insideWaiting
                self.insideWaiting = nil
                if last and (not last.wanted or last.wanted(last.map)) then self:LoadInside(last.map, last.wanted) end
            end
        end
        return
    end
    if not self:Load(addon, "inside") then self:Announce(addon) end
end










function DataLoad:PartsFor(handle)
    local insts, seen, whyOf = {}, {}, {}
    local function add(inst, why)
        if inst ~= nil and not seen[inst] and self:Knows(inst) then
            seen[inst] = true
            insts[#insts + 1] = inst
            whyOf[inst] = isInside(inst) and "inside" or why
        end
    end
    local origin, stops = handle.origin, handle.stops or {}
    local request = handle.request or {}
    local access = handle.access or request.access or {}
    local G = FGPS.Graph
    local ends = { origin }
    for _, stop in ipairs(stops) do ends[#ends + 1] = stop end
    local leaves = false
    local home = origin and homeOf(origin.inst)
    for k, p in ipairs(ends) do
        local why = k == 1 and "origin" or "stop"
        add(p.inst, why)


        add(homeOf(p.inst), why)
        if origin and homeOf(p.inst) ~= home then leaves = true end
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
            add(e.inst, "teleport")
            leaves = true
        end
    end
    if leaves or handle.needsJoined then


        local only = not leaves and handle.joinedInsts or nil
        local all = {}
        for inst in pairs(self.byInst) do all[#all + 1] = inst end
        table.sort(all)
        for _, inst in ipairs(all) do

            if joined(inst) and not isInside(inst) and (not only or only[inst]) then add(inst, "joined") end
        end
    end
    local out, why = {}, {}
    for _, inst in ipairs(insts) do
        for _, entry in ipairs(self.byInst[inst].graph.chain) do
            if not why[entry.addon] then
                why[entry.addon] = whyOf[inst]
                out[#out + 1] = entry.addon
            end
        end
    end
    local Router = FGPS.Router
    if Router and Router.UsesLandmarks and Router.UsesLandmarks(access, request.variant) then
        for _, inst in ipairs(insts) do
            local marks = self.byInst[inst].landmarks
            for _, entry in ipairs(marks and marks.chain or {}) do
                out[#out + 1] = entry.addon
                why[entry.addon] = "landmarks"
            end
        end
    end
    return out, why
end


local function waitForCombat(handle, addon, resume)
    if handle.waitingForData ~= "combat" then
        handle.waitingForData = "combat"
        local entry = DataLoad.parts[addon]
        if entry and handle.request and handle.request.reason ~= "alt" then


            handle.waitingText = string.format(L["Loading the map of %s when you leave combat."], whereOf(entry))
        end
        if FGPS.Events then FGPS.Events:Fire("ROUTE_WAITING", handle, "combat") end
    end
    combatWaiters[#combatWaiters + 1] = resume
end







function DataLoad:Hold(handle, onReady)
    if not (C_Timer and C_Timer.After) then return false end
    local need, owed = {}, {}
    local parts, why = self:PartsFor(handle)
    for _, addon in ipairs(parts) do
        local entry = self.parts[addon]
        if self:State(addon) ~= "loaded" then
            need[#need + 1] = addon
        elseif entry.part == "graph" and entry.index == #entry.chain and self.indexOwed[entry.inst] and not owed[entry.inst]
            and not (FGPS.Graph and FGPS.Graph:IsLoaded(entry.inst)) then

            owed[entry.inst] = true
            need[#need + 1] = { index = entry.inst }
        end
    end
    if #need == 0 then return false end



    local points = {}
    if handle.origin then points[1] = handle.origin end
    for _, stop in ipairs(handle.stops or {}) do points[#points + 1] = stop end
    local ends = {}
    for _, p in ipairs(points) do ends[p.inst] = true end
    for _, p in ipairs(points) do
        if isInside(p.inst) then
            for _, q in ipairs(points) do
                if q.inst ~= p.inst then ends[homeOf(p.inst)] = true break end
            end
        end
    end
    local function gone() return handle.cancelled or handle.done end
    local step
    step = function()
        if gone() then return end
        local item = need[1]
        local waitFor = type(item) == "table" and self.byInst[item.index].graph.addon or item
        if InCombatLockdown and InCombatLockdown() then return waitForCombat(handle, waitFor, step) end

        local work = type(item) == "table" and self.indexOwed[item.index] or type(item) == "string" and self:State(item) == "unloaded"
        if work and frameTaken(self) then return after(step) end
        handle.waitingForData = true
        table.remove(need, 1)
        if type(item) == "table" then


            payIndex(self, item.index)
            if #need > 0 then return after(step) end
            return after(function()
                if gone() then return end
                handle.waitingForData = nil
                onReady(nil)
            end)
        end
        local addon = item
        self.indexLater = true
        local ok = self:Load(addon, why[addon])
        self.indexLater = nil
        local entry = self.parts[addon]
        if ok and entry.part == "graph" and self.indexOwed[entry.inst] then
            table.insert(need, 1, { index = entry.inst })
        end
        if not ok then



            for k = #need, 1, -1 do
                local other = type(need[k]) == "string" and self.parts[need[k]]
                if other and (other.chain == entry.chain or (entry.part == "graph" and other.inst == entry.inst)) then
                    table.remove(need, k)
                end
            end
            self.staging[entry.chain] = nil
        end
        if not ok and entry.part ~= "landmarks" then
            self:Announce(addon)
            local needed = ends[entry.inst]
            for map in pairs(entry.maps or {}) do needed = needed or ends[map] end
            if needed then
                local message = self:Message(addon) or string.format(L["No navigation data is available for %s."],
                    whereOf(entry))
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


    local G = FGPS.Graph
    if link.kind == 7 and G and (isInside((G:Split(link.from))) or isInside((G:Split(link.to)))) then
        return nil
    end
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











function DataLoad.VisitBounds(inst, a, b, access, variant)
    local G, C = FGPS.Graph, FGPS.Cost
    local out = {}
    local cross = G and G.CrossLinks and G:CrossLinks(inst)
    if not (cross and C) then return out end
    local speed = variant == "no_flight" and C.GroundSpeed(access) or C.MaxSpeed(access)
    local function walk(link, p)
        local dx, dy = link.x - p.x, link.y - p.y
        return math.sqrt(dx * dx + dy * dy) / speed
    end
    local function across(m) return m ~= inst and DataLoad:Knows(m) and not isInside(m) end

    local away, back, ride = {}, {}, {}
    local function addRide(from, to, s)
        ride[from] = ride[from] or {}
        if not ride[from][to] or s < ride[from][to] then ride[from][to] = s end
    end
    for _, link in ipairs(cross.out) do
        local m = (G:Split(link.to))
        local s = across(m) and crossingSeconds(link, access, variant)
        if s then
            addRide(inst, m, s)
            s = s + walk(link, a)
            if not away[m] or s < away[m] then away[m] = s end
        end
    end
    for _, link in ipairs(cross.into) do
        local m = (G:Split(link.from))
        local s = across(m) and crossingSeconds(link, access, variant)
        if s then
            addRide(m, inst, s)
            s = s + walk(link, b)
            if not back[m] or s < back[m] then back[m] = s end
        end
    end

    for _, row in ipairs(FGPS.Data and FGPS.Data.links or {}) do
        local from, to = row[1], row[3]
        if from ~= to and across(from) and across(to) then
            local s = crossingSeconds({ from = G:Key(from, row[2]), to = G:Key(to, row[4]), kind = row[5],
                                        seconds = row[6], transportID = row[7] }, access, variant)
            if s then addRide(from, to, s) end
        end
    end
    local maps = {}
    for m in pairs(DataLoad.byInst) do if across(m) then maps[#maps + 1] = m end end



    for _ = 1, #maps + 1 do
        for from, row in pairs(ride) do
            for to, s in pairs(row) do
                if away[from] and (not away[to] or away[from] + s < away[to]) then away[to] = away[from] + s end
                if back[to] and (not back[from] or s + back[to] < back[from]) then back[from] = s + back[to] end
            end
        end
    end
    for _, m in ipairs(maps) do
        out[m] = (away[m] and back[m]) and away[m] + back[m] or math.huge
    end
    return out
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
    local waiting = {}
    for inst, row in pairs(self.byInst) do
        if inst ~= origin.inst and not isInside(inst) and row.graph and self:PartWaiting(row.graph)
            and G and G:InstancesConnected(origin.inst, inst) then
            waiting[inst] = true
        end
    end
    if next(waiting) == nil then return false end
    local seconds = route.totalSeconds
    local low, prev = math.huge, origin
    for _, stop in ipairs(stops) do
        local bound = DataLoad.DetourBound(origin.inst, prev, stop, access, variant)
        if bound < low then low = bound end
        prev = stop
    end
    if low >= seconds then return false end

    local visits = {}
    prev = origin
    for _, stop in ipairs(stops) do
        for m, s in pairs(DataLoad.VisitBounds(origin.inst, prev, stop, access, variant)) do
            if not visits[m] or s < visits[m] then visits[m] = s end
        end
        prev = stop
    end
    local only, wanted = {}, false
    for m, s in pairs(visits) do
        if s < seconds then
            only[m] = true
            if waiting[m] then wanted = true end
        end
    end

    if not wanted then return false end
    handle.needsJoined, handle.joinedInsts = true, only
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



function DataLoad:UseInsideForTest(insideMaps)
    local saved = FGPS.Data.insideMaps
    FGPS.Data.insideMaps = insideMaps
    buildParts(self.CATALOGUE)
    return function()
        FGPS.Data.insideMaps = saved
        buildParts(self.CATALOGUE)
    end
end




function DataLoad:ForgetForTest(inst, part)

    local row = self.byInst[inst]
    for _, which in ipairs(part == "landmarks" and { "landmarks" } or { "graph", "landmarks" }) do
        local first = row and row[which]
        for _, entry in ipairs(first and first.chain or {}) do entry.staged = nil end
        if first then self.staging[first.chain] = nil end
    end
    if part ~= "landmarks" then self.indexOwed[inst] = nil end
    local graphs = FGPS.Data and FGPS.Data.graphs
    local g = graphs and graphs[inst]
    if type(g) ~= "table" then return function() end end
    local G = FGPS.Graph
    local function drop()
        if G then G._taxiIndex, G._transportIndex = nil, nil end
        g._lm, g._lmCells, g._lmRoads = nil, nil, nil
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

    addInside(self.parts, self.byInst)
    if FGPS.Events then
        local function fightOver()
            if #combatWaiters == 0 then return end
            local waiters = combatWaiters
            combatWaiters = {}
            for _, resume in ipairs(waiters) do after(resume) end
        end


        FGPS.Events:Register("WORLD_ENTERED", function()
            if not (InCombatLockdown and InCombatLockdown()) then fightOver() end
            DataLoad:LoadPlayerContinent()
        end, self)
        FGPS.Events:Register("COMBAT_STATE", function(_, inCombat)
            if not inCombat then fightOver() end
        end, self)


        FGPS.Events:RegisterWoW("LOADING_SCREEN_ENABLED", function() DataLoad.loadingScreen = true end, self)
        FGPS.Events:RegisterWoW("LOADING_SCREEN_DISABLED", function() DataLoad.loadingScreen = false end, self)
    end
end
