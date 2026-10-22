






local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local Events = FGPS.Events
local Const = FGPS.Const
local sqrt, type, pairs, ipairs, tostring, tonumber, format = math.sqrt, type, pairs, ipairs, tostring, tonumber, string.format

local Personal = {
    HEARTH_ITEM = 6948,
    HEARTH_SPELL = 8690,
    LAST_BAG = 5,
    ASTRAL_RECALL = 556,
    GCD_SECONDS = 1.5,
    TOWN_INN_RADIUS = 300,
    CAPITAL_INN_RADIUS = 700,
    bindCache = {},
    spellIndex = nil,
    hearthItems = {},
    hearthState = nil,
}
FGPS.Personal = Personal




Personal.HEARTH_TOYS = {
    54452, 64488, 93672, 142542, 162973, 163045, 165669, 165670, 165802, 166746, 166747,
    168907, 172179, 188952, 190237, 193588, 200630, 206195, 208704, 209035, 212337,
}

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


local function plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end





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









local function readBind()
    if not GetBindLocation then return nil, "missing" end
    local ok, name = pcall(GetBindLocation)
    if not ok then return nil, "an error" end
    if name == nil then return nil, "nil" end
    if issecretvalue and issecretvalue(name) then return nil, "secret" end
    if type(name) ~= "string" then return nil, "not text" end
    return name, "text"
end
local function bindLocation() return (readBind()) end
Personal.BindLocation = bindLocation











Personal.LANDING_SPELLS = { [8690] = true, [556] = true }
Personal.LANDING_JUMP_YARDS = 40
Personal.LANDING_TICK_SECONDS = 0.5
Personal.LANDING_SECONDS = 30
Personal.CONFIRM_SECONDS = 120
Personal.CONFIRM_YARDS = 30

local function charStore()
    local DB = FGPS.DB
    if DB and type(DB.char) == "table" then return DB.char end
    Personal.volatileChar = Personal.volatileChar or {}
    return Personal.volatileChar
end

local function playerGUID()
    if not UnitGUID then return nil end
    local ok, guid = pcall(UnitGUID, "player")
    guid = ok and plain(guid) or nil
    return type(guid) == "string" and guid ~= "" and guid or nil
end

local function textOf(fn)
    if not fn then return nil end
    local ok, s = pcall(fn)
    s = ok and plain(s) or nil
    return type(s) == "string" and s ~= "" and s or nil
end

local function serverNow()
    if not GetServerTime then return nil end
    local ok, v = pcall(GetServerTime)
    return ok and tonumber(plain(v)) or nil
end

local function playerPosition()
    local Coords = FGPS.Coords
    if not (Coords and Coords.PlayerPos) then return nil end
    local ok, pos = pcall(Coords.PlayerPos)
    if ok and type(pos) == "table" and type(pos.inst) == "number" and type(pos.x) == "number" and type(pos.y) == "number" then return pos end
    return nil
end



function Personal.LearnedBind()
    local rec = charStore().hearthBind
    if type(rec) ~= "table" or type(rec.inst) ~= "number" or type(rec.x) ~= "number" or type(rec.y) ~= "number" then return nil end
    local me = playerGUID()
    if rec.owner and me and rec.owner ~= me then return nil end
    return rec
end

local HOW_WORDS = { bound = "a bind at an inn", landed = "a hearth landing" }



function Personal.LearnBind(how, name)
    local pos = playerPosition()
    if not pos then
        if FGPS.Log then FGPS.Log:Info("Hearthstone: %s seen, but the client gave no position to learn it from", HOW_WORDS[how] or tostring(how)) end
        return nil
    end
    local zone = textOf(GetRealZoneText) or textOf(GetZoneText)
    local subZone = textOf(GetSubZoneText)
    local text = bindLocation()
    local label = name or text or subZone or zone
    if label and Personal.BIND_ALIASES[lower(label)] then label = Personal.BIND_ALIASES[lower(label)] end
    local rec = { inst = pos.inst, x = Util.Round(pos.x, 1), y = Util.Round(pos.y, 1), map = pos.map, zone = zone, subZone = subZone,
                  name = label, bindText = text, how = how, at = serverNow(), owner = playerGUID() }
    charStore().hearthBind = rec
    Personal.InvalidateBind()
    local Access = FGPS.Access
    if Access and Access.Invalidate then Access:Invalidate() end
    if FGPS.Log then
        FGPS.Log:Info("Hearthstone landing learned from %s: %s (%s / %s) at %d %.0f %.0f", HOW_WORDS[how] or tostring(how), tostring(label),
            tostring(zone), tostring(subZone), rec.inst, rec.x, rec.y)
    end
    return rec
end


