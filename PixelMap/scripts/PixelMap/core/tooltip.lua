-- Hover tooltips on the Popup layer, not in the canvas, so a hover costs no redraw.
--
-- The box is its own top-level Element, so it does not die with whatever was
-- hovered: every teardown path has to call hide() or dismiss().

local core = require('openmw.core')
local ui = require('openmw.ui')
local util = require('openmw.util')

local I = require('openmw.interfaces')

local config = require('scripts.PixelMap.core.config')

local element = nil
-- What is hovered and last cursor position.
local hoveredText = nil
local shownText = nil
local cursorAt = nil
-- Real time until which a show is refused; see dismiss().
local blockUntil = 0

local function destroy()
    if element then
        element:destroy()
        element = nil
    end
    shownText = nil
end

-- Cursor positions are in the Windows layer's coordinate space, which the GUI
-- scale separates from the physical resolution ui.screenSize() reports.
local function logicalScreen()
    local index = ui.layers.indexOf('Windows')
    local size = index and ui.layers[index].size
    return size or ui.screenSize()
end

-- Rather than measure the box -- Lua is never told how big a widget came out --
-- flip which corner of it the cursor holds. Near the right edge the box hangs
-- to the left of the cursor, near the bottom it hangs above, so it stays on
-- screen at any size without anyone having to know what that size is.
local function placement()
    local screen = logicalScreen()
    local ax = (cursorAt.x > screen.x / 2) and 1 or 0
    local ay = (cursorAt.y > screen.y / 2) and 1 or 0
    local position = util.vector2(
        cursorAt.x + (ax == 0 and config.TOOLTIP_OFFSET_X or -config.TOOLTIP_MARGIN),
        cursorAt.y + (ay == 0 and config.TOOLTIP_OFFSET_Y or -config.TOOLTIP_MARGIN))
    return position, util.vector2(ax, ay)
end

local function render()
    if not hoveredText or not cursorAt then
        destroy()
        return
    end
    if core.getRealTime() < blockUntil then
        return
    end

    local position, anchor = placement()

    if element and shownText == hoveredText then
        -- Same label, cursor moved: reposition instead of rebuild (mouseMove fires many times/sec).
        element.layout.props.position = position
        element.layout.props.anchor = anchor
        element:update()
        return
    end

    destroy()
    shownText = hoveredText
    element = ui.create {
        layer = 'Popup',
        template = I.MWUI.templates.boxSolid,
        props = { position = position, anchor = anchor },
        content = ui.content {
            {
                template = I.MWUI.templates.padding,
                content = ui.content {
                    {
                        template = I.MWUI.templates.textNormal,
                        props = { text = hoveredText },
                    },
                },
            },
        },
    }
end

local function hover(text)
    hoveredText = text
    render()
end

-- Guard by label: adjacent widgets' enter/leave can arrive in any order.
local function unhover(text)
    if hoveredText == text then
        hoveredText = nil
        destroy()
    end
end

local function cursor(position)
    cursorAt = position
    if hoveredText then
        render()
    end
end

local function hide()
    hoveredText = nil
    destroy()
end

--- Hide for an action that rebuilds what was hovered.
--
-- Such a click destroys the hovered widget, so its focusLoss never arrives to
-- say the cursor left -- and a trailing mouseMove from the same click would
-- show the tooltip again, stranding it over whatever replaced the widget. So
-- showing is refused briefly as well. The window is far shorter than any
-- deliberate hover, so it never swallows a real one.
local function dismiss()
    hide()
    blockUntil = core.getRealTime() + config.TOOLTIP_DISMISS_SECONDS
end

return {
    hover = hover,
    unhover = unhover,
    cursor = cursor,
    hide = hide,
    dismiss = dismiss,
}
