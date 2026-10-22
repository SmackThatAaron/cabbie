


































local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local type, ipairs, pairs, tostring, tonumber, format = type, ipairs, pairs, tostring, tonumber, string.format

local Search = {
    window = nil,
    list = nil,
    tab = "search",
    filter = "towns",
    query = "",
    items = {},
    selectedIndex = 0,
    addStopMode = false,
    serviceResults = nil,
    serviceQuery = nil,
    listCategory = nil,
    listSub = nil,
    listQuery = "",
    searchGeneration = 0,
    pendingQuery = nil,
}
FGPS.UI.Search = Search

local WINDOW_KEY = "search"
local DEBOUNCE_SECONDS = 0.15
local ROW_HEIGHT = 20
local RESULT_LIMIT = 25
local MIN_QUERY = 2




local TABS = { "search", "favorites", "recent", "quests", "poi" }
local TAB_LABELS = { search = "Search", favorites = "Favorites", recent = "Recent", quests = "Quest", poi = "Points of interest" }
local TAB_WIDTH = { search = 60, favorites = 78, recent = 62, quests = 54, poi = 144 }




local TOWN_TYPES = { 1, 2, 5, 18, 21 }


local FILTERS = {
    { key = "all", label = "All", width = 44, types = nil },
    { key = "towns", label = "Towns", width = 62, first = TOWN_TYPES },
    { key = "dungeons", label = "Dungeons", width = 82, types = { 3, 4, 19 } },
    { key = "travel", label = "Travel", width = 62, types = { 6, 14, 15, 17 } },
    { key = "services", label = "Vendors", width = 74, types = { 7, 8, 9, 10, 11, 12, 13, 16, 20 } },
}

local SERVICE_LABELS = {
    vendor = "Vendor", repair = "Repair", flightmaster = "Flight master", inn = "Inn", mailbox = "Mailbox",
    bank = "Bank", auction = "Auction house", trainer = "Trainer", stable = "Stable master",
}




local LIST_LIMIT = 40

local LIST_FILTER_LIMIT = 2000
local LIST_CATEGORIES = {
    { key = "towns", label = "Towns", subs = {
        { key = "capitals", label = "Capitals", types = { 5 } },
        { key = "towns", label = "Towns", types = { 1 } },
        { key = "landmarks", label = "Landmarks", types = { 2 } },
    } },
    { key = "dungeons", label = "Dungeons", subs = {
        { key = "dungeons", label = "Dungeons", types = { 3 } },
        { key = "raids", label = "Raids", types = { 4 } },
        { key = "battlegrounds", label = "Battlegrounds", types = { 19 } },
    } },
    { key = "travel", label = "Travel", subs = {
        { key = "flight", label = "Flight masters", types = { 6 }, nearest = "flightmaster" },
        { key = "docks", label = "Docks", types = { 14 } },
        { key = "tram", label = "Tram", types = { 15 } },
        { key = "portals", label = "Portals", types = { 17 } },
    } },
    { key = "vendor", label = "Vendors", types = { 8 }, nearest = "vendor" },
    { key = "repair", label = "Repair", types = { 9 }, nearest = "repair" },
    { key = "inn", label = "Inn", types = { 7 }, nearest = "inn" },
    { key = "mailbox", label = "Mailbox", types = { 10 }, nearest = "mailbox" },
    { key = "bank", label = "Bank", types = { 11 }, nearest = "bank" },
    { key = "auction", label = "Auction house", types = { 12 }, nearest = "auction" },
    { key = "trainer", label = "Trainer", trainerMenu = true },
    { key = "weapons", label = "Weapon master", service = "trainer:weapons", nearest = "trainer:weapons" },
    { key = "stable", label = "Stable master", types = { 20 }, nearest = "stable" },
    { key = "graveyard", label = "Graveyard", types = { 16 } },
}


local TRAINER_LABELS = {
    alchemy = "Alchemy", blacksmithing = "Blacksmithing", cooking = "Cooking", enchanting = "Enchanting",
    engineering = "Engineering", firstaid = "First Aid", fishing = "Fishing", herbalism = "Herbalism",
    leatherworking = "Leatherworking", mining = "Mining", skinning = "Skinning", tailoring = "Tailoring",
    weapons = "Weapon master", riding = "Riding", pet = "Pet", portal = "Portal", other = "Other",
}

local function trainerKindLabel(kind)
    if TRAINER_LABELS[kind] then return L[TRAINER_LABELS[kind]] end
    if UnitClass then
        local ok, localised, token = pcall(UnitClass, "player")
        if ok and token == kind and type(localised) == "string" and localised ~= "" then return localised end
    end
    return L[kind:sub(1, 1) .. kind:sub(2):lower()]
end


local function serviceLabel(kind)
    local sub = type(kind) == "string" and kind:match("^trainer:(.+)$")
    if sub == "weapons" then return L["Weapon master"] end
    if sub then return format(L["%s trainer"], trainerKindLabel(sub)) end
    return L[SERVICE_LABELS[kind] or kind]
end




Search.STRAIGHT_FLAG_TEXT = "(open ground)"
Search.STRAIGHT_FLAG = "|cffffa633" .. Search.STRAIGHT_FLAG_TEXT .. "|r"

function Search.RefreshStraightFlag()
    local Skins = FGPS.UI.Skins
    local ok, skin = pcall(function() return Skins and Skins.Current and Skins.Current() end)
    local c = ok and type(skin) == "table" and type(skin.colors) == "table" and skin.colors.routeUnverified or nil
    if type(c) ~= "table" then return Search.STRAIGHT_FLAG end
    local function byte(v) return math.floor(Util.Clamp(v or 1, 0, 1) * 255 + 0.5) end
    Search.STRAIGHT_FLAG = format("|cff%02x%02x%02x%s|r", byte(c[1]), byte(c[2]), byte(c[3]), L[Search.STRAIGHT_FLAG_TEXT])
    return Search.STRAIGHT_FLAG
end
Search.SERVICES_HINT = "Nearest by route distance: the closest candidates by direct distance are routed and sorted by "
    .. "route length. A result marked (open ground) could not be routed; its distance is a direct estimate."




local function Frames()
    return FGPS.UI.Frames
end

local function settings()
    return FGPS.DB and FGPS.DB.settings or nil
end






local function Look()
    return FGPS.UI.Look
end



local function labelFont(kind, color)
    if color == "textDim" then return Look().Font("hint") end
    if color == "title" or color == "accent" then return Look().Font("listTitle") end
    return Look().Font(kind == "small" and "rowSmall" or "row")
end


local function makeLabel(parent, kind, text, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", labelFont(kind, color))
    fs:SetText(text or "")
    if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
    return fs
end


local function makeButton(parent, text, onClick, width, height)
    local button = Look().Button(parent, text, width or 90, height or 22)
    if onClick then button:SetScript("OnClick", onClick) end
    return button
end


local function markButton(button)
    local mark = button:CreateTexture(nil, "OVERLAY")
    mark:SetPoint("TOPLEFT", button, "TOPLEFT", 4, -3)
    mark:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -4, 3)
    Look().Highlight(mark)
    mark:Hide()
    button.fgpsMark = mark
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






