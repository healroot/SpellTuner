# T40 -- Practice under the theme and the window manager

Status: **built** 2026-09-30 on branch `ui/T40` (base 9a04b62), awaiting review.

## The row (docs/SPEC-forever-ui.md section 9)

| # | Task | Files | Tests | Needs |
|---|---|---|---|---|
| **T40** | **Practice under the theme and the manager**: the bindings sheet (`BW:Build(parent)` on Forever, its ESC entry, its footer line from T27), the panel's `UI.TEXT` colours (role rows 178, key labels 282), the sheet's (105, 165), the wrapping fields row, the `you` tag, the one-line bindings summary, the Simulate minimum lowered to 900. | `UI/BindingsWindow.lua`, `UI/PracticePanel.lua`, `UI/Windows_Forever.lua` (the Simulate minimum), `Modules/SpellTuner_Practice/Commands_Forever.lua` | `tools/practiceui.lua` 49 unchanged (tbc); `tools/practiceforever.lua` (+4: no `ffcc00` in the panel or the sheet; ESC closes the sheet and not the window; at 900 wide no fight field extends past the pane's right edge; the summary does not count a hidden binding) | T27, T31, T32, T33 |

Spec sections: 4.1 (gold leaves the practice panel and the bindings sheet; shared files read
`UI.TEXT` and keep their literals without it), 4.4 (the practice panel and the bindings sheet under
the theme), 6.1 rule 3 (editors are sheets), 6.2 (the bindings editor's row: pane +50, mask +30
over the whole pane, centred, 440x460, ESC closes the sheet, hides with its owner), 6.4 (sheets;
`/st binds` and "Edit bindings" open Simulate -> Practice with the sheet; `BW:Build(parent)`, TBC
keeps its window), 6.5 (one ESC entry), 6.6 (the bindings sheet refuses to open in combat), 6.7
(Simulate's minimum 900 x 560 once this lands), 7 (shared files gated on `UI.TEXT` / `MD.Win`),
8.1 decision 9 (a binding for a spell not in the book is neither listed nor counted).

## What was built

| file | change |
|---|---|
| `UI/PracticePanel.lua` (shared) | Everything below is gated on `UI.TEXT` (the Forever theme) or `MD.Win` (the manager); TBC builds every line as before. **Colours:** the role rows `every tank ...` in `text2` (were gold), the table header, the role cell, the intro's second sentence and the status line in `muted` (the same `|cff888888` literal on TBC), the first line of every tooltip the panel sets in the accent (the client draws an uncoloured first line gold; `Title(text)` returns the text unchanged on TBC). **`you`** is a small accent tag at the right of the name box (the box's right text inset widened for that row), and the Role cell holds the role alone -- no more `you healer` wrapping in 56 px. **The bindings summary:** the "What your presses cast" column right of the table goes; one line sits beside the group buttons, `6 bindings  [Edit bindings]` (`Nothing is bound` in orange when empty), its hover titled "What your presses cast" listing each binding (key in the accent, spell in `text`, `(not trained)` as before) and the hint. It counts `PR.Binds()`, which since T27 leaves out a binding for a spell not in the book, so a hidden binding is neither counted nor listed. **The fight fields wrap:** the six fields and "Same fight again" (with its seed box) flow left to right from x = 4 and start a new row, 24 px down, when the next one would pass the pane's right edge less 4; the table header moves down by the rows added, the intro and the status line take the pane's width, and the rows' scroll area takes the height left above Start (250 until the pane has one). `Layout` runs on every render and on the pane's `OnSizeChanged`. **Edit bindings** calls `MD:ShowBindings(pane)` under the manager. `MD.DashboardParts.PracticeHost()` answers the practice pane inside the main window (every pane built under the manager is registered, weak-keyed), which `/st binds` opens the sheet on. `api.summary` and `api.fightFrames` are exposed for the suite. |
| `UI/BindingsWindow.lua` (shared) | **The sheet.** `Build(onPane)` builds a sheet on the practice pane (`UI.CreateSheet(pane, pane, 440, 460, "PRACTICE BINDINGS")`: pane level +50, the mask over the whole pane at +30, centred) with a **Done** button in its title row, and every control inside the sheet's body (438 x 437, so the rows, list and footer size to it); without a pane it builds TBC's movable window and its `UISpecialFrames` entry exactly as before. `MD.BindingsWindow:Build(parent)` is the spec's `BW:Build(parent)`. `MD:ShowBindings(onPane)` under `MD.Win`: refused in combat with one chat line (6.6); opens the main window on Simulate -> Practice through `MD.Win:ShowMain` unless the pane is already on screen; builds the sheet once (on `onPane`, else `PracticeHost()`); shows it only if its pane is visible (a refused `ShowMain` -- T34's practice takeover -- opens nothing); and pushes it on the ESC stack, so one ESC closes the sheet and leaves the window. The pane's `OnHide` hides the sheet (hides with its owner: a view switch, the window closing, the combat hide), and the manager's `OnHide` hook takes its entry off. `MD:ToggleBindings` closes a shown sheet or opens it. **Colours:** `press a key or button...` in the accent and an import's notes in `text2` (both gold before), the hint's second sentence in `muted`, the tooltip titles in the accent -- all the old literals on TBC. The T27 footer (`1 binding kept for a spell you have not learned  [Forget]`) moves into the sheet unchanged. |
| `UI/Windows_Forever.lua` | `Win.SIZES.simulate` minimum 1036 x 600 -> **900 x 560** (the default stays 1036 x 646). |
| `Modules/SpellTuner_Practice/Commands_Forever.lua` | `/st binds` (and `/st bindings`) open Simulate -> Practice with the sheet (`MD:ShowBindings()`) under the manager; `ToggleBindings` without it. `/st practice` goes through `MD:SelectView` alone under the manager (it called `MD:ShowDashboard()` first, which shows the frame past `ShowMain`). |
| `tools/practiceforever.lua` | +4 (20 -> 24), below. `PanelBindText` (the helper T24 1 / T24 3 / T27 2 / T27 5 read) returns the summary line followed by its hover when the panel has a summary: those checks still assert the same things (nothing bound says Import and Edit bindings; Lifebloom absent; Rejuvenation present without the spellbook note; Regrowth back after learning) about the text the player now sees. |

