-- Cabbie/UI/Launcher.lua
-- A minimap button like other add-ons' ones, so the player can open search without typing
-- /cabbie (U31): round, in the game's minimap button border, on the minimap's edge. Left-click
-- opens search, right-click clears the trip the same way the world-map compass does, and a drag
-- with the left button moves it around the edge. Its place on the edge is settings.minimapButtonAngle
-- (degrees, counter-clockwise from the right, as math.atan2 gives it), so it stays there after a
-- reload. No library: LibDBIcon is not shipped, and this is the little of it Cabbie needs.
local ADDON_NAME, FGPS = ...

local L = FGPS.L
local type, tonumber = type, tonumber
local rad, deg, cos, sin, atan2, sqrt, max, min = math.rad, math.deg, math.cos, math.sin, math.atan2, math.sqrt, math.max, math.min

local Launcher = {
    button = nil,
    BUTTON_SIZE = 31,           -- the game's minimap button: a 31 px button in a 53 px tracking border
    BUTTON_ICON = "Interface\\AddOns\\Cabbie\\Media\\icon",
    BORDER = "Interface\\Minimap\\MiniMap-TrackingBorder",
    BACKGROUND = "Interface\\Minimap\\UI-Minimap-Background",
    HIGHLIGHT = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight",
    DEFAULT_ANGLE = 225,        -- bottom left, where the button stood before it went on the edge
    EDGE_OUTSET = 5,            -- pixels the button's centre sits outside the minimap's rim
}
FGPS.UI.Launcher = Launcher

FGPS.UI.AddSettingDefault("minimapButton", true)
FGPS.UI.AddSettingDefault("minimapButtonAngle", Launcher.DEFAULT_ANGLE)

local function settings()
    return FGPS.DB and FGPS.DB.settings or nil
end

local function wanted()
    local s = settings()
    return not s or s.minimapButton ~= false
end

-- The saved angle in [0, 360), or the default when nothing usable is saved.
function Launcher.Angle()
    local s = settings()
    local angle = s and tonumber(s.minimapButtonAngle)
    if not angle or angle ~= angle then return Launcher.DEFAULT_ANGLE end
    return angle % 360
end

-- Where the button's centre goes for an angle, relative to the minimap's centre. On a round
-- minimap that is the rim; on a square one (GetMinimapShape() from a minimap add-on), the edge
-- of the square, reached by pushing the point out along the diagonal and clamping it.
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

-- The angle of the mouse around the minimap's centre, in degrees.
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

local function createButton()
    if Launcher.button then return Launcher.button end
    local parent = Minimap
    if type(parent) ~= "table" then return nil end
    -- No name: a named frame is a global, and nothing reads this one by name.
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(Launcher.BUTTON_SIZE, Launcher.BUTTON_SIZE)
    if button.SetFrameStrata then button:SetFrameStrata("MEDIUM") end
    if button.SetFrameLevel then button:SetFrameLevel(8) end
    -- The pieces and offsets of the game's own minimap buttons: a dark disc, the icon on it and the
    -- round tracking border over both, its top left corner on the button's.
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
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            Launcher:ClearAll()
        else
            Launcher:ToggleSearch()
        end
    end)
    button:SetScript("OnDragStart", function() Launcher:StartDrag() end)
    button:SetScript("OnDragStop", function() Launcher:StopDrag() end)
    button:SetScript("OnEnter", function(self)
        if not GameTooltip or Launcher.dragging then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L["Cabbie"] or "Cabbie")
        GameTooltip:AddLine(L["Open the Cabbie destination search"] or "Open search", 1, 1, 1, true)
        GameTooltip:AddLine(L["Right-click: clear the route"] or "Right-click: clear the route", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(L["Drag: move the button around the minimap"], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
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

function Launcher:Init()
    self:UpdateVisibility()
    local Events = FGPS.Events
    if Events and Events.Register then
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
