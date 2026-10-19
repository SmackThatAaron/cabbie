


















local ADDON_NAME, FGPS = ...

local Route = {}
FGPS.Route = Route

local L = FGPS.L
local sqrt, floor, huge = math.sqrt, math.floor, math.huge
local type, pairs, ipairs = type, pairs, ipairs

Route.FLAGS = {
    VERIFIED = 1, TAXI = 2, TRANSPORT = 4, PORTAL = 8, ZONE = 16, INDOOR = 32, WATER = 64, POI = 128,
    BOUNDARY = 256, STOP = 512, ORIGIN = 1024, TELEPORT = 2048,
}
local F = Route.FLAGS
Route.PRESERVE_BITS = { F.TAXI, F.TRANSPORT, F.PORTAL, F.ZONE, F.BOUNDARY, F.STOP, F.ORIGIN, F.TELEPORT }
Route.SIMPLIFY_TOLERANCE = 4
Route.UNVERIFIED_KINDS = { [3] = true, [14] = true, [15] = true }




Route.APPROXIMATE_KINDS = { [4] = true }



Route.OPEN_GROUND_KINDS = { [19] = true }


Route.SURFACE_KINDS = { [22] = true, [23] = true }
function Route.IsOpenGround(kind)
    return Route.UNVERIFIED_KINDS[kind] == true or Route.OPEN_GROUND_KINDS[kind] == true
end


Route.KIND4_PAINT_ERROR_SAMPLES = {
    elwynn_eastvale_5_none = {
        src = "signpost:Eastvale Logging Camp:5-None",
        map = 1429,
        chordYards = 177.4,
        shapeYards = 370.9,
    },
}
function Route.Kind4PaintExcessYards(sample)
    return sample.shapeYards - sample.chordYards
end

local drawDashed
function Route.DashedKinds()
    if not drawDashed then
        drawDashed = {}
        for k in pairs(Route.UNVERIFIED_KINDS) do drawDashed[k] = true end
        for k in pairs(Route.APPROXIMATE_KINDS) do drawDashed[k] = true end
        for k in pairs(Route.OPEN_GROUND_KINDS) do drawDashed[k] = true end
    end
    return drawDashed
end

local TRANSPORT_LABELS = {
    taxi = L["Flight"], boat = L["Boat"], zeppelin = L["Zeppelin"], tram = L["Tram"], elevator = L["Elevator"],
    portal = L["Portal"], hearth = L["Hearthstone"], spell = L["Teleport"],
}




function Route.HasFlag(flags, bit)
    if not flags or flags == 0 then return false end
    return floor(flags / bit) % 2 == 1
end
local hasFlag = Route.HasFlag

function Route.AddFlag(flags, bit)
    flags = flags or 0
    if hasFlag(flags, bit) then return flags end
    return flags + bit
end

function Route.IsPreserved(point)
    local flags = point and point.f
    if not flags or flags == 0 then return false end
    local bits = Route.PRESERVE_BITS
    for i = 1, #bits do
        if hasFlag(flags, bits[i]) then return true end
    end
    return false
end












function Route.MustKeep(points, i)
    local p = points[i]
    if Route.IsPreserved(p) then return true end
    local q = points[i + 1]
    if not (p and q) then return false end
    if p.climbForm or q.climbForm then return true end


    local o = points[i - 1]
    if p.stacked then
        if not q.stacked or (o and not o.stacked) then return true end
    elseif q.stacked or (o and o.stacked) then
        return true
    end
    local dashed = Route.DashedKinds()
    return (dashed[p.k] or false) ~= (dashed[q.k] or false)
end

function Route.LegLabel(kind)
    return TRANSPORT_LABELS[kind] or kind
end




