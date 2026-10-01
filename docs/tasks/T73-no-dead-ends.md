# T73 -- No dead ends (plan P29)

Status: **built** 2026-10-01 on branch `plan/P29` (base `e00fd63`), wave 12 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator. No file was added, so no TOC line is needed.

## The task (docs/PLAN-refactor-ux.md section 5, P29)

Review items (`docs/review/2026-09-30-project-review.md`): **U11** (module placeholders that say
"Settings -> Modules" in plain text, modules that "unload at your next /reload" with no Reload button,
the window vanishing at the pull with no word), **U19** (`/st dump` buries the errors under ~60
capability lines), **A24** (the Forever host swaps placeholders by reaching into `nav.panes` /
`nav.group`, twice, copy-pasted) and **U24**'s TBC half (the label "Danger below (%)" presents the
built-fight fallback as the scoring line). Approved mockup: M1's placeholder frame and its Modules row
in `docs/mockups/refactor-ux.html` (section 7.1). The author's answer 8.1 item 6: **"Turn on" switches
the module on** (Settings -> Modules stays the way off).

Owned files (section 4, wave 12): `UI/Style.lua`, `UI/Dashboard_Forever.lua`,
`UI/Windows_Forever.lua`, `UI/Dump_Forever.lua`, `UI/Options_General.lua`, `tools/navui.lua`,
`tools/reviewforever.lua`, `tools/practiceforever.lua`, `tools/consolecheck.lua`, `tools/dashui.lua`,
`tools/wincheck.lua`. All eleven were edited, plus `tools/defaultscheck.lua` (one lookup line, see
Deviations) and this task file.

## What was built

### `nav:ReplacePane(group, view, pane)` (UI/Style.lua, A24)

A real API on `UI.CreateNavFrame`'s nav instead of callers writing `nav.panes`: it stores the pane in
the view's place and hides the old one; if that view is the one on screen it re-selects it (the new
pane shown, `onShow` run, so it refreshes), otherwise it keeps the new pane hidden until the view is
next selected. It returns the old pane. Additive: no TBC file calls it, so TBC's nav is unchanged.

The old copy-pasted swap left the new pane **shown** when its view was not on screen (a frame is
created shown); e.g. switching Practice on from Reports built the Practice pane over Review.
`ReplacePane` hides it.

### The placeholders (UI/Dashboard_Forever.lua, U11, A24, mockup M1)

- One `MODULE_VIEWS` table: Reports -> Review (Replay, `CreateReview`) and Simulate -> Practice
  (Practice, `CreatePractice`), each with its builder, the flag the suites find the placeholder by
  (`reviewPlaceholder` / `practicePlaceholder`) and M1's words. `onCreate` builds the real pane when
  the module's `DashboardParts` constructor exists, else the placeholder (`BuildModuleView`).
- The placeholder is M1's block, centred: the view's name in the accent (`REVIEW` / `PRACTICE`), the
  heading (`Review needs the Replay module`, `Practice needs the Practice module`, `UI.FONT_HEAD`), one
  sentence in `text2` saying what the module does and what it brings with it, a **Turn on** button
  (accent, 110 x 22) and a footnote in `muted`: "Loads now, no reload. To turn it off again: Settings ->
  Modules." After a failed load the footnote reads `could not load: <REASON>. Settings -> Modules shows
  each module.` in `bad` (refreshed on every showing too).
- **Turn on** calls `MD:SetModule(module, true)`: the module and everything it needs are switched on
  and loaded now (the author's answer 6). The swap is one `MODULE_LOADED` callback,
  `SwapPlaceholders`: every placeholder whose constructor now exists is replaced through
  `nav:ReplacePane` (loading Practice loads Replay first, so Review's placeholder is replaced on the
  way, hidden if it is not on screen). The two hand-copied `MODULE_LOADED` swaps are gone.
- **Reload UI** (M1: on the Modules row, not on the placeholder -- a placeholder only shows while the
  module is not loaded, where a reload does nothing): each row of Settings -> Modules carries an
  84 x 18 button right of its state line, shown only while `MD:ModuleState` is `unloads` (switched off,
  still loaded this session). Its click is `MD.API.Call("ReloadUI")`. The row's state text is
  `MD:ModuleStateText` (Core.lua); this file's own copy is gone.

### The combat line (UI/Windows_Forever.lua, U11)

`Win:EnterCombat`, after hiding what the fight hides: the first time anything was hidden it prints
`Win.COMBAT_NOTE` once -- "the window hides in combat and comes back after. Settings -> General ->
Windows." (M1's chat line) -- and sets `db.ui.combatNoted`, so it is said once ever, not per session or
per pull. A fight under `keep`, or with nothing shown, says nothing and does not use it up.

### `/st dump` (UI/Dump_Forever.lua, U19)

Order: `== client` (client, build, character), `== saved variables`, `== modules`, `== errors (...)`
with `error handler: ...` as its first line, then **one capabilities summary** -- `== capabilities (N
bindings, M absent)`, `absent: <client names>` (or `none`), `forbidden events: ...` -- then
`== capability table (N)` with every binding, and `== debug log (...)` last.

### TBC: the danger label (UI/Options_General.lua, U24)

`"Danger below (%)"` is `"Danger line for built fights (%)"`; the tooltip was "Seconds a tracked target
spends below this are what a plan / is scored on first, ahead of mana." and is now "Fights built in
Simulate score seconds a target spends below / this first, ahead of mana. A recorded fight measures its
own line: / the biggest hit each target took." (`db.simFloor` is the line for synthetic scenarios and a
recorded target's fallback since v0.10.3; the plan decides on the biggest hit so far since T20.) The
only TBC change in this task.

## Tests first

The assertions were written against the parent's five shipped files (`e00fd63`), in a copy of the
tree with those five put back (`git show e00fd63:<file>`):

```
tools/navui.lua (tbc)            35 ok, 1 failed
  FAIL ReplacePane swaps a view's pane on and off screen
