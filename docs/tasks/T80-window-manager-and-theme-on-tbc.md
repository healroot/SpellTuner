# T80 -- The window manager and the theme on TBC (plan C1)

Status: **built** 2026-10-01 on branch `plan/C1` (base `bf35c93`), wave C-a of
`docs/PLAN-refactor-ux.md`, awaiting the integrator. **The branch needs its TOC lines (below).**
The task renames `UI/Theme_Forever.lua` and `UI/Windows_Forever.lua` and adds `UI/EscStack.lua`,
and all three main TOCs are integrator-owned. Without the lines, every Forever suite fails at
load: the Forever TOCs still name the two old files, so the harness cannot open
`UI/Theme_Forever.lua`. The TBC TOC also does not yet list the theme and the manager. The TOCs
were not edited in the worktree. Every suite was run in a scratch copy of the worktree with the
TOC lines below applied. The failing-first runs used the parent `bf35c93`, taken with
`git archive`.

## The task (docs/PLAN-refactor-ux.md section 5.C, C1; review A22, A6c)

Decision 10, the author's answer 1 (section 8.1): "I would like to have updated UI on TBC as well
once its ready". C1 is the base of wave C. It puts the window manager and the flat theme on TBC, so
`UI.THEMED` becomes true there and everything P27-P33 gated under it turns on.

- **The manager takes its knowledge from the dashboard at `Register`** (A22). The window that
  registers with role `host` hands in five things: its sizes per group (`sizes`), the group it
  opens on (`group`), how to open it on a view (`open`), how to read the view it shows
  (`selected`), and the view a practice session goes back to (`practicePath`). A takeover window
  hands in the line `ShowMain` prints while a practice session plays (`busy`).
  - `Win.SIZES`, `Win.DEFAULT_GROUP`, `Win.PRACTICE_PATH` and `Win.PRACTICE_REFUSED` are gone from
    the manager.
  - The key `"main"` is no longer special-cased: the manager reads `Win.host`. `Win.SIZES` remains
    only as a reference to the host's table once it registers, for the suites that read it
    (`practiceforever`).
  - Forever's sizes moved into `UI/Dashboard_Forever.lua`, unchanged. TBC's table is in
    `UI/Dashboard.lua`.
- **The ESC stack is `UI/EscStack.lua`** (`MD.EscStack`). Its calls are also on `MD.Win`: `Push`,
  `Remove`, `Prune`, `OnEsc`, `CloseLists`, `TopWindow`, `EscStackOn`, `SetEscStack`, `EscLine`,
  `.stack` and `.proxy`. They share the same table and the same proxy, so `Client/Probe.lua` and
  the suites that call them there are untouched.
- **Renames:** the theme is now `UI/Theme_Flat.lua` and the manager `UI/Windows.lua`. Both are
  listed on `SpellTuner_TBC.toc` (integrator lines below).
- **The `if MD.Win` else-branches are deleted** in `UI/Dashboard_Forever.lua`,
  `UI/DebugConsole.lua`, `UI/PracticePanel.lua`, `UI/BindingsWindow.lua`, `UI/ReplayWindow.lua`,
  `UI/SpellsPane_Forever.lua`, `Practice/Commands_Forever.lua` and `Core_Forever.lua`. This
  removes:
  - TBC's `UISpecialFrames` entries for the dashboard, the replay, the console and the bindings
    window;
  - the replay's `HIGH` strata and its own `db.replayPos` positioning;
  - TBC's separate bindings window, which is now T40's sheet on Simulate -> Practice.
- **Saved places migrate with `Win:Adopt`:**
  - TBC's `db.replayPos` goes through the existing adoption path, now reached on TBC too.
  - The TBC dashboard was user-placed: the client kept its place. It registers with
    `adoptPlaced = true`, so a place the client gave it is adopted once into `db.ui.win.main`. The
    kit's untouched centre is not adopted.
