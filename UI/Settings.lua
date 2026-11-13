



























local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local type, ipairs, tostring, tonumber, format = type, ipairs, tostring, tonumber, string.format

local UISettings = {
    category = nil,
    subcategories = {},
    proxies = {},
    registered = false,
}
FGPS.UI.Settings = UISettings

local CATEGORY_NAME = "Cabbie"
local VARIABLE_PREFIX = "FGPS_"






local TEXT_SIZES = { { "normal", "Normal" }, { "large", "Large" } }

local UNITS = { { "yards", "Yards" }, { "metric", "Metric" } }


local MODIFIERS = { { "CTRL_RIGHT", "Ctrl + Right-click" }, { "ALT_LEFT", "Alt + Left-click" },
                    { "SHIFT_RIGHT", "Shift + Right-click" },
                    { "NONE", "No extra click", "Switches off the extra click only. Shift + Left-click still goes to the spot." } }




function UISettings.MapClickLabel(modifier)
    if modifier == "NONE" then return nil end
    for _, entry in ipairs(MODIFIERS) do
        if entry[1] == modifier then return L[entry[2]] end
    end
    return nil
end

local COMBAT_MODES = { { "all", "Keep All Guidance" },
                       { "visuals_only", "Visuals only, no voice" },
                       { "hide_all", "Hide all guidance" } }
local VERBOSITY = { { "minimal", "Minimal" }, { "normal", "Normal" }, { "detailed", "Detailed" } }
local ASSUME_MOUNT = { { "auto", "Detect automatically" }, { "none", "Never mounted" },
                       { "60", "60% mount" }, { "100", "100% mount" } }

local COLOR_SCHEMES = { { "preset", "Standard Colours" }, { "colorblind", "Colour-blind friendly" } }
UISettings.COLOR_SCHEMES = COLOR_SCHEMES





local ELEMENT_KEYS = {
    { "window:tome", "Reset Cabbie window position" },
}
local ELEMENT_ALIASES = { window = "window:tome", tome = "window:tome", search = "window:tome", places = "window:tome",
                          preview = "window:tome", favorites = "window:tome", itinerary = "window:tome",
                          stops = "window:tome" }




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
        container:Add(0, L["None reported by the game"])
    end
    for _, v in ipairs(voices) do container:Add(v.voiceID, tostring(v.name)) end
    return container:GetData()
end







local function buttonInitializer(name, buttonText, onClick, tooltip, built)
    if not Settings.RegisterInitializer then return nil end
    local label, tip = name, tooltip or name
    if not built then label, tip = L[label], L[tip] end
    if CreateSettingsButtonInitializer then
        return CreateSettingsButtonInitializer(label, L[buttonText], onClick, tip, true)
    end
    if Settings.CreateElementInitializer then
        local data = { name = label, buttonText = L[buttonText], buttonClick = onClick, tooltip = tip }
        local initializer = Settings.CreateElementInitializer("SettingButtonControlTemplate", data)
        if initializer and initializer.AddSearchTags then initializer:AddSearchTags(label) end
        return initializer
    end
    return nil
end

local function addButton(category, name, buttonText, onClick, tooltip, built)
    local initializer = buttonInitializer(name, buttonText, onClick, tooltip, built)
    if not initializer then return false end
    Settings.RegisterInitializer(category, initializer)
    return true
end



local function headerInitializer(text, tooltip)
    if not Settings.RegisterInitializer then return nil end
    if CreateSettingsListSectionHeaderInitializer then
        return CreateSettingsListSectionHeaderInitializer(text, tooltip)
    elseif Settings.CreateElementInitializer then
        return Settings.CreateElementInitializer("SettingsListSectionHeaderTemplate", { name = text, tooltip = tooltip })
    end
    return nil
end

local function addHeader(category, text, tooltip)
    local initializer = headerInitializer(text, tooltip)
    if not initializer then return false end
    Settings.RegisterInitializer(category, initializer)
    return true
end




local Actions = {}
UISettings.Actions = Actions

