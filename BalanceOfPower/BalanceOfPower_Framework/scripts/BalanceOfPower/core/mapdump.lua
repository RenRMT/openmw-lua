-- Renders the political map as text, for the log.
--
-- A poor substitute for a real map, and deliberately so: the whole thing
-- is a hundred lines and needs no UI, no engine support and no textures,
-- while answering the questions that actually come up while tuning --
-- who holds what, where the fronts are, and whether influence ranges
-- produce a map that looks like Morrowind.
--
-- One character per exterior cell, north at the top. Uppercase is a
-- settlement, lowercase the wilderness around it, so a glance shows both
-- where the seats of power are and how far each one's country extends.
--
-- Rendering is separated from printing so a test can assert on the
-- output, and so a caller can send it somewhere other than the log.
--
-- GLOBAL context only.

local cells = require('scripts.BalanceOfPower.core.cells')
local config = require('scripts.BalanceOfPower.core.config')
local log = require('scripts.BalanceOfPower.core.log')
local registry = require('scripts.BalanceOfPower.core.registry')
local resolve = require('scripts.BalanceOfPower.core.resolve')
local state = require('scripts.BalanceOfPower.core.state')

local M = {}

local UNCLAIMED = '.'
local NO_TERRITORY = ' '
local FALLBACK_SYMBOLS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'

--------------------------------------------------------------------------
-- Symbols
--------------------------------------------------------------------------

--- One letter per land-holding faction, stable across runs.
--
-- Prefers a letter from the faction's own id, so the map is readable
-- without constantly consulting the legend -- H for hlaalu, R for
-- redoran, and where those collide (temple and telvanni both want T) the
-- next unused letter of the id.
local function assignSymbols()
    local used, symbols = {}, {}

    local function claim(id)
        for index = 1, #id do
            local letter = string.upper(string.sub(id, index, index))
            if string.match(letter, '%u') and not used[letter] then
                return letter
            end
        end
        for letter in string.gmatch(FALLBACK_SYMBOLS, '.') do
            if not used[letter] then
                return letter
            end
        end
        return '?'
    end

    for _, id in ipairs(registry.sortedFactionIds()) do
        if registry.factions[id].territorial then
            local letter = claim(id)
            used[letter] = true
            symbols[id] = letter
        end
    end

    return symbols
end

--------------------------------------------------------------------------
-- Grid assembly
--------------------------------------------------------------------------

--- Map every exterior cell of every territory onto its grid position.
-- A multi-cell settlement covers several positions, which is what makes
-- Vivec show up as a block rather than a dot.
local function buildGrid(landmassId)
    local grid = {}
    local minX, maxX, minY, maxY

    for id, territory in pairs(registry.territories) do
        if not landmassId or territory.landmass == landmassId then
            for _, cellName in ipairs(territory.cells) do
                local gridX, gridY = cells.parse(cellName)
                if gridX then
                    grid[gridY] = grid[gridY] or {}
                    grid[gridY][gridX] = id

                    minX = math.min(minX or gridX, gridX)
                    maxX = math.max(maxX or gridX, gridX)
                    minY = math.min(minY or gridY, gridY)
                    maxY = math.max(maxY or gridY, gridY)
                end
            end
        end
    end

    return grid, minX, maxX, minY, maxY
end

--------------------------------------------------------------------------
-- Cell rendering
--------------------------------------------------------------------------

-- Each renderer returns the character to draw, and the faction it stands
-- for -- so the legend can list only what actually appears on this map
-- rather than every faction in the world.
local renderers = {}

local function symbolFor(territory, factionId, symbols)
    if not factionId then
        return UNCLAIMED, nil
    end
    local letter = symbols[factionId] or '?'
    -- Settlements shout, wilderness whispers.
    if territory.kind ~= 'settlement' then
        letter = string.lower(letter)
    end
    return letter, factionId
end

--- Who holds this ground now.
function renderers.owner(territory, symbols)
    return symbolFor(territory, state.getOwner(territory.id), symbols)
end

--- Who *will* hold it, given time and no change in anyone's power. Where
-- this differs from the ownership map, the front is moving -- which
-- makes it the view to read while tuning influence ranges.
function renderers.projection(territory, symbols)
    return symbolFor(territory, resolve.strongestProjector(territory), symbols)
end

-- How settled each cell is, ignoring who holds it. The four states of
-- classify(), drawn so the eye reads density as pressure: open ground is
-- quiet, a border is busy.
local CONTEST_SYMBOLS = {
    unclaimed = UNCLAIMED,
    consolidated = '-',
    uncontested = '+',
    contested = '#',
}

function renderers.contest(territory)
    return CONTEST_SYMBOLS[resolve.classify(territory)] or UNCLAIMED, nil
end

--------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------

