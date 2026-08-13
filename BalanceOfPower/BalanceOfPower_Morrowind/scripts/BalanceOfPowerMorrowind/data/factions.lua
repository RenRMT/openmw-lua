-- Faction definitions for Vvardenfell and Solstheim.
--
-- Two kinds, and the distinction matters:
--
--   LAND-HOLDING (territorial = true). The powers that actually own
--   ground: the Great Houses, the Temple, the Empire, the Ashlanders,
--   and on Solstheim the East Empire Company and the Skaal. These have
--   settlements, project influence, and appear on the map.
--
--   POWER-ONLY (territorial = false). The guilds and the criminal and
--   religious orders. They have standing that rises and falls with their
--   allies through the reaction table, and other systems can read it --
--   but they hold no ground. The Fighters Guild is a real political
--   force in Vvardenfell; it just doesn't own Balmora.
--
-- Ids are the game's own faction record ids wherever one exists, so the
-- reaction rows come from the game's data rather than being invented
-- here. Where no record exists, `reactions` is authored -- and the
-- framework warns at load about any faction that ends up with neither.
--
-- basePower is the starting standing, and is pure guesswork until the
-- thing has been played. It is the first number to reach for when the
-- starting map looks wrong.

return {

    ----------------------------------------------------------------------
    -- Land-holding
    ----------------------------------------------------------------------

    {
        id = 'hlaalu',
        displayName = 'House Hlaalu',
        basePower = 55,
        landmass = 'vvardenfell',
    },
    {
        id = 'redoran',
        displayName = 'House Redoran',
        basePower = 55,
        landmass = 'vvardenfell',
    },
    {
        id = 'telvanni',
        displayName = 'House Telvanni',
        basePower = 50,
        landmass = 'vvardenfell',
    },
    {
        id = 'temple',
        displayName = 'Tribunal Temple',
        basePower = 65,
        landmass = 'vvardenfell',
    },
    {
        -- The merged Empire of design doc 5.1, mapped onto the Legion's
        -- record so its reactions are real game data. Every Imperial
        -- holding in the settlement list is a fort or a Legion-garrisoned
        -- town, so this is not much of a stretch. The Imperial Cult is
        -- kept separate, below.
        id = 'imperial legion',
        displayName = 'The Empire',
        basePower = 65,
        landmass = 'vvardenfell',
    },
    {
        id = 'ashlanders',
        displayName = 'Ashlanders',
        basePower = 30,
        landmass = 'vvardenfell',
    },
    {
        -- Bloodmoon content with no joinable faction record behind it, so
        -- its reactions are authored. Values are how each *other* faction
        -- feels about the Company: the Empire backs it, the Skaal resent
        -- the mining, and Morrowind's own powers are indifferent to a
        -- trading concern on a distant island.
        id = 'east empire company',
        displayName = 'East Empire Company',
        basePower = 30,
        landmass = 'solstheim',
        reactions = {
            ['imperial legion'] = 3,
            ['imperial cult'] = 1,
            skaal = -3,
            hlaalu = 1,
            redoran = -1,
            telvanni = 0,
            temple = -1,
            ['camonna tong'] = -2,
        },
    },
    {
        id = 'skaal',
        displayName = 'Skaal',
        basePower = 25,
        landmass = 'solstheim',
        reactions = {
            ['east empire company'] = -3,
            ['imperial legion'] = -2,
            ['imperial cult'] = -1,
            ashlanders = 1,
            temple = -1,
            ['sixth house'] = -3,
        },
    },

    ----------------------------------------------------------------------
    -- Power-only
    ----------------------------------------------------------------------

    {
        id = 'fighters guild',
        displayName = 'Fighters Guild',
        territorial = false,
        basePower = 30,
    },
    {
        id = 'mages guild',
        displayName = 'Mages Guild',
        territorial = false,
        basePower = 30,
    },
    {
        id = 'thieves guild',
        displayName = 'Thieves Guild',
        territorial = false,
        basePower = 25,
    },
    {
        id = 'imperial cult',
        displayName = 'Imperial Cult',
        territorial = false,
        basePower = 30,
    },
    {
        id = 'camonna tong',
        displayName = 'Camonna Tong',
        territorial = false,
        basePower = 35,
    },
    {
        id = 'morag tong',
        displayName = 'Morag Tong',
        territorial = false,
        basePower = 20,
    },
}
