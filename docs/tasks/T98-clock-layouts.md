# T98 -- Clock layouts (K3)

Status: **built** 2026-10-01 on branch `next/T98` (base `25748e3`), wave N3 of
`docs/SPEC-next.md`, beside T97 and T100. It awaits the integrator.

**The branch needs no TOC line.** `UI/ClockView.lua` is already on the three main TOCs (T93). It
needs one fixture rebuild (below): `UI/ClockView.lua` registers `db.clockLook`, so the generated
`tools/data/import-forever-sv.lua` gains four lines. That file is not one of this task's files.
Without the rebuild, `importcheck` fails its "the committed fixture is what importfixture writes
today" check and nothing else. The rebuild was run in the working tree to check this, then
reverted before the commit.

## The task (docs/SPEC-next.md section 11, row T98; 7.2, 7.3, 2.4, 2.5; R-clock.md 4, 5, 6, 10 K3)

> **Clock layouts (K3).** Compact and Bar; `db.clockLook = { layout, over }` (declared here;
> reported for `defaultscheck`) resolved over the style's `clock` role, which each style file
> defines; bar sources; the spark; `UI.Skin(widget, "clock")`; the clock's dump line.

Owned files: `UI/ClockView.lua`, `UI/Widget.lua`, `UI/Clock_Forever.lua`, `tools/clockui.lua`
(new), `tools/clockfacecheck.lua`. Nothing else was edited apart from this file.

The author's answers used here (`docs/SPEC-next.md` 9.1; every decision not named there is taken
as recommended):

- **Decision 13:** Line, Compact and Bar now. Ring is T104's. Two lines is not scheduled.
- **Decision 15 (a):** each line keeps its bar's meaning by default (the 5SR on TBC, the pool on
  Forever). The spark is optional.
- **Decision 16:** the tones keep TTO's literals, and a look may re-tint them.

## What was built

### `UI/ClockView.lua` (both lines): layouts, the look, the bar

**The store.** `MD:RegisterDefaults({ clockLook = { layout = "line", over = {} } })`.

- Only the layout and an empty override table are declared, because a registered default fills
  every leaf (7.3).
- Nothing outside this file reads `db.clockLook.over`.
- The line's own switches stay where they are and reach the look as `show`: TBC
  `db.showRest` / `showCooldown`, Forever `db.clock.showRest`.

**The resolver.** `CV.Resolve(stored, role, facts) -> look` is pure. It resolves, in this order:

> the layout's defaults (`CV.LAYOUT`) <- the active style's clock role <- `over`

