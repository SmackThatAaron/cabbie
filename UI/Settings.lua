-- Cabbie/UI/Settings.lua
-- Blizzard Settings integration and the slash command set. A "Cabbie" category with the
-- subcategories General, Guidance, Transport, Voice and Advanced is registered through the
-- Settings API present in the Forever client (RegisterVerticalLayoutCategory /
-- RegisterVerticalLayoutSubcategory / RegisterAddOnCategory / RegisterProxySetting /
-- CreateCheckbox / CreateSlider / CreateDropdown / OpenToCategory). Every control is a proxy
-- setting bound to FGPS.DB:Get / FGPS.DB:Set, so changes flow through SETTINGS_CHANGED like any
-- other write. Buttons use CreateSettingsButtonInitializer when the client provides it, else a
-- canvas subcategory with plain buttons; when neither exists the same actions stay reachable as
-- slash commands. "/cabbie options" opens the category. General also carries a read-only "About"
-- block (addon version, data version, client build, Edit Mode integration) built from the
-- section-header and button initializers; "/cabbie about" prints the same lines.
--
-- Slash words: this module loads and initialises last (Core/Boot.lua order), so every word it
-- registers goes through registerIfFree and never replaces a handler an earlier module claimed
-- (perf and log from Core, version/help from Init, learn, voice, stops, preview, fav, recent,
-- layout, search from their own modules). "/cabbie help" is Core/Init.lua's registry dump; nothing
-- here keeps a separate command list.
local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local type, ipairs, pairs, tostring, tonumber, format = type, ipairs, pairs, tostring, tonumber, string.format
local floor = math.floor

local UISettings = {
    category = nil,
    subcategories = {},
    proxies = {},          -- path -> setting object
    registered = false,
}
FGPS.UI.Settings = UISettings

local CATEGORY_NAME = "Cabbie"
local VARIABLE_PREFIX = "FGPS_"

-------------------------------------------------------------------------------
-- Option tables
-------------------------------------------------------------------------------
local PRESETS = { { "minimal", "Minimal" }, { "modern", "Modern" }, { "classic", "Classic" } }
local TEXT_SIZES = {
    { value = "normal", label = L["Normal"] },
    { value = "large", label = L["Large"] },
}

local UNITS = { { "yards", "Yards" }, { "metric", "Metric" } }
-- Shift with the left button always goes to a spot on the world map (WorldMap.IsGoClick), so
-- "NONE" switches off this extra click and nothing else, and its label and tooltip say so.
local MODIFIERS = { { "CTRL_RIGHT", "Ctrl + Right-click" }, { "ALT_LEFT", "Alt + Left-click" },
                    { "SHIFT_RIGHT", "Shift + Right-click" },
                    { "NONE", "No extra click", "Switches off the extra click only. Shift + Left-click still goes to the spot." } }
local PLACEMENTS = { { "near_character", "Near character" }, { "below_minimap", "Below minimap" },
                     { "top_center", "Top centre" }, { "custom", "Custom (Edit Mode)" } }
local COMBAT_MODES = { { "all", "Keep everything (visuals and voice)" }, { "visuals_only", "Visuals only, no voice" },
                       { "hide_all", "Hide all guidance" } }
local VERBOSITY = { { "minimal", "Minimal" }, { "normal", "Normal" }, { "detailed", "Detailed" } }
local ASSUME_MOUNT = { { "auto", "Detect automatically" }, { "none", "Never mounted" },
                       { "60", "60% mount" }, { "100", "100% mount" } }
-- Kept in step with UI/Skins.lua COLOR_SCHEME_ORDER (a test pins that they agree).
local COLOR_SCHEMES = { { "preset", "Preset colours" }, { "colorblind", "Colour-blind friendly" } }
UISettings.COLOR_SCHEMES = COLOR_SCHEMES

-- Windows and elements whose positions can be reset individually ("Reset this element").
-- Windows are stored by UI/Frames under "window:<key>"; the arrow and panel use their Edit Mode keys.
local ELEMENT_KEYS = {
    { "arrow", "Reset arrow position" },
    { "panel", "Reset instruction panel position" },
    { "window:search", "Reset search window position" },
    { "window:preview", "Reset preview window position" },
    { "window:favorites", "Reset favorites window position" },
    { "window:itinerary", "Reset itinerary window position" },
    { "window:quests", "Reset quest window position" },
}
local ELEMENT_ALIASES = { search = "window:search", preview = "window:preview", favorites = "window:favorites",
                          itinerary = "window:itinerary", quests = "window:quests" }

-------------------------------------------------------------------------------
-- Proxy helpers
-------------------------------------------------------------------------------
local function variableName(path)
    return VARIABLE_PREFIX .. path:gsub("%.", "_")
end

local function varType(kind)
    if Settings and Settings.VarType then
        if kind == "boolean" then return Settings.VarType.Boolean end
        if kind == "number" then return Settings.VarType.Number end
        return Settings.VarType.String
    end
    return kind
