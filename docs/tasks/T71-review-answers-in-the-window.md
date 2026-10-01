# T71 -- Review answers in the window (plan P27)

Status: **built** 2026-10-01 on branch `plan/P27` (base `cf9c6ae`), wave 11 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator. The committed tree is green without its TOC lines
(`tools/reviewforever.lua` loads `UI/ContextMenu.lua` itself when the TOC the harness read does not list
it). **In game the row menu exists only once the TOC lines below are in**: without them the pane has no
right-click menu and no other change.

## The task (docs/PLAN-refactor-ux.md section 5, P27)

Review items (`docs/review/2026-09-30-project-review.md`): **U20** (the window's buttons answer in
chat), **U22** (playing a fight takes four clicks; `Coach*` and shift-click are hidden conventions),
**U25** (Forever's lists are cut off without saying so), **U17** (Review's list in the old table look),
**A17** (`SP.CardLines`), **A31** (`g.short` on the gates).

- `SP.CardLines(...)` returns structured lines (`{ text, tone }`); `SP.Card` joins them into exactly
  today's chat text. Gates carry a `short` verdict so the pane stops parsing prose.
- **Under `UI.THEMED` only:** Review's list on `CreateTable` with T30's options and scrolling (the
  table gains scrolling and a double-click callback in `UI/Dashboard_Rows.lua`, off unless asked for);
  a **result area** under the list with the last card or validation as lines, and the coach's
  progress; chat keeps one line; a double-click plays; a right-click row menu (Play, Coach, Coach
  anyway, Validate, Pin, Export) from new `UI/ContextMenu.lua`.
- The author ruled on U22 (section 8.1 item 5): **the row menu's "Coach anyway"; the `Coach*` star and
  shift-click go.** Done under `UI.THEMED`; TBC keeps both until wave C (it is not themed yet).
- Mockup M2 (`docs/mockups/refactor-ux.html`, approved, section 7.1).
- Tests: `reviewforever` +5; `reviewui` equal counts, the chat card byte-identical; `coachforever`;
  `gatecheck` +1 (every gate has a `short`); `dashui` equal.

Owned files (section 4, wave 11): `UI/Dashboard_Review.lua`, `Engine/SimPlanner.lua`,
`Engine/SimModel.lua`, `Replay/Gates_Forever.lua`, `UI/Dashboard_Rows.lua`, new `UI/ContextMenu.lua`,
`tools/reviewforever.lua`, `tools/reviewui.lua`, `tools/coachforever.lua`, `tools/gatecheck.lua`. All
edited and committed except `tools/reviewui.lua`, which needed no change (its 49 assertions pass
unchanged and its output is byte-identical), plus this task file.

## What was built

