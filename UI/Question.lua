
























local ADDON_NAME, FGPS = ...

local type, ipairs, pcall, tostring, floor, max = type, ipairs, pcall, tostring, math.floor, math.max

local Question = {
    frame = nil,
    current = nil,
    waiting = {},
    record = {},
}
FGPS.UI.Question = Question



Question.WIDTH = 320
Question.BUTTON_WIDTH = 128
Question.BUTTON_HEIGHT = 21
Question.BUTTON_GAP = 8
Question.PAD = 16
Question.MAX_BUTTONS = 3

Question.RECORD_MAX = 20


Question.KEYS_TEMPLATE = "InsecureKeyboardInputPropagatorTemplate"

local rows = setmetatable({}, { __mode = "k" })

local function inFight()
    return InCombatLockdown ~= nil and InCombatLockdown() == true
end

local function log(fmt, ...)
    if FGPS.Log then FGPS.Log:Error(fmt, ...) end
end




local function note(spec)
    if not FGPS:IsOwnerInstall() then return nil end
    local row = { q = spec.id, at = GetTime and floor(GetTime() * 10 + 0.5) / 10 or nil }
    local record = Question.record
    record[#record + 1] = row
    while #record > Question.RECORD_MAX do table.remove(record, 1) end
    return row
end

local function answered(spec, answer, how)
    local row = rows[spec]
    rows[spec] = nil
    if row then row.answer, row.how = answer, how end
end




local function setPropagation(frame, on)
    if inFight() or not frame.SetPropagateKeyboardInput then return end
    pcall(frame.SetPropagateKeyboardInput, frame, on)
end



local function letKeysThrough(frame)
    setPropagation(frame, true)
    if not frame.GetPropagateKeyboardInput then return false end
    local ok, on = pcall(frame.GetPropagateKeyboardInput, frame)
    return ok and on == true
end


local function takeKeyboard(frame)
    if Question.current and frame:IsVisible() and letKeysThrough(frame) then
        frame:EnableKeyboard(true)
    else
        frame:EnableKeyboard(false)
    end
end

local close, showNext

local function onKeyDown(frame, key)
    if key ~= "ESCAPE" or not Question.current then return end
    local later = not inFight() and C_Timer and C_Timer.After
    if later then setPropagation(frame, false) end
    close("escape", true)
    if later then


        C_Timer.After(0, function()
            setPropagation(frame, true)
            if not Question.current then showNext() end
        end)
    elseif not Question.current then
        showNext()
    end
end




local function press(index)
    local spec = Question.current
    if not spec then return end
    local button = spec.buttons[index]
    if not button then return end
    Question.current = nil
    Question.frame:Hide()
    answered(spec, button.answer or "taken")
    if button.onClick then
        local ok, err = pcall(button.onClick)
        if not ok then log("Question %s: the button %s failed: %s", tostring(spec.id), tostring(index), tostring(err)) end
    end
    if not Question.current then showNext() end
end



local function newFrame(Look)
    if Look.HasTemplate(Look.GROUND_TEMPLATE) and Look.HasTemplate(Question.KEYS_TEMPLATE) then
        local ok, made = pcall(CreateFrame, "Frame", nil, UIParent, Look.GROUND_TEMPLATE .. "," .. Question.KEYS_TEMPLATE)
        if ok and made then
            Look.Ground(made, 32)
            return made
        end
    end
    return (Look.CreateGround("Frame", UIParent, 32))
end

local function build()
    local Look = FGPS.UI.Look
    local frame = newFrame(Look)
    frame:Hide()
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)


    frame:SetPoint("TOPLEFT", UIParent, "TOP", Question.WIDTH / 2 + 10, -135)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    local text = frame:CreateFontString(nil, "ARTWORK", Look.Font("row"))
    text:SetPoint("TOP", frame, "TOP", 0, -Question.PAD)
    text:SetJustifyH("CENTER")
    if text.SetWordWrap then text:SetWordWrap(true) end
    frame.text = text
    frame.buttons = {}
    for i = 1, Question.MAX_BUTTONS do
        local button = Look.Button(frame, "", Question.BUTTON_WIDTH, Question.BUTTON_HEIGHT)
        button:SetScript("OnClick", function() press(i) end)
        button:Hide()
        frame.buttons[i] = button
    end
    frame:EnableKeyboard(false)
    frame:SetScript("OnKeyDown", onKeyDown)
    frame:SetScript("OnShow", function(self) takeKeyboard(self) end)
    frame:SetScript("OnHide", function(self) self:EnableKeyboard(false) end)
    return frame
