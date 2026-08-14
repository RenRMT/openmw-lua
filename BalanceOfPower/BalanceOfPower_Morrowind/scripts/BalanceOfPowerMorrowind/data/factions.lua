-- Faction definitions for Vvardenfell and Solstheim.
--
-- Two kinds, and the distinction matters:
--
--   LAND-HOLDING (territorial = true). The powers that actually own
--   ground: the Great Houses, the Temple, the Empire, the Ashlanders,
--   and on Solstheim the East Empire Company and the Skaal. These have
--   settlements, project influence, and appear on the map.
--
--   POWER-ONLY (territorial = false). The guilds, the orders, the cults
--   and the clans. They have standing that rises and falls with their
--   allies through the reaction table, and other systems can read it --
--   but they hold no ground. The Fighters Guild is a real political
--   force in Vvardenfell; it just doesn't own Balmora.
--
-- Ids are the game's own faction record ids wherever one exists.
--
-- READ THE REACTION TABLES THIS WAY ROUND:
--
--   reactions[X] = how this faction feels about X
--
-- A row belongs to the faction holding the opinions, so a table under
-- `hlaalu` saying `ashlanders = -2` means Hlaalu dislike the Ashlanders,
-- and so lose standing when the Ashlanders gain it. That is the same
-- direction the game's own faction records use, and the framework knows
-- no other -- see core/power.lua.
--
-- THE ROWS ARE VANILLA'S, TRANSCRIBED. Every reaction below is the value
-- Morrowind's own FACT record carries, with three classes of exception,
-- each marked where it appears:
--
--   * Bloodmoon's East Empire Company and Skaal predate nothing -- they
--     are simply absent from the base game's reaction matrix -- so their
--     pairs are authored guesses, like basePower.
--   * One deliberate override, on Redoran's regard for the Sixth House.
--   * Zeros are omitted. An absent entry already reads as zero, and a
--     reaction of zero propagates nothing, so writing them out would add
--     three hundred lines that say "no opinion" twice.
--
-- Transcribing rather than leaning on the records costs nothing -- an
-- identical value merged over an identical value -- and buys two things:
-- the pack stops depending on every record id resolving in game, and the
-- test suite, which runs against an empty record stub, exercises real
-- numbers instead of an empty world.
--
-- FOUR FACTIONS SIT OUTSIDE THE POLITICS, and vanilla says so rather
-- than this file forgetting them:
--
--   morag tong, talos cult    no reactions either way, at all
--   nerevarine                nobody it reacts to; Redoran and the
--                             Temple react to it
--   twin lamps                hates Telvanni; nobody has heard of them
--
-- `BoP.dumpReactions()` reports each of these as a zero column, which is
-- normally the sign of a mistake. Here it is the data. Anything else
-- appearing in that report is worth chasing.
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
            redoran = -1,
            telvanni = -1,
            temple = 1,
            ['imperial legion'] = 1,
            ashlanders = -2,
            -- The most Imperialized House, and a chartered trading
            -- company answering to the Empire suits it. Authored:
            -- Bloodmoon's factions are absent from the vanilla matrix.
            ['east empire company'] = 1,
            ['sixth house'] = -3,
            ['fighters guild'] = 1,
            ['mages guild'] = 1,
            ['thieves guild'] = -1,
            ['imperial cult'] = 1,
            ['camonna tong'] = 1,
            ['clan aundae'] = -2,
            ['clan berne'] = -2,
            ['clan quarra'] = -2,
        },
    },
    {
        id = 'redoran',
        displayName = 'House Redoran',
        basePower = 55,
        landmass = 'vvardenfell',
        reactions = {
            hlaalu = -1,
            telvanni = -1,
            temple = 2,
            ['imperial legion'] = 1,
            ashlanders = -2,
            ['east empire company'] = -1,
            -- OVERRIDE. Vanilla has Redoran at 0 toward the Sixth House,
            -- alone among the Houses and the Temple, who all sit at -3.
            -- Taken as a data slip rather than a position: Redoran is the
            -- House whose whole story is holding the line against the
            -- blight, and at 0 it would be the one Great House the
            -- invasion costs nothing, which shows up as a hole in the
            -- middle of the map rather than as an error.
            ['sixth house'] = -3,
            -- Two warrior cultures with much the same virtues. Authored.
            skaal = 1,
            ['fighters guild'] = 1,
            ['mages guild'] = -1,
            ['thieves guild'] = -1,
            ['camonna tong'] = -1,
            -- Vanilla really does say -4, past the nominal range. The
            -- framework clamps to REACTION_CLAMP on the way in.
            nerevarine = -4,
            ['clan aundae'] = -2,
            ['clan berne'] = -2,
            ['clan quarra'] = -2,
        },
    },
    {
        id = 'telvanni',
        displayName = 'House Telvanni',
        basePower = 50,
        landmass = 'vvardenfell',
        reactions = {
            hlaalu = -1,
            redoran = -1,
            temple = -1,
            ['imperial legion'] = -1,
            ashlanders = -1,
            ['east empire company'] = -1,
            ['sixth house'] = -3,
            -- The one real feud on this row, and it runs both ways: no
            -- Telvanni wizard answers to a guild charter.
            ['mages guild'] = -3,
            ['imperial cult'] = -1,
            ['clan aundae'] = -1,
            ['clan berne'] = -1,
            ['clan quarra'] = -1,
        },
    },
    {
        id = 'temple',
        displayName = 'Tribunal Temple',
        basePower = 65,
        landmass = 'vvardenfell',
        reactions = {
            hlaalu = 1,
            redoran = 2,
            telvanni = -1,
            ['imperial legion'] = -1,
            ashlanders = -1,
            ['east empire company'] = -1,
            ['sixth house'] = -3,
            skaal = -1,
            ['fighters guild'] = -1,
            ['mages guild'] = -2,
            ['thieves guild'] = -1,
            ['imperial cult'] = -2,
            blades = -1,
            -- The strongest opinion anywhere in the vanilla matrix, and
            -- well past the nominal range. Clamped, like Redoran's.
            nerevarine = -8,
            ['clan aundae'] = -3,
            ['clan berne'] = -3,
            ['clan quarra'] = -3,
        },
    },
    {
        -- The merged Empire of design doc 5.1, mapped onto the Legion's
        -- record so its reactions are real game data. Every Imperial
        -- holding in the settlement list is a fort or a Legion-garrisoned
        -- town, so this is not much of a stretch. The Imperial Cult and
        -- the Knights are kept separate, below.
        id = 'imperial legion',
        displayName = 'The Empire',
        basePower = 65,
        landmass = 'vvardenfell',
        reactions = {
            hlaalu = 1,
            redoran = 1,
            telvanni = -1,
            temple = -1,
            ashlanders = -2,
            -- The Company holds its charter from the Empire, so imperial
            -- strength is directly its own. Authored.
            ['east empire company'] = 3,
            ['sixth house'] = -3,
            skaal = -2,
            ['fighters guild'] = 2,
            ['mages guild'] = 1,
            ['thieves guild'] = -1,
            ['imperial cult'] = 2,
            ['camonna tong'] = -2,
            blades = 2,
            ['clan aundae'] = -2,
            ['clan berne'] = -2,
            ['clan quarra'] = -2,
        },
    },
    {
        id = 'ashlanders',
        displayName = 'Ashlanders',
        basePower = 30,
        landmass = 'vvardenfell',
        reactions = {
            hlaalu = -2,
            redoran = -2,
            telvanni = -1,
            temple = -1,
            ['imperial legion'] = -2,
            ['sixth house'] = -3,
            -- Both live outside the settled powers and are treated much
            -- the same way by them. Authored.
            skaal = 1,
            ['fighters guild'] = -2,
            ['mages guild'] = -1,
            ['thieves guild'] = -2,
            ['imperial cult'] = -1,
            ['camonna tong'] = -1,
            blades = -1,
            ['clan aundae'] = -3,
            ['clan berne'] = -3,
            ['clan quarra'] = -3,
        },
    },
    {
        -- Bloodmoon content, absent from the vanilla reaction matrix, so
        -- this whole row is authored: how the Company sees everyone else.
        -- It holds its charter from the Empire, so imperial strength is
        -- directly its own; the Skaal are what stands between it and the
        -- mining; and at that distance Morrowind's own powers are
        -- competitors rather than enemies.
        id = 'east empire company',
        displayName = 'East Empire Company',
        basePower = 30,
        landmass = 'solstheim',
        reactions = {
            hlaalu = 1,
            redoran = -1,
            telvanni = -1,
            temple = -1,
            ['imperial legion'] = 3,
            ['sixth house'] = -3,
            skaal = -3,
            ['imperial cult'] = 1,
            ['camonna tong'] = -2,
        },
    },
    {
        -- An ordinary faction, holding Red Mountain and reaching barely
        -- past it. What makes it an invasion is two fields, not a
        -- subsystem: it grows on its own, and it fights.
        --
        -- Its escalation comes free from that. Projection is power scaled
        -- by distance decay, so at low standing the Sixth House reaches
        -- barely past Red Mountain and its patrols appear around
        -- Ghostgate; as power accrues the same radius pushes outward on
        -- its own. Dormant, stirring, encroaching -- the stages the
        -- design document enumerated, with no stage table to maintain.
        --
        -- What it will not do is take Vvardenfell, though nothing
        -- forbids it: projection halves with distance and never stops.
        -- What stops it is the exchange rate. Dagoth Ur is an outpost, so
        -- two cells out costs it about 880 power and five cells about
        -- 258,000 -- an in-game year and a half for the first, centuries
        -- for the second. It creeps, decelerating, and never realistically
        -- leaves the Ashlands.
        --
        -- Both halves of its politics are load-bearing, and they are not
        -- the same half. The row below decides who it attacks -- everyone
        -- it regards at -3, which vanilla makes almost everybody. The
        -- `sixth house` entry every other faction carries is what makes
        -- an *awarded* change to its standing cost or relieve them,
        -- without a line of special-casing.
        --
        -- Its daily growth deliberately does not propagate. A drip
        -- through a table where nearly every entry is -3 compounds until
        -- the whole map is at zero power; see GROWTH_PROPAGATES. The
        -- Sixth House costing everyone something is a thing that happens
        -- when the world acts on its behalf, not something that accrues
        -- while nobody is looking.
        id = 'sixth house',
        displayName = 'Sixth House',
        basePower = 30,
        landmass = 'vvardenfell',
        -- The one faction on Vvardenfell that gets stronger whether or
        -- not anyone is paying attention. ~3 weeks to double its
        -- standing, ~4 months to the point where it holds every cell it
        -- can reach; after that it is capped by geography rather than by
        -- this number.
        --
        -- Nothing pushes back yet. Player counter-play arrives with the
        -- quest hooks in phase 5, and until then this only ever climbs.
        growthPerDay = 1.5,
        -- Attacks the player, and attacks any faction it regards at or
        -- below -3 -- which, given the row below, is everyone except the
        -- Camonna Tong. No other faction on Vvardenfell is flagged, so
        -- the Great Houses go on tolerating each other.
        hostile = true,
        reactions = {
            hlaalu = -3,
            redoran = -3,
            telvanni = -3,
            temple = -3,
            ['imperial legion'] = -3,
            ashlanders = -3,
            ['east empire company'] = -3,
            skaal = -3,
            ['fighters guild'] = -3,
            ['mages guild'] = -3,
            ['thieves guild'] = -3,
            ['imperial cult'] = -3,
            -- The one faction it merely dislikes. Vanilla's judgement,
            -- not this file's: a smuggling ring is no threat to what
            -- Dagoth Ur wants back.
            ['camonna tong'] = -1,
            blades = -3,
            ['clan aundae'] = -3,
            ['clan berne'] = -3,
            ['clan quarra'] = -3,
        },
        -- Vanilla record ids, reused as-is. Nothing here needs the
        -- Construction Set.
        --
        -- Tiered, so what appears gets worse as the Sixth House grows
        -- rather than being the same on the first day and the last. The
        -- lower tiers stay in the pool at every tier above them: an
        -- ascended sleeper leading a knot of ash slaves reads as a cult
        -- gaining ground, where four of them together reads as a boss
        -- fight nobody arranged.
        --
        -- Tiers are numbers because the framework has no vocabulary for
        -- them. What "tier 3" means is entirely this file's business.
        patrolRoster = {
            'ash slave',
            'corprus stalker',
            { id = 'ash zombie', tier = 2 },
            { id = 'ash ghoul', tier = 3 },
        },
    },
    {
        -- Bloodmoon content, absent from the vanilla matrix, so this row
        -- is authored throughout.
        id = 'skaal',
        displayName = 'Skaal',
        basePower = 25,
        landmass = 'solstheim',
        reactions = {
            redoran = 1,
            telvanni = -1,
            temple = -1,
            ['imperial legion'] = -2,
            ashlanders = 1,
            -- The mining concession, and everything that comes with it.
            ['east empire company'] = -3,
            ['sixth house'] = -3,
            ['imperial cult'] = -1,
        },
    },

    ----------------------------------------------------------------------
    -- Power-only: the guilds
    ----------------------------------------------------------------------

    {
        id = 'fighters guild',
        displayName = 'Fighters Guild',
        territorial = false,
        basePower = 30,
        reactions = {
            hlaalu = 1,
            redoran = 1,
            temple = -1,
            ['imperial legion'] = 2,
            ashlanders = -2,
            ['sixth house'] = -3,
            ['mages guild'] = 1,
            ['imperial cult'] = 1,
            ['camonna tong'] = -1,
            ['clan aundae'] = -2,
            ['clan berne'] = -2,
            ['clan quarra'] = -2,
        },
    },
    {
        id = 'mages guild',
        displayName = 'Mages Guild',
        territorial = false,
        basePower = 30,
        reactions = {
            hlaalu = 1,
            redoran = -1,
            telvanni = -3,
            temple = -2,
            ['imperial legion'] = 1,
            ashlanders = -1,
            ['sixth house'] = -3,
            ['fighters guild'] = 1,
            ['thieves guild'] = 1,
            ['imperial cult'] = 1,
            ['camonna tong'] = -1,
            ['census and excise'] = -1,
            ['clan aundae'] = -1,
            ['clan berne'] = -1,
        },
    },
    {
        id = 'thieves guild',
        displayName = 'Thieves Guild',
        territorial = false,
        basePower = 25,
        reactions = {
            hlaalu = -1,
            redoran = -1,
            temple = -1,
            ['imperial legion'] = -1,
            ashlanders = -2,
            ['sixth house'] = -3,
            ['mages guild'] = 1,
            ['imperial cult'] = 1,
            -- The other genuine feud in the vanilla matrix, and the pair
            -- that ALL_FACTIONS_HOSTILE exists to let off the leash.
            ['camonna tong'] = -3,
            ['census and excise'] = -1,
            ['clan aundae'] = -1,
            ['clan berne'] = -1,
        },
    },

    ----------------------------------------------------------------------
    -- Power-only: the Imperial apparatus
    ----------------------------------------------------------------------

    {
        id = 'imperial cult',
        displayName = 'Imperial Cult',
        territorial = false,
        basePower = 30,
        reactions = {
            hlaalu = 1,
            telvanni = -1,
            temple = -2,
            ashlanders = -1,
            ['east empire company'] = 1,
            ['sixth house'] = -3,
            skaal = -1,
            ['fighters guild'] = 1,
            ['mages guild'] = 1,
            ['thieves guild'] = 1,
            ['camonna tong'] = -1,
            blades = 2,
            ['imperial knights'] = 2,
            ['clan aundae'] = -2,
            ['clan berne'] = -2,
            ['clan quarra'] = -2,
        },
    },
    {
        -- The Order of Ebonheart. Kept out of the merged Empire above
        -- because it holds no garrison of its own.
        id = 'imperial knights',
        displayName = 'Imperial Knights',
        territorial = false,
        basePower = 20,
        reactions = {
            hlaalu = 1,
            redoran = 1,
            telvanni = -1,
            temple = -2,
            ['imperial legion'] = 2,
            ashlanders = -2,
            ['sixth house'] = -3,
            ['fighters guild'] = 1,
            ['mages guild'] = 1,
            ['thieves guild'] = -1,
            ['imperial cult'] = 2,
            ['camonna tong'] = -1,
            blades = 2,
            ['clan aundae'] = -2,
            ['clan berne'] = -2,
            ['clan quarra'] = -2,
        },
    },
    {
        -- The Emperor's own, and thin on the ground by design.
        id = 'blades',
        displayName = 'Blades',
        territorial = false,
        basePower = 20,
        reactions = {
            temple = -1,
            ['imperial legion'] = 2,
            ashlanders = -1,
            ['sixth house'] = -3,
            ['imperial cult'] = 2,
            ['camonna tong'] = -2,
            ['clan aundae'] = -2,
            ['clan berne'] = -2,
            ['clan quarra'] = -2,
        },
    },
    {
        -- Customs. Three opinions in the whole matrix, all of them about
        -- people who bring things ashore without asking.
        id = 'census and excise',
        displayName = 'Census and Excise',
        territorial = false,
        basePower = 15,
        reactions = {
            ashlanders = -3,
            ['camonna tong'] = -1,
            blades = 2,
        },
    },

    ----------------------------------------------------------------------
    -- Power-only: the criminal orders
    ----------------------------------------------------------------------

    {
        id = 'camonna tong',
        displayName = 'Camonna Tong',
        territorial = false,
        basePower = 35,
        reactions = {
            hlaalu = 1,
            redoran = -1,
            temple = -1,
            ['imperial legion'] = -2,
            ashlanders = -1,
            -- Imperial commerce muscling in on Morrowind's own rackets.
            -- Authored.
            ['east empire company'] = -2,
            ['sixth house'] = -1,
            ['fighters guild'] = -1,
            ['mages guild'] = -1,
            ['thieves guild'] = -3,
            ['imperial cult'] = -1,
            blades = -2,
        },
    },
    {
        -- Legally sanctioned assassins with no politics whatsoever:
        -- vanilla's row and column are empty but for its regard for
        -- itself. Nothing moves it and it moves nothing, which is the
        -- data rather than an omission -- see the header.
        id = 'morag tong',
        displayName = 'Morag Tong',
        territorial = false,
        basePower = 20,
    },

    ----------------------------------------------------------------------
    -- Power-only: the cults and the clans
    ----------------------------------------------------------------------

    {
        -- Plot furniture with no political weight in the matrix at all,
        -- in either direction. Registered so the pack holds every vanilla
        -- faction, not because the simulation has anything to do with it.
        id = 'talos cult',
        displayName = 'Talos Cult',
        territorial = false,
        basePower = 10,
    },
    {
        -- The abolitionists. One opinion in the entire matrix, and the
        -- asymmetry the framework's reaction direction was settled
        -- against: they hate the slavers, and House Telvanni has never
        -- heard of them.
        id = 'twin lamps',
        displayName = 'Twin Lamps',
        territorial = false,
        basePower = 10,
        reactions = {
            telvanni = -3,
        },
    },
    {
        -- A prophecy, modelled as a faction because vanilla does. It
        -- reacts to nobody; Redoran and the Temple react to it, both well
        -- past the nominal range.
        id = 'nerevarine',
        displayName = 'Nerevarine',
        territorial = false,
        basePower = 5,
    },
    {
        -- The three vampire clans. Everyone loathes them, they loathe
        -- each other, and none of them is flagged `hostile` -- the
        -- framework starts no fights, and clans that ambush travellers
        -- are a spawn rule a content pack has yet to write.
        id = 'clan aundae',
        displayName = 'Clan Aundae',
        territorial = false,
        basePower = 12,
        reactions = {
            hlaalu = -2,
            redoran = -2,
            temple = -3,
            ['imperial legion'] = -2,
            ashlanders = -3,
            ['sixth house'] = -3,
            ['fighters guild'] = -2,
            ['mages guild'] = -1,
            ['thieves guild'] = -1,
            ['imperial cult'] = -2,
            blades = -2,
            ['imperial knights'] = -2,
            ['clan berne'] = -3,
            ['clan quarra'] = -3,
        },
    },
    {
        id = 'clan berne',
        displayName = 'Clan Berne',
        territorial = false,
        basePower = 12,
        reactions = {
            hlaalu = -2,
            redoran = -2,
            temple = -3,
            ['imperial legion'] = -2,
            ashlanders = -3,
            ['sixth house'] = -3,
            ['fighters guild'] = -2,
            ['mages guild'] = -1,
            ['thieves guild'] = -1,
            ['imperial cult'] = -2,
            blades = -2,
            ['imperial knights'] = -2,
            ['clan aundae'] = -3,
        },
    },
    {
        id = 'clan quarra',
        displayName = 'Clan Quarra',
        territorial = false,
        basePower = 12,
        reactions = {
            hlaalu = -2,
            redoran = -2,
            temple = -3,
            ['imperial legion'] = -2,
            ashlanders = -3,
            ['sixth house'] = -3,
            ['fighters guild'] = -2,
            ['mages guild'] = -1,
            ['thieves guild'] = -1,
            ['imperial cult'] = -2,
            blades = -2,
            ['imperial knights'] = -2,
            ['clan aundae'] = -3,
            ['clan berne'] = -3,
        },
    },
}
