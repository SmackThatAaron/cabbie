





















local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local Events = FGPS.Events
local sqrt, floor, format, type, pairs, ipairs, tostring, tonumber = math.sqrt, math.floor, string.format, type, pairs, ipairs, tostring, tonumber

local Destinations = {
    MAX_RECENTS = 20,
    MAX_FAVORITES = 100,
    SNAP_NAME_YARDS = 25,
    REACHABLE_YARDS = 150,
    ADJUST_YARDS = 400,
    EQUAL_YARDS = 5,
}
FGPS.Destinations = Destinations


local TYPE_NAMES = {
    [1] = "town", [2] = "landmark", [3] = "dungeon", [4] = "raid", [5] = "capital", [6] = "flightmaster",
    [7] = "inn", [8] = "vendor", [9] = "repair", [10] = "mailbox", [11] = "bank", [12] = "auction",
    [13] = "trainer", [14] = "dock", [15] = "tram", [16] = "graveyard", [17] = "portal", [18] = "zone",
    [19] = "battleground", [20] = "stable", [21] = "subzone",
}
local TYPE_CODES = {}
for code, name in pairs(TYPE_NAMES) do TYPE_CODES[name] = code end
Destinations.TYPE_NAMES, Destinations.TYPE_CODES = TYPE_NAMES, TYPE_CODES


local TYPE_LABELS = {
    town = "Town", landmark = "Landmark", dungeon = "Dungeon", raid = "Raid", capital = "Capital city",
    flightmaster = "Flight master", inn = "Inn", vendor = "Vendor", repair = "Repair", mailbox = "Mailbox",
    bank = "Bank", auction = "Auction house", trainer = "Trainer", dock = "Dock", tram = "Tram", graveyard = "Graveyard",
    portal = "Portal", zone = "Zone", battleground = "Battleground", stable = "Stable master", subzone = "Area",
    taxi = "Flight master", quest = "Quest", coord = "Coordinates", custom = "Custom", service = "Service",
}


local TYPE_PRIORITY = {
    capital = 1, town = 2, zone = 3, taxi = 4, flightmaster = 4, inn = 5, dungeon = 6, raid = 6, landmark = 7,
    dock = 8, tram = 8, portal = 9, bank = 10, auction = 10, mailbox = 11, repair = 12, vendor = 13, trainer = 13,
    stable = 14, graveyard = 15, battleground = 16, subzone = 17, service = 5, coord = 20, custom = 20, quest = 20,
}

local SCORE_EXACT, SCORE_PREFIX, SCORE_WORD, SCORE_SUBSTRING, SCORE_ZONE = 100, 80, 60, 40, 30








local KIND_WORDS = {
    bank = "bank", banker = "bank",
    auction = "auction", ["auction house"] = "auction", auctioneer = "auction",
    repair = "repair",
    flight = "flightmaster", ["flight master"] = "flightmaster", flightmaster = "flightmaster",
    trainer = "trainer", vendor = "vendor",
    inn = "inn", innkeeper = "inn",
}


local WORD_SYNONYMS = { boat = "dock", ship = "dock" }




