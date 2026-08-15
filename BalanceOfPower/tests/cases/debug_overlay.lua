-- The debug overlay, loaded over real content.
--
-- Only the global half is exercised here; the player half needs
-- openmw.input and openmw.self, which aren't stubbed. That half is
-- input-only anyway -- all output lives here.
--
-- Deliberately thin. Nothing in this mod can break the simulation, so
-- what is tested is the handful of properties that are architecture
-- rather than formatting: that it registers no content, that it survives
-- having none, that it draws nothing over the HUD, that it names no
-- faction of its own, and that a bad pack doesn't take the framework
-- down with it. Log wording is not pinned.

local expect = require('support.expect')
local vanillaReactions = require('fixtures.vanilla_reactions')

local core = require('openmw.core')
local world = require('openmw.world')

local holdings = require('scripts.BalanceOfPower.core.holdings')
local power = require('scripts.BalanceOfPower.core.power')
local registry = require('scripts.BalanceOfPower.core.registry')
local resolve = require('scripts.BalanceOfPower.core.resolve')
local state = require('scripts.BalanceOfPower.core.state')

local M = {}

local captured = {}

--- Load the overlay and capture what it prints.
local function overlayWithCapture()
    local overlay = require('scripts.BoPDebug.global')
    captured = {}
    overlay.setOutput(function(line)
        captured[#captured + 1] = line
    end)
    return overlay.eventHandlers
end

--- Load real content, then the overlay on top of it.
local function loadWithOverlay()
    world._test.defineExteriorGrid(-22, 22, -18, 36)
    core._test.setFactionRecords(vanillaReactions)
    require('scripts.BalanceOfPowerMorrowind.main')
    state.fillDefaults(registry)
    holdings.seedPower()
    resolve.assignInitialControl()
    return overlayWithCapture()
end

local function output()
    return table.concat(captured, '\n')
end

local function says(fragment, what)
    expect.truthy(string.find(output(), fragment, 1, true),
        what or ('output mentions ' .. fragment))
end

--------------------------------------------------------------------------
-- It is an overlay, not content
--------------------------------------------------------------------------

--- The whole point of the rewrite. If the overlay ever registers
-- anything again it stops composing with content packs and starts
-- fighting them for faction ids.
function M.registersNothing()
    world._test.defineExteriorGrid(-22, 22, -18, 36)
    core._test.setFactionRecords(vanillaReactions)
    require('scripts.BalanceOfPowerMorrowind.main')
    state.fillDefaults(registry)
    holdings.seedPower()

    local factions = registry.countFactions()
    local settlements = #registry.settlementIds
    local frontier = #registry.frontierIds
    local generation = registry.generation

    require('scripts.BoPDebug.global')

    expect.equal(registry.countFactions(), factions, 'faction count unchanged')
    expect.equal(#registry.settlementIds, settlements, 'settlement count unchanged')
    expect.equal(#registry.frontierIds, frontier, 'frontier count unchanged')
    expect.equal(registry.generation, generation, 'nothing was registered at all')
end

--- Loading it with the framework but no content pack must not error --
-- that's a perfectly reasonable way to run it.
function M.loadsWithoutAnyContent()
    local handlers = overlayWithCapture()
    handlers.BoPDebug_Dump()
    says('no factions registered', 'says so rather than erroring')
end

--------------------------------------------------------------------------
-- Everything goes to the log
--------------------------------------------------------------------------

--- Nothing is drawn over the HUD. A fifty-row map never fitted in a
-- message box, and OpenMW's own log viewer scrolls back.
function M.sendsNothingToTheScreen()
    local handlers = loadWithOverlay()
    world._test.reset()

    handlers.BoPDebug_Dump()
    handlers.BoPDebug_Here({ cell = '#-3,-2' })
    handlers.BoPDebug_Boost({ cell = '#-3,-2', target = 'owner', amount = 50 })

    expect.count(world._test.eventsNamed('BoPDebug_Report'), 0, 'no message-box events')
    expect.greater(#captured, 0, 'but it did produce output')
end

--------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------

--- Standings are how everything else is read back, and the display name
-- coming from the record rather than the pack is a framework property
-- worth one smoke test through the shipping path.
function M.dumpReportsStandings()
    local handlers = loadWithOverlay()
    handlers.BoPDebug_Dump()

    says('Great House Hlaalu', 'names a faction, from the record')
    says('holds no land', 'separates power-only factions')
end

--- Naming no faction is what lets the overlay work against content it
-- knows nothing about: it pushes whoever holds the ground under you.
function M.boostPushesWhoeverHoldsTheGroundYouAreOn()
    local handlers = loadWithOverlay()

    local owner = state.getOwner(registry.territoryForCell('#-3,-2').id)
    expect.truthy(owner, 'Balmora is held by somebody')
    local before = power.getLive(owner)

    handlers.BoPDebug_Boost({ cell = '#-3,-2', target = 'owner', amount = 50 })

    expect.greater(power.getLive(owner), before, 'the holder was pushed')
end

--------------------------------------------------------------------------
-- Position
--------------------------------------------------------------------------

--- One line per cell entered. Walking across Vvardenfell would otherwise
-- bury the log in full reports.
function M.enteringACellPrintsOneLine()
    local handlers = loadWithOverlay()
    captured = {}

    handlers.BoPDebug_Entered({ cell = '#-3,-2' })

    expect.count(captured, 1, 'exactly one line')
    says('Balmora', 'names the territory')
end

--------------------------------------------------------------------------
-- Feed and self-test
--------------------------------------------------------------------------

--- Power propagates to every faction with an opinion, so one award is
-- several events. Off by default, or the log is unreadable.
function M.eventFeedIsOffUntilToggled()
    local handlers = loadWithOverlay()
    captured = {}

    handlers.BoP_PowerChanged({ faction = 'hlaalu', delta = 5, newTotal = 60 })
    expect.count(captured, 0, 'silent by default')

    handlers.BoPDebug_ToggleFeed()
    captured = {}
    handlers.BoP_PowerChanged({ faction = 'hlaalu', delta = 5, newTotal = 60 })
    expect.count(captured, 1, 'reported once toggled on')
end

--- The self-test must pick its victim from whatever is registered rather
-- than naming one, and must leave the registry intact afterwards.
function M.selfTestRejectsDuplicateRegistrationWithoutBreakingAnything()
    local handlers = loadWithOverlay()
    local factions = registry.countFactions()

    handlers.BoPDebug_SelfTest()

    says('rejected as expected', 'was rejected')
    expect.falsy(string.find(output(), 'FAIL', 1, true), 'not reported as a failure')
    expect.equal(registry.countFactions(), factions, 'registry intact afterwards')
    expect.isNil(registry.landmasses.bopdebug_should_not_exist, 'nothing half-registered')
end

return M
