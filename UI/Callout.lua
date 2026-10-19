








local ADDON_NAME, FGPS = ...

local type, min, max, pi = type, math.min, math.max, math.pi
local TWO_PI = 2 * pi

local Callout = {
    frame = nil,
    alpha = 0,
    target = 0,
    combat = false,
    glyph = nil,
    strata = nil,
    width = nil,
    live = nil,
    rotation = nil,
    shownX = nil,
    shownY = nil,
    fromX = nil,
    fromY = nil,
    blendLeft = 0,
    eventsBound = false,
}
FGPS.UI.Callout = Callout

Callout.Y = -96


Callout.STRATA = "LOW"





Callout.NOTICE_STRATA = "FULLSCREEN_DIALOG"






Callout.TEXT_BOTTOM = 7


Callout.MAX_WIDTH = 520
Callout.FADE_IN = 0.25
Callout.FADE_OUT = 0.6
Callout.GLYPH_SIZE = 26
Callout.ROUND = 5




Callout.ARROW_ART = { "Navigation-Tracked-Arrow", "poi-traveldirections-arrow" }
Callout.ROTATION = {
    ahead = 0,
    slight_left = pi / 4, left = pi / 2, sharp_left = 3 * pi / 4,
    slight_right = -pi / 4, right = -pi / 2, sharp_right = -3 * pi / 4,
    uturn = pi,
}


Callout.AIM_MIN_YARDS = 1






Callout.BLEND_SECONDS = 0.25
Callout.BLEND_MAX_YARDS = 30


local function enabled()
    if not FGPS.UI.Guide.Enabled() then return false end
    local DB = FGPS.DB
    return not (DB and DB.Get) or DB:Get("callout.enabled") ~= false
end

local function createFrame()
    local Look = FGPS.UI.Look
    local frame = CreateFrame("Frame", nil, UIParent)
    Callout.strata = Callout.STRATA
    frame:SetFrameStrata(Callout.strata)
    frame:SetSize(400, 30)
    frame:SetPoint("TOP", UIParent, "TOP", 0, Callout.Y)
    frame:SetAlpha(0)
    frame:Hide()


    frame:SetScript("OnHide", function(self)
        Callout.glyph = nil
        Look.ForgetLine(self.Text)
        Look.ForgetLine(self.Distance)
    end)




    frame.Text = frame:CreateFontString(nil, "OVERLAY", Look.Font("callout"))
    frame.Text:SetPoint("BOTTOM", frame, "BOTTOM", 0, Callout.TEXT_BOTTOM)
    if frame.Text.SetJustifyH then frame.Text:SetJustifyH("CENTER") end
    if frame.Text.SetWordWrap then frame.Text:SetWordWrap(true) end



    frame.Ruler = frame:CreateFontString(nil, "BACKGROUND", Look.Font("callout"))
    frame.Ruler:SetPoint("BOTTOM", frame, "TOP", 0, 0)
    frame.Ruler:SetAlpha(0)
    frame.Distance = frame:CreateFontString(nil, "OVERLAY", Look.Font("callout"))
    frame.Distance:SetPoint("LEFT", frame.Text, "RIGHT", 10, 0)
    frame.Glyph = frame:CreateTexture(nil, "ARTWORK")
    frame.Glyph:SetSize(Callout.GLYPH_SIZE, Callout.GLYPH_SIZE)


    frame.Glyph:SetPoint("RIGHT", frame.Text, "LEFT", -8, 2)
    frame.Glyph:Hide()
    return frame
end






local function turnArrow(frame, elapsed)
    local line = Callout.live
    local Coords = FGPS.Coords
    if not (line and Coords) then return end
    if Callout.blendLeft > 0 then
        local left = Callout.blendLeft - (elapsed or 0)
        if left < 0 then left = 0 end
        Callout.blendLeft = left
        local u = 1 - left / Callout.BLEND_SECONDS
        Callout.shownX = Callout.fromX + (line.aimX - Callout.fromX) * u
        Callout.shownY = Callout.fromY + (line.aimY - Callout.fromY) * u
    else
        Callout.shownX, Callout.shownY = line.aimX, line.aimY
    end
    local aimX, aimY = Callout.shownX, Callout.shownY
    local rotation
    local facing = Coords.PlayerFacing()
    if facing then
        local x, y, inst = Coords.PlayerXY()
        if x and inst == line.aimInst then
            local dx, dy = aimX - x, aimY - y
            if dx * dx + dy * dy < Callout.AIM_MIN_YARDS * Callout.AIM_MIN_YARDS then return end
            rotation = Coords.Bearing(x, y, aimX, aimY) - facing
            if rotation > pi then rotation = rotation - TWO_PI elseif rotation <= -pi then rotation = rotation + TWO_PI end
        end
    end
    if not rotation then rotation = Callout.ROTATION[line.glyph] end
    if rotation and rotation ~= Callout.rotation and frame.Glyph.SetRotation then
        Callout.rotation = rotation
        frame.Glyph:SetRotation(rotation)
    end
end



