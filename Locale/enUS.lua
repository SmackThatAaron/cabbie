













local ADDON_NAME, FGPS = ...

local L = setmetatable({}, { __index = function(_, key) return key end })
FGPS.L = L


L.ADDON_TITLE = "Cabbie"
L.VERSION_LINE = "Version %s on client %s (build %s, interface %d)%s"
L.NOT_FOREVER = " - warning: this client does not look like World of Warcraft: Forever"
L.BOOT_FAILED_MODULES = "%d of Cabbie's parts failed to start; type /cabbie log for details."
L.BOOT_UPDATED_WHILE_RUNNING = "Cabbie was updated while the game was open. Close the game completely and start it again."
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
L.SETUP_INTRO = "Cabbie guides you to a place and never moves your character for you. Shift-click the world map or type a place into the search at its top left to be guided there."
L.SETUP_PICK = "Choose how you want to be guided (pick one, the other, or both):"
L.SETUP_METHOD_ARROW = "Turn arrow"
L.SETUP_METHOD_ARROW_TIP = "Points to the next turn at the top of your screen."
L.SETUP_METHOD_BEACON = "Road beacon"
L.SETUP_METHOD_BEACON_TIP = "Shows a light beam, turn icon and distance on the road ahead."
L.SETUP_METHOD_VOICE = "Voice guidance"
L.SETUP_METHOD_VOICE_TIP = "Speaks upcoming turns out loud so you can keep your eyes on the game."
L.SETUP_METHOD_STEPS = "Step list"
L.SETUP_METHOD_STEPS_TIP = "Lists the next few turns and travel time beside your quest list."
L.SETUP_LATER = "Your route is also drawn on the map and minimap. You can change any of this any time in Settings."
L.SETUP_DONE = "Done"
L.SETUP_SETTINGS = "Settings..."
L.SETUP_WHATSNEW = "What's New..."




