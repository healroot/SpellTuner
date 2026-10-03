# T119 -- One UI, W7: Settings in two columns on both lines, one About, TBC's Settings at 860 x 560

Status: **ready** 2026-10-03, the One UI round (`docs/SPEC-one-ui.md`, version 0.17.0; mockup
`docs/mockups/one-ui.html`). **Wave B, beside T118.** Starts on T117's integrated commit. It
reads no file T117 or T118 writes; it is in wave B because it is independent of the Spells work.

## The task (docs/SPEC-one-ui.md 7, 10 W7; mockup M6, both panels and its caption)

> **W7, Settings.** The views, the two columns, TBC's sizes, About.

TBC's Settings is one `General` page of four 205-px columns in a 1036 x 646 window, built by
`UI/Options_General.lua` into `MD.optionsFrame` (a frame adopted into the dashboard), with an
About tab whose blurb predates the Forever line. Forever's is two columns at 860 x 560
(`UI/Dashboard_Forever.lua`'s `Build*Section` functions), with a REVIEW pane inside General.

After this task both lines build Settings with **one file**, `UI/Settings.lua`: the same views,
the same two columns, the same pane titles and the same About page. What differs is a table each
line installs (`MD.SettingsLine`), never a branch on the client (apicheck rule 10).

Owned files (the only files edited, apart from this one):

- `UI/Settings.lua` (new; both main TOCs)
- `UI/Options_General.lua` -> `UI/Settings_TBC.lua` (`git mv`, then rewritten as TBC's line table)
- `UI/Options_About.lua` (deleted)
- `UI/OptionsFrame.lua` (deleted)
- `UI/Dashboard.lua` (the Settings group, its size, `MD:ShowOptionsFrame`; nothing in the Spells
  group -- that is T120's)
- `UI/Dashboard_Forever.lua` (its Settings sections move to `UI/Settings.lua`; Forever's line
  table; the Review view; nothing in the Spells group)
- `SpellTuner_TBC.toc`: **three lines**: `UI\OptionsFrame.lua` -> `UI\Settings.lua`,
  `UI\Options_General.lua` -> `UI\Settings_TBC.lua`, `UI\Options_About.lua` removed
- `SpellTuner_Mainline.toc`, `SpellTuner.toc`: **one line each**, `UI\Settings.lua` right before
  `UI\Dashboard_Forever.lua`
- `tools/settingscheck.lua` (new, forever / tbc)
- `tools/wincheck.lua`, `tools/clocksettings.lua`, `tools/minimapcheck.lua`,
  `tools/slashcheck.lua`, `tools/defaultscheck.lua`, `tools/dashui.lua` (its Settings checks
  only), `tools/restylecheck.lua` (the Settings views list only), `tools/reviewforever.lua` and
  `tools/modulecheck.lua` (only if they name a moved control)

T118 (the same wave) edits `SpellTuner_TBC.toc`'s `Spells\Families_TBC.lua` line, far from these
three: the edits merge cleanly.

## What to build

### The views (spec 7, M6)

| Line | Settings views, in order |
|---|---|
| TBC | General, Clock, Review, About |
| Forever | General, Clock, Review, Modules, About |

**Review** is new on both lines: it takes the recording and model panes out of General.

### Sizes

- **TBC's Settings group: 860 x 560, fixed** (`UI/Dashboard.lua`'s `SIZES.settings = { w = 860,
  h = 560, minW = 860, minH = 560 }`), as Forever's.
- **TBC's Spells group stays 1036 x 646 in this task.** Its pane (`UI/SpellsView_TBC.lua`) is
  laid out for 912 px; T120 replaces it with the shared pane and moves the group to 860 x 560 in
  the same commit (Lead's correction: the spec moved both sizes in W7, which would squeeze the
  old pane for one wave).
- Reports and Simulate unchanged on both lines.

### `UI/Settings.lua` (`MD.Settings`, both main TOCs)

The builder. Forever's `Section`, `Hint`, `LEFT_W` (352), `RIGHT_X` (376), `PANE_GAP` (12) and its
`Build*Section` functions move here from `UI/Dashboard_Forever.lua`, generalised to read rows from
`MD.SettingsLine`. Reads `MD.db` through `MD:Setting` where a key may be unregistered on a line.

**Rows are data.** A line hands lists of rows; the builder draws them in order:

```lua
{ kind = "check",  text, key = "locked" | get = fn, set = fn, tips = { title, line, line },
  live = fn }                              -- live() false: drawn disabled (a module's key)
{ kind = "slider", text, key | get / set, min, max, step, scale = 100, tips }
{ kind = "dropdown", text, items = fn | list, get, set, width }
{ kind = "buttons", { text, onClick, tips, label = fn }, ... }   -- one row, left to right
{ kind = "hint",   text }                  -- a muted sentence
```

**`MS.Build(view, content)`** returns the pane for `general`, `review` or `about`, and
**`MS.Refresh(view)`** re-reads every control (the old `RefreshGeneralPane` /
`RefreshAboutPane`), called by each dashboard's `onShow`.

**General** (both lines; the order of the mockup's two columns):

- Left: **SPELL TOOLTIPS** -- `Add SpellTuner lines to heal tooltips` (`spellTooltip`),
  `...and to damage spells` (`spellTooltipDamage`), `Detail lines` (the dropdown over
  `MD.SpellTip.DETAIL_MODES`, writing `spellTooltipDetail`; drawn only when `MD.SpellTip` has
  `DETAIL_MODES`, so on TBC it appears with T121's shared block and not before). Both lines show
  both checks: `spellTooltipDamage` becomes the block's damage half on both (spec 6; T121 makes
  Forever's block read it -- until then the second check on Forever writes a key nothing reads,
  and its tooltip says "damage spells" only). **APPEARANCE** -- Forever's section as it is
  (`MD.ClockSettings.LookControls`, Text size, Window size, the two sentences). **WINDOWS** --
  Forever's section (In combat, Close one window per ESC, Minimap button, Reset window positions).
- Right: **MANA CLOCK** -- the line's rows (`SettingsLine.clock`). **ALERTS** -- the line's rows
  (`SettingsLine.alerts`), the pane drawn only when the line has some. **TOOLS** -- the line's
  rows (`SettingsLine.tools`). **INTEGRATIONS** -- under TOOLS, `MD.ClockSettings.BuildIntegrations`
  with the line's extra switches (`SettingsLine.integrations`; Forever's EllesmereUI mover).

**Review** (both lines):

- Left: **RECORDING** -- `SettingsLine.recording`, with the line's note on the title row
  (`SettingsLine.recordingNote`: Forever `needs the Replay module` / `... - off`).
- Right: **MODEL** -- `SettingsLine.model`, then `SettingsLine.modelHint` (a muted sentence).

**About** (both lines, Forever's page): the version (`SpellTuner <version>`), the client line
(`SettingsLine.client()`), the blurb **"Your spells rank by rank, your mana clock, and your fights
recorded, replayed and coached."** (TBC's stale blurb goes, spec 7), COMMANDS from
`MD:Commands()` (usage, the text cut at its first `"; "`, the whole on hover; `/st and /md both
answer`), one line per module not loaded (`MD.modules`, absent on TBC), and the line's optional
`SettingsLine.aboutNote = { title, text }` under COMMANDS (TBC: `BEFORE TRUSTING THE NUMBERS`,
today's three steps, words unchanged).

**The marks the suites read stay on the panes** (`pane.tooltipCheck`, `pane.detailDropdown`,
`pane.about`, `pane.integrations`, `pane.consoleButton`, `pane.dumpButton`, `pane.measureButton`,
`pane.reviewChecks`, `pane.fullHpSlider`, `pane.reviewNote`), so `tipcheck/forever` and the
others find their controls. `pane.reviewChecks` / `fullHpSlider` / `reviewNote` / `measureButton`
are on the Review pane now; a suite that looked for them on General moves its lookup.

**Fit.** Every view fits its 736 x ~512 content area at font offsets -2..+2 (the suite measures
under `S.Geometry(true)`); a column that would overflow is a failing test, not a scroll frame.

### `UI/Settings_TBC.lua` (TBC's `MD.SettingsLine`, TBC TOC only)

`UI/Options_General.lua` renamed. Its controls keep their keys, words, ranges and tooltips; only
their place changes. The map (every control of today's file):

| Today (pane) | Control | After |
|---|---|---|
| OOM Widget | Lock widget (`locked`) | General / MANA CLOCK, `Lock in place` |
| OOM Widget | Tooltip on the clock (`widgetTooltip`) | MANA CLOCK |
| OOM Widget | Reset position, Customise... | MANA CLOCK, one buttons row with **Show now** (`MD.Widget.Preview`, new here; the mover seam T93 made) |
| OOM Widget | Show rest time, Show mana cooldown | **removed**: Settings -> Clock -> Text since T116 (the same keys) |
| Alerts | Mute alerts (`muted`), Drink reminder (`drinkReminder`) | General / ALERTS |
| Model | Calibration drift alerts (`calibAlerts`) | General / ALERTS |
| Model | Spend half-life, OOM digits below error, Count Tree of Life aura, Average in Nature's Grace, Reset overheal data | Review / MODEL |
| Misc | Show minimap button | General / WINDOWS (the shared section's `Minimap button`) |
| Misc | Heals on spell tooltips, ...and on damage spells | General / SPELL TOOLTIPS (the shared words) |
| Misc | Debug Console, Verify spell data, Copy profile | General / TOOLS, one buttons row |
| Misc | Regen test (30s) | Review / MODEL, beside Reset overheal data |
| Fight recording | Record fights, Allow run recording, Replay: next pull follows (`Next pull follows`), Let Coach change ranks, Full health is above, Danger line for built fights | Review / RECORDING |
| -- | Coach a fight when it opens (`replayAutoCoach`), Snapshot ticks on the bars (`replayTicks`) | Review / RECORDING, **new on TBC** (the keys are `Engine/SimModel.lua`'s, registered on TBC; Forever's words) |
| Windows | In combat, Close one window per ESC, Text size, Window size, Reset window positions | General / WINDOWS (the shared section) |
| Windows | the Look controls | General / APPEARANCE (the shared section) |
| Integrations | everything | General / INTEGRATIONS under TOOLS |

`SettingsLine.client` = `"TBC Anniversary"` (the words today's About prints). No
`recordingNote` (TBC's recorder is always loaded). `modelHint` nil. No "Show the mana clock" row:
TBC's clock has no such switch (it shows by `MD.Visibility.Want`); adding one would be a new
setting in `UI/Widget.lua`, out of this task (Lead's correction: the mockup draws the row on TBC).

### `UI/Dashboard_Forever.lua` (Forever's `MD.SettingsLine`)

- `clock`: today's MANA CLOCK rows (Show the mana clock, Lock in place, the buttons row Reset
  position / Show now / Customise..., its sentence).
- `alerts`: nil (Forever has no advisor).
- `tools`: Debug console, Copy /st dump (Measure moves to Review / MODEL).
- `integrations`: the EllesmereUI mover switch (as today).
- `recording`: `REVIEW_CHECKS` and the Full health slider (as today), plus **Danger line for built
  fights** (`simFloor`) when the key is registered (the Replay module); `live` = the module
  loaded; `recordingNote` as today's REVIEW note.
- `model`: the Measure button; `modelHint` = `"~ marks a number the model computed, not one the
  game showed."`
- `client` = today's `ClientLine`.

`BuildGeneralPane`, `BuildAboutPane`, `RefreshGeneralPane`, `RefreshAboutPane` and the moved
section builders are deleted; the dashboard's `onCreate` / `onShow` call `MD.Settings`.

### `UI/Dashboard.lua` (TBC)

- `Groups()`'s settings views: `general`, `clock`, `review`, `about`.
- `onCreate`: `general` / `review` / `about` -> `MD.Settings.Build(view, content)`; `clock`
  unchanged (`MD.ClockSettings.Build(content, CLOCK_SWITCHES)`). The `AdoptOptionsPanel` path and
  `MD.optionsFrame` go.
- `onShow`: `MD.Settings.Refresh(view)` for the three.
- **`MD:ShowOptionsFrame(tab)`** stays (Core_TBC's `/md options` and `slashcheck`'s golden call
  it): `MD:SelectView("settings", tab or <the remembered settings view> or "general")`.
  `MD:OpenDashboardSettings()` -> `general`. `MD:Fire("ShowOptionsTab", ...)` is gone; a stray
  listener is harmless.
- `SIZES.settings` = 860 x 560 fixed (above).

## The checks (fail first on the parent, then green)

**`tools/settingscheck.lua`** (new, `HARNESS_FLAVOUR = { "forever", "tbc" }`, `S.Geometry(true)`).
On the parent it fails at load (no `MD.Settings`).

Both flavours:

1. The Settings views are the table's, in order.
2. General's left column titles are SPELL TOOLTIPS, APPEARANCE, WINDOWS; the right's MANA CLOCK,
   (TBC: ALERTS), TOOLS, INTEGRATIONS; Review's RECORDING and MODEL.
3. Every pane fits its column at offsets -2..+2 (no control's bottom below the content's).
4. Each check writes its key and re-reads it on `Refresh`; each slider writes its scaled key.
5. About: the version, the line's client words, the shared blurb, one row per `MD:Commands()` row
   that has a usage, and nothing that says "TBC Anniversary" in the blurb.
6. The detail-lines dropdown is drawn only when `MD.SpellTip.DETAIL_MODES` exists, and writes
   `spellTooltipDetail`.
7. ASCII only, no bare `|`, in every string the three views draw.

TBC only:

8. Every control of the parent's `UI/Options_General.lua` (the suite lists their keys and button
   words, captured on the parent) is found in its new place per the map; Show rest time and Show
   mana cooldown are not on General.
9. Show now runs `MD.Widget.Preview`; Customise... selects Settings -> Clock.
10. `MD:ShowOptionsFrame()` opens Settings on General; `MD:ShowOptionsFrame("about")` on About;
    `MD.optionsFrame` is nil.
11. The Settings group is 860 x 560 and has no grip; Spells is still 1036 x 646.

Forever only:

12. Measure is on Review / MODEL with the `~` sentence; TOOLS holds Debug console and Copy /st
    dump only.
13. RECORDING's controls are disabled with the note `needs the Replay module - off` while the
    module is off, live when it loads (`MODULE_LOADED`).

**Re-based suites** (each change listed in the suite's own comment, nothing else moved):

- `wincheck` -- forever: the views list gains Review; About's lookups unchanged (the mark).
  tbc: the Settings size 860 x 560 (its 4 checks re-based; Spells stays 1036 x 646).
- `clocksettings` -- tbc: `Customise...` is found on the Settings pane (`MD.Settings`), not
  `SpellTunerOptionsFrame_GeneralTab`.
- `minimapcheck` -- the WINDOWS box on both lines (TBC's `Show minimap button` becomes the shared
  `Minimap button`, same key).
- `slashcheck/tbc` -- the About tab's command rows read from the shared About page; the golden's
  `call MD:ShowOptionsFrame()` lines unchanged.
- `defaultscheck` -- tbc: `ShowOptionsTab` replaced by selecting the view.
- `dashui/tbc` -- "the settings panel exists" asks for the Settings pane, not `MD.optionsFrame`;
  the T80 Windows-column checks find the shared WINDOWS section.
- `restylecheck` -- the Settings views list gains Review (both lines).

**Unchanged**: `tipcheck/forever` (the marks), `modulecheck`, `reviewforever` (unless a lookup
moved: then only that lookup), every Spells suite, `apicheck` 0, `textcheck` 0. `make check`
green.

### Counts

| Suite | Before | After |
|---|---|---|
| `settingscheck/forever` | -- | **9** |
| `settingscheck/tbc` | -- | **11** |
| the re-based suites | as today | as today unless a check is split; record any change |

Record the measured numbers here when done.

## Integrator lines

- **TOCs:** the task's own edits; `releasecheck` (the two packages list `UI/Settings.lua`, the
  TBC one `UI/Settings_TBC.lua` and neither of the deleted files).
- **`tools/data/expected-counts.json`:** `settingscheck/forever`, `settingscheck/tbc`, and any
  re-based count.
- **`CLAUDE.md`:** a new row `UI/Settings.lua` (`**Settings, both lines** (T119, SPEC-one-ui 7,
  mockup M6): MD.Settings -- General (SPELL TOOLTIPS, APPEARANCE, WINDOWS | MANA CLOCK, ALERTS,
  TOOLS, INTEGRATIONS), Review (RECORDING | MODEL) and About from rows each line installs as
  MD.SettingsLine (check / slider / dropdown / buttons / hint); Forever's sections moved here`);
  `UI/Options_General.lua` row -> `UI/Settings_TBC.lua` (TBC's line table and the map); delete the
  `UI/OptionsFrame.lua` row; `UI/Dashboard.lua` and `UI/Dashboard_Forever.lua` get `**T119:**`
  (views, sizes, `MD:ShowOptionsFrame` kept as a door). The `tools/` row: `settingscheck`.
- **`docs/TOOLS.md`** section 1: the `settingscheck` row.
- **`docs/TESTING.md`** section 49 (0.17.0): a Settings paragraph (each view on both lines; TBC's
  controls in their new places; About).
- **`docs/DECISIONS.md`**, one entry:

  > ## One Settings (2026-10-03, T119, SPEC-one-ui 7)
  >
  > Settings is one file on both lines, built from rows each line installs. Review is its own
  > view (recording and the model's knobs); General keeps what every player sets. TBC's window
  > is 860 x 560 for Settings, as Forever's. TBC gets no "Show the mana clock" switch: its clock
  > appears by the visibility rule, and a new switch is a change to the widget, not to Settings.

## Deviations allowed

- The row kinds may grow (a `color` row, a `note` on a check) if a moved control needs one; the
  rows stay data.
- Pane heights and the exact y of each row are the implementer's, inside the fit check.
- If a TBC control has no room in its column at offset +2, it may move to the other view of the
  same theme (General <-> Review) with the reason in this file.

## Out of scope

- The Spells group, its size and its pane (T120); the tooltip block's detail key logic (T121).
- A "Show the mana clock" switch on TBC.
