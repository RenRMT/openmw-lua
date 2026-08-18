-- What each operator drives. Nothing in the game's data says "boat", so this
-- is inferred from the operator's class -- which is content knowledge, and
-- lives here rather than anywhere that pretends to be generic.
--
-- Class names arrive from the engine lowercased, so the keys are too.

return {
    classes = {
        ['caravaner']   = { id = 'strider', label = 'Silt strider' },
        ['shipmaster']  = { id = 'boat',    label = 'Boat' },
        ['guild guide'] = { id = 'guide',   label = 'Guild guide' },
        ['gondolier']   = { id = 'gondola', label = 'Gondola' },
    },

    -- Four vanilla operators have a class that says nothing about what they
    -- drive. Three of them run boats: the Holamayan pair, and Molag Mar's
    -- captain who is authored as a Rogue.
    overrides = {
        ['blatta hateria'] = 'boat',
        ['vevrana aryon']  = 'boat',
        ['rindral dralor'] = 'boat',
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