L.WHATSNEW_TITLE = "What's New in Cabbie %s"
L.WHATSNEW_HELP = "Show what's new in this update and preview guidance options"
L.WHATSNEW_INTRO = "Preview how your guidance looks below, hover any option to see it in action, and toggle what you want:"
L.WHATSNEW_STAGE_TURN = "Turn left at Goldshire"
L.WHATSNEW_STAGE_VOICE = "Voice: \"In 40 yards, turn left\""
L.WHATSNEW_STAGE_STEPS_HEAD = "Goldshire  1m 10s"
L.WHATSNEW_STAGE_STEPS_LINE = "1. Turn left (42 yd)"
L.WHATSNEW_STAGE_COMBAT_ON = "In combat: Visuals shown"
L.WHATSNEW_STAGE_COMBAT_OFF = "In combat: Hidden"
L.WHATSNEW_STAGE_ACTIVE = "Active: %s  |  Shift-click quests  |  50 yd arrival"
L.WHATSNEW_STAGE_NONE = "Map & minimap lines only  |  Shift-click quests  |  50 yd arrival"
L.WHATSNEW_STAGE_PREVIEW = "Previewing: %s"
L.WHATSNEW_BEACON = "Road beacon (new default)"
L.WHATSNEW_BEACON_TIP = "Shows a 3D light beam, turn icon and distance on the road ahead."
L.WHATSNEW_ARROW = "Turn arrow"
L.WHATSNEW_ARROW_TIP = "Points to the next turn at the top of your screen — use the beacon, the arrow, or both."
L.WHATSNEW_COMBAT = "Keep visual guidance shown in combat"
L.WHATSNEW_COMBAT_TIP = "Keeps your road beacon, arrow and map route visible during fights."
L.WHATSNEW_VOICE = "Voice guidance"
L.WHATSNEW_VOICE_TIP = "Speaks turns out loud."
L.WHATSNEW_STEPS = "Step list"
L.WHATSNEW_STEPS_TIP = "Lists turns beside quests."
L.WHATSNEW_HIGHLIGHTS_TITLE = "Also new & enabled automatically:"
L.WHATSNEW_HIGHLIGHTS_BODY = "• Shift+Left-click (or Ctrl+Left-click) any quest in your tracker, quest log or world map to route to it.\n• Routes now auto-complete within 50 yards of your destination (adjustable in Settings > Advanced)."
L.WHATSNEW_LATER = "Reopen any time with /cabbie whatsnew."
L.WHATSNEW_SETUP = "Setup..."


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
L.ROUTE_CALCULATING = "Finding the way..."
L.ROUTE_NO_PATH = "I can't find a way there."
L.ROUTE_NO_ORIGIN = "I can't tell where you are here."
L.ROUTE_UNREACHABLE = "You can't get there with the transports you have turned on."
L.ROUTE_NO_DATA = "I don't have a map of this area."
L.ROUTE_CANCELLED = "Stopped looking for a way."
L.SETTINGS_RESET_DONE = "Settings are back to their defaults. Your routing and transport choices were kept."
L.POSITIONS_RESET_DONE = "Cabbie's windows are back where they started."
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
    "Nothing matches that.",
    "No recent places yet.",
    "Type at least two letters.",
    "%s (%d stops)",
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
    "100% mount",
    "60% mount",
    "%s trainer",
    "%s (your class)",
    "Any Trainer",
    "Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering", "First Aid", "Fishing", "Herbalism",
    "Leatherworking", "Mining", "Skinning", "Tailoring", "Weapon master", "Riding", "Pet", "Portal", "Other",
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
    "Actions",
    "Add stop",
    "Adding stops: pick as many places as you like.",
    "Added a stop: %s",
    "Added to favorites: %s",
    "Advanced",
    "Once you're off the route, Cabbie looks for a new one at most this often.",
    "All",
    "Allow straight guesses",
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
    "I don't know a way from here inside %s yet.",
    "I don't know a way to this place inside %s yet.",
    "Move Cabbie's arrow. The arrow keys move the selection a little (with Shift, more).",
    "Cabbie voice guidance is working.",
    "Cabbie's recorded voice",
    "Capital city",
    "Cast %s",
    "Cast %s.",
    "Clear",
    "Clear recent destinations",
    "Client %s (%s), Edit Mode: %s",
    "Client build",
    "Close",
    "Settings",
    "Switches off the extra click only. Shift + Left-click still goes to the spot.",
    "Nothing to pause or resume.",
    "No route to pause.",
    "Guidance is already paused.",
    "Nothing is paused.",
    "Pause or resume guidance",
    "Colour-blind friendly",
    "Computing alternatives...",
    "Consider teleport spells",
    "Consider the Hearthstone",
    "Routes may start with your Hearthstone when that is quicker. Cabbie learns where it takes you the first time you use it or make an inn your home. Your Route's tooltip on the Places page says when it is left out, and why.",
    "Continue %s",
    "Continue %s across open ground for %s",
    "Continue %s across open ground for %s.",
    "Coordinates",
    "coordinates must be between 0 and 100",
    "Couldn't add that to your favorites (%s).",
    "Could not add that waypoint: %s",
    "I couldn't find that spot%s",
    "Could not use that waypoint: %s",
    "Ctrl + Right-click",
    "Cue '%s' is now %s.",
    "Cue volume set to %d.",
    "Custom",
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
    "How close to the place you need to be for Cabbie to say you've arrived.",
    "Distance units",
    "Dock",
    "Done",
    "Drag to move. The arrow keys move the selection a little (with Shift, more).",
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
    "Fewer Transfers",
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
    "How far you can stray from the route before Cabbie finds a new one.",
    "In %s, %s",
    "In combat",
    "Inn",
    "Innkeeper",
    "instance %d",
    "dungeons and raids",
    "interface",
    "It is available in %s.",
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
    "Nearest %s by travel time.",
    "Nearest %s by travel time; %d of %d have no known way (open ground).",
    "Never mounted",
    "No %s found: %s.",
    "No arrival position is known for this spell.",
    "No Rune of Teleportation in your bags; the teleport is not used for routing.",
    "no boats",
    "No Boats",
    "There's no place to add yet. Pick one first.",
    "No place is set yet. Pick one on the Places page first.",
    "No place is set yet.",
    "No destination was given.",
    "There's no other way that's really different.",
    "No extra click",
    "No favorite %d; see /cabbie fav list.",
    "No favorite matches '%s'.",
    "No favorites yet.",
    "no flights",
    "No Flights",
    "I know of no transport between %s and %s.",
    "No navigation data is available for %s.",
    "no sound available in this client",
    "No text-to-speech voices are installed.",
    "None reported by the game",
    "No road joins these points; the whole route is drawn dashed.",
    "No road was found; this route is drawn dashed.",
    "Normal",
    "not bound",
    "I don't know of one nearby",
    "off",
    "Off",
    "Off route, recalculating.",
    "Off-route distance (yards)",
    "on",
    "Open",
    "Open the Places page",
    "Open the Places page (optionally with a query)",
    "Open the options panel",
    "Open the world map first, then press the key with the cursor over the place you want.",
    "or",
    "Pause guidance",
    "Performance instrumentation",
    "Performance report",
    "Play a sample",
    "Portal",
    "Position of '%s' restored to its default.",
    "prefer roads",
    "Prefer roads",
    "Standard Colours",
    "Prints diagnostics to chat and forwards errors to the error handler.",
    "Raid",
    "Recent",
    "Recent places aren't available right now.",
    "Recent places cleared.",
    "Recent destinations; recent clear",
    "Remove",
    "Removed from favorites: %s",
    "Removed the stop %s: its waypoint was removed.",
    "Rename",
    "Repair",
    "Reset",
    "Reset Cabbie window position",
    "Reset all UI positions",
    "Reset settings",
    "Reset settings|positions|routing|all|window",
    "Reset to Default",
    "Resume guidance",
    "Revert Changes",
    "Room",
    "Route",
    "Route computation budget (ms per frame)",
    "Route updated.",
    "Route cleared.",
    "No route set.",
    "Routing and transport preferences restored to defaults.",
    "Routing preferences cannot be reset in this session (the settings store did not load).",
    "same distance",
    "selected",
    "Something went wrong with the search.",
    "Search isn't working right now.",
    "Looking for the nearest %s...",
    "Select %s to continue your route.",
    "Pick a place first.",
    "Service",
    "Something went wrong looking for that.",
    "Set a destination from waypoint coordinates or a pasted map pin link",
    "Settings and frame positions restored to defaults; routing preferences, favorites and recents were kept.",
    "Sharp left",
    "Sharp right",
    "Shift + Right-click",
    "Shortest time between recalculations (seconds)",
    "Show your route's steps beside the quest list",
    "The time and distance left, and the next few steps of your route, in a list beside the game's quest list. Drag it by its first line to move it. The arrow at the top of the screen guides you without it.",
    "Show the in-world waypoint marker",
    "Show Your Route on the Places page for the current destination",
    "Show version, data version, client build and Edit Mode status",
    "Skip Stop",
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
    "The speed Cabbie uses for travel times when it can't tell whether you're mounted.",
    "Spell not known yet.",
    "Stable master",
    "Start",
    "Start (or resume) navigation for the previewed route",
    "Stay aboard",
    "Stay aboard at %s",
    "stop %d",
    "Stop %d",
    "Stop %d: %s",
    "Stops reordered.",
    "Open ground",
    "Open Ground",
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
    "I can't take you to that spot%s",
    "that place",
    "The cursor is not over the world map.",
    "The game blocked an action right after Cabbie changed its in-world marker, so Cabbie has stopped the marker until you reload or log in again. The arrow and the map lines carry on; a marker Cabbie had already placed stays on the map until you remove it or reload.",
    "The game reports no text-to-speech voice on this computer, so the game voice settings below are greyed out. Cabbie's recorded voice needs nothing installed. Play a sample says one short sentence in it.",
    "that part of Cabbie is not ready",
    "the dock",
    "the far side",
    "The route in progress was replaced by %s. Use '%s add <coordinates>' to keep the route and add a stop instead.",
    "The route to %s was cancelled: its waypoint was removed.",
    "The layout editor cannot be opened during combat.",
    "the navigator did not accept the waypoint",
    "The options panel is not available in this client; use /cabbie help for the command list.",
    "The options panel opens when you leave combat.",
    "the portal",
    "The same words work as /cabbie way ... . Cabbie understands the common waypoint wording so guides need no rewriting; it is not, and does not replace, any other waypoint add-on.",
    "The Places page is not available in this session.",
    "The Places page is unavailable; use /cabbie go <x> <y> [zone] instead.",
    "There is no instruction to repeat.",
    "That instruction has no recorded voice.",
    "there is no map pin set",
    "this client has no map pin",
    "This client offers none of the sounds the cues use.",
    "those coordinates could not be resolved",
    "it's already there",
    "that place can't be saved",
    "the favorites list is full",
    "the request was not understood",
    "the search was stopped",
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
    "I don't know that kind of place",
    "Unnamed location",
    "Usage: /cabbie legend on|off",
    "Usage: /cabbie cues %s on|off",
    "Usage: /cabbie cues on|off|volume <n>|turn on|off|transport on|off|arrival on|off|test|status",
    "Usage: /cabbie cues volume <0..100>",
    "Usage: /cabbie fav remove <number> (see /cabbie fav list)",
    "Usage: /cabbie reset settings|positions|routing|all|window",
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
    "Where Cabbie knows no ground it may draw a straight line. Off: a place far from any known ground gets no route. To stay on roads use \"Prefer roads\".",
    "Yards",
    "Yards or metres and kilometres.",
    "You are already at %s; continue your route on foot.",
    "You have arrived at your destination.",
    "You have reached stop %d, %s. Continue to the next stop.",
    "You land at %s.",
    "I can't tell which zone you're in. Add the zone name after the numbers.",
    "your destination",
    "You still have stops from your last route (%d). Restart the game and Cabbie will ask if you want to pick them up.",
    "Your route to %s was replaced by %s. Use '%s add <coordinates>' to keep the route and add a stop instead.",
    "I can't tell where you are here",
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
    "Mage",
    "Mute voice guidance",
    "Normal or Large. Large adds two points to text in the Cabbie window, the Go to: line, the Route steps and the welcome window.",
    "Open Cabbie when the world map opens",
    "Paladin",
    "Priest",
    "Repeat the current instruction",
    "Rogue",
    "Set a destination at the world map cursor",
    "Shaman",
    "Short sounds the game already ships, played before a turn, for a transport action and on arrival. They work with voice guidance on or off.",
    "The Places page opens beside the world map each time you open it, and closes with it. It never takes the keyboard.",
    "Warlock",
    "Warrior",
    "Zero is silence. Clients without a per-sound volume play cues at the game's own sound effect volume.",
    "boats",
    "boats or zeppelins",
    "elevators",
    "flights",
    "no zone of that name is known",
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





