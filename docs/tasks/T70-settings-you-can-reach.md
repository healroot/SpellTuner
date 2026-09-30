# T70 -- Settings you can reach (plan P26)

Status: **built** 2026-09-30 on branch `plan/P26` (base `cf9c6ae`), wave 11 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator. No file was added, so no TOC line is needed.

## The task (docs/PLAN-refactor-ux.md section 5, P26)

Review items (`docs/review/2026-09-30-project-review.md`): **U18** (the Forever clock cannot be placed
at full mana: shown only in combat or under 90 %, lock only through `/st clock lock`, no reset, no
preview, no click action), **U24** (Forever part: `replayAutoCoach`, `replayNextPull`, `replayTicks`,
`simAllowRebinds`, `simFullHp` read with no control; console, dump and measure slash-only; no
About / command list), **U15** (two size knobs named by mechanism, not effect).

- Settings -> General in two columns. A **MANA CLOCK** pane: show, lock (unticking shows the clock for
  60 s, as TBC does), reset position, and a left-click on the clock opens the window. A **REVIEW**
  pane: auto-coach on open, next pull follows, snapshot ticks, let Coach change ranks, full-health %.
  A **TOOLS** pane: debug console, copy `/st dump`, measure on/off. An **About** view listing
  `MD:Commands()`. The APPEARANCE knobs named by effect ("Text size", "Window size") with one sentence
  each. Forever-only files.
