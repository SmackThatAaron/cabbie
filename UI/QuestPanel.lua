












































local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local type, ipairs, tostring, tonumber, format = type, ipairs, tostring, tonumber, string.format

local QuestPanel = {
    query = "",
    items = {},
    rows = {},
    focus = nil,
    searchGeneration = 0,
    pendingQuery = nil,
    questsPage = { rows = {}, selected = nil },
}
FGPS.UI.QuestPanel = QuestPanel

local DEBOUNCE_SECONDS = 0.15

QuestPanel.NO_PLACE_SECONDS = 4




local function Frames()
    return FGPS.UI.Frames
end

local function Look()
    return FGPS.UI.Look
end

local function settings()
    return FGPS.DB and FGPS.DB.settings or nil
end


local function makeButton(parent, text, onClick, width, height)
    local button = Look().Button(parent, text, width or 90, height or 22)
    if onClick then button:SetScript("OnClick", onClick) end
    return button
end

local function setButtonText(button, text)
    if button.SetLabel then button:SetLabel(text) else button:SetText(text) end
end

local function setButtonEnabled(button, enabled)
    if button.SetEnabledState then button:SetEnabledState(enabled) elseif enabled then button:Enable() else button:Disable() end
end




local function questData()
    local QuestData = FGPS.QuestData
    if QuestData and QuestData.Available and QuestData.Available() then return QuestData end
    return nil
end











function QuestPanel.MarkFlag(mark)
    return Look().Tint(FGPS.QuestData.MarkLabel(mark), "grey")
end




local function distanceFrom(pos, yards)


    if not pos then return "" end
    if type(yards) ~= "number" then return L["another continent"] end
    local s = settings()
    local text = Util.FormatDistance(yards, s and s.units or "yards")
    if text == "" then return "" end
    return format(L["%s away"], text)
end

local function distanceText(yards)
    local QuestData = FGPS.QuestData
    return distanceFrom(QuestData and QuestData.PlayerPos and QuestData.PlayerPos() or nil, yards)
end
QuestPanel.DistanceText = distanceText


local function withMark(right, mark)
    local flag = QuestPanel.MarkFlag(mark)
    if not right or right == "" then return flag end
    return right .. " \194\183 " .. flag
end




function QuestPanel.LevelText(level, minLevel)
    level, minLevel = tonumber(level), tonumber(minLevel)
    if not level or level <= 0 then
        if minLevel and minLevel > 0 then return format(L["requires level %d"], minLevel) end
        return nil
    end
    if minLevel and minLevel > 0 and minLevel ~= level then
        return format(L["level %d (requires %d)"], level, minLevel)
    end
    return format(L["level %d"], level)
end




local function titleFor(questID)
    local QuestData = FGPS.QuestData
    local title = QuestData and QuestData.Title and QuestData.Title(questID) or nil
    if type(title) == "string" and title ~= "" then return title, true end
    return L["Unknown quest"], false
end
QuestPanel.TitleFor = titleFor




local function lineTitle(questID)
    local title, known = titleFor(questID)
    if known then return title end
    return format(L["Quest %d"], questID)
end




local function shownTitle(questID, title, known)
    if known == false or type(title) ~= "string" or title == "" or title == format(L["Quest %d"], questID) then
        return titleFor(questID)
    end
    return title, true
end




local function withDetails(title, details)
    if not details or details == "" then return title end
    return title .. L[" - "] .. Look().Tint(details, "later")
end











local function goTo(questID, target, index)
    local Quests = FGPS.Quests
    local dest, reason
    if Quests and Quests.DestinationFor then
        local handle
        if target ~= "next" then handle = index and (target .. ":" .. index) or target end
        dest, reason = Quests.DestinationFor(questID, handle)
    end
    if not dest then
        local text = (Quests and Quests.ReasonText and Quests.ReasonText(reason)) or L["no map location is known for this quest"]
        local Guide = FGPS.UI.Guide
        if Guide and Guide.Say then Guide.Say(format(L["%s: %s"], lineTitle(questID), text), QuestPanel.NO_PLACE_SECONDS) end
        return false
    end

    local Search = FGPS.UI.Search
    if Search and Search.GoTo then
        Search.GoTo(dest, "start", { quiet = true })
    else
        local Navigator = FGPS.Navigator
        if not (Navigator and Navigator.SetDestination) then
            FGPS:Print(L["Navigation is not available right now."])
            return false
        end
        Navigator:SetDestination(dest, { start = true, quiet = true })
    end
    return true
end
QuestPanel.GoTo = goTo






local function isAccepted(questID)
    local Quests = FGPS.Quests
    if not (questID and Quests and Quests.Get) then return false end
    local ok, q = pcall(Quests.Get, questID)
    return ok and q ~= nil
end
QuestPanel.IsAccepted = isAccepted















local GO_TARGET = { accept = "giver", complete = "next", turnin = "turnin" }

local BATCH_ACTIONS = { pickup = "accept", objective = "complete", turnin = "turnin" }


QuestPanel.LEVELING_VERBS = { accept = "Accept", complete = "Objective", turnin = "Turn in" }
local LEVELING_VERBS = QuestPanel.LEVELING_VERBS



local function placeZone(at)
    if type(at) ~= "table" then return nil end
    if type(at.zoneName) == "string" and at.zoneName ~= "" then return at.zoneName end
    local Coords = FGPS.Coords
    if not Coords then return nil end
    if at.map and Coords.MapName then
        local name = Coords.MapName(at.map)
        if type(name) == "string" and name ~= "" then return name end
    end
    if at.inst and at.x and at.y and Coords.ZoneAt then
        local ok, _, name = pcall(Coords.ZoneAt, at.inst, at.x, at.y)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return nil
end

