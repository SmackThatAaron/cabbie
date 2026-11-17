
























































































local ADDON_NAME, FGPS = ...

local Router = {






    MAX_EXPANSIONS = 550000,






    YIELD_EVERY = 16,
    CACHE_SIZE = 16,
    DEFAULT_MAX_STRAIGHT_YARDS = 3000,
    HUB_REACH_YARDS = 1200,



















    STRAIGHT_FREE_YARDS = 30,
    STRAIGHT_DETOUR_PER_YARD = 2.5,
    STRAIGHT_DETOUR_MAX_YARDS = 400,















    STRAIGHT_DETOUR_LONG_SHARE = 1.0,






    WALL_GAP_YARDS = 20,
    WALL_CHECK_MIN_YARDS = 40,







    DOCK_WALL_EXEMPT_YARDS = 130,







    MOUNTAIN_GAP_YARDS = 50,

    MOUNTAIN_CHORD_MAX = 90,




    THUNDER_BLUFF_MESA_CHASM_CHORD_YARDS = 218,
    MOUNTAIN_MIN_YARDS = 450,
    PROFILE_MIN_YARDS = 60,
    CLIFF_Z_YARDS = 25,






    SPARSE_CHORD_FACTOR = 3.0,


    WALL_LINKED_QUAY_FACTOR = 15.0,












    TURN_SOFT_COS = 0.50,
    TURN_CHARGE_SECONDS = 4.0,
    SHORT_HOP_YARDS = 40,
    SHORT_HOP_SECONDS = 0.45,

























    CLIMB_STEP_YARDS = 5,
    CLIMB_WALKABLE_SLOPE = 0.3,
    CLIMB_DETOUR_BASE_YARDS = 400,
    CLIMB_DETOUR_PER_YARD = 15,
    CLIMB_DETOUR_MAX_YARDS = 600,




    SURFACE_SLOPE_FREE = 0.30,
    SURFACE_SLOPE_WEIGHT = 12.0,
    SURFACE_SLOPE_SHARP_FREE = 0.59,
    SURFACE_SLOPE_SHARP_WEIGHT = 20.0,
    HEIGHT_GUESS_YARDS = 30,
    HEIGHT_GUESS_SPREAD = 12,



    STACKED_LEVEL_YARDS = 4,
    VARIANTS = { "fastest", "fewer_transfers", "prefer_roads", "no_flight", "no_boat" },
    active = {},
    queue = {},
    running = nil,
    SHRINK_KEYS = 4000,
    RELEASE_IDLE_SECONDS = 60,
    nextRouteID = 0,
    nextHandleID = 0,
}
FGPS.Router = Router

local L, Util, Const = FGPS.L, FGPS.Util, FGPS.Const
local floor, sqrt, huge, abs = math.floor, math.sqrt, math.huge, math.abs
local type, pairs, ipairs, tostring, pcall, tonumber = type, pairs, ipairs, tostring, pcall, tonumber

local ORIGIN, DEST, TELE_BASE = -1, -2, -10

local BOARD_BASE = -2 ^ 40
local KIND_ATTACH = 14
local KIND_CONNECTOR = 3

local KIND_ROAD = 4
local KIND_MESH = 15


local KIND_SURFACE, KIND_SURFACE_SWIM = 22, 23

local BOARDING_KINDS = { [7] = true, [8] = true, [9] = true, [10] = true, [11] = true }
local CAPITAL_MAPS = { 1453, 1454, 1455, 1456, 1457, 1458 }
local capitalRects

