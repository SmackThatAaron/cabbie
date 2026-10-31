# Changelog

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
