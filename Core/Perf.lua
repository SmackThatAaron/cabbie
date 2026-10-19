-- Cabbie/Core/Perf.lua
-- Lightweight instrumentation: labelled timings (debugprofilestop), memory samples
-- (UpdateAddOnMemoryUsage/GetAddOnMemoryUsage plus the Lua heap), C_AddOnProfiler metrics when the
-- client provides them, per-journey memory deltas, and the "guidance enabled" switch that lets
-- testers compare frame times with all guidance work turned off.
--
-- Two different memory questions live here and must not be confused:
--   * ALLOCATED per journey (Perf.trips, filled by StartTripCounter/EndTrip). Cheap: no collection,
--     so the figure is mostly garbage the collector has not reached yet. It answers "how much does
--     a journey churn", which is a useful pressure signal, and nothing else.
--   * RETAINED across journeys (Perf:MarkRetained/RetainedSince, "/cabbie perf trip"). This is the
--     figure docs/PERFORMANCE_BUDGETS.md budgets ("<= 50 KB retained (after collectgarbage) across
--     20 consecutive journeys"). It needs a full collection, and a full collection is a visible
--     hitch, so it happens only when a tester asks: one collection for the baseline, one to read
--     the growth since. Two collections cover a whole 20-journey run.
-- The Navigator calls EndTrip with no options on every arrival and every cancel, so every recorded
-- trip delta is churn; the report says so in as many words rather than labelling it "retained".
local ADDON_NAME, FGPS = ...

local L = FGPS.L
local debugprofilestop = debugprofilestop
local pairs, ipairs, type, tostring, format = pairs, ipairs, type, tostring, string.format

local MAX_SAMPLES, MAX_TRIPS = 60, 20
local PROFILER_METRICS = { "SessionAverageTime", "RecentAverageTime", "LastTime", "PeakTime",
                           "CountTimeOver1Ms", "CountTimeOver5Ms", "CountTimeOver10Ms" }


local Perf = {
    enabled = true,          -- settings.perf.instrument
    guidanceEnabled = true,  -- runtime switch consulted by guidance modules (Route block, call-out, lines, voice, pin)
    labels = {},             -- label -> { count, totalMs, maxMs, lastMs }
    active = {},             -- label -> start time of an open Begin()
    samples = {},            -- ring of memory samples, newest last
    trips = {},              -- ALLOCATED KB per completed journey, newest last (see the file header)
    tripCount = 0,           -- journeys ever measured; unlike #trips this is not capped or wiped
    tripStartKB = nil,
    retained = nil,          -- { baseKB, baseTrips, time } once a tester took a baseline
    lastSample = nil,
}
FGPS.Perf = Perf

-------------------------------------------------------------------------------
-- Timing
-------------------------------------------------------------------------------
function Perf:Begin(label)
    if not self.enabled then return end
    self.active[label] = debugprofilestop()
end

-- Returns the elapsed milliseconds of the matching Begin (nil when disabled or unmatched).
function Perf:End(label)
    local start = self.active[label]
    if not start then return nil end
    self.active[label] = nil
    return self:Record(label, debugprofilestop() - start)
end

-- Adds one timing measured by the caller (a data folder's load, timed around LoadAddOn itself).
function Perf:Record(label, elapsed)
    if not self.enabled then return nil end
    local entry = self.labels[label]
    if not entry then
        entry = { count = 0, totalMs = 0, maxMs = 0, lastMs = 0 }
        self.labels[label] = entry
    end
    entry.count = entry.count + 1
    entry.totalMs = entry.totalMs + elapsed
    entry.lastMs = elapsed
    if elapsed > entry.maxMs then entry.maxMs = elapsed end
    return elapsed
end

-- Times a function call under a label and returns its results.
function Perf:Time(label, fn, ...)
    self:Begin(label)
    local results = { pcall(fn, ...) }
    self:End(label)
    if not results[1] then error(results[2], 0) end
    return unpack(results, 2)
end

-------------------------------------------------------------------------------
-- Memory and profiler samples
-------------------------------------------------------------------------------
-- The client charges memory to the add-on whose code allocated it, so the continents' graphs
-- count against their load-on-demand folders (Core/DataLoad.lua); they are added in.
local function addonMemoryKB(collect)
    if collect then collectgarbage("collect") end
    if UpdateAddOnMemoryUsage then UpdateAddOnMemoryUsage() end
    if GetAddOnMemoryUsage then
        local kb = GetAddOnMemoryUsage(FGPS.name)
        if type(kb) == "number" then
            local DataLoad = FGPS.DataLoad
            if DataLoad then
                for addon in pairs(DataLoad.parts) do
                    if DataLoad:State(addon) == "loaded" then
                        local part = GetAddOnMemoryUsage(addon)
                        if type(part) == "number" then kb = kb + part end
                    end
                end
            end
            return kb
        end
    end
    return collectgarbage("count")
end
Perf.AddonMemoryKB = addonMemoryKB

local function profilerMetrics()
    if not (C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric and Enum and Enum.AddOnProfilerMetric) then return nil end
    local out = {}
    for _, name in ipairs(PROFILER_METRICS) do
        local id = Enum.AddOnProfilerMetric[name]
        if id ~= nil then
            local ok, value = pcall(C_AddOnProfiler.GetAddOnMetric, FGPS.name, id)
            if ok and type(value) == "number" then out[name] = value end
        end
    end
    return out
end

function Perf:Sample()
    local sample = {
        time = GetTime and GetTime() or 0,
        addonKB = addonMemoryKB(false),
        luaKB = collectgarbage("count"),
        metrics = profilerMetrics(),
        frameRate = GetFramerate and GetFramerate() or nil,
    }
    self.samples[#self.samples + 1] = sample
    if #self.samples > MAX_SAMPLES then table.remove(self.samples, 1) end
    self.lastSample = sample
    return sample
end

-------------------------------------------------------------------------------
-- Per-journey allocation deltas
-------------------------------------------------------------------------------
function Perf:StartTripCounter(opts)
    self.tripStartKB = addonMemoryKB(opts and opts.collect)
    return self.tripStartKB
end

-- Records the memory ALLOCATED since StartTripCounter and counts the journey. Without
-- opts.collect (how the Navigator calls it, on every arrival and every cancel) the figure
-- includes garbage the collector has not reached, so it is a churn signal and never an answer to
-- the retained-memory budget: that is what MarkRetained/RetainedSince below are for.
-- opts.collect forces a full collection first, which is accurate but costs a frame hitch.
function Perf:EndTrip(opts)
    if not self.tripStartKB then return nil end
    self.tripCount = self.tripCount + 1
    local delta = addonMemoryKB(opts and opts.collect) - self.tripStartKB
    self.tripStartKB = nil
    self.trips[#self.trips + 1] = delta
    if #self.trips > MAX_TRIPS then table.remove(self.trips, 1) end
    return delta
end

-------------------------------------------------------------------------------
-- Retained memory across journeys (the docs/PERFORMANCE_BUDGETS.md leak budget)
-------------------------------------------------------------------------------
-- Collects and remembers the addon's memory as the zero point of a measurement.
function Perf:MarkRetained()
    local kb = addonMemoryKB(true)
    self.retained = { baseKB = kb, baseTrips = self.tripCount, time = GetTime and GetTime() or 0 }
    return kb
end

-- Collects and returns how much memory is retained since the baseline, how many journeys have
-- finished since it was taken, and the absolute figure. Returns nil when no baseline exists.
function Perf:RetainedSince()
    local base = self.retained
    if not base then return nil end
    local kb = addonMemoryKB(true)
    return kb - base.baseKB, self.tripCount - base.baseTrips, kb
end

-------------------------------------------------------------------------------
-- Guidance switch and settings binding
-------------------------------------------------------------------------------
function Perf:SetGuidanceEnabled(enabled)
    enabled = enabled and true or false
    if self.guidanceEnabled == enabled then return enabled end
    self.guidanceEnabled = enabled
    if FGPS.Events then FGPS.Events:Fire("SETTINGS_CHANGED", "perf.guidanceEnabled", enabled) end
    return enabled
end

function Perf:ToggleGuidance()
    return self:SetGuidanceEnabled(not self.guidanceEnabled)
end

function Perf:SetEnabled(enabled)
    self.enabled = enabled and true or false
    if not self.enabled then wipe(self.active) end
    return self.enabled
end

function Perf:Reset()
    wipe(self.labels)
    wipe(self.active)
    wipe(self.samples)
    wipe(self.trips)
    self.lastSample = nil
    self.tripStartKB = nil
    self.tripCount = 0
    self.retained = nil
    if FGPS.Scheduler and FGPS.Scheduler.ResetStats then FGPS.Scheduler:ResetStats() end
end

-------------------------------------------------------------------------------
-- Report
-------------------------------------------------------------------------------
function Perf:Report()
    local labels = {}
    for label, e in pairs(self.labels) do
        labels[#labels + 1] = { label = label, count = e.count, totalMs = e.totalMs, maxMs = e.maxMs, lastMs = e.lastMs,
                                avgMs = e.count > 0 and e.totalMs / e.count or 0 }
    end
    table.sort(labels, function(a, b)
        if a.totalMs ~= b.totalMs then return a.totalMs > b.totalMs end
        return a.label < b.label
    end)
    local tripTotal, tripMax = 0, nil
    for _, delta in ipairs(self.trips) do
        tripTotal = tripTotal + delta
        if not tripMax or delta > tripMax then tripMax = delta end
    end
    local trips = {}
    for i, delta in ipairs(self.trips) do trips[i] = delta end
    return {
        enabled = self.enabled,
        guidanceEnabled = self.guidanceEnabled,
        frameBudgetMs = FGPS.Scheduler and FGPS.Scheduler.frameBudgetMs or nil,
        labels = labels,
        memory = self.lastSample,
        -- Allocated, not retained: the names say so because a reader comparing these against the
        -- 50 KB retained-memory budget would otherwise see a leak that is not there.
        trips = trips,
        tripsAreAllocated = true,
        tripAllocatedAvgKB = #trips > 0 and tripTotal / #trips or nil,
        tripAllocatedMaxKB = tripMax,
        tripCount = self.tripCount,
        retainedBaselineKB = self.retained and self.retained.baseKB or nil,
        retainedBaselineTrips = self.retained and self.retained.baseTrips or nil,
        scheduler = FGPS.Scheduler and FGPS.Scheduler:Stats() or nil,
        uptime = (GetTime and FGPS.loginTime) and (GetTime() - FGPS.loginTime) or nil,
    }
end

function Perf:Print()
    local r = self:Report()
    FGPS:Print(L.PERF_HEADER, r.enabled and L.PERF_ON or L.PERF_OFF, r.guidanceEnabled and L.PERF_ON or L.PERF_OFF, r.frameBudgetMs or 0)
    if #r.labels == 0 then
        FGPS:Print(L.PERF_NO_LABELS)
    else
        for _, e in ipairs(r.labels) do
            FGPS:Print(L.PERF_LABEL_LINE, e.label, e.count, e.totalMs, e.avgMs, e.maxMs)
        end
    end
    if r.memory then
        local age = (GetTime and GetTime() or r.memory.time) - r.memory.time
        FGPS:Print(L.PERF_MEMORY, r.memory.addonKB, r.memory.luaKB, age)
        if r.memory.metrics then
            for _, name in ipairs(PROFILER_METRICS) do
                local value = r.memory.metrics[name]
                if value then FGPS:Print(L.PERF_METRIC, name, value) end
            end
        end
    end
    if #r.trips > 0 then FGPS:Print(L.PERF_TRIPS_ALLOCATED, #r.trips, r.tripAllocatedAvgKB, r.tripAllocatedMaxKB) end
    if r.scheduler then FGPS:Print(L.PERF_SCHEDULER, r.scheduler.queued, r.scheduler.completed, r.scheduler.sliceMs) end
    return r
end

-------------------------------------------------------------------------------
-- Initialisation and slash command ("/cabbie perf [toggle|reset|sample|on|off]")
-------------------------------------------------------------------------------
local function onSettingsChanged(_, key, value)
    if key == "perf.instrument" then
        Perf:SetEnabled(value)
    elseif key == "perf.guidanceEnabled" then
        Perf.guidanceEnabled = value and true or false
    elseif key == "*" and FGPS.DB then
        Perf:SetEnabled(FGPS.DB:Get("perf.instrument") ~= false)
    end
end

function Perf:Init()
    local DB = FGPS.DB
    if DB and DB.initialized then
        self:SetEnabled(DB:Get("perf.instrument") ~= false)
    end
    if FGPS.Events and not self.settingsBound then
        self.settingsBound = true
        FGPS.Events:Register("SETTINGS_CHANGED", onSettingsChanged, self)
    end
end

FGPS.Slash.Register("perf", function(args)
    local word = FGPS.Util.Lower(FGPS.Util.Trim(args))
    if word == "toggle" then
        local enabled = Perf:ToggleGuidance()
        FGPS:Print(enabled and L.PERF_GUIDANCE_ON or L.PERF_GUIDANCE_OFF)
    elseif word == "reset" then
        Perf:Reset()
        FGPS:Print(L.PERF_RESET)
    elseif word == "sample" then
        Perf:Sample()
        FGPS:Print(L.PERF_SAMPLED)
    elseif word == "trip" then
        -- Two calls make one retained-memory measurement: the first collects and remembers the
        -- zero point, the second collects again and reports the growth over the journeys between.
        if Perf.retained then
            local delta, trips = Perf:RetainedSince()
            if trips > 0 then
                FGPS:Print(L.PERF_RETAINED_REPORT, delta, trips, delta / trips)
            else
                FGPS:Print(L.PERF_RETAINED_NO_TRIPS, delta)
            end
        else
            FGPS:Print(L.PERF_RETAINED_BASELINE, Perf:MarkRetained())
        end
    elseif word == "on" or word == "off" then
        local enabled = word == "on"
        if FGPS.DB and FGPS.DB.initialized then FGPS.DB:Set("perf.instrument", enabled) else Perf:SetEnabled(enabled) end
        FGPS:Print(enabled and L.PERF_INSTRUMENT_ON or L.PERF_INSTRUMENT_OFF)
    else
        Perf:Sample()
        Perf:Print()
    end
end, L.HELP_PERF_FULL)