local EDIT_TEMPLATES = { "SearchBoxTemplate", "InputBoxTemplate" }
local function makeEditBox(parent, opts)
    local box = Look().EditBox(parent, EDIT_TEMPLATES)
    box:SetSize(opts.width or 160, opts.height or 22)
    if box.SetMaxLetters then box:SetMaxLetters(opts.maxLetters or 80) end

    box.Placeholder = box.Instructions
    if not box.Placeholder then
        box.Placeholder = box:CreateFontString(nil, "OVERLAY", Look().Font("hint"))
        box.Placeholder:SetPoint("LEFT", box, "LEFT", 8, 0)
    end
    box.Placeholder:SetText(opts.placeholder or "")
    local function report(self, text, userInput)
        local ok, err = pcall(opts.onChanged, self, text, userInput)
        if not ok and FGPS.Log then FGPS.Log:Error("Search box handler failed: %s", tostring(err)) end
    end
    box:SetScript("OnEnterPressed", function(self)
        if opts.onEnter then
            local ok, err = pcall(opts.onEnter, self, self:GetText())
            if not ok and FGPS.Log then FGPS.Log:Error("Search box handler failed: %s", tostring(err)) end
        end
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        if opts.onEscape then pcall(opts.onEscape, self) end
    end)
    box:HookScript("OnTextChanged", function(self, userInput)
        local text = self:GetText() or ""
        self.Placeholder:SetShown(text == "")
        if opts.onChanged then report(self, text, userInput) end
    end)


    if box.ClearButton and box.ClearButton.HookScript and opts.onChanged then
        box.ClearButton:HookScript("OnClick", function() report(box, "", true) end)
    end
    return box
end

local function makeList(parent, rowHeight, renderFn, onClick)
    local F = Frames()
    if F and F.CreateScrollList then
        local ok, list = pcall(F.CreateScrollList, parent, rowHeight, renderFn, { onClick = onClick })
        if ok and type(list) == "table" then return list end
        FGPS.Log:Error("Frames.CreateScrollList failed: %s", tostring(list))
    end
    return nil
end

local function setListItems(list, items)
    if not list then return end
    if list.SetItems then list:SetItems(items)
    elseif list.SetData then list:SetData(items)
    elseif list.Update then list:Update(items) end
end

local function contentFrame(window)
    local content = window.Content or window.content or window
    local top = (content == window) and 30 or 0
    return content, top
end

local function playerPos()
    local Coords = FGPS.Coords
    if Coords and Coords.PlayerPos then
        local ok, pos = pcall(Coords.PlayerPos)
        if ok and type(pos) == "table" then return pos end
    end
    return nil
end



function Search.DistanceText(dest, pos, yards)
    local s = settings()
    local units = s and s.units or "yards"
    local text
    if type(yards) == "number" then
        text = Util.FormatDistance(yards, units)
    else
        pos = pos or playerPos()
        if not pos or type(dest) ~= "table" or not dest.x or not dest.y then return "" end
        if dest.inst ~= nil and pos.inst ~= nil and dest.inst ~= pos.inst then return "" end
        local Coords = FGPS.Coords
        if Coords and Coords.Distance then
            yards = Coords.Distance(pos.x, pos.y, dest.x, dest.y)
        else
            local dx, dy = dest.x - pos.x, dest.y - pos.y
            yards = math.sqrt(dx * dx + dy * dy)
        end
        if not yards then return "" end
        text = Util.FormatDistance(yards, units)
    end
    if text == "" then return "" end
    return text .. " " .. L["direct"]
end

local function describe(dest)
    local Destinations = FGPS.Destinations
    if Destinations and Destinations.Describe then
        local ok, text = pcall(Destinations.Describe, dest)
        if ok and type(text) == "string" and text ~= "" then return text end
    end
    if type(dest) ~= "table" then return "?" end
    local name = dest.name or L["Map position"]
    if dest.zoneName then return name .. " - " .. dest.zoneName end
    return name
end





function Search.JourneyRunning()
    local Navigator = FGPS.Navigator
    if not Navigator then return false end
    if Navigator.IsJourney then return Navigator:IsJourney() and true or false end
    local state = Navigator.GetState and Navigator:GetState() or nil
    return state == "active" or state == "paused" or state == "in_transit"
end




function Search.GoTo(dest, mode, opts)
    local Navigator = FGPS.Navigator
    if type(dest) ~= "table" then return false end
    opts = opts or {}

    Search:CancelServiceSearch(true)
    if not Navigator or not Navigator.SetDestination then
        FGPS:Print(L["Navigation is not available right now."])
        return false
    end
    mode = mode or "preview"
    if mode == "addStop" then
        Navigator:SetDestination(dest, { addStop = true, start = false, quiet = opts.quiet == true })


        local Preview = FGPS.UI.Preview
        local stops = Navigator.GetStops and Navigator:GetStops() or {}
        if type(stops) == "table" and #stops > 1 and Preview and Preview.ShowCalculating then
            Preview:ShowCalculating(dest)
            if not Search.JourneyRunning() and Navigator.Preview and Navigator.state ~= "previewing" then
                Navigator:Preview()
            end
        end
        return true
    end
    if mode == "start" then
        Navigator:SetDestination(dest, { start = true, quiet = opts.quiet == true })
        return true
    end

    if mode == "showRoute" then
        local Preview = FGPS.UI.Preview
        local state = Navigator.GetState and Navigator:GetState() or nil
        if state == "active" and not Navigator.riding then





            if Preview and Preview.ShowCalculating then Preview:ShowCalculating(dest, { force = true }) end
            local plain, reason = Navigator:SetDestination(dest, { start = false, quiet = opts.quiet == true })
            if plain == nil and reason ~= nil then
                if Preview and Preview.Dismiss then Preview:Dismiss() end
                return false
            end
            return true
        end
        Navigator:SetDestination(dest, { start = false, quiet = opts.quiet == true })
        if Preview and Preview.ShowCalculating then Preview:ShowCalculating(dest, { force = true }) end
        if Navigator.Preview then Navigator:Preview() end
        return true
    end
    local Preview = FGPS.UI.Preview
    if Search.JourneyRunning() then




        if Preview and Preview.ShowCalculating then Preview:ShowCalculating(dest) end
        local plain, reason = Navigator:SetDestination(dest, { start = false, quiet = opts.quiet == true })
        if plain == nil and reason ~= nil then
            if Preview and Preview.Dismiss then Preview:Dismiss() end
            return false
        end
        return true
    end
    Navigator:SetDestination(dest, { start = false, quiet = opts.quiet == true })
    if Preview and Preview.ShowCalculating then Preview:ShowCalculating(dest) end
    if Navigator.Preview then Navigator:Preview() end
    return true
end


local function resolveItem(item)
    if type(item) ~= "table" then return nil end
    if item.dest then return item.dest end
    if item.resolve then
        local ok, dest, reason = pcall(item.resolve)
        if ok and dest then return dest end
        if ok and reason then FGPS:Print(L["%s: %s"], item.label or "?", tostring(reason)) end
        if not ok then FGPS.Log:Error("Destination resolve failed: %s", tostring(dest)) end
    end
    return nil
end

function Search:SelectedItem()
    local item = self.items[self.selectedIndex]
    if item and (item.dest or item.resolve) then return item end
    for _, candidate in ipairs(self.items) do
        if candidate.dest or candidate.resolve then return candidate end
    end
    return nil
end

function Search:Act(mode)
    local item = self:SelectedItem()
    local dest = resolveItem(item)
    if not dest then
        FGPS:Print(L["Select a destination first."])
        return false
    end
    if mode == "addStop" or (mode == nil and self.addStopMode) then
        Search.GoTo(dest, "addStop")
        return true
    end


    return Search.GoTo(dest, mode)
end