--- Render as a list of text lines.
--
-- @param opts table
--   landmass    restrict to one landmass
--   mode        'owner' | 'projection' | 'contest'
--   centreCell  "#x,y" to centre a window on, instead of drawing everything
--   radius      half-width of that window in cells (default 6)
--
-- The windowed form exists because the full map is forty columns by fifty
-- rows -- fine in a log, useless in a message box. Centred on where the
-- player is standing, a small window fits on screen and answers the
-- question actually being asked, which is what the ground around *here*
-- looks like.
function M.render(opts)
    opts = opts or {}
    local mode = opts.mode or 'owner'
    local renderCell = renderers[mode]
    if not renderCell then
        error('BalanceOfPower: unknown map mode "' .. tostring(mode) .. '"', 0)
    end

    local landmassId = opts.landmass
    local grid, minX, maxX, minY, maxY = buildGrid(landmassId)
    local lines = {}

    if not minX then
        lines[1] = string.format('%s: no territory with exterior cells',
            landmassId or 'world')
        return lines
    end

    local centreX, centreY
    if opts.centreCell then
        centreX, centreY = cells.parse(opts.centreCell)
        if not centreX then
            lines[1] = string.format('%s is not an exterior cell, so there is '
                .. 'nothing to centre on', tostring(opts.centreCell))
            return lines
        end
        -- Clamp to the drawn region: a window hanging off the edge of the
        -- world is just blank rows.
        local radius = opts.radius or config.MAP_WINDOW_RADIUS
        minX = math.max(minX, centreX - radius)
        maxX = math.min(maxX, centreX + radius)
        minY = math.max(minY, centreY - radius)
        maxY = math.min(maxY, centreY + radius)
        if minX > maxX or minY > maxY then
            lines[1] = string.format('%s is outside the simulated region',
                opts.centreCell)
            return lines
        end
    end

    local symbols = assignSymbols()

    local day = state.get().lastResolvedDay
    lines[#lines + 1] = string.format('=== %s -- %s -- %s ===',
        landmassId or 'world', mode,
        day and ('day ' .. day) or 'not yet ticked')
    if centreX then
        lines[#lines + 1] = string.format('around %s', opts.centreCell)
    else
        lines[#lines + 1] = string.format('x %d..%d, y %d..%d', minX, maxX, minY, maxY)
    end

    -- A ruler of last digits, so a column can be counted back to its
    -- real x without labelling every one of forty columns.
    local ruler = {}
    for gridX = minX, maxX do
        ruler[#ruler + 1] = tostring(math.abs(gridX) % 10)
    end
    lines[#lines + 1] = '      ' .. table.concat(ruler)

    -- North at the top: +Y is north in Morrowind, so rows descend.
    local seen = {}
    for gridY = maxY, minY, -1 do
        local row = {}
        for gridX = minX, maxX do
            local territoryId = grid[gridY] and grid[gridY][gridX]
            if territoryId then
                local letter, factionId = renderCell(registry.territories[territoryId], symbols)
                row[#row + 1] = letter
                if factionId then
                    seen[factionId] = true
                end
            else
                row[#row + 1] = NO_TERRITORY
            end
        end
        lines[#lines + 1] = string.format('%5d %s', gridY, table.concat(row))
    end

    if mode == 'contest' then
        lines[#lines + 1] = 'legend: # contested   + uncontested   '
            .. '- consolidated   . unclaimed'
        return lines
    end

    -- Only the factions that actually appear here. Listing every faction
    -- in the world would put the Great Houses in Solstheim's legend.
    local entries = {}
    for id in pairs(seen) do
        entries[#entries + 1] = string.format('%s/%s %s',
            symbols[id], string.lower(symbols[id]), registry.factions[id].displayName)
    end
    -- Sorted by symbol, so the legend reads in the order the eye scans.
    table.sort(entries)
    lines[#lines + 1] = 'legend: ' .. table.concat(entries, '   ')
    lines[#lines + 1] = '        UPPER = settlement, lower = wilderness, . = unclaimed'

    return lines
end

--- Print the map to the log.
--
-- With no landmass given, every registered landmass is drawn separately.
-- Drawing them together would be technically possible -- they share one
-- cell grid -- but Solstheim sits far to the north-west of Vvardenfell,
-- so a combined map is mostly blank.
function M.dump(opts)
    opts = opts or {}

    local landmasses = {}
    if opts.landmass then
        landmasses[1] = opts.landmass
    else
        for id in pairs(registry.landmasses) do
            landmasses[#landmasses + 1] = id
        end
        table.sort(landmasses)
    end

    for _, landmassId in ipairs(landmasses) do
        for _, line in ipairs(M.render({ landmass = landmassId, mode = opts.mode })) do
            log.info('%s', line)
        end
    end
end

return M
