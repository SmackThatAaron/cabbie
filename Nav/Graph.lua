





















































local ADDON_NAME, FGPS = ...

local Graph = {
    CELL = 256,
    ATTACH_RADIUS = 150,
    ATTACH_VERIFIED_RADIUS = 25,
    SURFACE_ATTACH_RADIUS = 25,
    ATTACH_RADII = { 150, 400, 800 },
    ATTACH_MAX = 8,
    ROAD_POINT_ATTACH_YARDS = 2,
    MESH_ATTACH_MAX = 4,
    GRID_ATTACH_MAX = 4,







    FREE_ATTACH_YARDS = 250,
    FREE_ATTACH_MAX = 4,
    HUB_CELL = 1200,
    loaded = {},
}
FGPS.Graph = Graph

local KEY_BASE = 1048576
local floor, ceil, sqrt, huge = math.floor, math.ceil, math.sqrt, math.huge
local type, pairs, ipairs, next = type, pairs, ipairs, next
local tsort = table.sort
local strbyte = string.byte

local EDGE_CHARS = 4

local FLAG_INDOOR = 32


local function isHubFlags(flags)
    return flags ~= nil and flags % 8 >= 2
end
Graph.IsHubFlags = isHubFlags





local PROJECTABLE = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [12] = true,
                      [16] = true, [17] = true, [18] = true, [22] = true, [23] = true }



local SYMMETRIC_KINDS = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [12] = true, [16] = true, [17] = true,
                          [18] = true, [22] = true, [23] = true }

local KIND_ATTACH, KIND_MESH, KIND_GRID = 14, 15, 19




function Graph:Key(inst, idx)
    return inst * KEY_BASE + idx
end

function Graph:Split(key)
    local inst = floor(key / KEY_BASE)
    return inst, key - inst * KEY_BASE
end

local function splitKey(key)
    local inst = floor(key / KEY_BASE)
    return inst, key - inst * KEY_BASE
end




local CELL = Graph.CELL
local CELL_OFFSET = 32768

local function cellKey(cx, cy)
    return (cx + CELL_OFFSET) * 65536 + (cy + CELL_OFFSET)
end

local function gridInsert(grid, x, y, idx)
    local k = cellKey(floor(x / CELL), floor(y / CELL))
    local cell = grid[k]
    if not cell then
        grid[k] = { idx }
    else
        cell[#cell + 1] = idx
    end
end

local function buildIndex(g)
    if FGPS.Perf then FGPS.Perf:Begin("graph_index") end
    local grid = {}
    local xs, ys = g.x, g.y
    local n = g.n or #xs
    local count = 0
    for i = 1, n do
        local x, y = xs[i], ys[i]
        if x and y then
            gridInsert(grid, x, y, i)
            count = count + 1
        end
    end
    g._grid = grid

    g._xsorted = nil


    local function packedBlock(block)
        if type(block) == "table" and type(block.a) == "table" and type(block.first) == "number" and block.first >= 1
            and type(block.slots) == "number" and block.slots >= 1 and type(block.row) == "number" and block.row >= 1 then
            return block
        end
        return nil
    end
    g._mesh = packedBlock(g.mesh)


    local tgrid = packedBlock(g.grid)
    if tgrid and g._mesh and tgrid.first <= g._mesh.first then tgrid = nil end
    g._tgrid = tgrid
    g._meshLast = tgrid and tgrid.first - 1 or n



    local surf = g.surf
    if type(surf) == "table" and type(surf.first) == "number" and type(surf.last) == "number"
        and surf.first >= 1 and surf.first <= surf.last and surf.last <= n
        and type(surf.row) == "number" and surf.row >= 1 and type(surf.t) == "table" and type(surf.names) == "table"
        and (surf.cl == nil or type(surf.cl) == "table") then
        local packedFirst = (g._mesh and g._mesh.first) or (tgrid and tgrid.first)
        if packedFirst and surf.last >= packedFirst then surf = nil end
    else
        surf = nil
    end
    g._surf = surf


    local pc = g.pc
    if type(pc) == "table" and pc.small == Graph.SMALL_PIECE_NODES and type(pc.ni) == "number"
        and type(pc.ns) == "number" and type(pc.nr) == "number" and type(pc.iso) == "table"
        and type(pc.sm) == "table" and type(pc.rp) == "table" and type(pc.nw) == "number" and type(pc.wp) == "table" then
        g._pc = pc
    else
        g._pc = nil
    end


    local ep = g.ep
    if type(ep) == "table" and type(ep.a) == "table" and type(ep.row) == "number" and ep.row >= 1 then
        g._ep = ep
    else
        g._ep = nil
    end

    local es = g.es
    if type(es) == "table" and type(es.len) == "table" and type(es.o) == "table"
        and type(es.a) == "table" and type(es.n) == "number" and es.n >= 0 then
        g._es = es
    else
        g._es = nil
    end


    local floors = {}
    if type(g.m) == "table" then
        for _, floorMap in pairs(g.m) do floors[floorMap] = true end
    end
    g._floors = floors
    g._indexed = count
    if FGPS.Perf then FGPS.Perf:End("graph_index") end
end




local function dataGraphs()
    local data = FGPS.Data
    return data and data.graphs or nil
end




function Graph:Ensure(inst)
    if inst == nil then return nil end
    local g = self.loaded[inst]
    if g then return g end
    local graphs = dataGraphs()
    g = graphs and graphs[inst]
    if type(g) ~= "table" or type(g.x) ~= "table" or type(g.y) ~= "table" then return nil end
    if g.n == nil then g.n = #g.x end
    if not g.eo then g.eo = { 1 } end
    buildIndex(g)
    self.loaded[inst] = g
    if FGPS.Events then FGPS.Events:Fire("DATA_LOADED", inst) end
    return g
end

function Graph:IsLoaded(inst)
    return self.loaded[inst] ~= nil
end


function Graph:HasData(inst)
    local graphs = dataGraphs()
    if graphs ~= nil and graphs[inst] ~= nil then return true end
    return FGPS.DataLoad ~= nil and FGPS.DataLoad:Knows(inst)
end


function Graph:Reset()
    for _, g in pairs(self.loaded) do
        g._grid, g._stats, g._indexed = nil, nil, nil
        g._hubCells, g._hubKeys, g._fixedNodes, g._fixedEdges = nil, nil, nil, nil
        g._mesh, g._ep, g._isolated, g._smallPiece, g._offPiece = nil, nil, nil, nil, nil
        g._isoAt, g._smallAt, g._offAt = nil, nil, nil
        g._tgrid, g._meshLast, g._surf, g._poiAnchor, g._pc, g._roadPieces = nil, nil, nil, nil, nil, nil
        g._xsorted = nil
        g._lm, g._lmCells = nil, nil
    end
    self.loaded = {}
    self._links = nil
    self._linkKinds = nil
    self._crossLinks = nil
    self._taxiIndex = nil
    self._transportIndex = nil
end




local function graphFor(inst)
    return Graph.loaded[inst] or Graph:Ensure(inst)
end

function Graph:NodePos(key)
    if type(key) ~= "number" or key < 0 then return nil end
    local inst, idx = splitKey(key)
    local g = graphFor(inst)
    if not g then return nil end
    return inst, g.x[idx], g.y[idx]
end

function Graph:NodeFlags(key)
    if type(key) ~= "number" or key < 0 then return 0 end
    local inst, idx = splitKey(key)
    local g = graphFor(inst)
    if not g or not g.f then return 0 end
    return g.f[idx] or 0
end


function Graph:NodeFloor(key)
    if type(key) ~= "number" or key < 0 then return nil end
    local inst, idx = splitKey(key)
    local g = graphFor(inst)
    return g and g.m and g.m[idx] or nil
end

function Graph:NodeTaxiID(key)
    if type(key) ~= "number" or key < 0 then return nil end
    local inst, idx = splitKey(key)
    local g = graphFor(inst)
    return g and g.tx and g.tx[idx] or nil
end


function Graph:NodeTransport(key)
    if type(key) ~= "number" or key < 0 then return nil end
    local inst, idx = splitKey(key)
    local g = graphFor(inst)
    local ts = g and g.ts and g.ts[idx]
    if not ts then return nil end
    local transportID = floor(ts / 100)
    return transportID, ts - transportID * 100
end

function Graph:NodePOI(key)
    if type(key) ~= "number" or key < 0 then return nil end
    local inst, idx = splitKey(key)
    local g = graphFor(inst)
    return g and g.pi and g.pi[idx] or nil
end









local HEIGHT_ROW, HEIGHT_BASE, HEIGHT_OFFSET = 50, 91, 2000
local FIRST_CHAR, SKIPPED_CHAR = 35, 92



local function unpackHeight(rows, index)
    if type(rows) ~= "table" or type(index) ~= "number" or index < 1 then return nil end
    local slot = index - 1
    local row = rows[floor(slot / HEIGHT_ROW) + 1]
    if type(row) ~= "string" then return nil end
    local at = (slot % HEIGHT_ROW) * 2 + 1
    local hi, lo = strbyte(row, at, at + 1)
    if not lo then return nil end
    if hi > SKIPPED_CHAR then hi = hi - 1 end
    if lo > SKIPPED_CHAR then lo = lo - 1 end
    local code = (hi - FIRST_CHAR) * HEIGHT_BASE + (lo - FIRST_CHAR)
    if code <= 0 then return nil end
    return code - 1 - HEIGHT_OFFSET
end
Graph.UnpackHeight = unpackHeight





Graph.LANDMARK_DIGITS = 3
function Graph.UnpackLandmark(rows, perRow, index, digits)
    local slot = index - 1
    local at = slot % perRow
    local row = rows[(slot - at) / perRow + 1]
    if type(row) ~= "string" then return nil end
    at = at * digits
    local value = 0
    for k = at + 1, at + digits do
        local b = strbyte(row, k)
        if not b then return nil end
        if b > SKIPPED_CHAR then b = b - 1 end
        value = value * HEIGHT_BASE + (b - FIRST_CHAR)
    end
    return value
end













local function edgeAt(ep, e)
    local perRow = ep.row
    local slot = e - 1
    local at = slot % perRow
    local row = ep.a[(slot - at) / perRow + 1]
    if type(row) ~= "string" then return nil end
    at = at * EDGE_CHARS
    local b1, b2, b3, b4 = strbyte(row, at + 1, at + EDGE_CHARS)
    if not b4 then return nil end
    if b1 > SKIPPED_CHAR then b1 = b1 - 1 end
    if b2 > SKIPPED_CHAR then b2 = b2 - 1 end
    if b3 > SKIPPED_CHAR then b3 = b3 - 1 end
    if b4 > SKIPPED_CHAR then b4 = b4 - 1 end
    return ((b1 - FIRST_CHAR) * HEIGHT_BASE + (b2 - FIRST_CHAR)) * HEIGHT_BASE + (b3 - FIRST_CHAR), b4 - FIRST_CHAR
end




local function edgeShapeLength(es, e)
    if not es or type(e) ~= "number" or e < 1 or e > es.n then return nil end
    local perRow = es.row or 250
    local width = es.lc == 2 and 2 or 3
    local slot = e - 1
    local at = slot % perRow
    local row = es.len[(slot - at) / perRow + 1]
    if type(row) ~= "string" then return nil end
    at = at * width
    local b1, b2, b3 = strbyte(row, at + 1, at + width)
    if not b1 or not b2 then return nil end
    if b1 > SKIPPED_CHAR then b1 = b1 - 1 end
    if b2 > SKIPPED_CHAR then b2 = b2 - 1 end
    local yards = (b1 - FIRST_CHAR) * HEIGHT_BASE + (b2 - FIRST_CHAR)
    if width == 3 then
        if not b3 then return nil end
        if b3 > SKIPPED_CHAR then b3 = b3 - 1 end
        yards = yards * HEIGHT_BASE + (b3 - FIRST_CHAR)
    end
    if yards <= 0 then return nil end
    return yards
end









local SHAPE_GUARD_KINDS = { [1] = true, [2] = true, [5] = true }
local LOOP_STRETCH, LOOP_SLACK = 1.5, 20


local function trustedShapeLength(es, e, kind, chord)
    local yards = edgeShapeLength(es, e)
    if yards and SHAPE_GUARD_KINDS[kind] and yards > LOOP_STRETCH * chord + LOOP_SLACK then return nil end
    return yards
end


local function chordYards(g, a, b)
    local ax, bx = g.x[a], g.x[b]
    if not ax or not bx then return 0 end
    local dx, dy = bx - ax, g.y[b] - g.y[a]
    return sqrt(dx * dx + dy * dy)
end


local function edgeShapeRange(es, e)
    local o, perRow = es.o, es.row or 250


    local width = es.oc == 4 and 4 or 3
    local function offsetAt(slot)
        local at = slot % perRow
        local row = o[(slot - at) / perRow + 1]
        if type(row) ~= "string" then return 0 end
        at = at * width
        local b1, b2, b3, b4 = strbyte(row, at + 1, at + width)
        if not b3 or (width == 4 and not b4) then return 0 end
        if b1 > SKIPPED_CHAR then b1 = b1 - 1 end
        if b2 > SKIPPED_CHAR then b2 = b2 - 1 end
        if b3 > SKIPPED_CHAR then b3 = b3 - 1 end
        local v = ((b1 - FIRST_CHAR) * HEIGHT_BASE + (b2 - FIRST_CHAR)) * HEIGHT_BASE + (b3 - FIRST_CHAR)
        if width == 4 then
            if b4 > SKIPPED_CHAR then b4 = b4 - 1 end
            v = v * HEIGHT_BASE + (b4 - FIRST_CHAR)
        end
        return v
    end
    return offsetAt(e - 1), offsetAt(e)
end



local function edgeShapePoints(es, e, ox, oy, out)
    local nOut = 0
    if not es or not ox then return 0 end
    local start, stop = edgeShapeRange(es, e)
    if stop <= start then return 0 end
    local a, blobChars = es.a, 4
    local px, py = ox, oy
    for p = start, stop - 1 do
        local charAt = p * blobChars
        local rowIdx = floor(charAt / 8000) + 1
        local row = a[rowIdx]
        if type(row) ~= "string" then break end
        local at = (charAt % 8000) + 1
        local h1, h2, h3, h4 = strbyte(row, at, at + 3)
        if not h4 then break end

        if h1 > SKIPPED_CHAR then h1 = h1 - 1 end
        if h2 > SKIPPED_CHAR then h2 = h2 - 1 end
        if h3 > SKIPPED_CHAR then h3 = h3 - 1 end
        if h4 > SKIPPED_CHAR then h4 = h4 - 1 end
        local codeX = (h1 - FIRST_CHAR) * HEIGHT_BASE + (h2 - FIRST_CHAR)
        local codeY = (h3 - FIRST_CHAR) * HEIGHT_BASE + (h4 - FIRST_CHAR)
        if codeX <= 0 or codeY <= 0 then break end
        local dx = codeX - 1 - HEIGHT_OFFSET
        local dy = codeY - 1 - HEIGHT_OFFSET
        px, py = px + dx, py + dy
        nOut = nOut + 1
        local pt = out[nOut]
        if pt then pt.x, pt.y = px, py else out[nOut] = { x = px, y = py } end
    end
    for i = #out, nOut + 1, -1 do out[i] = nil end
    return nOut
end


local function findEntry(g, fromIdx, toIdx, kind)
    local eo, ep = g.eo, g._ep
    if not eo or not ep then return nil end
    local first, stop = eo[fromIdx], eo[fromIdx + 1]
    if not first or not stop then return nil end
    for e = first, stop - 1 do
        local nb, k = edgeAt(ep, e)
        if nb == toIdx and (kind == nil or k == kind) then return e, k end
    end
    return nil
end













Graph.SMALL_PIECE_NODES = 25
Graph.SMALL_ATTACH_MAX = 2




local PIECE_KINDS = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true,
                      [11] = true, [12] = true, [15] = true, [16] = true, [17] = true, [18] = true, [19] = true,
                      [22] = true, [23] = true }






