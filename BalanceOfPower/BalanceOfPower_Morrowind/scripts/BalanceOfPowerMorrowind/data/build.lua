-- Turns the settlement list into what the framework's registration API
-- wants.
--
-- Every holding in the list is a settlement: named, ownable ground that
-- projects its faction's influence. A farm is one of the smallest tier
-- and a city one of the largest, and they differ by the numbers behind
-- the tier rather than by being different sorts of thing.
--
-- This transform lives in the content pack, not the framework,
-- deliberately: "Minor location" and "Small City" are Morrowind's
-- vocabulary, mapped to the framework's ladder in
-- sources/build_settlements.py, and the framework must not learn either.

local M = {}

local function cellNames(cells)
    local names = {}
    for i, cell in ipairs(cells) do
        names[i] = string.format('#%d,%d', cell[1], cell[2])
    end
    return names
end

--- Group the settlement list by landmass.
--
-- Centroids are deliberately not computed here. The framework derives
-- each settlement's projection origin from its own cells, which is the
-- only way the arithmetic stays in step with the grid its frontier
-- generator lays down -- two copies of "where is cell #3,-9" is how a map
-- ends up subtly out of register with its own settlements.
--
-- @return { [landmassId] = { territories = {...} } }
function M.plan(settlements)
    local byLandmass = {}

    for _, settlement in ipairs(settlements) do
        local id = settlement.landmass
        byLandmass[id] = byLandmass[id] or { territories = {} }
        local territories = byLandmass[id].territories

        territories[#territories + 1] = {
            id = M.idFor(settlement.name),
            displayName = settlement.name,
            tier = settlement.tier,
            region = settlement.region,
            cells = cellNames(settlement.cells),
            -- Whose seat it is, and so whose power it projects. An
            -- unaffiliated holding leaves this nil: it is still ground
            -- with a name, it simply projects for nobody and starts
            -- unowned.
            faction = settlement.faction,
            -- No defaultOwner except where the framework must not be
            -- allowed to derive one -- see main.lua. Initial control
            -- comes from projection, so the starting map is a consequence
            -- of where the seats of power are rather than a second list
            -- to keep in step with the first.
        }
    end

    return byLandmass
end

--- The set of faction ids holding at least one settlement in a plan.
function M.holdersIn(entry)
    local holders = {}
    for _, settlement in ipairs(entry.territories) do
        if settlement.faction then
            holders[settlement.faction] = true
        end
    end
    return holders
end

--- A stable settlement id from a settlement name.
--
-- "Tel Aruhn" becomes tel_aruhn, "Ald-Ruhn" becomes ald_ruhn, "Big
-- Head's Shack" becomes big_heads_shack. Apostrophes close up because
-- they're inside a word; every other punctuation mark separates, because
-- dropping it outright would run words together.
function M.idFor(name)
    local id = string.lower(name)
    id = string.gsub(id, "'", "")
    id = string.gsub(id, "[^%w]+", "_")
    id = string.gsub(id, "^_+", "")
    id = string.gsub(id, "_+$", "")
    return id
end

--- Build the faction list for one landmass's registerLandmass call.
--
-- A faction is defined by the first landmass that mentions it and
-- extended by every later one -- the Empire holds forts on Vvardenfell
-- and Fort Frostmoth on Solstheim, and both have to project at once. The
-- seats themselves need no help: they are registered against their own
-- landmass and name the faction, so the second call's settlements find it
-- already there.
-- @param definitions the faction table from data/factions.lua
-- @param holders set of faction ids holding a settlement on this landmass
-- @param defined set of faction ids already registered by an earlier call
function M.factionsFor(definitions, holders, defined, landmassId)
    local out = {}

    for _, definition in ipairs(definitions) do
        local id = definition.id
        local isPowerOnly = definition.territorial == false

        -- A land-holding faction is only worth registering here if it
        -- actually holds something on this landmass. A power-only faction
        -- has no geography at all, so it belongs to the first call only.
        local relevant = holders[id] or (isPowerOnly and not defined[id])

        if relevant then
            if defined[id] then
                out[#out + 1] = {
                    id = id,
                    extend = true,
                    landmass = landmassId,
                }
            else
                -- Everything the author wrote, with only the one field
                -- this file is responsible for laid over the top.
                --
                -- Deliberately a copy rather than a hand-listed set of
                -- fields. The list version silently dropped patrolRoster
                -- for as long as the field has existed: it validated, it
                -- was documented, and it never arrived. Any field the
                -- framework grows would have gone the same way, and
                -- nothing would have said so.
                local faction = {}
                for key, value in pairs(definition) do
                    faction[key] = value
                end
                faction.landmass = landmassId

                out[#out + 1] = faction
                defined[id] = true
            end
        end
    end

    return out
end

return M
