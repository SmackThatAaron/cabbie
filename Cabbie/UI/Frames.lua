












local ADDON_NAME, FGPS = ...

local L = FGPS.L
local type, pairs, ipairs, tostring, tonumber, select = type, pairs, ipairs, tostring, tonumber, select
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local Frames = {
    registry = setmetatable({}, { __mode = "k" }),
    windows = {},
    initialised = false,
    openMenu = nil,
}
FGPS.UI.Frames = Frames

local WHITE = "Interface\\Buttons\\WHITE8x8"
Frames.MIN_CLOSE_SIZE = 20
local CLOSE_UP = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up"
local CLOSE_DOWN = "Interface\\Buttons\\UI-Panel-MinimizeButton-Down"
local CLOSE_HIGHLIGHT = "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight"
local GRIP_UP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"
local GRIP_DOWN = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down"
local GRIP_HIGHLIGHT = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight"
local DROPDOWN_ARROW = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up"
local SLIDER_THUMB = "Interface\\Buttons\\UI-SliderBar-Button-Horizontal"
local CHECK_UP = "Interface\\Buttons\\UI-CheckBox-Up"
local CHECK_DOWN = "Interface\\Buttons\\UI-CheckBox-Down"
local CHECK_HIGHLIGHT = "Interface\\Buttons\\UI-CheckBox-Highlight"
local CHECK_CHECK = "Interface\\Buttons\\UI-CheckBox-Check"


local FALLBACK_SKIN = {
    name = "fallback", font = "Fonts\\FRIZQT__.TTF", titleFont = "Fonts\\FRIZQT__.TTF",
    fontSize = 12, smallFontSize = 10, largeFontSize = 16, titleFontSize = 12,
    colors = { bg = { 0.05, 0.05, 0.06, 0.85 }, border = { 0.3, 0.3, 0.3, 1 }, text = { 1, 1, 1, 1 },
               textDim = { 0.7, 0.7, 0.7, 1 }, title = { 1, 1, 1, 1 }, accent = { 0.3, 0.7, 1, 1 },
               routeVerified = { 0.3, 0.7, 1, 1 }, routeUnverified = { 1, 0.6, 0.2, 1 }, arrow = { 1, 1, 1, 1 },
               button = { 0.15, 0.15, 0.15, 1 }, buttonHover = { 0.25, 0.25, 0.25, 1 }, buttonBorder = { 0.35, 0.35, 0.35, 1 },
               selection = { 0.3, 0.7, 1, 0.25 }, highlight = { 1, 1, 1, 0.07 }, editBox = { 0, 0, 0, 0.9 },
               titleBar = { 0.1, 0.1, 0.1, 1 } },
    backdrop = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } },
    buttonBackdrop = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } },
    arrowTexture = "Interface\\AddOns\\Cabbie\\Media\\arrow_minimal", arrowSize = 40,
    ringTexture = "Interface\\AddOns\\Cabbie\\Media\\ring",
    panelAlpha = 0.9, titleHeight = 20, inset = 8, titleBarStyle = "flat", sliderStyle = "flat",
}




function Frames.Skin()
    local skins = FGPS.UI.Skins
    if skins and skins.Current then
        local ok, skin = pcall(skins.Current)
        if ok and type(skin) == "table" then return skin end
    end
    return FALLBACK_SKIN
end

local function rgba(color, alphaOverride)
    if type(color) ~= "table" then return 1, 1, 1, alphaOverride or 1 end
    return color[1] or 1, color[2] or 1, color[3] or 1, alphaOverride or color[4] or 1
end
Frames.RGBA = rgba

local function color(skin, name)
    local c = skin.colors and skin.colors[name]
    if c then return c end
    return FALLBACK_SKIN.colors[name] or FALLBACK_SKIN.colors.text
end


function Frames.SetFont(fs, skin, kind, outline)
    skin = skin or Frames.Skin()
    local path, size = skin.font, skin.fontSize
    if kind == "small" then size = skin.smallFontSize
    elseif kind == "large" then size = skin.largeFontSize
    elseif kind == "title" then path, size = skin.titleFont or skin.font, skin.titleFontSize end
    local db = FGPS.DB and FGPS.DB.settings
    if db and db.textSize == "large" then size = (size or 12) + 2 end
    if fs.SetFont then fs:SetFont(path or FALLBACK_SKIN.font, size or 12, outline and "OUTLINE" or "") end
end

local function setTextColor(fs, skin, name)
    if fs.SetTextColor then fs:SetTextColor(rgba(color(skin, name))) end
end



local function createBackdropFrame(frameType, parent, name)
    local ok, f = pcall(CreateFrame, frameType, name, parent, "BackdropTemplate")
    if ok and f and f.SetBackdrop then return f end
    f = CreateFrame(frameType, name, parent)
    return f
end
Frames.CreateBackdropFrame = createBackdropFrame

local function applyBackdrop(frame, backdrop, bg, border)
    if frame.SetBackdrop then
        if frame.fgpsBackdrop ~= backdrop then
            frame:SetBackdrop(backdrop)
            frame.fgpsBackdrop = backdrop
        end
        if frame.SetBackdropColor then frame:SetBackdropColor(rgba(bg)) end
        if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(rgba(border)) end
    else
        if not frame.fgpsBgTexture then
            frame.fgpsBgTexture = frame:CreateTexture(nil, "BACKGROUND")
            frame.fgpsBgTexture:SetAllPoints(frame)
        end
        frame.fgpsBgTexture:SetColorTexture(rgba(bg))
    end
end
Frames.ApplyBackdrop = applyBackdrop

local function isDescendant(widget, ancestor)
    local node = widget
    local guard = 0
    while node and guard < 64 do
        if node == ancestor then return true end
        node = node.GetParent and node:GetParent() or nil
        guard = guard + 1
    end
    return false
