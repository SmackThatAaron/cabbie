-- Cabbie/UI/Skins.lua
-- The visual preset. One skin, "minimal" (an unobtrusive flat look), is the only preset; a saved
-- name of one that is gone (modern, classic) loads as it (Core/DB.lua). Windows that wear the
-- game's own look (UI/Look.lua) keep it whatever the skin. A skin is a plain table read by
-- UI/Frames.lua and the HUD modules:
--
--   { name, label, font, titleFont, fontSize, smallFontSize, largeFontSize, titleFontSize,
--     colors = { bg, border, text, textDim, title, accent, routeVerified, routeUnverified, arrow,
--                button, buttonHover, buttonBorder, selection, highlight, editBox, titleBar },
--     backdrop, buttonBackdrop, dotTexture, pinTexture,
--     buttonTemplate, panelAlpha, titleHeight, inset, closeButtonTemplate }
--
-- Skins.Apply(name) re-skins every frame registered with UI/Frames.lua and never touches the
-- destination, routing preferences or custom positions; only Skins.Apply(name, { resetLayout = true })
-- re-applies the default positions through UI/Positions.lua.
local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local type, pairs, ipairs, tostring = type, pairs, ipairs, tostring

-------------------------------------------------------------------------------
-- Settings schema contributed by UI modules
-------------------------------------------------------------------------------
-- Core/DB.lua owns the settings schema, but a UI module that introduces a preference of its own
-- would otherwise have to edit that shared file. This helper lets the owning module declare its
-- own defaults at file scope, which runs before ADDON_LOADED and therefore before DB:Init applies
-- them; a reset picks them up through the same table. Nothing overwrites a key that already
-- exists, so Core/DB.lua always wins when a preference later moves into the schema proper.
--   FGPS.UI.AddSettingDefault("cues", { enabled = false, ... })
function FGPS.UI.AddSettingDefault(key, value)
    local defaults = FGPS.DB and FGPS.DB.defaults
    local settings = defaults and defaults.settings
    if type(settings) ~= "table" then return false end
    if settings[key] ~= nil then return false end
    settings[key] = value
    return true
end

local Skins = {
    presets = {},
    order = { "minimal" },
    current = nil,          -- resolved copy of the active preset
    currentName = nil,
    applying = false,       -- re-entrancy guard for the SETTINGS_CHANGED bridge
    initialised = false,
}
FGPS.UI.Skins = Skins

Skins.MEDIA = "Interface\\AddOns\\Cabbie\\Media\\"
Skins.DEFAULT = "minimal"
Skins.WHITE = "Interface\\Buttons\\WHITE8x8"

local FONT_NORMAL = "Fonts\\FRIZQT__.TTF"

-------------------------------------------------------------------------------
-- Preset definitions
-------------------------------------------------------------------------------
Skins.presets.minimal = {
    name = "minimal",
    label = L["Minimal"],
    font = FONT_NORMAL,
    titleFont = FONT_NORMAL,
    fontSize = 12,
    smallFontSize = 10,
    largeFontSize = 16,
    titleFontSize = 12,
    colors = {
        bg = { 0.05, 0.05, 0.06, 0.82 },
        border = { 0.28, 0.28, 0.31, 0.9 },
        text = { 0.93, 0.93, 0.93, 1 },
        textDim = { 0.66, 0.66, 0.68, 1 },
        title = { 0.93, 0.93, 0.93, 1 },
        accent = { 0.31, 0.76, 0.97, 1 },
        routeVerified = { 0.31, 0.76, 0.97, 1 },
        routeUnverified = { 1.0, 0.64, 0.22, 1 },
        routeTransport = { 0.80, 0.65, 1.00, 0.9 },
        arrow = { 1, 1, 1, 1 },
        arrowOutline = { 0, 0, 0, 0.85 },
        button = { 0.13, 0.13, 0.15, 1 },
        buttonHover = { 0.20, 0.20, 0.23, 1 },
        buttonBorder = { 0.32, 0.32, 0.35, 1 },
        selection = { 0.31, 0.76, 0.97, 0.25 },
        highlight = { 1, 1, 1, 0.07 },
        editBox = { 0.02, 0.02, 0.03, 0.9 },
        titleBar = { 0.10, 0.10, 0.12, 1 },
    },
    backdrop = { bgFile = Skins.WHITE, edgeFile = Skins.WHITE, edgeSize = 1,
                 insets = { left = 1, right = 1, top = 1, bottom = 1 } },
    buttonBackdrop = { bgFile = Skins.WHITE, edgeFile = Skins.WHITE, edgeSize = 1,
                       insets = { left = 1, right = 1, top = 1, bottom = 1 } },
    dotTexture = Skins.MEDIA .. "dot",
    pinTexture = Skins.MEDIA .. "pin",
    buttonTemplate = nil,
    closeButtonTemplate = nil,
    panelAlpha = 0.9,
    titleHeight = 20,
    inset = 8,
    titleBarStyle = "flat",     -- "flat" draws a tinted strip; "none" relies on the border texture
    sliderStyle = "flat",       -- "flat" thin track and accent thumb; "blizzard" default slider art
}

