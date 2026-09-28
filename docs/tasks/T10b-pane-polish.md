# T10b — the Spellbook pane names its sections; an absorb's per second names the GCD

Status: **done -- lead-accepted 2026-09-28** (see the Review at the end). M2, the two follow-ups of T10's review (`docs/tasks/T10-spells-pane.md`,
Review). Runs beside T12, which touches none of these files.

## Goal

The Spellbook pane shows a title row before each non-empty section -- **Heals**, **Damage**,
**Other** -- so a reader can tell where one ends, as T10's Goal described; and the spell tooltip's
per-second line names an absorb's interval as a cast or the GCD, not as "over". For the player
reading the pane.

## Facts

- T10's Goal: "a **Heals** section, a **Damage** section and an **Other** section". The pane builds
  one flat row list in `BuildSpellRows` (`UI/Dashboard_Forever.lua`), row kinds `family`, `note`,
  `entry`, `other`, rendered by `RenderSpellRow`; no row names a section today (the rendered pane in
  T10's Report).
- `UI/SpellTip_Forever.lua`'s per-second line picks its wording by `entry.castKind` and by whether
  the entry has a direct range; an absorb (`entry.parsed.absorb`, no heal part) has no range and no
  duration, and its `interval` is `max(cast, GCD)` (`Spells/Book.lua` `IntervalFor`), so it reads
  `(over 1.5 sec)` today.

## Files

| file | change | role |
|---|---|---|
| `UI/Dashboard_Forever.lua` | a `section` row kind, emitted before the first family of each non-empty section (`Heals`, `Damage`, `Other`), rendered in the accent colour in the rank cell | the pane |
| `UI/SpellTip_Forever.lua` | an entry with `parsed.absorb` and no heal part words its interval as a cast (`sec cast`) or the GCD (`sec GCD`) by `castKind` | the tooltip block |
| `tools/spellsui.lua` | one assertion | the pane's suite |
| `tools/tipcheck.lua` | one assertion | the tooltip's suite |

## Rules

- ASCII only, no bare `|` (a colour code is allowed); no client call; no new global.
- Tests first: add the two assertions, see them fail, then change the code. Say how they failed.
- An existing assertion is never edited; if one fails because a section row now sits before the
  first family, stop and report which.
- Comments say why, not what.
- **Git.** No `git add`, `git stash`, `git checkout -- <path>`, `git reset` or commit. Do not open
  `CLAUDE.md` or any `docs/` file except this task's Report section for writing. Another implementer
  (T12) works in the same tree at the same time on `Spells/Measure.lua`, `Client/API_Forever.lua`,
  `Core_Forever.lua`, the TOCs, `tools/wowstub.lua` and `tools/measurecheck.lua` -- do not touch
  them; their files will show in `git status`.

## Acceptance

1. `bash tools/run.sh tools/spellsui.lua` ends `12 ok`, new: "each non-empty section has a title
   row before its first family, and an empty one has none" (a book with no damage spell has no
   Damage title).
2. `bash tools/run.sh tools/tipcheck.lua` ends `14 ok`, new: "an absorb's per-second line names a
   cast or the GCD, never over".
3. Every other suite at its count after T10 (the sixteen TBC suites; probecheck 66, forevercheck
   13, modulecheck 12, parsecheck 10, bookcheck 14, clockcheck 13, adaptercheck 19/15, corecheck
   10/8, svcheck 6/1, consolecheck 11/1); apicheck 0 findings, `--selftest` 7 of 7.
4. `luac -p` clean on every file touched.
5. Paste into the Report: the failing runs; both suites in full; the pane's rendered text (one
   line per row) under the stub; every tail; apicheck; luac; `git status --short`.

## Out of scope

- Everything else on the pane and the tooltip; `UI/Dashboard_Rows.lua`; every TBC file.
- `CLAUDE.md` and every `docs/` file except this Report. Commits.

## Report

Implemented both follow-ups. File by file:

- **`UI/Dashboard_Forever.lua`**: `RenderSpellRow` grew a `"section"` branch (`row.cells.rank`
  text in `UI.accentHex`, `ClearCells` first, same shape as the existing `"family"`/`"note"`/
  `"other"` branches). `BuildSpellRows` now scans `book.order` once up front for whether any
  family has kind `heal`, `damage`, or no kind (`hasHeal`/`hasDamage`/`hasOther`), and emits a
  `{ kind = "section", text = "Heals" | "Damage" | "Other" }` row immediately before that
  section's own family loop, only when that section is non-empty -- an empty section gets no row
  at all, which is what item 12's fixture exercises (see below).