end






function Frames.Register(widget, applyFn)
    applyFn = applyFn or widget.fgpsApplySkin
    if type(applyFn) ~= "function" then return widget end
    widget.fgpsApplySkin = applyFn
    Frames.registry[widget] = applyFn
    local ok, err = pcall(applyFn, widget, Frames.Skin())
    if not ok and FGPS.Log then FGPS.Log:Error("Skinning a widget failed: %s", tostring(err)) end
    return widget
end

function Frames.Unregister(widget)
    Frames.registry[widget] = nil
end


function Frames.ApplySkin(frame, skin)
    skin = skin or Frames.Skin()
    for widget, applyFn in pairs(Frames.registry) do
        if widget == frame or isDescendant(widget, frame) then
            local ok, err = pcall(applyFn, widget, skin)
            if not ok and FGPS.Log then FGPS.Log:Error("Skinning a widget failed: %s", tostring(err)) end
        end
    end
    return frame
end


function Frames.ApplyAll(skin)
    skin = skin or Frames.Skin()
    local count = 0
    for widget, applyFn in pairs(Frames.registry) do
        local ok, err = pcall(applyFn, widget, skin)
        if not ok and FGPS.Log then FGPS.Log:Error("Skinning a widget failed: %s", tostring(err)) end
        count = count + 1
    end
    return count
end

function Frames.RegisteredCount()
    local n = 0
    for _ in pairs(Frames.registry) do n = n + 1 end
    return n
end




local function showTooltip(frame)
    local text = frame.fgpsTooltip
    if type(text) == "function" then text = text(frame) end
    if not text or not GameTooltip then return end
    GameTooltip:SetOwner(frame, frame.fgpsTooltipAnchor or "ANCHOR_RIGHT")
    if type(text) == "table" then
        for i = 1, #text do
            if i == 1 then
                GameTooltip:SetText(text[i])
            else
                GameTooltip:AddLine(text[i], 1, 1, 1, true)
            end
        end
    else
        GameTooltip:SetText(tostring(text), 1, 1, 1, 1, true)
    end
    GameTooltip:Show()
end

local function hideTooltip(frame)
    if GameTooltip and (not GameTooltip.IsOwned or GameTooltip:IsOwned(frame)) then GameTooltip:Hide() end
end


function Frames.Tooltip(frame, text, anchor)
    frame.fgpsTooltip = text
    frame.fgpsTooltipAnchor = anchor
    if not frame.fgpsTooltipHooked then
        frame.fgpsTooltipHooked = true
        if frame.EnableMouse and not frame:IsMouseEnabled() then frame:EnableMouse(true) end
        if frame.HookScript then
            frame:HookScript("OnEnter", showTooltip)
            frame:HookScript("OnLeave", hideTooltip)
        else
            frame:SetScript("OnEnter", showTooltip)
            frame:SetScript("OnLeave", hideTooltip)
        end
    end
    return frame
end




local function applyLabelSkin(fs, skin)
    Frames.SetFont(fs, skin, fs.fgpsKind, fs.fgpsOutline)
    setTextColor(fs, skin, fs.fgpsColor or "text")
end


function Frames.CreateLabel(parent, text, opts)
    opts = opts or {}
    local fs = parent:CreateFontString(nil, opts.layer or "OVERLAY", opts.fontObject or "GameFontHighlightSmall")
    fs.fgpsKind = opts.kind or "normal"
    fs.fgpsColor = opts.color or "text"
    fs.fgpsOutline = opts.outline or false
    if opts.width then fs:SetWidth(opts.width) end
    if opts.height then fs:SetHeight(opts.height) end
    if fs.SetJustifyH then fs:SetJustifyH(opts.justifyH or "LEFT") end
    if fs.SetJustifyV then fs:SetJustifyV(opts.justifyV or "MIDDLE") end
    if opts.wordWrap ~= nil and fs.SetWordWrap then fs:SetWordWrap(opts.wordWrap) end
    fs:SetText(text or "")
    Frames.Register(fs, applyLabelSkin)
    return fs
end




local function applyButtonSkin(b, skin)
    local bg = b.fgpsHover and color(skin, "buttonHover") or color(skin, "button")
    applyBackdrop(b, skin.buttonBackdrop or skin.backdrop, bg, color(skin, "buttonBorder"))
    if b.Text then
        Frames.SetFont(b.Text, skin, b.fgpsKind or "normal")
        if b:IsEnabled() then
            setTextColor(b.Text, skin, b.fgpsPrimary and "accent" or (skin.name == "classic" and "title" or "text"))
        else
            setTextColor(b.Text, skin, "textDim")
        end
    end
end


function Frames.CreateButton(parent, text, onClick, opts)
    opts = opts or {}
    local b = createBackdropFrame("Button", parent)
    b:SetSize(opts.width or 100, opts.height or 22)
    b.Text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.Text:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.Text:SetText(text or "")
    b.fgpsOnClick = onClick
    b.fgpsPrimary = opts.primary or false
    b.fgpsKind = opts.kind
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, button)
        if self.fgpsOnClick then
            local ok, err = pcall(self.fgpsOnClick, self, button)
            if not ok and FGPS.Log then FGPS.Log:Error("Button handler failed: %s", tostring(err)) end
        end
    end)
    b:SetScript("OnEnter", function(self)
        self.fgpsHover = true
        applyButtonSkin(self, Frames.Skin())
    end)
    b:SetScript("OnLeave", function(self)
        self.fgpsHover = false
        applyButtonSkin(self, Frames.Skin())
    end)
    function b:SetLabel(label) self.Text:SetText(label or "") end
    function b:GetLabel() return self.Text:GetText() end
    function b:SetOnClick(fn) self.fgpsOnClick = fn end
    function b:SetEnabledState(enabled)
        if enabled then self:Enable() else self:Disable() end
        applyButtonSkin(self, Frames.Skin())
    end
    Frames.Register(b, applyButtonSkin)
    if opts.tooltip then Frames.Tooltip(b, opts.tooltip) end
    return b
