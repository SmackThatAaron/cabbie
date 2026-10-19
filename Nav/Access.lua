





























local ADDON_NAME, FGPS = ...

local Access = {
    RIDING_SKILL_LINES = { 762, 3011 },
    dirty = true,
    current = nil,
    building = false,
    taxiScanned = false,
}
FGPS.Access = Access

local L = FGPS.L
local Util = FGPS.Util
local Const = FGPS.Const
local type, pairs, ipairs, tonumber, pcall, select = type, pairs, ipairs, tonumber, pcall, select

local function plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function settings()
    local db = FGPS.DB
    return db and db.settings or nil
end


local function characterKey()
    if UnitGUID then
        local ok, guid = pcall(UnitGUID, "player")
        guid = ok and plain(guid) or nil
        if type(guid) == "string" and guid ~= "" then return guid end
    end
    local name = UnitName and plain((UnitName("player"))) or nil
    if type(name) ~= "string" or name == "" then return nil end
    local realm = nil
    if GetNormalizedRealmName then
        local ok, value = pcall(GetNormalizedRealmName)
        realm = ok and plain(value) or nil
    end
    if type(realm) ~= "string" or realm == "" then
        if GetRealmName then
            local ok, value = pcall(GetRealmName)
            realm = ok and plain(value) or nil
        end
    end
    return name .. "-" .. (type(realm) == "string" and realm ~= "" and realm or "?")
end

local function wipeTaxiKnowledge(char)
    if wipe then
        wipe(char.knownTaxi)
        wipe(char.taxiConfirmed)
        wipe(char.taxiConfirmedInst)
    else
        char.knownTaxi, char.taxiConfirmed, char.taxiConfirmedInst = {}, {}, {}
    end
    char.taxiApiTrusted = nil
end



local function bindTaxiOwner(char)
    local key = characterKey()
    if not key then return false end
    if char.taxiOwner == key then return false end
    local switched = char.taxiOwner ~= nil
    if switched then
        wipeTaxiKnowledge(char)
        Access.taxiScanned = false
        Access.taxiNoticeGiven = nil
        Access.current = nil
        Access.dirty = true
        local Router = FGPS.Router
        if Router and Router.InvalidateCache then pcall(Router.InvalidateCache, Router) end
    end
    char.taxiOwner = key
    return switched
end

local function charDB()
    local db = FGPS.DB
    if db and db.char then
        if type(db.char.knownTaxi) ~= "table" then db.char.knownTaxi = {} end
        if type(db.char.taxiConfirmed) ~= "table" then db.char.taxiConfirmed = {} end
        if type(db.char.taxiConfirmedInst) ~= "table" then db.char.taxiConfirmedInst = {} end
        bindTaxiOwner(db.char)
        return db.char
    end
    return nil
end






