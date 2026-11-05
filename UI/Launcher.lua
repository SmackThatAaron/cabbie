













local ADDON_NAME, FGPS = ...

local L = FGPS.L
local type, tonumber = type, tonumber
local rad, deg, cos, sin, atan2, sqrt, max, min = math.rad, math.deg, math.cos, math.sin, math.atan2, math.sqrt, math.max, math.min

local Launcher = {
    button = nil,
    BUTTON_SIZE = 31,
    BUTTON_ICON = "Interface\\AddOns\\Cabbie\\Media\\icon",
    BORDER = "Interface\\Minimap\\MiniMap-TrackingBorder",
    BACKGROUND = "Interface\\Minimap\\UI-Minimap-Background",
    HIGHLIGHT = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight",
    DEFAULT_ANGLE = 225,
    EDGE_OUTSET = 5,
}
FGPS.UI.Launcher = Launcher



FGPS.UI.AddSettingDefault("minimapButton", false)
FGPS.UI.AddSettingDefault("minimapButtonAngle", Launcher.DEFAULT_ANGLE)

local function settings()
    return FGPS.DB and FGPS.DB.settings or nil
end


local function wanted()
    local s = settings()
    return s ~= nil and s.minimapButton == true
end


function Launcher.Angle()
    local s = settings()
    local angle = s and tonumber(s.minimapButtonAngle)
    if not angle or angle ~= angle then return Launcher.DEFAULT_ANGLE end
    return angle % 360
end




function Launcher.Offset(angle)
    local minimap = Minimap
    local w = (minimap and minimap.GetWidth and minimap:GetWidth() or 140) / 2 + Launcher.EDGE_OUTSET
    local h = (minimap and minimap.GetHeight and minimap:GetHeight() or 140) / 2 + Launcher.EDGE_OUTSET
    local x, y = cos(rad(angle)), sin(rad(angle))
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    if shape == "SQUARE" then
        x = max(-w, min(x * sqrt(2) * w, w))
        y = max(-h, min(y * sqrt(2) * h, h))
        return x, y
    end
    return x * w, y * h
end

function Launcher:Place(angle)
    local button = self.button
    if not button or not Minimap then return end
    local x, y = Launcher.Offset(angle or Launcher.Angle())
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end


function Launcher.CursorAngle()
    if not (Minimap and Minimap.GetCenter and GetCursorPosition) then return nil end
    local cx, cy = Minimap:GetCenter()
    if not cx then return nil end
    local px, py = GetCursorPosition()
    local scale = Minimap.GetEffectiveScale and Minimap:GetEffectiveScale() or 1
    if not scale or scale <= 0 then scale = 1 end
    return deg(atan2(py / scale - cy, px / scale - cx)) % 360
end

local function followCursor()
    local angle = Launcher.CursorAngle()
    if angle then
        Launcher.dragAngle = angle
        Launcher:Place(angle)
    end
end

function Launcher:StartDrag()
    local button = self.button
    if not button then return end
    self.dragging = true
    button:SetScript("OnUpdate", followCursor)
    followCursor()
end

function Launcher:StopDrag()
    local button = self.button
    if not button then return end
    button:SetScript("OnUpdate", nil)
    self.dragging = false
    local angle = self.dragAngle
    self.dragAngle = nil
    if angle and FGPS.DB and FGPS.DB.Set then
        FGPS.DB:Set("minimapButtonAngle", angle)
    end
    self:Place()
end



function Launcher:ClearAll()
    local WorldMap = FGPS.UI.WorldMap
    if WorldMap and WorldMap.ClearAll then
        WorldMap:ClearAll()
        return
    end
    local Navigator = FGPS.Navigator
    if Navigator and Navigator.Clear then
        pcall(Navigator.Clear, Navigator, "user")
    end
end

function Launcher:ToggleSearch()
    local Search = FGPS.UI.Search
    if not Search then return end
    if Search.IsShown and Search:IsShown() and Search.Hide then
        Search:Hide()
        return
    end
    if Search.Show then Search:Show() end
end




function Launcher.ClickHint()
    return L["Click to open"] .. " \194\183 " .. L["Right-click for options"]
end



local function somethingIsSet()
    local WorldMap = FGPS.UI.WorldMap
    if WorldMap and WorldMap.SomethingIsSet then return WorldMap.SomethingIsSet() and true or false end
    local Navigator = FGPS.Navigator
    if Navigator and Navigator.HasAnythingSet then
        local ok, set = pcall(Navigator.HasAnythingSet, Navigator)
        return ok and set and true or false
    end
    return false
end






function Launcher.MenuEntries()
    local UI = FGPS.UI
    return {
        { label = L["Optimized Leveling"], onClick = function()
            local QuestPanel = UI.QuestPanel
            if QuestPanel and QuestPanel.Show then QuestPanel:Show({ tab = "leveling" }) end
        end },
        { label = L["Settings"], onClick = function()
            local Settings = UI.Settings
            if Settings and Settings.Open then Settings:Open() end
        end },
        { label = L["Stop Route"], onClick = function() Launcher:ClearAll() end,
          disabled = not somethingIsSet() or nil, enabled = somethingIsSet, destructive = true },
    }
end








