





























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
local ROW_HEIGHT = 20
local DEBOUNCE_SECONDS = 0.15

local TABS = { "log", "search" }
local TAB_LABELS = { log = "My quests", search = "Find a quest" }




local function Frames()
    return FGPS.UI.Frames
end

local function settings()
    return FGPS.DB and FGPS.DB.settings or nil
end

local FALLBACK_FONTS = { small = "GameFontHighlightSmall", normal = "GameFontHighlight",
                         large = "GameFontNormalLarge", title = "GameFontNormalLarge" }

local function makeLabel(parent, kind, text, color)
    local F = Frames()
    if F and F.CreateLabel then
        local ok, fs = pcall(F.CreateLabel, parent, text, { kind = kind, color = color })
        if ok and fs then return fs end
    end
    local fs = parent:CreateFontString(nil, "OVERLAY", FALLBACK_FONTS[kind] or "GameFontHighlightSmall")
    fs:SetText(text or "")
    fs:SetJustifyH("LEFT")
    return fs
end

local function makeButton(parent, text, onClick, width, height)
    local F = Frames()
    local button
    if F and F.CreateButton then
        local ok, result = pcall(F.CreateButton, parent, text, onClick, { width = width or 90, height = height or 22 })
        if ok and type(result) == "table" then button = result end
    end
    if not button then
        button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        button:SetText(text)
        button:SetScript("OnClick", onClick)
        button:SetSize(width or 90, height or 22)
    end
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

local function makeEditBox(parent, opts)
    local F = Frames()
    if F and F.CreateEditBox then
        local ok, box = pcall(F.CreateEditBox, parent, opts)
        if ok and type(box) == "table" then return box end
    end
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(opts.width or 160, opts.height or 22)
    box:SetAutoFocus(false)
    box:SetScript("OnEnterPressed", function(self) if opts.onEnter then opts.onEnter(self, self:GetText()) end end)
    box:SetScript("OnTextChanged", function(self, userInput)
        if opts.onChanged then opts.onChanged(self, self:GetText() or "", userInput) end
    end)
    return box
end

local function contentFrame(window)
    local content = window.Content or window.content or window
    local top = (content == window) and 30 or 0
    return content, top
end




local function questData()
    local QuestData = FGPS.QuestData
    if QuestData and QuestData.Available and QuestData.Available() then return QuestData end
    return nil
end




function QuestPanel.MarkFlag(mark)
    local QuestData = FGPS.QuestData
    local text = QuestData and QuestData.MarkLabel and QuestData.MarkLabel(mark) or L["unconfirmed"]

    if text == "1.12 record" then text = L["unconfirmed"] end
    local Skins = FGPS.UI.Skins
    local name = (mark or 0) >= 2 and "routeVerified" or "routeUnverified"
    local ok, skin = pcall(function() return Skins and Skins.Current and Skins.Current() end)
    local c = ok and type(skin) == "table" and type(skin.colors) == "table" and skin.colors[name] or nil
    if type(c) ~= "table" then return text end
    local function byte(v) return math.floor(Util.Clamp(v or 1, 0, 1) * 255 + 0.5) end
    return format("|cff%02x%02x%02x%s|r", byte(c[1]), byte(c[2]), byte(c[3]), text)
end



local function distanceText(yards)
    if type(yards) ~= "number" then return L["another continent"] end
    local s = settings()
    local text = Util.FormatDistance(yards, s and s.units or "yards")
    if text == "" then return "" end
    return text .. " " .. L["direct"]
end
QuestPanel.DistanceText = distanceText



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