local function elementName(key)
    for _, entry in ipairs(ELEMENT_KEYS) do
        if entry[1] == key then
            return (entry[2]:match("^Reset (.*) position$")) or key
        end
    end
    return nil
end

function Actions.ResetElement(key)
    local DB = FGPS.DB
    key = ELEMENT_ALIASES[key] or key
    local name = elementName(key)
    if not name then return false end
    if DB and DB.ResetElementPosition then DB:ResetElementPosition(key) end
    FGPS:Print(L["Position of '%s' restored to its default."], name)
    return true
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
        FGPS:Print(L["Recent places cleared."])
    else
        FGPS:Print(L["Recent places aren't available right now."])
    end
end

function Actions.PerfReport()
    local Perf = FGPS.Perf
    if Perf then
        if Perf.Sample then Perf:Sample() end
        Perf:Print()
    end
end



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
            editMode = L["not available, Cabbie's own layout editor instead"]
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








local function registerClientLine(category)
    local lines = UISettings.AboutLines()
    local tooltipParts = {}
    for _, line in ipairs(lines) do tooltipParts[#tooltipParts + 1] = line[1] .. ": " .. line[2] end
    local tooltip = table.concat(tooltipParts, "\n")
    local build = FGPS.build or {}
    local rowName = format(L["Client %s (%s), Edit Mode: %s"], tostring(build.version or "?"), tostring(build.buildNumber or "?"), lines[4][2])
    local added = addButton(category, rowName, "Details", Actions.About, tooltip, true)
    if not added then FGPS.Log:Debug("Settings client build row unavailable in this client; use /cabbie about") end
    return added
end




local function registerGeneral(category)
    checkbox(category, "callout.enabled", "Turn arrow", "The arrow at the top of the screen that points along your route.")
    checkbox(category, "callout.showWords", "Show the words", "Names the turn and its landmark on a small scroll under the arrow.")
    checkbox(category, "callout.showDistance", "Show the distance", "Shows how far away the turn is, under the arrow.")
    checkbox(category, "callout.turnPulse", "Pulse at turns", "The arrow glows once, softly, when a turn comes up.")
    checkbox(category, "roadBeacon", "Road beacon", "Shows a light beam, turn icon and distance on the road ahead in the world.")
    checkbox(category, "windowSounds", "Window sounds",
        "Plays the game's quest log sounds in the Cabbie window: opening, closing, turning a page and picking a row.")
    checkbox(category, "worldMapLine", "World map line", "Draws your route on the world map.")
    checkbox(category, "worldMapLegend", "Route label on the map",
        "Names the route and its stops in a small label in the corner of the world map.")
    checkbox(category, "minimapLine", "Minimap line", "Draws your route on the minimap as a line of dots.")
    checkbox(category, "minimapButton", "Minimap button", "A button on the edge of the minimap that opens the Cabbie window.")
    dropdown(category, "units", "Distance units", "Yards or metres and kilometres.", UNITS)
end


local function registerGuidance(category)
    addHeader(category, L["Guidance"])

    checkbox(category, "routeBlock.enabled", "Show your route's steps beside the quest list",
        "The time and distance left, and the next few steps of your route, in a list beside the game's quest list. Drag it by its first line to move it. The arrow at the top of the screen guides you without it.")



    checkbox(category, "askCorpseRun", "Ask to take me back to my body when I die",
        "When you release your spirit, Cabbie asks whether to guide you back to your body. With this off, nothing is asked: as a ghost, pick Go to My Corpse at the top of the Places page, in your route's menu, or in the menu you get by right-clicking Cabbie beside the minimap.")
    dropdown(category, "combatMode", "In combat", "What guidance keeps doing while you are in combat.", COMBAT_MODES)
end

local function registerTextAndColours(category)
    addHeader(category, L["Text and Colours"])
    dropdown(category, "textSize", "Text size", "Normal or Large. Large adds two points to text in the Cabbie window, the Go to: line, the Route steps and the welcome window.", TEXT_SIZES)
    dropdown(category, "accessibility.colorScheme", "Colour scheme",
        "Colour-blind friendly replaces the route, transport and accent colours with a set that stays distinguishable for the common forms of colour blindness. The distinction between a road and open ground never depends on colour alone in either scheme: the map draws open ground dashed and the minimap draws it as larger hollow dots.",
        COLOR_SCHEMES)
end



local function registerMap(category)
    addHeader(category, L["Map"])
    checkbox(category, "openWithMap", "Open Cabbie when the world map opens",
        "The Places page opens beside the world map each time you open it, and closes with it. It never takes the keyboard.")
    checkbox(category, "inWorldPin", "Show the in-world waypoint marker", "Uses the game's own waypoint marker for the next point of the route.")
    dropdown(category, "mapClickModifier", "Extra world map click",
        "An extra click that sets a destination on the world map. Choose its modifier and mouse button, or switch it off. Shift + Left-click always goes to the spot at once.",
        MODIFIERS)
    checkbox(category, "removeStopOnMarkerOnly", "Remove a stop only when I click its marker",
        "Off (the default): Shift + Right-click anywhere on the world map removes the stop nearest the click, or the stop you are heading to when none is on the map. On: only Shift + Right-click on a stop's own marker removes it. When the extra world map click is Shift + Right-click, that click sets a destination and only the marker removes a stop.")
    checkbox(category, "goToMapPin", "Go to the map pin I place",
        "A pin you place on the world map becomes your route's new place, as a click on the map does, and starts a route when none runs. While you travel, Cabbie's marker uses the same pin and puts yours back at the end.")
    checkbox(category, "compat.wayCommand", "Answer the /way command",
        "Lets Cabbie take waypoint coordinates written the way guides and web sites write them. The word is only claimed when no other add-on already owns it.")
    addHeader(category, L["Place Icons"])


    local MapPlaces = FGPS.UI.MapPlaces
    for _, row in ipairs(MapPlaces and MapPlaces.CATEGORIES or {}) do
        checkbox(category, "mapPlaces." .. row.key, row.label, row.tooltip)
    end
end

local function registerTransport(category)
    addHeader(category, L["Transport"])
    checkbox(category, "transports.taxi", "Use flight paths")
    checkbox(category, "transports.boat", "Use boats")
    checkbox(category, "transports.zeppelin", "Use zeppelins")
    checkbox(category, "transports.tram", "Use the Deeprun Tram")
    checkbox(category, "transports.hearth", "Consider the Hearthstone",
        "Routes may start with your Hearthstone when that is quicker. Cabbie learns where it takes you the first time you use it or make an inn your home. Your Route's tooltip on the Places page says when it is left out, and why.")
    checkbox(category, "transports.spells", "Consider teleport spells")
end








function UISettings.GameHasVoices()
    local Voice = FGPS.UI.Voice
    return Voice ~= nil and Voice.HasSystemVoice ~= nil and Voice:HasSystemVoice() == true
end

local function onlyWithGameVoices(initializer)
    if type(initializer) == "table" and initializer.AddModifyPredicate then
        initializer:AddModifyPredicate(UISettings.GameHasVoices)
    end
    return initializer
end


local function playSample()
    local Voice = FGPS.UI.Voice
    if Voice and Voice.PlaySample then Voice:PlaySample() end
end



local function addSampleRow(category, name, tooltip, shownWhen)
    local initializer = buttonInitializer(name, "Play a sample", playSample, tooltip)
    if not initializer then return nil end
    if initializer.AddShownPredicate then
        initializer:AddShownPredicate(shownWhen)
    elseif not shownWhen() then
        return nil
    end
    Settings.RegisterInitializer(category, initializer)
    return initializer
end

local function registerVoice(category)
    checkbox(category, "voice.enabled", "Voice guidance", "Speak turn instructions out loud.")


    UISettings.noVoicesLine = addSampleRow(category, "Speaking with Cabbie's recorded voice",
        "The game reports no text-to-speech voice on this computer, so the game voice settings below are greyed out. Cabbie's recorded voice needs nothing installed. Play a sample says one short sentence in it.",
        function() return not UISettings.GameHasVoices() end)
    UISettings.sampleLine = addSampleRow(category, "Voice sample",
        "Says one short sentence in the voice chosen on this page, with voice guidance on or off.", UISettings.GameHasVoices)
    onlyWithGameVoices(checkbox(category, "voice.systemVoice", "Use the game's text-to-speech voice", "Off (the default): Cabbie's own recorded voice, the same on every computer. On: the voice chosen in the game's text-to-speech settings, which also says place names. Greyed out while the game reports no text-to-speech voice; the recorded one speaks then."))
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
    onlyWithGameVoices(Settings.CreateDropdown(category, setting, voiceOptions, L["Voice used for spoken guidance."]))
    onlyWithGameVoices(slider(category, "voice.rate", "Speech rate", nil, -10, 10, 1, function(value) return format("%d", value) end))
    onlyWithGameVoices(slider(category, "voice.volume", "Speech volume", nil, 0, 100, 5, function(value) return format("%d", value) end))
    dropdown(category, "voice.verbosity", "Verbosity", "Minimal: turns only. Normal: advance notices and turns. Detailed: every step and zone change.", VERBOSITY)


    checkbox(category, "cues.enabled", "Audio cues instead of speech",
        "Short sounds the game already ships, played before a turn, for a transport action and on arrival. They work with voice guidance on or off.")
    slider(category, "cues.volume", "Cue volume", "Zero is silence. Clients without a per-sound volume play cues at the game's own sound effect volume.",
        0, 100, 5, function(value) return format("%d", value) end)
    checkbox(category, "cues.turn", "Cue before a turn")
    checkbox(category, "cues.transport", "Cue for a transport action", "Boarding a boat or zeppelin, taking a flight, getting off again.")
    checkbox(category, "cues.arrival", "Cue on arrival")
end

local function registerRouting(category)
    addHeader(category, L["Routing"])
    local preferInit = checkbox(category, "routing.preferRoads", "Prefer roads",
        "Routes stick to roads unless the way round is much longer. Open ground, wandering creature paths and guessed stretches cost more. Off: the fastest line, often straight across open ground.")
    local shortcutInit = checkbox(category, "routing.roadShortcuts", "Allow shortcuts off the road",
        "Off (the default): routes keep to the road wherever one goes, and leave it only to reach a place off the road. On: a route may cut across open ground when that is clearly quicker. Needs \"Prefer roads\".")


    if type(preferInit) == "table" and type(shortcutInit) == "table" and shortcutInit.SetParentInitializer then
        shortcutInit:SetParentInitializer(preferInit, function()
            return FGPS.DB ~= nil and FGPS.DB:Get("routing.preferRoads") == true
        end)
    end
    checkbox(category, "routing.avoidGuarded", "Keep out of the other side's towns",
        "Routes go round the towns and outposts the other side holds, off the road where they must. A route still goes in when you start or stop there, or when there is no other way. Off: routes take the road through them.")
    checkbox(category, "routing.allowUnverified", "Allow straight guesses",
        "Where Cabbie knows no ground it may draw a straight line. Off: a place far from any known ground gets no route. To stay on roads use \"Prefer roads\".")
    slider(category, "routing.arrivalRadius", "Arrival radius (yards)", "How close to the place you need to be for Cabbie to say you've arrived.", 5, 100, 1,
        function(value) return format("%d", value) end)
    slider(category, "routing.offRouteYards", "Off-route distance (yards)", "How far you can stray from the route before Cabbie finds a new one.", 15, 150, 5,
        function(value) return format("%d", value) end)


    local Router = FGPS.Router
    slider(category, "routing.maxStraightYards", "Longest stretch across open ground (yards)",
        "Longest stretch across open ground a route may include. 0 turns these stretches off. The last-resort line across open ground is not affected.",
        0, 5000, 100, function(value) if value == 0 then return L["Off"] end return format("%d", value) end,
        { default = Router and Router.DEFAULT_MAX_STRAIGHT_YARDS or 3000 })
    dropdown(category, "routing.assumeMount", "Assume mount speed", "The speed Cabbie uses for travel times when it can't tell whether you're mounted.", ASSUME_MOUNT)
    slider(category, "routing.recalcMinSeconds", "Shortest time between recalculations (seconds)",
        "Once you're off the route, Cabbie looks for a new one at most this often.", 2, 30, 1,
        function(value) return format("%d", value) end)
end




local function registerActions(category)
    addHeader(category, L["Actions"])
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
        FGPS.Log:Warn("Settings buttons unavailable in this client; use /cabbie reset and /cabbie perf instead")
    end
    registerClientLine(category)
end


local function debugOn()
    local DB = FGPS.DB
    return DB ~= nil and DB.Get ~= nil and DB:Get("debug") == true
end





local function registerDeveloper(category)
    local header = headerInitializer(L["Developer"])
    local canHide = type(header) == "table" and type(header.AddShownPredicate) == "function"
    local makeRows = canHide or debugOn()
    if header and makeRows then
        if canHide then header:AddShownPredicate(debugOn) end
        Settings.RegisterInitializer(category, header)
    end
    local function row(path, kind, name, make)
        if not makeRows then
            proxy(category, path, kind, L[name])
            return
        end
        local initializer = make(name)
        if canHide and type(initializer) == "table" and initializer.AddShownPredicate then initializer:AddShownPredicate(debugOn) end
    end
    row("perf.instrument", "boolean", "Performance instrumentation", function(name)
        return checkbox(category, "perf.instrument", name, "Cheap timers for the performance report.")
    end)
    row("perf.frameBudgetMs", "number", "Route computation budget (ms per frame)", function(name)
        return slider(category, "perf.frameBudgetMs", name, "Time slice per frame for route calculation.", 1, 8, 1,
            function(value) return format("%d", value) end)
    end)
    row("perf.spareFrame", "boolean", "Use spare frame time for routes", function(name)
        return checkbox(category, "perf.spareFrame", name,
            "When the frame rate is high and you are not in combat, in a cutscene, or looking at the flight map, route calculation may use a longer slice of each frame.")
    end)
    row("perf.frameBudgetMaxMs", "number", "Longest route slice (ms per frame)", function(name)
        return slider(category, "perf.frameBudgetMaxMs", name,
            "Upper limit on that longer slice. The shorter budget above is used in combat, in a cutscene, below 30 frames a second, or with the flight map open.",
            4, 16, 1, function(value) return format("%d", value) end)
    end)
    row("debug", "boolean", "Debug output", function(name)
        return checkbox(category, "debug", name, "Prints diagnostics to chat and forwards errors to the error handler.")
    end)
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
        local voice = Settings.RegisterVerticalLayoutSubcategory(category, L["Voice"])
        local advanced = Settings.RegisterVerticalLayoutSubcategory(category, L["Advanced"])
        self.subcategories = { general = general, voice = voice, advanced = advanced }
    end)
    if not ok then
        self.failed = true
        FGPS.Log:Error("Settings registration failed: %s", tostring(err))
        return false
    end



    local sub = self.subcategories
    local pages = {
        { "General", registerGeneral, sub.general }, { "Voice", registerVoice, sub.voice },
        { "Advanced: guidance", registerGuidance, sub.advanced },
        { "Advanced: text and colours", registerTextAndColours, sub.advanced },
        { "Advanced: map", registerMap, sub.advanced },
        { "Advanced: transport", registerTransport, sub.advanced },
        { "Advanced: routing", registerRouting, sub.advanced },
        { "Advanced: actions", registerActions, sub.advanced },
        { "Advanced: developer", registerDeveloper, sub.advanced },
    }
    for _, page in ipairs(pages) do
        local pageOk, pageErr = pcall(page[2], page[3])
        if not pageOk then FGPS.Log:Error("Settings page %s failed: %s", page[1], tostring(pageErr)) end
    end
    if Settings.RegisterAddOnCategory then
        local added, addErr = pcall(Settings.RegisterAddOnCategory, self.category)
        if not added then
            self.failed = true
            FGPS.Log:Error("Settings registration failed: %s", tostring(addErr))
            return false
        end
    end
    self.registered = true
    return true
