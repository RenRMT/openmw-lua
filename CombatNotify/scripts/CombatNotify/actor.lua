local self = require('openmw.self')
local types = require('openmw.types')
local I = require('openmw.interfaces')
local time = require('openmw_aux.time')

-- you could tune this value but it won't change script behavior
local FIGHT_THRESHOLD = 50

local targetingPlayer = false
local lastTarget = nil  -- remember who to notify when combat ends

local function clearStatus()
    if targetingPlayer and lastTarget then
        lastTarget:sendEvent('CombatStatusChanged', { inCombat = false, attacker = self.object })
    end
    targetingPlayer = false
end

local function checkCombat()
    if types.Actor.isDead(self) then
        clearStatus()
        return
    end

    -- most actors most of the time aren't agressive enough to be fighting anyone so skip the AI package lookup
    local fight = types.Actor.stats.ai.fight(self).modified
    if fight < FIGHT_THRESHOLD then
        clearStatus()
        return
    end

    local target = I.AI.getActiveTarget('Combat')
    local isPlayer = target ~= nil and types.Player.objectIsInstance(target)

    if isPlayer then
        lastTarget = target
    end

    if isPlayer ~= targetingPlayer then
        targetingPlayer = isPlayer
        if lastTarget then
            lastTarget:sendEvent('CombatStatusChanged', {
                inCombat = isPlayer,
                attacker = self.object,
            })
        end
    end
end

local stopTimer = nil

local function onActive()
    stopTimer = time.runRepeatedly(checkCombat, 0.5 * time.second)
end

local function onInactive()
    clearStatus()
    if stopTimer then
        stopTimer()
        stopTimer = nil
    end
end

return {
    engineHandlers = {
        onActive = onActive,
        onInactive = onInactive,
        onDeath = clearStatus,
    },
}