end




local function applyCheckboxSkin(cb, skin)
    if cb.Text then
        Frames.SetFont(cb.Text, skin, "normal")
        setTextColor(cb.Text, skin, cb:IsEnabled() and "text" or "textDim")
    end
end


function Frames.CreateCheckbox(parent, label, opts)
    opts = opts or {}
    local cb = CreateFrame("CheckButton", nil, parent)
    cb:SetSize(22, 22)
    if cb.SetNormalTexture then cb:SetNormalTexture(CHECK_UP) end
    if cb.SetPushedTexture then cb:SetPushedTexture(CHECK_DOWN) end
    if cb.SetHighlightTexture then cb:SetHighlightTexture(CHECK_HIGHLIGHT, "ADD") end
    if cb.SetCheckedTexture then cb:SetCheckedTexture(CHECK_CHECK) end
    cb.Text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cb.Text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    if opts.width then cb.Text:SetWidth(opts.width - 24) end
    if cb.Text.SetJustifyH then cb.Text:SetJustifyH("LEFT") end
    cb.Text:SetText(label or "")
    cb.fgpsOnChange = opts.onChange
    cb:SetChecked(opts.checked and true or false)
    cb:SetScript("OnClick", function(self)
        local checked = self:GetChecked() and true or false
        if self.fgpsOnChange then
            local ok, err = pcall(self.fgpsOnChange, self, checked)
            if not ok and FGPS.Log then FGPS.Log:Error("Checkbox handler failed: %s", tostring(err)) end
        end
    end)
    function cb:SetValue(checked) self:SetChecked(checked and true or false) end
    function cb:GetValue() return self:GetChecked() and true or false end
    function cb:SetOnChange(fn) self.fgpsOnChange = fn end
    Frames.Register(cb, applyCheckboxSkin)
    if opts.tooltip then Frames.Tooltip(cb, opts.tooltip) end
    return cb
end




local function formatSliderValue(slider, value)
    local fmt = slider.fgpsFormat
    if type(fmt) == "function" then return fmt(value) end
    return string.format(fmt or "%.2f", value)
end

local function applySliderSkin(slider, skin)
    local flat = (skin.sliderStyle or "flat") == "flat"
    if slider.Track then
        if flat then
            slider.Track:SetColorTexture(rgba(color(skin, "buttonBorder")))
            slider.Track:Show()
        else
            slider.Track:Hide()
        end
    end
    if slider.fgpsThumb then
        if flat then
            slider.fgpsThumb:SetTexture(WHITE)
            slider.fgpsThumb:SetVertexColor(rgba(color(skin, "accent")))
            slider.fgpsThumb:SetSize(10, 16)
        else
            slider.fgpsThumb:SetTexture(SLIDER_THUMB)
            slider.fgpsThumb:SetVertexColor(1, 1, 1, 1)
            slider.fgpsThumb:SetSize(28, 28)
        end
    end
    if slider.SetBackdrop and not flat then
        applyBackdrop(slider, { bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
            edgeFile = "Interface\\Buttons\\UI-SliderBar-Border", tile = true, tileSize = 8, edgeSize = 8,
            insets = { left = 3, right = 3, top = 6, bottom = 6 } }, { 1, 1, 1, 1 }, { 1, 1, 1, 1 })
    elseif slider.SetBackdrop and slider.fgpsBackdrop then
        slider:SetBackdrop(nil)
        slider.fgpsBackdrop = nil
    end
    if slider.Label then Frames.SetFont(slider.Label, skin, "small") setTextColor(slider.Label, skin, "textDim") end
    if slider.Value then Frames.SetFont(slider.Value, skin, "small") setTextColor(slider.Value, skin, "text") end
end

local function roundToStep(value, minV, step)
    if not step or step <= 0 then return value end
    return minV + floor((value - minV) / step + 0.5) * step
end


function Frames.CreateSlider(parent, opts)
    opts = opts or {}
    local slider = createBackdropFrame("Slider", parent)
    slider:SetSize(opts.width or 140, 16)
    if slider.SetOrientation then slider:SetOrientation("HORIZONTAL") end
    slider.fgpsMin, slider.fgpsMax, slider.fgpsStep = opts.min or 0, opts.max or 1, opts.step or 0.01
    slider.fgpsFormat = opts.format
    slider.fgpsOnChange = opts.onChange
    slider:SetMinMaxValues(slider.fgpsMin, slider.fgpsMax)
    if slider.SetValueStep then slider:SetValueStep(slider.fgpsStep) end
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider.Track = slider:CreateTexture(nil, "BACKGROUND")
    slider.Track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    slider.Track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    slider.Track:SetHeight(4)
    if slider.SetThumbTexture then
        slider:SetThumbTexture(WHITE)
        slider.fgpsThumb = slider.GetThumbTexture and slider:GetThumbTexture() or nil
    end
    if opts.label then
        slider.Label = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        slider.Label:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 4)
        slider.Label:SetText(opts.label)
    end
    slider.Value = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    slider.Value:SetPoint("BOTTOMRIGHT", slider, "TOPRIGHT", 0, 4)
    if slider.Value.SetJustifyH then slider.Value:SetJustifyH("RIGHT") end
    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", function(self, delta)
        if not self:IsEnabled() then return end
        local value = roundToStep(self:GetValue() + delta * self.fgpsStep, self.fgpsMin, self.fgpsStep)
        value = max(self.fgpsMin, min(self.fgpsMax, value))
        self.fgpsUserInput = true
        self:SetValue(value)
        self.fgpsUserInput = false
        self:OnValueChanged(value, true)
    end)
    function slider:OnValueChanged(value, userInput)
        value = roundToStep(value, self.fgpsMin, self.fgpsStep)
        self.Value:SetText(formatSliderValue(self, value))
        if (userInput or self.fgpsUserInput) and not self.fgpsSilent and self.fgpsOnChange and value ~= self.fgpsLast then
            self.fgpsLast = value
            local ok, err = pcall(self.fgpsOnChange, self, value, true)
            if not ok and FGPS.Log then FGPS.Log:Error("Slider handler failed: %s", tostring(err)) end
        elseif not userInput then
            self.fgpsLast = value
        end
    end
    slider:SetScript("OnValueChanged", function(self, value, userInput) self:OnValueChanged(value, userInput) end)
    function slider:SetValueSilent(value)
        self.fgpsSilent = true
        self:SetValue(value)
        self.fgpsLast = value
        self.Value:SetText(formatSliderValue(self, value))
        self.fgpsSilent = false
    end
    function slider:SetOnChange(fn) self.fgpsOnChange = fn end
    slider:SetValueSilent(opts.value or slider.fgpsMin)
    Frames.Register(slider, applySliderSkin)
    return slider
