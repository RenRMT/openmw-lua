-- What each operator drives. Inferred from the operator's class.

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

    -- Operators whose class describes the person rather than what they drive.
    -- The vanilla three all run boats: the Holamayan pair, and Molag Mar's
    -- captain who is authored as a Rogue. TR adds a Daedroth.
    overrides = {
        ['blatta hateria']          = 'boat',
        ['vevrana aryon']           = 'boat',
        ['rindral dralor']          = 'boat',
        ['tr_m1_daedrothgindaman']  = 'guide',
    },

    -- Transport that arrives the moment it leaves.
    instant = {
        ['guide'] = true,
    },

    -- Bethesda's test NPC.
    exclude = {
        ['todd'] = true,
    },

    -- Names for stops the game never named. Keyed by grid reference, which
    -- is what an unnamed cell has instead of a name; a stop the game did
    -- name is never looked up here.
    places = {
        -- The landing below Holamayan Monastery: the boat from Ebonheart puts
        -- you on a beach in a cell nobody named.
        ['19,-5'] = 'Holamayan',
    },

    -- An operator whose class is not in the table still forms edges but the
    -- label degrades to unknown.
    unknown = { id = 'unknown', label = 'Unknown' },
}
