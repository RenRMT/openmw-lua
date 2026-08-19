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
    -- global -> player: "you have arrived, put yourself back together".
    -- Separate from BOOKED because it has to be handled in the player's own
    -- context: writing a dynamic stat on the player from a global script is
    -- refused at runtime.
    RESTORE = 'TravelAgentsRestore',
}