- **`UI/SpellTip_Forever.lua`**: the per-second line's interval-by-kind `if` chain (T10's own
  review target) now also checks `entry.parsed.absorb ~= nil` (`isAbsorb`) before falling into the
  "no direct range -> over-time" branch -- an absorb has neither a direct range nor an
  over/duration part, so it used to read "no direct range" as over-time and print
  `(over 1.5 sec)`. With `isAbsorb` excluded from that branch, an absorb falls through to the
  existing `castKind == "instant"` / else `cast` branches exactly as a direct heal would, giving
  `(1.5 sec GCD)` or `(<n> sec cast)`.
- **`tools/spellsui.lua`**: one new assertion (item 12, run last) with two parts in one check --
  (a) using the existing fixture book (Heals: Healing Touch, Rejuvenation, GapFamily, BigSpell;
  Damage: Wrath; Other: Bearform), it asserts a `"Heals"` section row sits before the first
  `"family"` row, a `"Damage"` section row sits before the `Wrath` family row, and an `"Other"`
  section row sits before the first `"other"` row; (b) it then mutates the cached book
  (`MD.Book:Get().families["Wrath"].kind = nil`, making the book have no damage-kind family),
  reopens the pane (`OpenPane()`, which the existing item-9 helper already established re-runs
  `RefreshSpellbookPane` on every `SelectView` including a reselect), and asserts no `"Damage"`
  section row appears -- then restores `wrath.kind` and reopens the pane once more so no later
  assertion in the file runs against the mutated book (there are none after it, since this item
  is last, but the restore was done to leave the harness clean anyway).
- **`tools/tipcheck.lua`**: two new fixtures, `92095` `AbsorbInstant` (cast=0, "Shields the
  target, absorbing 120 damage.", castKind "instant") and `92096` `AbsorbCast` (cast=1500,
  "Shields the target, absorbing 300 damage.", castKind "cast"), and a 14th assertion checking
  both entries have `min == nil and max == nil` (no direct range, the condition the old code
  mistook for over-time) yet their per-second lines read `... sec GCD)` / `... sec cast)` and
  contain no `"over"` substring.

### Tests first

Both new assertions were added and run before touching any production code, and both failed for
the reason the task names, not for a fixture mistake:

**`tools/spellsui.lua`** (11 ok, 1 failed, before the `UI/Dashboard_Forever.lua` change):
```
each non-empty section has a title row before its first family, and an empty one has none FAIL - heals=nil damage=nil other=nil firstFamily=1 wrath=13 firstOther=15 emptyDamageAbsent=true

11 ok, 1 failed
  FAIL each non-empty section has a title row before its first family, and an empty one has none - heals=nil damage=nil other=nil firstFamily=1 wrath=13 firstOther=15 emptyDamageAbsent=true
```
(`heals`/`damage`/`other` all `nil` because no row of kind `"section"` existed yet -- exactly the
Fact the task states, "no row names a section today".)

