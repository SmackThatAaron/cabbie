





local ADDON_NAME, FGPS = ...

local type, floor, format, max, pcall, huge, tonumber = type, math.floor, string.format, math.max, pcall, math.huge, tonumber
local ipairs, pairs, unpack, tostring = ipairs, pairs, unpack, tostring

local Look = {}
FGPS.UI.Look = Look







local FONTS = {
    header = { "ObjectiveTrackerHeaderFont", "GameFontNormalMed2", "GameFontNormal" },
    title = { "ObjectiveTrackerLineFont", "GameFontNormal" },
    line = { "ObjectiveTrackerLineFont", "GameFontHighlight" },
    callout = { "GameFontNormalLargeOutline", "GameFontNormalLarge", "GameFontNormal" },


    listTitle = { "GameFontNormal" },
    row = { "GameFontHighlight", "GameFontNormal" },
    rowSmall = { "GameFontHighlightSmall", "GameFontNormalSmall", "GameFontNormal" },
    input = { "ChatFontNormal", "GameFontHighlight", "GameFontNormal" },

    hint = { "GameFontDisableSmall", "GameFontDisable", "GameFontHighlightSmall" },


    panelTitle = { "GameFontHighlightLarge", "GameFontHighlight" },
    setting = { "GameFontHighlightMedium", "GameFontHighlight" },
}

function Look.Font(role)
    local names = FONTS[role] or FONTS.line
    for i = 1, #names do
        if type(_G[names[i]]) == "table" then return names[i] end
    end
    return "GameFontNormal"
end




local function rgb(color, r, g, b)
    if type(color) == "table" and type(color.r) == "number" and type(color.g) == "number" and type(color.b) == "number" then
        return color.r, color.g, color.b
    end
    return r, g, b
end



function Look.Color(role)
    local tracker = type(OBJECTIVE_TRACKER_COLOR) == "table" and OBJECTIVE_TRACKER_COLOR or nil
    local normal = type(NORMAL_FONT_COLOR) == "table" and NORMAL_FONT_COLOR or nil
    local highlight = type(HIGHLIGHT_FONT_COLOR) == "table" and HIGHLIGHT_FONT_COLOR or nil
    local grey = type(GRAY_FONT_COLOR) == "table" and GRAY_FONT_COLOR or nil
    if role == "header" then return rgb(normal, 1, 0.82, 0) end
    if role == "title" then return rgb(tracker and tracker.Header, 0.75, 0.61, 0) end
    if role == "current" then

        local r, g, b = rgb(tracker and tracker.NormalHighlight)
        if r then return r, g, b end
        return rgb(highlight, 1, 1, 1)
    end
    if role == "later" then return rgb(tracker and tracker.Normal, 0.8, 0.8, 0.8) end
    if role == "grey" then return rgb(grey, 0.5, 0.5, 0.5) end
    if role == "name" then return rgb(highlight, 1, 1, 1) end
    if role == "match" then return rgb(normal, 1, 0.82, 0) end
    return 1, 1, 1
end



function Look.Tint(text, role)
    local r, g, b = Look.Color(role)
    return format("|cff%02x%02x%02x%s|r", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5), text)
end






Look.DIFFICULTY = {
    impossible = { 1, 0.1, 0.1 }, verydifficult = { 1, 0.5, 0.25 }, difficult = { 1, 1, 0 },
    standard = { 0.25, 0.75, 0.25 }, trivial = { 0.5, 0.5, 0.5 },
}


Look.GREEN_RANGE = 8

local function playerLevel()
    if type(UnitLevel) ~= "function" then return nil end
    local ok, level = pcall(UnitLevel, "player")
    return ok and tonumber(level) or nil
end

local function greenRange()
    if type(UnitQuestTrivialLevelRange) == "function" then
        local ok, range = pcall(UnitQuestTrivialLevelRange, "player")
        if ok and type(range) == "number" and not (issecretvalue and issecretvalue(range)) then return range end
    end
    return Look.GREEN_RANGE
end

