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
-- The reaction table is what makes the invasion cost everybody something
-- without a line of special-casing anywhere in the invasion code: every
-- faction hates the Sixth House, so its growth is automatically their
-- loss and its setbacks are automatically their relief.
--
-- Authored rather than left to the game's data, because "the Sixth
-- House" is not reliably a faction record across content files, and the
-- consequence of guessing wrong is silent -- the invasion would simply
-- never move anyone's standing, and the only symptom would be a story
-- that fails to land. The other half of the relationship is in
-- data/factions.lua, where every other faction carries a `sixth house`
-- entry; without both halves the hostility only runs one way.
--
-- Authored values merge over the record where one exists, so this costs
-- nothing if the record turns out to be there.

return {
    id = 'sixth_house',

    faction = {
        id = 'sixth house',
        displayName = 'Sixth House',
        landmass = 'vvardenfell',

        basePower = 30,

        -- How each other faction feels about the Sixth House. Nobody
        -- makes an exception; the Ashlanders are the mildest only
        -- because they were never part of what Dagoth Ur wants back.
        reactions = {
            hlaalu = -3,
            redoran = -3,
            telvanni = -3,
            temple = -3,
            ['imperial legion'] = -3,
            ['imperial cult'] = -3,
            ashlanders = -2,
            ['east empire company'] = -3,
            skaal = -3,
            ['fighters guild'] = -3,
            ['mages guild'] = -3,
            ['thieves guild'] = -2,
            ['camonna tong'] = -2,
            ['morag tong'] = -2,
        },

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