local function buildPieces(g, inst)
    local n = g.n or 0
    local parent, joined = {}, {}
    for i = 1, n do parent[i] = i end
    local function root(i)
        while parent[i] ~= i do
            local up = parent[parent[i]]
            parent[i] = up
            i = up
        end
        return i
    end


    local dry = {}
    for i = 1, n do dry[i] = i end
    local function dryRoot(i)
        while dry[i] ~= i do
            local up = dry[dry[i]]
            dry[i] = up
            i = up
        end
        return i
    end
    local function dryJoin(a, b)
        local ra, rb = dryRoot(a), dryRoot(b)
        if ra ~= rb then dry[rb] = ra end
    end






    local ep = g._ep
    if ep then
        local eo, rows, perRow = g.eo, ep.a, ep.row
        local rowEnd = perRow * EDGE_CHARS
        for i = 1, n do
            local first, stop = eo[i], eo[i + 1]
            if first and stop and first < stop then
                joined[i] = true
                local ri
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
                    at = at + EDGE_CHARS
                    if b1 > SKIPPED_CHAR then b1 = b1 - 1 end
                    if b2 > SKIPPED_CHAR then b2 = b2 - 1 end
                    if b3 > SKIPPED_CHAR then b3 = b3 - 1 end
                    if b4 > SKIPPED_CHAR then b4 = b4 - 1 end
                    local nb = ((b1 - FIRST_CHAR) * HEIGHT_BASE + (b2 - FIRST_CHAR)) * HEIGHT_BASE + (b3 - FIRST_CHAR)
                    local kind = b4 - FIRST_CHAR
                    if nb >= 1 and nb <= n then
                        local join = nb > i
                        if not SYMMETRIC_KINDS[kind] then
                            joined[nb] = true
                            join = PIECE_KINDS[kind]
                        end
                        if join then
                            if kind ~= 5 and kind ~= 23 then dryJoin(i, nb) end
                            while parent[nb] ~= nb do
                                local up = parent[parent[nb]]
                                parent[nb] = up
                                nb = up
                            end
                            ri = ri or root(i)
                            if nb ~= ri then parent[nb] = ri end
                        end
                    end
                end
            end
        end
    end



    local function joinPacked(block, last)
        local slots = block.slots
        for i = block.first, last do
            local slot = i - block.first
            local row = block.a[floor(slot / block.row) + 1]
            if type(row) == "string" then
                local at = (slot % block.row) * slots * 3
                local ri
                for _ = 1, slots do
                    local b1, b2, b3 = strbyte(row, at + 1, at + 3)
                    if not b3 then break end
                    if b1 > SKIPPED_CHAR then b1 = b1 - 1 end
                    if b2 > SKIPPED_CHAR then b2 = b2 - 1 end
                    if b3 > SKIPPED_CHAR then b3 = b3 - 1 end
                    local nb = ((b1 - FIRST_CHAR) * HEIGHT_BASE + (b2 - FIRST_CHAR)) * HEIGHT_BASE + (b3 - FIRST_CHAR)
                    if nb <= 0 then break end
                    joined[i] = true
                    if nb > i and nb <= n then
                        dryJoin(i, nb)
                        while parent[nb] ~= nb do
                            local up = parent[parent[nb]]
                            parent[nb] = up
                            nb = up
                        end
                        ri = ri or root(i)
                        if nb ~= ri then parent[nb] = ri end
                    end
                    at = at + 3
                end
            end
        end
    end
    if g._mesh then joinPacked(g._mesh, g._meshLast or n) end
    if g._tgrid then joinPacked(g._tgrid, n) end

    local links = FGPS.Data and FGPS.Data.links
    if type(links) == "table" then
        for _, link in ipairs(links) do
            if link[1] == inst and type(link[2]) == "number" then joined[link[2]] = true end
            if link[3] == inst and type(link[4]) == "number" then joined[link[4]] = true end
        end
    end
    local size, largest = {}, 0
    for i = 1, n do
        local r = root(i)
        local s = (size[r] or 0) + 1
        size[r] = s
        if s > largest then largest = s end
    end

    local drySize, dryLeast, dryLargest = {}, {}, 0
    for i = 1, n do
        if joined[i] then
            local r = dryRoot(i)
            local s = (drySize[r] or 0) + 1
            drySize[r] = s
            if not dryLeast[r] then dryLeast[r] = i end
            if s > dryLargest then dryLargest = s end
        end
    end
    local main
    for r, s in pairs(drySize) do
        if s == dryLargest and (not main or dryLeast[r] < dryLeast[main]) then main = r end
    end
    local isolated, small, off = {}, {}, {}
    local limit = Graph.SMALL_PIECE_NODES
    for i = 1, n do
        if not joined[i] then
            isolated[i] = true
        else
            local r = root(i)
            local d = dryRoot(i)
            if d ~= main then off[i] = dryLeast[d] end
            if largest >= limit and size[r] < limit then small[i] = r end
        end
    end
    g._isolated, g._smallPiece, g._offPiece = isolated, small, off
