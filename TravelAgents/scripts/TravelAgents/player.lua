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
local FARES = 'SettingsPlayerTravelAgentsFares'
local TRIGGER = 'TravelAgentsPlanner'

-- The ids the bindings are filed under. Two of them, both firing the same
-- trigger: bindings are keyed by id rather than by what they fire, so a
-- keyboard key and a controller button can be bound at once and either one
-- opens the planner.
local BINDING = 'TravelAgentsPlannerBinding'
local CONTROLLER_BINDING = 'TravelAgentsPlannerControllerBinding'
local BINDINGS_SECTION = 'OMWInputBindings'

-- The engine's own labels for these live in a local table in that file, so
-- the few that are not keyboard keys are spelled out again here.
local MOUSE_BUTTONS = { [1] = 'Left', [2] = 'Middle', [3] = 'Right', [4] = '4', [5] = '5' }

-- Controller buttons, code to label.
--
-- Built by asking `input.CONTROLLER_BUTTON` for each name rather than by
-- iterating it: that table is read-only *userdata*, so `pairs` over it is an
-- error rather than an empty loop, and this runs at load. Indexing is what
-- the userdata is for.
--
-- The names match OpenMW's own Controls page so the two read alike, and the
-- list runs past the sixteenth button, which the engine's hand-written one
-- stops at.
local CONTROLLER_BUTTONS = {}
for name, label in pairs({
    A = 'A', B = 'B', X = 'X', Y = 'Y',
    Back = 'Back', Guide = 'Guide', Start = 'Start',
    LeftStick = 'Left Stick', RightStick = 'Right Stick',
    LeftShoulder = 'LB', RightShoulder = 'RB',
    DPadUp = 'D-pad Up', DPadDown = 'D-pad Down',
    DPadLeft = 'D-pad Left', DPadRight = 'D-pad Right',
    Misc1 = 'Misc 1', Touchpad = 'Touchpad',
    Paddle1 = 'Paddle 1', Paddle2 = 'Paddle 2',
    Paddle3 = 'Paddle 3', Paddle4 = 'Paddle 4',
}) do
    -- Behind a pcall because a read-only table can be the strict kind, which
    -- raises on a key it has never heard of. The paddles and the touchpad
    -- are 0.51 names; an older engine simply will not have them.
    local ok, code = pcall(function() return input.CONTROLLER_BUTTON[name] end)
    if ok and code ~= nil then
        CONTROLLER_BUTTONS[code] = label
    end
end

local l10n = core.l10n(L10N, 'en')

