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
as `reactions[X] = how this faction feels about X`, so a row answers *"whose
power moves this faction, and which way?"* **Sourced entirely from the game's
own faction records.** No mod in this ecosystem defines a faction or an opinion;
the game's content files do, so there is nowhere to author one and the registry
refuses a pack that tries.

Two statements that sound contradictory and are both true. Keep them together —
separating them is how this got shipped backwards:

- **Storage is outbound.** A row belongs to the faction holding the opinions,
  exactly as the ESM stores it. Nothing is transposed and no setting selects a
  direction.
- **The propagation query is inbound.** "Who moves when X moves" is X's
  *column* — every other faction's row, indexed by X.

Getting the storage direction backwards is silent: symmetric pairs behave
identically either way, and the framework shipped it backwards for three phases
before an asymmetric pair caught it. The engine's own documentation describes
the record map as inbound and is wrong for ESM3, which is how it got in.

A faction with no record, or a record with an empty row, sits outside the
politics — sometimes a mistyped id, often just what the game says. Closing a gap
means adding the FACT entry in an `.esp`, not a table in Lua.

**Seat** — a settlement, seen from its faction's side. A faction has no
geography of its own; it holds seats, and a seat is a settlement that names it.
There is no such thing as a projector that is not a settlement: a farm is a
settlement of the smallest tier, not a different sort of thing.

**Weight** — a settlement's share of its faction's power, by tier. A city
projects at full weight, a minor location at a fraction of it.

**Influence range** — the **halving distance**: how far a settlement's
projection travels before it drops to half strength. It halves again every
range after that and never reaches zero, so it is an exchange rate rather than
a limit — see *reach*.

**Power projection** — a faction's power at a particular place: its raw power
scaled by distance decay from its nearest seat. A faction's projection
somewhere is its **strongest single** settlement's contribution, never the sum
of several — so a faction cannot out-project a rival by accumulating farms.

**Reach** — which factions project *anything at all* onto a place, however
small. Distinct from projecting *above the claim threshold*. Reach is fixed
geometry, so it is cached; it is what keeps the daily pass cheap, because only
the factions that reach a place ever need evaluating there.

Strictly, every faction reaches everywhere: the decay never bottoms out. What
the cache stores is every faction that could *matter* there, and the horizon
past which it stops caring is a performance bound, not a rule of the world.

**Claim threshold** — the projection a faction must exceed for its presence
somewhere to count. Below it, a faction is in reach but not a contender.

This is what decides how far anyone reaches, since nothing else does. **There
is no distance at which a faction is shut out** — only a distance at which it
would need more power than it has. So a faction that grows claims further, and
because distance costs a fixed *fraction* per unit rather than a fixed amount,
it does so with diminishing returns:

> **Every doubling of a faction's power pushes its border out by exactly one
> influence range.**

Ten times the power is therefore a bit over three influence ranges further, not
ten times further.

---

## Places

**Cell** — one exterior cell of the game world, 8192 units square, named
`#x,y`. The engine's unit, not this system's.

**Territory** — the unit that can be owned. **Exactly one exterior cell.** The
two words are near enough to interchangeable in practice, but they are not the
same idea: a cell is the engine's, a territory is this system's, and interior
cells are cells that are not territories.

**Settlement** — a named place, and **the only thing on the map that projects
power.** A settlement is a *group of territories*, not a territory: Vivec is one
settlement over fifteen cells, each separately ownable and all carrying the same
`settlement` tag.

Every holding is one, down to a single farm. There is no second category for
things too small to be places — a farm is a `minor location`, projecting a
little and holding its own cell, and it differs from Vivec by the numbers behind
its tier rather than by kind.

**Tier** — where a settlement sits on one ladder, smallest to largest:

`minor location` · `outpost` · `village` · `town` · `small city` ·
`large city` · `metropolis` · `megalopolis`

The tier is not metadata. It sets three things at once: how strongly the
settlement projects (weight), how far (influence range), and how long its cells
are immune after changing hands (cooldown).

**Faction** (of a settlement) — whose seat it is, and so whose power it
projects. Not the same question as who *owns* the ground: ownership is derived
and can flip, while a settlement goes on projecting for the faction that built
it. A settlement with no faction is ordinary ground with a name.

