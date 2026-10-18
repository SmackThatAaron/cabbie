










local ADDON_NAME, FGPS = ...

local L = FGPS.L
local type, pcall, format, ipairs = type, pcall, string.format, ipairs

local Menus = { bound = false }
FGPS.UI.Menus = Menus




Menus.TRACKER_TAG = "MENU_QUEST_OBJECTIVE_TRACKER"
Menus.QUEST_LOG_TAG = "MENU_QUEST_MAP_LOG_TITLE"

Menus.NO_PLACE_HOLD = 4

Menus.STOPPED_HOLD = 6




Menus.UNDO_CLICK_DELAY = 0.5

local MAX_PARENTS = 4





local NOT_THE_PLAYERS = { not_in_log = true, no_quest = true }




function Menus.TakeMeThere(questID)
    local Quests, Go, Guide = FGPS.Quests, FGPS.UI.Go, FGPS.UI.Guide
    if not (Quests and Quests.DestinationFor and Go and Go.Start) then return false end
    local dest, reason = Quests.DestinationFor(questID)




    local Pin = FGPS.UI.InWorldPin
    if (dest or not NOT_THE_PLAYERS[reason]) and Pin and Pin.FocusQuest then Pin.FocusQuest(questID) end
    if not dest then
        if Guide and Guide.Say then Guide.Say(Menus.NoPlaceText(reason, questID), Menus.NO_PLACE_HOLD) end
        return false
    end
    return Go.Start(dest)
end











function Menus.NoPlaceText(reason, questID)
    if reason == "failed" then return L["This quest has failed"] end
    if reason == "interior" then return L["This quest's place is inside a dungeon with no known entrance"] end
    if reason == "objective_unknown" then
        local Quests = FGPS.Quests
        if Quests and Quests.HandInKnown and Quests.HandInKnown(questID) == true then
            return L["Where the open objective is found is not known. An old record has the hand-in: ask again when the quest is ready."]
        end
    end
    return L["No place known for this quest"]
end


















function Menus.QuestSelected(questID)
    local Quests, Go, Guide, Navigator = FGPS.Quests, FGPS.UI.Go, FGPS.UI.Guide, FGPS.Navigator
    if type(questID) ~= "number" or not (Quests and Quests.FollowsMine and Quests.IsQuestRoute and Quests.DestinationFor) then return nil end
    if not (Go and Go.Start and Navigator and Navigator.HasAnythingSet and Navigator.GetStops) then return nil end
    if not Quests.FollowsMine() then return nil end
    if Navigator:HasAnythingSet() and not Quests.IsQuestRoute() then return nil end
    local stops = Navigator:GetStops()
    if #stops == 1 and stops[1].questID == questID and Navigator:IsJourney() then return "followed" end
    local dest, reason = Quests.DestinationFor(questID)
    if not dest then
        if NOT_THE_PLAYERS[reason] then return nil end
        local said = tostring(questID) .. ":" .. tostring(reason)
        if Menus.noPlaceSaid ~= said then
            Menus.noPlaceSaid = said
            if Guide and Guide.Say then Guide.Say(Menus.NoPlaceText(reason, questID), Menus.NO_PLACE_HOLD) end
        end
        return "noplace"
    end
    Menus.noPlaceSaid = nil
    return Go.Start(dest) and "started" or nil
end

local function questNumber(value)
    if type(value) == "number" and value > 0 then return value end
    return nil
end

local function blockUnderMouse()
    local foci = GetMouseFoci()
    if type(foci) ~= "table" then return nil end
    for i = 1, #foci do
        local frame = foci[i]
        for _ = 1, MAX_PARENTS do
            if type(frame) ~= "table" then break end
            if questNumber(frame.id) and frame.parentModule ~= nil then return frame.id end
            frame = type(frame.GetParent) == "function" and frame:GetParent() or nil
        end
    end
    return nil
end





function Menus.QuestUnderMouse()
    if type(GetMouseFoci) ~= "function" then return nil end
    local ok, questID = pcall(blockUnderMouse)
    if ok then return questNumber(questID) end
    return nil
end

local function addTakeMeThere(root, questID)
    if not questID or type(root) ~= "table" or type(root.CreateButton) ~= "function" then return end
    root:CreateButton(L["Take me there"], function() Menus.TakeMeThere(questID) end)
end



function Menus.OnTrackerMenu(owner, root, contextData)
    local named = type(contextData) == "table" and (questNumber(contextData.id) or questNumber(contextData.questID)) or nil
    addTakeMeThere(root, named or Menus.QuestUnderMouse())
end



function Menus.OnQuestLogMenu(owner, root)
    addTakeMeThere(root, type(owner) == "table" and questNumber(owner.questID) or nil)
end





local function inCombat()
    return InCombatLockdown ~= nil and InCombatLockdown() == true
end

local function now()
    return (GetTime and GetTime()) or 0
end



