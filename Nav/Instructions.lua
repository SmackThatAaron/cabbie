




























local ADDON_NAME, FGPS = ...

local Instructions = {
    SLIGHT_DEGREES = 30,
    TURN_DEGREES = 70,
    SHARP_DEGREES = 120,
    UTURN_DEGREES = 165,
    MERGE_YARDS = 25,
    LOOP_DEGREES = 300,
    MIN_REVERSAL_YARDS = 12,
    ZONE_CONFIRM_YARDS = 50,
    LANDMARK_YARDS = 60,



    TOWN_YARDS = 50,
    LANDMARK_LEVEL_YARDS = 12,
    MIN_SEGMENT_YARDS = 3,
    MIN_UNVERIFIED_YARDS = 20,
    POI_CELL = 256,








    BEND_NEAR_YARDS = 8,
    BEND_FAR_YARDS = 25,
    CORNER_SHARE = 0.75,
    JUNCTION_YARDS = 25,



    SURFACE_TURN_DEGREES = 40,
    SURFACE_TURN_YARDS = 15,
    SURFACE_HOLD_SHARE = 0.6,
    SURFACE_NEAR_SHARE = 0.8,
    SURFACE_SHARE = 0.6,
}


Instructions.WAY_KINDS = { [1] = true, [2] = true, [4] = true, [6] = true, [12] = true, [16] = true, [17] = true, [18] = true }


Instructions.ROAD_KINDS = { [4] = true, [16] = true, [17] = true, [18] = true }




Instructions.BEND_KINDS = { [22] = true, [23] = true }
for k in pairs(Instructions.WAY_KINDS) do Instructions.BEND_KINDS[k] = true end
local SURFACE = { [22] = true, [23] = true }


