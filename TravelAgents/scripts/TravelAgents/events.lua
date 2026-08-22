-- Event names

return {
    -- player -> global: plan request from current position
    REQUEST_PLAN = 'TravelAgentsRequestPlan',
    -- global -> player: plan response (from plan.lua)
    PLAN = 'TravelAgentsPlan',
    -- player -> global: book request (names stop and operator, not price)
    BOOK = 'TravelAgentsBook',
    -- global -> player: booking result (sent even if refused)
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
    -- global -> player: restore stats (player context only; global cannot write stats)
    RESTORE = 'TravelAgentsRestore',
}
