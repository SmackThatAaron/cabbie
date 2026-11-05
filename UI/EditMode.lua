

























local ADDON_NAME, FGPS = ...

local L = FGPS.L
local type, pairs, ipairs, tostring, pcall = type, pairs, ipairs, tostring, pcall

local EditMode = {
    entries = {},
    order = {},
    active = false,
    native = false,
    fallbackActive = false,
    selectedKey = nil,
    layoutName = "default",
    dialog = nil,
    editorBar = nil,
    templateBroken = false,
    initialised = false,
}
FGPS.UI.EditMode = EditMode

EditMode.DEFAULT_LAYOUT = "default"
EditMode.NATIVE_TEMPLATE = "EditModeSystemSelectionTemplate"
EditMode.NUDGE_STEP = 1
EditMode.NUDGE_STEP_FAST = 10

local HIGHLIGHT_COLOR = { 0.36, 0.64, 1.0, 1 }
local SELECTED_COLOR = { 1.0, 0.82, 0.20, 1 }
local NUDGE_KEYS = { UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }

local function Positions() return FGPS.UI.Positions end
local function Frames() return FGPS.UI.Frames end

local function inCombat()
    return InCombatLockdown and InCombatLockdown() or false
end




function EditMode.IsAvailable()
    return type(EditModeManagerFrame) == "table" and type(EventRegistry) == "table"
        and type(EventRegistry.RegisterCallback) == "function"
end


function EditMode.IsNativeIntegration()
    if not EditMode.IsAvailable() then return false end
    return not EditMode.fallbackActive
end

function EditMode.IsActive()
    return EditMode.active
end

function EditMode.GetLayoutName()
    if type(EditModeManagerFrame) == "table" and type(EditModeManagerFrame.GetActiveLayoutInfo) == "function" then
        local ok, info = pcall(EditModeManagerFrame.GetActiveLayoutInfo, EditModeManagerFrame)
        if ok and type(info) == "table" and type(info.layoutName) == "string" and info.layoutName ~= "" then
            return info.layoutName
        end
    end
    return EditMode.DEFAULT_LAYOUT
end




local wireOverlay

local function createPlainOverlay(frame)
    local o = CreateFrame("Frame", nil, frame)
    o.fgpsNative = false
    o.Fill = o:CreateTexture(nil, "BACKGROUND")
    o.Fill:SetAllPoints(o)
    o.Edges = {}
    local thickness = 2
    for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = o:CreateTexture(nil, "ARTWORK")
        if side == "TOP" or side == "BOTTOM" then
            edge:SetPoint(side .. "LEFT", o, side .. "LEFT", 0, 0)
            edge:SetPoint(side .. "RIGHT", o, side .. "RIGHT", 0, 0)
            edge:SetHeight(thickness)
        else
            edge:SetPoint("TOP" .. side, o, "TOP" .. side, 0, 0)
            edge:SetPoint("BOTTOM" .. side, o, "BOTTOM" .. side, 0, 0)
            edge:SetWidth(thickness)
        end
        o.Edges[i] = edge
    end
    o.Label = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    o.Label:SetPoint("CENTER", o, "CENTER", 0, 0)
    local frames = Frames()
    if frames then frames.SetFont(o.Label, frames.Skin(), "normal", true) end
    return o
end

local function paintPlainOverlay(overlay, color, fillAlpha, label)
    overlay.Fill:SetColorTexture(color[1], color[2], color[3], fillAlpha)
    for _, edge in ipairs(overlay.Edges) do edge:SetColorTexture(color[1], color[2], color[3], 1) end
    overlay.Label:SetText(label or "")
    overlay.Label:SetTextColor(1, 1, 1, 1)
end



local function createOverlay(entry)
    local frame = entry.frame
    local overlay
    if not EditMode.templateBroken then
        local ok, f = pcall(CreateFrame, "Frame", nil, frame, EditMode.NATIVE_TEMPLATE)
        if ok and type(f) == "table" and type(f.ShowHighlighted) == "function"
            and type(f.ShowSelected) == "function" and type(f.Hide) == "function" then
            overlay = f
            overlay.fgpsNative = true
            if type(f.SetSystem) == "function" then

                pcall(f.SetSystem, f, { GetSystemName = function() return entry.label end })
            end
        else
            EditMode.templateBroken = true
            if ok and type(f) == "table" and f.Hide then pcall(f.Hide, f) end
            if FGPS.Log then FGPS.Log:Debug("Edit Mode selection template unavailable; using plain overlays") end
        end
    end
    if not overlay then overlay = createPlainOverlay(frame) end
    wireOverlay(entry, overlay)
    return overlay
end


local function demoteOverlay(entry)
    EditMode.templateBroken = true
    if entry.overlay then
        pcall(entry.overlay.Hide, entry.overlay)
        pcall(entry.overlay.EnableMouse, entry.overlay, false)
    end
    entry.overlay = createPlainOverlay(entry.frame)
    wireOverlay(entry, entry.overlay)
    return entry.overlay
