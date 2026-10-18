



















local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local type, ipairs, pairs, tostring, pcall, format = type, ipairs, pairs, tostring, pcall, string.format
local sqrt, min, max = math.sqrt, math.min, math.max

local MEDIA = "Interface\\AddOns\\Cabbie\\Media\\"



local function dockTexture(index, P)
    local name = P and P.name and P.name[index]
    if type(name) == "string" and name:lower():find("zeppelin", 1, true) then
        return MEDIA .. "place_zeppelin"
    end
    return MEDIA .. "place_boat"
end

local MapPlaces = {
    provider = nil,
    layer = nil,
    pool = nil,
    attached = false,
    lastDrawMapID = nil,
    lastCount = 0,
    ICON_SIZE = 18,
    ICON_SIZE_HOVER = 22,



    MAX_ICONS = 60,





    LAYER_GAP = 100,






    CATEGORIES = {
        { key = "towns", types = { 1, 5 }, hostTypes = { [5] = true }, default = true,
          textures = { [1] = MEDIA .. "place_town", [5] = MEDIA .. "place_city" },
          label = "Show towns on the world map (click one to route there)",
          tooltip = "Every town of the zone you are looking at gets a small icon on the world map. Left-click one to route there. Towns of the other faction are dimmed." },
        { key = "flight", types = { 6 }, texture = MEDIA .. "place_flight", default = false,
          label = "Show flight masters on the world map",
          tooltip = "Flight masters of the zone you are looking at get a small icon on the world map. Left-click one to route there." },
        { key = "inns", types = { 7 }, texture = MEDIA .. "place_inn", default = false,
          label = "Show inns on the world map",
          tooltip = "Inns of the zone you are looking at get a small icon on the world map. Left-click one to route there." },
        { key = "dungeons", types = { 3 }, texture = MEDIA .. "place_dungeon", default = false,
          label = "Show dungeon entrances on the world map",
          tooltip = "Dungeon entrances of the zone you are looking at get a small icon on the world map. Left-click one to route there." },
        { key = "banks", types = { 11 }, texture = MEDIA .. "place_bank", default = false,
          label = "Show banks on the world map",
          tooltip = "Banks of the zone you are looking at get a small icon on the world map. Left-click one to route there." },
        { key = "auction", types = { 12 }, texture = MEDIA .. "place_auction", default = false,
          label = "Show auction houses on the world map",
          tooltip = "Auction houses of the zone you are looking at get a small icon on the world map. Left-click one to route there." },
        { key = "mailbox", types = { 10 }, texture = MEDIA .. "place_mailbox", default = false,
          label = "Show mailboxes on the world map",
          tooltip = "Mailboxes of the zone you are looking at get a small icon on the world map. Left-click one to route there." },
        { key = "vendors", types = { 8 }, texture = MEDIA .. "place_vendor", default = false,
          label = "Show vendors on the world map",
          tooltip = "Vendors of the zone you are looking at get a small icon on the world map. Left-click one to route there. Busy cities have many, so this starts off." },
        { key = "repair", types = { 9 }, texture = MEDIA .. "place_repair", default = false,
          label = "Show repair vendors on the world map",
          tooltip = "Repair vendors of the zone you are looking at get a small icon on the world map. Left-click one to route there." },
        { key = "trainers", types = { 13 }, texture = MEDIA .. "place_trainer", default = false,
          label = "Show trainers on the world map",
          tooltip = "Trainers of the zone you are looking at get a small icon on the world map. Left-click one to route there." },
        { key = "stables", types = { 20 }, texture = MEDIA .. "place_stable", default = false,
          label = "Show stable masters on the world map",
          tooltip = "Stable masters of the zone you are looking at get a small icon on the world map. Left-click one to route there." },
        { key = "docks", types = { 14 }, texture = MEDIA .. "place_boat", texturePick = dockTexture, default = false,
          label = "Show docks and zeppelin towers on the world map",
          tooltip = "Boat docks and zeppelin towers of the zone you are looking at get a small icon on the world map. Left-click one to route there." },
        { key = "graveyards", types = { 16 }, texture = MEDIA .. "place_graveyard", default = false,
          label = "Show graveyards on the world map",
          tooltip = "Graveyards of the zone you are looking at get a small icon on the world map. Left-click one to route there." },
    },
}
FGPS.UI.MapPlaces = MapPlaces


do
    local defaults = {}
    for _, row in ipairs(MapPlaces.CATEGORIES) do defaults[row.key] = row.default ~= false end
    FGPS.UI.AddSettingDefault("mapPlaces", defaults)
