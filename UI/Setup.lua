










local ADDON_NAME, FGPS = ...

local L = FGPS.L

local Setup = { ready = false }
FGPS.UI = FGPS.UI or {}
FGPS.UI.Setup = Setup

Setup.WIDTH = 440
Setup.HEIGHT = 286
Setup.GAP = 10

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
    return Setup.HEIGHT + 12 * Look().TextSizeDelta()
end


function Setup:MarkDone()
    local account = FGPS.DB and FGPS.DB.account
    if account then account.setupComplete = true end
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

    win.Later = text(content, "hint")
    win.Later:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 22 + Setup.GAP)
    win.Later:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 22 + Setup.GAP)
    win.Later:SetText(L.SETUP_LATER)

    self.frame = win
    return win
end


function Setup:Show()
    local win = self:Create()
    if not win then return false end
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
        if (key == "textSize" or key == "*") and self.frame then self.frame:SetHeight(windowHeight()) end
    end, self)
end
