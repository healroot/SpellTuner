# T10c — the Spellbook pane: one line per name, and only spells you spend mana on

Status: **done -- lead-accepted 2026-09-28** (see Review), after T7b (needs `entry.passive` and the stub's `passive` / no-return cost).
M2 close-out. Evidence: `docs/probe/1.60.1_70009-m2.md` §"Screenshot 1" (lines 24-32).

## Goal

The Spellbook pane reads cleanly on the real book: every family header, section title, note and
Other line sits on **one line** across the table (truncated by the client with "..." when too long,
the full text on hover), never wrapped inside the 56-pixel Rank column where it overprints the rows
below. The Other section lists only kindless spells you can cast for mana (Mark of the Wild,
Nature's Grasp, Teleport: Moonglade), not passives, racials without a cost, Attack or professions --
those are counted in one grey line that points at the Export, which still lists everything
(`tools/refcheck.py` reads it). For the author and any Forever user reading the pane.

## Facts

- **Screenshot 1** (m2 26-32): "The spell-name cells wrap onto three or four lines ('Healing /
  Touch / suggeste...', 'Entangling / Roots / suggeste...') and overprint the section titles
  (`Heals`, `Damage`) and the first rank row of each spell; the `Other` section ... is a stack of
  overprinted names. Rows themselves read correctly."
- **Why:** `UI/Dashboard_Forever.lua` `RenderSpellRow` writes the family header, section title,
  note and Other text into `row.cells.rank`, a font string `SetWidth(56)` by
  `UI/Dashboard_Rows.lua` `CreateTable` (`SPELL_COLS[1].w`), with word wrap on (the client's
  default); rows are 16 px apart, so a wrapped cell runs into the next rows.
- `UI/Dashboard_Rows.lua` is **shared** with the TBC dashboard; its TBC path (no `opts.render`) must
  not change (`dashui` 56). Only the generic path (`opts.render`, T10) is touched.
- The book at level 10 (m2 export 36-193): kindless families are Armor Proficiency, Attack,
  Cultivation, Dodge, Endurance, Languages, Mark of the Wild, Nature's Grasp, Plainsrunning,
  Teleport: Moonglade, War Stomp (Thorns too until T7b). `isPassive=true` on Armor Proficiency,
  Dodge, Endurance, Languages, Plainsrunning (m2 255-259); no cost returned for Attack, Cultivation,
  War Stomp and every passive (T7b: read as `costState == "free"`); a mana cost on Mark of the Wild
  (20/50), Nature's Grasp (50), Teleport: Moonglade (120). Professions are not read (T7b).
- The pane is a rank-comparison table (T10 Goal: "value, cost, cast, per mana, per second, casts to
  OOM, suggested rank"); a spell without a mana cost has nothing to compare there.
- In WoW a `FontString` with a width and `SetWordWrap(false)` draws one line and ends it with
  "..." when it does not fit (retail widget API; the stub records the call, T10c adds that).

## Files

| file | change | role |
|---|---|---|
| `UI/Dashboard_Rows.lua` | generic path only: each row also gets `row.cells.wide`, anchored LEFT at x 8, width `width - 60 - 12`; every generic-path cell (the columns and `wide`) gets `SetWordWrap(false)`. `Release` clears `wide` like the others. TBC path byte-identical in behaviour | shared table |
| `UI/Dashboard_Forever.lua` | `RenderSpellRow`: `section`, `family`, `note` and `other` rows write their text to `cells.wide` and leave every column cell empty; `entry` rows clear `wide`. `SpellRowEnter`: a `family` row shows a tooltip with the family name, `suggested: Rank K` (when there is one) and `ranks listed: N`; an `other` row shows the name, the rank text, mana and cast; entry rows unchanged. `BuildSpellRows`: a kindless family is listed only when its representative (`maxKnown` or `ranks[1]`) is not `passive` and has a mana cost (`cost.amount` or `cost.percent`); the rest are counted, and after the Other lines one `note` row reads `<n> passives and spells with no mana cost not listed - Export has them` (none when n is 0); the `Other` title appears when anything (a line or that note) follows it. `ExportText` unchanged | the pane |
| `tools/wowstub.lua` | a FontString records `SetWordWrap(v)` as `self.wordWrap` and answers `GetWordWrap()` (default true, the client's) | stub |
| `tools/spellsui.lua` | the fixture edits below; three new assertions | suite |

## Rules

- Rendered strings ASCII, no bare `|`; a spell name is a client string -- through the same `Esc`
  the export uses before it is rendered or put in a tooltip.
- No client call outside `Client/` (the pane reads `MD.Book`, `MD.SpellTip`, `MD.Clock` only).
- `UI/Dashboard_Rows.lua`'s TBC path unchanged; `dashui` must stay 56.
- No new global, no library. Comments say why.
- Tests first: the three new assertions written and failing before the change.
- **Existing assertions:** names unchanged. Allowed fixture/read edits only: (a) the `Bearform`
  fixture gains `cost = 30` (a shapeshift costs mana; without a cost it is now correctly left off,
  and assertions 1 and 12 are about where a listed Other line goes); (b) assertion 3 reads the family
  header from the `wide` cell instead of `rank`; (c) any helper that reads a family/section/note/other
  row's text reads `wide`. Anything else failing is a question, not an edit.
- **Git:** no `git add`, `stash`, `checkout -- <path>`, `reset`, commit. Do not edit `CLAUDE.md` or
  any `docs/` file except this Report.

## Acceptance

1. `bash tools/run.sh tools/spellsui.lua` ends `15 ok, 0 failed`. New names, verbatim:
   - "family, section, note and Other rows are one line across the table, never inside the Rank
     column" -- for every such row in `pane.lastRows`: its frame's `wide` cell holds the text, the
     `rank` cell is empty, and `wide.wordWrap == false`; every column cell of every row has
     `wordWrap == false`.
   - "passives and spells with no mana cost are left off the pane, counted, and kept in the export"
     -- fixtures `S.AddSpell(92200, "Oakskin", "Passive", fn, {noCost = true, passive = true})` and
     `S.AddSpell(92201, "Swing", "", fn, {noCost = true})` (descriptions with no amount): neither name
     appears in any row's text; a note row reads exactly
     `2 passives and spells with no mana cost not listed - Export has them`; the export contains
     `name: Oakskin` and `name: Swing`.
   - "hovering a family or an Other row shows its full name" -- the family row of `Healing Touch`
     and the Other row of `Bearform`, each `OnEnter`: `GameTooltip`'s lines include the full name.
2. `bash tools/run.sh tools/dashui.lua` ends `56 ok, 0 failed` (the TBC table untouched).
3. Every other suite at its count after T7b (parsecheck 11, bookcheck 15; tipcheck 14, clockcheck
   13 or 15 if T11b has landed, measurecheck 9 or 18 if T12b has, the TBC sixteen, the four
   two-flavour suites).
4. `python3 tools/apicheck.py` 0 findings, `--selftest` 7 of 7; `python3 tools/refcheck.py --selftest` ok.
5. `luac -p` clean on every file touched.
6. Paste into the Report: the failing run; spellsui and dashui in full; every other tail; apicheck;
   luac; `git status --short`; and the rendered rows of the fixture pane (kind + wide/rank text), one
   per line, as the Report's picture of the layout.

## Out of scope

- The Book, the parser, the tooltip block, the clock; the column set and widths; the export's
  content; the TBC dashboard.
- `CLAUDE.md`, every `docs/` file except this Report. Commits.

## Report

Implemented as specified.

**`UI/Dashboard_Rows.lua`** (generic path only, `opts and opts.render`): `AcquireRow` now gives
every column cell `SetWordWrap(false)` and creates `row.cells.wide` (`SetPoint("LEFT", row,
"LEFT", 8, 0)`, `SetWidth(width - 60 - 12)`, `SetJustifyH("LEFT")`, `SetWordWrap(false)`) when
building a fresh generic-path row. `api:Release` now also does `row.cells.wide:SetText("")` when
the row has one. The TBC path (`opts == nil`) takes none of this — `dashui` still passes at 56.

**`UI/Dashboard_Forever.lua`**: `RenderSpellRow`'s `section`/`family`/`note`/`other` branches now
write to `row.cells.wide` instead of `row.cells.rank` (still preceded by `ClearCells`, which
blanks every `SPELL_COLS` cell including `rank`); the `entry` branch now clears `row.cells.wide`
first. `SpellRowEnter` gained two new branches ahead of the existing `entry` one: a `family` row
opens a tooltip with the family's (escaped) name, `suggested: Rank K` when there is one, and
`ranks listed: N`; an `other` row opens one with its representative's (escaped) name, rank text,
mana and cast. Pulled the shared `OpenSpellTooltip(row)` (SetOwner/SetPoint) out of the old inline
code so all three branches use it. `BuildSpellRows` now splits kindless families into
`listedOther` (representative not `passive` and has `cost.amount` or `cost.percent`) and a
`skippedOther` count; only `listedOther` gets an `"other"` row (now carrying `family = fam` so
the tooltip can read it), and after them, if `skippedOther > 0`, one `note` row reads exactly
`"<n> passives and spells with no mana cost not listed - Export has them"`. The `Other` section
title now appears when `#listedOther > 0 or skippedOther > 0`. `ExportText` untouched. Moved the
`Esc` helper (duplicated from `Client/Probe.lua`'s escaping, as it already was for the export)
above `RenderSpellRow`/`SpellRowEnter` so both can use it on a family/Other name before it is
rendered or put in a tooltip (Rules: "a spell name is a client string... through the same Esc");
applied it to the family header text, the Other line's name, and the two new tooltip names.

**`tools/wowstub.lua`**: added `FrameMT:SetWordWrap(v)` (stores `self.wordWrap`) and
`FrameMT:GetWordWrap()` (defaults to `true` when never set). Nothing else touched; re-read the
file immediately before editing (T13b's concurrent `S.roles`/`UnitGUID` additions are untouched
by this edit and vice versa).

**`tools/spellsui.lua`**: Bearform's fixture gained `cost = 30` (was `noCost = true`) so it still
lists as an `other` row under the new "needs a mana cost" rule (assertions 1 and 12 rely on it
being listed). Added two fixtures per the task: `92200 Oakskin` (`noCost = true, passive = true`)
and `92201 Swing` (`noCost = true`, description with no amount). Assertion 3 now reads the family
header via `CellText(headerRow, "wide")` instead of `"rank"`. Added the three new assertions
verbatim-named:
- "family, section, note and Other rows are one line across the table, never inside the Rank
  column" — for every `section`/`family`/`note`/`other` row: `wide` cell non-empty, `rank` cell
  empty, `wide.wordWrap == false`; every `SPELL_COLS` column cell of every row has
  `wordWrap == false`.
- "passives and spells with no mana cost are left off the pane, counted, and kept in the export"
  — neither `Oakskin` nor `Swing` appears in any row's text, the note row reads exactly
  `"2 passives and spells with no mana cost not listed - Export has them"`, and the export
  contains both `name: Oakskin` and `name: Swing`.
- "hovering a family or an Other row shows its full name" — `Healing Touch`'s family row and
  `Bearform`'s Other row, each `OnEnter`, put a `GameTooltip` line containing the full name.

No other file touched.

### Tests-first

Wrote the three new assertions and the fixture/assertion-3 edits before touching
`UI/Dashboard_Rows.lua` / `UI/Dashboard_Forever.lua`; ran `tools/run.sh tools/spellsui.lua` and
confirmed the new three failed (family/Other text still landing in `rank`, no `wide` cell, no
`wordWrap`, no filtering of Oakskin/Swing) before making the production change, then re-ran to
green.

### Suite output

`bash tools/run.sh tools/spellsui.lua` — full output:

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
family, section, note and Other rows are one line across the table, never inside the Rank column ok - checked=12
passives and spells with no mana cost are left off the pane, counted, and kept in the export ok - sawOakskin=false sawSwing=false note="2 passives and spells with no mana cost not listed - Export has them" exportHasBoth=true
hovering a family or an Other row shows its full name                    ok - familyRow=true otherRow=true famOk=true otherOk=true

15 ok, 0 failed
```

`bash tools/run.sh tools/dashui.lua`: `56 ok, 0 failed` (tail: "no bare pipe in any painted
string    ok").

Every other suite at its expected count:

```
simcheck      |cff9966ffSpellTuner:|r   measured mean 1.3%  max 2.8% at 23.0s   (+ 23.1 mana/s energize) -> PASS
reccheck      54 ok, 0 failed
replaycheck   80 ok, 0 failed
replayui      98 ok, 0 failed
runcheck      78 ok, 0 failed
reviewui      44 ok, 0 failed
navui         25 ok, 0 failed
dashui        56 ok, 0 failed
regencheck    27 ok, 0 failed
simwindow     8 ok, 0 failed
solvercheck   70 ok, 0 failed
timeline      27 ok, 0 failed
spelltip      48 ok, 0 failed
practice      74 ok, 0 failed
practiceui    49 ok, 0 failed
migrate       7 ok, 0 failed
probecheck    70 ok, 0 failed
forevercheck  13 ok, 0 failed
modulecheck   12 ok, 0 failed
parsecheck    11 ok, 0 failed
bookcheck     15 ok, 0 failed
tipcheck      14 ok, 0 failed
clockcheck    15 ok, 0 failed
spellsui      15 ok, 0 failed
measurecheck  9 ok, 0 failed
adaptercheck/forever     19 ok, 0 failed
adaptercheck/tbc         15 ok, 0 failed
corecheck/forever        10 ok, 0 failed
corecheck/tbc            8 ok, 0 failed
svcheck/forever          6 ok, 0 failed
svcheck/tbc              1 ok, 0 failed
consolecheck/forever     11 ok, 0 failed
consolecheck/tbc         1 ok, 0 failed
```

(the sixteen TBC suites are `simcheck reccheck replaycheck replayui runcheck reviewui navui
dashui regencheck simwindow solvercheck timeline spelltip practice practiceui migrate`, all
present above and unchanged; `clockcheck` is 15 since T11b landed; `measurecheck` is 9, T12b not
yet landed in this tree.)

`python3 tools/apicheck.py`: `apicheck: 8 Forever TOCs, 21 files, 40 distinct globals, 0 findings
(baseline 69893)`. `python3 tools/apicheck.py --selftest`: `selftest: 7 of 7 findings as
expected`. `python3 tools/refcheck.py --selftest`: `selftest: ok`.

`luac -p` (Lua 5.1.5 built by `tools/run.sh`) on every file touched: `UI/Dashboard_Rows.lua`,
`UI/Dashboard_Forever.lua`, `tools/wowstub.lua`, `tools/spellsui.lua` — all clean, no output
besides the file names.

`git status --short` at the end of this task (`Client/Probe.lua` and `tools/probecheck.lua` are
T13b's concurrent, untouched-by-me changes; the `docs/tasks/T1*` files are other agents'/the
lead's untracked task files, also untouched by me):

```
 M Client/Probe.lua
 M UI/Dashboard_Forever.lua
 M UI/Dashboard_Rows.lua
 M tools/probecheck.lua
 M tools/spellsui.lua
 M tools/wowstub.lua
?? docs/tasks/T10c-pane-layout.md
?? docs/tasks/T12b-measure-attribution.md
?? docs/tasks/T13-recorder-v3.md
?? docs/tasks/T13a-secret-arg-check.md
?? docs/tasks/T13b-probe-m3-items.md
?? docs/tasks/T13c-module-plumbing.md
?? docs/tasks/T13d-scenario-v3.md
?? docs/tasks/T14-gates-v3.md
?? docs/tasks/T15-kit-from-book.md
```

### The fixture pane's rendered rows (kind + wide/rank text), one per line

From `pane.lastRows` after `MD:SelectView("spells", "book")` on this suite's fixture book, dumped
with a standalone script built on the same fixtures (`kind` + `wide`-cell text for
section/family/note/other, `rankText` for `entry` since it has no `wide` text):

```
section  Heals
family   BigSpell
entry    Rank 1
family   GapFamily
note     Rank 1 not listed (untrained, or hidden - show all ranks)
entry    Rank 2
family   Healing Touch
note     Rank 2 not listed (untrained, or hidden - show all ranks)
entry    Rank 1
entry    Rank 3
family   Rejuvenation
entry    Rank 1
entry    Rank 2
section  Damage
family   Wrath
entry    Rank 1
section  Other
other    Bearform  Passive  30  inst
note     2 passives and spells with no mana cost not listed - Export has them
```

(Oakskin and Swing are counted in that note line and never listed; both appear in the Export's
`== spells` block as `name: Oakskin` / `name: Swing`.)

### Skipped / questions

Nothing skipped; no open questions. One judgment call beyond the letter of the Files table: I
applied `Esc` to the family header text and the Other line's name (not just the two new tooltip
lines), since the Rules section states this as a general rule ("a spell name is a client string
-- through the same Esc the export uses before it is rendered or put in a tooltip") and I was
already touching those lines; it is a no-op for every ASCII fixture name here so no assertion's
expected text changed.

## Review (lead, 2026-09-28)

Read the diff whole; reran spellsui `15 ok`, dashui `56 ok` (the TBC table untouched: every T10c
line in `UI/Dashboard_Rows.lua` is behind `opts and opts.render`), tipcheck 14. Family, section, note
and Other text sit in the one-line `wide` cell; the Other section lists only castable spells with a
mana cost and counts the rest in one note; the export is unchanged. Nit, not re-issued: an Other
row's `rankText` (a client string) is rendered unescaped beside the escaped name -- ASCII in every
text seen so far (m2 export), and `Esc` would only double a pipe the client never puts there.
Accepted.
