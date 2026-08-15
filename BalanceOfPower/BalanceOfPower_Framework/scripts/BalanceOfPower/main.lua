-- Balance of Power -- framework global script.
--
-- Owns the save/load boundary and exports the interface; 
-- the clock lives in core/driver.lua and the simulation in
-- the other core modules, so each later phase adds a call inside
-- driver.runDay() rather than growing this file.
--
-- On its own this mod will register nothing and report an empty 
-- world. It requires content packs.

local api = require('scripts.BalanceOfPower.core.api')
local driver = require('scripts.BalanceOfPower.core.driver')
local log = require('scripts.BalanceOfPower.core.log')
local registry = require('scripts.BalanceOfPower.core.registry')
local state = require('scripts.BalanceOfPower.core.state')

local function onInit()
    state.reset()
    state.fillDefaults(registry)
    driver.reset()
    log.info('framework initialized (interface v%d)', api.version)
end

local function onLoad(saved)
    state.deserialize(saved)
    state.fillDefaults(registry)
    driver.reset()
    log.debug('state restored, resuming from day %s', tostring(state.get().lastResolvedDay))
end

local function onSave()
    return state.serialize()
end

-- Script bodies run once per session, before any handler, so this
-- starts the tick exactly once. The first poll lands after onInit or
-- onLoad has set up state.
driver.start()

return {
    interfaceName = 'BalanceOfPower',
    interface = api,
    engineHandlers = {
        onInit = onInit,
        onLoad = onLoad,
        onSave = onSave,
    },
}
