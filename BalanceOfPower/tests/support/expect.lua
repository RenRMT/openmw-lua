-- Minimal assertion helpers. A failure raises with level 0 so the
-- message the runner prints is the message written here, not a file
-- and line inside this module.

local M = {}

local function fail(message)
    error(message, 0)
end

local function describe(value)
    if type(value) == 'string' then
        return string.format('%q', value)
    end
    if type(value) == 'number' then
        return string.format('%.6g', value)
    end
    return tostring(value)
end

function M.equal(actual, expected, what)
    if actual ~= expected then
        fail(string.format('%s: expected %s, got %s',
            what or 'value', describe(expected), describe(actual)))
    end
end

function M.near(actual, expected, tolerance, what)
    tolerance = tolerance or 1e-6
    if type(actual) ~= 'number' then
        fail(string.format('%s: expected a number near %s, got %s',
            what or 'value', describe(expected), describe(actual)))
    end
    if math.abs(actual - expected) > tolerance then
        fail(string.format('%s: expected %s (+/- %s), got %s',
            what or 'value', describe(expected), describe(tolerance), describe(actual)))
    end
end

function M.truthy(actual, what)
    if not actual then
        fail(string.format('%s: expected a truthy value, got %s',
            what or 'value', describe(actual)))
    end
end

function M.falsy(actual, what)
    if actual then
        fail(string.format('%s: expected a falsy value, got %s',
            what or 'value', describe(actual)))
    end
end

function M.isNil(actual, what)
    if actual ~= nil then
        fail(string.format('%s: expected nil, got %s', what or 'value', describe(actual)))
    end
end

function M.greater(actual, threshold, what)
    if not (type(actual) == 'number' and actual > threshold) then
        fail(string.format('%s: expected a number greater than %s, got %s',
            what or 'value', describe(threshold), describe(actual)))
    end
end

function M.count(list, expected, what)
    local actual = #list
    if actual ~= expected then
        fail(string.format('%s: expected %d entries, got %d',
            what or 'list', expected, actual))
    end
end

--- Asserts that `fn` raises, and that the message contains `pattern`
-- (a plain substring, not a Lua pattern).
function M.raises(fn, pattern, what)
    local ok, err = pcall(fn)
    if ok then
        fail(string.format('%s: expected an error, but the call succeeded', what or 'call'))
    end
    if pattern and not string.find(tostring(err), pattern, 1, true) then
        fail(string.format('%s: expected the error to mention %s, got: %s',
            what or 'call', describe(pattern), tostring(err)))
    end
    return err
end

return M
