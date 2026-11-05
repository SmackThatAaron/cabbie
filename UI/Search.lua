






































local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local type, ipairs, pairs, tostring, tonumber, format = type, ipairs, pairs, tostring, tonumber, string.format


local function resultsText(n)
    return format(n == 1 and L["%d result"] or L["%d results"], n)
end

local Search = {
    filter = "towns",
    query = "",
    only = nil,
    items = {},
    selectedIndex = 0,
    addStopMode = false,
    routesAsked = 0,
    serviceResults = nil,
    serviceQuery = nil,
    searchGeneration = 0,
    pendingQuery = nil,
}
FGPS.UI.Search = Search














Search.placesPage = { sections = {}, selected = nil, picked = nil }
local page = Search.placesPage

Search.PAGE = "places"
Search.PAGE_ICON = "Interface\\Icons\\INV_Misc_Map_01"
local DEBOUNCE_SECONDS = 0.15
local RESULT_LIMIT = 25
local MIN_QUERY = 2


local BOX_HEIGHT, STATUS_HEIGHT, HEAD_HEIGHT = 22, 14, 16
local RIGHT_SHARE = 0.32



Search.SECTION_ORDER = { nearest = 10, ornament = 15, favorites = 20, recent = 30, matches = 1000 }
local BREAK_FILE, BREAK_HEIGHT = "Interface\\QuestFrame\\UI-HorizontalBreak", 16
local WHEEL_ROWS = 3

Search.NEAREST = { "inn", "flightmaster", "bank", "mailbox" }




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




local function isLiftLanding(dest)
    local P = FGPS.Data and FGPS.Data.poi
    local src = P and P.src and type(dest) == "table" and dest.poiIndex and P.src[dest.poiIndex]
    local id = type(src) == "string" and src:match("^transport:(%d+):stop:%d+$")
    local records = id and FGPS.Data.transports
    local rec = records and records[tonumber(id)]
    return type(rec) == "table" and rec.kind == "elevator"
end






local KINDS = {
    { key = "towns", label = "Towns", types = { 5, 1, 2 } },
    { key = "dungeons", label = "Dungeons", types = { 3, 4 }, insideFirst = true },
    { key = "travel", label = "Travel", types = { 6, 14, 15, 17 }, skip = isLiftLanding },
    { key = "vendor", label = "Vendors", types = { 8 }, nearest = "vendor" },
    { key = "repair", label = "Repair", types = { 9 }, nearest = "repair" },
    { key = "inn", label = "Inn", types = { 7 }, nearest = "inn" },
    { key = "mailbox", label = "Mailbox", types = { 10 }, nearest = "mailbox" },
    { key = "bank", label = "Bank", types = { 11 }, nearest = "bank" },
    { key = "auction", label = "Auction House", types = { 12 }, nearest = "auction" },
    { key = "trainer", label = "Trainer", service = "trainer", nearest = "trainer" },
    { key = "weapons", label = "Weapon Master", service = "trainer:weapons", nearest = "trainer:weapons",
      inTrainerMenu = true },
    { key = "stable", label = "Stable Master", types = { 20 }, nearest = "stable" },
    { key = "graveyard", label = "Graveyard", types = { 16 } },
}
Search.KINDS = KINDS



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





local function kindAt(key)
    for _, kind in ipairs(KINDS) do
        if kind.key == key then return kind end
    end
    local sub = type(key) == "string" and key:match("^trainer:(.+)$")
    if not sub or sub == "weapons" or not (TRAINER_LABELS[sub] or sub:match("^%u+$")) then return nil end
    return { key = key, label = trainerKindLabel(sub), named = true, service = key, nearest = key }
end
local function kindLabel(kind)
    return kind.named and kind.label or L[kind.label]
end




Search.STRAIGHT_FLAG_TEXT = "(open ground)"
Search.STRAIGHT_FLAG = "|cffffa633" .. Search.STRAIGHT_FLAG_TEXT .. "|r"

Search.REFUSED_SECONDS = 4

function Search.RefreshStraightFlag()
    local Skins = FGPS.UI.Skins
    local ok, skin = pcall(function() return Skins and Skins.Current and Skins.Current() end)
    local c = ok and type(skin) == "table" and type(skin.colors) == "table" and skin.colors.routeUnverified or nil
    if type(c) ~= "table" then return Search.STRAIGHT_FLAG end
    local function byte(v) return math.floor(Util.Clamp(v or 1, 0, 1) * 255 + 0.5) end
    Search.STRAIGHT_FLAG = format("|cff%02x%02x%02x%s|r", byte(c[1]), byte(c[2]), byte(c[3]), L[Search.STRAIGHT_FLAG_TEXT])
    return Search.STRAIGHT_FLAG
end




local function Frames()
    return FGPS.UI.Frames
end

local function settings()
    return FGPS.DB and FGPS.DB.settings or nil
end

local function Look()
    return FGPS.UI.Look
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
    local width, height = frame and frame:GetWidth(), frame and frame:GetHeight()
    if type(width) ~= "number" or width <= 0 then
        width = tokens.windowWidth - edge.sheetLeft - edge.sheetRight - 2 * tokens.pad
    end
    if type(height) ~= "number" or height <= 0 then
        height = tokens.windowHeight - edge.sheetTop - edge.sheetBottom - 2 * tokens.pad - tokens.rowQuest - tokens.gapWide
    end
    return width, height
end


local function textWidth(text)
    local width = text.GetUnboundedStringWidth and text:GetUnboundedStringWidth() or text:GetStringWidth()
    return type(width) == "number" and width or 0
end

local function hideTip(owner)
    if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end


local function pageHas(file, without)
    local look = Look()
    if look.TomeHas("file", file) then return true end
    look.NoteOnce("tome:places:" .. file, "Tome: %s missing; %s", file, without)
    return false
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
        if not pos or type(dest) ~= "table" or type(dest.x) ~= "number" or type(dest.y) ~= "number" then return "" end
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



local function mapClosed()
    return type(OpenWorldMap) ~= "function" or (InCombatLockdown ~= nil and InCombatLockdown() == true)
end


