-- All PixelMap tunables. Numbers are world units unless a name says otherwise.

local util = require('openmw.util')

return {
    L10N_CONTEXT = 'PixelMap',
    SETTINGS_PAGE = 'PixelMap',

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

    -- Colour themes. Player chooses on settings; keys are l10n keys too.
    TERRAIN_THEME = 'muted',
    -- Flat style and the off-map void take fixed stops out of whichever theme
    -- is live, so a new theme never needs its own flat colours.
    FLAT_WATER_STOP = 2,
    FLAT_LAND_STOP = 2,
    VOID_WATER_STOP = 1,
    -- Relief ramps: evenly spaced colour stops interpolated across the bands.
    -- Any number of stops; repeat one to hold a colour over more of the range.
    TERRAIN_THEMES = {
        muted = {
            water = {
                util.color.rgb(0.290196, 0.392157, 0.470588),  -- #4a6478
                util.color.rgb(0.447059, 0.572549, 0.670588),  -- #7292ab
                util.color.rgb(0.635294, 0.729412, 0.788235),  -- #a2bac9
            },
            land = {
                util.color.rgb(0.584314, 0.592157, 0.431373),  -- #95976e
                util.color.rgb(0.701961, 0.650980, 0.509804),  -- #b3a682
                util.color.rgb(0.796078, 0.674510, 0.556863),  -- #cbac8e
                util.color.rgb(0.862745, 0.749020, 0.639216),  -- #dcbfa3
                util.color.rgb(0.917647, 0.850980, 0.772549),  -- #ead9c5
                util.color.rgb(0.972549, 0.945098, 0.901961),  -- #f8f1e6
            },
        },
        classic = {
            water = {
                util.color.rgb(0.078431, 0.121569, 0.113725),  -- #141f1d
                util.color.rgb(0.105882, 0.160784, 0.149020),  -- #1b2926
                util.color.rgb(0.145098, 0.207843, 0.184314),  -- #25352f
            },
            land = {
                util.color.rgb(0.250980, 0.188235, 0.121569),  -- #40301f
                util.color.rgb(0.203922, 0.145098, 0.101961),  -- #34251a
                util.color.rgb(0.168627, 0.121569, 0.086275),  -- #2b1f16
                util.color.rgb(0.141176, 0.101961, 0.070588),  -- #241a12
                util.color.rgb(0.105882, 0.078431, 0.062745),  -- #1b1410
                util.color.rgb(0.054902, 0.043137, 0.031373),  -- #0e0b08
            },
        },
        vivid = {
            water = {
                util.color.rgb(0.050980, 0.129412, 0.286275),  -- #0d2149
                util.color.rgb(0.121569, 0.372549, 0.658824),  -- #1f5fa8
                util.color.rgb(0.290196, 0.564706, 0.850980),  -- #4a90d9
            },
            land = {
                util.color.rgb(0.305882, 0.372549, 0.243137),  -- #4e5f3e
                util.color.rgb(0.372549, 0.435294, 0.270588),  -- #5f6f45
                util.color.rgb(0.490196, 0.478431, 0.321569),  -- #7d7a52
                util.color.rgb(0.611765, 0.572549, 0.439216),  -- #9c9270
                util.color.rgb(0.776471, 0.752941, 0.690196),  -- #c6c0b0
                util.color.rgb(0.909804, 0.901961, 0.866667),  -- #e8e6dd
            },
        },
    },
    -- Order of the theme select; keeps the list stable (TERRAIN_THEMES is a hash).
    TERRAIN_THEME_ORDER = { 'muted', 'classic', 'vivid' },

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

    -- Default edge for a bordered cell. White because a per-cell overlay
    -- is read as a shape before it is read as a colour, and a light edge
    -- separates two adjacent owners of similar hue.
    COLOR_CELL_BORDER = util.color.rgb(1, 1, 1),
}
