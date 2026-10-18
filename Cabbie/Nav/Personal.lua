






local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local Events = FGPS.Events
local Const = FGPS.Const
local sqrt, type, pairs, ipairs, tostring, tonumber = math.sqrt, type, pairs, ipairs, tostring, tonumber

local Personal = {
    HEARTH_ITEM = 6948,
    ASTRAL_RECALL = 556,
    GCD_SECONDS = 1.5,
    TOWN_INN_RADIUS = 300,
    CAPITAL_INN_RADIUS = 700,
    bindCache = {},
    spellIndex = nil,
}
FGPS.Personal = Personal

Personal.CLASS_SPELLS = {
    MAGE = { 3561, 3562, 3565, 3563, 3566, 3567 },
    DRUID = { 18960 },
    SHAMAN = { 556 },
}
Personal.SPELL_NAMES = {
    [3561] = "Teleport: Stormwind", [3562] = "Teleport: Ironforge", [3565] = "Teleport: Darnassus", [3563] = "Teleport: Undercity",
    [3566] = "Teleport: Thunder Bluff", [3567] = "Teleport: Orgrimmar", [18960] = "Teleport: Moonglade", [556] = "Astral Recall",
}
Personal.CAST_SECONDS = { [556] = 10, [3561] = 10, [3562] = 10, [3565] = 10, [3563] = 10, [3566] = 10, [3567] = 10, [18960] = 10 }

local POI_INN, POI_TOWN, POI_CAPITAL, POI_GRAVEYARD, POI_PORTAL = 7, 1, 5, 16, 17





Personal.BIND_ALIASES = {
    ["trade district"] = "Stormwind", ["the commons"] = "Ironforge", ["valley of strength"] = "Orgrimmar",
    ["trade quarter"] = "The Undercity", ["craftsmen's terrace"] = "Darnassus", ["lower rise"] = "Thunder Bluff",
    ["thunderbrew distillery"] = "Kharanos", ["stoutlager inn"] = "Thelsamar", ["deepwater tavern"] = "Menethil Harbor",
    ["gallows' end tavern"] = "Brill",
}

local function now() return GetTime and GetTime() or 0 end

