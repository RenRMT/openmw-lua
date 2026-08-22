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
    -- Sent out for any as a hook for any mods that listen to travel completion.
    ARRIVED = 'TravelAgentsArrived',
    -- global -> player: restore stats (player context only; global cannot write stats)
    RESTORE = 'TravelAgentsRestore',
}
