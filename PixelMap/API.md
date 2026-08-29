# Pixel Map — drawing your own layer

Pixel Map is a map window with a stack of layers in it. The two that ship
with it — terrain and cell grid — register through exactly the call your
mod uses, so anything they can do, yours can.

Everything here is player context. `I.PixelMap` is only reachable from a
player script.

## Registering

```lua
local I = require('openmw.interfaces')

local function register()
    I.PixelMap.registerLayer {
        key = 'MyMod_territory',
        name = 'Territory',
        draw = function(view)
            return { I.PixelMap.cell(gridX, gridY, myColor, 0.5) }
        end,
    }
end
```

**Load order is not yours to control**, so `I.PixelMap` may not exist when
your script loads. Handle `PixelMapReady` as well as calling directly:

```lua
return {
    engineHandlers = {
        onInit = function() if I.PixelMap then register() end end,
        onLoad = function() if I.PixelMap then register() end end,
    },
    eventHandlers = {
        PixelMapReady = register,
    },
}
```

Registering the same `key` twice replaces the layer rather than stacking
a second copy, so being called both ways is harmless — and so is
`reloadlua`.

### Layer fields

| Field | |
| --- | --- |
| `key` | Required, unique. Prefix it with your mod name. |
| `name` | Shown on the toggle button. Defaults to `key`. |
| `order` | Low draws first. Built-ins are 10 terrain, 20 grid. Default 100. |
| `enabled` | Default `true`. A layer that costs real time to draw should ship `false` and let the player ask for it. |
| `alpha` | 0–1, applied to the layer as a whole; its widgets inherit it. |
| `interactive` | Needed for clicks and hover. See below. Default `false`. |
| `draw` | Required. `draw(view)` returns a flat list of layouts. |

## Drawing

`draw(view)` is called on every redraw — open, pan, zoom, resize, toggle
— and returns a flat list of `openmw.ui` layouts positioned in canvas
pixels. It runs inside a `pcall`: a layer that errors switches itself off
rather than taking the window down with it.

Five helpers save you the arithmetic. The first three draw one thing;
the last two draw a whole grid at once and are what you want for anything
per-cell.

```lua
-- A solid rectangle, in canvas pixels.
I.PixelMap.quad(x, y, w, h, color, alpha)

-- One exterior cell, by grid coordinates. The unit for territory,
-- ownership, danger, anything painted per cell.
--
-- `tooltip` is optional, and makes the whole cell the hover area rather
-- than a fixed-size marker in the middle of it. It needs
-- `interactive = true` on the layer.
I.PixelMap.cell(gridX, gridY, color, alpha, tooltip)

-- A marker centred on a world position.
I.PixelMap.marker {
    position = obj.position,        -- Vector3 or Vector2, world
    size     = 40,                  -- screen pixels
    color    = util.color.rgb(1, 0, 0),
    tooltip  = 'Balmora',
    onClick  = async:callback(function() ... end),
}
```

Marker sizes are **screen pixels and do not scale with zoom**. That is
deliberate: a marker is a thing to aim at, and one that shrinks when the
player zooms out is exactly what a controller's cursor cannot hit.

Markers off the canvas are dropped and `marker` returns `nil`, so you can
offer every one you have and let the view decide. `t[#t + 1] = nil` is a
no-op in Lua, so the usual accumulate loop needs no guard. Pass
`cull = false` if you have already culled yourself.

### Painting per cell

`cells` is the one to reach for when your data is "a colour for some set
of cells" — territory, ownership, danger, discovery. It does the cull, the
loop and a quad budget, and **merges runs of the same colour along each
row**, so a faction holding a contiguous province costs a handful of
widgets rather than one per cell.

```lua
I.PixelMap.cells {
    -- Return a colour and alpha, or nil to leave the cell unpainted.
    at     = function(gridX, gridY) return myGrid[gridX][gridY], 0.5 end,
    margin = 0,      -- extra cells either way
    budget = 4000,   -- most quads to emit
}
```

`outline` draws the perimeter of every region on the grid: an edge only
where the neighbour belongs somewhere else, so a fifteen-cell city reads
as one shape rather than fifteen squares. What counts as the same region
is yours — `group` returns any value that compares equal for cells that
belong together, which lets you group by two things at once.

```lua
I.PixelMap.outline {
    -- nil means the cell is in no region.
    group   = function(gridX, gridY) return owner[gridX][gridY] end,
    color   = function(id) return colorFor(id) end,   -- or a plain Color
    width   = 2,
    alpha   = 1,
    tooltip = function(id, gridX, gridY) return 'Held by ' .. id end,
}
```

