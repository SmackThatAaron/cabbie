





















local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local floor, type, ipairs, pairs, tostring, format = math.floor, type, ipairs, pairs, tostring, string.format

local QuestMap = {
    provider = nil,
    overlay = nil,
    pinLayer = nil,
    pinPool = nil,
    areaPool = nil,
    pins = nil,
    minimapPool = nil,
    minimapActive = false,
    focus = nil,
    attached = false,
    lastDrawMapID = nil,
    lastPinCount = 0,
    lastAreaCount = 0,
    lastMinimapCount = 0,
}
FGPS.UI.QuestMap = QuestMap

local REF = "CabbieQuests"
local PIN_SIZE = 14
local PIN_SIZE_UNVERIFIED = 18
local MINIMAP_PIN_SIZE = 10
local MAX_QUESTS = 30
local MAX_AREAS_PER_QUEST = 6
local MIN_AREA_PIXELS = 10
local MAX_AREA_FRACTION = 0.9



local DISC_TEXTURE = "Interface\\COMMON\\Indicator-Gray"
local PIN_TEXTURE = "Interface\\COMMON\\Indicator-Yellow"

local DEFAULT_COLORS = {
    routeVerified = { 0.25, 0.80, 1.00, 0.95 },
    routeUnverified = { 1.00, 0.55, 0.10, 0.95 },
    accent = { 0.31, 0.76, 0.97, 1.0 },
}


local KIND_COLOR = { [1] = "routeUnverified", [3] = "routeUnverified" }

local function settings()
    local s = FGPS.DB and FGPS.DB.settings or nil
    if type(s) == "table" and type(s.quests) == "table" then return s, s.quests end
    return s, nil
end

local function skinColor(name)
    local Skins = FGPS.UI.Skins
    if Skins and Skins.Current then
        local ok, skin = pcall(Skins.Current)
        local c = ok and type(skin) == "table" and type(skin.colors) == "table" and skin.colors[name] or nil
        if type(c) == "table" then
            local r, g, b, a = c[1] or c.r, c[2] or c.g, c[3] or c.b, c[4] or c.a
            if r and g and b then return r, g, b, a or 1 end
        end
    end
    local d = DEFAULT_COLORS[name] or DEFAULT_COLORS.accent
    return d[1], d[2], d[3], d[4]
end

local function questData()
    local QuestData = FGPS.QuestData
    if QuestData and QuestData.Available and QuestData.Available() then return QuestData end
    return nil
end