local function searchLabel(row)
    local parts = { (titleFor(row.questID)) }
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
            out[#out + 1] = { target = "none", label = format(L["%s: the giver hands it to you"], objective.kindName) }
        elseif #objective.areas == 0 then
            unplacedListed = true
            out[#out + 1] = { target = "none", unplaced = true, label = format(L["%s: objective place not known"], objective.kindName) }
        end
    end



    if not unplacedListed and QuestData.IsPartial and QuestData.IsPartial(questID) then
        out[#out + 1] = { target = "none", unplaced = true, label = L["objective place not known"] }
    end


    for index, area in ipairs(QuestData.AreasFor(questID)) do
        local at = QuestData.ReachedAt(area)
        out[#out + 1] = {
            target = "objective", index = index, area = area, interior = area.interior,
            label = QuestData.AreaLabel(area),
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
        Search.GoTo(dest)
    else
        local Navigator = FGPS.Navigator
        if not (Navigator and Navigator.SetDestination) then
            FGPS:Print(L["Navigation is not available right now."])
            return false
        end
        Navigator:SetDestination(dest, { start = false })
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
    local accepted = isAccepted(questID)
    for _, stage in ipairs(QuestPanel.StagesFor(questID)) do
        local label = "    " .. stage.label
        if stage.interior then
            label = label .. (stage.routable and L[" (inside; routes to the entrance)"] or L[" (inside; no entrance is known)"])
        end
        local item = { kind = "stage", questID = questID, target = stage.target, index = stage.index,
                       label = label, right = stage.target ~= "none" and distanceText(stage.yards) or "" }
        if stage.target ~= "none" and stage.routable and not (accepted and stage.target == "giver") then
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
    local items = {}
    for _, q in ipairs(list or {}) do
        local title = q.title or (titleFor(q.questID))
        local parts = { title }
        local bundled = q.bundled
        local level = QuestPanel.LevelText(bundled and bundled.level or q.level, bundled and bundled.minLevel)
        if level then parts[#parts + 1] = level end
        if bundled and bundled.giverZone then
            parts[#parts + 1] = format(L["starts in %s"], bundled.giverZone)
        end
        if q.complete then
            parts[#parts + 1] = L["Ready to turn in"]
        elseif type(q.objectiveText) == "string" and q.objectiveText ~= "" then
            parts[#parts + 1] = q.objectiveText
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
        if bundled then right = right .. " " .. QuestPanel.MarkFlag(bundled.mark) end
        local open = QuestPanel.expanded == q.questID
        local item = {
            kind = "quest", questID = q.questID,
            label = (open and L["▾ "] or L["▸ "]) .. table.concat(parts, L[" - "]), right = right,
            quest = q, bundled = bundled, yards = yards, step = step,
        }
        if step then
            item.actionLabel = L["Go"]
            item.action = function() goTo(q.questID, "next") end
        end
        items[#items + 1] = item
        if QuestPanel.expanded == q.questID then
            for _, stage in ipairs(stageItems(q.questID)) do items[#items + 1] = stage end
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
            kind = "quest", questID = row.questID, row = row,
            label = (open and L["▾ "] or L["▸ "]) .. searchLabel(row),
            right = distanceText(row.yards) .. " " .. QuestPanel.MarkFlag(row.mark),
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
        if item.kind == "quest" and item.row then item.label = searchLabel(item.row) end
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




local function ensureRowWidgets(row)
    if row.fgpsReady then return end
    row.fgpsReady = true
    row.text = row.Text or makeLabel(row, "small", "", "text")
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.right = makeLabel(row, "small", "", "textDim")
    row.right:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    if row.right.SetJustifyH then row.right:SetJustifyH("RIGHT") end
    row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
    row.action = makeButton(row, "", nil, 48, 18)
    row.action:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.action:Hide()
end

local function applyRowColor(fs, key)
    local skin = FGPS.UI and FGPS.UI.Skins and FGPS.UI.Skins.Current and FGPS.UI.Skins.Current()
    local c = skin and skin.colors and skin.colors[key]
    if c then
        fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end
end

function QuestPanel.RenderRow(row, item, index)
    ensureRowWidgets(row)
    row.item, row.index = item, index
    row.text:SetText(item.label or "")
    if item.kind == "header" then
        applyRowColor(row.text, "title")
    elseif item.kind == "note" or item.kind == "stage" then
        applyRowColor(row.text, "textDim")
    else
        applyRowColor(row.text, "text")
    end


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
    applyRowColor(row.right, "textDim")
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
        for key, button in pairs(w.fgpsTabs) do
            if button.SetAlpha then button:SetAlpha(key == tab and 1 or 0.6) end
            if button.fgpsMark then
                if key == tab then button.fgpsMark:Show() else button.fgpsMark:Hide() end
            end
        end
        w.fgpsEdit:SetShown(tab == "search")
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
        title = L["Cabbie quests"], width = 480, height = 460,
        onClose = function() QuestPanel:OnWindowHidden() end,
        onKey = function(_, key) return QuestPanel:HandleKey(key) end,
    })
    if not ok or type(window) ~= "table" then
        FGPS.Log:Error("Frames.CreateWindow failed: %s", tostring(window))
        return nil
    end
    local content, top = contentFrame(window)
    window.fgpsContent = content

    local function markButton(button)
        local bar = button:CreateTexture(nil, "OVERLAY")
        bar:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 6, 1)
        bar:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -6, 1)
        bar:SetHeight(2)
        if bar.SetColorTexture then bar:SetColorTexture(0.31, 0.76, 0.97, 1) end
        bar:Hide()
        button.fgpsMark = bar
        return button
    end
    window.fgpsTabs = {}
    local previous
    for _, key in ipairs(TABS) do
        local button = markButton(makeButton(content, L[TAB_LABELS[key]], function() QuestPanel:SetTab(key) end, 110, 20))
        if previous then button:SetPoint("LEFT", previous, "RIGHT", 2, 0)
        else button:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -top) end
        window.fgpsTabs[key] = button
        previous = button
    end

    local lookup = makeButton(content, "", function() QuestPanel:LookupNextName() end, 140, 20)
    lookup:SetPoint("TOPRIGHT", content, "TOPRIGHT", -2, -top)
    lookup:Hide()
    window.fgpsLookup = lookup
    local F2 = Frames()
    if F2 and F2.Tooltip then
        pcall(F2.Tooltip, lookup, L["Cabbie bundles no vanilla quest names. This asks the server for one, from a small budget that is yours to spend."])
    end

    local edit = makeEditBox(content, {
        width = 450, height = 22, maxLetters = 60,
        placeholder = L["Zone, level, level band, or a quest name you have seen"],
        onChanged = function(_, text, userInput)
            if userInput == false then return end
            QuestPanel:ScheduleSearch(text or "")
        end,
        onEnter = function(_, text) QuestPanel:RunSearch(text or "") end,
        onEscape = function() QuestPanel:Hide() end,
        keepFocusOnEnter = true,
    })
    edit:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -(top + 26))
    window.fgpsEdit = edit

    local listAnchor = CreateFrame("Frame", nil, content)
    listAnchor:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -(top + 52))
    listAnchor:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -2, 56)
    window.fgpsListAnchor = listAnchor
    local list
    if F.CreateScrollList then
        local okList, made = pcall(F.CreateScrollList, listAnchor, ROW_HEIGHT, QuestPanel.RenderRow, { onClick = onRowClick })
        if okList and type(made) == "table" then list = made else FGPS.Log:Error("Frames.CreateScrollList failed: %s", tostring(made)) end
    end
    if list and list.SetAllPoints then list:SetAllPoints(listAnchor) end
    QuestPanel.list = list

    local status = makeLabel(content, "small", "", "textDim")
    status:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 6, 34)
    status:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -6, 34)
    if status.SetWordWrap then status:SetWordWrap(true) end
    window.fgpsStatus = status

    local specs = {
        { key = "giver", label = "Go to the start", target = "giver" },
        { key = "objective", label = "Go to an objective", target = "objective" },
        { key = "turnin", label = "Go to the turn-in", target = "turnin" },
    }
    window.fgpsButtons = {}
    previous = nil
    for _, spec in ipairs(specs) do
        local button = makeButton(content, L[spec.label], function() QuestPanel:Act(spec.target) end, 150, 22)
        if previous then button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else button:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 2, 4) end
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

