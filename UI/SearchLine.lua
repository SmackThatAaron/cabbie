










local ADDON_NAME, FGPS = ...

local L = FGPS.L
local type, ipairs, pcall, tostring, format, max, min = type, ipairs, pcall, tostring, string.format, math.max, math.min

local SearchLine = {
    surfaces = {},
    eventsBound = false,
    lifeTimer = nil,
}
FGPS.UI.SearchLine = SearchLine

SearchLine.ROW_HEIGHT = 20
SearchLine.ICON = 16
SearchLine.PAD = 8
SearchLine.GAP = 6
SearchLine.EDGE = 16
SearchLine.ROW_INSET = 4
SearchLine.TITLE_HEIGHT = 20
SearchLine.LIST_WIDTH = 360
SearchLine.DISTANCE_WIDTH = 64
SearchLine.LINE_WIDTH = 430
SearchLine.LINE_HEIGHT = 32
SearchLine.LINE_X = 32
SearchLine.LINE_Y = 140
SearchLine.LINE_STRATA = "DIALOG"
SearchLine.LINE_TEMPLATES = { "InputBoxTemplate" }
SearchLine.MAX_LETTERS = 60
SearchLine.NEAREST_REST = 0.3

local function trimmed(text)
    return FGPS.Util.Trim(type(text) == "string" and text or "")
end



local function cancelNearest(surface)
    if surface.timer then
        surface.timer:Cancel()
        surface.timer = nil
    end
    if surface.nearest then
        surface.nearest = nil
        local Services = FGPS.ServiceSearch
        if Services and Services.Cancel then Services.Cancel() end
    end
end






local function rowText(surface, entry)
    if entry.kind == "guide" or entry.kind == "note" then return entry.text or "" end
    local Look, Rows = FGPS.UI.Look, FGPS.UI.SearchRows
    local text = Rows.Mark(entry.name, surface.text)
    if type(entry.zone) == "string" and entry.zone ~= "" then text = text .. "  " .. Look.Tint(entry.zone, "grey") end
    return text
end


local function cursorAt()
    if type(GetCursorPosition) ~= "function" then return nil end
    return GetCursorPosition()
end





local function hovered(key, index)
    local surface = SearchLine.surfaces[key]
    if not surface then return end
    local x, y = cursorAt()
    if x ~= nil and x == surface.cursorX and y == surface.cursorY then return end
    surface.cursorX, surface.cursorY = x, y
    SearchLine.Select(key, index)
end

local function createRow(surface, index)
    local Look = FGPS.UI.Look
    local key = surface.key
    local row = CreateFrame("Button", nil, surface.list)
    row:SetHeight(SearchLine.ROW_HEIGHT)
    row.Highlight = row:CreateTexture(nil, "BACKGROUND")
    row.Highlight:SetAllPoints(row)
    Look.Highlight(row.Highlight)
    row.Highlight:Hide()


    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetPoint("CENTER", row, "LEFT", SearchLine.PAD + SearchLine.ICON / 2, 0)
    row.Distance = row:CreateFontString(nil, "OVERLAY", Look.Font("rowSmall"))
    row.Distance:SetPoint("RIGHT", row, "RIGHT", -SearchLine.PAD, 0)


    row.Text = row:CreateFontString(nil, "OVERLAY", Look.Font("row"))
    row.Text:SetPoint("LEFT", row, "LEFT", SearchLine.PAD + SearchLine.ICON + SearchLine.GAP, 0)
    if row.Text.SetJustifyH then row.Text:SetJustifyH("LEFT") end
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnClick", function() SearchLine.Click(key, index) end)

    row:SetScript("OnEnter", function() hovered(key, index) end)
    surface.list.Rows[index] = row
    return row
end



