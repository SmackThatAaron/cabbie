-- Cabbie/Locale/enUS.lua
-- English strings and the master catalogue every other locale is checked against.
--
-- FGPS.L falls back to the key itself, so a string that no locale translated still reads as the
-- English sentence a module asked for, never as a bare identifier. Two kinds of key exist:
--   * identifier keys (L.ROUTE_NO_PATH) for sentences that are too long or too formatted to use
--     as a key, and for anything a translator has to be able to find quickly;
--   * the English text itself (L["Start"], L["Turn left"]) for the short labels and sentences the
--     UI modules spell out inline.
-- The list at the bottom registers the second kind in this table, so this file is the complete
-- catalogue of keys a locale may override. tests/test_locale.lua fails a locale that invents a key
-- outside it, which catches typos in a translation before a player sees an English sentence where
-- a translated one was meant. Adding a string to the catalogue is part of adding it to the UI; see
-- docs/LOCALIZATION.md.
local ADDON_NAME, FGPS = ...

local L = setmetatable({}, { __index = function(_, key) return key end })
FGPS.L = L

-- Identity and chat output
L.ADDON_TITLE = "Cabbie"
L.VERSION_LINE = "Version %s on client %s (build %s, interface %d)%s"
L.NOT_FOREVER = " - warning: this client does not look like World of Warcraft: Forever"
L.BOOT_FAILED_MODULES = "%d part(s) of Cabbie failed to start; type /cabbie log for details."
L.LOG_EMPTY = "Log is empty."
L.LOG_HEADER = "Log buffer (%d entries, oldest first):"

-- Slash commands
L.SLASH_UNKNOWN = "Unknown command '%s'. Type /cabbie help for the list of commands."
L.SLASH_FAILED = "The command '%s' failed; type /cabbie log for details."
L.HELP_HEADER = "Cabbie %s - commands:"
L.HELP_LINE = "  /cabbie %s - %s"
L.HELP_HELP = "Show this list"
L.HELP_VERSION = "Print version and client build information"
L.HELP_LOG = "Print the internal log buffer (log clear empties it)"
L.HELP_PERF_FULL = "Performance report; perf toggle|reset|sample|trip|on|off"
L.HELP_SELFTEST = "Check this installation and print a pass/fail report"
L.HELP_REPORT = "Write a diagnostic snapshot into the saved variables"
L.HELP_MARK = "Mark the trip you are on, or the last one, with a note: /cabbie mark the harbor line went through a building"
L.TRIP_SUMMARY = "Trip: %s. Longest straight %d yd. Off route %d. Recalculated %d."
L.TRIP_NONE = "No finished trip to report yet."
L.TRIP_MARKED = "Marked this trip: %s"
L.TRIP_NO_MARK = "No trip to mark yet. Start a route first."
-- The welcome window (UI/Setup.lua, redesigned 2026-10-17): one short window, three sentences and
-- the one question ("Follow my quests", whose words and tooltip are in the guidance block below).
L.SETUP_TITLE = "Welcome to Cabbie"
L.SETUP_HELP = "Show the welcome window"
L.SETUP_INTRO = "Cabbie guides you to a place and never moves your character for you. While a route is set, an arrow at the top of the screen points the way and your next steps stand beside the quest list. Shift-click the world map or type a place into the search at its top left to be guided there, and right-click a quest in your quest list and choose Take me there to go to it."
L.SETUP_LATER = "Everything else has a sensible default. Change it any time in Settings, and type /cabbie setup to see this again."
L.SETUP_DONE = "Done"
L.SETUP_SETTINGS = "Settings..."

-- Performance report
L.PERF_HEADER = "Performance report (instrumentation %s, guidance %s, frame budget %d ms)"
L.PERF_ON = "on"
L.PERF_OFF = "off"
L.PERF_LABEL_LINE = "  %-14s count %6d  total %8.2f ms  avg %6.3f ms  max %6.3f ms"
L.PERF_NO_LABELS = "  no timed sections recorded yet"
L.PERF_MEMORY = "  memory: addon %.0f KB, Lua heap %.0f KB (sampled %.0f s ago)"
L.PERF_METRIC = "  profiler %s: %.3f"
-- Two different memory questions, kept apart on purpose. The per-journey figure is what a journey
-- ALLOCATED, which garbage collection then reclaims; it is cheap to measure but says nothing about
-- a leak. What the budget in docs/PERFORMANCE_BUDGETS.md actually limits is what stays RETAINED
-- after a full collection, which "/cabbie perf trip" measures against a baseline the tester takes.
L.PERF_TRIPS_ALLOCATED = "  trips: %d measured, %.1f KB allocated per trip on average, %.1f KB worst (allocated, not collected - type /cabbie perf trip for retained memory)"
L.PERF_RETAINED_BASELINE = "Retained memory baseline taken after a full collection: %.1f KB. Complete your trips, then type /cabbie perf trip again."
L.PERF_RETAINED_REPORT = "Retained since the baseline: %.1f KB after %d trip(s), %.1f KB per trip (budget: 50 KB over 20 trips)."
L.PERF_RETAINED_NO_TRIPS = "Retained since the baseline: %.1f KB, but no trip has finished yet."
L.PERF_SCHEDULER = "  scheduler: %d task(s) queued, %d completed, %.2f ms spent in slices"
L.PERF_GUIDANCE_ON = "Guidance work enabled."
L.PERF_GUIDANCE_OFF = "Guidance work disabled for measurement; type /cabbie perf toggle to re-enable."
L.PERF_RESET = "Performance counters cleared."
L.PERF_INSTRUMENT_ON = "Performance instrumentation enabled."
L.PERF_INSTRUMENT_OFF = "Performance instrumentation disabled."
L.PERF_SAMPLED = "Memory sample recorded."

-- Self test and diagnostic report
L.SELFTEST_HEADER = "Self test: %d checks - %d pass, %d note, %d warn, %d fail, %d skipped"
L.SELFTEST_LINE = "  [%s] %-13s %s"
L.SELFTEST_RUNNING = "Self test running..."
L.SELFTEST_SAVED_FIRST = "nothing to compare yet: this is the first session Cabbie remembers. After a /reload this line says 2 sessions if the game kept Cabbie's saved data. Not a fault in Cabbie: the Forever beta client forgets every addon's saved data when the game is restarted, and on some installs at a /reload as well (KNOWN_LIMITATIONS section 8)."
L.SELFTEST_SAVED_RELOAD_LOST = "the game reloaded the interface and Cabbie's saved data came back empty, so the client did not keep it through the /reload (unless Cabbie was switched on just before it). Not a fault in Cabbie: while the client does this, favourites and your known flight points start over at every /reload and every restart (KNOWN_LIMITATIONS section 8)."
L.REPORT_WRITTEN = "Diagnostic snapshot written to CabbieDB.report (SavedVariables\\Cabbie.lua, saved on /reload or on exit): %d setting(s) off default, %d log line(s), self test %d pass / %d warn / %d fail."
L.REPORT_NO_DB = "Cannot write a report: the saved variables are not available."

-- Units and time formatting
L.UNIT_YARDS = "yd"
L.UNIT_METERS = "m"
L.UNIT_KILOMETERS = "km"
L.TIME_SECONDS = "%ds"
L.TIME_MINUTES = "%dm %ds"
L.TIME_HOURS = "%dh %dm"
L.UNKNOWN_VALUE = "?"

