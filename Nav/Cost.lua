




local ADDON_NAME, FGPS = ...

local Cost = {}
FGPS.Cost = Cost

local L = FGPS.L
local Const = FGPS.Const
local floor, ceil, sqrt = math.floor, math.ceil, math.sqrt
local type = type





Const.INFERRED_FACTOR = 1.35
Const.UNVERIFIED_FACTOR = 1.35
Const.UNVERIFIED_STRICT_MAX_YARDS = 60
Const.TRANSFER_PENALTY_FASTEST = 20
Const.TRANSFER_PENALTY_FEWER = 240
Const.PREFER_ROADS_FACTOR = 2.0




Const.PREFER_ROADS_SURFACE = 1.20




Const.ROADS_ONLY_SURFACE = 3.0
Const.ROADS_ONLY_FACTOR = 4.0
Const.TELEPORT_MAX_WAIT = 120






Const.ROAD_WINDING = 1.137







Const.ROAD_SEARCH_BIAS = 0.78





Const.ROAD_CHORD_YARDS = 120


Const.STRAIGHT_CHORD_YARDS = 120



Const.MESH_SEARCH_BIAS = 1.05


Cost.KIND_HEARTH = 20
Cost.KIND_SPELL = 21


Cost.KIND_MESH = 15




Cost.KIND_STREET = 16



Cost.KIND_ROAD_PATH = 17




Cost.KIND_TERRAIN_ROAD = 18


Cost.KIND_TERRAIN_GRID = 19

Const.GRID_FACTOR = 1.0








Const.TERRAIN_ROAD_CHORD_FACTOR = 1.0





Cost.KIND_SURFACE = 22

Cost.KIND_SURFACE_SWIM = 23




Const.SWIM_CROSSING_CHARGE = 36000




local GROUND_KINDS = { [1] = true, [2] = true, [6] = true, [12] = true, [17] = true, [18] = true }

local DEFAULT_TRANSPORTS = { taxi = true, boat = true, zeppelin = true, tram = true, hearth = true, spells = true }

local function transportsOf(access)
    local t = access and access.transports
    if type(t) == "table" then return t end
    return DEFAULT_TRANSPORTS
end

local function allowUnverified(access)
    if access == nil or access.allowUnverified == nil then return true end
    return access.allowUnverified == true
end





function Cost.GroundSpeed(access)
    if access and access.hasMount and access.canMount ~= false then
        local speed = access.mountSpeed or 0
        if speed >= 1.0 then return Const.MOUNT_100 end
        if speed >= 0.6 then return Const.MOUNT_60 end
    end
    return Const.RUN_SPEED
end


function Cost.SpeedLabel(access)
    local speed = Cost.GroundSpeed(access)
    if speed >= Const.MOUNT_100 then
        return string.format(L["a 100%% ground mount (%.1f yards per second)"], speed)
    elseif speed >= Const.MOUNT_60 then
        return string.format(L["a 60%% ground mount (%.1f yards per second)"], speed)
    end
    return string.format(L["travel on foot (%.1f yards per second)"], speed)
end













local function canFly(access)
    if transportsOf(access).taxi == false then return false end
    local known = access and access.knownTaxi
    if type(known) ~= "table" then return false end
    local first = next(known)
    return first ~= nil and next(known, first) ~= nil
end

function Cost.MaxSpeed(access)
    local ground = Cost.GroundSpeed(access)
    if canFly(access) and Const.TAXI_SPEED > ground then return Const.TAXI_SPEED end
    return ground
end






local function expectedWait(period)
    if type(period) == "number" and period > 0 then
        local half = period / 2
        if half < Const.BOAT_WAIT_CAP then return half end
    end
    return Const.BOAT_WAIT_CAP
end
Cost.ExpectedWait = expectedWait




function Cost.AboardWait(rec, stopIndex)
    local stop = type(rec) == "table" and type(rec.stops) == "table" and rec.stops[stopIndex] or nil
    local dwell = type(stop) == "table" and tonumber(stop.wait) or 0
    local cap = expectedWait(type(rec) == "table" and rec.period or nil)
    if dwell > cap then return cap end
    if dwell < 0 then return 0 end
    return dwell
end