end

local function setOverlayState(entry, state)
    local overlay = entry.overlay
    if not overlay then return end
    if state == "hidden" then
        pcall(overlay.Hide, overlay)
        if overlay.EnableMouse then pcall(overlay.EnableMouse, overlay, false) end
        if overlay.EnableKeyboard then pcall(overlay.EnableKeyboard, overlay, false) end
        return
    end
    if overlay.fgpsNative then
        local fn = (state == "selected") and overlay.ShowSelected or overlay.ShowHighlighted
        local ok = pcall(fn, overlay)
        if not ok then
            overlay = demoteOverlay(entry)
        else

            if overlay.EnableMouse then pcall(overlay.EnableMouse, overlay, true) end
            return
        end
    end
    if state == "selected" then
        paintPlainOverlay(overlay, SELECTED_COLOR, 0.20, entry.label)
    else
        paintPlainOverlay(overlay, HIGHLIGHT_COLOR, entry.hover and 0.18 or 0.10, entry.label)
    end
    overlay:Show()
    if overlay.EnableMouse then pcall(overlay.EnableMouse, overlay, true) end
end

local function ensureOverlay(entry)
    if not entry.overlay then entry.overlay = createOverlay(entry) end
    return entry.overlay
end




local updateDialogAnchor



function EditMode.SaveEntry(entry, reason)
    local positions = Positions()
    if not positions then return nil end
    local record = positions.Save(entry.key, entry.frame, EditMode.layoutName)
    if record then positions.Apply(entry.frame, record, entry.positionOpts) end
    if entry.onPositionChanged then
        local ok, err = pcall(entry.onPositionChanged, entry.frame, reason, record)
        if not ok and FGPS.Log then FGPS.Log:Error("onPositionChanged for %s failed: %s", entry.key, tostring(err)) end
    end
    updateDialogAnchor()
    if EditMode.RefreshDialog then EditMode.RefreshDialog() end
    return record
end

function EditMode.OnDragStart(key)
    local entry = EditMode.entries[key]
    if not entry or not EditMode.active then return false end
    if EditMode.selectedKey ~= key then EditMode.Select(key) end
    entry.frame:SetMovable(true)
    if entry.frame.StartMoving then entry.frame:StartMoving() end
    entry.dragging = true
    return true
end

function EditMode.OnDragStop(key)
    local entry = EditMode.entries[key]
    if not entry or not entry.dragging then return nil end
    entry.dragging = false
    entry.frame:StopMovingOrSizing()
    return EditMode.SaveEntry(entry, "drag")
end


function EditMode.Nudge(key, dx, dy)
    local entry = EditMode.entries[key]
    local positions = Positions()
    if not entry or not positions then return nil end
    local frame = entry.frame
    local cx, cy = frame:GetCenter()
    if type(cx) ~= "number" or type(cy) ~= "number" then return nil end
    local es = frame:GetEffectiveScale() or 1
    local ues = UIParent:GetEffectiveScale() or 1
    local ratio = (es > 0 and ues > 0) and (es / ues) or 1
    local uw, uh = UIParent:GetSize()
    positions.AnchorCenter(frame, cx * ratio - uw / 2 + (dx or 0), cy * ratio - uh / 2 + (dy or 0))
    return EditMode.SaveEntry(entry, "nudge")
end


local function overlayKeyDown(entry, overlay, key)
    local handled = false
    local vec = NUDGE_KEYS[key]
    if vec and EditMode.selectedKey == entry.key then
        local fast = IsShiftKeyDown and IsShiftKeyDown()
        local step = fast and EditMode.NUDGE_STEP_FAST or EditMode.NUDGE_STEP
        EditMode.Nudge(entry.key, vec[1] * step, vec[2] * step)
        handled = true
    end
    if overlay.SetPropagateKeyboardInput and not inCombat() then
        pcall(overlay.SetPropagateKeyboardInput, overlay, not handled)
    end
    return handled
end

wireOverlay = function(entry, overlay)
    overlay:ClearAllPoints()
    overlay:SetAllPoints(entry.frame)
    overlay:EnableMouse(true)
    overlay:RegisterForDrag("LeftButton")
    if overlay.SetToplevel then pcall(overlay.SetToplevel, overlay, true) end
    if overlay.SetFrameLevel and entry.frame.GetFrameLevel then
        pcall(overlay.SetFrameLevel, overlay, (entry.frame:GetFrameLevel() or 1) + 50)
    end
    overlay:SetScript("OnMouseDown", function() EditMode.Select(entry.key) end)
    overlay:SetScript("OnDragStart", function() EditMode.OnDragStart(entry.key) end)
    overlay:SetScript("OnDragStop", function() EditMode.OnDragStop(entry.key) end)
    overlay:SetScript("OnEnter", function(self)
        entry.hover = true
        if self.fgpsNative and self.ShowEditInstructions then
            pcall(self.ShowEditInstructions, self, true)
        elseif EditMode.selectedKey ~= entry.key then
            setOverlayState(entry, "highlight")
        end
    end)
    overlay:SetScript("OnLeave", function(self)
        entry.hover = false
        if self.fgpsNative and self.ShowEditInstructions then
            pcall(self.ShowEditInstructions, self, false)
        elseif EditMode.selectedKey ~= entry.key then
            setOverlayState(entry, "highlight")
        end
    end)
    overlay:SetScript("OnKeyDown", function(self, key) overlayKeyDown(entry, self, key) end)
    if overlay.EnableKeyboard then pcall(overlay.EnableKeyboard, overlay, false) end
    overlay:Hide()