end




local function closeOpenMenu()
    if Frames.openMenu then
        Frames.openMenu:Hide()
        Frames.openMenu = nil
    end
end
Frames.CloseMenus = closeOpenMenu

local function applyDropdownSkin(dd, skin)
    applyBackdrop(dd, skin.buttonBackdrop or skin.backdrop,
        dd.fgpsHover and color(skin, "buttonHover") or color(skin, "button"), color(skin, "buttonBorder"))
    Frames.SetFont(dd.Text, skin, "normal")
    setTextColor(dd.Text, skin, skin.name == "classic" and "title" or "text")
    if dd.Menu then
        applyBackdrop(dd.Menu, skin.backdrop, color(skin, "bg"), color(skin, "border"))
        for _, row in ipairs(dd.Menu.rows) do
            Frames.SetFont(row.Text, skin, "normal")
            setTextColor(row.Text, skin, row.fgpsSelected and "accent" or "text")
            row.Bg:SetColorTexture(rgba(color(skin, "highlight")))
        end
    end
end

local function dropdownLabelFor(dd, value)
    for _, option in ipairs(dd.fgpsOptions) do
        if option.value == value then return option.label end
    end
    return value ~= nil and tostring(value) or ""
end

local function ensureMenu(dd)
    if dd.Menu then return dd.Menu end
    local menu = createBackdropFrame("Frame", dd)
    menu:SetFrameStrata("TOOLTIP")
    menu:SetToplevel(true)
    menu:SetClampedToScreen(true)
    menu:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -2)
    menu.rows = {}
    menu:Hide()
    dd.Menu = menu
    return menu
end

local function rebuildMenu(dd)
    local menu = ensureMenu(dd)
    local skin = Frames.Skin()
    local rowHeight = 20
    local count = #dd.fgpsOptions
    for i, option in ipairs(dd.fgpsOptions) do
        local row = menu.rows[i]
        if not row then
            row = CreateFrame("Button", nil, menu)
            row:SetHeight(rowHeight)
            row:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (i - 1) * rowHeight)
            row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -4 - (i - 1) * rowHeight)
            row.Bg = row:CreateTexture(nil, "BACKGROUND")
            row.Bg:SetAllPoints(row)
            row.Bg:Hide()
            row.Text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.Text:SetPoint("LEFT", row, "LEFT", 6, 0)
            row.Text:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            if row.Text.SetJustifyH then row.Text:SetJustifyH("LEFT") end
            row:SetScript("OnEnter", function(self) self.Bg:Show() end)
            row:SetScript("OnLeave", function(self) self.Bg:Hide() end)
            row:SetScript("OnClick", function(self) dd:Select(self.fgpsValue, true) closeOpenMenu() end)
            menu.rows[i] = row
        end
        row.fgpsValue = option.value
        row.fgpsSelected = (option.value == dd.fgpsValue)
        row.Text:SetText(option.label or tostring(option.value))
        row:Show()
    end
    for i = count + 1, #menu.rows do menu.rows[i]:Hide() end
    menu:SetSize(dd:GetWidth(), count * rowHeight + 8)
    applyDropdownSkin(dd, skin)
    return menu
end


function Frames.CreateDropdown(parent, opts)
    opts = opts or {}
    local dd = createBackdropFrame("Button", parent)
    dd:SetSize(opts.width or 140, opts.height or 22)
    dd.fgpsOptions = opts.options or {}
    dd.fgpsValue = opts.value
    dd.fgpsOnChange = opts.onChange
    dd.Text = dd:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dd.Text:SetPoint("LEFT", dd, "LEFT", 6, 0)
    dd.Text:SetPoint("RIGHT", dd, "RIGHT", -20, 0)
    if dd.Text.SetJustifyH then dd.Text:SetJustifyH("LEFT") end
    dd.Arrow = dd:CreateTexture(nil, "ARTWORK")
    dd.Arrow:SetSize(16, 16)
    dd.Arrow:SetPoint("RIGHT", dd, "RIGHT", -3, 0)
    dd.Arrow:SetTexture(DROPDOWN_ARROW)
    dd.Text:SetText(dropdownLabelFor(dd, dd.fgpsValue))
    dd:SetScript("OnClick", function(self)
        if self.Menu and self.Menu:IsShown() then
            closeOpenMenu()
            return
        end
        closeOpenMenu()
        local menu = rebuildMenu(self)
        menu:Show()
        Frames.openMenu = menu
    end)
    dd:SetScript("OnEnter", function(self) self.fgpsHover = true applyDropdownSkin(self, Frames.Skin()) end)
    dd:SetScript("OnLeave", function(self) self.fgpsHover = false applyDropdownSkin(self, Frames.Skin()) end)
    dd:SetScript("OnHide", function(self) if Frames.openMenu == self.Menu then closeOpenMenu() end end)
    function dd:Select(value, fire)
        self.fgpsValue = value
        self.Text:SetText(dropdownLabelFor(self, value))
        if fire and self.fgpsOnChange then
            local ok, err = pcall(self.fgpsOnChange, self, value)
            if not ok and FGPS.Log then FGPS.Log:Error("Dropdown handler failed: %s", tostring(err)) end
        end
    end
    function dd:SetValue(value) self:Select(value, false) end
    function dd:GetValue() return self.fgpsValue end
    function dd:SetOptions(options)
        self.fgpsOptions = options or {}
        self.Text:SetText(dropdownLabelFor(self, self.fgpsValue))
        if self.Menu and self.Menu:IsShown() then rebuildMenu(self) end
    end
    function dd:SetOnChange(fn) self.fgpsOnChange = fn end
    function dd:IsOpen() return self.Menu ~= nil and self.Menu:IsShown() end
    Frames.Register(dd, applyDropdownSkin)
    if opts.tooltip then Frames.Tooltip(dd, opts.tooltip) end
    return dd
