











local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local type, ipairs, tostring, tonumber = type, ipairs, tostring, tonumber

local Favorites = {
    items = { favorites = {}, recent = {} },
    renaming = nil,
}
FGPS.UI.Favorites = Favorites


Favorites.SECTIONS = { "favorites", "recent" }
local HEAD_HEIGHT, HINT_HEIGHT, MAX_NAME = 16, 14, 60

local function Look() return FGPS.UI.Look end
local function places() return FGPS.UI.Search end

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
    local Search = places()
    if Search and Search.DistanceText then return Search.DistanceText(dest) end
    return ""
end



local function isPlace(entry)
    return type(entry) == "table" and type(entry.x) == "number" and type(entry.y) == "number"
end

local function samePlace(a, b)
    if a == b then return true end
    local Destinations = FGPS.Destinations
    return Destinations ~= nil and Destinations.Equal ~= nil and Destinations.Equal(a, b) and true or false
end

local function isFavorite(dest)
    local Destinations = FGPS.Destinations
    return Destinations ~= nil and Destinations.IsFavorite ~= nil and Destinations.IsFavorite(dest) and true or false
end

local function savedList(key)
    local Destinations = FGPS.Destinations
    local read = Destinations and (key == "favorites" and Destinations.Favorites or Destinations.Recents)
    local list = read and read() or nil
    return type(list) == "table" and list or {}
end






local function itemsOf(list, key)
    local items = {}
    for i, dest in ipairs(type(list) == "table" and list or {}) do
        if isPlace(dest) then
            items[#items + 1] = { kind = "dest", section = key, index = i, dest = dest,
                label = describe(dest), right = distanceText(dest) }
        end
    end
    return items
end



function Favorites.BuildItems(favorites, recents)
    return { favorites = itemsOf(favorites, "favorites"), recent = itemsOf(recents, "recent") }
end




local function goTo(dest, mode)
    local Search = places()
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


function Favorites:Add(dest)
    local Search = places()
    if not (isPlace(dest) and Search and Search.ToggleFavorite) or isFavorite(dest) then return false end
    return Search:ToggleFavorite(dest)
end


function Favorites:Remove(dest)
    local Destinations = FGPS.Destinations
    if not (isPlace(dest) and Destinations and Destinations.IsFavorite and Destinations.RemoveFavorite) then return false end
    local index = Destinations.IsFavorite(dest)
    if not index then return false end
    local label = describe(dest)
    if not Destinations.RemoveFavorite(index) then return false end
    FGPS:Print(L["Removed from favorites: %s"], label)
    return true
end




function Favorites:Rename(dest, newName)
    local Destinations = FGPS.Destinations
    newName = Util.Trim(type(newName) == "string" and newName or "")
    if newName == "" or not isPlace(dest) or not (Destinations and Destinations.IsFavorite) then return false end
    local index = Destinations.IsFavorite(dest)
    local saved = index and savedList("favorites")[index] or nil
    if not isPlace(saved) then return false end
    saved.name = newName
    dest.name = newName
    FGPS.Events:Fire("FAVORITES_CHANGED")
    FGPS:Print(L["Favorite renamed to %s."], newName)
    return true
end



function Favorites:BeginRename(dest)
    local Search = places()
    if not (isPlace(dest) and isFavorite(dest) and Search and Search.RefreshSections) then return false end
    self.renaming = dest
    Search:RefreshSections()
    local box = self.renameBox
    if not (box and box:IsShown()) then
        self.renaming = nil
        return false
    end
    box:SetText(type(dest.name) == "string" and dest.name or "")
    box:SetFocus()
    if box.HighlightText then box:HighlightText() end
    return true
end


function Favorites:EndRename()
    if not self.renaming then return false end
    self.renaming = nil
    local box = self.renameBox
    if box then
        if box.ClearFocus then box:ClearFocus() end
        box:Hide()
    end
    local Search = places()
    if Search and Search.RefreshSections then Search:RefreshSections() end
    return true
end



