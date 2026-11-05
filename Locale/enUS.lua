













local ADDON_NAME, FGPS = ...

local L = setmetatable({}, { __index = function(_, key) return key end })
FGPS.L = L


L.ADDON_TITLE = "Cabbie"
L.VERSION_LINE = "Version %s on client %s (build %s, interface %d)%s"
L.NOT_FOREVER = " - warning: this client does not look like World of Warcraft: Forever"
L.BOOT_FAILED_MODULES = "%d of Cabbie's parts failed to start; type /cabbie log for details."
L.LOG_EMPTY = "Log is empty."
L.LOG_HEADER = "Log buffer (%d entries, oldest first):"


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
L.HELP_MARK = "Mark the route you are on, or the last one, with a note: /cabbie mark the harbor line went through a building"
L.TRIP_SUMMARY = "Route: %s. Longest stretch %d yd. Off route %d. Recalculated %d."
L.TRIP_NONE = "No finished route to report yet."
L.TRIP_MARKED = "Marked this route: %s"
L.TRIP_NO_MARK = "No route to mark yet. Start a route first."


L.SETUP_TITLE = "Welcome to Cabbie"
L.SETUP_HELP = "Show the welcome window"
L.SETUP_INTRO = "Cabbie guides you to a place and never moves your character for you. While a route is set, the next turn shows at the top of your screen, and Settings can also show your steps beside the quest list. Shift-click the world map or type a place into the search at its top left to be guided there, and right-click a quest in your quest list and choose Guide Me to go to it."
L.SETUP_LATER = "Everything else has a sensible default. Change it any time in Settings, and type /cabbie setup to see this again."
L.SETUP_DONE = "Done"
L.SETUP_SETTINGS = "Settings..."


L.PERF_HEADER = "Performance report (instrumentation %s, guidance %s, frame budget %d ms)"
L.PERF_ON = "on"
L.PERF_OFF = "off"
L.PERF_LABEL_LINE = "  %-14s count %6d  total %8.2f ms  avg %6.3f ms  max %6.3f ms"
L.PERF_NO_LABELS = "  no timed sections recorded yet"
L.PERF_MEMORY = "  memory: addon %.0f KB, Lua heap %.0f KB (sampled %.0f s ago)"
L.PERF_METRIC = "  profiler %s: %.3f"




L.PERF_TRIPS_ALLOCATED = "  trips: %d measured, %.1f KB allocated per trip on average, %.1f KB worst (allocated, not collected - type /cabbie perf trip for retained memory)"
L.PERF_RETAINED_BASELINE = "Retained memory baseline taken after a full collection: %.1f KB. Complete your routes, then type /cabbie perf trip again."
L.PERF_RETAINED_REPORT = "Retained since the baseline: %.1f KB, routes since then: %d, %.1f KB per route (budget: 50 KB over 20 routes)."
L.PERF_RETAINED_NO_TRIPS = "Retained since the baseline: %.1f KB, but no route has finished yet."
L.PERF_SCHEDULER = "  scheduler: %d queued, %d completed, %.2f ms spent in slices"
L.PERF_GUIDANCE_ON = "Guidance work enabled."
L.PERF_GUIDANCE_OFF = "Guidance work disabled for measurement; type /cabbie perf toggle to re-enable."
L.PERF_RESET = "Performance counters cleared."
L.PERF_INSTRUMENT_ON = "Performance instrumentation enabled."
L.PERF_INSTRUMENT_OFF = "Performance instrumentation disabled."
L.PERF_SAMPLED = "Memory sample recorded."
L.PERF_ROUTES_NONE = "  no route timings recorded yet"
L.PERF_ROUTE_LINE = "  %s, continent %s: cpu %.0f ms, wall %.0f ms, %d frames, %d expansions, budget %.1f ms, %.0f fps"


L.SELFTEST_HEADER = "Self test: %d checks - %d pass, %d note, %d warn, %d fail, %d skipped"
L.SELFTEST_LINE = "  [%s] %-13s %s"
L.SELFTEST_RUNNING = "Self test running..."
L.SELFTEST_SAVED_FIRST = "nothing to compare yet: this is the first session Cabbie remembers. After a /reload this line says 2 sessions if the game kept Cabbie's saved data. Not a fault in Cabbie: the Forever beta client forgets every addon's saved data when the game is restarted, and on some installs at a /reload as well (KNOWN_LIMITATIONS section 8)."
L.SELFTEST_SAVED_RELOAD_LOST = "the game reloaded the interface and Cabbie's saved data came back empty, so the client did not keep it through the /reload (unless Cabbie was switched on just before it). Not a fault in Cabbie: while the client does this, favourites and your known flight points start over at every /reload and every restart (KNOWN_LIMITATIONS section 8)."
L.REPORT_WRITTEN = "Diagnostic snapshot written to CabbieDB.report (SavedVariables\\Cabbie.lua, saved on /reload or on exit): settings off default: %d, log lines: %d, self test %d pass / %d warn / %d fail."
L.REPORT_NO_DB = "Cannot write a report: the saved variables are not available."


L.UNIT_YARDS = "yd"
L.UNIT_METERS = "m"
L.UNIT_KILOMETERS = "km"
L.TIME_SECONDS = "%ds"
L.TIME_MINUTES = "%dm %ds"
L.TIME_HOURS = "%dh %dm"
L.UNKNOWN_VALUE = "?"


L.NAV_STATE_IDLE = "Idle"
L.NAV_STATE_PREVIEWING = "Previewing"
L.NAV_STATE_ACTIVE = "Navigating"
L.NAV_STATE_PAUSED = "Paused"
L.ARROW_TURN_AROUND = "Turn around"
L.ARROW_PAUSED_REASON = "Paused: %s"
L.ARROW_ARRIVED = "Arrived at %s"
L.ROUTE_UNVERIFIED_WARNING = "Parts of this route cross open ground and are drawn dashed."
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








