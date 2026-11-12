


















local ADDON_NAME, FGPS = ...

local L = FGPS.L
local type, tonumber, tostring, pcall, rawget = type, tonumber, tostring, pcall, rawget

local QuestClicks = { hooks = {} }
FGPS.UI.QuestClicks = QuestClicks



local function ctrlOnly()
    if not (IsControlKeyDown ~= nil and IsControlKeyDown() == true) then return false end
    if (IsShiftKeyDown and IsShiftKeyDown()) or (IsAltKeyDown and IsAltKeyDown()) then return false end
    if IsModifiedClick and (IsModifiedClick("CHATLINK") or IsModifiedClick("QUESTWATCHTOGGLE")) then return false end
    return true
end

local function count(field, source)
    local QuestSearch = FGPS.QuestSearch
    local stats = QuestSearch and QuestSearch.stats
    if type(stats) ~= "table" then return end
    if type(stats[field]) ~= "table" then stats[field] = {} end
    stats[field][source] = (stats[field][source] or 0) + 1
end





function QuestClicks.Go(questID, source)
    local QuestSearch = FGPS.QuestSearch
    questID = tonumber(questID)
    if not (questID and questID > 0 and QuestSearch and QuestSearch.Next) then return false end
    count("clicks", source)
    local ok, dest = pcall(QuestSearch.Next, questID)
    if not ok then
        FGPS.Log:Error("The quest's place could not be worked out: %s", tostring(dest))
        return false
    end
    if not dest then
        FGPS:Print(L["I can't tell where this quest takes you next."])
        return false
    end
    local Go = FGPS.UI.Go
    if not (Go and Go.Start and Go.Start(dest)) then return false end
    count("routes", source)
    return true
end



local function hook(key, target, name, fn)
    local hooks = QuestClicks.hooks
    if hooks[key] or type(hooksecurefunc) ~= "function" then return end
    if type(target) == "table" and type(target[name]) == "function" then
        hooks[key] = pcall(hooksecurefunc, target, name, fn) or nil
    end
end

local function hookGlobal(key, name, fn)
    local hooks = QuestClicks.hooks
    if hooks[key] or type(hooksecurefunc) ~= "function" or type(rawget(_G, name)) ~= "function" then return end
    hooks[key] = pcall(hooksecurefunc, name, fn) or nil
end



function QuestClicks.HookAll()

    hookGlobal("log", "QuestMapLogTitleButton_OnClick", function(button, mouseButton)
        if mouseButton == "LeftButton" and type(button) == "table" and ctrlOnly() then QuestClicks.Go(button.questID, "log") end
    end)


    local function onHeader(_, block, mouseButton)
        if mouseButton == "LeftButton" and type(block) == "table" and ctrlOnly() then QuestClicks.Go(block.id, "tracker") end
    end
    hook("tracker", rawget(_G, "QuestObjectiveTracker"), "OnBlockHeaderClick", onHeader)
    hook("campaign", rawget(_G, "CampaignQuestObjectiveTracker"), "OnBlockHeaderClick", onHeader)

    local loader = rawget(_G, "QuestieLoader")
    local modules = type(loader) == "table" and rawget(loader, "_modules") or nil
    local utils = type(modules) == "table" and rawget(modules, "TrackerUtils") or nil
    hook("questie", utils, "SetQuestTomTomTarget", function(questID)
        QuestClicks.Go(questID, "questie")
    end)
    return QuestClicks.hooks
end

function QuestClicks:Init()
    if self.initialised then return end
    self.initialised = true
    QuestClicks.HookAll()
    local Events = FGPS.Events
    local function retry()
        local hooks = QuestClicks.HookAll()
        if hooks.log and hooks.tracker and hooks.questie and Events.UnregisterWoW then Events:UnregisterWoW("ADDON_LOADED", self) end
    end
    if Events.RegisterWoW then Events:RegisterWoW("ADDON_LOADED", retry, self) end
    Events:Register("WORLD_ENTERED", retry, self)
end
