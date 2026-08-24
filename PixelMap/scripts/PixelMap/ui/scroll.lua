-- Scroll arithmetic for clip-and-offset scroll areas. Engine-free so it can be
-- unit-tested; the window owns the widgets and applies these results.
--
-- Axis-agnostic: every function takes a content length and a viewport length,
-- so the same module serves a vertical list and a horizontal strip.

local M = {}

-- Below this a proportional thumb rounds away to nothing on a long list.
M.MIN_THUMB = 28

--- Largest valid offset. Zero when the content already fits.
function M.maxOffset(content, view)
    return math.max(0, (content or 0) - (view or 0))
end

--- Clamp an offset into [0, maxOffset].
function M.clamp(offset, content, view)
    local limit = M.maxOffset(content, view)
    offset = offset or 0
    if offset < 0 then
        return 0
    end
    if offset > limit then
        return limit
    end
    return offset
end

--- Thumb geometry for a track of `track` pixels.
--
-- `slack` lets a pane whose content length is only estimated ignore a few
-- pixels of overshoot rather than show a scrollbar for content that fits.
-- @return { visible = boolean, length = number, offset = number }
function M.thumb(content, view, track, offset, slack)
    content = content or 0
    if content <= 0 or content <= view + (slack or 0) then
        return { visible = false, length = track, offset = 0 }
    end
    local length = math.max(M.MIN_THUMB, track * view / content)
    local limit = M.maxOffset(content, view)
    local travel = limit > 0 and (M.clamp(offset, content, view) / limit) * (track - length) or 0
    return { visible = true, length = length, offset = travel }
end

--- How far the content moves per pixel the thumb is dragged.
--
-- The thumb crosses its travel while the content crosses its whole overflow, so
-- a drag moves the content by more than the cursor moved, by exactly that ratio.
function M.dragScale(content, view, track)
    local travel = track - M.thumb(content, view, track, 0).length
    if travel <= 0 then
        return 0
    end
    return M.maxOffset(content, view) / travel
end

--- Offset an absolute thumb position maps to.
function M.dragTo(position, content, view, track)
    return M.clamp(position * M.dragScale(content, view, track), content, view)
end

--- Shift an offset so that the span [at, at + length] is inside the viewport.
-- Used to keep a keyboard-selected row on screen.
function M.reveal(offset, at, length, view, content)
    if at < offset then
        offset = at
    elseif at + length > offset + view then
        offset = at + length - view
    end
    return M.clamp(offset, content, view)
end

return M