end

local FACTION_SENTENCE = {
    [1] = "This place belongs to the Alliance.",
    [2] = "This place belongs to the Horde.",
}
local DIMMED_ALPHA = 0.55




local function settings()
    return FGPS.DB and FGPS.DB.settings or nil
end

local function poi()
    return FGPS.Data and FGPS.Data.poi or nil
end



function MapPlaces.TextureFor(row, index)
    local P = poi()
    if type(row.texturePick) == "function" then
        local picked = row.texturePick(index, P)
        if type(picked) == "string" then return picked end
    end
    if type(row.textures) == "table" and P and P.type then
        local byType = row.textures[P.type[index]]
        if type(byType) == "string" then return byType end
    end
    return row.texture
end



function MapPlaces.CategoryEnabled(row)
    local s = settings()
    local places = s and s.mapPlaces
    local value
    if type(places) == "table" then value = places[row.key] end
    if value == nil then return row.default ~= false end
    return value ~= false
end






function MapPlaces.MapShowsPlaces(mapID)
    if type(mapID) ~= "number" then return false end
    local maps = FGPS.Data and FGPS.Data.maps
    local m = maps and maps[mapID]
    if m and m.kind ~= nil then return m.kind == 3 end
    if C_Map and C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, mapID)
        if ok and type(info) == "table" then
            local zone = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
            return info.mapType == zone
        end
    end
    return false
end