- **The role** is `UI.Styles.Recipe("clock")`, which is Flat's while no registry is loaded. Each
  style file defines its own. The resolver reads these fields from it:
  - `kind`, `fill`, `edge` (and `edgeColor`, through `UI.Skin`'s recipe) for the panel;
  - `bar`, the bar's backing colour;
  - `barFill`, optional: the bar's colour, in place of the source's own;
  - `ring`, for T104.
- **`over`** takes only the keys in `CV.OVER`, each with what it accepts:
  - `panel.fill` and `panel.edge`;
  - `bar.source`, `bar.spark`, `bar.height` (2-24), `bar.horizon` (60-600), `bar.color`
    (`source` / `tone` / `class` / a colour) and `bar.back`;
  - `colors.<tone>`, six hex digits each.

  A value it refuses is ignored and named in `look.refused`.
- **A layout nobody draws yet** (for example `ring`) resolves as `line`. The dump says
  `line (saved ring)`.
- **A refused source falls back.** A source the layout may not draw on this line falls back to the
  line's own. `CV.SourceOK(layout, source, facts)` decides:
  - `model` needs a modelled pool (Forever);
  - `pool` is refused for the ring wherever the pool is only drawn (Forever). The rule is written
    now, so T104 only draws.

**The store's API.** `CV.Look(facts)` reads the store and the active style. Three setters each
save and fire `CLOCK_LOOK`:

- `CV.SetLayout(key)` refuses an unknown key and names the layouts.
- `CV.Set(key, value)` takes a key from `CV.OVER`; nil removes it.
- `CV.ResetToStyle()` wipes `over` and keeps the layout.

**The dump line.** It is `CV.DumpLine()`, for example `clock: layout bar, 2 overrides
(bar.source, colors.crit)`. It goes through `MD:AddDumpLine("clock", ...)`, and it is added the
first time the look is not the default (T94's lazy rule). The dump of a player who never touched
the clock is therefore unchanged, and so is `consolecheck`'s "no dump line" check.

**The layouts.** `View:SetLook(look)` builds each layout's regions the first time that layout is
drawn and keeps them, one pool per frame, so a switch leaks nothing. The bar, its backing and the
spark are shared by all three.

- **line** (L1): T93's regions in T93's order:
  - label, probe, value, second and message, then the bar and its backing;
  - 180 x 30 with a 160 x 4 bar 5 px above the bottom.

  The frame grows taller only for a bar over 4 px. Anything less would change `stylecheck`'s clock
  golden; it does not change.
- **compact** (L2):
  - the label in `UI.FONT_SMALL` at the top left;
  - the value below it in the number face at 22 pt plus the font offset;
  - no secondary (the rest segment is in the hover);
  - no bar unless a source is set (then a strip at the bottom);
  - the preview's words wrap to the frame's width.
- **bar** (L3): a bar filling the clock, with the label on its left and the time right-aligned on
  its right. Both sit on a holder frame one level above the bar, because a status bar draws over
  its parent's own regions.

**Fits by construction.** Compact and Bar size their frame from what they must hold, measured in
their own fonts:

- the widest label (`labelSample`);
- `CV.VALUE_SAMPLE = ">0:00 vv"`, wider than anything drawn.

They are measured at each paint and re-placed only when a measure changed (a font offset). Line
keeps T93's rule: the value moves only when the label slot's width did.

**The bar.**

- **Sources** are drawn by `View:PaintBar(now)`:
  - `pool` is the line's own `draw.pool(bar)`. TBC reads it plain. Forever's goes through
    `MD.API.DrawUnitPower` and is never read.
  - `model` is the face's `pct`, on Forever only.
  - `time` is the shown time to OOM over `horizon` (180 s). It is full in FULL and out of combat,
    and empty with no number.
  - `fsr` is `5 - remaining`, where `remaining` is the line's `draw.fsr(now)`. TBC uses
    `MD.Regen:FSRRemaining()`; Forever uses the model's last priced spend.
  - `none` hides the bar, its backing and the spark.
- **The colour.** With `color = "source"` (the default) each source keeps its own colour:
  - `fsr`: amber while the rule runs, green once regen runs (TBC's);
  - `pool` and `model`: the mana blue (Forever's `0.3, 0.6, 1`);
  - `time`: its tone.

  `tone` uses the face's tone: on Forever's pool that is the *modelled* tone. `class` is the class
  colour, and any colour spec is used as given. A style's `barFill` sits between the source's
  colour and `over`.
- **The spark** (`bar.spark = "fsr"`, ElvUI's): a 2-physical-pixel yellow texture in ADD that
  sweeps the bar over the five seconds after a spend. Neither line knows the 2-s regen tick, so
  after the rule the spark is hidden. There is no white tick sweep yet.
- **`View:FillBar(r, g, b)`** is TBC's unlock preview: a full bar in the accent.

**The panel.** `View:Snap()` calls `UI.Skin(frame, "clock", panel.fill, panel.edge)` and sizes
the backing at the current physical pixel. The clock is now registered under the `clock` role, no
longer `window` (which `StylizeFrame` inferred from `bg`). Under Flat the paint is identical.

**What the view never does:**

- Show or hide the frame.
- Read a client value.
- Touch `MD.db` outside `CV.Look`, `SetLayout`, `Set` and `ResetToStyle`.

### `UI/Widget.lua` (TBC)

- **Its facts:** the source is `fsr`, `poolPlain = true`, there is no model, `labelSample` is
  `FULL`, and `show` comes from `db.showRest` / `showCooldown`.
- **Its `draw`:**
  - `pool`: `UnitPowerMax` / `UnitPower`, plain, as the file's visibility already reads them;
  - `fsr`: `MD.Regen:FSRRemaining()`.
- **The view** builds the bar and its backing (the same objects as before, now the view's);
  `widget.bar` and `widget.barBack` are kept. The OnUpdate draws the words at 4 Hz (`Paint`) and
  the bar at 10 Hz (`PaintBar`). The preview is `Message` plus `FillBar`.
- **A new look.** `CLOCK_LOOK` rebuilds the look and repaints at once. `STYLE_CHANGED` only
  rebuilds; the next 0.1 s paint draws, which keeps `stylecheck`'s round trip byte-identical.
  Neither touches visibility.
- `MD.Widget.view` and `MD.Widget.facts` are exposed.

### `UI/Clock_Forever.lua` (Forever)

- **Its facts:** the source is `pool`, `poolPlain = false`, `model = true`, `labelSample` is
  `~FULL`, and `show.rest` comes from `db.clock.showRest`.
- **Its `draw`:**
  - `pool`: `MD.API.DrawUnitPower(b, "player", 0)`;
  - `fsr`: `model.lastSpend + 5 - now`, plain.
- **`Paint`** is split:
  - `PaintFace(now)`: the snap, the words or the preview message, and `view:PaintBar(now)`;
  - then the visibility pass and the flash.

  `CLOCK_LOOK` repaints through `PaintFace`, never the visibility pass. That pass calls
  `widget:Show()` on every tick while the clock is shown, which a layout switch must not do.
- The bar's mana blue is set at build, as before (`stylecheck`'s golden).
- **The hover's last line** names what the bar is, from the look. By default it is unchanged:
  `The bar under the clock is your real mana, drawn by the game.`
  - other sources: `your modelled mana`, `the time until you are out of mana`, `the five seconds
    after each spend`;
  - source `none`: no bar sentence;
  - `The bar is ...` instead of `The bar under the clock is ...` outside the line layout.
- `MD.Clock.facts` is exposed.

## The checks

**Fails first on `25748e3`.** The suites were committed alone (`446f4a7`), before any code
commit, and run against an extract of the parent:

| Suite | On the parent |
|---|---|
| `clockui/tbc` | **0 ok, 16 failed** |
| `clockui/forever` | **0 ok, 16 failed** |
| `clockfacecheck/tbc` | 20 ok, **2 failed** (section 6) |
| `clockfacecheck/forever` | 17 ok, **2 failed** (section 6) |

**`tools/clockui.lua`** (new; tbc and forever, 16 each). It loads the flavour's whole TOC (on TBC
the UI files too; `Integrations/` is left out) with `S.Geometry(true)` on before the first file,
so every piece of the clock has a place that can be computed:

1. The layouts are `line`, `compact` and `bar`. `SetLayout` saves and fires `CLOCK_LOOK` once; an
   unknown layout is refused, naming the layouts, and nothing fires.
2. **Fits (three checks, one per layout):** each of the 14 `SAMPLES` faces, as this line draws it
   (Forever: `~`, mono, `0:15`), at font offsets -2..+2 (70 paints per layout). Every shown piece
   lies inside the frame, no two pieces overlap, and in line and compact no text overlaps the
   bar's backing. The bar and its backing lie inside the frame.
3. A second round of switches creates no region (one pool per frame).
4. The line layout is T93's: 180 x 30, a 160 x 4 bar 5 px above the bottom, centred.
5. `bar.source = "none"` hides the bar, its backing and the spark on every layout, the layout
   still fits, and a source brings the bar back.
6. The sources draw what they say:
   - `time`: 90 s of 180 is 0.5, white; with a 360 horizon it is 0.25;
   - `fsr`: 3 s left is 2 of 5, amber; then 5, green;
   - `pool`: TBC is `UnitPower` of `UnitPowerMax`, mana blue; on Forever the bar holds the secret,
     unread;
   - `model` (Forever): 0.4;
   - `color = "tone"`: crit red.
7. The spark at 3 s left sits 40 % along the bar, yellow. It is hidden at 0, and off when the
   setting is.
8. **Sources by line:**
   - Forever: `pool` is refused for the ring with a reason, allowed for the bar; `model` is
     allowed.
   - TBC: `pool` is allowed for the ring; `model` is refused and falls back to `fsr`, with the
     refusal named.
9. A layout switch leaves the frame's shown state alone, both shown (in a fight) and hidden (at
   full, out of combat), with no Show / Hide on the frame.
10. Every Show / Hide on the frame comes from the visibility owner. Each call is recorded with its
    caller's name (`debug.getinfo`) over a scenario: fights, ticks, every layout, overrides, a
    reset, the preview and a lock. Forever made 11 Show and 18 Hide calls, all from
    `UpdateVisibility`.
11. The frame is registered by the `clock` role in today's paint (`bg`, `border`, a black
    backing).
12. A test style's clock role paints the fill, the backing and the bar's colour (`barFill`). An
    override wins over all three. Reset to style gives the style back, and Flat gives today's paint
    back.
13. The dump line reads, in turn:
    - `clock: layout line, 0 overrides`;
    - `clock: layout bar, 1 override (bar.source)`;
    - `clock: layout bar, 2 overrides (bar.source, colors.crit)`.
14. **Forever:** under the forever profile every layout x source x spark (30 paints) paints in a
    fight without raising. The stub's secret raises on any arithmetic, comparison, concatenation
    or `tostring`. Only `pool` leaves a secret in the bar, every other source leaves a plain
    number, and no font string holds a secret. **TBC:** the same matrix paints without raising.

**`tools/clockfacecheck.lua`**: tbc 20 -> **22**, forever 17 -> **19**. Section 6 loads
`UI/Style.lua`, `Theme_Flat`, `Styles` and `ClockView` on TBC, where the harness drops UI files.

- **6.** With no role, the layout's defaults hold: `bg`, `border`, a black backing, `source`, the
  line's source. A role's fill, backing and `barFill` win over the defaults, and `over` wins over
  the role (fill, bar colour, backing, source, a tone colour). The resolved look is a copy, so the
  store keeps its own values.
- **6b.** Reset to style: the overrides are gone, the layout is kept, `CLOCK_LOOK` fires once,
  and the source and colours are the style's again.

**Mutations** (each reverted):

| Mutation | Result |
|---|---|
| Compact's width no longer measured (`w = look.width`) | `fits: compact` fails: `0:15 vv` runs past the 72-px frame at offset -2 |
| `SetLook` calls `self.parent:Show()` | the switch check and the owner check fail on both flavours ("Show from SetLook") |
| `PaintBar` compares the bar's value after drawing the pool | Forever: every check that paints the pool raises "attempt to compare number with table" |

**Unchanged:** every other suite, by count and by golden, including:

- `stylecheck` (its clock section, 8 regions with its checksum, and the Flat round trip);
- `ttocheck` 50 and `clockcheck` 35;
- `consolecheck`, `wincheck`, `themecheck` and `minimapcheck`.

### The whole check

`tools/check.sh` with the fixture rebuilt: **83 runs, all passed.** That is the parent's 81 plus
`clockui` on two flavours; 78 were counted against 76 expected, and the two extra are `clockui`.

| Count | Before | After |
|---|---|---|
| `clockui/tbc` | (new) | **16** |
| `clockui/forever` | (new) | **16** |
| `clockfacecheck/tbc` | 20 | **22** |
| `clockfacecheck/forever` | 17 | **19** |
| `defaultscheck/tbc` | 49 (44 read) | 49 (**45** read) |
| `defaultscheck/forever` | 52 (28 read) | 52 (**29** read) |
| `apicheck` | 0 findings, 66 files | unchanged |
| `textcheck` | 0 findings, 105 files | unchanged |

`defaultscheck`'s assertion counts do not move. Its "(N read)" figure gains `clockLook` on both
flavours, and the key has its default.

**Without the fixture rebuild** (the committed tree), only `importcheck` fails (20 ok, 1 failed:
"rebuild with: bash tools/run.sh tools/importfixture.lua").

## Integrator lines

**TOCs:** none. `UI\ClockView.lua` is already listed (T93).

**`tools/data/import-forever-sv.lua`:** rebuild it with `bash tools/run.sh tools/importfixture.lua`.
It gains exactly four lines after `["clock"]`'s block:

```lua
	["clockLook"] = {
		["layout"] = "line",
		["over"] = {},
	},
```

If T97 also registers defaults (`db.feeds`, `db.eui`), one rebuild after both merges covers both.

**`tools/data/expected-counts.json`:**

- `"clockui/forever": 16`
- `"clockui/tbc": 16`
- `"clockfacecheck/forever": 19`
- `"clockfacecheck/tbc": 22`

**`tools/check.sh`:** nothing. `clockui` declares `HARNESS_FLAVOUR = { "tbc", "forever" }` and is
picked up as a suite.

**`defaultscheck`:** counts unchanged, tbc 49 and forever 52. The "(N read)" figures move from 44
to 45 (tbc) and from 28 to 29 (forever) for `clockLook`, registered by `UI/ClockView.lua` on both
TOCs.

**`CLAUDE.md`:**

- `UI/ClockView.lua`'s row, appended:

  > **T98:** the layouts `line` (T93's regions exactly), `compact` and `bar`, each built on first use and kept (one pool per frame), sized from what they hold in their own fonts (`CV.VALUE_SAMPLE`); `db.clockLook = { layout, over }` registered here and resolved by `CV.Resolve` (pure) as the layout's defaults <- the active style's `clock` role (`kind` / `fill` / `edge` / `edgeColor` for the panel, `bar` the backing, `barFill` the bar's colour, `ring` T104's) <- `over` (`CV.OVER`'s keys only); `CV.Look`, `CV.SetLayout`, `CV.Set`, `CV.ResetToStyle` (each fires `CLOCK_LOOK`); the bar built here, its source `pool` / `model` / `time` / `fsr` / `none` (`CV.SourceOK`: `pool` refused for the ring where it is only drawn, `model` only on Forever; the line's own meaning by default, decision 15 (a)), its colour `source` / `tone` / `class` / a colour, the 5SR spark; `UI.Skin(frame, "clock")`; the dump line `clock: layout <key>, <n> overrides (<keys>)` once the look is not the default. A line hands it `facts` and `draw` (`pool(bar)`, `fsr(now)`); the view never shows or hides the frame |

- `UI/Widget.lua`'s row, appended:

  > **T98:** the bar, its backing and the panel are the view's (`UI/ClockView.lua`); the widget hands it its facts (the 5SR its bar's meaning, a pool it reads) and `draw` (`UnitPower`, `MD.Regen:FSRRemaining`), rebuilds the look on `CLOCK_LOOK` (repainted at once) and `STYLE_CHANGED` (next paint), never through the visibility owner; `MD.Widget.view` / `.facts`

- `UI/Clock_Forever.lua`'s row, appended:

  > **T98:** the bar, its backing and the panel are the view's; the clock hands it its facts (the pool its bar's meaning, drawn only, a modelled pool) and `draw` (`MD.API.DrawUnitPower`, the 5SR from the model's last priced spend); `PaintFace` (words and bar, no visibility pass) on `CLOCK_LOOK`; the hover names what the bar is (default wording unchanged); `MD.Clock.facts`

- The `tools/` row: after `**tools/clockfacecheck.lua**`'s text, add `; since T98 (tbc 22 / forever
  19) section 6: the clock's look -- over wins over the style's clock role, Reset to style wipes
  over`. Then a new sentence: `**tools/clockui.lua**` (T98, tbc / forever 16): the clock's layouts
  under `S.Geometry(true)` -- each `SAMPLES` face fits each layout at font offsets -2..+2, one region
  pool, bar.source none, the sources and the spark, pool refused for the ring on Forever, a layout
  switch keeps the shown state, every Show / Hide from the visibility owner, the clock role and
  over, the dump line, the forever profile's secrets.

**`docs/TOOLS.md`** section 1:

- A new row after `clockfacecheck.lua`'s:

  > | `clockui.lua` | **the clock's layouts** (T98, tbc 16 / forever 16; the whole TOC loaded with `S.Geometry(true)`): `line` / `compact` / `bar`, `CV.SetLayout` saving and firing `CLOCK_LOOK`; each of the 14 `SAMPLES` faces fits each layout at font offsets -2..+2 (inside the frame, no overlap, no text over the bar beside it); a second round of switches builds no region; the line layout is T93's 180 x 30 / 160 x 4; `bar.source = "none"` hides the bar; the sources (time, fsr, pool, model on Forever, the tone colour) and the spark; `pool` refused for the ring on Forever, `model` refused on TBC; a layout switch keeps the frame's shown state with no Show / Hide; every Show / Hide on the frame from `UpdateVisibility` (counted by caller); `UI.Skin(widget, "clock")`, a style's clock role, an override over it, Reset to style, Flat back; the dump line; Forever: every layout x source x spark in a fight without touching a secret (TBC: without raising) |

- `clockfacecheck.lua` row: change `(T88, tbc 20 / forever 17)` to `(T88, tbc 22 / forever 19)`
  and append: `; (T98) section 6: CV.Resolve -- over wins over the style's clock role, the role
  over the layout's defaults; Reset to style wipes over (layout kept, CLOCK_LOOK once)`.

**`docs/DECISIONS.md`:** one short entry. Nothing visible changes by default: the line layout,
the bar's meaning and colour, and the Forever hover's words are all as before. The entry records
two choices the spec leaves open:

> ## Clock layouts and the look (2026-10-01, T98, decisions 13 and 15)
>
> The clock draws in three layouts -- Line (today's, the default), Compact (one big number, no
> secondary, no bar unless asked) and Bar (a bar the width of the clock with the label and the time
> on it) -- chosen by `db.clockLook.layout`; Settings -> Clock (T102) will offer them. The look is
> the layout's defaults, then the UI style's `clock` role, then the user's overrides (`over`), and
> "Reset to style" wipes the overrides. The bar's colour defaults to its **source's own** (the 5SR
> amber then green, the pool and the model the mana blue, the time its tone) rather than the face's
> tone, so neither line's bar changes colour by default (decision 15 (a)); `bar.color = "tone"` gives
> the spec's "on Forever's pool the colour is the modelled tone". Compact and Bar size their frame
> from the widest value they can draw in their own fonts (they are wider than R-clock's 72 x 36 /
> 200 x 18 sketches when the font is), so nothing is ever cut at any font offset; Line keeps
> 180 x 30.

**`docs/TESTING.md`** section 46, a new item (the layouts have no setting until T102):

> 7. **Clock layouts (T98, wave N3), both clients, optional.** With the clock on screen (in a fight,
>    or Show now / `/md unlock`): `/run SpellTuner.ClockView.SetLayout("compact")`, then `"bar"`,
>    then `"line"`. Each draws the clock's words with nothing cut, and a switch never hides or shows
>    the clock. `/run SpellTuner.ClockView.Set("bar.spark", "fsr")`: after a cast a yellow mark crosses
>    the bar over five seconds. `/run SpellTuner.ClockView.Set("bar.source", "time")`: the bar drains
>    with the time to OOM. `/run SpellTuner.ClockView.ResetToStyle()` puts the bar back. On Forever,
>    `/st dump` shows `clock: layout ...` after any of these.

**`docs/HISTORY.md`:** wave N3's entry names T98:

- the clock's layouts Line, Compact and Bar in `UI/ClockView.lua`;
- `db.clockLook` resolved over the style's clock role;
- the bar's sources and the 5SR spark;
- `UI.Skin(widget, "clock")`;
- the dump line;
- no visible change by default.

## Deviations

1. **The bar's colour defaults to the source's own, not the face's tone.** The spec says "on
   Forever's `pool` the bar's colour is the *modelled* tone". Under decision 15 (a) the bars keep
   their meaning by default, and a tone-coloured bar would change both lines' default look with no
   decision behind it:
   - TBC's amber and green 5SR bar would turn white;
   - Forever's blue pool bar would turn white.

   So `bar.color` defaults to `source`, and `tone` gives exactly the spec's behaviour (it never
   reads the pool: the tone is the face's). A style's `barFill` overrides the source colour.
2. **Compact and Bar are sized by measurement, not by R-clock's sketch sizes.** The sketch sizes
   are 72 x 36 and 200 x 18. At 22 pt `>5:30 =` does not fit in 72 px under the stub's metric (or,
   roughly, a real one). These sizes are now minimums: the frame grows to what it must hold, which
   is what "each layout x each SAMPLES face fits its frame at font offsets -2..+2" asks for.