function Search:ToggleFavorite()
    local Destinations = FGPS.Destinations
    local item = self:SelectedItem()
    local dest = resolveItem(item)
    if not dest or not Destinations then
        FGPS:Print(L["Select a destination first."])
        return false
    end
    local index = Destinations.IsFavorite and Destinations.IsFavorite(dest)
    if index and Destinations.RemoveFavorite then
        if type(index) ~= "number" then
            index = nil
            local list = Destinations.Favorites and Destinations.Favorites() or {}
            for i, fav in ipairs(list) do
                if (Destinations.Equal and Destinations.Equal(fav, dest)) or fav == dest then index = i break end
            end
        end
        if index then
            Destinations.RemoveFavorite(index)
            FGPS:Print(L["Removed from favorites: %s"], describe(dest))
        end
    elseif Destinations.AddFavorite then
        local ok, reason = Destinations.AddFavorite(dest)
        if ok == false then
            FGPS:Print(L["Could not add favorite (%s)."], tostring(reason))
        else
            FGPS:Print(L["Added to favorites: %s"], describe(dest))
        end
    end
    if self.tab == "favorites" or self.tab == "search" or self.tab == "recent" then self:Refresh() end
    self:UpdateFavoriteButton()
    return true
end

function Search:UpdateFavoriteButton()
    local window = self.window
    local btn = window and window.fgpsButtons and window.fgpsButtons.favorite
    if not btn then return end
    local Destinations = FGPS.Destinations
    local dest = resolveItem(self:SelectedItem())
    local isFav = dest and Destinations and Destinations.IsFavorite and Destinations.IsFavorite(dest)
    setButtonText(btn, isFav and L["Unfavorite"] or L["Favorite"])
end




Search.ICON = 14

local SERVICE_ICON = {
    vendor = "vendor", repair = "repair", flightmaster = "flight", flight = "flight", travel = "flight", inn = "inn",
    mailbox = "mail", bank = "bank", auction = "auction", trainer = "trainer", weapons = "trainer", stable = "stable",
    towns = "place", capitals = "place", landmarks = "place", dungeons = "dungeon", raids = "dungeon",
}


local function iconKind(item)
    if item.kind == "quest" then return type(item.quest) == "table" and item.quest.complete and "questReady" or "quest" end
    if item.kind == "dest" and type(item.dest) == "table" then
        local Rows = FGPS.UI.SearchRows
        return Rows and Rows.TYPE_ICON and Rows.TYPE_ICON[item.dest.type] or "place"
    end
    if item.kind == "service" and type(item.service) == "string" then return SERVICE_ICON[item.service:match("^%a+")] end
    return nil
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
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("CENTER", row, "LEFT", 4 + Search.ICON / 2, 0)
    row.icon:Hide()
    row.text = row.Text or makeLabel(row, "normal", "", "text")
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.right = makeLabel(row, "small", "", "text")
    row.right:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    if row.right.SetJustifyH then row.right:SetJustifyH("RIGHT") end
    row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
    row.action = makeButton(row, "", nil, 64, 18)
    row.action:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.action:Hide()
end



function Search.RenderRow(row, item, index)
    ensureRowWidgets(row)
    local look = Look()
    row.item, row.index = item, index
    local gold = item.kind == "back" or item.kind == "header"
    row.text:SetFontObject(look.Font(gold and "listTitle" or "row"))
    row.right:SetFontObject(look.Font("rowSmall"))
    row.text:SetText(item.label or "")
    if row.text.SetWordWrap then row.text:SetWordWrap(false) end
    if row.text.SetMaxLines then row.text:SetMaxLines(1) end
    if gold then
        row.text:SetTextColor(look.Color("header"))
    elseif item.otherFaction then

        row.text:SetTextColor(look.Color("grey"))
    else
        row.text:SetTextColor(look.Color("name"))
    end
    row.right:SetTextColor(look.Color("name"))

    if row.Bg and row.Bg.SetAlpha then row.Bg:SetAlpha(0) end
    paintGlow(row)
    local icon = iconKind(item)
    if icon then
        if row.iconKind ~= icon then
            look.Icon(row.icon, icon, Search.ICON)
            row.iconKind = icon
        end
        row.icon:Show()
    else
        row.icon:Hide()
    end
    local left = icon and (8 + Search.ICON) or 6
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row, "LEFT", left, 0)
    if item.actionLabel then
        setButtonText(row.action, item.actionLabel)
        setButtonOnClick(row.action, function() if item.action then item.action(item) end end)
        row.action:Show()
        row.right:SetText("")
        row.right:Hide()

        row.text:SetPoint("RIGHT", row.action, "LEFT", -6, 0)
    else
        row.action:Hide()
        row.right:Show()
        row.right:SetText(item.right or "")
        row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
    end
    row:SetScript("OnDoubleClick", function() if item.dest or item.resolve then Search:Act() end end)
end

local function onRowClick(item, index, button)
    if type(item) ~= "table" then return end
    if item.kind == "back" then
        Search:ServiceBack()
        return
    end
    if item.kind == "header" then return end

    Search.listKeysArmed = true
    Search.selectedIndex = index

    if type(item.open) == "function" and button ~= "RightButton" then
        item.open(item)
        return
    end
    if button == "RightButton" then Search:Act() end
end

function Search:Select(index)
    if #self.items == 0 then
        self.selectedIndex = 0
        return
    end
    if index < 1 then index = 1 end
    if index > #self.items then index = #self.items end
    self.selectedIndex = index
    local list = self.list
    if list and list.SetSelected then list:SetSelected(index) end
    if list and list.ScrollTo then list:ScrollTo(index) end
    self:UpdateFavoriteButton()
end


local function isSkippable(item)
    return type(item) ~= "table" or item.kind == "header" or item.kind == "back"
end

function Search:MoveSelection(delta)
    if #self.items == 0 then return end
    local index = self.selectedIndex + delta
    if self.selectedIndex == 0 and delta > 0 then index = 1 end
    if index < 1 then index = 1 end
    if index > #self.items then index = #self.items end
    local guard = 0
    while isSkippable(self.items[index]) and guard < #self.items do
        index = index + (delta >= 0 and 1 or -1)
        if index < 1 then index = 1 break end
        if index > #self.items then index = #self.items break end
        guard = guard + 1
    end
    if isSkippable(self.items[index]) then

        self:SelectEdge(delta >= 0 and -1 or 1)
        return
    end
    self:Select(index)
end


function Search:SelectEdge(step)
    local n = #self.items
    if n == 0 then return end
    local index = step > 0 and 1 or n
    while index >= 1 and index <= n and isSkippable(self.items[index]) do index = index + step end
    if index < 1 or index > n then return end
    self:Select(index)
end



function Search:PageSize()
    local list = self.list
    local visible = list and list.VisibleCount and list:VisibleCount() or 0
    if type(visible) ~= "number" or visible < 2 then return 5 end
    return visible - 1
end




function Search:Activate()
    local item = self.items[self.selectedIndex]
    if type(item) == "table" then
        if item.kind == "back" then
            self:ServiceBack()
            return true
        end
        local shift = IsShiftKeyDown and IsShiftKeyDown()
        if type(item.open) == "function" and not (shift and type(item.action) == "function") then
            item.open(item)
            return true
        end
        if type(item.action) == "function" then
            item.action(item)
            return true
        end
    end
    return self:Act()
end








local function searchEditAcceptsKeys()
    local edit = Search.window and Search.window.fgpsEdit
    if not edit then return false end
    if edit.IsShown and not edit:IsShown() then return false end
    if edit.HasFocus and not edit:HasFocus() then return false end
    return true
end

local function listKeysAllowed()
    if searchEditAcceptsKeys() then return true end
    return Search.listKeysArmed == true
end

