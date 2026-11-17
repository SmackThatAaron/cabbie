










local ADDON_NAME, FGPS = ...

local L = FGPS.L
local type, pcall, format, ipairs = type, pcall, string.format, ipairs

local Menus = { bound = false }
FGPS.UI.Menus = Menus

do
    local Look = FGPS.UI.Look
    if Look and Look.ShimMenuVariants then Look.ShimMenuVariants() end
end


Menus.STOPPED_HOLD = 6




Menus.UNDO_CLICK_DELAY = 0.5





local function inCombat()
    return InCombatLockdown ~= nil and InCombatLockdown() == true
end

local function now()
    return (GetTime and GetTime()) or 0
end

local function readMapIdTaint()
    if type(issecurevariable) ~= "function" or type(WorldMapFrame) ~= "table" then return nil end
    local ok, secure, source = pcall(issecurevariable, WorldMapFrame, "mapID")
    if not ok then return nil end
    if issecretvalue and (issecretvalue(secure) or issecretvalue(source)) then return nil end
    return { secure = secure and true or false, source = type(source) == "string" and source or nil }
end



local function noteShowOnMapOpen()
    if not (FGPS.IsOwnerInstall and FGPS.IsOwnerInstall()) then return end
    local reading = readMapIdTaint()
    if not reading then return end
    Menus.showOnMapTaint = { afterOpen = reading }
    Menus.awaitingMapShownTaint = true
end