function QuestMap.DrawableQuests()
    local out, seen = {}, {}
    local function add(questID)
        if not questID or seen[questID] then return end
        seen[questID] = true
        out[#out + 1] = questID
    end
    local Quests = FGPS.Quests
    if Quests and Quests.List then
        local ok, list = pcall(Quests.List)
        if ok and type(list) == "table" then
            for _, q in ipairs(list) do
                if #out >= MAX_QUESTS then break end
                add(q.questID)
            end
        end
    end
    add(QuestMap.focus)
    return out
end






function QuestMap.MarkersFor(questID, accepted)
    local QuestData = questData()
    if not QuestData then return {} end
    local _, quests = settings()
    local out = {}
    local title = (FGPS.UI.QuestPanel and FGPS.UI.QuestPanel.TitleFor and FGPS.UI.QuestPanel.TitleFor(questID))
        or format(L["Quest %d"], questID)





    local areas
    local Quests = FGPS.Quests
    if accepted and Quests and Quests.OpenAreas then
        local ok, open = pcall(Quests.OpenAreas, questID)
        if ok and type(open) == "table" then
            areas = {}
            for i, entry in ipairs(open) do areas[i] = entry.area end
        end
    end
    areas = areas or QuestData.AreasFor(questID)

    local mark = QuestData.Mark(questID)
    local start = QuestData.Start(questID)
    if start and not start.interior and not accepted then
        out[#out + 1] = { kind = "giver", questID = questID, inst = start.inst, x = start.x, y = start.y,
                          label = QuestData.StartLabel and QuestData.StartLabel(title, start) or format(L["%s (start)"], title), mark = mark,
                          accepted = accepted }
    end
    local turnIn = QuestData.TurnIn(questID)




    local showTurnIn = turnIn and not turnIn.interior
    if showTurnIn and accepted then
        local q = Quests and Quests.Get and Quests.Get(questID)
        showTurnIn = q and q.complete == true
    end
    if showTurnIn then

        out[#out + 1] = { kind = "turnin", questID = questID, inst = turnIn.inst, x = turnIn.x, y = turnIn.y,
                          label = format(turnIn.later and L["%s (turn-in, from later records)"] or L["%s (turn-in)"], title), mark = mark,
                          accepted = accepted }
    end
    if not (quests and quests.objectiveAreas == false) then
        local drawn = 0
        for _, area in ipairs(areas) do
            if drawn >= MAX_AREAS_PER_QUEST then break end
            if not area.interior then
                drawn = drawn + 1
                out[#out + 1] = {
                    kind = "area", questID = questID, inst = area.inst, x = area.x, y = area.y,
                    r68 = area.r68 or 0, r = area.r or area.r68 or 0, objectiveKind = area.kind, objective = area.objective,
                    label = QuestData.AreaLabel(area),
                    mark = mark, accepted = accepted,
                }
            end
        end
    end
    return out
end


function QuestMap.AllMarkers()



    local drawable = QuestMap.DrawableQuests()
    local Quests = FGPS.Quests
    local accepted = {}
    if Quests and Quests.byID then
        for id in pairs(Quests.byID) do accepted[id] = true end
    end
    local out = {}
    for _, questID in ipairs(drawable) do
        for _, marker in ipairs(QuestMap.MarkersFor(questID, accepted[questID] == true)) do
            out[#out + 1] = marker
        end
    end
    return out
end




local function ensurePools()
    if QuestMap.pinPool then return true end
    local overlay = QuestMap.overlay
    if not overlay or not CreateFramePool then return false end
    QuestMap.pinPool = CreateFramePool("Frame", QuestMap.pinLayer or overlay, nil, function(_, pin)
        pin:Hide()
        pin:ClearAllPoints()
    end)
    QuestMap.areaPool = CreateFramePool("Frame", overlay, nil, function(_, disc)
        disc:Hide()
        disc:ClearAllPoints()
    end)
    return true
end

local function setupPin(pin)
    if pin.fgpsReady then return end
    pin.fgpsReady = true
    pin.ring = pin:CreateTexture(nil, "BACKGROUND")
    pin.ring:SetAllPoints(pin)
    pin.ring:SetTexture(PIN_TEXTURE)
    pin.fill = pin:CreateTexture(nil, "ARTWORK")
    pin.fill:SetPoint("TOPLEFT", pin, "TOPLEFT", 3, -3)
    pin.fill:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", -3, 3)
    pin.fill:SetTexture(PIN_TEXTURE)


    pin:EnableMouse(true)
    if pin.SetMouseClickEnabled then pin:SetMouseClickEnabled(false) end
    pin:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.fgpsLabel or L["Quest"])
        if self.fgpsStage and self.fgpsStage ~= "" then
            GameTooltip:AddLine(self.fgpsStage, 1, 1, 1, true)
        end
        if self.fgpsProgress and self.fgpsProgress ~= "" then
            GameTooltip:AddLine(self.fgpsProgress, 0.9, 0.9, 0.9, true)
        end
        if self.fgpsUnverified then
            GameTooltip:AddLine(L["Unconfirmed place"], 1, 0.85, 0.4, true)
        end
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function(self)
        if GameTooltip and (not GameTooltip.IsOwned or GameTooltip:IsOwned(self)) then GameTooltip:Hide() end
    end)
end



local function setupDisc(disc)
    if disc.fgpsReady then return end
    disc.fgpsReady = true
    disc.fill = disc:CreateTexture(nil, "BACKGROUND")
    disc.fill:SetAllPoints(disc)
    disc.fill:SetTexture(DISC_TEXTURE)


    disc:EnableMouse(true)
    if disc.SetMouseClickEnabled then disc:SetMouseClickEnabled(false) end
    disc:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.fgpsLabel or L["Quest"])
        GameTooltip:Show()
    end)
    disc:SetScript("OnLeave", function(self)
        if GameTooltip and (not GameTooltip.IsOwned or GameTooltip:IsOwned(self)) then GameTooltip:Hide() end
    end)
