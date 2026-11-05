local ADDON_NAME, FGPS = ...













FGPS.Data = FGPS.Data or {}

FGPS.Data.graphs = FGPS.Data.graphs or {}
local g = FGPS.Data.graphs[0]
if not g then return end
local function merge(t, p) for k, v in pairs(p) do t[k] = v end end
local function append(t, p) local o = #t for i = 1, #p do t[o + i] = p[i] end end

