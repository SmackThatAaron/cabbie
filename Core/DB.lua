

























local ADDON_NAME, FGPS = ...

local Util = FGPS.Util
local type, pairs, ipairs, tonumber, tostring = type, pairs, ipairs, tonumber, tostring

local DB = {
    VERSION = 10,
    initialized = false,
}
FGPS.DB = DB




local settingsDefaults = {
    version = 1,
    preset = "minimal",
    units = "yards",
    textSize = "normal",


    routeBlock = { enabled = false },



    callout = { enabled = true,
                arrowSize = 1,
                arrowAlpha = 1,
                arrowColor = "ffd030",
                arrowStyle = "arrow",
                turnPulse = true,


                showWords = false,
                showDistance = false,
                textSize = 1 },
    worldMapLine = true,
    minimapLine = true,


    roadBeacon = false,
    inWorldPin = false,


    windowSounds = true,
    mapClickModifier = "CTRL_RIGHT",
    removeStopOnMarkerOnly = false,
    goToMapPin = true,
    askCorpseRun = false,
    combatMode = "visuals_only",

    voice = { enabled = false, systemVoice = false, rate = 0, volume = 70, verbosity = "normal" },
    transports = { taxi = true, boat = true, zeppelin = true, tram = true, hearth = true, spells = true },
    routing = { preferRoads = true, roadShortcuts = false, allowUnverified = true, arrivalRadius = 50,
                offRouteYards = 40, recalcMinSeconds = 5, assumeMount = "auto",
                avoidGuarded = true },


    perf = { instrument = true, frameBudgetMs = 4, spareFrame = true, frameBudgetMaxMs = 12 },
    debug = false,
}

DB.defaults = {
    settings = settingsDefaults,
    account = { version = DB.VERSION, settings = settingsDefaults, positions = {}, windows = {}, favorites = {},
                recents = {}, learnedServices = {} },

    char = { knownTaxi = {}, itinerary = {} },
}



local PROTECTED_ACCOUNT_KEYS = { favorites = true, recents = true, learnedServices = true }
local PROTECTED_ACCOUNT_FLAGS = { setupComplete = true }
local ROUTING_PREF_KEYS = { routing = true, transports = true }




local function warn(fmt, ...)
    if FGPS.Log then FGPS.Log:Warn(fmt, ...) end
end



local function applyDefaults(dst, defaults, path)
    for key, value in pairs(defaults) do
        local current = dst[key]
        local here = path and (path .. "." .. tostring(key)) or tostring(key)
        if current == nil then
            dst[key] = Util.DeepCopy(value)
        elseif type(value) == "table" then
            if type(current) ~= "table" then
                warn("Saved value %s had type %s, expected table; restored default", here, type(current))
                dst[key] = Util.DeepCopy(value)
            else
                applyDefaults(current, value, here)
            end
        elseif type(current) ~= type(value) then
            warn("Saved value %s had type %s, expected %s; restored default", here, type(current), type(value))
            dst[key] = value
        end
    end
    return dst
end
DB.ApplyDefaults = applyDefaults




local pathCache = {}