- **The `ui` defaults left `Core_Forever.lua`'s `DEFAULTS`** for `MD:RegisterDefaults` in the files
  that read them:
  - `UI/Theme_Flat.lua`: `fontOffset`;
  - `UI/EscStack.lua`: `escStack`;
  - `UI/Windows.lua`: `scale`, `combat`, `win`.

  TBC therefore gets all of them. The theme also gains `UI.SetFontOffset(n)` (apply and save),
  which both Settings panes call.
- **TBC's Settings -> General gains a third column, Windows**, with M1's controls: In combat,
  Close one window per ESC, Text size, Window size, Reset window positions.
- **The TBC UI suites load the theme and the manager**, as the TOC now does. Their assertions that
  pinned the unthemed TBC look now hold the themed expectation (listed below).

## What changes on TBC in game (the DECISIONS entry below)

`/md` opens the window in the flat theme, at today's 1036 x 646 for every group (fixed, no grip).
It is placed by the manager, and the window scale applies. One ESC closes the top window only.
Entering combat hides the window, and a review replay, and they come back on the same view after
the fight (Settings -> General -> Windows -> In combat: "Keep them open" turns that off). The first
time this happens, one chat line explains it.

Changes inside the window:
- **Review** is P27's pane: the generic table, the row menu, Coach anyway instead of the Coach*
  star and shift-click, the result area, and a list that scrolls.
- **The replay** has P28's status band and two-column layout while coaching. It is a takeover
  (`DIALOG`, "< SpellTuner") instead of a `HIGH` window.
- **Practice** shows its bindings as a one-line summary, and Edit bindings opens the sheet.
- **Tooltips** take the kit's flat skin.
- **The debug console** is a `FULLSCREEN` tool on the ESC stack.

The minimap tooltip takes P36's themed shape. M6's words for it are C4's.

## Files

| File | Change |
|---|---|
| `UI/Windows_Forever.lua` -> `UI/Windows.lua` | The ESC stack moved out. The host's knowledge comes in at `Register` (`sizes`, `group`, `open`, `selected`, `practicePath`, `adoptPlaced`; a takeover's `busy`). `Win.host` and the `Win.SIZES` reference. `ClientPlace` adoption. The stack calls delegated. `MD:RegisterDefaults({ ui = { scale, combat, win } })`. |
| new `UI/EscStack.lua` | `MD.EscStack`: the proxy, `Push` / `Remove` / `Prune` / `OnEsc` / `CloseLists` / `TopWindow` / `On` / `Set(on, shown)` / `Line`, and the `UI_POPUP` subscription. `MD:RegisterDefaults({ ui = { escStack = true } })`. The proxy's OnHide goes through `MD.Win:OnEsc` when the manager is there. |
| `UI/Theme_Forever.lua` -> `UI/Theme_Flat.lua` | Header (every main TOC). `MD:RegisterDefaults({ ui = { fontOffset = 0 } })`. `UI.SetFontOffset`. |
| `UI/Dashboard.lua` (TBC) | `SIZES` (four groups, 1036 x 646, fixed). Registered as the host with `adoptPlaced`. `MD:OpenMainWindow`. `MD:SelectView` / `MD:ToggleDashboard` through `MD.Win:ShowMain`. `SetGroup` on every selection. Its `UISpecialFrames` line is gone. |
| `UI/Dashboard_Forever.lua` | `SIZES` moved here. Host registration with the dashboard's functions. `MD:SelectView` builds the window first (the host must exist before `ShowMain` opens it). The `MD.Win` guards are gone. Text size goes through `UI.SetFontOffset`. |
| `UI/Options_General.lua` (TBC) | Windows pane (third column, x 439): the combat dropdown, the ESC check, Text size, Window size (applied on mouse-up), Reset window positions. Refreshed on show. `pane.windowsPane` for `dashui`. |
| `UI/DebugConsole.lua` | Always a registered tool, and the copy box always on the stack. |
| `UI/PracticePanel.lua` | Every pane a host for the sheet. `PracticeHost` reads `MD.Win.host`. Edit bindings opens the sheet. |
| `UI/BindingsWindow.lua` | The sheet only (the movable window is gone). `ShowSheet` opens Simulate -> Practice through `MD:SelectView`. `MD:ToggleBindings` toggles the sheet. |
| `UI/ReplayWindow.lua` | Always a takeover with "< SpellTuner". `busy` is handed in. `db.replayPos` is adopted on both lines. `TakeOver` is unconditional. The T72 comment is updated. |
| `UI/SpellsPane_Forever.lua` | The picker's `Push` is unguarded. |
| `Practice/Commands_Forever.lua` | `/st practice` and `/st binds` without the `MD.Win` fallbacks. |
| `Core_Forever.lua` | `ui` left `DEFAULTS` (comment). `/st ui reset` is unguarded, and its comment names `UI/Windows.lua`. |
| `tools/wincheck.lua` | Declared `{ "forever", "tbc" }`. Forever check 1 now says the stack and the manager are on all three main TOCs. The new tbc half has 4 checks. |
| `tools/themecheck.lua` | The tbc half loads the theme and holds it (9 checks, rewritten). Forever check 1 now says `Theme_Flat.lua` follows `Style.lua` on all three TOCs. |
| `tools/defaultscheck.lua` | +1 (tbc): every `db.ui` key has a default, declared by the three files. |
| `tools/dashui.lua` | Loads the theme and the manager. One expectation changed. +1: the Windows pane. |
| `tools/navui.lua`, `reviewui.lua`, `replayui.lua`, `practiceui.lua`, `spelltip.lua`, `consolecheck.lua` | Each loads the theme and the manager (plus `UI/ContextMenu.lua` and `UI/Dashboard_Rows.lua` where Review is built). The changed expectations are listed below. |

