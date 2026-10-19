-- Cabbie/UI/Skins.lua
-- Visual presets. Three coherent skins share one set of functionality: "minimal" (default, an
-- unobtrusive flat look with a small arrow), "modern" (compact dark panels with restrained colours
-- and optional faction accents) and "classic" (parchment background with the game's own dialog
-- border textures). A skin is a plain table read by UI/Frames.lua and the HUD modules:
--
--   { name, label, font, titleFont, fontSize, smallFontSize, largeFontSize, titleFontSize,
--     colors = { bg, border, text, textDim, title, accent, routeVerified, routeUnverified, arrow,
--                button, buttonHover, buttonBorder, selection, highlight, editBox, titleBar },
--     backdrop, buttonBackdrop, arrowTexture, arrowSize, ringTexture, dotTexture, pinTexture,
--     buttonTemplate, panelAlpha, factionAccent, titleHeight, inset, closeButtonTemplate }
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
    order = { "minimal", "modern", "classic" },
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
local FONT_TITLE_CLASSIC = "Fonts\\MORPHEUS.TTF"

-- Faction accent colours (used by presets with factionAccent = true unless settings.factionAccent
-- is explicitly false).
Skins.FACTION_COLORS = {
    Alliance = { 0.29, 0.53, 0.90, 1 },
    Horde = { 0.85, 0.24, 0.22, 1 },
}

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
    arrowTexture = Skins.MEDIA .. "arrow_minimal",
    arrowSize = 40,
    ringTexture = Skins.MEDIA .. "ring",
    dotTexture = Skins.MEDIA .. "dot",
    pinTexture = Skins.MEDIA .. "pin",
    buttonTemplate = nil,
    closeButtonTemplate = nil,
    panelAlpha = 0.9,
    factionAccent = false,
    titleHeight = 20,
    inset = 8,
    titleBarStyle = "flat",     -- "flat" draws a tinted strip; "none" relies on the border texture
    sliderStyle = "flat",       -- "flat" thin track and accent thumb; "blizzard" default slider art
}

Skins.presets.modern = {
    name = "modern",
    label = L["Modern"],
    font = FONT_NORMAL,
    titleFont = FONT_NORMAL,
    fontSize = 12,
    smallFontSize = 10,
    largeFontSize = 18,
    titleFontSize = 13,
    colors = {
        bg = { 0.09, 0.10, 0.12, 0.95 },
        border = { 0.20, 0.22, 0.26, 1 },
        text = { 0.90, 0.91, 0.93, 1 },
        textDim = { 0.58, 0.61, 0.66, 1 },
        title = { 0.96, 0.96, 0.97, 1 },
        accent = { 0.36, 0.62, 0.86, 1 },
        routeVerified = { 0.36, 0.72, 0.90, 1 },
        routeUnverified = { 0.95, 0.60, 0.25, 1 },
        routeTransport = { 0.76, 0.62, 0.98, 0.9 },
        arrow = { 0.96, 0.96, 0.98, 1 },
        arrowOutline = { 0, 0, 0, 0.85 },
        button = { 0.15, 0.17, 0.20, 1 },
        buttonHover = { 0.22, 0.25, 0.30, 1 },
        buttonBorder = { 0.27, 0.30, 0.35, 1 },
        selection = { 0.36, 0.62, 0.86, 0.30 },
        highlight = { 1, 1, 1, 0.06 },
        editBox = { 0.05, 0.06, 0.07, 1 },
        titleBar = { 0.13, 0.15, 0.18, 1 },
    },
    backdrop = { bgFile = Skins.WHITE, edgeFile = Skins.WHITE, edgeSize = 1,
                 insets = { left = 1, right = 1, top = 1, bottom = 1 } },
    buttonBackdrop = { bgFile = Skins.WHITE, edgeFile = Skins.WHITE, edgeSize = 1,
                       insets = { left = 1, right = 1, top = 1, bottom = 1 } },
    arrowTexture = Skins.MEDIA .. "arrow_modern",
    arrowSize = 52,
    ringTexture = Skins.MEDIA .. "ring",
    dotTexture = Skins.MEDIA .. "dot",
    pinTexture = Skins.MEDIA .. "pin",
    buttonTemplate = nil,
    closeButtonTemplate = nil,
    panelAlpha = 0.96,
    factionAccent = true,
    titleHeight = 24,
    inset = 10,
    titleBarStyle = "flat",
    sliderStyle = "flat",
}

