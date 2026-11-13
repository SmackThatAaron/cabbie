









































local ADDON_NAME, FGPS = ...

local L = FGPS.L
local type, pairs, ipairs, tostring, tonumber, pcall = type, pairs, ipairs, tostring, tonumber, pcall
local sqrt, abs, floor, min, max, sin, atan2, format = math.sqrt, math.abs, math.floor, math.min, math.max, math.sin, math.atan2, string.format
local PI, TWO_PI = math.pi, 2 * math.pi

local InWorldPin = {
    initialised = false,
    state = {
        route = nil,
        progress = nil,
        navState = "idle",
        inCombat = false,
        set = false,
        saved = nil,
        target = nil,
        targetKey = nil,
        lastSet = nil,
        backedOff = false,
        noticeGiven = false,
        suppressed = false,
        questAtRelease = nil,
        fightMoveAt = nil,
        questMomentAt = nil,
        ignore = 0,
        unavailableMaps = {},
        focusQuest = nil,
        ownQuest = nil,
        lastCallAt = nil,
        lastCallWhat = nil,
        stopped = false,
        placeAskedAt = nil,
        carriedQuest = nil,
        savedAt = nil,
        arrowHidden = false,
    },
}
FGPS.UI.InWorldPin = InWorldPin

local RoadBeacon = {
    frame = nil,
    beacon = nil,
    parts = nil,
    frameFailed = false,
    attached = false,
    pinHidden = false,
    PIN_BACK_SECONDS = 3,
    frameState = {
        reason = nil,
        shown = false,
        clamped = false,
        mode = nil,
        distYards = nil,
        cue = nil,
        fade = 0,
    },
}
InWorldPin.Beacon = RoadBeacon
FGPS.UI.RoadBeacon = RoadBeacon

InWorldPin.MIN_AHEAD_YARDS = 60
InWorldPin.SIGHT_YARDS = 20
InWorldPin.SIGHT_CAP_YARDS = 200
InWorldPin.MOVE_YARDS = 30


InWorldPin.BEACON_SIGHT_YARDS = 8
InWorldPin.BEACON_CAP_YARDS = 60
InWorldPin.BEACON_TURN_YARDS = 75
InWorldPin.BEACON_MOVE_YARDS = 12
InWorldPin.REFRESH_SECONDS = 5
InWorldPin.MATCH_EPSILON = 0.0005
InWorldPin.NOTICE_HOLD = 6




InWorldPin.BLOCKED_WINDOW = 3




InWorldPin.QUEST_QUIET = 0.5




local function now()
    return GetTime and GetTime() or 0
end

local function inFight()
    return InCombatLockdown ~= nil and InCombatLockdown() == true
end


local function focusedQuest()
    if type(C_SuperTrack) ~= "table" or type(C_SuperTrack.GetSuperTrackedQuestID) ~= "function" then return nil end
    local ok, questID = pcall(C_SuperTrack.GetSuperTrackedQuestID)
    if not ok or type(questID) ~= "number" or (issecretvalue ~= nil and issecretvalue(questID) == true) or questID <= 0 then return nil end
    return questID
end

local function beaconMode()
    local db = FGPS.DB
    return db ~= nil and db.settings ~= nil and db.settings.roadBeacon == true
end

local function stockPinMode()
    local db = FGPS.DB
    return not (db and db.settings) or db.settings.inWorldPin == true
end

local function settingsEnabled()
    local db = FGPS.DB
    local s = db and db.settings
    if s and s.inWorldPin ~= true and s.roadBeacon ~= true then return false end
    if FGPS.Perf and FGPS.Perf.guidanceEnabled == false then return false end
    return true
end

local function apiAvailable()
    return type(C_Map) == "table" and type(C_Map.SetUserWaypoint) == "function"
        and type(C_SuperTrack) == "table" and type(C_SuperTrack.SetSuperTrackedUserWaypoint) == "function"
end

function InWorldPin.IsEnabled()
    return not InWorldPin.state.stopped and settingsEnabled() and apiAvailable()
end

function InWorldPin.IsActive()
    return InWorldPin.state.set
end

function InWorldPin.GetTarget()
    return InWorldPin.state.target
end

local function combatPolicy()
    local nav = FGPS.Navigator
    if nav and nav.CombatPolicy then
        local ok, policy = pcall(nav.CombatPolicy, nav)
        if ok and type(policy) == "string" then return policy end
    end
    local db = FGPS.DB
    return db and db.settings and db.settings.combatMode or "visuals_only"
end

