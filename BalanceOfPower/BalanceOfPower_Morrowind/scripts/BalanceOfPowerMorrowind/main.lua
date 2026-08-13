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
--   3. The Sixth House is registered as an invasion, which also creates
--      it as a faction -- so its anchor, declared in step 1 with an
--      authored owner, only resolves now. That forward reference is
--      expected; the framework checks references after everything loads.
--   4. Frontier generation runs last, because it works outward from the
--      power centers registered in the steps above.

local I = require('openmw.interfaces')

local BoP = I.BalanceOfPower
if not BoP then
    error('BalanceOfPowerMorrowind: the BalanceOfPower framework interface is not '
        .. 'available. BalanceOfPower_Framework.omwscripts must load BEFORE this mod.', 0)
end

local build = require('scripts.BalanceOfPowerMorrowind.data.build')
local factionDefs = require('scripts.BalanceOfPowerMorrowind.data.factions')
local settlements = require('scripts.BalanceOfPowerMorrowind.data.settlements')
local sixthHouse = require('scripts.BalanceOfPowerMorrowind.data.invasions.sixth_house')

-- The cell size comes from the framework rather than from a constant
-- here. It is an engine fact, not a Morrowind one, and the settlement
-- centroids computed from it have to agree with the grid the frontier
-- generator lays down.
local plan = build.plan(settlements, BoP.CELL_SIZE)
local defined = {}

--------------------------------------------------------------------------
-- The invader's holdings
--------------------------------------------------------------------------

-- Dagoth Ur comes out of the settlement list like any other holding, but
-- its faction is created by registerInvasion rather than by a landmass,
-- so its power centers are lifted out here and handed to the invasion
-- instead. Leaving them in would define the faction twice.
local INVADER = sixthHouse.faction.id

local function claimInvaderCenters(landmassId)
    local centers = plan[landmassId] and plan[landmassId].centers
    if centers and centers[INVADER] then
        sixthHouse.faction.powerCenters = sixthHouse.faction.powerCenters or {}
        for _, centre in ipairs(centers[INVADER]) do
            table.insert(sixthHouse.faction.powerCenters, centre)
        end
        centers[INVADER] = nil
    end
end

claimInvaderCenters('vvardenfell')
claimInvaderCenters('solstheim')

-- The homeland is the one place on the map with an authored owner. An
-- authored owner overrides derived control, which is what keeps Red
-- Mountain in Sixth House hands regardless of who out-projects them.
for _, territory in ipairs(plan.vvardenfell.territories) do
    for _, homeId in ipairs(sixthHouse.faction.homeTerritories) do
        if territory.id == homeId then
            territory.defaultOwner = INVADER
        end
    end
end

--------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------

BoP.registerLandmass({
    id = 'vvardenfell',
    displayName = 'Vvardenfell',
    factions = build.factionsFor(factionDefs, plan.vvardenfell.centers, defined, 'vvardenfell'),
    territories = plan.vvardenfell.territories,
})

BoP.registerLandmass({
    id = 'solstheim',
    displayName = 'Solstheim',
    factions = build.factionsFor(factionDefs, plan.solstheim.centers, defined, 'solstheim'),
    territories = plan.solstheim.territories,
})

BoP.registerInvasion(sixthHouse)

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