local function capitalRectsOf()
    if capitalRects then return capitalRects end
    capitalRects = {}
    local maps = FGPS.Data and FGPS.Data.maps
    if maps then
        for i = 1, #CAPITAL_MAPS do
            local m = maps[CAPITAL_MAPS[i]]
            if m then capitalRects[#capitalRects + 1] = m end
        end
    end
    return capitalRects
end

local CAPITAL_PAD = 200

local function inCapital(inst, x, y, pad)
    if not inst or not x or not y then return false end
    pad = pad or 0
    local rects = capitalRectsOf()
    for i = 1, #rects do
        local m = rects[i]
        if m.inst == inst and x >= m.minX - pad and x <= m.maxX + pad and y >= m.minY - pad and y <= m.maxY + pad then
            return true
        end
    end
    return false
end






local function cutsCapitalWall(inst, x1, y1, x2, y2, cityTrip, dock)


    local pad = cityTrip and CAPITAL_PAD or 0
    if not inCapital(inst, x1, y1, pad) or not inCapital(inst, x2, y2, pad) then return false end
    local dx, dy = x2 - x1, y2 - y1
    local d = sqrt(dx * dx + dy * dy)
    local gap = Router.WALL_GAP_YARDS
    if d < Router.WALL_CHECK_MIN_YARDS or d * 0.5 <= gap then return false end
    if dock and d <= Router.DOCK_WALL_EXEMPT_YARDS then return false end
    local G = FGPS.Graph
    local g = G:Ensure(inst)
    if not g or (g.n or 0) < 1000 then return false end
    return G:NearestKey(inst, x1 + dx * 0.5, y1 + dy * 0.5, gap) == nil
end











function Router._chasm(G, inst, x1, y1, dx, dy, z1, z2, linked)
    local cliffZ = Router.CLIFF_Z_YARDS
    local below, other, above, atOrBelow = 0, 0, 0, 0
    for i = 1, 3 do
        local t = i / 4
        local base = z1 + (z2 - z1) * t
        local near = G:Nearest(inst, x1 + dx * t, y1 + dy * t, Router.WALL_GAP_YARDS + 5, 32)
        for n = 1, #near do
            local zh = near[n].key and G:NodeHeightGuess(near[n].key)
            if zh then
                if zh < base - cliffZ then below = below + 1 else other = other + 1 end
                if zh > base + cliffZ then above = above + 1 else atOrBelow = atOrBelow + 1 end
            end
        end
    end
    return (below > 0 and other == 0) or (not linked and above > 0 and atOrBelow == 0)
end














local function cutsMountain(inst, x1, y1, x2, y2, z1, z2, dock, linked)
    if not inst or not x1 or not x2 then return false, false end
    local dx, dy = x2 - x1, y2 - y1
    local d = sqrt(dx * dx + dy * dy)
    local pier = dock == true
    if pier and d <= Router.DOCK_WALL_EXEMPT_YARDS then return false, false end
    local rise = (z1 and z2) and abs(z2 - z1) or 0
    local cliff = rise > Router.CLIFF_Z_YARDS and rise > Router.CLIMB_STEP_YARDS
        and rise > Router.CLIMB_WALKABLE_SLOPE * d
    local gap = Router.MOUNTAIN_GAP_YARDS
    local sparse = d >= Router.MOUNTAIN_MIN_YARDS and d * 0.5 > gap
    local minProfile = pier and Router.DOCK_WALL_EXEMPT_YARDS or (linked and 2 * gap or Router.PROFILE_MIN_YARDS)
    local profile = z1 and z2 and not cliff and not sparse and d > minProfile
    if not cliff and not sparse and not profile then return false, false end
    local G = FGPS.Graph
    local g = G:Ensure(inst)
    if not g or (g.n or 0) < 1000 then return false, false end
    if cliff then return true, false end
    if profile then return Router._chasm(G, inst, x1, y1, dx, dy, z1, z2, linked), false end


    if pier and not (z1 and z2) then return false, false end


    if d > Router.MOUNTAIN_CHORD_MAX and not pier then
        if G:NearestKey(inst, x1 + dx * 0.5, y1 + dy * 0.5, gap) == nil then
            local share = FGPS.Cost and FGPS.Cost.WaterShare(inst, x1, y1, x2, y2) or 0
            if share >= 0.5 then return false, false end
            return true, false
        end
    end

    local samples = floor(d / Router.MOUNTAIN_MIN_YARDS)
    if samples < 1 then samples = 1 end
    if samples > 8 then samples = 8 end
    local empty, ridge = false, false
    for i = 1, samples do
        local t = i / (samples + 1)
        local hitKey = G:NearestKey(inst, x1 + dx * t, y1 + dy * t, gap)
        if not hitKey then
            empty = true
        elseif z1 and z2 then


            local zh = G:NodeHeightGuess(hitKey)
            if zh then
                local base = z1 + (z2 - z1) * t
                if zh > base + Router.CLIFF_Z_YARDS and zh > base + Router.CLIMB_STEP_YARDS then ridge = true end
            end
        end
    end
    if ridge then return true, false end
    if pier or not empty then return false, false end
    local share = FGPS.Cost and FGPS.Cost.WaterShare(inst, x1, y1, x2, y2) or 0

    if share >= 0.5 then return false, false end
    if d > Router.MOUNTAIN_CHORD_MAX then return true, false end
    return false, true
end




local function crossesStreet(inst, x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    local dist = sqrt(dx * dx + dy * dy)
    if dist <= Router.DOCK_WALL_EXEMPT_YARDS then return false end
    local g = FGPS.Graph
    if not g then return false end
    local share = FGPS.Cost and FGPS.Cost.WaterShare(inst, x1, y1, x2, y2) or 0
    if share >= 0.5 then return false end
    for i = 1, 3 do
        local t = i / 4
        local near = g:Nearest(inst, x1 + dx * t, y1 + dy * t, Router.WALL_GAP_YARDS, 4)
        if near then
            for n = 1, #near do
                local street = false
                g:Neighbors(near[n].key, function(_, kind)


                    if kind == 2 or kind == 16 then street = true end
                end)
                if street then return true end
            end
        end
    end
    return false
end







local function judgeStraight(inst, x1, y1, x2, y2, cityTrip, z1, z2, dock, linked, stored)
    local climb = (type(z1) == "number" and type(z2) == "number") and abs(z2 - z1) or 0


    if dock and crossesStreet(inst, x1, y1, x2, y2) then return true, false, climb end




    if not (dock and sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2) <= Router.DOCK_WALL_EXEMPT_YARDS)
        and FGPS.Cost and FGPS.Cost.OverSwim
        and (FGPS.Cost.OverSwim(inst, x1, y1, x2, y2) or FGPS.Cost.OverBlocked(inst, x1, y1, x2, y2)) then
        local world = FGPS.Graph and FGPS.Graph:Ensure(inst)
        if world and (world.n or 0) >= 1000 then return true, false, climb end
    end




    local wall = cutsCapitalWall(inst, x1, y1, x2, y2, cityTrip, dock)
    if wall and not linked then return true, false, climb end




    local hard, sparse = cutsMountain(inst, x1, y1, x2, y2, z1, z2, dock, stored)
    if not hard and not linked and Router._sheerAttach and Router._sheerAttach(inst, x1, y1, x2, y2, z1, z2, dock) then
        return true, false, climb
    end
    if wall and linked then return hard, "quayrock", climb end
    return hard, sparse, climb
end

local function cutsObstacle(inst, x1, y1, x2, y2, cityTrip, z1, z2, dock, linked, stored)
    local hard, sparse = judgeStraight(inst, x1, y1, x2, y2, cityTrip, z1, z2, dock, linked, stored)
    return hard, sparse
end



function Router.judgeStraight(inst, x1, y1, x2, y2, cityTrip, z1, z2, dock)
    local hard, sparse, climb = judgeStraight(inst, x1, y1, x2, y2, cityTrip, z1, z2, dock)
    return { hard = hard and true or false, sparse = sparse and true or false, climb = climb or 0, blockedByPicture = false }
end



local function sparseFactor(sparse)
    if sparse == "quayrock" then return Router.WALL_LINKED_QUAY_FACTOR end
    if sparse then return Router.SPARSE_CHORD_FACTOR end
    return 1
end
















local WATER_CHECK_YARDS = 100



local function isTransportStop(flags)
    return flags ~= nil and flags % 8 >= 4
end

local VIA_ATTACH, VIA_DIRECT, VIA_HUB_ATTACH = "attach", "direct", "hubattach"




function Router.MaxStraightYards()
    local db = FGPS.DB
    local routing = db and db.settings and db.settings.routing
    local value = routing and tonumber(routing.maxStraightYards) or nil
    if value == nil or value < 0 then return Router.DEFAULT_MAX_STRAIGHT_YARDS end
    return value
end

local function Graph() return FGPS.Graph end
local function Cost() return FGPS.Cost end
local function Access() return FGPS.Access end
local function Coords() return FGPS.Coords end
local function Route() return FGPS.Route end
local function Scheduler() return FGPS.Scheduler end







local function dockAt(key)
    if type(key) ~= "number" or key < 0 then return nil end
    local G = Graph()
    if not isTransportStop(G:NodeFlags(key)) then return nil end
    local tid = G:NodeTransport(key)
    local records = FGPS.Data and FGPS.Data.transports
    local rec = tid and records and records[tid]
    if type(rec) == "table" and rec.kind == "elevator" then return "lift" end
    return true
end





function Router._swimRefused(inst, x1, y1, x2, y2, dock)
    if x1 == nil or x2 == nil then return false end
    if dock then
        local dx, dy = x2 - x1, y2 - y1
        local exempt = Router.DOCK_WALL_EXEMPT_YARDS
        if dx * dx + dy * dy <= exempt * exempt then return false end
    end
    local C = FGPS.Cost
    if not (C and C.OverSwim and (C.OverSwim(inst, x1, y1, x2, y2) or C.OverBlocked(inst, x1, y1, x2, y2))) then
        return false
    end
    local world = Graph():Ensure(inst)
    return world and (world.n or 0) >= 1000
end


local function dockBetween(a, b)
    local da, db = dockAt(a), dockAt(b)
    if da == "lift" or db == "lift" then return "lift" end
    return da or db
end


local function vettedInst(ctx, inst)
    local v = ctx.vetted[inst]
    if v == nil then
        v = Graph():IsVetted(inst)
        ctx.vetted[inst] = v
    end
    return v
end

local function clearTable(t)
    if wipe then wipe(t) else for k in pairs(t) do t[k] = nil end end
end






local heapKeys, heapF, heapSize = {}, {}, 0

local function heapPush(key, f)
    heapSize = heapSize + 1
    local i = heapSize
    while i > 1 do
        local parent = floor((i + 2) / 4)
        local pf = heapF[parent]
        if pf <= f then break end
        heapKeys[i], heapF[i] = heapKeys[parent], pf
        i = parent
    end
    heapKeys[i], heapF[i] = key, f
end

local function heapPop()
    if heapSize == 0 then return nil end
    local key, f = heapKeys[1], heapF[1]
    local n = heapSize
    local lastKey, lastF = heapKeys[n], heapF[n]
    heapKeys[n], heapF[n] = nil, nil
    n = n - 1
    heapSize = n
    if n > 0 then
        local i = 1
        while true do
            local c = 4 * i - 2
            if c > n then break end
            local best, bf = c, heapF[c]
            local cf
            if c + 1 <= n then cf = heapF[c + 1]; if cf < bf then best, bf = c + 1, cf end end
            if c + 2 <= n then cf = heapF[c + 2]; if cf < bf then best, bf = c + 2, cf end end
            if c + 3 <= n then cf = heapF[c + 3]; if cf < bf then best, bf = c + 3, cf end end
            if bf >= lastF then break end
            heapKeys[i], heapF[i] = heapKeys[best], bf
            i = best
        end
        heapKeys[i], heapF[i] = lastKey, lastF
    end
    return key, f
end

local function heapClear()
    for i = 1, heapSize do heapKeys[i], heapF[i] = nil, nil end
    heapSize = 0
end


local function heapRelease()
    heapKeys, heapF, heapSize = {}, {}, 0
end


Router._heap = { push = heapPush, pop = heapPop, clear = heapClear, size = function() return heapSize end }









local slotOf, gArr, fromArr, yardsArr, secArr, penArr, packArr, tidArr, boardArr, honestArr, closed =
    {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}

local underCount = 0



Router._hMemo, Router._hMemoHonest = {}, {}
Router._modeName = { "ground", "taxi", "portal", "boat", "zeppelin", "tram", "elevator", "hearth", "spell" }
Router._modeIdOf = {
    ground = 1, taxi = 2, portal = 3, boat = 4, zeppelin = 5, tram = 6, elevator = 7, hearth = 8, spell = 9,
}
Router._viaName = { "attach", "direct", "hubattach" }
Router._viaIdOf = { attach = 1, direct = 2, hubattach = 3 }




local searchOwner = nil
local touchedKeys = 0













function Router._dropSearchTables()
    slotOf, gArr, fromArr, yardsArr, secArr, penArr, packArr, tidArr, boardArr, honestArr, closed =
        {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
    Router._hMemo, Router._hMemoHonest = {}, {}
    Router._modeExtra, Router._viaExtra = nil, nil
    Router._lines = { n = 0, nu = 0, from = {}, g = {}, f = {}, x = {}, y = {}, z = {}, zt = {}, d = {}, goal = {}, hs = {}, u = {}, ug = {} }
    heapRelease()
    Router._bigTables = nil
end

local function resetSearch()
    if touchedKeys > Router.SHRINK_KEYS then Router._bigTables = true end
    clearTable(slotOf)
    clearTable(closed)
    clearTable(tidArr)
    clearTable(boardArr)
    clearTable(Router._hMemo)
    clearTable(Router._hMemoHonest)
    if Router._modeExtra then clearTable(Router._modeExtra) end
    if Router._viaExtra then clearTable(Router._viaExtra) end
    Router._lines.n, Router._lines.nu = 0, 0
    clearTable(Router._lines.ug)
    heapClear()
    touchedKeys, underCount = 0, 0
end




function Router._armRelease()
    local wait = Router.RELEASE_IDLE_SECONDS
    local t = GetTime and GetTime() or nil
    if not (t and C_Timer and C_Timer.After and type(wait) == "number" and wait > 0) then
        Router._dropSearchTables()
        return
    end
    Router._idleSince = t
    if Router._releaseArmed then return end
    Router._releaseArmed = true
    local function check()
        Router._releaseArmed = nil
        if not Router._bigTables or searchOwner ~= nil then return end
        local left = Router._idleSince + wait - GetTime()
        if left > 0.001 then
            Router._releaseArmed = true
            C_Timer.After(left, check)
            return
        end
        Router._dropSearchTables()
    end
    C_Timer.After(wait, check)
end



local function releaseSearch(ctx)
    if searchOwner ~= ctx then return end
    resetSearch()
    searchOwner = nil
    if Router._bigTables then Router._armRelease() end
end






function Router._releaseTaskSearch(task)
    if task ~= nil and searchOwner ~= nil and searchOwner.task == task then releaseSearch(searchOwner) end
end


function Router._gAt(key)
    local s = slotOf[key]
    if not s then return nil end
    return gArr[s]
end


function Router._slotMode(key)
    local s = slotOf[key]
    if not s then return nil, nil, "ground", nil end
    local packed = packArr[s] or 0
    local modeId = floor(packed / 256) % 16
    local mode = Router._modeName[modeId]
    if modeId == 0 and Router._modeExtra then mode = Router._modeExtra[s] end
    local parent = fromArr[s]
    if parent == false then parent = nil end
    return s, gArr[s], mode or "ground", parent
end


function Router._edgeOf(key)
    local s = slotOf[key]
    if not s then return nil end
    local packed = packArr[s] or 0
    local modeId = floor(packed / 256) % 16
    local viaId = floor(packed / 4096) % 8
    local mode = Router._modeName[modeId]
    if modeId == 0 and Router._modeExtra then mode = Router._modeExtra[s] end
    local via = viaId > 0 and Router._viaName[viaId] or nil
    if not via and Router._viaExtra then via = Router._viaExtra[s] end
    local parent = fromArr[s]
    if parent == false then parent = nil end
    local tid = tidArr[s]
    return parent, packed % 256, yardsArr[s] or 0, secArr[s] or 0, penArr[s] or 0, mode, tid, via
end

local cur = {}

local function posOf(ctx, key)
    if key <= BOARD_BASE then return Graph():NodePos(BOARD_BASE - key) end
    if key < 0 then
        local v = ctx.vpos[key]
        if not v then return nil end
        return v.inst, v.x, v.y
    end
    return Graph():NodePos(key)
end







function Router._prepareFlightH(ctx, speed)
    ctx.flightHubs = nil
    local Cost = FGPS.Cost
    local bias = Cost.RoadFactor(ctx.variant, 4)
    if not bias or bias > 1 then bias = 1 end
    bias = bias * 0.55
    if bias <= 0 or not speed then return end
    local ground = Cost.GroundSpeed(ctx.access)
    if not ground or ground <= 0 then return end
    ground = ground / bias
    if speed <= ground * 1.001 then return end


    ctx.flightGround = ground
    local dest = ctx.dest
    if not dest or not dest.x then return end
    local taxi = FGPS.Data and FGPS.Data.taxi
    local nodes, paths = taxi and taxi.nodes, taxi and taxi.paths
    if not nodes or not paths then return end
    local Access = FGPS.Access
    local access = ctx.access
    local D = FGPS.Coords.Distance
    local f, pos = {}, {}
    local function consider(id)
        if f[id] or not Access:CanUseTaxiNode(access, id) then return end
        local node = nodes[id]
        if not node or node.inst ~= dest.inst or not node.x then return end




        local rest = D(node.x, node.y, dest.x, dest.y) / ground
        local fast = ctx.fastLinks
        if fast then
            for i = 1, #fast do
                local link = fast[i]
                local alt = D(node.x, node.y, link.fx, link.fy) / ground + link.rest
                if alt < rest then rest = alt end
            end
        end
        f[id] = rest
        pos[id] = node
    end
    local hops = {}
    for i = 1, #paths do
        local p = paths[i]
        local a, b = nodes[p.from], nodes[p.to]
        if a and b and a.inst == dest.inst and b.inst == dest.inst and p.seconds then
            consider(p.from)
            consider(p.to)
            if f[p.from] and f[p.to] then hops[#hops + 1] = p end
        end
    end
    local keys = {}
    for id in pairs(f) do keys[#keys + 1] = id end
    if #keys == 0 then return end
    for _ = 1, #keys do
        local changed = false
        for i = 1, #hops do
            local p = hops[i]
            local alt = p.seconds + f[p.to]
            if alt < f[p.from] then
                f[p.from] = alt
                changed = true
            end
        end
        if not changed then break end
    end
    local hubs = {}
    for i = 1, #keys do
        local a = keys[i]
        local pa = pos[a]
        local dominated = false
        for j = 1, #keys do
            if j ~= i then
                local pb = pos[keys[j]]
                if f[keys[j]] + D(pa.x, pa.y, pb.x, pb.y) / ground <= f[a] + 1e-6 then
                    dominated = true
                    break
                end
            end
        end
        if not dominated then hubs[#hubs + 1] = { x = pa.x, y = pa.y, f = f[a] } end
    end
    if #hubs == 0 then return end
    ctx.flightHubs = hubs
end

function Router._flightH(ctx, x, y, hubs)
    hubs = hubs or ctx.flightHubs
    if not hubs then return nil end
    local D = FGPS.Coords.Distance
    local ground = ctx.flightGround
    local best
    for i = 1, #hubs do
        local hub = hubs[i]
        local via = D(x, y, hub.x, hub.y) / ground + hub.f
        if not best or via < best then best = via end
    end
    return best
end




local function estimateFrom(fast, speed, x, y, dest)
    local dx, dy = dest.x - x, dest.y - y
    local h = sqrt(dx * dx + dy * dy) / speed
    if fast then
        for i = 1, #fast do
            local link = fast[i]
            dx, dy = link.fx - x, link.fy - y
            local alt = sqrt(dx * dx + dy * dy) / speed + link.rest
            if alt < h then h = alt end
        end
    end
    return h
end





local function heuristic(ctx, key)


    if ctx.goals then return Router._goalH(ctx, key) end


    if key == DEST or key == ORIGIN or Router._noEstimate then return 0, 0 end



    local s = slotOf[key]
    local memo = Router._hMemo
    local known = s and memo[s]
    if known ~= nil then return known, Router._hMemoHonest[s] or 0 end
    local inst, x, y = posOf(ctx, key)
    if not x then return 0, 0 end



    local h, hs
    if inst ~= ctx.dest.inst then
        h = Router._outsideEstimate(ctx, inst, x, y)
        hs = h
        local alt = ctx.outsideAlt
        if alt and alt > hs then hs = alt end
    else
        h = estimateFrom(ctx.fastLinks, ctx.maxSpeed, x, y, ctx.dest)
        if ctx.flightGround then


            local tighter = estimateFrom(ctx.fastLinks, ctx.flightGround, x, y, ctx.dest)
            local via = Router._flightH(ctx, x, y)
            if via and via < tighter then tighter = via end
            if tighter > h then h = tighter end
        end
        hs = h
    end


    local lm = ctx.lm
    if lm and (key >= 0 or key <= BOARD_BASE) then
        local a = Router._landmarkAt(lm, inst, key)
        if a > hs then hs = a end

        local second = ctx.lm2
        if second then
            a = Router._landmarkAt(second, inst, key)
            if a > hs then hs = a end
        end
    end
    if s then
        memo[s] = hs
        if ctx.maxSeconds then Router._hMemoHonest[s] = h end
    end
    return hs, h
end

local function relax(ctx, key, g, from, kind, yards, seconds, penalty, mode, transportID, via)




    if ctx ~= searchOwner or ctx.task ~= FGPS.Scheduler.current then return end
    local s = slotOf[key]
    if s and gArr[s] ~= nil and gArr[s] <= g then return end


    local oldUnder = 0
    if s then oldUnder = floor((packArr[s] or 0) / 32768) % 2 end
    if not s then
        touchedKeys = touchedKeys + 1
        s = touchedKeys
        slotOf[key] = s
    end
    gArr[s] = g
    fromArr[s] = from or false
    yardsArr[s] = yards or 0
    secArr[s] = seconds or 0
    penArr[s] = penalty or 0
    local modeId = (mode and Router._modeIdOf[mode]) or 0
    local viaId = (via and Router._viaIdOf[via]) or 0
    if mode and modeId == 0 then
        local extra = Router._modeExtra
        if not extra then extra = {}; Router._modeExtra = extra end
        extra[s] = mode
    elseif Router._modeExtra then
        Router._modeExtra[s] = nil
    end
    if via and viaId == 0 then
        local extra = Router._viaExtra
        if not extra then extra = {}; Router._viaExtra = extra end
        extra[s] = via
    elseif Router._viaExtra then
        Router._viaExtra[s] = nil
    end
    if transportID then tidArr[s] = transportID elseif tidArr[s] then tidArr[s] = nil end
    local fs = from and slotOf[from]
    local inherited = fs and boardArr[fs] or nil
    local board = (key <= BOARD_BASE) and key or inherited
    if board then boardArr[s] = board elseif boardArr[s] then boardArr[s] = nil end
    local bound = ctx.maxSeconds
    local honest
    if bound then
        honest = ((fs and honestArr[fs]) or 0) + (seconds or 0) + (penalty or 0)
        honestArr[s] = honest
    end
    local h, hHonest = heuristic(ctx, key)
    heapPush(key, g + h)
    packArr[s] = (kind or 0) + modeId * 256 + viaId * 4096 + oldUnder * 32768
    if bound then

        local under = (honest + hHonest <= bound) and 1 or 0
        if under ~= oldUnder then
            packArr[s] = packArr[s] + (under - oldUnder) * 32768
            underCount = underCount + (under == 1 and 1 or -1)
        end
    end
end








local function straightRisk(d)
    local over = (d or 0) - Router.STRAIGHT_FREE_YARDS
    if over <= 0 then return 1 end
    local detour = over * Router.STRAIGHT_DETOUR_PER_YARD
    local most = Router.STRAIGHT_DETOUR_MAX_YARDS
    local long = (d or 0) * Router.STRAIGHT_DETOUR_LONG_SHARE
    if long > most then most = long end
    if detour > most then detour = most end
    return 1 + detour / d
end












local function climbDetour(d, zFrom, zTo, stacked)
    if not zFrom or not zTo then return 0 end
    local rise = abs(zTo - zFrom)
    if rise <= Router.CLIMB_STEP_YARDS then return 0 end
    local unexplained = stacked and rise or rise - Router.CLIMB_WALKABLE_SLOPE * (d or 0)
    if unexplained <= 0 then return 0 end
    local detour = Router.CLIMB_DETOUR_BASE_YARDS + unexplained * Router.CLIMB_DETOUR_PER_YARD
    local most = Router.CLIMB_DETOUR_MAX_YARDS
    if detour > most then detour = most end
    return detour
end




local function climbCharge(ctx, d, zFrom, zTo, stacked)
    local detour = climbDetour(d, zFrom, zTo, stacked)
    if detour <= 0 then return 0 end
    return detour * ctx.straightRate
end





local function heightOf(ctx, key)
    if key == ORIGIN then return ctx.originZ, ctx.originGuessed end
    if key == DEST then return ctx.destZ, ctx.destGuessed end
    if key <= BOARD_BASE then return Graph():NodeHeight(BOARD_BASE - key) end
    if key < 0 then
        local v = ctx.vpos[key]
        if not v then return nil end
        return v.z, v.zGuessed
    end
    return Graph():NodeHeight(key)
end





local function testHeightOf(ctx, key, z)
    if z ~= nil then return z end
    if key == ORIGIN then return ctx.originZg end
    if key == DEST then return ctx.destZg end
    if key <= BOARD_BASE then return Graph():NodeHeightGuess(BOARD_BASE - key) end
    if key < 0 then
        local v = ctx.vpos[key]
        return v and v.zg or nil
    end
    return Graph():NodeHeightGuess(key)
end







local function destHeightFrom(ctx, fromZ)
    if ctx.destZ or not ctx.destLow or not fromZ then return ctx.destZ, ctx.destGuessed end
    if fromZ < ctx.destLow then return ctx.destLow, true end
    if fromZ > ctx.destHigh then return ctx.destHigh, true end
    return fromZ, true
end





local function destTestHeightFrom(ctx, fromZ)
    if ctx.destZ then return ctx.destZ end
    local low, high = ctx.destLowG, ctx.destHighG
    if not low then return ctx.destZg end
    if not fromZ then return nil end
    if fromZ < low then return low end
    if fromZ > high then return high end
    return fromZ
end



Router.ON_FOOT = { onFoot = true }


local function indoorNode(key)
    if not key then return false end
    if key <= BOARD_BASE then key = BOARD_BASE - key end
    local inside = FGPS.Data and FGPS.Data.insideMaps
    if inside and key > 0 then
        local inst = Graph():Split(key)
        if inst and inside[inst] then return true end
    end
    local _, indoor = Graph():NodePlace(key)
    return indoor
end









function Router._enclosed(ctx, key)
    if key == ORIGIN then return ctx.originEnclosed or false end
    if key == DEST then return ctx.destEnclosed or false end
    if key <= BOARD_BASE then
        key = BOARD_BASE - key
    elseif key < 0 then
        return (ctx.teleEnclosed and ctx.teleEnclosed[key]) or false
    end
    local _, indoor, stacked = Graph():NodePlace(key)
    return indoor or stacked or Router._onHazardPiece(key)
end


local function surfaceExtra(kind, aKey, bKey, aIndoor)
    if kind == KIND_CONNECTOR then
        local inside = FGPS.Data and FGPS.Data.insideMaps
        if inside and ((aKey and aKey > 0 and inside[(Graph():Split(aKey))])
            or (bKey and bKey > 0 and inside[(Graph():Split(bKey))])) then
            return Router.ON_FOOT
        end
        return nil
    end
    if kind ~= KIND_SURFACE then return nil end
    if aIndoor == nil then aIndoor = indoorNode(aKey) end
    if aIndoor and indoorNode(bKey) then return Router.ON_FOOT end
    return nil
end



local function straightExtra(aKey, bKey, aIndoor)
    if aIndoor == nil then aIndoor = indoorNode(aKey) end
    if aIndoor or indoorNode(bKey) then return Router.ON_FOOT end
    return nil
end



function Router._surfaceSlopeFactor(za, zb, yards, variant)
    if not za or not zb or not yards or yards <= 0 then return 1 end
    local roadsOnly = variant == "roads_only"
    local free = roadsOnly and Router.SURFACE_SLOPE_FREE or Router.SURFACE_SLOPE_SHARP_FREE
    local over = abs(zb - za) / yards - free
    if over <= 0 then return 1 end
    local weight = roadsOnly and Router.SURFACE_SLOPE_WEIGHT or Router.SURFACE_SLOPE_SHARP_WEIGHT
    return 1 + weight * over * over
end






local function attachCost(ctx, cand, nodeKey, virtualZ, stacked, vx, vy)
    local C = Cost()
    local access, variant = ctx.access, ctx.variant
    local attachYards = cand.attachYards or cand.dist
    local base = C.EdgeSeconds(KIND_ATTACH, attachYards, access, nil, straightExtra(nodeKey))
    if not base then return nil end


    local factor = C.RoadFactor(variant, KIND_ATTACH) * C.ChordFactor(KIND_ATTACH, attachYards) * sparseFactor(cand.sparse)
    local honest = base
    local charged = base * factor
    local surcharge = charged * (straightRisk(attachYards) - 1) + climbCharge(ctx, attachYards, virtualZ, cand.footZ, stacked)
    local segYards = cand.segYards or 0
    if segYards > 0 then
        local extra2 = surfaceExtra(cand.segKind, nodeKey, cand.otherKey)
        local s2 = C.EdgeSeconds(cand.segKind, segYards, access, nil, extra2, cand.shaped)
        if not s2 then return nil end

        local f2 = C.RoadFactor(variant, cand.segKind) * C.ChordFactor(cand.segKind, segYards, cand.shaped, cand.segDoubt)
        if cand.segKind == KIND_SURFACE and extra2 ~= Router.ON_FOOT and cand.otherKey then
            local G = Graph()
            local whole = G:EdgeYards(nodeKey, cand.otherKey, KIND_SURFACE)
            if not whole then
                local _, ax, ay = G:NodePos(nodeKey)
                local _, bx, by = G:NodePos(cand.otherKey)
                if ax and bx then whole = sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay)) end
            end
            f2 = f2 * Router._surfaceSlopeFactor(G:NodeHeight(nodeKey), G:NodeHeight(cand.otherKey), whole, variant)
        end
        honest = honest + s2
        charged = charged + s2 * f2
        if cand.segKind == KIND_SURFACE_SWIM then


            local G, whole = Graph(), nil
            if cand.otherKey then
                whole = G:EdgeYards(nodeKey, cand.otherKey, KIND_SURFACE_SWIM)
                if not whole then
                    local _, ax, ay = G:NodePos(nodeKey)
                    local _, bx, by = G:NodePos(cand.otherKey)
                    if ax and bx then whole = sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay)) end
                end
            end
            local share = (whole and whole > 0) and math.min(1, segYards / whole) or 1
            surcharge = surcharge + Const.SWIM_CROSSING_CHARGE * share
        end
    end
    if ctx.guarded then


        local inst, x, y = Graph():NodePos(nodeKey)
        local footX, footY = cand.fx or x, cand.fy or y
        local share = C.GuardedShare(ctx.guarded, inst, footX, footY, x, y)
        local total = attachYards + segYards
        if vx and total > 0 then
            share = (C.GuardedShare(ctx.guarded, inst, vx, vy, footX, footY) * attachYards + share * segYards) / total
        end
        local gf = C.GuardedFactor(share)
        charged = charged * gf
        surcharge = surcharge * gf
    end
    return honest, attachYards + segYards, charged + surcharge
end

Router._attachCost = attachCost

















function Router._doorAllowed(ctx, fromInst, toInst)
    local maps = FGPS.Data and FGPS.Data.insideMaps
    if not maps or fromInst == toInst then return true end
    local ends = ctx.insideEnds or {}
    if maps[fromInst] and maps[toInst] and ends[toInst] then return true end
    if maps[fromInst] and not (ctx.insideStarts or {})[fromInst] then return false end
    if maps[toInst] and not ends[toInst] then return false end
    return true
end




function Router._teleportFeeders(set)
    local maps, links = FGPS.Data and FGPS.Data.insideMaps, FGPS.Data and FGPS.Data.links
    if not maps or type(links) ~= "table" then return set end
    local grown = true
    while grown do
        grown = false
        for _, l in ipairs(links) do
            local from, to = l[1], l[3]
            if l[5] == 7 and from ~= to and maps[from] and maps[to] and set[to] and not set[from] then
                set[from], grown = true, true
            end
        end
    end
    return set
end




Router._needs = { links = nil, byKey = nil }
function Router._linkNeed(fromKey, toKey)
    local links = FGPS.Data and FGPS.Data.links
    local cache = Router._needs
    if cache.links ~= links or not cache.byKey then
        local byKey, G = {}, Graph()
        for _, l in ipairs(type(links) == "table" and links or {}) do
            if type(l[8]) == "table" and l[1] and l[2] and l[3] and l[4] then
                byKey[G:Key(l[1], l[2]) .. ":" .. G:Key(l[3], l[4])] = l[8]
            end
        end
        cache.links, cache.byKey = links, byKey
    end
    return cache.byKey[fromKey .. ":" .. toKey]
end








function Router._lineReach(inst)
    local maps = FGPS.Data and FGPS.Data.insideMaps
    if inst ~= nil and maps and maps[inst] then return Graph().SURFACE_ATTACH_RADIUS end
    return nil
end


function Router._insideEnds(points)
    local maps = FGPS.Data and FGPS.Data.insideMaps
    local out = {}
    if maps then
        for _, p in ipairs(points) do
            if p and p.inst ~= nil and maps[p.inst] then out[p.inst] = true end
        end
    end
    return out
end






Router.DOOR_RECORD_YARDS = 5
function Router._doorName(fromInst, fx, fy, toInst, tx, ty)
    local maps = FGPS.Data and FGPS.Data.insideMaps
    if not maps or fromInst == toInst then return nil end
    local map, inst, x, y
    if maps[toInst] then
        map, inst, x, y = toInst, fromInst, fx, fy
    elseif maps[fromInst] then
        map, inst, x, y = fromInst, toInst, tx, ty
    else
        return nil
    end
    local best, bestD = nil, Router.DOOR_RECORD_YARDS
    for _, rec in ipairs(FGPS.Data.interiors or {}) do
        local e = rec.instanceMap == map and rec.entrance or nil
        if e and e.inst == inst then
            local d = math.sqrt((e.x - x) ^ 2 + (e.y - y) ^ 2)
            if d <= bestD then best, bestD = rec, d end
        end
    end
    return best and best.name or maps[map].name
end




local function edgeBase(ctx, fromKey, nbKey, kind, yards, seconds, transportID, shaped, fromIndoor)
    local C = Cost()
    local access, variant = ctx.access, ctx.ride
    local mode, extra, tid
    if kind == 8 then
        if variant == "no_flight" then return nil end
        local G, A = Graph(), Access()
        local fromTaxi, toTaxi = G:NodeTaxiID(fromKey), G:NodeTaxiID(nbKey)
        if not fromTaxi or not toTaxi then return nil end
        if not A:CanUseTaxiNode(access, fromTaxi) or not A:CanUseTaxiNode(access, toTaxi) then return nil end
        mode, tid = "taxi", fromTaxi
    elseif kind == 9 or kind == 10 or kind == 11 then
        if kind == 9 and variant == "no_boat" then return nil end
        local G, A = Graph(), Access()
        tid = transportID or G:NodeTransport(fromKey)
        local records = FGPS.Data and FGPS.Data.transports
        local rec = tid and records and records[tid] or nil
        if rec and not A:CanUseTransport(access, rec) then return nil end
        extra = rec
        mode = C.ModeOf(kind, rec)
    elseif kind == 7 then
        local G = Graph()
        if not Router._doorAllowed(ctx, (G:Split(fromKey)), (G:Split(nbKey))) then return nil end
        mode = "portal"
    else
        mode = "ground"
        extra = surfaceExtra(kind, fromKey, nbKey, fromIndoor)
    end
    local secs = C.EdgeSeconds(kind, yards, access, seconds, extra, shaped)
    if not secs then return nil end
    return secs, mode, tid
end









function Router._staysAboard(rec, fromStop, toStop, cameFrom)
    local legs = type(rec) == "table" and rec.legs
    if type(legs) ~= "table" or not fromStop or not toStop then return false end
    for i = 1, #legs do
        local leg = legs[i]
        if leg.to == fromStop and leg.from ~= toStop and (cameFrom == nil or leg.from == cameFrom) then return true end
    end
    return false
end



function Router._aboardAt(tid, fromKey, toKey, cameFrom)
    local records = FGPS.Data and FGPS.Data.transports
    local rec = tid and records and records[tid]
    if not rec then return nil end
    local G = Graph()
    local fromTid, fromStop = G:NodeTransport(fromKey)
    local toTid, toStop = G:NodeTransport(toKey)
    if fromTid ~= tid or toTid ~= tid or not Router._staysAboard(rec, fromStop, toStop, cameFrom) then return nil end
    return rec, fromStop
end


function Router._aboardSaving(tid, fromKey, toKey, cameFrom)
    local rec, stop = Router._aboardAt(tid, fromKey, toKey, cameFrom)
    if not rec then return 0 end
    local C = Cost()
    local saving = C.ExpectedWait(rec.period) - C.AboardWait(rec, stop)
    return saving > 0 and saving or 0
end




function Router._leastBase(ctx, e, yards)
    local secs, mode, tid = edgeBase(ctx, e.from, e.to, e.kind, yards, e.seconds, e.transportID)
    if secs and e.kind == 9 then secs = secs - Router._aboardSaving(tid, e.from, e.to) end
    return secs, mode, tid
end





local function turnCharge(ctx, parent, via, nbKey, kind, yards)
    if kind ~= 2 and not (kind == KIND_SURFACE and ctx.cityTrip) then return 0 end
    local charge = 0
    if parent and via and parent ~= ORIGIN and via ~= ORIGIN then
        local _, px, py = posOf(ctx, parent)
        local _, cx, cy = posOf(ctx, via)
        local _, nx, ny = posOf(ctx, nbKey)
        if px and cx and nx then
            local ix, iy = cx - px, cy - py
            local ox, oy = nx - cx, ny - cy
            local il = sqrt(ix * ix + iy * iy)
            local ol = sqrt(ox * ox + oy * oy)
            if il > 1 and ol > 1 then
                local cos = (ix * ox + iy * oy) / (il * ol)
                local soft = Router.TURN_SOFT_COS
                if cos < soft then

                    local t = (soft - cos) / (soft + 1)
                    if t > 1 then t = 1 elseif t < 0 then t = 0 end
                    charge = charge + Router.TURN_CHARGE_SECONDS * t
                end
            end
        end
    end
    if yards and yards < Router.SHORT_HOP_YARDS and yards >= 0 then
        charge = charge + Router.SHORT_HOP_SECONDS * (1 - yards / Router.SHORT_HOP_YARDS)
    end
    return charge
end








local function ridesBack(key, nbKey)
    local s = slotOf[key]
    local b
    if key <= BOARD_BASE then
        local parent = s and fromArr[s]
        if parent == false then parent = nil end
        s = parent and slotOf[parent]
        b = s and boardArr[s]
    else
        b = s and boardArr[s]
    end
    if not b then return false end
    local G = Graph()
    local ninst, nx, ny = G:NodePos(nbKey)
    local reach = Router.DOCK_WALL_EXEMPT_YARDS
    while b do
        local hub = BOARD_BASE - b
        if hub == nbKey then return true end
        local hinst, hx, hy = G:NodePos(hub)
        if nx and hx and hinst == ninst then
            local dx, dy = nx - hx, ny - hy
            if dx * dx + dy * dy <= reach * reach then return true end
        end
        s = slotOf[b]
        local parent = s and fromArr[s]
        if parent == false then parent = nil end
        s = parent and slotOf[parent]
        b = s and boardArr[s]
    end
    return false
end




local function visit(nbKey, kind, yards, seconds, transportID, shaped, entry)
    if closed[nbKey] then return end



    local nbSlot = slotOf[nbKey]
    local known = nbSlot and gArr[nbSlot]
    if known and known <= cur.g then return end
    if cur.boarding and not BOARDING_KINDS[kind] then return end
    if BOARDING_KINDS[kind] and ridesBack(cur.key, nbKey) then return end
    local ctx = cur.ctx


    local C, G = cur.C, cur.G
    local node = cur.node
    local access, variant = ctx.access, ctx.variant
    local secs, mode, tid, factor



    if kind == KIND_SURFACE or kind == KIND_SURFACE_SWIM then
        local length = yards or 0
        local onFoot = kind ~= KIND_SURFACE_SWIM and cur.indoor and indoorNode(nbKey)
        if kind == KIND_SURFACE_SWIM then
            secs = length / Const.SWIM_SPEED
        elseif onFoot then
            secs = length / Const.RUN_SPEED
        else
            secs = length / ctx.ground
        end
        mode = "ground"
        factor = ctx.rf[kind]
        if not factor then
            factor = C.RoadFactor(variant, kind)
            ctx.rf[kind] = factor
        end
        if kind == KIND_SURFACE and not onFoot and cur.z and length > 0 then
            factor = factor * Router._surfaceSlopeFactor(cur.z, G:NodeHeight(nbKey), length, variant)
        end
    elseif kind >= 7 and kind <= 11 then
        secs, mode, tid = edgeBase(ctx, node, nbKey, kind, yards, seconds, transportID, shaped, cur.indoor)

        if secs and kind == 9 and cur.aboard and tid == cur.aboard then
            secs = secs - Router._aboardSaving(tid, node, nbKey, cur.aboardFrom)
        end
    else
        secs, mode = C.EdgeSeconds(kind, yards, access, seconds, surfaceExtra(kind, node, nbKey, cur.indoor), shaped), "ground"
    end
    if not secs then return end
    local wetChord = not shaped and (kind == KIND_CONNECTOR or kind == KIND_ROAD or kind == 17)
        and Router._chordCrossesWater(G, C, node, nbKey, kind)
    if wetChord then
        secs = (yards or 0) / Const.SWIM_SPEED
        factor = 1
    end
    if not factor then
        local doubt
        if kind == KIND_ROAD then doubt = G:EdgeDoubt((G:Split(node)), entry) end

        local rf = ctx.rf[kind]
        if not rf then
            rf = C.RoadFactor(variant, kind)
            ctx.rf[kind] = rf
        end
        factor = rf * C.ChordFactor(kind, yards, shaped, doubt)
    end


    if kind == KIND_CONNECTOR or (kind == KIND_MESH and yards and yards >= Router.WALL_CHECK_MIN_YARDS) then
        local finst, fx, fy = G:NodePos(node)
        local _, nx2, ny2 = G:NodePos(nbKey)
        if fx and nx2 then
            local dock = dockBetween(node, nbKey)
            local stored = kind == KIND_CONNECTOR
            local hard, sparse = cutsObstacle(finst, fx, fy, nx2, ny2, ctx.cityTrip, G:NodeHeightGuess(node), G:NodeHeightGuess(nbKey),
                dock, stored and dock, stored)
            if hard then return end
            factor = factor * sparseFactor(sparse)
        end
    end
    if kind == KIND_CONNECTOR and yards and yards >= WATER_CHECK_YARDS
        and not isTransportStop(G:NodeFlags(node)) and not isTransportStop(G:NodeFlags(nbKey)) then




        local finst, fx, fy = G:NodePos(node)
        local _, nx2, ny2 = G:NodePos(nbKey)
        if fx and nx2 then secs = secs * C.WaterFactor(kind, finst, fx, fy, nx2, ny2, access) end
    end


    if mode == "ground" and ctx.guarded and (cur.guardedNear or not yards or yards > Const.GUARDED_NEAR) then
        local finst, fx, fy = G:NodePos(node)
        local _, nx2, ny2 = G:NodePos(nbKey)
        if fx and nx2 then
            factor = factor * C.GuardedFactor((C.GuardedShare(ctx.guarded, finst, fx, fy, nx2, ny2,
                G:NodeHeightGuess(node), G:NodeHeightGuess(nbKey))))
        end
    end


    local baseSecs = secs
    local charged = baseSecs * factor
    if (variant == "roads_only" or variant == "prefer_roads")
        and (kind == KIND_SURFACE or kind == 1 or kind == 2 or kind == KIND_CONNECTOR or kind == KIND_MESH or kind == 19)
        and not (cur.indoor and indoorNode(nbKey))
        and G:IsRoadNode(node) and not G:IsRoadNode(nbKey) then
        charged = charged + C.RoadExitSeconds(variant, kind, false, true, false)
    end



    if kind == KIND_SURFACE_SWIM or wetChord then charged = charged + Const.SWIM_CROSSING_CHARGE end


    local penalty, boarding = 0, 0
    if mode ~= "ground" and mode ~= cur.mode then penalty, boarding = C.TransferPenalty(ctx.ride), C.TransferPenalty() end
    if kind == KIND_CONNECTOR and cur.z then


        charged = charged + climbCharge(ctx, yards, cur.z, G:NodeHeight(nbKey))
    end




    if kind == 1 or kind == KIND_MESH then
        local zFrom = cur.z or G:NodeHeightGuess(node)
        local zToMeasured = G:NodeHeight(nbKey)
        local zTo = zToMeasured or G:NodeHeightGuess(nbKey)
        if zFrom and zTo and not (cur.z and zToMeasured) then
            local rise = abs(zTo - zFrom)
            if rise > Router.CLIFF_Z_YARDS and rise > Router.CLIMB_WALKABLE_SLOPE * (yards or 0) then
                charged = charged + climbCharge(ctx, yards, zFrom, zTo)
            end
        end
    end

    if kind == 2 or (kind == KIND_SURFACE and ctx.cityTrip) then
        charged = charged + turnCharge(ctx, cur.parent, cur.key, nbKey, kind, yards)
    end
    local g = cur.g + charged + penalty
    if known and known <= g then return end
    relax(ctx, nbKey, g, cur.key, kind, yards, baseSecs, boarding, mode, tid)
end





local function straightCost(ctx, d, inst, x1, y1, x2, y2, extra)
    local C = Cost()
    local base = C.EdgeSeconds(KIND_ATTACH, d, ctx.access, nil, extra)
    if not base then return nil end
    if x1 and x2 and d >= WATER_CHECK_YARDS then
        base = base * C.WaterFactor(KIND_ATTACH, inst, x1, y1, x2, y2, ctx.access)
    end
    return base, base * C.RoadFactor(ctx.variant, KIND_ATTACH) * C.ChordFactor(KIND_ATTACH, d)
end






local function hubStretchCost(ctx, d, inst, x1, y1, x2, y2, stop, extra)
    if not stop then return straightCost(ctx, d, inst, x1, y1, x2, y2, extra) end
    local honest, charged = straightCost(ctx, d, nil, nil, nil, nil, nil, extra)
    local land = d - WATER_CHECK_YARDS
    if not honest or land < WATER_CHECK_YARDS or not x1 or not x2 then return honest, charged end
    local t = land / d
    local factor = Cost().WaterFactor(KIND_ATTACH, inst, x1, y1, x1 + (x2 - x1) * t, y1 + (y2 - y1) * t, ctx.access)

    local scale = 1 + (factor - 1) * t
    return honest * scale, charged * scale
end




local function hubUsable(ctx, key, flags)
    local ok = ctx.hubOK[key]
    if ok ~= nil then return ok end
    local G, A = Graph(), Access()
    local access, variant = ctx.access, ctx.ride
    ok = false
    local taxiID = G:NodeTaxiID(key)
    if taxiID then
        ok = variant ~= "no_flight" and A:CanUseTaxiNode(access, taxiID)
    end
    if not ok then
        local tid = G:NodeTransport(key)
        if tid then
            local records = FGPS.Data and FGPS.Data.transports
            local rec = records and records[tid]
            if rec then
                local kind = rec.kind
                local boatLike = kind == "boat" or kind == "ferry" or kind == "zeppelin"
                ok = A:CanUseTransport(access, rec) and not (variant == "no_boat" and boatLike)
            else
                ok = true
            end
        end
    end
    ctx.hubOK[key] = ok
    return ok
end



local function hubVisit(hubKey, d, flags)
    if hubKey == cur.node then return end
    local target = hubKey
    if cur.boardOnly then target = BOARD_BASE - hubKey end
    if closed[target] then return end
    local ctx = cur.ctx


    local hubSlot = slotOf[target]
    local known = hubSlot and gArr[hubSlot]
    if known and cur.g + d * ctx.straightRate * Cost().ChordFactor(KIND_ATTACH, d) * straightRisk(d) >= known then return end
    if not hubUsable(ctx, hubKey, flags) or Router._enclosed(ctx, hubKey) then return end
    local G = Graph()
    local hinst, hx, hy = G:NodePos(hubKey)
    local _, fx, fy = G:NodePos(cur.node)
    local stop = isTransportStop(flags or G:NodeFlags(hubKey))
    if hinst and fx and hx and Router._swimRefused(hinst, fx, fy, hx, hy, dockAt(hubKey)) then return end


    local sparse = false
    if hinst and fx and hx then
        local hard
        hard, sparse = cutsObstacle(hinst, fx, fy, hx, hy, ctx.cityTrip, cur.zt, G:NodeHeightGuess(hubKey), dockAt(hubKey))
        if hard then return end
    end
    local honest, chargeBase = hubStretchCost(ctx, d, hinst, fx, fy, hx, hy, stop, straightExtra(cur.node, hubKey, cur.indoor))
    if not honest then return end
    chargeBase = chargeBase * sparseFactor(sparse)
    if ctx.guarded and fx and hx then
        local C = Cost()
        chargeBase = chargeBase * C.GuardedFactor((C.GuardedShare(ctx.guarded, hinst, fx, fy, hx, hy)))
    end
    local charged = chargeBase * straightRisk(d)
    if cur.z then
        local stackedHub = (ctx.goalHubs and ctx.goalHubs[hubKey]) or (hubKey == ctx.destHubKey and ctx.destStacked)
        charged = charged + climbCharge(ctx, d, cur.z, G:NodeHeight(hubKey), stackedHub)
    end
    relax(ctx, target, cur.g + charged, cur.key, KIND_ATTACH, d, honest, 0, "ground", nil, VIA_DIRECT)
end



local EDGE_CHARS, HEIGHT_BASE, FIRST_CHAR, SKIPPED_CHAR = 4, 91, 35, 92




Router._DEC2, Router._DEC1, Router._DEC0 = {}, {}, {}
for b = 0, 255 do
    local v = b
    if v > SKIPPED_CHAR then v = v - 1 end
    v = v - FIRST_CHAR
    Router._DEC2[b], Router._DEC1[b], Router._DEC0[b] = v * HEIGHT_BASE * HEIGHT_BASE, v * HEIGHT_BASE, v
end
local KEY_BASE = 1048576



local ROAD_LINE_KIND = { [1] = true, [2] = true, [4] = true, [6] = true, [12] = true, [17] = true, [18] = true }


































Router.LANDMARKS = true
Router.LANDMARK_ACTIVE = 8
Router.LANDMARK_EXACT_YARDS = 300




Router.LANDMARK_INLINE_PLACE = true
Router.LANDMARK_LINE_MEMO = true
Router.LANDMARK_EXACT_SHARE = 1.5
Router.LANDMARK_NONE = 91 ^ 3 - 1

Router.LANDMARK_SETUPS = 8





Router.LANDMARK_ORIGIN_YARDS = 500





Router.LANDMARK_MEMO_KEYS = 200000



function Router._landmarkBound(lm, side, idx)
    local row = side.row
    local slot = idx - 1
    local at = slot % row
    local r = (slot - at) / row + 1
    at = at * 3
    local columns, p, n, none = side.rows, lm.p, lm.n, Router.LANDMARK_NONE
    local strbyte = string.byte
    local dec2, dec1, dec0 = Router._DEC2, Router._DEC1, Router._DEC0
    local known = false
    for l = 1, n do
        local rows = columns[l]
        local v = false
        if rows then
            local s = rows[r]
            if not s then return 0 end
            local b1, b2, b3 = strbyte(s, at + 1, at + 3)
            if not b3 then return 0 end
            v = dec2[b1] + dec1[b2] + dec0[b3]


            if v >= none then return lm.unjoined end
            known = true
        end
        p[l] = v
    end
    if not known then return 0 end







    local wc, wlo, whi, best = lm.wc, lm.wlo, lm.whi, huge
    local lead = 0
    for j = 1, lm.ways do
        local c = wc[j]
        if c >= best then break end
        local d, o, top = 0, (j - 1) * n, 0
        if lead > 0 then
            local v = p[lead]
            local lo, hi = wlo[o + lead], whi[o + lead]
            d = (v < lo and lo - v) or (v > hi and v - hi) or 0
            top = lead
        end
        if c + d < best then
            for l = 1, n do
                local v = p[l]
                if v and l ~= lead then
                    local lo, hi = wlo[o + l], whi[o + l]
                    local e = (v < lo and lo - v) or (v > hi and v - hi) or 0
                    if e > d then
                        d, top = e, l
                        if c + d >= best then break end
                    end
                end
            end
            if c + d < best then best = c + d end
        end
        if top > 0 then lead = top end
    end
    if best == huge then return 0 end
    return best * lm.scale
end






function Router._landmarkAt(lm, inst, key)
    local side = lm.insts[inst]
    if side == nil then side = Router._landmarkSide(lm, inst) end
    if not side then return 0 end
    local idx
    if key >= 0 then
        idx = key - side.base
    else
        local hub = BOARD_BASE - key
        local dead = lm.dead[hub]
        if dead then return dead end
        idx = side.board[hub - side.base]
        if not idx then return 0 end
    end
    local memo = side.memo
    local v = memo[idx]
    if v then return v end
    v = Router._landmarkBound(lm, side, idx)
    local count = lm.bounds
    if count.n < Router.LANDMARK_MEMO_KEYS then
        memo[idx], count.n, side.n = v, count.n + 1, side.n + 1
    end
    return v
end


function Router._landmarkColumns(block)
    local cols = block._cols
    if not cols then
        cols = {}
        for c = 1, block.k do cols[block.ids[c]] = c end
        block._cols = cols
    end
    return cols
end




function Router._landmarkBoard(inst, block)
    local board = block._board
    if board ~= nil then return board end
    local G = Graph()
    local g = G:Ensure(inst)
    local hubs = G:Hubs(inst)
    board = {}
    for j = 1, #block.hubs do board[block.hubs[j]] = g.n + j end
    if #hubs ~= #block.hubs then board = false end
    for i = 1, board and #hubs or 0 do
        if not board[hubs[i] - inst * KEY_BASE] then
            board = false
            break
        end
    end
    block._board = board
    return board
end


function Router._landmarkSide(lm, inst)
    local G = Graph()

    local block
    if lm.roads then block = G:RoadsLandmarks(inst) else block = G:Landmarks(inst) end
    local side = false
    if block and block.speed == lm.speed and G:IsVetted(inst) then
        local board = Router._landmarkBoard(inst, block)
        if board then
            local cols = Router._landmarkColumns(block)
            local rows, any = {}, false
            for i = 1, lm.n do
                local c = cols[lm.ids[i]]
                rows[i] = c and block.p[c] or false
                if c then any = true end
            end
            if any then side = { rows = rows, row = block.row, base = inst * KEY_BASE, board = board, src = block.p, memo = {}, n = 0 } end
        end
    end
    lm.insts[inst] = side
    return side
end


function Router._lineBound(ctx, d)
    return d * ctx.straightRate * Cost().ChordFactor(KIND_ATTACH, d) * straightRisk(d)
end





function Router._surfaceEnclosed(g)
    local ringed = g.inst ~= nil and Router._hazardNodes(Graph(), g.inst) or nil
    local tagged = Router._taggedEnclosed(g)
    if not ringed then return tagged end
    return function(idx) return ringed[idx] ~= nil or tagged(idx) end
end


function Router._taggedEnclosed(g)
    local surf = g._surf
    if not surf then return function() return false end end
    local strbyte, SKIP, FIRST, HB = string.byte, SKIPPED_CHAR, FIRST_CHAR, HEIGHT_BASE
    local sFirst, sLast, sRow, sT = surf.first, surf.last, surf.row, surf.t
    local width = surf.w == 2 and 2 or 3
    return function(idx)
        if idx < sFirst or idx > sLast then return false end
        local slot = idx - sFirst
        local at = slot % sRow
        local rs = sT[(slot - at) / sRow + 1]
        if type(rs) ~= "string" then return false end
        at = at * width
        local b1, b2, b3 = strbyte(rs, at + 1, at + width)
        if not b1 or not b2 then return false end
        if b1 > SKIP then b1 = b1 - 1 end
        if b2 > SKIP then b2 = b2 - 1 end
        local value = (b1 - FIRST) * HB + (b2 - FIRST)
        if width == 3 then
            if not b3 then return false end
            if b3 > SKIP then b3 = b3 - 1 end
            value = value * HB + (b3 - FIRST)
        end
        local bits = value % 8
        return bits % 2 == 1 or bits % 4 >= 2
    end
end







function Router._landmarkWays(ctx, lm, board, scale, cols, attachOnly, exact)
    local G = Graph()
    local dest = ctx.dest
    local cells = G:LandmarkCells(dest.inst, function() return Scheduler().Yield() end)
    if not cells then return false end
    local k, row, base = #cols, lm.row, dest.inst * KEY_BASE
    local unpack, none = G.UnpackLandmark, Router.LANDMARK_NONE
    local ways = { dead = {} }
    local strbyte = string.byte


    local fast = not Router._slowUnpack
    local prow, dec2, dec1, dec0 = {}, Router._DEC2, Router._DEC1, Router._DEC0
    for t = 1, k do prow[t] = lm.p[cols[t]] end
    local function offer(idx, charge, attach, line)
        local p = {}
        local slot = idx - 1
        local at = slot % row
        local r = (slot - at) / row + 1
        at = at * 3
        for t = 1, k do
            local v
            if fast then
                local rs = prow[t][r]
                if type(rs) == "string" then
                    local b1, b2, b3 = strbyte(rs, at + 1, at + 3)
                    if b3 then
                        v = dec2[b1] + dec1[b2] + dec0[b3]
                    end
                end
            else
                v = unpack(lm.p[cols[t]], row, idx, 3)
            end
            if not v then return end
            if v >= none then
                ways.unjoined = true
                return
            end
            p[t] = v
        end
        ways[#ways + 1] = { c = charge / scale, lo = p, hi = p, attach = attach, line = line }
    end
    for key, cand in pairs(ctx.destAttach or {}) do
        local secs, _, charged = attachCost(ctx, cand, key, destHeightFrom(ctx, cand.footZ), ctx.destStacked, ctx.dest.x, ctx.dest.y)
        if secs then offer(key - base, charged, true) end
    end
    local reach = ctx.maxStraight or 0
    if attachOnly or reach <= 0 or ctx.destEnclosed then return ways end
    local g = G:Ensure(dest.inst)
    local grid, xs, ys = g._grid, g.x, g.y
    local cell = lm.cell
    local enclosedAt
    if Router.LANDMARK_INLINE_PLACE and G.loaded and G.loaded[dest.inst] == g then enclosedAt = Router._surfaceEnclosed(g) end


    local memoAll = Router.LANDMARK_LINE_MEMO and (ctx.lmLineMemo or {}) or nil
    if memoAll then ctx.lmLineMemo = memoAll end
    local sched, cancelled, steps = Scheduler(), false, 0
    local function lines(x, y, radius, extra, zTo, stacked, dock, mid)
        local memo = memoAll and mid ~= nil and memoAll[mid]
        if memoAll and mid ~= nil and not memo then
            memo = {}
            memoAll[mid] = memo
        end
        for cx = floor((x - radius) / cell), floor((x + radius) / cell) do
            for cy = floor((y - radius) / cell), floor((y + radius) / cell) do
                steps = steps + 1
                if steps >= 256 then
                    steps = 0
                    if not sched.Yield() then
                        cancelled = true
                        return
                    end
                end
                local ck = (cx + 32768) * 65536 + (cy + 32768)
                local slot = cells[ck]
                if slot then
                    local left, bottom = cx * cell, cy * cell
                    local dx = (x < left and left - x) or (x > left + cell and x - left - cell) or 0
                    local dy = (y < bottom and bottom - y) or (y > bottom + cell and y - bottom - cell) or 0
                    local near = sqrt(dx * dx + dy * dy)
                    if near < exact then
                        local list = grid and grid[ck]
                        local copied = false





                        for i = 2, list and #list or 0 do
                            if list[i] < list[i - 1] then
                                local copy = {}
                                for j = 1, #list do copy[j] = list[j] end
                                table.sort(copy)
                                list, copied = copy, true
                                break
                            end
                        end
                        if list and not copied and steps + #list >= 256 then
                            local copy = {}
                            for j = 1, #list do copy[j] = list[j] end
                            list = copy
                        end
                        for i = 1, list and #list or 0 do
                            steps = steps + 1
                            if steps >= 256 then
                                steps = 0
                                if not sched.Yield() then
                                    cancelled = true
                                    return
                                end
                            end
                            local idx = list[i]
                            local charge
                            if memo then charge = memo[idx] end
                            if charge == nil then
                                charge = false
                                local d = sqrt((xs[idx] - x) ^ 2 + (ys[idx] - y) ^ 2)


                                if d <= radius and not (enclosedAt and enclosedAt(idx) or (not enclosedAt and Router._enclosed(ctx, base + idx)))
                                    and not Router._swimRefused(dest.inst, xs[idx], ys[idx], x, y, dock) then
                                    charge = Router._lineBound(ctx, d) + extra
                                    local z = G:NodeHeight(base + idx)
                                    if z then charge = charge + climbCharge(ctx, d, z, zTo(z), stacked) end
                                end
                                if memo then memo[idx] = charge end
                            end
                            if charge then offer(idx, charge, nil, mid == "dest" and idx or nil) end
                        end
                    elseif near <= radius then
                        local lo, hi = {}, {}
                        for t = 1, k do
                            lo[t] = unpack(lm.lo[cols[t]], row, slot, 3)
                            hi[t] = unpack(lm.hi[cols[t]], row, slot, 3)
                        end

                        if lo[1] and hi[1] and lo[1] <= hi[1] then
                            ways[#ways + 1] = { c = (Router._lineBound(ctx, near) + extra) / scale, lo = lo, hi = hi }
                        end
                    end
                end
            end
        end
        if steps > 0 then
            steps = 0
            if not sched.Yield() then cancelled = true end
        end
    end



    G:HubsNear(dest.inst, dest.x, dest.y, G.ATTACH_VERIFIED_RADIUS, function(hubKey, d)
        if cancelled then return end
        if not Router._enclosed(ctx, hubKey) then
            local _, hx, hy = G:NodePos(hubKey)
            local hubDock = dockAt(hubKey)

            if hx and Router._swimRefused(dest.inst, hx, hy, dest.x, dest.y, hubDock) then return end
            local charge = Router._lineBound(ctx, d)
            local z = G:NodeHeight(hubKey)
            if z then charge = charge + climbCharge(ctx, d, z, (destHeightFrom(ctx, z)), ctx.destStacked) end
            local idx = board[hubKey - base]
            local v = idx and unpack(lm.p[cols[1]], row, idx, 3)
            if v and v < none then
                offer(idx, charge)
            elseif ctx.hubReach > 0 then
                ways.dead[hubKey] = charge
                local hz = z
                lines(hx, hy, ctx.hubReach, charge, function() return hz end, nil, hubDock, hubKey)
                if cancelled then return end

                ways.unjoined = true
            end
        end
    end)
    if cancelled then return false end
    lines(dest.x, dest.y, reach, 0, function(z) return (destHeightFrom(ctx, z)) end, ctx.destStacked, false, "dest")
    if cancelled then return false end
    return ways
end




function Router._keptServes(kept, o)
    if kept.oInst ~= o.inst then return false end
    local D, reach = Coords().Distance, Router.LANDMARK_ORIGIN_YARDS
    if D(kept.oX, kept.oY, o.x, o.y) <= reach then return true end
    local along = kept.along
    for i = 1, along and #along or 0, 2 do
        if D(along[i], along[i + 1], o.x, o.y) <= reach then return true end
    end
    return false
end



function Router._noteAlong(ctx, legs)
    local lm = ctx.lm
    if not lm or not lm.oInst or lm.along then return end
    local along = {}
    for _, leg in ipairs(legs) do
        if leg.kind == "walk" and leg.inst == lm.oInst then
            for _, p in ipairs(leg.points or {}) do
                along[#along + 1], along[#along + 2] = p.x, p.y
            end
        end
    end
    lm.along = along
end





function Router._keptColumns(active)
    local G = Graph()
    for inst, side in pairs(active.insts) do
        local block
        if active.roads then block = G:RoadsLandmarks(inst) else block = G:Landmarks(inst) end
        if (side and side.src ~= (block and block.p)) or (not side and block) then
            if side then active.bounds.n = active.bounds.n - side.n end
            active.insts[inst] = nil
        end
    end
end


function Router._forgetBounds(active)
    for _, set in ipairs({ active, active.second or false }) do
        for _, side in pairs(set and set.insts or {}) do
            if side then side.memo, side.n = {}, 0 end
        end
    end
    active.bounds.n = 0
end




function Router._keepBoundsOf(active)
    local last = Router._boundsOf
    if last and last ~= active then Router._forgetBounds(last) end
    Router._boundsOf = active
end







function Router._releaseBounds()
    local last = Router._boundsOf
    if last then Router._forgetBounds(last) end
end





function Router.UsesLandmarks(access, variant)
    if not Router.LANDMARKS then return false end
    local C = Cost()
    return variant == "no_flight" or C.MaxSpeed(access) <= C.GroundSpeed(access)
end

function Router._landmarkSetup(ctx)
    ctx.lm, ctx.lm2 = nil, nil
    local C, G = Cost(), Graph()
    local access, variant, dest = ctx.access, ctx.variant, ctx.dest
    if not Router.UsesLandmarks(access, ctx.ride) then return end
    local lm = G:Landmarks(dest.inst)

    if not lm or not vettedInst(ctx, dest.inst) then return end
    local board = Router._landmarkBoard(dest.inst, lm)
    if not board then return end
    local speed = C.GroundSpeed(access)

    if speed < lm.speed then return end


    local share = 1
    for kind = 1, 23 do
        local base, mine = C.RoadFactor("fastest", kind), C.RoadFactor(variant, kind)
        if base > 0 and mine / base < share then share = mine / base end
    end
    local scale = share / speed











    local cacheKey
    if access.hash ~= nil then
        cacheKey = string.format("%s|%s|%.3f|%.3f|%s|%s|%s|%.6f|%.6f|%.9g|%.9g|%s|%s|%s|%s|%s", tostring(access.hash), tostring(variant) .. "/" .. tostring(ctx.ride),
            dest.x, dest.y, tostring(dest.z), tostring(dest.zHint), Router._placeKey(dest), ctx.maxStraight or 0,
            ctx.hubReach or 0, scale, ctx.straightRate or 0, tostring(dest.poiIndex), tostring(dest.map),
            tostring(dest.floor), tostring(Router._freePoint(ctx, dest, true)), tostring(ctx.cityTrip))
        local mine = Router._landmarkSetups and Router._landmarkSetups[lm]
        local kept = mine and mine[cacheKey]
        if kept and not Router._keptServes(kept, ctx.origin) then kept = nil end
        if kept then
            Router._keptColumns(kept)
            if kept.second then Router._keptColumns(kept.second) end
            Router._keepBoundsOf(kept)
            ctx.lm, ctx.lm2 = kept, kept.second
            return
        end
    end
    local active = Router._landmarkActive(ctx, lm, board, scale)
    if not active then return end





    if variant == "roads_only" then
        local roads = G:RoadsLandmarks(dest.inst)
        local rboard = roads and Router._landmarkBoard(dest.inst, roads)


        if rboard and not Scheduler().Yield() then return end
        if rboard then
            local second = Router._landmarkActive(ctx, roads, rboard, 1 / speed)
            if second == false then return end

            if second then second.bounds = active.bounds end
            active.second = second
        end
    end
    ctx.lm, ctx.lm2 = active, active.second
    if cacheKey then
        local setups = Router._landmarkSetups
        if not setups then
            setups = setmetatable({}, { __mode = "k" })
            Router._landmarkSetups = setups
        end
        local mine = setups[lm]
        if not mine or mine.n >= Router.LANDMARK_SETUPS then
            mine = { n = 0 }
            setups[lm] = mine
        end
        local o = ctx.origin
        active.oInst, active.oX, active.oY = o.inst, o.x, o.y
        if mine[cacheKey] then mine[cacheKey] = active else mine[cacheKey], mine.n = active, mine.n + 1 end
        Router._keepBoundsOf(active)
    end
end















function Router._judgedWays(ctx, ways, n, scale)
    local memo = ctx.lmLineInto
    if not memo then
        memo = {}
        ctx.lmLineInto = memo
    end
    local G, dest = Graph(), ctx.dest
    local base = dest.inst * KEY_BASE
    local function before(a, b) return a.c < b.c or (a.c == b.c and a.attach and not b.attach) end
    table.sort(ways, before)

    local later = {}
    local kept, wc, wlo, whi = {}, {}, {}, {}
    local i = 1
    while true do
        local u
        if later[1] and (i > #ways or before(later[1], ways[i])) then
            u = table.remove(later, 1)
        elseif i <= #ways then
            u, i = ways[i], i + 1
        else
            break
        end
        local ulo, uhi, needed = u.lo, u.hi, true
        for j = 1, #kept do
            local w = kept[j]
            local room = u.c - w.c
            local wl, wh, far = w.lo, w.hi, 0
            for t = 1, n do
                local e = wl[t] - ulo[t]
                local e2 = uhi[t] - wh[t]
                if e2 > e then e = e2 end
                if e > far then
                    far = e
                    if far > room then break end
                end
            end
            if far <= room then
                needed = false
                break
            end
        end
        local idx = needed and u.line
        if idx then
            u.line = nil
            local charge = memo[idx]
            if charge == nil then
                local key = base + idx
                local inst, x, y = G:NodePos(key)
                local z = G:NodeHeight(key)
                local _, charged = Router._lineInto(ctx, key, inst, x, y, z, z or G:NodeHeightGuess(key),
                    Coords().Distance(x, y, dest.x, dest.y), true)
                charge = charged or false
                memo[idx] = charge
            end
            if not charge then
                needed = false
            elseif charge / scale > u.c then
                u.c, needed = charge / scale, false
                local at = #later + 1
                for j = 1, #later do
                    if before(u, later[j]) then
                        at = j
                        break
                    end
                end
                table.insert(later, at, u)
            end
        end
        if needed then
            local j = #kept + 1
            kept[j], wc[j] = u, u.c
            for t = 1, n do wlo[(j - 1) * n + t], whi[(j - 1) * n + t] = ulo[t], uhi[t] end
        end
    end
    return kept, wc, wlo, whi
end




function Router._landmarkActive(ctx, lm, board, scale)
    local G, dest = Graph(), ctx.dest
    local k = lm.k
    local all = {}
    for l = 1, k do all[l] = l end



    local attach = Router._landmarkWays(ctx, lm, board, scale, all, true)
    if not attach then return false end
    local first
    for i = 1, #attach do
        if not first or attach[i].c < first.c then first = attach[i] end
    end
    local score = {}
    for l = 1, k do score[l] = { l = l, b = huge } end
    local any = false
    local unpack, none = G.UnpackLandmark, Router.LANDMARK_NONE
    for key in pairs(first and ctx.originAttach or {}) do
        local inst = floor(key / KEY_BASE)
        local block = lm
        if inst ~= dest.inst then
            if lm.roads then block = G:RoadsLandmarks(inst) else block = G:Landmarks(inst) end
        end
        if block and block.speed == lm.speed then
            local cols = Router._landmarkColumns(block)
            any = true
            for l = 1, k do
                local c = cols[lm.ids[l]]
                local v = c and unpack(block.p[c], block.row, key - inst * KEY_BASE, 3)
                local b = (v and v < none) and abs(v - first.lo[l]) or 0
                if b < score[l].b then score[l].b, score[l].beyond = b, v and v > first.lo[l] end
            end
        end
    end
    local n = Router.LANDMARK_ACTIVE
    if n > k then n = k end
    if any then table.sort(score, function(a, b) return a.b > b.b or (a.b == b.b and a.l < b.l) end) end


    local pick, used, half = {}, {}, math.ceil(n / 2)
    for _, side in ipairs({ true, false }) do
        local count = 0
        for i = 1, k do
            if count < half and #pick < n and (score[i].beyond == true) == side then
                pick[#pick + 1], used[i], count = score[i].l, true, count + 1
            end
        end
    end
    for i = 1, k do
        if #pick < n and not used[i] then pick[#pick + 1], used[i] = score[i].l, true end
    end



    local want = any and Router.LANDMARK_EXACT_SHARE * score[1].b * scale or 0
    local exact, reach = Router.LANDMARK_EXACT_YARDS, ctx.maxStraight or 0
    while exact < reach and Router._lineBound(ctx, exact) < want do exact = exact + 50 end
    local ways = Router._landmarkWays(ctx, lm, board, scale, pick, false, exact)
    if not ways then return false end
    local kept, wc, wlo, whi = Router._judgedWays(ctx, ways, n, scale)
    if #kept == 0 then return nil end


    local unjoined = ways.unjoined or (exact < reach and not ctx.destEnclosed)
    local active = { ids = {}, n = n, p = {}, ways = #kept, wc = wc, wlo = wlo, whi = whi, scale = scale,
                     speed = lm.speed, insts = {}, dead = ways.dead, unjoined = unjoined and 0 or huge, roads = lm.roads,
                     bounds = { n = 0 } }
    for t = 1, n do active.ids[t] = lm.ids[pick[t]] end
    return active
end

local function roadLineKey(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    local len2 = dx * dx + dy * dy
    if len2 < 1 then return nil end
    local len = math.sqrt(len2)
    dx, dy = dx / len, dy / len
    if dx < 0 or (dx == 0 and dy < 0) then dx, dy = -dx, -dy end
    local off = x1 * dy - y1 * dx
    return string.format("%d:%d:%d", math.floor(dx * 10000 + 0.5), math.floor(dy * 10000 + 0.5), math.floor(off * 2 + 0.5))
end











function Router._eachEntry(g, fn, nodes)
    local eo, ep, xs = g.eo, g._ep, g.x
    local n = nodes and #nodes or g.n or 0
    local perRow = ep and ep.row
    if not (eo and ep and ep.a and perRow and perRow > 0 and xs) then return end
    local rows, rowEnd = ep.a, perRow * EDGE_CHARS
    local strbyte = string.byte
    for m = 1, n do
        local i = nodes and nodes[m] or m
        local first, stop = eo[i], eo[i + 1]
        if first and stop and first < stop then
            local slot = first - 1
            local at = slot % perRow
            local r = (slot - at) / perRow + 1
            local row = rows[r]
            at = at * EDGE_CHARS
            for _ = first, stop - 1 do
                if at >= rowEnd then
                    r = r + 1
                    row, at = rows[r], 0
                end
                if type(row) ~= "string" then break end
                local b1, b2, b3, b4 = strbyte(row, at + 1, at + EDGE_CHARS)
                if not b4 then break end
                if b1 > SKIPPED_CHAR then b1 = b1 - 1 end
                if b2 > SKIPPED_CHAR then b2 = b2 - 1 end
                if b3 > SKIPPED_CHAR then b3 = b3 - 1 end
                if b4 > SKIPPED_CHAR then b4 = b4 - 1 end
                local nb = ((b1 - FIRST_CHAR) * HEIGHT_BASE + (b2 - FIRST_CHAR)) * HEIGHT_BASE + (b3 - FIRST_CHAR)
                if xs[nb] and fn(i, nb, b4 - FIRST_CHAR) == false then return end
                at = at + EDGE_CHARS
            end
        end
    end
end

local function roadPieces(G, inst)
    local g = G:Ensure(inst)
    if not g then return nil end
    if g._roadPieces then return g._roadPieces end


    local pc = g._pc


    if pc and G._columnReady and G._columnReady(pc.rp, 2 * pc.nr) then
        g._roadPieces = { g = g, rows = pc.rp, pairs = pc.nr }
        return g._roadPieces
    end
    local n = g.n or 0
    local parent = {}
    for i = 1, n do parent[i] = i end
    Router._eachEntry(g, function(a, b)
        while parent[a] ~= a do
            local up = parent[parent[a]]
            parent[a] = up
            a = up
        end
        while parent[b] ~= b do
            local up = parent[parent[b]]
            parent[b] = up
            b = up
        end
        if a ~= b then parent[b] = a end
    end)
    for i = 1, n do
        local r = i
        while parent[r] ~= r do r = parent[r] end
        parent[i] = r
    end
    local pieces = { root = parent, g = g }
    g._roadPieces = pieces
    return pieces
end



function Router._fillRoadRoot(pieces)
    if pieces.root then return true end
    local rows, pairs = pieces.rows, pieces.pairs
    if not rows or not pairs or pairs <= 0 then
        pieces.root = {}
        return true
    end
    local at, root, S = Graph()._packedAt, {}, Scheduler()


    if not S.Yield() then return false end
    for i = 0, pairs - 1 do
        if i > 0 and i % 512 == 0 and not S.Yield() then return false end
        local node, piece = at(rows, i * 2), at(rows, i * 2 + 1)
        if not node or not piece then return false end
        root[node] = piece
    end
    pieces.root = root
    return true
end

function Router._roadRoot(pieces, idx)
    if pieces.root then return pieces.root[idx] or 0 end
    if not pieces.rows then return 0 end
    return Graph()._packedPair(pieces.rows, pieces.pairs, idx) or 0
end

function Router._roadPieceLines(pieces)
    if pieces.lines then return pieces.lines end
    if not Router._fillRoadRoot(pieces) then return nil end
    local g, root, lines = pieces.g, pieces.root, {}
    local xs, ys = g.x, g.y
    local seen, S = 0, Scheduler()
    local stop = false


    if not S.Yield() then return nil end
    Router._eachEntry(g, function(i, nb, kind)
        if stop then return false end
        seen = seen + 1
        if seen % 128 == 0 and not S.Yield() then
            stop = true
            return false
        end
        if ROAD_LINE_KIND[kind] then
            local lk = roadLineKey(xs[i], ys[i], xs[nb], ys[nb])
            if lk then
                local r = root[i] or 0
                local set = lines[r]
                if not set then
                    set = {}
                    lines[r] = set
                end
                set[lk] = true
            end
        end
    end)
    if stop then return nil end
    pieces.lines = lines
    return lines
end





Router.ROAD_LINES_PER_PIECE = true
function Router._roadLinesFor(pieces, r)
    if pieces.lines or r == 0 or not Router.ROAD_LINES_PER_PIECE then
        local lines = Router._roadPieceLines(pieces)
        if not lines then return nil end
        return lines[r] or false
    end
    local by = pieces.linesBy
    if by and by[r] ~= nil then return by[r] end
    if not Router._fillRoadRoot(pieces) then return nil end
    local S = Scheduler()
    local members = pieces.members
    if not members then
        members = {}
        local seen = 0
        for node, piece in pairs(pieces.root) do
            seen = seen + 1
            if seen % 4096 == 0 and not S.Yield() then return nil end
            local list = members[piece]
            if not list then
                list = {}
                members[piece] = list
            end
            list[#list + 1] = node
        end
        pieces.members = members
    end
    local g = pieces.g
    local xs, ys = g.x, g.y
    local set = false
    local list = members[r]
    if list then
        local seen, stop = 0, false
        Router._eachEntry(g, function(i, nb, kind)
            seen = seen + 1
            if seen % 128 == 0 and not S.Yield() then
                stop = true
                return false
            end
            if ROAD_LINE_KIND[kind] then
                local lk = roadLineKey(xs[i], ys[i], xs[nb], ys[nb])
                if lk then
                    if not set then set = {} end
                    set[lk] = true
                end
            end
        end, list)
        if stop then return nil end
    end
    if not by then
        by = {}
        pieces.linesBy = by
    end
    by[r] = set
    return set
end



local function destRoadNode(ctx)
    if ctx.destRoadNode ~= nil then return ctx.destRoadNode end
    local found = false
    local d = ctx.dest
    local G = Graph()
    if d and d.inst ~= nil and d.x ~= nil and d.y ~= nil then
        local near = G:Nearest(d.inst, d.x, d.y, 0.05, 1)
        local hit = near and near[1]
        if hit and hit.key and hit.dist ~= nil and hit.dist <= 1e-3 then
            local _, nx, ny = G:NodePos(hit.key)
            if nx ~= nil and (nx - d.x) * (nx - d.x) + (ny - d.y) * (ny - d.y) <= 1e-4 then
                found = { key = hit.key, inst = d.inst }
            end
        end
    end
    ctx.destRoadNode = found
    return found
end



local function bridgesUnconnectedRoads(ctx, fromKey, x, y)
    local dest = destRoadNode(ctx)
    if not dest then return false end
    local key = fromKey
    if not key or key <= 0 then
        local d = ctx.dest
        if not d or d.inst == nil then return false end
        local near = Graph():Nearest(d.inst, x, y, 0.05, 1)
        local hit = near and near[1]
        if not hit or not hit.key or hit.dist == nil or hit.dist > 1e-3 then return false end
        local _, nx, ny = Graph():NodePos(hit.key)
        if nx == nil or (nx - x) * (nx - x) + (ny - y) * (ny - y) > 1e-4 then return false end
        key = hit.key
    end
    if key == dest.key then return false end
    local pieces = roadPieces(Graph(), dest.inst)
    if not pieces then return false end
    local base = dest.inst * KEY_BASE
    local si, di = key - base, dest.key - base
    local rs, rd = Router._roadRoot(pieces, si), Router._roadRoot(pieces, di)
    if rs == rd then return false end
    local a = Router._roadLinesFor(pieces, rs)
    if not a then return false end
    local b = Router._roadLinesFor(pieces, rd)
    if not b then return false end
    for lk in pairs(a) do
        if b[lk] then return true end
    end
    return false
end






function Router._lineInto(ctx, fromKey, inst, x, y, fromZ, testZ, d, anyRoads)

    if ctx.destEnclosed or Router._enclosed(ctx, fromKey) then return nil end



    if Router._swimRefused(inst, x, y, ctx.dest.x, ctx.dest.y, false) then return nil end

    if not anyRoads and bridgesUnconnectedRoads(ctx, fromKey, x, y) then return nil end
    local inside = FGPS.Data and FGPS.Data.insideMaps
    local extra = (inside and inst ~= nil and inside[inst]) and Router.ON_FOOT or straightExtra(fromKey)
    local honest, chargeBase = straightCost(ctx, d, inst, x, y, ctx.dest.x, ctx.dest.y, extra)
    if not honest then return nil end
    local destZ = destHeightFrom(ctx, fromZ)
    local hard, sparse = cutsObstacle(inst, x, y, ctx.dest.x, ctx.dest.y, ctx.cityTrip, testZ, destTestHeightFrom(ctx, testZ))
    if hard then return nil end
    chargeBase = chargeBase * sparseFactor(sparse)
    if ctx.guarded then
        local C = Cost()
        chargeBase = chargeBase * C.GuardedFactor((C.GuardedShare(ctx.guarded, inst, x, y, ctx.dest.x, ctx.dest.y)))
    end
    local charged = chargeBase * straightRisk(d)
    if fromZ then charged = charged + climbCharge(ctx, d, fromZ, destZ, ctx.destStacked) end
    return honest, charged
end



function Router._judgeLine(ctx, fromKey, g, inst, x, y, fromZ, testZ, d)
    local honest, charged = Router._lineInto(ctx, fromKey, inst, x, y, fromZ, testZ, d)

    if honest then relax(ctx, ctx.destKey or DEST, g + charged, fromKey, KIND_ATTACH, d, honest, 0, "ground", nil, VIA_DIRECT) end
end







Router.LAZY_LINES = true
Router.LINE_BASE = -2 ^ 39
Router._lines = { n = 0, nu = 0, from = {}, g = {}, f = {}, x = {}, y = {}, z = {}, zt = {}, d = {}, goal = {}, hs = {}, u = {}, ug = {} }



function Router._popLine(ctx, key)
    local q = Router._lines
    local j = Router.LINE_BASE - key
    if q.goal[j] then return Router._goalLine(ctx, j) end
    local known = Router._gAt(DEST)
    if known and q.f[j] >= known then return false end
    Router._judgeLine(ctx, q.from[j], q.g[j], ctx.dest.inst, q.x[j], q.y[j], q.z[j] or nil, q.zt[j] or nil, q.d[j])
    return true
end



function Router._goalLine(ctx, j)
    local q = Router._lines
    local gi = q.goal[j]
    local goal = ctx.goals[gi]
    if q.u[j] then
        q.u[j] = nil
        if not closed[goal.key] then q.nu, q.ug[gi] = q.nu - 1, q.ug[gi] - 1 end
    end
    if q.hs[j] == false or closed[goal.key] then return false end
    q.hs[j] = false
    local known = Router._gAt(goal.key)
    if known and q.f[j] >= known then return false end
    Router._bindGoal(ctx, goal)
    Router._judgeLine(ctx, q.from[j], q.g[j], goal.dest.inst, q.x[j], q.y[j], q.z[j] or nil, q.zt[j] or nil, q.d[j])
    Router._unbindGoal(ctx, goal)
    return true
end


function Router._judgeUnderLines(ctx)
    local q, list = Router._lines, {}
    for i = 1, heapSize do
        local key = heapKeys[i]
        if key <= Router.LINE_BASE and key > BOARD_BASE then
            local j = Router.LINE_BASE - key
            if q.goal[j] and q.u[j] then list[#list + 1] = j end
        end
    end

    for _, j in ipairs(list) do
        if searchOwner ~= ctx then return end
        Router._goalLine(ctx, j)
    end
end




local function relaxDirect(ctx, fromKey, g, inst, x, y, fromZ, testZ)

    if ctx ~= searchOwner then return end
    if ctx.goals then return Router._goalsDirect(ctx, fromKey, g, inst, x, y, fromZ, testZ) end
    if closed[DEST] or inst ~= ctx.dest.inst then return end
    local d = Coords().Distance(x, y, ctx.dest.x, ctx.dest.y)
    if d > ctx.maxStraight or d > (Router._lineReach(inst) or d) then return end








    local least = g + d * ctx.straightRate * Cost().ChordFactor(KIND_ATTACH, d) * straightRisk(d)
    local known = Router._gAt(DEST)
    if known and least >= known then return end






    if Router.LAZY_LINES and not ctx.maxSeconds then
        local q = Router._lines
        local j = q.n + 1
        q.n = j
        q.from[j], q.g[j], q.f[j], q.x[j], q.y[j], q.d[j] = fromKey, g, least, x, y, d
        q.z[j], q.zt[j], q.goal[j] = fromZ or false, testZ or false, false
        heapPush(Router.LINE_BASE - j, least)
        return
    end
    Router._judgeLine(ctx, fromKey, g, inst, x, y, fromZ, testZ, d)
end



local function relaxAttachList(ctx, fromKey, g, list, via, fromZ)
    if not list then return end
    local src, vx, vy = ctx.vpos[fromKey], nil, nil
    if src then
        vx, vy = src.x, src.y
    elseif ctx.guarded then
        local _
        _, vx, vy = Graph():NodePos(fromKey)
    end
    for nodeKey, cand in pairs(list) do
        if not closed[nodeKey] and nodeKey ~= fromKey then
            local isStacked = (fromKey == ORIGIN and (ctx.originStacked or cand.stacked)) or nil
            local secs, yards, charged = attachCost(ctx, cand, nodeKey, fromZ, isStacked, vx, vy)
            if secs then relax(ctx, nodeKey, g + charged, fromKey, KIND_ATTACH, yards, secs, 0, "ground", nil, via) end
        end
    end
end

local attachFor







local function expandBoarding(ctx, key)
    local G = Graph()
    local hub = BOARD_BASE - key
    local z = G:NodeHeight(hub)
    local zt = testHeightOf(ctx, key, z)
    local _, g, mode, parent = Router._slotMode(key)
    cur.parent = parent
    cur.ctx, cur.key, cur.node, cur.g, cur.mode, cur.boarding = ctx, key, hub, g, mode, true
    cur.z, cur.zt, cur.boardOnly = z, zt, nil
    cur.indoor, cur.C, cur.G = indoorNode(hub), Cost(), G
    cur.aboard, cur.aboardFrom = nil, nil
    cur.guardedNear = true
    G:Neighbors(hub, visit, closed)

    if ctx ~= searchOwner then return end
    cur.boarding = nil
    local inst, x, y = G:NodePos(hub)
    if ctx.goals then
        local goals = ctx.goals
        for i = 1, #goals do
            local dest = goals[i].dest
            if x and inst == dest.inst and Coords().Distance(x, y, dest.x, dest.y) <= G.ATTACH_VERIFIED_RADIUS then
                relaxDirect(ctx, key, g, inst, x, y, z, zt)
                break
            end
        end
    elseif x and inst == ctx.dest.inst and Coords().Distance(x, y, ctx.dest.x, ctx.dest.y) <= G.ATTACH_VERIFIED_RADIUS then
        relaxDirect(ctx, key, g, inst, x, y, z, zt)
    end
end

local function expand(ctx, key)
    if key <= BOARD_BASE then return expandBoarding(ctx, key) end
    local _, g, mode, parent = Router._slotMode(key)
    cur.parent = parent
    cur.ctx, cur.key, cur.node, cur.g, cur.mode, cur.boarding = ctx, key, key, g, mode, nil
    local C, G = Cost(), Graph()
    cur.C, cur.G = C, G


    local z = heightOf(ctx, key)
    local zt = testHeightOf(ctx, key, z)
    cur.z, cur.zt, cur.boardOnly = z, zt, nil
    if key == ORIGIN or key <= TELE_BASE then
        local list = (key == ORIGIN) and ctx.originAttach or ctx.teleAttach[key]
        local src = ctx.vpos[key]
        relaxAttachList(ctx, key, g, list, VIA_ATTACH, z)
        if src and ctx.maxStraight > 0 then
            relaxDirect(ctx, key, g, src.inst, src.x, src.y, z, zt)




            local boardOnly = vettedInst(ctx, src.inst)
            local hubs = Router._enclosed(ctx, key) and {} or G:Hubs(src.inst)
            for i = 1, #hubs do
                local hubKey = hubs[i]
                local target = boardOnly and BOARD_BASE - hubKey or hubKey
                if not closed[target] and hubUsable(ctx, hubKey) and not Router._enclosed(ctx, hubKey) then
                    local _, hx, hy = G:NodePos(hubKey)
                    local d = Coords().Distance(src.x, src.y, hx, hy)
                    if d <= ctx.maxStraight then
                        local stop = isTransportStop(G:NodeFlags(hubKey))
                        local honest, chargeBase = hubStretchCost(ctx, d, src.inst, src.x, src.y, hx, hy, stop, straightExtra(hubKey))
                        local hard, sparse = false, false
                        if honest then
                            hard, sparse = cutsObstacle(src.inst, src.x, src.y, hx, hy, ctx.cityTrip, zt, G:NodeHeightGuess(hubKey), dockAt(hubKey))
                        end
                        if honest and not hard then
                            if ctx.guarded then
                                chargeBase = chargeBase * C.GuardedFactor((C.GuardedShare(ctx.guarded, src.inst, src.x, src.y, hx, hy)))
                            end
                            local charged = chargeBase * sparseFactor(sparse) * straightRisk(d)
                            if z then
                                local stackedHub = (ctx.goalHubs and ctx.goalHubs[hubKey]) or (hubKey == ctx.destHubKey and ctx.destStacked)
                                charged = charged + climbCharge(ctx, d, z, G:NodeHeight(hubKey), stackedHub)
                            end
                            relax(ctx, target, g + charged, key, KIND_ATTACH, d, honest, 0, "ground", nil, VIA_DIRECT)
                        end
                    end
                end
            end
        end
        if key == ORIGIN then
            for teleKey, tele in pairs(ctx.teleports) do

                local penalty = C.TransferPenalty(ctx.ride)
                relax(ctx, teleKey, g + tele.seconds + penalty, ORIGIN, tele.kind, 0, tele.seconds, C.TransferPenalty(), tele.mode, tele.option.id, nil)
            end
        end
        return
    end


    local _, indoor, stacked = G:NodePlace(key)
    local inside = FGPS.Data and FGPS.Data.insideMaps
    cur.indoor = indoor or (inside ~= nil and inside[(G:Split(key))] ~= nil)
    cur.guardedNear = nil
    if ctx.guarded then
        local ginst, gx, gy = G:NodePos(key)
        cur.guardedNear = C.GuardedNear(ctx.guarded, ginst, gx, gy)
    end

    cur.aboard, cur.aboardFrom = nil, nil
    local slot = slotOf[key]
    if slot and (packArr[slot] or 0) % 256 == 9 and tidArr[slot] then
        local from = parent and (parent <= BOARD_BASE and BOARD_BASE - parent or parent)
        local fromTid, fromStop = G:NodeTransport(from)
        if fromTid == tidArr[slot] then cur.aboard, cur.aboardFrom = fromTid, fromStop end
    end
    G:Neighbors(key, visit, closed)
    if ctx.goals then
        Router._goalAttach(ctx, key, g)
    else
        local cand = ctx.destAttach[key]
        if cand and not closed[DEST] then
            local secs, yards, charged = attachCost(ctx, cand, key, destHeightFrom(ctx, cand.footZ), ctx.destStacked, ctx.dest.x, ctx.dest.y)
            if secs then relax(ctx, DEST, g + charged, key, KIND_ATTACH, yards, secs, 0, "ground", nil, VIA_ATTACH) end
        end
    end
    local inst, x, y
    if ctx.maxStraight > 0 then
        inst, x, y = G:NodePos(key)
        if x then
            relaxDirect(ctx, key, g, inst, x, y, z, zt)

            if ctx ~= searchOwner then return end
            local vetted = vettedInst(ctx, inst)
            if ctx.hubReach > 0 and not (indoor or stacked or Router._onHazardPiece(key)) then
                cur.boardOnly = vetted or nil


                local cells = ctx.hubCells[inst]
                if cells == nil then
                    cells = G:HubCells(inst, function(hubKey, flags)
                        return hubUsable(ctx, hubKey, flags) and not Router._enclosed(ctx, hubKey)
                    end)
                    ctx.hubCells[inst] = cells
                end
                G:HubsNear(inst, x, y, ctx.hubReach, hubVisit, cells)
            end
        end
    end





    if G.IsHubFlags(G:NodeFlags(key)) then
        if not x then inst, x, y = G:NodePos(key) end
        if x and not (vettedInst(ctx, inst) and cur.mode == "ground") then
            local list = ctx.hubAttach[key]
            if list == nil then

                list = attachFor(ctx, { inst = inst, x = x, y = y, z = zt }, false, true) or false
                ctx.hubAttach[key] = list
            end
            if list then relaxAttachList(ctx, key, g, list, VIA_HUB_ATTACH, z) end
        end
    end
end











local function search(ctx)


    local S = Scheduler()
    if S.current and S.current.cancelled then return nil, "CANCELLED" end
    resetSearch()
    ctx.rf = {}
    ctx.ground = Cost().GroundSpeed(ctx.access)
    Router._setGuarded(ctx)
    ctx.task = S.current
    searchOwner = ctx
    touchedKeys = 1
    slotOf[ORIGIN] = 1
    gArr[1] = 0
    fromArr[1] = false
    yardsArr[1], secArr[1], penArr[1] = 0, 0, 0
    local expansions, judged = 0, 0
    local yieldEvery, maxExpansions, maxSeconds = Router.YIELD_EVERY, Router.MAX_EXPANSIONS, ctx.maxSeconds
    local originUnder = (maxSeconds and maxSeconds >= 0) and 1 or 0
    packArr[1] = 256 + originUnder * 32768
    if maxSeconds then honestArr[1] = 0 end
    if originUnder == 1 then underCount = 1 end
    heapPush(ORIGIN, heuristic(ctx, ORIGIN))
    if not S.Yield() or searchOwner ~= ctx then
        ctx.expansions = expansions
        return nil, "CANCELLED"
    end
    while heapSize > 0 do


        if searchOwner ~= ctx then break end


        if maxSeconds and underCount == 0 and Router._lines.nu > 0 and ctx.goalOpen then
            Router._judgeUnderLines(ctx)
            if searchOwner ~= ctx then break end
        end
        if maxSeconds and underCount == 0 and Router._lines.nu == 0 then



            if ctx.goalLimit and maxSeconds < ctx.goalCeiling then

                local left = Router._goalsLeftOut(ctx)
                if searchOwner ~= ctx then break end
                if left then
                    maxSeconds = ctx.goalCeiling
                    ctx.maxSeconds, ctx.goalLimit = maxSeconds, nil
                    Router._recountUnder(ctx)
                else
                    ctx.goalCut = maxSeconds
                end
            end
            if underCount == 0 and Router._lines.nu == 0 then
                ctx.expansions = expansions
                return nil, "BOUND"
            end
        end
        local key = heapPop()
        if key <= Router.LINE_BASE and key > BOARD_BASE then


            if Router._popLine(ctx, key) then
                judged = judged + 1
                if judged % yieldEvery == 0 and (not S.Yield() or searchOwner ~= ctx) then
                    ctx.expansions = expansions
                    return nil, "CANCELLED"
                end
            end
        elseif not closed[key] then
            closed[key] = true
            local openSlot = slotOf[key]
            if maxSeconds and openSlot then
                local packed = packArr[openSlot] or 0
                if floor(packed / 32768) % 2 == 1 then
                    packArr[openSlot] = packed - 32768
                    underCount = underCount - 1
                end
            end
            if ctx.goalSet and ctx.goalSet[key] then


                local q, gi = Router._lines, ctx.goalSet[key].index
                local gone = gi and q.ug[gi]
                if gone and gone > 0 then q.nu, q.ug[gi] = q.nu - gone, 0 end
                if Router._closeGoal(ctx, key) then
                    ctx.expansions = expansions
                    return true
                end
                local tighter = ctx.goalLimit and Router._goalBound(ctx)
                if tighter and tighter < maxSeconds then
                    maxSeconds = tighter
                    ctx.maxSeconds, ctx.goalOpen = tighter, true
                    Router._recountUnder(ctx)
                end
            elseif key == DEST then
                ctx.expansions = expansions
                local destSlot = slotOf[DEST]
                if maxSeconds and destSlot and honestArr[destSlot] > maxSeconds then return nil, "BOUND" end
                return true
            else
                expansions = expansions + 1



                if expansions % yieldEvery == 0 and (not S.Yield() or searchOwner ~= ctx) then
                    ctx.expansions = expansions
                    return nil, "CANCELLED"
                end
                if expansions > maxExpansions then
                    ctx.expansions = expansions
                    return nil, "CAP"
                end
                expand(ctx, key)
            end
        end
    end
    ctx.expansions = expansions
    if searchOwner ~= ctx then return nil, "CANCELLED" end
    return nil, "EXHAUSTED"
end


local function nodeOf(key)
    if key <= BOARD_BASE then return BOARD_BASE - key end
    return key
end



local function collectEdges()
    local edges = {}
    local key = DEST
    local guard = 0
    while key ~= ORIGIN do
        local from, kind, yards, seconds, penalty, mode, tid, via = Router._edgeOf(key)
        if from == nil then return nil end
        edges[#edges + 1] = { from = nodeOf(from), to = nodeOf(key), kind = kind, yards = yards, seconds = seconds,
                              penalty = penalty, mode = mode, transportID = tid, via = via }
        key = from
        guard = guard + 1
        if guard > 1000000 then return nil end
    end
    local n = #edges
    for i = 1, floor(n / 2) do edges[i], edges[n - i + 1] = edges[n - i + 1], edges[i] end
    return edges
end




local UNVERIFIED = { [3] = true, [14] = true, [KIND_MESH] = true }




local KIND_STREET = 16


local KIND_TERRAIN_ROAD, KIND_TERRAIN_GRID = 18, 19
local ZERO_YARDS = 0.01




local function pointFlags(key)
    local f = Graph():NodeFlags(key)
    return f and f % 256
end

local function flagsOf(ctx, key)
    local F = Route().FLAGS
    if key == ORIGIN then return F.ORIGIN end
    if key == DEST then return F.STOP end
    if key <= TELE_BASE then return F.TELEPORT end
    return pointFlags(key)
end

local function newWalk(ctx, fromKey)
    local inst, x, y = posOf(ctx, fromKey)
    local z
    if fromKey >= 0 then
        z = Router._groundPointZ(fromKey)
    elseif fromKey == ORIGIN and type(ctx.origin.z) == "number" then
        z = ctx.origin.z
    end
    return { kind = "walk", inst = inst, points = { { x = x, y = y, z = z, f = flagsOf(ctx, fromKey), node = fromKey >= 0 and fromKey or nil } },
             yards = 0, seconds = 0,
             verifiedYards = 0, unverifiedYards = 0, roadYards = 0, fromKey = fromKey >= 0 and fromKey or nil }
end









local function noteClimb(leg, point, yards, zFrom, zTo, guessed, stacked)
    if not zFrom or not zTo then return end
    local climb = floor(zTo - zFrom + 0.5)
    if point then
        point.climb = climb
        if guessed then point.climbGuessed = true end
    end
    if climbDetour(yards, zFrom, zTo, stacked) <= 0 then return end
    if point then point.steep = true end
    if not leg.steepClimb or abs(climb) > abs(leg.steepClimb) then
        leg.steepClimb, leg.climbGuessed = climb, guessed or nil
    end
end




local function addPoint(leg, x, y, f, kind, yards, seconds, zFrom, zTo, guessed, stacked)
    local point = { x = x, y = y, f = f or 0, k = kind }



    if type(zTo) == "number" and not guessed then point.z = zTo end
    leg.points[#leg.points + 1] = point
    if kind == KIND_ATTACH or kind == KIND_CONNECTOR then noteClimb(leg, point, yards, zFrom, zTo, guessed, stacked) end
    leg.yards = leg.yards + yards
    leg.seconds = leg.seconds + seconds
    if UNVERIFIED[kind] then
        leg.unverifiedYards = leg.unverifiedYards + yards
    elseif kind == KIND_ROAD then
        leg.roadYards = (leg.roadYards or 0) + yards
    elseif kind == KIND_STREET then
        leg.streetYards = (leg.streetYards or 0) + yards
    elseif kind == KIND_TERRAIN_ROAD then
        leg.terrainRoadYards = (leg.terrainRoadYards or 0) + yards
    elseif kind == KIND_TERRAIN_GRID then
        leg.terrainGroundYards = (leg.terrainGroundYards or 0) + yards
    elseif kind == KIND_SURFACE then

        leg.surfaceYards = (leg.surfaceYards or 0) + yards
    elseif kind == KIND_SURFACE_SWIM then
        leg.surfaceSwimYards = (leg.surfaceSwimYards or 0) + yards
    else
        leg.verifiedYards = leg.verifiedYards + yards
    end
end








function Router._tagPoint(point, key, fromKey, kind)
    if not point or type(key) ~= "number" or key < 0 then return end
    local G = Graph()
    local gz = Router._groundPointZ(key, kind)
    if point.z == nil or (gz ~= nil and gz ~= G:NodeHeight(key)) then
        point.z = gz
    end
    if not G:IsSurfaceNode(key) then return end
    local name, indoor, stacked, door = G:NodePlace(key)
    if name then point.room = name end
    if indoor then point.indoor = true end
    if stacked then point.stacked = true end
    if door then point.door = true end
    if kind == KIND_SURFACE and type(fromKey) == "number" and fromKey >= 0 then
        local form = G:ClimbForm(fromKey, key)
        if form then point.climbForm = form end
    end
end






function Router._shapeTags(fromKey, toKey, ax, ay, mids, bx, by, kind)
    if fromKey < 0 or toKey < 0 then return nil end
    local G = Graph()
    local surface = G:IsSurfaceNode(fromKey) and G:IsSurfaceNode(toKey)
    local zA, zB = Router._groundPointZ(fromKey, kind), Router._groundPointZ(toKey, kind)
    if not surface and not (type(zA) == "number" and type(zB) == "number") then return nil end
    local tags = {}
    if surface then
        local nameA, indoorA, stackedA = G:NodePlace(fromKey)
        local nameB, indoorB, stackedB = G:NodePlace(toKey)


        tags.room = nameA ~= nil and nameA == nameB and nameA or nil
        tags.indoor = (indoorA and indoorB) and true or nil
        tags.stacked = (stackedA and stackedB) and true or nil
        tags.climbForm = G:ClimbForm(fromKey, toKey)
    end
    if type(zA) == "number" and type(zB) == "number" then
        local along, total = {}, 0
        local px, py = ax, ay
        for i = 1, #mids do
            total = total + Coords().Distance(px, py, mids[i].x, mids[i].y)
            along[i] = total
            px, py = mids[i].x, mids[i].y
        end
        total = total + Coords().Distance(px, py, bx, by)
        tags.z = {}
        for i = 1, #mids do tags.z[i] = total > 0 and zA + (zB - zA) * along[i] / total or zA end
    end
    return tags
end




local function labelClimb(leg)
    if leg.steepClimb then
        leg.steep = true
        local yards = abs(leg.steepClimb)
        local up = leg.steepClimb > 0
        if leg.climbGuessed then
            if up then
                leg.climbNote = string.format(L["No road nearby leads up here: the way on may be about %d yd above you."], yards)
            else
                leg.climbNote = string.format(L["No road nearby leads down here: the way on may be about %d yd below you."], yards)
            end
        elseif up then
            leg.climbNote = string.format(L["No road nearby leads up here: the way on is about %d yd above the direct line."], yards)
        else
            leg.climbNote = string.format(L["No road nearby leads down here: the way on is about %d yd below the direct line."], yards)
        end
    end
end










local function finishWalk(leg)
    local R = Route()
    local pts = leg.points



    local stroke = R.Stroke
    local straightYards, connectorYards, meshYards = 0, 0, 0
    for i = 2, #pts do
        local k = pts[i].k
        if k == KIND_ATTACH or k == 3 or k == KIND_MESH then
            local dx, dy = pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y
            local d = sqrt(dx * dx + dy * dy)
            if k == 3 then connectorYards = connectorYards + d
            elseif k == KIND_MESH then meshYards = meshYards + d
            else straightYards = straightYards + d end
        end
        if i < #pts then
            if stroke(k) ~= stroke(pts[i + 1].k) then
                pts[i].f = R.AddFlag(pts[i].f, R.FLAGS.BOUNDARY)
            end
        end
    end
    leg.unverified = leg.unverifiedYards > 0
    leg.straightYards, leg.connectorYards, leg.meshYards = straightYards, connectorYards, meshYards
    if leg.unverifiedYards > 0 and leg.verifiedYards < ZERO_YARDS and (leg.roadYards or 0) < ZERO_YARDS
        and (leg.streetYards or 0) < ZERO_YARDS and connectorYards < ZERO_YARDS and meshYards < ZERO_YARDS
        and (leg.terrainRoadYards or 0) < ZERO_YARDS and (leg.terrainGroundYards or 0) < ZERO_YARDS
        and (leg.surfaceYards or 0) < ZERO_YARDS and (leg.surfaceSwimYards or 0) < ZERO_YARDS then
        leg.straight = true
        leg.label = L["Open ground"]
    end
    labelClimb(leg)
    return leg
end



local function mergeLastFlags(leg, extra)
    local R = Route()
    local last = leg.points[#leg.points]
    local bit = 1
    while bit <= 4096 do
        if R.HasFlag(extra, bit) then last.f = R.AddFlag(last.f, bit) end
        bit = bit * 2
    end
end



function Router._noteHazard(leg, liquid, yards)
    if not liquid then return end
    leg.hazardYards = leg.hazardYards or {}
    leg.hazardYards[liquid] = (leg.hazardYards[liquid] or 0) + yards
end


local function addAttach(ctx, leg, cand, edge, toVirtual)
    local G = Graph()
    local total = edge.yards
    local attachYards = cand and (cand.attachYards or cand.dist) or total
    local segYards = cand and cand.segYards or 0
    local share = total > 0 and (edge.seconds / total) or 0



    local zFrom, zTo, guessFrom, guessTo
    if toVirtual then
        if cand then zFrom = cand.footZ else zFrom, guessFrom = heightOf(ctx, edge.from) end
        if edge.to == DEST then zTo, guessTo = destHeightFrom(ctx, zFrom) else zTo, guessTo = heightOf(ctx, edge.to) end
    else
        zFrom, guessFrom = heightOf(ctx, edge.from)
        if cand then zTo = cand.footZ else zTo, guessTo = heightOf(ctx, edge.to) end
    end
    local guessed = guessFrom or guessTo or nil

    local stacked = toVirtual and edge.to == DEST and ctx.destStacked or nil


    local hazard = (cand and segYards > 0 and cand.segKind == KIND_SURFACE_SWIM and cand.otherKey)
        and G:HazardCrossing(toVirtual and edge.from or edge.to, cand.otherKey) or nil
    if hazard then Router._noteHazard(leg, hazard, segYards) end
    if toVirtual then
        local dinst, dx, dy = posOf(ctx, edge.to)
        if cand and segYards > 0 then
            if cand.shaped and cand.otherKey then
                Router._emitAttachShape(leg, cand, edge.from, cand.otherKey, true, hazard)
            end
            addPoint(leg, cand.fx, cand.fy, 0, cand.segKind, segYards, segYards * share)
            local foot = leg.points[#leg.points]
            foot.hazard = hazard
            local fz = Router._candGroundFootZ(cand, edge.from)
            if fz ~= nil then foot.z = fz end
        end
        if attachYards < ZERO_YARDS then


            local last = leg.points[#leg.points]
            if last then last.x, last.y = dx, dy end
            mergeLastFlags(leg, flagsOf(ctx, edge.to))
            noteClimb(leg, nil, 0, zFrom, zTo, guessed, stacked)
        else
            addPoint(leg, dx, dy, flagsOf(ctx, edge.to), KIND_ATTACH, attachYards, attachYards * share, zFrom, zTo, guessed, stacked)
        end
        leg.toInst = dinst ~= leg.inst and dinst or nil
    else
        local _, nx, ny = G:NodePos(edge.to)
        if cand and segYards > 0 then
            if attachYards >= ZERO_YARDS then
                addPoint(leg, cand.fx, cand.fy, 0, KIND_ATTACH, attachYards, attachYards * share, zFrom, zTo, guessed)


                local foot = leg.points[#leg.points]
                local fz = Router._candGroundFootZ(cand, edge.to)
                if fz ~= nil then foot.z = fz end
                if edge.from == ORIGIN and #leg.points == 2 then
                    leg._corridorAttach = {
                        attachYards = attachYards, segKind = cand.segKind,
                        otherKey = cand.otherKey, toKey = edge.to,
                        footZ = fz or zTo, steep = foot.steep, stacked = cand.stacked,
                    }
                end
            else
                noteClimb(leg, nil, 0, zFrom, zTo, guessed)
            end
            if cand.shaped and cand.otherKey then
                Router._emitAttachShape(leg, cand, cand.otherKey, edge.to, false, hazard)
            end
            addPoint(leg, nx, ny, pointFlags(edge.to), cand.segKind, segYards, segYards * share)
            leg.points[#leg.points].hazard = hazard
        elseif attachYards < ZERO_YARDS then
            mergeLastFlags(leg, pointFlags(edge.to))
            noteClimb(leg, nil, 0, zFrom, zTo, guessed)
        else
            addPoint(leg, nx, ny, pointFlags(edge.to), KIND_ATTACH, attachYards, attachYards * share, zFrom, zTo, guessed)
        end
    end
end

local function taxiName(taxiID)
    local nodes = FGPS.Data and FGPS.Data.taxi and FGPS.Data.taxi.nodes
    local node = nodes and nodes[taxiID]
    return node and node.name or (L["flight point"] .. " " .. tostring(taxiID))
end


local function taxiPathPoints(from, to)
    local taxi = FGPS.Data and FGPS.Data.taxi
    if not taxi or not taxi.paths then return nil end
    local candidates = taxi.byNode and taxi.byNode[from]
    if candidates then
        for _, pathIndex in ipairs(candidates) do
            local p = taxi.paths[pathIndex]
            if p and p.from == from and p.to == to and type(p.points) == "table" and #p.points >= 2 then return p.points end
        end
    end
    return nil
end

local function convertPoints(raw, baseFlags, kind)
    local out = {}
    for i, pt in ipairs(raw) do
        local f = 0
        if i == 1 or i == #raw then f = baseFlags end
        out[i] = { x = pt.x or pt[1], y = pt.y or pt[2], f = f, k = i > 1 and kind or nil }
    end
    return out
end

local function polylineYards(points, split)
    local total = 0
    for i = 2, #points do
        if not (split and i - 1 == split) then
            local dx, dy = points[i].x - points[i - 1].x, points[i].y - points[i - 1].y
            total = total + sqrt(dx * dx + dy * dy)
        end
    end
    return total
end

local function buildTaxiLeg(ctx, edge)
    local G, F = Graph(), Route().FLAGS
    local inst, fx, fy = G:NodePos(edge.from)
    local _, tx, ty = G:NodePos(edge.to)
    local fromID, toID = G:NodeTaxiID(edge.from), G:NodeTaxiID(edge.to)
    local raw = fromID and toID and taxiPathPoints(fromID, toID)
    local points
    if raw then
        points = convertPoints(raw, F.TAXI, 8)
    else
        points = { { x = fx, y = fy, f = F.TAXI }, { x = tx, y = ty, f = F.TAXI, k = 8 } }
    end
    return { kind = "taxi", inst = inst, points = points, yards = edge.yards, seconds = edge.seconds + edge.penalty,
             penaltySeconds = edge.penalty, fromKey = edge.from, toKey = edge.to, taxiFrom = fromID, taxiTo = toID,
             hops = { toID }, label = string.format(L["Flight from %s to %s"], taxiName(fromID), taxiName(toID)),
             unverified = false, verifiedYards = 0, unverifiedYards = 0, roadYards = 0 }
end

local function extendTaxiLeg(leg, edge)
    local G, F = Graph(), Route().FLAGS
    local _, tx, ty = G:NodePos(edge.to)
    local toID = G:NodeTaxiID(edge.to)
    local raw = leg.taxiTo and toID and taxiPathPoints(leg.taxiTo, toID)
    if raw then
        local pts = convertPoints(raw, F.TAXI, 8)
        for i = 2, #pts do leg.points[#leg.points + 1] = pts[i] end
    else
        leg.points[#leg.points + 1] = { x = tx, y = ty, f = F.TAXI, k = 8 }
    end
    leg.yards = leg.yards + edge.yards
    leg.seconds = leg.seconds + edge.seconds + edge.penalty
    leg.penaltySeconds = leg.penaltySeconds + edge.penalty
    leg.toKey = edge.to
    leg.taxiTo = toID
    leg.hops[#leg.hops + 1] = toID
    leg.label = string.format(L["Flight from %s to %s"], taxiName(leg.taxiFrom), taxiName(toID))
end


local function buildTransportLeg(ctx, edge, prev)
    local G, R = Graph(), Route()
    local F = R.FLAGS
    local fromInst, fx, fy = G:NodePos(edge.from)
    local toInst, tx, ty = G:NodePos(edge.to)
    local records = FGPS.Data and FGPS.Data.transports
    local rec = edge.transportID and records and records[edge.transportID] or nil
    local _, fromStop = G:NodeTransport(edge.from)
    local _, toStop = G:NodeTransport(edge.to)
    local baseFlag = edge.mode == "portal" and F.PORTAL or F.TRANSPORT
    local points, split, dataYards
    if rec and rec.legs and fromStop and toStop then
        for _, legRec in ipairs(rec.legs) do
            if legRec.from == fromStop and legRec.to == toStop and type(legRec.points) == "table" and #legRec.points >= 2 then
                points = convertPoints(legRec.points, baseFlag, edge.kind)
                split = legRec.split
                dataYards = legRec.yards
                break
            end
        end
    end
    if not points then
        points = { { x = fx, y = fy, f = baseFlag }, { x = tx, y = ty, f = baseFlag, k = edge.kind } }
        if fromInst ~= toInst then split = 1 end
    end



    local yards = edge.yards
    if dataYards and dataYards > 0 then yards = dataYards end
    if not yards or yards == 0 then yards = dataYards or polylineYards(points, split) end





    local need
    if edge.kind == 7 then
        yards, split = 0, split or 1
        need = Router._linkNeed(edge.from, edge.to)
    elseif edge.kind == 11 then
        yards = 0
    end
    local stopFrom = rec and rec.stops and rec.stops[fromStop or 0] or nil
    local stopTo = rec and rec.stops and rec.stops[toStop or 0] or nil
    local wait, aboard = 0, nil
    if edge.kind == 9 then
        wait = Cost().ExpectedWait(rec and rec.period)

        if prev and prev.kind == 9 and prev.transportID == edge.transportID then
            local prevTid, cameFrom = G:NodeTransport(prev.from)
            local aboardRec, stop
            if prevTid == edge.transportID then aboardRec, stop = Router._aboardAt(edge.transportID, edge.from, edge.to, cameFrom) end
            if aboardRec then wait, aboard = Cost().AboardWait(aboardRec, stop), true end
        end
    elseif edge.kind == 10 then
        wait = Const.TRAM_WAIT
    end
    return { kind = edge.mode, inst = fromInst, toInst = toInst ~= fromInst and toInst or nil, points = points, split = split,
             yards = yards, seconds = edge.seconds + edge.penalty, penaltySeconds = edge.penalty, wait = wait, aboard = aboard,
             fromKey = edge.from, toKey = edge.to, transportID = edge.transportID, need = need,
             label = rec and rec.name or (edge.kind == 7 and Router._doorName(fromInst, fx, fy, toInst, tx, ty))
                 or R.LegLabel(edge.mode), stopFrom = stopFrom and stopFrom.name or nil,
             stopTo = stopTo and stopTo.name or nil, period = rec and rec.period or nil,


             stopFromIndex = fromStop, stopToIndex = toStop,
             unverified = rec and rec.unverified == true or false, verifiedYards = 0, unverifiedYards = 0, roadYards = 0 }
end

local function buildTeleportLeg(ctx, edge)
    local F = Route().FLAGS
    local tele = ctx.teleports[edge.to]
    local o, a = ctx.vpos[ORIGIN], ctx.vpos[edge.to]
    return { kind = edge.mode, inst = o.inst, toInst = a.inst ~= o.inst and a.inst or nil,
             points = { { x = o.x, y = o.y, f = F.ORIGIN }, { x = a.x, y = a.y, f = F.TELEPORT, k = edge.kind } }, split = 1,
             yards = 0, seconds = edge.seconds + edge.penalty, penaltySeconds = edge.penalty, wait = tele.wait,
             castSeconds = tele.option.castSeconds, option = tele.option, label = tele.option.name or tele.option.bindName or Route().LegLabel(edge.mode),
             unverified = false, verifiedYards = 0, unverifiedYards = 0, roadYards = 0 }
end




local STREET_SNAP_YARDS = 8
local STREET_SNAP_COS = 0.85

local function snapToStreet(inst, x1, y1, x2, y2)
    if not inCapital(inst, x1, y1) or not inCapital(inst, x2, y2) then return x2, y2 end
    local dx, dy = x2 - x1, y2 - y1
    local len = sqrt(dx * dx + dy * dy)
    if len < 2 then return x2, y2 end
    local G = Graph()
    local near = G:Nearest(inst, x2, y2, STREET_SNAP_YARDS + 40, 6)
    local bestD, bestX, bestY = STREET_SNAP_YARDS, nil, nil
    for i = 1, #near do
        G:Neighbors(near[i].key, function(nb, kind)
            if kind ~= KIND_STREET then return end
            local _, ax, ay = G:NodePos(near[i].key)
            local _, bx, by = G:NodePos(nb)
            if not ax or not bx then return end
            local sx, sy = bx - ax, by - ay
            local sl = sqrt(sx * sx + sy * sy)
            if sl < 2 then return end
            if abs(dx * sx + dy * sy) / (len * sl) < STREET_SNAP_COS then return end
            local t = ((x2 - ax) * sx + (y2 - ay) * sy) / (sl * sl)
            if t < 0 then t = 0 elseif t > 1 then t = 1 end
            local px, py = ax + sx * t, ay + sy * t
            local ddx, ddy = x2 - px, y2 - py
            local d = sqrt(ddx * ddx + ddy * ddy)
            if d >= bestD then return end


            local ndx, ndy = px - x1, py - y1
            local nlen = sqrt(ndx * ndx + ndy * ndy)
            if nlen < 2 or (dx * ndx + dy * ndy) / (len * nlen) < 0.94 then return end
            bestD, bestX, bestY = d, px, py
        end)
    end
    if bestX then return bestX, bestY end
    return x2, y2
end





function Router._emitAttachShape(leg, cand, fromNode, toNode, toVirtual, hazard)
    local G = Graph()
    local raw = G:EdgeShape(fromNode, toNode, cand.segKind)
    if not raw or #raw == 0 then return end

    local mids = {}
    for i = 1, #raw do
        local p = raw[i]
        mids[i] = { x = p.x, y = p.y }
    end
    local _, ax, ay = G:NodePos(fromNode)
    local _, bx, by = G:NodePos(toNode)
    if not ax or not bx then return end
    local D = Coords().Distance
    local along, fullLen = {}, 0
    local qx, qy = ax, ay
    for i = 1, #mids do
        fullLen = fullLen + D(qx, qy, mids[i].x, mids[i].y)
        along[i] = fullLen
        qx, qy = mids[i].x, mids[i].y
    end
    fullLen = fullLen + D(qx, qy, bx, by)
    local low, high
    if toVirtual then
        low, high = ZERO_YARDS, cand.segYards - ZERO_YARDS
    else
        low, high = fullLen - cand.segYards + ZERO_YARDS, fullLen - ZERO_YARDS
    end
    local shapeTags = Router._shapeTags(fromNode, toNode, ax, ay, mids, bx, by, cand.segKind)
    local prev = leg.points[#leg.points]
    local px, py = prev.x, prev.y
    local snap = cand.segKind == 2
    for i = 1, #mids do
        local s = along[i]
        if s > low and s < high then
            local p = mids[i]
            local sx, sy = p.x, p.y
            if snap then sx, sy = snapToStreet(leg.inst, px, py, sx, sy) end
            addPoint(leg, sx, sy, 0, cand.segKind, 0, 0)
            local point = leg.points[#leg.points]
            point.shape = true
            point.hazard = hazard
            if shapeTags then
                point.room, point.indoor, point.stacked = shapeTags.room, shapeTags.indoor, shapeTags.stacked
                point.climbForm, point.z = shapeTags.climbForm, shapeTags.z and shapeTags.z[i]
            end
            px, py = sx, sy
        end
    end
end




local PIER_MODES = { boat = true, zeppelin = true, ferry = true }
local KIND_PIER = 1

local function pierStop(edge, which)
    if not PIER_MODES[edge.mode] then return nil end
    local records = FGPS.Data and FGPS.Data.transports
    local rec = edge.transportID and records and records[edge.transportID] or nil
    if not rec or type(rec.stops) ~= "table" then return nil end
    local key = which == "to" and edge.to or edge.from
    local _, index = Graph():NodeTransport(key)
    local stop = index and rec.stops[index] or nil
    if type(stop) ~= "table" or type(stop.x) ~= "number" or type(stop.y) ~= "number" then return nil end
    return stop
end



local function pierYards(x1, y1, x2, y2, access)
    local yards = Coords().Distance(x1, y1, x2, y2)
    if not yards or yards <= 1 then return nil end
    local seconds = Cost().EdgeSeconds(KIND_PIER, yards, access)
    if not seconds then seconds = yards / (Const.RUN_SPEED or 7) end
    return yards, seconds
end




function Router._guessedDockStep(walk, yards)
    if not yards or yards <= 0 then return end
    walk.verifiedYards = walk.verifiedYards - yards
    if walk.verifiedYards < 0 then walk.verifiedYards = 0 end
    walk.unverifiedYards = walk.unverifiedYards + yards
    walk.dockYards = (walk.dockYards or 0) + yards
end

local function extendWalkToPier(walk, edge, which, access)
    local stop = pierStop(edge, which)
    if not stop or (stop.inst and walk.inst and stop.inst ~= walk.inst) then return end
    local last = walk.points[#walk.points]
    if not last then return end
    local yards, seconds = pierYards(last.x, last.y, stop.x, stop.y, access)
    if not yards then



        if last.k == KIND_ATTACH and inCapital(walk.inst, last.x, last.y) then
            last.k = KIND_PIER
            local prev = walk.points[#walk.points - 1]
            if prev then walk.dockYards = (walk.dockYards or 0) + Coords().Distance(prev.x, prev.y, last.x, last.y) end
        end
        return
    end
    addPoint(walk, stop.x, stop.y, 0, KIND_PIER, yards, seconds)
    Router._guessedDockStep(walk, yards)
end

local function startWalkAtPier(walk, edge, access)
    local stop = pierStop(edge, "to")
    if not stop or (stop.inst and walk.inst and stop.inst ~= walk.inst) then return end
    local first = walk.points[1]
    if not first then return end
    local yards, seconds = pierYards(stop.x, stop.y, first.x, first.y, access)
    if not yards then return end
    local hx, hy, hf = first.x, first.y, first.f
    first.x, first.y, first.f = stop.x, stop.y, 0
    addPoint(walk, hx, hy, hf, KIND_PIER, yards, seconds)


    local hub = walk.points[#walk.points]
    hub.z, hub.node, hub.room, hub.indoor, hub.stacked, hub.door = first.z, first.node, first.room, first.indoor, first.stacked, first.door
    first.z, first.node, first.room, first.indoor, first.stacked, first.door = nil, nil, nil, nil, nil, nil
    Router._guessedDockStep(walk, yards)
end



local CLOSER_ROAD_KINDS = { [1] = true, [2] = true, [17] = true, [18] = true }



local function closerRoadFoot(fromKey, dx, dy)
    local G, C = Graph(), Coords()
    local _, fx, fy = G:NodePos(fromKey)
    if not fx then return nil end
    local nodeDist = C.Distance(fx, fy, dx, dy)
    local best
    G:Neighbors(fromKey, function(nb, kind)
        if CLOSER_ROAD_KINDS[kind] then
            local _, nx, ny = G:NodePos(nb)
            if nx then
                local vx, vy = nx - fx, ny - fy
                local len2 = vx * vx + vy * vy
                if len2 > 0 then
                    local t = ((dx - fx) * vx + (dy - fy) * vy) / len2
                    if t > 0 and t < 1 then
                        local along = t * math.sqrt(len2)
                        local px, py = fx + t * vx, fy + t * vy
                        local hop = C.Distance(px, py, dx, dy)
                        if along >= 8 and hop <= nodeDist - 1 and (not best or hop < best.hop) then
                            best = { x = px, y = py, kind = kind, along = along, hop = hop }
                        end
                    end
                end
            end
        end
    end)
    return best
end


Router._CORRIDOR_ROAD_KINDS = {
    [1] = true, [2] = true, [4] = true, [6] = true, [12] = true,
    [16] = true, [17] = true, [18] = true, [22] = true,
}





function Router._smoothOriginCorridor(ctx, walk)
    local info = walk and walk._corridorAttach
    if walk then walk._corridorAttach = nil end
    if not info or info.steep or info.stacked or ctx.originStacked then return end
    local corridor = Const.ROAD_CORRIDOR_YARDS or 20
    if info.attachYards > corridor then return end
    if ctx.origin and ctx.origin.place and ctx.origin.place.indoor then return end
    local kinds = Router._CORRIDOR_ROAD_KINDS
    if not kinds[info.segKind] then return end
    local G, R, D = Graph(), Route(), Coords().Distance
    for _, key in ipairs({ info.otherKey, info.toKey }) do
        if type(key) == "number" and key >= 0 and G:IsSurfaceNode(key) then
            local _, indoor, stacked, door = G:NodePlace(key)
            if indoor or stacked or door then return end
        end
    end
    if info.segKind == KIND_SURFACE and type(info.otherKey) == "number" and type(info.toKey) == "number"
        and G:ClimbForm(info.otherKey, info.toKey) then
        return
    end
    local pts = walk.points
    if not pts or #pts < 3 then return end
    local p1, foot, p3 = pts[1], pts[2], pts[3]
    if foot.k ~= KIND_ATTACH or foot.indoor or foot.stacked or foot.door
        or p3.indoor or p3.stacked or p3.door or p3.climbForm or p3.steep then
        return
    end
    local footZ = type(foot.z) == "number" and foot.z or info.footZ
    local minForward = info.attachYards * 2.0
    if minForward < 12 then minForward = 12 end
    local maxNodeSpan = minForward * 1.5
    if maxNodeSpan < 45 then maxNodeSpan = 45 end
    local keep = 3
    local alongRoad = D(foot.x, foot.y, p3.x, p3.y)
    local slideU
    while alongRoad < minForward and keep < #pts do
        local prv, cur, nxt = pts[keep - 1], pts[keep], pts[keep + 1]
        if R.IsPreserved(cur) or cur.indoor or cur.stacked or cur.door or cur.climbForm or cur.steep
            or nxt.indoor or nxt.stacked or nxt.door or nxt.climbForm or not kinds[nxt.k] then
            break
        end
        if type(footZ) == "number"
            and ((type(cur.z) == "number" and abs(cur.z - footZ) > 5)
                or (type(nxt.z) == "number" and abs(nxt.z - footZ) > 5)) then
            break
        end
        local ax, ay = cur.x - prv.x, cur.y - prv.y
        local bx, by = nxt.x - cur.x, nxt.y - cur.y
        local al, bl = sqrt(ax * ax + ay * ay), sqrt(bx * bx + by * by)
        if al > 0.5 and bl > 0.5 and (ax * bx + ay * by) / (al * bl) < 0.866 then
            break
        end
        if bl <= 0.01 then
            keep = keep + 1
        elseif alongRoad + bl <= maxNodeSpan then
            alongRoad = alongRoad + bl
            keep = keep + 1
        else
            slideU = (minForward - alongRoad) / bl
            break
        end
    end
    local target = pts[keep]
    local tx, ty, tz = target.x, target.y, target.z
    local arcToTarget = alongRoad
    if slideU and slideU > 0 and slideU < 1 then
        local nxt = pts[keep + 1]
        tx = target.x + (nxt.x - target.x) * slideU
        ty = target.y + (nxt.y - target.y) * slideU
        arcToTarget = alongRoad + D(target.x, target.y, tx, ty)
        if type(target.z) == "number" and type(nxt.z) == "number" then
            tz = target.z + (nxt.z - target.z) * slideU
        end
    end
    if tz == nil and type(footZ) == "number" then
        local z0, arc0 = footZ, 0
        local arc = 0
        for i = 3, keep do
            arc = arc + D(pts[i - 1].x, pts[i - 1].y, pts[i].x, pts[i].y)
            if type(pts[i].z) == "number" then z0, arc0 = pts[i].z, arc end
        end
        local j, span = keep + 1, arcToTarget - arc0
        local px, py = tx, ty
        while j <= #pts and pts[j].z == nil and pts[j].shape do
            span = span + D(px, py, pts[j].x, pts[j].y)
            px, py = pts[j].x, pts[j].y
            j = j + 1
        end
        local jz = pts[j] and pts[j].z
        if type(jz) == "number" then
            span = span + D(px, py, pts[j].x, pts[j].y)
            tz = span > 0.01 and (z0 + (jz - z0) * ((arcToTarget - arc0) / span)) or z0
        else
            tz = z0
        end
    end
    if D(p1.x, p1.y, tx, ty) < ZERO_YARDS then return end
    local finalAlong = D(foot.x, foot.y, tx, ty)
    if finalAlong < 8 and keep < #pts then
        local nxt = pts[keep + 1]
        local mx, my = tx - p1.x, ty - p1.y
        local nx2, ny2 = nxt.x - tx, nxt.y - ty
        local ml, nl = sqrt(mx * mx + my * my), sqrt(nx2 * nx2 + ny2 * ny2)
        if ml <= 0.5 or nl <= 0.5 or (mx * nx2 + my * ny2) / (ml * nl) < 0.707 then
            return
        end
    end
    local z1 = p1.z or ctx.originZ or ctx.originZg
    local z2 = tz or (target.node and G:NodeHeightGuess(target.node)) or footZ
    if type(footZ) == "number" and type(z2) == "number" and abs(z2 - footZ) > 5 then return end
    if type(z1) == "number" and type(z2) == "number" and abs(z2 - z1) > 5 then return end
    if Router.judgeStraight(walk.inst, p1.x, p1.y, tx, ty, ctx.cityTrip, z1, z2).hard then return end
    if FGPS.Cost and FGPS.Cost.OverSwim and FGPS.Cost.OverSwim(walk.inst, p1.x, p1.y, tx, ty) then return end
    local prevNode = (type(info.otherKey) == "number" and info.otherKey >= 0) and info.otherKey or nil
    for i = 2, keep - 1 do
        if pts[i].node then prevNode = pts[i].node end
    end
    if slideU and slideU > 0 and slideU < 1 then
        target.x, target.y, target.z = tx, ty, tz
        target.node = nil
        target.shape = true
    else
        if target.z == nil and type(tz) == "number" then target.z = tz end
        if prevNode then target.corridorBefore = prevNode end
    end
    if finalAlong >= 8 then
        target.corridorX, target.corridorY = foot.x, foot.y
    end
    local shift = keep - 2
    local oldN = #pts
    for i = keep, oldN do pts[i - shift] = pts[i] end
    for i = oldN - shift + 1, oldN do pts[i] = nil end
end

do
    local WAY_NEIGHBOR_KINDS = {
        [1] = true, [2] = true, [4] = true, [6] = true,
        [12] = true, [16] = true, [17] = true, [18] = true,
    }

    function Router._smoothWalk(ctx, walk)
        local pts = walk and walk.points
        if not pts or #pts < 3 then return end
        local inst = walk.inst
        local inside = FGPS.Data and FGPS.Data.insideMaps
        if inside and inside[inst] then return end
        local G, C, R = Graph(), Cost(), Route()
        local highRes = ctx and ctx.access and ctx.access.highRes == true
        local checks, maxChecks = 0, highRes and 96 or 48

        local function hasOutdoorFloor(x, y, z)
            local hits = G:Nearest(inst, x, y, 18, 1, function(key)
                if not G:IsSurfaceNode(key) then return false end
                local _, indoor, stacked, door = G:NodePlace(key)
                return not (indoor or stacked or door)
            end, z)
            local hit = hits and hits[1]
            if not hit then return false end
            local hz = G:NodeHeight(hit.key) or G:NodeHeightGuess(hit.key)
            return hz == nil or abs(hz - z) <= 3.5
        end

        local beforeCum = R.Cumulative(walk).total
        R.SmoothLeg(walk, {
            highRes = highRes,
            isPinnedNode = function(key, p)
                if not G:IsSurfaceNode(key) then return true end
                if inCapital(inst, p.x, p.y) then return true end
                local hasWay = false
                G:Neighbors(key, function(_, kind)
                    if WAY_NEIGHBOR_KINDS[kind] then hasWay = true end
                end)
                return hasWay
            end,
            canShortcut = function(a, b, chord)
                if checks >= maxChecks then return false end
                checks = checks + 1
                local mx, my, mz = (a.x + b.x) * 0.5, (a.y + b.y) * 0.5, (a.z + b.z) * 0.5
                if not hasOutdoorFloor(mx, my, mz) then return false end
                if chord > 36 then
                    if not hasOutdoorFloor(a.x + (b.x - a.x) * 0.25, a.y + (b.y - a.y) * 0.25, a.z + (b.z - a.z) * 0.25) then
                        return false
                    end
                    if not hasOutdoorFloor(a.x + (b.x - a.x) * 0.75, a.y + (b.y - a.y) * 0.75, a.z + (b.z - a.z) * 0.75) then
                        return false
                    end
                end
                if Router._inBlockedLiquid(inst, mx, my) or Router._overHazardFloor(inst, a.x, a.y, b.x, b.y) then
                    return false
                end
                if C.OverSwim and C.OverSwim(inst, a.x, a.y, b.x, b.y) then return false end
                if C.OverBlocked and C.OverBlocked(inst, a.x, a.y, b.x, b.y) then return false end
                if ctx and ctx.guarded and C.GuardedShare(ctx.guarded, inst, a.x, a.y, b.x, b.y, a.z, b.z) > 0 then
                    return false
                end
                return not Router.judgeStraight(inst, a.x, a.y, b.x, b.y, ctx and ctx.cityTrip, a.z, b.z).hard
            end,
            canFillet = function(a, b)
                local mx, my = (a.x + b.x) * 0.5, (a.y + b.y) * 0.5
                if Router._inBlockedLiquid(inst, mx, my) or Router._overHazardFloor(inst, a.x, a.y, b.x, b.y) then
                    return false
                end
                if C.OverSwim and C.OverSwim(inst, a.x, a.y, b.x, b.y) then return false end
                if ctx and ctx.guarded and C.GuardedShare(ctx.guarded, inst, a.x, a.y, b.x, b.y, a.z, b.z) > 0 then
                    return false
                end
                return true
            end,
        })
        if walk._cum == nil then
            local afterCum = R.Cumulative(walk).total
            local delta = afterCum - beforeCum
            if walk.yards then
                walk.yards = walk.yards + delta
                if walk.yards < 0 then walk.yards = 0 end
            end
            if walk.surfaceYards and delta < 0 then
                walk.surfaceYards = walk.surfaceYards + delta
                if walk.surfaceYards < 0 then walk.surfaceYards = 0 end
            end
            if walk.seconds then
                local spd = (ctx and ctx.ground) or (C.GroundSpeed and C.GroundSpeed(ctx and ctx.access)) or (Const.RUN_SPEED or 7)
                if spd and spd > 0 then
                    walk.seconds = walk.seconds + delta / spd
                    if walk.seconds < 0 then walk.seconds = 0 end
                end
            end
        end
    end
end

local function buildLegs(ctx, edges)
    local legs = {}
    local walk
    local prev
    for _, e in ipairs(edges) do
        if e.mode == "ground" then
            if not walk then
                walk = newWalk(ctx, e.from)
                Router._tagPoint(walk.points[1], e.from)


                if prev and PIER_MODES[prev.mode] then startWalkAtPier(walk, prev, ctx.access) end
            end


            if e.from == ORIGIN or e.from <= TELE_BASE then
                if e.to == DEST then
                    addAttach(ctx, walk, nil, e, true)
                else
                    local list = (e.from == ORIGIN) and ctx.originAttach or ctx.teleAttach[e.from]
                    local cand = (e.via == VIA_ATTACH) and list and list[e.to] or nil
                    addAttach(ctx, walk, cand, e, false)
                end
            elseif e.to == DEST then
                addAttach(ctx, walk, (e.via == VIA_ATTACH) and ctx.destAttach[e.from] or nil, e, true)
            elseif e.via == VIA_HUB_ATTACH then
                local list = ctx.hubAttach[e.from]
                addAttach(ctx, walk, list and list[e.to] or nil, e, false)
            else
                local _, nx, ny = Graph():NodePos(e.to)
                if e.kind == KIND_ATTACH or e.kind == KIND_CONNECTOR then


                    local zFrom, zTo = Graph():NodeHeight(e.from), Graph():NodeHeight(e.to)


                    local drawKind = e.kind
                    if e.kind == KIND_CONNECTOR and dockAt(e.to) and zFrom and zTo
                        and math.abs(zTo - zFrom) <= Router.CLIMB_STEP_YARDS then


                        drawKind = KIND_PIER
                    end
                    local stacked = e.kind == KIND_ATTACH and e.to == ctx.destHubKey and ctx.destStacked or nil


                    local foot
                    if nx and ctx.dest and ctx.dest.x and Coords().Distance(nx, ny, ctx.dest.x, ctx.dest.y) <= 8 then
                        foot = closerRoadFoot(e.from, ctx.dest.x, ctx.dest.y)
                    end
                    if foot then
                        local secPer = (e.yards and e.yards > 0) and ((e.seconds or 0) / e.yards) or 0
                        addPoint(walk, foot.x, foot.y, 0, foot.kind, foot.along, secPer * foot.along)


                        addPoint(walk, nx, ny, pointFlags(e.to), drawKind, foot.hop, secPer * foot.hop)
                    else
                        addPoint(walk, nx, ny, pointFlags(e.to), drawKind, e.yards, e.seconds, zFrom, zTo, nil, stacked)
                    end
                    if drawKind ~= e.kind then Router._guessedDockStep(walk, foot and foot.hop or e.yards) end
                else
                    local mids = Graph():EdgeShape(e.from, e.to, e.kind)
                    local prev = walk.points[#walk.points]
                    local px, py = prev.x, prev.y
                    local snap = e.kind == 2
                    local shapeTags = mids and Router._shapeTags(e.from, e.to, px, py, mids, nx, ny, e.kind)


                    local hazard = e.kind == KIND_SURFACE_SWIM and Graph():HazardCrossing(e.from, e.to) or nil
                    if mids then
                        for i = 1, #mids do
                            local p = mids[i]
                            local sx, sy = p.x, p.y
                            if snap then sx, sy = snapToStreet(walk.inst, px, py, p.x, p.y) end
                            addPoint(walk, sx, sy, 0, e.kind, 0, 0)


                            local point = walk.points[#walk.points]
                            point.shape = true
                            point.hazard = hazard
                            if shapeTags then
                                point.room, point.indoor, point.stacked = shapeTags.room, shapeTags.indoor, shapeTags.stacked
                                point.climbForm, point.z = shapeTags.climbForm, shapeTags.z and shapeTags.z[i]
                            end
                            px, py = sx, sy
                        end
                    end
                    if snap then nx, ny = snapToStreet(walk.inst, px, py, nx, ny) end
                    addPoint(walk, nx, ny, pointFlags(e.to), e.kind, e.yards, e.seconds, nil, Graph():NodeHeight(e.to))
                    walk.points[#walk.points].hazard = hazard
                    Router._noteHazard(walk, hazard, e.yards)

                    if e.kind == KIND_ROAD and mids and #mids > 0 then
                        walk.roadShapedYards = (walk.roadShapedYards or 0) + e.yards
                    end
                end
            end
            walk.toKey = e.to >= 0 and e.to or nil

            if e.to >= 0 then walk.points[#walk.points].node = e.to end
            Router._tagPoint(walk.points[#walk.points], e.to, e.from, e.kind)
        else
            if walk then


                extendWalkToPier(walk, e, "from", ctx.access)
                Router._smoothOriginCorridor(ctx, walk)
                Router._smoothWalk(ctx, walk)
                legs[#legs + 1] = finishWalk(walk)
                walk = nil
            end
            if e.mode == "taxi" and prev and prev.mode == "taxi" and legs[#legs] and legs[#legs].kind == "taxi" then
                extendTaxiLeg(legs[#legs], e)
            elseif e.mode == "taxi" then
                legs[#legs + 1] = buildTaxiLeg(ctx, e)
            elseif e.mode == "hearth" or e.mode == "spell" then
                legs[#legs + 1] = buildTeleportLeg(ctx, e)
            else
                legs[#legs + 1] = buildTransportLeg(ctx, e, prev)
            end
        end
        prev = e
    end
    if walk then
        if walk.yards < ZERO_YARDS and #legs > 0 then

            local lastLeg = legs[#legs]
            mergeLastFlags(lastLeg, walk.points[#walk.points].f)
        else
            Router._smoothOriginCorridor(ctx, walk)
            Router._smoothWalk(ctx, walk)
            legs[#legs + 1] = finishWalk(walk)
        end
    end
    return legs
end

local function straightLeg(ctx)
    local C, F = Cost(), Route().FLAGS
    local o, d = ctx.origin, ctx.dest

    if o.inst == d.inst and bridgesUnconnectedRoads(ctx, nil, o.x, o.y) then return nil end


    local originZ = ctx.originZ or o.z
    local destZ, destGuessed = destHeightFrom(ctx, originZ)
    destZ = destZ or d.z
    local originTestZ = originZ or ctx.originZg
    local destTestZ = destTestHeightFrom(ctx, originTestZ) or d.z
    if o.inst == d.inst and cutsObstacle(o.inst, o.x, o.y, d.x, d.y, ctx.cityTrip, originTestZ, destTestZ) then return nil end
    local yards = Coords().Distance(o.x, o.y, d.x, d.y)
    local inside = FGPS.Data and FGPS.Data.insideMaps
    local legExtra = (inside and (inside[o.inst] or inside[d.inst])) and Router.ON_FOOT or nil
    local honest = straightCost(ctx, yards, o.inst, o.x, o.y, d.x, d.y, legExtra)
    if not honest then

        honest = C.EdgeSeconds(KIND_ATTACH, yards, ctx.access, nil, legExtra)
        if not honest then return nil end
    end
    local leg = { kind = "walk", inst = o.inst, points = { { x = o.x, y = o.y, f = F.ORIGIN }, { x = d.x, y = d.y, f = F.STOP, k = KIND_ATTACH } },
                  yards = yards, seconds = honest, verifiedYards = 0, unverifiedYards = yards, roadYards = 0, straightYards = yards, connectorYards = 0, meshYards = 0,
                  unverified = true, straight = true, label = L["Open ground"] }
    if o.inst == d.inst then
        noteClimb(leg, leg.points[2], yards, originZ, destZ, ctx.originGuessed or destGuessed or nil)
        labelClimb(leg)
    end
    return leg
end
Router._straightLeg = straightLeg




local function candidateMap(list)
    local map, count = {}, 0
    for _, cand in ipairs(list or {}) do
        local existing = map[cand.key]
        if not existing or cand.dist < existing.dist then map[cand.key] = cand end
        count = count + 1
    end
    return map, count
end





Router.FREE_CUSTOM_TYPES = {
    zone = true, corpse = true, player = true, shared = true, questplace = true, custom = true,
}





function Router._freePoint(ctx, pos, isDest)
    if not isDest then return pos == ctx.origin end
    if pos.poiIndex then
        local poi = FGPS.Data and FGPS.Data.poi
        return type(poi) == "table" and type(poi.type) == "table" and poi.type[pos.poiIndex] == 18
    end
    local kind = pos.kind
    if kind == "custom" then
        return type(pos.original) == "table" and Router.FREE_CUSTOM_TYPES[pos.original.type] == true
    end
    return kind == nil or kind == "coord"
end






function Router._hazardNodes(G, inst)
    local g = G:Ensure(inst)
    local hz, eo = g and g.hz, g and g.eo
    if type(hz) ~= "table" or type(eo) ~= "table" then return nil end
    local cached = g._hazardNodes
    if cached and cached.hz == hz and cached.eo == eo then return cached.nodes end
    local n, base, nodes = g.n or 0, inst * KEY_BASE, nil
    G:IsIsolated(base + 1)
    local off = g._offPiece
    for e in pairs(off and n > 0 and hz or {}) do

        local lo, hi = 1, n
        while lo < hi do
            local mid = floor((lo + hi + 1) / 2)
            if eo[mid] <= e then lo = mid else hi = mid - 1 end
        end
        local piece = off[lo]
        if piece and not (nodes and nodes[lo]) then
            nodes = nodes or {}
            nodes[lo] = piece
            local queue, at = { lo }, 1
            while queue[at] do
                G:Neighbors(base + queue[at], function(key)
                    local idx = key - base
                    if idx >= 1 and idx <= n and not nodes[idx] and off[idx] == piece then
                        nodes[idx] = piece
                        queue[#queue + 1] = idx
                    end
                end)
                at = at + 1
            end
        end
    end
    g._hazardNodes = { hz = hz, eo = eo, nodes = nodes }
    return nodes
end



function Router._onHazardPiece(key)
    local inst = floor(key / KEY_BASE)
    local nodes = Router._hazardNodes(Graph(), inst)
    return nodes ~= nil and nodes[key - inst * KEY_BASE] ~= nil
end




function Router._keptHead(map, G)
    local head, near
    for key, cand in pairs(map) do
        local d = cand.attachYards or cand.dist or 0
        if not head or d < near or (d == near and key < head.key) then head, near = cand, d end
    end
    if head and near <= G.SURFACE_ATTACH_RADIUS then return head end
    return nil
end

do



    local function hazardFloor(inst)
        local water = FGPS.Data and FGPS.Data.water
        local f = water and water[inst] and water[inst].f
        if type(f) ~= "table" or type(f.c) ~= "table" then return nil end
        return f
    end

    local function onFloor(f, x, y)
        local cx, cy = floor((x - f.ox) / f.cell), floor((y - f.oy) / f.cell)
        if cx < 0 or cy < 0 or cx >= f.w or cy >= f.h then return false end
        return f.c[cy * f.w + cx + 1] ~= nil
    end


    function Router._onHazardFloor(inst, x, y)
        local f = hazardFloor(inst)
        return f == nil or onFloor(f, x, y)
    end



    function Router._overHazardFloor(inst, ax, ay, bx, by)
        local f = hazardFloor(inst)
        if not f then return false end
        local dx, dy = bx - ax, by - ay
        local n = floor(sqrt(dx * dx + dy * dy) / (f.cell / 2)) + 1
        for i = 1, n - 1 do
            if onFloor(f, ax + dx * i / n, ay + dy * i / n) then return true end
        end
        return false
    end
end



function Router._inBlockedLiquid(inst, x, y)
    local water = FGPS.Data and FGPS.Data.water
    local layer = water and water[inst]
    local b = layer and layer.b
    if type(b) ~= "table" or type(b.c) ~= "table" or not b.cell then return false end
    local cx, cy = floor((x - layer.ox) / b.cell), floor((y - layer.oy) / b.cell)
    if cx < 0 or cy < 0 or cx >= (b.w or 0) or cy >= (b.h or 0) then return false end
    return b.c[cy * b.w + cx + 1] ~= nil
end

do


    Router.SHEER_WALL_Z_YARDS = 15
    Router.SHEER_WALL_SLOPE = 0.45

    local function inSwimCell(inst, x, y)
        local water = FGPS.Data and FGPS.Data.water
        local layer = water and water[inst]
        local s = layer and layer.s
        if type(s) ~= "table" or type(s.c) ~= "table" or x == nil or y == nil then return false end
        local cell = s.cell or 50
        local cx, cy = floor((x - layer.ox) / cell), floor((y - layer.oy) / cell)
        if cx < 0 or cy < 0 or cx >= (s.w or 0) or cy >= (s.h or 0) then return false end
        return s.c[cy * s.w + cx + 1] ~= nil
    end

    local function touchesSwim(G, key, cand)
        if cand and cand.segKind == KIND_SURFACE_SWIM then return true end
        local wet = false
        G:Neighbors(key, function(_, kind)
            if kind == KIND_SURFACE_SWIM then wet = true end
        end)
        return wet
    end





    function Router._sheerAttach(inst, x1, y1, x2, y2, z1, z2, dock)
        if dock == true or not z1 or not z2 or not inst or not x1 or not x2 then return false end
        local rise = abs(z2 - z1)
        if rise <= Router.HEIGHT_GUESS_SPREAD then return false end
        local dx, dy = x2 - x1, y2 - y1
        local d = sqrt(dx * dx + dy * dy)
        if d < Router.WALL_CHECK_MIN_YARDS then return false end
        local G = Graph()
        local g = G:Ensure(inst)
        if not g or (g.n or 0) < 1000 then return false end
        local wallZ, wallSlope = Router.SHEER_WALL_Z_YARDS, Router.SHEER_WALL_SLOPE
        if rise >= 20 and rise > wallSlope * d then return true end
        local cliffZ = Router.CLIFF_Z_YARDS
        local maxR = Router.WALL_GAP_YARDS + 5
        local checkSpan = d > 2 * Router.MOUNTAIN_GAP_YARDS and d < Router.MOUNTAIN_MIN_YARDS
        for i = 1, 3 do
            local t = i / 4
            local sx, sy = x1 + dx * t, y1 + dy * t
            local base = z1 + (z2 - z1) * t
            if checkSpan then
                local spanNear = G:Nearest(inst, sx, sy, maxR, 8)
                local below, above, other = 0, 0, 0
                for n = 1, #spanNear do
                    local zh = spanNear[n].key and G:NodeHeightGuess(spanNear[n].key)
                    if zh then
                        if zh < base - cliffZ then below = below + 1
                        elseif zh > base + cliffZ then above = above + 1
                        else other = other + 1 end
                    end
                end
                if other == 0 and (below > 0 or above > 0) then return true end
            end
            local d1 = d * t
            local d2 = d - d1
            local rCap = maxR
            if d1 - 5 < rCap then rCap = d1 - 5 end
            if d2 - 5 < rCap then rCap = d2 - 5 end
            if rCap >= 10 then
                local near = G:Nearest(inst, sx, sy, rCap, 8)
                local nHere, sheerHere = 0, 0
                for n = 1, #near do
                    local zh = near[n].key and G:NodeHeightGuess(near[n].key)
                    if zh then
                        nHere = nHere + 1
                        local r1, r2 = abs(zh - z1), abs(z2 - zh)
                        if (r1 > wallZ and r1 > wallSlope * d1) or (r2 > wallZ and r2 > wallSlope * d2) then
                            sheerHere = sheerHere + 1
                        end
                    end
                end
                if nHere > 0 and sheerHere == nHere then return true end
            end
        end
        return false
    end



    function Router._waterAttachZ(G, pos, map, inSurface)
        if not pos or pos.z ~= nil or inSurface then return nil end
        if type(pos.place) == "table" and pos.place.indoor then return nil end
        local g = G:Ensure(pos.inst)
        if not g or (g.n or 0) < 1000 then return nil end
        if not inSwimCell(pos.inst, pos.x, pos.y) then return nil end
        local surfReach = G.SURFACE_ATTACH_RADIUS
        local bestZ, bestD, bestKey
        for key, cand in pairs(map) do
            local d = cand.attachYards or cand.dist or 0
            local wet = touchesSwim(G, key, cand)
            if not wet and d <= surfReach then return nil end
            if wet then
                local cz = cand.footZg or G:NodeHeightGuess(key)
                if cz and (not bestD or d < bestD or (d == bestD and key < bestKey)) then
                    bestZ, bestD, bestKey = cz, d, key
                end
            end
        end
        return bestZ
    end



    function Router._filterCliffAttaches(G, pos, kept, keptN, pz, fromWater, isDest, isHub)
        if isHub or keptN <= 1 then return kept, keptN end
        local refZ = pz or (not isDest and type(pos.zHint) == "number" and pos.zHint or nil)
        if not refZ then return kept, keptN end
        local g = G:Ensure(pos.inst)
        if not g or (g.n or 0) < 1000 then return kept, keptN end
        local stepZ = Router.CLIMB_STEP_YARDS
        local wetOrigin = fromWater or (pz ~= nil and inSwimCell(pos.inst, pos.x, pos.y))
        local hasSameLevel, hadMain = false, false
        for key, cand in pairs(kept) do
            if not cand.offMain then hadMain = true end
            local cz = cand.footZg or G:NodeHeightGuess(key)
            if cz and abs(cz - refZ) <= stepZ then hasSameLevel = true end
        end
        if not hasSameLevel then return kept, keptN end
        local spread = Router.HEIGHT_GUESS_SPREAD
        local slope = Router.CLIMB_WALKABLE_SLOPE
        local stackedStep = Router.STACKED_LEVEL_YARDS * 2
        local surfReach = G.SURFACE_ATTACH_RADIUS
        local out, outN, hasMain = {}, 0, false
        for key, cand in pairs(kept) do
            local drop = false
            if not dockAt(key) then
                local cz = cand.footZg or G:NodeHeightGuess(key)
                if cz then
                    local dz = abs(cz - refZ)
                    local d = cand.attachYards or cand.dist or 0
                    if wetOrigin and dz > stepZ + 3 then
                        drop = true
                    elseif pz ~= nil then
                        if (cand.stacked and dz >= stackedStep) or (dz > spread and dz > slope * d) then
                            drop = true
                        end
                    elseif cand.stacked and dz > spread and d <= surfReach then
                        drop = true
                    end
                end
            end
            if not drop then
                out[key] = cand
                outN = outN + 1
                if not cand.offMain then hasMain = true end
            end
        end


        if not wetOrigin and pz == nil and hadMain and not hasMain then return kept, keptN end
        if outN > 0 then return out, outN end
        return kept, keptN
    end
end







function Router._chordCrossesWater(G, C, node, nbKey, kind)
    if not (C and C.OverSwim) then return false end
    if kind == KIND_CONNECTOR and (isTransportStop(G:NodeFlags(node)) or isTransportStop(G:NodeFlags(nbKey))) then
        return false
    end
    local finst, fx, fy = G:NodePos(node)
    local _, nx2, ny2 = G:NodePos(nbKey)
    if not (fx and nx2) or not C.OverSwim(finst, fx, fy, nx2, ny2) then return false end
    local world = G:Ensure(finst)
    if not world or ((world.n or 0) < 1000 and (finst == 0 or finst == 1 or finst == 2991)) then return false end
    local _, aIn, aSt = G:NodePlace(node)
    if aIn or aSt then return false end
    local _, bIn, bSt = G:NodePlace(nbKey)
    if bIn or bSt then return false end
    local memo = world._wetChord
    if not memo then
        memo = {}
        world._wetChord = memo
    end
    local aIdx, bIdx = node % KEY_BASE, nbKey % KEY_BASE
    if aIdx > bIdx then aIdx, bIdx = bIdx, aIdx end
    local pairKey = aIdx * KEY_BASE + bIdx
    local cached = memo[pairKey]
    if cached ~= nil then return cached end
    local az, bz = G:NodeHeightGuess(node), G:NodeHeightGuess(nbKey)
    local edgeZ = (az and bz) and (0.5 * (az + bz)) or az or bz
    local isBridge = false
    if edgeZ ~= nil then
        local mx, my = 0.5 * (fx + nx2), 0.5 * (fy + ny2)
        local swimZ, bestSwimD = nil, 999
        for _, hit in ipairs(G:Nearest(finst, mx, my, 85, 128)) do
            if hit.dist < bestSwimD then
                local isSwim = false
                G:Neighbors(hit.key, function(_, nkind)
                    if nkind == KIND_SURFACE_SWIM or nkind == 5 then isSwim = true end
                end)
                if isSwim then
                    local hz = G:NodeHeight(hit.key)
                    if hz ~= nil then bestSwimD, swimZ = hit.dist, hz end
                end
            end
        end
        if swimZ ~= nil and edgeZ - swimZ >= Router.STACKED_LEVEL_YARDS then
            isBridge = true
        end
    end
    local wet = not isBridge
    memo[pairKey] = wet
    return wet
end






Router.GROUND_Z_CLAMP_RADIUS = 15
Router.GROUND_Z_CLAMP_DIFF = 20
Router.GROUND_Z_MAX_SPREAD = 10
function Router._groundPointZ(key, kind)
    if type(key) ~= "number" or key < 0 then return nil end
    local G = Graph()
    local z = G:NodeHeight(key)
    if z == nil or G:IsSurfaceNode(key) then return z end
    if kind ~= nil and kind ~= 1 and kind ~= 2 and kind ~= 3 and kind ~= 4 and kind ~= 17 then
        return z
    end
    if isTransportStop(G:NodeFlags(key)) then return z end
    local inst, x, y = G:NodePos(key)
    local world = inst and G:Ensure(inst)
    if not world then return z end
    local memo = world._groundPointZ
    if not memo then
        memo = {}
        world._groundPointZ = memo
    end
    local idx = key - inst * KEY_BASE
    local cached = memo[idx]
    if cached ~= nil then return cached == false and z or cached end
    if kind == nil then
        local target = false
        G:Neighbors(key, function(_, nkind)
            if nkind == 1 or nkind == 2 or nkind == 3 or nkind == 4 or nkind == 17 then target = true end
        end)
        if not target then
            memo[idx] = false
            return z
        end
    end
    local minZ, maxZ, nearZ, nearD, ambiguous, hasDry = nil, nil, nil, nil, false, false
    for _, hit in ipairs(G:Nearest(inst, x, y, Router.GROUND_Z_CLAMP_RADIUS, 24)) do
        if G:IsSurfaceNode(hit.key) then
            local _, hIn, hSt = G:NodePlace(hit.key)
            if hIn or hSt then
                ambiguous = true
                break
            end
            local hz = G:NodeHeight(hit.key)
            if hz ~= nil then
                local dry = false
                G:Neighbors(hit.key, function(_, nkind)
                    if nkind == KIND_SURFACE then dry = true end
                end)
                if dry then
                    hasDry = true
                    if not minZ or hz < minZ then minZ = hz end
                    if not maxZ or hz > maxZ then maxZ = hz end
                    if not nearD or hit.dist < nearD or (hit.dist == nearD and hit.key < key) then
                        nearD, nearZ = hit.dist, hz
                    end
                end
            end
        end
    end
    if ambiguous or not hasDry or (maxZ - minZ) > Router.GROUND_Z_MAX_SPREAD or abs(z - nearZ) <= Router.GROUND_Z_CLAMP_DIFF then
        memo[idx] = false
        return z
    end


    local q, seen, head, tail = { key }, { [key] = true }, 1, 1
    local caveMouth = false
    while head <= tail and tail < 30 do
        local curK = q[head]
        head = head + 1
        G:Neighbors(curK, function(nb)
            if caveMouth then return end
            if G:IsSurfaceNode(nb) then
                local sz = G:NodeHeight(nb)
                if sz ~= nil and abs(sz - z) <= 15 then caveMouth = true end
            elseif not seen[nb] and tail < 30 then
                seen[nb] = true
                tail = tail + 1
                q[tail] = nb
            end
        end)
        if caveMouth then break end
    end
    if caveMouth then
        memo[idx] = false
        return z
    end
    memo[idx] = nearZ
    return nearZ
end

function Router._candGroundFootZ(cand, nodeKey)
    if not cand or type(cand.footZ) ~= "number" then return nil end
    local key = type(nodeKey) == "number" and nodeKey >= 0 and nodeKey or cand.key
    if not cand.otherKey or type(key) ~= "number" or key < 0 then
        return Router._groundPointZ(key, cand.segKind) or cand.footZ
    end
    local G = Graph()
    local za = Router._groundPointZ(key, cand.segKind)
    local zb = Router._groundPointZ(cand.otherKey, cand.segKind)
    if not (za and zb) then return cand.footZ end
    if za == G:NodeHeight(key) and zb == G:NodeHeight(cand.otherKey) then return cand.footZ end
    local _, ax, ay = G:NodePos(key)
    local _, bx, by = G:NodePos(cand.otherKey)
    if not (ax and bx and cand.fx and cand.fy) then return za end
    local D = Coords().Distance
    local da = D(ax, ay, cand.fx, cand.fy)
    local db = D(cand.fx, cand.fy, bx, by)
    local tot = da + db
    return tot > 0 and (za + (zb - za) * (da / tot)) or za
end

























function Router._ownPiece(pos, map, count)
    local G = Graph()
    local nodes = Router._hazardNodes(G, pos.inst)
    if not nodes then return map, count, false end
    local base, head = pos.inst * KEY_BASE, Router._keptHead(map, G)
    local own = head and nodes[head.key - base] or nil
    local beside
    if own ~= nil and not Router._onHazardFloor(pos.inst, pos.x, pos.y) then
        own, beside = nil, own
        local inLiquid = Router._inBlockedLiquid(pos.inst, pos.x, pos.y)
        local left, leftN = {}, 0
        for key, cand in pairs(map) do
            local fx, fy = cand.fx, cand.fy
            if not fx then
                local _, nx, ny = G:NodePos(key)
                fx, fy = nx, ny
            end
            if nodes[key - base] ~= nil
                    or not inLiquid and not (fx and Router._overHazardFloor(pos.inst, pos.x, pos.y, fx, fy)) then
                left[key], leftN = cand, leftN + 1
            end
        end
        map, count = left, leftN
    end
    local kept, keptN, onMain = {}, 0, false
    for key, cand in pairs(map) do
        if nodes[key - base] == own then
            kept[key], keptN = cand, keptN + 1
            onMain = onMain or not cand.offMain
        end
    end
    if own == nil and not onMain then

        if beside == nil then return map, count, false end
        own, kept, keptN = beside, {}, 0
        for key, cand in pairs(map) do
            if nodes[key - base] == own then kept[key], keptN = cand, keptN + 1 end
        end
    end
    return kept, keptN, own ~= nil
end




















Router.DOOR_SPOT_YARDS = 3
function Router._doorFloor(pos, map, count, stated)
    if not Router._lineReach(pos.inst) then return map, count end
    local G = Graph()
    local inferredDoor = pos.inferred and not pos.place
    local head, near
    if stated and pos.z ~= nil and not inferredDoor then
        for key, cand in pairs(map) do
            local d, z = cand.attachYards or cand.dist or 0, cand.footZ or G:NodeHeight(key)
            if d <= Router.DOOR_SPOT_YARDS and z ~= nil and abs(z - pos.z) <= Router.STACKED_LEVEL_YARDS
                    and (not head or d < near or (d == near and key < head.key)) then
                head, near = cand, d
            end
        end
    end
    if not head then
        head = Router._keptHead(map, G)
        if not head or (head.attachYards or head.dist or 0) > Router.DOOR_SPOT_YARDS
                or floor((G:NodeFlags(head.key) or 0) / 8) % 2 ~= 1 then
            head, near = nil, nil
            if inferredDoor then
                for key, cand in pairs(map) do
                    local d = cand.attachYards or cand.dist or 0
                    if floor((G:NodeFlags(key) or 0) / 8) % 2 == 1
                            and (not head or d < near or (d == near and key < head.key)) then
                        head, near = cand, d
                    end
                end
                if not head then
                    for _, hit in ipairs(G:Nearest(pos.inst, pos.x, pos.y, G.SURFACE_ATTACH_RADIUS, 128)) do
                        local z = G:NodeHeight(hit.key)
                        if floor((G:NodeFlags(hit.key) or 0) / 8) % 2 == 1
                                and (pos.z == nil or z == nil or abs(z - pos.z) <= (G.MAX_ATTACH_DZ or 15))
                                and (not head or hit.dist < near or (hit.dist == near and hit.key < head.key)) then
                            head, near = { key = hit.key, dist = hit.dist, attachYards = hit.dist, footZ = z }, hit.dist
                        end
                    end
                end
            end
            if not head then return map, count end
        end
    end
    G:IsIsolated(head.key)
    local off, base = G:Ensure(pos.inst)._offPiece, pos.inst * KEY_BASE
    local own = off and off[head.key - base] or 0
    local kept, keptN = {}, 0
    for key, cand in pairs(map) do
        if (off and off[key - base] or 0) == own then kept[key], keptN = cand, keptN + 1 end
    end
    if keptN == 0 and inferredDoor then
        kept[head.key], keptN = head, 1
    end
    return kept, keptN
end





function attachFor(ctx, pos, isDest, isHub)



    local opts = { allowUnverified = ctx.access.allowUnverified ~= false, map = not isHub and pos.map or nil,
                   floor = not isHub and pos.floor or nil, poiIndex = (isDest and not isHub) and pos.poiIndex or nil,
                   originPoi = (not isDest and not isHub) and pos.poiIndex or nil,
                   place = not isHub and pos.place or nil, free = not isHub and Router._freePoint(ctx, pos, isDest) or nil,
                   z = not isHub and pos.z or nil, zHint = not isHub and pos.zHint or nil,
                   highRes = not isHub and ctx.access.highRes or nil }


    local perf = FGPS.Perf
    local started = perf and perf.enabled and debugprofilestop() or nil
    local list, radius = Graph():AttachProgressive(pos.inst, pos.x, pos.y, opts)
    if started then perf:Record("attach", debugprofilestop() - started) end
    local map, count = candidateMap(list)
    local reach = Router._lineReach(pos.inst)
    if count > 0 and reach then
        local near, nearN = {}, 0
        for key, cand in pairs(map) do
            if (cand.attachYards or cand.dist or 0) <= reach then
                near[key], nearN = cand, nearN + 1
            end
        end
        if nearN > 0 then map, count = near, nearN end
    end





    local waterZ
    if count > 0 then
        local kept, keptN = {}, 0
        local G = Graph()
        local pz = pos.z
        local fromWater = false
        if pz == nil and not isHub then
            waterZ = Router._waterAttachZ(G, pos, map, list.inSurface)
            if waterZ ~= nil then
                pz, fromWater = waterZ, true
            end
        end
        for key, cand in pairs(map) do
            local fx, fy = cand.fx, cand.fy
            if not fx then
                local _, nx, ny = G:NodePos(key)
                fx, fy = nx, ny
            end
            local nz = G:NodeHeightGuess(key)
            local cut, sparse = false, false
            if fx then cut, sparse = cutsObstacle(pos.inst, pos.x, pos.y, fx, fy, ctx.cityTrip, pz, cand.footZg or nz) end






            if not cut and (cand.segKind == KIND_CONNECTOR or cand.segKind == KIND_MESH) then
                local _, ax, ay = G:NodePos(key)
                local dock = dockBetween(key, cand.otherKey)
                local stored = cand.segKind == KIND_CONNECTOR
                local linked = stored and dock
                if ax and fx then cut = cutsObstacle(pos.inst, fx, fy, ax, ay, ctx.cityTrip, cand.footZg, nz, dock, linked, stored) end
                if not cut and ax and cand.otherKey then
                    local _, bx, by = G:NodePos(cand.otherKey)
                    if bx then
                        cut = cutsObstacle(pos.inst, ax, ay, bx, by, ctx.cityTrip, nz, G:NodeHeightGuess(cand.otherKey), dock, linked, stored)
                    end
                end
            end
            if not cut then

                cand.sparse = sparse or nil
                kept[key] = cand
                keptN = keptN + 1
            end
        end
        kept, keptN = Router._filterCliffAttaches(G, pos, kept, keptN, pz, fromWater, isDest, isHub)
        map, count = kept, keptN
    end
    if not isDest and not isHub and pos == ctx.origin then ctx.originWaterZ = waterZ end

    local ringed = false
    if count > 0 then map, count, ringed = Router._ownPiece(pos, map, count) end
    if count > 0 and not ringed then map, count = Router._doorFloor(pos, map, count, not isHub) end
    return map, count, radius, list.inSurface or ringed
end
























local function levelRange(candidates, borrowed)
    if not candidates then return nil end
    local reach, low, high = Router.HEIGHT_GUESS_YARDS, nil, nil
    for _, cand in pairs(candidates) do
        local z, d = cand.footZ, cand.attachYards or cand.dist
        if borrowed then z = cand.footZg end
        if z and d <= reach then
            if not low or z < low then low = z end
            if not high or z > high then high = z end
        end
    end
    return low, high
end



local function levelsApart(candidates)
    local low, high = levelRange(candidates, true)
    if low == nil then return false end
    if high - low > Router.HEIGHT_GUESS_SPREAD then return true end


    local reach, sLow, sHigh = Router.HEIGHT_GUESS_YARDS, nil, nil
    for _, cand in pairs(candidates) do
        local z, d = cand.footZ, cand.attachYards or cand.dist
        if cand.stacked and z and d <= reach then
            if not sLow or z < sLow then sLow = z end
            if not sHigh or z > sHigh then sHigh = z end
        end
    end
    return sLow ~= nil and sHigh - sLow >= Router.STACKED_LEVEL_YARDS
end


local function guessHeight(candidates, anyLevel, borrowed, hint)
    if not candidates then return nil end
    local reach, nearest, best = Router.HEIGHT_GUESS_YARDS, nil, nil
    local hinted, hintedD
    local spread = Router.HEIGHT_GUESS_SPREAD










    local onMain = false
    for _, cand in pairs(candidates) do
        local z = borrowed and cand.footZg or cand.footZ
        if z and not cand.offMain and (cand.attachYards or cand.dist) <= reach then onMain = true break end
    end
    local levelZ
    if type(hint) == "number" then
        local stacked = false
        for _, cand in pairs(candidates) do
            local z, d = cand.footZ, cand.attachYards or cand.dist
            if borrowed then z = cand.footZg end
            if onMain and cand.offMain then z = nil end
            if z and d <= reach and abs(z - hint) <= spread then
                if cand.stacked then stacked = true end
                local off, cur = abs(z - hint), levelZ and abs(levelZ - hint)
                if not levelZ or off < cur or (off == cur and z < levelZ) then levelZ = z end
            end
        end
        if not stacked then levelZ = nil end
    end
    for _, cand in pairs(candidates) do
        local z, d = cand.footZ, cand.attachYards or cand.dist
        if borrowed then z = cand.footZg end
        if onMain and cand.offMain then z = nil end
        if z and d <= reach then

            if not nearest or d < nearest or (d == nearest and z < best) then nearest, best = d, z end
            local onLevel
            if levelZ then onLevel = abs(z - levelZ) <= Router.CLIMB_STEP_YARDS
            else onLevel = type(hint) == "number" and abs(z - hint) <= spread end
            if onLevel and (not hintedD or d < hintedD or (d == hintedD and z < hinted)) then
                hinted, hintedD = z, d
            end
        end
    end
    if hinted then return hinted end
    if not best then return nil end
    if not anyLevel and levelsApart(candidates) then return nil end
    return best
end

local function setupTeleports(ctx)
    local access, C = ctx.access, Cost()
    local options = {}
    local t = access.transports or {}
    if access.hearth and t.hearth ~= false then options[#options + 1] = { entry = access.hearth, kind = C.KIND_HEARTH, mode = "hearth" } end
    if t.spells ~= false and type(access.spells) == "table" then
        for _, sp in ipairs(access.spells) do options[#options + 1] = { entry = sp, kind = C.KIND_SPELL, mode = "spell" } end
    end
    local k = 0
    for _, opt in ipairs(options) do
        local e = opt.entry
        local remaining = e.ready and 0 or (tonumber(e.cdRemaining) or huge)
        if e.inst and e.x and e.y and remaining < Const.TELEPORT_MAX_WAIT and Graph():InstancesConnected(e.inst, ctx.dest.inst) then
            k = k + 1
            local key = TELE_BASE - k
            local cast = tonumber(e.castSeconds) or Const.HEARTH_CAST_SECONDS
            local v = { inst = e.inst, x = e.x, y = e.y, map = e.map,
                        z = e.poiIndex and Graph():PoiLevelHeight(e.poiIndex) or nil }
            ctx.vpos[key] = v
            ctx.teleports[key] = { option = e, kind = opt.kind, mode = opt.mode, wait = remaining,
                                   seconds = cast + Const.HEARTH_LOAD_SECONDS + remaining }



            if remaining > 0 then ctx.teleportWaits = true end
            local list, _, _, enclosed = attachFor(ctx, v, false)
            ctx.teleAttach[key], ctx.teleEnclosed[key] = list, enclosed
            if not v.z then
                v.z = guessHeight(list, true)
                v.zGuessed = v.z ~= nil or nil
                if not v.z then v.zg = guessHeight(list, true, true) end
            end
        end
    end
end




local function relaxChains(list, speed)
    local n = #list
    local D = Coords().Distance
    for _ = 1, n do
        local changed = false
        for i = 1, n do
            local a = list[i]
            if a.tx then
                for j = 1, n do
                    if i ~= j then
                        local b = list[j]
                        local alt = a.secs + D(a.tx, a.ty, b.fx, b.fy) / speed + b.rest
                        if alt < a.rest then a.rest, changed = alt, true end
                    end
                end
            end
        end
        if not changed then break end
    end
end






Router._fixed = {}
function Router._fixedEdges(inst)
    local G = Graph()
    local base = G:FixedEdges(inst)
    local links = FGPS.Data and FGPS.Data.links
    local kept = Router._fixed[inst]
    if kept and kept.base == base and kept.links == links then return kept.list end
    local list, seen = {}, {}
    for i = 1, #base do
        local e = base[i]
        list[i] = e
        seen[e.from .. ":" .. e.to] = true
    end
    for _, l in ipairs(type(links) == "table" and links or {}) do
        if l[5] == 7 and l[1] == inst and l[3] == inst and l[2] and l[4] then
            local from, to = G:Key(inst, l[2]), G:Key(inst, l[4])
            local _, fx, fy = G:NodePos(from)
            local _, tx, ty = G:NodePos(to)
            if fx and tx and not seen[from .. ":" .. to] then
                seen[from .. ":" .. to] = true
                list[#list + 1] = { from = from, to = to, kind = 7, yards = Coords().Distance(fx, fy, tx, ty), seconds = l[6],
                                    transportID = l[7], fx = fx, fy = fy, tx = tx, ty = ty }
            end
        end
    end
    Router._fixed[inst] = { base = base, links = links, list = list }
    return list
end







local function setupFastLinks(ctx)


    local speed = Cost().SearchSpeed(ctx.access, ctx.variant)
    ctx.maxSpeed = speed
    local edges = Router._fixedEdges(ctx.dest.inst)
    local D = Coords().Distance
    local dest = ctx.dest
    local list = {}
    for i = 1, #edges do
        local e = edges[i]
        local secs = Router._leastBase(ctx, e, e.yards)
        if secs and e.yards > secs * speed then
            list[#list + 1] = { fx = e.fx, fy = e.fy, tx = e.tx, ty = e.ty, secs = secs,
                                rest = secs + D(e.tx, e.ty, dest.x, dest.y) / speed }
        end
    end
    relaxChains(list, speed)







    local cross = Graph():CrossLinks(dest.inst)
    local outside, outsideAlt
    local lm = ctx.lm
    for i = 1, #cross.into do
        local e = cross.into[i]
        local secs = Router._leastBase(ctx, e, 0)
        if secs then
            local alt = secs + estimateFrom(list, speed, e.x, e.y, dest)
            if not outside or alt < outside then outside = alt end



            if lm then
                local bound = Router._landmarkAt(lm, dest.inst, e.to)
                if ctx.lm2 then
                    local roads = Router._landmarkAt(ctx.lm2, dest.inst, e.to)
                    if roads > bound then bound = roads end
                end
                local landed = secs + bound
                if alt > landed then landed = alt end
                if not outsideAlt or landed < outsideAlt then outsideAlt = landed end
            end
        end
    end
    ctx.outsideAlt = outsideAlt
    if outside then
        ctx.outsideRest = outside
        local inside = #list
        for i = 1, #cross.out do
            local e = cross.out[i]
            local secs = Router._leastBase(ctx, e, 0)


            if secs and secs + outside < estimateFrom(list, speed, e.x, e.y, dest) then
                list[#list + 1] = { fx = e.x, fy = e.y, rest = secs + outside }
            end
        end
        if #list > inside then relaxChains(list, speed) end
    end
    if #list > 0 then ctx.fastLinks = list end
    ctx.outsideLists = {}
    Router._prepareFlightH(ctx, speed)
end













function Router._outsideList(ctx, inst)
    local G, D = Graph(), Coords().Distance
    local speed, dest = ctx.maxSpeed, ctx.dest
    local outside = ctx.outsideRest or 0
    local list = {}
    local cross = G:CrossLinks(inst)
    for i = 1, #cross.out do
        local e = cross.out[i]
        local secs = Router._leastBase(ctx, e, 0)
        if secs then
            local toInst, tx, ty = G:NodePos(e.to)






            local after = outside
            if toInst == dest.inst and tx then after = estimateFrom(ctx.fastLinks, speed, tx, ty, dest) end
            list[#list + 1] = { fx = e.x, fy = e.y, rest = secs + after }
        end
    end
    if #list == 0 then
        ctx.outsideLists[inst] = false
        return false
    end
    local edges = Router._fixedEdges(inst)
    for i = 1, #edges do
        local e = edges[i]
        local secs = Router._leastBase(ctx, e, e.yards)
        if secs and e.yards > secs * speed then
            local rest = huge
            for j = 1, #list do
                local b = list[j]
                if not b.tx then
                    local alt = secs + D(e.tx, e.ty, b.fx, b.fy) / speed + b.rest
                    if alt < rest then rest = alt end
                end
            end
            list[#list + 1] = { fx = e.fx, fy = e.fy, tx = e.tx, ty = e.ty, secs = secs, rest = rest }
        end
    end
    relaxChains(list, speed)





    table.sort(list, function(a, b) return a.rest < b.rest end)
    local kept = {}
    for i = 1, #list do
        local b, needed = list[i], true
        for j = 1, #kept do
            local a = kept[j]
            if a.rest + D(a.fx, a.fy, b.fx, b.fy) / speed <= b.rest then
                needed = false
                break
            end
        end
        if needed then kept[#kept + 1] = b end
    end
    list = kept
    ctx.outsideLists[inst] = list
    return list
end

function Router._outsideEstimate(ctx, inst, x, y)
    local outside = ctx.outsideRest or 0
    local lists = ctx.outsideLists
    if not lists then return outside end
    local list = lists[inst]
    if list == nil then list = Router._outsideList(ctx, inst) end
    if not list then return outside end
    local speed, h = ctx.maxSpeed, huge



    for i = 1, #list do
        local link = list[i]
        if link.rest >= h then break end
        local dx, dy = link.fx - x, link.fy - y
        local alt = sqrt(dx * dx + dy * dy) / speed + link.rest
        if alt < h then h = alt end
    end
    if h < outside then h = outside end
    return h
end

local function instanceName(inst)
    local instances = FGPS.Data and FGPS.Data.instances
    local rec = instances and instances[inst]
    if rec and rec.name then return rec.name end
    return string.format(L["instance %d"], inst)
end

local KIND_WORDS = { [7] = "portals", [8] = "flights", [9] = "boats or zeppelins", [10] = "the tram", [11] = "elevators" }

local function transportLinkUsable(ctx, kind, transportID, fromInst, toInst)
    local access, variant = ctx.access, ctx.ride
    local A = Access()
    if kind == 8 then
        if variant == "no_flight" then return false end
        if access.transports and access.transports.taxi == false then return false end
        local kt = access.knownTaxi
        if not kt then return false end
        for _ in pairs(kt) do return true end
        return false
    end
    if kind == 9 or kind == 10 or kind == 11 then
        if kind == 9 and variant == "no_boat" then return false end
        local records = FGPS.Data and FGPS.Data.transports
        local rec = transportID and records and records[transportID]
        if rec then return A:CanUseTransport(access, rec) end
        if kind == 10 then return not (access.transports and access.transports.tram == false) end
        if kind == 11 then return true end
        local t = access.transports
        return not (t and t.boat == false and t.zeppelin == false)
    end
    if kind == 7 then return Router._doorAllowed(ctx, fromInst, toInst) end
    return false
end

local function instancesReachableByAccess(ctx, fromInst, toInst)
    if fromInst == toInst then return true end
    local G = Graph()
    if not G:InstancesConnected(fromInst, toInst) then return false end
    local instances = FGPS.Data and FGPS.Data.instances
    if not instances then return true end
    local seen, frontier = { [fromInst] = true }, { fromInst }
    while #frontier > 0 do
        local cur = table.remove(frontier)
        for nextInst in pairs(instances) do
            if not seen[nextInst] then
                local links = G:LinkKinds(cur, nextInst)
                for i = 1, #links do
                    local link = links[i]
                    if transportLinkUsable(ctx, link.kind, link.transportID, cur, nextInst) then
                        if nextInst == toInst then return true end
                        seen[nextInst] = true
                        frontier[#frontier + 1] = nextInst
                        break
                    end
                end
            end
        end
    end
    return false
end



local function teleportReaches(ctx)
    for key in pairs(ctx.teleports) do
        if instancesReachableByAccess(ctx, ctx.vpos[key].inst, ctx.dest.inst) then return true end
    end
    return false
end



function Router._doorOutside(map)
    local G = Graph()
    local maps = FGPS.Data and FGPS.Data.insideMaps or {}
    local best
    for inst in pairs(FGPS.Data and FGPS.Data.instances or {}) do
        if inst ~= map and not maps[inst] and (best == nil or inst < best) then
            for _, link in ipairs(G:LinkKinds(map, inst)) do
                if link.kind == 7 then
                    best = inst
                    break
                end
            end
        end
    end
    return best
end


local function unreachableMessage(ctx, o, d)
    local G = Graph()
    o, d = o or ctx.origin.inst, d or ctx.dest.inst



    local maps = FGPS.Data and FGPS.Data.insideMaps
    local inside = maps and o ~= d and ((maps[d] and d) or (maps[o] and o)) or nil
    if inside then
        local outside = Router._doorOutside(inside)
        local followed = outside and not maps[outside]
        if inside == d and followed and not instancesReachableByAccess(ctx, o, outside) and not teleportReaches(ctx) then
            return unreachableMessage(ctx, o, outside)
        end
        if inside == o and followed and not instancesReachableByAccess(ctx, outside, d) then
            return unreachableMessage(ctx, outside, d)
        end
        local name = maps[inside].name or instanceName(inside)
        if inside == d then return string.format(L["I don't know a way to this place inside %s yet."], name) end
        return string.format(L["I don't know a way from here inside %s yet."], name)
    end
    if not G:InstancesConnected(o, d) then
        return string.format(L["I know of no transport between %s and %s."], instanceName(o), instanceName(d))
    end
    local kinds = G:LinkKinds(o, d)
    local words, seen = {}, {}
    for _, link in ipairs(kinds) do
        local records = FGPS.Data and FGPS.Data.transports
        local rec = link.transportID and records and records[link.transportID]
        local word = rec and rec.kind and (rec.kind .. "s") or KIND_WORDS[link.kind] or L["transports"]
        if rec and rec.kind == "ferry" then word = "boats" end
        if not seen[word] then
            seen[word] = true
            words[#words + 1] = L[word]
        end
    end
    if #words > 0 then
        return string.format(L["%s can only be reached by %s; enable them in the transport settings or check the faction restriction."],
            instanceName(d), table.concat(words, " " .. L["or"] .. " "))
    end
    return string.format(L["%s is reachable only through another continent's transports, which are currently disabled."], instanceName(d))
end


function Router._searchLegs(ctx)
    local ok, reason = search(ctx)
    if not ok then return nil, reason end
    local edges = collectEdges()
    if not edges then return nil, "EXHAUSTED" end
    return buildLegs(ctx, edges)
end








function Router._unlessSlowerThanWithout(ctx, legs)
    if ctx.variant ~= "roads_only" and ctx.variant ~= "prefer_roads" then return legs end
    local first = legs[1]
    if not first or (first.kind ~= "hearth" and first.kind ~= "spell") then return legs end
    local o, d = ctx.origin, ctx.dest
    if o.inst ~= d.inst and not instancesReachableByAccess(ctx, o.inst, d.inst) then return legs end
    local function total(list)
        local s = 0
        for i = 1, #list do s = s + (list[i].seconds or 0) end
        return s
    end
    local seconds = total(legs)
    local teleports, bound, expansions = ctx.teleports, ctx.maxSeconds, ctx.expansions or 0
    ctx.teleports = {}
    ctx.maxSeconds = (bound and bound < seconds) and bound or seconds
    local other, reason = Router._searchLegs(ctx)
    ctx.teleports, ctx.maxSeconds = teleports, bound
    ctx.expansions = expansions + (ctx.expansions or 0)
    if reason == "CANCELLED" then return nil, reason end
    if other and total(other) <= seconds then return other end
    return legs
end

local function computeSegment(ctx)
    local G = Graph()
    local o, d = ctx.origin, ctx.dest

    ctx.straightRate = (Cost().EdgeSeconds(KIND_ATTACH, 1, ctx.access) or 0) * Cost().RoadFactor(ctx.variant, KIND_ATTACH)
    ctx.cityTrip = o.inst == d.inst and inCapital(o.inst, o.x, o.y) and inCapital(d.inst, d.x, d.y) or nil
    local originGraph, destGraph = G:Ensure(o.inst), G:Ensure(d.inst)
    setupTeleports(ctx)
    if o.inst == d.inst then
        if not originGraph then
            local leg = straightLeg(ctx)


            if leg and ctx.maxSeconds and leg.seconds > ctx.maxSeconds then
                return nil, { code = "NO_PATH", message = L.ROUTE_NO_PATH, partial = { expansions = 0, bound = ctx.maxSeconds } }
            end
            if leg then
                ctx.fallback = "straight"
                return { leg }
            end
            return nil, { code = "NO_DATA", message = L.ROUTE_NO_DATA }
        end
    elseif not originGraph or not destGraph then



        local missing = (not originGraph) and o.inst or d.inst
        if not G:InstancesConnected(o.inst, d.inst) then
            local inside = FGPS.Data and FGPS.Data.insideMaps
            local message = (not originGraph and not (inside and inside[o.inst]))
                and string.format(L["Cabbie has no map of %s. Ask again once you leave it."], instanceName(o.inst))
                or unreachableMessage(ctx)
            return nil, { code = "UNREACHABLE", message = message }
        end
        return nil, { code = "NO_DATA", message = string.format(L["No navigation data is available for %s."], instanceName(missing)) }
    end

    local originCount, destCount, originRadius, destRadius
    ctx.originAttach, originCount, originRadius, ctx.originEnclosed = attachFor(ctx, o, false)


    if not Scheduler().Yield() then return nil, { code = "CANCELLED", message = L.ROUTE_CANCELLED } end
    ctx.destAttach, destCount, destRadius, ctx.destEnclosed = attachFor(ctx, d, true)
    if not Scheduler().Yield() then return nil, { code = "CANCELLED", message = L.ROUTE_CANCELLED } end
    ctx.originZ, ctx.destZ, ctx.originGuessed, ctx.destGuessed = o.z, d.z, nil, nil
    ctx.originZg, ctx.destZg = nil, nil
    if not ctx.originZ then
        ctx.originZ = guessHeight(ctx.originAttach, true, nil, o.zHint) or ctx.originWaterZ
        ctx.originGuessed = ctx.originZ ~= nil or nil

        if not ctx.originZ then ctx.originZg = guessHeight(ctx.originAttach, true, true, o.zHint) end
    end
    ctx.originStacked = ctx.originZ ~= nil and levelsApart(ctx.originAttach) or nil
    ctx.destLow, ctx.destHigh, ctx.destLowG, ctx.destHighG = nil, nil, nil, nil
    if not ctx.destZ then
        ctx.destZ = guessHeight(ctx.destAttach, false)
        ctx.destGuessed = ctx.destZ ~= nil or nil
        if not ctx.destZ and levelsApart(ctx.destAttach) then


            ctx.destLow, ctx.destHigh = levelRange(ctx.destAttach)
            ctx.destLowG, ctx.destHighG = levelRange(ctx.destAttach, true)
        end
        if not ctx.destZ and not ctx.destLowG then ctx.destZg = guessHeight(ctx.destAttach, false, true) end
    end



    ctx.destStacked = ctx.destZ ~= nil and levelsApart(ctx.destAttach) or nil
    local taxiID = d.original and d.original.taxiNodeID
    ctx.destHubKey = type(taxiID) == "number" and G:TaxiNodeKey(taxiID) or nil
    ctx.attachInfo = { originRadius = originRadius, destRadius = destRadius,
                       originAttached = originCount > 0, destAttached = destCount > 0,
                       widened = (originCount > 0 and originRadius > G.ATTACH_RADIUS) or (destCount > 0 and destRadius > G.ATTACH_RADIUS)
                                 or originCount == 0 or destCount == 0 }
    if o.inst ~= d.inst and not instancesReachableByAccess(ctx, o.inst, d.inst) and not teleportReaches(ctx) then
        return nil, { code = "UNREACHABLE", message = unreachableMessage(ctx) }
    end






    if destCount == 0 then
        local same = o.inst == d.inst
        local cap = ctx.maxStraight or Router.DEFAULT_MAX_STRAIGHT_YARDS
        local closable = (same and Coords().Distance(o.x, o.y, d.x, d.y) <= cap) or #G:Nearest(d.inst, d.x, d.y, cap, 1) > 0
        for key in pairs(ctx.teleports) do
            local p = ctx.vpos[key]
            if p.inst == d.inst and Coords().Distance(p.x, p.y, d.x, d.y) <= cap then closable = true end
        end
        if not closable then
            if same and ctx.access.allowUnverified ~= false then
                local leg = straightLeg(ctx)
                if leg and not (ctx.maxSeconds and leg.seconds > ctx.maxSeconds) then
                    ctx.fallback = "straight"
                    return { leg }
                end
            end
            return nil, { code = "NO_PATH", message = L.ROUTE_NO_PATH, partial = { expansions = 0 } }
        end
    end
    Router._setGuarded(ctx)
    Router._landmarkSetup(ctx)
    if not Scheduler().Yield() then return nil, { code = "CANCELLED", message = L.ROUTE_CANCELLED } end
    setupFastLinks(ctx)
    if not Scheduler().Yield() then return nil, { code = "CANCELLED", message = L.ROUTE_CANCELLED } end

    local legs, reason = Router._searchLegs(ctx)
    if legs then legs, reason = Router._unlessSlowerThanWithout(ctx, legs) end
    if legs then Router._noteAlong(ctx, legs) end
    if legs then


        if #legs == 1 and legs[1].straight then ctx.fallback = "straight" end
        return legs
    end
    if reason == "CANCELLED" then return nil, { code = "CANCELLED", message = L.ROUTE_CANCELLED } end
    if reason == "BOUND" then
        return nil, { code = "NO_PATH", message = L.ROUTE_NO_PATH, partial = { expansions = ctx.expansions, bound = ctx.maxSeconds } }
    end
    if o.inst ~= d.inst then
        if reason == "CAP" then
            return nil, { code = "NO_PATH", message = L.ROUTE_NO_PATH, partial = { expansions = ctx.expansions, cap = true } }
        end
        return nil, { code = "UNREACHABLE", message = unreachableMessage(ctx), partial = { expansions = ctx.expansions } }
    end
    if ctx.access.allowUnverified ~= false then
        local leg = straightLeg(ctx)
        if leg and not (ctx.maxSeconds and leg.seconds > ctx.maxSeconds) then
            ctx.fallback = "straight"
            return { leg }
        end
    end
    return nil, { code = "NO_PATH", message = L.ROUTE_NO_PATH, partial = { expansions = ctx.expansions, cap = reason == "CAP" or nil } }
end









local function positionHeight(p)
    if type(p.z) == "number" and not p.zInferred then return p.z end
    local G = Graph()
    if type(p.poiIndex) == "number" then



        local z = G:PoiLevelHeight(p.poiIndex)
        if z then return z end
    end
    if type(p.taxiNodeID) == "number" then
        local key = G:TaxiNodeKey(p.taxiNodeID)
        if key then return G:NodeHeight(key) end
    end
    return nil
end















Router.LIFT_FIND_YARDS = 26




Router.LIFT_STEP_REACH = 16
Router.LIFT_STEP_MARGIN = 1.5



function Router._liftSpots(inst, x, y)
    local G, spots = Graph(), {}
    for _, item in ipairs(G:Nearest(inst, x, y, Router.LIFT_FIND_YARDS, 64) or {}) do
        local key, lift = item.key, false
        G:Neighbors(key, function(_, kind) if kind == 11 then lift = true end end)
        if lift then
            local landingZ = G:NodeHeight(key)
            local _, landingIndoor = G:NodePlace(key)
            G:Neighbors(key, function(to, kind)
                if kind == 11 then return end
                local _, sx, sy = G:NodePos(to)
                local z = G:NodeHeight(to) or landingZ
                local _, indoor = G:NodePlace(to)
                if sx and z then spots[#spots + 1] = { x = sx, y = sy, z = z, landing = key, d = item.dist, roofed = (indoor or landingIndoor) or nil } end
            end)
        end
    end
    table.sort(spots, function(a, b) return a.d < b.d end)
    return spots
end


function Router._liftLevel(p)
    if type(p) ~= "table" or type(p.inst) ~= "number" or type(p.x) ~= "number" or type(p.y) ~= "number" then return nil end
    if type(p.place) == "table" and p.place.indoor then return nil end
    local spots, D = Router._liftSpots(p.inst, p.x, p.y), Coords().Distance
    local best, bestD
    for _, s in ipairs(spots) do
        if s.roofed then return nil end
        s.from = D(p.x, p.y, s.x, s.y)
        if not bestD or s.from < bestD then best, bestD = s, s.from end
    end
    if not best or bestD > Router.LIFT_STEP_REACH then return nil end
    for _, s in ipairs(spots) do
        if abs(s.z - best.z) > Router.HEIGHT_GUESS_SPREAD and s.from - bestD < Router.LIFT_STEP_MARGIN then return nil end
    end
    return best.z
end

local function normalizePos(p)
    if type(p) ~= "table" then return nil end
    local inst, x, y = p.inst, p.x, p.y
    if (inst == nil or x == nil or y == nil) and p.map and p.mx and p.my then
        inst, x, y = Coords().MapToWorld(p.map, p.mx, p.my)
    end
    if type(inst) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then return nil end
    return { inst = inst, x = x, y = y, z = positionHeight(p), map = p.map, mx = p.mx, my = p.my, name = p.name,
             poiIndex = p.poiIndex, floor = p.floor, indoor = p.indoor, kind = p.kind,
             zHint = type(p.zHint) == "number" and p.zHint or nil, place = type(p.place) == "table" and p.place or nil,
             original = p }
end

local function effectiveAccess(access, variant)
    local eff = Util.ShallowCopy(access)
    local t = {}
    for k, v in pairs(access.transports or {}) do t[k] = v end
    if variant == "no_flight" then t.taxi = false end
    if variant == "no_boat" then t.boat, t.zeppelin = false, false end
    eff.transports = t
    return eff
end




function Router._placeKey(p)
    local name = p.place and p.place.name
    return type(name) == "string" and name or "-"
end

local function posKey(p)
    local key = string.format("%d:%d:%d:%s", p.inst, Util.Round(p.x), Util.Round(p.y), tostring(p.poiIndex or "-"))
    if p.place then key = key .. ":" .. Router._placeKey(p) end
    return key
end




local function levelBucket(p)
    local z = p.z
    if type(z) ~= "number" then z = p.zHint end
    if type(z) ~= "number" then return "-" end
    return tostring(floor(z / Router.HEIGHT_GUESS_SPREAD))
end

local function cellKey(p)
    return string.format("%d:%d:%d:%s:%s", p.inst, floor(p.x / Const.ORIGIN_CELL_YARDS), floor(p.y / Const.ORIGIN_CELL_YARDS), levelBucket(p),
        Router._placeKey(p))
end

local function requestSuffix(request)
    return string.format("%s:%s:%s:%s", tostring(request.access and request.access.hash or "-"), request.variant or "fastest",
        tostring(request.maxSeconds or "-"), tostring(request.fallbackCapYards or "-"))
end






local function fallbackCapped(request, ctx, legs)
    local cap = tonumber(request.fallbackCapYards)
    if not cap or ctx.fallback ~= "straight" then return false end
    local yards = 0
    for _, leg in ipairs(legs) do yards = yards + (leg.yards or 0) end
    return yards > cap
end






local function waitsForCooldown(legs)
    for _, leg in ipairs(legs) do
        if (leg.kind == "hearth" or leg.kind == "spell") and (leg.wait or 0) > 0 then return true end
    end
    return false
end


function Router:CacheKey(request)
    local origin = normalizePos(request.origin)
    if not origin then return nil end
    local parts = { "R", cellKey(origin) }
    for _, stop in ipairs(request.stops or {}) do
        local p = normalizePos(stop)
        if not p then return nil end
        parts[#parts + 1] = posKey(p)
    end
    parts[#parts + 1] = requestSuffix(request)
    return table.concat(parts, "|")
end



local function segmentKey(origin, stop, request, exactOrigin)
    local from = exactOrigin and ("P" .. posKey(origin) .. ":" .. levelBucket(origin)) or cellKey(origin)
    return "S|" .. from .. "|" .. posKey(stop) .. "|" .. requestSuffix(request)
end

local function newLRU(size) return { size = size, map = {}, order = {} } end

local function lruTouch(lru, key)
    local order = lru.order
    for i = 1, #order do
        if order[i] == key then
            table.remove(order, i)
            break
        end
    end
    order[#order + 1] = key
end

local function lruGet(lru, key)
    local entry = lru.map[key]
    if not entry then return nil end
    lruTouch(lru, key)
    return entry
end

local function lruPut(lru, key, value)
    if not lru.map[key] then
        lru.order[#lru.order + 1] = key
    else
        lruTouch(lru, key)
    end
    lru.map[key] = value
    while #lru.order > lru.size do
        local old = table.remove(lru.order, 1)
        lru.map[old] = nil
    end
end

Router.routeCache = newLRU(Router.CACHE_SIZE)
Router.segmentCache = newLRU(Router.CACHE_SIZE)
Router.cacheHash = nil




Router.cacheEpoch = 0
Router.dataEpoch = 0

function Router:InvalidateCache()
    self.routeCache = newLRU(self.CACHE_SIZE)
    self.segmentCache = newLRU(self.CACHE_SIZE)
    Router.cacheEpoch = Router.cacheEpoch + 1
end

local function syncCacheHash(hash)
    if Router.cacheHash ~= hash then
        Router:InvalidateCache()
        Router.cacheHash = hash
    end
end

function Router:GetCached(key)
    if not key then return nil end
    return lruGet(self.routeCache, key)
end

function Router:CacheSize()
    return #self.routeCache.order, #self.segmentCache.order
end




local function shallowLeg(leg)
    local copy = {}
    for k, v in pairs(leg) do
        if not (type(k) == "string" and k:sub(1, 1) == "_") then copy[k] = v end
    end
    return copy
end









local function routeCopy(route, stops)
    local copy = {}
    for k, v in pairs(route) do copy[k] = v end
    copy.legs, copy.steps, copy.calibrated, copy.measured = {}, {}, nil, nil
    for i, leg in ipairs(route.legs) do copy.legs[i] = shallowLeg(leg) end
    if stops and route.stops then
        copy.stops = {}
        for i, stop in ipairs(route.stops) do
            local own = {}
            for k, v in pairs(stop) do own[k] = v end
            if stops[i] then own.dest = stops[i].original or stops[i] end
            copy.stops[i] = own
        end
    end
    return copy
end

local function appendSegment(route, seg, stopIndex, stop, cached)
    local legFrom = #route.legs + 1
    for _, leg in ipairs(seg.legs) do
        local copy = shallowLeg(leg)
        copy.stopIndex = stopIndex
        route.legs[#route.legs + 1] = copy
    end
    route.stops[stopIndex] = { dest = stop.original or stop, legFrom = legFrom, legTo = #route.legs, inst = stop.inst, x = stop.x, y = stop.y,
                               attachInfo = seg.attachInfo }
    if seg.fallback then
        route.fallbackStops[#route.fallbackStops + 1] = stopIndex
    end
    local info = seg.attachInfo
    if info then


        local ri = route.attachInfo
        if not ri then
            ri = { originRadius = info.originRadius, destRadius = info.destRadius, originAttached = info.originAttached,
                   destAttached = info.destAttached, widened = info.widened or false }
            route.attachInfo = ri
        else
            if (info.destRadius or 0) > (ri.destRadius or 0) then ri.destRadius = info.destRadius end
            if info.destAttached == false then ri.destAttached = false end
            if info.widened then ri.widened = true end
        end
    end

    if not cached then route.expansions = route.expansions + (seg.expansions or 0) end
end










function Router._setGuarded(ctx)
    if ctx.guardedReady then return end
    ctx.guardedReady = true
    local C = Cost()
    local index = C.GuardedIndex(ctx.access)
    if not index then
        ctx.guarded = nil
        return
    end
    local held = {}
    if ctx.dest and not ctx.goals then C.GuardedHold(index, ctx.dest.inst, ctx.dest.x, ctx.dest.y, held) end
    ctx.guarded = C.GuardedExcept(index, held)
end








Router.OFF_ROAD_KINDS = { [3] = true, [14] = true, [15] = true, [19] = true, [22] = true, [23] = true }
function Router._guardedNotes(route, access)
    local C = Cost()
    local index = C.GuardedIndex(access)
    if not index then return end
    local legs = route.legs or {}
    local held = {}
    local function hold(inst, x, y)
        if inst then C.GuardedHold(index, inst, x, y, held) end
    end
    local firstPts, lastPts = legs[1] and legs[1].points, legs[#legs] and legs[#legs].points
    if firstPts and firstPts[1] then hold(legs[1].inst, firstPts[1].x, firstPts[1].y) end
    if lastPts and lastPts[#lastPts] then hold(legs[#legs].inst, lastPts[#lastPts].x, lastPts[#lastPts].y) end
    if route.origin then hold(route.origin.inst, route.origin.x, route.origin.y) end
    for _, stop in ipairs(route.stops or {}) do hold(stop.inst, stop.x, stop.y) end
    local passed, named = {}, {}
    for _, leg in ipairs(legs) do
        local pts = leg.kind == "walk" and leg.points
        leg.guardedAt, leg.guardedRoundAt = nil, nil
        if pts then



            local zs = {}
            for i = 2, #pts - 1 do
                local z = pts[i].z
                for d = 1, #pts do
                    if z ~= nil then break end
                    local a, b = pts[i - d], pts[i + d]
                    z = (a and i - d > 1 and a.z) or (b and i + d < #pts and b.z) or nil
                    if not a and not b then break end
                end
                zs[i] = z
            end
            local inside
            for i = 2, #pts do
                local a, b = pts[i - 1], pts[i]
                local share, place = C.GuardedShare(index, leg.inst, a.x, a.y, b.x, b.y, zs[i - 1], zs[i])
                if share <= 0 or held[place] then
                    inside = nil
                else
                    if inside ~= place then
                        leg.guardedAt = leg.guardedAt or {}
                        leg.guardedAt[i - 1] = place.name or false
                    end
                    inside = place
                    if not named[place] then
                        named[place] = true
                        passed[#passed + 1] = place.name or false
                    end
                end
            end
            local i = 3
            while i <= #pts do
                if Router.OFF_ROAD_KINDS[pts[i].k] and not Router.OFF_ROAD_KINDS[pts[i - 1].k] then
                    local j = i
                    while j < #pts and Router.OFF_ROAD_KINDS[pts[j + 1].k] do j = j + 1 end
                    if j < #pts then



                        local a, b = pts[i - 1], pts[j]
                        local share, place = C.GuardedShare(index, leg.inst, a.x, a.y, b.x, b.y, zs[i - 1], zs[j], true)
                        if share == 0 and FGPS.Graph then
                            local G = FGPS.Graph
                            local dx, dy = b.x - a.x, b.y - a.y
                            local crow = sqrt(dx * dx + dy * dy)
                            if crow >= 80 and crow <= 1800 then
                                local ha = G:Nearest(leg.inst, a.x, a.y, 6, 1)
                                local hb = G:Nearest(leg.inst, b.x, b.y, 6, 1)
                                local ka, kb = ha[1] and ha[1].key, hb[1] and hb[1].key
                                if ka and kb and ka ~= kb then
                                    local maxDist = crow * 2.2
                                    local function roadTree(root)
                                        local prev, dist, q, h = { [root] = 0 }, { [root] = 0 }, { root }, 1
                                        while h <= #q and #q <= 256 do
                                            local u = q[h]
                                            h = h + 1
                                            local du = dist[u]
                                            G:Neighbors(u, function(nb, kind, yd)
                                                if prev[nb] == nil and (kind == 4 or kind == 17 or kind == 18) then
                                                    local nd = du + (yd or 1)
                                                    if nd <= maxDist then
                                                        prev[nb], dist[nb] = u, nd
                                                        q[#q + 1] = nb
                                                    end
                                                end
                                            end)
                                        end
                                        return prev, dist, q
                                    end
                                    local prevA, distA, qA = roadTree(ka)
                                    local bestCost, bestU, bestV = maxDist + 1, nil, nil
                                    if prevA[kb] ~= nil then
                                        bestU, bestV = kb, kb
                                    else
                                        local prevB, distB, qB = roadTree(kb)
                                        local cellsB, vxOf, vyOf = {}, {}, {}
                                        for ib = 1, #qB do
                                            local v = qB[ib]
                                            local _, vx, vy = G:NodePos(v)
                                            if vx then
                                                vxOf[v], vyOf[v] = vx, vy
                                                local ck = floor(vx / 90) * 131072 + floor(vy / 90)
                                                local list = cellsB[ck]
                                                if not list then list = {}; cellsB[ck] = list end
                                                list[#list + 1] = v
                                            end
                                        end
                                        for ia = 1, #qA do
                                            local u = qA[ia]
                                            if prevB[u] ~= nil then
                                                local tot = distA[u] + distB[u]
                                                if tot < bestCost then bestCost, bestU, bestV = tot, u, u end
                                            else
                                                local _, ux, uy = G:NodePos(u)
                                                if ux then
                                                    local cx, cy = floor(ux / 90), floor(uy / 90)
                                                    for dcx = -1, 1 do
                                                        for dcy = -1, 1 do
                                                            local list = cellsB[(cx + dcx) * 131072 + (cy + dcy)]
                                                            if list then
                                                                for k = 1, #list do
                                                                    local v = list[k]
                                                                    local dxv, dyv = vxOf[v] - ux, vyOf[v] - uy
                                                                    local gap = sqrt(dxv * dxv + dyv * dyv)
                                                                    if gap <= 85 then
                                                                        local tot = distA[u] + gap + distB[v]
                                                                        if tot < bestCost then bestCost, bestU, bestV = tot, u, v end
                                                                    end
                                                                end
                                                            end
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                        if bestU then
                                            local cur = bestV
                                            while cur ~= kb and cur ~= 0 do
                                                local nxt = prevB[cur]
                                                if nxt and nxt ~= 0 then
                                                    local _, ux, uy = G:NodePos(cur)
                                                    local _, vx, vy = G:NodePos(nxt)
                                                    if ux and vx then
                                                        local s2, pl2 = C.GuardedShare(index, leg.inst, ux, uy, vx, vy, G:NodeHeight(cur), G:NodeHeight(nxt), true)
                                                        if s2 > 0 and not held[pl2] and not named[pl2] then
                                                            share, place = s2, pl2
                                                            break
                                                        end
                                                    end
                                                end
                                                cur = nxt or 0
                                            end
                                        end
                                    end
                                    if bestU and share == 0 then
                                        if bestU ~= bestV then
                                            local _, ux, uy = G:NodePos(bestU)
                                            local _, vx, vy = G:NodePos(bestV)
                                            if ux and vx then
                                                local s2, pl2 = C.GuardedShare(index, leg.inst, ux, uy, vx, vy, G:NodeHeight(bestU), G:NodeHeight(bestV), true)
                                                if s2 > 0 and not held[pl2] and not named[pl2] then share, place = s2, pl2 end
                                            end
                                        end
                                        local cur = bestU
                                        while share == 0 and cur ~= ka and cur ~= 0 do
                                            local p = prevA[cur]
                                            if p and p ~= 0 then
                                                local _, ux, uy = G:NodePos(p)
                                                local _, vx, vy = G:NodePos(cur)
                                                if ux and vx then
                                                    local s2, pl2 = C.GuardedShare(index, leg.inst, ux, uy, vx, vy, G:NodeHeight(p), G:NodeHeight(cur), true)
                                                    if s2 > 0 and not held[pl2] and not named[pl2] then
                                                        share, place = s2, pl2
                                                        break
                                                    end
                                                end
                                            end
                                            cur = p or 0
                                        end
                                    end
                                end
                            end
                        end
                        if share > 0 and not held[place] and not named[place] then
                            leg.guardedRoundAt = leg.guardedRoundAt or {}
                            leg.guardedRoundAt[i - 1] = place.name or false
                        end
                    end
                    i = j + 1
                else
                    i = i + 1
                end
            end
        end
    end
    if #passed > 0 then route.guardedPassed = passed end
end

local function finalizeRoute(route, request, access)
    local C = Cost()
    local totalSeconds, totalYards, unverified, verified, transfers = 0, 0, 0, 0, 0
    local road, mesh, street, terrainRoad, terrainGround = 0, 0, 0, 0, 0
    local surface, surfaceSwim, roadShaped, dock, hazard = 0, 0, 0, 0, nil
    local legs = route.legs
    for i, leg in ipairs(legs) do
        totalSeconds = totalSeconds + (leg.seconds or 0)
        totalYards = totalYards + (leg.yards or 0)
        unverified = unverified + (leg.unverifiedYards or 0)
        verified = verified + (leg.verifiedYards or 0)
        road = road + (leg.roadYards or 0)
        roadShaped = roadShaped + (leg.roadShapedYards or 0)
        mesh = mesh + (leg.meshYards or 0)
        dock = dock + (leg.dockYards or 0)
        street = street + (leg.streetYards or 0)
        terrainRoad = terrainRoad + (leg.terrainRoadYards or 0)
        terrainGround = terrainGround + (leg.terrainGroundYards or 0)
        surface = surface + (leg.surfaceYards or 0)
        surfaceSwim = surfaceSwim + (leg.surfaceSwimYards or 0)
        for liquid, yards in pairs(leg.hazardYards or {}) do
            hazard = hazard or {}
            hazard[liquid] = (hazard[liquid] or 0) + yards
        end
        if leg.kind ~= "walk" then
            local prev = legs[i - 1]
            if not prev or prev.kind ~= leg.kind or prev.transportID ~= leg.transportID or leg.kind == "hearth" or leg.kind == "spell" then
                transfers = transfers + 1
            end
        end
    end
    route.totalSeconds, route.totalYards = totalSeconds, totalYards
    route.unverifiedYards, route.verifiedYards, route.transfers = unverified, verified, transfers

    route.roadYards, route.roadShapedYards = road, roadShaped

    route.streetYards = street


    route.terrainRoadYards, route.terrainGroundYards = terrainRoad, terrainGround

    route.surfaceYards, route.surfaceSwimYards = surface, surfaceSwim

    route.hazardYards = hazard



    route.meshYards, route.dockYards = mesh, dock

    if #legs == 1 and legs[1].kind == "walk" and legs[1].straight then route.fallback = "straight" else route.fallback = nil end
    route.assumptions = { groundSpeed = C.GroundSpeed(access), speedLabel = C.SpeedLabel(access), mountSpeed = access.mountSpeed,
                          hasMount = access.hasMount, taxi = access.transports and access.transports.taxi ~= false }
    Router._guardedNotes(route, access)
    route.explain = C.Explain(route)
    route.createdAt = GetTime and GetTime() or 0
    Router.nextRouteID = Router.nextRouteID + 1
    route.id = Router.nextRouteID
    if #route.fallbackStops == 0 then route.fallbackStops = nil end
    return route
end






local function searchVariant(request, access)
    local variant = request.variant or "fastest"
    if access.preferRoads then

        return access.roadShortcuts and "prefer_roads" or "roads_only"
    end
    return variant
end






Router.GOAL_KEYS = { DEST, -3, -4, -5, -6, -7, -8, -9 }

function Router._bindGoal(ctx, goal)
    local s = ctx._gs
    if not s then s = {}; ctx._gs = s end
    s.on = true
    s.dest, s.destKey = ctx.dest, ctx.destKey
    s.destEnclosed, s.destStacked = ctx.destEnclosed, ctx.destStacked
    s.destZ, s.destGuessed = ctx.destZ, ctx.destGuessed
    s.destLow, s.destHigh = ctx.destLow, ctx.destHigh
    s.destLowG, s.destHighG = ctx.destLowG, ctx.destHighG
    s.destZg, s.cityTrip = ctx.destZg, ctx.cityTrip
    s.destRoadNode, s.destHubKey, s.destAttach = ctx.destRoadNode, ctx.destHubKey, ctx.destAttach


    s.destPos = ctx.vpos[DEST]
    ctx.vpos[DEST] = goal.dest
    ctx.dest, ctx.destKey = goal.dest, goal.key
    ctx.destEnclosed, ctx.destStacked = goal.enclosed, goal.stacked
    ctx.destZ, ctx.destGuessed = goal.z, goal.guessed
    ctx.destLow, ctx.destHigh = goal.low, goal.high
    ctx.destLowG, ctx.destHighG = goal.lowG, goal.highG
    ctx.destZg, ctx.cityTrip = goal.zg, goal.cityTrip
    ctx.destRoadNode, ctx.destHubKey, ctx.destAttach = goal.roadNode, goal.hubKey, goal.attach
end

function Router._unbindGoal(ctx, goal)
    local s = ctx._gs
    if not s or not s.on then return end
    if goal then goal.roadNode = ctx.destRoadNode end
    ctx.vpos[DEST] = s.destPos
    ctx.dest, ctx.destKey = s.dest, s.destKey
    ctx.destEnclosed, ctx.destStacked = s.destEnclosed, s.destStacked
    ctx.destZ, ctx.destGuessed = s.destZ, s.destGuessed
    ctx.destLow, ctx.destHigh = s.destLow, s.destHigh
    ctx.destLowG, ctx.destHighG = s.destLowG, s.destHighG
    ctx.destZg, ctx.cityTrip = s.destZg, s.cityTrip
    ctx.destRoadNode, ctx.destHubKey, ctx.destAttach = s.destRoadNode, s.destHubKey, s.destAttach
    s.on = false
end

function Router._goalH(ctx, key)
    if key == ORIGIN or (ctx.goalSet and ctx.goalSet[key]) or Router._noEstimate then return 0, 0 end
    local s = slotOf[key]
    local memo = Router._hMemo
    local known = s and memo[s]



    local open = ctx.goalOpen
    if known ~= nil and not open then return known, Router._hMemoHonest[s] or 0 end
    local inst, x, y = posOf(ctx, key)
    if not x then return 0, 0 end
    local goals = ctx.goals
    local speed = ctx.maxSpeed
    if not speed or speed <= 0 then return 0, 0 end
    local ground = ctx.flightGround







    local h = known
    if h == nil then
        local plain, walked = huge, huge
        for i = 1, #goals do
            local goal = goals[i]
            if inst == goal.dest.inst then
                local a = estimateFrom(goal.fastLinks, speed, x, y, goal.dest)
                if a < plain then plain = a end
                if ground then
                    a = estimateFrom(goal.fastLinks, ground, x, y, goal.dest)
                    if a < walked then walked = a end
                end
            else
                local a = goal.outsideRest or 0
                if a < plain then plain = a end
                if a < walked then walked = a end
            end
        end
        if ground then
            local via = Router._flightH(ctx, x, y, ctx.goalFlight)
            if via and via < walked then walked = via end
            if walked < huge and walked > plain then plain = walked end
        end
        h = (plain < huge) and plain or 0
        if s then
            memo[s] = h
            if ctx.maxSeconds then Router._hMemoHonest[s] = h end
        end
    end
    if not open then return h, h end

    local rest = huge
    for i = 1, #goals do
        local goal = goals[i]
        if not goal.reached then
            local a
            if inst == goal.dest.inst then
                a = estimateFrom(goal.fastLinks, speed, x, y, goal.dest)
                if ground then
                    local t = estimateFrom(goal.fastLinks, ground, x, y, goal.dest)
                    local via = goal.flightHubs and Router._flightH(ctx, x, y, goal.flightHubs)
                    if via and via < t then t = via end
                    if t > a then a = t end
                end
            else
                a = goal.outsideRest or 0
            end
            if a < rest then rest = a end
        end
    end
    if rest < h then rest = h end
    return h, (rest < huge) and rest or h
end














function Router._goalBound(ctx)
    local limit, totals = ctx.goalLimit, {}
    for _, goal in ipairs(ctx.goals) do
        if goal.reached and goal.legs then
            local s = 0
            for _, leg in ipairs(goal.legs) do s = s + (leg.seconds or 0) end
            totals[#totals + 1] = s
        end
    end
    if #totals < limit then return nil end
    table.sort(totals)
    local b = totals[limit]
    return b + b * 1e-9 + 8 * Const.UNVERIFIED_FACTOR * Cost().GroundSpeed(ctx.access) / (Const.RUN_SPEED * Const.SWIM_SPEED)
end








function Router._goalsLeftOut(ctx)
    local bound = huge
    for _, goal in ipairs(ctx.goals) do
        if goal.reached and goal.legs then
            local s = 0
            for _, leg in ipairs(goal.legs) do s = s + (leg.seconds or 0) end
            if s < bound then bound = s end
        end
    end
    for i, goal in ipairs(ctx.goals) do
        if not goal.reached then
            local otherwise = ctx.goalOtherwise and ctx.goalOtherwise[i] or 0
            if ctx.access.allowUnverified ~= false and goal.dest.inst == ctx.origin.inst then
                Router._bindGoal(ctx, goal)
                local leg = Router._straightLeg(ctx)
                Router._unbindGoal(ctx, goal)
                if leg then otherwise = leg.seconds or 0 end
            end
            if not (type(otherwise) == "number" and otherwise > bound) then return true end
        end
    end
    return false
end



function Router._recountUnder(ctx)
    local bound, seen, n = ctx.maxSeconds, {}, 0
    local q = Router._lines
    q.nu = 0
    clearTable(q.ug)
    for i = 1, heapSize do
        local key = heapKeys[i]
        local s = slotOf[key]
        if key <= Router.LINE_BASE and key > BOARD_BASE then
            local j = Router.LINE_BASE - key
            q.u[j] = nil
            local gi = q.goal[j]
            if gi and q.hs[j] and q.hs[j] <= bound and not closed[ctx.goals[gi].key] then q.u[j], q.nu, q.ug[gi] = true, q.nu + 1, (q.ug[gi] or 0) + 1 end
        elseif s and not closed[key] and not seen[s] then
            seen[s] = true
            local _, hh = heuristic(ctx, key)
            local under = ((honestArr[s] or 0) + (hh or 0) <= bound) and 1 or 0
            local packed = packArr[s] or 0
            local old = floor(packed / 32768) % 2
            if under ~= old then packArr[s] = packed + (under - old) * 32768 end
            n = n + under
        end
    end
    underCount = n
end

function Router._edgesFrom(startKey)
    local edges = {}
    local key = startKey
    local guard = 0
    while key ~= ORIGIN do
        local from, kind, yards, seconds, penalty, mode, tid, via = Router._edgeOf(key)
        if from == nil then return nil end
        local to = nodeOf(key)
        if to <= -2 and to > -10 then to = DEST end
        edges[#edges + 1] = { from = nodeOf(from), to = to, kind = kind, yards = yards, seconds = seconds,
                              penalty = penalty, mode = mode, transportID = tid, via = via }
        key = from
        guard = guard + 1
        if guard > 1000000 then return nil end
    end
    local n = #edges
    for i = 1, floor(n / 2) do edges[i], edges[n - i + 1] = edges[n - i + 1], edges[i] end
    return edges
end

function Router._closeGoal(ctx, key)
    local goal = ctx.goalSet[key]
    if goal.reached then return ctx.goalsLeft <= 0 end
    goal.reached = true
    ctx.goalsLeft = ctx.goalsLeft - 1
    local edges = Router._edgesFrom(key)
    Router._bindGoal(ctx, goal)
    local built
    if edges then
        local ok, result = Scheduler().Protect(buildLegs, ctx, edges)
        if ok then
            built = result
        elseif not goal.failed then
            goal.failed = true
            if FGPS.Log then FGPS.Log:Error("Goal leg build failed: %s", tostring(result)) end
        end
    end
    Router._unbindGoal(ctx, goal)
    if type(built) == "table" and #built > 0 then
        goal.legs = built
        if #built == 1 and built[1].straight then goal.fallback = "straight" end
    end
    return ctx.goalsLeft <= 0
end

function Router._goalAttach(ctx, key, g)
    local goals = ctx.goals
    for i = 1, #goals do
        local goal = goals[i]
        if not closed[goal.key] then
            local cand = goal.attach and goal.attach[key]
            if cand then
                Router._bindGoal(ctx, goal)
                local secs, yards, charged = attachCost(ctx, cand, key, destHeightFrom(ctx, cand.footZ), ctx.destStacked, ctx.dest.x, ctx.dest.y)
                if secs then relax(ctx, goal.key, g + charged, key, KIND_ATTACH, yards, secs, 0, "ground", nil, VIA_ATTACH) end
                Router._unbindGoal(ctx, goal)
            end
        end
    end
end

function Router._goalsDirect(ctx, fromKey, g, inst, x, y, fromZ, testZ)
    local goals = ctx.goals
    local D = Coords().Distance
    for i = 1, #goals do
        local goal = goals[i]
        local dest = goal.dest
        if not closed[goal.key] and inst == dest.inst then
            local d = D(x, y, dest.x, dest.y)
            if d <= ctx.maxStraight and d <= (Router._lineReach(inst) or d) then
                local least = g + Router._lineBound(ctx, d)
                local known = Router._gAt(goal.key)

                if known and least >= known then least = nil end
                if least and Router.LAZY_LINES then


                    local q = Router._lines
                    local j = q.n + 1
                    q.n = j
                    q.from[j], q.g[j], q.f[j], q.x[j], q.y[j], q.d[j] = fromKey, g, least, x, y, d
                    q.z[j], q.zt[j], q.goal[j] = fromZ or false, testZ or false, i
                    local s = slotOf[fromKey]
                    local hs = ((s and honestArr[s]) or 0) + d / ctx.maxSpeed
                    q.hs[j], q.u[j] = hs, nil
                    if ctx.maxSeconds and hs <= ctx.maxSeconds then q.u[j], q.nu, q.ug[i] = true, q.nu + 1, (q.ug[i] or 0) + 1 end
                    heapPush(Router.LINE_BASE - j, least)
                elseif least and not Router._swimRefused(inst, x, y, dest.x, dest.y, false) then
                    Router._bindGoal(ctx, goal)
                    Router._judgeLine(ctx, fromKey, g, inst, x, y, fromZ, testZ, d)
                    Router._unbindGoal(ctx, goal)
                end
            end
        end
    end
end

function Router._prepareGoal(ctx, dest, key, city)
    ctx.cityTrip = city
    ctx.dest = dest
    ctx.destRoadNode = nil
    local attach, count, radius, enclosed = attachFor(ctx, dest, true)
    local goal = { key = key, dest = dest, attach = attach or {}, enclosed = enclosed, cityTrip = city,
                   count = count, radius = radius }
    goal.z = dest.z
    if not goal.z then
        goal.z = guessHeight(attach, false)
        goal.guessed = goal.z ~= nil or nil
        if not goal.z and levelsApart(attach) then
            goal.low, goal.high = levelRange(attach)
            goal.lowG, goal.highG = levelRange(attach, true)
        end
        if not goal.z and not goal.lowG then goal.zg = guessHeight(attach, false, true) end
    end
    goal.stacked = goal.z ~= nil and levelsApart(attach) or nil
    local taxiID = dest.original and dest.original.taxiNodeID
    if type(taxiID) ~= "number" then taxiID = dest.taxiNodeID end
    goal.hubKey = type(taxiID) == "number" and Graph():TaxiNodeKey(taxiID) or nil
    if goal.hubKey and goal.stacked then ctx.goalHubs[goal.hubKey] = true end
    ctx.vpos[key] = { inst = dest.inst, x = dest.x, y = dest.y, map = dest.map, z = goal.z }
    return goal
end

function Router._finishGoal(ctx, goal, request, access)


    if (goal.cut or goal.failed) and not goal.legs then return nil end
    if not goal.legs then

        if ctx.access.allowUnverified ~= false and goal.dest.inst == ctx.origin.inst then
            Router._bindGoal(ctx, goal)
            local leg = straightLeg(ctx)
            Router._unbindGoal(ctx, goal)
            if leg then goal.legs = { leg } end
        end
    end
    if not goal.legs or #goal.legs == 0 then return nil end
    local dest = goal.dest
    local route = { variant = request.variant, legs = goal.legs, steps = {},
                    stops = { { dest = dest.original or dest, legFrom = 1, legTo = #goal.legs, inst = dest.inst, x = dest.x, y = dest.y } },
                    fallback = nil, fallbackStops = {}, expansions = ctx.expansions, reason = request.reason,
                    origin = { inst = ctx.origin.inst, x = ctx.origin.x, y = ctx.origin.y } }
    return finalizeRoute(route, request, access)
end





function Router._goalsUnlessSlowerThanWithout(ctx)
    if ctx.variant ~= "roads_only" and ctx.variant ~= "prefer_roads" then return nil end
    local function total(list)
        local s = 0
        for i = 1, #list do s = s + (list[i].seconds or 0) end
        return s
    end
    local redo, bound = {}, 0
    for _, goal in ipairs(ctx.goals) do
        local first = goal.legs and goal.legs[1]
        if first and (first.kind == "hearth" or first.kind == "spell") then
            local seconds = total(goal.legs)
            redo[#redo + 1] = { goal = goal, legs = goal.legs, fallback = goal.fallback, seconds = seconds }
            if seconds > bound then bound = seconds end
        end
    end
    if #redo == 0 then return nil end

    for _, goal in ipairs(ctx.goals) do goal.reached = true end
    for _, r in ipairs(redo) do r.goal.reached, r.goal.legs, r.goal.fallback = nil, nil, nil end
    local teleports, maxSeconds, expansions = ctx.teleports, ctx.maxSeconds, ctx.expansions or 0
    ctx.teleports, ctx.maxSeconds, ctx.goalsLeft, ctx.goalLimit = {}, bound, #redo, nil
    local _, reason = search(ctx)
    ctx.teleports, ctx.maxSeconds = teleports, maxSeconds
    ctx.expansions = expansions + (ctx.expansions or 0)
    for _, r in ipairs(redo) do
        local other = r.goal.legs
        if reason == "CANCELLED" or not (other and #other > 0 and total(other) <= r.seconds) then
            r.goal.legs, r.goal.fallback = r.legs, r.fallback
        end
    end
    return reason
end







function Router._goalsInTheTownHere(ctx)
    local C, o = Cost(), ctx.origin
    local index = ctx.guarded
    if not index or not (o and o.inst) then return nil end
    local here = {}
    C.GuardedHold(index, o.inst, o.x, o.y, here)
    if next(here) == nil then return nil end
    local redo = {}
    for _, goal in ipairs(ctx.goals) do
        local d = goal.dest
        local at = d and C.GuardedAt(index, d.inst, d.x, d.y)
        if at and here[at] then
            redo[#redo + 1] = { goal = goal, legs = goal.legs, fallback = goal.fallback, reached = goal.reached, cut = goal.cut }
        end
    end
    if #redo == 0 then return nil end
    local reached = {}
    for i, goal in ipairs(ctx.goals) do reached[i] = goal.reached goal.reached = true end
    for _, r in ipairs(redo) do r.goal.reached, r.goal.legs, r.goal.fallback = nil, nil, nil end
    local expansions, goalLimit = ctx.expansions or 0, ctx.goalLimit
    ctx.guarded, ctx.goalsLeft, ctx.goalLimit = C.GuardedExcept(index, here), #redo, nil
    local _, reason = search(ctx)
    ctx.guarded, ctx.goalLimit = index, goalLimit
    ctx.expansions = expansions + (ctx.expansions or 0)
    for i, goal in ipairs(ctx.goals) do goal.reached = reached[i] end
    local function total(list)
        local s = 0
        for i = 1, #list do s = s + (list[i].seconds or 0) end
        return s
    end
    for _, r in ipairs(redo) do
        local legs = r.goal.legs


        if reason ~= "CANCELLED" and legs and #legs > 0 and not (r.legs and #r.legs > 0 and total(r.legs) < total(legs)) then
            r.goal.reached, r.goal.cut = true, nil
        elseif reason ~= "CANCELLED" and r.goal.failed and not (r.legs and #r.legs > 0) then
            r.goal.reached, r.goal.cut = true, nil
        else
            r.goal.legs, r.goal.fallback, r.goal.reached, r.goal.cut = r.legs, r.fallback, r.reached, r.cut
        end
    end
    return reason
end

function Router._computeGoals(handle)
    local request, access = handle.request, handle.access
    local variant = searchVariant(request, access)
    local origin, stops = handle.origin, handle.stops
    local maxStraight = (access.allowUnverified ~= false) and Router.MaxStraightYards() or 0
    local hubReach = Router.HUB_REACH_YARDS
    if hubReach > maxStraight then hubReach = maxStraight end
    local ctx = { access = access, variant = variant, ride = request.variant or "fastest", maxSeconds = 1e12, origin = origin, dest = stops[1],
                  vpos = { [ORIGIN] = origin }, originAttach = {}, destAttach = {}, teleAttach = {}, teleEnclosed = {},
                  teleports = {}, hubAttach = {}, hubOK = {}, hubCells = {}, vetted = {}, goals = {}, goalSet = {},
                  goalHubs = {}, maxStraight = maxStraight, hubReach = hubReach, expansions = 0 }

    local limit = request.goalLimit
    if type(limit) == "number" and limit >= 1 then
        ctx.goalLimit, ctx.goalCeiling, ctx.goalOtherwise = floor(limit), ctx.maxSeconds, request.goalOtherwise
    end
    local ends = {}
    for _, stop in ipairs(stops) do ends[#ends + 1] = stop end
    ctx.insideStarts, ctx.insideEnds = Router._insideEnds({ origin }), Router._teleportFeeders(Router._insideEnds(ends))
    ctx.straightRate = (Cost().EdgeSeconds(KIND_ATTACH, 1, access) or 0) * Cost().RoadFactor(variant, KIND_ATTACH)
    local cities, nStops = {}, #stops
    local goalKeys = Router.GOAL_KEYS
    if nStops > #goalKeys then nStops = #goalKeys end
    for i = 1, nStops do
        local stop = stops[i]
        cities[i] = origin.inst == stop.inst and inCapital(origin.inst, origin.x, origin.y) and inCapital(stop.inst, stop.x, stop.y) or nil
    end
    local same = true
    for i = 2, nStops do if cities[i] ~= cities[1] then same = false end end
    ctx.cityTrip = same and cities[1] or nil
    local G = Graph()
    local originGraph = G:Ensure(origin.inst)
    local function cancelled()
        releaseSearch(ctx)
        return nil, { code = "CANCELLED", message = L.ROUTE_CANCELLED }
    end
    if originGraph then
        local originAttach, originCount, originRadius, originEnclosed = attachFor(ctx, origin, false)
        ctx.originAttach, ctx.originEnclosed = originAttach, originEnclosed
        if originCount and originRadius then ctx.originRadius = originRadius end
        if not Scheduler().Yield() then return cancelled() end
        ctx.originZ = origin.z
        if not ctx.originZ then
            ctx.originZ = guessHeight(ctx.originAttach, true, nil, origin.zHint) or ctx.originWaterZ
            ctx.originGuessed = ctx.originZ ~= nil or nil
            if not ctx.originZ then ctx.originZg = guessHeight(ctx.originAttach, true, true, origin.zHint) end
        end
        ctx.originStacked = ctx.originZ ~= nil and levelsApart(ctx.originAttach) or nil
        for i = 1, nStops do
            local goal = Router._prepareGoal(ctx, stops[i], goalKeys[i], cities[i])
            goal.index = i
            ctx.goals[i] = goal
            ctx.goalSet[goal.key] = goal
            if not Scheduler().Yield() then return cancelled() end
        end
        ctx.goalsLeft = #ctx.goals
        ctx.cityTrip = same and cities[1] or nil
        ctx.dest = stops[1]
        local first = ctx.goals[1]
        if first then
            ctx.destZ, ctx.destEnclosed, ctx.destAttach = first.z, first.enclosed, first.attach
            ctx.vpos[DEST] = ctx.vpos[first.key]
        end
        setupTeleports(ctx)
        for i = 1, #ctx.goals do
            local goal = ctx.goals[i]
            ctx.fastLinks, ctx.outsideRest, ctx.outsideAlt, ctx.outsideLists = nil, nil, nil, {}
            Router._bindGoal(ctx, goal)
            setupFastLinks(ctx)
            goal.fastLinks, goal.outsideRest, goal.flightHubs = ctx.fastLinks, ctx.outsideRest, ctx.flightHubs
            Router._unbindGoal(ctx, goal)
            if not Scheduler().Yield() then return cancelled() end
        end
        ctx.fastLinks, ctx.outsideRest, ctx.outsideLists, ctx.flightHubs = nil, nil, {}, nil

        if ctx.flightGround then
            local merged, at = {}, {}
            for _, goal in ipairs(ctx.goals) do
                for _, hub in ipairs(goal.flightHubs or {}) do
                    local k = hub.x .. ":" .. hub.y
                    local m = at[k]
                    if not m then
                        m = { x = hub.x, y = hub.y, f = hub.f }
                        at[k] = m
                        merged[#merged + 1] = m
                    elseif hub.f < m.f then
                        m.f = hub.f
                    end
                end
            end
            if #merged > 0 then ctx.goalFlight = merged end
        end
        ctx.cityTrip = same and cities[1] or nil
        ctx.destKey, ctx.destHubKey, ctx.destStacked, ctx.destRoadNode = nil, nil, nil, nil
        ctx.maxSpeed = ctx.maxSpeed or Cost().SearchSpeed(access, variant)
        local _, reason = search(ctx)
        if reason == "CANCELLED" then return cancelled() end
        if ctx.goalCut then
            for _, goal in ipairs(ctx.goals) do
                if not goal.reached then goal.cut = true end
            end
        end
        if Router._goalsUnlessSlowerThanWithout(ctx) == "CANCELLED" then return cancelled() end
        if Router._goalsInTheTownHere(ctx) == "CANCELLED" then return cancelled() end
    else
        for i = 1, nStops do
            local goal = { key = goalKeys[i], dest = stops[i], attach = {}, cityTrip = cities[i] }
            ctx.goals[i] = goal
        end
    end
    local results, cut = {}, nil
    for i = 1, #ctx.goals do
        results[i] = Router._finishGoal(ctx, ctx.goals[i], request, access)
        if ctx.goals[i].cut and not results[i] then
            cut = cut or {}
            cut[i] = ctx.goalCut
        end
    end


    releaseSearch(ctx)

    return { goalSearch = true, uncacheable = true, expansions = ctx.expansions or 0, results = results, cut = cut }
end






function Router._spendTeleports(access, request, legs)
    local landing = FGPS.Personal and FGPS.Personal.LANDING_SPELLS or {}
    local stone, spells = false, {}
    for _, leg in ipairs(legs) do
        local option = leg.option
        if leg.kind == "hearth" then
            stone = true
        elseif leg.kind == "spell" and type(option) == "table" and landing[option.id] then
            spells[option.id] = true
        end
    end
    if not stone and next(spells) == nil then return access, request end
    local copy = {}
    for k, v in pairs(access) do copy[k] = v end
    if stone then copy.hearth = nil end
    if next(spells) ~= nil and type(access.spells) == "table" then
        copy.spells = {}
        for _, sp in ipairs(access.spells) do
            if not spells[sp.id] then copy.spells[#copy.spells + 1] = sp end
        end
    end



    local ids = {}
    for id in pairs(spells) do ids[#ids + 1] = id end
    table.sort(ids)
    copy.hash = Util.Hash({ "spent", access.hash, stone, ids })
    local req = {}
    for k, v in pairs(request) do req[k] = v end
    req.access = copy
    return copy, req
end

local function runRequest(handle)
    local request = handle.request
    local access = handle.access
    local variant = searchVariant(request, access)
    if request.goalStops then return Router._computeGoals(handle) end
    local route = { variant = request.variant, legs = {}, steps = {}, stops = {}, fallback = nil, fallbackStops = {},
                    expansions = 0, reason = request.reason, origin = { inst = handle.origin.inst, x = handle.origin.x, y = handle.origin.y } }
    local prev = handle.origin
    local stones = access
    for i, stop in ipairs(handle.stops) do
        local key = segmentKey(prev, stop, request, i > 1)



        local seg = not (request.bypassCache and i == 1) and lruGet(Router.segmentCache, key) or nil
        local cached = seg ~= nil
        if not seg then
            local maxStraight = (access.allowUnverified ~= false) and Router.MaxStraightYards() or 0
            local hubReach = Router.HUB_REACH_YARDS
            if hubReach > maxStraight then hubReach = maxStraight end
            local ctx = { access = stones, variant = variant, ride = request.variant or "fastest", maxSeconds = request.maxSeconds, origin = prev, dest = stop,
                          vpos = { [ORIGIN] = prev, [DEST] = stop }, originAttach = {}, destAttach = {}, teleAttach = {}, teleEnclosed = {}, teleports = {},
                          hubAttach = {}, hubOK = {}, hubCells = {}, vetted = {}, maxStraight = maxStraight, hubReach = hubReach, expansions = 0 }
            ctx.insideStarts, ctx.insideEnds = Router._insideEnds({ prev }), Router._teleportFeeders(Router._insideEnds({ stop }))



            local perf = FGPS.Perf
            local started = perf and perf.enabled and debugprofilestop() or nil
            local legs, err = computeSegment(ctx)
            if started and not (type(err) == "table" and err.code == "CANCELLED") then
                perf:Record("route", debugprofilestop() - started)
            end
            releaseSearch(ctx)
            if legs and fallbackCapped(request, ctx, legs) then
                legs, err = nil, { code = "NO_PATH", reason = "FALLBACK_CAPPED", message = L.ROUTE_NO_PATH,
                                   partial = { expansions = ctx.expansions } }
            end

            if not legs or #legs == 0 then
                if type(err) ~= "table" then
                    err = { code = "NO_PATH", message = L.ROUTE_NO_PATH }
                end
                err.stopIndex = i
                err.attachInfo = ctx.attachInfo
                if i > 1 then err.partial = finalizeRoute(route, request, access) end
                return nil, err
            end
            seg = { legs = legs, fallback = ctx.fallback, expansions = ctx.expansions, attachInfo = ctx.attachInfo,
                    uncacheable = ctx.teleportWaits }


            if levelsApart(ctx.originAttach) and ctx.origin.z == nil and ctx.origin.zHint == nil then
                seg.uncacheable = true
            end
            if not waitsForCooldown(legs) and not seg.uncacheable and handle.epoch == Router.cacheEpoch then
                lruPut(Router.segmentCache, key, seg)
            end
        end

        if type(seg.legs) ~= "table" or #seg.legs == 0 then
            return nil, { code = "NO_PATH", message = L.ROUTE_NO_PATH, stopIndex = i }
        end
        if seg.uncacheable then route.uncacheable = true end
        appendSegment(route, seg, i, stop, cached)
        prev = stop
        stones, request = Router._spendTeleports(stones, request, seg.legs)
        if not Scheduler().Yield() then return nil, { code = "CANCELLED", message = L.ROUTE_CANCELLED } end
    end
    return finalizeRoute(route, request, access)
end




local function removeActive(handle)
    for i = #Router.active, 1, -1 do
        if Router.active[i] == handle then table.remove(Router.active, i) end
    end
end




function Router._endKey(p)
    if type(p) ~= "table" then return "?" end


    if type(p.poiKey) == "string" then return (p.poiKey:gsub(";[^|]*", ""):gsub(",", ".")) end
    if type(p.taxiNodeID) == "number" then return "taxi:" .. p.taxiNodeID end
    local kind = type(p.kind) == "string" and p.kind or "point"
    if kind == "service" and type(p.serviceKind) == "string" then kind = kind .. ":" .. p.serviceKind end
    if kind == "inside" and type(p.type) == "string" then kind = kind .. ":" .. p.type end
    return type(p.map) == "number" and (kind .. ":" .. p.map) or kind
end






function Router._noteTiming(handle, route, err)
    local Perf = FGPS.Perf
    if not Perf or not Perf.NoteRoute then return end
    if type(handle) ~= "table" or handle.cancelled then return end
    if type(err) == "table" and err.code == "CANCELLED" then return end
    local request = handle.request
    local origin = handle.origin
    if type(origin) ~= "table" and type(request) == "table" then origin = request.origin end
    if type(origin) ~= "table" or type(origin.inst) ~= "number" then return end
    local task = handle.task
    local now = GetTime and GetTime() or nil
    local wall = (now and handle.askedAt) and ((now - handle.askedAt) * 1000) or 0
    local reason = type(request) == "table" and request.reason or nil
    if reason == "alt" then reason = "alternative" end
    local expansions = 0
    if not handle.cached then
        expansions = route and route.expansions or nil
        if expansions == nil and type(err) == "table" and type(err.partial) == "table" then
            expansions = err.partial.expansions
        end
    end
    local row = {
        cpuMs = task and task.elapsedMs or 0,
        maxSliceMs = task and task.maxSliceMs or 0,
        wallMs = wall,
        frames = task and task.slices or 0,
        expansions = expansions or 0,
        budgetMs = handle.budgetMs or 0,
        fps = handle.fps,
        reason = reason,
        why = type(request) == "table" and request.why or nil,
        continent = origin.inst,
    }
    if FGPS:IsOwnerInstall() and type(request) == "table" then
        row.kind = (reason == "service" or reason == "alternative") and reason or "route"
        row.service = reason == "service" and request.service or nil
        local ends = {}
        for i, stop in ipairs(type(request.stops) == "table" and request.stops or {}) do ends[i] = Router._endKey(stop) end
        row.ends = table.concat(ends, ",")
        local asked = type(request.origin) == "table" and request.origin or origin
        row.zone = asked.map or origin.map
        row.again = handle.searchedAgain or nil
    end
    Perf:NoteRoute(row)
end

local function deliver(handle, route, err)
    if handle.delivered then return end
    handle.delivered = true
    handle.done = true
    removeActive(handle)
    Router._noteTiming(handle, route, err)
    if type(handle.callback) == "function" then
        local ok, callErr = pcall(handle.callback, route, err)
        if not ok and FGPS.Log then FGPS.Log:Error("Route callback failed: %s", tostring(callErr)) end
    end
end

local function cancelledError()
    return { code = "CANCELLED", message = L.ROUTE_CANCELLED }
end

local startNext


local function startHandle(handle)


    local DataLoad = FGPS.DataLoad
    if DataLoad and not handle.dataReady and DataLoad:Hold(handle, function(err)
        if err then return deliver(handle, nil, err) end
        handle.dataReady = true
        table.insert(Router.queue, 1, handle)
        startNext()
    end) then
        startNext()
        return
    end
    Router.running = handle


    handle.epoch = Router.cacheEpoch
    handle.dataEpoch = Router.dataEpoch
    local access = handle.request.access
    handle.task = Scheduler():Run(function() return runRequest(handle) end, {
        label = "route",
        onDone = function(ok, result, err)
            if Router.running == handle then Router.running = nil end
            local cancelled = handle.cancelled or (not ok and result == "cancelled")
            local requeue = false
            local postOk, postErr = pcall(function()
                Router._releaseTaskSearch(handle.task)


                if ok and result and not cancelled and DataLoad and DataLoad:WantsJoined(handle, result) then
                    handle.dataReady, handle.searchedAgain = nil, true
                    table.insert(Router.queue, 1, handle)
                    requeue = true
                    return
                end



                if ok and result and not result.goalSearch and not cancelled
                    and handle.request and handle.request.variant ~= "no_boat"
                    and handle.dataEpoch ~= Router.dataEpoch and not handle.retriedDataEpoch then
                    handle.dataReady, handle.retriedDataEpoch = nil, true
                    table.insert(Router.queue, 1, handle)
                    requeue = true
                    return
                end
                if ok and result and not cancelled and handle.key and not result.uncacheable and Router.cacheHash == access.hash
                    and handle.epoch == Router.cacheEpoch and not waitsForCooldown(result.legs) then
                    lruPut(Router.routeCache, handle.key, routeCopy(result))
                end
            end)
            if not postOk and FGPS.Log then
                FGPS.Log:Error("Route post-search bookkeeping failed: %s", tostring(postErr))
            end
            if requeue then
                local nextOk, nextErr = pcall(startNext)
                if not nextOk and FGPS.Log then
                    FGPS.Log:Error("Route queue advance failed: %s", tostring(nextErr))
                end
                if nextOk or Router.running == handle or handle.waitingForData or handle.done then
                    return
                end
            else


                local nextOk, nextErr = pcall(startNext)
                if not nextOk and FGPS.Log then
                    FGPS.Log:Error("Route queue advance failed: %s", tostring(nextErr))
                end
            end
            if cancelled then
                deliver(handle, nil, cancelledError())
            elseif not ok then
                deliver(handle, nil, { code = "NO_PATH", message = L.ROUTE_NO_PATH, error = tostring(result) })
            elseif result then
                deliver(handle, result, nil)
            else
                deliver(handle, nil, err or { code = "NO_PATH", message = L.ROUTE_NO_PATH })
            end
        end,
    })
end


function startNext()
    local running = Router.running

    if running and running.task and running.task.done then Router.running, running = nil, nil end
    if running then return end
    local queue = Router.queue
    while #queue > 0 do
        local handle = table.remove(queue, 1)
        if not handle.cancelled and not handle.done then
            startHandle(handle)
            return
        end
    end
end

local function removeQueued(handle)
    local queue = Router.queue
    for i = #queue, 1, -1 do
        if queue[i] == handle then table.remove(queue, i) end
    end
end




function Router:RequestGoals(request, callback)
    if type(request) == "table" then
        request.goalStops = true
        request.bypassCache = true
    end
    return self:RequestRoute(request, callback)
end


function Router:RequestRoute(request, callback)
    self.nextHandleID = self.nextHandleID + 1
    local handle = { id = self.nextHandleID, request = request, callback = callback, cancelled = false, done = false }
    if type(request) ~= "table" then
        deliver(handle, nil, { code = "NO_ORIGIN", message = L.ROUTE_NO_ORIGIN })
        return handle
    end
    request.variant = request.variant or "fastest"
    local origin = normalizePos(request.origin)
    if not origin then
        deliver(handle, nil, { code = "NO_ORIGIN", message = L.ROUTE_NO_ORIGIN })
        return handle
    end






    if origin.z == nil then
        if origin.zHint == nil then
            local hint = Router._liftLevel(origin)
            if hint then
                origin.zHint = hint
                request.origin = Util.ShallowCopy(request.origin)
                request.origin.zHint = hint
            end
        elseif request.reason ~= "recalc" and request.reason ~= "level" then
            local hint = Router._liftLevel(origin)
            if hint and math.abs(hint - origin.zHint) > Router.HEIGHT_GUESS_SPREAD then
                origin.zHint = hint
                request.origin = Util.ShallowCopy(request.origin)
                request.origin.zHint = hint
            end
        end
    end
    local stops = {}
    for _, stop in ipairs(request.stops or {}) do
        local p = normalizePos(stop)
        if p then stops[#stops + 1] = p end
    end
    if #stops == 0 then
        deliver(handle, nil, { code = "NO_PATH", message = L["No destination was given."] })
        return handle
    end
    local access = request.access or Access():Snapshot()
    request.access = access
    syncCacheHash(access.hash)
    handle.askedAt = GetTime and GetTime() or nil
    if GetFramerate then
        local fpsOk, fpsValue = pcall(GetFramerate)
        handle.fps = fpsOk and type(fpsValue) == "number" and fpsValue or nil
    end
    if Scheduler().RouteBudget then handle.budgetMs = Scheduler():RouteBudget() end



    local key = not request.bypassCache and self:CacheKey(request) or nil
    handle.key = key
    local cached = key and lruGet(self.routeCache, key)
    if cached then
        handle.cached = true
        deliver(handle, routeCopy(cached, stops), nil)
        return handle
    end

    handle.origin, handle.stops = origin, stops
    handle.access = effectiveAccess(access, request.variant)
    self.active[#self.active + 1] = handle

    self.queue[#self.queue + 1] = handle
    startNext()
    return handle
end






function Router:Cancel(handle)
    if type(handle) ~= "table" or handle.done then return false end
    if handle.children then
        handle.cancelled = true
        for _, child in ipairs(handle.children) do self:Cancel(child) end
        return true
    end
    if handle.cancelled then return true end
    handle.cancelled = true



    if handle.task and not handle.task.done then
        Scheduler():Cancel(handle.task)
        if self.running == handle then
            self.running = nil
            startNext()
        end
    else
        removeQueued(handle)

        handle.task = Scheduler():Run(function() end, {
            label = "route-cancelled",
            onDone = function() deliver(handle, nil, cancelledError()) end,
        })
    end
    return true
end

function Router:CancelAll()
    local n = 0
    for i = #self.active, 1, -1 do
        if self:Cancel(self.active[i]) then n = n + 1 end
    end
    return n
end

function Router:IsBusy()
    return #self.active > 0
end


local function signature(route)
    local parts = {}
    for _, leg in ipairs(route.legs) do
        if leg.kind ~= "walk" then
            parts[#parts + 1] = leg.kind .. ":" .. tostring(leg.transportID or "") .. ":" .. tostring(leg.taxiFrom or "") .. ">" .. tostring(leg.taxiTo or "")
        end
    end
    return table.concat(parts, ",")
end

local function isDistinct(route, list)
    local sig = signature(route)
    for _, other in ipairs(list) do
        local a, b = route.totalSeconds or 0, other.totalSeconds or 0
        local base = a < b and a or b
        local diff = base > 0 and abs(a - b) / base or (a == b and 0 or 1)
        if signature(other) == sig and diff <= 0.05 then return false end
    end
    return true
end
Router.IsDistinct = isDistinct




function Router:Alternatives(request, callback)
    local handle = { children = {}, cancelled = false, done = false }
    if type(request) ~= "table" then
        if callback then callback({}) end
        handle.done = true
        return handle
    end
    local base = request.variant or "fastest"
    local order = { base }


    local access = request.access or Access():Snapshot()
    for _, v in ipairs(self.VARIANTS) do
        if v ~= base and not (v == "prefer_roads" and access.preferRoads) then order[#order + 1] = v end
    end
    local results, errors, index = {}, {}, 0
    local function step()
        if handle.cancelled then
            handle.done = true
            if callback then callback(results, errors) end
            return
        end
        index = index + 1
        if index > #order or #results >= 4 then
            handle.done = true
            if callback then callback(results, errors) end
            return
        end
        local req = Util.ShallowCopy(request)
        req.variant = order[index]
        req.reason = "alt"



        local child = self:RequestRoute(req, function(route, err)
            if route then
                if isDistinct(route, results) then results[#results + 1] = route end
            elseif err then
                errors[req.variant] = err





                if type(err) == "table" and err.code == "CANCELLED" then handle.cancelled = true end
            end
            step()
        end)
        handle.children[#handle.children + 1] = child
    end
    step()
    return handle
end

function Router:Init()
    if self.initialized then return end
    self.initialized = true
    local Events = FGPS.Events
    if Events then
        Events:Register("SETTINGS_CHANGED", function(_, key)
            if type(key) == "string" and (key == "*" or key:sub(1, 10) == "transports" or key:sub(1, 7) == "routing") then
                Router:InvalidateCache()
            end
        end, self)


        Events:Register("ACCESS_CHANGED", function()
            Router:InvalidateCache()
        end, self)

        Events:Register("DATA_PART_LOADED", function(_, _, part)
            if part ~= "landmarks" then Router.dataEpoch = Router.dataEpoch + 1 end
            Router:InvalidateCache()
        end, self)


        Events:Register("NAV_ARRIVED", function(_, _, isFinal)
            if isFinal then Router._releaseBounds() end
        end, self)
        Events:Register("NAV_CANCELLED", function() Router._releaseBounds() end, self)
    end
end
