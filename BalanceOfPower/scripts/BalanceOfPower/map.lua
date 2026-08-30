-- The map overlays: where the settlements are, and who controls the
-- ground, drawn on Pixel Map.
--
-- Two layers, because they answer two questions at two scales. The
-- settlement layer outlines named places and marks each with its tier;
-- the control layer washes every held cell in its holder's colour. A
-- player who wants the frontier without the labels, or the labels without
-- the wash, turns one off.
--
-- PLAYER context only, because that is where Pixel Map lives. The
-- framework's interface is global-only, so this asks for its data with
-- BoP_RequestMap and BoP_RequestTerritory exactly as any third-party mod
-- would have to -- there is no private channel here that an outside map
-- could not also use.
--
-- Optional in every direction. Pixel Map may not be installed, may load
-- after this script, or may be reloaded underneath it; none of those is
-- an error, and in all of them this simply draws nothing.
--
-- No cell geometry lives here. Pixel Map owns the grid its canvas is drawn
-- on, so the range to paint, a cell's rectangle and the seam between two of
-- them all come from `view`. This file decides only what colour a cell is
-- and what its tooltip says.

local core = require('openmw.core')
local ui = require('openmw.ui')
local util = require('openmw.util')

local I = require('openmw.interfaces')

local config = require('scripts.BalanceOfPower.core.config')
local eventnames = require('scripts.BalanceOfPower.core.eventnames')

local l10n = core.l10n(config.L10N_CONTEXT, 'en')

-- gridX -> gridY -> { settlementId, settlement, owner, ownerName, color },
-- rebuilt whenever a BoP_Map arrives. Keyed by grid rather than kept as a
-- list because draw culls to the visible cell range and then looks each
-- one up, which turns the per-frame cost into the size of the viewport
-- instead of the size of the world. The perimeter test wants the same
-- lookup for a cell's four neighbours, which a list could not answer.
local byGrid = {}

-- One row per settlement: { name, tier, gridX, gridY, color, ownerName }.
-- A list rather than a grid because there are a few hundred of them
-- against thousands of cells, and every one carries a marker that is
-- sized in screen pixels and so can hang outside its own cell.
local places = {}
local haveData = false

-- The control wash: gridX -> gridY -> colour. Separate from byGrid
-- because it covers the whole generated map, arrives from a different
-- event, and is drawn by a layer the player can turn off on its own.
local controlByGrid = {}
local haveControl = false

-- The world moved while the map was shut, so what is held here is a day or
-- more out of date. Cleared by the next request.
local stale = false

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

local iconOutlineColor = util.color.rgb(0.05, 0.05, 0.05)

-- ui.texture is a resource handle rather than a value, so one per tier is
-- built once and kept. Empty until MAP_TIER_ICON_TEXTURE has entries, at
-- which point that tier's icon stops being a plain square.
local iconTextures = {}

local function iconTextureFor(tier)
    local path = config.MAP_TIER_ICON_TEXTURE[tier]
    if not path then
        return nil
    end
    local cached = iconTextures[tier]
    if not cached then
        cached = ui.texture { path = path }
        iconTextures[tier] = cached
    end
    return cached
end

--------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------

--- A no-op while the map is shut, so this is safe to call blindly every
-- time the world moves under us.
local function refresh()
    if I.PixelMap then
        I.PixelMap.redraw()
    end
end

local function onMap(data)
    byGrid = {}
    places = {}
    haveData = true

    for _, row in ipairs(data and data.cells or {}) do
        local column = byGrid[row.gridX]
        if not column then
            column = {}
            byGrid[row.gridX] = column
        end
        column[row.gridY] = {
            settlementId = row.settlementId,
            settlement = row.settlement,
            owner = row.owner,
            ownerName = row.ownerName,
            color = colorFor(row.owner),
            -- Built here, not in blockAt: the outline asks every member cell
            -- for its group five times over -- itself and its four
            -- neighbours -- on every redraw, and a pan redraws several times
            -- a second. This changes only when a BoP_Map lands.
            block = row.settlementId .. '/' .. tostring(row.owner),
        }
    end

    for _, row in ipairs(data and data.settlements or {}) do
        places[#places + 1] = {
            name = row.name,
            tier = row.tier,
            gridX = row.gridX,
            gridY = row.gridY,
            ownerName = row.ownerName,
            color = colorFor(row.owner),
        }
    end

    refresh()
end

local function onTerritory(data)
    controlByGrid = {}
    haveControl = true

    for _, held in ipairs(data and data.owners or {}) do
        local color = colorFor(held.faction)
        local flat = held.cells
        -- x, y, x, y, ... -- see BoP_Territory for why it arrives flat.
        for index = 1, #flat - 1, 2 do
            local gridX, gridY = flat[index], flat[index + 1]
            local column = controlByGrid[gridX]
            if not column then
                column = {}
                controlByGrid[gridX] = column
            end
            column[gridY] = color
        end
    end

    refresh()
end

local function requestMap()
    stale = false
    core.sendGlobalEvent(eventnames.REQUEST_MAP, {})
    core.sendGlobalEvent(eventnames.REQUEST_TERRITORY, {})
end