function Look.QuestColor(level)
    level = tonumber(level)
    if not level or level <= 0 then return Look.Color("title") end
    if type(GetQuestDifficultyColor) == "function" then
        local ok, color = pcall(GetQuestDifficultyColor, level)
        if ok then
            local r, g, b = rgb(color)
            if r then return r, g, b end
        end
    end
    local own = playerLevel()
    if not own then return unpack(Look.DIFFICULTY.difficult) end
    local above = level - own
    local step
    if above >= 5 then step = "impossible"
    elseif above >= 3 then step = "verydifficult"
    elseif above >= -2 then step = "difficult"
    elseif -above <= greenRange() then step = "standard"
    else step = "trivial" end
    return unpack(Look.DIFFICULTY[step])
end








function Look.Distance(yards, step)
    if type(yards) == "number" and (yards ~= yards or yards == huge or yards == -huge) then return nil end
    local DB = FGPS.DB
    local units = DB and DB.Get and DB:Get("units") or "yards"
    if type(yards) ~= "number" or type(step) ~= "number" or not (step > 0) then
        return FGPS.Util.FormatDistance(yards, units)
    end
    local perYard = units == "metric" and FGPS.Const.METERS_PER_YARD or 1
    local shown = floor(yards * perYard / step + 0.5) * step
    return FGPS.Util.FormatDistance(shown / perYard, units), shown
end




function Look.Clock(seconds)
    if type(seconds) ~= "number" or seconds ~= seconds or seconds < 0 or seconds == huge then return nil end
    seconds = floor(seconds + 0.5)
    local hours = floor(seconds / 3600)
    local minutes = floor((seconds % 3600) / 60)
    if hours > 0 then return format("%d:%02d:%02d", hours, minutes, seconds % 60) end
    return format("%d:%02d", minutes, seconds % 60)
end











local shown = setmetatable({}, { __mode = "k" })




function Look.SetLine(line, text, r, g, b)
    if not line then return false end
    local was = shown[line]
    if not was then
        was = {}
        shown[line] = was
    end
    local changed = was.text ~= text
    if changed then
        was.text = text
        line:SetText(text)
    end
    if r ~= nil and (was.r ~= r or was.g ~= g or was.b ~= b) then
        was.r, was.g, was.b = r, g, b
        line:SetTextColor(r, g, b)
    end
    return changed
end



function Look.ForgetLine(line)
    if line then shown[line] = nil end
end








function Look.Atlas(texture, candidates, size)
    if not (texture and type(candidates) == "table" and C_Texture and C_Texture.GetAtlasInfo) then return false end
    if type(size) ~= "number" or not (size > 0) then return false end
    for i = 1, #candidates do
        local name = candidates[i]
        local ok, info = pcall(C_Texture.GetAtlasInfo, name)
        if ok and type(info) == "table" and (info.width or 0) > 0 and (info.height or 0) > 0 then
            local scale = size / max(info.width, info.height)
            texture:SetAtlas(name)
            texture:SetSize(info.width * scale, info.height * scale)
            return name
        end
    end
    return false
end






local ICONS = {
    place = { atlas = { "poi-town", "Waypoint-MapPin-Untracked" } },
    dungeon = { atlas = { "Dungeon", "Raid" } },
    flight = { atlas = { "FlightMaster", "TaxiNode_Neutral" }, file = "Interface\\GossipFrame\\TaxiGossipIcon" },
    inn = { atlas = { "Innkeeper" }, file = "Interface\\GossipFrame\\BinderGossipIcon" },
    bank = { atlas = { "Banker" }, file = "Interface\\GossipFrame\\BankerGossipIcon" },
    repair = { atlas = { "Repair" }, file = "Interface\\Minimap\\Tracking\\Repair" },
    mail = { atlas = { "Mailbox" }, file = "Interface\\Minimap\\Tracking\\Mailbox" },
    vendor = { atlas = {}, file = "Interface\\GossipFrame\\VendorGossipIcon" },
    trainer = { atlas = { "Class" }, file = "Interface\\GossipFrame\\TrainerGossipIcon" },
    stable = { atlas = { "StableMaster" }, file = "Interface\\Minimap\\Tracking\\StableMaster" },
    auction = { atlas = { "Auctioneer" }, file = "Interface\\Minimap\\Tracking\\Auctioneer" },
    quest = { atlas = {}, file = "Interface\\GossipFrame\\IncompleteQuestIcon" },
    questReady = { atlas = { "QuestTurnin" }, file = "Interface\\GossipFrame\\ActiveQuestIcon" },
    pickup = { atlas = { "QuestNormal" }, file = "Interface\\GossipFrame\\AvailableQuestIcon" },
    search = { atlas = { "common-search-magnifyingglass" }, file = "Interface\\Common\\UI-Searchbox-Icon" },
    map = { atlas = { "Waypoint-MapPin-Untracked", "Waypoint-MapPin-Tracked" } },
    route = { atlas = { "Navigation-Tracked-Arrow", "poi-traveldirections-arrow" } },
}
Look.ICONS = ICONS
Look.MARK_SHARE = 0.4



