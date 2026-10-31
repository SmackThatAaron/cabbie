

































local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local floor, sqrt = math.floor, math.sqrt
local type, tostring, tonumber, ipairs, pairs, format = type, tostring, tonumber, ipairs, pairs, string.format
local tremove = table.remove

local Voice = {
    queue = {},
    current = nil,
    watchdog = nil,
    voices = nil,
    recentKeys = {},
    announced = {},
    currentStep = nil,
    lastProgress = nil,
    lastStepText = nil,
    inCombat = false,
    lastOffRoute = -math.huge,
    lastRecalc = -math.huge,
    lastDepartText = nil,
    rerouted = false,
    clipChannel = nil,
    state = "disabled",
    stats = nil,
    skippedKeys = {},
    failedClips = {},
}
FGPS.UI.Voice = Voice




function Voice:ResetStats()
    self.stats = { spoken = 0, dropped = 0, deduped = 0, expired = 0, clipsPlayed = 0, clipsFailed = 0,
                   clipsConfirmed = 0, clipsNotPlaying = 0, lastFailedClip = nil, lastFailure = nil, skipped = {} }
    self.skippedKeys, self.failedClips = {}, {}
end
Voice:ResetStats()

Voice.PRIORITY_ADVANCE, Voice.PRIORITY_TURN, Voice.PRIORITY_ALERT = 1, 2, 3
local QUEUE_CAP = 4
local DEFAULT_TTL = 8
local WATCHDOG_SECONDS = 6


local WATCHDOG_STARTED_SECONDS = 20
local ADVANCE_MOUNTED, ADVANCE_FOOT, TURN_YARDS = 150, 80, 25
local OFF_ROUTE_THROTTLE = 20
local RECALC_THROTTLE = 20
local RATE_MIN, RATE_MAX, VOLUME_MIN, VOLUME_MAX = -10, 10, 0, 100


local IMMEDIATE_KINDS = { depart = true, disembark = true, land = true }


local ARRIVAL_KINDS = { arrive = true, stop_arrive = true }

local DETAILED_KINDS = { continue = true, zone = true }




Voice.CLIP_SECONDS = {
    ["arrived"] = 1.93, ["boat_board"] = 1.06, ["boat_wrong"] = 2.60, ["continue"] = 0.81, ["continue_road"] = 1.38,
    ["disembark"] = 0.93, ["elevator_down"] = 1.44, ["elevator_leave"] = 1.11, ["elevator_ride"] = 1.13, ["elevator_up"] = 1.37,
    ["flight_land"] = 0.88, ["flight_take"] = 2.39, ["flying"] = 0.69, ["follow_ramp"] = 1.01, ["gate"] = 1.04,
    ["head_east"] = 0.80, ["head_north"] = 0.87, ["head_northeast"] = 1.02, ["head_northwest"] = 1.06, ["head_out"] = 0.73,
    ["head_south"] = 0.80, ["head_southeast"] = 1.03, ["head_southwest"] = 1.02, ["head_west"] = 0.80, ["hearthstone"] = 1.19,
    ["in_100"] = 1.46, ["in_150"] = 1.62, ["in_200"] = 1.42, ["in_25"] = 1.41, ["in_300"] = 1.54,
    ["in_50"] = 1.19, ["in_500"] = 1.53, ["in_80"] = 1.10, ["keep_left"] = 0.77, ["keep_right"] = 0.79,
    ["level_down"] = 1.54, ["level_up"] = 1.39, ["no_route"] = 0.99, ["now"] = 0.53,
    ["off_route"] = 1.65, ["open_ground"] = 1.88, ["portal"] = 0.99, ["ramp_down"] = 1.03, ["ramp_up"] = 0.83,
    ["ride_long"] = 1.30, ["route_cleared"] = 0.88, ["route_start"] = 0.98, ["route_updated"] = 1.01, ["sharp_left"] = 0.83,
    ["sharp_right"] = 0.84, ["stairs_down"] = 1.25, ["stairs_up"] = 1.11, ["stop_reached"] = 2.86, ["teleport"] = 1.17,
    ["tram_board"] = 1.03, ["tram_leave"] = 1.01, ["turn_left"] = 0.77, ["turn_right"] = 0.80, ["u_turn"] = 1.08,
    ["voice_test"] = 1.80, ["way_above"] = 1.36, ["way_below"] = 1.37, ["zeppelin_board"] = 1.15, ["zeppelin_wrong"] = 2.83,
    ["zone_enter"] = 1.28,
}
local CLIP_PATH = "Interface\\AddOns\\Cabbie\\Media\\Voice\\%s.ogg"
local CLIP_GAP = 0.12
local TURN_CLIPS = { turn_left = "turn_left", turn_right = "turn_right", turn_slight_left = "keep_left",
    turn_slight_right = "keep_right", turn_sharp_left = "sharp_left", turn_sharp_right = "sharp_right", uturn = "u_turn" }

