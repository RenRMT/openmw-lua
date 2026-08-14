-- Balance of Power -- Morrowind content pack.
--
-- Registers Vvardenfell and Solstheim against the framework, then asks it
-- to derive the wilderness between the settlements. Nothing here is
-- behaviour: it is data, plus the four API calls that hand the data over.
--
-- Order matters, and each step depends on the one before:
--
--   1. Vvardenfell defines every faction that appears on it.
--   2. Solstheim extends the ones it shares (the Empire garrisons Fort
--      Frostmoth as well as half of Vvardenfell) and defines its own.
--   3. Frontier generation runs last, because it works outward from the
--      settlements registered in the steps above.
--
-- There is no authored ownership anywhere in this pack. The whole map,
-- including Red Mountain, falls out of where the seats of power are.

local I = require('openmw.interfaces')

local BoP = I.BalanceOfPower
if not BoP then
    error('BalanceOfPowerMorrowind: the BalanceOfPower framework interface is not '
        .. 'available. BalanceOfPower_Framework.omwscripts must load BEFORE this mod.', 0)
end

local build = require('scripts.BalanceOfPowerMorrowind.data.build')
local factionDefs = require('scripts.BalanceOfPowerMorrowind.data.factions')
local settlements = require('scripts.BalanceOfPowerMorrowind.data.settlements')

local plan = build.plan(settlements)
local defined = {}

--------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------

BoP.registerLandmass({
    id = 'vvardenfell',
    displayName = 'Vvardenfell',
    factions = build.factionsFor(factionDefs, build.holdersIn(plan.vvardenfell), defined, 'vvardenfell'),
    territories = plan.vvardenfell.territories,
})

BoP.registerLandmass({
    id = 'solstheim',
    displayName = 'Solstheim',
    factions = build.factionsFor(factionDefs, build.holdersIn(plan.solstheim), defined, 'solstheim'),
    territories = plan.solstheim.territories,
})

--------------------------------------------------------------------------
-- Derived frontier
--------------------------------------------------------------------------

-- Only ground within reach of a settlement becomes territory, so these
-- calls produce a map shaped like the inhabited world rather than a
-- rectangle full of ocean. Granularity is the framework's default of one
-- territory per exterior cell; override cellsPerUnit here if the daily
-- pass ever needs to be cheaper.
BoP.generateFrontier({ landmass = 'vvardenfell' })
BoP.generateFrontier({ landmass = 'solstheim' })
