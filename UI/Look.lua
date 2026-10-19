





local ADDON_NAME, FGPS = ...

local type, floor, format, max, pcall, huge = type, math.floor, string.format, math.max, pcall, math.huge
local ipairs, unpack = ipairs, unpack

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




Look.WINDOW_EDGE = 32
Look.WINDOW_BORDER = 14
Look.WINDOW_TITLE_TOP = 8
Look.WINDOW_TITLE_HEIGHT = 24

local function dressWindowNow(window)
    local look = Look
    window.fgpsGround = look.Ground(window, Look.WINDOW_EDGE)
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