function Look.HasFile(path)
    if type(path) ~= "string" or type(GetFileIDFromPath) ~= "function" then return false end
    local ok, id = pcall(GetFileIDFromPath, path)
    return ok and type(id) == "number" and id > 0
end




function Look.Icon(texture, kind, size)
    if not texture or type(size) ~= "number" or not (size > 0) then return false end
    local icon = ICONS[kind] or ICONS.place
    if Look.Atlas(texture, icon.atlas, size) then return "atlas" end

    if texture.SetTexCoord then texture:SetTexCoord(0, 1, 0, 1) end
    if Look.HasFile(icon.file) then
        texture:SetTexture(icon.file)
        texture:SetSize(size, size)
        return "file"
    end
    local r, g, b = Look.Color("match")
    texture:SetColorTexture(r, g, b, 1)
    local side = max(2, floor(size * Look.MARK_SHARE + 0.5))
    texture:SetSize(side, side)
    return "mark"
end











function Look.HasTemplate(name)
    if type(name) ~= "string" then return false end
    if type(C_XMLUtil) ~= "table" or type(C_XMLUtil.GetTemplateInfo) ~= "function" then return true end
    local ok, info = pcall(C_XMLUtil.GetTemplateInfo, name)
    return ok and type(info) == "table"
end








Look.GROUND_TEMPLATE = "BackdropTemplate"
Look.DIALOG_FILL = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark"
Look.DIALOG_EDGE = "Interface\\DialogFrame\\UI-DialogBox-Border"
Look.GROUND_FILL = { 0.05, 0.05, 0.07, 0.94 }
Look.GROUND_EDGE = { 0.75, 0.61, 0, 0.9 }



local backdrops = {}
function Look.Backdrop(edge)
    edge = type(edge) == "number" and edge > 0 and edge or 16
    local backdrop = backdrops[edge]
    if not backdrop then
        local inset = max(2, floor(edge * 11 / 32 + 0.5))
        backdrop = { bgFile = Look.DIALOG_FILL, edgeFile = Look.DIALOG_EDGE, tile = true, tileSize = 32, edgeSize = edge,
                     insets = { left = inset, right = inset, top = inset, bottom = inset } }
        backdrops[edge] = backdrop
    end
    return backdrop
end




function Look.Ground(frame, edge)
    if not frame then return false end
    if frame.SetBackdrop and not frame.fgpsNoBackdrop and Look.HasFile(Look.DIALOG_FILL) and Look.HasFile(Look.DIALOG_EDGE) then
        local backdrop = Look.Backdrop(edge)
        if pcall(frame.SetBackdrop, frame, backdrop) then
            if frame.SetBackdropColor then frame:SetBackdropColor(1, 1, 1, 1) end
            if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(1, 1, 1, 1) end

            frame.fgpsBackdrop = backdrop
            if frame.fgpsPlainGround then
                for _, texture in ipairs(frame.fgpsPlainGround) do texture:Hide() end
            end
            return "game"
        end
    end
    if frame.SetBackdrop and frame.GetBackdrop and frame:GetBackdrop() ~= nil then pcall(frame.SetBackdrop, frame, nil) end
    if not frame.fgpsPlainGround then
        local fill, edges = Look.PlainGround(frame)
        frame.fgpsPlainGround = { fill, unpack(edges or {}) }
    end
    for _, texture in ipairs(frame.fgpsPlainGround) do texture:Show() end
    return "plain"