end



local function stylePin(pin, marker)
    pin.fgpsLabel = marker.label or marker.name or L["Quest"]
    local kind = marker.kind
    if kind == "giver" then
        pin.fgpsStage = L["Start"]
    elseif kind == "turnin" then
        pin.fgpsStage = L["Turn-in"]
    elseif kind == "area" then
        pin.fgpsStage = L["Objective"]
    else
        pin.fgpsStage = nil
    end
    local obj = marker.objective
    if type(obj) == "string" and obj ~= "" then
        pin.fgpsProgress = obj
    elseif type(obj) == "table" and obj.text then
        pin.fgpsProgress = tostring(obj.text)
    else
        pin.fgpsProgress = nil
    end
    local unverified = (marker.mark or 0) <= 1
    pin.fgpsUnverified = unverified
    local name = unverified and "routeUnverified" or "routeVerified"
    local r, g, b = skinColor(name)
    if unverified then
        pin:SetSize(PIN_SIZE_UNVERIFIED, PIN_SIZE_UNVERIFIED)
        pin.ring:SetVertexColor(r, g, b, 0.95)
        pin.fill:SetVertexColor(0, 0, 0, 0.55)
    else
        pin:SetSize(PIN_SIZE, PIN_SIZE)
        pin.ring:SetVertexColor(0, 0, 0, 0.8)
        pin.fill:SetVertexColor(r, g, b, 0.95)
    end
    if not marker.accepted then pin:SetAlpha(0.8) else pin:SetAlpha(1) end
end
QuestMap.StylePin = stylePin

local function toMap(inst, x, y, mapID)
    local Coords = FGPS.Coords
    if Coords and Coords.WorldToMap then
        local ok, id, mx, my = pcall(Coords.WorldToMap, inst, x, y, mapID)
        if ok and id == mapID and mx and my then return mx, my end
    end
    return nil
end



function QuestMap.MapYards(mapID)
    local maps = FGPS.Data and FGPS.Data.maps
    local m = maps and maps[mapID]
    if not m or not m.minX then return nil end
    return (m.maxX - m.minX), (m.maxY - m.minY)
end

function QuestMap:ClearDrawing()
    if self.pinPool then self.pinPool:ReleaseAll() end
    if self.areaPool then self.areaPool:ReleaseAll() end
    self.lastPinCount, self.lastAreaCount = 0, 0
    self.lastDrawMapID = nil
end

local function canvasScale()
    local map = WorldMapFrame
    if map and map.GetCanvasScale then
        local ok, scale = pcall(map.GetCanvasScale, map)
        if ok and type(scale) == "number" and scale > 0 then return scale end
    end
    return 1
end




local function placePin(pin, canvas, w, h, scale)
    pin:SetScale(1 / scale)
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", canvas, "TOPLEFT", (pin.normalizedX * w) * scale, -(pin.normalizedY * h) * scale)
end

function QuestMap:OnScaleChanged()
    local map = WorldMapFrame
    local canvas = map and map.GetCanvas and map:GetCanvas()
    if not canvas then return end
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    local scale = canvasScale()
    if self.pinPool then
        for pin in self.pinPool:EnumerateActive() do
            if pin.normalizedX then placePin(pin, canvas, w, h, scale) end
        end
    end
end

