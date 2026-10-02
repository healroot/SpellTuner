# T115 -- Clock v2: mana and the five-second rule together, the frame's size, the smooth strip (C2, C3, C4, C6)

Status: **ready** 2026-10-02, the clock v2 round of `docs/SPEC-next.md` section 13 (the author's
answers to `docs/mockups/clock-v2.html`). Runs beside T114 (no shared file); T116 builds on it.

## The task (docs/mockups/clock-v2.html C2, C3, C4, C5's Frame / Bars / Colours tabs and rule chips, C6; docs/SPEC-next.md 13, 7.2-7.4)

> Both mana and the five-second rule visible at once, on every layout and both lines, in three
> designs the player picks from -- **A** two bars (the default), **B** one bar with the 5SR veil,
> **C** a mana bar and a cooldown-swipe chip. The bar sources of 0.16.6 (Your mana / Modelled
> mana / Time to OOM / Five-second rule / None), the Horizon and the Spark go; **Bars**, **Join**
> and **Mana from** replace them, and a saved look is read as C4's table says. **Height** moves to
> the Frame tab beside **Width** and **Scale**, per layout, each with its minimum, and its pixels
> go to the mana bar. The 5SR fill moves every frame (F1's step, reused).

Owned files (the only files edited, apart from this one):

- `UI/ClockView.lua`
- `UI/Widget.lua`
- `UI/Clock_Forever.lua`
- `UI/ClockSettings.lua`
- `Engine/RegenModel.lua`
- `tools/clockui.lua`
- `tools/clockfacecheck.lua`
- `tools/clocksettings.lua`
- `tools/ttocheck.lua`
- `tools/clockcheck.lua`
- `tools/stylecheck.lua`
- `tools/wowstub.lua` (only to add a `Cooldown` frame that records `SetCooldown` / `Clear`, if the
  stub's fallback does not already record them)

The author's answers used here (`docs/SPEC-next.md` 13, verbatim "We can do all 3, and let user
decide / And those that are recomended become default"):

- **Answer 1:** all three designs are built as choices. **A (Stacked) is the default**; B (One
  bar, the veil) and C (Swipe chip) are options. The mockup said C would not be built unless asked
  for: it was asked for.
- **Answer 2:** the default is **Mana + 5SR on both lines**, replacing decision 15 (a) (5SR on
  TBC, the pool on Forever). A saved look keeps what it chose (C4's table, below).
- **Answer 5:** after the rule the strip stays **full green** by default. The 2-s regen-tick
  sweep is an option **only where the tick can be known**: on TBC, learned from mana gains; on
  Forever it is not offered, and the control's tooltip says why.
- Everything else as the mockup recommends: Time to OOM, Horizon and Spark removed as bar options;
  Height on the Frame tab; width / height / scale per layout with minimums; the smooth fill.

## What to build

### The store: new keys, the old ones read once (`UI/ClockView.lua`)

`db.clockLook = { layout, over }` keeps its shape; **no new default is registered** (`over` stays
sparse, 7.3), so `defaultscheck` and the import fixture do not move. `CV.OVER` gains keys of
three levels (`Get` / `CV.Set` take any depth; the resolved look is still a copy):

| key (`over.`) | values | default (both lines) |
|---|---|---|
| `bars.<layout>.show` | `both` (Mana + 5SR) / `mana` (Mana only) / `fsr` (5SR only) / `none` | `both` |
| `bars.<layout>.join` | `stacked` (A) / `veil` (B, One bar) / `chip` (C, Swipe chip) | `stacked` |
| `bars.<layout>.order` | `manaOver` / `fsrOver` (stacked only) | `manaOver` |
| `bars.<layout>.mana` | `game` / `model` (Forever only; TBC has no model) | `game` |
| `bars.<layout>.fsr` | 1-8 px, the strip's thickness | 3 |
| `bars.<layout>.after` | `green` / `empty` / `tick` (TBC only, answer 5) | `green` |
| `bars.<layout>.texture` | `flat` / `statusbar` (`UI-StatusBar`) / `raid` (`Raid-Bar-Hp-Fill`); Forever `flat` only until Q-clock-4 | `flat` |
| `frame.<layout>.w` / `.h` | pixels, per layout's range (below) | the layout's default |
| `frame.<layout>.scale` | 50-200 (%) | 100 |
| `colors.manaBar` | `mana` (mana blue) / `tone` / `class` / a colour | `mana` |

`panel.fill`, `panel.edge`, `bar.back` and `colors.<tone>` stay as they are. `bar.source`,
`bar.spark`, `bar.horizon`, `bar.height` and `bar.color` leave `CV.OVER`.

**`CV.Migrate(stored) -> changed, dropped`** (pure; idempotent; run once at login on
`db.clockLook` by this file, and harmless again). It reads 0.16.6's keys as the mockup's C4 table
says, writes the new keys into **each of the three layouts** (0.16.6's bar keys were global), and
removes the old ones:

| 0.16.6 saved | read as |
|---|---|
| `bar.source` not set (the line's own) | nothing written: the new default, Mana + 5SR |
| `bar.source = "pool"` | `show = "mana"` |
| `bar.source = "model"` | `show = "mana"`, `mana = "model"` (on TBC, where `model` was refused, `show = "mana"` only) |
| `bar.source = "fsr"` | `show = "fsr"` |
| `bar.source = "time"` | nothing written: Mana + 5SR (the source is gone) |
| `bar.source = "none"` | `show = "none"` |
| `bar.color = "source"` | dropped (the default) |
| `bar.color` = `tone` / `class` / a colour | `colors.manaBar` = the same |
| `bar.spark`, `bar.horizon`, `bar.height` | dropped |

A key already in the new shape is never overwritten. When anything was dropped, a lazy dump line
says it once per session, `clock: 2 old clock keys dropped (bar.horizon, bar.spark)` (the count and
names are what was found; through `MD:AddDumpLine`, T94's lazy rule), and `CV.DumpLine()` keeps
listing the overrides in the new names.

**The resolver** (`CV.Resolve`, pure) resolves `look.bars` and `look.frame` for the layout on
screen: the layout's defaults <- the style's `clock` role <- `over` (as T98). `CV.SourceOK` becomes
`CV.BarsOK(layout, bars, facts)`: `mana = "model"` needs `facts.model`; `after = "tick"` needs
`facts.tick` (TBC); a texture other than `flat` needs `facts.textures` (TBC true; Forever false
until Q-clock-4); the ring rule (the game's pool cannot be drawn on a ring where it is only drawn)
is kept for T104. A refusal falls back to the default and is named in `look.refused`.

### The layouts' sizes (C2)

| layout | default W x H (both lines) | minimum (at the default text) | ranges offered | Height's pixels go to | Width's pixels go to |
|---|---|---|---|---|---|
| line | **180 x 32** (was 180 x 30) | 150 x 30; 100 x 30 with no secondary | W 100-400, H 26-80 | the mana bar (text fixed) | both bars; the secondary stays at the right edge |
| compact | **72 x 46** (was 72 x 36, no bar) | 64 x 42 (+12 with a Bottom slot, T116) | W 60-300, H 36-120 | the mana bar | the bars; the number stays left |
| bar | **200 x 22** (was 200 x 18) | 120 x 20 | W 100-400, H 16-60 | the mana bar (the text sits in it, centred) | the bar |

- **The minimum is measured** in the clock's own fonts (as T98's Compact and Bar already measure
  `CV.VALUE_SAMPLE` and the label), so a bigger text (T116's Size) raises it. `View:Minimum() ->
  w, h` is what Settings marks. A size under it stops at it; `look.refused["frame.<layout>.w"]`
  says `under this layout's minimum (150)`.
- **The text keeps its size; the mana bar takes every pixel the text does not**, and the 5SR strip
  keeps its own thickness (`bars.fsr`). Line at the default: text row, mana 4 px, a 1-px black
  gap, the strip 3 px (Line 32 -> 44 gives the mana bar 16 px, the text unchanged). Bar: the mana
  bar is `H - strip - gap - 2` with the text centred in it (default 22: bar 16, strip 3; 30: bar
  24; the mockup's 32 at Size 14: bar 26). With `show = "fsr"` the strip takes the mana bar's place and height
  (0.16.6's TBC look, smooth). With `show = "none"` the frame is the text's (Line's minimum
  height applies).
- **Scale** (`frame.<layout>.scale`, the clock only, 50-200 %) is `SetScale` on the line's frame,
  applied when the slider is released (spec 7.4). The clock's centre stays where it was: each line
  converts its saved point (TBC `db.pos`, Forever `db.clock.point`, which the EllesmereUI mover
  also writes) by old / new scale when the scale changes, as T51 does for windows.
- A layout switch keeps the frame's shown state (T98's rule); width, height and scale are each
  layout's own.

### The three designs (C3), on every layout

The constraint the mockup states: on Forever the mana fill is drawn by the game from a secret and
SpellTuner never learns where it ends, so **nothing is placed at the fill's edge**. Every 5SR mark
is placed by **time alone** -- seconds since the line's last spend (TBC `MD.Regen:FSRRemaining()`;
Forever the model's last *priced* spend, a free cast does not start it) -- and drawn the same over
any fill. The mana bar's **colour** is ours on both lines; its **length** is the game's on Forever.

- **A, Stacked (default).** The mana bar (mana blue; Forever the game's real pool through
  `MD.API.DrawUnitPower`, never read; TBC `UnitPower` / `UnitPowerMax` read plain), a 1-px black
  gap, the 5SR strip: amber filling left to right over the five seconds, then full green while
  regen runs. `order = "fsrOver"` swaps them.
- **B, One bar (the veil).** One mana bar. While the rule runs, an amber veil covers the bar's
  right part, `width = barW * remaining / 5`, anchored to the bar's right edge, draining to the
  right as the seconds pass; after the rule a 1-px green line along the bar's top. The mockup
  draws the veil hatched; the kit ships no art, so it is a flat amber at 0.45 alpha with a 1-px
  amber edge at its left boundary (say so in the file; a hatch texture is a later art question).
- **C, Swipe chip.** One mana bar plus a square left of the label -- 10 px on Line (the label moves
  13 px right), 9 px on Compact, the bar's height on Bar -- holding a `Cooldown` frame
  (`CreateFrame("Cooldown", nil, chip, "CooldownFrameTemplate")`): `SetCooldown(lastSpend, 5)` on
  each spend, which the client animates every frame on both clients; after the rule the chip turns
  green (`after = "empty"`: an empty chip). The template on TBC 20506 and Forever is VERIFY in
  game (TESTING item).
- **After the rule** (`bars.after`): `green` (default) the strip full green, the veil's green line,
  the chip green; `empty` none of those; `tick` (**TBC only**) a white mark sweeping the green
  strip once per 2-s regen tick, from `MD.Regen:RegenTick()` (below); until a tick is learned the
  strip stays green. On Forever the option is not in the list and the Bars tab's After-rule
  tooltip reads `Forever cannot read your mana, so the 2-second regen tick cannot be learned: the
  strip stays green.`
- **Mana from** (`bars.mana`, Forever only): `game` (default) or `model` -- the model's pool, drawn
  from the face's plain `pct`, at 0.6 alpha with the hover saying `~ modelled`.
- **Colours.** `colors.manaBar`: mana blue by default; `tone` = the face's (on Forever the
  *modelled* tone over the game's fill, 0.16.6's rule); `class`; a swatch. A style's `barFill`
  (Ellesmere's accent, T100) tints the **mana bar only**; the 5SR strip, veil and chip keep amber
  and green under every style, so their meaning never changes with the look.
- **Texture** (`bars.texture`): `flat` (`UI.whiteTexture`); TBC also `Interface\TargetingFrame\
  UI-StatusBar` and `Interface\RaidFrame\Raid-Bar-Hp-Fill`; Forever `flat` only until Q-clock-4.
- Compact gains both bars by default (it had none).

### The smooth fill (C6)

F1's per-frame step (`View:WantsSmooth`, `Smooth`, `Step`, `MoveSpark`; one function per view,
an OnUpdate on the view's bar, never on the line's frame) now drives **the strip's value and the
veil's width**: `(now - lastSpend) / 5`, one `SetValue` / `SetWidth` per frame, no allocation,
installed while the rule runs and removed when it ends (strip full green or empty by `after`),
when the look stops drawing the rule, and by the preview's `FillBar`. The words keep their own
cadence (TBC 0.25 s, Forever 0.5 s). A new spend restarts the strip at 0 at once (the rule, not a
stutter). The chip needs no step (the client animates it). `tick`: the same step sweeps the
white mark while a tick is known. The **mana bar** is redrawn at the line's paint as today (TBC
0.1 s, Forever 0.5 s): unchanged.

The spark (`bar.spark`, `CV.SPARK_*`) is removed with its option (the mockup's "Not proposed").

### `UI/Widget.lua` (TBC)

- Facts: `poolPlain = true`, `model = false`, `tick = true`, `textures = true`; the line's
  `source` fact is gone (the default is the same on both lines now).
- `draw`: `pool(bar)` (`UnitPower` / `UnitPowerMax`), `fsr(now)` (`MD.Regen:FSRRemaining()`),
  `spend()` (the time of the last spend, for the chip: `RM.fsrEnd - 5`), `tick(now)`
  (`MD.Regen:RegenTick()`).
- `widget.bar` is the mana bar, `widget.strip` the 5SR strip (both the view's); the unlock preview
  fills the mana bar in the accent and the strip green.
- Its point converted on a scale change (above).

### `UI/Clock_Forever.lua` (Forever)

- Facts: `poolPlain = false`, `model = true`, `tick = false`, `textures = false`.
- `draw`: `pool(bar)` (`MD.API.DrawUnitPower(bar, "player", 0)`), `model()` (the face's `pct`),
  `fsr(now)` (`model.lastSpend + 5 - now`), `spend()` (`model.lastSpend`).
- The hover's bar sentence names what is drawn, by default: `The bar is your real mana, drawn by
  the game; the strip under it is the five seconds after your last priced cast.` (One bar: `the
  amber veil ...`; Swipe chip: `the square ...`; Mana from the model: `your modelled mana (~)`.)
- `Clock.bar` is the mana bar, `Clock.strip` the strip; its point converted on a scale change.

### `Engine/RegenModel.lua` (TBC): the regen tick, learned

`RM:RegenTick() -> lastTickTime, period | nil`. Every mana **gain** on `UNIT_POWER_UPDATE` (in and
out of combat; a gain is any rise the five-second rule does not explain) is timed; when the last
two intervals between gains are each within 2.0 +- 0.15 s and the latest gain is under 4 s old,
the tick is known (period 2.0, phase the latest gain). Anything else answers nil. Nothing else in
the model reads it. VERIFY in game (TESTING item): drinking and potion gains are irregular and
answer nil.

### `UI/ClockSettings.lua`: the Frame, Bars and Colours tabs, the rule chips (C5)

The box keeps 0.16.6's vertical tabs; **Show** stays as it is (T116 replaces it with Text).

- **Frame:** Width, Height, Scale (sliders over the layout's ranges, the layout's minimum drawn as
  a green mark with `min N` beside; Scale written on mouse-up), Background (swatches + alpha),
  Border (swatches / none). Each writes `frame.<layout>.*` / `panel.*` through `CV.Set`. Note
  under the box: `Width, height and scale are kept per layout.`
- **Bars** (replaces **Bar**): Bars (Mana + 5SR / Mana only / 5SR only / None), Join (Stacked /
  One bar / Swipe chip), Order (Mana over 5SR / 5SR over mana; Stacked only), Mana from (The game /
  The model; Forever only), 5SR thickness 1-8, After the rule (Green / Empty, and Regen tick on
  TBC; on Forever the tooltip above), Texture (Flat, and the two client bars on TBC; on Forever
  `Flat (others wait for the probe)`). Writes `bars.<layout>.*`.
- **Colours:** **Mana colour** (Mana blue / By tone / Class colour / a swatch) replaces the bar
  colour row; the tones and the bar background stay.
- **The preview** gains a rule chip row under the state chips: `in the rule, 3.0 s left`, `just
  cast`, `regen running`. A chip drives the preview's own `draw.fsr` / `draw.spend` so the strip,
  veil or chip animates as in game (the step runs on the preview's frame, never the widget's).
  The preview's illustrative pool fill stays `CS.SAMPLE_POOL`.
- Height no longer appears on the Bar tab (its 0.16.6 place); the old Source dropdown, Spark and
  Horizon are gone.
- Commands keep their shape (`/st clock layout|look reset|preview`, `/md clock ...`):
  `slashcheck/tbc` unchanged.

## The checks (fail first on the parent, then green)

Commit the suites first and run them against the parent; the new checks fail there, the re-based
ones are listed with what they assert now.

**`tools/clockui.lua`** (tbc / forever, 19 -> **32** each, measured: on the parent 8 ok / 24 failed
on tbc, 7 / 25 on forever): T98's section 5 (source none), 6 (sources), 7 (spark), 8 (sources by line) and F1's
three are re-based on Bars; the rest kept. New and re-based checks:

1. Defaults: every layout draws mana + strip, stacked, mana over 5SR, 3-px strip, green after;
   Line 180 x 32 (text row, mana 4, gap 1, strip 3), Compact 72 x 46, Bar 200 x 22.
2. Each of the 14 `SAMPLES` faces fits each layout x each join x each `show` at font offsets
   -2..+2 (inside the frame, no overlap, no text over a bar beside it).
3. Height: Line 32 -> 44 gives the mana bar 12 px more and moves no text; Bar 22 -> 30 grows the
   bar; the strip keeps its thickness.
4. Width stretches both bars; the secondary stays at the right edge.
5. The minimum: a width / height under it stops at it and is named; `View:Minimum()` equals the
   measure; a bigger font raises it.
6. Scale: `SetScale` per layout, 50-200 %; the frame's centre unchanged across a scale change
   (TBC `db.pos`, Forever `db.clock.point` converted).
7. Stacked mid-rule (3.0 s left): strip 2/5 amber; after: full green; `after = empty`: empty.
8. Veil: width = barW x remaining / 5 at the right edge, every frame; after the rule a 1-px green
   top line; `empty`: none.
9. Chip: `SetCooldown(lastSpend, 5)` once per spend (spied), green after; the label moves 13 px on
   Line.
10. The smooth step drives the strip and the veil on each of eight 0.03 s frames between two line
    paints; it is gone at the rule's end, on a join / show change, and under the preview's
    `FillBar`; one function per view (nothing allocated).
11. `show = "fsr"`: the strip in the mana bar's place; `none`: no bar, no strip, no chip.
12. A style's `barFill` tints the mana bar only; the strip keeps amber / green; an override wins;
    Reset to style restores; Flat paints today's panel.
13. `colors.manaBar = "tone"`: crit red on the mana bar.
14. Tick (TBC): with `RM:RegenTick()` answering, a white mark sweeps the strip over 2 s after the
    rule; without, green. Forever: `after = "tick"` refused with its reason.
15. Mana from the model (Forever): the bar holds the face's plain `pct`; refused on TBC.
16. Texture: TBC applies each; Forever refuses all but `flat`.
17. Every Show / Hide on the frame from the visibility owner (counted by caller), across joins,
    shows, sizes and scales; a switch keeps the shown state.
18. Forever under the forever profile: every layout x join x show x mana-from paints in a fight
    without raising; only the mana bar (`game`) holds the secret; the strip, the veil and the chip
    hold plain numbers; nothing reads the bar's value.
19. The dump line names the new keys (`clock: layout line, 2 overrides (bars.line.join, frame.line.h)`).

**`tools/clockfacecheck.lua`** (tbc 22 -> **24**, forever 19 -> **21**): section 6 re-based on
`bars` / `frame` (over wins over the role, the role over the layout's defaults; Reset to style);
new: **6c** `CV.Migrate` -- every row of C4's table on a 0.16.6-shaped store (written into all
three layouts, a new key never overwritten, TBC's `model` read as Mana only), the dropped names
returned; **6d** migrate twice equals migrate once, and the resolved look after it equals the
resolved look of the hand-written new keys.

**`tools/clocksettings.lua`** (tbc 34 -> **39**, forever 35 -> **40**, measured): the Bar tab's
checks re-based on Bars; new: the Frame tab's three sliders write `frame.<layout>.*` and the
widget rebuilds; the minimum mark equals `View:Minimum()`; Scale writes on mouse-up only; Join's
three values; Mana from offered on Forever only; After the rule offers Regen tick on TBC only and
the Forever tooltip's words; Texture's list per line; Mana colour writes `colors.manaBar`; the
rule chips animate the preview's strip and never touch the widget; the old Source / Spark / Horizon
controls are gone.

**`tools/ttocheck.lua`** (tbc 50 -> **52**): section 12 re-based (the panel 180 x 32, a 160 x 4
mana bar and a 160 x 3 strip under it, the strip amber in the rule and green after; the label,
value and secondary at their T93 places, unmoved); section 13 (the preview fills the mana bar in
the accent); new: `RM:RegenTick()` learned from scripted gains 2.0 s apart; nil for irregular
gains.

**`tools/clockcheck.lua`** (forever 35 -> **36**): the backing check re-based (mana bar 160 x 4 and
the strip, both backed, re-snapped on a scale change); new: the hover's bar sentence by join.

**`tools/stylecheck.lua`** (34 both, count unchanged): the clock section's golden **re-based**
(the new default regions: mana bar, gap, strip; 180 x 32), captured from this task's paint and
listed region by region below; every other section byte-identical, Flat's round trip
included. A DECISIONS line records the re-base.

**Unchanged:** `clocktextcheck` (T114's, if merged first), `surfacecheck`, `euicheck` (but its one size number, below),
`minimapcheck`, `restylecheck`, `slashcheck/tbc`, `defaultscheck` (no default registered),
`importcheck` (no fixture rebuild), `regencheck`, `consolecheck`. `make check` green, apicheck 0
findings, textcheck 0 findings.

The re-based golden (`--golden`; tbc `clock = { 17, 1258458495 }`, forever
`clock = { 17, 1154631320 }`, was `{ 8, ... }`), the 17 regions in creation order (`--print`):

1. Frame -- the panel, 180 x 32, the kit's pixel backdrop (bg, border; Forever hidden until shown)
2. FontString -- the label (shown)
3. FontString -- the label slot's measuring probe (hidden)
4. FontString -- the value (shown)
5. FontString -- the secondary (shown)
6. FontString -- the preview message (hidden)
7. StatusBar -- the mana bar, 160 x 4
8. Texture -- its back, black, one physical pixel wider each side (TBC 162 x 6)
9. StatusBar -- the 5SR strip, 160 x 3
10. Texture -- its back, black (TBC 162 x 5)
11. Texture -- the veil, amber at 0.45, 4 high (hidden: Join is stacked)
12. Texture -- the veil's edge, amber, one physical pixel wide (hidden)
13. Texture -- the green line after the rule, 1 high (hidden)
14. Frame -- the chip (hidden)
15. Texture -- the chip's fill, green
16. Cooldown -- the chip's swipe
17. Texture -- the tick mark on the strip, white, 2 physical px x 3 (hidden)

Every other section (nav, host, palette, text, fonts) byte-identical; Flat's round trip passes.

**`tools/euicheck.lua`** (forever 19, count unchanged): check 12's mover size `180 x 30` -> `180 x
32` (the clock's new default height); one number, nothing else.

## Integrator lines

- **TOCs:** none.
- **`tools/data/expected-counts.json`:** `clockui/tbc` 32, `clockui/forever` 32,
  `clockfacecheck/tbc` 24, `clockfacecheck/forever` 21, `clocksettings/tbc` 39,
  `clocksettings/forever` 40, `ttocheck/tbc` 52, `clockcheck/forever` 36 (`stylecheck` 34 and
  `euicheck/forever` 19 unchanged).
- **`CLAUDE.md`:** `UI/ClockView.lua`'s row: `**T115 (clock v2, C2-C4, C6):** Bars (both / mana /
  fsr / none), Join (stacked -- the default, A -- / veil, B / chip, C, a Cooldown frame's swipe),
  Order, Mana from (game / model, Forever), the 5SR strip's thickness, After the rule (green /
  empty / tick, TBC), texture, colors.manaBar -- per layout under bars.<layout>; frame.<layout>.w /
  h / scale with each layout's measured minimum (View:Minimum), Height's pixels to the mana bar;
  the 5SR marks placed by time alone (never at the fill's edge); F1's step drives the strip and
  the veil every frame; CV.Migrate reads 0.16.6's bar.source / spark / horizon / height / color
  once (C4's table) with a lazy dump line; the spark and the time source removed; decision 15 (a)
  replaced: Mana + 5SR on both lines`. `UI/Widget.lua` / `UI/Clock_Forever.lua` rows: their new
  `draw` (`spend`, `tick` on TBC; Forever's modelled mana is the face's plain `pct`), `bar` / `strip`, the point kept on a scale
  change, the hover's sentence (Forever). `Engine/RegenModel.lua`: `**T115:** RM:RegenTick() --
  the 2-s regen tick learned from mana gains (two intervals within 2.0 +- 0.15 s, the latest under
  4 s), read only by the clock's After the rule = tick`. `UI/ClockSettings.lua`: `**T115:** Frame
  (Width / Height / Scale with the minimum mark, background, border), Bars replacing Bar, Mana
  colour on Colours, the rule chips in the preview`. The `tools/` row: the counts.
- **`docs/TOOLS.md`** section 1: the `clockui`, `clockfacecheck`, `clocksettings`, `ttocheck`,
  `clockcheck` rows (counts and the new sections), `stylecheck`'s re-based clock golden (17
  regions), `euicheck`'s mover size 180 x 32.
- **`docs/DECISIONS.md`**, one entry:

  > ## Clock v2: mana and the five-second rule together (2026-10-02, T115, the author's answers to clock-v2.html)
  >
  > Both bars are drawn by default on both lines and every layout: the mana bar over a 3-px
  > five-second-rule strip (design A). **This replaces decision 15 (a)** (the 5SR on TBC, the pool on
  > Forever). The veil (B) and the swipe chip (C) are options under Bars -> Join. Time to OOM, the
  > Horizon and the Spark are gone; a 0.16.6 look is read once as `clock-v2.html` C4's table says.
  > Every 5SR mark is placed by time alone, so it means the same over the game's secret fill on
  > Forever. Line is 180 x 32, Compact 72 x 46 with bars, Bar 200 x 22; Height gives its pixels to the
  > mana bar. After the rule the strip stays green; a regen-tick sweep is offered on TBC only,
  > learned from mana gains (Forever cannot read mana). `stylecheck`'s clock golden was re-based for
  > the new default regions.

- **`docs/TESTING.md`**, a new item: Settings -> Clock -> Bars on each layout: cast -- the strip
  fills amber smoothly and turns green; Join One bar: the veil drains right; Swipe chip: the
  square sweeps (VERIFY the template on both clients); Frame: Height 32 -> 44 grows only the mana
  bar, Width stretches, Scale 150 % keeps the clock's centre; a 0.16.6 look with Source "Five-second
  rule" reopens as 5SR only, Time to OOM as Mana + 5SR, and `/st dump` names the dropped keys once.
  TBC: After the rule = Regen tick, out of the rule a white mark crosses every 2 s (paste whether
  it lines up with the mana ticks).
- **`docs/HISTORY.md`:** the round's entry names T115.

## Out of scope

- The text slots, the Text tab, size / outline / shadow / numbers (T114, T116).
- The Ring layout (T104): `CV.BarsOK` keeps the ring rule only.
- Forever textures (Q-clock-4) and a hatched veil (no art in the kit).
- A smoother mana fill: the mana bar keeps the line's paint cadence.
- A spark riding the mana fill's edge on Forever (would need the game to place it from the
  secret: a probe question, not a plan).
