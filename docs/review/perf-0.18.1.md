# Performance review: 0.18.1 (CurseForge beta 9608474 / 9608475, commit b0535ca)

2026-11-15. Trigger: players report a freeze "every few seconds". Read from the code at b0535ca;
no in-game profile yet. Costs below come from the offline harness and are scaled up by entry
count. The client's own cost (tooltip data, dynamic descriptions) is not in them and is probably
the larger part.

## Verdict

The Forever spell book (`Spells/Book.lua`) runs a **full rescan from the cast handler**. That
rescan grew about 3x in 0.18.1, because every rank not learned yet is now read too. A healer
casting every 1.5-3 s pays one full scan per cast or so: the freeze "every few seconds".
TBC's book (`Spells/Book_Model.lua`) has no future ranks and is not on the cast path; it is
lower risk and none of 0.18.1's changes touch it.

## Findings, worst first

### P1 (critical): the cast handler rescans the whole book
`Engine/ManaPool_Forever.lua` `UNIT_SPELLCAST_SUCCEEDED` -> `Pool.CostFor(id)` -> `ST.Book:Get()`.
`Book:Get()` rescans when the book is dirty **or the cache is 2 s old** (`CACHE_SECONDS = 2`).
In combat the cache is nearly always over 2 s old, or dirty from `UNIT_AURA` (P4), when the next
cast lands. So almost every cast runs `Book:Scan()` inside the event handler.
This fires for every class with a model, which is every class: warriors and rogues too, and a
hunter's Auto Shot every 2-3 s.
**Fix:** `CostFor` reads the cached book without a rescan (a `Book:Peek()` that never scans).
A spell the cache lacks is read alone (`ReadSpell(id)`, already the fallback). Never scan from
an event handler.

### P2 (critical): every rank not learned yet is re-read on every scan (new in 0.18.1)
`Book:AddFutureRanks` -> `BuildFutureEntry` for every rank in `Data/Ranks_Forever.lua` of every
spell name the book has. That is 187 druid ranks, 220 priest, 264 hunter, and also for warriors
and rogues. A level-20 druid adds about 120 entries to about 60 known ones.
Each entry costs `SpellName`, `SpellSubtext`, `SpellTexture`, `SpellKnown`, and `ReadById`:
`SpellDescription` (generated text), `SpellLevelLearned`, **`SpellTooltipData`
(`C_TooltipInfo.GetSpellByID`)**, `SpellInfo` and `SpellPowerCost`. Every one goes through
`pcall` and `Copy`, then `Parse.Description` runs pattern matching on the text.
Harness: about 0.33 ms of Lua and about 20 adapter calls per entry. For about 180 entries that
is about 60 ms of Lua plus about 3,600 client calls (180 tooltip builds) **per scan**, before
the client's own cost.
**Fix:** build future entries only when the book is marked dirty (level, talents, gear,
`SPELLS_CHANGED`), never on the timer. Only for families of a rank-table kind (heal / damage)
of a class granted `rankTable`; no future ranks for a class without one. Keep the built
entries between scans.

### P3 (high): the 2-second expiry rescans a book that did not change
`Book:Get()`'s time rule (from T7) rescans an unchanged book every 2 s for any caller: the cast
handler, the spell tooltip on hover (`UI/SpellTip.lua`), `/st measure`, and the Spells pane's
2-second ticks while open. It was affordable at about 50 entries in October; it is not at 180.
**Fix:** event-driven only: a scan when dirty, else the cache. If a safety net is wanted, make
it 30 s+ and out of combat only.

### P4 (high): every player aura change marks the book dirty and fires BOOK_CHANGED
`ST:On("UNIT_AURA")` for `player` -> `Book:MarkDirty()`. In combat that fires many times a
second (HoTs on yourself, procs, raid buffs).
A scan after `MarkDirty` counts as **changed** (`changed = Book._dirty or ...`). So it fires
`BOOK_CHANGED`, which runs `Tabs:Reconcile` and `SpellsPane:RefreshRail()`; the rail is rebuilt
even while the window is closed.
**Fix:**
- `BOOK_CHANGED` only when the generation moved (`entryChanged`), not whenever the book was
  dirty.
- Aura dirtiness coalesced (one mark per frame, or only the auras that move a number: forms,
  +healing / crit buffs).
- `RefreshRail` deferred while the pane is hidden.

### P5 (medium): a tooltip read for every entry on every scan
`ReadById` calls `SpellTooltipData` (`C_TooltipInfo`, a full tooltip build) for every entry,
known or future, every scan. That makes about 180 tooltip builds per scan.
**Fix:** cache the tooltip-derived fields by id. Re-read only when dirty for a reason that
changes them (level, talents), or when the description did not read.

### P6 (medium): the book contract is checked on every scan
`ST.BookShape.Check(book, ...)` validates every field of every entry on every live scan. That
is O(entries x fields), and the harness already holds the contract.
**Fix:** check on the first scan of a session, or only under the debug console.

### P7 (low): `EntrySig` and `MeasureBonus` over the whole book every scan
Both are proportional to entry count, so they grew with P2. Fixing P2 and P3 cuts their call
rate as well.

## Not the cause (checked)
- The Forever clock's 0.5 s tick paints from the mana model only: no book read.
- `SpellRequestLoad` runs once per id (`Book._loadAsked`), so there is no
  `SPELL_DATA_LOAD_RESULT` loop.
- The Spells pane's 2 s ticks run only while it is shown.
- Crit (`CritNow`) is one `GetSpellCritChance` per school per scan: cheap.

## Order of work
1. **P1 and P3**: a scan never runs from an event handler or the timer. This alone removes the
   per-cast freeze. Small change in `Spells/Book.lua` and `Engine/ManaPool_Forever.lua`.
2. **P2**: future entries only on dirty, only for rank-table families.
3. **P4**: `BOOK_CHANGED` on generation only; aura dirtiness coalesced.
4. **P5 and P6**: cut the remaining per-scan cost.
5. A `/st perf` line in `/st dump` (scans this session, last scan ms by `debugprofilestop`,
   scans from events) so a player's report shows it.

Ship 1-3 as 0.18.2.

## Status (2026-11-15)
P1-P6 built on `future-ranks-crit` (see `docs/HISTORY.md` 2026-11-15, `tools/perfcheck.lua`).
P7 left: scans are now rare (marks only), so their per-entry cost matters far less.
