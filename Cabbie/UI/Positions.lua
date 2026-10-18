














local ADDON_NAME, FGPS = ...

local type, pairs, tostring, tonumber = type, pairs, tostring, tonumber
local floor, abs = math.floor, math.abs

local Positions = {
    registry = {},
    initialised = false,
    VERSION = 1,
    MIN_VISIBLE = 0.0,
}
FGPS.UI.Positions = Positions

Positions.DEFAULT_LAYOUT = "default"




local function account()
    local db = FGPS.DB
    return db and db.account or nil
end


local function store(layoutName, create)
    local acc = account()
    if not acc then return nil end
    if layoutName == nil then
        if type(acc.windows) ~= "table" then
            if not create then return nil end
            acc.windows = {}
        end
        return acc.windows
    end
    if type(acc.positions) ~= "table" then
        if not create then return nil end
        acc.positions = {}
    end
    local layout = acc.positions[layoutName]
    if type(layout) ~= "table" then
        if not create then return nil end
        layout = {}
        acc.positions[layoutName] = layout
    end
    return layout
end

function Positions.Get(key, layoutName)
    local s = store(layoutName, false)
    local record = s and s[key]
    if type(record) == "table" then return record end
    return nil
end

function Positions.Has(key, layoutName)
    return Positions.Get(key, layoutName) ~= nil
end




local function parentSize()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    if not w or w <= 0 then w = (GetScreenWidth and GetScreenWidth()) or 1024 end
    if not h or h <= 0 then h = (GetScreenHeight and GetScreenHeight()) or 768 end
    return w, h
end


local function scaleRatio(frame)
    local es = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    local ues = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    if not es or es <= 0 then es = 1 end
    if not ues or ues <= 0 then ues = 1 end
    return es / ues
end

local function isFinite(n)
    return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end



function Positions.ToRecord(frame)
    local cx, cy = frame:GetCenter()
    if not isFinite(cx) or not isFinite(cy) then return nil end
    local ratio = scaleRatio(frame)
    local uw, uh = parentSize()
    local ux, uy = cx * ratio, cy * ratio
    local record = {
        v = Positions.VERSION,
        fx = (ux - uw / 2) / uw,
        fy = (uy - uh / 2) / uh,
        scale = frame:GetScale() or 1,
    }
    local w, h = frame:GetSize()
    if isFinite(w) and isFinite(h) and w > 0 and h > 0 then
        record.w, record.h = floor(w + 0.5), floor(h + 0.5)
    end
    return record
end

local function validRecord(record)
    return type(record) == "table" and isFinite(record.fx) and isFinite(record.fy)
        and abs(record.fx) < 10 and abs(record.fy) < 10
end



function Positions.ClampCenter(dx, dy, frameW, frameH)
    local uw, uh = parentSize()
    local halfW, halfH = uw / 2, uh / 2
    local allowW = frameW * Positions.MIN_VISIBLE
    local allowH = frameH * Positions.MIN_VISIBLE
    local limitX = halfW - frameW / 2 + allowW
    local limitY = halfH - frameH / 2 + allowH
    if limitX < 0 then dx = 0 elseif dx > limitX then dx = limitX elseif dx < -limitX then dx = -limitX end
    if limitY < 0 then dy = 0 elseif dy > limitY then dy = limitY elseif dy < -limitY then dy = -limitY end
    return dx, dy
end


function Positions.AnchorCenter(frame, dx, dy)
    local ratio = scaleRatio(frame)
    local w, h = frame:GetSize()
    w = (isFinite(w) and w or 0) * ratio
    h = (isFinite(h) and h or 0) * ratio
    dx, dy = Positions.ClampCenter(dx, dy, w, h)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", dx / ratio, dy / ratio)
    return dx, dy
end



function Positions.Apply(frame, record, opts)
    if not validRecord(record) then return false end
    if record.scale and isFinite(record.scale) and record.scale > 0 and not (opts and opts.applyScale == false) then
        frame:SetScale(record.scale)
    end
    if opts and opts.restoreSize and isFinite(record.w) and isFinite(record.h) and record.w > 0 and record.h > 0 then
        local w, h = record.w, record.h
        local minSize = opts.minSize
        if minSize then
            if minSize[1] and w < minSize[1] then w = minSize[1] end
            if minSize[2] and h < minSize[2] then h = minSize[2] end
        end
        frame:SetSize(w, h)
    end
    local uw, uh = parentSize()
    Positions.AnchorCenter(frame, record.fx * uw, record.fy * uh)
    return true
end






function Positions.ApplyDefault(frame, default, opts)
    if type(default) == "function" then
        local ok, value = pcall(default, frame)
        if not ok then
            if FGPS.Log then FGPS.Log:Error("Default position callback failed: %s", tostring(value)) end
            value = nil
        end
        default = value
    end
    if type(default) == "table" and default.point then
        local rel = default.relativeTo
        if type(rel) == "string" then rel = _G[rel] end
        if type(rel) ~= "table" then rel = UIParent end
        frame:ClearAllPoints()
        frame:SetPoint(default.point, rel, default.relativePoint or default.point, default.x or 0, default.y or 0)
        return "anchor"
    end
    local fx, fy = 0, 0
    if type(default) == "table" then
        if isFinite(default.fx) then fx = default.fx end
        if isFinite(default.fy) then fy = default.fy end
        if isFinite(default.scale) and default.scale > 0 and not (opts and opts.applyScale == false) then
            frame:SetScale(default.scale)
        end
    end
    local uw, uh = parentSize()
    Positions.AnchorCenter(frame, fx * uw, fy * uh)
    return "default"
