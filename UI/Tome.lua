


























local ADDON_NAME, FGPS = ...

local type, pairs, ipairs, pcall, tostring = type, pairs, ipairs, pcall, tostring
local sort = table.sort
local Look = FGPS.UI.Look

local Tome = {
    pages = {},
    tabs = {},
    window = nil,
    lastPage = nil,
    initialised = false,
}
FGPS.UI.Tome = Tome

Tome.KEY = "tome"
Tome.TAB_TEMPLATE = "LargeSideTabButtonTemplate"
Tome.DEFAULT_PAGE = "places"

local built = setmetatable({}, { __mode = "k" })
local shownFrame = nil



local function call(key, what, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and FGPS.Log then
        FGPS.Log:Error("Tome page %s %s failed: %s", tostring(key), what, tostring(err))
    end
end


local function orderedKeys()
    local keys = {}
    for key in pairs(Tome.pages) do keys[#keys + 1] = key end
    sort(keys, function(a, b)
        local oa, ob = Tome.pages[a].order, Tome.pages[b].order
        if oa ~= ob then return oa < ob end
        return a < b
    end)
    return keys
end



local function isAvailable(key)
    local page = Tome.pages[key]
    if not page then return false end
    if page.available == nil then return true end
    local ok, yes = pcall(page.available)
    if not ok then return true end
    return yes and true or false
end

local function availableKeys()
    local keys = {}
    for _, key in ipairs(orderedKeys()) do
        if isAvailable(key) then keys[#keys + 1] = key end
    end
    return keys
end

local openPage

local function onTabMouseUp(tab, button, upInside)
    if button ~= "LeftButton" or not upInside then return end
    if tab.fgpsPage == Tome:Current() then return end
    openPage(tab.fgpsPage, nil, true)
end




local function tabFor(key)
    local tab = Tome.tabs[key]
    if tab then return tab end
    local template = Tome.TAB_TEMPLATE
    local ok
    if Look.TomeHas("template", template) then
        ok, tab = pcall(CreateFrame, "Frame", nil, Tome.window, template)
        if not ok or not tab then Look.TomeLacks("template", template) end
    end
    if not ok or not tab then
        Look.NoteOnce("tome:tabs", "Tome: %s missing; the window has no tabs", template)
        return nil
    end
    if type(tab.SetChecked) ~= "function" then
        tab:Hide()
        Look.TomeLacks("template", template)
        Look.NoteOnce("tome:tabs", "Tome: %s has no SetChecked; the window has no tabs", template)
        return nil
    end





    if (tab:GetWidth() or 0) <= 0 or (tab:GetHeight() or 0) <= 0 then
        tab:Hide()
        Look.TomeLacks("template", template)
        Look.NoteOnce("tome:tabs", "Tome: %s came with no size; the window has no tabs", template)
        return nil
    end
    local tokens = Look.TOKENS
    if type(tab.SetFillToInterior) == "function" then
        tab:SetFillToInterior(true)
    elseif tab.Icon then
        tab.Icon:SetSize(tokens.iconBox, tokens.iconBox)
    end
    if tab.SetCustomOnMouseUpHandler then
        tab:SetCustomOnMouseUpHandler(onTabMouseUp)
    else
        tab:HookScript("OnMouseUp", onTabMouseUp)
    end
    Tome.tabs[key] = tab
    return tab
end




local function layoutTabs()
    local win = Tome.window
    if not win then return end
    local current = Tome:Current()
    local listed, previous = {}, nil
    for index, key in ipairs(availableKeys()) do
        local tab = tabFor(key)
        if tab then
            local page = Tome.pages[key]
            listed[tab] = true
            tab.fgpsPage, tab._index = key, index
            tab.tooltipText = page.label
            if tab.Icon then tab.Icon:SetTexture(page.icon) end
            tab:ClearAllPoints()
            if previous then
                tab:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -Look.TOKENS.sideTabGap)
            else
                tab:SetPoint("TOPLEFT", win, "TOPRIGHT", 0, -Look.TOKENS.sideTabTop)
            end
            tab:SetChecked(key == current)
            tab:Show()
            previous = tab
        end
    end
    for _, tab in pairs(Tome.tabs) do
        if not listed[tab] then tab:Hide() end
    end
end



local function onClose(_, sounded)
    if not sounded then Look.PlaySound("IG_QUEST_LOG_CLOSE") end
end

local function ensureWindow()
    if Tome.window then return Tome.window end
    local win = Look.Window({ key = Tome.KEY, title = "", footer = true, onClose = onClose })
    win.fgpsCloseWith = function() Tome:Close() end


    win.Open = function(_, key, opts) return Tome:Open(key, opts) end
    win.Toggle = function(_, key) return Tome:Toggle(key) end
    Tome.window = win
    return win
end



local function defaultPage()
    if Tome.lastPage and isAvailable(Tome.lastPage) then return Tome.lastPage end
    if isAvailable(Tome.DEFAULT_PAGE) then return Tome.DEFAULT_PAGE end
    return availableKeys()[1]
end

local function showPage(key, opts)
    local win, page = Tome.window, Tome.pages[key]
    local state = built[page]
    if not state then
        local frame = CreateFrame("Frame", nil, win.Page)
        frame:SetAllPoints(win.Page)
        frame:Hide()
        state = { frame = frame }
        built[page] = state
        call(key, "build", page.build, frame, win)
    end
    if shownFrame and shownFrame ~= state.frame then shownFrame:Hide() end
    shownFrame = state.frame
    state.frame:Show()
    Tome.lastPage = key
    win:SetTitleText(page.label)
    for tabKey, tab in pairs(Tome.tabs) do tab:SetChecked(tabKey == key) end
    if page.show then call(key, "show", page.show, state.frame, opts) end
    if page.footer then
        call(key, "footer", page.footer, win)
    else
        win:SetFooterButtons({})
        if win.FooterNote then win.FooterNote:SetText("") end
    end
end




function Tome.RegisterPage(key, page)
    if type(key) ~= "string" or key == "" or type(page) ~= "table" then return false end
    if type(page.label) ~= "string" or page.label == "" then return false end
    if type(page.order) ~= "number" or type(page.build) ~= "function" then return false end
    if page.show ~= nil and type(page.show) ~= "function" then return false end
    if page.footer ~= nil and type(page.footer) ~= "function" then return false end
    if page.available ~= nil and type(page.available) ~= "function" then return false end
    local onWindow = key == Tome:Current()
    Tome.pages[key] = page
    if Tome.window then layoutTabs() end
    if onWindow then showPage(key) end
    return true
end



openPage = function(key, opts, fromTab)
    local win = ensureWindow()
    local wasShown, from = Tome:IsShown(), Tome:Current()
    layoutTabs()
    showPage(key, opts)
    if not wasShown then
        win:FadeIn(fromTab)
    elseif from ~= key and not fromTab then
        Look.PlaySound("IG_ABILITY_PAGE_TURN")
    end
    return true
end



function Tome:Open(key, opts)
    if key == nil then key = defaultPage() end
    if key == nil or not self.pages[key] or not isAvailable(key) then return false end
    return openPage(key, opts, false)
end



function Tome.RefreshPages()
    if not Tome.window then return end
    layoutTabs()
    local current = Tome:Current()
    if current and not isAvailable(current) then
        local key = defaultPage()
        if key then openPage(key, nil, false) else Tome:Close() end
    end
end


function Tome:Close()
    if not self:IsShown() then return false end
    return self.window:FadeOut() == true
end



function Tome:Toggle(key)
    if self:IsShown() and (key == nil or key == self:Current()) then return self:Close() end
    return self:Open(key)
end


function Tome:IsShown()
    local win = self.window
    return win ~= nil and win:IsShown() == true and not win.fgpsClosing
end


function Tome:Current()
    if self:IsShown() then return self.lastPage end
    return nil
end

function Tome:Init()
    self.initialised = true
end
