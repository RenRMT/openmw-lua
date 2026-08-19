-- Event names, in one place.
--
-- The graph is built in the global script, because only global scripts may
-- walk cells; the window is drawn in the player script, because only local
-- scripts may draw. These two names are the whole of the traffic between
-- them, and a typo in one of them is a window that silently never opens.

return {
    -- player -> global: "where can I get to from here?"
    REQUEST_PLAN = 'TravelNetworkRequestPlan',
    -- global -> player: the answer, shaped by plan.lua
    PLAN = 'TravelNetworkPlan',
}
