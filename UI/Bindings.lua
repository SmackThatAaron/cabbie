















local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local type, ipairs, pairs, tostring, format = type, ipairs, pairs, tostring, string.format

local Bindings = {
    lastAction = nil,
}
FGPS.UI.Bindings = Bindings




Bindings.HEADER = "BINDING_HEADER_CABBIE"




local function navigator()
    return FGPS.Navigator
end









local function actionGoTo()
    local Line = FGPS.UI.SearchLine
    if not (Line and Line.Toggle) then
        FGPS:Print(L["The search line is not available in this session."])
        return false
    end
    return Line.Toggle() and true or false
end



local function actionSearch()
    local Search = FGPS.UI.Search
    if not Search or not Search.Toggle then
        FGPS:Print(L["The search window is not available in this session."])
        return false
    end
    Search:Toggle()
    return true
end



local function actionRepeat()
    local Voice = FGPS.UI.Voice
    if Voice and Voice.Repeat and Voice:IsEnabled() and Voice:IsAvailable() then
        return Voice:Repeat() and true or false
    end

    local Navigator = navigator()
    local progress = Navigator and Navigator.GetProgress and select(2, pcall(Navigator.GetProgress, Navigator)) or nil
    local step = type(progress) == "table" and progress.currentStep or nil
    local text = type(step) == "table" and (step.text or step.shortText) or nil
    if text then
        FGPS:Print("%s", text)
        return true
    end
    FGPS:Print(L["There is no instruction to repeat."])
    return false
end



local function actionMute()
    local Voice = FGPS.UI.Voice
    if not Voice or not Voice.Mute then
        FGPS:Print(L["Voice guidance is not available in this session."])
        return false
    end
    Voice:Mute()
    FGPS:Print(L["Voice guidance muted; queued speech cleared."])
    return true
end







local function actionClear()
    local Navigator = navigator()
    if not Navigator or not Navigator.Clear then
        FGPS:Print(L["Navigation is not available right now."])
        return false
    end
    return Navigator:Clear("user") and true or false
end


local actionCancel = actionClear



local function actionArrow()
    local DB = FGPS.DB
    if not DB or not DB.Set then return false end
    local enabled = DB:Get("arrow.enabled") ~= false
    DB:Set("arrow.enabled", not enabled)
    FGPS:Print(enabled and L["Arrow disabled."] or L["Arrow enabled."])
    return true
end



local function actionStepList()
    local DB = FGPS.DB
    if not DB or not DB.Set then return false end
    local enabled = DB:Get("panel.enabled") == true
    DB:Set("panel.enabled", not enabled)
    local Panel = FGPS.UI.Panel
    if Panel and Panel.UpdateVisibility then Panel.UpdateVisibility() end
    FGPS:Print(enabled and L["Step list hidden."] or L["Step list shown."])
    return true
end


local function actionPauseResume()
    local Navigator = navigator()
    if not Navigator then
        FGPS:Print(L["Navigation is not available right now."])
        return false
    end
    local state = Navigator.GetState and Navigator:GetState() or nil
    if state == "paused" then
        if not Navigator.Resume then return false end
        return Navigator:Resume() and true or false
    end
    if state == "active" or state == "in_transit" then
        if not Navigator.Pause then return false end
        return Navigator:Pause() and true or false
    end
    FGPS:Print(L["Nothing to pause or resume."])
    return false
end



