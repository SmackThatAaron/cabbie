



















local ADDON_NAME, FGPS = ...

local Route = {}
FGPS.Route = Route

local L = FGPS.L
local sqrt, floor, huge, abs = math.sqrt, math.floor, math.huge, math.abs
local type, pairs, ipairs = type, pairs, ipairs

Route.FLAGS = {
    VERIFIED = 1, TAXI = 2, TRANSPORT = 4, PORTAL = 8, ZONE = 16, INDOOR = 32, WATER = 64, POI = 128,
    BOUNDARY = 256, STOP = 512, ORIGIN = 1024, TELEPORT = 2048,
}
local F = Route.FLAGS
Route.PRESERVE_BITS = { F.TAXI, F.TRANSPORT, F.PORTAL, F.ZONE, F.BOUNDARY, F.STOP, F.ORIGIN, F.TELEPORT }
Route.SIMPLIFY_TOLERANCE = 4
Route.UNVERIFIED_KINDS = { [3] = true, [14] = true, [15] = true }



Route.OPEN_GROUND_KINDS = { [19] = true }


Route.SURFACE_KINDS = { [22] = true, [23] = true }


local drawDashed
function Route.DashedKinds()
    if not drawDashed then
        drawDashed = {}
        for k in pairs(Route.UNVERIFIED_KINDS) do drawDashed[k] = true end
        for k in pairs(Route.OPEN_GROUND_KINDS) do drawDashed[k] = true end
    end
    return drawDashed
end





local strokeCache = {}
for k in pairs(Route.DashedKinds()) do strokeCache[k] = "dashed" end
local function strokeTable()
    return strokeCache
end

function Route.Stroke(kind)
    return strokeTable()[kind] or "solid"
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
    local stroke = strokeTable()
    return (stroke[p.k] or "solid") ~= (stroke[q.k] or "solid")
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
        if not (leg.split and i - 1 == leg.split) then
            local dx, dy = b.x - a.x, b.y - a.y
            total = total + sqrt(dx * dx + dy * dy)
        end
        cum[i] = total
    end
    cum.total = total
    leg._cum = cum
    return cum
end




Route.LEVEL_BAND_YARDS = 6
Route.LEVEL_WEIGHT = 3

local function segScoreD2(a, b, t, d2, z)
    if type(z) ~= "number" then return d2 end
    local az, bz = a.z, b.z
    local segZ
    if type(az) == "number" and type(bz) == "number" then
        segZ = az + t * (bz - az)
    elseif type(az) == "number" then
        segZ = az
    elseif type(bz) == "number" then
        segZ = bz
    end
    if segZ == nil then return d2 end
    local dz = abs(segZ - z) - Route.LEVEL_BAND_YARDS
    if dz <= 0 then return d2 end
    local w = dz * Route.LEVEL_WEIGHT
    return d2 + w * w
end





function Route.Project(leg, x, y, z)
    local points = leg.points
    local n = points and #points or 0
    if n == 0 then return nil end
    if n == 1 then
        local p = points[1]
        local dx, dy = p.x - x, p.y - y
        return 1, 0, sqrt(dx * dx + dy * dy), 0
    end
    local cum = Route.Cumulative(leg)
    local bestI, bestT, bestD2, bestScore, bestAlong = 1, 0, huge, huge, 0
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
            local score = segScoreD2(a, b, t, d2, z)
            if score < bestScore then
                bestScore, bestD2, bestI, bestT = score, d2, i, t
                bestAlong = cum[i] + t * sqrt(len2)
            end
        end
    end
    return bestI, bestT, sqrt(bestD2), bestAlong
end




Route.WINDOW_AHEAD_YARDS = 60
Route.WINDOW_BAND_YARDS = 40













function Route.ProjectWindow(leg, x, y, fromIndex, aheadYards, bandYards, sinceAlong, z)
    local points = leg and leg.points
    local n = points and #points or 0
    if n < 2 then return Route.Project(leg, x, y, z) end
    local cum = Route.Cumulative(leg)
    local from = fromIndex or 1
    if from < 1 then from = 1 end
    from = from - 2
    if from < 1 then from = 1 end
    if from > n - 1 then from = n - 1 end
    aheadYards = aheadYards or Route.WINDOW_AHEAD_YARDS
    bandYards = bandYards or Route.WINDOW_BAND_YARDS
    local bestI, bestT, bestD2, bestScore, bestAlong
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
            local score = segScoreD2(a, b, t, d2, z)
            if not bestScore or score < bestScore then
                bestScore, bestD2, bestI, bestT = score, d2, i, t
                bestAlong = cum[i] + t * sqrt(len2)
            end
        end
    end
    if not bestI or sqrt(bestD2) > bandYards then return Route.Project(leg, x, y, z) end
    return bestI, bestT, sqrt(bestD2), bestAlong