end



function Look.CreateGround(frameType, parent, edge)
    local frame
    if Look.HasTemplate(Look.GROUND_TEMPLATE) then
        local ok, made = pcall(CreateFrame, frameType, nil, parent, Look.GROUND_TEMPLATE)
        if ok and made then frame = made end
    end
    if not frame then


        frame = CreateFrame(frameType, nil, parent)
        frame.fgpsNoBackdrop = true
    end
    return frame, Look.Ground(frame, edge)
end



function Look.PlainGround(frame)
    if not (frame and frame.CreateTexture) then return nil end
    local fill = frame:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(frame)
    fill:SetColorTexture(unpack(Look.GROUND_FILL))
    local edges = {}
    for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = frame:CreateTexture(nil, "BORDER")
        edge:SetColorTexture(unpack(Look.GROUND_EDGE))
        if side == "TOP" or side == "BOTTOM" then
            edge:SetHeight(1)
            edge:SetPoint(side .. "LEFT", frame, side .. "LEFT", 0, 0)
            edge:SetPoint(side .. "RIGHT", frame, side .. "RIGHT", 0, 0)
        else
            edge:SetWidth(1)
            edge:SetPoint("TOP" .. side, frame, "TOP" .. side, 0, 0)
            edge:SetPoint("BOTTOM" .. side, frame, "BOTTOM" .. side, 0, 0)
        end
        edges[i] = edge
    end
    return fill, edges
end



Look.HIGHLIGHT_FILE = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
function Look.Highlight(texture)
    if not texture then return false end
    if Look.HasFile(Look.HIGHLIGHT_FILE) then
        texture:SetTexture(Look.HIGHLIGHT_FILE)
        if texture.SetBlendMode then texture:SetBlendMode("ADD") end
        return "file"
    end
    local r, g, b = Look.Color("match")
    texture:SetColorTexture(r, g, b, 0.2)
    return "plain"
end







Look.BUTTON_TEMPLATE = "UIPanelButtonTemplate"
Look.CLOSE_TEMPLATE = "UIPanelCloseButton"
Look.CLOSE_FILES = {
    up = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up",
    down = "Interface\\Buttons\\UI-Panel-MinimizeButton-Down",
    highlight = "Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight",
}
Look.KNOB_FILE = "Interface\\Buttons\\UI-ScrollBar-Knob"

local function fromTemplate(frameType, parent, template)
    if not Look.HasTemplate(template) then return nil end
    local ok, made = pcall(CreateFrame, frameType, nil, parent, template)
    if ok and made then return made end
    return nil
end

local function setLabel(self, text) self:SetText(text or "") end
local function getLabel(self) return self:GetText() end




function Look.Button(parent, text, width, height)
    local button, how = fromTemplate("Button", parent, Look.BUTTON_TEMPLATE), "template"
    if not button then
        button, how = Look.CreateGround("Button", parent, 12), "plain"
        if button.SetNormalFontObject then button:SetNormalFontObject(Look.Font("listTitle")) end
        if button.SetHighlightFontObject then button:SetHighlightFontObject(Look.Font("row")) end
        if button.SetDisabledFontObject then button:SetDisabledFontObject(Look.Font("hint")) end
        local glow = button:CreateTexture(nil, "HIGHLIGHT")
        glow:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -3)
        glow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
        Look.Highlight(glow)
        button.fgpsGlow = glow
    end
    button:SetSize(width or 90, height or 22)
    button:SetText(text or "")
    button.SetLabel, button.GetLabel = setLabel, getLabel
    button.fgpsLook = how
    return button, how
end



