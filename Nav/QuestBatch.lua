




local ADDON_NAME, FGPS = ...

local QuestBatch = {}
FGPS.QuestBatch = QuestBatch

local L = FGPS.L


QuestBatch.MAX_STOPS = 6

QuestBatch.LEVEL_YARDS = 40
QuestBatch.DEFAULT_RADIUS = 600

QuestBatch.TOO_HIGH = 5

local generation = 0
local inflight
local current

local function modules()
    return FGPS.QuestData, FGPS.Navigator, FGPS.Router, FGPS.Events
end

function QuestBatch.Radius()
    local db = FGPS.DB
    local n = db and db.Get and tonumber(db:Get("quests.batchRadius"))
    if not n or n <= 0 then return QuestBatch.DEFAULT_RADIUS end
    return n
end


function QuestBatch.LevelPenalty(questLevel, playerLevel)
    questLevel = tonumber(questLevel)
    playerLevel = tonumber(playerLevel)
    if not questLevel or not playerLevel or playerLevel <= 0 then return 0 end
    local low, high = playerLevel - 4, playerLevel + 2
    if questLevel < low then return low - questLevel end
    if questLevel > high then return questLevel - high end
    return 0
end

function QuestBatch:Init()
end

function QuestBatch.Current()
    return current
end

local function playerLevel()
    if not UnitLevel then return 0 end
    local ok, level = pcall(UnitLevel, "player")
    if ok and tonumber(level) then return tonumber(level) end
    return 0
end


local function say(text)
    local guide = FGPS.UI and FGPS.UI.Guide
    if guide and guide.Say then guide.Say(L[text], 6) end
end

