









































local ADDON_NAME, FGPS = ...

local L = FGPS.L
local type, pairs, ipairs, tostring, tonumber, pcall = type, pairs, ipairs, tostring, tonumber, pcall
local sqrt, abs, floor, ceil, min, max, sin, atan2, exp, format = math.sqrt, math.abs, math.floor, math.ceil, math.min, math.max, math.sin, math.atan2, math.exp, string.format
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
        reachedAt = nil,
        arrowHidden = false,
        playerZ = nil,
        playerZInst = nil,
        playerZX = nil,
        playerZY = nil,
        canopyInst = nil,
        canopyX = nil,
        canopyY = nil,
        canopyRetryAt = nil,
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
    GLIDE_DECAY = 14,
    GLIDE_MAX_PIXELS = 140,
    frameState = {
        reason = nil,
        shown = false,
        clamped = false,
        canopySnap = false,
        mode = nil,
        vertical = nil,
        distYards = nil,
        cue = nil,
        fade = 0,
        glideX = 0,
        glideY = 0,
    },
}
InWorldPin.Beacon = RoadBeacon
FGPS.UI.RoadBeacon = RoadBeacon

InWorldPin.MIN_AHEAD_YARDS = 60
InWorldPin.SIGHT_YARDS = 20
InWorldPin.SIGHT_CAP_YARDS = 200
InWorldPin.MOVE_YARDS = 30



InWorldPin.BEACON_SIGHT_YARDS = 14
InWorldPin.BEACON_FAR_SIGHT_YARDS = 6
InWorldPin.BEACON_CANYON_SIGHT_YARDS = 3.5
InWorldPin.BEACON_CAP_YARDS = 60
InWorldPin.BEACON_MIN_AHEAD_YARDS = 25
InWorldPin.BEACON_TURN_YARDS = 75
InWorldPin.BEACON_TURN_RELEASE_YARDS = 18
InWorldPin.BEACON_MOVE_YARDS = 8
InWorldPin.BEACON_CURVE_MOVE_YARDS = 3.5
InWorldPin.BEACON_HIGHRES_MOVE_YARDS = 2.5
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

local function isSecret(value)
    return value ~= nil and issecretvalue ~= nil and issecretvalue(value) == true
end

local function safeNumber(value)
    if type(value) ~= "number" or isSecret(value) then return nil end
    return value
end

local function explicitPosZ(pos)
    if type(pos) ~= "table" or pos.zInferred then return nil end
    return safeNumber(pos.z)
end

local function canSetOnMap(uiMapID)
    if type(C_Map.CanSetUserWaypointOnMap) ~= "function" then return false end
    local ok, can = pcall(C_Map.CanSetUserWaypointOnMap, uiMapID)
    return ok and can == true
end

local function makePoint(uiMapID, mx, my, z)
    if type(UiMapPoint) == "table" and type(UiMapPoint.CreateFromCoordinates) == "function" then
        local ok, point
        if z ~= nil then
            ok, point = pcall(UiMapPoint.CreateFromCoordinates, uiMapID, mx, my, z)
        else
            ok, point = pcall(UiMapPoint.CreateFromCoordinates, uiMapID, mx, my)
        end
        if ok and type(point) == "table" then
            if z ~= nil then point.z = z end
            return point
        end
    end
    local position = CreateVector2D and CreateVector2D(mx, my) or { x = mx, y = my }
    return { uiMapID = uiMapID, position = position, z = z }
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




local function remember(uiMapID, x, y, z)
    local record = { uiMapID = uiMapID, x = x, y = y, z = z, saved = InWorldPin.state.saved }
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
        if playerInst ~= nil and playerInst ~= inst then return nil end
        local bestMap = C_Map.GetBestMapForUnit("player")
        local pos = InWorldPin.state.progress and InWorldPin.state.progress.pos
        local posMap = type(pos) == "table" and (safeNumber(pos.uiMapID) or safeNumber(pos.map)) or nil
        local candidate = posMap or bestMap
        local triedBest = (candidate == bestMap)
        local guard = 0
        while candidate and guard < 6 do
            local mx, my = hbd:GetZoneCoordinatesFromWorld(x, y, candidate, false)
            if mx and my then return candidate, mx, my end
            local info = C_Map.GetMapInfo and C_Map.GetMapInfo(candidate)
            candidate = info and info.parentMapID
            if not candidate and not triedBest then
                candidate = bestMap
                triedBest = true
            end
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
    uturn = true, ramp = true, enter = true, level = true, bridge = true,
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



local function beaconSightOk(pos, count, fx, fy, cx, cy, x, y, sight)
    if count > 0 then
        if fx and (x - pos.x) * fx + (y - pos.y) * fy <= 2 then return false end
        if (x - cx) * (cx - pos.x) + (y - cy) * (cy - pos.y) < 0
            and distance(pos.x, pos.y, x, y) < distance(pos.x, pos.y, cx, cy) then
            return false
        end
    end
    return inSight(pos, count, x, y, sight)
end


local function interpBeaconSight(pos, count, fx, fy, cx, cy, tx, ty, sight)
    if count == 0 then return tx, ty, true, 1 end
    local lo, hi = 0, 1
    for _ = 1, 8 do
        local mid = (lo + hi) * 0.5
        if beaconSightOk(pos, count, fx, fy, cx, cy, cx + (tx - cx) * mid, cy + (ty - cy) * mid, sight) then
            lo = mid
        else
            hi = mid
        end
    end
    if lo <= 0.02 then return cx, cy, false, 0 end
    return cx + (tx - cx) * lo, cy + (ty - cy) * lo, true, lo
end

local function isSwimPoint(pt)
    if type(pt) ~= "table" then return false end
    return pt.k == 23 or pt.k == 5 or pt.hazard ~= nil
end



local function overSwimGrid(inst, x1, y1, x2, y2)
    local data = FGPS.Data
    local layer = data and data.water and data.water[inst]
    local s = layer and layer.s
    if not s or type(s.c) ~= "table" or not x1 or not x2 then return false end
    local cell = s.cell or 50
    local dx, dy = x2 - x1, y2 - y1
    local d = sqrt(dx * dx + dy * dy)
    if d < 18 then return false end
    local ox, oy = layer.ox or 0, layer.oy or 0
    local w, h, grid = s.w or 0, s.h or 0, s.c
    if w <= 0 or h <= 0 then return false end
    local c1, r1 = floor((x1 - ox) / cell), floor((y1 - oy) / cell)
    local c2, r2 = floor((x2 - ox) / cell), floor((y2 - oy) / cell)
    local steps = max(2, ceil(2 * d / cell))
    if steps > 64 then steps = 64 end
    for i = 1, steps - 1 do
        local t = i / steps
        local col = floor((x1 + dx * t - ox) / cell)
        local row = floor((y1 + dy * t - oy) / cell)
        if (col ~= c1 or row ~= r1) and (col ~= c2 or row ~= r2)
            and col >= 0 and row >= 0 and col < w and row < h and grid[row * w + col + 1] then
            return true
        end
    end
    return false
end

local function isWaterStretch(inst, ax, ay, prevPt, pt)
    if type(pt) ~= "table" or not pt.x or not pt.y then return false end
    if isSwimPoint(pt) then return true end
    if pt.stacked or pt.indoor or pt.climbForm then return false end
    if type(prevPt) == "table" and prevPt.stacked and type(pt.z) == "number" and type(prevPt.z) == "number"
        and abs(pt.z - prevPt.z) <= 5 then
        return false
    end
    local k = pt.k
    if k == 16 or k == 18 or k == 22 then return false end
    if inst ~= nil and ax and ay then
        local Cost = FGPS.Cost
        if Cost then
            if Cost.OverSwim and Cost.OverSwim(inst, ax, ay, pt.x, pt.y) then return true end
            if Cost.WaterShare and (Cost.WaterShare(inst, ax, ay, pt.x, pt.y) or 0) > 0 then return true end
        end
        if overSwimGrid(inst, ax, ay, pt.x, pt.y) then return true end
    end
    return false
end



