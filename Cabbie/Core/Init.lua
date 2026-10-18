



local ADDON_NAME, FGPS = ...

FGPS.name = ADDON_NAME

Cabbie = FGPS

FGPS.Data = FGPS.Data or {}
FGPS.UI = FGPS.UI or {}

local L = FGPS.L
local format, floor, tostring, type, select, pairs, ipairs = string.format, math.floor, tostring, type, select, pairs, ipairs




local function metadata(field)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        local ok, value = pcall(C_AddOns.GetAddOnMetadata, ADDON_NAME, field)
        if ok and type(value) == "string" and value ~= "" then return value end
    end
    return nil
end

FGPS.version = metadata("Version") or "0.0.0-dev"
FGPS.title = metadata("Title") or "Cabbie"

do
    local versionString, buildNumber, buildDate, interface
    if GetBuildInfo then
        local ok, v, b, d, i = pcall(GetBuildInfo)
        if ok then versionString, buildNumber, buildDate, interface = v, b, d, i end
    end
    interface = tonumber(interface)
    FGPS.build = {
        version = versionString,
        buildNumber = buildNumber,
        date = buildDate,
        interface = interface,

        isForever = (interface == 16001) or (type(versionString) == "string" and versionString:sub(1, 4) == "1.60"),
    }
end




FGPS.Const = {
    RUN_SPEED = 7.0,
    MOUNT_60 = 11.2,
    MOUNT_100 = 14.0,
    SWIM_SPEED = 4.72,
    TAXI_SPEED = 32,
    TAXI_BOARD_SECONDS = 5,
    BOAT_WAIT_CAP = 120,
    TRAM_WAIT = 30,
    TRAM_SECONDS = 60,
    ELEVATOR_SECONDS = 20,
    PORTAL_SECONDS = 5,
    HEARTH_CAST_SECONDS = 10,
    HEARTH_LOAD_SECONDS = 5,
    ARRIVE_YARDS = 10,
    INTERMEDIATE_ARRIVE_YARDS = 15,
    OFFROUTE_YARDS = 40,


    OFFROUTE_GUESS_SHARE = 0.15,
    OFFROUTE_GUESS_MAX_YARDS = 150,
    OFFROUTE_TICKS = 3,
    RECALC_MIN_SECONDS = 5,



    RECALC_FALLBACK_CAP_YARDS = 150,


    TRANSPORT_ARRIVE_YARDS = 60,
    POS_HZ = 4,
    GRID_CELL_YARDS = 256,
    ORIGIN_CELL_YARDS = 32,
    ATTACH_RADIUS_YARDS = 150,
    ATTACH_VERIFIED_ONLY_YARDS = 25,
    MAX_EXPANSIONS = 150000,
    YARDS_PER_METER = 1.0936133,
    METERS_PER_YARD = 0.9144,
}




local Util = {}
FGPS.Util = Util

function Util.Clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end


function Util.Round(value, decimals)
    local m = 10 ^ (decimals or 0)
    if value >= 0 then return floor(value * m + 0.5) / m end
    return -floor(-value * m + 0.5) / m
end

local function withThousands(n)
    local s = tostring(floor(n + 0.5))
    local head, tail = s:match("^(-?%d+)(%.?%d*)$")
    if not head then return s end
    local formatted = head:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    formatted = formatted:gsub("^(-?),", "%1")
    return formatted .. tail
end
Util.WithThousands = withThousands



function Util.FormatDistance(yards, units)
    if type(yards) ~= "number" then return L.UNKNOWN_VALUE end
    if yards < 0 then yards = -yards end
    if units == "metric" then
        local metres = yards * FGPS.Const.METERS_PER_YARD
        if metres < 1000 then return format("%d %s", floor(metres + 0.5), L.UNIT_METERS) end
        return format("%.1f %s", metres / 1000, L.UNIT_KILOMETERS)
    end
    return format("%s %s", withThousands(yards), L.UNIT_YARDS)
end


function Util.FormatTime(seconds)
    if type(seconds) ~= "number" then return L.UNKNOWN_VALUE end
    seconds = floor(seconds + 0.5)
    if seconds < 0 then seconds = 0 end
    if seconds < 60 then return format(L.TIME_SECONDS, seconds) end
    if seconds < 3600 then return format(L.TIME_MINUTES, floor(seconds / 60), seconds % 60) end
    return format(L.TIME_HOURS, floor(seconds / 3600), floor((seconds % 3600) / 60))