local window = nil
-- The place whose journey the right-hand pane is showing.
local selected = nil
-- Set when the key was pressed before a plan had arrived: open the window as
-- soon as one does, rather than making the player press again.
local openWhenReady = false
-- Which page of the destination list is showing. There is no scrollbar in
-- MWUI, so a list longer than the window is paged rather than clipped --
-- otherwise the tail is unreachable rather than merely out of sight.
local page = 1
-- Which tab is open, as a number of changes of vehicle -- nil means every
-- stop. Opens on 0: the places reachable without changing are the ones
-- somebody standing at a travel service is usually asking about.
local tab = nil
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
        {
            -- The same trigger under a second id, so a controller can reach
            -- the planner without giving up the keyboard key. The renderer
            -- records whatever is pressed, so this row will take a key as
            -- readily as a button -- it is the row a controller player fills
            -- in, not a row that refuses anything else.
            key = 'plannerController',
            name = 'plannerController',
            description = 'plannerControllerDescription',
            renderer = 'inputBinding',
            default = CONTROLLER_BINDING,
            argument = { type = 'trigger', key = TRIGGER },
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
-- answer: what the counter should charge.
--
-- The routing penalties are not here. They are tie-breakers between two
-- routes of near-equal cost, which is a thing the shipped network almost
-- never offers -- config.lua keeps them, and carries what measuring them
-- found.
local function preferences()
    local fares = storage.playerSection(FARES)
    return {
        legSurcharge = fraction(fares:get('legSurcharge')),
        modeChangeSurcharge = fraction(fares:get('modeChangeSurcharge')),
    }
end

--- What one binding reads as, or nil when that row is empty.
local function labelOf(settingKey, fallbackId)
    local id = storage.playerSection(GROUP):get(settingKey) or fallbackId
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
        return l10n('controllerButton',
            { button = CONTROLLER_BUTTONS[binding.button] or binding.button })
    end
    return nil
end

--- The keybind, as the player sees it.
-- Both rows if both are filled in, since either one opens the planner and a
-- hint naming only one of them is wrong for whoever bound the other.
-- @return the label, or nil when nothing is bound
local function boundKey()
    local labels = {}
    local keyboard = labelOf('plannerKey', BINDING)
    local controller = labelOf('plannerController', CONTROLLER_BINDING)
    if keyboard then
        labels[#labels + 1] = keyboard
    end
    if controller and controller ~= keyboard then
        labels[#labels + 1] = controller
    end
    if #labels == 0 then
        return nil
    end
    if #labels == 1 then
        return labels[1]
    end
    return l10n('eitherBinding', { first = labels[1], second = labels[2] })
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

--- Where each character of a UTF-8 string starts.
--
-- Names come out of the content files, and on a localised install they are
-- multi-byte: `#name` counts bytes, so a twelve-character Russian name reads
-- as twenty-four, gets cut to fit a column it already fitted, and is cut in
-- the middle of a character. Lua 5.1 has no utf8 library and a continuation
-- byte is the only thing that has to be spotted -- everything else begins
-- one character.
local function characterStarts(text)
    local starts = {}
    for index = 1, #text do
        local byte = string.byte(text, index)
        if byte < 128 or byte >= 192 then
            starts[#starts + 1] = index
        end
    end
    return starts
end

--- Names are as long as the game made them; the column is not.
local function fit(name, width)
    local starts = characterStarts(name)
    if #starts <= width then
        return name
    end
    -- Three of the columns go to the ellipsis.
    local cut = starts[math.max(width - 3, 1) + 1]
    if cut == nil then
        return name
    end
    return string.sub(name, 1, cut - 1) .. '...'
end

--- Pad to a column counted in characters, for the same reason.
local function pad(text, width)
    local short = width - #characterStarts(text)
    if short <= 0 then
        return text
    end
    return text .. string.rep(' ', short)
end

--- Shut the planner, leaving the conversation as it was.
local function close()
    if window then
        window:destroy()
        window = nil
        selected = nil
        page = 1
    end
end

--------------------------------------------------------------------------
-- Tabs, one per number of changes
--------------------------------------------------------------------------

--- Which tab a journey belongs under. The counting is the plan's, not the
-- window's, so anything else asking the same question gets the same answer.
local function bucketOf(stop)
    return plan.changeBucket(stop, config.MAX_CHANGE_TAB)
end

--- The buckets this plan actually fills, ascending, with their sizes.
--
-- Only occupied buckets get a tab: from a stop with nothing beyond one
-- change, a `3+` tab reading zero is furniture.
local function tabsInPlan()
    local counts, order = {}, {}
    for _, stop in ipairs(current.stops) do
        local bucket = bucketOf(stop)
        if counts[bucket] == nil then
            counts[bucket] = 0
            order[#order + 1] = bucket
        end
        counts[bucket] = counts[bucket] + 1
    end
    -- Fewest changes first. Unlike the networks this replaced there is a
    -- natural order here, and it is also the order of preference.
    table.sort(order)
    return order, counts
end

local function servesTab(stop, bucket)
    return bucket == nil or bucketOf(stop) == bucket
end

local function stopsInTab()
    local out = {}
    for _, stop in ipairs(current.stops) do
        if servesTab(stop, tab) then
            out[#out + 1] = stop
        end
    end
    return out
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
    local label = string.format('%s%s %5s', marker,
        pad(fit(stop.name, config.NAME_COLUMN), config.NAME_COLUMN), price)
    return row(label, function() pick(stop.key) end)
end

--- What to call a bucket on its tab.
local function bucketLabel(bucket)
    if bucket == 0 then
        return l10n('tabDirect')
    end
    if bucket >= config.MAX_CHANGE_TAB then
        return l10n('tabChangesPlus', { changes = bucket })
    end
    return l10n('tabChanges', { changes = bucket })
end

--- One tab per number of changes a journey needs, fewest first.
local function tabRow()
    local order, counts = tabsInPlan()
    if #order < 2 then
        -- Everything reachable the same way: a row of one tab is furniture.
        return nil
    end

    local buttons = {}
    local function tabButton(bucket, label, count)
        local caption = string.format(' %s %d ', label, count)
        if bucket == tab then
            return {
                template = I.MWUI.templates.box,
                content = ui.content { text(caption, I.MWUI.templates.textHeader) },
            }
        end
        return {
            template = I.MWUI.templates.box,
            content = ui.content { row(caption, function()
                tab = bucket
                selected = nil
                page = 1
                render()
            end) },
        }
    end

    for _, bucket in ipairs(order) do
        buttons[#buttons + 1] = tabButton(bucket, bucketLabel(bucket), counts[bucket])
    end
    buttons[#buttons + 1] = tabButton(nil, l10n('tabAll'), #current.stops)

    -- One row, and no wrapping. The tabs are the buckets this plan fills
    -- plus *All*, and MAX_CHANGE_TAB collects everything past it -- five
    -- buttons at the very most, which fit across the window.
    local strip = {}
    for _, button in ipairs(buttons) do
        strip[#strip + 1] = button
        strip[#strip + 1] = { template = I.MWUI.templates.interval }
    end

    return {
        type = ui.TYPE.Flex,
        props = { horizontal = true, arrange = ui.ALIGNMENT.Start },
        content = ui.content(strip),
    }
end

--- The destination list, filling one column and then the next.
--
-- Both halves of the window are the list now. What used to sit on the right
-- -- the legs of the chosen journey, one per line -- is a strip along the
-- bottom instead, because a load order with a mainland in it has far more
-- destinations than a single column can hold and the leg list was the only
-- thing in the window that could afford to shrink.
--
-- Flowed down the left column and then down the right, so the list still
-- reads cheapest-first in the order the router returned.
local function destinations()
    local stops = stopsInTab()
    local capacity = config.ROWS_PER_COLUMN * 2
    local pages = math.max(1, math.ceil(#stops / capacity))
    if page > pages then
        page = pages
    end

    local first = (page - 1) * capacity + 1
    local last = math.min(first + capacity - 1, #stops)

    local columns = { {}, {} }
    for index = first, last do
        local which = ((index - first) < config.ROWS_PER_COLUMN) and 1 or 2
        local into = columns[which]
        into[#into + 1] = stopRow(stops[index])
    end

    if #stops == 0 then
        columns[1][1] = text(l10n(tab and 'nowhereWithThisManyChanges' or 'nowhereToGo'))
    end

    local function pane(rows)
        return {
            type = ui.TYPE.Flex,
            props = {
                horizontal = false,
                arrange = ui.ALIGNMENT.Start,
                autoSize = false,
                size = util.vector2(config.COLUMN_WIDTH, config.LIST_HEIGHT),
            },
            content = ui.content(rows),
        }
    end

    local grid = {
        type = ui.TYPE.Flex,
        props = { horizontal = true, arrange = ui.ALIGNMENT.Start },
        content = ui.content {
            pane(columns[1]),
            { template = I.MWUI.templates.interval },
            pane(columns[2]),
        },
    }

    local body = grid

    if pages < 2 then
        return body
    end

    -- Paging only appears when it is needed, so vanilla never sees it.
    local controls = {}
    if page > 1 then
        controls[#controls + 1] = row(l10n('pagePrev'), function() page = page - 1 render() end)
        controls[#controls + 1] = { template = I.MWUI.templates.interval }
    end
    controls[#controls + 1] = text(l10n('pageOf', { page = page, pages = pages }))
    if page < pages then
        controls[#controls + 1] = { template = I.MWUI.templates.interval }
        controls[#controls + 1] = row(l10n('pageNext'), function() page = page + 1 render() end)
    end

    return {
        type = ui.TYPE.Flex,
        props = { horizontal = false, arrange = ui.ALIGNMENT.Start },
        content = ui.content {
            body,
            {
                type = ui.TYPE.Flex,
                props = { horizontal = true, arrange = ui.ALIGNMENT.Start },
                content = ui.content(controls),
            },
        },
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

--- Everything about the chosen journey, in a strip a few lines deep.
--
-- The condensed form of what used to be the right-hand pane: where you are
-- going, what it asks of you, what it costs and the button. The per-leg
-- breakdown collapses to one "via" line -- the intermediate stops are the
-- part of it a traveller actually reads.
local function footer()
    local stop = chosen()
    if stop == nil then
        return text(l10n('pickAStop'))
    end

    local rows = {}

    -- Where, and what it asks of you, on one line.
    local heading = stop.name
    if stop.arrival and stop.arrival ~= stop.name then
        heading = l10n('arrivingAt', { place = stop.arrival })
    end
    rows[#rows + 1] = {
        type = ui.TYPE.Flex,
        props = { horizontal = true, arrange = ui.ALIGNMENT.Start },
        content = ui.content {
            text(heading, I.MWUI.templates.textHeader),
            { template = I.MWUI.templates.interval },
            text(l10n(plan.summarise(stop))),
        },
    }

    -- The legs, as the places they pass through rather than a line each.
    if #stop.legs > 1 then
        local via = {}
        for index = 1, #stop.legs - 1 do
            via[#via + 1] = stop.legs[index].to
        end
        rows[#rows + 1] = text(l10n('via', { places = table.concat(via, ', ') }))
    end

    -- What it costs, broken into the parts the player is being charged.
    local fare = l10n('fareLine', { base = stop.baseFare })
    if (stop.surcharge or 0) > 0 then
        fare = fare .. '  ' .. l10n('surchargeLine', {
            percent = stop.surchargePercent, extra = stop.surcharge,
        })
    end

    local buttons = { text(fare), { template = I.MWUI.templates.interval } }
    for _, entry in ipairs(bookButton(stop)) do
        buttons[#buttons + 1] = entry
        buttons[#buttons + 1] = { template = I.MWUI.templates.interval }
    end
    rows[#rows + 1] = {
        type = ui.TYPE.Flex,
        props = { horizontal = true, arrange = ui.ALIGNMENT.Start },
        content = ui.content(buttons),
    }

    return {
        type = ui.TYPE.Flex,
        props = {
            horizontal = false,
            arrange = ui.ALIGNMENT.Start,
            autoSize = false,
            size = util.vector2(config.WINDOW_WIDTH - 40, config.FOOTER_HEIGHT),
        },
        content = ui.content(rows),
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
                    -- Full width, above both panes: the tabs choose what the
                    -- left one lists, and there is no room for six of them
                    -- inside its column.
                    tabRow() or { template = I.MWUI.templates.interval },
                    destinations(),
                    line(),
                    footer(),
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
        -- Whoever this is sells no journeys, so there is nothing to open.
        -- Leaving the flag armed would spring the window open on the next
        -- plan that does arrive, which nobody asked for.
        openWhenReady = false
        return
    end
    -- A plan already in hand means this is the same conversation resumed
    local resumed = current ~= nil
    current = data
    selected = nil
    page = 1

    -- Open on the places reachable without changing vehicle: standing in
    -- front of a driver, that is the question being asked. Falls back to the
    -- fewest changes anywhere goes, so a stop whose every destination needs
    -- a transfer opens on a tab with something in it rather than an empty
    -- one.
    if not resumed then
        current.stops = current.stops or {}
        local order = tabsInPlan()
        tab = order[1]
    end

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
--
-- Only when it went wrong. Arriving says nothing: the window has already
-- shown where, how long and what it costs, and the traveller standing
-- somewhere else with less gold is its own confirmation -- which is all
-- vanilla does. A refusal is different, because a booking that fails in
-- silence reads as a bug.
--
-- The quiet arrival is also what leaves room for a mod that has something
-- more interesting to say about the journey.
local function onBooked(data)
    if data == nil or data.ok then
        return
    end
    if data.reason == 'gold' then
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
