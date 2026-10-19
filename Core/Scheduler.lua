





local ADDON_NAME, FGPS = ...

local debugprofilestop = debugprofilestop
local coroutine, pcall, type, select, unpack = coroutine, pcall, type, select, unpack

local MIN_BUDGET_MS, MAX_BUDGET_MS, DEFAULT_BUDGET_MS = 1, 8, 4

local Scheduler = {
    tasks = {},
    frameBudgetMs = DEFAULT_BUDGET_MS,
    frameStart = 0,
    current = nil,
    rotation = 0,
    frame = nil,
    stats = { started = 0, completed = 0, failed = 0, cancelled = 0, sliceMs = 0, slices = 0 },
}
FGPS.Scheduler = Scheduler

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
    local offset = Scheduler.rotation % count
    for step = 0, count - 1 do
        local task = tasks[((offset + step) % count) + 1]
        if task and not task.done then resume(task) end
        Scheduler.rotation = offset + step + 1
        if debugprofilestop() - frameStart >= Scheduler.frameBudgetMs then break end
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
    if now - task.sliceStart >= task.budgetMs or now - Scheduler.frameStart >= Scheduler.frameBudgetMs then
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
