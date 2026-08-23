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

Three helpers save you the arithmetic:

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

**Cull against `bounds()`.** The map covers hundreds of cells when zoomed
out, and every layout you return becomes a widget. For per-cell fills,
turn the bounds into a cell range and loop over that, not over your whole
dataset.

`view.cell` is the test for "is there an exterior to draw" — not
`worldSpaceId`, which a cell is allowed not to have.

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
| `I.PixelMap.version` | Currently 1. |
