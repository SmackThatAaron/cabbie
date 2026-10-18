




local ADDON_NAME, FGPS = ...

local pcall, type, select, ipairs, pairs = pcall, type, select, ipairs, pairs

local Events = {
    handlers = {},
    wowHandlers = {},
    frame = nil,
    unitFrames = {},
    unitFilters = {},
}
FGPS.Events = Events

local firing = {}

local function logError(kind, name, err)
    if FGPS.Log then
        FGPS.Log:Error("%s handler for %s failed: %s", kind, tostring(name), tostring(err))
    end
end


local function mutableList(store, name)
    local list = store[name]
    if not list then
        list = {}
        store[name] = list
        return list
    end
    if firing[list] then
        local copy = {}
        for i = 1, #list do copy[i] = list[i] end
        store[name] = copy
        return copy
    end
    return list
end

local function dispatch(list, kind, name, ...)
    firing[list] = (firing[list] or 0) + 1
    for i = 1, #list do
        local entry = list[i]
        local ok, err = pcall(entry.fn, name, ...)
        if not ok then logError(kind, name, err) end
    end
    local depth = firing[list] - 1
    firing[list] = depth > 0 and depth or nil
end


local function removeMatching(store, name, fnOrOwner)
    local list = store[name]
    if not list then return 0 end
    local removed = 0
    local target
    for i = #list, 1, -1 do
        local entry = list[i]
        if entry.fn == fnOrOwner or (fnOrOwner ~= nil and entry.owner == fnOrOwner) then
            target = target or mutableList(store, name)
            table.remove(target, i)
            removed = removed + 1
        end
    end
    if target and #target == 0 then store[name] = nil end
    return removed
end




function Events:Register(name, fn, owner)
    assert(type(name) == "string", "Events:Register: name must be a string")
    assert(type(fn) == "function", "Events:Register: fn must be a function")
    local list = mutableList(self.handlers, name)
    list[#list + 1] = { fn = fn, owner = owner }
end

function Events:Unregister(name, fnOrOwner)
    return removeMatching(self.handlers, name, fnOrOwner)
end

function Events:Fire(name, ...)
    local list = self.handlers[name]
    if not list then return 0 end
    dispatch(list, "Event", name, ...)
    return #list
end

function Events:HasHandlers(name)
    local list = self.handlers[name]
    return list ~= nil and #list > 0
end








local function onWoWEvent(frame, event, ...)
    local list = Events.wowHandlers[event]
    if not list then return end
    local unitFrame = frame ~= nil and frame ~= Events.frame
    firing[list] = (firing[list] or 0) + 1
    local unitArg = ...
    for i = 1, #list do
        local entry = list[i]
        local mine
        if unitFrame then


            mine = entry.unit ~= nil and entry.unit == unitArg
        else
            mine = entry.unit == nil
        end
        if mine then
            local ok, err = pcall(entry.fn, event, ...)
            if not ok then logError("WoW event", event, err) end
        end
    end
    local depth = firing[list] - 1
    firing[list] = depth > 0 and depth or nil
end

local function ensureFrame()
    if not Events.frame then
        Events.frame = CreateFrame("Frame")
        Events.frame:SetScript("OnEvent", onWoWEvent)
    end
    return Events.frame
end

local function registerFrameEvent(frame, event)
    local ok, err = pcall(frame.RegisterEvent, frame, event)
    if not ok and FGPS.Log then FGPS.Log:Warn("Cannot register WoW event %s: %s", tostring(event), tostring(err)) end
    return ok
end

function Events:RegisterWoW(event, fn, owner)
    assert(type(event) == "string", "Events:RegisterWoW: event must be a string")
    assert(type(fn) == "function", "Events:RegisterWoW: fn must be a function")
    local list = mutableList(self.wowHandlers, event)
    list[#list + 1] = { fn = fn, owner = owner }
    if not self.frame or not self.frame:IsEventRegistered(event) then
        registerFrameEvent(ensureFrame(), event)
    end
end




local function applyUnitFilter(event)
    local frame = Events.unitFrames[event]
    local filters = Events.unitFilters[event]
    if not frame then return end
    local units = {}
    for unit, count in pairs(filters or {}) do
        if count > 0 then units[#units + 1] = unit end
    end
    if #units == 0 then
        frame:UnregisterEvent(event)
    elseif #units <= 2 and frame.RegisterUnitEvent then
        local ok = pcall(frame.RegisterUnitEvent, frame, event, units[1], units[2])
        if not ok then registerFrameEvent(frame, event) end
    else
        registerFrameEvent(frame, event)
    end
end

function Events:RegisterUnitWoW(event, unit, fn, owner)
    assert(type(event) == "string" and type(unit) == "string", "Events:RegisterUnitWoW: event and unit must be strings")
    assert(type(fn) == "function", "Events:RegisterUnitWoW: fn must be a function")
    local list = mutableList(self.wowHandlers, event)
    list[#list + 1] = { fn = fn, owner = owner, unit = unit }
    if not self.unitFrames[event] then
        local frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", onWoWEvent)
        self.unitFrames[event] = frame
        self.unitFilters[event] = {}
    end
    local filters = self.unitFilters[event]
    filters[unit] = (filters[unit] or 0) + 1
    applyUnitFilter(event)
end

function Events:UnregisterWoW(event, fnOrOwner)
    local list = self.wowHandlers[event]
    if not list then return 0 end
    local removedUnits = {}
    local removed = 0
    local target
    for i = #list, 1, -1 do
        local entry = list[i]
        if entry.fn == fnOrOwner or (fnOrOwner ~= nil and entry.owner == fnOrOwner) then
            target = target or mutableList(self.wowHandlers, event)
            table.remove(target, i)
            removed = removed + 1
            if entry.unit then removedUnits[entry.unit] = (removedUnits[entry.unit] or 0) + 1 end
        end
    end
    if removed == 0 then return 0 end
    local remaining = target
    local filters = self.unitFilters[event]
    if filters then
        for unit, count in pairs(removedUnits) do
            filters[unit] = (filters[unit] or 0) - count
            if filters[unit] <= 0 then filters[unit] = nil end
        end
        applyUnitFilter(event)
    end
    local plainLeft = false
    for i = 1, #remaining do
        if remaining[i].unit == nil then plainLeft = true break end
    end
    if not plainLeft and self.frame then self.frame:UnregisterEvent(event) end
    if #remaining == 0 then self.wowHandlers[event] = nil end
    return removed
end


function Events:UnregisterAllByOwner(owner)
    assert(owner ~= nil, "Events:UnregisterAllByOwner: owner is required")
    local removed = 0
    local names = {}
    for name in pairs(self.handlers) do names[#names + 1] = name end
    for _, name in ipairs(names) do removed = removed + self:Unregister(name, owner) end
    names = {}
    for event in pairs(self.wowHandlers) do names[#names + 1] = event end
    for _, event in ipairs(names) do removed = removed + self:UnregisterWoW(event, owner) end
    return removed
end

function Events:IsWoWRegistered(event)
    local list = self.wowHandlers[event]
    return list ~= nil and #list > 0
end
