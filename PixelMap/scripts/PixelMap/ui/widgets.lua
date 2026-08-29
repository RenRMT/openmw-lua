-- Native-looking widgets assembled from the engine's own art. MWUI ships text,
-- boxes and lines but no button and no checkbox, so these rebuild the MyGUI
-- skins out of the textures those skins are themselves made of.
--
-- Textures are Morrowind.bsa's, present in any install: menu_button_frame_*
-- (MW_Button) and menu_thin_border_* (the same pieces MWUI's own box uses).

local async = require('openmw.async')
local core = require('openmw.core')
local ui = require('openmw.ui')
local util = require('openmw.util')

local I = require('openmw.interfaces')

local v2 = util.vector2

local M = {}

local whiteTexture = ui.texture { path = 'white' }

--- Look up a named child. A ui.content map raises on an unknown name rather
-- than answering nil, so a miss has to be caught rather than tested for.
local function named(content, name)
    if not content then
        return nil
    end
    local ok, found = pcall(function() return content[name] end)
    return ok and found or nil
end

--------------------------------------------------------------------------
-- Font colours
--------------------------------------------------------------------------

-- The GMSTs the engine's own button skin reads, so a button tinted from these
-- matches whatever the player's UI colour settings say. They need a loaded
-- game, so resolve on first use rather than at load.
local cached
local function colors()
    if not cached then
        local function gmst(name, fallback)
            local ok, color = pcall(function()
                return util.color.commaString(core.getGMST('FontColor_color_' .. name))
            end)
            return (ok and color) or fallback
        end
        local white = util.color.rgb(1, 1, 1)
        cached = {
            normal = gmst('normal', white),
            normalOver = gmst('normal_over', white),
            active = gmst('active', util.color.rgb(0.45, 0.50, 0.90)),
            activeOver = gmst('active_over', util.color.rgb(0.55, 0.60, 1.00)),
            header = gmst('header', white),
            disabled = gmst('disabled', util.color.rgb(0.5, 0.5, 0.5)),
        }
    end
    return cached
end

--------------------------------------------------------------------------
-- Refresh hook
--------------------------------------------------------------------------

-- Hover recolouring mutates a layout in place, which shows only once the owning
-- Element is updated. The window injects that here so these factories never
-- need to know which Element they ended up in.
local refresh = function() end

function M.setRefresh(fn)
    refresh = fn or function() end
end

--------------------------------------------------------------------------
-- Dragging
--------------------------------------------------------------------------

--- Give a widget its own drag gesture.
--
-- The anchor is the cursor position recorded at press, so `onMove` receives the
-- total delta since the drag began rather than the step since the last event.
-- That makes the handler idempotent: the same movement arriving twice lands in
-- the same place, which matters because an ancestor can deliver it again.
--
-- handlers: { onStart(layout), onMove(delta, layout), onEnd(delta, layout) }
function M.draggable(node, handlers)
    node.userData = node.userData or {}
    node.userData.dragging = false
    node.userData.from = nil
    node.events = node.events or {}

    node.events.mousePress = async:callback(function(event, layout)
        layout.userData.dragging = true
        layout.userData.from = event.position
        if handlers.onStart then
            handlers.onStart(layout)
        end
    end)

    node.events.mouseMove = async:callback(function(event, layout)
        if not (layout.userData.dragging and layout.userData.from) then
            return
        end
        handlers.onMove(event.position - layout.userData.from, layout)
    end)

    node.events.mouseRelease = async:callback(function(event, layout)
        if not layout.userData.dragging then
            return
        end
        layout.userData.dragging = false
        if handlers.onEnd then
            handlers.onEnd(event.position - (layout.userData.from or event.position), layout)
        end
        layout.userData.from = nil
    end)

    return node
end

--------------------------------------------------------------------------
-- Borders
--------------------------------------------------------------------------

local BORDER = 2

local SIDES = {
    { key = 'top', at = v2(0, 0), span = v2(1, 0) },
    { key = 'bottom', at = v2(0, 1), span = v2(1, 0) },
    { key = 'left', at = v2(0, 0), span = v2(0, 1) },
    { key = 'right', at = v2(1, 0), span = v2(0, 1) },
}

local CORNERS = {
    { key = 'top_left', at = v2(0, 0) },
    { key = 'top_right', at = v2(1, 0) },
    { key = 'bottom_left', at = v2(0, 1) },
    { key = 'bottom_right', at = v2(1, 1) },
}

-- Eight pieces filling the parent, assembled the way MWUI's own box is: each
-- side tiles its own directional texture and the corners join them. Reusing one
-- side's texture for the opposite edge draws visibly wrong art.
local function borderPieces(thickness)
    thickness = thickness or 'thin'
    local side = 'textures/menu_' .. thickness .. '_border_%s.dds'
    local corner = 'textures/menu_' .. thickness .. '_border_%s_corner.dds'
    local pieces = {}

    for _, s in ipairs(SIDES) do
        local horizontal = s.span.x == 1
        pieces[#pieces + 1] = {
            type = ui.TYPE.Image,
            props = {
                resource = ui.texture { path = side:format(s.key) },
                tileH = horizontal,
                tileV = not horizontal,
                position = (s.span - s.at) * BORDER,
                relativePosition = s.at,
                size = (v2(1, 1) - s.span * 3) * BORDER,
                relativeSize = s.span,
            },
        }
    end

    for _, c in ipairs(CORNERS) do
        pieces[#pieces + 1] = {
            type = ui.TYPE.Image,
            props = {
                resource = ui.texture { path = corner:format(c.key) },
                position = -c.at * BORDER,
                relativePosition = c.at,
                size = v2(BORDER, BORDER),
            },
        }
    end

    return pieces
end

--- Wrap children in a thin border, ready for any fixed-size widget's content.
-- The border goes on last so it draws over the children rather than under them.
local function framed(children, thickness)
    local out = {}
    for _, child in ipairs(children or {}) do
        out[#out + 1] = child
    end
    for _, piece in ipairs(borderPieces(thickness)) do
        out[#out + 1] = piece
    end
    return ui.content(out)
end

--------------------------------------------------------------------------
-- Button
--------------------------------------------------------------------------

local BUTTON_BORDER = 4
local BUTTON_PAD = 10

local function buttonEdge(name, props, tileH, tileV)
    props.resource = ui.texture { path = 'textures/menu_button_frame_' .. name .. '.dds' }
    props.tileH = tileH or false
    props.tileV = tileV or false
    return { type = ui.TYPE.Image, props = props }
end

local B = BUTTON_BORDER

-- MW_Button's frame, as a template so it autosizes to whatever lands in the slot.
local buttonFrame = {
    type = ui.TYPE.Container,
    content = ui.content {
        buttonEdge('top', { position = v2(B, 0), relativePosition = v2(0, 0),
                            size = v2(0, B), relativeSize = v2(1, 0) }, true, false),
        buttonEdge('bottom', { position = v2(B, B), relativePosition = v2(0, 1),
                               size = v2(0, B), relativeSize = v2(1, 0) }, true, false),
        buttonEdge('left', { position = v2(0, B), relativePosition = v2(0, 0),
                             size = v2(B, 0), relativeSize = v2(0, 1) }, false, true),
        buttonEdge('right', { position = v2(B, B), relativePosition = v2(1, 0),
                              size = v2(B, 0), relativeSize = v2(0, 1) }, false, true),
        buttonEdge('top_left_corner', { position = v2(0, 0), relativePosition = v2(0, 0), size = v2(B, B) }),
        buttonEdge('top_right_corner', { position = v2(B, 0), relativePosition = v2(1, 0), size = v2(B, B) }),
        buttonEdge('bottom_left_corner', { position = v2(0, B), relativePosition = v2(0, 1), size = v2(B, B) }),
        buttonEdge('bottom_right_corner', { position = v2(B, B), relativePosition = v2(1, 1), size = v2(B, B) }),
        { external = { slot = true }, props = { position = v2(B, B), relativeSize = v2(1, 1) } },
    },
}

--- A button in the engine's own frame, sized to its label.
--
-- Hover brightens the text and `opts.active` shows the blue toggled colour,
-- both the way MW_Button does. `opts.width` fixes the inner width so a button
-- whose label changes does not resize and shove its neighbours along.
-- opts: { active = boolean, width = number, height = number }
function M.button(label, onClick, opts)
    opts = opts or {}
    local c = colors()
    local base = opts.active and c.active or c.normal
    local over = opts.active and c.activeOver or c.normalOver

    local text = {
        template = I.MWUI.templates.textNormal,
        props = { text = label, textColor = base },
        events = {
            focusGain = async:callback(function(_, layout)
                layout.props.textColor = over
                refresh()
            end),
            focusLoss = async:callback(function(_, layout)
                layout.props.textColor = base
                refresh()
            end),
        },
    }

    local inner
    if opts.width then
        text.props.relativePosition = v2(0.5, 0.5)
        text.props.anchor = v2(0.5, 0.5)
        inner = {
            type = ui.TYPE.Widget,
            props = { size = v2(opts.width, opts.height or 18) },
            content = ui.content { text },
        }
    else
        inner = {
            type = ui.TYPE.Flex,
            props = { horizontal = true, arrange = ui.ALIGNMENT.Center },
            content = ui.content {
                { props = { size = v2(BUTTON_PAD, 0) } },
                text,
                { props = { size = v2(BUTTON_PAD, 0) } },
            },
        }
    end

    return {
        template = buttonFrame,
        -- Without this a button sitting on a draggable band starts a window drag
        -- instead of clicking, and the click is swallowed.
        props = { propagateEvents = false },
        content = ui.content { inner },
        events = { mouseClick = onClick and async:callback(function() onClick() end) or nil },
    }
end

--------------------------------------------------------------------------
-- Checkbox
--------------------------------------------------------------------------

-- The centred indicator, or nothing when unchecked.
local function checkMark(opts, size)
    if not opts.checked then
        return nil
    end
    local props = { relativePosition = v2(0.5, 0.5), anchor = v2(0.5, 0.5) }
    if opts.image then
        props.resource = ui.texture { path = opts.image }
        props.size = v2(size - 4, size - 4)
    else
        props.resource = whiteTexture
        props.color = opts.mark or colors().normal
        props.size = v2(size - 9, size - 9)
    end
    return { type = ui.TYPE.Image, props = props }
end

--- A bordered square that shows a centred mark when checked.
-- opts: { checked, label, size, color, mark, image, gap, onClick }
function M.checkbox(opts)
    opts = opts or {}
    local size = opts.size or 16
    local c = colors()
    local mark = checkMark(opts, size)

    local row = {
        {
            name = 'box',
            type = ui.TYPE.Widget,
            props = { size = v2(size, size) },
            content = framed(mark and { mark } or {}),
        },
    }

    if opts.label then
        row[#row + 1] = { props = { size = v2(opts.gap or 5, 0) } }
        row[#row + 1] = {
            type = ui.TYPE.Text,
            template = I.MWUI.templates.textNormal,
            props = { text = opts.label, textColor = opts.color or c.normal },
        }
    end

    return {
        type = ui.TYPE.Flex,
        props = { horizontal = true, arrange = ui.ALIGNMENT.Center, propagateEvents = false },
        events = opts.onClick and { mouseClick = async:callback(function() opts.onClick() end) } or nil,
        content = ui.content(row),
        -- Kept so setChecked can rebuild the mark without the caller restating
        -- how the box was styled.
        userData = { checkbox = { size = size, image = opts.image, mark = opts.mark } },
    }
end

--- Tick or untick an existing checkbox in place.
--- Retick a checkbox in place.
--
-- Rebuilding the box means rebuilding its border -- eight images -- and the
-- window calls this for every toggle on every redraw, which a pan fires
-- several times a second. The state it is being set to is almost always the
-- state it is already in, so the early return is what keeps a drag from
-- churning through widgets nobody asked to change.
function M.setChecked(node, checked)
    local spec = node and node.userData and node.userData.checkbox
    if not spec then
        return
    end
    checked = checked and true or false
    if spec.checked == checked then
        return
    end
    spec.checked = checked
    local box = named(node.content, 'box')
    if not box then
        return
    end
    local mark = checkMark({ checked = checked, image = spec.image, mark = spec.mark }, spec.size)
    box.content = framed(mark and { mark } or {})
end

return M
