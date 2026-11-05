












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




local function questHelpOff()
    local db = FGPS.DB
    return db ~= nil and db.Get ~= nil and db:Get("quests.enabled") == false
end




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
            return L["No place known for the objective: ask again when the quest is ready to turn in."]
        end
    end
    return L["No place known for this quest"]
end


















function Menus.QuestSelected(questID)
    local Quests, Go, Guide, Navigator = FGPS.Quests, FGPS.UI.Go, FGPS.UI.Guide, FGPS.Navigator
    if type(questID) ~= "number" or not (Quests and Quests.FollowsMine and Quests.IsQuestRoute and Quests.DestinationFor) then return nil end
    if questHelpOff() then return nil end
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
    if questHelpOff() then return end
    root:CreateButton(L["Guide Me"], function() Menus.TakeMeThere(questID) end)
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




function Menus.ShowOnMap(mapID)
    if type(OpenWorldMap) ~= "function" or inCombat() then return false end
    mapID = tonumber(mapID)
    if mapID then
        OpenWorldMap(mapID)
        return true
    end
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
    root:CreateButton(L["Reset Position"], function()
        local RouteBlock = FGPS.UI.RouteBlock
        if RouteBlock and RouteBlock.ResetPlace then RouteBlock.ResetPlace() end
    end)
end






local function addGoToCorpse(root)
    local Social = FGPS.Social
    if not (Social and Social.IsGhost and Social.GoToCorpse and Social.IsGhost()) then return end
    root:CreateButton(L["Go to My Corpse"], function() Social.GoToCorpse(true) end)
end






local function addFollowMyQuests(root)
    local Quests = FGPS.Quests
    if not (Quests and Quests.IsQuestRoute and Quests.FollowsMine and Quests.SetFollowsMine and Quests.IsQuestRoute()) then return end
    local function toggle() Quests.SetFollowsMine(not Quests.FollowsMine()) end
    if type(root.CreateCheckbox) == "function" then
        root:CreateCheckbox(L["Follow My Quests"], function() return Quests.FollowsMine() end, toggle)
    elseif Quests.FollowsMine() then
        root:CreateButton(L["Stop Following My Quests"], toggle)
    else
        root:CreateButton(L["Follow My Quests"], toggle)
    end
end




local function addHowToUse(root)
    root:CreateButton(L["How to Use Cabbie"], function()
        local Line = FGPS.UI.SearchLine
        if Line and Line.Guide then Line.Guide() end
    end)
end








local function stopRoute()
    local Navigator = FGPS.Navigator
    if not (Navigator and Navigator.Clear) then return end
    local stops = Navigator.GetStops and Navigator:GetStops() or nil
    local undo = type(stops) == "table" and #stops > 0
    local Guide, RouteBlock = FGPS.UI.Guide, FGPS.UI.RouteBlock
    if not (Navigator:Clear("user", { quiet = true }) and undo and Guide) then return end
    Menus.stoppedAt = now()
    if Guide.ShowStopped then Guide.ShowStopped() end
    local blockSaysIt = Guide.ShowStopped ~= nil and RouteBlock ~= nil and RouteBlock.Wanted ~= nil and RouteBlock.Wanted() == true
    if not blockSaysIt and Guide.Say then Guide.Say(L["Route stopped."], Menus.STOPPED_HOLD) end
end


local function addTitle(root)
    if type(root.CreateTitle) == "function" then root:CreateTitle(L["Route"]) end
end

function Menus.RouteMenu(owner, root)
    local Navigator = FGPS.Navigator
    local state = Navigator and Navigator.GetState and Navigator:GetState() or "idle"
    addTitle(root)

    if routeStopped() then
        root:CreateButton(L["Bring the Route Back"], function() Menus.BringBack() end)
        addGoToCorpse(root)
        addResetPosition(root)
        addHowToUse(root)
        return
    end
    addGoToCorpse(root)


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
        root:CreateButton(L["Show on Map"], function() Menus.ShowOnMap() end)
    end
    addResetPosition(root)
    addHowToUse(root)


    if type(root.CreateDivider) == "function" then root:CreateDivider() end
    root:CreateButton(L["Stop Route"], stopRoute)
end


function Menus.OpenRouteMenu(owner)
    if type(MenuUtil) ~= "table" or type(MenuUtil.CreateContextMenu) ~= "function" then return nil end
    return MenuUtil.CreateContextMenu(owner, Menus.RouteMenu)
end






local function entryDisabled(entry)
    local disabled = entry.disabled
    if type(disabled) == "function" then
        local ok, yes = pcall(disabled)
        return not ok or yes and true or false
    end
    return disabled and true or false
end












