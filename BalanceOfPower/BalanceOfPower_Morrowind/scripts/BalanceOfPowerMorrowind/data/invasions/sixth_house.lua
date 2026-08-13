-- The Sixth House (design doc section 4).
--
-- An invading faction is an ordinary faction with a different growth
-- source and a different consequence when it wins, so almost everything
-- here is the same shape as a Great House. What differs: it grows on a
-- timer rather than through the player's dealings, it holds a homeland
-- it cannot lose, and taking ground corrupts it rather than annexing it.
--
-- Its power centers come from the settlement list (Dagoth Ur), not from
-- this file -- see main.lua, which hands them over.
--
-- The reaction table is the payoff of reusing the game's own disposition
-- data: the Sixth House's vanilla row is hostile to essentially
-- everyone, and everyone's row is hostile back, so its growth
-- automatically costs every other faction power and every setback
-- automatically gives everyone relief. No special-casing anywhere in the
-- invasion code. If the framework warns at load that this faction has no
-- reactions, that assumption is wrong for the installed content files
-- and a table needs authoring here.

return {
    id = 'sixth_house',

    faction = {
        id = 'sixth house',
        displayName = 'Sixth House',
        landmass = 'vvardenfell',

        basePower = 30,

        -- Ambient drift, independent of anything the player does. The
        -- primary pacing dial for the whole invasion: at 1.5 a day it
        -- takes roughly three weeks to reach `raiding` and four months to
        -- reach `overrunning`, assuming nobody pushes back.
        growthPerDay = 1.5,

        -- Red Mountain. Held unconditionally: an authored owner overrides
        -- projection, so this stays theirs no matter who out-projects
        -- them there.
        homeTerritories = { 'dagoth_ur' },

        escalationThresholds = {
            { stage = 'stirring',    power = 30 },
            { stage = 'raiding',     power = 60 },
            { stage = 'encroaching', power = 100 },
            { stage = 'overrunning', power = 150 },
        },

        -- Vanilla record ids, reused as-is. Nothing here needs the
        -- Construction Set.
        patrolRoster = {
            'ash zombie',
            'ash ghoul',
            'ash slave',
            'corprus stalker',
        },
    },
}