local function paint(surface)
    local list, view = surface.list, surface.view
    if not (view and surface.listWanted) then
        list:Hide()
        return
    end
    local Look = FGPS.UI.Look

    surface.cursorX, surface.cursorY = cursorAt()
    local y = SearchLine.PAD
    if view.title then
        Look.SetLine(list.Title, view.title, Look.Color("match"))
        Look.SetLine(list.Hint, view.hint or "", Look.Color("grey"))
        list.Title:Show()
        list.Hint:Show()
        y = y + SearchLine.TITLE_HEIGHT
    else
        list.Title:Hide()
        list.Hint:Hide()
    end
    local left = SearchLine.PAD + SearchLine.ICON + SearchLine.GAP
    local wide = SearchLine.LIST_WIDTH - left - SearchLine.PAD - 2 * SearchLine.ROW_INSET
    for i, entry in ipairs(view.rows) do
        local row = list.Rows[i] or createRow(surface, i)
        local sentence = entry.kind == "guide" or entry.kind == "note"

        row.Text:SetWidth(sentence and wide or (wide - SearchLine.DISTANCE_WIDTH - SearchLine.GAP))
        if row.Text.SetWordWrap then row.Text:SetWordWrap(sentence) end
        if row.Text.SetMaxLines then row.Text:SetMaxLines(sentence and 2 or 1) end
        Look.SetLine(row.Text, rowText(surface, entry), Look.Color(entry.kind == "note" and "grey" or "name"))

        local distance = (not sentence and type(entry.yards) == "number") and Look.Distance(entry.yards) or nil
        Look.SetLine(row.Distance, distance or "", Look.Color("name"))
        if entry.icon then
            if row.iconKind ~= entry.icon then
                Look.Icon(row.Icon, entry.icon, SearchLine.ICON)
                row.iconKind = entry.icon
            end
            row.Icon:Show()
        else
            row.Icon:Hide()
        end
        row.Highlight:SetShown(view.selectable == true and i == surface.selected)
        local height = SearchLine.ROW_HEIGHT
        if sentence then height = max(height, (row.Text:GetStringHeight() or 0) + 8) end
        row:SetHeight(height)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", list, "TOPLEFT", SearchLine.ROW_INSET, -y)
        row:SetPoint("TOPRIGHT", list, "TOPRIGHT", -SearchLine.ROW_INSET, -y)
        row:Show()
        y = y + height
    end
    for i = #view.rows + 1, #list.Rows do list.Rows[i]:Hide() end
    list:SetHeight(y + SearchLine.PAD)
    list:Show()
end

local function paintSelection(surface)
    local view = surface.view
    for i, row in ipairs(surface.list.Rows) do
        row.Highlight:SetShown(view ~= nil and view.selectable == true and i == surface.selected)
    end
end







local function restBeforeNearest(surface, text)
    local Rows = FGPS.UI.SearchRows
    if not (C_Timer and C_Timer.NewTimer and Rows and Rows.Nearest) then return end
    surface.timer = C_Timer.NewTimer(SearchLine.NEAREST_REST, function()
        surface.timer = nil
        local service, base = Rows.Service(text)
        if not service then return end




        local Services = FGPS.ServiceSearch
        if Services and Services.IsSearching and Services.IsSearching() then return end
        surface.nearest = text
        Rows.Nearest(service, base, function(routed)
            if surface.nearest ~= text then return end
            surface.nearest = nil
            local view = surface.view
            if not (routed and view and view.selectable) or surface.moved or trimmed(surface.text) ~= text then return end
            for _, row in ipairs(view.rows) do
                if row.kind ~= "service" and #routed < Rows.MAX then routed[#routed + 1] = row end
            end
            view.rows = routed
            paint(surface)
        end)
    end)
end



local function refresh(surface)
    local Rows = FGPS.UI.SearchRows
    local text = trimmed(surface.text)
    cancelNearest(surface)
    surface.selected, surface.moved = 1, false
    if not Rows then
        surface.view = nil
    elseif #text < Rows.MIN_LETTERS then


        local rows, title = Rows.Guide(surface.passive == true and surface.key == "line")
        surface.view = { title = title, hint = surface.passive and L["Click to close"] or nil, rows = rows, selectable = false }
    else


        local ok, rows, service = pcall(Rows.For, text)
        if not ok then
            if FGPS.Log then FGPS.Log:Error("The search for '%s' failed: %s", text, tostring(rows)) end
            rows, service = {}, nil
        end
        if #rows == 0 then
            surface.view = { rows = { { kind = "note", text = format(L["No place matches '%s'."], text) } }, selectable = false }
        else
            surface.view = { rows = rows, selectable = true }
            if service then restBeforeNearest(surface, text) end
        end
    end
    paint(surface)
