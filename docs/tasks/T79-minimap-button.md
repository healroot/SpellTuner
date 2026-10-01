# T79 -- The minimap button on Forever (plan P36)

Status: **built** 2026-10-01 on branch `plan/P36` (base `7fd71b3`), wave 17 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator. **The branch needs its TOC lines (below)**:
`UI/MinimapButton.lua` must go on the two Forever main TOCs, which are integrator-owned. Without the
lines two runs fail on the committed tree (`minimapcheck/forever` check 1, "from the main TOC", and
`defaultscheck/forever`, whose scan finds `MD.db.minimap` read by `UI/Dashboard_Forever.lua` with no
default because the file that registers it is not loaded). The TOCs were not edited in the worktree.
Every suite was run in a scratch copy of the worktree with the lines below applied (and the import
fixture rebuilt, below). The failing-first runs used the parent `7fd71b3`, extracted with
`git archive`, with the new stub and suite copied in.

## The task (docs/PLAN-refactor-ux.md section 5, P36)

Section 8.1 item 10, the author's answer: **"Minimap button on Forever: yes"**. The same button on
both lines: left-click opens the window on the last view, right-click opens Settings, drag moves it
round the minimap, and a setting hides it. Mockups `docs/mockups/refactor-ux.html` **M1** (the
WINDOWS pane gains *Minimap button* with "Left-click opens the window, right-click opens Settings.")
and **M6** (the button, and its tooltip: `SpellTuner`, `Out of mana in ~1:20`, `Full again in ~2:10
if you stop`, a spacer, `Left-click open the window`, `Right-click Settings`, `Drag move it round the
map`, and the muted `Hide it: Settings -> General -> Windows.`). TBC does not change until wave C (C1
turns `UI.THEMED` on there, and C4 rewrites `Tip:Clock`'s words).

## What was built

| File | Change |
|---|---|
| `UI/MinimapButton.lua` | **One file for both lines.** It declares its default once: `MD:RegisterDefaults({ minimap = { hide = false, angle = 220 } })`. Two seams, and no client test. (a) The clock lines come from `MD.MinimapLines(hints)`, provided once per line through `MD:Provide("MinimapLines", fn)`. With no provider the tooltip shows only the title. (b) The tooltip's shape follows `UI.THEMED`. **Unthemed** (TBC) it makes the old call byte for byte: `MD.Tip:Show(self, "ANCHOR_LEFT", MD.MinimapLines({ "Left-click: dashboard", "Right-click: settings" }))`. **Themed** (Forever) it shows M6's lines through `MD.Tip:Show(self, lines, { anchor = "ANCHOR_LEFT" })`: the provider's lines with no hints, a spacer, three `label` / white pairs, and the `muted` hide line. Clicks, the drag, the radius (half the minimap's width + 5), the 31 x 31 button, its textures and `MD:UpdateMinimapButton` are unchanged. |
| `UI/Tip_TBC.lua` | One line at the end: `MD:Provide("MinimapLines", function(hints) return Tip:Clock(hints) end)`. `Tip:Clock` is unchanged. |
| `UI/Clock_Forever.lua` | **`Clock:SummaryLines(now, state)`** gives the clock's answer as `label` pairs: the mode line (`Out of mana in ~1:20`, `Full again in ~0:45`, `Out of mana in` / `a few more casts first`, `not at this pace`, `Full` / `now`), and in a fight `Full again in ~2:10 if you stop`. It answers `{}` before the pool has a model. **`Clock:HoverLines` now reads these lines** in place of its own copy, with unchanged output and order (Mana, the summary, then in a fight Spending and Regen). The hover and the minimap tooltip cannot drift apart. The Forever `MinimapLines` provider gives the `accent` title `SpellTuner`, the summary, and the hints when it is given any. The local `Pair` moved above both functions. |
| `UI/Dashboard_Forever.lua` | **`MD:OpenDashboardSettings()`** calls `MD:SelectView("settings", "general")`. **WINDOWS** gains the *Minimap button* checkbox (`pane.minimapCheck`) at -77. It writes `db.minimap.hide = not checked` and calls `MD:UpdateMinimapButton()`. Its tooltip is "The SpellTuner button on the minimap's rim." with "Left-click opens the window, right-click opens Settings; drag it round the map." Under it is M1's hint (`pane.minimapHint`), "Left-click opens the window, right-click opens Settings.". *Reset window positions* now sits under the hint, and the section grows from 100 to 138. `RefreshGeneralPane` ticks the box from the db. |
| `Core_TBC.lua` | The `minimap = { hide = false, angle = 220 },` line leaves `DEFAULTS`. A comment names the owner. |
| `tools/wowstub.lua` | `_G.Minimap`: a frame of 140 x 140. `GetCenter` answers `S.minimapCenter` (default `{ 1200, 600 }`) and `GetEffectiveScale` answers `S.minimapScale` (default 1). `GetCursorPosition()` answers `S.cursorPos` (`{ x, y }`), and nothing while it is nil. Before this task the stub had no `GetCursorPosition` at all, and `UI/Tip.lua`'s `CursorX` reads nil either way. |
| `tools/minimapcheck.lua` (new) | Both flavours (below). `--print` prints the TBC golden. |
| `tools/dashui.lua` | **Not owned (deviation 1).** Its Settings load list adds `UI/MinimapButton.lua` in front of `UI/Options_General.lua`. |

