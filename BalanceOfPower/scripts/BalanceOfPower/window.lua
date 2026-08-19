-- The tribute window: what every faction is worth, and what yours cost.
--
-- PLAYER context only. Two columns, and the split is the point of the
-- screen: the left is the whole world's standings, which the player can
-- only watch, and the right is the short list they can actually do
-- something about -- the factions that count them a member.
--
-- Nothing here reaches the framework directly. The interface is
-- global-context only, so this asks with BoP_RequestSnapshot and pays
-- with BoP_PayTribute, exactly as any third-party mod would have to.
-- The arithmetic it shows is core/tribute.lua's, so the number on the
-- button and the number the global script awards cannot drift apart.

local async = require('openmw.async')
local core = require('openmw.core')
local input = require('openmw.input')
local self = require('openmw.self')
local types = require('openmw.types')
local ui = require('openmw.ui')
local util = require('openmw.util')

local I = require('openmw.interfaces')

local config = require('scripts.BalanceOfPower.core.config')
local eventnames = require('scripts.BalanceOfPower.core.eventnames')
local gold = require('scripts.BalanceOfPower.core.gold')
local settings = require('scripts.BalanceOfPower.core.settings')
local tribute = require('scripts.BalanceOfPower.core.tribute')

local l10n = core.l10n(config.L10N_CONTEXT, 'en')

local GROUP = 'SettingsPlayerBalanceOfPowerWindow'
local TRIGGER = 'BalanceOfPowerWindow'

local window = nil
-- The last snapshot the framework sent. nil until one arrives, which is
-- why a key press asks for one rather than assuming it has one.
local standings = nil
-- Set when the key was pressed before a snapshot had arrived: show the
-- window as soon as one does, rather than making the player press again.
local openWhenReady = false

--------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------

input.registerTrigger {
    key = TRIGGER,
    l10n = config.L10N_CONTEXT,
    name = 'windowKey',
    description = 'windowKeyDescription',
}

if I.Settings then
    -- The page as well as the group. Which context loads first is not
    -- something to rely on, and registering a page twice costs nothing.
    settings.registerPage(I)
    I.Settings.registerGroup {
        key = GROUP,
        page = config.SETTINGS_PAGE,
        l10n = config.L10N_CONTEXT,
        name = 'windowGroup',
        description = 'windowGroupDescription',
        permanentStorage = true,
        settings = {
            {
                key = 'windowKey',
                name = 'windowKey',
                description = 'windowKeyDescription',
                -- Nothing is bound by default: a framework has no business
                -- claiming a key the player has plans for.
                default = '',
                renderer = 'inputBinding',
                argument = { key = TRIGGER, type = 'trigger' },
            },
        },
    }
end

--------------------------------------------------------------------------
-- Reading the player
--------------------------------------------------------------------------

