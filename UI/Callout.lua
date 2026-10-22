








local ADDON_NAME, FGPS = ...

local type, min, max, abs, exp, pi = type, math.min, math.max, math.abs, math.exp, math.pi
local TWO_PI = 2 * pi


local function fold(a)
    if a > pi then return a - TWO_PI elseif a <= -pi then return a + TWO_PI end
    return a
end

local Callout = {
    frame = nil,
    alpha = 0,
    target = 0,
    combat = false,
    glyph = nil,
    strata = nil,
    distanceAlone = nil,
    width = nil,
    live = nil,
    rotation = nil,
    shownX = nil,
    shownY = nil,
    fromX = nil,
    fromY = nil,
    blendLeft = 0,
    editing = false,
    editRegistered = false,
    offset = 0,
    offsetRate = 0,
    turnFrom = nil,
    eventsBound = false,
}
FGPS.UI.Callout = Callout




Callout.GLYPH_SIZE = 64
Callout.GLYPH_GAP = 2
Callout.LINE_HEIGHT = 16
Callout.HEIGHT = 89
Callout.Y = -37


Callout.STRATA = "LOW"





Callout.NOTICE_STRATA = "FULLSCREEN_DIALOG"






Callout.TEXT_BOTTOM = 7


Callout.MAX_WIDTH = 520
Callout.FADE_IN = 0.25
Callout.FADE_OUT = 0.6
Callout.ROUND = 5





Callout.ART = "Interface\\AddOns\\Cabbie\\Media\\arrow_guide"
Callout.ROTATION = {
    ahead = 0,
    slight_left = pi / 4, left = pi / 2, sharp_left = 3 * pi / 4,
    slight_right = -pi / 4, right = -pi / 2, sharp_right = -3 * pi / 4,
    uturn = pi,
}


Callout.AIM_MIN_YARDS = 1






Callout.BLEND_SECONDS = 0.25
Callout.BLEND_MAX_YARDS = 30






Callout.TURN_SECONDS = 0.1


Callout.EDIT_KEY = "callout"
Callout.SAMPLE = { glyph = "ahead", text = FGPS.L["The next turn is shown here"], yards = 100, key = "editmode" }





Callout.SIZE = { min = 0.5, max = 2, step = 0.05 }
Callout.ALPHA = { min = 0.2, max = 1, step = 0.05 }
Callout.TEXT_SIZE = { min = 0.75, max = 2, step = 0.05 }




Callout.ART_TINT = "Interface\\AddOns\\Cabbie\\Media\\arrow_guide_tint"




Callout.STYLES = {
    { value = "arrow", label = FGPS.L["Arrow"], art = Callout.ART_TINT, gold = Callout.ART },
    { value = "chevron", label = FGPS.L["Chevron"], art = "Interface\\AddOns\\Cabbie\\Media\\arrow_chevron" },
    { value = "needle", label = FGPS.L["Needle"], art = "Interface\\AddOns\\Cabbie\\Media\\arrow_needle" },
    { value = "pointer", label = FGPS.L["Pointer"], art = "Interface\\AddOns\\Cabbie\\Media\\arrow_pointer" },
}
local STYLE_BY_VALUE = {}
for _, style in ipairs(Callout.STYLES) do STYLE_BY_VALUE[style.value] = style end


local function lookNumber(key, range)
    local DB = FGPS.DB
    local value = DB and DB.Get and DB:Get("callout." .. key)
    if type(value) == "number" and value >= range.min and value <= range.max then return value end
    local default = DB and DB.GetDefault and DB:GetDefault("callout." .. key)
    return type(default) == "number" and default or 1
end



local function lookColor()
    local DB, Look = FGPS.DB, FGPS.UI.Look
    local default = DB and DB.GetDefault and DB:GetDefault("callout.arrowColor") or "ffd030"
    local value = DB and DB.Get and DB:Get("callout.arrowColor")
    if not (Look and Look.HexColor(value)) then value = default end
    value = value:lower()
    return value, value == default
end