L["No stop to skip."] = "No stop to skip."





local LATER = {
    "  %s (position not available)",
    "  %s: %.1f yards per second over %d samples",
    "  %s: %.1f yards per second over %d samples (not used yet, %d needed)",
    "  %s: nothing measured yet",
    "  flights: timed paths: %d, from real rides: %d",
    "  teleports: cast and loading times for %d of them",
    "  transports: docks with known departure times: %d",
    "%s (graveyard)",
    "%s cross open ground from one place where creatures are known to stand to the next; nobody has walked the way between them.",
    "%s cross open ground on a way that keeps off cliffs and deep water; trees, rocks and fences along it are not known.",
    "%s follow ground, floors and halls read from the game's own world.",
    "%s follow roads known from the game's signposts, drawn along the road's bends.",
    "%s follow roads known from the game's signposts; the line is drawn straight between junctions, so it cuts corners.",
    "%s follow roads traced from the ground of the game world.",
    "%s from %s",
    "%s is heading to %s. Type /cabbie accept to go there too, or /cabbie decline to ignore it.",
    "%s is no longer in your group; following stopped.",
    "%s swim across water read from the game's own world.",
    "%s cross fel read from the game's own world: it hurts, but there is no dry way.",
    "%s cross slime read from the game's own world: it hurts, but there is no dry way.",
    "%s cross lava read from the game's own world: it hurts, but there is no dry way.",
    "%s to %s",
    "%s, %s",
    "Accept a destination somebody shared",
    "Allow shortcuts off the road",
    "Board the %s to %s",
    "Cabbie does not know which flight paths you have in %s yet, so routes leave out the flights there. Talk to a flight master there once and it will use the ones you really have.",
    "Cabbie does not know which flight paths you have yet, so routes leave flights out. Talk to any flight master once and it will use the ones you really have.",
    "Cabbie:",
    "Clear everything Cabbie has set: the route, the preview, every stop and the map markers",
    "Old key for Stop Route",
    "Cleared. No route and no stops are set. Undo for %d seconds (/cabbie undo).",
    "Your route and its stops are cleared.",
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
    "The game no longer says where %s is, so I stopped following.",
    "The client will not say where %s is (a different continent, or inside an instance).",
    "The game won't say where your body is, so I'll take you to the nearest graveyard instead.",
    "The shared destination was ignored.",
    "The way on is well above or below this line.",
    "There is nothing measured called '%s'. Try ground, flights, transports or teleports.",
    "This client does not let add-ons post to chat.",
    "The game won't say where your body is, and I don't know a graveyard nearby.",
    "This place has no spot I can share.",
    "This is not the %s to %s. A new route follows when you get off.",
    "This is not the transport of your route (%s). A new route follows as soon as you get off.",
    "Alliance",
    "Horde",
    "This place belongs to the Alliance.",
    "This place belongs to the Horde.",
    "Use /cabbie calibrate reset [ground|flights|transports|teleports] to forget measurements.",
    "Use /cabbie follow <name> to navigate to a group member, or /cabbie follow off to stop.",
    "You're alive, so there's no body to run back to.",
    "You are not following anybody.",
    "Vendors",
    "Your corpse",
    "a shared destination",
    "elevator",
    "flights you have taken before",
    "mounted",
    "on foot",
    "someone in your group",
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
    "Add a zone name after the two numbers.",
    "Bring the Route Back",
    "Click for options. Drag to move.",
    "Click to bring the route back",
    "Each of the two numbers goes from 0 to 100.",
    "Finding a new way",
    "Finding the way",
    "Go to a place by name or by two map numbers",
    "Go to My Corpse",
    "No flights yet: visit a flight master.",
    "No flights in %s yet: visit a flight master there.",
    "Going to %s.",
    "No place matches '%s'.",
    "I can't tell where you are",
    "I can't find a way to %s",
    "No zone is called '%s'.",
    "Pause",
    "Reset Position",
    "Press Resume to try again.",
    "Route stopped.",
    "Route stopped. Click to bring it back.",
    "Show on Map",
    "Stop Route",
    "I can't find a way to that spot",
    "The new route starts when this ride ends",
    "The next turn is shown here",
    "Those numbers are not a place on that map.",
    "To %s",
    "Turn arrow",
    "Type a place after the command, for example: %s Goldshire",
    "I can't find your body yet",
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





local TELEPORTS = {
    "a quest done",
    "an item",
    "It needs %s first.",
    "It needs %s.",
    "level %d",
    "something else done",
    "Take teleporter",
    "Take the teleporter",
    "Take the teleporter to %s",
    "two items",
}
for i = 1, #TELEPORTS do L[TELEPORTS[i]] = TELEPORTS[i] end






local INSIDE_ROOMS = {
    "Follow the way in",
    "Follow the way out",
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





local GUARDED = {
    "Keep out of the other side's towns",
    "Routes go round the towns and outposts the other side holds, off the road where they must. A route still goes in when you start or stop there, or when there is no other way. Off: routes take the road through them.",
    "This route goes through %s, which the other side holds: you may be attacked there.",
    "This route goes through an outpost of the other side: you may be attacked there.",
    "%s ahead is held by the other side: you may be attacked",
    "The outpost ahead is held by the other side: you may be attacked",
    "The other side holds the ground ahead",
    "Leave the road here to go round %s, held by the other side",
    "Off the road round %s",
    "Leave the road here to go round an outpost of the other side",
    "Off the road round the outpost",
}
for i = 1, #GUARDED do L[GUARDED[i]] = GUARDED[i] end





local COMPASS = {
    "north", "north-west", "west", "south-west", "south", "south-east", "east", "north-east",
}
for i = 1, #COMPASS do L[COMPASS[i]] = COMPASS[i] end







local SEARCH_LINE = {
    "Class Trainer",
    "Class trainer",
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
    "Open the world map and type a place or a word like inn or repair",
    "Repair vendor",
    "Shift-click the world map to be guided to that spot",
    "Stable Master",
    "The search line is not available in this session.",
    "Type a place or a word like inn or repair",
    "Your steps appear beside your quest list. Click the word Route to stop or pause",
}
for i = 1, #SEARCH_LINE do L[SEARCH_LINE[i]] = SEARCH_LINE[i] end



L["Take Me There"] = "Take Me There"
L["No Thanks"] = "No Thanks"


L["Add as a Stop"] = "Add as a Stop"

L["You died. Want me to take you back to your body?"] = "You died. Want me to take you back to your body?"


L["Want me to take you to %s?"] = "Want me to take you to %s?"
L["the spot the guard marked"] = "the spot the guard marked"
L["The spot the guard marked"] = "The spot the guard marked"


L["from Questie"] = "from Questie"




L["Pick up from %s"] = "Pick up from %s"
L["Find %s"] = "Find %s"
L["Turn in to %s"] = "Turn in to %s"
L["the quest giver"] = "the quest giver"
L["the item that starts it"] = "the item that starts it"
L["the spot your map marks"] = "the spot your map marks"
L["Quest place"] = "Quest place"
L["Quest places"] = "Quest places"

L["To find quests by name, Cabbie needs the Questie add-on."] = "To find quests by name, Cabbie needs the Questie add-on."

L["I can't tell where this quest takes you next."] = "I can't tell where this quest takes you next."


L["No %s known here. Ask a guard, or visit one and I'll remember it."] = "No %s known here. Ask a guard, or visit one and I'll remember it."

L["Resume"] = "Resume"





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

L["Go to the map pin I place"] = "Go to the map pin I place"
L["A pin you place on the world map becomes your route's new place, as a click on the map does, and starts a route when none runs. While you travel, Cabbie's marker uses the same pin and puts yours back at the end."] = "A pin you place on the world map becomes your route's new place, as a click on the map does, and starts a route when none runs. While you travel, Cabbie's marker uses the same pin and puts yours back at the end."

L["Remove a stop only when I click its marker"] = "Remove a stop only when I click its marker"
L["Off (the default): Shift + Right-click anywhere on the world map removes the stop nearest the click, or the stop you are heading to when none is on the map. On: only Shift + Right-click on a stop's own marker removes it. When the extra world map click is Shift + Right-click, that click sets a destination and only the marker removes a stop."] = "Off (the default): Shift + Right-click anywhere on the world map removes the stop nearest the click, or the stop you are heading to when none is on the map. On: only Shift + Right-click on a stop's own marker removes it. When the extra world map click is Shift + Right-click, that click sets a destination and only the marker removes a stop."
L["Removed %s."] = "Removed %s."
L["Removed %s. Your route is cleared."] = "Removed %s. Your route is cleared."
L["Names the route and its stops in a small label in the corner of the world map."] = "Names the route and its stops in a small label in the corner of the world map."
L["Route label on the map on."] = "Route label on the map on."
L["Route label on the map off."] = "Route label on the map off."
L["Route label on the map: on|off"] = "Route label on the map: on|off"


L["direct"] = "direct"

L["*"] = "*"


L["Large"] = "Large"










L["Map"] = "Map"
L["Place Icons"] = "Place Icons"
L["Text and Colours"] = "Text and Colours"
L["Keep All Guidance"] = "Keep All Guidance"
L["The arrow at the top of the screen that points along your route."] = "The arrow at the top of the screen that points along your route."
L["Names the turn and its landmark on a small scroll under the arrow."] = "Names the turn and its landmark on a small scroll under the arrow."
L["Shows how far away the turn is, under the arrow."] = "Shows how far away the turn is, under the arrow."
L["The arrow glows once, softly, when a turn comes up."] = "The arrow glows once, softly, when a turn comes up."
L["Road beacon"] = "Road beacon"
L["Shows a light beam, turn icon and distance on the road ahead in the world."] = "Shows a light beam, turn icon and distance on the road ahead in the world."
L["Window sounds"] = "Window sounds"
L["Plays the game's quest log sounds in the Cabbie window: opening, closing, turning a page and picking a row."] = "Plays the game's quest log sounds in the Cabbie window: opening, closing, turning a page and picking a row."
L["World map line"] = "World map line"
L["Draws your route on the world map."] = "Draws your route on the world map."
L["Minimap line"] = "Minimap line"
L["Draws your route on the minimap as a line of dots."] = "Draws your route on the minimap as a line of dots."
L["Minimap button"] = "Minimap button"
L["A button on the edge of the minimap that opens the Cabbie window."] = "A button on the edge of the minimap that opens the Cabbie window."
L["Lets Cabbie take waypoint coordinates written the way guides and web sites write them. The word is only claimed when no other add-on already owns it."] = "Lets Cabbie take waypoint coordinates written the way guides and web sites write them. The word is only claimed when no other add-on already owns it."
L["Cheap timers for the performance report."] = "Cheap timers for the performance report."
L["not available, Cabbie's own layout editor instead"] = "not available, Cabbie's own layout editor instead"
L["Cabbie cannot route in %s yet: Cabbie was updated while the game was open. Close the game completely and start it again."] = "Cabbie cannot route in %s yet: Cabbie was updated while the game was open. Close the game completely and start it again."



L["%s cut across city streets and squares on lines checked against the city map; nobody has walked those exact lines."] = "%s cut across city streets and squares on lines checked against the city map; nobody has walked those exact lines."

L["You still have your route from last time, with one stop. Pick up where you left off?"] = "You still have your route from last time, with one stop. Pick up where you left off?"
L["You still have your route from last time, with %d stops. Pick up where you left off?"] = "You still have your route from last time, with %d stops. Pick up where you left off?"
L["Keep Going"] = "Keep Going"
L["Clear It"] = "Clear It"
L["%s of this route is a guessed way over open ground (drawn dashed on the maps); expect obstacles."] = "%s of this route is a guessed way over open ground (drawn dashed on the maps); expect obstacles."
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


L["Search a town, a person or 42.5 65.1"] = "Search a town, a person or 42.5 65.1"
L["Show Only"] = "Show Only"
L["Everything"] = "Everything"
L["Add Stop"] = "Add Stop"
L["Add to Favorites"] = "Add to Favorites"
L["Remove from Favorites"] = "Remove from Favorites"
L["Pick a place first"] = "Pick a place first"
L["Double-click to be guided there"] = "Double-click to be guided there"
L["I don't know of an inn, flight master, bank or mailbox nearby."] = "I don't know of an inn, flight master, bank or mailbox nearby."
L["Auction House"] = "Auction House"
L["Weapon Master"] = "Weapon Master"


L["Your Route"] = "Your Route"
L["Move Up"] = "Move Up"
L["Move Down"] = "Move Down"
L["Best Order"] = "Best Order"
L["Confirm Best Order"] = "Confirm Best Order"
L["Choose Confirm Best Order to reorder your stops by travel distance."] = "Choose Confirm Best Order to reorder your stops by travel distance."
L["Total %s"] = "Total %s"
L["Prefer Roads"] = "Prefer Roads"
L["The stop you are heading to"] = "The stop you are heading to"
L["... and 1 more stop"] = "... and 1 more stop"
L["... and %d more stops"] = "... and %d more stops"
L["Other routes found: right-click Your Route to choose one."] = "Other routes found: right-click Your Route to choose one."
L["No stops yet. Search for a place above and press Go."] = "No stops yet. Search for a place above and press Go."
L["No stops yet. Search for a place above and press Go, or %s a place on the world map."] = "No stops yet. Search for a place above and press Go, or %s a place on the world map."
L["Your Route on the Places page; skip|clear"] = "Your Route on the Places page; skip|clear"

L["Right-click any place and choose Add to Favorites."] = "Right-click any place and choose Add to Favorites."
L["Clear Recent"] = "Clear Recent"
L["Favorites on the Places page; fav add [name]|list|remove <n>|<name>"] = "Favorites on the Places page; fav add [name]|list|remove <n>|<name>"
L["Type /cabbie recent clear again to confirm."] = "Type /cabbie recent clear again to confirm."

L["Ask to take me back to my body when I die"] = "Ask to take me back to my body when I die"
L["When you release your spirit, Cabbie asks whether to guide you back to your body. With this off, nothing is asked: as a ghost, pick Go to My Corpse at the top of the Places page, in your route's menu, or in the menu you get by right-clicking Cabbie beside the minimap."] = "When you release your spirit, Cabbie asks whether to guide you back to your body. With this off, nothing is asked: as a ghost, pick Go to My Corpse at the top of the Places page, in your route's menu, or in the menu you get by right-clicking Cabbie beside the minimap."

L["Click to be guided back to your body"] = "Click to be guided back to your body"


L["Training Dummy"] = "Training Dummy"
L["Training dummy"] = "Training dummy"


L["Show training dummies on the world map"] = "Show training dummies on the world map"
L["Training dummies of the zone you are looking at get a small icon on the world map. Left-click one to route there."] = "Training dummies of the zone you are looking at get a small icon on the world map. Left-click one to route there."
L["I don't know any training dummies here yet. Target one up close and I'll remember it."] = "I don't know any training dummies here yet. Target one up close and I'll remember it."

L["Cabbie has no map of %s. Ask again once you leave it."] = "Cabbie has no map of %s. Ask again once you leave it."

L["%s step onto or off a dock or landing; nobody has walked that step, and it is drawn like the path to it."] = "%s step onto or off a dock or landing; nobody has walked that step, and it is drawn like the path to it."

L["I can't find a way to %s, so I stopped following."] = "I can't find a way to %s, so I stopped following."

L["Release your spirit first, then I can take you to your body."] = "Release your spirit first, then I can take you to your body."
L["OK"] = "OK"

