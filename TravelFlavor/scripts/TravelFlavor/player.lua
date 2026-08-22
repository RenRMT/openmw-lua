-- PLAYER context only.
local core = require('openmw.core')
local self = require('openmw.self')
local types = require('openmw.types')
local ui = require('openmw.ui')

local L10N = 'TravelFlavor'
local l10n = core.l10n(L10N, 'en')

-- Set true and the log says what the engine reported at every step.
local DEBUG = false

-- Fallback lines that suit any journey.
local GENERIC = 'generic'

-- Real seconds an arrival may lag the conversation closing.
local ARRIVAL_WINDOW = 3.0

-- Real seconds to wait after arriving before saying anything.
local SETTLE = 0.5

-- So a gap in the numbering cannot spin the counting loop forever.
local MAX_LINES = 500

local function out(fmt, ...)
    if DEBUG then
        print('[TravelFlavor] ' .. string.format(fmt, ...))
    end
end

-- The lines
--
-- A group is an operator's class id, lowercased. Counted on first use.
-- A missing key may come back as the key, as nil or empty, or raise; all three
-- mean the numbering has run out.
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

--- Which group of lines describes travelling with this actor.
--
-- `record.class` is the class record id. Creatures have no class
-- and will fall back to generic. (Just one in TR)
local function travelGroupOf(actor)
    if actor == nil then
        return nil
    end
    local record = recordOf(actor)
    if record == nil then
        return nil
    end
    -- Length because engine hands these lists back as userdata.
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

-- Named cells provide specific context (e.g. "Balmora, Guild of Mages").
-- Unnamed exteriors fall back to region.
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

-- The frame is an l10n message. Line break and the order
-- have to be changed there.
local function framed(flavor, place)
    place = place or placeName()
    local key = place and 'arrival' or 'arrivalUnplaced'
    local ok, text = pcall(l10n, key, { place = place, flavor = flavor })
    if ok and text and text ~= key then
        return text
    end
    -- No frame in this locale's file: the line alone still beats nothing.
    return flavor
end

-- Spotting the journey
local armedGroup = nil
local armedUntil = nil
local lastCell = nil

local pendingText = nil
local showAt = nil

local function onUiModeChanged(data)
    if data == nil then
        return
    end
    out('mode -> %s (arg %s)', tostring(data.newMode), tostring(data.arg))

    -- Travel window is the moment worth watching.
    if data.newMode == 'Travel' then
        local group = travelGroupOf(data.arg)
        if group then
            out('armed: %s', group)
            armedGroup = group
            armedUntil = nil
        end
        return
    end

    -- Player closed the ticket window without buying.
    -- Travel also passes through Dialogue, but without actor attached.
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
-- Disarms on the way through, so a journey
-- spotted twice is still only spoken about once.
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

--- Somewhere else, suddenly. (Alone. Naked. )
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
        -- First frame: note without calling it an arrival.
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
-- Adapter mostly for my other mod TravelAgents.
-- Behavior is identical if the mod isn't installed.
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