local function samePlace(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    if a == b then return true end
    return a.inst == b.inst and a.x == b.x and a.y == b.y and (a.name == nil or b.name == nil or a.name == b.name)
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

    Search.routesAsked = Search.routesAsked + 1
    if mode == "start" then
        Navigator:SetDestination(dest, { start = true, quiet = opts.quiet == true })
        return true
    end

    if mode == "showRoute" then
        local Preview = FGPS.UI.Preview
        local state = Navigator.GetState and Navigator:GetState() or nil
        if state == "active" and not (Navigator.riding or (UnitOnTaxi and UnitOnTaxi("player"))) then






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




local function reasonText(code, fallback)
    local Compat = FGPS.UI.Compat
    if Compat and Compat.ReasonText then return Compat.ReasonText(code, fallback) end
    return tostring(code or fallback or L["unknown reason"])
end




local function resolveItem(item, quiet)
    if type(item) ~= "table" then return nil end
    if item.dest then return item.dest end
    if item.resolve then
        local ok, dest, reason = pcall(item.resolve)
        if ok and dest then return dest end
        if not ok then FGPS.Log:Error("Destination resolve failed: %s", tostring(dest)) end
        if ok and reason then
            local why = format(L["%s: %s"], item.label or "?", tostring(reason))
            if not quiet then FGPS:Print("%s", why) end
            return nil, why
        end
    end
    return nil
end

function Search:SelectedItem()
    local item = self.items[self.selectedIndex]
    if item and (item.dest or item.resolve) then return item end



    if item and item.kind ~= "header" and item.kind ~= "back" then return nil end
    for _, candidate in ipairs(self.items) do
        if candidate.dest or candidate.resolve then return candidate end
    end
    return nil
end


local refreshFooter


function Search:ShowingMatches()
    return self.only ~= nil or Util.Trim(self.query or "") ~= ""
end




function Search:PickedPlace(quiet)
    if self:ShowingMatches() then return resolveItem(self:SelectedItem(), quiet) end
    return page.selected
end



function Search:PickChanged()
    if self:ShowingMatches() then
        local dest = resolveItem(self:SelectedItem(), true)
        page.selected = dest
        page.picked = dest and "matches" or nil
    end
    refreshFooter()
end







function Search:Act(mode)
    local dest, why = self:PickedPlace(true)
    if not dest then
        local Guide = FGPS.UI.Guide
        if Guide and Guide.Say then Guide.Say(why or L["Select a destination first."], Search.REFUSED_SECONDS) end
        return false
    end
    if mode == "addStop" or (mode == nil and self.addStopMode) then
        Search.GoTo(dest, "addStop")
        return true
    end


    return Search.GoTo(dest, mode or "start", { quiet = true })
end


function Search:ToggleFavorite(dest)
    local Destinations = FGPS.Destinations
    if type(dest) ~= "table" then dest = self:PickedPlace() end
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
            FGPS:Print(L["Could not add favorite (%s)."], reasonText(reason, L["unknown reason"]))
        else
            FGPS:Print(L["Added to favorites: %s"], describe(dest))
        end
    end


    self:RefreshDistances()
    self:PickChanged()
    return true
end










local function dressPlaceRow(row)
    local tokens = Look().TOKENS
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(tokens.iconBox, tokens.iconBox)
    row.Icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.Name = pageText(row, "pageBody", "ink")
    row.Name:SetHeight(tokens.rowPlace)
    row.Zone = pageText(row, "pageSub", "inkGrey")
    row.Zone:SetPoint("LEFT", row.Name, "RIGHT", tokens.gap, 0)
    row.Zone:SetHeight(tokens.rowPlace)
    row.Right = pageText(row, "pageSub", "inkGrey", "RIGHT")
    row.Right:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.Right:SetHeight(tokens.rowPlace)

    if row.Text then
        row.Text:SetText("")
        row.Text:Hide()
    end
end
Search.DressPlaceRow = dressPlaceRow

local function iconOf(item)
    if item.icon then return item.icon end
    local Rows = FGPS.UI.SearchRows
    local dest = item.dest
    local kind = type(dest) == "table" and Rows and Rows.TYPE_ICON and Rows.TYPE_ICON[dest.type] or nil
    return kind or "place"
end

local function paintPlaceRow(row, item, width)
    local look = Look()
    local tokens = look.TOKENS
    row.entry = item
    row.Name:ClearAllPoints()
    if item.kind == "header" then
        row.Icon:Hide()
        row.Name:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.Name:SetFontObject(look.Font("pageSub"))
        row.Name:SetTextColor(look.Color("rubric"))
        row.Name:SetText(item.label or "")
        row.Name:SetWidth(width)
        row.Zone:SetText("")
        row.Right:SetText("")
        return
    end
    local icon = iconOf(item)
    if row.fgpsIcon ~= icon then
        look.Icon(row.Icon, icon, tokens.iconBox)
        row.fgpsIcon = icon
    end
    row.Icon:Show()
    row.Name:SetPoint("LEFT", row, "LEFT", tokens.iconBox + tokens.gap, 0)
    row.Name:SetFontObject(look.Font("pageBody"))
    row.Name:SetTextColor(look.Color(item.otherFaction and "inkGrey" or "ink"))
    local dest = item.dest
    local name = type(dest) == "table" and type(dest.name) == "string" and dest.name or item.label or ""
    local Rows = FGPS.UI.SearchRows
    local typed = item.marked and Search.query or ""
    local text = Rows and Rows.Mark and Rows.Mark(name, typed, "rubric") or name
    if item.favorite then text = L["*"] .. " " .. text end
    row.Name:SetText(text)
    local zone = type(dest) == "table" and dest.zoneName or nil
    if zone == name then zone = nil end
    row.Zone:SetText(zone or "")
    row.Right:SetText(item.right or "")
    local rightWidth = math.floor(width * RIGHT_SHARE)
    row.Right:SetWidth(rightWidth)
    local room = math.max(0, width - rightWidth - tokens.iconBox - tokens.gap - tokens.gapWide)
    local nameWidth = math.min(textWidth(row.Name), room)
    row.Name:SetWidth(nameWidth)
    row.Zone:SetWidth(math.max(0, room - nameWidth - tokens.gap))
end
Search.PaintPlaceRow = paintPlaceRow


local function placeTooltip(row, item)
    if type(item) ~= "table" or item.kind ~= "dest" or type(item.dest) ~= "table" then
        hideTip(row)
        return
    end
    Look().Tooltip(row, describe(item.dest), nil,
        L["Double-click to be guided there"] .. " \194\183 " .. L["Right-click for options"])
end



function Search.OpenPlaceMenu(owner, item)
    local Menus = FGPS.UI.Menus
    if not (Menus and Menus.OpenRowMenu) or type(item) ~= "table" or item.kind == "header" then return nil end
    local dest = resolveItem(item, true)
    if type(dest) ~= "table" then return nil end
    local Destinations = FGPS.Destinations
    local favorite = Destinations and Destinations.IsFavorite and Destinations.IsFavorite(dest) and true or false
    local map = placeMap(dest)
    return Menus.OpenRowMenu(owner, {
        title = type(dest.name) == "string" and dest.name or describe(dest),
        entries = {
            { label = L["Go"], onClick = function() Search.GoTo(dest, "start", { quiet = true }) end },
            { label = L["Add as a Stop"], onClick = function() Search.GoTo(dest, "addStop") end },
            { label = favorite and L["Remove from Favorites"] or L["Add to Favorites"],
              onClick = function() Search:ToggleFavorite(dest) end },
            { label = L["Show on Map"], onClick = function() Menus.ShowOnMap(map) end, disabled = map == nil or mapClosed },
        },
    })
end


function Search:IsPicked(dest, key)
    if key ~= nil and page.picked ~= key then return false end
    return samePlace(page.selected, dest)
end

local layoutPage


function Search:PickPlace(dest, key)
    if type(dest) ~= "table" then return false end
    page.selected, page.picked = dest, key
    Look().PlaySound("IG_QUEST_LIST_SELECT")
    layoutPage()
    refreshFooter()
    return true
end

local function paintGlow(row)
    if not row.Glow then return end
    local entry = row.entry
    local picked = type(entry) == "table" and Search:IsPicked(entry.dest, row.fgpsSection)
    row.Glow:SetShown(picked or row.fgpsHover == true)
end


local function onSectionsWheel(_, delta)
    if type(delta) ~= "number" then return end
    Search:ScrollSections(-delta * WHEEL_ROWS * Look().TOKENS.rowPlace)
end





function Search.NewPlaceRow(parent, key, menu)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(Look().TOKENS.rowPlace)
    row.Glow = row:CreateTexture(nil, "BACKGROUND")
    row.Glow:SetAllPoints(row)
    Look().Highlight(row.Glow)
    row.Glow:Hide()
    dressPlaceRow(row)
    row.fgpsSection = key
    row.fgpsMenu = type(menu) == "function" and menu or nil
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            (self.fgpsMenu or Search.OpenPlaceMenu)(self, self.entry)
            return
        end
        local entry = self.entry
        if type(entry) == "table" and not Search:IsPicked(entry.dest, self.fgpsSection) then
            Search:PickPlace(entry.dest, self.fgpsSection)
        end
    end)
    row:SetScript("OnDoubleClick", function(self, button)
        if button == "RightButton" then
            (self.fgpsMenu or Search.OpenPlaceMenu)(self, self.entry)
            return
        end
        local entry = self.entry
        if type(entry) ~= "table" or type(entry.dest) ~= "table" then return end
        if not Search:IsPicked(entry.dest, self.fgpsSection) then Search:PickPlace(entry.dest, self.fgpsSection) end
        Search:Act()
    end)
    row:SetScript("OnEnter", function(self)
        self.fgpsHover = true
        paintGlow(self)
        placeTooltip(self, self.entry)
    end)
    row:SetScript("OnLeave", function(self)
        self.fgpsHover = false
        paintGlow(self)
        hideTip(self)
    end)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", onSectionsWheel)
    return row