local function publish(stops, status, seconds, radius, origin, line)
    local _, _, _, Events = modules()
    local lines = {}
    if line then
        lines[1] = L[line]
    elseif status == "none" then
        lines[1] = format(L["No quests to take within %d yards."], math.floor((radius or 0) + 0.5))
    elseif status ~= "dismissed" then
        for i = 1, #stops do
            local stop = stops[i]
            local level = tonumber(stop.level)
            local name = (level and level > 0) and format(L["[%d] %s"], level, stop.title) or stop.title
            if stop.unconfirmed then name = name .. L[" (unconfirmed)"] end
            if stop.notInOrder then name = name .. L[" (not in your order)"] end
            lines[#lines + 1] = format("%d. %s", i, name)
        end
        if status == "pending" then
            lines[#lines + 1] = L["Working out the route."]
        elseif status == "no_path" then
            lines[#lines + 1] = L["No route to these stops."]
        elseif status == "cancelled" then
            lines[#lines + 1] = L["The route was cancelled."]
        elseif status == "ok" then
            local shown = FGPS.Util and FGPS.Util.FormatTime and FGPS.Util.FormatTime(seconds or 0) or ""
            lines[#lines + 1] = format(L["The route takes %s."], shown)
        end
    end
    current = {
        stops = stops,
        status = status,
        totalSeconds = seconds,
        lines = lines,
        radius = radius,
        origin = origin,
    }
    if Events and Events.Fire then Events:Fire("QUEST_BATCH", current) end
    return current
end

local function samePlace(a, b)
    if type(a) ~= "table" or type(b) ~= "table" or not a.x or not b.x then return false end
    if a.inst and b.inst and a.inst ~= b.inst then return false end
    local dx, dy = a.x - b.x, a.y - b.y
    return dx * dx + dy * dy < 1
end




local function titleFor(QuestData, questID)
    local title = QuestData.Title and QuestData.Title(questID)
    if type(title) == "string" and title ~= "" then return title, true end
    return format(L and L["Quest %d"] or "Quest %d", questID), false
end













local SRC_ITEM_DROP = 3
local function takeable(QuestData, questID)
    local verdict, _, code = QuestData.CanTake(questID)
    if verdict == "yes" then return true, false end
    if verdict == "unknown" and code == "forever_incomplete" then return true, true end
    return false, false
end

local function bonusFor(questID)
    local Leveling = FGPS.Leveling
    if not (Leveling and Leveling.Bonus) then return 0 end
    local ok, yards = pcall(Leveling.Bonus, questID)
    return ok and tonumber(yards) or 0
end

function QuestBatch.Collect(origin)
    local QuestData = modules()
    if not QuestData or not origin or not origin.map or not origin.inst or not origin.x then
        return {}
    end
    local radius = QuestBatch.Radius()
    local level = playerLevel()
    local givers = QuestData.GiversOnMap(origin.map) or {}
    local best = {}
    for i = 1, #givers do
        local entry = givers[i]
        local questID = entry and tonumber(entry.id)
        local position = entry and entry.position
        if questID and type(position) == "table" and position.x and position.y and position.src ~= SRC_ITEM_DROP then
            local info = QuestData.Lookup and QuestData.Lookup(questID) or QuestData.Info(questID)
            local start = info and info.start
            local tooHigh = level > 0 and tonumber(info and info.level)
                and tonumber(info.level) >= level + QuestBatch.TOO_HIGH
            local ok, unconfirmed = false, false
            if start and not tooHigh then ok, unconfirmed = takeable(QuestData, questID) end
            if ok then
                local turnIn = info.turnIn
                local turnInOnly = turnIn and samePlace(position, turnIn) and not samePlace(position, start)
                if not turnInOnly then
                    local distance = QuestData.DistanceTo(origin, position.inst, position.x, position.y)
                    if distance and distance <= radius then
                        local penalty = QuestBatch.LevelPenalty(info.level, level)
                        local bonus = bonusFor(questID)
                        local score = distance + penalty * QuestBatch.LEVEL_YARDS - bonus
                        local prev = best[questID]
                        if not prev or score < prev.score then
                            local title, named = titleFor(QuestData, questID)
                            best[questID] = {
                                questID = questID,
                                title = named and title or (L and L["Unknown quest"] or "Unknown quest"),
                                unknownQuest = not named and questID or nil,
                                distance = distance,
                                level = info.level,
                                penalty = penalty,
                                score = score,
                                bonus = bonus > 0 and bonus or nil,
                                unconfirmed = unconfirmed or nil,
                                inst = position.inst,
                                x = position.x,
                                y = position.y,
                                map = position.map or origin.map,




                                dest = {
                                    kind = "quest",
                                    type = "quest",
                                    questID = questID,
                                    questTarget = "giver",
                                    name = QuestData.StartLabel(title, position),
                                    inst = position.inst,
                                    x = position.x,
                                    y = position.y,
                                    map = position.map or origin.map,
                                    source = "questbatch",
                                },
                            }
                        end
                    end
                end
            end
        end
    end
    local list = {}
    for _, stop in pairs(best) do
        list[#list + 1] = stop
    end
    table.sort(list, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        return a.questID < b.questID
    end)
    while #list > QuestBatch.MAX_STOPS do
        list[#list] = nil
    end
    return list
end

local function orderStops(origin, picks)
    local _, Navigator = modules()
    if not Navigator or not Navigator.OptimizeOrder then return picks end

    local order = Navigator.OptimizeOrder({ inst = origin.inst, x = origin.x, y = origin.y }, picks)
    if type(order) ~= "table" then return picks end
    local ordered = {}
    for i = 1, #order do
        ordered[i] = picks[order[i]]
    end
    return ordered
end





local function orderFirst(stops)
    local Leveling = FGPS.Leveling
    local on = Leveling and Leveling.Enabled and Leveling.Enabled()
    for i = 1, #stops do
        stops[i].notInOrder = nil
    end
    if not on then return stops end
    local inOrder, rest = {}, {}
    for i = 1, #stops do
        local stop = stops[i]
        if stop.bonus then
            inOrder[#inOrder + 1] = stop
        else
            stop.notInOrder = true
            rest[#rest + 1] = stop
        end
    end
    for i = 1, #rest do
        inOrder[#inOrder + 1] = rest[i]
    end
    return inOrder
end

local function cost(origin, stops, radius)
    local _, _, Router = modules()
    generation = generation + 1
    local gen = generation
    if inflight and Router and Router.Cancel then Router:Cancel(inflight) end
    inflight = nil
    publish(stops, "pending", nil, radius, origin)
    local routeStops = {}
    for i = 1, #stops do
        routeStops[i] = stops[i].dest
    end
    if not Router then return nil end
    local finished = false
    local handle = Router:RequestRoute({
        origin = { inst = origin.inst, x = origin.x, y = origin.y, map = origin.map },
        stops = routeStops,
        variant = "fastest",
    }, function(route, err)
        if gen ~= generation then return end
        finished = true
        inflight = nil
        if type(err) == "table" and err.code == "CANCELLED" then
            publish(stops, "cancelled", nil, radius, origin)
            return
        end
        if type(route) ~= "table" or route.totalSeconds == nil then
            publish(stops, "no_path", nil, radius, origin)
            return
        end
        publish(stops, "ok", route.totalSeconds, radius, origin)
    end)

    if gen == generation and not finished then inflight = handle end
    return inflight
end

function QuestBatch.Suggest()
    local QuestData, _, Router = modules()
    local origin = QuestData and QuestData.PlayerPos and QuestData.PlayerPos()
    local radius = QuestBatch.Radius()
    local picks = QuestBatch.Collect(origin)
    if #picks == 0 then
        generation = generation + 1
        if inflight and Router and Router.Cancel then Router:Cancel(inflight) end
        inflight = nil
        publish({}, "none", nil, radius, origin)
        return nil
    end
    return cost(origin, orderFirst(orderStops(origin, picks)), radius)
end

function QuestBatch.Cancel()
    local _, _, Router = modules()
    if inflight and Router and Router.Cancel then
        Router:Cancel(inflight)
    end
end


function QuestBatch.Accept()
    local _, Navigator = modules()
    local stops = current and current.stops
    if not stops or #stops == 0 or not Navigator or not Navigator.SetDestination then
        say("No stops to set.")
        return false
    end


    local following = Navigator.IsJourney and Navigator:IsJourney()
    local opts = { quiet = true, start = false, askedBy = "player" }
    Navigator:SetDestination(stops[1].dest, opts)
    for i = 2, #stops do
        Navigator:AddStop(stops[i].dest, opts)
    end
    say(following and "Stops set. Your route now goes to them." or "Stops set. Press Start for the route.")
    return true
end

function QuestBatch.DropLast()
    local stops = current and current.stops
    local origin = current and current.origin
    if not stops or #stops == 0 then
        say("No stop to drop.")
        return false
    end
    local kept = {}
    for i = 1, #stops - 1 do
        kept[i] = stops[i]
    end
    say("The last stop was dropped.")
    if #kept == 0 then
        local _, _, Router = modules()
        generation = generation + 1
        if inflight and Router and Router.Cancel then Router:Cancel(inflight) end
        inflight = nil
        publish({}, "none", nil, current and current.radius, origin, "No stops left.")
        return true
    end
    cost(origin, kept, current and current.radius)
    return true
end

function QuestBatch.Dismiss()
    local _, _, Router = modules()
    generation = generation + 1
    if inflight and Router and Router.Cancel then Router:Cancel(inflight) end
    inflight = nil
    publish({}, "dismissed", nil, current and current.radius, current and current.origin)
    say("The list was dismissed.")
    return true
end
