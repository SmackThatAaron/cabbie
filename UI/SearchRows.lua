-- Cabbie/UI/SearchRows.lua
-- What the search list holds. Pure logic: it turns a typed text into at most eight rows (places
-- and services in one list), says in which order, what a row starts, and gives the rows of the
-- first-run guide. It creates no frame and listens to nothing; UI/SearchLine.lua paints.
-- The matching is the engine's: Destinations.Search for places and services, and
-- ServiceSearch.Nearest for the order of a service along the route.
local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local type, ipairs = type, ipairs
local sort, concat = table.sort, table.concat
local huge = math.huge

local Rows = {}
FGPS.UI.SearchRows = Rows

Rows.MAX = 8                    -- rows in the list
Rows.MIN_LETTERS = 2            -- one letter matches nearly every place and is not searched
Rows.COST_CEILING = 2000000     -- Lua VM instructions one search may cost (tests/test_searchrows.lua)

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
    dummy = "dummy", ["training dummy"] = "dummy", ["target dummy"] = "dummy",
}

-- A town or a capital the text names comes first, as for a typed "/go" (UI/Go.lua).
local FIRST = { "town", "capital" }
local LEADING = { town = true, capital = true }
-- The icon of a place by its type (UI/Look.lua knows the kinds); any other type is a "place".
local TYPE_ICON = {
    flightmaster = "flight", taxi = "flight", inn = "inn", bank = "bank", repair = "repair", mailbox = "mail",
    vendor = "vendor", trainer = "trainer", stable = "stable", auction = "auction", dungeon = "dungeon", raid = "dungeon",
    room = "dungeon", boss = "dungeon",
}
Rows.TYPE_ICON = TYPE_ICON       -- read by UI/Search.lua for the icons of the Places page's rows
-- The place types a service word asks for.
local SERVICE_TYPES = {
    inn = { inn = true }, bank = { bank = true }, flightmaster = { flightmaster = true, taxi = true },
    repair = { repair = true }, mailbox = { mailbox = true }, vendor = { vendor = true, repair = true },
    trainer = { trainer = true }, stable = { stable = true }, auction = { auction = true }, dummy = { dummy = true },
}
-- Sections the Places page groups Destinations.Search results under (1 Places, 2 Quest places,
-- nil Other), so GuardedResultsLast keeps moved service rows inside their own section.
local PLACE_SECTIONS = {
    town = 1, landmark = 1, dungeon = 1, raid = 1, capital = 1, room = 1,
    zone = 1, area = 1, questplace = 2,
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

-- The name with the typed letters in gold (Look's colour role "match"), or in the colour role given
-- (the Places page's "rubric"). The name as it is when nothing of the text is in it.
function Rows.Mark(name, text, role)
    if type(name) ~= "string" then return "" end
    local typed = plain(text)
    local Look = FGPS.UI.Look
    if typed == "" or not (Look and Look.Tint) then return name end
    local out, at = {}, 1
    for _, span in ipairs(spans(Util.Lower(name), typed)) do
        if span[1] >= at then
            out[#out + 1] = name:sub(at, span[1] - 1)
            out[#out + 1] = Look.Tint(name:sub(span[1], span[2]), role or "match")
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

-- The player's access snapshot, or nil when it cannot be built.
local function accessSnapshot()
    local Access = FGPS.Access
    if not (Access and Access.Snapshot) then return nil end
    local ok, access = pcall(Access.Snapshot, Access)
    return ok and access or nil
end

-- Rows.For(text, minLetters) -> rows, serviceType
-- The rows for a typed text, at most Rows.MAX, and the service the text asks for (nil for a
-- name). Nothing for a text shorter than minLetters (Rows.MIN_LETTERS when it is not given).
-- A place search that raises is passed on to the caller.
-- A row: { kind = "place"|"service", icon, name, zone, yards, score, group, lead, dest }
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
    local Go = FGPS.UI and FGPS.UI.Go
    if Go and Go.FromCoordinates then
        local dest = Go.FromCoordinates(typed)
        if type(dest) == "table" then
            local yards
            local Coords = FGPS.Coords
            local pos = Coords and Coords.PlayerPos and Coords.PlayerPos()
            if pos and Coords.WorldDistance then
                yards = Coords.WorldDistance(pos.inst, pos.x, pos.y, dest.inst, dest.x, dest.y)
            end
            rows[1] = {
                kind = "place", icon = "map", name = dest.name, zone = dest.zoneName,
                yards = yards, score = 100, group = 0, lead = true, dest = dest,
            }
        end
    end
    local placed = #rows
    local function collect(limit, cap)
        local Destinations = FGPS.Destinations
        if Destinations and Destinations.Search then
            -- Not under pcall: a typed "/go" answers a lookup that raises as a failed command
            -- (UI/Go.lua), and the search line catches it where it calls this (UI/SearchLine.lua).
            -- Twins are dropped after the search returns. Asking for only the eight rows can then
            -- leave the list short ("thunder bluff"). Four more covers those drops. A class trainer
            -- still asks for every trainer.
            local found = Destinations.Search(typed, { limit = limit, first = FIRST })
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
                        if #rows >= cap then break end
                    end
                end
            end
        end
    end
    collect(class and huge or (Rows.MAX + 4), Rows.MAX)
    -- "Keep out of the other side's towns": a service row inside one of the other side's places
    -- (Astranaar's mailbox for the Horde) goes after the others, as "Nearest" leaves it out, so a
    -- typed "/go mailbox" or Enter does not start the way into the town. When every row the short
    -- search gave is such a place (near Darkshire, eight Alliance places), the search is asked for
    -- every service of the kind, so the nearest one outside them leads, as Nearest picks it. With no
    -- such service within Nearest's reach (Dolanaar for the Horde), nothing moves, as Nearest then
    -- offers the ones in the town.
    local outsideNear = service and Services and Services.AnyOutsideGuarded and Services.AnyOutsideGuarded(service, accessSnapshot())
    if outsideNear and Rows.GuardedLast(rows) and rows[placed + 1] and rows[placed + 1].guarded then
        for i = #rows, placed + 1, -1 do rows[i] = nil end
        collect(huge, huge)
        Rows.GuardedLast(rows)
    end
    while #rows > Rows.MAX do rows[#rows] = nil end
    return rows, service
end

-- The service rows ServiceSearch.GuardedLeftOut leaves out (inside one of the other side's places,
-- not the player's own side's, nor the town the player stands in) moved after the rest, each part in
-- its order and marked row.guarded. Returns true when the switch is on ("Keep out of the other side's
-- towns"); nothing moves with it off.
function Rows.GuardedLast(rows)
    local Cost, Services, D = FGPS.Cost, FGPS.ServiceSearch, FGPS.Destinations
    if not (Cost and Cost.GuardedIndex and Services and Services.GuardedLeftOut and Services.GuardedIndexAt) then return false end
    local access = accessSnapshot()
    if not Cost.GuardedIndex(access) then return false end
    local index = Services.GuardedIndexAt(access, D and D.PlayerPos and D.PlayerPos() or nil)
    local front, back = {}, {}
    for _, row in ipairs(rows) do
        local d = row.dest
        local own = type(d) == "table" and (not d.learned or d.questie) and d.faction or nil
        if row.kind == "service" and type(d) == "table" and Services.GuardedLeftOut(index, d.inst, d.x, d.y, own) then
            row.guarded = true
            back[#back + 1] = row
        else
            front[#front + 1] = row
        end
    end
    for i = 1, #front do rows[i] = front[i] end
    for i = 1, #back do rows[#front + i] = back[i] end
    return true
end

-- For a typed service word with "Keep out of the other side's towns" on and an outside service
-- within Nearest's reach (ServiceSearch.AnyOutsideGuarded), moves the Destinations.Search results
-- of that service that ServiceSearch.GuardedLeftOut leaves out (leaving the town the player stands
-- in unmoved) to the end of their own section, each part in its order. Returns true when the order
-- applies; nothing moves otherwise.
function Rows.GuardedResultsLast(results, text)
    if type(results) ~= "table" then return false end
    local service, base = Rows.Service(text)
    local types = base and SERVICE_TYPES[base] or nil
    if not types then return false end
    local Cost, Services, D = FGPS.Cost, FGPS.ServiceSearch, FGPS.Destinations
    if not (Cost and Cost.GuardedIndex and Services and Services.AnyOutsideGuarded
            and Services.GuardedLeftOut and Services.GuardedIndexAt) then
        return false
    end
    local access = accessSnapshot()
    if not Cost.GuardedIndex(access) then return false end
    if not Services.AnyOutsideGuarded(service, access) then return false end
    local index = Services.GuardedIndexAt(access, D and D.PlayerPos and D.PlayerPos() or nil)
    if not index then return false end
    local n = #results
    local start = 1
    while start <= n do
        local d0 = type(results[start]) == "table" and (results[start].dest or results[start]) or nil
        local sec = (type(d0) == "table" and PLACE_SECTIONS[d0.type]) or 0
        local stop = start
        while stop < n do
            local dn = type(results[stop + 1]) == "table" and (results[stop + 1].dest or results[stop + 1]) or nil
            local nextSec = (type(dn) == "table" and PLACE_SECTIONS[dn.type]) or 0
            if nextSec ~= sec then break end
            stop = stop + 1
        end
        if sec == 0 and stop > start then
            local front, back = {}, {}
            for i = start, stop do
                local entry = results[i]
                local d = type(entry) == "table" and (entry.dest or entry) or nil
                local own = type(d) == "table" and (not d.learned or d.questie) and d.faction or nil
                if type(d) == "table" and types[d.type] and Services.GuardedLeftOut(index, d.inst, d.x, d.y, own) then
                    back[#back + 1] = entry
                else
                    front[#front + 1] = entry
                end
            end
            for i = 1, #front do results[start + i - 1] = front[i] end
            for i = 1, #back do results[start + #front + i - 1] = back[i] end
        end
        start = stop + 1
    end
    return true
end

-- True when the two best rows are equally good: the same match and the same group, and no
-- service word was typed (the nearest is the answer to one). A typed "/go" then starts nothing
-- and shows the list.
function Rows.Tied(rows, service)
    local first, second = type(rows) == "table" and rows[1] or nil, type(rows) == "table" and rows[2] or nil
    if service or not (first and second) then return false end
    return first.score == second.score and first.group == second.group
end

-- Starts guidance to a row's place or service through Go.Start. It shows the way and does
-- nothing else.
function Rows.Start(row)
    if type(row) ~= "table" then return false end
    local Go = FGPS.UI.Go
    if type(row.dest) ~= "table" or not (Go and Go.Start) then return false end
    return Go.Start(row.dest) == true
end

-- Rows.Nearest(serviceType, base, callback, limit) -> bool
-- Asks the engine for the nearest of a service along the route (up to limit, Rows.MAX without one;
-- it works out a route to each of the closest few, over several frames) and hands the callback their rows in
-- that order, or nil when the search ended without a list (no position, none near, cancelled), and
-- then the engine's reason ("no_position", "none", "cancelled"...), nil with a list. A row the
-- router could not reach has straight = true: its yards are the direct estimate. A cancelled search
-- also hands, third, the rows it knew when it was stopped (those not routed yet by the direct
-- estimate), for a caller that would rather show those than nothing. false, and no callback,
-- without the engine's search or without a callback.
function Rows.Nearest(service, base, callback, limit)
    local Services = FGPS.ServiceSearch
    if type(callback) ~= "function" or not (Services and Services.Nearest) then return false end
    limit = type(limit) == "number" and limit >= 1 and limit or Rows.MAX
    local function toRows(list)
        local rows = {}
        for _, entry in ipairs(list) do
            local dest = entry.dest
            if type(dest) == "table" and type(dest.name) == "string" then
                rows[#rows + 1] = { kind = "service", icon = TYPE_ICON[base] or TYPE_ICON[dest.type] or "place", name = dest.name,
                                    zone = dest.zoneName, yards = entry.yards or entry.straightYards, score = 100, group = 0,
                                    lead = true, dest = dest, straight = entry.straight == true }
            end
        end
        return rows
    end
    return Services.Nearest(service, { limit = limit }, function(list, err)
        if err ~= nil or type(list) ~= "table" or #list == 0 then
            local known = err == "cancelled" and type(list) == "table" and #list > 0 and toRows(list) or nil
            callback(nil, err, known)
            return
        end
        callback(toRows(list))
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
        add("type", "search", L["Open the world map and type a place or a word like inn or repair"])
    else
        add("type", "search", L["Type a place or a word like inn or repair"])
    end
    -- The Shift-click exists where the map took Cabbie's click handler (UI/WorldMap.lua).
    local WorldMap = FGPS.UI.WorldMap
    if WorldMap and WorldMap.clickHandler and FGPS.UI.Go then
        add("map", "map", L["Shift-click the world map to be guided to that spot"])
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
    return rows, L["How to Use Cabbie"]
end