## The checks (`tools/minimapcheck.lua`)

**TBC (6).** Written and run on the parent before the first edit, and equal after it:

1. The button is `SpellTunerMinimapButton`, a `Button` on `Minimap`, 31 x 31.
2. On a fresh db, `db.minimap` is `{ hide = false, angle = 220 }`.
3. Its point at 220 degrees is `CENTER Minimap CENTER -57.453 -48.209`. Dragged east it stores 0 at
   (75, 0), dragged north 90 at (0, 75), and dragged south-west at a minimap scale of 2 it stores 225
   at (-53.033, -53.033). `OnDragStart` sets `OnUpdate` and `OnDragStop` clears it.
4. Left-click calls `MD:ToggleDashboard` and right-click calls `MD:OpenDashboardSettings` (spies;
   the TBC harness does not load `UI/Dashboard.lua`).
5. `db.minimap.hide` hides the button through `MD:UpdateMinimapButton`, and showing it again works.
6. **The tooltip's anchor and its 15 lines, colours included, as a golden** taken two ticks after
   login: the title in the druid's class colour, `FULL`, the raw mana lines, Innervate, and the two
   muted hints. Every assertion is in `GOLDEN_TBC`.

**Forever (8).** Red on the parent, which has no button on this line:

1. `SpellTunerMinimapButton` exists after `MD_READY`, on `Minimap`, loaded by the main TOC
   (`UI/MinimapButton.lua` after `UI/Clock_Forever.lua` in both `SpellTuner_Mainline.toc` and
   `SpellTuner.toc`). On a tree whose TOC lacks the line the suite loads the file by hand, so the
   other checks still report, and this one fails.
2. A drag with the pointer due east stores angle 0 and puts the button at (75, 0).
3. With `db.uiPath = { "reports", "review" }` a left-click opens the main window on Review, and a
   second left-click closes it.
4. A right-click opens Settings -> General.
5. The WINDOWS checkbox reads `Minimap button` with M1's hint. Unticking it hides the button and
   writes `db.minimap.hide = true`, and ticking it shows the button again. With `hide` set while the
   pane is away, showing the pane unticks the box.
6. The themed tooltip has M6's 8 lines. The title `SpellTuner` is in `accent`. `Out of mana in` /
   `~m:ss` and `Full again in` / `~m:ss if you stop` have `label` labels and `mana` values. Then come a
   spacer, the three pairs and the `muted` hide line. The anchor is `ANCHOR_LEFT`, and every string is
   ASCII with no bare pipe. Its clock lines are `MD.Clock:SummaryLines()`, and the clock's own hover
   carries the same pairs at the same moment.
7. On a fresh db, `db.minimap` is `{ hide = false, angle = 220 }`.
8. The default is declared once, by the button file through `MD:RegisterDefaults`, and no file on
   any TOC carries a `minimap = {` default of its own.

## Failing first

The parent `7fd71b3` with `tools/wowstub.lua` and `tools/minimapcheck.lua` copied in:

```
=== minimapcheck (tbc)        6 ok, 0 failed     <- the golden, equal before and after
=== minimapcheck (forever)    1 ok, 7 failed
  FAIL 7. on a fresh db, db.minimap is { hide = false, angle = 220 } - no db.minimap
  FAIL 1. SpellTunerMinimapButton exists after MD_READY, on Minimap, from the main TOC - button=true loadedByToc=false Mainline=false plain=false load: .../UI/MinimapButton.lua:11: attempt to index field 'minimap' (a nil value)
  FAIL 2. a drag due east stores angle 0 and puts the button at (75, 0) - raised: .../UI/MinimapButton.lua:23: attempt to index field 'minimap' (a nil value)
  FAIL 4. right-click opens Settings -> General - raised: .../UI/MinimapButton.lua:50: attempt to call method 'OpenDashboardSettings' (a nil value)
  FAIL 5. WINDOWS: Minimap button hides the button and writes db.minimap.hide; ticked, back - raised: .../tools/minimapcheck.lua:343: attempt to index field 'minimap' (a nil value)
  FAIL 6. the themed tooltip is M6's, its clock lines the clock hover's own - raised: .../UI/MinimapButton.lua:23: attempt to index field 'minimap' (a nil value)
  FAIL 8. the minimap default is declared once, by the button file (MD:RegisterDefaults) - registers=false declared in: Core_TBC.lua
```