local function levelingItems()
    local Leveling = FGPS.Leveling
    if not (Leveling and Leveling.Next) then
        local why = L["Optimized Leveling is not available in this copy of Cabbie."]
        return {}, why, { ready = false, why = why }
    end
    if not Leveling.Enabled() then
        local why = L["Optimized Leveling is turned off. Turn it on under Quest help in the settings."]
        return {}, why, { ready = false, why = why }
    end
    local status = Leveling.Status()
    local ctx = status.context
    if not ctx then
        local why = L["Your character is not known yet."]
        return {}, why, { ready = false, why = why }
    end
    local QuestData = questData()
    local pos = QuestData and QuestData.PlayerPos and QuestData.PlayerPos() or nil
    local items = {}
    local function add(entry, action, section)
        local questID = entry.questID
        local title, named = shownTitle(questID, Leveling.Title(questID))
        local head = entry.level and format(L["[%d] %s"], entry.level, title) or title
        local parts = {}
        if entry.objective then parts[#parts + 1] = format(L["objective %d"], entry.objective) end
        if entry.untested then parts[#parts + 1] = L["not tested in the beta"] end


        local target = GO_TARGET[action] or "giver"
        local accepted = isAccepted(questID)
        if target == "next" and not accepted then target = "giver" end
        if target == "giver" and accepted then target = "next" end
        local at, zone
        if target == "next" then
            local okStep, step = pcall(FGPS.Quests.NextStep, questID)
            at = okStep and step or nil
            zone = placeZone(at)
        elseif QuestData then



            local place = (target == "turnin" and QuestData.TurnIn or QuestData.Start)(questID)
            zone = placeZone(place)
            if place and QuestData.ReachedAt then place = QuestData.ReachedAt(place) end
            at = place
            zone = zone or placeZone(at)
        end
        local known = QuestData and QuestData.Lookup and QuestData.Lookup(questID) ~= nil
        local right, yards
        if at and pos and QuestData.DistanceTo then
            yards = QuestData.DistanceTo(pos, at.inst, at.x, at.y)
            right = distanceText(yards)
        elseif at then
            right = ""
        else


            right = L["place not known"]
        end
        local mark = known and QuestData.Mark(questID) or nil
        if known then right = withMark(right, mark) end
        local details = table.concat(parts, L[" - "])
        local turnIn = QuestData and QuestData.TurnIn and QuestData.TurnIn(questID) or nil
        local item = { kind = "quest", questID = questID, level = entry.level, leveling = entry, section = section,
                       stepAction = action, verb = L[LEVELING_VERBS[action] or LEVELING_VERBS.accept],
                       title = title, named = named, label = withDetails(head, details), details = details,
                       right = right, yards = yards, mark = mark, zone = zone,
                       turnInZone = placeZone(turnIn), unknownQuest = not named and questID or nil,
                       place = at }
        if at then
            item.action = function() goTo(questID, target, target ~= "next" and 1 or nil) end
        end
        items[#items + 1] = item
    end
    local seen = {}
    for _, entry in ipairs(Leveling.Next()) do
        if not seen[entry.questID] then
            seen[entry.questID] = true
            add(entry, LEVELING_VERBS[entry.action] and entry.action or "accept", "steps")
        end
    end


    local steps = #items
    local classQuests = Leveling.ClassQuests(3)
    local headed = false
    for _, c in ipairs(classQuests) do
        if not seen[c.questID] then
            if not headed then
                items[#items + 1] = { kind = "header", label = L["Class Quests for Your Character"] }
                headed = true
            end
            seen[c.questID] = true
            add({ questID = c.questID, level = c.level,
                  untested = c.level and c.level >= status.untestedFrom }, isAccepted(c.questID) and "complete" or "accept", "class")
        end
    end



    local Auto = FGPS.LevelingAuto
    local following = Auto and Auto.On and Auto.On() or false
    if following then
        local top = {}
        local heading = Auto.Heading and Auto.Heading() or nil
        if not heading and #Leveling.Next() > 0 then



            top[#top + 1] = { kind = "note", noStop = true,
                              label = L["No next stop yet: the next quests have no known place or cannot be taken yet. Skip Step passes over the first one."] }
        end
        if heading then
            top[#top + 1] = { kind = "note", heading = true, label = heading }


            for _, item in ipairs(Auto.batch.items) do
                local questID, done = item.questID, item.done == true
                local title = Leveling.Title(questID)
                local shown, named = shownTitle(questID, title)
                local rec = QuestData and QuestData.Lookup and QuestData.Lookup(questID) or nil
                local action = BATCH_ACTIONS[item.kind] or "complete"
                top[#top + 1] = {
                    kind = "note", batch = true, questID = questID, done = done,
                    label = done and format(L["%s (done)"], title) or title,
                    row = { kind = "quest", questID = questID, level = rec and tonumber(rec.level) or nil,
                            title = shown, named = named, unknownQuest = not named and questID or nil,
                            stepAction = action, done = done, right = "",
                            verb = done and L["Done"] or L[LEVELING_VERBS[action]] },
                }
            end
        end
        for k = #items, 1, -1 do items[k + #top] = items[k] end
        for k = 1, #top do items[k] = top[k] end
    end

    local who = format(L["%s %s"], (UnitRace("player")) or ctx.raceFile, (UnitClass("player")) or ctx.classFile)
    local text
    if steps == 0 then
        text = format(L["Optimized Leveling for %s: nothing left in the order."], who)
    else
        text = format(L["Optimized Leveling for %s: step %d of %d."], who, status.cursor, status.total)
    end
    local untested
    if (ctx.level or 0) + 2 >= status.untestedFrom then
        untested = format(L["Levels %d to 60 were not played in the beta: that part of the order is untested."], status.untestedFrom)
        text = text .. " " .. untested
    end
    return items, text, { ready = true, who = who, cursor = status.cursor, total = status.total, steps = steps,
                          level = ctx.level, untested = untested, following = following }
end
QuestPanel.LevelingItems = levelingItems















local function logHasCollapsedHeader()
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then return false end
    local okN, n = pcall(C_QuestLog.GetNumQuestLogEntries)
    if not okN or type(n) ~= "number" then return false end
    for i = 1, n do
        local ok, info = pcall(C_QuestLog.GetInfo, i)
        if ok and type(info) == "table" and info.isHeader and info.isCollapsed then return true end
    end
    return false
end
QuestPanel.LogHasCollapsedHeader = logHasCollapsedHeader





local function logItems()
    local Quests = FGPS.Quests
    if not (Quests and Quests.List) then
        return {}, L["Quest lookup is not available right now."], false
    end
    local ok, list = pcall(Quests.List)
    if not ok then
        FGPS.Log:Error("Quests.List failed: %s", tostring(list))
        return {}, L["Quest lookup failed."], false
    end
    local QuestData = questData()


    local pos = FGPS.QuestData and FGPS.QuestData.PlayerPos and FGPS.QuestData.PlayerPos() or nil
    local items = {}
    for logIndex, q in ipairs(list or {}) do
        local title, named = shownTitle(q.questID, q.title, q.titleKnown)
        local bundled = q.bundled
        local level = tonumber(bundled and bundled.level or q.level)



        local okStep, step, why = pcall(Quests.NextStep, q.questID)
        if not okStep then step, why = nil, nil end
        local yards, right = nil, ""
        if step and pos and FGPS.QuestData.DistanceTo then
            yards = FGPS.QuestData.DistanceTo(pos, step.inst, step.x, step.y)
            right = distanceText(yards)
        elseif not step and why == "failed" and Quests.ReasonText then

            right = Quests.ReasonText(why)
        elseif not step and why == "objective_unknown" then




            right = L["objective place not known"]
        elseif not step then


            right = L["place not known"]
        end
        if bundled then right = withMark(right, bundled.mark) end



        local nextText
        if why == "failed" and Quests.ReasonText then
            nextText = Quests.ReasonText(why)
        elseif q.complete then
            local zone = step and placeZone(step) or nil
            nextText = zone and format(L["Turn in at %s"], zone) or L["Ready to turn in"]
        elseif type(q.objectiveText) == "string" and q.objectiveText ~= "" then
            nextText = q.objectiveText
        elseif not step then
            nextText = why == "objective_unknown" and L["objective place not known"] or L["place not known"]
        else
            nextText = placeZone(step) or ""
        end
        local item = {
            kind = "quest", questID = q.questID, level = level, title = title, named = named,
            unknownQuest = not named and q.questID or nil, next = nextText, right = right,
            stepAction = q.complete and "turnin" or "complete",
            quest = q, bundled = bundled, yards = yards, step = step, logIndex = logIndex, place = step,
        }
        if step then
            item.action = function() goTo(q.questID, "next") end
        end
        items[#items + 1] = item
    end


    local function rank(item)
        if item.yards then return 0 end
        if item.step then return 1 end
        return 2
    end
    table.sort(items, function(a, b)
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then return ra < rb end
        if a.yards and b.yards and a.yards ~= b.yards then return a.yards < b.yards end
        return a.logIndex < b.logIndex
    end)
    local status
    if #items > 0 and not QuestData then
        status = L["Quest data is not installed in this copy of Cabbie; only what the client reports is shown."]
    end
    return items, status, #items == 0
end
QuestPanel.LogItems = logItems



local function searchDetails(row)
    local parts = {}
    local level = QuestPanel.LevelText(row.level, row.minLevel)
    if level then parts[#parts + 1] = level end
    if row.startInterior then
        parts[#parts + 1] = L["starts inside a dungeon"]
    elseif row.startName then
        parts[#parts + 1] = format(L["starts in %s"], row.startName)
    end
    if row.levelNote then parts[#parts + 1] = row.levelNote end
    if row.layer == "forever" then parts[#parts + 1] = L["Forever quest: start only"] end


    if row.partial then parts[#parts + 1] = L["objective place not known"] end
    return table.concat(parts, L[" - "])
end




local function searchWhere(row, pos)
    local where = row.startInterior and L["starts inside a dungeon"] or row.startName
    local far
    if pos then
        if type(row.yards) == "number" then
            local s = settings()
            far = Util.FormatDistance(row.yards, s and s.units or "yards")
            if far == "" then far = nil end
        else
            far = L["another continent"]
        end
    end
    if where and far then return format(L["%s, %s"], where, far) end
    return where or far or ""
end


local function searchAction(questID)
    if isAccepted(questID) then return goTo(questID, "next") end
    return goTo(questID, "giver", 1)
end



local function searchRowItems(rows)
    local items = {}
    local QuestData = FGPS.QuestData
    local pos = QuestData and QuestData.PlayerPos and QuestData.PlayerPos() or nil
    for _, row in ipairs(rows) do
        local title, named = titleFor(row.questID)
        local item = {
            kind = "quest", questID = row.questID, row = row, level = row.level, title = title, named = named,
            unknownQuest = not named and row.questID or nil, next = searchWhere(row, pos), details = searchDetails(row),
            right = withMark(distanceFrom(pos, row.yards), row.mark),
            stepAction = isAccepted(row.questID) and "complete" or "accept",
            action = function() return searchAction(row.questID) end,
        }
        items[#items + 1] = item
    end
    return items
end

local function searchItems()
    local QuestData = questData()
    if not QuestData then
        return {}, L["Quest data is not installed in this copy of Cabbie."]
    end
    local rows, status = QuestData.Search(QuestPanel.query)
    QuestPanel.rows = rows
    local items = searchRowItems(rows)
    if #rows == 0 and type(status) == "string" and status ~= "" then
        status = status .. " " .. L["Or open Search for a town, inn, or flight master."]
    end
    return items, status
end

local function searching()
    return QuestPanel.query ~= nil and QuestPanel.query ~= ""
end

local repaintQuestRows




function QuestPanel:SweepTitles()
    local QuestData = questData()
    if not QuestData or not searching() then return end
    local unnamed = QuestData.UnnamedIn(self.rows)
    if #unnamed == 0 then
        self:UpdateLookupButton()
        return
    end
    local generation = self.searchGeneration
    QuestData.SweepTitles(unnamed, function(found)
        if QuestPanel.searchGeneration ~= generation then return end
        if found and found > 0 then QuestPanel:Relabel() end
        QuestPanel:UpdateLookupButton()
    end)
end




function QuestPanel:Relabel()
    for _, item in ipairs(self.items) do
        if item.kind == "quest" and item.row then
            local title, known = titleFor(item.questID)
            if known then item.row.title = title end
            item.title, item.named = title, known
            item.unknownQuest = not known and item.questID or nil
        end
    end
    repaintQuestRows()
end




function QuestPanel:UpdateLookupButton()
    local button = self.questsPage and self.questsPage.Lookup
    if not button then return end
    local QuestData = questData()
    if not QuestData or not searching() then
        button:Hide()
        return
    end
    local unnamed = QuestData.UnnamedIn(self.rows)
    local left = QuestData.LookupsLeft()
    local allowed = QuestData.CanLookup()
    if #unnamed == 0 or left <= 0 or not (allowed or QuestData.lookups.inFlight) then
        button:Hide()
        return
    end
    local want = #unnamed
    if want > left then want = left end
    setButtonText(button, format(want == 1 and L["Look Up %d Name (%d Left)"] or L["Look Up %d Names (%d Left)"], want, left))
    button:Show()
end




local function reasonText(code, fallback)
    local Compat = FGPS.UI.Compat
    if Compat and Compat.ReasonText then return Compat.ReasonText(code, fallback) end
    return tostring(code or fallback or L["unknown reason"])
end




function QuestPanel:LookupNextName()
    local QuestData = questData()
    if not QuestData then return false end
    local unnamed = QuestData.UnnamedIn(self.rows)
    local questID = unnamed[1]
    if not questID then return false end
    local generation = self.searchGeneration
    local ok, why = QuestData.RequestTitle(questID, function()
        if QuestPanel.searchGeneration ~= generation then return end
        QuestPanel:Relabel()
        QuestPanel:UpdateLookupButton()
    end)
    if not ok then
        FGPS:Print(L["Cabbie cannot look a name up right now (%s)."], reasonText(why, L["unknown reason"]))
    end
    self:UpdateLookupButton()
    return ok
end




local renderQuestsPage



function QuestPanel:SetFocus(questID)
    self.focus = questID
    local QuestMap = FGPS.UI.QuestMap
    if QuestMap and QuestMap.SetFocus then pcall(QuestMap.SetFocus, questID) end
end



local function newQuery(text)
    QuestPanel.query = text or ""
    QuestPanel.searchGeneration = QuestPanel.searchGeneration + 1
    QuestPanel.questsPage.selected = nil
    QuestPanel:SetFocus(nil)
end

function QuestPanel:RunSearch(text)
    newQuery(text)
    self:Refresh()
end

function QuestPanel:ScheduleSearch(text)
    self.pendingQuery = text
    if C_Timer and C_Timer.After then
        local generation = self.searchGeneration + 1
        self.searchGeneration = generation
        C_Timer.After(DEBOUNCE_SECONDS, function()
            if QuestPanel.searchGeneration ~= generation then return end
            QuestPanel:RunSearch(QuestPanel.pendingQuery or "")
        end)
    else
        self:RunSearch(text)
    end
end


function QuestPanel:Refresh()
    renderQuestsPage()
end




function QuestPanel:RefreshDistances()
    if not searching() then return self:Refresh() end
    local QuestData = questData()
    local rows = self.rows
    if not QuestData or not QuestData.DistanceTo or type(rows) ~= "table" then return self:Refresh() end
    local pos = QuestData.PlayerPos and QuestData.PlayerPos() or nil
    for _, row in ipairs(rows) do
        local start = QuestData.Start and QuestData.Start(row.questID) or nil
        if start and pos then
            row.yards = QuestData.DistanceTo(pos, start.inst, start.x, start.y)
        else
            row.yards = nil
        end
    end
    table.sort(rows, function(a, b)
        local ay, by = a.yards, b.yards
        if ay and by then
            if ay ~= by then return ay < by end
        elseif ay then
            return true
        elseif by then
            return false
        end
        return (a.questID or 0) < (b.questID or 0)
    end)
    renderQuestsPage(searchRowItems(rows))
end





local function onQuestsUpdated()
    if not QuestPanel:IsShown() then return end
    if searching() then


        renderQuestsPage(searchRowItems(QuestPanel.rows))
    else
        QuestPanel:Refresh()
    end
end

local function listen(on)
    local Events = FGPS.Events
    Events:Unregister("QUESTS_UPDATED", onQuestsUpdated)
    if on then Events:Register("QUESTS_UPDATED", onQuestsUpdated, QuestPanel) end
end



local function onLevelingUpdated()
    QuestPanel.RefreshLevelingPage()
    if QuestPanel:IsShown() and QuestPanel.questsPage.empty then QuestPanel:Refresh() end
end






function QuestPanel.About()
    local QuestData = FGPS.QuestData
    local stats = QuestData and QuestData.Stats and QuestData.Stats() or nil
    if not stats or not stats.available then
        FGPS:Print(L["Quest data is not installed in this copy of Cabbie."])
        return false
    end


    FGPS:Print(L["Quests: %d with a full route, %d with an objective whose place is not known, %d with only one known end."],
        stats.full or stats.shipped, stats.partial or 0, stats.oneEnded or 0)
    local d = stats.dataset
    if d then
        FGPS:Print(L["Forever's own quests: %d, and %d of them have a known start."],
            (d.foreverListed or 0) + (d.foreverUnknown or 0), d.foreverPositioned or 0)
    end
    FGPS:Print(L["Quest givers may have moved since the records were made. Names are the game's own for %d of %d quests, the 1.12 records' for the rest."],
        stats.titlesKnown or 0, stats.shipped)
    return true
end

















QuestPanel.trackerHooks = {}

local function fromTracker(questID)
    local s = settings()
    if s and type(s.quests) == "table" and s.quests.enabled == false then return end
    questID = tonumber(questID)
    if not questID or questID <= 0 then return end
    local ok, err = pcall(QuestPanel.ShowQuest, QuestPanel, questID)
    if not ok then FGPS.Log:Error("Opening the quest window from the tracker failed: %s", tostring(err)) end
end

local function modified()
    return (IsShiftKeyDown and IsShiftKeyDown()) or (IsControlKeyDown and IsControlKeyDown())
        or (IsAltKeyDown and IsAltKeyDown()) or false
end



local NATIVE_TRACKERS = { { "native", "QuestObjectiveTracker" }, { "campaign", "CampaignQuestObjectiveTracker" } }

local function onNativeHeaderClick(_, block, mouseButton)
    if mouseButton == "RightButton" or type(block) ~= "table" or modified() then return end
    fromTracker(block.id)
end



function QuestPanel.HookTrackers()
    local hooks = QuestPanel.trackerHooks
    if type(hooksecurefunc) ~= "function" then return hooks end
    if not hooks.questie then
        local loader = rawget(_G, "QuestieLoader")
        local modules = type(loader) == "table" and rawget(loader, "_modules") or nil
        local utils = type(modules) == "table" and rawget(modules, "TrackerUtils") or nil
        if type(utils) == "table" and type(utils.ShowQuestLog) == "function" then
            hooks.questie = pcall(hooksecurefunc, utils, "ShowQuestLog", function(_, quest)
                if type(quest) == "table" then fromTracker(quest.Id) end
            end) or nil
        end
    end
    for _, entry in ipairs(NATIVE_TRACKERS) do
        local key, name = entry[1], entry[2]
        if not hooks[key] then
            local tracker = rawget(_G, name)
            if type(tracker) == "table" and type(tracker.OnBlockHeaderClick) == "function" then
                hooks[key] = pcall(hooksecurefunc, tracker, "OnBlockHeaderClick", onNativeHeaderClick) or nil
            end
        end
    end
    return hooks
end


























local LevelingPage = {}
QuestPanel.LevelingPage = LevelingPage
QuestPanel.LEVELING_PAGE_ICON = "Interface\\AddOns\\Cabbie\\Media\\icon"
QuestPanel.NEXT_STOP_ROWS = 3
QuestPanel.MAX_LEVEL = 60
local STEP_ICONS = { accept = "Interface\\GossipFrame\\AvailableQuestIcon", turnin = "Interface\\GossipFrame\\ActiveQuestIcon" }
local BREAK_FILE = "Interface\\QuestFrame\\UI-HorizontalBreak"
local FOLD_OPEN, FOLD_CLOSED = "Interface\\Buttons\\UI-MinusButton-Up", "Interface\\Buttons\\UI-PlusButton-Up"
local BAR_FILE = "Interface\\TargetingFrame\\UI-StatusBar"

local PAGE_HEADING, PAGE_SUB, PAGE_RUBRIC, PAGE_BREAK = 22, 14, 16, 16
local PAGE_VERB, PAGE_BAR, PAGE_LEVEL, PAGE_STATUS = 72, 10, 14, 40


QuestPanel.levelingPage = { rows = {}, zones = {} }



local function pageHas(file, without, which)
    local look = Look()
    if look.TomeHas("file", file) then return true end
    look.NoteOnce("tome:" .. (which or "leveling") .. ":" .. file, "Tome: %s missing; %s", file, without)
    return false
end

local function pageText(parent, role, color, justify)
    local look = Look()
    local text = parent:CreateFontString(nil, "OVERLAY", look.Font(role))
    text:SetTextColor(look.Color(color))
    text:SetJustifyH(justify or "LEFT")
    if text.SetWordWrap then text:SetWordWrap(false) end
    text:SetText("")
    return text
end


local function pageSize(frame)
    local look = Look()
    local tokens, edge = look.TOKENS, look.TOME_FRAME
    local width, height = frame:GetWidth(), frame:GetHeight()
    if type(width) ~= "number" or width <= 0 then
        width = tokens.windowWidth - edge.sheetLeft - edge.sheetRight - 2 * tokens.pad
    end
    if type(height) ~= "number" or height <= 0 then
        height = tokens.windowHeight - edge.sheetTop - edge.sheetBottom - 2 * tokens.pad - tokens.rowQuest - tokens.gapWide
    end
    return width, height
end

local function hideTip(owner)
    if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end


local function dressStepRow(row)
    local tokens = Look().TOKENS
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(tokens.iconBox, tokens.iconBox)
    row.Icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.Name = pageText(row, "pageBody", "ink")
    row.Name:SetPoint("LEFT", row, "LEFT", tokens.iconBox + tokens.gap, 0)
    row.Verb = pageText(row, "pageSub", "inkGrey", "RIGHT")
    row.Verb:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.Verb:SetWidth(PAGE_VERB)
    row.Name:SetHeight(tokens.rowQuest)


    row.Suffix = pageText(row, "pageBody", "inkGrey")
    row.Suffix:SetPoint("LEFT", row.Name, "RIGHT", tokens.gap, 0)
    row.Suffix:SetHeight(tokens.rowQuest)
    row.Suffix:Hide()
end



local function stepSuffix(item)
    if item.sameName and item.turnInZone then return format(L["turn in at %s"], item.turnInZone) end
    return nil
end


local function textWidth(text)
    if text.GetUnboundedStringWidth then return text:GetUnboundedStringWidth() or 0 end
    return text:GetStringWidth() or 0
end

local function stepIcon(item)
    if item.stepAction == "complete" then return Look().ICONS.quest.file end
    return STEP_ICONS[item.stepAction] or STEP_ICONS.accept
end



local function paintStepRow(row, item, width)
    local look, tokens = Look(), Look().TOKENS
    row.entry = item
    row.fgpsZone = nil
    local icon = stepIcon(item)
    if pageHas(icon, "the Optimized Leveling rows have no icon") then
        row.Icon:SetTexture(icon)
        row.Icon:SetTexCoord(0, 1, 0, 1)
        row.Icon:Show()
    else
        row.Icon:Hide()
    end
    row.Name:SetFontObject(look.Font("pageBody"))
    row.Name:SetText(look.QuestTitle(item.title, item.level))

    if item.unknownQuest or item.done then
        row.Name:SetTextColor(look.Color("inkGrey"))
    else
        row.Name:SetTextColor(look.QuestColor(item.level, item.questID))
    end
    row.Verb:SetText(item.verb or "")
    row.Verb:Show()
    local room = math.max(0, width - PAGE_VERB - tokens.iconBox - tokens.gap - tokens.gapWide)
    local suffix = stepSuffix(item)
    if suffix then
        row.Suffix:SetText(suffix)
        local suffixWidth = math.min(textWidth(row.Suffix), room)
        row.Suffix:SetWidth(suffixWidth)
        row.Suffix:Show()
        row.Name:SetWidth(math.max(0, math.min(textWidth(row.Name), room - suffixWidth - tokens.gap)))
    else
        row.Suffix:SetText("")
        row.Suffix:Hide()
        row.Name:SetWidth(room)
    end
end



local function stepTooltip(owner, item)
    if type(item) ~= "table" or not item.questID then return end
    local look = Look()
    local parts = {}
    if item.unknownQuest then parts[#parts + 1] = format(L["Quest %d"], item.unknownQuest) end
    local suffix = stepSuffix(item)
    if suffix then parts[#parts + 1] = suffix end
    if item.details and item.details ~= "" then parts[#parts + 1] = item.details end
    if item.right and item.right ~= "" then parts[#parts + 1] = item.right end
    local title = item.unknownQuest and L["Unknown quest"] or look.QuestTitle(item.title, item.level)



    local hint = L["Right-click for options"]
    if type(item.action) == "function" then
        hint = L["Double-click to be guided there"] .. " \194\183 " .. hint
    end
    look.Tooltip(owner, title, table.concat(parts, L[" - "]), hint)
end












local skipStep


local function placeMap(at)
    if type(at) ~= "table" then return nil end
    local map = tonumber(at.map)
    if map then return map end
    local Coords = FGPS.Coords
    if Coords and Coords.WorldToMap and at.inst and at.x and at.y then
        local ok, mapID = pcall(Coords.WorldToMap, at.inst, at.x, at.y)
        if ok and tonumber(mapID) then return tonumber(mapID) end
    end
    return nil
end



local function rowPlace(item)
    if item.place then return item.place end
    if not item.row then return nil end
    if isAccepted(item.questID) then
        local ok, step = pcall(FGPS.Quests.NextStep, item.questID)
        return ok and step or nil
    end
    local QuestData = questData()
    return QuestData and QuestData.Start and QuestData.Start(item.questID) or nil
end



local function mapClosed()
    return type(OpenWorldMap) ~= "function" or (InCombatLockdown ~= nil and InCombatLockdown() == true)
end


local function actOn(item)
    if type(item) == "table" and item.kind == "quest" and type(item.action) == "function" then item.action() end
end



local function openRowMenu(owner, item, withSkip)
    local Menus = FGPS.UI.Menus
    if not (Menus and Menus.OpenRowMenu) or type(item) ~= "table" or item.kind ~= "quest" then return nil end
    local map = placeMap(rowPlace(item))
    local entries = {
        { label = L["Guide Me"], onClick = function() actOn(item) end, disabled = type(item.action) ~= "function" },
        { label = L["Show on Map"], onClick = function() Menus.ShowOnMap(map) end, disabled = map == nil or mapClosed },
    }
    if withSkip then
        local questID = item.questID
        entries[#entries + 1] = { label = L["Skip Step"], onClick = function() skipStep(questID) end,
                                  disabled = item.done == true, destructive = true }
    end
    local title = item.unknownQuest and L["Unknown quest"] or item.title
    return Menus.OpenRowMenu(owner, { title = title, entries = entries })
end
QuestPanel.OpenRowMenu = openRowMenu



local function renderPageRow(row, item, _, list)
    local look, tokens = Look(), Look().TOKENS
    if not row.Name then
        dressStepRow(row)
        if row.Text then row.Text:SetText("") row.Text:Hide() end
    end
    local width = (list:GetWidth() or 0)
    if list.Bar and list.Bar:IsShown() then width = width - (list.Bar:GetWidth() or 0) - 2 end
    if item.kind == "quest" then
        paintStepRow(row, item, width)
        return
    end
    row.entry = nil
    row.Verb:SetText("")
    row.Verb:Hide()
    row.Suffix:SetText("")
    row.Suffix:Hide()
    row.Name:SetWidth(math.max(0, width - tokens.iconBox - tokens.gap))
    if item.kind == "zone" then
        row.fgpsZone = item.zone
        local open = QuestPanel.levelingPage.zones[item.zone].open
        local file = open and FOLD_OPEN or FOLD_CLOSED

        local folds = pageHas(FOLD_OPEN, "a later zone's header opens and closes by its name alone")
        folds = pageHas(FOLD_CLOSED, "a later zone's header opens and closes by its name alone") and folds
        if folds then
            row.Icon:SetTexture(file)
            row.Icon:Show()
        else
            row.Icon:Hide()
        end
        row.Name:SetFontObject(look.Font("pageBody"))
        row.Name:SetTextColor(look.Color("ink"))
        row.Name:SetText(item.label)
    else
        row.fgpsZone = nil
        row.Icon:Hide()
        row.Name:SetFontObject(look.Font("pageSub"))
        row.Name:SetTextColor(look.Color("rubric"))
        row.Name:SetText(item.label)
    end
end

local renderLevelingPage
local newNextRow

local function onPageRowClick(item)
    if type(item) ~= "table" or item.kind ~= "zone" then return end
    local zone = QuestPanel.levelingPage.zones[item.zone]
    zone.open = not zone.open
    renderLevelingPage()
end



local function onPageRowDoubleClick(item)
    if type(item) == "table" and item.kind == "zone" then return onPageRowClick(item) end
    actOn(item)
end


local function onPageRowRightClick(item, _, row)
    openRowMenu(row, item, true)
end

local function onPageRowEnter(item, _, row)
    if type(item) == "table" and item.kind == "quest" then stepTooltip(row, item) end
end

local function onPageRowLeave(_, _, row)
    hideTip(row)
end



newNextRow = function(frame, width)
    local row = CreateFrame("Button", nil, frame)
    row:SetHeight(Look().TOKENS.rowQuest)
    row:SetWidth(width)
    dressStepRow(row)
    row:SetScript("OnEnter", function(self) stepTooltip(self, self.entry) end)
    row:SetScript("OnLeave", hideTip)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
        if button == "RightButton" then openRowMenu(self, self.entry, true) end
    end)
    row:SetScript("OnDoubleClick", function(self, button)
        if button == "RightButton" then openRowMenu(self, self.entry, true) else actOn(self.entry) end
    end)
    row:Hide()
    return row
end


function LevelingPage.build(frame)
    local page = QuestPanel.levelingPage
    local look = Look()
    local tokens = look.TOKENS
    page.frame = frame
    local width = pageSize(frame)

    page.Heading = pageText(frame, "pageHeading", "ink")
    page.Heading:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    page.Heading:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    page.Heading:SetHeight(PAGE_HEADING)
    page.Who = pageText(frame, "pageSub", "inkGrey")
    page.Who:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -PAGE_HEADING)
    page.Who:SetSize(width / 2, PAGE_SUB)
    page.Step = pageText(frame, "pageSub", "inkGrey", "RIGHT")
    page.Step:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -PAGE_HEADING)
    page.Step:SetSize(width / 2, PAGE_SUB)


    local box = CreateFrame("Frame", nil, frame)
    box:SetHeight(PAGE_SUB)
    box:EnableMouse(true)
    box:SetScript("OnEnter", function(self)
        Look().Tooltip(self, L["Some quest givers may have moved since the old records."], FGPS.QuestData.MarkText(0))
    end)
    box:SetScript("OnLeave", hideTip)
    page.ConfidenceBox = box
    page.Confidence = pageText(box, "pageSub", "inkGrey")
    page.Confidence:SetAllPoints(box)

    page.NextHead = pageText(frame, "pageSub", "rubric")
    page.NextHead:SetText(L["Next Stop"])
    page.NextHead:SetHeight(PAGE_RUBRIC)
    page.NextFar = pageText(frame, "pageSub", "inkGrey", "RIGHT")
    page.NextFar:SetHeight(PAGE_RUBRIC)
    page.NextFar:SetWidth(width / 2)

    page.nextRows = {}
    for i = 1, QuestPanel.NEXT_STOP_ROWS do page.nextRows[i] = newNextRow(frame, width) end


    page.Break, page.Bar = nil, nil
    if pageHas(BREAK_FILE, "a gap stands for the ornament under Next Stop") then
        page.Break = frame:CreateTexture(nil, "ARTWORK")
        page.Break:SetTexture(BREAK_FILE)
        page.Break:SetHeight(PAGE_BREAK)
    end

    local F = Frames()
    if F and F.CreateScrollList then
        local ok, list = pcall(F.CreateScrollList, frame, tokens.rowQuest, renderPageRow,
            { width = width, onClick = onPageRowClick, onDoubleClick = onPageRowDoubleClick,
              onRightClick = onPageRowRightClick, onEnter = onPageRowEnter, onLeave = onPageRowLeave,

              noPick = true })
        if ok and type(list) == "table" then
            page.list = list
        else
            FGPS.Log:Error("Frames.CreateScrollList failed: %s", tostring(list))
        end
    end



    local level = pageText(frame, "pageSub", "inkGrey")
    level:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    level:SetSize(width, PAGE_LEVEL)
    page.Level = level
    local barBottom = PAGE_LEVEL + tokens.gap
    if pageHas(BAR_FILE, "the level has no bar") and CreateFrame then
        local ok, bar = pcall(CreateFrame, "StatusBar", nil, frame)
        if ok and bar and bar.SetStatusBarTexture then
            bar:SetStatusBarTexture(BAR_FILE)
            if bar.SetStatusBarColor then bar:SetStatusBarColor(look.Color("rubric")) end
            bar:SetMinMaxValues(0, QuestPanel.MAX_LEVEL)
            bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, barBottom)
            bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, barBottom)
            bar:SetSize(width, PAGE_BAR)
            page.Bar = bar
            barBottom = barBottom + PAGE_BAR + tokens.gap
        end
    end
    local statusBox = CreateFrame("Frame", nil, frame)
    statusBox:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, barBottom)
    statusBox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, barBottom)
    statusBox:SetSize(width, PAGE_STATUS)
    statusBox:EnableMouse(true)
    statusBox:SetScript("OnEnter", function(self)
        if page.saidQuest then Look().Tooltip(self, L["Unknown quest"], format(L["Quest %d"], page.saidQuest)) end
    end)
    statusBox:SetScript("OnLeave", hideTip)
    page.StatusBox = statusBox
    local status = pageText(statusBox, "pageSub", "ink")
    status:SetAllPoints(statusBox)
    if status.SetWordWrap then status:SetWordWrap(true) end
    if status.SetJustifyV then status:SetJustifyV("BOTTOM") end
    page.Status = status
    page.footHeight = barBottom + PAGE_STATUS + tokens.gap
end









local function sortSteps(items)
    local steps, class, batch = {}, {}, {}
    for _, item in ipairs(items) do
        if item.kind == "quest" then
            if item.section == "class" then class[#class + 1] = item else steps[#steps + 1] = item end
        elseif item.kind == "note" and item.batch and item.row then
            batch[#batch + 1] = item
        end
    end
    local zone
    for _, item in ipairs(steps) do
        zone = item.zone or zone
        item.pageZone = zone
    end
    local first
    for _, item in ipairs(steps) do
        if item.pageZone then first = item.pageZone break end
    end
    for _, item in ipairs(steps) do item.pageZone = item.pageZone or first end
    local titles = {}
    for _, item in ipairs(steps) do titles[item.title] = (titles[item.title] or 0) + 1 end
    for _, item in ipairs(class) do titles[item.title] = (titles[item.title] or 0) + 1 end
    for _, item in ipairs(steps) do item.sameName = item.named and titles[item.title] > 1 or nil end
    for _, item in ipairs(class) do item.sameName = item.named and titles[item.title] > 1 or nil end

    local nextStop, shown = {}, {}
    if #batch > 0 then
        local byQuest = {}
        for _, item in ipairs(steps) do byQuest[item.questID] = byQuest[item.questID] or item end
        for _, note in ipairs(batch) do
            local step = not note.done and byQuest[note.questID] or nil
            local row = step or note.row
            if not shown[row] then
                row.section = "next"
                nextStop[#nextStop + 1] = row
                shown[row] = true
            end
        end
    else
        for _, item in ipairs(steps) do
            if #nextStop >= QuestPanel.NEXT_STOP_ROWS or item.pageZone ~= first then break end
            item.section = "next"
            nextStop[#nextStop + 1] = item
            shown[item] = true
        end
    end

    local here, runs = {}, {}
    for _, item in ipairs(steps) do
        if not shown[item] then
            local run = runs[#runs]
            if not run or run.zone ~= item.pageZone then
                run = { zone = item.pageZone, steps = {} }
                runs[#runs + 1] = run
            end
            run.steps[#run.steps + 1] = item
        end
    end
    if runs[1] and runs[1].zone == first then
        here = table.remove(runs, 1).steps
        for _, item in ipairs(here) do item.section = "here" end
    end
    for _, run in ipairs(runs) do
        for _, item in ipairs(run.steps) do item.section = "later" end
    end
    return nextStop, here, runs, class, first
end





local function laterItems(here, runs, class, first)
    local page = QuestPanel.levelingPage
    local items = {}
    if #here > 0 then
        items[#items + 1] = { kind = "rubric", label = first and format(L["Later in %s"], first) or L["Later in the Order"] }
        for _, item in ipairs(here) do items[#items + 1] = item end
    end
    local function fold(key, label, steps)
        page.zones[key] = page.zones[key] or { open = false }
        items[#items + 1] = { kind = "zone", zone = key, label = label }
        if page.zones[key].open then
            for _, item in ipairs(steps) do items[#items + 1] = item end
        end
    end
    local runsOf = {}
    for _, run in ipairs(runs) do
        local name = run.zone or L["Later in the Order"]
        runsOf[name] = (runsOf[name] or 0) + 1
        fold(runsOf[name] == 1 and name or (name .. "#" .. runsOf[name]), name, run.steps)
    end
    if #class > 0 then
        local key = L["Class Quests for Your Character"]
        for _, item in ipairs(class) do item.section = "class" end
        fold(key, key, class)
    end
    return items
end




local function pageStatus(items, info)
    local page = QuestPanel.levelingPage
    if page.said then return page.said end
    if not info.ready then return info.why or "" end
    for _, item in ipairs(items) do
        if item.kind == "note" and item.noStop then return item.label end
    end
    if info.steps == 0 then return format(L["Optimized Leveling for %s: nothing left in the order."], info.who) end
    return info.untested or ""
end

local function playerLevel()
    if type(UnitLevel) ~= "function" then return nil end
    local ok, level = pcall(UnitLevel, "player")
    if ok and type(level) == "number" and level > 0 then return level end
    return nil
end


renderLevelingPage = function()
    local page = QuestPanel.levelingPage
    local frame = page.frame
    if not frame then return end
    local look = Look()
    local tokens = look.TOKENS
    local width, height = pageSize(frame)
    local items, _, info = levelingItems()
    local nextStop, here, runs, class, first = sortSteps(items)

    page.Heading:SetText(first or "")
    page.Who:SetText(info.ready and info.who or "")
    page.Step:SetText((info.ready and info.steps > 0) and format(L["Step %d of %d"], info.cursor, info.total) or "")

    local y = PAGE_HEADING + PAGE_SUB + tokens.gap
    local vanilla = false
    for _, item in ipairs(items) do
        if item.kind == "quest" and item.mark == 0 then vanilla = true break end
    end
    page.Confidence:SetText(vanilla and L["Some quest givers may have moved since the old records."] or "")
    page.ConfidenceBox:ClearAllPoints()
    page.ConfidenceBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
    page.ConfidenceBox:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -y)
    page.ConfidenceBox:SetWidth(width)
    page.ConfidenceBox:SetShown(vanilla)
    page.Confidence:SetShown(vanilla)
    if vanilla then y = y + PAGE_SUB + tokens.gap end

    local hasNext = #nextStop > 0
    page.NextHead:ClearAllPoints()
    page.NextHead:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
    page.NextHead:SetShown(hasNext)
    page.NextFar:ClearAllPoints()
    page.NextFar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -y)

    local lead
    for _, item in ipairs(nextStop) do
        if not item.done then lead = item break end
    end
    page.NextFar:SetText(lead and lead.yards and distanceText(lead.yards) or "")
    page.NextFar:SetShown(hasNext)
    if hasNext then y = y + PAGE_RUBRIC end

    local rows = {}
    for i = #page.nextRows + 1, #nextStop do page.nextRows[i] = newNextRow(frame, width) end
    for i, row in ipairs(page.nextRows) do
        local item = nextStop[i]
        row:ClearAllPoints()
        if item then
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -y)
            row:SetWidth(width)
            paintStepRow(row, item, width)
            row:Show()
            rows[#rows + 1] = row
            y = y + tokens.rowQuest
        else
            row.entry = nil
            row:Hide()
        end
    end

    local listItems = laterItems(here, runs, class, first)
    local showBreak = hasNext and #listItems > 0
    if page.Break then
        page.Break:ClearAllPoints()
        page.Break:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
        page.Break:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -y)
        page.Break:SetShown(showBreak)
    end
    if showBreak then y = y + (page.Break and PAGE_BREAK or tokens.gapWide) end

    local list = page.list
    if list then
        local listHeight = math.max(tokens.rowQuest, height - y - page.footHeight)
        list:ClearAllPoints()
        list:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
        list:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -y)
        list:SetSize(width, listHeight)
        list:SetItems(listItems)
        list:SetShown(#listItems > 0)
        for _, row in ipairs(list.rows or {}) do
            if row:IsShown() and row.entry then rows[#rows + 1] = row end
        end
    end
    page.rows = rows

    page.Status:SetText(pageStatus(items, info))
    local level = info.level or playerLevel()
    page.Level:SetText(level and format(L["Level %d of %d"], level, QuestPanel.MAX_LEVEL) or "")
    if page.Bar then
        page.Bar:SetValue(level or 0)
        page.Bar:SetShown(level ~= nil)
    end
    page.info = info
end


function LevelingPage.show()
    local page = QuestPanel.levelingPage
    page.said, page.saidQuest = nil, nil
    renderLevelingPage()
end




skipStep = function(questID)
    local Leveling = FGPS.Leveling
    if not (Leveling and Leveling.Skip) then return end
    local skipped = Leveling.Skip(tonumber(questID))
    local page = QuestPanel.levelingPage
    if skipped then
        local title, known = titleFor(skipped)
        page.said = format(L["Optimized Leveling: skipped %s."], title)
        page.saidQuest = not known and skipped or nil
    end
    onLevelingUpdated()
end


local function guide()
    local Auto = FGPS.LevelingAuto
    if not Auto then return end
    if Auto.On and Auto.On() then Auto.Stop() else Auto.Start() end
    QuestPanel.RefreshLevelingPage()
end




function QuestPanel.LevelingFooterButtons(info)
    if not info then
        local _, _, asked = levelingItems()
        info = asked
    end
    local why = not info.ready and info.why or nil
    local Auto = FGPS.LevelingAuto
    return {
        { label = L["Skip Step"], onClick = function() skipStep() end, enabled = info.ready == true, why = why },
        { label = info.following and L["Stop"] or L["Guide Me"], onClick = guide,
          enabled = info.ready == true and Auto ~= nil, why = why },
    }
end


function LevelingPage.footer(win)
    local page = QuestPanel.levelingPage
    local info = page.info
    if not info then
        local _, _, asked = levelingItems()
        info = asked
    end
    win:SetFooterButtons(QuestPanel.LevelingFooterButtons(info))
    if win.FooterNote then
        win.FooterNote:SetText(info.following and L["Following the order: Cabbie sets the next stop by itself."]
            or L["Follows your level and quest log by itself."])
    end
end


function QuestPanel.RefreshLevelingPage()
    local Tome = FGPS.UI.Tome
    if not (Tome and Tome.Current and Tome:Current() == "leveling") then return end
    renderLevelingPage()
    if Tome.window then LevelingPage.footer(Tome.window) end
end




function QuestPanel.QuestHelpOn()
    local db = FGPS.DB
    return not (db and db.Get and db:Get("quests.enabled") == false)
end

local function questHelpOffSaid()
    if QuestPanel.QuestHelpOn() then return false end
    FGPS:Print(L["Quest help is off. Turn it on under Quests in Cabbie's settings."])
    return true
end


function QuestPanel.OpenLevelingPage()
    if questHelpOffSaid() then return false end
    local Tome = FGPS.UI.Tome
    if Tome and Tome.pages and Tome.pages.leveling and Tome:Open("leveling") then return true end
    FGPS:Print(L["Optimized Leveling is not available in this copy of Cabbie."])
    return false
end










local QuestsPage = {}
QuestPanel.QuestsPage = QuestsPage
QuestPanel.QUESTS_PAGE_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"

local QP_SEARCH, QP_STATUS, QP_BUTTON, QP_LOOKUP = 22, 28, 22, 170

QuestPanel.NEARBY_HEAD, QuestPanel.NEARBY_LINE, QuestPanel.BUTTON_HEIGHT = PAGE_RUBRIC, PAGE_SUB, QP_BUTTON
local QP_NEXT_SHARE = 0.45


local function dressQuestRow(row)
    local tokens = Look().TOKENS
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(tokens.iconBox, tokens.iconBox)
    row.Icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.Name = pageText(row, "pageBody", "ink")
    row.Name:SetPoint("LEFT", row, "LEFT", tokens.iconBox + tokens.gap, 0)
    row.Name:SetHeight(tokens.rowQuest)
    row.Next = pageText(row, "pageSub", "inkGrey", "RIGHT")
    row.Next:SetPoint("RIGHT", row, "RIGHT", 0, 0)
end

local function paintQuestRow(row, item, width)
    local look, tokens = Look(), Look().TOKENS
    row.entry, row.questID = item, item.questID
    local icon = stepIcon(item)
    if pageHas(icon, "the Quests rows have no icon", "quests") then
        row.Icon:SetTexture(icon)
        row.Icon:SetTexCoord(0, 1, 0, 1)
        row.Icon:Show()
    else
        row.Icon:Hide()
    end
    row.Name:SetText(look.QuestTitle(item.title, item.level))
    if item.unknownQuest then
        row.Name:SetTextColor(look.Color("inkGrey"))
    else
        row.Name:SetTextColor(look.QuestColor(item.level, item.questID))
    end
    row.Next:SetText(item.next or "")
    local nextWidth = math.floor(width * QP_NEXT_SHARE)
    row.Next:SetWidth(nextWidth)
    row.Name:SetWidth(math.max(0, width - nextWidth - tokens.iconBox - tokens.gap - tokens.gapWide))
end

local function onQuestRowEnter(item, _, row)
    if type(item) == "table" and item.kind == "quest" then stepTooltip(row, item) else hideTip(row) end
end




local function renderQuestRow(row, item, index, list)
    if not row.Name then
        dressQuestRow(row)
        if row.Text then row.Text:SetText("") row.Text:Hide() end
    end
    local width = (list:GetWidth() or 0)
    if list.Bar and list.Bar:IsShown() then width = width - (list.Bar:GetWidth() or 0) - 2 end
    paintQuestRow(row, item, width)
    if row.fgpsHover and GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(row) then
        onQuestRowEnter(item, index, row)
    end
end
QuestPanel.RenderQuestRow = renderQuestRow

local layoutQuestsPage
local pickQuest

local function refreshQuestsFooter()
    local Tome = FGPS.UI.Tome
    if Tome and Tome.window and Tome.Current and Tome:Current() == "quests" then QuestsPage.footer(Tome.window) end
end


local function onQuestRowClick(item)
    if type(item) ~= "table" or item.kind ~= "quest" then return end
    QuestPanel.questsPage.selected = item.questID
    Look().PlaySound("IG_QUEST_LIST_SELECT")
    if searching() then QuestPanel:SetFocus(item.questID) end
    refreshQuestsFooter()
end


function QuestPanel:MovePick(step)
    local items, page = self.items, self.questsPage
    if #items == 0 then return false end
    local index
    for i, item in ipairs(items) do
        if item.questID == page.selected then index = i break end
    end
    if index then index = index + step elseif step > 0 then index = 1 else index = #items end
    if index < 1 then index = 1 elseif index > #items then index = #items end
    local list = page.list
    if list and list.SetSelected then list:SetSelected(index) end
    if list and list.ScrollTo then list:ScrollTo(index) end
    onQuestRowClick(items[index])
    return true
end



local function guideSelected()
    local questID = QuestPanel.questsPage.selected
    if not questID then return false end
    return searchAction(questID)
end
QuestPanel.GuideSelected = guideSelected



local function onQuestRowDoubleClick(item)
    if type(item) ~= "table" or item.kind ~= "quest" then return end
    if QuestPanel.questsPage.selected ~= item.questID then onQuestRowClick(item) end
    guideSelected()
end


local function onQuestRowRightClick(item, _, row)
    openRowMenu(row, item, false)
end



local function firstLevelingStep()
    local items, _, info = levelingItems()
    if not (info and info.ready) then return nil end
    for _, item in ipairs(items) do
        if item.kind == "quest" and item.section == "steps" then return item end
    end
    return nil
end

local function guideToFirstStep()
    local item = QuestPanel.questsPage.firstStep
    if not item then return false end
    if item.action then return item.action() end
    return goTo(item.questID, "giver", 1)
end




local function paintNearby()
    local page = QuestPanel.questsPage
    local text = page.NearbyText
    if not text then return false end
    local batch = FGPS.QuestBatch
    local cur = batch and batch.Current and batch.Current() or nil
    local buttons = page.nearbyButtons


    local shown = cur ~= nil and cur.status ~= "dismissed"
    if not shown then
        text:SetText("")
        setButtonEnabled(buttons.accept, false)
        page.nearbyLines = 0
        return false
    end
    local lines, painted = cur.lines or {}, {}
    for i, line in ipairs(lines) do
        local stop = cur.stops and cur.stops[i]
        painted[i] = (stop and stop.unknownQuest) and Look().Tint(line, "grey") or line
    end
    text:SetText(table.concat(painted, "\n"))

    page.nearbyLines = math.max(1, #lines)
    setButtonEnabled(buttons.accept, cur.stops ~= nil and #cur.stops > 0)
    return true
end




function QuestPanel.OpenNearbyMenu(owner)
    local Menus = FGPS.UI.Menus
    local batch = FGPS.QuestBatch
    local nearby = QuestPanel.questsPage.Nearby
    if not (Menus and Menus.OpenRowMenu and batch and nearby and nearby:IsShown()) then return nil end
    local function noStops()
        local cur = batch.Current and batch.Current() or nil
        return not (cur and cur.status ~= "dismissed" and cur.stops and #cur.stops > 0)
    end
    return Menus.OpenRowMenu(owner, { title = L["Quests to Pick Up Nearby"], entries = {
        { label = L["Dismiss"], onClick = function() if batch.Dismiss then batch.Dismiss() end end },
        { label = L["Drop Last Stop"], onClick = function() if batch.DropLast then batch.DropLast() end end,
          disabled = noStops, destructive = true },
    } })
end

function QuestPanel.BatchCardText()
    local text = QuestPanel.questsPage.NearbyText
    return text and text:GetText() or ""
end


local function paintEmpty()
    local page = QuestPanel.questsPage
    if logHasCollapsedHeader() then


        page.Heading:SetText(L["Your quest log shows no quests"])
        page.EmptyLine:SetText(L["Open its collapsed headers to see them."])
        page.firstStep = nil
    else
        page.Heading:SetText(L["Your quest log is empty"])
        page.EmptyLine:SetText(L["The quests you take show here, each with its next step."])
        page.firstStep = firstLevelingStep()
    end
    local item = page.firstStep
    local where = page.WhereToBegin
    if not item then
        where.Row.entry = nil
        where:Hide()
        return false
    end
    local width = pageSize(page.frame)
    item.next = item.zone or ""
    paintQuestRow(where.Row, item, width)
    where:Show()
    return true
end


function QuestsPage.build(frame)
    local page = QuestPanel.questsPage
    local look = Look()
    local tokens = look.TOKENS
    local F = Frames()
    page.frame = frame
    local width = pageSize(frame)

    page.Search = look.SearchBox(frame, {
        width = width, height = QP_SEARCH, maxLetters = 80, placeholder = L["Find a quest"],

        onChanged = function(_, text, userInput)
            if userInput then QuestPanel:ScheduleSearch(text) end
        end,




        onEnter = function(box, text)
            text = text or ""
            if QuestPanel.questsPage.selected and text == (QuestPanel.query or "") then
                if guideSelected() == false and box and box.ClearFocus then box:ClearFocus() end
            else
                QuestPanel:RunSearch(text)
            end
        end,
    })
    page.Search:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    page.Search:HookScript("OnEnter", function(self)
        Look().Tooltip(self, L["Find a quest"], L["Zone, level, level band, or a quest name you have seen"])
    end)
    page.Search:HookScript("OnLeave", hideTip)

    page.Search:SetScript("OnArrowPressed", function(_, key)
        if key == "UP" then QuestPanel:MovePick(-1) elseif key == "DOWN" then QuestPanel:MovePick(1) end
    end)

    page.Status = pageText(frame, "pageSub", "inkGrey")
    if page.Status.SetWordWrap then page.Status:SetWordWrap(true) end
    if page.Status.SetJustifyV then page.Status:SetJustifyV("TOP") end
    page.Status:SetHeight(QP_STATUS)

    page.Lookup = makeButton(frame, "", function() QuestPanel:LookupNextName() end, QP_LOOKUP, QP_BUTTON)
    page.Lookup:SetScript("OnEnter", function(self)
        Look().Tooltip(self, self:GetText(),
            L["This asks the server for a quest's name in Forever's own wording, from a small budget that is yours to spend."])
    end)
    page.Lookup:SetScript("OnLeave", hideTip)
    page.Lookup:Hide()


    local empty = CreateFrame("Frame", nil, frame)
    page.Empty = empty
    page.Heading = pageText(empty, "pageHeading", "ink")
    page.Heading:SetPoint("TOPLEFT", empty, "TOPLEFT", 0, 0)
    page.Heading:SetPoint("TOPRIGHT", empty, "TOPRIGHT", 0, 0)
    page.Heading:SetHeight(PAGE_HEADING)
    page.EmptyLine = pageText(empty, "pageSub", "inkGrey")
    page.EmptyLine:SetPoint("TOPLEFT", empty, "TOPLEFT", 0, -PAGE_HEADING)
    page.EmptyLine:SetPoint("TOPRIGHT", empty, "TOPRIGHT", 0, -PAGE_HEADING)
    page.EmptyLine:SetHeight(PAGE_SUB)
    local y = PAGE_HEADING + PAGE_SUB + tokens.gap
    if pageHas(BREAK_FILE, "a gap stands for the ornament over Where to Begin", "quests") then
        page.EmptyBreak = empty:CreateTexture(nil, "ARTWORK")
        page.EmptyBreak:SetTexture(BREAK_FILE)
        page.EmptyBreak:SetPoint("TOPLEFT", empty, "TOPLEFT", 0, -y)
        page.EmptyBreak:SetPoint("TOPRIGHT", empty, "TOPRIGHT", 0, -y)
        page.EmptyBreak:SetHeight(PAGE_BREAK)
        y = y + PAGE_BREAK
    else
        y = y + tokens.gapWide
    end
    local where = CreateFrame("Frame", nil, empty)
    where:SetPoint("TOPLEFT", empty, "TOPLEFT", 0, -y)
    where:SetPoint("TOPRIGHT", empty, "TOPRIGHT", 0, -y)
    page.WhereToBegin = where
    where.Head = pageText(where, "pageSub", "rubric")
    where.Head:SetText(L["Where to Begin"])
    where.Head:SetPoint("TOPLEFT", where, "TOPLEFT", 0, 0)
    where.Head:SetHeight(PAGE_RUBRIC)
    local stepRow = CreateFrame("Button", nil, where)
    stepRow:SetPoint("TOPLEFT", where, "TOPLEFT", 0, -PAGE_RUBRIC)
    stepRow:SetPoint("TOPRIGHT", where, "TOPRIGHT", 0, -PAGE_RUBRIC)
    stepRow:SetSize(width, tokens.rowQuest)
    dressQuestRow(stepRow)
    stepRow:SetScript("OnEnter", function(self) stepTooltip(self, self.entry) end)
    stepRow:SetScript("OnLeave", hideTip)


    stepRow:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    stepRow:SetScript("OnClick", function(self, button)
        if button == "RightButton" then openRowMenu(self, self.entry, true) end
    end)
    stepRow:SetScript("OnDoubleClick", function(self, button)
        if button == "RightButton" then openRowMenu(self, self.entry, true) else guideToFirstStep() end
    end)
    where.Row = stepRow
    local ruled = PAGE_RUBRIC + tokens.rowQuest
    where.Note = pageText(where, "pageSub", "inkGrey")
    where.Note:SetText(L["The first step of the Optimized Leveling order for this character."])
    where.Note:SetPoint("TOPLEFT", where, "TOPLEFT", 0, -ruled)
    where.Note:SetPoint("TOPRIGHT", where, "TOPRIGHT", 0, -ruled)
    where.Note:SetHeight(PAGE_SUB)
    ruled = ruled + PAGE_SUB + tokens.gap
    where.GuideMe = makeButton(where, L["Guide Me"], guideToFirstStep, 110, QP_BUTTON)
    where.GuideMe:SetPoint("TOPLEFT", where, "TOPLEFT", 0, -ruled)
    where.OpenLeveling = makeButton(where, L["Open Optimized Leveling"], function() QuestPanel.OpenLevelingPage() end, 190, QP_BUTTON)
    where.OpenLeveling:SetPoint("LEFT", where.GuideMe, "RIGHT", tokens.gapWide, 0)
    where:SetHeight(ruled + QP_BUTTON)
    page.emptyHeight = y + ruled + QP_BUTTON
    page.emptyHeadHeight = PAGE_HEADING + PAGE_SUB
    empty:Hide()


    local nearby = CreateFrame("Frame", nil, frame)
    page.Nearby = nearby
    nearby:EnableMouse(true)
    nearby:SetScript("OnEnter", function(self)
        local batch = FGPS.QuestBatch
        local cur = batch and batch.Current and batch.Current()
        local numbers
        for _, stop in ipairs(cur and cur.status ~= "dismissed" and cur.stops or {}) do
            if stop.unknownQuest then
                local number = format(L["Quest %d"], stop.unknownQuest)
                numbers = numbers and format(L["%s, %s"], numbers, number) or number
            end
        end
        if numbers then Look().Tooltip(self, L["Unknown quest"], numbers) end
    end)
    nearby:SetScript("OnLeave", hideTip)
    nearby:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then QuestPanel.OpenNearbyMenu(self) end
    end)
    nearby.Head = pageText(nearby, "pageSub", "rubric")
    nearby.Head:SetText(L["Quests to Pick Up Nearby"])
    nearby.Head:SetPoint("TOPLEFT", nearby, "TOPLEFT", 0, 0)
    nearby.Head:SetHeight(PAGE_RUBRIC)
    page.NearbyText = pageText(nearby, "pageSub", "ink")
    if page.NearbyText.SetWordWrap then page.NearbyText:SetWordWrap(true) end
    if page.NearbyText.SetJustifyV then page.NearbyText:SetJustifyV("TOP") end
    page.NearbyText:SetPoint("TOPLEFT", nearby, "TOPLEFT", 0, -PAGE_RUBRIC)
    page.NearbyText:SetPoint("TOPRIGHT", nearby, "TOPRIGHT", 0, -PAGE_RUBRIC)
    local function press(method)
        return function()
            local batch = FGPS.QuestBatch
            if batch and batch[method] then batch[method]() end
        end
    end




    local addToRoute = press("Accept")
    local accept = makeButton(nearby, L["Add to Route"], function(self, button)
        if button == "RightButton" then QuestPanel.OpenNearbyMenu(self) else addToRoute() end
    end, 110, QP_BUTTON)
    accept:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    accept:SetPoint("BOTTOMLEFT", nearby, "BOTTOMLEFT", 0, 0)
    accept:SetScript("OnEnter", function(self)
        Look().Tooltip(self, L["Add to Route"],
            L["Adds the places where these quests start to your route as stops, in this order. The route starts when you press Start."],
            L["Right-click for options"])
    end)
    accept:SetScript("OnLeave", hideTip)
    page.nearbyButtons = { accept = accept }
    QuestPanel.batchButtons = page.nearbyButtons
    nearby:Hide()



    if F and F.CreateScrollList then
        local ok, list = pcall(F.CreateScrollList, frame, tokens.rowQuest, renderQuestRow, {
            width = width, onClick = onQuestRowClick, onDoubleClick = onQuestRowDoubleClick,
            onRightClick = onQuestRowRightClick, onEnter = onQuestRowEnter, onLeave = onPageRowLeave,
        })
        if ok and type(list) == "table" then
            page.list = list
        else
            FGPS.Log:Error("Frames.CreateScrollList failed: %s", tostring(list))
        end
    end
    QuestPanel.list = page.list



    frame:HookScript("OnHide", function(self)
        local Tome = FGPS.UI.Tome
        local win = Tome and Tome.window
        if self:IsShown() and win and win:IsShown() then return end
        QuestPanel:OnPageHidden()
    end)
end


layoutQuestsPage = function()
    local page = QuestPanel.questsPage
    local frame = page.frame
    if not frame then return end
    local tokens = Look().TOKENS
    local width, height = pageSize(frame)
    local y = QP_SEARCH + tokens.gap

    QuestPanel:UpdateLookupButton()
    local lookup = page.Lookup:IsShown()
    local status = page.status or ""
    page.Status:SetText(status)
    page.Status:ClearAllPoints()
    page.Status:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
    page.Status:SetPoint("TOPRIGHT", frame, "TOPRIGHT", lookup and -(QP_LOOKUP + tokens.gapWide) or 0, -y)
    page.Lookup:ClearAllPoints()
    page.Lookup:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -y)
    local statusShown = status ~= "" or lookup
    page.Status:SetShown(status ~= "")
    if statusShown then y = y + QP_STATUS + tokens.gap end

    page.Empty:ClearAllPoints()
    if page.empty then
        local where = paintEmpty()
        page.Empty:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
        page.Empty:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -y)
        local tall = where and page.emptyHeight or page.emptyHeadHeight
        page.Empty:SetSize(width, tall)
        page.Empty:Show()
        y = y + tall + tokens.gapWide
    else
        page.firstStep = nil
        page.Empty:Hide()
    end

    page.Nearby:ClearAllPoints()
    if paintNearby() then
        local tall = PAGE_RUBRIC + page.nearbyLines * PAGE_SUB + tokens.gap + QP_BUTTON
        page.NearbyText:SetHeight(page.nearbyLines * PAGE_SUB)
        page.Nearby:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
        page.Nearby:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -y)
        page.Nearby:SetSize(width, tall)
        page.Nearby:Show()
        y = y + tall + tokens.gapWide
    else
        page.Nearby:Hide()
    end

    local items = QuestPanel.items
    local list = page.list
    if not list then
        page.rows = {}
        return
    end
    local selected
    for i, item in ipairs(items) do
        if item.questID == page.selected then selected = i break end
    end
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
    list:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -y)
    list:SetSize(width, math.max(tokens.rowQuest, height - y))
    list.selected = selected
    list:SetItems(items)
    list:SetShown(#items > 0)
    local rows = {}
    for _, row in ipairs(list.rows or {}) do
        if row:IsShown() and row.entry then rows[#rows + 1] = row end
    end
    page.rows = rows
end


repaintQuestRows = function()
    local list = QuestPanel.questsPage.list
    if list and list.Refresh then list:Refresh() end
end





renderQuestsPage = function(items)
    local page = QuestPanel.questsPage
    if not page.frame then return end
    if items then
        page.empty = false
    elseif searching() then
        items, page.status = searchItems()
        page.empty = false
    else
        items, page.status, page.empty = logItems()
    end
    QuestPanel.items = items
    if page.selected then
        local still = false
        for _, item in ipairs(items) do
            if item.questID == page.selected then still = true break end
        end
        if not still then page.selected = nil end
    end
    layoutQuestsPage()
    if searching() then QuestPanel:SweepTitles() end
    refreshQuestsFooter()
end



pickQuest = function(questID)
    local page = QuestPanel.questsPage
    page.selected = questID
    if searching() then QuestPanel:SetFocus(questID) end
    layoutQuestsPage()
    local list = page.list
    if list and list.selected and list.ScrollTo then list:ScrollTo(list.selected) end
    refreshQuestsFooter()
end




function QuestsPage.show(_, opts)
    opts = type(opts) == "table" and opts or {}
    local page = QuestPanel.questsPage
    if type(opts.query) == "string" then
        newQuery(Util.Trim(opts.query))
    elseif opts.tab == "log" then
        newQuery("")
    end
    if page.Search and (page.Search:GetText() or "") ~= QuestPanel.query then page.Search:SetText(QuestPanel.query) end
    page.live = true
    listen(true)


    if FGPS.QuestBatch and FGPS.QuestBatch.Suggest then FGPS.QuestBatch.Suggest() end
    QuestPanel:Refresh()
    if opts.questID then pickQuest(opts.questID) end
    if opts.tab == "search" and page.Search then page.Search:SetFocus() end
end



function QuestPanel.QuestsFooterButtons()
    return {
        { label = L["Guide Me"], onClick = guideSelected, enabled = QuestPanel.questsPage.selected ~= nil,
          why = L["Pick a quest first"] },
    }
end

function QuestsPage.footer(win)
    win:SetFooterButtons(QuestPanel.QuestsFooterButtons())
    if win.FooterNote then win.FooterNote:SetText("") end
end





function QuestPanel:OnPageHidden()
    local page = self.questsPage
    if not page.live then return end
    page.live = false
    if FGPS.QuestBatch and FGPS.QuestBatch.Cancel then FGPS.QuestBatch.Cancel() end
    self:SetFocus(nil)
    listen(false)
end






function QuestPanel:Show(opts)
    opts = type(opts) == "table" and opts or {}
    if opts.tab == "leveling" then return QuestPanel.OpenLevelingPage() end
    if questHelpOffSaid() then return false end
    local Tome = FGPS.UI.Tome
    if Tome and Tome.pages and Tome.pages.quests and Tome:Open("quests", opts) then return true end
    FGPS:Print(L["The Quests page is unavailable."])
    return false
end






function QuestPanel:ShowQuest(questID)
    questID = tonumber(questID)
    if not questID or questID <= 0 then
        self:Show({ tab = "log" })
        return false
    end



    local title, known = titleFor(questID)
    local searched = known and not isAccepted(questID)
    if not self:Show(searched and { query = title } or { tab = "log" }) then return false end
    local function pickIfListed()
        for _, item in ipairs(self.items) do
            if item.questID == questID then
                pickQuest(questID)
                return true
            end
        end
        return false
    end
    if pickIfListed() then return true end


    local page = self.questsPage
    local function list(query)
        self:RunSearch(query)
        if page.Search and (page.Search:GetText() or "") ~= self.query then page.Search:SetText(self.query) end
    end
    if not searched and known then
        list(Util.Trim(title))
        if pickIfListed() then return true end
    end
    if self.query ~= "" then list("") end
    return false
end


function QuestPanel:IsShown()
    local Tome = FGPS.UI.Tome
    return Tome ~= nil and Tome.Current ~= nil and Tome:Current() == "quests"
end


function QuestPanel:Hide()
    if not self:IsShown() then return false end
    FGPS.UI.Tome.window:Hide()
    self:OnPageHidden()
    return true
end

function QuestPanel:Toggle()
    if self:IsShown() then
        FGPS.UI.Tome:Close()
        return false
    end
    return self:Show()
end




local function slash(args)
    local text = Util.Trim(args or "")
    local word = Util.Lower(text)
    if word == "about" or word == "stats" then
        QuestPanel.About()
        return
    end
    if text == "" then
        QuestPanel:Show({ tab = "log" })
        return
    end
    QuestPanel:Show({ query = text })
end




function QuestPanel.LevelingSlash(args)
    if questHelpOffSaid() then return end
    local word = Util.Lower(Util.Trim(args or ""))
    local Leveling = FGPS.Leveling
    if Leveling and word == "skip" then
        local questID = Leveling.Skip()
        if questID then FGPS:Print(L["Optimized Leveling: skipped %s."], (Leveling.Title(questID))) end
    elseif Leveling and word == "reset" then
        Leveling.Reset()
        FGPS:Print(L["Optimized Leveling: every skipped quest is back in the order."])
    elseif word == "start" and FGPS.LevelingAuto then
        FGPS.LevelingAuto.Start()
    elseif word == "stop" and FGPS.LevelingAuto then
        if not FGPS.LevelingAuto.Stop() then FGPS:Print(L["Optimized Leveling: stopped following the order."]) end
    end
    QuestPanel:Show({ tab = "leveling" })
end

function QuestPanel:Init()
    if self.eventsBound then return end
    self.eventsBound = true
    local Events = FGPS.Events


    Events:Register("SETTINGS_CHANGED", function(_, key)
        local batchKey = key == "quests.batchRadius" or key == "quests.leveling" or key == "*"
            or (type(key) == "string" and (key:sub(1, 8) == "routing." or key:sub(1, 11) == "transports."))
        if batchKey and FGPS.QuestBatch and FGPS.QuestBatch.Suggest and QuestPanel:IsShown() then
            FGPS.QuestBatch.Suggest()
        end
        if (key == "quests.enabled" or key == "*") and FGPS.UI.Tome and FGPS.UI.Tome.RefreshPages then
            FGPS.UI.Tome.RefreshPages()
        end
        if key == "units" or key == "preset" or key == "accessibility.colorScheme" or key == "*"
            or (type(key) == "string" and key:sub(1, 7) == "quests.") then
            if QuestPanel:IsShown() then QuestPanel:Refresh() end
            QuestPanel.RefreshLevelingPage()
        end
    end, self)

    Events:Register("QUEST_BATCH", function()
        if QuestPanel.questsPage.frame then layoutQuestsPage() end
    end, self)

    Events:Register("LEVELING_UPDATED", onLevelingUpdated, self)
    Events:Register("LEVELING_AUTO", onLevelingUpdated, self)

    QuestPanel.HookTrackers()
    if Events.RegisterWoW then
        Events:RegisterWoW("ADDON_LOADED", function()
            local hooks = QuestPanel.HookTrackers()
            if hooks.questie and hooks.native and Events.UnregisterWoW then Events:UnregisterWoW("ADDON_LOADED", self) end
        end, self)
    end


    local Tome = FGPS.UI.Tome
    if Tome and Tome.RegisterPage then
        local icon = pageHas(QuestPanel.QUESTS_PAGE_ICON, "the Quests tab has no icon", "quests")
            and QuestPanel.QUESTS_PAGE_ICON or nil
        Tome.RegisterPage("quests", {
            label = L["Quests"], icon = icon, order = 2,
            build = QuestsPage.build, show = QuestsPage.show, footer = QuestsPage.footer,
            available = QuestPanel.QuestHelpOn,
        })
        Tome.RegisterPage("leveling", {
            label = L["Optimized Leveling"], icon = QuestPanel.LEVELING_PAGE_ICON, order = 3,
            build = LevelingPage.build, show = LevelingPage.show, footer = LevelingPage.footer,
            available = QuestPanel.QuestHelpOn,
        })
    end
    FGPS.Slash.Register("quests", slash,
        L["Quest help: quests [zone|level|name] | quests about"])
    FGPS.Slash.Register("leveling", QuestPanel.LevelingSlash,
        L["Optimized Leveling: the next steps for this character; leveling skip | leveling reset | leveling start | leveling stop"])
end