local SELF = {
    " (available in %s)",
    "%.1f kilometers",
    "%d meters",
    "%d result",
    "%d results",
    "%d stop",
    "%d stops",
    "%d transfer",
    "%d transfers",
    "Waypoints forgotten: %d. The route in progress is still running; type /cabbie cancel to stop it.",
    "%d metres",
    "%d yards",
    "%s %s",
    "No matching destinations.",
    "No recent destinations.",
    "Type at least two characters.",
    "%s (%d stops)",
    "%s (next waypoint)",
    "%s at %s",
    "%s can only be reached by %s; enable them in the transport settings or check the faction restriction.",
    "%s is reachable only through another continent's transports, which are currently disabled.",
    "%s of this route is open ground (drawn dashed).",
    "%s of this route is open ground (drawn dashed on the maps); expect obstacles.",
    "%s open ground",
    "%s toward %s",
    "%s, entering %s",
    "%s, then continue %s across open ground for %s",
    "%s: %s",
    "(adjusted %d yd)",
    "(open ground)",
    "... and %d more steps",
    "100% mount",
    "60% mount",
    "%s trainer",
    "%s (your class)",
    "Any Trainer",
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
    "Allow open ground",
    "Alt + Left-click",
    "Alternatives",
    "Alternatives are not available right now.",
    "An extra click that sets a destination on the world map. Choose its modifier and mouse button, or switch it off. Shift + Left-click always goes to the spot at once.",
    "and",
    "Area",
    "Arrival radius (yards)",
    "Arrive at %s",
    "Arrived at stop %d.",
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
    "Bear left",
    "Bear right",
    "Board %s",
    "Board the %s to %s at %s (%s)",
    "Board the %s to %s. The crossing takes %s.",
    "Board the tram at %s (%s)",
    "Board the tram. The ride takes %s.",
    "Board tram",
    "boat",
    "Boat",
    "Boss",
    "build",
    "Cabbie",
    "Cabbie does not answer /way while \"Answer the /way command\" is off in its settings. /cabbie way still works.",
    "Cabbie knows no way yet from this place inside %s.",
    "Cabbie knows no way yet to this place inside %s.",
    "Move Cabbie's arrow. The arrow keys move the selection a little (with Shift, more).",
    "Cabbie voice guidance is working.",
    "Cabbie's recorded voice",
    "Capital city",
    "Cast %s",
    "Cast %s.",
    "Cheap timers behind /cabbie perf.",
    "Clear",
    "Clear recent destinations",
    "Client %s (%s), Edit Mode: %s",
    "Client build",
    "Close",
    "Settings",
    "Switches off the extra click only. Shift + Left-click still goes to the spot.",
    "Search",
    "Nothing to pause or resume.",
    "No route to pause.",
    "Guidance is already paused.",
    "Nothing is paused.",
    "Pause or resume guidance",
    "Keep planning",
    "Closes this window. Your stops stay set.",
    "Colour-blind friendly",
    "Computing alternatives...",
    "Confirm",
    "Consider teleport spells",
    "Consider the Hearthstone",
    "Routes may start with your Hearthstone when that is quicker. Cabbie learns where it takes you the first time you use it or make an inn your home. The route preview says when it is left out, and why.",
    "Continue %s",
    "Continue %s across open ground for %s",
    "Continue %s across open ground for %s.",
    "Coordinates",
    "coordinates must be between 0 and 100",
    "Could not add favorite (%s).",
    "Could not add that waypoint: %s",
    "Could not resolve those coordinates%s",
    "Could not use that waypoint: %s",
    "Ctrl + Right-click",
    "Cue '%s' is now %s.",
    "Cue volume set to %d.",
    "Custom",
    "Danger margin (levels)",
    "Data version",
    "Debug output",
    "Debug output disabled.",
    "Debug output enabled.",
    "Destination",
    "Detailed",
    "Details",
    "Detect automatically",
    "Disembark",
    "Disembark at %s",
    "Disembark at %s.",
    "Distance %s",
    "Distance from the destination at which you count as arrived.",
    "Distance units",
    "Dock",
    "Done",
    "Drag to move. The arrow keys move the selection a little (with Shift, more).",
    "Draw route hints on the minimap",
    "Show the minimap button",
    "A compass button on the minimap opens search without typing /cabbie.",
    "Draw the route on the world map",
    "Dungeon",
    "Dungeons",
    "Edit Mode",
    "Edit Mode is open; move Cabbie's arrow there.",
    "Elevator",
    "Elevator down",
    "Elevator up",
    "Enter coordinates as: x y [zone], for example 42.5 65.1 Elwynn Forest or Elwynn Forest 42.5, 65.1 (values 0-100; zone may be a name or map id)",
    "Entering %s",
    "Entering %s.",
    "Extra world map click",
    "Fastest",
    "Favorite %d removed.",
    "Favorite renamed to %s.",
    "Favorites",
    "Fewer transfers",
    "Flight",
    "Flight from %s to %s",
    "Flight master",
    "flight point",
    "Fly to %s",
    "Follow the ramp",
    "Follow the road toward %s",
    "General",
    "Go",
    "Go through %s",
    "Go through %s.",
    "Graveyard",
    "Guidance",
    "Guidance work is switched off for a measurement; type /cabbie perf toggle first.",
    "Head %s",
    "Head %s from %s",
    "Hearthstone",
    "Hearthstone not used: Cabbie learns where your hearthstone takes you the first time you use it or bind at an inn.",
    "Hearthstone not used: no hearthstone in your bags.",
    "Hearthstone not used: on cooldown for %d min.",
    "Hide all guidance",
    "How far from the route you can stray before it is recalculated.",
    "In %s, %s",
    "In combat",
    "Inn",
    "Innkeeper",
    "instance %d",
    "dungeons and raids",
    "interface",
    "It is available in %s.",
    "Stops",
    "Stops window; skip|clear",
    "Keep everything (visuals and voice)",
    "Key bindings (set them in the game's Key Bindings interface, under Cabbie):",
    "Land at %s",
    "Landmark",
    "Landmarks",
    "Layout editor closed.",
    "Layout editor opened. Drag to move things, then press Done or Escape.",
    "Leave elevator",
    "Leave the elevator at %s",
    "Leave the tram at %s",
    "Leave the tram at %s.",
    "Leave tram",
    "Levels above yours before an area counts as dangerous.",
    "List the Cabbie key bindings and the keys they are on",
    "Longest stretch across open ground (yards)",
    "Longest stretch across open ground a route may include. 0 turns these stretches off. The last-resort line across open ground is not affected.",
    "Mailbox",
    "Make a U-turn",
    "Make this inn your home",
    "Map pin",
    "Map pin guidance paused because you changed the tracked objective; it resumes with the next route.",
    "Map position",
    "Metric",
    "Minimal",
    "Minimal: turns only. Normal: advance notices and turns. Detailed: every step and zone change.",
    "native integration available",
    "Navigation is not available right now.",
    "Nearest",
    "Nearest %s by route distance.",
    "Nearest %s by route distance; %d of %d could not be routed and show open ground.",
    "Never mounted",
    "Next waypoint on the way to the quest",
    "No %s found: %s.",
    "No arrival position is known for this spell.",
    "No Rune of Teleportation in your bags; the teleport is not used for routing.",
    "no boats",
    "No boats",
    "No current destination to add. Set a destination first.",
    "No destination is set. Use /cabbie go or the search window first.",
    "No destination set.",
    "No destination was given.",
    "No distinct alternatives were found.",
    "No extra click",
    "No favorite %d; see /cabbie fav list.",
    "No favorite matches '%s'.",
    "No favorites yet.",
    "no flights",
    "No flights",
    "No known transport connects %s and %s.",
    "no map location is known for this quest",
    "No navigation data is available for %s.",
    "no quest is being tracked",
    "no quest was given",
    "no sound available in this client",
    "No text-to-speech voices are installed.",
    "None reported by the game",
    "No turn-by-turn steps are available for this route.",
    "No road joins these points; the whole route is drawn dashed.",
    "No road was found; this route is drawn dashed.",
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
    "Play a sample",
    "Portal",
    "Position of '%s' restored to its default.",
    "prefer roads",
    "Prefer roads",
    "Preset colours",
    "Show route",
    "Prints diagnostics to chat and forwards errors to the error handler.",
    "Quest",
    "Quest lookup failed.",
    "Quest lookup is not available right now.",
    "quest tracking is not available in this client",
    "Quests",
    "Raid",
    "Ready to turn in",
    "Recent",
    "Recent destinations are not available right now.",
    "Recent destinations cleared.",
    "Recent destinations; recent clear",
    "Removed from favorites: %s",
    "Removed the stop %s: its waypoint was removed.",
    "Rename",
    "Repair",
    "Reset",
    "Reset all UI positions",
    "Reset favorites window position",
    "Reset stops window position",
    "Reset preview window position",
    "Reset search window position",
    "Reset settings",
    "Reset settings|positions|routing|all|<element>",
    "Reset to default",
    "Resume guidance",
    "Room",
    "Route",
    "Route computation budget (ms per frame)",
    "Route preview",
    "Route updated.",
    "Route cleared.",
    "No route set.",
    "Routing and transport preferences restored to defaults.",
    "Routing preferences cannot be reset in this session (the settings store did not load).",
    "same distance",
    "selected",
    "Search failed; type /cabbie log for details.",
    "Search is not available right now.",
    "Searching for the nearest %s...",
    "Select %s to continue your route.",
    "Select a destination first.",
    "Service",
    "Service search failed; type /cabbie log for details.",
    "Set a destination from waypoint coordinates or a pasted map pin link",
    "Settings and frame positions restored to defaults; routing preferences, favorites and recents were kept.",
    "Sharp left",
    "Sharp right",
    "Shift + Right-click",
    "Shortest time between recalculations (seconds)",
    "Show your route's steps beside the quest list",
    "The time and distance left, and the next few steps of your route, in a list beside the game's quest list. Drag it by its first line to move it. The arrow at the top of the screen guides you without it.",
    "Show the in-world waypoint marker",
    "Show the route preview for the current destination",
    "Show the turn call-out",
    "Show version, data version, client build and Edit Mode status",
    "Skip stop",
    "Says one short sentence in the voice chosen on this page, with voice guidance on or off.",
    "Speak turn instructions out loud.",
    "Speaking with Cabbie's recorded voice",
    "Off (the default): Cabbie's own recorded voice, the same on every computer. On: the voice chosen in the game's text-to-speech settings, which also says place names. Greyed out while the game reports no text-to-speech voice; the recorded one speaks then.",
    "Use the game's text-to-speech voice",
    "Speech rate",
    "Speech rate set to %d.",
    "Speech volume",
    "Speech volume set to %d.",
    "Rate and volume apply to the game's voice only.",
    "Speed used for estimates when mount detection is uncertain.",
    "Spell not known yet.",
    "Stable master",
    "Start",
    "Start (or resume) navigation for the previewed route",
    "Stay aboard",
    "Stay aboard at %s",
    "Steps",
    "stop %d",
    "Stop %d",
    "Stop %d: %s",
    "Stops reordered.",
    "Open ground",
    "Routes may cross open ground; recalculating.",
    "Take elevator",
    "Take portal",
    "Take the elevator down to %s",
    "Take the elevator to %s",
    "Take the elevator up to %s",
    "Take the flight from %s to %s (%s)",
    "Talk to the flight master and take the flight to %s. The flight takes %s.",
    "Teleport",
    "text-to-speech available",
    "That is not a coordinate pair. Try: %s 42.5 65.1 Elwynn Forest",
    "that map pin is the one Cabbie placed for the current route",
    "that map position cannot be used as a destination",
    "That map position cannot be used as a destination%s",
    "that place",
    "that quest location is no longer listed",
    "The cursor is not over the world map.",
    "The game reports no text-to-speech voice on this computer, so the game voice settings below are greyed out. Cabbie's recorded voice needs nothing installed. Play a sample says one short sentence in it.",
    "that part of Cabbie is not ready",
    "the dock",
    "the far side",
    "The route in progress was replaced by %s. Use '%s add <coordinates>' to keep the route and add a stop instead.",
    "The route to %s was cancelled: its waypoint was removed.",
    "The layout editor cannot be opened during combat.",
    "the navigator did not accept the waypoint",
    "the objective is inside a dungeon or building; navigate to its entrance instead",
    "The options panel is not available in this client; use /cabbie help for the command list.",
    "The options panel opens when you leave combat.",
    "the portal",
    "The same words work as /cabbie way ... . Cabbie understands the common waypoint wording so guides need no rewriting; it is not, and does not replace, any other waypoint add-on.",
    "The search window is not available in this session.",
    "The search window is unavailable; use /cabbie go <x> <y> [zone] instead.",
    "There is no instruction to repeat.",
    "That instruction has no recorded voice.",
    "there is no map pin set",
    "this client has no map pin",
    "This client offers none of the sounds the cues use.",
    "this quest is not in your quest log",
    "those coordinates could not be resolved",
    "a lookup is still running",
    "it is already a favorite",
    "name lookups are switched off in the settings",
    "no quest is chosen",
    "not during a fight",
    "that place cannot be saved",
    "the favorites list is full",
    "the lookups for this session are used up",
    "the request was not understood",
    "the search was stopped",
    "this game client cannot look names up",
    "wait a moment before the next one",
    "Time slice per frame for route calculation.",
    "Toggle debug output: on|off",
    "Move Cabbie's arrow on the screen (when the game has no Edit Mode)",
    "Town",
    "Towns",
    "Trainer",
    "Tram",
    "Transport",
    "transports",
    "Travel",
    "travel on foot (%.1f yards per second)",
    "Turn left",
    "Turn right",
    "Turn sharply left",
    "Turn sharply right",
    "Places",
    "U-turn",
    "unknown (GetBuildInfo unavailable)",
    "unknown (no data manifest loaded)",
    "unknown (Edit Mode is not ready)",
    "Unknown destination",
    "unknown reason",
    "unknown service type",
    "Unnamed location",
    "Usage: /cabbie legend on|off",
    "Usage: /cabbie cues %s on|off",
    "Usage: /cabbie cues on|off|volume <n>|turn on|off|transport on|off|arrival on|off|test|status",
    "Usage: /cabbie cues volume <0..100>",
    "Usage: /cabbie fav remove <number> (see /cabbie fav list)",
    "Usage: /cabbie reset settings|positions|routing|all|<element> (search, preview, favorites, stops)",
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
    "Voice guidance: %s (%s). Verbosity %s, %d queued.",
    "Voice guidance: on|off|mute|repeat|list|voice <id>|rate <n>|volume <n>|verbosity <level>|test",
    "Voice sample",
    "Voice set to %s.",
    "Voice used for spoken guidance.",
    "Voice verbosity set to %s.",
    "Waypoint: %s",
    "Waypoints forgotten.",
    "Waypoints: %s <x> <y> [zone or title] | %s <zone> <x> <y> [title] | %s <pasted map pin link> | %s pin | %s add <...> | %s clear",
    "What guidance keeps doing while you are in combat.",
    "The guide may draw a straight leg across open ground. Turning this off keeps routes on roads.",
    "X",
    "Yards",
    "Yards or metres and kilometres.",
    "You are already at %s; continue your route on foot.",
    "You have arrived at your destination.",
    "You have reached stop %d, %s. Continue to the next stop.",
    "You land at %s.",
    "Your current zone is unknown; add a zone name after the coordinates.",
    "your destination",
    "Stops kept from last time: %d. Type /cabbie start to continue or /cabbie cancel to clear them.",
    "Your route to %s was replaced by %s. Use '%s add <coordinates>' to keep the route and add a stop instead.",
    "your position is not available here",
    "Use spare frame time for routes",
    "When the frame rate is high and you are not in combat, in a cutscene, or looking at the flight map, route calculation may use a longer slice of each frame.",
    "Longest route slice (ms per frame)",
    "Upper limit on that longer slice. The shorter budget above is used in combat, in a cutscene, below 30 frames a second, or with the flight map open.",
    "Your route continues by flight to %s, but this flight master cannot take you there (undiscovered or not connected).",
    "Your route continues by flight to %s, which this flight master does not offer.",
    "zeppelin",
    "Zeppelin",

    "Answer the /way command",
    "Audio cues instead of speech",
    "Boarding a boat or zeppelin, taking a flight, getting off again.",
    "Colour scheme",
    "Colour-blind friendly replaces the route, transport and accent colours with a set that stays distinguishable for the common forms of colour blindness. The distinction between a road and open ground never depends on colour alone in either scheme: the map draws open ground dashed and the minimap draws it as larger hollow dots.",
    "Cue before a turn",
    "Cue for a transport action",
    "Cue on arrival",
    "Cue volume",
    "Druid",
    "Hunter",
    "Lets Cabbie take waypoint coordinates written the way guides and web sites write them. The word is only claimed when no other add-on already owns it; /cabbie way always works.",
    "Mage",
    "Mute voice guidance",
    "Normal or Large. Large adds two points to window list and label fonts.",
    "Open Cabbie when the world map opens",
    "Paladin",
    "Priest",
    "Repeat the current instruction",
    "Rogue",
    "Set a destination at the world map cursor",
    "Shaman",
    "Short sounds the game already ships, played before a turn, for a transport action and on arrival. They work with voice guidance on or off.",
    "The destination search appears beside the world map each time you open it, and closes with it. It never takes the keyboard.",
    "Warlock",
    "Warrior",
    "Zero is silence. Clients without a per-sound volume play cues at the game's own sound effect volume.",
    "boats",
    "boats or zeppelins",
    "elevators",
    "flights",
    "no zone of that name is known",
    "objective place not known: the 1.12 records do not say where it is found, and the client names no position from here",
    "portals",
    "that is not a coordinate pair",
    "that place has no world position",
    "the tram",
    "trams",
    "your current zone is unknown; name a zone after the coordinates",
    "zeppelins",
    "Zone",
}
for i = 1, #SELF do L[SELF[i]] = SELF[i] end