local function findDryLanding(legs, startL, startP, inst)
    local curLeg = legs[startL]
    local curPts = curLeg and curLeg.points or {}
    local firstPt = curPts[startP]
    if type(firstPt) ~= "table" or not firstPt.x or not firstPt.y then return nil end

    local lastWaterPt = firstPt
    local checkChordLand = not isSwimPoint(firstPt)
    for l = startL, #legs do
        local leg = legs[l]
        if type(leg) ~= "table" or (leg.kind ~= nil and leg.kind ~= "walk") then break end
        if leg.inst ~= nil and inst ~= nil and leg.inst ~= inst then break end
        local pts = leg.points or {}
        local pFrom = (l == startL) and (startP + 1) or 1
        local nextLeg = legs[l + 1]
        local continuesWalk = type(nextLeg) == "table" and (nextLeg.kind == nil or nextLeg.kind == "walk")
            and (nextLeg.inst == nil or inst == nil or nextLeg.inst == inst)
            and (nextLeg.stopIndex or 1) == (leg.stopIndex or 1)
        for p = pFrom, #pts do
            local cand = pts[p]
            if type(cand) == "table" and cand.x and cand.y then
                if not isWaterStretch(inst, lastWaterPt.x, lastWaterPt.y, lastWaterPt, cand) then
                    if checkChordLand then
                        return firstPt.x, firstPt.y, firstPt, false, nil, true
                    end
                    local seg = distance(lastWaterPt.x, lastWaterPt.y, cand.x, cand.y)
                    local isFinal = (p == #pts) and not continuesWalk
                    if seg <= 35 then
                        return cand.x, cand.y, cand, isFinal, nil, true
                    end
                    local u = 10 / seg
                    return lastWaterPt.x + (cand.x - lastWaterPt.x) * u,
                        lastWaterPt.y + (cand.y - lastWaterPt.y) * u,
                        nil, false, nil, true
                end
                checkChordLand = false
                lastWaterPt = cand
            end
        end
        if not continuesWalk then break end
    end
    return lastWaterPt.x, lastWaterPt.y, lastWaterPt, true, nil, true
end

local function loadedGraph(inst)
    local G = FGPS.Graph
    if not G or inst == nil then return nil end
    if G.IsLoaded and not G:IsLoaded(inst) then return nil end
    return G
end

local _nbGraph, _nbMinZ, _nbMaxZ, _nbCount
local function scanNeighborHeight(nbKey, kindCode)
    if kindCode == 6 or kindCode == 7 or kindCode == 8 or kindCode == 9 or kindCode == 10 then return end
    local nz = _nbGraph:NodeHeightGuess(nbKey)
    if nz ~= nil then
        _nbCount = _nbCount + 1
        if _nbMinZ == nil or nz < _nbMinZ then _nbMinZ = nz end
        if _nbMaxZ == nil or nz > _nbMaxZ then _nbMaxZ = nz end
    end
end

local function graphNodeZ(G, key, allowStacked)
    if not G or type(key) ~= "number" or not G.NodeHeightGuess then return nil end
    local z = safeNumber(G:NodeHeightGuess(key))
    if z == nil then return nil end
    if allowStacked then return z end
    if G.NodePlace then
        local _, indoor, stacked = G:NodePlace(key)
        if indoor or stacked then return z end
    end
    if G.Neighbors then
        _nbGraph, _nbMinZ, _nbMaxZ, _nbCount = G, nil, nil, 0
        G:Neighbors(key, scanNeighborHeight)
        local nMin, nMax, nCnt = _nbMinZ, _nbMaxZ, _nbCount
        _nbGraph, _nbMinZ, _nbMaxZ = nil, nil, nil

        if nCnt >= 2 and nMax ~= nil and nMin ~= nil and (nMax - nMin) <= 6 and (z - nMax) > 22 then
            return nMax
        end
    end
    return z
end

local function pointRawZ(pt, G)
    if type(pt) ~= "table" then return nil end
    local z = safeNumber(pt.z)
    if z ~= nil then return z end
    if pt.node and G then
        return graphNodeZ(G, pt.node, pt.stacked or pt.climbForm or pt.indoor)
    end
    return nil
end

local function isMultiDeckPoint(pt)
    return type(pt) == "table" and (pt.stacked == true or pt.indoor == true)
end



local function advanceBeaconMinAhead(legs, li, pos, fx, fy, enterPoint, step, startL, startP, ax, ay, curAlong, basePoint, sightG)
    local minAhead = InWorldPin.BEACON_MIN_AHEAD_YARDS
    local deckMinAhead = 8
    local cap = InWorldPin.BEACON_CAP_YARDS
    if not ax or distance(pos.x, pos.y, ax, ay) >= minAhead or curAlong >= cap then
        return ax, ay, basePoint, false, nil, false
    end
    local bestX, bestY, bestPoint = ax, ay, basePoint
    local prevPt = basePoint
    local startZ = pointRawZ(basePoint, sightG)
    for l = startL, #legs do
        local leg = legs[l]
        if type(leg) ~= "table" or (leg.kind ~= nil and leg.kind ~= "walk") then break end
        if leg.inst ~= nil and pos.inst ~= nil and leg.inst ~= pos.inst then break end
        local points = leg.points or {}
        local pFrom = (l == startL) and startP or 1
        if prevPt == nil and pFrom > 1 and type(points[pFrom - 1]) == "table" then
            prevPt = points[pFrom - 1]
        end
        if startZ == nil and prevPt then
            startZ = pointRawZ(prevPt, sightG)
        end
        for p = pFrom, #points do
            local pt = points[p]
            if type(pt) == "table" and pt.x and pt.y then
                if isWaterStretch(pos.inst, ax, ay, prevPt, pt) then
                    if bestX and distance(pos.x, pos.y, bestX, bestY) >= minAhead then
                        return bestX, bestY, bestPoint, false, nil, false
                    end
                    return findDryLanding(legs, l, p, pos.inst)
                end
                if l == li and enterPoint and p == enterPoint then
                    return pt.x, pt.y, step, false, "step", false
                end
                local ptZ = pointRawZ(pt, sightG)
                if startZ == nil and ptZ ~= nil then
                    startZ = ptZ
                end
                local remSeg = distance(ax, ay, pt.x, pt.y)
                if remSeg > 0.001 then
                    if fx and (pt.x - ax) * fx + (pt.y - ay) * fy < -0.35 * remSeg
                        and ((pt.x - pos.x) * fx + (pt.y - pos.y) * fy <= 2
                            or distance(pos.x, pos.y, pt.x, pt.y) <= distance(pos.x, pos.y, ax, ay)) then
                        return bestX, bestY, bestPoint, false, nil, false
                    end
                    local bestDist = bestX and distance(pos.x, pos.y, bestX, bestY) or 0
                    if bestDist >= deckMinAhead then
                        if ((pt.climbForm or (prevPt and prevPt.climbForm) or isMultiDeckPoint(pt) or isMultiDeckPoint(prevPt))
                                and fx and (pt.x - ax) * fx + (pt.y - ay) * fy <= 0.01 * remSeg)
                            or (startZ ~= nil and ptZ ~= nil and abs(ptZ - startZ) > 8.5) then
                            return bestX, bestY, bestPoint, false, nil, false
                        end
                    end
                    if prevPt and bestDist >= 15 then
                        if isMultiDeckPoint(pt) ~= isMultiDeckPoint(prevPt) then
                            return bestX, bestY, bestPoint, false, nil, false
                        end
                        local prevZ = pointRawZ(prevPt, sightG)
                        if ptZ ~= nil and prevZ ~= nil and abs(ptZ - prevZ) > 12 then
                            return bestX, bestY, bestPoint, false, nil, false
                        end
                    end
                    local tx, ty, capped = pt.x, pt.y, false
                    if curAlong + remSeg >= cap then
                        local cu = (cap - curAlong) / remSeg
                        tx, ty, capped = ax + (pt.x - ax) * cu, ay + (pt.y - ay) * cu, true
                        remSeg = cap - curAlong
                    end
                    if distance(pos.x, pos.y, tx, ty) >= minAhead then
                        local lo, hi = 0, 1
                        for _ = 1, 6 do
                            local mid = (lo + hi) * 0.5
                            if distance(pos.x, pos.y, ax + (tx - ax) * mid, ay + (ty - ay) * mid) >= minAhead then
                                hi = mid
                            else
                                lo = mid
                            end
                        end
                        return ax + (tx - ax) * hi, ay + (ty - ay) * hi, nil, false, nil, false
                    end
                    bestX, bestY = tx, ty
                    bestPoint = capped and nil or pt
                    curAlong = curAlong + remSeg
                    ax, ay = tx, ty
                    if capped then return bestX, bestY, nil, false, nil, false end
                else
                    bestX, bestY, bestPoint = pt.x, pt.y, pt
                end
                prevPt = pt
            end
        end
        local nextLeg = legs[l + 1]
        if not nextLeg or (nextLeg.stopIndex or 1) ~= (leg.stopIndex or 1) then break end
    end
    return bestX, bestY, bestPoint, bestPoint ~= nil, nil, false
end









local _sightPos = {}

local function sightTarget(route, progress, pos, useBeacon)
    local legs = route.legs
    local li = progress.legIndex or 1
    local sight = useBeacon and InWorldPin.BEACON_SIGHT_YARDS or InWorldPin.SIGHT_YARDS
    local cap = useBeacon and InWorldPin.BEACON_CAP_YARDS or InWorldPin.SIGHT_CAP_YARDS
    local minDryAhead = InWorldPin.BEACON_MIN_AHEAD_YARDS
    local turnCap = useBeacon and InWorldPin.BEACON_TURN_YARDS or nil
    local turnRelease = useBeacon and InWorldPin.BEACON_TURN_RELEASE_YARDS or 0
    local step = useBeacon and progress.currentStep or nil
    local turnPoint = (type(step) == "table" and step.legIndex == li and TURN_STEP_KINDS[step.kind]
        and type(step.pointIndex) == "number") and step.pointIndex or nil
    local enterPoint = (turnPoint and step.kind == "enter") and turnPoint or nil
    local count = 0
    local bestX, bestY, bestPoint
    local fx, fy
    local sightPos = pos
    local along, cx, cy = 0, pos.x, pos.y
    local st = InWorldPin.state
    local baseZ = explicitPosZ(pos) or safeNumber(progress.playerZ)
        or (st.playerZInst == pos.inst and safeNumber(st.playerZ))
        or safeNumber(pos.zHint)
    local sightG = useBeacon and loadedGraph(pos.inst) or nil
    local minSightZ, maxSightZ
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
        local prevPt = (startP > 1 and type(points[startP - 1]) == "table") and points[startP - 1] or bestPoint
        if l == li and useBeacon then
            local curPt = type(points[startP]) == "table" and points[startP] or nil
            if not isMultiDeckPoint(prevPt) and not isMultiDeckPoint(curPt) then
                local ax, ay
                if type(progress.alongYards) == "number" and FGPS.Route and FGPS.Route.PointAlong and #points >= 2 then
                    ax, ay = FGPS.Route.PointAlong(leg, progress.alongYards)
                elseif prevPt and curPt and prevPt.x and prevPt.y and curPt.x and curPt.y then
                    local vx, vy = curPt.x - prevPt.x, curPt.y - prevPt.y
                    local len2 = vx * vx + vy * vy
                    if len2 > 0 then
                        local t = ((pos.x - prevPt.x) * vx + (pos.y - prevPt.y) * vy) / len2
                        if t < 0 then t = 0 elseif t > 1 then t = 1 end
                        ax, ay = prevPt.x + vx * t, prevPt.y + vy * t
                    end
                end
                if type(ax) == "number" and type(ay) == "number" then
                    local perp = distance(pos.x, pos.y, ax, ay)
                    local corridor = (FGPS.Const and FGPS.Const.ROAD_CORRIDOR_YARDS) or 20
                    if perp > 0.25 and perp <= corridor then
                        _sightPos.inst, _sightPos.x, _sightPos.y = pos.inst, ax, ay
                        sightPos = _sightPos
                        cx, cy = ax, ay
                    end
                end
            end
        end
        if baseZ == nil and prevPt then baseZ = pointRawZ(prevPt, sightG) end
        if baseZ ~= nil and minSightZ == nil then minSightZ, maxSightZ = baseZ, baseZ end
        for p = startP, #points do
            local pt = points[p]
            if type(pt) == "table" and pt.x and pt.y then
                if isWaterStretch(pos.inst, cx, cy, prevPt, pt)
                    or (l == li and p == startP and sightPos ~= pos and isWaterStretch(pos.inst, pos.x, pos.y, prevPt, pt)) then
                    if bestX and distance(pos.x, pos.y, bestX, bestY) >= minDryAhead then
                        return bestX, bestY, bestPoint, false, nil, false
                    end
                    return findDryLanding(legs, l, p, pos.inst)
                end
                local ptZ = useBeacon and pointRawZ(pt, sightG) or safeNumber(pt.z)
                if baseZ == nil and ptZ ~= nil then
                    baseZ, minSightZ, maxSightZ = ptZ, ptZ, ptZ
                end
                local seg = distance(cx, cy, pt.x, pt.y)
                if not fx then
                    if seg > 0.5 then
                        fx, fy = (pt.x - cx) / seg, (pt.y - cy) / seg
                    elseif p > 1 and type(points[p - 1]) == "table" and points[p - 1].x then
                        local pd = distance(points[p - 1].x, points[p - 1].y, pt.x, pt.y)
                        if pd > 0.5 then fx, fy = (pt.x - points[p - 1].x) / pd, (pt.y - points[p - 1].y) / pd end
                    end
                end
                if not useBeacon then
                    local multiDeck = isMultiDeckPoint(pt) or isMultiDeckPoint(prevPt)
                        or pt.climbForm or (prevPt and prevPt.climbForm)
                    local pinSight = multiDeck and 4.5 or sight
                    if bestX and distance(pos.x, pos.y, bestX, bestY) >= 8 then
                        if (multiDeck and fx and (pt.x - cx) * fx + (pt.y - cy) * fy <= 0.01 * seg)
                            or (baseZ ~= nil and ptZ ~= nil and abs(ptZ - baseZ) > 8.5) then
                            return bestX, bestY, bestPoint
                        end
                    end
                    if along + seg >= cap then
                        local u = (cap - along) / seg
                        local x, y = cx + (pt.x - cx) * u, cy + (pt.y - cy) * u
                        if inSight(pos, count, x, y, pinSight) then return x, y, nil end
                        return bestX, bestY, bestPoint
                    end
                    if not inSight(pos, count, pt.x, pt.y, pinSight) then return bestX, bestY, bestPoint end
                    bestX, bestY, bestPoint = pt.x, pt.y, pt
                    count = count + 1
                    passed[count] = pt
                    along, cx, cy = along + seg, pt.x, pt.y
                else
                    local lockTurn = l == li and turnPoint and p == turnPoint
                        and (enterPoint ~= nil or along + seg > turnRelease)
                    local segSight = sight
                    if not lockTurn then
                        local multiDeck = isMultiDeckPoint(pt) or isMultiDeckPoint(prevPt)
                            or pt.climbForm or (prevPt and prevPt.climbForm)
                        local tightCorridor = multiDeck
                            or pt.k == 1 or pt.k == 2 or pt.k == 16 or pt.k == 22
                            or (baseZ ~= nil and ptZ ~= nil and abs(ptZ - baseZ) > 4.5)
                        if multiDeck or (tightCorridor and along + seg > 28) then
                            segSight = InWorldPin.BEACON_CANYON_SIGHT_YARDS or 3.5
                        elseif along + seg > 38 then
                            segSight = InWorldPin.BEACON_FAR_SIGHT_YARDS or 6
                        end
                    end
                    local crestOrDip = baseZ ~= nil and ptZ ~= nil and (
                        (maxSightZ ~= nil and (maxSightZ - baseZ) >= 3.0 and (maxSightZ - ptZ) >= 2.0)
                        or (minSightZ ~= nil and (baseZ - minSightZ) >= 3.0 and (ptZ - minSightZ) >= 2.0)
                    )
                    if not lockTurn and bestX and distance(pos.x, pos.y, bestX, bestY) >= minDryAhead then
                        if (prevPt and isMultiDeckPoint(pt) ~= isMultiDeckPoint(prevPt))
                            or (baseZ ~= nil and ptZ ~= nil and abs(ptZ - baseZ) > 8.5)
                            or crestOrDip then
                            return bestX, bestY, bestPoint, false, nil, false
                        end
                    elseif not lockTurn and crestOrDip and along + seg > minDryAhead and seg > 0.001 then
                        local u = (minDryAhead - along) / seg
                        local x, y = cx + (pt.x - cx) * u, cy + (pt.y - cy) * u
                        if beaconSightOk(sightPos, count, fx, fy, cx, cy, x, y, segSight) then
                            return advanceBeaconMinAhead(legs, li, pos, fx, fy, enterPoint, step, l, p, x, y, minDryAhead, nil, sightG)
                        end
                        local ix, iy, moved, frac = interpBeaconSight(sightPos, count, fx, fy, cx, cy, x, y, segSight)
                        return advanceBeaconMinAhead(legs, li, pos, fx, fy, enterPoint, step, l, p,
                            ix, iy, along + (minDryAhead - along) * frac, moved and nil or bestPoint, sightG)
                    end
                    if ptZ ~= nil then
                        if minSightZ == nil or ptZ < minSightZ then minSightZ = ptZ end
                        if maxSightZ == nil or ptZ > maxSightZ then maxSightZ = ptZ end
                    end
                    if lockTurn and along + seg <= turnCap then
                        if beaconSightOk(sightPos, count, fx, fy, cx, cy, pt.x, pt.y, sight) then
                            return pt.x, pt.y, step, false, "step", false
                        end
                        local ix, iy, moved, frac = interpBeaconSight(sightPos, count, fx, fy, cx, cy, pt.x, pt.y, sight)
                        return advanceBeaconMinAhead(legs, li, pos, fx, fy, enterPoint, step, l, p,
                            ix, iy, along + seg * frac, moved and nil or bestPoint, sightG)
                    end
                    if along + seg >= cap then
                        local u = (cap - along) / seg
                        local x, y = cx + (pt.x - cx) * u, cy + (pt.y - cy) * u
                        if beaconSightOk(sightPos, count, fx, fy, cx, cy, x, y, segSight) then
                            return advanceBeaconMinAhead(legs, li, pos, fx, fy, enterPoint, step, l, p, x, y, cap, nil, sightG)
                        end
                        local ix, iy, moved, frac = interpBeaconSight(sightPos, count, fx, fy, cx, cy, x, y, segSight)
                        return advanceBeaconMinAhead(legs, li, pos, fx, fy, enterPoint, step, l, p,
                            ix, iy, along + (cap - along) * frac, moved and nil or bestPoint, sightG)
                    end
                    if not beaconSightOk(sightPos, count, fx, fy, cx, cy, pt.x, pt.y, segSight) then
                        local ix, iy, moved, frac = interpBeaconSight(sightPos, count, fx, fy, cx, cy, pt.x, pt.y, segSight)
                        return advanceBeaconMinAhead(legs, li, pos, fx, fy, enterPoint, step, l, p,
                            ix, iy, along + seg * frac, moved and nil or bestPoint, sightG)
                    end
                    bestX, bestY, bestPoint = pt.x, pt.y, pt
                    count = count + 1
                    passed[count] = pt
                    along, cx, cy = along + seg, pt.x, pt.y
                end
                prevPt = pt
            end
        end
        local nextLeg = legs[l + 1]
        if not nextLeg or (nextLeg.stopIndex or 1) ~= (leg.stopIndex or 1) then break end
    end

    return bestX, bestY, bestPoint, bestPoint ~= nil, nil, false
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
            local x, y, point, ends, hitKind, waterCrossing = sightTarget(route, progress, pos, useBeacon)
            if x then return inst, x, y, hitKind or (ends and "stop" or "point"), point, waterCrossing or nil end
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
                if type(pt) == "table" and pt.x and pt.y and not isSwimPoint(pt) then
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




local _deckTargetZ
local function isIndoorOrStackedNode(key)
    local G = FGPS.Graph
    if not G or not G.NodePlace then return false end
    local _, indoor, stacked = G:NodePlace(key)
    if not indoor and not stacked then return false end
    if _deckTargetZ ~= nil and G.NodeHeightGuess then
        local nz = G:NodeHeightGuess(key)
        if nz ~= nil and nz < _deckTargetZ - 6 then return false end
    end
    return true
end

local _psGraph, _psIndoor
local function matchPlayerPlace(key)
    if not _psGraph or not _psGraph.NodePlace then return true end
    local _, isInd = _psGraph:NodePlace(key)
    if _psIndoor == false then return not isInd end
    return isInd == true
end

local function playerSurfaceZ(G, inst, x, y, hintZ)
    if not (G and G.NearestKey and inst ~= nil and x and y) then return nil end
    local indoor
    local nav = FGPS.Navigator
    if nav and type(nav.place) == "table" and nav.place.indoor ~= nil then
        indoor = nav.place.indoor
    elseif IsIndoors then
        local ok, ind = pcall(IsIndoors)
        if ok and not isSecret(ind) then indoor = ind and true or false end
    end
    local key
    if indoor ~= nil and G.NodePlace then
        _psGraph, _psIndoor = G, indoor
        key = G:NearestKey(inst, x, y, 25, matchPlayerPlace, hintZ)
        _psGraph, _psIndoor = nil, nil
        if not key and indoor == true then
            key = G:NearestKey(inst, x, y, 25, nil, hintZ)
        end
    else
        key = G:NearestKey(inst, x, y, 25, nil, hintZ)
    end
    if key then return graphNodeZ(G, key, false) end
    return nil
end

local function legPointZ(points, idx, G, inst, hintZ)
    local pt = points[idx]
    if type(pt) ~= "table" or not pt.x or not pt.y then return nil end
    local z = pointRawZ(pt, G)
    local allowSpike = pt.stacked or pt.climbForm or pt.indoor
    if z ~= nil and allowSpike then return z end

    local prevPt, prevZ
    for i = idx - 1, max(1, idx - 6), -1 do
        local p = points[i]
        local pz = pointRawZ(p, G)
        if pz ~= nil and p.x and p.y then
            prevPt, prevZ = p, pz
            break
        end
    end
    local nextPt, nextZ
    for i = idx + 1, min(#points, idx + 6) do
        local p = points[i]
        local nz = pointRawZ(p, G)
        if nz ~= nil and p.x and p.y then
            nextPt, nextZ = p, nz
            break
        end
    end

    if z ~= nil then
        if prevPt and nextPt then
            local dPrev = distance(prevPt.x, prevPt.y, pt.x, pt.y)
            local dNext = distance(pt.x, pt.y, nextPt.x, nextPt.y)
            local span = dPrev + dNext
            local interp = span > 0.01 and (prevZ * dNext + nextZ * dPrev) / span or (prevZ + nextZ) * 0.5
            local hi = max(prevZ, nextZ)
            if (z - hi) > 22 and abs(prevZ - nextZ) <= 8 and (z - interp) > max(22, 0.45 * min(dPrev, dNext)) then
                return interp
            end
        end
        return z
    end

    if idx == 1 and prevPt == nil then
        if pt._originZ ~= nil then
            if type(pt._originZ) == "number" then return pt._originZ end
        elseif G and inst ~= nil then
            local oz = playerSurfaceZ(G, inst, pt.x, pt.y, hintZ)
            pt._originZ = oz or false
            if oz ~= nil then return oz end
        end
        if nextPt and (nextPt.stacked or nextPt.climbForm or nextPt.indoor)
            and distance(pt.x, pt.y, nextPt.x, nextPt.y) > 20 then
            return nil
        end
    end

    if prevPt and nextPt then
        local dPrev = distance(prevPt.x, prevPt.y, pt.x, pt.y)
        local dNext = distance(pt.x, pt.y, nextPt.x, nextPt.y)
        local span = dPrev + dNext
        if span > 0.01 then
            return prevZ + (nextZ - prevZ) * (dPrev / span)
        end
        return (prevZ + nextZ) * 0.5
    elseif prevPt and distance(prevPt.x, prevPt.y, pt.x, pt.y) <= 120 then
        return prevZ
    elseif nextPt and distance(pt.x, pt.y, nextPt.x, nextPt.y) <= 120 then
        return nextZ
    end
    return nil
end

local function interpLegZ(leg, x, y, startIdx, G, hintZ)
    local points = leg and leg.points
    if type(points) ~= "table" or #points == 0 then return nil end
    local inst = leg.inst
    if #points == 1 then
        local pt = points[1]
        if pt and pt.x and pt.y and distance(x, y, pt.x, pt.y) <= 25 then
            return legPointZ(points, 1, G, inst, hintZ), 1, 0
        end
        return nil
    end
    local nSeg = #points - 1
    local first = max(1, min(nSeg, (startIdx or 1) - 2))
    local nearHi = min(nSeg, first + 18)
    local bestIdx, bestT, bestScore, bestDistSq
    for pass = 1, 3 do
        local lo, hi
        if pass == 1 then lo, hi = first, nearHi
        elseif pass == 2 then lo, hi = nearHi + 1, nSeg
        else lo, hi = 1, first - 1 end
        if lo <= hi then
            for i = lo, hi do
                local a, b = points[i], points[i + 1]
                if a and b and a.x and a.y and b.x and b.y then
                    local vx, vy = b.x - a.x, b.y - a.y
                    local lenSq = vx * vx + vy * vy
                    local t = 0
                    if lenSq > 1e-6 then
                        t = ((x - a.x) * vx + (y - a.y) * vy) / lenSq
                        if t < 0 then t = 0 elseif t > 1 then t = 1 end
                    end
                    local px, py = a.x + vx * t, a.y + vy * t
                    local dx, dy = x - px, y - py
                    local dSq = dx * dx + dy * dy
                    local score = dSq
                    if hintZ ~= nil and dSq <= 625 then
                        local az, bz = pointRawZ(a, G), pointRawZ(b, G)
                        local ez = (az and bz) and (az + (bz - az) * t) or (az or bz)
                        if ez ~= nil and abs(ez - hintZ) > 12 then
                            local zDiff = abs(ez - hintZ) - 12
                            score = score + zDiff * zDiff * 4
                        end
                    end
                    if bestScore == nil or score < bestScore then
                        bestScore, bestDistSq, bestIdx, bestT = score, dSq, i, t
                        if score <= 0.25 then break end
                    end
                end
            end
        end
        if bestDistSq and bestDistSq <= 4 and (bestScore or 0) <= 16 then break end
    end
    if not bestIdx or bestDistSq > 625 then return nil end
    local za = legPointZ(points, bestIdx, G, inst, hintZ)
    local zb = legPointZ(points, bestIdx + 1, G, inst, hintZ)
    if za ~= nil and zb ~= nil then
        return za + (zb - za) * bestT, bestIdx, bestT
    end
    return (za ~= nil and za or zb), bestIdx, bestT
end

function InWorldPin.ResolveTargetZ(route, progress, inst, x, y, kind, source)
    if not x or not y then return nil end
    local G = loadedGraph(inst)
    local legs = type(route) == "table" and route.legs or nil
    local li = type(progress) == "table" and progress.legIndex or 1
    local leg = type(legs) == "table" and legs[li] or nil
    if leg and leg.inst ~= nil and inst ~= nil and leg.inst ~= inst and leg.toInst ~= inst then
        leg = nil
    end
    local points = leg and leg.points
    local pStart = (type(progress) == "table" and progress.pointIndex) or 1

    if type(source) == "table" then
        if kind == "step" and type(source.pointIndex) == "number" and type(points) == "table" then
            local sz = safeNumber(source.z)
            if sz ~= nil and (source.stacked or source.climbForm or source.indoor or source.kind == "level" or source.kind == "ramp") then
                return sz
            end
            local lz = legPointZ(points, source.pointIndex, G, inst)
            if lz ~= nil then return lz end
        elseif type(points) == "table" then
            for i = max(1, pStart - 1), #points do
                if points[i] == source then
                    local pz = legPointZ(points, i, G, inst)
                    if pz ~= nil then return pz end
                    break
                end
            end
        end
        local sz = safeNumber(source.z)
        if sz ~= nil then return sz end
        if source.node and G then
            local nz = graphNodeZ(G, source.node, source.stacked or source.climbForm or source.indoor)
            if nz ~= nil then return nz end
        end
    end

    local pos = type(progress) == "table" and progress.pos or nil
    local st = InWorldPin.state
    local hintZ = (pos and (pos.inst == nil or pos.inst == inst) and explicitPosZ(pos))
        or (type(progress) == "table" and (not pos or pos.inst == nil or pos.inst == inst) and safeNumber(progress.playerZ))
        or (st.playerZInst == inst and safeNumber(st.playerZ))
        or (pos and (pos.inst == nil or pos.inst == inst) and (safeNumber(pos.zHint) or safeNumber(pos.z)))
        or nil
    if leg then
        local iz = interpLegZ(leg, x, y, pStart, G, hintZ)
        if iz ~= nil then return iz end
        if type(legs) == "table" then
            for l = li + 1, #legs do
                local nextLeg = legs[l]
                if type(nextLeg) ~= "table" or (nextLeg.kind ~= nil and nextLeg.kind ~= "walk")
                    or (nextLeg.inst ~= nil and inst ~= nil and nextLeg.inst ~= inst) then
                    break
                end
                iz = interpLegZ(nextLeg, x, y, 1, G, hintZ)
                if iz ~= nil then return iz end
            end
        end
    end

    if kind == "stop" and type(route) == "table" and type(route.stops) == "table" then
        local stopIdx = (leg and leg.stopIndex) or #route.stops
        local stop = route.stops[stopIdx]
        local dest = stop and stop.dest
        local dz = dest and safeNumber(dest.z)
        if dz ~= nil and dest.x and dest.y and distance(x, y, dest.x, dest.y) <= 20 then
            return dz
        end
    end

    if G and G.NearestKey then
        local key = G:NearestKey(inst, x, y, 25, nil, hintZ)
        if key then
            return graphNodeZ(G, key, false)
        end
    end
    return nil
end

local function resolvePlayerZ(route, progress)
    if type(progress) ~= "table" then return nil end
    local pos = progress.pos
    if type(pos) ~= "table" or not pos.x or not pos.y then return nil end
    local st = InWorldPin.state
    local pz = explicitPosZ(pos) or safeNumber(progress.playerZ)
    if pz ~= nil then
        st.playerZInst, st.playerZX, st.playerZY = pos.inst, pos.x, pos.y
        return pz
    end
    local inst = pos.inst
    local prevZ = (st.playerZInst == inst) and safeNumber(st.playerZ) or nil
    if prevZ ~= nil and st.playerZX and st.playerZY
        and distance(pos.x, pos.y, st.playerZX, st.playerZY) < 1.0 then
        return prevZ
    end
    local hintZ = prevZ or safeNumber(pos.zHint)
    local G = loadedGraph(inst)
    local legs = type(route) == "table" and route.legs or nil
    local leg = type(legs) == "table" and legs[progress.legIndex or 1] or nil
    if leg and (leg.inst == nil or inst == nil or leg.inst == inst or leg.toInst == inst) then
        local iz = interpLegZ(leg, pos.x, pos.y, progress.pointIndex or 1, G, hintZ)
        if iz ~= nil then
            st.playerZInst, st.playerZX, st.playerZY = inst, pos.x, pos.y
            return iz
        end
    end
    local nz = playerSurfaceZ(G, inst, pos.x, pos.y, hintZ)
    if nz ~= nil then
        st.playerZInst, st.playerZX, st.playerZY = inst, pos.x, pos.y
        return nz
    end
    local fallbackZ = safeNumber(pos.zHint) or safeNumber(pos.z)
    if fallbackZ ~= nil then
        st.playerZInst, st.playerZX, st.playerZY = inst, pos.x, pos.y
    end
    return fallbackZ
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






function InWorldPin.Place(uiMapID, mx, my, z)
    local placed = false
    local st = InWorldPin.state
    withIgnoredEvents("placing the pin", function()
        local had = focusedQuest()
        local wasSet = C_Map.SetUserWaypoint(makePoint(uiMapID, mx, my, z))
        placed = wasSet ~= false
        if placed then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
            if questShownOverPin() and type(C_SuperTrack.SetSuperTrackedQuestID) == "function" then
                C_SuperTrack.SetSuperTrackedQuestID(0)
            end
            if had and focusedQuest() ~= had and st.saved then st.saved.questID, st.saved.questTaken = had, true end
        end
    end)
    if placed then remember(uiMapID, mx, my, z) end
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
            C_Map.SetUserWaypoint(makePoint(saved.waypoint.uiMapID, saved.waypoint.x, saved.waypoint.y, saved.waypoint.z))
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
            withIgnoredEvents("putting back the player's pin", C_Map.SetUserWaypoint, makePoint(own.uiMapID, own.x, own.y, own.z))
        end
    end
    forget()
    st.backedOff = true
    st.set = false
    st.saved, st.carriedQuest = nil, nil
    st.target, st.targetKey, st.lastSet, st.playerZ = nil, nil, nil, nil
    st.playerZInst, st.playerZX, st.playerZY = nil, nil, nil
    st.canopyInst, st.canopyX, st.canopyY, st.canopyRetryAt = nil, nil, nil, nil
    st.suppressed, st.pinClearedInFight, st.reachedAt = false, nil, nil
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

local function notifyCallout()
    local Callout = FGPS.UI.Callout
    if Callout and Callout.Repaint then Callout.Repaint() end
end


function InWorldPin.Restore(reason)
    local st = InWorldPin.state
    if st.stopped then return end
    local wasSet = st.set
    local saved = st.saved
    if st.set and saved and not st.backedOff and apiAvailable() then
        giveBack(saved)
        forget()
        if FGPS.Log then FGPS.Log:Debug("In-world pin restored previous tracking (%s)", tostring(reason)) end
    end
    st.set = false
    st.saved, st.carriedQuest = nil, nil
    st.target, st.targetKey, st.lastSet, st.playerZ = nil, nil, nil, nil
    st.playerZInst, st.playerZX, st.playerZY = nil, nil, nil
    st.canopyInst, st.canopyX, st.canopyY, st.canopyRetryAt = nil, nil, nil, nil
    st.suppressed, st.pinClearedInFight, st.reachedAt = false, nil, nil
    RoadBeacon.Refresh()
    syncGameArrow()
    if wasSet then notifyCallout() end
end


local update
local applyTargetCues
function InWorldPin.Update(force)
    local st = InWorldPin.state
    local wasSet = st.set
    local wasUnavail = next(st.unavailableMaps) ~= nil
    local placed = update(force)
    RoadBeacon.Refresh()
    syncGameArrow()
    if st.set ~= wasSet or (next(st.unavailableMaps) ~= nil) ~= wasUnavail then
        notifyCallout()
    end
    return placed
end

update = function(force)
    local st = InWorldPin.state
    if not InWorldPin.IsEnabled() then return false end
    if st.backedOff or st.suppressed or not st.route or not st.progress then return false end
    if st.inCombat and combatPolicy() == "hide_all" then return false end
    local posNow = st.progress.pos
    if st.progress.positionAvailable == false
        or (type(posNow) == "table" and posNow.inst ~= nil and st.target and st.target.inst ~= nil and posNow.inst ~= st.target.inst) then
        if st.set then InWorldPin.Restore("position unavailable in area") end
        if type(posNow) ~= "table" or not posNow.x or st.progress.positionAvailable == false then
            return false
        end
    end
    local legs = st.route.legs
    local leg = type(legs) == "table" and legs[st.progress.legIndex or 1] or nil
    if type(leg) == "table" and (NO_WAY_KINDS[leg.kind] or (not stockPinMode() and leg.kind ~= nil and leg.kind ~= "walk")) then




        if st.set then InWorldPin.Restore("leg without a way to walk") end
        return false
    end
    st.playerZ = resolvePlayerZ(st.route, st.progress)
    local useBeacon = beaconMode()
    local inst, x, y, kind, source, waterCrossing = InWorldPin.SelectTarget(st.route, st.progress, useBeacon)
    if not inst or not x then
        if st.set then InWorldPin.Restore("no target position") end
        return false
    end




    local shown = st.target
    local moveYards = InWorldPin.MOVE_YARDS
    if useBeacon then
        local s = FGPS.DB and FGPS.DB.settings
        local r = s and s.routing
        if type(r) == "table" and r.highRes == true then
            moveYards = InWorldPin.BEACON_HIGHRES_MOVE_YARDS
        else
            moveYards = InWorldPin.BEACON_MOVE_YARDS
            local pos = st.progress and st.progress.pos
            if shown and shown.inst == inst and shown.wx and type(pos) == "table" and pos.x and pos.y then
                local ux, uy = shown.wx - pos.x, shown.wy - pos.y
                local vx, vy = x - pos.x, y - pos.y
                local ul, vl = sqrt(ux * ux + uy * uy), sqrt(vx * vx + vy * vy)
                if ul > 2 and vl > 2 and (ux * vx + uy * vy) / (ul * vl) < 0.9975 then
                    moveYards = InWorldPin.BEACON_CURVE_MOVE_YARDS
                end
            end
        end
    end
    if not force and kind == "point" and shown and shown.inst == inst and shown.wx
        and not (waterCrossing and not shown.waterCrossing)
        and distance(shown.wx, shown.wy, x, y) < moveYards then
        local pos = st.progress.pos
        local keepShown = true
        if useBeacon and type(pos) == "table" and pos.x and pos.y then
            local nx, ny = st.progress.nextX, st.progress.nextY
            if distance(pos.x, pos.y, shown.wx, shown.wy) < InWorldPin.BEACON_MIN_AHEAD_YARDS
                or (shown.wx - pos.x) * (x - pos.x) + (shown.wy - pos.y) * (y - pos.y) <= 0
                or (nx and ny and (shown.wx - pos.x) * (nx - pos.x) + (shown.wy - pos.y) * (ny - pos.y) <= 0) then
                keepShown = false
            end
        end
        if keepShown then
            x, y, source = shown.wx, shown.wy, shown.source
        end
    end
    local key = format("%d:%.0f:%.0f", inst, x, y)
    local t = now()
    local pStart = st.progress.pointIndex or 1
    local canopyHere = (st.canopyInst == inst and st.canopyX ~= nil and st.canopyY ~= nil)
    if not force and key == st.targetKey and st.lastSet and shown
        and shown.wx == x and shown.wy == y and shown.kind == kind and shown.source == source
        and shown.waterCrossing == (waterCrossing or nil)
        and (shown.canopyActive == true) == canopyHere
        and ((st.playerZ == nil) == (shown.evalPlayerZ == nil))
        and (st.playerZ == nil or abs(st.playerZ - shown.evalPlayerZ) <= 6) then
        applyTargetCues(shown, leg, pStart, st.playerZ)
        if (t - st.lastSet) < InWorldPin.REFRESH_SECONDS then return false end




        if st.set and InWorldPin.IsOurTrackingIntact() then
            st.lastSet = t
            return false
        end
    end



    local routeZ = InWorldPin.ResolveTargetZ(st.route, st.progress, inst, x, y, kind, source)
    local explicitZ = (kind ~= "point") or (waterCrossing == true)
    if not explicitZ and routeZ ~= nil then
        if type(source) == "table" and (source.stacked or source.indoor or source.climbForm) then
            explicitZ = true
        end
        local G = not explicitZ and loadedGraph(inst) or nil
        local segLen, segDz = 0, 0
        if not explicitZ and leg and type(leg.points) == "table" then
            local _, segIdx = interpLegZ(leg, x, y, pStart, G, st.playerZ)
            if segIdx then
                local a, b = leg.points[segIdx], leg.points[segIdx + 1]
                if a and b and a.x and b.x then
                    segLen = distance(a.x, a.y, b.x, b.y)
                    local za, zb = legPointZ(leg.points, segIdx, G, inst, st.playerZ), legPointZ(leg.points, segIdx + 1, G, inst, st.playerZ)
                    if za and zb then segDz = abs(zb - za) end
                end
                local bk = b and b.k
                if (a and (a.stacked or a.indoor or a.climbForm))
                    or (b and (b.stacked or b.indoor or b.climbForm))
                    or ((bk == 1 or bk == 2 or bk == 16) and segLen > 0 and segLen <= 28) then
                    explicitZ = true
                end
            end
        end
        if not explicitZ and G and G.NearestKey and G.NodePlace then
            _deckTargetZ = routeZ
            local hitKey = G:NearestKey(inst, x, y, 12, isIndoorOrStackedNode)
            _deckTargetZ = nil
            if hitKey ~= nil then
                explicitZ = true
            end
        end
        if st.canopyInst == inst and st.canopyX and st.canopyY then
            if distance(x, y, st.canopyX, st.canopyY) <= 220 then
                if not (segLen > 30 and segDz > 5.0) then
                    explicitZ = true
                    st.canopyX, st.canopyY = x, y
                end
            else
                st.canopyInst, st.canopyX, st.canopyY = nil, nil, nil
            end
        end
    elseif routeZ ~= nil and st.canopyInst == inst and st.canopyX and st.canopyY then
        if distance(x, y, st.canopyX, st.canopyY) <= 220 then
            st.canopyX, st.canopyY = x, y
        else
            st.canopyInst, st.canopyX, st.canopyY = nil, nil, nil
        end
    end
    local waypointZ = explicitZ and routeZ or nil
    canopyHere = (st.canopyInst == inst and st.canopyX ~= nil and st.canopyY ~= nil)
    local zChanged = shown ~= nil and (((shown.z == nil) ~= (waypointZ == nil))
        or (waypointZ ~= nil and shown.z ~= nil and abs(waypointZ - shown.z) > 2.5))
    if not force and not zChanged and key == st.targetKey and st.lastSet then
        if shown then
            shown.kind, shown.source, shown.waterCrossing = kind, source, waterCrossing or nil
            shown.routeZ, shown.evalPlayerZ, shown.canopyActive = routeZ, st.playerZ, canopyHere
            applyTargetCues(shown, leg, pStart, st.playerZ)
        end
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
        and ((st.target.z == nil) == (waypointZ == nil))
        and (waypointZ == nil or abs(waypointZ - st.target.z) <= 2)
        and InWorldPin.IsOurTrackingIntact() then
        st.target.kind, st.target.source = kind, source
        st.target.waterCrossing = waterCrossing or nil
        st.target.wx, st.target.wy = x, y
        st.target.z = waypointZ
        st.target.routeZ = routeZ
        st.target.evalPlayerZ = st.playerZ
        st.target.canopyActive = canopyHere
        applyTargetCues(st.target, leg, pStart, st.playerZ)
        st.targetKey = key
        st.lastSet = t
        return false
    end
    if not st.set then InWorldPin.SaveCurrent() end
    local placed = InWorldPin.Place(uiMapID, mx, my, waypointZ)
    if placed then
        st.set = true
        st.targetKey = key
        st.lastSet = t
        st.target = {
            uiMapID = uiMapID, x = mx, y = my, z = waypointZ, routeZ = routeZ,
            evalPlayerZ = st.playerZ, canopyActive = canopyHere,
            inst = inst, wx = x, wy = y,
            kind = kind, source = source, waterCrossing = waterCrossing or nil,
            vertDir = (shown and shown.inst == inst and not shown.vertGoal) and shown.vertDir or nil,
        }
        applyTargetCues(st.target, leg, pStart, st.playerZ)
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

local function clientSays(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or isSecret(value) then return nil end
    return value and true or false
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
    if progress.positionAvailable == false then return "no_position" end
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

local function isNearMultiLevel(target, leg, pStart)
    local source = target and target.source
    if type(source) == "table" and (source.stacked or source.climbForm or source.indoor) then
        return true, source.climbForm
    end
    if type(leg) == "table" and type(leg.points) == "table" and target and target.wx and target.wy then
        local pts = leg.points
        local n = #pts
        if target.kind == "stop" and n >= 1 then
            local lastPt = pts[n]
            local prevPt = n >= 2 and pts[n - 1] or nil
            if (lastPt and (lastPt.stacked or lastPt.climbForm or lastPt.indoor))
                or (prevPt and (prevPt.stacked or prevPt.climbForm or prevPt.indoor)) then
                return true, (lastPt and lastPt.climbForm) or (prevPt and prevPt.climbForm)
            end
        end
        local lo = max(1, (pStart or 1) - 2)
        local hi = min(n - 1, (pStart or 1) + 8)
        for i = lo, hi do
            local a, b = pts[i], pts[i + 1]
            if a and b and a.x and a.y and b.x and b.y
                and (a.stacked or a.climbForm or a.indoor or b.stacked or b.climbForm or b.indoor)
                and offLine(target.wx, target.wy, a.x, a.y, b.x, b.y) <= 16 then
                return true, b.climbForm or a.climbForm
            end
        end
    end
    return false, nil
end

local function elevatorStopDelta(route, progress)
    local legs = route and route.legs
    local li = progress and progress.legIndex or 1
    if type(legs) ~= "table" then return nil end
    local walkStop = legs[li] and (legs[li].stopIndex or 1) or 1
    for k = li + 1, #legs do
        local nextLeg = legs[k]
        if type(nextLeg) ~= "table" or (nextLeg.stopIndex or 1) ~= walkStop then break end
        local nk = nextLeg.kind
        if nk == "walk" then
            walkStop = nextLeg.stopIndex or walkStop
        elseif nk == "elevator" then
            local epts = nextLeg.points
            local z1 = type(epts) == "table" and epts[1] and safeNumber(epts[1].z) or nil
            local z2 = type(epts) == "table" and epts[#epts] and safeNumber(epts[#epts].z) or nil
            if z1 and z2 and z2 ~= z1 then return z2 - z1 end
            return nil
        else
            break
        end
    end
    return nil
end

applyTargetCues = function(target, leg, pStart, playerZ)
    if type(target) ~= "table" then return end
    local prevDir = not target.vertGoal and target.vertDir or nil
    local kind, source = target.kind, target.source
    target.cue, target.levelCue, target.levelDown = nil, nil, false
    target.vertDir, target.vertYards, target.vertGoal = nil, nil, false

    local st = InWorldPin.state
    local route, progress = st.route, st.progress
    local pos = progress and progress.pos
    local tz, pz = safeNumber(target.routeZ) or safeNumber(target.z), safeNumber(playerZ)
    local dz = (tz and pz) and (tz - pz) or nil
    local dist2D = (pos and pos.x and pos.y and target.wx and target.wy
        and (target.inst == nil or pos.inst == target.inst))
        and distance(pos.x, pos.y, target.wx, target.wy) or nil
    local isMulti, form = isNearMultiLevel(target, leg, pStart)

    if kind == "step" and type(source) == "table" then
        local base = source.shortText or source.text
        local joined = source.joined
        local jLevel
        if type(joined) == "table" and #joined > 0 then
            local j1 = joined[1]
            if type(j1) == "table" and (j1.kind == "level" or j1.kind == "ramp") then jLevel = j1 end
            local jText = type(j1) == "table" and (j1.shortText or j1.text) or nil
            if type(jText) == "string" and jText ~= "" then
                local low = (FGPS.Util and FGPS.Util.Lower and FGPS.Util.Lower(jText:sub(1, 1)) or jText:sub(1, 1):lower()) .. jText:sub(2)
                local full = (type(base) == "string" and base ~= "") and format(L["%s, then %s"], base, low) or jText
                if (TURN_SIDE[source.kind] or source.kind == "uturn") and #full > 30 then
                    base = jText
                else
                    base = full
                end
            end
        end
        target.cue = truncateCue(base)
        if source.kind == "level" or source.kind == "ramp" then
            local sdz = safeNumber(source.dz)
            if source.up ~= nil then
                target.levelDown = (source.up == false)
            elseif sdz ~= nil and sdz ~= 0 then
                target.levelDown = sdz < 0
            elseif dz ~= nil then
                target.levelDown = dz < -3
            end
            target.vertDir = target.levelDown and "down" or "up"
            if dz ~= nil and ((target.levelDown and dz <= -4) or (not target.levelDown and dz >= 4)) then
                target.vertYards = abs(dz)
            elseif sdz ~= nil and abs(sdz) >= 4 then
                target.vertYards = abs(sdz)
            end
            return
        elseif jLevel and jLevel.up ~= nil then
            local down = (jLevel.up == false)
            target.vertDir = down and "down" or "up"
            local jdz = safeNumber(jLevel.dz)
            if jdz ~= nil and abs(jdz) >= 4 then
                target.vertYards = abs(jdz)
            elseif dz ~= nil and abs(dz) >= 4 then
                target.vertYards = abs(dz)
            end
            return
        end
    end

    if kind == "stop" and (dz == nil or abs(dz) < 6) then
        local edz = elevatorStopDelta(route, progress)
        if edz ~= nil then
            target.vertDir = edz < 0 and "down" or "up"
            if abs(edz) >= 4 then target.vertYards = abs(edz) end
            return
        end
    end

    if not target.waterCrossing and dz ~= nil then
        local absDz = abs(dz)
        local candDir = dz < 0 and "down" or "up"
        local sameDir = (prevDir == candDir)
        if isMulti then
            if absDz >= (sameDir and 4.5 or 6.0) then
                target.vertDir, target.vertYards = candDir, absDz
                if kind == "point" then
                    target.levelDown = dz < 0
                    if form == "stairs" then
                        target.levelCue = dz > 0 and L["Take the stairs up"] or L["Take the stairs down"]
                    elseif form == "ramp" then
                        target.levelCue = L["Follow the ramp"]
                    else
                        target.levelCue = dz > 0 and L["Go up to the upper level"] or L["Go down to the lower level"]
                    end
                end
                return
            end
        else
            local minDz = sameDir and 5.5 or 7.5
            local bigDz = sameDir and 9.5 or 11.5
            local minSlope = sameDir and 0.15 or 0.20
            if absDz >= minDz and (absDz >= bigDz
                or (dist2D ~= nil and absDz / max(dist2D, 1) >= minSlope)
                or (dist2D == nil and absDz >= 9.0)) then
                target.vertDir, target.vertYards = candDir, absDz
                return
            end
        end
    end



    if kind ~= "stop" and pz ~= nil and pos and pos.x and pos.y and type(route) == "table" and type(route.stops) == "table" then
        local stopIdx = (leg and leg.stopIndex) or #route.stops
        local stop = route.stops[stopIdx]
        local dest = stop and (stop.dest or stop)
        local endLeg = (stop and type(stop.legTo) == "number" and type(route.legs) == "table") and route.legs[stop.legTo] or leg
        local endPts = (type(endLeg) == "table" and (endLeg.kind == nil or endLeg.kind == "walk")) and endLeg.points or nil
        local endPt = (type(endPts) == "table" and #endPts >= 1) and endPts[#endPts] or nil
        local gx = (dest and dest.x) or (endPt and endPt.x)
        local gy = (dest and dest.y) or (endPt and endPt.y)
        local gz = (dest and safeNumber(dest.z)) or (endPt and safeNumber(endPt.z))
        if gx and gy and gz and (not dest or dest.inst == nil or dest.inst == pos.inst) then
            local goalDist2D = distance(pos.x, pos.y, gx, gy)
            local goalDz = gz - pz
            local absGoalDz = abs(goalDz)
            if goalDist2D <= 60 and absGoalDz >= 9.0
                and (absGoalDz >= 12.0 or absGoalDz / max(goalDist2D, 8) >= 0.22
                    or (endPt and (endPt.indoor or endPt.stacked))) then
                target.vertDir = goalDz < 0 and "down" or "up"
                target.vertYards = absGoalDz
                target.vertGoal = true
            end
        end
    end
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
                return TEX_FLIGHT, false, L["Flight master"], 0
            elseif nk == "boat" or nk == "ferry" then
                return TEX_BOAT, false, truncateCue(nextLeg.label) or L["boat"], 0
            elseif nk == "zeppelin" then
                return TEX_ZEPPELIN, false, truncateCue(nextLeg.label) or L["zeppelin"], 0
            elseif nk == "portal" then
                return TEX_DUNGEON, false, truncateCue(nextLeg.label), 0
            elseif nk == "elevator" then
                local epts = nextLeg.points
                local z1 = type(epts) == "table" and epts[1] and safeNumber(epts[1].z) or nil
                local z2 = type(epts) == "table" and epts[#epts] and safeNumber(epts[#epts].z) or nil
                if z1 and z2 and z2 ~= z1 then
                    return TEX_CHEVRON, false, z2 > z1 and L["Elevator up"] or L["Elevator down"], z2 < z1 and PI or 0
                end
                return TEX_STOP_RING, true, L["Take elevator"], 0
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
        return TEX_DUNGEON, false, name, 0
    end
    return TEX_STOP_RING, true, name, 0
end

local function selectVisual(target)
    local kind = target and target.kind
    local source = target and target.source
    if kind == "step" and type(source) == "table" then
        local sk = source.kind
        local cue = (target and target.cue) or truncateCue(source.shortText or source.text)
        local side = TURN_SIDE[sk]
        if side == "left" then
            return "turn", TEX_TURN, false, 0, false, cue
        elseif side == "right" then
            return "turn", TEX_TURN, true, 0, false, cue
        elseif sk == "uturn" then
            return "turn", TEX_CHEVRON, false, PI, false, cue
        elseif sk == "enter" then
            return "stop", TEX_DUNGEON, false, 0, false, cue
        elseif sk == "level" then
            local down = source.up == false or (source.up == nil and target and target.levelDown == true)
            return "turn", TEX_CHEVRON, false, down and PI or 0, false, cue
        elseif sk == "ramp" then
            local down = source.up == false or (source.up == nil and target and target.levelDown == true)
            return "turn", TEX_CHEVRON, false, down and PI or 0, false, cue or L["Follow the ramp"]
        end
        return "turn", TEX_CHEVRON, false, 0, false, cue
    end
    if kind == "stop" then
        local st = InWorldPin.state
        local tex, dotOn, cue, rot = stopVisual(st.route, st.progress)
        return "stop", tex, false, rot or 0, dotOn, cue
    end
    if target and target.waterCrossing then
        return "road", TEX_CHEVRON, false, 0, false, L["the far side"]
    end
    if target and target.levelCue then
        return "turn", TEX_CHEVRON, false, target.levelDown and PI or 0, false, target.levelCue
    end
    if target and target.vertDir and not target.vertGoal then
        return "road", TEX_CHEVRON, false, target.vertDir == "down" and PI or 0, false, nil
    end
    return "road", TEX_STOP_RING, false, 0, true, nil
end

local function elevationTint(dir)
    local Skins = FGPS.UI and FGPS.UI.Skins
    local cb = Skins and Skins.ColorSchemeName and Skins.ColorSchemeName() == "colorblind"
    if dir == "down" then
        if cb then return 0.92, 0.46, 0.08, true end
        return 1.0, 0.62, 0.30, false
    end
    if cb then return 0.34, 0.71, 0.91, true end
    return 0.56, 0.88, 1.0, false
end

local function formatElevationBadge(dir, goal, yards)
    if not dir then return nil end
    local head = goal and (dir == "down" and L["Goal below"] or L["Goal above"])
        or (dir == "down" and L["Below"] or L["Above"])
    if yards and yards >= 1 then
        local Look = FGPS.UI and FGPS.UI.Look
        local distLabel = (Look and Look.Distance and Look.Distance(yards, 1)) or format("%d yd", yards)
        return head .. " \194\183 " .. distLabel
    end
    return head
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

    local elevText
    if Look and Look.FontString then
        elevText = Look.FontString(beacon, "OVERLAY", "mapLabel")
    else
        elevText = beacon:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    end
    elevText:SetPoint("BOTTOM", beacon, "TOP", 6, 3)
    if elevText.SetWordWrap then elevText:SetWordWrap(false) end
    elevText:SetTextColor(0.56, 0.88, 1.0, 1)
    elevText:Hide()

    local elevMark = beacon:CreateTexture(nil, "OVERLAY", nil, 3)
    elevMark:SetTexture(TEX_CHEVRON)
    elevMark:SetSize(13, 13)
    elevMark:SetPoint("RIGHT", elevText, "LEFT", -2, 0)
    elevMark:SetVertexColor(0.56, 0.88, 1.0, 0.98)
    elevMark:Hide()

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
        elevText = elevText,
        elevMark = elevMark,
    }
    return frame
end

local frameState = RoadBeacon.frameState
local anchoredTo = nil
local lastTargetKey = nil
local lastTargetInst, lastTargetWX, lastTargetWY = nil, nil, nil
local lastNavX, lastNavY = nil, nil
local glideX, glideY, appliedOx, appliedOy = 0, 0, 0, 0
local lastTex, lastMirror, lastRot, lastMode = nil, nil, nil, nil
local lastYards, lastUnits, lastCue, distAtEdge = nil, nil, nil, false
local elevCache = { dir = nil, goal = false, yards = nil, units = nil, cb = nil, edge = false, dotOn = nil }
local fade, invalidFor, pinBack = 0, 0, true
local beaconClock, pulseLeft = 0, 0
local beaconHalted = false
local detachedAt
local detachedOn = setmetatable({}, { __mode = "v" })
local lastBeaconError
local detachBeacon

local function resetBeaconState()
    if (appliedOx ~= 0 or appliedOy ~= 0) and anchoredTo and RoadBeacon.beacon then
        RoadBeacon.beacon:ClearAllPoints()
        RoadBeacon.beacon:SetPoint("CENTER", anchoredTo, "CENTER", 0, 0)
    end
    anchoredTo = nil
    lastTargetKey = nil
    lastTargetInst, lastTargetWX, lastTargetWY = nil, nil, nil
    lastNavX, lastNavY = nil, nil
    glideX, glideY, appliedOx, appliedOy = 0, 0, 0, 0
    lastTex, lastMirror, lastRot, lastMode = nil, nil, nil, nil
    lastYards, lastUnits, lastCue = nil, nil, nil
    elevCache.dir, elevCache.goal, elevCache.yards = nil, false, nil
    elevCache.units, elevCache.cb, elevCache.dotOn = nil, nil, nil
    fade, invalidFor, pinBack = 0, 0, true
    pulseLeft = 0
    frameState.reason, frameState.shown, frameState.clamped, frameState.canopySnap = nil, false, false, false
    frameState.mode, frameState.vertical, frameState.distYards, frameState.cue, frameState.fade = nil, nil, nil, nil, 0
    frameState.glideX, frameState.glideY = 0, 0
    local parts = RoadBeacon.parts
    if parts then
        if distAtEdge then
            parts.distText:ClearAllPoints()
            parts.distText:SetPoint("TOP", parts.beacon, "BOTTOM", 0, -2)
            distAtEdge = false
        end
        if elevCache.edge then
            parts.elevText:ClearAllPoints()
            parts.elevText:SetPoint("BOTTOM", parts.beacon, "TOP", 6, 3)
            elevCache.edge = false
        end
    else
        distAtEdge, elevCache.edge = false, false
    end
    if RoadBeacon.beacon then RoadBeacon.beacon:Hide() end
end






local function beaconDistances(target)
    local navDist
    local Nav = C_Navigation
    if type(Nav) == "table" and type(Nav.GetDistance) == "function" then
        local ok, d = pcall(Nav.GetDistance)
        local n = ok and safeNumber(d) or nil
        if n and n > 0 then navDist = n end
    end
    if target and target.wx and target.wy then
        local st = InWorldPin.state
        local progress = st.progress
        local pos = progress and progress.pos
        if pos and pos.x and pos.y and (target.inst == nil or pos.inst == target.inst) then
            local dist2D = distance(pos.x, pos.y, target.wx, target.wy)
            local pz = explicitPosZ(pos) or safeNumber(progress.playerZ)
                or (st.playerZInst == pos.inst and st.playerZ) or safeNumber(pos.z)
            local tz = safeNumber(target.routeZ) or safeNumber(target.z)
            local dz = (tz and pz) and (tz - pz) or 0
            local trueDist = sqrt(dist2D * dist2D + dz * dz)
            local canopySnap = false
            if navDist and navDist > dist2D + 2 then
                local navDz = sqrt(max(0, navDist * navDist - dist2D * dist2D))
                local expectedDz = (tz and pz) and abs(dz) or 0
                if navDz - expectedDz > 12 then
                    canopySnap = true
                end
            end
            return trueDist, canopySnap
        end
    end
    return navDist, false
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
        lastNavX, lastNavY = nil, nil
        glideX, glideY = 0, 0
        frameState.glideX, frameState.glideY = 0, 0
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

    if fade < 1 then
        fade = min(1, fade + elapsed / BEACON_FADE_IN)
    end

    local st = InWorldPin.state
    local target = st.target
    local dist, canopySnap = beaconDistances(target)
    if canopySnap and target and target.kind == "point" and target.z == nil and target.routeZ ~= nil
        and st.set and not st.backedOff and not st.stopped and not st.suppressed and not inFight() then
        st.canopyInst, st.canopyX, st.canopyY = target.inst, target.wx, target.wy
        local tNow = now()
        if not st.canopyRetryAt or (tNow - st.canopyRetryAt) >= 0.25 then
            st.canopyRetryAt = tNow
            InWorldPin.Update(true)
            target = st.target
            navFrame = Nav.GetFrame() or navFrame
            dist, canopySnap = beaconDistances(target)
        end
    end

    local key = st.targetKey
    if key ~= nil and key ~= lastTargetKey then
        if lastTargetKey ~= nil then pulseLeft = BEACON_PULSE end
        lastTargetKey = key
    end
    local yards = dist and floor(dist + 0.5) or nil
    local clamped = clientSays(Nav.WasClampedToScreen) == true

    local cx, cy = screenCenter()
    local nx, ny
    if type(navFrame.GetCenter) == "function" then
        local ok, rx, ry = pcall(navFrame.GetCenter, navFrame)
        nx, ny = ok and safeNumber(rx), ok and safeNumber(ry)
    end

    local twx = target and target.wx or nil
    local twy = target and target.wy or nil
    local tinst = target and target.inst or nil
    local movedWorld = (twx ~= nil and twy ~= nil)
        and (lastTargetWX ~= nil and lastTargetWY ~= nil and tinst == lastTargetInst)
        and (twx ~= lastTargetWX or twy ~= lastTargetWY)
    lastTargetInst, lastTargetWX, lastTargetWY = tinst, twx, twy

    if clamped or not nx or not ny then
        glideX, glideY = 0, 0
    else
        if movedWorld and lastNavX and lastNavY then
            local jx, jy = nx - lastNavX, ny - lastNavY
            if jx * jx + jy * jy >= 4 then
                glideX = glideX + (lastNavX - nx)
                glideY = glideY + (lastNavY - ny)
                local gLen = sqrt(glideX * glideX + glideY * glideY)
                local gMax = RoadBeacon.GLIDE_MAX_PIXELS
                if gLen > gMax and gMax > 0 then
                    local s = gMax / gLen
                    glideX, glideY = glideX * s, glideY * s
                end
            end
        end
        if (glideX ~= 0 or glideY ~= 0) and elapsed > 0 then
            local decay = exp(-RoadBeacon.GLIDE_DECAY * elapsed)
            glideX, glideY = glideX * decay, glideY * decay
            if glideX * glideX + glideY * glideY < 0.12 then
                glideX, glideY = 0, 0
            end
        end
    end
    lastNavX, lastNavY = (not clamped and nx) or nil, (not clamped and ny) or nil
    frameState.glideX, frameState.glideY = glideX, glideY

    local parts = RoadBeacon.parts
    local beacon = parts.beacon
    if anchoredTo ~= navFrame then
        beacon:ClearAllPoints()
        beacon:SetPoint("CENTER", navFrame, "CENTER", glideX, glideY)
        anchoredTo = navFrame
        appliedOx, appliedOy = glideX, glideY
    elseif glideX ~= appliedOx or glideY ~= appliedOy then
        beacon:ClearAllPoints()
        beacon:SetPoint("CENTER", navFrame, "CENTER", glideX, glideY)
        appliedOx, appliedOy = glideX, glideY
    end
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

    local vertDir = target and target.vertDir or nil
    local vertGoal = target ~= nil and target.vertGoal == true
    local vertYards = (target and type(target.vertYards) == "number") and max(1, floor(target.vertYards + 0.5)) or nil
    local er, eg, eb, ecb = elevationTint(vertDir)
    if vertDir ~= elevCache.dir or vertGoal ~= elevCache.goal or vertYards ~= elevCache.yards
        or units ~= elevCache.units or ecb ~= elevCache.cb then
        elevCache.dir, elevCache.goal, elevCache.yards = vertDir, vertGoal, vertYards
        elevCache.units, elevCache.cb = units, ecb
        if vertDir then
            local badge = formatElevationBadge(vertDir, vertGoal, vertYards)
            parts.elevText:SetText(badge)
            parts.elevText:SetTextColor(er, eg, eb, 1)
            parts.elevText:Show()
            parts.elevMark:SetRotation(vertDir == "down" and PI or 0)
            parts.elevMark:SetVertexColor(er, eg, eb, 0.98)
            parts.elevMark:Show()
        else
            parts.elevText:Hide()
            parts.elevMark:Hide()
        end
    elseif vertDir and not parts.elevText:IsShown() then
        parts.elevText:Show()
        parts.elevMark:Show()
    elseif not vertDir and parts.elevText:IsShown() then
        parts.elevText:Hide()
        parts.elevMark:Hide()
    end

    frameState.clamped = clamped
    frameState.canopySnap = canopySnap
    frameState.distYards = yards
    frameState.vertical = not vertGoal and vertDir or nil

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
        if lastRot == nil or abs(angle - lastRot) > 0.005 or lastMode ~= "edge" then
            parts.edgeArrow:SetRotation(angle)
            lastRot = angle
        end
        parts.edgeArrow:Show()

        parts.distText:ClearAllPoints()
        parts.distText:SetPoint("CENTER", beacon, "CENTER", -ux * 26, -uy * 20)
        if not elevCache.edge then
            parts.elevText:ClearAllPoints()
            parts.elevText:SetPoint("TOP", parts.distText, "BOTTOM", 6, -1)
            elevCache.edge = true
        end
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
    if elevCache.edge then
        parts.elevText:ClearAllPoints()
        parts.elevText:SetPoint("BOTTOM", beacon, "TOP", 6, 3)
        elevCache.edge = false
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
    if mode ~= lastMode or dotOn ~= elevCache.dotOn then
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
            local sz = dotOn and 22 or 19
            parts.icon:SetSize(sz, sz)
            parts.icon:SetVertexColor(1.0, 0.94, 0.72, 0.95)
            parts.ring:SetVertexColor(0.94, 0.83, 0.50, 0.78)
            parts.distText:SetTextColor(0.96, 0.93, 0.84, 0.95)
        end
        lastMode, elevCache.dotOn = mode, dotOn
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
    local suppressBeam = canopySnap or (vertDir == "down" and not vertGoal)
    local beamFade = suppressBeam and 0 or 1
    if not suppressBeam and d < 14 then
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
    st.targetKey, st.lastSet, st.reachedAt = nil, nil, nil
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
    if st.reachedAt ~= nil and st.reachedAt == now() and waypointMatches(currentWaypoint(), st.target) then



        st.reachedAt = nil
        if st.navState == "active" or st.navState == "in_transit" then
            InWorldPin.Update(true)
        end
        return
    end
    InWorldPin.BackOff("user")
end



local function onDestinationSet(_, _, askedBy)
    if askedBy == "player" then InWorldPin.state.placeAskedAt = now() end
end

local function onDestinationReached()
    InWorldPin.state.reachedAt = now()
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
    st.target, st.targetKey, st.lastSet, st.playerZ = nil, nil, nil, nil
    st.playerZInst, st.playerZX, st.playerZY = nil, nil, nil
    st.canopyInst, st.canopyX, st.canopyY, st.canopyRetryAt = nil, nil, nil, nil
    st.suppressed, st.pinClearedInFight, st.reachedAt = false, nil, nil
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
        E:RegisterWoW("NAVIGATION_DESTINATION_REACHED", onDestinationReached, InWorldPin)
        E:RegisterWoW("ADDON_ACTION_FORBIDDEN", onActionBlocked, InWorldPin)
        E:RegisterWoW("ADDON_ACTION_BLOCKED", onActionBlocked, InWorldPin)
        local function onWorldState()
            local st = InWorldPin.state
            if st.set and not st.backedOff then
                local Coords = FGPS.Coords
                if Coords and Coords.IsInstanced and Coords.IsInstanced() and Coords.PlayerXY then
                    local px, py, pinst = Coords.PlayerXY()
                    if not px or not py or (st.target and st.target.inst ~= nil and pinst ~= nil and pinst ~= st.target.inst) then
                        InWorldPin.Restore("entered area without waypoint")
                        return
                    end
                end
            end
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
