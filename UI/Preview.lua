















local ADDON_NAME, FGPS = ...

local L = FGPS.L
local Util = FGPS.Util
local type, ipairs, tostring, tonumber, format = type, ipairs, tostring, tonumber, string.format
local abs = math.abs

local Preview = {
    route = nil,
    alternatives = nil,
    error = nil,
    calculating = false,
    listMode = "steps",
    pendingDest = nil,


    open = false,
}
FGPS.UI.Preview = Preview



local TRANSPORT_LABELS = { taxi = "Flight", boat = "Boat", zeppelin = "Zeppelin", tram = "Tram", elevator = "Elevator",
                           portal = "Portal", hearth = "Hearthstone", spell = "Teleport" }
local VARIANT_LABELS = { fastest = "Fastest", fewer_transfers = "Fewer Transfers", prefer_roads = "Prefer Roads",
                         no_flight = "No Flights", no_boat = "No Boats" }

local function settings() return FGPS.DB and FGPS.DB.settings or nil end




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

            local D = FGPS.Destinations
            local name = D and D.SpokenName and D.SpokenName(dest, stops) or dest.name
            if #stops > 1 then return format(L["%s (%d stops)"], name, #stops) end
            return name
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
    local Look = FGPS.UI.Look
    local about = Look and Look.About and Look.About(route.totalSeconds) or nil
    summary.eta = about or ""


    summary.total = format(L["Total %s"], about and (about .. " \194\183 " .. summary.distance) or summary.distance)


    local dashedYards = summary.unverifiedYards - (tonumber(route.dockYards) or 0)
    if dashedYards >= leastGuessedYards() then


        local sentence
        if (tonumber(route.meshYards) or 0) > 0 then
            sentence = L["%s of this route is a guessed way over open ground (drawn dashed on the maps); expect obstacles."]
        else
            sentence = L["%s of this route is open ground (drawn dashed on the maps); expect obstacles."]
        end
        summary.unverifiedText = format(sentence, Util.FormatDistance(dashedYards, units))
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



