# Balance of Power — glossary

Shared vocabulary for the framework, the content packs and the design
documents. When a word here appears in code, a comment, a log line or a
document, it means what it says here and nothing else.

This exists because several of these terms are nearly synonyms in ordinary
English and mean quite different things in this system — most importantly
**cell** and **territory**, and **projects** versus **reaches**.

---

## Power

**Power** — a faction's raw standing, one number per faction, world-wide. It
has no location. This is what the player's actions move, what reaction
propagation spreads between factions, and the only input to the simulation
that changes from day to day.

**Reaction** — how one faction feels about another, in roughly `[-3, 3]`. Read
as `reactions[X] = how X feels about the faction whose row this is`, so a row
answers *"when this faction's power moves, who moves with it?"* Sourced from
the game's faction records and from authored tables, merged.

**Power centre** — a point on the map that projects a faction's power outward.
Every settlement is a power centre; **not every power centre is a settlement.**
Farms, shacks and mines are power centres that are not settlements: they shape
who a region belongs to without being places anything happens.

**Weight** — a power centre's share of its faction's power, by tier. A capital
projects at full weight, a minor holding at a fraction of it.

**Influence range** — the distance at which a power centre's contribution
decays to exactly zero. Beyond it a faction projects nothing there, however
powerful it is — which is why ground outside every influence range is never
generated as territory at all.

**Power projection** — a faction's power at a particular place: its raw power
scaled by distance decay from its nearest power centre. A faction's projection
somewhere is its **strongest single** power centre's contribution, never the
sum of several — so a faction cannot out-project a rival by accumulating minor
holdings.

**Reach** — which factions project *anything at all* onto a place, however
small. Distinct from projecting *above the claim threshold*. Reach is fixed
geometry, so it is cached; it is what keeps the daily pass cheap, because only
the factions that reach a place ever need evaluating there.

**Claim threshold** — the projection a faction must exceed for its presence
somewhere to count. Below it, a faction is in reach but not a contender.

---

## Places

**Cell** — one exterior cell of the game world, 8192 units square, named
`#x,y`. The engine's unit, not this system's.

**Territory** — the unit that can be owned. Do not use these two words
interchangeably.

**Settlement** — a place with a name: a city, town, village, fort or camp. A
settlement is a power centre and has a tier (`metropolis`, `city`, `town`,
`village`, `outpost`). Several settlements span more than one cell — Vivec
covers fifteen.

**Frontier cell** — territory with no settlement on it. The wilderness between
the named places. Generated rather than authored: a content pack declares where
the seats of power are, and the frontier falls out of their influence ranges.

**Landmass** — the registration grouping a pack declares. Vvardenfell and
Solstheim are separate landmasses; a faction can hold ground on both.

**Region** — the game's own region name for a cell, carried through for display
and for future region-scoped rules. Never acted on by the simulation.

---

## Ownership

**Owner** — the faction currently holding a territory, or nobody.

**Flip** — an ownership change during play. Distinct from the initial
assignment at world creation, which is not a flip: it fires no events and
stamps no cooldown.

**Cooldown** — the period after a flip during which a territory cannot change
hands again, so a contested border creeps rather than oscillating.

**Surrounded** — a settlement whose adjacent frontier cells are held by rivals
past a configured share. The framework tracks and exposes this; it does not act
on it. Anything that happens as a result belongs to an extension.

---

## What the framework does not define

The framework simulates influence and ownership. It has no vocabulary for, and
takes no position on, what happens as a consequence:

- **sieges** and settlements changing hands by force
- **invasion**, escalation stages, corruption of territory
- **spawns** and patrols

Those are extensions. They read ownership, projection and surrounded status
through the interface and keep their own state. If a term for one of them ends
up in this file, the boundary has moved and that should be a deliberate
decision rather than a drift.