--- The factions the player belongs to, keyed by the record id the engine
-- knows them under, carrying the rank and how long that ladder is.
--
-- Keyed lowercase because the two sides spell ids differently: the
-- framework registers "sixth house" and the records answer "Sixth House".
local function membership()
    local out = {}
    for _, recordId in ipairs(types.NPC.getFactions(self.object) or {}) do
        local record = core.factions.records[recordId]
        local rank = types.NPC.getFactionRank(self.object, recordId) or 0
        local ranks = record and record.ranks or nil
        out[string.lower(recordId)] = {
            rank = rank,
            rankCount = (ranks and #ranks) or 1,
            rankName = ranks and ranks[rank] or nil,
        }
    end
    return out
end

--------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------

local function text(content, template)
    return {
        template = template or I.MWUI.templates.textNormal,
        props = { text = content },
    }
end

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

local function column(content)
    return {
        type = ui.TYPE.Flex,
        props = { horizontal = false, arrange = ui.ALIGNMENT.Start },
        content = ui.content(content),
    }
end

--- Names are as long as the game made them; the column is not.
local function fit(name, width)
    if #name <= width then
        return name .. string.rep(' ', width - #name)
    end
    return string.sub(name, 1, width - 1) .. '.'
end

-- A clickable amount, or the same amount greyed out when the player
-- cannot afford it. Disabled rather than hidden, so the player can see
-- what the next tier up would cost them.
local function amountButton(factionId, amount, affordable, onPay)
    local label = ' ' .. tostring(amount) .. ' '
    if not affordable then
        return {
            template = I.MWUI.templates.disabled,
            content = ui.content {
                { template = I.MWUI.templates.box, content = ui.content { text(label) } },
            },
        }
    end
    return {
        template = I.MWUI.templates.box,
        content = ui.content { row(label, function() onPay(factionId, amount) end) },
    }
end

--------------------------------------------------------------------------
-- The two columns
--------------------------------------------------------------------------

local payTribute

--- Left: every faction the framework knows, strongest first.
local function standingsColumn()
    local content = { text(l10n('standingsHeading'), I.MWUI.templates.textHeader), line() }

    if standings == nil or #standings == 0 then
        content[#content + 1] = text(l10n('noStandings'))
        return column(content)
    end

    local shown = 0
    for _, faction in ipairs(standings) do
        if shown >= config.WINDOW_MAX_STANDINGS then
            content[#content + 1] = text(l10n('andMore', { count = #standings - shown }))
            break
        end
        shown = shown + 1
        -- Padded rather than laid out in a grid: MWUI has no table widget,
        -- and a padded string is honest about that where nested Flex rows
        -- that almost line up are not.
        content[#content + 1] = text(string.format('%s %7.1f',
            fit(faction.displayName or faction.id, 22), faction.power or 0))
    end
    return column(content)
end

--- Right: the factions that count the player a member, and what a
-- payment to each would buy.
local function tributeColumn()
    local held = gold.held(self.object)
    local content = {
        text(l10n('tributeHeading'), I.MWUI.templates.textHeader),
        line(),
        text(l10n('goldHeld', { gold = held })),
        { template = I.MWUI.templates.interval },
    }

    local mine = membership()
    local any = false

    for _, faction in ipairs(standings or {}) do
        local member = mine[string.lower(faction.recordId or faction.id)]
        if member and member.rank >= 1 then
            any = true
            content[#content + 1] = text(faction.displayName or faction.id,
                I.MWUI.templates.textHeader)
            if member.rankName then
                content[#content + 1] = text(l10n('rankLine', { rank = member.rankName }))
            end

            -- What the smallest offer buys, so the rank multiplier is
            -- visible rather than something the player has to infer from
            -- results they cannot see.
            local sample = config.TRIBUTE_AMOUNTS[1] or 1
            content[#content + 1] = text(l10n('tributeRate', {
                gold = sample,
                power = string.format('%.1f',
                    tribute.powerFor(sample, member.rank, member.rankCount)),
            }))

            local buttons = {}
            for _, amount in ipairs(config.TRIBUTE_AMOUNTS) do
                buttons[#buttons + 1] =
                    amountButton(faction.id, amount, held >= amount, payTribute)
                buttons[#buttons + 1] = { template = I.MWUI.templates.interval }
            end
            content[#content + 1] = {
                type = ui.TYPE.Flex,
                props = { horizontal = true, arrange = ui.ALIGNMENT.Start },
                content = ui.content(buttons),
            }
            content[#content + 1] = { template = I.MWUI.templates.interval }
        end
    end

    if not any then
        content[#content + 1] = text(l10n('noMemberships'))
    end
    return column(content)
end

--------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------

local render
local close

local function body()
    return {
        template = I.MWUI.templates.boxSolid,
        content = ui.content {
            column {
                text(l10n('windowTitle'), I.MWUI.templates.textHeader),
                line(),
                {
                    type = ui.TYPE.Flex,
                    props = { horizontal = true, arrange = ui.ALIGNMENT.Start },
                    content = ui.content {
                        standingsColumn(),
                        { template = I.MWUI.templates.interval },
                        { template = I.MWUI.templates.verticalLine },
                        { template = I.MWUI.templates.interval },
                        tributeColumn(),
                    },
                },
                line(),
                row(l10n('close'), function() close() end),
            },
        },
    }
end

render = function()
    if window then
        -- Only the contents are replaced. The window's own position is
        -- left alone, because the player may have dragged it somewhere
        -- they want it and re-applying the props would snap it back.
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
    -- A cursor to click the buttons with. Without a mode the window draws
    -- and nothing in it can be pressed.
    I.UI.setMode('Interface', { windows = {} })
end

close = function()
    if window then
        window:destroy()
        window = nil
    end
    if I.UI.getMode() == 'Interface' then
        I.UI.setMode()
    end
end

--------------------------------------------------------------------------
-- Wiring
--------------------------------------------------------------------------

local function ask()
    core.sendGlobalEvent(eventnames.REQUEST_SNAPSHOT, {})
end

payTribute = function(factionId, amount)
    core.sendGlobalEvent(eventnames.PAY_TRIBUTE, {
        player = self.object,
        faction = factionId,
        gold = amount,
    })
end

local function onSnapshot(data)
    if type(data) ~= 'table' or type(data.factions) ~= 'table' then
        return
    end
    standings = data.factions
    -- Strongest first. The framework answers in a stable order of its own,
    -- which is the right one for a log line and the wrong one for a table
    -- somebody is reading down.
    table.sort(standings, function(a, b)
        if (a.power or 0) == (b.power or 0) then
            return tostring(a.id) < tostring(b.id)
        end
        return (a.power or 0) > (b.power or 0)
    end)

    if openWhenReady then
        openWhenReady = false
        render()
    elseif window then
        render()
    end
end

local function onTributePaid(data)
    if type(data) ~= 'table' then
        return
    end
    if data.ok then
        ui.showMessage(l10n('tributePaid', {
            gold = data.gold or 0,
            power = string.format('%.1f', data.power or 0),
        }))
        -- Asked again rather than adjusting the copy in hand: a payment
        -- propagates along the reaction table, so the faction paid is
        -- rarely the only number that moved.
        ask()
    elseif data.reason == 'gold' then
        ui.showMessage(l10n('tributeTooPoor'))
    elseif data.reason == 'rank' then
        ui.showMessage(l10n('tributeNotAMember'))
    end
end

local function toggle()
    if window then
        close()
        return
    end
    -- Always re-asked: whatever standings are in hand are from the last
    -- time the window was open, and days resolve while it is shut.
    openWhenReady = true
    ask()
end

input.registerTriggerHandler(TRIGGER, async:callback(toggle))

--- Something else taking the screen closes this with it, so the window
-- cannot be left floating over an inventory the player opened next.
--
-- The window is destroyed directly rather than through close(), which
-- would drop the mode that the thing replacing it just set.
local function onUiModeChanged(data)
    if window and data and data.newMode ~= 'Interface' then
        window:destroy()
        window = nil
    end
end

return {
    eventHandlers = {
        [eventnames.SNAPSHOT] = onSnapshot,
        [eventnames.TRIBUTE_PAID] = onTributePaid,
        UiModeChanged = onUiModeChanged,
    },
}