local function splitPath(path)
    local parts = pathCache[path]
    if parts then return parts end
    parts = {}
    for piece in tostring(path):gmatch("[^.]+") do parts[#parts + 1] = piece end
    pathCache[path] = parts
    return parts
end



local function walk(root, path, depth)
    if path == nil or path == "" then return root end
    local node = root
    local parts = splitPath(path)
    for i = 1, depth or #parts do
        if type(node) ~= "table" then return nil end
        node = node[parts[i]]
    end
    return node
end




local migrations = {}



migrations[3] = function(account)
    if type(account) ~= "table" then return end
    account.arrow = nil
    account.panel = nil
    if type(account.settings) == "table" then
        account.settings.arrow = nil
        account.settings.panel = nil
    end
end




local QUEST_STOP_FIELDS = { "questID", "questTarget", "questChosen", "objectiveIndex", "areaIndex", "areaRadius",
                            "finishedCount", "complete", "source" }

local function isQuestStop(stop)
    if type(stop) ~= "table" then return false end
    if stop.kind == "quest" or stop.type == "quest" then return true end
    return stop.questTarget ~= nil
end


local function filterInPlace(list, keep)
    if type(list) ~= "table" then return end
    local count, kept = #list, 0
    for i = 1, count do
        local entry = list[i]
        if keep(entry) then
            kept = kept + 1
            list[kept] = entry
        end
    end
    for i = kept + 1, count do list[i] = nil end
end




local function keepAsPlace(entry)
    if not isQuestStop(entry) then return true end
    if type(entry.inst) ~= "number" or type(entry.x) ~= "number" or type(entry.y) ~= "number" then return false end
    for _, f in ipairs(QUEST_STOP_FIELDS) do entry[f] = nil end
    if entry.kind == "quest" then entry.kind = "custom" end
    if entry.type == "quest" then entry.type = "custom" end
    return true
end

local function notQuestStop(stop) return not isQuestStop(stop) end







local function dropQuestRecords(char)
    if type(char) ~= "table" then return end
    char.leveling, char.questPickups, char.questRoute = nil, nil, nil
    filterInPlace(char.itinerary, notQuestStop)
    if isQuestStop(char.lastDestination) then char.lastDestination = nil end
end






local function dropQuestPlaces(account)
    if type(account) ~= "table" then return end
    if type(account.settings) == "table" then account.settings.quests = nil end
    filterInPlace(account.favorites, keepAsPlace)
    filterInPlace(account.recents, keepAsPlace)
end





migrations[7] = function(account, char)
    if type(account) ~= "table" then return end
    dropQuestPlaces(account)
    dropQuestRecords(char)
end



migrations[0] = function(account)
    if type(account.settings) ~= "table" then account.settings = {} end
    for key in pairs(settingsDefaults) do
        if key ~= "version" and account[key] ~= nil then
            if account.settings[key] == nil then account.settings[key] = account[key] end
            account[key] = nil
        end
    end
    if type(account.favourites) == "table" then
        if type(account.favorites) ~= "table" then account.favorites = {} end
        for _, entry in ipairs(account.favourites) do
            account.favorites[#account.favorites + 1] = entry
        end
        account.favourites = nil
    end
end












DB.defaultChanges = {

    [2] = { { path = "routing.preferRoads", from = false } },



    [4] = { { path = "routeBlock.enabled", from = true } },





    [5] = { { path = "callout.showWords", from = true }, { path = "callout.showDistance", from = true } },






    [8] = { { path = "inWorldPin", from = true } },


    [9] = { { path = "routing.arrivalRadius", from = 10 } },
}



local function moveChangedDefaults(account, changes)
    local settings = account.settings
    if type(settings) ~= "table" then return 0 end
    local moved = 0
    for _, change in ipairs(changes) do
        local path = type(change) == "table" and change.path or nil
        local parts = type(path) == "string" and splitPath(path) or nil
        if parts and #parts > 0 then

            local node, want = walk(settings, path, #parts - 1), walk(DB.defaults.settings, path, #parts - 1)
            if type(node) == "table" and type(want) == "table" then
                local leaf = parts[#parts]
                local new = want[leaf]
                if new ~= nil and new ~= change.from and node[leaf] == change.from then
                    node[leaf] = Util.DeepCopy(new)
                    moved = moved + 1
                end
            end
        end
    end
    return moved
end

function DB:Migrate(fromVersion)
    fromVersion = tonumber(fromVersion) or 0
    if fromVersion > DB.VERSION then
        warn("Saved variables were written by a newer layout (%d > %d); leaving them untouched", fromVersion, DB.VERSION)
        return fromVersion
    end
    local version = fromVersion
    while version < DB.VERSION do
        local step = migrations[version]
        if step then
            local ok, err = pcall(step, self.account, self.char)
            if not ok then
                if FGPS.Log then FGPS.Log:Error("Migration %d -> %d failed: %s", version, version + 1, tostring(err)) end
            elseif FGPS.Log then
                FGPS.Log:Info("Migrated saved variables from layout %d to %d", version, version + 1)
            end
        end
        local changes = DB.defaultChanges[version]
        if type(changes) == "table" then
            local ok, moved = pcall(moveChangedDefaults, self.account, changes)
            if not ok then
                if FGPS.Log then FGPS.Log:Error("Moving the changed defaults of layout %d failed: %s", version + 1, tostring(moved)) end
            elseif moved > 0 and FGPS.Log then
                FGPS.Log:Info("Moved %d setting(s) to the new defaults of layout %d", moved, version + 1)
            end
        end
        version = version + 1
        self.account.version = version
    end
    self.version = version
    return version
end
































local function dropRetired(self)
    self.account.routeReports = nil
    if not FGPS:IsOwnerInstall() then
        self.account.lastSession = nil
        self.account.selftest = nil
    end
    local settings = self.account.settings
    if type(settings) == "table" then
        settings.learnPaths = nil
        settings.factionAccent = nil
        if type(settings.routing) == "table" then
            settings.routing.avoidDanger = nil
            settings.routing.dangerMargin = nil
        end
    end
    dropQuestPlaces(self.account)
    dropQuestRecords(self.char)
end




function DB:Init()
    if type(CabbieDB) ~= "table" then CabbieDB = {} end
    if type(CabbieCharDB) ~= "table" then CabbieCharDB = {} end
    self.account = CabbieDB
    self.char = CabbieCharDB

    local hasContent = next(self.account) ~= nil
    local from = tonumber(self.account.version)
    if from == nil then from = hasContent and 0 or DB.VERSION end


    local version = self:Migrate(from)
    if version <= DB.VERSION then dropRetired(self) end

    applyDefaults(self.account, DB.defaults.account)
    applyDefaults(self.char, DB.defaults.char)
    self.account.perf = nil
    self.settings = self.account.settings


    if version <= DB.VERSION then self.settings.version = DB.defaults.settings.version end
    self.account.version = version
    self.version = version
    self.initialized = true
    return self
end




function DB:Get(path)
    return walk(self.settings, path)
end

function DB:GetDefault(path)
    return walk(DB.defaults.settings, path)
end

function DB:Set(path, value)
    assert(type(path) == "string" and path ~= "", "DB:Set: path must be a non-empty string")
    local parts = splitPath(path)
    local node = self.settings
    for i = 1, #parts - 1 do
        local nextNode = node[parts[i]]
        if type(nextNode) ~= "table" then
            nextNode = {}
            node[parts[i]] = nextNode
        end
        node = nextNode
    end
    node[parts[#parts]] = value
    if FGPS.Events then FGPS.Events:Fire("SETTINGS_CHANGED", path, value) end
    return value
end

function DB:IsDefault(path)
    return Util.Serialize(self:Get(path)) == Util.Serialize(self:GetDefault(path))
end






function DB:ResetSettings(opts)
    local settings = self.settings
    local kept = {}
    if not (opts and opts.includeRouting) then
        for key in pairs(ROUTING_PREF_KEYS) do kept[key] = settings[key] end
    end
    wipe(settings)
    applyDefaults(settings, DB.defaults.settings)
    for key, value in pairs(kept) do settings[key] = value end
    if FGPS.Events then FGPS.Events:Fire("SETTINGS_CHANGED", "*", nil) end
end


function DB:ResetPositions()
    wipe(self.account.positions)
    wipe(self.account.windows)
    if FGPS.Events then FGPS.Events:Fire("POSITIONS_RESET", nil) end
end



function DB:ResetElementPosition(key, layoutName)
    assert(key ~= nil, "DB:ResetElementPosition: key is required")
    if layoutName ~= nil then
        local layout = self.account.positions[layoutName]
        if type(layout) == "table" then layout[key] = nil end
    else
        for _, layout in pairs(self.account.positions) do
            if type(layout) == "table" then layout[key] = nil end
        end
        self.account.windows[key] = nil
    end
    if FGPS.Events then FGPS.Events:Fire("POSITIONS_RESET", key) end
end



function DB:ResetRouting()
    local settings = self.settings
    for key in pairs(ROUTING_PREF_KEYS) do
        settings[key] = Util.DeepCopy(DB.defaults.settings[key])
    end
    if FGPS.Events then FGPS.Events:Fire("SETTINGS_CHANGED", "*", nil) end
end





function DB:ResetAll()
    self:ResetSettings()
    self:ResetPositions()
    self.account.perf = nil
    for key in pairs(PROTECTED_ACCOUNT_KEYS) do
        if type(self.account[key]) ~= "table" then self.account[key] = {} end
    end
    for key in pairs(PROTECTED_ACCOUNT_FLAGS) do
        if self.account[key] == nil then self.account[key] = false end
    end
end
