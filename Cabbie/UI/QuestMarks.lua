





























local ADDON_NAME, FGPS = ...

local L = FGPS.L
local type, ipairs, tonumber, tostring, format, pcall = type, ipairs, tonumber, tostring, string.format, pcall

local QuestMarks = {
    provider = nil,
    layer = nil,
    pinPool = nil,
    pins = nil,
    minimapPool = nil,
    minimapActive = false,
    attached = false,
    live = false,
    timer = nil,
    hovered = nil,
    clickHandler = nil,
    lastDrawMapID = nil,
    lastCount = 0,
    lastMinimapMapID = nil,
    lastMinimapCount = 0,
    verdicts = {},
    logCount = nil,
}
FGPS.UI.QuestMarks = QuestMarks

QuestMarks.REF = "CabbieQuestMarks"
local PIN_SIZE = 18
local MINIMAP_PIN_SIZE = 12
local REDRAW_SECONDS = 1
local CLICK_PRIORITY = 96
local SRC_ITEM_DROP = 3
local ZONE_MAP_TYPE = 3



QuestMarks.EVENTS = { "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP",
                      "SKILL_LINES_CHANGED", "ZONE_CHANGED_NEW_AREA" }


local LIVE = {}

local function questSettings()
    local s = FGPS.DB and FGPS.DB.settings or nil
    return type(s) == "table" and type(s.quests) == "table" and s.quests or nil
end

local function questData()
    local QuestData = FGPS.QuestData
    if QuestData and QuestData.Available and QuestData.Available() then return QuestData end
    return nil
end



function QuestMarks.Wanted()
    local quests = questSettings()
    if quests and (quests.enabled == false or quests.pickupMarks == false) then return false end
    if FGPS.Perf and FGPS.Perf.guidanceEnabled == false then return false end
    return questData() ~= nil
end




local function trivialRange()
    if type(UnitQuestTrivialLevelRange) ~= "function" then return nil end
    local ok, range = pcall(UnitQuestTrivialLevelRange, "player")
    if ok and type(range) == "number" and not (issecretvalue and issecretvalue(range)) then return range end
    return nil
end



local function pinnedByQuestMap(onMinimap)
    local QuestMap, quests = FGPS.UI.QuestMap, questSettings()
    if not (QuestMap and QuestMap.focus) then return nil end
    if quests and quests[onMinimap and "minimapPins" or "mapPins"] == false then return nil end
    return QuestMap.focus
end


local function judge(QuestData, questID, playerLevel, range)
    local answer, sentence, code = QuestData.CanTake(questID)
    local note
    if answer == "unknown" and code == "forever_incomplete" then
        note = sentence
    elseif answer ~= "yes" then
        return false
    end
    local info = QuestData.Lookup(questID)
    local level = info and tonumber(info.level) or nil
    if level and level <= 0 then level = nil end
    if level and playerLevel and range and playerLevel - level > range then return false end
    return { level = level, mark = QuestData.Mark(questID), note = note }
end






function QuestMarks.MarksFor(uiMapID, onMinimap, verdicts)
    uiMapID = tonumber(uiMapID)
    if not uiMapID or not QuestMarks.Wanted() then return {} end
    local QuestData = FGPS.QuestData
    local pinned = pinnedByQuestMap(onMinimap)
    local playerLevel, range = QuestData.PlayerLevel(), trivialRange()
    local out = {}
    verdicts = verdicts or {}
    for _, entry in ipairs(QuestData.GiversOnMap(uiMapID)) do
        local id, pos = entry.id, entry.position
        if pos and not pos.interior and pos.src ~= SRC_ITEM_DROP and id ~= pinned then
            local verdict = verdicts[id]
            if verdict == nil then
                verdict = judge(QuestData, id, playerLevel, range)
                verdicts[id] = verdict
            end
            if verdict then
                out[#out + 1] = { questID = id, giver = entry.giver, inst = pos.inst, x = pos.x, y = pos.y, map = pos.map,
                                  level = verdict.level, mark = verdict.mark, note = verdict.note }
            end
        end
    end
    return out
end



