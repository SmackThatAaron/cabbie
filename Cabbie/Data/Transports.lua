local ADDON_NAME, FGPS = ...















FGPS.Data = FGPS.Data or {}

FGPS.Data.transports = {
  [9253] = {
    name = "Southshore - Menethil Harbor", kind = "boat", fac = 0, period = 266,
    source = "taxipath:253",
    path = 253, speed = 23.8,
    unverified = true,
    notes = {
      "docks derived from geometry (no TaxiPathNode Delay on this path)",
      "speed 23.8 yd/s not implied by a cmangos period",
      "period 266 s is computed (spline yards / speed + dock dwell); no source period exists",
    },
    stops = {
      { inst = 0, x = -545.7, y = -988, map = 1424, name = "Southshore dock", wait = 0 },
      { inst = 0, x = -536.7, y = -3748.3, map = 1437, name = "Menethil Harbor dock", wait = 0 },
    },
    legs = {
      { from = 1, to = 2, seconds = 135, yards = 3208.5,
        points = { {-545.7,-988}, {-599.5,-1009.6}, {-664.2,-1089.3}, {-747.7,-1279.8}, {-882.5,-1454.7}, {-920.4,-1620}, {-887.4,-1793.8}, {-854.2,-2030.5}, {-852.3,-2456.7}, {-716.8,-2694}, {-527.7,-2773}, {-400.1,-2926.8}, {-353.2,-3187.8}, {-524.1,-3453.1}, {-622.5,-3627.8}, {-536.7,-3748.3} } },
      { from = 2, to = 1, seconds = 131, yards = 3108.4,
        points = { {-536.7,-3748.3}, {-402.7,-3678}, {-377.9,-3534.5}, {-500.4,-3292.9}, {-701.6,-3073.8}, {-812.7,-2758.6}, {-859.3,-2455.8}, {-876.6,-1975.8}, {-747,-1829.5}, {-658.4,-1697.6}, {-626.2,-1557.4}, {-528.6,-1411}, {-493.9,-1265.8}, {-481,-1139.7}, {-499.3,-1035.9}, {-545.7,-988} } },
    },
  },
  [9450] = {
    name = "Gnomeregan lift", kind = "elevator", fac = 0, period = 27,
    source = "cmangos gameobject 9450 (Vator, entry 80023) + TransportAnimation 80023 (26667 ms)",
    notes = {
      "ride 5 s down and 5 s up: the car's run between its landings in TransportAnimation 80023 (4566 and 4567 ms of the 26667 ms cycle); it waits 6.9 s at the top and 10.7 s at the bottom",
      "landings at z 349.5 and 249.4: the spawn height 349.5 plus the highest and the lowest keyframe offset",
    },
    stops = {
      { inst = 0, x = 650.4, y = -5164.2, z = 349.5, map = 1426, name = "Gnomeregan lift upper landing", wait = 7 },
      { inst = 0, x = 650.4, y = -5164.2, z = 249.4, map = 1426, name = "Gnomeregan lift lower landing", wait = 11 },
    },
    legs = {
      { from = 1, to = 2, seconds = 5, yards = 0,
        points = { {650.4,-5164.2}, {650.4,-5164.2} } },
      { from = 2, to = 1, seconds = 5, yards = 0,
        points = { {650.4,-5164.2}, {650.4,-5164.2} } },
    },
  },
  [16874] = {
    name = "Great Lift", kind = "elevator", fac = 0, period = 30,
    source = "cmangos gameobject 16874 (Mesa Elevator, entry 11898) + TransportAnimation 11898 (30000 ms)",
    notes = {
      "ride 10 s down and 10 s up: the car's run between its landings in TransportAnimation 11898 (10000 and 9900 ms of the 30000 ms cycle); it waits 5.1 s at the top and 5.0 s at the bottom",
      "landings at z 85.4 and -43.9: the spawn height 85.4 plus the highest and the lowest keyframe offset",
    },
    stops = {
      { inst = 1, x = -1827.7, y = -4665.4, z = 85.4, map = 1441, name = "Great Lift upper landing", wait = 5 },
      { inst = 1, x = -1827.7, y = -4665.4, z = -43.9, map = 1441, name = "Great Lift lower landing", wait = 5 },
    },
    legs = {
      { from = 1, to = 2, seconds = 10, yards = 0,
        points = { {-1827.7,-4665.4}, {-1827.7,-4665.4} } },
      { from = 2, to = 1, seconds = 10, yards = 0,
        points = { {-1827.7,-4665.4}, {-1827.7,-4665.4} } },
    },
  },
  [16875] = {
    name = "Freewind Post lift", kind = "elevator", fac = 0, period = 30,
    source = "cmangos gameobject 16875 (Mesa Elevator, entry 11898) + TransportAnimation 11898 (30000 ms)",
    notes = {
      "ride 10 s down and 10 s up: the car's run between its landings in TransportAnimation 11898 (10000 and 9900 ms of the 30000 ms cycle); it waits 5.1 s at the top and 5.0 s at the bottom",
      "landings at z 89.0 and -40.3: the spawn height 89.0 plus the highest and the lowest keyframe offset",
    },
    stops = {
      { inst = 1, x = -2504.6, y = -5399.2, z = 89, map = 1441, name = "Freewind Post lift upper landing", wait = 5 },
      { inst = 1, x = -2504.6, y = -5399.2, z = -40.3, map = 1441, name = "Freewind Post lift lower landing", wait = 5 },
    },
    legs = {
      { from = 1, to = 2, seconds = 10, yards = 0,
        points = { {-2504.6,-5399.2}, {-2504.6,-5399.2} } },
      { from = 2, to = 1, seconds = 10, yards = 0,
        points = { {-2504.6,-5399.2}, {-2504.6,-5399.2} } },
    },
  },
  [16876] = {
    name = "Great Lift", kind = "elevator", fac = 0, period = 30,
    source = "cmangos gameobject 16876 (Mesa Elevator, entry 11899) + TransportAnimation 11899 (30000 ms)",
    notes = {
      "ride 10 s down and 10 s up: the car's run between its landings in TransportAnimation 11899 (10000 and 10000 ms of the 30000 ms cycle); it waits 5.0 s at the top and 5.0 s at the bottom",
      "landings at z 85.4 and -44.1: the spawn height -44.1 plus the highest and the lowest keyframe offset",
    },
    stops = {
      { inst = 1, x = -1849.6, y = -4670.8, z = 85.4, map = 1441, name = "Great Lift upper landing", wait = 5 },
      { inst = 1, x = -1849.6, y = -4670.8, z = -44.1, map = 1441, name = "Great Lift lower landing", wait = 5 },
    },
    legs = {
      { from = 1, to = 2, seconds = 10, yards = 0,
        points = { {-1849.6,-4670.8}, {-1849.6,-4670.8} } },
      { from = 2, to = 1, seconds = 10, yards = 0,
        points = { {-1849.6,-4670.8}, {-1849.6,-4670.8} } },
    },
  },
  [16877] = {
    name = "Freewind Post lift", kind = "elevator", fac = 0, period = 30,
    source = "cmangos gameobject 16877 (Mesa Elevator, entry 11899) + TransportAnimation 11899 (30000 ms)",
    notes = {
      "ride 10 s down and 10 s up: the car's run between its landings in TransportAnimation 11899 (10000 and 10000 ms of the 30000 ms cycle); it waits 5.0 s at the top and 5.0 s at the bottom",
      "landings at z 89.0 and -40.5: the spawn height -40.5 plus the highest and the lowest keyframe offset",
    },
    stops = {
      { inst = 1, x = -2489.4, y = -5382.5, z = 89, map = 1441, name = "Freewind Post lift upper landing", wait = 5 },
      { inst = 1, x = -2489.4, y = -5382.5, z = -40.5, map = 1441, name = "Freewind Post lift lower landing", wait = 5 },
    },
    legs = {
      { from = 1, to = 2, seconds = 10, yards = 0,
        points = { {-2489.4,-5382.5}, {-2489.4,-5382.5} } },
      { from = 2, to = 1, seconds = 10, yards = 0,
        points = { {-2489.4,-5382.5}, {-2489.4,-5382.5} } },
    },
  },
  [18298] = {
    name = "Thunder Bluff south lift", kind = "elevator", fac = 0, period = 30,
    source = "cmangos gameobject 18298 (Mesa Elevator, entry 4170) + TransportAnimation 4170 (30033 ms)",
    notes = {
      "ride 10 s down and 10 s up: the car's run between its landings in TransportAnimation 4170 (10000 and 10033 ms of the 30033 ms cycle); it waits 5.0 s at the top and 5.0 s at the bottom",
      "landings at z 130.1 and 68.8: the spawn height 130.1 plus the highest and the lowest keyframe offset",
    },
    stops = {
      { inst = 1, x = 189.7, y = -1286.2, z = 130.1, map = 1456, name = "Thunder Bluff south lift upper landing", wait = 5 },
      { inst = 1, x = 189.7, y = -1286.2, z = 68.8, map = 1456, name = "Thunder Bluff south lift lower landing", wait = 5 },
    },
    legs = {
      { from = 1, to = 2, seconds = 10, yards = 0,
        points = { {189.7,-1286.2}, {189.7,-1286.2} } },
      { from = 2, to = 1, seconds = 10, yards = 0,
        points = { {189.7,-1286.2}, {189.7,-1286.2} } },
    },
  },
  [18435] = {
    name = "Thunder Bluff south lift", kind = "elevator", fac = 0, period = 30,
    source = "cmangos gameobject 18435 (Mesa Elevator, entry 4171) + TransportAnimation 4171 (30000 ms)",
    notes = {
      "ride 10 s down and 10 s up: the car's run between its landings in TransportAnimation 4171 (10000 and 10000 ms of the 30000 ms cycle); it waits 5.0 s at the top and 5.0 s at the bottom",
      "landings at z 130.1 and 68.6: the spawn height 68.6 plus the highest and the lowest keyframe offset",
    },
    stops = {
      { inst = 1, x = 185.3, y = -1308.4, z = 130.1, map = 1456, name = "Thunder Bluff south lift upper landing", wait = 5 },
      { inst = 1, x = 185.3, y = -1308.4, z = 68.6, map = 1456, name = "Thunder Bluff south lift lower landing", wait = 5 },
    },
    legs = {
      { from = 1, to = 2, seconds = 10, yards = 0,
        points = { {185.3,-1308.4}, {185.3,-1308.4} } },
      { from = 2, to = 1, seconds = 10, yards = 0,
        points = { {185.3,-1308.4}, {185.3,-1308.4} } },
    },
  },
  [20639] = {
    name = "Thunder Bluff north lift", kind = "elevator", fac = 0, period = 30,
    source = "cmangos gameobject 20639 (Mesa Elevator, entry 47296) + TransportAnimation 47296 (30000 ms)",
    notes = {
      "ride 10 s down and 10 s up: the car's run between its landings in TransportAnimation 47296 (10000 and 10000 ms of the 30000 ms cycle); it waits 5.0 s at the top and 5.0 s at the bottom",
      "landings at z 140.5 and 69.0: the spawn height 69.0 plus the highest and the lowest keyframe offset",
    },
    stops = {
      { inst = 1, x = -28.4, y = -1028, z = 140.5, map = 1456, name = "Thunder Bluff north lift upper landing", wait = 5 },
      { inst = 1, x = -28.4, y = -1028, z = 69, map = 1456, name = "Thunder Bluff north lift lower landing", wait = 5 },
    },
    legs = {
      { from = 1, to = 2, seconds = 10, yards = 0,
        points = { {-28.4,-1028}, {-28.4,-1028} } },
      { from = 2, to = 1, seconds = 10, yards = 0,
        points = { {-28.4,-1028}, {-28.4,-1028} } },
    },
  },
  [20640] = {
    name = "Thunder Bluff north lift", kind = "elevator", fac = 0, period = 30,
    source = "cmangos gameobject 20640 (Mesa Elevator, entry 47297) + TransportAnimation 47297 (30033 ms)",
    notes = {
      "ride 10 s down and 10 s up: the car's run between its landings in TransportAnimation 47297 (10000 and 10033 ms of the 30033 ms cycle); it waits 5.0 s at the top and 5.0 s at the bottom",
      "landings at z 140.5 and 69.3: the spawn height 140.5 plus the highest and the lowest keyframe offset",
    },
    stops = {
      { inst = 1, x = -49.2, y = -1037.3, z = 140.5, map = 1456, name = "Thunder Bluff north lift upper landing", wait = 5 },
      { inst = 1, x = -49.2, y = -1037.3, z = 69.3, map = 1456, name = "Thunder Bluff north lift lower landing", wait = 5 },
    },
    legs = {
      { from = 1, to = 2, seconds = 10, yards = 0,
        points = { {-49.2,-1037.3}, {-49.2,-1037.3} } },
      { from = 2, to = 1, seconds = 10, yards = 0,
        points = { {-49.2,-1037.3}, {-49.2,-1037.3} } },
    },
  },
  [20808] = {
    name = "Ratchet - Booty Bay", kind = "boat", fac = 0, period = 351,
    source = "taxipath:241 + cmangos transports 20808 (Ratchet and Booty Bay, period 350818 ms)",
    path = 241, speed = 25.3,
    stops = {
      { inst = 1, x = -3841.6, y = -1005.6, map = 1413, name = "Ratchet dock", wait = 60 },
      { inst = 0, x = 582.9, y = -14277.7, map = 1434, name = "Booty Bay dock", wait = 60 },
    },
    legs = {
      { from = 1, to = 2, seconds = 110, yards = 2787, split = 12,
        points = { {-3841.6,-1005.6}, {-3877.1,-956.4}, {-3917.8,-935.5}, {-3981.3,-950.2}, {-4049.1,-1026.8}, {-4124.8,-1091.8}, {-4320.8,-1160.8}, {-4533.8,-1209.5}, {-4778.1,-1312.3}, {-4947.8,-1449}, {-5107.1,-1652.7}, {-5196.9,-1867.1}, {1558.3,-14335.8}, {1302,-14366.6}, {1081.1,-14338.3}, {867.3,-14366.7}, {733.7,-14351.3}, {635.4,-14342.5}, {582.9,-14277.7} } },
      { from = 2, to = 1, seconds = 121, yards = 3044.8, split = 8,
        points = { {582.9,-14277.7}, {578.4,-14171.9}, {626.5,-14088.3}, {732.2,-14052.8}, {852.5,-14122.9}, {865,-14351.6}, {833.4,-14917.5}, {808.3,-15089.8}, {-4966.5,-2031.8}, {-4933,-1969.4}, {-4794.2,-1734.3}, {-4641.6,-1558.6}, {-4431.8,-1441.7}, {-4266.7,-1370.2}, {-4139.9,-1264.9}, {-4019.7,-1212.5}, {-3887.8,-1154.2}, {-3824.1,-1105.5}, {-3818.9,-1058.5}, {-3841.6,-1005.6} } },
    },
  },
  [44892] = {
    name = "Undercity west lift", kind = "elevator", fac = 0, period = 17,
    source = "cmangos gameobject 44892 (Undervator, entry 20649) + TransportAnimation 20649 (16667 ms)",
    notes = {
      "ride 3 s down and 4 s up: the car's run between its landings in TransportAnimation 20649 (3333 and 3500 ms of the 16667 ms cycle); it waits 4.8 s at the top and 5.0 s at the bottom",
      "landings at z 55.7 and -40.8: the spawn height 14.7 plus the highest and the lowest keyframe offset",
    },
    stops = {
      { inst = 0, x = 291.8, y = 1596.2, z = 55.7, map = 1458, name = "Undercity west lift upper landing", wait = 5 },
      { inst = 0, x = 291.8, y = 1596.2, z = -40.8, map = 1458, name = "Undercity west lift lower landing", wait = 5 },
    },
    legs = {
      { from = 1, to = 2, seconds = 3, yards = 0,
        points = { {291.8,1596.2}, {291.8,1596.2} } },
      { from = 2, to = 1, seconds = 4, yards = 0,
        points = { {291.8,1596.2}, {291.8,1596.2} } },
    },
  },
  [44901] = {
    name = "Undercity south lift", kind = "elevator", fac = 0, period = 17,
    source = "cmangos gameobject 44901 (Undervator, entry 20655) + TransportAnimation 20655 (16667 ms)",
    notes = {
      "ride 3 s down and 4 s up: the car's run between its landings in TransportAnimation 20655 (3334 and 3500 ms of the 16667 ms cycle); it waits 4.8 s at the top and 5.0 s at the bottom",
      "landings at z 55.7 and -40.8: the spawn height -40.8 plus the highest and the lowest keyframe offset",
    },
    stops = {
      { inst = 0, x = 240.8, y = 1544.2, z = 55.7, map = 1458, name = "Undercity south lift upper landing", wait = 5 },
      { inst = 0, x = 240.8, y = 1544.2, z = -40.8, map = 1458, name = "Undercity south lift lower landing", wait = 5 },
    },
    legs = {
      { from = 1, to = 2, seconds = 3, yards = 0,
        points = { {240.8,1544.2}, {240.8,1544.2} } },
      { from = 2, to = 1, seconds = 4, yards = 0,
        points = { {240.8,1544.2}, {240.8,1544.2} } },
    },
  },
  [44962] = {
    name = "Undercity east lift", kind = "elevator", fac = 0, period = 17,
    source = "cmangos gameobject 44962 (Undervator, entry 20652) + TransportAnimation 20652 (16667 ms)",
    notes = {
      "ride 3 s down and 4 s up: the car's run between its landings in TransportAnimation 20652 (3333 and 3500 ms of the 16667 ms cycle); it waits 4.8 s at the top and 5.0 s at the bottom",
      "landings at z 55.7 and -40.8: the spawn height -40.8 plus the highest and the lowest keyframe offset",
    },
    stops = {
      { inst = 0, x = 188.6, y = 1595.3, z = 55.7, map = 1458, name = "Undercity east lift upper landing", wait = 5 },
      { inst = 0, x = 188.6, y = 1595.3, z = -40.8, map = 1458, name = "Undercity east lift lower landing", wait = 5 },
    },
    legs = {
      { from = 1, to = 2, seconds = 3, yards = 0,
        points = { {188.6,1595.3}, {188.6,1595.3} } },
      { from = 2, to = 1, seconds = 4, yards = 0,
        points = { {188.6,1595.3}, {188.6,1595.3} } },
    },
  },
  [164871] = {
    name = "Orgrimmar - The Undercity", kind = "zeppelin", fac = 2, period = 356,
    source = "taxipath:302 + cmangos transports 164871 (Orgrimmar and Undercity, period 356284 ms)",
    path = 302, speed = 24,
    stops = {
      { inst = 1, x = -4658, y = 1318.1, map = 1411, name = "Orgrimmar zeppelin tower", wait = 60 },
      { inst = 0, x = 293, y = 2062.4, map = 1420, name = "The Undercity zeppelin tower", wait = 60 },
    },
    legs = {
      { from = 1, to = 2, seconds = 137, yards = 3296.5, split = 12,
        points = { {-4658,1318.1}, {-4599.4,1311.8}, {-4555.8,1295.4}, {-4536.3,1263.5}, {-4564.3,1223.9}, {-4625,1218.9}, {-4700.3,1238.7}, {-4831.2,1255.5}, {-4961.9,1267.8}, {-5140.1,1268.5}, {-5370.2,1256.7}, {-5494.3,1260.3}, {1873.1,3170.1}, {1769.5,3049.9}, {1577.6,2731.3}, {1226.5,2318.6}, {1023.4,2123.6}, {779.7,1988.9}, {599.8,1949.9}, {465.4,1945.7}, {342.5,1988}, {293,2062.4} } },
      { from = 2, to = 1, seconds = 99, yards = 2386.1, split = 8,
        points = { {293,2062.4}, {283.7,2201.3}, {270.8,2437.4}, {264.8,2711.4}, {206.9,2906.6}, {269.3,3117.4}, {362.1,3218.6}, {417.8,3247.7}, {-5755.9,1320.5}, {-5686.1,1334.8}, {-5460.1,1363}, {-5170.1,1336.8}, {-4934.8,1277.2}, {-4773.1,1297.9}, {-4707.4,1309.9}, {-4658,1318.1} } },
    },
  },
  [175080] = {
    name = "Grom'gol Base Camp - Orgrimmar", kind = "zeppelin", fac = 2, period = 303,
    source = "taxipath:285 + cmangos transports 175080 (Grom'Gol Base Camp and Orgrimmar, period 303463 ms)",
    path = 285, speed = 22,
    stops = {
      { inst = 0, x = 231.6, y = -12464, map = 1434, name = "Grom'gol Base Camp zeppelin tower", wait = 60 },
      { inst = 1, x = -4631.3, y = 1360.9, map = 1411, name = "Orgrimmar zeppelin tower", wait = 60 },
    },
    legs = {
      { from = 1, to = 2, seconds = 110, yards = 2422.1, split = 8,
        points = { {231.6,-12464}, {141.6,-12564.8}, {177.1,-12677.8}, {296.4,-12730.4}, {463.6,-12703.1}, {633.1,-12667.5}, {904.5,-12612.8}, {1010.5,-12602.9}, {-5493.4,1131.6}, {-5400.9,1132.9}, {-5200.8,1166.7}, {-4935.5,1165.3}, {-4751.3,1129.7}, {-4526.6,1126.9}, {-4465.4,1223.5}, {-4508.2,1299.5}, {-4631.3,1360.9} } },
      { from = 2, to = 1, seconds = 73, yards = 1616.6, split = 7,
        points = { {-4631.3,1360.9}, {-4755.9,1468.6}, {-4918.9,1465.4}, {-5065.4,1453.2}, {-5230.6,1443}, {-5331.9,1441.4}, {-5433.2,1446.6}, {999.8,-12466}, {931.3,-12465.8}, {685.7,-12442.8}, {397.4,-12428}, {231.6,-12464} } },
    },
  },
  [176080] = {
    name = "Stormwind - Ironforge", kind = "tram", fac = 1, period = 143,
    source = "TransportAnimation 176080-176085 (143333 ms) + cmangos areatrigger_teleport 2173 + areatrigger:2173 + cmangos areatrigger_teleport 2175 + areatrigger:2175",
    notes = {
      "leg time 59 s = platform-to-platform run of TransportAnimation car 176080 (58633 ms of the 143333 ms cycle, 13.0 s dwell at each end); the walk between a street-level entrance and its platform is not included",
      "the two stops are the street-level station entrances",
    },
    stops = {
      { inst = 0, x = 514, y = -8346.5, map = 1453, name = "Stormwind Deeprun Tram station", wait = 0 },
      { inst = 0, x = -1330.5, y = -4840.3, map = 1455, name = "Ironforge Deeprun Tram station", wait = 0 },
    },
    legs = {
      { from = 1, to = 2, seconds = 59, yards = 0,
        points = { {514,-8346.5}, {-1330.5,-4840.3} } },
      { from = 2, to = 1, seconds = 59, yards = 0,
        points = { {-1330.5,-4840.3}, {514,-8346.5} } },
    },
  },
  [176231] = {
    name = "Menethil Harbor - Theramore", kind = "boat", fac = 1, period = 329,
    source = "taxipath:292 + cmangos transports 176231 (Menethil Harbor and Theramore Isle, period 329313 ms)",
    path = 292, speed = 23.8,
    stops = {
      { inst = 0, x = -585.8, y = -3905.2, map = 1437, name = "Menethil Harbor dock", wait = 60 },
      { inst = 1, x = -4740.6, y = -4016.4, map = 1445, name = "Theramore dock", wait = 60 },
    },
    legs = {
      { from = 1, to = 2, seconds = 103, yards = 2440.9, split = 7,
        points = { {-585.8,-3905.2}, {-528.8,-3830.8}, {-421.6,-3789.7}, {-232.1,-3809.4}, {43.7,-3998.8}, {376.5,-4025.7}, {516.2,-4008}, {-5732,-4301.1}, {-5627.4,-4298.5}, {-5067.3,-4284.9}, {-4823.3,-4263.5}, {-4718.7,-4201.2}, {-4692.4,-4100.9}, {-4740.6,-4016.4} } },
      { from = 2, to = 1, seconds = 107, yards = 2536.2, split = 9,
        points = { {-4740.6,-4016.4}, {-4813.7,-3952.5}, {-4889.9,-3927.4}, {-5033,-3902.8}, {-5148.3,-3816.9}, {-5204.6,-3668.6}, {-5208.8,-3476.4}, {-5261.7,-3214}, {-5280.2,-3157.3}, {309,-3609.4}, {178.1,-3787.5}, {15.7,-4037.3}, {-165.9,-4151.5}, {-372.3,-4199.9}, {-531.3,-4150.9}, {-599.1,-4088.9}, {-611.3,-3996.3}, {-585.8,-3905.2} } },
    },
  },
  [176244] = {
    name = "Rut'theran Village - Auberdine", kind = "boat", fac = 1, period = 316,
    source = "taxipath:293 + cmangos transports 176244 (Teldrassil and Auberdine, period 316251 ms)",
    path = 293, speed = 23,
    stops = {
      { inst = 1, x = 1023.7, y = 8532, map = 1438, name = "Rut'theran Village dock", wait = 60 },
      { inst = 1, x = 759.8, y = 6594.4, map = 1439, name = "Auberdine dock", wait = 60 },
    },
    legs = {
      { from = 1, to = 2, seconds = 96, yards = 2219.3,
        points = { {1023.7,8532}, {932.4,8504.5}, {851.5,8448.1}, {803.3,8348.1}, {764.7,8138}, {752.6,7917.8}, {747.1,7612.2}, {650.4,7304.4}, {578,6968.4}, {564.1,6765.6}, {588.8,6655.1}, {672.3,6592.9}, {759.8,6594.4} } },
      { from = 2, to = 1, seconds = 100, yards = 2300.6,
        points = { {759.8,6594.4}, {840.6,6638.7}, {913.2,6716.2}, {991.5,6833.6}, {1077.2,6983.4}, {1200.5,7226.1}, {1296.2,7466.8}, {1346.3,7665.7}, {1347.4,7685.3}, {1340.5,7912.6}, {1324.4,8293.7}, {1251.4,8452}, {1133.8,8526.4}, {1023.7,8532} } },
    },
  },
  [176310] = {
    name = "Menethil Harbor - Auberdine", kind = "boat", fac = 1, period = 296,
    source = "taxipath:295 + cmangos transports 176310 (Menethil Harbor and Auberdine, period 295579 ms)",
    path = 295, speed = 22.3,
    stops = {
      { inst = 0, x = -575.1, y = -3709.5, map = 1437, name = "Menethil Harbor dock", wait = 60 },
      { inst = 1, x = 823.1, y = 6406.2, map = 1439, name = "Auberdine dock", wait = 60 },
    },
    legs = {
      { from = 1, to = 2, seconds = 96, yards = 2154.5, split = 8,
        points = { {-575.1,-3709.5}, {-494.8,-3739.9}, {-388.3,-3725.3}, {-291.6,-3628.3}, {-273.8,-3474.4}, {-369,-3194}, {-392.6,-2979}, {-390.5,-2866.8}, {1312.3,5808.3}, {1241,5807.6}, {1115.7,5837}, {961.1,5904.4}, {840.9,5981.7}, {746.5,6077}, {702.8,6189.7}, {698.1,6299.1}, {761.4,6376.5}, {823.1,6406.2} } },
      { from = 2, to = 1, seconds = 79, yards = 1769.5, split = 8,
        points = { {823.1,6406.2}, {893.4,6417.1}, {986.7,6402.8}, {1072,6339}, {1135.7,6240}, {1173.1,6113.5}, {1178.8,6010}, {1178.5,5868.7}, {-92.6,-2963.1}, {-222.4,-3037.9}, {-481.6,-3286.6}, {-588.5,-3421.7}, {-628.9,-3523.7}, {-643.6,-3600.9}, {-625.2,-3663.4}, {-575.1,-3709.5} } },
    },
  },
  [176495] = {
    name = "Grom'gol Base Camp - The Undercity", kind = "zeppelin", fac = 2, period = 333,
    source = "taxipath:301 + cmangos transports 176495 (Grom'Gol Base Camp and Undercity, period 333044 ms)",
    path = 301, speed = 23.8,
    notes = {
      "implied speed 89.6 yd/s out of range; using fallback", "speed 23.8 yd/s not implied by a cmangos period",
      "period 333 s is the cmangos figure; the loop computed from the spline at 23.8 yd/s would be 923 s",
    },
    stops = {
      { inst = 0, x = 211.8, y = -12406.9, map = 1434, name = "Grom'gol Base Camp zeppelin tower", wait = 60 },
      { inst = 0, x = 235.3, y = 2062.6, map = 1420, name = "The Undercity zeppelin tower", wait = 60 },
    },
    legs = {
      { from = 1, to = 2, seconds = 114, yards = 2700.9, split = 8,
        points = { {211.8,-12406.9}, {34.2,-12366.5}, {-85.9,-12302.5}, {-257.3,-12184.9}, {-390.7,-12007.9}, {-408.4,-11704.9}, {-401,-11440}, {-402.1,-11372.7}, {-1001.8,2299.4}, {-944.4,2301.1}, {-821.1,2302.7}, {-510.7,2311.2}, {-207.2,2298.3}, {-39.3,2258.5}, {102.5,2199.2}, {200.9,2130.2}, {235.3,2062.6} } },
      { from = 2, to = 1, seconds = 689, yards = 16388.7,
        points = { {235.3,2062.6}, {229.4,1998.7}, {158.9,1954.8}, {87.2,1937.5}, {-28.7,1918.9}, {-217.3,1914.5}, {-478.7,1821}, {-536.6,1797.8}, {1460.6,-12327}, {1353.5,-12332.8}, {1121.4,-12312}, {819.7,-12318.4}, {424.2,-12381.3}, {211.8,-12406.9} } },
    },
  },
  [177233] = {
    name = "Feathermoon Stronghold - Forgotten Coast", kind = "boat", fac = 0, period = 317,
    source = "taxipath:303 + cmangos transports 177233 (Forgotton Coast and Feathermoon Stronghold, period 317038 ms)",
    path = 303, speed = 24.8,
    notes = { "stop name 'Forgotten Coast' taken from cmangos transports.name" },
    stops = {
      { inst = 1, x = 3286.6, y = -4197.3, map = 1444, name = "Feathermoon Stronghold dock", wait = 30 },
      { inst = 1, x = 2444.4, y = -4347.8, map = 1444, name = "Forgotten Coast dock", wait = 60 },
    },
    legs = {
      { from = 1, to = 2, seconds = 36, yards = 899,
        points = { {3286.6,-4197.3}, {3066.7,-4196.5}, {2900,-4200}, {2588.1,-4237.6}, {2483.7,-4267.3}, {2444.4,-4347.8} } },
      { from = 2, to = 1, seconds = 129, yards = 3188.1,
        points = { {2444.4,-4347.8}, {2476.1,-4448.2}, {2579.7,-4623.8}, {2778.3,-4905.6}, {2970.5,-5053.6}, {3186,-5121.1}, {3471.5,-5130.5}, {3706,-5089.3}, {3853.4,-5009.8}, {3939.9,-4880.2}, {3962.1,-4693.1}, {3904,-4417.4}, {3783.3,-4196.2}, {3466.7,-4195.8}, {3286.6,-4197.3} } },
    },
  },
  [910001] = {
    name = "Stormwind Harbor - Auberdine", kind = "boat", fac = 1, period = 239,
    source = "taxipath:11616",
    path = 11616, speed = 23.8,
    notes = {
      "both directions are TaxiPath 11616 between the dwells; the continent jump is left out of the yards",
      "Stormwind Harbor is the measured hull on either side of the jump, not a dock-to-dock foot line",
      "no source period: the period is computed from the spline at the fallback boat speed plus dock dwell",
      "speed 23.8 yd/s not implied by a cmangos period",
    },
    stops = {
      { inst = 0, x = 1344.4, y = -8654.5, map = 1453, name = "Stormwind Harbor dock", wait = 60 },
      { inst = 1, x = 942.2, y = 6548.3, map = 1439, name = "Auberdine dock", wait = 60 },
    },
    legs = {
      { from = 1, to = 2, seconds = 53, yards = 1264.8, split = 6,
        points = { {1344.4,-8654.5}, {1372.8,-8611.7}, {1423.5,-8579.1}, {1494,-8544.8}, {1605.1,-8496.3}, {1724.4,-8444.3}, {1488.4,7057.8}, {1253.5,6992.8}, {1082.9,6871.3}, {996.1,6768.1}, {942.6,6672.1}, {932.3,6604}, {942.2,6548.3} } },
      { from = 2, to = 1, seconds = 66, yards = 1571.9, split = 7,
        points = { {942.2,6548.3}, {971.9,6496.8}, {1022.5,6447.8}, {1116.5,6405}, {1271.8,6397.1}, {1573.3,6445.6}, {1813.8,6484.8}, {1780,-8950.9}, {1564.3,-8948.2}, {1423.4,-8883}, {1343,-8793.6}, {1327.5,-8711.2}, {1344.4,-8654.5} } },
    },
  },
  [910002] = {
    name = "Southshore - Auberdine", kind = "boat", fac = 1, period = 296,
    source = "Wowhead news 382891 (2026-09-15), Three New Ship Routes Debuting in Forever; no TaxiPath spline in the 1.60.1.69913 export",
    unverified = true,
    notes = {
      "missing leg of the Menethil - Southshore - Auberdine ship; the other two legs are TaxiPath 253 and 295",
      "period 296 s is computed (stand-in yards / analogous boat speed + dock dwell); no source period exists",
      "yards are the mean of the nearest measured crossing in the TaxiPath export, not a traced hull path",
    },
    stops = {
      { inst = 0, x = -545.7, y = -988, map = 1424, name = "Southshore dock", wait = 60 },
      { inst = 1, x = 823.1, y = 6406.2, map = 1439, name = "Auberdine dock", wait = 60 },
    },
    legs = {
      { from = 1, to = 2, seconds = 88, yards = 1962, split = 1,
        points = { {-545.7,-988}, {823.1,6406.2} } },
      { from = 2, to = 1, seconds = 88, yards = 1962, split = 1,
        points = { {823.1,6406.2}, {-545.7,-988} } },
    },
  },
  [910003] = {
    name = "Tanaris - Powderfuse Port", kind = "boat", fac = 0, period = 252,
    source = "taxipath:11391",
    path = 11391, speed = 23.8,
    notes = {
      "both directions are TaxiPath 11391 between the dwells; the continent jump is left out of the yards",
      "Tanaris is the measured hull on either side of the jump, not a dock-to-dock foot line",
      "no source period: the period is computed from the spline at the fallback boat speed plus dock dwell",
      "speed 23.8 yd/s not implied by a cmangos period",
    },
    stops = {
      { inst = 1, x = -4950.8, y = -6932.6, map = 1446, name = "Tanaris dock", wait = 60 },
      { inst = 0, x = -5800.8, y = -8232.3, map = 2548, name = "Powderfuse Port dock", wait = 60 },
    },
    legs = {
      { from = 1, to = 2, seconds = 66, yards = 1560.4, split = 11,
        points = { {-4950.8,-6932.6}, {-4952.8,-6991.3}, {-4972,-7046.1}, {-5055.7,-7127.1}, {-5164.7,-7184.6}, {-5276.3,-7244.4}, {-5355,-7298.3}, {-5420,-7330.2}, {-5490.1,-7340}, {-5640.2,-7341.4}, {-5746.1,-7340.6}, {-6340.4,-8230.1}, {-6275.7,-8222.4}, {-6195.1,-8230.6}, {-6110.4,-8226.3}, {-6006.1,-8181.3}, {-5918.3,-8158.8}, {-5842.7,-8176.4}, {-5800.8,-8232.3} } },
      { from = 2, to = 1, seconds = 67, yards = 1588.1, split = 9,
        points = { {-5800.8,-8232.3}, {-5781.1,-8280.1}, {-5783.3,-8343.4}, {-5808.6,-8418.9}, {-5833.6,-8477.8}, {-5877,-8570.7}, {-5940.5,-8689.6}, {-6038.9,-8805.9}, {-6155.3,-8885.7}, {-5617.6,-6606.8}, {-5506.2,-6632.2}, {-5183.2,-6695.5}, {-5030.8,-6775}, {-4965.9,-6849.3}, {-4950.8,-6932.6} } },
    },
  },
  [910005] = {
    name = "Dalaran - Zephras Isle", kind = "zeppelin", fac = 1, period = 371,
    source = "taxipath:11398",
    path = 11398, speed = 23.8,
    unverified = true,
    notes = {
      "both directions are TaxiPath 11398 between the dwells; the continent jump is left out of the yards",
      "Dalaran is the measured hull on either side of the jump, not a dock-to-dock foot line",
      "no source period: the period is computed from the spline at the fallback boat speed plus dock dwell",
      "the ride time is estimated from the spline at the fallback speed; nobody has timed this airship in the game",
      "speed 23.8 yd/s not implied by a cmangos period",
    },
    stops = {
      { inst = 0, x = 424.2, y = 544.8, deckZ = 107, map = 1421, name = "Dalaran skyship balcony", wait = 60 },
      { inst = 2991, x = 569.1, y = 1848.3, deckZ = 642.7, map = 2521, name = "Zephras Isle zeppelin tower", wait = 60 },
    },
    legs = {
      { from = 1, to = 2, seconds = 113, yards = 2690.3, split = 7,
        points = { {424.2,544.8}, {558.7,487.6}, {639.5,403.4}, {674.9,222.5}, {778.6,-10.6}, {960.5,-220.2}, {1153.2,-472}, {481.8,1202.4}, {544.5,1285.7}, {626.1,1413.4}, {624.2,1525.1}, {480.4,1741.9}, {327.3,1802.4}, {255,1881.7}, {254.4,1982.5}, {315.1,2028.5}, {370.3,1999.8}, {428.8,1925.8}, {569.1,1848.3} } },
      { from = 2, to = 1, seconds = 138, yards = 3282.2, split = 9,
        points = { {569.1,1848.3}, {618.3,1815.5}, {668,1822.1}, {773.7,1871.7}, {847.8,1827.3}, {849,1735.6}, {788.6,1633.3}, {644.7,1459.8}, {477.1,1256.8}, {-363.6,-1158.6}, {-354.3,-969.2}, {-351.7,-808.6}, {-350.7,-682.2}, {-364.2,-413.5}, {-376.1,-259.8}, {-385.3,-118.7}, {-383.7,27.2}, {-348.2,128.4}, {-219.1,179.7}, {-116.6,253.1}, {63.7,466.3}, {224.6,616.3}, {424.2,544.8} } },
    },
  },
  [910006] = {
    name = "Mulgore - Zephras Isle", kind = "zeppelin", fac = 2, period = 341,
    source = "taxipath:11457",
    path = 11457, speed = 23.8,
    unverified = true,
    notes = {
      "both directions are TaxiPath 11457 between the dwells; the continent jump is left out of the yards",
      "Mulgore is the measured hull on either side of the jump, not a dock-to-dock foot line",
      "no source period: the period is computed from the spline at the fallback boat speed plus dock dwell",
      "the ride time is estimated from the spline at the fallback speed; nobody has timed this airship in the game",
      "speed 23.8 yd/s not implied by a cmangos period",
    },
    stops = {
      { inst = 1, x = 366.5, y = -802, deckZ = 188, map = 1412, name = "Skywatcher Plateau skyship dock", wait = 60 },
      { inst = 2991, x = 1019.1, y = 1952.5, deckZ = 659.9, map = 2521, name = "Zephras Isle zeppelin tower", wait = 30 },
    },
    legs = {
      { from = 1, to = 2, seconds = 218, yards = 5174.5, split = 4,
        points = { {366.5,-802}, {518.3,-1034.2}, {323.4,-1292.8}, {-59.9,-1773.3}, {-69.9,-1786.2}, {535.9,1122.5}, {549,1148}, {554.6,1179}, {593.2,1332.3}, {716.8,1582.3}, {822.9,1757.3}, {946,1924}, {1019.1,1952.5} } },
      { from = 2, to = 1, seconds = 281, yards = 6674.7, split = 10,
        points = { {1019.1,1952.5}, {1132.2,1982.3}, {1188.7,2086.4}, {1142.4,2185}, {985.7,2226.2}, {851.6,2125.8}, {780.9,1927.8}, {717.9,1779.6}, {475.5,1321.3}, {391.9,1143}, {-147.5,1117}, {-803.6,-1724.1}, {-828,-1593.3}, {-855.8,-1113.8}, {-527.9,-778.3}, {97.9,-704.7}, {366.5,-802} } },
    },
  },
}
