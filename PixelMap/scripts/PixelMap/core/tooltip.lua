-- Hover tooltips on the Popup layer, not in the canvas, so a hover costs no redraw.

local ui = require('openmw.ui')
local util = require('openmw.util')

local I = require('openmw.interfaces')

local config = require('scripts.PixelMap.core.config')

local element = nil
-- What is hovered and last cursor position.
local hoveredText = nil
local shownText = nil
local cursorAt = nil

local function destroy()
    if element then
        element:destroy()
        element = nil
    end
    shownText = nil
end

local function cornerFor(width, height)
    local screen = ui.screenSize()
    return util.vector2(
        math.max(config.TOOLTIP_MARGIN,
            math.min(cursorAt.x + config.TOOLTIP_OFFSET_X,
                     screen.x - width - config.TOOLTIP_MARGIN)),
        math.max(config.TOOLTIP_MARGIN,
            math.min(cursorAt.y + config.TOOLTIP_OFFSET_Y,
                     screen.y - height - config.TOOLTIP_MARGIN)))
end

local function render()
    if not hoveredText or not cursorAt then
        destroy()
        return
    end

    -- Width guessed from string (widget sizes not readable); good enough for screen edge constraint.
    local width = #hoveredText * 9 + 24
    local height = 34
    local corner = cornerFor(width, height)

    if element and shownText == hoveredText then
        -- Same label, cursor moved: reposition instead of rebuild (mouseMove fires many times/sec).
        element.layout.props.position = corner
        element:update()
        return
    end

    destroy()
    shownText = hoveredText
    element = ui.create {
        layer = 'Popup',
        type = ui.TYPE.Widget,
        props = {
            position = corner,
            size = util.vector2(width, height),
        },
        content = ui.content {
            {
                template = I.MWUI.templates.boxSolid,
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

return {
    hover = hover,
    unhover = unhover,
    cursor = cursor,
    hide = hide,
}
