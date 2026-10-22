-- Cabbie/UI/InWorldPin.lua
-- In-world guidance marker through Blizzard's own super tracking. While a route is active the
-- module places the user waypoint (C_Map.SetUserWaypoint) on the farthest place of the walk ahead
-- that a straight line from the player reaches without leaving the route by more than
-- SIGHT_YARDS, at most SIGHT_CAP_YARDS along it (on a ride: the next step at least MIN_AHEAD_YARDS
-- ahead, falling back to later points and finally the destination), and super tracks it
-- (C_SuperTrack.SetSuperTrackedUserWaypoint), so the client's SuperTrackedFrame renders a
-- 3D-projected marker with its own distance text. During a hearthstone, spell, portal or lift leg
-- there is no marker: nothing is to be walked to until it is used, so a marker already up is taken
-- down and the player's own tracking put back until the walk after it. A target that slides along
-- the road is set again only when it moves by MOVE_YARDS or more; a step, or the place where the
-- walk ahead ends, is marked where it is. For an unchanged target the module checks every
-- REFRESH_SECONDS (read-only) that its marker is still in place and sets it again only if it was
-- lost, so Blizzard's own listeners of USER_WAYPOINT_UPDATED / SUPER_TRACKING_CHANGED are not
-- woken up for nothing.
--
-- The module never fights the user: whatever was super tracked before the first placement (quest
-- or map pin) is remembered and restored on cancel or final arrival, and if SUPER_TRACKING_CHANGED
-- or USER_WAYPOINT_UPDATED arrives that we did not cause, the module backs off until the next route
-- start (or a new place the player asks for during the route), puts back the player's own map pin that the marker had taken the place of (without the
-- focus, which the player has just moved), and says so once in the call-out. It stays inert when settings.inWorldPin is false, when guidance is
-- disabled for measurement, when C_Map.CanSetUserWaypointOnMap denies the target map, and during
-- combat under the hide_all policy (the marker is released and re-asserted after combat unless the
-- user picked something else meanwhile).
--
-- One change of the focus that the module did not cause is not a reason to back off: the player
-- selects a quest by its round marker while "Follow my quests" is on and the route leads to a
-- quest. The route then changes to that quest (UI/Menus.lua) and the marker goes with it. This
-- module is the one that watches the focus, so it is the one that notices the selection, with or
-- without a marker up: the last section of this file.
--
-- No journey, no pin. The client keeps the user waypoint across /reload and logout while this
-- module starts from nothing, so the waypoint it placed is also written to the per-character saved
-- variables (char.inWorldPin). A waypoint that still matches that record while nothing is being
-- navigated is this module's own leftover and is removed (at start-up, on entering the world, and
-- when the module backs off); it is never mistaken for a pin the player set, and a pin the player
-- did set never matches the record and is never touched. The record also keeps what the marker
-- remembered of the player's own tracking, so a leftover removed after a reload gives that back.
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
        set = false,            -- true once we changed the waypoint / super tracking
        saved = nil,            -- previous super tracking state captured before the first change
        target = nil,           -- { uiMapID, x, y, inst, wx, wy }
        targetKey = nil,
        lastSet = nil,          -- time of the last placement or of the last "still in place" check
        backedOff = false,
        noticeGiven = false,    -- the back-off was said for this route
        suppressed = false,     -- released for combat, will be re-asserted
        questAtRelease = nil,   -- the quest in focus when it was released (a change from it is the player's)
        ignore = 0,             -- > 0 while our own API calls fire events
        unavailableMaps = {},
        -- The quest the player selects by its round marker (the last section of this file):
        focusQuest = nil,       -- the quest that had the game's focus when it was last looked at
        ownQuest = nil,         -- the quest this module itself gave the focus last, until the focus moves on
        quietUntil = nil,       -- until then a focus that moves is taken for the game's doing, not the player's
        quietAt = nil,          -- when that was last noted (for the log line of a decision)
        selected = nil,         -- { questID, at }: a quest that got the focus, to be decided on the next frame
        selectTimer = nil,
    },
}
FGPS.UI.InWorldPin = InWorldPin

