-- Faction tuning for Vvardenfell and Solstheim.
--
-- The framework registers every faction from the game's own FACT records,
-- so this file is not a faction list. It holds only the numbers vanilla
-- has no field for: basePower, growthPerDay, hostile, patrolRoster.
--
-- Whether a faction holds ground is derived from whether any settlement
-- names it, and its display name comes from the record. Neither is
-- authored here.
--
-- basePower is guesswork until the thing has been played, and is the
-- first number to reach for when the starting map looks wrong.

return {

    ----------------------------------------------------------------------
    -- Land-holding
    ----------------------------------------------------------------------

    { id = 'hlaalu', basePower = 55 },
    { id = 'redoran', basePower = 55 },
    { id = 'telvanni', basePower = 50 },
    { id = 'temple', basePower = 65 },
    -- The merged Empire of design doc 5.1, registered under the Legion's
    -- own record id so its reactions are real game data. Every Imperial
    -- holding in the settlement list is a fort or a Legion-garrisoned
    -- town. The Imperial Cult and the Knights stay separate.
    { id = 'imperial legion', basePower = 65 },
    { id = 'ashlanders', basePower = 30 },
    { id = 'east empire company', basePower = 30 },
    { id = 'skaal', basePower = 25 },

    {
        -- An ordinary faction holding Red Mountain. What makes it an
        -- invasion is two fields, not a subsystem: it grows on its own,
        -- and it fights.
        --
        -- Escalation comes free from that. Projection is power scaled by
        -- distance decay, so the Sixth House reaches barely past Red
        -- Mountain at low standing and pushes outward as power accrues --
        -- the stages the design document enumerated, with no stage table.
        -- What stops it taking Vvardenfell is the exchange rate rather
        -- than any rule: it creeps, decelerating, and never realistically
        -- leaves the Ashlands.
        id = 'sixth house',
        basePower = 30,
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

    ----------------------------------------------------------------------
    -- Power-only
    --
    -- Registered from the records regardless; these entries exist only to
    -- set a starting standing. Phase 2 derives it and they go away.
    ----------------------------------------------------------------------

    { id = 'fighters guild', basePower = 30 },
    { id = 'mages guild', basePower = 30 },
    { id = 'thieves guild', basePower = 25 },
    { id = 'imperial cult', basePower = 30 },
    { id = 'imperial knights', basePower = 20 },
    { id = 'blades', basePower = 20 },
    { id = 'census and excise', basePower = 15 },
    { id = 'camonna tong', basePower = 35 },
    { id = 'morag tong', basePower = 20 },
    { id = 'talos cult', basePower = 10 },
    { id = 'twin lamps', basePower = 10 },
    { id = 'nerevarine', basePower = 5 },
    { id = 'clan aundae', basePower = 12 },
    { id = 'clan berne', basePower = 12 },
    { id = 'clan quarra', basePower = 12 },
}
