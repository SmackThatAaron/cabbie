





































local ADDON_NAME, FGPS = ...

local L = FGPS.L
local type, pairs, ipairs, tostring, tonumber, pcall = type, pairs, ipairs, tostring, tonumber, pcall
local sqrt, abs, format = math.sqrt, math.abs, string.format

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
        ignore = 0,
        unavailableMaps = {},

        focusQuest = nil,
        ownQuest = nil,
        quietUntil = nil,
        quietAt = nil,
        selected = nil,
        selectTimer = nil,
    },
}
FGPS.UI.InWorldPin = InWorldPin

InWorldPin.MIN_AHEAD_YARDS = 60
InWorldPin.SIGHT_YARDS = 20
InWorldPin.SIGHT_CAP_YARDS = 200
InWorldPin.MOVE_YARDS = 30
InWorldPin.REFRESH_SECONDS = 5
InWorldPin.MATCH_EPSILON = 0.0005
InWorldPin.NOTICE_HOLD = 6




InWorldPin.QUEST_QUIET = 0.5
InWorldPin.WORLD_QUIET = 5




local function now()
    return GetTime and GetTime() or 0
end





local function quietFor(seconds)
    local st = InWorldPin.state
    st.quietAt = now()
    local untilTime = st.quietAt + seconds
    if not st.quietUntil or untilTime > st.quietUntil then st.quietUntil = untilTime end
end


local function focusedQuest()
    if type(C_SuperTrack) ~= "table" or type(C_SuperTrack.GetSuperTrackedQuestID) ~= "function" then return nil end
    local ok, questID = pcall(C_SuperTrack.GetSuperTrackedQuestID)
    if not ok or type(questID) ~= "number" or (issecretvalue ~= nil and issecretvalue(questID) == true) or questID <= 0 then return nil end
    return questID
end

local function settingsEnabled()
    local db = FGPS.DB
    if db and db.settings and db.settings.inWorldPin == false then return false end
    if FGPS.Perf and FGPS.Perf.guidanceEnabled == false then return false end
    return true
end

local function apiAvailable()
    return type(C_Map) == "table" and type(C_Map.SetUserWaypoint) == "function"
        and type(C_SuperTrack) == "table" and type(C_SuperTrack.SetSuperTrackedUserWaypoint) == "function"
end

function InWorldPin.IsEnabled()
    return settingsEnabled() and apiAvailable()
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


local function inSight(pos, count, x, y)
    local sight = InWorldPin.SIGHT_YARDS
    for i = 1, count do
        local p = passed[i]
        if offLine(p.x, p.y, pos.x, pos.y, x, y) > sight then return false end
    end
    return true
end








local function sightTarget(route, progress, pos)
    local legs = route.legs
    local li = progress.legIndex or 1
    local cap = InWorldPin.SIGHT_CAP_YARDS
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
            local i = 1
            while i < #points and (cum[i + 1] or 0) <= progress.alongYards do i = i + 1 end
            if startP > i + 1 then startP = i + 1 end
        end
        for p = startP, #points do
            local pt = points[p]
            if type(pt) == "table" and pt.x and pt.y then
                local seg = distance(cx, cy, pt.x, pt.y)
                if along + seg >= cap then
                    local u = (cap - along) / seg
                    local x, y = cx + (pt.x - cx) * u, cy + (pt.y - cy) * u
                    if inSight(pos, count, x, y) then return x, y, nil end
                    return bestX, bestY, bestPoint
                end
                if not inSight(pos, count, pt.x, pt.y) then return bestX, bestY, bestPoint end
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










function InWorldPin.SelectTarget(route, progress)
    if type(route) ~= "table" or type(progress) ~= "table" then return nil end
    local pos = progress.pos
    if type(pos) ~= "table" or not pos.x or not pos.y then return nil end
    local minAhead = InWorldPin.MIN_AHEAD_YARDS
    local inst = pos.inst

    local current = type(route.legs) == "table" and route.legs[progress.legIndex or 1] or nil
    if type(current) == "table" then
        if NO_WAY_KINDS[current.kind] then return nil end
        if (current.kind == nil or current.kind == "walk") and (current.inst == nil or inst == nil or current.inst == inst) then
            local x, y, point, ends = sightTarget(route, progress, pos)
            if x then return inst, x, y, ends and "stop" or "point", point end
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
    InWorldPin.state.saved = saved
    return saved
end