end



local VALUE_ROW = 50
local function unpackValues(rows, count)
    if type(rows) ~= "table" or type(count) ~= "number" or count < 0 then return nil end
    local out = {}
    for k = 0, count - 1 do
        local at = k % VALUE_ROW
        local row = rows[(k - at) / VALUE_ROW + 1]
        if type(row) ~= "string" then return nil end
        at = at * 3
        local b1, b2, b3 = strbyte(row, at + 1, at + 3)
        if not b3 then return nil end
        if b1 > SKIPPED_CHAR then b1 = b1 - 1 end
        if b2 > SKIPPED_CHAR then b2 = b2 - 1 end
        if b3 > SKIPPED_CHAR then b3 = b3 - 1 end
        out[k + 1] = ((b1 - FIRST_CHAR) * HEIGHT_BASE + (b2 - FIRST_CHAR)) * HEIGHT_BASE + (b3 - FIRST_CHAR)
    end
    return out
end
Graph.UnpackValues = unpackValues


local function packedAt(rows, k)
    if type(rows) ~= "table" or type(k) ~= "number" or k < 0 then return nil end
    local at = k % VALUE_ROW
    local row = rows[(k - at) / VALUE_ROW + 1]
    if type(row) ~= "string" then return nil end
    at = at * 3
    local b1, b2, b3 = strbyte(row, at + 1, at + 3)
    if not b3 then return nil end
    if b1 > SKIPPED_CHAR then b1 = b1 - 1 end
    if b2 > SKIPPED_CHAR then b2 = b2 - 1 end
    if b3 > SKIPPED_CHAR then b3 = b3 - 1 end
    return ((b1 - FIRST_CHAR) * HEIGHT_BASE + (b2 - FIRST_CHAR)) * HEIGHT_BASE + (b3 - FIRST_CHAR)
end



local function packedHas(rows, count, node)
    if not count or count <= 0 then return false end
    local lo, hi = 0, count - 1
    while lo <= hi do
        local mid = floor((lo + hi) / 2)
        local v = packedAt(rows, mid)
        if v == nil then return nil end
        if v == node then return true end
        if v < node then lo = mid + 1 else hi = mid - 1 end
    end
    return false
end


local function packedPair(rows, pairs, node)
    if not pairs or pairs <= 0 then return nil end
    local lo, hi = 0, pairs - 1
    while lo <= hi do
        local mid = floor((lo + hi) / 2)
        local v = packedAt(rows, mid * 2)
        if v == nil then return nil end
        if v == node then return packedAt(rows, mid * 2 + 1) end
        if v < node then lo = mid + 1 else hi = mid - 1 end
    end
    return nil
end

local function columnReady(rows, count)
    if type(count) ~= "number" or count < 0 then return false end
    if count == 0 then return true end
    return packedAt(rows, 0) ~= nil and packedAt(rows, count - 1) ~= nil
end


Graph._packedAt = packedAt
Graph._packedPair = packedPair
Graph._columnReady = columnReady


function Graph._decodePieceTables(pc)
    if type(pc) ~= "table" then return nil end
    local iso = unpackValues(pc.iso, pc.ni)
    local small = unpackValues(pc.sm, 2 * pc.ns)
    local offRows = unpackValues(pc.wp, 2 * pc.nw)
    if not (iso and small and offRows) then return nil end
    local isolated, pieces, off = {}, {}, {}
    for i = 1, #iso do isolated[iso[i]] = true end
    for i = 1, #small, 2 do pieces[small[i]] = small[i + 1] end
    for i = 1, #offRows, 2 do off[offRows[i]] = offRows[i + 1] end
    return isolated, pieces, off
end



local function pieceView(fn)
    return setmetatable({}, { __index = function(_, idx)
        if type(idx) ~= "number" or idx < 1 then return nil end
        return fn(idx)
    end })
end







local function ensurePieces(g, inst)
    if not g._isolated then
        local pc = g._pc
        local ni, ns, nw = pc and pc.ni, pc and pc.ns, pc and pc.nw
        if pc and columnReady(pc.iso, ni) and columnReady(pc.sm, 2 * ns) and columnReady(pc.wp, 2 * nw) then
            local isoRows, smRows, wpRows = pc.iso, pc.sm, pc.wp
            g._isoAt = function(idx)
                if packedHas(isoRows, ni, idx) then return true end
                return nil
            end
            g._smallAt = function(idx) return packedPair(smRows, ns, idx) end
            g._offAt = function(idx) return packedPair(wpRows, nw, idx) end
            g._isolated = pieceView(g._isoAt)
            g._smallPiece = pieceView(g._smallAt)
            g._offPiece = pieceView(g._offAt)
        else
            buildPieces(g, inst)
        end
    end
    return g._isolated, g._smallPiece, g._offPiece
end




function Graph:NodeHeight(key)
    if type(key) ~= "number" or key < 0 then return nil end
    local inst, idx = splitKey(key)
    local g = graphFor(inst)
    if not g then return nil end
    if idx > (g.n or 0) then return nil end
    return unpackHeight(g.z, idx)
end







function Graph:NodeHeightGuess(key)
    if type(key) ~= "number" or key < 0 then return nil end
    local inst, idx = splitKey(key)
    local g = graphFor(inst)
    if not g then return nil end
    if idx > (g.n or 0) then return nil end
    local z = unpackHeight(g.z, idx)
    if z == nil then z = unpackHeight(g.zg, idx) end
    return z
end




function Graph:NodeZone(key)
    if type(key) ~= "number" or key < 0 then return nil end
    local inst, idx = splitKey(key)
    local g = graphFor(inst)
    if not g or not g.zn or not g.zm then return nil end
    local slot = g.zn[idx]
    if type(slot) ~= "number" or slot < 1 then return nil end
    return g.zm[slot]
end



function Graph:IsVetted(inst)
    local g = graphFor(inst)
    return g ~= nil and type(g.cd) == "table"
end






function Graph:EdgeDoubt(inst, entry)
    local g = graphFor(inst)
    if not g or type(entry) ~= "number" or entry < 1 then return nil end
    local cd = g.cd
    if type(cd) ~= "table" then return nil end
    local eo, n = g.eo, g.n or 0
    if not eo or not eo[n + 1] or entry >= eo[n + 1] then return nil end
    local bits = cd[entry]
    if bits == nil then return 0 end
    if type(bits) ~= "number" or bits < 0 then return nil end
    return bits
end


function Graph:PoiHeight(poiIndex)
    local poi = FGPS.Data and FGPS.Data.poi
    if not poi or type(poiIndex) ~= "number" or poiIndex > (poi.n or 0) then return nil end
    return unpackHeight(poi.z, poiIndex)
end




function Graph:PoiLevelHeight(poiIndex)
    local z = self:PoiHeight(poiIndex)
    if z then return z end
    local poi = FGPS.Data and FGPS.Data.poi
    local src = poi and poi.src and poi.src[poiIndex]
    if type(src) ~= "string" then return nil end
    local id, stopIndex = src:match("^transport:(%d+):stop:(%d+)$")
    local records = id and FGPS.Data.transports
    local rec = records and records[tonumber(id)]
    local stop = type(rec) == "table" and type(rec.stops) == "table" and rec.stops[tonumber(stopIndex)]
    return type(stop) == "table" and type(stop.z) == "number" and stop.z or nil
end



function Graph:EdgeYards(fromKey, toKey, kind)
    if type(fromKey) ~= "number" or type(toKey) ~= "number" then return nil end
    local inst, fromIdx = splitKey(fromKey)
    local toInst, toIdx = splitKey(toKey)
    if inst ~= toInst then return nil end
    local g = graphFor(inst)
    if not g or not g._es then return nil end
    local e, k = findEntry(g, fromIdx, toIdx, kind)
    if not e then return nil end
    return trustedShapeLength(g._es, e, k, chordYards(g, fromIdx, toIdx))
end

