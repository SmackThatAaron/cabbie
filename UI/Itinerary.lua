







local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local type, ipairs, pairs, tostring, format = type, ipairs, pairs, tostring, string.format

local Itinerary = {
    window = nil,
    list = nil,
    items = {},
    stops = {},
    closedByUser = false,
    hidingProgrammatically = false,
    optimizeArmedAt = nil,
}
FGPS.UI.Itinerary = Itinerary

local WINDOW_KEY = "itinerary"
local ROW_HEIGHT = 22
local OPTIMIZE_CONFIRM_SECONDS = 10




local function Frames() return FGPS.UI.Frames end

local function now() return GetTime and GetTime() or 0 end

local FALLBACK_FONTS = { small = "GameFontHighlightSmall", normal = "GameFontHighlight", large = "GameFontNormalLarge", title = "GameFontNormalLarge" }

local function applyLabelColor(fs, key)
    local skin = FGPS.UI and FGPS.UI.Skins and FGPS.UI.Skins.Current and FGPS.UI.Skins.Current()
    local c = skin and skin.colors and skin.colors[key]
    if c then
        fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    elseif key == "textDim" then
        fs:SetTextColor(0.6, 0.6, 0.6)
    elseif key == "title" then
        fs:SetTextColor(1, 0.82, 0)
    end
end

local function makeLabel(parent, kind, text, color)
    local F = Frames()
    if F and F.CreateLabel then
        local ok, fs = pcall(F.CreateLabel, parent, text, { kind = kind, color = color })
        if ok and fs then return fs end
    end
    local fs = parent:CreateFontString(nil, "OVERLAY", FALLBACK_FONTS[kind] or "GameFontHighlightSmall")
    fs:SetText(text or "")
    fs:SetJustifyH("LEFT")
    applyLabelColor(fs, color or "text")
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

local function makeList(parent, rowHeight, renderFn)
    local F = Frames()
    if F and F.CreateScrollList then
        local ok, list = pcall(F.CreateScrollList, parent, rowHeight, renderFn, {})
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
    local legIndex = progress.legIndex or 1
    for i, stop in ipairs(route.stops) do
        if stop.legTo and legIndex <= stop.legTo then
            if i <= #stops then return i end
            return nil
        end
    end
    return nil
end