The interior is left unpainted on purpose: an outline says where
something is without hiding the ground it stands on. Put `cells`
underneath if you want both. With `tooltip` you get an invisible
full-cell hover target on top of each cell's edges — the empty middle of
an outlined region answers the cursor — and the layer needs
`interactive = true`.

Both return a flat list, so you can concatenate them with anything else
you draw.

**Colours merge by value, not identity.** A fresh `util.color.rgb` per
cell merges fine. Merged quads are plain images and take no events: if
your cells must answer the cursor, use `outline`'s `tooltip`, or
`cell{ tooltip = }` one at a time.

### The view

| | |
| --- | --- |
| `view.center` | Vector2, world coordinates at the centre of the canvas |
| `view.zoom` | Canvas pixels per world unit |
| `view.canvasSize` | Vector2, pixels |
| `view.cell` | The player's exterior cell, `nil` in an interior |
| `view.worldSpaceId` | Which worldspace is being drawn |
| `view.worldToCanvas(x, y)` | World → canvas pixels |
| `view.canvasToWorld(x, y)` | Canvas pixels → world |
| `view.bounds()` | `minX, minY, maxX, maxY` in world units |
| `view.cellBounds(margin)` | `fromX, fromY, toX, toY` — the visible cell range, or `nil` in an interior |
| `view.cellRect(gridX, gridY)` | `x, y, side` — one cell as a canvas rectangle |
| `view.worldToCell(x, y)` | `gridX, gridY` |
| `view.cellToWorld(gridX, gridY)` | Vector2, the centre of that cell |

**Cull against `cellBounds()`.** The map covers hundreds of thousands of
cells at minimum zoom, and every layout you return becomes a widget. Loop
over the cell range and look your data up, rather than walking your whole
dataset — the first costs what is on screen, the second costs the same at
every zoom no matter how little of it is visible. `cells` and `outline`
do this for you.

`cellBounds()` returns `nil` where there is no exterior, so it doubles as
the "is there anything to draw" guard — that is the same question
`view.cell` answers, and neither is `worldSpaceId`, which a cell is
allowed not to have.

There is deliberately **no exported cell size**. The engine does not
publish one, and a constant copied into your mod is a constant that can
silently disagree with the grid the canvas is drawn on. Work in grid
indices and let `view` convert. `cellRect`'s side carries a one-pixel
overlap that closes the seam between neighbouring cells at fractional
zooms; anything you draw over a cell fill must take its geometry from
there or it will not line up.

## Clicks and tooltips

A transparent sheet sits over the drawing layers and catches drags for
panning, so a widget in an ordinary layer never sees a mouse event.

Set `interactive = true` and your layer is drawn **above** that sheet.
Its widgets then get `mouseClick` and `focusGain`/`focusLoss`, which is
what `onClick` and `tooltip` are built on. The trade is that a drag begun
on one of your widgets does not pan the map, so use it for the layers
that need input and leave the rest alone.

`mouseMove` reaches an interactive layer's widgets too. `mousePress` is
never delivered at all, and `mouseRelease` reaches only the window
itself. `tooltip` still takes a string rather than letting you place one
yourself: the tooltip is drawn on the Popup layer from the cursor
position the window tracks, so it is never clipped by the canvas.

Nothing in an ordinary layer sees any of these — the sheet described
above is in the way, and that is what `interactive` opts out of.

## The rest of the interface

| | |
| --- | --- |
| `I.PixelMap.unregisterLayer(key)` | Removes it. Returns `false` if it was not there. |
| `I.PixelMap.setLayerEnabled(key, on)` | What the toggle button does. |
| `I.PixelMap.setLayerAlpha(key, alpha)` | Fade a layer. |
| `I.PixelMap.open()` / `close()` | Open and close the window. |
| `I.PixelMap.redraw()` | Redraw now. A no-op while the window is shut, so call it blindly when your data changes. |
| `I.PixelMap.isOpen()` | |
| `I.PixelMap.view` | The table above. |
| `I.PixelMap.version` | Currently 1. Gate on it if you use anything below. |

`cells`, `outline`, `marker` culling and the four `view` cell functions
are version 1. Check `I.PixelMap.version >= 1` before calling them if you
want to keep working against an older Pixel Map.

## Budgets

A layer that returns more than a few thousand layouts is reported to the
console once per redraw. It is not a limit — a layer is allowed to be
expensive — but silently expensive is what a player experiences as the
map having become slow for no reason. `cells` takes a `budget` and stops
there; the built-in terrain and grid layers cap themselves the same way.
