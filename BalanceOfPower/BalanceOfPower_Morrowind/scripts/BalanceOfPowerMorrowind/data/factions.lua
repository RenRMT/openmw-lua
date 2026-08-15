-- Faction tuning for Vvardenfell and Solstheim.
--
-- Not a faction list: the framework registers every faction from the
-- game's own FACT records, and derives starting power from each one's
-- settlements. What is left here is what vanilla has no field for and
-- geography cannot imply.
--
-- Most factions need no entry at all. The ones below either fight, grow,
-- field patrols, or have no politics in the records and would otherwise
-- go unregistered.

return {

    -- An ordinary faction holding Red Mountain. What makes it an invasion
    -- is two fields, not a subsystem: it grows on its own, and it fights.
    --
    -- Escalation comes free from that. Projection is power scaled by
    -- distance decay, so the Sixth House reaches barely past Red Mountain
    -- at low standing and pushes outward as power accrues -- the stages
    -- the design document enumerated, with no stage table. What stops it
    -- taking Vvardenfell is the exchange rate rather than any rule.
    {
        id = 'sixth house',
        -- ~3 weeks to double its standing. Nothing pushes back until the
        -- phase 5 quest hooks, so until then this only ever climbs.
        growthPerDay = 1.5,
        -- Attacks the player, and any faction it regards at or below -3 --
        -- given its vanilla row, everyone except the Camonna Tong. Growth
        -- deliberately does not propagate: a daily drip through a row of
        -- -3s empties the map. See GROWTH_PROPAGATES.
        hostile = true,
        -- Tiered so what appears worsens as the Sixth House grows. Lower
        -- tiers stay in the pool, so an ascended sleeper leads ash slaves
        -- rather than arriving with three of its peers.
        patrolRoster = {
            'ash slave',
            'corprus stalker',
            { id = 'ash zombie', tier = 2 },
            { id = 'ash ghoul', tier = 3 },
        },
    },

    -- No reactions in either direction, so the records alone would leave
    -- them out. Named here to keep them in the standings, which is where
    -- an extension looking for them will expect to find them.
    { id = 'morag tong' },
    { id = 'talos cult' },
    { id = 'skaal' },
}
