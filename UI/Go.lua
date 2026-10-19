-- Cabbie/UI/Go.lua
-- The one way the new entry points start a route: a Shift-click on the map, "Take me there" on a
-- quest, and a typed place all end in Go.Start, which begins guidance at once. There is no
-- preview step and no chat line; the Route block shows where the route leads.
local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local type, tostring, tonumber, format = type, tostring, tonumber, string.format
local min = math.min

local Go = { bound = false, slashRegistered = false }
FGPS.UI.Go = Go

-- The dispatch entry of the plain "/go"; the word itself is in the global SLASH_CABBIEGO1.
local GO_SLASH_NAME = "CABBIEGO"
local GO_WORD = "/go"

-- A town or a capital the typed name matches comes first, whichever side it belongs to: by score
-- alone "crossroads" was the Crossroads Graveyard in the Wetlands. Landmarks are not in the list,
-- or "inn" would be the Shady Rest Inn in Dustwallow Marsh instead of the nearest innkeeper.
local FIRST = { "town", "capital" }

-- Starts guidance to dest. Returns false when there is nothing to start.
function Go.Start(dest)
    local Navigator = FGPS.Navigator
    if type(dest) ~= "table" or not (Navigator and Navigator.SetDestination) then return false end
    -- A "Nearest" search of the search window that is still running routes to several candidates
    -- one after the other, and the route asked for now would wait behind them (as Search.GoTo).
    local Search = FGPS.UI.Search
    if Search and Search.CancelServiceSearch then Search:CancelServiceSearch(true) end
    -- The navigator answers nil and a reason for a destination it cannot use (no coordinates).
    local plain, refused = Navigator:SetDestination(dest, { start = true, quiet = true })
    return not (plain == nil and refused ~= nil)
end

Go.RIDE_HOLD = 6            -- seconds the line about a route that waits for a ride's end is shown

-- For a control that starts the route to the stops as they are ("/cabbie start", Start in the
-- old preview window). It acts when a re-route waits (Navigator.pendingReroute) and answers
-- whether one did. A re-route waits because another place was set during a flight or a boat ride,
-- or because the control's own start was asked for during one: the navigator works no route out
-- from the middle of a ride and keeps both for its end (Navigator:Reroute, Navigator:Start). The
-- control calls this first, and asks the navigator for nothing when a re-route waited already;
-- and once more after its own start, which the navigator may just have kept.
--
-- What it does for a re-route that waits: a route that is paused is made to go on, because the
-- re-route is issued on a route that is being followed; and while the ride is still under way the
-- player is told in the call-out when the new route starts (a notice: it answers a click or a
-- typed command). The ride can have ended while the route was paused. Then the resume issues the
-- re-route at once, the way is being found, and nothing is said of a ride.
-- Go.Start itself needs no such care: it sets a place, which the navigator keeps for the end of
-- the ride by itself.
function Go.WaitOutTheRide()
    local Navigator = FGPS.Navigator
    if not (Navigator and Navigator.pendingReroute) then return false end
    if Navigator.GetState and Navigator:GetState() == "paused" and Navigator.Resume then Navigator:Resume() end
    -- Asked after the resume, by the navigator's own condition for a ride under way (Reroute).
    local riding = Navigator.riding or (Navigator.GetState and Navigator:GetState() == "in_transit")
    local Guide = FGPS.UI.Guide
    if riding and Guide and Guide.Say then Guide.Say(L["The new route starts when this ride ends"], Go.RIDE_HOLD) end
    return true
end

-- "42.5 65.1" or "42.5 65.1 Elwynn Forest": dest, or nil when the text is not two numbers, or
-- nil and a sentence when the numbers cannot be placed.
local function fromCoordinates(text)
    local Destinations = FGPS.Destinations
    if not (Destinations and Destinations.ParseCoords and Destinations.FromCoords) then return nil end
    local zone, x, y = Destinations.ParseCoords(text)
    if not (x and y) then return nil end
    -- A number where the zone name goes is a map id: "42 65 1429". In plain digits only: tonumber
    -- also reads "0x595", "1e3" and, on some systems, "nan" and "inf", and none of them is one.
    if type(zone) == "string" and zone:find("^%d+$") then zone = tonumber(zone) end
    if not zone then
        local Coords = FGPS.Coords
        local pos = Coords and Coords.PlayerPos and Coords.PlayerPos()
        zone = pos and pos.map or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
    end
    if not zone then return nil, L["Add a zone name after the two numbers."] end
    local dest, err = Destinations.FromCoords(zone, x, y)
    if dest then return dest end
    -- FromCoords answers with a short code ("unknown_zone", "range", "no_world"); the player
    -- gets a sentence.
    if err == "unknown_zone" then return nil, format(L["No zone is called '%s'."], tostring(zone)) end
    if err == "range" then return nil, L["Each of the two numbers goes from 0 to 100."] end
    return nil, L["Those numbers are not a place on that map."]
end