function Look.CloseButton(parent, onClick)
    local button, how = fromTemplate("Button", parent, Look.CLOSE_TEMPLATE), "template"
    if not button then
        button = CreateFrame("Button", nil, parent)
        button:SetSize(26, 26)
        if Look.HasFile(Look.CLOSE_FILES.up) then
            how = "files"
            if button.SetNormalTexture then button:SetNormalTexture(Look.CLOSE_FILES.up) end
            if button.SetPushedTexture then button:SetPushedTexture(Look.CLOSE_FILES.down) end
            if button.SetHighlightTexture then button:SetHighlightTexture(Look.CLOSE_FILES.highlight, "ADD") end
        else
            how = "glyph"
            if button.SetNormalFontObject then button:SetNormalFontObject(Look.Font("listTitle")) end
            button:SetText("x")
        end
    end
    if button.RegisterForClicks then button:RegisterForClicks("LeftButtonUp") end
    if onClick then button:SetScript("OnClick", onClick) end
    button.fgpsLook = how
    return button, how
end



Look.GEAR_FILES = { "Interface\\Buttons\\UI-OptionsButton", "Interface\\Icons\\INV_Misc_Gear_01" }
function Look.SettingsButton(parent, onClick)
    local button, how = CreateFrame("Button", nil, parent), "glyph"
    button:SetSize(22, 22)
    button:EnableMouse(true)
    for _, file in ipairs(Look.GEAR_FILES) do
        if Look.HasFile(file) then
            how = file
            if button.SetNormalTexture then button:SetNormalTexture(file) end
            if button.SetHighlightTexture then button:SetHighlightTexture(file, "ADD") end
            break
        end
    end
    if how == "glyph" then
        if button.SetNormalFontObject then button:SetNormalFontObject(Look.Font("listTitle")) end
        button:SetText("S")
    end
    if button.RegisterForClicks then button:RegisterForClicks("LeftButtonUp") end
    if onClick then button:SetScript("OnClick", onClick) end
    button.fgpsLook = how
    return button, how
end



function Look.ScrollKnob(texture)
    if not texture then return false end
    if texture.SetVertexColor then texture:SetVertexColor(1, 1, 1, 1) end
    if Look.HasFile(Look.KNOB_FILE) then
        texture:SetTexture(Look.KNOB_FILE)
        if texture.SetTexCoord then texture:SetTexCoord(0.2, 0.8, 0.25, 0.75) end
        return "file"
    end
    local r, g, b = Look.Color("match")
    texture:SetColorTexture(r, g, b, 0.8)
    return "plain"
end






function Look.EditBox(parent, templates)
    if type(templates) == "table" then
        for _, template in ipairs(templates) do
            local box = fromTemplate("EditBox", parent, template)
            if box then
                box:SetAutoFocus(false)
                return box, template
            end
        end
    end
    local box = Look.CreateGround("EditBox", parent, 12)
    box:SetAutoFocus(false)
    box:SetFontObject(Look.Font("input"))
    if box.SetTextInsets then box:SetTextInsets(8, 8, 0, 0) end
    return box, false
end







Look.SEARCH_TEMPLATES = { "SearchBoxTemplate", "InputBoxTemplate" }
function Look.SearchBox(parent, opts)
    opts = opts or {}
    local box = Look.EditBox(parent, Look.SEARCH_TEMPLATES)
    box:SetSize(opts.width or 160, opts.height or 22)
    if box.SetMaxLetters then box:SetMaxLetters(opts.maxLetters or 80) end
    box.Placeholder = box.Instructions
    if not box.Placeholder then
        box.Placeholder = box:CreateFontString(nil, "OVERLAY", Look.Font("hint"))
        box.Placeholder:SetPoint("LEFT", box, "LEFT", 8, 0)
    end
    box.Placeholder:SetText(opts.placeholder or "")
    local function call(fn, ...)
        local ok, err = pcall(fn, ...)
        if not ok and FGPS.Log then FGPS.Log:Error("Search box handler failed: %s", tostring(err)) end
    end
    box:SetScript("OnEnterPressed", function(self)
        if opts.onEnter then call(opts.onEnter, self, self:GetText()) end
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        if opts.onEscape then call(opts.onEscape, self) end
    end)
    box:HookScript("OnTextChanged", function(self, userInput)
        local text = self:GetText() or ""
        self.Placeholder:SetShown(text == "")
        if opts.onChanged then call(opts.onChanged, self, text, userInput) end
    end)


    if box.ClearButton and box.ClearButton.HookScript and opts.onChanged then
        box.ClearButton:HookScript("OnClick", function() call(opts.onChanged, box, "", true) end)
    end
    return box