-- Navigation vocabulary shared by Nav and UI modules
L.NAV_STATE_IDLE = "Idle"
L.NAV_STATE_PREVIEWING = "Previewing"
L.NAV_STATE_ACTIVE = "Navigating"
L.NAV_STATE_PAUSED = "Paused"
L.ARROW_TURN_AROUND = "Turn around"
L.ARROW_PAUSED_REASON = "Paused: %s"
L.ARROW_ARRIVED = "Arrived at %s"
L.ROUTE_UNVERIFIED_WARNING = "Parts of this route are rough direction and are drawn dashed."
L.ROUTE_CALCULATING = "Calculating..."
L.ROUTE_NO_PATH = "No route could be found to that destination."
L.ROUTE_NO_ORIGIN = "Your position is not available here."
L.ROUTE_UNREACHABLE = "That destination cannot be reached with the transports currently enabled."
L.ROUTE_NO_DATA = "No navigation data is available for this area."
L.ROUTE_CANCELLED = "Route calculation cancelled."
L.SETTINGS_RESET_DONE = "Settings restored to defaults; routing and transport preferences were kept (/cabbie reset routing resets those)."
L.POSITIONS_RESET_DONE = "Frame positions restored to defaults."
L.DESTINATION_SET = "Destination set: %s"
L.ARRIVED_AT = "You have arrived at %s."

