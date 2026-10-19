-- Cabbie/UI/SearchRows.lua
-- What the search list holds. Pure logic: it turns a typed text into at most eight rows (places,
-- services and quests in one list), says in which order, what a row starts, and gives the rows of
-- the first-run guide. It creates no frame and listens to nothing; UI/SearchLine.lua paints.
-- The matching is the engine's: Destinations.Search for places and services, Quests.List for the
-- quests of the log, QuestData.SearchTitles for quests that can be picked up, and
-- ServiceSearch.Nearest for the order of a service along the route.
local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local type, ipairs, pcall = type, ipairs, pcall
local sort, insert, concat = table.sort, table.insert, table.concat
local huge = math.huge

local Rows = {}
FGPS.UI.SearchRows = Rows

Rows.MAX = 8                    -- rows in the list
Rows.MIN_LETTERS = 2            -- one letter matches nearly every place and is not searched
Rows.COST_CEILING = 2000000     -- Lua VM instructions one search may cost (tests/test_searchrows.lua)
Rows.NO_PLACE_HOLD = 4          -- seconds the call-out says that a quest has no known place

-- The words that ask for a kind of service instead of a name, and the type Nav/Services.lua
-- knows it by. The whole typed text is looked up, so "stormwind bank" stays a name search.
Rows.SERVICE_WORDS = {
    inn = "inn", innkeeper = "inn",
    bank = "bank", banker = "bank",
    flight = "flightmaster", ["flight master"] = "flightmaster", flightmaster = "flightmaster",
    repair = "repair",
    mail = "mailbox", mailbox = "mailbox",
    vendor = "vendor",
    trainer = "trainer",
    stable = "stable", ["stable master"] = "stable",
    auction = "auction", ["auction house"] = "auction", auctioneer = "auction",
}

-- A town or a capital the text names comes first, as for a typed "/go" (UI/Go.lua).
local FIRST = { "town", "capital" }
local LEADING = { town = true, capital = true }
-- The icon of a place by its type (UI/Look.lua knows the kinds); any other type is a "place".
local TYPE_ICON = {
    flightmaster = "flight", taxi = "flight", inn = "inn", bank = "bank", repair = "repair", mailbox = "mail",
    vendor = "vendor", trainer = "trainer", stable = "stable", auction = "auction", dungeon = "dungeon", raid = "dungeon",
}
Rows.TYPE_ICON = TYPE_ICON       -- read by UI/Search.lua for the icons of the old window's rows
-- The place types a service word asks for.
local SERVICE_TYPES = {
    inn = { inn = true }, bank = { bank = true }, flightmaster = { flightmaster = true, taxi = true },
    repair = { repair = true }, mailbox = { mailbox = true }, vendor = { vendor = true, repair = true },
    trainer = { trainer = true }, stable = { stable = true }, auction = { auction = true },
}
local SIDE_WORDS = { [1] = "Alliance", [2] = "Horde" }

-- How a typed text is compared: lower case, no spaces around it, single spaces inside.
local function plain(text)
    return (Util.Lower(Util.Trim(type(text) == "string" and text or "")):gsub("%s+", " "))
end

-- The service a text asks for: the type to hand to ServiceSearch.Nearest and its plain kind, or
-- nil. "trainer" is the trainer of the player's class when the class is known: asked for any of
-- the 25 trades, a warrior got cooks and enchanters.
function Rows.Service(text)
    local base = Rows.SERVICE_WORDS[plain(text)]
    if base == "trainer" then
        local Services = FGPS.ServiceSearch
        local class = Services and Services.PlayerClass and Services.PlayerClass() or nil
        if class then return "trainer:" .. class, base end
    end
    return base, base
end

-- How well a name matches a typed text, on the engine's scale (Destinations.ScoreName).
function Rows.Score(name, text)
    local Destinations = FGPS.Destinations
    local a, b = plain(name), plain(text)
    if a == "" or b == "" or not (Destinations and Destinations.ScoreName) then return 0 end
    return Destinations.ScoreName(a, b)