end




local function updatePlaceholder(box)
    if not box.Placeholder then return end
    local text = box:GetText()
    local empty = text == nil or text == ""
    box.Placeholder:SetShown(empty and not box.fgpsFocused)
end

local function applyEditBoxSkin(box, skin)
    applyBackdrop(box, skin.backdrop, color(skin, "editBox"), box.fgpsFocused and color(skin, "accent") or color(skin, "border"))
    Frames.SetFont(box, skin, "normal")
    setTextColor(box, skin, "text")
    if box.Placeholder then
        Frames.SetFont(box.Placeholder, skin, "normal")
        setTextColor(box.Placeholder, skin, "textDim")
    end
end



function Frames.CreateEditBox(parent, opts)
    opts = opts or {}
    local box = createBackdropFrame("EditBox", parent)


    if box.SetFontObject then box:SetFontObject("GameFontHighlightSmall") end
    box:SetSize(opts.width or 160, opts.height or 22)
    box:SetAutoFocus(false)
    if box.SetTextInsets then box:SetTextInsets(6, 6, 0, 0) end
    if opts.maxLetters and box.SetMaxLetters then box:SetMaxLetters(opts.maxLetters) end
    if opts.numeric and box.SetNumeric then box:SetNumeric(true) end
    box.Placeholder = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    box.Placeholder:SetPoint("LEFT", box, "LEFT", 6, 0)
    box.Placeholder:SetPoint("RIGHT", box, "RIGHT", -6, 0)
    if box.Placeholder.SetJustifyH then box.Placeholder:SetJustifyH("LEFT") end
    box.Placeholder:SetText(opts.placeholder or "")
    box.fgpsOnEnter, box.fgpsOnChanged, box.fgpsOnEscape = opts.onEnter, opts.onChanged, opts.onEscape
    box.fgpsKeepFocus = opts.keepFocusOnEnter
    box:SetScript("OnEnterPressed", function(self)
        if self.fgpsOnEnter then
            local ok, err = pcall(self.fgpsOnEnter, self, self:GetText())
            if not ok and FGPS.Log then FGPS.Log:Error("EditBox handler failed: %s", tostring(err)) end
        end
        if not self.fgpsKeepFocus then self:ClearFocus() end
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        if self.fgpsOnEscape then pcall(self.fgpsOnEscape, self) end
    end)
    box:SetScript("OnTextChanged", function(self, userInput)
        updatePlaceholder(self)
        if self.fgpsOnChanged then
            local ok, err = pcall(self.fgpsOnChanged, self, self:GetText(), userInput)
            if not ok and FGPS.Log then FGPS.Log:Error("EditBox handler failed: %s", tostring(err)) end
        end
    end)
    box:SetScript("OnEditFocusGained", function(self)
        self.fgpsFocused = true
        updatePlaceholder(self)
        applyEditBoxSkin(self, Frames.Skin())
    end)
    box:SetScript("OnEditFocusLost", function(self)
        self.fgpsFocused = false
        updatePlaceholder(self)
        applyEditBoxSkin(self, Frames.Skin())
    end)
    function box:GetValue() return self:GetText() or "" end
    function box:SetValue(text) self:SetText(text or "") updatePlaceholder(self) end
    function box:SetPlaceholder(text) self.Placeholder:SetText(text or "") end
    Frames.Register(box, applyEditBoxSkin)
    box:SetText(opts.text or "")
    updatePlaceholder(box)
    return box
end




local SCROLLBAR_WIDTH = 10




local function applyRowSkin(row, skin)
    Frames.SetFont(row.Text, skin, "normal")
    setTextColor(row.Text, skin, "text")
    row.Bg:SetColorTexture(rgba(row.fgpsSelected and color(skin, "selection") or color(skin, "highlight")))
end

local function applyListSkin(list, skin)
    if list.Bar then
        list.Bar.Track:SetColorTexture(rgba(color(skin, "buttonBorder"), 0.5))
        if list.Bar.fgpsThumb then
            list.Bar.fgpsThumb:SetTexture(WHITE)
            list.Bar.fgpsThumb:SetVertexColor(rgba(color(skin, "accent")))
        end
    end
    if list.Empty then
        Frames.SetFont(list.Empty, skin, "normal")
        setTextColor(list.Empty, skin, "textDim")
    end
    for _, row in ipairs(list.rows) do applyRowSkin(row, skin) end
end

local function listVisibleCount(list)
    local h = list:GetHeight() or 0
    if h <= 0 then return 0 end
    return max(0, floor(h / list.rowHeight))
end

