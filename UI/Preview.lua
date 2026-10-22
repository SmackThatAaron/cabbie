


































local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local type, ipairs, pairs, tostring, tonumber, format = type, ipairs, pairs, tostring, tonumber, string.format
local abs, min = math.abs, math.min

local Preview = {
    window = nil,
    list = nil,
    route = nil,
    alternatives = nil,
    error = nil,
    calculating = false,
    listMode = "steps",
    pendingDest = nil,
}
FGPS.UI.Preview = Preview

local WINDOW_KEY = "preview"
local ROW_HEIGHT = 18
local MAX_STEPS = 8


local TRANSPORT_LABELS = { taxi = "Flight", boat = "Boat", zeppelin = "Zeppelin", tram = "Tram", elevator = "Elevator",
                           portal = "Portal", hearth = "Hearthstone", spell = "Teleport" }
local TRANSPORT_ICONS = {
    taxi = { atlases = { "FlightPath", "TaxiNode_Neutral", "UI-Taxi-Icon-Nub" }, file = "Interface\\Icons\\Ability_Mount_Gryphon_01" },
    portal = { atlases = { "TaxiNode_Continent_Neutral" }, file = "Interface\\Icons\\Spell_Arcane_PortalStormwind" },
    spell = { atlases = { "TaxiNode_Continent_Neutral" }, spellID = 3561, file = "Interface\\Icons\\Spell_Arcane_TeleportStormwind" },
    hearth = { itemID = 6948, file = "Interface\\Icons\\INV_Misc_Rune_01" },
    boat = { atlases = { "FlightMaster_Ferry-Taxi_Frame_Gray" } },
}
local TRANSPORT_COLORS = { boat = { 0.3, 0.6, 1 }, zeppelin = { 0.9, 0.5, 0.2 }, tram = { 0.7, 0.7, 0.7 }, elevator = { 0.6, 0.9, 0.6 },
                           taxi = { 1, 0.85, 0.3 }, portal = { 0.6, 0.4, 1 }, spell = { 0.5, 0.7, 1 }, hearth = { 0.4, 0.9, 0.5 } }
local DEFAULT_MARKER_COLOR = { 0.8, 0.8, 0.8 }
local MARKER_TEXTURE = "Interface\\Buttons\\WHITE8X8"




local iconCache = {}

local function markerSpec(kind)
    return { color = TRANSPORT_COLORS[kind] or DEFAULT_MARKER_COLOR }
end

local function atlasExists(name)
    if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    return ok and info ~= nil
end




function Preview.ResolveTransportIcon(kind)
    local cached = iconCache[kind]
    if cached then return cached end
    local spec = TRANSPORT_ICONS[kind] or {}
    local resolved
    if spec.atlases then
        for _, name in ipairs(spec.atlases) do
            if atlasExists(name) then
                resolved = { atlas = name }
                break
            end
        end
    end
    if not resolved and spec.itemID and C_Item and C_Item.GetItemIconByID then
        local ok, icon = pcall(C_Item.GetItemIconByID, spec.itemID)
        if ok and icon then resolved = { file = icon } end
    end
    if not resolved and spec.spellID and C_Spell and C_Spell.GetSpellTexture then
        local ok, icon = pcall(C_Spell.GetSpellTexture, spec.spellID)
        if ok and icon then resolved = { file = icon } end
    end
    if not resolved and spec.file then resolved = { file = spec.file, probe = true } end
    if not resolved then resolved = markerSpec(kind) end
    iconCache[kind] = resolved
    return resolved
end


function Preview.ResetIconCache()
    wipe(iconCache)
end

local function applyMarker(icon, kind)
    local c = (TRANSPORT_COLORS[kind] or DEFAULT_MARKER_COLOR)
    if icon.SetTexCoord then icon:SetTexCoord(0, 1, 0, 1) end
    icon:SetTexture(MARKER_TEXTURE)
    icon:SetVertexColor(c[1], c[2], c[3], 0.9)
end

local function applyTransportIcon(icon, kind)
    local spec = Preview.ResolveTransportIcon(kind)
    if spec.atlas then
        local ok = pcall(icon.SetAtlas, icon, spec.atlas)
        if ok then
            icon:SetVertexColor(1, 1, 1, 1)
            return
        end
        iconCache[kind] = markerSpec(kind)
    elseif spec.file then
        if icon.SetTexCoord then icon:SetTexCoord(0, 1, 0, 1) end
        local ok, success = pcall(icon.SetTexture, icon, spec.file)


        if ok and success ~= false then
            icon:SetVertexColor(1, 1, 1, 1)
            return
        end
        FGPS:Debug("Transport icon %s for %s is not available in this client; using the marker", tostring(spec.file), kind)
        iconCache[kind] = markerSpec(kind)
    end
    applyMarker(icon, kind)