local function dist(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return sqrt(dx * dx + dy * dy)
end
Destinations.Distance = dist

local function lower(s) return Util.Lower(s) end

local function maps() return FGPS.Data and FGPS.Data.maps or nil end
local function poi() return FGPS.Data and FGPS.Data.poi or nil end
local function zoneNames() return FGPS.Data and FGPS.Data.zoneNames or {} end
local function dataVersion()
    local manifest = FGPS.Data and FGPS.Data.manifest
    return manifest and manifest.dataVersion or nil
end




local function poiKeyOf(i)
    local P = poi()
    local src = P and P.src and P.src[i]
    if type(src) ~= "string" or src == "" or not P.type[i] then return nil end
    return src .. "|" .. P.type[i]
end
Destinations.PoiKey = poiKeyOf




local keyRows = { source = nil, count = nil, rows = nil }
local function keyRowsNow()
    local P = poi()
    if not P then return nil end
    if keyRows.source ~= P or keyRows.count ~= P.n then
        local rows = {}
        for i = 1, P.n do
            local k = poiKeyOf(i)
            if k then rows[k] = (rows[k] == nil) and i or false end
        end
        keyRows.source, keyRows.count, keyRows.rows = P, P.n, rows
    end
    return keyRows.rows
end

local function rowOfKey(key)
    local rows = keyRowsNow()
    return rows and rows[key] or nil
end



local function keyTrusted(key)
    local rows = keyRowsNow()
    return not rows or rows[key] ~= false
end

function Destinations.TypeName(code)
    return TYPE_NAMES[code] or "landmark"
end

function Destinations.TypeLabel(typeName)
    return L[TYPE_LABELS[typeName] or "Location"]
end


function Destinations.PlayerFactionCode()
    if UnitFactionGroup then
        local ok, faction = pcall(UnitFactionGroup, "player")
        if ok then
            if faction == "Alliance" then return 1 end
            if faction == "Horde" then return 2 end
        end
    end
    return 3
end


local function factionAllowed(fac, playerCode, allFactions)
    if allFactions or not fac or fac == 0 or fac == 3 or playerCode == 3 then return true end
    return fac == playerCode
end
Destinations.FactionAllowed = factionAllowed




local CAPITAL_FACTION = {
    stormwind = 1, ironforge = 1, darnassus = 1,
    orgrimmar = 2, ["thunder bluff"] = 2, undercity = 2,
}

local function capitalFactionOf(name)
    local key = lower(name or ""):gsub("^the%s+", ""):gsub("%s+city$", "")
    return CAPITAL_FACTION[key]
end
Destinations.CapitalFaction = capitalFactionOf



local function sideOf(i)
    local P = poi()
    if not P or not P.type[i] then return nil end
    local fac = P.fac and P.fac[i]
    if fac == 1 or fac == 2 then return fac end
    if P.type[i] == 5 then return capitalFactionOf(P.name[i]) end
    return nil
end
Destinations.PlaceFaction = sideOf



local function otherSide(fac, playerCode)
    if fac ~= 1 and fac ~= 2 then return nil end
    if factionAllowed(fac, playerCode or Destinations.PlayerFactionCode(), false) then return nil end
    return fac
end





local ANY_SIDE_TYPES = { town = true, capital = true }
local ITEM_TYPES = { vendor = true, repair = true }

local SIDE_LABELS = { [1] = "Alliance", [2] = "Horde" }



local function typeText(typeName, moreTypes, side)
    local text = Destinations.TypeLabel(typeName)
    if moreTypes then
        for i = 1, #moreTypes do text = text .. ", " .. Destinations.TypeLabel(moreTypes[i]) end
    end
    if SIDE_LABELS[side] then text = text .. ", " .. L[SIDE_LABELS[side]] end
    return text
end





function Destinations.PlayerPos()
    local C = FGPS.Coords
    if C and C.PlayerPos then return C.PlayerPos() end
    if not UnitPosition then return nil end
    local py, px, _, inst = UnitPosition("player")
    if not px or not py then return nil end
    local pos = { inst = inst, x = px, y = py }
    if C_Map and C_Map.GetBestMapForUnit then
        local map = C_Map.GetBestMapForUnit("player")
        if map then
            pos.map = map
            if C_Map.GetPlayerMapPosition then
                local v = C_Map.GetPlayerMapPosition(map, "player")
                if v then pos.mx, pos.my = v:GetXY() end
            end
        end
    end
    return pos
end

local function mapToWorld(uiMapID, mx, my)
    local C = FGPS.Coords
    if C and C.MapToWorld then return C.MapToWorld(uiMapID, mx, my) end
    local m = maps() and maps()[uiMapID]
    if not m or not m.minX then return nil end
    return m.inst, m.maxX - mx * (m.maxX - m.minX), m.maxY - my * (m.maxY - m.minY)
end
Destinations.MapToWorld = mapToWorld

local function worldToMap(inst, x, y, uiMapID)
    local C = FGPS.Coords
    if C and C.WorldToMap then return C.WorldToMap(inst, x, y, uiMapID) end
    local all = maps()
    if not all then return nil end
    local id = uiMapID
    if not id then
        local bestArea
        for mapID, m in pairs(all) do
            if m.kind == 3 and m.inst == inst and m.minX and x >= m.minX and x <= m.maxX and y >= m.minY and y <= m.maxY then
                local area = (m.maxX - m.minX) * (m.maxY - m.minY)
                if not bestArea or area < bestArea then id, bestArea = mapID, area end
            end
        end
    end
    local m = id and all[id]
    if not m or not m.minX or m.inst ~= inst then return nil end
    return id, (m.maxX - x) / (m.maxX - m.minX), (m.maxY - y) / (m.maxY - m.minY)
end
Destinations.WorldToMap = worldToMap

local function mapName(uiMapID)
    local m = maps() and maps()[uiMapID]
    if m and m.name then return m.name end
    if C_Map and C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, uiMapID)
        if ok and info and info.name then return info.name end
    end
    return nil
end
Destinations.MapName = mapName

local function zoneAt(inst, x, y)
    local C = FGPS.Coords
    if C and C.ZoneAt then return C.ZoneAt(inst, x, y) end
    local id = worldToMap(inst, x, y)
    if not id then return nil end
    return id, mapName(id)
end




local function round1(v) return floor(v * 10 + 0.5) / 10 end






local function deadEndTest(Graph)
    if not Graph.IsIsolated then return nil end
    return function(key)
        local ok, isolated = pcall(Graph.IsIsolated, Graph, key)
        return ok and isolated == true
    end
end



local function attachable(Graph, dest, radius)
    if not Graph.AttachCandidates then return false end
    local ok, list = pcall(Graph.AttachCandidates, Graph, dest.inst, dest.x, dest.y, radius and { radius = radius } or nil)
    return ok and type(list) == "table" and #list > 0
end