local function acquireRow(list, i)
    local row = list.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, list)
    row:SetHeight(list.rowHeight)
    row.Bg = row:CreateTexture(nil, "BACKGROUND")
    row.Bg:SetAllPoints(row)
    row.Bg:Hide()
    row.Text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.Text:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.Text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    if row.Text.SetJustifyH then row.Text:SetJustifyH("LEFT") end
    applyRowSkin(row, Frames.Skin())
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button) list:OnRowClick(self, button) end)
    row:SetScript("OnEnter", function(self)
        self.fgpsHover = true
        if not self.fgpsSelected then self.Bg:Show() end
        if list.onEnter then pcall(list.onEnter, self.fgpsItem, self.fgpsIndex, self) end
    end)
    row:SetScript("OnLeave", function(self)
        self.fgpsHover = false
        if not self.fgpsSelected then self.Bg:Hide() end
        if list.onLeave then pcall(list.onLeave, self.fgpsItem, self.fgpsIndex, self) end
    end)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta) list:Scroll(-delta * list.wheelStep) end)
    list.rows[i] = row
    return row
end



function Frames.CreateScrollList(parent, rowHeight, renderFn, opts)
    opts = opts or {}
    assert(type(rowHeight) == "number" and rowHeight > 0, "CreateScrollList: rowHeight must be a positive number")
    assert(type(renderFn) == "function", "CreateScrollList: renderFn must be a function")
    local list = CreateFrame("Frame", nil, parent)
    list:SetSize(opts.width or 200, opts.height or 200)
    list.rowHeight = rowHeight
    list.renderFn = renderFn
    list.items = {}
    list.rows = {}
    list.offset = 0
    list.selected = nil
    list.onClick = opts.onClick
    list.onEnter, list.onLeave = opts.onEnter, opts.onLeave
    list.wheelStep = opts.wheelStep or 3
    list.emptyText = opts.emptyText
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta) self:Scroll(-delta * self.wheelStep) end)
    list:SetScript("OnSizeChanged", function(self) self:Refresh() end)

    list.Empty = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    list.Empty:SetPoint("TOP", list, "TOP", 0, -8)
    list.Empty:SetText(opts.emptyText or "")
    list.Empty:Hide()

    local bar = CreateFrame("Slider", nil, list)
    bar:SetWidth(SCROLLBAR_WIDTH)
    bar:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, 0)
    if bar.SetOrientation then bar:SetOrientation("VERTICAL") end
    bar.Track = bar:CreateTexture(nil, "BACKGROUND")
    bar.Track:SetAllPoints(bar)
    if bar.SetThumbTexture then
        bar:SetThumbTexture(WHITE)
        bar.fgpsThumb = bar.GetThumbTexture and bar:GetThumbTexture() or nil
        if bar.fgpsThumb then bar.fgpsThumb:SetSize(SCROLLBAR_WIDTH, 24) end
    end
    bar:SetMinMaxValues(0, 0)
    if bar.SetValueStep then bar:SetValueStep(1) end
    if bar.SetObeyStepOnDrag then bar:SetObeyStepOnDrag(true) end
    bar:SetScript("OnValueChanged", function(self, value, userInput)
        if list.fgpsSettingBar then return end
        local offset = floor((value or 0) + 0.5)
        if offset ~= list.offset then
            list.offset = offset
            list:Refresh(true)
        end
    end)
    bar:Hide()
    list.Bar = bar

    function list:MaxOffset()
        return max(0, #self.items - listVisibleCount(self))
    end

    function list:Refresh(fromBar)
        local visible = listVisibleCount(self)
        local count = #self.items
        local maxOffset = max(0, count - visible)
        if self.offset > maxOffset then self.offset = maxOffset end
        if self.offset < 0 then self.offset = 0 end
        local showBar = count > visible and visible > 0
        self.Bar:SetShown(showBar)
        if not fromBar then
            self.fgpsSettingBar = true
            self.Bar:SetMinMaxValues(0, maxOffset)
            self.Bar:SetValue(self.offset)
            self.fgpsSettingBar = false
        end
        local rightInset = showBar and (SCROLLBAR_WIDTH + 2) or 0
        local skin = Frames.Skin()
        for i = 1, visible do
            local index = self.offset + i
            local item = self.items[index]
            local row = acquireRow(self, i)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(i - 1) * self.rowHeight)
            row:SetPoint("TOPRIGHT", self, "TOPRIGHT", -rightInset, -(i - 1) * self.rowHeight)
            if item ~= nil then
                row.fgpsItem, row.fgpsIndex = item, index
                row.fgpsSelected = (index == self.selected)
                row.Bg:SetColorTexture(rgba(row.fgpsSelected and color(skin, "selection") or color(skin, "highlight")))
                row.Bg:SetShown(row.fgpsSelected or row.fgpsHover or false)
                local ok, err = pcall(self.renderFn, row, item, index, self)
                if not ok and FGPS.Log then FGPS.Log:Error("Scroll list render failed: %s", tostring(err)) end
                row:Show()
            else
                row.fgpsItem, row.fgpsIndex, row.fgpsSelected = nil, nil, false
                row:Hide()
            end
        end
        for i = visible + 1, #self.rows do
            local row = self.rows[i]
            row.fgpsItem, row.fgpsIndex, row.fgpsSelected = nil, nil, false
            row:Hide()
        end
        self.Empty:SetShown(count == 0 and self.emptyText ~= nil and self.emptyText ~= "")
    end

    function list:SetItems(items)
        self.items = items or {}
        if self.selected and self.selected > #self.items then self.selected = nil end
        self:Refresh()
    end

    function list:GetItems() return self.items end

    function list:Scroll(delta)
        local target = max(0, min(self:MaxOffset(), self.offset + delta))
        if target ~= self.offset then
            self.offset = target
            self:Refresh()
        end
    end

    function list:ScrollTo(index)
        local visible = listVisibleCount(self)
        if index < self.offset + 1 then
            self.offset = max(0, index - 1)
        elseif index > self.offset + visible then
            self.offset = max(0, index - visible)
        end
        self:Refresh()
    end

    function list:SetSelected(index, fire)
        if index ~= nil and (index < 1 or index > #self.items) then index = nil end
        self.selected = index
        self:Refresh()
        if fire and index and self.onClick then
            pcall(self.onClick, self.items[index], index, "LeftButton", nil)
        end
    end

    function list:GetSelected()
        if self.selected then return self.items[self.selected], self.selected end
        return nil
    end

    function list:OnRowClick(row, button)
        if row.fgpsIndex == nil then return end
        self.selected = row.fgpsIndex
        self:Refresh()
        if self.onClick then
            local ok, err = pcall(self.onClick, row.fgpsItem, row.fgpsIndex, button, row)
            if not ok and FGPS.Log then FGPS.Log:Error("Scroll list click handler failed: %s", tostring(err)) end
        end
    end

    function list:SetOnClick(fn) self.onClick = fn end
    function list:SetEmptyText(text) self.emptyText = text self.Empty:SetText(text or "") self:Refresh() end
    function list:VisibleCount() return listVisibleCount(self) end

    Frames.Register(list, applyListSkin)
    list:Refresh()
    return list
end




local function applyWindowSkin(win, skin)
    applyBackdrop(win, skin.backdrop, color(skin, "bg"), color(skin, "border"))
    win:SetAlpha(skin.panelAlpha or 1)
    local titleHeight = skin.titleHeight or 20
    local inset = skin.inset or 8
    win.TitleBar:SetHeight(titleHeight)
    win.TitleBar:ClearAllPoints()
    win.TitleBar:SetPoint("TOPLEFT", win, "TOPLEFT", inset / 2, -inset / 2)
    win.TitleBar:SetPoint("TOPRIGHT", win, "TOPRIGHT", -inset / 2, -inset / 2)
    if (skin.titleBarStyle or "flat") == "flat" then
        win.TitleBar.Bg:SetColorTexture(rgba(color(skin, "titleBar")))
        win.TitleBar.Bg:Show()
        win.TitleBar.Accent:SetColorTexture(rgba(color(skin, "accent")))
        win.TitleBar.Accent:Show()
    else
        win.TitleBar.Bg:Hide()
        win.TitleBar.Accent:Hide()
    end
    Frames.SetFont(win.Title, skin, "title")
    setTextColor(win.Title, skin, "title")
    win.Content:ClearAllPoints()
    win.Content:SetPoint("TOPLEFT", win, "TOPLEFT", inset, -(titleHeight + inset))
    win.Content:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -inset, inset)
    local close = win.Close
    if skin.closeButtonTemplate then
        close.Icon:Show()
        close.Glyph:Hide()
        close:SetSize(26, 26)
    else
        close.Icon:Hide()
        close.Glyph:Show()
        Frames.SetFont(close.Glyph, skin, "normal")
        setTextColor(close.Glyph, skin, close.fgpsHover and "accent" or "textDim")
        close:SetSize(math.max(titleHeight or 20, 20), math.max(titleHeight or 20, 20))
    end