local COMPASS_CLIPS = { "head_north", "head_northwest", "head_west", "head_southwest", "head_south", "head_southeast",
    "head_east", "head_northeast" }
local ADVANCE_YARDS = { 25, 50, 80, 100, 150, 200, 300, 500 }
local LEVEL_CLIPS = { stairs = { "stairs_up", "stairs_down" }, ramp = { "ramp_up", "ramp_down" } }
local BOARD_CLIPS = { boat = "boat_board", zeppelin = "zeppelin_board", tram = "tram_board" }


local KIND_CLIPS = { continue = "open_ground", ramp = "follow_ramp", zone = "zone_enter", fly = "flight_take",
    land = "flight_land", hearth = "hearthstone", cast = "teleport", arrive = "arrived", stop_arrive = "stop_reached" }


function Voice.ClipsFor(step)
    if type(step) ~= "table" then return nil end
    local kind = step.kind or "turn"
    local clip = TURN_CLIPS[kind] or KIND_CLIPS[kind]
    if kind == "depart" then
        clip = type(step.bearing) == "number" and COMPASS_CLIPS[floor(step.bearing / (2 * math.pi) * 8 + 0.5) % 8 + 1]
            or "head_out"
    elseif kind == "level" then
        local pair = LEVEL_CLIPS[step.climbForm] or { "level_up", "level_down" }
        clip = step.up and pair[1] or pair[2]
    elseif kind == "board" then
        if step.aboard or step.door then



            clip = nil
        elseif step.mode == "elevator" then
            clip = (step.way == "up" and "elevator_up") or (step.way == "down" and "elevator_down") or "elevator_ride"
        else
            clip = BOARD_CLIPS[step.mode] or "portal"
        end
    elseif kind == "disembark" then
        clip = (step.mode == "tram" and "tram_leave") or (step.mode == "elevator" and "elevator_leave") or "disembark"
    end
    local clips = clip and { clip } or nil

    if type(step.joined) == "table" then
        for i = 1, #step.joined do
            local more = Voice.ClipsFor(step.joined[i])
            if more then
                clips = clips or {}
                for j = 1, #more do clips[#clips + 1] = more[j] end
            end
        end
    end
    return clips
end


function Voice.AdvanceClip(yards)
    local best, gap = ADVANCE_YARDS[1], math.huge
    for _, y in ipairs(ADVANCE_YARDS) do
        local d = math.abs(y - (tonumber(yards) or 0))
        if d < gap then best, gap = y, d end
    end
    return "in_" .. best
end




local function voiceSettings()
    local s = FGPS.DB and FGPS.DB.settings
    return s and s.voice or nil
end

local function now()
    return GetTime and GetTime() or 0
end

function Voice:RefreshVoices()
    self.voices = nil
    if C_VoiceChat and C_VoiceChat.GetTtsVoices then
        local ok, list = pcall(C_VoiceChat.GetTtsVoices)
        if ok and type(list) == "table" then self.voices = list end
    end
    self.voices = self.voices or {}
    return self.voices
end

function Voice:GetVoices()
    if not self.voices then self:RefreshVoices() end
    return self.voices
end


function Voice:HasSystemVoice()
    return #self:GetVoices() > 0 and C_VoiceChat ~= nil and C_VoiceChat.SpeakText ~= nil
end


function Voice:UsesClips()
    local vs = voiceSettings()
    return not (vs and vs.systemVoice == true and self:HasSystemVoice())
end

function Voice:IsAvailable()
    if self:UsesClips() then return PlaySoundFile ~= nil end
    return self:HasSystemVoice()
end



function Voice:IsEnabled()
    if FGPS.Perf and FGPS.Perf.guidanceEnabled == false then return false end
    local vs = voiceSettings()
    return vs ~= nil and vs.enabled == true
end



function Voice:GetVoiceID()
    local voices = self:GetVoices()
    local vs = voiceSettings()
    local wanted = vs and tonumber(vs.voiceID) or nil
    if wanted then
        for _, v in ipairs(voices) do
            if v.voiceID == wanted then return wanted end
        end
    end
    local default
    if C_TTSSettings and C_TTSSettings.GetVoiceOptionID and Enum and Enum.TtsVoiceType then
        local ok, id = pcall(C_TTSSettings.GetVoiceOptionID, Enum.TtsVoiceType.Standard)
        if ok and type(id) == "number" then default = id end
    end
    if default then
        for _, v in ipairs(voices) do
            if v.voiceID == default then return default end
        end
    end
    if voices[1] then return voices[1].voiceID end
    return default or 0
end