function QuestPanel:Hide()
    if self.window and self.window:IsShown() then self.window:Hide() end
end

function QuestPanel:OnWindowHidden()


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



    FGPS:Print(L["Cabbie ships %d fully routable quests: a known giver, a known turn-in and every objective placed."], stats.full or stats.shipped)
    if (stats.partial or 0) > 0 then
        FGPS:Print(L["  %d more ship as partial rows: a known giver and a known turn-in, and an objective whose place is not known."], stats.partial)
    end
    if (stats.oneEnded or 0) > 0 then
        FGPS:Print(L["  %d more ship with one known end: only where they are handed in, or only where they are given."], stats.oneEnded)
    end
    local d = stats.dataset
    if d then
        FGPS:Print(L["  Of the %d quests this client lists, %d have a 1.12 record and %d of those are routable end to end."],
            d.rosterQuests or 0, d.vanillaRecords or 0, d.full or d.shipped or 0)
        FGPS:Print(L["  %d are complete and plausible, %d carry something the builder found suspect."],
            d.plausible or 0, d.suspect or 0)
        FGPS:Print(L["  %d quests exist only in Forever; %d of them are listed here and %d have a known start."],
            (d.foreverListed or 0) + (d.foreverUnknown or 0), d.foreverListed or 0, d.foreverPositioned or 0)
    end
    for _, entry in ipairs(stats.dropped or {}) do
        FGPS:Print(L["  not shipped: %d because %s"], entry.n or 0, L[tostring(entry.why)])
    end
    for _, entry in ipairs(stats.partialReasons or {}) do
        FGPS:Print(L["  partial row: %d because %s"], entry.n or 0, L[tostring(entry.why)])
    end
    for _, entry in ipairs(stats.oneEndedReasons or {}) do
        FGPS:Print(L["  one known end: %d because %s"], entry.n or 0, L[tostring(entry.why)])
    end
    FGPS:Print(L["Every one of them is a 1.12 record. That the quest exists was checked against this client's own list; that its giver has not moved was not."])
    FGPS:Print(L["Quest names are not bundled: the client answers for them in Forever's own wording. Names known so far: %d of %d."],
        stats.titlesKnown or 0, stats.shipped)
    return true
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
        if key == "units" or key == "preset" or key == "accessibility.colorScheme" or key == "*"
            or (type(key) == "string" and key:sub(1, 7) == "quests.") then
            if QuestPanel:IsShown() then QuestPanel:Refresh() end
        end
    end, self)
    FGPS.Slash.Register("quests", slash,
        L["Quest help: quests [zone|level|name] | quests about"])
end