-- The best match of a typed name and the words the search labels it with (name, zone, kind), or
-- nil. A service word ("bank", "inn") is the nearest of its kind; the engine ranks the rest.
local function bestMatch(text)
    local Destinations = FGPS.Destinations
    local results = Destinations and Destinations.Search and Destinations.Search(text, { limit = 1, first = FIRST }) or {}
    local best = results[1]
    if not best then return nil end
    return best.dest or best, best.label
end

-- Starts the route to a typed place: two numbers (with or without a zone name) or a name. The
-- search list ranks the matches; the best one starts, or the line opens when two are equally good.
-- Chat is used only when nothing can be started and nothing opens.
function Go.FromText(text)
    text = Util.Trim(type(text) == "string" and text or "")
    local Line, Rows = FGPS.UI.SearchLine, FGPS.UI.SearchRows
    if text == "" then
        -- "/go" with nothing after it opens the line. The sentence is for a client without it.
        if Line and Line.Open and Line.Open() then return false end
        FGPS:Print(L["Type a place after the command, for example: /go Goldshire"])
        return false
    end
    local dest, problem = fromCoordinates(text)
    if dest then return Go.Start(dest) end
    if problem then
        FGPS:Print("%s", problem)
        return false
    end
    -- A name: the best row of the search list, which holds places, services and quests in one
    -- order (UI/SearchRows.lua). Two rows that are equally good start nothing: the line opens
    -- with the text filled in and shows them. One letter starts its best row all the same: the
    -- line searches from Rows.MIN_LETTERS letters on and would show the guide instead.
    if Rows and Rows.For and Rows.Tied and Rows.Start then
        local rows, service = Rows.For(text, 1)
        local listed = #text >= (Rows.MIN_LETTERS or 1)
        if listed and Rows.Tied(rows, service) and Line and Line.Open and Line.Open(text) then return false end
        if rows[1] then return Rows.Start(rows[1]) end
        FGPS:Print(L["No place matches '%s'."], text)
        return false
    end
    -- Without the list (its file failed to load): the best place, as before.
    local match = bestMatch(text)
    if not match then
        FGPS:Print(L["No place matches '%s'."], text)
        return false
    end
    return Go.Start(match)
end