Instructions.CITY_MAPS = { [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true }
FGPS.Instructions = Instructions

local L, Util = FGPS.L, FGPS.Util
local floor, abs, sqrt, pi = math.floor, math.abs, math.sqrt, math.pi
local type, pairs, ipairs, tostring = type, pairs, ipairs, tostring
local format = string.format





local UNVERIFIED = (FGPS.Route and FGPS.Route.UNVERIFIED_KINDS) or { [3] = true, [14] = true, [15] = true }




local CHECKED = (FGPS.Route and FGPS.Route.OPEN_GROUND_KINDS) or { [19] = true }
local function isOpenGround(kind)
    return UNVERIFIED[kind] == true or CHECKED[kind] == true
end
local EXCLUDED_POI_TYPES = { [18] = true }







local MINUTE_SENTENCES = { L["about 1 minute"], L["about 1 minute 1 second"], L["about 1 minute %d seconds"],
                           L["about %d minutes"], L["about %d minutes 1 second"], L["about %d minutes %d seconds"] }
local HOUR_SENTENCES = { L["about 1 hour"], L["about 1 hour 1 minute"], L["about 1 hour %d minutes"],
                         L["about %d hours"], L["about %d hours 1 minute"], L["about %d hours %d minutes"] }

local function spokenDuration(seconds)
    seconds = floor((seconds or 0) + 0.5)
    if seconds < 60 then
        if seconds == 1 then return L["about 1 second"] end
        return format(L["about %d seconds"], seconds)
    end
    local big, small, sentences
    if seconds < 3600 then
        big, small, sentences = floor(seconds / 60), seconds % 60, MINUTE_SENTENCES
    else
        big, small, sentences = floor(seconds / 3600), floor((seconds % 3600) / 60), HOUR_SENTENCES
    end
    local one = big == 1
    if small == 0 then return one and sentences[1] or format(sentences[4], big) end
    if small == 1 then return one and sentences[2] or format(sentences[5], big) end
    if one then return format(sentences[3], small) end
    return format(sentences[6], big, small)
end
Instructions.SpokenDuration = spokenDuration

local function distanceUnits()
    local s = FGPS.DB and FGPS.DB.settings
    return s and s.units or "yards"
end

local function spokenDistance(yards)
    yards = floor((yards or 0) + 0.5)
    if yards >= 100 then yards = floor(yards / 10 + 0.5) * 10 end
    if distanceUnits() == "metric" then
        local metres = floor(yards * (FGPS.Const.METERS_PER_YARD or 0.9144) + 0.5)
        if metres >= 100 then metres = floor(metres / 10 + 0.5) * 10 end
        return format(L["%d metres"], metres)
    end
    return format(L["%d yards"], yards)
end
Instructions.SpokenDistance = spokenDistance

local function shortTime(seconds)
    return Util.FormatTime(seconds or 0)
end







local poiGrids, gridSource, gridCount = {}, nil, nil
local POI_CELL = Instructions.POI_CELL

local function poiCellKey(cx, cy)
    return (cx + 32768) * 65536 + (cy + 32768)
end

local function poiGrid(inst)
    local poi = FGPS.Data and FGPS.Data.poi
    local n = poi and poi.name and (poi.n or #poi.name) or 0
    if poi ~= gridSource or n ~= gridCount then
        poiGrids, gridSource, gridCount = {}, poi, n
    end
    local grid = poiGrids[inst]
    if grid then return grid end
    grid = {}
    poiGrids[inst] = grid
    if n == 0 then return grid end
    for i = 1, n do
        if poi.inst[i] == inst and not EXCLUDED_POI_TYPES[poi.type[i]] then
            local k = poiCellKey(floor(poi.x[i] / POI_CELL), floor(poi.y[i] / POI_CELL))
            local cell = grid[k]
            if not cell then grid[k] = { i } else cell[#cell + 1] = i end
        end
    end
    return grid
end



local function poiHeight(poi, i)
    local G = FGPS.Graph
    local z = G and G.PoiLevelHeight and G:PoiLevelHeight(i)
    if type(z) == "number" then return z end
    return nil
end










function Instructions.LandmarkNear(inst, x, y, radius, skip, z)
    if inst == nil or x == nil or y == nil then return nil end
    radius = radius or Instructions.LANDMARK_YARDS
    local poi = FGPS.Data and FGPS.Data.poi
    if not poi or not poi.name then return nil end
    local grid = poiGrid(inst)
    local cx, cy = floor(x / POI_CELL), floor(y / POI_CELL)
    local skipIndex, skipName = skip and skip.index, skip and skip.name
    if type(z) ~= "number" then z = nil end
    local level = Instructions.LANDMARK_LEVEL_YARDS

    local best, bestD = nil, radius * radius
    local known, knownD, otherD = nil, bestD, bestD
    for dx = -1, 1 do
        for dy = -1, 1 do
            local cell = grid[poiCellKey(cx + dx, cy + dy)]
            if cell then
                for j = 1, #cell do
                    local i = cell[j]
                    if i ~= skipIndex and poi.name[i] ~= skipName then
                        local ex, ey = poi.x[i] - x, poi.y[i] - y
                        local d2 = ex * ex + ey * ey
                        local h = z and poiHeight(poi, i)
                        if h and abs(h - z) > level then
                            if d2 < otherD then otherD = d2 end
                        else
                            if d2 <= bestD then best, bestD = i, d2 end
                            if h and d2 <= knownD then known, knownD = i, d2 end
                        end
                    end
                end
            end
        end
    end
    if best ~= known and bestD > otherD then best, bestD = known, knownD end
    if not best then return nil end
    return poi.name[best], sqrt(bestD), best
end



local TOWN_TYPE = { [1] = true, [5] = true }

function Instructions.TownNear(inst, x, y, radius, z)
    if inst == nil or x == nil or y == nil then return nil end
    radius = radius or Instructions.TOWN_YARDS
    local poi = FGPS.Data and FGPS.Data.poi
    if not poi or not poi.name then return nil end
    local grid = poiGrid(inst)
    local cx, cy = floor(x / POI_CELL), floor(y / POI_CELL)
    if type(z) ~= "number" then z = nil end
    local level = Instructions.LANDMARK_LEVEL_YARDS
    local best, bestD
    local radiusSq = radius * radius
    for dx = -1, 1 do
        for dy = -1, 1 do
            local cell = grid[poiCellKey(cx + dx, cy + dy)]
            if cell then
                for j = 1, #cell do
                    local i = cell[j]
                    if TOWN_TYPE[poi.type[i]] then
                        local ex, ey = poi.x[i] - x, poi.y[i] - y
                        local d2 = ex * ex + ey * ey
                        if d2 <= radiusSq then
                            local h = z and poiHeight(poi, i)
                            if not (h and abs(h - z) > level) then
                                if not bestD or d2 < bestD then best, bestD = i, d2 end
                            end
                        end
                    end
                end
            end
        end
    end
    if not best then return nil end
    return poi.name[best], sqrt(bestD), best
end

local function pointKind(p)
    return p and (p.k or p.kind)
end




local legTowns = setmetatable({}, { __mode = "k" })

local function townsOfLeg(leg)
    local cached = legTowns[leg]
    if cached then return cached end
    local pts = leg.points or {}
    local n = #pts
    local at, first, second = {}, {}, {}
    for j = 1, n do
        local _, _, idx = Instructions.TownNear(leg.inst, pts[j].x, pts[j].y, Instructions.TOWN_YARDS, pts[j].z)
        at[j] = idx
    end
    for i = n - 1, 1, -1 do
        if Instructions.ROAD_KINDS[pointKind(pts[i + 1])] then
            local t, f2, s2 = at[i + 1], first[i + 1], second[i + 1]
            if t and t ~= f2 then
                first[i], second[i] = t, f2
            else
                first[i], second[i] = f2, s2
            end
        end
    end
    cached = { at = at, first = first, second = second }
    legTowns[leg] = cached
    return cached
end



local function townAhead(leg, at)
    local pts = leg.points
    local n = pts and #pts or 0
    if at < 1 or at >= n then return nil end
    if not Instructions.ROAD_KINDS[pointKind(pts[at + 1])] then return nil end
    local towns = townsOfLeg(leg)
    local pick = towns.first[at]
    if pick and pick == towns.at[at] then pick = towns.second[at] end
    if not pick then return nil end
    return FGPS.Data.poi.name[pick]
end

function Instructions.ResetLandmarks()
    poiGrids, gridSource, gridCount = {}, nil, nil
    legTowns = setmetatable({}, { __mode = "k" })
end





local function classify(deg)
    local a = abs(deg)
    if a < Instructions.SLIGHT_DEGREES then return nil end
    if a >= Instructions.UTURN_DEGREES then return "uturn" end
    local side = deg > 0 and "left" or "right"
    if a >= Instructions.SHARP_DEGREES then return "turn_sharp_" .. side end
    if a >= Instructions.TURN_DEGREES then return "turn_" .. side end
    return "turn_slight_" .. side
end
Instructions.Classify = classify

local TURN_TEXT = {
    turn_slight_left = { text = L["Bear left"], short = L["Bear left"] },
    turn_slight_right = { text = L["Bear right"], short = L["Bear right"] },
    turn_left = { text = L["Turn left"], short = L["Turn left"] },
    turn_right = { text = L["Turn right"], short = L["Turn right"] },
    turn_sharp_left = { text = L["Turn sharply left"], short = L["Sharp left"] },
    turn_sharp_right = { text = L["Turn sharply right"], short = L["Sharp right"] },
    uturn = { text = L["Make a U-turn"], short = L["U-turn"] },
}

local function turnTexts(kind, landmark)
    local t = TURN_TEXT[kind]
    local text = t.text
    if landmark then text = format(L["%s at %s"], text, landmark) end
    return text, t.short, text .. "."
end



local function fold(deg)
    while deg > 180 do deg = deg - 360 end
    while deg <= -180 do deg = deg + 360 end
    return deg
end





local function addZone(step)
    local name = step.zoneName
    if not name then return end
    step.text = format(L["%s, entering %s"], step.text, name)
    step.zoneVoice = format(L["Entering %s."], name)
end





local function describeTurn(step)
    local text, short, voice
    if step.kind == "ramp" then
        text, short = L["Follow the ramp"], L["Follow the ramp"]
        voice = text .. "."
    elseif step.toward then


        local base = turnTexts(step.kind, nil)
        local sink, voiceLine
        sink, sink, voiceLine = turnTexts(step.kind, step.landmark)
        text = format(L["%s toward %s"], base, step.toward)
        short = text
        voice = voiceLine
    else
        text, short, voice = turnTexts(step.kind, step.landmark)
    end
    local guess = step.guess
    if guess and guess.checked then
        text = format(L["%s, then continue %s across open ground for %s"], text, guess.compass, guess.distance)
    elseif guess then
        text = format(L["%s, then continue %s across open ground for %s"], text, guess.compass, guess.distance)
        if guess.steepNote then text = text .. " " .. guess.steepNote end
    end
    step.text, step.shortText, step.voiceText = text, short, voice
    step.guessVoice = guess and guess.voiceText or nil
    addZone(step)
end








local function classifyTurn(step, legEnd)
    local turned = step.turned
    if abs(turned) >= Instructions.LOOP_DEGREES and step.sharp == 0 then
        step.kind, step.deg = "ramp", nil
    else
        local deg = fold(turned)
        local kind = classify(deg)
        if not kind then return false end

        if step.surface and kind == "turn_slight_left" then kind = "turn_left" end
        if step.surface and kind == "turn_slight_right" then kind = "turn_right" end





        if legEnd - step.lastAt < Instructions.MIN_REVERSAL_YARDS then return false end
        step.kind, step.deg = kind, deg
    end
    describeTurn(step)
    return true
end




local function addStep(steps, step)
    step.index = #steps + 1
    steps[#steps + 1] = step
    return step
end

local function removeStep(steps, step)
    for i = #steps, 1, -1 do
        if steps[i] == step then
            table.remove(steps, i)
            return
        end
    end
end

local function dist(a, b)
    local dx, dy = b.x - a.x, b.y - a.y
    return sqrt(dx * dx + dy * dy)
end

local function zoneNameAt(inst, x, y)
    local _, name = FGPS.Coords.ZoneAt(inst, x, y)
    return name
end

local function stopName(route, stopIndex, final)
    local stop = route.stops and route.stops[stopIndex]
    local dest = stop and stop.dest
    if dest and dest.name and dest.name ~= "" then return dest.name end
    if final then return L["your destination"] end
    return format(L["stop %d"], stopIndex)
end



local function stopSkip(route, leg)
    local stop = route.stops and route.stops[leg.stopIndex or 1]
    local dest = stop and stop.dest
    if type(dest) ~= "table" then return nil end
    if dest.poiIndex == nil and (dest.name == nil or dest.name == "") then return nil end
    return { index = dest.poiIndex, name = dest.name ~= "" and dest.name or nil }
end



local LEVEL_TEXT = {
    stairs = { up = L["Take the stairs up"], down = L["Take the stairs down"] },
    ramp = { up = L["Go up the ramp to the upper level"], down = L["Go down the ramp to the lower level"] },
    climb = { up = L["Go up to the upper level"], down = L["Go down to the lower level"] },
}


local function climbWay(pts, i)
    local a, b = pts[i - 1].z, pts[i].z
    if type(a) ~= "number" or type(b) ~= "number" or a == b then return nil end
    return b > a and 1 or -1
end

local function walkSteps(route, steps, leg, li, state)
    local Coords = FGPS.Coords
    local pts = leg.points
    local n = #pts
    local cum = FGPS.Route.Cumulative(leg)
    local legYards, legSeconds = cum.total, leg.seconds or 0
    local function eta(along)
        if legYards <= 0 then return state.secs end
        return state.secs + legSeconds * (along / legYards)
    end
    local minSeg = Instructions.MIN_SEGMENT_YARDS
    local skip = stopSkip(route, leg)
    local legEnd = state.dist + legYards


    local function ahead(i)
        local j = i + 1
        while j < n and dist(pts[i], pts[j]) < minSeg do j = j + 1 end
        return j
    end


    local function further(i, yards)
        local target = cum[i] + yards
        if target > legYards then return nil end
        local j = i + 1
        while j < n and cum[j] < target do j = j + 1 end
        local a, b = pts[j - 1], pts[j]
        local seg = cum[j] - cum[j - 1]
        local u = seg > 0 and (target - cum[j - 1]) / seg or 1
        return a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u
    end


    local function at(i, d)
        local target = cum[i] + d
        if target <= 0 then return pts[1].x, pts[1].y end
        if target >= legYards then return pts[n].x, pts[n].y end
        local j = i
        if d >= 0 then
            while j < n - 1 and cum[j + 1] < target do j = j + 1 end
        else
            while j > 1 and cum[j] > target do j = j - 1 end
        end
        local a, b = pts[j], pts[j + 1]
        local seg = cum[j + 1] - cum[j]
        local u = seg > 0 and (target - cum[j]) / seg or 0
        return a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u
    end



    local function windowTurn(i, d)
        local p = pts[i]
        local ax, ay = at(i, -d)
        local bx, by = at(i, d)
        if Coords.Distance(ax, ay, p.x, p.y) < minSeg or Coords.Distance(p.x, p.y, bx, by) < minSeg then return nil end
        return Coords.AngleDelta(Coords.Bearing(ax, ay, p.x, p.y), Coords.Bearing(p.x, p.y, bx, by)) * 180 / pi
    end




    local WAY = Instructions.WAY_KINDS
    local function otherWayOut(i)
        local key = pts[i].node
        local G = FGPS.Graph
        if not (key and G and G.Neighbors) then return false end
        local before, after
        for j = i - 1, 1, -1 do
            if pts[j].node then before = pts[j].node break end
        end
        for j = i + 1, n do
            if pts[j].node then after = pts[j].node break end
        end
        local found = false
        G:Neighbors(key, function(nb, kind)
            if WAY[kind] and nb ~= before and nb ~= after and nb ~= key then found = true end
        end)
        return found
    end





    local BEND = Instructions.BEND_KINDS
    local function judged(i, deg)
        local p, q = pts[i], pts[i + 1]
        if not (BEND[p.k] and q and BEND[q.k] and (p.shape or p.node)) then return deg end
        if p.shape or not otherWayOut(i) then
            local near = windowTurn(i, Instructions.BEND_NEAR_YARDS)
            local far = windowTurn(i, Instructions.BEND_FAR_YARDS)
            if near and abs(near) >= Instructions.TURN_DEGREES and abs(near) >= Instructions.CORNER_SHARE * abs(far or near) then
                return near, "corner"
            end








            if SURFACE[p.k] and SURFACE[q.k] and abs(deg) >= Instructions.SLIGHT_DEGREES
                and Instructions.CITY_MAPS[Coords.ZoneAt(leg.inst, p.x, p.y) or false] then
                local mid = windowTurn(i, Instructions.SURFACE_TURN_YARDS)
                if mid and far and abs(mid) >= Instructions.SURFACE_TURN_DEGREES and (mid > 0) == (far > 0)
                    and abs(far) >= Instructions.SURFACE_HOLD_SHARE * abs(mid) and abs(mid) >= Instructions.SURFACE_SHARE * abs(far)
                    and near and abs(near) >= Instructions.SURFACE_NEAR_SHARE * abs(mid) then
                    return mid, "surface"
                end
            end
            return 0, "bend"
        end
        local wide = windowTurn(i, Instructions.JUNCTION_YARDS)
        if wide and abs(wide) > abs(deg) then return wide end
        return deg
    end

    if n >= 2 and state.needDepart then
        local j = ahead(1)
        local bearing = Coords.Bearing(pts[1].x, pts[1].y, pts[j].x, pts[j].y)
        local compass = Coords.CompassName(bearing)
        local landmark = Instructions.LandmarkNear(leg.inst, pts[1].x, pts[1].y, nil, skip, pts[1].z)
        local text = format(L["Head %s"], compass)
        if landmark then text = format(L["Head %s from %s"], compass, landmark) end
        local shortText = format(L["Head %s"], compass)
        local voiceText = text .. "."
        local toward = townAhead(leg, 1)
        if toward then
            text = format(L["Follow the road toward %s"], toward)
            shortText = text
        end
        addStep(steps, { kind = "depart", legIndex = li, pointIndex = 1, inst = leg.inst, x = pts[1].x, y = pts[1].y,
                         distanceFromStart = state.dist, seconds = state.secs, text = text, shortText = shortText,
                         voiceText = voiceText, landmark = landmark, bearing = bearing, toward = toward })
        state.needDepart = false
    end

    local startZone, startName = Coords.ZoneAt(leg.inst, pts[1].x, pts[1].y)
    if state.zone == nil then
        state.zone = startZone
    elseif startZone and startZone ~= state.zone then



        local fx, fy = further(1, Instructions.ZONE_CONFIRM_YARDS)
        if fx and Coords.ZoneAt(leg.inst, fx, fy) == startZone then
            state.zone = startZone
            local here = steps[#steps]
            if here and here.legIndex == li and here.pointIndex == 1 then
                here.zone, here.zoneName = startZone, startName
                addZone(here)
            else
                addStep(steps, { kind = "zone", legIndex = li, pointIndex = 1, inst = leg.inst, x = pts[1].x, y = pts[1].y,
                                 distanceFromStart = state.dist, seconds = state.secs, text = format(L["Entering %s"], startName),
                                 shortText = startName, voiceText = format(L["Entering %s."], startName), zone = startZone })
            end
        end
    end



    local function dropTurn(step)
        local guess = step.guess
        step.deg, step.landmark, step.near = nil, nil, nil
        if guess then
            step.kind = "continue"

            step.text, step.shortText, step.voiceText, step.guessVoice = guess.text, guess.shortText, guess.voiceText, nil
            addZone(step)
        elseif step.zoneName then
            step.kind = "zone"
            step.text, step.shortText, step.voiceText = format(L["Entering %s"], step.zoneName), step.zoneName, format(L["Entering %s."], step.zoneName)
            step.zoneName, step.zoneVoice = nil, nil
        else
            removeStep(steps, step)
        end
    end









    local room = pts[1].room
    if room == nil and n >= 2 and not pts[1].door and not pts[2].door then room = pts[2].room end
    local climbing, lastClimb
    local function addEnter(at, name)
        local q = pts[at]
        local text = format(L["Enter %s"], name)
        addStep(steps, { kind = "enter", legIndex = li, pointIndex = at, inst = leg.inst, x = q.x, y = q.y,
                         distanceFromStart = state.dist + cum[at], seconds = eta(cum[at]), text = text, shortText = text,
                         voiceText = text .. ".", room = name })
    end

    local lastSig = 1
    local lastTurn
    for i = 2, n do
        local p = pts[i]
        local way = p.climbForm and climbWay(pts, i) or nil
        if way and way ~= climbing then
            local top = i
            while top < n and pts[top + 1].climbForm and climbWay(pts, top + 1) == way do top = top + 1 end



            if lastClimb and lastClimb.way == way and cum[i - 1] - lastClimb.top < Instructions.MERGE_YARDS then
                lastClimb.top = cum[top]
            elseif pts[i - 1].stacked or pts[top].stacked then
                lastClimb = { way = way, top = cum[top] }
                local texts = LEVEL_TEXT[p.climbForm] or LEVEL_TEXT.climb
                local text = way > 0 and texts.up or texts.down
                local q = pts[i - 1]
                addStep(steps, { kind = "level", legIndex = li, pointIndex = i - 1, inst = leg.inst, x = q.x, y = q.y,
                                 distanceFromStart = state.dist + cum[i - 1], seconds = eta(cum[i - 1]), text = text,
                                 shortText = text, voiceText = text .. ".", climbForm = p.climbForm, up = way > 0 })
            end
        end
        climbing = way
        local entered = p.room ~= nil and p.room ~= room
        if entered and pts[i - 1].door then
            addEnter(i - 1, p.room)
            entered = false
        end
        if i < n then

            local incoming, outgoing = isOpenGround(p.k), isOpenGround(pts[i + 1].k)
            local stretch = 0
            local steepNote
            local checked = false
            if outgoing and not incoming then
                local j = i + 1
                checked = CHECKED[pts[j].k] == true
                while j < n and isOpenGround(pts[j + 1].k) do
                    j = j + 1
                    if not CHECKED[pts[j].k] then checked = false end
                end
                stretch = cum[j] - cum[i]




                for k = i + 1, j do
                    if pts[k].steep then steepNote = leg.climbNote or L["The way on is well above or below this line."] break end
                end
            end
            local guess
            if stretch >= Instructions.MIN_UNVERIFIED_YARDS or (steepNote and stretch > 0) then
                local bearing = Coords.Bearing(p.x, p.y, pts[i + 1].x, pts[i + 1].y)
                local compass = Coords.CompassName(bearing)
                local distance = Util.FormatDistance(stretch, distanceUnits())
                local text, voiceText
                if checked then
                    text = format(L["Continue %s across open ground for %s"], compass, distance)
                    voiceText = format(L["Continue %s across open ground for %s."], compass, spokenDistance(stretch))
                else
                    text = format(L["Continue %s across open ground for %s"], compass, distance)
                    voiceText = format(L["Continue %s across open ground for %s."], compass, spokenDistance(stretch))
                end
                if steepNote then
                    text = text .. " " .. steepNote
                    voiceText = voiceText .. " " .. steepNote
                end
                guess = { compass = compass, distance = distance, steepNote = steepNote, text = text, checked = checked or nil,
                          shortText = format(L["Continue %s"], compass), voiceText = voiceText }
            end
            local turnHere


            local insideChecked = CHECKED[p.k] and CHECKED[pts[i + 1].k]
            if not insideChecked and dist(pts[lastSig], p) >= minSeg then
                local j = ahead(i)
                if dist(p, pts[j]) >= minSeg then
                    local bIn = Coords.Bearing(pts[lastSig].x, pts[lastSig].y, p.x, p.y)
                    local bOut = Coords.Bearing(p.x, p.y, pts[j].x, pts[j].y)
                    local vertex = Coords.AngleDelta(bIn, bOut) * 180 / pi
                    local deg, how = judged(i, vertex)
                    local bend = how == "bend"




                    if lastTurn and SURFACE[p.k] and SURFACE[pts[i + 1].k]
                        and (lastTurn.surface or (how == "surface" and lastTurn.windowed))
                        and state.dist + cum[i] - lastTurn.lastAt < Instructions.SURFACE_TURN_YARDS then
                        deg, bend = 0, false
                    end






                    if bend and (SURFACE[p.k] or SURFACE[pts[i + 1].k]) and classify(vertex) and lastTurn
                        and state.dist + cum[i] - lastTurn.distanceFromStart < Instructions.MERGE_YARDS then
                        lastTurn.turned = lastTurn.turned + vertex
                        lastTurn.sharp = lastTurn.sharp + (abs(vertex) >= Instructions.SHARP_DEGREES and 1 or 0)
                        lastTurn.lastAt = state.dist + cum[i]
                        if not classifyTurn(lastTurn, legEnd) then
                            dropTurn(lastTurn)
                            lastTurn = nil
                        end
                    elseif classify(deg) then
                        local along = cum[i]
                        local absolute = state.dist + along
                        local sharp = abs(deg) >= Instructions.SHARP_DEGREES and 1 or 0



                        local merge = lastTurn and (absolute - lastTurn.distanceFromStart < Instructions.MERGE_YARDS
                            or (lastTurn.sharp == 0 and sharp == 0 and abs(lastTurn.turned) >= Instructions.UTURN_DEGREES
                                and (lastTurn.turned > 0) == (deg > 0) and absolute - lastTurn.lastAt < Instructions.MERGE_YARDS))

                        local near
                        if not merge then
                            near = Instructions.LandmarkNear(leg.inst, p.x, p.y, nil, skip, p.z)




                            merge = near ~= nil and lastTurn ~= nil and steps[#steps] == lastTurn and lastTurn.near == near
                                and (lastTurn.turned > 0) == (deg > 0) and absolute - lastTurn.lastAt < Instructions.LANDMARK_YARDS
                                and abs(lastTurn.turned + deg) < 180
                        end
                        if merge then
                            lastTurn.turned = lastTurn.turned + deg
                            lastTurn.sharp = lastTurn.sharp + sharp
                            lastTurn.lastAt = absolute
                            if how == "surface" then lastTurn.surface = true end
                            if how == "surface" or how == "corner" then lastTurn.windowed = true end
                            if not classifyTurn(lastTurn, legEnd) then
                                dropTurn(lastTurn)
                                lastTurn = nil
                            end
                        else



                            local before, landmark = steps[#steps], near
                            if near and before and before.legIndex == li and (before.near or before.landmark) == near then landmark = nil end
                            local step = { legIndex = li, pointIndex = i, inst = leg.inst, x = p.x, y = p.y,
                                           distanceFromStart = absolute, seconds = eta(along), turned = deg, sharp = sharp,
                                           lastAt = absolute, landmark = landmark, near = near,
                                           surface = how == "surface" or nil, toward = townAhead(leg, i),
                                           windowed = (how == "surface" or how == "corner") or nil }
                            if guess then
                                step.guess, step.unverified, step.steep = guess, not guess.checked or nil, guess.steepNote ~= nil or nil
                            end
                            if classifyTurn(step, legEnd) then
                                lastTurn = addStep(steps, step)
                                turnHere = true
                            end
                        end
                    end
                end
                lastSig = i
            end
            if guess and not turnHere then
                addStep(steps, { kind = "continue", legIndex = li, pointIndex = i, inst = leg.inst, x = p.x, y = p.y,
                                 distanceFromStart = state.dist + cum[i], seconds = eta(cum[i]), text = guess.text,
                                 shortText = guess.shortText, voiceText = guess.voiceText,
                                 unverified = not guess.checked or nil, steep = guess.steepNote ~= nil or nil })
            end
        end




        local zoneID, zoneName = Coords.ZoneAt(leg.inst, p.x, p.y)
        if zoneID and zoneID ~= state.zone then
            local fx, fy = further(i, Instructions.ZONE_CONFIRM_YARDS)
            if fx and Coords.ZoneAt(leg.inst, fx, fy) == zoneID then
                state.zone = zoneID
                local here = steps[#steps]
                if here and here.legIndex == li and here.pointIndex == i then
                    here.zone, here.zoneName = zoneID, zoneName
                    addZone(here)
                else
                    addStep(steps, { kind = "zone", legIndex = li, pointIndex = i, inst = leg.inst, x = p.x, y = p.y,
                                     distanceFromStart = state.dist + cum[i], seconds = eta(cum[i]), text = format(L["Entering %s"], zoneName),
                                     shortText = zoneName, voiceText = format(L["Entering %s."], zoneName), zone = zoneID })
                end
            end
        end
        if entered then addEnter(i, p.room) end
        room = p.room
    end
    state.dist = state.dist + legYards
    state.secs = state.secs + legSeconds
end



local function landingHeight(leg, field)
    local T = FGPS.Transport
    local index = T and T.LegStopIndex and T.LegStopIndex(leg, field) or leg[field .. "Index"]
    local records = FGPS.Data and FGPS.Data.transports
    local rec = leg.transportID and records and records[leg.transportID]
    local stop = rec and type(rec.stops) == "table" and type(index) == "number" and rec.stops[index]
    if type(stop) == "table" and type(stop.z) == "number" then return stop.z end
    local G, key = FGPS.Graph, field == "stopFrom" and leg.fromKey or leg.toKey
    if G and G.NodeHeight and type(key) == "number" then
        local ok, z = pcall(G.NodeHeight, G, key)
        if ok and type(z) == "number" then return z end
    end
    return nil
end



local LIFT_RISE_YARDS = 5
local function liftDirection(leg)
    local from, to = landingHeight(leg, "stopFrom"), landingHeight(leg, "stopTo")
    if not from or not to or abs(to - from) < LIFT_RISE_YARDS then return nil end
    return to > from and "up" or "down"
end

local function transportSteps(route, steps, leg, li, state)
    local pts = leg.points
    local first, last = pts[1], pts[#pts]
    local kind = leg.kind
    local fromName = leg.stopFrom or zoneNameAt(leg.inst, first.x, first.y) or L["the dock"]
    local toName = leg.stopTo or zoneNameAt(leg.toInst or leg.inst, last.x, last.y) or L["the far side"]
    local rideSeconds = (leg.seconds or 0) - (leg.wait or 0) - (leg.penaltySeconds or 0)
    if rideSeconds < 0 then rideSeconds = 0 end

    local rideSpoken = spokenDuration(rideSeconds)
    local boardKind, leaveKind = "board", "disembark"
    local text, short, voice, leaveText, leaveShort, leaveVoice
    if kind == "taxi" then
        boardKind, leaveKind = "fly", "land"
        local dest = leg.taxiTo and FGPS.Data and FGPS.Data.taxi and FGPS.Data.taxi.nodes and FGPS.Data.taxi.nodes[leg.taxiTo]
        local destName = dest and dest.name or toName
        local srcNode = leg.taxiFrom and FGPS.Data and FGPS.Data.taxi and FGPS.Data.taxi.nodes and FGPS.Data.taxi.nodes[leg.taxiFrom]
        local srcName = srcNode and srcNode.name or fromName
        text = format(L["Take the flight from %s to %s (%s)"], srcName, destName, rideSpoken)
        short = format(L["Fly to %s"], destName)
        voice = format(L["Talk to the flight master and take the flight to %s. The flight takes %s."], destName, rideSpoken)
        leaveText = format(L["Land at %s"], destName)
        leaveShort = format(L["Land at %s"], destName)
        leaveVoice = format(L["You land at %s."], destName)
    elseif kind == "boat" or kind == "zeppelin" then
        local vehicle = kind == "boat" and L["boat"] or L["zeppelin"]
        text = format(L["Board the %s to %s at %s (%s)"], vehicle, toName, fromName, rideSpoken)
        short = format(L["Board %s"], vehicle)
        voice = format(L["Board the %s to %s. The crossing takes %s."], vehicle, toName, rideSpoken)
        leaveText = format(L["Disembark at %s"], toName)
        leaveShort = L["Disembark"]
        leaveVoice = format(L["Disembark at %s."], toName)
    elseif kind == "tram" then
        text = format(L["Board the tram at %s (%s)"], fromName, rideSpoken)
        short = L["Board tram"]
        voice = format(L["Board the tram. The ride takes %s."], rideSpoken)
        leaveText = format(L["Leave the tram at %s"], toName)
        leaveShort = L["Leave tram"]
        leaveVoice = format(L["Leave the tram at %s."], toName)
    elseif kind == "elevator" then


        local way = liftDirection(leg)
        if way == "up" then
            text, short = format(L["Take the elevator up to %s"], toName), L["Elevator up"]
        elseif way == "down" then
            text, short = format(L["Take the elevator down to %s"], toName), L["Elevator down"]
        else
            text, short = format(L["Take the elevator to %s"], toName), L["Take elevator"]
        end
        voice = text .. "."
        leaveText = format(L["Leave the elevator at %s"], toName)
        leaveShort = L["Leave elevator"]
        leaveVoice = leaveText .. "."
    else
        local label = leg.label and leg.label ~= "" and leg.label or L["the portal"]
        text = format(L["Go through %s"], label)
        short = L["Take portal"]
        voice = format(L["Go through %s."], label)
    end
    addStep(steps, { kind = boardKind, legIndex = li, pointIndex = 1, inst = leg.inst, x = first.x, y = first.y,
                     distanceFromStart = state.dist, seconds = state.secs, text = text, shortText = short, voiceText = voice,
                     transportID = leg.transportID, taxiFrom = leg.taxiFrom, taxiTo = leg.taxiTo, duration = rideSeconds, wait = leg.wait,
                     label = leg.label, mode = kind, way = kind == "elevator" and liftDirection(leg) or nil })
    state.dist = state.dist + (leg.yards or 0)
    state.secs = state.secs + (leg.seconds or 0)
    if leaveText then
        addStep(steps, { kind = leaveKind, legIndex = li, pointIndex = #pts, inst = leg.toInst or leg.inst, x = last.x, y = last.y,
                         distanceFromStart = state.dist, seconds = state.secs, text = leaveText, shortText = leaveShort, voiceText = leaveVoice,
                         transportID = leg.transportID, taxiTo = leg.taxiTo, label = leg.label, mode = kind })
    end
    state.needDepart = true
    state.zone = nil
end








local function arrivalName(leg)
    if leg.kind == "taxi" then
        local nodes = FGPS.Data and FGPS.Data.taxi and FGPS.Data.taxi.nodes
        local dest = leg.taxiTo and nodes and nodes[leg.taxiTo]
        if dest and dest.name then return dest.name end
    end
    local pts = leg.points
    local last = pts and pts[#pts]
    return leg.stopTo or (last and zoneNameAt(leg.toInst or leg.inst, last.x, last.y)) or L["the far side"]
end

local function vehicleName(leg)
    if leg.kind == "boat" then return L["boat"] end
    if leg.kind == "zeppelin" then return L["zeppelin"] end
    if leg.kind == "tram" then return L["tram"] end
    if leg.kind == "elevator" then return L["elevator"] end
    return L["transport"]
end


function Instructions.RideText(leg, secondsLeft)
    if type(leg) ~= "table" then return nil end
    local text
    if leg.kind == "taxi" then
        text = format(L["Flying to %s"], arrivalName(leg))
    elseif leg.kind == "elevator" then
        text = L["Ride the elevator"]
    else
        text = format(L["Ride the %s to %s"], vehicleName(leg), arrivalName(leg))
    end
    return text
end



function Instructions.WaitText(leg, secondsToDeparture)
    if type(leg) ~= "table" then return nil end
    local text = format(L["Board the %s to %s"], vehicleName(leg), arrivalName(leg))
    return text
end


function Instructions.WrongRideText(leg)
    if type(leg) ~= "table" then return nil end
    return format(L["This is not the %s to %s. A new route follows when you get off."], vehicleName(leg), arrivalName(leg))
end

local function teleportSteps(route, steps, leg, li, state)
    local pts = leg.points
    local first, last = pts[1], pts[#pts]
    local option = leg.option or {}
    local name = option.bindName or option.name or leg.label or ""
    local kind, text, short, voice
    if leg.kind == "hearth" then
        kind = "hearth"
        text = format(L["Use your Hearthstone to return to %s"], name)
        short = L["Use Hearthstone"]
        voice = format(L["Use your Hearthstone to return to %s."], name)
    else
        kind = "cast"
        text = format(L["Cast %s"], name)
        short = format(L["Cast %s"], name)
        voice = format(L["Cast %s."], name)
    end
    if (leg.wait or 0) > 0 then
        text = text .. format(L[" (available in %s)"], shortTime(leg.wait))
        voice = voice .. " " .. format(L["It is available in %s."], spokenDuration(leg.wait))
    end
    addStep(steps, { kind = kind, legIndex = li, pointIndex = 1, inst = leg.inst, x = first.x, y = first.y,
                     distanceFromStart = state.dist, seconds = state.secs, text = text, shortText = short, voiceText = voice,
                     wait = leg.wait, option = option, arrivalInst = leg.toInst or leg.inst, arrivalX = last.x, arrivalY = last.y })
    state.secs = state.secs + (leg.seconds or 0)
    state.needDepart = true
    state.zone = nil
end


function Instructions.Build(route)
    local steps = {}
    if type(route) ~= "table" or type(route.legs) ~= "table" then
        if type(route) == "table" then route.steps = steps end
        return steps
    end
    local legs = route.legs
    local state = { dist = 0, secs = 0, needDepart = true, zone = nil }
    local stopCount = route.stops and #route.stops or 0
    for li, leg in ipairs(legs) do
        if leg.kind == "walk" then
            walkSteps(route, steps, leg, li, state)
        elseif leg.kind == "hearth" or leg.kind == "spell" then
            teleportSteps(route, steps, leg, li, state)
        else
            transportSteps(route, steps, leg, li, state)
        end
        local nextLeg = legs[li + 1]
        local stopIndex = leg.stopIndex or 1
        local lastOfStop = (not nextLeg) or (nextLeg.stopIndex or 1) ~= stopIndex
        if lastOfStop then
            local final = not nextLeg
            local last = leg.points[#leg.points]
            local name = stopName(route, stopIndex, final)
            local text, short, voice
            if final then
                text = format(L["Arrive at %s"], name)
                short = format(L["Arrive at %s"], name)
                voice = format(L.ARRIVED_AT, name)
            else
                text = format(L["Stop %d: %s"], stopIndex, name)
                short = format(L["Stop %d"], stopIndex)
                voice = format(L["You have reached stop %d, %s. Continue to the next stop."], stopIndex, name)
            end
            addStep(steps, { kind = final and "arrive" or "stop_arrive", legIndex = li, pointIndex = #leg.points, inst = leg.toInst or leg.inst,
                             x = last.x, y = last.y, distanceFromStart = state.dist, seconds = state.secs, text = text, shortText = short,
                             voiceText = voice, stopIndex = stopIndex, final = final })
            state.needDepart = true
        end
    end




    local atLeg, atPoint = 1, 1
    for i, step in ipairs(steps) do
        step.index = i
        local yards = 0
        for li = atLeg, step.legIndex do
            local pts = legs[li].kind == "walk" and legs[li].points or nil
            for k = (li == atLeg and atPoint or 1) + 1, pts and (li == step.legIndex and step.pointIndex or #pts) or 0 do
                if UNVERIFIED[pts[k].k] then yards = yards + dist(pts[k - 1], pts[k]) end
            end
        end
        step.guessedYards = yards
        atLeg, atPoint = step.legIndex, step.pointIndex
    end
    route.steps = steps
    route.stopCount = stopCount
    return steps
end







function Instructions.NextActionable(route, progress)
    if type(route) ~= "table" then return nil end
    local steps = route.steps
    if not steps or #steps == 0 then steps = Instructions.Build(route) end
    if #steps == 0 then return nil end
    if type(progress) ~= "table" or progress.legIndex == nil then return steps[1] end
    local li, pi = progress.legIndex or 1, progress.pointIndex or 0
    for _, step in ipairs(steps) do
        if step.legIndex > li or (step.legIndex == li and step.pointIndex > pi) then return step end
    end
    return steps[#steps]
end

function Instructions:Init()
    self.initialized = true
end
