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
    MASTER_WIDTH = 260,
    NAME_COLUMN = 24,

    -- How many places the list shows before offering the rest.
    SHOWN_STOPS = 16,
    HOURS_PER_UNIT = 0.00012,
    MAX_ROUTE_LEGS = 8,
}