function Cost.EdgeSeconds(kind, yards, access, edgeSeconds, extra, shaped)
    yards = yards or 0
    if GROUND_KINDS[kind] then
        return yards / Cost.GroundSpeed(access)
    elseif kind == 4 then


        if shaped then return yards / Cost.GroundSpeed(access) end
        return yards * Const.ROAD_WINDING / Cost.GroundSpeed(access)
    elseif kind == 3 then


        if not allowUnverified(access) and yards > Const.UNVERIFIED_STRICT_MAX_YARDS then return nil end
        if extra and extra.onFoot then return yards * Const.INFERRED_FACTOR / Const.RUN_SPEED end
        return yards * Const.INFERRED_FACTOR / Cost.GroundSpeed(access)
    elseif kind == 14 then
        if not allowUnverified(access) and yards > Const.UNVERIFIED_STRICT_MAX_YARDS then return nil end

        if extra and extra.onFoot then return yards * Const.UNVERIFIED_FACTOR / Const.RUN_SPEED end
        return yards * Const.UNVERIFIED_FACTOR / Cost.GroundSpeed(access)
    elseif kind == Cost.KIND_MESH then






        if not allowUnverified(access) then return nil end
        return yards * Const.INFERRED_FACTOR / Cost.GroundSpeed(access)
    elseif kind == Cost.KIND_STREET then



        if not allowUnverified(access) and yards > Const.UNVERIFIED_STRICT_MAX_YARDS then return nil end
        return yards / Cost.GroundSpeed(access)
    elseif kind == Cost.KIND_TERRAIN_GRID then

        if not allowUnverified(access) and yards > Const.UNVERIFIED_STRICT_MAX_YARDS then return nil end
        return yards * Const.GRID_FACTOR / Cost.GroundSpeed(access)
    elseif kind == Cost.KIND_SURFACE then
        if extra and extra.onFoot then return yards / Const.RUN_SPEED end
        return yards / Cost.GroundSpeed(access)
    elseif kind == Cost.KIND_SURFACE_SWIM then
        return yards / Const.SWIM_SPEED
    elseif kind == 5 then
        return yards / Const.SWIM_SPEED
    elseif kind == 7 then
        return edgeSeconds or Const.PORTAL_SECONDS
    elseif kind == 8 then
        if transportsOf(access).taxi == false then return nil end
        return edgeSeconds or (yards / Const.TAXI_SPEED + Const.TAXI_BOARD_SECONDS)
    elseif kind == 9 then
        local t = transportsOf(access)
        local recKind = extra and extra.kind
        if recKind == "zeppelin" then
            if t.zeppelin == false then return nil end
        elseif recKind == "boat" or recKind == "ferry" then
            if t.boat == false then return nil end
        elseif t.boat == false and t.zeppelin == false then
            return nil
        end
        return (edgeSeconds or (yards / Const.TAXI_SPEED)) + expectedWait(extra and extra.period)
    elseif kind == 10 then
        if transportsOf(access).tram == false then return nil end
        return (edgeSeconds or Const.TRAM_SECONDS) + Const.TRAM_WAIT
    elseif kind == 11 then
        return edgeSeconds or Const.ELEVATOR_SECONDS
    elseif kind == Cost.KIND_HEARTH or kind == Cost.KIND_SPELL then
        return edgeSeconds
    end
    return nil
end


function Cost.TransferPenalty(variant)
    if variant == "fewer_transfers" then return Const.TRANSFER_PENALTY_FEWER end
    return Const.TRANSFER_PENALTY_FASTEST
end





function Cost.RoadFactor(variant, kind)


    if kind == Cost.KIND_SURFACE then
        if variant == "roads_only" then return Const.ROADS_ONLY_SURFACE end
        return variant == "prefer_roads" and Const.PREFER_ROADS_SURFACE or 1.0
    end
    if kind == Cost.KIND_SURFACE_SWIM then return 1.0 end
    if kind == 4 or kind == Cost.KIND_ROAD_PATH or kind == Cost.KIND_TERRAIN_ROAD then

        return Const.ROAD_SEARCH_BIAS
    end
    if kind == Cost.KIND_MESH or kind == 3 or kind == 14 or kind == Cost.KIND_TERRAIN_GRID then
        if variant == "roads_only" then return Const.ROADS_ONLY_FACTOR end
        if variant == "prefer_roads" then return Const.PREFER_ROADS_FACTOR end
        if kind == Cost.KIND_MESH then return Const.MESH_SEARCH_BIAS end
    end
    return 1.0
