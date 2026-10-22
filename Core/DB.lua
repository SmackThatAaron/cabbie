

























local ADDON_NAME, FGPS = ...

local Util = FGPS.Util
local type, pairs, ipairs, tonumber, tostring = type, pairs, ipairs, tonumber, tostring

local DB = {
    VERSION = 5,
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
                showWords = true,
                showDistance = true,
                textSize = 1 },
    worldMapLine = true,
    minimapLine = true,
    inWorldPin = true,
    mapClickModifier = "CTRL_RIGHT",
    combatMode = "visuals_only",

    voice = { enabled = false, systemVoice = false, rate = 0, volume = 70, verbosity = "normal" },
    transports = { taxi = true, boat = true, zeppelin = true, tram = true, hearth = true, spells = true },
    routing = { preferRoads = true, roadShortcuts = false, allowUnverified = true, avoidDanger = false, dangerMargin = 3, arrivalRadius = 10,
                offRouteYards = 40, recalcMinSeconds = 5, assumeMount = "auto" },




    quests = { enabled = true, mapPins = true, minimapPins = true, objectiveAreas = true,
               searchForever = true, serverLookup = true, followProgress = true, pickupMarks = true,

               batchRadius = 600 },


    perf = { instrument = true, frameBudgetMs = 4, spareFrame = true, frameBudgetMaxMs = 12 },
    debug = false,
}

DB.defaults = {
    settings = settingsDefaults,
    account = { version = DB.VERSION, settings = settingsDefaults, positions = {}, windows = {}, favorites = {},
                recents = {}, learnedServices = {}, perf = {} },

    char = { knownTaxi = {}, itinerary = {} },

    quests = { titles = {} },
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

























local RETIRED_QUEST_FIELDS = { "observed", "stats", "_seq", "_export", "_exportTime" }

local function dropRetired(self)
    for _, key in ipairs(RETIRED_QUEST_FIELDS) do self.quests[key] = nil end
    self.account.routeReports = nil
    local settings = self.account.settings
    local quests = type(settings) == "table" and settings.quests or nil
    if type(quests) == "table" then quests.harvest = nil end
    if type(settings) == "table" then
        settings.learnPaths = nil
        settings.factionAccent = nil
        if settings.preset ~= nil and settings.preset ~= settingsDefaults.preset then
            settings.preset = settingsDefaults.preset
        end
    end
end




function DB:Init()
    if type(CabbieDB) ~= "table" then CabbieDB = {} end
    if type(CabbieCharDB) ~= "table" then CabbieCharDB = {} end
    if type(CabbieQuests) ~= "table" then CabbieQuests = {} end
    self.account = CabbieDB
    self.char = CabbieCharDB
    self.quests = CabbieQuests

    local hasContent = next(self.account) ~= nil
    local from = tonumber(self.account.version)
    if from == nil then from = hasContent and 0 or DB.VERSION end


    local version = self:Migrate(from)
    if version <= DB.VERSION then dropRetired(self) end

    applyDefaults(self.account, DB.defaults.account)
    applyDefaults(self.char, DB.defaults.char)
    applyDefaults(self.quests, DB.defaults.quests)
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

function DB:ResetElementPosition(key)
    assert(key ~= nil, "DB:ResetElementPosition: key is required")
    for _, layout in pairs(self.account.positions) do
        if type(layout) == "table" then layout[key] = nil end
    end
    self.account.windows[key] = nil
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
    wipe(self.account.perf)
    for key in pairs(PROTECTED_ACCOUNT_KEYS) do
        if type(self.account[key]) ~= "table" then self.account[key] = {} end
    end
    for key in pairs(PROTECTED_ACCOUNT_FLAGS) do
        if self.account[key] == nil then self.account[key] = false end
    end


    if type(self.quests) == "table" then applyDefaults(self.quests, DB.defaults.quests) end
end
