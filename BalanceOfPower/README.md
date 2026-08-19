# Balance of Power — a factions framework

Tracks faction power and territory control, and exposes an interface that
content packs and extensions read. It ships **no factions and no
territories**. On its own it does nothing.

The framework decides *what the numbers are*, and stops there. It places no
actor, starts no fight and writes no quest — it answers the questions those
things need answered, so that every mod built on it answers them the same way.

## What it models

**Power** is a faction's standing, one number. It moves for four reasons: an
award — from a content pack, or from the player paying tribute — ambient growth,
propagation along the game's own reaction table, and drift.

**Territory** is ownership of an exterior cell. A faction projects onto a cell
by power scaled against distance, the strongest projection claims it, and
contested ground changes hands on a roll.

**Drift** closes the loop between the two. Ground held raises the standing that
took it and ground lost lowers it, so power and territory are not two systems
but one. A faction's power is pulled toward its **capacity** — what its holdings
support — displaced by its **fortune**, a slow curve derived from the faction id
and the day index alone. Fortune costs no save state, holds a direction for
weeks rather than jittering daily, and is bounded, so a long game cannot
random-walk away.

Breadth beats depth on both sides of that. Ten cells stacked in one region are
worth much less than ten regions holding one each, which is what stops the
strongest faction compounding its way across the map.

**Invaders** are the exception, and one field declares it:
`type = 'invader'`. Such a faction is an outside threat rather than a
participant in the politics — it does not drift, takes no part in the reaction
table in either direction, and fights everyone without needing a hostility
flag. Because it has no capacity to revert toward, a setback dealt by content is
permanent: the ramp resumes from lower down rather than recovering.

## The window

One screen, opened by a key you bind yourself (nothing is bound by default).

The **left column** lists every faction the framework has registered, strongest
first, with its current standing. That is the whole world, and you can only
watch it.

The **right column** lists the ones that count you a member, and lets you pay
**tribute**: gold handed to your own people, turned into their standing.

Two things shape what a payment is worth:

- **Returns diminish.** The curve is concave in gold, so a hundred coins buys
  about three times what ten does, not ten times. Every further point of
  standing costs more than the last, which is what stops tribute being a slider
  you drag to win.
- **Rank multiplies.** The same purse moves more in the hands of someone the
  faction actually listens to — from ×1 at the bottom of its ladder to ×3 at
  the top. Rank is read from the player by the global script, never taken from
  the window, so a forged event cannot buy a councilman's rate at a hireling's
  price.

Worth knowing what tribute does *not* do: an award to an ordinary faction decays
back toward its capacity, so buying a house to the top of the table does not
keep it there. Tribute lifts a faction while it spends that standing on taking
ground; **ground held is the only thing that makes the lift permanent.**

## Settings

Options → Scripts → Balance of Power.

| Setting | What it does |
|---|---|
| *Power drifts over time* | The master switch for drift. Off, power only moves when something awards it |
| *Reversion rate* | How fast power moves toward what a faction's holdings support |
| *Fortune swing* | How far luck carries a faction above or below that |
| *Overreach weakens defence* | Holding more than your standing supports costs you when defending it |
| *Value of tribute* | How much standing a member's gold buys. 0 turns tribute off |
| *Open the standings* | The key that opens the window. Nothing is bound until you bind one |
| *Announce territory changes* | Whether notices go to the log, the screen, or nowhere |
| *Named places only* | Announce towns and cities, not every frontier cell |

Every tunable the simulation reads is a named constant in
`scripts/BalanceOfPower/core/config.lua`; the page above exposes the behavioural
ones. Map-shape constants are deliberately not exposed — they are consumed once
when the frontier grid is generated, so a slider would do nothing until a new
game.

## For other mods

`require('openmw.interfaces').BalanceOfPower` from any global script. It
publishes standings, capacity, fortune, projection, reach, ownership and
hostility, and emits events when the map moves — including
`BoP_DayResolved`, the scheduling hook to build on.

The interface is global-context only, so player scripts have events to reach it
instead: `BoP_AwardPower` to move a faction's standing, `BoP_RequestSnapshot`
answered with everything a UI needs to draw the world, and `BoP_PayTribute`
answered with `BoP_TributePaid`. The tribute window is built on exactly those
and nothing else, so it doubles as a worked example of what an extension can
do from player context.

Never `require` a module under `core/` directly. The merged VFS allows it and
the internals change without notice.

## Status

In development, and unstable: the interface version is 0. The Morrowind content
pack and the debug overlay are not yet published here.

## Setup

Point `openmw.cfg` at the mod directory and enable its script list. The
framework must load before any content pack.

```
data="<path to>/openmw-lua/BalanceOfPower"
content=BalanceOfPower.omwscripts
```
