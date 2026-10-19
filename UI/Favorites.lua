




local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local type, ipairs, pairs, tostring, tonumber, format = type, ipairs, pairs, tostring, tonumber, string.format

local Favorites = {
    window = nil,
    list = nil,
    items = {},
    selectedIndex = 0,
}
FGPS.UI.Favorites = Favorites

local WINDOW_KEY = "favorites"
local ROW_HEIGHT = 20




local function Frames() return FGPS.UI.Frames end

local FALLBACK_FONTS = { small = "GameFontHighlightSmall", normal = "GameFontHighlight", large = "GameFontNormalLarge", title = "GameFontNormalLarge" }

local function makeLabel(parent, kind, text, color)
    local F = Frames()
    if F and F.CreateLabel then
        local ok, fs = pcall(F.CreateLabel, parent, text, { kind = kind, color = color })
        if ok and fs then return fs end
    end
    local fs = parent:CreateFontString(nil, "OVERLAY", FALLBACK_FONTS[kind] or "GameFontHighlightSmall")
    fs:SetText(text or "")
    fs:SetJustifyH("LEFT")
    if color == "textDim" then fs:SetTextColor(0.6, 0.6, 0.6) elseif color == "title" then fs:SetTextColor(1, 0.82, 0) end
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
    box:SetMaxLetters(opts.maxLetters or 60)
    box:SetTextInsets(6, 6, 0, 0)
    box:SetScript("OnEnterPressed", function(self) if opts.onEnter then opts.onEnter(self, self:GetText()) end self:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
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
    return content, (content == window) and 30 or 0
end

local function describe(dest)
    local Destinations = FGPS.Destinations
    if Destinations and Destinations.Describe then
        local ok, text = pcall(Destinations.Describe, dest)
        if ok and type(text) == "string" and text ~= "" then return text end
    end
    if type(dest) ~= "table" then return "?" end
    if dest.zoneName then return (dest.name or L["Map position"]) .. " - " .. dest.zoneName end
    return dest.name or L["Map position"]
end

local function distanceText(dest)
    local Search = FGPS.UI.Search
    if Search and Search.DistanceText then return Search.DistanceText(dest) end
    return ""
end





function Favorites.BuildItems(favorites, recents)
    local items = { { kind = "header", label = L["Favorites"] } }
    if #favorites == 0 then items[#items + 1] = { kind = "empty", label = L["No favorites yet. Star a place in Search, or right-click a town on the map."] } end
    for i, dest in ipairs(favorites) do
        items[#items + 1] = { kind = "favorite", index = i, dest = dest, label = describe(dest), right = distanceText(dest) }
    end
    items[#items + 1] = { kind = "header", label = L["Recent"] }
    if #recents == 0 then items[#items + 1] = { kind = "empty", label = L["No recent destinations."] } end
    for i, dest in ipairs(recents) do
        items[#items + 1] = { kind = "recent", index = i, dest = dest, label = describe(dest), right = distanceText(dest) }
    end
    return items
end

function Favorites:Refresh()
    if not self.window then return end
    local Destinations = FGPS.Destinations
    local favorites = Destinations and Destinations.Favorites and Destinations.Favorites() or {}
    local recents = Destinations and Destinations.Recents and Destinations.Recents() or {}
    self.items = Favorites.BuildItems(favorites, recents)
    local current = self.items[self.selectedIndex]
    if not current or not current.dest then self.selectedIndex = 0 end
    self:UpdateControls()
    setListItems(self.list, self.items)
    if self.list and self.list.SetSelected then self.list:SetSelected(self.selectedIndex > 0 and self.selectedIndex or nil) end
end

function Favorites:Selected()
    return self.items[self.selectedIndex]
end

function Favorites:UpdateControls()
    local w = self.window
    if not w then return end
    local item = self:Selected()
    local hasDest = item ~= nil and item.dest ~= nil
    local isFavorite = hasDest and item.kind == "favorite"
    for key, button in pairs(w.fgpsButtons) do
        if key == "clear" then
            setButtonEnabled(button, true)
        elseif key == "rename" or key == "remove" then
            setButtonEnabled(button, isFavorite)
        else
            setButtonEnabled(button, hasDest)
        end
    end
    if isFavorite then
        w.fgpsRename:SetText(item.dest.name or "")
    else
        w.fgpsRename:SetText("")
    end
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
end

local function applyRowColor(fs, key)
    local skin = FGPS.UI and FGPS.UI.Skins and FGPS.UI.Skins.Current and FGPS.UI.Skins.Current()
    local c = skin and skin.colors and skin.colors[key]
    if c then
        fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end
end

function Favorites.RenderRow(row, item, index)
    ensureRowWidgets(row)
    row.item = item
    row.text:SetText(item.label or "")
    row.right:SetText(item.right or "")
    if item.kind == "header" then
        applyRowColor(row.text, "title")
    elseif item.kind == "empty" then
        applyRowColor(row.text, "textDim")
    else
        applyRowColor(row.text, "text")
    end
    applyRowColor(row.right, "textDim")
    row:SetScript("OnDoubleClick", function() if item.dest then Favorites:Go() end end)
end

local function onRowClick(item, index)
    if type(item) ~= "table" or not item.dest then return end
    Favorites.selectedIndex = index
    Favorites:UpdateControls()
end




local function goTo(dest, mode)
    local Search = FGPS.UI.Search
    if Search and Search.GoTo then return Search.GoTo(dest, mode) end
    local Navigator = FGPS.Navigator
    if not Navigator or not Navigator.SetDestination then return false end
    if mode == "addStop" then
        if Navigator.AddStop then Navigator:AddStop(dest) else Navigator:SetDestination(dest, { addStop = true }) end
        return true
    end


    local journey = Navigator.IsJourney and Navigator:IsJourney()
    Navigator:SetDestination(dest, { start = false })
    if not journey and Navigator.Preview then Navigator:Preview() end
    return true
end

function Favorites:Go()
    local item = self:Selected()
    if not item or not item.dest then return false end
    if goTo(item.dest) then self:Hide() return true end
    return false
end

function Favorites:AddStop()
    local item = self:Selected()
    if not item or not item.dest then return false end
    return goTo(item.dest, "addStop")
end

function Favorites:Remove()
    local Destinations = FGPS.Destinations
    local item = self:Selected()
    if not item or item.kind ~= "favorite" or not Destinations or not Destinations.RemoveFavorite then return false end
    Destinations.RemoveFavorite(item.index)
    FGPS:Print(L["Removed from favorites: %s"], item.label or "?")
    self.selectedIndex = 0
    self:Refresh()
    return true
end



function Favorites:Rename(newName)
    local Destinations = FGPS.Destinations
    local item = self:Selected()
    newName = Util.Trim(newName or "")
    if not item or item.kind ~= "favorite" or newName == "" then return false end
    if Destinations and Destinations.RenameFavorite then
        Destinations.RenameFavorite(item.index, newName)
    else
        item.dest.name = newName
        local saved = FGPS.DB and FGPS.DB.account and FGPS.DB.account.favorites
        if type(saved) == "table" then
            local entry = saved[item.index]
            if type(entry) == "table" and entry ~= item.dest then
                local same = Destinations and Destinations.Equal and Destinations.Equal(entry, item.dest)
                if same or (entry.x == item.dest.x and entry.y == item.dest.y and entry.inst == item.dest.inst) then
                    entry.name = newName
                end
            end
        end
        FGPS.Events:Fire("FAVORITES_CHANGED")
    end
    FGPS:Print(L["Favorite renamed to %s."], newName)
    self:Refresh()
    return true
end

function Favorites:ClearRecents()
    local Destinations = FGPS.Destinations
    local now = (GetTime and GetTime()) or 0
    if not self.clearRecentsArmedAt or (now - self.clearRecentsArmedAt) > 5 then
        self.clearRecentsArmedAt = now
        FGPS:Print(L["Click Clear recents again to confirm."])
        return false
    end
    self.clearRecentsArmedAt = nil
    if Destinations and Destinations.ClearRecents then
        Destinations.ClearRecents()
        FGPS:Print(L["Recent destinations cleared."])
    end
    self.selectedIndex = 0
    self:Refresh()
    return true
end




local function buildWindow()
    local F = Frames()
    if not F or not F.CreateWindow then
        FGPS.Log:Error("UI.Frames.CreateWindow is unavailable; the favorites window cannot be built")
        return nil
    end
    local ok, window = pcall(F.CreateWindow, WINDOW_KEY, { title = L["Favorites and recent destinations"], width = 420, height = 440 })
    if not ok or type(window) ~= "table" then
        FGPS.Log:Error("Frames.CreateWindow failed: %s", tostring(window))
        return nil
    end
    local content, top = contentFrame(window)
    local listAnchor = CreateFrame("Frame", nil, content)
    listAnchor:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -(top + 2))
    listAnchor:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -2, 62)
    local list = makeList(listAnchor, ROW_HEIGHT, Favorites.RenderRow, onRowClick)
    if list and list.SetAllPoints then list:SetAllPoints(listAnchor) end
    Favorites.list = list

    local rename = makeEditBox(content, {
        width = 250, height = 22, maxLetters = 60, placeholder = L["New name"],
        onEnter = function(_, text) Favorites:Rename(text) end,
    })
    rename:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 2, 32)

    rename:Show()
    window.fgpsRename = rename
    local renameButton = makeButton(content, L["Rename"], function() Favorites:Rename(rename:GetText()) end, 80, 22)
    renameButton:SetPoint("LEFT", rename, "RIGHT", 6, 0)

    local specs = {
        { key = "go", label = "Go", fn = function() Favorites:Go() end },
        { key = "addStop", label = "Add stop", fn = function() Favorites:AddStop() end },
        { key = "remove", label = "Remove", fn = function() Favorites:Remove() end },
        { key = "clear", label = "Clear recents", fn = function() Favorites:ClearRecents() end },
    }
    window.fgpsButtons = { rename = renameButton }
    local previous
    for _, spec in ipairs(specs) do
        local button = makeButton(content, L[spec.label], spec.fn, 96, 22)
        if previous then button:SetPoint("LEFT", previous, "RIGHT", 4, 0) else button:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 2, 2) end
        window.fgpsButtons[spec.key] = button
        previous = button
    end
    if F.ApplySkin then pcall(F.ApplySkin, window) end
    return window