end

-- Registers a proxy setting bound to a dotted settings path. opts: { get = fn, set = fn(value),
-- default = value } override the DB accessors (used for the voice dropdown).
local function proxy(category, path, kind, name, opts)
    opts = opts or {}
    local DB = FGPS.DB
    local default = opts.default
    if default == nil then default = DB:GetDefault(path) end
    if default == nil then
        if kind == "boolean" then default = false elseif kind == "number" then default = 0 else default = "" end
    end
    local get = opts.get or function()
        local value = DB:Get(path)
        if value == nil then return default end
        if kind == "number" and type(value) ~= "number" then return tonumber(value) or default end
        return value
    end
    local set = opts.set or function(value)
        if kind == "number" then value = tonumber(value) or default end
        if kind == "boolean" then value = value and true or false end
        DB:Set(path, value)
    end
    local setting = Settings.RegisterProxySetting(category, variableName(path), varType(kind), name, default, get, set)
    UISettings.proxies[path] = setting
    return setting
end

local function checkbox(category, path, name, tooltip)
    local setting = proxy(category, path, "boolean", L[name])
    return Settings.CreateCheckbox(category, setting, L[tooltip or name])
end

-- proxyOpts (optional) is handed to proxy(); used for a default the settings schema does not carry.
local function slider(category, path, name, tooltip, minValue, maxValue, step, formatter, proxyOpts)
    local setting = proxy(category, path, "number", L[name], proxyOpts)
    local options = Settings.CreateSliderOptions(minValue, maxValue, step)
    if options.SetLabelFormatter and MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatter or function(value) return tostring(value) end)
    end
    return Settings.CreateSlider(category, setting, options, L[tooltip or name])
end

local function optionsFunction(entries)
    return function()
        local container = Settings.CreateControlTextContainer()
        for _, entry in ipairs(entries) do container:Add(entry[1], L[entry[2]], entry[3] and L[entry[3]] or nil) end
        return container:GetData()
    end
end

local function dropdown(category, path, name, tooltip, entries, kind)
    local setting = proxy(category, path, kind or "string", L[name])
    return Settings.CreateDropdown(category, setting, optionsFunction(entries), L[tooltip or name])
end

local function voiceOptions()
    local container = Settings.CreateControlTextContainer()
    local Voice = FGPS.UI.Voice
    local voices = Voice and Voice.RefreshVoices and Voice:RefreshVoices() or {}
    if #voices == 0 then
        container:Add(0, L["No text-to-speech voices installed"])
    end
    for _, v in ipairs(voices) do container:Add(v.voiceID, tostring(v.name)) end
    return container:GetData()
end

-------------------------------------------------------------------------------
-- Buttons
-------------------------------------------------------------------------------
local function addButton(category, name, buttonText, onClick, tooltip)
    if CreateSettingsButtonInitializer and Settings.RegisterInitializer then
        local initializer = CreateSettingsButtonInitializer(L[name], L[buttonText], onClick, L[tooltip or name], true)
        Settings.RegisterInitializer(category, initializer)
        return true
    end
    if Settings.CreateElementInitializer and Settings.RegisterInitializer then
        local data = { name = L[name], buttonText = L[buttonText], buttonClick = onClick, tooltip = L[tooltip or name] }
        local initializer = Settings.CreateElementInitializer("SettingButtonControlTemplate", data)
        if initializer and initializer.AddSearchTags then initializer:AddSearchTags(L[name]) end
        Settings.RegisterInitializer(category, initializer)
        return true
    end
    return false
end

-- Text-only section header row ("About"). Uses Blizzard's own initializer when present, else the
-- same template through CreateElementInitializer; returns false when neither exists.
local function addHeader(category, text, tooltip)
    if not Settings.RegisterInitializer then return false end
    local initializer
    if CreateSettingsListSectionHeaderInitializer then
        initializer = CreateSettingsListSectionHeaderInitializer(text, tooltip)
    elseif Settings.CreateElementInitializer then
        initializer = Settings.CreateElementInitializer("SettingsListSectionHeaderTemplate", { name = text, tooltip = tooltip })
    end
    if not initializer then return false end
    Settings.RegisterInitializer(category, initializer)
    return true
end

-- Fallback when button initializers do not exist: a canvas subcategory holding plain buttons.
local function canvasButtons(parentCategory, specs)
    if not Settings.RegisterCanvasLayoutSubcategory then return false end
    local frame = CreateFrame("Frame")
    frame:SetSize(600, 400)
    local previous
    for _, spec in ipairs(specs) do
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetSize(260, 22)
        button:SetText(L[spec.name])
        button:SetScript("OnClick", spec.onClick)
        if previous then button:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -6) else button:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16) end
        previous = button
    end
    local ok, category = pcall(Settings.RegisterCanvasLayoutSubcategory, parentCategory, frame, L["Actions"])
    if ok and category then
        UISettings.subcategories.actions = category
        return true
    end
    return false