function Search:HandleKey(key)
    if key == "ENTER" or key == "NUMPADENTER" or key == "TAB" then
        if not searchEditAcceptsKeys() then return false end
    elseif key == "UP" or key == "DOWN" or key == "PAGEUP" or key == "PAGEDOWN" or key == "HOME" or key == "END" then
        if not listKeysAllowed() then return false end
    end
    if key == "UP" then
        self:MoveSelection(-1)
    elseif key == "DOWN" then
        self:MoveSelection(1)
    elseif key == "PAGEUP" then
        self:MoveSelection(-self:PageSize())
    elseif key == "PAGEDOWN" then
        self:MoveSelection(self:PageSize())
    elseif key == "HOME" then
        self:SelectEdge(1)
    elseif key == "END" then
        self:SelectEdge(-1)
    elseif key == "ENTER" or key == "NUMPADENTER" then
        self:Activate()
    elseif key == "TAB" then
        self:CycleTab(IsShiftKeyDown and IsShiftKeyDown() and -1 or 1)
    else
        return false
    end
    return true
end


function Search:CycleTab(step)
    local index = 1
    for i, key in ipairs(TABS) do if key == self.tab then index = i end end
    index = index + (step or 1)
    while index < 1 do index = index + #TABS end
    while index > #TABS do index = index - #TABS end
    self:SetTab(TABS[index])
end

function Search:SetItems(items, status)
    self.items = items or {}
    if self.selectedIndex > #self.items then self.selectedIndex = 0 end
    if self.addStopMode then
        local banner = L["Adding stops. Pick a place; the window stays open."]
        status = status and (banner .. "  " .. status) or banner
    end
    if self.window and self.window.fgpsStatus then self.window.fgpsStatus:SetText(status or "") end
    setListItems(self.list, self.items)
    if self.list and self.list.SetSelected then self.list:SetSelected(self.selectedIndex > 0 and self.selectedIndex or nil) end
end


function Search:GetResults()
    return self.items
end





local PLACE_TYPES = {
    town = true, landmark = true, dungeon = true, raid = true, capital = true,
    zone = true, area = true,
}

local function destItems(list, pos)
    local Destinations = FGPS.Destinations
    local items = {}
    for _, entry in ipairs(list or {}) do
        local dest = entry.dest or entry
        local label = entry.label or describe(dest)

        if Destinations and Destinations.IsFavorite and Destinations.IsFavorite(dest) then
            label = L["*"] .. " " .. label
        end
        items[#items + 1] = { kind = "dest", dest = dest, label = label,
                              right = Search.DistanceText(dest, pos, entry.distance), otherFaction = entry.otherFaction,
                              favorite = Destinations and Destinations.IsFavorite and Destinations.IsFavorite(dest) and true or false }
    end
    return items
end