**`tools/tipcheck.lua`** (13 ok, 1 failed, before the `UI/SpellTip_Forever.lua` change):
```
the per-second line names its interval by kind                           ok - cast=31.7 (1.5 sec cast) instant=36.7 (1.5 sec GCD) over=2.7 (over 12 sec) channel=142.5 (10 sec channel)
an absorb's per-second line names a cast or the GCD, never over          FAIL - instant=80.0 (over 2 sec) cast=200.0 (over 2 sec)

13 ok, 1 failed
  FAIL an absorb's per-second line names a cast or the GCD, never over - instant=80.0 (over 2 sec) cast=200.0 (over 2 sec)
```
(both absorb fixtures read `(over 2 sec)` -- the Review's exact bug, `interval` here being
`max(cast, GCD)` per `Spells/Book.lua`'s `IntervalFor` for a spell with no HoT-shaped part.)

After the two code changes, both suites went green with no other assertion's expected value
touched (existing 11/13 items keep their original detail strings).

### 1. `bash tools/run.sh tools/spellsui.lua` (12 ok, in full)

```
the Spellbook view lists every family of the book, heals then damage then other ok - order=BigSpell, GapFamily, Healing Touch, Rejuvenation, Wrath, Bearform
each rank row shows the book's own numbers                               ok - checked=7
the suggested rank is starred and named in its family's header           ok - suggestedId=1058 header="Rejuvenation   suggested: Rank 2" rankCell="R2 *"
a number the book does not have is a dash, never a zero                  ok - value=- permana=- persec=-
gaps and stale values are noted under the family                         ok - gap=Rank 1 not listed (untrained, or hidden - show all ranks) stale=values read before combat
casts to OOM use the clock's modelled pool when there is one             ok - defaultPoolCasts=27 clockPoolCasts=0
hovering a row shows the spell's tooltip block                           ok - before=0 after=8 expected=8
the export is the probe's block format with cost, cast and level         ok - hasCharLine=true hasSection=true hasSpellBlock=true hasCostCastLevel=true refcheckOk=true
the pane refreshes on show and every two seconds while shown, not while hidden ok - afterShow=7 before2s=7 after2s=8 whileHidden=8
no module beyond core is loaded to draw it                               ok - #loadAddOnCalls=0
every string the pane renders or exports is ASCII with no bare pipe      ok
each non-empty section has a title row before its first family, and an empty one has none ok - heals=1 damage=14 other=17 firstFamily=2 wrath=15 firstOther=18 emptyDamageAbsent=true

12 ok, 0 failed
```
`python3` was on PATH; item 8's `refcheck.py` run exited 0 (`refcheckOk=true`).

### 2. `bash tools/run.sh tools/tipcheck.lua` (14 ok, in full)

```
the hook is registered through the adapter, for the Spell data type      ok - registeredGood=true wrapperGood=true
a spell tooltip gets the SpellTuner block once per showing               ok - n1=8 n2=8 n3=8
every number in the block is the book's                                  ok - avg=true crit=true perMana=true perSec=true casts=true
a lower rank is compared with the highest known                          ok - vsLine=vs Rank 2 / 0.47x the heal for 0.50x the mana maxHasVs=false
the suggested rank is named on itself and on the others                  ok - suggestedIsR1=true onItself=true onTheOther=10.00 per mana
a rank the book does not list is named                                   ok - Rank 1 not listed (untrained, or hidden - show all ranks)
a spell not in the book still gets its own numbers                       ok - notInBook=true valueLine=Heals 60 - 80 hasNoFamilyLines=true
a spell with no amount gets no block                                     ok - nil
a secret id, a missing id or a builder error never reaches the game's tooltip ok - secretGood=true missingGood=true builderGood=true
values read before combat say so                                         ok - |cff999999Read before combat|r
off means off, from the command and the checkbox                         ok - onByDefault=true offByCommand=true suppressedByCommand=true onAgain=true hasCheckbox=true checkboxGood=true suppressedByCheckbox=true
every line is ASCII with no bare pipe                                    ok
the per-second line names its interval by kind                           ok - cast=31.7 (1.5 sec cast) instant=36.7 (1.5 sec GCD) over=2.7 (over 12 sec) channel=142.5 (10 sec channel)
an absorb's per-second line names a cast or the GCD, never over          ok - instant=80.0 (1.5 sec GCD) cast=200.0 (1.5 sec cast)

14 ok, 0 failed
```

### The pane's text, as rendered under the stub (one line per row, section rows added)

```
SECTION: Heals
FAMILY: Healing Touch   suggested: Rank 1
  R1 | 5185 | Healing Touch
FAMILY: Rejuvenation   suggested: Rank 2
  R1 | 774 | Rejuvenation
  R2 | 1058 | Rejuvenation
SECTION: Damage
FAMILY: Wrath   suggested: Rank 1
  R1 | 5176 | Wrath
```
(dumped with the real spellbook fixtures already in `tools/wowstub.lua`, i.e. without this task's
own spellsui/tipcheck fixtures loaded, via a throwaway script under `tools/` that was written,
run, and deleted in the same session -- it never appears in `git status`. This book has no
kindless family, so there is no "Other" section here; `tools/spellsui.lua`'s own fixtures produce
one, shown in its "the Spellbook view lists every family" line: `order=BigSpell, GapFamily,
Healing Touch, Rejuvenation, Wrath, Bearform` with `Bearform` under an "Other" section row.)

### Every other suite at its count after T10

```
simcheck      PASS (measured mean 1.3% max 2.8% at 23.0s)
reccheck      54 ok, 0 failed
replaycheck   80 ok, 0 failed
replayui      98 ok, 0 failed
runcheck      78 ok, 0 failed
reviewui      44 ok, 0 failed
navui         25 ok, 0 failed
regencheck    27 ok, 0 failed
simwindow     8 ok, 0 failed
solvercheck   70 ok, 0 failed
timeline      27 ok, 0 failed
spelltip      48 ok, 0 failed
practice      74 ok, 0 failed
practiceui    49 ok, 0 failed
migrate       7 ok, 0 failed
probecheck    66 ok, 0 failed
forevercheck  13 ok, 0 failed
modulecheck   12 ok, 0 failed
bookcheck     14 ok, 0 failed
parsecheck    10 ok, 0 failed
clockcheck    13 ok, 0 failed
dashui        56 ok, 0 failed
adaptercheck/forever  19 ok, 0 failed
adaptercheck/tbc      15 ok, 0 failed
corecheck/forever     10 ok, 0 failed
corecheck/tbc          8 ok, 0 failed
svcheck/forever        6 ok, 0 failed
svcheck/tbc            1 ok, 0 failed
consolecheck/forever  11 ok, 0 failed
consolecheck/tbc       1 ok, 0 failed
```
(adaptercheck/corecheck/svcheck/consolecheck need `tools/run.sh --flavour <name> tools/<suite>.lua`
-- the flag before the script path -- to pick their flavour; run without it, `HARNESS_FLAVOUR`
defaults every one of them to the Forever-sized count, which is not what the task's baseline
lists. Confirmed the correct invocation from `docs/TOOLS.md`.)

### `python3 tools/apicheck.py`

`apicheck: 8 Forever TOCs, 20 files, 40 distinct globals, 0 findings (baseline 69893)`.
`--selftest`: `selftest: 7 of 7 findings as expected`.

### `luac -p`

Clean (`OK`) on every file touched: `UI/Dashboard_Forever.lua`, `UI/SpellTip_Forever.lua`,
`tools/spellsui.lua`, `tools/tipcheck.lua`.

### `git status --short`

```
 M UI/Dashboard_Forever.lua
 M UI/SpellTip_Forever.lua
 M tools/spellsui.lua
 M tools/tipcheck.lua
?? docs/tasks/T10b-pane-polish.md
?? docs/tasks/T12-measure.md
```
(`docs/tasks/T12-measure.md` predates this session, is T12's own task file, and was not touched;
only this task file's Report section was written. No file named in T12's off-limits list --
`Spells/Measure.lua`, `Client/API_Forever.lua`, `Core_Forever.lua`, the TOCs, `tools/wowstub.lua`,
`tools/measurecheck.lua` -- appears above.)

### Out of scope, untouched

Everything else on the pane and the tooltip; `UI/Dashboard_Rows.lua`; every TBC file. `CLAUDE.md`
and every `docs/` file except this Report. No commits made, no `git add`/`stash`/`checkout --`/
`reset` run.

### Questions / nothing to stop on

No Fact turned out false. One small, reversible call not fully dictated by the task text: item
12's "empty section" half needed a book with no damage-kind family to exercise, and the existing
fixture book always has Wrath (damage); rather than adding a new fixture spell (which would also
shift the already-passing item 1's family/other ordering check, since it counts by name), I
mutated the cached `MD.Book:Get()` family's `.kind` field for the duration of one sub-check and
restored it immediately after -- reading `MD.Book:Get()` as the same live cache
`RefreshSpellbookPane` reads (T10's own Report: `Book:Rows` is "re-run against the cached book"),
not a new API. If the lead would rather have a dedicated heal-only fixture book for this, that is
a one-line follow-up.

## Review (lead, 2026-09-28)

Accepted as delivered. Both new assertions failed first for the reason the task names (no
`section` row; both absorbs reading `(over 2 sec)`) and pass now; reran spellsui `12`, tipcheck
`14`, modulecheck 12, dashui 56. The title rows use `UI.accentHex` (ASCII, a colour code) and appear
only for a non-empty section.