end












function Cost.ChordFactor(kind, yards, shaped, doubt)

    if kind == Cost.KIND_TERRAIN_ROAD then return Const.TERRAIN_ROAD_CHORD_FACTOR end







    local doubtful = kind == 4 and type(doubt) == "number" and doubt ~= 0
    if shaped and not doubtful then
        if kind == 4 then return 0.55 end
        return 1
    end
    if type(yards) ~= "number" then return 1 end
    local limit
    if kind == 14 then
        limit = Const.STRAIGHT_CHORD_YARDS
    elseif kind == 4 then
        if doubt == 0 then return 1 end
        limit = Const.ROAD_CHORD_YARDS
    elseif kind == 3 or kind == 15 then
        limit = Const.ROAD_CHORD_YARDS
    else
        return 1
    end
    if yards <= limit then return 1 end
    return yards / limit
end











function Cost.SearchSpeed(access, variant)
    local bias = Cost.RoadFactor(variant, 4)
    if bias > 1 then bias = 1 end


    bias = bias * 0.55
    local speed = Cost.MaxSpeed(access)
    local road = Cost.GroundSpeed(access) / bias
    if road > speed then speed = road end
    return speed
end


function Cost.ModeOf(kind, transportRecord)
    if kind == 8 then return "taxi" end
    if kind == 7 then return "portal" end
    if kind == 9 then
        local k = transportRecord and transportRecord.kind
        if k == "zeppelin" then return "zeppelin" end
        return "boat"
    end
    if kind == 10 then return "tram" end
    if kind == 11 then return "elevator" end
    if kind == Cost.KIND_HEARTH then return "hearth" end
    if kind == Cost.KIND_SPELL then return "spell" end
    return "ground"
end














Const.GUARDED_FACTOR = 25


Const.GUARDED_NEAR = 256







Const.GUARDED_HEIGHT = 10
Const.GUARDED_HEIGHT_SPAN = 100

local guardedIndexes = setmetatable({}, { __mode = "k" })

local function guardedCell(x, y)
    return (floor(x / Const.GUARDED_NEAR) + 32768) * 65536 + (floor(y / Const.GUARDED_NEAR) + 32768)
end