end
Search.PaintPick = paintGlow




local function paintMatchGlow(row)
    if row.fgpsGlow then row.fgpsGlow:SetShown(row.fgpsSelected == true or row.fgpsHover == true) end
end

local function renderMatchRow(row, item, _, list)
    if not row.Name then
        dressPlaceRow(row)
        if row.Bg and row.Bg.SetAlpha then row.Bg:SetAlpha(0) end
        row.fgpsGlow = row:CreateTexture(nil, "BACKGROUND")
        row.fgpsGlow:SetAllPoints(row)
        Look().Highlight(row.fgpsGlow)
    end
    local width = list:GetWidth() or 0
    if list.Bar and list.Bar.IsShown and list.Bar:IsShown() then width = width - (list.Bar:GetWidth() or 0) - 2 end
    paintPlaceRow(row, item, math.max(0, width))
    paintMatchGlow(row)
end

local function onMatchClick(item, index)
    if type(item) ~= "table" then return end
    if item.kind == "header" then

        local list = page.list
        if list and list.SetSelected then list:SetSelected(Search.selectedIndex > 0 and Search.selectedIndex or nil) end
        return
    end
    if Search.selectedIndex ~= index then
        Search.selectedIndex = index
        Look().PlaySound("IG_QUEST_LIST_SELECT")
    end
    Search:PickChanged()
end

local function onMatchDoubleClick(item, index)
    if type(item) ~= "table" or not (item.dest or item.resolve) then
        onMatchClick(item, index)
        return
    end
    if Search.selectedIndex ~= index then
        Search.selectedIndex = index
        Search:PickChanged()
    end
    Search:Act()
end

local function onMatchRightClick(item, _, row)
    Search.OpenPlaceMenu(row, item)
end

local function onMatchEnter(item, _, row)
    paintMatchGlow(row)
    placeTooltip(row, item)
end

local function onMatchLeave(_, _, row)
    paintMatchGlow(row)
    hideTip(row)
end

function Search:Select(index)
    if #self.items == 0 then
        self.selectedIndex = 0
        return
    end
    if index < 1 then index = 1 end
    if index > #self.items then index = #self.items end
    self.selectedIndex = index
    local list = page.list
    if list and list.SetSelected then list:SetSelected(index) end
    if list and list.ScrollTo then list:ScrollTo(index) end
    self:PickChanged()
end


