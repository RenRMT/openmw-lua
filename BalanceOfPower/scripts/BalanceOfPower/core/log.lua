-- Prefixed console/log output. Everything the framework prints goes
-- through here so anyone reading openmw.log can filter on one string, and
-- so DEBUG-only chatter is gated in exactly one place.

local config = require('scripts.BalanceOfPower.core.config')

local PREFIX = '[BalanceOfPower] '

local M = {}

function M.info(fmt, ...)
    print(PREFIX .. string.format(fmt, ...))
end

function M.warn(fmt, ...)
    print(PREFIX .. 'WARNING: ' .. string.format(fmt, ...))
end

function M.debug(fmt, ...)
    if config.DEBUG then
        print(PREFIX .. string.format(fmt, ...))
    end
end

return M
