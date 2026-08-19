-- TravelNetwork -- player script: the keybind, the settings, the window.
--
-- Everything here is presentation. The graph and the routing live in the
-- global script; this asks for a plan and draws it, and holds no opinion
-- about what a good route is.
--
-- PLAYER context only.

local async = require('openmw.async')
local core = require('openmw.core')
local input = require('openmw.input')
local self = require('openmw.self')
local ui = require('openmw.ui')
local util = require('openmw.util')

local I = require('openmw.interfaces')

local events = require('scripts.TravelNetwork.events')
local plan = require('scripts.TravelNetwork.plan')

local L10N = 'TravelNetwork'
local PAGE = 'TravelNetwork'
local GROUP = 'SettingsPlayerTravelNetwork'
local TRIGGER = 'TravelNetworkPlanner'

local l10n = core.l10n(L10N, 'en')

-- How many destinations the window shows. Vanilla offers 32 from most stops,
-- which is more than fits on screen and more than anyone reads.
local SHOWN = 14

local window = nil
local expanded = nil
local current = nil

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
            default = 'TravelNetworkPlannerBinding',
            argument = { type = 'trigger', key = TRIGGER },
        },
    },
}

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

local function close()
    if window then
        window:destroy()
        window = nil
        expanded = nil
        I.UI.setMode()
    end
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
        if index > SHOWN then
            content[#content + 1] = text(l10n('andMore', { count = #current.stops - SHOWN }))
            break
        end
        content[#content + 1] = row(
            string.format('%s  --  %s', stop.name, plan.summarise(stop)),
            function() toggleExpanded(stop.key) end)
        if expanded == stop.key then
            for _, leg in ipairs(stop.legs) do
                content[#content + 1] = text('      ' .. plan.describeLeg(leg))
            end
        end
    end

    content[#content + 1] = { template = I.MWUI.templates.horizontalLine }
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
        I.UI.setMode('Interface', { windows = {} })
    end
end

--------------------------------------------------------------------------
-- Wiring
--------------------------------------------------------------------------

local function onPlan(data)
    if data == nil or data.origin == nil then
        -- Nothing to plan from: the player is somewhere the graph cannot
        -- measure, which is worth saying rather than opening an empty box.
        ui.showMessage(l10n('nowhereNearby'))
        return
    end
    current = data
    expanded = nil
    render()
end

local function toggle()
    if window then
        close()
        return
    end
    core.sendGlobalEvent(events.REQUEST_PLAN, { player = self.object })
end

input.registerTriggerHandler(TRIGGER, async:callback(toggle))

--- The player left interface mode, by whatever route. The window goes too:
-- an element left behind would sit over the game with no way to dismiss it.
local function onUiModeChanged(data)
    if window and data.newMode ~= 'Interface' then
        window:destroy()
        window = nil
        expanded = nil
    end
end

return {
    eventHandlers = {
        [events.PLAN] = onPlan,
        UiModeChanged = onUiModeChanged,
    },
}
