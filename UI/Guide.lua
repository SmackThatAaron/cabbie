







local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local type, format, abs, max, pi, huge = type, string.format, math.abs, math.max, math.pi, math.huge

local Guide = {
    model = nil,
    route = nil,
    progress = nil,
    navState = "idle",
    destName = nil,
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
    uturn = true, enter = true, level = true,
}


local GLYPH = {
    turn_slight_left = "slight_left", turn_left = "left", turn_sharp_left = "sharp_left",
    turn_slight_right = "slight_right", turn_right = "right", turn_sharp_right = "sharp_right",
    uturn = "uturn", ramp = "ahead",


    enter = "ahead", level = "ahead",
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






function Guide.RowText(step)
    if type(step) ~= "table" then return nil end
    local text = step.shortText
    if type(text) ~= "string" or text == "" then text = step.text end
    if type(text) ~= "string" or text == "" then return nil end

    if isTurn(step.kind) and not step.toward and type(step.landmark) == "string" and step.landmark ~= "" then
        return format(L["%s at %s"], text, step.landmark)
    end
    return text
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
            local open = guessedOf(current) >= least and guessedAhead(route, progress, current) > 0
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





function Guide.YardsToStep(route, progress, step)
    if type(progress) ~= "table" or type(step) ~= "table" then return nil end
    local total = type(route) == "table" and route.totalYards or nil
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
    return { glyph = glyph, text = text, yards = yards, key = step.index, open = open }
end



function Guide.LookAheadYards(speed)
    local s = type(speed) == "number" and speed or 0
    return Util.Clamp(s * Guide.LOOKAHEAD_SECONDS, Guide.LOOKAHEAD_MIN_YARDS, Guide.LOOKAHEAD_MAX_YARDS)
end




local function heldAt(route, progress, cum, along, ahead)
    local steps = route.steps
    if type(steps) ~= "table" then return ahead end
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
                local allowed
                if d >= hold then
                    allowed = at
                elseif d >= 0 then
                    allowed = at + hold - d
                else
                    allowed = at + hold - 2 * d
                end
                if allowed < ahead then ahead = allowed end
                if d >= hold then break end
            end
        elseif step.legIndex > progress.legIndex then
            break
        end
    end
    return ahead
end








function Guide.Aim(route, progress, speed)
    local Route = FGPS.Route
    local legs = type(route) == "table" and route.legs or nil
    local leg = type(progress) == "table" and type(legs) == "table" and legs[progress.legIndex] or nil
    local along = type(progress) == "table" and progress.alongYards or nil
    if type(leg) ~= "table" or leg.kind ~= "walk" or type(leg.points) ~= "table" or #leg.points < 2
        or type(along) ~= "number" or not (Route and Route.PointAlong and Route.Cumulative) then return nil end
    local target = type(progress.pointIndex) == "number" and leg.points[progress.pointIndex] or nil
    local yards = Guide.LookAheadYards(speed)
    if type(target) == "table" and (target.indoor or target.stacked) then yards = Guide.LOOKAHEAD_MIN_YARDS end
    local ahead, inst = heldAt(route, progress, Route.Cumulative(leg), along, along + yards), leg.inst
    local split = leg.split
    if split then
        local jump = Route.Cumulative(leg)[split]
        if along < jump then
            if ahead > jump then ahead = jump end
        else
            inst = leg.toInst or leg.inst
        end
    end
    local x, y = Route.PointAlong(leg, ahead)
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    return x, y, inst
end



local function liveLine(route, progress)
    local yards = Guide.YardsToStep(route, progress, markedStep(route, progress))
    if type(yards) ~= "number" then yards = progress.remainingYards end
    return { glyph = "ahead", yards = yards, key = "live" }
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
    local radius = Nav:ArriveRadius(index >= #stops, stop.dest)
    local yards = Coords.Distance(pos.x, pos.y, at.x, at.y)
    return type(radius) == "number" and type(yards) == "number" and yards <= radius
end




function Guide.DestName(route)
    local stops = type(route) == "table" and route.stops or nil
    local stop = type(stops) == "table" and stops[#stops] or nil
    local dest = stop and (stop.dest or stop)
    if type(dest) == "table" and type(dest.name) == "string" and dest.name ~= "" then return dest.name end
    return nil
end




local PAUSE_SENTENCE = { NO_PATH = "ROUTE_NO_PATH", UNREACHABLE = "ROUTE_UNREACHABLE", NO_DATA = "ROUTE_NO_DATA" }

local function pausedText(reason)
    local key = type(reason) == "string" and PAUSE_SENTENCE[reason] or nil
    if key then return format(L.ARROW_PAUSED_REASON, L[key]) end
    return L.NAV_STATE_PAUSED
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
    if name then model.title = format(L["To %s"], name) end

    if journey then
        model.visible = true


        if input.noFlights then model.noFlights, model.noFlightsIn = true, input.noFlightsIn end
        local noPosition = type(progress) == "table" and progress.positionAvailable == false


        local staying = input.staying == true and state ~= "paused" and not noPosition
        if type(progress) == "table" and not staying and not (newPlace and state == "paused") then
            model.header.seconds = progress.remainingSeconds
            model.header.yards = progress.remainingYards
        end
        if state == "paused" then
            model.rows = { { key = "paused", text = pausedText(input.pauseReason), current = false, grey = true } }
        elseif noPosition then


            model.rows = { { key = "noposition", text = L["No position here"], current = false, grey = true } }
        elseif staying then



            model.rows = { { key = "staying", text = L["You are there. The route moves on when this part of the quest is done."],
                             current = false, grey = true } }
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
                    local aimX, aimY, aimInst = Guide.Aim(route, progress, input.speed)
                    if aimX then
                        line = line or liveLine(route, progress)
                        line.live, line.aimX, line.aimY, line.aimInst = true, aimX, aimY, aimInst
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
            local aimX, aimY, aimInst = Guide.Aim(route, progress, input.speed)
            if aimX then
                local c = model.callout
                c.glyph, c.live, c.aimX, c.aimY, c.aimInst = "ahead", true, aimX, aimY, aimInst
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
    if ca and (ca.key ~= cb.key or ca.text ~= cb.text or ca.glyph ~= cb.glyph or ca.open ~= cb.open or ca.answer ~= cb.answer
        or ca.live ~= cb.live) then return true end
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








function Guide.Staying(route, progress)
    if type(progress) ~= "table" or not progress.parked then return false end
    local stops = type(route) == "table" and route.stops or nil
    local stop = type(stops) == "table" and stops[#stops] or nil
    local Quests = FGPS.Quests
    if type(stop) ~= "table" or not (Quests and Quests.StaysAt) then return false end
    if not progress.holdYards and not Guide.AtStop(route, progress) then return false end
    local ok, yards = pcall(Quests.StaysAt, stop.dest or stop)


    if ok then
        Guide.stayingError = nil
    elseif Guide.stayingError ~= tostring(yards) then
        Guide.stayingError = tostring(yards)
        if FGPS.Log then FGPS.Log:Error("Guide: the quest module could not say whether the route stays: %s", Guide.stayingError) end
    end
    return ok and yards ~= nil
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
        computing = computing(), destName = Guide.destName, notice = notice,
        pauseReason = nav and nav.pauseReason or nil, wrongWay = Guide.wrongWay, stopped = Guide.stopped ~= nil,
        noFlights = Guide.noFlights, noFlightsIn = Guide.noFlightsIn, staying = Guide.Staying(Guide.route, Guide.progress),
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
    if (off or inFight()) and type(UIErrorsFrame) == "table" and type(UIErrorsFrame.AddMessage) == "function" then
        UIErrorsFrame:AddMessage(text, 1, 0.1, 0.1)
    end
end











function Guide.Tell(text, holdSeconds, glyph)
    if not inFight() then return say(text, holdSeconds, glyph) end
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










local function sayFailure(err, own)
    local text
    if type(err) == "table" and err.code == "NO_ORIGIN" then
        text = L["No position here"]
    else
        text = format(L["No way found to %s"], Guide.destName or L["that place"])
    end
    if own then say(text, Guide.HOLD_FAILED) else Guide.Say(text, Guide.HOLD_FAILED) end
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



    Events:Register("DESTINATION_SET", function(_, dest)
        Guide.destName = type(dest) == "table" and dest.name or nil


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
        Guide.destName = Guide.DestName(route) or Guide.destName
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
            if text and Guide.notice ~= nil and Guide.notice == Guide.atStop then
                Guide.waiting = { text = text, glyph = GLYPH[step.kind], untilTime = now() + Guide.HOLD_DEPART }
            else
                if say(text, Guide.HOLD_DEPART, GLYPH[step.kind]) then
                    Guide.notice.depart = true
                    Guide.Refresh()
                end
            end
        end
    end, self)




    Events:Register("NAV_ARRIVED", function(_, stopIndex, isFinal)
        if isFinal == false then
            local stops = type(Guide.route) == "table" and Guide.route.stops or nil
            local stop = type(stops) == "table" and stops[stopIndex] or nil
            local dest = type(stop) == "table" and (stop.dest or stop) or nil
            local name = type(dest) == "table" and type(dest.name) == "string" and dest.name ~= "" and dest.name or nil
            if say(format(L.ARROW_ARRIVED, name or L["that place"]), Guide.HOLD_ARRIVED, "arrive") then
                Guide.atStop = Guide.notice
            end
            return
        end
        say(format(L.ARROW_ARRIVED, Guide.destName or L["that place"]), Guide.HOLD_ARRIVED, "arrive")
    end, self)

    Events:Register("NAV_RECALC_START", function()
        say(L["Finding a new way"], Guide.HOLD_RECALC)
        Guide.finding = Guide.notice
    end, self)


    Events:Register("NAV_RECALC_DONE", function(_, route, err)
        if failed(route, err) then
            sayFailure(err, askedByTheNavigator())
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
        if key == "*" or key == "units" or key == "perf.guidanceEnabled" then Guide.Refresh() end
    end, self)

    self.eventsBound = true
end
