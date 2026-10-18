





























local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local type, tostring, tonumber, pairs, ipairs, format = type, tostring, tonumber, pairs, ipairs, string.format

local Compat = {
    waypoints = {},
    nextUid = 1,
    waySlashRegistered = false,
}
FGPS.UI.Compat = Compat


FGPS.UI.AddSettingDefault("compat", { wayCommand = true })



local WAY_SLASH_NAME = "CABBIEWAY"
local WAY_WORDS = { "/way", "/cabbieway" }







function Compat.ParsePinLink(text)
    if type(text) ~= "string" then return nil end
    local mapID, x, y = text:match("Hworldmap:(%d+):(%d+):(%d+)")
    if not mapID then return nil end
    mapID, x, y = tonumber(mapID), tonumber(x), tonumber(y)
    if not mapID or not x or not y then return nil end
    return mapID, x / 100, y / 100
end

local NUMBER = "%-?%d+%.?%d*"
local SEPARATOR = "[%s,;:/]+"








function Compat.ParseWay(text)
    text = Util.Trim(tostring(text or ""))
    if text == "" then return nil end

    local mapID, px, py = Compat.ParsePinLink(text)
    if mapID then return px, py, mapID, L["Map pin"] end


    local sx, sy, rest = text:match("^(" .. NUMBER .. ")" .. SEPARATOR .. "(" .. NUMBER .. ")%s*(.-)$")
    if sx then
        rest = Util.Trim(rest or "")
        if rest == "" then return tonumber(sx), tonumber(sy), nil, nil end
        return tonumber(sx), tonumber(sy), tonumber(rest) or rest, rest
    end


    local zone, zx, zy, title = text:match("^(.-)%s+(" .. NUMBER .. ")" .. SEPARATOR .. "(" .. NUMBER .. ")%s*(.-)$")
    if zx then
        zone = Util.Trim(zone or "")
        title = Util.Trim(title or "")
        if zone == "" then zone = nil else zone = tonumber(zone) or zone end
        return tonumber(zx), tonumber(zy), zone, title ~= "" and title or nil
    end
    return nil
end


local function inRange(x, y)
    return type(x) == "number" and type(y) == "number" and x >= 0 and x <= 100 and y >= 0 and y <= 100
end

local function currentMapID()
    local Coords = FGPS.Coords
    if Coords and Coords.PlayerPos then
        local ok, pos = pcall(Coords.PlayerPos)
        if ok and type(pos) == "table" and pos.map then return pos.map end
    end
    if C_Map and C_Map.GetBestMapForUnit then
        local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
        if ok and type(id) == "number" then return id end
    end
    return nil
end


local COORD_REASONS = {
    unknown_zone = "no zone of that name is known",
    range = "coordinates must be between 0 and 100",
    no_map = "your current zone is unknown; name a zone after the coordinates",
    no_world = "that place has no world position",
    parse = "that is not a coordinate pair",
}

local function reasonText(code)
    local key = COORD_REASONS[code]
    if key then return L[key] end
    return L["those coordinates could not be resolved"]
end












function Compat.Resolve(x, y, zone, title)
    local Destinations = FGPS.Destinations
    if not Destinations or not Destinations.FromCoords then
        return nil, L["that part of Cabbie is not ready"]
    end
    if not inRange(x, y) then return nil, L["coordinates must be between 0 and 100"] end
    local ambiguous = zone ~= nil and title ~= nil and zone == title
    if ambiguous and type(zone) == "string" and Destinations.ResolveZoneName then
        local ok, _, score = pcall(Destinations.ResolveZoneName, zone)
        if not (ok and score == 100) then zone = nil end
    end

    local dest, err
    if zone ~= nil then
        local ok, result, reason = pcall(Destinations.FromCoords, zone, x, y)
        if ok and result then
            dest = result

            if ambiguous then title = nil end
        else
            err = ok and reason or nil
            if not ambiguous then return nil, reasonText(err) end
        end
    end
    if not dest then
        local mapID = currentMapID()
        if not mapID then return nil, reasonText(err or "no_map") end
        local ok, result, reason = pcall(Destinations.FromCoords, mapID, x, y)
        if ok and result then dest = result else err = (ok and reason) or err end
    end
    if not dest then return nil, reasonText(err) end
    if type(title) == "string" and title ~= "" then dest.name = title end
    return dest
end




local function describe(dest)
    local Destinations = FGPS.Destinations
    if Destinations and Destinations.Describe then
        local ok, text = pcall(Destinations.Describe, dest)
        if ok and type(text) == "string" and text ~= "" then return text end
    end
    return (type(dest) == "table" and dest.name) or L["that place"]
