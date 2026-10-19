






















local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local Events = FGPS.Events
local sqrt, format, type, pairs, ipairs, tonumber, tostring = math.sqrt, string.format, type, pairs, ipairs, tonumber, tostring

local Social = {
    FOLLOW_HZ = 1,
    FOLLOW_MOVE_YARDS = 40,
    FOLLOW_LOST_TICKS = 5,
    OFFER_TTL = 180,
    GRAVEYARD_TYPE = 16,
    NO_CORPSE_HOLD = 4,
    FOLLOW_ENDED_HOLD = 6,
    PREFIX = "CBB",
    VERSION = 1,
    MAX_PARTY = 4,
    MAX_RAID = 40,
    following = nil,
    ticker = nil,
    corpse = nil,
    corpseOffered = false,
    lifeLook = nil,
    offer = nil,
}
FGPS.Social = Social

local function now() return GetTime and GetTime() or 0 end

local function dist(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return sqrt(dx * dx + dy * dy)
end

local function playerPos()
    local C = FGPS.Coords
    if C and C.PlayerPos then
        local ok, pos = pcall(C.PlayerPos)
        if ok then return pos end
    end
    local D = FGPS.Destinations
    if D and D.PlayerPos then return D.PlayerPos() end
    return nil
end

local function mapToWorld(uiMapID, mx, my)
    local C = FGPS.Coords
    if C and C.MapToWorld then
        local ok, inst, x, y = pcall(C.MapToWorld, uiMapID, mx, my)
        if ok and inst then return inst, x, y end
    end
    local D = FGPS.Destinations
    if D and D.MapToWorld then return D.MapToWorld(uiMapID, mx, my) end
    return nil
end

local function worldToMap(inst, x, y)
    local C = FGPS.Coords
    if C and C.WorldToMap then
        local ok, uiMapID, mx, my = pcall(C.WorldToMap, inst, x, y)
        if ok and uiMapID then return uiMapID, mx, my end
    end
    return nil
end

local function zoneName(uiMapID)
    local D = FGPS.Destinations
    if D and D.MapName and uiMapID then return D.MapName(uiMapID) end
    return nil
end

local function navigator()
    return FGPS.Navigator
end


local function plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end




function Social.IsDead()
    if not UnitIsDeadOrGhost then return false end
    local ok, dead = pcall(UnitIsDeadOrGhost, "player")
    return (ok and plain(dead)) and true or false
end



function Social.IsGhost()
    if type(UnitIsGhost) ~= "function" then return false end
    local ok, ghost = pcall(UnitIsGhost, "player")
    return (ok and plain(ghost)) and true or false
end



function Social.CorpsePosition()
    if not (C_DeathInfo and C_DeathInfo.GetCorpseMapPosition) then return nil end
    local pos = playerPos()
    local uiMapID = pos and pos.map or nil
    if not uiMapID and C_Map and C_Map.GetBestMapForUnit then
        local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
        if ok then uiMapID = plain(id) end
    end
    if type(uiMapID) ~= "number" then return nil end
    local ok, vector = pcall(C_DeathInfo.GetCorpseMapPosition, uiMapID)
    if not ok or type(vector) ~= "table" then return nil end
    local mx, my = plain(vector.x), plain(vector.y)
    if type(mx) ~= "number" or type(my) ~= "number" then return nil end
    if mx == 0 and my == 0 then return nil end
    local inst, x, y = mapToWorld(uiMapID, mx, my)
    if not inst then return nil end
    return { inst = inst, x = x, y = y, map = uiMapID, mx = mx, my = my }
end




function Social.NearestGraveyard(pos)
    pos = pos or playerPos()
    local P = FGPS.Data and FGPS.Data.poi
    if not pos or not P or not P.n then return nil end
    local best, bestD
    for i = 1, P.n do
        if P.type[i] == Social.GRAVEYARD_TYPE and P.inst[i] == pos.inst then
            local d = dist(pos.x, pos.y, P.x[i], P.y[i])
            if not bestD or d < bestD then best, bestD = i, d end
        end
    end
    if not best then return nil end
    return { kind = "poi", poiIndex = best, name = P.name[best], inst = P.inst[best], x = P.x[best], y = P.y[best],
             map = P.map[best], type = "graveyard" }, bestD
end


function Social.CorpseDestination()
    if not Social.IsDead() then return nil, "not_dead" end
    local corpse = Social.CorpsePosition()
    if corpse then
        local uiMapID, mx, my = corpse.map, corpse.mx, corpse.my
        return { kind = "custom", name = L["Your corpse"], type = "corpse", inst = corpse.inst, x = corpse.x, y = corpse.y,
                 map = uiMapID, mx = mx, my = my, zoneName = zoneName(uiMapID) }, "corpse"
    end
    local grave = Social.NearestGraveyard()
    if not grave then return nil, "no_position" end
    local uiMapID, mx, my = worldToMap(grave.inst, grave.x, grave.y)
    return { kind = "custom", name = format(L["%s (graveyard)"], grave.name or L["Graveyard"]), type = "graveyard",
             inst = grave.inst, x = grave.x, y = grave.y, map = uiMapID or grave.map, mx = mx, my = my,
             zoneName = zoneName(uiMapID or grave.map) }, "graveyard"
end






function Social.GoToCorpse(quiet)
    local Nav = navigator()
    local dest, kind = Social.CorpseDestination()
    if not dest then
        if quiet then
            local Guide = FGPS.UI and FGPS.UI.Guide
            if kind ~= "not_dead" and Guide and Guide.Say then
                Guide.Say(L["Your corpse cannot be found yet"], Social.NO_CORPSE_HOLD)
            end
        elseif kind == "not_dead" then
            FGPS:Print(L["You are not dead; there is no corpse to run to."])
        else
            FGPS:Print(L["This client will not say where your corpse is and no graveyard is known nearby."])
        end
        return false, kind
    end
    if not (Nav and Nav.SetDestination) then return false, "no_navigator" end
    Social.StopFollowing("corpse")
    Nav:SetDestination(dest, { start = true, quiet = quiet and true or nil })
    Social.corpse = dest
    if kind == "graveyard" and not quiet then
        FGPS:Print(L["The client will not say where your corpse is, so this is the nearest graveyard instead."])
    end
    return true, kind
end







local CORPSE_POPUP = "CABBIE_GO_CORPSE"

local function ensureCorpsePopup()
    if type(StaticPopupDialogs) ~= "table" then return false end
    if StaticPopupDialogs[CORPSE_POPUP] then return true end
    StaticPopupDialogs[CORPSE_POPUP] = {
        text = "%s",
        button1 = L["Go to corpse"],
        button2 = L["Not now"],
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        OnAccept = function() Social.GoToCorpse(true) end,
        OnCancel = function() end,
    }
    return true
end


function Social.OfferCorpseRun()
    if Social.corpseOffered then return false end
    Social.corpseOffered = true
    if not ensureCorpsePopup() or type(StaticPopup_Show) ~= "function" then return false end
    StaticPopup_Show(CORPSE_POPUP, L["You are dead. Guide me back to my corpse?"])
    return true
end



local function isCorpseStop(stop)
    return type(stop) == "table" and stop.kind == "custom" and (stop.type == "corpse" or stop.type == "graveyard")
end






function Social.OnAlive()
    local dest = Social.corpse
    Social.corpse = nil
    local Nav = navigator()
    if not Nav or not Nav.HasAnythingSet or not Nav:HasAnythingSet() then return false end
    local stops = Nav.GetStops and Nav:GetStops() or {}
    local D = FGPS.Destinations
    local matches = false
    for _, stop in ipairs(stops) do
        if isCorpseStop(stop) or (dest and (stop == dest or (D and D.Equal and D.Equal(stop, dest)))) then
            matches = true
            break
        end
    end
    if not matches then return false end
    Nav:Cancel("resurrected")
    return true
end

local function cancelLifeLook()
    local timer = Social.lifeLook
    Social.lifeLook = nil
    if timer and timer.Cancel then timer:Cancel() end
end



local function aliveAgain()
    cancelLifeLook()
    Social.corpseOffered = false
    if type(StaticPopup_Hide) == "function" then StaticPopup_Hide(CORPSE_POPUP) end
    Social.OnAlive()
end







local function lookAtLife(lookAgain)
    cancelLifeLook()
    if Social.IsGhost() then
        Social.OfferCorpseRun()
    elseif not Social.IsDead() then
        aliveAgain()
    elseif lookAgain and C_Timer and C_Timer.NewTimer then
        Social.lifeLook = C_Timer.NewTimer(0, function()
            Social.lifeLook = nil
            lookAtLife(false)
        end)
    end
end







function Social.UnitWorldPosition(unit)
    if not UnitPosition then return nil end
    local ok, posY, posX, _, inst = pcall(UnitPosition, unit)
    if not ok then return nil end
    posY, posX, inst = plain(posY), plain(posX), plain(inst)
    if type(posX) ~= "number" or type(posY) ~= "number" then return nil end
    if posX == 0 and posY == 0 then return nil end
    return { inst = type(inst) == "number" and inst or nil, x = posX, y = posY }
end

local function unitName(unit)
    if not UnitName then return nil end
    local ok, name = pcall(UnitName, unit)
    if not ok then return nil end
    name = plain(name)
    return type(name) == "string" and name ~= "" and name or nil
end
Social.UnitName = unitName





function Social.GroupMembers()
    local out, listed = {}, {}
    local me = unitName("player")

    local function add(unit)
        local name = unitName(unit)
        if not name then return false end
        if name ~= me and not listed[name] then
            listed[name] = true
            local pos = Social.UnitWorldPosition(unit)
            out[#out + 1] = { unit = unit, name = name, inst = pos and pos.inst, x = pos and pos.x, y = pos and pos.y }
        end
        return true
    end
    for i = 1, Social.MAX_PARTY do add("party" .. i) end
    if unitName("raid1") then
        for i = 1, Social.MAX_RAID do
            if not add("raid" .. i) and i > 1 then break end
        end
    end
    return out
end


function Social.ResolveMember(text)
    if type(text) ~= "string" or text == "" then return nil end
    local wanted = Util.Lower(Util.Trim(text))
    local members = Social.GroupMembers()
    for _, m in ipairs(members) do
        if Util.Lower(m.unit) == wanted or Util.Lower(m.name) == wanted then return m end
    end
    for _, m in ipairs(members) do
        if Util.Lower(m.name):sub(1, #wanted) == wanted then return m end
    end
    return nil
end




local function followDestination(member)
    local uiMapID, mx, my = worldToMap(member.inst, member.x, member.y)
    return { kind = "custom", type = "player", name = member.name, inst = member.inst, x = member.x, y = member.y,
             map = uiMapID, mx = mx, my = my, zoneName = zoneName(uiMapID) }
end

function Social.FollowedUnit()
    return Social.following and Social.following.unit or nil
end




local function followedMemberUnit(following)
    if unitName(following.unit) == following.name then return following.unit end
    for _, m in ipairs(Social.GroupMembers()) do
        if m.name == following.name then return m.unit end
    end
    return nil
end

local function updateTicker()
    local want = Social.following ~= nil
    if want and not Social.ticker then
        if C_Timer and C_Timer.NewTicker then
            Social.ticker = C_Timer.NewTicker(1 / Social.FOLLOW_HZ, function() Social.FollowTick() end)
        end
    elseif not want and Social.ticker then
        Social.ticker:Cancel()
        Social.ticker = nil
    end
end
Social.UpdateTicker = updateTicker



function Social.Follow(text)
    local member = Social.ResolveMember(text)
    if not member then
        FGPS:Print(L["Nobody in your group is called '%s'."], tostring(text))
        return false, "no_member"
    end
    if not member.inst or not member.x then
        FGPS:Print(L["The client will not say where %s is (a different continent, or inside an instance)."], member.name)
        return false, "no_position"
    end
    local Nav = navigator()
    if not (Nav and Nav.SetDestination) then return false, "no_navigator" end
    Social.corpse = nil
    Social.following = { unit = member.unit, name = member.name, inst = member.inst, x = member.x, y = member.y, lost = 0 }
    Nav:SetDestination(followDestination(member), { start = true })
    updateTicker()
    FGPS:Print(L["Following %s. Type /cabbie follow off to stop."], member.name)
    return true
end







local function tell(fmt, name)
    local Guide = FGPS.UI and FGPS.UI.Guide
    if not (Guide and Guide.Tell) then return end
    local ok, err = pcall(Guide.Tell, Util.SafeFormat(fmt, name), Social.FOLLOW_ENDED_HOLD)
    if not ok and FGPS.Log and FGPS.Log.Error then FGPS.Log:Error("Social: the guide could not tell a line: %s", tostring(err)) end
end



function Social.StopFollowing(reason)
    local following = Social.following
    Social.following = nil
    updateTicker()
    if not following then return false end
    if reason == "left" then
        tell(L["%s is no longer in your group; following stopped."], following.name)
    elseif reason == "lost" then
        tell(L["The client can no longer say where %s is; following stopped."], following.name)
    elseif reason ~= "corpse" and reason ~= "quiet" then
        FGPS:Print(L["No longer following %s."], following.name)
    end
    return true
end




local function followedStopStands(Nav, following)
    local stops = Nav.GetStops and Nav:GetStops() or {}
    local stop = stops[1]
    return #stops == 1 and type(stop) == "table" and stop.type == "player" and stop.name == following.name
end



function Social.FollowTick()
    local following = Social.following
    if not following then updateTicker() return nil end
    local Nav = navigator()


    if not Nav or not Nav.IsJourney or not (Nav:IsJourney() or Nav.inflight ~= nil) or not followedStopStands(Nav, following) then


        Social.StopFollowing("quiet")
        return nil
    end
    local unit = followedMemberUnit(following)
    if not unit then
        Social.StopFollowing("left")
        return nil
    end
    following.unit = unit
    local pos = Social.UnitWorldPosition(unit)
    if not pos or not pos.inst then
        following.lost = following.lost + 1
        if following.lost >= Social.FOLLOW_LOST_TICKS then Social.StopFollowing("lost") end
        return nil
    end
    following.lost = 0
    local moved = (pos.inst == following.inst) and dist(pos.x, pos.y, following.x, following.y) or math.huge
    if moved < Social.FOLLOW_MOVE_YARDS then return false end
    following.inst, following.x, following.y = pos.inst, pos.x, pos.y

    Nav:SetDestination(followDestination(following), { start = true, quiet = true, askedBy = "navigator" })
    return true
end







function Social.Encode(dest)
    if type(dest) ~= "table" or type(dest.inst) ~= "number" or type(dest.x) ~= "number" or type(dest.y) ~= "number" then
        return nil
    end
    local uiMapID, mx, my = dest.map, dest.mx, dest.my
    if type(uiMapID) ~= "number" then uiMapID, mx, my = worldToMap(dest.inst, dest.x, dest.y) end
    return format("<%s:%d:%d:%.1f:%.1f:%d:%.4f:%.4f>", Social.PREFIX, Social.VERSION, dest.inst, dest.x, dest.y,
        tonumber(uiMapID) or 0, tonumber(mx) or 0, tonumber(my) or 0)
end




function Social.Decode(text, name)
    if type(text) ~= "string" then return nil end
    local pattern = "<" .. Social.PREFIX .. ":(%d+):(%-?%d+):(%-?[%d%.]+):(%-?[%d%.]+):(%d+):(%-?[%d%.]+):(%-?[%d%.]+)>"
    local version, inst, x, y, uiMapID, mx, my = text:match(pattern)
    if not version then return nil end
    version, inst, x, y = tonumber(version), tonumber(inst), tonumber(x), tonumber(y)
    uiMapID, mx, my = tonumber(uiMapID), tonumber(mx), tonumber(my)
    if version ~= Social.VERSION or not inst or not x or not y then return nil end
    if x ~= x or y ~= y then return nil end
    if uiMapID == 0 then uiMapID, mx, my = worldToMap(inst, x, y) end
    local zone = zoneName(uiMapID)
    local label = name
    if not label or label == "" then
        label = text:match("^%s*Cabbie:%s*(.-)%s*<") or text:match("(.-)%s*<" .. Social.PREFIX)


        local suffix = type(label) == "string" and type(zone) == "string" and zone ~= "" and " - " .. zone
        if suffix and #label > #suffix and label:find(suffix, #label - #suffix + 1, true) then
            label = label:sub(1, #label - #suffix)
        end
    end
    if type(label) ~= "string" or label == "" then label = L["a shared destination"] end
    return { kind = "custom", type = "shared", name = label, inst = inst, x = x, y = y, map = uiMapID,
             mx = mx, my = my, zoneName = zone }
end

local function describe(dest)
    local D = FGPS.Destinations
    if D and D.Describe then return D.Describe(dest) end
    return dest and dest.name or "?"
end







function Social.ShareText(dest)
    local tail = Social.Encode(dest)
    if not tail then return nil end
    local name = type(dest.name) == "string" and dest.name ~= "" and dest.name
    if not name then return format("%s %s %s", L["Cabbie:"], describe(dest), tail) end
    local zone = dest.zoneName
    if type(zone) == "string" and zone ~= "" and zone ~= name then name = name .. " - " .. zone end
    return format("%s %s %s", L["Cabbie:"], name, tail)
end



function Social.Share(channel)
    local Nav = navigator()
    local stops = Nav and Nav.GetStops and Nav:GetStops() or {}
    local dest = stops[1]
    if not dest then
        FGPS:Print(L["No destination set; there is nothing to share."])
        return false, "no_destination"
    end
    local text = Social.ShareText(dest)
    if not text then
        FGPS:Print(L["This destination has no position that can be shared."])
        return false, "bad_destination"
    end
    channel = channel or (unitName("raid1") and "RAID" or "PARTY")
    if not SendChatMessage then
        FGPS:Print(L["This client does not let add-ons post to chat."])
        return false, "no_api"
    end
    local ok, err = pcall(SendChatMessage, text, channel)
    if not ok then
        FGPS:Print(L["Could not post to %s chat: %s"], tostring(channel), tostring(err))
        return false, "send_failed"
    end
    return true, channel, text
end



function Social.OnChatMessage(text, sender)
    if type(text) ~= "string" then return nil end
    local me = unitName("player")
    if sender and me and sender:match("^[^-]+") == me then return nil end
    local dest = Social.Decode(text)
    if not dest then return nil end
    Social.offer = { dest = dest, sender = sender or L["someone in your group"], at = now() }
    FGPS:Print(L["%s is heading to %s. Type /cabbie accept to go there too, or /cabbie decline to ignore it."],
        tostring(Social.offer.sender), describe(dest))
    return dest
end

function Social.PendingOffer()
    local offer = Social.offer
    if not offer then return nil end
    if now() - offer.at > Social.OFFER_TTL then
        Social.offer = nil
        return nil
    end
    return offer
end

function Social.AcceptOffer()
    local offer = Social.PendingOffer()
    if not offer then
        FGPS:Print(L["Nobody has shared a destination with you recently."])
        return false, "no_offer"
    end
    Social.offer = nil
    local Nav = navigator()
    if not (Nav and Nav.SetDestination) then return false, "no_navigator" end
    Social.StopFollowing("quiet")
    Social.corpse = nil
    Nav:SetDestination(offer.dest, { start = true })
    return true
end

function Social.DeclineOffer()
    local had = Social.offer ~= nil
    Social.offer = nil
    if had then FGPS:Print(L["The shared destination was ignored."]) end
    return had
end




local function slashCorpse()
    Social.GoToCorpse()
end

local function slashFollow(args)
    local text = Util.Trim(args or "")
    local word = Util.Lower(text)
    if word == "" then
        local unit = Social.FollowedUnit()
        if unit then
            FGPS:Print(L["Following %s. Type /cabbie follow off to stop."], Social.following.name)
        else
            FGPS:Print(L["Use /cabbie follow <name> to navigate to a group member, or /cabbie follow off to stop."])
            local members = Social.GroupMembers()
            for _, m in ipairs(members) do
                if m.inst then
                    FGPS:Print("  %s", m.name)
                else
                    FGPS:Print(L["  %s (position not available)"], m.name)
                end
            end
        end
        return
    end
    if word == "off" or word == "stop" or word == "none" then
        if not Social.StopFollowing("user") then FGPS:Print(L["You are not following anybody."]) end
        return
    end
    Social.Follow(text)
end

local function slashShare()
    Social.Share()
end

local function slashAccept()
    Social.AcceptOffer()
end

local function slashDecline()
    Social.DeclineOffer()
end




local CHAT_EVENTS = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER" }

function Social:Init()
    if self.initialised then return end
    self.initialised = true


    Events:RegisterWoW("PLAYER_ALIVE", function() lookAtLife(true) end, self)

    Events:RegisterWoW("PLAYER_UNGHOST", aliveAgain, self)



    Events:Register("WORLD_ENTERED", function()
        if Social.IsGhost() then
            Social.OfferCorpseRun()
        elseif (Social.corpseOffered or Social.corpse) and not Social.IsDead() then
            aliveAgain()
        end
    end, self)
    for _, event in ipairs(CHAT_EVENTS) do
        Events:RegisterWoW(event, function(_, text, sender) Social.OnChatMessage(text, sender) end, self)
    end
    Events:RegisterWoW("GROUP_ROSTER_UPDATE", function()
        local following = Social.following
        if not following then return end
        local unit = followedMemberUnit(following)
        if unit then following.unit = unit else Social.StopFollowing("left") end
    end, self)

    Events:Register("NAV_CANCELLED", function() Social.StopFollowing("quiet") end, self)
    Events:Register("NAV_ARRIVED", function(_, _, isFinal) if isFinal then Social.StopFollowing("quiet") end end, self)
    if FGPS.Slash and FGPS.Slash.Register then
        FGPS.Slash.Register("corpse", slashCorpse, L["Navigate back to your corpse"])
        FGPS.Slash.Register("follow", slashFollow, L["Follow a group member: follow <name>|off"])
        FGPS.Slash.Register("share", slashShare, L["Post your destination to party chat"])
        FGPS.Slash.Register("accept", slashAccept, L["Accept a destination somebody shared"])
        FGPS.Slash.Register("decline", slashDecline, L["Ignore a destination somebody shared"])
    end
end
