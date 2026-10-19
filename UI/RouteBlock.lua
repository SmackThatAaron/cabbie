



local ADDON_NAME, FGPS = ...

local L = FGPS.L
local type, ipairs, floor, format = type, ipairs, math.floor, string.format

local RouteBlock = {
    frame = nil,
    dragging = false,
    dragged = false,
    combat = false,
    measured = false,
    remeasure = nil,
    clickable = false,
    noteUnder = nil,
    eventsBound = false,
}
FGPS.UI.RouteBlock = RouteBlock

RouteBlock.WIDTH = 235
RouteBlock.GAP = 12
RouteBlock.FALLBACK_X = -270
RouteBlock.FALLBACK_Y = -230
RouteBlock.MAX_ROWS = 3
RouteBlock.HEADER_HEIGHT = 18
RouteBlock.LINE_GAP = 2
RouteBlock.INDENT = 12




local function enabled()
    if not FGPS.UI.Guide.Enabled() then return false end
    local DB = FGPS.DB
    if not (DB and DB.Get) then return true end
    if RouteBlock.combat and DB:Get("combatMode") == "hide_all" then return false end
    return DB:Get("routeBlock.enabled") ~= false
end



function RouteBlock.Wanted()
    return enabled()
end




local function trackerFrame()
    local tracker = ObjectiveTrackerFrame
    if type(tracker) ~= "table" or not tracker.GetWidth then return nil end
    if tracker.GetLeft and not tracker:GetLeft() then return nil end
    return tracker
end






local function savedPlace()
    local account = FGPS.DB and FGPS.DB.account
    local saved = account and account.routeBlockPlace
    if type(saved) == "table" and type(saved.x) == "number" and type(saved.y) == "number" then return saved end
    return nil
end


local function fontString(parent, role, oneLine)
    local text = parent:CreateFontString(nil, "OVERLAY", FGPS.UI.Look.Font(role))
    if text.SetJustifyH then text:SetJustifyH("LEFT") end
    if text.SetWordWrap then text:SetWordWrap(not oneLine) end
    if oneLine and text.SetMaxLines then text:SetMaxLines(1) end
    return text
end

local function createFrame()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("LOW")
    frame:SetSize(RouteBlock.WIDTH, 60)
    frame:Hide()



    frame:SetScript("OnHide", function(self)
        if self.StopMovingOrSizing then self:StopMovingOrSizing() end
        if RouteBlock.dragging then
            RouteBlock.dragging = false
            RouteBlock.Place()
        end
    end)


    local header = CreateFrame("Button", nil, frame)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    header:SetHeight(RouteBlock.HEADER_HEIGHT)
    frame.Header = header
    frame.HeaderText = fontString(header, "header", true)
    frame.HeaderText:SetPoint("LEFT", header, "LEFT", 0, 0)
    frame.HeaderText:SetPoint("RIGHT", header, "RIGHT", 0, 0)




    frame.Rule = frame:CreateTexture(nil, "ARTWORK")
    frame.Rule:SetColorTexture(0.85, 0.65, 0.08, 0.9)
    frame.Rule:SetHeight(1)
    frame.Rule:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    frame.Rule:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -2)




    frame.Title = fontString(frame, "title")
    frame.Title:SetPoint("TOPLEFT", frame.Rule, "BOTTOMLEFT", 0, -6)

    frame.Rows = {}
    local above = frame.Title
    for i = 1, RouteBlock.MAX_ROWS do
        local row = fontString(frame, "line")
        row:SetPoint("TOPLEFT", above, "BOTTOMLEFT", i == 1 and RouteBlock.INDENT or 0, -RouteBlock.LINE_GAP)
        frame.Rows[i] = row
        above = row
    end



    frame.Note = fontString(frame, "line")
    frame.Note:Hide()





    frame.Body = CreateFrame("Button", nil, frame)
    frame.Body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    frame.Body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.Body:Hide()
    return frame
end



local function fitWidth(frame)
    local tracker = trackerFrame()
    local width = tracker and tracker:GetWidth() or 0


    if width > 0 and tracker.GetEffectiveScale and UIParent.GetEffectiveScale then
        local own, screen = tracker:GetEffectiveScale(), UIParent:GetEffectiveScale()
        if type(own) == "number" and own > 0 and type(screen) == "number" and screen > 0 then
            width = width * own / screen
        end
    end
    if width <= 0 then width = RouteBlock.WIDTH end
    frame:SetWidth(width)
    frame.Title:SetWidth(width)
    for _, row in ipairs(frame.Rows) do row:SetWidth(width - RouteBlock.INDENT) end
    frame.Note:SetWidth(width - RouteBlock.INDENT)
    RouteBlock.measured = false
    return tracker