local QUESTS = {
    "Quests: %d with a full route, %d with an objective whose place is not known, %d with only one known end.",
    "Forever's own quests: %d, and %d of them have a known start.",
    "Quest givers may have moved since the records were made. Names are the game's own for %d of %d quests, the 1.12 records' for the rest.",
    " - ",
    "%d levels above you",
    "%d more are Forever's own quests.",
    "%d more is one of Forever's own quests.",
    "%d more start with another race or class.",
    "%d more starts with another race or class.",
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
    "%s, in %s",
    "%s, reported by another source",

    "objective",



    "may have moved",
    "not checked in game",
    "from the game",
    "May have moved: from the 1.12 records, not confirmed in Forever.",
    "Not checked in game: reported for Forever by another source, not confirmed on this client.",
    "From the game: confirmed on this client.",

    "%s away",
    "- ",
    "[%d] %s",
    "A kill or collect objective is an area, not a point. Cabbie draws the measured area and labels it with its width, rather than putting a pin in the middle of it.",
    "This asks the server for a quest's name in Forever's own wording, from a small budget that is yours to spend.",
    "Classic quest names come with Cabbie in English, and the game's own wording replaces them once it is known. This allows the button that spends part of a small per-session lookup budget to fill in the names of a search result.",
    "Cabbie cannot look a name up right now (%s).",
    "No quest name matches that. Search by zone or by level, or open a quest once and Cabbie will remember its name. Names known so far: %d of %d.",
    "No quest name matches that. Search by zone or by level. A classic quest is found by its 1.12 name until Cabbie has seen the game's own name for it, then by that name. Names known so far from the game itself: %d of %d.",
    "Draw objective areas",
    "Find a quest",
    "Forever quest: start only",
    "Include Forever's own quests in search",
    "Look Up %d Names (%d Left)",
    "Look Up %d Name (%d Left)",
    "No routable quest matches that.",
    "No stops yet. Open Search and press Add stop.",
    "No stops yet. Open Search and press Add stop, or %s a place on the world map.",
    "Offer to look quest names up on the server",
    "Or open Search for a town, inn, or flight master.",
    "Pins for the quests you have accepted and for a quest you searched for and selected. Never for quests you have not taken.",
    "Quest %d",
    "Unknown quest",


    "Quests to Pick Up Nearby",
    "Adds the places where these quests start to your route as stops, in this order. The route starts when you press Start.",
    "Add to Route",
    "Drop Last Stop",
    "Dismiss",
    "No quests to take within %d yards.",
    "Working out the route.",
    "No route to these stops.",
    "The route was cancelled.",
    "The route takes %s.",
    "No stops left.",
    "No stops to set.",
    "No stop to drop.",
    "No stop to skip.",
    "Stops set. Press Start for the route.",
    "Stops set. Your route now goes to them.",
    "The last stop was dropped.",
    "The list was dismissed.",
    "Quests to take, yards",
    "How far to look for quests you can take. Add to Route sets the stops. You press Start for the route.",
    "Quest data is not installed in this copy of Cabbie.",
    "Quest data is not installed in this copy of Cabbie; only what the client reports is shown.",
    "Quest help",
    "Quest help: quests [zone|level|name] | quests about",
    "Quest pins on the minimap",
    "Quest pins on the world map",
    "Quests that exist only in Forever. Cabbie knows a name and sometimes where they start, never a turn-in or an objective, and says so.",
    "The quest panel, quest pins and quest search. Turning this off leaves the bundled quest data loaded but unused.",
    "The Quests page is unavailable.",
    "Quest help is off. Turn it on under Quests in Cabbie's settings.",
    "Zone, level, level band, or a quest name you have seen",


    "Turn in at %s",
    "Your quest log is empty",
    "The quests you take show here, each with its next step.",
    "Your quest log shows no quests",
    "Open its collapsed headers to see them.",
    "Where to Begin",
    "The first step of the Optimized Leveling order for this character.",
    "Open Optimized Leveling",
    "Pick a quest first",
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

    "a faction",
    "another class takes this quest",
    "another quest of its group is done or taken",
    "another race takes this quest",
    "is for characters of a lower standing with %s",
    "is for characters up to level %d",
    "is given during a holiday only",
    "it is in your quest log",
    "needs %s at %d",
    "needs a better standing with %s",
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
    "this quest is in WoW Forever only",
    "this quest was issued again, and who may take the new version is not known",
    "whether you have done this quest cannot be told",
    "whether your side may take this quest cannot be told",
    "you have done this quest",
    "your level cannot be told",
}
for i = 1, #QUESTS do L[QUESTS[i]] = QUESTS[i] end