function QuestMarks.TooltipLines(mark, onMap)
    local QuestData = FGPS.QuestData
    local lines = {}
    if not (mark and QuestData) then return lines end
    lines[1] = { text = QuestData.Title(mark.questID) or format(L["Quest %d"], mark.questID) }
    if mark.level then lines[#lines + 1] = { text = format(L["Level %d"], mark.level), r = 1, g = 1, b = 1 } end
    lines[#lines + 1] = { text = QuestData.MarkText(mark.mark), r = 1, g = 1, b = 1 }
    if type(mark.note) == "string" and mark.note ~= "" then
        lines[#lines + 1] = { text = (mark.note:gsub("^%l", string.upper)) .. ".", r = 1, g = 1, b = 1 }
    end
    if onMap then
        local Look = FGPS.UI.Look
        local r, g, b = 0.5, 0.5, 0.5
        if Look and Look.Color then r, g, b = Look.Color("grey") end
        lines[#lines + 1] = { text = L["Shift-click: go there"], r = r, g = g, b = b }
    end
    return lines
end

local function showTooltip(owner, onMap)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    for i, line in ipairs(QuestMarks.TooltipLines(owner.fgpsMark, onMap)) do
        if i == 1 then GameTooltip:AddLine(line.text) else GameTooltip:AddLine(line.text, line.r, line.g, line.b, true) end
    end
    GameTooltip:Show()
end

local function hideTooltip(owner)
    if GameTooltip and (not GameTooltip.IsOwned or GameTooltip:IsOwned(owner)) then GameTooltip:Hide() end
end








function QuestMarks.GoTo(questID, giver)
    local QuestData = questData()
    if not QuestData then return false end
    local ok, dest = pcall(QuestData.DestinationFor, questID, "giver", giver, true)
    if not ok then
        FGPS.Log:Error("A pick-up mark's destination failed: %s", tostring(dest))
        dest = nil
    end
    if not dest then
        local Guide, WorldMap = FGPS.UI.Guide, FGPS.UI.WorldMap
        if Guide and Guide.Say then Guide.Say(L["That spot cannot be reached"], WorldMap and WorldMap.GO_REFUSED_SECONDS) end
        return false
    end
    local Go = FGPS.UI.Go
    return Go ~= nil and Go.Start ~= nil and Go.Start(dest) ~= false
end



function QuestMarks.OnCanvasClick(_, button)
    local pin = QuestMarks.hovered
    if not (QuestMarks.live and pin and pin.fgpsMark and pin:IsShown()) then return false end
    local WorldMap = FGPS.UI.WorldMap
    if not (WorldMap and WorldMap.IsGoClick and WorldMap.IsGoClick(button)) then return false end
    if pin.IsMouseOver and not pin:IsMouseOver() then return false end
    QuestMarks.GoTo(pin.fgpsMark.questID, pin.fgpsMark.giver)
    return true
end




local function resetPin(_, pin)
    if QuestMarks.hovered == pin then
        QuestMarks.hovered = nil
        hideTooltip(pin)
    end
    pin.fgpsMark, pin.fgpsQuestID, pin.fgpsGiver = nil, nil, nil
    pin.normalizedX, pin.normalizedY = nil, nil
    pin:Hide()
    pin:ClearAllPoints()
end

local function setupPin(pin)
    if pin.fgpsReady then return end
    pin.fgpsReady = true
    pin:SetSize(PIN_SIZE, PIN_SIZE)
    pin.art = pin:CreateTexture(nil, "ARTWORK")
    pin.art:SetPoint("CENTER", pin, "CENTER", 0, 0)
    local Look = FGPS.UI.Look
    if Look and Look.Icon then Look.Icon(pin.art, "pickup", PIN_SIZE) end

    pin:EnableMouse(true)
    if pin.SetMouseClickEnabled then pin:SetMouseClickEnabled(false) end
    pin:SetScript("OnEnter", function(self)
        QuestMarks.hovered = self
        showTooltip(self, true)
    end)
    pin:SetScript("OnLeave", function(self)
        if QuestMarks.hovered == self then QuestMarks.hovered = nil end
        hideTooltip(self)
    end)
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

function QuestMarks:ClearDrawing()
    if self.pinPool then self.pinPool:ReleaseAll() end
    self.lastCount, self.lastDrawMapID = 0, nil
end

function QuestMarks:OnScaleChanged()
    local map = WorldMapFrame
    local canvas = map and map.GetCanvas and map:GetCanvas()
    if not (canvas and self.pinPool) then return end
    local w, h, scale = canvas:GetWidth(), canvas:GetHeight(), canvasScale()
    for pin in self.pinPool:EnumerateActive() do
        if pin.normalizedX then placePin(pin, canvas, w, h, scale) end
    end
end

function QuestMarks:Redraw()
    local map = WorldMapFrame
    if not (map and self.layer) then return end
    local mapID = self.live and not (map.IsShown and not map:IsShown()) and map:GetMapID() or nil
    local marks = mapID and QuestMarks.MarksFor(mapID, false, self.verdicts) or nil
    self:ClearDrawing()
    if not marks or #marks == 0 then return end
    if not self.pinPool then
        if not CreateFramePool then return end
        self.pinPool = CreateFramePool("Frame", self.layer, nil, resetPin)
    end
    local Perf, Coords = FGPS.Perf, FGPS.Coords
    if Perf then Perf:Begin("questMarks") end
    local canvas = map:GetCanvas()
    local w, h, scale = canvas:GetWidth(), canvas:GetHeight(), canvasScale()
    local count = 0
    for _, mark in ipairs(marks) do
        local ok, id, mx, my = pcall(Coords.WorldToMap, mark.inst, mark.x, mark.y, mapID)
        if ok and id == mapID and mx and my and mx >= 0 and mx <= 1 and my >= 0 and my <= 1 then
            local pin = self.pinPool:Acquire()
            setupPin(pin)
            pin.fgpsMark, pin.fgpsQuestID, pin.fgpsGiver = mark, mark.questID, mark.giver
            pin.normalizedX, pin.normalizedY = mx, my
            placePin(pin, canvas, w, h, scale)
            pin:Show()
            count = count + 1
        end
    end
    self.lastCount, self.lastDrawMapID = count, mapID
    if Perf then Perf:End("questMarks") end
end






local function playerZone()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or type(mapID) ~= "number" or (issecretvalue and issecretvalue(mapID)) then return nil end
    for _ = 1, 4 do
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
        if type(info) ~= "table" or type(info.mapType) ~= "number" or info.mapType <= ZONE_MAP_TYPE or not info.parentMapID then break end
        mapID = info.parentMapID
    end
    return mapID
end

local function makeMinimapIcon()
    local icon = CreateFrame("Frame", nil, (_G and _G.Minimap) or UIParent)
    icon:SetSize(MINIMAP_PIN_SIZE, MINIMAP_PIN_SIZE)
    icon.art = icon:CreateTexture(nil, "ARTWORK")
    icon.art:SetPoint("CENTER", icon, "CENTER", 0, 0)
    local Look = FGPS.UI.Look
    if Look and Look.Icon then Look.Icon(icon.art, "pickup", MINIMAP_PIN_SIZE) end

    icon:EnableMouse(true)
    if icon.SetMouseClickEnabled then icon:SetMouseClickEnabled(false) end
    icon:SetScript("OnEnter", function(self) showTooltip(self, false) end)
    icon:SetScript("OnLeave", function(self) hideTooltip(self) end)
    icon:Hide()
    return icon
end

function QuestMarks:ClearMinimap()
    if self.pins and self.minimapActive then self.pins:RemoveAllMinimapIcons(QuestMarks.REF) end
    if self.minimapPool then self.minimapPool:ReleaseAll() end
    self.minimapActive = false
    self.lastMinimapCount, self.lastMinimapMapID = 0, nil
end

function QuestMarks:RefreshMinimap()
    local mapID = self.live and self.pins and playerZone() or nil
    local marks = mapID and QuestMarks.MarksFor(mapID, true, self.verdicts) or nil
    self:ClearMinimap()
    if not marks then return end
    self.lastMinimapMapID = mapID
    if #marks == 0 then return end
    if not self.minimapPool then
        if not CreateObjectPool then return end
        self.minimapPool = CreateObjectPool(makeMinimapIcon, function(_, icon)
            hideTooltip(icon)
            icon.fgpsMark = nil
            icon:Hide()
        end)
    end
    for _, mark in ipairs(marks) do
        local icon = self.minimapPool:Acquire()
        icon.fgpsMark = mark


        self.pins:AddMinimapIconWorld(QuestMarks.REF, icon, mark.inst, mark.x, mark.y, false)
    end
    self.minimapActive = true
    self.lastMinimapCount = #marks
end




function QuestMarks:RefreshAll()
    self:Redraw()
    self:RefreshMinimap()
end


local function schedule()
    if QuestMarks.timer or not QuestMarks.live then return end
    if not (C_Timer and C_Timer.NewTimer) then
        QuestMarks:RefreshAll()
        return
    end
    QuestMarks.timer = C_Timer.NewTimer(REDRAW_SECONDS, function()
        QuestMarks.timer = nil
        QuestMarks:RefreshAll()
    end)
end
QuestMarks.Schedule = schedule



local function onQuestEvent()
    QuestMarks.verdicts = {}
    schedule()
end




local function onQuestsUpdated(_, count)
    if count == QuestMarks.logCount then return end
    QuestMarks.logCount = count
    onQuestEvent()
end

local function goLive(self)
    self.live = true
    local Events = FGPS.Events
    for _, event in ipairs(QuestMarks.EVENTS) do Events:RegisterWoW(event, onQuestEvent, LIVE) end
    Events:Register("QUESTS_UPDATED", onQuestsUpdated, LIVE)
end



local function addClickHandler(self)
    local map = WorldMapFrame
    if self.attached and not self.clickHandler and map and map.AddCanvasClickHandler then
        local handler = function(canvas, button) return QuestMarks.OnCanvasClick(canvas, button) end
        local ok, err = pcall(map.AddCanvasClickHandler, map, handler, CLICK_PRIORITY)
        if ok then
            self.clickHandler = handler
        else
            FGPS.Log:Error("The pick-up marks' click handler could not be added: %s", tostring(err))
        end
    end
end

local function goIdle(self)
    self.live = false
    FGPS.Events:UnregisterAllByOwner(LIVE)
    if self.timer then
        self.timer:Cancel()
        self.timer = nil
    end


    local map = WorldMapFrame
    if self.clickHandler and map and map.RemoveCanvasClickHandler
        and pcall(map.RemoveCanvasClickHandler, map, self.clickHandler, CLICK_PRIORITY) then
        self.clickHandler = nil
    end
    self.verdicts, self.logCount = {}, nil
    self:ClearDrawing()
    self:ClearMinimap()
end



function QuestMarks:Apply()
    if QuestMarks.Wanted() then
        if not self.live then goLive(self) end
        addClickHandler(self)
        onQuestEvent()
    elseif self.live or self.minimapActive or self.lastCount > 0 then
        goIdle(self)
    end
end




local function createProvider()
    local base = MapCanvasDataProviderMixin or {}
    local provider = CreateFromMixins(base)
    function provider:OnAdded(owningMap)
        if base.OnAdded then base.OnAdded(self, owningMap) else self.owningMap = owningMap end
        if not QuestMarks.layer then
            local canvas = owningMap:GetCanvas()


            local WorldMap, QuestMap = FGPS.UI.WorldMap, FGPS.UI.QuestMap
            local layer = CreateFrame("Frame", nil, (WorldMap and WorldMap.pinLayer) or canvas)
            layer:SetAllPoints(canvas)
            local level = (QuestMap and QuestMap.PinLayerLevel) and QuestMap.PinLayerLevel(canvas:GetFrameLevel())
                or ((canvas:GetFrameLevel() or 1) + 2)
            layer:SetFrameLevel(level)
            layer:EnableMouse(false)
            QuestMarks.layer = layer
        end
    end
    function provider:OnRemoved(owningMap)
        QuestMarks:ClearDrawing()
        if base.OnRemoved then pcall(base.OnRemoved, self, owningMap) else self.owningMap = nil end
    end
    function provider:RemoveAllData() QuestMarks:ClearDrawing() end
    function provider:RefreshAllData() QuestMarks:Redraw() end
    function provider:OnMapChanged() QuestMarks:Redraw() end
    function provider:OnShow() QuestMarks:Redraw() end
    function provider:OnHide() QuestMarks:ClearDrawing() end
    function provider:OnCanvasScaleChanged() QuestMarks:OnScaleChanged() end
    function provider:OnCanvasSizeChanged() QuestMarks:Redraw() end
    return provider
end

function QuestMarks:Attach()
    if self.attached then return true end
    local map = WorldMapFrame
    if not map or not map.AddDataProvider or not CreateFromMixins then return false end
    self.provider = self.provider or createProvider()
    local ok, err = pcall(map.AddDataProvider, map, self.provider)
    if not ok then
        FGPS.Log:Error("Pick-up marks provider could not be added: %s", tostring(err))
        return false
    end
    self.attached = true
    return true
end

local function onReady()
    QuestMarks:Attach()
    QuestMarks:Apply()
end

function QuestMarks:Init()
    if LibStub and not self.pins then
        self.pins = LibStub("HereBeDragons-Pins-2.0", true)
        if not self.pins then FGPS.Log:Warn("HereBeDragons-Pins-2.0 not found; pick-up marks on the minimap are disabled") end
    end
    if FGPS.ready then onReady() end
    if self.eventsBound then return end
    self.eventsBound = true
    local Events = FGPS.Events


    Events:Register("ADDON_READY", onReady, self)
    if not WorldMapFrame then
        Events:RegisterWoW("ADDON_LOADED", function(_, name)
            if name == "Blizzard_WorldMap" and FGPS.ready then onReady() end
        end, self)
    end
    Events:Register("SETTINGS_CHANGED", function(_, key)
        if key == "*" or key == "quests.pickupMarks" or key == "quests.enabled" or key == "perf.guidanceEnabled" then
            QuestMarks:Apply()
        elseif key == "quests.mapPins" or key == "quests.minimapPins" then
            schedule()
        end
    end, self)
end