end



local function keyLess(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta < tb end
    if ta == "number" or ta == "string" then return a < b end
    return tostring(a) < tostring(b)
end

local function serialize(value, out, seen)
    local t = type(value)
    if t == "table" then
        if seen[value] then out[#out + 1] = "<cycle>" return end
        seen[value] = true
        local keys = {}
        for k in pairs(value) do keys[#keys + 1] = k end
        table.sort(keys, keyLess)
        out[#out + 1] = "{"
        for i = 1, #keys do
            local k = keys[i]
            serialize(k, out, seen)
            out[#out + 1] = "="
            serialize(value[k], out, seen)
            out[#out + 1] = ";"
        end
        out[#out + 1] = "}"
        seen[value] = nil
    elseif t == "string" then
        out[#out + 1] = format("%q", value)
    elseif t == "number" then
        out[#out + 1] = format("%.10g", value)
    else
        out[#out + 1] = tostring(value)
    end
end


function Util.Serialize(value)
    local out = {}
    serialize(value, out, {})
    return table.concat(out)
end



local function hashString(s)
    local h = 5381
    for i = 1, #s do
        h = (h * 33 + s:byte(i)) % 4294967296
    end
    return format("%04x%04x", floor(h / 65536), h % 65536)
end

function Util.Hash(value)
    if type(value) == "string" then return hashString(value) end
    return hashString(Util.Serialize(value))
end

function Util.ShallowCopy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

local function deepCopy(t, seen)
    if type(t) ~= "table" then return t end
    if seen[t] then return seen[t] end
    local out = {}
    seen[t] = out
    for k, v in pairs(t) do out[deepCopy(k, seen)] = deepCopy(v, seen) end
    return out
end

function Util.DeepCopy(t)
    return deepCopy(t, {})
end



function Util.Merge(dst, src, keepExisting)
    for k, v in pairs(src) do
        local cur = dst[k]
        if type(v) == "table" then
            if type(cur) ~= "table" then
                if cur == nil or not keepExisting then dst[k] = deepCopy(v, {}) end
            else
                Util.Merge(cur, v, keepExisting)
            end
        elseif cur == nil or not keepExisting then
            dst[k] = v
        end
    end
    return dst
end

function Util.Trim(s)
    if type(s) ~= "string" then return "" end
    local r = s:gsub("^%s+", "")
    r = r:gsub("%s+$", "")
    return r
end

local function asciiLower(c) return string.char(c:byte() + 32) end

function Util.Lower(s)
    if type(s) ~= "string" then return "" end
    local r = s:gsub("[A-Z]", asciiLower)
    return r
end


function Util.Split(s, sep)
    local out = {}
    if type(s) ~= "string" then return out end
    sep = sep or " "
    local pattern = "[^" .. sep:gsub("(%W)", "%%%1") .. "]+"
    for piece in s:gmatch(pattern) do out[#out + 1] = piece end
    return out
end


function Util.CopyVector(v)
    if not v then return nil end
    local x, y
    if v.GetXY then x, y = v:GetXY() else x, y = v.x, v.y end
    if CreateVector2D then return CreateVector2D(x, y) end
    return { x = x, y = y }
end

function Util.Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end


function Util.SafeFormat(fmt, ...)
    local n = select("#", ...)
    if n == 0 then return tostring(fmt) end
    local ok, result = pcall(format, tostring(fmt), ...)
    if ok then return result end
    local parts = { tostring(fmt) }
    for i = 1, n do parts[#parts + 1] = tostring((select(i, ...))) end
    return table.concat(parts, " ")
end




local PREFIX = "|cff4fc3f7Cabbie|r: "

local function emit(text)
    local frame = DEFAULT_CHAT_FRAME
    if frame and frame.AddMessage then
        frame:AddMessage(PREFIX .. text)
    else
        print(PREFIX .. text)
    end
end

function FGPS:Print(fmt, ...)
    emit(Util.SafeFormat(fmt, ...))
end

function FGPS:IsDebug()
    local db = self.DB
    return db ~= nil and db.settings ~= nil and db.settings.debug == true
end


function FGPS:Debug(fmt, ...)
    if not self:IsDebug() then return end
    local text = Util.SafeFormat(fmt, ...)
    emit("|cff999999" .. text .. "|r")
    if self.Log then self.Log:Debug("%s", text) end
end




local Slash = { commands = {}, order = {} }
FGPS.Slash = Slash


function Slash.Register(word, handler, help)
    assert(type(word) == "string" and word ~= "", "Slash.Register: word must be a non-empty string")
    assert(type(handler) == "function", "Slash.Register: handler must be a function")
    word = Util.Lower(word)
    if not Slash.commands[word] then
        Slash.order[#Slash.order + 1] = word
    elseif FGPS.Log then
        FGPS.Log:Debug("Slash command '%s' re-registered", word)
    end
    Slash.commands[word] = { handler = handler, help = help }
end

function Slash.Unregister(word)
    word = Util.Lower(word)
    if not Slash.commands[word] then return end
    Slash.commands[word] = nil
    for i = #Slash.order, 1, -1 do
        if Slash.order[i] == word then table.remove(Slash.order, i) end
    end
end

function Slash.Help()
    FGPS:Print(L.HELP_HEADER, FGPS.version)
    for _, word in ipairs(Slash.order) do
        local cmd = Slash.commands[word]
        if cmd and cmd.help then emit(format(L.HELP_LINE, word, cmd.help)) end
    end
end

function Slash.Dispatch(message)
    message = Util.Trim(message)
    if message == "" then


        local line = FGPS.UI and FGPS.UI.SearchLine
        if line and line.Open then
            local ok, opened = pcall(line.Open)
            if ok and opened then return end
            if not ok and FGPS.Log then FGPS.Log:Error("The search line failed to open: %s", tostring(opened)) end
        end
        local search = FGPS.UI and FGPS.UI.Search
        local opener = search and (search.Toggle or search.Show or search.Open)
        if opener then


            if UIParent and UIParent.IsVisible and not UIParent:IsVisible() then return end
            local ok, err = pcall(opener, search)
            if not ok and FGPS.Log then FGPS.Log:Error("Search window failed to open: %s", tostring(err)) end
            return
        end
        Slash.Help()
        return
    end
    local word, rest = message:match("^(%S+)%s*(.-)$")
    word = Util.Lower(word)
    local cmd = Slash.commands[word]
    if not cmd then



        local Go = FGPS.UI and FGPS.UI.Go
        if Go and Go.FromUnknownCommand then
            local ok, err = pcall(Go.FromUnknownCommand, message)
            if not ok then
                if FGPS.Log then FGPS.Log:Error("Going to '%s' failed: %s", message, tostring(err)) end
                FGPS:Print(L.SLASH_FAILED, "go")
            end
            return
        end
        FGPS:Print(L.SLASH_UNKNOWN, word)
        return
    end
    local ok, err = pcall(cmd.handler, rest, word)
    if not ok then
        if FGPS.Log then FGPS.Log:Error("Slash command '%s' failed: %s", word, tostring(err)) end
        FGPS:Print(L.SLASH_FAILED, word)
    end
end



Slash.Register("help", function()
    local line = FGPS.UI and FGPS.UI.SearchLine
    if line and line.Open then
        local ok, err = pcall(line.Open)
        if not ok and FGPS.Log then FGPS.Log:Error("The search line failed to open: %s", tostring(err)) end
    end
    Slash.Help()
end, L.HELP_HELP)
Slash.Register("version", function()
    local b = FGPS.build
    FGPS:Print(L.VERSION_LINE, FGPS.version, tostring(b.version), tostring(b.buildNumber), b.interface or 0,
        b.isForever and "" or L.NOT_FOREVER)
end, L.HELP_VERSION)








local function slashClear()
    local Navigator = FGPS.Navigator
    if not (Navigator and Navigator.Clear) then
        FGPS:Print(L["Navigation is not available right now."])
        return
    end

    Navigator:Clear("user")
end
Slash.Register("clear", slashClear, L["Clear everything Cabbie has set: the route, the preview, every stop and the map markers"])
Slash.Register("stop", slashClear, L["Same as clear"])
Slash.Register("cancel", slashClear, L["Same as clear"])

SLASH_CABBIE1 = "/cabbie"
SLASH_CABBIE2 = "/gps"
SLASH_CABBIE3 = "/cab"
if SlashCmdList then
    SlashCmdList["CABBIE"] = function(message) Slash.Dispatch(message) end
end
