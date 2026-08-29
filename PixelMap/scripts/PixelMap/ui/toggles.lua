-- The row of layer checkboxes above the map.
--
-- Owns its own state -- the slot it was built into, the boxes by layer key,
-- and the width it was last filled at -- because the window has no reason to
-- hold any of it. What the window needs is the row count, which is what
-- decides how much height is left for the map.
--
-- Toggles wrap onto as many rows as the width needs rather than scrolling.
-- Nothing is ever out of reach that way, and the row count is knowable before
-- anything is built, which is what lets the canvas be sized for it.

local ui = require('openmw.ui')
local util = require('openmw.util')

local I = require('openmw.interfaces')

local config = require('scripts.PixelMap.core.config')
local layers = require('scripts.PixelMap.core.layers')
local widgets = require('scripts.PixelMap.ui.widgets')

local M = {}

-- The layout table the row lives in, held by reference so a resize can refill
-- it rather than rebuild the window around it.
local slot = nil
local slotWidth = nil
local boxes = {}

-- Rough width of one toggle, for deciding where a row breaks. The engine
-- reports no measured size back to Lua, so the extent has to be estimated;
-- over-estimating only wraps a toggle a little early.
local function toggleWidth(layer)
    return config.TOGGLE_BOX + 5 + #layer.name * 8 + config.TOGGLE_GAP
end

-- Walk the toggles, calling `onRow` at every break. Shared so the row count
-- the canvas is sized from and the rows that are built cannot disagree.
local function wrap(width, onLayer, onRow)
    local used = 0
    for _, layer in ipairs(layers.list()) do
        local span = toggleWidth(layer)
        if used > 0 and used + span > width then
            onRow()
            used = 0
        end
        used = used + span
        if onLayer then
            onLayer(layer)
        end
    end
    return used
end

--- How many rows the toggles wrap onto at `width`. Always at least one: the
-- row is there even with nothing in it, saying so.
function M.rowCount(width)
    local rows = 1
    local used = wrap(width, nil, function() rows = rows + 1 end)
    return used > 0 and rows or math.max(1, rows - 1)
end

local function content(width, onToggle, emptyText)
    boxes = {}
    local rows = {}
    local row = {}

    local function flush()
        rows[#rows + 1] = {
            type = ui.TYPE.Flex,
            props = { horizontal = true, arrange = ui.ALIGNMENT.Center },
            content = ui.content(row),
        }
        row = {}
    end

    wrap(width, function(layer)
        local key = layer.key
        local box = widgets.checkbox {
            checked = layer.enabled,
            label = layer.name,
            size = config.TOGGLE_BOX,
            onClick = function() onToggle(key) end,
        }
        boxes[key] = box
        row[#row + 1] = box
        row[#row + 1] = { props = { size = util.vector2(config.TOGGLE_GAP, 0) } }
    end, flush)

    if #row > 0 then
        flush()
    end
    if #rows == 0 then
        return { {
            template = I.MWUI.templates.textNormal,
            props = { text = emptyText },
        } }
    end
    return rows
end

--- Build the row. `onToggle(key)` is called when a box is clicked;
-- `emptyText` is what stands in when no layer is registered.
function M.build(width, onToggle, emptyText)
    slotWidth = width
    slot = {
        type = ui.TYPE.Flex,
        props = { horizontal = false, arrange = ui.ALIGNMENT.Start },
        content = ui.content(content(width, onToggle, emptyText)),
    }
    return slot
end

--- Refill the slot at a new width. Called on resize, and when a layer
-- registers or unregisters and the contents are no longer what was built.
--
-- `force` is for the latter: a resize fires every frame the cursor moves and
-- the width usually has not changed, so by default an unchanged width does
-- nothing.
function M.rebuild(width, onToggle, emptyText, force)
    if not slot or (not force and width == slotWidth) then
        return
    end
    slotWidth = width
    slot.content = ui.content(content(width, onToggle, emptyText))
end

--- Retick every box from the registry. A no-op per box whose state has not
-- changed, which on a pan is all of them.
function M.sync()
    for key, box in pairs(boxes) do
        local layer = layers.get(key)
        if layer then
            widgets.setChecked(box, layer.enabled)
        end
    end
end

--- Drop everything, for a window teardown.
function M.reset()
    slot = nil
    slotWidth = nil
    boxes = {}
end

return M
