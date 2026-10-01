# T102 -- Settings: the Clock view, the Look dropdown, the INTEGRATIONS pane

Status: **built** 2026-10-01 on branch `next/T102` (base `319f6cb`), wave N4 of
`docs/SPEC-next.md`, beside T104 and T105 (and T103, T106, T107). It awaits the integrator.

## The task (docs/SPEC-next.md section 11, row T102; 5.4, 6.3, 7.3-7.4, 2.5; mockups M7b, M8f, M8g, M9d)

> **Settings: Clock view, Look dropdown, INTEGRATIONS pane** (5.4, 6.3, 7.4). The clock view with
> the preview (`MD.ClockView.Build`) and chips; the swatch row; `Customise...` on both everyday
> panes; the Look dropdown and the class-colour check; the clock subcommands through
> `MD:AddSubcommand("clock", ...)` from `UI/ClockSettings.lua` (no core file touched).

Owned files, and the only files edited: `UI/ClockSettings.lua` (new), `UI/Dashboard.lua`,
`UI/Dashboard_Forever.lua`, `UI/Options_General.lua`, `tools/clocksettings.lua` (new),
`tools/slashcheck.lua`, and this file.

The author's answers used (9.1): every decision as recommended except those listed there.
Decision 3 (each style its own accent, one "Use my class colour" over all of them), decision 4
(live switch, with the reload line), decision 13 (Line, Compact, Bar and Ring; the ring is T104's),
decision 17 (left-click out of combat only, stated in When), decision 19 (brokers on by default,
ElvUI lists them twice, Settings says which to pick).

## What was built

### `UI/ClockSettings.lua` (new; both lines)

**Settings -> Clock** (`MD.ClockSettings.Build(content, opts)`), a view of its own in the
Settings group:

- **PREVIEW.** A frame of its own, drawn by `MD.ClockView.Build`. It is never the widget and never
  a child of it, so neither line's single visibility owner is touched from here.
  - A `ground` toggle, dark or light, under the preview.
  - **The chips**, (Live) then OOM, OOM <20s, bound, hold, warm-up, FULL, rest and ooc. These are
    `MD.ClockFace.SAMPLES` by key, named as SAMPLES names them.
  - A chip paints its face as this line draws one (`CS.SampleFace`). On a line with a modelled
    pool (Forever, from the line's own `facts.model`) that means the `~`, one colour, `0:15` and
    no arrow.
  - (Live) paints `MD.ClockFace.Current(GetTime())` on every tick while the view is visible,
    through the line's own bar `draw`. On Forever that is `MD.API.DrawUnitPower`, never read.
  - The chips' bar is illustrative: a fill of 0.6, and 3 s left in the five-second rule in a fight.
- **LAYOUT.** One button per `MD.ClockView.LAYOUTS`, so T104's ring joins the row when it is
  drawn. Beside them, `style: <name> (Settings -> General -> Look)` and **Reset to style**.
- **The level-3 box** (`UI.CreateNavBox`, the kit's rule one level down: tabs on the left):
  - **Colours:** a swatch row per tone (`colors.<tone>`), the bar colour (By source / By tone /
    Class colour, or a swatch: `bar.color`) and the bar background (`bar.back`).
  - **Frame:** background swatches and an alpha slider (`panel.fill`, rgba), border swatches and
    `none` (`panel.edge`).
  - **Bar:** the source (only those `CV.SourceOK` allows for this layout on this line), the spark
    (`bar.spark`), the height 2-24 and the horizon 60-600 s.
  - **Show** and **When:** the line's own switches, handed in by its dashboard (below).
- **The swatch row** (local to the file, as 7.4 says): the six tones, seven style tokens (read at
  each repaint), the class colour, eight fixed colours, and `style` (the override removed). It
  makes no client call.
- **Under the box:** Show on screen 60 s (`MD.ClockWidget:Preview(60)`) and Reset place.
- **Every control writes through `MD.ClockView.Set`.** It never writes `db.clockLook.over`
  itself; `CLOCK_LOOK` rebuilds the line's clock (its own handler) and the preview. The pane
  rebuilds on `CLOCK_LOOK` and `STYLE_CHANGED`.

**The Look controls** (`CS.LookControls(parent, ddWidth)`; 5.4, M7b):

- **The Look dropdown.** Every `UI.Styles.Keys()` entry, by the style's `name`. Ellesmere is named
  by `UI.Ellesmere.Label()`, so it reads `Ellesmere (following EllesmereUI)` while it follows.
  The style's `hint` is the item's tooltip. Picking calls `UI.SetStyle`, which saves `db.ui.style`
  and repaints at once.
- **Use my class colour** (`db.useClassColour`, registered here, default false; decision 3).
  - The file wraps `UI.ApplyStyleTokens`, the applier every style goes through. While the switch
    is on, the applier is handed the style with `accent = "class"`.
  - Toggling the switch re-applies the active style through `UI.Styles.Refresh`, which fires one
    `STYLE_CHANGED`.
  - Under Flat it changes nothing, because Flat's accent is the class colour already.
  - A lazy dump line, `accent: your class colour (Use my class colour)`, is added the first time
    the switch is turned on.
- **The reload line** `Some windows finish changing after a reload  [Reload]` (decision 4). It is
  shown while the style or the accent painted differs from what the session logged in with
  (`CS.ReloadNeeded`), and hidden again after going back. Reload is
  `MD.API.Call("ReloadUI")`.

**INTEGRATIONS** (`CS.BuildIntegrations(parent, width, height, extra)`; 6.3, M9d):

- What was found, one line each: `MD.Integrations.Lines()` (T97), else `none found`.
- **Publish brokers** (`db.feeds.ldb`; off takes effect after a reload, as T97 publishes at
  `MD_READY`) and **Compact broker text** (`db.feeds.compact`, live).
- The line's own extra switches (Forever: the EllesmereUI mover).
- A hint for the host found:
  - EllesmereUI: `Add them in /eui -> DataBars -> a Broker Plugin block.`
  - ElvUI with brokers: `In ElvUI pick SpellTuner, not LDB: SpellTuner - both read the same.`
    (decision 19)
  - brokers only: a broker display lists them;
  - else where they would show.

**`MD.ClockLook`** (`MD:Provide`): the line's resolved clock look (`MD.ClockWidget.view.look`).
`Integrations/Surface_LDB.lua` already follows it when a file provides it (T97 deviation 3), so the
broker now drops the rest segment when the Forever clock does. With the default settings the
broker's words are unchanged (`euicheck` and `surfacecheck` identical).

**The subcommands** (7.4, 2.5), each through `MD:AddSubcommand("clock", ...)`:

- `layout <name>`: `CV.SetLayout`. With no name it prints the layout and the list. An unknown name
  is refused, naming the layouts.
- `look reset`: `CV.ResetToStyle`. `look` alone prints its usage.
- `preview`: `MD.ClockWidget:Preview(60)`, or `mana clock: not loaded`.
- On Forever, `/st clock` and `/st clock lock` are unchanged: a sub is matched only on its own
  first word, and the row reads `/st clock [lock] / rest / clickthrough / layout <name> / look
  reset / preview`.
- On TBC, which had no `clock` verb, the subs create `/md clock`. It prints the three usages, and
  its help row is `/st clock layout <name> / look reset / preview`, as T94's `/md ui` reads
  `/st ui style <name>`.
- The usage says `<name>`, not a list, so the help row does not change when T104 adds the ring.

### `UI/Dashboard.lua` (TBC)

- Settings views are now `general, clock, about`. The clock view is the ClockSettings pane, kept
  apart from `MD.optionsFrame`, which stays the pane of General and About.
- `onShow` refreshes the clock pane.
- `CLOCK_SWITCHES` holds this line's keys:
  - Show: `db.showRest` (`segment = "rest"`) and `db.showCooldown` (`segment = "cd"`);
  - When: `db.locked` and `db.widgetTooltip`, each followed by `MD:UpdateVisibility`.

### `UI/Dashboard_Forever.lua` (Forever)

- Settings views are now `general, clock, modules, about`.
- **APPEARANCE** opens with Look, its dropdown and "Use my class colour" on one row, and the
  reload line under them. The two sliders sit 44 px lower; the section is 148 tall instead of 104.
- **MANA CLOCK** gains `Customise...` beside Show now (`pane.clockCustomise`).
- **INTEGRATIONS** goes under WINDOWS in the left column, 116 tall. Its extra switch is
  `Clock mover in EllesmereUI's /unlock` (`db.eui.unlock`). Turning it on calls
  `MD.EUI.RegisterMover()`; off takes effect after a reload. It is shown only when
  `MD.Surfaces.eui` exists.
- `CLOCK_SWITCHES` holds this line's keys:
  - Show: `db.clock.showRest` (`segment = "rest"`);
  - When: `db.clock.shown`, `db.clock.locked` (through `MD.Clock:SetLocked`) and
    `db.clock.clickThrough`.
- **Fit.** The left column ends at 4 + 64 + 12 + 148 + 12 + 138 + 12 + 116 = 506 of the view's
  520. The right column is unchanged.

### `UI/Options_General.lua` (TBC)

- **OOM Widget** gains `Customise...` under Reset position (`pane.customiseButton`). The pane is
  186 tall instead of 164, and the panes under it move down 22 px (Fight recording ends at 531 of
  606).
- **Windows** opens with Look and its dropdown, Use my class colour, and the reload line (wrapped
  in 132 px). Its own controls sit 84 px lower; the pane is 320 tall.
- **Integrations** is a fourth column at x 656 (656 + 205 = 861 of the view's 912), 150 tall.
- Each new control is guarded on `MD.ClockSettings`, so a TOC without the file builds the panes
  as before, with an empty band at the top of Windows.

## The checks

**Fails first on `319f6cb`** (the two suites copied into an extract of the parent):

| Suite | On the parent |
|---|---|
| `clocksettings/tbc` | 1 ok, **33 failed** |
| `clocksettings/forever` | 2 ok, **33 failed** |
| `slashcheck/tbc` (re-based) | 6 ok, **4 failed** (the help row, both passes, About, the row count) |

**`tools/clocksettings.lua`** (new; tbc 34, forever 35). It loads the flavour's whole TOC under
`S.Geometry(true)`, with fake hosts installed before the TOC: LDB on both lines, ElvUI on TBC,
EllesmereUI 9.3.4 on Forever. It loads `UI/ClockSettings.lua` where the integrator's TOC line puts
it when the TOC does not list it yet; the first check says which.

1. **The view.**
   - The Settings group's views are `general,clock,about` (TBC) or
     `general,clock,modules,about` (Forever).
   - The pane has PREVIEW and LAYOUT, and the box has the five tabs.
   - The preview is neither the widget nor its child.
2. **The chips.**
   - Each of the eight sample chips paints the words of the SAMPLES face, built in the suite
     itself with Forever's marks on Forever.
   - The clock on screen is untouched: the same words, the same shown state, no Show or Hide on
     its frame.
   - The chip names are `(Live),OOM,OOM <20s,bound,hold,warm-up,FULL,rest,ooc`.
   - (Live) paints `ClockFace.Current`.
3. **Layout buttons.** A button saves `db.clockLook.layout` and fires `CLOCK_LOOK` once; the widget
   and the preview rebuild; the buttons are `CV.LAYOUTS`.
4. **Controls.**
   - A crit swatch writes `colors.crit` on the widget and the preview.
   - The source, spark and height write `bar.*`, and the widget's look has them.
   - The offered sources are `pool,time,fsr,none` on TBC and `pool,model,time,fsr,none` on
     Forever.
   - The alpha slider writes `panel.fill[4]`.
   - Reset to style empties `over` and keeps the layout, with `CLOCK_LOOK` once.
5. **Show and When.**
   - The rest switch writes the line's key. The rest chip loses `rest 3:40` at once and gets it
     back, and `MD.ClockLook().show.rest` is false.
   - Locked writes the line's lock.
6. **Look.**
   - The items are `UI.Styles.Keys()`, and Ellesmere's text is `UI.Ellesmere.Label()`.
   - Picking Ellesmere writes `db.ui.style`, fires `STYLE_CHANGED` once and changes the palette.
     The reload line shows and the clock pane says `style: Ellesmere`.
   - The class colour puts `UI.classAccent` over the style's accent (`STYLE_CHANGED` once), and
     unticking takes it back.
   - Back on Flat, the palette is Flat's and the reload line hides.
7. **Slash.**
   - `layout compact`, then `Nosuch` (refused, naming `CV.LAYOUTS`).
   - `layout ring`, which is saved where `CV.LAYOUT.ring` exists and refused otherwise, so the
     check holds before and after T104.
   - `look reset` and `look`.
   - `preview` (the widget is shown).
   - Forever: `/st clock` and `/st clock lock` print `hidden`, `shown`, `locked` and `unlocked`,
     one line each, exactly as before.
   - TBC: `/md clock` prints the three usages.
   - The help row on each line.
8. **INTEGRATIONS.**
   - The lines equal `MD.Integrations.Lines()`: `ElvUI: 2 datatexts / Broker: 2 objects` on TBC,
     and `EllesmereUI 9.3.4 (tested 9.3.4): ...` on Forever.
   - The hint for that host.
   - The broker and compact switches write `db.feeds`.
   - Forever's mover switch is shown and writes `db.eui.unlock`.
   - `none found` with no `MD.Integrations`.
9. **Customise...** on OOM Widget (TBC) and on MANA CLOCK (Forever) opens Settings -> Clock.
10. **Text and fit.**
    - Every string of the clock view, the INTEGRATIONS pane, the reload line and the dropdown
      items is ASCII with no bare pipe (over 40 strings).
    - Every titled pane, the box and the two buttons of Settings -> Clock lie inside the view.
    - Every titled pane of Settings -> General lies inside the view: 736 x 520 on Forever,
      912 x 606 on TBC, at the windows' fixed sizes.
11. **A fight (both lines; Forever under the forever profile).** (Live) paints through six ticks
    without raising, and no font string holds a non-string.

**`tools/slashcheck.lua`** (re-based; TBC 10, unchanged count).

- It loads `UI/ClockView.lua` and `UI/ClockSettings.lua` as the TBC TOC will list them.
- VERBS gains `clock`, `Clock Layout Bar`, `clock layout compact`, `clock layout line`,
  `clock look`, `clock look reset` and `clock preview`. None of them prints the layout list, which
  T104's ring will change.
- The golden was regenerated with `--golden`. Its diff from the T94 golden is additions only:
  - the new help row in both helps and both `nosuch`;
  - the seven verbs in each pass;
  - the two About lines.

  The `--print` transcripts before and after were compared line by line. The row-count check is
  now 30 lines (heading + 29 rows).

**The whole check, two states:**

- **This branch** (no TOC line): `tools/check.sh` gives 88 runs, all passed. 83 were counted
  against 81 expected; the two extra are `clocksettings` NOTEs.
- **Integrated** (the three TOC lines below added and the import fixture rebuilt, then both
  reverted): 88 runs, all passed. Every existing count is unchanged, including `wincheck`,
  `dashui`, `euicheck`, `surfacecheck`, `clockui`, `stylecheck`, `themecheck`, `consolecheck`,
  `defaultscheck` and `importcheck`.

| Count | Before | After |
|---|---|---|
| `clocksettings/tbc` | (new) | **34** |
| `clocksettings/forever` | (new) | **35** |
| `slashcheck/tbc` | 10 | 10 (golden re-based) |
| `defaultscheck/tbc` | 49 (46 read) | 49 (**47** read, with the TOC line) |
| `defaultscheck/forever` | 52 (31 read) | 52 (**32** read, with the TOC line) |
| `apicheck` | 0 findings, 69 files | 0 findings, 70 files (with the TOC line) |
| `textcheck` | 0 findings, 108 files | 0 findings, 109 files (with the TOC line) |

`defaultscheck`'s new "read" key is `useClassColour`, which has its default on both flavours.

## Integrator lines

**TOCs** (UI/ClockSettings.lua needs `UI/ClockView.lua`, the line's clock and `UI/Styles.lua`
loaded before it; the dashboards reach it only when a pane is built):

- `SpellTuner_TBC.toc`: `UI\ClockSettings.lua` right after `UI\Widget.lua`.
- `SpellTuner_Mainline.toc` and `SpellTuner.toc`: `UI\ClockSettings.lua` right after
  `UI\Clock_Forever.lua`.

**`tools/data/expected-counts.json`:** `"clocksettings/forever": 35`, `"clocksettings/tbc": 34`.

**`tools/check.sh`:** nothing (a new `tools/*.lua` is a suite; `HARNESS_FLAVOUR` declares both).

**`tools/data/import-forever-sv.lua`:** rebuild with `bash tools/run.sh tools/importfixture.lua`
after the TOC lines. It gains exactly one line, `["useClassColour"] = false,`, in the account
table (checked here, then reverted). One rebuild after the wave covers every task's defaults.

**`docs/DECISIONS.md`** (proposed lines):

- *`/md clock` on TBC (T102, docs/SPEC-next.md 2.5, 7.4).* `UI/ClockSettings.lua` registers
  `clock layout <name>`, `clock look reset` and `clock preview` through `MD:AddSubcommand`. TBC
  had no `clock` verb, so a new `/md clock` row appears in the help and the About tab, and
  `slashcheck/tbc`'s golden was re-based for it (additions only, as T94's `/md ui`). Forever's
  `/st clock` and `/st clock lock` are unchanged.
- *Use my class colour (decision 3, T102).* It is `db.useClassColour`, default off, and puts the
  class colour over any style's accent. It is applied by wrapping `UI.ApplyStyleTokens` in
  `UI/ClockSettings.lua`. The active style is re-applied, with one `STYLE_CHANGED`, when the
  switch changes. Under Flat it changes nothing.
- *The reload line (decision 4, T102).* It shows while the style or the accent painted differs
  from the login's. It does not yet count T107's conversions; see deviation 4.
- *The broker follows the line's clock look (T102, closing T97 deviation 3).* `MD.ClockLook` is
  provided, so turning the Forever rest segment off turns it off in the brokers too.

**`docs/TESTING.md`**, section 46: spec section 12's item 9 as written, with these notes:

- the box's tabs are Colours, Frame, Bar, Show and When (no Text tab; deviation 1);
- check the Look dropdown, Use my class colour and the reload line (item 8);
- check INTEGRATIONS on both clients (items 5 and 7: the pane says which ElvUI entry to pick).

**`docs/HISTORY.md`**: wave N4's entry names T102:

- Settings -> Clock with its preview and chips, the layouts, the box and the swatch row;
- the Look dropdown and Use my class colour with the reload line;
- INTEGRATIONS on both lines;
- `Customise...` on both everyday panes;
- `/st clock layout / look reset / preview`;
- `clocksettings` 34 / 35.

**`CLAUDE.md`**, the file table: a `UI/ClockSettings.lua` row (both TOCs: Settings -> Clock,
the Look controls, INTEGRATIONS, the clock subcommands, `MD.ClockLook`, `db.useClassColour`).
The `UI/Dashboard.lua`, `UI/Dashboard_Forever.lua` and `UI/Options_General.lua` rows gain a T102
note.

## Deviations

1. **No Text tab yet.** 7.3's Text group needs these keys:
   - font face, size and outline;
   - shadow, the numbers' face and the alignment;
   - the time format and the labels.

   The renderer accepts none of them. `MD.ClockView.OVER` has only the `panel.*`, `bar.*` and
   `colors.*` keys, and `UI/ClockView.lua` is T104's file this wave. A tab whose controls do
   nothing was left out. The same goes for 7.3's Frame size, scale, alpha and strata, the bar
   texture, position and reverse fill, and Show's mp5, pct and 5SR segments.

   The box holds every control the renderer draws today. Adding a key means declaring it in
   `CV.OVER` and drawing it in `UI/ClockView.lua`; a control here then writes it through
   `CV.Set`.
2. **Show and When hold the line's own switches**, handed in by each dashboard (`opts.show` /
   `opts.when`). They are not new `clockLook` keys: 7.3 phase 1 keeps the existing keys where they
   are, and a shared file reading the other line's keys would fail `defaultscheck`. The When tab
   states the visibility rule and the left-click rule as text; they are not switches yet.
3. **"Use my class colour" wraps `UI.ApplyStyleTokens`** instead of living in `UI/Styles.lua`.
   That file is T103's this wave; T94 noted `UI.StyleAccent` as the natural seat. `/st dump`'s
   style line still says `(accent style)` under the switch, so this file adds its own lazy
   `accent:` line. Folding the switch into `UI.StyleAccent` and the style line is a later
   one-file change.
4. **The reload line does not count what is left.** It shows on any live change of the style or
   the accent. T107 (this wave) converts the creation-time colours and may expose a count; when
   it does, `CS.ReloadNeeded` can also ask it.
5. **The level-3 box's tabs are on the left** (`UI.CreateNavBox`'s groups, the kit's "level 1
   vertical, level 2 on top" rule, 7.4 "the level-3 box is UI.CreateNavBox"). Mockup M8f drew
   them as a top row. The empty view row of the box is used by the tab frames (they start 22 px
   higher).
6. **Bottom row:** Show on screen 60 s and Reset place. The Lock of the mockup is the When tab's
   Locked switch, the line's own.
7. **`/st clock layout ring` is refused on this branch.** It is accepted once T104 adds the ring to
   `CV.LAYOUT`, with no edit here. The help says `layout <name>` so that the golden does not move
   then.