local function lookStyle()
    local DB = FGPS.DB
    local value = DB and DB.Get and DB:Get("callout.arrowStyle")
    return value ~= nil and STYLE_BY_VALUE[value] or Callout.STYLES[1]
end



local function stylePicture(style)
    local hex, isDefault = lookColor()
    if style.gold and isDefault then return style.gold, 1, 1, 1 end
    local r, g, b = FGPS.UI.Look.HexColor(hex)
    return style.art, r, g, b
end



local function paintArt(glyph)
    local art, r, g, b = stylePicture(lookStyle())
    if glyph.fgpsArt ~= art then
        glyph.fgpsArt = art
        glyph:SetTexture(art)
    end
    glyph:SetVertexColor(r, g, b)
end






function Callout.DefaultPosition(frame)
    local height = frame and frame.GetHeight and frame:GetHeight() or Callout.HEIGHT
    return { point = "TOP", relativePoint = "TOP", x = 0, y = math.min(0, Callout.Y - Callout.HEIGHT + height) }
end


local function lookFlag(key)
    local DB = FGPS.DB
    local value = DB and DB.Get and DB:Get("callout." .. key)
    if type(value) == "boolean" then return value end
    return not (DB and DB.GetDefault and DB:GetDefault("callout." .. key) == false)
end

local fitWords





local function sizeWords(frame, scale)
    if frame.fgpsTextScale == scale or (frame.fgpsTextScale == nil and scale == 1) then return end
    frame.fgpsTextScale = scale
    local font = frame.fgpsFont
    for _, line in ipairs({ frame.Text, frame.Ruler, frame.Distance }) do
        line:SetFont(font[1], font[2] * scale, font[3])
    end
    fitWords(frame, frame.Ruler:GetText() or "")
end





local function applyLook(frame)
    if not frame then return end
    local glyph = math.floor(Callout.GLYPH_SIZE * lookNumber("arrowSize", Callout.SIZE) + 0.5)
    frame.Glyph:SetSize(glyph, glyph)
    frame.Glyph:SetAlpha(lookNumber("arrowAlpha", Callout.ALPHA))
    paintArt(frame.Glyph)
    local textScale = lookNumber("textSize", Callout.TEXT_SIZE)
    sizeWords(frame, textScale)
    local line = math.floor(Callout.LINE_HEIGHT * textScale + 0.5)
    local height = glyph + Callout.GLYPH_GAP + line + Callout.TEXT_BOTTOM
    if frame:GetHeight() == height and frame:GetNumPoints() > 0 then return end
    frame:SetHeight(height)
    local Positions = FGPS.UI.Positions
    if Callout.editRegistered and Positions and Positions.IsRegistered(Callout.EDIT_KEY) then
        Positions.Reapply(Callout.EDIT_KEY)
    else
        frame:ClearAllPoints()
        frame:SetPoint("TOP", UIParent, "TOP", 0, Callout.DefaultPosition(frame).y)
    end
end

function Callout.ApplyLook()
    applyLook(Callout.frame)
end


local function enabled()
    if not FGPS.UI.Guide.Enabled() then return false end
    local DB = FGPS.DB
    return not (DB and DB.Get) or DB:Get("callout.enabled") ~= false
end



local function placeDistance(frame, alone)
    if Callout.distanceAlone == alone then return end
    Callout.distanceAlone = alone
    frame.Distance:ClearAllPoints()
    if alone then
        frame.Distance:SetPoint("BOTTOM", frame, "BOTTOM", 0, Callout.TEXT_BOTTOM)
    else
        frame.Distance:SetPoint("LEFT", frame.Text, "RIGHT", 10, 0)
    end
end