| file | change |
|---|---|
| `Engine/SimPlanner.lua` | **`SP.CardLines(rec, best, bestResult, replayResult, baselineResults, cls, validation, opts)`** -- the old `SP.Card` body, each line now `{ text, tone }`: `head` (the first line), `text`, `good` (headroom, one fewer drink, the progress line), `bad` (NOT causal, an incomplete breakdown), `note` (caveats; plain in chat), `muted` (the three lines chat has always shown grey: the `/md coach N safe / ...` hint and the two "why" reasons). The list also carries `used = { you, best }`. **`SP.CardText(lines)`** joins: a `muted` line's grey goes around what follows its indent (`lead .. "|cff888888" .. rest .. "|r"`, exactly the old literals). **`SP.Card(...)` = `SP.CardText(SP.CardLines(...))`**. `SP.Coach` builds the card from the lines (the progress line appended as `good`) and returns them as a **fifth value**. `SP.CoachAsync`: `opts.noChat` skips the "coach: searching" chat line, `opts.onProgress(evals, max, bestScore)` is called from the search's progress hook, and `onDone(lines, validation, cardLines)` gets the structured lines (the `search: N plans evaluated` line included, as `note`). |
| `Engine/SimModel.lua` | `SM.NewValidation`'s `Gate(name, ok, text, value, limit, why, short)` -- a seventh argument stored as `g.short` (the name when a caller passes none). Every v2 gate and shared gate passes one: `mana 1.2% off`, `mana 3.9% off at worst`, `no mana samples`, `health` / `health, N reproduced`, `nobody died` / `N death(s)`, `foreign healing N%`, `model N% off` / `not yet calibrated` / `calibrated`, `spend N% accounted for`. No `text` changed. |
| `Replay/Gates_Forever.lua` | The v3 gates pass their `short`: health as v2, `foreign healing N%`, `model N% off the meter`, `heals N% off the meter`, and `no meter reading` (one local) for the three meter gates without a reading. |
| `UI/Dashboard_Rows.lua` | The generic table's new options, each off unless asked for: **`opts.scroll`** -- a window of `visible` rows (`api:SetVisibleRows(n)`, else what the frame's height holds), the mouse wheel moves it (`opts.scrollStep`, 3 rows a notch), a 4-px track and a draggable accent thumb at `rowWidth + 4`, `api:ScrollTo / ScrollBy / Reveal / Offset / Visible`; a row's `index` is its place in the whole list (the zebra does not swap on a scroll). **`opts.onDoubleClick(row, r, button)`** -- a second LeftButton click on the same entry (`r.id`, else `r`) within 0.4 s (`GetTime`); `onClick` still runs for both clicks, first, and the entry is read before it (a click that re-renders hands the pooled row another entry). **`opts.noHeader`**. With none of them set the table is byte-for-byte what it was (`dashui` 64, `spellsui` 48, outputs identical). |
| `UI/ContextMenu.lua` (new, both main TOCs) | `UI.CreateContextMenu(parent, width)` -> `menu:Open(anchor, title, items)` / `menu:Close()`: the dropdown list's look (the `header` fill through `UI.StylizeFrame`, 18-px `accent-hover` rows, `UI.LIST_STRATA` or DIALOG), a muted title line, each item `{ text, note, disabled, onClick, tooltip }` with the note right-aligned in the row, a disabled item in the `disabled` tone; opens at the pointer (`GetCursorPosition`, toolkit), else under `anchor`; tells `UI.OnPopup` when it shows and hides, so ESC closes the menu first. A click hides the menu, then runs the item. No client data, no flavour branch. |
| `UI/Dashboard_Review.lua` | TBC's path is untouched (every new branch is `if THEMED`; `reviewui`'s output byte-identical). **Under `UI.THEMED`:** the list is `CreateTable` with T30's options (`FONT_NUM_SMALL` numbers, 20-px rows, a 22-px header with its rule, zebra, `marker = "bar"` for the selected row) and `scroll`; the columns of M2 -- `#`, `When` (`At` on a run), `Zone`, `Length`, `Targets`, `Casts`, `Spent`, `Low mana`, `Result` -- right-aligned numbers, the cell keys unchanged. **Result** reads the gates' own `short`: `replays` (good), `does not replay: <short>` (bad), `not checked`, `short - under the recording gate, not coached` (muted), `- coached[: N less mana]` when the pane coached it, `- pinned`; a failing row's other cells in `text2`. No tail line (it scrolls). A **RESULT area** under the list (a muted `RESULT` title with what it is about, a rule, a header-less scrolled table): **Validate** shows the verdict, one row per gate (name, `ok` / `FAIL`, its text), energize, exclusions, each failing gate's provenance, and what to do next; **Coach** shows `coaching... N of 300 plans` / `best so far: N mana used (and owed)` while it searches, then the card from `SP.CardLines` (tones mapped onto tokens; long lines cut at word boundaries into rows); a plain Coach on a fight that does not replay shows its validation and "Right-click the row -> Coach anyway ..." and searches nothing; **Coach run** shows `SP.CoachRun`'s card. **Chat gets one line** each time (`fight 2 validated - does not replay (foreign healing). The details are in Review.`, `fight 2 coached - used: you X, best Y. The card is in Review.`, the refusal, `run X coached ...`). A **double-click plays** the row; a **right-click** selects it and opens the menu: Play (`double-click`), Validate, Coach / Coach pull (greyed with `does not replay`, `short` or `Druid only`), **Coach anyway** (forces: `SP.forced` set, the replay draws both columns marked FORCED), Pin / Unpin (the run's on a run), Export where `MD.RunExport` exists. **No `Coach*` star, no shift-click** on Coach, Coach pull or Play; the tooltips name the row menu instead. The pane coaches through `SP.CoachAsync` itself (not `MD:RunCoach`, which prints the card), with `RunCoach`'s rules: an auto-coach from the replay gives way, a second search is refused. The row hover anchors at the cursor and ends with "Double-click: Play. Right-click: ...". A hint by Start run: "Double-click a row to play it. Right-click for the rest." The list and the result area share the pane's height (the result gets 42 %, at least 120 px) and re-lay on `OnSizeChanged`; the menu closes when the pane hides. |
| `tools/reviewforever.lua` | See Tests. |
| `tools/gatecheck.lua` | +1, see Tests. |
| `tools/coachforever.lua` | +1, see Tests. |

