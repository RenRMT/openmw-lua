-- TravelAgents -- player script: the keybind, the settings, the window.
-- PLAYER context only.

local async = require('openmw.async')
local core = require('openmw.core')
local input = require('openmw.input')
local self = require('openmw.self')
local storage = require('openmw.storage')
local ui = require('openmw.ui')
local util = require('openmw.util')

local I = require('openmw.interfaces')

local config = require('scripts.TravelAgents.config')
local events = require('scripts.TravelAgents.events')
local money = require('scripts.TravelAgents.money')
local plan = require('scripts.TravelAgents.plan')
local restore = require('scripts.TravelAgents.restore')

local L10N = 'TravelAgents'
local PAGE = 'TravelAgents'
local GROUP = 'SettingsPlayerTravelAgents'
local ROUTING = 'SettingsPlayerTravelAgentsRouting'
local FARES = 'SettingsPlayerTravelAgentsFares'
local TRIGGER = 'TravelAgentsPlanner'

-- The id the binding is filed under.
local BINDING = 'TravelAgentsPlannerBinding'
local BINDINGS_SECTION = 'OMWInputBindings'

-- The engine's own labels for these live in a local table in that file, so
-- the few that are not keyboard keys are spelled out again here.
local MOUSE_BUTTONS = { [1] = 'Left', [2] = 'Middle', [3] = 'Right', [4] = '4', [5] = '5' }

local l10n = core.l10n(L10N, 'en')

local window = nil
-- The place whose journey the right-hand pane is showing.
local selected = nil
-- Set when the key was pressed before a plan had arrived: open the window as
-- soon as one does, rather than making the player press again.
local openWhenReady = false
-- Whether the list is showing everything or only the first SHOWN_STOPS of it.
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

-- What a change is worth avoiding, in game units of detour.
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

-- What the convenience is worth in gold.
I.Settings.registerGroup {
    key = FARES,
    page = PAGE,
    l10n = L10N,
    name = 'faresGroup',
    description = 'faresGroupDescription',
    permanentStorage = true,
    settings = {
        {
            key = 'legSurcharge',
            name = 'legSurcharge',
            description = 'legSurchargeDescription',
            renderer = 'number',
            default = config.FARE_LEG_SURCHARGE * 100,
            argument = { integer = true, min = 0, max = 200 },
        },
        {
            key = 'modeChangeSurcharge',
            name = 'modeChangeSurcharge',
            description = 'modeChangeSurchargeDescription',
            renderer = 'number',
            default = config.FARE_MODE_CHANGE_SURCHARGE * 100,
            argument = { integer = true, min = 0, max = 200 },
        },
    },
}

--- A percentage as the fraction the fare arithmetic works in.
local function fraction(percent)
    if type(percent) ~= 'number' then
        return nil
    end
    return percent / 100
end

--- Everything the player has set that the global script needs in order to
-- answer: what the planner should avoid, and what the counter should charge.
local function preferences()
    local routing = storage.playerSection(ROUTING)
    local fares = storage.playerSection(FARES)
    return {
        transferPenalty = routing:get('transferPenalty'),
        modeChangePenalty = routing:get('modeChangePenalty'),
        legSurcharge = fraction(fares:get('legSurcharge')),
        modeChangeSurcharge = fraction(fares:get('modeChangeSurcharge')),
    }
end

-- The keybind, as the player sees it
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

-- Two window panes: the list of places on the left, the journey to the one you
-- picked on the right.
local function text(content, template)
    return {
        template = template or I.MWUI.templates.textNormal,
        props = { text = content },
    }
end

--- A line the player can click.
local function row(label, onClick)
    return {
        template = I.MWUI.templates.textNormal,
        props = { text = label },
        events = { mouseClick = async:callback(onClick) },
    }
end

local function line()
    return { template = I.MWUI.templates.horizontalLine }
end

--- Names are as long as the game made them; the column is not.
local function fit(name, width)
    if #name <= width then
        return name
    end
    return string.sub(name, 1, width - 3) .. '...'
end

--- Shut the planner, leaving the conversation as it was.
local function close()
    if window then
        window:destroy()
        window = nil
        selected = nil
        showAll = false
    end
end

--- The conversation is over: the planner it offered goes with it.
local function leaveDialogue()
    current = nil
    interlocutor = nil
    openWhenReady = false
    close()
end

--- Buy the journey and be taken on it.
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
        player = self.object, actor = operator, to = stop.key, preferences = preferences(),
    })
end

local render

local function pick(key)
    selected = key
    render()
end


