# MapUI Design Notes

## OpenMW 0.51 Engine Behaviour

### Event Delivery Model
- `mousePress` is never delivered to any widget
- `mouseMove` and `mouseRelease` reach only an Element root, never a child
- `mouseClick` and `focusGain`/`focusLoss` do reach children
- Drags are driven from the root and classified by cursor position

### UI Element Constraints
- `ui.texture{path='transparent'}` renders as opaque white, not transparent; use white at alpha 0
- `ui.TYPE.Window` cannot be resized (no move/resize handles in vfs/mygui/openmw_lua.xml) and swallows drags; MapUI uses a hand-rolled frame instead

### Element Layout
- A nested `ui.create` Element is a rebuild boundary: `update()` on a parent does not refresh a child Element's layout
- Solution: one Element per layer

### Tooltip Architecture
- Tooltips need two event sources: focus events reveal what is hovered but carry no position; root mouseMove carries position but knows nothing about markers
- `focusLoss` must be guarded by label because adjacent widgets' enter/leave can arrive in either order

### Terrain Sampling
- Step snapped to CELL_SIZE / 2^n
- Colour banding with waterline on a band boundary
- Horizontal run merging on drawn colour (mergeKey)
- Two-generation cache keyed by worldspace