end

-------------------------------------------------------------------------------
-- Actions shared by buttons and slash commands
-------------------------------------------------------------------------------
local Actions = {}
UISettings.Actions = Actions

function Actions.ResetElement(key)
    local DB = FGPS.DB
    key = ELEMENT_ALIASES[key] or key
    if DB and DB.ResetElementPosition then DB:ResetElementPosition(key) end
    FGPS:Print(L["Position of '%s' restored to its default."], key)
end

function Actions.ResetPositions()
    local DB = FGPS.DB
    if DB and DB.ResetPositions then DB:ResetPositions() end
    FGPS:Print(L.POSITIONS_RESET_DONE)
end

function Actions.ResetSettings()
    local DB = FGPS.DB
    if DB and DB.ResetSettings then DB:ResetSettings() end
    FGPS:Print(L.SETTINGS_RESET_DONE)
end

function Actions.ResetAll()
    local DB = FGPS.DB
    if DB and DB.ResetAll then DB:ResetAll() end
    FGPS:Print(L["Settings and frame positions restored to defaults; routing preferences, favorites and recents were kept."])
end

-- The only reset that touches the routing and transport preferences (DB:ResetRouting). Every other
-- reset keeps them, because losing a transport choice silently changes the routes people get.
function Actions.ResetRouting()
    local DB = FGPS.DB
    if DB and DB.ResetRouting then
        DB:ResetRouting()
        FGPS:Print(L["Routing and transport preferences restored to defaults."])
    else
        FGPS:Print(L["Routing preferences cannot be reset in this session (the settings store did not load)."])
    end
end

function Actions.ClearRecents()
    local Destinations = FGPS.Destinations
    if Destinations and Destinations.ClearRecents then
        Destinations.ClearRecents()
        FGPS:Print(L["Recent destinations cleared."])
    else
        FGPS:Print(L["Recent destinations are not available right now."])
    end
end

function Actions.PerfReport()
    local Perf = FGPS.Perf
    if Perf then
        if Perf.Sample then Perf:Sample() end
        Perf:Print()
    end
end

-- The facts shown in the About block: { { label, value }, ... }. Pure; every source is guarded so
-- the block renders even when a module or API is missing.
function UISettings.AboutLines()
    local build = FGPS.build or {}
    local manifest = FGPS.Data and FGPS.Data.manifest
    local dataVersion = manifest and manifest.dataVersion
    if dataVersion ~= nil then dataVersion = tostring(dataVersion) else dataVersion = L["unknown (no data manifest loaded)"] end
    local client
    if build.version then
        client = format("%s (%s %s, %s %s)", tostring(build.version), L["build"], tostring(build.buildNumber or "?"),
            L["interface"], tostring(build.interface or "?"))
    else
        client = L["unknown (GetBuildInfo unavailable)"]
    end
    local EditMode = FGPS.UI.EditMode
    local editMode
    if EditMode and EditMode.IsAvailable then
        if EditMode.IsAvailable() then
            if EditMode.IsNativeIntegration and not EditMode.IsNativeIntegration() then
                editMode = L["available, fallback layout editor active"]
            else
                editMode = L["native integration available"]
            end
        else
            editMode = L["not available (fallback layout editor via /cabbie layout)"]
        end
    else
        editMode = L["unknown (Edit Mode is not ready)"]
    end
    return {
        { L["Version"], tostring(FGPS.version) },
        { L["Data version"], dataVersion },
        { L["Client build"], client },
        { L["Edit Mode"], editMode },
    }
end

function Actions.About()
    FGPS:Print(L["%s %s"], L.ADDON_TITLE, tostring(FGPS.version))
    for _, line in ipairs(UISettings.AboutLines()) do
        FGPS:Print("  %s: %s", line[1], line[2])
    end
end