end

local function headerText(header)
    local Look = FGPS.UI.Look
    local text = L["Route"]
    local clock = header and Look.Clock(header.seconds) or nil
    local distance = header and type(header.yards) == "number" and Look.Distance(header.yards) or nil
    if clock and distance then return text .. "  " .. clock .. " \194\183 " .. distance end
    if clock or distance then return text .. "  " .. (clock or distance) end
    return text
end



local function openMark()
    local r, g, b = FGPS.UI.Look.Color("grey")
    return format(" |cff%02x%02x%02x%s|r", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5), L["(open ground)"])
end

local NO_ROWS = {}













local function paint(model)
    local frame = RouteBlock.frame
    if not frame then return end
    if not (type(model) == "table" and model.visible and enabled()) then
        if RouteBlock.remeasure then
            RouteBlock.remeasure:Cancel()
            RouteBlock.remeasure = nil
        end
        frame:Hide()
        return
    end
    local Look = FGPS.UI.Look




    local appearing = not frame:IsShown()
    if appearing then
        Look.ForgetLine(frame.HeaderText)
        Look.ForgetLine(frame.Title)
        for _, row in ipairs(frame.Rows) do Look.ForgetLine(row) end
        Look.ForgetLine(frame.Note)
        if savedPlace() then fitWidth(frame) else RouteBlock.Place() end
    end
    Look.SetLine(frame.HeaderText, headerText(model.header), Look.Color("header"))
    local changed = Look.SetLine(frame.Title, model.title or "", Look.Color("title"))
    local rows = model.rows or NO_ROWS
    for i, row in ipairs(frame.Rows) do
        local entry = rows[i]
        if entry then
            if Look.SetLine(row, "- " .. entry.text .. (entry.open and openMark() or ""),
                    Look.Color(entry.grey and "grey" or (entry.current and "current" or "later"))) then
                changed = true
                row:Show()
            end
        elseif Look.SetLine(row, "") then
            changed = true
            row:Hide()
        end
    end




    local note = frame.Note
    if model.noFlights then
        local under = #rows < #frame.Rows and #rows or #frame.Rows
        if RouteBlock.noteUnder ~= under then
            RouteBlock.noteUnder = under
            note:ClearAllPoints()
            if under > 0 then
                note:SetPoint("TOPLEFT", frame.Rows[under], "BOTTOMLEFT", 0, -RouteBlock.LINE_GAP)
            else
                note:SetPoint("TOPLEFT", frame.Title, "BOTTOMLEFT", RouteBlock.INDENT, -RouteBlock.LINE_GAP)
            end
        end
        local text = model.noFlightsIn and format(L["No flights in %s yet: visit a flight master there."], model.noFlightsIn)
            or L["No flights yet: visit a flight master."]
        if Look.SetLine(note, text, Look.Color("grey")) then
            changed = true
            note:Show()
        end
    elseif Look.SetLine(note, "") then
        changed = true
        note:Hide()
    end


    local clickable = model.stopped == true
    if RouteBlock.clickable ~= clickable then
        RouteBlock.clickable = clickable
        if clickable then frame.Body:Show() else frame.Body:Hide() end
    end
    if changed or not RouteBlock.measured then
        local height = RouteBlock.HEADER_HEIGHT + 9 + frame.Title:GetStringHeight()
        for i, row in ipairs(frame.Rows) do
            if rows[i] then height = height + RouteBlock.LINE_GAP + row:GetStringHeight() end
        end
        if model.noFlights then height = height + RouteBlock.LINE_GAP + note:GetStringHeight() end
        frame:SetHeight(height)
        RouteBlock.measured = true
    end
    if appearing then
        frame:Show()




        RouteBlock.measured = false



        if RouteBlock.remeasure then RouteBlock.remeasure:Cancel() end
        RouteBlock.remeasure = C_Timer and C_Timer.NewTimer and C_Timer.NewTimer(0, function()
            RouteBlock.remeasure = nil
            if frame:IsShown() and not RouteBlock.measured then RouteBlock.Paint(model) end
        end) or nil
    end
end