local function isSkippable(item)
    return type(item) ~= "table" or item.kind == "header"
end


function Search:MoveSelection(delta)
    if #self.items == 0 then return end
    local before = self.selectedIndex
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
    else
        self:Select(index)
    end
    if self.selectedIndex ~= before then Look().PlaySound("IG_QUEST_LIST_SELECT") end
end


function Search:SelectEdge(step)
    local n = #self.items
    if n == 0 then return end
    local index = step > 0 and 1 or n
    while index >= 1 and index <= n and isSkippable(self.items[index]) do index = index + step end
    if index < 1 or index > n then return end
    self:Select(index)
end




function Search:Activate()
    self:FlushPending()
    return self:Act()
end

function Search:SetItems(items, status)
    self.items = items or {}
    if self.selectedIndex > #self.items then self.selectedIndex = 0 end
    if self.addStopMode then
        local banner = L["Adding stops. Pick a place; the window stays open."]
        status = status and status ~= "" and (banner .. "  " .. status) or banner
    end
    page.status = status or ""
    layoutPage()
    self:PickChanged()
end


function Search:GetResults()
    return self.items
end





local PLACE_TYPES = {
    town = true, landmark = true, dungeon = true, raid = true, capital = true, room = true,
    zone = true, area = true,
}

local function destItems(list, pos)
    local Destinations = FGPS.Destinations
    local items = {}
    for _, entry in ipairs(list or {}) do



        local dest = type(entry) == "table" and (entry.dest or entry) or nil
        if type(dest) == "table" then
            local label = entry.label or describe(dest)

            local favorite = Destinations and Destinations.IsFavorite and Destinations.IsFavorite(dest) and true or false
            if favorite then
                label = L["*"] .. " " .. label
            end
            items[#items + 1] = { kind = "dest", dest = dest, label = label,
                                  right = Search.DistanceText(dest, pos, entry.distance), otherFaction = entry.otherFaction,
                                  favorite = favorite }
        end
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


local function firstPlace(items)
    for i, item in ipairs(items or {}) do
        if item.kind == "dest" then return i end
    end
    return 0
end



function Search:RunSearch(text)
    local Destinations = FGPS.Destinations
    text = Util.Trim(text or "")
    self.query = text
    if self.only then
        self:ShowKind()
        return
    end


    if #text == 0 then
        self.selectedIndex = 0
        if page.picked == "matches" then page.selected, page.picked = nil, nil end
        self:SetItems({}, "")
        self:RefreshNearest()
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
    for _, item in ipairs(items) do item.marked = true end
    self.selectedIndex = firstPlace(items)
    local n = 0
    for _, item in ipairs(items) do if item.kind == "dest" then n = n + 1 end end
    self:SetItems(items, n == 0 and L["No matching destinations."] or resultsText(n))
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
        self.pendingQuery = nil
        self:RunSearch(text)
    end
end




function Search:FlushPending()
    local query = self.pendingQuery
    if query == nil then return false end
    self.searchGeneration = self.searchGeneration + 1
    self.pendingQuery = nil
    self:RunSearch(query)
    return true
end





local LIST_ROW_DEST = { reachability = false }

local function candidateDest(c)
    local Destinations = FGPS.Destinations
    if c.poiIndex and Destinations and Destinations.FromPOI then
        local ok, dest = pcall(Destinations.FromPOI, c.poiIndex, LIST_ROW_DEST)
        if ok and dest then return dest end
    end
    local s = c.learned
    if type(s) ~= "table" then return nil end
    return { kind = "service", name = s.name, inst = s.inst, x = s.x, y = s.y, map = s.map,
             type = s.kind, serviceKind = s.kind, zoneName = s.zoneName,
             faction = (s.fac ~= 0) and s.fac or nil, learned = true }
end


local function listQueryText()
    return Util.Trim(Search.query or ""):lower()
end



