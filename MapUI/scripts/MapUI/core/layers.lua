-- Layer registry: ordered list, enable/disable, alpha control.

local registry = {}
local ordered = {}

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
        error('MapUI.registerLayer requires a table with a string key')
    end
    if type(layer.draw) ~= 'function' then
        error('MapUI layer "' .. layer.key .. '" has no draw function')
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
    -- Live: window reads this every rebuild frame, so layers registered mid-session appear immediately.
    list = function() return ordered end,
}
