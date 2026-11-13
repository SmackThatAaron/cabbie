












local ADDON_NAME, FGPS = ...

local L = FGPS.L
local type, tonumber, tostring, ipairs, pcall, rawget, format =
    type, tonumber, tostring, ipairs, pcall, rawget, string.format

local QuestClicks = { hooks = {}, handledMapClickAt = nil }
FGPS.UI.QuestClicks = QuestClicks


local hookedFrames = setmetatable({}, { __mode = "k" })
local lastQuestieClickID
local lastQuestieClickAt
local restoringWatch = false

local function nowTime()
    return GetTime and GetTime() or 0
end

local function markMapClick()
    QuestClicks.handledMapClickAt = nowTime()
end



function QuestClicks.ConsumeMapClick()
    local at = QuestClicks.handledMapClickAt
    if at == nil then return false end
    QuestClicks.handledMapClickAt = nil
    return at == nowTime()
end

local function chatEditOpen()
    local util = rawget(_G, "ChatFrameUtil")
    if type(util) == "table" and type(util.GetActiveWindow) == "function" then
        local ok, win = pcall(util.GetActiveWindow)
        if ok and win then return true end
    end
    local getEdit = rawget(_G, "ChatEdit_GetActiveWindow")
    if type(getEdit) == "function" then
        local ok, win = pcall(getEdit)
        if ok and win then return true end
    end
    local edit = rawget(_G, "ChatFrame1EditBox")
    if type(edit) == "table" and type(edit.HasFocus) == "function" then
        local ok, focus = pcall(edit.HasFocus, edit)
        if ok and focus then return true end
    end
    return false
end

local function isShiftOnly()
    if not (IsShiftKeyDown ~= nil and IsShiftKeyDown() == true) then return false end
    if (IsControlKeyDown and IsControlKeyDown()) or (IsAltKeyDown and IsAltKeyDown()) then return false end
    return true
end



function QuestClicks.IsGoClick(mouseButton)
    if mouseButton ~= "LeftButton" then return false end
    if IsAltKeyDown and IsAltKeyDown() then return false end
    local shift = IsShiftKeyDown ~= nil and IsShiftKeyDown() == true
    local ctrl = IsControlKeyDown ~= nil and IsControlKeyDown() == true
    if shift == ctrl then return false end
    local chatLink = IsModifiedClick and IsModifiedClick("CHATLINK") or false
    if chatEditOpen() and (shift or chatLink) then return false end
    if ctrl and chatLink then return false end
    return true
end

local function count(field, source)
    local QuestSearch = FGPS.QuestSearch
    local stats = QuestSearch and QuestSearch.stats
    if type(stats) ~= "table" then return end
    if type(stats[field]) ~= "table" then stats[field] = {} end
    stats[field][source] = (stats[field][source] or 0) + 1
end

local function inLog(questID)
    local C = C_QuestLog
    if not C then return false end
    if C.IsOnQuest then
        local ok, on = pcall(C.IsOnQuest, questID)
        if ok and on == true then return true end
    end
    if not C.GetLogIndexForQuestID then return false end
    local ok, index = pcall(C.GetLogIndexForQuestID, questID)
    return ok and type(index) == "number" and index > 0
end

local function questieModule(name)
    local loader = rawget(_G, "QuestieLoader")
    local modules = type(loader) == "table" and rawget(loader, "_modules") or nil
    local mod = type(modules) == "table" and rawget(modules, name) or nil
    return type(mod) == "table" and mod or nil
end




