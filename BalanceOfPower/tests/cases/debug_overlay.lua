-- The debug overlay, loaded over real content.
--
-- Only the global half is exercised here; the player half needs
-- openmw.input, openmw.self and openmw.ui, which aren't stubbed. What
-- matters most is testable either way: that the overlay adds nothing to
-- the world, and that its commands work without naming a faction.

local expect = require('support.expect')

local world = require('openmw.world')

local power = require('scripts.BalanceOfPower.core.power')
local registry = require('scripts.BalanceOfPower.core.registry')
local resolve = require('scripts.BalanceOfPower.core.resolve')
local state = require('scripts.BalanceOfPower.core.state')

local M = {}

--- Load real content, then the overlay on top of it, and hand back the
-- overlay's event handlers.
local function loadWithOverlay()
    world._test.defineExteriorGrid(-22, 22, -18, 36)
    require('scripts.BalanceOfPowerMorrowind.main')
    state.fillDefaults(registry)
    resolve.assignInitialControl()

    local overlay = require('scripts.BoPDebug.global')
    return overlay.eventHandlers
end

local function lastReport()
    local reports = world._test.eventsNamed('BoPDebug_Report')
    expect.greater(#reports, 0, 'the overlay reported something')
    return reports[#reports].text
end

--------------------------------------------------------------------------
-- It is an overlay, not content
--------------------------------------------------------------------------

--- The whole point of the rewrite. If the overlay ever registers
-- anything again it stops composing with content packs and starts
-- fighting them for faction ids.
function M.registersNothing()
    world._test.defineExteriorGrid(-22, 22, -18, 36)
    require('scripts.BalanceOfPowerMorrowind.main')
    state.fillDefaults(registry)

    local factions = registry.countFactions()
    local anchors = #registry.anchorIds
    local frontier = #registry.frontierIds
    local landmasses = registry.generation

    require('scripts.BoPDebug.global')

    expect.equal(registry.countFactions(), factions, 'faction count unchanged')
    expect.equal(#registry.anchorIds, anchors, 'anchor count unchanged')
    expect.equal(#registry.frontierIds, frontier, 'frontier count unchanged')
    expect.equal(registry.generation, landmasses, 'nothing was registered at all')
end

--- Loading it with the framework but no content pack must not error --
-- that's a perfectly reasonable way to run it.
function M.loadsWithoutAnyContent()
    local overlay = require('scripts.BoPDebug.global')
    overlay.eventHandlers.BoPDebug_Dump()
    expect.truthy(string.find(lastReport(), 'No factions registered', 1, true),
        'says so rather than erroring')
end

--------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------

function M.dumpReportsStandings()
    local handlers = loadWithOverlay()
    handlers.BoPDebug_Dump()

    local text = lastReport()
    expect.truthy(string.find(text, 'House Hlaalu', 1, true), 'names a faction')
    expect.truthy(string.find(text, 'no land', 1, true), 'separates power-only factions')
end

--- Targeting by standing position is what lets the overlay work against
-- content it knows nothing about.
function M.boostPushesWhoeverHoldsTheGroundYouAreOn()
    local handlers = loadWithOverlay()

    local owner = state.getOwner('balmora')
    expect.truthy(owner, 'Balmora is held by somebody')
    local before = power.getLive(owner)

    handlers.BoPDebug_Boost({ cell = '#-3,-2', target = 'owner', amount = 50 })

    expect.greater(power.getLive(owner), before, 'the holder was pushed')
end

function M.boostCanWeaken()
    local handlers = loadWithOverlay()

    local owner = state.getOwner('balmora')
    local before = power.getLive(owner)
    handlers.BoPDebug_Boost({ cell = '#-3,-2', target = 'owner', amount = -50 })

    expect.greater(before, power.getLive(owner), 'the holder was weakened')
end

--- Pushing the challenger is what actually moves a front, so it has to
-- find one -- and say so plainly when there isn't one.
function M.boostReportsWhenThereIsNoChallenger()
    local handlers = loadWithOverlay()

    -- A faction's own seat: it holds the ground and projects strongest.
    handlers.BoPDebug_Boost({ cell = '#-3,-2', target = 'challenger', amount = 50 })
    expect.truthy(string.find(lastReport(), 'No challenger', 1, true), 'says so')
end

function M.boostReportsWhenNotStandingInTerritory()
    local handlers = loadWithOverlay()

    handlers.BoPDebug_Boost({ cell = '#999,999', target = 'owner', amount = 50 })
    expect.truthy(string.find(lastReport(), 'Not standing in any registered territory',
        1, true), 'says so')
end

function M.whereAmIDescribesTheGround()
    local handlers = loadWithOverlay()
    handlers.BoPDebug_WhereAmI({ cell = '#-3,-2' })

    local text = lastReport()
    expect.truthy(string.find(text, 'Balmora', 1, true), 'names the territory')
    expect.truthy(string.find(text, 'projection', 1, true), 'shows who reaches it')
end

function M.forceDayAdvancesTheSimulation()
    local handlers = loadWithOverlay()
    local before = state.get().lastResolvedDay or 0

    handlers.BoPDebug_ForceDay({ count = 3 })

    expect.greater(state.get().lastResolvedDay, before, 'days were resolved')
end

--- The self-test must pick its victim from whatever is registered rather
-- than naming one, and must leave the registry intact afterwards.
function M.selfTestRejectsDuplicateRegistrationWithoutBreakingAnything()
    local handlers = loadWithOverlay()
    local factions = registry.countFactions()

    handlers.BoPDebug_SelfTest()

    local text = lastReport()
    expect.truthy(string.find(text, 'Rejected as expected', 1, true), 'was rejected')
    expect.falsy(string.find(text, 'FAIL', 1, true), 'not reported as a failure')
    expect.equal(registry.countFactions(), factions, 'registry intact afterwards')
    expect.isNil(registry.landmasses.bopdebug_should_not_exist, 'nothing half-registered')
end

function M.mapDrawsAndSummarises()
    local handlers = loadWithOverlay()
    handlers.BoPDebug_Map({ mode = 'contest' })

    local text = lastReport()
    expect.truthy(string.find(text, 'contest', 1, true), 'names the mode')
    expect.truthy(string.find(text, 'contested', 1, true), 'summarises the classification')
end

return M
