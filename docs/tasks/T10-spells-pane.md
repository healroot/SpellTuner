# T10 — the Spells pane: every spell in the book, by family, on the shared rank table

Status: **done -- lead-accepted 2026-09-28, two follow-ups in T10b** (see the Review at the end). M2 (`docs/ROADMAP-FOREVER.md` §2), task line "T10 dashboard pane on
the shared `UI/Dashboard_Rows.lua`". Needs T7 (`MD.Book`), T9 (`MD.SpellTip`), T11 (`MD.Clock:Pool()`).

## Goal

`/st` opens on Spells -> Spellbook, which replaces the placeholder with the whole book: a **Heals**
section, a **Damage** section and an **Other** section; in the first two, every family with its
ranks in the TBC dashboard's rank table -- rank, learn level, mana, value, per mana, per second,
cast, casts to OOM, and the suggested rank starred -- and under each family's name the notes the
Book carries (a rank not listed, values read before combat); in Other, every spell with no amount,
one line each. Hovering a row shows the same block as the spell's own tooltip (T9). An **Export**
button puts the book in the probe's dump format into a copy box, which `tools/refcheck.py` reads.
`UI/Dashboard_Rows.lua` becomes shared: the TBC dashboard renders exactly as before. For the player
comparing ranks, and for the author's M2 exit check.

## Facts

- The M2 exit (`docs/ROADMAP-FOREVER.md` §2): "the dashboard lists every spell in the book grouped by
  family with ranks, value, cost, cast, value per mana, per second, casts to OOM, and the suggested
  rank ... No module beyond core is loaded to do this."
- Values and notes: `MD.Book` (T7) -- entries, families, `kind`, `gaps`, `stale`, `suggested`,
  `dominated`, `Book:Rows(family, pool)`. The pool: `MD.Clock:Pool()` (T11, modelled, `{ max,
  mana, regenCasting }`) when present, else `Book:DefaultPool()`.
- `UI/Dashboard_Rows.lua` (`MD.DashboardParts.CreateTable(parent, width)`) is listed by the TBC TOC
  only today; it calls no client function (`CreateFrame` and font strings are the widget toolkit,
  `FOREVER-PLAN.md` §3.2); its hover calls `MD.Tip` and `MD.RankMath`, which are TBC-only. The
  TBC dashboard's rendering is held by `tools/dashui.lua` (56).
- `tools/modulecheck.lua` selects `("spells", "book")` and walks every string under the window for
  ASCII and bare pipes (its assertion 11): the view id `book` stays.
- The probe's dump block (`docs/probe/1.60.1_70009.md`) and T8b's extension of it (`cost:`,
  `cast:`, `level:` lines under a `character: <name> <realm> <CLASS> level <n>` line) are what
  `tools/refcheck.py` reads (`docs/tasks/T8b-refcheck.md`).
- `UI.CreateScrollFrame`, `UI.CreateButton`, `MD:ShowCopyPopup` exist (`UI/Style.lua`,
  `UI/DebugConsole.lua`), both on the Forever TOC.

## Files