function QuestMap:Redraw()
    local map = WorldMapFrame
    if not map or not self.overlay then return end
    if not ensurePools() then return end
    local _, quests = settings()
    local wanted = not (quests and (quests.enabled == false or quests.mapPins == false))
        and not (FGPS.Perf and FGPS.Perf.guidanceEnabled == false)
        and not (map.IsShown and not map:IsShown())
    local mapID = wanted and map:GetMapID() or nil




    local markers = mapID and QuestMap.AllMarkers() or nil
    self:ClearDrawing()
    if not markers then return end
    local Perf = FGPS.Perf
    if Perf then Perf:Begin("questMap") end
    local canvas = map:GetCanvas()
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    local scale = canvasScale()
    local spanX = QuestMap.MapYards(mapID)
    local pins, areas = 0, 0
    for _, marker in ipairs(markers) do
        local mx, my = toMap(marker.inst, marker.x, marker.y, mapID)
        if mx and mx >= 0 and mx <= 1 and my >= 0 and my <= 1 then
            if marker.kind == "area" then
                local disc = self.areaPool:Acquire()
                setupDisc(disc)



                local size = MIN_AREA_PIXELS
                if spanX and spanX > 0 then
                    local fraction = (marker.r68 * 2) / spanX
                    if fraction > MAX_AREA_FRACTION then fraction = MAX_AREA_FRACTION end
                    size = fraction * w
                    if size < MIN_AREA_PIXELS then size = MIN_AREA_PIXELS end
                end
                disc:SetSize(size, size)
                disc:ClearAllPoints()
                disc:SetPoint("CENTER", canvas, "TOPLEFT", mx * w, -my * h)
                local r, g, b = skinColor(KIND_COLOR[marker.objectiveKind] or "accent")
                disc.fill:SetVertexColor(r, g, b, 0.28)

                disc.fgpsLabel = marker.label
                disc:Show()
                areas = areas + 1
            else
                local pin = self.pinPool:Acquire()
                setupPin(pin)
                stylePin(pin, marker)
                pin.normalizedX, pin.normalizedY = mx, my
                placePin(pin, canvas, w, h, scale)
                pin:Show()
                pins = pins + 1
            end
        end
    end
    self.lastPinCount, self.lastAreaCount, self.lastDrawMapID = pins, areas, mapID
    if Perf then Perf:End("questMap") end
end




local function makeMinimapIcon()
    local parent = _G and _G.Minimap or UIParent
    local icon = CreateFrame("Frame", nil, parent)
    icon:SetSize(MINIMAP_PIN_SIZE, MINIMAP_PIN_SIZE)
    icon:EnableMouse(false)
    icon.border = icon:CreateTexture(nil, "BACKGROUND")
    icon.border:SetAllPoints(icon)
    icon.border:SetTexture(PIN_TEXTURE)
    icon.fill = icon:CreateTexture(nil, "ARTWORK")
    icon.fill:SetPoint("TOPLEFT", icon, "TOPLEFT", 2, -2)
    icon.fill:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2, 2)
    icon.fill:SetTexture(PIN_TEXTURE)
    icon:Hide()
    return icon
end

function QuestMap:ClearMinimap()
    if self.pins and self.minimapActive then self.pins:RemoveAllMinimapIcons(REF) end
    if self.minimapPool then self.minimapPool:ReleaseAll() end
    self.minimapActive = false
    self.lastMinimapCount = 0
end

function QuestMap:RefreshMinimap()
    local _, quests = settings()
    local wanted = self.pins ~= nil and not (quests and (quests.enabled == false or quests.minimapPins == false))
        and not (FGPS.Perf and FGPS.Perf.guidanceEnabled == false)


    local markers = wanted and QuestMap.AllMarkers() or nil
    self:ClearMinimap()
    if not markers then return end
    if not self.minimapPool then
        if not CreateObjectPool then return end
        self.minimapPool = CreateObjectPool(makeMinimapIcon, function(_, icon) icon:Hide() end)
    end
    local placed = 0
    for _, marker in ipairs(markers) do


        if marker.kind ~= "area" then
            local icon = self.minimapPool:Acquire()
            local unverified = (marker.mark or 0) <= 1
            local r, g, b = skinColor(unverified and "routeUnverified" or "routeVerified")
            if unverified then
                icon.border:SetVertexColor(r, g, b, 0.95)
                icon.fill:SetVertexColor(0, 0, 0, 0.55)
            else
                icon.border:SetVertexColor(0, 0, 0, 0.8)
                icon.fill:SetVertexColor(r, g, b, 0.95)
            end



            self.pins:AddMinimapIconWorld(REF, icon, marker.inst, marker.x, marker.y, false)
            placed = placed + 1
        end
    end
    self.minimapActive = placed > 0
    self.lastMinimapCount = placed
end






