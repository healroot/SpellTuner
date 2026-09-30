# T53 -- TBC lists say what they hide (plan P9)

Status: **built** 2026-09-30 on branch `plan/P9` (base `4702b5c`), wave 3 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator.

## The task (docs/PLAN-refactor-ux.md section 5, P9)

Review item U25 (`docs/review/2026-09-30-project-review.md`), the TBC half; the Forever list gets a
scroll frame in P27. Review and Waste stopped painting rows at the pane's height and said nothing, so
a 36-pull run showed about 30. Now, when rows are cut, the last visible slot becomes a grey
`... and N more (scroll: not yet)` line, and in Review the selected row is always kept visible. No
layout, font or colour change.

Owned files (section 4, wave 3): `UI/Dashboard_Review.lua`, `UI/Dashboard_Waste.lua`,
`tools/reviewui.lua`, `tools/dashui.lua`. No other file was touched.

## What was built

| file | change |
|---|---|
| `UI/Dashboard_Review.lua` | `ListWindow(n, top, floor, selected)` works out how many slots fit. It uses the loop's old `break` test unchanged (`y < -(pane:GetHeight() - 70)`), so the number of slots is exactly the number of rows painted before. If the list fits, nothing changes. If it does not, the last slot goes to the tail line, `hidden` is the number of rows not painted, and the window starts at the selected row when that row would fall off. At the end of the list the window backs up so the slots stay full. The row loop runs `first..last` instead of `ipairs` + `break`. The tail row uses the `when` cell at `width - 80` (as the empty-list row does), is grey (`888888`, the pane's existing muted colour) and ignores the mouse. `TailText(n)` holds the wording. |
| `UI/Dashboard_Waste.lua` | `ListFit(n, top, floor)`: the same slot count against Waste's own old test (`y < -(pane:GetHeight() - 40)`). A longer list paints `slots - 1` rows and then the tail line in the `label` cell at width 600 (as the empty-list row does). Every cell of the mode's columns is cleared first, because a pooled row keeps the last render's text. Waste has no selection. |

Edge cases, the same in both files. A pane with no slot at all (no height yet; the stub's default
height of 20) paints nothing, as before, so no suite that builds a pane without a size moves. With
one slot there is only the tail line.

All text is ASCII with no bare pipe, and the only escapes are `|cff888888 ... |r`.

**Both lines see it until P27.** Both files are shared (both main TOCs). The Forever Review list
therefore gets the same tail line until P27 gives it a scroll frame under `UI.THEMED`. The tail row
uses the pane's existing font (`SMALL`) and the grey its empty-list row already uses, so nothing
Forever-specific is added.

## Failing first

On the parent's two UI files (`git show 4702b5c:UI/Dashboard_Review.lua`, `..._Waste.lua` put in
place with the new suites, then restored):

```
reviewui (exit 1):
a 36-pull run ends with the tail line          FAIL - tail=nil rows=19 (1..19)
selecting pull 36 keeps it on screen           FAIL - tail=nil rows=19 (1..19)
46 ok, 2 failed

dashui (exit 1):
a long Waste list ends with the tail line        FAIL - rows=14 last=14 tail=nil
63 ok, 1 failed
```

With the change:

```
a 36-pull run ends with the tail line          ok - tail=18 rows=18 (1..18)
selecting pull 36 keeps it on screen           ok - tail=18 rows=18 (19..36)
48 ok, 0 failed

a long Waste list ends with the tail line        ok - rows=13 last=13 tail=27
64 ok, 0 failed
```

The parent's 19 and 14 rows are the slot counts the new code keeps (18 + tail, 13 + tail), which
shows the cut-off test did not move.

The tests:
- `reviewui` +2. The scripted run's pulls are replaced by 36 copies, and the pane is 760 x 420 (19
  slots). The list shows pulls 1-18 and `... and 18 more (scroll: not yet)`. Then the pane grows to
  1000 high (every pull fits), pull 36 is clicked, and the pane shrinks back to 420: pulls 19-36 are
  shown, 36 among them, and the tail line still says 18.