end











local DIALOG_WIDTH = 390
local DIALOG_PAD = 20
local TITLE_TOP = 15
local TITLE_HEIGHT = 20
local ROW_HEIGHT = 32
local LABEL_WIDTH = 100
local CONTROL_WIDTH = 200
local BUTTON_WIDTH, BUTTON_HEIGHT = 180, 28

local function Look() return FGPS.UI.Look end
local floor = math.floor

local function safeGet(setting)
    if type(setting.get) ~= "function" then return setting.value end
    local ok, value = pcall(setting.get)
    if ok then return value end
    return nil
end

local function safeSet(setting, value, entry)
    if type(setting.set) ~= "function" then return end
    local ok, err = pcall(setting.set, value)
    if not ok and FGPS.Log then FGPS.Log:Error("Edit Mode setting '%s' failed: %s", tostring(setting.label), tostring(err)) end
    if entry and entry.onSettingChanged then pcall(entry.onSettingChanged, entry.frame, setting, value) end
    updateDialogAnchor()
end



local function stepValue(setting, value)
    local minV, maxV, step = setting.min or 0, setting.max or 1, setting.step or 0.01
    value = tonumber(value) or minV
    if step > 0 then value = minV + floor((value - minV) / step + 0.5) * step end
    value = floor(value * 1e6 + 0.5) / 1e6
    if value < minV then value = minV elseif value > maxV then value = maxV end
    return value
end

local function formatValue(setting, value)
    local fmt = setting.format or "%.2f"
    if type(fmt) == "function" then return fmt(value) end
    return string.format(fmt, value)
end


local function sliderMoved(row, value)
    if row.fgpsSilent or not row.fgpsSetting then return end
    value = stepValue(row.fgpsSetting, value)
    if value == row.fgpsValue then return end
    row.fgpsValue = value
    if row.fgpsOnChange then row.fgpsOnChange(value) end
end



local function createSlider(row)
    local slider = Look().StepperSlider(row, CONTROL_WIDTH)
    if slider then
        slider.fgpsNative = true
        local mixin = MinimalSliderWithSteppersMixin
        local event = type(mixin) == "table" and type(mixin.Event) == "table" and mixin.Event.OnValueChanged or "OnValueChanged"
        slider:RegisterCallback(event, function(_, value) sliderMoved(row, value) end, row)
    else
        slider = Frames().CreateSlider(row, { width = CONTROL_WIDTH - 40 })
        slider:SetOnChange(function(_, value) sliderMoved(row, value) end)
    end
    slider:SetPoint("LEFT", row.Label, "RIGHT", 5, 0)
    return slider
end




local function showSliderValue(row, value, init)
    local setting, slider = row.fgpsSetting, row.Slider
    value = stepValue(setting, value)
    row.fgpsSilent = true
    if slider.fgpsNative then
        if init then
            local minV, maxV, step = setting.min or 0, setting.max or 1, setting.step or 0.01
            local steps = math.max(1, floor((maxV - minV) / step + 0.5))
            local labels = type(MinimalSliderWithSteppersMixin) == "table" and MinimalSliderWithSteppersMixin.Label
            local right = type(labels) == "table" and labels.Right or 2
            local ok, err = pcall(slider.Init, slider, value, minV, maxV, steps,
                { [right] = function(v) return formatValue(setting, stepValue(setting, v)) end })
            if not ok and FGPS.Log then FGPS.Log:Error("Edit Mode slider '%s' failed: %s", tostring(setting.label), tostring(err)) end
        else
            pcall(slider.SetValue, slider, value)
        end
    else
        if init then
            slider.fgpsMin, slider.fgpsMax, slider.fgpsStep = setting.min or 0, setting.max or 1, setting.step or 0.01
            slider:SetMinMaxValues(slider.fgpsMin, slider.fgpsMax)
            if slider.SetValueStep then slider:SetValueStep(slider.fgpsStep) end
            slider.fgpsFormat = function(v) return formatValue(setting, v) end
        end
        slider:SetValueSilent(value)
    end
    row.fgpsValue = value
    row.fgpsSilent = false
end