end





function Positions.Save(key, frame, layoutName)
    assert(type(key) == "string" and key ~= "", "Positions.Save: key must be a non-empty string")
    local record = Positions.ToRecord(frame)
    if not record then return nil end
    local s = store(layoutName, true)
    if s then s[key] = record end
    local entry = Positions.registry[key]
    if entry then entry.layoutName = layoutName end
    return record
end





function Positions.Restore(key, frame, default, layoutName, opts)
    assert(type(key) == "string" and key ~= "", "Positions.Restore: key must be a non-empty string")
    assert(type(frame) == "table", "Positions.Restore: frame is required")
    Positions.registry[key] = { frame = frame, default = default, layoutName = layoutName, opts = opts }
    local record = Positions.Get(key, layoutName)
    if record and Positions.Apply(frame, record, opts) then return "stored" end
    if record then

        local s = store(layoutName, false)
        if s then s[key] = nil end
        if FGPS.Log then FGPS.Log:Warn("Discarded invalid stored position for %s", tostring(key)) end
    end
    return Positions.ApplyDefault(frame, default, opts)
end


function Positions.Reapply(key)
    local entry = Positions.registry[key]
    if not entry then return nil end
    return Positions.Restore(key, entry.frame, entry.default, entry.layoutName, entry.opts)
end


function Positions.SetScale(key, scale)
    local entry = Positions.registry[key]
    if not entry or not isFinite(scale) or scale <= 0 then return end
    entry.frame:SetScale(scale)
    local record = Positions.Get(key, entry.layoutName)
    if record then
        record.scale = scale
        Positions.Apply(entry.frame, record, entry.opts)
    else
        Positions.ApplyDefault(entry.frame, entry.default, { applyScale = false })
    end
end


function Positions.Nudge(key, dx, dy)
    local entry = Positions.registry[key]
    if not entry then return nil end
    local frame = entry.frame
    local cx, cy = frame:GetCenter()
    if not isFinite(cx) or not isFinite(cy) then return nil end
    local ratio = scaleRatio(frame)
    local uw, uh = parentSize()
    local ux, uy = cx * ratio - uw / 2 + (dx or 0), cy * ratio - uh / 2 + (dy or 0)
    Positions.AnchorCenter(frame, ux, uy)
    return Positions.Save(key, frame, entry.layoutName)
end

function Positions.Unregister(key)
    Positions.registry[key] = nil
end

function Positions.IsRegistered(key)
    return Positions.registry[key] ~= nil
end



function Positions.Reset(key)
    assert(type(key) == "string" and key ~= "", "Positions.Reset: key must be a non-empty string")
    local db = FGPS.DB
    if db and db.account and db.ResetElementPosition then
        db:ResetElementPosition(key)
    else
        local acc = account()
        if acc then
            if type(acc.positions) == "table" then
                for _, layout in pairs(acc.positions) do
                    if type(layout) == "table" then layout[key] = nil end
                end
            end
            if type(acc.windows) == "table" then acc.windows[key] = nil end
        end
        if FGPS.Events then FGPS.Events:Fire("POSITIONS_RESET", key) end
    end
end


function Positions.ResetAll()
    local db = FGPS.DB
    if db and db.account and db.ResetPositions then
        db:ResetPositions()
    else
        local acc = account()
        if acc then
            if type(acc.positions) == "table" then wipe(acc.positions) end
            if type(acc.windows) == "table" then wipe(acc.windows) end
        end
        if FGPS.Events then FGPS.Events:Fire("POSITIONS_RESET", nil) end
    end
end




local function reapplyAll()
    for key, entry in pairs(Positions.registry) do
        local ok, err = pcall(Positions.Restore, key, entry.frame, entry.default, entry.layoutName, entry.opts)
        if not ok and FGPS.Log then FGPS.Log:Error("Re-applying position %s failed: %s", tostring(key), tostring(err)) end
    end
end
Positions.ReapplyAll = reapplyAll

local function onPositionsReset(_, key)
    if key == nil then
        reapplyAll()
    else
        local entry = Positions.registry[key]
        if entry then
            local ok, err = pcall(Positions.ApplyDefault, entry.frame, entry.default, entry.opts)
            if not ok and FGPS.Log then FGPS.Log:Error("Resetting position %s failed: %s", tostring(key), tostring(err)) end
        end
    end
end

local function onDisplayChanged()
    reapplyAll()
end

function Positions:Init()
    if Positions.initialised then return Positions end
    if FGPS.Events then
        FGPS.Events:Register("POSITIONS_RESET", onPositionsReset, Positions)
        FGPS.Events:RegisterWoW("DISPLAY_SIZE_CHANGED", onDisplayChanged, Positions)
        FGPS.Events:RegisterWoW("UI_SCALE_CHANGED", onDisplayChanged, Positions)
    end
    Positions.initialised = true
    return Positions
end
