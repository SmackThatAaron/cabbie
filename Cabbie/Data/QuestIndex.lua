local ADDON_NAME, FGPS = ...





































FGPS.Data = FGPS.Data or {}

FGPS.Data.questIndex = {
  schema = 1,
  dataset = {
    rosterQuests = 6600,
    vanillaRecords = 3535,
    shipped = 3524,
    full = 3108,
    partial = 322,
    oneEnded = 94,
    dropped = 11,
    plausible = 2052,
    suspect = 1472,
    foreverListed = 922,
    foreverUnknown = 2143,
    foreverPositioned = 472,
  },
  dropped = {
    { n = 11, why = "neither where it is given nor where it is handed in has a position in any source" },
  },
  partial = {
    { n = 278, why = "an objective item has no placeable source" },
    { n = 22, why = "the objective is an event or a place the 1.12 records do not locate" },
    { n = 12, why = "an objective creature or object has no spawn" },
    { n = 10, why = "an objective item has no placeable source, and another objective is unplaced" },
  },
  oneEnded = {
    { n = 86, why = "no giver position in any source: only the hand-in is known" },
    { n = 6, why = "no turn-in position in any source: only the giver is known" },
    { n = 1, why = "the giver's position falls on no Forever map: only the hand-in is known" },
    { n = 1, why = "the turn-in's position falls on no Forever map: only the giver is known" },
  },
  limits = {
    { n = 321, why = "an objective only on an instance map" },
    { n = 98, why = "giver only on an instance map" },
    { n = 94, why = "turn-in only on an instance map" },
  },
  qualityNames = {
    [1] = "the quest's zone gained areas Forever added, so the ground may have changed",
    [128] = "no source says where the quest is given, or no source says where it is handed in",
    [16] = "cmangos has no spawn for the giver; the start comes from the second source",
    [2] = "the second source puts the start more than 3 map units away",
    [256] = "an objective's place is reported by another source (AllTheThings), not from the 1.12 spawns or the later records",
    [32] = "an objective has no known place: nothing in the 1.12 records says where it is found",
    [4] = "the second source puts the start on a different map",
    [64] = "a place of this quest (an objective or the hand-in) is from later records than 1.12, not from the 1.12 spawns",
    [8] = "the giver stands inside a zone Forever added",
  },
  srcNames = {
    [1] = "cmangos creature spawn",
    [10] = "AllTheThings' own files, where an objective is done: reported by another source",
    [2] = "cmangos gameobject spawn",
    [3] = "cmangos item drop (the item that starts the quest)",
    [4] = "Forever client AreaTrigger table",
    [5] = "cmangos loot chain",
    [6] = "AllTheThings via forever-quest-markers",
    [7] = "Forever client QuestPOIBlob table",
    [8] = "lodestar",
    [9] = "cmangos quest_poi, from later records than 1.12",
  },
  kindNames = { [1] = "kill", [2] = "interact", [3] = "collect", [4] = "cast", [5] = "explore", [6] = "event" },
  zoneQuests = {
    [1411] = 97,
    [1412] = 51,
    [1413] = 179,
    [1416] = 64,
    [1417] = 70,
    [1418] = 54,
    [1419] = 17,
    [1420] = 64,
    [1421] = 43,
    [1422] = 76,
    [1423] = 98,
    [1424] = 69,
    [1425] = 40,
    [1426] = 78,
    [1427] = 26,
    [1428] = 71,
    [1429] = 73,
    [1430] = 4,
    [1431] = 67,
    [1432] = 46,
    [1433] = 39,
    [1434] = 191,
    [1435] = 36,
    [1436] = 37,
    [1437] = 100,
    [1438] = 80,
    [1439] = 69,
    [1440] = 64,
    [1441] = 49,
    [1442] = 39,
    [1443] = 64,
    [1444] = 93,
    [1445] = 66,
    [1446] = 122,
    [1447] = 44,
    [1448] = 58,
    [1449] = 38,
    [1450] = 25,
    [1451] = 93,
    [1452] = 59,
    [1453] = 180,
    [1454] = 148,
    [1455] = 132,
    [1456] = 69,
    [1457] = 56,
    [1458] = 100,
    [2548] = 1,
  },
  doors = {
    {
      name = "Alterac Valley",
      instanceMap = 30,
      entrance = { inst = 0, x = -1085.7, y = 536.5, map = 1416 },
      source = "cmangos:areatrigger_teleport:2606 (exit target, \"Alterac Valley - Horde Exit\")",
    },
    {
      name = "Alterac Valley",
      instanceMap = 30,
      entrance = { inst = 0, x = -184.9, y = 101.1, map = 1416 },
      source = "cmangos:areatrigger_teleport:2608 (exit target, \"Alterac Valley - Alliance Exit\")",
    },
    {
      name = "Deeprun Tram",
      instanceMap = 369,
      entrance = { inst = 0, x = -1317.7, y = -4839.5, map = 1455 },
      source = "cmangos:areatrigger_teleport:2166 (exit target, \"Deeprun Tram - Ironforge Instance (Inside)\")",
    },
    {
      name = "Deeprun Tram",
      instanceMap = 369,
      entrance = { inst = 0, x = 524.1, y = -8354.2, map = 1453 },
      source = "cmangos:areatrigger_teleport:2171 (exit target, \"Deeprun Tram - Stormwind Instance (Inside)\")",
    },
    {
      name = "Arathi Basin",
      instanceMap = 529,
      entrance = { inst = 0, x = -2531.8, y = -1215.6, map = 1417 },
      source = "cmangos:areatrigger_teleport:3948 (exit target, \"Arathi Basin Alliance Out\")",
    },
    {
      name = "Arathi Basin",
      instanceMap = 529,
      entrance = { inst = 0, x = -3518.5, y = -831.9, map = 1417 },
      source = "cmangos:areatrigger_teleport:3949 (exit target, \"Arathi Basin Horde Out\")",
    },
  },
}
