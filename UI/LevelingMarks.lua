


































local ADDON_NAME, FGPS = ...

local L = FGPS.L
local type, ipairs, tonumber, tostring, format, pcall, sort, concat = type, ipairs, tonumber, tostring, string.format, pcall, table.sort, table.concat

local Marks = {
    frame = nil,
    lines = nil,
    live = false,
    source = nil,
    rows = nil,
    eventsBound = false,
    stats = { addon = ADDON_NAME, looks = 0, lastMs = 0, maxMs = 0 },
}
FGPS.UI = FGPS.UI or {}
FGPS.UI.LevelingMarks = Marks

Marks.WIDTH = 250
Marks.MAX_LINES = 12
Marks.EVENTS = { "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE",
                 "GOSSIP_CLOSED", "QUEST_FINISHED" }



local LIVE = {}
Marks.OWNER = LIVE

local function clock()
    if debugprofilestop then return debugprofilestop() end
    return 0
end


function Marks.Wanted()
    local db = FGPS.DB
    if db and db.Get and db:Get("quests.levelingMarks") == false then return false end
    local Leveling = FGPS.Leveling
    return Leveling and Leveling.Enabled and Leveling.Enabled() and true or false
end










local function passedOver(later, at, action)
    if action ~= "accept" or not later.stateAt then return false end
    local state, stepAction = later.stateAt(at)
    return state == "pass" and stepAction == "accept"
end




function Marks.OrderPlace(questID, action, ahead, later)
    questID = tonumber(questID)
    if not questID then return nil end
    for _, e in ipairs(ahead) do
        if e.questID == questID and e.action == action then return "now", e.position or 0 end
    end



    local at = action == "turnin" and later and later.turninAt and later.turninAt[questID] or nil
    at = at or (later and later.firstAt and later.firstAt[questID])
    if at and at >= (later.cursor or 1) and not (later.skipped and later.skipped[questID])
        and not passedOver(later, at, action) then
        return "later", at
    end
    return nil
end

local function lower(s) return type(s) == "string" and s:lower() or nil end










function Marks.Judge(offered, handedBack, ahead, later)
    ahead = ahead or {}
    local byTitle = nil
    local Leveling = FGPS.Leveling
    local function idOf(q)
        if tonumber(q.questID) and tonumber(q.questID) > 0 then return tonumber(q.questID) end
        local t = lower(q.title)
        if not t then return nil end
        if not byTitle then
            byTitle = {}
            for _, e in ipairs(ahead) do
                local name = Leveling and Leveling.Title and lower(Leveling.Title(e.questID))
                if name and not byTitle[name] then byTitle[name] = e.questID end
            end
        end
        return byTitle[t]
    end
    local rows = {}
    local function add(q, kind, action)
        local id = idOf(q)
        local place, rank = Marks.OrderPlace(id, action, ahead, later)
        local title = q.title
        if (type(title) ~= "string" or title == "") and id and Leveling and Leveling.Title then title = Leveling.Title(id) end
        rows[#rows + 1] = { questID = id, title = title or "?", kind = kind, place = place,
                            rank = place == "now" and rank or (place == "later" and 100000 + rank) or 1000000 + #rows,
                            next = false }
    end
    for _, q in ipairs(offered or {}) do add(q, "take", "accept") end
    for _, q in ipairs(handedBack or {}) do
        if q.isComplete ~= false then add(q, "handin", "turnin") end
    end
    sort(rows, function(a, b) return a.rank < b.rank end)
    if rows[1] and rows[1].place == "now" then rows[1].next = true end
    return rows
end



local turnins = { seq = nil, at = nil }
local function turninAt(Leveling)
    local seq, decode = Leveling.seq, Leveling.Decode
    if type(seq) ~= "table" or type(decode) ~= "function" then return nil end
    if turnins.seq == seq then return turnins.at end
    local at = {}
    for i = 1, #seq do
        local q, a = decode(seq[i])
        if a == 2 and not at[q] then at[q] = i end
    end
    turnins.seq, turnins.at = seq, at
    return at
end



local function stateAt(position)
    local Leveling = FGPS.Leveling
    if not (Leveling and type(Leveling.StateAt) == "function") then return nil end
    local ok, state, action = pcall(Leveling.StateAt, position)
    if ok then return state, action end
    return nil
