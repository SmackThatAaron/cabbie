





































local ADDON_NAME, FGPS = ...

local L = FGPS.L
local type, tostring, pcall, ipairs, pairs, format, sqrt = type, tostring, pcall, ipairs, pairs, string.format, math.sqrt

local Auto = {
    batch = nil,
    applied = nil,
    applying = false,
    reached = {},
    left = {},
    signature = nil,
    initialised = false,
    stats = { addon = ADDON_NAME, plans = 0, lastMs = 0, maxMs = 0, applied = 0 },
}
FGPS.LevelingAuto = Auto

Auto.HUB_YARDS = 120
Auto.FIELD_YARDS = 300
Auto.MAX_BATCH = 6
Auto.LEAVE_FACTOR = 3

local function clock()
    if debugprofilestop then return debugprofilestop() end
    return 0
end

local function store()
    local char = FGPS.DB and FGPS.DB.char
    if type(char) ~= "table" then return nil end
    if type(char.leveling) ~= "table" then char.leveling = {} end
    return char.leveling
end

local function navigator() return FGPS.Navigator end

local function dead()
    if not UnitIsDeadOrGhost then return false end
    local ok, d = pcall(UnitIsDeadOrGhost, "player")
    return ok and d and true or false
end

local function dist(a, b)
    if a.inst ~= b.inst then return nil end
    local dx, dy = a.x - b.x, a.y - b.y
    return sqrt(dx * dx + dy * dy)
end

function Auto.On()
    local s = store()
    return s ~= nil and s.auto == true
end


local function keyOf(questID, target)
    return tostring(questID) .. ":" .. tostring(target)
end




local UNSURE_OF_CHARACTER = { race_unknown = true, class_unknown = true, side_unknown = true,
                              level_unknown = true, race_doubtful = true }



local function takeable(QuestData, questID)
    local ok, verdict, _, code = pcall(QuestData.CanTake, questID)
    if not ok then return false end
    if verdict == "yes" then return true end
    if verdict ~= "unknown" then return false end
    if UNSURE_OF_CHARACTER[code] then return true end
    return code == "forever_incomplete"
end





Auto.places, Auto.placeCount = {}, 0
Auto.MAX_PLACES = 200

local function progressOf(Quests, q)
    local ok, held = pcall(Quests.Get, q)
    if not ok or type(held) ~= "table" then return "none" end
    local finished = 0
    for _, o in ipairs(held.objectives or {}) do
        if o.finished then finished = finished + 1 end
    end
    return (held.complete and "c" or "o") .. finished
end

local function cachedDest(Quests, q, handle, stamp)
    local key = tostring(q) .. ":" .. tostring(handle)
    local hit = Auto.places[key]
    if hit and hit.stamp == stamp then return hit.dest, hit.why end
    local dest, why = Quests.DestinationFor(q, handle)
    if Auto.placeCount >= Auto.MAX_PLACES then Auto.places, Auto.placeCount = {}, 0 end
    if not hit then Auto.placeCount = Auto.placeCount + 1 end
    Auto.places[key] = { dest = dest, why = why, stamp = stamp }
    return dest, why
end




local function placeOf(entry)
    local QuestData, Quests = FGPS.QuestData, FGPS.Quests
    if not (QuestData and Quests and Quests.DestinationFor) then return nil, "no_data" end
    local q = entry.questID
    if entry.action == "accept" then
        if not (QuestData.CanTake and takeable(QuestData, q)) then return nil, "cannot_take" end
        local dest, why = cachedDest(Quests, q, "giver", "giver")
        if not dest then return nil, why end
        return { entry = entry, kind = "pickup", target = "giver", dest = dest }
    end
    local dest, why = cachedDest(Quests, q, nil, progressOf(Quests, q))
    if not dest then return nil, why end
    local target = dest.questTarget or "client"
    return { entry = entry, kind = target == "turnin" and "turnin" or "objective", target = target, dest = dest }
end

local GROUP = { pickup = "hub", turnin = "hub", objective = "field" }