local function createCheckbox(row)
    local look = Look()
    local check = look.CheckButton(row, "")
    check:SetSize(32, 32)
    check:SetPoint("LEFT", row, "LEFT", -5, 0)
    local label = check.Label
    if label then
        if label.SetFontObject then label:SetFontObject(look.Font("setting")) end
        label:ClearAllPoints()
        label:SetPoint("LEFT", check, "RIGHT", 5, 0)
    end
    check:SetScript("OnClick", function(self)
        if row.fgpsOnChange then row.fgpsOnChange(self:GetChecked() and true or false) end
    end)
    return check
end


local function settingColor(setting, value)
    local look = Look()
    local r, g, b = look.HexColor(value)
    if not r then r, g, b = look.HexColor(setting.default) end
    if not r then r, g, b = 1, 1, 1 end
    return r, g, b
end





local function pickRowColor(row)
    local setting, onChange = row.fgpsSetting, row.fgpsOnChange
    local look = Look()
    if not (setting and onChange and look.CanPickColor()) then return end
    local before = safeGet(setting)
    local r, g, b = settingColor(setting, before)
    look.PickColor(r, g, b, function(nr, ng, nb)
        local hex = look.ColorHex(nr, ng, nb)
        if hex then onChange(hex) end
    end, function() onChange(before) end)
end

local function createSwatch(row)
    local swatch = Look().ColorSwatch(row)
    swatch:SetPoint("LEFT", row.Label, "RIGHT", 5, 0)
    swatch:SetScript("OnClick", function() pickRowColor(row) end)
    Frames().Tooltip(swatch, function()
        return Look().CanPickColor() and L["Click to choose a colour"] or L["This client has no colour picker."]
    end)
    return swatch
end





local PICTURE_SIZE, PICTURE_GAP = 32, 6

local function ensurePictures(row, count)
    row.Pictures = row.Pictures or {}
    for i = #row.Pictures + 1, count do
        local button = Look().PictureButton(row, PICTURE_SIZE)
        button:SetPoint("LEFT", row.Label, "RIGHT", 5 + (i - 1) * (PICTURE_SIZE + PICTURE_GAP), 0)
        button:SetScript("OnClick", function(self)
            if row.fgpsOnChange and self.fgpsValue ~= nil then row.fgpsOnChange(self.fgpsValue) end
        end)
        Frames().Tooltip(button, function(self) return self.fgpsLabel end)
        row.Pictures[i] = button
    end
end

