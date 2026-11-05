

















local ADDON_NAME, FGPS = ...

local L = FGPS.L
local type, tonumber, tostring, pcall, ipairs, format, floor = type, tonumber, tostring, pcall, ipairs, string.format, math.floor

local Leveling = {
    key = nil,
    seq = nil,
    firstAt = nil,
    levelOf = nil,
    neededUntil = nil,
    index = nil,
    shown = {},
    ahead = {},
    signature = nil,
    doneMemo = {},
    gone = {},
    pending = false,
    initialised = false,

    stats = { addon = ADDON_NAME, refreshes = 0, lastMs = 0, maxMs = 0, scanned = 0, built = 0, buildMs = 0 },
}
FGPS.Leveling = Leveling

Leveling.SHOWN = 8
Leveling.AHEAD = 16
Leveling.MAX_SCAN = 400
Leveling.OUTLEVELED = 5

Leveling.YARDS_PER_POINT = 4
Leveling.DELAY = 0.3
Leveling.ACTIONS = { [0] = "accept", [1] = "complete", [2] = "turnin" }

Leveling.CLASS_SCORE = { [4] = 70, [3] = 55, [2] = 50, [1] = 30, [0] = 0 }

local RACES = { human = true, dwarf = true, gnome = true, nightelf = true, orc = true, troll = true,
                tauren = true, undead = true, scourge = true, skyborne = true }
local CLASSES = { warrior = true, paladin = true, shaman = true, hunter = true, rogue = true, priest = true,
                  mage = true, warlock = true, druid = true }

local OFF = { sod = true, som = true, season = true, wotlk = true, tbc = true, hardcore = true, skip = true }

local function data()
    local d = FGPS.Data and FGPS.Data.leveling
    if type(d) == "table" and type(d.routes) == "table" then return d end
    return nil
end

local function clock()
    if debugprofilestop then return debugprofilestop() end
    return 0
end



function Leveling.Decode(n)
    local fi = n % 512
    n = (n - fi) / 512
    local fv = n % 2
    n = (n - fv) / 2
    local o = n % 8
    n = (n - o) / 8
    local l = n % 64
    n = (n - l) / 64
    local s = n % 128
    n = (n - s) / 128
    local a = n % 4
    return (n - a) / 4, a, s, l, o, fv, fi
end
local decode = Leveling.Decode


function Leveling.DecodeClass(n)
    local side = n % 4
    n = (n - side) / 4
    local l = n % 64
    n = (n - l) / 64
    local p = n % 8
    return (n - p) / 8, p, l, side
end

function Leveling.Enabled()
    local db = FGPS.DB
    if db and db.Get and db:Get("quests.leveling") == false then return false end
    if db and db.Get and db:Get("quests.enabled") == false then return false end
    return data() ~= nil
end


function Leveling.Context()
    local faction, raceFile, raceID, classFile, level
    if UnitFactionGroup then
        local ok, f = pcall(UnitFactionGroup, "player")
        if ok and (f == "Alliance" or f == "Horde") then faction = f end
    end
    if UnitRace then
        local ok, _, file, id = pcall(UnitRace, "player")
        if ok and type(file) == "string" then raceFile, raceID = file, tonumber(id) end
    end
    if UnitClass then
        local ok, _, file = pcall(UnitClass, "player")
        if ok and type(file) == "string" then classFile = file end
    end
    if UnitLevel then
        local ok, lv = pcall(UnitLevel, "player")
        if ok then level = tonumber(lv) end
    end
    if not (faction and raceFile and classFile) then return nil end
    local race = raceFile:lower()
    if race == "scourge" then race = "undead" end
    return { faction = faction, raceFile = raceFile, raceID = raceID, race = race,
             classFile = classFile, class = classFile:lower(), level = level or 0,
             key = faction .. "|" .. raceFile .. "|" .. classFile }
end

local function tokenTrue(tok, ctx)
    local neg = tok:sub(1, 1) == "!"
    local t = (neg and tok:sub(2) or tok):lower()
    local v
    if t == "alliance" or t == "horde" then
        v = ctx.faction:lower() == t
    elseif RACES[t] then
        if t == "scourge" then t = "undead" end
        v = ctx.race == t
    elseif CLASSES[t] then
        v = ctx.class == t
    elseif OFF[t] or t:find("^season") or t:find("^xprate") then
        v = false
    else
        v = true
    end
    if neg then return not v end
    return v