tools/dashui.lua (tbc)           64 ok, 1 failed
  FAIL the danger slider names built fights, truly
tools/reviewforever.lua          exit 1 (stops: nothing loads the module)
  with the Replay module off the Review view says how to switch it on and loads nothing  FAIL
  switching the Replay module on replaces the placeholder with the Review tab            FAIL
  Turn on loads Replay and Recorder, and the swap goes through nav:ReplacePane           FAIL -
tools/practiceforever.lua        exit 1 (stops: nothing loads the module)
  the Simulate group has a Practice view, a placeholder until the module is on           FAIL
  T73: Turn on loads Practice with what it needs, swapped in through nav:ReplacePane     FAIL - replaced=
  /st practice and /st binds exist only with the Practice module on                      FAIL
tools/wincheck.lua               61 ok, 1 failed
  T73: the first combat hide prints one line, once  FAIL - keep=0 closed=0 total=0
tools/consolecheck.lua (forever) 19 ok, 1 failed
  /st dump shows one block with every section, in order  FAIL
tools/defaultscheck.lua (tbc)    45 ok, 3 failed (the slider looked up by its new label)
```

After: every one passes (counts below).

## Suites

| suite | before | after |
|---|---|---|
| `navui/tbc` | 35 | 36 (+1: `ReplacePane` on and off screen, nothing rebuilt) |
| `dashui/tbc` | 64 | 65 (+1: the label and its tooltip) |
| `reviewforever/forever` | 18 | 20 (+2: Turn on loads Replay and Recorder through `ReplacePane`; Reload UI on a module that unloads, and it reloads; two changed: the placeholder's words and button, the swap by the button) |
| `practiceforever/forever` | 28 | 29 (+1: Turn on loads Practice through `ReplacePane`; one changed: the placeholder's words and button) |
| `wincheck/forever` | 61 | 62 (+1: the combat line once, nothing under keep or with nothing shown) |
| `consolecheck/forever` | 20 | 20 (the dump-order assertion changed to the new order) |
| `defaultscheck/tbc` | 48 | 48 (the lookup follows the label) |
| every other suite | as `tools/data/expected-counts.json` | equal |

`make check`: 68 runs, all passed (the five notes are the counts above); `apicheck` 0 findings (57
files, 47 distinct globals: `ReloadUI` goes through `MD.API.Call`); `textcheck` 0 findings; `luac -p` on
the five shipped files.

TBC byte-identity (principle 2): `practiceui` and `simwindow` print the same lines before and after;
`reviewui` the same apart from the time-sliced search's evaluation count and the `ms` timings;
`navui` and `dashui` the same plus their one new line each; `defaultscheck/tbc` the same.

## Integrator lines

- **TOCs**: none (no new file).
- **`tools/data/expected-counts.json`**:
  `"dashui/tbc": 65,` (was 64), `"navui/tbc": 36,` (was 35), `"practiceforever/forever": 29,` (was 28),
  `"reviewforever/forever": 20,` (was 18), `"wincheck/forever": 62,` (was 61).
- **`docs/TOOLS.md`** section 1: the same five counts.
- **`docs/DECISIONS.md`** (the one TBC text change, and the answer it carries out):

  > ### No dead ends (T73, P29, 2026-10-01)
  > A placeholder's **Turn on** switches its module on, with what it needs, and loads it at once (the
  > author's answer 6 to `docs/PLAN-refactor-ux.md` section 8): the T16b rule "a placeholder never
  > loads a module" is retired; Settings -> Modules stays the way to switch one off, and a module
  > switched off but still loaded gets a Reload UI button there. On TBC the Options slider for
  > `db.simFloor` reads "Danger line for built fights (%)": since v0.10.3 a recorded fight measures its
  > own line and since T20 a plan decides on the biggest hit so far, so the flat line is what a fight
  > built in Simulate is scored on (and a recorded target's fallback); the old label and tooltip called
  > it the scoring line. A text fix; the value and its use are unchanged.

- **`CLAUDE.md`**, appended to rows:
  - `UI/Style.lua`: **T73 (P29):** `nav:ReplacePane(group, view, pane)` -- a view's pane replaced
    (the old hidden; re-selected when on screen, else kept hidden), returning the old one; the Forever
    host's module placeholders go through it.
  - `UI/Dashboard_Forever.lua`: **T73 (P29):** one `MODULE_VIEWS` table (Review / Replay, Practice /
    Practice): a placeholder (M1: the name, a sentence, **Turn on** -- `MD:SetModule(name, true)`, which
    loads it now --, the footnote or the failed load's reason) swapped for the real pane through
    `nav:ReplacePane` on `MODULE_LOADED`; Settings -> Modules shows **Reload UI** on a module that
    unloads at the next reload (`MD.API.Call("ReloadUI")`), its state words `MD:ModuleStateText`.
  - `UI/Windows_Forever.lua`: **T73 (P29):** the first combat hide prints one line
    (`Win.COMBAT_NOTE`), once ever (`db.ui.combatNoted`).
  - `UI/Dump_Forever.lua`: **T73 (P29):** client, saved variables, modules, errors (the handler line
    first), one capabilities summary (counts, `absent:`, forbidden events), then the capability table
    and the debug log.
  - `UI/OptionsFrame.lua` (the row that names `UI/Options_General.lua`): **T73 (P29):** the
    `db.simFloor` slider reads "Danger line for built fights (%)", its tooltip naming Simulate and the
    measured line of a recorded fight.
- **`Core_Forever.lua`** (optional, not needed for behaviour): `combatNoted` may be listed in
  `DEFAULTS.ui` as `false` for documentation; `nil` reads the same.
- **`docs/TESTING.md`** section 44, check 21 (the plan's) and check 19:

  > 19. `/st dump`: the errors come right after the modules, before `== capabilities`; one summary
  > (`absent:` and `forbidden events:`) then the whole table, the debug log last.
  > 21. **Placeholders (P29).** On a fresh install (every module off), Reports: the Review placeholder
  > (`Review needs the Replay module`, a sentence, **Turn on**). Click Turn on: chat says Recorder and
  > Replay loaded, the Review list replaces the placeholder at once (no reload). Simulate -> Practice:
  > the same, Turn on loads Practice. Settings -> Modules: untick Replay -- its row reads `off - unloads
  > at your next /reload` with a **Reload UI** button; click it: the interface reloads and Review shows
  > the placeholder again. Pull a mob with the window open (Windows: hide): one chat line says the
  > window hides in combat and where to change it; the next pull says nothing. **TBC:** `/md options`
  > -> General: the slider reads `Danger line for built fights (%)`, its hover names Simulate.

## Deviations

- **`tools/defaultscheck.lua` edited (not in the wave table).** Its section 5 finds the TBC Options
  slider by its label, `sliders["Danger below (%)"]`, so the label the plan asks for turned three of its
  assertions red. The one lookup line now names `"Danger line for built fights (%)"`; no assertion
  added or removed (48). Wave 12 has P29 alone, so no other task owns the file.
- **`ReloadUI` through `MD.API.Call("ReloadUI")`**, not a named binding: `Client/API.lua` is not this
  task's file. A later task touching it may add `ReloadUI = "ReloadUI"` to the shared `Bind` and call
  `MD.API.ReloadUI()` here.
- **The combat line is once ever**, not once per session: the review asks for "a one-time chat line",
  and the mockup labels it "the first time the window hides for combat". `db.ui.combatNoted` holds it.
- **Practice's sentence** is not in the mockup (M1 draws only Review's and names Practice's heading):
  "Practice plays a fight you heal in real time, then reviews it like a real pull. It needs Replay and
  Recorder, which turn on with it." -- invented wording, adjustable in game (section 7.1).
