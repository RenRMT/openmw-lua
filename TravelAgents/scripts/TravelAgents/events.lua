-- Event names

return {
    -- player -> global: "where can I get to from here?"
    REQUEST_PLAN = 'TravelAgentsRequestPlan',
    -- global -> player: the answer, shaped by plan.lua
    PLAN = 'TravelAgentsPlan',
    -- player -> global: "take me there". Names the stop and the operator, not
    -- a price -- the global script quotes the journey again before charging
    -- for it.
    BOOK = 'TravelAgentsBook',
    -- global -> player: what happened. Sent whether or not the journey was
    -- made, because a refusal the player never hears about reads as a bug.
    BOOKED = 'TravelAgentsBooked',
}
