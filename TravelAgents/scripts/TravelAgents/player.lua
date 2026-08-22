-- Player script: keybinding, settings, planner window (PLAYER context only).

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

-- Two binding ids, one trigger: keyboard and controller both open planner.
local BINDING = 'TravelAgentsPlannerBinding'
local CONTROLLER_BINDING = 'TravelAgentsPlannerControllerBinding'
local BINDINGS_SECTION = 'OMWInputBindings'

-- Mouse button labels (engine defines keyboard keys).
local MOUSE_BUTTONS = { [1] = 'Left', [2] = 'Middle', [3] = 'Right', [4] = '4', [5] = '5' }

-- Controller buttons code->label (can't iterate userdata, must index).
-- Names match OpenMW Controls page; extends past engine's 16 buttons.
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
    -- Pcall: strict tables raise on unknown keys. Paddles/touchpad are 0.51+.
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
-- Which page of the destination list is showing. Paginated.
local page = 1
-- Which tab is open, as a number of changes of vehicle -- nil means every
-- stop. Opens on 0: the places reachable without changing are the ones
-- somebody standing at a travel service is usually asking about.
local tab = nil
-- The plan for the operator currently being talked to, fetched when the
-- conversation opens so the keypress has nothing to wait for.
local current = nil
-- Who is being talked to. Kept so a booking can name them.
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
            -- Value is binding id; argument is trigger (registered first).
            -- No default; player picks key on settings page.
            default = BINDING,
            argument = { type = 'trigger', key = TRIGGER },
        },
        {
            -- Second binding id for same trigger (controller & keyboard together).
            -- Renderer takes any input; controller players fill this row.
            key = 'plannerController',
            name = 'plannerController',
            description = 'plannerControllerDescription',
            renderer = 'inputBinding',
            default = CONTROLLER_BINDING,
            argument = { type = 'trigger', key = TRIGGER },
        },
    },
}

-- Surcharge settings: convenience cost in gold.
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

--- Convert percentage to fraction for fare calculation.
local function fraction(percent)
    if type(percent) ~= 'number' then
        return nil
    end
    return percent / 100
end

--- Player settings for fare calculation.
-- Routing penalties stay in config.lua (tie-breakers, not player-facing).
local function preferences()
    local fares = storage.playerSection(FARES)
    return {
        legSurcharge = fraction(fares:get('legSurcharge')),
        modeChangeSurcharge = fraction(fares:get('modeChangeSurcharge')),
    }
end

--- Binding label (human-readable) or nil if unbound.
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

--- Both bindings if both set (either opens planner).
-- @return label or nil
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

-- Two-pane window: places left, journey detail right.
local function text(content, template)
    return {
        template = template or I.MWUI.templates.textNormal,
        props = { text = content },
    }
end

--- Clickable UI row.
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

--- Character start positions in UTF-8 string (multi-byte names).
-- Lua 5.1 has no utf8; spot continuation bytes to avoid cutting chars.
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

--- Fit name to column width (truncate with ellipsis if needed).
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

--- Pad string to width in characters.
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

--- Which tab a journey belongs under.
local function bucketOf(stop)
    return plan.changeBucket(stop, config.MAX_CHANGE_TAB)
end

--- The buckets this plan actually fills, ascending, with their sizes.
-- Only occupied buckets get a tab.
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
    -- Fewest changes first.
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

--- Dialogue ended; clear planner state.
local function leaveDialogue()
    current = nil
    interlocutor = nil
    openWhenReady = false
    close()
end

--- Book journey (check affordability, then send to global).
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
-- Destination row with fare
local function stopRow(stop)
    local marker = (selected == stop.key) and '> ' or '  '
    local price = stop.fare > 0 and tostring(stop.fare) or '-'
    local label = string.format('%s%s %5s', marker,
        pad(fit(stop.name, config.NAME_COLUMN), config.NAME_COLUMN), price)
    return row(label, function() pick(stop.key) end)
end

--- Tab label for change-count bucket.
local function bucketLabel(bucket)
    if bucket == 0 then
        return l10n('tabDirect')
    end
    if bucket >= config.MAX_CHANGE_TAB then
        return l10n('tabChangesPlus', { changes = bucket })
    end
    return l10n('tabChanges', { changes = bucket })
end

--- Tabs by journey complexity (fewest changes first).
local function tabRow()
    local order, counts = tabsInPlan()
    if #order < 2 then
        -- One tab = furniture (everything reachable same way).
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

--- Destination list filling two columns, then paging.
-- Two-column layout (mainland has more destinations than one column holds).
-- Flows left column then right, maintaining cheapest-first order.
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

    -- Paging only shown when needed (vanilla never sees it).
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

-- Get chosen destination's details
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

--- Book button (greyed if unaffordable).
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
    -- Greyed instead of clickable+refused (answer is known).
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

--- Chosen journey details (destination, cost, button).
-- Condensed form of old right pane; per-leg detail collapses to via line.
local function footer()
    local stop = chosen()
    if stop == nil then
        return text(l10n('pickAStop'))
    end

    local rows = {}

    -- Destination and journey summary on one line.
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

    -- Intermediate stops as one line (better than per-leg breakdown).
    if #stop.legs > 1 then
        local via = {}
        for index = 1, #stop.legs - 1 do
            via[#via + 1] = stop.legs[index].to
        end
        rows[#rows + 1] = text(l10n('via', { places = table.concat(via, ', ') }))
    end

    -- Cost breakdown: base + surcharge (if any).
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

-- Assemble full window
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
        -- Replace contents only; preserve player-positioned window.
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
    -- fewest changes anywhere goes, although this should never occur.
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

-- Request plan for an operator
local function onTalk(actor)
    interlocutor = actor
    core.sendGlobalEvent(events.REQUEST_PLAN, {
        player = self.object, actor = actor, preferences = preferences(),
    })
end

--- Handle booking result (silent on success, messages on failure).
-- Arrival is silent (confirmation is obvious); refusal must say why.
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

-- Toggle planner window open/closed
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

--- Dialogue open/close controls planner availability.
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

    -- Other screen: planner closes but dialogue continues.
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
