-- Every tunable value
return {
    -- Two exterior stops this close together are considered the same place.
    -- Only for unnamed cells. Named cells merge by name.
    NODE_MERGE_RADIUS = 1500,

    -- How far out of a building a walk link may chase a door chain. Vanilla's
    -- deepest stop is two doors in.
    MAX_DOOR_HOPS = 3,

    -- Routing costs in game units. Penalties prevent bouncing between modes.
    --
    -- Tie-breakers, and nothing more. A vanilla vehicle leg runs a median
    -- 76,000 units, so distance decides every route that is not already
    -- near-level and these only settle the ones that are. Measured over all
    -- 1,056 origin-destination pairs of the vanilla network: raising
    -- TRANSFER_PENALTY from 0 to 4000 moves one journey, and the whole
    -- 0..100,000 range never once changes where a traveller ends up. Both
    -- were settings until that was measured; they are constants now because
    -- no slider can show a player an effect that small.
    TRANSFER_PENALTY = 4000,
    MODE_CHANGE_PENALTY = 6000,

    -- Booking. Vanilla's own scale, but not influenced by modifiers.
    FARE_PER_UNIT = 0.00025,

    -- Additional convenience costs for legs & transfers.
    -- Fractions of the base fare, added rather than compounded.
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

    -- Rows per column. MWUI has no scrollbar, so excess pages instead of clips.
    ROWS_PER_COLUMN = 18,

    -- Last tab collects journeys with this many+ changes; beyond this count matters less.
    MAX_CHANGE_TAB = 3,
    HOURS_PER_UNIT = 0.00012,
    MAX_ROUTE_LEGS = 8,

    -- Real seconds of cell walking per frame. Measured on MW+Tribunal+Bloodmoon+TR.
    --
    -- The number that matters is the COLD one -- the first build after the
    -- game starts, when the cells have to come off disk. Re-measure it warm
    -- and you will get an answer thirty times smaller and conclude the whole
    -- of this is unnecessary. It is not. Both were measured on 2026-08-20,
    -- same session, same 10,319 cells, thirteen seconds apart:
    --
    --   cold, first build after load:  529 slices, ~5.3s of work, 14.6s wall
    --   warm, rebuild() straight after:            ~0.16s of work
    --
    -- so about 0.51ms a cell cold against 0.016ms warm. onUpdate fires ~60
    -- times a second, not the 30 once assumed.
    --
    -- 10ms a frame spread that 5.3s over 14.6s of play without a stutter --
    -- longest slice 19ms. That is the budget doing its job.
    --
    -- This only bites when the walk actually runs. data/operators.lua says
    -- where the operators of the common load orders stand, and the scan
    -- opens one cell each instead -- about 155, a tenth of a second, over
    -- before the first frame is done. The budget is for the load order that
    -- adds a travel service nobody has tabulated -- and for a table gone
    -- stale, since a single unaccounted record sends the scan round every
    -- cell. The build log names it when that happens.
    BUILD_SLICE_SECONDS = 0.010,

    -- How often the build says how far it has got, in real seconds.
    BUILD_REPORT_SECONDS = 5,

    -- Records to read before looking at the clock, while working out which
    -- ones offer travel at all. There are more records than cells and each
    -- is far cheaper, so checking after every one would spend more time
    -- asking the time than reading records.
    SCAN_RECORDS_PER_CHECK = 256,
}