end




Look.TAB_DIM = 0.45
function Look.Tab(parent, text, width, height)
    local button, how = Look.Button(parent, text, width, height)
    local mark = button:CreateTexture(nil, "OVERLAY")
    mark:SetPoint("TOPLEFT", button, "TOPLEFT", 4, -3)
    mark:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -4, 3)
    Look.Highlight(mark)
    mark:Hide()
    button.fgpsMark = mark
    return button, how
end



function Look.SelectTab(tabs, chosen)
    if type(tabs) ~= "table" then return end
    for key, button in pairs(tabs) do
        local on = key == chosen
        if button.SetAlpha then button:SetAlpha(on and 1 or Look.TAB_DIM) end
        if button.fgpsMark then button.fgpsMark:SetShown(on) end
    end
end




Look.WINDOW_EDGE = 32
Look.WINDOW_BORDER = 14
Look.WINDOW_TITLE_TOP = 8
Look.WINDOW_TITLE_HEIGHT = 24







Look.UNDERLAY = { 0, 0, 0, 1 }
local function underlay(window)
    local under = window.fgpsUnderlay
    if not under then
        if not window.CreateTexture then return end
        under = window:CreateTexture(nil, "BACKGROUND", nil, -8)
        under:SetColorTexture(unpack(Look.UNDERLAY))
        window.fgpsUnderlay = under
    end
    local inset = window.fgpsGround == "game" and Look.Backdrop(Look.WINDOW_EDGE).insets.left or 0
    under:ClearAllPoints()
    under:SetPoint("TOPLEFT", window, "TOPLEFT", inset, -inset)
    under:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -inset, inset)
    under:Show()
end

local function dressWindowNow(window)
    local look = Look
    window.fgpsGround = look.Ground(window, Look.WINDOW_EDGE)
    underlay(window)
    if window.SetAlpha then window:SetAlpha(1) end
    local bar = window.TitleBar
    if bar then
        if bar.Bg then bar.Bg:Hide() end
        if bar.Accent then bar.Accent:Hide() end
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", window, "TOPLEFT", Look.WINDOW_BORDER - 2, -Look.WINDOW_TITLE_TOP)
        bar:SetPoint("TOPRIGHT", window, "TOPRIGHT", -(Look.WINDOW_BORDER + 16), -Look.WINDOW_TITLE_TOP)
        bar:SetHeight(Look.WINDOW_TITLE_HEIGHT)
    end
    if window.Title then
        window.Title:SetFontObject(look.Font("listTitle"))
        window.Title:SetTextColor(look.Color("header"))
    end
    if window.Close then window.Close:Hide() end
    if window.Content then
        window.Content:ClearAllPoints()
        window.Content:SetPoint("TOPLEFT", window, "TOPLEFT", Look.WINDOW_BORDER, -(Look.WINDOW_TITLE_TOP + Look.WINDOW_TITLE_HEIGHT + 2))
        window.Content:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -Look.WINDOW_BORDER, Look.WINDOW_BORDER)
    end
end







function Look.DressWindow(window)
    if type(window) ~= "table" then return end
    local F = FGPS.UI.Frames
    if not window.fgpsClose then
        local close = Look.CloseButton(window, function() window:Hide() end)
        close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -5, -5)


        local function raise()
            local bar = window.TitleBar
            if close.SetFrameLevel and bar and bar.GetFrameLevel then close:SetFrameLevel((bar:GetFrameLevel() or 1) + 5) end
        end
        raise()
        if window.HookScript then window:HookScript("OnShow", raise) end
        if F and F.Tooltip then pcall(F.Tooltip, close, FGPS.L["Close"]) end
        window.fgpsClose = close
    end
    dressWindowNow(window)
    if F and F.Register and not window.fgpsDressed then
        window.fgpsDressed = true
        local skinPass = window.fgpsApplySkin
        F.Register(window, function(w, skin)
            if skinPass then skinPass(w, skin) end
            dressWindowNow(w)
        end)
    end
end



