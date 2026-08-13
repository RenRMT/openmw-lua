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
-- here.
--
-- READ THE REACTION TABLES THIS WAY ROUND:
--
--   reactions[X] = how X feels about the faction whose table this is
--
-- So a table under `hlaalu` saying `ashlanders = -2` means the
-- Ashlanders dislike Hlaalu, and therefore lose standing when Hlaalu
-- gain it. Getting this backwards is easy and almost invisible in play,
-- because symmetric pairs behave the same either way.
--
-- WHY VANILLA FACTIONS HAVE AUTHORED TABLES AT ALL. Authored values are
-- merged over the game's records rather than replacing them, so these
-- tables do not restate Morrowind's politics -- they only add the rows
-- the records cannot contain. Four factions here have no ESM record
-- behind them:
--
--   east empire company, skaal, ashlanders, sixth house
--
-- Nothing in Morrowind.esm can name those, so without the entries below
-- no vanilla faction would have any opinion about them, and their power
-- would never move for any reason other than a direct award. That
-- failure is silent -- they look wired up, they move other factions
-- perfectly well, and nothing ever moves them. `BoP.dumpReactions()`
-- reports the column that would have shown it.
--
-- Every number in those added rows is guesswork, like basePower. They
-- are the second thing to reach for when the politics feel wrong.
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
        reactions = {
            -- The most Imperialized House: good for trade, worst of the
            -- three for anyone who wants Morrowind left alone.
            ['east empire company'] = 1,
            skaal = 0,
            ashlanders = -2,
            ['sixth house'] = -3,
        },
    },
    {
        id = 'redoran',
        displayName = 'House Redoran',
        basePower = 55,
        landmass = 'vvardenfell',
        reactions = {
            ['east empire company'] = -1,
            -- Two warrior cultures with much the same virtues.
            skaal = 1,
            ashlanders = -1,
            ['sixth house'] = -3,
        },
    },
    {
        id = 'telvanni',
        displayName = 'House Telvanni',
        basePower = 50,
        landmass = 'vvardenfell',
        reactions = {
            -- A chartered trading company is competition, and worse,
            -- competition that answers to the Empire.
            ['east empire company'] = -1,
            skaal = -1,
            ashlanders = -1,
            ['sixth house'] = -3,
        },
    },
    {
        id = 'temple',
        displayName = 'Tribunal Temple',
        basePower = 65,
        landmass = 'vvardenfell',
        reactions = {
            ['east empire company'] = -1,
            skaal = -1,
            -- The Ashlanders reject the Tribunal outright; this is the
            -- oldest quarrel on the island.
            ashlanders = -2,
            ['sixth house'] = -3,
        },
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
        reactions = {
            -- The Company holds its charter from the Empire, so imperial
            -- strength is directly its own.
            ['east empire company'] = 3,
            skaal = -2,
            ashlanders = -2,
            ['sixth house'] = -3,
        },
    },
    {
        -- No single Ashlander faction record exists -- the tribes are
        -- separate records where they exist at all -- so this whole row
        -- is authored.
        id = 'ashlanders',
        displayName = 'Ashlanders',
        basePower = 30,
        landmass = 'vvardenfell',
        reactions = {
            hlaalu = -2,
            redoran = -1,
            telvanni = -1,
            temple = -2,
            ['imperial legion'] = -1,
            ['imperial cult'] = -1,
            ['camonna tong'] = -1,
            ['east empire company'] = 0,
            -- Both live outside the settled powers and are treated much
            -- the same way by them.
            skaal = 1,
            ['sixth house'] = -2,
        },
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
            ashlanders = 0,
            ['sixth house'] = -3,
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
            redoran = 1,
            hlaalu = 0,
            telvanni = 0,
        },
    },

    ----------------------------------------------------------------------
    -- Power-only
    ----------------------------------------------------------------------
    --
    -- These have real ESM records, so their vanilla politics arrive on
    -- their own. The tables below add only the four factions those
    -- records cannot name.

    {
        id = 'fighters guild',
        displayName = 'Fighters Guild',
        territorial = false,
        basePower = 30,
        reactions = {
            ashlanders = 0,
            ['sixth house'] = -3,
        },
    },
    {
        id = 'mages guild',
        displayName = 'Mages Guild',
        territorial = false,
        basePower = 30,
        reactions = {
            ashlanders = -1,
            ['sixth house'] = -3,
        },
    },
    {
        id = 'thieves guild',
        displayName = 'Thieves Guild',
        territorial = false,
        basePower = 25,
        reactions = {
            ashlanders = 0,
            ['sixth house'] = -3,
        },
    },
    {
        id = 'imperial cult',
        displayName = 'Imperial Cult',
        territorial = false,
        basePower = 30,
        reactions = {
            ['east empire company'] = 1,
            skaal = -1,
            ashlanders = -1,
            ['sixth house'] = -3,
        },
    },
    {
        id = 'camonna tong',
        displayName = 'Camonna Tong',
        territorial = false,
        basePower = 35,
        reactions = {
            -- Imperial commerce muscling in on Morrowind's own rackets.
            ['east empire company'] = -2,
            skaal = 0,
            ashlanders = -1,
            ['sixth house'] = -2,
        },
    },
    {
        id = 'morag tong',
        displayName = 'Morag Tong',
        territorial = false,
        basePower = 20,
        reactions = {
            ashlanders = 0,
            ['sixth house'] = -3,
        },
    },
}