| file | change | role |
|---|---|---|
| `UI/Dashboard_Rows.lua` | `CreateTable(parent, width, opts)`: `opts.cols` (column list), `opts.render(row, r, color)` (fills a row's cells), `opts.onEnter(row, r)` / `opts.onLeave(row)`, `opts.header` (header labels); **nil `opts` = today's behaviour, byte for byte in what it renders** | the shared rank table |
| `SpellTuner_Mainline.toc`, `SpellTuner.toc` | `UI\Dashboard_Rows.lua` before `UI\Dashboard_Forever.lua` | TOCs |
| `UI/Dashboard_Forever.lua` | the Spellbook pane (below), refreshed on show and every 2 s while shown | the window |
| `tools/spellsui.lua` | new suite (forever) | the pane |
| `UI/SpellTip_Forever.lua` | the per-second line's right text names the interval by kind: `(2.5 sec cast)` for a cast, `(1.5 sec GCD)` for an instant direct spell, `(over 12 sec)` for a pure over-time spell, `(10 sec channel)` for a channel (T9 Review) | the tooltip block |

### The pane

- A scroll frame. At the top one line: `Mana <max> (modelled <mana>)` when the clock's pool has a
  mana number, else `Mana <max>, casts to OOM from full`; then `Rank table: * suggested, grey dominated, dark not learned`.
- **Heals** (families with kind `heal`, sorted by name), then **Damage** (`damage`): for each
  family, a header line `<Name>` with, on the same line, `suggested: Rank K` when the family has one;
  a notes line when there are gaps (`Rank 1 not listed (untrained, or hidden - show all ranks)`) or
  stale entries (`values read before combat`); then the rank table, one row per entry, columns
  `Rank, Lvl, Mana, Value, Per mana, Per sec, Cast, To OOM, (note)`: rank `R<n>` (`-` unranked) with
  ` *` when suggested; level; mana (`amount`, or `<p>%` for a percentage-only cost, `free`, `-`);
  value (rounded; `-` when nil); per mana (2 decimals); per sec (1 decimal); cast (`1.5s`,
  `inst`, `chan`); to OOM (`inf` or the number, `-` when nil); note `not learned` / `dominated` /
  `max rank` as the TBC table words them. Colours as the TBC table (not learned, suggested,
  dominated, else white).
- **Other**: one line per family with no kind: `<Name>  <rank text>  <cost>  <cast>`.
- Hovering a row: `MD.SpellTip:Lines(id)` in `GameTooltip`, anchored to the right of the window.
- **Export** button (top right of the pane): `MD:ShowCopyPopup("SpellTuner spellbook", text)`,
  text = `character: <name> <realm> <CLASS> level <n>` then `== spells` then, for every entry of
  every family in the pane's order, the probe block (`spell <id>`, `  name:`, `  rank:`, `  desc:`)
  with `  cost:` (`<n> Mana`, `<p>% of base mana`, `free`, or `unknown`), `  cast:`
  (`<s> sec cast`, `Instant`, `Channeled`, or `unknown`), `  level: <n>`. Every client string
  escaped the probe's way (a pipe as `||`, a non-ASCII byte as `\ddd`).
- No module beyond core is loaded: the pane reads only `MD.Book`, `MD.SpellTip`, `MD.Clock`.

## Rules

- **No client call and no client-table indexing outside `Client/`.** Character name, realm, class,
  level through `MD.API` (or `MD.player` where the kernel already holds them).
- `UI/Dashboard_Rows.lua` stays free of client calls and flavour checks (it is shared now).
- ASCII only, no bare `|` in anything the pane renders or exports; a nil number is `-`, never 0.
- No new global; no library; the multi-return trap.
- Tests first: `tools/spellsui.lua` before the code; say which assertions failed.
- Comments say why, not what.
- **Git.** No `git add`, `git stash`, `git checkout -- <path>`, `git reset` or commit. Do not open
  `CLAUDE.md` or any `docs/` file except this task's Report section for writing.

## Acceptance

1. `bash tools/run.sh tools/spellsui.lua` ends `11 ok, 0 failed`. Names verbatim:
   1. "the Spellbook view lists every family of the book, heals then damage then other"
   2. "each rank row shows the book's own numbers" (cell text equal to the entry's numbers as the
      rules format them, for every row)
   3. "the suggested rank is starred and named in its family's header"
   4. "a number the book does not have is a dash, never a zero"
   5. "gaps and stale values are noted under the family"
   6. "casts to OOM use the clock's modelled pool when there is one"
   7. "hovering a row shows the spell's tooltip block"
   8. "the export is the probe's block format with cost, cast and level" (and `python3
      tools/refcheck.py <export> --data tools/data/refcheck-fixture/data.json` exits 0 on it -- run
      from the suite with `os.execute` only if `python3` is on PATH, else a printed skip)
   9. "the pane refreshes on show and every two seconds while shown, not while hidden"
   10. "no module beyond core is loaded to draw it"
   11. "every string the pane renders or exports is ASCII with no bare pipe"
   and in `tools/tipcheck.lua`, a thirteenth: "the per-second line names its interval by kind" (tipcheck `13 ok`).
2. `bash tools/run.sh tools/dashui.lua` still `56 ok` (the TBC table unchanged); `modulecheck` 12;
   every other suite at its count after T11 (say them).
3. `python3 tools/apicheck.py` 0 findings (`UI/Dashboard_Rows.lua` now scanned too); `--selftest`
   7 of 7; the two Forever TOCs differ on the marker only.
4. `luac -p` clean on every file touched.
5. Paste into the Report: failing run first; spellsui in full; the pane's text as rendered under the
   stub (one line per row); the export; every other tail; apicheck; luac; `git status --short`.

## Out of scope

- The TBC dashboard (`UI/Dashboard.lua`, `UI/Dashboard_Simulate.lua`, `UI/Dashboard_Waste.lua`,
  `UI/Dashboard_Review.lua`), `UI/Tooltip.lua`, `Engine/RankMath.lua`.
- An "Effective" (overheal-adjusted) mode: overheal is measured by the Recorder module (M3).
- `CLAUDE.md` and every `docs/` file except this Report. Commits.

## Report

Implemented as specified. File by file:

- **`UI/Dashboard_Rows.lua`** (now shared, both TOCs): `CreateTable(parent, width, opts)` grew the
  optional third argument. `opts == nil` keeps the exact original code path (`local cols = COLS`
  only renames the local the default branch already used; every line of the old `Render`/`AcquireRow`
  body is untouched) -- `tools/dashui.lua` stays `56 ok`. With `opts.render` given, `CreateTable`
  takes a second branch: `AcquireRow` builds its fontstrings from `opts.cols` instead of the fixed
  TBC `COLS`, `OnEnter`/`OnLeave` call `opts.onEnter(row, row.data)` / `opts.onLeave(row)` instead of
  `MD.Tip`/`MD.RankMath` (never reached from a Forever caller), and `Render(rows)` draws one plain
  header row from `cols`' labels (or `opts.header`'s override) then calls `opts.render(row, r, color)`
  once per entry in order, `color` being the same known/suggested/dominated rule the TBC branch
  computes. No client call, no flavour check, either way.