local function withPlaceHeaders(items)
    local hasPlace, hasOther = false, false
    for _, row in ipairs(items or {}) do
        if PLACE_TYPES[row.dest and row.dest.type] then
            hasPlace = true
        else
            hasOther = true
        end
    end
    if not (hasPlace and hasOther) then
        return items
    end
    local out, last = {}, nil
    for _, row in ipairs(items) do
        local section = PLACE_TYPES[row.dest and row.dest.type] and "Places" or "Other"
        if section ~= last then
            out[#out + 1] = { kind = "header", label = L[section] }
            last = section
        end
        out[#out + 1] = row
    end
    return out
end

function Search:RunSearch(text)
    local Destinations = FGPS.Destinations
    text = Util.Trim(text or "")
    self.query = text


    if #text == 0 then
        self.selectedIndex = 0
        self:SetItems({}, L["Type a place name."])
        return
    end
    if #text < MIN_QUERY then
        self.selectedIndex = 0
        self:SetItems({}, L["Type at least two characters."])
        return
    end
    if not Destinations or not Destinations.Search then
        self:SetItems({}, L["Search is not available right now."])
        return
    end
    local filter, town
    for _, f in ipairs(FILTERS) do
        if f.key == self.filter then filter = f end
        if f.key == "towns" then town = f end
    end
    filter = filter or town
    local ok, results = pcall(Destinations.Search, text, { types = filter.types, first = filter.first, limit = RESULT_LIMIT })
    if not ok then
        FGPS.Log:Error("Destinations.Search failed: %s", tostring(results))
        self:SetItems({}, L["Search failed; type /cabbie log for details."])
        return
    end
    local items = withPlaceHeaders(destItems(results, playerPos()))
    self.selectedIndex = 0
    for i, item in ipairs(items) do
        if item.kind == "dest" then self.selectedIndex = i break end
    end
    local n = 0
    for _, item in ipairs(items) do if item.kind == "dest" then n = n + 1 end end
    self:SetItems(items, n == 0 and L["No matching destinations."] or format(L["%d result(s)"], n))
end

function Search:ScheduleSearch(text)
    self.searchGeneration = self.searchGeneration + 1
    local generation = self.searchGeneration
    self.pendingQuery = text
    if C_Timer and C_Timer.After then
        C_Timer.After(DEBOUNCE_SECONDS, function()
            if generation ~= Search.searchGeneration then return end
            Search.pendingQuery = nil
            Search:RunSearch(text)
        end)
    else
        self:RunSearch(text)
    end
end


local function filterList()
    Search:CancelServiceSearch()
    Search.serviceResults = nil
    Search:Refresh()
end

function Search:ScheduleListFilter(text)
    self.searchGeneration = self.searchGeneration + 1
    local generation = self.searchGeneration
    self.listQuery = text or ""
    if C_Timer and C_Timer.After then
        C_Timer.After(DEBOUNCE_SECONDS, function()
            if generation ~= Search.searchGeneration then return end
            if Search.tab ~= "poi" then return end
            filterList()
        end)
    else
        filterList()
    end
end



local function questReasonText(Quests, reason)
    if type(Quests.ReasonText) == "function" then
        local ok, text = pcall(Quests.ReasonText, reason)
        if ok and type(text) == "string" and text ~= "" then return text end
    end
    return L["no map location is known for this quest"]
end




local function questLocationLabel(title, loc, n, total)
    local where = format(L["%s (%d of %d)"], tostring(loc.zoneName or L["Unknown zone"]), n, total)
    if loc.waypoint then where = where .. " " .. L["(next)"] end
    local objective = loc.objectiveText
    if type(objective) == "string" and objective ~= "" then
        return format(L["%s - %s: %s"], title, where, objective)
    end
    return format(L["%s - %s"], title, where)
end







local function questItem(Quests, q, title, label, locationHandle)
    local questID = q.questID
    local function destination()
        local dest, reason = Quests.DestinationFor(questID, locationHandle)
        if dest then return dest end
        return nil, questReasonText(Quests, reason)
    end
    return {
        kind = "quest", label = label, quest = q, locationHandle = locationHandle, actionLabel = L["Go"],
        resolve = destination,
        action = function()
            local dest, why = destination()
            if dest then

                Search.GoTo(dest, Search.addStopMode and "addStop" or "start")
            else
                FGPS:Print(L["%s: %s"], title, why)
            end
        end,
    }
end





local function questTitle(q)
    if type(q.title) == "string" and q.title ~= "" then return q.title end
    local QuestData = FGPS.QuestData
    if QuestData and QuestData.Title then
        local ok, title = pcall(QuestData.Title, q.questID)
        if ok and type(title) == "string" and title ~= "" then return title end
    end
    return format(L["Quest %d"], tonumber(q.questID) or 0)
end



local function questStepWhere(step, pos)
    local zone = step.zoneName
    if type(zone) ~= "string" or zone == "" then return nil end
    if not pos then return zone end
    local distance = Search.DistanceText(step, pos)
    if distance == "" then distance = L["another continent"] end
    return format(L["%s, %s"], zone, distance)
end

local function questItems()
    local Quests = FGPS.Quests
    local items = {}
    if not Quests or not Quests.List then
        return items, L["Quest lookup is not available right now."]
    end
    local ok, list = pcall(Quests.List)
    if not ok then
        FGPS.Log:Error("Quests.List failed: %s", tostring(list))
        return items, L["Quest lookup failed; type /cabbie log for details."]
    end
    local pos = playerPos()
    for _, q in ipairs(list or {}) do
        local title = questTitle(q)
        if q.complete then title = title .. " " .. L["(complete)"] end
        local outdoor = type(q.outdoor) == "table" and q.outdoor or {}
        if #outdoor > 1 then


            for n, loc in ipairs(outdoor) do
                items[#items + 1] = questItem(Quests, q, title, questLocationLabel(title, loc, n, #outdoor), loc.key or loc.index)
            end
        else




            local step, why
            if type(Quests.NextStep) == "function" then
                local okStep, found, reason = pcall(Quests.NextStep, q.questID)
                if okStep then step, why = found, reason end
            end
            local label = title
            local where = step and questStepWhere(step, pos) or nil
            local objective = outdoor[1] and outdoor[1].objectiveText or q.objectiveText
            local hasObjective = type(objective) == "string" and objective ~= ""
            if where and hasObjective then
                label = format(L["%s - %s: %s"], title, where, objective)
            elseif where then
                label = format(L["%s - %s"], title, where)
            elseif hasObjective then
                label = format(L["%s - %s"], title, objective)
            end
            local item = questItem(Quests, q, title, label, nil)
            if not step and why == "objective_unknown" then



                item.actionLabel, item.action = nil, nil
                item.right = L["objective place not known"]
            end
            items[#items + 1] = item
        end
    end
    return items, #items == 0 and L["No quests with a known location."] or nil
end

local function listCategoryAt(key)
    for i, cat in ipairs(LIST_CATEGORIES) do
        if cat.key == key then return i, cat end
    end
end

local function candidateDest(c)
    local Destinations = FGPS.Destinations
    if c.poiIndex and Destinations and Destinations.FromPOI then
        local ok, dest = pcall(Destinations.FromPOI, c.poiIndex)
        if ok and dest then return dest end
    end
    local s = c.learned
    if type(s) ~= "table" then return nil end
    return { kind = "service", name = s.name, inst = s.inst, x = s.x, y = s.y, map = s.map,
             type = s.kind, serviceKind = s.kind, zoneName = s.zoneName,
             faction = (s.fac ~= 0) and s.fac or nil, learned = true }
end

local function listQueryText()
    return Util.Trim(Search.listQuery or ""):lower()
end

local function listHit(text)
    local query = listQueryText()
    if query == "" then return true end
    local plain = tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower()
    return plain:find(query, 1, true) ~= nil
end

local function subsOf(cat)
    if type(cat.subs) == "table" then return cat.subs end
    if not cat.trainerMenu then return nil end
    local ServiceSearch = FGPS.ServiceSearch
    if not ServiceSearch or not ServiceSearch.TrainerKinds then return {} end
    local ok, kinds = pcall(ServiceSearch.TrainerKinds, playerPos(), 1e9)
    if not ok or type(kinds) ~= "table" then return {} end
    local mine = ServiceSearch.PlayerClass and ServiceSearch.PlayerClass() or nil
    local rows = {}
    for _, entry in ipairs(kinds) do
        local label = trainerKindLabel(entry.kind)
        if entry.kind == mine then label = format(L["%s (your class)"], label) end
        local query = "trainer:" .. entry.kind
        rows[#rows + 1] = { key = entry.kind, label = label, service = query, nearest = query, count = entry.count, named = true }
    end

    rows[#rows + 1] = { key = "any", label = L["Any trainer"], service = "trainer", nearest = "trainer", named = true }
    return rows
end

local function subAt(subs, key)
    for i, sub in ipairs(subs or {}) do
        if sub.key == key then return i, sub end
    end
end

local function subLabel(sub)
    local text = sub.named and sub.label or L[sub.label]
    if sub.count then text = format("%s  |cff999999%d|r", text, sub.count) end
    return text
end

local function placesFor(cat, limit)
    local Destinations = FGPS.Destinations
    if cat.service then
        local ServiceSearch = FGPS.ServiceSearch
        local pos = playerPos()
        if not ServiceSearch or not ServiceSearch.Candidates or not pos then return {} end
        local ok, candidates = pcall(ServiceSearch.Candidates, cat.service, pos, 1e9, limit)
        if not ok or type(candidates) ~= "table" then return {} end
        local rows = {}
        for _, c in ipairs(candidates) do
            local dest = candidateDest(c)
            if dest then
                local label
                if Destinations and Destinations.Label then
                    local named, text = pcall(Destinations.Label, dest.name, dest.zoneName, dest.type)
                    if named and type(text) == "string" then label = text end
                end
                rows[#rows + 1] = { dest = dest, label = label, distance = c.straightYards }
            end
        end
        return rows
    end
    if not cat.types or not Destinations or not Destinations.Browse then return {} end
    local ok, rows = pcall(Destinations.Browse, { types = cat.types, limit = limit })
    if not ok or type(rows) ~= "table" then return {} end
    return rows
end

function Search:NextList(step)
    step = step or 1
    local i, cat = listCategoryAt(self.listCategory)
    if not i then
        self.listCategory = LIST_CATEGORIES[1].key
        self.listSub = nil
        self:Refresh()
        return
    end
    local subs = self.listSub and subsOf(cat) or nil
    local si = subs and subAt(subs, self.listSub) or nil
    if si then
        si = si + step
        if si < 1 then si = #subs end
        if si > #subs then si = 1 end
        self.listSub = subs[si].key
    else
        i = i + step
        if i < 1 then i = #LIST_CATEGORIES end
        if i > #LIST_CATEGORIES then i = 1 end
        self.listCategory = LIST_CATEGORIES[i].key
        self.listSub = nil
    end
    self:Refresh()
end

local function matchingPlaces(cat)
    local filtering = listQueryText() ~= ""
    local rows = placesFor(cat, filtering and LIST_FILTER_LIMIT or LIST_LIMIT)
    if not filtering then return rows end
    local matched = {}
    for _, row in ipairs(rows) do
        local dest = row.dest
        if listHit(row.label) or (dest and (listHit(dest.name) or listHit(dest.zoneName))) then
            matched[#matched + 1] = row
        end
    end
    return matched
end



local function openRow(entry, label, open)
    local row = { kind = "service", service = entry.key, label = label, open = open }
    if entry.nearest then
        local query = entry.nearest
        row.actionLabel, row.action = L["Nearest"], function() Search:FindNearest(query) end
    else
        row.actionLabel, row.action = entry.trainerMenu and L["Choose"] or L["Open"], open
    end
    return row
end

local function listItems()
    local index = listCategoryAt(Search.listCategory)
    if not index then
        local items = {}
        for _, cat in ipairs(LIST_CATEGORIES) do
            local label = L[cat.label]
            if listHit(label) then
                items[#items + 1] = openRow(cat, label, function()
                    Search.listCategory = cat.key
                    Search.listSub = nil
                    Search:Refresh()
                end)
            end
        end
        local status = L["Pick a category. The list is the nearest places of that kind."]
        if listQueryText() ~= "" then
            status = #items == 0 and L["No matching destinations."] or format(L["%d result(s)"], #items)
        end
        return items, status
    end
    local cat = LIST_CATEGORIES[index]
    local subs = subsOf(cat)
    if subs and not Search.listSub then
        local items = {
            { kind = "back", label = L["< Back to categories"] },
            { kind = "service", label = L[cat.label], actionLabel = L["Next"],
              action = function() Search:NextList(1) end },
        }
        for _, sub in ipairs(subs) do
            local label = subLabel(sub)
            if listHit(label) then
                items[#items + 1] = openRow(sub, label, function()
                    Search.listSub = sub.key
                    Search:Refresh()
                end)
            end
        end
        local n = #items - 2
        local status = L["Pick a list."]
        if listQueryText() ~= "" then
            status = n == 0 and L["No matching destinations."] or format(L["%d result(s)"], n)
        elseif n == 0 then
            status = L["No matching destinations."]
        elseif cat.trainerMenu and #subs == 1 then

            status = L["No trainers are known on this continent for your faction."]
        end
        return items, status
    end
    local leaf = cat
    local title = L[cat.label]
    local back = L["< Back to categories"]
    if subs then
        local _, sub = subAt(subs, Search.listSub)
        leaf = sub or cat
        if sub then title = sub.named and sub.label or L[sub.label] end
        back = L["< Back to lists"]
    end
    local items = {
        { kind = "back", label = back },
        { kind = "service", label = title, actionLabel = L["Next"],
          action = function() Search:NextList(1) end },
    }
    for _, row in ipairs(destItems(matchingPlaces(leaf), playerPos())) do
        items[#items + 1] = row
    end
    local n = #items - 2
    local status = n == 0 and L["No matching destinations."] or format(L["%d result(s)"], n)
    return items, status
end



function Search:ServiceBack()
    if self.serviceResults then
        self.serviceResults = nil
    elseif self.listSub then
        self.listSub = nil
    else
        self.listCategory = nil
    end
    self:Refresh()
end







function Search:CancelServiceSearch(redraw)
    if not self.serviceQuery then return false end
    self.serviceQuery = nil
    local ServiceSearch = FGPS.ServiceSearch
    local cancelled = false
    if ServiceSearch and ServiceSearch.Cancel then
        local ok, result = pcall(ServiceSearch.Cancel)
        cancelled = ok and result == true
    end
    if redraw and self.tab == "poi" and self:IsShown() then self:Refresh() end
    return cancelled
end

function Search:FindNearest(kind)
    local ServiceSearch = FGPS.ServiceSearch
    if not ServiceSearch or not ServiceSearch.Nearest then return end





    self:CancelServiceSearch()
    self.serviceQuery = kind
    self:SetItems(self.items, format(L["Searching for the nearest %s..."], serviceLabel(kind)))
    local ok, err = pcall(ServiceSearch.Nearest, kind, { limit = 5 }, function(list, reason)
        if Search.serviceQuery ~= kind then return end
        Search.serviceQuery = nil
        Search.serviceResults = { kind = kind, list = type(list) == "table" and list or {}, reason = reason }
        Search:Refresh()
    end)
    if not ok then
        FGPS.Log:Error("ServiceSearch.Nearest failed: %s", tostring(err))
        self.serviceQuery = nil
        self:SetItems(self.items, L["Service search failed; type /cabbie log for details."])
    end
end

local SERVICE_REASONS = {
    no_position = "your position is not available here",
    none = "nothing of that kind is known within range",
    bad_type = "unknown service type",
}



function Search.ServiceResultText(entry, pos, units)
    local text
    if type(entry.yards) == "number" then
        text = Util.FormatDistance(entry.yards, units)
    elseif type(entry.straightYards) == "number" then
        text = Util.FormatDistance(entry.straightYards, units)
    else
        text = Search.DistanceText(entry.dest or entry, pos)
    end
    if entry.straight then
        text = (text ~= "" and (text .. " ") or "") .. Search.STRAIGHT_FLAG
    end
    return text
end


local function resultsBackLabel()
    if not Search.listCategory then return L["< Back to categories"] end
    if Search.listCategory == "trainer" then return L["< Back to trainer kinds"] end
    return L["< Back to lists"]
end

local function serviceResultItems(results)
    local items = { { kind = "back", label = resultsBackLabel() } }
    local pos = playerPos()
    local s = settings()
    local units = s and s.units or "yards"
    local straightCount = 0
    for _, entry in ipairs(results.list) do
        local dest = entry.dest or entry
        local unverified = entry.straight == true
        if unverified then straightCount = straightCount + 1 end
        items[#items + 1] = { kind = "dest", dest = dest, label = entry.label or describe(dest),
                              right = Search.ServiceResultText(entry, pos, units), unverified = unverified }
    end
    local label = serviceLabel(results.kind)
    local status
    if #results.list == 0 then
        local why = results.reason and (L[SERVICE_REASONS[results.reason] or tostring(results.reason)]) or L["nothing of that kind is known within range"]
        status = format(L["No %s found: %s."], label, why)
        status = status .. " " .. L["Try Favorites, or Search for a town."]
    elseif straightCount > 0 then
        status = format(L["Nearest %s by route distance; %d of %d could not be routed and show open ground."], label, straightCount, #results.list)
    else
        status = format(L["Nearest %s by route distance."], label)
    end
    return items, status
end


function Search:Refresh()
    if not self.window then return end
    local Destinations = FGPS.Destinations
    local tab = self.tab
    local items, status
    if tab == "search" then
        self:RunSearch(self.query)
        return
    elseif tab == "favorites" then
        local list = Destinations and Destinations.Favorites and Destinations.Favorites() or {}
        items = destItems(list, playerPos())
        status = #items == 0 and L["No favorites yet. Select a result and press Favorite."] or nil
    elseif tab == "recent" then
        local list = Destinations and Destinations.Recents and Destinations.Recents() or {}
        items = destItems(list, playerPos())
        status = #items == 0 and L["No recent destinations."] or nil
    elseif tab == "quests" then
        items, status = questItems()
    elseif tab == "poi" then
        if self.serviceResults then
            items, status = serviceResultItems(self.serviceResults)
        else
            items, status = listItems()
        end
    end
    self.selectedIndex = 0
    for i, item in ipairs(items or {}) do
        if item.kind == "dest" then self.selectedIndex = i break end
    end
    if self.selectedIndex == 0 then


        for i, item in ipairs(items or {}) do
            if not isSkippable(item) then self.selectedIndex = i break end
        end
    end
    self:SetItems(items, status)
end



function Search:RefreshDistances()
    if not self:IsShown() then return end
    local keep = self.selectedIndex
    local kept = self.items[keep]
    self:Refresh()
    if not kept or keep <= 0 then return end
    local restored = 0
    for i, item in ipairs(self.items) do
        if item == kept then restored = i break end
        if kept.dest and item.dest and item.dest.inst == kept.dest.inst
            and item.dest.x == kept.dest.x and item.dest.y == kept.dest.y
            and (item.dest.name == nil or kept.dest.name == nil or item.dest.name == kept.dest.name) then
            restored = i
            break
        end
        if kept.label and item.label == kept.label and item.kind == kept.kind then
            restored = i
            break
        end
    end
    if restored == 0 and keep <= #self.items then restored = keep end
    if restored > 0 then
        self.selectedIndex = restored
        if self.list and self.list.SetSelected then self.list:SetSelected(restored) end
    end
end

function Search:SetTab(tab)
    if not TAB_LABELS[tab] then return end
    self:CancelServiceSearch()
    self.searchGeneration = self.searchGeneration + 1
    self.pendingQuery = nil
    self.listCategory = nil
    self.listSub = nil
    self.listQuery = ""
    self.tab = tab
    self.serviceResults = nil
    local w = self.window
    if w then
        for key, button in pairs(w.fgpsTabs) do
            local on = key == tab
            if button.SetAlpha then button:SetAlpha(on and 1 or 0.45) end
            if button.fgpsMark and button.fgpsMark.SetShown then button.fgpsMark:SetShown(on) end
        end
        local isSearch = tab == "search"
        local isPoi = tab == "poi"
        w.fgpsEdit:SetShown(isSearch or isPoi)
        if w.fgpsEdit.Placeholder and w.fgpsEdit.Placeholder.SetText then
            w.fgpsEdit.Placeholder:SetText(L[isPoi and "Filter this list" or "Town, NPC, or 42.5 65.1"])
        end
        w.fgpsEdit:SetText(isPoi and (self.listQuery or "") or (self.query or ""))
        if w.fgpsCoordTip then w.fgpsCoordTip:SetShown(isSearch) end
        if w.fgpsHint then w.fgpsHint:SetShown(isPoi) end
        if w.fgpsQuestPanel then w.fgpsQuestPanel:SetShown(tab == "quests") end
    end
    if tab == "search" then self.filter = "towns" end
    self:Refresh()
end

function Search:SetFilter(key)
    self.filter = key
    if self.tab == "search" then self:RunSearch(self.query) end
end






local function parseCoordinatesLocally(text)
    local cleaned = text:gsub("[,;:/]", " ")
    local sx, sy, rest = cleaned:match("^(%-?%d+%.?%d*)%s+(%-?%d+%.?%d*)%s*(.-)$")
    if not sx then
        rest, sx, sy = cleaned:match("^(.-)%s+(%-?%d+%.?%d*)%s+(%-?%d+%.?%d*)$")
    end
    if not sx then return nil end
    return Util.Trim(rest or ""), tonumber(sx), tonumber(sy)
end





function Search.ParseCoordinates(text)
    text = Util.Trim(tostring(text or ""))
    if text == "" then return nil end
    local zone, x, y
    local Destinations = FGPS.Destinations
    if Destinations and Destinations.ParseCoords then
        local ok, rest, px, py = pcall(Destinations.ParseCoords, text)
        if ok and type(px) == "number" and type(py) == "number" then zone, x, y = rest, px, py end
    end
    if not x then zone, x, y = parseCoordinatesLocally(text) end
    if not x or not y or x < 0 or x > 100 or y < 0 or y > 100 then return nil end
    if type(zone) == "string" then
        zone = Util.Trim(zone)
        if zone == "" then zone = nil else zone = tonumber(zone) or zone end
    end
    return x, y, zone
end

function Search:GoToCoordinates(text)
    local Destinations = FGPS.Destinations
    local x, y, zone = Search.ParseCoordinates(text)
    if not x then
        FGPS:Print(L["Enter coordinates as: x y [zone], for example 42.5 65.1 Elwynn Forest or Elwynn Forest 42.5, 65.1 (values 0-100; zone may be a name or map id)"])
        return false
    end
    if not Destinations or not Destinations.FromCoords then
        FGPS:Print(L["Navigation is not available right now."])
        return false
    end
    if not zone then
        local pos = playerPos()
        zone = pos and pos.map or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
        if not zone then
            FGPS:Print(L["Your current zone is unknown; add a zone name after the coordinates."])
            return false
        end
    end
    local ok, dest, err = pcall(Destinations.FromCoords, zone, x, y)
    if not ok then
        FGPS.Log:Error("FromCoords failed: %s", tostring(dest))
        return false
    end
    if not dest then
        FGPS:Print(L["Could not resolve those coordinates%s"], err and (": " .. tostring(err)) or ".")
        return false
    end
    return Search.GoTo(dest, self.addStopMode and "addStop" or nil)
end











local function dressListNow(list)
    local look = Look()
    local bar = list.Bar
    if bar then
        if bar.Track then bar.Track:SetColorTexture(0, 0, 0, 0.35) end
        if bar.fgpsThumb then look.ScrollKnob(bar.fgpsThumb) end
    end
    if list.Empty then
        list.Empty:SetFontObject(look.Font("hint"))
        list.Empty:SetTextColor(look.Color("grey"))
    end
end



function Search.DressList(list)
    if type(list) ~= "table" then return end
    dressListNow(list)
    local F = Frames()
    if F and F.Register and not list.fgpsDressed then
        list.fgpsDressed = true
        local skinPass = list.fgpsApplySkin
        F.Register(list, function(l, skin)
            if skinPass then skinPass(l, skin) end
            dressListNow(l)
            if l.Refresh then l:Refresh() end
        end)
    end
end

local function buildWindow()
    local F = Frames()
    if not F or not F.CreateWindow then
        FGPS.Log:Error("UI.Frames.CreateWindow is unavailable; the search window cannot be built")
        return nil
    end
    local ok, window = pcall(F.CreateWindow, WINDOW_KEY, {
        title = L["Where to"], width = 440, height = 500,
        onClose = function() Search:OnWindowHidden() end,


        onKey = function(_, key) return Search:HandleKey(key) end,
    })
    if not ok or type(window) ~= "table" then
        FGPS.Log:Error("Frames.CreateWindow failed: %s", tostring(window))
        return nil
    end
    Look().DressWindow(window)


    local cog = Look().SettingsButton(window, function() FGPS.UI.Settings:Open() end)
    cog:SetPoint("RIGHT", window.fgpsClose, "LEFT", -2, 0)
    local function raiseCog()
        if cog.SetFrameLevel and window.fgpsClose.GetFrameLevel then cog:SetFrameLevel(window.fgpsClose:GetFrameLevel()) end
    end
    raiseCog()
    if window.HookScript then window:HookScript("OnShow", raiseCog) end
    if Frames().Tooltip then pcall(Frames().Tooltip, cog, L["Settings"]) end
    window.fgpsSettings = cog
    local content, top = contentFrame(window)
    window.fgpsContent = content


    window.fgpsTabs = {}
    local previous
    for _, key in ipairs(TABS) do
        local button = markButton(makeButton(content, L[TAB_LABELS[key]], function() Search:SetTab(key) end, TAB_WIDTH[key], 24))
        if previous then button:SetPoint("LEFT", previous, "RIGHT", 2, 0)
        else button:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -top) end
        window.fgpsTabs[key] = button
        previous = button
    end


    local edit = makeEditBox(content, {
        width = 410, height = 26, maxLetters = 80,
        placeholder = L["Town, NPC, or 42.5 65.1"],
        onChanged = function(_, text, userInput)
            if userInput == false then return end
            if Search.tab == "poi" then
                Search:ScheduleListFilter(text or "")
                return
            end
            Search:ScheduleSearch(text or "")
        end,
        onEnter = function(_, text)
            if Search.tab ~= "poi" and Search.ParseCoordinates(text) then Search:GoToCoordinates(text) return end
            Search:Activate()
        end,
        onEscape = function() Search:Hide() end,
        keepFocusOnEnter = true,
    })
    edit:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(top + 28))
    edit:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(top + 28))
    if edit.SetHeight then edit:SetHeight(26) end


    edit:SetScript("OnArrowPressed", function(_, key) Search:HandleKey(key) end)
    edit:SetScript("OnTabPressed", function()
        Search:CycleTab(IsShiftKeyDown and IsShiftKeyDown() and -1 or 1)
    end)
    window.fgpsEdit = edit


    local listAnchor = CreateFrame("Frame", nil, content)
    listAnchor:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(top + 58))
    listAnchor:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 78)
    window.fgpsListAnchor = listAnchor
    local list = makeList(listAnchor, ROW_HEIGHT, Search.RenderRow, onRowClick)
    if list and list.SetAllPoints then list:SetAllPoints(listAnchor) end
    Search.DressList(list)
    Search.list = list


    local status = makeLabel(content, "small", "", "textDim")
    status:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 6, 64)
    status:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -6, 64)
    window.fgpsStatus = status


    local hint = makeLabel(content, "small", L[Search.SERVICES_HINT], "textDim")
    hint:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 6, 32)
    hint:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -6, 32)
    if hint.SetWordWrap then hint:SetWordWrap(true) end
    if hint.SetJustifyV then hint:SetJustifyV("BOTTOM") end
    hint:Hide()
    window.fgpsHint = hint


    local tip = makeLabel(content, "small", L["Tip: type 42.5 65.1 to go to map coordinates"], "textDim")
    tip:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 4, 36)
    tip:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -4, 36)
    tip:Hide()
    window.fgpsCoordTip = tip






    local questPanel = makeButton(content, L["Open the quest panel"], function()
        local QuestPanel = FGPS.UI.QuestPanel
        if not (QuestPanel and QuestPanel.Show) then
            FGPS:Print(L["The quest panel is not available right now."])
            return
        end

        local item = Search.items[Search.selectedIndex]
        local questID = type(item) == "table" and item.kind == "quest" and type(item.quest) == "table"
            and item.quest.questID or nil
        Search:Hide()
        if questID and QuestPanel.ShowQuest then
            QuestPanel:ShowQuest(questID)
        else
            QuestPanel:Show()
        end
    end, 200, 22)
    questPanel:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 2, 34)
    questPanel:Hide()
    window.fgpsQuestPanel = questPanel





    local specs = {
        { key = "start", label = "Start", width = 76, fn = function() Search:Act("start") end },
        { key = "addStop", label = "Add stop", width = 74, fn = function() Search:Act("addStop") end },
        { key = "favorite", label = "Favorite", width = 74, fn = function() Search:ToggleFavorite() end },
        { key = "preview", label = "Show route", width = 80, fn = function() Search:Act("showRoute") end },
    }
    window.fgpsButtons = {}
    previous = nil
    for _, spec in ipairs(specs) do
        local button = makeButton(content, L[spec.label], spec.fn, spec.width, 24)
        if previous then button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else button:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 2, 2) end
        window.fgpsButtons[spec.key] = button
        previous = button
    end
    local clear = makeButton(content, L["Clear route"], function() Search:ClearAll() end, 90, 24)
    clear:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -2, 2)
    if F.Tooltip then
        pcall(F.Tooltip, clear, L["Removes the route, the preview, every stop and their markers. Nothing stays set."])
    end
    window.fgpsButtons.clear = clear
    if F.ApplySkin then pcall(F.ApplySkin, window) end
    return window