end
Preview.ApplyTransportIcon = applyTransportIcon
local VARIANT_LABELS = { fastest = "Fastest", fewer_transfers = "Fewer transfers", prefer_roads = "Prefer roads",
                         no_flight = "No flights", no_boat = "No boats" }




local function Frames() return FGPS.UI.Frames end
local function settings() return FGPS.DB and FGPS.DB.settings or nil end

local FALLBACK_FONTS = { small = "GameFontHighlightSmall", normal = "GameFontHighlight", large = "GameFontNormalLarge", title = "GameFontNormalLarge" }

local function applyLabelColor(fs, key)
    local skin = FGPS.UI and FGPS.UI.Skins and FGPS.UI.Skins.Current and FGPS.UI.Skins.Current()
    local c = skin and skin.colors and skin.colors[key]
    if c then
        fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    elseif key == "textDim" then
        fs:SetTextColor(0.6, 0.6, 0.6)
    elseif key == "title" then
        fs:SetTextColor(1, 0.82, 0)
    end
end

local function makeLabel(parent, kind, text, color)
    local F = Frames()
    if F and F.CreateLabel then
        local ok, fs = pcall(F.CreateLabel, parent, text, { kind = kind, color = color })
        if ok and fs then return fs end
    end
    local fs = parent:CreateFontString(nil, "OVERLAY", FALLBACK_FONTS[kind] or "GameFontHighlightSmall")
    fs:SetText(text or "")
    fs:SetJustifyH("LEFT")
    applyLabelColor(fs, color or "text")
    return fs
end

local function makeButton(parent, text, onClick, width, height)
    local F = Frames()
    local button
    if F and F.CreateButton then
        local ok, result = pcall(F.CreateButton, parent, text, onClick, { width = width or 90, height = height or 22 })
        if ok and type(result) == "table" then button = result end
    end
    if not button then
        button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        button:SetText(text)
        button:SetScript("OnClick", onClick)
        button:SetSize(width or 90, height or 22)
    end
    return button
end

local function setButtonText(button, text)
    if button.SetLabel then button:SetLabel(text) else button:SetText(text) end
end

local function setButtonEnabled(button, enabled)
    if button.SetEnabledState then button:SetEnabledState(enabled) elseif enabled then button:Enable() else button:Disable() end
end

local function makeList(parent, rowHeight, renderFn, onClick)
    local F = Frames()
    if F and F.CreateScrollList then
        local ok, list = pcall(F.CreateScrollList, parent, rowHeight, renderFn, { onClick = onClick })
        if ok and type(list) == "table" then return list end
        FGPS.Log:Error("Frames.CreateScrollList failed: %s", tostring(list))
    end
    return nil
end

local function setListItems(list, items)
    if not list then return end
    if list.SetItems then list:SetItems(items)
    elseif list.SetData then list:SetData(items)
    elseif list.Update then list:Update(items) end
end

local function contentFrame(window)
    local content = window.Content or window.content or window
    return content, (content == window) and 30 or 0
end




