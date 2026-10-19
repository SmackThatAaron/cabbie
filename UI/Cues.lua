-- Cabbie/UI/Cues.lua
-- Short non-speech audio cues: a quiet click shortly before a turn, a distinct sound for a
-- transport action (board, fly, disembark, land) and one for arrival. They are meant for players
-- who want to be told when something is coming without a voice reading sentences to them, so they
-- work on their own and they also work alongside UI/Voice.lua.
--
-- Only sounds the client already ships are used, addressed through the shared SOUNDKIT constant
-- table. That table differs between builds, so every cue names an ordered list of candidates and
-- the first identifier the running client actually defines is the one that is played; a cue whose
-- candidates are all missing simply stays silent instead of erroring or playing a wrong sound.
-- Nothing is ever loaded from a file path of our own: no media ships for this.
--
-- Playback goes through C_Sound.PlaySound when the client has it, because that call takes a
-- volume override and the cue volume setting is only honest with it. The older global PlaySound
-- has no volume argument; when that is all the client offers, the cue is played at the game's own
-- sound effect volume and the slider only decides whether the cue plays at all (a volume of zero
-- is silence either way).
--
-- Cues are off by default. In combat they follow the same policy as spoken guidance: silent unless
-- the combat policy is "all". They are also off while the performance switch ("/cabbie perf
-- toggle") has all guidance work turned off.
local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local type, ipairs, pairs, tostring, tonumber, sqrt = type, ipairs, pairs, tostring, tonumber, math.sqrt

local Cues = {
    currentStep = nil,
    announced = {},         -- step index -> true once the turn cue fired for it
    lastPlayed = nil,       -- name of the last cue played (tests and "/cabbie cues status")
    stats = { played = 0, suppressed = 0, missing = 0 },
    resolved = nil,         -- cue name -> sound kit id, resolved once per session
}
FGPS.UI.Cues = Cues

-- Defaults for the preferences this module owns (see UI/Skins.lua AddSettingDefault).
FGPS.UI.AddSettingDefault("cues", { enabled = false, volume = 60, turn = true, transport = true, arrival = true })

-- Distance at which the turn cue fires, matching the "turn" stage of the spoken guidance so the
-- two never disagree about when a manoeuvre is imminent.
Cues.TURN_YARDS = 25
-- Two cues closer together than this run into each other and stop being distinguishable, so the
-- second one is dropped. Arrival is exempt: it is the one cue that must not be swallowed by a turn
-- announced a moment earlier.
Cues.MIN_GAP_SECONDS = 1.5
local ALWAYS_HEARD = { arrival = true }

-- Ordered candidates per cue. Every name is a SOUNDKIT key of the Forever client; the fallbacks
-- are names that have existed for many builds, so a cue keeps working on an older table.
Cues.CANDIDATES = {
    turn = { "UI_MAP_WAYPOINT_CONTROL_CLICK", "IG_MAINMENU_OPTION_CHECKBOX_ON", "MAP_PING" },
    transport = { "UI_MAP_WAYPOINT_SUPER_TRACK_ON", "MAP_PING", "UI_MAP_WAYPOINT_ADD" },
    arrival = { "UI_WORLDQUEST_COMPLETE", "UI_MAP_WAYPOINT_REMOVE", "IG_MAINMENU_OPTION_CHECKBOX_OFF" },
}
Cues.ORDER = { "turn", "transport", "arrival" }

-- Step kinds that count as a transport action rather than a turn.
local TRANSPORT_KINDS = { board = true, disembark = true, fly = true, land = true, hearth = true, cast = true }
-- Step kinds that arrival handles, so the turn cue leaves them alone.
local ARRIVAL_KINDS = { arrive = true, stop_arrive = true }
-- Step kinds with no manoeuvre worth a sound.
local QUIET_KINDS = { continue = true, zone = true, depart = true }

-------------------------------------------------------------------------------
-- Settings
-------------------------------------------------------------------------------
local function cueSettings()
    local s = FGPS.DB and FGPS.DB.settings
    local c = s and s.cues
    if type(c) ~= "table" then return nil end
    return c
end

function Cues:IsEnabled()
    if FGPS.Perf and FGPS.Perf.guidanceEnabled == false then return false end
    local c = cueSettings()
    return c ~= nil and c.enabled == true
end

-- 0..100 as stored, clamped.
function Cues:GetVolume()
    local c = cueSettings()
    return Util.Clamp(tonumber(c and c.volume) or 60, 0, 100)
end

-- Per-event toggle; an absent key counts as on, so a cue added later is audible once cues are on.
function Cues:IsCueEnabled(name)
    local c = cueSettings()
    if not c then return false end
    return c[name] ~= false
end

local function combatPolicy()
    local Navigator = FGPS.Navigator
    if Navigator and Navigator.CombatPolicy then
        local ok, policy = pcall(Navigator.CombatPolicy, Navigator)
        if ok and type(policy) == "string" then return policy end
    end
    local s = FGPS.DB and FGPS.DB.settings
    return s and s.combatMode or "visuals_only"
end

function Cues:IsBlockedByCombat()
    return self.inCombat == true and combatPolicy() ~= "all"
end

-------------------------------------------------------------------------------
-- Sound kit resolution
-------------------------------------------------------------------------------
-- The shared sound kit constant table, or nil when this client does not provide it.
local function soundKit()
    if type(SOUNDKIT) == "table" then return SOUNDKIT end
    return nil
end

-- The sound kit id behind a cue name, or nil when this client defines none of its candidates.
-- Resolved once and remembered; SOUNDKIT never changes inside a session.
function Cues:SoundID(name)
    self.resolved = self.resolved or {}
    local cached = self.resolved[name]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end
    local found = false
    local kit = soundKit()
    if kit then
        for _, key in ipairs(Cues.CANDIDATES[name] or {}) do
            local id = kit[key]
            if type(id) == "number" then
                found = id
                break
            end
        end
    end
    self.resolved[name] = found
    if found == false then
        self.stats.missing = self.stats.missing + 1
        FGPS.Log:Debug("No sound kit identifier for the '%s' cue in this client; that cue stays silent", tostring(name))
        return nil
    end
    return found
end

-- Which candidate answered, for "/cabbie cues status" and the tests.
function Cues:SoundName(name)
    local kit = soundKit()
    if not kit then return nil end
    for _, key in ipairs(Cues.CANDIDATES[name] or {}) do
        if type(kit[key]) == "number" then return key end
    end
    return nil
end

-------------------------------------------------------------------------------
-- Playback
-------------------------------------------------------------------------------
local function now()
    return GetTime and GetTime() or 0
end

-- Plays one resolved sound. Returns true when the client accepted it.
local function playSound(id, volume01)
    if C_Sound and type(C_Sound.PlaySound) == "function" then
        local ok, played = pcall(C_Sound.PlaySound, id, nil, true, false, nil, volume01)
        if ok and played ~= false then return true end
    end
    if type(PlaySound) == "function" then
        -- No volume argument here: the cue follows the game's own sound effect volume.
        local ok, played = pcall(PlaySound, id, "SFX", true)
        if ok and played ~= false then return true end
    end
    return false
end

-- Cues:Play(name, opts) -> bool
-- opts.force skips the per-event toggle and the combat block (used by "/cabbie cues test").
function Cues:Play(name, opts)
    opts = opts or {}
    if not opts.force then
        if not self:IsEnabled() then return false end
        if not self:IsCueEnabled(name) then return false end
        if self:IsBlockedByCombat() then
            self.stats.suppressed = self.stats.suppressed + 1
            return false
        end
        local t = now()
        if not ALWAYS_HEARD[name] and self.lastTime and (t - self.lastTime) < Cues.MIN_GAP_SECONDS then
            self.stats.suppressed = self.stats.suppressed + 1
            return false
        end
    end
    local volume = self:GetVolume()
    if volume <= 0 and not opts.force then return false end
    local id = self:SoundID(name)
    if not id then return false end
    if not playSound(id, volume / 100) then return false end
    self.lastTime = now()
    self.lastPlayed = name
    self.stats.played = self.stats.played + 1
    return true
end

-------------------------------------------------------------------------------
-- Navigation events
-------------------------------------------------------------------------------
local function stepIndex(step)
    return step.index or step.legIndex or 0
end

local function distanceToStep(step, progress)
    if type(progress) ~= "table" then return nil end
    local pos = progress.pos
    if type(step) == "table" and step.x and step.y and type(pos) == "table" and pos.x and pos.y
        and (step.inst == nil or pos.inst == nil or step.inst == pos.inst) then
        local dx, dy = step.x - pos.x, step.y - pos.y
        return sqrt(dx * dx + dy * dy)
    end
    return tonumber(progress.distToNext)
end

-- The cue a step deserves, or nil when it deserves none.
function Cues.CueFor(step)
    if type(step) ~= "table" then return nil end
    local kind = step.kind or "turn"
    if ARRIVAL_KINDS[kind] then return nil end       -- NAV_ARRIVED owns the arrival cue
    if TRANSPORT_KINDS[kind] then return "transport" end
    if QUIET_KINDS[kind] then return nil end
    return "turn"
end

local function resetJourneyState()
    Cues.announced = {}
    Cues.currentStep = nil
end

-- A transport action is announced as soon as it becomes the current instruction: the player has to
-- walk onto a boat or talk to a flight master, not steer through a corner.
local function onInstruction(_, step, isNew)
    if type(step) ~= "table" then return end
    Cues.currentStep = step
    if isNew == false then return end
    if Cues.CueFor(step) == "transport" then
        local index = stepIndex(step)
        -- Marked only after the sound plays. A cue that was off, or a fight, must not use the
        -- announcement up: the next progress or instruction can still play it.
        if not Cues.announced[index] and Cues:Play("transport") then
            Cues.announced[index] = true
        end
    end
end

-- A turn is announced by distance, so the sound arrives while there is still time to act on it.
local function onProgress(_, progress)
    if type(progress) ~= "table" then return end
    local step = progress.currentStep or Cues.currentStep
    if type(step) ~= "table" then return end
    Cues.currentStep = step
    if Cues.CueFor(step) ~= "turn" then return end
    local index = stepIndex(step)
    if Cues.announced[index] then return end
    local dist = distanceToStep(step, progress)
    if not dist or dist > Cues.TURN_YARDS then return end
    if Cues:Play("turn") then
        Cues.announced[index] = true
    end
end

local function onArrived(_, stopIndex, isFinal)
    Cues:Play("arrival")
    if isFinal ~= false then resetJourneyState() end
end

local function onCombat(_, inCombat)
    Cues.inCombat = inCombat and true or false
end

-------------------------------------------------------------------------------
-- Slash command: /cabbie cues on|off|volume <n>|turn|transport|arrival on|off|test|status
-------------------------------------------------------------------------------
local function printStatus()
    local c = cueSettings() or {}
    FGPS:Print(L["Audio cues: %s, volume %d."], c.enabled and L["on"] or L["off"], Cues:GetVolume())
    for _, name in ipairs(Cues.ORDER) do
        local sound = Cues:SoundName(name)
        FGPS:Print("  %s: %s (%s)", name, Cues:IsCueEnabled(name) and L["on"] or L["off"],
            sound or L["no sound available in this client"])
    end
end

local function isCueName(word)
    for _, name in ipairs(Cues.ORDER) do
        if name == word then return true end
    end
    return false
end

local function slashCues(args)
    local DB = FGPS.DB
    local word, rest = Util.Trim(args or ""):match("^(%S*)%s*(.-)$")
    word = Util.Lower(word or "")
    rest = Util.Lower(Util.Trim(rest or ""))
    if word == "" or word == "status" then
        printStatus()
    elseif word == "on" or word == "off" then
        DB:Set("cues.enabled", word == "on")
        FGPS:Print(word == "on" and L["Audio cues enabled."] or L["Audio cues disabled."])
    elseif word == "volume" then
        local n = tonumber(rest)
        if not n then
            FGPS:Print(L["Usage: /cabbie cues volume <0..100>"])
            return
        end
        DB:Set("cues.volume", Util.Clamp(math.floor(n + 0.5), 0, 100))
        FGPS:Print(L["Cue volume set to %d."], Cues:GetVolume())
    elseif isCueName(word) then
        if rest ~= "on" and rest ~= "off" then
            FGPS:Print(L["Usage: /cabbie cues %s on|off"], word)
            return
        end
        DB:Set("cues." .. word, rest == "on")
        FGPS:Print(L["Cue '%s' is now %s."], word, rest)
    elseif word == "test" then
        local any = false
        for _, name in ipairs(Cues.ORDER) do
            if Cues:Play(name, { force = true }) then any = true end
        end
        if not any then FGPS:Print(L["This client offers none of the sounds the cues use."]) end
    else
        FGPS:Print(L["Usage: /cabbie cues on|off|volume <n>|turn on|off|transport on|off|arrival on|off|test|status"])
    end
end

-------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------
function Cues:Init()
    if InCombatLockdown then self.inCombat = InCombatLockdown() and true or false end
    self.resolved = nil
    if not self.eventsBound then
        self.eventsBound = true
        local Events = FGPS.Events
        Events:Register("NAV_INSTRUCTION", onInstruction, self)
        Events:Register("ROUTE_PROGRESS", onProgress, self)
        Events:Register("ROUTE_STARTED", resetJourneyState, self)
        Events:Register("ROUTE_UPDATED", resetJourneyState, self)
        Events:Register("NAV_CANCELLED", resetJourneyState, self)
        Events:Register("NAV_ARRIVED", onArrived, self)
        Events:Register("COMBAT_STATE", onCombat, self)
        FGPS.Slash.Register("cues", slashCues,
            L["Audio cues instead of speech: on|off|volume <n>|turn|transport|arrival on|off|test"])
    end
    return self
end