end

function Search:EnsureWindow()
    if self.window then return self.window end
    self.window = buildWindow()
    if self.window then
        self.filter = "towns"
        self:SetTab(self.tab)
    end
    return self.window
end





function Search:Show(opts)
    local window = self:EnsureWindow()
    if not window then
        FGPS:Print(L["The search window is unavailable; use /cabbie go <x> <y> [zone] instead."])
        return false
    end
    opts = opts or {}
    self.addStopMode = opts.mode == "addStop"


    local dock = opts.dock
    if not dock and self.docked and window:IsShown() then dock = self.dockFrame end
    self:ApplyDock(window, dock)
    window:Show()
    self:UpdateClearButton()
    if opts.query then
        self.query = opts.query
        window.fgpsEdit:SetText(opts.query)
    else

        self.query = ""
        window.fgpsEdit:SetText("")
    end
    if opts.tab then
        self:SetTab(opts.tab)
    elseif opts.query and self.tab ~= "search" then
        self:SetTab("search")
    else
        self:Refresh()
    end


    if window.fgpsEdit.SetFocus and self.tab == "search" and not opts.noFocus then window.fgpsEdit:SetFocus() end
    return true
end





function Search:ApplyDock(window, dock)
    if type(dock) == "table" and dock.GetRight then
        local screen = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
        local ratio = 1
        if dock.GetEffectiveScale and UIParent and UIParent.GetEffectiveScale then
            local mine, theirs = UIParent:GetEffectiveScale(), dock:GetEffectiveScale()
            if type(mine) == "number" and mine > 0 and type(theirs) == "number" then ratio = theirs / mine end
        end
        local right = (dock:GetRight() or 0) * ratio
        window:ClearAllPoints()
        if right + (window:GetWidth() or 0) + 8 <= screen then
            window:SetPoint("TOPLEFT", dock, "TOPRIGHT", 4, 0)
            self.dockedInside = false
        else
            window:SetPoint("TOPRIGHT", dock, "TOPRIGHT", -12, -64)
            self.dockedInside = true
        end


        window.fgpsEscape = true
        if window.SetFrameStrata then pcall(window.SetFrameStrata, window, "FULLSCREEN_DIALOG") end
        self.docked = true
        self.dockFrame = dock
    elseif self.docked then
        self.docked = false
        self.dockFrame = nil
        self.dockedInside = nil
        window.fgpsEscape = true
        if window.SetFrameStrata then pcall(window.SetFrameStrata, window, "HIGH") end
        if window.RestorePosition then window:RestorePosition() end
    end
