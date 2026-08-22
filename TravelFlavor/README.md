# Travel Flavor — travel descriptions (OpenMW)

After arriving by silt strider, boat, gondola, or guild guide, a short line describes the trip you did not have to sit through.

```
You arrive in Balmora.
The driver spent the journey counting gold from the morning's fares.
```

## Setup

Point `openmw.cfg` at the mod directory and enable its script list:

```
data="<path to>/openmw-lua/TravelFlavor"
content=TravelFlavor.omwscripts
```

## Adding lines

Everything is in `l10n/TravelFlavor/en.yaml`. A line's key is the operator's
**class id**, lowercased, numbered from one:

```yaml
shipmaster_7: "For most of the crossing the water lay unnaturally still."
```

The script counts what is there each time it runs. Numbering must not skip, since counting stops at the first gap.

## Compatibility
The mod has lines prepared for the TR-added river striders.

A mod that invents a vehicle only needs lines written
under its class id. Anything else: `generic_*` covers it, as well as the few operators with an unusual class, or creature
operators added by mods.

`arrival` and `arrivalUnplaced` are the frame around each line. The line
break and the order of the two halves live there, not in the script.

## Other travel mods
If a mod adds travel in a way that doesn't use the vanilla Travel window, the journey will be invisible to this mod's ordinary
detection. Any mod that announces an arrival is handled in the *Adapters* section of the script. Mostly done for my other mod **TravelAgents**.

To announce a journey from your own mod, send the player:

```lua
player:sendEvent('TravelAgentsArrived', {
    class = 'shipmaster',   -- the operator's class id, as the content files spell it
    place = 'Ebonheart',    -- optional; the cell arrived in is used otherwise
})
```
