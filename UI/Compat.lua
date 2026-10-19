-- Cabbie/UI/Compat.lua
-- Waypoint interoperability.
--
-- Guide authors, quest helpers and web sites all write coordinates in the same few shapes, so
-- Cabbie understands them instead of asking people to retype:
--   /way 42.5 65.1                     the current zone
--   /way 42.5 65.1 Elwynn Forest       a zone named after the numbers (Cabbie's own written form)
--   /way 42.5 65.1 Meet here           a title after the numbers when the words are not a zone
--   /way Elwynn Forest 42.5 65.1       a zone named before the numbers
--   /way Elwynn Forest 42.5 65.1 Inn   ... with a title after them
--   /way |cffffff00|Hworldmap:1429:4250:6510|h[Map Pin]|h|r   a pasted map pin link
--   /way pin                           whatever the client's own map pin is pointing at
--   /way add <any of the above>        add the place as another stop instead of replacing
-- The same words work as "/cabbie way ...", which is always available even when another add-on
-- owns the plain "/way".
--
-- COMPATIBILITY SHIM, NOT AN IMPERSONATION. Cabbie also answers to the function signature that
-- waypoint-providing add-ons made the common dialect, so a guide that already calls
--   TomTom:AddWaypoint(uiMapID, x, y, opts)
-- can drive Cabbie by calling
--   Cabbie:AddWaypoint(uiMapID, x, y, opts)
-- with nothing else changed. That is all this is: a door with a familiar handle. Cabbie does not
-- register itself as, replace, or claim to be TomTom or any other add-on, it defines no global of
-- another add-on's name, and it does not pretend to implement the rest of that add-on's API. Only
-- the arguments listed at AddWaypoint below are honoured; the rest are accepted and ignored so a
-- caller written for the other add-on does not error. If the real add-on is installed it keeps its
-- own name, its own "/way" and its own arrow, and Cabbie stays out of its way.
--
-- A destination arriving through any of these paths never silently replaces a journey in progress:
-- the player is told in chat which destination was dropped, and is told how to add a stop instead.
local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local type, tostring, tonumber, pairs, ipairs, format = type, tostring, tonumber, pairs, ipairs, string.format

local Compat = {
    waypoints = {},          -- uid -> { dest, title, addedAt, source }
    nextUid = 1,
    waySlashRegistered = false,
}
FGPS.UI.Compat = Compat

-- Defaults for the preferences this module owns (see UI/Skins.lua AddSettingDefault).
FGPS.UI.AddSettingDefault("compat", { wayCommand = true })

-- Name under which the plain "/way" is registered in the client's slash dispatch table. It is
-- deliberately our own name: the dispatch entry says Cabbie, not somebody else's add-on.
local WAY_SLASH_NAME = "CABBIEWAY"
local WAY_WORDS = { "/way", "/cabbieway" }

-------------------------------------------------------------------------------
-- Parsing
-------------------------------------------------------------------------------
-- The map pin link the client puts in chat is "|Hworldmap:<uiMapID>:<x>:<y>|h[Map Pin]|h", with x
-- and y as ten-thousandths of the map rectangle.
-- Compat.ParsePinLink(text) -> uiMapID, x100, y100   (percentages, as the other forms use)
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

-- Compat.ParseWay(text) -> x, y, zone, title    (x and y are 0..100 map percentages)
--   zone is a zone name, a uiMapID (number) or nil for the current zone;
--   title is the label the caller wrote after the coordinates, or nil.
-- The words that follow a "numbers first" form are ambiguous: TomTom-style guides put a title
-- there and Cabbie's own written form puts the zone there. They are returned as BOTH candidates
-- (zone and title are the same string) and Compat.Resolve decides by trying the zone first; only
-- the caller has the destination tables needed to tell a real zone name from a label.
function Compat.ParseWay(text)
    text = Util.Trim(tostring(text or ""))
    if text == "" then return nil end

    local mapID, px, py = Compat.ParsePinLink(text)
    if mapID then return px, py, mapID, L["Map pin"] end

    -- Numbers first, optionally followed by a zone name or a title.
    local sx, sy, rest = text:match("^(" .. NUMBER .. ")" .. SEPARATOR .. "(" .. NUMBER .. ")%s*(.-)$")
    if sx then
        rest = Util.Trim(rest or "")
        if rest == "" then return tonumber(sx), tonumber(sy), nil, nil end
        return tonumber(sx), tonumber(sy), tonumber(rest) or rest, rest
    end

    -- Zone name first, then the numbers, then an optional title.
    local zone, zx, zy, title = text:match("^(.-)%s+(" .. NUMBER .. ")" .. SEPARATOR .. "(" .. NUMBER .. ")%s*(.-)$")
    if zx then
        zone = Util.Trim(zone or "")
        title = Util.Trim(title or "")
        if zone == "" then zone = nil else zone = tonumber(zone) or zone end
        return tonumber(zx), tonumber(zy), zone, title ~= "" and title or nil
    end
    return nil
end

-- True when both numbers look like map percentages.
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

-- Sentences for the reason codes Destinations.FromCoords answers with; a raw code is never shown.
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

-- Compat.Resolve(x, y, zone, title) -> dest|nil, reason
-- Turns parsed coordinates into a destination.
--
-- A zone the caller named explicitly is binding: a mistyped zone answers with "no zone of that
-- name is known" rather than quietly sending the player to the same numbers in whatever zone they
-- happen to be standing in. Only the genuinely ambiguous case falls back, which is the wording
-- "<numbers> <words>": ParseWay offers those words as both the zone and the title, so they are
-- tried as a zone first and become the destination's name when no such zone exists. There they
-- are a zone only when they are a zone's whole name: a zone name is matched by its start and by
-- letters inside it, so a guide's title "Hill", "Rest" or "A" moved the spot to Hillsbrad
-- Foothills, Silverpine Forest or Alterac Mountains and lost the title.
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
            -- The words were a zone, so they are not a title unless the caller wrote one as well.
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

-------------------------------------------------------------------------------
-- Handing a destination to the navigator
-------------------------------------------------------------------------------
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

-- The destination the running journey is heading for, for the "this replaced that" notice.
local function currentDestination()
    local Navigator = FGPS.Navigator
    if not Navigator then return nil end
    if Navigator.GetStops then
        -- The itinerary holds destination tables directly; the unwrap is for a caller that hands
        -- back route-style records instead.
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

-- Compat.Accept(dest, opts) -> bool
-- The single door every waypoint in this file goes through. opts:
--   addStop = true      add the place as another stop instead of replacing the journey
--   silent = true       do not print the confirmation line (the notice about a replaced journey
--                       is still printed: losing a journey is never silent)
--   source = string     where the waypoint came from, for the log
function Compat.Accept(dest, opts)
    opts = opts or {}
    local Search = FGPS.UI.Search
    if type(dest) ~= "table" then return false end
    local running = journeyRunning()
    local previous = running and currentDestination() or nil

    if opts.addStop then
        -- quiet: Compat prints the one "Added a stop" line; Navigator must not also say Destination set.
        if Search and Search.GoTo then Search.GoTo(dest, "addStop", { quiet = true })
        else
            local Navigator = FGPS.Navigator
            if not Navigator then return false end
            Navigator:SetDestination(dest, { addStop = true, start = false, quiet = true })
        end
        if not opts.silent then FGPS:Print(L["Added a stop: %s"], describe(dest)) end
        return true
    end

    -- A journey in progress is about to be re-routed. Say what is being given up and how to keep
    -- it, before the navigator acts on the new destination. The same waypoint arriving twice is
    -- not a replacement and says nothing.
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

    -- quiet: Compat owns the player chat line (Waypoint or the replace notice).
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

-------------------------------------------------------------------------------
-- The client's own map pin
-------------------------------------------------------------------------------
-- True when the user waypoint currently set is the one UI/InWorldPin.lua placed for the running
-- journey. Taking our own marker as a new destination would be a loop, not interoperability.
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

-- Compat.FromUserWaypoint() -> dest|nil, reason
-- The place the client's own map pin points at, as a Cabbie destination.
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

-------------------------------------------------------------------------------
-- Compatibility entry point
-------------------------------------------------------------------------------
-- Compat.AddWaypoint(uiMapID, x, y, opts) -> uid|nil, reason
--
-- Deliberately the signature waypoint add-ons made the common dialect, so an existing guide needs
-- no rewriting: x and y are NORMALISED map coordinates (0..1), not percentages. Both call styles
-- work, so "Cabbie:AddWaypoint(...)" and "Cabbie.AddWaypoint(...)" mean the same thing.
--
-- Honoured options: opts.title (the destination's name), opts.silent (no chat line),
-- opts.addStop (add a stop instead of replacing the journey; Cabbie's own extension). Every other
-- option of the original add-on (crazy, persistent, minimap, world, callbacks, cleardistance, ...)
-- is accepted and ignored, because Cabbie answers them with its own Route block, minimap dots and
-- map line rather than with a second set of markers.
--
-- The returned uid is an opaque handle for Compat.RemoveWaypoint; it is not the other add-on's
-- table and nothing should read its fields.
function Compat.AddWaypoint(uiMapID, x, y, opts)
    -- Method-call form: Cabbie:AddWaypoint(m, x, y, opts).
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

-- The older five-argument form of the same dialect; the second argument was a dungeon floor and no
-- longer means anything, so it is dropped.
function Compat.AddMFWaypoint(uiMapID, floor, x, y, opts)
    if type(uiMapID) == "table" then
        uiMapID, floor, x, y, opts = floor, x, y, opts, nil
    end
    return Compat.AddWaypoint(uiMapID, x, y, opts)
end

-- Compat.RemoveWaypoint(uid) -> bool
-- Forgets a waypoint this shim handed out. It cancels the journey only when that waypoint is the
-- destination currently being navigated to, and says so.
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

-- Forgets every waypoint this shim handed out. A running journey is left alone; cancelling it is
-- the player's decision, so they are only reminded how.
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

-------------------------------------------------------------------------------
-- Slash handling
-------------------------------------------------------------------------------
local function printWayHelp()
    FGPS:Print(L["Waypoints: /way <x> <y> [zone or title] | /way <zone> <x> <y> [title] | /way <pasted map pin link> | /way pin | /way add <...> | /way clear"])
    FGPS:Print(L["The same words work as /cabbie way ... . Cabbie understands the common waypoint wording so guides need no rewriting; it is not, and does not replace, any other waypoint add-on."])
end

-- Compat.SlashWay(args) -> bool
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

-------------------------------------------------------------------------------
-- The plain "/way" word
-------------------------------------------------------------------------------
-- True when the game itself answers this word: an emote, a chat type, or a command it has
-- already resolved. The client looks a typed word up in its commands before its emotes, so an
-- add-on's command of the same name takes the word away from the game.
-- Inferred from the client's chat code as generally known, not read on this client: three global
-- tables keyed by the word in upper case ("/GO"): hash_EmoteTokenList, hash_ChatTypeInfoList and
-- hash_SlashCmdList (the commands resolved so far, which can be the asker's own: `own`). The
-- emote table may be filled only as emotes are used, so the emotes' words themselves are read
-- too: the globals EMOTE<i>_CMD<j>, i up to MAXEMOTEINDEX. Each of these may be missing.
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

-- True when somebody else already owns this slash word: another add-on, or the game itself. The
-- client keeps an add-on's word in globals named SLASH_<NAME><n>, so the dispatch table's own
-- names are what has to be inspected. own is the handler the asker registers the word with: a
-- word the game has resolved to that handler is the asker's own.
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

-- The client keeps every command it has resolved (hash_SlashCmdList, see above) until /reload,
-- so a /way typed after the setting was switched off can still arrive here although the word was
-- given back (UnregisterWaySlash). The game's table is not written to (taint): the handler asks the
-- setting itself, and answers the typed command with one line instead of acting on it.
local function waySlash(message)
    local c = FGPS.DB and FGPS.DB.settings and FGPS.DB.settings.compat
    if type(c) == "table" and c.wayCommand == false then
        FGPS:Print(L["Cabbie does not answer /way while \"Answer the /way command\" is off in its settings. /cabbie way still works."])
        return
    end
    Compat.SlashWay(message)
end

-- Claims the plain "/way". The word is only taken when nobody else has it: an installed waypoint
-- add-on keeps its own command, and "/cabbie way" stays available either way.
--
-- The client's slash dispatch needs the word itself in a global named after the dispatch entry,
-- which is why these two names are written through _G rather than declared: they are built from
-- the entry name and there is no other way to register a top-level command.
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

-------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------
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
    -- The compatibility entry point on the addon table, so a guide can call Cabbie:AddWaypoint().
    FGPS.AddWaypoint = Compat.AddWaypoint
    FGPS.AddMFWaypoint = Compat.AddMFWaypoint
    FGPS.RemoveWaypoint = Compat.RemoveWaypoint
    FGPS.ClearWaypoints = Compat.ClearWaypoints
    Compat.RegisterWaySlash()
    return Compat
end