function Destinations.ApplyReachability(dest)
    local Graph = FGPS.Graph
    if not Graph or not dest.inst or not dest.x then
        dest.reachable = false
        dest.reachableNote = "no_graph"
        return dest
    end
    if attachable(Graph, dest) then
        dest.reachable = true
        dest.reachableNote = nil
        return dest
    end
    local isDeadEnd = deadEndTest(Graph)
    if isDeadEnd and Graph.Nearest then



        local ok, near = pcall(Graph.Nearest, Graph, dest.inst, dest.x, dest.y, Destinations.REACHABLE_YARDS, 1)
        local first = ok and type(near) == "table" and near[1] or nil
        if first and first.key and isDeadEnd(first.key) and attachable(Graph, dest, Destinations.ADJUST_YARDS) then
            dest.reachable = true
            dest.reachableNote = nil
            return dest
        end
    end
    if Graph.Nearest and Graph.NodePos then
        local filter = isDeadEnd and function(key) return not isDeadEnd(key) end or nil
        local ok, near = pcall(Graph.Nearest, Graph, dest.inst, dest.x, dest.y, Destinations.ADJUST_YARDS, 1, filter)
        local best = ok and type(near) == "table" and near[1] or nil
        if best and best.key and best.dist and best.dist <= Destinations.ADJUST_YARDS then
            local okPos, nInst, nx, ny = pcall(Graph.NodePos, Graph, best.key)
            if okPos and nx and ny and (nInst == nil or nInst == dest.inst) then
                dest.originalX, dest.originalY = dest.x, dest.y
                dest.x, dest.y = round1(nx), round1(ny)
                dest.reachable = "adjusted"
                dest.adjustedYards = floor(best.dist + 0.5)
                local map, mx, my = worldToMap(dest.inst, dest.x, dest.y, dest.map)
                if map then dest.map, dest.mx, dest.my = map, mx, my end
                dest.reachableNote = nil
                return dest
            end
        end
    end
    dest.reachable = false
    dest.reachableNote = "no_verified_path"
    return dest
end


function Destinations.Resolve(dest)
    if type(dest) ~= "table" then return nil end
    if dest.reachable == nil then Destinations.ApplyReachability(dest) end
    return dest
end




local function finishDest(dest)
    if dest.map and (not dest.mx or not dest.my) then
        local map, mx, my = worldToMap(dest.inst, dest.x, dest.y, dest.map)
        if map then dest.map, dest.mx, dest.my = map, mx, my end
    end
    if not dest.zoneName then
        local zoneMap, zoneName = zoneAt(dest.inst, dest.x, dest.y)
        dest.zoneName = zoneName or (dest.map and mapName(dest.map)) or nil
        if not dest.map and zoneMap then
            local map, mx, my = worldToMap(dest.inst, dest.x, dest.y, zoneMap)
            if map then dest.map, dest.mx, dest.my = map, mx, my end
        end
    end
    return dest
end


local function nearestPOI(inst, x, y, radius, filter)
    local P = poi()
    if not P then return nil end
    local bestI, bestD
    local px, py, pinst = P.x, P.y, P.inst
    for i = 1, P.n do
        if pinst[i] == inst and (not filter or filter(i)) then
            local dx, dy = px[i] - x, py[i] - y
            if dx > -radius and dx < radius and dy > -radius and dy < radius then
                local d = sqrt(dx * dx + dy * dy)
                if d <= radius and (not bestD or d < bestD) then bestI, bestD = i, d end
            end
        end
    end
    return bestI, bestD
end
Destinations.NearestPOI = nearestPOI

local function destFromPOIIndex(i)
    local P = poi()
    if not P or not P.name[i] then return nil end
    local code = P.type[i]
    local dest = {
        kind = "poi", poiIndex = i, poiKey = poiKeyOf(i), name = P.name[i], inst = P.inst[i], x = P.x[i], y = P.y[i], map = P.map[i],
        type = TYPE_NAMES[code] or "landmark", typeCode = code, faction = sideOf(i),
        zoneName = zoneNames()[P.zone[i] or 0],
    }
    local ent = P.ent and P.ent[i]
    if ent and P.name[ent] then

        dest.entrance = { poiIndex = ent, poiKey = poiKeyOf(ent), name = P.name[ent], inst = P.inst[ent], x = P.x[ent], y = P.y[ent], map = P.map[ent] }
        dest.interior = { inst = dest.inst, x = dest.x, y = dest.y, map = dest.map }
        dest.inst, dest.x, dest.y, dest.map = P.inst[ent], P.x[ent], P.y[ent], P.map[ent]
        dest.mx, dest.my = nil, nil
    end
    return finishDest(dest)
end




function Destinations.FromMapClick(uiMapID, mx, my)
    if type(uiMapID) ~= "number" or type(mx) ~= "number" or type(my) ~= "number" then return nil, "bad_arguments" end
    local inst, x, y = mapToWorld(uiMapID, mx, my)
    if not inst then return nil, "no_world" end
    local dest = { kind = "coord", inst = inst, x = round1(x), y = round1(y), map = uiMapID, mx = mx, my = my }




    local clicked = maps() and maps()[uiMapID]
    if clicked and (clicked.kind == 1 or clicked.kind == 2) then
        local zoneMap, zoneName = zoneAt(inst, x, y)
        if zoneMap and zoneMap ~= uiMapID then
            local map, zx, zy = worldToMap(inst, x, y, zoneMap)
            if map then dest.map, dest.mx, dest.my = map, zx, zy end
        end
        dest.zoneName = zoneName
    end
    dest.zoneName = dest.zoneName or mapName(dest.map)
    local i = nearestPOI(inst, x, y, Destinations.SNAP_NAME_YARDS)
    if i then
        local P = poi()
        dest.kind = "poi"
        dest.poiIndex = i
        dest.poiKey = poiKeyOf(i)
        dest.name = P.name[i]
        dest.typeCode = P.type[i]
        dest.type = TYPE_NAMES[P.type[i]] or "landmark"
        dest.faction = sideOf(i)
    else
        dest.type = "coord"
        dest.name = format("%.1f, %.1f", (dest.mx or mx) * 100, (dest.my or my) * 100)
    end
    Destinations.ApplyReachability(dest)
    return dest