local function distance(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    return sqrt(dx * dx + dy * dy)
end

local function canSetOnMap(uiMapID)
    if type(C_Map.CanSetUserWaypointOnMap) ~= "function" then return false end
    local ok, can = pcall(C_Map.CanSetUserWaypointOnMap, uiMapID)
    return ok and can == true
end

local function makePoint(uiMapID, mx, my)
    if type(UiMapPoint) == "table" and type(UiMapPoint.CreateFromCoordinates) == "function" then
        local ok, point = pcall(UiMapPoint.CreateFromCoordinates, uiMapID, mx, my, 0)
        if ok and point then return point end
    end
    local position = CreateVector2D and CreateVector2D(mx, my) or { x = mx, y = my }
    return { uiMapID = uiMapID, position = position, z = 0 }
end

local function pointXY(point)
    if type(point) ~= "table" then return nil end
    local pos = point.position
    if type(pos) == "table" then
        if pos.GetXY then return pos:GetXY() end
        return pos.x, pos.y
    end
    return point.x, point.y
end

local function copyPoint(point)
    local x, y = pointXY(point)
    if not point or not x then return nil end
    return { uiMapID = point.uiMapID, x = x, y = y, z = point.z }
end

local function waypointMatches(point, target)
    if not point or not target then return false end
    if point.uiMapID ~= target.uiMapID then return false end
    local x, y = pointXY(point)
    if not x or not y then return false end
    return abs(x - target.x) <= InWorldPin.MATCH_EPSILON and abs(y - target.y) <= InWorldPin.MATCH_EPSILON
end




local function charData()
    local db = FGPS.DB
    if db and type(db.char) == "table" then return db.char end
    return nil
end


function InWorldPin.Record()
    local char = charData()
    local record
    if char then record = char.inWorldPin else record = InWorldPin.volatileRecord end
    if type(record) == "table" and record.uiMapID and record.x and record.y then return record end
    return nil
end




local function remember(uiMapID, x, y)
    local record = { uiMapID = uiMapID, x = x, y = y, saved = InWorldPin.state.saved }
    local char = charData()
    if char then char.inWorldPin = record else InWorldPin.volatileRecord = record end
end

local function forget()
    local char = charData()
    if char then char.inWorldPin = nil end
    InWorldPin.volatileRecord = nil
end

local function currentWaypoint()
    if type(C_Map) ~= "table" or type(C_Map.GetUserWaypoint) ~= "function" then return nil end
    local ok, point = pcall(C_Map.GetUserWaypoint)
    if ok then return point end
    return nil
end



local function resolveMap(inst, x, y)
    local coords = FGPS.Coords
    if coords and coords.WorldToMap then
        local ok, uiMapID, mx, my = pcall(coords.WorldToMap, inst, x, y)
        if ok and uiMapID and mx and my then return uiMapID, mx, my end
    end
    local hbd = coords and coords.HBD
    if not hbd and LibStub then
        local ok, lib = pcall(LibStub, "HereBeDragons-2.0", true)
        if ok then hbd = lib end
    end
    if hbd and hbd.GetZoneCoordinatesFromWorld and hbd.GetPlayerWorldPosition and C_Map.GetBestMapForUnit then
        local _, _, playerInst = hbd:GetPlayerWorldPosition()
        if playerInst ~= inst then return nil end
        local candidate = C_Map.GetBestMapForUnit("player")
        local guard = 0
        while candidate and guard < 4 do
            local mx, my = hbd:GetZoneCoordinatesFromWorld(x, y, candidate, false)
            if mx and my then return candidate, mx, my end
            local info = C_Map.GetMapInfo and C_Map.GetMapInfo(candidate)
            candidate = info and info.parentMapID
            guard = guard + 1
        end
    end
    return nil
end
InWorldPin.ResolveMap = resolveMap






local NO_WAY_KINDS = { hearth = true, spell = true, portal = true, elevator = true }
local TURN_STEP_KINDS = {
    turn_slight_left = true, turn_left = true, turn_sharp_left = true,
    turn_slight_right = true, turn_right = true, turn_sharp_right = true,
    uturn = true, ramp = true, enter = true,
}


local function offLine(x, y, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len2 = dx * dx + dy * dy
    local t = 0
    if len2 > 0 then
        t = ((x - ax) * dx + (y - ay) * dy) / len2
        if t < 0 then t = 0 elseif t > 1 then t = 1 end
    end
    return distance(x, y, ax + t * dx, ay + t * dy)
end




local passed = {}


local function inSight(pos, count, x, y, sight)
    sight = sight or InWorldPin.SIGHT_YARDS
    for i = 1, count do
        local p = passed[i]
        if offLine(p.x, p.y, pos.x, pos.y, x, y) > sight then return false end
    end
    return true
end






local function sightTarget(route, progress, pos, useBeacon)
    local legs = route.legs
    local li = progress.legIndex or 1
    local sight = useBeacon and InWorldPin.BEACON_SIGHT_YARDS or InWorldPin.SIGHT_YARDS
    local cap = useBeacon and InWorldPin.BEACON_CAP_YARDS or InWorldPin.SIGHT_CAP_YARDS
    local turnCap = useBeacon and InWorldPin.BEACON_TURN_YARDS or nil
    local step = useBeacon and progress.currentStep or nil
    local turnPoint = (type(step) == "table" and step.legIndex == li and TURN_STEP_KINDS[step.kind]
        and type(step.pointIndex) == "number") and step.pointIndex or nil
    local count = 0
    local bestX, bestY, bestPoint
    local along, cx, cy = 0, pos.x, pos.y
    for l = li, #legs do
        local leg = legs[l]
        if type(leg) ~= "table" or (leg.kind ~= nil and leg.kind ~= "walk") then break end
        if leg.inst ~= nil and pos.inst ~= nil and leg.inst ~= pos.inst then break end
        local points = leg.points or {}
        local startP = (l == li) and (progress.pointIndex or 1) or 1
        if l == li and type(progress.alongYards) == "number" and FGPS.Route and FGPS.Route.Cumulative and #points >= 2 then




            local cum = FGPS.Route.Cumulative(leg)
            local walked, n = progress.alongYards, #points
            local k = startP - 1
            if k > n then k = n end
            if k >= 2 and cum[k] > walked then
                local lo, hi = 2, k
                while lo < hi do
                    local mid = floor((lo + hi) / 2)
                    if cum[mid] > walked then hi = mid else lo = mid + 1 end
                end
                startP = lo
            elseif startP > n + 1 then
                startP = n + 1
            end
        end
        for p = startP, #points do
            local pt = points[p]
            if type(pt) == "table" and pt.x and pt.y then
                local seg = distance(cx, cy, pt.x, pt.y)
                if l == li and turnPoint and p == turnPoint and along + seg <= turnCap then
                    if inSight(pos, count, pt.x, pt.y, sight) then
                        return pt.x, pt.y, step, false, "step"
                    end
                    return bestX, bestY, bestPoint
                end
                if along + seg >= cap then
                    local u = (cap - along) / seg
                    local x, y = cx + (pt.x - cx) * u, cy + (pt.y - cy) * u
                    if inSight(pos, count, x, y, sight) then return x, y, nil end
                    return bestX, bestY, bestPoint
                end
                if not inSight(pos, count, pt.x, pt.y, sight) then return bestX, bestY, bestPoint end
                bestX, bestY, bestPoint = pt.x, pt.y, pt
                count = count + 1
                passed[count] = pt
                along, cx, cy = along + seg, pt.x, pt.y
            end
        end
        local nextLeg = legs[l + 1]
        if not nextLeg or (nextLeg.stopIndex or 1) ~= (leg.stopIndex or 1) then break end
    end

    return bestX, bestY, bestPoint, bestPoint ~= nil
end










function InWorldPin.SelectTarget(route, progress, beaconOverride)
    if type(route) ~= "table" or type(progress) ~= "table" then return nil end
    local pos = progress.pos
    if type(pos) ~= "table" or not pos.x or not pos.y then return nil end
    local minAhead = InWorldPin.MIN_AHEAD_YARDS
    local inst = pos.inst
    local useBeacon = beaconOverride
    if useBeacon == nil then useBeacon = beaconMode() end

    local current = type(route.legs) == "table" and route.legs[progress.legIndex or 1] or nil
    if type(current) == "table" then
        if NO_WAY_KINDS[current.kind] then return nil end
        if (current.kind == nil or current.kind == "walk") and (current.inst == nil or inst == nil or current.inst == inst) then
            local x, y, point, ends, hitKind = sightTarget(route, progress, pos, useBeacon)
            if x then return inst, x, y, hitKind or (ends and "stop" or "point"), point end
        end
    end

    local steps = route.steps
    if type(steps) == "table" and #steps > 0 then
        local startIndex
        if progress.currentStep and progress.currentStep.index then
            startIndex = progress.currentStep.index
        elseif progress.nextStep and progress.nextStep.index then
            startIndex = progress.nextStep.index
        else
            startIndex = 1
        end
        local fallback
        for i = startIndex, #steps do
            local step = steps[i]
            if type(step) == "table" and step.x and step.y then
                if step.inst ~= nil and inst ~= nil and step.inst ~= inst then break end
                if distance(pos.x, pos.y, step.x, step.y) >= minAhead then
                    return inst, step.x, step.y, "step", step
                end
                fallback = step
            end
        end
        if fallback then return inst, fallback.x, fallback.y, "step", fallback end
    end

    local legs = route.legs
    if type(legs) == "table" then
        local legIndex = progress.legIndex or 1
        local pointIndex = progress.pointIndex or 1
        local last
        for l = legIndex, #legs do
            local leg = legs[l]
            if type(leg) ~= "table" then break end
            local points = leg.points or {}

            local first = (l == legIndex) and pointIndex or 1
            local lastIndex = #points




            if leg.toInst ~= nil and leg.toInst ~= leg.inst and inst ~= nil then
                local split = FGPS.Transport.DepartureCount(leg)
                if inst == leg.inst then
                    if split < lastIndex then lastIndex = split end
                elseif inst == leg.toInst then
                    if first < split + 1 then first = split + 1 end
                else
                    break
                end
            elseif leg.inst ~= nil and inst ~= nil and leg.inst ~= inst then
                break
            end
            for p = first, lastIndex do
                local pt = points[p]
                if type(pt) == "table" and pt.x and pt.y then
                    if distance(pos.x, pos.y, pt.x, pt.y) >= minAhead then
                        return inst, pt.x, pt.y, "point", pt
                    end
                    last = pt
                end
            end
        end
        if last then return inst, last.x, last.y, "point", last end
    end

    local stops = route.stops
    if type(stops) == "table" then
        for i = #stops, 1, -1 do
            local dest = stops[i] and stops[i].dest
            if type(dest) == "table" and dest.x and dest.y and (dest.inst == nil or inst == nil or dest.inst == inst) then
                return inst, dest.x, dest.y, "stop", dest
            end
        end
    end
    return nil
end




function InWorldPin.SaveCurrent()
    local carried = InWorldPin.state.carriedQuest
    InWorldPin.state.carriedQuest = nil


    local record = InWorldPin.Record()
    local point = currentWaypoint()
    local ours = point ~= nil and waypointMatches(point, record)
    if ours and type(record.saved) == "table" then
        InWorldPin.state.saved = record.saved
        return record.saved
    end
    local saved = { questID = nil, waypoint = nil, trackingWaypoint = false }
    if type(C_SuperTrack.GetSuperTrackedQuestID) == "function" then
        local ok, questID = pcall(C_SuperTrack.GetSuperTrackedQuestID)
        if ok and type(questID) == "number" and questID ~= 0 then saved.questID = questID end
    end




    if point and not ours then saved.waypoint = copyPoint(point) end
    if not ours and type(C_SuperTrack.IsSuperTrackingUserWaypoint) == "function" then
        local ok, tracking = pcall(C_SuperTrack.IsSuperTrackingUserWaypoint)
        saved.trackingWaypoint = ok and tracking == true
    end

    if carried and not saved.questID then saved.questID, saved.questTaken = carried, true end
    InWorldPin.state.saved, InWorldPin.state.savedAt = saved, now()
    return saved
end





local function withIgnoredEvents(what, fn, ...)
    local st = InWorldPin.state
    if st.stopped then return false end
    st.lastCallAt, st.lastCallWhat = now(), what
    st.ignore = st.ignore + 1
    local ok, a, b = pcall(fn, ...)
    st.ignore = st.ignore - 1
    if not ok and FGPS.Log then FGPS.Log:Error("In-world pin API call failed: %s", tostring(a)) end
    return ok, a, b
end





local function questShownOverPin()
    if not focusedQuest() or type(C_SuperTrack.GetHighestPrioritySuperTrackingType) ~= "function"
        or not (Enum and Enum.SuperTrackingType) then
        return false
    end
    local ok, kind = pcall(C_SuperTrack.GetHighestPrioritySuperTrackingType)
    return ok and kind == Enum.SuperTrackingType.Quest
end






function InWorldPin.Place(uiMapID, mx, my)
    local placed = false
    local st = InWorldPin.state
    withIgnoredEvents("placing the pin", function()
        local had = focusedQuest()
        local wasSet = C_Map.SetUserWaypoint(makePoint(uiMapID, mx, my))
        placed = wasSet ~= false
        if placed then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
            if questShownOverPin() and type(C_SuperTrack.SetSuperTrackedQuestID) == "function" then
                C_SuperTrack.SetSuperTrackedQuestID(0)
            end
            if had and focusedQuest() ~= had and st.saved then st.saved.questID, st.saved.questTaken = had, true end
        end
    end)
    if placed then remember(uiMapID, mx, my) end
    return placed
end



local function clearIfOurs(ours)
    if not ours or not apiAvailable() or type(C_Map.ClearUserWaypoint) ~= "function" then return false end
    if not waypointMatches(currentWaypoint(), ours) then return false end
    withIgnoredEvents("clearing the pin", function()

        local okTracking, tracking = pcall(C_SuperTrack.IsSuperTrackingUserWaypoint or function() return false end)
        if okTracking and tracking == true then C_SuperTrack.SetSuperTrackedUserWaypoint(false) end
        C_Map.ClearUserWaypoint()
    end)
    return true
end



local function stillInLog(questID)
    if type(C_QuestLog) ~= "table" or type(C_QuestLog.IsOnQuest) ~= "function" then return true end
    local ok, on = pcall(C_QuestLog.IsOnQuest, questID)
    if not ok or (issecretvalue ~= nil and issecretvalue(on) == true) then return true end
    return on ~= false
end








local function giveBack(saved)
    local st = InWorldPin.state
    withIgnoredEvents("giving back the player's tracking", function()
        if saved.waypoint and saved.waypoint.uiMapID then
            C_Map.SetUserWaypoint(makePoint(saved.waypoint.uiMapID, saved.waypoint.x, saved.waypoint.y))
            C_SuperTrack.SetSuperTrackedUserWaypoint(saved.trackingWaypoint and true or false)
        else
            C_SuperTrack.SetSuperTrackedUserWaypoint(false)
            if type(C_Map.ClearUserWaypoint) == "function" then C_Map.ClearUserWaypoint() end
        end


        if saved.questID and (saved.questTaken or not saved.trackingWaypoint)
            and type(C_SuperTrack.SetSuperTrackedQuestID) == "function" and stillInLog(saved.questID) then


            st.ownQuest = saved.questID
            C_SuperTrack.SetSuperTrackedQuestID(saved.questID)
        end
    end)
end







function InWorldPin.ClearLeftover(final)
    local record = InWorldPin.Record()
    if not record then return false end
    local st = InWorldPin.state
    if st.set or st.route or (st.navState ~= "idle" and st.navState ~= "arrived") then return false end
    local nav = FGPS.Navigator
    if nav and nav.GetState then
        local ok, navState = pcall(nav.GetState, nav)
        if ok and navState ~= nil and navState ~= "idle" and navState ~= "arrived" then return false end
    end
    local removed = clearIfOurs(record)
    if removed and type(record.saved) == "table" then giveBack(record.saved) end
    if removed or final then forget() end
    if removed and FGPS.Log then FGPS.Log:Info("Removed a map pin left behind by an earlier route") end
    return removed
end


function InWorldPin.IsOurTrackingIntact()
    local st = InWorldPin.state
    if not st.target then return false end
    if st.suppressed then return true end
    if type(C_SuperTrack.IsSuperTrackingUserWaypoint) == "function" then
        local ok, tracking = pcall(C_SuperTrack.IsSuperTrackingUserWaypoint)
        if not ok or tracking ~= true then return false end
    end
    if type(C_SuperTrack.GetHighestPrioritySuperTrackingType) == "function" and Enum and Enum.SuperTrackingType then
        local ok, kind = pcall(C_SuperTrack.GetHighestPrioritySuperTrackingType)


        local types = Enum.SuperTrackingType
        if ok and kind ~= nil and kind ~= types.UserWaypoint and kind ~= types.Corpse then return false end
    end
    if type(C_Map.GetUserWaypoint) == "function" then
        local ok, point = pcall(C_Map.GetUserWaypoint)
        if not ok or not waypointMatches(point, st.target) then return false end
    end
    return true
end












local function turnArrowOn()
    local db = FGPS.DB
    return not (db and db.Get) or db:Get("callout.enabled") ~= false
end

local function corpseShown()
    if type(C_SuperTrack.GetHighestPrioritySuperTrackingType) ~= "function" or not (Enum and Enum.SuperTrackingType) then
        return false
    end
    local ok, kind = pcall(C_SuperTrack.GetHighestPrioritySuperTrackingType)
    return ok and kind == Enum.SuperTrackingType.Corpse
end

local function syncGameArrow()
    local st = InWorldPin.state
    local frame = SuperTrackedFrame
    local arrow = type(frame) == "table" and frame.Arrow or nil
    if type(arrow) ~= "table" or type(arrow.SetAlpha) ~= "function" then return end



    local hide = (st.set and not st.backedOff and not st.stopped
        and not (st.inCombat and combatPolicy() == "hide_all")
        and turnArrowOn() and not corpseShown()) or RoadBeacon.pinHidden
    if hide and not st.arrowHidden then
        arrow:SetAlpha(0)
        st.arrowHidden = true
    elseif not hide and st.arrowHidden then
        arrow:SetAlpha(1)
        st.arrowHidden = false
    end
end




function InWorldPin.BackOff(reason)
    local st = InWorldPin.state
    if st.backedOff then return end
    if st.stopped then



        local record = InWorldPin.Record()
        if record then record.saved = nil end
        st.saved = nil
        return
    end






    if clearIfOurs(st.target) then
        local own = st.saved and st.saved.waypoint
        if own and own.uiMapID and own.x and own.y then
            withIgnoredEvents("putting back the player's pin", C_Map.SetUserWaypoint, makePoint(own.uiMapID, own.x, own.y))
        end
    end
    forget()
    st.backedOff = true
    st.set = false
    st.saved, st.carriedQuest = nil, nil
    st.target, st.targetKey, st.lastSet = nil, nil, nil
    st.suppressed, st.pinClearedInFight = false, nil
    RoadBeacon.Refresh()
    syncGameArrow()
    if not st.noticeGiven then
        st.noticeGiven = true
        local Guide = FGPS.UI.Guide
        if Guide and Guide.Say then
            Guide.Say(L["Map pin guidance paused because you changed the tracked objective; it resumes with the next route."], InWorldPin.NOTICE_HOLD)
        end
    end
    if FGPS.Log then FGPS.Log:Debug("In-world pin backed off (%s)", tostring(reason)) end
end


function InWorldPin.Restore(reason)
    local st = InWorldPin.state
    if st.stopped then return end
    local saved = st.saved
    if st.set and saved and not st.backedOff and apiAvailable() then
        giveBack(saved)
        forget()
        if FGPS.Log then FGPS.Log:Debug("In-world pin restored previous tracking (%s)", tostring(reason)) end
    end
    st.set = false
    st.saved, st.carriedQuest = nil, nil
    st.target, st.targetKey, st.lastSet = nil, nil, nil
    st.suppressed, st.pinClearedInFight = false, nil
    RoadBeacon.Refresh()
    syncGameArrow()
end


local update
function InWorldPin.Update(force)
    local placed = update(force)
    RoadBeacon.Refresh()
    syncGameArrow()
    return placed
end

update = function(force)
    local st = InWorldPin.state
    if not InWorldPin.IsEnabled() then return false end
    if st.backedOff or st.suppressed or not st.route or not st.progress then return false end
    if st.inCombat and combatPolicy() == "hide_all" then return false end
    local legs = st.route.legs
    local leg = type(legs) == "table" and legs[st.progress.legIndex or 1] or nil
    if type(leg) == "table" and (NO_WAY_KINDS[leg.kind] or (not stockPinMode() and leg.kind ~= nil and leg.kind ~= "walk")) then




        if st.set then InWorldPin.Restore("leg without a way to walk") end
        return false
    end
    local useBeacon = beaconMode()
    local inst, x, y, kind, source = InWorldPin.SelectTarget(st.route, st.progress, useBeacon)
    if not inst or not x then return false end




    local shown = st.target
    local moveYards = useBeacon and InWorldPin.BEACON_MOVE_YARDS or InWorldPin.MOVE_YARDS
    if not force and kind == "point" and shown and shown.inst == inst and shown.wx
        and distance(shown.wx, shown.wy, x, y) < moveYards then
        x, y = shown.wx, shown.wy
    end
    local key = format("%d:%.0f:%.0f", inst, x, y)
    local t = now()
    if not force and key == st.targetKey and st.lastSet then
        if shown then shown.kind, shown.source = kind, source end
        if (t - st.lastSet) < InWorldPin.REFRESH_SECONDS then return false end




        if st.set and InWorldPin.IsOurTrackingIntact() then
            st.lastSet = t
            return false
        end
    end



    local uiMapID, mx, my = resolveMap(inst, x, y)
    if not uiMapID then
        if st.set then InWorldPin.Restore("place ahead on no map") end
        return false
    end
    if st.unavailableMaps[uiMapID] and key == st.targetKey then return false end
    if not canSetOnMap(uiMapID) then
        if st.set then InWorldPin.Restore("map refuses a waypoint") end
        st.unavailableMaps[uiMapID] = true
        st.targetKey = key
        return false
    end
    st.unavailableMaps[uiMapID] = nil


    if st.set and st.target and st.target.uiMapID == uiMapID
        and abs(mx - st.target.x) <= InWorldPin.MATCH_EPSILON
        and abs(my - st.target.y) <= InWorldPin.MATCH_EPSILON
        and InWorldPin.IsOurTrackingIntact() then
        st.target.kind, st.target.source = kind, source
        st.targetKey = key
        st.lastSet = t
        return false
    end
    if not st.set then InWorldPin.SaveCurrent() end
    local placed = InWorldPin.Place(uiMapID, mx, my)
    if placed then
        st.set = true
        st.targetKey = key
        st.lastSet = t
        st.target = { uiMapID = uiMapID, x = mx, y = my, inst = inst, wx = x, wy = y, kind = kind, source = source }
    end
    return placed
end






local BEACON_FADE_IN = 0.14
local BEACON_FADE_OUT = 0.16
local BEACON_PULSE = 0.24
local BEACON_BREATHE = 2.4
local BEACON_REATTACH = 0.1

local MEDIA = "Interface\\AddOns\\Cabbie\\Media\\"
local TEX_DOT = MEDIA .. "dot"
local TEX_RING = MEDIA .. "place_ring"
local TEX_STOP_RING = MEDIA .. "stop_ring"
local TEX_CHEVRON = MEDIA .. "arrow_chevron"
local TEX_POINTER = MEDIA .. "arrow_pointer"
local TEX_TURN = MEDIA .. "turn_mark"
local TEX_FLIGHT = MEDIA .. "place_flight"
local TEX_BOAT = MEDIA .. "place_boat"
local TEX_ZEPPELIN = MEDIA .. "place_zeppelin"
local TEX_DUNGEON = MEDIA .. "place_dungeon"

local PIN_REGIONS = { "Icon", "IconBorder", "DistanceText", "Arrow" }

local TURN_SIDE = {
    turn_slight_left = "left", turn_left = "left", turn_sharp_left = "left",
    turn_slight_right = "right", turn_right = "right", turn_sharp_right = "right",
}

local function isSecret(value)
    return value ~= nil and issecretvalue ~= nil and issecretvalue(value) == true
end

local function clientSays(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or isSecret(value) then return nil end
    return value and true or false
end

local function safeNumber(value)
    if type(value) ~= "number" or isSecret(value) then return nil end
    return value
end

local function setPinAlpha(alpha)
    local frame = SuperTrackedFrame
    if type(frame) ~= "table" then return end
    local st = InWorldPin.state
    local keepArrowHidden = alpha == 1 and st.set and not st.backedOff and not st.stopped
        and not (st.inCombat and combatPolicy() == "hide_all") and turnArrowOn() and not corpseShown()
    for i = 1, #PIN_REGIONS do
        local name = PIN_REGIONS[i]
        local region = frame[name]
        if type(region) == "table" and type(region.SetAlpha) == "function" then
            region:SetAlpha((keepArrowHidden and name == "Arrow") and 0 or alpha)
        end
    end
end

function RoadBeacon.HidePin()
    RoadBeacon.pinHidden = true
    setPinAlpha(0)
end

function RoadBeacon.ShowPin()
    RoadBeacon.pinHidden = false
    setPinAlpha(1)
end


function RoadBeacon.Evaluate()
    if not beaconMode() then return "setting" end
    if FGPS.Perf and FGPS.Perf.guidanceEnabled == false then return "setting" end
    local st = InWorldPin.state
    local route, progress = st.route, st.progress
    if (st.navState ~= "active" and st.navState ~= "in_transit") or type(route) ~= "table" or type(progress) ~= "table" then
        return "no_route"
    end
    local legs = route.legs
    local leg = type(legs) == "table" and legs[progress.legIndex or 1] or nil
    if type(leg) ~= "table" or (leg.kind ~= nil and leg.kind ~= "walk") then return "not_walk" end
    local Coords = FGPS.Coords
    if Coords and Coords.IsInstanced and Coords.IsInstanced() then return "instance" end
    if clientSays(UnitIsGhost, "player") or corpseShown() then return "ghost" end
    if not st.set or st.backedOff or st.stopped then return "pin_inactive" end
    if st.suppressed or not InWorldPin.IsOurTrackingIntact() then return "pin_released" end
    return nil
end

local function truncateCue(text)
    if type(text) ~= "string" or text == "" then return nil end
    if #text <= 30 then return text end
    return text:sub(1, 27) .. "..."
end

local function stopVisual(route, progress)
    local legs = route and route.legs
    local li = progress and progress.legIndex or 1
    if type(legs) == "table" then
        local walkStop = legs[li] and (legs[li].stopIndex or 1) or 1
        for k = li + 1, #legs do
            local nextLeg = legs[k]
            if type(nextLeg) ~= "table" then break end
            if (nextLeg.stopIndex or 1) ~= walkStop then break end
            local nk = nextLeg.kind
            if nk == "walk" then
                walkStop = nextLeg.stopIndex or walkStop
            elseif nk == "taxi" then
                return TEX_FLIGHT, false, L["Flight master"]
            elseif nk == "boat" or nk == "ferry" then
                return TEX_BOAT, false, truncateCue(nextLeg.label) or L["boat"]
            elseif nk == "zeppelin" then
                return TEX_ZEPPELIN, false, truncateCue(nextLeg.label) or L["zeppelin"]
            elseif nk == "portal" then
                return TEX_DUNGEON, false, truncateCue(nextLeg.label)
            else
                break
            end
        end
    end
    local stops = route and route.stops
    local stop = type(stops) == "table" and stops[legs and legs[li] and legs[li].stopIndex or #stops] or nil
    local dest = stop and stop.dest
    local destType = dest and (dest.type or dest.kind)
    local name = truncateCue(dest and dest.name)
    if destType == "dungeon" or destType == "raid" or destType == "instance" then
        return TEX_DUNGEON, false, name
    end
    return TEX_STOP_RING, true, name
end

local function selectVisual(target)
    local kind = target and target.kind
    local source = target and target.source
    if kind == "step" and type(source) == "table" then
        local sk = source.kind
        local cue = truncateCue(source.shortText or source.text)
        local side = TURN_SIDE[sk]
        if side == "left" then
            return "turn", TEX_TURN, false, 0, false, cue
        elseif side == "right" then
            return "turn", TEX_TURN, true, 0, false, cue
        elseif sk == "uturn" then
            return "turn", TEX_CHEVRON, false, PI, false, cue
        elseif sk == "enter" then
            return "stop", TEX_DUNGEON, false, 0, false, cue
        end
        return "turn", TEX_CHEVRON, false, 0, false, cue
    end
    if kind == "stop" then
        local st = InWorldPin.state
        local tex, dotOn, cue = stopVisual(st.route, st.progress)
        return "stop", tex, false, 0, dotOn, cue
    end
    return "road", TEX_CHEVRON, false, 0, false, nil
end

local function applyVerticalFade(tex, r, g, b, botAlpha)
    tex:SetVertexColor(r, g, b, botAlpha)
    if type(CreateColor) == "function" and type(tex.SetGradient) == "function" then
        local ok = pcall(tex.SetGradient, tex, "VERTICAL", CreateColor(r, g, b, botAlpha), CreateColor(r, g, b, 0))
        if ok then tex:SetVertexColor(1, 1, 1, 1) end
    end
end

local function makeBeaconFrame()
    local Look = FGPS.UI and FGPS.UI.Look
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:Hide()
    frame:SetFrameStrata("LOW")
    frame:SetAllPoints(UIParent)
    if frame.EnableMouse then frame:EnableMouse(false) end

    local beacon = CreateFrame("Frame", nil, frame)
    beacon:SetSize(32, 32)
    if beacon.EnableMouse then beacon:EnableMouse(false) end
    beacon:Hide()

    local beamGlow = beacon:CreateTexture(nil, "BACKGROUND", nil, 1)
    beamGlow:SetTexture(TEX_DOT)
    beamGlow:SetTexCoord(0, 1, 0, 0.5)
    beamGlow:SetBlendMode("ADD")
    beamGlow:SetPoint("BOTTOM", beacon, "CENTER", 0, 4)
    beamGlow:SetSize(18, 110)
    applyVerticalFade(beamGlow, 1.0, 0.84, 0.30, 0.30)

    local beamCore = beacon:CreateTexture(nil, "ARTWORK", nil, -1)
    beamCore:SetTexture(TEX_DOT)
    beamCore:SetTexCoord(0, 1, 0, 0.5)
    beamCore:SetBlendMode("ADD")
    beamCore:SetPoint("BOTTOM", beacon, "CENTER", 0, 4)
    beamCore:SetSize(4.5, 96)
    applyVerticalFade(beamCore, 1.0, 0.97, 0.80, 0.62)

    local halo = beacon:CreateTexture(nil, "BACKGROUND", nil, 0)
    halo:SetTexture(TEX_DOT)
    halo:SetBlendMode("ADD")
    halo:SetPoint("CENTER", beacon, "CENTER", 0, 0)
    halo:SetSize(44, 44)
    halo:SetVertexColor(1.0, 0.86, 0.36, 0.24)

    local ring = beacon:CreateTexture(nil, "BORDER", nil, 1)
    ring:SetTexture(TEX_RING)
    ring:SetPoint("CENTER", beacon, "CENTER", 0, 0)
    ring:SetSize(30, 30)
    ring:SetVertexColor(0.96, 0.85, 0.52, 0.88)

    local icon = beacon:CreateTexture(nil, "ARTWORK", nil, 2)
    icon:SetTexture(TEX_CHEVRON)
    icon:SetPoint("CENTER", beacon, "CENTER", 0, 0)
    icon:SetSize(20, 20)
    icon:SetVertexColor(1.0, 0.94, 0.72, 1.0)

    local centerDot = beacon:CreateTexture(nil, "OVERLAY", nil, 1)
    centerDot:SetTexture(TEX_DOT)
    centerDot:SetPoint("CENTER", beacon, "CENTER", 0, 0)
    centerDot:SetSize(9, 9)
    centerDot:SetVertexColor(1.0, 0.92, 0.55, 0.95)
    centerDot:Hide()

    local pulse = beacon:CreateTexture(nil, "OVERLAY", nil, 2)
    pulse:SetTexture(TEX_RING)
    pulse:SetBlendMode("ADD")
    pulse:SetPoint("CENTER", beacon, "CENTER", 0, 0)
    pulse:SetSize(30, 30)
    pulse:SetVertexColor(1.0, 0.90, 0.48, 0)
    pulse:Hide()

    local edgeArrow = beacon:CreateTexture(nil, "ARTWORK", nil, 3)
    edgeArrow:SetTexture(TEX_POINTER)
    edgeArrow:SetPoint("CENTER", beacon, "CENTER", 0, 0)
    edgeArrow:SetSize(26, 26)
    edgeArrow:SetVertexColor(1.0, 0.86, 0.36, 0.92)
    edgeArrow:Hide()

    local distText
    if Look and Look.FontString then
        distText = Look.FontString(beacon, "OVERLAY", "mapLabel")
    else
        distText = beacon:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    end
    distText:SetPoint("TOP", beacon, "BOTTOM", 0, -2)
    if distText.SetWordWrap then distText:SetWordWrap(false) end
    distText:SetTextColor(0.97, 0.93, 0.82, 1)

    local cueText
    if Look and Look.FontString then
        cueText = Look.FontString(beacon, "OVERLAY", "mapLabel")
    else
        cueText = beacon:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    end
    cueText:SetPoint("TOP", distText, "BOTTOM", 0, -1)
    if cueText.SetWordWrap then cueText:SetWordWrap(false) end
    cueText:SetTextColor(1.0, 0.86, 0.38, 1)
    cueText:Hide()

    RoadBeacon.beacon = beacon
    RoadBeacon.parts = {
        beacon = beacon,
        beamGlow = beamGlow,
        beamCore = beamCore,
        halo = halo,
        ring = ring,
        icon = icon,
        centerDot = centerDot,
        pulse = pulse,
        edgeArrow = edgeArrow,
        distText = distText,
        cueText = cueText,
    }
    return frame
end

local frameState = RoadBeacon.frameState
local anchoredTo = nil
local lastTargetKey = nil
local lastTex, lastMirror, lastRot, lastMode = nil, false, 0, nil
local lastYards, lastUnits, lastCue, distAtEdge = nil, nil, nil, false
local fade, invalidFor, pinBack = 0, 0, true
local beaconClock, pulseLeft = 0, 0
local beaconHalted = false
local detachedAt
local detachedOn = setmetatable({}, { __mode = "v" })
local lastBeaconError
local detachBeacon

local function resetBeaconState()
    anchoredTo = nil
    lastTargetKey = nil
    lastTex, lastMirror, lastRot, lastMode = nil, false, 0, nil
    lastYards, lastUnits, lastCue, distAtEdge = nil, nil, nil, false
    fade, invalidFor, pinBack = 0, 0, true
    pulseLeft = 0
    frameState.reason, frameState.shown, frameState.clamped = nil, false, false
    frameState.mode, frameState.distYards, frameState.cue, frameState.fade = nil, nil, nil, 0
    if RoadBeacon.beacon then RoadBeacon.beacon:Hide() end
end

local function targetDistance(target)
    local Nav = C_Navigation
    if type(Nav) == "table" and type(Nav.GetDistance) == "function" then
        local ok, d = pcall(Nav.GetDistance)
        local n = ok and safeNumber(d) or nil
        if n and n > 0 then return n end
    end
    if target and target.wx and target.wy then
        local progress = InWorldPin.state.progress
        local pos = progress and progress.pos
        if pos and pos.x and pos.y and (target.inst == nil or pos.inst == target.inst) then
            return distance(pos.x, pos.y, target.wx, target.wy)
        end
    end
    return nil
end

local function screenCenter()
    local wf = WorldFrame
    if type(wf) == "table" and type(wf.GetCenter) == "function" then
        local ok, cx, cy = pcall(wf.GetCenter, wf)
        local sx, sy = ok and safeNumber(cx), ok and safeNumber(cy)
        if sx and sy then
            local scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
            if type(scale) == "number" and scale > 0 then return sx / scale, sy / scale end
            return sx, sy
        end
    end
    if UIParent and UIParent.GetCenter then
        local ok, cx, cy = pcall(UIParent.GetCenter, UIParent)
        local sx, sy = ok and safeNumber(cx), ok and safeNumber(cy)
        if sx and sy then return sx, sy end
    end
    return 800, 450
end

local function stepBeacon(elapsed)
    if type(elapsed) ~= "number" or elapsed < 0 then elapsed = 0 elseif elapsed > 0.25 then elapsed = 0.25 end
    beaconClock = (beaconClock + elapsed) % 3600

    local Nav = C_Navigation
    if type(Nav) ~= "table" or type(Nav.HasValidScreenPosition) ~= "function" or type(Nav.GetFrame) ~= "function" then
        frameState.reason, frameState.shown = "no_api", false
        return
    end

    local valid = clientSays(Nav.HasValidScreenPosition)
    local navFrame = valid and Nav.GetFrame() or nil
    if not valid or type(navFrame) ~= "table" then
        frameState.reason = "invalid"
        if fade > 0 then
            fade = max(0, fade - elapsed / BEACON_FADE_OUT)
            frameState.fade = fade
            if fade > 0 and RoadBeacon.beacon then
                RoadBeacon.beacon:SetAlpha(fade)
                frameState.shown = true
                return
            end
        end
        if RoadBeacon.beacon then RoadBeacon.beacon:Hide() end
        frameState.shown, frameState.fade = false, 0
        invalidFor = invalidFor + elapsed
        if invalidFor >= RoadBeacon.PIN_BACK_SECONDS and not pinBack then
            pinBack = true
            if RoadBeacon.pinHidden then RoadBeacon.ShowPin() end
        end
        return
    end

    invalidFor = 0
    if pinBack or not RoadBeacon.pinHidden then
        pinBack = false
        RoadBeacon.HidePin()
        syncGameArrow()
    end

    local parts = RoadBeacon.parts
    local beacon = parts.beacon
    if anchoredTo ~= navFrame then
        beacon:ClearAllPoints()
        beacon:SetPoint("CENTER", navFrame, "CENTER", 0, 0)
        anchoredTo = navFrame
    end

    if fade < 1 then
        fade = min(1, fade + elapsed / BEACON_FADE_IN)
    end

    local st = InWorldPin.state
    local target = st.target
    local key = st.targetKey
    if key ~= nil and key ~= lastTargetKey then
        if lastTargetKey ~= nil then pulseLeft = BEACON_PULSE end
        lastTargetKey = key
    end

    local dist = targetDistance(target)
    local yards = dist and floor(dist + 0.5) or nil
    local units = (FGPS.DB and FGPS.DB.settings and FGPS.DB.settings.units) or "yards"
    if yards ~= lastYards or units ~= lastUnits then
        lastYards, lastUnits = yards, units
        if yards and yards >= 1 then
            local Look = FGPS.UI and FGPS.UI.Look
            local label = (Look and Look.Distance and Look.Distance(yards, 1)) or format("%d yd", yards)
            parts.distText:SetText(label)
            parts.distText:Show()
        else
            parts.distText:Hide()
        end
    end

    local clamped = clientSays(Nav.WasClampedToScreen) == true
    frameState.clamped = clamped
    frameState.distYards = yards

    local cx, cy = screenCenter()
    local nx, ny
    if type(navFrame.GetCenter) == "function" then
        local ok, rx, ry = pcall(navFrame.GetCenter, navFrame)
        nx, ny = ok and safeNumber(rx), ok and safeNumber(ry)
    end

    if clamped then
        frameState.reason = nil
        frameState.mode = "edge"
        frameState.cue = nil
        parts.beamGlow:Hide()
        parts.beamCore:Hide()
        parts.ring:Hide()
        parts.icon:Hide()
        parts.centerDot:Hide()
        parts.pulse:Hide()
        parts.cueText:Hide()

        parts.halo:SetSize(34, 34)
        parts.halo:SetAlpha(0.18)
        parts.halo:Show()

        local angle = 0
        local ux, uy = 0, 1
        if nx and ny then
            local dx, dy = nx - cx, ny - cy
            local len = sqrt(dx * dx + dy * dy)
            if len > 1 then
                ux, uy = dx / len, dy / len
                angle = atan2(-dx, dy)
            end
        end
        if abs(angle - lastRot) > 0.005 or lastMode ~= "edge" then
            parts.edgeArrow:SetRotation(angle)
            lastRot = angle
        end
        parts.edgeArrow:Show()

        parts.distText:ClearAllPoints()
        parts.distText:SetPoint("CENTER", beacon, "CENTER", -ux * 26, -uy * 20)
        distAtEdge = true
        lastMode = "edge"

        beacon:SetAlpha(0.88 * fade)
        beacon:Show()
        frameState.shown, frameState.fade = true, fade
        return
    end

    frameState.reason = nil
    parts.edgeArrow:Hide()
    if distAtEdge then
        parts.distText:ClearAllPoints()
        parts.distText:SetPoint("TOP", beacon, "BOTTOM", 0, -2)
        distAtEdge = false
    end

    local mode, tex, mirror, rot, dotOn, cue = selectVisual(target)
    frameState.mode = mode
    frameState.cue = cue

    if tex ~= lastTex then
        parts.icon:SetTexture(tex)
        lastTex = tex
    end
    if mirror ~= lastMirror then
        if mirror then
            parts.icon:SetTexCoord(1, 0, 0, 1)
        else
            parts.icon:SetTexCoord(0, 1, 0, 1)
        end
        lastMirror = mirror
    end
    if rot ~= lastRot or lastMode == "edge" then
        parts.icon:SetRotation(rot)
        lastRot = rot
    end
    if mode ~= lastMode then
        if mode == "turn" then
            parts.icon:SetSize(23, 23)
            parts.icon:SetVertexColor(1.0, 0.90, 0.42, 1.0)
            parts.ring:SetVertexColor(1.0, 0.84, 0.36, 0.95)
            parts.distText:SetTextColor(1.0, 0.90, 0.46, 1)
        elseif mode == "stop" then
            local sz = dotOn and 26 or 22
            parts.icon:SetSize(sz, sz)
            parts.icon:SetVertexColor(1.0, 0.94, 0.76, 1.0)
            parts.ring:SetVertexColor(0.98, 0.88, 0.56, 0.92)
            parts.distText:SetTextColor(1.0, 0.90, 0.46, 1)
        else
            parts.icon:SetSize(19, 19)
            parts.icon:SetVertexColor(1.0, 0.94, 0.72, 0.95)
            parts.ring:SetVertexColor(0.94, 0.83, 0.50, 0.78)
            parts.distText:SetTextColor(0.96, 0.93, 0.84, 0.95)
        end
        lastMode = mode
    end

    parts.ring:Show()
    parts.icon:Show()
    if dotOn then parts.centerDot:Show() else parts.centerDot:Hide() end

    if cue ~= lastCue then
        lastCue = cue
        if cue then
            parts.cueText:SetText(cue)
            parts.cueText:Show()
        else
            parts.cueText:Hide()
        end
    elseif cue and not parts.cueText:IsShown() then
        parts.cueText:Show()
    elseif not cue and parts.cueText:IsShown() then
        parts.cueText:Hide()
    end

    local d = dist or 45
    local beamFade = 1
    if d < 14 then
        beamFade = (d - 5) / 9
        if beamFade < 0 then beamFade = 0 elseif beamFade > 1 then beamFade = 1 end
    end
    if beamFade > 0.02 then
        local span = min(1, max(0, (d - 12) / 55))
        local bh = 82 + 44 * span
        local boost = (mode == "turn" or mode == "stop") and 1.18 or 1.0
        parts.beamGlow:SetHeight(bh)
        parts.beamCore:SetHeight(bh * 0.86)
        parts.beamGlow:SetAlpha(min(1, beamFade * boost))
        parts.beamCore:SetAlpha(min(1, beamFade * boost))
        parts.beamGlow:Show()
        parts.beamCore:Show()
    else
        parts.beamGlow:Hide()
        parts.beamCore:Hide()
    end

    local breathe = 0.21 + 0.05 * sin(beaconClock * (TWO_PI / BEACON_BREATHE))
    parts.halo:SetSize(44, 44)
    parts.halo:SetAlpha(breathe)
    parts.halo:Show()

    if pulseLeft > 0 then
        pulseLeft = pulseLeft - elapsed
        if pulseLeft > 0 then
            local u = 1 - pulseLeft / BEACON_PULSE
            local psz = 28 + 20 * u
            parts.pulse:SetSize(psz, psz)
            parts.pulse:SetAlpha(0.55 * (1 - u))
            parts.pulse:Show()
        else
            parts.pulse:Hide()
        end
    end

    local comfort = 1
    if d < 9 then
        comfort = 0.48 + 0.52 * max(0, d / 9)
    end
    if nx and ny then
        local adx, ady = abs(nx - cx), abs(ny - cy)
        if adx < 80 and ady < 100 then
            local box = max(adx / 80, ady / 100)
            comfort = min(comfort, 0.52 + 0.48 * box)
        end
    end

    beacon:SetAlpha(fade * comfort)
    beacon:Show()
    frameState.shown, frameState.fade = true, fade
end

local function reportBeaconError(err)
    local text = tostring(err)
    if text ~= lastBeaconError then
        lastBeaconError = text
        if FGPS.Log then FGPS.Log:Error("The road beacon stopped: %s", text) end
    end
end

local function onBeaconUpdate(_, elapsed)
    local ok, err = pcall(stepBeacon, elapsed)
    if ok then return end
    beaconHalted = true
    pcall(detachBeacon)
    pcall(RoadBeacon.ShowPin)
    syncGameArrow()
    reportBeaconError(err)
end

local function attachBeacon()
    local frame = RoadBeacon.frame
    if not frame then
        RoadBeacon.frameFailed = true
        frame = makeBeaconFrame()
        RoadBeacon.frameFailed = false
        RoadBeacon.frame = frame
    end
    local t = now()
    local route = InWorldPin.state.route
    local again = detachedAt and (t - detachedAt) < BEACON_REATTACH and route ~= nil and route == detachedOn[1]
    if not again then resetBeaconState() end
    detachedAt, detachedOn[1] = nil, nil
    RoadBeacon.attached = true
    frame:SetScript("OnUpdate", onBeaconUpdate)
    frame:Show()
end

detachBeacon = function()
    RoadBeacon.attached = false
    local frame = RoadBeacon.frame
    if frame then
        frame:SetScript("OnUpdate", nil)
        frame:Hide()
    end
    if RoadBeacon.beacon then RoadBeacon.beacon:Hide() end
    detachedAt, detachedOn[1] = now(), InWorldPin.state.route
    frameState.shown = false
end

function RoadBeacon.IsDrawing()
    return RoadBeacon.attached
end

function RoadBeacon.ClearHalt()
    beaconHalted = false
end

local function refreshBeacon()
    local reason = RoadBeacon.Evaluate()
    frameState.reason = reason
    if not beaconHalted and not RoadBeacon.frameFailed and reason == nil then
        if not RoadBeacon.attached then attachBeacon() end
        if not RoadBeacon.pinHidden and not pinBack then RoadBeacon.HidePin() end
    elseif RoadBeacon.attached or RoadBeacon.pinHidden then
        detachBeacon()
        RoadBeacon.ShowPin()
    end
end

function RoadBeacon.Refresh()
    local ok, err = pcall(refreshBeacon)
    if ok then
        lastBeaconError = nil
    else
        pcall(detachBeacon)
        pcall(RoadBeacon.ShowPin)
        reportBeaconError(err)
    end
end








local function progressOf(route)
    local Navigator = FGPS.Navigator
    local st = InWorldPin.state
    local current = Navigator and Navigator.GetProgress and Navigator:GetProgress()
    if Navigator and Navigator.GetRoute and Navigator:GetRoute() == route and type(current) == "table" then
        st.progress = current
    end
end

local function onRouteStarted(_, route)
    RoadBeacon.ClearHalt()
    local st = InWorldPin.state
    st.route = route
    st.backedOff = false
    st.noticeGiven = false
    st.unavailableMaps = {}
    st.targetKey, st.lastSet = nil, nil
    progressOf(route)
    if st.progress then InWorldPin.Update(true) else RoadBeacon.Refresh() end
end





local function onRouteUpdated(_, route, reason)
    local st = InWorldPin.state
    st.route = route
    st.targetKey = nil
    local Navigator = FGPS.Navigator
    if reason == "destination" and Navigator and Navigator.askedBy == "player" then
        st.backedOff, st.noticeGiven = false, false
    end
    progressOf(route)
    if st.progress then InWorldPin.Update(true) else RoadBeacon.Refresh() end
end

local function onRouteProgress(_, progress)
    InWorldPin.state.progress = progress
    InWorldPin.Update(false)
end

local function onNavState(_, newState)
    local st = InWorldPin.state
    st.navState = newState or "idle"
    if newState == "idle" or newState == "arrived" then
        InWorldPin.Restore("state:" .. tostring(newState))
        st.route, st.progress = nil, nil
    else
        RoadBeacon.Refresh()
        syncGameArrow()
    end
end

local function onNavArrived(_, _, isFinal)
    if isFinal then InWorldPin.Restore("arrived") end
end

local function onNavCancelled()
    InWorldPin.Restore("cancelled")
    InWorldPin.state.route, InWorldPin.state.progress = nil, nil
end

local function onCombatState(_, inCombat)
    local st = InWorldPin.state
    st.inCombat = inCombat and true or false
    if st.inCombat then
        if st.set and not st.suppressed and combatPolicy() == "hide_all" then
            st.suppressed = true



            st.questAtRelease, st.fightMoveAt = focusedQuest(), nil
            withIgnoredEvents("releasing the focus for a fight", C_SuperTrack.SetSuperTrackedUserWaypoint, false)
        end
    elseif st.suppressed then
        st.suppressed = false





        local wp = currentWaypoint()
        local userTookOver = focusedQuest() ~= st.questAtRelease
            or (wp ~= nil and not waypointMatches(wp, st.target))
            or (wp == nil and st.pinClearedInFight)
        st.questAtRelease, st.fightMoveAt = nil, nil
        st.pinClearedInFight = nil
        if userTookOver then
            InWorldPin.BackOff("combat")
        else
            InWorldPin.Update(true)
        end
    end
    RoadBeacon.Refresh()
    syncGameArrow()
end












local function onSuperTrackingChanged()
    local st = InWorldPin.state
    local before, quest = st.focusQuest, focusedQuest()
    st.focusQuest = quest

    if st.suppressed and st.ignore == 0 and currentWaypoint() == nil then st.pinClearedInFight = true end




    if st.suppressed and quest ~= before then
        local t = now()
        if st.questMomentAt and t - st.questMomentAt <= InWorldPin.QUEST_QUIET then
            st.questAtRelease = quest
        else
            st.fightMoveAt = t
        end
    end
    if quest ~= st.ownQuest then st.ownQuest = nil end
    RoadBeacon.Refresh()
    syncGameArrow()
    if st.ignore > 0 or not st.set or st.backedOff then return end
    if InWorldPin.IsOurTrackingIntact() then return end
    if st.placeAskedAt ~= nil and st.placeAskedAt == now() then



        if st.saved and st.savedAt == now() and type(C_SuperTrack.IsSuperTrackingUserWaypoint) == "function" then
            local ok, tracking = pcall(C_SuperTrack.IsSuperTrackingUserWaypoint)
            st.saved.trackingWaypoint = ok and tracking == true
        end
        InWorldPin.Update(true)
        return
    end
    InWorldPin.BackOff("user")
end



local function onDestinationSet(_, _, askedBy)
    if askedBy == "player" then InWorldPin.state.placeAskedAt = now() end
end








local function pinKey(point)
    local px, py = pointXY(point)
    return tostring(point.uiMapID) .. ":" .. tostring(px) .. ":" .. tostring(py)
end

local function pinToFollow()
    local st = InWorldPin.state
    local db = FGPS.DB
    if st.ignore > 0 or not st.worldEntered or not (db and db.settings and db.settings.goToMapPin ~= false) then
        return nil
    end
    local point = currentWaypoint()
    if point == nil then
        st.pinFollowed = nil
        return nil
    end
    local key = pinKey(point)
    if key == st.pinFollowed or waypointMatches(point, InWorldPin.Record()) then return nil end
    local Compat = FGPS.UI.Compat
    if not (Compat and Compat.FromUserWaypoint) then return nil end
    local ok, dest = pcall(Compat.FromUserWaypoint)
    if not ok or type(dest) ~= "table" then return nil end
    st.pinFollowed = key
    return dest
end






local function letGoForThePin()
    local st = InWorldPin.state
    forget()
    local saved = st.saved
    st.carriedQuest = saved and (saved.questTaken or not saved.trackingWaypoint) and saved.questID or nil
    st.set, st.saved, st.backedOff = false, nil, false
    st.target, st.targetKey, st.lastSet = nil, nil, nil
    st.suppressed, st.pinClearedInFight = false, nil
    RoadBeacon.Refresh()
    syncGameArrow()
end

local function onUserWaypointUpdated()
    local dest = pinToFollow()
    local Go = FGPS.UI.Go
    if dest and Go and Go.Start then
        letGoForThePin()
        Go.Start(dest)
        return
    end
    onSuperTrackingChanged()
end




local function noteQuestMoment()
    local st = InWorldPin.state
    st.questMomentAt = now()
    if st.suppressed and st.fightMoveAt == st.questMomentAt then st.questAtRelease = focusedQuest() end
end

local function onSettingsChanged(_, key)
    if key == "inWorldPin" or key == "roadBeacon" or key == "perf.guidanceEnabled" or key == "*" then
        if not InWorldPin.IsEnabled() then
            InWorldPin.Restore("disabled")
        elseif InWorldPin.state.route and InWorldPin.state.progress then
            InWorldPin.Update(true)
        else
            RoadBeacon.Refresh()
            syncGameArrow()
        end
    elseif key == "combatMode" and InWorldPin.state.inCombat then
        onCombatState(nil, true)
    else
        RoadBeacon.Refresh()
        syncGameArrow()
    end
end




local function onActionBlocked(_, addon, func)
    local st = InWorldPin.state
    if addon ~= ADDON_NAME or st.stopped or not st.lastCallAt then return end
    local since = now() - st.lastCallAt
    if since > InWorldPin.BLOCKED_WINDOW then return end
    st.stopped = true
    RoadBeacon.Refresh()
    syncGameArrow()
    if FGPS.Log then
        FGPS.Log:Warn("In-world marker stopped for this session: the client blocked %s %.2f s after the marker's last change (%s)",
            tostring(func), since, tostring(st.lastCallWhat))
    end
    FGPS:Print(L["The game blocked an action right after Cabbie changed its in-world marker, so Cabbie has stopped the marker until you reload or log in again. The arrow and the map lines carry on; a marker Cabbie had already placed stays on the map until you remove it or reload."])
end




function InWorldPin:Init()
    if InWorldPin.initialised then return InWorldPin end
    InWorldPin.initialised = true
    if FGPS.Events then
        local E = FGPS.Events
        E:Register("ROUTE_STARTED", onRouteStarted, InWorldPin)
        E:Register("ROUTE_UPDATED", onRouteUpdated, InWorldPin)
        E:Register("ROUTE_PROGRESS", onRouteProgress, InWorldPin)
        E:Register("NAV_STATE", onNavState, InWorldPin)
        E:Register("NAV_ARRIVED", onNavArrived, InWorldPin)
        E:Register("NAV_CANCELLED", onNavCancelled, InWorldPin)
        E:Register("COMBAT_STATE", onCombatState, InWorldPin)
        E:Register("SETTINGS_CHANGED", onSettingsChanged, InWorldPin)
        E:Register("DESTINATION_SET", onDestinationSet, InWorldPin)
        E:RegisterWoW("SUPER_TRACKING_CHANGED", onSuperTrackingChanged, InWorldPin)
        E:RegisterWoW("USER_WAYPOINT_UPDATED", onUserWaypointUpdated, InWorldPin)
        E:RegisterWoW("ADDON_ACTION_FORBIDDEN", onActionBlocked, InWorldPin)
        E:RegisterWoW("ADDON_ACTION_BLOCKED", onActionBlocked, InWorldPin)
        local function onWorldState()
            RoadBeacon.Refresh()
            syncGameArrow()
        end
        E:RegisterWoW("PLAYER_DEAD", onWorldState, InWorldPin)
        E:RegisterWoW("PLAYER_ALIVE", onWorldState, InWorldPin)
        E:RegisterWoW("PLAYER_UNGHOST", onWorldState, InWorldPin)
        E:RegisterWoW("ZONE_CHANGED_NEW_AREA", onWorldState, InWorldPin)




        local function questLeft(_, questID)
            noteQuestMoment()
            local st = InWorldPin.state
            if questID ~= nil and questID == st.ownQuest and focusedQuest() == questID then
                st.ownQuest = nil
                withIgnoredEvents("taking back a quest's focus", C_SuperTrack.SetSuperTrackedQuestID, 0)
            end
        end
        E:RegisterWoW("QUEST_ACCEPTED", noteQuestMoment, InWorldPin)
        E:RegisterWoW("QUEST_TURNED_IN", questLeft, InWorldPin)
        E:RegisterWoW("QUEST_REMOVED", questLeft, InWorldPin)

        E:Register("WORLD_ENTERED", function()
            InWorldPin.ClearLeftover(true)


            local st = InWorldPin.state
            if not st.worldEntered then
                st.worldEntered = true
                local point = currentWaypoint()
                st.pinFollowed = point and pinKey(point) or nil
            end



            if InCombatLockdown and inFight() ~= InWorldPin.state.inCombat then onCombatState(nil, inFight()) end
        end, InWorldPin)
    end
    InWorldPin.state.focusQuest = focusedQuest()
    InWorldPin.state.inCombat = InCombatLockdown and InCombatLockdown() or false
    InWorldPin.ClearLeftover(false)
    return InWorldPin
end
