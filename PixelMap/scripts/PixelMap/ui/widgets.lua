-- Native-looking widgets assembled from the engine's own art. MWUI ships text,
-- boxes and lines but no button, no checkbox and no scrollbar, so these rebuild
-- the MyGUI skins out of the textures those skins are themselves made of.
--
-- Textures are Morrowind.bsa's, present in any install: menu_button_frame_*
-- (MW_Button), menu_thin_border_* (the same pieces MWUI's own box uses) and
-- omw_menu_scroll_* (shipped by OpenMW).

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
function M.named(content, name)
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

M.colors = colors

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
-- Title bar
--------------------------------------------------------------------------

--- A caption in the engine's own textured head block, draggable to move the
-- window. The blocks grow to fill whatever the title does not, so the text sits
-- on the dark centre where it stays readable.
-- opts: { height, textSize, name, onStart(), onMove(delta), onDone() }
function M.titleBar(caption, opts)
    opts = opts or {}
    local height = opts.height or 20

    local function block()
        return {
            type = ui.TYPE.Image,
            external = { grow = 1 },
            props = {
                resource = ui.texture { path = 'textures/menu_head_block_middle.dds' },
                tileH = true,
                tileV = true,
                size = v2(0, height),
            },
        }
    end

    local node = {
        name = opts.name,
        type = ui.TYPE.Flex,
        props = { horizontal = true, relativeSize = v2(1, 0), size = v2(0, height),
                  autoSize = false, arrange = ui.ALIGNMENT.Center },
        content = ui.content {
            block(),
            { props = { size = v2(12, 0) } },
            {
                template = I.MWUI.templates.textHeader,
                props = { text = caption, textSize = opts.textSize or 16 },
            },
            { props = { size = v2(12, 0) } },
            block(),
        },
    }

    if opts.onMove then
        M.draggable(node, { onStart = opts.onStart, onMove = opts.onMove, onEnd = opts.onDone })
    end
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

M.borderPieces = borderPieces

--- Wrap children in a thin border, ready for any fixed-size widget's content.
-- The border goes on last so it draws over the children rather than under them.
function M.framed(children, thickness)
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

M.buttonFrame = buttonFrame

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
            content = M.framed(mark and { mark } or {}),
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
function M.setChecked(node, checked)
    local spec = node and node.userData and node.userData.checkbox
    if not spec then
        return
    end
    local box = M.named(node.content, 'box')
    if not box then
        return
    end
    local mark = checkMark({ checked = checked, image = spec.image, mark = spec.mark }, spec.size)
    box.content = M.framed(mark and { mark } or {})
end

--------------------------------------------------------------------------
-- Scrollbar
--------------------------------------------------------------------------

local SCROLL = {
    up = 'textures/omw_menu_scroll_up.dds',
    down = 'textures/omw_menu_scroll_down.dds',
    left = 'textures/omw_menu_scroll_left.dds',
    right = 'textures/omw_menu_scroll_right.dds',
    thumbV = 'textures/omw_menu_scroll_center_v.dds',
    thumbH = 'textures/omw_menu_scroll_center_h.dds',
}

M.SCROLL_GAP = 3

--- A scrollbar: two boxed arrows with a bordered groove between them, mirroring
-- MW_VScroll. The thumb owns its own drag; `onDrag` receives the distance it has
-- been pulled along the bar, which the caller scales into content pixels with
-- scroll.dragScale.
--
-- opts: { thickness, length, arrow, thumb = scroll.thumb result, horizontal,
--         name, onStepBack, onStepOn, onDragStart(), onDrag(distance), onDragEnd() }
function M.scrollbar(opts)
    local horizontal = opts.horizontal
    local thickness, length = opts.thickness, opts.length
    local arrow = opts.arrow
    local boxLength = arrow - M.SCROLL_GAP
    local glyph = thickness - 6
    local inset = math.floor((thickness - glyph) / 2)
    local along = math.floor((boxLength - glyph) / 2)

    local function across(a, b)
        return horizontal and v2(a, b) or v2(b, a)
    end

    local function arrowBox(at, texture, onClick)
        local content = borderPieces()
        content[#content + 1] = {
            type = ui.TYPE.Image,
            props = {
                resource = ui.texture { path = texture },
                size = v2(glyph, glyph),
                position = across(along, inset),
            },
            events = onClick and { mouseClick = async:callback(onClick) } or nil,
        }
        return {
            type = ui.TYPE.Widget,
            props = { position = across(at, 0), size = across(boxLength, thickness) },
            content = ui.content(content),
        }
    end

    -- The groove spans the thumb's travel; the thumb is a sibling drawn over it.
    local groove = {
        type = ui.TYPE.Widget,
        props = { position = across(arrow, 0), size = across(length - 2 * arrow, thickness) },
        content = ui.content(borderPieces()),
    }

    local thumb = {
        name = 'thumb',
        type = ui.TYPE.Image,
        props = {
            resource = ui.texture { path = horizontal and SCROLL.thumbH or SCROLL.thumbV },
            tileH = true,
            tileV = true,
            -- Flush against the groove's near border, one pixel clear of the far
            -- one, which is how the engine's own scrollbar sits.
            position = across(arrow + opts.thumb.offset, 2),
            size = across(opts.thumb.length, thickness - 5),
            pointer = horizontal and 'hresize' or 'vresize',
            -- A drag on the thumb is not a drag on whatever the bar sits over.
            propagateEvents = false,
        },
    }

    if opts.onDrag then
        M.draggable(thumb, {
            onStart = opts.onDragStart,
            onMove = function(delta)
                opts.onDrag(horizontal and delta.x or delta.y)
            end,
            onEnd = opts.onDragEnd,
        })
    end

    return {
        name = opts.name,
        type = ui.TYPE.Widget,
        props = { size = across(length, thickness), visible = opts.thumb.visible },
        content = ui.content {
            groove,
            arrowBox(0, horizontal and SCROLL.left or SCROLL.up, opts.onStepBack),
            arrowBox(length - boxLength, horizontal and SCROLL.right or SCROLL.down, opts.onStepOn),
            thumb,
        },
    }
end

--- Move an already-built scrollbar's thumb, so scrolling does not rebuild it.
function M.thumbAt(bar, thumb, arrow, thickness, horizontal)
    if not bar then
        return
    end
    bar.props.visible = thumb.visible
    local node = M.named(bar.content, 'thumb')
    if not node then
        return
    end
    local along = arrow + thumb.offset
    node.props.position = horizontal and v2(along, 2) or v2(2, along)
    node.props.size = horizontal and v2(thumb.length, thickness - 5)
        or v2(thickness - 5, thumb.length)
end

return M
