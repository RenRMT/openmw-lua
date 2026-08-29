-- Layer registry: ordered list, enable/disable, alpha control.

local registry = {}
local ordered = {}

-- Bumped whenever the set of layers or their draw order changes. The window
-- compares it to decide whether the canvas has to be reassembled, which it
-- does on every redraw -- so this is a number to compare rather than a list
-- to walk and a string to build.
local revision = 0

local function sortLayers()
    table.sort(ordered, function(a, b)
        if a.order == b.order then
            return a.key < b.key
        end
        return a.order < b.order
    end)
end

local function register(layer)
    if type(layer) ~= 'table' or type(layer.key) ~= 'string' then
        error('PixelMap.registerLayer requires a table with a string key')
    end
    if type(layer.draw) ~= 'function' then
        error('PixelMap layer "' .. layer.key .. '" has no draw function')
    end

    local entry = {
        key = layer.key,
        name = layer.name or layer.key,
        order = tonumber(layer.order) or 100,
        draw = layer.draw,
        enabled = layer.enabled ~= false,
        -- Inherited by layer's wrapper widget and contents.
        alpha = tonumber(layer.alpha),
        -- Interactive layers above the panning sheet; get their own hover/click events.
        interactive = layer.interactive == true,
    }

    -- Re-registering preserves enabled state; alpha default only on first registration.
    local existing = registry[entry.key]
    if existing then
        entry.enabled = existing.enabled
        if existing.alphaOverridden then
            entry.alpha = existing.alpha
            entry.alphaOverridden = true
        end
        for i, l in ipairs(ordered) do
            if l.key == entry.key then
                table.remove(ordered, i)
                break
            end
        end
    end

    registry[entry.key] = entry
    ordered[#ordered + 1] = entry
    sortLayers()
    revision = revision + 1
    return entry
end

local function unregister(key)
    if not registry[key] then
        return false
    end
    registry[key] = nil
    for i, layer in ipairs(ordered) do
        if layer.key == key then
            table.remove(ordered, i)
            break
        end
    end
    revision = revision + 1
    return true
end

local function setEnabled(key, enabled)
    local layer = registry[key]
    if layer then
        layer.enabled = enabled and true or false
    end
end

local function setAlpha(key, alpha)
    local layer = registry[key]
    if layer then
        layer.alpha = tonumber(alpha)
        layer.alphaOverridden = true
    end
end

local function toggle(key)
    local layer = registry[key]
    if layer then
        layer.enabled = not layer.enabled
    end
end

return {
    register = register,
    unregister = unregister,
    setEnabled = setEnabled,
    setAlpha = setAlpha,
    toggle = toggle,
    get = function(key) return registry[key] end,
    -- Changes when a layer is added, replaced or removed -- which covers a
    -- re-registration that flips `interactive`, since that goes through
    -- register too.
    revision = function() return revision end,
    -- Live: window reads this every rebuild frame, so layers registered mid-session appear immediately.
    list = function() return ordered end,
}
