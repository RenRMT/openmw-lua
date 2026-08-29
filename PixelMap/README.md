# Pixel Map — a world map drawn in Lua (OpenMW)

A pixel-style map drawn from the terrain itself, so
it works with whatever landmasses your load order adds.

It is not the vanilla map. There is no fog of war; the engine does not
tell Lua which cells you have explored, so the coastline is there whether
you have walked it or not.

## Setup

Point `openmw.cfg` at the mod directory and enable its script list:

```
data="<path to>/openmw-lua/PixelMap"
content=PixelMap.omwscripts
```

Bind a key under **Options → Scripts → Pixel Map**.

## Controls

| | |
| --- | --- |
| Drag the map | Pan |
| Click the map | Centre there |
| Mouse wheel | Zoom |
| `+` / `−` | Zoom |
| Centre on me | Jump back to your own position |
| Tick a layer's box | Show or hide that layer |
| Drag the strip above the layer row | Move the window |
| Drag an edge or corner | Resize the window |

The window opens at about three quarters of your screen the first time, and
after that wherever and however big you last left it.

## Screenshots
![Pixel map example 1](Docs/PixelMap1.jpg)
![Pixel map example 2](Docs/PixelMap2.jpg)

## Settings

**Colour theme** — *Muted*, the default, is a soft physical-atlas
palette. *Classic MW* is the dark, parchment-brown look of the vanilla
world map. *Vivid* is a bright, high-contrast atlas palette.

**Terrain colouring** — *Relief* shades the map by height, like a
physical map: deep sea through shallows, then low ground, hills, peaks.
*Flat* uses one colour for land and one for sea, which is clearer under
another mod's overlay and quicker to draw. Both are drawn from whichever
theme is selected.

## Layers

Two ship with the mod, each with a checkbox above the map. The row wraps
onto further lines when enough mods have added layers to outrun the window:

- **Terrain** — the map itself.
- **Cell grid** — cell boundaries, once you are zoomed in far enough for
  them to be readable.

Your own position is always marked and has no toggle.

Other mods can add layers of their own through the `PixelMap` interface,
declared in `scripts/PixelMap/api.lua`. Its per-cell helpers — a colour
per cell, and the outline round a region — are what a territory or
ownership overlay is built from, and they do the culling and merging that
keeps a map that size quick.

## Known limits

- Exteriors only. In an interior the map has nothing to show.
- A drag that starts on top of a marker does not pan the map.
- Layer toggles and window size are not remembered between sessions.
- Panning redraws the map, so it follows the cursor in steps rather than
  smoothly. If it stutters on a large landmass, raise
  `DRAG_REDRAW_PIXELS` in `scripts/PixelMap/core/config.lua`.