-------------------------------------------------------------------------------
-- Catalogue: strings the modules look up by their English text. The entry maps the sentence to
-- itself, which is what the fallback would produce anyway; listing it here is what makes the
-- string translatable and what lets tests/test_locale.lua tell a translation from a typo.
-- Generated from the sources (every L["..."] lookup plus the option, label and settings tables
-- that are looked up as L[variable]); keep it sorted and add new UI strings as you write them.
-------------------------------------------------------------------------------
local SELF = {
    " (available in %s)",
    "%.1f kilometers",
    "%d meters",
    "%d result(s)",
    "%d stop",
    "%d stops",
    "%d transfer",
    "%d transfers",
    "%d waypoint(s) forgotten. The trip in progress is still running; type /cabbie cancel to stop it.",
    "%d metres",
    "%d yards",
    "%s %s",
    "No matching destinations.",
    "No recent destinations.",
    "Type at least two characters.",
    "%s (%d of %d)",
    "%s (%d stops)",
    "%s (next waypoint)",
    "%s - %s",
    "%s - %s: %s",
    "%s at %s",
    "%s can only be reached by %s; enable them in the transport settings or check the faction restriction.",
    "%s is reachable only through another continent's transports, which are currently disabled.",
    "%s of this route is rough direction (drawn dashed).",
    "%s of this route is rough direction (drawn dashed on the maps); expect obstacles.",
    "%s rough direction",
    "%s, entering %s",
    "%s, then continue %s across open ground for %s (rough direction)",
    "%s: %s",
    "(adjusted %d yd)",
    "(complete)",
    "(next)",
    "(no known path nearby)",
    "(rough direction)",
    "... and %d more steps",
    "100% mount",
    "60% mount",
    "< Back to categories",
    "< Back to lists",
    "< Back to service types",
    "< Back to trainer kinds",
    "%s trainer",
    "%s (your class)",
    "Any trainer",
    "Choose",
    "No trainers are known on this continent for your faction.",
    "Pick a kind of trainer; the number is how many are known within range.",
    "Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering", "First Aid", "Fishing", "Herbalism",
    "Leatherworking", "Mining", "Skinning", "Tailoring", "Weapon master", "Riding", "Pet", "Portal", "Other",
    "^",
    "a 100%% ground mount (%.1f yards per second)",
    "a 60%% ground mount (%.1f yards per second)",
    "a waypoint needs a map and two coordinates",
    "about %d hours",
    "about %d hours %d minutes",
    "about %d hours 1 minute",
    "about %d minutes",
    "about %d minutes %d seconds",
    "about %d minutes 1 second",
    "about %d seconds",
    "about 1 hour",
    "about 1 hour %d minutes",
    "about 1 hour 1 minute",
    "about 1 minute",
    "about 1 minute %d seconds",
    "about 1 minute 1 second",
    "about 1 second",
    "About %s %s (data %s)",
    "Actions",
    "Add stop",
    "Adding stops. Pick a place; the window stays open.",
    "Added a stop: %s",
    "Added to favorites: %s",
    "Adds cost to cells whose hostile creatures are above your level.",
    "Advanced",
    "After you leave the route a new one is requested at most this often.",
    "All",
    "Allow straight-line legs",
    "Alt + Left-click",
    "Alternatives",
    "Alternatives are not available right now.",
    "An extra click that sets a destination on the world map. Choose its modifier and mouse button, or switch it off. Shift + Left-click always goes to the spot at once.",
    "and",
    "Apply an interface preset: minimal|modern|classic",
    "Area",
    "Arrival radius (yards)",
    "Arrive",
    "Arrive at %s",
    "Arrived at stop %d.",
    "Arrow disabled.",
    "Arrow enabled.",
    "Arrow opacity",
    "Arrow placement",
    "Arrow placement set to %s.",
    "Arrow scale",
    "Arrow scale set to %.2f.",
    "Arrow shows distance",
    "Arrow shows travel time left",
    "Adds the time left on the route under the distance. Off by default.",
    "Arrow shows the next instruction",
    "Arrow: %s, placement %s, scale %.2f",
    "Arrow: on|off|scale <n>|<placement>",
    "Assume mount speed",
    "Auction house",
    "Audio cues disabled.",
    "Audio cues enabled.",
    "Audio cues instead of speech: on|off|volume <n>|turn|transport|arrival on|off|test",
    "Audio cues: %s, volume %d.",
    "available, fallback layout editor active",
    "Avoid high-level areas",
    "Bank",
    "Battleground",
    "Battlegrounds",
    "Bear left",
    "Bear right",
    "Below minimap",
    "Bind location not found in the navigation data; the hearthstone is not used for routing.",
    "Bind location unknown; the hearthstone is not used for routing.",
    "Board %s",
    "Board the %s to %s at %s (%s)",
    "Board the %s to %s. The crossing takes %s.",
    "Board the tram at %s (%s)",
    "Board the tram. The ride takes %s.",
    "Board tram",
    "boat",
    "Boat",
    "build",
    "Cabbie",
    "Cabbie does not answer /way while \"Answer the /way command\" is off in its settings. /cabbie way still works.",
    "Cabbie layout editor: drag frames, arrow keys nudge (Shift: 10 px).",
    "Cabbie voice guidance is working.",
    "Cancel",
    "Cancel trip",
    "Cancel the current trip",
    "Capital city",
    "Capitals",
    "Cast %s",
    "Cast %s.",
    "Cheap timers behind /cabbie perf.",
    "Classic",
    "Clear",
    "Clear recent destinations",
    "Clear recents",
    "Client %s (%s), Edit Mode: %s",
    "Client build",
    "Close",
    "Solid line: known path",
    "Settings",
    "Hide the map legend",
    "Turn it back on in Cabbie's settings, or with /cabbie legend on.",
    "Switches off the extra click only. Shift + Left-click still goes to the spot.",
    "Tip: type 42.5 65.1 to go to map coordinates",
    "Services",
    "Search",
    "Nothing to pause or resume.",
    "Step list shown.",
    "Step list hidden.",
    "Pause or resume guidance",
    "Toggle step list",
    "Keep planning",
    "Closes this window. Your stops stay set.",
    "Colour-blind friendly",
    "Computing alternatives...",
    "Confirm",
    "Consider teleport spells",
    "Consider the Hearthstone",
    "Continue %s",
    "Continue %s across open ground for %s (rough direction)",
    "Continue %s across open ground for %s. There is no known path here.",
    "Coordinates",
    "coordinates must be between 0 and 100",
    "Could not add favorite (%s).",
    "Could not add that waypoint: %s",
    "Could not resolve those coordinates%s",
    "Could not use that waypoint: %s",
    "Ctrl + Right-click",
    "Cue '%s' is now %s.",
    "Cue volume set to %d.",
    "Current preset: %s (available: minimal, modern, classic)",
    "Custom",
    "Custom (Edit Mode)",
    "Danger margin (levels)",
    "Data version",
    "Debug output",
    "Debug output disabled.",
    "Debug output enabled.",
    "Destination",
    "Detailed",
    "Detect automatically",
    "Disembark",
    "Disembark at %s",
    "Disembark at %s.",
    "Distance %s",
    "Distance from the destination at which you count as arrived.",
    "Distance units",
    "Dock",
    "Docks",
    "Done",
    "Drag to move. Arrow keys nudge the selection (Shift: 10 px).",
    "Draw route hints on the minimap",
    "Show the minimap button",
    "A compass button on the minimap opens search without typing /cabbie.",
    "Draw the route on the world map",
    "Dungeon",
    "Dungeons",
    "Edit Mode",
    "Edit Mode is open; move the Cabbie frames there.",
    "Elevator",
    "Elevator down",
    "Elevator up",
    "Enter coordinates as: x y [zone], for example 42.5 65.1 Elwynn Forest or Elwynn Forest 42.5, 65.1 (values 0-100; zone may be a name or map id)",
    "Entering %s",
    "Entering %s.",
    "Extra world map click",
    "Faction-coloured accents",
    "Fastest",
    "Favorite",
    "Favorite %d removed.",
    "Favorite renamed to %s.",
    "Favorites",
    "Favorites and recent destinations",
    "Favorites window; fav add [name]|list|remove <n>|<name>",
    "Fewer transfers",
    "Filter this list",
    "Flight",
    "Flight from %s to %s",
    "Flight master",
    "Flight masters",
    "flight point",
    "Fly to %s",
    "Follow the ramp",
    "General",
    "Go",
    "Go through %s",
    "Go through %s.",
    "GPS",
    "Graveyard",
    "Guidance",
    "Guidance work is switched off for a measurement; type /cabbie perf toggle first.",
    "Head %s",
    "Head %s from %s",
    "Hearthstone",
    "Hide all guidance",
    "How far from the route you can stray before it is recalculated.",
    "How many steps the panel lists, counting the current one.",
    "How solid the arrow is drawn; it is dimmed further in combat when guidance is set to visuals only.",
    "In %s, %s",
    "In combat",
    "Inn",
    "Innkeeper",
    "instance %d",
    "Instruction panel lines",
    "Instruction panel scale",
    "interface",
    "Interface preset",
    "It is available in %s.",
    "Itinerary",
    "Itinerary window; stops skip|clear",
    "Keep everything (visuals and voice)",
    "Key bindings (set them in the game's Key Bindings interface, under Cabbie):",
    "Land at %s",
    "Landmark",
    "Landmarks",
    "Layout editor closed.",
    "Layout editor opened. Drag the frames, then press Done or Escape.",
    "Leave elevator",
    "Leave the elevator",
    "Leave the elevator.",
    "Leave the elevator at %s",
    "Leave the tram at %s",
    "Leave the tram at %s.",
    "Leave tram",
    "Levels above yours before an area counts as dangerous.",
    "List the Cabbie key bindings and the keys they are on",
    "Lists",
    "Longest straight-line stretch (yards)",
    "Longest stretch without verified ground data the router may put inside a route. 0 turns these stretches off; the last-resort straight-line guidance is not affected.",
    "Mailbox",
    "Make a U-turn",
    "Make this inn your home",
    "Map pin",
    "Map pin guidance paused because you changed the tracked objective; it resumes with the next route.",
    "Map legend off.",
    "Map legend on.",
    "Map legend: on|off",
    "Map position",
    "Metric",
    "Minimal",
    "Minimal: turns only. Normal: advance notices and turns. Detailed: every step and zone change.",
    "Modern",
    "native integration available",
    "Navigation is not available right now.",
    "Near character",
    "Nearest",
    "Nearest %s by route distance.",
    "Nearest %s by route distance; %d of %d could not be routed and show rough direction.",
    "Never mounted",
    "New name",
    "Next",
    "Next waypoint on the way to the quest",
    "No %s found: %s.",
    "No arrival position is known for this spell.",
    "no boats",
    "No boats",
    "No current destination to add. Set a destination first.",
    "No destination is set. Use /cabbie go or the search window first.",
    "No destination set.",
    "No destination was given.",
    "No distinct alternatives were found.",
    "No extra click",
    "No favorite matches '%s'.",
    "No favorites yet.",
    "No favourites yet. Select a place and press Favorite (star), or search for a town.",
    "No favorites yet. Star a place in Search, or right-click a town on the map.",
    "no flights",
    "No flights",
    "No known transport connects %s and %s.",
    "no map location is known for this quest",
    "No places match. Try a town name, a zone, or bank / flight / inn.",
    "No navigation data is available for %s.",
    "no quest is being tracked",
    "no quest was given",
    "No quests with a known place. Open the quest panel, or accept a quest first.",
    "No recent places. Search for a town, or open Favourites if you saved one.",
    "no sound available in this client",
    "No text-to-speech voices are installed.",
    "No text-to-speech voices installed",
    "no text-to-speech voices installed",
    "No turn-by-turn steps are available for this route.",
    "No known path exists between these points; the whole route is rough direction (dashed).",
    "No known path was found; this is rough direction drawn dashed.",
    "Normal",
    "not available (fallback layout editor via /cabbie layout)",
    "not bound",
    "nothing of that kind is known within range",
    "off",
    "Off",
    "Off route, recalculating.",
    "Off-route distance (yards)",
    "on",
    "On foot or mounted only",
    "Open",
    "Open the Cabbie destination search",
    "Open the destination search",
    "Open the destination search (optionally with a query)",
    "Open the options panel",
    "Open the world map first, then press the key with the cursor over the place you want.",
    "Optimize",
    "Optimize reorders your stops by estimated travel distance. Click Confirm to apply the new order.",
    "or",
    "Pause guidance",
    "Performance instrumentation",
    "Performance report",
    "Pick a category. The list is the nearest places of that kind.",
    "Pick a list.",
    "Pick a service type; results are the nearest by route distance.",
    "Portal",
    "Portals",
    "Position of '%s' restored to its default.",
    "prefer roads",
    "Prefer roads",
    "Prefer known paths",
    "Preset '%s' applied.",
    "Preset colours",
    "Presets that support it tint their accent colour and verified route line with your faction's colour.",
    "Preview",
    "Show route",
    "Prints diagnostics to chat and forwards errors to the error handler.",
    "Quest",
    "Quest lookup failed; type /cabbie log for details.",
    "Quest lookup is not available right now.",
    "quest tracking is not available in this client",
    "Quests",
    "Raid",
    "Raids",
    "Ready to turn in",
    "Recent",
    "Recent destinations are not available right now.",
    "Recent destinations cleared.",
    "Click Clear recents again to confirm.",
    "Recent destinations; recent clear",
    "Remove",
    "Removed from favorites: %s",
    "Rename",
    "Repair",
    "Reset",
    "Reset all UI positions",
    "Reset arrow position",
    "Reset favorites window position",
    "Reset instruction panel position",
    "Reset itinerary window position",
    "Reset preview window position",
    "Reset search window position",
    "Reset settings",
    "Reset settings|positions|routing|all|<element>",
    "Reset to default",
    "Resume guidance",
    "Route",
    "Route computation budget (ms per frame)",
    "Route lines on the map:",
    "Route preview",
    "Route updated.",
    "Routing and transport preferences restored to defaults.",
    "Routing preferences cannot be reset in this session (the settings store did not load).",
    "Same as cancel",
    "same distance",
    "selected",
    "Search failed; type /cabbie log for details.",
    "Search is not available right now.",
    "Searching for the nearest %s...",
    "Select %s to continue your route.",
    "Select a destination first.",
    "Service",
    "Service search failed; type /cabbie log for details.",
    "Service search is not available right now.",
    "Set a destination from waypoint coordinates or a pasted map pin link",
    "Settings and frame positions restored to defaults; routing preferences, favorites and recents were kept.",
    "Sharp left",
    "Sharp right",
    "Shift + Right-click",
    "Shortest time between recalculations (seconds)",
    "Show the guidance arrow",
    "Show the in-world waypoint marker",
    "Show the instruction panel",
    "Show the map legend",
    "Show the route preview for the current destination",
    "Show version, data version, client build and Edit Mode status",
    "Skip stop",
    "Speak turn instructions out loud.",
    "Off (the default): Cabbie's own recorded voice, the same on every computer. On: the voice chosen in the game's text-to-speech settings, which also says place names. Without a voice there, the recorded one speaks.",
    "Use the game's text-to-speech voice",
    "Speech rate",
    "Speech rate set to %d.",
    "Speech volume",
    "Speech volume set to %d.",
    "Speed used for estimates when mount detection is uncertain.",
    "Spell not known yet.",
    "Stable master",
    "Start",
    "Start (or resume) navigation for the previewed route",
    "Steps",
    "stop %d",
    "Stop %d",
    "Stop %d: %s",
    "Stops reordered.",
    "Straight line (rough direction)",
    "Straight-line guidance",
    "Straight-line legs enabled for routing; recalculating.",
    "Take elevator",
    "Take portal",
    "Take the elevator",
    "Take the elevator.",
    "Take the elevator down to %s",
    "Take the elevator to %s",
    "Take the elevator up to %s",
    "Take the flight from %s to %s (%s)",
    "Talk to the flight master and take the flight to %s. The flight takes %s.",
    "Teleport",
    "text-to-speech available",
    "That is not a coordinate pair. Try: /way 42.5 65.1 Elwynn Forest",
    "that map pin is the one Cabbie placed for the current trip",
    "that map position cannot be used as a destination",
    "That map position cannot be used as a destination%s",
    "that place",
    "that quest location is no longer listed",
    "The cursor is not over the world map.",
    "that part of Cabbie is not ready",
    "the dock",
    "the far side",
    "The trip in progress was replaced by %s. Use '/way add <coordinates>' to keep the trip and add a stop instead.",
    "The trip to %s was cancelled: its waypoint was removed.",
    "The layout editor cannot be opened during combat.",
    "the navigator did not accept the waypoint",
    "the objective is inside a dungeon or building; navigate to its entrance instead",
    "The box in the corner of the world map that names the solid, dashed and coloured lines. Turn it off here, or with /cabbie legend.",
    "The options panel is not available in this client; use /cabbie help for the command list.",
    "the portal",
    "The same words work as /cabbie way ... . Cabbie understands the common waypoint wording so guides need no rewriting; it is not, and does not replace, any other waypoint add-on.",
    "The search window is not available in this session.",
    "The search window is unavailable; use /cabbie go <x> <y> [zone] instead.",
    "There is no instruction to repeat.",
    "there is no map pin set",
    "this client has no map pin",
    "This client offers none of the sounds the cues use.",
    "this quest is not in your quest log",
    "those coordinates could not be resolved",
    "Time slice per frame for route calculation.",
    "Toggle debug output: on|off",
    "Toggle the layout editor for the HUD frames (fallback when Edit Mode is unavailable)",
    "Top centre",
    "Town",
    "Towns",
    "Trainer",
    "Tram",
    "Transport",
    "transports",
    "Travel",
    "travel on foot (%.1f yards per second)",
    "Try Favorites, or Search for a town.",
    "Turn left",
    "Turn around",
    "Turn right",
    "Turn sharply left",
    "Turn sharply right",
    "Places",
    "Type a place name.",
    "Type at least two characters, or open Favourites / Recent for a place you already used.",
    "U-turn",
    "unknown (GetBuildInfo unavailable)",
    "unknown (no data manifest loaded)",
    "unknown (Edit Mode is not ready)",
    "Unknown destination",
    "Unknown preset '%s'. Available: minimal, modern, classic",
    "unknown reason",
    "unknown service type",
    "Unknown zone",
    "Unnamed location",
    "Usage: /cabbie arrow on|off|scale <n>|near_character|below_minimap|top_center|custom",
    "Usage: /cabbie legend on|off",
    "Usage: /cabbie arrow scale <0.5..2>",
    "Usage: /cabbie cues %s on|off",
    "Usage: /cabbie cues on|off|volume <n>|turn on|off|transport on|off|arrival on|off|test|status",
    "Usage: /cabbie cues volume <0..100>",
    "Usage: /cabbie fav remove <number> (see /cabbie fav list)",
    "Usage: /cabbie reset settings|positions|routing|all|<element> (arrow, panel, search, preview, favorites, itinerary)",
    "Usage: /cabbie voice on|off|mute|repeat|list|voice <id>|rate <n>|volume <n>|verbosity <level>|test",
    "Usage: /cabbie voice rate <-10..10>",
    "Usage: /cabbie voice verbosity minimal|normal|detailed",
    "Usage: /cabbie voice voice <id> (see /cabbie voice list)",
    "Usage: /cabbie voice volume <0..100>",
    "Use boats",
    "Use flight paths",
    "Use Hearthstone",
    "Use the client's own map pin as the destination",
    "Use the Deeprun Tram",
    "Use your Hearthstone to return to %s",
    "Use your Hearthstone to return to %s.",
    "Use zeppelins",
    "Uses the game's own waypoint marker for the next point of the route.",
    "v",
    "Vendor",
    "Verbosity",
    "Version",
    "Visual preset for the arrow, panel and windows.",
    "Visuals only, no voice",
    "Voice",
    "Voice %d is not installed (see /cabbie voice list).",
    "Voice guidance",
    "Voice guidance disabled.",
    "Voice guidance enabled, but this client reports no text-to-speech voices.",
    "Voice guidance enabled.",
    "Voice guidance is not available in this session.",
    "Voice guidance is off; type /cabbie voice on first.",
    "Voice guidance muted; queued speech cleared.",
    "Voice guidance: %s (%s). Voice %s, rate %d, volume %d, verbosity %s, %d queued.",
    "Voice guidance: on|off|mute|repeat|list|voice <id>|rate <n>|volume <n>",
    "Voice set to %s.",
    "Voice used for spoken guidance.",
    "Voice verbosity set to %s.",
    "Waypoint: %s",
    "Waypoints forgotten.",
    "Waypoints: /way <x> <y> [zone or title] | /way <zone> <x> <y> [title] | /way <pasted map pin link> | /way pin | /way add <...> | /way clear",
    "What guidance keeps doing while you are in combat.",
    "Where the arrow sits; Custom keeps the position set in Edit Mode.",
    "Without a known path the guide may draw straight legs; turning this off limits routes to known paths.",
    "X",
    "Yards",
    "Yards or metres and kilometres.",
    "You are already at %s; continue your route on foot.",
    "You have arrived at your destination.",
    "You have reached stop %d, %s. Continue to the next stop.",
    "You land at %s.",
    "Your current zone is unknown; add a zone name after the coordinates.",
    "your destination",
    "Your itinerary from last time is still set (%d stop(s)). Type /cabbie start to continue or /cabbie cancel to clear it.",
    "Your trip to %s was replaced by %s. Use '/way add <coordinates>' to keep the trip and add a stop instead.",
    "your position is not available here",
    "Your route continues by flight to %s, but this flight master cannot take you there (undiscovered or not connected).",
    "Your route continues by flight to %s, which this flight master does not offer.",
    "zeppelin",
    "Zeppelin",
    "Zone",
}
for i = 1, #SELF do L[SELF[i]] = SELF[i] end

