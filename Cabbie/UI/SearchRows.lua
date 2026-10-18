






local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local type, ipairs, pcall = type, ipairs, pcall
local sort, insert, concat = table.sort, table.insert, table.concat
local huge = math.huge

local Rows = {}
FGPS.UI.SearchRows = Rows

Rows.MAX = 8
Rows.MIN_LETTERS = 2
Rows.COST_CEILING = 2000000
Rows.NO_PLACE_HOLD = 4



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


local FIRST = { "town", "capital" }
local LEADING = { town = true, capital = true }

local TYPE_ICON = {
    flightmaster = "flight", taxi = "flight", inn = "inn", bank = "bank", repair = "repair", mailbox = "mail",
    vendor = "vendor", trainer = "trainer", stable = "stable", auction = "auction", dungeon = "dungeon", raid = "dungeon",
}
Rows.TYPE_ICON = TYPE_ICON

local SERVICE_TYPES = {
    inn = { inn = true }, bank = { bank = true }, flightmaster = { flightmaster = true, taxi = true },
    repair = { repair = true }, mailbox = { mailbox = true }, vendor = { vendor = true, repair = true },
    trainer = { trainer = true }, stable = { stable = true }, auction = { auction = true },
}
local SIDE_WORDS = { [1] = "Alliance", [2] = "Horde" }


local function plain(text)
    return (Util.Lower(Util.Trim(type(text) == "string" and text or "")):gsub("%s+", " "))
end




function Rows.Service(text)
    local base = Rows.SERVICE_WORDS[plain(text)]
    if base == "trainer" then
        local Services = FGPS.ServiceSearch
        local class = Services and Services.PlayerClass and Services.PlayerClass() or nil
        if class then return "trainer:" .. class, base end
    end
    return base, base
end


function Rows.Score(name, text)
    local Destinations = FGPS.Destinations
    local a, b = plain(name), plain(text)
    if a == "" or b == "" or not (Destinations and Destinations.ScoreName) then return 0 end
    return Destinations.ScoreName(a, b)
end



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



local function logQuests(typed)
    local out, inLog = {}, {}
    local Quests, Destinations = FGPS.Quests, FGPS.Destinations
    if not (Quests and Quests.List) then return out, inLog end
    local ok, list = pcall(Quests.List)
    if not ok or type(list) ~= "table" then return out, inLog end
    local pos = Destinations and Destinations.PlayerPos and Destinations.PlayerPos() or nil
    for _, q in ipairs(list) do
        inLog[q.questID] = true

        local score = q.titleKnown ~= false and Rows.Score(q.title, typed) or 0
        if score > 0 then
            local row = { kind = "quest", icon = q.complete and "questReady" or "quest", name = q.title, score = score,
                          group = 2, lead = false, questID = q.questID }

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



local function onQuest(questID)
    if not (C_QuestLog and C_QuestLog.IsOnQuest) then return false end
    local ok, on = pcall(C_QuestLog.IsOnQuest, questID)
    return ok and not (issecretvalue and issecretvalue(on)) and on == true
end



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



local function mergeIn(rows, quest)
    for i, row in ipairs(rows) do
        if not row.lead and (row.score < quest.score or (row.score == quest.score and quest.group < row.group)) then
            insert(rows, i, quest)
            return
        end
    end
    rows[#rows + 1] = quest
end








function Rows.For(text, minLetters)
    local typed = plain(text)
    if #typed < (minLetters or Rows.MIN_LETTERS) then return {}, nil end
    local service, base = Rows.Service(typed)



    local Services = FGPS.ServiceSearch
    local trainerKind = Services and Services.TrainerKind or nil
    local class = trainerKind and type(service) == "string" and service:match("^trainer:(.+)$") or nil
    local rows = {}
    local Destinations = FGPS.Destinations
    if Destinations and Destinations.Search then


        local found = Destinations.Search(typed, { limit = class and huge or Rows.MAX, first = FIRST })
        if type(found) == "table" then


            local cities = {}
            for _, result in ipairs(found) do
                local dest = type(result) == "table" and result.dest or nil
                if type(dest) == "table" and LEADING[dest.type] and type(dest.name) == "string" then cities[dest.name] = true end
            end





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




function Rows.Tied(rows, service)
    local first, second = type(rows) == "table" and rows[1] or nil, type(rows) == "table" and rows[2] or nil
    if service or not (first and second) then return false end
    return first.score == second.score and first.group == second.group
end






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

    local WorldMap = FGPS.UI.WorldMap
    if WorldMap and WorldMap.clickHandler and FGPS.UI.Go then
        add("map", "map", L["Shift-click the world map to be guided to that spot"])
    end





    local Quests, Menus = FGPS.Quests, FGPS.UI.Menus
    local focusWatched = type(C_SuperTrack) == "table" and type(C_SuperTrack.GetSuperTrackedQuestID) == "function"
    if Quests and Quests.FollowsMine and Quests.FollowsMine() and focusWatched and Menus and Menus.QuestSelected then
        add("quest", "pickup", L["Click the round marker beside a quest and Cabbie leads you to it"])
    elseif Menus and Menus.questMenus == true then
        add("quest", "pickup", L["Right-click a quest in your quest list: Take me there"])
    end


    local RouteBlock = FGPS.UI.RouteBlock
    if RouteBlock and RouteBlock.frame and not off("routeBlock.enabled") then
        add("route", "route", L["Your steps appear beside your quest list. Click the word Route to stop or pause"])
    end



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
