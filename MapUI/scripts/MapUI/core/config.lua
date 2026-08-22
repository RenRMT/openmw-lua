-- All MapUI tunables. Numbers are world units unless a name says otherwise.

local util = require('openmw.util')

return {
    L10N_CONTEXT = 'MapUI',
    SETTINGS_PAGE = 'MapUI',

    -- Time redraws; off by default (prints per frame). Pair with `lua profiler = true` in settings.cfg.
    PROFILE = false,

    -- Morrowind exterior cell: 8192 units. Used for grid, terrain alignment, cache.
    CELL_SIZE = 8192,

    -- Canvas is fraction of screen (same ratio on 4K and 1080p).
    CANVAS_SCREEN_FRACTION = 0.72,
    CANVAS_MIN_WIDTH = 480,
    CANVAS_MIN_HEIGHT = 360,
    WINDOW_MARGIN_X = 40,
    WINDOW_MARGIN_Y = 110,
    WINDOW_MIN_WIDTH = 420,
    WINDOW_MIN_HEIGHT = 320,

    -- Invisible grab strips; window is hand-rolled (ui.TYPE.Window cannot be resized).
    FRAME_GRAB = 8,
    FRAME_TITLE_HEIGHT = 24,

    -- Pan redraws sampled by cursor distance; zoom/resize similarly sampled.
    DRAG_REDRAW_PIXELS = 20,
    DRAG_TAP_PIXELS = 4,
    RESIZE_REDRAW_PIXELS = 16,

    -- At 0.012 one cell is ~98px; min fits ~370 cells (landmass mods).
    ZOOM_MIN = 0.00025,
    ZOOM_MAX = 0.08,
    ZOOM_DEFAULT = 0.012,
    ZOOM_STEP = 1.5,

    -- Terrain samples snapped to cell fractions; quad cap prevents widget bloat.
    TERRAIN_SAMPLES = 44,
    TERRAIN_MAX_QUADS = 4000,
    TERRAIN_MAX_SUBDIV = 5,

    -- Default style ('relief' by height, 'flat' for land/sea; flat merges more). Player chooses on settings.
    TERRAIN_STYLE = 'relief',
    COLOR_FLAT_LAND = util.color.rgb(0.40, 0.44, 0.32),
    COLOR_FLAT_OCEAN = util.color.rgb(0.11, 0.19, 0.34),

    -- Colour bands: sea is one band over most area (major savings); more bands = smoother ramp, more widgets.
    TERRAIN_COLOR_BANDS = 24,
    TERRAIN_WATER_BANDS = 8,
    -- Negative: one sample spans 2^-n cells (-6 = 64 cells per sample for Tamriel Rebuilt).
    TERRAIN_MIN_SUBDIV = -6,
    -- Two generations kept; rotation drops older half (vs wiping all, which killed cache feel).
    TERRAIN_CACHE_LIMIT = 150000,

    -- Height ramp: WATER_LEVEL is map switch point (not cell-specific). PEAK is above Red Mountain.
    WATER_LEVEL = 0,
    TERRAIN_FLOOR = -2500,
    TERRAIN_PEAK = 6500,
    COLOR_DEEP = util.color.rgb(0.05, 0.10, 0.24),
    COLOR_SHALLOW = util.color.rgb(0.20, 0.42, 0.60),
    COLOR_LOW = util.color.rgb(0.32, 0.42, 0.24),
    COLOR_MID = util.color.rgb(0.52, 0.44, 0.28),
    COLOR_HIGH = util.color.rgb(0.82, 0.80, 0.76),
    COLOR_VOID = util.color.rgb(0.06, 0.06, 0.07),

    -- Grid dropped when cell narrower than this.
    GRID_MIN_SPACING = 24,
    GRID_MAX_LINES = 200,
    COLOR_GRID = util.color.rgb(0.35, 0.35, 0.38),

    -- Marker default: large for joystick cursor targeting.
    MARKER_SIZE = 26,
    MARKER_OUTLINE = 3,

    -- Player marker: small, quiet, readable.
    PLAYER_MARKER_SIZE = 11,
    PLAYER_MARKER_OUTLINE = 2,
    TOOLTIP_OFFSET_X = 18,
    TOOLTIP_OFFSET_Y = 18,
    TOOLTIP_MARGIN = 8,
    COLOR_PLAYER = util.color.rgb(0.93, 0.82, 0.38),
    COLOR_MARKER_OUTLINE = util.color.rgb(0.05, 0.05, 0.05),
}
