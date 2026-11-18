# Changelog

## 1.10.0 (2026-11-18)

Restart the game completely after updating (a `/reload` will not load updated add-on files and tables of contents).

- **Blackfathom Deeps sunken temple entrance:** Routes from Ashenvale to Blackfathom Deeps (`BFD`) and on inside to its bosses now follow Zoram Strand's spiral stairwell, west archway, and underground corridor right to the dungeon portal instead of stopping on the cliff above, including with **Only use verified paths** turned on.
- **Multi-level & spiral ramp guidance:** Live route tracking, the on-screen turn arrow, and the 3D Road beacon now stay locked to your current floor on spiral staircases, corkscrew ramps, and vertically overlapping multi-level walkways and dungeons instead of jumping to levels overhead or underneath.

## 1.9.0 (2026-11-17)

Restart the game completely after updating (a `/reload` will not load new or removed files).

- **Purely visual navigation:** Spoken voice guidance, recorded voice clips, client text-to-speech, route audio cues, and all voice settings have been removed so Cabbie stays light and purely visual (book window click sounds remain).
- **Sharper roads & wider 20-yard road corridor:** Updated outdoor roads and capital-city street crossings across all 50 maps so routes follow bends, bridges, canyons, mountain switchbacks, and valley floors cleanly without cutting corners or snapping through cave walls, and widened road tracking to 20 yards on either side of the road so you never have to run down the dead centre.
- **Smoother live guidance + High-resolution mode:** Road curves and open-ground paths smooth out choppy zig-zags, the 3D Road beacon glides smoothly across hills and bends while staying grounded on roads and shorelines, the turn arrow tracks curves continuously, minimap dots stay planted on the road, and an optional **High-resolution navigation** toggle under `Settings > Cabbie > Advanced` adds finer curve detail and faster live updates.
- **Clear "Above" & "Below" height cues:** The 3D Road beacon and turn arrow now show **Above** / **Below** height badges with the vertical distance, flat roads show a grounded centre dot inside the beacon ring, and minimap markers add up/down chevrons when a turn or stop is on another level.
- **5-man dungeon boss routing & Forever updates:** Added room-by-room boss routing across all 5-man dungeons (search a boss's name, right-click a dungeon entrance icon on the world map for **Bosses**, or pick from the **Bosses** button on the map and the list at the top of **Places** once inside), hid locked raids while raids are closed in WoW Forever, updated airship and flight timings, put **Favorites** first in search with closest-first distance badges on services and trainers, and improved right-click menus everywhere.

## 1.8.0 (2026-11-13)

Restart the game completely after updating (a `/reload` will not load new files).

- **3D Road beacon by default + pick either or both:** New and default world guidance now uses the **Road beacon** (a 3D light beam, turn icon, and distance on the road ahead) on its own, while `/cabbie setup` and Settings let you pick the Road beacon, the **Turn arrow**, or both together.
- **What's New visual update window:** Updating Cabbie now pops up a **What's New** window once per release (and any time via `/cabbie whatsnew` or `/cabbie news`) with a live HUD preview, hover spotlighting, and one-click toggles for new guidance options.
- **Add to Favorites everywhere:** Right-clicking any place icon on the world map, any stop in **Your Route**, the **Route** block or stop/destination pins on the world map, or any match in the `/go` and world-map search dropdowns now offers **Add to Favorites** / **Remove from Favorites**, and `/cabbie fav <name>` or `/cabbie fav <number>` starts guidance right away.
- **Smoother road-centred turn arrow (4-yard buffer):** Walking or riding within 4 yards of a road's centreline now keeps the turn arrow pointing straight down the road instead of swinging hard towards road nodes beside you, while nudging smoothly back towards the route if you drift further off.

## 1.7.0 (2026-11-13)

Restart the game completely after updating (a `/reload` will not load new files).

- **Pick your guidance style + optional 3D Road beacon:** First-time setup (`/cabbie setup`) now lets you choose any mix of **Turn arrow** (on by default), **Road beacon** (a 3D light beam, turn icon, and distance on the road ahead), **Voice guidance**, and **Step list**.
- **Shift-click quests anywhere:** Shift + Left-click (while no chat box is open) or Ctrl + Left-click a quest in the quest sidebar (both the game's tracker and Questie's tracker, without untracking it), in the quest view (quest list or open quest details), or right on a quest icon on the world map to start routing there.
- **Navigation stays visible in combat:** Visual guidance (including the turn arrow) now stays shown during fights by default while voice waits until combat ends (`Settings > Cabbie > Advanced` still offers **Keep All Guidance** and **Hide all guidance**).
- **Wider 50-yard arrival auto-completion:** Routes now complete automatically within 50 yards by default (configurable up to 100 yards in `Settings > Cabbie > Advanced`) while still guiding you tightly around final turns and short local walks.

## 1.6.0 (2026-11-12)

Restart the game completely after updating (a `/reload` will not load new files).

- **Navigation only + Questie support:** Built-in quest pages and pins are removed so Cabbie stays focused on routing. With Questie installed, search any quest name or Ctrl-click a quest in your log or tracker to route to its next step.
- **Enemy town avoidance:** Routes now go around the other faction's guarded towns and outposts by default (toggle in Settings > Cabbie > Advanced).
- **Trainers, services & training dummies:** Finds Forever's new trainers and services via QuestieDB, city guard directions, or trainers you visit, plus searchable training dummies.
- **Updated world & dungeon routes:** Updated flights, transports, and road paths for WoW Forever (including Thoradin's Wall, Silverpine trails, Bloodvenom Post, Blackwing Lair, Naxxramas' Frostwyrm Lair, Scholomance, and Maraudon), plus cleaner floor detection in multi-level cities.
- **Map clicks & pins:** Clicking a new spot on the world map or dropping a map pin routes there right away; Shift + Right-click removes the nearest stop.
- **UI & arrow polish:** Your Route now lives at the top of the Places page, minimap markers use round parchment-and-ink icons, Large text size updates right away, corpse runs sit on the Places page without death popups, and the game's extra screen-edge arrow is hidden while Cabbie's turn arrow is active.

## 1.4.0 (2026-11-04)

- Cabbie is now for WoW Forever only; Classic Era is no longer supported. Extract the zip into the `Interface/AddOns` folder of your WoW Forever install and restart the game after updating: a /reload does not pick up new add-on folders.
- A new book-style window opens from the game's add-on compartment beside the minimap: left-click opens it, right-click shows a small menu. Its Places page replaces the Where to window. With nothing typed it lists the nearest innkeeper, flight master, bank and mailbox by route; typing searches places; your favorites and recent places sit under the nearest services, and a right-click on one renames it, removes it or adds it as a stop.
- Quest help is off by default, so out of the box Cabbie is pure navigation: no quest pins, objective areas, "!" pick-up marks, Quests or Optimized Leveling pages, and nothing added to the game's quest menus. Turn on Quest help under Quests in Cabbie's settings to get them back; even then, the "!" pick-up marks and the quest pins on the minimap stay off until you tick them too. If you had quest help on before, this update switches it off once; anything you turn back on stays on.
- With Quest help on, the Quests page lists your quests with each one's next step and a quest search, and the Optimized Leveling page shows the next stop's quests for your faction, race and class, with Accept, Objective or Turn in beside them. Double-click a row to be guided there; right-click it for Show on Map or Skip Step. Optimized Leveling no longer offers quests your race, class or side cannot take, both quests of a "one of" pair, or quests you cannot pick up yet.
- A new look: the turn arrow is a gilded arrow that glows softly at each turn ("Pulse at turns" in Edit Mode switches that off) with its words on a small parchment scroll. The route on the world map is drawn in dark ink, solid on roads, dashed over open ground and dotted for flights, boats and zeppelins, with numbered stops and an inked X at the destination, and a route started with the map open draws itself across it. The route dots on the minimap are ink-dark too.
- The nearest services on the Places page no longer go blank while you follow a route.
- Smaller fixes: the voice says "You have arrived at your destination." once, and no longer says "Disembark" in the middle of a ride after a fight; pressing Enter in the search gives the keyboard back so you can move at once; menus and tooltips read like the game's own (Stop Route, Turn in); the turn arrow can be picked up in Edit Mode every time; many quest search fixes.

Known gaps: parts of this release were played in WoW Forever on its launch day; the newest changes were checked with the automated tests only. Routes inside some dungeon areas are still missing or rough. The voice is English only.

## 1.3.0 (2026-10-31)

- Guidance now leads you inside dungeons and raids, to rooms and bosses. At a dungeon's door the route says "Enter" and the dungeon's name and picks the wing your place is in; inside, the call-out names the next room and the one after it, says when the next room is up or down, and keeps going after the loading screen until you arrive. A quest objective inside a dungeon or raid leads inside to it, room by room. Uldaman's rooms and more of the Ruins of Lordaeron now have a way in, and inside Zul'Gurub and the Excavation Site the way follows the floor instead of a straight line through a wall.
- Search finds dungeons and raids by the names players type (RFC, WC, DM East, BRD, UBRS, ZG, AQ40, Naxx and more), and also finds their rooms and raid bosses; picking one leads you inside. The Where to window lists a dungeon's rooms and bosses while you are in it. Three Forever dungeons can be routed to: Ruins of Lordaeron, City of Dalaran and Excavation Site: Wetlands. Raid entrances now show on the world map.
- More roads in the Eastern Kingdoms and Kalimdor: Thelgen Rock, the Wetlands' main road, Tarren Mill, Strahnbrad, Arathi Highlands, Loch Modan, Westfall, the way into Dun Algaz, Dolanaar to Darnassus, western Azshara and more of Feralas. Routes keep to them instead of a straight guess, with fewer steps through walls and fences, and "Make a U-turn" where two roads meet is now the turn you actually make.
- Routes no longer cross fel, slime or lava on a guessed line, nor cut across a valley or canyon between two heights. Bloodvenom Post in Felwood can be walked out of and into, with a warning before the one stretch through fel, and the route explanation says that stretch is fel, not water. The Skywatcher Plateau skyship dock is reached by the south lift from Thunder Bluff.
- Boats, zeppelins and flights are planned more truthfully. The Undercity to Grom'gol zeppelin takes about two minutes, so Tirisfal to Stranglethorn no longer changes at Orgrimmar. The Southshore ship sails Southshore, Auberdine, Menethil Harbor and waits at its own pier. On the ship from Auberdine to Southshore the route tells you to stay aboard at Menethil Harbor. The voice says where a ride ends, and a long boat trip counts its real distance.
- Routes come sooner: long walks such as Auberdine to Shen'dralas or Mount Hyjal take a fraction of the work they did, and a new route after you leave the route is found faster. Cabbie also uses a little less memory on the first search, and map lines on the world map keep up as you drag or zoom.
- Quests: givers and hand-ins inside Ironforge, Orgrimmar and Thunder Bluff now show on the city's own map. Givers only the other side may speak to are no longer offered, quests that need faction standing say which standing is in the way, and "Avoid high-level areas" also counts patrolling and elite creatures. Wallace the Blind in Silverpine can be found as a weapon seller, and the nearest inn is no longer a hanging sign with no innkeeper.
- Voice and languages: the recorded voice says "Route cleared", "Follow the ramp" and "Continue across open ground", plays more reliably when the game refuses it at full volume, says "you have arrived" only once, and has a Play a sample button in the voice settings. Directions and vehicles are translated in German, Spanish, French, Italian, Korean, Portuguese, Russian and Chinese, and windows use the game's own font for your language.
- Smaller fixes: dying mid-route keeps your route behind the run to your body; "Destination set" no longer clutters chat; the Go to field no longer covers the floor buttons; hiding the interface no longer forgets your picked quest; the settings, stops and favorites commands and messages are clearer, including decimal-comma coordinates in /way and /go. Cabbie no longer keeps a diagnostic record of your sessions in its saved variables.

Known gaps: routes inside some dungeon areas are still missing or rough, and the Hall of Thanes, Half-Pint Tavern, Manor Mistmantle and the new raids have no door yet. Darkshore's coast road is still a rough direction. The voice is English only.

## 1.2.0 (2026-10-22)

- A bigger, clearer turn arrow at the top of the screen that swings smoothly to the new direction. Move it in Edit Mode ("Turn arrow") and choose its style, size, colour and opacity, and whether its words and distance show.
- Routes go round fel, slime and lava instead of through them.
- New roads in Westfall, the Wetlands, Darkshore, Azshara and Shen'dralas. The Stonetalon road follows the canyon west of Mirkfallon Lake, and roads keep to their bends.
- Steps name the town a road leads to, for example "Follow the road toward Goldshire".
- Your Hearthstone is found and used more reliably: Cabbie learns where it takes you when you set your home at an inn or first use it.
- The quest window has the game's own look, lists quests you can pick up nearby in walking order, and opens from a click in the quest tracker.
- Where to: Go starts the route at once, the window stays open, and Services and Lists are one "Points of interest" tab with inns, mailboxes and banks.
- The list of route steps beside the quest list is hidden by default; turn it on under Guidance. Signpost roads are drawn like every other road. A round minimap button, and routes appear sooner.

Known gaps: some zones still have only part of their roads, so routes there follow rough directions in places. The voice is English only.

## 1.1.0 (2026-10-19)

- Narrow roads stay roads. Where a narrow road had a short gap in Cabbie's map, the route now carries straight on along it instead of cutting a rough line beside it, for example south of the Crossroads on the way to Camp Taurajo.
- The road north of Razor Hill no longer wanders off to the side.
- The Hinterlands, the Swamp of Sorrows and Desolace now have part of their roads.

Known gaps: some zones, among them Westfall, Wetlands, Azshara and Darkshore, still have no road data, so routes there follow rough directions. The voice is English only.

## 1.0.0 (2026-10-18)

The first full release.

- Routes follow the roads of each zone, and stay on them unless you tick "Allow shortcuts off the road".
- Flights, boats, zeppelins, the Deeprun Tram, lifts and portals are all part of the route, and so are your Hearthstone and teleport spells when they're ready.
- Guidance beside the quest list, a call-out before each turn, and the route drawn on the world map and minimap.
- Voice guidance in Cabbie's own recorded voice, the same on every computer, or the game's own text-to-speech voice if you prefer.
- Search the world map or type `/go` and a place; search for the nearest inn, bank, repairer and more; "Take me there" on any quest.
- Each continent's map loads only when it's needed, so Cabbie stays light on memory.

Known gaps: about twenty zones have no road data yet, so routes there follow rough directions. The voice is English only.
