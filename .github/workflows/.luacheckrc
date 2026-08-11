-- OpenMW Lua runs 5.1 with a few 5.2/5.3 extensions bolted on, and its
-- environment is sandboxed: no _G-level implicit globals from the game API,
-- since every package (openmw.self, openmw.ui, etc.) is pulled in via a
-- local `require(...)`. So scripts shouldn't reference *any* globals beyond
-- the base Lua stdlib -- if luacheck flags an unexpected global, that's
-- almost always a typo (e.g. missing `local`).
std = "lua51"
globals = {}

-- Engine handlers have fixed signatures dictated by OpenMW
-- (onUpdate(dt), onKeyPress(key), ...), so a script not using every
-- parameter isn't a bug -- don't warn on it.
unused_args = false

-- `self` is not a method-call convention here (openmw.self is its own
-- required package), so don't special-case it.
self = false

exclude_files = {
    ".luarocks/**",
}