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

    -- Booking. There is no radius here: the planner opens from a conversation,
    -- so the operator selling the journey is whoever is being talked to and
    -- nothing has to search for one.
    FARE_PER_UNIT = 0.004,

    -- What the convenience costs. Buying one ticket for a journey somebody
    -- else has to arrange is worth more than the legs are, so each leg past
    -- the first adds a share of the fare, and a change between two kinds of
    -- transport -- which crosses two operators who have no arrangement with
    -- each other -- adds more again. Fractions of the base fare, added
    -- together rather than compounded: three legs with one change of vehicle
    -- is 5 + 5 + 10 per cent, not a product of three multipliers.
    FARE_LEG_SURCHARGE = 0.05,
    FARE_MODE_CHANGE_SURCHARGE = 0.10,
    HOURS_PER_UNIT = 0.00012,
    MAX_ROUTE_LEGS = 8,
}
