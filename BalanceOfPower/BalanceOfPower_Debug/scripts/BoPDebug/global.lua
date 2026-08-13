-- Balance of Power -- debug overlay, global half.
--
-- Registers nothing. No factions, no territory, no simulation: it reads
-- whatever content is loaded and drives it. That means it can sit on top
-- of the Morrowind pack, or any other content pack, or a pack somebody
-- else wrote, without competing with it for faction ids.
--
-- It also means everything here has to be written without naming a
-- single faction. The power commands work that out from where the player
-- is standing instead: boost whoever holds this ground, or boost
-- whoever is about to take it. That turns out to be more useful than
-- naming factions anyway -- stand on a border, push one side, watch it
-- move.
--
-- If this file ever needs to know that "hlaalu" exists, something has
-- gone wrong.
--
-- All output goes to openmw.log, which OpenMW's own log viewer (F11)
-- displays in-game. Nothing is drawn over the HUD: a map is fifty rows
-- and a message box is not, and anything worth reading twice is worth
-- having somewhere it can be scrolled back through.

local I = require('openmw.interfaces')

local BoP = I.BalanceOfPower
if not BoP then
    error('BoPDebug: the BalanceOfPower framework interface is not available. '
        .. 'Check that BalanceOfPower_Framework.omwscripts loads BEFORE this mod.', 0)
end

--------------------------------------------------------------------------
-- Output
--------------------------------------------------------------------------

-- Short, so it costs little width on a map row, and greppable, so this
-- mod's output can be pulled out of a log shared with everything else.
local TAG = '[BoP]'
local RULE = string.rep('-', 64)

local function defaultEmit(line)
    -- Blank lines carry the tag but nothing after it, so a separator
    -- doesn't leave trailing whitespace in the log.
    if line == '' then
        print(TAG)
    else
        print(TAG .. ' ' .. line)
    end
end

local emit = defaultEmit

--- Redirect output. Tests use this; so could anything that wants the
-- debug output somewhere other than the log.
local function setOutput(fn)
    emit = fn or defaultEmit
end

local function out(fmt, ...)
    if select('#', ...) > 0 then
        emit(string.format(fmt, ...))
    else
        emit(fmt)
    end
end

local function blank()
    emit('')
end

--- A titled block, so consecutive commands don't run together in a log
-- that also has the framework's own output in it.
local function heading(fmt, ...)
    blank()
    emit(RULE)
    out(fmt, ...)
    emit(RULE)
end

local function nameOf(factionId)
    local faction = factionId and BoP.getFaction(factionId)
    return faction and faction.displayName or tostring(factionId)
end

local function dayLabel()
    local day = BoP.getCurrentDay()
    return day and ('day ' .. day) or 'not yet ticked'
end

--------------------------------------------------------------------------
-- Standings
--------------------------------------------------------------------------