No stub hunk and no shared-test hunk: the 900-wide check installs its own point recorder and a
text-length `GetStringWidth` (7 px a character, more than Friz at 11-13 px) on the frame metatable
for that check only and restores them. No new adapter binding (`MD.API.UnitAffectingCombat`,
`MD.API.After` were bound), no TOC change.

## Tests first

The four new assertions against the base's shipped files (the suite edited first):

```
T40: no ffcc00 in the panel, its bindings hover or the bindings sheet                           FAIL - panel: |cffffcc00every tank|r
T40: the bindings sheet is on Simulate -> Practice; ESC closes it and not the window            FAIL - shown=true view=simulate/practice onTop=false gone=false main=false special=true proxy=false
T40: at 900 wide no fight field extends past the pane's right edge                              FAIL - window=1036x600 items=0 unresolved=nil rightmost=-inf pane=776
T40: the one-line bindings summary does not count a hidden binding                              FAIL - summary= hover=
20 ok, 4 failed
```

(On the base, one ESC closed the main window -- the stack's only entry -- and the bindings window
went through its own `UISpecialFrames` entry; the Simulate group could not go under 1036.)

After: `24 ok, 0 failed`:

```
T40: no ffcc00 in the panel, its bindings hover or the bindings sheet                           ok
T40: the bindings sheet is on Simulate -> Practice; ESC closes it and not the window            ok - shown=true view=simulate/practice onTop=true gone=true main=true special=false proxy=true
T40: at 900 wide no fight field extends past the pane's right edge                              ok - window=900x560 items=15 unresolved=nil rightmost=755 pane=776
T40: the one-line bindings summary does not count a hidden binding                              ok - summary=1 binding
```

## The full check