-------------------------------------------------------------------------------
-- Colour schemes (accessibility)
-------------------------------------------------------------------------------
-- A preset chooses colours for looks; a colour scheme replaces the few colours that carry MEANING
-- (verified route, unverified route, transport, accent) with a set that stays distinguishable for
-- the common forms of colour blindness. The values are the blue / vermillion / reddish-purple /
-- sky-blue of the Okabe-Ito qualitative palette, which was designed so that no pair collapses
-- under deuteranopia, protanopia or tritanopia and every pair also differs in lightness, so the
-- lines stay apart in greyscale too.
--
-- Colour is never the only cue in any case: the world map draws unverified stretches dashed, the
-- minimap draws them as larger hollow dots, the arrow shows a ring, the preview says how many
-- yards are estimated and the service list carries a "(straight line)" flag. The scheme is here so
-- that the colours agree with those cues instead of fighting them.
Skins.COLOR_SCHEMES = {
    preset = { label = L["Preset colours"] },
    colorblind = {
        label = L["Colour-blind friendly"],
        colors = {
            routeVerified = { 0.00, 0.45, 0.70, 1 },     -- #0072B2 blue
            routeUnverified = { 0.84, 0.37, 0.00, 1 },   -- #D65F00 vermillion
            routeTransport = { 0.80, 0.47, 0.65, 1 },    -- #CC79A7 reddish purple
            accent = { 0.34, 0.71, 0.91, 1 },            -- #57B4E9 sky blue
        },
    },
}
Skins.COLOR_SCHEME_ORDER = { "preset", "colorblind" }
Skins.DEFAULT_COLOR_SCHEME = "preset"

FGPS.UI.AddSettingDefault("accessibility", { colorScheme = Skins.DEFAULT_COLOR_SCHEME })

function Skins.IsValidColorScheme(name)
    return type(name) == "string" and Skins.COLOR_SCHEMES[name] ~= nil
end

-- The configured colour scheme name (settings.accessibility.colorScheme), validated.
function Skins.ColorSchemeName()
    local db = FGPS.DB
    local access = db and db.settings and db.settings.accessibility
    local name = type(access) == "table" and access.colorScheme or nil
    if Skins.IsValidColorScheme(name) then return name end
    return Skins.DEFAULT_COLOR_SCHEME
end

function Skins.ColorScheme()
    return Skins.COLOR_SCHEMES[Skins.ColorSchemeName()]
end

