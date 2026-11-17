-- Cabbie/UI/Skins.lua
-- The one look (D8). Cabbie has no skins to choose from any more: "modern" and "classic" went on
-- 2026-10-20 and "minimal" with Task 29. Skins.Current() is one table, built from the game's look
-- as UI/Look.lua gives it (its colour roles, its plain ground and the colours and fonts of the flat
-- widgets, Look.FLAT), with the colour scheme's meaning colours laid over it. It is read by
-- UI/Frames.lua and by the modules that colour a word or a mark by what it means:
--
--   { name = "tome", colorScheme, font, titleFont, fontSize, smallFontSize, largeFontSize, titleFontSize,
--     colors = { bg, border, text, textDim, title, accent, mapAccent, routeVerified,
--                routeUnverified, routeTransport, button, buttonHover, buttonBorder, selection,
--                highlight, editBox, titleBar },
--     backdrop, buttonBackdrop, panelAlpha, titleHeight, inset, titleBarStyle, sliderStyle }
--
-- Skins.Refresh() builds it again and re-skins every frame registered with UI/Frames.lua; it never
-- touches the destination, the routing preferences or a position. settings.preset stays in a save
-- and is read by nothing (Core/DB.lua).
local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local type, pairs, ipairs = type, pairs, ipairs

-------------------------------------------------------------------------------
-- Settings schema contributed by UI modules
-------------------------------------------------------------------------------
-- Core/DB.lua owns the settings schema, but a UI module that introduces a preference of its own
-- would otherwise have to edit that shared file. This helper lets the owning module declare its
-- own defaults at file scope, which runs before ADDON_LOADED and therefore before DB:Init applies
-- them; a reset picks them up through the same table. Nothing overwrites a key that already
-- exists, so Core/DB.lua always wins when a preference later moves into the schema proper.
--   FGPS.UI.AddSettingDefault("compat", { wayCommand = true })
function FGPS.UI.AddSettingDefault(key, value)
    local defaults = FGPS.DB and FGPS.DB.defaults
    local settings = defaults and defaults.settings
    if type(settings) ~= "table" then return false end
    if settings[key] ~= nil then return false end
    settings[key] = value
    return true
end

local Skins = {
    current = nil,          -- the look as last built, until the next Refresh
    initialised = false,
}
FGPS.UI.Skins = Skins

Skins.NAME = "tome"
Skins.WHITE = "Interface\\Buttons\\WHITE8x8"

-- FRIZQT__ has no Cyrillic, Hangul or Han glyphs. The client names the text font of its own locale
-- in STANDARD_TEXT_FONT (FRIZQT__ again on the Latin clients), so the look takes that one when the
-- client names one, read each time the look is built.
local function localeFont(path)
    if type(STANDARD_TEXT_FONT) == "string" and STANDARD_TEXT_FONT ~= "" then return STANDARD_TEXT_FONT end
    return path
end

-------------------------------------------------------------------------------
-- Colour schemes (accessibility)
-------------------------------------------------------------------------------
-- The look has its own colours ("Standard Colours"); a colour scheme replaces the few colours that
-- carry MEANING (verified route, unverified route, transport, accent) with a set that stays
-- distinguishable for the common forms of colour blindness. The values are the blue / vermillion /
-- reddish-purple / sky-blue of the Okabe-Ito qualitative palette, which was designed so that no
-- pair collapses under deuteranopia, protanopia or tritanopia and every pair also differs in
-- lightness, so the lines stay apart in greyscale too. The key of the standard colours stays
-- "preset", as saves hold it.
--
-- Colour is never the only cue in any case: the world map draws unverified stretches dashed, the
-- minimap draws them as larger hollow dots, the arrow shows a ring, the preview says how many
-- yards are estimated and the service list carries a "(straight line)" flag. The scheme is here so
-- that the colours agree with those cues instead of fighting them.
Skins.COLOR_SCHEMES = {
    preset = { label = L["Standard Colours"] },
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

-- Overwrites the meaning-carrying colours of a built look with the active scheme's.
local function applyColorScheme(skin)
    skin.colorScheme = Skins.ColorSchemeName()
    local scheme = Skins.ColorScheme()
    if not scheme or type(scheme.colors) ~= "table" then return skin end
    for key, color in pairs(scheme.colors) do
        skin.colors[key] = Util.ShallowCopy(color)
    end
    skin.colors.selection = { scheme.colors.accent[1], scheme.colors.accent[2], scheme.colors.accent[3], 0.30 }
    skin.colors.mapAccent = Util.ShallowCopy(scheme.colors.accent)
    return skin
end

-------------------------------------------------------------------------------
-- The one look
-------------------------------------------------------------------------------
local function copy(c)
    return { c[1], c[2], c[3], c[4] or 1 }
end

local function role(name, alpha)
    local r, g, b = FGPS.UI.Look.Color(name)
    return { r, g, b, alpha or 1 }
end

local function backdrop()
    return { bgFile = Skins.WHITE, edgeFile = Skins.WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } }
end

-- Builds the look afresh from Look: the game's white, grey and gold for the words, its plain dark
-- ground and gold edge for a window, gilt for the accent, the flat widgets' own shades and fonts
-- (with mapAccent, the map marks' blue), and over them the colour scheme, whose accent is the map
-- marks' accent too. Every call gives a new table.
local function build()
    local Look = FGPS.UI.Look
    local flat = Look.FLAT
    local colors = {
        bg = copy(Look.GROUND_FILL),
        border = copy(Look.GROUND_EDGE),
        text = role("name"),
        textDim = role("grey"),
        title = role("header"),
        accent = role("gilt"),
        selection = role("gilt", flat.selectionAlpha),
    }
    for key, c in pairs(flat.colors) do colors[key] = copy(c) end
    local font = localeFont(flat.font)
    return applyColorScheme({
        name = Skins.NAME,
        font = font,
        titleFont = font,
        fontSize = flat.fontSize,
        smallFontSize = flat.smallFontSize,
        largeFontSize = flat.largeFontSize,
        titleFontSize = flat.titleFontSize,
        colors = colors,
        backdrop = backdrop(),
        buttonBackdrop = backdrop(),
        panelAlpha = 0.9,
        titleHeight = 20,
        inset = 8,
        titleBarStyle = "flat",     -- "flat" draws a tinted strip; "none" relies on the border texture
        sliderStyle = "flat",       -- "flat" thin track and accent thumb; "blizzard" default slider art
    })
end

-- The look in use, built the first time it is asked for.
function Skins.Current()
    if not Skins.current then Skins.current = build() end
    return Skins.current
end

-- Builds the look again (after the colour scheme or the text size changed, or a reset), re-skins
-- every registered frame and tells the UI with UI_PRESET_APPLIED("tome").
function Skins.Refresh()
    Skins.current = build()
    local look = FGPS.UI.Look
    if look and look.RefreshFonts then look.RefreshFonts() end
    local frames = FGPS.UI.Frames
    if frames and frames.ApplyAll then pcall(frames.ApplyAll, Skins.current) end
    -- The event keeps its old name; its payload is always "tome", the one look's name.
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
-- A reset of every setting ("*") may change the colour scheme, or the text size UI/Frames.lua
-- reads on its skin pass.
local function onSettingsChanged(_, key)
    if key == "*" or key == "accessibility.colorScheme" or key == "textSize" then
        Skins.Refresh()
    end
end

function Skins:Init()
    Skins.current = build()
    if not Skins.initialised and FGPS.Events then
        FGPS.Events:Register("SETTINGS_CHANGED", onSettingsChanged, Skins)
        Skins.initialised = true
    end
    return Skins
end