local function restoreQuestWatch(questID)
    if restoringWatch or not isShiftOnly() or not inLog(questID) then return end
    restoringWatch = true
    local C = C_QuestLog
    if C and C.AddQuestWatch then
        local watched = false
        if C.GetQuestWatchType then
            local ok, wt = pcall(C.GetQuestWatchType, questID)
            watched = ok and wt ~= nil
        end
        if not watched then pcall(C.AddQuestWatch, questID) end
    end
    local q = rawget(_G, "Questie")
    local db = type(q) == "table" and rawget(q, "db") or nil
    local char = type(db) == "table" and rawget(db, "char") or nil
    if type(char) == "table" then
        local autoUntracked = rawget(char, "AutoUntrackedQuests")
        if type(autoUntracked) == "table" and autoUntracked[questID] then autoUntracked[questID] = nil end
        local tracked = rawget(char, "TrackedQuests")
        if type(tracked) == "table" and tracked[questID] == false then tracked[questID] = true end
    end
    local tracker = questieModule("QuestieTracker")
    if tracker then
        if type(tracker.TrackQuestId) == "function" then
            pcall(tracker.TrackQuestId, tracker, questID)
        elseif type(tracker.Update) == "function" then
            pcall(tracker.Update, tracker)
        end
    end
    restoringWatch = false
end

local function destFromSpot(questID, spot)
    local QuestSearch, Coords = FGPS.QuestSearch, FGPS.Coords
    if type(spot) ~= "table" or not (QuestSearch and QuestSearch.Dest) then return nil end
    local inst, x, y, map = spot.inst, spot.x, spot.y, spot.map
    if not inst and type(map) == "number" and type(spot.mx) == "number" and type(spot.my) == "number"
        and Coords and Coords.MapToWorld then
        local ok, wi, wx, wy = pcall(Coords.MapToWorld, map, spot.mx, spot.my)
        if ok and wi then inst, x, y = wi, wx, wy end
    end
    if not inst and type(spot.areaID) == "number" and type(spot.ax) == "number" and type(spot.ay) == "number" then
        local Services = FGPS.ServiceSearch
        if Services and Services.QuestieSpots then
            local ok, spots = pcall(Services.QuestieSpots, { [spot.areaID] = { { spot.ax, spot.ay } } })
            local first = ok and type(spots) == "table" and spots[1] or nil
            if first then inst, x, y, map = first.inst, first.x, first.y, first.map end
        end
    end
    if not (inst and type(x) == "number" and type(y) == "number") then return nil end
    local text = spot.text
    if text == nil then text = L["the spot your map marks"] end
    return QuestSearch.Dest(questID, {
        inst = inst, x = x, y = y, map = map,
        role = spot.role or "map", text = text,
    }, spot.questName)
end

local function pickupDest(questID, questName)
    local QuestSearch = FGPS.QuestSearch
    if not (QuestSearch and QuestSearch.Places and QuestSearch.Dest) then return nil end
    local ok, places = pcall(QuestSearch.Places, questID, { pickup = true })
    if not ok or type(places) ~= "table" then return nil end
    for _, p in ipairs(places) do
        if p.role == "pickup" then return QuestSearch.Dest(questID, p, questName) end
    end
    return nil
end





function QuestClicks.Go(questID, source, opts)
    local QuestSearch = FGPS.QuestSearch
    questID = tonumber(questID)
    if not (questID and questID > 0 and QuestSearch and QuestSearch.Next) then return false end
    source = source or "log"
    count("clicks", source)

    local spot = type(opts) == "table" and opts.spot or nil
    local preferSpot = type(opts) == "table" and opts.preferSpot == true
    local allowPickup = type(opts) == "table" and opts.allowPickup == true
    local dest

    if preferSpot and spot then
        local ok, built = pcall(destFromSpot, questID, spot)
        if ok then dest = built end
    end

    if not dest then
        local stats = QuestSearch.stats
        local nothing = type(stats) == "table" and type(stats.nothing) == "table" and stats.nothing or nil
        local beforeNotInLog = nothing and nothing.not_in_log
        local beforeNoPlace = nothing and nothing.no_place
        local ok, nextDest, why = pcall(QuestSearch.Next, questID)
        if not ok then
            FGPS.Log:Error("The quest's place could not be worked out: %s", tostring(nextDest))
            return false
        end
        dest = nextDest
        if not dest and allowPickup and why == "not_in_log" then
            dest = pickupDest(questID, spot and spot.questName)
        end
        if not dest and not preferSpot and spot then
            local okSpot, built = pcall(destFromSpot, questID, spot)
            if okSpot then dest = built end
        end

        if dest and nothing then
            nothing.not_in_log = beforeNotInLog
            nothing.no_place = beforeNoPlace
        end
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