The card was captured before the first edit and after, by a scratch script (not committed) that coaches
the TBC scripted pull (`tools/fakepull.lua`: `SP.Coach` plain and forced, `SP.CoachAsync` with the
search) and both Forever fixture recordings (the same three, plus every gate's text): **92 TBC lines and
143 Forever lines, byte-identical** (`cmp`).

## Tests first

On the parent (`cf9c6ae`) with the new suites (the new `UI/ContextMenu.lua` kept so the pane loads):

```
tools/run.sh tools/reviewforever.lua                       (exit 1)
B24: the selected, never validated row paints its verdict on the first render     FAIL - row1=ok
each recording is a row with its validate result         FAIL - row1=ok row2=foreign healing: no damage meter reading after the fight
T71: Validate shows the report in the result area, and chat gets one line          FAIL - gate rows=0 foreign FAIL=false verdict=false chat=11/14 SpellTuner: recording 2: Blood Furnace, 30s, 4 casts, 110 mana
lua: tools/reviewforever.lua:389: expected a clickable Coach with no star, got nil
```

(The parent's Validate printed 11 and 14 chat lines -- U20.) Without the new file the suite stops at
`load UI/ContextMenu.lua: cannot open`.

```
tools/run.sh tools/gatecheck.lua                           (exit 1)
T71: every gate, v3 and v2, carries a short verdict (ASCII, no pipe, not its name)  FAIL - v3 clean / mana mean: short=nil

tools/run.sh tools/coachforever.lua                        (exit 1)
lua: tools/coachforever.lua:656: attempt to call field '?' (a nil value)            (SP.CardText)
```

On the branch: `reviewforever` 18 ok, `gatecheck` 12 ok, `coachforever` 22 ok.

**`reviewforever` (13 -> 18).** Five new checks: the result area shows the validation after Validate,
a row per gate with `FAIL` on foreign healing, and chat gets one line; the row menu lists Play,
Validate, Coach (disabled, `does not replay`), Coach anyway, Pin, and Coach anyway forces (the plan made,
`SP.forced` set, the card in the result area, one chat line); the card lines join into the chat card
byte for byte (`SP.Coach`'s fifth return through `SP.CardText`) and the result area's first line is the
card's head; a double-click opens the replay (a single click does not); 36 fights scroll -- the wheel
reaches row 36 in 10 notches, 9 rows at a time, back to row 1, and no tail line. Re-pointed to the
themed pane (the author's ruling, section 8.1 item 5, and the table's rows): B24 and check 4 read
`replays` / `does not replay: no meter reading` where they read `ok` / `foreign healing: no damage meter
reading ...` (the prose parse A31 removes); check 6 is now "Coach refuses the failing fight in the result
area with one chat line, shift or not" (it was "... and shift-click coaches it anyway"; forcing is the
new menu check); the ASCII scan walks the whole pane, so the result area, the menu and the tooltip are
scanned too; `SelectRow` clicks through the table row's `OnMouseUp` and moves the stub's clock a second
first (two selections are never one double-click).

**`gatecheck` (11 -> 12).** Every gate on both roads has a `short` that is a string, not the gate's
name, at most 32 characters, ASCII, with no pipe: the v3 fixture clean, with no meter reading, with a
death; the v2 road on the author's practice fight (`tools/data/practice/1790701698.lua`) and on a v2
stream with no mana samples -- 37 gates.

**`coachforever` (21 -> 22).** The pane's coach: `SP.CoachAsync` with `noChat` prints nothing,
`onProgress` is called with the maximum (300) and a count, and the structured lines it hands onDone
join into exactly the chat lines beside them, ending with `  search: N plans evaluated`.

**Mutations** (each alone, then restored):

- `SP.CardText` never colouring a `muted` line: the card check's first version **survived** (it
  compared `SP.CardText(lines)` with `SP.Card`, which is the same function); the check now also reads
  the chat card's own shape -- every `muted` line `^%s*|cff888888.-|r$`, no colour code on any other --
  and fails (`same=false`, 17 ok, 1 failed).
- `Gate` storing no `short`: `gatecheck` 11 ok, 1 failed (`v3 clean / mana mean: short=nil`), and
  `reviewforever`'s check 4 reads `does not replay: failed`.
- `DOUBLE_CLICK = -1` in `Dashboard_Rows.lua` (the stub's two clicks share a moment, so 0 would still
  count): the double-click check fails (`opened=`).
- The table's `Clamp(#rows)` removed: the wheel past the end raises in the table's render
  (`attempt to index local 'r'`), `reviewforever` exits 1.
- `noChat` ignored: `coachforever` 21 ok, 1 failed (`chat=1`).

## Suites (`make check` = `tools/check.sh`, exit codes and footers checked)

Before: `cf9c6ae`, 68 runs, all passed (63 counted). After: this branch, with and without the TOC lines
in the working tree: 68 runs, all passed (63 counted).

| suite | before | after |
|---|---|---|
| `reviewforever/forever` | 13 | **18** |
| `coachforever/forever` | 21 | **22** |
| `gatecheck/forever` | 11 | **12** |
| `reviewui/tbc` / `dashui/tbc` / `navui/tbc` / `replayui/tbc` / `replaycheck/tbc` / `simcheck/tbc` / `restcheck/tbc` / `solvercheck/tbc` / `verifycheck/tbc` | 49 / 64 / 35 / 103 / 82 / 13 / 51 / 84 / 14 | same |
| `spellsui/forever` / `replayforever/forever` / `scenariocheck/forever` / `practiceforever/forever` / `themecheck` | 48 / 15 / 14 / 28 / 28 + 7 | same |
| every other suite in `tools/data/expected-counts.json` | as expected | same |
| `apicheck` | 0 findings, 56 files | 0 findings, **57** files with the TOC lines (56 without) |
| `textcheck` | 0 findings, 92 files | 0 findings, **93** with the TOC lines |
| `releasecheck` (21) | tbc 62 files, forever 30 | with the TOC lines: tbc **63**, forever **31** |

**Outputs.** Every suite's saved output (`tools/.lua/check/*.out`) before and after, with table
addresses, frame counts, milliseconds and search evaluation counts normalised: identical except the
three suites above (their new and re-pointed lines), the file counts (`apicheck`, `textcheck`,
`releasecheck`, with the TOC lines) and `themecheck`'s count of token reads (59 -> 66: the new
`UI.Hex` / `UI.RGB` / `UI.Fill` reads, every one a known token), and `coachforever`'s
"asynchronous coach ... frames=2" (3 on one run: the search is frame-sliced on `debugprofilestop()`).
**Every TBC suite's output is byte-identical**, `reviewui`, `dashui` and `replayui` included.

