-- The text map.

local expect = require('support.expect')

local world = require('openmw.world')

local mapdump = require('scripts.BalanceOfPower.core.mapdump')
local power = require('scripts.BalanceOfPower.core.power')
local registry = require('scripts.BalanceOfPower.core.registry')
local resolve = require('scripts.BalanceOfPower.core.resolve')
local state = require('scripts.BalanceOfPower.core.state')

local M = {}

local CELL = 8192

local function cellCentre(gridX, gridY)
    return { x = gridX * CELL + CELL / 2, y = gridY * CELL + CELL / 2 }
end

--- Two factions with settlements close enough that their influence
-- genuinely overlaps, so there is a contested band between them. Set
-- them any further apart and the discs are tangent, nothing is
-- contested, and several of these tests would pass by accident.
local function twoRealms()
    world._test.defineExteriorGrid(-6, 6, -6, 6)

    registry.registerLandmass({
        id = 'testland',
        factions = {
            {
                id = 'alpha',
                displayName = 'Alpha',
                basePower = 50,
                powerCenters = {
                    { id = 'alpha_seat', tier = 'capital',
                      coords = cellCentre(-2, 0), influenceRange = 3 * CELL },
                },
            },
            {
                id = 'beta',
                -- Stronger, so it holds the overlapping band outright.
                -- At equal power the tie would go to alpha on sorted id,
                -- and boosting alpha later would change nothing.
                displayName = 'Beta',
                basePower = 80,
                powerCenters = {
                    { id = 'beta_seat', tier = 'capital',
                      coords = cellCentre(2, 0), influenceRange = 3 * CELL },
                },
            },
            -- Power-only: has standing, holds nothing, must never appear.
            {
                id = 'guild',
                displayName = 'Guild',
                territorial = false,
                basePower = 90,
            },
        },
        territories = {
            { id = 'alphatown', displayName = 'Alphatown', tier = 'town',
              cells = { '#-2,0' }, centroid = cellCentre(-2, 0) },
            { id = 'betatown', displayName = 'Betatown', tier = 'town',
              cells = { '#2,0' }, centroid = cellCentre(2, 0) },
        },
    })
    state.fillDefaults(registry)
    require('scripts.BalanceOfPower.core.frontier').generate({
        landmass = 'testland', margin = 0,
    })
    resolve.assignInitialControl()
end

local function joined(lines)
    return table.concat(lines, '\n')
end

--- Just the drawn rows, without the header or legend. The legend for
-- `contest` mode contains a '#' of its own, so searching the whole
-- output for one would pass whether or not anything was drawn.
local function gridOnly(lines)
    local rows = {}
    for _, line in ipairs(lines) do
        if string.match(line, '^%s*%-?%d+ ') then
            rows[#rows + 1] = line
        end
    end
    return table.concat(rows, '\n')
end

--------------------------------------------------------------------------

function M.drawsSettlementsInUppercaseAndWildernessInLower()
    twoRealms()
    local text = joined(mapdump.render({ landmass = 'testland' }))

    expect.truthy(string.find(text, 'A', 1, true), 'the settlement')
    expect.truthy(string.find(text, 'a', 1, true), 'its wilderness')
    expect.truthy(string.find(text, 'B', 1, true), 'the rival settlement')
end

--- North at the top. Getting this backwards would make every map a lie
-- that still looked plausible, so it's worth pinning down.
function M.putsNorthAtTheTop()
    twoRealms()
    local lines = mapdump.render({ landmass = 'testland' })

    local previous = nil
    for _, line in ipairs(lines) do
        local label = string.match(line, '^%s*(%-?%d+) ')
        if label then
            local y = tonumber(label)
            if previous then
                expect.truthy(y < previous, 'rows descend in y')
            end
            previous = y
        end
    end
    expect.truthy(previous ~= nil, 'some rows were drawn')
end

--- A guild has standing but no ground, so it must not appear on the map
-- or in its legend however much power it has.
function M.omitsPowerOnlyFactions()
    twoRealms()
    local text = joined(mapdump.render({ landmass = 'testland' }))

    expect.falsy(string.find(text, 'Guild', 1, true), 'guild absent from the legend')
end

--- Listing every faction in the world would put the Great Houses in
-- Solstheim's legend.
function M.legendListsOnlyWhatIsDrawn()
    twoRealms()
    -- Strip beta from the map by removing its power entirely.
    power.set('beta', 0)
    resolve.invalidateProjections()

    local text = joined(mapdump.render({ landmass = 'testland', mode = 'projection' }))
    expect.truthy(string.find(text, 'Alpha', 1, true), 'Alpha is drawn and listed')
    expect.falsy(string.find(text, 'Beta', 1, true), 'Beta projects nothing, so is not listed')
end

--- The view for tuning: where projection disagrees with ownership, the
-- front is about to move.
function M.projectionModeShowsWhoWillHoldGround()
    twoRealms()
    local before = joined(mapdump.render({ landmass = 'testland', mode = 'projection' }))

    power.set('alpha', 500)
    local after = joined(mapdump.render({ landmass = 'testland', mode = 'projection' }))

    expect.truthy(before ~= after, 'the projection map moves when power moves')

    -- Ownership has not caught up yet -- that takes daily rolls.
    local owner = joined(mapdump.render({ landmass = 'testland', mode = 'owner' }))
    expect.truthy(owner ~= after, 'ownership lags projection')
end

function M.contestModeMarksFronts()
    twoRealms()
    local lines = mapdump.render({ landmass = 'testland', mode = 'contest' })

    expect.truthy(string.find(joined(lines), 'contested', 1, true), 'legend')
    expect.truthy(string.find(gridOnly(lines), '#', 1, true),
        'a contested cell between the two realms')
    expect.truthy(string.find(gridOnly(lines), '-', 1, true), 'and consolidated ground')
end

function M.rejectsUnknownMode()
    twoRealms()
    expect.raises(function()
        mapdump.render({ landmass = 'testland', mode = 'nonsense' })
    end, 'unknown map mode', 'bad mode')
end

function M.handlesAnEmptyWorld()
    local lines = mapdump.render({ landmass = 'nowhere' })
    expect.count(lines, 1, 'one explanatory line')
    expect.truthy(string.find(lines[1], 'no territory', 1, true), 'says so plainly')
end

return M