-------------------------------------------------------------------------------
-- Category registration
-------------------------------------------------------------------------------
-- About block: a header carrying the addon and data versions plus one button row whose label
-- names the client build and Edit Mode state; the button (and its tooltip) gives every line.
local function registerAbout(category)
    local lines = UISettings.AboutLines()
    local tooltipParts = {}
    for _, line in ipairs(lines) do tooltipParts[#tooltipParts + 1] = line[1] .. ": " .. line[2] end
    local tooltip = table.concat(tooltipParts, "\n")
    local header = format(L["About %s %s (data %s)"], L.ADDON_TITLE, tostring(FGPS.version), lines[2][2])
    local added = addHeader(category, header, tooltip)
    local build = FGPS.build or {}
    local rowName = format(L["Client %s (%s), Edit Mode: %s"], tostring(build.version or "?"), tostring(build.buildNumber or "?"), lines[4][2])
    if addButton(category, rowName, "Details", Actions.About, tooltip) then added = true end
    if not added then FGPS.Log:Debug("Settings about block unavailable in this client; use /cabbie about") end
    return added
end

local function registerGeneral(category)
    checkbox(category, "worldMapLegend", "Show the map legend",
        "The box in the corner of the world map that names the solid, dashed and coloured lines. Turn it off here, or with /cabbie legend.")
    dropdown(category, "preset", "Interface preset", "Visual preset for the arrow, panel and windows.", PRESETS)
    checkbox(category, "factionAccent", "Faction-coloured accents", "Presets that support it tint their accent colour and verified route line with your faction's colour.")
    dropdown(category, "units", "Distance units", "Yards or metres and kilometres.", UNITS)
    dropdown(category, "textSize", "Text size", "Normal or Large. Large adds two points to window list and label fonts.", TEXT_SIZES)
    dropdown(category, "accessibility.colorScheme", "Colour scheme",
        "Colour-blind friendly replaces the route, transport and accent colours with a set that stays distinguishable for the common forms of colour blindness. The distinction between verified ground and an unverified path never depends on colour alone in either scheme: the map draws unverified stretches dashed and the minimap draws them as larger hollow dots.",
        COLOR_SCHEMES)
    dropdown(category, "mapClickModifier", "Extra world map click",
        "An extra click that sets a destination on the world map. Choose its modifier and mouse button, or switch it off. Shift + Left-click always goes to the spot at once.",
        MODIFIERS)
    checkbox(category, "compat.wayCommand", "Answer the /way command",
        "Lets Cabbie take waypoint coordinates written the way guides and web sites write them. The word is only claimed when no other add-on already owns it; /cabbie way always works.")
    registerAbout(category)
end

local function registerGuidance(category)
    addHeader(category, L["Arrow"])
    checkbox(category, "arrow.enabled", "Show the guidance arrow")
    dropdown(category, "arrow.placement", "Arrow placement", "Where the arrow sits; Custom keeps the position set in Edit Mode.", PLACEMENTS)
    slider(category, "arrow.scale", "Arrow scale", nil, 0.5, 2.0, 0.05, function(value) return format("%.2f", value) end)
    -- Opacity only; paused journeys already dim the arrow. Combat does not change it further.
    slider(category, "arrow.alpha", "Arrow opacity", "How solid the arrow is drawn.",
        0.2, 1.0, 0.05, function(value) return format("%.2f", value) end)
    checkbox(category, "arrow.showDistance", "Arrow shows distance")
    checkbox(category, "arrow.showEta", "Arrow shows travel time left",
        "Adds the time left on the route under the distance. Off by default.")
    checkbox(category, "arrow.showNextStep", "Arrow shows the next instruction")
    addHeader(category, L["Step list"])
    checkbox(category, "panel.enabled", "Show the instruction panel")
    slider(category, "panel.scale", "Instruction panel scale", nil, 0.5, 2.0, 0.05, function(value) return format("%.2f", value) end)
    slider(category, "panel.maxSteps", "Instruction panel lines", "How many steps the panel lists, counting the current one.", 1, 5, 1,
        function(value) return format("%d", value) end)
    dropdown(category, "combatMode", "In combat", "What guidance keeps doing while you are in combat.", COMBAT_MODES)
end

-- Map drawing and place icons live here so Guidance stays about the arrow and step list (U14).
local function registerMap(category)
    checkbox(category, "worldMapLine", "Draw the route on the world map")
    checkbox(category, "openWithMap", "Open Cabbie when the world map opens",
        "The destination search appears beside the world map each time you open it, and closes with it. It never takes the keyboard.")
    checkbox(category, "minimapLine", "Draw route hints on the minimap")
    checkbox(category, "minimapButton", "Show the minimap button",
        "A compass button on the minimap opens search without typing /cabbie.")
    checkbox(category, "inWorldPin", "Show the in-world waypoint marker", "Uses the game's own waypoint marker for the next point of the route.")
    addHeader(category, L["Place icons"])
    -- One checkbox per category of clickable place icons. UI/MapPlaces.lua owns the list (and the
    -- defaults made from it), so a category added there gets its switch here without an edit.
    local MapPlaces = FGPS.UI.MapPlaces
    for _, row in ipairs(MapPlaces and MapPlaces.CATEGORIES or {}) do
        checkbox(category, "mapPlaces." .. row.key, row.label, row.tooltip)
    end
end

local function registerTransport(category)
    checkbox(category, "transports.taxi", "Use flight paths")
    checkbox(category, "transports.boat", "Use boats")
    checkbox(category, "transports.zeppelin", "Use zeppelins")
    checkbox(category, "transports.tram", "Use the Deeprun Tram")
    checkbox(category, "transports.hearth", "Consider the Hearthstone")
    checkbox(category, "transports.spells", "Consider teleport spells")
    checkbox(category, "routing.preferRoads", "Prefer roads and known paths",
        "Routes stick to roads and known paths unless the way round is much longer. Open ground, wandering creature paths and guessed stretches cost more. Off: the fastest line, often straight across open ground.")
    checkbox(category, "routing.roadShortcuts", "Allow shortcuts off the road",
        "Off (the default): routes keep to the road wherever one goes, and leave it only to reach a place off the road. On: a route may cut across open ground when that is clearly quicker. Needs \"Prefer roads and known paths\".")
    checkbox(category, "routing.allowUnverified", "Allow straight-line legs", "Without a known path the guide may draw straight legs; turning this off limits routes to known paths.")
    checkbox(category, "routing.avoidDanger", "Avoid high-level areas", "Adds cost to cells whose hostile creatures are above your level.")
end

local function registerVoice(category)
    checkbox(category, "voice.enabled", "Voice guidance", "Speak turn instructions out loud.")
    checkbox(category, "voice.systemVoice", "Use the game's text-to-speech voice", "Off (the default): Cabbie's own recorded voice, the same on every computer. On: the voice chosen in the game's text-to-speech settings, which also says place names. Without a voice there, the recorded one speaks.")
    local Voice = FGPS.UI.Voice
    local defaultVoice = Voice and Voice.GetVoiceID and Voice:GetVoiceID() or 0
    local setting = proxy(category, "voice.voiceID", "number", L["Voice"], {
        default = defaultVoice,
        get = function()
            local vs = FGPS.DB:Get("voice")
            local id = vs and tonumber(vs.voiceID)
            if id == nil then
                if Voice and Voice.GetVoiceID then return Voice:GetVoiceID() end
                return defaultVoice
            end
            return id
        end,
        set = function(value) FGPS.DB:Set("voice.voiceID", tonumber(value)) end,
    })
    Settings.CreateDropdown(category, setting, voiceOptions, L["Voice used for spoken guidance."])
    slider(category, "voice.rate", "Speech rate", nil, -10, 10, 1, function(value) return format("%d", value) end)
    slider(category, "voice.volume", "Speech volume", nil, 0, 100, 5, function(value) return format("%d", value) end)
    dropdown(category, "voice.verbosity", "Verbosity", "Minimal: turns only. Normal: advance notices and turns. Detailed: every step and zone change.", VERBOSITY)

    -- Audio cues share this page because they are the alternative to speech for the same events.
    checkbox(category, "cues.enabled", "Audio cues instead of speech",
        "Short sounds the game already ships, played before a turn, for a transport action and on arrival. They work with voice guidance on or off.")
    slider(category, "cues.volume", "Cue volume", "Zero is silence. Clients without a per-sound volume play cues at the game's own sound effect volume.",
        0, 100, 5, function(value) return format("%d", value) end)
    checkbox(category, "cues.turn", "Cue before a turn")
    checkbox(category, "cues.transport", "Cue for a transport action", "Boarding a boat or zeppelin, taking a flight, getting off again.")
    checkbox(category, "cues.arrival", "Cue on arrival")
end

-- Quests. Every control here decides what Cabbie draws; none of them decides what is true.
-- The quest pins are for the quests the player has accepted or searched for; the pick-up marks
-- (UI/QuestMarks.lua) for the quests this character can take now, as far as the records say.
local function registerQuests(category)
    checkbox(category, "quests.enabled", "Quest help",
        "The quest panel, quest pins and quest search. Turning this off leaves the bundled quest data loaded but unused.")
    checkbox(category, "quests.mapPins", "Quest pins on the world map",
        "Pins for the quests you have accepted and for a quest you searched for and selected. Never for quests you have not taken.")
    checkbox(category, "quests.minimapPins", "Quest pins on the minimap")
    checkbox(category, "quests.pickupMarks", "Show quests I can pick up",
        "A yellow ! on the world map and the minimap where you can take a quest now, as far as the records say. Hover one to see where its place comes from; Shift-click it on the world map to go there.")
    checkbox(category, "quests.objectiveAreas", "Draw objective areas",
        "A kill or collect objective is an area, not a point. Cabbie draws the measured area and labels it with its width, rather than putting a pin in the middle of it.")
    checkbox(category, "quests.followProgress", "Follow my quests",
        "A quest route moves on to the next objective and the hand-in, and a click on the round marker beside a quest in the quest list or on the map starts the way to it.")
    checkbox(category, "quests.searchForever", "Include Forever's own quests in search",
        "Quests that exist only in Forever. Cabbie knows a name and sometimes where they start, never a turn-in or an objective, and says so.")
    checkbox(category, "quests.serverLookup", "Offer to look quest names up on the server",
        "Cabbie bundles no vanilla quest names; the client answers for them in Forever's own wording. This allows the button that spends part of a small per-session lookup budget to fill in the names of a search result.")
end

local function registerAdvanced(category)
    addHeader(category, L["Routing"])
    slider(category, "routing.arrivalRadius", "Arrival radius (yards)", "Distance from the destination at which you count as arrived.", 5, 60, 1,
        function(value) return format("%d", value) end)
    slider(category, "routing.offRouteYards", "Off-route distance (yards)", "How far from the route you can stray before it is recalculated.", 15, 150, 5,
        function(value) return format("%d", value) end)
    -- The settings schema has no entry for this one (Nav/Router.lua reads it with its own
    -- fallback), so the default comes from the router.
    local Router = FGPS.Router
    slider(category, "routing.maxStraightYards", "Longest straight-line stretch (yards)",
        "Longest stretch without verified ground data the router may put inside a route. 0 turns these stretches off; the last-resort straight-line guidance is not affected.",
        0, 5000, 100, function(value) if value == 0 then return L["Off"] end return format("%d", value) end,
        { default = Router and Router.DEFAULT_MAX_STRAIGHT_YARDS or 3000 })
    slider(category, "routing.dangerMargin", "Danger margin (levels)", "Levels above yours before an area counts as dangerous.", 0, 10, 1,
        function(value) return format("%d", value) end)
    dropdown(category, "routing.assumeMount", "Assume mount speed", "Speed used for estimates when mount detection is uncertain.", ASSUME_MOUNT)
    slider(category, "routing.recalcMinSeconds", "Shortest time between recalculations (seconds)",
        "After you leave the route a new one is requested at most this often.", 2, 30, 1,
        function(value) return format("%d", value) end)
    addHeader(category, L["Developer"])
    checkbox(category, "perf.instrument", "Performance instrumentation", "Cheap timers behind /cabbie perf.")
    slider(category, "perf.frameBudgetMs", "Route computation budget (ms per frame)", "Time slice per frame for route calculation.", 1, 8, 1,
        function(value) return format("%d", value) end)
    checkbox(category, "debug", "Debug output", "Prints diagnostics to chat and forwards errors to the error handler.")

    local buttonSpecs = {}
    for _, entry in ipairs(ELEMENT_KEYS) do
        local key = entry[1]
        buttonSpecs[#buttonSpecs + 1] = { name = entry[2], button = "Reset", onClick = function() Actions.ResetElement(key) end }
    end
    buttonSpecs[#buttonSpecs + 1] = { name = "Reset all UI positions", button = "Reset", onClick = Actions.ResetPositions }
    buttonSpecs[#buttonSpecs + 1] = { name = "Reset settings", button = "Reset", onClick = Actions.ResetSettings }
    buttonSpecs[#buttonSpecs + 1] = { name = "Clear recent destinations", button = "Clear", onClick = Actions.ClearRecents }
    buttonSpecs[#buttonSpecs + 1] = { name = "Performance report", button = "Open", onClick = Actions.PerfReport }
    local added = 0
    for _, spec in ipairs(buttonSpecs) do
        if addButton(category, spec.name, spec.button, spec.onClick, spec.name) then added = added + 1 end
    end
    if added == 0 then
        if not canvasButtons(category, buttonSpecs) then
            FGPS.Log:Warn("Settings buttons unavailable in this client; use /cabbie reset and /cabbie perf instead")
        end
    end
end

function UISettings:Register()
    if self.registered then return true end
    if self.failed then return false end
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting
            and Settings.CreateCheckbox and Settings.CreateSlider and Settings.CreateDropdown) then
        FGPS.Log:Warn("Blizzard Settings API not available; the options panel is disabled (slash commands still work)")
        return false
    end
    local ok, err = pcall(function()
        local category = Settings.RegisterVerticalLayoutCategory(L[CATEGORY_NAME])
        self.category = category
        local general = Settings.RegisterVerticalLayoutSubcategory(category, L["General"])
        local guidance = Settings.RegisterVerticalLayoutSubcategory(category, L["Guidance"])
        local map = Settings.RegisterVerticalLayoutSubcategory(category, L["Map"])
        local transport = Settings.RegisterVerticalLayoutSubcategory(category, L["Transport"])
        local quests = Settings.RegisterVerticalLayoutSubcategory(category, L["Quests"])
        local voice = Settings.RegisterVerticalLayoutSubcategory(category, L["Voice"])
        local advanced = Settings.RegisterVerticalLayoutSubcategory(category, L["Advanced"])
        self.subcategories = { general = general, guidance = guidance, map = map, transport = transport,
                               quests = quests, voice = voice, advanced = advanced }
        registerGeneral(general)
        registerGuidance(guidance)
        registerMap(map)
        registerTransport(transport)
        registerQuests(quests)
        registerVoice(voice)
        registerAdvanced(advanced)
        if Settings.RegisterAddOnCategory then Settings.RegisterAddOnCategory(category) end
    end)
    if not ok then
        self.failed = true
        FGPS.Log:Error("Settings registration failed: %s", tostring(err))
        return false
    end
    self.registered = true
    return true
end

function UISettings:Open(subcategory)
    if not self.registered and not self:Register() then
        FGPS:Print(L["The options panel is not available in this client; use /cabbie help for the command list."])
        return false
    end
    -- Open General, not the empty parent category: the parent paints a shell until a page is
    -- chosen, and the first paint must already show the General rows.
    local target = subcategory and self.subcategories[subcategory]
        or self.subcategories.general
        or self.category
    if not target or not Settings.OpenToCategory then return false end
    local id = target.GetID and target:GetID() or target
    local ok, err = pcall(Settings.OpenToCategory, id)
    if not ok then FGPS.Log:Error("OpenToCategory failed: %s", tostring(err)) end
    return ok
end

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------
local function navigator()
    local Navigator = FGPS.Navigator
    if not Navigator then FGPS:Print(L["Navigation is not available right now."]) end
    return Navigator
end

-- True when the stops that are set lead somewhere else than the route the navigator holds: the
-- route's last stop and the last stop set are both known and are not the same place. The stops
-- can be replaced while a route is paused and the way to the new place not yet found ("Show
-- route" in the search window sets the place and asks for a preview): the route held is then one
-- to a place asked for before. Asked of the navigator's stops and route alone, not of any window.
-- Where one of the two is not known nothing says that the route was replaced.
local function stopsLeadElsewhere(Navigator)
    local route = Navigator.GetRoute and Navigator:GetRoute() or nil
    local stops = Navigator.GetStops and Navigator:GetStops() or nil
    local last = type(stops) == "table" and stops[#stops] or nil
    local ends = type(route) == "table" and type(route.stops) == "table" and route.stops[#route.stops] or nil
    local dest = type(ends) == "table" and ends.dest or nil
    local Destinations = FGPS.Destinations
    if not (last and dest and Destinations and Destinations.Equal) then return false end
    return not Destinations.Equal(last, dest)
end

-- "/cabbie start". The preview window is asked first whenever it keeps a route (Preview:Start).
-- Without one, a paused route is resumed, but only while it leads to the last stop set: one to a
-- place that was replaced since is never gone on with. The way to the stops as they are is asked
-- for then, as when nothing is paused, and a preview window that stands on "Calculating" for that
-- place closes as it does when its own Start is pressed (it opens again if no way is found).
-- During a ride no route is asked for from mid-air. A re-route that waits for the ride to end
-- takes the stops up by itself, so nothing more is asked for then (Go.WaitOutTheRide, called
-- first). Without one the navigator is asked as always and keeps the start for the end of the
-- ride itself (Navigator:Start); Go.WaitOutTheRide, called again, then makes a paused route go on
-- and tells the player. So the rule above holds during a ride too: a paused route to a place that
-- was replaced is not gone on with, the way to the stops is found where the ride ends.
local function slashStart()
    local Navigator = navigator()
    if not Navigator then return end
    local Preview, Go = FGPS.UI.Preview, FGPS.UI.Go
    local waitOut = Go and Go.WaitOutTheRide
    if waitOut and waitOut() then return end
    if Preview and Preview.route and Preview.Start then Preview:Start() return end
    local state = Navigator.GetState and Navigator:GetState()
    if state == "paused" and Navigator.Resume then
        if not stopsLeadElsewhere(Navigator) then Navigator:Resume() return end
        if Preview and Preview.Hide then Preview:Hide() end
    end
    if Navigator.Start then Navigator:Start() end
    if waitOut then waitOut() end
end

local function slashCancel()
    local Navigator = navigator()
    if Navigator and Navigator.Cancel then Navigator:Cancel("user") end
end

local function slashPause()
    local Navigator = navigator()
    if Navigator and Navigator.Pause then Navigator:Pause() end
end

local function slashResume()
    local Navigator = navigator()
    if Navigator and Navigator.Resume then Navigator:Resume() end
end

local function slashPreset(args)
    local Skins = FGPS.UI.Skins
    local name = Util.Lower(Util.Trim(args))
    if name == "" then
        local current = Skins and Skins.Current and Skins.Current()
        FGPS:Print(L["Current preset: %s (available: minimal, modern, classic)"], tostring(current and current.name or FGPS.DB:Get("preset")))
        return
    end
    local valid = false
    for _, entry in ipairs(PRESETS) do if entry[1] == name then valid = true end end
    if not valid then
        FGPS:Print(L["Unknown preset '%s'. Available: minimal, modern, classic"], name)
        return
    end
    if Skins and Skins.Apply then
        Skins.Apply(name)
    else
        FGPS.DB:Set("preset", name)
    end
    FGPS:Print(L["Preset '%s' applied."], name)
end

local function slashArrow(args)
    local DB = FGPS.DB
    local word, rest = Util.Trim(args):match("^(%S*)%s*(.-)$")
    word = Util.Lower(word or "")
    if word == "on" or word == "off" then
        DB:Set("arrow.enabled", word == "on")
        FGPS:Print(word == "on" and L["Arrow enabled."] or L["Arrow disabled."])
    elseif word == "scale" then
        local n = tonumber(rest)
        if not n then FGPS:Print(L["Usage: /cabbie arrow scale <0.5..2>"]) return end
        DB:Set("arrow.scale", Util.Clamp(n, 0.5, 2))
        FGPS:Print(L["Arrow scale set to %.2f."], DB:Get("arrow.scale"))
    elseif word ~= "" then
        local valid = false
        for _, entry in ipairs(PLACEMENTS) do if entry[1] == word then valid = true end end
        if not valid then
            FGPS:Print(L["Usage: /cabbie arrow on|off|scale <n>|near_character|below_minimap|top_center|custom"])
            return
        end
        DB:Set("arrow.placement", word)
        FGPS:Print(L["Arrow placement set to %s."], word)
    else
        FGPS:Print(L["Arrow: %s, placement %s, scale %.2f"], DB:Get("arrow.enabled") and L["on"] or L["off"],
            tostring(DB:Get("arrow.placement")), DB:Get("arrow.scale") or 1)
    end
end

local function slashLegend(args)
    local DB = FGPS.DB
    local word = Util.Lower(Util.Trim(args))
    local on
    if word == "on" then
        on = true
    elseif word == "off" then
        on = false
    elseif word == "" then
        local current = DB:Get("worldMapLegend")
        if current == nil then current = true end
        on = not current
    else
        FGPS:Print(L["Usage: /cabbie legend on|off"])
        return
    end
    DB:Set("worldMapLegend", on)
    FGPS:Print(on and L["Map legend on."] or L["Map legend off."])
end

local function slashDebug(args)
    local DB = FGPS.DB
    local word = Util.Lower(Util.Trim(args))
    local enabled
    if word == "on" then enabled = true elseif word == "off" then enabled = false else enabled = not DB:Get("debug") end
    DB:Set("debug", enabled)
    FGPS:Print(enabled and L["Debug output enabled."] or L["Debug output disabled."])
end

local function slashReset(args)
    local word = Util.Lower(Util.Trim(args))
    if word == "settings" then
        Actions.ResetSettings()
    elseif word == "positions" or word == "ui" then
        Actions.ResetPositions()
    elseif word == "all" then
        Actions.ResetAll()
    elseif word == "routing" then
        Actions.ResetRouting()
    elseif word ~= "" then
        Actions.ResetElement(word)
    else
        FGPS:Print(L["Usage: /cabbie reset settings|positions|routing|all|<element> (arrow, panel, search, preview, favorites, itinerary)"])
    end
end

local function slashSearchFallback(args)
    local Search = FGPS.UI.Search
    local query = Util.Trim(args)
    if Search and Search.Show then Search:Show({ query = query ~= "" and query or nil }) end
end

-- Registers a command only when no earlier module claimed it. Words are compared the way the
-- registry stores them (ASCII lower case); a word that is already taken keeps its handler and
-- help text untouched, and the skip is logged at debug level.
local function registerIfFree(word, handler, help)
    local Slash = FGPS.Slash
    local key = Util.Lower(word)
    if Slash.commands[key] then
        FGPS.Log:Debug("Slash word '%s' is owned by an earlier module; Settings keeps that handler", key)
        return false
    end
    Slash.Register(word, handler, help)
    return true
end
UISettings.RegisterIfFree = registerIfFree

-- Every word this module offers, in help order. Each entry is skipped when another module already
-- registered the word, so nothing here can shadow perf, log, version, help, voice, stops,
-- preview, fav, recent, layout or search.
local SLASH_WORDS = {
    { "options", function() UISettings:Open() end, "Open the options panel" },
    { "config", function() UISettings:Open() end, "Open the options panel" },
    { "about", function() Actions.About() end, "Show version, data version, client build and Edit Mode status" },
    { "start", slashStart, "Start (or resume) navigation for the previewed route" },
    { "pause", slashPause, "Pause guidance" },
    { "resume", slashResume, "Resume guidance" },
    { "cancel", slashCancel, "Cancel the current trip" },
    { "stop", slashCancel, "Same as cancel" },
    { "preset", slashPreset, "Apply an interface preset: minimal|modern|classic" },
    { "arrow", slashArrow, "Arrow: on|off|scale <n>|<placement>" },
    { "legend", slashLegend, "Map legend: on|off" },
    { "debug", slashDebug, "Toggle debug output: on|off" },
    { "reset", slashReset, "Reset settings|positions|routing|all|<element>" },
    { "search", slashSearchFallback, "Open the destination search" },
}

function UISettings:RegisterSlashCommands()
    if self.slashRegistered then return end
    self.slashRegistered = true
    for _, entry in ipairs(SLASH_WORDS) do
        registerIfFree(entry[1], entry[2], L[entry[3]])
    end
end

function UISettings:Init()
    self:RegisterSlashCommands()
    self:Register()
end