## The checks

**`wincheck/tbc` (new, 4)**, run with the stub's geometry on, the TBC UI files loaded in TOC order:

1. The TBC window registers as the host:
   - `Win.host`, role `host`, strata `HIGH`, not user-placed.
   - TBC's sizes: each of Spells, Reports, Simulate and Settings opens at 1036 x 646, and
     `Win:Fixed` holds for each.
   - Every `MD:SelectView` goes through `MD.Win:ShowMain`.
   - `SpellTunerDashboard` is not in `UISpecialFrames`, and only the proxy is.
2. A place kept before C1 is adopted:
   - The dashboard, which the client had put at TOPLEFT (100, 700) as a user-placed frame, is
     saved there in `db.ui.win.main`.
   - `db.replayPos = { "TOPLEFT", "BOTTOMLEFT", 40, 600 }` becomes `db.ui.win.replay` (40, 600)
     and is deleted.
3. One ESC closes the top window only: the debug console first, the dashboard on the next press.
4. A fight hides the window, and `PLAYER_REGEN_ENABLED` shows it again on Settings -> General.

**`wincheck/forever`**: 66, equal. Check 1 now reads
`UI/EscStack.lua then UI/Windows.lua are in all three main TOCs`.

**`defaultscheck/tbc`** 48 -> 49. The new check: `db.ui` on a fresh TBC database and in
`MD.DEFAULTS` holds fontOffset 0, scale 1, combat hide, escStack true and win {}. The keys are
declared (`RegisterDefaults({ ui = ...`) in exactly `UI/EscStack.lua`, `UI/Theme_Flat.lua` and
`UI/Windows.lua`.

**`dashui/tbc`** 67 -> 68. The new check: the Windows pane's five controls write
`db.ui.combat`, `escStack`, `fontOffset` and `scale` through the manager or the theme, and Reset
empties `db.ui.win`.

### Expected values that changed (the re-baseline under the theme)

