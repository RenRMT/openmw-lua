# Travel Flavor — a line of colour after a journey (OpenMW)

Arrive by silt strider, boat, gondola, river strider or guild guide and a
short line describes the trip you did not have to sit through.

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
shipmaster_73: "The captain said nothing for the whole crossing."
```

Nothing else needs changing — the script counts what is there each time it
runs. Numbering must not skip, since counting stops at the first gap.

Vanilla's classes are `caravaner`, `shipmaster`, `gondolier` and
`guild guide`; Tamriel Rebuilt adds `t_mw_riverstriderservice`. **Any class
works**, so a landmass mod that invents a vehicle only needs lines written
under its class id. Until it has any, `generic_*` covers it — as it does for
the few operators authored with a class describing the person rather than
what they drive.

`arrival` and `arrivalUnplaced` are the frame around each line. The line
break and the order of the two halves live there, not in the script.
