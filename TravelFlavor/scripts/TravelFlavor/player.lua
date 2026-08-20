-- Nothing in the engine announces "the player has travelled", so it is
-- inferred: a conversation with somebody who sells travel, followed shortly
-- by arriving somewhere else. Neither half is enough on its own.

local core = require('openmw.core')
local self = require('openmw.self')
local types = require('openmw.types')
local ui = require('openmw.ui')

local L10N = 'TravelFlavor'
local l10n = core.l10n(L10N, 'en')

-- Set true and the log says what the engine reports
local DEBUG = false

-- Lines that suit any journey, used when the operator's own class has none
-- written for it.
local GENERIC = 'generic'

-- Real seconds an arrival may lag the conversation closing before it stops
-- counting as the journey that conversation sold.
local ARRIVAL_WINDOW = 3.0

-- Real seconds to wait after arriving before saying anything.
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
-- `t_mw_riverstriderservice_1`.
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
-- first journey.
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

-- Who sells travel, and what kind
--
--- An actor's record, whether they are an NPC or a creature.
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
-- A creature has no class at all, and so falls back to generic lines.
local function travelGroupOf(actor)
    if actor == nil then
        return nil
    end
    local record = recordOf(actor)
    if record == nil then
        return nil
    end
    -- The one thing that actually says "this person sells travel". 
    -- Length, not type.
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
-- A named cell names itself. An unnamed exterior has only its region.
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
-- The frame is an l10n message rather than a concatenation here.
local function framed(flavor, place)
    place = place or placeName()
    local key = place and 'arrival' or 'arrivalUnplaced'
    local ok, text = pcall(l10n, key, { place = place, flavor = flavor })
    if ok and text and text ~= key then
        return text
    end
    return flavor
end

-- Spotting the journey
--
-- The group to draw a line from when the traveller arrives, and the real time
-- after which the conversation that armed it is too old to have caused it.
local armedGroup = nil
local armedUntil = nil

-- Where the player was last seen.
local lastCell = nil

-- A line waiting for the screen to settle, and when to show it.
local pendingText = nil
local showAt = nil

local function onUiModeChanged(data)
    if data == nil then
        return
    end
    out('mode -> %s (arg %s)', tostring(data.newMode), tostring(data.arg))

    if data.newMode == 'Travel' then
        local group = travelGroupOf(data.arg)
        if group then
            out('armed: %s', group)
            armedGroup = group
            -- No deadline yet
            armedUntil = nil
        end
        return
    end

    -- closed the travel window
    if armedGroup and data.newMode == 'Dialogue' and data.arg then
        out('ticket window closed without travelling; disarming')
        armedGroup, armedUntil = nil, nil
        return
    end

    -- Everything closed.
    if armedGroup and data.newMode == nil then
        armedUntil = core.getRealTime() + ARRIVAL_WINDOW
    end
end

--- Say something about a journey that has just ended.
local function announce(group, place)
    armedGroup, armedUntil = nil, nil
    if group == nil then
        return
    end
    local text = lineFor(group) or lineFor(GENERIC)
    if text == nil then
        out('no line for %s and none generic either', group)
        return
    end
    out('arrived by %s', group)
    pendingText = framed(text, place)
    showAt = core.getRealTime() + SETTLE
end

--- Somewhere else, suddenly.
local function arrived()
    if armedGroup == nil then
        return
    end
    if armedUntil and core.getRealTime() > armedUntil then
        out('arrival too late to be the journey; forgetting')
        armedGroup, armedUntil = nil, nil
        return
    end

    announce(armedGroup)
end

local function onUpdate()
    local cell = self.cell
    local here = cell and cell.id or nil
    if lastCell == nil then
        -- Nothing can be armed this early in practice
        lastCell = here
    elseif here ~= lastCell then
        lastCell = here
        arrived()
    end

    if showAt and core.getRealTime() >= showAt then
        local text = pendingText
        pendingText, showAt = nil, nil
        ui.showMessage(text)
    end
end

-- Adapters
--
-- A mod that adds travel through its own window never opens the
-- vanilla one, so nothing above sees them. Any that announces an
-- arrival can be handled here.

--- TravelAgents (optional). Sends the operator's class id rather than its
-- own vehicle vocabulary, so it maps onto a group here with no translation,
-- and the stop's name, which beats the cell we would otherwise land on.
local function onTravelAgentsArrived(data)
    if data == nil then
        return
    end
    local group = GENERIC
    if type(data.class) == 'string' and data.class ~= '' then
        group = string.lower(data.class)
    end
    local place = type(data.place) == 'string' and data.place ~= '' and data.place or nil
    out('TravelAgents arrived: class %s at %s', tostring(data.class), tostring(place))
    announce(group, place)
end

return {
    engineHandlers = {
        onUpdate = onUpdate,
    },
    eventHandlers = {
        UiModeChanged = onUiModeChanged,
        TravelAgentsArrived = onTravelAgentsArrived,
    },
}
