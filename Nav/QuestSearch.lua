
















local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local floor, sqrt, type, ipairs, tostring, format = math.floor, math.sqrt, type, ipairs, tostring, string.format

local QuestSearch = {
    SOURCES = 30,
    FAR = 1e9,
}
FGPS.QuestSearch = QuestSearch




QuestSearch.stats = { nothing = {} }

local function services() return FGPS.ServiceSearch end

local function read(entity, id, key)
    return services().QuestieRead(entity, id, key)
end




local spotCache = { maps = nil, lib = nil, byKey = {} }

local function spotsOf(entity, kind, id)
    local maps, lib = FGPS.Data and FGPS.Data.maps, rawget(_G, "LibQuestieDB")
    if spotCache.maps ~= maps or spotCache.lib ~= lib then spotCache.maps, spotCache.lib, spotCache.byKey = maps, lib, {} end
    local key = kind .. ":" .. tostring(id)
    local spots = spotCache.byKey[key]
    if not spots then
        spots = services().QuestieSpots(read(entity, id, "spawns"))
        spotCache.byKey[key] = spots
    end
    return spots
end

local function playerPos()
    local Coords = FGPS.Coords
    return Coords and Coords.PlayerPos and Coords.PlayerPos() or nil
end

local function distanceTo(pos, inst, x, y)
    if not pos or pos.inst ~= inst then return QuestSearch.FAR end
    local dx, dy = pos.x - x, pos.y - y
    return sqrt(dx * dx + dy * dy)
end



local function nearestOf(sources, pos)
    local best, bestD
    for _, source in ipairs(sources) do
        for _, group in ipairs(services().QuestieGroups(source.spots)) do
            local spot = group.middle
            local d = distanceTo(pos, group.inst, spot.x, spot.y)
            if not bestD or d < bestD then
                best, bestD = { inst = group.inst, x = spot.x, y = spot.y, map = spot.map, name = source.name, distance = d }, d
            end
        end
    end
    return best
end

local function listOf(v)
    return type(v) == "table" and v or {}
end