local function guardedLayer(entries)
    local near = Const.GUARDED_NEAR
    local list, cells = {}, {}
    for _, entry in ipairs(entries) do
        list[#list + 1] = entry
        for cx = floor((entry.minX - near) / near), floor((entry.maxX + near) / near) do
            for cy = floor((entry.minY - near) / near), floor((entry.maxY + near) / near) do
                local k = (cx + 32768) * 65536 + (cy + 32768)
                local cell = cells[k]
                if not cell then cell = {} cells[k] = cell end
                cell[#cell + 1] = entry
            end
        end
    end
    return { list = list, cells = cells }
end


local function buildGuardedIndex(data, side)
    local index = {}
    for inst, places in pairs(data) do
        local entries = {}
        for _, place in ipairs(places) do
            local xs, ys = place.x, place.y
            if place.side == side and type(xs) == "table" and type(ys) == "table" and #xs >= 3 and #xs == #ys then
                local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
                for i = 1, #xs do
                    if xs[i] < minX then minX = xs[i] end
                    if xs[i] > maxX then maxX = xs[i] end
                    if ys[i] < minY then minY = ys[i] end
                    if ys[i] > maxY then maxY = ys[i] end
                end
                local zLo = type(place.zmin) == "number" and place.zmin - Const.GUARDED_HEIGHT or nil
                local zHi = type(place.zmax) == "number" and place.zmax + Const.GUARDED_HEIGHT or nil
                entries[#entries + 1] = { place = place, x = xs, y = ys, n = #xs, minX = minX, maxX = maxX, minY = minY, maxY = maxY,
                    zLo = zLo, zHi = zHi }
            end
        end
        if #entries > 0 then index[inst] = guardedLayer(entries) end
    end
    return index
end




function Cost.GuardedIndex(access)
    if not access or not access.avoidGuarded or access.dead then return nil end
    local side = (access.faction == "Alliance" and 2) or (access.faction == "Horde" and 1) or nil
    local data = FGPS.Data and FGPS.Data.guarded
    if not side or type(data) ~= "table" then return nil end
    local bySide = guardedIndexes[data]
    if not bySide then bySide = {} guardedIndexes[data] = bySide end
    local index = bySide[side]
    if not index then index = buildGuardedIndex(data, side) bySide[side] = index end
    return index
end




Const.GUARDED_TOWN_YARDS = 150


function Cost.GuardedHold(index, inst, x, y, held)
    local place = Cost.GuardedAt(index, inst, x, y)
    if not place or held[place] then return end
    local list = index[inst].list
    local at
    for i = 1, #list do
        if list[i].place == place then at = list[i] break end
    end
    local reach = Const.GUARDED_TOWN_YARDS
    for i = 1, #list do
        local e = list[i]
        if (place.name and e.place.name == place.name) or (e.minX <= at.maxX + reach and e.maxX >= at.minX - reach
                and e.minY <= at.maxY + reach and e.maxY >= at.minY - reach) then
            held[e.place] = true
        end
    end
end


function Cost.GuardedExcept(index, held)
    if not index or next(held) == nil then return index end
    local out = {}
    for inst, layer in pairs(index) do
        local entries = {}
        for _, e in ipairs(layer.list) do
            if not held[e.place] then entries[#entries + 1] = e end
        end
        if #entries > 0 then out[inst] = guardedLayer(entries) end
    end
    return out
end


function Cost.GuardedNear(index, inst, x, y)
    local layer = index and index[inst]
    if not layer or x == nil or y == nil then return false end
    return layer.cells[guardedCell(x, y)] ~= nil
end




local function offBand(e, z1, z2, long2, anyLength)
    if z1 == nil or z2 == nil or not (e.zLo and e.zHi) then return false end
    if not anyLength and long2 > Const.GUARDED_HEIGHT_SPAN * Const.GUARDED_HEIGHT_SPAN then return false end
    return (z1 < e.zLo and z2 < e.zLo) or (z1 > e.zHi and z2 > e.zHi)
end

local function insideOutline(e, x, y)
    local xs, ys, n = e.x, e.y, e.n
    for i = 1, n do
        local j = i < n and i + 1 or 1
        if (xs[j] - xs[i]) * (y - ys[i]) - (ys[j] - ys[i]) * (x - xs[i]) < 0 then return false end
    end
    return true
end



local function shareInside(e, x1, y1, x2, y2)
    local xs, ys, n = e.x, e.y, e.n
    local dx, dy = x2 - x1, y2 - y1
    local t0, t1 = 0, 1
    for i = 1, n do
        local j = i < n and i + 1 or 1
        local ex, ey = xs[j] - xs[i], ys[j] - ys[i]
        local num = ex * (y1 - ys[i]) - ey * (x1 - xs[i])
        local den = ex * dy - ey * dx
        if den == 0 then
            if num < 0 then return 0 end
        else
            local t = -num / den
            if den > 0 then
                if t > t0 then t0 = t end
            elseif t < t1 then
                t1 = t
            end
            if t0 >= t1 then return 0 end
        end
    end
    return t1 - t0
end





function Cost.GuardedShare(index, inst, x1, y1, x2, y2, z1, z2, anyLength)
    local layer = index and index[inst]
    if not layer or x1 == nil or x2 == nil then return 0, nil end
    local near = Const.GUARDED_NEAR
    local list
    local long2 = (x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1)
    if long2 <= near * near then
        list = layer.cells[guardedCell(x1, y1)]
        if not list then return 0, nil end
    else
        list = layer.list
    end
    local minX, maxX = x1 < x2 and x1 or x2, x1 < x2 and x2 or x1
    local minY, maxY = y1 < y2 and y1 or y2, y1 < y2 and y2 or y1
    local share, first = 0, nil
    for i = 1, #list do
        local e = list[i]
        if maxX >= e.minX and minX <= e.maxX and maxY >= e.minY and minY <= e.maxY and not offBand(e, z1, z2, long2, anyLength) then
            local s
            if x1 == x2 and y1 == y2 then
                s = insideOutline(e, x1, y1) and 1 or 0
            else
                s = shareInside(e, x1, y1, x2, y2)
            end
            if s > 0 then
                share = share + s
                first = first or e.place
            end
        end
    end
    if share > 1 then share = 1 end
    return share, first
end


function Cost.GuardedFactor(share)
    if not share or share <= 0 then return 1 end
    return 1 + (Const.GUARDED_FACTOR - 1) * share
end


function Cost.GuardedAt(index, inst, x, y)
    local layer = index and index[inst]
    if not layer or x == nil or y == nil then return nil end
    local list = layer.cells[guardedCell(x, y)]
    if not list then return nil end
    for i = 1, #list do
        local e = list[i]
        if x >= e.minX and x <= e.maxX and y >= e.minY and y <= e.maxY and insideOutline(e, x, y) then return e.place end
    end
    return nil
end
















local WATER_CELL_DEFAULT = 100
local WATER_MIN_YARDS = 100
local WATER_MAX_SAMPLES = 9


function Cost.WaterShare(inst, x1, y1, x2, y2)
    local data = FGPS.Data
    local layer = data and data.water and data.water[inst]
    if not layer or x1 == nil or x2 == nil then return 0 end
    local grid = layer.c
    if type(grid) ~= "table" then return 0 end
    local dx, dy = x2 - x1, y2 - y1
    local d = sqrt(dx * dx + dy * dy)
    if d < WATER_MIN_YARDS then return 0 end
    local cell = layer.cell or WATER_CELL_DEFAULT
    local w, h = layer.w or 0, layer.h or 0



    local steps = ceil(d / cell)
    if steps > WATER_MAX_SAMPLES then steps = WATER_MAX_SAMPLES end
    if steps < 1 then steps = 1 end
    local hits = 0
    for i = 0, steps do
        local t = i / steps
        local col = floor((x1 + dx * t - layer.ox) / cell)
        local row = floor((y1 + dy * t - layer.oy) / cell)
        if col >= 0 and row >= 0 and col < w and row < h and grid[row * w + col + 1] then
            hits = hits + 1
        end
    end
    return hits / (steps + 1)
end



local function swimSpans(s)
    local lo = s._lo
    if lo then return lo, s._hi end
    lo = {}
    local hi = {}
    s._lo, s._hi = lo, hi
    local w, grid = s.w or 0, s.c
    if w > 0 and type(grid) == "table" then
        for idx in pairs(grid) do
            local i = idx - 1
            local row = floor(i / w)
            local col = i - row * w
            local slot = row + 1
            local a, b = lo[slot], hi[slot]
            if not a or col < a then lo[slot] = col end
            if not b or col > b then hi[slot] = col end
        end
    end
    return lo, hi
end




local SWIM_SLOTS = 128
local swimX1, swimY1, swimX2, swimY2, swimInst, swimGrid, swimHit = {}, {}, {}, {}, {}, {}, {}

local function swimSlot(inst, x1, y1, x2, y2)
    local n = floor(x1) * 3 + floor(y1) * 5 + floor(x2) * 7 + floor(y2) * 11 + inst * 13
    n = n % SWIM_SLOTS
    if n < 0 then n = n + SWIM_SLOTS end
    return n + 1
end






function Cost.OverSwim(inst, x1, y1, x2, y2)
    local data = FGPS.Data
    local layer = data and data.water and data.water[inst]
    local s = layer and layer.s
    if not s or type(s.c) ~= "table" or x1 == nil or x2 == nil then return false end
    local cell = s.cell or 50
    local dx, dy = x2 - x1, y2 - y1
    local d = sqrt(dx * dx + dy * dy)
    if d <= 2 * cell then return false end
    local slot = swimSlot(inst, x1, y1, x2, y2)
    if swimGrid[slot] == s and swimInst[slot] == inst and swimX1[slot] == x1 and swimY1[slot] == y1 and swimX2[slot] == x2 and swimY2[slot] == y2 then
        return swimHit[slot]
    end
    local w, h, grid = s.w or 0, s.h or 0, s.c
    local lo, hi = swimSpans(s)
    local ox, oy = layer.ox, layer.oy

    local steps = ceil(d / cell)
    local hit = false
    for i = 1, steps - 1 do
        local along = d * i / steps
        if along >= cell and along <= d - cell then
            local t = i / steps
            local col = floor((x1 + dx * t - ox) / cell)
            local row = floor((y1 + dy * t - oy) / cell)
            local span = lo[row + 1]
            if span and col >= span and col <= hi[row + 1] and col >= 0 and row >= 0 and col < w and row < h
                and grid[row * w + col + 1] then
                hit = true
                break
            end
        end
    end
    swimInst[slot], swimGrid[slot], swimX1[slot], swimY1[slot], swimX2[slot], swimY2[slot], swimHit[slot] = inst, s, x1, y1, x2, y2, hit
    return hit
end





local BLOCKED_CELL_DEFAULT = 10
local BLOCKED_BLOCK = 16




local function blockedBlocks(b)
    local hot = b._hot
    if hot then return hot, b._bw end
    hot = {}
    local w, grid = b.w or 0, b.c
    local bw = ceil(w / BLOCKED_BLOCK) + 2
    if w > 0 and type(grid) == "table" then
        for idx in pairs(grid) do
            local i = idx - 1
            local row = floor(i / w)
            local br, bc = floor(row / BLOCKED_BLOCK) + 1, floor((i - row * w) / BLOCKED_BLOCK) + 1
            for r = br - 1, br + 1 do
                for c = bc - 1, bc + 1 do hot[r * bw + c] = true end
            end
        end
    end
    b._hot, b._bw = hot, bw
    return hot, bw
end


local blockX1, blockY1, blockX2, blockY2, blockGrid, blockHit = {}, {}, {}, {}, {}, {}


function Cost.OverBlocked(inst, x1, y1, x2, y2)
    local data = FGPS.Data
    local layer = data and data.water and data.water[inst]
    local b = layer and layer.b
    if not b or type(b.c) ~= "table" or x1 == nil or x2 == nil then return false end
    local slot = swimSlot(inst, x1, y1, x2, y2)
    if blockGrid[slot] == b and blockX1[slot] == x1 and blockY1[slot] == y1 and blockX2[slot] == x2 and blockY2[slot] == y2 then
        return blockHit[slot]
    end
    local cell = b.cell or BLOCKED_CELL_DEFAULT
    local w, h, grid = b.w or 0, b.h or 0, b.c
    local ox, oy = layer.ox, layer.oy
    local dx, dy = x2 - x1, y2 - y1
    local d = sqrt(dx * dx + dy * dy)
    local steps = ceil(2 * d / cell)
    local hit = false
    if steps >= 2 then
        local ac, ar = floor((x1 - ox) / cell), floor((y1 - oy) / cell)
        local zc, zr = floor((x2 - ox) / cell), floor((y2 - oy) / cell)
        local hot, bw = blockedBlocks(b)
        local coarse = ceil(4 * d / (BLOCKED_BLOCK * cell))
        local done = 0
        for j = 0, coarse do
            local t = j / coarse
            local col = floor((x1 + dx * t - ox) / cell)
            local row = floor((y1 + dy * t - oy) / cell)
            local bc = floor(col / BLOCKED_BLOCK) + 1
            if bc >= 0 and bc < bw and hot[(floor(row / BLOCKED_BLOCK) + 1) * bw + bc] then
                local first = floor((j - 1) * steps / coarse)
                if first <= done then first = done + 1 end
                local last = ceil((j + 1) * steps / coarse)
                if last > steps - 1 then last = steps - 1 end
                for i = first, last do
                    local s = i / steps
                    local c = floor((x1 + dx * s - ox) / cell)
                    local r = floor((y1 + dy * s - oy) / cell)
                    if c >= 0 and r >= 0 and c < w and r < h and grid[r * w + c + 1]
                        and not (c == ac and r == ar) and not (c == zc and r == zr) then
                        hit = true
                        break
                    end
                end
                if last > done then done = last end
                if hit then break end
            end
        end
    end
    blockGrid[slot], blockX1[slot], blockY1[slot], blockX2[slot], blockY2[slot], blockHit[slot] = b, x1, y1, x2, y2, hit
    return hit
end




function Cost.WaterFactor(kind, inst, x1, y1, x2, y2, access)
    if kind ~= 3 and kind ~= 14 then return 1.0 end
    local share = Cost.WaterShare(inst, x1, y1, x2, y2)
    if share <= 0 then return 1.0 end
    local ratio = Cost.GroundSpeed(access) / Const.SWIM_SPEED
    if ratio <= 1 then return 1.0 end
    return 1 + share * (ratio - 1)
end





local HAZARD_LIQUIDS = { "fel", "slime", "lava" }
local HAZARD_EXPLAIN = {
    fel = L["%s cross fel read from the game's own world: it hurts, but there is no dry way."],
    slime = L["%s cross slime read from the game's own world: it hurts, but there is no dry way."],
    lava = L["%s cross lava read from the game's own world: it hurts, but there is no dry way."],
}

function Cost.Explain(route)



    local text = ""
    local units = FGPS.DB and FGPS.DB.settings and FGPS.DB.settings.units or "yards"
    local unverified = route and route.unverifiedYards or 0
    local function add(sentence)
        if text == "" then text = sentence else text = text .. " " .. sentence end
    end
    if route and route.fallback == "straight" then
        add(L["No road joins these points; the whole route is drawn dashed."])
    elseif unverified > 0 then


        local mesh = route.meshYards or 0
        local dock = route.dockYards or 0
        if unverified - mesh - dock >= 0.5 then
            add(string.format(L["%s of this route is open ground (drawn dashed)."],
                FGPS.Util.FormatDistance(unverified - mesh - dock, units)))
        end
        if mesh >= 0.5 then
            add(string.format(
                L["%s cross open ground from one place where creatures are known to stand to the next; nobody has walked the way between them."],
                FGPS.Util.FormatDistance(mesh, units)))
        end
        if dock >= 0.5 then
            add(string.format(
                L["%s step onto or off a dock or landing; nobody has walked that step, and it is drawn like the path to it."],
                FGPS.Util.FormatDistance(dock, units)))
        end
    end




    local shaped = route and route.roadShapedYards or 0
    local road = (route and route.roadYards or 0) - shaped
    if road >= 0.5 then
        add(string.format(
            L["%s follow roads known from the game's signposts; the line is drawn straight between junctions, so it cuts corners."],
            FGPS.Util.FormatDistance(road, units)))
    end
    if shaped >= 0.5 then
        add(string.format(L["%s follow roads known from the game's signposts, drawn along the road's bends."],
            FGPS.Util.FormatDistance(shaped, units)))
    end


    local street = route and route.streetYards or 0
    if street > 0 then
        add(string.format(
            L["%s cut across city streets and squares on lines checked against the city map; nobody has walked those exact lines."],
            FGPS.Util.FormatDistance(street, units)))
    end


    local terrainRoad = route and route.terrainRoadYards or 0
    if terrainRoad >= 0.5 then
        add(string.format(L["%s follow roads traced from the ground of the game world."],
            FGPS.Util.FormatDistance(terrainRoad, units)))
    end
    local terrainGround = route and route.terrainGroundYards or 0
    if terrainGround >= 0.5 then
        add(string.format(L["%s cross open ground on a way that keeps off cliffs and deep water; trees, rocks and fences along it are not known."],
            FGPS.Util.FormatDistance(terrainGround, units)))
    end

    local surface = route and route.surfaceYards or 0
    if surface >= 0.5 then
        add(string.format(L["%s follow ground, floors and halls read from the game's own world."],
            FGPS.Util.FormatDistance(surface, units)))
    end


    local hazard = route and route.hazardYards or {}
    local swim = route and route.surfaceSwimYards or 0
    for _, liquid in ipairs(HAZARD_LIQUIDS) do swim = swim - (hazard[liquid] or 0) end
    if swim >= 0.5 then
        add(string.format(L["%s swim across water read from the game's own world."],
            FGPS.Util.FormatDistance(swim, units)))
    end
    for _, liquid in ipairs(HAZARD_LIQUIDS) do
        if (hazard[liquid] or 0) >= 0.5 then
            add(string.format(HAZARD_EXPLAIN[liquid], FGPS.Util.FormatDistance(hazard[liquid], units)))
        end
    end

    for _, name in ipairs(route and route.guardedPassed or {}) do
        if name then
            add(string.format(L["This route goes through %s, which the other side holds: you may be attacked there."], name))
        else
            add(L["This route goes through an outpost of the other side: you may be attacked there."])
        end
    end
    return text
end

function Cost:Init()
    self.initialized = true
end