end

function Favorites:EnsureWindow()
    if self.window then return self.window end
    self.window = buildWindow()
    return self.window
end

function Favorites:Show()
    local window = self:EnsureWindow()
    if not window then return false end


    self.selectedIndex = 0
    window:Show()
    self:Refresh()
    return true
end

function Favorites:Hide()
    if self.window and self.window:IsShown() then self.window:Hide() end
end

function Favorites:IsShown()
    return self.window ~= nil and self.window:IsShown()
end

function Favorites:Toggle()
    if self:IsShown() then self:Hide() else self:Show() end
end




local function currentDestination()
    local Navigator = FGPS.Navigator
    if Navigator and Navigator.GetStops then
        local ok, stops = pcall(Navigator.GetStops, Navigator)
        if ok and type(stops) == "table" and #stops > 0 then return stops[#stops] end
    end
    local char = FGPS.DB and FGPS.DB.char
    return char and char.lastDestination or nil
end

local function slashFav(args)
    local Destinations = FGPS.Destinations
    local word, rest = Util.Trim(args):match("^(%S*)%s*(.-)$")
    word = Util.Lower(word or "")
    if word == "add" then
        local dest = currentDestination()
        if not dest or not Destinations or not Destinations.AddFavorite then
            FGPS:Print(L["No current destination to add. Set a destination first."])
            return
        end
        if rest ~= "" then dest = Util.ShallowCopy(dest) dest.name = rest end
        local ok, reason = Destinations.AddFavorite(dest)
        if ok == false then
            FGPS:Print(L["Could not add favorite (%s)."], tostring(reason))
        else
            FGPS:Print(L["Added to favorites: %s"], describe(dest))
        end
    elseif word == "list" then
        local list = Destinations and Destinations.Favorites and Destinations.Favorites() or {}
        if #list == 0 then FGPS:Print(L["No favorites yet."]) return end
        for i, dest in ipairs(list) do FGPS:Print("  %d. %s", i, describe(dest)) end
    elseif word == "remove" then
        local index = tonumber(rest)
        if not index or not Destinations or not Destinations.RemoveFavorite then
            FGPS:Print(L["Usage: /cabbie fav remove <number> (see /cabbie fav list)"])
            return
        end
        Destinations.RemoveFavorite(index)
        FGPS:Print(L["Favorite %d removed."], index)
    elseif word ~= "" then

        local needle = Util.Lower(Util.Trim(args))
        local list = Destinations and Destinations.Favorites and Destinations.Favorites() or {}
        for _, dest in ipairs(list) do
            if Util.Lower(dest.name or ""):find(needle, 1, true) then
                goTo(dest)
                return
            end
        end
        FGPS:Print(L["No favorite matches '%s'."], Util.Trim(args))
    else
        Favorites:Toggle()
    end
end

local function slashRecent(args)
    local word = Util.Lower(Util.Trim(args))
    if word == "clear" then
        Favorites:ClearRecents()
    else
        Favorites:Show()
    end
end

function Favorites:Init()
    if self.eventsBound then return end
    self.eventsBound = true
    local Events = FGPS.Events
    Events:Register("FAVORITES_CHANGED", function() if Favorites:IsShown() then Favorites:Refresh() end end, self)
    Events:Register("RECENTS_CHANGED", function() if Favorites:IsShown() then Favorites:Refresh() end end, self)
    FGPS.Slash.Register("fav", slashFav, L["Favorites window; fav add [name]|list|remove <n>|<name>"])
    FGPS.Slash.Register("recent", slashRecent, L["Recent destinations; recent clear"])
end