end

function Search:Hide()
    if self.window and self.window:IsShown() then self.window:Hide() end
    self.addStopMode = false
end

function Search:OnWindowHidden()
    Search.listKeysArmed = false
    self:CancelServiceSearch()
    self.addStopMode = false
    self.serviceResults = nil
    local window = self.window
    local wasDocked = self.docked
    self.docked = false
    self.dockFrame = nil
    self.dockedInside = nil
    if window then
        window.fgpsEscape = true
        if wasDocked then
            if window.SetFrameStrata then pcall(window.SetFrameStrata, window, "HIGH") end
            if window.RestorePosition then window:RestorePosition() end
        end
        if window.fgpsEdit and window.fgpsEdit.ClearFocus then window.fgpsEdit:ClearFocus() end
    end
end

function Search:IsShown()
    return self.window ~= nil and self.window:IsShown()
end

function Search:Toggle()
    if self:IsShown() then self:Hide() else self:Show() end
end







function Search:UpdateClearButton()
    local button = self.window and self.window.fgpsButtons and self.window.fgpsButtons.clear
    if not button then return false end
    local Navigator = FGPS.Navigator
    local set = false
    if Navigator and Navigator.HasAnythingSet then
        local ok, result = pcall(Navigator.HasAnythingSet, Navigator)
        set = ok and result == true
    end
    if set ~= button:IsEnabled() then setButtonEnabled(button, set) end
    return set