end





function UISettings:Open(subcategory)
    if InCombatLockdown and InCombatLockdown() then
        self.openAfterCombat = subcategory or true
        FGPS:Print(L["The options panel opens when you leave combat."])
        return false
    end
    if not self.registered and not self:Register() then
        FGPS:Print(L["The options panel is not available in this client; use /cabbie help for the command list."])
        return false
    end


    local target = subcategory and self.subcategories[subcategory]
        or self.subcategories.general
        or self.category
    if not target or not Settings.OpenToCategory then return false end
    local id = target.GetID and target:GetID() or target
    local ok, err = pcall(Settings.OpenToCategory, id)
    if not ok then FGPS.Log:Error("OpenToCategory failed: %s", tostring(err)) end
    return ok
end




local function navigator()
    local Navigator = FGPS.Navigator
    if not Navigator then FGPS:Print(L["Navigation is not available right now."]) end
    return Navigator
end







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



local function slashPause()
    local Navigator = navigator()
    if not (Navigator and Navigator.Pause) or Navigator:Pause() then return end
    local state = Navigator.GetState and Navigator:GetState()
    FGPS:Print(state == "paused" and L["Guidance is already paused."] or L["No route to pause."])
end

local function slashResume()
    local Navigator = navigator()
    if not (Navigator and Navigator.Resume) or Navigator:Resume() then return end
    FGPS:Print(L["Nothing is paused."])
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
        FGPS:Print(FGPS.Util.EscapeBars(L["Usage: /cabbie legend on|off"]))
        return
    end
    DB:Set("worldMapLegend", on)
    FGPS:Print(on and L["Route label on the map on."] or L["Route label on the map off."])
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
        if not Actions.ResetElement(word) then
            FGPS:Print(FGPS.Util.EscapeBars(L["Usage: /cabbie reset settings|positions|routing|all|window"]))
        end
    else
        FGPS:Print(FGPS.Util.EscapeBars(L["Usage: /cabbie reset settings|positions|routing|all|window"]))
    end