end

-- Where in a name (in lower case) the typed letters stand: the whole text where it is in the
-- name, else each typed word where it is. A list of { first, last }, in the order of the name.
local function spans(lowerName, typed)
    local first, last = lowerName:find(typed, 1, true)
    if first then return { { first, last } } end
    local list = {}
    for word in typed:gmatch("%S+") do
        local wordFirst, wordLast = lowerName:find(word, 1, true)
        if wordFirst then list[#list + 1] = { wordFirst, wordLast } end
    end
    sort(list, function(a, b) return a[1] < b[1] end)
    return list
end

-- The name with the typed letters in gold. The name as it is when nothing of the text is in it.
function Rows.Mark(name, text)
    if type(name) ~= "string" then return "" end
    local typed = plain(text)
    local Look = FGPS.UI.Look
    if typed == "" or not (Look and Look.Tint) then return name end
    local out, at = {}, 1
    for _, span in ipairs(spans(Util.Lower(name), typed)) do
        if span[1] >= at then
            out[#out + 1] = name:sub(at, span[1] - 1)
            out[#out + 1] = Look.Tint(name:sub(span[1], span[2]), "match")
            at = span[2] + 1
        end
    end
    out[#out + 1] = name:sub(at)
    return concat(out)
end

-- One result of the place search as a row. A place of the kind a service word asks for is a
-- service row; it and a town or a capital the text names lead the list.
local function placeRow(result, base)
    local dest = type(result) == "table" and result.dest or nil
    if type(dest) ~= "table" or type(dest.name) ~= "string" then return nil end
    local zone = dest.zoneName
    if zone == dest.name then zone = nil end
    if result.otherFaction and SIDE_WORDS[dest.faction] then
        zone = (zone and zone ~= "" and (zone .. ", ") or "") .. L[SIDE_WORDS[dest.faction]]
    end
    local score = type(result.score) == "number" and result.score or 0
    local service = base ~= nil and SERVICE_TYPES[base] ~= nil and SERVICE_TYPES[base][dest.type] == true
    return {
        kind = service and "service" or "place",
        icon = TYPE_ICON[dest.type] or "place",
        name = dest.name, zone = zone, yards = result.distance, score = score, dest = dest,
        lead = service or (LEADING[dest.type] == true and score >= 60),
        group = service and 0 or (LEADING[dest.type] and 1 or 3),
    }
end

-- The quests of the log whose title matches, best first, and every quest of the log by its
-- number (so that none of them is offered for pick-up as well).
local function logQuests(typed)
    local out, inLog = {}, {}
    local Quests, Destinations = FGPS.Quests, FGPS.Destinations
    if not (Quests and Quests.List) then return out, inLog end
    local ok, list = pcall(Quests.List)
    if not ok or type(list) ~= "table" then return out, inLog end
    local pos = Destinations and Destinations.PlayerPos and Destinations.PlayerPos() or nil
    for _, q in ipairs(list) do
        inLog[q.questID] = true
        -- A stand-in ("Quest 362") is no title the player could type.
        local score = q.titleKnown ~= false and Rows.Score(q.title, typed) or 0
        if score > 0 then
            local row = { kind = "quest", icon = q.complete and "questReady" or "quest", name = q.title, score = score,
                          group = 2, lead = false, questID = q.questID }
            -- Where it leads next, for the zone and the distance; asking costs no route.
            local stepped, step = pcall(Quests.NextStep, q.questID)
            if stepped and type(step) == "table" then
                row.zone = step.zoneName
                if pos and pos.inst == step.inst and pos.x and pos.y and step.x and step.y then
                    row.yards = Destinations.Distance(pos.x, pos.y, step.x, step.y)
                end
            end
            out[#out + 1] = row
        end
    end
    sort(out, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.name < b.name
    end)
    return out, inLog
end

local function flaggedDone(questID)
    if not (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) then return false end
    local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, questID)
    return ok and done == true
end

-- Asked by the quest's id: a quest under a collapsed header of the log may be missing from
-- Nav/Quests.lua's walk of it, and the character holds it all the same.
local function onQuest(questID)
    if not (C_QuestLog and C_QuestLog.IsOnQuest) then return false end
    local ok, on = pcall(C_QuestLog.IsOnQuest, questID)
    return ok and not (issecretvalue and issecretvalue(on)) and on == true
end

-- The quests that can be picked up and whose title matches: the title is known, the record names
-- a giver's place, the quest is not in the log (nor held under a collapsed header) and is not done.
local function pickups(typed, inLog)
    local out = {}
    local QuestData = FGPS.QuestData
    if not (QuestData and QuestData.SearchTitles) then return out end
    local ok, found = pcall(QuestData.SearchTitles, typed, { limit = Rows.MAX * 2 })
    if not ok or type(found) ~= "table" then return out end
    for _, quest in ipairs(found) do
        if type(quest.title) == "string" and quest.hasStart and not inLog[quest.questID] and not onQuest(quest.questID)
                and not flaggedDone(quest.questID) then
            out[#out + 1] = { kind = "pickup", icon = "pickup", name = quest.title, zone = quest.startName, yards = quest.yards,
                              score = quest.score or Rows.Score(quest.title, typed), group = 4, lead = false, questID = quest.questID }
        end
    end
    return out
end

-- Puts a quest into the list: ahead of the first row that does not lead and matches less well, or
-- matches as well and belongs to a later group. The places keep the order the engine gave them.
local function mergeIn(rows, quest)
    for i, row in ipairs(rows) do
        if not row.lead and (row.score < quest.score or (row.score == quest.score and quest.group < row.group)) then
            insert(rows, i, quest)
            return
        end
    end
    rows[#rows + 1] = quest
end

-- Rows.For(text, minLetters) -> rows, serviceType
-- The rows for a typed text, at most Rows.MAX, and the service the text asks for (nil for a
-- name). Nothing for a text shorter than minLetters (Rows.MIN_LETTERS when it is not given).
-- A place search that raises is passed on to the caller; the quest lookups are not (a list of
-- places is worth showing without them).
-- A row: { kind = "place"|"service"|"quest"|"pickup", icon, name, zone, yards, score, group,
--          lead, dest (place, service) | questID (quest, pickup) }
function Rows.For(text, minLetters)
    local typed = plain(text)
    if #typed < (minLetters or Rows.MIN_LETTERS) then return {}, nil end
    local service, base = Rows.Service(typed)
    -- "trainer" for a known class keeps the trainers of that class alone, read from the name as
    -- Nav/Services.lua does. The nearest eight trainers may all be of other trades, so the place
    -- search is then asked for every trainer (about 300 of one side, some 100,000 instructions more).
    local Services = FGPS.ServiceSearch
    local trainerKind = Services and Services.TrainerKind or nil
    local class = trainerKind and type(service) == "string" and service:match("^trainer:(.+)$") or nil
    local rows = {}
    local Destinations = FGPS.Destinations
    if Destinations and Destinations.Search then
        -- Not under pcall: a typed "/go" answers a lookup that raises as a failed command
        -- (UI/Go.lua), and the search line catches it where it calls this (UI/SearchLine.lua).
        local found = Destinations.Search(typed, { limit = class and huge or Rows.MAX, first = FIRST })
        if type(found) == "table" then
            -- A capital and the zone of its name ("Ironforge") lead to the same city and their rows
            -- would read alike: the zone's is left out, whichever of the two the engine gave first.
            local cities = {}
            for _, result in ipairs(found) do
                local dest = type(result) == "table" and result.dest or nil
                if type(dest) == "table" and LEADING[dest.type] and type(dest.name) == "string" then cities[dest.name] = true end
            end
            -- A row of the same name and the same zone as one already listed reads alike too, and
            -- the player could not tell the two apart (a dungeon and the landmark at its door, two
            -- graveyards of one name in one city): the first the engine gave stays. A service row
            -- is kept: the nearest of a service often share a name ("Mailbox", Stormwind City),
            -- and their distances tell them apart.
            local listed = {}
            for _, result in ipairs(found) do
                local row = placeRow(result, base)
                local key = row and row.kind ~= "service" and (row.name .. "\0" .. (row.zone or "")) or nil
                local twin = row and ((row.dest.type == "zone" and cities[row.name]) or (key and listed[key]))
                local otherTrade = row and class and row.dest.type == "trainer" and trainerKind(row.name) ~= class
                if row and not twin and not otherTrade then
                    rows[#rows + 1] = row
                    if key then listed[key] = true end
                    if #rows >= Rows.MAX then break end
                end
            end
        end
    end
    local quests, inLog = logQuests(typed)
    for _, quest in ipairs(quests) do mergeIn(rows, quest) end
    for _, quest in ipairs(pickups(typed, inLog)) do mergeIn(rows, quest) end
    while #rows > Rows.MAX do rows[#rows] = nil end
    return rows, service
end

-- True when the two best rows are equally good: the same match and the same group, and no
-- service word was typed (the nearest is the answer to one). A typed "/go" then starts nothing
-- and shows the list.
function Rows.Tied(rows, service)
    local first, second = type(rows) == "table" and rows[1] or nil, type(rows) == "table" and rows[2] or nil
    if service or not (first and second) then return false end
    return first.score == second.score and first.group == second.group
end

-- Starts guidance to a row. A place or a service through Go.Start; a quest of the log as "Take
-- me there" does (its next place, and the quest gets the game's focus); a quest that can be
-- picked up to its giver. A quest without a known place is answered in the call-out, in the
-- sentence "Take me there" says for that reason (UI/Menus.lua). It shows the way and does
-- nothing else.
function Rows.Start(row)
    if type(row) ~= "table" then return false end
    local Go, Guide, Menus = FGPS.UI.Go, FGPS.UI.Guide, FGPS.UI.Menus
    if row.kind == "quest" then
        return Menus ~= nil and Menus.TakeMeThere ~= nil and Menus.TakeMeThere(row.questID) == true
    end
    if row.kind == "pickup" then
        local Quests = FGPS.Quests
        local dest, reason
        if Quests and Quests.DestinationFor then dest, reason = Quests.DestinationFor(row.questID, "giver") end
        if not dest then
            local text = Menus and Menus.NoPlaceText and Menus.NoPlaceText(reason, row.questID) or L["No place known for this quest"]
            if Guide and Guide.Say then Guide.Say(text, Rows.NO_PLACE_HOLD) end
            return false
        end
        return Go ~= nil and Go.Start ~= nil and Go.Start(dest) == true
    end
    if type(row.dest) ~= "table" or not (Go and Go.Start) then return false end
    return Go.Start(row.dest) == true
end

-- Rows.Nearest(serviceType, base, callback) -> bool
-- Asks the engine for the nearest of a service along the route (up to Rows.MAX; it works out a
-- route to each of the closest few, over several frames) and hands the callback their rows in
-- that order, or nil when the search ended without a list (no position, none near, cancelled).
-- false, and no callback, without the engine's search or without a callback.
function Rows.Nearest(service, base, callback)
    local Services = FGPS.ServiceSearch
    if type(callback) ~= "function" or not (Services and Services.Nearest) then return false end
    return Services.Nearest(service, { limit = Rows.MAX }, function(list, err)
        if err ~= nil or type(list) ~= "table" or #list == 0 then
            callback(nil)
            return
        end
        local rows = {}
        for _, entry in ipairs(list) do
            local dest = entry.dest
            if type(dest) == "table" and type(dest.name) == "string" then
                rows[#rows + 1] = { kind = "service", icon = TYPE_ICON[base] or TYPE_ICON[dest.type] or "place", name = dest.name,
                                    zone = dest.zoneName, yards = entry.yards or entry.straightYards, score = 100, group = 0,
                                    lead = true, dest = dest }
            end
        end
        callback(rows)
    end) == true
end

-------------------------------------------------------------------------------
-- The first-run guide
-------------------------------------------------------------------------------
-- Rows.Guide(noField) -> rows, title
-- How to use Cabbie without typing a command, as rows of the list: { kind = "guide", key, icon,
-- text }. A row is there only while what it describes exists in this client and is switched on,
-- so the guide never promises a click that does nothing. noField is true where the guide stands
-- with nothing beside it to type in: by the chat input without the "Go to:" line (the first
-- login, the Route block's menu). The first row then says where to type, because a word typed
-- into the chat input would be said aloud.
function Rows.Guide(noField)
    local rows = {}
    local function add(key, icon, text)
        rows[#rows + 1] = { kind = "guide", key = key, icon = icon, text = text }
    end
    local DB = FGPS.DB
    local function off(setting)
        return DB ~= nil and DB.Get ~= nil and DB:Get(setting) == false
    end
    if noField then
        add("type", "search", L["Open the world map and type a place, a quest, or a word like inn or repair"])
    else
        add("type", "search", L["Type a place, a quest, or a word like inn or repair"])
    end
    -- The Shift-click exists where the map took Cabbie's click handler (UI/WorldMap.lua).
    local WorldMap = FGPS.UI.WorldMap
    if WorldMap and WorldMap.clickHandler and FGPS.UI.Go then
        add("map", "map", L["Shift-click the world map to be guided to that spot"])
    end
    -- A quest. In the game's interface code a left click on a quest's round marker button (in the
    -- quest list or on the map) makes it the focused quest, and a click on its title only opens
    -- its details. With "Follow my quests" on, UI/InWorldPin.lua notices the focus move
    -- (C_SuperTrack) and Menus.QuestSelected starts the way to that quest. Otherwise the entry
    -- "Take me there" in the quest's right-click menu, where the client took it (Menus:Init).
    local Quests, Menus = FGPS.Quests, FGPS.UI.Menus
    local focusWatched = type(C_SuperTrack) == "table" and type(C_SuperTrack.GetSuperTrackedQuestID) == "function"
    if Quests and Quests.FollowsMine and Quests.FollowsMine() and focusWatched and Menus and Menus.QuestSelected then
        add("quest", "pickup", L["Click the round marker beside a quest and Cabbie leads you to it"])
    elseif Menus and Menus.questMenus == true then
        add("quest", "pickup", L["Right-click a quest in your quest list: Take me there"])
    end
    -- A plain click on the block's header opens its menu (UI/Menus.lua, Menus.OnHeaderClick). The
    -- header reads "Route" and then the time and the distance (UI/RouteBlock.lua).
    local RouteBlock = FGPS.UI.RouteBlock
    if RouteBlock and RouteBlock.frame and not off("routeBlock.enabled") then
        add("route", "route", L["Your steps appear beside your quest list. Click the word Route to stop or pause"])
    end
    -- Only while it is true: once a flight map was seen, flights are part of the routes. The
    -- Route block's own line about flights asks the same (Nav/Access.lua), and names the continent
    -- once another one's flight paths are known.
    local Access = FGPS.Access
    local leftOut, where = false, nil
    if Access and Access.FlightsLeftOut then leftOut, where = Access:FlightsLeftOut() end
    if leftOut and type(where) == "string" then
        add("flights", "flight", Util.SafeFormat(L["Flights in %s are used once you have visited a flight master there"], where))
    elseif leftOut then
        add("flights", "flight", L["Flights are used once you have visited a flight master"])
    end
    return rows, L["How to use Cabbie"]
end