- `dashui` +1. A Waste pane 760 x 300 (14 slots) with `Overheal:SpellRows` answering 40 rows shows
  `Spell 1`..`Spell 13` and `... and 27 more (scroll: not yet)`.

## Suites (exit codes checked; the loop in docs/TOOLS.md section 1)

Before (base `4702b5c`) and after: every suite exits 0. Counts are equal except the two named
suites:

| suite | before | after |
|---|---|---|
| `reviewui` | 46 | **48** |
| `dashui` | 63 | **64** |
| every other suite in the loop (simcheck 13, reccheck 63, replaycheck 82, replayui 98, runcheck 81, navui 35, regencheck 27, simwindow 8, solvercheck 84, restcheck 51, timeline 27, spelltip 48, costcheck 3, practice 81, practiceui 50, migrate 7, probecheck 87, forevercheck 16, modulecheck 14, kitcheck 7, recordcheck 29, scenariocheck 14, gatecheck 9, replayforever 15, reviewforever 13, coachforever 20, practiceforever 25, bindscheck 6, parsecheck 15, bookcheck 21, tipcheck 37, clockcheck 23, spellsui 48, measurecheck 30, releasecheck 16, importcheck 20, themecheck 23, tabscheck 24, wincheck 53; adaptercheck 22/15, corecheck 10/8, svcheck 6/1, consolecheck 17/1) | equal | equal |
| `apicheck.py` | 0 findings, selftest 10/10 | same |
| `textcheck.py` | 0 findings, selftest 2/2 | same |
| `refcheck.py --selftest` | 2/2 | same |

I compared transcripts for `reviewui`, `dashui`, `practiceui`, `practiceforever`, `reviewforever`,
`wincheck`, `navui` and `replayui`, running the same suite files on the parent's UI files and on the
new ones. The only differences are the three new assertions and run-to-run noise: millisecond timings,
table addresses, and `replayui`'s frame-sliced `search N evaluations` lines, which also differ between
two runs of identical code. `luac -p` passes on both changed UI files.

## Integrator lines

**docs/TOOLS.md section 1** (append to each row's text):

- `reviewui.lua`: ` Since **T53** (48): a 36-pull run in a 420-high pane lists 18 pulls and "... and 18 more (scroll: not yet)"; pull 36, selected, stays on screen (U25)`
- `dashui.lua`: ` Since **T53** (64): a Waste list longer than the pane ends with "... and N more (scroll: not yet)" (U25)`

**tools/data/expected-counts.json** (when it exists): `reviewui` 48, `dashui` 64.

**CLAUDE.md**, append to the rows:

- `UI/Dashboard_Review.lua`: ` **T53** (review U25, 2026-09-30): a list longer than the pane ends with a grey `... and N more (scroll: not yet)` line instead of stopping silently, and the selected row is kept on screen (the list starts at it, backed up at the list's end); no scroll yet (P27 on Forever)`
- `UI/Dashboard_Waste.lua`: ` **T53** (review U25, 2026-09-30): a list longer than the pane ends with a grey `... and N more (scroll: not yet)` line`

**docs/TESTING.md section 44**, under **TBC.** (after item 8):

```
9. **Long lists (P9).** Open `/md` -> Reports -> Review on a run with more than 30 pulls: the list ends
   with `... and N more (scroll: not yet)`, and N plus the rows shown is the run's pull count.
```

**docs/DECISIONS.md**: nothing. The plan says it is not needed, because the old behaviour was a
silent truncation. **TOCs**: nothing (no new file).

## Deviations

- **The window backs up at the end of the list.** The plan says the list "starts at" the selected row
  when that row would fall off. That is what happens, except near the end of the list: there the
  window starts earlier so every slot is used. Selecting pull 36 of 36 shows 19-36, not pull 36 alone
  under 17 empty slots. The selected row is visible either way, and the tail's N always counts every
  row not shown, above or below.
- **Forever sees the tail line too until P27.** Both files are shared and the change is not gated on
  the theme. That matches the plan's "the Forever list gets a scroll frame in P27". The tail row adds
  no font, colour or layout of its own.
- **Not fixed here.** Waste's existing empty-list row keeps whatever text a pooled row had in its
  other cells. It is outside U25; the new tail row clears its cells.
