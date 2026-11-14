-- Cabbie/UI/WhatsNew.lua
-- The update window: pops up once per version when an existing Cabbie install updates (and opens
-- any time via /cabbie whatsnew, /cabbie news, or the Welcome window's "What's New..." button).
-- Shows a live visual HUD stage built from Cabbie's own textures so the player can see how the 3D
-- road beacon, turn arrow, step list, voice banner and combat visibility look, hover any option to
-- preview it, and toggle preferences directly without hunting through Settings.
local ADDON_NAME, FGPS = ...

local L = FGPS.L
local format = string.format
local ipairs, pcall, sin, tostring, type = ipairs, pcall, math.sin, tostring, type
local TWO_PI = 2 * math.pi

local MEDIA = "Interface\\AddOns\\" .. (ADDON_NAME or "Cabbie") .. "\\Media\\"
local TEX_DOT = MEDIA .. "dot"
local TEX_RING = MEDIA .. "place_ring"
local TEX_STOP_RING = MEDIA .. "stop_ring"
local TEX_TURN = MEDIA .. "turn_mark"
local TEX_ARROW = MEDIA .. "arrow_guide"

local WhatsNew = {
    ready = false,
    loginArmed = false,
    loginWaits = false,
    loginTimer = nil,
    hoveredKey = nil,
    clock = 0,
}
FGPS.UI = FGPS.UI or {}
FGPS.UI.WhatsNew = WhatsNew

WhatsNew.WIDTH = 520
WhatsNew.HEIGHT = 532
WhatsNew.STAGE_HEIGHT = 136
WhatsNew.GAP = 8
WhatsNew.LOGIN_DELAY = 2.5

local SYNC_KEYS = {
    ["roadBeacon"] = true,
    ["callout.enabled"] = true,
    ["combatMode"] = true,
    ["voice.enabled"] = true,
    ["routeBlock.enabled"] = true,
    ["units"] = true,
    ["textSize"] = true,
    ["*"] = true,
}

local function Look()
    return FGPS.UI.Look
end

local function inFight()
    return InCombatLockdown and InCombatLockdown() and true or false
end

local function mapVisible()
    return type(WorldMapFrame) == "table" and WorldMapFrame.IsVisible and WorldMapFrame:IsVisible() and true or false
end

local function setupVisible()
    local Setup = FGPS.UI and FGPS.UI.Setup
    return Setup and Setup.IsShown and Setup:IsShown() and true or false
end

local function text(parent, role)
    local fs = Look().FontString(parent, "OVERLAY", role)
    if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
    if fs.SetJustifyV then fs:SetJustifyV("TOP") end
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    return fs
end

local function windowHeight()
    return WhatsNew.HEIGHT + 30 * Look().TextSizeDelta()
end

local function applyVerticalFade(tex, r, g, b, botAlpha)
    tex:SetVertexColor(r, g, b, botAlpha)
    if type(CreateColor) == "function" and type(tex.SetGradient) == "function" then
        local ok = pcall(tex.SetGradient, tex, "VERTICAL", CreateColor(r, g, b, botAlpha), CreateColor(r, g, b, 0))
        if ok then tex:SetVertexColor(1, 1, 1, 1) end
    end
end

local function combatVisibleOn()
    local DB = FGPS.DB
    local mode = DB and DB.Get and DB:Get("combatMode") or "visuals_only"
    return mode ~= "hide_all"
end

local function setCombatVisible(on)
    local DB = FGPS.DB
    if not (DB and DB.Set and DB.Get) then return end
    if on then
        local cur = DB:Get("combatMode")
        if cur == "hide_all" or type(cur) ~= "string" then
            DB:Set("combatMode", "visuals_only")
        end
    else
        DB:Set("combatMode", "hide_all")
    end
end

-- True when an existing Cabbie account (one that has already seen first-time setup or the login
-- guide) has not yet been shown What's New for FGPS.version. A brand-new install sees Setup first,
-- which stamps whatsNewVersion so the player never gets two welcome popups on their first login.
function WhatsNew.NeedsPopup()
    local account = FGPS.DB and FGPS.DB.account
    if type(account) ~= "table" then return false end
    if not (account.setupComplete == true or account.guideSeenAtLogin == true) then return false end
    local ver = FGPS.version
    if type(ver) ~= "string" or ver == "" then return false end
    return account.whatsNewVersion ~= ver
end

function WhatsNew:MarkSeen()
    local account = FGPS.DB and FGPS.DB.account
    local ver = FGPS.version
    if account and type(ver) == "string" and ver ~= "" then
        account.whatsNewVersion = ver
    end
end

local function makeBorder(frame, r, g, b, a)
    local edges = {}
    local specs = {
        { "TOPLEFT", "TOPRIGHT", 0, 1 },
        { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, 0 },
        { "TOPRIGHT", "BOTTOMRIGHT", 1, 0 },
    }
    for i, s in ipairs(specs) do
        local tex = frame:CreateTexture(nil, "BORDER")
        tex:SetColorTexture(r, g, b, a)
        tex:SetPoint(s[1], frame, s[1], 0, 0)
        tex:SetPoint(s[2], frame, s[2], 0, 0)
        if s[3] > 0 then tex:SetWidth(s[3]) end
        if s[4] > 0 then tex:SetHeight(s[4]) end
        edges[i] = tex
    end
    return edges
end

local function buildStage(parent)
    local look = Look()
    local stage = CreateFrame("Frame", nil, parent)
    stage:SetHeight(WhatsNew.STAGE_HEIGHT)
    makeBorder(stage, 0.72, 0.58, 0.24, 0.65)

    -- Twilight sky, warm horizon band, grass ground and 3-step road perspective.
    local sky = stage:CreateTexture(nil, "BACKGROUND", nil, 0)
    sky:SetPoint("TOPLEFT", stage, "TOPLEFT", 1, -1)
    sky:SetPoint("TOPRIGHT", stage, "TOPRIGHT", -1, -1)
    sky:SetHeight(64)
    sky:SetColorTexture(0.06, 0.09, 0.16, 0.96)

    local horizon = stage:CreateTexture(nil, "BACKGROUND", nil, 1)
    horizon:SetPoint("TOPLEFT", sky, "BOTTOMLEFT", 0, 10)
    horizon:SetPoint("TOPRIGHT", sky, "BOTTOMRIGHT", 0, 10)
    horizon:SetHeight(16)
    horizon:SetColorTexture(0.22, 0.18, 0.11, 0.55)

    local ground = stage:CreateTexture(nil, "BACKGROUND", nil, 0)
    ground:SetPoint("TOPLEFT", sky, "BOTTOMLEFT", 0, 0)
    ground:SetPoint("BOTTOMRIGHT", stage, "BOTTOMRIGHT", -1, 1)
    ground:SetColorTexture(0.07, 0.10, 0.07, 0.96)

    local roadFar = stage:CreateTexture(nil, "BACKGROUND", nil, 2)
    roadFar:SetPoint("TOP", sky, "BOTTOM", 0, -2)
    roadFar:SetSize(46, 16)
    roadFar:SetColorTexture(0.24, 0.20, 0.14, 0.78)

    local roadMid = stage:CreateTexture(nil, "BACKGROUND", nil, 2)
    roadMid:SetPoint("TOP", roadFar, "BOTTOM", 0, 0)
    roadMid:SetSize(88, 22)
    roadMid:SetColorTexture(0.27, 0.22, 0.15, 0.85)

    local roadNear = stage:CreateTexture(nil, "BACKGROUND", nil, 2)
    roadNear:SetPoint("TOP", roadMid, "BOTTOM", 0, 0)
    roadNear:SetPoint("BOTTOM", stage, "BOTTOM", 0, 20)
    roadNear:SetWidth(148)
    roadNear:SetColorTexture(0.30, 0.24, 0.16, 0.90)

    -- Subtle 50 yd destination arrival ring further up the road.
    local stopRing = stage:CreateTexture(nil, "ARTWORK", nil, 0)
    stopRing:SetTexture(TEX_STOP_RING)
    stopRing:SetSize(16, 16)
    stopRing:SetPoint("CENTER", roadFar, "TOP", 26, -3)
    stopRing:SetVertexColor(0.95, 0.86, 0.52, 0.55)

    -- 1. 3D Road beacon preview (beam + halo + ring + turn mark + distance + cue).
    local beacon = CreateFrame("Frame", nil, stage)
    beacon:SetSize(30, 30)
    beacon:SetPoint("CENTER", stage, "CENTER", 0, -6)

    local beamGlow = beacon:CreateTexture(nil, "BACKGROUND", nil, 3)
    beamGlow:SetTexture(TEX_DOT)
    beamGlow:SetTexCoord(0, 1, 0, 0.5)
    beamGlow:SetBlendMode("ADD")
    beamGlow:SetPoint("BOTTOM", beacon, "CENTER", 0, 3)
    beamGlow:SetSize(16, 68)
    applyVerticalFade(beamGlow, 1.0, 0.84, 0.30, 0.34)

    local beamCore = beacon:CreateTexture(nil, "ARTWORK", nil, 1)
    beamCore:SetTexture(TEX_DOT)
    beamCore:SetTexCoord(0, 1, 0, 0.5)
    beamCore:SetBlendMode("ADD")
    beamCore:SetPoint("BOTTOM", beacon, "CENTER", 0, 3)
    beamCore:SetSize(4, 60)
    applyVerticalFade(beamCore, 1.0, 0.97, 0.80, 0.68)

    local halo = beacon:CreateTexture(nil, "BACKGROUND", nil, 2)
    halo:SetTexture(TEX_DOT)
    halo:SetBlendMode("ADD")
    halo:SetPoint("CENTER", beacon, "CENTER", 0, 0)
    halo:SetSize(38, 38)
    halo:SetVertexColor(1.0, 0.86, 0.36, 0.24)

    local ring = beacon:CreateTexture(nil, "BORDER", nil, 2)
    ring:SetTexture(TEX_RING)
    ring:SetPoint("CENTER", beacon, "CENTER", 0, 0)
    ring:SetSize(26, 26)
    ring:SetVertexColor(1.0, 0.84, 0.36, 0.95)

    local icon = beacon:CreateTexture(nil, "ARTWORK", nil, 2)
    icon:SetTexture(TEX_TURN)
    icon:SetPoint("CENTER", beacon, "CENTER", 0, 0)
    icon:SetSize(19, 19)
    icon:SetVertexColor(1.0, 0.90, 0.42, 1.0)

    local distText = look.FontString(beacon, "OVERLAY", "mapLabel")
    distText:SetPoint("TOP", beacon, "BOTTOM", 0, -1)
    distText:SetTextColor(1.0, 0.90, 0.46, 1)

    local cueText = look.FontString(beacon, "OVERLAY", "rowSmall")
    cueText:SetPoint("TOP", distText, "BOTTOM", 0, -1)
    cueText:SetTextColor(1.0, 0.86, 0.38, 1)
    cueText:SetText(L.WHATSNEW_STAGE_TURN)

    -- 2. Top-screen Turn arrow preview.
    local arrowHolder = CreateFrame("Frame", nil, stage)
    arrowHolder:SetSize(34, 34)
    arrowHolder:SetPoint("TOP", stage, "TOP", 0, -6)

    local arrowTex = arrowHolder:CreateTexture(nil, "OVERLAY", nil, 2)
    arrowTex:SetTexture(TEX_ARROW)
    arrowTex:SetAllPoints(arrowHolder)
    if arrowTex.SetRotation then arrowTex:SetRotation(0.38) end

    -- 3. Combat visibility pill (top-left).
    local combatPill = CreateFrame("Frame", nil, stage)
    combatPill:SetPoint("TOPLEFT", stage, "TOPLEFT", 8, -7)
    combatPill:SetSize(156, 18)
    local combatBg = combatPill:CreateTexture(nil, "ARTWORK", nil, 0)
    combatBg:SetAllPoints(combatPill)
    combatBg:SetColorTexture(0.05, 0.06, 0.08, 0.78)
    local combatText = look.FontString(combatPill, "OVERLAY", "rowSmall")
    combatText:SetPoint("LEFT", combatPill, "LEFT", 5, 0)

    -- 4. Voice guidance pill (bottom-left above caption).
    local voicePill = CreateFrame("Frame", nil, stage)
    voicePill:SetPoint("BOTTOMLEFT", stage, "BOTTOMLEFT", 8, 23)
    voicePill:SetSize(176, 18)
    local voiceBg = voicePill:CreateTexture(nil, "ARTWORK", nil, 0)
    voiceBg:SetAllPoints(voicePill)
    voiceBg:SetColorTexture(0.14, 0.11, 0.04, 0.85)
    local voiceText = look.FontString(voicePill, "OVERLAY", "rowSmall")
    voiceText:SetPoint("LEFT", voicePill, "LEFT", 5, 0)
    voiceText:SetTextColor(1.0, 0.86, 0.38, 1)
    voiceText:SetText(L.WHATSNEW_STAGE_VOICE)

    -- 5. Step list mini-card (right side).
    local stepsCard = CreateFrame("Frame", nil, stage)
    stepsCard:SetPoint("TOPRIGHT", stage, "TOPRIGHT", -8, -8)
    stepsCard:SetSize(134, 38)
    local stepsBg = stepsCard:CreateTexture(nil, "ARTWORK", nil, 0)
    stepsBg:SetAllPoints(stepsCard)
    stepsBg:SetColorTexture(0.05, 0.06, 0.08, 0.82)
    makeBorder(stepsCard, 0.55, 0.46, 0.22, 0.55)
    local stepsHead = look.FontString(stepsCard, "OVERLAY", "rowSmall")
    stepsHead:SetPoint("TOPLEFT", stepsCard, "TOPLEFT", 5, -4)
    stepsHead:SetTextColor(1.0, 0.82, 0.0, 1)
    stepsHead:SetText(L.WHATSNEW_STAGE_STEPS_HEAD)
    local stepsLine = look.FontString(stepsCard, "OVERLAY", "rowSmall")
    stepsLine:SetPoint("TOPLEFT", stepsHead, "BOTTOMLEFT", 0, -2)
    stepsLine:SetTextColor(0.92, 0.92, 0.92, 1)
    stepsLine:SetText(L.WHATSNEW_STAGE_STEPS_LINE)

    -- Bottom caption bar.
    local captionBg = stage:CreateTexture(nil, "ARTWORK", nil, 1)
    captionBg:SetPoint("BOTTOMLEFT", stage, "BOTTOMLEFT", 1, 1)
    captionBg:SetPoint("BOTTOMRIGHT", stage, "BOTTOMRIGHT", -1, 1)
    captionBg:SetHeight(18)
    captionBg:SetColorTexture(0.03, 0.04, 0.06, 0.88)

    local caption = look.FontString(stage, "OVERLAY", "rowSmall")
    caption:SetPoint("LEFT", captionBg, "LEFT", 7, 0)
    caption:SetPoint("RIGHT", captionBg, "RIGHT", -7, 0)
    if caption.SetJustifyH then caption:SetJustifyH("LEFT") end
    if caption.SetWordWrap then caption:SetWordWrap(false) end

    stage.Beacon = beacon
    stage.BeaconHalo = halo
    stage.BeaconDist = distText
    stage.Arrow = arrowHolder
    stage.CombatPill = combatPill
    stage.CombatText = combatText
    stage.VoicePill = voicePill
    stage.StepsCard = stepsCard
    stage.Caption = caption
    return stage
end

local HOVER_LABELS = {
    beacon = "WHATSNEW_BEACON",
    arrow  = "WHATSNEW_ARROW",
    combat = "WHATSNEW_COMBAT",
    voice  = "WHATSNEW_VOICE",
    steps  = "WHATSNEW_STEPS",
}

-- Updates checkboxes and the live visual stage from the current settings + hover state.
function WhatsNew:Sync()
    local win = self.frame
    local DB = FGPS.DB
    if not (win and DB and DB.Get) then return end

    local beaconOn = DB:Get("roadBeacon") == true
    local arrowOn = DB:Get("callout.enabled") == true
    local combatOn = combatVisibleOn()
    local voiceOn = DB:Get("voice.enabled") == true
    local stepsOn = DB:Get("routeBlock.enabled") == true

    win.BeaconCheck:SetChecked(beaconOn)
    win.ArrowCheck:SetChecked(arrowOn)
    win.CombatCheck:SetChecked(combatOn)
    win.VoiceCheck:SetChecked(voiceOn)
    win.StepsCheck:SetChecked(stepsOn)

    local stage = win.Stage
    if not stage then return end

    local hover = self.hoveredKey
    local look = Look()
    local distLabel = (look and look.Distance and look.Distance(42, 1)) or "42 yd"
    stage.BeaconDist:SetText(distLabel)

    if beaconOn or hover == "beacon" then
        stage.Beacon:SetAlpha(beaconOn and 1.0 or 0.92)
        stage.Beacon:Show()
    else
        stage.Beacon:Hide()
    end

    if arrowOn or hover == "arrow" then
        stage.Arrow:SetAlpha(arrowOn and 1.0 or 0.92)
        stage.Arrow:Show()
    else
        stage.Arrow:Hide()
    end

    if voiceOn or hover == "voice" then
        stage.VoicePill:SetAlpha(voiceOn and 1.0 or 0.92)
        stage.VoicePill:Show()
    else
        stage.VoicePill:Hide()
    end

    if stepsOn or hover == "steps" then
        stage.StepsCard:SetAlpha(stepsOn and 1.0 or 0.92)
        stage.StepsCard:Show()
    else
        stage.StepsCard:Hide()
    end

    if combatOn or hover == "combat" then
        stage.CombatText:SetText(L.WHATSNEW_STAGE_COMBAT_ON)
        stage.CombatText:SetTextColor(1.0, 0.86, 0.36, 1)
    else
        stage.CombatText:SetText(L.WHATSNEW_STAGE_COMBAT_OFF)
        stage.CombatText:SetTextColor(0.62, 0.62, 0.62, 1)
    end

    if hover and HOVER_LABELS[hover] then
        stage.Caption:SetTextColor(1.0, 0.86, 0.36, 1)
        stage.Caption:SetText(format(L.WHATSNEW_STAGE_PREVIEW, L[HOVER_LABELS[hover]]))
    else
        local names = {}
        if beaconOn then names[#names + 1] = L.SETUP_METHOD_BEACON end
        if arrowOn then names[#names + 1] = L.SETUP_METHOD_ARROW end
        if voiceOn then names[#names + 1] = L.SETUP_METHOD_VOICE end
        if stepsOn then names[#names + 1] = L.SETUP_METHOD_STEPS end
        stage.Caption:SetTextColor(0.85, 0.85, 0.85, 1)
        if #names > 0 then
            stage.Caption:SetText(format(L.WHATSNEW_STAGE_ACTIVE, table.concat(names, " + ")))
        else
            stage.Caption:SetText(L.WHATSNEW_STAGE_NONE)
        end
    end
end

local function wireHover(check, key)
    if not check.HookScript then return end
    check:HookScript("OnEnter", function()
        WhatsNew.hoveredKey = key
        WhatsNew:Sync()
    end)
    check:HookScript("OnLeave", function()
        if WhatsNew.hoveredKey == key then
            WhatsNew.hoveredKey = nil
            WhatsNew:Sync()
        end
    end)
end

local function onStageUpdate(_, elapsed)
    if type(elapsed) ~= "number" or elapsed < 0 then elapsed = 0 elseif elapsed > 0.25 then elapsed = 0.25 end
    WhatsNew.clock = (WhatsNew.clock + elapsed) % 3600
    local win = WhatsNew.frame
    local stage = win and win.Stage
    if stage and stage.Beacon and stage.Beacon:IsShown() and stage.BeaconHalo then
        stage.BeaconHalo:SetAlpha(0.22 + 0.06 * sin(WhatsNew.clock * (TWO_PI / 2.4)))
    end
end

function WhatsNew:Create()
    if self.frame then return self.frame end
    local Frames = FGPS.UI.Frames
    if not (Frames and Frames.CreateWindow) then return nil end
    local title = format(L.WHATSNEW_TITLE, tostring(FGPS.version or ""))
    local ok, win = pcall(Frames.CreateWindow, "whatsnew", {
        title = title, width = WhatsNew.WIDTH, height = windowHeight(), persist = false, escape = true,
    })
    if not ok or type(win) ~= "table" then
        if FGPS.Log then FGPS.Log:Error("The What's New window could not be made: %s", tostring(win)) end
        return nil
    end
    local look = Look()
    look.DressWindow(win)
    win:ClearAllPoints()
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 24)

    local content = win.Content

    win.Intro = text(content, "row")
    win.Intro:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -2)
    win.Intro:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -2)
    win.Intro:SetText(L.WHATSNEW_INTRO)

    win.Stage = buildStage(content)
    win.Stage:SetPoint("TOPLEFT", win.Intro, "BOTTOMLEFT", 0, -WhatsNew.GAP)
    win.Stage:SetPoint("TOPRIGHT", win.Intro, "BOTTOMRIGHT", 0, -WhatsNew.GAP)

    local function makeFullCheck(prev, key, labelKey, tipKey, onClick)
        local check = look.CheckButton(content, L[labelKey])
        check:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -5)
        if check.SetHitRectInsets then check:SetHitRectInsets(0, -280, 0, -12) end
        check:SetScript("OnClick", function(btn)
            look.PlaySound("row")
            onClick(btn:GetChecked() and true or false)
        end)
        wireHover(check, key)

        local tip = text(content, "hint")
        tip:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 26, 2)
        tip:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        tip:SetText(L[tipKey])
        return check, tip
    end

    local beaconCheck, beaconTip = makeFullCheck(win.Stage, "beacon", "WHATSNEW_BEACON", "WHATSNEW_BEACON_TIP", function(on)
        if FGPS.DB and FGPS.DB.Set then FGPS.DB:Set("roadBeacon", on) end
    end)
    local arrowCheck, arrowTip = makeFullCheck(beaconTip, "arrow", "WHATSNEW_ARROW", "WHATSNEW_ARROW_TIP", function(on)
        if FGPS.DB and FGPS.DB.Set then FGPS.DB:Set("callout.enabled", on) end
    end)
    local combatCheck, combatTip = makeFullCheck(arrowTip, "combat", "WHATSNEW_COMBAT", "WHATSNEW_COMBAT_TIP", setCombatVisible)

    -- Side-by-side compact row for Voice guidance and Step list.
    local voiceCheck = look.CheckButton(content, L.WHATSNEW_VOICE)
    voiceCheck:SetPoint("TOPLEFT", combatTip, "BOTTOMLEFT", 0, -5)
    if voiceCheck.SetHitRectInsets then voiceCheck:SetHitRectInsets(0, -130, 0, -12) end
    voiceCheck:SetScript("OnClick", function(btn)
        look.PlaySound("row")
        if FGPS.DB and FGPS.DB.Set then FGPS.DB:Set("voice.enabled", btn:GetChecked() and true or false) end
    end)
    wireHover(voiceCheck, "voice")

    local voiceTip = text(content, "hint")
    voiceTip:SetPoint("TOPLEFT", voiceCheck, "BOTTOMLEFT", 26, 2)
    voiceTip:SetWidth(205)
    voiceTip:SetText(L.WHATSNEW_VOICE_TIP)

    local stepsCheck = look.CheckButton(content, L.WHATSNEW_STEPS)
    stepsCheck:SetPoint("TOPLEFT", combatTip, "BOTTOMLEFT", 242, -5)
    if stepsCheck.SetHitRectInsets then stepsCheck:SetHitRectInsets(0, -130, 0, -12) end
    stepsCheck:SetScript("OnClick", function(btn)
        look.PlaySound("row")
        if FGPS.DB and FGPS.DB.Set then FGPS.DB:Set("routeBlock.enabled", btn:GetChecked() and true or false) end
    end)
    wireHover(stepsCheck, "steps")

    local stepsTip = text(content, "hint")
    stepsTip:SetPoint("TOPLEFT", stepsCheck, "BOTTOMLEFT", 26, 2)
    stepsTip:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    stepsTip:SetText(L.WHATSNEW_STEPS_TIP)

    win.HighlightsTitle = text(content, "listTitle")
    win.HighlightsTitle:SetPoint("TOPLEFT", voiceTip, "BOTTOMLEFT", -26, -8)
    win.HighlightsTitle:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    win.HighlightsTitle:SetText(L.WHATSNEW_HIGHLIGHTS_TITLE)

    win.Highlights = text(content, "hint")
    win.Highlights:SetPoint("TOPLEFT", win.HighlightsTitle, "BOTTOMLEFT", 0, -3)
    win.Highlights:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    win.Highlights:SetText(L.WHATSNEW_HIGHLIGHTS_BODY)

    win.Done = look.Button(content, L.SETUP_DONE, 88, 22)
    win.Done:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    win.Done:SetScript("OnClick", function() WhatsNew:Hide() end)

    win.Settings = look.Button(content, L.SETUP_SETTINGS, 104, 22)
    win.Settings:SetPoint("RIGHT", win.Done, "LEFT", -6, 0)
    win.Settings:SetScript("OnClick", function()
        WhatsNew:Hide()
        local Settings = FGPS.UI.Settings
        if Settings and Settings.Open then Settings:Open() end
    end)

    win.SetupBtn = look.Button(content, L.WHATSNEW_SETUP, 92, 22)
    win.SetupBtn:SetPoint("RIGHT", win.Settings, "LEFT", -6, 0)
    win.SetupBtn:SetScript("OnClick", function()
        WhatsNew:Hide()
        local Setup = FGPS.UI.Setup
        if Setup and Setup.Show then Setup:Show() end
    end)

    win.Later = text(content, "hint")
    win.Later:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 22 + WhatsNew.GAP)
    win.Later:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 22 + WhatsNew.GAP)
    win.Later:SetText(L.WHATSNEW_LATER)

    win.BeaconCheck = beaconCheck
    win.ArrowCheck = arrowCheck
    win.CombatCheck = combatCheck
    win.VoiceCheck = voiceCheck
    win.StepsCheck = stepsCheck
    win.Options = {
        { key = "beacon", Check = beaconCheck, Tip = beaconTip },
        { key = "arrow",  Check = arrowCheck,  Tip = arrowTip },
        { key = "combat", Check = combatCheck, Tip = combatTip },
        { key = "voice",  Check = voiceCheck,  Tip = voiceTip },
        { key = "steps",  Check = stepsCheck,  Tip = stepsTip },
    }

    if win.HookScript then
        win:HookScript("OnShow", function()
            if win.Stage then win.Stage:SetScript("OnUpdate", onStageUpdate) end
        end)
        win:HookScript("OnHide", function()
            WhatsNew.hoveredKey = nil
            if win.Stage then win.Stage:SetScript("OnUpdate", nil) end
        end)
    end

    self.frame = win
    self:Sync()
    return win
