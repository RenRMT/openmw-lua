-- What each operator drives. Inferred from the operator's class.
-- Class names arrive from the engine lowercased, so the keys are too.

return {
    classes = {
        -- Vanilla. These four are confirmed against the shipped content.
        ['caravaner']   = { id = 'strider', label = 'Silt strider' },
        ['shipmaster']  = { id = 'boat',    label = 'Boat' },
        ['guild guide'] = { id = 'guide',   label = 'Guild guide' },
        ['gondolier']   = { id = 'gondola', label = 'Gondola' },

        -- The large landmass mods. Checked against a real load order rather
        -- than guessed at: of everything they add, only the river striders
        -- carry a class of their own. Guar caravans and carriages are
        -- authored as ordinary `caravaner`s, so the game's data gives the
        -- mod no way to tell them from a silt strider -- they share the
        -- overland tab, which is the right grouping even if the label is
        -- vanilla's word for it.
        ['therionaut'] = { id = 'riverstrider', label = 'River strider' },
    },

    -- Four vanilla operators have a class that says nothing about what they
    -- drive. Three of them run boats: the Holamayan pair, and Molag Mar's
    -- captain who is authored as a Rogue.
    overrides = {
        ['blatta hateria'] = 'boat',
        ['vevrana aryon']  = 'boat',
        ['rindral dralor'] = 'boat',
    },

    -- Transport that arrives the moment it leaves.
    --
    -- A guild guide teleports: vanilla advances no clock for it, and the
    -- traveller steps out of the other hall at the hour they stepped into
    -- this one. Every other mode is a vehicle that has to cover ground.
    --
    -- This is why the mod cannot price time as distance alone, and why a
    -- guide journey rests nobody -- see route.lua on `rests`.
    instant = {
        ['guide'] = true,
    },

    -- Bethesda's test NPC, who travels from a debug cell to the same debug
    -- cell. Reachable from nowhere, and noise in a planner.
    exclude = {
        ['todd'] = true,
    },

    -- An operator whose class is not in the table still forms edges; it is the
    -- label that degrades, never the routing. A Tamriel Rebuilt caravaner is
    -- handled by class; an invented class shows up as this.
    unknown = { id = 'unknown', label = 'Unknown' },
}
