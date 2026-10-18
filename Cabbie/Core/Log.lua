



local ADDON_NAME, FGPS = ...

local L = FGPS.L
local SafeFormat = FGPS.Util.SafeFormat

local Log = {
    capacity = 200,
    entries = {},
    head = 0,
    counts = { DEBUG = 0, INFO = 0, WARN = 0, ERROR = 0 },
}
FGPS.Log = Log

local function now()
    if GetTime then return GetTime() end
    return 0
end

local function record(level, fmt, ...)
    local text = SafeFormat(fmt, ...)
    Log.head = Log.head + 1
    Log.entries[((Log.head - 1) % Log.capacity) + 1] = { time = now(), level = level, text = text }
    Log.counts[level] = (Log.counts[level] or 0) + 1
    return text
end

function Log:Info(fmt, ...) record("INFO", fmt, ...) end
function Log:Warn(fmt, ...) record("WARN", fmt, ...) end

function Log:Debug(fmt, ...)
    if FGPS:IsDebug() then record("DEBUG", fmt, ...) end
end

function Log:Error(fmt, ...)
    local text = record("ERROR", fmt, ...)
    if FGPS:IsDebug() then
        FGPS:Print("|cffff4040error:|r %s", text)
        if geterrorhandler then
            local handler = geterrorhandler()
            if type(handler) == "function" then


                Log.forwarding = true
                pcall(handler, ADDON_NAME .. ": " .. text)
                Log.forwarding = nil
            end
        end
    end
    return text
end


function Log:Count()
    if self.head < self.capacity then return self.head end
    return self.capacity
end


function Log:Lines(levelFilter)
    local out = {}
    local count = self:Count()
    local first = self.head - count + 1
    for n = first, self.head do
        local entry = self.entries[((n - 1) % self.capacity) + 1]
        if entry and (not levelFilter or entry.level == levelFilter) then out[#out + 1] = entry end
    end
    return out
end

function Log:Clear()
    self.entries = {}
    self.head = 0
    for level in pairs(self.counts) do self.counts[level] = 0 end
end


function Log:Dump(levelFilter)
    local lines = self:Lines(levelFilter)
    if #lines == 0 then
        FGPS:Print(L.LOG_EMPTY)
        return 0
    end
    FGPS:Print(L.LOG_HEADER, #lines)
    for _, entry in ipairs(lines) do
        FGPS:Print("[%8.1f] %-5s %s", entry.time, entry.level, entry.text)
    end
    return #lines
end

FGPS.Slash.Register("log", function(args)
    local word = FGPS.Util.Lower(FGPS.Util.Trim(args))
    if word == "clear" then
        Log:Clear()
        FGPS:Print(L.LOG_EMPTY)
    elseif word == "errors" then
        Log:Dump("ERROR")
    else
        Log:Dump()
    end
end, L.HELP_LOG)