function Menus.ShowOnMap(mapID)
    if type(OpenWorldMap) ~= "function" or inCombat() then return false end
    mapID = tonumber(mapID)
    if mapID then
        OpenWorldMap(mapID)
    else
        local Navigator = FGPS.Navigator
        local route = Navigator and Navigator.GetRoute and Navigator:GetRoute() or nil
        local stops = type(route) == "table" and route.stops or nil
        local stop = type(stops) == "table" and stops[#stops] or nil
        local dest = stop and (stop.dest or stop) or nil
        OpenWorldMap(type(dest) == "table" and dest.map or nil)
    end
    noteShowOnMapOpen()
    return true
end


local function routeStopped()
    local Guide = FGPS.UI.Guide
    return Guide ~= nil and Guide.IsStopped ~= nil and Guide.IsStopped() == true
end





function Menus.BringBack()
    local Navigator, Guide = FGPS.Navigator, FGPS.UI.Guide
    local back = Navigator ~= nil and Navigator.UndoClear ~= nil and Navigator:UndoClear({ quiet = true }) == true
    if not back and Guide and Guide.HideStopped then Guide.HideStopped() end
    return back
end

local function addResetPosition(root)
    root:CreateButton(L["Reset Position"], function()
        local RouteBlock = FGPS.UI.RouteBlock
        if RouteBlock and RouteBlock.ResetPlace then RouteBlock.ResetPlace() end
    end)
end






local function addGoToCorpse(root)
    local Social = FGPS.Social
    if not (Social and Social.IsGhost and Social.GoToCorpse and Social.IsGhost()) then return end
    root:CreateButton(L["Go to My Corpse"], function() Social.GoToCorpse(true) end)
end




local function addHowToUse(root)
    root:CreateButton(L["How to Use Cabbie"], function()
        local Line = FGPS.UI.SearchLine
        if Line and Line.Guide then Line.Guide() end
    end)
end








local function stopRoute()
    local Navigator = FGPS.Navigator
    if not (Navigator and Navigator.Clear) then return end
    local stops = Navigator.GetStops and Navigator:GetStops() or nil
    local undo = type(stops) == "table" and #stops > 0
    local Guide, RouteBlock = FGPS.UI.Guide, FGPS.UI.RouteBlock
    if not (Navigator:Clear("user", { quiet = true }) and undo and Guide) then return end
    Menus.stoppedAt = now()
    if Guide.ShowStopped then Guide.ShowStopped() end
    local blockSaysIt = Guide.ShowStopped ~= nil and RouteBlock ~= nil and RouteBlock.Wanted ~= nil and RouteBlock.Wanted() == true
    if not blockSaysIt and Guide.Say then Guide.Say(L["Route stopped."], Menus.STOPPED_HOLD) end
end

local function isPlace(dest)
    return type(dest) == "table" and type(dest.inst) == "number"
        and type(dest.x) == "number" and type(dest.y) == "number"
end



local function routeDest(owner)
    if type(owner) == "table" and isPlace(owner.fgpsDest) then return owner.fgpsDest end
    local Navigator = FGPS.Navigator
    local stops = Navigator and Navigator.GetStops and Navigator:GetStops() or nil
    if type(stops) == "table" and isPlace(stops[#stops]) then return stops[#stops] end
    local route = Navigator and Navigator.GetRoute and Navigator:GetRoute() or nil
    local routeStops = type(route) == "table" and route.stops or nil
    local last = type(routeStops) == "table" and routeStops[#routeStops] or nil
    local dest = last and (last.dest or last) or nil
    if isPlace(dest) then return dest end
    return nil
end

local function addFavorite(owner, root)
    local dest = routeDest(owner)
    local Search = FGPS.UI.Search
    if not (dest and Search and Search.ToggleFavorite) then return end
    local Destinations = FGPS.Destinations
    local favorite = Destinations and Destinations.IsFavorite and Destinations.IsFavorite(dest) and true or false
    root:CreateButton(favorite and L["Remove from Favorites"] or L["Add to Favorites"], function()
        Search:ToggleFavorite(dest)
    end)
end


local function addTitle(root)
    if type(root.CreateTitle) == "function" then root:CreateTitle(L["Route"]) end
end

function Menus.RouteMenu(owner, root)
    local Navigator = FGPS.Navigator
    local state = Navigator and Navigator.GetState and Navigator:GetState() or "idle"
    addTitle(root)

    if routeStopped() then
        root:CreateButton(L["Bring the Route Back"], function() Menus.BringBack() end)
        addGoToCorpse(root)
        addResetPosition(root)
        addHowToUse(root)
        return
    end
    addGoToCorpse(root)


    if state == "paused" then
        root:CreateButton(L["Resume"], function()
            if Navigator and Navigator.Resume then Navigator:Resume() end
        end)
    elseif state == "active" or state == "in_transit" then
        root:CreateButton(L["Pause"], function()
            if Navigator and Navigator.Pause then Navigator:Pause() end
        end)
    end
    if not inCombat() then
        root:CreateButton(L["Show on Map"], function() Menus.ShowOnMap() end)
    end
    addResetPosition(root)
    addFavorite(owner, root)
    addHowToUse(root)


    if type(root.CreateDivider) == "function" then root:CreateDivider() end
    root:CreateButton(L["Stop Route"], stopRoute)
end







Menus.KEYS_TEMPLATE = "InsecureKeyboardInputPropagatorTemplate"
Menus.FALLBACK_POLL_SECONDS = 0.2
Menus.FALLBACK_PAD_X = 10
Menus.FALLBACK_PAD_Y = 8
Menus.FALLBACK_ROW_HEIGHT = 20
Menus.FALLBACK_TITLE_HEIGHT = 20
Menus.FALLBACK_DIVIDER_HEIGHT = 8
Menus.FALLBACK_MIN_WIDTH = 140
Menus.FALLBACK_MAX_WIDTH = 320

local rootPane
local subPane
local fallbackWatcher
local activeFallback

local function evalEnabled(val)
    if val == nil then return true end
    if type(val) == "function" then
        local ok, yes = pcall(val)
        return ok and yes and true or false
    end
    return val and true or false
end

local function evalSelected(fn, data)
    if type(fn) ~= "function" then return fn and true or false end
    local ok, yes = pcall(fn, data)
    return ok and yes and true or false
end

local function attachElementMethods(node)
    function node:SetTag(tag, contextData)
        self.tag, self.contextData = tag, contextData
    end
    function node:SetEnabled(val)
        self.enabled = val
        return self
    end
    function node:IsEnabled()
        return evalEnabled(self.enabled)
    end
    function node:ShouldPollEnabled()
        return type(self.enabled) == "function"
    end
    function node:SetResponder(fn)
        self.callback = fn
        return self
    end
    local function pushChild(kind, text, callback, extra)
        local el = {
            kind = kind,
            text = text or "",
            callback = callback,
            elements = {},
        }
        if extra then
            for k, v in pairs(extra) do el[k] = v end
        end
        attachElementMethods(el)
        node.elements[#node.elements + 1] = el
        return el
    end
    function node:CreateTitle(text)
        return pushChild("title", text, nil)
    end
    function node:CreateDivider()
        return pushChild("divider", "", nil)
    end
    function node:CreateButton(text, callback, data)
        return pushChild("button", text, callback, { data = data })
    end
    function node:CreateRedHighlightButton(text, callback, data)
        return pushChild("button", text, callback, { data = data, red = true })
    end
    function node:CreateCheckbox(text, isSelected, setSelected, data)
        return pushChild("checkbox", text, setSelected, {
            isSelected = isSelected,
            setSelected = setSelected,
            data = data,
        })
    end
    function node:CreateRadio(text, isSelected, setSelected, data)
        return pushChild("radio", text, setSelected, {
            isSelected = isSelected,
            setSelected = setSelected,
            data = data,
        })
    end
    return node
end

local function newFallbackDescription()
    return attachElementMethods({ elements = {} })
end

local function setFallbackPropagation(frame, on)
    if inCombat() or not (frame and frame.SetPropagateKeyboardInput) then return end
    pcall(frame.SetPropagateKeyboardInput, frame, on)
end

local function fallbackLetsKeysThrough(frame)
    setFallbackPropagation(frame, true)
    if not (frame and frame.GetPropagateKeyboardInput) then return false end
    local ok, on = pcall(frame.GetPropagateKeyboardInput, frame)
    return ok and on == true
end

local function syncFallbackKeyboard(frame, wanted)
    if not (frame and frame.EnableKeyboard) then return end
    if wanted and frame:IsVisible() and fallbackLetsKeysThrough(frame) then
        frame:EnableKeyboard(true)
    else
        frame:EnableKeyboard(false)
    end
end

local function paneHasMouse(pane)
    if not (pane and pane.frame and pane.frame:IsShown()) then return false end
    if pane.frame.IsMouseOver and pane.frame:IsMouseOver() then return true end
    return false
end

function Menus.CloseFallbackMenu()
    local was = activeFallback
    activeFallback = nil
    Menus.fallbackMenu = nil
    if subPane and subPane.frame then
        subPane.activeElements = nil
        subPane.frame:Hide()
    end
    if rootPane and rootPane.frame then
        rootPane.activeElements = nil
        syncFallbackKeyboard(rootPane.frame, false)
        rootPane.frame:Hide()
    end
    return was ~= nil
end

local function ensureFallbackWatcher()
    if fallbackWatcher or type(CreateFrame) ~= "function" then return end
    fallbackWatcher = CreateFrame("Frame", nil, UIParent)
    fallbackWatcher:Hide()
    pcall(fallbackWatcher.RegisterEvent, fallbackWatcher, "GLOBAL_MOUSE_DOWN")
    pcall(fallbackWatcher.RegisterEvent, fallbackWatcher, "PLAYER_REGEN_DISABLED")
    fallbackWatcher:SetScript("OnEvent", function(_, event)
        if not activeFallback then return end
        if event == "PLAYER_REGEN_DISABLED" then
            if rootPane and rootPane.frame and rootPane.frame.EnableKeyboard then
                rootPane.frame:EnableKeyboard(false)
            end
            return
        end
        if event == "GLOBAL_MOUSE_DOWN" then
            if not paneHasMouse(rootPane) and not paneHasMouse(subPane) then
                Menus.CloseFallbackMenu()
            end
        end
    end)
end

local function createPopupFrame(Look, withKeyboard, level)
    local frame, how
    if withKeyboard and Look.HasTemplate(Look.GROUND_TEMPLATE) and Look.HasTemplate(Menus.KEYS_TEMPLATE) then
        local ok, made = pcall(CreateFrame, "Frame", nil, UIParent, Look.GROUND_TEMPLATE .. "," .. Menus.KEYS_TEMPLATE)
        if ok and made then
            how = Look.Ground(made, 16)
            frame = made
        end
    end
    if not frame then
        frame, how = Look.CreateGround("Frame", UIParent, 16)
    end
    frame:Hide()
    if frame.SetFrameStrata then frame:SetFrameStrata("TOOLTIP") end
    if frame.SetFrameLevel then frame:SetFrameLevel(level) end
    if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
    frame:EnableMouse(true)
    local inset = how == "game" and 4 or 0
    local underlay = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    underlay:SetColorTexture(0.05, 0.05, 0.07, 0.96)
    underlay:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    underlay:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
    frame.fgpsUnderlay = underlay
    return {
        frame = frame,
        titles = {},
        dividers = {},
        buttons = {},
        activeButtons = {},
    }
end

local function paintButtonState(btn)
    local Look = FGPS.UI.Look
    local el = btn.fgpsElement
    if not el then return end
    local enabled = el:IsEnabled()
    btn.fgpsEnabled = enabled
    if enabled then btn:Enable() else btn:Disable() end
    if not enabled and btn.Glow then btn.Glow:Hide() end
    if not enabled then
        btn.Label:SetTextColor(Look.Color("grey"))
    elseif el.red then
        if btn.fgpsHover then
            btn.Label:SetTextColor(1, 1, 1, 1)
        else
            btn.Label:SetTextColor(1, 0.25, 0.25, 1)
        end
    else
        btn.Label:SetTextColor(1, 1, 1, 1)
    end
    if btn.ArrowText then
        if enabled then
            btn.ArrowText:SetTextColor(Look.Color("header"))
        else
            btn.ArrowText:SetTextColor(Look.Color("grey"))
        end
    end
    if el.kind == "checkbox" or el.kind == "radio" then
        local checked = evalSelected(el.isSelected, el.data)
        btn.CheckBox:Show()
        if checked then
            local checkFile = el.kind == "radio"
                and "Interface\\Buttons\\UI-RadioButton"
                or "Interface\\Buttons\\UI-CheckBox-Check"
            if Look.HasFile(checkFile) then
                btn.CheckMark:SetTexture(checkFile)
                if btn.CheckMark.SetTexCoord then
                    if el.kind == "radio" then
                        btn.CheckMark:SetTexCoord(0.25, 0.5, 0, 1)
                    else
                        btn.CheckMark:SetTexCoord(0, 1, 0, 1)
                    end
                end
            else
                local r, g, b = Look.Color("match")
                btn.CheckMark:SetColorTexture(r, g, b, 1)
            end
            btn.CheckMark:Show()
        else
            btn.CheckMark:Hide()
        end
    else
        btn.CheckBox:Hide()
        btn.CheckMark:Hide()
    end
end

local renderPane

local function refreshOpenPanes()
    if rootPane and rootPane.frame and rootPane.frame:IsShown() then
        for _, btn in ipairs(rootPane.activeButtons) do paintButtonState(btn) end
    end
    if subPane and subPane.frame and subPane.frame:IsShown() then
        for _, btn in ipairs(subPane.activeButtons) do paintButtonState(btn) end
    end
end

local function screenBounds()
    local w = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
    local h = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
    if type(w) ~= "number" or w <= 0 then w = 1024 end
    if type(h) ~= "number" or h <= 0 then h = 768 end
    return w, h
end

local function placeRootAtCursor(frame, owner, width, height)
    local screenW, screenH = screenBounds()
    local cx, cy
    if type(GetCursorPosition) == "function" then
        local ok, rawX, rawY = pcall(GetCursorPosition)
        if ok and type(rawX) == "number" and type(rawY) == "number" then
            local scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
            if type(scale) ~= "number" or scale <= 0 then scale = 1 end
            cx, cy = rawX / scale, rawY / scale
        end
    end
    if not cx and type(owner) == "table" and owner.GetLeft and owner.GetBottom then
        local left, bottom = owner:GetLeft(), owner:GetBottom()
        if type(left) == "number" and type(bottom) == "number" then
            cx, cy = left, bottom
        end
    end
    if not cx then cx, cy = screenW * 0.5, screenH * 0.5 end
    local x = math.max(4, math.min(cx, math.max(4, screenW - width - 4)))
    local top = cy
    if top - height < 4 then
        top = math.min(screenH - 4, math.max(height + 4, cy + height))
    else
        top = math.min(screenH - 4, top)
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, top)
end

local function placeSubPaneBeside(frame, parentBtn, width, height)
    local screenW, screenH = screenBounds()
    local left = parentBtn.GetLeft and parentBtn:GetLeft()
    local right = parentBtn.GetRight and parentBtn:GetRight()
    local top = parentBtn.GetTop and parentBtn:GetTop()
    if type(right) ~= "number" or type(top) ~= "number" then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", parentBtn, "TOPRIGHT", -2, Menus.FALLBACK_PAD_Y)
        return
    end
    local x = right - 2
    if x + width > screenW - 4 and type(left) == "number" then
        x = math.max(4, left - width + 2)
    end
    local yTop = math.min(screenH - 4, top + Menus.FALLBACK_PAD_Y)
    if yTop - height < 4 then
        yTop = math.min(screenH - 4, math.max(height + 4, height + 4))
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, yTop)
end

local function acquirePopupButton(pane, index)
    local btn = pane.buttons[index]
    if btn then return btn end
    local Look = FGPS.UI.Look
    btn = CreateFrame("Button", nil, pane.frame)
    btn:SetHeight(Menus.FALLBACK_ROW_HEIGHT)
    btn:RegisterForClicks("LeftButtonUp")
    btn.Glow = btn:CreateTexture(nil, "BACKGROUND")
    btn.Glow:SetAllPoints(btn)
    Look.Highlight(btn.Glow)
    btn.Glow:Hide()
    btn.CheckBox = btn:CreateTexture(nil, "BORDER")
    btn.CheckBox:SetSize(14, 14)
    btn.CheckBox:SetPoint("LEFT", btn, "LEFT", 2, 0)
    btn.CheckBox:SetColorTexture(0.35, 0.35, 0.38, 0.65)
    btn.CheckBox:Hide()
    btn.CheckMark = btn:CreateTexture(nil, "ARTWORK")
    btn.CheckMark:SetSize(14, 14)
    btn.CheckMark:SetPoint("CENTER", btn.CheckBox, "CENTER", 0, 0)
    btn.CheckMark:Hide()
    btn.Label = Look.FontString(btn, "OVERLAY", "row")
    btn.Label:SetJustifyH("LEFT")
    if btn.Label.SetWordWrap then btn.Label:SetWordWrap(false) end
    btn.ArrowText = Look.FontString(btn, "OVERLAY", "rowSmall")
    btn.ArrowText:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
    btn.ArrowText:SetText(">")
    btn.ArrowText:Hide()

    btn:SetScript("OnEnter", function(self)
        local el = self.fgpsElement
        if not el then return end
        self.fgpsHover = true
        if el:IsEnabled() then
            if el.red then
                self.Glow:SetVertexColor(1, 0.2, 0.2, 0.85)
            else
                self.Glow:SetVertexColor(1, 1, 1, 1)
            end
            self.Glow:Show()
        end
        paintButtonState(self)
        if pane == rootPane then
            if #el.elements > 0 and el:IsEnabled() then
                if not subPane then subPane = createPopupFrame(FGPS.UI.Look, false, 9520) end
                local sw, sh = renderPane(subPane, el.elements)
                placeSubPaneBeside(subPane.frame, self, sw, sh)
                subPane.frame:Show()
                if activeFallback then activeFallback.subFrame = subPane.frame end
            elseif subPane and subPane.frame then
                subPane.frame:Hide()
            end
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self.fgpsHover = false
        self.Glow:Hide()
        paintButtonState(self)
    end)
    btn:SetScript("OnClick", function(self)
        local el = self.fgpsElement
        if not el or not el:IsEnabled() then return end
        if #el.elements > 0 then
            if pane == rootPane then
                if not subPane then subPane = createPopupFrame(FGPS.UI.Look, false, 9520) end
                local sw, sh = renderPane(subPane, el.elements)
                placeSubPaneBeside(subPane.frame, self, sw, sh)
                subPane.frame:Show()
                if activeFallback then activeFallback.subFrame = subPane.frame end
            end
            return
        end
        if el.kind == "checkbox" or el.kind == "radio" then
            if type(el.setSelected) == "function" then
                local ok, resp = pcall(el.setSelected, el.data)
                if not ok and FGPS.Log then
                    FGPS.Log:Error("Context menu option %s failed: %s", tostring(el.text), tostring(resp))
                end
                local refreshCode = (_G.MenuResponse and _G.MenuResponse.Refresh) or 2
                if ok and resp == refreshCode then
                    refreshOpenPanes()
                    return
                end
            end
            Menus.CloseFallbackMenu()
            return
        end
        Menus.CloseFallbackMenu()
        if type(el.callback) == "function" then
            local ok, err = pcall(el.callback, el.data)
            if not ok and FGPS.Log then
                FGPS.Log:Error("Context menu entry %s failed: %s", tostring(el.text), tostring(err))
            end
        end
    end)
    pane.buttons[index] = btn
    return btn
end

renderPane = function(pane, elements)
    local Look = FGPS.UI.Look
    pane.activeElements = elements
    for i = #pane.activeButtons, 1, -1 do pane.activeButtons[i] = nil end
    local hasChecks, hasSubs = false, false
    for _, el in ipairs(elements) do
        if el.kind == "checkbox" or el.kind == "radio" then hasChecks = true end
        if #el.elements > 0 then hasSubs = true end
    end
    local leftGutter = hasChecks and 20 or 0
    local rightGutter = hasSubs and 16 or 0
    local padX, padY = Menus.FALLBACK_PAD_X, Menus.FALLBACK_PAD_Y
    local titleIdx, divIdx, btnIdx = 0, 0, 0
    local maxTextW = 0
    local rows = {}

    for _, el in ipairs(elements) do
        if el.kind == "title" then
            titleIdx = titleIdx + 1
            local title = pane.titles[titleIdx]
            if not title then
                title = Look.FontString(pane.frame, "OVERLAY", "listTitle")
                title:SetJustifyH("LEFT")
                if title.SetWordWrap then title:SetWordWrap(false) end
                pane.titles[titleIdx] = title
            else
                Look.ApplyFont(title, "listTitle")
            end
            title:SetTextColor(Look.Color("header"))
            title:SetText(el.text or "")
            local tw = title.GetStringWidth and title:GetStringWidth() or 0
            if tw > maxTextW then maxTextW = tw end
            rows[#rows + 1] = { kind = "title", widget = title, height = Menus.FALLBACK_TITLE_HEIGHT }
        elseif el.kind == "divider" then
            divIdx = divIdx + 1
            local div = pane.dividers[divIdx]
            if not div then
                div = pane.frame:CreateTexture(nil, "ARTWORK")
                div:SetColorTexture(0.65, 0.58, 0.42, 0.35)
                pane.dividers[divIdx] = div
            end
            rows[#rows + 1] = { kind = "divider", widget = div, height = Menus.FALLBACK_DIVIDER_HEIGHT }
        else
            btnIdx = btnIdx + 1
            local btn = acquirePopupButton(pane, btnIdx)
            btn.fgpsElement = el
            btn.fgpsHover = false
            btn.Glow:Hide()
            Look.ApplyFont(btn.Label, "row")
            btn.Label:SetText(el.text or "")
            local tw = (btn.Label.GetStringWidth and btn.Label:GetStringWidth() or 0) + leftGutter + rightGutter
            if tw > maxTextW then maxTextW = tw end
            btn.ArrowText:SetShown(#el.elements > 0)
            paintButtonState(btn)
            pane.activeButtons[#pane.activeButtons + 1] = btn
            rows[#rows + 1] = { kind = "button", widget = btn, height = Menus.FALLBACK_ROW_HEIGHT }
        end
    end

    for i = titleIdx + 1, #pane.titles do pane.titles[i]:Hide() end
    for i = divIdx + 1, #pane.dividers do pane.dividers[i]:Hide() end
    for i = btnIdx + 1, #pane.buttons do
        pane.buttons[i].fgpsElement = nil
        pane.buttons[i]:Hide()
    end

    local innerW = math.max(Menus.FALLBACK_MIN_WIDTH - 2 * padX,
        math.min(Menus.FALLBACK_MAX_WIDTH - 2 * padX, math.ceil(maxTextW) + 12))
    local width = innerW + 2 * padX
    local y = padY
    for _, r in ipairs(rows) do
        local w = r.widget
        w:ClearAllPoints()
        if r.kind == "title" then
            w:SetPoint("TOPLEFT", pane.frame, "TOPLEFT", padX, -y)
            w:SetWidth(innerW)
            w:SetHeight(r.height)
            w:Show()
        elseif r.kind == "divider" then
            local mid = math.floor(r.height * 0.5)
            w:SetPoint("TOPLEFT", pane.frame, "TOPLEFT", padX, -(y + mid))
            w:SetPoint("TOPRIGHT", pane.frame, "TOPRIGHT", -padX, -(y + mid))
            w:SetHeight(1)
            w:Show()
        else
            w:SetPoint("TOPLEFT", pane.frame, "TOPLEFT", padX, -y)
            w:SetSize(innerW, r.height)
            w.Label:ClearAllPoints()
            w.Label:SetPoint("LEFT", w, "LEFT", leftGutter + 4, 0)
            w.Label:SetPoint("RIGHT", w, "RIGHT", -(rightGutter + 4), 0)
            w:Show()
        end
        y = y + r.height
    end
    local height = y + padY
    pane.frame:SetSize(width, height)
    return width, height
end

local function ensureRootPane()
    if rootPane then return rootPane end
    local Look = FGPS.UI.Look
    rootPane = createPopupFrame(Look, true, 9500)
    rootPane.frame:SetScript("OnKeyDown", function(frame, key)
        if key ~= "ESCAPE" or not activeFallback then return end
        local later = not inCombat() and C_Timer and C_Timer.After
        if later then setFallbackPropagation(frame, false) end
        Menus.CloseFallbackMenu()
        if later then
            C_Timer.After(0, function() setFallbackPropagation(frame, true) end)
        end
    end)
    rootPane.frame:SetScript("OnUpdate", function(_, elapsed)
        local current = activeFallback
        if not current then return end
        local tracked = current.trackedOwner
        if tracked and tracked.IsVisible and not tracked:IsVisible() then
            Menus.CloseFallbackMenu()
            return
        end
        current.pollElapsed = (current.pollElapsed or 0) + (tonumber(elapsed) or 0)
        if current.pollElapsed >= Menus.FALLBACK_POLL_SECONDS then
            current.pollElapsed = 0
            refreshOpenPanes()
        end
    end)
    return rootPane
end

local function openFallbackPopup(owner, generator)
    Menus.CloseFallbackMenu()
    local desc = newFallbackDescription()
    local ok, err = pcall(generator, owner or UIParent, desc)
    if not ok then
        if FGPS.Log then FGPS.Log:Error("Fallback menu generator failed: %s", tostring(err)) end
        return nil
    end
    if #desc.elements == 0 then return nil end
    ensureFallbackWatcher()
    local pane = ensureRootPane()
    local width, height = renderPane(pane, desc.elements)
    placeRootAtCursor(pane.frame, owner, width, height)

    local trackedOwner = nil
    if type(owner) == "table" and owner ~= UIParent and owner ~= WorldMapFrame and owner ~= Minimap
        and type(owner.IsVisible) == "function" and owner:IsVisible() then
        trackedOwner = owner
    end

    desc.fgpsFallback = true
    desc.frame = pane.frame
    desc.buttons = pane.activeButtons
    desc.trackedOwner = trackedOwner
    desc.pollElapsed = 0
    function desc:IsShown()
        return pane.frame:IsShown()
    end
    function desc:IsVisible()
        return pane.frame:IsVisible()
    end
    function desc:Close()
        if activeFallback == self then Menus.CloseFallbackMenu() end
    end
    function desc:Button(label)
        for _, btn in ipairs(pane.activeButtons) do
            if btn.fgpsElement and btn.fgpsElement.text == label then return btn end
        end
        if subPane and subPane.frame and subPane.frame:IsShown() then
            for _, btn in ipairs(subPane.activeButtons) do
                if btn.fgpsElement and btn.fgpsElement.text == label then return btn end
            end
        end
        return nil
    end
    function desc:Select(label)
        local btn = self:Button(label)
        if not btn then return false end
        local onClick = btn.GetScript and btn:GetScript("OnClick")
        if type(onClick) == "function" then onClick(btn, "LeftButton") end
        return true
    end

    activeFallback = desc
    Menus.fallbackMenu = desc
    pane.frame:Show()
    syncFallbackKeyboard(pane.frame, true)
    return desc
end

local function safeIndex(tbl, key)
    return tbl[key]
end

local function safeCallMethod(tbl, method)
    if type(tbl) ~= "table" then return end
    local okIndex, fn = pcall(safeIndex, tbl, method)
    if okIndex and type(fn) == "function" then
        pcall(fn, tbl)
    end
end

local function resolveMenuFrame(menu)
    if type(menu) ~= "table" then return menu end
    local okToProxy, toProxy = pcall(safeIndex, menu, "ToProxy")
    if not okToProxy then return nil end
    if type(toProxy) == "function" then
        local ok, proxy = pcall(toProxy, menu)
        if ok and type(proxy) == "table" then return proxy end
        local okP, p = pcall(safeIndex, menu, "proxy")
        if okP and type(p) == "table" then return p end
        return nil
    end
    local okProxy, proxy = pcall(safeIndex, menu, "proxy")
    if not okProxy then return nil end
    if type(proxy) == "table" then return proxy end
    return menu
end

local function closeHalfOpenedBlizzardMenu(menu)
    if type(menu) ~= "table" then return end
    safeCallMethod(menu, "Close")
    safeCallMethod(menu, "Hide")
    local okFrame, frame = pcall(resolveMenuFrame, menu)
    if okFrame and type(frame) == "table" and frame ~= menu then
        safeCallMethod(frame, "Close")
        safeCallMethod(frame, "Hide")
    end
end

local function blizzardMenuHealthy(menu)
    if menu == nil then return false end
    if type(menu) ~= "table" then return true end
    local okFrame, frame = pcall(resolveMenuFrame, menu)
    if not okFrame or frame == nil or type(frame) ~= "table" then return false end

    local okShownFn, isShownFn = pcall(safeIndex, frame, "IsShown")
    if not okShownFn then return false end
    if type(isShownFn) == "function" then
        local okShown, shown = pcall(isShownFn, frame)
        if not okShown or not shown then return false end
    end

    local okVisFn, isVisFn = pcall(safeIndex, frame, "IsVisible")
    if not okVisFn then return false end
    if type(isVisFn) == "function" and UIParent and type(UIParent.IsVisible) == "function" and UIParent:IsVisible() then
        local okVis, vis = pcall(isVisFn, frame)
        if not okVis or not vis then return false end
    end

    local okWFn, getWFn = pcall(safeIndex, frame, "GetWidth")
    local okHFn, getHFn = pcall(safeIndex, frame, "GetHeight")
    if not okWFn or not okHFn then return false end
    if type(getWFn) == "function" or type(getHFn) == "function" then
        if type(getWFn) ~= "function" or type(getHFn) ~= "function" then
            return false
        end
        local okW, w = pcall(getWFn, frame)
        local okH, h = pcall(getHFn, frame)
        if not okW or not okH or type(w) ~= "number" or type(h) ~= "number" then
            return false
        end
        if w ~= w or h ~= h or w <= 1 or h <= 1 then
            return false
        end
    end
    return true
end





function Menus.OpenContextMenu(owner, generator, opts)
    if type(generator) ~= "function" then return nil end
    opts = opts or {}
    Menus.CloseFallbackMenu()
    if GameTooltip and owner and GameTooltip.IsOwned and GameTooltip:IsOwned(owner) then
        GameTooltip:Hide()
    end
    local Look = FGPS.UI.Look
    if Look and Look.ShimMenuVariants then Look.ShimMenuVariants() end
    local hasMenuUtil = Look and Look.TomeHas and Look.TomeHas("global", "MenuUtil")
        and type(MenuUtil) == "table" and type(MenuUtil.CreateContextMenu) == "function"
    if not hasMenuUtil then
        if opts.noteKey and Look and Look.NoteOnce then
            Look.NoteOnce(opts.noteKey, "%s", opts.noteMessage or "No MenuUtil; using Cabbie popup menu")
        end
        return openFallbackPopup(owner, generator)
    end
    local safeOwner = Look and Look.MenuOwner and Look.MenuOwner(owner) or owner
    local ok, menu = pcall(MenuUtil.CreateContextMenu, safeOwner, generator)
    local okHealth, healthy = false, false
    if ok then
        okHealth, healthy = pcall(blizzardMenuHealthy, menu)
    end
    if ok and okHealth and healthy then
        return menu
    end
    if not ok then
        local errField = opts.errorFlag or "contextMenuFailed"
        if not Menus[errField] then
            Menus[errField] = true
            if FGPS.Log then
                FGPS.Log:Error("%s: %s", opts.errorLabel or "A context menu failed to open", tostring(menu))
            end
        end
    else
        pcall(closeHalfOpenedBlizzardMenu, menu)
    end
    return openFallbackPopup(owner, generator)
end


function Menus.OpenRouteMenu(owner)
    return Menus.OpenContextMenu(owner, Menus.RouteMenu, {
        noteKey = "route:menu",
        noteMessage = "Route menu: no MenuUtil in this client; using Cabbie popup menu",
        errorFlag = "routeMenuFailed",
        errorLabel = "The Route menu failed to open",
    })
end






local function entryDisabled(entry)
    local disabled = entry.disabled
    if type(disabled) == "function" then
        local ok, yes = pcall(disabled)
        return not ok or yes and true or false
    end
    return disabled and true or false
end












local function rowMenuGenerator(spec)
    return function(_, root)
        if type(root) ~= "table" or type(root.CreateButton) ~= "function" then return end
        if type(spec.title) == "string" and spec.title ~= "" and type(root.CreateTitle) == "function" then
            root:CreateTitle(spec.title)
        end
        local plain, ending = {}, {}
        for _, entry in ipairs(type(spec.entries) == "table" and spec.entries or {}) do
            if type(entry) == "table" and type(entry.label) == "string" then
                local into = entry.destructive and ending or plain
                into[#into + 1] = entry
            end
        end
        local add
        add = function(node, create, entry)
            if type(entry.entries) == "table" then
                local sub = create(node, entry.label)
                local into = (type(sub) == "table" and type(sub.CreateButton) == "function") and sub or node
                for _, child in ipairs(entry.entries) do
                    if type(child) == "table" and type(child.label) == "string" then add(into, into.CreateButton, child) end
                end
                return
            end
            local element = create(node, entry.label, function()
                if entryDisabled(entry) or type(entry.onClick) ~= "function" then return end
                local ok, err = pcall(entry.onClick)
                if not ok and FGPS.Log then FGPS.Log:Error("Row menu entry %s failed: %s", entry.label, tostring(err)) end
            end)
            if type(element) ~= "table" or type(element.SetEnabled) == "function" then
                if type(element) == "table" then
                    if type(entry.disabled) == "function" then
                        element:SetEnabled(function() return not entryDisabled(entry) end)
                    elseif entry.disabled then
                        element:SetEnabled(false)
                    end
                end
            end
        end
        for _, entry in ipairs(plain) do add(root, root.CreateButton, entry) end
        if #ending == 0 then return end
        if type(root.CreateDivider) == "function" then root:CreateDivider() end
        local red = type(root.CreateRedHighlightButton) == "function" and root.CreateRedHighlightButton or root.CreateButton
        for _, entry in ipairs(ending) do add(root, red, entry) end
    end
end




function Menus.OpenRowMenu(owner, spec)
    if type(spec) ~= "table" then return nil end
    return Menus.OpenContextMenu(owner, rowMenuGenerator(spec), {
        noteKey = "tome:rowmenu",
        noteMessage = "Tome: no MenuUtil in this client; using Cabbie popup menu",
        errorFlag = "rowMenuFailed",
        errorLabel = "A row's menu failed to open",
    })
end







function Menus.RouteTooltip(onLine)
    local Navigator = FGPS.Navigator
    if onLine and routeStopped() then
        return { title = L["Route"], hint = L["Click to bring the route back"] }
    end
    local tip = { title = L["Route"], hint = L["Click for options. Drag to move."] }
    if Navigator and Navigator.GetState and Navigator:GetState() == "paused" and Navigator.pauseReason ~= nil then
        tip.line = L["Press Resume to try again."]
    end
    return tip
end



local function showRouteTooltip(button)
    local Look = FGPS.UI.Look
    if not (Look and Look.Tooltip) then return end
    local RouteBlock = FGPS.UI.RouteBlock
    local frame = RouteBlock and RouteBlock.frame or nil
    local tip = Menus.RouteTooltip(frame ~= nil and button == frame.Body)
    Look.Tooltip(button, tip.title, tip.line, tip.hint, "ANCHOR_LEFT")
end

local function hideRouteTooltip(button)
    if GameTooltip and (not GameTooltip.IsOwned or GameTooltip:IsOwned(button)) then GameTooltip:Hide() end
end









function Menus.OnHeaderClick(owner, button)
    local RouteBlock = FGPS.UI.RouteBlock
    if button == "LeftButton" then
        if RouteBlock and RouteBlock.dragged then
            RouteBlock.dragged = false
            return nil
        end
    elseif button ~= "RightButton" then
        return nil
    end
    hideRouteTooltip(owner)
    return Menus.OpenRouteMenu(owner)
end










function Menus.OnLineClick(owner, button)
    if button == "RightButton" then
        hideRouteTooltip(owner)
        return Menus.OpenRouteMenu(owner)
    end
    if button ~= "LeftButton" or not routeStopped() then return nil end
    if Menus.stoppedAt and now() - Menus.stoppedAt < Menus.UNDO_CLICK_DELAY then return nil end
    hideRouteTooltip(owner)
    Menus.BringBack()
    return nil
end







Menus.TRACKING_TAG = "MENU_MINIMAP_TRACKING"
Menus.NEAREST_HOLD = 4



Menus.NEAREST = {
    { "inn", "Inn", "Inn" }, { "bank", "Bank", "Bank" }, { "flightmaster", "Flight Master", "Flight master" },
    { "repair", "Repair", "Repair vendor" }, { "mailbox", "Mailbox", "Mailbox" }, { "vendor", "Vendor", "Vendor" },
    { "trainer", "Class Trainer", "Class trainer" }, { "stable", "Stable Master", "Stable master" },
    { "dummy", "Training Dummy", "Training dummy" },
}




local NAVIGATOR_ENDS = { resurrected = true }





function Menus.GoToNearest(service, word)
    local Services, Go, Guide = FGPS.ServiceSearch, FGPS.UI.Go, FGPS.UI.Guide
    if not (Services and Services.Nearest and Go and Go.Start) then return false end
    local asked = service
    if service == "trainer" then

        local class = Services.PlayerClass and Services.PlayerClass() or nil
        if class then asked = "trainer:" .. class end
    end
    if Guide and Guide.Say then
        local noun = type(word) == "string" and word or service
        for _, row in ipairs(Menus.NEAREST) do
            if row[1] == service then noun = L[row[3]] break end
        end
        Guide.Say(format(L["Finding the nearest %s"], FGPS.Util.Lower(noun)), Menus.NEAREST_HOLD)
    end




    local Nav = FGPS.Navigator


    local pick = { previewed = Nav and Nav.GetState and Nav:GetState() == "previewing" and Nav:GetRoute() or nil }
    Menus.nearestPick = pick
    return Services.Nearest(asked, { limit = 1 }, function(list)
        if Menus.nearestPick ~= pick then return end
        Menus.nearestPick = nil
        local best = type(list) == "table" and list[1] or nil
        if best and type(best.dest) == "table" then
            Go.Start(best.dest)
        elseif Guide and Guide.Say then
            Guide.Say(L["None found near here"], Menus.NEAREST_HOLD)
        end
    end) == true
end


function Menus.OnTrackingMenu(owner, root)
    if type(root) ~= "table" or type(root.CreateButton) ~= "function" then return end
    if type(root.CreateDivider) == "function" then root:CreateDivider() end
    local nearest = root:CreateButton(L["Go to Nearest"])
    if type(nearest) ~= "table" or type(nearest.CreateButton) ~= "function" then return end
    for _, service in ipairs(Menus.NEAREST) do
        nearest:CreateButton(L[service[2]], function() Menus.GoToNearest(service[1], L[service[2]]) end)
    end

    local Look = FGPS.UI.Look
    if Look and Look.NoteOnce then Look.NoteOnce("tracking", "Tracking menu: entry added") end
end




function Menus:Init()
    if self.bound then return end
    self.bound = true
    if type(Menu) == "table" and type(Menu.ModifyMenu) == "function" then
        Menu.ModifyMenu(Menus.TRACKING_TAG, Menus.OnTrackingMenu)
    end



    FGPS.Events:Register("DESTINATION_SET", function(_, _, askedBy)
        if askedBy ~= "navigator" then Menus.nearestPick = nil end
    end, self)
    FGPS.Events:Register("NAV_CANCELLED", function(_, reason)
        if not NAVIGATOR_ENDS[reason] then Menus.nearestPick = nil end
    end, self)


    FGPS.Events:Register("NAV_STATE", function(_, new, old)
        local pick = Menus.nearestPick
        if pick and pick.previewed and new == "active" and old == "previewing"
            and FGPS.Navigator:GetRoute() == pick.previewed then
            Menus.nearestPick = nil
        end
    end, self)
    FGPS.Events:Register("MAP_SHOWN", function()
        if not Menus.awaitingMapShownTaint then return end
        Menus.awaitingMapShownTaint = nil
        if not (FGPS.IsOwnerInstall and FGPS.IsOwnerInstall()) then return end
        if type(Menus.showOnMapTaint) == "table" then
            Menus.showOnMapTaint.atNextMapShown = readMapIdTaint()
        end
    end, self)
    local RouteBlock = FGPS.UI.RouteBlock
    local frame = RouteBlock and RouteBlock.frame or nil





    local function bind(button, onClick)
        if not (button and button.RegisterForClicks) then return end
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:SetScript("OnClick", onClick)
        button:SetScript("OnEnter", showRouteTooltip)
        button:SetScript("OnLeave", hideRouteTooltip)
    end
    bind(frame and frame.Header, function(clicked, mouseButton) Menus.OnHeaderClick(clicked, mouseButton) end)
    bind(frame and frame.Body, function(clicked, mouseButton) Menus.OnLineClick(clicked, mouseButton) end)
end