function Voice:GetVoiceName(voiceID)
    voiceID = voiceID or self:GetVoiceID()
    for _, v in ipairs(self:GetVoices()) do
        if v.voiceID == voiceID then return v.name end
    end
    return tostring(voiceID)
end

function Voice:GetRate()
    local vs = voiceSettings()
    return Util.Clamp(tonumber(vs and vs.rate) or 0, RATE_MIN, RATE_MAX)
end

function Voice:GetVolume()
    local vs = voiceSettings()
    return Util.Clamp(tonumber(vs and vs.volume) or 70, VOLUME_MIN, VOLUME_MAX)
end

function Voice:GetVerbosity()
    local vs = voiceSettings()
    local v = vs and vs.verbosity
    if v == "minimal" or v == "detailed" then return v end
    return "normal"
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





local function clientMayBeFighting()
    return InCombatLockdown == nil or InCombatLockdown() == true
end


function Voice:IsBlockedByCombat()
    return self.inCombat and clientMayBeFighting() and combatPolicy() ~= "all"
end

local function setState(state)
    if Voice.state == state then return end
    Voice.state = state
    FGPS.Events:Fire("VOICE_STATE", state)
end

function Voice:GetState()
    return self.state
end

function Voice:UpdateState()
    if not self:IsEnabled() then
        setState("disabled")
    elseif not self:IsAvailable() then
        setState("unavailable")
    elseif self.current then
        setState("speaking")
    else
        setState("idle")
    end
end




local function insertSorted(queue, entry)
    local pos = #queue + 1
    for i = 1, #queue do
        if queue[i].priority < entry.priority then
            pos = i
            break
        end
    end
    table.insert(queue, pos, entry)
end

local function findKey(queue, key)
    for i = 1, #queue do
        if queue[i].key == key then return i end
    end
    return nil
end

local function stopWatchdog()
    if Voice.watchdog then
        Voice.watchdog:Cancel()
        Voice.watchdog = nil
    end
end

local function startWatchdog(seconds)
    stopWatchdog()
    local budget = seconds or WATCHDOG_SECONDS
    if C_Timer and C_Timer.NewTimer then
        Voice.watchdog = C_Timer.NewTimer(budget, function()
            Voice.watchdog = nil
            if Voice.current then
                FGPS.Log:Debug("Voice watchdog: no playback finished event after %d s", budget)
                Voice:OnUtteranceEnded()
            end
        end)
    end
end



local function skip(reason, key)
    local tag = reason .. "|" .. tostring(key)
    if not Voice.skippedKeys[tag] then
        Voice.skippedKeys[tag] = true
        local skipped = Voice.stats.skipped
        skipped[reason] = (skipped[reason] or 0) + 1
    end
    return false, reason
end


function Voice:Pump()
    if self.current then return end
    while #self.queue > 0 do
        local entry = tremove(self.queue, 1)
        if now() - entry.queuedAt > entry.ttl then
            self.stats.expired = self.stats.expired + 1
            skip("expired", entry.key)
        elseif (not entry.sample and not self:IsEnabled()) or not self:IsAvailable() or (self:UsesClips() and not entry.clips) then
            self.stats.dropped = self.stats.dropped + 1
            skip(not self:IsAvailable() and "unavailable" or (self:UsesClips() and not entry.clips) and "no clip" or "off", entry.key)
        elseif self:UsesClips() then
            self.current = entry
            entry.startedAt = now()
            entry.viaClips = true
            self.stats.spoken = self.stats.spoken + 1
            self.recentKeys[entry.key] = now()
            if entry.isStep then self.lastStepText = entry.text end
            Voice._playClip(entry, 1)
            self:UpdateState()
            return
        else
            self.current = entry
            entry.startedAt = now()
            local ok, err = pcall(C_VoiceChat.SpeakText, self:GetVoiceID(), entry.text, self:GetRate(), self:GetVolume(), false)
            if not ok then
                FGPS.Log:Error("SpeakText failed: %s", tostring(err))
                self.current = nil
            else
                self.stats.spoken = self.stats.spoken + 1
                self.recentKeys[entry.key] = now()
                if entry.isStep then self.lastStepText = entry.text end


                startWatchdog(entry.started and WATCHDOG_STARTED_SECONDS or nil)
                self:UpdateState()
                return
            end
        end
    end
    self:UpdateState()
end






local CLIP_CHANNELS = { "Master", "none" }

local function playFile(path)
    local first = Voice.clipChannel == "none" and 2 or 1
    local reason
    for i = first, #CLIP_CHANNELS do
        local channel = CLIP_CHANNELS[i]
        local ok, willPlay, handle
        if channel == "none" then
            ok, willPlay, handle = pcall(PlaySoundFile, path)
        else
            ok, willPlay, handle = pcall(PlaySoundFile, path, channel)
        end
        if ok and willPlay ~= false then
            Voice.clipChannel = channel
            return true, handle
        end
        reason = ok and "refused: the game answered false" or ("error: " .. tostring(willPlay):sub(1, 160))
    end
    return false, nil, reason
