# T116 -- Clock v2: the slots drawn, and the Text tab (C1, C5's Text tab)

Status: **ready** 2026-10-02, the clock v2 round of `docs/SPEC-next.md` section 13 (the author's
answers to `docs/mockups/clock-v2.html`). **Starts after T114 and T115 are merged and green**: it
draws T114's slots in T115's frame, and it edits four of T115's files.

## The task (docs/mockups/clock-v2.html C1, C2's text-driven minimums, C5's Text tab; docs/SPEC-next.md 13, 7.3 Text / Show, decision 14)

> Each layout keeps its fixed places (decision 14: only a value's own digits move) and every place
> becomes a slot filled from one list. Line: Left, Main, Right (and an optional second Right);
> Compact: Top, Main, an optional Bottom; Bar: Left and Right on the bar. Size, outline, shadow and
> the numbers' face per layout. A **Text** tab replaces **Show**.

Owned files (the only files edited, apart from this one):

- `UI/ClockView.lua` (after T115)
- `UI/ClockSettings.lua` (after T115)
- `UI/Clock_Forever.lua` (after T115)
- `UI/Widget.lua` (after T115)
- `tools/clockui.lua` (after T115)
- `tools/clocksettings.lua` (after T115)
- `tools/clockcheck.lua` (after T115)
- `tools/ttocheck.lua` (after T115)

It reads, never edits, T114's `Engine/ClockFace.lua` (`CF.TEXT`, `CF.TEXT_OPTIONS`,
`CF.ResolveText`, `CF.Slots`, `CF.Time`) and `MD.API.DrawPowerText` / `POWER_TEXT_READS`.

The author's answers used here (`docs/SPEC-next.md` 13):

- **Answer 3:** Line keeps **one** Right slot by default (the one-second glance ruling). The second
  Right slot is an option, off by default, **offered only where the width allows**.
- **Answer 4:** on Forever, Mana % and Mana are offered now and draw the model's `~` values; the
  real ones only after Q-clock-2, through T114's seam, which stays off.
- Everything else as the mockup recommends (C1's option table, C5's Text tab).

## What to build

### `UI/ClockView.lua`: the text in the look, the slots in the frame

**The store.** `CV.OVER` gains, per layout, `text.<layout>.<key>` for T114's word keys (validated
by `CF.ResolveText`: `left`, `main`, `right`, `right2`, `top`, `bottom`, `labels`, `ofMax`,
`time`) and the renderer's own:

| key | values | default |
|---|---|---|
| `text.<layout>.size` | 8-32 | unset: the kit's font as today (Line 13, Compact 22 with Top 9, Bar 12), **following the window text-size offset**; set: that size exactly |
| `text.<layout>.outline` | `none` / `outline` / `thick` / `mono` (Cell's tuple: `""`, `OUTLINE`, `THICKOUTLINE`, `MONOCHROME`) | `none` |
| `text.<layout>.shadow` | true / false | true (today's) |
| `text.<layout>.numbers` | `number` (the kit's number face: Arial Narrow; Expressway under Ellesmere) / `labels` (the labels' face) | `number` |

Still no default registered (`over` sparse): `defaultscheck` and the import fixture unchanged.

**The resolver.** `CV.Resolve` adds `look.text` (the layout on screen) and **`look.texts`** (all
three layouts, each through `CF.ResolveText(over.text[layout], layout, { cd = facts.cd })`) -- the
contract T114's feed and broker read as `look.texts.line`, so the datatext and the brokers follow
Line's slots whatever layout is on screen. Refusals land in `look.refused` as T114 names them.

**The line's switches** (TBC `db.showRest` / `db.showCooldown`, Forever `db.clock.showRest`) keep
gating the face's `second` exactly as today, so the default Right (`rest`) is byte-identical and
`/md rest`, `/st clock rest` keep working. The Text tab writes them (below).

**The slots in the frame** (decision 14's fixed places, each slot one font string):

- **Line:** Left from the left edge; Main at a fixed x (the left slot's measured width + the gap,
  re-anchored only when that width changes); Right right-aligned to the right edge; Right2
  right-aligned left of Right with two spaces' gap. Only a value's own digits move.
- **Compact:** Top small (9 pt by default, scaled with Size) at the top left; Main big below it;
  Bottom small under Main (adds 12 px to the minimum height, as the mockup says).
- **Bar:** Left and Right on the bar, Main's place being Right (T114's time's home).
- A slot holding a time (T114's label-with-time) carries its arrow and tones; pct / mana in Main
  in the `mana` tone, elsewhere `muted`; the crit band paints from the label on as today.
- **The minimum** (T115's `View:Minimum()`) is measured from the slots actually set, in the fonts
  actually used: a bigger Size, an outline, Right2 or Bottom raise it. Line's 100 x 30 with no
  secondary is `right = none` (or the switch off).
- **Right2 offered only where the width allows** (answer 3): `View:FitsRight2()` -- the Line
  frame's width at least the minimum measured with Right2 set to its widest sample. When it does
  not fit, Right2 is not drawn and `look.refused["text.line.right2"]` reads `needs <N> px of width
  (now <W>)`; it comes back when the width is raised. Default `none`, so nothing changes until
  someone sets it.
- **Forever's real text, behind the seam.** For a `pct` / `mana` slot the renderer asks the line's
  `draw.powerText(fs, kind)`. Forever's returns false while `MD.API.POWER_TEXT_READS` is false
  (always, this round) and the slot draws T114's `~` words; were it true, the font string would be
  handed to `MD.API.DrawPowerText` and never read (no `~`, no `ofMax`: a secret cannot be
  concatenated). TBC's `draw.powerText` is absent: plain words.
- The view still never shows or hides the frame, never reads a client value (the line's `draw`
  does) and touches `MD.db` only through `CV.Look` / `CV.Set` / `CV.SetLayout` / `CV.ResetToStyle`.

### `UI/Widget.lua` (TBC) and `UI/Clock_Forever.lua` (Forever)

- Facts gain `cd` (TBC true, Forever false).
- Forever's `draw.powerText(fs, kind)`: `MD.API.POWER_TEXT_READS == true and
  MD.API.DrawPowerText(fs, "player", 0, kind)`; false otherwise.
- Both paint from `CF.Slots` through the view (no new client read on either line: TBC's mana,
  pct and mp5 come in the face, T114).
- Forever's hover gains one line when a slot shows a modelled mana number: `~62% is the model's;
  the game's own number cannot be shown yet.`

### `UI/ClockSettings.lua`: the Text tab replaces Show

Tabs: **Text**, Colours, Frame, Bars, When. The Text tab edits the layout on screen (the preview
shows it), as the mockup's C5 draws:

- **SHOW (LINE / COMPACT / BAR):** one dropdown per slot of the layout (Line: Left, Main, Right,
  and **Right 2** -- disabled with the reason `needs N px: raise the width on Frame` when
  `View:FitsRight2()` is false; Compact: Top, Main, Bottom; Bar: Left, Right), each listing
  `CF.TEXT_OPTIONS` with the mockup's words and samples (`Rest 2:10`, `Mana % 62%`, `Mana 4210`,
  `Regen 92 mp5`, `Five-second rule 3.0`, `Cooldown inn 2:10`, `None`). On Forever Mana % / Mana /
  Regen read `~ model` beside them and Cooldown is not listed; the tab's footnote: `Forever: the ~
  stays on every modelled number. A real mana % or number as text waits for the probe (Q-clock-2);
  until then those picks show the model's ~ value.`
- **Labels** (OOM / FULL or out / full) and **Mana as 4210/6800** (`ofMax`).
- **FORMAT:** Time (`1:20` -- the line's own -- / `80s` / `1m20`), Size (8-32 slider, shown at the
  current size; a `Default` button removes the override), Outline, Shadow, Numbers.
- **The line's switches, written by the Right picks:** picking Rest on Right removes
  `text.<layout>.right` and turns the line's rest switch on (`opts.show`, the handed-in
  `CLOCK_SWITCHES`); picking Cooldown (TBC) writes `cd` and turns `showCooldown` on; None writes
  `none` and leaves the switches alone; any other kind writes it. So the default stays today's and
  the commands that flip the switches keep their meaning.
- Every control writes through `MD.ClockView.Set`; the preview and the widget rebuild on
  `CLOCK_LOOK`. The note under the box stays: `Text, size and bars are kept per layout; Reset to
  style wipes your changes, not the layout.`
- The **Show** tab and its switches are gone (the switches now live behind Right's picks; When
  keeps its own).

## The checks (fail first on the merged T114 + T115, then green)

**`tools/clockui.lua`** (+9 each flavour over T115's count):

1. Defaults: every layout draws today's words byte for byte at T115's places (Line's label, value
   and secondary where `ttocheck` 12 expects them).
2. Every slot at a fixed place: `59s` -> `1:00` -> `>10m` moves no slot's anchor on any layout.
3. Every `CF.TEXT_OPTIONS` value in every slot of every layout x every `SAMPLES` face fits its
   frame at Size 8, 13, 22 and 32 (the frame at its minimum or larger; nothing overlaps, nothing
   over a bar).
4. Size, outline, shadow and numbers reach the font strings (`GetFont` flags, the shadow offset,
   the number face); unset Size follows the window font offset, set Size does not.
5. Per layout: Compact's `main = pct` leaves Line's words unchanged; switching layouts shows each
   its own.
6. Right2: drawn after Right when the width allows; refused with the measured width when not; back
   when the width is raised.
7. Compact Bottom adds 12 px to the minimum height; Line's minimum is 100 x 30 with `right = none`.
8. Forever: with `POWER_TEXT_READS = false`, `MD.API.DrawPowerText` is never called (spied) and the
   slot reads `~62%`; with it set true in the test only, the font string holds the stub's secret
   unread and no `~`, and nothing raises under the forever profile.
9. `look.texts.line` resolved whatever layout is on screen: the clock feed (T114) reads `... 62%`
   with Line's `right = pct` while Bar is on screen.

**`tools/clocksettings.lua`** (+7 each flavour over T115's count): the Text tab replaces Show; each
slot's dropdown lists the line's values (Cooldown on TBC only, `~ model` on Forever) and writes
`text.<layout>.<slot>`; Right 2 disabled with its reason at 180 px and enabled at 300 px; Rest /
None / Cooldown write the line's switches as above; Time, Size (with Default), Outline, Shadow,
Numbers write their keys and the preview follows; the Forever footnote; no Show tab.

**`tools/ttocheck.lua`** (tbc +1 over T115's): the TBC widget's words through the slots are
byte-identical to `MD:GetDisplayString()` stripped of colour on a scripted fight (`vv`, `inn`,
`rest` included); `/md rest` off empties Right as before.

**`tools/clockcheck.lua`** (forever +1 over T115's): `right = pct` paints `~62%` on the Forever
clock and the hover carries the modelled-number line; `/st clock rest` still drops the rest.

**Unchanged:** `clocktextcheck`, `clockfacecheck`, `stylecheck` (the default text is today's, so
the clock golden T115 re-based holds), `surfacecheck`, `euicheck`, `minimapcheck`, `restylecheck`,
`slashcheck/tbc`, `defaultscheck`, `importcheck`. `make check` green, apicheck 0, textcheck 0.

### Counts (recorded 2026-10-02)

| Suite | Before (T115, ad4a02f) | Failing tests on the parent | After |
|---|---|---|---|
| `clockui/tbc` | 32 | 32 ok, 9 failed | **41** |
| `clockui/forever` | 32 | 32 ok, 9 failed | **41** |
| `clocksettings/tbc` | 39 | 37 ok, 9 failed | **46** |
| `clocksettings/forever` | 40 | 38 ok, 9 failed | **47** |
| `ttocheck/tbc` | 52 | 52 ok, 1 failed | **53** |
| `clockcheck/forever` | 36 | 36 ok, 1 failed | **37** |

The parent's 9 clocksettings failures are the 7 new 5b checks and two existing checks the tab change
rewrote: the tab list and section 5's Show check. Every other suite's count is unchanged.
`make check`: 94 runs, all passed. apicheck 0 findings, textcheck 0 findings.

## Integrator lines

- **TOCs:** none.
- **`tools/data/expected-counts.json`:** `clockui` (both), `clocksettings` (both), `ttocheck/tbc`,
  `clockcheck/forever` -- the exact numbers from the task file.
- **`CLAUDE.md`:** `UI/ClockView.lua`'s row: `**T116 (clock v2, C1):** text.<layout> (T114's slots
  and words, plus size 8-32 -- unset follows the window font offset --, outline, shadow, numbers);
  look.text and look.texts (every layout's, Line's read by the feeds and brokers); each slot one
  font string at a fixed place (decision 14); the minimum measured from the slots set; Right2
  drawn only where the width allows (View:FitsRight2); a pct / mana slot asks draw.powerText
  (Forever: off until Q-clock-2, the model's ~ words)`. `UI/ClockSettings.lua`: `**T116:** the
  Text tab replaces Show -- a dropdown per slot of the layout on screen (Right 2 disabled with its
  reason when narrow), Labels, Mana as of max, Time / Size / Outline / Shadow / Numbers; the Right
  picks write the line's rest / cooldown switches`. `UI/Clock_Forever.lua`: `draw.powerText`, the
  hover's modelled-number line. `UI/Widget.lua`: `facts.cd`. The `tools/` row: the counts.
- **`docs/TOOLS.md`** section 1: the four rows' counts and new checks.
- **`docs/DECISIONS.md`**, one entry:

  > ## Clock v2: what the clock says (2026-10-02, T114, T116, the author's answers to clock-v2.html)
  >
  > Every place a clock layout draws is a slot filled from one list (label, time, Mana %, Mana,
  > mp5, the five-second rule, rest, cooldown, none), kept per layout with its size, outline,
  > shadow and number face, in a Text tab that replaces Show. Line keeps one Right slot by default
  > (the one-second glance ruling); a second Right slot is an option, off, offered only when the
  > clock is wide enough. The time is never lost: when Main shows something else, the label slot
  > carries it. On Forever, Mana % and Mana show the model's `~` values; the game's own number waits
  > for probe Q-clock-2 (`MD.API.POWER_TEXT_READS`, off). The datatext and the brokers follow Line's
  > slots. By default every word is as before.

- **`docs/TESTING.md`**, a new item: Settings -> Clock -> Text on each layout: set Right to Mana %
  (TBC `62%`, Forever `~62%`), Main to Mana % (the time moves to the label: `OOM 1:20 v`), Size 20
  (the minimum rises on Frame), Outline thick; Right 2 is greyed at 180 px and works at 300 px;
  ElvUI / EllesmereUI's SpellTuner text follows Line's slots; `/md rest` / `/st clock rest` still
  drops the rest.
- **`docs/HISTORY.md`:** the round's entry names T116.

## Out of scope

- The bars, the frame's size and scale (T115) and the words themselves (T114).
- The real Forever mana text (the flag stays off until a Forever report answers Q-clock-2), and a
  font face chooser beyond the number face (spec 7.3's Friz / Skurri / Morpheus wait for
  Q-clock-4).
- The Ring layout (T104) and the two-line layout (T112, not scheduled).
- Moving the line's rest / cooldown switches into `db.clockLook` (kept where they are, 7.3 phase 1).