local function hookScriptOnce(frame, script, fn)
    if type(frame) ~= "table" or hookedFrames[frame] or type(frame.HookScript) ~= "function" then return end
    local tag = hookedFrames[frame]
    if tag then return end
    local ok = pcall(frame.HookScript, frame, script, fn)
    if ok then hookedFrames[frame] = true end
end

local function questIDFromArgs(a, b)
    local n = tonumber(a)
    if n and n > 0 then return n end
    n = tonumber(b)
    if n and n > 0 then return n end
    if type(a) == "table" then
        n = tonumber(a.Id or a.questID or a.id)
        if n and n > 0 then return n end
    end
    if type(b) == "table" then
        n = tonumber(b.Id or b.questID or b.id)
        if n and n > 0 then return n end
    end
    return nil
end

local function pinMapID(pin)
    if type(pin) == "table" then
        if type(pin.mapID) == "number" and pin.mapID > 0 then return pin.mapID end
        if type(pin.GetMap) == "function" then
            local ok, m = pcall(pin.GetMap, pin)
            if ok and type(m) == "table" and type(m.GetMapID) == "function" then
                local okID, id = pcall(m.GetMapID, m)
                if okID and type(id) == "number" and id > 0 then return id end
            end
        end
    end
    local wmf = rawget(_G, "WorldMapFrame")
    if type(wmf) == "table" and type(wmf.GetMapID) == "function" then
        local ok, id = pcall(wmf.GetMapID, wmf)
        if ok and type(id) == "number" and id > 0 then return id end
    end
    return nil
end

local function blizzPinSpot(pin, role, text, questName)
    if type(pin) ~= "table" then return nil end
    local mx = type(pin.normalizedX) == "number" and pin.normalizedX or (type(pin.x) == "number" and pin.x or nil)
    local my = type(pin.normalizedY) == "number" and pin.normalizedY or (type(pin.y) == "number" and pin.y or nil)
    local mapID = pinMapID(pin)
    if not (mapID and mx and my) then
        if questName then return { role = role, text = text, questName = questName } end
        return nil
    end
    return { map = mapID, mx = mx, my = my, role = role, text = text, questName = questName }
end

local function poiButtonQuestID(button)
    if type(button) ~= "table" then return nil end
    if type(button.GetQuestID) == "function" then
        local ok, id = pcall(button.GetQuestID, button)
        if ok and tonumber(id) then return tonumber(id) end
    end
    return tonumber(button.questID)
end

local function isMapCanvasPin(frame)
    if type(frame) ~= "table" then return false end
    if type(frame.GetMap) == "function" then
        local ok, m = pcall(frame.GetMap, frame)
        if ok and m ~= nil then return true end
    end
    return type(frame.pinTemplate) == "string"
end

local function handlePOIButton(button, mouseButton)
    if not QuestClicks.IsGoClick(mouseButton) then return end
    local questID = poiButtonQuestID(button)
    if not questID then return end
    restoreQuestWatch(questID)
    if isMapCanvasPin(button) then
        markMapClick()
        QuestClicks.Go(questID, "map", { spot = blizzPinSpot(button, "map") })
    else
        local parent = type(button.GetParent) == "function" and button:GetParent() or button.parent
        local isLog = type(parent) == "table" and parent.questLogIndex ~= nil
        QuestClicks.Go(questID, isLog and "log" or "tracker")
    end
end