3. **The clock role's fields** (`bar`, `barFill`, `ring`) are named here, because T98 is the
   resolver that reads them. Flat's role (T94) already has `bar`. T100, T103 and T108 set
   `barFill` or `bar` for their accent or mana-blue bars. `UI.Styles.Validate` does not check
   these three fields; the resolver checks `bar` and `barFill` with its own colour test and falls
   back to black and to the source colour.
4. **No white 2-s tick on the spark.** ElvUI's spark sweeps the 2-s regen tick in white after the
   rule. Neither line keeps the tick's phase (TBC's `RegenModel` and Forever's model have none), so
   after the five seconds the spark is hidden. A tick source would be a `draw.tick(now)` the view
   could read.
5. **`clockui` has 16 checks per flavour, not the row's six bullets.** The extra checks are the
   resolver's paint, the sources, the spark, the line layout's geometry, the region pool and the
   dump line, all of which T98 builds.
6. **The Forever hover's bar sentence follows the source.** That sentence is in an owned file and
   would otherwise be untrue under any non-default source. The default words are unchanged.
7. **No slash command for the layouts.** `/st clock layout|look|preview` are T102's (from
   `UI/ClockSettings.lua`, re-basing `slashcheck/tbc`). Until then the look is changed through
   `SpellTuner.ClockView` (TESTING item above).
8. **The fixture rebuild is the integrator's.** `tools/data/import-forever-sv.lua` is generated and
   not in the owned files. It changes by the one registered default.