InWorldPin.MIN_AHEAD_YARDS = 60
InWorldPin.SIGHT_YARDS = 20         -- the line from the player to the pin keeps this close to the route
InWorldPin.SIGHT_CAP_YARDS = 200    -- and the pin is never further along the route than this
InWorldPin.MOVE_YARDS = 30          -- a target that moved less than this leaves the pin where it is
InWorldPin.REFRESH_SECONDS = 5
InWorldPin.MATCH_EPSILON = 0.0005
InWorldPin.NOTICE_HOLD = 6          -- seconds the call-out says that the marker gave way
-- A quest that gets the game's focus is taken for the player's selection, except around a moment
-- at which the game may move the focus by itself: this long after a quest was accepted, handed
-- in or dropped (and in the same frame, whichever comes first), and this long after the world
-- was entered. Whether this client does move it then was not seen.
InWorldPin.QUEST_QUIET = 0.5
InWorldPin.WORLD_QUIET = 5

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
local function now()
    return GetTime and GetTime() or 0
end

-- Notes a moment after which the game may move its focus by itself, for `seconds`: a focus that
-- moves to a quest until then is not taken for the player's selection (the last section of this
-- file). Also called when this module lets go of the focus, because a game that picks a quest of
-- its own for an empty focus would otherwise start a route at the end of every route.
local function quietFor(seconds)
    local st = InWorldPin.state
    st.quietAt = now()
    local untilTime = st.quietAt + seconds
    if not st.quietUntil or untilTime > st.quietUntil then st.quietUntil = untilTime end
end

-- The quest the game has in focus, or nil.
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

-------------------------------------------------------------------------------
-- The record of our own waypoint (per character, survives /reload)
-------------------------------------------------------------------------------
local function charData()
    local db = FGPS.DB
    if db and type(db.char) == "table" then return db.char end
    return nil
end

-- { uiMapID, x, y } of the waypoint this module placed last, or nil.
function InWorldPin.Record()
    local char = charData()
    local record
    if char then record = char.inWorldPin else record = InWorldPin.volatileRecord end
    if type(record) == "table" and record.uiMapID and record.x and record.y then return record end
    return nil
end

-- The record also carries what the marker remembered of the player's own tracking (state.saved,
-- the same table, so that a quest written into it later is kept too): after a /reload or a logout
-- in the middle of a route that state would otherwise be gone, and the player's own pin with it.
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