-------------------------------------------------------------------------------
-- "/cabbie <text>" when the first word is not a command
-------------------------------------------------------------------------------
-- How many single letters have to be added, dropped or changed to make b out of a, two
-- neighbouring letters that swapped places counting as one (Damerau-Levenshtein, the plain table).
local function editDistance(a, b)
    local d = {}
    for i = 0, #a do d[i] = { [0] = i } end
    for j = 0, #b do d[0][j] = j end
    for i = 1, #a do
        for j = 1, #b do
            local same = a:sub(i, i) == b:sub(j, j)
            local best = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (same and 0 or 1))
            if i > 1 and j > 1 and a:sub(i, i) == b:sub(j - 1, j - 1) and a:sub(i - 1, i - 1) == b:sub(j, j) then
                best = min(best, d[i - 2][j - 2] + 1)
            end
            d[i][j] = best
        end
    end
    return d[#a][#b]
end

-- The command a word that is no command most likely stood for, or nil: a command it is the
-- first three or more letters of ("paus", "star"), a command one edit away ("cancle", "halp"),
-- or two edits away for a word of six letters or more. The closest wins, then the one that comes
-- first in "/cabbie help".
local function nearestCommand(word)
    local Slash = FGPS.Slash
    if not (Slash and Slash.order) then return nil end
    word = Util.Lower(word)
    local best, bestDistance
    for _, command in ipairs(Slash.order) do
        local distance = editDistance(word, command)
        local near = distance == 1 or (distance == 2 and #word >= 6) or (#word >= 3 and command:sub(1, #word) == word)
        if near and (not bestDistance or distance < bestDistance) then best, bestDistance = command, distance end
    end
    return best
end

-- How a typed name and a place's name are compared: lower case, no spaces around it, single
-- spaces inside, and without a "the" in front ("crossroads" is The Crossroads).
local function plain(text)
    return (Util.Lower(Util.Trim(text)):gsub("%s+", " "):gsub("^the ", ""))
end

-- True when what was typed is the place's whole name. The words in brackets after a person's
-- name say what they do ("Officer Areyn (Accessories Quartermaster)") and need not be typed.
local function isWholeName(text, dest)
    if type(dest.name) ~= "string" then return false end
    local typed = plain(text)
    return plain(dest.name) == typed or plain((dest.name:gsub("%s*%b()%s*$", ""))) == typed
end

-- The kinds of place that whole words from the beginning of the name are enough for. A person, a
-- service and a landmark need their whole name: measured on the bundled data, the best match of
-- "officer" is a quartermaster called Officer Areyn, of "captain" a trainer, of "tower" the Tower
-- of Ilgalar and of "forest" Forest Song.
local BY_LEADING_WORDS = { town = true, capital = true, zone = true }

-- True when what was typed is, for a town, a capital or a zone, whole words from the beginning
-- of its name: the name goes on with a space. The first letters of a word are not enough at any
-- length ("home" is not Homer Stonefield, "gold" is not Goldshire), and how the search scored the
-- place does not count.
local function beginsName(text, dest)
    if type(dest.name) ~= "string" or not BY_LEADING_WORDS[dest.type] then return false end
    local typed, name = plain(text), plain(dest.name)
    return name:sub(1, #typed + 1) == typed .. " "
end

-- What "/cabbie <text>" does when the first word is not a command (Slash.Dispatch hands the whole
-- line over). A route that starts replaces the stops without a word, so this is stricter than
-- "/go": measured on the bundled data, the best match of "off" is Officer Areyn, of "menu" Peria
-- Lamenur, of "star" Starbreeze Village and of "home" Homer Stonefield, a fruit seller.
--   1. The whole name of the best match, word for word, starts it, also when it has two words
--      or more and the first is nearly a command ("dark portal" and "mark", "refuge pointe" and
--      "resume").
--   2. A first word that is nearly a command is a command mistyped. Nothing starts, also when
--      that one word is a place's whole name ("vice" is The Vice, and one letter from "voice").
--   3. Two map numbers are a spot, as for "/go".
--   4. A name starts when it is the best match's whole name without the words in brackets, or,
--      for a town, a capital or a zone, whole words from its beginning. The player did not name
--      that place in full, so one line says which place was chosen ("camp" is Camp Mojache).
--   5. Anything else starts nothing, and one line says where to go on.
function Go.FromUnknownCommand(text)
    text = Util.Trim(type(text) == "string" and text or "")
    if text == "" then return Go.FromText(text) end
    local dest, label = bestMatch(text)
    local word = text:match("^%S+")
    local command = nearestCommand(word)
    if dest and type(dest.name) == "string" and plain(dest.name) == plain(text) and (not command or word ~= text) then
        return Go.Start(dest)
    end
    -- The advice names the word Cabbie answers: "/go" belongs to somebody else where RegisterSlash
    -- stepped aside, and "/cabbie go" is Cabbie's either way.
    local goWord = Go.slashRegistered and GO_WORD or "/cabbie go"
    if command then
        FGPS:Print(L["'%s' is not a command. Did you mean /cabbie %s? /cabbie help lists the commands, and %s %s looks for a place."],
            word, command, goWord, text)
        return false
    end
    local Destinations = FGPS.Destinations
    if Destinations and Destinations.ParseCoords and select(2, Destinations.ParseCoords(text)) then
        return Go.FromText(text)
    end
    if dest and isWholeName(text, dest) then return Go.Start(dest) end
    if dest and beginsName(text, dest) then
        local started = Go.Start(dest)
        if started then FGPS:Print(L["Going to %s."], type(label) == "string" and label or dest.name) end
        return started
    end
    if dest then
        FGPS:Print(L["'%s' is neither a command nor enough of a place name to start a route. /cabbie help lists the commands, and %s %s looks for a place."],
            text, goWord, text)
    else
        FGPS:Print(L["'%s' is neither a command nor a place Cabbie knows. /cabbie help lists the commands."], text)
    end
    return false
end

-------------------------------------------------------------------------------
-- The plain "/go"
-------------------------------------------------------------------------------
-- Through the registry: "/go x" is "/cabbie go x", also when the lookup raises (one line of chat,
-- L.SLASH_FAILED, and the error in the log).
local function goSlash(message)
    FGPS.Slash.Dispatch("go " .. tostring(message or ""))
end

-- Claims "/go" when nobody else has it: an add-on that answers the word already keeps it, and so
-- does the game (an emote or a chat type of that name: Compat.SlashWordTaken says how that is
-- told, which is inferred and not seen on this client). "/cabbie go" is there either way. The two
-- names are written through _G, as UI/Compat.lua writes "/way", so that no bare global is assigned.
function Go.RegisterSlash()
    if type(SlashCmdList) ~= "table" then return false end
    if Go.slashRegistered then return true end
    local Compat = FGPS.UI.Compat
    if Compat and Compat.SlashWordTaken and Compat.SlashWordTaken(GO_WORD, goSlash) then
        local Log = FGPS.Log
        if Log and Log.Info then Log:Info("Another add-on or the game already owns %s; a typed place stays on /cabbie go", GO_WORD) end
        return false
    end
    _G["SLASH_" .. GO_SLASH_NAME .. "1"] = GO_WORD
    SlashCmdList[GO_SLASH_NAME] = goSlash
    Go.slashRegistered = true
    return true
end

function Go:Init()
    if self.bound then return end
    self.bound = true
    local Slash = FGPS.Slash
    if Slash and Slash.Register then
        Slash.Register("go", function(args) Go.FromText(args) end, L["Go to a place by name or by two map numbers"])
    end
    -- The plain word waits until every module is up: who else answers "/go" is asked of
    -- UI/Compat.lua, which loads later.
    FGPS.Events:Register("ADDON_READY", function() Go.RegisterSlash() end, Go)
end