local function mapsForInstance(inst)
    local out = {}
    local instances = FGPS.Data and FGPS.Data.instances
    local rec = instances and instances[inst]
    if rec then
        if rec.continentMap then out[#out + 1] = rec.continentMap end
        if type(rec.zones) == "table" then
            for _, id in ipairs(rec.zones) do out[#out + 1] = id end
        end
    end
    if #out == 0 and C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo then
        local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
        map = ok and plain(map) or nil
        local guard = 0
        while map and guard < 8 do
            guard = guard + 1
            local okInfo, info = pcall(C_Map.GetMapInfo, map)
            if not okInfo or type(info) ~= "table" then break end
            out[#out + 1] = map
            if info.mapType == 2 or not info.parentMapID or info.parentMapID == 0 then
                if info.mapType == 2 and C_Map.GetMapChildrenInfo then
                    local okKids, kids = pcall(C_Map.GetMapChildrenInfo, map, 3, false)
                    if okKids and type(kids) == "table" then
                        for _, kid in ipairs(kids) do out[#out + 1] = kid.mapID end
                    end
                end
                break
            end
            map = info.parentMapID
        end
    end
    return out
end

local function scanMap(uiMapID, cache, char)
    if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) or not uiMapID then return 0 end
    local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, uiMapID)
    if not ok or type(nodes) ~= "table" then return 0 end
    local found = 0
    for _, node in ipairs(nodes) do
        local id = plain(node.nodeID)

        local undiscovered = plain(node.isUndiscovered)
        if id and undiscovered == false then
            if not cache[id] then found = found + 1 end
            cache[id] = true
        elseif id and undiscovered == true then



            if cache[id] then found = found + 1 end
            cache[id] = nil
            if char and not char.taxiApiTrusted then
                char.taxiApiTrusted = true
                found = found + 1
            end
        end
    end
    return found
end


function Access:RefreshKnownTaxi(scope)
    local char = charDB()
    if not char then return 0 end
    local cache = char.knownTaxi
    local maps
    if type(scope) == "table" then
        maps = scope
    elseif scope == "all" then
        maps = {}
        local instances = FGPS.Data and FGPS.Data.instances
        if type(instances) == "table" then
            for inst, rec in pairs(instances) do
                if rec.continentMap then
                    for _, id in ipairs(mapsForInstance(inst)) do maps[#maps + 1] = id end
                end
            end
        end
        if #maps == 0 then maps = mapsForInstance(nil) end
    else
        local inst = scope
        if inst == nil then
            local pos = FGPS.Coords and FGPS.Coords.PlayerPos()
            inst = pos and pos.inst or nil
        end
        maps = mapsForInstance(inst)
    end
    local found = 0
    for _, id in ipairs(maps) do found = found + scanMap(id, cache, char) end
    if found > 0 then self.dirty = true end
    return found
end




function Access:RefreshFromTaxiMap()
    local char = charDB()
    if not char then return 0 end
    local confirmed, confirmedInst = char.taxiConfirmed, char.taxiConfirmedInst
    local changed = 0
    local mapID = GetTaxiMapID and plain(GetTaxiMapID()) or nil
    if mapID and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes then
        local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, mapID)
        if ok and type(nodes) == "table" then
            local unreachable = Enum and Enum.FlightPathState and Enum.FlightPathState.Unreachable or 2
            local data = FGPS.Data and FGPS.Data.taxi and FGPS.Data.taxi.nodes
            local listed, instances = {}, {}
            for _, node in ipairs(nodes) do
                local id = plain(node.nodeID)
                local state = plain(node.state)
                if id and state ~= nil then
                    local known = state ~= unreachable
                    listed[id] = true
                    if confirmed[id] ~= known then changed = changed + 1 end
                    confirmed[id] = known
                    local record = data and data[id]
                    if record and record.inst ~= nil then instances[record.inst] = true end
                end
            end


            for inst in pairs(instances) do
                confirmedInst[inst] = true
                for id, record in pairs(data or {}) do
                    if record.inst == inst and not listed[id] and confirmed[id] ~= false then
                        confirmed[id] = false
                        changed = changed + 1
                    end
                end
            end
        end
    end
    if changed > 0 then self.dirty = true end
    return changed
end



local flightContinents, flightContinentsOf = {}, nil
local function continentsWithFlights()
    local nodes = FGPS.Data and FGPS.Data.taxi and FGPS.Data.taxi.nodes
    if nodes ~= flightContinentsOf then
        flightContinents, flightContinentsOf = {}, nodes
        for _, record in pairs(type(nodes) == "table" and nodes or {}) do
            if type(record) == "table" and record.inst ~= nil then flightContinents[record.inst] = true end
        end
    end
    return flightContinents
end





local function unconfirmedOn(char, inst)
    if char.taxiApiTrusted then return false end
    if inst == nil then return next(char.taxiConfirmedInst) == nil end
    return continentsWithFlights()[inst] == true and char.taxiConfirmedInst[inst] ~= true
end

local function playerContinent()
    local pos = FGPS.Coords and FGPS.Coords.PlayerPos and FGPS.Coords.PlayerPos()
    return pos and pos.inst or nil
end



function Access:TaxiUnconfirmed(inst)
    local char = charDB()
    if not char then return false end
    if inst == nil then inst = playerContinent() end
    return unconfirmedOn(char, inst)
end

local function flightsSwitchedOn()
    local s = settings()
    return not (s and s.transports and s.transports.taxi == false)
end





local function leftOutIn(inst)
    local char = charDB()
    if inst == nil or not char or next(char.taxiConfirmedInst) == nil then return nil end
    local instances = FGPS.Data and FGPS.Data.instances
    local record = instances and instances[inst]
    return type(record) == "table" and type(record.name) == "string" and record.name or nil
end








function Access:FlightsLeftOut(route)
    if not flightsSwitchedOn() then return false end
    local legs = type(route) == "table" and type(route.legs) == "table" and route.legs or {}
    local asked = false
    for _, leg in ipairs(legs) do
        if type(leg) == "table" then
            if leg.inst ~= nil then
                asked = true
                if self:TaxiUnconfirmed(leg.inst) then return true, leftOutIn(leg.inst) end
            end
            if leg.toInst ~= nil then
                asked = true
                if self:TaxiUnconfirmed(leg.toInst) then return true, leftOutIn(leg.toInst) end
            end
        end
    end
    if asked then return false end
    local inst = playerContinent()
    if self:TaxiUnconfirmed(inst) then return true, leftOutIn(inst) end
    return false
end


local function continentsLeftOut()
    local char = charDB()
    if not char or not flightsSwitchedOn() then return 0 end
    local n = 0
    for inst in pairs(continentsWithFlights()) do
        if unconfirmedOn(char, inst) then n = n + 1 end
    end
    return n
end




local function ridingRank()
    if not (C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID) then return 0, nil end
    local best, bestLine = 0, nil
    for _, id in ipairs(Access.RIDING_SKILL_LINES) do
        local ok, info = pcall(C_SkillInfo.GetSkillLineInfoByID, id)
        if ok and type(info) == "table" then
            local rank = tonumber(plain(info.rank)) or 0
            if rank > best then best, bestLine = rank, id end
        end
    end
    return best, bestLine
end


local function mountJournal()
    if not (C_MountJournal and C_MountJournal.GetMountIDs and C_MountJournal.GetMountInfoByID) then return nil, nil end
    local ok, ids = pcall(C_MountJournal.GetMountIDs)
    if not ok or type(ids) ~= "table" then return nil, nil end
    local usable, collected = false, false
    for _, mountID in ipairs(ids) do
        local okInfo, _, _, _, _, isUsable, _, _, _, _, _, isCollected = pcall(C_MountJournal.GetMountInfoByID, mountID)
        if okInfo and isCollected then
            collected = true
            if isUsable then
                usable = true
                break
            end
        end
    end
    return usable, collected
end

local function mountState(routing)
    local rank, line = ridingRank()
    local speed = 0
    if rank >= 150 then speed = 1.0 elseif rank >= 75 then speed = 0.6 end
    local usable, collected = mountJournal()
    local hasMount
    if usable == nil then
        hasMount = speed > 0
    else
        local indoors = IsIndoors and IsIndoors() or false
        hasMount = speed > 0 and (usable or (collected and indoors))
    end
    local assume = routing and routing.assumeMount or "auto"
    if assume == "none" then
        speed, hasMount = 0, false
    elseif assume == "60" then
        speed, hasMount = 0.6, true
    elseif assume == "100" then
        speed, hasMount = 1.0, true
    end
    return speed, hasMount, rank, line
end

local function canMountHere()
    local instanced, instanceType = false, "none"
    if FGPS.Coords and FGPS.Coords.IsInstanced then instanced, instanceType = FGPS.Coords.IsInstanced() end
    if instanced and instanceType ~= "none" and instanceType ~= "pvp" then return false end
    if IsOutdoors then
        local ok, outdoors = pcall(IsOutdoors)
        if ok and outdoors == false then return false end
    end
    return true
end




local function cooldownRemaining(start, duration)
    start, duration = tonumber(plain(start)) or 0, tonumber(plain(duration)) or 0
    if duration <= 0 then return 0 end
    local now = GetTime and GetTime() or 0
    local remaining = start + duration - now
    if remaining < 0 then remaining = 0 end
    return remaining
end

local function hearthFallback()
    if not (C_Container and C_Container.PlayerHasHearthstone) then return nil end
    local ok, itemID = pcall(C_Container.PlayerHasHearthstone)
    itemID = ok and plain(itemID) or nil
    if not itemID then return nil end


    local Personal = FGPS.Personal
    local bindName = Personal and Personal.BindLocation and Personal.BindLocation() or nil
    if type(bindName) ~= "string" or bindName == "" then return nil end
    local poi = FGPS.Data and FGPS.Data.poi
    if not poi or not poi.name then return nil end
    local target = Util.Lower(bindName)
    local found
    for i = 1, poi.n or #poi.name do
        local t = poi.type[i]
        if (t == 7 or t == 1 or t == 5) and Util.Lower(poi.name[i]) == target then
            found = i
            if t == 7 then break end
        end
    end
    if not found then return nil end
    local remaining = 0
    if C_Container.GetItemCooldown then
        local okCd, start, duration = pcall(C_Container.GetItemCooldown, itemID)
        if okCd then remaining = cooldownRemaining(start, duration) end
    end
    return { itemID = itemID, ready = remaining <= 0, cdRemaining = remaining, bindName = bindName,
             inst = poi.inst[found], x = poi.x[found], y = poi.y[found], map = poi.map[found],
             castSeconds = Const.HEARTH_CAST_SECONDS, name = bindName }
end

local function personalOptions()
    local hearth, spells = nil, {}
    local personal = FGPS.Personal
    if personal and type(personal.Options) == "function" then
        local ok, options = pcall(personal.Options)
        if ok and type(options) == "table" then
            for _, opt in ipairs(options) do
                if type(opt) == "table" and opt.inst and opt.x and opt.y and opt.known ~= false then
                    local entry = {
                        kind = opt.kind, id = opt.id, itemID = opt.kind == "hearth" and opt.id or nil,
                        spellID = opt.kind == "spell" and opt.id or nil, name = opt.name, bindName = opt.kind == "hearth" and opt.name or nil,
                        inst = opt.inst, x = opt.x, y = opt.y, map = opt.map, ready = opt.ready ~= false,
                        cdRemaining = tonumber(opt.cdRemaining) or 0, castSeconds = tonumber(opt.castSeconds) or Const.HEARTH_CAST_SECONDS,
                    }
                    if opt.kind == "hearth" then
                        if not hearth then hearth = entry end
                    elseif opt.kind == "spell" then
                        spells[#spells + 1] = entry
                    end
                end
            end
            return hearth, spells, true
        end
    end
    return hearthFallback(), spells, false
end




local function teleportDigest(entry)
    if not entry then return nil end
    return { entry.inst, Util.Round(entry.x or 0), Util.Round(entry.y or 0), entry.ready or entry.cdRemaining < Const.TELEPORT_MAX_WAIT, entry.id or entry.itemID or entry.spellID }
end

local function build()
    local s = settings()
    local routing = s and s.routing or {}
    local transportsSetting = s and s.transports or {}
    local faction = UnitFactionGroup and plain((UnitFactionGroup("player"))) or nil
    local factionMask = 3
    if faction == "Alliance" then factionMask = 1 elseif faction == "Horde" then factionMask = 2 else faction = "Neutral" end
    local level = UnitLevel and tonumber(plain(UnitLevel("player"))) or 60
    local race = UnitRace and plain((select(2, UnitRace("player")))) or nil
    local class = UnitClass and plain((select(2, UnitClass("player")))) or nil

    if not Access.taxiScanned then
        Access.taxiScanned = true
        Access:RefreshKnownTaxi("all")
    end
    local knownTaxi = {}
    local taxiConfirmedCount, taxiListedCount = 0, 0
    local char = charDB()
    if char then
        for id, known in pairs(char.taxiConfirmed) do
            if known then
                knownTaxi[id] = true
                taxiConfirmedCount = taxiConfirmedCount + 1
            end
        end
        if char.taxiApiTrusted then

            local data = FGPS.Data and FGPS.Data.taxi and FGPS.Data.taxi.nodes
            for id, known in pairs(char.knownTaxi) do
                local record = data and data[id]
                local settled = char.taxiConfirmed[id] ~= nil
                    or (record ~= nil and record.inst ~= nil and char.taxiConfirmedInst[record.inst] == true)
                if known and not settled then
                    knownTaxi[id] = true
                    taxiListedCount = taxiListedCount + 1
                end
            end
        end
    end

    local mountSpeed, hasMount, ridingRankValue, ridingLine = mountState(routing)
    local canMount = canMountHere()

    local transports = {}
    for k, v in pairs({ taxi = true, boat = true, zeppelin = true, tram = true, hearth = true, spells = true }) do
        local value = transportsSetting[k]
        if value == nil then value = v end
        transports[k] = value and true or false
    end

    local hearth, spells, fromPersonal = personalOptions()





    local deadOk, dead = false, false
    if UnitIsDeadOrGhost then deadOk, dead = pcall(UnitIsDeadOrGhost, "player") end
    dead = (deadOk and plain(dead)) and true or false
    if dead then
        hearth, spells, canMount = nil, {}, false
        transports.hearth, transports.spells, transports.taxi = false, false, false
    end

    local access = {
        faction = faction, factionMask = factionMask, level = level or 60, race = race, class = class,
        knownTaxi = knownTaxi,
        taxiConfirmedCount = taxiConfirmedCount, taxiListedCount = taxiListedCount,
        taxiUnconfirmed = Access:TaxiUnconfirmed(),
        mountSpeed = mountSpeed, hasMount = hasMount, canMount = canMount, ridingRank = ridingRankValue, ridingLine = ridingLine,
        transports = transports, dead = dead,
        hearth = hearth, spells = spells, personalSource = fromPersonal and "personal" or "fallback",
        allowUnverified = routing.allowUnverified ~= false,
        preferRoads = routing.preferRoads == true,
        roadShortcuts = routing.roadShortcuts == true,
        avoidDanger = routing.avoidDanger == true,
        dangerMargin = tonumber(routing.dangerMargin) or 3,
        assumeMount = routing.assumeMount or "auto",
        createdAt = GetTime and GetTime() or 0,
    }

    local taxiIDs = {}
    for id in pairs(knownTaxi) do taxiIDs[#taxiIDs + 1] = id end
    table.sort(taxiIDs)
    local spellDigest = {}
    for i, sp in ipairs(spells) do spellDigest[i] = teleportDigest(sp) end
    access.hash = Util.Hash({
        f = factionMask, lvl = access.level, taxi = taxiIDs, ms = mountSpeed, hm = hasMount, cm = canMount,
        tr = transports, h = teleportDigest(hearth), sp = spellDigest,
        au = access.allowUnverified, pr = access.preferRoads, rs = access.roadShortcuts, ad = access.avoidDanger, dm = access.dangerMargin,
        own = char and char.taxiOwner or characterKey(), dead = dead or nil,
    })


    local wait = Const.TELEPORT_MAX_WAIT or 0
    local function watch(entry)
        local remaining = entry and not entry.ready and tonumber(entry.cdRemaining) or 0
        if remaining <= 0 then return end
        local at = access.createdAt + (remaining > wait and remaining - wait or remaining)
        if not access.expiresAt or at < access.expiresAt then access.expiresAt = at end
    end
    watch(hearth)
    for _, sp in ipairs(spells) do watch(sp) end
    return access
end


local function fallbackSnapshot(err)
    local access = {
        faction = "Neutral", factionMask = 3, level = 60, knownTaxi = {}, mountSpeed = 0, hasMount = false, canMount = true,
        transports = { taxi = true, boat = true, zeppelin = true, tram = true, hearth = true, spells = true },
        hearth = nil, spells = {}, allowUnverified = true, preferRoads = false, avoidDanger = false, dangerMargin = 3,
        degraded = tostring(err),
    }
    access.hash = Util.Hash("fallback")
    return access
end

function Access:Snapshot()


    charDB()
    local current = self.current
    if current and current.expiresAt and (GetTime and GetTime() or 0) >= current.expiresAt then self.dirty = true end
    if current and not self.dirty then return current end
    if self.building then

        return self.current or fallbackSnapshot("re-entrant")
    end
    self.building = true
    local ok, access = pcall(build)
    self.building = false
    if not ok then
        if FGPS.Log then FGPS.Log:Error("Access snapshot failed: %s", tostring(access)) end
        access = fallbackSnapshot(access)
    end
    local previous = self.current
    self.current = access
    self.dirty = false
    if FGPS.Events and (not previous or previous.hash ~= access.hash) then
        FGPS.Events:Fire("ACCESS_CHANGED", access.hash, previous and previous.hash or nil)
    end
    return access
end

function Access:Invalidate()
    self.dirty = true
end




function Access:CanUseTaxiNode(access, taxiNodeID)
    if not access or not taxiNodeID then return false end
    if access.transports and access.transports.taxi == false then return false end
    if not (access.knownTaxi and access.knownTaxi[taxiNodeID]) then return false end
    local nodes = FGPS.Data and FGPS.Data.taxi and FGPS.Data.taxi.nodes
    local node = nodes and nodes[taxiNodeID]
    if node and node.fac and node.fac ~= 0 and node.fac ~= 3 then
        local mask = access.factionMask or 3
        if mask ~= 3 and node.fac ~= mask then return false end
    end
    return true
end

local KIND_TOGGLE = { boat = "boat", ferry = "boat", zeppelin = "zeppelin", tram = "tram" }

function Access:CanUseTransport(access, record)
    if not access or type(record) ~= "table" then return false end
    local toggle = KIND_TOGGLE[record.kind]
    if toggle and access.transports and access.transports[toggle] == false then return false end
    local fac = record.fac or 0
    if fac ~= 0 and fac ~= 3 then
        local mask = access.factionMask or 3
        if mask ~= 3 and fac ~= mask then return false end
    end
    return true
end




local INVALIDATE_EVENTS = {
    "SKILL_LINES_CHANGED", "NEW_MOUNT_ADDED", "MOUNT_JOURNAL_USABILITY_CHANGED", "BAG_UPDATE_COOLDOWN",
    "SPELL_UPDATE_COOLDOWN", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS",
    "HEARTHSTONE_BOUND", "PLAYER_ENTERING_WORLD", "UNIT_FACTION",
    "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
}

function Access:Init()
    if self.initialized then return end
    self.initialized = true
    local Events = FGPS.Events
    if not Events then return end
    for _, event in ipairs(INVALIDATE_EVENTS) do
        Events:RegisterWoW(event, function() Access.dirty = true end, self)
    end






    local function readAgain(refresh, scope)
        local leftOut = continentsLeftOut()
        refresh(Access, scope)
        Access.dirty = true
        if continentsLeftOut() < leftOut then Events:Fire("FLIGHTS_KNOWN") end
    end
    Events:RegisterWoW("TAXI_NODE_STATUS_CHANGED", function() readAgain(Access.RefreshKnownTaxi, nil) end, self)
    Events:RegisterWoW("TAXIMAP_OPENED", function() readAgain(Access.RefreshFromTaxiMap) end, self)
    Events:Register("SETTINGS_CHANGED", function(_, key)
        if type(key) ~= "string" then return end
        if key == "*" or key:sub(1, 10) == "transports" or key:sub(1, 7) == "routing" then Access.dirty = true end
    end, self)
    Events:Register("WORLD_ENTERED", function() readAgain(Access.RefreshKnownTaxi, nil) end, self)








    local function tellOnce(onTheBlock, route)
        if Access.taxiNoticeGiven then return end
        local leftOut, where = Access:FlightsLeftOut(route)
        if not leftOut then return end
        if onTheBlock then
            local RouteBlock = FGPS.UI and FGPS.UI.RouteBlock
            local asked, shows = pcall(function() return RouteBlock.Wanted() end)
            if asked and shows == true then return end
        end
        Access.taxiNoticeGiven = true
        if where then
            FGPS:Print(L["Cabbie does not know which flight paths you have in %s yet, so routes leave out the flights there. Talk to a flight master there once and it will use the ones you really have."], where)
        else
            FGPS:Print(L["Cabbie does not know which flight paths you have yet, so routes leave flights out. Talk to any flight master once and it will use the ones you really have."])
        end
    end
    Events:Register("ROUTE_PREVIEW", function(_, route) tellOnce(false, route) end, self)
    Events:Register("ROUTE_STARTED", function(_, route) tellOnce(true, route) end, self)
end