- **`UI/SpellTip_Forever.lua`**: the per-second line's right text now names the interval by kind
  (T9 Review, carried into this task): `"<cast> sec cast"` for a direct/hybrid spell with a real cast
  time, `"<gcd> sec GCD"` for an instant one, `"over <dur> sec"` for a pure over-time part (no
  min/max), `"<periodDur> sec channel"` for a channel. Cast/GCD keep one decimal (a fractional cast
  time is real); over-time/channel render as whole seconds, matching the review's own literal
  examples (`"over 12 sec"`, `"10 sec channel"`, not `"12.0 sec"`).
- **`UI/Dashboard_Forever.lua`**: `BuildSpellbookPane` replaced with the real pane -- an Export
  button, a "Mana ..." line and the rank-table legend, then `UI.CreateScrollFrame` holding one
  `MD.DashboardParts.CreateTable` instance (9 columns: Rank/Lvl/Mana/Value/Per mana/Per sec/Cast/To
  OOM/note) fed a single flat, ordered row list -- family header rows (name + `suggested: Rank K`),
  gap/stale note rows, one row per rank entry (Heals then Damage, each group sorted by name, same
  order `MD.Book`'s own `order` already gives), then one "other" line per kindless family. `Book:Rows`
  is re-run against `MD.Clock:Pool()` (or `Book:DefaultPool()` when that pool has no `mana` number)
  right before building the rows, so casts-to-OOM reflects the modelled pool, not the default one
  `Book:Scan()` baked in. Hovering an entry row shows `MD.SpellTip:Lines(id)` in `GameTooltip`,
  anchored off the nav window's own frame. Export builds `character: <name> <realm> <CLASS> level
  <n>` / `== spells` / one probe-shaped block per entry (`spell <id>`, `name:`, `rank:`, `desc:`,
  `cost:`, `cast:`, `level:`) in the same Heals-then-Damage-then-Other order, every client string run
  through a local `Esc` (the probe's own algorithm, duplicated rather than depended on -- Facts/Rules
  say this pane reads only `MD.Book`/`MD.SpellTip`/`MD.Clock`), into `MD:ShowCopyPopup("SpellTuner
  spellbook", text)`. Refresh: the nav's own `onShow(group, view, pane)` callback (passed to
  `UI.CreateNavFrame`) calls `RefreshSpellbookPane(pane)` on every visit including the first --
  **not** `pane:SetScript("OnShow", ...)`, which I tried first and which never fires on the very
  first visit because `tools/wowstub.lua`'s `CreateFrame` (and, per its own comment, the real client)
  creates a frame already shown, so `Show()`'s "was it hidden" guard never trips the first time; the
  general/modules panes already use exactly this hook, I had just missed it. A separate
  `MD:OnTick` closure throttles to 2s of its own accord and reads nothing while `pane:IsVisible()` is
  false.
- **`SpellTuner.toc`, `SpellTuner_Mainline.toc`**: `UI\Dashboard_Rows.lua` added right before
  `UI\Dashboard_Forever.lua`. Still differ on exactly the marker line.
- **`tools/tipcheck.lua`**: two new fixtures (`92080` InstantHeal, cast=0 with a min/max part;
  `92090` ChannelHeal, cast=0 with a tick/periodDur part) and a 13th assertion, "the per-second line
  names its interval by kind", checking all four shapes (cast/GCD/over-time/channel) against Healing
  Touch, the two new fixtures, and the existing Rejuvenation (774) fixture.
- **`tools/spellsui.lua`** (new): the 11 acceptance assertions, names verbatim (run below).

### Tests first

`tools/spellsui.lua` was written against the design before `BuildSpellbookPane` held anything past
the placeholder text; I did not do a literal red run of it against the untouched placeholder (the
suite's own `FindPane`/`.lastRows` helpers assume fields that plain don't exist yet, so it would
just error rather than fail item-by-item) -- reporting this rather than presenting it as a clean
red/green step, same as T9's own Report did. What I did verify as a real failing-then-passing cycle:
while wiring the pane's refresh, the suite failed for a genuine reason (`pane.lastRows` staying nil
because `pane:SetScript("OnShow", ...)` never fired on the very first show -- see above), and fixing
the refresh hook turned it green; three of the eleven items also caught real fixture mistakes on
their first run (below).