local LATER = {
    "  %s (position not available)",
    "  %s: %.1f yards per second over %d samples",
    "  %s: %.1f yards per second over %d samples (not used yet, %d needed)",
    "  %s: nothing measured yet",
    "  flights: timed paths: %d, from real rides: %d",
    "  teleports: cast and loading times for %d of them",
    "  transports: docks with known departure times: %d",
    "%d more have an objective whose place is not known.",
    "%d more has an objective whose place is not known.",
    "%d more have no known turn-in.",
    "%d more has no known turn-in.",
    "%d of them have an objective whose place is not known.",
    "%d of them have no known giver or no known turn-in.",
    "%s (%s spot)",
    "%s (graveyard)",
    "%s cross open ground from one place where creatures are known to stand to the next; nobody has walked the way between them.",
    "%s cross open ground on a way that keeps off cliffs and deep water; trees, rocks and fences along it are not known.",
    "%s follow ground, floors and halls read from the game's own world.",
    "%s follow roads known from the game's signposts, drawn along the road's bends.",
    "%s follow roads known from the game's signposts; the line is drawn straight between junctions, so it cuts corners.",
    "%s follow roads traced from the ground of the game world.",
    "%s from %s",
    "%s has failed, so the route to it has ended.",
    "%s has left your quest log, so the route to it has ended.",
    "%s is complete, but no route can lead to where it is turned in: %s. The route to it has ended.",
    "%s is heading to %s. Type /cabbie accept to go there too, or /cabbie decline to ignore it.",
    "%s is in your quest log now, so the route to where it starts has ended.",
    "%s is no longer in your group; following stopped.",
    "%s spot",
    "%s swim across water read from the game's own world.",
    "%s cross fel read from the game's own world: it hurts, but there is no dry way.",
    "%s cross slime read from the game's own world: it hurts, but there is no dry way.",
    "%s cross lava read from the game's own world: it hurts, but there is no dry way.",
    "%s to %s",
    "%s, %s",
    "%s: that objective is done, but no route can lead to the next step: %s. The route to it has ended.",
    "%s: that objective is done. Where the next one is found is not known, so the route to it has ended.",
    "Accept a destination somebody shared",
    "Allow shortcuts off the road",
    "Board the %s to %s",
    "Cabbie does not know which flight paths you have in %s yet, so routes leave out the flights there. Talk to a flight master there once and it will use the ones you really have.",
    "Cabbie does not know which flight paths you have yet, so routes leave flights out. Talk to any flight master once and it will use the ones you really have.",
    "Cabbie:",
    "Clear everything Cabbie has set: the route, the preview, every stop and the map markers",
    "Old key for Stop Route",
    "Cleared. No route and no stops are set. Undo for %d seconds (/cabbie undo).",
    "No route or stops to clear.",
    "Restore the route cleared in the last 30 seconds",
    "Nothing to undo (the clear is older than 30 seconds).",
    "Nothing to undo.",
    "Restored the cleared route.",
    "Could not post to %s chat: %s",
    "Auction houses of the zone you are looking at get a small icon on the world map. Left-click one to route there.",
    "Banks of the zone you are looking at get a small icon on the world map. Left-click one to route there.",
    "Boat docks and zeppelin towers of the zone you are looking at get a small icon on the world map. Left-click one to route there.",
    "Dungeon and raid entrances of the zone you are looking at get a small icon on the world map. Left-click one to route there.",
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
    "Ignore a destination somebody shared",
    "Click to go here",
    "Location",
    "Measured rather than modelled: %s.",
    "Measured travel times (everything else comes from the model):",
    "Measured travel times: calibrate [reset ...]",
    "Navigate back to your corpse",
    "No destination set; there is nothing to share.",
    "You are not in a group; nobody would see the shared destination.",
    "Inside a dungeon, raid or battleground the game does not let add-ons post to chat. Share the destination again once you are outside.",
    "The game is not letting add-ons post to chat at the moment. Share the destination again in a little while.",
    "No road nearby leads down here: the way on is about %d yd below the direct line.",
    "No road nearby leads down here: the way on may be about %d yd below you.",
    "No road nearby leads up here: the way on is about %d yd above the direct line.",
    "No road nearby leads up here: the way on may be about %d yd above you.",
    "No longer following %s.",
    "Nobody has shared a destination with you recently.",
    "Nobody in your group is called '%s'.",
    "Off (the default): routes keep to the road wherever one goes, and leave it only to reach a place off the road. On: a route may cut across open ground when that is clearly quicker. Needs \"Prefer roads\".",
    "Post your destination to party chat",
    "Removes the route, the preview, every stop and their markers. Nothing stays set.",
    "Ride the %s to %s",
    "Ride the elevator",
    "Routes stick to roads unless the way round is much longer. Open ground, wandering creature paths and guessed stretches cost more. Off: the fastest line, often straight across open ground.",
    "Same as clear",
    "Show auction houses on the world map",
    "Show banks on the world map",
    "Show docks and zeppelin towers on the world map",
    "Show dungeon and raid entrances on the world map",
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
    "Vendors",
    "Your corpse",
    "a shared destination",
    "elevator",
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













local GUIDANCE = {
    "'%s' is neither a command nor a place Cabbie knows. /cabbie help lists the commands.",
    "'%s' is neither a command nor enough of a place name to start a route. /cabbie help lists the commands, and %s %s looks for a place.",
    "'%s' is not a command. Did you mean /cabbie %s? /cabbie help lists the commands, and %s %s looks for a place.",
    "A quest route moves on to the next objective and the turn-in, and a click on the round marker beside a quest in the quest list or on the map starts the way to it.",
    "Add a zone name after the two numbers.",
    "Bring the Route Back",
    "Click for options. Drag to move.",
    "Click to bring the route back",
    "Each of the two numbers goes from 0 to 100.",
    "Finding a new way",
    "Finding the way",
    "Follow My Quests",
    "Follow my quests",
    "Go to a place by name or by two map numbers",
    "Go to My Corpse",
    "No flights yet: visit a flight master.",
    "No flights in %s yet: visit a flight master there.",
    "Going to %s.",
    "No place known for this quest",
    "No place matches '%s'.",
    "No position here",
    "No way found to %s",
    "No zone is called '%s'.",
    "Pause",
    "Guide Me",
    "Reset Position",
    "Resume tries again.",
    "Route stopped.",
    "Route stopped. Click to bring it back.",
    "Show on Map",
    "Stop Following My Quests",
    "Stop Route",
    "That spot cannot be reached",
    "The new route starts when this ride ends",
    "The next turn is shown here",
    "Those numbers are not a place on that map.",
    "This quest has failed",
    "This quest's place is inside a dungeon with no known entrance",
    "To %s",
    "Turn arrow",
    "Type a place after the command, for example: %s Goldshire",
    "No place known for the objective: ask again when the quest is ready to turn in.",
    "You are there. The route moves on when this part of the quest is done.",
    "Your corpse cannot be found yet",
}
for i = 1, #GUIDANCE do L[GUIDANCE[i]] = GUIDANCE[i] end



local ARROW_LOOK = {
    "Arrow",
    "Arrow colour",
    "Arrow opacity",
    "Arrow size",
    "Arrow style",
    "Chevron",
    "Click to choose a colour",
    "Needle",
    "Pointer",
    "Pulse at turns",
    "Show the distance",
    "Show the words",
    "Text size",
    "This client has no colour picker.",
}
for i = 1, #ARROW_LOOK do L[ARROW_LOOK[i]] = ARROW_LOOK[i] end






local LEVELS = {
    "%s, then %s",
    "Enter %s",
    "Go down the ramp to the lower level",
    "Go down to the lower level",
    "Go up the ramp to the upper level",
    "Go up to the upper level",
    "Leave %s",
    "Take the stairs down",
    "Take the stairs up",
}
for i = 1, #LEVELS do L[LEVELS[i]] = LEVELS[i] end





local INSIDE_ROOMS = {
    "Follow the way in",
    "Go down to %s",
    "Go to %s",
    "Go up to %s",
}
for i = 1, #INSIDE_ROOMS do L[INSIDE_ROOMS[i]] = INSIDE_ROOMS[i] end



local HAZARDS = {
    "Cross the fel here: it hurts, but there is no dry way",
    "Cross the fel: it hurts",
    "Cross the lava here: it hurts, but there is no dry way",
    "Cross the lava: it hurts",
    "Cross the slime here: it hurts, but there is no dry way",
    "Cross the slime: it hurts",
}
for i = 1, #HAZARDS do L[HAZARDS[i]] = HAZARDS[i] end





local COMPASS = {
    "north", "north-west", "west", "south-west", "south", "south-east", "east", "north-east",
}
for i = 1, #COMPASS do L[COMPASS[i]] = COMPASS[i] end







local SEARCH_LINE = {
    "Class Trainer",
    "Class trainer",
    "Click the round marker beside a quest and Cabbie leads you to it",
    "Click to close",
    "Finding the nearest %s",
    "Flight Master",
    "Flights are used once you have visited a flight master",
    "Flights in %s are used once you have visited a flight master there",
    "Go to Nearest",
    "Go to a place",
    "Go to:",
    "How to Use Cabbie",
    "None found near here",
    "Open the world map and type a place, a quest, or a word like inn or repair",
    "Repair vendor",
    "Right-click a quest in your quest list: Guide Me",
    "Shift-click the world map to be guided to that spot",
    "Stable Master",
    "The search line is not available in this session.",
    "Type a place, a quest, or a word like inn or repair",
    "Your steps appear beside your quest list. Click the word Route to stop or pause",
}
for i = 1, #SEARCH_LINE do L[SEARCH_LINE[i]] = SEARCH_LINE[i] end





local PICKUP_MARKS = {
    "%s. The source may not list every condition.",
    "A yellow ! on the world map and the minimap where you can take a quest now, as far as the records say. Hover one to see where its place comes from; Shift-click it on the world map to go there.",
    "Level %d",
    "Shift-click to go there",
    "Show quests I can pick up",
}
for i = 1, #PICKUP_MARKS do L[PICKUP_MARKS[i]] = PICKUP_MARKS[i] end

L["Replace"] = "Replace"

L["Keep Going"] = "Keep Going"

L["Add as a Stop"] = "Add as a Stop"

L["Replace the route to %s?"] = "Replace the route to %s?"

L["Go to Corpse"] = "Go to Corpse"
L["Not Now"] = "Not Now"
L["You are dead. Guide me back to my corpse?"] = "You are dead. Guide me back to my corpse?"

L["Resume"] = "Resume"

L["On screen"] = "On screen"




L["Routing"] = "Routing"

L["Developer"] = "Developer"

L["Stop %s: %s"] = "Stop %s: %s"
L["Shift+Right-click to remove"] = "Shift+Right-click to remove"
L["Right-click for options"] = "Right-click for options"


L["Click to open"] = "Click to open"
L["about %d min"] = "about %d min"



L["Route to %s"] = "Route to %s"
L["Right-click the X for options"] = "Right-click the X for options"
L["A solid line is a road or walkable ground, a dashed line open ground or a guess."] = "A solid line is a road or walkable ground, a dashed line open ground or a guess."
L["Route label on the map"] = "Route label on the map"
L["Names the route and its stops in a small label in the corner of the world map."] = "Names the route and its stops in a small label in the corner of the world map."
L["Route label on the map on."] = "Route label on the map on."
L["Route label on the map off."] = "Route label on the map off."
L["Route label on the map: on|off"] = "Route label on the map: on|off"

L["Objective"] = "Objective"
L["Turn-in"] = "Turn-in"

L["direct"] = "direct"

L["*"] = "*"


L["Large"] = "Large"





L["Map"] = "Map"
L["Place icons"] = "Place icons"



L["%s cut across city streets and squares on lines checked against the city map; nobody has walked those exact lines."] = "%s cut across city streets and squares on lines checked against the city map; nobody has walked those exact lines."
L["Continue"] = "Continue"
L["Your route from last time is still set. Stops: %d. Continue or clear?"] = "Your route from last time is still set. Stops: %d. Continue or clear?"
L["Search by zone (\"Westfall\"), by level (\"24\" or \"20-30\"), or by a quest name you have already seen. %d routable quests are bundled."] = "Search by zone (\"Westfall\"), by level (\"24\" or \"20-30\"), or by a quest name you have already seen. %d routable quests are bundled."
L["%s of this route is a guessed way over open ground (drawn dashed on the maps); expect obstacles."] = "%s of this route is a guessed way over open ground (drawn dashed on the maps); expect obstacles."
L["%s, place not confirmed"] = "%s, place not confirmed"
L["Place not confirmed"] = "Place not confirmed"
L["Weapon master"] = "Weapon master"
L["Stop"] = "Stop"


L["Cabbie cannot route in %s: its map add-on, %s, is not installed. Reinstall Cabbie with all its folders."] = "Cabbie cannot route in %s: its map add-on, %s, is not installed. Reinstall Cabbie with all its folders."
L["Cabbie cannot route in %s: %s is turned off. Turn it on in the AddOns list at character select."] = "Cabbie cannot route in %s: %s is turned off. Turn it on in the AddOns list at character select."
L["%s is from another version of Cabbie. Reinstall Cabbie so that all its folders match."] = "%s is from another version of Cabbie. Reinstall Cabbie so that all its folders match."
L["The map of %s did not finish loading. Type /reload to try again."] = "The map of %s did not finish loading. Type /reload to try again."
L["Cabbie cannot route in %s: the game marks %s as out of date. Tick \"Load out of date AddOns\" in the AddOns list at character select, or install the Cabbie made for this version of the game."] = "Cabbie cannot route in %s: the game marks %s as out of date. Tick \"Load out of date AddOns\" in the AddOns list at character select, or install the Cabbie made for this version of the game."
L["Cabbie cannot route in %s: %s needs another of Cabbie's folders, which is missing or turned off. Reinstall Cabbie with all its folders and turn them all on in the AddOns list at character select."] = "Cabbie cannot route in %s: %s needs another of Cabbie's folders, which is missing or turned off. Reinstall Cabbie with all its folders and turn them all on in the AddOns list at character select."
L["Cabbie cannot route in %s: the game would not load %s. Reinstall Cabbie with all its folders."] = "Cabbie cannot route in %s: the game would not load %s. Reinstall Cabbie with all its folders."
L["Cabbie cannot route in %s: this version of the game gives Cabbie no way to load %s."] = "Cabbie cannot route in %s: this version of the game gives Cabbie no way to load %s."
L["Loading the map of %s when you leave combat."] = "Loading the map of %s when you leave combat."




L["Take"] = "Take"
L["Accept"] = "Accept"
L["Turn in"] = "Turn in"
L["Optimized Leveling is not available in this copy of Cabbie."] = "Optimized Leveling is not available in this copy of Cabbie."
L["Optimized Leveling is turned off. Turn it on under Quest help in the settings."] = "Optimized Leveling is turned off. Turn it on under Quest help in the settings."
L["Your character is not known yet."] = "Your character is not known yet."
L["objective %d"] = "objective %d"
L["not tested in the beta"] = "not tested in the beta"
L["Class Quests for Your Character"] = "Class Quests for Your Character"
L["Optimized Leveling for %s: nothing left in the order."] = "Optimized Leveling for %s: nothing left in the order."
L["Optimized Leveling for %s: step %d of %d."] = "Optimized Leveling for %s: step %d of %d."
L["Levels %d to 60 were not played in the beta: that part of the order is untested."] = "Levels %d to 60 were not played in the beta: that part of the order is untested."
L["Optimized Leveling: skipped %s."] = "Optimized Leveling: skipped %s."
L["Optimized Leveling: every skipped quest is back in the order."] = "Optimized Leveling: every skipped quest is back in the order."

L["Optimized Leveling: the next steps for this character; leveling skip | leveling reset | leveling start | leveling stop"] = "Optimized Leveling: the next steps for this character; leveling skip | leveling reset | leveling start | leveling stop"
L["Following the order: Cabbie sets the next stop by itself."] = "Following the order: Cabbie sets the next stop by itself."
L["No next stop yet: the next quests have no known place or cannot be taken yet. Skip Step passes over the first one."] = "No next stop yet: the next quests have no known place or cannot be taken yet. Skip Step passes over the first one."
L["%s (done)"] = "%s (done)"
L["Optimized Leveling: following the order. Cabbie sets the next stop by itself. Press Stop on the Optimized Leveling page to end it."] = "Optimized Leveling: following the order. Cabbie sets the next stop by itself. Press Stop on the Optimized Leveling page to end it."
L["Optimized Leveling: you set a place yourself, so Cabbie stopped setting the next stop. Press Guide Me on the Optimized Leveling page to start it again."] = "Optimized Leveling: you set a place yourself, so Cabbie stopped setting the next stop. Press Guide Me on the Optimized Leveling page to start it again."
L["Optimized Leveling: stopped following the order."] = "Optimized Leveling: stopped following the order."
L["Quests to do here: %d (%d left)"] = "Quests to do here: %d (%d left)"
L["Quests to pick up here: %d (%d left)"] = "Quests to pick up here: %d (%d left)"
L["Quests to turn in here: %d (%d left)"] = "Quests to turn in here: %d (%d left)"
L["Quests to turn in here: %d, to pick up: %d (%d left)"] = "Quests to turn in here: %d, to pick up: %d (%d left)"
L[" (unconfirmed)"] = " (unconfirmed)"
L[" (not in your order)"] = " (not in your order)"

L["Step %d of %d"] = "Step %d of %d"
L["Some quest givers may have moved since the old records."] = "Some quest givers may have moved since the old records."
L["Next Stop"] = "Next Stop"
L["turn in at %s"] = "turn in at %s"
L["Later in %s"] = "Later in %s"
L["Later in the Order"] = "Later in the Order"
L["Level %d of %d"] = "Level %d of %d"
L["Skip Step"] = "Skip Step"
L["Follows your level and quest log by itself."] = "Follows your level and quest log by itself."

L["%s - next"] = "%s - next"
L["%s - later in the order"] = "%s - later in the order"
L["Not in your order: %s"] = "Not in your order: %s"
L["and %d more"] = "and %d more"
L["Cabbie marks the quests your Optimized Leveling order wants from this quest giver. Taking and turning in stays yours."] = "Cabbie marks the quests your Optimized Leveling order wants from this quest giver. Taking and turning in stays yours."
L["Mark Optimized Leveling quests at quest givers"] = "Mark Optimized Leveling quests at quest givers"
L["When you talk to a quest giver, a small panel beside its window names the quests your Optimized Leveling order wants from it, which one comes next, and the turn-ins it wants. Taking and turning in stays yours."] = "When you talk to a quest giver, a small panel beside its window names the quests your Optimized Leveling order wants from it, which one comes next, and the turn-ins it wants. Taking and turning in stays yours."
L["Optimized Leveling"] = "Optimized Leveling"
L["A quest order for your faction, race and class from level 1 to 60, from published Forever leveling guides. It follows your level and quests by itself, shows the next steps on its own page of Cabbie's book-style window, and puts its quests first in the quests to take nearby. Levels 31 to 60 were not played in the beta."] = "A quest order for your faction, race and class from level 1 to 60, from published Forever leveling guides. It follows your level and quests by itself, shows the next steps on its own page of Cabbie's book-style window, and puts its quests first in the quests to take nearby. Levels 31 to 60 were not played in the beta."

L["Search a town, a person or 42.5 65.1"] = "Search a town, a person or 42.5 65.1"
L["Show Only"] = "Show Only"
L["Everything"] = "Everything"
L["Add Stop"] = "Add Stop"
L["Add to Favorites"] = "Add to Favorites"
L["Remove from Favorites"] = "Remove from Favorites"
L["Pick a place first"] = "Pick a place first"
L["Double-click to be guided there"] = "Double-click to be guided there"
L["No innkeeper, flight master, bank or mailbox is known nearby."] = "No innkeeper, flight master, bank or mailbox is known nearby."
L["Auction House"] = "Auction House"
L["Weapon Master"] = "Weapon Master"

L["Right-click any place and choose Add to Favorites."] = "Right-click any place and choose Add to Favorites."
L["Clear Recent"] = "Clear Recent"
L["Favorites on the Places page; fav add [name]|list|remove <n>|<name>"] = "Favorites on the Places page; fav add [name]|list|remove <n>|<name>"