end


local function orderNow()
    local Leveling = FGPS.Leveling
    if not Leveling then return {}, nil end
    local ok, ahead = pcall(Leveling.Ahead)
    if not ok or type(ahead) ~= "table" then ahead = {} end
    local later = nil
    local okS, status = pcall(Leveling.Status)
    if okS and type(status) == "table" then
        later = { firstAt = Leveling.firstAt, turninAt = turninAt(Leveling), cursor = status.cursor, skipped = status.skipped,
                  stateAt = stateAt }
    end
    return ahead, later
end





local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c, d, e
end


function Marks.ReadGossip()
    local G = type(C_GossipInfo) == "table" and C_GossipInfo or nil
    local offered, back = {}, {}
    if not G then return offered, back end
    local list = call(G.GetAvailableQuests)
    for _, q in ipairs(type(list) == "table" and list or {}) do
        if type(q) == "table" then offered[#offered + 1] = { questID = q.questID, title = q.title } end
    end
    list = call(G.GetActiveQuests)
    for _, q in ipairs(type(list) == "table" and list or {}) do
        if type(q) == "table" then back[#back + 1] = { questID = q.questID, title = q.title, isComplete = q.isComplete } end
    end
    return offered, back
end


function Marks.ReadGreeting()
    local offered, back = {}, {}
    local n = tonumber((call(GetNumAvailableQuests))) or 0
    for i = 1, n do
        local title = call(GetAvailableTitle, i)
        local _, _, _, _, questID = call(GetAvailableQuestInfo, i)
        offered[#offered + 1] = { questID = tonumber(questID), title = title }
    end
    n = tonumber((call(GetNumActiveQuests))) or 0
    for i = 1, n do
        local title, isComplete = call(GetActiveTitle, i)
        local questID = call(GetActiveQuestID, i)
        questID = tonumber(questID)

        if isComplete == nil and questID and type(C_QuestLog) == "table" then
            isComplete = call(C_QuestLog.IsComplete, questID)
        end
        back[#back + 1] = { questID = tonumber(questID), title = title, isComplete = isComplete }
    end
    return offered, back
end


function Marks.ReadSingle(source)
    local questID = tonumber((call(GetQuestID)))
    local title = call(GetTitleText)
    local q = { questID = questID and questID > 0 and questID or nil, title = title }
    if source == "detail" then return { q }, {} end


    if source == "progress" then
        local done = false
        if q.questID and type(C_QuestLog) == "table" and type(C_QuestLog.IsComplete) == "function" then
            done = call(C_QuestLog.IsComplete, q.questID) == true
        end
        q.isComplete = done
    end
    return {}, { q }
end





local function hostFor(source)
    if source == "gossip" then return type(GossipFrame) == "table" and GossipFrame or nil end
    return type(QuestFrame) == "table" and QuestFrame or nil
end

local function ensureFrame()
    if Marks.frame then return Marks.frame end
    local Look = FGPS.UI.Look
    local frame
    if Look and Look.CreateGround then frame = Look.CreateGround("Frame", UIParent, 12) else frame = CreateFrame("Frame", nil, UIParent) end
    frame:SetWidth(Marks.WIDTH)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:Hide()
    local font = Look and Look.Font or function() return "GameFontNormal" end
    local title = frame:CreateFontString(nil, "OVERLAY", font("header"))
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -9)
    title:SetText(L["Optimized Leveling"])
    if Look and Look.Color then title:SetTextColor(Look.Color("header")) end
    frame.title = title
    Marks.lines = {}
    for i = 1, Marks.MAX_LINES do
        local line = frame:CreateFontString(nil, "OVERLAY", font("rowSmall"))
        line:SetPoint("TOPLEFT", i == 1 and title or Marks.lines[i - 1], "BOTTOMLEFT", 0, -3)
        line:SetWidth(Marks.WIDTH - 20)
        if line.SetJustifyH then line:SetJustifyH("LEFT") end
        line:Hide()
        Marks.lines[i] = line
    end
    frame:SetScript("OnEnter", function(self)
        if type(GameTooltip) ~= "table" then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Optimized Leveling"])
        GameTooltip:AddLine(L["Cabbie marks the quests your Optimized Leveling order wants from this quest giver. Taking and turning in stays yours."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() if type(GameTooltip) == "table" then GameTooltip:Hide() end end)
    Marks.frame = frame
    return frame
end


function Marks.Lines(rows)
    local out, others = {}, {}
    for _, r in ipairs(rows) do
        if r.place then
            local label = r.kind == "handin" and L["Turn in"] or L["Take"]
            local text = format("%s: %s", label, tostring(r.title))
            if r.next then
                text = format(L["%s - next"], text)
            elseif r.place == "later" then
                text = format(L["%s - later in the order"], text)
            end
            out[#out + 1] = { text = text, role = r.next and "match" or (r.place == "now" and "current" or "later"), row = r }
        else
            others[#others + 1] = tostring(r.title)
        end
    end
    if #others > 0 then
        out[#out + 1] = { text = format(L["Not in your order: %s"], concat(others, ", ")), role = "grey" }
    end
    return out
end

local function hide()
    Marks.source, Marks.rows = nil, nil
    if Marks.frame then Marks.frame:Hide() end
end


function Marks.Show(source)
    if not Marks.Wanted() then return hide() end
    local t0 = clock()
    local offered, back
    if source == "gossip" then
        offered, back = Marks.ReadGossip()
    elseif source == "greeting" then
        offered, back = Marks.ReadGreeting()
    else
        offered, back = Marks.ReadSingle(source)
    end
    local ahead, later = orderNow()
    local rows = Marks.Judge(offered, back, ahead, later)
    local stats = Marks.stats
    stats.looks = stats.looks + 1
    Marks.source, Marks.rows = source, rows
    local lines = Marks.Lines(rows)
    local host = hostFor(source)
    if #lines == 0 or not host then
        if Marks.frame then Marks.frame:Hide() end
    else
        local frame = ensureFrame()
        local Look = FGPS.UI.Look
        local height = 9 + (frame.title.GetStringHeight and frame.title:GetStringHeight() or 14) + 10
        for i, line in ipairs(Marks.lines) do
            local l = lines[i]
            if l and i == Marks.MAX_LINES and #lines > Marks.MAX_LINES then
                l = { text = format(L["and %d more"], #lines - Marks.MAX_LINES + 1), role = "grey" }
            end
            if l then
                line:SetText(l.text)
                if Look and Look.Color then line:SetTextColor(Look.Color(l.role)) end
                line:Show()
                height = height + (line.GetStringHeight and line:GetStringHeight() or 12) + 3
            else
                line:SetText("")
                line:Hide()
            end
        end
        frame:SetHeight(height)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", host, "TOPRIGHT", 4, -2)
        frame:Show()
    end
    stats.lastMs = clock() - t0
    if stats.lastMs > stats.maxMs then stats.maxMs = stats.lastMs end
    return rows
end

local SOURCE = { GOSSIP_SHOW = "gossip", QUEST_GREETING = "greeting", QUEST_DETAIL = "detail",
                 QUEST_PROGRESS = "progress", QUEST_COMPLETE = "complete" }

local function onGiverEvent(event)
    if event == "GOSSIP_CLOSED" then
        if Marks.source == "gossip" then hide() end
        return
    end
    if event == "QUEST_FINISHED" then
        if Marks.source and Marks.source ~= "gossip" then hide() end
        return
    end
    local source = SOURCE[event]
    if source then Marks.Show(source) end
end



local function onLevelingRefreshed()
    if Marks.source == "gossip" or Marks.source == "greeting" then Marks.Show(Marks.source) end
end

function Marks:Apply()
    if Marks.Wanted() then
        if not self.live then
            self.live = true
            local Events = FGPS.Events
            for _, event in ipairs(Marks.EVENTS) do Events:RegisterWoW(event, onGiverEvent, LIVE) end
            Events:Register("LEVELING_REFRESHED", onLevelingRefreshed, LIVE)
        end
    elseif self.live then
        self.live = false
        FGPS.Events:UnregisterAllByOwner(LIVE)
        hide()
    end
end

function Marks:Init()
    if self.eventsBound then return end
    self.eventsBound = true
    FGPS.Events:Register("SETTINGS_CHANGED", function(_, key)
        if key == "*" or key == "quests.levelingMarks" or key == "quests.leveling" or key == "quests.enabled" then
            Marks:Apply()
        end
    end, self)
    self:Apply()
end