function Auto.Plan(entries, origin, exclude)
    local passed, seen = {}, {}
    local anchor, group, radius
    local batch = {}
    local QuestData, Quests = FGPS.QuestData, FGPS.Quests
    for _, entry in ipairs(entries or {}) do
        local q = entry.questID
        if q and not seen[q] and not (exclude and exclude[q]) then
            seen[q] = true
            if not anchor then
                local place, why = placeOf(entry)
                if place then
                    anchor, group = place, GROUP[place.kind]
                    radius = group == "hub" and Auto.HUB_YARDS or Auto.FIELD_YARDS
                    batch[1] = place
                else
                    passed[#passed + 1] = { questID = q, why = why }
                end
            elseif #batch < Auto.MAX_BATCH then



                local guess, at = "objective", nil
                if entry.action == "accept" then
                    guess = "pickup"
                    at = QuestData and QuestData.Start and QuestData.Start(q) or nil
                else
                    local okHeld, held = pcall(Quests.Get, q)
                    if okHeld and type(held) == "table" and held.complete then
                        guess = "turnin"
                        at = QuestData and QuestData.TurnIn and QuestData.TurnIn(q) or nil
                    end
                end
                local near = GROUP[guess] == group
                if near and at and at.inst and at.x and at.y then
                    local d = dist(anchor.dest, at)
                    near = d ~= nil and d <= radius * 2
                end
                if near then
                    local p = placeOf(entry)
                    if p and GROUP[p.kind] == group then
                        local d = dist(anchor.dest, p.dest)
                        if d and d <= radius then batch[#batch + 1] = p end
                    end
                end
            end
        end
    end
    if not anchor then return {}, nil, passed end
    local Navigator = navigator()
    if #batch > 1 and origin and Navigator and Navigator.OptimizeOrder then
        local stops = {}
        for i, p in ipairs(batch) do stops[i] = p.dest end
        local ok, order = pcall(Navigator.OptimizeOrder, { inst = origin.inst, x = origin.x, y = origin.y }, stops)
        if ok and type(order) == "table" and #order == #batch then
            local ordered = {}
            for i = 1, #order do ordered[i] = batch[order[i]] end
            batch = ordered
        end
    end
    return batch, group, passed
end



local function remember(batch, group)
    if #batch == 0 then Auto.batch = nil return end
    local anchor = batch[1].dest
    local old = Auto.batch
    local radius = group == "hub" and Auto.HUB_YARDS or Auto.FIELD_YARDS
    local keep = old and old.group == group and old.inst == anchor.inst
        and dist(old, anchor) ~= nil and dist(old, anchor) <= radius
    local now = {}
    for _, p in ipairs(batch) do now[p.entry.questID] = p end
    if keep then
        for _, item in ipairs(old.items) do
            local p = now[item.questID]
            if p then
                item.kind, item.done = p.kind, false
                now[item.questID] = nil
            else
                item.done = true
            end
        end
        for _, p in ipairs(batch) do
            if now[p.entry.questID] then
                old.items[#old.items + 1] = { questID = p.entry.questID, kind = p.kind, done = false }
            end
        end
        return
    end
    local items = {}
    for i, p in ipairs(batch) do items[i] = { questID = p.entry.questID, kind = p.kind, done = false } end
    Auto.reached = {}
    Auto.batch = { group = group, inst = anchor.inst, x = anchor.x, y = anchor.y, items = items }
end


local function routeKeys(Navigator)
    local keys, n = {}, 0
    local ok, stops = pcall(Navigator.GetStops, Navigator)
    if not ok or type(stops) ~= "table" then return keys, 0 end
    for _, stop in ipairs(stops) do
        if stop.questID then
            keys[keyOf(stop.questID, stop.questTarget or "client")] = true
        end
        n = n + 1
    end
    return keys, n
end

local function sameSet(a, b, countB)
    local n = 0
    for k in pairs(a) do
        if not b[k] then return false end
        n = n + 1
    end
    return n == countB
end


local function apply(batch)
    local Navigator = navigator()
    if not (Navigator and Navigator.SetDestination and Navigator.AddStop) then return false end
    local want, any = {}, false
    for _, p in ipairs(batch) do
        local key = keyOf(p.entry.questID, p.target)
        if not Auto.reached[key] then want[key], any = true, true end
    end

    if not any then return false end
    local have, count = routeKeys(Navigator)
    local journey = Navigator.IsJourney and Navigator:IsJourney()
    if sameSet(want, have, count) then
        Auto.applied = want
        if journey or (Navigator.GetState and Navigator:GetState() ~= "idle") then return false end

        Auto.applying = true
        pcall(Navigator.Start, Navigator, nil, true, true, "navigator")
        Auto.applying = false
        return true
    end
    Auto.applying = true
    local ok, err = pcall(function()
        Navigator:SetDestination(batch[1].dest, { quiet = true, start = false, askedBy = "navigator" })
        for k = 2, #batch do
            Navigator:AddStop(batch[k].dest, { quiet = true, start = false, askedBy = "navigator" })
        end
        if not Navigator:IsJourney() then Navigator:Start(nil, true, true, "navigator") end
    end)
    Auto.applying = false
    if not ok and FGPS.Log then FGPS.Log:Warn("LevelingAuto: %s", tostring(err)) end
    Auto.applied = want
    Auto.stats.applied = Auto.stats.applied + 1
    return true
end



function Auto.walkedAway(batch, group, origin)
    local radius = (group == "hub" and Auto.HUB_YARDS or Auto.FIELD_YARDS) * Auto.LEAVE_FACTOR
    for _, p in ipairs(batch) do
        if not Auto.reached[keyOf(p.entry.questID, p.target)] then return false end
        local d = dist(origin, p.dest)
        if d and d <= radius then return false end
    end
    return true
end

local function fire()
    if FGPS.Events then FGPS.Events:Fire("LEVELING_AUTO", Auto.On(), Auto.batch) end
end



function Auto.Update()
    if Auto.busy or not Auto.On() then return false end
    Auto.busy = true
    local ok, set = pcall(Auto.UpdateNow)
    Auto.busy = false
    if not ok then
        if FGPS.Log then FGPS.Log:Warn("LevelingAuto: %s", tostring(set)) end
        return false
    end
    return set
end

function Auto.UpdateNow()
    local Leveling = FGPS.Leveling
    if not (Leveling and Leveling.Enabled and Leveling.Enabled() and Leveling.Ahead) then return false end
    local Navigator = navigator()
    if not Navigator then return false end
    if dead() then return false end

    if Navigator.GetState and Navigator:GetState() == "paused" and not Navigator.pauseReason then return false end
    local t0 = clock()
    local QuestData = FGPS.QuestData
    local origin = QuestData and QuestData.PlayerPos and QuestData.PlayerPos() or nil
    local entries = Leveling.Ahead()
    local batch, group = Auto.Plan(entries, origin, Auto.left)
    if #batch > 0 and origin and Auto.walkedAway(batch, group, origin) then
        for _, p in ipairs(batch) do Auto.left[p.entry.questID] = true end
        batch, group = Auto.Plan(entries, origin, Auto.left)
    end
    local parts = {}
    for i, p in ipairs(batch) do parts[i] = keyOf(p.entry.questID, p.target) end
    local signature = table.concat(parts, ",")
    local changed = signature ~= Auto.signature
    Auto.signature = signature
    if changed then
        remember(batch, group)
        fire()
    end
    local set = false
    if #batch > 0 then set = apply(batch) end
    local stats = Auto.stats
    stats.plans = stats.plans + 1
    stats.lastMs = clock() - t0
    if stats.lastMs > stats.maxMs then stats.maxMs = stats.lastMs end
    return set
end

function Auto.Start()
    local s = store()
    if not s then return false end


    local Leveling = FGPS.Leveling
    if not (Leveling and Leveling.Enabled and Leveling.Enabled()) then return false end
    s.auto = true
    Auto.batch, Auto.signature, Auto.applied, Auto.queued = nil, nil, nil, nil
    Auto.reached, Auto.left = {}, {}
    Auto.places, Auto.placeCount = {}, 0
    FGPS:Print(L["Optimized Leveling: following the order. Cabbie sets the next stop by itself. Press Stop on the Optimized Leveling page to end it."])
    if Leveling.Refresh then Leveling.Refresh() end
    Auto.Update()
    fire()
    return true
end


function Auto.Stop(why)
    local s = store()
    if not s or s.auto ~= true then return false end
    s.auto = nil
    Auto.batch, Auto.signature, Auto.applied, Auto.queued = nil, nil, nil, nil
    if why == "player" then
        FGPS:Print(L["Optimized Leveling: you set a place yourself, so Cabbie stopped setting the next stop. Press Guide Me on the Optimized Leveling page to start it again."])
    else
        FGPS:Print(L["Optimized Leveling: stopped following the order."])
    end
    fire()
    return true
end

function Auto.Toggle()
    if Auto.On() then return Auto.Stop() end
    return Auto.Start()
end


function Auto.Heading(batch)
    batch = batch or Auto.batch
    if not batch then return nil end
    local pickups, turnins, objectives, open = 0, 0, 0, 0
    for _, item in ipairs(batch.items) do
        if item.kind == "pickup" then pickups = pickups + 1
        elseif item.kind == "turnin" then turnins = turnins + 1
        else objectives = objectives + 1 end
        if not item.done then open = open + 1 end
    end
    if objectives > 0 and pickups + turnins == 0 then
        return format(L["Quests to do here: %d (%d left)"], objectives, open)
    end
    if turnins == 0 then return format(L["Quests to pick up here: %d (%d left)"], pickups, open) end
    if pickups == 0 then return format(L["Quests to turn in here: %d (%d left)"], turnins, open) end
    return format(L["Quests to turn in here: %d, to pick up: %d (%d left)"], turnins, pickups, open)
end


local LEFT_BY = { arrived = true, skipped = true, removed = true }








Auto.queued = nil

local function runQueued()
    if not Auto.queued then return end
    Auto.queued = nil
    Auto.Update()
end

function Auto.Queue()
    if not Auto.On() then return false end
    local now = GetTime and GetTime() or 0
    local queued = Auto.queued
    if queued and now >= queued and now - queued < 1 then return false end
    Auto.queued = now
    if C_Timer and C_Timer.After then C_Timer.After(0, runQueued) else runQueued() end
    return true
end

function Auto:Init()
    if self.initialised then return end
    self.initialised = true
    local Events = FGPS.Events
    if not Events then return end
    Events:Register("LEVELING_REFRESHED", function() Auto.Queue() end, self)



    Events:Register("ITINERARY_CHANGED", function(_, stops, reason)
        if not LEFT_BY[reason] or not Auto.applied or not Auto.On() then return end
        local have = {}
        for _, stop in ipairs(stops or {}) do
            if stop.questID then have[keyOf(stop.questID, stop.questTarget or "client")] = true end
        end
        for key in pairs(Auto.applied) do
            if not have[key] then Auto.reached[key] = true end
        end
    end, self)



    Events:Register("SETTINGS_CHANGED", function(_, key)
        if key ~= "quests.leveling" and key ~= "quests.enabled" and key ~= "*" then return end
        local Leveling = FGPS.Leveling
        if Auto.On() and not (Leveling and Leveling.Enabled and Leveling.Enabled()) then Auto.Stop() end
    end, self)



    Events:Register("DESTINATION_SET", function(_, dest, askedBy)
        if Auto.applying or askedBy == "navigator" or not Auto.On() then return end
        if type(dest) == "table" and dest.kind == "custom" and (dest.type == "corpse" or dest.type == "graveyard") then return end
        Auto.Stop("player")
    end, self)

    Events:Register("NAV_CANCELLED", function(_, reason)
        if Auto.applying or reason ~= "user" or not Auto.On() then return end
        Auto.Stop()
    end, self)
end