`luac -p` on every changed file: clean.

## TBC

No change. Every new behaviour in `UI/Dashboard_Review.lua` is behind `UI.THEMED`, which is false on
TBC until wave C (C1); the TBC chat card is byte-identical (the capture above); the gates' `text` is
unchanged and `short` is a new field nothing on TBC reads; the table's new options are off unless
asked for; `UI/ContextMenu.lua` defines a constructor nobody calls on TBC. When C1 turns the theme on,
TBC gets this pane as it is (runs included: `At`, Coach run into the result area, Pin the run) -- C2
then re-baselines `reviewui`.

## Integrator lines

**`SpellTuner_Mainline.toc`** and **`SpellTuner.toc`** (identical) -- one line after
`UI\Windows_Forever.lua`, before `UI\Dashboard_Rows.lua`:

```
UI\Theme_Forever.lua
UI\Windows_Forever.lua
UI\ContextMenu.lua
UI\Dashboard_Rows.lua
```

**`SpellTuner_TBC.toc`** -- one line after `UI\Style.lua`:

```
UI\Style.lua
UI\ContextMenu.lua
UI\Tooltip.lua
```

**`tools/data/expected-counts.json`**: `"coachforever/forever": 22`, `"gatecheck/forever": 12`,
`"reviewforever/forever": 18`.

**`CLAUDE.md`**, rows:

- new row after `UI/Style.lua`'s: `| UI/ContextMenu.lua | **A right-click menu** (T71, P27, review U22;
  both main TOCs): UI.CreateContextMenu(parent, width) -> menu:Open(anchor, title, items) / Close() --
  the dropdown list's look (the header fill, 18-px rows, UI.LIST_STRATA), items { text, note, disabled,
  onClick, tooltip }, opened at the pointer, announced to UI.OnPopup so ESC closes it first. Review's
  row menu under UI.THEMED |`
- `UI/Dashboard_Review.lua`, append: `**T71 (P27):** under UI.THEMED the list is the generic table,
  scrolled, the Result cell from the gates' short; a RESULT area under it shows the last validation or
  coach card (SP.CardLines) and the coach's progress, chat gets one line; a double-click plays; a
  right-click opens the row menu (UI/ContextMenu.lua: Play, Validate, Coach, Coach anyway, Pin, Export);
  no Coach* star or shift-click there (section 8.1 item 5). TBC unchanged until wave C`
- `UI/Dashboard_Rows.lua`, append: `**T71 (P27):** opts.scroll (a window of rows, the wheel, a thin
  bar; api:SetVisibleRows / ScrollTo / ScrollBy / Reveal), opts.onDoubleClick, opts.noHeader -- off
  unless asked for`
- `Engine/SimPlanner.lua`, append: `**T71 (P27, review A17):** SP.CardLines -> { text, tone } lines
  (head / text / good / bad / note / muted, plus used = { you, best }), SP.CardText joins them, SP.Card =
  CardText(CardLines) (chat byte-identical); SP.Coach returns the lines fifth; SP.CoachAsync takes
  opts.noChat and opts.onProgress(evals, max, bestScore) and hands onDone the lines third`
- `Engine/SimModel.lua`, append: `**T71 (P27, review A31):** every gate carries short (SM.NewValidation's
  seventh argument), the few words a list cell shows`

**`docs/DECISIONS.md`** (Forever behaviour, the author's ruling): "Review on Forever: forcing is the
row menu's Coach anyway (T71, PLAN-refactor-ux 8.1 item 5). Under the theme the Coach* star and the
shift-click on Coach, Coach pull and Play are gone; a plain Coach on a fight that does not replay shows
why in the result area and searches nothing. The window's Validate and Coach answer in the result area
with one chat line; the slash commands still print in full. TBC keeps the star and the shift-click
until wave C turns the theme on there."

**`docs/TESTING.md`**: section 9 item 22 of the plan as written ("Validate a fight: the report appears
under the list, chat has one line. Double-click a row: it plays. Right-click: the menu. A 30+ pull run
scrolls.") -- on Forever, a long list is only reachable with more than 8 fights plus pins or 8 practice
fights; the run case is TBC's, after wave C. Add: "Right-click a fight that does not replay -> Coach
anyway: the card appears under the list and Play shows both columns, FORCED."

## Deviations

1. **The scroll is a window inside the table, not `UI.CreateScrollFrame`.** The plan says "a scroll
   frame"; the table shows `visible` rows from an offset, moved by the wheel and a draggable thumb. A
   `ScrollFrame` would put 36 pooled rows in a scroll child, and the stub has no
   `GetVerticalScroll` (it falls to the no-op fallback, so `VerticalScroll` raises on `nil + step`) --
   `tools/wowstub.lua` is not this task's file. The windowed table is also cheaper (only the visible
   rows exist) and is the same API for the result area.
2. **The star and the shift-click are gone under the theme** (P27's text says they "stay until the
   author rules"; the author ruled, section 8.1 item 5). TBC keeps both: its pane is not themed until C1.
3. **`SP.CoachAsync`'s option is `noChat`, not `quiet`.** `UI/ReplayWindow.lua`'s auto-coach has passed
   `quiet = true` since v0.13.9, which `CoachAsync` never read; honouring `quiet` would have removed the
   "coach: searching" line from TBC's auto-coach (seen in `replayui`'s output on a first try). Whether
   the replay's auto-coach should be quiet is P28's file and question.
4. **The Result cell's words** follow M2 where M2 has them (`replays`, `does not replay: health`,
   `not checked`, `- pinned`, `- coached: N less mana`) and the gates' own `short` elsewhere -- a fight
   with no meter reading reads `does not replay: no meter reading`, not `foreign healing`, because the
   short says what failed rather than which gate. `short - under the recording gate, not coached`
   replaces M2's `short - under 20 s, not coached` (the gate is 20 s **and** 5 casts).
5. **The run's coach card is shown as plain lines**: `SP.RunCard` is not structured (only the single
   fight's card is, A17's scope); its colour codes are stripped for the result area.
6. **Long result lines are cut into rows** at word boundaries (about 6 px a character); the rows are one
   height, so a wrapping font string would overprint the next row.
7. **`coachforever` +1** (the plan names the suite without a number): the seam the pane uses (`noChat`,
   `onProgress`, the third onDone argument) is held there, where the coach is.
8. **`tools/reviewui.lua` unchanged** (owned, not edited): it already passes 49 and its output is
   byte-identical; the TBC card's byte identity was checked by the capture above rather than by a new
   assertion, so its count stays equal as the plan asks.
9. The habits and progress lines stay at the pane's foot under the theme (M2 does not show them; nothing
   asked to remove them).
10. **Not done here:** installing the build into the beta and TBC clients (the user asked the session
    for that). This branch is not integrated; installing it alone would ship a Forever window without
    its TOC line for the menu. The integrator installs after the wave merges.