Skins.presets.classic = {
    name = "classic",
    label = L["Classic"],
    font = FONT_NORMAL,
    titleFont = FONT_TITLE_CLASSIC,
    fontSize = 12,
    smallFontSize = 10,
    largeFontSize = 18,
    titleFontSize = 15,
    colors = {
        bg = { 1, 1, 1, 1 },                      -- parchment tile is drawn at full colour
        border = { 1, 1, 1, 1 },                  -- Blizzard border texture, untinted
        text = { 0.16, 0.10, 0.04, 1 },
        textDim = { 0.42, 0.32, 0.20, 1 },
        -- Dark brown on parchment (gold titles were ~1.5:1 on the light tile).
        title = { 0.30, 0.18, 0.06, 1 },
        accent = { 0.80, 0.58, 0.12, 1 },
        routeVerified = { 0.20, 0.55, 0.95, 1 },
        routeUnverified = { 0.85, 0.35, 0.10, 1 },
        routeTransport = { 0.55, 0.30, 0.75, 0.95 },
        arrow = { 1, 1, 1, 1 },
        arrowOutline = { 0, 0, 0, 0.85 },
        button = { 0.30, 0.20, 0.10, 0.9 },
        buttonHover = { 0.42, 0.30, 0.15, 0.95 },
        buttonBorder = { 0.55, 0.42, 0.20, 1 },
        selection = { 0.80, 0.58, 0.12, 0.30 },
        highlight = { 0.60, 0.40, 0.10, 0.12 },
        editBox = { 0.96, 0.92, 0.80, 1 },
        titleBar = { 0.26, 0.16, 0.06, 0.95 },
    },
    -- Parchment tile behind the game's default dialog border (supported texture paths).
    backdrop = { bgFile = Skins.MEDIA .. "parchment", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                 tile = true, tileSize = 256, edgeSize = 24,
                 insets = { left = 6, right = 6, top = 6, bottom = 6 } },
    buttonBackdrop = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                       edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
                       insets = { left = 3, right = 3, top = 3, bottom = 3 } },
    arrowTexture = Skins.MEDIA .. "arrow_classic",
    arrowSize = 56,
    ringTexture = Skins.MEDIA .. "ring",
    dotTexture = Skins.MEDIA .. "dot",
    pinTexture = Skins.MEDIA .. "pin",
    buttonTemplate = "UIPanelButtonTemplate",
    closeButtonTemplate = "UIPanelCloseButton",
    panelAlpha = 1.0,
    factionAccent = false,
    titleHeight = 26,
    inset = 12,
    titleBarStyle = "none",
    sliderStyle = "blizzard",
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
        -- The faction accent would put the two factions' red and blue back on top of the route
        -- colours, so it stands down while this scheme is active.
        suppressFactionAccent = true,
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
    if not scheme or type(scheme.colors) ~= "table" then return skin, false end
    for key, color in pairs(scheme.colors) do
        skin.colors[key] = Util.ShallowCopy(color)
    end
    skin.colors.selection = { scheme.colors.accent[1], scheme.colors.accent[2], scheme.colors.accent[3], 0.30 }
    skin.colorScheme = Skins.ColorSchemeName()
    return skin, scheme.suppressFactionAccent == true
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

local function factionAccentEnabled()
    local db = FGPS.DB
    if db and db.settings then
        local value = db.settings.factionAccent
        if value == false then return false end
    end
    return true
end

local function playerFactionColor()
    if type(UnitFactionGroup) ~= "function" then return nil end
    local ok, faction = pcall(UnitFactionGroup, "player")
    if ok and type(faction) == "string" then return Skins.FACTION_COLORS[faction] end
    return nil
end

-- Returns a fresh resolved copy of a preset (faction accent applied); callers may keep it
-- without affecting the preset definition. Unknown names resolve to the default preset.
function Skins.Get(name)
    if not Skins.IsValid(name) then name = Skins.DEFAULT end
    local skin = Util.DeepCopy(Skins.presets[name])
    skin.colorScheme = Skins.DEFAULT_COLOR_SCHEME
    local _, suppressFaction = applyColorScheme(skin)
    if skin.factionAccent and not suppressFaction and factionAccentEnabled() then
        local color = playerFactionColor()
        if color then
            -- Accent tints chrome only. The known-path colour stays semantic so Horde
            -- red never turns the solid line into a danger colour next to orange dashes.
            skin.colors.accent = Util.ShallowCopy(color)
            skin.colors.selection = { color[1], color[2], color[3], 0.30 }
        end
    end
    return skin
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

-- Re-resolves the current skin (for example after the faction accent setting changed) and
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
    elseif key == "factionAccent" or key == "accessibility.colorScheme" or key == "textSize" then
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
