-- What each operator drives. Inferred from the operator's class.
--
-- The keys are class *record ids*, lowercased -- `types.NPC.record(actor).class`
-- returns the id, never the name shown in game. The two differ for anything a
-- mod adds: Tamriel Rebuilt's river striders are class `T_Mw_RiverstriderService`
-- named "Therionaut", and a table keyed on the name matches nothing.

return {
    classes = {
        -- Vanilla. These four are confirmed against the shipped content.
        ['caravaner']   = { id = 'strider', label = 'Silt strider' },
        ['shipmaster']  = { id = 'boat',    label = 'Boat' },
        ['guild guide'] = { id = 'guide',   label = 'Guild guide' },
        ['gondolier']   = { id = 'gondola', label = 'Gondola' },

        -- The large landmass mods, read off Tamriel Rebuilt 25.08.12 rather
        -- than guessed at. Only two classes there are the mod's own; guar
        -- caravans and carriages are authored as ordinary `caravaner`s, so
        -- the game's data gives no way to tell them from a silt strider.
        ['t_mw_riverstriderservice'] = { id = 'riverstrider', label = 'River strider' },
        -- Two fishermen who ferry a passenger across one stretch of water.
        -- What a fisherman travels in is not in question.
        ['t_glb_fisherman'] = { id = 'boat', label = 'Boat' },
    },

    -- Operators whose class describes the person rather than what they drive.
    --
    -- The vanilla three all run boats: the Holamayan pair, and Molag Mar's
    -- captain who is authored as a Rogue.
    --
    -- Thazlorakis is a daedroth who carries passengers between three Guilds
    -- of Mages and is authored with no class at all. Being a guide is not
    -- cosmetic here -- it is what makes the journey instant and a wait
    -- rather than a rest, so leaving it to fall through would charge hours
    -- for a teleport and hand back health nobody rested for.
    overrides = {
        ['blatta hateria']          = 'boat',
        ['vevrana aryon']           = 'boat',
        ['rindral dralor']          = 'boat',
        ['tr_m1_daedrothgindaman']  = 'guide',
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
    --
    -- One operator is deliberately left to it. Nassuran Omoril, class
    -- Merchant, runs a single leg inland to Ushu-Kur that no other operator
    -- touches, so nothing in the data says what carries you -- and a guessed
    -- vehicle reads as fact to everyone downstream. "Merchant" is the honest
    -- answer until somebody looks.
    unknown = { id = 'unknown', label = 'Unknown' },
}