end




local function windowKeyDown(self, key)
    local handled = key == "ESCAPE"
    if not handled and self.fgpsOnKey then
        local ok, result = pcall(self.fgpsOnKey, self, key)
        if not ok then
            if FGPS.Log then FGPS.Log:Error("Window %s key handler failed: %s", tostring(self.key), tostring(result)) end
        else
            handled = result == true
        end
    end
    if self.SetPropagateKeyboardInput and not (InCombatLockdown and InCombatLockdown()) then
        pcall(self.SetPropagateKeyboardInput, self, not handled)
    end
    if key == "ESCAPE" then self:Hide() end
end

local function windowKeyboard(win, enabled)
    if not win.EnableKeyboard then return end
    if enabled and win.fgpsEscape and not (InCombatLockdown and InCombatLockdown()) then
        win:EnableKeyboard(true)
    else
        win:EnableKeyboard(false)
    end
end






Frames.DEFAULT_OFFSETS = {
    search = { fx = -0.30, fy = 0.08 },
    preview = { fx = 0.30, fy = 0.08 },
    itinerary = { fx = -0.30, fy = -0.28 },
    favorites = { fx = 0.30, fy = -0.28 },
    quests = { fx = -0.30, fy = 0.32 },
    setup = { fx = 0.0, fy = 0.12 },
}

local function defaultOffset(key)
    local slot = Frames.DEFAULT_OFFSETS[key]
    if slot then return { fx = slot.fx, fy = slot.fy } end
    return { fx = -0.22, fy = 0.12 }
end

