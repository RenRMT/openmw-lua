-- Every tunable in one place. A number buried in logic is a number nobody
-- finds again, and this mod is unusable until its costs are tuned.

return {
    -- Two exterior stops this close together are the same place. Only points
    -- in cells the game never named need it -- named cells merge by name --
    -- and the window is measured, not chosen: Daynas Darys stands 396 units
    -- outside Tel Aruhn's cell, while Vivec and Vivec, Foreign Quarter are
    -- only 4192 apart and must stay separate stops.
    NODE_MERGE_RADIUS = 1500,

    -- How far out of a building a walk link may chase a door chain. Vanilla's
    -- deepest stop is two doors in -- the Vivec and Wolverine Hall guild halls
    -- both open onto another interior first -- and the limit is what stops a
    -- mod with a warren of cellars from making the walk unbounded.
    MAX_DOOR_HOPS = 3,

    -- Routing costs. Distance is in game units; the penalties are the price
    -- of an interchange expressed in the same currency, so a route does not
    -- bounce between two modes to save a few metres.
    TRANSFER_PENALTY = 4000,
    MODE_CHANGE_PENALTY = 6000,

    -- Booking.
    BOOKING_RADIUS = 300,
    FARE_PER_UNIT = 0.004,
    HOURS_PER_UNIT = 0.00012,
    MAX_ROUTE_LEGS = 8,
}