local function handleOfferPin(pin, mouseButton)
    if not QuestClicks.IsGoClick(mouseButton) or type(pin) ~= "table" then return end
    local questID = tonumber(pin.questID)
    if not questID then return end
    markMapClick()
    local questName = type(pin.questName) == "string" and pin.questName ~= "" and pin.questName or nil
    local giver = type(pin.questGiverName) == "string" and pin.questGiverName ~= "" and pin.questGiverName or nil
    local text = giver and format(L["Pick up from %s"], giver) or format(L["Pick up from %s"], L["the quest giver"])
    QuestClicks.Go(questID, "map", {
        spot = blizzPinSpot(pin, "pickup", text, questName),
        preferSpot = true,
        allowPickup = true,
    })
end


local function handleQuestieIcon(icon, mouseButton)
    if not QuestClicks.IsGoClick(mouseButton) or type(icon) ~= "table" then return end
    local data = rawget(icon, "data")
    if type(data) ~= "table" then return end
    local qd = type(data.QuestData) == "table" and data.QuestData or nil
    local questID = tonumber((qd and qd.Id) or data.QuestId or data.Id)
    if not (questID and questID > 0) then return end
    markMapClick()

    local parent = type(icon.GetParent) == "function" and icon:GetParent() or nil
    local mapID = pinMapID(parent) or tonumber(icon.UiMapID)
    local mx = type(parent) == "table" and type(parent.normalizedX) == "number" and parent.normalizedX or nil
    local my = type(parent) == "table" and type(parent.normalizedY) == "number" and parent.normalizedY or nil
    if not (mx and my) and type(icon.UiMapID) == "number" and type(icon.x) == "number" and type(icon.y) == "number" then
        mapID = icon.UiMapID
        mx = icon.x > 1 and icon.x / 100 or icon.x
        my = icon.y > 1 and icon.y / 100 or icon.y
    end
    local areaID = tonumber(icon.AreaID or data.AreaID or data.zoneID)
    local ax = type(icon.x) == "number" and (icon.x <= 1 and icon.x * 100 or icon.x) or nil
    local ay = type(icon.y) == "number" and (icon.y <= 1 and icon.y * 100 or icon.y) or nil

    local kind = data.Type
    local role = "objective"
    local text
    local npcOrObjName = type(data.Name) == "string" and data.Name ~= "" and data.Name or nil
    local objDesc = type(data.ObjectiveData) == "table" and type(data.ObjectiveData.Description) == "string"
        and data.ObjectiveData.Description ~= "" and data.ObjectiveData.Description or nil
    if kind == "available" then
        role = "pickup"
        text = format(L["Pick up from %s"], npcOrObjName or L["the quest giver"])
    elseif kind == "complete" then
        role = "turnin"
        text = format(L["Turn in to %s"], npcOrObjName or L["the quest giver"])
    else
        text = objDesc or npcOrObjName or L["the spot your map marks"]
    end
    local questName = qd and type(qd.name) == "string" and qd.name ~= "" and qd.name or nil

    QuestClicks.Go(questID, "map", {
        spot = {
            map = mapID, mx = mx, my = my,
            areaID = areaID, ax = ax, ay = ay,
            role = role, text = text, questName = questName,
        },
        preferSpot = true,
        allowPickup = true,
    })
end

local function hookQuestieIcon(icon)
    if type(icon) ~= "table" or hookedFrames[icon] or type(icon.HookScript) ~= "function" then return end
    hookScriptOnce(icon, "OnClick", function(self, mouseButton)
        handleQuestieIcon(self, mouseButton)
    end)
end

local function hookPOIButtonInstance(button)
    if type(button) ~= "table" or hookedFrames[button] then return end
    local poiMixin = rawget(_G, "POIButtonMixin")
    if QuestClicks.hooks.poiButton and type(poiMixin) == "table" and button.OnClick == poiMixin.OnClick then return end
    if type(hooksecurefunc) == "function" and type(button.OnClick) == "function" then
        if pcall(hooksecurefunc, button, "OnClick", handlePOIButton) then
            hookedFrames[button] = true
        end
        return
    end
    hookScriptOnce(button, "OnClick", handlePOIButton)
end

