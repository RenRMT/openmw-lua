-- Every tunable value
return {
    -- Two exterior stops this close together are considered the same place.
    -- Only for unnamed cells. Named cells merge by name.
    NODE_MERGE_RADIUS = 1500,

    -- How far out of a building a walk link may chase a door chain. Vanilla's
    -- deepest stop is two doors in.
    MAX_DOOR_HOPS = 3,

    -- Routing costs in game units; the penalties are the cost of an interchange
    -- so a route does not bounce between two modes to save a few metres.
    TRANSFER_PENALTY = 4000,
    MODE_CHANGE_PENALTY = 6000,

    -- Booking. Vanilla's own scale, but not influenced by modifiers.
    FARE_PER_UNIT = 0.00025,

    -- Additional convenience costs for legs & transfers.
    -- Fractions of the base fare, added rather than compounded.
    FARE_LEG_SURCHARGE = 0.10,
    FARE_MODE_CHANGE_SURCHARGE = 0.20,

    -- The planner window, in pixels.
    WINDOW_WIDTH = 640,
    WINDOW_HEIGHT = 560,
    NAME_COLUMN = 24,

    -- Both halves of the window are the destination list, so a column is
    -- half of it less the gap between them.
    COLUMN_WIDTH = 290,
    -- What is left once the title, the tabs, the footer and the close row
    -- have taken theirs.
    LIST_HEIGHT = 360,
    FOOTER_HEIGHT = 90,

    -- Rows in one column. Two columns to a page, so a page holds twice
    -- this; anything past it pages rather than overflowing the window,
    -- because MWUI has no scrollbar and a clipped row is unreachable
    -- rather than merely unseen.
    ROWS_PER_COLUMN = 18,

    -- Tabs across the window before the row wraps. Flex does not wrap on
    -- its own.
    TABS_PER_ROW = 5,

    -- The last tab in the row, which collects every journey needing this
    -- many changes of vehicle or more. Past it the count stops telling the
    -- player anything they would choose differently on.
    MAX_CHANGE_TAB = 3,
    HOURS_PER_UNIT = 0.00012,
    MAX_ROUTE_LEGS = 8,

    -- Real seconds of cell walking to do per frame while building the graph.
    -- Small enough to disappear into a frame's slack at any playable frame
    -- rate; the whole walk is nine thousand cells on a load order with a
    -- mainland in it, so this trades a second or two of background work for
    -- never stalling.
    BUILD_SLICE_SECONDS = 0.002,
}