The suite loop of `docs/TOOLS.md` section 1 plus `themecheck`, `wincheck` and `tabscheck`, run on
this branch and on an export of the base (9a04b62):

- **Counts:** practiceforever 20 -> 24. Every other count identical: simcheck PASS, reccheck 54,
  replaycheck 80, replayui 98, runcheck 78, reviewui 44, navui 35, dashui 63, regencheck 27,
  simwindow 8, solvercheck 77, timeline 27, spelltip 48, practice 74, **practiceui 49**, migrate 7,
  probecheck 87, forevercheck 13, modulecheck 14, kitcheck 7, recordcheck 24, scenariocheck 12,
  gatecheck 9, replayforever 14, reviewforever 11, coachforever 18, bindscheck 6, parsecheck 12,
  bookcheck 17, tipcheck 37, clockcheck 20, spellsui 35, measurecheck 30, releasecheck 13,
  themecheck 23, wincheck 39, tabscheck 24, adaptercheck 22 / 15, corecheck 10 / 8, svcheck 6 / 1,
  consolecheck 17 / 1. (releasecheck needs a git checkout, so on the base export it could not run;
  on this branch it is 13.)
- **TBC output:** the sixteen TBC suites' whole output diffed against the base: identical except
  run-dependent lines (reccheck's and replayui's millisecond timings, replayui's frame-sliced search
  count printed in a different order, solvercheck's table addresses). practiceui and dashui, the
  two that build the shared practice panel and bindings window, are byte-identical.
- `python3 tools/apicheck.py`: 0 findings (8 Forever TOCs, 48 files); `--selftest` 10 of 10;
  `python3 tools/refcheck.py --selftest` ok.
- `luac -p` (tools/.lua/lua-5.1.5/src/luac): `UI/BindingsWindow.lua`, `UI/PracticePanel.lua`,
  `UI/Windows_Forever.lua`, `Modules/SpellTuner_Practice/Commands_Forever.lua`,
  `tools/practiceforever.lua`.

## Deviations

- **The spec's line numbers** (PracticePanel 178 / 282, BindingsWindow 105 / 165) predate T27; the
  gold on the base was at PracticePanel 178 (role rows) and 282 (key labels) and BindingsWindow 111
  (`press a key...`) and 196 (the import's notes). All four are themed.
- **Where the summary sits.** 4.4 gives the line, not its place. At 900 the old column right of
  the table has 162 px left, too narrow for the line and its 110-px button, so the line sits beside
  the group buttons (x of about 370), where it has room at every width the group allows.
- **Tooltip titles in the accent** (the panel's and the sheet's): not in the row, but 4.1 says gold
  leaves every SpellTuner window and tooltip on Forever, and an uncoloured first tooltip line is
  gold in the client. TBC keeps its uncoloured titles.
- **A Done button** in the sheet's title row: the kit's sheet has no close control of its own and
  the row names none; the picker has Done too. ESC and the pane hiding also close it.
- **The sheet hides with its pane** (a view switch, the main window closing or its combat hide),
  and is not reshown when the window comes back after combat -- 6.2's "hides with its owner",
  read as closing it, so no stale stack entry can outlive it.
- **The existing checks' helper** `PanelBindText` reads the summary and its hover (see above); no
  assertion was dropped or loosened.
- **`/st practice`** under the manager no longer calls `MD:ShowDashboard()` before `MD:SelectView`
  (the manager's door opens the window itself; `ShowDashboard` would show it past T34's refusal).

## In game (docs/SPEC-forever-ui.md section 10, item 1 and 3)

Simulate -> Practice: no gold (the role rows grey, the key labels in the summary's hover in the
class colour), `you` a small tag at the right of your name, one line `N bindings  [Edit bindings]`
beside the group buttons with the list on hover. Drag the window's corner narrower: it stops at 900,
the fight fields move onto a second row and nothing runs off the right. Edit bindings (or `/st
binds`): the bindings sheet opens over the pane, the pane greyed behind it; press ESC once: the
sheet closes and the window stays. In combat `/st binds` says the sheet does not open in combat.