- Mockup **M1** (`docs/mockups/refactor-ux.html`, approved 2026-09-30): left SPELL TOOLTIPS,
  APPEARANCE, WINDOWS; right MANA CLOCK (Show, Lock in place, Reset position, **Show now** -- the
  page's choice: the same 60 s preview as unticking Lock), REVIEW (a note "needs the Replay module"),
  TOOLS; About with the usages in the numbers font.
- Tests: `wincheck` +5 (each new control writes and applies its key; Reset clears the clock position);
  `clockcheck` +2 (unticking Lock shows a full-mana clock for 60 s and hides it after; a left-click
  calls `MD:ToggleDashboard`).
- TBC: no.

Owned files (section 4, wave 11): `UI/Dashboard_Forever.lua`, `UI/Clock_Forever.lua`,
`tools/wincheck.lua`, `tools/clockcheck.lua`. All four were edited, plus this task file.

## What was built

### Settings -> General (UI/Dashboard_Forever.lua)

Two columns at M1's geometry: the left column 352 wide at x 4, the right one from x 376 to the pane's
right edge. `Section(pane, text, height, above, column)` hangs each titled pane from the column's top
or from the pane above it (Cell's 12 px apart, first control at -27, as T42).

| column | pane | controls (db key) |
|---|---|---|
| left | SPELL TOOLTIPS | unchanged (T37 / T42) |
| left | APPEARANCE | **Text size** (was "Font offset"; `db.ui.fontOffset`, -2..+2) and **Window size** (was "Window scale"; `db.ui.scale`, 70-120 %), each with a grey sentence under it: "Every SpellTuner text, one size bigger or smaller." / "Every SpellTuner window, bigger or smaller." The clock check moved to MANA CLOCK. |
| left | WINDOWS | unchanged (T42) |
| right | MANA CLOCK | Show the mana clock (`db.clock.shown`); Lock in place (`db.clock.locked`, through `MD.Clock:SetLocked`: unticked previews 60 s); the hint "Unlocked: the clock stays up for 60 s, even at full mana, so you can drag it."; **Reset position** (`MD.Clock:ResetPosition`, `db.clock.point` cleared, back at TOP -120); **Show now** (`MD.Clock:Preview`, disabled while the clock is off); "Left-click the clock to open this window." |
| right | REVIEW | Coach a fight when it opens (`replayAutoCoach`), Next pull follows (`replayNextPull`), Snapshot ticks on the bars (`replayTicks`), Let Coach change ranks (`simAllowRebinds`), the slider Full health is above (`simFullHp`, 70-99 %). The tooltips are TBC's words for the same keys. The title carries "needs the Replay module" on the right. |
| right | TOOLS | Debug console (`MD:ToggleDebugConsole`), Copy /st dump (`MD:ShowCopyPopup("SpellTuner dump", MD:BuildDump())`, what `/st dump` does), Measure: off / on (`MD.Measure:Toggle`, the label follows `MD.Measure.on`); the hint "Measure checks each cast that lands against its own text." |

**REVIEW is live only while the Replay module is loaded.** Its five keys are the module's
(`Engine/SimModel.lua` registers their defaults through `MD:RegisterDefaults`), so with Replay not
loaded `MD:Setting` has nothing to show. Rather than declare the defaults a second time here (P20's
rule: defaults declared once), the four checks and the slider are **disabled** and the note reads
"needs the Replay module - off"; `MODULE_LOADED` refreshes the pane, so switching Replay on makes it
live at once. Each control writes `MD.db[key]` (the slider `value / 100`), which is what the readers
ask (`MD:Setting` / `MD.db` directly).

### Settings -> About (UI/Dashboard_Forever.lua)

A third Settings view, `about`. "SpellTuner <MD.version>", the client line ("WoW: Forever, build N",
the build from `MD.API.BuildInfo()`; the client is named, not read from `MD.API.client`, which
apicheck's rule 10 keeps inside `Client/` -- the file is on the Forever TOCs only), one sentence, and a titled COMMANDS pane ("/st and /md both answer" on
the right of its title) with one row per `MD:Commands()` entry that is not hidden: the usage in
`UI.FONT_NUM` (Arial Narrow, the theme's; `UI.FONT` without it) in a 196-px column, the text in
`text2` cut at its first "; " -- the whole text on the row's hover when it was cut (`/st measure`,
`/st tooltip`). A module that is not loaded is one muted row ("Replay  off: its commands are listed
here once it is on (Settings -> Modules)"), because its commands are registered only when it loads.
The rows are rebuilt on every show and on `MODULE_LOADED` (18 rows with every module on).

### The clock (UI/Clock_Forever.lua)

- `Clock.PREVIEW_SECONDS = 60`; `Clock:Preview([seconds])` sets a `GetTime()` deadline; the one
  visibility owner passes "previewing" as `MD.Visibility.Want`'s `unlocked` argument, so the clock is
  up at any mana level while it lasts and the 90/95 rule takes over after (the next tick hides a
  full-mana clock). Off (`db.clock.shown` false) stays off. While previewing the text reads
  "SpellTuner - drag me" in the accent (TBC's words), plain ASCII; afterwards the projection again.
- `Clock:SetLocked(locked)`: writes `db.clock.locked`; unlocking previews, locking ends the preview.
  `Clock:Previewing()`; `Clock:ResetPosition()`.
- Dragging: while unlocked, and during a preview (TBC's rule: `not locked or GetTime() < forceUntil`).
- **A left-click opens the window**: `OnMouseDown` clears a `dragged` flag, `OnDragStart` sets it,
  `OnMouseUp` with the left button and no drag calls `MD:ToggleDashboard()` -- whatever order the
  client fires `OnDragStop` and `OnMouseUp` in. **Not in combat** (see Deviations). The hover gains
  "Left-click (out of combat): open the SpellTuner window".

## Tests first

Both suites were written against the new behaviour, committed, then run with the two UI files checked
out from the parent (`git checkout cf9c6ae -- UI/Dashboard_Forever.lua UI/Clock_Forever.lua`):

```
wincheck/forever on the parent:  55 ok, 6 failed
  T70: with Replay not loaded, REVIEW is shown disabled and says so; About lists Replay as off  FAIL
  T70: General in two columns (tooltips, appearance, windows | clock, review, tools); Text size, Window size  FAIL
  T70: MANA CLOCK   FAIL - raised: ... attempt to index ... (no clock pane)
  T70: REVIEW's four checks and 'Full health is above' write their keys once Replay is loaded  FAIL
  T70: TOOLS        FAIL - raised: ... (no measure button)
  T70: About lists every visible command (the modules' too), ...  FAIL - rows=0 want=18
clockcheck/forever on the parent: 24 ok, 2 failed
  unticking Lock shows the clock at full mana for 60 s, then it hides  FAIL - lock=false ... word0="~FULL"
  a left-click on the clock calls MD:ToggleDashboard; a drag, a right-click or combat does not  FAIL - calls=0
```

A block that raises on the parent is caught (`Guarded`) and reported as one FAIL, so the suite still
reaches its footer. On this branch: wincheck 61 ok, clockcheck 26 ok.

The new assertions:

- `wincheck` section 12 (before the Replay module loads): REVIEW's four checks and the slider are
  disabled, its note says "- off", About has the "Replay  off: ..." row and no `/st replay` row.
- `wincheck` section 14: the six panes in their columns (each titled pane's anchor chain ends on the
  General pane at x 4 or 376) and the sliders labelled Text size / Window size with their sentences;
  MANA CLOCK (Show off hides the clock and disables Show now, Lock writes `db.clock.locked`, Show now
  previews, **Reset position clears `db.clock.point` and puts the clock at TOP -120**, unticking Lock
  previews and 61 s later the preview is over); REVIEW (the four keys written true and false, the
  slider 90 -> 0.9, 120 clamped to 0.99, live and noted as such once Replay loaded); TOOLS (the console
  shown, the copy box holding the dump, measure on then off with its label); About (every visible
  `MD:Commands()` usage has its row, `/st replay` among them, no "off" row, `/st measure`'s text cut at
  "; " with the whole text in the hover, the version and client line).
- `clockcheck`: at full mana out of combat the clock is hidden; unticking Settings -> General's Lock
  shows it with "SpellTuner - drag me", still at 59 s, hidden after 60.5 s with the projection back;
  a click calls `MD:ToggleDashboard` once, a drag, a right-click and a click in combat do not, and the
  hover names the click.

The plan asked for `wincheck` +5; this is +6 (the "Replay off" state is its own assertion, since it
has to run before section 12 loads the module).

## Suites (`make check` = `tools/check.sh`, exit codes and footers checked)

Before: `cf9c6ae`, 68 runs, all passed (63 counted). After: this branch, 68 runs; every suite passes and
the counter reports only the two counts below as different from `expected-counts.json` (the
integrator's file, not edited here):

| suite | before | after |
|---|---|---|
| `wincheck/forever` | 55 | **61** |
| `clockcheck/forever` | 24 | **26** |
| `tipcheck/forever` (finds `tooltipCheck` / `detailDropdown` on the General pane) | 38 | 38 |
| `modulecheck/forever`, `navui/tbc`, `reviewforever/forever`, `practiceforever/forever`, `consolecheck`, `themecheck`, `spellsui/forever`, `dashui/tbc` | as expected | same |
| `apicheck` | 0 findings | 0 findings (no new global) |
| `textcheck` | 0 findings | 0 findings |

`make check`'s last run: "check: 68 run(s), all passed", the only notes the two counts above. (A first
run caught one apicheck finding -- About read `MD.API.client` to name the client -- fixed in the second
commit by naming it, since the file is Forever-only.)

`luac -p UI/Dashboard_Forever.lua UI/Clock_Forever.lua`: clean.

## TBC

No change. Both UI files are on the Forever TOCs only; the TBC suites (`dashui`, `navui`, `reviewui`,
`replayui`, `practiceui`, ...) keep their counts.

## Integrator lines

**TOCs**: none (no file added or moved).

**tools/data/expected-counts.json**: `"clockcheck/forever": 26`, `"wincheck/forever": 61`.

**CLAUDE.md**, the files table:

- `UI/Dashboard_Forever.lua` row, append: ` **T70 (P26, review U18, U24, U15, mockup M1):** Settings -> General in two columns -- left SPELL TOOLTIPS, APPEARANCE ("Text size", "Window size", a sentence each), WINDOWS; right MANA CLOCK (show, Lock in place -- unticking previews the clock 60 s --, Reset position, Show now), REVIEW (`replayAutoCoach`, `replayNextPull`, `replayTicks`, `simAllowRebinds`, `simFullHp`; live only while the Replay module is loaded, which registers them) and TOOLS (debug console, copy /st dump, measure on/off); **Settings -> About**: the version, the client and every `MD:Commands()` usage, a module not loaded one line`
- `UI/Clock_Forever.lua` row, append: ` **T70 (P26, review U18):** `MD.Clock:Preview([s])` (60 s up at any mana level, draggable, "SpellTuner - drag me"), `SetLocked` (unlocking previews), `ResetPosition`; a left-click out of combat opens the window (a drag is not a click)`

**docs/TOOLS.md** section 1:

- `wincheck.lua` row, append: ` Since **T70** (61): Settings -> General's two columns, MANA CLOCK / REVIEW / TOOLS writing their keys (REVIEW disabled until the Replay module loads), Reset position clearing the clock's point, and Settings -> About listing every visible command`
- `clockcheck.lua` row, append: ` Since **T70** (26): unticking Lock previews the clock at full mana for 60 s; a left-click opens the window, a drag, a right-click or combat does not`

**docs/TESTING.md** section 44: the plan's section 9 item 20 as written ("Settings -> General: move the
clock at full mana with Lock unticked (it shows for 60 s), Reset it; click the clock: the window
opens."), plus: "Settings -> About lists the commands; with Replay off, REVIEW is greyed and says so."

**docs/DECISIONS.md**: one line, if the integrator wants it recorded -- "Forever clock (T70): a
left-click opens the window only out of combat; in combat the click does nothing, because the window
hides in combat (decision 4)." No TBC behaviour changed.

**docs/HISTORY.md**: the wave-11 entry names T70 with the counts above.

## Deviations

1. **The click opens the window out of combat only.** The plan says "a left-click on the clock opens
   the window". The clock is up in every fight and takes the mouse, and the window hides in combat
   (decision 4, `db.ui.combat = "hide"`); a stray click mid-fight would have put the window over the
   party. The hover says "(out of combat)". TBC's widget has no such guard (it opens on a click while
   locked); TBC is unchanged.
2. **REVIEW is disabled while the Replay module is not loaded**, instead of showing a default. The
   keys' defaults are the module's (`MD:RegisterDefaults` in `Engine/SimModel.lua`); showing a value
   without it would mean declaring them a second time (P20). The mockup's note "needs the Replay
   module" is kept and gains "- off" in that state.
3. **The tooltips are not scaled with the window** (U15's second half). P26's "What" names only the
   labels and sentences; `UI.tooltip` belongs to `UI/Style.lua` and the scale to
   `UI/Windows_Forever.lua`, neither of them this task's. So the Window size sentence says "Every
   SpellTuner window, bigger or smaller." and its hover lists the windows, not "and the tooltips in
   it" as M1 drew it. Left for a kit task (P31 / P32).
4. **About does not group the module commands under "WITH THE MODULES"** with a module column as M1
   drew them: `MD:Commands()` does not record which addon registered a command, and a module that is
   not loaded has registered nothing, so a greyed list of its commands would have to be typed in here.
   One list in registration order (the core's, then each module's as it loaded), and one muted row per
   module that is off.
5. **`wincheck` +6, not +5** (the "Replay off" assertion; see Tests first).
6. **`/st clock lock`** (`Core_Forever.lua`, not this task's) still toggles `db.clock.locked` without the
   preview; the Settings checkbox previews. Pointing the command at `MD.Clock:SetLocked` is a one-line
   follow-up for whoever next owns `Core_Forever.lua`.
7. **The minimap button** that M1 draws under WINDOWS is P36's (wave 17), not built here.