function Favorites:ClearRecents()
    local Destinations = FGPS.Destinations
    if not (Destinations and Destinations.ClearRecents) then return false end
    Destinations.ClearRecents()
    FGPS:Print(L["Recent destinations cleared."])
    return true
end





function Favorites.OpenRowMenu(owner, item)
    local Menus, Search = FGPS.UI.Menus, places()
    if not (Menus and Menus.OpenRowMenu and Search) or type(item) ~= "table" or not isPlace(item.dest) then return nil end
    local dest = item.dest
    local entries = {
        { label = L["Go"], onClick = function() Search.GoTo(dest, "start", { quiet = true }) end },
        { label = L["Add as a Stop"], onClick = function() Search.GoTo(dest, "addStop") end },
    }
    if item.section == "favorites" then
        entries[3] = { label = L["Rename"], onClick = function() Favorites:BeginRename(dest) end }
        entries[4] = { label = L["Remove from Favorites"], onClick = function() Favorites:Remove(dest) end,
            destructive = true }
    else
        entries[3] = { label = L["Add to Favorites"], onClick = function() Favorites:Add(dest) end,
            disabled = function() return isFavorite(dest) end }
        entries[4] = { label = L["Clear Recent"], onClick = function() Favorites:ClearRecents() end,
            destructive = true }
    end
    return Menus.OpenRowMenu(owner, {
        title = type(dest.name) == "string" and dest.name or describe(dest),
        entries = entries,
    })
end

local function openRowMenu(row, item) return Favorites.OpenRowMenu(row, item) end




local function pageText(parent, role, color)
    local look = Look()
    local text = parent:CreateFontString(nil, "OVERLAY", look.Font(role))
    text:SetTextColor(look.Color(color))
    text:SetJustifyH("LEFT")
    if text.SetWordWrap then text:SetWordWrap(false) end
    return text
end

local function headOf(key)
    if key == "favorites" then return L["Favorites"] end
    return L["Recent"]
end

local function hintOf(key)
    if key == "favorites" then return L["Right-click any place and choose Add to Favorites."] end
    return L["No recent destinations."]
end



local function newRenameBox(frame)
    local box = Look().EditBox(frame, { "InputBoxTemplate" })
    if box.SetMaxLetters then box:SetMaxLetters(MAX_NAME) end
    box:SetScript("OnEnterPressed", function(self)
        local dest, text = Favorites.renaming, self:GetText()
        Favorites:EndRename()
        if dest then Favorites:Rename(dest, text) end
    end)
    box:SetScript("OnEscapePressed", function() Favorites:EndRename() end)
    box:HookScript("OnEditFocusLost", function() Favorites:EndRename() end)
    box:Hide()
    return box
end

local function paintSection(f, key)
    local Search = places()
    local tokens = Look().TOKENS
    local width = Search.PageWidth()
    local items = itemsOf(savedList(key), key)
    Favorites.items[key] = items


    local page = Search.placesPage
    if page and page.picked == key then
        local still = false
        for _, item in ipairs(items) do
            if Search:IsPicked(item.dest, key) then still = true break end
        end
        if not still then Search:Unpick(key) end
    end
    local renaming = key == "favorites" and Favorites.renaming or nil
    local renameRow
    local y = HEAD_HEIGHT
    for i, item in ipairs(items) do
        local row = f.Rows[i]
        if not row then
            row = Search.NewPlaceRow(f, key, openRowMenu)
            f.Rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
        row:SetSize(width, tokens.rowPlace)
        Search.PaintPlaceRow(row, item, width)
        Search.PaintPick(row)
        local covered = renaming ~= nil and renameRow == nil and samePlace(item.dest, renaming)
        if covered then renameRow = row end
        row.Name:SetShown(not covered)
        row.Zone:SetShown(not covered)
        row.Right:SetShown(not covered)
        row:Show()
        y = y + tokens.rowPlace
    end
    for i = #items + 1, #f.Rows do
        f.Rows[i].entry = nil
        f.Rows[i]:Hide()
    end
    local box = f.Rename
    if box then
        if renameRow then
            local inset = tokens.iconBox + tokens.gap
            box:ClearAllPoints()
            box:SetPoint("TOPLEFT", renameRow, "TOPLEFT", inset, 0)
            box:SetSize(math.max(1, width - inset), tokens.rowPlace)

            if box.SetFrameLevel and renameRow.GetFrameLevel then box:SetFrameLevel(renameRow:GetFrameLevel() + 2) end
            box:Show()
        else

            Favorites.renaming = nil
            if box:IsShown() then
                if box.ClearFocus then box:ClearFocus() end
                box:Hide()
            end
        end
    end
    if #items == 0 then
        f.Hint:ClearAllPoints()
        f.Hint:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
        f.Hint:SetWidth(width)
        f.Hint:Show()
        y = y + HINT_HEIGHT
    else
        f.Hint:Hide()
    end
    return y