function Route.Cumulative(leg)
    local cum = leg._cum
    local points = leg.points
    if cum and cum.n == #points then return cum end
    cum = { n = #points }
    local total = 0
    cum[1] = 0
    for i = 2, #points do
        local a, b = points[i - 1], points[i]
        if leg.split and i - 1 == leg.split then

        else
            local dx, dy = b.x - a.x, b.y - a.y
            total = total + sqrt(dx * dx + dy * dy)
        end
        cum[i] = total
    end
    cum.total = total
    leg._cum = cum
    return cum
end






function Route.Project(leg, x, y)
    local points = leg.points
    local n = points and #points or 0
    if n == 0 then return nil end
    if n == 1 then
        local p = points[1]
        local dx, dy = p.x - x, p.y - y
        return 1, 0, sqrt(dx * dx + dy * dy), 0
    end
    local cum = Route.Cumulative(leg)
    local bestI, bestT, bestD2, bestAlong = 1, 0, huge, 0
    for i = 1, n - 1 do
        if not (leg.split and i == leg.split) then
            local a, b = points[i], points[i + 1]
            local vx, vy = b.x - a.x, b.y - a.y
            local len2 = vx * vx + vy * vy
            local t = 0
            if len2 > 0 then
                t = ((x - a.x) * vx + (y - a.y) * vy) / len2
                if t < 0 then t = 0 elseif t > 1 then t = 1 end
            end
            local px, py = a.x + t * vx - x, a.y + t * vy - y
            local d2 = px * px + py * py
            if d2 < bestD2 then
                bestD2, bestI, bestT = d2, i, t
                bestAlong = cum[i] + t * sqrt(len2)
            end
        end
    end
    return bestI, bestT, sqrt(bestD2), bestAlong
end




Route.WINDOW_AHEAD_YARDS = 60
Route.WINDOW_BAND_YARDS = 40













function Route.ProjectWindow(leg, x, y, fromIndex, aheadYards, bandYards, sinceAlong)
    local points = leg and leg.points
    local n = points and #points or 0
    if n < 2 then return Route.Project(leg, x, y) end
    local cum = Route.Cumulative(leg)
    local from = fromIndex or 1
    if from < 1 then from = 1 end
    from = from - 2
    if from < 1 then from = 1 end
    if from > n - 1 then from = n - 1 end
    aheadYards = aheadYards or Route.WINDOW_AHEAD_YARDS
    bandYards = bandYards or Route.WINDOW_BAND_YARDS
    local bestI, bestT, bestD2, bestAlong
    local originAlong = cum[from]
    if sinceAlong then
        while from > 1 and cum[from] > sinceAlong do from = from - 1 end
        originAlong = sinceAlong
    end
    for i = from, n - 1 do
        if cum[i] - originAlong > aheadYards then break end
        if not (leg.split and i == leg.split) then
            local a, b = points[i], points[i + 1]
            local vx, vy = b.x - a.x, b.y - a.y
            local len2 = vx * vx + vy * vy
            local t = 0
            if len2 > 0 then
                t = ((x - a.x) * vx + (y - a.y) * vy) / len2
                if t < 0 then t = 0 elseif t > 1 then t = 1 end
            end
            local px, py = a.x + t * vx - x, a.y + t * vy - y
            local d2 = px * px + py * py
            if not bestD2 or d2 < bestD2 then
                bestD2, bestI, bestT = d2, i, t
                bestAlong = cum[i] + t * sqrt(len2)
            end
        end
    end
    if not bestI or sqrt(bestD2) > bandYards then return Route.Project(leg, x, y) end
    return bestI, bestT, sqrt(bestD2), bestAlong
end




function Route.ProjectRange(leg, x, y, loAlong, hiAlong)
    local points = leg and leg.points
    local n = points and #points or 0
    if n < 2 then return Route.Project(leg, x, y) end
    local cum = Route.Cumulative(leg)
    local bestI, bestT, bestD2, bestAlong
    for i = 1, n - 1 do
        if cum[i] > hiAlong then break end
        if cum[i + 1] >= loAlong and not (leg.split and i == leg.split) then
            local a, b = points[i], points[i + 1]
            local vx, vy = b.x - a.x, b.y - a.y
            local len = sqrt(vx * vx + vy * vy)
            local t, lo, hi = 0, 0, 1
            if len > 0 then
                lo, hi = (loAlong - cum[i]) / len, (hiAlong - cum[i]) / len
                if lo < 0 then lo = 0 end
                if hi > 1 then hi = 1 end
                t = ((x - a.x) * vx + (y - a.y) * vy) / (len * len)
                if t < lo then t = lo elseif t > hi then t = hi end
            end
            local px, py = a.x + t * vx - x, a.y + t * vy - y
            local d2 = px * px + py * py
            if not bestD2 or d2 < bestD2 then
                bestD2, bestI, bestT = d2, i, t
                bestAlong = cum[i] + t * len
            end
        end
    end
    if not bestI then return nil end
    return bestI, bestT, sqrt(bestD2), bestAlong
end




function Route.PointAlong(leg, alongYards)
    local points = leg and leg.points
    local n = points and #points or 0
    if n == 0 then return nil end
    if n == 1 or not alongYards or alongYards <= 0 then return points[1].x, points[1].y end
    local cum = Route.Cumulative(leg)
    local total = cum.total or 0
    if alongYards >= total then return points[n].x, points[n].y end
    for i = 1, n - 1 do
        if not (leg.split and i == leg.split) then
            local nextAlong = cum[i + 1]
            if nextAlong >= alongYards then
                local seg = nextAlong - cum[i]
                local u = seg > 0 and (alongYards - cum[i]) / seg or 0
                local a, b = points[i], points[i + 1]
                return a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u
            end
        end
    end
    return points[n].x, points[n].y
end




function Route.LookAhead(leg, x, y, yards)
    if type(leg) ~= "table" or not x or not y then return nil end
    local _, _, _, along = Route.Project(leg, x, y)
    if not along then return nil end
    return Route.PointAlong(leg, along + (yards or 0))
end




local function legLength(leg)
    if leg.yards and leg.yards > 0 then return leg.yards end
    return Route.Cumulative(leg).total
end




function Route.RemainingYards(route, legIndex, pointIndex, x, y)
    local legs = route and route.legs
    if not legs or #legs == 0 then return 0 end
    legIndex = legIndex or 1
    local leg = legs[legIndex]
    if not leg then return 0 end
    local remaining = 0
    local points = leg.points
    local n = #points
    if n >= 2 then
        local cum = Route.Cumulative(leg)
        local i = pointIndex or 1
        if i < 1 then i = 1 end
        if i >= n then i = n - 1 end
        local nextPoint = points[i + 1]
        local toNext
        if x and y and not (leg.split and i == leg.split) then
            local dx, dy = nextPoint.x - x, nextPoint.y - y
            toNext = sqrt(dx * dx + dy * dy)
        else
            toNext = cum[i + 1] - cum[i]
        end
        local geometric = toNext + (cum.total - cum[i + 1])

        if cum.total > 0 and leg.yards and leg.yards > 0 and leg.kind ~= "walk" then
            geometric = geometric * (leg.yards / cum.total)
        end
        remaining = geometric
    else
        remaining = legLength(leg)
    end
    for i = legIndex + 1, #legs do
        remaining = remaining + legLength(legs[i])
    end
    return remaining
end


function Route.RemainingSeconds(route, legIndex, pointIndex, x, y)
    local legs = route and route.legs
    if not legs or #legs == 0 then return 0 end
    legIndex = legIndex or 1
    local leg = legs[legIndex]
    if not leg then return 0 end
    local remaining = 0
    local total = legLength(leg)
    if total > 0 then
        local currentRemainingYards = Route.RemainingYards({ legs = { leg } }, 1, pointIndex, x, y)
        local share = currentRemainingYards / total
        if share > 1 then share = 1 elseif share < 0 then share = 0 end
        remaining = (leg.seconds or 0) * share
    else
        remaining = leg.seconds or 0
    end
    for i = legIndex + 1, #legs do
        remaining = remaining + (legs[i].seconds or 0)
    end
    return remaining
end




local function perpendicular(p, a, b)
    local vx, vy = b.x - a.x, b.y - a.y
    local len2 = vx * vx + vy * vy
    if len2 == 0 then
        local dx, dy = p.x - a.x, p.y - a.y
        return sqrt(dx * dx + dy * dy)
    end
    local t = ((p.x - a.x) * vx + (p.y - a.y) * vy) / len2
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local px, py = a.x + t * vx - p.x, a.y + t * vy - p.y
    return sqrt(px * px + py * py)
end




function Route.Simplify(points, toleranceYards)
    local n = #points
    local out = {}
    if n <= 2 then
        for i = 1, n do out[i] = points[i] end
        return out
    end
    local tol = toleranceYards or Route.SIMPLIFY_TOLERANCE
    local keep = {}
    keep[1], keep[n] = true, true
    for i = 2, n - 1 do
        if Route.MustKeep(points, i) then keep[i] = true end
    end

    local stack = {}
    local last = 1
    for i = 2, n do
        if keep[i] then
            if i - last > 1 then stack[#stack + 1] = last stack[#stack + 1] = i end
            last = i
        end
    end
    while #stack > 0 do
        local hi = table.remove(stack)
        local lo = table.remove(stack)
        local a, b = points[lo], points[hi]
        local bestD, bestI = -1, nil
        for i = lo + 1, hi - 1 do
            local d = perpendicular(points[i], a, b)
            if d > bestD then bestD, bestI = d, i end
        end
        if bestI and bestD > tol then
            keep[bestI] = true
            if bestI - lo > 1 then stack[#stack + 1] = lo stack[#stack + 1] = bestI end
            if hi - bestI > 1 then stack[#stack + 1] = bestI stack[#stack + 1] = hi end
        end
    end
    for i = 1, n do
        if keep[i] then out[#out + 1] = points[i] end
    end
    return out
end








Route.SIMPLIFY_WINDOW = 32
function Route.SimplifyLinear(points, toleranceYards, window)
    local n = #points
    local out = {}
    if n <= 2 then
        for i = 1, n do out[i] = points[i] end
        return out
    end
    local tol = toleranceYards or Route.SIMPLIFY_TOLERANCE
    window = window or Route.SIMPLIFY_WINDOW
    out[1] = points[1]
    local anchor = 1
    while anchor < n do
        local best = anchor + 1
        local j = anchor + 2
        while j <= n and j - anchor <= window and not Route.MustKeep(points, j - 1) do
            local a, b = points[anchor], points[j]
            local fits = true
            for k = anchor + 1, j - 1 do
                if perpendicular(points[k], a, b) > tol then fits = false break end
            end
            if not fits then break end
            best = j
            j = j + 1
        end
        out[#out + 1] = points[best]
        anchor = best
    end
    return out
end




function Route.LegBounds(leg)
    local points = leg and leg.points
    if not points or #points == 0 then return nil end
    local minX, maxX, minY, maxY = huge, -huge, huge, -huge
    local limit = leg.split or #points
    for i = 1, limit do
        local p = points[i]
        if p.x < minX then minX = p.x end
        if p.x > maxX then maxX = p.x end
        if p.y < minY then minY = p.y end
        if p.y > maxY then maxY = p.y end
    end
    return minX, maxX, minY, maxY
end

local function deepCopy(value, seen)
    if type(value) ~= "table" then return value end
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for k, v in pairs(value) do
        if not (type(k) == "string" and k:sub(1, 1) == "_") then
            out[k] = deepCopy(v, seen)
        end
    end
    return out
end


function Route.Clone(route)
    return deepCopy(route, {})
end


function Route.Summary(route)
    local transports, seen = {}, {}
    local legs = route and route.legs or {}
    for _, leg in ipairs(legs) do
        if leg.kind ~= "walk" and not seen[leg.kind] then
            seen[leg.kind] = true
            transports[#transports + 1] = Route.LegLabel(leg.kind)
        end
    end
    return {
        transports = transports,
        eta = route and route.totalSeconds or 0,
        yards = route and route.totalYards or 0,
        unverifiedYards = route and route.unverifiedYards or 0,
        verifiedYards = route and route.verifiedYards or 0,


        roadYards = route and route.roadYards or 0,

        streetYards = route and route.streetYards or 0,


        meshYards = route and route.meshYards or 0,
        transfers = route and route.transfers or 0,
        stops = route and route.stops and #route.stops or 0,
        legs = #legs,
        fallback = route and route.fallback or nil,
        variant = route and route.variant or nil,
    }
end

function Route:Init()
    self.initialized = true
end
