














local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local type, ipairs, tostring, format = type, ipairs, tostring, string.format
local max, min = math.max, math.min

local Itinerary = {
    items = {},
    stops = {},
    closedByUser = false,
    showOwed = false,
    hidingProgrammatically = false,
    optimizeArmedAt = nil,


    routeSection = nil,


    asked = false,
}
FGPS.UI.Itinerary = Itinerary

local SECTION = "route"
local OPTIMIZE_CONFIRM_SECONDS = 10

local HEAD_HEIGHT, LINE_HEIGHT = 16, 14

local function Look() return FGPS.UI.Look end
local function now() return GetTime and GetTime() or 0 end

local function pageKey()
    local Search = FGPS.UI.Search
    return Search and Search.PAGE or "places"
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

local function navigatorStops()
    local Navigator = FGPS.Navigator
    if Navigator and Navigator.GetStops then
        local ok, stops = pcall(Navigator.GetStops, Navigator)
        if ok and type(stops) == "table" then return stops end
    end
    return {}
end







local function currentStopIndex(stops)
    local Navigator = FGPS.Navigator
    if not Navigator or not Navigator.GetRoute or not Navigator.GetProgress then return nil end
    local okR, route = pcall(Navigator.GetRoute, Navigator)
    local okP, progress = pcall(Navigator.GetProgress, Navigator)
    if not (okR and okP and type(route) == "table" and type(progress) == "table" and type(route.stops) == "table") then return nil end
    local Destinations = FGPS.Destinations
    local equal = Destinations and Destinations.Equal
    local legIndex = progress.legIndex or 1
    for _, stop in ipairs(route.stops) do
        local dest = stop.dest
        if stop.legTo and legIndex <= stop.legTo and type(dest) == "table" then
            for i = 1, #stops do
                if stops[i] == dest or (equal and equal(stops[i], dest)) then return i end
            end
        end
    end
    return nil
end