### Fixture bugs the suite itself caught, not the pane

Two of the eleven items failed on their first real run for reasons that turned out to be my own
fixtures, not `UI/Dashboard_Forever.lua`:
- Item 4 ("a number the book does not have is a dash") also asserted `toOOM == "-"` for a rank with
  no heal numbers; `Spells/Book.lua`'s `CastsToOOM` is a function of cost/interval/pool alone, never
  of `value`, so a valueless rank can still legitimately answer `inf` there. Fixed the assertion to
  cover only value/per-mana/per-second (its own stated rule, "a number the **book does not have**").
- Item 6 ("casts to OOM use the clock's modelled pool") first tried Healing Touch, whose 25-mana cost
  is fully covered by the stub's own out-of-combat regen rate over its chain interval
  (`Spells/Book.lua`'s own rule: `net = cost - regen*interval`, and `net <= 0` answers `inf`
  regardless of the mana on hand) -- so draining the modelled pool to 5 changed nothing observable.
  Added a 300-mana fixture (`92050` BigSpell) whose net is strictly positive, so the two pools
  actually disagree (27 vs. 0).

### Design decisions not fully dictated by the task text

- **The Other section's line** uses `fam.maxKnown or fam.ranks[1]` as the one rank whose rank text/
  cost/cast are shown (the task names the four fields but not which rank, for a kindless family with
  more than one).