end


function SearchLine.SetQuery(key, text)
    local surface = SearchLine.surfaces[key]
    if not surface then return false end
    text = type(text) == "string" and text or ""

    if surface.view and surface.text == text then return false end
    surface.text = text
    if not surface.listWanted then return false end
    refresh(surface)
    return true
end

function SearchLine.Select(key, index)
    local surface = SearchLine.surfaces[key]
    local view = surface and surface.view
    if not (view and view.selectable) or type(index) ~= "number" then return false end
    index = max(1, min(#view.rows, index))
    if index == surface.selected then return false end
    surface.selected, surface.moved = index, true
    paintSelection(surface)
    return true
end

function SearchLine.Move(key, delta)
    local surface = SearchLine.surfaces[key]
    if not surface then return false end
    return SearchLine.Select(key, (surface.selected or 1) + delta)
end



function SearchLine.Dismiss(key)
    local surface = SearchLine.surfaces[key]
    if not surface then return false end
    if key == "line" then return SearchLine.Close() end
    cancelNearest(surface)
    surface.listWanted, surface.passive = false, false
    surface.text, surface.view = "", nil
    surface.list:Hide()
    surface.edit:SetText("")
    surface.edit:ClearFocus()
    return true
end



function SearchLine.Accept(key, index)
    local surface = SearchLine.surfaces[key]
    if not surface then return false end
    local view = surface.view
    local row = view and view.selectable and view.rows[index or surface.selected] or nil
    SearchLine.Dismiss(key)
    if not row then return false end
    local Rows = FGPS.UI.SearchRows
    return Rows ~= nil and Rows.Start(row) == true
end


function SearchLine.Click(key, index)
    local surface = SearchLine.surfaces[key]
    local view = surface and surface.view
    if not view then return false end
    if view.selectable then return SearchLine.Accept(key, index) end
    SearchLine.Dismiss(key)
    return false
end


function SearchLine.OnFocusGained(key)
    local surface = SearchLine.surfaces[key]
    if not surface then return end
    local text = surface.edit:GetText() or ""
    local stale = surface.passive or not (surface.listWanted and surface.view and surface.text == text)
    surface.listWanted, surface.passive = true, false
    surface.text = text
    if stale then refresh(surface) end
end



function SearchLine.OnFocusLost(key)
    local surface = SearchLine.surfaces[key]
    if not surface then return end
    if key == "line" then
        SearchLine.Close()
        return
    end
    cancelNearest(surface)
    surface.listWanted = false
    surface.list:Hide()
end








local function createList(surface, parent)
    local Look = FGPS.UI.Look
    local list
    list, surface.ground = Look.CreateGround("Frame", parent, SearchLine.EDGE)
    list:SetWidth(SearchLine.LIST_WIDTH)
    list:EnableMouse(true)
    list:Hide()
    list.Title = list:CreateFontString(nil, "OVERLAY", Look.Font("listTitle"))
    list.Title:SetPoint("TOPLEFT", list, "TOPLEFT", SearchLine.PAD, -SearchLine.PAD)
    list.Hint = list:CreateFontString(nil, "OVERLAY", Look.Font("rowSmall"))
    list.Hint:SetPoint("TOPRIGHT", list, "TOPRIGHT", -SearchLine.PAD, -SearchLine.PAD)
    list.Rows = {}

    local key = surface.key
    list:SetScript("OnMouseUp", function()
        if surface.passive then SearchLine.Dismiss(key) end
    end)
    surface.list = list
    return list
end





local function createEdit(surface, parent, templates)
    local Look = FGPS.UI.Look
    local edit
    edit, surface.template = Look.EditBox(parent, templates)
    if edit.SetAltArrowKeyMode then edit:SetAltArrowKeyMode(false) end
    if edit.SetMaxLetters then edit:SetMaxLetters(SearchLine.MAX_LETTERS) end
    local key = surface.key
    edit:SetScript("OnEscapePressed", function() SearchLine.Dismiss(key) end)
    edit:SetScript("OnEnterPressed", function() SearchLine.Accept(key) end)
    edit:SetScript("OnArrowPressed", function(_, arrow)
        if arrow == "UP" then SearchLine.Move(key, -1) elseif arrow == "DOWN" then SearchLine.Move(key, 1) end
    end)


    edit:HookScript("OnTextChanged", function(self) SearchLine.SetQuery(key, self:GetText() or "") end)
    edit:HookScript("OnEditFocusGained", function() SearchLine.OnFocusGained(key) end)
    edit:HookScript("OnEditFocusLost", function() SearchLine.OnFocusLost(key) end)
    surface.edit = edit
    return edit
end



local function anchorLine(surface)
    local holder = surface.holder
    holder:ClearAllPoints()
    local chat = ChatFrame1EditBox
    if type(chat) == "table" and chat.GetLeft and chat:GetLeft() then
        holder:SetPoint("TOPLEFT", chat, "TOPLEFT", 0, 0)
        holder:SetPoint("BOTTOMRIGHT", chat, "BOTTOMRIGHT", 0, 0)
    else
        holder:SetSize(SearchLine.LINE_WIDTH, SearchLine.LINE_HEIGHT)
        holder:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", SearchLine.LINE_X, SearchLine.LINE_Y)
    end
end

local function createLine()
    local Look = FGPS.UI.Look
    local holder = CreateFrame("Frame", nil, UIParent)
    holder:SetFrameStrata(SearchLine.LINE_STRATA)
    holder:SetSize(SearchLine.LINE_WIDTH, SearchLine.LINE_HEIGHT)
    holder:Hide()
    local surface = { key = "line", holder = holder, text = "", selected = 1 }
    local edit = createEdit(surface, holder, SearchLine.LINE_TEMPLATES)
    edit:SetPoint("TOPLEFT", holder, "TOPLEFT", 6, 0)
    edit:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -6, 0)

    surface.label = edit:CreateFontString(nil, "OVERLAY", Look.Font("listTitle"))
    surface.label:SetPoint("LEFT", edit, "LEFT", 6, 0)
    surface.label:SetText(L["Go to:"])
    if edit.SetTextInsets then edit:SetTextInsets((surface.label:GetStringWidth() or 40) + 12, 6, 0, 0) end
    createList(surface, holder)
    surface.list:SetPoint("BOTTOMLEFT", holder, "TOPLEFT", 0, 4)
    return surface
end








local function keepFilledIn(edit, text)
    if text == "" or not edit.HighlightText then return end
    edit:HighlightText(0, 0)
    if edit.SetCursorPosition then edit:SetCursorPosition(#text) end
end


local function openField(surface, text)
    surface.edit:SetText(text)
    surface.edit:SetFocus()
    keepFilledIn(surface.edit, text)

    if not (surface.listWanted and surface.view and surface.text == text) or surface.passive then
        surface.listWanted, surface.passive = true, false
        surface.text = text
        refresh(surface)
    end
    return true
end







function SearchLine.Open(text)
    local surface = SearchLine.surfaces.line
    if not surface then return false end
    text = type(text) == "string" and text or ""
    local parent = surface.holder:GetParent()
    if parent and parent.IsVisible and not parent:IsVisible() then return false end
    local field = SearchLine.surfaces.map
    if field and field.holder:IsVisible() then
        if surface.passive then SearchLine.Close() end
        return openField(field, text)
    end
    if SearchLine.lifeTimer then
        SearchLine.lifeTimer:Cancel()
        SearchLine.lifeTimer = nil
    end
    anchorLine(surface)
    surface.listWanted, surface.passive = true, false
    surface.text, surface.view = text, nil
    surface.holder:Show()
    surface.edit:Show()
    surface.edit:SetText(text)
    if surface.edit.SetCursorPosition then surface.edit:SetCursorPosition(#text) end
    surface.edit:SetFocus()
    keepFilledIn(surface.edit, text)


    if not surface.view then refresh(surface) end
    return true
end


function SearchLine.Close()
    local surface = SearchLine.surfaces.line
    if not (surface and surface.holder:IsShown()) then return false end
    if SearchLine.lifeTimer then
        SearchLine.lifeTimer:Cancel()
        SearchLine.lifeTimer = nil
    end
    cancelNearest(surface)
    surface.listWanted, surface.passive = false, false
    surface.text, surface.view = "", nil
    surface.holder:Hide()
    surface.list:Hide()
    surface.edit:ClearFocus()
    surface.edit:SetText("")
    return true
end


function SearchLine.IsOpen()
    local surface = SearchLine.surfaces.line
    return surface ~= nil and surface.holder:IsShown() and not surface.passive
end





function SearchLine.Toggle()
    if SearchLine.IsOpen() then return SearchLine.Close() end
    return SearchLine.Open()
end


function SearchLine.LetGo()
    SearchLine.Close()
    if SearchLine.surfaces.map then SearchLine.Dismiss("map") end
end




SearchLine.FIELD_WIDTH = 200
SearchLine.FIELD_HEIGHT = 20
SearchLine.FIELD_X = 16
SearchLine.FIELD_Y = -14
SearchLine.FIELD_STRATA = "FULLSCREEN_DIALOG"
SearchLine.FIELD_TEMPLATES = { "SearchBoxTemplate", "InputBoxTemplate" }




local function createField()
    local map = WorldMapFrame
    if type(map) ~= "table" or not map.GetWidth then return nil end
    local picture = map.ScrollContainer or (map.GetCanvasContainer and map:GetCanvasContainer()) or map
    local holder = CreateFrame("Frame", nil, map)


    holder:Hide()



    holder:SetFrameStrata(SearchLine.FIELD_STRATA)
    if holder.SetFixedFrameStrata then holder:SetFixedFrameStrata(true) end
    holder:SetSize(SearchLine.FIELD_WIDTH, SearchLine.FIELD_HEIGHT)
    holder:SetPoint("TOPLEFT", picture, "TOPLEFT", SearchLine.FIELD_X, SearchLine.FIELD_Y)
    local surface = { key = "map", holder = holder, text = "", selected = 1 }
    local edit = createEdit(surface, holder, SearchLine.FIELD_TEMPLATES)
    edit:SetAllPoints(holder)
    createList(surface, holder)
    surface.list:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", -6, -4)
    return surface
end



function SearchLine.OnMapShown()
    local surface = SearchLine.surfaces.map
    if not surface then
        surface = createField()
        if not surface then return false end
        SearchLine.surfaces.map = surface
    end

    surface.holder:SetFrameStrata(SearchLine.FIELD_STRATA)
    surface.holder:Show()



    local lineSurface = SearchLine.surfaces.line
    if lineSurface and lineSurface.passive then SearchLine.Close() end



    local account = FGPS.DB and FGPS.DB.account
    if account and not account.guideSeenOnMap and not (InCombatLockdown ~= nil and InCombatLockdown() == true)
        and not SearchLine.IsOpen() then
        account.guideSeenOnMap = true
        SearchLine.MapGuide()
    end
    return true
end



function SearchLine.OnMapHidden()
    return SearchLine.Dismiss("map")
end










SearchLine.FIRST_DELAY = 4
SearchLine.FIRST_LIFE = 60

local function inFight()
    return InCombatLockdown ~= nil and InCombatLockdown() == true
end






function SearchLine.Guide()
    local surface = SearchLine.surfaces.line
    if not surface or SearchLine.IsOpen() then return false end
    local field = SearchLine.surfaces.map
    if field and field.holder:IsVisible() then
        local shown = SearchLine.MapGuide()
        local account = FGPS.DB and FGPS.DB.account
        if shown and account then account.guideSeenOnMap = true end
        return shown
    end
    anchorLine(surface)
    surface.listWanted, surface.passive = true, true
    surface.text = ""
    surface.edit:Hide()
    surface.holder:Show()
    refresh(surface)
    if SearchLine.lifeTimer then
        SearchLine.lifeTimer:Cancel()
        SearchLine.lifeTimer = nil
    end
    if C_Timer and C_Timer.NewTimer then
        SearchLine.lifeTimer = C_Timer.NewTimer(SearchLine.FIRST_LIFE, function()
            SearchLine.lifeTimer = nil
            if surface.passive then SearchLine.Close() end
        end)
    end
    return true
end



function SearchLine.MapGuide()
    local surface = SearchLine.surfaces.map
    if not surface or surface.listWanted then return false end
    surface.listWanted, surface.passive = true, true
    surface.text = ""
    refresh(surface)
    return true
end


function SearchLine.EndGuide()
    local line, map = SearchLine.surfaces.line, SearchLine.surfaces.map
    if line and line.passive then SearchLine.Close() end
    if map and map.passive then SearchLine.Dismiss("map") end
end

local function startFirstTimer()
    if SearchLine.firstTimer or not (C_Timer and C_Timer.NewTimer) then return end
    SearchLine.firstTimer = C_Timer.NewTimer(SearchLine.FIRST_DELAY, function()
        SearchLine.firstTimer = nil
        SearchLine.FirstLogin()
    end)
end







function SearchLine.FirstLogin()
    local account = FGPS.DB and FGPS.DB.account
    if not account or account.guideSeenAtLogin then return false end
    if inFight() then
        SearchLine.firstWaits = true
        return false
    end
    if UIParent and UIParent.IsVisible and not UIParent:IsVisible() then
        startFirstTimer()
        return false
    end
    SearchLine.firstWaits = false
    account.guideSeenAtLogin = true
    local Navigator = FGPS.Navigator
    if Navigator and Navigator.HasAnythingSet and Navigator:HasAnythingSet() then return false end
    local Setup = FGPS.UI.Setup
    if Setup and Setup.Show and Setup:Show() then return true end
    return SearchLine.Guide()
end




local function armFirstLogin()
    local account = FGPS.DB and FGPS.DB.account
    if not account or account.guideSeenAtLogin then return end
    if SearchLine.firstArmed then
        if SearchLine.firstWaits and not inFight() then startFirstTimer() end
        return
    end
    SearchLine.firstArmed = true
    startFirstTimer()
end




function SearchLine:Init()
    if not self.surfaces.line then self.surfaces.line = createLine() end


    local Slash = FGPS.Slash
    if not self.slashRegistered and Slash and Slash.Register then
        self.slashRegistered = true
        local function welcome()
            local Setup = FGPS.UI.Setup
            if Setup and Setup.Show and Setup:Show() then return end
            SearchLine.Open()
        end
        Slash.Register("setup", welcome, L.SETUP_HELP)
        Slash.Register("welcome", welcome, L.SETUP_HELP)
    end
    if self.eventsBound then return end
    local Events = FGPS.Events
    if not Events then return end

    Events:Register("MAP_SHOWN", function() SearchLine.OnMapShown() end, self)
    Events:Register("MAP_HIDDEN", function() SearchLine.OnMapHidden() end, self)


    Events:Register("COMBAT_STATE", function(_, inCombat)
        if inCombat == true then
            SearchLine.LetGo()
        elseif SearchLine.firstWaits then

            SearchLine.FirstLogin()
        end
    end, self)


    Events:Register("WORLD_ENTERED", function() armFirstLogin() end, self)
    Events:Register("DESTINATION_SET", function() SearchLine.EndGuide() end, self)
    self.eventsBound = true
end