local function showPictures(row, setting)
    local options = setting.options or {}
    ensurePictures(row, #options)
    local value = safeGet(setting)
    for i, option in ipairs(options) do
        local button = row.Pictures[i]
        button.fgpsValue, button.fgpsLabel = option.value, option.label
        local texture, r, g, b = option.texture, 1, 1, 1
        if type(setting.picture) == "function" then
            local ok, t, pr, pg, pb = pcall(setting.picture, option.value)
            if ok and t then texture, r, g, b = t, pr or 1, pg or 1, pb or 1 end
        end
        if button.fgpsTexture ~= texture then
            button.fgpsTexture = texture
            button.Icon:SetTexture(texture)
        end
        button.Icon:SetVertexColor(r, g, b)
        button:SetChosen(option.value == value)
        button:Show()
    end
    for i = #options + 1, #row.Pictures do row.Pictures[i]:Hide() end
end

local function createRow(dialog, index)
    local look = Look()
    local row = CreateFrame("Frame", nil, dialog)
    row:SetHeight(ROW_HEIGHT)
    row.Label = row:CreateFontString(nil, "ARTWORK", look.Font("setting"))
    row.Label:SetSize(LABEL_WIDTH, ROW_HEIGHT)
    row.Label:SetPoint("LEFT", row, "LEFT", 0, 0)
    if row.Label.SetJustifyH then row.Label:SetJustifyH("LEFT") end
    row.Slider = createSlider(row)
    row.Dropdown = Frames().CreateDropdown(row, { options = {}, width = CONTROL_WIDTH })
    row.Dropdown:SetPoint("LEFT", row.Label, "RIGHT", 5, 0)
    row.Checkbox = createCheckbox(row)
    row.Swatch = createSwatch(row)
    dialog.rows[index] = row
    return row
end


local function showRowValue(row, setting)
    if setting.type == "slider" then
        showSliderValue(row, safeGet(setting), false)
    elseif setting.type == "dropdown" then
        row.Dropdown:SetValue(safeGet(setting))
    elseif setting.type == "checkbox" then
        row.Checkbox:SetChecked(safeGet(setting) and true or false)
    elseif setting.type == "color" then
        row.Swatch:SetColorRGB(settingColor(setting, safeGet(setting)))
    elseif setting.type == "pictures" then
        showPictures(row, setting)
    end
end

local ROW_KINDS = { slider = true, dropdown = true, checkbox = true, color = true, pictures = true }

local function configureRow(row, setting, entry)
    row.Slider:Hide()
    row.Dropdown:Hide()
    row.Checkbox:Hide()
    row.Swatch:Hide()
    for _, button in ipairs(row.Pictures or {}) do button:Hide() end
    row.Label:SetText("")
    row.fgpsSetting = setting
    row.fgpsOnChange = function(value) safeSet(setting, value, entry) end
    local kind = setting.type
    if kind == "slider" then
        row.Label:SetText(setting.label or "")
        showSliderValue(row, safeGet(setting), true)
        row.Slider:Show()
    elseif kind == "dropdown" then
        row.Label:SetText(setting.label or "")
        local dd = row.Dropdown
        dd:SetOptions(setting.options or {})
        dd:SetValue(safeGet(setting))
        dd:SetOnChange(function(_, value) row.fgpsOnChange(value) end)
        dd:Show()
    elseif kind == "checkbox" then
        local check = row.Checkbox
        if check.Label then check.Label:SetText(setting.label or "") end
        check:SetChecked(safeGet(setting) and true or false)
        check:Show()
    elseif kind == "color" then

        row.Label:SetText(setting.label or "")
        local swatch = row.Swatch
        swatch:SetColorRGB(settingColor(setting, safeGet(setting)))
        if Look().CanPickColor() then swatch:Enable() else swatch:Disable() end
        swatch:Show()
    elseif kind == "pictures" then
        row.Label:SetText(setting.label or "")
        showPictures(row, setting)
    end
    row:SetHeight(ROW_KINDS[kind] and ROW_HEIGHT or 0)
    row:Show()
end

local function ensureDialog()
    if EditMode.dialog then return EditMode.dialog end
    local look = Look()
    if not (look and Frames()) then return nil end
    local dialog, how = look.EditPanel(UIParent)

    dialog:Hide()
    dialog.fgpsLook = how
    dialog:SetSize(DIALOG_WIDTH, 160)
    dialog:SetFrameStrata("DIALOG")
    if dialog.SetToplevel then dialog:SetToplevel(true) end
    dialog:SetClampedToScreen(true)
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", function(self)
        self.fgpsMoving = true
        self:StartMoving()
    end)
    dialog:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self.fgpsMoving = false
        self.fgpsPlaced = true
    end)
    dialog:SetScript("OnHide", function()
        Frames().CloseMenus()
        if EditMode.selectedKey and not EditMode.closingDialog then EditMode.ClearSelection(true) end
    end)
    dialog.Title = dialog:CreateFontString(nil, "ARTWORK", look.Font("panelTitle"))
    dialog.Title:SetPoint("TOP", dialog, "TOP", 0, -TITLE_TOP)
    dialog.Close = look.CloseButton(dialog, function() dialog:Hide() end)
    dialog.Close:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", 0, 0)
    dialog.rows = {}
    dialog.Hint = dialog:CreateFontString(nil, "ARTWORK", look.Font("hint"))
    if dialog.Hint.SetJustifyH then dialog.Hint:SetJustifyH("LEFT") end
    if dialog.Hint.SetWordWrap then dialog.Hint:SetWordWrap(true) end
    dialog.Hint:SetText(L["Drag to move. The arrow keys move the selection a little (with Shift, more)."])
    dialog.Reset = look.Button(dialog, L["Reset to default"], BUTTON_WIDTH, BUTTON_HEIGHT)
    dialog.Reset:SetScript("OnClick", function()
        if EditMode.selectedKey then EditMode.ResetEntry(EditMode.selectedKey) end
    end)
    EditMode.dialog = dialog
    return dialog
end

local function buildDialog(entry)
    local dialog = ensureDialog()
    if not dialog then return nil end
    dialog.Title:SetText(entry.label or "")
    local y = TITLE_TOP + TITLE_HEIGHT + 12
    local count = 0
    for _, setting in ipairs(entry.settings or {}) do
        count = count + 1
        local row = dialog.rows[count] or createRow(dialog, count)
        configureRow(row, setting, entry)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", dialog, "TOPLEFT", DIALOG_PAD, -y)
        row:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -DIALOG_PAD, -y)
        y = y + (row:GetHeight() or 0) + 2
    end
    for i = count + 1, #dialog.rows do dialog.rows[i]:Hide() end
    y = y + 10
    dialog.Hint:ClearAllPoints()
    dialog.Hint:SetPoint("TOPLEFT", dialog, "TOPLEFT", DIALOG_PAD, -y)
    dialog.Hint:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -DIALOG_PAD, -y)
    dialog.Hint:SetHeight(28)
    y = y + 32
    dialog.Reset:ClearAllPoints()
    dialog.Reset:SetPoint("TOP", dialog, "TOP", 0, -y)
    y = y + BUTTON_HEIGHT + DIALOG_PAD
    dialog:SetHeight(y)
    return dialog
end



local function refreshDialogValues()
    local dialog = EditMode.dialog
    local entry = EditMode.selectedKey and EditMode.entries[EditMode.selectedKey]
    if not dialog or not entry or not dialog:IsShown() then return end
    for i, setting in ipairs(entry.settings or {}) do
        local row = dialog.rows[i]
        if row then showRowValue(row, setting) end
    end
end
EditMode.RefreshDialog = refreshDialogValues