local function onUpdate(frame, elapsed)
    if Callout.alpha ~= Callout.target then
        if Callout.target > Callout.alpha then
            Callout.alpha = min(Callout.target, Callout.alpha + elapsed / Callout.FADE_IN)
        else
            Callout.alpha = max(Callout.target, Callout.alpha - elapsed / Callout.FADE_OUT)
        end
        frame:SetAlpha(Callout.alpha)
    end
    local live = Callout.live ~= nil and Callout.target > 0
    if live then turnArrow(frame, elapsed) end
    if Callout.alpha == Callout.target and not live then
        frame:SetScript("OnUpdate", nil)
        if Callout.alpha == 0 then frame:Hide() end
    end
end



local function fadeTo(frame, target)
    Callout.target = target
    if target > 0 then frame:Show() end
    if Callout.alpha ~= target or (target > 0 and Callout.live ~= nil) then
        frame:SetScript("OnUpdate", onUpdate)
        return
    end

    frame:SetScript("OnUpdate", nil)
    if target == 0 then frame:Hide() end
end





local function paintGlyph(frame, glyph, live)
    local mark = live and true or glyph or false
    if Callout.glyph == mark then return end
    Callout.glyph = mark
    local rotation
    if mark == true then
        rotation = Callout.ROTATION[glyph] or 0
    elseif mark then
        rotation = Callout.ROTATION[mark]
    end
    if rotation and FGPS.UI.Look.Atlas(frame.Glyph, Callout.ARROW_ART, Callout.GLYPH_SIZE) then
        if frame.Glyph.SetRotation then frame.Glyph:SetRotation(rotation) end
        Callout.rotation = rotation
        frame.Glyph:Show()
    else
        frame.Glyph:Hide()
    end
end







local function fitWords(frame, text)
    frame.Ruler:SetText(text)
    local natural = frame.Ruler:GetStringWidth()
    local width = type(natural) == "number" and natural > Callout.MAX_WIDTH and Callout.MAX_WIDTH or nil
    if Callout.width == width then return end
    Callout.width = width
    frame.Text:SetWidth(width or 0)
end




local function paint(model)
    local frame = Callout.frame
    if not frame then return end
    local callout = type(model) == "table" and model.callout or nil
    if not (type(callout) == "table" and enabled() and not Callout.combat) then
        Callout.live, Callout.shownX, Callout.shownY, Callout.blendLeft = nil, nil, nil, 0
        fadeTo(frame, 0)
        return
    end
    local Look = FGPS.UI.Look


    local strata = callout.answer and Callout.NOTICE_STRATA or Callout.STRATA
    if Callout.strata ~= strata then
        Callout.strata = strata
        frame:SetFrameStrata(strata)
    end
    local words = callout.text or ""
    if Look.SetLine(frame.Text, words, Look.Color("current")) then fitWords(frame, words) end
    local distance, shown = Look.Distance(callout.yards, Callout.ROUND)
    if shown and shown > 0 then
        if Look.SetLine(frame.Distance, distance, Look.Color("header")) then frame.Distance:Show() end
    elseif Look.SetLine(frame.Distance, "") then
        frame.Distance:Hide()
    end


    local live = callout.live and type(callout.aimX) == "number" and type(callout.aimY) == "number" and callout or nil


    local was = Callout.live
    local sx, sy = Callout.shownX, Callout.shownY
    if live and was and sx and was.aimInst == live.aimInst
        and (live.aimX - sx) ^ 2 + (live.aimY - sy) ^ 2 <= Callout.BLEND_MAX_YARDS * Callout.BLEND_MAX_YARDS then
        if live.aimX ~= was.aimX or live.aimY ~= was.aimY then
            Callout.fromX, Callout.fromY, Callout.blendLeft = sx, sy, Callout.BLEND_SECONDS
        end
    else
        Callout.shownX, Callout.shownY, Callout.blendLeft = nil, nil, 0
    end
    Callout.live = live
    paintGlyph(frame, callout.glyph, live ~= nil)
    if live then turnArrow(frame, 0) end
    fadeTo(frame, 1)
end




function Callout.Paint(model)
    local Perf = FGPS.Perf
    if Perf then Perf:Begin("callout") end
    paint(model)
    if Perf then Perf:End("callout") end
end


local function repaint()
    local Guide = FGPS.UI.Guide
    Callout.Paint(Guide and Guide.Get and Guide.Get() or nil)
end


local function inFight()
    return InCombatLockdown ~= nil and InCombatLockdown() == true
end

function Callout:Init()
    if not self.frame then self.frame = createFrame() end

    self.combat = inFight()
    if self.eventsBound then return end
    local Events = FGPS.Events
    if not Events then return end
    Events:Register("GUIDE_CHANGED", function(_, model) Callout.Paint(model) end, self)
    Events:Register("COMBAT_STATE", function(_, inCombat)
        Callout.combat = inCombat == true
        repaint()
    end, self)
    Events:Register("SETTINGS_CHANGED", function(_, key)
        if key == "*" or key == "callout.enabled" then repaint() end
    end, self)


    Events:Register("WORLD_ENTERED", function()
        Callout.combat = inFight()
        repaint()
    end, self)
    self.eventsBound = true
end