function Graph:HasEdgeShape(fromKey, toKey, kind)
    return self:EdgeYards(fromKey, toKey, kind) ~= nil
end




local _shapeScratch = {}
function Graph:EdgeShape(fromKey, toKey, kind)
    if type(fromKey) ~= "number" or type(toKey) ~= "number" then return nil end
    local inst, fromIdx = splitKey(fromKey)
    local toInst, toIdx = splitKey(toKey)
    if inst ~= toInst then return nil end
    local g = graphFor(inst)
    if not g or not g._es then return nil end
    local e, k = findEntry(g, fromIdx, toIdx, kind)
    if not e or not trustedShapeLength(g._es, e, k, chordYards(g, fromIdx, toIdx)) then return nil end
    local ox, oy = g.x[fromIdx], g.y[fromIdx]
    local n = edgeShapePoints(g._es, e, ox, oy, _shapeScratch)
    if n <= 0 then return nil end
    return _shapeScratch
end



function Graph:IsMeshNode(key)
    if type(key) ~= "number" or key < 0 then return false end
    local inst, idx = splitKey(key)
    local g = graphFor(inst)
    local mesh = g and g._mesh
    return mesh ~= nil and idx >= mesh.first and idx <= (g._meshLast or g.n or 0)
end



function Graph:IsGridNode(key)
    if type(key) ~= "number" or key < 0 then return false end
    local inst, idx = splitKey(key)
    local g = graphFor(inst)
    local tgrid = g and g._tgrid
    return tgrid ~= nil and idx >= tgrid.first and idx <= (g.n or 0)
end








local function surfaceTag(g, idx)
    local surf = g._surf
    if not surf or idx < surf.first or idx > surf.last then return nil end
    local slot = idx - surf.first
    local perRow = surf.row
    local width = surf.w == 2 and 2 or 3
    local at = slot % perRow
    local row = surf.t[(slot - at) / perRow + 1]
    if type(row) ~= "string" then return nil end
    at = at * width
    local b1, b2, b3 = strbyte(row, at + 1, at + width)
    if not b1 or not b2 then return nil end
    if b1 > SKIPPED_CHAR then b1 = b1 - 1 end
    if b2 > SKIPPED_CHAR then b2 = b2 - 1 end
    local value = (b1 - FIRST_CHAR) * HEIGHT_BASE + (b2 - FIRST_CHAR)
    if width == 3 then
        if not b3 then return nil end
        if b3 > SKIPPED_CHAR then b3 = b3 - 1 end
        value = value * HEIGHT_BASE + (b3 - FIRST_CHAR)
    end
    return value
end



function Graph:IsSurfaceNode(key)
    if type(key) ~= "number" or key < 0 then return false end
    local inst, idx = splitKey(key)
    local g = graphFor(inst)
    local surf = g and g._surf
    return surf ~= nil and idx >= surf.first and idx <= surf.last
end




local function placeOf(g, idx)
    local value = surfaceTag(g, idx)
    if not value then return nil, false, false, false end
    local bits = value % 8
    local name = g._surf.names[(value - bits) / 8]
    if type(name) ~= "string" then name = nil end
    return name, bits % 2 == 1, bits % 4 >= 2, bits >= 4
end

function Graph:NodePlace(key)
    if type(key) ~= "number" or key < 0 then return nil, false, false, false end
    local inst, idx = splitKey(key)
    local g = graphFor(inst)
    if not g then return nil, false, false, false end
    return placeOf(g, idx)
end

local CLIMB_FORMS = { "stairs", "ramp", "climb" }




function Graph:ClimbForm(fromKey, toKey)
    if type(fromKey) ~= "number" or type(toKey) ~= "number" or fromKey < 0 or toKey < 0 then return nil end
    local inst, fromIdx = splitKey(fromKey)
    local toInst, toIdx = splitKey(toKey)
    if inst ~= toInst then return nil end
    local g = graphFor(inst)
    local cl = g and g._surf and g._surf.cl
    if not cl then return nil end
    local e = findEntry(g, fromIdx, toIdx, 22)
    local form = e and cl[e]
    if form == nil then
        e = findEntry(g, toIdx, fromIdx, 22)
        form = e and cl[e]
    end
    return CLIMB_FORMS[form] or nil
end






function Graph:IsIsolated(key)
    if type(key) ~= "number" or key < 0 then return false end
    local inst, idx = splitKey(key)
    local g = graphFor(inst)
    if not g or idx > (g.n or 0) then return false end
    return ensurePieces(g, inst)[idx] == true
end