local function createFrame()
    local Look = FGPS.UI.Look
    local frame = CreateFrame("Frame", nil, UIParent)
    Callout.strata = Callout.STRATA
    frame:SetFrameStrata(Callout.strata)
    frame:SetSize(400, Callout.HEIGHT)
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
    placeDistance(frame, false)


    local path, size, flags = frame.Text:GetFont()
    frame.fgpsFont = { type(path) == "string" and path or "Fonts\\FRIZQT__.TTF",
                       type(size) == "number" and size > 0 and size or 16, type(flags) == "string" and flags or "OUTLINE" }



    frame.Glyph = frame:CreateTexture(nil, "ARTWORK")
    frame.Glyph:SetTexture(Callout.ART)
    frame.Glyph.fgpsArt = Callout.ART
    frame.Glyph:SetSize(Callout.GLYPH_SIZE, Callout.GLYPH_SIZE)
    frame.Glyph:SetPoint("TOP", frame, "TOP", 0, 0)
    frame.Glyph:Hide()


    applyLook(frame)
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
            rotation = fold(Coords.Bearing(x, y, aimX, aimY) - facing)
        end
    end
    if not rotation then rotation = Callout.ROTATION[line.glyph] end
    if not rotation then return end

    if Callout.turnFrom then
        Callout.offset = fold(Callout.turnFrom - rotation)
        Callout.turnFrom = nil
    end
    local offset = Callout.offset
    if offset ~= 0 then
        local dt = elapsed or 0
        if dt > 0 then


            local w = 2 / Callout.TURN_SECONDS
            local rate = Callout.offsetRate
            local k = (rate + w * offset) * dt
            local e = exp(-w * dt)
            offset, rate = (offset + k) * e, (rate - w * k) * e
            if abs(offset) < 1e-4 and abs(rate) < 1e-3 then offset, rate = 0, 0 end
            Callout.offset, Callout.offsetRate = offset, rate
        end
        rotation = fold(rotation + offset)
    end
    if rotation ~= Callout.rotation and frame.Glyph.SetRotation then
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
    if rotation then
        if frame.Glyph.SetRotation then frame.Glyph:SetRotation(rotation) end
        Callout.rotation = rotation
        frame.Glyph:Show()
    else
        frame.Glyph:Hide()
    end
end







function fitWords(frame, text)
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
    if type(callout) ~= "table" and Callout.editing then callout = Callout.SAMPLE end
    if not (type(callout) == "table" and enabled() and not Callout.combat) then
        Callout.live, Callout.shownX, Callout.shownY, Callout.blendLeft = nil, nil, nil, 0
        Callout.offset, Callout.offsetRate, Callout.turnFrom = 0, 0, nil
        fadeTo(frame, 0)
        return
    end
    local Look = FGPS.UI.Look


    local strata = callout.answer and Callout.NOTICE_STRATA or Callout.STRATA
    if Callout.strata ~= strata then
        Callout.strata = strata
        frame:SetFrameStrata(strata)
    end


    local live = callout.live and type(callout.aimX) == "number" and type(callout.aimY) == "number" and callout or nil



    local hideWords = not lookFlag("showWords") and not callout.answer
        and (live ~= nil or Callout.ROTATION[callout.glyph] ~= nil)
    local words = not hideWords and callout.text or ""


    if callout.open and not hideWords then
        local r, g, b = Look.Color("grey")
        words = words .. string.format(" |cff%02x%02x%02x%s|r", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), FGPS.L["(open ground)"])
    end
    if Look.SetLine(frame.Text, words, Look.Color("current")) then fitWords(frame, words) end
    placeDistance(frame, words == "")
    local distance, shown = Look.Distance(callout.yards, Callout.ROUND)
    if shown and shown > 0 and lookFlag("showDistance") then
        if Look.SetLine(frame.Distance, distance, Look.Color("header")) then frame.Distance:Show() end
    elseif Look.SetLine(frame.Distance, "") then
        frame.Distance:Hide()
    end




    local was = Callout.live
    local sx, sy = Callout.shownX, Callout.shownY
    local shownRotation = Callout.glyph and frame.Glyph:IsShown() and Callout.rotation or nil
    if live and was and sx and was.aimInst == live.aimInst
        and (live.aimX - sx) ^ 2 + (live.aimY - sy) ^ 2 <= Callout.BLEND_MAX_YARDS * Callout.BLEND_MAX_YARDS then
        if live.aimX ~= was.aimX or live.aimY ~= was.aimY then
            Callout.fromX, Callout.fromY, Callout.blendLeft = sx, sy, Callout.BLEND_SECONDS
        end
    else
        Callout.shownX, Callout.shownY, Callout.blendLeft = nil, nil, 0
        if live then Callout.turnFrom = shownRotation end
    end
    Callout.live = live
    paintGlyph(frame, callout.glyph, live ~= nil)
    if live then
        turnArrow(frame, 0)
    else
        Callout.offset, Callout.offsetRate, Callout.turnFrom = 0, 0, nil
    end
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