end

function Search:ClearAll()
    local Navigator = FGPS.Navigator
    if Navigator and Navigator.Clear then Navigator:Clear("user") end

    self.addStopMode = false
    self:UpdateClearButton()
end




local function onListsChanged(event)
    if not Search:IsShown() then return end
    if (event == "FAVORITES_CHANGED" and Search.tab == "favorites") or (event == "RECENTS_CHANGED" and Search.tab == "recent") then
        Search:Refresh()
    end
end

function Search:Init()
    if self.eventsBound then return end
    self.eventsBound = true
    local Events = FGPS.Events
    Events:Register("FAVORITES_CHANGED", onListsChanged, self)
    Events:Register("RECENTS_CHANGED", onListsChanged, self)
    Events:Register("SETTINGS_CHANGED", function(_, key)
        if key == "preset" or key == "accessibility.colorScheme" or key == "*" then Search.RefreshStraightFlag() end
        if (key == "units" or key == "preset" or key == "accessibility.colorScheme" or key == "*")
            and Search:IsShown() then Search:Refresh() end
    end, self)
    Events:Register("UI_PRESET_APPLIED", function()
        Search.RefreshStraightFlag()
        if Search:IsShown() then Search:Refresh() end
    end, self)
    Search.RefreshStraightFlag()


    local function onSetStateChanged() if Search:IsShown() then Search:UpdateClearButton() end end
    for _, event in ipairs({ "ITINERARY_CHANGED", "NAV_STATE", "ROUTE_PREVIEW", "NAV_CANCELLED" }) do
        Events:Register(event, onSetStateChanged, self)
    end
    FGPS.Slash.Register("search", function(args)
        Search:Show({ query = Util.Trim(args) ~= "" and Util.Trim(args) or nil })
    end, L["Open the destination search (optionally with a query)"])
end
