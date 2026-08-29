-- Terrain sampling and caching. No map texture available; derives from land records directly.
-- Not fog-of-war; shows unexplored coastlines.

local core = require('openmw.core')
local util = require('openmw.util')

local config = require('scripts.PixelMap.core.config')

local M = {}

local WATER_BANDS = config.TERRAIN_WATER_BANDS
local LAND_BANDS = config.TERRAIN_COLOR_BANDS - WATER_BANDS

local function lerpColor(a, b, t)
    t = math.max(0, math.min(1, t))
    return util.color.rgb(
        a.r + (b.r - a.r) * t,
        a.g + (b.g - a.g) * t,
        a.b + (b.b - a.b) * t)
end

local BLACK = util.color.rgb(0, 0, 0)

-- Sample an evenly spaced ramp of colour stops at t in [0,1].
local function rampAt(ramp, t)
    local n = #ramp
    if n == 0 then
        return BLACK
    end
    local at = math.max(0, math.min(1, t)) * (n - 1)
    local i = math.floor(at)
    if i >= n - 1 then
        return ramp[n]
    end
    return lerpColor(ramp[i + 1], ramp[i + 2], at - i)
end

-- Fixed stop by index, clamped so a short ramp still answers.
local function stopAt(ramp, index)
    local n = #ramp
    if n == 0 then
        return BLACK
    end
    return ramp[math.max(1, math.min(n, index))]
end

-- Runs merge on the drawn colour, not the band: a colour repeated across two
-- bands (a shared ramp stop at the shoreline) must not split a run.
local function mergeKeysFor(palette)
    local keys, byColor, count = {}, {}, 0
    for band = 0, config.TERRAIN_COLOR_BANDS - 1 do
        local c = palette[band]
        local id = string.format('%.4f,%.4f,%.4f', c.r, c.g, c.b)
        if byColor[id] == nil then
            byColor[id] = count
            count = count + 1
        end
        keys[band] = byColor[id]
    end
    return keys
end

-- Built once per theme; allocates only once per build, not once per sample.
local function buildTheme(def)
    local relief, flat = {}, {}
    for band = 0, WATER_BANDS - 1 do
        relief[band] = rampAt(def.water, band / math.max(1, WATER_BANDS - 1))
    end
    for i = 0, LAND_BANDS - 1 do
        relief[WATER_BANDS + i] = rampAt(def.land, i / math.max(1, LAND_BANDS - 1))
    end

    local flatLand = stopAt(def.land, config.FLAT_LAND_STOP)
    local flatOcean = stopAt(def.water, config.FLAT_WATER_STOP)
    for band = 0, config.TERRAIN_COLOR_BANDS - 1 do
        flat[band] = (band >= WATER_BANDS) and flatLand or flatOcean
    end

    return {
        palettes = { relief = relief, flat = flat },
        mergeKeys = { relief = mergeKeysFor(relief), flat = mergeKeysFor(flat) },
        void = stopAt(def.water, config.VOID_WATER_STOP),
    }
end

local THEMES = {}
for name, def in pairs(config.TERRAIN_THEMES) do
    THEMES[name] = buildTheme(def)
end

local theme = THEMES[config.TERRAIN_THEME] and config.TERRAIN_THEME or next(THEMES)
local style = THEMES[theme].palettes[config.TERRAIN_STYLE] and config.TERRAIN_STYLE or 'relief'

-- Switch themes (cache holds bands, not colours).
function M.setTheme(newTheme)
    if THEMES[newTheme] then
        theme = newTheme
    end
    return theme
end

-- Off-map backdrop: the deepest water of the live theme.
function M.voidColor()
    return THEMES[theme].void
end

-- Switch styles (cache holds bands, not colours).
function M.setStyle(newStyle)
    if THEMES[theme].palettes[newStyle] then
        style = newStyle
    end
    return style
end

function M.colorFor(band)
    return THEMES[theme].palettes[style][band]
end

function M.mergeKey(band)
    if band == nil then
        return nil
    end
    return THEMES[theme].mergeKeys[style][band]
end

