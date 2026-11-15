# Full performance and memory review: SpellTuner 0.18.1

2026-11-15, at b0535ca (the CurseForge 0.18.1 release), both lines. The freeze finding is
written up separately in `docs/review/perf-0.18.1.md` (P1-P7); this review covers the whole
addon. The aim is the same feature set at a much smaller CPU and memory cost.
Replay, coach and practice should cost nothing until switched on.

**How it was measured.** The offline harness on a real Lua 5.1 drove the stub client: ticks,
events and a raid-like combat log. Garbage was measured with the collector stopped and time with
`os.clock`. The probes are in `tools/perf/` (not suites; `tools/run.sh [--flavour f]
tools/perf/<name>.lua`) so every fix can be measured against the same baseline.
The stub's spell book has 4 entries, so book numbers are scaled up by entry count. The client's
own cost (tooltip data, generated descriptions) is not in any number here.
Saved-variable sizes are from the author's own TBC and Forever clients.

## Baseline

| What | Forever | TBC |
|---|---|---|
| Source loaded at login | 1.70 MB, 58 files | 2.34 MB, 91 files |
| Generated data resident, all 9 classes | about 630 KB (player's class: about 60 KB) | - |
| Garbage per 0.5 s tick, out of combat / in combat | 4.6 / 6.2 KB | about 1.9 KB (clock) |
| Garbage per `UNIT_POWER_FREQUENT` (several a second) | 1.4 KB | - |
| Garbage per own cast | about 94 KB (stub book), **MBs scaled** | 0.1 KB |
| Garbage per book scan | 108 KB (4 entries); **about 3-4 MB at 180** | - |
| Garbage per combat log event | (forbidden on Forever) | 0.31 KB; **15-60 KB/s in a raid** |
| Saved variables, author's character | 12 KB | **2.3 MB** in memory (1.27 MB file) |
| `ST.API.Call` vs a direct call | 2.2 us vs 0.04 us; 128 bytes per call | same code, no secrets |
| `ST.API.Copy` of a 12-line tooltip | 81 us, 2.2 KB | - |

## Findings, worst first

### Freezes (CPU on a hot path)

**F1. The Forever book rescans from the cast handler, every 2 s, and on every aura** (critical).
`docs/review/perf-0.18.1.md` P1-P4: `UNIT_SPELLCAST_SUCCEEDED` -> `Pool.CostFor` ->
`Book:Get()`. That scans when dirty (any player `UNIT_AURA`) or when the cache is 2 s old.
0.18.1 added about 120-260 never-learned ranks to each scan.
*Fix:* a scan only on events that change the book, never from an event handler or a timer;
`CostFor` reads the cache. *Gain:* the per-cast freeze goes away (about 100+ ms per cast to
about 0).

**F2. A book scan allocates about 20 KB per entry** (high).
Split by part, per entry:
- `BuildEntry` about 8 KB (the copied tooltip table about 2 KB, the parsed description, the
  entry itself);
- the whole-book `BookShape.Check` about 4 KB;
- `EntrySig` strings, `GroupFamilies` and `Rows` the rest.
At 180 entries that is megabytes per scan. That garbage is what makes the client's collector
take long steps, a second source of hitches.
*Fix:*
- keep entries between scans and rebuild only an id whose inputs changed (rank text,
  description, level, gear / talents generation);
- read `SpellTooltipData` only when the description did not parse;
- `BookShape.Check` on the session's first scan only (the suites hold the contract);
- the signature from numbers, not concatenated strings.
*Gain:* a scan that does happen allocates a few KB, not MBs.

**F3. TBC: the combat log handler costs every event in the log** (high in raids).
`UI/Summary.lua:219` runs on all of them (others' swings, damage, heals, auras):
- `Blooms.Aura` for every aura event, of any spell;
- `Targets:NoteCast` for every cast by anyone;
- `FightRecorder:Event` / `EnemyCast` whenever recording, which is the default.
That is 0.31 KB of garbage per event, about 15-60 KB/s in a raid.
*Fix:*
- the subevent and spell-id tests first: `Blooms.Aura` only for Lifebloom's ids;
  `NoteCast` only for the mana-cooldown spell names `Engine/ManaCooldowns.lua` lists, from a
  grouped GUID;
- the recorder only while recording (see M2);
- no varargs re-packing on the drop path.
*Gain:* about 90% of the events return after two comparisons.

**F4. The adapter costs 55x a direct call and a table per call** (medium, everywhere on Forever).
`ST.API.Call`:
- `Pack(pcall(fn, ...))` builds a table each call, with an O(n^2) `select` loop;
- each return value then goes through `IsSecret`, which looks up `Has` twice and runs two
  `pcall`s.
`ST.API.Copy` runs `IsSecret` on every key and every value.
*Fix:*
- resolve `issecretvalue` / `issecrettable` once at load into upvalues;
- `IsSecret` returns false at once when neither exists (TBC);
- a fixed-arity fast path in `Call` (up to 6 returns in locals, `Pack` only past that);
- `Copy` asks `issecrettable` once per table and `issecretvalue` per scalar, with no wrapper
  calls.
*Gain:* about 3-5x faster client reads, and no garbage per call.

**F5. Every tick paints strings and tables, whether anyone reads them** (medium).
- Forever clock tick (`UI/Clock_Forever.lua:443`) about 2.8 KB per tick: `Pool:Project`, the
  face, `ClockWords.Build` and formatted strings, rebuilt every 0.5 s.
- `UI/Feeds.lua:142` `Feeds.Poll` about 2 KB per tick: both feeds' texts are built even when no
  broker or ElvUI datatext consumes them.
- TBC clock (`Engine/TTO.lua:243`) about 1.9 KB per tick.
*Fix:*
- `Feeds.Poll` runs only while a consumer is registered (`Surface_LDB` / `Surface_ElvUI`
  registering);
- the clock reuses its state, face and words tables; a time is formatted only when its
  displayed second changed; nothing is painted while the clock is hidden.
*Gain:* steady garbage from about 10 KB/s to well under 1 KB/s.

**F6. Forever `UNIT_POWER_FREQUENT`: 1.4 KB per event** (medium; several events a second).
The bar's `PaintPower` goes through `pcall` closures and `ST.API.Call` (`DrawUnitPower`)
for each power text, on every event.
*Fix:* F4's fast path; coalesce to at most once per frame (the game eases the bar anyway).

### Memory (resident and saved)

**M1. Forever keeps every class's generated data** (high, about 550 KB).
These stay resident for all 9 classes:
- `ST.TalentTree` about 260 KB (descriptions);
- `ST.FutureRanks` about 248 KB;
- `ST.CoefRules` about 121 KB (by spell id, every class).
The player's class needs about 60 KB of it.
*Fix:* at `CORE_LOGIN`, nil every other class's subtable and filter `CoefRules` to the
player's ids (`FutureRanks`' ids plus the book's). The tables were loaded already, so the
collector frees them. A later step could generate one file per class, loaded on demand.
The talent tree's descriptions are only for the planner, so they could also be loaded when the
planner first opens.

**M2. TBC records every pull by default** (high, about 1.2 MB saved, plus per-event work).
`recordFights = true` in `Core_TBC.lua`. The author's character keeps 1.17 MB of recordings,
about half the saved data, and every fight pays F3's recorder path. Recordings feed replay and
coach, which are meant to be opt-in.
*Fix:* default `recordFights = false` (Forever already loads its Recorder only when switched
on). The fight summary, overheal, calibration and the waste view do not need it. Turning on
Replay / Coach in Settings turns recording on with it.
Existing installs keep their setting; a one-time notice says where the switch is.

**M3. TBC loads replay, coach, simulator and practice code always** (medium, about 760 KB of
source).
`Engine/SimModel.lua`, `SimPlanner.lua`, `UI/ReplayWindow.lua`, `Engine/Practice.lua`,
`SimSolver.lua`, `FightRecorder.lua` and the rest are a third of the TBC load list.
**`Data/SimFixture_BF1.lua`, a test fixture, is listed in `SpellTuner_TBC.toc` and ships.**
*Fix, now:* the fixture leaves the TOC (the harness loads it by path).
*Fix, later:* the same LoadOnDemand siblings Forever has (`SpellTuner_Recorder` / `_Replay` /
`_Practice`) on TBC too. That is a structural task of its own and the gain is code memory only.

**M4. Forever loads tools that run on a command** (medium, about 170 KB of source).
`Client/Probe.lua` (132 KB, runs on `/st probe`) and `Spells/Measure.lua` (39 KB, off until
`/st measure`) load at every login.
*Fix:* one more LoadOnDemand sibling (`SpellTuner_Tools`) loaded by the command, as the three
modules are.

**M5. TBC saved data grows with use** (low-medium).
- `runs` keeps 2 runs (the author's is 0.8 MB);
- `fights` 200 summaries (187 KB);
- `practice` (108 KB).
All of it is read at login and held for the session.
*Fix:* keep `runs` to 1 unless pinned; `fights` drops the per-cast detail of fights older than
the last 50 (the totals stay); practice keeps 4, as now.
**Not a cut for coaching:** a coach that uses old fights reads the totals.

### Smaller items

- **S1.** `Book:Get()` from `UI/SpellTip.lua` on every hover: covered by F1, as the cache
  answers.
- **S2.** `BOOK_CHANGED` rebuilds the Spells rail while the window is closed: rebuild on show
  (perf-0.18.1 P4).
- **S3.** `ST:Debug(...)` costs only its argument evaluation while off. Keep `tostring` /
  `string.format` out of hot call sites' arguments: format inside `Debug`.
- **S4.** The master ticker calls every handler every 0.5 s, including the views'
  hidden-checks. That is fine at this size; no change.

## Design: the author's four rules (2026-11-15), applied

These are the author's four rules. Each one is mapped to the code it changes; F1, F2 and F5
are applications of them.

**1. Scan the part an event touched; sweep the rest in small chunks.**
Each event names what it can have changed. Nothing else is read again:

| Event | What is redone |
|---|---|
| `SPELLS_CHANGED` / `LEARNED_SPELL_IN_TAB` | the slot list; new or removed ids only |
| `PLAYER_LEVEL_UP` | future ranks' learnability; the level penalty (numbers only, no text) |
| talents (`TRAIT_CONFIG_UPDATED`, `PLAYER_TALENT_UPDATE`) | `Book.adjust` over the entries, from their kept text |
| gear, a +healing or crit aura (`UNIT_AURA` filtered to the buffs that move a number) | the +bonus and crit readings, then numbers only; no description, no tooltip |
| a description gone secret / back | that id only |

A **sweeper** catches a missed event. Out of combat it re-reads a few ids per tick (for
example 4 per 0.5 s, so a 180-entry book every about 25 s) and compares each with its kept text.
It pauses in combat. A difference marks that id, never the whole book.

**2. Compute what someone looks at, when they look.**
The book splits into two layers:
- **read:** text, cost, cast, level per id; kept, updated by rule 1;
- **derived:** values with bonus and crit, per mana / per second, marks, What if. Computed per
  family, stamped with the generations it was computed from (bonus, crit, talents, level,
  rules), and recomputed only when a stamp moved **and** something asks.

Who asks for what:
- the cast path asks for a cost only (the read layer, one id);
- the spell tooltip asks for one entry's derived numbers on hover;
- the Spells pane asks for its families when shown;
- the What if builds only while its drawer is open (it already does).
Nothing derives for a closed window.

**3. Keep edge cases off the common path.**
Paths that run on every scan today but matter rarely:
- **future ranks:** only the Spells pane shows them. Read them when the pane opens (and on
  level-up while it is open), never for the cast path or the tooltip;
- **the +bonus fit** (`MeasureBonus`): only when a new reading arrived, not every scan;
- **`BookShape.Check`:** the session's first build only;
- **the stale-text carry:** only for an id whose description is secret now;
- **the talent seam's four rules:** each runs only for the entries its table names (cast
  talents, multipliers, Bloom, crit), indexed by spell name once per talent change;
- **TBC combat log:** the spell / subevent tests first (F3).

**4. Make the code that remains cheap.**
- **Memoise `Parse.Description` by the description string.** On Forever the text changes only
  when +healing, talents or level move it. Most rescans read the same strings, so the parse
  becomes a table lookup. Same for `Parse.Rank` and `Parse.Clean`.
- The adapter's fast path and the leaner `Copy` (F4).
- Signatures from numbers, not concatenated strings (F2).
- No `table.sort` of names per scan, kept sorted at insert.
- Reused tables in the clock and the feeds (F5); the feeds' texts only for a consumer.

With rules 1-3 most of a scan's work never happens. Rule 4 makes the rest cheap.
Expected: a cast costs a table lookup; an aura costs a number refresh for the families the
open views show; a book read is a handful of ids at a time.

## What is already right
- Forever's Recorder / Replay / Practice are LoadOnDemand and load only when switched on
  (`Core.lua` `CORE_READY` loads a module only when `db.modules[name] == true`).
- The Spells pane's and Clock settings' ticks return at once while hidden.
- The Forever clock tick reads no book; spell data loads are asked once per id.
- No `OnUpdate` runs on a hidden frame. The clock's line driver is a child of the clock, so it
  stops when the clock hides.

## Plan

| Step | Items | Size | Effect |
|---|---|---|---|
| 0.18.2 (now) | F1 (P1-P4 of perf-0.18.1), fixture out of TBC TOC | small | the freeze gone |
| 0.18.3 | M1, M2, F5, F2 (entry reuse, Check once) | medium | about -0.6 MB Forever resident, -1.2 MB TBC saved, steady garbage about -90% |
| 0.18.4 | F3, F4, F6 | medium | raid combat log cost about -90%, client reads 3-5x cheaper |
| later | M3, M4 (LoadOnDemand siblings), M5 | large | code memory about -0.9 MB TBC / -0.2 MB Forever |

Each step:
- runs the `tools/perf/` probes before and after, and records the numbers in `docs/HISTORY.md`;
- adds a `perf:` line to `/st dump`: scans this session, last scan ms (`debugprofilestop`), the
  addon's memory (`UpdateAddOnMemoryUsage` / `GetAddOnMemoryUsage`). That way a player's report
  gives in-game numbers instead of harness ones.