local function ensureLinks()
    if Graph._links then return Graph._links end
    local byKey, kinds = {}, {}
    local links = FGPS.Data and FGPS.Data.links
    if type(links) == "table" then
        for _, link in ipairs(links) do
            local fromInst, fromIdx, toInst, toIdx, kind, seconds, transportID = link[1], link[2], link[3], link[4], link[5], link[6], link[7]
            if fromInst and fromIdx and toInst and toIdx and kind then
                local fromKey = fromInst * KEY_BASE + fromIdx
                local list = byKey[fromKey]
                if not list then
                    list = {}
                    byKey[fromKey] = list
                end
                list[#list + 1] = { toKey = toInst * KEY_BASE + toIdx, kind = kind, seconds = seconds, transportID = transportID }
                local row = kinds[fromInst]
                if not row then
                    row = {}
                    kinds[fromInst] = row
                end
                local set = row[toInst]
                if not set then
                    set = {}
                    row[toInst] = set
                end
                set[#set + 1] = { kind = kind, transportID = transportID }
            end
        end
    end
    Graph._links = byKey
    Graph._linkKinds = kinds
    return byKey
end


function Graph:LinkKinds(fromInst, toInst)
    ensureLinks()
    local row = self._linkKinds[fromInst]
    return (row and row[toInst]) or {}
end


function Graph:InstancesConnected(fromInst, toInst)
    if fromInst == toInst then return true end
    ensureLinks()
    local seen, frontier = { [fromInst] = true }, { fromInst }
    while #frontier > 0 do
        local cur = table.remove(frontier)
        local row = self._linkKinds[cur]
        if row then
            for nextInst in pairs(row) do
                if nextInst == toInst then return true end
                if not seen[nextInst] then
                    seen[nextInst] = true
                    frontier[#frontier + 1] = nextInst
                end
            end
        end
    end
    return false
end

local function ensureReverseIndexes()
    if Graph._taxiIndex then return end
    local taxi, transport = {}, {}
    local graphs = dataGraphs()
    if type(graphs) == "table" then
        for inst, g in pairs(graphs) do
            if type(g) == "table" then
                if type(g.tx) == "table" then
                    for idx, taxiID in pairs(g.tx) do taxi[taxiID] = inst * KEY_BASE + idx end
                end
                if type(g.ts) == "table" then
                    for idx, ts in pairs(g.ts) do transport[ts] = inst * KEY_BASE + idx end
                end
            end
        end
    end
    Graph._taxiIndex = taxi
    Graph._transportIndex = transport
end

function Graph:TaxiNodeKey(taxiNodeID)
    ensureReverseIndexes()
    return self._taxiIndex[taxiNodeID]
end

function Graph:TransportStopKey(transportID, stopIndex)
    ensureReverseIndexes()
    return self._transportIndex[transportID * 100 + stopIndex]
end









function Graph:Neighbors(key, fn, skip)
    if type(key) ~= "number" or key < 0 then return end
    local inst, idx = splitKey(key)
    local g = graphFor(inst)
    if not g then return end
    local xs, ys = g.x, g.y
    local x, y = xs[idx], ys[idx]
    if not x then return end
    local n = g.n or 0
    if idx <= n then
        local eo, ep, ed = g.eo, g._ep, g.ed
        local first, stop = eo[idx], eo[idx + 1]
        if ep and first and stop and first < stop then



            local base = inst * KEY_BASE
            local rows, perRow = ep.a, ep.row
            local slot = first - 1
            local at = slot % perRow
            local r = (slot - at) / perRow + 1
            local row, rowEnd = rows[r], perRow * EDGE_CHARS
            at = at * EDGE_CHARS




            local es = g._es
            local lens = es and es.row == perRow and es.len or nil
            local lenWidth = (es and es.lc == 2) and 2 or 3
            local lastShaped = lens and es.n or 0
            local lrow = lens and lens[r]
            for e = first, stop - 1 do
                if at >= rowEnd then
                    r = r + 1
                    row, at = rows[r], 0
                    lrow = lens and lens[r]
                end
                if type(row) ~= "string" then break end
                local b1, b2, b3, b4 = strbyte(row, at + 1, at + EDGE_CHARS)
                if not b4 then break end
                if b1 > SKIPPED_CHAR then b1 = b1 - 1 end
                if b2 > SKIPPED_CHAR then b2 = b2 - 1 end
                if b3 > SKIPPED_CHAR then b3 = b3 - 1 end
                if b4 > SKIPPED_CHAR then b4 = b4 - 1 end
                local nb = ((b1 - FIRST_CHAR) * HEIGHT_BASE + (b2 - FIRST_CHAR)) * HEIGHT_BASE + (b3 - FIRST_CHAR)
                local nx, ny
                if not (skip and skip[base + nb]) then nx, ny = xs[nb], ys[nb] end
                if nx then
                    local dx, dy = nx - x, ny - y
                    local yards = sqrt(dx * dx + dy * dy)
                    local kind = b4 - FIRST_CHAR
                    local shapedLen
                    if lens then
                        if e <= lastShaped and type(lrow) == "string" then
                            local la = at / EDGE_CHARS * lenWidth
                            local c1, c2, c3 = strbyte(lrow, la + 1, la + lenWidth)
                            local len
                            if lenWidth == 2 then
                                if c2 then
                                    if c1 > SKIPPED_CHAR then c1 = c1 - 1 end
                                    if c2 > SKIPPED_CHAR then c2 = c2 - 1 end
                                    len = (c1 - FIRST_CHAR) * HEIGHT_BASE + (c2 - FIRST_CHAR)
                                end
                            elseif c3 then
                                if c1 > SKIPPED_CHAR then c1 = c1 - 1 end
                                if c2 > SKIPPED_CHAR then c2 = c2 - 1 end
                                if c3 > SKIPPED_CHAR then c3 = c3 - 1 end
                                len = ((c1 - FIRST_CHAR) * HEIGHT_BASE + (c2 - FIRST_CHAR)) * HEIGHT_BASE + (c3 - FIRST_CHAR)
                            end
                            if len and len > 0 and not (SHAPE_GUARD_KINDS[kind] and len > LOOP_STRETCH * yards + LOOP_SLACK) then
                                shapedLen = len
                            end
                        end
                    elseif es then
                        shapedLen = trustedShapeLength(es, e, kind, yards)
                    end
                    if shapedLen then yards = shapedLen end
                    fn(base + nb, kind, yards, ed and ed[e] or nil, nil, shapedLen and true or nil, e)
                end
                at = at + EDGE_CHARS
            end
        end






        local mesh, tgrid = g._mesh, g._tgrid
        local gridFirst = tgrid and tgrid.first or huge
        local block
        if idx >= gridFirst then
            block = tgrid
        elseif mesh and idx >= mesh.first then
            block = mesh
        end
        if block then
            local slot = idx - block.first
            local perRow, slots = block.row, block.slots
            local row = block.a[floor(slot / perRow) + 1]
            local ownKind = block == tgrid and KIND_GRID or KIND_MESH
            if type(row) == "string" then
                local at = (slot % perRow) * slots * 3
                local base = inst * KEY_BASE
                for _ = 1, slots do
                    local b1, b2, b3 = strbyte(row, at + 1, at + 3)
                    if not b3 then break end
                    if b1 > SKIPPED_CHAR then b1 = b1 - 1 end
                    if b2 > SKIPPED_CHAR then b2 = b2 - 1 end
                    if b3 > SKIPPED_CHAR then b3 = b3 - 1 end
                    local nb = ((b1 - FIRST_CHAR) * HEIGHT_BASE + (b2 - FIRST_CHAR)) * HEIGHT_BASE + (b3 - FIRST_CHAR)
                    if nb <= 0 then break end
                    local nx, ny = xs[nb], ys[nb]
                    if nx and nb <= n and not (skip and skip[base + nb]) then
                        local dx, dy = nx - x, ny - y
                        fn(base + nb, nb >= gridFirst and KIND_GRID or ownKind, sqrt(dx * dx + dy * dy), nil, nil)
                    end
                    at = at + 3
                end
            end
        end
    end
    local links = (self._links or ensureLinks())[key]
    if links then
        for i = 1, #links do
            local link = links[i]
            local toInst, toIdx = splitKey(link.toKey)
            local tg = graphFor(toInst)
            local yards = 0
            if tg and tg.x[toIdx] and toInst == inst then
                local dx, dy = tg.x[toIdx] - x, tg.y[toIdx] - y
                yards = sqrt(dx * dx + dy * dy)
            end


            local unloaded = not tg and FGPS.DataLoad ~= nil and FGPS.DataLoad:Knows(toInst)
            if not unloaded and not (skip and skip[link.toKey]) then fn(link.toKey, link.kind, yards, link.seconds, link.transportID) end
        end
    end
end




















local CELL_SPAN_MIN, CELL_SPAN_STEPS, CELL_SPAN_SLACK = 48, 1024, 0.01
local function cellSpan(g, k, cell, x, x0, radiusSq)
    local count = #cell
    if count < CELL_SPAN_MIN or radiusSq * 16 > CELL * CELL then return 1, count end
    local xs = g.x
    local sorted = g._xsorted
    if not sorted then
        sorted = {}
        g._xsorted = sorted
    end
    if not sorted[k] then
        for i = 1, count do
            local idx = cell[i]
            cell[i] = floor((xs[idx] - x0) * CELL_SPAN_STEPS) * KEY_BASE + idx
        end
        tsort(cell)
        for i = 1, count do cell[i] = cell[i] % KEY_BASE end
        sorted[k] = true


        local Sched = FGPS.Scheduler
        if Sched and Sched.Yield then Sched.Yield() end
    end
    local r = sqrt(radiusSq) + CELL_SPAN_SLACK
    local q = floor((x - r - x0) * CELL_SPAN_STEPS)
    local lo, hi = 1, count + 1
    while lo < hi do
        local mid = floor((lo + hi) / 2)
        if floor((xs[cell[mid]] - x0) * CELL_SPAN_STEPS) < q then lo = mid + 1 else hi = mid end
    end
    q = floor((x + r - x0) * CELL_SPAN_STEPS)
    local first = lo
    hi = count + 1
    while lo < hi do
        local mid = floor((lo + hi) / 2)
        if floor((xs[cell[mid]] - x0) * CELL_SPAN_STEPS) <= q then lo = mid + 1 else hi = mid end
    end
    return first, lo - 1
end

local function scanCell(g, grid, cx, cy, x, y, radiusSq, filterFn, base, results)
    local x0, y0 = cx * CELL, cy * CELL
    local gx, gy = 0, 0
    if x < x0 then gx = x0 - x elseif x > x0 + CELL then gx = x - (x0 + CELL) end
    if y < y0 then gy = y0 - y elseif y > y0 + CELL then gy = y - (y0 + CELL) end
    if gx * gx + gy * gy > radiusSq then return end
    local k = cellKey(cx, cy)
    local cell = grid[k]
    if not cell then return end
    local xs, ys = g.x, g.y


    local first, last = cellSpan(g, k, cell, x, x0, radiusSq)
    for i = first, last do
        local idx = cell[i]
        local dx = xs[idx] - x
        local dx2 = dx * dx
        if dx2 <= radiusSq then
            local dy = ys[idx] - y
            local dsq = dx2 + dy * dy
            if dsq <= radiusSq then
                local key = base + idx
                if not filterFn or filterFn(key, idx, g) then
                    results[#results + 1] = { key = key, dist = sqrt(dsq) }
                end
            end
        end
    end
end

local function byDist(a, b)
    if a.dist ~= b.dist then return a.dist < b.dist end
    return a.key < b.key
end






function Graph:_nearestOne(g, inst, x, y, radiusSq, maxRing, filterFn)
    local grid, xs, ys = g._grid, g.x, g.y
    local cx0, cy0 = floor(x / CELL), floor(y / CELL)
    local base = inst * KEY_BASE
    local bestSq, bestIdx
    local function scan(cx, cy)
        local x0, y0 = cx * CELL, cy * CELL
        local gx, gy = 0, 0
        if x < x0 then gx = x0 - x elseif x > x0 + CELL then gx = x - (x0 + CELL) end
        if y < y0 then gy = y0 - y elseif y > y0 + CELL then gy = y - (y0 + CELL) end
        if gx * gx + gy * gy > radiusSq then return end
        local k = cellKey(cx, cy)
        local cell = grid[k]
        if not cell then return end

        local first, last = cellSpan(g, k, cell, x, x0, radiusSq)
        for i = first, last do
            local idx = cell[i]
            local dx = xs[idx] - x
            local dx2 = dx * dx
            if dx2 <= (bestSq or radiusSq) then
                local dy = ys[idx] - y
                local dsq = dx2 + dy * dy
                if dsq <= radiusSq and (not bestSq or dsq < bestSq or (dsq == bestSq and idx < bestIdx))
                    and (not filterFn or filterFn(base + idx, idx, g)) then
                    bestSq, bestIdx = dsq, idx
                end
            end
        end
    end
    for r = 0, maxRing do
        if r == 0 then
            scan(cx0, cy0)
        else
            for i = -r, r do
                scan(cx0 + i, cy0 - r)
                scan(cx0 + i, cy0 + r)
            end
            for j = -r + 1, r - 1 do
                scan(cx0 - r, cy0 + j)
                scan(cx0 + r, cy0 + j)
            end
        end
        if bestSq and sqrt(bestSq) <= r * CELL then break end
    end
    if not bestSq then return {} end
    return { { key = base + bestIdx, dist = sqrt(bestSq) } }
end


function Graph:Nearest(inst, x, y, radiusYards, maxCount, filterFn)
    local results = {}
    local g = graphFor(inst)
    if not g or x == nil or y == nil then return results end
    radiusYards = radiusYards or self.ATTACH_RADIUS
    maxCount = maxCount or 1
    local grid = g._grid
    local radiusSq = radiusYards * radiusYards
    local cx0, cy0 = floor(x / CELL), floor(y / CELL)
    local base = inst * KEY_BASE
    local maxRing = ceil(radiusYards / CELL)
    if maxCount == 1 then return self:_nearestOne(g, inst, x, y, radiusSq, maxRing, filterFn) end
    for r = 0, maxRing do
        if r == 0 then
            scanCell(g, grid, cx0, cy0, x, y, radiusSq, filterFn, base, results)
        else
            for i = -r, r do
                scanCell(g, grid, cx0 + i, cy0 - r, x, y, radiusSq, filterFn, base, results)
                scanCell(g, grid, cx0 + i, cy0 + r, x, y, radiusSq, filterFn, base, results)
            end
            for j = -r + 1, r - 1 do
                scanCell(g, grid, cx0 - r, cy0 + j, x, y, radiusSq, filterFn, base, results)
                scanCell(g, grid, cx0 + r, cy0 + j, x, y, radiusSq, filterFn, base, results)
            end
        end

        if #results >= maxCount then
            tsort(results, byDist)
            if results[maxCount].dist <= r * CELL then break end
        end
    end
    tsort(results, byDist)
    for i = #results, maxCount + 1, -1 do results[i] = nil end
    return results
end









local function floorFromMap(uiMapID, g)
    if not uiMapID then return nil end
    local maps = FGPS.Data and FGPS.Data.maps
    local m = maps and maps[uiMapID]
    if m and (m.kind == 4 or m.kind == 5) then return uiMapID end
    if m and m.kind == 3 and g and g._floors and g._floors[uiMapID] then return uiMapID end
    return nil
end


local function floorMatches(g, idx, posFloor)
    local flags = g.f and g.f[idx] or 0
    local nodeFloor = g.m and g.m[idx] or nil
    if posFloor == nil then
        return nodeFloor == nil and flags % (FLAG_INDOOR * 2) < FLAG_INDOOR
    end
    return nodeFloor == posFloor
end


local function poiAnchor(g, poiIndex)
    local anchors = g._poiAnchor
    if not anchors then
        anchors = {}
        for idx, p in pairs(g.pi or {}) do
            if not anchors[p] or idx < anchors[p] then anchors[p] = idx end
        end
        g._poiAnchor = anchors
    end
    return anchors[poiIndex]
end






local function placeFilter(self, g, inst, x, y, list, place, isolated, out)
    local surf = g._surf
    if not surf then return list end
    local base = inst * KEY_BASE
    local first, last = surf.first, surf.last
    local function inBlock(idx) return idx >= first and idx <= last end
    local function keep(test)
        local kept = {}
        for i = 1, #list do
            if test(list[i], list[i].key - base) then kept[#kept + 1] = list[i] end
        end
        return kept
    end



    local reach = self.SURFACE_ATTACH_RADIUS
    local isoAt = g._isoAt
    local nearest = self:Nearest(inst, x, y, reach, 1, function(_, idx)
        local hit = isoAt and isoAt(idx) or nil
        if not isoAt then hit = isolated[idx] end
        return inBlock(idx) and not hit
    end)[1]
    if nearest then
        local _, indoor, stacked = placeOf(g, nearest.key - base)
        if indoor or stacked then
            local xs, ys, reachSq = g.x, g.y, reach * reach
            local kept = keep(function(_, idx)
                local dx, dy = xs[idx] - x, ys[idx] - y
                return inBlock(idx) and dx * dx + dy * dy <= reachSq
            end)
            if #kept > 0 then
                list = kept
                out.inSurface = true
            end
        end
    end





    if type(place) ~= "table" or place.indoor == nil then
        if out.inSurface then return list end
        local outside = keep(function(_, idx) return not select(2, placeOf(g, idx)) end)
        return #outside > 0 and outside or list
    end
    if place.indoor then
        local indoors = keep(function(_, idx) return select(2, placeOf(g, idx)) end)
        if #indoors == 0 then

            out.placeFallback = true
            return list
        end
        if place.name then
            local named = keep(function(_, idx) return placeOf(g, idx) == place.name end)
            if #named > 0 then return named end

            out.placeLoose = true
        end
        return indoors
    end
    local outdoors = keep(function(_, idx) return not select(2, placeOf(g, idx)) end)
    if #outdoors == 0 then
        out.placeFallback = true
        return list
    end
    return outdoors
end


















function Graph:AttachCandidates(inst, x, y, opts)
    opts = opts or {}
    local out = {}
    local g = graphFor(inst)
    if not g or x == nil or y == nil then return out end
    local allowUnverified = opts.allowUnverified ~= false
    local radius = allowUnverified and (opts.radius or self.ATTACH_RADIUS) or self.ATTACH_VERIFIED_RADIUS
    out.radius = radius
    local maxCount = opts.maxCount or self.ATTACH_MAX
    local posFloor = opts.floor or floorFromMap(opts.map, g)
    local n = g.n or 0









    local meshFirst = g._mesh and g._mesh.first or nil
    local meshLast = g._meshLast or n
    local gridFirst = g._tgrid and g._tgrid.first or nil

    local tailFirst = meshFirst or gridFirst or huge
    local isolated, smallPiece, offPiece = ensurePieces(g, inst)


    local isoAt, smallAt, offAt = g._isoAt, g._smallAt, g._offAt
    local function pieceIso(idx)
        if isoAt then return isoAt(idx) end
        return isolated[idx]
    end
    local function pieceSmall(idx)
        if smallAt then return smallAt(idx) end
        return smallPiece[idx]
    end
    local function pieceOff(idx)
        if offAt then return offAt(idx) end
        return offPiece[idx]
    end
    local function filter(_, idx, graph)
        if idx >= tailFirst and idx <= n then return false end
        if pieceIso(idx) or pieceSmall(idx) then return false end
        return floorMatches(graph, idx, posFloor)
    end
    local function smallFilter(_, idx, graph)
        if idx >= tailFirst and idx <= n then return false end
        return pieceSmall(idx) ~= nil and floorMatches(graph, idx, posFloor)
    end
    local function meshFilter(_, idx, graph)
        return idx >= meshFirst and idx <= meshLast and not pieceIso(idx) and floorMatches(graph, idx, posFloor)
    end
    local function gridFilter(_, idx, graph)
        return idx >= gridFirst and idx <= n and not pieceIso(idx) and floorMatches(graph, idx, posFloor)
    end
    local nodes = self:Nearest(inst, x, y, radius, maxCount * 3, filter)
    local smallNodes = self:Nearest(inst, x, y, radius, self.SMALL_ATTACH_MAX, smallFilter)
    if #nodes == 0 and #smallNodes == 0 and posFloor ~= nil and not opts.strictFloor then


        posFloor = nil
        nodes = self:Nearest(inst, x, y, radius, maxCount * 3, filter)
        smallNodes = self:Nearest(inst, x, y, radius, self.SMALL_ATTACH_MAX, smallFilter)
        out.floorFallback = (#nodes > 0 or #smallNodes > 0) or nil
    end
    for i = 1, #smallNodes do nodes[#nodes + 1] = smallNodes[i] end


    local meshNodes
    if meshFirst and allowUnverified then
        meshNodes = self:Nearest(inst, x, y, radius, self.MESH_ATTACH_MAX, meshFilter)
    end


    local gridNodes
    if gridFirst and allowUnverified then
        gridNodes = self:Nearest(inst, x, y, radius, self.GRID_ATTACH_MAX, gridFilter)
    end
    out.baseCount = 0
    if #nodes == 0 and not (meshNodes and #meshNodes > 0) and not (gridNodes and #gridNodes > 0) then return out end

    local best = {}
    local xs, ys = g.x, g.y
    local base = inst * KEY_BASE
    local radiusSq = radius * radius



    local heights, guesses = g.z, g.zg
    local function heightOf(idx)
        return unpackHeight(heights, idx)
    end

    local function guessOf(idx)
        local z = heightOf(idx)
        if z == nil and idx <= n then z = unpackHeight(guesses, idx) end
        return z
    end


    local function footHeights(idx, nb, t)
        local footZ, footZg
        local za, zb = heightOf(idx), heightOf(nb)
        if za and zb then footZ = za + t * (zb - za) end
        za, zb = guessOf(idx), guessOf(nb)
        if za and zb then footZg = za + t * (zb - za) end
        return footZ, footZg
    end
    local function doubtOf(kind, entryIndex)
        if kind ~= 4 or not entryIndex then return nil end
        return self:EdgeDoubt(inst, entryIndex)
    end

    local function offer(cand)
        local cur = best[cand.key]
        if not cur or cand.attachYards < cur.attachYards or (cand.attachYards == cur.attachYards and cand.dist < cur.dist) then
            best[cand.key] = cand
        end
    end

    local _projShape = {}
    local function project(idx, nb, kind, nodeDist, entryIndex)
        if not floorMatches(g, nb, posFloor) then return end
        local ax, ay, bx, by = xs[idx], ys[idx], xs[nb], ys[nb]
        if not bx then return end

        if entryIndex and g._es and trustedShapeLength(g._es, entryIndex, kind, chordYards(g, idx, nb)) then
            local nPts = edgeShapePoints(g._es, entryIndex, ax, ay, _projShape)
            if nPts > 0 then
                local bestPerp, bestFx, bestFy, bestAlong, total = nil, nil, nil, 0, 0
                local px0, py0 = ax, ay
                local function consider(qx, qy, rx, ry, alongBefore)
                    local vx, vy = rx - qx, ry - qy
                    local len2 = vx * vx + vy * vy
                    if len2 <= 0 then return end
                    local segLen = sqrt(len2)
                    local t = ((x - qx) * vx + (y - qy) * vy) / len2
                    if t < 0 then t = 0 elseif t > 1 then t = 1 end
                    local fx, fy = qx + t * vx, qy + t * vy
                    local dx, dy = fx - x, fy - y
                    local perpSq = dx * dx + dy * dy
                    if perpSq > radiusSq then return end
                    local perp = sqrt(perpSq)
                    if bestPerp and perp >= bestPerp then return end
                    bestPerp, bestFx, bestFy = perp, fx, fy
                    bestAlong = alongBefore + t * segLen
                end
                for i = 1, nPts do
                    local p = _projShape[i]
                    consider(px0, py0, p.x, p.y, total)
                    total = total + sqrt((p.x - px0) * (p.x - px0) + (p.y - py0) * (p.y - py0))
                    px0, py0 = p.x, p.y
                end
                consider(px0, py0, bx, by, total)
                total = total + sqrt((bx - px0) * (bx - px0) + (by - py0) * (by - py0))
                if bestPerp and bestPerp < nodeDist and total > 0 then
                    local footZ, footZg = footHeights(idx, nb, bestAlong / total)
                    local doubt = doubtOf(kind, entryIndex)
                    offer({ key = base + idx, dist = bestPerp + bestAlong, kind = KIND_ATTACH,
                            attachYards = bestPerp, segYards = bestAlong, segKind = kind,
                            fx = bestFx, fy = bestFy, otherKey = base + nb, footZ = footZ, footZg = footZg, shaped = true,
                            segDoubt = doubt })
                    offer({ key = base + nb, dist = bestPerp + (total - bestAlong), kind = KIND_ATTACH,
                            attachYards = bestPerp, segYards = total - bestAlong, segKind = kind,
                            fx = bestFx, fy = bestFy, otherKey = base + idx, footZ = footZ, footZg = footZg, shaped = true,
                            segDoubt = doubt })
                    return
                end
            end
        end
        local vx, vy = bx - ax, by - ay
        local len2 = vx * vx + vy * vy
        if len2 <= 0 then return end
        local t = ((x - ax) * vx + (y - ay) * vy) / len2
        if t <= 0 or t >= 1 then return end
        local fx, fy = ax + t * vx, ay + t * vy
        local px, py = fx - x, fy - y
        local perpSq = px * px + py * py
        if perpSq > radiusSq then return end
        local perp = sqrt(perpSq)
        if perp >= nodeDist then return end
        local segLen = sqrt(len2)
        local footZ, footZg = footHeights(idx, nb, t)
        local doubt = doubtOf(kind, entryIndex)
        offer({ key = base + idx, dist = perp + t * segLen, kind = KIND_ATTACH, attachYards = perp, segYards = t * segLen,
                segKind = kind, fx = fx, fy = fy, otherKey = base + nb, footZ = footZ, footZg = footZg, segDoubt = doubt })
        offer({ key = base + nb, dist = perp + (1 - t) * segLen, kind = KIND_ATTACH, attachYards = perp, segYards = (1 - t) * segLen,
                segKind = kind, fx = fx, fy = fy, otherKey = base + idx, footZ = footZ, footZg = footZg, segDoubt = doubt })
    end

    for i = 1, #nodes do
        local entry = nodes[i]
        local idx = entry.key - base
        offer({ key = entry.key, dist = entry.dist, kind = KIND_ATTACH, attachYards = entry.dist, segYards = 0, footZ = heightOf(idx),
                footZg = guessOf(idx) })
        if idx <= n then
            local eo, ep = g.eo, g._ep
            local first, stop = eo[idx], eo[idx + 1]
            if ep and first and stop then
                for e = first, stop - 1 do
                    local nb, kind = edgeAt(ep, e)
                    if nb and PROJECTABLE[kind] then project(idx, nb, kind, entry.dist, e) end
                end
            end
        end
    end




    if meshNodes then
        for i = 1, #meshNodes do
            local entry = meshNodes[i]
            offer({ key = entry.key, dist = entry.dist, kind = KIND_ATTACH, attachYards = entry.dist, segYards = 0,
                    footZ = heightOf(entry.key - base), footZg = guessOf(entry.key - base), mesh = true })
        end
    end


    if gridNodes then
        for i = 1, #gridNodes do
            local entry = gridNodes[i]
            offer({ key = entry.key, dist = entry.dist, kind = KIND_ATTACH, attachYards = entry.dist, segYards = 0,
                    footZ = heightOf(entry.key - base), footZg = guessOf(entry.key - base), grid = true })
        end
    end

    local gathered = {}
    for _, cand in pairs(best) do gathered[#gathered + 1] = cand end
    local place = opts.place
    if place == nil and opts.poiIndex and g._surf then


        local anchor = poiAnchor(g, opts.poiIndex)
        if anchor and anchor >= g._surf.first and anchor <= g._surf.last then
            local name, indoor = placeOf(g, anchor)
            place = { indoor = indoor, name = name }
        end
    end
    gathered = placeFilter(self, g, inst, x, y, gathered, place, isolated, out)
    for i = 1, #gathered do out[i] = gathered[i] end
    tsort(out, byDist)


    local kept, small = 0, 0
    for i = 1, #out do
        local cand = out[i]
        local keep = kept < maxCount
        if keep and pieceSmall(cand.key - base) then
            small = small + 1
            keep = small <= self.SMALL_ATTACH_MAX
        end
        if keep then
            kept = kept + 1
            out[kept] = cand
        end
    end
    for i = #out, kept + 1, -1 do out[i] = nil end


    if opts.poiIndex and g.pi then
        local poiKey
        for i = 1, #out do
            if g.pi[out[i].key - base] == opts.poiIndex then poiKey = i break end
        end
        if not poiKey then
            for idx, pIndex in pairs(g.pi) do
                if pIndex == opts.poiIndex then
                    local dx, dy = xs[idx] - x, ys[idx] - y
                    local d = sqrt(dx * dx + dy * dy)
                    if d <= radius and not pieceIso(idx) and floorMatches(g, idx, posFloor) then
                        out[#out + 1] = { key = base + idx, dist = d, kind = KIND_ATTACH, attachYards = d, segYards = 0, poi = true,
                                          footZ = heightOf(idx), footZg = guessOf(idx) }
                        poiKey = #out
                    end
                    break
                end
            end
        end
        if poiKey then
            local cand = table.remove(out, poiKey)
            cand.poi = true
            table.insert(out, 1, cand)
        end
    end






    if not (type(opts.place) == "table" and opts.place.indoor) then
        local have = {}
        for i = 1, #out do have[out[i].key] = true end
        local hits = self:Nearest(inst, x, y, self.ROAD_POINT_ATTACH_YARDS, 4, function(_, idx, graph)
            if idx >= tailFirst and idx <= n then return false end
            return not pieceIso(idx) and not pieceSmall(idx) and floorMatches(graph, idx, posFloor)
        end)
        for i = 1, #hits do
            local hit = hits[i]
            if not have[hit.key] then
                local onRoad = false
                self:Neighbors(hit.key, function(_, kind)
                    if kind == 18 or kind == 17 or kind == 4 or kind == 2 then onRoad = true end
                end)
                if onRoad then
                    local idx = hit.key - base
                    out[#out + 1] = { key = hit.key, dist = hit.dist, kind = KIND_ATTACH, attachYards = hit.dist,
                                      segYards = 0, footZ = heightOf(idx), footZg = guessOf(idx), road = true }
                    have[hit.key] = true
                end
            end
        end
    end







    if opts.free and not out.inSurface and not (type(opts.place) == "table" and opts.place.indoor) and #out > 0 then
        local onLargest = false
        for i = 1, #out do
            if not pieceOff(out[i].key - base) then onLargest = true break end
        end
        if not onLargest then
            local surf = g._surf
            local hits = self:Nearest(inst, x, y, self.FREE_ATTACH_YARDS, self.FREE_ATTACH_MAX, function(_, idx, graph)
                if pieceIso(idx) or pieceOff(idx) or not floorMatches(graph, idx, posFloor) then return false end
                return not (surf and idx >= surf.first and idx <= surf.last and select(2, placeOf(graph, idx)))
            end)
            for i = 1, #hits do
                local idx = hits[i].key - base
                out[#out + 1] = { key = hits[i].key, dist = hits[i].dist, kind = KIND_ATTACH, attachYards = hits[i].dist,
                                  segYards = 0, footZ = heightOf(idx), footZg = guessOf(idx), free = true }
            end

            if #hits > 0 then out.freeMain = #hits end
        end
    end



    local baseCount = 0
    for i = 1, #out do
        local cand = out[i]
        if not cand.mesh and not pieceSmall(cand.key - base) then baseCount = baseCount + 1 end
        local idx = cand.key - base
        if g._surf and idx >= g._surf.first and idx <= g._surf.last then
            local room, indoor, stacked = placeOf(g, idx)
            cand.room, cand.indoor, cand.stacked = room, indoor or nil, stacked or nil
        end


        if pieceOff(idx) then cand.offMain = true end
    end
    out.baseCount = baseCount
    return out
end






function Graph:AttachProgressive(inst, x, y, opts)
    opts = opts or {}
    local copy = {}
    for k, v in pairs(opts) do copy[k] = v end
    if copy.allowUnverified == false then
        copy.radius = nil
        local list = self:AttachCandidates(inst, x, y, copy)
        return list, list.radius or self.ATTACH_VERIFIED_RADIUS
    end








    local radii = opts.radii or self.ATTACH_RADII
    local list, used, firstHit = {}, nil, nil
    for i = 1, #radii do
        copy.radius = radii[i]
        used = radii[i]
        local found = self:AttachCandidates(inst, x, y, copy)
        if #found > 0 then
            list = found
            firstHit = firstHit or radii[i]
            if (found.baseCount or 0) > 0 then break end
        end
    end
    return list, firstHit or used
end




local HUB_CELL = Graph.HUB_CELL

local function ensureHubs(g, inst)
    if g._hubCells then return g._hubCells end
    local cells, keys, fixedNodes, fixedSeen = {}, {}, {}, {}
    local n, flags, xs, ys = g.n or 0, g.f, g.x, g.y
    local base = inst * KEY_BASE
    if type(flags) == "table" then
        for idx, f in pairs(flags) do
            if idx <= n and xs[idx] and ys[idx] then
                if isHubFlags(f) then
                    keys[#keys + 1] = base + idx
                    local k = cellKey(floor(xs[idx] / HUB_CELL), floor(ys[idx] / HUB_CELL))
                    local cell = cells[k]
                    if not cell then cells[k] = { idx } else cell[#cell + 1] = idx end
                end


                if f % 16 >= 2 then
                    fixedSeen[idx] = true
                    fixedNodes[#fixedNodes + 1] = base + idx
                end
            end
        end
    end

    if type(g.ts) == "table" then
        for idx in pairs(g.ts) do
            if idx <= n and xs[idx] and ys[idx] and not fixedSeen[idx] then
                fixedSeen[idx] = true
                fixedNodes[#fixedNodes + 1] = base + idx
            end
        end
    end
    tsort(keys)
    tsort(fixedNodes)
    g._hubCells, g._hubKeys, g._fixedNodes = cells, keys, fixedNodes
    return cells
end



function Graph:Hubs(inst)
    local g = graphFor(inst)
    if not g then return {} end
    ensureHubs(g, inst)
    return g._hubKeys
end








function Graph:HubCells(inst, keep)
    local g = graphFor(inst)
    if not g then return {} end
    local cells = ensureHubs(g, inst)
    local flags, base, out = g.f, inst * KEY_BASE, {}
    for k, cell in pairs(cells) do
        local kept
        for c = 1, #cell do
            local idx = cell[c]
            if keep(base + idx, flags and flags[idx] or 0) then
                kept = kept or {}
                kept[#kept + 1] = idx
            end
        end
        if kept then out[k] = kept end
    end
    return out
end

function Graph:HubsNear(inst, x, y, radiusYards, fn, only)
    local g = graphFor(inst)
    if not g or x == nil or y == nil or not radiusYards or radiusYards <= 0 then return 0 end
    local cells = only or ensureHubs(g, inst)
    if next(cells) == nil then return 0 end
    local xs, ys, flags = g.x, g.y, g.f
    local base = inst * KEY_BASE
    local radiusSq = radiusYards * radiusYards
    local cx, cy = floor(x / HUB_CELL), floor(y / HUB_CELL)
    local r = ceil(radiusYards / HUB_CELL)
    local found = 0
    for i = -r, r do
        for j = -r, r do
            local cell = cells[cellKey(cx + i, cy + j)]
            if cell then
                for c = 1, #cell do
                    local idx = cell[c]
                    local dx, dy = xs[idx] - x, ys[idx] - y
                    local dsq = dx * dx + dy * dy
                    if dsq <= radiusSq then
                        found = found + 1
                        fn(base + idx, sqrt(dsq), flags and flags[idx] or 0)
                    end
                end
            end
        end
    end
    return found
end






local FIXED_KINDS = { [7] = true, [9] = true, [10] = true, [11] = true }

function Graph:FixedEdges(inst)
    local g = graphFor(inst)
    if not g then return {} end
    if g._fixedEdges then return g._fixedEdges end
    ensureHubs(g, inst)
    local list = {}
    local xs, ys = g.x, g.y
    local fromKey, fx, fy
    local function collect(toKey, kind, yards, seconds, transportID)
        if not FIXED_KINDS[kind] then return end
        local toInst, toIdx = splitKey(toKey)
        if toInst ~= inst or not xs[toIdx] then return end
        list[#list + 1] = { from = fromKey, to = toKey, kind = kind, yards = yards, seconds = seconds, transportID = transportID,
                            fx = fx, fy = fy, tx = xs[toIdx], ty = ys[toIdx] }
    end
    for _, key in ipairs(g._fixedNodes) do
        local idx = key - inst * KEY_BASE
        fromKey, fx, fy = key, xs[idx], ys[idx]
        self:Neighbors(key, collect)
    end
    g._fixedEdges = list
    return list
end








function Graph:CrossLinks(inst)
    local cache = self._crossLinks
    if not cache then
        cache = {}
        self._crossLinks = cache
    end
    local entry = cache[inst]
    if entry then return entry end
    entry = { out = {}, into = {} }
    cache[inst] = entry
    local g = graphFor(inst)
    if not g then return entry end
    for fromKey, list in pairs(self._links or ensureLinks()) do
        local fromInst, fromIdx = splitKey(fromKey)
        for i = 1, #list do
            local link = list[i]
            local toInst, toIdx = splitKey(link.toKey)
            local side, idx
            if fromInst == inst and toInst ~= inst then
                side, idx = entry.out, fromIdx
            elseif toInst == inst and fromInst ~= inst then
                side, idx = entry.into, toIdx
            end
            if side and g.x[idx] then
                side[#side + 1] = { from = fromKey, to = link.toKey, kind = link.kind, seconds = link.seconds,
                                    transportID = link.transportID, x = g.x[idx], y = g.y[idx] }
            end
        end
    end
    return entry
end






function Graph:Landmarks(inst)
    local g = graphFor(inst)
    if not g then return nil end
    if g._lm ~= nil then return g._lm or nil end
    local lm = g.lm
    local ok = type(lm) == "table" and type(lm.k) == "number" and lm.k >= 1 and type(lm.row) == "number" and lm.row >= 1
        and lm.digits == Graph.LANDMARK_DIGITS
        and lm.cell == CELL and type(lm.off) == "number" and type(lm.speed) == "number" and lm.speed > 0
        and type(lm.nc) == "number" and type(lm.c) == "table" and type(lm.ids) == "table" and type(lm.hubs) == "table"
        and type(lm.p) == "table" and type(lm.lo) == "table" and type(lm.hi) == "table"
    if ok then
        for l = 1, lm.k do
            if type(lm.p[l]) ~= "table" or type(lm.lo[l]) ~= "table" or type(lm.hi[l]) ~= "table" then ok = false end
        end
    end
    g._lm = ok and lm or false
    return ok and lm or nil
end




function Graph:LandmarkCells(inst, yieldFn)
    local g = graphFor(inst)
    local lm = self:Landmarks(inst)
    if not lm then return nil end
    if g._lmCells then return g._lmCells end
    local cells, rows, row, off = {}, lm.c, lm.row, lm.off
    local unpack = Graph.UnpackLandmark
    for slot = 1, lm.nc do
        local cx = unpack(rows, row, 2 * slot - 1, 3)
        local cy = unpack(rows, row, 2 * slot, 3)
        if not cx or not cy then return nil end
        cells[cellKey(cx - off, cy - off)] = slot
        if yieldFn and slot % 2000 == 0 and yieldFn() == false then return nil end
    end
    g._lmCells = cells
    return cells
end







local VERIFIED_KINDS = { [1] = true, [2] = true, [5] = true, [6] = true, [12] = true }



local function computeStats(g)
    local xs, ys, eo, ep = g.x, g.y, g.eo, g._ep
    local n = g.n or 0
    local edges = (eo[n + 1] or 1) - 1
    local verified, inferred, water, taxi, transport, portal = 0, 0, 0, 0, 0, 0
    local road, street = 0, 0
    for i = 1, n do
        local first, stop = eo[i], eo[i + 1]
        if ep and first and stop then
            local x, y = xs[i], ys[i]
            for e = first, stop - 1 do
                local nb, kind = edgeAt(ep, e)
                if not nb then break end
                local dx, dy = xs[nb] - x, ys[nb] - y
                local yards = sqrt(dx * dx + dy * dy)
                if SYMMETRIC_KINDS[kind] then yards = yards / 2 end
                if VERIFIED_KINDS[kind] then verified = verified + yards end
                if kind == 3 then inferred = inferred + yards end
                if kind == 4 then road = road + yards end
                if kind == 16 then street = street + yards end
                if kind == 5 then water = water + yards end
                if kind == 8 then taxi = taxi + 1 end
                if kind == 9 or kind == 10 or kind == 11 then transport = transport + 1 end
                if kind == 7 then portal = portal + 1 end
            end
        end
    end
    local taxiNodes, transportStops, poiNodes = 0, 0, 0
    if g.tx then for _ in pairs(g.tx) do taxiNodes = taxiNodes + 1 end end
    if g.ts then for _ in pairs(g.ts) do transportStops = transportStops + 1 end end
    if g.pi then for _ in pairs(g.pi) do poiNodes = poiNodes + 1 end end
    local cells = 0
    if g._grid then for _ in pairs(g._grid) do cells = cells + 1 end end


    local meshNodes = g._mesh and math.max(0, (g._meshLast or n) - g._mesh.first + 1) or 0
    local gridNodes = g._tgrid and math.max(0, n - g._tgrid.first + 1) or 0
    local surfaceNodes = g._surf and (g._surf.last - g._surf.first + 1) or 0
    return { nodes = n, edges = edges, meshNodes = meshNodes, gridNodes = gridNodes, surfaceNodes = surfaceNodes, verifiedYards = verified, inferredYards = inferred, waterYards = water,
             roadYards = road, streetYards = street, taxiEdges = taxi, transportEdges = transport, portalEdges = portal, taxiNodes = taxiNodes,
             transportStops = transportStops, poiNodes = poiNodes, gridCells = cells }
end

function Graph:Stats(inst)
    local g = graphFor(inst)
    if not g then return nil end
    local stats = g._stats
    if not stats then
        stats = computeStats(g)
        g._stats = stats
    end
    local out = {}
    for k, v in pairs(stats) do out[k] = v end
    out.inst = inst
    return out
end


function Graph:Instances()
    local out = {}
    local graphs = dataGraphs()
    if type(graphs) == "table" then
        for inst in pairs(graphs) do out[#out + 1] = inst end
    end
    tsort(out)
    return out
end

function Graph:Init()

    self.initialized = true
    if FGPS.Events and not self.partsBound then
        self.partsBound = true


        FGPS.Events:Register("DATA_PART_LOADED", function(_, inst)
            Graph._taxiIndex, Graph._transportIndex = nil, nil
            local g = Graph.loaded[inst]
            if g then g._lm, g._lmCells = nil, nil end
        end, self)
    end
end