function RouteBlock.Paint(model)
    local Perf = FGPS.Perf
    if Perf then Perf:Begin("routeBlock") end
    paint(model)
    if Perf then Perf:End("routeBlock") end
end




local function roomOnTheLeft(tracker, width)
    local left = tracker.GetLeft and tracker:GetLeft()
    if type(left) ~= "number" then return true end
    if tracker.GetEffectiveScale and UIParent.GetEffectiveScale then
        local own, screen = tracker:GetEffectiveScale(), UIParent:GetEffectiveScale()
        if type(own) == "number" and type(screen) == "number" and screen > 0 then left = left * own / screen end
    end
    local screenLeft = UIParent.GetLeft and UIParent:GetLeft() or 0
    return left - (type(screenLeft) == "number" and screenLeft or 0) >= width + RouteBlock.GAP
end






function RouteBlock.Place()
    local frame = RouteBlock.frame
    if not frame then return end
    local saved = savedPlace()
    local tracker = fitWidth(frame)
    frame:ClearAllPoints()
    if saved then
        local corner = saved.right == true and "TOPRIGHT" or "TOPLEFT"
        frame:SetPoint(corner, UIParent, corner, saved.x, saved.y)
    elseif tracker and roomOnTheLeft(tracker, frame:GetWidth()) then
        frame:SetPoint("TOPRIGHT", tracker, "TOPLEFT", -RouteBlock.GAP, 0)
    elseif tracker then
        frame:SetPoint("TOPLEFT", tracker, "TOPRIGHT", RouteBlock.GAP, 0)
    else
        frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", RouteBlock.FALLBACK_X, RouteBlock.FALLBACK_Y)
    end
end




function RouteBlock.SavePlace()
    local frame = RouteBlock.frame
    local account = FGPS.DB and FGPS.DB.account
    if not (frame and account and frame.GetLeft and frame.GetTop and UIParent.GetTop) then return false end
    local left, top, screenTop = frame:GetLeft(), frame:GetTop(), UIParent:GetTop()
    if not (left and top and screenTop) then return false end
    local place = { x = left - (UIParent.GetLeft and UIParent:GetLeft() or 0), y = top - screenTop }
    local right = frame.GetRight and frame:GetRight()
    local screenRight = UIParent.GetRight and UIParent:GetRight()
    if right and screenRight and screenRight - right < place.x then
        place.x, place.right = right - screenRight, true
    end
    account.routeBlockPlace = place
    RouteBlock.Place()
    return true
end

function RouteBlock.ResetPlace()
    local account = FGPS.DB and FGPS.DB.account
    if account then account.routeBlockPlace = nil end
    RouteBlock.Place()
end

local function enableDrag(frame)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame.Header:RegisterForDrag("LeftButton")



    frame.Header:SetScript("OnMouseDown", function()
        RouteBlock.dragged = false
    end)
    frame.Header:SetScript("OnDragStart", function()
        RouteBlock.dragging, RouteBlock.dragged = true, true
        frame:StartMoving()
    end)


    frame.Header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        if not RouteBlock.dragging then return end
        RouteBlock.dragging = false
        RouteBlock.SavePlace()
    end)
end


local function repaint()
    local Guide = FGPS.UI.Guide
    RouteBlock.Paint(Guide and Guide.Get and Guide.Get() or nil)
end


local function inFight()
    return InCombatLockdown ~= nil and InCombatLockdown() == true
end

function RouteBlock:Init()
    if not self.frame then
        self.frame = createFrame()
        enableDrag(self.frame)
        RouteBlock.Place()
    end

    self.combat = inFight()
    if self.eventsBound then return end
    local Events = FGPS.Events
    if not Events then return end
    Events:Register("GUIDE_CHANGED", function(_, model) RouteBlock.Paint(model) end, self)
    Events:Register("COMBAT_STATE", function(_, inCombat)
        RouteBlock.combat = inCombat == true
        repaint()
    end, self)
    Events:Register("SETTINGS_CHANGED", function(_, key)
        if key == "*" or key == "routeBlock.enabled" or key == "combatMode" then repaint() end
    end, self)




    Events:Register("WORLD_ENTERED", function()
        RouteBlock.Place()
        RouteBlock.combat = inFight()
        repaint()
    end, self)

    Events:Register("POSITIONS_RESET", function(_, key)
        if key == nil then RouteBlock.ResetPlace() end
    end, self)
    self.eventsBound = true
end