end




function Route.ProjectRange(leg, x, y, loAlong, hiAlong, z)
    local points = leg and leg.points
    local n = points and #points or 0
    if n < 2 then return Route.Project(leg, x, y, z) end
    local cum = Route.Cumulative(leg)
    local bestI, bestT, bestD2, bestScore, bestAlong
    for i = 1, n - 1 do
        if cum[i] > hiAlong then break end
        if cum[i + 1] >= loAlong and not (leg.split and i == leg.split) then
            local a, b = points[i], points[i + 1]
            local vx, vy = b.x - a.x, b.y - a.y
            local len = sqrt(vx * vx + vy * vy)
            local t = 0
            if len > 0 then
                local lo, hi = (loAlong - cum[i]) / len, (hiAlong - cum[i]) / len
                if lo < 0 then lo = 0 end
                if hi > 1 then hi = 1 end
                t = ((x - a.x) * vx + (y - a.y) * vy) / (len * len)
                if t < lo then t = lo elseif t > hi then t = hi end
            end
            local px, py = a.x + t * vx - x, a.y + t * vy - y
            local d2 = px * px + py * py
            local score = segScoreD2(a, b, t, d2, z)
            if not bestScore or score < bestScore then
                bestScore, bestD2, bestI, bestT = score, d2, i, t
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





local function legRemaining(leg, pointIndex, x, y)
    local remaining
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
    return remaining
end




function Route.RemainingYards(route, legIndex, pointIndex, x, y)
    local legs = route and route.legs
    if not legs or #legs == 0 then return 0 end
    legIndex = legIndex or 1
    local leg = legs[legIndex]
    if not leg then return 0 end
    local remaining = legRemaining(leg, pointIndex, x, y)
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
    local remaining
    local total = legLength(leg)
    if total > 0 then
        local currentRemainingYards = legRemaining(leg, pointIndex, x, y)
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




local SMOOTH_SHAPE_KINDS = { [4] = true, [16] = true, [17] = true, [18] = true }

local function lerpShapePoint(a, b, t)
    local z
    if type(a.z) == "number" and type(b.z) == "number" then
        z = a.z + (b.z - a.z) * t
    end
    return { x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t, z = z }
end

