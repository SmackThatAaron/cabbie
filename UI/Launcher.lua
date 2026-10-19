-- Cabbie/UI/Launcher.lua
-- A small compass button on the minimap cluster so the player can open search without typing
-- /cabbie (U31). Right-click clears the trip the same way the world-map compass does.
local ADDON_NAME, FGPS = ...

local L = FGPS.L

local Launcher = {
    button = nil,
    BUTTON_SIZE = 28,
    BUTTON_ICON = "Interface\\AddOns\\Cabbie\\Media\\icon",
}
FGPS.UI.Launcher = Launcher

FGPS.UI.AddSettingDefault("minimapButton", true)

local function settings()
    return FGPS.DB and FGPS.DB.settings or nil
end

local function wanted()
    local s = settings()
    return not s or s.minimapButton ~= false
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

local function createButton()
    if Launcher.button then return Launcher.button end
    local parent = MinimapCluster or Minimap or UIParent
    if type(parent) ~= "table" then return nil end
    -- No name: a named frame is a global, and nothing reads this one by name.
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(Launcher.BUTTON_SIZE, Launcher.BUTTON_SIZE)
    button.Icon = button:CreateTexture(nil, "ARTWORK")
    button.Icon:SetAllPoints(button)
    button.Icon:SetTexture(Launcher.BUTTON_ICON)
    if button.SetHighlightTexture then
        pcall(button.SetHighlightTexture, button, "Interface\\Buttons\\ButtonHilight-Square", "ADD")
    end
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            Launcher:ClearAll()
        else
            Launcher:ToggleSearch()
        end
    end)
    button:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L["Cabbie"] or "Cabbie")
        GameTooltip:AddLine(L["Open the Cabbie destination search"] or "Open search", 1, 1, 1, true)
        GameTooltip:AddLine(L["Right-click: clear the trip"] or "Right-click: clear the trip", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    -- Bottom-left of the cluster, clear of the zone text and tracking eye.
    button:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 2, 2)
    if button.SetFrameStrata then button:SetFrameStrata("MEDIUM") end
    Launcher.button = button
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

function Launcher:Init()
    self:UpdateVisibility()
    local Events = FGPS.Events
    if Events and Events.Register then
        Events:Register("SETTINGS_CHANGED", function(_, path)
            if path == "minimapButton" or path == "*" then
                Launcher:UpdateVisibility()
            end
        end, self)
    end
end

return Launcher