local function dressListNow(list)
    local bar = list.Bar
    if bar then
        if bar.Track then bar.Track:SetColorTexture(0, 0, 0, 0.35) end
        if bar.fgpsThumb then Look.ScrollKnob(bar.fgpsThumb) end
    end
    if list.Empty then
        list.Empty:SetFontObject(Look.Font("hint"))
        list.Empty:SetTextColor(Look.Color("grey"))
    end
end






function Look.DressList(list)
    if type(list) ~= "table" then return end
    dressListNow(list)
    local F = FGPS.UI.Frames
    if F and F.Register and not list.fgpsDressed then
        list.fgpsDressed = true
        local skinPass = list.fgpsApplySkin
        F.Register(list, function(l, skin)
            if skinPass then skinPass(l, skin) end
            dressListNow(l)
            if l.Refresh then l:Refresh() end
        end)
    end
end




Look.CHECK_TEMPLATE = "UICheckButtonTemplate"
Look.CHECK_FILES = {
    up = "Interface\\Buttons\\UI-CheckBox-Up", down = "Interface\\Buttons\\UI-CheckBox-Down",
    highlight = "Interface\\Buttons\\UI-CheckBox-Highlight", check = "Interface\\Buttons\\UI-CheckBox-Check",
}
function Look.CheckButton(parent, text)
    local button, how = fromTemplate("CheckButton", parent, Look.CHECK_TEMPLATE), "template"
    if not button then
        button, how = CreateFrame("CheckButton", nil, parent), "files"
        if button.SetNormalTexture then button:SetNormalTexture(Look.CHECK_FILES.up) end
        if button.SetPushedTexture then button:SetPushedTexture(Look.CHECK_FILES.down) end
        if button.SetHighlightTexture then button:SetHighlightTexture(Look.CHECK_FILES.highlight, "ADD") end
        if button.SetCheckedTexture then button:SetCheckedTexture(Look.CHECK_FILES.check) end
    end
    button:SetSize(24, 24)
    local label = button.Text or button.text
    if not label then
        label = button:CreateFontString(nil, "OVERLAY", Look.Font("listTitle"))
        label:SetPoint("LEFT", button, "RIGHT", 2, 1)
    end
    label:SetText(text or "")
    button.Label = label
    button.fgpsLook = how
    return button, how
end









Look.PANEL_BORDER_TEMPLATE = "DialogBorderTranslucentTemplate"
Look.SLIDER_TEMPLATE = "MinimalSliderWithSteppersTemplate"




function Look.EditPanel(parent)
    if Look.HasTemplate(Look.PANEL_BORDER_TEMPLATE) then
        local panel = CreateFrame("Frame", nil, parent)
        local border = fromTemplate("Frame", panel, Look.PANEL_BORDER_TEMPLATE)
        if border then
            border:SetAllPoints(panel)
            panel.Border = border
            return panel, "template"
        end
        panel:Hide()
    end
    return Look.CreateGround("Frame", parent, Look.WINDOW_EDGE)
end





function Look.StepperSlider(parent, width)
    local slider = fromTemplate("Frame", parent, Look.SLIDER_TEMPLATE)
    if not slider then return false end
    if not (type(slider.Init) == "function" and type(slider.SetValue) == "function"
            and type(slider.RegisterCallback) == "function" and type(slider.Slider) == "table") then
        slider:Hide()
        return false
    end
    slider:SetWidth(type(width) == "number" and width > 0 and width or 200)
    slider.fgpsLook = "template"
    return slider, "template"
end






function Look.HexColor(hex)
    if type(hex) ~= "string" then return nil end
    local r, g, b = hex:match("^(%x%x)(%x%x)(%x%x)$")
    if not r then return nil end
    return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
end



function Look.ColorHex(r, g, b)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
    local function byte(v)
        if v ~= v or v < 0 then return 0 end
        if v > 1 then return 255 end
        return floor(v * 255 + 0.5)
    end
    return format("%02x%02x%02x", byte(r), byte(g), byte(b))
end





