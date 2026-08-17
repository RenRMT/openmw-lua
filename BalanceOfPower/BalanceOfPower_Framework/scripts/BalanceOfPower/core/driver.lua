-- The clock: turns elapsed game time into resolution passes.
--
-- Split out from main.lua so that "when does the world resolve" is a
-- separate question from "how does it resolve".
-- It's also the only place that can run a day on demand, which is what
-- makes the simulation testable without sleeping through in-game days.
--
-- GLOBAL context only.

local core = require('openmw.core')
local time = require('openmw_aux.time')

local config = require('scripts.BalanceOfPower.core.config')
local events = require('scripts.BalanceOfPower.core.events')
local holdings = require('scripts.BalanceOfPower.core.holdings')
local log = require('scripts.BalanceOfPower.core.log')
local power = require('scripts.BalanceOfPower.core.power')
local registry = require('scripts.BalanceOfPower.core.registry')
local resolve = require('scripts.BalanceOfPower.core.resolve')
local state = require('scripts.BalanceOfPower.core.state')

local M = {}

-- Packs register any time between load and the first tick, so anything
-- needing the whole world waits for the first poll: reference checking,
-- and seeding starting power from every faction's holdings.
local sealed = false

--- The in-game calendar day, as an integer index.
function M.currentDay()
    return math.floor(core.getGameTime() / time.day)
end

--- One in-game day of simulation.
--
-- Everything inside the batch reads a frozen snapshot of faction power
-- and queues its changes, so no roll can be influenced by another roll
-- that happened to resolve earlier in the same day.
function M.runDay(day)
    -- Before the batch opens, so today's rolls resolve against today's
    -- power rather than yesterday's. Growth is an input to the day, not
    -- a result of it -- the same category as an award arriving from a
    -- quest, and the opposite of everything inside the batch.
    power.applyDailyGrowth()

    power.beginBatch()

    -- The whole world in one pass, which is what the MVP wants. Passing
    -- an explicit batch here instead is how staggering across smaller
    -- timers happens later, without resolve itself changing.
    resolve.run(day)

    power.commitBatch()

    -- After the commit, so a listener that reads power back sees settled
    -- numbers. This is the scheduling hook every extension runs from.
    events.emit(events.DAY_RESOLVED, { day = day })

    if config.DEBUG_DAILY_SUMMARY and registry.countFactions() > 0 then
        log.info('day %d | %s', day, power.summary())
    end
end

--- Poll for day rollover.
--
-- game time jumps whenever the player sleeps, waits or fast travels,
-- a period timer either drifts against midnight or swallows the jump entirely.
-- Comparing day indices instead anchors the tick to the game calendar,
-- and a jump is caught as however many days it actually was.
function M.poll()
    -- Cheap and idempotent, so it runs every tick rather than requiring
    -- the framework to know whether a pack registered late. Engine load
    -- order between script bodies and onInit/onLoad handlers decides
    -- whether registration lands before or after the framework's own
    -- handlers, and this makes that difference not matter.
    state.fillDefaults(registry)

    -- The only point at which every pack is known to have registered.
    -- Starting power is measured against the whole world's holdings, so
    -- it can only be seeded here.
    if not sealed then
        sealed = true
        holdings.seedPower()
        registry.validateReferences()
    end

    local data = state.get()
    local today = M.currentDay()

    if data.lastResolvedDay == nil then
        -- First tick of a new game, or of a save made before this
        -- framework was installed: establish a baseline instead of
        -- resolving every day since the calendar epoch, and let the
        -- factions claim the ground they project onto before any
        -- contest starts.
        data.lastResolvedDay = today
        resolve.assignInitialControl()
        log.debug('baseline day set to %d', today)
        return
    end

    local missed = today - data.lastResolvedDay
    if missed <= 0 then
        -- Also the case after forceDays() has run the simulation ahead
        -- of the calendar: nothing happens until real time catches up.
        return
    end

    if missed > config.MAX_CATCHUP_DAYS then
        log.debug('%d days elapsed, resolving the most recent %d', missed, config.MAX_CATCHUP_DAYS)
        missed = config.MAX_CATCHUP_DAYS
    end

    for _ = 1, missed do
        data.lastResolvedDay = data.lastResolvedDay + 1
        M.runDay(data.lastResolvedDay)
    end

    -- If the catch-up was capped, skip the remainder outright rather
    -- than leaving the simulation permanently behind the calendar.
    data.lastResolvedDay = today
end

--- Resolve days immediately, ignoring the calendar. For testing.
--
-- This runs the simulation *ahead* of game time, so the scheduled poll
-- then does nothing until the calendar catches up. That's the intended
-- behaviour -- it means a forced day is a real day, not an extra one.
-- @return number the new last-resolved day
function M.forceDays(count)
    count = math.max(1, math.floor(tonumber(count) or 1))
    local data = state.get()

    -- Running the simulation on demand means sealing the world early, the
    -- same as the first poll would.
    state.fillDefaults(registry)
    holdings.seedPower()
    if data.lastResolvedDay == nil then
        data.lastResolvedDay = M.currentDay()
    end

    for _ = 1, count do
        data.lastResolvedDay = data.lastResolvedDay + 1
        M.runDay(data.lastResolvedDay)
    end

    log.info('forced %d day(s); simulation is now at day %d (calendar is at %d)',
        count, data.lastResolvedDay, M.currentDay())
    return data.lastResolvedDay
end

--- Called on load, so the first-tick work runs again for the new session.
function M.reset()
    sealed = false
end

--- Start the scheduled tick. Called once per session from main.lua.
-- `time.hour`/`time.day`, the `type = time.GameTime` option and
-- `core.getGameTime()` returning in-game seconds were all checked
-- against the openmw_aux.time and openmw.core docs during development.
function M.start()
    time.runRepeatedly(M.poll, config.TICK_POLL_HOURS * time.hour, { type = time.GameTime })
end

return M