local function withIgnoredEvents(fn, ...)
    local st = InWorldPin.state
    st.ignore = st.ignore + 1
    local ok, a, b = pcall(fn, ...)
    st.ignore = st.ignore - 1
    if not ok and FGPS.Log then FGPS.Log:Error("In-world pin API call failed: %s", tostring(a)) end
    return ok, a, b
end









function InWorldPin.FocusQuest(questID)
    if type(questID) ~= "number" or questID <= 0 then return false end
    if type(C_SuperTrack) ~= "table" or type(C_SuperTrack.SetSuperTrackedQuestID) ~= "function" then return false end
    local st = InWorldPin.state
    if st.set and st.saved and not st.backedOff then
        st.saved.questID, st.saved.trackingWaypoint = questID, false
        return true
    end
    st.ownQuest = questID
    local ok = withIgnoredEvents(C_SuperTrack.SetSuperTrackedQuestID, questID)


    if ok and type(C_SuperTrack.IsSuperTrackingUserWaypoint) == "function"
        and type(C_SuperTrack.SetSuperTrackedUserWaypoint) == "function" then
        local asked, tracking = pcall(C_SuperTrack.IsSuperTrackingUserWaypoint)
        if asked and tracking == true then withIgnoredEvents(C_SuperTrack.SetSuperTrackedUserWaypoint, false) end
    end
    return ok
end

function InWorldPin.Place(uiMapID, mx, my)
    local placed = false
    withIgnoredEvents(function()
        local wasSet = C_Map.SetUserWaypoint(makePoint(uiMapID, mx, my))
        placed = wasSet ~= false
        if placed then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    end)
    if placed then remember(uiMapID, mx, my) end
    return placed
end