-- Old keys still used by engine callers: map them to glossary wording so player text stays plain.
L["%s of this route have no verified path (drawn dashed)."] = L["%s of this route is rough direction (drawn dashed)."]
L["%s, then continue %s across open ground for %s (no verified path)"] = L["%s, then continue %s across open ground for %s (rough direction)"]
L["(no verified path nearby)"] = L["(no known path nearby)"]
L["Continue %s across open ground for %s (no verified path)"] = L["Continue %s across open ground for %s (rough direction)"]
L["Continue %s across open ground for %s. There is no verified path here."] = L["Continue %s across open ground for %s. There is no known path here."]
L["Nearest %s by route distance; %d of %d could not be routed and show an unverified path."] = L["Nearest %s by route distance; %d of %d could not be routed and show rough direction."]
L["No verified path exists between these points; the whole route is drawn dashed."] = L["No known path exists between these points; the whole route is rough direction (dashed)."]
L["Prefer verified paths"] = L["Prefer known paths"]
L["Straight line (no verified path)"] = L["Straight line (rough direction)"]
L["Without verified ground data the router may draw straight legs; turning this off limits routes to verified paths."] = L["Without a known path the guide may draw straight legs; turning this off limits routes to known paths."]
L["Prefer roads and verified paths"] = L["Prefer roads and known paths"]