Check 3 passes on the parent because the hand-loaded old file already called the Forever
`MD:ToggleDashboard`. Check 1 is the one that holds the wiring.

On this branch, in a copy with the TOC lines applied: TBC `6 ok, 0 failed`, Forever `8 ok, 0 failed`.

**Mutations** (scratch copy):

- With the right-click branch calling `MD:ToggleDashboard()`, both halves go red. TBC fails
  `left-click toggles the dashboard, right-click opens its settings - toggles=2 settings=0`. Forever
  fails `4. ... - view=spells/overview` and `5.` (Settings never opened).
- With the theme test inverted (`not UI.THEMED`), both halves go red. TBC fails `the tooltip, line
  for line (golden) - 17 lines, want 15` and Forever fails `6.` (`spacer=false hints=false
  hide=false`).

## Suites, before and after

Before: `7fd71b3`, `tools/check.sh` green, 68 runs, 63 counted. After: this branch in a scratch copy
with the TOC lines and the rebuilt import fixture: **70 runs, all passed**, 63 counted against 63
expected, plus `minimapcheck/forever` 8 and `minimapcheck/tbc` 6 (new, "not in the expected
counts").

| Suite | Before | After |
|---|---|---|
| `minimapcheck/tbc` | (new; 6 on the parent) | 6 |
| `minimapcheck/forever` | (new; 1 of 8 on the parent) | 8 |
| `slashcheck/tbc` (golden transcript) | 8 | 8 |
| `defaultscheck/forever` / `tbc` | 52 / 48 | 52 / 48 (its Forever scan now covers the button file and finds `minimap`'s default) |
| `clockcheck/forever` (the hover reads `SummaryLines`) | 29 | 29 |
| `wincheck/forever` | 66 | 66 |
| `spelltip/tbc`, `consolecheck/forever` / `tbc` | 49, 20 / 1 | the same |
| `dashui/tbc` | 67 | 67 (one load-list line, deviation 1) |
| `importcheck` | 21 | 21 (with the fixture rebuilt, below) |
| every other suite | as `tools/data/expected-counts.json` | the same |
| `apicheck` | 0 findings, 8 Forever TOCs, 57 files, 47 globals | 0 findings, 8 Forever TOCs, **58** files, **48** globals (`Minimap` / `GetCursorPosition`, both in `TOOLKIT`) |
| `textcheck` | 0 findings, 9 TOCs, 94 files | 0 findings, 9 TOCs, 94 files |

On the committed tree without the TOC lines, `minimapcheck/forever` fails check 1 (7 ok, 1 failed)
and `defaultscheck/forever` fails "every setting read on the forever TOCs has a default", naming
`minimap` at `UI/Dashboard_Forever.lua:106`. Both pass once the lines are in.

`luac -p` passes on `UI/MinimapButton.lua`, `UI/Tip_TBC.lua`, `UI/Clock_Forever.lua`,
`UI/Dashboard_Forever.lua`, `Core_TBC.lua`, `tools/wowstub.lua`, `tools/minimapcheck.lua` and
`tools/dashui.lua`.

## Integrator lines

**`SpellTuner_Mainline.toc`** and **`SpellTuner.toc`** (identical): add one new line right after
`UI\Clock_Forever.lua`:

```
UI\Clock_Forever.lua
UI\MinimapButton.lua
```

`SpellTuner_TBC.toc` is unchanged (`UI\MinimapButton.lua` stays at its place after
`UI\Options_About.lua`). No module TOC changes.

**`tools/data/import-forever-sv.lua`**: rebuild it after the TOC lines with
`bash tools/run.sh tools/importfixture.lua`. A Forever db now carries the registered default, so
the fixture gains exactly these four lines (checked in the scratch copy, and `importcheck` 21 ok
after):

```
	["minimap"] = {
		["angle"] = 220,
		["hide"] = false,
	},
```

**`tools/data/expected-counts.json`**: add these two entries:

```
  "minimapcheck/forever": 8,
  "minimapcheck/tbc": 6,
```

**CLAUDE.md**:

- A new row after `UI/Clock_Forever.lua`'s: `| `UI/MinimapButton.lua` | **The minimap button, both lines** (T79, P36; section 8.1 item 10, mockups M1 / M6): `SpellTunerMinimapButton` on `Minimap` (collectors adopt it by name), 31 x 31, dragged round the rim (`db.minimap.angle`, radius half the minimap's width + 5); left-click `MD:ToggleDashboard` (the remembered view), right-click `MD:OpenDashboardSettings`; `db.minimap` declared here (`MD:RegisterDefaults`, `{ hide = false, angle = 220 }`). Two seams: the clock lines `MD.MinimapLines(hints)` (`MD:Provide`: TBC `Tip:Clock`, Forever `MD.Clock:SummaryLines` with the title) and the shape by `UI.THEMED` (unthemed TBC's old lines byte for byte; themed M6's -- the clock lines, `Left-click` / `Right-click` / `Drag` pairs, the muted `Hide it: Settings -> General -> Windows.`). TBC TOC after `UI/Options_About.lua`, the Forever main TOCs after `UI/Clock_Forever.lua` |`
- The `UI/Clock_Forever.lua` row: append `**T79 (P36):** `Clock:SummaryLines(now, state)` -- the mode line and, in a fight, `Full again in ~N if you stop` -- read by the hover and by the minimap button's tooltip (the Forever `MinimapLines` provider)`.
- The `UI/Dashboard_Forever.lua` row: append `**T79 (P36):** `MD:OpenDashboardSettings()` (Settings -> General, the minimap button's right-click); WINDOWS gains *Minimap button* (`db.minimap.hide`, `MD:UpdateMinimapButton`) with M1's sentence`.
- The `Core_TBC.lua` row: append `**T79:** `minimap` left `DEFAULTS` (`UI/MinimapButton.lua` registers it)`.
- The `tools/` row: after `**`tools/ttocheck.lua`** (T58, tbc): ...`, add: `**`tools/minimapcheck.lua`** (T79, tbc + forever): the minimap button -- TBC's golden (name, parent, size, points after drags, clicks, hide, the tooltip line for line, captured on `7fd71b3` before the edit; `--print`) and Forever's eight (the TOC loads it, drag, left / right click, the WINDOWS box, M6's themed tooltip sharing `SummaryLines` with the clock hover, the default, declared once); the stub's `Minimap` (`S.minimapCenter`, `S.minimapScale`) and `GetCursorPosition` (`S.cursorPos`)`.

**docs/TOOLS.md** section 1: add `minimapcheck` (tbc, forever) to the suite list, with this text:
"the minimap button: TBC golden, Forever's eight; `--print` prints the TBC golden".

**docs/TESTING.md** section 44: item 25 as the plan words it ("Minimap button (P36). On Forever the
SpellTuner button sits on the minimap's rim; drag it round, `/reload`, and it stays there. Left-click
opens the window on the view you left, again closes it; right-click opens Settings -> General;
unticking *Minimap button* under WINDOWS hides it. If you use a minimap-button collector, say whether
it picked the button up. On TBC nothing changes until wave C.").

**docs/DECISIONS.md**: none. This is a new Forever surface the author asked for (section 8.1 item
10), and TBC is unchanged.

## Deviations

1. **`tools/dashui.lua` was edited, although P36 does not own it.** `Core_TBC.lua`'s `DEFAULTS` no
   longer carries `minimap`, as the plan asks. `dashui` loads `UI/Options_General.lua`, whose TBC
   "Show minimap button" box reads `MD.db.minimap.hide`, but it never loads `UI/MinimapButton.lua`,
   the file that now registers that default. So `dashui` raised at `Options_General.lua:285`. In game
   the TBC TOC always loads the button file. The fix is one load-list entry (`UI/MinimapButton.lua`
   in front of the Options files) with a comment, and the count stays 67. No other wave-17 task owns
   `dashui` (P34 owns `spellsui`, `tipcheck`, `themecheck`), so the edit cannot conflict. The
   alternative was keeping `Core_TBC.lua`'s line as a second declaration, which breaks P20's rule
   and check 8.
2. **The import fixture needs a rebuild** that the task does not commit
   (`tools/data/import-forever-sv.lua` is not owned, and it changes only once the TOC loads the
   button). It is listed above as an integrator step.
3. **The stub's pointer is `S.cursorPos`, not `S.cursor`.** The plan names `S.cursor`, but that name
   has been `GetCursorInfo`'s since T36 (a spell dragged from the spellbook), and reusing it would
   break `spellsui`'s drop onto the rail. The Minimap's centre and scale are settable too
   (`S.minimapCenter`, `S.minimapScale`), so the TBC golden can drag at a minimap scale of 2.
4. **The hint pairs' values are a literal white `{ 1, 1, 1 }`** (M6's `.w`), not the `text` token,
   so the button's own lines read only `accent`, `label`, `muted` and `mana`, as the plan says. The
   clock's summary lines are the clock hover's (P32), and its `Full` / `now` line keeps the `text`
   token it already used. Neither reads `text2`, which P34 merges.
5. **The TBC golden is taken two ticks after login** (the clock's mana state present). That makes it
   carry the raw mana lines and Innervate rather than only the title and hints. It was captured on
   the parent before the first edit and is equal after it.