--- Ask again if the world moved while the map was shut.
--
-- Called from the layers rather than from an open hook, because a draw is
-- the first thing that happens when the window opens and there is no other
-- signal. The answer arrives a moment later and redraws, so an
-- already-open map shows one frame of yesterday's frontier -- a far better
-- trade than rebuilding and serializing every owned cell in the world once
-- an in-game day for nobody.
local function refreshIfStale()
    if stale then
        requestMap()
    end
end

--------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------

local function at(grid, gridX, gridY)
    local column = grid[gridX]
    return column and column[gridY] or nil
end

--- What the tooltip says over one settlement cell.
local function describe(entry)
    if entry.ownerName then
        return l10n('mapTooltipHeld', { settlement = entry.settlement, faction = entry.ownerName })
    end
    return l10n('mapTooltipUnowned', { settlement = entry.settlement })
end

--- Which outlined block a cell belongs to, for PixelMap.outline.
--
-- Settlement *and* owner, not settlement alone. A city taken in pieces is
-- held in pieces, and one outline drawn around the whole of it would paint
-- one colour over two claims -- exactly the thing this layer exists to
-- show. Pixel Map compares whatever comes back, so a string of the two is
-- all the grouping it needs.
local function blockAt(gridX, gridY)
    local entry = at(byGrid, gridX, gridY)
    return entry and entry.block or nil
end

--- The tier mark in a settlement's middle cell.
--
-- Sized in screen pixels, so the ladder stays readable at every zoom
-- instead of collapsing with the map. A tier with no size on the ladder
-- draws nothing, which is how a farm stays an outline. Pixel Map culls
-- what is off canvas, so every settlement can be offered blindly.
local function icon(out, view, place)
    local size = config.MAP_TIER_ICON_SIZE[place.tier]
    if not size then
        return
    end
    out[#out + 1] = I.PixelMap.marker {
        position = view.cellToWorld(place.gridX, place.gridY),
        size = size,
        color = place.color,
        outline = config.MAP_ICON_OUTLINE,
        outlineColor = iconOutlineColor,
        resource = iconTextureFor(place.tier),
        tooltip = describe { settlement = place.name, ownerName = place.ownerName },
    }
end

--- Settlements: the perimeter of each held block, then the tier marks.
--
-- The outline leaves the middle of a block empty on purpose -- it says
-- where a place is without hiding the ground it stands on -- and its
-- tooltip covers the cell whole, interior included.
local function drawSettlements(view)
    refreshIfStale()

    local out = I.PixelMap.outline {
        group = blockAt,
        color = function(_, gridX, gridY)
            return at(byGrid, gridX, gridY).color
        end,
        width = config.MAP_OUTLINE_WIDTH,
        alpha = config.MAP_OUTLINE_ALPHA,
        tooltip = function(_, gridX, gridY)
            return describe(at(byGrid, gridX, gridY))
        end,
    }

    -- Icons last, so they sit above every outline rather than only above
    -- their own settlement's.
    if view.cellBounds() then
        for _, place in ipairs(places) do
            icon(out, view, place)
        end
    end

    return out
end

--- The control wash: one colour per held cell, over the whole frontier.
--
-- Pixel Map merges runs of one colour along each row, so a faction holding
-- a contiguous province costs a handful of quads rather than one per cell.
local function drawControl()
    refreshIfStale()

    return I.PixelMap.cells {
        at = function(gridX, gridY)
            return at(controlByGrid, gridX, gridY), config.MAP_CONTROL_ALPHA
        end,
    }
end

--------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------

local function register()
    if not I.PixelMap then
        return
    end

    I.PixelMap.registerLayer {
        key = config.MAP_CONTROL_LAYER_KEY,
        name = l10n('mapControlLayerName'),
        order = config.MAP_CONTROL_LAYER_ORDER,
        -- Deliberately not interactive. It covers most of the world, and
        -- an interactive layer that size would make the map undraggable
        -- everywhere anybody holds ground. The settlement layer above it
        -- is what answers the cursor.
        draw = drawControl,
    }

    I.PixelMap.registerLayer {
        key = config.MAP_LAYER_KEY,
        name = l10n('mapLayerName'),
        order = config.MAP_LAYER_ORDER,
        -- Needed for the hover tooltips, and the cost is that a drag
        -- begun on a settlement does not pan the map. Acceptable here:
        -- settlements are a small fraction of the surface, so there is
        -- open ground to grab almost everywhere.
        interactive = true,
        draw = drawSettlements,
    }

    -- Registering says nothing about having anything to draw, and the
    -- layers may well be registered long before the first BoP_Map lands.
    if not haveData or not haveControl then
        requestMap()
    end
end

--- Ask again once the world has moved.
--
-- Ownership only changes on the framework's daily pass, so this is the
-- one event worth relisting on -- redrawing off TERRITORY_FLIPPED would
-- mean a request per flip, and a season's frontier churn is hundreds.
local function onDayResolved()
    -- Only worth asking for if somebody is looking. Otherwise this is the
    -- whole world's ownership rebuilt, serialized across the global/player
    -- boundary and thrown away, every simulated day.
    if I.PixelMap and I.PixelMap.isOpen() then
        requestMap()
    else
        stale = true
    end
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
        [eventnames.TERRITORY] = onTerritory,
        [eventnames.DAY_RESOLVED] = onDayResolved,
    },
}
