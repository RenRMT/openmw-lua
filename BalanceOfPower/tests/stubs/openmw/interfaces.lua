-- Stub for openmw.interfaces, for headless tests.
--
-- In game, a script's `interface` table is published under its
-- `interfaceName` once it loads, and later scripts pick it up from here.
-- Nothing loads scripts in a test, so the framework's interface is wired
-- in directly. That's what lets a content pack's real main.lua be
-- required and exercised exactly as the engine would run it.

return {
    BalanceOfPower = require('scripts.BalanceOfPower.core.api'),
}