end

local function journeyRunning()
    local Search = FGPS.UI.Search
    if Search and Search.JourneyRunning then return Search.JourneyRunning() end
    local Navigator = FGPS.Navigator
    if Navigator and Navigator.IsJourney then return Navigator:IsJourney() and true or false end
    return false
end


local function currentDestination()
    local Navigator = FGPS.Navigator
    if not Navigator then return nil end
    if Navigator.GetStops then


        local ok, stops = pcall(Navigator.GetStops, Navigator)
        if ok and type(stops) == "table" and #stops > 0 then
            local last = stops[#stops]
            if type(last) == "table" then return last.dest or last end
        end
    end
    if Navigator.GetRoute then
        local ok, route = pcall(Navigator.GetRoute, Navigator)
        local stops = ok and type(route) == "table" and route.stops or nil
        if type(stops) == "table" and #stops > 0 then
            local last = stops[#stops]
            return last.dest or last
        end
    end
    return nil
end







function Compat.Accept(dest, opts)
    opts = opts or {}
    local Search = FGPS.UI.Search
    if type(dest) ~= "table" then return false end
    local running = journeyRunning()
    local previous = running and currentDestination() or nil

    if opts.addStop then

        if Search and Search.GoTo then Search.GoTo(dest, "addStop", { quiet = true })
        else
            local Navigator = FGPS.Navigator
            if not Navigator then return false end
            Navigator:SetDestination(dest, { addStop = true, start = false, quiet = true })
        end
        if not opts.silent then FGPS:Print(L["Added a stop: %s"], describe(dest)) end
        return true
    end




    local Destinations = FGPS.Destinations
    local samePlace = previous ~= nil and Destinations ~= nil and Destinations.Equal ~= nil
        and Destinations.Equal(previous, dest) == true
    if running and not samePlace then
        if previous then
            FGPS:Print(L["Your trip to %s was replaced by %s. Use '/way add <coordinates>' to keep the trip and add a stop instead."],
                describe(previous), describe(dest))
        else
            FGPS:Print(L["The trip in progress was replaced by %s. Use '/way add <coordinates>' to keep the trip and add a stop instead."],
                describe(dest))
        end
    end


    if Search and Search.GoTo then
        Search.GoTo(dest, nil, { quiet = true })
    else
        local Navigator = FGPS.Navigator
        if not Navigator or not Navigator.SetDestination then
            FGPS:Print(L["Navigation is not available right now."])
            return false
        end
        Navigator:SetDestination(dest, { start = false, quiet = true })
    end
    if not opts.silent and not running then FGPS:Print(L["Waypoint: %s"], describe(dest)) end
    FGPS.Log:Debug("Waypoint accepted from %s: %s", tostring(opts.source or "way"), describe(dest))
    return true
end






function Compat.PinIsOurs()
    local InWorldPin = FGPS.UI.InWorldPin
    local state = InWorldPin and InWorldPin.state
    if not state or not state.set or type(state.target) ~= "table" then return false end
    if type(C_Map) ~= "table" or type(C_Map.GetUserWaypoint) ~= "function" then return false end
    local ok, point = pcall(C_Map.GetUserWaypoint)
    if not ok or type(point) ~= "table" then return false end
    local target = state.target
    if point.uiMapID ~= target.uiMapID then return false end
    local position = point.position
    local px = position and (position.x or (position.GetXY and select(1, position:GetXY())))
    local py = position and (position.y or (position.GetXY and select(2, position:GetXY())))
    if type(px) ~= "number" or type(py) ~= "number" then return false end
    local epsilon = InWorldPin.MATCH_EPSILON or 0.0005
    return math.abs(px - target.x) <= epsilon and math.abs(py - target.y) <= epsilon
end



function Compat.FromUserWaypoint()
    if type(C_Map) ~= "table" or type(C_Map.GetUserWaypoint) ~= "function" then
        return nil, L["this client has no map pin"]
    end
    local ok, point = pcall(C_Map.GetUserWaypoint)
    if not ok or type(point) ~= "table" then return nil, L["there is no map pin set"] end
    if Compat.PinIsOurs() then
        return nil, L["that map pin is the one Cabbie placed for the current trip"]
    end
    local position = point.position
    local px = position and (position.x or (position.GetXY and select(1, position:GetXY())))
    local py = position and (position.y or (position.GetXY and select(2, position:GetXY())))
    if type(px) ~= "number" or type(py) ~= "number" then return nil, L["there is no map pin set"] end
    local Destinations = FGPS.Destinations
    if not Destinations or not Destinations.FromMapClick then
        return nil, L["that part of Cabbie is not ready"]
    end
    local okDest, dest, reason = pcall(Destinations.FromMapClick, point.uiMapID, px, py)
    if not okDest or not dest then return nil, (okDest and reason) or L["that map position cannot be used as a destination"] end
    if not dest.name or dest.name == "" then dest.name = L["Map pin"] end
    return dest
end


















function Compat.AddWaypoint(uiMapID, x, y, opts)

    if type(uiMapID) == "table" then
        uiMapID, x, y, opts = x, y, opts, nil
    end
    uiMapID, x, y = tonumber(uiMapID), tonumber(x), tonumber(y)
    if not uiMapID or not x or not y then return nil, L["a waypoint needs a map and two coordinates"] end
    opts = type(opts) == "table" and opts or {}
    local dest, reason = Compat.Resolve(x * 100, y * 100, uiMapID, opts.title)
    if not dest then
        if not opts.silent then FGPS:Print(L["Could not add that waypoint: %s"], tostring(reason)) end
        return nil, reason
    end
    if not Compat.Accept(dest, { addStop = opts.addStop == true, silent = opts.silent == true, source = "AddWaypoint" }) then
        return nil, L["the navigator did not accept the waypoint"]
    end
    local uid = Compat.nextUid
    Compat.nextUid = uid + 1
    Compat.waypoints[uid] = { dest = dest, title = opts.title, addedAt = GetTime and GetTime() or 0, source = "AddWaypoint" }
    return uid
end



function Compat.AddMFWaypoint(uiMapID, floor, x, y, opts)
    if type(uiMapID) == "table" then
        uiMapID, floor, x, y, opts = floor, x, y, opts, nil
    end
    return Compat.AddWaypoint(uiMapID, x, y, opts)
end




function Compat.RemoveWaypoint(uid)
    if type(uid) == "table" then return false end
    local entry = Compat.waypoints[uid]
    if not entry then return false end
    Compat.waypoints[uid] = nil
    local Destinations = FGPS.Destinations
    local current = currentDestination()
    if current and Destinations and Destinations.Equal and Destinations.Equal(current, entry.dest) then
        local Navigator = FGPS.Navigator
        if Navigator and Navigator.Cancel then
            Navigator:Cancel("waypoint_removed")
            FGPS:Print(L["The trip to %s was cancelled: its waypoint was removed."], describe(entry.dest))
        end
    end
    return true
end



function Compat.ClearWaypoints()
    local count = 0
    for uid in pairs(Compat.waypoints) do
        Compat.waypoints[uid] = nil
        count = count + 1
    end
    if count > 0 and journeyRunning() then
        FGPS:Print(L["%d waypoint(s) forgotten. The trip in progress is still running; type /cabbie cancel to stop it."], count)
    end
    return count
end




local function printWayHelp()
    FGPS:Print(L["Waypoints: /way <x> <y> [zone or title] | /way <zone> <x> <y> [title] | /way <pasted map pin link> | /way pin | /way add <...> | /way clear"])
    FGPS:Print(L["The same words work as /cabbie way ... . Cabbie understands the common waypoint wording so guides need no rewriting; it is not, and does not replace, any other waypoint add-on."])
end


function Compat.SlashWay(args)
    args = Util.Trim(tostring(args or ""))
    local word = Util.Lower(args:match("^(%S*)") or "")
    if args == "" or word == "help" or word == "?" then
        printWayHelp()
        return false
    end

    local addStop = false
    if word == "add" or word == "stop" then
        addStop = true
        args = Util.Trim(args:sub(#word + 1))
        word = Util.Lower(args:match("^(%S*)") or "")
        if args == "" then
            printWayHelp()
            return false
        end
    end

    if word == "clear" or word == "reset" then
        Compat.ClearWaypoints()
        FGPS:Print(L["Waypoints forgotten."])
        return true
    end

    local dest, reason
    if word == "pin" or word == "waypoint" then
        dest, reason = Compat.FromUserWaypoint()
    else
        local x, y, zone, title = Compat.ParseWay(args)
        if not x then
            FGPS:Print(L["That is not a coordinate pair. Try: /way 42.5 65.1 Elwynn Forest"])
            printWayHelp()
            return false
        end
        dest, reason = Compat.Resolve(x, y, zone, title)
    end
    if not dest then
        FGPS:Print(L["Could not use that waypoint: %s"], tostring(reason or L["unknown reason"]))
        return false
    end
    return Compat.Accept(dest, { addStop = addStop, source = "slash" }) and true or false
end












local MAX_EMOTES, MAX_WORDS = 2000, 8

local function gameWordTaken(word, own)
    local key = string.upper(word)
    if type(hash_EmoteTokenList) == "table" and hash_EmoteTokenList[key] ~= nil then return true end
    if type(hash_ChatTypeInfoList) == "table" and hash_ChatTypeInfoList[key] ~= nil then return true end
    if type(hash_SlashCmdList) == "table" then
        local handler = hash_SlashCmdList[key]
        if handler ~= nil and handler ~= own then return true end
    end
    local globals = _G
    if type(MAXEMOTEINDEX) ~= "number" or type(globals) ~= "table" then return false end
    for i = 1, math.min(MAXEMOTEINDEX, MAX_EMOTES) do
        for j = 1, MAX_WORDS do
            local value = globals["EMOTE" .. i .. "_CMD" .. j]
            if value == nil then break end
            if type(value) == "string" and Util.Lower(value) == word then return true end
        end
    end
    return false
end





local function slashWordTaken(word, own)
    if gameWordTaken(word, own) then return true end
    if type(SlashCmdList) ~= "table" then return false end
    local globals = _G
    if type(globals) ~= "table" then return false end
    for name in pairs(SlashCmdList) do
        if name ~= WAY_SLASH_NAME then
            for i = 1, 8 do
                local value = globals["SLASH_" .. tostring(name) .. i]
                if value == nil then break end
                if type(value) == "string" and Util.Lower(value) == word then return true end
            end
        end
    end
    return false
end
Compat.SlashWordTaken = slashWordTaken





local function waySlash(message)
    local c = FGPS.DB and FGPS.DB.settings and FGPS.DB.settings.compat
    if type(c) == "table" and c.wayCommand == false then
        FGPS:Print(L["Cabbie does not answer /way while \"Answer the /way command\" is off in its settings. /cabbie way still works."])
        return
    end
    Compat.SlashWay(message)
end







function Compat.RegisterWaySlash()
    if type(SlashCmdList) ~= "table" then return false end
    local s = FGPS.DB and FGPS.DB.settings
    local c = s and s.compat
    if type(c) == "table" and c.wayCommand == false then return false end
    if Compat.waySlashRegistered then return true end
    if slashWordTaken(WAY_WORDS[1], waySlash) then
        FGPS.Log:Info("Another add-on or the game already owns %s; Cabbie's waypoints stay on /cabbie way", WAY_WORDS[1])
        return false
    end
    local globals = _G
    if type(globals) ~= "table" then return false end
    for i, wordText in ipairs(WAY_WORDS) do
        globals["SLASH_" .. WAY_SLASH_NAME .. i] = wordText
    end
    SlashCmdList[WAY_SLASH_NAME] = waySlash
    Compat.waySlashRegistered = true
    return true
end

function Compat.UnregisterWaySlash()
    if not Compat.waySlashRegistered then return false end
    local globals = _G
    if type(globals) == "table" then
        for i = 1, #WAY_WORDS do globals["SLASH_" .. WAY_SLASH_NAME .. i] = nil end
    end
    if type(SlashCmdList) == "table" then SlashCmdList[WAY_SLASH_NAME] = nil end
    Compat.waySlashRegistered = false
    return true
end




local function onSettingsChanged(_, key)
    if key ~= "compat.wayCommand" and key ~= "*" then return end
    local c = FGPS.DB and FGPS.DB.settings and FGPS.DB.settings.compat
    if type(c) == "table" and c.wayCommand == false then
        Compat.UnregisterWaySlash()
    else
        Compat.RegisterWaySlash()
    end
end

function Compat:Init()
    if not Compat.initialised then
        Compat.initialised = true
        FGPS.Slash.Register("way", function(args) Compat.SlashWay(args) end,
            L["Set a destination from waypoint coordinates or a pasted map pin link"])
        FGPS.Slash.Register("pin", function() Compat.SlashWay("pin") end,
            L["Use the client's own map pin as the destination"])
        if FGPS.Events then FGPS.Events:Register("SETTINGS_CHANGED", onSettingsChanged, Compat) end
    end

    FGPS.AddWaypoint = Compat.AddWaypoint
    FGPS.AddMFWaypoint = Compat.AddMFWaypoint
    FGPS.RemoveWaypoint = Compat.RemoveWaypoint
    FGPS.ClearWaypoints = Compat.ClearWaypoints
    Compat.RegisterWaySlash()
    return Compat
end