updateDialogAnchor = function()
    local dialog = EditMode.dialog
    local entry = EditMode.selectedKey and EditMode.entries[EditMode.selectedKey]
    if not dialog or not entry or dialog.fgpsMoving or dialog.fgpsPlaced then return end
    local frame = entry.frame
    local right = frame.GetRight and frame:GetRight()
    local es = frame:GetEffectiveScale() or 1
    local ues = UIParent:GetEffectiveScale() or 1
    local ratio = (es > 0 and ues > 0) and (es / ues) or 1
    local uw = UIParent:GetWidth() or 0
    dialog:ClearAllPoints()
    if type(right) == "number" and (right * ratio + 12 + DIALOG_WIDTH) > uw then
        dialog:SetPoint("TOPRIGHT", frame, "TOPLEFT", -12, 0)
    else
        dialog:SetPoint("TOPLEFT", frame, "TOPRIGHT", 12, 0)
    end
end




function EditMode.Select(key)
    local entry = EditMode.entries[key]
    if not entry or not EditMode.active then return false end
    if EditMode.selectedKey == key then return true end
    local previous = EditMode.selectedKey and EditMode.entries[EditMode.selectedKey]
    if previous then
        setOverlayState(previous, "highlight")
        if previous.overlay and previous.overlay.EnableKeyboard then pcall(previous.overlay.EnableKeyboard, previous.overlay, false) end
    end
    EditMode.selectedKey = key
    ensureOverlay(entry)
    setOverlayState(entry, "selected")
    entry.frame:SetMovable(true)
    if entry.overlay.EnableKeyboard and not inCombat() then pcall(entry.overlay.EnableKeyboard, entry.overlay, true) end
    local dialog = buildDialog(entry)
    if dialog then
        dialog.fgpsPlaced = false
        updateDialogAnchor()
        dialog:Show()
    end
    return true
end

function EditMode.ClearSelection(keepDialogHidden)
    local key = EditMode.selectedKey
    if not key then return end
    local entry = EditMode.entries[key]
    EditMode.selectedKey = nil
    if entry then
        if entry.dragging then EditMode.OnDragStop(key) end
        if EditMode.active then setOverlayState(entry, "highlight") end
        if entry.overlay and entry.overlay.EnableKeyboard then pcall(entry.overlay.EnableKeyboard, entry.overlay, false) end
    end
    if EditMode.dialog and not keepDialogHidden then
        EditMode.closingDialog = true
        EditMode.dialog:Hide()
        EditMode.closingDialog = false
    end
end

function EditMode.GetSelected()
    return EditMode.selectedKey
end



function EditMode.ResetEntry(key)
    local entry = EditMode.entries[key]
    if not entry then return false end
    for _, setting in ipairs(entry.settings or {}) do
        if setting.default ~= nil then safeSet(setting, setting.default, entry) end
    end
    local positions = Positions()
    if positions then positions.Reset(key, EditMode.layoutName) end
    EditMode.ApplyEntryPosition(entry)
    if entry.onPositionChanged then pcall(entry.onPositionChanged, entry.frame, "reset", nil) end
    if EditMode.selectedKey == key then
        buildDialog(entry)
        updateDialogAnchor()
    end
    return true
end






function EditMode.ApplyEntryPosition(entry)
    if type(entry.applyPosition) == "function" then
        local ok, err = pcall(entry.applyPosition, entry.frame, EditMode.layoutName)
        if not ok and FGPS.Log then FGPS.Log:Error("applyPosition for %s failed: %s", entry.key, tostring(err)) end
        return
    end
    local positions = Positions()
    if positions then
        positions.Restore(entry.key, entry.frame, entry.defaultPosition, EditMode.layoutName, entry.positionOpts)
    end
end




local function entryAvailable(entry)
    if type(entry.available) ~= "function" then return true end
    local ok, yes = pcall(entry.available)
    if not ok then return true end
    return yes and true or false
end

local function showEntry(entry)
    local frame = entry.frame
    if not frame:IsShown() then frame:Show() end
    frame:SetMovable(true)
    ensureOverlay(entry)
    setOverlayState(entry, EditMode.selectedKey == entry.key and "selected" or "highlight")
end

local function hideEntryOverlay(entry)


    if entry.dragging then EditMode.OnDragStop(entry.key) end

    if EditMode.selectedKey == entry.key then
        EditMode.selectedKey = nil
        if EditMode.dialog then
            EditMode.closingDialog = true
            EditMode.dialog:Hide()
            EditMode.closingDialog = false
        end
    end
    ensureOverlay(entry)
    setOverlayState(entry, "hidden")
end

local function enterEntry(entry)
    local frame = entry.frame

    if not entry.editEntered then
        entry.wasMouseEnabled = frame:IsMouseEnabled() and true or false
        entry.wasShown = frame:IsShown() and true or false
        entry.editEntered = true
    end
    if entry.onEditModeEnter then
        local ok, err = pcall(entry.onEditModeEnter, frame)
        if not ok and FGPS.Log then FGPS.Log:Error("onEditModeEnter for %s failed: %s", entry.key, tostring(err)) end
    end
    if not entryAvailable(entry) then
        hideEntryOverlay(entry)
        return
    end
    showEntry(entry)