function Itinerary.BuildItems(stops, currentIndex)
    local items = {}
    for i, dest in ipairs(stops) do
        local marker = (currentIndex == i) and "> " or ""
        items[#items + 1] = { index = i, dest = dest, label = format("%s%d. %s", marker, i, describe(dest)),
                              first = (i == 1), last = (i == #stops), current = (currentIndex == i) }
    end
    return items
end

local function ensureRowWidgets(row)
    if row.fgpsReady then return end
    row.fgpsReady = true
    row.text = row.Text or makeLabel(row, "small", "", "text")
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.remove = makeButton(row, L["X"], nil, 22, 18)
    row.remove:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.down = makeButton(row, L["v"], nil, 22, 18)
    row.down:SetPoint("RIGHT", row.remove, "LEFT", -2, 0)
    row.up = makeButton(row, L["^"], nil, 22, 18)
    row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
    row.text:SetPoint("RIGHT", row.up, "LEFT", -6, 0)
end

function Itinerary.RenderRow(row, item, index)
    ensureRowWidgets(row)
    row.item = item
    row.text:SetText(item.label or "")
    applyLabelColor(row.text, item.current and "accent" or "text")
    setButtonOnClick(row.remove, function() Itinerary:RemoveStop(item.index) end)
    setButtonOnClick(row.up, function() Itinerary:MoveStop(item.index, item.index - 1) end)
    setButtonOnClick(row.down, function() Itinerary:MoveStop(item.index, item.index + 1) end)
    setButtonEnabled(row.up, not item.first)
    setButtonEnabled(row.down, not item.last)
end

function Itinerary:Refresh()
    if not self.window then return end
    self.stops = navigatorStops()
    self.items = Itinerary.BuildItems(self.stops, currentStopIndex(self.stops))
    setListItems(self.list, self.items)
    local w = self.window
    w.fgpsCount:SetText(format(#self.stops == 1 and L["%d stop"] or L["%d stops"], #self.stops))
    setButtonEnabled(w.fgpsButtons.optimize, #self.stops >= 2)
    setButtonEnabled(w.fgpsButtons.skip, #self.stops >= 1)
    setButtonEnabled(w.fgpsButtons.cancel, #self.stops >= 1)
    self:UpdateOptimizeState()
    if #self.stops == 0 and w.fgpsStatus and not self.optimizeArmedAt then
        w.fgpsStatus:SetText(L["No stops yet. Open Search and press Add stop, or right-click a place on the map."])
    end
end




function Itinerary:RemoveStop(index)
    local Navigator = FGPS.Navigator
    if Navigator and Navigator.RemoveStop then
        local ok, err = pcall(Navigator.RemoveStop, Navigator, index)
        if not ok then FGPS.Log:Error("RemoveStop failed: %s", tostring(err)) end
    end
    self:Refresh()
end

function Itinerary:MoveStop(from, to)
    local Navigator = FGPS.Navigator
    if to < 1 or to > #self.stops or from == to then return end
    if Navigator and Navigator.MoveStop then
        local ok, err = pcall(Navigator.MoveStop, Navigator, from, to)
        if not ok then FGPS.Log:Error("MoveStop failed: %s", tostring(err)) end
    end
    self:Refresh()
end

function Itinerary:UpdateOptimizeState()
    local w = self.window
    if not w then return end
    if self.optimizeArmedAt and now() - self.optimizeArmedAt <= OPTIMIZE_CONFIRM_SECONDS then
        setButtonText(w.fgpsButtons.optimize, L["Confirm"])
        w.fgpsStatus:SetText(L["Optimize reorders your stops by estimated travel distance. Click Confirm to apply the new order."])
    else
        self.optimizeArmedAt = nil
        setButtonText(w.fgpsButtons.optimize, L["Optimize"])
        w.fgpsStatus:SetText("")
    end
end


function Itinerary:Optimize()
    local Navigator = FGPS.Navigator
    if #self.stops < 2 then return false end
    if not self.optimizeArmedAt or now() - self.optimizeArmedAt > OPTIMIZE_CONFIRM_SECONDS then
        self.optimizeArmedAt = now()
        self:UpdateOptimizeState()
        return false
    end
    self.optimizeArmedAt = nil
    if Navigator and Navigator.OptimizeStops then
        local ok, err = pcall(Navigator.OptimizeStops, Navigator)
        if not ok then FGPS.Log:Error("OptimizeStops failed: %s", tostring(err)) end
        FGPS:Print(L["Stops reordered."])
    end
    self:Refresh()
    return true
end

function Itinerary:SkipStop()
    local Navigator = FGPS.Navigator
    if Navigator and Navigator.SkipStop then
        local ok, err = pcall(Navigator.SkipStop, Navigator)
        if not ok then FGPS.Log:Error("SkipStop failed: %s", tostring(err)) end
    end
    self:Refresh()
end



function Itinerary:CancelJourney()
    local Navigator = FGPS.Navigator
    if Navigator and Navigator.Clear then pcall(Navigator.Clear, Navigator, "user") end
    self:HideProgrammatically()
end




local function buildWindow()
    local F = Frames()
    if not F or not F.CreateWindow then
        FGPS.Log:Error("UI.Frames.CreateWindow is unavailable; the stops window cannot be built")
        return nil
    end
    local ok, window = pcall(F.CreateWindow, WINDOW_KEY, {
        title = L["Stops"], width = 360, height = 340,
        onClose = function() Itinerary:OnWindowHidden() end,
    })
    if not ok or type(window) ~= "table" then
        FGPS.Log:Error("Frames.CreateWindow failed: %s", tostring(window))
        return nil
    end
    local content, top = contentFrame(window)
    window.fgpsCount = makeLabel(content, "small", "", "title")
    window.fgpsCount:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -(top + 2))
    local listAnchor = CreateFrame("Frame", nil, content)
    listAnchor:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -(top + 20))
    listAnchor:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -2, 60)
    local list = makeList(listAnchor, ROW_HEIGHT, Itinerary.RenderRow)
    if list and list.SetAllPoints then list:SetAllPoints(listAnchor) end
    Itinerary.list = list
    window.fgpsStatus = makeLabel(content, "small", "", "title")
    window.fgpsStatus:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 4, 30)
    window.fgpsStatus:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -4, 30)
    if window.fgpsStatus.SetWordWrap then window.fgpsStatus:SetWordWrap(true) end

    local specs = {
        { key = "optimize", label = "Optimize", fn = function() Itinerary:Optimize() end },
        { key = "skip", label = "Skip stop", fn = function() Itinerary:SkipStop() end },
        { key = "cancel", label = "Cancel route", fn = function() Itinerary:CancelJourney() end },
    }
    window.fgpsButtons = {}
    local previous
    for _, spec in ipairs(specs) do
        local button = makeButton(content, L[spec.label], spec.fn, 110, 22)
        if previous then button:SetPoint("LEFT", previous, "RIGHT", 4, 0) else button:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 2, 2) end
        window.fgpsButtons[spec.key] = button
        previous = button
    end
    if F.ApplySkin then pcall(F.ApplySkin, window) end
    return window
end

function Itinerary:EnsureWindow()
    if self.window then return self.window end
    self.window = buildWindow()
    return self.window
end

function Itinerary:Show()
    local window = self:EnsureWindow()
    if not window then return false end
    self.closedByUser = false
    window:Show()
    self:Refresh()
    return true
end

function Itinerary:HideProgrammatically()
    if self.window and self.window:IsShown() then
        self.hidingProgrammatically = true
        self.window:Hide()
        self.hidingProgrammatically = false
    end
end

function Itinerary:Hide()
    self:HideProgrammatically()
end

function Itinerary:OnWindowHidden()
    if not self.hidingProgrammatically and #self.stops > 1 then

        self.closedByUser = true
    end
    self.optimizeArmedAt = nil
end

function Itinerary:IsShown()
    return self.window ~= nil and self.window:IsShown()
end

function Itinerary:Toggle()
    if self:IsShown() then self:Hide() else self:Show() end
end




local function onItineraryChanged(_, stops)
    if type(stops) ~= "table" then stops = navigatorStops() end
    Itinerary.stops = stops
    if #stops > 1 then
        if not Itinerary.closedByUser then

            local Search = FGPS.UI and FGPS.UI.Search
            local searchOpen = Search and Search.IsShown and Search:IsShown()
            if not searchOpen then
                if not Itinerary.window then Itinerary:EnsureWindow() end
                if Itinerary.window and not Itinerary.window:IsShown() then Itinerary.window:Show() end
            end
        end
        Itinerary:Refresh()
    else
        Itinerary:HideProgrammatically()
        if Itinerary.window then Itinerary:Refresh() end
    end
end

local function onJourneyEnded()
    Itinerary.closedByUser = false
    Itinerary.optimizeArmedAt = nil
    Itinerary.stops = {}
    Itinerary:HideProgrammatically()
end

function Itinerary:Init()
    if self.eventsBound then return end
    self.eventsBound = true
    local Events = FGPS.Events
    Events:Register("ITINERARY_CHANGED", onItineraryChanged, self)
    Events:Register("NAV_CANCELLED", onJourneyEnded, self)
    Events:Register("NAV_ARRIVED", function(_, _, isFinal)
        if isFinal ~= false then onJourneyEnded() elseif Itinerary:IsShown() then Itinerary:Refresh() end
    end, self)
    FGPS.Slash.Register("stops", function(args)
        local word = Util.Lower(Util.Trim(args))
        if word == "skip" then Itinerary:SkipStop()
        elseif word == "clear" then
            local Navigator = FGPS.Navigator
            if Navigator and Navigator.ClearStops then Navigator:ClearStops() end
        else Itinerary:Toggle() end
    end, L["Stops window; skip|clear"])
end