local function hookMapPin(pin)
    if type(pin) ~= "table" then return end
    local inner = rawget(pin, "icon")
    if type(inner) == "table" then
        hookQuestieIcon(inner)
        return
    end
    if rawget(pin, "data") ~= nil then
        hookQuestieIcon(pin)
        return
    end

    if hookedFrames[pin] then return end
    if pin.GetStyle or pin.GetQuestID then
        hookPOIButtonInstance(pin)
        return
    end
    local offerMixin = rawget(_G, "QuestOfferPinMixin")
    if type(pin.OnMouseClickAction) == "function" then
        if QuestClicks.hooks.offerPin and type(offerMixin) == "table" and pin.OnMouseClickAction == offerMixin.OnMouseClickAction then
            return
        end
        if type(hooksecurefunc) == "function" and pcall(hooksecurefunc, pin, "OnMouseClickAction", handleOfferPin) then
            hookedFrames[pin] = true
        end
    end
end

local function detailQuestID(frame)
    local qmf = rawget(_G, "QuestMapFrame")
    local details = type(qmf) == "table" and qmf.DetailsFrame or nil
    if type(details) == "table" and tonumber(details.questID) and tonumber(details.questID) > 0 then
        if not details.IsShown or details:IsShown() or frame == details then
            return tonumber(details.questID), false
        end
    end
    local popup = rawget(_G, "QuestLogPopupDetailFrame")
    if type(popup) == "table" and tonumber(popup.questID) and tonumber(popup.questID) > 0 then
        if not popup.IsShown or popup:IsShown() or frame == popup then
            return tonumber(popup.questID), false
        end
    end
    local qf = rawget(_G, "QuestFrame")
    local getQuestID = rawget(_G, "GetQuestID")
    if type(qf) == "table" and (not qf.IsShown or qf:IsShown()) and type(getQuestID) == "function" then
        local ok, id = pcall(getQuestID)
        if ok and tonumber(id) and tonumber(id) > 0 then return tonumber(id), true end
    end
    if C_QuestLog and C_QuestLog.GetSelectedQuest then
        local ok, id = pcall(C_QuestLog.GetSelectedQuest)
        if ok and tonumber(id) and tonumber(id) > 0 then return tonumber(id), false end
    end
    return nil, false
end

local function hookDetailSurface(frame)
    if type(frame) ~= "table" or hookedFrames[frame] then return end
    if type(frame.IsObjectType) == "function" then
        local ok, isButton = pcall(frame.IsObjectType, frame, "Button")
        if ok and isButton then
            hookScriptOnce(frame, "OnClick", function(self, mouseButton)
                if not QuestClicks.IsGoClick(mouseButton) then return end
                local id, allowPickup = detailQuestID(self)
                if id then QuestClicks.Go(id, "details", allowPickup and { allowPickup = true } or nil) end
            end)
            return
        end
    end
    hookScriptOnce(frame, "OnMouseUp", function(self, mouseButton, upInside)
        if upInside == false or not QuestClicks.IsGoClick(mouseButton) then return end
        local id, allowPickup = detailQuestID(self)
        if id then QuestClicks.Go(id, "details", allowPickup and { allowPickup = true } or nil) end
    end)
end

local function hookQuestDetailsFrames()
    local qmf = rawget(_G, "QuestMapFrame")
    local details = type(qmf) == "table" and qmf.DetailsFrame or nil
    if type(details) == "table" then
        hookDetailSurface(details)
        hookDetailSurface(details.DestinationMapButton)
        hookDetailSurface(details.WaypointMapButton)
        local sf = details.ScrollFrame
        if type(sf) == "table" then
            hookDetailSurface(sf)
            hookDetailSurface(sf.Contents)
        end
    end
    local popup = rawget(_G, "QuestLogPopupDetailFrame")
    if type(popup) == "table" then
        hookDetailSurface(popup)
        local sf = popup.ScrollFrame
        if type(sf) == "table" then
            hookDetailSurface(sf)
            hookDetailSurface(sf.ScrollChild)
        end
    end
    for _, name in ipairs({ "QuestDetailScrollFrame", "QuestProgressScrollFrame", "QuestRewardScrollFrame" }) do
        hookDetailSurface(rawget(_G, name))
    end