-- Quest support (Nav/QuestData.lua, UI/QuestPanel.lua, UI/QuestMap.lua).
-- Kept as its own block because it arrived as one feature and a translator can take it as one
-- piece; it registers itself exactly as the list above does.
--
-- Two kinds of quest string are deliberately NOT here. The first is any vanilla quest title or
-- objective text: none is bundled, the client answers for those in Forever's own wording, and a
-- catalogue entry for one would be the 1.12 wording this add-on refuses to ship. The second is the
-- prose Data/QuestIndex.lua carries -- the reasons a quest was dropped, the names of the quality
-- and source codes, the objective kinds. Those come out of a generated file that is rebuilt
-- whenever a source is refreshed, so pinning them here would leave the catalogue naming sentences
-- the data no longer contains. FGPS.L falls back to the key, so they read as their English selves
-- either way.
local QUESTS = {
    "  %d are complete and plausible, %d carry something the builder found suspect.",
    "  %d quests exist only in Forever; %d of them are listed here and %d have a known start.",
    "  Of the %d quests this client lists, %d have a 1.12 record and %d of those are routable end to end.",
    "  not shipped: %d because %s",
    " (inside; no entrance is known)",
    " (inside; routes to the entrance)",
    " - ",
    "%d levels above you",
    "%d more start with another race or class.",
    "%d quests accepted. Select one to see where it starts, what it wants and where it is handed in.",
    "%d quests found.",
    "%d routable quests start in %s.",
    "%s (%s area)",
    "%s (%s area, from later records)",
    "%s (%s area, reported by another source)",
    "%s (%s spot, from later records)",
    "%s (%s spot, reported by another source)",
    "%s (start)",
    "%s (turn-in)",
    "%s (turn-in, from later records)",
    "%s (where it starts)",
    "%s (where the item that starts it drops)",
    "%s (where you picked it up)",
    "%s area, about %d yd across",
    "%s, at the entrance of %s",
    "%s, from later records",
    "%s, from the older version of this quest",
    "%s, reported by another source",
    "%s: the giver hands it to you",
    -- The kind of an objective of the Forever layer, which no source names (QuestData.KindName).
    "objective",
    "unconfirmed",
    "▸ ",
    "▾ ",
    "A kill or collect objective is an area, not a point. Cabbie draws the measured area and labels it with its width, rather than putting a pin in the middle of it.",
    "Cabbie bundles no vanilla quest names. This asks the server for one, from a small budget that is yours to spend.",
    "Cabbie bundles no vanilla quest names; the client answers for them in Forever's own wording. This allows the button that spends part of a small per-session lookup budget to fill in the names of a search result.",
    "Cabbie cannot look a name up right now (%s).",
    "Cabbie does not ship quest names for vanilla quests - the client supplies them, in Forever's own wording. Search by zone or by level, or open a quest once and Cabbie will remember its name. Names known so far: %d of %d.",
    "Cabbie quests",
    "Cabbie ships %d fully routable quests: a known giver, a known turn-in and every objective placed.",
    "Confirmed on this client.",
    "Draw objective areas",
    "Every one of them is a 1.12 record. That the quest exists was checked against this client's own list; that its giver has not moved was not.",
    "Find a quest",
    "Forever quest: start only",
    "From 1.12 records. Not confirmed in Forever - it may have moved or changed.",
    "Go to an objective",
    "Go to the start",
    "Go to the turn-in",
    "Include Forever's own quests in search",
    "My quests",
    "Look up %d names (%d left)",
    "No bundled record for this quest.",
    "No routable quest matches that.",
    "No stops yet. Open Search and press Add stop, or right-click a place on the map.",
    "Offer to look quest names up on the server",
    "Open the quest panel",
    "Or open Search for a town, inn, or flight master.",
    "Pins for the quests you have accepted and for a quest you searched for and selected. Never for quests you have not taken.",
    "Quest %d",
    "Quest data is not installed in this copy of Cabbie.",
    "Quest data is not installed in this copy of Cabbie; only what the client reports is shown.",
    "Quest help",
    "Quest help: quests [zone|level|name] | quests about",
    "Quest names are not bundled: the client answers for them in Forever's own wording. Names known so far: %d of %d.",
    "Quest pins on the minimap",
    "Quest pins on the world map",
    "Quests that exist only in Forever. Cabbie knows a name and sometimes where they start, never a turn-in or an objective, and says so.",
    "Reported for Forever by another source, not confirmed on this client.",
    "Select a quest first.",
    "The quest panel is not available right now.",
    "The quest panel, quest pins and quest search. Turning this off leaves the bundled quest data loaded but unused.",
    "The quest window is unavailable; type /cabbie quests about for what the data says.",
    "Where it is handed in",
    "Where it starts",
    "Your quest log is empty.",
    "Zone, level, level band, or a quest name you have seen",
    "another class starts this quest",
    "another continent",
    "another race starts this quest",
    "level %d",
    "level %d (requires %d)",
    "needs level %d",
    "requires level %d",
    "starts in %s",
    "starts inside a dungeon",
    "the bundled quest records are not installed in this copy of Cabbie",
    -- Whether a character can take a quest now (QuestData.CanTake).
    "another class takes this quest",
    "another quest of its group is done or taken",
    "another race takes this quest",
    "is for characters up to level %d",
    "is given during a holiday only",
    "it is in your quest log",
    "needs %s at %d",
    "needs a skill, and whether you have it cannot be told",
    "needs a standing with a faction, and how much is not known",
    "needs another quest done first: %s",
    "needs another quest in your quest log: %s",
    "needs one of %d other quests done first",
    "nothing is known of this quest",
    "the other side takes this quest",
    "the record's rule for classes does not know your class",
    "the record's rule for races does not know your race",
    "the record's rule for races is doubtful for this quest",
    "the source for Forever's own quests may not list every condition",
    "this quest was issued again, and who may take the new version is not known",
    "whether you have done this quest cannot be told",
    "whether your side may take this quest cannot be told",
    "you have done this quest",
    "your level cannot be told",
}
for i = 1, #QUESTS do L[QUESTS[i]] = QUESTS[i] end