-- The list of places
local function stopRow(stop)
    local marker = (selected == stop.key) and '> ' or '  '
    local price = stop.fare > 0 and tostring(stop.fare) or '-'
    local label = string.format('%s%-' .. config.NAME_COLUMN .. 's %5s',
        marker, fit(stop.name, config.NAME_COLUMN), price)
    return row(label, function() pick(stop.key) end)
end

--- The places, split by what the journey asks of the traveller.
local function master()
    local shown = showAll and #current.stops or math.min(#current.stops, config.SHOWN_STOPS)
    local direct, changing = {}, {}
    for index = 1, shown do
        local stop = current.stops[index]
        local into = ((stop.modeChanges or 0) > 0) and changing or direct
        into[#into + 1] = stopRow(stop)
    end

    local content = {}
    local function section(title, rows)
        if #rows == 0 then
            return
        end
        content[#content + 1] = text(title, I.MWUI.templates.textHeader)
        for _, entry in ipairs(rows) do
            content[#content + 1] = entry
        end
        content[#content + 1] = { template = I.MWUI.templates.interval }
    end

    if #current.stops == 0 then
        content[#content + 1] = text(l10n('nowhereToGo'))
    end
    section(l10n('sectionDirect'), direct)
    section(l10n('sectionChanging'), changing)

    if shown < #current.stops then
        content[#content + 1] = row(l10n('andMore', { count = #current.stops - shown }),
            function() showAll = true render() end)
    elseif showAll and #current.stops > config.SHOWN_STOPS then
        content[#content + 1] = row(l10n('showFewer'), function() showAll = false render() end)
    end

    return {
        type = ui.TYPE.Flex,
        props = {
            horizontal = false,
            arrange = ui.ALIGNMENT.Start,
            autoSize = false,
            size = util.vector2(config.MASTER_WIDTH, config.WINDOW_HEIGHT - 90),
        },
        content = ui.content(content),
    }
end

-- The journey to the place you picked
local function chosen()
    if selected == nil then
        return nil
    end
    for _, stop in ipairs(current.stops) do
        if stop.key == selected then
            return stop
        end
    end
    return nil
end

--- The button, and the reason it is greyed out when it is.
local function bookButton(stop)
    local gold = money.held(self.object)
    local label = stop.fare > 0 and l10n('book', { fare = stop.fare }) or l10n('bookFree')
    if gold >= stop.fare then
        return {
            {
                template = I.MWUI.templates.box,
                content = ui.content { row(' ' .. label .. ' ', function() bookTo(stop) end) },
            },
        }
    end
    -- Shaded and unclickable rather than clickable and refused: the answer is
    -- already known, and finding it out by being told off is worse.
    return {
        {
            template = I.MWUI.templates.disabled,
            content = ui.content {
                { template = I.MWUI.templates.box, content = ui.content { text(' ' .. label .. ' ') } },
            },
        },
        text(l10n('youHave', { gold = gold })),
    }
end

local function detail()
    local stop = chosen()
    local content = {}
    if stop == nil then
        content[#content + 1] = text(l10n('pickAStop'))
    else
        content[#content + 1] = text(stop.name, I.MWUI.templates.textHeader)
        content[#content + 1] = text(l10n(plan.summarise(stop)))
        -- The row is named after the town
        if stop.arrival and stop.arrival ~= stop.name then
            content[#content + 1] = text(l10n('arrivingAt', { place = stop.arrival }))
        end
        content[#content + 1] = line()
        for _, leg in ipairs(stop.legs) do
            content[#content + 1] = text('  ' .. plan.describeLeg(leg))
        end
        content[#content + 1] = line()
        content[#content + 1] = text(l10n('fareLine', { base = stop.baseFare }))
        if (stop.surcharge or 0) > 0 then
            content[#content + 1] = text(l10n('surchargeLine', {
                percent = stop.surchargePercent, extra = stop.surcharge,
            }))
        end
        content[#content + 1] = { template = I.MWUI.templates.interval }
        for _, entry in ipairs(bookButton(stop)) do
            content[#content + 1] = entry
        end
    end

    return {
        type = ui.TYPE.Flex,
        props = {
            horizontal = false,
            arrange = ui.ALIGNMENT.Start,
            autoSize = false,
            size = util.vector2(config.WINDOW_WIDTH - config.MASTER_WIDTH - 40,
                config.WINDOW_HEIGHT - 90),
        },
        content = ui.content(content),
    }
end

-- Putting it together
local function body()
    local heading = current.origin.name
    if #current.origin.modes > 0 then
        heading = string.format('%s -- %s', heading, table.concat(current.origin.modes, ', '))
    end

    return {
        template = I.MWUI.templates.boxSolid,
        content = ui.content {
            {
                type = ui.TYPE.Flex,
                props = { horizontal = false, arrange = ui.ALIGNMENT.Start },
                content = ui.content {
                    text(l10n('from', { place = heading }), I.MWUI.templates.textHeader),
                    line(),
                    {
                        type = ui.TYPE.Flex,
                        props = { horizontal = true, arrange = ui.ALIGNMENT.Start },
                        content = ui.content {
                            master(),
                            { template = I.MWUI.templates.verticalLine },
                            { template = I.MWUI.templates.interval },
                            detail(),
                        },
                    },
                    line(),
                    row(l10n('close'), close),
                },
            },
        },
    }
end

render = function()
    if current == nil then
        return
    end
    if window then
        -- Only the contents are replaced. The window's own position is left
        -- alone, because the player may have dragged it somewhere they want it
        -- and re-applying the props would snap it back to the middle.
        window.layout.content = ui.content { body() }
        window:update()
        return
    end
    window = ui.create {
        layer = 'Windows',
        type = ui.TYPE.Window,
        props = {
            size = util.vector2(config.WINDOW_WIDTH, config.WINDOW_HEIGHT),
            anchor = util.vector2(0.5, 0.5),
            relativePosition = util.vector2(0.5, 0.5),
        },
        content = ui.content { body() },
    }
end

-- Wiring
local function onPlan(data)
    if data == nil or data.origin == nil then
        current = nil
        return
    end
    -- A plan already in hand means this is the same conversation resumed
    local resumed = current ~= nil
    current = data
    selected = nil
    showAll = false

    if openWhenReady then
        openWhenReady = false
        render()
        return
    end
    if resumed then
        return
    end

    local key = boundKey()
    if key then
        ui.showMessage(l10n('plannerHint', { key = key }))
    else
        ui.showMessage(l10n('plannerUnbound'))
    end
end

local function onTalk(actor)
    interlocutor = actor
    core.sendGlobalEvent(events.REQUEST_PLAN, {
        player = self.object, actor = actor, preferences = preferences(),
    })
end

--- What became of a booking.
local function onBooked(data)
    if data == nil then
        return
    end
    if data.ok then
        local hours = string.format('%.1f', data.hours or 0)
        local paid = (data.fare or 0) > 0
        if (data.hours or 0) <= 0 then
            -- A guild guide puts you down at the hour you left. "0.0 hours
            -- on the road" is technically true and reads as a bug.
            ui.showMessage(l10n(paid and 'arrivedInstantly' or 'arrivedInstantlyFree',
                { place = data.place, fare = data.fare }))
        elseif paid then
            ui.showMessage(l10n('arrived', { place = data.place, hours = hours, fare = data.fare }))
        else
            ui.showMessage(l10n('arrivedFree', { place = data.place, hours = hours }))
        end
    elseif data.reason == 'gold' then
        ui.showMessage(l10n('cannotAfford', { fare = data.fare, short = data.short }))
    elseif data.reason == 'route' then
        ui.showMessage(l10n('noRoute'))
    else
        ui.showMessage(l10n('bookingFailed'))
    end
end

--- Put the traveller back together, in the one context allowed to.
local function onRestore(data)
    restore.afterJourney(self.object, data and data.rests)
end

local function toggle()
    if window then
        close()
        return
    end
    if current == nil then
        -- Still talking to someone, but with no plan in hand:
        if interlocutor and I.UI.getMode() == 'Dialogue' then
            openWhenReady = true
            onTalk(interlocutor)
        end
        return
    end
    render()
end

input.registerTriggerHandler(TRIGGER, async:callback(toggle))

--- Dialogue opening is what offers the planner; dialogue *ending* withdraws
-- it.
local function onUiModeChanged(data)
    if data.newMode == 'Dialogue' then
        if data.arg then
            onTalk(data.arg)
        elseif interlocutor and current == nil then
            -- Resumed without being told who by. The engine names the actor
            -- when a conversation opens; it need not name them again.
            onTalk(interlocutor)
        end
        return
    end

    -- Something else owns the screen. The planner goes away with it, but the
    -- conversation underneath does not: only every window closing ends that.
    close()
    if data.newMode == nil then
        leaveDialogue()
    end
end

return {
    eventHandlers = {
        [events.PLAN] = onPlan,
        [events.BOOKED] = onBooked,
        [events.RESTORE] = onRestore,
        UiModeChanged = onUiModeChanged,
    },
}