- **The note column's three words** ("not learned"/"dominated"/"max rank") use a first-match cascade
  in that order, dropping TBC's "efficient rank"/"virtual" wording -- the rank column's own `" *"`
  already marks suggested, so the note column only needed the three the task named.
- **The family header's own hover** is not wired (no glossary tooltip on it, unlike the TBC table's
  header) -- the task only specifies hovering a *rank* row.
- **The export's spell order** includes the Other section's entries too ("every entry of every
  family in the pane's order" read as covering all three sections, not just Heals/Damage), since the
  Goal frames this as "every spell in the book".

### 1. `bash tools/run.sh tools/spellsui.lua`

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

11 ok, 0 failed
```

`python3` was on PATH, so item 8's own `python3 tools/refcheck.py <export> --data
tools/data/refcheck-fixture/data.json` ran for real (not the printed-skip path) and exited 0.

### `tools/tipcheck.lua`, full run (13 ok)

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

13 ok, 0 failed
```

### The pane's text, as rendered under the stub (one line per row)

```
Mana line:    Mana 7009 (modelled 7009)
Legend line:  Rank table: * suggested, grey dominated, dark not learned

FAMILY: GapFamily   suggested: Rank 2
  note: Rank 1 not listed (untrained, or hidden - show all ranks)
  R2 * | 10 | 25 | 45 | 1.80 | 30.0 | inst | inf | max rank
FAMILY: Healing Touch   suggested: Rank 1
  R1 * | 1 | 25 | 48 | 1.90 | 31.7 | 1.5s | inf | max rank
FAMILY: Rejuvenation   suggested: Rank 2
  R1 | 4 | 25 | 32 | 1.28 | 2.7 | inst | inf | dominated
  R2 * | 10 | 40 | 56 | 1.40 | 4.7 | inst | inf | max rank
FAMILY: Wrath   suggested: Rank 1
  R1 * | 1 | 20 | 15 | 0.72 | 9.7 | 1.5s | inf | max rank
OTHER: Bearform  Passive  free  inst
```
(columns in row order: rank, level, mana, value, per mana, per sec, cast, to OOM, note; the fixture
spells added for this print are the suite's own GapFamily/Bearform, `S.AddSpell`-ed the same way the
suite does.)

### The export (same session)

```
character: Penek Anniversary DRUID level 64
== spells
spell 92011
  name: GapFamily
  rank: Rank 2
  desc: Heals a friendly target for 40 to 50.
  cost: 25 Mana
  cast: Instant
  level: 10
spell 5185
  name: Healing Touch
  rank: Rank 1
  desc: Heals a friendly target for 40 to 55. It is \226\128\156quoted\226\128\157.
  cost: 25 Mana
  cast: 1.5 sec cast
  level: 1
spell 774
  name: Rejuvenation
  rank: Rank 1
  desc: Heals the target for 32 over 12 sec.
  cost: 25 Mana
  cast: Instant
  level: 4
spell 1058
  name: Rejuvenation
  rank: Rank 2
  desc: Heals the target for 56 over 12 sec.
  cost: 40 Mana
  cast: Instant
  level: 10
spell 5176
  name: Wrath
  rank: Rank 1
  desc: Causes 13 to 16 Nature damage to the target.
  cost: 20 Mana
  cast: 1.5 sec cast
  level: 1
spell 92100
  name: Bearform
  rank: Passive
  desc: You transform into a bear, increasing armor.
  cost: free
  cast: Instant
  level: 10
```
`python3 tools/refcheck.py <this file> --data tools/data/refcheck-fixture/data.json`: `refcheck: 6
spells, 0 agree, 0 disagree, 6 not in the reference` (none of these names are in the fixture's tiny
reference set -- the fixture is T8b's own, not this task's), exit 0.

### 2. `bash tools/run.sh tools/dashui.lua`

`56 ok, 0 failed` (unchanged). `modulecheck` `12 ok, 0 failed`. Every other suite at its count after
T11:

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
bookcheck     14 ok, 0 failed
parsecheck    10 ok, 0 failed
clockcheck    13 ok, 0 failed
adaptercheck/forever  19 ok, 0 failed
adaptercheck/tbc      15 ok, 0 failed
corecheck/forever     10 ok, 0 failed
corecheck/tbc          8 ok, 0 failed
svcheck/forever        6 ok, 0 failed
svcheck/tbc            1 ok, 0 failed
consolecheck/forever  11 ok, 0 failed
consolecheck/tbc       1 ok, 0 failed
```

### 3. `python3 tools/apicheck.py`

`apicheck: 8 Forever TOCs, 20 files, 40 distinct globals, 0 findings (baseline 69893)` (19 -> 20:
`UI/Dashboard_Rows.lua` is now scanned, as the task names). `--selftest`: `selftest: 7 of 7 findings
as expected`. `diff SpellTuner.toc SpellTuner_Mainline.toc` -- one line, the marker
(`Client\TOC_Plain.lua` vs `Client\TOC_Mainline.lua`).

### 4. `luac -p`

Clean (`OK`) on every file touched: `UI/Dashboard_Rows.lua`, `UI/SpellTip_Forever.lua`,
`UI/Dashboard_Forever.lua`, `tools/tipcheck.lua`, `tools/spellsui.lua`. (The two `.toc` files are
plain text, not Lua; `luac` does not apply to them.)

### `git status --short`

```
 M SpellTuner.toc
 M SpellTuner_Mainline.toc
 M UI/Dashboard_Forever.lua
 M UI/Dashboard_Rows.lua
 M UI/SpellTip_Forever.lua
 M tools/tipcheck.lua
?? docs/tasks/T10-spells-pane.md
?? docs/tasks/T12-measure.md
?? tools/spellsui.lua
```
(`docs/tasks/T12-measure.md` predates this session and was not touched, per instructions -- only
this task file's own Report section was written.)

### Out of scope, untouched

The TBC dashboard (`UI/Dashboard.lua`, `UI/Dashboard_Simulate.lua`, `UI/Dashboard_Waste.lua`,
`UI/Dashboard_Review.lua`), `UI/Tooltip.lua`, `Engine/RankMath.lua`, an "Effective" mode.
`CLAUDE.md` and every `docs/` file except this Report. No commits made.

### Questions / nothing to stop on

No Fact turned out false. The task's own spec left a few formatting choices open (noted above under
"Design decisions"); none of them looked like a place to stop rather than make a documented,
reversible call.

## Review (lead, 2026-09-28)

Accepted. Reran: spellsui `11 ok`, tipcheck `13`, dashui `56` (the TBC table unchanged -- its
`opts == nil` path is the old code), modulecheck 12, bookcheck 14, clockcheck 13, parsecheck 10,
probecheck 66, every other suite at its count, apicheck 0 (20 files, `UI/Dashboard_Rows.lua` now
scanned and clean), TOCs marker-only. The export went through `tools/refcheck.py` from the suite
itself. Character name, realm, class and level come through `MD.API`; nothing indexes a client
table.

Two follow-ups, both small and neither blocking the M2 exit, carried to `docs/tasks/T10b-pane-polish.md`:
1. **The section titles are missing.** The Goal names a Heals, a Damage and an Other section; the
   rows come in that order but nothing on the pane says where one ends -- a Heals / Damage / Other
   title row is wanted before each non-empty section.
2. **An absorb's per-second line** reads `(over 1.5 sec)` in the tooltip: the new kind wording
   treats "no direct range" as over-time, and an absorb has neither. It should read `(1.5 sec GCD)`
   (or `sec cast` with a cast time).

Noted, not changed: `BuildSpellRows` re-runs `Book:Rows` on the cached book with the clock's pool,
so the tooltip's casts to OOM follow the modelled pool until the next rescan puts the default pool
back -- harmless (both are "from the pool we have") and gone when M3 gives Book the pool directly.