end


function Destinations.ParseCoords(text)
    if type(text) ~= "string" then return nil end
    local nums = {}
    local rest = text:gsub("(%-?%d+%.?%d*)", function(n)
        if #nums < 2 then
            nums[#nums + 1] = tonumber(n)
            return " "
        end
        return n
    end)
    if #nums < 2 then return nil end
    rest = rest:gsub("[,;:/]", " "):gsub("%s+", " ")
    rest = Util.Trim(rest)
    if rest == "" then rest = nil end
    return rest, nums[1], nums[2]
end

local function scoreName(key, q)
    if key == q then return SCORE_EXACT end
    if key:sub(1, #q) == q then return SCORE_PREFIX end
    if key:find(" " .. q, 1, true) then return SCORE_WORD end
    if key:find(q, 1, true) then return SCORE_SUBSTRING end
    return 0
end



Destinations.ScoreName = scoreName






function Destinations.ResolveZoneName(name)
    local all = maps()
    if not all or type(name) ~= "string" then return nil end
    local q = lower(Util.Trim(name))
    if q == "" then return nil end
    local bestID, bestScore, bestKind
    for id, m in pairs(all) do
        if m.name and m.minX and m.sys ~= 1 then
            local s = scoreName(lower(m.name), q)
            if s > 0 then
                local kindRank = (m.kind == 3) and 0 or 1
                if not bestScore or s > bestScore or (s == bestScore and (kindRank < bestKind or (kindRank == bestKind and id < bestID))) then
                    bestID, bestScore, bestKind = id, s, kindRank
                end
            end
        end
    end
    return bestID, bestScore
end


function Destinations.FromCoords(mapArg, x100, y100)
    if type(mapArg) == "string" and x100 == nil and y100 == nil then
        mapArg, x100, y100 = Destinations.ParseCoords(mapArg)
        if not x100 then return nil, "parse" end
    end
    x100, y100 = tonumber(x100), tonumber(y100)
    if not x100 or not y100 then return nil, "parse" end
    local uiMapID
    if type(mapArg) == "number" then
        uiMapID = mapArg
    elseif type(mapArg) == "string" and Util.Trim(mapArg) ~= "" then
        uiMapID = Destinations.ResolveZoneName(mapArg)
        if not uiMapID then return nil, "unknown_zone" end
    else
        local pos = Destinations.PlayerPos()
        uiMapID = pos and pos.map or nil
        if not uiMapID and C_Map and C_Map.GetBestMapForUnit then uiMapID = C_Map.GetBestMapForUnit("player") end
    end
    if not uiMapID then return nil, "no_map" end
    if x100 < 0 or x100 > 100 or y100 < 0 or y100 > 100 then return nil, "range" end
    local mx, my = x100 / 100, y100 / 100
    local inst, x, y = mapToWorld(uiMapID, mx, my)
    if not inst then return nil, "no_world" end
    local dest = { kind = "coord", type = "coord", inst = inst, x = round1(x), y = round1(y), map = uiMapID, mx = mx, my = my,
                   name = format("%.1f, %.1f", x100, y100), zoneName = mapName(uiMapID) }
    Destinations.ApplyReachability(dest)
    return dest
end

function Destinations.FromPOI(poiIndex)
    local dest = destFromPOIIndex(tonumber(poiIndex))
    if not dest then return nil, "no_poi" end
    Destinations.ApplyReachability(dest)
    return dest
end

function Destinations.FromTaxiNode(taxiNodeID)
    local taxi = FGPS.Data and FGPS.Data.taxi
    local node = taxi and taxi.nodes and taxi.nodes[taxiNodeID]
    if not node then return nil, "no_taxi_node" end
    local dest = { kind = "taxi", taxiNodeID = taxiNodeID, name = node.name, inst = node.inst, x = node.x, y = node.y,
                   map = node.map, mx = node.mx, my = node.my, type = "taxi", faction = (node.fac ~= 3 and node.fac ~= 0) and node.fac or nil }
    finishDest(dest)
    Destinations.ApplyReachability(dest)
    return dest
end




local index = { static = nil, learned = nil, learnedCount = -1,
                srcPoi = nil, srcPoiCount = nil, srcMaps = nil, srcTaxi = nil }

local function addEntry(list, e)
    e.key = lower(e.name)
    e.zoneKey = e.zoneName and lower(e.zoneName) or ""
    list[#list + 1] = e
end

local function buildStatic()
    local list = {}
    local P = poi()
    local names = zoneNames()
    local zoneEntryNames, flightNames = {}, {}
    if P then
        for i = 1, P.n do
            local code = P.type[i]
            local e = { kind = "poi", ref = i, name = P.name[i], inst = P.inst[i], x = P.x[i], y = P.y[i], map = P.map[i],
                        type = TYPE_NAMES[code] or "landmark", code = code, fac = sideOf(i) or 0, zoneName = names[P.zone[i] or 0] }
            if code == 18 then zoneEntryNames[lower(e.name)] = true end
            if code == 6 then flightNames[lower(e.name)] = true end
            addEntry(list, e)
        end
    end
    local all = maps()
    if all then
        for id, m in pairs(all) do
            if m.kind == 3 and m.minX and m.name and not zoneEntryNames[lower(m.name)] then
                addEntry(list, { kind = "zone", ref = id, name = m.name, inst = m.inst, x = (m.minX + m.maxX) / 2,
                                 y = (m.minY + m.maxY) / 2, map = id, type = "zone", code = 18, fac = 0, zoneName = m.name })
            end
        end
    end
    local taxi = FGPS.Data and FGPS.Data.taxi
    if taxi and taxi.nodes then

        for nodeID, n in pairs(taxi.nodes) do
            if n.name and not flightNames[lower(n.name)] then
                local fac = (n.fac == 3 or n.fac == nil) and 0 or n.fac
                local zone = n.map and mapName(n.map) or nil
                addEntry(list, { kind = "taxi", ref = nodeID, name = n.name, inst = n.inst, x = n.x, y = n.y, map = n.map,
                                 type = "taxi", code = 6, fac = fac, zoneName = zone })
            end
        end
    end
    return list
end

local function learnedServices()
    local Services = FGPS.ServiceSearch
    if Services and Services.Learned then return Services.Learned() end
    local DB = FGPS.DB
    return DB and DB.account and DB.account.learnedServices or {}
end




local function buildLearned()
    local list = {}
    local Services = FGPS.ServiceSearch
    local inData = Services and Services.InData
    for i, s in ipairs(learnedServices()) do
        if s.name and s.inst and s.x and s.y then
            local fac = s.fac or 0
            if inData and (fac == 0 or fac == 3) then
                local alliance, horde = inData(s, 1), inData(s, 2)
                if alliance and horde then fac = nil elseif alliance then fac = 2 elseif horde then fac = 1 end
            elseif inData and inData(s, fac) then
                fac = nil
            end
            if fac then
                addEntry(list, { kind = "service", ref = i, name = s.name, inst = s.inst, x = s.x, y = s.y, map = s.map,
                                 type = s.kind or "service", code = TYPE_CODES[s.kind or ""] or 0, fac = fac,
                                 zoneName = s.zoneName or (s.map and mapName(s.map)) or nil, learned = s })
            end
        end
    end
    return list
end

function Destinations.InvalidateIndex(learnedOnly)
    if not learnedOnly then index.static = nil end
    index.learned = nil
    index.learnedCount = -1
end

local function ensureIndex()
    local P, all, taxi = poi(), maps(), FGPS.Data and FGPS.Data.taxi or nil
    if not index.static or index.srcPoi ~= P or index.srcPoiCount ~= (P and P.n) or index.srcMaps ~= all or index.srcTaxi ~= taxi then
        index.static = buildStatic()
        index.srcPoi, index.srcPoiCount, index.srcMaps, index.srcTaxi = P, P and P.n, all, taxi
    end
    local learned = learnedServices()
    if not index.learned or index.learnedCount ~= #learned then
        index.learned = buildLearned()
        index.learnedCount = #learned
    end
    return index.static, index.learned
end

local function destFromEntry(e)
    if e.kind == "poi" then return destFromPOIIndex(e.ref) end
    if e.kind == "taxi" then
        local dest = { kind = "taxi", taxiNodeID = e.ref, name = e.name, inst = e.inst, x = e.x, y = e.y, map = e.map,
                       type = "taxi", zoneName = e.zoneName, faction = e.fac ~= 0 and e.fac or nil }
        return finishDest(dest)
    end
    if e.kind == "zone" then
        local dest = { kind = "custom", name = e.name, inst = e.inst, x = e.x, y = e.y, map = e.map, type = "zone",
                       zoneName = e.zoneName, uiMapID = e.ref }
        return finishDest(dest)
    end
    local s = e.learned or {}
    local dest = { kind = "service", name = e.name, inst = e.inst, x = e.x, y = e.y, map = e.map, mx = s.mx, my = s.my,
                   type = e.type, serviceKind = e.type, zoneName = e.zoneName, faction = e.fac ~= 0 and e.fac or nil, learned = true }
    return finishDest(dest)
end



local function labelFor(name, zoneName, typeName, moreTypes, side)
    local typeLabel = typeText(typeName, moreTypes, side)
    if zoneName and zoneName ~= "" and zoneName ~= name then
        return format("%s - %s (%s)", name, zoneName, typeLabel)
    end
    return format("%s (%s)", name, typeLabel)
end
Destinations.Label = labelFor

local function typeFilter(types)
    if not types then return nil end
    local set = {}
    for k, v in pairs(types) do
        local name = (type(k) == "number") and v or k
        if type(name) == "number" then name = TYPE_NAMES[name] end
        if type(name) == "string" then set[name] = true end
    end
    if set.flightmaster then set.taxi = true end
    if set.taxi then set.flightmaster = true end
    if next(set) == nil then return nil end
    return set
end





local function scoreEntry(e, words, whole)
    local total
    for _, w in ipairs(words) do
        local s = scoreName(e.key, w)
        if s == 0 and e.zoneKey ~= "" and (e.zoneKey:find(w, 1, true)) then s = SCORE_ZONE end
        if s == 0 then return 0 end
        if not total or s < total then total = s end
    end
    if total and whole then
        local s = scoreName(e.key, whole)
        if s > total then total = s end
    end
    return total or 0
end













function Destinations.Search(text, opts)
    opts = opts or {}
    local q = lower(Util.Trim(text or ""))
    if q == "" then return {} end
    local split = Util.Split(q, " ")
    if #split == 0 then return {} end


    local words, seenWord = {}, {}
    for i = 1, #split do
        local w = WORD_SYNONYMS[split[i]] or split[i]
        if not seenWord[w] then
            seenWord[w] = true
            words[#words + 1] = w
        end
    end

    local whole = #split > 1 and q or nil
    local limit = opts.limit or 25
    local playerCode = opts.faction == "Alliance" and 1 or opts.faction == "Horde" and 2 or Destinations.PlayerFactionCode()
    local allFactions = opts.allFactions or opts.faction == "all"
    local types = typeFilter(opts.types)
    local first = typeFilter(opts.first)
    local kindOf = KIND_WORDS[q] and typeFilter({ KIND_WORDS[q] }) or nil
    local kinds = opts.kinds and typeFilter(opts.kinds) or nil
    local pos = Destinations.PlayerPos()
    local static, learned = ensureIndex()

    local hits = {}
    local function consider(e)
        if types and not types[e.type] then return end
        if kinds and not kinds[e.kind] then return end
        local side = not allFactions and otherSide(e.fac, playerCode) or nil
        if side and e.learned then return end
        if side and not ANY_SIDE_TYPES[e.type] and not ITEM_TYPES[e.type] then return end
        local s, tier = scoreEntry(e, words, whole), 1
        if kindOf and kindOf[e.type] then
            s, tier = SCORE_EXACT, 0
        elseif first and first[e.type] and s >= SCORE_WORD then
            tier = 0
        end
        if s > 0 then
            local d
            if pos and pos.inst == e.inst then d = dist(pos.x, pos.y, e.x, e.y) else d = 1e9 end
            hits[#hits + 1] = { e = e, score = s, tier = tier, dist = d, prio = TYPE_PRIORITY[e.type] or 18,
                                side = side, other = side ~= nil }
        end
    end
    for i = 1, #static do consider(static[i]) end
    for i = 1, #learned do consider(learned[i]) end






    local function itemSide(h)
        if not ITEM_TYPES[h.e.type] then return 0 end
        if h.other then return 2 end
        if kindOf then return 0 end
        if h.e.fac == 1 or h.e.fac == 2 then return 0 end
        return 1
    end
    table.sort(hits, function(a, b)
        if a.tier ~= b.tier then return a.tier < b.tier end
        local sa, sb = itemSide(a), itemSide(b)
        if sa ~= sb then return sa < sb end
        if a.score ~= b.score then return a.score > b.score end
        if a.other ~= b.other then return b.other end
        if a.prio ~= b.prio then return a.prio < b.prio end
        if a.dist ~= b.dist then return a.dist < b.dist end
        return a.e.key < b.e.key
    end)





    local out, byName = {}, {}
    for i = 1, #hits do
        local h = hits[i]
        local e = h.e
        local kept
        local sameName = byName[e.name]
        if sameName then
            for j = 1, #sameName do
                local r = sameName[j]
                if r.dest.inst == e.inst and r.x == e.x and r.y == e.y then kept = r break end
            end
        end
        if kept then
            local typeName = e.type
            local more = kept.moreTypes
            local listed = typeName == kept.dest.type
            if more and not listed then
                for j = 1, #more do
                    if more[j] == typeName then listed = true break end
                end
            end
            if not listed then
                if not more then
                    more = {}
                    kept.moreTypes = more
                end
                more[#more + 1] = typeName
                kept.label = labelFor(kept.dest.name, kept.dest.zoneName, kept.dest.type, more, kept.side)
            end
        elseif #out < limit then
            local dest = destFromEntry(e)
            if dest then
                local row = { dest = dest, score = h.score, label = labelFor(dest.name, dest.zoneName, dest.type, nil, h.side),
                              distance = h.dist < 1e9 and h.dist or nil, otherFaction = h.other or nil,
                              x = e.x, y = e.y, side = h.side }
                out[#out + 1] = row
                if not sameName then
                    sameName = {}
                    byName[e.name] = sameName
                end
                sameName[#sameName + 1] = row
            end
        end
    end
    for i = 1, #out do out[i].x, out[i].y, out[i].side = nil, nil, nil end
    return out
end




function Destinations.Browse(opts)
    opts = opts or {}
    local limit = opts.limit or 25
    local types = typeFilter(opts.types)
    if not types then return {} end
    local playerCode = opts.faction == "Alliance" and 1 or opts.faction == "Horde" and 2 or Destinations.PlayerFactionCode()
    local pos = Destinations.PlayerPos()
    local static = ensureIndex()
    local hits = {}
    for i = 1, #static do
        local e = static[i]
        if types[e.type] then
            local side = otherSide(e.fac, playerCode)
            if not (side and not ANY_SIDE_TYPES[e.type] and not ITEM_TYPES[e.type]) then
                local d
                if pos and pos.inst == e.inst then d = dist(pos.x, pos.y, e.x, e.y) else d = 1e9 end
                hits[#hits + 1] = { e = e, dist = d, side = side, other = side ~= nil }
            end
        end
    end
    table.sort(hits, function(a, b)
        if a.dist ~= b.dist then return a.dist < b.dist end
        return a.e.key < b.e.key
    end)
    local out = {}
    for i = 1, #hits do
        if #out >= limit then break end
        local h = hits[i]
        local dest = destFromEntry(h.e)
        if dest then
            out[#out + 1] = {
                dest = dest, score = 0,
                label = labelFor(dest.name, dest.zoneName, dest.type, nil, h.side),
                distance = h.dist < 1e9 and h.dist or nil,
                otherFaction = h.other or nil,
            }
        end
    end
    return out
end





function Destinations.BrowseTowns(opts)
    opts = opts or {}
    local limit = opts.limit or 25
    local playerCode = opts.faction == "Alliance" and 1 or opts.faction == "Horde" and 2 or Destinations.PlayerFactionCode()
    local pos = Destinations.PlayerPos()
    local static = ensureIndex()
    local hits = {}
    for i = 1, #static do
        local e = static[i]
        if e.kind == "poi" and (e.type == "capital" or e.type == "town") then
            local d
            if pos and pos.inst == e.inst then d = dist(pos.x, pos.y, e.x, e.y) else d = 1e9 end
            local tier = 1
            if e.type == "capital" and (playerCode == 3 or e.fac == playerCode) then tier = 0 end
            hits[#hits + 1] = { e = e, dist = d, tier = tier, side = otherSide(e.fac, playerCode) }
        end
    end
    table.sort(hits, function(a, b)
        if a.tier ~= b.tier then return a.tier < b.tier end
        if a.dist ~= b.dist then return a.dist < b.dist end
        return a.e.key < b.e.key
    end)
    local out = {}
    for i = 1, #hits do
        if #out >= limit then break end
        local h = hits[i]
        local dest = destFromEntry(h.e)
        if dest then
            out[#out + 1] = {
                dest = dest, score = 0,
                label = labelFor(dest.name, dest.zoneName, dest.type, nil, h.side),
                distance = h.dist < 1e9 and h.dist or nil,
                otherFaction = h.side ~= nil or nil,
            }
        end
    end
    return out
end







local PLAIN_FIELDS = { "kind", "inst", "x", "y", "map", "mx", "my", "name", "zoneName", "type", "typeCode", "poiIndex",
                       "poiKey", "dataVersion", "questID", "taxiNodeID", "reachable", "adjustedYards", "faction", "serviceKind", "uiMapID",
                       "originalX", "originalY", "complete", "source", "learned",
                        "questTarget", "questChosen", "objectiveIndex", "areaIndex", "areaRadius", "finishedCount" }




function Destinations.Plain(dest)
    if type(dest) ~= "table" then return nil end
    local out = {}
    for _, f in ipairs(PLAIN_FIELDS) do
        local v = dest[f]
        if v ~= nil and type(v) ~= "table" and type(v) ~= "function" then out[f] = v end
    end
    if out.poiIndex and out.poiKey and poiKeyOf(out.poiIndex) == out.poiKey then out.dataVersion = dataVersion() end
    if type(dest.entrance) == "table" then
        out.entrance = { poiIndex = dest.entrance.poiIndex, poiKey = dest.entrance.poiKey, name = dest.entrance.name,
                         inst = dest.entrance.inst, x = dest.entrance.x, y = dest.entrance.y, map = dest.entrance.map }
    end
    if type(dest.interior) == "table" then
        out.interior = { inst = dest.interior.inst, x = dest.interior.x, y = dest.interior.y, map = dest.interior.map }
    end
    return out
end



local function questStage(dest)
    return dest.questTarget or "client"
end






local function sameQuestStop(a, b)
    if a.questID ~= b.questID then return false end
    local stage = questStage(a)
    if stage ~= questStage(b) then return false end
    if stage == "objective" and a.areaIndex and b.areaIndex then return a.areaIndex == b.areaIndex end
    return true
end





function Destinations.Equal(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    if a == b then return true end
    if a.poiKey and b.poiKey then
        if a.poiKey ~= b.poiKey then return false end
        if keyTrusted(a.poiKey) then return true end

    end
    if a.poiIndex and b.poiIndex then
        if a.poiIndex ~= b.poiIndex then return false end
        if a.name == nil or b.name == nil or a.name == b.name then return true end

    end
    if a.questID and b.questID then return sameQuestStop(a, b) end
    if a.taxiNodeID and b.taxiNodeID then return a.taxiNodeID == b.taxiNodeID end
    if a.inst ~= b.inst or not a.x or not b.x or not a.y or not b.y then return false end
    return dist(a.x, a.y, b.x, b.y) <= Destinations.EQUAL_YARDS
end

function Destinations.Describe(dest)
    if type(dest) ~= "table" then return L["Unknown destination"] end
    local name = dest.name
    if not name or name == "" then
        if dest.mx and dest.my then name = format("%.1f, %.1f", dest.mx * 100, dest.my * 100)
        else name = L["Unnamed location"] end
    end
    local parts = { name }
    if dest.zoneName and dest.zoneName ~= name then parts[#parts + 1] = dest.zoneName end
    local text = table.concat(parts, " - ")
    if dest.type and dest.type ~= "coord" and dest.type ~= "custom" then
        text = format("%s (%s)", text, typeText(dest.type, nil, otherSide(dest.faction)))
    end
    if dest.reachable == "adjusted" and dest.adjustedYards then
        text = format("%s %s", text, format(L["(adjusted %d yd)"], dest.adjustedYards))
    elseif dest.reachable == false then
        text = format("%s %s", text, L["(open ground)"])
    end
    return text
end



local function savedSpot(saved)
    local inner = type(saved.interior) == "table" and saved.interior or nil
    if inner and inner.x and inner.y then return inner.inst or saved.inst, inner.x, inner.y end
    return saved.inst, saved.originalX or saved.x, saved.originalY or saved.y
end






local function rekeyRow(saved)
    if not (saved.poiIndex or saved.poiKey) then return false end
    local P = poi()
    if not P then return false end
    local i = saved.poiKey and rowOfKey(saved.poiKey) or nil
    local inst, x, y = savedSpot(saved)
    if not i and saved.name and inst and x and y then
        i = nearestPOI(inst, x, y, Destinations.SNAP_NAME_YARDS, function(j)
            return P.name[j] == saved.name and (not saved.typeCode or P.type[j] == saved.typeCode)
        end)
    end
    if not i and saved.typeCode and inst and x and y then
        i = nearestPOI(inst, x, y, Destinations.EQUAL_YARDS, function(j) return P.type[j] == saved.typeCode end)
    end
    local key = i and poiKeyOf(i) or saved.poiKey
    if saved.poiIndex == i and saved.poiKey == key then return false end
    saved.poiIndex, saved.poiKey = i, key
    return true
end







function Destinations.Rekey(saved)
    if type(saved) ~= "table" then return false end
    local changed = rekeyRow(saved)
    if type(saved.entrance) == "table" and rekeyRow(saved.entrance) then changed = true end
    if saved.poiIndex and saved.dataVersion ~= dataVersion() then
        saved.dataVersion = dataVersion()
        changed = true
    elseif not saved.poiIndex and saved.dataVersion then
        saved.dataVersion = nil
        changed = true
    end
    return changed
end





local rekeyed = setmetatable({}, { __mode = "k" })

local function accountList(key)
    local DB = FGPS.DB
    if not DB or not DB.account then return {} end
    if type(DB.account[key]) ~= "table" then DB.account[key] = {} end
    local list = DB.account[key]
    if rekeyed[list] ~= poi() then
        for i = 1, #list do Destinations.Rekey(list[i]) end
        rekeyed[list] = poi()
    end
    return list
end

function Destinations.Favorites() return accountList("favorites") end
function Destinations.Recents() return accountList("recents") end

function Destinations.IsFavorite(dest)
    local list = accountList("favorites")
    for i = 1, #list do
        if Destinations.Equal(list[i], dest) then return i end
    end
    return false
end



function Destinations.AddFavorite(dest)
    local plain = Destinations.Plain(dest)
    if not plain or not plain.inst or not plain.x then return false, "invalid" end
    Destinations.Rekey(plain)
    if Destinations.IsFavorite(plain) then return false, "duplicate" end
    local list = accountList("favorites")
    if #list >= Destinations.MAX_FAVORITES then return false, "full" end
    plain.time = time and time() or 0
    list[#list + 1] = plain
    Events:Fire("FAVORITES_CHANGED")
    return true
end

function Destinations.RemoveFavorite(i)
    local list = accountList("favorites")
    if type(i) == "table" then i = Destinations.IsFavorite(i) end
    if not i or not list[i] then return false end
    table.remove(list, i)
    Events:Fire("FAVORITES_CHANGED")
    return true
end

function Destinations.AddRecent(dest)
    local plain = Destinations.Plain(dest)
    if not plain or not plain.inst or not plain.x then return false end
    Destinations.Rekey(plain)
    local list = accountList("recents")
    for i = #list, 1, -1 do
        if Destinations.Equal(list[i], plain) then table.remove(list, i) end
    end
    plain.time = time and time() or 0
    table.insert(list, 1, plain)
    while #list > Destinations.MAX_RECENTS do list[#list] = nil end
    Events:Fire("RECENTS_CHANGED")
    return true
end

function Destinations.ClearRecents()
    local list = accountList("recents")
    wipe(list)
    Events:Fire("RECENTS_CHANGED")
end




function Destinations:Init()
    if self.initialised then return end
    self.initialised = true
    Events:Register("LEARNED_SERVICES_CHANGED", function() Destinations.InvalidateIndex(true) end, self)


end
