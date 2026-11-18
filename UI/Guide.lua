







local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local type, format, abs, max, sqrt, pi, huge = type, string.format, math.abs, math.max, math.sqrt, math.pi, math.huge

local Guide = {
    model = nil,
    route = nil,
    progress = nil,
    navState = "idle",
    destName = nil,
    destPlace = nil,
    destStops = nil,
    notice = nil,

    noticeTimer = nil,
    finding = nil,
    atStop = nil,
    waiting = nil,
    stopped = nil,
    stoppedTimer = nil,
    noFlights = false,

    noFlightsIn = nil,
    lookTimer = nil,
    wrongSince = nil,
    wrongWay = false,
    headingFault = nil,
    resting = false,
    movedAt = nil,
    eventsBound = false,
}
FGPS.UI.Guide = Guide

Guide.MAX_ROWS = 3
Guide.CALLOUT_SECONDS = 8
Guide.CALLOUT_MIN_YARDS = 100
Guide.CALLOUT_MAX_YARDS = 200



















Guide.LOOKAHEAD_SECONDS = 1.2
Guide.LOOKAHEAD_MIN_YARDS = 10
Guide.LOOKAHEAD_MAX_YARDS = 20
Guide.HOLD_YARDS = 10
Guide.LIVE_STILL_SECONDS = 3
local HOLD_KINDS = {
    turn_slight_left = true, turn_left = true, turn_sharp_left = true,
    turn_slight_right = true, turn_right = true, turn_sharp_right = true,
    uturn = true, enter = true, level = true, ramp = true,
}


local GLYPH = {
    turn_slight_left = "slight_left", turn_left = "left", turn_sharp_left = "sharp_left",
    turn_slight_right = "slight_right", turn_right = "right", turn_sharp_right = "sharp_right",
    uturn = "uturn", ramp = "ahead",


    enter = "ahead", level = "ahead",

    hazard = "ahead",

    guarded = "ahead", guarded_round = "ahead",
    board = "board", fly = "board", hearth = "board", cast = "board",
    arrive = "arrive", stop_arrive = "arrive",
}
Guide.GLYPH = GLYPH


local SILENT = { zone = true }
local STRAIGHT = { depart = true, continue = true }


local FOLLOWED = { active = true, paused = true, in_transit = true }

local function isTurn(kind)
    return type(kind) == "string" and (kind:find("^turn_") ~= nil or kind == "uturn")
end














function Guide.ShortLandmark(name)
    if type(name) ~= "string" then return name end
    local short = name:match("^(.-)%s+%b()$")
    if short and short ~= "" then return short end
    return name
end





local function stepWords(step, landmarkOf)
    if type(step) ~= "table" then return nil end
    local text, short = step.shortText, true
    if type(text) ~= "string" or text == "" then text, short = step.text, false end
    if type(text) ~= "string" or text == "" then return nil end

    if isTurn(step.kind) and not step.toward and type(step.landmark) == "string" and step.landmark ~= "" then
        text = format(L["%s at %s"], text, landmarkOf and landmarkOf(step.landmark) or step.landmarkSaid or step.landmark)
    end


    if short and type(step.joined) == "table" then
        for i = 1, #step.joined do
            local more = step.joined[i].shortText
            if type(more) == "string" and more ~= "" then
                text = format(L["%s, then %s"], text, Util.Lower(more:sub(1, 1)) .. more:sub(2))
            end
        end
    end
    return text
end

function Guide.RowText(step)
    return stepWords(step, nil)
end

local function indexOf(steps, step)
    if type(step.index) == "number" and steps[step.index] == step then return step.index end
    for i = 1, #steps do
        if steps[i] == step then return i end
    end
    return nil
end












local function guessedOf(step)
    local yards = step.guessedYards
    return type(yards) == "number" and yards or 0
end





local function rideUnmeasured(route, step)
    local legs = route.legs
    local leg = type(legs) == "table" and type(step.legIndex) == "number" and legs[step.legIndex] or nil
    return type(leg) == "table" and leg.kind ~= "walk" and leg.unverified == true
end





local function guessedAhead(route, progress, step)
    local Route = FGPS.Route
    local kinds = Route and Route.UNVERIFIED_KINDS
    local legs = route.legs
    local leg = type(legs) == "table" and legs[progress.legIndex] or nil
    local pts = type(leg) == "table" and leg.kind == "walk" and leg.points or nil
    if not (kinds and Route.Cumulative and type(pts) == "table") then return 0 end
    local cum = Route.Cumulative(leg)
    local target = type(progress.pointIndex) == "number" and progress.pointIndex or 2
    local to = step.legIndex == progress.legIndex and type(step.pointIndex) == "number" and step.pointIndex or #pts
    if to > #pts then to = #pts end
    local along = progress.alongYards
    if type(along) ~= "number" then along = cum[max(1, target - 1)] or 0 end
    local yards = 0



    local from = max(2, target - 1)
    while from > 2 and cum[from - 1] > along do from = from - 1 end
    for i = from, to do
        if kinds[pts[i].k] and cum[i] > along then yards = yards + cum[i] - max(cum[i - 1], along) end
    end
    return yards
end





local function eachLine(route, progress, visit)
    local steps = type(route) == "table" and route.steps or nil
    local current = type(progress) == "table" and progress.currentStep or nil
    if type(steps) ~= "table" or type(current) ~= "table" then return end
    local I = FGPS.Instructions
    local least = I and I.MIN_UNVERIFIED_YARDS or 20
    local first = indexOf(steps, current)
    if not first then
        local text = Guide.RowText(current)
        if text then
            local open = (guessedOf(current) >= least and guessedAhead(route, progress, current) > 0)
                or rideUnmeasured(route, current)
            visit(current, current.index or 1, text, true, open or nil)
        end
        return
    end
    local lastKind
    local isFirst, onTheWay, behindCurrent = true, 0, 0
    for i = first, #steps do
        local step = steps[i]
        local kind = step.kind
        onTheWay = onTheWay + guessedOf(step)
        if i > first then behindCurrent = behindCurrent + guessedOf(step) end
        local text = not SILENT[kind] and not (STRAIGHT[kind] and STRAIGHT[lastKind]) and Guide.RowText(step) or nil
        if text then
            local open = onTheWay >= least
            if open and isFirst then open = guessedAhead(route, progress, current) + behindCurrent > 0 end
            open = open or rideUnmeasured(route, step)
            if visit(step, step.index or i, text, isFirst, open or nil) then return end
            lastKind, isFirst, onTheWay, behindCurrent = kind, false, 0, 0
        end
    end
end


