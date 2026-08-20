-- TravelFlavor -- a line of colour after a journey.
-- PLAYER context only.
--
-- Nothing in the engine announces "the player has travelled", so it is
-- inferred: a conversation with somebody who sells travel, followed shortly
-- by arriving somewhere else. Neither half is enough on its own -- talking to
-- a caravaner and walking out is not a journey, and a door is not one either.

local core = require('openmw.core')
local self = require('openmw.self')
local types = require('openmw.types')
local ui = require('openmw.ui')

local L10N = 'TravelFlavor'
local l10n = core.l10n(L10N, 'en')

-- Set true and the log says what the engine reported at every step, which is
-- how the numbers below were chosen and how to choose them again.
local DEBUG = false

-- Lines that suit any journey, used when the operator's own class has none
-- written for it. Every unknown vehicle lands here, so it is the one group
-- that must never be empty.
local GENERIC = 'generic'

-- Real seconds an arrival may lag the conversation closing before it stops
-- counting as the journey that conversation sold. Vanilla moves you the
-- moment you pick a destination; this only has to cover the load.
local ARRIVAL_WINDOW = 3.0

-- Real seconds to wait after arriving before saying anything. A message
-- posted during the load is a message nobody reads.
local SETTLE = 0.5

-- No group is ever going to have this many lines; it is here so a gap in the
-- numbering cannot spin the counting loop forever.
local MAX_LINES = 500

local function out(fmt, ...)
    if DEBUG then
        print('[TravelFlavor] ' .. string.format(fmt, ...))
    end
end

--------------------------------------------------------------------------
-- The lines
--------------------------------------------------------------------------
--
-- A group is an operator's class id, lowercased, and the l10n keys are that
-- id numbered from one: `shipmaster_1`, `guild guide_1`,
-- `t_mw_riverstriderservice_1`. There is no table mapping one to the other
-- and nothing to keep in step -- a landmass mod that invents a class gets its
-- own lines the moment somebody writes them under that name, and falls back
-- to generic until they do.

-- How many lines each group has. Counted the first time a group is asked
-- about rather than at load, because the groups are class ids and there is no
-- list of those to walk.
--
-- Counted rather than declared. A count kept by hand beside the yaml goes
-- stale the moment a line is added and the new line is simply never shown.
--
-- What a missing key looks like is not worth being sure about: l10n may hand
-- back the key itself, or nothing, or raise. All three mean "there is no line
-- number `index`", so all three end the count.
local counts = {}

local function lineCount(group)
    if counts[group] ~= nil then
        return counts[group]
    end
    local found = 0
    for index = 1, MAX_LINES do
        local key = group .. '_' .. index
        local ok, text = pcall(l10n, key)
        if not ok or text == nil or text == '' or text == key then
            break
        end
        found = index
    end
    counts[group] = found
    out('%s: %d line(s)', group, found)
    return found
end

-- math.random without a seed deals the same hand every session. Seeded at the
-- first journey rather than at load, because at load the clock has barely
-- started and every session would begin from much the same number.
local seeded = false

local function seed()
    if seeded then
        return
    end
    seeded = true
    pcall(function()
        math.randomseed(math.floor(core.getRealTime() * 1000) % 2147483647)
    end)
end

-- What each group said last, so it does not say it twice running.
local lastShown = {}

local function lineFor(group)
    local count = lineCount(group)
    if count == 0 then
        return nil
    end
    seed()
    local index = math.random(count)
    -- The same line twice in a row reads as a bug rather than as chance.
    if count > 1 and index == lastShown[group] then
        index = index % count + 1
    end
    lastShown[group] = index
    local ok, text = pcall(l10n, group .. '_' .. index)
    return ok and text or nil
end

--------------------------------------------------------------------------
-- Who sells travel, and what kind
--------------------------------------------------------------------------

--- An actor's record, whether they are an NPC or a creature.
-- Asked by trying rather than by testing the type, so this needs to know
-- nothing about how the engine spells "is an NPC".
local function recordOf(actor)
    local ok, record = pcall(types.NPC.record, actor)
    if ok and record then
        return record
    end
    ok, record = pcall(types.Creature.record, actor)
    if ok and record then
        return record
    end
    return nil
end