function Skins.ColorSchemeList()
    local out = {}
    for _, name in ipairs(Skins.COLOR_SCHEME_ORDER) do
        out[#out + 1] = { name = name, label = Skins.COLOR_SCHEMES[name].label }
    end
    return out
end

-- Overwrites the meaning-carrying colours of a resolved skin with the active scheme's.
local function applyColorScheme(skin)
    local scheme = Skins.ColorScheme()
    if not scheme or type(scheme.colors) ~= "table" then return skin end
    for key, color in pairs(scheme.colors) do
        skin.colors[key] = Util.ShallowCopy(color)
    end
    skin.colors.selection = { scheme.colors.accent[1], scheme.colors.accent[2], scheme.colors.accent[3], 0.30 }
    skin.colorScheme = Skins.ColorSchemeName()
    return skin
end

-------------------------------------------------------------------------------
-- Resolution
-------------------------------------------------------------------------------
function Skins.IsValid(name)
    return type(name) == "string" and Skins.presets[name] ~= nil
end

function Skins.List()
    local out = {}
    for _, name in ipairs(Skins.order) do
        out[#out + 1] = { name = name, label = Skins.presets[name].label }
    end
    return out
end

-- Returns a fresh resolved copy of a preset (colour scheme applied); callers may keep it
-- without affecting the preset definition. Unknown names resolve to the default preset.
function Skins.Get(name)
    if not Skins.IsValid(name) then name = Skins.DEFAULT end
    local skin = Util.DeepCopy(Skins.presets[name])
    skin.colorScheme = Skins.DEFAULT_COLOR_SCHEME
    return applyColorScheme(skin)
end

function Skins.Current()
    if not Skins.current then
        Skins.current = Skins.Get(Skins.CurrentName())
        Skins.currentName = Skins.current.name
    end
    return Skins.current
end

-- The configured preset name (settings.preset), validated.
function Skins.CurrentName()
    if Skins.currentName then return Skins.currentName end
    local db = FGPS.DB
    local name = db and db.settings and db.settings.preset
    if Skins.IsValid(name) then return name end
    return Skins.DEFAULT
end

-------------------------------------------------------------------------------
-- Application
-------------------------------------------------------------------------------
-- Applies a preset: stores it in settings, rebuilds the resolved skin, re-skins every registered
-- frame and fires PRESET_CHANGED then UI_PRESET_APPLIED. Destination, routing preferences and
-- custom positions are untouched; opts.resetLayout = true additionally restores default positions.
function Skins.Apply(name, opts)
    if not Skins.IsValid(name) then
        if FGPS.Log then FGPS.Log:Warn("Unknown UI preset '%s'; using '%s'", tostring(name), Skins.DEFAULT) end
        name = Skins.DEFAULT
    end
    if Skins.applying then return Skins.current end
    Skins.applying = true

    local db = FGPS.DB
    if db and db.settings and db.settings.preset ~= name and db.Set then
        -- DB:Set fires SETTINGS_CHANGED("preset"); the re-entrancy guard above swallows the echo.
        db:Set("preset", name)
    end

    Skins.currentName = name
    Skins.current = Skins.Get(name)
    local skin = Skins.current

    if FGPS.Events then FGPS.Events:Fire("PRESET_CHANGED", name) end

    local frames = FGPS.UI.Frames
    if frames and frames.ApplyAll then
        local ok, err = pcall(frames.ApplyAll, skin)
        if not ok and FGPS.Log then FGPS.Log:Error("Re-skinning frames failed: %s", tostring(err)) end
    end

    if opts and opts.resetLayout then
        local positions = FGPS.UI.Positions
        if positions and positions.ResetAll then
            local ok, err = pcall(positions.ResetAll)
            if not ok and FGPS.Log then FGPS.Log:Error("Resetting positions failed: %s", tostring(err)) end
        end
    end

    Skins.applying = false
    if FGPS.Events then FGPS.Events:Fire("UI_PRESET_APPLIED", name) end
    return skin
end

-- Re-resolves the current skin (for example after the colour scheme or the text size changed) and
-- re-skins registered frames without changing the preset.
function Skins.Refresh()
    Skins.current = Skins.Get(Skins.CurrentName())
    local frames = FGPS.UI.Frames
    if frames and frames.ApplyAll then pcall(frames.ApplyAll, Skins.current) end
    if FGPS.Events then FGPS.Events:Fire("UI_PRESET_APPLIED", Skins.current.name) end
    return Skins.current
end

-------------------------------------------------------------------------------
-- Colour helpers shared by UI modules
-------------------------------------------------------------------------------
-- Unpacks a colour table {r, g, b, a}; alphaOverride replaces the stored alpha.
function Skins.RGBA(color, alphaOverride)
    if type(color) ~= "table" then return 1, 1, 1, alphaOverride or 1 end
    return color[1] or 1, color[2] or 1, color[3] or 1, alphaOverride or color[4] or 1
end

-- "|cffRRGGBB" escape for a colour table.
function Skins.Hex(color)
    local r, g, b = Skins.RGBA(color)
    return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------
local function onSettingsChanged(_, key, value)
    if Skins.applying then return end
    if key == "preset" then
        if Skins.IsValid(value) and value ~= Skins.currentName then Skins.Apply(value) end
    elseif key == "*" then
        Skins.currentName = nil
        local name = Skins.CurrentName()
        if name ~= (Skins.current and Skins.current.name) then Skins.Apply(name) else Skins.Refresh() end
    elseif key == "accessibility.colorScheme" or key == "textSize" then
        Skins.Refresh()
    end
end

function Skins:Init()
    Skins.currentName = nil
    Skins.current = Skins.Get(Skins.CurrentName())
    Skins.currentName = Skins.current.name
    if not Skins.initialised and FGPS.Events then
        FGPS.Events:Register("SETTINGS_CHANGED", onSettingsChanged, Skins)
        Skins.initialised = true
    end
    return Skins
end