end

function WhatsNew:Show()
    local win = self:Create()
    if not win then return false end
    if win.Title then win.Title:SetText(format(L.WHATSNEW_TITLE, tostring(FGPS.version or ""))) end
    self.hoveredKey = nil
    self:Sync()
    self:MarkSeen()
    win:Show()
    if win.Stage then win.Stage:SetScript("OnUpdate", onStageUpdate) end
    return true
end

function WhatsNew:Hide()
    if self.frame and self.frame:IsShown() then
        self.hoveredKey = nil
        if self.frame.Stage then self.frame.Stage:SetScript("OnUpdate", nil) end
        self.frame:Hide()
    end
end

function WhatsNew:IsShown()
    return self.frame ~= nil and self.frame:IsShown() == true
end

local function startLoginTimer()
    if WhatsNew.loginTimer or not (C_Timer and C_Timer.NewTimer) then return end
    WhatsNew.loginTimer = C_Timer.NewTimer(WhatsNew.LOGIN_DELAY, function()
        WhatsNew.loginTimer = nil
        WhatsNew.CheckUpdateLogin()
    end)
end

-- Shows What's New once after an existing install updates to a new version, waiting politely for
-- combat, a hidden UI (cinematic / Alt-Z), the world map or the welcome window.
function WhatsNew.CheckUpdateLogin()
    if not WhatsNew.NeedsPopup() then
        WhatsNew.loginWaits = false
        return false
    end
    if inFight() then
        WhatsNew.loginWaits = true
        return false
    end
    if UIParent and UIParent.IsVisible and not UIParent:IsVisible() then
        startLoginTimer()
        return false
    end
    if mapVisible() or setupVisible() then
        WhatsNew.loginWaits = true
        return false
    end
    WhatsNew.loginWaits = false
    return WhatsNew:Show()