local function routeTransports(route)
    local Route = FGPS.Route
    local kinds, seen = {}, {}
    if type(route.legs) == "table" then
        for _, leg in ipairs(route.legs) do
            local kind = leg.kind
            if kind and TRANSPORT_LABELS[kind] and not seen[kind] then
                seen[kind] = true
                kinds[#kinds + 1] = kind
            end
        end
    end
    if #kinds == 0 and Route and Route.Summary then
        local ok, summary = pcall(Route.Summary, route)
        if ok and type(summary) == "table" and type(summary.transports) == "table" then
            for _, name in ipairs(summary.transports) do kinds[#kinds + 1] = name end
        end
    end
    return kinds
end

local function destinationName(route)
    local stops = route.stops
    if type(stops) == "table" and #stops > 0 then
        local last = stops[#stops]
        local dest = last.dest or last
        if type(dest) == "table" and dest.name then
            if #stops > 1 then return format(L["%s (%d stops)"], dest.name, #stops) end
            return dest.name
        end
    end
    local legs = route.legs
    local leg = type(legs) == "table" and legs[#legs]
    return leg and leg.label or L["Destination"]
end


local function leastGuessedYards()
    local I = FGPS.Instructions
    return I and I.MIN_UNVERIFIED_YARDS or 20
end




local function hearthNote(route)
    local s = settings()
    if s and s.transports and s.transports.hearth == false then return nil end
    for _, leg in ipairs(type(route.legs) == "table" and route.legs or {}) do
        if leg.kind == "hearth" then return nil end
    end
    local Personal = FGPS.Personal
    if not (Personal and Personal.HearthNote) then return nil end
    local ok, note = pcall(Personal.HearthNote)
    return ok and type(note) == "string" and note or nil
end



function Preview.Summarize(route)
    local s = settings()
    local units = s and s.units or "yards"
    local summary = {
        title = destinationName(route),
        eta = "",
        distance = Util.FormatDistance(route.totalYards, units),
        transfers = tonumber(route.transfers) or 0,
        transports = routeTransports(route),
        unverifiedYards = tonumber(route.unverifiedYards) or 0,
        fallback = route.fallback,
    }

    if summary.unverifiedYards >= leastGuessedYards() then


        local sentence
        if (tonumber(route.meshYards) or 0) > 0 then
            sentence = L["%s of this route is a guessed way over open ground (drawn dashed on the maps); expect obstacles."]
        else
            sentence = L["%s of this route is open ground (drawn dashed on the maps); expect obstacles."]
        end
        summary.unverifiedText = format(sentence, Util.FormatDistance(summary.unverifiedYards, units))
    end
    local Cost = FGPS.Cost
    if Cost and Cost.Explain then
        local ok, text = pcall(Cost.Explain, route)
        if ok and type(text) == "string" then summary.explain = text end
    end
    summary.explain = summary.explain or route.explain
    summary.hearthNote = hearthNote(route)
    return summary
end


function Preview.DescribeAlternative(alt, reference)
    local parts = {}
    local units = settings() and settings().units or "yards"
    local delta = (tonumber(alt.totalYards) or 0) - (tonumber(reference and reference.totalYards) or 0)
    if reference then
        if abs(delta) < 1 then
            parts[#parts + 1] = L["same distance"]
        elseif delta > 0 then
            parts[#parts + 1] = "+" .. Util.FormatDistance(delta, units)
        else
            parts[#parts + 1] = "-" .. Util.FormatDistance(-delta, units)
        end
    else
        parts[#parts + 1] = Util.FormatDistance(alt.totalYards, units)
    end
    local transfers = tonumber(alt.transfers) or 0
    parts[#parts + 1] = format(transfers == 1 and L["%d transfer"] or L["%d transfers"], transfers)
    if alt.variant == "prefer_roads" then parts[#parts + 1] = L["prefer roads"] end
    if alt.variant == "no_flight" then parts[#parts + 1] = L["no flights"] end
    if alt.variant == "no_boat" then parts[#parts + 1] = L["no boats"] end
    if (tonumber(alt.unverifiedYards) or 0) >= leastGuessedYards() then
        parts[#parts + 1] = format(L["%s open ground"], Util.FormatDistance(alt.unverifiedYards, settings() and settings().units or "yards"))
    end
    return table.concat(parts, ", ")
end




local function ensureRowWidgets(row)
    if row.fgpsReady then return end
    row.fgpsReady = true
    row.left = makeLabel(row, "small", "", "textDim")
    row.left:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.left:SetWidth(56)
    row.text = row.Text or makeLabel(row, "small", "", "text")
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row.left, "RIGHT", 4, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -6, 0)
end

function Preview.RenderRow(row, item, index)
    ensureRowWidgets(row)
    row.item = item
    row.left:SetText(item.left or "")
    row.text:SetText(item.text or "")
    applyLabelColor(row.left, "textDim")
    if item.kind == "alternative" then

        applyLabelColor(row.text, item.selected and "accent" or "text")
    elseif item.unverified then



        applyLabelColor(row.text, "routeUnverified")
    else
        applyLabelColor(row.text, "text")
    end
end

local function onRowClick(item)
    if type(item) == "table" and item.kind == "alternative" then Preview:ChooseAlternative(item.alt) end
end

local function stepItems(route)
    local items = {}
    local steps = type(route.steps) == "table" and route.steps or {}
    local s = settings()
    local units = s and s.units or "yards"
    local least = leastGuessedYards()
    for i = 1, min(#steps, MAX_STEPS) do
        local step = steps[i]




        local leg = route.legs and step.legIndex and route.legs[step.legIndex]
        local unverified = (type(step.guessedYards) == "number" and step.guessedYards >= least)
            or (type(leg) == "table" and leg.kind ~= "walk" and leg.unverified == true)
        local text = step.text or step.shortText or step.kind or ""


        if unverified then text = text .. "  " .. L["(open ground)"] end
        items[#items + 1] = {
            kind = "step",
            left = step.distanceFromStart and Util.FormatDistance(step.distanceFromStart, units) or "",
            text = text,
            unverified = unverified,
        }
    end
    if #steps > MAX_STEPS then
        items[#items + 1] = { kind = "more", left = "", text = format(L["... and %d more steps"], #steps - MAX_STEPS) }
    end
    if #items == 0 then items[1] = { kind = "more", left = "", text = L["No turn-by-turn steps are available for this route."] } end
    return items
end

local function alternativeItems(alternatives, current)
    local items = {}
    for _, alt in ipairs(alternatives or {}) do
        items[#items + 1] = {
            kind = "alternative", alt = alt,
            left = L[VARIANT_LABELS[alt.variant] or tostring(alt.variant)],
            text = Preview.DescribeAlternative(alt, current),
            selected = current ~= nil and (alt == current or (alt.id ~= nil and alt.id == current.id)),
        }
        if items[#items].selected then
            items[#items].text = items[#items].text .. " (" .. (L["selected"] or "selected") .. ")"
        end
    end
    if #items == 0 then items[1] = { kind = "more", left = "", text = L["No distinct alternatives were found."] } end
    return items
end




local function setStatus(window, text, r, g, b)
    window.fgpsStatus:SetText(text or "")
    window.fgpsStatus:SetTextColor(r or 1, g or 0.82, b or 0)
end

local function renderTransports(window, kinds)
    local row = window.fgpsTransports
    for _, icon in ipairs(row.icons) do icon:Hide() end
    row.text:ClearAllPoints()
    if #kinds == 0 then
        row.text:SetText(L["On foot or mounted only"])
        row.text:SetPoint("LEFT", row, "LEFT", 0, 0)
        return
    end
    local names, previous = {}, nil
    for i, kind in ipairs(kinds) do
        local icon = row.icons[i]
        if not icon then
            icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(16, 16)
            row.icons[i] = icon
        end
        icon:ClearAllPoints()
        if previous then icon:SetPoint("LEFT", previous, "RIGHT", 2, 0) else icon:SetPoint("LEFT", row, "LEFT", 0, 0) end
        applyTransportIcon(icon, kind)
        icon:Show()
        previous = icon
        names[#names + 1] = L[TRANSPORT_LABELS[kind] or kind]
    end
    row.text:SetPoint("LEFT", previous, "RIGHT", 6, 0)
    row.text:SetText(table.concat(names, ", "))
end


local function labelAlternativesButton(window, listMode)
    setButtonText(window.fgpsButtons.alternatives, listMode == "alternatives" and L["Steps"] or L["Alternatives"])
end

local function setButtons(window, enabled)
    setButtonEnabled(window.fgpsButtons.start, enabled)
    setButtonEnabled(window.fgpsButtons.alternatives, enabled)
    setButtonEnabled(window.fgpsButtons.addStop, enabled)
end

local function clearSummary(window)
    window.fgpsEta:SetText("")
    window.fgpsDistance:SetText("")
    window.fgpsTransfers:SetText("")
    for _, icon in ipairs(window.fgpsTransports.icons) do icon:Hide() end
    window.fgpsTransports.text:SetText("")
    window.fgpsWarning:SetText("")
    window.fgpsWarning:Hide()
    window.fgpsExplain:SetText("")
    window.fgpsListTitle:SetText("")
end

function Preview:RenderRoute()
    local window = self.window
    local route = self.route
    if not window or not route then return end
    local summary = Preview.Summarize(route)
    window.fgpsTitle:SetText(summary.title)
    window.fgpsEta:SetText("")
    window.fgpsDistance:SetText(format(L["Distance %s"], summary.distance))
    window.fgpsTransfers:SetText(format(summary.transfers == 1 and L["%d transfer"] or L["%d transfers"], summary.transfers))
    renderTransports(window, summary.transports)
    if summary.unverifiedText then
        window.fgpsWarning:SetText(summary.unverifiedText)
        window.fgpsWarning:Show()


        window.fgpsExplain:SetText(summary.hearthNote or "")
        if summary.hearthNote then window.fgpsExplain:Show() else window.fgpsExplain:Hide() end
    else
        window.fgpsWarning:SetText("")
        window.fgpsWarning:Hide()
        local explain = summary.explain or ""
        if summary.hearthNote then explain = explain == "" and summary.hearthNote or (explain .. " " .. summary.hearthNote) end
        window.fgpsExplain:SetText(explain)
        window.fgpsExplain:Show()
    end
    if summary.fallback == "straight" then
        setStatus(window, L["No road was found; this route is drawn dashed."], 1, 0.65, 0.2)
    elseif self.calculating then
        setStatus(window, L.ROUTE_CALCULATING)
    else
        setStatus(window, "")
    end
    setButtons(window, true)
    window.fgpsFallback:Hide()
    labelAlternativesButton(window, self.listMode)
    if self.listMode == "alternatives" then
        window.fgpsListTitle:SetText(L["Alternatives"])
        setListItems(self.list, alternativeItems(self.alternatives, route))
    else
        window.fgpsListTitle:SetText(L["Steps"])
        setListItems(self.list, stepItems(route))
    end
end

local function errorMessage(err)
    if type(err) ~= "table" then return L.ROUTE_NO_PATH end
    local code = err.code
    local base
    if code == "NO_PATH" then base = L.ROUTE_NO_PATH
    elseif code == "NO_ORIGIN" then base = L.ROUTE_NO_ORIGIN
    elseif code == "UNREACHABLE" then base = L.ROUTE_UNREACHABLE
    elseif code == "NO_DATA" then base = L.ROUTE_NO_DATA
    elseif code == "CANCELLED" then base = L.ROUTE_CANCELLED
    else base = L.ROUTE_NO_PATH end
    if type(err.message) == "string" and err.message ~= "" and err.message ~= base then
        return base .. " " .. err.message
    end
    return base
end
Preview.ErrorMessage = errorMessage


function Preview.CanOfferFallback(err)
    if type(err) ~= "table" then return false end
    if type(err.fallback) == "table" then return true end
    local s = settings()
    return err.code == "NO_PATH" and s ~= nil and s.routing ~= nil and s.routing.allowUnverified == false
end

function Preview:RenderError()
    local window = self.window
    local err = self.error
    if not window then return end
    local dest = self.pendingDest
    window.fgpsTitle:SetText(dest and dest.name or L["Route"])
    clearSummary(window)
    setStatus(window, errorMessage(err), 1, 0.3, 0.3)
    setButtons(window, false)
    setListItems(self.list, {})
    if Preview.CanOfferFallback(err) then window.fgpsFallback:Show() else window.fgpsFallback:Hide() end
end

function Preview:RenderCalculating()
    local window = self.window
    if not window then return end
    local dest = self.pendingDest
    if dest and dest.name then window.fgpsTitle:SetText(dest.name) elseif not self.route then window.fgpsTitle:SetText(L["Route"]) end
    setStatus(window, L.ROUTE_CALCULATING)
    if not self.route then
        clearSummary(window)
        setListItems(self.list, {})
        setButtons(window, false)
    end
    window.fgpsFallback:Hide()
end

function Preview:Render()
    if not self.window then return end


    labelAlternativesButton(self.window, self.listMode)
    if self.calculating and not self.route then
        self:RenderCalculating()
    elseif self.error and not self.route then
        self:RenderError()
    elseif self.route then
        self:RenderRoute()
    else
        self:RenderCalculating()
    end
end




function Preview:Start()
    local Navigator = FGPS.Navigator
    if not self.route or not Navigator or not Navigator.Start then return false end


    local Go = FGPS.UI.Go
    local waitOut = Go and Go.WaitOutTheRide
    if waitOut and waitOut() then
        self:Hide()
        return true
    end
    local held = Navigator.GetRoute and Navigator:GetRoute() or nil



    local following = Navigator.IsJourney and Navigator:IsJourney() and held == self.route
    if following then
        if Navigator.GetState and Navigator:GetState() == "paused" and Navigator.Resume then Navigator:Resume() end
    else




        local previewed = Navigator.GetState and Navigator:GetState() == "previewing" and held == self.route
        if previewed then
            Navigator:Start(self.route)
        else



            Navigator:Start()
            if waitOut then waitOut() end
        end
    end
    self:Hide()
    return true
end

function Preview:ToggleAlternatives()
    if self.listMode == "alternatives" then
        self.listMode = "steps"
        self:Render()
        return
    end
    local Navigator = FGPS.Navigator
    if not Navigator or not Navigator.RequestAlternatives then
        FGPS:Print(L["Alternatives are not available right now."])
        return
    end
    self.listMode = "alternatives"
    if self.alternatives then
        self:Render()
        return
    end
    if self.window then setStatus(self.window, L["Computing alternatives..."]) end
    local reference = self.route
    local ok, err = pcall(Navigator.RequestAlternatives, Navigator, function(list, requestErr)
        if Preview.route ~= reference then return end
        Preview.alternatives = type(list) == "table" and list or {}
        if requestErr and Preview.window then
            setStatus(Preview.window, errorMessage(requestErr), 1, 0.3, 0.3)
        end
        Preview:Render()
    end)
    if not ok then
        FGPS.Log:Error("RequestAlternatives failed: %s", tostring(err))
        self.listMode = "steps"
        self:Render()
    end
end

function Preview:ChooseAlternative(alt)
    local Navigator = FGPS.Navigator
    if type(alt) ~= "table" then return end

    local keepAlternatives = self.alternatives
    self.route = alt
    self.alternatives = keepAlternatives
    self.error = nil
    self.listMode = "steps"
    self:Render()
    if Navigator and Navigator.SelectAlternative and alt.variant then
        local ok, err = pcall(Navigator.SelectAlternative, Navigator, alt.variant)
        if not ok then FGPS.Log:Error("SelectAlternative failed: %s", tostring(err)) end
    end
end

function Preview:AddStop()
    local Search = FGPS.UI.Search
    if Search and Search.Show then Search:Show({ mode = "addStop" }) end
end






function Preview:Cancel()
    local Navigator = FGPS.Navigator
    if Navigator and Navigator.Clear then
        pcall(Navigator.Clear, Navigator, "user")
    elseif Navigator and Navigator.Cancel then
        pcall(Navigator.Cancel, Navigator, "user")
    end
    self.route, self.alternatives, self.error, self.pendingDest = nil, nil, nil, nil
    self.calculating = false
    self:Hide()
end

function Preview:UseFallback()
    local Navigator = FGPS.Navigator
    local err = self.error
    if type(err) == "table" and type(err.fallback) == "table" then
        if Navigator and Navigator.Start then
            self.error = nil
            Navigator:Start(err.fallback)
            self:Hide()
        end
        return
    end
    local DB = FGPS.DB
    if DB and DB:Get("routing.allowUnverified") == false then
        DB:Set("routing.allowUnverified", true)
        FGPS:Print(L["Routes may cross open ground; recalculating."])
        self.error = nil
        self.calculating = true
        self:Render()
        if not Navigator then return end
        if Navigator.IsJourney and Navigator:IsJourney() and Navigator.GetState and Navigator:GetState() == "paused"
            and Navigator.Resume then



            Navigator:Resume()
        elseif Navigator.Preview then
            Navigator:Preview()
        end
    end
end




local function buildWindow()
    local F = Frames()
    if not F or not F.CreateWindow then
        FGPS.Log:Error("UI.Frames.CreateWindow is unavailable; the preview window cannot be built")
        return nil
    end
    local ok, window = pcall(F.CreateWindow, WINDOW_KEY, { title = L["Route preview"], width = 400, height = 470 })
    if not ok or type(window) ~= "table" then
        FGPS.Log:Error("Frames.CreateWindow failed: %s", tostring(window))
        return nil
    end

    if window.Close and F.Tooltip then
        F.Tooltip(window.Close, { L["Keep planning"], L["Closes this window. Your stops stay set."] })
    end
    local content, top = contentFrame(window)
    local previous = nil
    local function placeBelow(region, xOfs, yOfs)
        region:ClearAllPoints()
        if previous then
            region:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", xOfs or 0, yOfs or -2)
        else
            region:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -(top + 2))
        end
        region:SetPoint("RIGHT", content, "RIGHT", -4, 0)
        previous = region
    end
    local function line(kind, color)
        local fs = makeLabel(content, kind, "", color)
        placeBelow(fs, 0, -2)
        return fs
    end
    window.fgpsTitle = line("title", "title")
    window.fgpsEta = line("normal", "text")
    window.fgpsDistance = line("normal", "text")
    window.fgpsTransfers = line("small", "text")
    local transports = CreateFrame("Frame", nil, content)
    transports:SetHeight(18)
    placeBelow(transports, 0, -4)
    transports.icons = {}
    transports.text = makeLabel(transports, "small", "", "text")
    transports.text:SetPoint("LEFT", transports, "LEFT", 0, 0)
    window.fgpsTransports = transports
    window.fgpsWarning = line("small", "text")
    window.fgpsWarning:SetTextColor(1, 0.65, 0.2)
    if window.fgpsWarning.SetWordWrap then window.fgpsWarning:SetWordWrap(true) end
    window.fgpsExplain = line("small", "textDim")
    if window.fgpsExplain.SetWordWrap then window.fgpsExplain:SetWordWrap(true) end
    window.fgpsStatus = line("normal", "title")
    window.fgpsListTitle = line("small", "title")

    local fallback = makeButton(content, L["Open ground"], function() Preview:UseFallback() end, 180, 22)
    placeBelow(fallback, 0, -4)
    fallback:Hide()
    window.fgpsFallback = fallback

    local listAnchor = CreateFrame("Frame", nil, content)
    listAnchor:ClearAllPoints()
    listAnchor:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", -2, -2)
    listAnchor:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -2, 30)
    local list = makeList(listAnchor, ROW_HEIGHT, Preview.RenderRow, onRowClick)
    if list and list.SetAllPoints then list:SetAllPoints(listAnchor) end
    Preview.list = list

    local specs = {
        { key = "start", label = "Start", fn = function() Preview:Start() end },
        { key = "alternatives", label = "Alternatives", fn = function() Preview:ToggleAlternatives() end },
        { key = "addStop", label = "Add stop", fn = function() Preview:AddStop() end },
        { key = "cancel", label = "Clear route", fn = function() Preview:Cancel() end },
    }
    window.fgpsButtons = {}
    local previous
    for _, spec in ipairs(specs) do
        local button = makeButton(content, L[spec.label], spec.fn, 92, 22)
        if previous then button:SetPoint("LEFT", previous, "RIGHT", 3, 0) else button:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 2, 2) end
        window.fgpsButtons[spec.key] = button
        previous = button
    end
    if F.ApplySkin then pcall(F.ApplySkin, window) end
    return window
end

function Preview:EnsureWindow()
    if self.window then return self.window end
    self.window = buildWindow()
    return self.window
end




function Preview:Show()
    local window = self:EnsureWindow()
    if not window then return false end
    window:Show()
    self:Render()
    return true
end

function Preview:Hide()

    self.listMode = "steps"
    if self.window and self.window:IsShown() then self.window:Hide() end
end

function Preview:IsShown()
    return self.window ~= nil and self.window:IsShown()
end


function Preview:Dismiss()
    self.pendingDest = nil
    self.calculating = false
    self.suppressMenu = false
    self.error = nil
    self.route = nil
    self.alternatives = nil
    self.listMode = "steps"
    self:Hide()
end


function Preview.ShouldOpenMenu()
    local Navigator = FGPS.Navigator
    if Navigator and Navigator.GetStops then
        local stops = Navigator:GetStops()
        if type(stops) == "table" and #stops > 1 then return true end
    end
    return false
end




function Preview:ShowCalculating(dest, opts)
    local force = type(opts) == "table" and opts.force == true
    if not force and not Preview.ShouldOpenMenu() then
        self.suppressMenu = true
        self.pendingDest = dest
        return false
    end
    self.suppressMenu = false
    self.pendingDest = dest
    self.calculating = true
    self.error = nil
    self.route = nil
    self.alternatives = nil
    self.listMode = "steps"
    return self:Show()
end







local function startSingleStop(route)
    local Navigator = FGPS.Navigator
    if type(route) ~= "table" or not Navigator or not Navigator.Start then return end
    if Navigator.IsJourney and Navigator:IsJourney() then return end
    Navigator:Start(route)
end




local function onRoutePreview(_, route, alternatives, err)
    if not route and type(err) == "table" and err.code == "CANCELLED" then return end


    local Navigator = FGPS.Navigator
    local unasked = not Preview:IsShown() and Preview.pendingDest == nil and not Preview.calculating
        and Navigator ~= nil and Navigator.askedBy == "navigator"
    Preview.calculating = false
    local suppress = Preview.suppressMenu == true and not Preview.ShouldOpenMenu()
    Preview.suppressMenu = false
    if not route then
        Preview.route = nil
        Preview.alternatives = nil
        Preview.error = err or { code = "NO_PATH" }
        if unasked then return end


        Preview:Show()
        return
    end
    Preview.route = route
    Preview.alternatives = type(alternatives) == "table" and alternatives or nil
    Preview.error = nil
    Preview.listMode = "steps"
    Preview.pendingDest = nil
    if unasked then return end
    if suppress then
        startSingleStop(route)
        return
    end
    Preview:Show()
end

local function onRecalcStart()
    if not Preview:IsShown() then return end
    Preview.calculating = true
    Preview:Render()
end





local function adoptRoute(route, reason)
    if type(route) ~= "table" or route == Preview.route then return end
    Preview.route = route
    if reason ~= "alternative" then
        Preview.alternatives = nil
        Preview.listMode = "steps"
    end
end







local function leadsElsewhere(route)
    local Navigator, Destinations = FGPS.Navigator, FGPS.Destinations
    local stops = Navigator and Navigator.GetStops and Navigator:GetStops() or nil
    local last = type(stops) == "table" and stops[#stops] or nil
    local ends = type(route) == "table" and type(route.stops) == "table" and route.stops[#route.stops] or nil
    local dest = type(ends) == "table" and ends.dest or nil
    if not (last and dest and Destinations and Destinations.Equal) then return false end
    return not Destinations.Equal(last, dest)
end

local function onRecalcDone(_, route, err)
    Preview.calculating = false
    if route then


        adoptRoute(route, "recalc")
        Preview.error = nil
        if Preview:IsShown() then Preview:Render() end
        return
    end
    Preview.error = err or { code = "NO_PATH" }
    if Preview:IsShown() or Preview.pendingDest then
        Preview.route = nil
        Preview.alternatives = nil
        Preview:Show()
    end
end

local function onRouteUpdated(_, route, reason)
    adoptRoute(route, reason)


    if route then Preview.pendingDest = nil end
    Preview.error = nil
    Preview.calculating = false
    if Preview:IsShown() then Preview:Render() end
end



local function onRouteStarted(_, route)
    if type(route) == "table" then
        adoptRoute(route, "start")
    else
        Preview.route, Preview.alternatives = nil, nil
    end
    Preview.pendingDest = nil
    Preview:Hide()
end





local function onNavState(_, state)
    if state ~= "idle" or not Preview.route then return end
    local Navigator = FGPS.Navigator
    if Navigator and Navigator.GetRoute and Navigator:GetRoute() ~= nil then return end
    Preview.route, Preview.alternatives = nil, nil
    Preview.listMode = "steps"
    if Preview:IsShown() then Preview:Render() end
end

local function onCancelled()
    Preview.route, Preview.alternatives, Preview.error, Preview.pendingDest = nil, nil, nil, nil
    Preview.calculating = false
    Preview.suppressMenu = false
    Preview:Hide()
end

function Preview:Init()
    if self.eventsBound then return end
    self.eventsBound = true
    local Events = FGPS.Events
    Events:Register("ROUTE_PREVIEW", onRoutePreview, self)
    Events:Register("NAV_RECALC_START", onRecalcStart, self)
    Events:Register("NAV_RECALC_DONE", onRecalcDone, self)
    Events:Register("ROUTE_UPDATED", onRouteUpdated, self)
    Events:Register("ROUTE_STARTED", onRouteStarted, self)
    Events:Register("NAV_STATE", onNavState, self)
    Events:Register("NAV_CANCELLED", onCancelled, self)
    Events:Register("NAV_ARRIVED", function(_, _, isFinal) if isFinal ~= false then onCancelled() end end, self)






    Events:Register("ITINERARY_CHANGED", function(_, stops)
        if type(stops) == "table" and #stops == 0 then onCancelled() end
    end, self)
    Events:Register("SETTINGS_CHANGED", function(_, key)
        if (key == "units" or key == "*") and Preview:IsShown() then Preview:Render() end
    end, self)
    FGPS.Slash.Register("preview", function()
        local Navigator = FGPS.Navigator



        local current = Navigator and Navigator.GetRoute and Navigator:GetRoute() or nil
        if type(current) == "table" and not leadsElsewhere(current) then
            adoptRoute(current)
            Preview.error = nil
            Preview.calculating = false
        end

        if Preview.route and leadsElsewhere(Preview.route) then
            Preview.route, Preview.alternatives = nil, nil
            Preview.listMode = "steps"
        end
        if Preview.route then Preview:Show() return end
        if Navigator and Navigator.Preview and Navigator.GetStops and #(Navigator:GetStops() or {}) > 0 then

            Preview:ShowCalculating(nil, { force = true })




            local rerouting = Navigator.IsJourney and Navigator:IsJourney() and Navigator.inflight ~= nil
            if not rerouting then Navigator:Preview() end
        else
            FGPS:Print(L["No destination is set. Use /cabbie go or the search window first."])
        end
    end, L["Show the route preview for the current destination"])
end
