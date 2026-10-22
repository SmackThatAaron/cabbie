





local ADDON_NAME, FGPS = ...

local debugprofilestop = debugprofilestop
local coroutine, pcall, type, select, unpack = coroutine, pcall, type, select, unpack

local MIN_BUDGET_MS, MAX_BUDGET_MS, DEFAULT_BUDGET_MS = 1, 8, 4
local MIN_MAX_MS, MAX_MAX_MS, DEFAULT_MAX_MS = 4, 16, 12

local Scheduler = {
    tasks = {},
    frameBudgetMs = DEFAULT_BUDGET_MS,
    frameBudgetMaxMs = DEFAULT_MAX_MS,
    spareFrame = true,
    routeBudget = DEFAULT_BUDGET_MS,
    frameStart = 0,
    current = nil,
    rotation = 0,
    frame = nil,
    stats = { started = 0, completed = 0, failed = 0, cancelled = 0, sliceMs = 0, slices = 0 },
}
FGPS.Scheduler = Scheduler

local function clampMax(ms)
    ms = tonumber(ms) or DEFAULT_MAX_MS
    if ms < MIN_MAX_MS then ms = MIN_MAX_MS end
    if ms > MAX_MAX_MS then ms = MAX_MAX_MS end
    return ms
end

local function spareWanted()
    local DB = FGPS.DB
    if DB and DB.Get then
        local value = DB:Get("perf.spareFrame")
        if value ~= nil then return value and true or false end
    end
    return Scheduler.spareFrame ~= false
end

local function maxBudget()
    local DB = FGPS.DB
    local ms = DB and DB.Get and DB:Get("perf.frameBudgetMaxMs")
    if ms == nil then ms = Scheduler.frameBudgetMaxMs end
    return clampMax(ms)
end

local function frameShown(name)
    local frame = _G[name]
    if type(frame) ~= "table" or type(frame.IsShown) ~= "function" then return false end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and shown and true or false
end



local function playerBusy()
    if InCombatLockdown and InCombatLockdown() then return true end
    if frameShown("CinematicFrame") or frameShown("MovieFrame") then return true end
    if frameShown("TaxiFrame") or frameShown("FlightMapFrame") then return true end
    if InCinematic then
        local ok, value = pcall(InCinematic)
        if ok and value then return true end
    end
    return false
end

local function readFps()
    if not GetFramerate then return nil end
    local ok, value = pcall(GetFramerate)
    if ok and type(value) == "number" then return value end
    return nil
end





local function routeBudgetNow()
    local base = Scheduler.frameBudgetMs
    if not spareWanted() or playerBusy() then return base end
    local cap = maxBudget()
    if cap < base then cap = base end
    local fps = readFps()
    if not fps or fps < 30 then return base end
    if fps >= 50 then return cap end
    return base + (cap - base) * ((fps - 30) / 20)
end

local function logError(fmt, ...)
    if FGPS.Log then FGPS.Log:Error(fmt, ...) end
end

local function safeCall(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn, ...)
    if not ok then logError("Scheduler callback failed: %s", tostring(err)) end
end

local function finish(task, ok, ...)
    if task.done then return end
    task.done = true
    task.finishedAt = debugprofilestop()
    if ok then
        Scheduler.stats.completed = Scheduler.stats.completed + 1
    elseif task.cancelled then
        Scheduler.stats.cancelled = Scheduler.stats.cancelled + 1
    else
        Scheduler.stats.failed = Scheduler.stats.failed + 1
    end
    if not ok and not task.cancelled then
        task.error = (...)
        logError("Scheduler task '%s' failed: %s", tostring(task.label), tostring(task.error))
        safeCall(task.onError, task.error)
    end
    safeCall(task.onDone, ok, ...)
end

local function afterResume(task, ok, ...)
    Scheduler.current = nil
    local spent = debugprofilestop() - task.sliceStart
    task.elapsedMs = task.elapsedMs + spent
    task.slices = task.slices + 1
    Scheduler.stats.sliceMs = Scheduler.stats.sliceMs + spent
    Scheduler.stats.slices = Scheduler.stats.slices + 1
    if not ok then
        finish(task, false, ...)
    elseif coroutine.status(task.co) == "dead" then
        if task.cancelled then
            finish(task, false, "cancelled")
        else
            finish(task, true, ...)
        end
    end
end


local function resume(task)
    if task.done then return end
    if task.cancelled and not task.started then
        finish(task, false, "cancelled")
        return
    end
    if not task.started then
        task.started = true
        task.startedAt = debugprofilestop()
        Scheduler.stats.started = Scheduler.stats.started + 1
    end
    task.sliceStart = debugprofilestop()
    Scheduler.current = task
    afterResume(task, coroutine.resume(task.co, unpack(task.args, 1, task.nargs)))
end