local function rowMenuGenerator(spec)
    return function(_, root)
        if type(root) ~= "table" or type(root.CreateButton) ~= "function" then return end
        if type(spec.title) == "string" and spec.title ~= "" and type(root.CreateTitle) == "function" then
            root:CreateTitle(spec.title)
        end
        local plain, ending = {}, {}
        for _, entry in ipairs(type(spec.entries) == "table" and spec.entries or {}) do
            if type(entry) == "table" and type(entry.label) == "string" then
                local into = entry.destructive and ending or plain
                into[#into + 1] = entry
            end
        end
        local add
        add = function(node, create, entry)
            if type(entry.entries) == "table" then
                local sub = create(node, entry.label)
                local into = (type(sub) == "table" and type(sub.CreateButton) == "function") and sub or node
                for _, child in ipairs(entry.entries) do
                    if type(child) == "table" and type(child.label) == "string" then add(into, into.CreateButton, child) end
                end
                return
            end
            local element = create(node, entry.label, function()
                if entryDisabled(entry) or type(entry.onClick) ~= "function" then return end
                local ok, err = pcall(entry.onClick)
                if not ok and FGPS.Log then FGPS.Log:Error("Row menu entry %s failed: %s", entry.label, tostring(err)) end
            end)
            if type(element) ~= "table" or type(element.SetEnabled) ~= "function" then return end
            if type(entry.disabled) == "function" then
                element:SetEnabled(function() return not entryDisabled(entry) end)
            elseif entry.disabled then
                element:SetEnabled(false)
            end
        end
        for _, entry in ipairs(plain) do add(root, root.CreateButton, entry) end
        if #ending == 0 then return end
        if type(root.CreateDivider) == "function" then root:CreateDivider() end
        local red = type(root.CreateRedHighlightButton) == "function" and root.CreateRedHighlightButton or root.CreateButton
        for _, entry in ipairs(ending) do add(root, red, entry) end
    end
end







function Menus.OpenRowMenu(owner, spec)
    local Look = FGPS.UI.Look
    if not (Look and Look.TomeHas and Look.TomeHas("global", "MenuUtil")) then
        if Look and Look.NoteOnce then
            Look.NoteOnce("tome:rowmenu", "Tome: no MenuUtil in this client; a right-click on a row opens no menu")
        end
        return nil
    end
    if type(MenuUtil) ~= "table" or type(MenuUtil.CreateContextMenu) ~= "function" then return nil end
    if type(spec) ~= "table" then return nil end
    if GameTooltip and owner and GameTooltip.IsOwned and GameTooltip:IsOwned(owner) then GameTooltip:Hide() end


    local ok, menu = pcall(MenuUtil.CreateContextMenu, owner, rowMenuGenerator(spec))
    if ok then return menu end
    if not Menus.rowMenuFailed then
        Menus.rowMenuFailed = true
        if FGPS.Log then FGPS.Log:Error("A row's menu failed to open: %s", tostring(menu)) end
    end
    return nil
end









function Menus.RouteTooltip(onLine)
    local Navigator = FGPS.Navigator
    local Guide = FGPS.UI.Guide
    local model = Guide and type(Guide.model) == "table" and Guide.model or nil
    local unknown = model and tonumber(model.unknownQuest) or nil
    local number = unknown and format(L["Quest %d"], unknown) or nil
    if onLine and routeStopped() then
        return { title = L["Route"], line = number, hint = L["Click to bring the route back"] }
    end
    local tip = { title = L["Route"], line = number, hint = L["Click for options. Drag to move."] }
    if Navigator and Navigator.GetState and Navigator:GetState() == "paused" and Navigator.pauseReason ~= nil then
        tip.line = number and (number .. L[" - "] .. L["Resume tries again."]) or L["Resume tries again."]
    end
    return tip
end



local function showRouteTooltip(button)
    local Look = FGPS.UI.Look
    if not (Look and Look.Tooltip) then return end
    local RouteBlock = FGPS.UI.RouteBlock
    local frame = RouteBlock and RouteBlock.frame or nil
    local tip = Menus.RouteTooltip(frame ~= nil and button == frame.Body)
    Look.Tooltip(button, tip.title, tip.line, tip.hint, "ANCHOR_LEFT")
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
    { "inn", "Inn", "Inn" }, { "bank", "Bank", "Bank" }, { "flightmaster", "Flight Master", "Flight master" },
    { "repair", "Repair", "Repair vendor" }, { "mailbox", "Mailbox", "Mailbox" }, { "vendor", "Vendor", "Vendor" },
    { "trainer", "Class Trainer", "Class trainer" }, { "stable", "Stable Master", "Stable master" },
}





local NAVIGATOR_ENDS = { quest = true, resurrected = true }





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




    local Nav = FGPS.Navigator


    local pick = { previewed = Nav and Nav.GetState and Nav:GetState() == "previewing" and Nav:GetRoute() or nil }
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
    local nearest = root:CreateButton(L["Go to Nearest"])
    if type(nearest) ~= "table" or type(nearest.CreateButton) ~= "function" then return end
    for _, service in ipairs(Menus.NEAREST) do
        nearest:CreateButton(L[service[2]], function() Menus.GoToNearest(service[1], L[service[2]]) end)
    end

    local Look = FGPS.UI.Look
    if Look and Look.NoteOnce then Look.NoteOnce("tracking", "Tracking menu: entry added") end
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





    FGPS.Events:Register("DESTINATION_SET", function(_, _, askedBy)
        if askedBy ~= "navigator" then Menus.nearestPick = nil end
        Menus.noPlaceSaid = nil
    end, self)
    FGPS.Events:Register("NAV_CANCELLED", function(_, reason)
        if not NAVIGATOR_ENDS[reason] then Menus.nearestPick = nil end
    end, self)


    FGPS.Events:Register("NAV_STATE", function(_, new, old)
        local pick = Menus.nearestPick
        if pick and pick.previewed and new == "active" and old == "previewing"
            and FGPS.Navigator:GetRoute() == pick.previewed then
            Menus.nearestPick = nil
        end
    end, self)
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