end

local function refreshAvailability()
    if not EditMode.active then return end
    for _, key in ipairs(EditMode.order) do
        local entry = EditMode.entries[key]
        if entry and entry.available then
            if entryAvailable(entry) then
                if not entry.overlay or not entry.overlay:IsShown() then showEntry(entry) end
            else
                hideEntryOverlay(entry)
            end
        end
    end
end

local function exitEntry(entry)
    local frame = entry.frame
    entry.editEntered = nil
    if entry.dragging then EditMode.OnDragStop(entry.key) end
    frame:StopMovingOrSizing()
    frame:SetMovable(false)
    frame:EnableMouse(entry.wasMouseEnabled and true or false)
    setOverlayState(entry, "hidden")
    if entry.onEditModeExit then
        local ok, err = pcall(entry.onEditModeExit, frame)
        if not ok and FGPS.Log then FGPS.Log:Error("onEditModeExit for %s failed: %s", entry.key, tostring(err)) end
    elseif not entry.wasShown then
        frame:Hide()
    end
end







function EditMode.Register(frame, opts)
    assert(type(frame) == "table", "EditMode.Register: frame is required")
    assert(type(opts) == "table" and type(opts.key) == "string" and opts.key ~= "", "EditMode.Register: opts.key is required")
    local key = opts.key
    local entry = EditMode.entries[key]
    if not entry then
        entry = { key = key }
        EditMode.entries[key] = entry
        EditMode.order[#EditMode.order + 1] = key
    elseif entry.frame ~= frame and entry.overlay then
        pcall(entry.overlay.Hide, entry.overlay)
        entry.overlay = nil
    end
    entry.frame = frame
    entry.label = opts.label or key
    entry.defaultPosition = opts.defaultPosition
    entry.settings = opts.settings
    entry.onPositionChanged = opts.onPositionChanged
    entry.applyPosition = opts.applyPosition
    entry.available = opts.available
    entry.onEditModeEnter = opts.onEditModeEnter
    entry.onEditModeExit = opts.onEditModeExit
    entry.onSettingChanged = opts.onSettingChanged
    entry.positionOpts = opts.positionOpts
    frame.fgpsEditKey = key
    EditMode.ApplyEntryPosition(entry)
    if EditMode.active then enterEntry(entry) end
    return entry
end

function EditMode.Unregister(key)
    local entry = EditMode.entries[key]
    if not entry then return end
    if EditMode.selectedKey == key then EditMode.ClearSelection() end
    if EditMode.active then exitEntry(entry) end
    EditMode.entries[key] = nil
    for i = #EditMode.order, 1, -1 do
        if EditMode.order[i] == key then table.remove(EditMode.order, i) end
    end
    local positions = Positions()
    if positions then positions.Unregister(key) end
end

function EditMode.GetEntry(key)
    return EditMode.entries[key]
end




local showEditorBar, hideEditorBar

function EditMode.Enter(native)
    if EditMode.active then


        if native and not EditMode.native then
            EditMode.native = true
            EditMode.fallbackActive = false
            hideEditorBar()
            return true
        end
        return false
    end
    EditMode.active = true
    EditMode.native = native and true or false
    EditMode.fallbackActive = not EditMode.native
    EditMode.layoutName = EditMode.GetLayoutName()
    for _, key in ipairs(EditMode.order) do
        local entry = EditMode.entries[key]
        if entry then
            local ok, err = pcall(enterEntry, entry)
            if not ok and FGPS.Log then FGPS.Log:Error("Edit Mode enter for %s failed: %s", key, tostring(err)) end
        end
    end
    if not EditMode.native then showEditorBar() end
    return true
end

function EditMode.Exit()
    if not EditMode.active then return false end
    EditMode.ClearSelection()
    for _, key in ipairs(EditMode.order) do
        local entry = EditMode.entries[key]
        if entry then
            local ok, err = pcall(exitEntry, entry)
            if not ok and FGPS.Log then FGPS.Log:Error("Edit Mode exit for %s failed: %s", key, tostring(err)) end
        end
    end
    hideEditorBar()
    EditMode.active = false
    EditMode.native = false
    EditMode.fallbackActive = false
    return true
end


function EditMode.RefreshLayout()
    local name = EditMode.GetLayoutName()
    if name == EditMode.layoutName then return false end
    EditMode.layoutName = name
    for _, key in ipairs(EditMode.order) do
        local entry = EditMode.entries[key]
        if entry then EditMode.ApplyEntryPosition(entry) end
    end
    if EditMode.selectedKey then updateDialogAnchor() end
    return true
end




local function editorKeyDown(self, key)
    if key == "ESCAPE" then
        if self.SetPropagateKeyboardInput and not inCombat() then pcall(self.SetPropagateKeyboardInput, self, false) end
        EditMode.Exit()
    elseif self.SetPropagateKeyboardInput and not inCombat() then
        pcall(self.SetPropagateKeyboardInput, self, true)
    end
end

local function applyEditorBarSkin(bar, skin)
    local frames = Frames()
    frames.ApplyBackdrop(bar, skin.backdrop, skin.colors.bg, skin.colors.accent)
    bar:SetAlpha(skin.panelAlpha or 1)
end

showEditorBar = function()
    local frames = Frames()
    if not frames then return end
    local bar = EditMode.editorBar
    if not bar then
        bar = frames.CreateBackdropFrame("Frame", UIParent)
        bar:SetSize(520, 36)
        bar:SetPoint("TOP", UIParent, "TOP", 0, -40)
        bar:SetFrameStrata("DIALOG")
        bar:SetToplevel(true)
        bar:EnableMouse(true)
        bar.Text = frames.CreateLabel(bar, L["Move Cabbie's arrow. The arrow keys move the selection a little (with Shift, more)."],
            { kind = "small", color = "text" })
        bar.Text:SetPoint("LEFT", bar, "LEFT", 10, 0)
        bar.Done = frames.CreateButton(bar, L["Done"], function() EditMode.Exit() end, { width = 70, primary = true })
        bar.Done:SetPoint("RIGHT", bar, "RIGHT", -8, 0)
        bar:SetScript("OnKeyDown", editorKeyDown)
        frames.Register(bar, applyEditorBarSkin)
        EditMode.editorBar = bar
    end
    bar:Show()
    if bar.EnableKeyboard and not inCombat() then bar:EnableKeyboard(true) end
end

hideEditorBar = function()
    local bar = EditMode.editorBar
    if not bar then return end
    if bar.EnableKeyboard then bar:EnableKeyboard(false) end
    bar:Hide()
end


function EditMode.ToggleEditor()
    if EditMode.active then
        if EditMode.native then return true end
        EditMode.Exit()
        return false
    end
    if inCombat() then
        FGPS:Print(L["The layout editor cannot be opened during combat."])
        return false
    end
    EditMode.Enter(false)
    return true
end

local function slashLayout()
    if EditMode.active and EditMode.native then
        FGPS:Print(L["Edit Mode is open; move Cabbie's arrow there."])
        return
    end
    local nowActive = EditMode.ToggleEditor()
    if nowActive then
        FGPS:Print(L["Layout editor opened. Drag to move things, then press Done or Escape."])
    else
        FGPS:Print(L["Layout editor closed."])
    end
end










local function setSelectedKeyboard(enabled)
    local entry = EditMode.selectedKey and EditMode.entries[EditMode.selectedKey]
    local overlay = entry and entry.overlay
    if overlay and overlay.EnableKeyboard then pcall(overlay.EnableKeyboard, overlay, enabled) end
end

local function onCombatState(_, inCombatNow)
    if inCombatNow and EditMode.active and not EditMode.native then EditMode.Exit() end
    refreshAvailability()
    if inCombatNow then
        if EditMode.editorBar and EditMode.editorBar.EnableKeyboard then EditMode.editorBar:EnableKeyboard(false) end
        setSelectedKeyboard(false)
    elseif EditMode.active then
        local bar = EditMode.editorBar
        if bar and bar.EnableKeyboard and bar:IsShown() then bar:EnableKeyboard(true) end
        setSelectedKeyboard(true)
    end
end

local function onLayoutsUpdated()
    EditMode.RefreshLayout()
end

function EditMode:Init()
    EditMode.layoutName = EditMode.GetLayoutName()
    if EditMode.initialised then return EditMode end
    EditMode.initialised = true
    if EditMode.IsAvailable() then
        EventRegistry:RegisterCallback("EditMode.Enter", function() EditMode.Enter(true) end, EditMode)
        EventRegistry:RegisterCallback("EditMode.Exit", function() EditMode.Exit() end, EditMode)
        EventRegistry:RegisterCallback("EditMode.SavedLayouts", onLayoutsUpdated, EditMode)
    end
    if FGPS.Events then
        FGPS.Events:RegisterWoW("EDIT_MODE_LAYOUTS_UPDATED", onLayoutsUpdated, EditMode)
        FGPS.Events:Register("COMBAT_STATE", onCombatState, EditMode)
        FGPS.Events:Register("SETTINGS_CHANGED", function()
            refreshDialogValues()
            refreshAvailability()
        end, EditMode)
    end
    if FGPS.Slash and FGPS.Slash.Register then
        FGPS.Slash.Register("layout", slashLayout, L["Move Cabbie's arrow on the screen (when the game has no Edit Mode)"])
    end

    if EditMode.IsAvailable() and type(EditModeManagerFrame.IsEditModeActive) == "function" then
        local ok, activeNow = pcall(EditModeManagerFrame.IsEditModeActive, EditModeManagerFrame)
        if ok and activeNow then EditMode.Enter(true) end
    end
    return EditMode
end