end



local CONFIRM_SECONDS = 0.2
local function confirmLater(handle)
    if type(handle) ~= "number" or not (C_Sound and C_Sound.IsPlaying and C_Timer and C_Timer.After) then return end
    C_Timer.After(CONFIRM_SECONDS, function()
        local ok, playing = pcall(C_Sound.IsPlaying, handle)
        if not ok or type(playing) ~= "boolean" then return end
        local stats = Voice.stats
        if playing then
            stats.clipsConfirmed = stats.clipsConfirmed + 1
        else
            stats.clipsNotPlaying = stats.clipsNotPlaying + 1
        end
    end)
end



function Voice._playClip(entry, i)
    local name = entry.clips[i]
    local played, handle, reason = playFile(format(CLIP_PATH, name))
    local stats = Voice.stats
    if played then
        Voice.clipHandle = handle
        stats.clipsPlayed = stats.clipsPlayed + 1
        confirmLater(handle)
    else
        stats.clipsFailed = stats.clipsFailed + 1
        stats.lastFailedClip, stats.lastFailure = name, reason
        if not Voice.failedClips[name] then
            Voice.failedClips[name] = true
            FGPS.Log:Info("Voice clip %s did not play (%s)", tostring(name), tostring(reason))
        end
    end
    local function nextClip()
        Voice.clipTimer = nil
        if Voice.current ~= entry then return end
        if entry.clips[i + 1] then Voice._playClip(entry, i + 1) else Voice:OnUtteranceEnded() end
    end
    if C_Timer and C_Timer.NewTimer then
        Voice.clipTimer = C_Timer.NewTimer((Voice.CLIP_SECONDS[name] or 1.5) + CLIP_GAP, nextClip)
    else
        nextClip()
    end
end

function Voice:OnUtteranceEnded()
    stopWatchdog()
    self.current = nil
    self:UpdateState()
    self:Pump()
end







