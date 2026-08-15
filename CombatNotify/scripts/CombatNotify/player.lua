local core = require('openmw.core')
local ui = require('openmw.ui')
local util = require('openmw.util')

local combatMsg = core.l10n('CombatNotify', 'en')

local attackerCount = 0
local indicator = nil

local function refreshIndicator()
    if attackerCount > 0 and not indicator then
        indicator = ui.create {
            layer = 'HUD',
            type = ui.TYPE.Text,
            props = {
                text = combatMsg('in_combat'),
                textSize = 24,
                textColor = util.color.rgb(0.85, 0.15, 0.15),
                textShadow = true,
                relativePosition = util.vector2(0.5, 0.06),
                anchor = util.vector2(0.5, 0),
                autoSize = true,
            },
        }
    elseif attackerCount <= 0 and indicator then
        indicator:destroy()
        indicator = nil
    end
end

local function onCombatStatusChanged(data)
    attackerCount = math.max(0, attackerCount + (data.inCombat and 1 or -1))
    refreshIndicator()
end

return {
    eventHandlers = {
        CombatStatusChanged = onCombatStatusChanged,
    },
}
