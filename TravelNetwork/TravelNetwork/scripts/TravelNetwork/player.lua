-- TravelNetwork -- player script: the keybind, the settings, the window.
--
-- Everything here is presentation. The graph, the routing and the selling
-- live in the global script; this asks for a plan, draws it, and asks for a
-- journey when the player picks one. It holds no opinion about what a good
-- route is and no authority over what one costs.
--
-- The planner belongs to a conversation. Talking to a caravaner, shipmaster,
-- gondolier or guild guide is what makes it available -- asking the person who
-- drives the thing, rather than consulting a map in the middle of the street.
-- Outside such a conversation the key does nothing but explain itself.
--
-- Lua cannot add a dialogue topic; topics are DIAL records and live in content
-- files. What it can do is notice the conversation, which is what this does.
--
-- PLAYER context only.

local async = require('openmw.async')
local core = require('openmw.core')
local input = require('openmw.input')
local self = require('openmw.self')
local storage = require('openmw.storage')
local ui = require('openmw.ui')
local util = require('openmw.util')

local I = require('openmw.interfaces')

local config = require('scripts.TravelNetwork.config')
local events = require('scripts.TravelNetwork.events')
local money = require('scripts.TravelNetwork.money')
local plan = require('scripts.TravelNetwork.plan')

local L10N = 'TravelNetwork'
local PAGE = 'TravelNetwork'
local GROUP = 'SettingsPlayerTravelNetwork'
local ROUTING = 'SettingsPlayerTravelNetworkRouting'
local TRIGGER = 'TravelNetworkPlanner'

-- The id the binding is filed under. The settings entry stores this string,
-- and the engine keys the actual key press by it -- see the inputBinding
-- renderer in scripts/omw/input/settings.lua.
local BINDING = 'TravelNetworkPlannerBinding'
local BINDINGS_SECTION = 'OMWInputBindings'

-- The engine's own labels for these live in a local table in that file, so
-- the few that are not keyboard keys are spelled out again here.
local MOUSE_BUTTONS = { [1] = 'Left', [2] = 'Middle', [3] = 'Right', [4] = '4', [5] = '5' }

local l10n = core.l10n(L10N, 'en')

-- How many destinations the window shows. Vanilla offers 32 from most stops,
-- which is more than fits on screen and more than anyone reads.
local SHOWN = 14

local window = nil
local expanded = nil
-- Whether the list is showing everything or only the first SHOWN of it.
local showAll = false
-- The plan for the operator currently being talked to, fetched when the
-- conversation opens so the keypress has nothing to wait for.
local current = nil
-- Who is being talked to. Kept so a booking can name them: the global script
-- resolves the origin from the operator rather than trusting the window, and
-- this is the window's half of that.
local interlocutor = nil

--------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------

input.registerTrigger {
    key = TRIGGER,
    l10n = L10N,
    name = 'plannerKey',
    description = 'plannerKeyDescription',
}

I.Settings.registerPage {
    key = PAGE,
    l10n = L10N,
    name = 'settingsPage',
    description = 'settingsPageDescription',
}

I.Settings.registerGroup {
    key = GROUP,
    page = PAGE,
    l10n = L10N,
    name = 'plannerGroup',
    description = 'plannerGroupDescription',
    permanentStorage = true,
    settings = {
        {
            key = 'plannerKey',
            name = 'plannerKey',
            description = 'plannerKeyDescription',
            renderer = 'inputBinding',
            -- The value is the binding's own id; the argument names the
            -- trigger it fires, which is why that is registered first. No key
            -- is bound by default -- the player picks one on this page.
            default = BINDING,
            argument = { type = 'trigger', key = TRIGGER },
        },
    },
}

-- What a change is worth avoiding, in game units of detour -- the planner's
-- taste, which is why it is the player's to set. These do not change what a
-- leg costs in gold; they change which route the planner picks, and the fare
-- follows from that. Read when a conversation opens, so a change takes effect
-- at the next operator you talk to.
I.Settings.registerGroup {
    key = ROUTING,
    page = PAGE,
    l10n = L10N,
    name = 'routingGroup',
    description = 'routingGroupDescription',
    permanentStorage = true,
    settings = {
        {
            key = 'transferPenalty',
            name = 'transferPenalty',
            description = 'transferPenaltyDescription',
            renderer = 'number',
            default = config.TRANSFER_PENALTY,
            argument = { integer = true, min = 0, max = 100000 },
        },
        {
            key = 'modeChangePenalty',
            name = 'modeChangePenalty',
            description = 'modeChangePenaltyDescription',
            renderer = 'number',
            default = config.MODE_CHANGE_PENALTY,
            argument = { integer = true, min = 0, max = 100000 },
        },
    },
}

