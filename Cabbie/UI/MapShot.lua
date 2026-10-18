



















local ADDON_NAME, FGPS = ...

local L = FGPS.L
local floor, sort = math.floor, table.sort

local MapShot = {
    SETTLE_SECONDS = 1.0,
    AFTER_SHOT_SECONDS = 0.3,
    CORNER_UNITS = 10,
    CELL_UNITS = 8,
    STRIP_GAP = 4,
    ID_BITS = 12,
    frame = nil,
    corners = {},
    cells = {},
    state = nil,
}
FGPS.MapShot = MapShot

local CORNERS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }






function MapShot.MapList()
    local data = FGPS.Data or {}
    local maps, instances = data.maps or {}, data.instances or {}
    local list, area = {}, {}
    for id, m in pairs(maps) do
        local inst = instances[m.inst]
        if m.kind == 3 and not m.sys and inst and inst.instanceType == 0 and id < 2 ^ MapShot.ID_BITS
            and m.minX and m.maxX and m.minY and m.maxY then
            list[#list + 1] = id
            area[id] = (m.maxX - m.minX) * (m.maxY - m.minY)
        end
    end
    sort(list, function(a, b)
        if area[a] ~= area[b] then return area[a] < area[b] end
        return a < b
    end)
    return list
end




local function ensureMarkers()
    if MapShot.frame then return MapShot.frame end
    local canvas = WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
    if not canvas then return nil end
    local frame = CreateFrame("Frame", nil, canvas)
    frame:SetAllPoints(canvas)
    frame:SetFrameStrata("TOOLTIP")
    frame:EnableMouse(false)
    frame:Hide()

    for _, corner in ipairs(CORNERS) do
        local tex = frame:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(1, 0, 1, 1)
        tex:SetSize(MapShot.CORNER_UNITS, MapShot.CORNER_UNITS)
        tex:SetPoint(corner, canvas, corner, 0, 0)
        MapShot.corners[corner] = tex
    end

    local cell, count = MapShot.CELL_UNITS, MapShot.ID_BITS * 2
    local left = MapShot.CORNER_UNITS + MapShot.STRIP_GAP
    local backing = frame:CreateTexture(nil, "ARTWORK")
    backing:SetColorTexture(0, 0, 0, 1)
    backing:SetSize(count * cell + 4, cell + 2)
    backing:SetPoint("TOPLEFT", canvas, "TOPLEFT", left - 2, 0)
    for i = 1, count do
        local tex = frame:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(0, 0, 0, 1)
        tex:SetSize(cell, cell)
        tex:SetPoint("TOPLEFT", canvas, "TOPLEFT", left + (i - 1) * cell, 0)
        MapShot.cells[i] = tex
    end

    MapShot.frame = frame
    return frame
end

local function spellMapID(id)
    local bits = MapShot.ID_BITS
    for i = 1, bits do
        local bit = floor(id / 2 ^ (bits - i)) % 2
        local on, off = MapShot.cells[i], MapShot.cells[bits + i]
        if bit == 1 then
            on:SetColorTexture(1, 1, 1, 1)
            off:SetColorTexture(0, 0, 0, 1)
        else
            on:SetColorTexture(0, 0, 0, 1)
            off:SetColorTexture(1, 1, 1, 1)
        end
    end
end




local function ownOverlays()
    local out = {}
    local UI = FGPS.UI or {}
    local WorldMap, MapPlaces, QuestMap = UI.WorldMap, UI.MapPlaces, UI.QuestMap
    if WorldMap then out[#out + 1] = WorldMap.overlay out[#out + 1] = WorldMap.pinLayer end
    if MapPlaces then out[#out + 1] = MapPlaces.layer end
    if QuestMap then out[#out + 1] = QuestMap.overlay end
    return out
end

local function mapIsOpen()
    return WorldMapFrame and WorldMapFrame.IsShown and WorldMapFrame:IsShown()
end

local function finish(message)
    local state = MapShot.state
    if not state then return end
    MapShot.state = nil
    if state.timer then state.timer:Cancel() end
    if MapShot.frame then MapShot.frame:Hide() end
    for _, overlay in ipairs(state.hidden) do overlay:Show() end
    if state.quality then SetCVar("screenshotQuality", state.quality) end
    if state.mapID and mapIsOpen() then pcall(WorldMapFrame.SetMapID, WorldMapFrame, state.mapID) end
    FGPS:Print(message, state.shots)
end

local nextMap

local function capture()
    local state = MapShot.state
    if not state then return end
    if not mapIsOpen() or InCombatLockdown() then
        finish(L["Map pictures stopped after %d screenshots: the world map was closed or combat began."])
        return
    end
    Screenshot()
    state.shots = state.shots + 1
    state.timer = C_Timer.NewTimer(MapShot.AFTER_SHOT_SECONDS, nextMap)
end

nextMap = function()
    local state = MapShot.state
    if not state then return end
    if not mapIsOpen() or InCombatLockdown() then
        finish(L["Map pictures stopped after %d screenshots: the world map was closed or combat began."])
        return
    end
    state.index = state.index + 1
    local id = state.list[state.index]
    if not id then
        finish(L["Map pictures done: %d screenshots are in the game's Screenshots folder."])
        return
    end
    if not pcall(WorldMapFrame.SetMapID, WorldMapFrame, id) then
        nextMap()
        return
    end
    spellMapID(id)
    state.timer = C_Timer.NewTimer(MapShot.SETTLE_SECONDS, capture)
end

function MapShot.IsRunning() return MapShot.state ~= nil end

function MapShot.Start()
    if MapShot.state then return false end
    if InCombatLockdown() then
        FGPS:Print(L["Map pictures cannot start in combat."])
        return false
    end
    if not mapIsOpen() then
        FGPS:Print(L["Open the world map first, then type /cabbie mapshot again."])
        return false
    end
    local frame = ensureMarkers()
    if not frame or type(Screenshot) ~= "function" then
        FGPS:Print(L["Map pictures are not available in this client."])
        return false
    end

    local state = { list = MapShot.MapList(), index = 0, shots = 0, hidden = {},
                    mapID = WorldMapFrame:GetMapID(), quality = GetCVar("screenshotQuality") }
    for _, overlay in ipairs(ownOverlays()) do
        if overlay:IsShown() then
            overlay:Hide()
            state.hidden[#state.hidden + 1] = overlay
        end
    end
    SetCVar("screenshotQuality", "10")
    frame:Show()
    MapShot.state = state

    local perMap = MapShot.SETTLE_SECONDS + MapShot.AFTER_SHOT_SECONDS
    FGPS:Print(L["Map pictures: %d maps, about %d seconds. Leave the map open; /cabbie mapshot stop cancels."],
        #state.list, floor(#state.list * perMap + 0.5))
    nextMap()
    return true
end

function MapShot.Stop()
    finish(L["Map pictures stopped after %d screenshots."])
end

FGPS.Slash.Register("mapshot", function(args)
    local word = FGPS.Util.Lower(FGPS.Util.Trim(args))
    if word == "stop" then
        MapShot.Stop()
    else
        MapShot.Start()
    end
end, L["Maintainer tool: screenshot every zone and city map for road tracing; mapshot stop cancels"])