end

local function lay(frame, spec)
    local count = #spec.buttons
    local rowWidth = count * Question.BUTTON_WIDTH + (count - 1) * Question.BUTTON_GAP
    local width = max(Question.WIDTH, rowWidth + 2 * Question.PAD)
    frame.text:SetWidth(width - 30)
    frame.text:SetText(spec.text)
    local textHeight = frame.text:GetStringHeight() or 12
    local left = -rowWidth / 2
    for i, button in ipairs(frame.buttons) do
        local item = spec.buttons[i]
        button:ClearAllPoints()
        if item then
            button:SetText(item.label)
            button:SetPoint("BOTTOMLEFT", frame, "BOTTOM", left + (i - 1) * (Question.BUTTON_WIDTH + Question.BUTTON_GAP), Question.PAD)
            button:Show()
        else
            button:Hide()
        end
    end
    frame:SetSize(width, Question.PAD + textHeight + Question.PAD + Question.BUTTON_HEIGHT + Question.PAD)
end

local function closed(spec, how)
    answered(spec, "closed", how)
    if spec.onClose then
        local ok, err = pcall(spec.onClose, how)
        if not ok then log("Question %s: closing failed: %s", tostring(spec.id), tostring(err)) end
    end
end

local function show(spec)
    local frame = Question.frame
    if not frame then
        frame = build()
        Question.frame = frame
    end
    lay(frame, spec)
    rows[spec] = rows[spec] or note(spec)
    Question.current = spec
    frame:Show()
    if frame.Raise then frame:Raise() end
    takeKeyboard(frame)
end


showNext = function()
    local spec = table.remove(Question.waiting)
    if spec then show(spec) end
end



close = function(how, noNext)
    local spec = Question.current
    if not spec then return false end
    Question.current = nil
    if Question.frame then Question.frame:Hide() end
    closed(spec, how)
    if not noNext and not Question.current then showNext() end
    return true
end


local function dropWaiting(id, how)
    for i = #Question.waiting, 1, -1 do
        local spec = Question.waiting[i]
        if spec.id == id then
            table.remove(Question.waiting, i)
            closed(spec, how)
            return true
        end
    end
    return false
end








function Question.Ask(spec)
    if type(spec) ~= "table" or type(spec.id) ~= "string" or type(spec.text) ~= "string"
        or type(spec.buttons) ~= "table" then
        return false
    end
    local count = #spec.buttons
    if count < 1 or count > Question.MAX_BUTTONS then return false end
    if not (FGPS.UI.Look and UIParent and CreateFrame) then return false end

    dropWaiting(spec.id, "replaced")
    local showing = Question.current
    if showing and showing.waits and showing.id ~= spec.id then
        Question.current = nil
        Question.waiting[#Question.waiting + 1] = showing
    else
        close("replaced", true)
    end
    show(spec)
    return true
end



function Question.Close(id)
    local spec = Question.current
    if spec and spec.id == id then return close("withdrawn") end
    return dropWaiting(id, "withdrawn")
end


function Question.Showing()
    local spec = Question.current
    if not spec then return nil end
    return spec.id, spec.text
end



local function retake()
    local frame = Question.frame
    if frame then takeKeyboard(frame) end
end
if FGPS.Events then
    FGPS.Events:Register("COMBAT_STATE", function(_, fighting) if not fighting then retake() end end, Question)
    FGPS.Events:Register("WORLD_ENTERED", retake, Question)
end