--- The routing preferences, as the global script's route options.
local function routing()
    local section = storage.playerSection(ROUTING)
    return {
        transferPenalty = section:get('transferPenalty'),
        modeChangePenalty = section:get('modeChangePenalty'),
    }
end

--------------------------------------------------------------------------
-- The keybind, as the player sees it
--------------------------------------------------------------------------

--- What key opens the planner, spelled the way the settings page spells it.
--
-- Read fresh each time rather than cached: the player can rebind it mid-game,
-- and a hint naming the old key is worse than one naming none.
--
-- @return the label, or nil when nothing is bound
local function boundKey()
    local id = storage.playerSection(GROUP):get('plannerKey') or BINDING
    local binding = storage.playerSection(BINDINGS_SECTION):get(id)
    if not binding or not binding.button then
        return nil
    end
    if binding.device == 'keyboard' then
        return input.getKeyName(binding.button)
    end
    if binding.device == 'mouse' then
        return string.format('Mouse %s', MOUSE_BUTTONS[binding.button] or binding.button)
    end
    if binding.device == 'controller' then
        return l10n('controllerButton')
    end
    return nil
end

--------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------

local function text(content, header)
    return {
        template = header and I.MWUI.templates.textHeader or I.MWUI.templates.textNormal,
        props = { text = content },
    }
end

--- A line the player can click. Rows are the only interactive thing in the
-- window: clicking one opens its legs, clicking it again closes them.
local function row(label, onClick)
    return {
        template = I.MWUI.templates.textNormal,
        props = { text = label },
        events = { mouseClick = async:callback(onClick) },
    }
end

--- Shut the planner, leaving the conversation as it was.
--
-- No mode juggling: the window only ever opens inside dialogue, which already
-- has a cursor and its own mode. Dropping modes here would end the
-- conversation the player opened the planner from.
local function close()
    if window then
        window:destroy()
        window = nil
        expanded = nil
        showAll = false
    end
end

--- The conversation is over: the planner it offered goes with it.
local function leaveDialogue()
    current = nil
    interlocutor = nil
    close()
end

--- Buy the journey and be taken on it.
--
-- The conversation is ended here, before the request goes out, because the
-- player is about to be somewhere else: a dialogue window left open on an
-- operator now a province away would follow them across the map. The global
-- script quotes the journey again before charging for it, so the check below
-- is a courtesy -- it keeps an unaffordable journey from closing the
-- conversation to say no -- and never the thing that decides.
local function bookTo(stop)
    local gold = money.held(self.object)
    if stop.fare > gold then
        ui.showMessage(l10n('cannotAfford', { fare = stop.fare, short = stop.fare - gold }))
        return
    end
    local operator = interlocutor
    leaveDialogue()
    I.UI.setMode()
    core.sendGlobalEvent(events.BOOK, {
        player = self.object, actor = operator, to = stop.key, routing = routing(),
    })
end

local render

local function toggleExpanded(key)
    expanded = (expanded ~= key) and key or nil
    render()
end

