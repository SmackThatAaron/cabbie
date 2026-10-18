

local ADDON_NAME, ns = ...
local core = Cabbie
if type(core) == "table" and type(core.RegisterData) == "function" then
    core.RegisterData(ADDON_NAME, "2026.10.18.3", ns.Data)
end
ns.Data = nil
