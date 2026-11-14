-- Cabbie/Core/Boot.lua
-- Last file in the load order. Owns the single boot frame: initialises saved variables on
-- ADDON_LOADED, initialises every present module in a fixed order on PLAYER_LOGIN (each Init is
-- pcall-isolated and logged; missing modules are skipped), fires ADDON_READY once, and bridges
-- PLAYER_ENTERING_WORLD and combat state to the internal bus.
local ADDON_NAME, FGPS = ...

local L = FGPS.L
local pcall, type, ipairs = pcall, type, ipairs

local Boot = {
    -- Core services that need saved settings; they run before the module list.
    coreOrder = { "Scheduler", "Perf", "DataLoad" },
    -- Fixed init order (ARCHITECTURE.md section 6). It keeps the TOC's order (section 4) by and large but
    -- not exactly: Calibrate before Social, Compat and Bindings before Cues, SelfTest last.
    order = {
        "Coords", "Graph", "Access", "Cost", "Route", "Router", "Instructions", "Personal", "Transport",
        "Destinations", "ServiceSearch", "Calibrate", "Social", "Inside", "Navigator",
        "UI.Guide", "UI.RouteBlock", "UI.Callout", "UI.Go", "UI.Menus", "UI.SearchLine",
        "UI.Skins", "UI.Frames", "UI.Positions", "UI.Tome", "UI.EditMode", "UI.WorldMap",
        "UI.MapPlaces", "UI.Minimap", "UI.Launcher", "UI.Search", "UI.Preview", "UI.Favorites", "UI.Itinerary", "UI.Voice",
        "UI.InWorldPin", "UI.Settings", "UI.Setup", "UI.WhatsNew", "UI.Compat", "UI.QuestClicks", "UI.Bindings", "UI.Cues", "SelfTest",
    },
    report = nil,
}
FGPS.Boot = Boot

-- Resolves "UI.Skins" to FGPS.UI.Skins; returns nil when any part is missing.
local function resolve(name)
    local node = FGPS
    for part in name:gmatch("[^.]+") do
        if type(node) ~= "table" then return nil end
        node = node[part]
    end
    if type(node) == "table" then return node end
    return nil
end

local function initOne(name, report)
    local module = resolve(name)
    if not module or type(module.Init) ~= "function" then
        report.skipped[#report.skipped + 1] = name
        FGPS.Log:Warn("Module %s is not there and was skipped", name)
        return false
    end
    local ok, err = pcall(module.Init, module)
    if ok then
        report.initialised[#report.initialised + 1] = name
        return true
    end
    report.failed[#report.failed + 1] = { name = name, error = tostring(err) }
    FGPS.Log:Error("Module %s failed to initialise: %s", name, tostring(err))
    return false
end

-- Initialises core services then every module present in Boot.order. Safe to call again: every
-- Init is required to be idempotent (ARCHITECTURE.md section 6).
function Boot.InitModules()
    local report = { initialised = {}, skipped = {}, failed = {} }
    for _, name in ipairs(Boot.coreOrder) do initOne(name, report) end
    for _, name in ipairs(Boot.order) do initOne(name, report) end
    Boot.report = report
    return report
end

local function onLogin()
    if FGPS.ready then return end
    if not FGPS.DB.initialized then FGPS.DB:Init() end
    FGPS.loginTime = GetTime and GetTime() or 0
    local report = Boot.InitModules()
    FGPS.ready = true
    FGPS.Events:Fire("ADDON_READY")
    local broken = #report.failed + #report.skipped
    if FGPS.UpdatedWhileRunning and FGPS.UpdatedWhileRunning() then
        FGPS:Print(L.BOOT_UPDATED_WHILE_RUNNING)
    elseif broken > 0 then
        FGPS:Print(L.BOOT_FAILED_MODULES, broken)
    end
    FGPS.Log:Info("%s %s ready: %d module(s) initialised, %d skipped, %d failed", FGPS.name, FGPS.version,
        #report.initialised, #report.skipped, #report.failed)
end
Boot.OnLogin = onLogin

local frame = CreateFrame("Frame")
Boot.frame = frame
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            FGPS.DB:Init()
            FGPS.loaded = true
            frame:UnregisterEvent("ADDON_LOADED")
            -- Loaded after login (load on demand or a late enable): PLAYER_LOGIN will not fire again.
            if IsLoggedIn and IsLoggedIn() then onLogin() end
        end
    elseif event == "PLAYER_LOGIN" then
        onLogin()
    elseif event == "PLAYER_ENTERING_WORLD" then
        FGPS.Events:Fire("WORLD_ENTERED", arg1, arg2)
    elseif event == "PLAYER_REGEN_DISABLED" then
        FGPS.Events:Fire("COMBAT_STATE", true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        FGPS.Events:Fire("COMBAT_STATE", false)
    end
end)