function Voice:Speak(text, opts)
    if type(text) ~= "string" or text == "" then return false end
    opts = opts or {}
    local key = opts.key or text
    if not opts.sample and not self:IsEnabled() then return false, "off" end
    if not self:IsAvailable() then return skip("unavailable", key) end
    if self:UsesClips() and not opts.clips then return skip("no clip", key) end
    if self:IsBlockedByCombat() and not opts.force then
        self.stats.dropped = self.stats.dropped + 1
        return skip("combat", key)
    end
    local ttl = opts.ttl or DEFAULT_TTL
    local priority = opts.priority or Voice.PRIORITY_TURN
    if not opts.force then
        if self.current and self.current.key == key then
            self.stats.deduped = self.stats.deduped + 1
            return skip("duplicate", key)
        end
        local existing = findKey(self.queue, key)
        if existing then
            self.stats.deduped = self.stats.deduped + 1
            return skip("duplicate", key)
        end
        local last = self.recentKeys[key]
        if last and now() - last < ttl then
            self.stats.deduped = self.stats.deduped + 1
            return skip("duplicate", key)
        end
    end

    for k, t in pairs(self.recentKeys) do
        if now() - t > DEFAULT_TTL * 2 then self.recentKeys[k] = nil end
    end
    for i = #self.queue, 1, -1 do
        if now() - self.queue[i].queuedAt > self.queue[i].ttl then
            tremove(self.queue, i)
            self.stats.expired = self.stats.expired + 1
        end
    end
    local entry = { text = text, key = key, priority = priority, ttl = ttl, queuedAt = now(), isStep = opts.isStep == true,
                    clips = opts.clips, sample = opts.sample == true }
    if #self.queue >= QUEUE_CAP then


        local tail = self.queue[#self.queue]
        if tail.priority < priority then
            tremove(self.queue, #self.queue)
            self.stats.dropped = self.stats.dropped + 1
            skip("queue full", tail.key)
        else
            self.stats.dropped = self.stats.dropped + 1
            return skip("queue full", key)
        end
    end
    insertSorted(self.queue, entry)
    self:Pump()
    return true
end


function Voice:Mute()
    self.queue = {}
    stopWatchdog()
    local hadCurrent = self.current ~= nil
    local viaClips = hadCurrent and self.current.viaClips
    self.current = nil
    if self.clipTimer then
        self.clipTimer:Cancel()
        self.clipTimer = nil
    end
    if viaClips then
        if self.clipHandle and StopSound then pcall(StopSound, self.clipHandle) end
        self.clipHandle = nil
        self:UpdateState()
        return hadCurrent
    end


    if hadCurrent and C_VoiceChat and C_VoiceChat.StopSpeakingText then pcall(C_VoiceChat.StopSpeakingText) end
    self:UpdateState()
    return hadCurrent
end


function Voice:ClearQueue()
    self.queue = {}
end


function Voice:Repeat()
    local text
    local step = self.currentStep
    if type(step) == "table" then text = step.voiceText or step.text end
    if not text then
        local Navigator = FGPS.Navigator
        local progress = Navigator and Navigator.GetProgress and select(2, pcall(Navigator.GetProgress, Navigator)) or nil
        local cur = type(progress) == "table" and progress.currentStep or nil
        if type(cur) == "table" then
            text = cur.voiceText or cur.text


            step = step or cur
        end
    end
    text = text or self.lastStepText
    if not text then
        FGPS:Print(L["There is no instruction to repeat."])
        local Navigator = FGPS.Navigator
        if not (Navigator and Navigator.GetRoute and Navigator:GetRoute()) then
            self:Speak(L["No route set."], { priority = Voice.PRIORITY_ALERT, key = "no_route", force = true, clips = { "no_route" } })
        end
        return false
    end
    local ok, reason = self:Speak(text, { priority = Voice.PRIORITY_ALERT, key = "repeat:" .. tostring(now()), force = true, isStep = true,
                              clips = Voice.ClipsFor(step) })
    if not ok and reason == "no clip" then
        FGPS:Print(L["That instruction has no recorded voice."])
    end
    return ok
end




function Voice:PlaySample()
    return self:Speak(L["Cabbie voice guidance is working."], { priority = Voice.PRIORITY_ALERT, key = "sample:" .. tostring(now()),
                                                                force = true, sample = true, clips = { "voice_test" } })
end

function Voice:QueueLength()
    return #self.queue
end


local SOUND_CVARS = { allSound = "Sound_EnableAllSound", masterVolume = "Sound_MasterVolume",
                      effects = "Sound_EnableSFX", effectsVolume = "Sound_SFXVolume" }

local function soundSettings()
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    if type(get) ~= "function" then return nil end
    local out = {}
    for field, cvar in pairs(SOUND_CVARS) do
        local ok, value = pcall(get, cvar)
        if ok and type(value) == "string" then out[field] = value end
    end
    return out
end




function Voice:Report()
    local vs = voiceSettings() or {}
    local s = self.stats
    local skipped = {}
    for reason, n in pairs(s.skipped) do skipped[reason] = n end
    return {
        enabled = vs.enabled == true,
        recorded = self:UsesClips(),
        verbosity = self:GetVerbosity(),
        gameVoices = #self:GetVoices(),
        spoken = s.spoken,
        clipsPlayed = s.clipsPlayed,
        clipsFailed = s.clipsFailed,
        lastFailedClip = s.lastFailedClip,
        lastFailure = s.lastFailure,
        clipsConfirmed = s.clipsConfirmed,
        clipsNotPlaying = s.clipsNotPlaying,
        channel = self.clipChannel,
        skipped = skipped,
        sound = soundSettings(),
    }
end




local function roundTo(value, step)
    return floor(value / step + 0.5) * step
end


function Voice.SpokenDistance(yards)
    local s = FGPS.DB and FGPS.DB.settings
    if s and s.units == "metric" then
        local metres = roundTo(yards * FGPS.Const.METERS_PER_YARD, 10)
        if metres < 1000 then return format(L["%d meters"], metres) end
        return format(L["%.1f kilometers"], metres / 1000)
    end
    return format(L["%d yards"], roundTo(yards, 10))
end

local function stepText(step)
    if type(step) ~= "table" then return nil end
    local text = step.voiceText or step.text or step.shortText
    if type(text) ~= "string" or text == "" then return nil end
    return text
end






local function fullClips(step)
    local clips = Voice.ClipsFor(step)
    if not clips or Voice:GetVerbosity() ~= "detailed" then return clips end
    if type(step.guessVoice) == "string" then clips[#clips + 1] = "open_ground" end
    if type(step.zoneVoice) == "string" then clips[#clips + 1] = "zone_enter" end
    return clips
end

local function fullText(step, text)
    if Voice:GetVerbosity() ~= "detailed" then return text end
    if type(step.guessVoice) == "string" then text = text .. " " .. step.guessVoice end
    if type(step.zoneVoice) == "string" then text = text .. " " .. step.zoneVoice end
    return text
end

local function lowerFirst(text)
    local first = text:sub(1, 1)
    if first:match("%u") then return Util.Lower(first) .. text:sub(2) end
    return text
end

local function stepKey(step, stage)
    return format("step:%s:%s", tostring(step.index or step.legIndex or "?"), stage)
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

local function advanceDistance()
    if IsMounted and IsMounted() then return ADVANCE_MOUNTED end
    return ADVANCE_FOOT
end




local function announcedFor(step)
    local index = step.index or step.legIndex or 0
    local rec = Voice.announced[index]
    if not rec then
        rec = {}
        Voice.announced[index] = rec
    end
    return rec
end




function Voice:EvaluateStep(progress)
    if type(progress) == "table" and progress.state == "paused" then return end
    local step = self.currentStep or (type(progress) == "table" and progress.currentStep) or nil
    if type(step) ~= "table" or not self:IsEnabled() then return end
    local kind = step.kind or "turn"
    if IMMEDIATE_KINDS[kind] or ARRIVAL_KINDS[kind] then return end
    local verbosity = self:GetVerbosity()
    if DETAILED_KINDS[kind] and verbosity ~= "detailed" then return end
    local text = stepText(step)
    if not text then return end
    local dist = distanceToStep(step, progress)
    if not dist then return end
    local rec = announcedFor(step)
    if dist <= TURN_YARDS then
        if not rec.turn then


            if self:Speak(fullText(step, text), { priority = Voice.PRIORITY_TURN, key = stepKey(step, "turn"), isStep = true,
                                                 clips = fullClips(step) }) then
                rec.turn = true
                rec.advance = true
            end
        end
    elseif dist <= advanceDistance() then
        if not rec.advance and verbosity ~= "minimal" then
            local phrase = format(L["In %s, %s"], Voice.SpokenDistance(dist), lowerFirst(text))
            local clips = Voice.ClipsFor(step)
            if clips then table.insert(clips, 1, Voice.AdvanceClip(dist)) end
            if self:Speak(phrase, { priority = Voice.PRIORITY_ADVANCE, key = stepKey(step, "advance"), isStep = true,
                                    clips = clips }) then
                rec.advance = true
            end
        end
    end
end

local function onInstruction(_, step, isNew)
    if type(step) ~= "table" then return end
    Voice.currentStep = step
    local rerouted = Voice.rerouted
    Voice.rerouted = false
    local text = stepText(step)
    if not text then return end
    if isNew == false then


        local kind = step.kind or "turn"
        if not (DETAILED_KINDS[kind] and Voice:GetVerbosity() ~= "detailed") then
            Voice:Speak(fullText(step, text), { priority = Voice.PRIORITY_TURN, key = stepKey(step, "reannounce"), isStep = true,
                                                clips = fullClips(step) })
        end
        return
    end
    local kind = step.kind or "turn"
    if IMMEDIATE_KINDS[kind] then
        local rec = announcedFor(step)
        if not rec.turn then
            if kind == "depart" then


                local same = rerouted and text == Voice.lastDepartText
                Voice.lastDepartText = text
                if same then
                    rec.turn, rec.advance = true, true
                    return
                end
            end
            if Voice:Speak(text, { priority = Voice.PRIORITY_TURN, key = stepKey(step, "turn"), isStep = true,
                                   clips = Voice.ClipsFor(step) }) then
                rec.turn, rec.advance = true, true
            end
        end
        return
    end
    if Voice.lastProgress then Voice:EvaluateStep(Voice.lastProgress) end
end

local function onProgress(_, progress)
    Voice.lastProgress = progress
    if type(progress) == "table" and progress.currentStep and Voice.currentStep
        and progress.currentStep ~= Voice.currentStep
        and (progress.currentStep.index or 0) > (Voice.currentStep.index or 0) then

        Voice.currentStep = progress.currentStep
    end
    Voice:EvaluateStep(progress)
end






local function resetJourneyState()
    Voice.announced = {}
    Voice.currentStep = nil
    Voice.lastProgress = nil
    Voice.recentKeys = {}
    Voice.skippedKeys = {}
    Voice.lastRecalc = -math.huge
    Voice.lastDepartText = nil
    Voice.rerouted = false
    Voice:ClearQueue()
end

local function onRouteStarted(_, route)
    resetJourneyState()
end

local function onRouteUpdated(_, route, reason)
    Voice.announced = {}
    Voice.currentStep = nil
    Voice.recentKeys = {}
    Voice.skippedKeys = {}
    Voice.rerouted = true
    Voice:ClearQueue()
end

local function onCancelled(_, reason)
    resetJourneyState()
    Voice.lastStepText = nil



    if reason == "user" then
        Voice:Speak(L["Route cleared."], { priority = Voice.PRIORITY_ALERT, key = "route_cleared", force = true, clips = { "route_cleared" } })
    end
end

local function onArrived(_, stopIndex, isFinal)
    local text
    if isFinal == false then
        text = format(L["Arrived at stop %d."], tonumber(stopIndex) or 0)
    else
        text = L["You have arrived at your destination."]
    end
    Voice:Speak(text, { priority = Voice.PRIORITY_ALERT, key = "arrived:" .. tostring(stopIndex or "final"),
                        clips = { isFinal == false and "stop_reached" or "arrived" } })
    if isFinal ~= false then
        Voice.announced = {}
        Voice.currentStep = nil
    end
end





local function onRecalcDone(_, route, err, kept)
    if not route or kept == "kept" then return end
    local t = now()
    if t - Voice.lastRecalc < RECALC_THROTTLE then return end


    if Voice:Speak(L["Route updated."], { priority = Voice.PRIORITY_ALERT, key = "recalc", clips = { "route_updated" } }) then
        Voice.lastRecalc = t
    end
end

local function onOffRoute()
    local t = now()
    if t - Voice.lastOffRoute < OFF_ROUTE_THROTTLE then return end
    if Voice:Speak(L["Off route, recalculating."], { priority = Voice.PRIORITY_ALERT, key = "offroute", clips = { "off_route" } }) then
        Voice.lastOffRoute = t
    end
end

local function onCombat(_, inCombat)
    Voice.inCombat = inCombat and true or false
    if Voice.inCombat and combatPolicy() ~= "all" then

        Voice:Mute()
    end
end

local function onSettingsChanged(_, key)
    if key == "voice.enabled" or key == "perf.guidanceEnabled" or key == "*" then
        if not Voice:IsEnabled() then Voice:Mute() end
        Voice:UpdateState()
    elseif key == "voice.voiceID" or key == "voice.systemVoice" then
        Voice:UpdateState()
    end
end






local function onTtsEvent(event, arg1, arg2)
    if event == "VOICE_CHAT_TTS_VOICES_UPDATE" then
        Voice:RefreshVoices()
        Voice:UpdateState()
        return
    end
    local current = Voice.current

    if not current or current.viaClips then return end
    if event == "VOICE_CHAT_TTS_SPEAK_TEXT_UPDATE" then



        if type(arg2) == "number" and current.utteranceID == nil then
            current.utteranceID = arg2
        end
        return
    end
    local ours = current.utteranceID
    if ours ~= nil and type(arg1) == "number" and arg1 ~= ours then
        return
    end
    if event == "VOICE_CHAT_TTS_PLAYBACK_STARTED" then
        current.started = true
        startWatchdog(WATCHDOG_STARTED_SECONDS)
    elseif event == "VOICE_CHAT_TTS_PLAYBACK_FINISHED" or event == "VOICE_CHAT_TTS_PLAYBACK_FAILED" then
        if event == "VOICE_CHAT_TTS_PLAYBACK_FAILED" then
            FGPS.Log:Warn("Text-to-speech playback failed (status %s)", tostring(arg2))
        end
        Voice:OnUtteranceEnded()
    end
end




local function printStatus()
    local vs = voiceSettings() or {}
    if Voice:UsesClips() then


        FGPS:Print(L["Voice guidance: %s (%s). Verbosity %s, %d queued."],
            vs.enabled and L["on"] or L["off"],
            L["Cabbie's recorded voice"],
            Voice:GetVerbosity(), #Voice.queue)
        FGPS:Print(L["Rate and volume apply to the game's voice only."])
    else
        FGPS:Print(L["Voice guidance: %s (%s). Voice %s, rate %d, volume %d, verbosity %s, %d queued."],
            vs.enabled and L["on"] or L["off"],
            L["text-to-speech available"],
            Voice:GetVoiceName(), Voice:GetRate(), Voice:GetVolume(), Voice:GetVerbosity(), #Voice.queue)
    end
end

local function slashVoice(args)
    local DB = FGPS.DB
    local word, rest = Util.Trim(args):match("^(%S*)%s*(.-)$")
    word = Util.Lower(word or "")
    if word == "" or word == "status" then
        printStatus()
    elseif word == "on" or word == "off" then
        DB:Set("voice.enabled", word == "on")
        if word == "on" and not Voice:IsAvailable() then
            FGPS:Print(L["Voice guidance enabled, but this client reports no text-to-speech voices."])
        else
            FGPS:Print(word == "on" and L["Voice guidance enabled."] or L["Voice guidance disabled."])
        end
    elseif word == "mute" then
        Voice:Mute()
        FGPS:Print(L["Voice guidance muted; queued speech cleared."])
    elseif word == "repeat" then
        Voice:Repeat()
    elseif word == "list" then
        local voices = Voice:RefreshVoices()
        if #voices == 0 then
            FGPS:Print(L["No text-to-speech voices are installed."])
        else
            for _, v in ipairs(voices) do FGPS:Print("  %d: %s", v.voiceID, tostring(v.name)) end
        end
    elseif word == "voice" then
        local id = tonumber(rest)
        if not id then
            FGPS:Print(L["Usage: /cabbie voice voice <id> (see /cabbie voice list)"])
            return
        end
        local found = false
        for _, v in ipairs(Voice:GetVoices()) do if v.voiceID == id then found = true end end
        if not found then
            FGPS:Print(L["Voice %d is not installed (see /cabbie voice list)."], id)
            return
        end
        DB:Set("voice.voiceID", id)
        FGPS:Print(L["Voice set to %s."], Voice:GetVoiceName(id))
    elseif word == "rate" then
        local n = tonumber(rest)

        if not n or n ~= n then FGPS:Print(L["Usage: /cabbie voice rate <-10..10>"]) return end
        DB:Set("voice.rate", Util.Clamp(floor(n + 0.5), RATE_MIN, RATE_MAX))
        FGPS:Print(L["Speech rate set to %d."], Voice:GetRate())
        if Voice:UsesClips() then FGPS:Print(L["Rate and volume apply to the game's voice only."]) end
    elseif word == "volume" then
        local n = tonumber(rest)
        if not n or n ~= n then FGPS:Print(L["Usage: /cabbie voice volume <0..100>"]) return end
        DB:Set("voice.volume", Util.Clamp(floor(n + 0.5), VOLUME_MIN, VOLUME_MAX))
        FGPS:Print(L["Speech volume set to %d."], Voice:GetVolume())
        if Voice:UsesClips() then FGPS:Print(L["Rate and volume apply to the game's voice only."]) end
    elseif word == "verbosity" then
        local level = Util.Lower(Util.Trim(rest))
        if level ~= "minimal" and level ~= "normal" and level ~= "detailed" then
            FGPS:Print(FGPS.Util.EscapeBars(L["Usage: /cabbie voice verbosity minimal|normal|detailed"]))
            return
        end
        DB:Set("voice.verbosity", level)
        FGPS:Print(L["Voice verbosity set to %s."], level)
    elseif word == "test" then
        if not Voice:IsEnabled() then
            local vs = voiceSettings()
            if vs and vs.enabled == true then
                FGPS:Print(L["Guidance work is switched off for a measurement; type /cabbie perf toggle first."])
            else
                FGPS:Print(L["Voice guidance is off; type /cabbie voice on first."])
            end
            return
        end
        Voice:Speak(L["Cabbie voice guidance is working."], { priority = Voice.PRIORITY_ALERT, key = "test:" .. tostring(now()), force = true,
                                                              clips = { "voice_test" } })
    else
        FGPS:Print(FGPS.Util.EscapeBars(L["Usage: /cabbie voice on|off|mute|repeat|list|voice <id>|rate <n>|volume <n>|verbosity <level>|test"]))
    end
end




function Voice:Init()
    if InCombatLockdown then self.inCombat = InCombatLockdown() and true or false end
    self:RefreshVoices()
    if not self.eventsBound then
        self.eventsBound = true
        local Events = FGPS.Events
        Events:Register("NAV_INSTRUCTION", onInstruction, self)
        Events:Register("ROUTE_PROGRESS", onProgress, self)
        Events:Register("ROUTE_STARTED", onRouteStarted, self)
        Events:Register("ROUTE_UPDATED", onRouteUpdated, self)
        Events:Register("NAV_CANCELLED", onCancelled, self)
        Events:Register("NAV_ARRIVED", onArrived, self)
        Events:Register("NAV_RECALC_DONE", onRecalcDone, self)
        Events:Register("NAV_OFF_ROUTE", onOffRoute, self)
        Events:Register("COMBAT_STATE", onCombat, self)


        Events:Register("WORLD_ENTERED", function()
            if not InCombatLockdown then return end
            local fighting = InCombatLockdown() and true or false
            if fighting ~= Voice.inCombat then onCombat(nil, fighting) end
        end, self)
        Events:Register("SETTINGS_CHANGED", onSettingsChanged, self)
        Events:RegisterWoW("VOICE_CHAT_TTS_SPEAK_TEXT_UPDATE", onTtsEvent, self)
        Events:RegisterWoW("VOICE_CHAT_TTS_PLAYBACK_STARTED", onTtsEvent, self)
        Events:RegisterWoW("VOICE_CHAT_TTS_PLAYBACK_FINISHED", onTtsEvent, self)
        Events:RegisterWoW("VOICE_CHAT_TTS_PLAYBACK_FAILED", onTtsEvent, self)
        Events:RegisterWoW("VOICE_CHAT_TTS_VOICES_UPDATE", onTtsEvent, self)
        FGPS.Slash.Register("voice", slashVoice, L["Voice guidance: on|off|mute|repeat|list|voice <id>|rate <n>|volume <n>"])
    end
    self:UpdateState()
end