end

local function slashSearchFallback(args)
    local Search = FGPS.UI.Search
    local query = Util.Trim(args)
    if Search and Search.Show then Search:Show({ query = query ~= "" and query or nil }) end
end




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




local SLASH_WORDS = {
    { "options", function() UISettings:Open() end, "Open the options panel" },
    { "config", function() UISettings:Open() end, "Open the options panel" },
    { "about", function() Actions.About() end, "Show version, data version, client build and Edit Mode status" },
    { "start", slashStart, "Start (or resume) navigation for the previewed route" },
    { "pause", slashPause, "Pause guidance" },
    { "resume", slashResume, "Resume guidance" },
    { "legend", slashLegend, "Route label on the map: on|off" },
    { "debug", slashDebug, "Toggle debug output: on|off" },
    { "reset", slashReset, "Reset settings|positions|routing|all|window" },
    { "search", slashSearchFallback, "Open the Places page (optionally with a query)" },
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
    if not self.combatBound and FGPS.Events then
        self.combatBound = true
        local function openDeferred(_, inCombat)
            local pending = UISettings.openAfterCombat
            if inCombat or not pending then return end
            UISettings.openAfterCombat = nil
            UISettings:Open(pending ~= true and pending or nil)
        end
        FGPS.Events:Register("COMBAT_STATE", openDeferred, self)
        FGPS.Events:Register("WORLD_ENTERED", function()
            if not (InCombatLockdown and InCombatLockdown()) then openDeferred(nil, false) end
        end, self)
    end
end
