-- Operator modes: class -> vehicle type mapping.

return {
    classes = {
        ['caravaner']   = { id = 'strider', label = 'Silt strider' },
        ['shipmaster']  = { id = 'boat',    label = 'Boat' },
        ['guild guide'] = { id = 'guide',   label = 'Guild guide' },
        ['gondolier']   = { id = 'gondola', label = 'Gondola' },

        -- Classes added by TR. Other PTR mods use `caravaner`.
        ['t_mw_riverstriderservice'] = { id = 'riverstrider', label = 'River strider' },
        -- Two fishermen who ferry a passenger across one stretch of water.
        -- What a fisherman travels in is not in question.
        ['t_glb_fisherman'] = { id = 'boat', label = 'Boat' },
    },

    -- Classes that describe person, not vehicle (three vanilla boats, one TR guide).
    overrides = {
        ['blatta hateria']          = 'boat',
        ['vevrana aryon']           = 'boat',
        ['rindral dralor']          = 'boat',
        ['tr_m1_daedrothgindaman']  = 'guide',
    },

    -- Instant transport (no travel time).
    instant = {
        ['guide'] = true,
    },

    -- Bethesda test NPC (excluded).
    exclude = {
        ['todd'] = true,
    },

    -- Fallback names for unnamed stops (grid reference -> name).
    places = {
        -- Landing below Holamayan (Ebonheart boat destination).
        ['19,-5'] = 'Holamayan',
    },

    -- Undeclared class: forms edges, label degrades to unknown.
    unknown = { id = 'unknown', label = 'Unknown' },
}