--- Power and holdings per faction, in aligned columns. Land-holding
-- factions first, since the map is about them; the power-only factions
-- follow in their own group rather than mixed in with a blank column.
local function printStandings()
    local ids = BoP.factionIds()
    if #ids == 0 then
        out('no factions registered -- is a content pack loaded?')
        return
    end

    -- One pass over the map rather than one per faction.
    local held = {}
    for _, territoryId in ipairs(BoP.territoryIds()) do
        local owner = BoP.getOwner(territoryId)
        if owner then
            held[owner] = (held[owner] or 0) + 1
        end
    end

    local landed, powerOnly = {}, {}
    for _, id in ipairs(ids) do
        local faction = BoP.getFaction(id)
        local bucket = faction.territorial and landed or powerOnly
        bucket[#bucket + 1] = { faction = faction, id = id }
    end

    -- Strongest first: what you want to see when checking whether a push
    -- landed is the ordering, not the alphabet.
    local function byPower(a, b)
        return BoP.getPower(a.id) > BoP.getPower(b.id)
    end
    table.sort(landed, byPower)
    table.sort(powerOnly, byPower)

    out('  %-26s %8s %7s', 'faction', 'power', 'held')
    for _, entry in ipairs(landed) do
        out('  %-26s %8.1f %7d',
            entry.faction.displayName, BoP.getPower(entry.id), held[entry.id] or 0)
    end

    if #powerOnly > 0 then
        out('  -- holds no land --')
        for _, entry in ipairs(powerOnly) do
            out('  %-26s %8.1f %7s',
                entry.faction.displayName, BoP.getPower(entry.id), '-')
        end
    end
end

--------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------

local handlers = {}

function handlers.BoPDebug_Dump()
    heading('STANDINGS -- %s', dayLabel())

    local settlements = BoP.territoryIds('settlement')
    local frontier = BoP.territoryIds('frontier')
    local contested = 0
    for _, territoryId in ipairs(BoP.territoryIds()) do
        if BoP.classify(territoryId) == 'contested' then
            contested = contested + 1
        end
    end

    out('  %d settlements, %d frontier cells, %d contested', #settlements, #frontier, contested)
    blank()
    printStandings()
end

--- Both scales of the map. The window is what you read while standing
-- somewhere; the full draw is what you read when the question is about
-- the whole island.
function handlers.BoPDebug_Map(data)
    local mode = data.mode or 'owner'

    if data.cell then
        heading('MAP around %s (%s) -- %s', data.cell, mode, dayLabel())
        for _, line in ipairs(BoP.renderMap({ mode = mode, centreCell = data.cell })) do
            emit(line)
        end
    end

    heading('MAP full (%s) -- %s', mode, dayLabel())
    BoP.dumpMap({ mode = mode })
end

function handlers.BoPDebug_ForceDay(data)
    local count = data.count or 1
    local day = BoP.forceDay(count)

    heading('RAN %d DAY(S) -- now day %d', count, day)
    printStandings()
end

--- Push whoever holds the ground under the player, or whoever is about to
-- take it. Naming no factions is what lets this work against any content
-- pack -- and standing on a border and pushing one side is the fastest
-- way to see the resolution loop actually do something.
function handlers.BoPDebug_Boost(data)
    local territory = BoP.getTerritoryForCell(data.cell or '')
    if not territory then
        heading('BOOST -- not standing in any registered territory')
        return
    end

    local target
    if data.target == 'challenger' then
        -- The strongest projector, unless that's already the owner, in
        -- which case there is nobody challenging for this ground.
        local claimant = BoP.getProjection(territory.id)
        local owner = BoP.getOwner(territory.id)
        if not claimant or claimant == owner then
            heading('BOOST -- no challenger at %s', territory.displayName)
            out('  %s both holds it and projects strongest here.', nameOf(owner))
            return
        end
        target = claimant
    else
        target = BoP.getOwner(territory.id)
        if not target then
            heading('BOOST -- %s is unclaimed, nobody to push', territory.displayName)
            return
        end
    end

    local before = BoP.getPower(target)
    BoP.awardPower(target, data.amount)

    heading('BOOST %s %+.0f at %s', nameOf(target), data.amount, territory.displayName)
    out('  power    %.1f -> %.1f', before, BoP.getPower(target))
    -- Whether the *local* picture changed is the interesting part, not
    -- the raw number.
    out('  holds    %s', nameOf(BoP.getOwner(territory.id)))
    out('  will hold %s', nameOf(BoP.getProjection(territory.id)))
end

--------------------------------------------------------------------------
-- Position
--------------------------------------------------------------------------

--- A single line, printed on every cell change. Walking across
-- Vvardenfell would otherwise bury the log in full reports.
function handlers.BoPDebug_Entered(data)
    local territory = BoP.getTerritoryForCell(data.cell)
    if not territory then
        out('%-12s (no registered territory)', data.cell)
        return
    end

    local owner = BoP.getOwner(territory.id)
    local claimant = BoP.getProjection(territory.id)
    local contested = ''
    if claimant and claimant ~= owner then
        contested = string.format('  <- %s closing in', nameOf(claimant))
    end

    out('%-12s %-24s %-20s %s%s', data.cell, territory.displayName,
        owner and nameOf(owner) or 'unclaimed',
        BoP.classify(territory.id), contested)
end

--- The full report, on demand.
function handlers.BoPDebug_Here(data)
    local territory = BoP.getTerritoryForCell(data.cell or '')
    if not territory then
        heading('HERE -- %s is not registered territory', tostring(data.cell))
        return
    end

    local owner = BoP.getOwner(territory.id)
    local claimant = BoP.getProjection(territory.id)

    heading('HERE -- %s', territory.displayName)
    out('  cell      %s', data.cell)
    out('  kind      %s', territory.kind == 'settlement' and territory.tier or 'frontier')
    out('  region    %s', territory.region or '-')
    out('  owner     %s', owner and nameOf(owner) or 'unclaimed')
    out('  state     %s', BoP.classify(territory.id))
    if claimant and claimant ~= owner then
        out('  closing   %s', nameOf(claimant))
    end
    if BoP.isSurrounded(territory.id) then
        out('  surrounded since day %s', tostring(BoP.surroundedSince(territory.id)))
    end

    -- Every faction that reaches here, strongest first. This is the
    -- number that decides ownership, so it's what to read when the map
    -- isn't doing what you expected.
    local rows = {}
    for _, id in ipairs(BoP.getReach(territory.id).ids) do
        rows[#rows + 1] = { id = id, value = BoP.getEffectivePower(id, territory.id) }
    end
    table.sort(rows, function(a, b) return a.value > b.value end)

    blank()
    out('  projection')
    if #rows == 0 then
        out('    (nobody reaches here)')
    end
    for _, row in ipairs(rows) do
        out('    %-26s %7.1f', nameOf(row.id), row.value)
    end
end

--------------------------------------------------------------------------
-- Event feed
--------------------------------------------------------------------------

-- Loud by design -- power propagates to every faction with an opinion,
-- so one award is several events -- so it starts off.
local watching = false

function handlers.BoPDebug_ToggleFeed()
    watching = not watching
    out('event feed %s', watching and 'ON' or 'OFF')
end

-- The framework broadcasts to global scripts as well as to players, so
-- these arrive here with no subscription step.

function handlers.BoP_PowerChanged(data)
    if watching then
        out('  power   %-26s %+7.2f -> %.1f', nameOf(data.faction), data.delta, data.newTotal)
    end
end

function handlers.BoP_DayResolved(data)
    if watching then
        out('  day     %s resolved', tostring(data.day))
    end
end

-- Always worth knowing about, feed or no feed.
function handlers.BoP_TerritoryFlipped(data)
    out('FLIP    %s: %s -> %s', data.territory, tostring(data.from), tostring(data.to))
end

function handlers.BoP_SettlementSurrounded(data)
    out('RINGED  %s (day %s)', data.territory, tostring(data.day))
end

function handlers.BoP_SettlementRelieved(data)
    out('RELIEF  %s (day %s)', data.territory, tostring(data.day))
end

--------------------------------------------------------------------------
-- Self-test
--------------------------------------------------------------------------

--- Deliberately bad registration, to confirm validation rejects it and
-- that a failed pack doesn't take the framework down with it. Uses
-- whichever faction happens to be registered first, so it works against
-- any content.
function handlers.BoPDebug_SelfTest()
    heading('SELF-TEST -- duplicate registration')

    local ids = BoP.factionIds()
    if #ids == 0 then
        out('  no factions registered -- nothing to test against.')
        return
    end

    local victim = ids[1]
    local ok, err = pcall(function()
        BoP.registerLandmass({
            id = 'bopdebug_should_not_exist',
            factions = { { id = victim } },   -- already registered, no extend
        })
    end)

    if ok then
        out('  FAIL: a duplicate registration of "%s" was accepted.', victim)
        return
    end

    out('  rejected as expected:')
    out('  %s', tostring(err))
    blank()
    out('  framework still live:')
    printStandings()
end

--------------------------------------------------------------------------

heading('DEBUG OVERLAY LOADED')
out('  Ctrl+1 map (Shift: next mode)   Ctrl+2 standings')
out('  Ctrl+3 run a day (Shift: 7)     Ctrl+4 push holder')
out('  Ctrl+5 push challenger          Ctrl+6 event feed')
out('  Ctrl+7 self-test                Ctrl+8 report here')
out('  Shift reverses 4 and 5. Output goes here; F11 opens this viewer.')

return {
    setOutput = setOutput,
    eventHandlers = handlers,
}
