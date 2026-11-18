# Cabbie

Cabbie is a sat-nav for WoW: Forever. Tell it where you want to go and it works out the way: roads, flight paths, boats, zeppelins, lifts, the tram, and right into dungeons, room by room. Then it guides you there one turn at a time.

While you travel, a **Road beacon** places a 3D light beam and turn icon on the road ahead by default, the route is drawn in ink on your world map and minimap, an optional turn arrow sits at the top of the screen (with optional words and distance in Edit Mode), "Above" and "Below" height badges mark climbs, descents, and stops on another level, and an optional Route block beside your quest list names the next steps. On first setup (`/cabbie setup`) or after updates (`/cabbie whatsnew`), you can pick one, the other, or both world guidance styles.

Cabbie only ever shows you the way. It never moves, steers or clicks for your character.

## How to use it

- Click Cabbie in the add-on compartment beside the minimap (or its button on the world map) to open the **Places** page: Your Route while a route is set, the nearest innkeeper, flight master, bank and mailbox, your Favorites and Recent places, and a search box. You can also search at the top left of the world map, or type `/go Goldshire` in chat.
- Shift-click anywhere on the world map (or place a map pin, or use Ctrl + Right-click) to head straight there. Shift + Right-click removes the nearest stop. While adding stops from Your Route, clicks add stops instead.
- Shift-click or Ctrl-click any quest in your quest sidebar (the game's tracker or Questie's tracker), in your quest view (the quest list or open quest details), or right on a quest icon on the world map to head to its next place. With Questie installed, you can also type a quest's name into Cabbie's search to pick its next objective or turn-in.
- Need an inn, bank, mailbox, repairer, class trainer or training dummy? Type the word, pick a category under **Show Only** on the Places page, or use **Go to Nearest** on the minimap. Saved Favorites appear first, and matching services and trainers sort closest-first with a live distance badge. Ask a city guard for directions and click **Take Me There** when Cabbie asks; with QuestieDB installed, Forever's extra services and trainers are included too.
- Heading to a dungeon? Type its name or short name (RFC, WC, BFD, DM East, BRD, UBRS...) to route to the door, or search a boss's name, right-click a dungeon entrance icon on the world map for **Bosses**, or use the **Bosses** button on the map and the list at the top of **Places** once inside to be guided floor by floor to a boss's room.

By default Cabbie sticks to the roads and goes round the other side's guarded towns and outposts. Both can be changed under **Settings > Cabbie > Advanced** (alongside **Allow shortcuts off the road** and **High-resolution navigation**).

A few other handy bits: pick **Go to My Corpse** on the Places page or type `/cabbie corpse` after you release, follow a party member with `/cabbie follow <name>`, share where you're heading with `/cabbie share`, and `/way` waypoints from guides work too. `/cabbie help` lists everything.

## Installing

Extract the whole zip into your WoW Forever `Interface/AddOns` folder. You'll get `Cabbie` plus seventeen map folders; keep all eighteen enabled. Close the game completely and start it again after installing or updating, because `/reload` won't pick up new or updated folders and files.

## Heads up

A few stretches still follow rough directions, shown as dashed lines on the map (Darkshore's coast road is one), and some dungeon areas don't have a full route inside yet. Questie support and learned training dummies read English clients only. If a route looks off, a screenshot plus `/cabbie report` really helps.

## Credits

Free and open source under GPL-3.0-or-later. Thanks to HereBeDragons-2.0, LibStub, CallbackHandler-1.0, MelloUI, CMaNGOS classic-db, Blizzard game data through wago.tools, the warcraft.wiki.gg contributors (CC BY-SA 4.0), and Carbonite. Full notices are in `Cabbie/LICENSES.txt`.

## About this repository

This is where each released version of Cabbie lives, exactly as it's uploaded to CurseForge. Every release is a commit with a matching tag (`v1.0.0` and so on), so you can always grab or compare an older version. It's updated now and then, when a new version comes out.

Not made or endorsed by Blizzard Entertainment.