| Suite | Check (old -> new) | Old expectation | New expectation |
|---|---|---|---|
| `themecheck/tbc` | `UI.THEMED is false with UI/Style.lua alone` -> `UI.THEMED is true with the theme loaded as the TBC TOC lists it` | false | true |
| `themecheck/tbc` | `the tokens hold the literals the shared files carried` -> `the tokens equal Forever's ...` | accent ffcc00, muted 888888, disabled 555555, dominated 8a8a8a, note ffcc00, tipGold 1/0.82/0 | accent ff7c0a (druid), text ffffff, text2 = label b3b3b3, muted 7a7a7a, disabled 4d4d4d, mana 4d99ff, good 5ccb6e, bad e0605a; dominated = text, note = text2, tipGold = accent |
| `themecheck/tbc` | `the palette keeps its window fills ...` -> `the palette is Forever's ...` | frame 0.1/0.9, pane 0.13 | frame 22/255 at 0.96, pane 28/255 (hover 0.12, selected 0.28, suggested 0.10, rowAlt, line and border unchanged) |
| `themecheck/tbc` | `Review's small text is GameFontHighlightSmall, never the kit's` -> `... is the kit's UI.FONT_SMALL, never GameFontHighlightSmall` | >= 3 GameFontHighlightSmall, 0 kit | 0 GameFontHighlightSmall, >= 3 kit |
| `themecheck/tbc` | `a kit button, check box and edit box paint the old literals, 1-unit edges` -> `... take the theme's pixel edges, registered` | edgeSize 1, nothing registered | edgeSize = insets = `UI.px(1)`, all three registered (fills unchanged: 0.115, accent 0.6, close 0.6/0.1/0.1) |
| `navui/tbc` | `on TBC the active style is today's` -> `on TBC the active style is the theme's` | the active group in its hover colour, scripts dropped, no bar | the `selected` fill with the left 2-px bar, the tab's bar at the bottom, hover laid over an inactive group |
| `navui/tbc` | `on TBC view tabs are #text * 8 + 16 by 20` -> `on TBC view tabs are the theme's, 22 high` | 13 * 8 + 16 wide, 20 high | 22 high like the group buttons (not the old width) |
| `dashui/tbc` | `T76: a disabled TBC button has no motion scripts` -> `T76/T80: a disabled TBC button keeps its motion scripts (the theme's)` | `motionWhileDisabled == nil` | `== true` |
| `spelltip/tbc` | `T76: TBC's Tip:Show is GameTooltip, unskinned` -> `T76/T80: TBC's Tip:Show is GameTooltip, in the kit's skin` | not skinned, THEMED false | skinned, THEMED true (still GameTooltip, the kit tooltip untouched) |
| `consolecheck/tbc` | `TBC installs no error handler and keeps its Regen test button` (name kept) | `MD.Win == nil`, the console in `UISpecialFrames` | a registered `tool`, on the stack, not in `UISpecialFrames` |
| `reviewui/tbc` | `a rejected fight keeps a clickable Coach, marked` -> `... keeps a clickable Coach, no star` | a `Coach*` button | `Coach`, enabled, and no `Coach*` |
| `reviewui/tbc` | `shift-click coaches it anyway` -> `the row menu's Coach anyway coaches it` | shift-click on `Coach*` | right-click the row, then the menu's Coach anyway (answer 5) |
| `reviewui/tbc` | `and the column says it was forced` -> `and the band says it was coached anyway` | `FORCED` in the right column's title | `coached anyway` in the band's verdict (P28) |
| `reviewui/tbc` | `shift-click Play forces from the tab` -> `shift-click Play no longer forces (Coach anyway does)` | the right column drawn | not drawn |
| `reviewui/tbc` | `a 36-pull run ends with the tail line` -> `a 36-pull run scrolls to pull 36, no tail line` | 18 rows and `... and 18 more` | the wheel reaches 36, no tail line (P27) |
| `reviewui/tbc` | `selecting pull 36 keeps it on screen` (name kept) | rows 19..36 and the tail line | 36 still listed after a render, no tail line |
| `reviewui/tbc` | rows clicked by `OnMouseUp` with the clock a second apart (the generic table), and the replay's background coach drained before the plain-click check | | |
| `replayui/tbc` | `left only without a plan` -> `without a plan the suggested column is laid out, dimmed and empty` | right title hidden | right title shown, `dimmed == true`, no plan |
| `replayui/tbc` | `the hint says what it is doing` -> `the suggested column's title says what it is doing` | `coach` in the hint | `coaching` in the right column's title |
| `replayui/tbc` | `narrower window` -> `two columns wide at once (968), not a narrower window` | width < 500 | width 968 |
| `replayui/tbc` | `...and the hint names the gate and the way past it` -> `...and the band names the gate, with Coach anyway` | `does not replay` and `force` in the hint | `does not replay: mana mean` in the band, Coach anyway shown |
| `replayui/tbc` | `T51: combat at a pull boundary ...` (name kept) | | run under `db.ui.combat = "keep"`: the manager hides the replay in combat by default now |
| `replayui/tbc` | `T72: combat lets go of the keyboard until re-entry` (name kept) | | run under `"keep"`, for the same reason |
| `replayui/tbc` | `T72: TBC keeps its header, no band, no key hint` -> `T72/T80: TBC has the band, its verdict and the key hint` | `band == nil`, `replays` in the header | the band and the key hint present, `replays` (good) in the band |
| `practiceui/tbc` | `the panel lists what your presses cast` (name kept) | a font string with `BUTTON5` and `Lifebloom` | the summary `6 bindings` and, in its hover, the `BUTTON5 ... Lifebloom` line |
| `practiceui/tbc` | `the bindings window opens` -> `the bindings sheet opens on the panel` | shown | shown and `bindingsSheet == true` |