function Personal.StopLandingWatch()
    local watch = Personal.landingWatch
    Personal.landingWatch = nil
    if watch and watch.ticker then watch.ticker:Cancel() end
end





function Personal.OnBound()
    local confirm = Personal.confirm
    Personal.confirm = nil
    Personal.InvalidateBind()
    local pos = playerPosition()
    local asked = confirm and now() - confirm.at <= Personal.CONFIRM_SECONDS
    if asked and confirm.pos and pos then
        asked = pos.inst == confirm.pos.inst and dist(pos.x, pos.y, confirm.pos.x, confirm.pos.y) <= Personal.CONFIRM_YARDS
    end
    if asked then return Personal.LearnBind("bound", confirm.name) end
    if FGPS.Log and not Personal.unaskedLogged then
        Personal.unaskedLogged = true
        FGPS.Log:Info("Hearthstone: HEARTHSTONE_BOUND came without the innkeeper's question just before, here; nothing learned from it")
    end
    return nil
end





function Personal.CheckLanding()
    local watch = Personal.landingWatch
    if not watch then return nil end
    local pos = playerPosition()
    local from = watch.from
    if pos and (watch.loaded or (from and (pos.inst ~= from.inst or dist(pos.x, pos.y, from.x, from.y) > Personal.LANDING_JUMP_YARDS))) then
        Personal.StopLandingWatch()
        return Personal.LearnBind("landed")
    end
    if now() - watch.since > Personal.LANDING_SECONDS then
        Personal.StopLandingWatch()
        if FGPS.Log then FGPS.Log:Info("Hearthstone: no landing seen within %d s of the cast", Personal.LANDING_SECONDS) end
        return nil
    end
    if pos then watch.from = pos end
    return nil
end

function Personal.WatchLanding()
    Personal.StopLandingWatch()
    local watch = { since = now(), from = playerPosition() }
    Personal.landingWatch = watch
    if C_Timer and C_Timer.NewTicker then
        watch.ticker = C_Timer.NewTicker(Personal.LANDING_TICK_SECONDS, function() Personal.CheckLanding() end)
    end
end



local function worldEntered()
    local watch = Personal.landingWatch
    if not watch then return end
    watch.loaded, watch.since = true, now()
    Personal.CheckLanding()
end

local function learnedPosition(rec)
    local pos = { inst = rec.inst, x = rec.x, y = rec.y, map = rec.map, zoneName = rec.zone, poiName = rec.name }
    local D = FGPS.Destinations
    if D and D.WorldToMap then
        local map, mx, my = D.WorldToMap(pos.inst, pos.x, pos.y, pos.map)
        if map then pos.map, pos.mx, pos.my = map, mx, my end
    end
    return pos
end




local function landing(bindName)
    local pos = Personal.ResolveBind(bindName)
    if pos then return pos, "resolved" end
    local rec = Personal.LearnedBind()
    if not rec then return nil, "unknown" end
    if bindName and rec.bindText and rec.bindText ~= bindName then return nil, "stale" end
    return learnedPosition(rec), "learned", rec
end




local function measuredCast(id, fallback)
    local Calibrate = FGPS.Calibrate
    if Calibrate and Calibrate.TeleportSeconds then
        local ok, cast = pcall(Calibrate.TeleportSeconds, id)
        if ok and type(cast) == "number" and cast > 0 then return cast end
    end
    return fallback
end



local function castsHearth(itemID)
    if itemID == Personal.HEARTH_ITEM then return true end
    local known = Personal.hearthItems[itemID]
    if known ~= nil then return known end
    if not (C_Item and C_Item.GetItemSpell) then return false end
    local ok, _, spellID = pcall(C_Item.GetItemSpell, itemID)
    spellID = ok and tonumber(plain(spellID)) or nil
    if not spellID then return false end
    Personal.hearthItems[itemID] = spellID == Personal.HEARTH_SPELL
    return Personal.hearthItems[itemID]
end

local function hearthInBags()
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemID) then return nil end
    for bag = 0, Personal.LAST_BAG do
        local ok, slots = pcall(C_Container.GetContainerNumSlots, bag)
        slots = ok and tonumber(plain(slots)) or 0
        for slot = 1, slots do
            local okItem, itemID = pcall(C_Container.GetContainerItemID, bag, slot)
            itemID = okItem and tonumber(plain(itemID)) or nil
            if itemID and castsHearth(itemID) then return itemID end
        end
    end
    return nil
end

