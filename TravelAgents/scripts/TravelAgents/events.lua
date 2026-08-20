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
    -- global -> player: "a journey just ended, here is what it was".
    --
    -- Nothing in this mod listens for it. It is sent because a journey
    -- bought here never opens the vanilla ticket window, so a mod watching
    -- for travel the ordinary way sees nothing at all -- and going quiet on
    -- arrival was a deliberate choice that left that gap.
    --
    -- The payload is fact, not vocabulary: `class` is the operator's class
    -- id straight from the content files, not this mod's own mode id, so a
    -- listener needs to know nothing about how TravelAgents files vehicles.
    -- `place` is the stop's name, which is better than the arrival cell's.
    ARRIVED = 'TravelAgentsArrived',
    -- global -> player: "you have arrived, put yourself back together".
    -- Separate from BOOKED because it has to be handled in the player's own
    -- context: writing a dynamic stat on the player from a global script is
    -- refused at runtime.
    RESTORE = 'TravelAgentsRestore',
}