local function listHit(text, query)
    query = query or listQueryText()
    if query == "" then return true end
    local plain = tostring(text or "")

    if plain:find("|", 1, true) then
        plain = plain:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    end
    return plain:lower():find(query, 1, true) ~= nil
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
    if cat.inside then

        if not (Destinations and Destinations.InsidePlaces) then return {} end
        local ok, rows = pcall(Destinations.InsidePlaces, cat.inside)
        return ok and type(rows) == "table" and rows or {}
    end
    if not cat.types or not Destinations or not Destinations.Browse then return {} end


    local ask = cat.skip and LIST_FILTER_LIMIT or limit
    local ok, rows = pcall(Destinations.Browse, { types = cat.types, limit = ask })
    if not ok or type(rows) ~= "table" then return {} end
    if not cat.skip then return rows end
    local kept = {}
    for _, row in ipairs(rows) do
        if #kept >= limit then break end
        if not cat.skip(row.dest) then kept[#kept + 1] = row end
    end
    return kept
end




local function placesOfKind(kind, limit)
    local rows = {}
    if kind.insideFirst then
        local Inside = FGPS.Inside
        local map = Inside and Inside.Map and Inside.Map() or nil
        local rec = map and FGPS.Data and FGPS.Data.insideMaps and FGPS.Data.insideMaps[map] or nil
        if rec then
            for _, row in ipairs(placesFor({ inside = map }, limit)) do rows[#rows + 1] = row end
        end
    end
    for _, row in ipairs(placesFor(kind, limit)) do rows[#rows + 1] = row end
    return rows
end

local function matchingPlaces(kind)
    local query = listQueryText()
    local filtering = query ~= ""
    local rows = placesOfKind(kind, filtering and LIST_FILTER_LIMIT or LIST_LIMIT)
    if not filtering then return rows end
    local matched = {}
    for _, row in ipairs(rows) do
        local dest = row.dest
        if listHit(row.label, query) or (dest and (listHit(dest.name, query) or listHit(dest.zoneName, query))) then
            matched[#matched + 1] = row
        end
    end
    return matched
end







function Search:CancelServiceSearch(redraw)

    local chain = self:CancelNearest(redraw and "route" or nil)
    if not self.serviceQuery then return chain end
    self.serviceQuery = nil
    local ServiceSearch = FGPS.ServiceSearch
    local cancelled = false
    if ServiceSearch and ServiceSearch.Cancel then
        local ok, result = pcall(ServiceSearch.Cancel)
        cancelled = ok and result == true
    end
    if redraw and self.only and self:IsShown() then
        self.serviceResults = { kind = kindAt(self.only) and kindAt(self.only).nearest, list = {}, cancelled = true }
        self:Refresh()
    end
    return cancelled or chain
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


local function serviceResultItems(results)
    local items = {}
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
        local why = results.reason and (SERVICE_REASONS[results.reason] and L[SERVICE_REASONS[results.reason]] or reasonText(results.reason, L["nothing of that kind is known within range"])) or L["nothing of that kind is known within range"]
        status = format(L["No %s found: %s."], label, why)
    elseif straightCount > 0 then
        status = format(L["Nearest %s by route distance; %d of %d could not be routed and show open ground."], label, straightCount, #results.list)
    else
        status = format(L["Nearest %s by route distance."], label)
    end
    return items, status
end




function Search:ShowKind()
    local kind = kindAt(self.only)
    if not kind then
        self.only = nil
        self:RunSearch(self.query)
        return
    end
    local items, status
    local results = self.serviceResults
    if listQueryText() == "" and kind.nearest and not (results and results.cancelled) then
        if not (results and results.kind == kind.nearest) then
            if self.serviceQuery ~= kind.nearest then
                self.items, self.selectedIndex = {}, 0
                self:FindNearest(kind.nearest)
            end
            return
        end
        items, status = serviceResultItems(results)
    else

        if self.serviceQuery then self:CancelServiceSearch() end
        items = destItems(matchingPlaces(kind), playerPos())
        for _, item in ipairs(items) do item.marked = true end
        status = #items == 0 and L["No matching destinations."] or resultsText(#items)
        status = format(L["%s: %s"], kindLabel(kind), status)
    end
    self.selectedIndex = firstPlace(items)
    self:SetItems(items, status)
end



function Search:SetOnly(key)
    if key ~= nil and not kindAt(key) then return false end


    self:CancelNearest("kind")
    self:CancelServiceSearch()
    self.serviceResults = nil
    self.only = key
    self.searchGeneration = self.searchGeneration + 1
    self.pendingQuery = nil
    self.selectedIndex = 0
    local box = page.Box
    self:RunSearch(box and box:GetText() or self.query)
    return true
end

local function showOnlyEntry(label, key)
    return { label = label, onClick = function() Search:SetOnly(key) end, disabled = Search.only == key }
end





local function trainerEntries()
    local ServiceSearch = FGPS.ServiceSearch
    local pos = playerPos()
    local kinds = {}
    if ServiceSearch and ServiceSearch.TrainerKinds and pos then
        local ok, list = pcall(ServiceSearch.TrainerKinds, pos, 1e9)
        if ok and type(list) == "table" then kinds = list end
    end
    local mine
    if ServiceSearch and ServiceSearch.PlayerClass then
        local ok, token = pcall(ServiceSearch.PlayerClass)
        if ok then mine = token end
    end
    local entries, rest = {}, {}
    for _, k in ipairs(kinds) do
        local kind = type(k) == "table" and k.kind
        if type(kind) == "string" and kind ~= "weapons" and kindAt("trainer:" .. kind) then
            if kind == mine then
                entries[#entries + 1] = showOnlyEntry(format(L["%s (your class)"], trainerKindLabel(kind)), "trainer:" .. kind)
            else
                rest[#rest + 1] = showOnlyEntry(trainerKindLabel(kind), "trainer:" .. kind)
            end
        end
    end
    for _, entry in ipairs(rest) do entries[#entries + 1] = entry end
    entries[#entries + 1] = showOnlyEntry(L["Any Trainer"], "trainer")
    for _, kind in ipairs(KINDS) do
        if kind.inTrainerMenu then entries[#entries + 1] = showOnlyEntry(L[kind.label], kind.key) end
    end
    return entries
end



function Search.OpenShowOnlyMenu(owner)
    local Menus = FGPS.UI.Menus
    if not (Menus and Menus.OpenRowMenu) then return nil end
    local entries = { showOnlyEntry(L["Everything"], nil) }
    for _, kind in ipairs(KINDS) do
        if kind.key == "trainer" then
            entries[#entries + 1] = { label = L[kind.label], entries = trainerEntries() }
        elseif not kind.inTrainerMenu then
            entries[#entries + 1] = showOnlyEntry(L[kind.label], kind.key)
        end
    end
    return Menus.OpenRowMenu(owner, { title = L["Show Only"], entries = entries })
end





















local nearest = { rows = {}, state = nil, step = 0, generation = 0, asking = nil, retries = 0 }
Search.nearestState = nearest
Search.NEAREST_LIMIT = 3
Search.NEAREST_RETRIES = 3

local function nearestItem(row)
    local s = settings()
    local units = s and s.units or "yards"
    return { kind = "dest", dest = row.dest, label = describe(row.dest), icon = row.icon,
             right = Search.ServiceResultText({ yards = row.yards, straight = row.straight }, nil, units),
             unverified = row.straight == true }
end

local function askNearest(generation)
    if generation ~= nearest.generation or nearest.state ~= "running" then return end
    nearest.step = nearest.step + 1
    local service = Search.NEAREST[nearest.step]
    local Rows = FGPS.UI.SearchRows
    if not service or not (Rows and Rows.Nearest) then
        nearest.state, nearest.asking = "done", nil
        layoutPage()
        return
    end
    nearest.asking = service
    layoutPage()
    local answered = false
    local ok, err = pcall(Rows.Nearest, service, service, function(rows, why, known)
        answered = true
        if generation ~= nearest.generation or nearest.state ~= "running" then return end
        if why == "cancelled" then


            local guess = type(known) == "table" and known[1] or nil
            local function keepGuess()
                if guess and type(guess.dest) == "table" then nearest.rows[#nearest.rows + 1] = nearestItem(guess) end
            end
            nearest.retries = nearest.retries + 1
            if nearest.retries <= Search.NEAREST_RETRIES and C_Timer and C_Timer.After then
                nearest.step = nearest.step - 1
                C_Timer.After(0, function()
                    if generation ~= nearest.generation or nearest.state ~= "running" then return end
                    local ServiceSearch = FGPS.ServiceSearch
                    if not (ServiceSearch and ServiceSearch.IsSearching and ServiceSearch.IsSearching()) then
                        askNearest(generation)
                        return
                    end
                    FGPS.Log:Info("Nearest %s: another service search is running; the section waits", tostring(service))
                    keepGuess()
                    nearest.state, nearest.asking = "paused", nil
                    layoutPage()
                end)
                return
            end
            FGPS.Log:Info("Nearest %s: cut short %d times in a row; the direct estimate stands", tostring(service),
                nearest.retries)
            nearest.retries = 0
            keepGuess()
            askNearest(generation)
            return
        end
        nearest.retries = 0
        local first = type(rows) == "table" and rows[1] or nil
        if first and type(first.dest) == "table" then nearest.rows[#nearest.rows + 1] = nearestItem(first) end
        askNearest(generation)
    end, Search.NEAREST_LIMIT)
    if not ok then
        FGPS.Log:Error("Nearest %s failed: %s", tostring(service), tostring(err))
        nearest.state, nearest.asking = "done", nil
        layoutPage()
        return
    end

    if not answered and err ~= true then askNearest(generation) end
end



function Search:RefreshNearest(force)
    if nearest.state ~= nil and nearest.state ~= "paused" and not force then return false end
    if not page.frame then return false end
    nearest.generation = nearest.generation + 1
    nearest.rows, nearest.state, nearest.step, nearest.asking, nearest.retries = {}, "running", 0, nil, 0
    askNearest(nearest.generation)
    return true
end




function Search:CancelNearest(why)
    if why == "route" and nearest.state == "paused" then nearest.state = "cancelled" end
    if nearest.state ~= "running" then return false end
    nearest.state, nearest.asking = why == "kind" and "paused" or "cancelled", nil
    nearest.generation = nearest.generation + 1
    local ServiceSearch = FGPS.ServiceSearch
    if ServiceSearch and ServiceSearch.Cancel then pcall(ServiceSearch.Cancel) end
    layoutPage()
    return true
end

local function buildNearest(frame)
    frame.Head = pageText(frame, "pageSub", "rubric")
    frame.Head:SetText(L["Nearest"])
    frame.Head:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.Head:SetHeight(HEAD_HEIGHT)
    frame.Rows = {}
    for i = 1, #Search.NEAREST do frame.Rows[i] = Search.NewPlaceRow(frame, "nearest") end
    frame.Line = pageText(frame, "pageSub", "inkGrey")
    frame.Line:SetHeight(STATUS_HEIGHT)
    return function(f)
        local tokens = Look().TOKENS
        local width = pageSize(page.frame)
        local y = HEAD_HEIGHT
        for i, row in ipairs(f.Rows) do
            local item = nearest.rows[i]
            if item then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
                row:SetSize(width, tokens.rowPlace)
                paintPlaceRow(row, item, width)
                paintGlow(row)
                row:Show()
                y = y + tokens.rowPlace
            else
                row.entry = nil
                row:Hide()
            end
        end
        local line
        if nearest.state == "running" and nearest.asking then
            line = format(L["Searching for the nearest %s..."], serviceLabel(nearest.asking))
        elseif nearest.state == "done" and #nearest.rows == 0 then
            line = L["No innkeeper, flight master, bank or mailbox is known nearby."]
        end
        if line then
            f.Line:SetText(line)
            f.Line:ClearAllPoints()
            f.Line:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
            f.Line:SetWidth(width)
            f.Line:Show()
            y = y + STATUS_HEIGHT
        else
            f.Line:Hide()
        end
        if #nearest.rows == 0 and not line then return 0 end
        return y
    end
end
















local pending = {}

local function buildSection(section)
    if section.key == "matches" then return end
    local ok, paint = pcall(section.builder, section.frame, page)
    if not ok then
        FGPS.Log:Error("Places section %s failed to build: %s", tostring(section.key), tostring(paint))
        section.paint = nil
        return
    end
    section.paint = type(paint) == "function" and paint or nil
end

local function sortSections()
    table.sort(page.sections, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.key < b.key
    end)
end

local function placeSection(key, order, builder)
    for _, section in ipairs(page.sections) do
        if section.key == key then
            section.order, section.builder = order, builder
            buildSection(section)
            sortSections()
            return section
        end
    end
    local frame = CreateFrame("Frame", nil, page.Content or page.frame)
    frame:Hide()
    local section = { key = key, order = order, builder = builder, frame = frame }
    page.sections[#page.sections + 1] = section
    buildSection(section)
    sortSections()
    return section
end

function Search:AddSection(key, order, builder)
    if type(key) ~= "string" or key == "" or key == "matches" then return false end
    if type(order) ~= "number" or type(builder) ~= "function" then return false end
    if not page.frame then
        pending[key] = { order = order, builder = builder }
        return true
    end
    placeSection(key, order, builder)
    layoutPage()
    return true
end


function Search:RefreshSections()
    layoutPage()
end




function Search:ShowSection(key)
    if type(key) ~= "string" then return false end
    page.anchor = key
    layoutPage()
    for _, section in ipairs(page.sections) do
        if section.key == key then return section.top ~= nil end
    end
    return false
end



function Search:ScrollSections(pixels)
    if type(pixels) ~= "number" then return false end
    page.anchor = nil
    page.scroll = (page.scroll or 0) + pixels
    layoutPage()
    return true
end



function Search:Unpick(key)
    if key == nil or page.picked ~= key then return false end
    page.selected, page.picked = nil, nil
    refreshFooter()
    return true
end


function Search.PageWidth()
    return (pageSize(page.frame))
end




layoutPage = function()
    local frame = page.frame
    if not frame then return end
    local tokens = Look().TOKENS
    local width, height = pageSize(frame)
    local y = BOX_HEIGHT + tokens.gap
    local status = page.status or ""
    page.Status:SetText(status)
    page.Status:ClearAllPoints()
    page.Status:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
    page.Status:SetWidth(width)
    page.Status:SetShown(status ~= "")
    if status ~= "" then y = y + STATUS_HEIGHT + tokens.gap end




    local body, content = page.Body, page.Content
    local tall = math.max(tokens.rowPlace, height - y)
    body:ClearAllPoints()
    body:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -y)
    body:SetSize(width, tall)
    local matches = Search:ShowingMatches()
    local ornament = Search.SECTION_ORDER.ornament
    local top, above, breakTop = 0, false, nil
    for _, section in ipairs(page.sections) do
        local f = section.frame
        section.top = nil
        if section.key == "matches" then
            if matches then
                section.top = 0
                f:SetSize(width, tall)
                f:Show()
                local list = page.list
                if list then
                    list:SetSize(width, tall)
                    list.selected = Search.selectedIndex > 0 and Search.selectedIndex or nil
                    list:SetItems(Search.items)
                end
                top = tall
            else
                f:Hide()
            end
        elseif matches or not section.paint then
            f:Hide()
        else
            local ok, painted = pcall(section.paint, f, page)
            if not ok then
                FGPS.Log:Error("Places section %s failed to paint: %s", tostring(section.key), tostring(painted))
                painted = 0
            end
            if type(painted) == "number" and painted > 0 then
                if above and not breakTop and section.order > ornament then
                    breakTop = top
                    top = top + (page.Break and BREAK_HEIGHT or tokens.gapWide)
                end
                if section.order < ornament then above = true end
                section.top = top
                f:SetSize(width, painted)
                f:Show()
                top = top + painted + tokens.gapWide
            else
                f:Hide()
            end
        end
    end
    local scroll = 0
    if not matches then
        scroll = page.scroll or 0
        for _, section in ipairs(page.sections) do
            if page.anchor ~= nil and section.key == page.anchor and section.top then scroll = section.top end
        end
        scroll = math.max(0, math.min(scroll, top - tall))
    end
    page.scroll = scroll
    content:SetSize(width, math.max(top, tall))
    for _, section in ipairs(page.sections) do
        if section.top then
            section.frame:ClearAllPoints()
            section.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -section.top)
        end
    end
    if page.Break then
        page.Break:ClearAllPoints()
        if breakTop then
            page.Break:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -breakTop)
            page.Break:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -breakTop)
        end
        page.Break:SetShown(breakTop ~= nil)
    end
    if body.SetVerticalScroll then body:SetVerticalScroll(scroll) end
end



function Search.PlacesFooter(win)
    local picked = Search:PickedPlace(true) ~= nil
    local why = L["Pick a place first"]
    win:SetFooterButtons({
        { label = L["Add Stop"], onClick = function() Search:Act("addStop") end, enabled = picked, why = why },
        { label = L["Go"], onClick = function() Search:Act("start") end, enabled = picked, why = why },
    })
    if win.FooterNote then win.FooterNote:SetText("") end
end

refreshFooter = function()
    local Tome = FGPS.UI.Tome
    if Tome and Tome.window and Tome.Current and Tome:Current() == Search.PAGE then Search.PlacesFooter(Tome.window) end
end

local function buildPage(frame)
    local look = Look()
    local F = Frames()
    page.frame = frame
    local width = pageSize(frame)

    page.Box = look.SearchBox(frame, {
        width = width, height = BOX_HEIGHT, maxLetters = 80, placeholder = L["Search a town, a person or 42.5 65.1"],

        onChanged = function(_, text, userInput)
            if userInput then Search:ScheduleSearch(text or "") end
        end,




        onEnter = function(box, text)
            local asked = Search.routesAsked
            local acted
            if not Search.only and Search.ParseCoordinates(text) then
                acted = Search:GoToCoordinates(text)
            else
                acted = Search:Activate()
            end
            if (acted == false or Search.routesAsked ~= asked) and box and box.ClearFocus then box:ClearFocus() end
        end,
    })
    page.Box:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    page.Box:HookScript("OnEnter", function(self)
        Look().Tooltip(self, L["Places"], L["Search a town, a person or 42.5 65.1"], L["Right-click for options"])
    end)
    page.Box:HookScript("OnLeave", hideTip)

    page.Box:HookScript("OnMouseUp", function(self, button)
        if button == "RightButton" then Search.OpenShowOnlyMenu(self) end
    end)

    page.Box:SetScript("OnArrowPressed", function(_, key)
        if key == "UP" then Search:MoveSelection(-1) elseif key == "DOWN" then Search:MoveSelection(1) end
    end)

    page.Status = pageText(frame, "pageSub", "inkGrey")
    page.Status:SetHeight(STATUS_HEIGHT)




    page.Body = CreateFrame("ScrollFrame", nil, frame)
    page.Content = CreateFrame("Frame", nil, page.Body)
    page.Content:SetSize(width, 1)
    page.Body:SetScrollChild(page.Content)
    page.Body:EnableMouseWheel(true)
    page.Body:SetScript("OnMouseWheel", onSectionsWheel)
    page.scroll, page.anchor = 0, nil
    page.Break = nil
    if pageHas(BREAK_FILE, "a gap stands for the ornament over Favorites") then
        page.Break = page.Content:CreateTexture(nil, "ARTWORK")
        page.Break:SetTexture(BREAK_FILE)
        page.Break:SetHeight(BREAK_HEIGHT)
        page.Break:Hide()
    end

    local matches = placeSection("matches", Search.SECTION_ORDER.matches, function() end)
    if F and F.CreateScrollList then
        local ok, list = pcall(F.CreateScrollList, matches.frame, look.TOKENS.rowPlace, renderMatchRow, {
            width = width, onClick = onMatchClick, onDoubleClick = onMatchDoubleClick,
            onRightClick = onMatchRightClick, onEnter = onMatchEnter, onLeave = onMatchLeave,
        })
        if ok and type(list) == "table" then
            list:SetPoint("TOPLEFT", matches.frame, "TOPLEFT", 0, 0)
            page.list = list
        else
            FGPS.Log:Error("Frames.CreateScrollList failed: %s", tostring(list))
        end
    end
    placeSection("nearest", Search.SECTION_ORDER.nearest, buildNearest)
    for key, section in pairs(pending) do placeSection(key, section.order, section.builder) end
    pending = {}



    frame:HookScript("OnHide", function(self)
        local Tome = FGPS.UI.Tome
        local win = Tome and Tome.window
        if self:IsShown() and win and win:IsShown() then return end
        Search:OnPageHidden()
    end)
end



local function showPage(_, opts)
    page.live = true
    if type(opts) ~= "table" then
        Search:Refresh()
        return
    end
    Search.addStopMode = opts.mode == "addStop"
    Search:CancelServiceSearch()
    Search.only, Search.serviceResults = nil, nil
    Search.searchGeneration = Search.searchGeneration + 1
    Search.pendingQuery = nil
    nearest.state = nil
    local text = type(opts.query) == "string" and Util.Trim(opts.query) or ""
    if page.Box then page.Box:SetText(text) end
    Search.selectedIndex = 0
    page.selected, page.picked = nil, nil


    page.scroll, page.anchor = 0, type(opts.section) == "string" and opts.section or nil
    Search:RunSearch(text)


    if page.Box and page.Box.SetFocus and not opts.noFocus then page.Box:SetFocus() end
end


function Search:OnPageHidden()
    if not page.live then return end
    page.live = false
    self:CancelServiceSearch()
    self.addStopMode = false
    self.serviceResults = nil
    if page.Box and page.Box.ClearFocus then page.Box:ClearFocus() end


    local Itinerary = FGPS.UI.Itinerary
    if Itinerary and Itinerary.SearchClosed then
        local ok, err = pcall(Itinerary.SearchClosed, Itinerary)
        if not ok and FGPS.Log then FGPS.Log:Error("Stops window on closing the Places page failed: %s", tostring(err)) end
    end
end


function Search:Refresh()
    if not page.frame then return end
    self:RunSearch(self.query)
end




function Search:RefreshDistances()
    if not self:IsShown() then return end
    if not self:ShowingMatches() then
        layoutPage()
        return
    end


    if self.serviceQuery then return end
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
    end


    if restored == 0 and kept.label then
        for i, item in ipairs(self.items) do
            if item.label == kept.label and item.kind == kept.kind then
                restored = i
                break
            end
        end
    end
    if restored == 0 and keep <= #self.items then restored = keep end
    if restored > 0 then
        self.selectedIndex = restored
        local list = page.list
        if list and list.SetSelected then list:SetSelected(restored) end
        self:PickChanged()
    end
end

function Search:SetFilter(key)
    self.filter = key
    if not self.only then self:RunSearch(self.query) end
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
        FGPS:Print(L["Could not resolve those coordinates%s"], err and (": " .. reasonText(err)) or ".")
        return false
    end
    return Search.GoTo(dest, self.addStopMode and "addStop" or "start", { quiet = true })
end








function Search:Show(opts)
    local Tome = FGPS.UI.Tome
    if not (Tome and Tome.Open and Tome.pages and Tome.pages[Search.PAGE]) then
        FGPS:Print(L["The search window is unavailable; use /cabbie go <x> <y> [zone] instead."])
        return false
    end
    if UIParent and UIParent.IsVisible and not UIParent:IsVisible() then return false end
    opts = type(opts) == "table" and opts or {}


    local dock = opts.dock
    if not dock and self.docked and self:IsShown() then dock = self.dockFrame end
    if not Tome:Open(Search.PAGE, opts) then return false end
    self:ApplyDock(Tome.window, dock)
    return true
end





function Search:ApplyDock(window, dock)
    if not window then return end
    if type(dock) == "table" and dock.GetRight then
        local screen = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
        local ratio = 1
        if dock.GetEffectiveScale and UIParent and UIParent.GetEffectiveScale then
            local mine, theirs = UIParent:GetEffectiveScale(), dock:GetEffectiveScale()
            if type(mine) == "number" and mine > 0 and type(theirs) == "number" then ratio = theirs / mine end
        end
        local right = (dock:GetRight() or 0) * ratio
        if not self.docked then
            self.undockedStrata = window.GetFrameStrata and window:GetFrameStrata() or nil
        end
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
        if not window.fgpsSearchUndock and window.HookScript then
            window.fgpsSearchUndock = true
            window:HookScript("OnHide", function(w)

                if w.IsShown and w:IsShown() then return end
                Search:Undock(w)
            end)
        end
    elseif self.docked then
        self:Undock(window)
    end
end


function Search:Undock(window)
    if not self.docked then return false end
    self.docked = false
    self.dockFrame = nil
    self.dockedInside = nil
    window = window or (FGPS.UI.Tome and FGPS.UI.Tome.window)
    if window then
        window.fgpsEscape = true
        if window.SetFrameStrata then pcall(window.SetFrameStrata, window, self.undockedStrata or "HIGH") end
        if window.RestorePosition then window:RestorePosition() end
    end
    self.undockedStrata = nil
    return true
end


function Search:Hide()
    self.addStopMode = false
    local Tome = FGPS.UI.Tome
    if self:IsShown() then Tome.window:Hide() end
    self:OnPageHidden()
    self:Undock()
end


function Search:IsShown()
    local Tome = FGPS.UI.Tome
    return Tome ~= nil and Tome.Current ~= nil and Tome:Current() == Search.PAGE
end



function Search:Toggle()
    if self:IsShown() then
        FGPS.UI.Tome:Close()
        return true
    end
    return self:Show()
end




function Search:ClearAll()
    local Navigator = FGPS.Navigator
    if Navigator and Navigator.Clear then Navigator:Clear("user") end

    self.addStopMode = false
end






local function onListsChanged()
    if not Search:IsShown() then return end
    Search:RefreshDistances()
end



function Search.RegisterPlacesPage()
    local Tome = FGPS.UI.Tome
    if not (Tome and Tome.RegisterPage) then return false end
    local icon = pageHas(Search.PAGE_ICON, "the Places tab shows no picture") and Search.PAGE_ICON or nil
    return Tome.RegisterPage(Search.PAGE, { label = L["Places"], icon = icon, order = 1, build = buildPage, show = showPage,
                                            footer = Search.PlacesFooter })
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
    Search.RegisterPlacesPage()
    FGPS.Slash.Register("search", function(args)
        Search:Show({ query = Util.Trim(args) ~= "" and Util.Trim(args) or nil })
    end, L["Open the destination search (optionally with a query)"])
end
