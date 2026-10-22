

































local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local type, ipairs, pairs, tostring, tonumber, format = type, ipairs, pairs, tostring, tonumber, string.format

local QuestPanel = {
    window = nil,
    list = nil,
    tab = "log",
    query = "",
    items = {},
    rows = {},
    selectedIndex = 0,
    expanded = nil,
    focus = nil,
    searchGeneration = 0,
    pendingQuery = nil,
}
FGPS.UI.QuestPanel = QuestPanel

local WINDOW_KEY = "quests"
local ROW_HEIGHT = 22
local DEBOUNCE_SECONDS = 0.15

local TABS = { "log", "search" }
local TAB_LABELS = { log = "My quests", search = "Find a quest" }



QuestPanel.WIDTH, QuestPanel.HEIGHT = 480, 600
QuestPanel.GAP = 8
local TAB_HEIGHT, EDIT_HEIGHT, BUTTON_HEIGHT = 24, 24, 24
local CARD_HEADER, CARD_LINE = 16, 13
local STATUS_HEIGHT = 26
local LIST_BOTTOM = BUTTON_HEIGHT + 6 + STATUS_HEIGHT + 4




local function Frames()
    return FGPS.UI.Frames
end

local function Look()
    return FGPS.UI.Look
end

local function settings()
    return FGPS.DB and FGPS.DB.settings or nil
end



local function makeLabel(parent, role, text, color)
    local look = Look()
    local fs = parent:CreateFontString(nil, "OVERLAY", look.Font(role))
    fs:SetText(text or "")
    if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
    if color then fs:SetTextColor(look.Color(color)) end
    return fs
end


local function makeButton(parent, text, onClick, width, height)
    local button = Look().Button(parent, text, width or 90, height or 22)
    if onClick then button:SetScript("OnClick", onClick) end
    return button
end

local function setButtonText(button, text)
    if button.SetLabel then button:SetLabel(text) else button:SetText(text) end
end

local function setButtonOnClick(button, fn)
    if button.SetOnClick then button:SetOnClick(fn) else button:SetScript("OnClick", fn) end
end

local function setButtonEnabled(button, enabled)
    if button.SetEnabledState then button:SetEnabledState(enabled) elseif enabled then button:Enable() else button:Disable() end
end





local function questData()
    local QuestData = FGPS.QuestData
    if QuestData and QuestData.Available and QuestData.Available() then return QuestData end
    return nil
end









local MARK_WORDS = { [0] = "may have moved", [1] = "not checked in game", [2] = "from the game" }
function QuestPanel.MarkFlag(mark)
    return Look().Tint(L[MARK_WORDS[mark] or MARK_WORDS[0]], "grey")
end



local function distanceText(yards)
    if type(yards) ~= "number" then return L["another continent"] end
    local s = settings()
    local text = Util.FormatDistance(yards, s and s.units or "yards")
    if text == "" then return "" end
    return format(L["%s away"], text)
end
QuestPanel.DistanceText = distanceText


local function withMark(right, mark)
    local flag = QuestPanel.MarkFlag(mark)
    if not right or right == "" then return flag end
    return right .. " \194\183 " .. flag
end


local function sentence(text)
    return (text:gsub("^%l", string.upper))
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
    return format(L["Quest %d"], questID), false
end
QuestPanel.TitleFor = titleFor




local function withDetails(title, details)
    if not details or details == "" then return title end
    return title .. L[" - "] .. Look().Tint(details, "later")
end



local function searchLabel(row)
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
    return withDetails((titleFor(row.questID)), table.concat(parts, L[" - "]))
end
QuestPanel.SearchLabel = searchLabel






local function yardsTo(QuestData, pos, at)
    if not at then return nil end
    return QuestData.DistanceTo(pos, at.inst, at.x, at.y)
end





