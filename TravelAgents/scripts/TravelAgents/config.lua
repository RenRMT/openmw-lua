-- Every tunable value
return {
    -- Two exterior stops this close together are considered the same place.
    -- Only for unnamed cells. Named cells merge by name.
    NODE_MERGE_RADIUS = 1500,

    -- How far out of a building a walk link may chase a door chain. Vanilla's
    -- deepest stop is two doors in.
    MAX_DOOR_HOPS = 3,

    -- Routing costs in game units. Penalties prevent bouncing between modes.
    TRANSFER_PENALTY = 4000,
    MODE_CHANGE_PENALTY = 6000,

    -- Booking. Vanilla's own scale, but not influenced by modifiers.
    FARE_PER_UNIT = 0.00025,

    -- Additional convenience costs for legs & transfers.
    -- Fractions of the base fare.
    FARE_LEG_SURCHARGE = 0.10,
    FARE_MODE_CHANGE_SURCHARGE = 0.20,

    -- Window dimensions in pixels.
    WINDOW_WIDTH = 640,
    WINDOW_HEIGHT = 560,
    NAME_COLUMN = 24,

    -- Column width: half the window minus gap.
    COLUMN_WIDTH = 290,
    -- Height after title, tabs, footer, close row.
    LIST_HEIGHT = 360,
    FOOTER_HEIGHT = 90,

    -- Rows per column. Excess rows paginate.
    ROWS_PER_COLUMN = 18,

    -- Last tab collects journeys with this many+ changes.
    MAX_CHANGE_TAB = 3,
    HOURS_PER_UNIT = 0.00012,
    MAX_ROUTE_LEGS = 8,

    -- Real seconds of cell walking per frame. Measured on MW+Tribunal+Bloodmoon+TR.
    --
    BUILD_SLICE_SECONDS = 0.010,

    -- How often the build says how far it has got, in real seconds.
    BUILD_REPORT_SECONDS = 5,

    -- Records to read before looking at the clock, while working out which
    -- ones offer travel at all.
    SCAN_RECORDS_PER_CHECK = 256,
}