local function bandFor(height)
    if height < config.WATER_LEVEL then
        local t = (height - config.TERRAIN_FLOOR) / (config.WATER_LEVEL - config.TERRAIN_FLOOR)
        return math.max(0, math.min(WATER_BANDS - 1, math.floor(t * WATER_BANDS)))
    end
    local t = (height - config.WATER_LEVEL) / (config.TERRAIN_PEAK - config.WATER_LEVEL)
    return WATER_BANDS + math.max(0, math.min(LAND_BANDS - 1, math.floor(t * LAND_BANDS)))
end

-- Two generations per worldspace; keyed by worldspace (Cyrodiil/Skyrim can share Vvardenfell coords).
local current, previous = {}, {}
local currentCount = 0

-- Get or create columns table for worldspace+step; resolved once per draw, held on context (hot path).
local function tier(root, worldSpaceId, step)
    local byWs = root[worldSpaceId]
    if not byWs then
        byWs = {}
        root[worldSpaceId] = byWs
    end
    local byStep = byWs[step]
    if not byStep then
        byStep = {}
        byWs[step] = byStep
    end
    return byStep
end

-- Rotate cache when full: clearing meant going cold every few zoom clicks.
local function rotateIfFull()
    if currentCount < config.TERRAIN_CACHE_LIMIT then
        return
    end
    previous = current
    current = {}
    currentCount = 0
end

-- Sample spacing: snapped to CELL_SIZE / 2^n so cache survives zoom. Negative n for continent zoom.
local function stepFor(view)
    local width = view.canvasSize.x / view.zoom
    local height = view.canvasSize.y / view.zoom
    local target = math.max(width, height) / config.TERRAIN_SAMPLES

    local subdiv = math.floor(math.log(config.CELL_SIZE / target) / math.log(2) + 0.5)
    subdiv = math.max(config.TERRAIN_MIN_SUBDIV, math.min(config.TERRAIN_MAX_SUBDIV, subdiv))

    -- Snapping can overshoot up to 2x; back off until sample count fits budget.
    while subdiv > config.TERRAIN_MIN_SUBDIV do
        local step = config.CELL_SIZE / (2 ^ subdiv)
        if (width / step + 1) * (height / step + 1) <= config.TERRAIN_MAX_QUADS then
            break
        end
        subdiv = subdiv - 1
    end
    return config.CELL_SIZE / (2 ^ subdiv)
end

-- Engine queries since the last context(). A bare counter rather than a
-- profiler call, because this is incremented once per cache miss in the
-- sampling loop and the loop runs thousands of times per redraw; the layer
-- reports the total once, afterwards.
local queries = 0

function M.queryCount()
    return queries
end

-- Worked out once per redraw (interior returns nil).
function M.context(view)
    if not view.cell then
        return nil
    end
    rotateIfFull()
    queries = 0

    local minX, minY, maxX, maxY = view.bounds()
    local step = stepFor(view)
    local worldSpaceId = view.worldSpaceId or 'default'
    local oldByWs = previous[worldSpaceId]
    return {
        cell = view.cell,
        tier = tier(current, worldSpaceId, step),
        oldTier = oldByWs and oldByWs[step] or nil,
        step = step,
        startX = math.floor(minX / step) * step,
        startY = math.floor(minY / step) * step,
        maxX = maxX,
        maxY = maxY,
    }
end

-- Get or query band at sample; cached failures as false (avoid re-query).
function M.bandAt(ctx, x, y)
    local col = ctx.tier[x]
    if not col then
        col = {}
        ctx.tier[x] = col
    end
    local cached = col[y]
    if cached ~= nil then
        return cached or nil
    end

    local old = ctx.oldTier and ctx.oldTier[x]
    local promoted = old and old[y]
    if promoted ~= nil then
        col[y] = promoted
        currentCount = currentCount + 1
        return promoted or nil
    end

    queries = queries + 1
    local ok, h = pcall(core.land.getHeightAt,
        util.vector3(x + ctx.step * 0.5, y + ctx.step * 0.5, 0), ctx.cell)
    local value = (ok and type(h) == 'number') and bandFor(h) or false

    col[y] = value
    currentCount = currentCount + 1
    return value or nil
end

function M.originX(view)
    return view.canvasSize.x * 0.5 - view.center.x * view.zoom
end

return M
