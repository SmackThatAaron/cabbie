



local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local type, tostring, tonumber, format = type, tostring, tonumber, string.format
local min = math.min

local Go = { bound = false, slashRegistered = false }
FGPS.UI.Go = Go


local GO_SLASH_NAME = "CABBIEGO"
local GO_WORD = "/go"




local FIRST = { "town", "capital" }


function Go.Start(dest)
    local Navigator = FGPS.Navigator
    if type(dest) ~= "table" or not (Navigator and Navigator.SetDestination) then return false end


    local Search = FGPS.UI.Search
    if Search and Search.CancelServiceSearch then Search:CancelServiceSearch(true) end

    local plain, refused = Navigator:SetDestination(dest, { start = true, quiet = true })
    return not (plain == nil and refused ~= nil)
end

Go.RIDE_HOLD = 6
















function Go.WaitOutTheRide()
    local Navigator = FGPS.Navigator
    if not (Navigator and Navigator.pendingReroute) then return false end
    if Navigator.GetState and Navigator:GetState() == "paused" and Navigator.Resume then Navigator:Resume() end

    local riding = Navigator.riding or (Navigator.GetState and Navigator:GetState() == "in_transit")
    local Guide = FGPS.UI.Guide
    if riding and Guide and Guide.Say then Guide.Say(L["The new route starts when this ride ends"], Go.RIDE_HOLD) end
    return true
end



local function fromCoordinates(text)
    local Destinations = FGPS.Destinations
    if not (Destinations and Destinations.ParseCoords and Destinations.FromCoords) then return nil end
    local zone, x, y = Destinations.ParseCoords(text)
    if not (x and y) then return nil end


    if type(zone) == "string" and zone:find("^%d+$") then zone = tonumber(zone) end
    if not zone then
        local Coords = FGPS.Coords
        local pos = Coords and Coords.PlayerPos and Coords.PlayerPos()
        zone = pos and pos.map or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
    end
    if not zone then return nil, L["Add a zone name after the two numbers."] end
    local dest, err = Destinations.FromCoords(zone, x, y)
    if dest then return dest end


    if err == "unknown_zone" then return nil, format(L["No zone is called '%s'."], tostring(zone)) end
    if err == "range" then return nil, L["Each of the two numbers goes from 0 to 100."] end
    return nil, L["Those numbers are not a place on that map."]
end



local function bestMatch(text)
    local Destinations = FGPS.Destinations
    local results = Destinations and Destinations.Search and Destinations.Search(text, { limit = 1, first = FIRST }) or {}
    local best = results[1]
    if not best then return nil end
    return best.dest or best, best.label
end




function Go.FromText(text)
    text = Util.Trim(type(text) == "string" and text or "")
    local Line, Rows = FGPS.UI.SearchLine, FGPS.UI.SearchRows
    if text == "" then

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




    if Rows and Rows.For and Rows.Tied and Rows.Start then
        local rows, service = Rows.For(text, 1)
        local listed = #text >= (Rows.MIN_LETTERS or 1)
        if listed and Rows.Tied(rows, service) and Line and Line.Open and Line.Open(text) then return false end
        if rows[1] then return Rows.Start(rows[1]) end
        FGPS:Print(L["No place matches '%s'."], text)
        return false
    end

    local match = bestMatch(text)
    if not match then
        FGPS:Print(L["No place matches '%s'."], text)
        return false
    end
    return Go.Start(match)
end






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



local function plain(text)
    return (Util.Lower(Util.Trim(text)):gsub("%s+", " "):gsub("^the ", ""))
end



local function isWholeName(text, dest)
    if type(dest.name) ~= "string" then return false end
    local typed = plain(text)
    return plain(dest.name) == typed or plain((dest.name:gsub("%s*%b()%s*$", ""))) == typed
end





local BY_LEADING_WORDS = { town = true, capital = true, zone = true }





local function beginsName(text, dest)
    if type(dest.name) ~= "string" or not BY_LEADING_WORDS[dest.type] then return false end
    local typed, name = plain(text), plain(dest.name)
    return name:sub(1, #typed + 1) == typed .. " "
end















function Go.FromUnknownCommand(text)
    text = Util.Trim(type(text) == "string" and text or "")
    if text == "" then return Go.FromText(text) end
    local dest, label = bestMatch(text)
    local word = text:match("^%S+")
    local command = nearestCommand(word)
    if dest and type(dest.name) == "string" and plain(dest.name) == plain(text) and (not command or word ~= text) then
        return Go.Start(dest)
    end


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






local function goSlash(message)
    FGPS.Slash.Dispatch("go " .. tostring(message or ""))
end





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


    FGPS.Events:Register("ADDON_READY", function() Go.RegisterSlash() end, Go)
end
