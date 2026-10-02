# F1 -- the clock bar's Height, and a smooth five-second rule

Branch `fix/F1`, from `2ffece3` (0.16.6). Files: `UI/ClockView.lua`,
`tools/clockui.lua`, this file. No new option, no new source (the clock's v2
mockup is drawn in parallel).

## The symptom, in the author's words

On 0.16.6, Settings -> Clock -> Bar tab, Bar layout, Source "Five-second
rule", Height 14:

* "the height does not really change anything"
* "5-sec rule bar - I like it but the fillment should be more smooth"

## The cause

**Height.** `UI/ClockView.lua`'s `METRICS.bar` (parent line 527) returned
`barH = h - 4`, the frame's height less 4: the Height setting
(`look.bar.height`, `bar.height` in `CV.OVER`, 2..24) was never read on the
Bar layout. Only `METRICS.line` and `METRICS.compact` read it. The slider
saved its value and fired `CLOCK_LOOK`, but the bar layout drew the same bar
whatever it said.

**Smoothness.** `View:PaintBar` (parent line 804) is the only thing that sets
the bar's value and the spark's place, and it runs at the line's paint:
Forever's `MD:OnTick` (every 0.5 s, `UI/Clock_Forever.lua:350`), TBC's widget
OnUpdate throttled to 10 a second (`UI/Widget.lua:144`, `:173`). So the
five-second rule's bar stepped in 0.5 s jumps on Forever (10 steps over the
rule) and 0.1 s jumps on TBC.

## The fix

* `METRICS.bar`: the bar is the Height setting. The frame is
  `max(look.height, text + 6, bar + 4)` tall -- at least as tall as its text
  needs; the bar (already anchored CENTER) sits centred behind the text when
  it is shorter than the frame, and the frame grows 2 px round it when it is
  taller. The default (14 on an 18-px frame) draws as before wherever the text
  fits in 18 px.
* The per-frame step (`View:WantsSmooth`, `Smooth`, `Step`, `MoveSpark`): an
  OnUpdate on the view's **bar** (never on the line's frame), the function made
  once per view in `CV.Build` (`v.step`), installed by `PaintBar` while the
  source or the spark is the five-second rule and the rule runs
  (`draw.fsr(now) > 0`). Each frame it sets only the bar's value (source `fsr`)
  and the spark's point, from the line's own `draw.fsr(GetTime())` -- TBC
  `MD.Regen:FSRRemaining()`, Forever the model's `lastSpend + 5 - now`. When
  the rule ends it sets the bar full in the regen colour, hides the spark and
  removes itself. It is removed when the look stops wanting it (`ShowBar`, run
  by every `SetLook`: a source change, source none), when `PaintBar` draws no
  bar, and by `FillBar` (TBC's unlock preview, so the accent bar is not
  overwritten). No Show / Hide of the frame, no allocation per frame, nothing
  else repainted; the line's own paint is unchanged.

Both lines go through the one renderer, so both get both fixes; nothing
branches on the client.

## Tests

`tools/clockui.lua`, a new section "F1: the bar's height and the smooth
five-second rule", three assertions:

1. every layout (line, compact, bar) with source fsr draws its bar at 6, 14
   and 24 (two heights, two bars), fitting the frame (`Misfit`); the bar
   layout's default bar is 14;
2. bar and spark move on each of eight 0.03 s steps between two line paints
   (under TBC's 0.1 s and Forever's 0.5 s), the value on the rule's track;
3. the step ends with the rule (full, green, no spark, no OnUpdate), the same
   function is installed again (nothing allocated), a source change and source
   none remove it, the spark alone still sweeps and the step never moves
   another source's value.

| suite | parent `2ffece3` (test commit) | fix |
|---|---|---|
| clockui / tbc | 16 ok, 3 failed | 19 ok |
| clockui / forever | 16 ok, 3 failed | 19 ok |
| clocksettings / tbc | 34 ok | 34 ok |
| clocksettings / forever | 35 ok | 35 ok |
| ttocheck / tbc | 50 ok | 50 ok |

The parent's failures: `bar: height 6 drew 15 (frame 200x19)`;
`0 of 8 frames moved` (Forever), `2 of 8 frames moved` (TBC);
`installed false`.

`make check` green (`clockui` 19 / 19 noted against the expected 16 / 16),
`python3 tools/apicheck.py` 0 findings, `python3 tools/textcheck.py` 0
findings.

## For the integrator

* `tools/data/expected-counts.json`: `"clockui/forever": 19`, `"clockui/tbc": 19`.
* `docs/TOOLS.md`, the `clockui.lua` row: `(T98, tbc 16 / forever 16` ->
  `(T98, F1: tbc 19 / forever 19`, and at its end: `; F1: every layout draws
  its bar at the Height setting (6 / 14 / 24), the five-second rule's bar and
  spark moving every frame between two paints, the per-frame step gone when
  the rule ends or the source changes`.
* `CLAUDE.md`, the `UI/ClockView.lua` row, at its end: `**F1:** the bar layout
  draws its bar at the Height setting (centred behind the text, the frame
  growing round a taller bar); while the five-second rule runs an OnUpdate on
  the bar (View:Step, made once per view) moves the bar's value and the spark
  every frame from draw.fsr(now), removed when the rule ends, the look stops
  drawing the rule or the preview fills the bar`.
* `docs/TESTING.md`: Settings -> Clock -> Bar, Bar layout: drag Height 2..24 --
  the bar changes on the Bar layout too; cast a spell with Source
  "Five-second rule" (and the spark on): the bar fills smoothly, not in steps.
* No TOC line changes.
