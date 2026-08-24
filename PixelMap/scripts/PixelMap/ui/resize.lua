-- Window move/resize arithmetic. Engine-free -- plain numbers in, plain numbers
-- out, no vectors and no openmw packages -- so it can be unit-tested; the frame
-- owns the grab strips and applies these results.

local M = {}

-- Which edges a grab pulls. `move` pulls none and translates instead.
M.GRABS = {
    move        = {},
    left        = { x = -1 },
    right       = { x = 1 },
    top         = { y = -1 },
    bottom      = { y = 1 },
    topLeft     = { x = -1, y = -1 },
    topRight    = { x = 1, y = -1 },
    bottomLeft  = { x = -1, y = 1 },
    bottomRight = { x = 1, y = 1 },
}

local function clamp(v, lo, hi)
    if v < lo then
        return lo
    end
    if v > hi then
        return hi
    end
    return v
end

--- New window rect for a drag.
--
-- Pure and idempotent: resolved from the rect recorded when the drag began, so
-- the same movement arriving twice lands in the same place. A leading edge moves
-- the origin and shrinks the size together; a trailing edge only resizes.
--
-- @param grab  a key of M.GRABS
-- @param start { x, y, w, h } at press
-- @param delta { x, y } cursor movement since press
-- @param opts  { minW, minH, screenW, screenH }
-- @return { x, y, w, h }
function M.apply(grab, start, delta, opts)
    local pull = M.GRABS[grab]
    if not pull then
        return { x = start.x, y = start.y, w = start.w, h = start.h }
    end

    if grab == 'move' then
        return {
            x = clamp(start.x + delta.x, 0, math.max(0, opts.screenW - start.w)),
            y = clamp(start.y + delta.y, 0, math.max(0, opts.screenH - start.h)),
            w = start.w,
            h = start.h,
        }
    end

    local x, y, w, h = start.x, start.y, start.w, start.h

    if pull.x == -1 then
        local dx = clamp(delta.x, -start.x, start.w - opts.minW)
        x, w = start.x + dx, start.w - dx
    elseif pull.x == 1 then
        w = clamp(start.w + delta.x, opts.minW, opts.screenW - start.x)
    end

    if pull.y == -1 then
        local dy = clamp(delta.y, -start.y, start.h - opts.minH)
        y, h = start.y + dy, start.h - dy
    elseif pull.y == 1 then
        h = clamp(start.h + delta.y, opts.minH, opts.screenH - start.y)
    end

    return { x = x, y = y, w = w, h = h }
end

--- What a cursor position inside the window means.
--
-- `fallback` is what the middle of the window is for -- a map pans, a list does
-- nothing -- so the caller names it rather than this module assuming.
function M.classify(offset, size, opts)
    local g = opts.grab
    local left = offset.x < g
    local right = offset.x > size.x - g
    local top = offset.y < g
    local bottom = offset.y > size.y - g

    if top and left then return 'topLeft' end
    if top and right then return 'topRight' end
    if bottom and left then return 'bottomLeft' end
    if bottom and right then return 'bottomRight' end
    if left then return 'left' end
    if right then return 'right' end
    if top then return 'top' end
    if bottom then return 'bottom' end
    if offset.y < g + opts.title then return 'move' end
    return opts.fallback
end

return M