local function hearthToy()
    if not PlayerHasToy then return nil end
    for _, toyID in ipairs(Personal.HEARTH_TOYS) do
        local ok, has = pcall(PlayerHasToy, toyID)
        if ok and plain(has) then
            local usable = true
            if C_ToyBox and C_ToyBox.IsToyUsable then
                local okUse, can = pcall(C_ToyBox.IsToyUsable, toyID)
                if okUse and plain(can) == false then usable = false end
            end
            if usable then return toyID end
        end
    end
    return nil
end






local function findHearthstone()
    local said = "missing"
    if C_Container and C_Container.PlayerHasHearthstone then
        local ok, id = pcall(C_Container.PlayerHasHearthstone)
        if not ok then said = "an error"
        elseif id == nil then said = "nil"
        elseif issecretvalue and issecretvalue(id) then said = "a secret value"
        else
            said = tostring(id)
            if id then return tonumber(id) or Personal.HEARTH_ITEM, "client", said end
        end
    end
    local id = hearthInBags()
    if id then return id, "bags", said end
    id = hearthToy()
    if id then return id, "toy", said end
    return nil, nil, said
end




local LANDING_WORDS = {
    resolved = "found by its name in the navigation data", stale = "unknown (learned under another bind text)",
    unknown = "unknown (not learned yet)",
}
local function logCheck(s)
    if not FGPS.Log then return end
    local item
    if s.found == "client" then item = format("item %d named by the client", s.item)
    elseif s.found == "bags" then item = format("item %d found in the bags", s.item)
    elseif s.found == "toy" then item = format("toy %d found in the toy box", s.item)
    else item = "no hearthstone in the bags or the toy box" end
    local bind = s.bind == "text" and format('"%s"', s.bindName) or s.bind
    local land = s.landing == "learned" and ("learned from " .. (HOW_WORDS[s.learned] or "?")) or LANDING_WORDS[s.landing] or tostring(s.landing)
    local line = format("Hearthstone check: PlayerHasHearthstone gave %s, %s; GetBindLocation gave %s; landing %s", s.said, item, bind, land)
    if line == Personal.hearthLogged then return end
    Personal.hearthLogged = line
    FGPS.Log:Info("%s", line)
end




function Personal.Hearth()
    local itemID, found, said = findHearthstone()
    local bindName, bindWord = readBind()
    local pos, how, rec = landing(bindName)
    Personal.hearthState = { item = itemID, found = found, said = said, bind = bindWord, bindName = bindName, landing = how,
                             learned = rec and rec.how or nil }
    logCheck(Personal.hearthState)
    if not itemID then return nil end
    local start, duration = itemCooldown(itemID)
    local ready, remaining = readiness(start, duration)
    local opt = { kind = "hearth", id = itemID, name = L["Hearthstone"], bindName = bindName, ready = ready, cdRemaining = remaining,
                  castSeconds = measuredCast("hearth", Const.HEARTH_CAST_SECONDS or 10), known = true, landing = how }
    if pos then
        opt.inst, opt.x, opt.y, opt.map, opt.mx, opt.my = pos.inst, pos.x, pos.y, pos.map, pos.mx, pos.my
        opt.zoneName, opt.poiIndex, opt.targetName = pos.zoneName, pos.poiIndex, pos.poiName


        opt.placeName = how == "resolved" and bindName or pos.poiName or pos.zoneName
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
                    pos = landing(hearth and hearth.bindName or bindLocation())
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



function Personal.HearthNote()
    local opt = Personal.Hearth()
    if not opt then return L["Hearthstone not used: no hearthstone in your bags."] end
    if not opt.routable then
        return L["Hearthstone not used: Cabbie learns where your hearthstone takes you the first time you use it or bind at an inn."]
    end
    local remaining = tonumber(opt.cdRemaining) or 0
    if not opt.ready and remaining >= (Const.TELEPORT_MAX_WAIT or 120) then
        return format(L["Hearthstone not used: on cooldown for %d min."], math.ceil(remaining / 60))
    end
    return nil
end

function Personal.InvalidateBind()
    wipe(Personal.bindCache)
end




function Personal:Init()
    if self.initialised then return end
    self.initialised = true



    Events:RegisterWoW("CONFIRM_BINDER", function(_, areaName)
        areaName = plain(areaName)
        Personal.confirm = { name = type(areaName) == "string" and areaName ~= "" and areaName or nil, at = now(),
                             pos = playerPosition() }
    end, self)
    Events:RegisterWoW("HEARTHSTONE_BOUND", function() Personal.OnBound() end, self)
    Events:RegisterUnitWoW("UNIT_SPELLCAST_SUCCEEDED", "player", function(_, unit, _, spellID)
        if unit == "player" and Personal.LANDING_SPELLS[tonumber(plain(spellID)) or 0] then Personal.WatchLanding() end
    end, self)
    Events:Register("WORLD_ENTERED", worldEntered, self)



end