function Itinerary.BuildItems(stops, currentIndex)
    local items = {}
    for i, dest in ipairs(stops) do
        local name = type(dest) == "table" and type(dest.name) == "string" and dest.name ~= "" and dest.name or L["Map position"]
        local zone = type(dest) == "table" and type(dest.zoneName) == "string" and dest.zoneName ~= "" and dest.zoneName or nil
        if zone == name then zone = nil end
        items[#items + 1] = { index = i, dest = dest, number = tostring(i), name = name, zone = zone, label = describe(dest),
                              first = (i == 1), last = (i == #stops), current = (currentIndex == i) }
    end
    return items
end





local function emptyText()
    local UI = FGPS.UI or {}
    local UISettings, WorldMap = UI.Settings, UI.WorldMap
    local settings = FGPS.DB and FGPS.DB.settings
    local click = WorldMap and WorldMap.clickHandler and UISettings and UISettings.MapClickLabel
        and UISettings.MapClickLabel(settings and settings.mapClickModifier or "CTRL_RIGHT")
    if not click then return L["No stops yet. Search for a place above and press Go."] end
    return format(L["No stops yet. Search for a place above and press Go, or %s a place on the world map."], click)
end

local function armed()
    return Itinerary.optimizeArmedAt ~= nil and now() - Itinerary.optimizeArmedAt <= OPTIMIZE_CONFIRM_SECONDS
end







local function placeOf(item)
    local stops = navigatorStops()
    local dest = item.dest
    if stops[item.index] == dest then return item.index, stops end
    local Destinations = FGPS.Destinations
    local equal = Destinations and Destinations.Equal
    for i, stop in ipairs(stops) do
        if stop == dest then return i, stops end
    end
    if equal and type(dest) == "table" then
        for i, stop in ipairs(stops) do
            if equal(stop, dest) then return i, stops end
        end
    end
    return nil, stops
end




function Itinerary.OpenStopMenu(owner, item)
    local Menus = FGPS.UI.Menus
    if not (Menus and Menus.OpenRowMenu) or type(item) ~= "table" then return nil end
    local dest = item.dest
    local Search = FGPS.UI.Search
    local Destinations = FGPS.Destinations
    local entries = {
        { label = L["Move Up"],
          onClick = function() local i = placeOf(item) if i then Itinerary:MoveStop(i, i - 1) end end,
          disabled = function() local i = placeOf(item) return i == nil or i <= 1 end },
        { label = L["Move Down"],
          onClick = function() local i = placeOf(item) if i then Itinerary:MoveStop(i, i + 1) end end,
          disabled = function() local i, stops = placeOf(item) return i == nil or i >= #stops end },
        { label = L["Skip Stop"], onClick = function() Itinerary:SkipStop() end,
          disabled = function()
              local i, stops = placeOf(item)
              return i == nil or i ~= (currentStopIndex(stops) or 1)
          end },
    }
    if type(dest) == "table" and type(dest.inst) == "number" and type(dest.x) == "number" and type(dest.y) == "number"
        and Search and Search.ToggleFavorite then
        local favorite = Destinations and Destinations.IsFavorite and Destinations.IsFavorite(dest) and true or false
        entries[#entries + 1] = {
            label = favorite and L["Remove from Favorites"] or L["Add to Favorites"],
            onClick = function() Search:ToggleFavorite(dest) end,
        }
    end
    entries[#entries + 1] = {
        label = L["Remove"], destructive = true,
        onClick = function() local i = placeOf(item) if i then Itinerary:RemoveStop(i) end end,
        disabled = function() return placeOf(item) == nil end,
    }
    return Menus.OpenRowMenu(owner, { title = item.name, entries = entries })
end


local function somethingSet()
    if #navigatorStops() > 0 then return true end
    local Preview = FGPS.UI.Preview
    return Preview ~= nil and (Preview.route ~= nil or Preview.error ~= nil or Preview.calculating == true)
end



function Itinerary.OpenHeadMenu(owner)
    local Menus = FGPS.UI.Menus
    if not (Menus and Menus.OpenRowMenu) then return nil end
    local Preview = FGPS.UI.Preview
    local entries = Preview and Preview.MenuEntries and Preview.MenuEntries() or {}
    entries[#entries + 1] = { label = armed() and L["Confirm Best Order"] or L["Best Order"],
                              onClick = function() Itinerary:Optimize() end,
                              disabled = function() return #navigatorStops() < 2 end }
    entries[#entries + 1] = { label = L["Stop Route"], destructive = true,
                              onClick = function() Itinerary:CancelJourney() end,
                              disabled = function() return not somethingSet() end }
    return Menus.OpenRowMenu(owner, { title = L["Your Route"], entries = entries })
end




local function lineOf(parent, role, color, justify)
    local look = Look()
    local text = look.FontString(parent, "OVERLAY", role)
    text:SetTextColor(look.Color(color))
    text:SetJustifyH(justify or "LEFT")
    if text.SetWordWrap then text:SetWordWrap(false) end
    text:SetText("")
    return text
end


local function textWidth(text)
    local width = text.GetUnboundedStringWidth and text:GetUnboundedStringWidth() or text:GetStringWidth()
    return type(width) == "number" and width or 0
end

local function hideTip(owner)
    if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

local function paintGlow(row)
    local item = row.item
    local Search = FGPS.UI.Search
    local picked = type(item) == "table" and Search ~= nil and Search.IsPicked ~= nil and Search:IsPicked(item.dest, SECTION)
    row.Glow:SetShown(picked == true or row.fgpsHover == true)
end



local function onRowClick(self, button)
    local item = self.item
    if type(item) ~= "table" then return end
    if button == "RightButton" then
        Itinerary.OpenStopMenu(self, item)
        return
    end
    local Search = FGPS.UI.Search
    if Search and Search.PickPlace and not Search:IsPicked(item.dest, SECTION) then Search:PickPlace(item.dest, SECTION) end
end

local function onRowEnter(self)
    self.fgpsHover = true
    paintGlow(self)
    local item = self.item
    if type(item) ~= "table" then return end

    Look().Tooltip(self, item.label, item.current and L["The stop you are heading to"] or nil, L["Right-click for options"])
end

local function onRowLeave(self)
    self.fgpsHover = false
    paintGlow(self)
    hideTip(self)
end

local function newRow(parent)
    local look = Look()
    local tokens = look.TOKENS
    local rowH = look.PlaceRowHeight()
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(rowH)
    row.Glow = row:CreateTexture(nil, "BACKGROUND")
    row.Glow:SetAllPoints(row)
    look.Highlight(row.Glow)
    row.Glow:Hide()
    row.Number = lineOf(row, "pageBody", "rubric", "RIGHT")
    row.Number:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.Number:SetSize(tokens.iconBox, rowH)
    row.Name = lineOf(row, "pageBody", "ink")
    row.Name:SetPoint("LEFT", row.Number, "RIGHT", tokens.gap, 0)
    row.Name:SetHeight(rowH)
    row.Zone = lineOf(row, "pageSub", "inkGrey")
    row.Zone:SetPoint("LEFT", row.Name, "RIGHT", tokens.gap, 0)
    row.Zone:SetHeight(rowH)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", onRowClick)
    row:SetScript("OnEnter", onRowEnter)
    row:SetScript("OnLeave", onRowLeave)
    return row
end

local function paintRow(row, item, width)
    local look = Look()
    local tokens = look.TOKENS
    local rowH = look.PlaceRowHeight()
    row.item, row.index = item, item.index
    row.Number:SetSize(tokens.iconBox, rowH)
    row.Name:SetHeight(rowH)
    row.Zone:SetHeight(rowH)
    row.Number:SetText(item.number)
    row.Name:SetText(item.name)
    row.Zone:SetText(item.zone or "")
    local room = max(0, width - tokens.iconBox - 2 * tokens.gap)
    local nameWidth = min(textWidth(row.Name), room)
    row.Name:SetWidth(nameWidth)
    row.Zone:SetWidth(max(0, room - nameWidth - tokens.gap))
    paintGlow(row)
end


local function unpickGone(page, items)
    local Search = FGPS.UI.Search
    if not (Search and type(page) == "table" and page.picked == SECTION) then return end
    for _, item in ipairs(items) do
        if Search:IsPicked(item.dest, SECTION) then return end
    end
    Search:Unpick(SECTION)
end




local function shownRange(count, current, fit)
    if count <= fit then return 1, count end
    local first = max(1, min((current or 1) - 1, count - fit + 1))
    return first, first + fit - 1
end

local function placeLine(text, f, y, width)
    text:ClearAllPoints()
    text:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
    text:SetWidth(width)
    text:Show()
end

local function paintSection(section, f)
    local look = Look()
    local delta = look.TextSizeDelta()
    local rowH = look.PlaceRowHeight()
    local headH = HEAD_HEIGHT + delta
    local lineH = LINE_HEIGHT + delta
    local page = section.page
    local Search = FGPS.UI.Search
    local width = Search.PageWidth()
    local stops = navigatorStops()
    Itinerary.stops = stops
    local items = Itinerary.BuildItems(stops, currentStopIndex(stops))
    Itinerary.items = items
    local Preview = FGPS.UI.Preview
    local view = Preview and Preview.SectionView and Preview.SectionView() or {}
    local line = armed() and L["Choose Confirm Best Order to reorder your stops by travel distance."] or view.line
    if not line and #items == 0 and Itinerary.asked then line = emptyText() end
    unpickGone(page, items)



    local room = Search.PageHeight() - headH - (view.summary and lineH or 0) - (line and lineH or 0)
    local first, last = 1, #items
    if #items * rowH > room then
        local fit = max(1, math.floor((room - lineH) / rowH))
        local current
        for _, item in ipairs(items) do
            if item.current then current = item.index end
        end
        first, last = shownRange(#items, current, fit)
    end
    local shown = #items > 0 and last - first + 1 or 0


    if shown > 0 and Search:IsShown() then Itinerary.showOwed = false end
    for i = shown + 1, #section.rows do
        local row = section.rows[i]
        row.item, row.index = nil, nil
        row:Hide()
    end
    if #items == 0 and not line and not view.summary then
        section.More:Hide()
        return 0
    end
    section.Head:SetSize(width, headH)
    section.Summary:SetHeight(lineH)
    section.Line:SetHeight(lineH)
    section.More:SetHeight(lineH)
    local y = headH
    if view.summary then
        section.Summary:SetText(view.summary)
        placeLine(section.Summary, f, y, width)
        y = y + lineH
    else
        section.Summary:SetText("")
        section.Summary:Hide()
    end
    for i = 1, shown do
        local item = items[first + i - 1]
        local row = section.rows[i]
        if not row then
            row = newRow(f)
            section.rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
        row:SetSize(width, rowH)
        paintRow(row, item, width)
        row:Show()
        y = y + rowH
    end
    local after = #items - last
    if after > 0 then
        section.More:SetText(after == 1 and L["... and 1 more stop"] or format(L["... and %d more stops"], after))
        placeLine(section.More, f, y, width)
        y = y + lineH
    else
        section.More:SetText("")
        section.More:Hide()
    end
    if line then
        section.Line:SetText(line)
        placeLine(section.Line, f, y, width)
        y = y + lineH
    else
        section.Line:SetText("")
        section.Line:Hide()
    end
    return y
end



local function onHeadEnter(self)
    local Preview = FGPS.UI.Preview
    local view = Preview and Preview.SectionView and Preview.SectionView() or {}
    Look().Tooltip(self, L["Your Route"], view.note, L["Right-click for options"])
end

local function onHeadUp(self, button)
    if button == "RightButton" then Itinerary.OpenHeadMenu(self) end
end



local function buildSection(frame, page)
    local section = { frame = frame, page = page, rows = {} }
    local head = CreateFrame("Frame", nil, frame)
    head:SetHeight(HEAD_HEIGHT)
    head:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    head.Text = lineOf(head, "pageSub", "rubric")
    head.Text:SetPoint("LEFT", head, "LEFT", 0, 0)
    head.Text:SetText(L["Your Route"])
    head:EnableMouse(true)
    head:SetScript("OnMouseUp", onHeadUp)
    head:SetScript("OnEnter", onHeadEnter)
    head:SetScript("OnLeave", hideTip)
    section.Head = head
    section.Summary = lineOf(frame, "pageSub", "inkGrey")
    section.Summary:SetHeight(LINE_HEIGHT)
    section.Line = lineOf(frame, "pageSub", "inkGrey")
    section.Line:SetHeight(LINE_HEIGHT)
    section.More = lineOf(frame, "pageSub", "inkGrey")
    section.More:SetHeight(LINE_HEIGHT)
    Itinerary.routeSection = section



    local Tome = FGPS.UI.Tome
    local win = Tome and Tome.window
    if win and win.HookScript and not win.fgpsRouteHooked then
        win.fgpsRouteHooked = true
        win:HookScript("OnHide", function(self)
            if self:IsShown() then return end
            Itinerary:OnTomeClosed()
        end)
    end


    local pageFrame = type(page) == "table" and page.frame or nil
    if pageFrame and pageFrame.HookScript and not pageFrame.fgpsRouteHooked then
        pageFrame.fgpsRouteHooked = true
        pageFrame:HookScript("OnHide", function(self)
            local shownWin = FGPS.UI.Tome and FGPS.UI.Tome.window
            if self:IsShown() and shownWin and shownWin:IsShown() then return end
            Itinerary:OnPageHidden()
        end)
    end
    return function(f) return paintSection(section, f) end
end



function Itinerary:RefreshSection()
    local Search = FGPS.UI.Search
    if self.routeSection and Search and Search.IsShown and Search:IsShown() and Search.RefreshSections then
        Search:RefreshSections()
    end
end




function Itinerary:RemoveStop(index)
    local Navigator = FGPS.Navigator
    if Navigator and Navigator.RemoveStop then
        local ok, err = pcall(Navigator.RemoveStop, Navigator, index)
        if not ok then FGPS.Log:Error("RemoveStop failed: %s", tostring(err)) end
    end
    self:RefreshSection()
end

function Itinerary:MoveStop(from, to)
    local Navigator = FGPS.Navigator
    if to < 1 or to > #self.stops or from == to then return end
    if Navigator and Navigator.MoveStop then
        local ok, err = pcall(Navigator.MoveStop, Navigator, from, to)
        if not ok then FGPS.Log:Error("MoveStop failed: %s", tostring(err)) end
    end
    self:RefreshSection()
end



function Itinerary:UpdateOptimizeState()
    if self.optimizeArmedAt and not armed() then self.optimizeArmedAt = nil end
    self:RefreshSection()
end



function Itinerary:Optimize()
    local Navigator = FGPS.Navigator
    if #self.stops < 2 then return false end
    if not armed() then
        self.optimizeArmedAt = now()
        self:UpdateOptimizeState()


        local armedAt = self.optimizeArmedAt
        if C_Timer and C_Timer.After then
            C_Timer.After(OPTIMIZE_CONFIRM_SECONDS + 0.05, function()
                if Itinerary.optimizeArmedAt ~= armedAt then return end
                Itinerary:UpdateOptimizeState()
            end)
        end
        return false
    end
    self.optimizeArmedAt = nil
    if Navigator and Navigator.OptimizeStops then
        local ok, result = pcall(Navigator.OptimizeStops, Navigator)
        if not ok then FGPS.Log:Error("OptimizeStops failed: %s", tostring(result)) end

        if ok and result ~= false then FGPS:Print(L["Stops reordered."]) end
    end
    self:RefreshSection()
    return true
end


function Itinerary:SkipStop()
    local skipped = false
    local Navigator = FGPS.Navigator
    if Navigator and Navigator.SkipStop then
        local ok, result = pcall(Navigator.SkipStop, Navigator)
        if ok then
            skipped = result == true
        else
            skipped = nil
            FGPS.Log:Error("SkipStop failed: %s", tostring(result))
        end
    end
    self:RefreshSection()
    return skipped
end





function Itinerary:CancelJourney()
    local Preview = FGPS.UI.Preview
    self.asked = false
    if Preview and Preview.Cancel then
        Preview:Cancel()
    else
        local Navigator = FGPS.Navigator
        if Navigator and Navigator.Clear then pcall(Navigator.Clear, Navigator, "user") end
    end
    self:RefreshSection()
end






local function openOnRoute()
    local Search, Tome = FGPS.UI.Search, FGPS.UI.Tome
    if not (Search and Search.Show and Tome) then return false end
    if not Search:Show({ section = SECTION, noFocus = true }) then return false end
    Itinerary:RefreshSection()
    return Tome:Current() == pageKey()
end



function Itinerary:Show()
    self.closedByUser = false
    self.asked = true
    return openOnRoute()
end


function Itinerary:Hide()
    local Search, Tome = FGPS.UI.Search, FGPS.UI.Tome
    if not (Search and Search:IsShown() and Tome and Tome.window) then return end
    self.hidingProgrammatically = true
    Tome.window:Hide()
    self.hidingProgrammatically = false
end









function Itinerary:OnTomeClosed()
    if self.hidingProgrammatically or #self.stops < 2 then return end
    local Tome = FGPS.UI.Tome
    if self.showOwed and Tome and Tome.lastPage ~= pageKey() then return end
    self.closedByUser = true
end


function Itinerary:OnPageHidden()
    self.optimizeArmedAt = nil
    self.asked = false
    local Preview = FGPS.UI.Preview
    if Preview and Preview.OnPageHidden then Preview:OnPageHidden() end
end


function Itinerary:IsShown()
    local Search = FGPS.UI.Search
    local section = self.routeSection
    return Search ~= nil and Search:IsShown() == true and section ~= nil and section.frame:IsShown() == true
end




function Itinerary:ShowOwed()
    if not self.showOwed then return false end
    self.showOwed = false
    if self.closedByUser or #navigatorStops() < 2 then return false end
    local Tome = FGPS.UI.Tome
    if not (Tome and Tome.IsShown) or Tome:IsShown() then return false end
    return openOnRoute()
end



function Itinerary:SearchClosed()
    self.showOwed = false
    return false
end



function Itinerary:Toggle()
    local Search, Tome = FGPS.UI.Search, FGPS.UI.Tome
    if Search and Search:IsShown() and Tome then
        if #self.stops > 1 then self.closedByUser = true end
        Tome:Close()
        return
    end
    self:Show()
end







local function openForTheTrip()
    local Tome = FGPS.UI.Tome
    if not (Tome and Tome.IsShown) then return end
    if not Tome:IsShown() then
        openOnRoute()
    elseif not Itinerary:IsShown() then
        Itinerary.showOwed = true
    end
end

local function onItineraryChanged(_, stops)
    if type(stops) ~= "table" then stops = navigatorStops() end
    Itinerary.stops = stops
    if #stops > 1 then
        if not Itinerary.closedByUser then openForTheTrip() end
    else



        Itinerary.closedByUser = false
        Itinerary.showOwed = false
    end
    Itinerary:RefreshSection()
end



local function onJourneyEnded()
    Itinerary.closedByUser = false
    Itinerary.showOwed = false
    Itinerary.optimizeArmedAt = nil
    Itinerary.asked = false
    Itinerary.stops = {}
    Itinerary:RefreshSection()
end

function Itinerary:Init()
    if self.eventsBound then return end
    self.eventsBound = true
    local Events = FGPS.Events
    Events:Register("ITINERARY_CHANGED", onItineraryChanged, self)
    Events:Register("NAV_CANCELLED", onJourneyEnded, self)
    Events:Register("NAV_ARRIVED", function(_, _, isFinal)
        if isFinal ~= false then onJourneyEnded() else Itinerary:RefreshSection() end
    end, self)


    local function onRoute() Itinerary:RefreshSection() end

    Events:Register("ROUTE_STARTED", function()
        if not Itinerary:ShowOwed() then onRoute() end
    end, self)
    Events:Register("ROUTE_UPDATED", onRoute, self)

    Events:Register("SETTINGS_CHANGED", function(_, key)
        if key == "mapClickModifier" or key == "*" then Itinerary:RefreshSection() end
    end, self)
    local Search = FGPS.UI.Search
    if Search and Search.AddSection then
        Search:AddSection(SECTION, Search.SECTION_ORDER and Search.SECTION_ORDER.route or 5, buildSection)
    end
    FGPS.Slash.Register("stops", function(args)
        local word = Util.Lower(Util.Trim(args))


        if word == "skip" then
            if Itinerary:SkipStop() == false then FGPS:Print(L["No stop to skip."]) end
        elseif word == "clear" then


            local Navigator = FGPS.Navigator
            if Navigator and Navigator.Clear and not Navigator:Clear("user") then
                FGPS:Print(L["No route or stops to clear."])
            end
        else Itinerary:Show() end
    end, L["Your Route on the Places page; skip|clear"])
end
