-- Everything Pixel Map exposes to other mods, in one place.
--
-- The table returned here *is* `I.PixelMap`. It is a facade and nothing
-- else: no state, no logic, no decisions -- every field forwards to the
-- module that owns the thing. That is the point of the file. The public
-- surface is the one part of a mod that cannot be changed freely once
-- somebody depends on it, so it is worth being able to read all of it at
-- once, and worth it being obvious when a commit widens it.
--
-- Player context only, which is where the map lives.
--
-- The comments below are the reference: what a field is for, and what it
-- takes. Anything needing more than that belongs next to the code that
-- implements it, not here.

local I = require('openmw.interfaces')

local draw = require('scripts.PixelMap.core.draw')
local layers = require('scripts.PixelMap.core.layers')
local view = require('scripts.PixelMap.core.view')
local window = require('scripts.PixelMap.window')

-- Bumped when anything below changes shape. Consumers gate on it, and it
-- rides along on PixelMapReady so a mod can check before it registers
-- rather than after a call has already failed.
local VERSION = 1

--- Open the map.
--
-- Public because a mod may well want to put the player in front of it --
-- a quest marker, a travel destination -- and the mode juggling is not
-- something a caller should have to know about.
local function open()
    window.show()
    -- Without a mode there is no cursor, and nothing on the map can be
    -- clicked. The empty window list keeps the engine's own windows off
    -- the screen while this one is up.
    I.UI.setMode('Interface', { windows = {} })
end

---
-- @module PixelMap
-- @context player
-- @usage local I = require('openmw.interfaces')
return {
    version = VERSION,

    --------------------------------------------------------------------
    -- Layers
    --------------------------------------------------------------------

    --- Add a layer to the map, or replace one registered under the same key.
    --
    -- Fields: key, name, order, enabled, alpha, interactive, draw(required).
    -- `draw(view)` returns a flat list of layouts and runs inside a pcall, so
    -- a layer that errors switches itself off rather than taking the window
    -- down. `interactive` draws it above the pan-catcher, which is what gives
    -- its widgets clicks and hover.
    registerLayer = layers.register,

    --- Take a layer off the map. Returns false if it was not there.
    unregisterLayer = layers.unregister,

    --- Turn a layer on/off (same toggle in map).
    setLayerEnabled = layers.setEnabled,

    --- Fade a layer: 0 invisible, 1 opaque. Applied to the layer as a
    -- whole, which its widgets inherit.
    setLayerAlpha = layers.setAlpha,

    --------------------------------------------------------------------
    -- Drawing one thing
    --------------------------------------------------------------------

    --- A solid rectangle in canvas pixels: x, y, w, h, color, alpha.
    quad = draw.quad,

    --- A quad covering one exterior cell.
    --
    -- opts: `gridX`, `gridY`, `color`, `alpha`, `tooltip`, `border`,
    -- `borderColor`.
    --
    -- `tooltip` is optional text shown while the cursor is anywhere over
    -- the cell; it needs `interactive = true` on the layer, and turns the
    -- quad into a widget, so leave it off the fills that do not need to
    -- answer. For a whole grid at once, prefer `cells` below.
    cell = draw.cell,

    --- A marker centred on a world position, sized in screen pixels so it
    -- stays the same size at every zoom.
    --
    -- opts: `position` (Vector3 or Vector2, world), `size`, `color`,
    -- `outline`, `outlineColor`, `alpha`, `resource` (a `ui.texture`),
    -- `onClick` (an async callback), `tooltip` (text shown while the
    -- cursor is over it), `cull` (default true). Clicks and hover need
    -- `interactive = true` on the layer.
    --
    -- Returns nil for a marker off the canvas, so a layer can offer every
    -- one it has and let the view decide.
    marker = draw.marker,

    --------------------------------------------------------------------
    -- Drawing a grid
    --------------------------------------------------------------------

    --- Paint a colour over every visible cell that has one, in one call:
    -- the viewport cull, the loop and a quad budget, with runs of the same
    -- colour merged along each row.
    --
    -- opts: `at(gridX, gridY)` returning colour and alpha (nil colour
    -- leaves the cell alone), `margin` in cells, `budget`.
    cells = draw.cells,

    --- The perimeter of every region on the visible grid: an edge only
    -- where the neighbour belongs to somewhere else, so a block of cells
    -- reads as one shape rather than as its squares.
    --
    -- opts: `group(gridX, gridY)` returning an id that compares equal for
    -- cells that belong together (nil for none), `color` (a Color, or a
    -- function of the id), `width`, `alpha`, `margin`, and
    -- `tooltip(id, gridX, gridY)` which adds a hover target over the whole
    -- cell and needs `interactive = true`.
    outline = draw.outline,

    --------------------------------------------------------------------
    -- The view
    --------------------------------------------------------------------

    --- Current viewport, and the argument every draw is handed.
    --
    -- Read-only as far as a layer is concerned. Carries the world/canvas
    -- and world/cell conversions, `bounds()` and `cellBounds()`, and
    -- `cellRect()` -- which is where anything drawn over a cell must take
    -- its geometry from.
    --
    -- No cell size is exported on purpose: the engine publishes none, and a
    -- constant copied into a consuming mod can silently disagree with the
    -- grid the canvas is drawn on. Work in grid indices and let this convert.
    view = view,

    --------------------------------------------------------------------
    -- The window
    --------------------------------------------------------------------

    open = open,
    close = window.hide,

    --- Redraw now. A no-op while the window is shut, so call it blindly
    -- whenever your data changes.
    redraw = window.refresh,

    isOpen = window.isOpen,
}