-- Sentences added after the first catalogue (sharing and following, measured travel times, riding a
-- transport, quest routes that follow progress, heights). They were found by comparing every
-- L["..."] the code looks up with the lists above; FGPS.L falls back to the key, so they always
-- read correctly in English, but a translator only sees what is listed here.
local LATER = {
    "  %d more ship as partial rows: a known giver and a known turn-in, and an objective whose place is not known.",
    "  %d more ship with one known end: only where they are handed in, or only where they are given.",
    "  %s (position not available)",
    "  %s: %.1f yards per second over %d samples",
    "  %s: %.1f yards per second over %d samples (not used yet, %d needed)",
    "  %s: nothing measured yet",
    "  flights: %d path(s) timed from %d real ride(s)",
    "  one known end: %d because %s",
    "  partial row: %d because %s",
    "  teleports: cast and loading times for %d of them",
    "  transports: departure times known for %d dock(s)",
    "%d more have an objective whose place is not known.",
    "%d more have no known hand-in.",
    "%d of them have an objective whose place is not known.",
    "%d of them have no known giver or no known hand-in.",
    "%s (%s spot)",
    "%s (graveyard)",
    "%s away in a straight line",
    "%s cross open ground from one place where creatures are known to stand to the next; nobody has walked the way between them.",
    "%s cross open ground on a way that keeps off cliffs and deep water; trees, rocks and fences along it are not known.",
    "%s follow ground, floors and halls read from the game's own world.",
    "%s follow roads known from the game's signposts; the line is drawn straight between junctions, so it cuts corners.",
    "%s follow roads traced from the ground of the game world.",
    "%s from %s",
    "%s has failed, so the route to it has ended.",
    "%s has left your quest log, so the route to it has ended.",
    "%s is complete, but no route can lead to where it is handed in: %s. The route to it has ended.",
    "%s is heading to %s. Type /cabbie accept to go there too, or /cabbie decline to ignore it.",
    "%s is in your quest log now, so the route to where it starts has ended.",
    "%s is no longer in your group; following stopped.",
    "%s of this route is rough direction (drawn dashed on the maps); expect obstacles.",
    "%s spot",
    "%s swim across water read from the game's own world.",
    "%s to %s",
    "%s, %s",
    "%s, then continue %s across open ground for %s",
    "%s: objective place not known",
    "%s: that objective is done, but no route can lead to the next step: %s. The route to it has ended.",
    "%s: that objective is done. Where the next one is found is not known, so the route to it has ended.",
    "Accept a destination somebody shared",
    "Allow shortcuts off the road",
    "Board the %s to %s",
    "Boat or zeppelin icon: where you board; the label beside it names the far side",
    "Cabbie does not know which flight paths you have in %s yet, so routes leave out the flights there. Talk to a flight master there once and it will use the ones you really have.",
    "Cabbie does not know which flight paths you have yet, so routes leave flights out. Talk to any flight master once and it will use the ones you really have.",
    "Cabbie:",
    "Clear Cabbie",
    "Clear everything Cabbie has set: the route, the preview, every stop and the map markers",
    "Clear route",
    "Cleared. No route and no stops are set. Undo for %d seconds (/cabbie undo).",
    "Continue %s across open ground for %s",
    "Continue %s across open ground for %s.",
    "Restore the trip cleared in the last 30 seconds",
    "Nothing to undo (the clear is older than 30 seconds).",
    "Nothing to undo.",
    "Restored the cleared trip.",
    "Coloured line: flight, boat, zeppelin or elevator",
    "Dotted coloured line: flight, boat or zeppelin",
    "Could not post to %s chat: %s",
    "Dashed line: rough direction",
    "Auction houses of the zone you are looking at get a small icon on the world map. Left-click one to route there.",
    "Banks of the zone you are looking at get a small icon on the world map. Left-click one to route there.",
    "Boat docks and zeppelin towers of the zone you are looking at get a small icon on the world map. Left-click one to route there.",
    "Dungeon entrances of the zone you are looking at get a small icon on the world map. Left-click one to route there.",
    "Every town of the zone you are looking at gets a small icon on the world map. Left-click one to route there. Towns of the other faction are dimmed.",
    "Flight masters of the zone you are looking at get a small icon on the world map. Left-click one to route there.",
    "Graveyards of the zone you are looking at get a small icon on the world map. Left-click one to route there.",
    "Inns of the zone you are looking at get a small icon on the world map. Left-click one to route there.",
    "Mailboxes of the zone you are looking at get a small icon on the world map. Left-click one to route there.",
    "Repair vendors of the zone you are looking at get a small icon on the world map. Left-click one to route there.",
    "Stable masters of the zone you are looking at get a small icon on the world map. Left-click one to route there.",
    "Trainers of the zone you are looking at get a small icon on the world map. Left-click one to route there.",
    "Vendors of the zone you are looking at get a small icon on the world map. Left-click one to route there. Busy cities have many, so this starts off.",
    "Flying to %s",
    "Follow a group member: follow <name>|off",
    "Following %s. Type /cabbie follow off to stop.",
    "Forgot the measurements for: %s.",
    "Go to the next step",
    "Ignore a destination somebody shared",
    "Click: guide me here",
    "Location",
    "Measured rather than modelled: %s.",
    "Measured travel times (everything else comes from the model):",
    "Measured travel times: calibrate [reset ...]",
    "Navigate back to your corpse",
    "No destination set; there is nothing to share.",
    "No known path nearby leads down here: the way on is about %d yd below the straight line.",
    "No known path nearby leads down here: the way on may be about %d yd below you.",
    "No known path nearby leads up here: the way on is about %d yd above the straight line.",
    "No known path nearby leads up here: the way on may be about %d yd above you.",
    "No longer following %s.",
    "Nobody has shared a destination with you recently.",
    "Nobody in your group is called '%s'.",
    "Off (the default): routes keep to the road wherever one goes, and leave it only to reach a place off the road. On: a route may cut across open ground when that is clearly quicker. Needs \"Prefer roads and known paths\".",
    "On the minimap a solid dot is a known path and a larger hollow dot is a rough direction.",
    "Post your destination to party chat",
    "Prefer roads and known paths",
    "Removes the route, the preview, every stop and their markers. Nothing stays set.",
    "Ride the %s to %s",
    "Ride the elevator",
    "Right-click: add as a stop",
    "Right-click: clear the route and every stop",
    "Right-click: clear the trip",
    "Routes stick to roads and known paths unless the way round is much longer. Open ground, wandering creature paths and guessed stretches cost more. Off: the fastest line, often straight across open ground.",
    "Same as clear",
    "Show auction houses on the world map",
    "Show banks on the world map",
    "Show docks and zeppelin towers on the world map",
    "Show dungeon entrances on the world map",
    "Show flight masters on the world map",
    "Show graveyards on the world map",
    "Show inns on the world map",
    "Show mailboxes on the world map",
    "Show repair vendors on the world map",
    "Show stable masters on the world map",
    "Show towns on the world map (click one to route there)",
    "Show trainers on the world map",
    "Show vendors on the world map",
    "The client can no longer say where %s is; following stopped.",
    "The client will not say where %s is (a different continent, or inside an instance).",
    "The client will not say where your corpse is, so this is the nearest graveyard instead.",
    "The shared destination was ignored.",
    "The way on is well above or below this line.",
    "There is nothing measured called '%s'. Try ground, flights, transports or teleports.",
    "This client does not let add-ons post to chat.",
    "This client will not say where your corpse is and no graveyard is known nearby.",
    "This destination has no position that can be shared.",
    "This is not the %s to %s. A new route follows when you get off.",
    "This is not the transport of your route (%s). A new route follows as soon as you get off.",
    "Alliance",
    "Horde",
    "This place belongs to the Alliance.",
    "This place belongs to the Horde.",
    "Use /cabbie calibrate reset [ground|flights|transports|teleports] to forget measurements.",
    "Use /cabbie follow <name> to navigate to a group member, or /cabbie follow off to stop.",
    "You are not dead; there is no corpse to run to.",
    "You are not following anybody.",
    "42.5  65.1",
    "Map coordinates from 0 to 100. Add a zone name if you are not standing in it, for example 42.5 65.1 Elwynn Forest.",
    "Map pin",
    "Nearby",
    "Town, NPC, or 42.5 65.1",
    "Vendors",
    "Where to",
    "Your corpse",
    "a shared destination",
    "elevator",
    "every objective with a known place is done",
    "flights you have taken before",
    "mounted",
    "objective place not known",
    "on foot",
    "place not known",
    "someone in your group",
    "this quest has failed",
    "the real departure times of the boats on this route",
    "tram",
    "transport",
    "your own cast and loading times",
    "your own ground speed",
    "your own speed %s (%.1f instead of %.1f yards per second, over %d samples)",
}
for i = 1, #LATER do L[LATER[i]] = LATER[i] end