The counts stay equal for all of these suites except `dashui` (+1).

## Failing first

**The parent `bf35c93`** with T80's suites copied in:

```
=== wincheck (tbc)        exit 1   (raised: load UI/Theme_Flat.lua: cannot open)
=== wincheck (forever)    65 ok, 1 failed   UI/EscStack.lua then UI/Windows.lua are in all three main TOCs  FAIL
=== themecheck (tbc)      exit 1   (raised: load UI/Theme_Flat.lua)
=== themecheck (forever)  36 ok, 1 failed   UI/Theme_Flat.lua follows UI/Style.lua in all three main TOCs (TBC's too)  FAIL
=== defaultscheck (tbc)   48 ok, 1 failed   tbc: every db.ui key has a default ...  FAIL - db false, defaults false, declared in
=== dashui, navui, reviewui, replayui, practiceui, spelltip (tbc)   exit 1 (load UI/Theme_Flat.lua)
=== consolecheck (tbc)    0 ok, 1 failed  (load UI/Theme_Flat.lua)
```

**The parent with T80's three new files** (`Theme_Flat.lua`, `EscStack.lua`, `Windows.lua`) and
the TBC TOC lines, but the parent's dashboards, settings and windows. This shows what the TBC
files' own changes are needed for:

```
=== wincheck (tbc)     0 ok, 4 failed
  the TBC window registers as the host ...          FAIL - ... routed=0
  a place kept before C1 is adopted ...             FAIL - main nil,nil replay 40.00,600.00
  one ESC closes the top window only ...            FAIL - both=true first=false second=true
  a fight hides the window and it reopens ...       FAIL - before=true hidden=false after=true
=== dashui (tbc)       67 ok, 1 failed   T80: the Windows pane in Settings -> General ...  FAIL
```

On this branch, in the scratch copy with the TOC lines applied, every one of those runs passes.

**Mutations** (scratch copy):

- **M1.** The TBC dashboard keeps its own `tinsert(UISpecialFrames, "SpellTunerDashboard")`.
  `wincheck/tbc` fails check 1 (not only the proxy is special) and check 3 (one ESC closes both
  windows: `first=false`).
- **M2.** The Windows pane's combat dropdown writes nothing. `dashui/tbc` fails
  `T80: the Windows pane ...`.
- **M3.** `Win:Register` drops the host's `open`. `wincheck/tbc` fails check 3 (`both=false`: the
  window never opens) and check 4 (`after=false`).

## Suites, before and after

Before: `tools/check.sh` on `bf35c93` gave **70 runs, all passed**, 65 counted against 65.

