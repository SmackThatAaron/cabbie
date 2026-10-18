














local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local type, pairs, ipairs, tostring = type, pairs, ipairs, tostring










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
    current = nil,
    currentName = nil,
    applying = false,
    initialised = false,
}
FGPS.UI.Skins = Skins

Skins.MEDIA = "Interface\\AddOns\\Cabbie\\Media\\"
Skins.DEFAULT = "minimal"
Skins.WHITE = "Interface\\Buttons\\WHITE8x8"

local FONT_NORMAL = "Fonts\\FRIZQT__.TTF"
local FONT_TITLE_CLASSIC = "Fonts\\MORPHEUS.TTF"



Skins.FACTION_COLORS = {
    Alliance = { 0.29, 0.53, 0.90, 1 },
    Horde = { 0.85, 0.24, 0.22, 1 },
}




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
    titleBarStyle = "flat",
    sliderStyle = "flat",
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
        bg = { 1, 1, 1, 1 },
        border = { 1, 1, 1, 1 },
        text = { 0.16, 0.10, 0.04, 1 },
        textDim = { 0.42, 0.32, 0.20, 1 },

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















Skins.COLOR_SCHEMES = {
    preset = { label = L["Preset colours"] },
    colorblind = {
        label = L["Colour-blind friendly"],
        colors = {
            routeVerified = { 0.00, 0.45, 0.70, 1 },
            routeUnverified = { 0.84, 0.37, 0.00, 1 },
            routeTransport = { 0.80, 0.47, 0.65, 1 },
            accent = { 0.34, 0.71, 0.91, 1 },
        },


        suppressFactionAccent = true,
    },
}
Skins.COLOR_SCHEME_ORDER = { "preset", "colorblind" }
Skins.DEFAULT_COLOR_SCHEME = "preset"

FGPS.UI.AddSettingDefault("accessibility", { colorScheme = Skins.DEFAULT_COLOR_SCHEME })

function Skins.IsValidColorScheme(name)
    return type(name) == "string" and Skins.COLOR_SCHEMES[name] ~= nil
end


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



function Skins.Get(name)
    if not Skins.IsValid(name) then name = Skins.DEFAULT end
    local skin = Util.DeepCopy(Skins.presets[name])
    skin.colorScheme = Skins.DEFAULT_COLOR_SCHEME
    local _, suppressFaction = applyColorScheme(skin)
    if skin.factionAccent and not suppressFaction and factionAccentEnabled() then
        local color = playerFactionColor()
        if color then


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


function Skins.CurrentName()
    if Skins.currentName then return Skins.currentName end
    local db = FGPS.DB
    local name = db and db.settings and db.settings.preset
    if Skins.IsValid(name) then return name end
    return Skins.DEFAULT
end







function Skins.Apply(name, opts)
    if not Skins.IsValid(name) then
        if FGPS.Log then FGPS.Log:Warn("Unknown UI preset '%s'; using '%s'", tostring(name), Skins.DEFAULT) end
        name = Skins.DEFAULT
    end
    if Skins.applying then return Skins.current end
    Skins.applying = true

    local db = FGPS.DB
    if db and db.settings and db.settings.preset ~= name and db.Set then

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



function Skins.Refresh()
    Skins.current = Skins.Get(Skins.CurrentName())
    local frames = FGPS.UI.Frames
    if frames and frames.ApplyAll then pcall(frames.ApplyAll, Skins.current) end
    if FGPS.Events then FGPS.Events:Fire("UI_PRESET_APPLIED", Skins.current.name) end
    return Skins.current
end





function Skins.RGBA(color, alphaOverride)
    if type(color) ~= "table" then return 1, 1, 1, alphaOverride or 1 end
    return color[1] or 1, color[2] or 1, color[3] or 1, alphaOverride or color[4] or 1
end


function Skins.Hex(color)
    local r, g, b = Skins.RGBA(color)
    return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end




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