-- The guidance that took the place of the floating arrow and the instruction panel: the Route
-- block and the call-out (UI/Guide.lua, UI/RouteBlock.lua), a place typed after "/cabbie" or "/go"
-- (UI/Go.lua), "Take me there" in the game's quest menus and the Route block's own menu
-- (UI/Menus.lua), and what the corpse popup (Nav/Social.lua) and a Shift-click on the world map
-- (UI/WorldMap.lua) say in the call-out. "Follow my quests" is here with its tooltip, which the
-- old settings page shows (UI/Settings.lua). Kept as its own block, as the quest strings are: it
-- arrived as one feature and a translator can take it as one piece. Four of its sentences are
-- identifier keys further up, because the catalogue had them already: "Arrived at %s"
-- (L.ARROW_ARRIVED), "Paused" (L.NAV_STATE_PAUSED), "Paused: %s" (L.ARROW_PAUSED_REASON) and "Turn
-- around" (L.ARROW_TURN_AROUND). tests/test_locale.lua reads the new modules and fails when one of
-- them looks up a sentence that is not listed.
local GUIDANCE = {
    "'%s' is neither a command nor a place Cabbie knows. /cabbie help lists the commands.",
    "'%s' is neither a command nor enough of a place name to start a route. /cabbie help lists the commands, and %s %s looks for a place.",
    "'%s' is not a command. Did you mean /cabbie %s? /cabbie help lists the commands, and %s %s looks for a place.",
    "(open ground)",
    "A quest route moves on to the next objective and the hand-in, and a click on the round marker beside a quest in the quest list or on the map starts the way to it.",
    "Add a zone name after the two numbers.",
    "Bring the route back",
    "Click for options. Drag to move.",
    "Each of the two numbers goes from 0 to 100.",
    "Finding a new way",
    "Finding the way",
    "Follow my quests",
    "Go to a place by name or by two map numbers",
    "Go to my corpse",
    "No flights yet: visit a flight master.",
    "No flights in %s yet: visit a flight master there.",
    "Going to %s.",
    "No place known for this quest",
    "No place matches '%s'.",
    "No position here",
    "No way found to %s",
    "No zone is called '%s'.",
    "Pause",
    "Reset position",
    "Resume tries again.",
    "Route stopped. Click to bring it back.",
    "Route stopped. Type /cabbie undo within %d seconds to bring it back",
    "Show on map",
    "Stop following my quests",
    "Stop route",
    "Take me there",
    "That spot cannot be reached",
    "The new route starts when this ride ends",
    "Those numbers are not a place on that map.",
    "This quest has failed",
    "This quest's place is inside a dungeon with no known entrance",
    "To %s",
    "Type a place after the command, for example: /go Goldshire",
    "Where the open objective is found is not known. An old record has the hand-in: ask again when the quest is ready.",
    "You are there. The route moves on when this part of the quest is done.",
    "Your corpse cannot be found yet",
}
for i = 1, #GUIDANCE do L[GUIDANCE[i]] = GUIDANCE[i] end

-- Rooms and levels of the walkable surface read from the game's geometry (Nav/Instructions.lua,
-- steps "enter" and "level"): said in the call-out and the Route block like a turn. "Enter %s"
-- takes the room's name as the client writes it.
local LEVELS = {
    "Enter %s",
    "Go down the ramp to the lower level",
    "Go down to the lower level",
    "Go up the ramp to the upper level",
    "Go up to the upper level",
    "Take the stairs down",
    "Take the stairs up",
}
for i = 1, #LEVELS do L[LEVELS[i]] = LEVELS[i] end