end

local function armUpdateLogin()
    if not WhatsNew.NeedsPopup() then return end
    if WhatsNew.loginArmed then
        if WhatsNew.loginWaits and not inFight() then startLoginTimer() end
        return
    end
    WhatsNew.loginArmed = true
    startLoginTimer()
end

function WhatsNew:Init()
    if self.ready then return end
    self.ready = true

    local Slash = FGPS.Slash
    if Slash and Slash.Register then
        local function openWhatsNew() WhatsNew:Show() end
        Slash.Register("whatsnew", openWhatsNew, L.WHATSNEW_HELP)
        Slash.Register("news", openWhatsNew, L.WHATSNEW_HELP)
    end

    local Events = FGPS.Events
    if not Events then return end
    local function hide() WhatsNew:Hide() end

    Events:Register("WORLD_ENTERED", function() armUpdateLogin() end, self)
    Events:Register("COMBAT_STATE", function(_, inCombat)
        if inCombat == true then
            hide()
        elseif WhatsNew.loginWaits then
            WhatsNew.CheckUpdateLogin()
        end
    end, self)
    Events:Register("DESTINATION_SET", hide, self)
    Events:Register("MAP_SHOWN", hide, self)
    Events:Register("MAP_HIDDEN", function()
        if WhatsNew.loginWaits then WhatsNew.CheckUpdateLogin() end
    end, self)
    Events:Register("SETTINGS_CHANGED", function(_, key)
        if not self.frame then return end
        if key == "textSize" or key == "*" then self.frame:SetHeight(windowHeight()) end
        if SYNC_KEYS[key] then self:Sync() end
    end, self)
end