local function generateMenu(_, root)
    if type(root) ~= "table" or type(root.CreateButton) ~= "function" then return end
    if type(root.CreateTitle) == "function" then root:CreateTitle(L["Cabbie"]) end
    for _, entry in ipairs(Launcher.MenuEntries()) do
        local create = root.CreateButton
        if entry.destructive then
            if type(root.CreateDivider) == "function" then root:CreateDivider() end
            if type(root.CreateRedHighlightButton) == "function" then create = root.CreateRedHighlightButton end
        end
        local element = create(root, entry.label, entry.onClick)
        local enabled = entry.enabled
        if type(element) == "table" and type(element.SetEnabled) == "function" then
            if type(enabled) == "function" then
                element:SetEnabled(function()
                    local ok, yes = pcall(enabled)
                    return ok and yes and true or false
                end)
            elseif entry.disabled then
                element:SetEnabled(false)
            end
        end
    end
end





function Launcher:OpenMenu(owner)
    local Look = FGPS.UI.Look
    if not (Look and Look.TomeHas and Look.TomeHas("global", "MenuUtil")) then
        if Look and Look.NoteOnce then
            Look.NoteOnce("launcher:menu", "Launcher: no MenuUtil in this client; a right-click opens no menu")
        end
        return nil
    end
    if type(MenuUtil) ~= "table" or type(MenuUtil.CreateContextMenu) ~= "function" then return nil end
    if GameTooltip and owner and GameTooltip.IsOwned and GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
    return MenuUtil.CreateContextMenu(owner, generateMenu)
end

local function createButton()
    if Launcher.button then return Launcher.button end
    local parent = Minimap
    if type(parent) ~= "table" then return nil end

    local button = CreateFrame("Button", nil, parent)
    button:SetSize(Launcher.BUTTON_SIZE, Launcher.BUTTON_SIZE)
    if button.SetFrameStrata then button:SetFrameStrata("MEDIUM") end
    if button.SetFrameLevel then button:SetFrameLevel(8) end


    button.Background = button:CreateTexture(nil, "BACKGROUND")
    button.Background:SetSize(20, 20)
    button.Background:SetTexture(Launcher.BACKGROUND)
    button.Background:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -5)
    button.Icon = button:CreateTexture(nil, "ARTWORK")
    button.Icon:SetSize(17, 17)
    button.Icon:SetTexture(Launcher.BUTTON_ICON)
    button.Icon:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -6)
    button.Border = button:CreateTexture(nil, "OVERLAY")
    button.Border:SetSize(53, 53)
    button.Border:SetTexture(Launcher.BORDER)
    button.Border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    if button.SetHighlightTexture then
        pcall(button.SetHighlightTexture, button, Launcher.HIGHLIGHT, "ADD")
    end
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            Launcher:OpenMenu(self)
        else
            Launcher:ToggleSearch()
        end
    end)
    button:SetScript("OnDragStart", function() Launcher:StartDrag() end)
    button:SetScript("OnDragStop", function() Launcher:StopDrag() end)


    button:SetScript("OnHide", function() if Launcher.dragging then Launcher:StopDrag() end end)


    button:SetScript("OnEnter", function(self)
        local Look = FGPS.UI.Look
        if Launcher.dragging or not (Look and Look.Tooltip) then return end
        Look.Tooltip(self, L["Cabbie"], nil, Launcher.ClickHint(), "ANCHOR_LEFT")
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    Launcher.button = button
    Launcher:Place()
    return button
end

function Launcher:UpdateVisibility()
    local button = createButton()
    if not button then return false end
    if wanted() then
        button:Show()
        return true
    end
    button:Hide()
    return false
end









local function guarded(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and FGPS.Log and FGPS.Log.Error then
        pcall(FGPS.Log.Error, FGPS.Log, "Launcher: add-on compartment: %s", tostring(err))
    end
end

local function compartmentClick(mouseButton)
    if type(mouseButton) == "table" then mouseButton = mouseButton.buttonName end
    if mouseButton ~= "RightButton" then
        Launcher:ToggleSearch()
        return
    end



    local timer = C_Timer
    if type(timer) == "table" and type(timer.After) == "function" then
        timer.After(0, function() guarded(Launcher.OpenMenu, Launcher, nil) end)
    else
        Launcher:OpenMenu(nil)
    end
end

local function compartmentEnter(menuButton)
    local Look = FGPS.UI.Look
    if type(menuButton) ~= "table" or not (Look and Look.Tooltip) then return end


    Look.Tooltip(menuButton, L["Cabbie"], nil, Launcher.ClickHint(), "ANCHOR_LEFT")
end

local function compartmentLeave(menuButton)
    local tooltip = GameTooltip
    if type(tooltip) ~= "table" or type(tooltip.Hide) ~= "function" then return end
    if menuButton ~= nil and type(tooltip.IsOwned) == "function" and not tooltip:IsOwned(menuButton) then return end
    tooltip:Hide()
end

function Cabbie_AddonCompartmentClick(_, mouseButton)
    guarded(compartmentClick, mouseButton)
end

function Cabbie_AddonCompartmentEnter(_, menuButton)
    guarded(compartmentEnter, menuButton)
end

function Cabbie_AddonCompartmentLeave(_, menuButton)
    guarded(compartmentLeave, menuButton)
end

function Launcher:Init()
    self:UpdateVisibility()

    if self.eventsBound then return end
    local Events = FGPS.Events
    if Events and Events.Register then
        self.eventsBound = true
        Events:Register("SETTINGS_CHANGED", function(_, path)
            if path == "minimapButton" or path == "*" then
                Launcher:UpdateVisibility()
            end
            if (path == "minimapButtonAngle" or path == "*") and not Launcher.dragging then
                Launcher:Place()
            end
        end, self)
    end
end

return Launcher
