-- The territory overlay: who holds which settlement, drawn on Pixel Map.
--
-- PLAYER context only, because that is where Pixel Map lives. The
-- framework's interface is global-only, so this asks for its data with
-- BoP_RequestMap exactly as any third-party mod would have to -- there is
-- no private channel here that an outside map could not also use.
--
-- Optional in every direction. Pixel Map may not be installed, may load
-- after this script, or may be reloaded underneath it; none of those is
-- an error, and in all of them this simply draws nothing.

local core = require('openmw.core')
local util = require('openmw.util')

local I = require('openmw.interfaces')

local config = require('scripts.BalanceOfPower.core.config')
local eventnames = require('scripts.BalanceOfPower.core.eventnames')

local l10n = core.l10n(config.L10N_CONTEXT, 'en')

-- gridX -> gridY -> { settlement, ownerName, color }, rebuilt whenever a
-- BoP_Map arrives. Keyed by grid rather than kept as a list because draw
-- culls to the visible cell range and then looks each one up, which turns
-- the per-frame cost into the size of the viewport instead of the size of
-- the world.
local byGrid = {}
local haveData = false

--------------------------------------------------------------------------
-- Colour
--------------------------------------------------------------------------

--- A stable colour for a faction with no entry in the palette.
--
-- Hashed from the id so a modded faction keeps the same colour between
-- sessions, and kept light and saturated enough to read against the
-- terrain -- a derived colour that lands on dark grey would be
-- indistinguishable from unowned ground.
local function derivedColor(factionId)
    local hash = 0
    for index = 1, #factionId do
        hash = (hash * 31 + string.byte(factionId, index)) % 65536
    end
    local function channel(shift)
        return 0.35 + ((math.floor(hash / shift) % 8) / 7) * 0.5
    end
    return { channel(1), channel(8), channel(64) }
end

local colorCache = {}

local function colorFor(factionId)
    if not factionId then
        local unowned = config.MAP_COLOR_UNOWNED
        return util.color.rgb(unowned[1], unowned[2], unowned[3])
    end
    local cached = colorCache[factionId]
    if not cached then
        local rgb = config.MAP_COLORS[factionId] or derivedColor(factionId)
        cached = util.color.rgb(rgb[1], rgb[2], rgb[3])
        colorCache[factionId] = cached
    end
    return cached
end

--------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------

local function onMap(data)
    byGrid = {}
    haveData = true

    for _, row in ipairs(data and data.cells or {}) do
        local column = byGrid[row.gridX]
        if not column then
            column = {}
            byGrid[row.gridX] = column
        end
        column[row.gridY] = {
            settlement = row.settlement,
            ownerName = row.ownerName,
            color = colorFor(row.owner),
        }
    end

    -- A no-op while the map is shut, so this is safe to call blindly
    -- every time the world moves under us.
    if I.PixelMap then
        I.PixelMap.redraw()
    end
end

local function requestMap()
    core.sendGlobalEvent(eventnames.REQUEST_MAP, {})
end

--------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------

--- What the tooltip says over one settlement cell.
local function describe(entry)
    if entry.ownerName then
        return l10n('mapTooltipHeld', { settlement = entry.settlement, faction = entry.ownerName })
    end
    return l10n('mapTooltipUnowned', { settlement = entry.settlement })
end

local function draw(view)
    -- No exterior under the player means no grid to paint on.
    if not view.cell then
        return {}
    end

    local minX, minY, maxX, maxY = view.bounds()
    -- The framework's own figure rather than Pixel Map's: both read it
    -- from the engine, but a disagreement here would slide the overlay
    -- off the grid it is meant to be painting.
    local size = config.CELL_SIZE

    -- Cull to the visible cell range and look those up, rather than
    -- walking every settlement in the world: zoomed out, the second costs
    -- the same at every frame no matter how little of it is on screen.
    local fromX = math.floor(minX / size)
    local toX = math.floor(maxX / size)
    local fromY = math.floor(minY / size)
    local toY = math.floor(maxY / size)

    local out = {}
    for gridX = fromX, toX do
        local column = byGrid[gridX]
        if column then
            for gridY = fromY, toY do
                local entry = column[gridY]
                if entry then
                    out[#out + 1] = I.PixelMap.cell {
                        gridX = gridX,
                        gridY = gridY,
                        color = entry.color,
                        alpha = config.MAP_FILL_ALPHA,
                        border = config.MAP_CELL_BORDER,
                        tooltip = describe(entry),
                    }
                end
            end
        end
    end
    return out
end

--------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------

local function register()
    if not I.PixelMap then
        return
    end

    I.PixelMap.registerLayer {
        key = config.MAP_LAYER_KEY,
        name = l10n('mapLayerName'),
        order = config.MAP_LAYER_ORDER,
        -- Needed for the hover tooltips, and the cost is that a drag
        -- begun on a settlement does not pan the map. Acceptable here:
        -- settlements are a small fraction of the surface, so there is
        -- open ground to grab almost everywhere.
        interactive = true,
        draw = draw,
    }

    -- Registering says nothing about having anything to draw, and the
    -- layer may well be registered long before the first BoP_Map lands.
    if not haveData then
        requestMap()
    end
end

--- Ask again once the world has moved.
--
-- Ownership only changes on the framework's daily pass, so this is the
-- one event worth relisting on -- redrawing off TERRITORY_FLIPPED would
-- mean a request per flip, and a season's frontier churn is hundreds.
local function onDayResolved()
    requestMap()
end

return {
    engineHandlers = {
        onInit = register,
        onLoad = register,
    },
    eventHandlers = {
        -- Pixel Map announces itself after every script loads, including
        -- reloadlua, which is what makes load order irrelevant here.
        PixelMapReady = register,
        [eventnames.MAP] = onMap,
        [eventnames.DAY_RESOLVED] = onDayResolved,
    },
}