-- The search line and the first-run guide (UI/SearchRows.lua, UI/SearchLine.lua): the guide's
-- title and its rows, the words of the "Go to:" line, its key binding and "Go to nearest" in the
-- minimap's menu (UI/Menus.lua). One block, as the guidance above: it arrived as one feature.
-- tests/test_locale.lua reads the two modules and fails when one looks up a sentence that is not
-- listed here.
local SEARCH_LINE = {
    "Class trainer",
    "Click the round marker beside a quest and Cabbie leads you to it",
    "Click to close",
    "Finding the nearest %s",
    "Flights are used once you have visited a flight master",
    "Flights in %s are used once you have visited a flight master there",
    "Go to a place",
    "Go to nearest",
    "Go to:",
    "How to use Cabbie",
    "None found near here",
    "Open the world map and type a place, a quest, or a word like inn or repair",
    "Repair vendor",
    "Right-click a quest in your quest list: Take me there",
    "Shift-click the world map to be guided to that spot",
    "Show how to use Cabbie",
    "The search line is not available in this session.",
    "Type a place, a quest, or a word like inn or repair",
    "Your steps appear beside your quest list. Click the word Route to stop or pause",
}
for i = 1, #SEARCH_LINE do L[SEARCH_LINE[i]] = SEARCH_LINE[i] end

-- The pick-up marks (UI/QuestMarks.lua): the lines of a mark's tooltip beside the sentences
-- QuestData already has (the quest's name, where the place comes from), and the settings
-- checkbox with its tooltip (UI/Settings.lua). tests/test_questmarks.lua reads the module and
-- fails when one of its lookups is not listed.
local PICKUP_MARKS = {
    "A yellow ! on the world map and the minimap where you can take a quest now, as far as the records say. Hover one to see where its place comes from; Shift-click it on the world map to go there.",
    "Level %d",
    "Shift-click: go there",
    "Show quests I can pick up",
}
for i = 1, #PICKUP_MARKS do L[PICKUP_MARKS[i]] = PICKUP_MARKS[i] end

L["Replace"] = "Replace"

L["Keep going"] = "Keep going"

L["Add as stop"] = "Add as stop"

L["Replace the route to %s?"] = "Replace the route to %s?"

L["During a trip, left-click asks before replacing the route"] = "During a trip, left-click asks before replacing the route"
L["Go to corpse"] = "Go to corpse"
L["Not now"] = "Not now"
L["You are dead. Guide me back to my corpse?"] = "You are dead. Guide me back to my corpse?"

L["Resume"] = "Resume"

L["Arrow"] = "Arrow"

L["Step list"] = "Step list"

L["Map marks"] = "Map marks"

L["Routing"] = "Routing"

L["Developer"] = "Developer"

L["Stop %s: %s"] = "Stop %s: %s"
L["Shift+Right-click to remove"] = "Shift+Right-click to remove"

L["Quest"] = "Quest"
L["Objective"] = "Objective"
L["Turn-in"] = "Turn-in"

L["direct"] = "direct"

L["*"] = "*"

L["Unfavorite"] = "Unfavorite"

L["Large"] = "Large"

L["Text size"] = "Text size"

L["Try Favorites, or Search for a town."] = "Try Favorites, or Search for a town."

L["No stops yet. Open Search and press Add stop, or right-click a place on the map."] =
    "No stops yet. Open Search and press Add stop, or right-click a place on the map."

L["Or open Search for a town, inn, or flight master."] = "Or open Search for a town, inn, or flight master."

L["Map"] = "Map"
L["Place icons"] = "Place icons"

-- Strings the modules read as L["..."] that were missing here (2026-10-17: Navigator, Cost, QuestData,
-- MapShot, Preview, QuestMap, Search, WorldMap); tools/check_locale.py now fails such a string.
L["%s cut across city streets and squares in straight lines checked against the city map; nobody has walked those exact lines."] = "%s cut across city streets and squares in straight lines checked against the city map; nobody has walked those exact lines."
L["Continue"] = "Continue"
L["Your trip from last time is still set (%d stop(s)). Continue or clear?"] = "Your trip from last time is still set (%d stop(s)). Continue or clear?"
L["Search by zone (\"Westfall\"), by level (\"24\" or \"20-30\"), or by a quest name you have already seen. %d routable quests are bundled."] = "Search by zone (\"Westfall\"), by level (\"24\" or \"20-30\"), or by a quest name you have already seen. %d routable quests are bundled."
L["Maintainer tool: screenshot every zone and city map for road tracing; mapshot stop cancels"] = "Maintainer tool: screenshot every zone and city map for road tracing; mapshot stop cancels"
L["Map pictures are not available in this client."] = "Map pictures are not available in this client."
L["Map pictures cannot start in combat."] = "Map pictures cannot start in combat."
L["Map pictures done: %d screenshots are in the game's Screenshots folder."] = "Map pictures done: %d screenshots are in the game's Screenshots folder."
L["Map pictures stopped after %d screenshots."] = "Map pictures stopped after %d screenshots."
L["Map pictures stopped after %d screenshots: the world map was closed or combat began."] = "Map pictures stopped after %d screenshots: the world map was closed or combat began."
L["Map pictures: %d maps, about %d seconds. Leave the map open; /cabbie mapshot stop cancels."] = "Map pictures: %d maps, about %d seconds. Leave the map open; /cabbie mapshot stop cancels."
L["Open the world map first, then type /cabbie mapshot again."] = "Open the world map first, then type /cabbie mapshot again."
L["%s of this route has no verified path (drawn dashed on the maps); expect obstacles."] = "%s of this route has no verified path (drawn dashed on the maps); expect obstacles."
L["%s of this route is a guessed way over open ground without verified ground data (drawn dashed on the maps); expect obstacles."] = "%s of this route is a guessed way over open ground without verified ground data (drawn dashed on the maps); expect obstacles."
L["%s unverified"] = "%s unverified"
L["(no verified path)"] = "(no verified path)"
L["No verified path was found; this is unverified guidance drawn dashed."] = "No verified path was found; this is unverified guidance drawn dashed."
L["Unconfirmed place"] = "Unconfirmed place"
L["No favorites yet. Select a result and press Favorite."] = "No favorites yet. Select a result and press Favorite."
L["No quests with a known location."] = "No quests with a known location."
L["Weapon master"] = "Weapon master"
L["Stop"] = "Stop"

-- The continents' maps ship as folders of their own that Cabbie loads when needed (Core/DataLoad.lua).
L["Cabbie cannot route in %s: its map add-on, %s, is not installed. Reinstall Cabbie with all its folders."] = "Cabbie cannot route in %s: its map add-on, %s, is not installed. Reinstall Cabbie with all its folders."
L["Cabbie cannot route in %s: %s is turned off. Turn it on in the AddOns list at character select."] = "Cabbie cannot route in %s: %s is turned off. Turn it on in the AddOns list at character select."
L["%s is from another version of Cabbie. Reinstall Cabbie so that all its folders match."] = "%s is from another version of Cabbie. Reinstall Cabbie so that all its folders match."
L["The map of %s did not finish loading. Type /reload to try again."] = "The map of %s did not finish loading. Type /reload to try again."
L["Loading the map of %s when you leave combat."] = "Loading the map of %s when you leave combat."