end

local function questieLineQuestID(line)
    if type(line) ~= "table" then return nil end
    local q = rawget(line, "Quest")
    if type(q) == "table" and tonumber(q.Id) then return tonumber(q.Id) end
    if tonumber(q) then return tonumber(q) end
    return tonumber(rawget(line, "questId") or rawget(line, "questID"))
end

local function hookQuestieLine(line)
    if type(line) ~= "table" then return end
    local btn = type(rawget(line, "button")) == "table" and line.button or line
    if hookedFrames[btn] or type(btn.HookScript) ~= "function" then return end
    hookScriptOnce(btn, "OnClick", function(self, mouseButton)
        if not QuestClicks.IsGoClick(mouseButton) then return end
        local questID = questieLineQuestID(self) or questieLineQuestID(line)
        if not questID then return end
        if lastQuestieClickID == questID and lastQuestieClickAt == nowTime() then
            lastQuestieClickID = nil
            lastQuestieClickAt = nil
            return
        end
        lastQuestieClickID = nil
        lastQuestieClickAt = nil
        restoreQuestWatch(questID)
        QuestClicks.Go(questID, "questie")
    end)
end

local function scanQuestieTrackerButtons(root, depth)
    if type(root) ~= "table" or (depth or 0) > 4 or type(root.GetChildren) ~= "function" then return end
    local ok, children = pcall(function() return { root:GetChildren() } end)
    if not ok or type(children) ~= "table" then return end
    for _, child in ipairs(children) do
        if type(child) == "table" then
            if rawget(child, "Quest") ~= nil or rawget(child, "Objective") ~= nil then
                hookQuestieLine(child)
            end
            scanQuestieTrackerButtons(child, (depth or 0) + 1)
        end
    end
end


