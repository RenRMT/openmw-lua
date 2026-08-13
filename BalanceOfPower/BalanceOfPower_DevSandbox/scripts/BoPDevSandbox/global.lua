-- Balance of Power -- debug overlay, global half.
--
-- Registers nothing. No factions, no territory, no invasion: it reads
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

local world = require('openmw.world')
local I = require('openmw.interfaces')

local BoP = I.BalanceOfPower
if not BoP then
    error('BoPDevSandbox: the BalanceOfPower framework interface is not available. '
        .. 'Check that BalanceOfPower_Framework.omwscripts loads BEFORE this mod.', 0)
end

--------------------------------------------------------------------------
-- Reporting
--------------------------------------------------------------------------

local function report(text)
    for _, player in ipairs(world.players) do
        player:sendEvent('BoPDev_Report', { text = text })
    end
end

local function nameOf(factionId)
    local faction = factionId and BoP.getFaction(factionId)
    return faction and faction.displayName or tostring(factionId)
end

--- Standings, plus how much ground each faction holds. Land-holding
-- factions first, since they're the ones the map is about.
local function standings()
    local ids = BoP.factionIds()
    if #ids == 0 then
        return 'No factions registered -- is a content pack loaded?'
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
        if faction.territorial then
            landed[#landed + 1] = string.format('%s %.0f (%d)',
                faction.displayName, BoP.getPower(id), held[id] or 0)
        else
            powerOnly[#powerOnly + 1] = string.format('%s %.0f',
                faction.displayName, BoP.getPower(id))
        end
    end

    local text = table.concat(landed, '\n')
    if #powerOnly > 0 then
        text = text .. '\n-- no land --\n' .. table.concat(powerOnly, '\n')
    end
    return text
end

--------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------

local handlers = {}

function handlers.BoPDev_Dump()
    BoP.dump()
    report(string.format('Day %s\n%s\n(full detail in openmw.log)',
        tostring(BoP.getCurrentDay()), standings()))
end

--- The text map goes to the log, since it's far too wide for a message
-- box. On screen, just enough to know it worked and what it was drawn as.
function handlers.BoPDev_Map(data)
    local mode = data.mode or 'owner'
    BoP.dumpMap({ mode = mode })

    local counts = { empty = 0, consolidated = 0, contested = 0 }
    for _, territoryId in ipairs(BoP.territoryIds()) do
        local class = BoP.classify(territoryId)
        counts[class] = (counts[class] or 0) + 1
    end

    report(string.format('Map drawn to openmw.log (mode: %s)\n%d contested, '
        .. '%d consolidated, %d unreachable',
        mode, counts.contested, counts.consolidated, counts.empty))
end

function handlers.BoPDev_ForceDay(data)
    local count = data.count or 1
    local day = BoP.forceDay(count)
    report(string.format('Ran %d day(s), now day %d\n\n%s', count, day, standings()))
end

--- Push whoever holds the ground under the player, or whoever is about to
-- take it. Naming no factions is what lets this work against any content
-- pack -- and standing on a border and pushing one side is the fastest
-- way to see the resolution loop actually do something.
function handlers.BoPDev_Boost(data)
    local territory = BoP.getTerritoryForCell(data.cell or '')
    if not territory then
        report('Not standing in any registered territory.')
        return
    end

    local target
    if data.target == 'challenger' then
        -- The strongest projector, unless that's already the owner, in
        -- which case there is nobody challenging for this ground.
        local claimant = BoP.getProjection(territory.id)
        local owner = BoP.getOwner(territory.id)
        if claimant and claimant ~= owner then
            target = claimant
        else
            report(string.format('%s\nNo challenger here -- %s both holds it and '
                .. 'projects strongest.', territory.displayName, nameOf(owner)))
            return
        end
    else
        target = BoP.getOwner(territory.id)
        if not target then
            report(string.format('%s is unclaimed -- nobody to push.', territory.displayName))
            return
        end
    end

    local before = BoP.getPower(target)
    BoP.awardPower(target, data.amount)

    -- Whether the *local* picture changed is the interesting part, not
    -- the raw number.
    local claimant = BoP.getProjection(territory.id)
    local owner = BoP.getOwner(territory.id)
    report(string.format('%s %+.0f  (%.0f -> %.0f)\n%s\nholder: %s\nwill hold: %s',
        nameOf(target), data.amount, before, BoP.getPower(target),
        territory.displayName, nameOf(owner), nameOf(claimant)))
end

--- Answers "whose ground am I standing on?" for the cell watcher.
function handlers.BoPDev_WhereAmI(data)
    local territory = BoP.getTerritoryForCell(data.cell)
    if not territory then
        report(string.format('%s: no registered territory', data.cell))
        return
    end

    local owner = BoP.getOwner(territory.id)
    local claimant = BoP.getProjection(territory.id)

    -- Every faction that reaches here, strongest first. This is the
    -- number that decides ownership, so it's what to read when the map
    -- isn't doing what you expected.
    local rows = {}
    for _, id in ipairs(BoP.getReach(territory.id).ids) do
        rows[#rows + 1] = { id = id, value = BoP.getEffectivePower(id, territory.id) }
    end
    table.sort(rows, function(a, b) return a.value > b.value end)

    local projection = {}
    for _, row in ipairs(rows) do
        projection[#projection + 1] = string.format('  %s %.1f', nameOf(row.id), row.value)
    end
    if #projection == 0 then
        projection[1] = '  (nobody reaches here)'
    end

    local contested = ''
    if claimant and claimant ~= owner then
        contested = string.format('\ncontested by: %s', nameOf(claimant))
    end

    report(string.format('%s (%s, %s)\nowner: %s%s%s\nprojection:\n%s',
        territory.displayName,
        territory.kind == 'anchor' and territory.tier or 'frontier',
        BoP.classify(territory.id),
        owner and nameOf(owner) or 'unclaimed',
        BoP.isCorrupted(territory.id) and '  [CORRUPTED]' or '',
        contested,
        table.concat(projection, '\n')))
end

--- Deliberately bad registration, to confirm validation rejects it and
-- that a failed pack doesn't take the framework down with it. Uses
-- whichever faction happens to be registered first, so it works against
-- any content.
function handlers.BoPDev_SelfTest()
    local ids = BoP.factionIds()
    if #ids == 0 then
        report('No factions registered -- nothing to test against.')
        return
    end

    local victim = ids[1]
    local ok, err = pcall(function()
        BoP.registerLandmass({
            id = 'bopdev_should_not_exist',
            factions = { { id = victim } },   -- already registered, no extend
        })
    end)

    if ok then
        report('FAIL: a duplicate registration of "' .. victim .. '" was accepted.')
        return
    end

    report(string.format('Rejected as expected:\n%s\n\nFramework still live:\n%s',
        tostring(err), standings()))
end

return {
    eventHandlers = handlers,
}