local function actionMapDestination()
    local map = WorldMapFrame
    if not map or (map.IsShown and not map:IsShown()) then
        FGPS:Print(L["Open the world map first, then press the key with the cursor over the place you want."])
        return false
    end
    local mapID = map.GetMapID and map:GetMapID() or nil


    local cx, cy
    local canvas = map.GetCanvas and map:GetCanvas() or nil
    for _, owner in ipairs({ map, canvas }) do
        if cx == nil and type(owner) == "table" and owner.GetNormalizedCursorPosition then
            local ok, x, y = pcall(owner.GetNormalizedCursorPosition, owner)
            if ok and type(x) == "number" and type(y) == "number" then cx, cy = x, y end
        end
    end
    if not mapID or type(cx) ~= "number" or type(cy) ~= "number" then
        FGPS:Print(L["The cursor is not over the world map."])
        return false
    end
    if cx < 0 or cx > 1 or cy < 0 or cy > 1 then
        FGPS:Print(L["The cursor is not over the world map."])
        return false
    end
    local Destinations = FGPS.Destinations
    if not Destinations or not Destinations.FromMapClick then
        FGPS:Print(L["Navigation is not available right now."])
        return false
    end
    local ok, dest, err = pcall(Destinations.FromMapClick, mapID, cx, cy)
    if not ok or not dest then
        FGPS:Print(L["That map position cannot be used as a destination%s"], (ok and err) and (": " .. tostring(err)) or ".")
        return false
    end
    local Compat = FGPS.UI.Compat
    if Compat and Compat.Accept then return Compat.Accept(dest, { source = "binding" }) end
    local WorldMap = FGPS.UI.WorldMap
    if WorldMap and WorldMap.GoTo then return WorldMap.GoTo(dest) and true or false end
    return false
end



Bindings.ORDER = { "goTo", "search", "stepList", "pauseResume", "repeat", "mute", "cancel", "clear", "arrow", "mapDestination" }
Bindings.ACTIONS = {
    goTo = { binding = "CABBIE_GOTO", label = "Go to a place", run = actionGoTo },
    search = { binding = "CABBIE_SEARCH", label = "Open the destination search", run = actionSearch },
    stepList = { binding = "CABBIE_STEP_LIST", label = "Toggle step list", run = actionStepList },
    pauseResume = { binding = "CABBIE_PAUSE_RESUME", label = "Pause or resume guidance", run = actionPauseResume },
    ["repeat"] = { binding = "CABBIE_REPEAT", label = "Repeat the current instruction", run = actionRepeat },
    mute = { binding = "CABBIE_MUTE", label = "Mute voice guidance", run = actionMute },


    cancel = { binding = "CABBIE_CANCEL", label = "Clear route", run = actionCancel },
    clear = { binding = "CABBIE_CLEAR", label = "Clear route", run = actionClear },
    arrow = { binding = "CABBIE_ARROW", label = "Show or hide the guidance arrow", run = actionArrow },
    mapDestination = { binding = "CABBIE_MAP_DESTINATION", label = "Set a destination at the world map cursor", run = actionMapDestination },
}







function Bindings.Run(name)
    local action = Bindings.ACTIONS[name]
    if not action then
        FGPS.Log:Warn("Unknown key binding action '%s'", tostring(name))
        return false
    end
    Bindings.lastAction = name
    local ok, result = pcall(action.run)
    if not ok then
        FGPS.Log:Error("Key binding '%s' failed: %s", tostring(name), tostring(result))
        return false
    end
    return result and true or false
end


function Bindings.KeyFor(name)
    local action = Bindings.ACTIONS[name]
    if not action or type(GetBindingKey) ~= "function" then return nil end
    local ok, key = pcall(GetBindingKey, action.binding)
    if ok and type(key) == "string" and key ~= "" then return key end
    return nil
end







local function publishNames()
    local globals = _G
    if type(globals) ~= "table" then return false end
    globals[Bindings.HEADER] = L["Cabbie"]
    for _, name in ipairs(Bindings.ORDER) do
        local action = Bindings.ACTIONS[name]
        globals["BINDING_NAME_" .. action.binding] = L[action.label]
    end
    return true
end
Bindings.PublishNames = publishNames
publishNames()




local function slashBind()
    FGPS:Print(L["Key bindings (set them in the game's Key Bindings interface, under Cabbie):"])
    for _, name in ipairs(Bindings.ORDER) do
        local action = Bindings.ACTIONS[name]
        local key = Bindings.KeyFor(name)
        FGPS:Print("  %s: %s", L[action.label], key or L["not bound"])
    end
end




function Bindings:Init()
    publishNames()
    if not Bindings.initialised then
        Bindings.initialised = true
        FGPS.Slash.Register("bind", slashBind, L["List the Cabbie key bindings and the keys they are on"])
    end
    return Bindings
end
