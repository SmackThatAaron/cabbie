








local ADDON_NAME, FGPS = ...

local L = FGPS.L
local ipairs, pcall, tostring, type = ipairs, pcall, tostring, type

local Setup = { ready = false }
FGPS.UI = FGPS.UI or {}
FGPS.UI.Setup = Setup

Setup.WIDTH = 460
Setup.HEIGHT = 368
Setup.GAP = 10

Setup.METHODS = {
    { key = "beacon", field = "BeaconCheck", path = "roadBeacon",         labelKey = "SETUP_METHOD_BEACON", tipKey = "SETUP_METHOD_BEACON_TIP" },
    { key = "arrow",  field = "ArrowCheck",  path = "callout.enabled",    labelKey = "SETUP_METHOD_ARROW",  tipKey = "SETUP_METHOD_ARROW_TIP" },
    { key = "steps",  field = "StepsCheck",  path = "routeBlock.enabled", labelKey = "SETUP_METHOD_STEPS",  tipKey = "SETUP_METHOD_STEPS_TIP" },
}

local METHOD_PATHS = {}
for _, spec in ipairs(Setup.METHODS) do METHOD_PATHS[spec.path] = true end

local function Look()
    return FGPS.UI.Look
end

local function text(parent, role)
    local fs = Look().FontString(parent, "OVERLAY", role)
    if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
    if fs.SetJustifyV then fs:SetJustifyV("TOP") end
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    return fs
end

local function windowHeight()
    return Setup.HEIGHT + 24 * Look().TextSizeDelta()
end


function Setup:Sync()
    local win = self.frame
    local DB = FGPS.DB
    if not (win and win.Methods and DB and DB.Get) then return end
    for _, row in ipairs(win.Methods) do
        row.Check:SetChecked(DB:Get(row.path) == true)
    end
end



function Setup:MarkDone()
    local account = FGPS.DB and FGPS.DB.account
    if account then
        account.setupComplete = true
        if type(FGPS.version) == "string" and FGPS.version ~= "" then
            account.whatsNewVersion = FGPS.version
        end
    end
end

function Setup:Create()
    if self.frame then return self.frame end
    local Frames = FGPS.UI.Frames
    if not (Frames and Frames.CreateWindow) then return nil end
    local ok, win = pcall(Frames.CreateWindow, "setup", {
        title = L.SETUP_TITLE, width = Setup.WIDTH, height = windowHeight(), persist = false, escape = true,
    })
    if not ok or type(win) ~= "table" then
        if FGPS.Log then FGPS.Log:Error("The welcome window could not be made: %s", tostring(win)) end
        return nil
    end
    local look = Look()
    look.DressWindow(win)
    local content = win.Content

    win.Intro = text(content, "row")
    win.Intro:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -2)
    win.Intro:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -2)
    win.Intro:SetText(L.SETUP_INTRO)

    win.PickHeading = text(content, "listTitle")
    win.PickHeading:SetPoint("TOPLEFT", win.Intro, "BOTTOMLEFT", 0, -Setup.GAP)
    win.PickHeading:SetPoint("TOPRIGHT", win.Intro, "BOTTOMRIGHT", 0, -Setup.GAP)
    win.PickHeading:SetText(L.SETUP_PICK)

    win.Methods = {}
    local prevAnchor = win.PickHeading
    for i, spec in ipairs(Setup.METHODS) do
        local check = look.CheckButton(content, L[spec.labelKey])
        check:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", 0, i == 1 and -6 or -4)
        if check.SetHitRectInsets then check:SetHitRectInsets(0, -240, 0, -14) end
        check:SetScript("OnClick", function(btn)
            look.PlaySound("row")
            if FGPS.DB and FGPS.DB.Set then
                FGPS.DB:Set(spec.path, btn:GetChecked() and true or false)
            end
        end)

        local tip = text(content, "hint")
        tip:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 26, 2)
        tip:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        tip:SetText(L[spec.tipKey])

        win[spec.field] = check
        win.Methods[i] = { key = spec.key, path = spec.path, Check = check, Tip = tip }
        prevAnchor = tip
    end

    win.Done = look.Button(content, L.SETUP_DONE, 96, 22)
    win.Done:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    win.Done:SetScript("OnClick", function() Setup:Hide() end)

    win.Settings = look.Button(content, L.SETUP_SETTINGS, 110, 22)
    win.Settings:SetPoint("RIGHT", win.Done, "LEFT", -6, 0)
    win.Settings:SetScript("OnClick", function()
        Setup:Hide()
        local Settings = FGPS.UI.Settings
        if Settings and Settings.Open then Settings:Open() end
    end)

    win.WhatsNew = look.Button(content, L.SETUP_WHATSNEW, 110, 22)
    win.WhatsNew:SetPoint("RIGHT", win.Settings, "LEFT", -6, 0)
    win.WhatsNew:SetScript("OnClick", function()
        Setup:Hide()
        local WhatsNew = FGPS.UI.WhatsNew
        if WhatsNew and WhatsNew.Show then WhatsNew:Show() end
    end)

    win.Later = text(content, "hint")
    win.Later:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 22 + Setup.GAP)
    win.Later:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 22 + Setup.GAP)
    win.Later:SetText(L.SETUP_LATER)

    self.frame = win
    self:Sync()
    return win
end


function Setup:Show()
    local win = self:Create()
    if not win then return false end
    self:Sync()
    self:MarkDone()
    win:Show()

    Look().NoteOnce("welcome", "Welcome window: ground %s", tostring(win.fgpsGround))
    return true
end

function Setup:Hide()
    if self.frame and self.frame:IsShown() then self.frame:Hide() end
end

function Setup:IsShown()
    return self.frame ~= nil and self.frame:IsShown() == true
end

function Setup:Init()
    if self.ready then return end
    self.ready = true
    local Events = FGPS.Events
    if not Events then return end
    local function hide() Setup:Hide() end
    Events:Register("COMBAT_STATE", function(_, inCombat) if inCombat == true then hide() end end, self)
    Events:Register("DESTINATION_SET", hide, self)
    Events:Register("MAP_SHOWN", hide, self)
    Events:Register("SETTINGS_CHANGED", function(_, key)
        if not self.frame then return end
        if key == "textSize" or key == "*" then self.frame:SetHeight(windowHeight()) end
        if METHOD_PATHS[key] or key == "*" then self:Sync() end
    end, self)
end