local function dist(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return sqrt(dx * dx + dy * dy)
end

local function lower(s) return Util.Lower(s) end





local function readiness(start, duration)
    start, duration = tonumber(start) or 0, tonumber(duration) or 0
    if duration <= Personal.GCD_SECONDS then return true, 0 end
    local remaining = start + duration - now()
    if remaining <= 0 then return true, 0 end
    return false, remaining
end
Personal.Readiness = readiness




local function itemCooldown(itemID)
    if C_Container and C_Container.GetItemCooldown then
        local ok, start, duration = pcall(C_Container.GetItemCooldown, itemID)
        if ok then
            if issecretvalue and (issecretvalue(start) or issecretvalue(duration)) then return 0, 0 end
            return start, duration
        end
    end
    if C_Item and C_Item.GetItemCooldown then
        local ok, start, duration = pcall(C_Item.GetItemCooldown, itemID)
        if ok then
            if issecretvalue and (issecretvalue(start) or issecretvalue(duration)) then return 0, 0 end
            return start, duration
        end
    end
    return 0, 0
end

local function spellCooldown(spellID)
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
        if ok and type(info) == "table" then
            local start, duration = info.startTime, info.duration
            if issecretvalue and (issecretvalue(start) or issecretvalue(duration)) then return 0, 0 end
            return start, duration
        end
    end
    return 0, 0
end

local function spellKnown(spellID)
    if IsSpellKnown then
        local ok, v = pcall(IsSpellKnown, spellID)
        if ok and v then return true end
    end
    if IsPlayerSpell then
        local ok, v = pcall(IsPlayerSpell, spellID)
        if ok and v then return true end
    end
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, v = pcall(C_SpellBook.IsSpellKnown, spellID)
        if ok and v then return true end
    end
    return false
end
Personal.IsSpellKnown = spellKnown

local function spellName(spellID)
    if C_Spell then
        if C_Spell.GetSpellName then
            local ok, name = pcall(C_Spell.GetSpellName, spellID)
            if ok and type(name) == "string" and name ~= "" then return name end
        end
        if C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
            if ok and type(info) == "table" and info.name then return info.name end
        end
    end
    return Personal.SPELL_NAMES[spellID] or ("Spell " .. tostring(spellID))
end

local function playerClass()
    if not UnitClass then return nil end
    local ok, _, classFile = pcall(UnitClass, "player")
    if ok then return classFile end
    return nil
end




local function poi() return FGPS.Data and FGPS.Data.poi or nil end

local function positionFromPOI(i)
    local P = poi()
    local D = FGPS.Destinations
    local pos = { inst = P.inst[i], x = P.x[i], y = P.y[i], map = P.map[i], poiIndex = i, poiName = P.name[i],
                  zoneName = FGPS.Data.zoneNames and FGPS.Data.zoneNames[P.zone[i] or 0] or nil }
    if D and D.WorldToMap then
        local map, mx, my = D.WorldToMap(pos.inst, pos.x, pos.y, pos.map)
        if map then pos.map, pos.mx, pos.my = map, mx, my end
    end
    return pos
end


local function spellArrival(spellID)
    local P = poi()
    if not P then return nil end

    if not Personal.spellIndex or Personal.spellIndexSource ~= P then
        Personal.spellIndexSource = P
        local index = {}
        if type(P.spell) == "table" then
            for i, id in pairs(P.spell) do index[id] = i end
        end
        for i = 1, P.n do
            if P.type[i] == POI_PORTAL and not index[P.spell and P.spell[i] or -1] then
                local src = P.src and P.src[i]
                local id = src and tonumber(src:match("spell_target_position:(%d+)")) or nil
                if id and not index[id] then index[id] = i end
            end
        end
        Personal.spellIndex = index
    end
    local i = Personal.spellIndex[spellID]
    if not i then return nil end
    return positionFromPOI(i)
end
Personal.SpellArrival = spellArrival

local function zoneIndexByName(name)
    local names = FGPS.Data and FGPS.Data.zoneNames
    if not names then return nil end
    local q = lower(name)
    for i, n in ipairs(names) do
        if lower(n) == q then return i end
    end
    return nil
end


function Personal.ResolveBind(bindName)
    if type(bindName) ~= "string" or Util.Trim(bindName) == "" then return nil end
    local P = poi()
    if Personal.bindCacheSource ~= P then

        wipe(Personal.bindCache)
        Personal.bindCacheSource = P
    end
    local cached = Personal.bindCache[bindName]
    if cached ~= nil then return cached or nil end
    if not P then return nil end
    local q = lower(Util.Trim(bindName))
    if Personal.BIND_ALIASES[q] then q = lower(Personal.BIND_ALIASES[q]) end
    local innExact, townExact, graveyardExact, innContains
    local names, types = P.name, P.type
    for i = 1, P.n do
        local t = types[i]
        if t == POI_INN or t == POI_TOWN or t == POI_CAPITAL or t == POI_GRAVEYARD then
            local key = lower(names[i])
            if key == q then
                if t == POI_INN then innExact = innExact or i
                elseif t == POI_GRAVEYARD then graveyardExact = graveyardExact or i
                else townExact = townExact or i end
            elseif t == POI_INN and not innContains and (key:find(q, 1, true) or q:find(key, 1, true)) then
                innContains = i
            end
        end
    end
    local result
    if innExact then
        result = positionFromPOI(innExact)
    elseif townExact then

        local best, bestD
        local radius = types[townExact] == POI_CAPITAL and Personal.CAPITAL_INN_RADIUS or Personal.TOWN_INN_RADIUS
        for i = 1, P.n do
            if types[i] == POI_INN and P.inst[i] == P.inst[townExact] then
                local d = dist(P.x[i], P.y[i], P.x[townExact], P.y[townExact])
                if d <= radius and (not bestD or d < bestD) then best, bestD = i, d end
            end
        end
        result = positionFromPOI(best or townExact)
    else

        local zoneIdx = zoneIndexByName(q)
        if zoneIdx then
            local anchor
            for i = 1, P.n do
                if (types[i] == POI_CAPITAL or types[i] == POI_TOWN) and P.zone[i] == zoneIdx and lower(names[i]) == q:gsub(" city$", "") then anchor = i break end
            end
            local best, bestD
            for i = 1, P.n do
                if types[i] == POI_INN and P.zone[i] == zoneIdx then
                    local d = anchor and dist(P.x[i], P.y[i], P.x[anchor], P.y[anchor]) or 0
                    if not bestD or d < bestD then best, bestD = i, d end
                end
            end
            if best or anchor then result = positionFromPOI(best or anchor) end
        end
        if not result and graveyardExact then result = positionFromPOI(graveyardExact) end
        if not result and innContains then result = positionFromPOI(innContains) end
    end
    Personal.bindCache[bindName] = result or false




    if FGPS.Log then
        if result then
            FGPS.Log:Info('Hearth bind location "%s" resolved to %s', bindName, tostring(result.poiName))
        else
            FGPS.Log:Info('Hearth bind location "%s" not found in the navigation data', bindName)
        end
    end
    return result
end








local function bindLocation()
    if not GetBindLocation then return nil end
    local ok, name = pcall(GetBindLocation)
    if not ok or name == nil then return nil end
    if issecretvalue and issecretvalue(name) then return nil end
    if type(name) ~= "string" then return nil end
    return name
end
Personal.BindLocation = bindLocation




local function measuredCast(id, fallback)
    local Calibrate = FGPS.Calibrate
    if Calibrate and Calibrate.TeleportSeconds then
        local ok, cast = pcall(Calibrate.TeleportSeconds, id)
        if ok and type(cast) == "number" and cast > 0 then return cast end
    end
    return fallback
end

function Personal.Hearth()
    if not (C_Container and C_Container.PlayerHasHearthstone) then return nil end
    local ok, itemID = pcall(C_Container.PlayerHasHearthstone)
    if not ok or not itemID then return nil end
    local start, duration = itemCooldown(itemID)
    local ready, remaining = readiness(start, duration)
    local bindName = bindLocation()
    local opt = { kind = "hearth", id = itemID, name = L["Hearthstone"], bindName = bindName, ready = ready, cdRemaining = remaining,
                  castSeconds = measuredCast("hearth", Const.HEARTH_CAST_SECONDS or 10), known = true }
    local pos = Personal.ResolveBind(bindName)
    if pos then
        opt.inst, opt.x, opt.y, opt.map, opt.mx, opt.my = pos.inst, pos.x, pos.y, pos.map, pos.mx, pos.my
        opt.zoneName, opt.poiIndex, opt.targetName = pos.zoneName, pos.poiIndex, pos.poiName
        opt.routable = true
    else
        opt.routable = false
        opt.note = bindName and L["Bind location not found in the navigation data; the hearthstone is not used for routing."]
                             or L["Bind location unknown; the hearthstone is not used for routing."]
    end
    return opt
end


function Personal.Options()
    local out = {}
    local hearth = Personal.Hearth()
    if hearth then out[#out + 1] = hearth end
    local classFile = playerClass()
    local spells = classFile and Personal.CLASS_SPELLS[classFile] or nil
    if spells then
        for _, spellID in ipairs(spells) do
            local start, duration = spellCooldown(spellID)
            local ready, remaining = readiness(start, duration)
            local opt = { kind = "spell", id = spellID, name = spellName(spellID), known = spellKnown(spellID), ready = ready,
                          cdRemaining = remaining, castSeconds = measuredCast(spellID, Personal.CAST_SECONDS[spellID] or 10) }
            local pos
            if spellID == Personal.ASTRAL_RECALL then
                if hearth and hearth.routable then
                    pos = { inst = hearth.inst, x = hearth.x, y = hearth.y, map = hearth.map, mx = hearth.mx, my = hearth.my,
                            zoneName = hearth.zoneName, poiIndex = hearth.poiIndex, poiName = hearth.targetName }
                else
                    pos = Personal.ResolveBind(hearth and hearth.bindName or bindLocation())
                end
                opt.bindName = hearth and hearth.bindName or nil
            else
                pos = spellArrival(spellID)
            end
            if pos then
                opt.inst, opt.x, opt.y, opt.map, opt.mx, opt.my = pos.inst, pos.x, pos.y, pos.map, pos.mx, pos.my
                opt.zoneName, opt.poiIndex, opt.targetName = pos.zoneName, pos.poiIndex, pos.poiName
                opt.routable = opt.known
                if not opt.known then opt.note = L["Spell not known yet."] end
            else
                opt.routable = false
                opt.note = L["No arrival position is known for this spell."]
            end
            out[#out + 1] = opt
        end
    end
    return out
end

function Personal.InvalidateBind()
    wipe(Personal.bindCache)
end




function Personal:Init()
    if self.initialised then return end
    self.initialised = true
    Events:RegisterWoW("HEARTHSTONE_BOUND", function() Personal.InvalidateBind() end, self)



end