local function lines()
    local content = {}
    content[#content + 1] = text(l10n('windowTitle'), true)
    content[#content + 1] = text(l10n('from', { place = current.origin.name }))
    if #current.origin.modes > 0 then
        content[#content + 1] = text(l10n('servedBy', {
            modes = table.concat(current.origin.modes, ', '),
        }))
    end
    content[#content + 1] = { template = I.MWUI.templates.horizontalLine }

    if #current.stops == 0 then
        content[#content + 1] = text(l10n('nowhereToGo'))
    end

    for index, stop in ipairs(current.stops) do
        if index > SHOWN and not showAll then
            -- A line that only announced how much it was hiding, and did
            -- nothing about it, was the least useful thing in the window.
            content[#content + 1] = row(l10n('andMore', { count = #current.stops - SHOWN }),
                function() showAll = true render() end)
            break
        end
        local summaryKey, summaryArgs = plan.summarise(stop)
        content[#content + 1] = row(
            string.format('%s  --  %s', stop.name, l10n(summaryKey, summaryArgs)),
            function() toggleExpanded(stop.key) end)
        if expanded == stop.key then
            for _, leg in ipairs(stop.legs) do
                content[#content + 1] = text('      ' .. plan.describeLeg(leg))
            end
            -- A journey made entirely of walk legs has no fare, because a door
            -- charges nobody. Saying "0 gold" would read as a bug.
            local label = stop.fare > 0 and l10n('book', { fare = stop.fare }) or l10n('bookFree')
            content[#content + 1] = row('      ' .. label, function() bookTo(stop) end)
        end
    end

    content[#content + 1] = { template = I.MWUI.templates.horizontalLine }
    if showAll and #current.stops > SHOWN then
        content[#content + 1] = row(l10n('showFewer'), function() showAll = false render() end)
    end
    content[#content + 1] = row(l10n('close'), close)
    return content
end

render = function()
    if current == nil then
        return
    end
    local layout = {
        layer = 'Windows',
        template = I.MWUI.templates.boxSolid,
        props = { anchor = util.vector2(0.5, 0.5), relativePosition = util.vector2(0.5, 0.5) },
        content = ui.content {
            {
                type = ui.TYPE.Flex,
                props = { horizontal = false, arrange = ui.ALIGNMENT.Start },
                content = ui.content(lines()),
            },
        },
    }
    if window then
        window.layout = layout
        window:update()
    else
        window = ui.create(layout)
    end
end

--------------------------------------------------------------------------
-- Wiring
--------------------------------------------------------------------------

local function onPlan(data)
    if data == nil or data.origin == nil then
        -- Not an operator: a shopkeeper, a guard, anyone. Nothing to offer,
        -- and nothing to say either -- the player did not ask.
        current = nil
        return
    end
    current = data
    expanded = nil
    showAll = false
    local key = boundKey()
    if key then
        ui.showMessage(l10n('plannerHint', { key = key }))
    else
        -- Nothing bound, so nothing the player can press. Saying "ask about
        -- the network" here would be an instruction they cannot follow.
        ui.showMessage(l10n('plannerUnbound'))
    end
end

--- Talking to someone. Ask the global script whether they run anything; the
-- answer decides whether the key does anything for the length of this
-- conversation.
local function onTalk(actor)
    interlocutor = actor
    core.sendGlobalEvent(events.REQUEST_PLAN, {
        player = self.object, actor = actor, routing = routing(),
    })
end

--- What became of a booking. Every outcome says something: a refusal nobody
-- hears about is indistinguishable from a broken button.
local function onBooked(data)
    if data == nil then
        return
    end
    if data.ok then
        local hours = string.format('%.1f', data.hours or 0)
        if (data.fare or 0) > 0 then
            ui.showMessage(l10n('arrived', { place = data.place, hours = hours, fare = data.fare }))
        else
            ui.showMessage(l10n('arrivedFree', { place = data.place, hours = hours }))
        end
    elseif data.reason == 'gold' then
        ui.showMessage(l10n('cannotAfford', { fare = data.fare, short = data.short }))
    elseif data.reason == 'route' then
        ui.showMessage(l10n('noRoute'))
    else
        -- 'arrival' or 'operator': the journey could not be made at all, and
        -- neither has a cause the player can do anything about.
        ui.showMessage(l10n('bookingFailed'))
    end
end

local function toggle()
    if window then
        close()
        return
    end
    if current == nil then
        -- Pressed somewhere the planner has nothing to say. It says nothing:
        -- a key that answers back every time it is brushed in combat is worse
        -- than one that looks inert outside the conversation it belongs to.
        return
    end
    render()
end

input.registerTriggerHandler(TRIGGER, async:callback(toggle))

--- Dialogue opening is what offers the planner; dialogue closing withdraws it.
--
-- `arg` is the actor for the modes that have a target, which is how the mod
-- knows who is being talked to without touching the dialogue system itself.
local function onUiModeChanged(data)
    if data.newMode == 'Dialogue' and data.arg then
        onTalk(data.arg)
        return
    end
    if data.oldMode == 'Dialogue' then
        leaveDialogue()
    end
end

return {
    eventHandlers = {
        [events.PLAN] = onPlan,
        [events.BOOKED] = onBooked,
        UiModeChanged = onUiModeChanged,
    },
}