end



local function sectionBuilder(key)
    return function(frame)
        frame.Head = pageText(frame, "pageSub", "rubric")
        frame.Head:SetText(headOf(key))
        frame.Head:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.Head:SetHeight(HEAD_HEIGHT)
        frame.Hint = pageText(frame, "pageSub", "inkGrey")
        frame.Hint:SetText(hintOf(key))
        frame.Hint:SetHeight(HINT_HEIGHT)
        frame.Hint:Hide()
        frame.Rows = {}
        if key == "favorites" then
            Favorites.renaming = nil
            frame.Rename = newRenameBox(frame)
            Favorites.renameBox = frame.Rename
        end
        return function(f) return paintSection(f, key) end
    end
end





function Favorites:Show(section)
    local Search = places()
    if not (Search and Search.Show) then return false end
    return Search:Show({ section = section == "recent" and "recent" or "favorites" })
end

function Favorites:Hide()
    local Search = places()
    if Search and Search.IsShown and Search:IsShown() then Search:Hide() end
end


function Favorites:IsShown()
    local Search = places()
    return Search ~= nil and Search.IsShown ~= nil and Search:IsShown() and true or false
end

function Favorites:Toggle(section)
    if self:IsShown() then
        self:Hide()
        return false
    end
    return self:Show(section)
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
            local Compat = FGPS.UI.Compat
            local why = Compat and Compat.ReasonText and Compat.ReasonText(reason, L["unknown reason"])
                or tostring(reason or L["unknown reason"])
            FGPS:Print(L["Could not add favorite (%s)."], why)
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
        if Destinations.RemoveFavorite(index) then
            FGPS:Print(L["Favorite %d removed."], index)
        else
            FGPS:Print(L["No favorite %d; see /cabbie fav list."], index)
        end
    elseif word ~= "" then


        local needle = Util.Lower(Util.Trim(args))
        local list = Destinations and Destinations.Favorites and Destinations.Favorites() or {}
        for _, dest in ipairs(list) do
            if type(dest) == "table" and Util.Lower(dest.name or "") == needle then goTo(dest) return end
        end
        if needle:match("^%d+$") then
            local dest = list[tonumber(needle)]
            if type(dest) == "table" then goTo(dest) return end
        end
        for _, dest in ipairs(list) do
            if type(dest) == "table" and Util.Lower(dest.name or ""):find(needle, 1, true) then goTo(dest) return end
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
        Favorites:Show("recent")
    end
end



function Favorites:Init()
    if self.initialised then return end
    self.initialised = true
    local Search = places()
    if Search and Search.AddSection and Search.SECTION_ORDER then
        for _, key in ipairs(Favorites.SECTIONS) do
            Search:AddSection(key, Search.SECTION_ORDER[key], sectionBuilder(key))
        end
    end
    FGPS.Slash.Register("fav", slashFav, L["Favorites on the Places page; fav add [name]|list|remove <n>|<name>"])
    FGPS.Slash.Register("recent", slashRecent, L["Recent destinations; recent clear"])
end