function QuestMap.SetFocus(questID)
    questID = tonumber(questID)
    if QuestMap.focus == questID then return end
    QuestMap.focus = questID
    QuestMap:Redraw()
    QuestMap:RefreshMinimap()
end







function QuestMap.PinLayerLevel(canvasLevel)
    local MapPlaces = FGPS.UI.MapPlaces
    if MapPlaces and MapPlaces.LayerLevel then
        return MapPlaces.LayerLevel(canvasLevel) + (MapPlaces.MAX_ICONS or 0) + 1
    end
    return (canvasLevel or 1) + 2
end

local function createProvider()
    local base = MapCanvasDataProviderMixin or {}
    local provider = CreateFromMixins(base)
    function provider:OnAdded(owningMap)
        if base.OnAdded then base.OnAdded(self, owningMap) else self.owningMap = owningMap end
        if not QuestMap.overlay then
            local canvas = owningMap:GetCanvas()

            local overlay = CreateFrame("Frame", nil, canvas)
            overlay:SetAllPoints(canvas)
            overlay:SetFrameLevel((canvas:GetFrameLevel() or 1) + 2)
            overlay:EnableMouse(false)
            QuestMap.overlay = overlay


            local WorldMap = FGPS.UI.WorldMap
            local pinLayer = CreateFrame("Frame", nil, (WorldMap and WorldMap.pinLayer) or canvas)
            pinLayer:SetAllPoints(canvas)
            pinLayer:SetFrameLevel(QuestMap.PinLayerLevel(canvas:GetFrameLevel()))
            pinLayer:EnableMouse(false)
            QuestMap.pinLayer = pinLayer
        end
    end
    function provider:OnRemoved(owningMap)
        QuestMap:ClearDrawing()
        if base.OnRemoved then pcall(base.OnRemoved, self, owningMap) else self.owningMap = nil end
    end
    function provider:RemoveAllData() QuestMap:ClearDrawing() end
    function provider:RefreshAllData() QuestMap:Redraw() end
    function provider:OnMapChanged() QuestMap:Redraw() end
    function provider:OnShow() QuestMap:Redraw() end
    function provider:OnHide() QuestMap:ClearDrawing() end
    function provider:OnCanvasScaleChanged() QuestMap:OnScaleChanged() end
    function provider:OnCanvasSizeChanged() QuestMap:Redraw() end
    return provider
end

function QuestMap:Attach()
    if self.attached then return true end
    local map = WorldMapFrame
    if not map or not map.AddDataProvider or not CreateFromMixins then return false end
    self.provider = self.provider or createProvider()
    local ok, err = pcall(map.AddDataProvider, map, self.provider)
    if not ok then
        FGPS.Log:Error("Quest map provider could not be added: %s", tostring(err))
        return false
    end
    self.attached = true
    return true
end




local function refreshBoth()
    QuestMap:Redraw()
    QuestMap:RefreshMinimap()
end

function QuestMap:Init()
    if LibStub and not self.pins then
        self.pins = LibStub("HereBeDragons-Pins-2.0", true)
        if not self.pins then FGPS.Log:Warn("HereBeDragons-Pins-2.0 not found; quest pins on the minimap are disabled") end
    end
    if FGPS.ready then self:Attach() end
    if self.eventsBound then return end
    self.eventsBound = true
    local Events = FGPS.Events




    Events:Register("ADDON_READY", function() QuestMap:Attach() end, self)
    if not WorldMapFrame then
        Events:RegisterWoW("ADDON_LOADED", function(_, name)
            if name == "Blizzard_WorldMap" and FGPS.ready then QuestMap:Attach() end
        end, self)
    end
    Events:Register("QUESTS_UPDATED", refreshBoth, self)
    Events:Register("QUEST_TITLE_RESOLVED", refreshBoth, self)
    Events:Register("SETTINGS_CHANGED", function(_, key)
        if key == "*" or key == "preset" or key == "accessibility.colorScheme"
            or (type(key) == "string" and key:sub(1, 7) == "quests.") then
            refreshBoth()
        end
    end, self)
    Events:Register("UI_PRESET_APPLIED", refreshBoth, self)

    local Quests = FGPS.Quests
    if Quests and Quests.Invalidate then pcall(Quests.Invalidate) end
end