local function clearIfOurs(ours)
    if not ours or not apiAvailable() or type(C_Map.ClearUserWaypoint) ~= "function" then return false end
    if not waypointMatches(currentWaypoint(), ours) then return false end
    withIgnoredEvents(function()

        local okTracking, tracking = pcall(C_SuperTrack.IsSuperTrackingUserWaypoint or function() return false end)
        if okTracking and tracking == true then C_SuperTrack.SetSuperTrackedUserWaypoint(false) end
        C_Map.ClearUserWaypoint()
    end)
    quietFor(InWorldPin.QUEST_QUIET)
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
    withIgnoredEvents(function()
        if saved.waypoint and saved.waypoint.uiMapID then
            C_Map.SetUserWaypoint(makePoint(saved.waypoint.uiMapID, saved.waypoint.x, saved.waypoint.y))
            C_SuperTrack.SetSuperTrackedUserWaypoint(saved.trackingWaypoint and true or false)
        else
            C_SuperTrack.SetSuperTrackedUserWaypoint(false)
            if type(C_Map.ClearUserWaypoint) == "function" then C_Map.ClearUserWaypoint() end
        end
        if saved.questID and not saved.trackingWaypoint and type(C_SuperTrack.SetSuperTrackedQuestID) == "function"
            and stillInLog(saved.questID) then

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
    if removed and FGPS.Log then FGPS.Log:Info("Removed a map pin left behind by an earlier journey") end
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
        if ok and kind ~= nil and kind ~= Enum.SuperTrackingType.UserWaypoint then return false end
    end
    if type(C_Map.GetUserWaypoint) == "function" then
        local ok, point = pcall(C_Map.GetUserWaypoint)
        if not ok or not waypointMatches(point, st.target) then return false end
    end
    return true
end




function InWorldPin.BackOff(reason)
    local st = InWorldPin.state
    if st.backedOff then return end






    if clearIfOurs(st.target) then
        local own = st.saved and st.saved.waypoint
        if own and own.uiMapID and own.x and own.y then
            withIgnoredEvents(C_Map.SetUserWaypoint, makePoint(own.uiMapID, own.x, own.y))
        end
    end
    forget()
    st.backedOff = true
    st.set = false
    st.saved = nil
    st.target, st.targetKey, st.lastSet = nil, nil, nil
    st.suppressed, st.pinClearedInFight = false, nil
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
    local saved = st.saved
    if st.set and saved and not st.backedOff and apiAvailable() then
        giveBack(saved)
        forget()
        quietFor(InWorldPin.QUEST_QUIET)
        if FGPS.Log then FGPS.Log:Debug("In-world pin restored previous tracking (%s)", tostring(reason)) end
    end
    st.set = false
    st.saved = nil
    st.target, st.targetKey, st.lastSet = nil, nil, nil
    st.suppressed, st.pinClearedInFight = false, nil
end


function InWorldPin.Update(force)
    local st = InWorldPin.state
    if not InWorldPin.IsEnabled() then return false end
    if st.backedOff or st.suppressed or not st.route or not st.progress then return false end
    if st.inCombat and combatPolicy() == "hide_all" then return false end
    local legs = st.route.legs
    local leg = type(legs) == "table" and legs[st.progress.legIndex or 1] or nil
    if type(leg) == "table" and NO_WAY_KINDS[leg.kind] then





        if st.set then InWorldPin.Restore("leg without a way to walk") end
        return false
    end
    local inst, x, y, kind = InWorldPin.SelectTarget(st.route, st.progress)
    if not inst or not x then return false end




    local shown = st.target
    if not force and kind == "point" and shown and shown.inst == inst and shown.wx
        and distance(shown.wx, shown.wy, x, y) < InWorldPin.MOVE_YARDS then
        x, y = shown.wx, shown.wy
    end
    local key = format("%d:%.0f:%.0f", inst, x, y)
    local t = now()
    if not force and key == st.targetKey and st.lastSet then
        if (t - st.lastSet) < InWorldPin.REFRESH_SECONDS then return false end




        if st.set and InWorldPin.IsOurTrackingIntact() then
            st.lastSet = t
            return false
        end
    end
    local uiMapID, mx, my = resolveMap(inst, x, y)
    if not uiMapID then return false end
    if st.unavailableMaps[uiMapID] and key == st.targetKey then return false end
    if not canSetOnMap(uiMapID) then
        st.unavailableMaps[uiMapID] = true
        st.targetKey = key
        return false
    end
    st.unavailableMaps[uiMapID] = nil
    if not st.set then InWorldPin.SaveCurrent() end
    local placed = InWorldPin.Place(uiMapID, mx, my)
    if placed then
        st.set = true
        st.targetKey = key
        st.lastSet = t
        st.target = { uiMapID = uiMapID, x = mx, y = my, inst = inst, wx = x, wy = y }
    end
    return placed
end




local function onRouteStarted(_, route)
    local st = InWorldPin.state
    st.route = route
    st.backedOff = false
    st.noticeGiven = false
    st.unavailableMaps = {}
    st.targetKey, st.lastSet = nil, nil
    if st.progress then InWorldPin.Update(true) end
end





local function onRouteUpdated(_, route, reason)
    local st = InWorldPin.state
    st.route = route
    st.targetKey = nil
    local Navigator = FGPS.Navigator
    if reason == "destination" and Navigator and Navigator.askedBy == "player" then
        st.backedOff, st.noticeGiven = false, false
    end
    if st.progress then InWorldPin.Update(true) end
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



            st.questAtRelease = focusedQuest()
            withIgnoredEvents(C_SuperTrack.SetSuperTrackedUserWaypoint, false)
            quietFor(InWorldPin.QUEST_QUIET)
        end
    elseif st.suppressed then
        st.suppressed = false




        local wp = currentWaypoint()
        local userTookOver = focusedQuest() ~= st.questAtRelease
            or (wp ~= nil and not waypointMatches(wp, st.target))
            or (wp == nil and st.pinClearedInFight)
        st.questAtRelease = nil
        st.pinClearedInFight = nil
        if userTookOver then
            InWorldPin.BackOff("combat")
        else
            InWorldPin.Update(true)
        end
    end
end


























local function inFight()
    return InCombatLockdown ~= nil and InCombatLockdown() == true
end




local function followsSelection()
    local Quests, Navigator = FGPS.Quests, FGPS.Navigator
    if not (Quests and Quests.FollowsMine and Quests.IsQuestRoute and Navigator and Navigator.HasAnythingSet) then return false end
    if not Quests.FollowsMine() then return false end
    return not Navigator:HasAnythingSet() or Quests.IsQuestRoute()
end




local ANSWER_WORDS = { followed = "already followed", noplace = "refused, no place known" }

local function logDecision(selected, answer, why, wasSet, fight)
    local words = answer == "started" and (wasSet and "replaced the route" or "started")
        or ANSWER_WORDS[answer] or ("refused, " .. (why or "nothing to start"))
    local quietAt = InWorldPin.state.quietAt
    local since = quietAt and format("%.1f s since the last quiet mark", selected.at - quietAt) or "no quiet mark yet"
    FGPS.Log:Info("Quest selection %d: %s; %s; %s.", selected.questID, words, since, fight and "in a fight" or "not in a fight")
end




function InWorldPin.DecideSelection()
    local st = InWorldPin.state
    local selected = st.selected
    st.selected, st.selectTimer = nil, nil
    if not selected then return nil end
    local answer, why
    local fight = inFight()
    local Navigator, logging = FGPS.Navigator, FGPS.Log ~= nil and FGPS.Log.Info ~= nil
    local wasSet = logging and Navigator ~= nil and Navigator.HasAnythingSet ~= nil and Navigator:HasAnythingSet()
    if focusedQuest() ~= selected.questID then
        why = "the focus moved on"
    elseif st.quietUntil and selected.at <= st.quietUntil then
        why = "the game's own moment"
    elseif fight then
        why = "in a fight"
    else
        local Menus = FGPS.UI.Menus
        if Menus and Menus.QuestSelected then
            local ok, what = pcall(Menus.QuestSelected, selected.questID)
            if ok then
                answer = what
            else
                why = "an error"
                if FGPS.Log then FGPS.Log:Error("The selected quest could not be followed: %s", tostring(what)) end
            end
        end
    end
    if logging then logDecision(selected, answer, why, wasSet, fight) end
    if answer == "started" or answer == "followed" then

        if st.set and st.saved and not st.backedOff then st.saved.questID, st.saved.trackingWaypoint = selected.questID, false end
        return answer
    end


    if st.set and not st.backedOff and not InWorldPin.IsOurTrackingIntact() then
        if answer == "noplace" then st.noticeGiven = true end
        InWorldPin.BackOff("user")
    end
    return answer
end

local function onSuperTrackingChanged()
    local st = InWorldPin.state
    local before, quest = st.focusQuest, focusedQuest()
    st.focusQuest = quest

    if st.suppressed and st.ignore == 0 and currentWaypoint() == nil then st.pinClearedInFight = true end
    local own = st.ignore > 0 or (quest ~= nil and quest == st.ownQuest)
    if quest ~= st.ownQuest then st.ownQuest = nil end
    if quest and quest ~= before and not own and followsSelection() then
        st.selected = { questID = quest, at = now() }
        if not (C_Timer and C_Timer.NewTimer) then
            InWorldPin.DecideSelection()
        elseif not st.selectTimer then
            st.selectTimer = C_Timer.NewTimer(0, InWorldPin.DecideSelection)
        end
        return
    end



    if st.selected then return end
    if st.ignore > 0 or not st.set or st.backedOff then return end
    if InWorldPin.IsOurTrackingIntact() then return end
    InWorldPin.BackOff("user")
end

local function onSettingsChanged(_, key, value)
    if key == "inWorldPin" or key == "perf.guidanceEnabled" or key == "*" then
        if not InWorldPin.IsEnabled() then
            InWorldPin.Restore("disabled")
        elseif InWorldPin.state.route and InWorldPin.state.progress then
            InWorldPin.Update(true)
        end
    elseif key == "combatMode" and InWorldPin.state.inCombat then
        onCombatState(nil, true)
    end
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
        E:RegisterWoW("SUPER_TRACKING_CHANGED", onSuperTrackingChanged, InWorldPin)
        E:RegisterWoW("USER_WAYPOINT_UPDATED", onSuperTrackingChanged, InWorldPin)

        local function questEvent() quietFor(InWorldPin.QUEST_QUIET) end



        local function questLeft(_, questID)
            quietFor(InWorldPin.QUEST_QUIET)
            local st = InWorldPin.state
            if questID ~= nil and questID == st.ownQuest and focusedQuest() == questID then
                st.ownQuest = nil
                withIgnoredEvents(C_SuperTrack.SetSuperTrackedQuestID, 0)
            end
        end
        E:RegisterWoW("QUEST_ACCEPTED", questEvent, InWorldPin)
        E:RegisterWoW("QUEST_TURNED_IN", questLeft, InWorldPin)
        E:RegisterWoW("QUEST_REMOVED", questLeft, InWorldPin)

        E:Register("WORLD_ENTERED", function()
            quietFor(InWorldPin.WORLD_QUIET)
            InWorldPin.ClearLeftover(true)
        end, InWorldPin)
    end
    InWorldPin.state.focusQuest = focusedQuest()
    InWorldPin.state.inCombat = InCombatLockdown and InCombatLockdown() or false
    InWorldPin.ClearLeftover(false)
    return InWorldPin
end