function Preview.DescribeAlternative(alt, reference, named)
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
    if not named then
        if alt.variant == "prefer_roads" then parts[#parts + 1] = L["prefer roads"] end
        if alt.variant == "no_flight" then parts[#parts + 1] = L["no flights"] end
        if alt.variant == "no_boat" then parts[#parts + 1] = L["no boats"] end
    end
    if (tonumber(alt.unverifiedYards) or 0) >= leastGuessedYards() then
        parts[#parts + 1] = format(L["%s open ground"], Util.FormatDistance(alt.unverifiedYards, settings() and settings().units or "yards"))
    end
    return table.concat(parts, ", ")
end




local function explainBesideWarning(text)
    if type(text) ~= "string" or text == "" then return "" end
    local rest = text
    while true do
        local sentence, tail = rest:match("^([^.]*%.)%s*(.*)$")
        if not sentence then return rest end
        if sentence:find("open ground (drawn dashed)", 1, true)
            or sentence:find("nobody has walked the way between them", 1, true)
            or sentence:find("the whole route is drawn dashed", 1, true) then
            rest = tail or ""
        else
            return rest
        end
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


    local s = settings()
    return err.code == "NO_PATH" and s ~= nil and s.routing ~= nil and s.routing.allowUnverified == false
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



local function sectionRoute()
    local route = Preview.route
    if type(route) == "table" and not leadsElsewhere(route) then return route end
    local Navigator = FGPS.Navigator
    route = Navigator and Navigator.GetRoute and Navigator:GetRoute() or nil
    if type(route) == "table" and not leadsElsewhere(route) then return route end
    return nil
end






local function routeNote(summary)
    local parts = {}
    local explain = summary.explain or ""
    if summary.unverifiedText then
        parts[#parts + 1] = summary.unverifiedText
        explain = explainBesideWarning(explain)
    end
    if explain ~= "" then parts[#parts + 1] = explain end
    if summary.hearthNote then parts[#parts + 1] = summary.hearthNote end
    if #parts == 0 then return nil end
    return table.concat(parts, " ")
end

local function isCurrent(alt, route)
    return route ~= nil and (alt == route or (alt.id ~= nil and alt.id == route.id))
end

local function otherAlternativesCount(alternatives, route)
    if type(alternatives) ~= "table" then return 0 end
    local n = 0
    for _, alt in ipairs(alternatives) do
        if not isCurrent(alt, route) then n = n + 1 end
    end
    return n
end



function Preview.AlternativeLabel(alt, reference)
    local how = Preview.DescribeAlternative(alt, reference, true)
    if isCurrent(alt, reference) then how = how .. ", " .. L["selected"] end
    return format("%s (%s)", L[VARIANT_LABELS[alt.variant] or tostring(alt.variant)], how)
end






function Preview.SectionView()
    local view = {}
    local route = sectionRoute()
    view.route = route
    if route then
        local summary = Preview.Summarize(route)
        view.summary = summary.total
        if summary.fallback == "straight" then
            view.line = L["No road was found; this route is drawn dashed."]
        elseif Preview.calculating then
            view.line = L.ROUTE_CALCULATING
        elseif Preview.listMode == "alternatives" then
            local alternatives = Preview.alternatives
            if alternatives == nil then
                view.line = L["Computing alternatives..."]
            elseif otherAlternativesCount(alternatives, route) == 0 then
                view.line = L["There's no other way that's really different."]
            else
                view.line = L["Other routes found: right-click Your Route to choose one."]
            end
        end
        if view.line == nil and summary.unverifiedText ~= nil then view.line = summary.unverifiedText end
        view.note = routeNote(summary)
    elseif Preview.calculating then
        view.line = L.ROUTE_CALCULATING
    elseif Preview.error then
        view.line = errorMessage(Preview.error)
    end
    return view
end





function Preview.MenuEntries()
    local entries = {}
    local Navigator = FGPS.Navigator
    local route = sectionRoute()
    local kept = Preview.route
    if kept ~= nil then
        local journey = Navigator and Navigator.IsJourney and Navigator:IsJourney() or false
        local held = Navigator and Navigator.GetRoute and Navigator:GetRoute() or nil
        local state = Navigator and Navigator.GetState and Navigator:GetState() or nil
        if not (journey and held == kept and state ~= "paused") then
            entries[#entries + 1] = { label = L["Start"], onClick = function() Preview:Start() end }
        end
    end
    entries[#entries + 1] = { label = L["Add Stop"], onClick = function() Preview:AddStop() end }
    local alternatives = route and Preview.alternatives or nil
    if type(alternatives) == "table" and otherAlternativesCount(alternatives, route) > 0 then
        for _, alt in ipairs(alternatives) do
            entries[#entries + 1] = {
                label = Preview.AlternativeLabel(alt, route),
                onClick = function() Preview:ChooseAlternative(alt) end,
                disabled = function() return isCurrent(alt, Preview.route) end,
            }
        end
    elseif route and Preview.listMode ~= "alternatives" then
        entries[#entries + 1] = { label = L["Alternatives"], onClick = function() Preview:ToggleAlternatives() end }
    end
    if not route and Preview.error and Preview.CanOfferFallback(Preview.error) then
        entries[#entries + 1] = { label = L["Open Ground"], onClick = function() Preview:UseFallback() end }
    end
    return entries
end


function Preview:Render()
    local Itinerary = FGPS.UI.Itinerary
    if Itinerary and Itinerary.RefreshSection then Itinerary:RefreshSection() end
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
    self:Render()
    local reference = self.route


    local ok, err = pcall(Navigator.RequestAlternatives, Navigator, function(list)
        if Preview.route ~= reference then return end
        Preview.alternatives = type(list) == "table" and list or {}
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








function Preview:Show()
    local Tome, Search = FGPS.UI.Tome, FGPS.UI.Search
    if not (Search and Search.Show and Tome) or not Search:Show({ section = "route", noFocus = true }) then return false end
    self.open = true
    self:Render()
    return Tome:Current() == Search.PAGE
end



function Preview:Hide()

    self.listMode = "steps"
    self.open = false
    self:Render()
end

function Preview:IsShown()
    if not self.open then return false end
    local Search = FGPS.UI.Search
    return Search ~= nil and Search.IsShown ~= nil and Search:IsShown() == true
end



function Preview:OnPageHidden()
    self.listMode = "steps"
    self.open = false
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


local function onRecalcDone(_, route, err)
    Preview.calculating = false
    if route then


        adoptRoute(route, "recalc")
        Preview.error = nil
        Preview:Render()
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
    Preview:Render()
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
    Preview:Render()
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





    Events:Register("FLIGHTS_KNOWN", function()
        Preview.alternatives = nil
        if Preview.listMode == "alternatives" and Preview:IsShown() then
            Preview.listMode = "steps"
            Preview:ToggleAlternatives()
        end
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
            FGPS:Print(L["No place is set yet. Pick one on the Places page first."])
        end
    end, L["Show Your Route on the Places page for the current destination"])
end