end



function Leveling.Matches(f, ctx)
    if f == nil or f == "" then return true end
    for part in (f .. " & "):gmatch("(.-) & ") do
        if part ~= "" then
            local any = false
            for clause in (part .. "/"):gmatch("([^/]*)/") do
                local all = clause:find("%S") ~= nil
                for tok in clause:gmatch("%S+") do
                    if not tokenTrue(tok, ctx) then all = false break end
                end
                if all then any = true break end
            end
            if not any then return false end
        end
    end
    return true
end

local function charStore()
    local char = FGPS.DB and FGPS.DB.char
    if type(char) ~= "table" then return nil end
    if type(char.leveling) ~= "table" then char.leveling = {} end
    local store = char.leveling
    if type(store.skipped) ~= "table" then store.skipped = {} end
    return store
end


local function ensure(ctx)
    local d = data()
    if not d or not ctx then return nil end
    if Leveling.key == ctx.key and Leveling.seq then return Leveling.seq end
    local t0 = clock()
    local routes = d.routes[ctx.faction]
    local start = d.startFor and d.startFor[ctx.raceFile]
    local filters = d.filters or {}
    local ok = {}
    local seq, firstAt, levelOf = {}, {}, {}



    local lastLevel = 0
    local function take(list)
        if type(list) ~= "table" then return end
        for i = 1, #list do
            local n = list[i]
            local fi = n % 512
            local pass = true
            if fi > 0 then
                pass = ok[fi]
                if pass == nil then
                    pass = Leveling.Matches(filters[fi], ctx)
                    ok[fi] = pass
                end
            end
            if pass then
                seq[#seq + 1] = n
                local q, a, _, l = decode(n)
                if not firstAt[q] then firstAt[q] = #seq end
                if l > 0 then
                    lastLevel = l
                elseif a == 0 and lastLevel > 0 and not levelOf[q] then
                    levelOf[q] = lastLevel
                end
            end
        end
    end
    if routes then
        take(start and routes[start])
        take(routes.shared)
    end






    local neededUntil = {}
    local QuestData = FGPS.QuestData
    if QuestData and QuestData.EarlierQuests then
        for p = 1, #seq do
            local q, a, _, l = decode(seq[p])
            if a == 0 then
                if l == 0 then l = levelOf[q] or 0 end
                if l > 0 then
                    local okList, earlier = pcall(QuestData.EarlierQuests, q)
                    for _, e in ipairs(okList and type(earlier) == "table" and earlier or {}) do
                        local at = firstAt[e]
                        if at and at < p and (neededUntil[e] or 0) < l then
                            local _, ha, _, hl = decode(seq[at])
                            if hl == 0 then hl = levelOf[e] or 0 end
                            if ha == 0 and l > hl then neededUntil[e] = l end
                        end
                    end
                end
            end
        end
    end
    Leveling.key, Leveling.seq, Leveling.firstAt, Leveling.index = ctx.key, seq, firstAt, nil
    Leveling.levelOf, Leveling.neededUntil = levelOf, neededUntil
    Leveling.start = start
    local store = charStore()
    if store and store.key ~= ctx.key then
        store.key, store.cursor, store.skipped = ctx.key, 1, {}
    end
    Leveling.stats.built = Leveling.stats.built + 1
    Leveling.stats.buildMs = clock() - t0
    return seq
end

local function cursorOf(store, seq)
    local c = store and tonumber(store.cursor) or 1
    if c < 1 or c > #seq + 1 then c = 1 end
    return floor(c)
end

local function isDone(q)
    if Leveling.doneMemo[q] then return true end
    local QuestData = FGPS.QuestData
    local done = QuestData and QuestData.IsDone and QuestData.IsDone(q)
    if done then Leveling.doneMemo[q] = true end
    return done == true
end

local function inLog(q)



    if Leveling.gone[q] then return false end
    local QuestData = FGPS.QuestData
    return QuestData and QuestData.InLog and QuestData.InLog(q) == true or false
end


local function objectiveDone(q, o)
    local Quests = FGPS.Quests
    if not (Quests and Quests.Get) then return false end
    local ok, held = pcall(Quests.Get, q)
    if not ok or type(held) ~= "table" then return false end
    if held.complete then return true end
    local list = held.objectives
    if o > 0 and type(list) == "table" and list[o] then return list[o].finished and true or false end
    return false
end


local EARLIER = { earlier = true, earlier_one = true, earlier_log = true }







local LASTING = { race = true, class = true, side = true, level_max = true }








local function takeState(q)
    local QuestData = FGPS.QuestData
    if not (QuestData and QuestData.CanTake) then return nil end
    local ok, verdict, _, code = pcall(QuestData.CanTake, q)
    if not (ok and verdict == "no") then return nil end
    local need, told
    if code == "level" then
        if not QuestData.CanTakeAtAnyLevel then return nil end
        local okPast, past, _, pastCode, pastNeed = pcall(QuestData.CanTakeAtAnyLevel, q)
        if not (okPast and past == "no") then return nil end
        code, need, told = pastCode, pastNeed, true
    end
    if LASTING[code] then return "pass" end
    if code == "exclusive" then
        local okShut, shut = pcall(QuestData.ExclusiveDone, q)
        if okShut and shut == true then return "pass" end
        return nil
    end
    if EARLIER[code] ~= true then return nil end
    if told then return "wait", need end
    if not QuestData.WaitsFor then return "wait" end
    local okNeed, waitsFor = pcall(QuestData.WaitsFor, q)
    return "wait", okNeed and waitsFor or nil
end



Leveling.WAIT_DEPTH = 3

local stepState









local function comesThrough(need, ctx, skipped, from, depth)
    if depth >= Leveling.WAIT_DEPTH then return true end
    if type(need) == "table" then
        for k = 1, #need do
            local x = tonumber(need[k])

            if x and not (x > 0 and isDone(x)) and comesThrough(x, ctx, skipped, from, depth) then return true end
        end
        return #need == 0
    end
    need = tonumber(need)
    if not need then return true end
    local x = need < 0 and -need or need
    if skipped[x] then return false end
    if isDone(x) then return need > 0 end
    if inLog(x) then return true end
    local at = Leveling.firstAt and Leveling.firstAt[x]
    if not at or at < from then return false end
    local state = stepState(Leveling.seq[at], ctx, skipped, from, depth + 1)
    return state == "open" or state == "wait"
end






function stepState(n, ctx, skipped, from, depth)
    local q, a, _, l, o = decode(n)
    if skipped[q] then return "pass" end
    if isDone(q) then return "done" end
    local held = inLog(q)
    if a == 0 then
        if held then return "done" end
        if l == 0 then l = Leveling.levelOf and Leveling.levelOf[q] or 0 end
        if l > 0 and ctx.level > 0 and ctx.level >= l + Leveling.OUTLEVELED then
            local until_ = Leveling.neededUntil and Leveling.neededUntil[q]
            if not (until_ and ctx.level < until_ + Leveling.OUTLEVELED) then return "pass" end
        end
        local state, need = takeState(q)
        if state == "pass" then return "pass" end
        if state == "wait" then
            if comesThrough(need, ctx, skipped, from or 1, depth or 0) then return "wait" end
            return "pass"
        end
        return "open"
    end
    if not held then return "pass" end
    if a == 1 and objectiveDone(q, o) then return "done" end
    return "open"
end

local function entryFor(n, d)
    local q, a, s, l, o, fv = decode(n)
    return { questID = q, action = Leveling.ACTIONS[a] or "accept", objective = o > 0 and o or nil,
             level = l > 0 and l or nil, score = s, forever = fv == 1,
             untested = l >= (d.untestedFrom or 31) }
end


function Leveling.Refresh()
    Leveling.pending = nil
    if not Leveling.Enabled() then
        if #Leveling.shown > 0 then
            Leveling.shown, Leveling.ahead, Leveling.signature = {}, {}, nil
            if FGPS.Events then FGPS.Events:Fire("LEVELING_UPDATED", Leveling.shown) end
        end
        return Leveling.shown
    end
    local ctx = Leveling.Context()
    local seq = ensure(ctx)
    if not seq then return Leveling.shown end
    local t0 = clock()
    local d = data()
    local store = charStore() or { skipped = {} }
    local skipped = store.skipped or {}
    local i = cursorOf(store, seq)





    local atCursor
    while i <= #seq do
        atCursor = stepState(seq[i], ctx, skipped, i)
        if atCursor == "open" or atCursor == "wait" then break end
        i = i + 1
    end
    store.cursor = i
    local shown, ahead, parts = {}, {}, {}




    local last = #seq
    local want = Leveling.AHEAD > Leveling.SHOWN and Leveling.AHEAD or Leveling.SHOWN
    local j = i
    while j <= last and #ahead < want do
        local n = seq[j]
        if (j == i and atCursor == "open") or (j > i and stepState(n, ctx, skipped, i) == "open") then
            if #ahead == 0 and j + Leveling.MAX_SCAN < last then last = j + Leveling.MAX_SCAN end
            local e = entryFor(n, d)
            e.position = j
            ahead[#ahead + 1] = e
            if #shown < Leveling.SHOWN then
                shown[#shown + 1] = e
                parts[#parts + 1] = n
            end
        end
        j = j + 1
    end
    Leveling.shown, Leveling.ahead = shown, ahead
    local stats = Leveling.stats
    stats.refreshes = stats.refreshes + 1
    stats.scanned = j - i
    stats.lastMs = clock() - t0
    if stats.lastMs > stats.maxMs then stats.maxMs = stats.lastMs end
    local signature = table.concat(parts, ",") .. "|" .. tostring(ctx.level)
    if signature ~= Leveling.signature then
        Leveling.signature = signature
        if FGPS.Events then FGPS.Events:Fire("LEVELING_UPDATED", shown) end
    end
    if FGPS.Events then FGPS.Events:Fire("LEVELING_REFRESHED", shown) end
    return shown
end




function Leveling.Schedule()
    local now = GetTime and GetTime() or 0
    local pending = Leveling.pending
    if pending and now >= pending and now - pending < Leveling.DELAY + 1 then return end
    Leveling.pending = now
    if C_Timer and C_Timer.After then
        C_Timer.After(Leveling.DELAY, function()
            if Leveling.pending then Leveling.Refresh() end
        end)
    else
        Leveling.Refresh()
    end
end



local function rewindTo(q)
    q = tonumber(q)
    local firstAt = Leveling.firstAt
    local store = charStore()
    if not (q and firstAt and firstAt[q] and store) then return end
    if (tonumber(store.cursor) or 1) > firstAt[q] then store.cursor = firstAt[q] end
end
Leveling.RewindTo = rewindTo



function Leveling.Next(n)
    if not Leveling.signature then Leveling.Refresh() end
    local out = {}
    for k = 1, math.min(n or Leveling.SHOWN, #Leveling.shown) do out[k] = Leveling.shown[k] end
    return out
end


function Leveling.Ahead()
    if not Leveling.signature then Leveling.Refresh() end
    return Leveling.ahead
end



local PRIORITY_NAME = { [4] = "mandatory", [3] = "recommended", [2] = "roster", [1] = "optional", [0] = "skip" }
function Leveling.ClassQuests(n)
    local d, ctx = data(), Leveling.Context()
    local out = {}
    if not (d and ctx and d.classQuests) then return out end
    local list = d.classQuests[ctx.classFile]
    if type(list) ~= "table" then return out end
    local side = ctx.faction == "Alliance" and 1 or 2
    local QuestData = FGPS.QuestData
    local skipped = (charStore() or {}).skipped or {}
    for _, packed in ipairs(list) do
        local q, p, l, s = Leveling.DecodeClass(packed)
        local races = d.classRaces and d.classRaces[q]
        local raceOK = true
        if races and ctx.raceID then
            raceOK = false
            for _, r in ipairs(races) do if r == ctx.raceID then raceOK = true end end
        end
        if p > 0 and raceOK and (s == 0 or s == side) and not skipped[q]
            and (ctx.level <= 0 or l <= ctx.level + 2) and not isDone(q) then
            local verdict = QuestData and QuestData.CanTake and QuestData.CanTake(q)
            if verdict ~= "no" or inLog(q) then
                out[#out + 1] = { questID = q, level = l > 0 and l or nil, priority = PRIORITY_NAME[p] }
                if #out >= (n or 4) then break end
            end
        end
    end
    return out
end



function Leveling.Bonus(questID)
    if not Leveling.Enabled() then return 0 end
    local ctx = Leveling.Context()
    local seq = ensure(ctx)
    if not seq then return 0 end
    local index = Leveling.index
    if not index then
        index = {}
        for i = 1, #seq do
            local q, _, s = decode(seq[i])
            if not index[q] or s > index[q] then index[q] = s end
        end
        local d = data()
        local list = d.classQuests and d.classQuests[ctx.classFile]
        for _, packed in ipairs(type(list) == "table" and list or {}) do
            local q, p = Leveling.DecodeClass(packed)
            if not index[q] then index[q] = Leveling.CLASS_SCORE[p] or 0 end
        end
        Leveling.index = index
    end
    local s = index[tonumber(questID)]
    return s and s * Leveling.YARDS_PER_POINT or 0
end


function Leveling.Title(questID)
    local QuestData = FGPS.QuestData
    local title = QuestData and QuestData.Title and QuestData.Title(questID)
    if type(title) == "string" and title ~= "" then return title end
    local d = data()
    title = d and d.titles and d.titles[questID]
    if type(title) == "string" and title ~= "" then return title end
    return format(L["Quest %d"], questID)
end


function Leveling.Status()
    local ctx = Leveling.Context()
    local seq = ensure(ctx)
    local store = charStore()
    local d = data()
    return {
        context = ctx, start = Leveling.start, total = seq and #seq or 0,
        cursor = seq and cursorOf(store, seq) or 1,
        untestedFrom = d and d.untestedFrom or 31, pendingZones = d and d.pendingZones or {},
        skipped = store and store.skipped or {},
    }
end





function Leveling.StateAt(position)
    local seq = Leveling.seq
    local n = type(seq) == "table" and seq[tonumber(position) or 0] or nil
    local ctx = n and Leveling.Context()
    if not ctx then return nil end
    local store = charStore()
    local _, a = decode(n)
    return stepState(n, ctx, store and store.skipped or {}, cursorOf(store, seq)), Leveling.ACTIONS[a]
end



local function waitingAtCursor()
    local seq, store = Leveling.seq, charStore()
    local ctx = seq and Leveling.Context()
    if not (ctx and store) then return nil end
    local c = cursorOf(store, seq)
    local n = seq[c]
    if not n or stepState(n, ctx, store.skipped, c) ~= "wait" then return nil end
    return (decode(n))
end



function Leveling.Skip(questID)
    questID = tonumber(questID) or (Leveling.shown[1] and Leveling.shown[1].questID) or waitingAtCursor()
    local store = charStore()
    if not (questID and store) then return nil end
    store.skipped[questID] = true
    Leveling.signature = nil
    Leveling.Refresh()
    return questID
end


function Leveling.Reset()
    local store = charStore()
    if store then store.skipped, store.cursor = {}, 1 end
    Leveling.key, Leveling.seq, Leveling.firstAt, Leveling.index, Leveling.signature = nil, nil, nil, nil, nil
    Leveling.doneMemo, Leveling.gone = {}, {}
    return Leveling.Refresh()
end

function Leveling:Init()
    if self.initialised then return end
    self.initialised = true
    local Events = FGPS.Events
    if not Events then return end
    local function soon() if Leveling.Enabled() then Leveling.Schedule() end end
    for _, event in ipairs({ "PLAYER_LEVEL_UP", "QUEST_LOG_UPDATE", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
        Events:RegisterWoW(event, soon, self)
    end


    Events:RegisterWoW("QUEST_ACCEPTED", function(_, a, b)
        local questID = tonumber(b) or tonumber(a)
        if questID then Leveling.gone[questID] = nil end
        rewindTo(questID)
        soon()
    end, self)
    Events:RegisterWoW("QUEST_TURNED_IN", function(_, questID)
        questID = tonumber(questID)
        if questID then Leveling.doneMemo[questID] = true end
        soon()
    end, self)
    Events:RegisterWoW("QUEST_REMOVED", function(_, questID)
        questID = tonumber(questID)

        if questID then Leveling.gone[questID] = true end
        rewindTo(questID)
        soon()
    end, self)
    Events:Register("SETTINGS_CHANGED", function(_, key)
        if key == "quests.leveling" or key == "quests.enabled" or key == "*" then
            Leveling.signature = nil
            Leveling.Refresh()
        end
    end, self)
    soon()
end