Look.SWATCH_TEMPLATE = "ColorSwatchTemplate"
local function setSwatchColor(self, r, g, b) self.Swatch:SetColorRGB(r, g, b) end
local function plainSwatchColor(self, r, g, b) self.Color:SetVertexColor(r, g, b) end
function Look.ColorSwatch(parent)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(24, 24)
    local swatch, how = fromTemplate("Frame", button, Look.SWATCH_TEMPLATE), "template"
    if swatch and not (type(swatch.SetColorRGB) == "function" and type(swatch.Color) == "table") then
        swatch:Hide()
        swatch = nil
    end
    if not swatch then
        how = "plain"
        swatch = CreateFrame("Frame", nil, button)
        swatch:SetSize(16, 16)
        for _, part in ipairs({ { "SwatchBg", 14, 1 }, { "InnerBorder", 12, 0 }, { "Color", 10, 1 } }) do
            local texture = swatch:CreateTexture(nil, "BACKGROUND")
            texture:SetSize(part[2], part[2])
            texture:SetPoint("CENTER", swatch, "CENTER", 0, 0)
            texture:SetColorTexture(part[3], part[3], part[3], 1)
            swatch[part[1]] = texture
        end
        swatch.SetColorRGB = plainSwatchColor
    end
    swatch:SetPoint("CENTER", button, "CENTER", 0, 0)
    if swatch.SetScale then swatch:SetScale(1.5) end
    button.Swatch = swatch
    button.SetColorRGB = setSwatchColor
    if button.RegisterForClicks then button:RegisterForClicks("LeftButtonUp") end
    button.fgpsLook = how
    return button, how
end





Look.PICTURE_FILES = { highlight = "Interface\\Buttons\\ButtonHilight-Square", chosen = "Interface\\Buttons\\CheckButtonHilight" }
local function setChosen(self, on)
    if on then self.Chosen:Show() else self.Chosen:Hide() end
end
function Look.PictureButton(parent, size)
    size = type(size) == "number" and size > 0 and size or 32
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    local ground = button:CreateTexture(nil, "BACKGROUND")
    ground:SetAllPoints(button)
    ground:SetColorTexture(0, 0, 0, 0.35)
    button.Icon = button:CreateTexture(nil, "ARTWORK")
    button.Icon:SetSize(size - 6, size - 6)
    button.Icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.Glow = button:CreateTexture(nil, "HIGHLIGHT")
    button.Glow:SetAllPoints(button)
    button.Chosen = button:CreateTexture(nil, "OVERLAY")
    button.Chosen:SetAllPoints(button)
    local how = "plain"
    if Look.HasFile(Look.PICTURE_FILES.highlight) and Look.HasFile(Look.PICTURE_FILES.chosen) then
        how = "file"
        button.Glow:SetTexture(Look.PICTURE_FILES.highlight)
        button.Chosen:SetTexture(Look.PICTURE_FILES.chosen)
        for _, texture in ipairs({ button.Glow, button.Chosen }) do
            if texture.SetBlendMode then texture:SetBlendMode("ADD") end
        end
    else
        button.Glow:SetColorTexture(1, 1, 1, 0.15)
        local r, g, b = Look.Color("match")
        button.Chosen:SetColorTexture(r, g, b, 0.35)
    end
    button.Chosen:Hide()
    button.SetChosen = setChosen
    if button.RegisterForClicks then button:RegisterForClicks("LeftButtonUp") end
    button.fgpsLook = how
    return button, how
end


function Look.CanPickColor()
    local picker = ColorPickerFrame
    return type(picker) == "table" and type(picker.SetupColorPickerAndShow) == "function"
        and type(picker.GetColorRGB) == "function"
end






function Look.PickColor(r, g, b, onPick, onCancel)
    if not Look.CanPickColor() then return false end
    local picker = ColorPickerFrame
    local ok = pcall(picker.SetupColorPickerAndShow, picker, {
        r = r, g = g, b = b, hasOpacity = false,
        swatchFunc = function()
            local nr, ng, nb = picker:GetColorRGB()
            if onPick and type(nr) == "number" then onPick(nr, ng, nb) end
        end,
        cancelFunc = function()
            if onCancel then onCancel(r, g, b) end
        end,
    })
    return ok
end