function Guide.Rows(route, progress)
    local rows = {}
    eachLine(route, progress, function(step, key, text, isFirst, open)
        rows[#rows + 1] = { key = key, text = text, current = isFirst, kind = step.kind, open = open }
        return #rows >= Guide.MAX_ROWS
    end)
    return rows
end





function Guide.CalloutRange(speed)
    local yards = (type(speed) == "number" and speed or 0) * Guide.CALLOUT_SECONDS
    return Util.Clamp(yards, Guide.CALLOUT_MIN_YARDS, Guide.CALLOUT_MAX_YARDS)
end





local function stepTotalYards(route)
    local total = type(route) == "table" and route.totalYards or nil
    if type(total) ~= "number" then return nil end
    local legs, Route = route.legs, FGPS.Route
    if type(legs) ~= "table" or not (Route and Route.Cumulative) then return total end
    local sum, anyPoints = 0, false
    for i = 1, #legs do
        local leg = legs[i]
        if type(leg) == "table" and leg.kind == "walk" and type(leg.points) == "table" and #leg.points >= 2 then
            sum = sum + (Route.Cumulative(leg).total or 0)
            anyPoints = true
        elseif type(leg) == "table" and leg.kind ~= "hearth" and leg.kind ~= "spell" then
            if type(leg.yards) == "number" and leg.yards > 0 then
                sum = sum + leg.yards
            elseif type(leg.points) == "table" and #leg.points >= 2 then
                sum = sum + (Route.Cumulative(leg).total or 0)
            end
        end
    end
    return anyPoints and sum or total
end

function Guide.YardsToStep(route, progress, step)
    if type(progress) ~= "table" or type(step) ~= "table" then return nil end
    local total = stepTotalYards(route)
    local left, at = progress.remainingYards, step.distanceFromStart
    if type(total) == "number" and type(left) == "number" and type(at) == "number" then
        local yards = at - (total - left)
        if yards < 0 then yards = 0 end
        return yards
    end
    local pos, Coords = progress.pos, FGPS.Coords
    if type(pos) == "table" and step.x and step.y and Coords and Coords.Distance and (step.inst == nil or step.inst == pos.inst) then
        return Coords.Distance(pos.x, pos.y, step.x, step.y)
    end
    if step == progress.currentStep then return progress.distToNext end
    return nil
end






local function markedStep(route, progress)
    local step = type(progress) == "table" and progress.currentStep or nil
    if type(step) ~= "table" then return nil end
    local steps = type(route) == "table" and route.steps or nil
    local first = type(steps) == "table" and indexOf(steps, step) or nil
    if first then
        for i = first, #steps do
            if GLYPH[steps[i].kind] then return steps[i] end
        end
        return nil
    end
    return GLYPH[step.kind] and step or nil
end
Guide.MarkedStep = markedStep

local function legZAt(leg, cum, along)
    local pts = leg and leg.points
    if type(pts) ~= "table" or #pts == 0 then return nil, false end
    if #pts == 1 or type(cum) ~= "table" or type(along) ~= "number" or along <= 0 then
        local p1 = pts[1]
        return type(p1.z) == "number" and p1.z or nil,
            (p1.indoor or p1.stacked or p1.climbForm) and true or false
    end
    local n = #pts
    local s = 1
    while s < n - 1 and (cum[s + 1] or 0) <= along do s = s + 1 end
    local a, b = pts[s], pts[s + 1]
    local multi = (a and (a.indoor or a.stacked or a.climbForm)
        or (b and (b.indoor or b.stacked or b.climbForm))) and true or false
    local az, bz = a and a.z, b and b.z
    if type(az) == "number" and type(bz) == "number" then
        local span = (cum[s + 1] or cum[s]) - (cum[s] or 0)
        local t = span > 0 and (along - (cum[s] or 0)) / span or 0
        if t < 0 then t = 0 elseif t > 1 then t = 1 end
        return az + t * (bz - az), multi
    end
    return nil, multi
end

local function playerZForGuide(leg, cum, progress)
    if type(progress) ~= "table" then return nil end
    local pos = progress.pos
    if type(pos) == "table" and not pos.zInferred and type(pos.z) == "number" then
        return pos.z
    end
    if type(progress.playerZ) == "number" then return progress.playerZ end
    if leg and cum and type(progress.alongYards) == "number" then
        return (legZAt(leg, cum, progress.alongYards))
    end
    return nil
end

local function calloutVertical(route, progress, step, yardsToStep, isStepCallout)
    local legs = type(route) == "table" and route.legs or nil
    local leg = type(progress) == "table" and type(legs) == "table" and legs[progress.legIndex or 1] or nil
    if type(leg) ~= "table" or leg.kind ~= "walk" then return nil, nil, nil end
    local Route = FGPS.Route
    local pts = leg.points
    local cum = (Route and Route.Cumulative and type(pts) == "table" and #pts >= 2) and Route.Cumulative(leg) or nil
    local pz = playerZForGuide(leg, cum, progress)

    if type(step) == "table" and (isStepCallout or (type(yardsToStep) == "number" and yardsToStep <= 60)) then
        if step.kind == "level" or step.kind == "ramp" then
            local down = step.up == false or (step.up == nil and type(step.dz) == "number" and step.dz < 0)
            local vYards
            if type(step.dz) == "number" and abs(step.dz) >= 4 then
                vYards = abs(step.dz)
            elseif pz ~= nil and type(step.z) == "number" and abs(step.z - pz) >= 4 then
                vYards = abs(step.z - pz)
            end
            return down and "down" or "up", vYards, nil
        elseif type(step.joined) == "table" and #step.joined > 0 then
            local j1 = step.joined[1]
            if type(j1) == "table" and (j1.kind == "level" or j1.kind == "ramp") and j1.up ~= nil then
                local vYards = type(j1.dz) == "number" and abs(j1.dz) >= 4 and abs(j1.dz) or nil
                return j1.up == false and "down" or "up", vYards, nil
            end
        elseif step.kind == "board" and step.mode == "elevator" and (step.way == "up" or step.way == "down") then
            return step.way, nil, nil
        end
    end

    local along = type(progress.alongYards) == "number" and progress.alongYards or nil
    if pz ~= nil and cum and along ~= nil then
        local total = cum.total or 0
        local aheadAlong = along + 40
        if aheadAlong > total then aheadAlong = total end
        local span = aheadAlong - along
        if span > 1 then
            local az, multi = legZAt(leg, cum, aheadAlong)
            if not multi and type(pts) == "table" then
                local s = 1
                while s < #pts and (cum[s + 1] or 0) <= along do s = s + 1 end
                for i = s, #pts do
                    local pt = pts[i]
                    if pt and (pt.indoor or pt.stacked or pt.climbForm) then multi = true break end
                    if (cum[i] or 0) >= aheadAlong then break end
                end
            end
            if type(az) == "number" then
                local dz = az - pz
                local absDz = abs(dz)
                if multi then
                    if absDz >= 6 then return dz < 0 and "down" or "up", absDz, nil end
                elseif absDz >= 8 and (absDz >= 12 or absDz / span >= 0.22) then
                    return dz < 0 and "down" or "up", absDz, nil
                end
            end
        end
    end

    local pos = progress.pos
    if pz ~= nil and type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number"
        and type(route.stops) == "table" then
        local stopIdx = leg.stopIndex or #route.stops
        local stop = route.stops[stopIdx]
        local dest = stop and (stop.dest or stop)
        local endLeg = (stop and type(stop.legTo) == "number" and type(legs) == "table") and legs[stop.legTo] or leg
        local endPts = (type(endLeg) == "table" and endLeg.kind == "walk") and endLeg.points or nil
        local endPt = (type(endPts) == "table" and #endPts >= 1) and endPts[#endPts] or nil
        local gx = (dest and dest.x) or (endPt and endPt.x)
        local gy = (dest and dest.y) or (endPt and endPt.y)
        local gz = (dest and type(dest.z) == "number" and dest.z) or (endPt and type(endPt.z) == "number" and endPt.z) or nil
        if gx and gy and gz and (not dest or dest.inst == nil or pos.inst == nil or dest.inst == pos.inst) then
            local dx, dy = gx - pos.x, gy - pos.y
            local goalDist2D = sqrt(dx * dx + dy * dy)
            local goalDz = gz - pz
            local absGoalDz = abs(goalDz)
            if goalDist2D <= 60 and absGoalDz >= 9
                and (absGoalDz >= 12 or absGoalDz / max(goalDist2D, 8) >= 0.22
                    or (endPt and (endPt.indoor or endPt.stacked))) then
                local atStopStep = isStepCallout and type(step) == "table"
                    and (step.kind == "arrive" or step.kind == "stop_arrive")
                    and (yardsToStep or 999) <= 35
                return goalDz < 0 and "down" or "up", absGoalDz, not atStopStep or nil
            end
        end
    end
    return nil, nil, nil
end

function Guide.CalloutFor(route, progress, speed)
    local step = markedStep(route, progress)
    if not step then return nil end
    local glyph = GLYPH[step.kind]
    local text = Guide.RowText(step)
    if not text then return nil end
    local yards = Guide.YardsToStep(route, progress, step)
    if type(yards) ~= "number" or yards > Guide.CalloutRange(speed) then return nil end

    local called, open = step, nil
    eachLine(route, progress, function(lineStep, _, _, _, lineOpen)
        if lineStep == called then
            open = lineOpen
            return true
        end
    end)
    local vDir, vYards, vGoal = calloutVertical(route, progress, step, yards, true)



    return { glyph = glyph, text = text, short = stepWords(step, Guide.ShortLandmark), yards = yards, key = step.index,
             open = open, inst = step.inst, x = step.x, y = step.y,
             vertical = vDir, verticalYards = vYards, verticalGoal = vGoal }
end



function Guide.LookAheadYards(speed)
    local s = type(speed) == "number" and speed or 0
    return Util.Clamp(s * Guide.LOOKAHEAD_SECONDS, Guide.LOOKAHEAD_MIN_YARDS, Guide.LOOKAHEAD_MAX_YARDS)
end




local function heldAt(route, progress, cum, along, ahead)
    local steps = route.steps
    if type(steps) ~= "table" then return ahead, 1 end
    local current = progress.currentStep
    local first = type(current) == "table" and indexOf(steps, current) or 1

    while first > 1 and steps[first - 1].legIndex == progress.legIndex do first = first - 1 end
    local hold = Guide.HOLD_YARDS
    local corridorScale = 1
    for i = first, #steps do
        local step = steps[i]
        if step.legIndex == progress.legIndex then
            local at = HOLD_KINDS[step.kind] and type(step.pointIndex) == "number" and cum[step.pointIndex] or nil
            if at then
                local d = at - along
                local allowed
                if d >= hold then
                    allowed = at
                elseif d >= 0 then
                    allowed = at + hold - d
                else
                    allowed = at + hold - 2 * d
                end
                if allowed < ahead then ahead = allowed end
                local s = 1
                if d >= 0 then
                    if d <= hold then
                        s = 0
                    elseif d < hold + 20 then
                        s = (d - hold) / 20
                    end
                elseif d > -12 then
                    s = -d / 12
                end
                if s < corridorScale then corridorScale = s end
                if d >= hold + 20 then break end
            end
        elseif step.legIndex > progress.legIndex then
            break
        end
    end
    return ahead, corridorScale
end











function Guide.Aim(route, progress, speed)
    local Route = FGPS.Route
    local legs = type(route) == "table" and route.legs or nil
    local leg = type(progress) == "table" and type(legs) == "table" and legs[progress.legIndex] or nil
    local along = type(progress) == "table" and progress.alongYards or nil
    if type(leg) ~= "table" or leg.kind ~= "walk" or type(leg.points) ~= "table" or #leg.points < 2
        or type(along) ~= "number" or not (Route and Route.PointAlong and Route.Cumulative) then return nil end
    local pts = leg.points
    local pIdx = type(progress.pointIndex) == "number" and progress.pointIndex or nil
    local target = pIdx and pts[pIdx] or nil
    local prev = (pIdx and pIdx > 1) and pts[pIdx - 1] or nil
    local tightStretch = (type(target) == "table" and (target.indoor or target.stacked or target.climbForm or target.door))
        or (type(prev) == "table" and (prev.indoor or prev.stacked or prev.climbForm or prev.door))
    local yards = Guide.LookAheadYards(speed)
    if tightStretch then yards = Guide.LOOKAHEAD_MIN_YARDS end
    local cum = Route.Cumulative(leg)
    local total = cum.total or 0
    local ahead, corridorScale = heldAt(route, progress, cum, along, along + yards)
    local inst = leg.inst
    if ahead > total then ahead = total end
    if ahead < 0 then ahead = 0 end

    local x, y = Route.PointAlong(leg, ahead)
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    local baseAlong = along > 0 and along or 0
    if pts[2] and pts[2].k == 14 and cum[2] and baseAlong < cum[2] and ahead > cum[2] then
        baseAlong = cum[2]
    end
    local bx, by = Route.PointAlong(leg, baseAlong)
    local dirX, dirY
    if type(bx) == "number" and type(by) == "number" then
        local dx, dy = x - bx, y - by
        local len = sqrt(dx * dx + dy * dy)
        if len > 1e-4 then dirX, dirY = dx / len, dy / len end
    end
    if not dirX then
        local n = #pts
        local a, b = pts[n - 1], pts[n]
        if a and b and type(a.x) == "number" and type(b.x) == "number" then
            local dx, dy = b.x - a.x, b.y - a.y
            local len = sqrt(dx * dx + dy * dy)
            if len > 1e-4 then dirX, dirY = dx / len, dy / len end
        end
    end
    local aheadYards = ahead - along
    if aheadYards < 0 then aheadYards = 0 end
    local minCorridor = (FGPS.UI and FGPS.UI.Callout and FGPS.UI.Callout.CORRIDOR_YARDS) or 4
    local maxCorridor = (FGPS.Const and FGPS.Const.ROAD_CORRIDOR_YARDS) or 20
    if maxCorridor < minCorridor then maxCorridor = minCorridor end
    local corridorYards = tightStretch and minCorridor or (minCorridor + (maxCorridor - minCorridor) * corridorScale)
    return x, y, inst, dirX, dirY, aheadYards, corridorYards
end



local function attachLiveWindow(line, route, progress, speed)
    local Route = FGPS.Route
    local legs = type(route) == "table" and route.legs or nil
    local leg = type(progress) == "table" and type(legs) == "table" and legs[progress.legIndex] or nil
    local along = type(progress) == "table" and progress.alongYards or nil
    if type(leg) ~= "table" or leg.kind ~= "walk" or leg.split
        or type(leg.points) ~= "table" or #leg.points < 2
        or type(along) ~= "number" or not (Route and Route.Cumulative) then
        return
    end
    local pts = leg.points
    local cum = Route.Cumulative(leg)
    local n = #pts
    local pIdx = type(progress.pointIndex) == "number" and progress.pointIndex or 2
    local target = pts[pIdx]
    local prev = pIdx > 1 and pts[pIdx - 1] or nil
    local tightStretch = (type(target) == "table" and (target.indoor or target.stacked or target.climbForm or target.door))
        or (type(prev) == "table" and (prev.indoor or prev.stacked or prev.climbForm or prev.door))
    local lookYards = Guide.LookAheadYards(speed)
    if tightStretch then lookYards = Guide.LOOKAHEAD_MIN_YARDS end

    local segIdx = pIdx - 1
    if segIdx < 1 then segIdx = 1 elseif segIdx > n - 1 then segIdx = n - 1 end
    while segIdx > 1 and (cum[segIdx] or 0) > along do segIdx = segIdx - 1 end
    while segIdx < n - 1 and (cum[segIdx + 1] or 0) < along do segIdx = segIdx + 1 end

    local holdAt, holdAllowed
    local otherCap = cum.total or 0
    local steps = route.steps
    if type(steps) == "table" then
        local current = progress.currentStep
        local first = type(current) == "table" and indexOf(steps, current) or 1
        while first > 1 and steps[first - 1].legIndex == progress.legIndex do first = first - 1 end
        local hold = Guide.HOLD_YARDS
        for i = first, #steps do
            local step = steps[i]
            if step.legIndex == progress.legIndex then
                local at = HOLD_KINDS[step.kind] and type(step.pointIndex) == "number" and cum[step.pointIndex] or nil
                if at then
                    local d = at - along
                    local allowed = d >= hold and at or (d >= 0 and (at + hold - d) or (at + hold - 2 * d))
                    if holdAllowed == nil or allowed < holdAllowed then
                        if holdAllowed ~= nil and holdAllowed < otherCap then otherCap = holdAllowed end
                        holdAt, holdAllowed = at, allowed
                    elseif allowed < otherCap then
                        otherCap = allowed
                    end
                    if d >= hold + 20 then break end
                end
            elseif step.legIndex > progress.legIndex then
                break
            end
        end
    end

    line.liveLeg = leg
    line.liveSegIdx = segIdx
    line.liveMinAlong = along
    line.liveLookYards = lookYards
    line.liveHoldAt = holdAt
    line.liveHoldYards = Guide.HOLD_YARDS
    line.liveMaxAhead = otherCap
    line.liveTight = tightStretch or nil
    line.liveZ = type(progress.playerZ) == "number" and progress.playerZ
        or (type(progress.levelZ) == "number" and progress.levelZ)
        or nil
end




local function liveLine(route, progress, open)
    local step = markedStep(route, progress)
    local yards = Guide.YardsToStep(route, progress, step)
    local vDir, vYards, vGoal = calloutVertical(route, progress, step, yards, false)
    if type(yards) ~= "number" then yards = progress.remainingYards end
    return { glyph = "ahead", yards = yards, key = "live", open = open or nil,
             vertical = vDir, verticalYards = vYards, verticalGoal = vGoal }
end






Guide.WRONG_WAY_RAD = 2 * pi / 3
Guide.WRONG_WAY_HOLD = 2




function Guide.HeadingError(bearing, facing)
    if type(bearing) ~= "number" or type(facing) ~= "number" then return nil end
    local off = abs(bearing - facing) % (2 * pi)
    if off > pi then off = 2 * pi - off end
    return off
end






function Guide.WrongWay(headingError, speed, since, now)
    if type(headingError) ~= "number" or type(speed) ~= "number" or type(now) ~= "number" then return false, nil end
    if not (headingError > Guide.WRONG_WAY_RAD and speed > 0) then return false, nil end
    since = since or now
    return now - since >= Guide.WRONG_WAY_HOLD, since
end








function Guide.AtCorner(route, progress)
    local step = type(progress) == "table" and progress.currentStep or nil
    if type(step) ~= "table" or not isTurn(step.kind) then return false end
    local Const = FGPS.Const
    local radius = Const and Const.INTERMEDIATE_ARRIVE_YARDS
    local yards = Guide.YardsToStep(route, progress, step)
    return type(yards) == "number" and type(radius) == "number" and yards <= radius
end













function Guide.AtStop(route, progress)
    local index = type(progress) == "table" and progress.arrivedStopIndex or nil
    local stops = type(route) == "table" and route.stops or nil
    local stop = index and type(stops) == "table" and stops[index] or nil
    local leg = type(stop) == "table" and type(route.legs) == "table" and route.legs[stop.legTo] or nil
    local pts = type(leg) == "table" and leg.points or nil
    local at = type(pts) == "table" and pts[#pts] or nil
    local pos, Coords, Nav = progress and progress.pos, FGPS.Coords, FGPS.Navigator
    if type(at) ~= "table" or type(pos) ~= "table" or (leg.toInst or leg.inst) ~= pos.inst then return false end
    if not (Coords and Coords.Distance and Nav and Nav.ArriveRadius) then return false end
    local radius = Nav:ArriveRadius(index >= #stops)
    local yards = Coords.Distance(pos.x, pos.y, at.x, at.y)
    return type(radius) == "number" and type(yards) == "number" and yards <= radius
end





local function lastDest(route)
    local stops = type(route) == "table" and route.stops or nil
    local stop = type(stops) == "table" and stops[#stops] or nil
    local dest = stop and (stop.dest or stop)
    return type(dest) == "table" and dest or nil
end

function Guide.DestName(route)
    local dest = lastDest(route)
    if dest and type(dest.name) == "string" and dest.name ~= "" then return dest.name end
    return nil
end



local function spokenName(dest, stops)
    local D = FGPS.Destinations
    local said = D and D.SpokenName and D.SpokenName(dest, stops) or nil
    if type(said) == "string" and said ~= "" then return said end
    return dest.name
end



local function nameSaid(name, route, place, placeStops)
    if name == nil then return nil end
    local last = lastDest(route)
    if last and last.name == name then return spokenName(last, route.stops) end
    if type(place) == "table" and place.name == name then return spokenName(place, placeStops) end
    return name
end




local PAUSE_SENTENCE = { NO_PATH = "ROUTE_NO_PATH", UNREACHABLE = "ROUTE_UNREACHABLE", NO_DATA = "ROUTE_NO_DATA" }




Guide.ROOMS_AHEAD = 3








local function roomsAhead(route, progress)
    local legs = type(route.legs) == "table" and route.legs or {}
    local leg = legs[progress.legIndex]
    local I, Route = FGPS.Inside, FGPS.Route
    if not (type(leg) == "table" and leg.kind == "walk" and I and I.Runs) then return {} end
    local runs = I.Runs(leg)
    local pts = leg.points
    local cum = Route and Route.Cumulative and Route.Cumulative(leg) or nil
    local kinds = Route and Route.UNVERIFIED_KINDS or {}
    local least = FGPS.Instructions and FGPS.Instructions.MIN_UNVERIFIED_YARDS or 20
    local at = progress.inside.run or 0

    local here = at > 0 and runs[at] or nil
    if not here then at = 0 end
    local from = here and here.first or 1
    local out, guessed = {}, 0
    for j = at + 1, #runs do
        local run = runs[j]
        if cum then
            for i = from + 1, run.first do
                if kinds[pts[i].k] then guessed = guessed + cum[i] - cum[i - 1] end
            end
        end
        from = run.first
        local name = run.name
        if name then
            out[#out + 1] = { name = name, open = guessed >= least or nil, climb = run.climb }
            guessed = 0
            if #out >= Guide.ROOMS_AHEAD then break end
        end
    end
    return out
end




local function emptyRoomsText(route, progress)
    local legs = type(route.legs) == "table" and route.legs or {}
    local at = type(progress.legIndex) == "number" and progress.legIndex or nil
    local leg = at and legs[at] or nil
    if type(leg) == "table" then
        if leg.kind == "portal" then
            for _, step in ipairs(type(route.steps) == "table" and route.steps or {}) do
                if step.legIndex == at and type(step.text) == "string" and step.text ~= "" then
                    return step.text
                end
            end
            if leg.toInst ~= nil and leg.toInst ~= leg.inst then return L["Follow the way out"] end
        elseif leg.kind == "walk" then
            for i = at + 1, #legs do
                local nextLeg = legs[i]
                if type(nextLeg) == "table" and nextLeg.kind ~= "walk" then
                    if nextLeg.kind == "portal" and nextLeg.toInst ~= nil and nextLeg.toInst ~= leg.inst then
                        return L["Follow the way out"]
                    end
                    break
                end
            end
        end
    end
    return L["Follow the way in"]
end

local function pausedText(reason)
    local key = type(reason) == "string" and PAUSE_SENTENCE[reason] or nil
    if key then return format(L.ARROW_PAUSED_REASON, L[key]), true end
    return L.NAV_STATE_PAUSED, false
end




function Guide.Build(input)
    local state = input.state or "idle"
    local route, progress = input.route, input.progress
    local journey = FOLLOWED[state] == true and type(route) == "table"
    local model = { visible = false, header = {}, title = nil, rows = {}, callout = nil }




    local routeName = journey and Guide.DestName(route) or nil
    local newPlace = routeName ~= nil and input.destName ~= nil and input.destName ~= routeName
    if newPlace and input.computing and state ~= "paused" then journey = false end
    local name = input.destName or Guide.DestName(route)
    if newPlace and journey and state ~= "paused" then name = routeName end


    if name then model.title = format(L["To %s"], nameSaid(name, route, input.dest, input.destStops)) end

    if journey then
        model.visible = true


        if input.noFlights then model.noFlights, model.noFlightsIn = true, input.noFlightsIn end
        local noPosition = type(progress) == "table" and progress.positionAvailable == false
        if type(progress) == "table" and not (newPlace and state == "paused") then
            model.header.seconds = progress.remainingSeconds
            model.header.yards = progress.remainingYards
        end
        if state == "paused" then
            local text, hasReason = pausedText(input.pauseReason)
            model.rows = { { key = "paused", text = text, current = false, grey = true } }
            if hasReason then
                model.callout = { key = "paused", text = text, glyph = false }
            end
        elseif noPosition and state == "active" and type(progress.inside) == "table" then



            local rooms = roomsAhead(route, progress)
            if #rooms == 0 then
                local line = emptyRoomsText(route, progress)
                model.rows = { { key = "rooms", text = line, current = true } }
                model.callout = { key = "rooms", text = line, glyph = false }
            else


                local GO = { up = L["Go up to %s"], down = L["Go down to %s"] }
                for i, room in ipairs(rooms) do
                    local text = GO[room.climb] and format(GO[room.climb], room.name) or room.name
                    model.rows[i] = { key = "room" .. i, text = text, current = i == 1, open = room.open }
                end
                local text = format(GO[rooms[1].climb] or L["Go to %s"], rooms[1].name)
                if rooms[2] then text = format(L["%s, then %s"], text, rooms[2].name) end
                model.callout = { key = "rooms", text = text, glyph = false, open = rooms[1].open }
            end
        elseif noPosition then


            model.rows = { { key = "noposition", text = L["I can't tell where you are"], current = false, grey = true } }
            if state == "active" then
                model.callout = { key = "lost", text = L["I can't tell where you are"], glyph = false }
            end
        else
            model.rows = Guide.Rows(route, progress)
            local status = type(progress) == "table" and progress.statusText or nil
            if type(status) == "string" and status ~= "" then
                if model.rows[1] then
                    model.rows[1].text = status
                else
                    model.rows[1] = { key = "status", text = status, current = true }
                end
            end
            if state == "active" then

                local line = input.wrongWay and { glyph = GLYPH.uturn, text = L.ARROW_TURN_AROUND, key = "wrongway" }
                    or Guide.CalloutFor(route, progress, input.speed)




                if input.facing and (line or input.moving) then
                    local aimX, aimY, aimInst, dirX, dirY, aheadYards, corridorYards = Guide.Aim(route, progress, input.speed)
                    if aimX then
                        line = line or liveLine(route, progress, model.rows[1] and model.rows[1].open)
                        line.live, line.aimX, line.aimY, line.aimInst = true, aimX, aimY, aimInst
                        line.dirX, line.dirY, line.aheadYards, line.corridorYards = dirX, dirY, aheadYards, corridorYards
                        attachLiveWindow(line, route, progress, input.speed)
                    end
                end
                model.callout = line
            end
        end
    elseif input.computing then
        model.visible = true
        model.rows = { { key = "computing", text = L["Finding the way"], current = false, grey = true } }
    elseif input.stopped then


        model.visible, model.stopped = true, true
        model.rows = { { key = "stopped", text = L["Route stopped. Click to bring it back."], current = false, grey = true } }
    end

    local notice = input.notice
    if type(notice) == "table" and type(notice.text) == "string" then


        model.callout = { glyph = notice.glyph, text = notice.text, key = "notice", answer = notice.answer }


        if notice.depart and journey and state == "active" and input.facing then
            local aimX, aimY, aimInst, dirX, dirY, aheadYards, corridorYards = Guide.Aim(route, progress, input.speed)
            if aimX then
                local c = model.callout
                c.glyph, c.live, c.aimX, c.aimY, c.aimInst = "ahead", true, aimX, aimY, aimInst
                c.dirX, c.dirY, c.aheadYards, c.corridorYards = dirX, dirY, aheadYards, corridorYards
                attachLiveWindow(c, route, progress, input.speed)
            end
        end
    end
    return model
end




local NO_HEADER = {}

local function written(n)
    return type(n) == "number" and n == n and n ~= huge and n ~= -huge
end

function Guide.LayoutDiffers(a, b)
    if a == nil or b == nil then return a ~= b end
    if a.visible ~= b.visible or a.title ~= b.title or #a.rows ~= #b.rows or a.noFlights ~= b.noFlights
        or a.noFlightsIn ~= b.noFlightsIn then return true end
    local ha, hb = a.header or NO_HEADER, b.header or NO_HEADER
    if written(ha.seconds) ~= written(hb.seconds) or written(ha.yards) ~= written(hb.yards) then return true end
    for i = 1, #a.rows do
        local x, y = a.rows[i], b.rows[i]
        if x.key ~= y.key or x.text ~= y.text or x.current ~= y.current or x.grey ~= y.grey or x.open ~= y.open then return true end
    end
    local ca, cb = a.callout, b.callout
    if (ca == nil) ~= (cb == nil) then return true end
    if ca and (ca.key ~= cb.key or ca.text ~= cb.text or ca.short ~= cb.short or ca.glyph ~= cb.glyph or ca.open ~= cb.open
        or ca.answer ~= cb.answer or ca.live ~= cb.live
        or ca.vertical ~= cb.vertical or ca.verticalGoal ~= cb.verticalGoal) then return true end
    return false
end




Guide.HOLD_ARRIVED = 3
Guide.HOLD_FAILED = 5
Guide.HOLD_RECALC = 3
Guide.HOLD_DEPART = 5
Guide.UNDO_SHOW = 15

local function now()
    return (GetTime and GetTime()) or 0
end

local function computing()
    local nav = FGPS.Navigator
    return nav ~= nil and nav.inflight ~= nil
end



function Guide.Enabled()
    local Perf = FGPS.Perf
    return not (Perf and Perf.guidanceEnabled == false)
end


local function inFight()
    return InCombatLockdown ~= nil and InCombatLockdown() == true
end


local function calloutHiddenInFight()
    if not inFight() then return false end
    local DB = FGPS.DB
    return DB ~= nil and DB.Get ~= nil and DB:Get("combatMode") == "hide_all"
end



local function forgetHeading()
    Guide.wrongWay, Guide.wrongSince = false, nil
end




local function flightsLeftOut()
    local Access = FGPS.Access
    if not (Access and Access.FlightsLeftOut) then return false, nil end
    local ok, leftOut, where = pcall(Access.FlightsLeftOut, Access, Guide.route)
    if not (ok and leftOut == true) then return false, nil end
    return true, type(where) == "string" and where or nil
end


local function forgetStopped()
    local timer = Guide.stoppedTimer
    if timer and timer.Cancel then timer:Cancel() end
    Guide.stopped, Guide.stoppedTimer = nil, nil
end



local function setNotice(text, glyph, untilTime, answer)
    local timer = Guide.noticeTimer
    if timer and timer.Cancel then timer:Cancel() end
    Guide.notice = { text = text, glyph = glyph, untilTime = untilTime, answer = answer }
    Guide.noticeTimer = nil
    if C_Timer and C_Timer.NewTimer then
        Guide.noticeTimer = C_Timer.NewTimer(untilTime - now() + 0.05, function()
            Guide.noticeTimer = nil
            Guide.Refresh()
        end)
    end
end







function Guide.Refresh()
    if not Guide.Enabled() then
        if not Guide.resting then
            Guide.resting = true
            forgetHeading()
            local model = { visible = false, header = {}, title = nil, rows = {}, callout = nil }
            local layoutChanged = Guide.LayoutDiffers(Guide.model, model)
            Guide.model = model
            FGPS.Events:Fire("GUIDE_CHANGED", model, layoutChanged)
        end
        return Guide.model
    end
    Guide.resting = false
    if Guide.stopped and now() >= Guide.stopped.untilTime then forgetStopped() end



    if Guide.noFlights then Guide.noFlights, Guide.noFlightsIn = flightsLeftOut() end
    local notice = Guide.notice
    if notice and now() >= notice.untilTime then
        notice, Guide.notice = nil, nil


        local waiting = Guide.waiting
        Guide.waiting, Guide.atStop = nil, nil
        if waiting and now() < waiting.untilTime then
            setNotice(waiting.text, waiting.glyph, waiting.untilTime)
            Guide.notice.depart = true
            notice = Guide.notice
        end
    end




    local Coords = FGPS.Coords
    local speed = Coords and Coords.PlayerSpeed and Coords.PlayerSpeed() or 0



    if speed > 0 then Guide.movedAt = now() end
    local moving = Guide.movedAt ~= nil and now() - Guide.movedAt < Guide.LIVE_STILL_SECONDS

    local facing = Guide.navState == "active" and Coords ~= nil and Coords.PlayerFacing ~= nil and Coords.PlayerFacing() ~= nil
    local nav = FGPS.Navigator
    local model = Guide.Build({
        state = Guide.navState, route = Guide.route, progress = Guide.progress, speed = speed,
        moving = moving, facing = facing,
        computing = computing(), destName = Guide.destName, dest = Guide.destPlace, destStops = Guide.destStops, notice = notice,
        pauseReason = nav and nav.pauseReason or nil, wrongWay = Guide.wrongWay, stopped = Guide.stopped ~= nil,
        noFlights = Guide.noFlights, noFlightsIn = Guide.noFlightsIn,
    })
    local layoutChanged = Guide.LayoutDiffers(Guide.model, model)
    Guide.model = model
    FGPS.Events:Fire("GUIDE_CHANGED", model, layoutChanged)
    return model
end

function Guide.Get()
    return Guide.model or Guide.Refresh()
end








function Guide.ShowStopped()
    forgetStopped()
    local nav = FGPS.Navigator
    local seconds, kept = Guide.UNDO_SHOW, nav and nav.UNDO_SECONDS
    if type(kept) == "number" and kept < seconds then seconds = kept end
    Guide.stopped = { untilTime = now() + seconds }
    if C_Timer and C_Timer.NewTimer then
        Guide.stoppedTimer = C_Timer.NewTimer(seconds + 0.05, function()
            Guide.stoppedTimer = nil
            Guide.Refresh()
        end)
    end
    Guide.Refresh()
end


function Guide.HideStopped()
    if not Guide.stopped then return false end
    forgetStopped()
    Guide.Refresh()
    return true
end


function Guide.IsStopped()
    local stopped = Guide.stopped
    return stopped ~= nil and now() < stopped.untilTime
end



function Guide.Hush()
    local timer = Guide.noticeTimer
    if timer and timer.Cancel then timer:Cancel() end
    Guide.noticeTimer, Guide.notice, Guide.finding = nil, nil, nil
    Guide.atStop, Guide.waiting = nil, nil
end





local function say(text, holdSeconds, glyph, answer)
    if type(text) ~= "string" or text == "" or type(holdSeconds) ~= "number" then return false end
    Guide.Hush()
    setNotice(text, glyph, now() + holdSeconds, answer)
    Guide.Refresh()
    return true
end










function Guide.Say(text, holdSeconds, glyph)
    if not say(text, holdSeconds, glyph, true) then return end
    local DB = FGPS.DB
    local off = DB and DB.Get and DB:Get("callout.enabled") == false
    if (off or calloutHiddenInFight()) and type(UIErrorsFrame) == "table" and type(UIErrorsFrame.AddMessage) == "function" then
        UIErrorsFrame:AddMessage(text, 1, 0.1, 0.1)
    end
end









function Guide.Tell(text, holdSeconds, glyph)
    if not calloutHiddenInFight() then return say(text, holdSeconds, glyph) end
    if type(text) ~= "string" or text == "" or type(holdSeconds) ~= "number" then return false end
    Guide.Hush()
    Guide.notice = { text = text, glyph = glyph, untilTime = huge, hold = holdSeconds }
    Guide.Refresh()
    return true
end


local function releaseNews()
    local notice = Guide.notice
    if not (notice and notice.hold) then return end
    setNotice(notice.text, notice.glyph, now() + notice.hold)
    Guide.Refresh()
end





function Guide.Unsay(text)
    local notice = Guide.notice
    if type(text) ~= "string" or text == "" or not notice or notice.text ~= text then return false end
    Guide.Hush()
    Guide.Refresh()
    return true
end










local function lookAtHeading(progress)
    local due, since = false, nil
    local pos = type(progress) == "table" and progress.pos or nil
    local Coords = FGPS.Coords
    if Guide.navState == "active" and type(pos) == "table" and progress.legKind == "walk"
        and not Guide.AtCorner(Guide.route, progress) and not Guide.AtStop(Guide.route, progress)
        and progress.positionAvailable ~= false and type(pos.x) == "number" and type(pos.y) == "number"
        and type(progress.nextX) == "number" and type(progress.nextY) == "number"
        and (not progress.nextInst or progress.nextInst == pos.inst)
        and Coords and Coords.Bearing and Coords.PlayerFacing and Coords.PlayerSpeed then
        local facing = Coords.PlayerFacing()
        local off = facing and Guide.HeadingError(Coords.Bearing(pos.x, pos.y, progress.nextX, progress.nextY), facing)
        due, since = Guide.WrongWay(off, (Coords.PlayerSpeed()), Guide.wrongSince, now())
    end
    Guide.wrongWay, Guide.wrongSince = due, since
end




local function judgeHeading(progress)
    local ok, err = pcall(lookAtHeading, progress)
    if ok then return end
    forgetHeading()
    if Guide.headingFault == nil then
        Guide.headingFault = tostring(err)
        if FGPS.Log and FGPS.Log.Error then FGPS.Log:Error("Guide: the heading could not be judged: %s", Guide.headingFault) end
    end
end










local function failureText(err)
    if type(err) == "table" and err.code == "NO_ORIGIN" then
        return L["I can't tell where you are"]
    end
    return format(L["I can't find a way to %s"],
                  nameSaid(Guide.destName, Guide.route, Guide.destPlace, Guide.destStops) or L["that place"])
end

local function sayFailure(err, own)
    local text = failureText(err)
    if own then say(text, Guide.HOLD_FAILED) else Guide.Say(text, Guide.HOLD_FAILED) end
end



local NO_WAY_CODES = { UNREACHABLE = true, NO_PATH = true, NO_DATA = true }

local function askNoWay(err)
    if type(err) ~= "table" or err.replacedJourney ~= true or not NO_WAY_CODES[err.code] then return end
    local Question = FGPS.UI and FGPS.UI.Question
    if not (Question and Question.Ask) then return end
    local text = type(err.message) == "string" and err.message ~= "" and err.message or failureText(err)
    Question.Ask({
        id = "no_way",
        text = text,
        buttons = { { label = L["OK"] } },
    })
end





local function askedByTheNavigator()
    local nav = FGPS.Navigator
    return nav ~= nil and nav.askedBy == "navigator"
end



local function failed(route, err)
    return route == nil and err ~= nil and not (type(err) == "table" and err.code == "CANCELLED")
end

function Guide:Init()
    if self.eventsBound then return end
    local Events = FGPS.Events
    if not Events then return end


    local function lookOnTheNextFrame()
        local timer = Guide.lookTimer
        if timer and timer.Cancel then timer:Cancel() end
        if C_Timer and C_Timer.NewTimer then
            Guide.lookTimer = C_Timer.NewTimer(0, function()
                Guide.lookTimer = nil
                Guide.Refresh()
            end)
        end
    end


    Events:Register("ROUTE_WAITING", function(_, handle, why)
        if why ~= "combat" or type(handle) ~= "table" or type(handle.waitingText) ~= "string" then return end
        Guide.Say(handle.waitingText, 8)
    end, self)


    Events:Register("DESTINATION_SET", function(_, dest)
        Guide.destName = type(dest) == "table" and dest.name or nil
        local nav = FGPS.Navigator
        Guide.destPlace = type(dest) == "table" and dest or nil
        Guide.destStops = Guide.destPlace and nav and nav.GetStops and nav:GetStops() or nil
        if FGPS.UI and FGPS.UI.Question and FGPS.UI.Question.Close then
            FGPS.UI.Question.Close("no_way")
        end


        forgetStopped()

        lookOnTheNextFrame()
    end, self)









    Events:Register("NAV_STATE", function(_, state)
        Guide.navState = state or "idle"
        if Guide.navState == "idle" then
            Guide.route, Guide.progress, Guide.noFlights, Guide.noFlightsIn = nil, nil, false, nil
            Guide.movedAt = nil
        else
            forgetStopped()
        end
        forgetHeading()
        local nav = FGPS.Navigator
        if FOLLOWED[Guide.navState] and Guide.route == nil and nav and nav.GetRoute and nav:GetRoute() ~= nil then return end
        Guide.Refresh()
    end, self)

    local function onRoute(_, route)
        Guide.route = route
        local named = Guide.DestName(route)
        if named then
            Guide.destName = named
            Guide.destPlace, Guide.destStops = lastDest(route), route.stops
        end
        local nav = FGPS.Navigator
        local progress = nav and nav.GetProgress and nav:GetProgress() or nil
        if progress then Guide.progress = progress end
        forgetHeading()
        forgetStopped()

        Guide.noFlights, Guide.noFlightsIn = flightsLeftOut()
        Guide.Refresh()
    end
    Events:Register("ROUTE_STARTED", onRoute, self)
    Events:Register("ROUTE_UPDATED", onRoute, self)

    Events:Register("ROUTE_PROGRESS", function(_, progress)
        Guide.progress = progress
        if Guide.Enabled() then judgeHeading(progress) end
        Guide.Refresh()
    end, self)










    Events:Register("NAV_INSTRUCTION", function(_, step)
        if type(step) == "table" and step.kind == "depart" then
            local text = Guide.RowText(step)
            local notice = Guide.notice
            if text and notice ~= nil and notice == Guide.atStop then
                Guide.waiting = { text = text, glyph = GLYPH[step.kind], untilTime = now() + Guide.HOLD_DEPART }
            elseif text and notice ~= nil and notice.answer == true and askedByTheNavigator() then
                Guide.waiting = { text = text, glyph = GLYPH[step.kind], untilTime = notice.untilTime + Guide.HOLD_DEPART }
            else
                if say(text, Guide.HOLD_DEPART, GLYPH[step.kind]) then
                    Guide.notice.depart = true
                    Guide.Refresh()
                end
            end
        end
    end, self)





    Events:Register("NAV_ARRIVED", function(_, stopIndex, isFinal)
        local stops = type(Guide.route) == "table" and Guide.route.stops or nil
        if isFinal == false or (type(stops) == "table" and type(stopIndex) == "number" and stopIndex > 0 and stopIndex < #stops) then
            local stop = type(stops) == "table" and stops[stopIndex] or nil
            local dest = type(stop) == "table" and (stop.dest or stop) or nil
            local name = type(dest) == "table" and type(dest.name) == "string" and dest.name ~= "" and spokenName(dest, stops) or nil
            if say(format(L.ARROW_ARRIVED, name or L["that place"]), Guide.HOLD_ARRIVED, "arrive") and isFinal == false then
                Guide.atStop = Guide.notice
            end
            return
        end
        local name = nameSaid(Guide.destName, Guide.route, Guide.destPlace, Guide.destStops)
        say(format(L.ARROW_ARRIVED, name or L["that place"]), Guide.HOLD_ARRIVED, "arrive")
    end, self)

    Events:Register("NAV_RECALC_START", function()
        say(L["Finding a new way"], Guide.HOLD_RECALC)
        Guide.finding = Guide.notice
    end, self)


    Events:Register("NAV_RECALC_DONE", function(_, route, err)
        if failed(route, err) then
            sayFailure(err, askedByTheNavigator())
            askNoWay(err)
            return
        end



        if route ~= nil and Guide.notice ~= nil and Guide.notice == Guide.finding then Guide.Hush() end
        Guide.Refresh()
    end, self)



    Events:Register("ROUTE_PREVIEW", function(_, route, _, err)
        if failed(route, err) then sayFailure(err, askedByTheNavigator()) else Guide.Refresh() end
    end, self)


    Events:Register("NAV_CANCELLED", function()
        Guide.route, Guide.progress, Guide.noFlights, Guide.noFlightsIn = nil, nil, false, nil
        Guide.movedAt = nil
        forgetHeading()
        Guide.Hush()
        Guide.Refresh()
    end, self)









    Events:Register("ITINERARY_CHANGED", function(_, stops)
        if type(stops) ~= "table" or #stops == 0 then
            Guide.Refresh()
        elseif Guide.stopped then
            forgetStopped()
            lookOnTheNextFrame()
        end
    end, self)




    Events:Register("COMBAT_STATE", function(_, inCombat)
        if not inCombat then releaseNews() end
    end, self)
    Events:Register("WORLD_ENTERED", function()
        if not inFight() then releaseNews() end
    end, self)



    Events:Register("SETTINGS_CHANGED", function(_, key)
        if (key == "*" or key == "combatMode") and not calloutHiddenInFight() then releaseNews() end
        if key == "*" or key == "units" or key == "perf.guidanceEnabled" then Guide.Refresh() end
    end, self)

    self.eventsBound = true
end