local indexCache = {}
local function indicesFor(row)
    local P = poi()
    if not P then return {} end
    local cached = indexCache[row.key]
    if cached and cached.source == P then return cached.list end
    local wanted = {}
    for _, code in ipairs(row.types) do wanted[code] = true end
    local list = {}
    for i = 1, P.n or 0 do
        if wanted[P.type[i]] then list[#list + 1] = i end
    end
    indexCache[row.key] = { source = P, list = list }
    return list
end







local hostCache = {}
function MapPlaces.HostZone(index)
    local P = poi()
    local maps = FGPS.Data and FGPS.Data.maps
    if not P or not maps or not P.x[index] then return nil end
    local cached = hostCache[index]
    if cached ~= nil then return cached or nil end
    local inst, x, y, own = P.inst[index], P.x[index], P.y[index], P.map[index]
    local best, bestDepth
    for mapID, m in pairs(maps) do
        if mapID ~= own and m.kind == 3 and not m.sys and m.inst == inst and m.minX
            and x >= m.minX and x <= m.maxX and y >= m.minY and y <= m.maxY then
            local fx = (x - m.minX) / (m.maxX - m.minX)
            local fy = (y - m.minY) / (m.maxY - m.minY)
            local depth = min(fx, 1 - fx, fy, 1 - fy)
            if not bestDepth or depth > bestDepth or (depth == bestDepth and mapID < best) then
                best, bestDepth = mapID, depth
            end
        end
    end
    hostCache[index] = best or false
    return best
end

local function toMap(inst, x, y, mapID)
    local Coords = FGPS.Coords
    if Coords and Coords.WorldToMap then
        local ok, id, mx, my = pcall(Coords.WorldToMap, inst, x, y, mapID)
        if ok and id == mapID and mx and my then return mx, my end
    end
    return nil
end



local function isOtherFaction(fac)
    local Destinations = FGPS.Destinations
    if not Destinations or not Destinations.PlayerFactionCode or not Destinations.FactionAllowed then return false end
    return not Destinations.FactionAllowed(fac, Destinations.PlayerFactionCode(), false)
end





local function factionOf(index)
    local Destinations = FGPS.Destinations
    if Destinations and Destinations.PlaceFaction then return Destinations.PlaceFaction(index) end
    local P = poi()
    return P and P.fac and P.fac[index] or nil
end







function MapPlaces.PlacesFor(mapID)
    local out = {}
    if not MapPlaces.MapShowsPlaces(mapID) then return out end
    local P = poi()
    if not P then return out end
    for _, row in ipairs(MapPlaces.CATEGORIES) do
        if MapPlaces.CategoryEnabled(row) then
            for _, i in ipairs(indicesFor(row)) do
                if #out >= MapPlaces.MAX_ICONS then return out end
                local belongs = P.map[i] == mapID
                if not belongs and row.hostTypes and row.hostTypes[P.type[i]] then
                    belongs = MapPlaces.HostZone(i) == mapID
                end
                if belongs then
                    local mx, my = toMap(P.inst[i], P.x[i], P.y[i], mapID)
                    if mx and mx >= 0 and mx <= 1 and my >= 0 and my <= 1 then
                        out[#out + 1] = { index = i, x = mx, y = my, category = row,
                                          otherFaction = isOtherFaction(factionOf(i)) }
                    end
                end
            end
        end
    end
    return out
end




function MapPlaces.TooltipLines(index)
    local P = poi()
    if not P or not P.name[index] then return {} end
    local Destinations = FGPS.Destinations
    local lines = { P.name[index] }
    local typeName = Destinations and Destinations.TypeName and Destinations.TypeName(P.type[index]) or nil
    local kind = (Destinations and Destinations.TypeLabel and Destinations.TypeLabel(typeName)) or L["Location"]
    local zoneNames = FGPS.Data and FGPS.Data.zoneNames
    local zone = zoneNames and zoneNames[P.zone and P.zone[index] or 0] or nil
    lines[#lines + 1] = zone and format(L["%s, %s"], kind, zone) or kind
    local fac = factionOf(index)
    if isOtherFaction(fac) and FACTION_SENTENCE[fac] then
        lines[#lines + 1] = "|cffff6060" .. L[FACTION_SENTENCE[fac]] .. "|r"
    end
    local Coords = FGPS.Coords
    if Coords and Coords.PlayerPos then
        local ok, pos = pcall(Coords.PlayerPos)
        if ok and type(pos) == "table" and pos.inst == P.inst[index] and pos.x and pos.y then
            local dx, dy = pos.x - P.x[index], pos.y - P.y[index]
            local s = settings()
            lines[#lines + 1] = format(L["%s away in a straight line"], Util.FormatDistance(sqrt(dx * dx + dy * dy), s and s.units))
        end
    end
    lines[#lines + 1] = L["Click: guide me here"]
    lines[#lines + 1] = L["During a trip, left-click asks before replacing the route"]
    return lines
end










local REPLACE_POPUP = "CABBIE_REPLACE_ROUTE"

local function ensureReplacePopup()
    if type(StaticPopupDialogs) ~= "table" then return false end
    if StaticPopupDialogs[REPLACE_POPUP] then return true end
    StaticPopupDialogs[REPLACE_POPUP] = {
        text = "%s",
        button1 = L["Replace"],
        button2 = L["Keep going"],
        button3 = L["Add as stop"],
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        OnAccept = function(self)
            local dest = self.data
            local WorldMap = FGPS.UI.WorldMap
            if dest and WorldMap and WorldMap.GoTo then WorldMap.GoTo(dest, { start = true }) end
        end,
        OnCancel = function() end,
        OnAlt = function(self)
            local dest = self.data
            local WorldMap = FGPS.UI.WorldMap
            if dest and WorldMap and WorldMap.GoTo then WorldMap.GoTo(dest, { addStop = true, start = false }) end
        end,
    }
    return true
end

local function askBeforeReplace(dest)
    if not ensureReplacePopup() or type(StaticPopup_Show) ~= "function" then
        local WorldMap = FGPS.UI.WorldMap
        if WorldMap and WorldMap.GoTo then WorldMap.GoTo(dest, { start = true }) end
        return
    end
    local name = (dest and dest.name) or L["that place"]
    local dialog = StaticPopup_Show(REPLACE_POPUP, (L["Replace the route to %s?"]):format(name))
    if type(dialog) == "table" then dialog.data = dest end
end

local function onClick(icon, button)
    local index = icon.poiIndex
    local Destinations = FGPS.Destinations
    local WorldMap = FGPS.UI.WorldMap
    if not index or not Destinations or not Destinations.FromPOI or not WorldMap or not WorldMap.GoTo then return end
    if button and button ~= "LeftButton" then return end
    local ok, dest = pcall(Destinations.FromPOI, index)
    if not ok then
        FGPS.Log:Error("FromPOI failed for place %s: %s", tostring(index), tostring(dest))
        return
    end



    local goNow = WorldMap.IsGoClick and WorldMap.IsGoClick("LeftButton")
    if not dest then
        local Guide = FGPS.UI.Guide
        if not goNow then
            FGPS:Print(L["That map position cannot be used as a destination%s"], ".")
        elseif Guide and Guide.Say then
            Guide.Say(L["That spot cannot be reached"], WorldMap.GO_REFUSED_SECONDS)
        end
        return
    end
    if goNow then
        local Go = FGPS.UI.Go
        if Go and Go.Start then Go.Start(dest) end
        return
    end
    local Search = FGPS.UI.Search
    if Search and Search.addStopMode == true then
        WorldMap.GoTo(dest, { addStop = true, start = false })
        return
    end
    if Search and Search.JourneyRunning and Search.JourneyRunning() then
        askBeforeReplace(dest)
        return
    end
    WorldMap.GoTo(dest, { start = true })
end

local function onEnter(icon)
    icon:SetSize(MapPlaces.ICON_SIZE_HOVER, MapPlaces.ICON_SIZE_HOVER)
    MapPlaces.hoveredIcon = icon
    if not GameTooltip or not icon.poiIndex then return end
    GameTooltip:SetOwner(icon, "ANCHOR_RIGHT")
    for i, line in ipairs(MapPlaces.TooltipLines(icon.poiIndex)) do
        if i == 1 then GameTooltip:AddLine(line) else GameTooltip:AddLine(line, 1, 1, 1, true) end
    end
    GameTooltip:Show()
end

local function onLeave(icon)
    icon:SetSize(MapPlaces.ICON_SIZE, MapPlaces.ICON_SIZE)
    if MapPlaces.hoveredIcon == icon then MapPlaces.hoveredIcon = nil end
    if GameTooltip and (not GameTooltip.IsOwned or GameTooltip:IsOwned(icon)) then GameTooltip:Hide() end
end



function MapPlaces:RefreshOpenTooltip()
    local icon = self.hoveredIcon
    if not icon or not icon.poiIndex or not GameTooltip then return end
    if GameTooltip.IsOwned and not GameTooltip:IsOwned(icon) then return end
    GameTooltip:ClearLines()
    for i, line in ipairs(MapPlaces.TooltipLines(icon.poiIndex)) do
        if i == 1 then GameTooltip:AddLine(line) else GameTooltip:AddLine(line, 1, 1, 1, true) end
    end
    GameTooltip:Show()
end



local function resetIcon(_, icon)
    if icon.poiIndex then onLeave(icon) end
    icon.poiIndex = nil
    icon.normalizedX, icon.normalizedY = nil, nil
    icon:Hide()
    icon:ClearAllPoints()
end

local function setupIcon(icon)
    if icon.fgpsReady then return end
    icon.fgpsReady = true
    icon:SetSize(MapPlaces.ICON_SIZE, MapPlaces.ICON_SIZE)
    icon.art = icon:CreateTexture(nil, "ARTWORK")
    icon.art:SetAllPoints(icon)
    icon:EnableMouse(true)


    icon:EnableMouseWheel(false)


    icon:RegisterForClicks("LeftButtonUp")
    icon:SetScript("OnClick", onClick)
    icon:SetScript("OnEnter", onEnter)
    icon:SetScript("OnLeave", onLeave)
end

local function ensurePool()
    if MapPlaces.pool then return true end
    if not MapPlaces.layer or not CreateFramePool then return false end
    MapPlaces.pool = CreateFramePool("Button", MapPlaces.layer, nil, resetIcon)
    return true
end

local function canvasScale()
    local map = WorldMapFrame
    if map and map.GetCanvasScale then
        local ok, scale = pcall(map.GetCanvasScale, map)
        if ok and type(scale) == "number" and scale > 0 then return scale end
    end
    return 1
end




local function positionIcon(icon, canvas, w, h, scale)
    icon:SetScale(1 / scale)
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", canvas, "TOPLEFT", (icon.normalizedX * w) * scale, -(icon.normalizedY * h) * scale)
end

function MapPlaces:ClearDrawing()
    if self.pool then self.pool:ReleaseAll() end
    self.lastCount = 0
    self.lastDrawMapID = nil
end


function MapPlaces:Redraw()
    local map = WorldMapFrame
    if not map or not self.layer then return end
    if not ensurePool() then return end
    self:ClearDrawing()
    if FGPS.Perf and FGPS.Perf.guidanceEnabled == false then return end
    if map.IsShown and not map:IsShown() then return end
    local mapID = map:GetMapID()
    if not mapID then return end
    local Perf = FGPS.Perf
    if Perf then Perf:Begin("mapPlaces") end
    local canvas = map:GetCanvas()
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    local scale = canvasScale()
    local baseLevel = self.layer:GetFrameLevel() or 1
    local count = 0
    for _, place in ipairs(MapPlaces.PlacesFor(mapID)) do
        local icon = self.pool:Acquire()
        setupIcon(icon)
        count = count + 1
        icon.poiIndex = place.index
        icon.normalizedX, icon.normalizedY = place.x, place.y
        icon.art:SetTexture(MapPlaces.TextureFor(place.category, place.index))

        icon.art:SetDesaturated(place.otherFaction)
        icon:SetAlpha(place.otherFaction and DIMMED_ALPHA or 1)
        icon.dimmed = place.otherFaction


        icon:SetFrameLevel(baseLevel + count)
        icon:SetSize(MapPlaces.ICON_SIZE, MapPlaces.ICON_SIZE)
        positionIcon(icon, canvas, w, h, scale)
        icon:Show()
    end
    self.lastCount, self.lastDrawMapID = count, mapID
    if Perf then Perf:End("mapPlaces") end
end


function MapPlaces:OnScaleChanged()
    if not self.pool or self.lastCount == 0 then return end
    local map = WorldMapFrame
    local canvas = map and map:GetCanvas()
    if not canvas then return end
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    local scale = canvasScale()
    for icon in self.pool:EnumerateActive() do
        if icon.normalizedX then positionIcon(icon, canvas, w, h, scale) end
    end
end






function MapPlaces.LayerLevel(canvasLevel)
    local WorldMap = FGPS.UI.WorldMap
    local pinLevels = WorldMap and WorldMap.PIN_LAYER_LEVELS or 5000
    return min(9000, (canvasLevel or 1) + pinLevels) - MapPlaces.LAYER_GAP
end




local function ensureLayer(owningMap)
    if MapPlaces.layer then return MapPlaces.layer end
    local canvas = owningMap:GetCanvas()
    local WorldMap = FGPS.UI.WorldMap
    local pinLayer = WorldMap and WorldMap.pinLayer
    local parent = pinLayer or canvas
    local layer = CreateFrame("Frame", nil, parent)
    layer:SetAllPoints(canvas)
    if pinLayer then
        layer:SetFrameLevel(max(1, (pinLayer:GetFrameLevel() or 1) - MapPlaces.LAYER_GAP))
    else

        layer:SetFrameLevel(MapPlaces.LayerLevel(canvas:GetFrameLevel()))
    end

    layer:EnableMouse(false)
    MapPlaces.layer = layer
    return layer
end

local function createProvider()
    local base = MapCanvasDataProviderMixin or {}
    local provider = CreateFromMixins(base)
    function provider:OnAdded(owningMap)
        if base.OnAdded then base.OnAdded(self, owningMap) else self.owningMap = owningMap end
        ensureLayer(owningMap)
    end
    function provider:OnRemoved(owningMap)
        MapPlaces:ClearDrawing()
        if base.OnRemoved then pcall(base.OnRemoved, self, owningMap) else self.owningMap = nil end
    end
    function provider:RemoveAllData() MapPlaces:ClearDrawing() end
    function provider:RefreshAllData() MapPlaces:Redraw() end
    function provider:OnMapChanged() MapPlaces:Redraw() end
    function provider:OnShow() MapPlaces:Redraw() end
    function provider:OnHide() MapPlaces:ClearDrawing() end
    function provider:OnCanvasScaleChanged() MapPlaces:OnScaleChanged() end
    function provider:OnCanvasSizeChanged() MapPlaces:Redraw() end
    return provider
end

function MapPlaces:Attach()
    if self.attached then return true end
    local map = WorldMapFrame
    if not map or not map.AddDataProvider or not CreateFromMixins then return false end
    self.provider = self.provider or createProvider()
    local ok, err = pcall(map.AddDataProvider, map, self.provider)
    if not ok then
        FGPS.Log:Error("Map places provider could not be added: %s", tostring(err))
        return false
    end
    self.attached = true

    self:Redraw()
    return true
end




local function onSettingsChanged(_, key)
    if key == "*" or key == "perf.guidanceEnabled"
        or (type(key) == "string" and (key == "mapPlaces" or key:sub(1, 10) == "mapPlaces.")) then
        MapPlaces:Redraw()
    end
end

function MapPlaces:Init()
    if not self.eventsBound then
        self.eventsBound = true
        local Events = FGPS.Events
        Events:Register("SETTINGS_CHANGED", onSettingsChanged, self)


        Events:Register("ADDON_READY", function() MapPlaces:Attach() end, self)
        if not WorldMapFrame then
            Events:RegisterWoW("ADDON_LOADED", function(_, name)
                if name == "Blizzard_WorldMap" and FGPS.ready then MapPlaces:Attach() end
            end, self)
        end
    end
    if FGPS.ready then self:Attach() end
end