function Menus.ShowOnMap()
    if type(OpenWorldMap) ~= "function" or inCombat() then return false end
    local Navigator = FGPS.Navigator
    local route = Navigator and Navigator.GetRoute and Navigator:GetRoute() or nil
    local stops = type(route) == "table" and route.stops or nil
    local stop = type(stops) == "table" and stops[#stops] or nil
    local dest = stop and (stop.dest or stop) or nil
    OpenWorldMap(type(dest) == "table" and dest.map or nil)
    return true
end


local function routeStopped()
    local Guide = FGPS.UI.Guide
    return Guide ~= nil and Guide.IsStopped ~= nil and Guide.IsStopped() == true
end





function Menus.BringBack()
    local Navigator, Guide = FGPS.Navigator, FGPS.UI.Guide
    local back = Navigator ~= nil and Navigator.UndoClear ~= nil and Navigator:UndoClear({ quiet = true }) == true
    if not back and Guide and Guide.HideStopped then Guide.HideStopped() end
    return back
end

local function addResetPosition(root)
    root:CreateButton(L["Reset position"], function()
        local RouteBlock = FGPS.UI.RouteBlock
        if RouteBlock and RouteBlock.ResetPlace then RouteBlock.ResetPlace() end
    end)
end






local function addGoToCorpse(root)
    local Social = FGPS.Social
    if not (Social and Social.IsGhost and Social.GoToCorpse and Social.IsGhost()) then return end
    root:CreateButton(L["Go to my corpse"], function() Social.GoToCorpse(true) end)
end






local function addFollowMyQuests(root)
    local Quests = FGPS.Quests
    if not (Quests and Quests.IsQuestRoute and Quests.FollowsMine and Quests.SetFollowsMine and Quests.IsQuestRoute()) then return end
    local function toggle() Quests.SetFollowsMine(not Quests.FollowsMine()) end
    if type(root.CreateCheckbox) == "function" then
        root:CreateCheckbox(L["Follow my quests"], function() return Quests.FollowsMine() end, toggle)
    elseif Quests.FollowsMine() then
        root:CreateButton(L["Stop following my quests"], toggle)
    else
        root:CreateButton(L["Follow my quests"], toggle)
    end
end



local function addHowToUse(root)
    root:CreateButton(L["How to use Cabbie"], function()
        local Line = FGPS.UI.SearchLine
        if Line and Line.Guide then Line.Guide() end
    end)
end

function Menus.RouteMenu(owner, root)
    local Navigator = FGPS.Navigator
    local state = Navigator and Navigator.GetState and Navigator:GetState() or "idle"

    if routeStopped() then
        root:CreateButton(L["Bring the route back"], function() Menus.BringBack() end)
        addGoToCorpse(root)
        addResetPosition(root)
        addHowToUse(root)
        return
    end
    addGoToCorpse(root)







    root:CreateButton(L["Stop route"], function()
        if not (Navigator and Navigator.Clear) then return end
        local stops = Navigator.GetStops and Navigator:GetStops() or nil
        local undo = type(stops) == "table" and #stops > 0
        local Guide, RouteBlock = FGPS.UI.Guide, FGPS.UI.RouteBlock
        if not (Navigator:Clear("user", { quiet = true }) and undo and Guide) then return end
        Menus.stoppedAt = now()
        if Guide.ShowStopped then Guide.ShowStopped() end
        local blockSaysIt = Guide.ShowStopped ~= nil and RouteBlock ~= nil and RouteBlock.Wanted ~= nil and RouteBlock.Wanted() == true
        if not blockSaysIt and Guide.Say then
            Guide.Say(format(L["Route stopped. Type /cabbie undo within %d seconds to bring it back"], Navigator.UNDO_SECONDS or 30),
                Menus.STOPPED_HOLD)
        end
    end)


    if state == "paused" then
        root:CreateButton(L["Resume"], function()
            if Navigator and Navigator.Resume then Navigator:Resume() end
        end)
    elseif state == "active" or state == "in_transit" then
        root:CreateButton(L["Pause"], function()
            if Navigator and Navigator.Pause then Navigator:Pause() end
        end)
    end
    addFollowMyQuests(root)
    if not inCombat() then
        root:CreateButton(L["Show on map"], function() Menus.ShowOnMap() end)
    end
    addResetPosition(root)
    addHowToUse(root)
end


function Menus.OpenRouteMenu(owner)
    if type(MenuUtil) ~= "table" or type(MenuUtil.CreateContextMenu) ~= "function" then return nil end
    return MenuUtil.CreateContextMenu(owner, Menus.RouteMenu)
end







function Menus.RouteTooltip(onLine)
    local Navigator = FGPS.Navigator
    if onLine and routeStopped() then return { L["Route"], L["Route stopped. Click to bring it back."] } end
    local lines = { L["Route"], L["Click for options. Drag to move."] }
    if Navigator and Navigator.GetState and Navigator:GetState() == "paused" and Navigator.pauseReason ~= nil then
        lines[#lines + 1] = L["Resume tries again."]
    end
    return lines
end



local function showRouteTooltip(button)
    if not GameTooltip then return end
    local RouteBlock = FGPS.UI.RouteBlock
    local frame = RouteBlock and RouteBlock.frame or nil
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    for i, line in ipairs(Menus.RouteTooltip(frame ~= nil and button == frame.Body)) do
        if i == 1 then GameTooltip:AddLine(line) else GameTooltip:AddLine(line, 1, 1, 1, true) end
    end
    GameTooltip:Show()
end

local function hideRouteTooltip(button)
    if GameTooltip and (not GameTooltip.IsOwned or GameTooltip:IsOwned(button)) then GameTooltip:Hide() end
end









function Menus.OnHeaderClick(owner, button)
    local RouteBlock = FGPS.UI.RouteBlock
    if button == "LeftButton" then
        if RouteBlock and RouteBlock.dragged then
            RouteBlock.dragged = false
            return nil
        end
    elseif button ~= "RightButton" then
        return nil
    end
    hideRouteTooltip(owner)
    return Menus.OpenRouteMenu(owner)
end










function Menus.OnLineClick(owner, button)
    if button == "RightButton" then
        hideRouteTooltip(owner)
        return Menus.OpenRouteMenu(owner)
    end
    if button ~= "LeftButton" or not routeStopped() then return nil end
    if Menus.stoppedAt and now() - Menus.stoppedAt < Menus.UNDO_CLICK_DELAY then return nil end
    hideRouteTooltip(owner)
    Menus.BringBack()
    return nil
end







Menus.TRACKING_TAG = "MENU_MINIMAP_TRACKING"
Menus.NEAREST_HOLD = 4


Menus.NEAREST = {
    { "inn", "Inn", "Inn" }, { "bank", "Bank", "Bank" }, { "flightmaster", "Flight master", "Flight master" },
    { "repair", "Repair", "Repair vendor" }, { "mailbox", "Mailbox", "Mailbox" }, { "vendor", "Vendor", "Vendor" },
    { "trainer", "Class trainer", "Class trainer" }, { "stable", "Stable master", "Stable master" },
}





function Menus.GoToNearest(service, word)
    local Services, Go, Guide = FGPS.ServiceSearch, FGPS.UI.Go, FGPS.UI.Guide
    if not (Services and Services.Nearest and Go and Go.Start) then return false end
    local asked = service
    if service == "trainer" then

        local class = Services.PlayerClass and Services.PlayerClass() or nil
        if class then asked = "trainer:" .. class end
    end
    if Guide and Guide.Say then
        local noun = type(word) == "string" and word or service
        for _, row in ipairs(Menus.NEAREST) do
            if row[1] == service then noun = L[row[3]] break end
        end
        Guide.Say(format(L["Finding the nearest %s"], FGPS.Util.Lower(noun)), Menus.NEAREST_HOLD)
    end



    local pick = {}
    Menus.nearestPick = pick
    return Services.Nearest(asked, { limit = 1 }, function(list)
        if Menus.nearestPick ~= pick then return end
        Menus.nearestPick = nil
        local best = type(list) == "table" and list[1] or nil
        if best and type(best.dest) == "table" then
            Go.Start(best.dest)
        elseif Guide and Guide.Say then
            Guide.Say(L["None found near here"], Menus.NEAREST_HOLD)
        end
    end) == true
end


function Menus.OnTrackingMenu(owner, root)
    if type(root) ~= "table" or type(root.CreateButton) ~= "function" then return end
    if type(root.CreateDivider) == "function" then root:CreateDivider() end
    local nearest = root:CreateButton(L["Go to nearest"])
    if type(nearest) ~= "table" or type(nearest.CreateButton) ~= "function" then return end
    for _, service in ipairs(Menus.NEAREST) do
        nearest:CreateButton(L[service[2]], function() Menus.GoToNearest(service[1], L[service[2]]) end)
    end
end




function Menus:Init()
    if self.bound then return end
    self.bound = true
    if type(Menu) == "table" and type(Menu.ModifyMenu) == "function" then
        Menu.ModifyMenu(Menus.TRACKER_TAG, Menus.OnTrackerMenu)
        Menu.ModifyMenu(Menus.QUEST_LOG_TAG, Menus.OnQuestLogMenu)

        Menus.questMenus = true
        Menu.ModifyMenu(Menus.TRACKING_TAG, Menus.OnTrackingMenu)
    end



    FGPS.Events:Register("DESTINATION_SET", function()
        Menus.nearestPick = nil
        Menus.noPlaceSaid = nil
    end, self)
    FGPS.Events:Register("NAV_CANCELLED", function() Menus.nearestPick = nil end, self)
    local RouteBlock = FGPS.UI.RouteBlock
    local frame = RouteBlock and RouteBlock.frame or nil





    local function bind(button, onClick)
        if not (button and button.RegisterForClicks) then return end
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:SetScript("OnClick", onClick)
        button:SetScript("OnEnter", showRouteTooltip)
        button:SetScript("OnLeave", hideRouteTooltip)
    end
    bind(frame and frame.Header, function(clicked, mouseButton) Menus.OnHeaderClick(clicked, mouseButton) end)
    bind(frame and frame.Body, function(clicked, mouseButton) Menus.OnLineClick(clicked, mouseButton) end)
end