After: `tools/check.sh` in the scratch copy with the TOC lines gave **71 runs, all passed**, 66
counted against 65. The notes:
- `wincheck/tbc: 4 assertion(s), not in the expected counts`
- `defaultscheck/tbc: 49 assertion(s), 48 expected`
- `dashui/tbc: 68 assertion(s), 67 expected`

| Suite | Before | After |
|---|---|---|
| `wincheck/forever` | 66 | 66 |
| `wincheck/tbc` | (none) | 4 |
| `themecheck/forever` / `tbc` | 37 / 9 | 37 / 9 |
| `defaultscheck/forever` / `tbc` | 52 / 48 | 52 / **49** |
| `dashui/tbc` | 67 | **68** |
| `navui/tbc` | 46 | 46 |
| `reviewui/tbc` | 49 | 49 |
| `replayui/tbc` | 107 | 107 |
| `practiceui/tbc` | 52 | 52 |
| `spelltip/tbc` | 49 | 49 |
| `consolecheck/forever` / `tbc` | 20 / 1 | 20 / 1 |
| `spellsui`, `reviewforever`, `replayforever`, `practiceforever` (forever) | 50, 22, 28, 29 | 50, 22, 28, 29 |
| `probecheck/tbc` (the `esc=` line through the delegated `EscLine`) | 88 | 88 |
| every other suite | as `tools/data/expected-counts.json` | the same |
| `apicheck` | 0 findings, 8 Forever TOCs, 58 files, 48 globals | 0 findings, 8 Forever TOCs, **59** files (`UI/EscStack.lua`), 48 globals |
| `textcheck` | 0 findings, 9 TOCs, 94 files | 0 findings, 9 TOCs, **95** files |

`luac -p` passes on every changed shipped file: `UI/Windows.lua`, `UI/EscStack.lua`,
`UI/Theme_Flat.lua`, `UI/Dashboard.lua`, `UI/Dashboard_Forever.lua`, `UI/Options_General.lua`,
`UI/DebugConsole.lua`, `UI/PracticePanel.lua`, `UI/BindingsWindow.lua`, `UI/ReplayWindow.lua`,
`UI/SpellsPane_Forever.lua`, `Modules/SpellTuner_Practice/Commands_Forever.lua`,
`Core_Forever.lua`.

## Integrator lines

**`SpellTuner_Mainline.toc`** and **`SpellTuner.toc`** (identical): replace

```
UI\Theme_Forever.lua
UI\Windows_Forever.lua
```

with

```
UI\Theme_Flat.lua
UI\EscStack.lua
UI\Windows.lua
```

(Same place: right after `UI\Style.lua`, before `UI\ContextMenu.lua`.)

**`SpellTuner_TBC.toc`**: right after `UI\Style.lua` (so before `UI\ContextMenu.lua` and well
before `UI\Dashboard_Rows.lua`), add

```
UI\Theme_Flat.lua
UI\EscStack.lua
UI\Windows.lua
```

No module TOC changes.

**`tools/data/expected-counts.json`**: add `"wincheck/tbc": 4`. Change `"defaultscheck/tbc"` to
49 and `"dashui/tbc"` to 68.

**`tools/data/import-forever-sv.lua`**: no rebuild needed. Rebuilt in the scratch copy with the
TOC lines (`bash tools/run.sh tools/importfixture.lua`), it is byte for byte the committed file.

**CLAUDE.md**:

- The `UI/Theme_Forever.lua` row becomes `UI/Theme_Flat.lua`:
  > **The flat theme** (T29, 0.16.2; `docs/SPEC-forever-ui.md` 4.1-4.3; renamed by T80 / C1 and
  > on every main TOC since, TBC's included, right after `UI/Style.lua`): ... (the rest as today),
  > plus **T80:** `db.ui.fontOffset`'s default declared here (`MD:RegisterDefaults`);
  > `UI.SetFontOffset(n)` applies and saves the offset (both Settings panes).

  Drop "Forever TOCs only" and "On TBC none of it exists".
- The `UI/Windows_Forever.lua` row becomes `UI/Windows.lua`:
  > **The window manager `MD.Win`** (T32-T34, T40, T42, 0.16.2; T80 / C1: on every main TOC,
  > TBC's included, after `UI/EscStack.lua`)

  Keep the rest, but replace "A shared window calls it behind `if MD.Win`" with:
  > **T80 (C1, review A22):** it knows no dashboard -- the host registers with `sizes` (per group),
  > `group`, `open(group, view)`, `selected()` and `practicePath`, a takeover with `busy` (the
  > line `ShowMain` prints while practice plays); `Win.host`; `Win.SIZES` is the host's table
  > (for the suites); `adoptPlaced` adopts the place the client gave a user-placed window once;
  > `scale` / `combat` / `win` declared here; the ESC stack's calls delegated to
  > `UI/EscStack.lua`.
- A new row after it:
  > `UI/EscStack.lua` | **The ESC stack** (T33; moved out of the manager by T80 / C1, review A22;
  > every main TOC, before `UI/Windows.lua`): `MD.EscStack` -- `SpellTunerEscProxy`, the only
  > SpellTuner frame in `UISpecialFrames`; `Push` / `Remove` / `Prune` / `OnEsc` / `CloseLists` /
  > `TopWindow` / `On` / `Set(on, shown)` / `Line`; the `UI_POPUP` subscription;
  > `db.ui.escStack` declared here; the same calls on `MD.Win`
- The `Core_Forever.lua` row: append
  > **T80:** `ui` left `DEFAULTS` (the theme, the stack and the manager declare it)
- The `UI/Dashboard_Forever.lua` row: append
  > **T80 (C1):** the sizes per group are this file's (`SIZES`), handed to `MD.Win:Register` with
  > `open` / `selected` / `practicePath`; `MD:SelectView` builds the window first
- The `UI/Dashboard.lua` row: append
  > **T80 (C1, decision 10):** registered with the window manager as the host -- TBC's `SIZES`
  > (every group 1036 x 646, fixed), `adoptPlaced` (the place the client kept for the user-placed
  > window), `MD:OpenMainWindow`, every `MD:SelectView` / `ToggleDashboard` through
  > `MD.Win:ShowMain`; no `UISpecialFrames` entry; hidden in combat and reopened on the same view
- The `UI/OptionsFrame.lua` row (General's panes): append
  > **T80:** `UI/Options_General.lua`'s third column, Windows -- In combat, Close one window per
  > ESC, Text size, Window size, Reset window positions
- `UI/ReplayWindow.lua`, `UI/BindingsWindow.lua`, `UI/PracticePanel.lua` and `UI/DebugConsole.lua`
  rows: append
  > **T80 (C1):** the `MD.Win` branches are gone -- on TBC too the replay is a takeover (its
  > `db.replayPos` adopted), the bindings are the sheet (TBC's window is gone), the console a tool
  > on the ESC stack

  Remove "TBC keeps its window", "TBC keeps `HIGH` and its `UISpecialFrames` entry" and "TBC
  keeps `UISpecialFrames`".
- The `tools/` row:
  - `tools/wincheck.lua` is now listed for both flavours: "(forever, tbc: T80 -- the TBC window
    under the manager, 4)".
  - The TBC UI suites load the theme and the manager.
- The conventions line "Forever-only look gates on `UI.THEMED`" stays. `UI.THEMED` is now true on
  both lines wherever the TOC is loaded.

**docs/TOOLS.md** section 1: `wincheck` (forever, tbc). Add the sentence: "under tbc, the TBC
window registered with the manager: its sizes, a place kept before C1 adopted, one ESC, the
combat hide".

**docs/DECISIONS.md**, the entry the plan names:

> **TBC takes the Forever window** (2026-10-01, T80 / C1; U4's list, the author's answer 1 to
> decision 10). The TBC TOC lists the flat theme and the window manager, so `UI.THEMED` is true on
> TBC. Every look P27-P33 gated now applies there: the flat window and tooltips, Review's generic
> table with its row menu (Coach anyway, no Coach* or shift-click), and the replay's band.
> `/md`'s window is the manager's host:
> - TBC's own sizes per group (1036 x 646, fixed until C3);
> - a place the client kept for it adopted once, and the replay's `db.replayPos` likewise;
> - one ESC closes one window;
> - it hides in combat and comes back on the same view (Settings -> General -> Windows offers
>   "Keep them open");
> - the bindings are the sheet on Simulate -> Practice.
>
> The tests that pinned the unthemed TBC look were re-based on the themed one
> (`docs/tasks/T80-window-manager-and-theme-on-tbc.md` lists every value).

**docs/TESTING.md** section 44, after item 26 (or as its first half), TBC (C1):

> **TBC window (C1).**
> - `/md`: the window is flat, the size it was, and where you last dragged it (if it opens
>   centred, say so: the client's own saved place for it was not there to adopt).
> - Drag it, `/reload`: it stays.
> - Open the debug console from Settings -> General: one ESC closes the console, a second ESC
>   the window.
> - Pull a mob with the window open: it hides and comes back on the same view after the fight;
>   one chat line says why, once.
> - Settings -> General -> Windows: set Keep them open and pull again (it stays); set Window size
>   to 90 % (every SpellTuner window smaller); set Text size to +1; then Reset window positions.
> - Simulate -> Practice -> Edit bindings: a sheet on the pane, not a window. `/md binds` opens
>   the same sheet.
> - `/md replay 1`: it opens where the old replay window was.

**docs/HISTORY.md**: the integrator's wave entry.

## Deviations

1. **`tools/dashui.lua` gained a check (67 -> 68).** The plan names only re-baselines for the
   other TBC UI suites, but the new WINDOWS controls of `UI/Options_General.lua` needed a test, and
   `dashui` is the suite that builds TBC's Settings. `UI/Options_General.lua` exposes
   `pane.windowsPane` for it.
2. **`MD:SelectView` on Forever builds the window first.** `MD.Win:ShowMain` used to call
   `MD:OpenMainWindow`, which built the window lazily. The manager now only knows the host once it
   has registered, so the dashboard's `MD:SelectView` calls `CreateDashboard()` before
   `ShowMain`. `UI/BindingsWindow.lua`'s sheet opens Simulate -> Practice through `MD:SelectView`
   for the same reason, where it called `MD.Win:ShowMain` directly. Nothing changes for the
   player.
3. **The practice-refused line moved to the replay window** (`busy` in its spec) together with the
   practice path (the host's `practicePath`). This is A22's "practice rule" leaving the manager.
   The text is unchanged and `wincheck/forever`'s check of it still passes.
4. **Two `replayui/tbc` checks run under "Keep them open".** These are B22's
   combat-at-a-boundary check and T72's keyboard check. On TBC the manager now hides a review
   replay in combat (decision 4), so a replay that is still on screen in combat exists only under
   `db.ui.combat = "keep"`. That is where those rules apply, and the checks set it and restore
   `hide`.
   - Under the default `hide`, a replay shown again after the fight under a pointer that never
     left takes the keyboard again: the pointer is over a window that just appeared. This keeps
     answer 12 ("only while the pointer is over the replay, never in combat").
   - A stricter rule ("only after the pointer enters again") was tried and dropped, as a change
     the plan does not ask for.
5. **The import fixture is unchanged.** `Core_Forever.lua`'s `DEFAULTS` no longer carries `ui`,
   but the three files register the same five keys with the same values, so a Forever database
   is the same. `tools/data/import-forever-sv.lua`, rebuilt in the scratch copy, is byte for byte
   the committed file, and `importcheck` (21) passes.
6. **The TBC sizes are today's 1036 x 646 for every group, all fixed** (no grip). M6 notes the
   Spells group at 860 x 560, but that is C3's view. C1 keeps every TBC pane at the size it was
   laid out for.
7. **The dashboard's old place.** The client's layout cache restored a user-placed frame. Whether
   it did so for a window built at `MD_READY` is not verified (TESTING asks). The adoption reads
   whatever single point the frame holds at `Register`, and skips the kit's untouched centre.
