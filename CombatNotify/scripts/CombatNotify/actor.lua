local self = require('openmw.self')
local types = require('openmw.types')
local I = require('openmw.interfaces')
local time = require('openmw_aux.time')

-- Tune this. Hostile actors that are actively engaged tend to sit well
-- above their peaceful baseline; passive/neutral actors usually sit low.
-- Playtest and adjust -- exact values vary by creature/faction.
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

    -- Cheap early-out: most actors most of the time aren't worked up
    -- enough to be fighting anyone, so skip the AI package lookup entirely.
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