-- World -> (uiMapID, mx, my). FGPS.Coords first; without it, HereBeDragons against the player's
-- current map and its parents (only for points in the player's instance).
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

-------------------------------------------------------------------------------
-- Target selection (pure; covered by tests)
-------------------------------------------------------------------------------
-- Legs that move the player without a way on the ground; a lift is ridden on the spot, its landing
-- under the player's feet on the map.
local NO_WAY_KINDS = { hearth = true, spell = true, portal = true, elevator = true }

-- Yards from (x, y) to the closest place on the stretch (ax, ay)-(bx, by).
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

-- Route points between the player and the candidate of the sight search. The search runs on every
-- progress tick (4 Hz), so the list is kept from one search to the next: each search counts its
-- own entries and reads only those (the ones past its count are left over from an earlier one).
local passed = {}

-- True when every one of passed[1..count] lies within SIGHT_YARDS of the line from pos to (x, y).
local function inSight(pos, count, x, y)
    local sight = InWorldPin.SIGHT_YARDS
    for i = 1, count do
        local p = passed[i]
        if offLine(p.x, p.y, pos.x, pos.y, x, y) > sight then return false end
    end
    return true
end

-- The farthest place of the walk ahead that the player can head for in a straight line: every
-- route point on the way there lies within SIGHT_YARDS of the line from the player, and it is at
-- most SIGHT_CAP_YARDS along the route. Returns x, y, the route point (nil for a place between
-- two points) and true when that point is where the walk ahead ends, or nil. The walk ends at a
-- stop and before a ride: the pin marks the flight master, not a place on the flight's straight
-- line beyond it. The next step used to be marked instead, up to 1,200 yd away, and the straight
-- line to it ran across cliffs while the arrow followed the road.
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
    -- Every point up to the end of the walk is in sight: the last of them is where it ends.
    return bestX, bestY, bestPoint, bestPoint ~= nil
end

-- Returns inst, x, y, kind ("step" | "point" | "stop"), source for the point to mark. On a walk
-- leg: the sight target above, of kind "stop" when it is where the walk ahead ends (the stop, or
-- the dock or flight master before a ride). Otherwise the first upcoming step at least
-- MIN_AHEAD_YARDS away, else the last reachable step; without steps the route polyline is used the
-- same way; finally the destination of the current instance. Nothing while the player is on a
-- hearthstone, spell, portal or lift leg (the pin sat on the inn while the text said "Use your
-- Hearthstone").
-- In the Navigator's progress table currentStep is the upcoming step (the one the player is
-- heading for) and nextStep is the one after it, so the search starts at currentStep.
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
            -- progress.pointIndex is the route point ahead of the player, so it is a candidate.
            local first = (l == legIndex) and pointIndex or 1
            local lastIndex = #points
            -- A leg that changes continent (zeppelin, boat, portal) keeps both halves in one list:
            -- the points up to leg.split are in leg.inst, the rest in leg.toInst (Nav/Router.lua).
            -- Only the half the player is in can be marked. Read in the wrong continent's frame,
            -- the Undercity tower's coordinates put a pin somewhere in Kalimdor during the ride.
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

-------------------------------------------------------------------------------
-- Placement, restore and back-off
-------------------------------------------------------------------------------
function InWorldPin.SaveCurrent()
    -- A waypoint that matches the record is a pin of ours left behind by a /reload in the middle
    -- of a route: what was remembered before it (the record's saved) is still the player's own.
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
    -- A waypoint that matches the record is a pin of ours that an earlier journey left behind (a
    -- /reload in the middle of it, or a back-off). Saved as "the player's own" it would be put
    -- back after this journey and after every later one, so it is not saved, and neither is the
    -- fact that it was super tracked.
    if point and not ours then saved.waypoint = copyPoint(point) end
    if not ours and type(C_SuperTrack.IsSuperTrackingUserWaypoint) == "function" then
        local ok, tracking = pcall(C_SuperTrack.IsSuperTrackingUserWaypoint)
        saved.trackingWaypoint = ok and tracking == true
    end
    InWorldPin.state.saved = saved
    return saved
end

-- Every change this module makes to the game's waypoint or focus goes through here. While the
-- call runs, the events it fires are this module's own doing (state.ignore), and the listener at
-- the end of this file takes none of them for the player's.
local function withIgnoredEvents(fn, ...)
    local st = InWorldPin.state
    st.ignore = st.ignore + 1
    local ok, a, b = pcall(fn, ...)
    st.ignore = st.ignore - 1
    if not ok and FGPS.Log then FGPS.Log:Error("In-world pin API call failed: %s", tostring(a)) end
    return ok, a, b
end

-- Makes a quest the one the game has in focus (the game's word for super tracking), because the
-- player asked for the way to it ("Take me there"). The game has one focus. While the marker of a
-- running route holds it, the quest is remembered instead and Restore gives it the focus when
-- that route ends: taking the focus now would look like the player taking it away, and the
-- marker would back off. Returns true when the quest has, or will get, the focus.
-- The focus this gives is Cabbie's own doing and never the player's selection of a quest: the
-- calls run with their events ignored, and the quest is kept as the one this module focused
-- (state.ownQuest) for a client that reports the change only after the call has returned.
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
    -- One focus: a map pin of the player's that still has it gives it up to the quest. Only the
    -- focus goes, the pin stays on the map.
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

-- Takes the user waypoint off the map when it is the one described by `ours` ({ uiMapID, x, y }).
-- Returns true when it was removed. A waypoint anywhere else is the player's and is left alone.
local function clearIfOurs(ours)
    if not ours or not apiAvailable() or type(C_Map.ClearUserWaypoint) ~= "function" then return false end
    if not waypointMatches(currentWaypoint(), ours) then return false end
    withIgnoredEvents(function()
        -- Only the waypoint: whatever else the player super tracks (a quest) is theirs.
        local okTracking, tracking = pcall(C_SuperTrack.IsSuperTrackingUserWaypoint or function() return false end)
        if okTracking and tracking == true then C_SuperTrack.SetSuperTrackedUserWaypoint(false) end
        C_Map.ClearUserWaypoint()
    end)
    quietFor(InWorldPin.QUEST_QUIET)
    return true
end

-- Whether a quest is still in the player's log, asked by its id (a collapsed header hides nothing
-- from that question). True when the client cannot say: a focus is then given back as before.
local function stillInLog(questID)
    if type(C_QuestLog) ~= "table" or type(C_QuestLog.IsOnQuest) ~= "function" then return true end
    local ok, on = pcall(C_QuestLog.IsOnQuest, questID)
    if not ok or (issecretvalue ~= nil and issecretvalue(on) == true) then return true end
    return on ~= false
end

-- Gives the game back what the player had before the marker touched it (`saved`, as SaveCurrent
-- made it): their own map pin and whether it had the focus, else no waypoint at all, and the
-- quest that had the focus. A quest that left the log meanwhile (dropped during the route) is not
-- given the focus again: the game would show a focus on nothing, and would not focus the next
-- quest the player accepts, which it does only while nothing has it. A quest whose hand-in ends
-- its own route is still in the log here; the listener of QUEST_TURNED_IN in Init takes that
-- focus back.
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
            -- Given back by this module: not the player selecting that quest (state.ownQuest).
            st.ownQuest = saved.questID
            C_SuperTrack.SetSuperTrackedQuestID(saved.questID)
        end
    end)
end

-- Removes a pin of ours that outlived its journey: the client keeps the user waypoint across a
-- /reload or a logout, the module does not keep its state. Does nothing while a journey is under
-- way. `final` = the client's waypoint is known to be loaded (entering the world): a record that
-- matches nothing any more is then dropped; at start-up it is kept, because the waypoint may
-- simply not be there yet. Returns true when a waypoint was removed. The record carries what the
-- marker had remembered of the player's own tracking, and that is given back with it.
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

-- True while super tracking still points at the waypoint we placed.
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

-- Gives up for the rest of this route (the user took over super tracking) and says so once per
-- route. That answers what the player just did on the screen, so it is a notice in the call-out
-- (UI/Guide.lua, which loads after this file and is looked up here) and no chat line.
function InWorldPin.BackOff(reason)
    local st = InWorldPin.state
    if st.backedOff then return end
    -- The player changed what is tracked (a quest, nothing at all) but our pin may still sit on
    -- the map: it is ours, so it goes, or it would stay at some point in the middle of the route
    -- long after the journey (Restore does nothing once backed off). When the player replaced the
    -- pin with one of their own, the waypoint no longer matches and is left exactly as it is.
    -- The game has one user waypoint, and ours had taken the place of the player's own pin: once
    -- ours is gone, theirs goes back on the map, without the focus the player has just moved.
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

-- Puts back what the user had before we touched super tracking. Safe to call repeatedly.
function InWorldPin.Restore(reason)
    local st = InWorldPin.state
    local saved = st.saved
    if st.set and saved and not st.backedOff and apiAvailable() then
        giveBack(saved)
        forget()      -- whatever waypoint exists now is the player's, or none
        quietFor(InWorldPin.QUEST_QUIET)
        if FGPS.Log then FGPS.Log:Debug("In-world pin restored previous tracking (%s)", tostring(reason)) end
    end
    st.set = false
    st.saved = nil
    st.target, st.targetKey, st.lastSet = nil, nil, nil
    st.suppressed, st.pinClearedInFight = false, nil
end

-- Places or refreshes the marker. Returns true when the waypoint was (re)placed.
function InWorldPin.Update(force)
    local st = InWorldPin.state
    if not InWorldPin.IsEnabled() then return false end
    if st.backedOff or st.suppressed or not st.route or not st.progress then return false end
    if st.inCombat and combatPolicy() == "hide_all" then return false end
    local legs = st.route.legs
    local leg = type(legs) == "table" and legs[st.progress.legIndex or 1] or nil
    if type(leg) == "table" and NO_WAY_KINDS[leg.kind] then
        -- Nothing to walk to until the hearthstone (spell, portal) is used or the lift has been
        -- ridden. A pin placed before this became the current leg stayed on the old walk, or on the
        -- shaft under the player's feet, so it comes down and the player's own tracking is put back;
        -- the walk after it saves it again and places a fresh pin. Keeping our super tracking with
        -- no marker would read the client's next tracking event as the player taking over.
        if st.set then InWorldPin.Restore("leg without a way to walk") end
        return false
    end
    local inst, x, y, kind = InWorldPin.SelectTarget(st.route, st.progress)
    if not inst or not x then return false end
    -- On a straight road the target slides forward with every step; the pin follows it only once
    -- it has moved MOVE_YARDS, so the client is not asked to move its marker four times a second.
    -- A step, or the end of the walk, is marked where it is: held back like a place on the road,
    -- the pin came to rest up to 30 yd short of the flight master while its distance read 0 yd.
    local shown = st.target
    if not force and kind == "point" and shown and shown.inst == inst and shown.wx
        and distance(shown.wx, shown.wy, x, y) < InWorldPin.MOVE_YARDS then
        x, y = shown.wx, shown.wy
    end
    local key = format("%d:%.0f:%.0f", inst, x, y)
    local t = now()
    if not force and key == st.targetKey and st.lastSet then
        if (t - st.lastSet) < InWorldPin.REFRESH_SECONDS then return false end
        -- Same target as before. Setting the waypoint again would make the client announce a
        -- change that did not happen, so only look (read-only) whether our marker is still there.
        -- A change made by the user reaches onSuperTrackingChanged and backs off; what is left
        -- here is a marker the client dropped without telling us, and only that is placed again.
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

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
local function onRouteStarted(_, route)
    local st = InWorldPin.state
    st.route = route
    st.backedOff = false
    st.noticeGiven = false
    st.unavailableMaps = {}
    st.targetKey, st.lastSet = nil, nil
    if st.progress then InWorldPin.Update(true) end
end

-- A new place the player asked for while a route runs is a re-route ("destination"), and for the
-- marker it is the next route, which the back-off notice promises: it comes back, as on
-- ROUTE_STARTED. A place the navigator sets by itself (Navigator.askedBy, read while its answer is
-- fired: a party member followed, a quest moving on) leaves a back-off as it is.
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
            -- What has the focus as the marker lets go, so that only a change made during the
            -- fight counts as the player's: a quest they had before the route may stay in focus
            -- under the waypoint, and "anything tracked" afterwards would read it as one.
            st.questAtRelease = focusedQuest()
            withIgnoredEvents(C_SuperTrack.SetSuperTrackedUserWaypoint, false)
            quietFor(InWorldPin.QUEST_QUIET)
        end
    elseif st.suppressed then
        st.suppressed = false
        -- The user may have picked something else while we were quiet; respect it: another quest
        -- in focus, or a user waypoint that is not the marker's (their own pin). No waypoint at
        -- all is no pin of theirs when the client dropped ours without a word: it is put back.
        -- The player's own clear sent USER_WAYPOINT_UPDATED (state.pinClearedInFight): theirs.
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

-------------------------------------------------------------------------------
-- The quest the player selects by its round marker
-------------------------------------------------------------------------------
-- The game has one focus, and this module is the one that watches it. When the focus moves to a
-- quest and Cabbie did not move it, the player selected that quest, as far as can be told, and
-- with "Follow my quests" on the way to it starts (UI/Menus.lua, Menus.QuestSelected, which
-- decides whether it may: never over a route to anything but quests). By the game's own interface
-- code (read, not seen in the game) the click that does it is a left click on the round marker
-- beside a quest, in the quest list or on the world map, or "Super track" in its menu; a click on
-- the marker that is selected already clears the focus, and a click on the title selects nothing.
--
-- What is Cabbie's own doing: every change made through withIgnoredEvents (the marker taking the
-- focus for its pin, the focus given back at a route's end, FocusQuest), told while the call runs
-- by state.ignore and, for a client that reports a change after the call has returned, by the
-- quest this module focused last (state.ownQuest). What may be the game's own doing, and so is
-- not taken for a selection either: a focus that moves in the frame a quest is accepted, handed
-- in or dropped or QUEST_QUIET seconds after it, in the first WORLD_QUIET seconds after the world
-- is entered, or during a fight. By the game's code it moves the focus by itself only when a quest
-- is accepted with nothing in focus, which the first of those refuses; what it does at login and
-- what other addons do was not seen. If something does, routes start that nobody asked for, and
-- "Follow my quests" in the Route block's menu is what switches that off.
--
-- The decision is made on the next frame, once: the order in which the game reports a quest that
-- is accepted and the focus that moves to it within one frame is not known.

local function inFight()
    return InCombatLockdown ~= nil and InCombatLockdown() == true
end

-- Whether a selected quest could start a route at all right now, asked before anything is kept
-- for the next frame: "Follow my quests" is on, and nothing is set or what is set leads to quests
-- alone. With the switch off nothing below this line runs, and the marker behaves as it did.
local function followsSelection()
    local Quests, Navigator = FGPS.Quests, FGPS.Navigator
    if not (Quests and Quests.FollowsMine and Quests.IsQuestRoute and Navigator and Navigator.HasAnythingSet) then return false end
    if not Quests.FollowsMine() then return false end
    return not Navigator:HasAnythingSet() or Quests.IsQuestRoute()
end

-- One line in the log per decision, so that after a session in the game it can be told which
-- moment started a route and which did not. Only the log module is asked for; nothing of it is
-- worked out without one. wasSet: something was set before the decision.
local ANSWER_WORDS = { followed = "already followed", noplace = "refused, no place known" }

local function logDecision(selected, answer, why, wasSet, fight)
    local words = answer == "started" and (wasSet and "replaced the route" or "started")
        or ANSWER_WORDS[answer] or ("refused, " .. (why or "nothing to start"))
    local quietAt = InWorldPin.state.quietAt
    local since = quietAt and format("%.1f s since the last quiet mark", selected.at - quietAt) or "no quiet mark yet"
    FGPS.Log:Info("Quest selection %d: %s; %s; %s.", selected.questID, words, since, fight and "in a fight" or "not in a fight")
end

-- The frame after a quest got the focus: decides whether that was the player's selection and
-- hands it to UI/Menus.lua, which answers "started" (the route leads to that quest now),
-- "followed" (it did already), "noplace" (said why) or nil (not wanted). Returns that answer.
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
        -- The marker goes with the route, and that quest has the focus again when the route ends.
        if st.set and st.saved and not st.backedOff then st.saved.questID, st.saved.trackingWaypoint = selected.questID, false end
        return answer
    end
    -- Nothing started: the focus was taken from the marker, as before this rule existed. Where
    -- the reason was just said ("noplace"), the marker gives way without a line of its own.
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
    -- A pin cleared while the marker is released for a fight, and not by Cabbie: the player's.
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
    -- A selection waits for its decision on the next frame (DecideSelection backs off there when
    -- nothing starts). A second event of the same change, in the same frame, must not back off
    -- now: its quiet mark would make the selection read as the game's own doing.
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

-------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------
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
        -- Moments at which the game may move its focus by itself (see the section above).
        local function questEvent() quietFor(InWorldPin.QUEST_QUIET) end
        -- A quest handed in or dropped: Nav/Quests.lua hears it first and ends a route that led to
        -- it, and the client still has the quest in its log then, so giveBack has just focused it
        -- again. That focus, given by this module, goes now; one the player gave is the game's.
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
        -- Entering the world is the first moment the client's own waypoint is certain to be loaded.
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
