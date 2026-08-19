-- Names for stops the game never named.
--
-- The other half of data/modes.lua: the little that this mod has to know about
-- Morrowind specifically. An exterior cell with no name gets called after its
-- region and grid reference -- "Azura's Coast (19, -5)" -- which is honest and
-- useless to read. Where the place has a name everybody knows and the content
-- file simply never wrote down, it goes here.
--
-- Keyed by grid reference, because that is what an unnamed cell has instead of
-- a name. A stop the game did name is never looked up here.

return {
    exteriors = {
        -- The landing below Holamayan Monastery: the boat from Ebonheart puts
        -- you on a beach in a cell nobody named, and "Wilderness (19, -5)" is
        -- not what a player would ever call it.
        ['19,-5'] = 'Holamayan',
    },
}
