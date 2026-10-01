# T93 -- Clock parity (K2)

Status: **built** 2026-10-01 on branch `next/T93` (base `231525d`), wave N2 of
`docs/SPEC-next.md`, beside T92, T94, T95 and T96. It awaits the integrator.

**The branch needs its TOC lines and a fixture rebuild (below).** `UI/ClockView.lua` must go on
the three main TOCs, which are integrator-owned. `UI/Widget.lua` and `UI/Clock_Forever.lua` now
draw through it. Without the lines, 11 Forever runs fail on the committed tree (listed under "The
checks"). `UI/Clock_Forever.lua` registers two new `db.clock` defaults, so the generated
`tools/data/import-forever-sv.lua` gains two lines; it is not in this task's owned files, so it is
rebuilt by the integrator. The TOC lines and the rebuilt fixture were applied in the working tree
only to run the suites, then reverted before the commit.

## The task (docs/SPEC-next.md section 11, row T93; 7.1, 7.3, 2.4, 6.3; R-clock.md 2 and 10 K2)

> **Clock parity (K2).** F1 tones on Forever; F2 fixed segments on both (`ClockFace.Segments`); F3
> `manaUsersOnly`; F4 click-through; F5 pulse; F6 rest toggle; `Visibility.Want(..., rule)` with
> today's default; the renderer `UI/ClockView.lua`; the mover seam (`ApplyPoint`,
> `ResetPosition`, `Preview`) exposed on both clocks. New `db.clock` / TBC keys reported for
> `defaultscheck`.

Owned files: `Engine/ClockFace.lua`, `UI/ClockView.lua` (new), `UI/Widget.lua`,
`UI/Clock_Forever.lua`, `UI/Visibility.lua`, `tools/clockcheck.lua`, `tools/ttocheck.lua`,
`tools/clockfacecheck.lua`. Nothing else was edited (apart from this file).

The author's answers used here (`docs/SPEC-next.md` 9.1: every decision not named there as
recommended): decision 14 (a) fixed segments; decision 16 the Forever clock gets TBC's tones,
TTO's literals under Flat, no `vv` on Forever; decision 17 the same left-click rule on TBC;
decision 18 all of F3-F6.

## What was built

### `Engine/ClockFace.lua` (pure, both lines)

- **`CF.Segments(face, look)`** cuts a face into the three pieces a layout draws:
  - `label` `{ text, tone }`: `OOM`, `FULL`, `~OOM`;
  - `value` `{ text, tone, arrow, arrowTone }` or nil: `1:20` + `v`, `>1:50` + `=`, `...`, `--`;
    nil beside a lone `FULL`;
  - `second` `{ text, tone }` or nil: `rest 2:10`, `inn 2:15`.

  The pieces carry plain text and tone names, never colour codes. Each tone is the one `LineString`
  paints that piece with:
  - in the crit band the whole line is red, label included, and keeps its `vv`;
  - a bound and a warm-up are muted throughout;
  - otherwise the label is muted, the value takes its band's tone (or muted, with `~`, when it is
    unstable), and the arrow takes its own tone.

  `look.show.rest == false` drops a `rest` secondary (F6), and `look.show.cd == false` drops a
  cooldown one. With no look, or no switch, the piece is kept. A face's `mono` is not read here:
  the renderer always colours (F1). The Forever *string* (`ManaModel.Text`) stays mono, so its
  golden is untouched.
- **`CF.JoinSegments(segs)`** gives the plain line: the label, one space, the value and its
  arrow, two spaces, the secondary. It is byte for byte `LineString` without the colour codes.
  **`CF.ValueText(value)`** gives the value with its arrow.
- **`CF.ToneHex(tone, colors)`** and **`CF.ToneRGB(tone, colors)`** turn a tone into a colour.
  `colors` maps a tone to six hex digits and wins over `CF.HEX`; an unknown tone is `normal`.
- The file still loads with Lua's library only (clockfacecheck 1).

### `UI/ClockView.lua` (new, both lines): the renderer

`MD.ClockView.Build(parent, look) -> view` builds inside the line's own frame:

- **Three font strings at fixed places** (F2, decision 14; DECISIONS "Widget text
  left-anchored ... centred text slides"):
  - the label: the kit's font, `TOPLEFT` 8, -4, left-justified;
  - the value: the kit's **number** font (`UI.FONT_NUM`), `TOPLEFT` at a fixed x;
  - the secondary: the kit's font, `TOPRIGHT` -8, -4, right-justified.

  Each piece hangs on the frame, never on another piece. The value's x is the label slot: the
  widest label the line draws (`look.labelSample`: `FULL` on TBC, `~FULL` on Forever), measured
  in the label's font on a font string that is never shown, plus a 6-px gap. It is measured again
  at each paint, and the value is re-anchored **only** when that width changed (a font offset, a
  font that loaded late), never because the words changed.
- **`view:Paint(face, look)`** sets each piece's text and `SetTextColor` from its tone. The arrow
  is inline-coloured only where its tone differs from the value's. A piece with no text is hidden.
  A face that is not a table draws the warm-up's `OOM ...`, which is what the TBC widget showed
  before its first state.
- **`view:Message(text, r, g, b)`** draws one centred line (at T82's `TOP 0,-4`) instead of the
  pieces. It is the preview's `SpellTuner - drag me`.
- **`view:Text()`** gives the words as drawn, plain.
- **`view:Pulse()`** plays the pulse: four quarter-second fades, the animation that was
  `UI/Widget.lua`'s (F5).
- It never calls `Show` / `Hide` on the frame, reads no client value and reads no `MD.db`.

### `UI/Visibility.lua`

`Visibility.Want(pct, shown, inCombat, unlocked, rule, usesMana)` now takes a show rule:

- `rule = { combat = "always"|"never", ooc = "low"|"always"|"never", showBelow, hideAbove,
  manaUsersOnly }`.
- A field the rule leaves out comes from `Visibility.DEFAULT_RULE`
  (`{ combat = "always", ooc = "low", manaUsersOnly = true }`). The thresholds default to
  `SHOW_BELOW` / `HIDE_ABOVE`, read at each call.
- Being unlocked or previewed always wins.
- **`manaUsersOnly`** (F3): when `usesMana == false`, there is no clock, in combat too. `nil` (not
  known) does not hide.
- With no rule, or the default rule, the answer is the parent's on every case
  (clockfacecheck 5).

### `UI/Widget.lua` (TBC)

- The words: `MD.ClockView.Build(widget, look)` (`labelSample = "FULL"`, `show` from
  `db.showRest` / `db.showCooldown`) and `view:Paint(MD:GetClockFace(), look)` every 0.25 s. The
  bytes are `MD:GetDisplayString`'s: the face already obeys both switches.
- The preview is `view:Message(..., accent)`. `widget.pulse` is `view.pulse`. `MD:PulseWidget`
  and the once-per-fight flash (TBC's own rule on `GetManaState`, unchanged) call `view:Pulse()`.
- **Decision 17:** a left-click opens the window **out of combat only**. The hover's hint reads
  `open the window (out of combat)`.
- `MD:UpdateVisibility` asks `Want(pct, shown, inCombat, unlocked, nil, usesMana)`. The
  "no mana pool" gate that stood in front of it is now the shared rule's `manaUsersOnly`, with the
  same answer. The mana is still read only when the answer depends on it.
- **The mover seam:** `MD.Widget` holds `ApplyPoint()` (`MD:ApplyWidgetPosition`),
  `ResetPosition()` (`db.pos` = a copy of `MD.DEFAULTS.pos`, applied), `Preview(seconds)`
  (`MD:ForceWidgetPreview`, 0 ends it) and `frame`. It is provided as **`MD.ClockWidget`**.
- No new TBC key.

### `UI/Clock_Forever.lua` (Forever)

- `MD:RegisterDefaults({ clock = { showRest = true, clickThrough = false } })`: the file that
  reads the keys declares them. `shown` / `locked` / `point` stay `Core_Forever.lua`'s.
- **F1:** the words are `view:Paint(MD.ManaModel.Face(state, now), look)`, so the pieces take
  TBC's tones from `CF.HEX`: red under 20 s, amber under 60 s, label muted. There is never an
  arrow on Forever, so never `vv`. The label slot is `~FULL`.
- **F3:** `UpdateVisibility` passes `usesMana`. A warrior or rogue gets no clock, in combat
  too, except during a preview.
- **F4:** `db.clock.clickThrough`. `UpdateVisibility` sets
  `EnableMouse(Previewing() or not clickThrough)` on every pass, so a click-through clock takes no
  hover, click or drag except while it is being placed.
- **F5:** one pulse per fight, the first time the projection reads `oom` under 30 s while the
  clock is shown in combat. `PLAYER_REGEN_DISABLED` re-arms it. `MD:PulseWidget` (MD:Alert's)
  pulses this clock while it is shown.
- **F6:** `db.clock.showRest` reaches the view as `look.show.rest`.
- **The mover seam:** `Clock:ApplyPoint()` is new and public. `ResetPosition` and `Preview`
  already existed. `MD.Clock` is provided as **`MD.ClockWidget`**.
- **`/st clock rest`** and **`/st clock clickthrough`** are subcommands through
  `MD:AddSubcommand`. They let the author switch F4 / F6 until Settings -> Clock (T102); see
  Deviations 4. `/st clock` and `/st clock lock` are unchanged (corecheck/forever 29 ok).

## The checks

**Fails first on `231525d`.** The suites were committed alone as `4e5e981`, before any code
edit:

| Suite | On the parent |
|---|---|
| `clockcheck/forever` | 29 ok, **6 failed**: every new check |
| `ttocheck/tbc` | 45 ok, **5 failed**: checks 12-13 re-based to the segments, plus the 3 new |
| `clockfacecheck/tbc` | 17 ok, **3 failed** |
| `clockfacecheck/forever` | 14 ok, **3 failed** |

**`tools/clockcheck.lua`**, forever, 29 -> **35**. The six new checks:

1. **F1:** `~OOM 0:10` has its label and value in crit red and no arrow. `~OOM 0:45` has the
   value amber, `~OOM 1:20` has it white, and the labels are muted.
2. **F3:** with no mana pool there is no clock in combat. A mana user gets one, and a preview
   still shows it.
3. **F4:** click-through is off by default. On, `EnableMouse(false)`; while previewing,
   `EnableMouse(true)`; off again, `true`. `/st clock clickthrough` toggles it both ways and
   leaves `shown` alone.
4. **F5:** over a fight at 45 / 25 / 20 / 12 s the pulse plays once; the next fight plays one
   more; `MD:PulseWidget` plays once.
5. **F6:** `showRest` is on by default and reads `~OOM 1:20  rest 3:20`. Off, it reads
   `~OOM 1:20` with the secondary hidden. `/st clock rest` toggles it both ways.
6. **The mover seam:** `MD.ClockWidget == MD.Clock`; `ApplyPoint` applies the stored point;
   `ResetPosition` clears it and puts the clock at `TOP 0,-120`.

The suite reads the clock's words through a `ClockText()` helper: the view's segments joined, or
the message line, or the parent's `Clock.text`. The 29 old checks mean the same and pass on both
trees.

**`tools/ttocheck.lua`**, tbc, 47 -> **50**. It loads `UI/ClockView.lua` before the widget when
the file exists.

- **Check 12** reads the three segments: label `UI.FONT` at `TOPLEFT` -4, value `UI.FONT_NUM` at
  `TOPLEFT`, secondary `TOPRIGHT`, all on the widget.
- **Check 13** reads the message line: the preview in the accent with the segments hidden, then
  the segments back.
- Three new checks:
  - **14.** Label, value and rest stay at fixed x on the widget across `59s v` -> `1:00 v` ->
    `>10m v`. Every anchor is on the widget, and none is re-set during the three paints.
  - **15.** For the 14 `SAMPLES` and the three faces above, what the segments draw is
    `LineString`'s text byte for byte, `OOM 15s vv` included.
  - **16.** A left-click opens the window out of combat and not in combat. `MD.ClockWidget` is
    `MD.Widget`: `ResetPosition` writes a copy of `DEFAULTS.pos`, and `Preview(60)` shows the
    widget at full mana while `Preview(0)` ends it.

**`tools/clockfacecheck.lua`**, tbc 17 -> **20**, forever 14 -> **17**. It loads
`UI/Visibility.lua` with Lua's library only. The oracle is the parent's `Want`, copied.

- **5.** The default rule equals the parent's on 80 cases (10 mana fractions x shown x combat x
  unlocked) x 5 ways of asking: 4 args, `rule` nil, `DEFAULT_RULE`, `DEFAULT_RULE` with a mana
  user, and `{}`.
- **5b.** `ooc = "never"` gives `unlocked or inCombat`. Beside it, `ooc = "always"` is always
  true and `combat = "never"` is false in combat.
- **5c.** `manaUsersOnly`: with no pool the answer is `unlocked` only; with it off, the parent's
  answer; for a mana user, the parent's answer.

**Mutations** (each reverted):

| Mutation | Result |
|---|---|
| The value anchored to the label's `TOPRIGHT` instead of the frame | ttocheck 12 and 14 fail (`fixed=false`) |
| The `manaUsersOnly` line removed from `Want` | clockcheck F3 and clockfacecheck 5c fail |

### The whole check

`tools/check.sh` with the TOC lines and the rebuilt fixture: **77 runs, all passed; 72 counted
against 72 expected.** Four counts are higher than expected (NOTE, not FAIL):

| Count | Before | After |
|---|---|---|
| `clockcheck/forever` | 29 | **35** |
| `ttocheck/tbc` | 47 | **50** |
| `clockfacecheck/tbc` | 17 | **20** |
| `clockfacecheck/forever` | 14 | **17** |
| `apicheck` | 0 findings, 63 files | 0 findings, **64** files |
| `textcheck` | 0 findings, 102 files | 0 findings, **103** files |
| `defaultscheck` | tbc 49 (44 read), forever 52 (28 read) | **unchanged**: tbc 49 (44 read), forever 52 (28 read) |

`defaultscheck` does not move: the new keys sit under `db.clock`, which already had a default,
and no new top-level `MD.db.<key>` is read (`showRest` / `showCooldown` were already TTO's reads
on TBC). The "(N read)" figures for the parent were measured on an extract of `231525d`.

**Without the TOC lines and the fixture** (the committed tree), 11 Forever runs fail:
clockcheck, corecheck, measurecheck, minimapcheck, practiceforever, recordcheck, recordingscheck,
replayforever, spellsui and wincheck (each `/forever`; `MD.ClockView` is nil when the clock is
built), plus importcheck (the fixture). Every TBC suite passes either way.

## Integrator lines

**TOCs** (one new line each):

- `SpellTuner_TBC.toc`: `UI\ClockView.lua` right before `UI\Widget.lua` (after
  `UI\Visibility.lua`).
- `SpellTuner_Mainline.toc` and `SpellTuner.toc` (identical): `UI\ClockView.lua` right before
  `UI\Clock_Forever.lua` (after `UI\Visibility.lua`).
- No module TOC changes.

**`tools/data/import-forever-sv.lua`**: rebuild it after the TOC lines with
`bash tools/run.sh tools/importfixture.lua`. Under `["clock"]` it gains exactly two lines,
`["clickThrough"] = false,` and `["showRest"] = true,`. If another N2 task also rebuilds it (T96's
`kit.profile`), one rebuild after both merges covers both.

**`tools/data/expected-counts.json`**:

- `"clockcheck/forever": 35`
- `"ttocheck/tbc": 50`
- `"clockfacecheck/tbc": 20`
- `"clockfacecheck/forever": 17`

`tools/check.sh` needs nothing.

**`defaultscheck`**: counts unchanged, tbc 49 (44 read) and forever 52 (28 read). The new
Forever keys are `db.clock.showRest = true` and `db.clock.clickThrough = false`, registered by
`UI/Clock_Forever.lua`. There is no new TBC key.

**`CLAUDE.md`**:

- A new row before `UI/Widget.lua`'s:

  > | `UI/ClockView.lua` | **The clock's renderer, both lines** (T93, `docs/SPEC-next.md` 7.1 F2, decision 14): `MD.ClockView.Build(parent, look)` draws a face (`ClockFace.Segments`) into the line's own frame as three font strings at FIXED places -- the label from the left edge, the value and its arrow in the kit's number font at a fixed x (the label slot: `look.labelSample` measured in the label's font, re-anchored only when that width changes), the secondary right-aligned to the right edge -- each in its tone (`ClockFace.ToneRGB`, a look's `colors` winning); `view:Paint(face, look)`, `view:Message(text, r, g, b)` (the preview's centred line), `view:Text()`, `view:Pulse()` (the pulse animation, F5). Never Shows / Hides the frame, reads no client value and no `MD.db`. Both main TOCs, before `UI/Widget.lua` / `UI/Clock_Forever.lua`; T98 adds layouts and bar sources |

- `UI/Widget.lua`'s row, appended:

  > **T93:** the words through `UI/ClockView.lua` (three fixed segments, decision 14; the bytes `GetDisplayString`'s), the preview its message line, the pulse its; a left-click opens the window out of combat only (decision 17); the no-mana gate is the shared rule's `manaUsersOnly`; the mover seam `MD.Widget` (`ApplyPoint`, `ResetPosition`, `Preview`, `frame`), provided as `MD.ClockWidget`

- `UI/Clock_Forever.lua`'s row, appended:

  > **T93:** the words through `UI/ClockView.lua` from `ManaModel.Face`, in TBC's tones (F1, decision 16; never an arrow); no clock without a mana pool (F3); `db.clock.clickThrough` (F4: no mouse except while previewing); one pulse per fight under 30 s and `MD:PulseWidget` (F5); `db.clock.showRest` (F6) -- both keys registered here; `/st clock rest` / `clickthrough` subcommands; `Clock:ApplyPoint()` and `MD.Clock` provided as `MD.ClockWidget` (the mover seam)

- `UI/Visibility.lua`'s row, appended:

  > **T93:** `Want(pct, shown, inCombat, unlocked, rule, usesMana)` -- `Visibility.DEFAULT_RULE` (`combat` always, `ooc` low, `manaUsersOnly`), thresholds `showBelow` / `hideAbove`; the default rule is the old answer on every case (clockfacecheck 5)

- `Engine/ClockFace.lua`'s row, appended:

  > **T93:** `Segments(face, look)` -- label / value+arrow / secondary as plain text and tone names (`look.show.rest` / `.cd` drop a secondary), `JoinSegments` (LineString's plain bytes), `ValueText`, `ToneHex` / `ToneRGB`; `mono` stays LineString's only

- The "Widget visibility has a single owner" convention: unchanged in substance. Optionally add
  "(the rule's `manaUsersOnly` included; `UI/ClockView.lua` never shows or hides)".
- The `tools/` row: after `**tools/clockfacecheck.lua**`'s text, add `; since T93 (tbc 20 /
  forever 17) section 5: Visibility.Want's rule`. In the clockcheck / ttocheck mentions, note
  T93's checks as in `docs/TOOLS.md` below.

**`docs/TOOLS.md`** section 1:

- `ttocheck.lua` row: change `(T58, tbc, 47)` to `(T58, tbc, 50)` and append: `; (T93) the font
  check reads the three fixed segments and the preview is the view's message line; label, value
  and rest keep their x across 59s -> 1:00 -> >10m; the drawn segments are the line's bytes (vv
  included); a left-click opens the window out of combat only; the mover seam MD.ClockWidget`.
- `clockfacecheck.lua` row: change `(T88, tbc 17 / forever 14)` to `(T88, tbc 20 / forever 17)`
  and append: `; (T93) section 5: Visibility.Want with a show rule -- the default rule is the
  parent's Want on 80 cases x 5 ways of asking, ooc never (always, combat never), manaUsersOnly`.
- `clockcheck.lua` row: append `Since **T93** (35): the words read through UI/ClockView.lua's
  segments; F1 tones (~OOM 0:10 crit, no arrow), F3 no clock without a mana pool, F4
  click-through, F5 one pulse per fight and MD:PulseWidget, F6 the rest switch (with /st clock
  rest and clickthrough), the mover seam MD.ClockWidget`.

**`docs/DECISIONS.md`**: one entry with four paragraphs (decisions 14, 16, 17, 18):

> ## The clock: fixed segments, tones on Forever, the click rule, the Forever gaps (2026-10-01, T93, decisions 14, 16-18)
>
> **Fixed segments (decision 14).** On both lines the clock's text is three pieces at fixed
> places: the label from the left edge, the value in the kit's number font at a fixed x, and the
> secondary right-aligned to the right edge. When `OOM 59s` becomes `OOM 1:00` only the digits
> move. This restores "Widget text left-anchored ... centred text slides when the digit count
> changes" and reverses T82's centring. The words and colours are unchanged
> (`ClockFace.Segments` is `LineString` cut into pieces; ttocheck holds the bytes). The preview's
> `SpellTuner - drag me` stays centred.
>
> **Tones on Forever (decision 16).** The Forever clock is coloured as TBC's is, with TTO's
> literals: red from the label on under 20 s, the value amber under 60 s and white above, the
> label muted, FULL green, a warm-up or missing value grey. Forever has no arrow, so no `vv`.
> `ManaModel.Text` (the string) stays one colour.
>
> **Left-click on TBC (decision 17).** The TBC widget opens the window on a left-click out of
> combat only, as the Forever clock has since T70. The hover says `open the window (out of
> combat)`.
>
> **The Forever gaps (decision 18).** No clock for a character without a mana pool, in combat too
> (`manaUsersOnly` in the shared show rule, TBC's gate moved there). `db.clock.clickThrough` (off
> by default): no mouse except while the clock is being placed. One pulse per fight the first
> time the clock reads under 30 s, and `MD:Alert` pulses it. `db.clock.showRest` (on by default)
> drops the `rest` segment. `/st clock rest` and `/st clock clickthrough` switch the last two
> until Settings -> Clock.

**`docs/TESTING.md`** section 46, a new item:

> 2. **Clock (T93, wave N2), both clients.** In a fight, spend until the clock reads under 20 s:
>    on Forever it turns red (amber under 60 s, the label grey); on TBC as before. Watch `59s` ->
>    `1:00` (TBC) or `0:55` -> `1:00` (Forever): the label and the rest segment do not move, only
>    the number. On TBC, a left-click on the clock in combat does nothing; out of combat it opens
>    the window. On Forever: `/st clock clickthrough`, then a click on the clock passes to the
>    world (no hover either), `/st clock clickthrough` again to undo; `/st clock rest` hides the
>    rest segment. Under 30 s the clock pulses once per fight. On a Forever warrior or rogue alt:
>    no clock in combat.

**`docs/HISTORY.md`**: wave N2's entry names T93. Both clocks draw the face through
`UI/ClockView.lua` in fixed segments. The Forever clock has F1 and F3-F6. TBC changes are the
segments and the left-click rule. The mover seam is `MD.ClockWidget` on both lines, for T97's
mover and T102's settings.

## Deviations

1. **`Visibility.Want` takes a sixth argument, `usesMana`.** The spec writes
   `Want(pct, shown, inCombat, unlocked, rule)`. `manaUsersOnly` is a setting, but whether the
   character has a pool is a fact about it, so it is passed beside the rule rather than stored in
   it. `Want` stays pure. Only `false` hides; `nil` (not known) does not.
2. **The suites grew by one more than the spec's numbers.** `clockcheck` is +6, not +5: the mover
   seam on Forever. `ttocheck` is +3, not +2: decision 17's left-click rule and the TBC mover
   seam. Both are visible or seam behaviour that would otherwise go untested.
3. **The pieces carry tone names, not colour codes.** A layout's colours (T98's `look.colors`,
   decision 16's "a style may re-tint them") then apply in one place, `ClockFace.ToneRGB` / the
   view. Only the arrow, where its tone differs from the value's, is an inline code inside the
   value's font string. "Three font strings: label, value + arrow, secondary" stays literal.
4. **`/st clock rest` and `/st clock clickthrough` are not in the row.** They are added so that
   F4 and F6 (and in-game check 4's "click-through on") can be switched on Forever before T102's
   Settings -> Clock. They mirror TBC's `/md rest` and `/md tooltip`. They go through
   `MD:AddSubcommand`, so `/st clock` and `/st clock lock` are unchanged, and they do not collide
   with T102's `layout` / `look` / `preview`. Before T93, `/st clock rest` toggled the clock's
   visibility (any argument but `lock` did).
5. **Click-through on Forever takes the mouse back only while previewing, not whenever unlocked.**
   TBC's rule is "unlocked: mouse on". The Forever clock's `locked` defaults to `false`, so the
   TBC rule would make click-through do nothing there by default. A click-through clock is placed
   through Show now / unticking Lock (the 60-s preview), during which it takes the mouse.
6. **The fixture rebuild is the integrator's.** `tools/data/import-forever-sv.lua` is generated
   and not in the owned files. It changes by the two registered defaults only.
7. **The TOC lines are not committed** (integrator-owned). They were applied in the working tree
   to run the suites and reverted. See "The checks" for what fails without them.
8. **Not done here, by the spec's split:** layouts (Compact, Bar), bar sources, the spark, the
   bar's tone colour on Forever's `pool` and `db.clockLook` are T98's. The ring is T104's.
   Settings -> Clock is T102's. Forever still has no arrow (R-clock 5.1's optional latch is not
   scheduled).