function QuestPanel.StagesFor(questID)
    local QuestData = questData()
    if not QuestData then return {} end
    local out = {}
    local pos = QuestData.PlayerPos()
    local start = QuestData.Start(questID)
    if start then
        local at = QuestData.ReachedAt(start)
        out[#out + 1] = {
            target = "giver", index = 1, label = L["Where it starts"], position = start,
            yards = yardsTo(QuestData, pos, at), routable = at ~= nil,
            interior = start.interior,
        }
    end




    local unplacedListed = false
    for _, objective in ipairs(QuestData.Objectives(questID)) do
        if objective.provided then
            out[#out + 1] = { target = "none", label = sentence(format(L["%s: the giver hands it to you"], objective.kindName)) }
        elseif #objective.areas == 0 then
            unplacedListed = true
            out[#out + 1] = { target = "none", unplaced = true, label = sentence(format(L["%s: objective place not known"], objective.kindName)) }
        end
    end



    if not unplacedListed and QuestData.IsPartial and QuestData.IsPartial(questID) then
        out[#out + 1] = { target = "none", unplaced = true, label = sentence(L["objective place not known"]) }
    end


    for index, area in ipairs(QuestData.AreasFor(questID)) do
        local at = QuestData.ReachedAt(area)
        out[#out + 1] = {
            target = "objective", index = index, area = area, interior = area.interior,
            label = sentence(QuestData.AreaLabel(area)),
            yards = yardsTo(QuestData, pos, at), routable = at ~= nil,
        }
    end
    local turnIn = QuestData.TurnIn(questID)
    if turnIn then
        local at = QuestData.ReachedAt(turnIn)
        out[#out + 1] = {
            target = "turnin", index = 1, label = L["Where it is handed in"], position = turnIn,
            yards = yardsTo(QuestData, pos, at), routable = at ~= nil,
            interior = turnIn.interior,
        }
    end
    return out
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
        FGPS:Print(L["%s: %s"], (titleFor(questID)), text)
        return false
    end

    local Search = FGPS.UI.Search
    if Search and Search.GoTo then
        Search.GoTo(dest, "start")
    else
        local Navigator = FGPS.Navigator
        if not (Navigator and Navigator.SetDestination) then
            FGPS:Print(L["Navigation is not available right now."])
            return false
        end
        Navigator:SetDestination(dest, { start = true })
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





local function stageItems(questID)
    local items = {}
    for _, stage in ipairs(QuestPanel.StagesFor(questID)) do
        local label = "    " .. stage.label
        if stage.interior then
            label = label .. (stage.routable and L[" (inside; routes to the entrance)"] or L[" (inside; no entrance is known)"])
        end
        local item = { kind = "stage", questID = questID, target = stage.target, index = stage.index,
                       label = label, right = stage.target ~= "none" and distanceText(stage.yards) or "" }
        if stage.target ~= "none" and stage.routable then
            item.actionLabel = L["Go"]
            item.action = function() goTo(questID, stage.target, stage.index) end
        end
        items[#items + 1] = item
    end
    if #items == 0 then
        items[1] = { kind = "note", label = "    " .. L["No bundled record for this quest."] }
    end
    return items
end



local function logItems()
    local Quests = FGPS.Quests
    if not (Quests and Quests.List) then
        return {}, L["Quest lookup is not available right now."]
    end
    local ok, list = pcall(Quests.List)
    if not ok then
        FGPS.Log:Error("Quests.List failed: %s", tostring(list))
        return {}, L["Quest lookup failed; type /cabbie log for details."]
    end
    local QuestData = questData()


    local pos = FGPS.QuestData and FGPS.QuestData.PlayerPos and FGPS.QuestData.PlayerPos() or nil
    local quests = {}
    for logIndex, q in ipairs(list or {}) do


        local title = q.title or (titleFor(q.questID))
        local bundled = q.bundled
        local level = tonumber(bundled and bundled.level or q.level)
        local head = (level and level > 0) and format(L["[%d] %s"], level, title) or title
        local left
        if q.complete then
            left = L["Ready to turn in"]
        elseif type(q.objectiveText) == "string" and q.objectiveText ~= "" then
            left = q.objectiveText
        end



        local okStep, step, why = pcall(Quests.NextStep, q.questID)
        if not okStep then step, why = nil, nil end
        local yards, right = nil, ""
        if step and pos and FGPS.QuestData.DistanceTo then
            yards = FGPS.QuestData.DistanceTo(pos, step.inst, step.x, step.y)
            right = distanceText(yards)
        elseif not step and why == "objective_unknown" then




            right = L["objective place not known"]
        elseif not step then


            right = L["place not known"]
        end
        if bundled then right = withMark(right, bundled.mark) end
        local open = QuestPanel.expanded == q.questID
        local item = {
            kind = "quest", questID = q.questID, level = level,
            label = (open and L["- "] or L["+ "]) .. withDetails(head, left), right = right,
            quest = q, bundled = bundled, yards = yards, step = step, logIndex = logIndex,
        }
        if step then
            item.actionLabel = L["Go"]
            item.action = function() goTo(q.questID, "next") end
        end
        quests[#quests + 1] = item
    end


    local function rank(item)
        if item.yards then return 0 end
        if item.step then return 1 end
        return 2
    end
    table.sort(quests, function(a, b)
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then return ra < rb end
        if a.yards and b.yards and a.yards ~= b.yards then return a.yards < b.yards end
        return a.logIndex < b.logIndex
    end)
    local items = {}
    for _, item in ipairs(quests) do
        items[#items + 1] = item
        if QuestPanel.expanded == item.questID then
            for _, stage in ipairs(stageItems(item.questID)) do items[#items + 1] = stage end
        end
    end
    local status
    if #items == 0 then
        status = L["Your quest log is empty."]
    elseif not QuestData then
        status = L["Quest data is not installed in this copy of Cabbie; only what the client reports is shown."]
    else
        status = format(L["%d quests accepted. Select one to see where it starts, what it wants and where it is handed in."], #list)
    end
    return items, status
end

local function searchItems()
    local QuestData = questData()
    if not QuestData then
        return {}, L["Quest data is not installed in this copy of Cabbie."]
    end
    local rows, status = QuestData.Search(QuestPanel.query)
    QuestPanel.rows = rows
    local items = {}
    for _, row in ipairs(rows) do
        local open = QuestPanel.expanded == row.questID
        items[#items + 1] = {
            kind = "quest", questID = row.questID, row = row, level = row.level,
            label = (open and L["- "] or L["+ "]) .. searchLabel(row),
            right = withMark(distanceText(row.yards), row.mark),
        }
        if QuestPanel.expanded == row.questID then
            for _, stage in ipairs(stageItems(row.questID)) do items[#items + 1] = stage end
        end
    end
    if #rows == 0 and type(status) == "string" and status ~= "" then
        status = status .. " " .. L["Or open Search for a town, inn, or flight master."]
    end
    return items, status
end




function QuestPanel:SweepTitles()
    local QuestData = questData()
    if not QuestData or self.tab ~= "search" then return end
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
            item.label = (self.expanded == item.questID and L["- "] or L["+ "]) .. searchLabel(item.row)
        end
    end
    if self.list and self.list.Refresh then self.list:Refresh() end
end




function QuestPanel:UpdateLookupButton()
    local window = self.window
    if not window or not window.fgpsLookup then return end
    local QuestData = questData()
    local button = window.fgpsLookup
    if not QuestData or self.tab ~= "search" then
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
    setButtonText(button, format(L["Look up %d names (%d left)"], want, left))
    button:Show()
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
        FGPS:Print(L["Cabbie cannot look a name up right now (%s)."], tostring(why))
    end
    self:UpdateLookupButton()
    return ok
end






local function paintGlow(row)
    row.fgpsGlow:SetShown(row.fgpsSelected == true or row.fgpsHover == true)
end

local function ensureRowWidgets(row)
    if row.fgpsReady then return end
    row.fgpsReady = true
    if row.Bg and row.Bg.SetAlpha then row.Bg:SetAlpha(0) end
    row.fgpsGlow = row:CreateTexture(nil, "BACKGROUND")
    row.fgpsGlow:SetAllPoints(row)
    Look().Highlight(row.fgpsGlow)
    row.fgpsGlow:Hide()
    if row.HookScript then
        row:HookScript("OnEnter", paintGlow)
        row:HookScript("OnLeave", paintGlow)
    end
    row.text = row.Text or makeLabel(row, "line", "")
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row, "LEFT", 6, 0)


    if row.text.SetWordWrap then row.text:SetWordWrap(false) end
    if row.text.SetMaxLines then row.text:SetMaxLines(1) end
    row.right = makeLabel(row, "rowSmall", "")
    row.right:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    if row.right.SetJustifyH then row.right:SetJustifyH("RIGHT") end
    row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
    row.action = makeButton(row, "", nil, 48, 20)
    row.action:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.action:Hide()
end




local function rowLook(item)
    local look = Look()
    if item.kind == "header" then return "listTitle", look.Color("header") end
    if item.kind == "quest" then return "title", look.QuestColor(item.level) end
    if item.kind == "stage" and item.target ~= "none" then return "line", look.Color("later") end
    return "line", look.Color("grey")
end

function QuestPanel.RenderRow(row, item, index)
    ensureRowWidgets(row)
    local look = Look()
    row.item, row.index = item, index
    local role, r, g, b = rowLook(item)
    row.text:SetFontObject(look.Font(role))
    row.text:SetText(item.label or "")
    row.text:SetTextColor(r, g, b)
    row.right:SetFontObject(look.Font("rowSmall"))
    row.right:SetTextColor(look.Color("later"))

    if row.Bg and row.Bg.SetAlpha then row.Bg:SetAlpha(0) end
    paintGlow(row)


    row.right:ClearAllPoints()
    if item.actionLabel then
        setButtonText(row.action, item.actionLabel)
        setButtonOnClick(row.action, function() if item.action then item.action(item) end end)
        row.action:Show()
        row.right:SetPoint("RIGHT", row.action, "LEFT", -6, 0)
    else
        row.action:Hide()
        row.right:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    end
    row.right:SetText(item.right or "")
end

local function onRowClick(item, index)
    if type(item) ~= "table" then return end
    QuestPanel.selectedIndex = index
    if item.kind == "quest" then

        if QuestPanel.expanded == item.questID then
            QuestPanel.expanded = nil
        else
            QuestPanel.expanded = item.questID
        end


        if QuestPanel.tab == "search" then QuestPanel:SetFocus(QuestPanel.expanded) end
        QuestPanel:Refresh()
    end
    QuestPanel:UpdateButtons()
end





function QuestPanel:SelectedQuest()
    local item = self.items[self.selectedIndex]
    if type(item) == "table" and item.questID then return item.questID end
    return nil
end

function QuestPanel:UpdateButtons()
    local window = self.window
    if not window or not window.fgpsButtons then return end
    local questID = self:SelectedQuest()
    local QuestData = questData()
    local haveStart, haveObjective, haveTurnIn = false, false, false
    if questID and QuestData then
        haveStart = QuestData.Routable(QuestData.Start(questID))
        haveTurnIn = QuestData.Routable(QuestData.TurnIn(questID))
        for _, area in ipairs(QuestData.AreasFor(questID)) do
            if QuestData.Routable(area) then haveObjective = true break end
        end
    end



    local accepted = isAccepted(questID)
    local first = window.fgpsButtons.giver
    if accepted then
        haveObjective = QuestPanel.OpenObjectiveIndex(questID) ~= nil
        local Quests = FGPS.Quests
        local ok, step = pcall(Quests.NextStep, questID)
        setButtonText(first, L["Go to the next step"])
        setButtonEnabled(first, ok and step ~= nil)
    else
        setButtonText(first, L["Go to the start"])
        setButtonEnabled(first, haveStart)
    end
    setButtonEnabled(window.fgpsButtons.objective, haveObjective)
    setButtonEnabled(window.fgpsButtons.turnin, haveTurnIn)
end

function QuestPanel:Act(target)
    local questID = self:SelectedQuest()
    if not questID then
        FGPS:Print(L["Select a quest first."])
        return false
    end
    local accepted = isAccepted(questID)
    if target == "giver" and accepted then return goTo(questID, "next") end
    if target == "objective" and accepted then

        local index = QuestPanel.OpenObjectiveIndex(questID)
        if not index then
            FGPS:Print(L["%s: %s"], (titleFor(questID)), L["every objective with a known place is done"])
            return false
        end
        return goTo(questID, target, index)
    end
    return goTo(questID, target, 1)
end




function QuestPanel.OpenObjectiveIndex(questID)
    local Quests, QuestData = FGPS.Quests, questData()
    if not (Quests and Quests.OpenAreas and QuestData) then return nil end
    local ok, open = pcall(Quests.OpenAreas, questID)
    if not ok or type(open) ~= "table" then return nil end
    for _, entry in ipairs(open) do
        if QuestData.Routable(entry.area) then return entry.index end
    end
    return nil
end




function QuestPanel:SetItems(items, status)
    self.items = items or {}
    if self.selectedIndex > #self.items then self.selectedIndex = 0 end
    if self.window and self.window.fgpsStatus then self.window.fgpsStatus:SetText(status or "") end
    if self.list and self.list.SetItems then


        if self.list.selected ~= nil or self.selectedIndex > 0 then
            self.list.selected = self.selectedIndex > 0 and self.selectedIndex or nil
        end
        self.list:SetItems(self.items)
    end
    self:UpdateButtons()
end


local function sameRow(a, b)
    return a.kind == b.kind and a.questID == b.questID and a.target == b.target and a.index == b.index
end




local function layout(window)
    if not (window and window.fgpsTabs) then return end
    local content, gap = window.fgpsContent, QuestPanel.GAP
    local y = window.fgpsCard:IsShown() and (window.fgpsCard:GetHeight() + gap) or 0
    local first = window.fgpsTabs[TABS[1]]
    first:ClearAllPoints()
    first:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    window.fgpsLookup:ClearAllPoints()
    window.fgpsLookup:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
    y = y + TAB_HEIGHT + gap
    local edit = window.fgpsEdit
    edit:ClearAllPoints()
    edit:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    edit:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
    if edit:IsShown() then y = y + EDIT_HEIGHT + gap end
    local anchor = window.fgpsListAnchor
    anchor:ClearAllPoints()
    anchor:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    anchor:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, LIST_BOTTOM)
end

local function paintBatch()
    local text = QuestPanel.batchText
    if not text then return end
    local batch = FGPS.QuestBatch
    local cur = batch and batch.Current and batch.Current()
    local buttons = QuestPanel.batchButtons
    local shown = cur ~= nil and cur.status ~= "dismissed"
    local window = QuestPanel.window
    if window and window.fgpsCard and window.fgpsCardShown ~= shown then
        window.fgpsCardShown = shown
        window.fgpsCard:SetShown(shown)
        layout(window)
    end
    if not shown then
        text:SetText("")
        if buttons then
            setButtonEnabled(buttons.accept, false)
            setButtonEnabled(buttons.drop, false)
            setButtonEnabled(buttons.dismiss, false)
        end
        return
    end
    text:SetText(table.concat(cur.lines or {}, "\n"))
    if buttons then
        local on = cur.stops and #cur.stops > 0
        setButtonEnabled(buttons.accept, on)
        setButtonEnabled(buttons.drop, on)
        setButtonEnabled(buttons.dismiss, true)
    end
end

function QuestPanel.BatchCardText()
    local text = QuestPanel.batchText
    return text and text:GetText() or ""
end

function QuestPanel:Refresh()
    if not self.window then return end




    local selected = self.items[self.selectedIndex]
    local items, status
    if self.tab == "search" then
        items, status = searchItems()
    else
        items, status = logItems()
    end
    if type(selected) == "table" and selected.questID then
        local exact, quest
        for i, item in ipairs(items or {}) do
            if sameRow(item, selected) then exact = i break end
            if item.kind == "quest" and item.questID == selected.questID then quest = i end
        end

        self.selectedIndex = exact or quest or 0
    end
    if self.selectedIndex == 0 then
        for i, item in ipairs(items or {}) do
            if item.kind == "quest" then self.selectedIndex = i break end
        end
    end
    self:SetItems(items, status)
    paintBatch()
    if self.tab == "search" then
        self:SweepTitles()
    elseif self.window.fgpsLookup then
        self.window.fgpsLookup:Hide()
    end
end

function QuestPanel:RunSearch(text)
    self.query = text or ""
    self.searchGeneration = self.searchGeneration + 1
    self.selectedIndex = 0
    self.expanded = nil
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

function QuestPanel:SetTab(tab)
    if not TAB_LABELS[tab] then return end
    self.tab = tab
    self.selectedIndex = 0
    self.expanded = nil
    local w = self.window
    if w then
        Look().SelectTab(w.fgpsTabs, tab)
        w.fgpsEdit:SetShown(tab == "search")
        layout(w)
    end
    if tab ~= "search" then self:SetFocus(nil) end
    self:Refresh()
end



function QuestPanel:SetFocus(questID)
    self.focus = questID
    local QuestMap = FGPS.UI.QuestMap
    if QuestMap and QuestMap.SetFocus then pcall(QuestMap.SetFocus, questID) end
end




local function buildWindow()
    local F = Frames()
    if not F or not F.CreateWindow then
        FGPS.Log:Error("UI.Frames.CreateWindow is unavailable; the quest window cannot be built")
        return nil
    end
    local ok, window = pcall(F.CreateWindow, WINDOW_KEY, {
        title = L["Cabbie quests"], width = QuestPanel.WIDTH, height = QuestPanel.HEIGHT,
        onClose = function() QuestPanel:OnWindowHidden() end,
        onKey = function(_, key) return QuestPanel:HandleKey(key) end,
    })
    if not ok or type(window) ~= "table" then
        FGPS.Log:Error("Frames.CreateWindow failed: %s", tostring(window))
        return nil
    end
    Look().DressWindow(window)
    local content = window.Content or window
    window.fgpsContent = content



    local lines = ((FGPS.QuestBatch and FGPS.QuestBatch.MAX_STOPS) or 6) + 1
    local card = CreateFrame("Frame", nil, content)
    card:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    card:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    card:SetHeight(CARD_HEADER + 4 + lines * CARD_LINE + 4 + BUTTON_HEIGHT)
    card:Hide()
    window.fgpsCard, window.fgpsCardShown = card, false
    local header = makeLabel(card, "listTitle", L["Quests to pick up nearby"], "header")
    header:SetPoint("TOPLEFT", card, "TOPLEFT", 2, 0)
    header:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
    header:SetHeight(CARD_HEADER)
    window.fgpsCardHeader = header
    local batchText = makeLabel(card, "rowSmall", "")
    batchText:SetPoint("TOPLEFT", card, "TOPLEFT", 2, -(CARD_HEADER + 4))
    batchText:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, -(CARD_HEADER + 4))
    batchText:SetHeight(lines * CARD_LINE)
    if batchText.SetJustifyV then batchText:SetJustifyV("TOP") end
    window.fgpsBatchText = batchText
    local function press(method)
        return function()
            local batch = FGPS.QuestBatch
            if batch and batch[method] then batch[method]() end
        end
    end
    local accept = makeButton(card, L["Accept"], press("Accept"), 80, BUTTON_HEIGHT)
    local drop = makeButton(card, L["Drop last stop"], press("DropLast"), 130, BUTTON_HEIGHT)
    local dismiss = makeButton(card, L["Dismiss"], press("Dismiss"), 80, BUTTON_HEIGHT)
    accept:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 0, 0)
    drop:SetPoint("LEFT", accept, "RIGHT", 6, 0)
    dismiss:SetPoint("LEFT", drop, "RIGHT", 6, 0)

    window.fgpsBatch = { accept = accept, drop = drop, dismiss = dismiss }
    QuestPanel.batchText = batchText
    QuestPanel.batchButtons = window.fgpsBatch


    if F.Tooltip then
        pcall(F.Tooltip, accept, L["Adds the places where these quests start to your route as stops, in this order. The route starts when you press Start."])
        pcall(F.Tooltip, drop, L["Takes the last quest off this list."])
        pcall(F.Tooltip, dismiss, L["Hides this list until you open the window again."])
    end


    window.fgpsTabs = {}
    local previous
    for _, key in ipairs(TABS) do
        local button = Look().Tab(content, L[TAB_LABELS[key]], 110, TAB_HEIGHT)
        button:SetScript("OnClick", function() QuestPanel:SetTab(key) end)
        if previous then button:SetPoint("LEFT", previous, "RIGHT", 2, 0) end
        window.fgpsTabs[key] = button
        previous = button
    end

    local lookup = makeButton(content, "", function() QuestPanel:LookupNextName() end, 190, TAB_HEIGHT)
    lookup:Hide()
    window.fgpsLookup = lookup
    if F.Tooltip then
        pcall(F.Tooltip, lookup, L["This asks the server for a quest's name in Forever's own wording, from a small budget that is yours to spend."])
    end

    local edit = Look().SearchBox(content, {
        width = QuestPanel.WIDTH - 2 * Look().WINDOW_BORDER, height = EDIT_HEIGHT, maxLetters = 60,
        placeholder = L["Zone, level, level band, or a quest name you have seen"],
        onChanged = function(_, text, userInput)
            if userInput == false then return end
            QuestPanel:ScheduleSearch(text or "")
        end,
        onEnter = function(_, text) QuestPanel:RunSearch(text or "") end,
        onEscape = function() QuestPanel:Hide() end,
    })
    window.fgpsEdit = edit

    local listAnchor = CreateFrame("Frame", nil, content)
    window.fgpsListAnchor = listAnchor
    local list
    if F.CreateScrollList then
        local okList, made = pcall(F.CreateScrollList, listAnchor, ROW_HEIGHT, QuestPanel.RenderRow, { onClick = onRowClick })
        if okList and type(made) == "table" then list = made else FGPS.Log:Error("Frames.CreateScrollList failed: %s", tostring(made)) end
    end
    if list and list.SetAllPoints then list:SetAllPoints(listAnchor) end
    Look().DressList(list)
    QuestPanel.list = list

    local status = makeLabel(content, "hint", "")
    status:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 2, BUTTON_HEIGHT + 6)
    status:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -2, BUTTON_HEIGHT + 6)
    status:SetHeight(STATUS_HEIGHT)
    if status.SetWordWrap then status:SetWordWrap(true) end
    if status.SetJustifyV then status:SetJustifyV("BOTTOM") end
    window.fgpsStatus = status

    local specs = {
        { key = "giver", label = "Go to the start", target = "giver" },
        { key = "objective", label = "Go to an objective", target = "objective" },
        { key = "turnin", label = "Go to the turn-in", target = "turnin" },
    }
    window.fgpsButtons = {}
    previous = nil
    for _, spec in ipairs(specs) do
        local button = makeButton(content, L[spec.label], function() QuestPanel:Act(spec.target) end, 146, BUTTON_HEIGHT)
        if previous then button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else button:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0) end
        window.fgpsButtons[spec.key] = button
        previous = button
    end
    if F.ApplySkin then pcall(F.ApplySkin, window) end
    return window
end

function QuestPanel:EnsureWindow()
    if self.window then return self.window end
    self.window = buildWindow()
    if self.window then self:SetTab(self.tab) end
    return self.window
end




function QuestPanel:Select(index)
    if #self.items == 0 then
        self.selectedIndex = 0
        return
    end
    if index < 1 then index = 1 end
    if index > #self.items then index = #self.items end
    self.selectedIndex = index
    if self.list and self.list.SetSelected then self.list:SetSelected(index) end
    if self.list and self.list.ScrollTo then self.list:ScrollTo(index) end
    self:UpdateButtons()
end

local function questEditAcceptsKeys()
    local edit = QuestPanel.window and QuestPanel.window.fgpsEdit
    if not edit then return false end
    if edit.IsShown and not edit:IsShown() then return false end
    if edit.HasFocus and not edit:HasFocus() then return false end
    return true
end

function QuestPanel:HandleKey(key)
    if key == "ENTER" or key == "NUMPADENTER" or key == "TAB" then
        if not questEditAcceptsKeys() then return false end
    end
    if key == "UP" then
        self:Select(self.selectedIndex - 1)
    elseif key == "DOWN" then
        self:Select(self.selectedIndex == 0 and 1 or self.selectedIndex + 1)
    elseif key == "ENTER" or key == "NUMPADENTER" then
        local item = self.items[self.selectedIndex]
        if type(item) == "table" and type(item.action) == "function" then
            item.action(item)
        elseif item then
            onRowClick(item, self.selectedIndex)
        end
    elseif key == "TAB" then
        self:SetTab(self.tab == "log" and "search" or "log")
    else
        return false
    end
    return true
end


function QuestPanel:Show(opts)
    local window = self:EnsureWindow()
    if not window then
        FGPS:Print(L["The quest window is unavailable; type /cabbie quests about for what the data says."])
        return false
    end
    opts = opts or {}
    window:Show()
    if FGPS.QuestBatch and FGPS.QuestBatch.Suggest then FGPS.QuestBatch.Suggest() end
    if opts.query and opts.query ~= "" then
        self.query = opts.query
        if window.fgpsEdit.SetText then window.fgpsEdit:SetText(opts.query) end
        self:SetTab("search")
        self:RunSearch(opts.query)
    elseif opts.tab then
        self:SetTab(opts.tab)
    else
        self:Refresh()
    end
    return true
end



local function reveal(questID)
    QuestPanel.expanded = questID
    if QuestPanel.tab == "search" then QuestPanel:SetFocus(questID) end
    QuestPanel.selectedIndex = 0
    QuestPanel:Refresh()
    for i, item in ipairs(QuestPanel.items) do
        if item.kind == "quest" and item.questID == questID then
            QuestPanel:Select(i)
            return true
        end
    end
    QuestPanel.expanded = nil
    if QuestPanel.tab == "search" then QuestPanel:SetFocus(nil) end
    QuestPanel:Refresh()
    return false
end





function QuestPanel:ShowQuest(questID)
    questID = tonumber(questID)
    if not self:Show({ tab = "log" }) then return false end
    if not questID or questID <= 0 then return false end
    if reveal(questID) then return true end
    local title, known = titleFor(questID)
    if not known then return false end
    local window = self.window
    if window.fgpsEdit and window.fgpsEdit.SetText then window.fgpsEdit:SetText(title) end
    self:SetTab("search")
    self:RunSearch(title)
    if reveal(questID) then return true end
    self:SetTab("log")
    return false
end

function QuestPanel:Hide()
    if self.window and self.window:IsShown() then self.window:Hide() end
end

function QuestPanel:OnWindowHidden()



    if FGPS.QuestBatch and FGPS.QuestBatch.Cancel then FGPS.QuestBatch.Cancel() end
    self:SetFocus(nil)
    self.expanded = nil
    if self.window and self.window.fgpsEdit and self.window.fgpsEdit.ClearFocus then self.window.fgpsEdit:ClearFocus() end
end

function QuestPanel:IsShown()
    return self.window ~= nil and self.window:IsShown()
end

function QuestPanel:Toggle()
    if self:IsShown() then self:Hide() else self:Show() end
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
    if not hooks.native then
        local tracker = rawget(_G, "QuestObjectiveTracker")
        if type(tracker) == "table" and type(tracker.OnBlockHeaderClick) == "function" then
            hooks.native = pcall(hooksecurefunc, tracker, "OnBlockHeaderClick", function(_, block, mouseButton)
                if mouseButton == "RightButton" or type(block) ~= "table" or modified() then return end
                fromTracker(block.id)
            end) or nil
        end
    end
    return hooks
end




local function slash(args)
    local text = Util.Trim(args or "")
    local word = Util.Lower(text)
    if word == "about" or word == "stats" then
        QuestPanel.About()
        return
    end
    QuestPanel:Show({ query = text ~= "" and text or nil })
end

function QuestPanel:Init()
    if self.eventsBound then return end
    self.eventsBound = true
    local Events = FGPS.Events
    Events:Register("QUESTS_UPDATED", function()
        if QuestPanel:IsShown() and QuestPanel.tab == "log" then QuestPanel:Refresh() end
    end, self)
    Events:Register("SETTINGS_CHANGED", function(_, key)
        if key == "quests.batchRadius" and FGPS.QuestBatch and FGPS.QuestBatch.Suggest
            and QuestPanel:IsShown() then
            FGPS.QuestBatch.Suggest()
        end
        if key == "units" or key == "preset" or key == "accessibility.colorScheme" or key == "*"
            or (type(key) == "string" and key:sub(1, 7) == "quests.") then
            if QuestPanel:IsShown() then QuestPanel:Refresh() end
        end
    end, self)
    Events:Register("QUEST_BATCH", function()
        if QuestPanel.batchText then paintBatch() end
    end, self)

    QuestPanel.HookTrackers()
    if Events.RegisterWoW then
        Events:RegisterWoW("ADDON_LOADED", function()
            local hooks = QuestPanel.HookTrackers()
            if hooks.questie and hooks.native and Events.UnregisterWoW then Events:UnregisterWoW("ADDON_LOADED", self) end
        end, self)
    end
    FGPS.Slash.Register("quests", slash,
        L["Quest help: quests [zone|level|name] | quests about"])
end