local function chaikinPass(chain, maxCut, keepMidOnWide)
    local m = #chain
    local out = { chain[1] }
    for i = 2, m - 1 do
        local prev, cur, nxt = chain[i - 1], chain[i], chain[i + 1]
        local dx1, dy1 = cur.x - prev.x, cur.y - prev.y
        local dx2, dy2 = nxt.x - cur.x, nxt.y - cur.y
        local l1, l2 = sqrt(dx1 * dx1 + dy1 * dy1), sqrt(dx2 * dx2 + dy2 * dy2)
        if l1 > 0.25 and l2 > 0.25 then
            local cosA = (dx1 * dx2 + dy1 * dy2) / (l1 * l2)
            if cosA < 0.999 and cosA > -0.75 then
                local c1 = maxCut < 0.25 * l1 and maxCut or (0.25 * l1)
                local c2 = maxCut < 0.25 * l2 and maxCut or (0.25 * l2)
                local q = lerpShapePoint(cur, prev, c1 / l1)
                local r = lerpShapePoint(cur, nxt, c2 / l2)
                out[#out + 1] = q
                if keepMidOnWide then
                    local qrx, qry = r.x - q.x, r.y - q.y
                    if qrx * qrx + qry * qry > 4.84 then
                        local mz
                        if type(q.z) == "number" and type(cur.z) == "number" and type(r.z) == "number" then
                            mz = 0.25 * q.z + 0.5 * cur.z + 0.25 * r.z
                        end
                        out[#out + 1] = {
                            x = 0.25 * q.x + 0.5 * cur.x + 0.25 * r.x,
                            y = 0.25 * q.y + 0.5 * cur.y + 0.25 * r.y,
                            z = mz,
                        }
                    end
                end
                out[#out + 1] = r
            else
                out[#out + 1] = cur
            end
        else
            out[#out + 1] = cur
        end
    end
    out[#out + 1] = chain[m]
    return out
end

local function thinSmoothedChain(chain, tol, maxStep)
    local m = #chain
    if m <= 2 then return chain end
    local out = { chain[1] }
    local anchor = 1
    while anchor < m do
        local best = anchor + 1
        local j = anchor + 2
        while j <= m and j - anchor <= 16 do
            local a, b = chain[anchor], chain[j]
            local dx, dy = b.x - a.x, b.y - a.y
            local chord = sqrt(dx * dx + dy * dy)
            local curved = false
            local fits = true
            for k = anchor + 1, j - 1 do
                local d = perpendicular(chain[k], a, b)
                if d > 0.04 then curved = true end
                if d > tol then fits = false break end
                if type(a.z) == "number" and type(b.z) == "number" and type(chain[k].z) == "number" and chord > 0.01 then
                    local u = ((chain[k].x - a.x) * dx + (chain[k].y - a.y) * dy) / (chord * chord)
                    if u < 0 then u = 0 elseif u > 1 then u = 1 end
                    if abs(chain[k].z - (a.z + (b.z - a.z) * u)) > 0.4 then fits = false break end
                end
            end
            if not fits or (curved and chord > maxStep) then break end
            best = j
            j = j + 1
        end
        out[#out + 1] = chain[best]
        anchor = best
    end
    return out
end

local function shapeBlocked(p)
    return not p or Route.IsPreserved(p) or p.indoor or p.stacked or p.door or p.climbForm
        or p.steep or p.hazard or p.corridorX or p.corridorY or p.corridorBefore
end

local function endBlocked(p)
    return not p or p.indoor or p.stacked or p.door or p.climbForm or p.hazard
end



local function nearSharpHook(pts, idx, n)
    local lo = idx - 2
    if lo < 2 then lo = 2 end
    local hi = idx + 2
    if hi > n - 1 then hi = n - 1 end
    for k = lo, hi do
        local a, b, c = pts[k - 1], pts[k], pts[k + 1]
        local dx1, dy1 = b.x - a.x, b.y - a.y
        local dx2, dy2 = c.x - b.x, c.y - b.y
        local l1, l2 = sqrt(dx1 * dx1 + dy1 * dy1), sqrt(dx2 * dx2 + dy2 * dy2)
        if l1 > 0.2 and l2 > 0.2 and (l1 < 8 or l2 < 8) then
            if (dx1 * dx2 + dy1 * dy2) / (l1 * l2) <= -0.34 then
                return true
            end
        end
    end
    return false
end






function Route.SmoothLeg(leg, opts)
    if type(leg) ~= "table" or leg.kind ~= "walk" or leg.split then return end
    local pts = leg.points
    local n = pts and #pts or 0
    if n < 3 then return end
    opts = opts or {}
    local highRes = opts.highRes == true
    local wantSurface = opts.canShortcut ~= nil or opts.smoothSurface == true
    local hasShapeRun, hasSurfaceRun = false, false
    for i = 2, n - 1 do
        local pk = pts[i].k
        if pts[i].shape and SMOOTH_SHAPE_KINDS[pk] and pts[i + 1].shape and pts[i + 1].k == pk then
            hasShapeRun = true
        elseif wantSurface and pk == 22 and pts[i + 1].k == 22 then
            hasSurfaceRun = true
        end
        if hasShapeRun and (hasSurfaceRun or not wantSurface) then break end
    end
    if not hasShapeRun and not hasSurfaceRun then return end

    local changed = false
    if hasShapeRun then
        if highRes then
            local tol = 0.06
            local maxStep = 2.4
            local nextPts = {}
            local i = 1
            while i <= n do
                local p = pts[i]
                if i >= 2 and i <= n - 2 and p.shape and SMOOTH_SHAPE_KINDS[p.k]
                    and not shapeBlocked(p) and not endBlocked(pts[i - 1]) then
                    local kind, room = p.k, p.room
                    local j = i
                    while j + 1 <= n - 1 and pts[j + 1].shape and pts[j + 1].k == kind
                        and pts[j + 1].room == room and not shapeBlocked(pts[j + 1]) do
                        j = j + 1
                    end
                    if j >= i + 1 and pts[j + 1].k == kind and not endBlocked(pts[j + 1])
                        and not nearSharpHook(pts, i - 1, n) and not nearSharpHook(pts, j + 1, n) then
                        local chain = { pts[i - 1] }
                        for m = i, j + 1 do chain[#chain + 1] = pts[m] end
                        chain = chaikinPass(chain, 2.5, false)
                        chain = chaikinPass(chain, 1.25, true)
                        chain = thinSmoothedChain(chain, tol, maxStep)
                        for m = 2, #chain - 1 do
                            local c = chain[m]
                            nextPts[#nextPts + 1] = {
                                x = c.x, y = c.y, z = c.z, f = 0, k = kind, shape = true, room = room,
                            }
                        end
                        changed = true
                        i = j + 1
                    else
                        nextPts[#nextPts + 1] = p
                        i = i + 1
                    end
                else
                    nextPts[#nextPts + 1] = p
                    i = i + 1
                end
            end
            pts = nextPts
            n = #pts
        else


            local i = 2
            while i <= n - 2 do
                local p = pts[i]
                if p.shape and SMOOTH_SHAPE_KINDS[p.k] and not shapeBlocked(p) and not endBlocked(pts[i - 1]) then
                    local kind, room = p.k, p.room
                    local j = i
                    while j + 1 <= n - 1 and pts[j + 1].shape and pts[j + 1].k == kind
                        and pts[j + 1].room == room and not shapeBlocked(pts[j + 1]) do
                        j = j + 1
                    end
                    if j >= i + 1 and pts[j + 1].k == kind and not endBlocked(pts[j + 1])
                        and not nearSharpHook(pts, i - 1, n) and not nearSharpHook(pts, j + 1, n) then
                        local origX, origY = {}, {}
                        for m = i - 1, j + 1 do origX[m], origY[m] = pts[m].x, pts[m].y end
                        local function turnCross(idx)
                            if idx < i or idx > j then return 0 end
                            local a, b, c = pts[idx - 1], pts[idx], pts[idx + 1]
                            return (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
                        end
                        for _ = 1, 2 do
                            local nx, ny = {}, {}
                            for m = i, j do
                                local prev, cur, nxt = pts[m - 1], pts[m], pts[m + 1]
                                local dx1, dy1 = cur.x - prev.x, cur.y - prev.y
                                local dx2, dy2 = nxt.x - cur.x, nxt.y - cur.y
                                local l1, l2 = sqrt(dx1 * dx1 + dy1 * dy1), sqrt(dx2 * dx2 + dy2 * dy2)
                                local cosA = (l1 > 0.1 and l2 > 0.1) and ((dx1 * dx2 + dy1 * dy2) / (l1 * l2)) or -1
                                local cCur = turnCross(m)
                                local oscillates = (cCur * turnCross(m - 1) < -1e-4) or (cCur * turnCross(m + 1) < -1e-4)
                                if oscillates and l1 <= 12 and l2 <= 12 and cosA > 0.70 then
                                    local tx = 0.25 * prev.x + 0.5 * cur.x + 0.25 * nxt.x
                                    local ty = 0.25 * prev.y + 0.5 * cur.y + 0.25 * nxt.y
                                    local ox, oy = tx - origX[m], ty - origY[m]
                                    local od = sqrt(ox * ox + oy * oy)
                                    if od > 0.85 then
                                        tx = origX[m] + ox * (0.85 / od)
                                        ty = origY[m] + oy * (0.85 / od)
                                    end
                                    local nl1 = sqrt((tx - prev.x) ^ 2 + (ty - prev.y) ^ 2)
                                    local nl2 = sqrt((nxt.x - tx) ^ 2 + (nxt.y - ty) ^ 2)
                                    if (l1 >= 3.05) == (nl1 >= 3.05) and (l2 >= 3.05) == (nl2 >= 3.05) then
                                        nx[m], ny[m] = tx, ty
                                    end
                                end
                            end
                            for m = i, j do
                                if nx[m] then
                                    pts[m].x, pts[m].y = nx[m], ny[m]
                                    changed = true
                                end
                            end
                        end
                        i = j + 1
                    else
                        i = i + 1
                    end
                else
                    i = i + 1
                end
            end
        end
    end

    if hasSurfaceRun and n >= 3 then
        local isPinnedNode = opts.isPinnedNode
        local canShortcut = opts.canShortcut
        local canFillet = opts.canFillet
        local maxLook = highRes and 6 or 4
        local maxChord = highRes and 110 or 85

        local function movableSurface(idx)
            if idx < 2 or idx > n - 1 then return false end
            local prev, p, nxt = pts[idx - 1], pts[idx], pts[idx + 1]
            if p.k ~= 22 or nxt.k ~= 22 then return false end
            if shapeBlocked(p) or endBlocked(prev) or endBlocked(nxt) then return false end
            if hasFlag(p.f, F.INDOOR) or hasFlag(p.f, F.WATER) or hasFlag(p.f, F.POI) then return false end
            if p.room ~= prev.room or p.room ~= nxt.room then return false end
            if isPinnedNode and p.node and isPinnedNode(p.node, p) then return false end
            return true
        end

        local nextPts = {}
        local i = 1
        while i <= n do
            if movableSurface(i) then
                local j = i
                while movableSurface(j + 1) do j = j + 1 end
                local chain = { pts[i - 1] }
                for m = i, j + 1 do chain[#chain + 1] = pts[m] end

                local pulled
                if canShortcut then
                    pulled = { chain[1] }
                    local cur = 1
                    local cm = #chain
                    while cur < cm do
                        local jump = cur + 1
                        local limit = cur + maxLook
                        if limit > cm then limit = cm end
                        local a = chain[cur]
                        if type(a.z) == "number" then
                            for cand = limit, cur + 2, -1 do
                                local b = chain[cand]
                                if type(b.z) == "number" then
                                    local dx, dy = b.x - a.x, b.y - a.y
                                    local chord = sqrt(dx * dx + dy * dy)
                                    if chord >= 4 and chord <= maxChord and abs(b.z - a.z) <= chord * 0.22 then
                                        local arc = 0
                                        local okSpan = true
                                        for m = cur + 1, cand do
                                            local pm, qm = chain[m - 1], chain[m]
                                            local sdx, sdy = qm.x - pm.x, qm.y - pm.y
                                            arc = arc + sqrt(sdx * sdx + sdy * sdy)
                                            if m < cand then
                                                if type(qm.z) ~= "number" or perpendicular(qm, a, b) > 12 then
                                                    okSpan = false
                                                    break
                                                end
                                                local u = ((qm.x - a.x) * dx + (qm.y - a.y) * dy) / (chord * chord)
                                                if u < 0 then u = 0 elseif u > 1 then u = 1 end
                                                if abs(qm.z - (a.z + (b.z - a.z) * u)) > 2.0 then
                                                    okSpan = false
                                                    break
                                                end
                                            end
                                        end
                                        if okSpan and arc - chord >= 0.6 and canShortcut(a, b, chord) then
                                            jump = cand
                                            changed = true
                                            break
                                        end
                                    end
                                end
                            end
                        end
                        pulled[#pulled + 1] = chain[jump]
                        cur = jump
                    end
                else
                    pulled = chain
                end

                local pm = #pulled
                for r = 2, pm - 1 do
                    local prev, corner, nxt = pulled[r - 1], pulled[r], pulled[r + 1]
                    local filleted = false
                    if highRes then
                        local dx1, dy1 = corner.x - prev.x, corner.y - prev.y
                        local dx2, dy2 = nxt.x - corner.x, nxt.y - corner.y
                        local l1, l2 = sqrt(dx1 * dx1 + dy1 * dy1), sqrt(dx2 * dx2 + dy2 * dy2)


                        if l1 >= 10 and l2 >= 10 then
                            local cosA = (dx1 * dx2 + dy1 * dy2) / (l1 * l2)
                            if cosA < 0.985 and cosA > 0.50 then
                                local cut = 4.5
                                if 0.25 * l1 < cut then cut = 0.25 * l1 end
                                if 0.25 * l2 < cut then cut = 0.25 * l2 end
                                local pIn = lerpShapePoint(corner, prev, cut / l1)
                                local pOut = lerpShapePoint(corner, nxt, cut / l2)
                                if not canFillet or canFillet(pIn, pOut) then
                                    local hasZ = type(pIn.z) == "number" and type(corner.z) == "number" and type(pOut.z) == "number"
                                    for s = 0, 2 do
                                        local t = s * 0.5
                                        local u = 1 - t
                                        local bz
                                        if hasZ then bz = u * u * pIn.z + 2 * u * t * corner.z + t * t * pOut.z end
                                        nextPts[#nextPts + 1] = {
                                            x = u * u * pIn.x + 2 * u * t * corner.x + t * t * pOut.x,
                                            y = u * u * pIn.y + 2 * u * t * corner.y + t * t * pOut.y,
                                            z = bz, f = 0, k = 22, shape = true, room = corner.room,
                                        }
                                    end
                                    filleted = true
                                    changed = true
                                end
                            end
                        end
                    end
                    if not filleted then nextPts[#nextPts + 1] = corner end
                end
                i = j + 1
            else
                nextPts[#nextPts + 1] = pts[i]
                i = i + 1
            end
        end
        pts = nextPts
    end

    if changed then
        leg.points = pts
        leg._cum = nil
    end
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