function Frames.CreateWindow(key, opts)
    assert(type(key) == "string" and key ~= "", "CreateWindow: key must be a non-empty string")
    opts = opts or {}
    if Frames.windows[key] then return Frames.windows[key] end

    local win = createBackdropFrame("Frame", UIParent)
    win.key = key
    win.opts = opts
    win.fgpsEscape = opts.escape ~= false
    win.fgpsOnKey = opts.onKey
    win.fgpsPersist = opts.persist ~= false
    win:SetSize(opts.width or 320, opts.height or 240)
    win:SetFrameStrata(opts.strata or "HIGH")
    win:SetToplevel(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:Hide()


    local bar = CreateFrame("Frame", nil, win)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar.Bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.Bg:SetAllPoints(bar)
    bar.Accent = bar:CreateTexture(nil, "ARTWORK")
    bar.Accent:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    bar.Accent:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    bar.Accent:SetHeight(1)
    bar:SetScript("OnDragStart", function() win:StartMoving() win.fgpsMoving = true end)
    bar:SetScript("OnDragStop", function()
        win:StopMovingOrSizing()
        win.fgpsMoving = false
        win:SavePosition()
    end)
    win.TitleBar = bar

    win.Title = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.Title:SetPoint("LEFT", bar, "LEFT", 6, 0)
    win.Title:SetPoint("RIGHT", bar, "RIGHT", -28, 0)
    if win.Title.SetJustifyH then win.Title:SetJustifyH("LEFT") end
    win.Title:SetText(opts.title or "")

    local close = CreateFrame("Button", nil, win)
    close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -2, -2)
    close.Icon = close:CreateTexture(nil, "ARTWORK")
    close.Icon:SetAllPoints(close)
    close.Icon:SetTexture(CLOSE_UP)
    close.Glyph = close:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    close.Glyph:SetPoint("CENTER", close, "CENTER", 0, 0)
    close.Glyph:SetText("x")
    if close.SetHighlightTexture then close:SetHighlightTexture(CLOSE_HIGHLIGHT, "ADD") end
    if close.SetPushedTexture then close:SetPushedTexture(CLOSE_DOWN) end




    local function raiseClose()
        if close.SetFrameLevel and bar.GetFrameLevel then close:SetFrameLevel((bar:GetFrameLevel() or 1) + 5) end
    end
    raiseClose()
    win.RaiseCloseButton = raiseClose
    close:RegisterForClicks("LeftButtonUp")
    close:SetScript("OnClick", function() win:Hide() end)
    close:SetScript("OnEnter", function(self) self.fgpsHover = true applyWindowSkin(win, Frames.Skin()) end)
    close:SetScript("OnLeave", function(self) self.fgpsHover = false applyWindowSkin(win, Frames.Skin()) end)
    Frames.Tooltip(close, L["Close"])
    win.Close = close

    win.Content = CreateFrame("Frame", nil, win)

    if opts.resizable then
        win:SetResizable(true)
        local minW, minH = 160, 100
        if opts.minSize then minW, minH = opts.minSize[1] or minW, opts.minSize[2] or minH end
        local maxW, maxH
        if opts.maxSize then maxW, maxH = opts.maxSize[1], opts.maxSize[2] end
        win.fgpsMinSize = { minW, minH }
        if win.SetResizeBounds then
            win:SetResizeBounds(minW, minH, maxW, maxH)
        else
            if win.SetMinResize then win:SetMinResize(minW, minH) end
            if maxW and win.SetMaxResize then win:SetMaxResize(maxW, maxH) end
        end
        local grip = CreateFrame("Button", nil, win)
        grip:SetSize(20, 20)
        grip:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -3, 3)
        if grip.SetNormalTexture then grip:SetNormalTexture(GRIP_UP) end
        if grip.SetHighlightTexture then grip:SetHighlightTexture(GRIP_HIGHLIGHT) end
        if grip.SetPushedTexture then grip:SetPushedTexture(GRIP_DOWN) end
        grip:SetScript("OnMouseDown", function()
            if win.StartSizing then win:StartSizing("BOTTOMRIGHT") win.fgpsSizing = true end
        end)
        grip:SetScript("OnMouseUp", function()
            win:StopMovingOrSizing()
            win.fgpsSizing = false
            win:SavePosition()
            if opts.onResize then pcall(opts.onResize, win, win:GetSize()) end
        end)
        win.Grip = grip

        if grip.SetFrameLevel and win.GetFrameLevel then grip:SetFrameLevel((win:GetFrameLevel() or 1) + 10) end
    end


    win:SetScript("OnKeyDown", windowKeyDown)
    win:SetScript("OnShow", function(self)
        windowKeyboard(self, true)
        if self.Raise then self:Raise() end
        if self.RaiseCloseButton then self.RaiseCloseButton() end
        if opts.onShow then pcall(opts.onShow, self) end
    end)
    win:SetScript("OnHide", function(self)
        windowKeyboard(self, false)
        closeOpenMenu()
        if opts.onClose then
            local ok, err = pcall(opts.onClose, self)
            if not ok and FGPS.Log then FGPS.Log:Error("Window %s onClose failed: %s", key, tostring(err)) end
        end
    end)

    function win:SetTitle(text) self.Title:SetText(text or "") end
    function win:Toggle() if self:IsShown() then self:Hide() else self:Show() end end
    function win:Open() self:Show() end
    function win:SavePosition()
        local positions = FGPS.UI.Positions
        if self.fgpsPersist and positions and positions.Save then
            positions.Save("window:" .. self.key, self)
        end
    end
    function win:RestorePosition()
        local positions = FGPS.UI.Positions
        if self.fgpsPersist and positions and positions.Restore then
            return positions.Restore("window:" .. self.key, self, defaultOffset(self.key), nil,
                { restoreSize = opts.resizable and true or false, minSize = self.fgpsMinSize })
        end
        local slot = defaultOffset(self.key)
        local uw = (UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 1024
        local uh = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 768
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "CENTER", slot.fx * uw, slot.fy * uh)
        return "default"
    end
    function win:GetContentSize() return self.Content:GetSize() end

    win:RestorePosition()
    Frames.windows[key] = win
    Frames.Register(win, applyWindowSkin)
    return win
end

function Frames.GetWindow(key)
    return Frames.windows[key]
end


function Frames.HideAllWindows()
    for _, win in pairs(Frames.windows) do win:Hide() end
end




local function onCombatState(_, inCombat)
    for _, win in pairs(Frames.windows) do
        if inCombat then
            windowKeyboard(win, false)
        elseif win:IsShown() then
            windowKeyboard(win, true)
        end
    end
end

function Frames:Init()
    if not Frames.initialised and FGPS.Events then
        FGPS.Events:Register("COMBAT_STATE", onCombatState, Frames)
        Frames.initialised = true
    end
    Frames.ApplyAll(Frames.Skin())
    return Frames
end