local function percent(value) return string.format("%d%%", math.floor(value * 100 + 0.5)) end




local function lookSettings()
    local DB, L = FGPS.DB, FGPS.L
    local function numberRow(key, label, range)
        return { type = "slider", label = label, min = range.min, max = range.max, step = range.step, format = percent,
                 default = DB:GetDefault("callout." .. key),
                 get = function() return lookNumber(key, range) end,
                 set = function(value) DB:Set("callout." .. key, value) end }
    end
    local function checkRow(key, label)
        return { type = "checkbox", label = label, default = DB:GetDefault("callout." .. key),
                 get = function() return lookFlag(key) end,
                 set = function(value) DB:Set("callout." .. key, value and true or false) end }
    end
    local styles = {}
    for i, style in ipairs(Callout.STYLES) do styles[i] = { value = style.value, label = style.label, texture = style.art } end
    return {
        { type = "pictures", label = L["Arrow style"], options = styles, default = DB:GetDefault("callout.arrowStyle"),
          picture = function(value)
              local style = STYLE_BY_VALUE[value]
              if style then return stylePicture(style) end
          end,
          get = function() return lookStyle().value end,
          set = function(value) DB:Set("callout.arrowStyle", value) end },
        numberRow("arrowSize", L["Arrow size"], Callout.SIZE),
        { type = "color", label = L["Arrow colour"], default = DB:GetDefault("callout.arrowColor"),
          get = function() return (lookColor()) end,
          set = function(value) DB:Set("callout.arrowColor", value) end },
        numberRow("arrowAlpha", L["Arrow opacity"], Callout.ALPHA),
        checkRow("showWords", L["Show the words"]),
        checkRow("showDistance", L["Show the distance"]),
        numberRow("textSize", L["Text size"], Callout.TEXT_SIZE),
    }
end





local function registerEditMode()
    local EditMode = FGPS.UI.EditMode
    if Callout.editRegistered or not (Callout.frame and EditMode and EditMode.Register) then return end
    Callout.editRegistered = true
    EditMode.Register(Callout.frame, {
        key = Callout.EDIT_KEY,
        label = FGPS.L["Turn arrow"],
        defaultPosition = Callout.DefaultPosition,
        settings = lookSettings(),
        onEditModeEnter = function()
            Callout.editing = true
            repaint()
        end,
        onEditModeExit = function()
            Callout.editing = false
            repaint()
        end,
    })
end

function Callout:Init()
    if not self.frame then self.frame = createFrame() end

    self.combat = inFight()


    local EditMode = FGPS.UI.EditMode
    if EditMode and EditMode.initialised then registerEditMode() end
    if self.eventsBound then return end
    local Events = FGPS.Events
    if not Events then return end
    Events:Register("ADDON_READY", registerEditMode, self)
    Events:Register("GUIDE_CHANGED", function(_, model) Callout.Paint(model) end, self)
    Events:Register("COMBAT_STATE", function(_, inCombat)
        Callout.combat = inCombat == true
        repaint()
    end, self)
    Events:Register("SETTINGS_CHANGED", function(_, key)
        if key == "*" or key == "callout" or (type(key) == "string" and key:sub(1, 8) == "callout.") then
            applyLook(Callout.frame)
            repaint()
        end
    end, self)


    Events:Register("WORLD_ENTERED", function()
        Callout.combat = inFight()
        repaint()
    end, self)
    self.eventsBound = true
end