--- Which group of lines describes travelling with this actor, or nil when
-- they sell no travel at all.
--
-- `record.class` is the class *record id*, never the name shown in game --
-- Tamriel Rebuilt's river striders are class `T_Mw_RiverstriderService` named
-- "Therionaut". Lowercased, because the ESM capitalises inconsistently.
--
-- A creature has no class at all, and so falls back like any other operator
-- whose vehicle nobody has written lines for.
local function travelGroupOf(actor)
    if actor == nil then
        return nil
    end
    local record = recordOf(actor)
    if record == nil then
        return nil
    end
    -- The one thing that actually says "this person sells travel". Creature
    -- records carry it too; no vanilla creature uses it, but a mod may.
    --
    -- Length, not type. The engine hands these lists back as *userdata*, not
    -- as Lua tables, so testing for 'table' rejects every real operator --
    -- which it duly did, in silence, until the log was asked about it.
    local ok, count = pcall(function() return #record.travelDestinations end)
    if not ok or count == nil or count == 0 then
        out('%s sells no travel (%s)', tostring(record.id), type(record.travelDestinations))
        return nil
    end
    if type(record.class) ~= 'string' or record.class == '' then
        return GENERIC
    end
    return string.lower(record.class)
end

--- Where the traveller has washed up, as something to call it.
--
-- A named cell names itself: "Balmora" out of doors, "Balmora, Guild of
-- Mages" for a guide's hall, which is the more useful of the two anyway. An
-- unnamed exterior -- the beach below Holamayan is the vanilla one -- has
-- only its region. Neither, and the frame says so without naming anywhere.
local function placeName()
    local cell = self.cell
    if cell == nil then
        return nil
    end
    if type(cell.name) == 'string' and cell.name ~= '' then
        return cell.name
    end
    if type(cell.region) == 'string' and cell.region ~= '' then
        return cell.region
    end
    return nil
end

--- The flavour line inside its frame: where you are, then what happened.
--
-- The frame is an l10n message rather than a concatenation here, so the line
-- break and the order of the two halves are a translator's to change.
local function framed(flavor)
    local place = placeName()
    local key = place and 'arrival' or 'arrivalUnplaced'
    local ok, text = pcall(l10n, key, { place = place, flavor = flavor })
    if ok and text and text ~= key then
        return text
    end
    -- No frame in this locale's file: the line alone still beats nothing.
    return flavor
end

--------------------------------------------------------------------------
-- Spotting the journey
--------------------------------------------------------------------------

-- The group to draw a line from when the traveller arrives, and the real time
-- after which the conversation that armed it is too old to have caused it.
local armedGroup = nil
local armedUntil = nil

-- Where the player was last seen, so arriving can be noticed without relying
-- on an engine handler that is not exercised anywhere else in this repo.
local lastCell = nil

-- A line waiting for the screen to settle, and when to show it.
local pendingText = nil
local showAt = nil

local function onUiModeChanged(data)
    if data == nil then
        return
    end
    out('mode -> %s (arg %s)', tostring(data.newMode), tostring(data.arg))

    -- The ticket window, which is the moment worth watching. Arming on the
    -- conversation instead would fire for anyone who asked a caravaner about
    -- rumours and then walked through a door; opening this means they are
    -- buying a journey. It carries the operator, so there is nothing to
    -- remember from the conversation before it.
    if data.newMode == 'Travel' then
        local group = travelGroupOf(data.arg)
        if group then
            out('armed: %s', group)
            armedGroup = group
            -- No deadline yet. The destination list is read for as long as
            -- the player likes, and the journey follows straight from it
            -- with no mode change in between.
            armedUntil = nil
        end
        return
    end

    -- Back in conversation with somebody: they closed the ticket window
    -- without buying. Arriving after a real journey also passes through
    -- Dialogue, but with no actor attached, which is what tells the two
    -- apart.
    if armedGroup and data.newMode == 'Dialogue' and data.arg then
        out('ticket window closed without travelling; disarming')
        armedGroup, armedUntil = nil, nil
        return
    end

    -- Everything closed. If a journey were happening it would have landed by
    -- now or be about to; anything later than the window is a door.
    if armedGroup and data.newMode == nil then
        armedUntil = core.getRealTime() + ARRIVAL_WINDOW
    end
end

--- Somewhere else, suddenly. Travel is not the only way that happens, which
-- is what the arming is for.
local function arrived()
    if armedGroup == nil then
        return
    end
    if armedUntil and core.getRealTime() > armedUntil then
        out('arrival too late to be the journey; forgetting')
        armedGroup, armedUntil = nil, nil
        return
    end

    local group = armedGroup
    armedGroup, armedUntil = nil, nil
    local text = lineFor(group) or lineFor(GENERIC)
    if text == nil then
        out('no line for %s and none generic either', group)
        return
    end
    out('arrived by %s', group)
    pendingText = framed(text)
    showAt = core.getRealTime() + SETTLE
end

local function onUpdate()
    local cell = self.cell
    local here = cell and cell.id or nil
    if here ~= lastCell then
        lastCell = here
        arrived()
    end

    if showAt and core.getRealTime() >= showAt then
        local text = pendingText
        pendingText, showAt = nil, nil
        ui.showMessage(text)
    end
end

return {
    engineHandlers = {
        onUpdate = onUpdate,
    },
    eventHandlers = {
        UiModeChanged = onUiModeChanged,
    },
}
