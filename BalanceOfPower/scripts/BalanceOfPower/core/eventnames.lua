-- Event names, and nothing else.
--
-- Split out from core/events.lua because that module requires
-- openmw.world to broadcast, which makes it GLOBAL-only -- and the
-- scripts most likely to listen are PLAYER scripts, which cannot load
-- it. A listener needs the name far more often than the emitter, so the
-- names live in the half that anyone can require.
--
-- ANY context.

local M = {}

--------------------------------------------------------------------------
-- Out of the framework
--------------------------------------------------------------------------

-- A territory changed hands:
-- { territory, kind, name, settlement, from, to, fromName, toName, day }
--
-- `to` is absent when ground was released rather than taken. `kind` is
-- 'settlement' or 'frontier', which is what lets a listener ignore the
-- hundreds of frontier flips a season without inspecting the id.
M.TERRITORY_FLIPPED = 'BoP_TerritoryFlipped'

-- A settlement's surrounding frontier passed into, or back out of, rival
-- hands: { territory, name, day }. Fires on the change, not every day it
-- holds.
--
-- The framework reports this and does nothing about it. What being
-- surrounded means (siege, blockade, nothing) is a question for whatever
-- extension cares.
M.SETTLEMENT_SURROUNDED = 'BoP_SettlementSurrounded'
M.SETTLEMENT_RELIEVED = 'BoP_SettlementRelieved'

-- A faction's power moved: { faction, delta, newTotal }
M.POWER_CHANGED = 'BoP_PowerChanged'

-- A faction's holdings passed STRAIN_EVENT_THRESHOLD, or fell back under
-- it: { faction, strain, day }. Fires on the crossing, not every day it
-- holds -- the same contract as SETTLEMENT_SURROUNDED, and for the same
-- reason: what overreach means is a question for whatever extension
-- cares.
M.FACTION_STRAINED = 'BoP_FactionStrained'
M.FACTION_RELIEVED = 'BoP_FactionRelieved'

-- One in-game day finished resolving: { day }.
--
-- The scheduling hook for everything built on top. An extension that has
-- to act once a day runs from this rather than keeping a timer that
-- drifts against the framework's own pass.
--
-- Delivery is queued rather than synchronous, so a listener acts on the
-- day *after* the one it hears about. That is invisible in play, but an
-- extension needing strict ordering should poll getCurrentDay() instead,
-- which is the pattern the driver itself uses.
M.DAY_RESOLVED = 'BoP_DayResolved'

--------------------------------------------------------------------------
-- Into the framework
--------------------------------------------------------------------------
--
-- The interface is global-context only, so a player script -- a quest
-- watcher reading the journal, a UI drawing on screen -- has no way to
-- reach it. These two are the way in.

-- Move a faction's standing: { faction, delta, rankMultiplier }.
-- The event form of api.awardPower, and the whole of what a quest mod
-- needs. Sent to the global context with core.sendGlobalEvent.
M.AWARD_POWER = 'BoP_AwardPower'

-- Ask for the current state: { cell } -- both fields optional.
--
-- Every other event fires on change only, so without this a script that
-- starts mid-game has no way to learn where things stand until something
-- moves. Answered with one SNAPSHOT, broadcast the usual way.
M.REQUEST_SNAPSHOT = 'BoP_RequestSnapshot'

-- Pay a faction of which the player is a member:
-- { player, faction, gold }.
--
-- Taking the gold needs global context, and knowing how much the player
-- has and what rank they hold needs the player's own -- so this crosses
-- from one to the other, and the global half re-checks everything the
-- window already checked. A window is a thing another mod can forge.
M.PAY_TRIBUTE = 'BoP_PayTribute'

-- What became of it: { ok, faction, gold, power, reason }.
--
-- `reason` is 'gold', 'faction', 'rank' or 'amount' when `ok` is false,
-- so the window can say which of them went wrong rather than failing
-- silently.
M.TRIBUTE_PAID = 'BoP_TributePaid'

-- The answer: { day, factions, territory }.
--
-- `factions` carries a row per registered faction with enough to draw it
-- without asking a second question; `territory` is present only when the
-- request named a cell that resolved to one.
M.SNAPSHOT = 'BoP_Snapshot'

-- Ask where every settlement is and who holds it: no payload.
--
-- Kept apart from REQUEST_SNAPSHOT rather than folded into it because
-- the two have opposite shapes. A snapshot is small and wanted often --
-- the tribute window asks every time it opens. This is one row per
-- settlement cell and wanted rarely, by whatever is drawing a map, and
-- putting it in the snapshot would make every caller pay for it.
M.REQUEST_MAP = 'BoP_RequestMap'

-- The answer: { day, cells }.
--
-- One row per owned settlement cell: { gridX, gridY, settlement, owner,
-- ownerName }. Cells rather than settlements because ownership is
-- resolved per cell -- a city under attack can be held in pieces, and a
-- payload keyed by settlement could not say so.
--
-- `owner` is nil for a settlement cell nobody holds, which is ordinary:
-- a derelict tower is ground with a name and no claimant.
M.MAP = 'BoP_Map'

return M