local function onUpdate()
    local tasks = Scheduler.tasks
    local count = #tasks
    if count == 0 then
        if Scheduler.frame then Scheduler.frame:Hide() end
        return
    end
    local frameStart = debugprofilestop()
    Scheduler.frameStart = frameStart

    Scheduler.routeBudget = routeBudgetNow()
    local offset = Scheduler.rotation % count
    for step = 0, count - 1 do
        local task = tasks[((offset + step) % count) + 1]
        if task and not task.done then resume(task) end
        Scheduler.rotation = offset + step + 1
        local cap = Scheduler.frameBudgetMs
        if task and task.label == "route" and not task.budgetFixed then cap = Scheduler.routeBudget end
        if debugprofilestop() - frameStart >= cap then break end
    end
    for i = #tasks, 1, -1 do
        if tasks[i].done then table.remove(tasks, i) end
    end
    if #tasks == 0 then

        Scheduler.rotation = 0
        if Scheduler.frame then Scheduler.frame:Hide() end
    end
end

local function ensureFrame()
    if Scheduler.frame or not CreateFrame then return Scheduler.frame end
    local frame = CreateFrame("Frame")
    frame:Hide()
    frame:SetScript("OnUpdate", onUpdate)
    Scheduler.frame = frame
    return frame
end






function Scheduler:Run(fn, opts, ...)
    assert(type(fn) == "function", "Scheduler:Run: fn must be a function")
    opts = opts or {}
    local task = {
        co = coroutine.create(fn),
        label = opts.label or "task",
        budgetMs = opts.budgetMs or self.frameBudgetMs,

        budgetFixed = opts.budgetMs ~= nil,
        onDone = opts.onDone,
        onError = opts.onError,
        args = { ... },
        nargs = select("#", ...),
        cancelled = false,
        started = false,
        done = false,
        elapsedMs = 0,
        slices = 0,
        queuedAt = debugprofilestop(),
    }
    self.tasks[#self.tasks + 1] = task
    local frame = ensureFrame()
    if frame then frame:Show() end
    return task
end



function Scheduler:Cancel(handle)
    if type(handle) ~= "table" or handle.done then return false end
    handle.cancelled = true
    return true
end

function Scheduler:CancelAll()
    local n = 0
    for _, task in ipairs(self.tasks) do
        if not task.done then task.cancelled = true n = n + 1 end
    end
    return n
end

function Scheduler:IsIdle()
    return #self.tasks == 0
end

function Scheduler:Count()
    return #self.tasks
end



function Scheduler.Yield()
    local task = Scheduler.current
    if not task then return true end
    local now = debugprofilestop()
    local slice, frameCap = task.budgetMs, Scheduler.frameBudgetMs
    if task.label == "route" and not task.budgetFixed then
        slice = Scheduler.routeBudget or slice
        frameCap = slice
    end
    if now - task.sliceStart >= slice or now - Scheduler.frameStart >= frameCap then
        coroutine.yield()
    end
    return not task.cancelled
end

function Scheduler:SetFrameBudget(ms)
    ms = tonumber(ms) or DEFAULT_BUDGET_MS
    if ms < MIN_BUDGET_MS then ms = MIN_BUDGET_MS end
    if ms > MAX_BUDGET_MS then ms = MAX_BUDGET_MS end
    self.frameBudgetMs = ms
    return ms
end

function Scheduler:GetFrameBudget()
    return self.frameBudgetMs
end


function Scheduler:RouteBudget()
    return routeBudgetNow()
end

function Scheduler:SetFrameBudgetMax(ms)
    self.frameBudgetMaxMs = clampMax(ms)
    return self.frameBudgetMaxMs
end


function Scheduler:Step()
    onUpdate()
end

function Scheduler:Stats()
    local s = self.stats
    return { queued = #self.tasks, started = s.started, completed = s.completed, failed = s.failed,
             cancelled = s.cancelled, sliceMs = s.sliceMs, slices = s.slices, frameBudgetMs = self.frameBudgetMs }
end

function Scheduler:ResetStats()
    local s = self.stats
    s.started, s.completed, s.failed, s.cancelled, s.sliceMs, s.slices = 0, 0, 0, 0, 0, 0
end


function Scheduler:Init()
    local DB = FGPS.DB
    if DB and DB.initialized then
        self:SetFrameBudget(DB:Get("perf.frameBudgetMs"))
    end
    if FGPS.Events and not self.settingsBound then
        self.settingsBound = true
        FGPS.Events:Register("SETTINGS_CHANGED", function(_, key, value)
            if key == "perf.frameBudgetMs" then
                Scheduler:SetFrameBudget(value)
            elseif key == "*" and FGPS.DB then
                Scheduler:SetFrameBudget(FGPS.DB:Get("perf.frameBudgetMs"))
            end
        end, self)
    end
    ensureFrame()
end
