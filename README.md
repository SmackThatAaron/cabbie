# Cabbie

Cabbie is a sat-nav for WoW: Forever. Tell it where you want to go and it works out the way: roads, flight paths, boats, zeppelins, lifts, the tram, the lot. Then it talks you through it one turn at a time.

While you travel, the next steps sit beside your quest list, a short call-out pops up before each turn, and the route is drawn on your map and minimap. Turn on voice guidance and a voice will tell you "in 80 yards, turn left" so you can keep your eyes on the game. The voice is built in, so it works the same on Windows, Mac and Linux.

Cabbie only ever shows you the way. It never moves, steers or clicks for your character.

## How to use it

- Type a place into the search box on the world map, or `/go Goldshire` in chat.
- Shift-click anywhere on the world map to head there.
- Right-click a quest and pick **Take me there**.
- Need an inn, a bank or a repair? Just search *inn*, *bank* or *repair* and it takes you to the nearest one.

By default Cabbie sticks to the roads, like a car would. If you'd rather cut across country when it's quicker, tick **Allow shortcuts off the road** in the settings.

A few other handy bits: run back to your corpse after you release, follow a party member with `/cabbie follow <name>`, share where you're heading with `/cabbie share`, and `/way` waypoints from guides work too. `/cabbie help` lists everything.

## Installing

Extract the whole zip into your `Interface/AddOns` folder. You'll get `Cabbie` plus five map folders; keep all six enabled. Then restart the game properly, because a `/reload` won't pick up new folders.

## Heads up

Some zones don't have road data yet (Westfall, Wetlands, Darkshore and a few others), so routes there follow rough directions, shown as dashed lines. The voice is English only. Forever is still in beta, so if a route looks off, a screenshot plus `/cabbie report` really helps.

## Credits

Free and open source under GPL-3.0. Thanks to HereBeDragons, LibStub and CallbackHandler, CMaNGOS classic-db, wago.tools, MelloUI, Carbonite, AllTheThings, the warcraft.wiki.gg contributors (CC BY-SA 4.0) and the Kokoro-82M voice model (Apache-2.0). Full notices are in `Cabbie/LICENSES.txt`.

## About this repository

This is where each released version of Cabbie lives, exactly as it's uploaded to CurseForge. Every release is a commit with a matching tag (`v1.0.0` and so on), so you can always grab or compare an older version. It's updated now and then, when a new version comes out.

Not made or endorsed by Blizzard Entertainment.