function QuestClicks.HookAll()

    local function onLogTitle(button, mouseButton)
        if type(button) == "table" and QuestClicks.IsGoClick(mouseButton) then
            local questID = tonumber(button.questID)
            if questID then
                restoreQuestWatch(questID)
                QuestClicks.Go(questID, "log")
            end
        end
    end
    hookGlobal("log", "QuestMapLogTitleButton_OnClick", onLogTitle)
    hookGlobal("classicLog", "QuestLogTitleButton_OnClick", onLogTitle)


    hookQuestDetailsFrames()
    hookGlobal("showDetails", "QuestMapFrame_ShowQuestDetails", function()
        hookQuestDetailsFrames()
    end)
    hookGlobal("questInfo", "QuestInfo_Display", function(_, parentFrame)
        hookQuestDetailsFrames()
        if type(parentFrame) == "table" then
            hookDetailSurface(parentFrame)
            if type(parentFrame.GetParent) == "function" then
                local ok, scroll = pcall(parentFrame.GetParent, parentFrame)
                if ok and type(scroll) == "table" then hookDetailSurface(scroll) end
            end
        end
    end)


    local function onHeader(_, block, mouseButton)
        if type(block) == "table" and QuestClicks.IsGoClick(mouseButton) then
            local questID = tonumber(block.id)
            if questID then
                restoreQuestWatch(questID)
                QuestClicks.Go(questID, "tracker")
            end
        end
    end
    hook("tracker", rawget(_G, "QuestObjectiveTracker"), "OnBlockHeaderClick", onHeader)
    hook("campaign", rawget(_G, "CampaignQuestObjectiveTracker"), "OnBlockHeaderClick", onHeader)
    hook("worldTracker", rawget(_G, "WorldQuestObjectiveTracker"), "OnBlockHeaderClick", onHeader)
    hook("bonusTracker", rawget(_G, "BonusObjectiveTracker"), "OnBlockHeaderClick", onHeader)



    hook("poiButton", rawget(_G, "POIButtonMixin"), "OnClick", handlePOIButton)
    hook("trackerPoi", rawget(_G, "ObjectiveTrackerQuestPOIBlockMixin"), "GetPOIButton", function(block)
        if type(block) == "table" and block.poiButton then hookPOIButtonInstance(block.poiButton) end
    end)
    local qsf = rawget(_G, "QuestScrollFrame")
    if type(qsf) == "table" and type(qsf.Contents) == "table" then
        hook("logPoi", qsf.Contents, "GetButtonForQuest", function(contents, questID)
            if type(contents.FindButtonByQuestID) == "function" then
                local ok, btn = pcall(contents.FindButtonByQuestID, contents, questID)
                if ok and btn then hookPOIButtonInstance(btn) end
            end
        end)
    end
    hook("offerPin", rawget(_G, "QuestOfferPinMixin"), "OnMouseClickAction", handleOfferPin)


    local wmf = rawget(_G, "WorldMapFrame")
    if type(wmf) == "table" then
        hook("acquirePin", wmf, "AcquirePin", function(map, pinTemplate, maybeIcon)
            if type(maybeIcon) == "table" then hookQuestieIcon(maybeIcon) end
            if type(map) == "table" and type(map.EnumeratePinsByTemplate) == "function" and type(pinTemplate) == "string" then
                local ok, iter, state, key = pcall(map.EnumeratePinsByTemplate, map, pinTemplate)
                if ok and type(iter) == "function" then
                    for pin in iter, state, key do hookMapPin(pin) end
                end
            end
        end)
        if type(wmf.ExecuteOnAllPins) == "function" then
            pcall(wmf.ExecuteOnAllPins, wmf, hookMapPin)
        end
    end


    local utils = questieModule("TrackerUtils")
    hook("questie", utils, "SetQuestTomTomTarget", function(a, b)
        local questID = questIDFromArgs(a, b)
        if questID then
            if QuestClicks.IsGoClick("LeftButton") then
                lastQuestieClickID = questID
                lastQuestieClickAt = nowTime()
            end
            QuestClicks.Go(questID, "questie")
        end
    end)

    local qTracker = questieModule("QuestieTracker")
    hook("questieUntrack", qTracker, "UntrackQuestId", function(a, b)
        if restoringWatch or not QuestClicks.IsGoClick("LeftButton") then return end
        local questID = questIDFromArgs(a, b)
        if not questID then return end
        lastQuestieClickID = questID
        lastQuestieClickAt = nowTime()
        restoreQuestWatch(questID)
        QuestClicks.Go(questID, "questie")
    end)
    hook("questieTrackerUpdate", qTracker, "Update", function()
        scanQuestieTrackerButtons(rawget(_G, "Questie_BaseFrame"), 0)
    end)
    scanQuestieTrackerButtons(rawget(_G, "Questie_BaseFrame"), 0)

    local linePool = questieModule("TrackerLinePool")
    if linePool then
        hook("questieLineUpdate", linePool, "UpdateQuestLines", function()
            scanQuestieTrackerButtons(rawget(_G, "Questie_BaseFrame"), 0)
        end)
    end

    local qMap = questieModule("QuestieMap")
    if qMap then
        hook("questieDrawWorld", qMap, "DrawWorldIcon", function()
            local map = rawget(_G, "WorldMapFrame")
            if type(map) == "table" and type(map.ExecuteOnAllPins) == "function" then
                pcall(map.ExecuteOnAllPins, map, hookMapPin)
            end
        end)
    end

    return QuestClicks.hooks
end

function QuestClicks:Init()
    if self.initialised then return end
    self.initialised = true
    QuestClicks.HookAll()
    local Events = FGPS.Events
    local function retry()
        local hooks = QuestClicks.HookAll()
        if hooks.log and hooks.tracker and hooks.acquirePin and hooks.questie and Events.UnregisterWoW then
            Events:UnregisterWoW("ADDON_LOADED", self)
        end
    end
    if Events.RegisterWoW then Events:RegisterWoW("ADDON_LOADED", retry, self) end
    Events:Register("WORLD_ENTERED", retry, self)
end