**Garrison floor** — the projection a faction is guaranteed at a cell its own
settlement occupies, scaled by that settlement's weight. It is what keeps a
settlement with whoever built it, and it is a number rather than a rule, so
there is no "settlements cannot change owner" branch anywhere. A holding with
weight 0 gets a floor of 0 and behaves like open ground.

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

**Cell state** — every territory is in exactly one of four, and the four cover
everything:

| | Meaning |
|---|---|
| `unclaimed` | Nobody owns it. Equivalently: nobody projects above the claim threshold |
| `consolidated` | One faction is above the threshold, and holds it. Deep interior |
| `uncontested` | Several are above it, and the owner is the strongest. A border, but a stable one |
| `contested` | The owner is *not* the strongest. It is changing hands |

`unclaimed` is exactly "no owner", so the other three cover everything owned
and nothing is ever in two states at once.

Note what `uncontested` does **not** mean: it does not mean nobody else is
here. Two factions can both be projecting hard onto a cell and it still reads
`uncontested` while the owner leads. The "deep interior, nobody else within
reach" signal is `consolidated` — that is the one a spawn rule wants when
deciding whether a cell is a border.

A freshly derived map has **no** contested cells, and that is not a bug:
initial control hands every cell to its strongest projector, so no owner is
being out-projected. Contest appears only once power has moved.

**Flip** — an ownership change during play. Distinct from the initial
assignment at world creation, which is not a flip: it fires no events and
stamps no cooldown.

**Cooldown** — the period after a flip during which a territory cannot change
hands again, so a contested border creeps rather than oscillating.

**Surrounded** — a settlement whose adjacent frontier cells are held by rivals
past a configured share. The framework tracks and exposes this; it does not act
on it. Anything that happens as a result belongs to an extension.

A settlement's owner does not change. It is claimed once — at world creation,
or the first day somebody projects hard enough onto ground nobody reached — and
held from then on. The competition modelled here is non-violent: **borders
move, seats do not.**

---

---

## Patrols

**Patrol** — actors a faction puts on the ground it holds, and the only part of
this system a player without a console ever sees. Nobody reads a projection
number; they notice that the road out of Balmora has guards on it and that
somewhere south of Ghostgate it stopped.

**Roster** — the record ids a faction fields, authored by a content pack. The
framework stores them and never looks inside one: what a `hlaalu guard` is, and
which content file defines it, is the pack's business entirely. **A faction with
an empty roster fields no patrols**, which is the whole opt-out — there is no
flag for it.

**Tier** — a number on a roster entry, gating it behind a projection threshold.
Numbers rather than names because a name would be content: one pack's "veteran"
is another's "housecarl". Entries at lower tiers stay in the pool, so a strong
faction fields its best troops *alongside* its ordinary ones.

**Belligerent / hostile** — a faction its pack flagged as one that fights.
Defaults to nobody: Morrowind's Great Houses dislike each other without
brawling in the street. A hostile faction attacks the player, and attacks any
faction it *regards* at or below the hostility threshold — so who it fights
comes from the reaction table rather than a second list.

Note the direction. Hostility asks how the hostile faction feels about the
other one, which is the aggressor's own row — not the target's.

**Ambient growth** — power a faction gains each day with nobody doing anything
(`growthPerDay`). It does not propagate through reactions, because a daily drip
compounds where a one-off award does not — see the constant for the arithmetic.
A faction that grows on its own is an ordinary faction with a number set, not a
mode.

---

## What the framework does not define

The framework simulates influence and ownership, and provides the mechanisms
that make them observable. It has no vocabulary for, and takes no position on,
what anyone does about them:

- **sieges** and settlements changing hands by force
- **invasion**, escalation stages, corruption of territory
- what a patrol *is* — its records, its equipment, its dialogue

Those are extensions and content packs. They read ownership, projection,
surrounded status and patrol plans through the interface and keep their own
state. If a term for one of them ends up in this file, the boundary has moved
and that should be a deliberate decision rather than a drift.

**Patrols moved across this line deliberately**, in August 2026. The earlier
rule was that anything acting on ownership was an extension, which put spawning
outside; the rule now is that the framework owns the mechanisms that make
ownership visible, and decides nothing about who or what. A territory system
nobody can see is a spreadsheet. The test that keeps it honest is unchanged: no
faction id, no record id, and no `if landmass ==` anywhere in `core/`.