local function sourcesOf(lib, npcs, objects, out)
    out = out or {}
    for _, pair in ipairs({ { lib.Npc, "npc", npcs }, { lib.Object, "object", objects } }) do
        local entity, kind = pair[1], pair[2]
        if type(entity) == "table" and type(entity.Get) == "function" then
            for _, id in ipairs(listOf(pair[3])) do
                if #out >= QuestSearch.SOURCES then return out end
                if type(id) == "number" then
                    local name = read(entity, id, "name")
                    out[#out + 1] = { spots = spotsOf(entity, kind, id), name = type(name) == "string" and name or nil }
                end
            end
        end
    end
    return out
end


local function itemSources(lib, itemID)
    local Item = lib.Item
    if type(Item) ~= "table" or type(Item.Get) ~= "function" then return {} end
    return sourcesOf(lib, read(Item, itemID, "npcDrops"), read(Item, itemID, "objectDrops"))
end

local function itemName(lib, itemID)
    local Item = lib.Item
    local name = type(Item) == "table" and type(Item.Get) == "function" and read(Item, itemID, "name") or nil
    return type(name) == "string" and name or nil
end



local function lineText(text)
    if type(text) ~= "string" then return nil end
    text = Util.Trim(text)
    text = text:gsub("^%d+%s*/%s*%d+%s+", ""):gsub("%s*:%s*%d+%s*/%s*%d+%s*$", "")
    if text == "" then return nil end
    return text
end


local function logLines(questID)
    local C = C_QuestLog
    if not (C and C.GetQuestObjectives) then return {} end
    local ok, list = pcall(C.GetQuestObjectives, questID)
    local out = {}
    for _, o in ipairs(ok and type(list) == "table" and list or {}) do
        if type(o) == "table" then out[#out + 1] = { text = o.text, finished = o.finished == true } end
    end
    return out
end




local function inLog(questID)
    local C = C_QuestLog
    if not C then return false end
    if C.IsOnQuest then
        local ok, on = pcall(C.IsOnQuest, questID)
        if ok and on == true then return true end
    end
    if not C.GetLogIndexForQuestID then return false end
    local ok, index = pcall(C.GetLogIndexForQuestID, questID)
    return ok and type(index) == "number" and index > 0
end

local function logComplete(questID)
    local C = C_QuestLog
    if not (C and C.IsComplete) then return false end
    local ok, complete = pcall(C.IsComplete, questID)
    return ok and complete == true
end

local function logTitle(questID)
    local C = C_QuestLog
    if not (C and C.GetTitleForQuestID) then return nil end
    local ok, title = pcall(C.GetTitleForQuestID, questID)
    return ok and type(title) == "string" and title ~= "" and title or nil
end





local function objectivesOf(lib, questID)
    local Q, out = lib.Quest, {}
    local objectives = read(Q, questID, "objectives")
    if type(objectives) == "table" then
        for _, o in ipairs(listOf(objectives[1])) do
            if type(o) == "table" and type(o[1]) == "number" then
                local sources = sourcesOf(lib, { o[1] }, nil)
                out[#out + 1] = { name = type(o[2]) == "string" and o[2] or (sources[1] and sources[1].name), sources = sources }
            end
        end
        for _, o in ipairs(listOf(objectives[2])) do
            if type(o) == "table" and type(o[1]) == "number" then
                local sources = sourcesOf(lib, nil, { o[1] })
                out[#out + 1] = { name = type(o[2]) == "string" and o[2] or (sources[1] and sources[1].name), sources = sources }
            end
        end
        for _, o in ipairs(listOf(objectives[3])) do
            if type(o) == "table" and type(o[1]) == "number" then
                out[#out + 1] = { name = type(o[2]) == "string" and o[2] or itemName(lib, o[1]), sources = itemSources(lib, o[1]) }
            end
        end
        for _, o in ipairs(listOf(objectives[5])) do
            if type(o) == "table" and type(o[1]) == "table" then
                local sources = sourcesOf(lib, o[1], nil)
                local Npc = lib.Npc
                local credit = type(o[2]) == "number" and type(Npc) == "table" and type(Npc.Get) == "function"
                    and read(Npc, o[2], "name") or nil
                local name = type(o[3]) == "string" and o[3] or (type(credit) == "string" and credit) or (sources[1] and sources[1].name)
                out[#out + 1] = { name = name, sources = sources }
            end
        end
    end
    local trigger = read(Q, questID, "triggerEnd")
    if type(trigger) == "table" and type(trigger[1]) == "string" then
        out[#out + 1] = { name = trigger[1], sources = { { spots = services().QuestieSpots(trigger[2]), name = trigger[1] } } }
    end
    for i, o in ipairs(out) do o.index = i end
    return out
end





local function matchLines(objectives, lines, complete)
    local used, order = {}, {}
    for i, o in ipairs(objectives) do order[i] = o end
    table.sort(order, function(a, b)
        local la, lb = type(a.name) == "string" and #a.name or 0, type(b.name) == "string" and #b.name or 0
        if la ~= lb then return la > lb end
        return a.index < b.index
    end)
    for _, o in ipairs(order) do
        local key = type(o.name) == "string" and Util.Lower(o.name) or nil
        o.done = complete
        for i, line in ipairs(lines) do
            if key and not used[i] and type(line.text) == "string" and Util.Lower(line.text):find(key, 1, true) then
                used[i] = true
                o.done = line.finished
                o.text = lineText(line.text)
                break
            end
        end
        o.text = o.text or o.name
    end
end








function QuestSearch.Places(questID, opts)
    local lib, why = services().QuestieLib()
    if not lib then return nil, why end
    if type(lib.Quest) ~= "table" or type(lib.Quest.Get) ~= "function" then return nil, "api" end
    opts = opts or {}
    local pos, out = playerPos(), {}
    local Q = lib.Quest
    if opts.pickup then
        local starters = listOf(read(Q, questID, "startedBy"))
        local place = nearestOf(sourcesOf(lib, starters[1], starters[2]), pos)
        if place then
            place.role, place.text = "pickup", format(L["Pick up from %s"], place.name or L["the quest giver"])
        else
            local item
            for _, itemID in ipairs(listOf(starters[3])) do
                if type(itemID) == "number" then
                    place = nearestOf(itemSources(lib, itemID), pos)
                    if place then item = itemID break end
                end
            end
            if place then place.role, place.text = "pickup", format(L["Find %s"], itemName(lib, item) or L["the item that starts it"]) end
        end
        if place then out[#out + 1] = place end
    end
    if inLog(questID) then
        local objectives = objectivesOf(lib, questID)
        matchLines(objectives, logLines(questID), logComplete(questID))
        for _, o in ipairs(objectives) do
            local place = nearestOf(o.sources, pos)
            if place then
                place.role, place.text, place.done = "objective", o.text or place.name, o.done == true
                out[#out + 1] = place
            end
        end
        local finishers = listOf(read(Q, questID, "finishedBy"))
        local place = nearestOf(sourcesOf(lib, finishers[1], finishers[2]), pos)
        if place then
            place.role, place.text = "turnin", format(L["Turn in to %s"], place.name or L["the quest giver"])
            out[#out + 1] = place
        end
    end
    return out
end



function QuestSearch.GamePlace(questID)
    local C, Coords = C_QuestLog, FGPS.Coords
    if not (C and Coords and Coords.MapToWorld) then return nil end
    local map, mx, my
    if C.GetNextWaypoint then
        local ok, m, x, y = pcall(C.GetNextWaypoint, questID)
        if ok and type(m) == "number" and type(x) == "number" and type(y) == "number" then map, mx, my = m, x, y end
    end
    if not map and GetQuestUiMapID and C.GetQuestsOnMap then
        local ok, m = pcall(GetQuestUiMapID, questID)
        if ok and type(m) == "number" and m > 0 then
            local okList, list = pcall(C.GetQuestsOnMap, m)
            for _, q in ipairs(okList and type(list) == "table" and list or {}) do
                if type(q) == "table" and q.questID == questID and type(q.x) == "number" and type(q.y) == "number" then
                    map, mx, my = m, q.x, q.y
                    break
                end
            end
        end
    end
    if not map then return nil end
    local inst, x, y = Coords.MapToWorld(map, mx, my)
    if not inst then return nil end
    return { role = "map", text = L["the spot your map marks"], inst = inst, x = x, y = y, map = map,
             distance = distanceTo(playerPos(), inst, x, y) }
end


function QuestSearch.QuestName(questID)
    local title = logTitle(questID)
    if title then return title end
    local lib = services().QuestieLib()
    local name = lib and type(lib.Quest) == "table" and type(lib.Quest.Get) == "function" and read(lib.Quest, questID, "name") or nil
    return type(name) == "string" and name or nil
end





function QuestSearch.Dest(questID, place, questName)
    if type(place) ~= "table" or not place.inst then return nil end
    questName = questName or QuestSearch.QuestName(questID)
    local text = place.text or ""
    local dest = { kind = "custom", type = "questplace", name = questName and format(L["%s: %s"], questName, text) or text,
                   inst = place.inst, x = floor(place.x * 10 + 0.5) / 10, y = floor(place.y * 10 + 0.5) / 10, map = place.map,
                   questID = questID, questRole = place.role }
    local Coords = FGPS.Coords
    if dest.map and Coords and Coords.WorldToMap then
        local map, mx, my = Coords.WorldToMap(dest.inst, dest.x, dest.y, dest.map)
        if map then dest.map, dest.mx, dest.my = map, mx, my end
    end
    if Coords and Coords.ZoneAt then
        local _, zoneName = Coords.ZoneAt(dest.inst, dest.x, dest.y)
        dest.zoneName = zoneName
    end
    local Destinations = FGPS.Destinations
    if not dest.zoneName and dest.map and Destinations and Destinations.MapName then dest.zoneName = Destinations.MapName(dest.map) end
    return dest
end

local function nearest(places, keep)
    local best
    for _, p in ipairs(places) do
        if keep(p) and (not best or p.distance < best.distance) then best = p end
    end
    return best
end






function QuestSearch.Next(questID)
    local stats = QuestSearch.stats
    local function nothing(why)
        stats.nothing[why] = (stats.nothing[why] or 0) + 1
        return nil, why
    end
    if type(questID) ~= "number" or not inLog(questID) then return nothing("not_in_log") end
    local places = QuestSearch.Places(questID)
    local place
    if places then
        place = nearest(places, function(p) return p.role == "objective" and not p.done end)


        if not place and (logComplete(questID) or not QuestSearch.HasOpenLines(questID)) then
            place = nearest(places, function(p) return p.role == "turnin" end)
        end
    end
    place = place or QuestSearch.GamePlace(questID)
    if not place then return nothing("no_place") end
    return QuestSearch.Dest(questID, place)
end


function QuestSearch.HasOpenLines(questID)
    for _, line in ipairs(logLines(questID)) do
        if not line.finished then return true end
    end
    return false
end










QuestSearch.MIN_LETTERS = 3
QuestSearch.MAX_QUESTS = 5
QuestSearch.MAX_ROWS = 10
QuestSearch.CANDIDATES = 200
QuestSearch.OFFER_POOL = 10
QuestSearch.NAMES_PER_YIELD = 50
QuestSearch.NAMES_SLICE_MS = 2


QuestSearch.names = { state = nil, lib = nil, keys = nil, ids = nil, task = nil, ms = nil, slices = nil }


local function fold(text)
    return (Util.Trim(Util.Lower(text):gsub("'", "")):gsub("%s+", " "))
end

local function scoreName(key, q)
    local Destinations = FGPS.Destinations
    return Destinations and Destinations.ScoreName and Destinations.ScoreName(key, q) or 0
end



function QuestSearch.ReadNames(lib)
    local names, Scheduler = QuestSearch.names, FGPS.Scheduler
    if names.lib ~= lib then
        if names.task and Scheduler and Scheduler.Cancel then Scheduler:Cancel(names.task) end
        names.state, names.lib, names.keys, names.ids, names.task = nil, lib, nil, nil, nil
    end
    if names.state ~= nil or not (Scheduler and Scheduler.Run) then return false end
    local Q = lib.Quest
    if type(Q) ~= "table" or type(Q.GetAllIds) ~= "function" or type(Q.Get) ~= "function" then
        names.state = "failed"
        return false
    end
    names.state = "running"
    local keys, ids = {}, {}
    names.task = Scheduler:Run(function()
        local ok, all = pcall(Q.GetAllIds)
        if not ok or type(all) ~= "table" then return "failed" end
        local Yield = Scheduler.Yield
        for i = 1, #all do
            local id = all[i]
            local name = type(id) == "number" and read(Q, id, "name") or nil
            if type(name) == "string" and name ~= "" then
                keys[#keys + 1], ids[#ids + 1] = fold(name), id
            end
            if i % QuestSearch.NAMES_PER_YIELD == 0 and not Yield() then return "cancelled" end
        end
        return "ready"
    end, {
        label = "questnames", budgetMs = QuestSearch.NAMES_SLICE_MS,
        onDone = function(ok, answer)
            local task = names.task
            if names.lib ~= lib then return end
            names.task = nil
            names.ms, names.slices = task and task.elapsedMs, task and task.slices
            if ok and answer == "ready" then
                names.state, names.keys, names.ids = "ready", keys, ids
                FGPS.Events:Fire("QUEST_NAMES_READY")
            else
                names.state = "failed"
            end
        end,
    })
    return true
end



local function hasBit(value, mask)
    return floor(value / mask) % 2 == 1
end

local function flaggedDone(questID)
    local C = C_QuestLog
    if not (C and C.IsQuestFlaggedCompleted) then return false end
    local ok, done = pcall(C.IsQuestFlaggedCompleted, questID)
    return ok and done == true
end



local function playerFacts(lib)
    local enum = type(lib.Enum) == "table" and lib.Enum or {}
    local facts = { level = UnitLevel and UnitLevel("player") or nil }
    local raceID = UnitRace and select(3, UnitRace("player")) or nil
    local races = type(enum.raceMaskById) == "table" and enum.raceMaskById or {}
    if type(raceID) == "number" and type(races[raceID]) == "number" and races[raceID] > 0 then facts.race = races[raceID] end
    local classFile = UnitClass and select(2, UnitClass("player")) or nil
    local classes = type(enum.classKeys) == "table" and enum.classKeys or {}
    local classMask = type(classFile) == "string" and (classes[classFile] or classes[(classFile:gsub("KNIGHT$", "_KNIGHT"):gsub("HUNTER$", "_HUNTER"))]) or nil
    if type(classMask) == "number" and classMask > 0 then facts.class = classMask end
    local faction = UnitFactionGroup and UnitFactionGroup("player") or nil
    facts.side = faction == "Alliance" and "A" or faction == "Horde" and "H" or nil
    return facts
end




local function groupQuestDone(Q, id)
    if type(id) ~= "number" then return false end
    if id < 0 then return flaggedDone(-id) end
    if flaggedDone(id) then return true end
    for _, other in ipairs(listOf(read(Q, id, "exclusiveTo"))) do
        if flaggedDone(other) then return true end
    end
    return false
end








local function canTake(lib, questID, facts)
    local Q = lib.Quest
    if flaggedDone(questID) or inLog(questID) then return false end
    local races = read(Q, questID, "requiredRaces")
    if facts.race and type(races) == "number" and races > 0 and not hasBit(races, facts.race) then return false end
    local classes = read(Q, questID, "requiredClasses")
    if facts.class and type(classes) == "number" and classes > 0 and not hasBit(classes, facts.class) then return false end
    local level = facts.level
    if type(level) == "number" then
        local minLevel, maxLevel = read(Q, questID, "requiredLevel"), read(Q, questID, "requiredMaxLevel")
        if type(minLevel) == "number" and minLevel > level then return false end
        if type(maxLevel) == "number" and maxLevel > 0 and maxLevel < level then return false end
    end
    for _, id in ipairs(listOf(read(Q, questID, "preQuestGroup"))) do
        if not groupQuestDone(Q, id) then return false end
    end
    for _, id in ipairs(listOf(read(Q, questID, "exclusiveTo"))) do
        if flaggedDone(id) or inLog(id) then return false end
    end
    local single = listOf(read(Q, questID, "preQuestSingle"))
    if #single > 0 then
        local any = false
        for _, id in ipairs(single) do
            if flaggedDone(id) then any = true break end
        end
        if not any then return false end
    end
    local npcs = listOf(listOf(read(Q, questID, "startedBy"))[1])
    if facts.side and #npcs > 0 and type(lib.Npc) == "table" and type(lib.Npc.Get) == "function" then
        for _, id in ipairs(npcs) do
            local side = read(lib.Npc, id, "friendlyToFaction")
            if side == nil or side == "AH" or side == facts.side then return true end
        end
        return false
    end
    return true
end
QuestSearch.CanTake = canTake


local function logMatches(q)
    local C, out = C_QuestLog, {}
    if not (C and C.GetNumQuestLogEntries and C.GetInfo) then return out end
    local okN, n = pcall(C.GetNumQuestLogEntries)
    if not okN or type(n) ~= "number" then return out end
    for i = 1, n do
        local ok, info = pcall(C.GetInfo, i)
        if ok and type(info) == "table" and not info.isHeader and type(info.questID) == "number" and info.questID > 0
            and type(info.title) == "string" then
            local score = scoreName(fold(info.title), q)
            if score > 0 then out[#out + 1] = { id = info.questID, title = info.title, score = score } end
        end
    end
    table.sort(out, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.title < b.title
    end)
    return out
end





local function questRows(lib, quest, out)
    local Destinations = FGPS.Destinations
    local places
    if quest.inLog then
        local all = lib and QuestSearch.Places(quest.id) or nil
        local complete = logComplete(quest.id)
        local open, turnin = {}, nil
        for _, p in ipairs(all or {}) do
            if p.role == "objective" and not p.done and not complete then open[#open + 1] = p end
            if p.role == "turnin" then turnin = p end
        end
        table.sort(open, function(a, b) return a.distance < b.distance end)
        local placedOpen = #open
        places = open
        if turnin then places[#places + 1] = turnin end
        if placedOpen == 0 and not (turnin and (complete or not QuestSearch.HasOpenLines(quest.id))) then
            local mark = QuestSearch.GamePlace(quest.id)
            if mark then table.insert(places, 1, mark) end
        end
    else
        places = { quest.pickup }
    end
    for _, place in ipairs(places) do
        if #out >= QuestSearch.MAX_ROWS then return end
        local dest = QuestSearch.Dest(quest.id, place, quest.title)
        if dest then
            out[#out + 1] = { dest = dest, score = quest.score, quest = true,
                              label = Destinations.Label(dest.name, dest.zoneName, dest.type),
                              distance = place.distance < QuestSearch.FAR and place.distance or nil }
        end
    end
end









function QuestSearch.Search(text)
    local q = type(text) == "string" and fold(text) or ""
    if #q < QuestSearch.MIN_LETTERS then return {} end
    local stats = QuestSearch.stats
    stats.searches = (stats.searches or 0) + 1
    local lib = services().QuestieLib()
    local quests, inLogSet = {}, {}

    local matched, takeable = false, false
    for _, quest in ipairs(logMatches(q)) do
        inLogSet[quest.id] = true
        if #quests < QuestSearch.MAX_QUESTS then
            quest.inLog = true
            quests[#quests + 1] = quest
        end
    end
    if lib then
        local names = QuestSearch.names
        if names.lib ~= lib or names.state == nil then QuestSearch.ReadNames(lib) end
        if names.state == "ready" and #quests < QuestSearch.MAX_QUESTS then


            local keys, ids, hits, scores = names.keys, names.ids, {}, {}
            for i = 1, #keys do
                if not inLogSet[ids[i]] then
                    local score = scoreName(keys[i], q)
                    if score > 0 then
                        hits[#hits + 1] = i
                        scores[i] = score
                    end
                end
            end
            table.sort(hits, function(a, b)
                if scores[a] ~= scores[b] then return scores[a] > scores[b] end
                if keys[a] ~= keys[b] then return keys[a] < keys[b] end
                return ids[a] < ids[b]
            end)


            local facts, pool = playerFacts(lib), {}
            for n = 1, math.min(#hits, QuestSearch.CANDIDATES) do
                if #pool >= QuestSearch.OFFER_POOL then break end
                local i = hits[n]
                local id = ids[i]
                matched = true

                if inLog(id) then
                    if #quests < QuestSearch.MAX_QUESTS then
                        inLogSet[id] = true
                        quests[#quests + 1] = { id = id, score = scores[i], inLog = true, title = QuestSearch.QuestName(id) }
                    end
                elseif canTake(lib, id, facts) then
                    takeable = true
                    local pickup
                    for _, p in ipairs(QuestSearch.Places(id, { pickup = true }) or {}) do
                        if p.role == "pickup" then pickup = p end
                    end
                    if pickup then pool[#pool + 1] = { id = id, score = scores[i], pickup = pickup, key = keys[i] } end
                end
            end
            table.sort(pool, function(a, b)
                if a.score ~= b.score then return a.score > b.score end
                if a.pickup.distance ~= b.pickup.distance then return a.pickup.distance < b.pickup.distance end
                if a.key ~= b.key then return a.key < b.key end
                return a.id < b.id
            end)
            for _, quest in ipairs(pool) do
                if #quests >= QuestSearch.MAX_QUESTS then break end
                quest.title = QuestSearch.QuestName(quest.id)
                quests[#quests + 1] = quest
            end
        end
    end
    local rows = {}
    for _, quest in ipairs(quests) do questRows(lib, quest, rows) end
    if #rows > 0 then
        stats.withRows = (stats.withRows or 0) + 1
    else
        local why
        if #quests > 0 or takeable then why = "no_place"
        elseif not lib then why = "no_questie"
        elseif QuestSearch.names.state ~= "ready" then why = "names_" .. tostring(QuestSearch.names.state or "running")
        elseif matched then why = "cannot_take"
        else why = "no_match" end
        if type(stats.searchNothing) ~= "table" then stats.searchNothing = {} end
        stats.searchNothing[why] = (stats.searchNothing[why] or 0) + 1
    end
    return rows
end




function QuestSearch.Note(text)
    local q = type(text) == "string" and fold(text) or ""
    if QuestSearch.noted or #q < QuestSearch.MIN_LETTERS then return false end
    local _, why = services().QuestieLib()
    if why ~= "absent" then return false end
    QuestSearch.noted = true
    FGPS:Print(L["To find quests by name, Cabbie needs the Questie add-on."])
    return true
end
