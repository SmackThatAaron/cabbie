# Cabbie

Cabbie is a sat-nav for WoW: Forever. Tell it where you want to go and it works out the way: roads, flight paths, boats, zeppelins, lifts, the tram, and right into dungeons and raids, room by room. Then it talks you through it one turn at a time.

While you travel, the next steps sit beside your quest list, a short call-out pops up before each turn, and the route is drawn on your map and minimap. Turn on voice guidance and a voice will tell you "in 80 yards, turn left" so you can keep your eyes on the game. The voice is built in, so it works the same on Windows, Mac and Linux.

Cabbie only ever shows you the way. It never moves, steers or clicks for your character.

## How to use it

- Open the world map and type a place, a quest, or a word like *inn* or *repair* into the search box. Or type `/go Goldshire` in chat.
- Shift-click anywhere on the world map to head straight there. Ctrl + Right-click adds the spot as a stop instead; you can change that click in the settings.
- Right-click a quest and pick **Take me there**.
- Heading to a dungeon or raid? Type its name, or the short one everyone uses (BRD, ZG, Naxx...). Cabbie leads you to the door and on inside to the room or boss you picked.
- Need an inn, a bank or a repair? Search *inn*, *bank* or *repair*, or open the Points of interest tab, and it takes you to the nearest one.

By default Cabbie sticks to the roads, like a car would. If you'd rather cut across country when it's quicker, tick **Allow shortcuts off the road** in the settings.

A few other handy bits: run back to your corpse after you release, follow a party member with `/cabbie follow <name>`, share where you're heading with `/cabbie share`, and `/way` waypoints from guides work too. `/cabbie help` lists everything.

## Installing

Extract the whole zip into your `Interface/AddOns` folder. You'll get `Cabbie` plus six map folders; keep all seven enabled. Then restart the game properly, because a `/reload` won't pick up new folders. Do the same after each update.

## Heads up

Most zones have their roads now, but a few still have only part of them, so routes there follow rough directions in places, shown as dashed lines (Darkshore's coast road is one). Some dungeon areas don't have a route inside yet. The voice is English only. If a route looks off, a screenshot plus `/cabbie report` really helps.

## Credits

Free and open source under GPL-3.0. Thanks to HereBeDragons, LibStub and CallbackHandler, CMaNGOS classic-db, wago.tools, MelloUI, Carbonite, AllTheThings, the warcraft.wiki.gg contributors (CC BY-SA 4.0) and the Kokoro-82M voice model (Apache-2.0). Full notices are in `Cabbie/LICENSES.txt`.

## About this repository

This is where each released version of Cabbie lives, exactly as it's uploaded to CurseForge. Every release is a commit with a matching tag (`v1.0.0` and so on), so you can always grab or compare an older version. It's updated now and then, when a new version comes out.

Not made or endorsed by Blizzard Entertainment.
