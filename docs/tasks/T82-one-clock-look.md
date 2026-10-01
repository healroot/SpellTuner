# T82 -- One clock look (plan C4)

Status: **built** 2026-10-01 on branch `plan/C4` (base `70b424d`), wave C-b of
`docs/PLAN-refactor-ux.md`, beside C2. It awaits the integrator. No TOC line is needed: every file
this task touches is already listed where it must be (`UI\Theme_Flat.lua`, `UI\Tip.lua`,
`UI\Tip_TBC.lua`, `UI\Visibility.lua`, `UI\Widget.lua` and `UI\MinimapButton.lua` on
`SpellTuner_TBC.toc` since C1 / P36).

## The task (docs/PLAN-refactor-ux.md section 5.C, C4; review U4; mockup M6, approved 7.1)

> The TBC widget moves onto the kit's panel, font and a 160 x 4 five-second-rule bar, and its
> unlock text takes the accent colour. TBC's `Tip:Clock` body takes M6's words (`Out of mana in`,
> `Full again in ... if you stop` as label/value pairs; the CV and raw lines behind the detail key).
> With C1's `UI.THEMED`, the TBC minimap tooltip is then P36's themed shape.

Owned files: `UI/Widget.lua`, `UI/Tip_TBC.lua`, `tools/ttocheck.lua`, `tools/minimapcheck.lua`.
Nothing else was edited.

## What was built

### `UI/Widget.lua`: the TBC clock in the Forever clock's look

The widget now uses `UI/Clock_Forever.lua`'s layout, element for element:

- a 180 x 30 `BackdropTemplate` frame, styled with `UI.StylizeFrame(widget, PALETTE.bg,
  PALETTE.border)` (the theme's near-opaque `bg`, 1-px black edge);
- the text in the kit's font (`UI.FONT`, 13 pt), centred at the top (`TOP`, 0, -4), in the theme's
  `text`. The colour codes `MD:GetDisplayString` puts in still win, so `OOM`, `rest` and the arrow
  keep their colours (Engine/TTO.lua is untouched);
- a 160 x 4 bar at the bottom (`BOTTOM`, 0, 5), on a black backing texture one pixel wider on every
  side, re-snapped from the 10 Hz `OnUpdate` when `UI.px(1)` moves (the Forever clock's own rule:
  the window manager never touches a clock).

The bar still means **the five-second rule**: it fills over 5 s after a spend, amber
(1, 0.67, 0.2) while it fills and green (0.2, 1, 0.4) once spirit regen runs. That is M6's note
("TBC's bar keeps meaning the five-second rule, in the same slot as Forever's pool bar").

The unlock and first-run preview says `SpellTuner - drag me` in the accent (`UI.RGB("accent")`, the
class colour) over a full bar in the accent. The old purple `|cff9966ff` and the 14-pt `OUTLINE`
font are gone.

The hover is the new `Tip:Clock` (below), anchored `ANCHOR_TOP` as on Forever, with two hint
pairs: `Left-click: open the window` and `Shift: spend, regen and cooldowns`. While Shift is down,
only the first pair is shown. Nothing else changed: the visibility rule (`MD.Visibility.Want`), the
`db.widgetTooltip` mouse rule, the drag, the left-click and the pulse are as before.

### `UI/Tip_TBC.lua`: `Tip:Clock` in M6's words

`Tip:Clock(hints, detail)` builds these lines:

1. The title, `SpellTuner`, in `accent`.
2. The summary, `Tip:ClockSummary(MD:GetManaState())`. Each line is a label/value pair, with the
   label in `label` and the value in `text` (white, M6's `w`). The words are the Forever clock's,
   with TBC's numbers and no `~`:

   | Mode | Line |
   |---|---|
   | oom | `Out of mana in` `1:20`. When the estimate is not yet stable, `about 1:20` (the face's `~`). When the confidence gate holds the face on its bound, `no sooner than 1:20`. |
   | warmup | `Out of mana in` `a few more casts first` (muted) |
   | hold | `Out of mana in` `not at this pace` (muted) |
   | full, ooc | `Full again in` `2:10` |
   | nodata | `Full again in` `--` (muted) |
   | fullnow | `Full` `now` |
   | in combat, oom/hold/warmup, with a rest time | `Full again in` `3:40 if you stop` (the face's rule: never beside FULL) |

   Times use the face's steps: to the second under 30 s, to 5 s above, `>10m` past ten minutes,
   written as M:SS (`MD.Util.Clock`).
3. With `detail`: a spacer, then `Tip:Mana()` (the raw time with its spread, the net rate, the spend
   with its CV, the regen terms, the mana cooldowns, the pull budget), then `Tip:Fights(1)`.
4. The hints, after a spacer. A string becomes a muted line (the old shape); a table is used as it
   is (a pair).

The detail key is **Shift**, read through the adapter (`MD.API.IsShiftKeyDown`), as on the TBC spell
tooltip. The `MinimapLines` provider passes it at every hover. A watcher (`MD:On(
"MODIFIER_STATE_CHANGED")`, `Tip.OnClockModifier`) runs the owner's `OnEnter` again when Shift goes
down or up while `GameTooltip` is owned by `SpellTunerWidget` or `SpellTunerMinimapButton`. The
detail lines therefore come and go without moving the mouse, as UI/SpellTooltip.lua does for the
spell tooltip.

New exports, used by the widget: `Tip.ClockPair`, `Tip.ClockTime`, `Tip:ClockSummary`,
`Tip.ClockDetail`, `Tip.OnClockModifier`.

`Tip:Mana` and `Tip:Fights` are unchanged, so the ElvUI datatext, which renders them directly, is
unchanged.

With C1's `UI.THEMED` on TBC, the minimap button (`UI/MinimapButton.lua`, not edited) takes P36's
themed path: the provider's title and pairs, a spacer, the three hint pairs and the muted hide
line. That is M6's TBC minimap tooltip.

## The checks

**`ttocheck/tbc` 45 -> 47.** The loader now loads `UI/Theme_Flat.lua` after `UI/Style.lua`, as the
TBC TOC lists it since C1. The 45 old checks pass unchanged under the theme. While the widget is
built, the stub's `CreateFontString` keeps its template and `SetPoint` keeps a region's first
point, so the layout can be read back (test plumbing only, removed again right after).

12. `widget: the kit's panel, font and a 160 x 4 five-second-rule bar (themed)`. Checked:
    - `UI.THEMED`;
    - the backdrop exists, its fill is `PALETTE.bg` (alpha included) and its edge `PALETTE.border`;
    - the frame is 180 x 30;
    - the text uses the template `UI.FONT`, at `TOP` 0, -4;
    - the bar is 160 x 4 at `BOTTOM` 0, 5, on a black backing `160 + 2px` x `4 + 2px`;
    - after a Healing Touch in combat the bar is amber with a value under 5, and six seconds later
      green and full.
13. `widget: the unlock text is in the accent, over a full accent bar`. Under
    `MD:ForceWidgetPreview(60)`, the text is `SpellTuner - drag me` in `UI.RGB("accent")`, the bar
    is at 5 in the accent, and the widget is shown. With the preview ended, the text is the clock
    again, in `text`.

**`minimapcheck/tbc` 6 -> 7.** The TBC half now loads the theme after the kit (as the TOC does), so
the button takes the themed path. The golden is replaced by M6's lines. It is captured in a fight
(`Fight()`: one Healing Touch every 3.5 s against a scripted 10 / 5 regen, until the clock is out of
mana, stable and trusted), which is the moment M6 draws. Both goldens were captured with `--print`
on this tree.

`GOLDEN_TBC` (check renamed `tbc: the tooltip in a fight is M6's, line for line (golden)`):

```
anchor ANCHOR_LEFT
SpellTuner | nil | 1.000,0.490,0.040 | -
Out of mana in | 1:10 | 0.702,0.702,0.702 | 1.000,1.000,1.000
Full again in | 3:40 if you stop | 0.702,0.702,0.702 | 1.000,1.000,1.000
  | nil | - | -
Left-click | open the window | 0.702,0.702,0.702 | 1.000,1.000,1.000
Right-click | Settings | 0.702,0.702,0.702 | 1.000,1.000,1.000
Drag | move it round the map | 0.702,0.702,0.702 | 1.000,1.000,1.000
Hide it: Settings -> General -> Windows. | nil | 0.478,0.478,0.478 | -
```

(It replaces the old 15-line golden, captured at full mana on 7fd71b3: `FULL`, the raw lines,
`Innervate`, and the hints `Left-click: dashboard` and `Right-click: settings`.)

New check `tbc: Shift pressed over it adds the raw lines (golden); released, they go`. The tooltip
is shown and owned by the button. Shift is pressed and `MODIFIER_STATE_CHANGED` fires; the
tooltip, redrawn by the watcher, is `GOLDEN_TBC_DETAIL`:

```
anchor ANCHOR_LEFT
SpellTuner | nil | 1.000,0.490,0.040 | -
Out of mana in | 1:10 | 0.702,0.702,0.702 | 1.000,1.000,1.000
Full again in | 3:40 if you stop | 0.702,0.702,0.702 | 1.000,1.000,1.000
  | nil | - | -
Time to OOM (raw) | 72s +- 20s | 1.000,1.000,1.000 | 1.000,1.000,1.000
Full if you stop casting | 221s | 1.000,1.000,1.000 | 1.000,1.000,1.000
Net rate (pessimistic) | -66 mana/s | 1.000,1.000,1.000 | 1.000,1.000,1.000
Spending | 53 +- 18 mana/s (9 casts, CV 0.35) | 1.000,1.000,1.000 | 1.000,1.000,1.000
Regen now / projected | 5 / 5 mana/s  (5SR 100% of time) | 1.000,1.000,1.000 | 1.000,1.000,1.000
Regen out of 5SR / casting | 10 / 5 mana/s | 1.000,1.000,1.000 | 1.000,1.000,1.000
Spirit / gear mp5 | ~35 / ~14 | 1.000,1.000,1.000 | 1.000,1.000,1.000
Spirit regen resumes | 4.5s | 1.000,0.670,0.200 | 1.000,1.000,1.000
  | nil | - | -
Innervate | 671 mana -> OOM 82s | 0.780,0.780,0.780 | 0.310,0.660,0.940
  | nil | - | -
Left-click | open the window | 0.702,0.702,0.702 | 1.000,1.000,1.000
Right-click | Settings | 0.702,0.702,0.702 | 1.000,1.000,1.000
Drag | move it round the map | 0.702,0.702,0.702 | 1.000,1.000,1.000
Hide it: Settings -> General -> Windows. | nil | 0.478,0.478,0.478 | -
```

The check also needs the plain tooltip before the press to have the golden's 8 lines, and the
tooltip after the release to have 8 again.

The first five TBC checks (the button's name, parent and size, its point and drags, the clicks, the
hide setting, the fresh default) and the Forever half's eight are unchanged.

## Failing first

**The parent `70b424d`** (taken with `git archive`) with this branch's two suites copied in:

```
=== ttocheck (tbc)      45 ok, 2 failed   exit 1
  widget: the kit's panel, font and a 160 x 4 five-second-rule bar (themed) FAIL - themed=true panel=false font=nil slot=nil rule=false (nil -> nil)
  widget: the unlock text is in the accent, over a full accent bar   FAIL - nil - bar=false shown=true back=false
=== minimapcheck (tbc)  5 ok, 2 failed
  tbc: the tooltip in a fight is M6's, line for line (golden)              FAIL - 19 lines, want 9
  tbc: Shift pressed over it adds the raw lines (golden); released, they go FAIL - 1 lines, want 20; plain 18, released 0
```

`tools/check.sh` on that copy: `check: 71 run(s), 3 failed: minimapcheck/tbc ttocheck/tbc counts`.

**Mutations** (a scratch copy of this tree):

- **M1.** The `MinimapLines` provider passes `false` instead of `Tip.ClockDetail()`.
  `minimapcheck/tbc` fails the Shift check (`9 lines, want 20; plain 8, released 8`).
- **M2.** The preview's text colour is `UI.RGB("text")` instead of the accent. `ttocheck/tbc` fails
  check 13 (`SpellTuner - drag me 1,1,1`).
- **M3.** The bar is the old 60 x 2. `ttocheck/tbc` fails check 12 (`slot=false`).

## Suites, before and after

Before: `tools/check.sh` on `70b424d` gave **71 runs, all passed**, 66 counted against 66.

After: `tools/check.sh` on this branch gave **71 runs, all passed**, 66 counted against 66, with
two notes:
- `minimapcheck/tbc: 7 assertion(s), 6 expected`
- `ttocheck/tbc: 47 assertion(s), 45 expected`

| Suite | Before | After |
|---|---|---|
| `ttocheck/tbc` | 45 | **47** |
| `minimapcheck/tbc` | 6 | **7** |
| `minimapcheck/forever` | 8 | 8 |
| every other suite | as `tools/data/expected-counts.json` | the same |
| `apicheck` | 0 findings (8 Forever TOCs, 59 files, 48 globals) | the same |
| `textcheck` | 0 findings (9 TOCs, 95 files) | the same |

`luac -p` passes on both changed shipped files: `UI/Widget.lua` and `UI/Tip_TBC.lua`.

## Integrator lines

**`tools/data/expected-counts.json`:**

```
  "minimapcheck/tbc": 7,
  "ttocheck/tbc": 47,
```

**TOCs:** none.

**`CLAUDE.md`**, append to the `UI/Widget.lua` row:

> **T82 (C4, mockup M6):** one clock look -- the Forever clock's panel (180 x 30,
> `UI.StylizeFrame` in the theme's `bg`, the kit's `UI.FONT` centred at the top) and a 160 x 4 bar
> on a black backing, still the five-second rule (amber filling, green after); the unlock preview
> `SpellTuner - drag me` in the accent over a full accent bar; the hover is `Tip:Clock` with
> `Left-click` / `Shift` pairs, `ANCHOR_TOP`

and the row's opening words "Floating one-liner + 5SR underline" become "The TBC mana clock + its
five-second-rule bar".

Append to the `UI/Tip_TBC.lua` row:

> **T82 (C4, mockup M6):** `Tip:Clock(hints, detail)` in M6's words -- the title, then
> `Tip:ClockSummary` (`Out of mana in 1:20` / `about` / `no sooner than`, `Full again in 2:10`,
> `Full again in 3:40 if you stop` in a fight, as label / value pairs in `label` / `text`, no `~`),
> `Tip:Mana` and the last fight behind Shift (`Tip.ClockDetail`, through `MD.API.IsShiftKeyDown`;
> the `MinimapLines` provider reads it at each hover, and `MODIFIER_STATE_CHANGED` re-runs the
> widget's or the minimap button's `OnEnter`). `Tip:Mana` / `Tip:Fights` unchanged (the ElvUI
> datatext)

**`docs/TOOLS.md`**, section 1 table:

- `ttocheck.lua` row: `(T58, tbc, 45)` -> `(T58, tbc, 47)`, and append "; (T82) under the theme the
  widget's kit panel, font and 160 x 4 five-second-rule bar, the unlock preview in the accent".
- `minimapcheck.lua` row: `(T79, P36; tbc 6, forever 8)` -> `(T79, P36; tbc 7, forever 8)`, and
  replace "TBC golden" with "TBC under the theme: M6's tooltip in a fight (golden) and Shift's raw
  lines (golden), T82"; `--print` prints both TBC goldens.

**`docs/DECISIONS.md`**, after the paragraph **TBC takes the Forever window** (C1), one paragraph:

> **One clock look** (2026-10-01, T82 / C4; U4's "two clock looks", mockup M6). The TBC clock
> widget wears the Forever clock's panel: 180 x 30, the theme's fill and edge, the kit's 13-pt font
> centred (the 14-pt OUTLINE text and its left anchor are gone), and a 160 x 4 bar on a black
> backing. On TBC the bar still shows the five-second rule (amber while it fills, green once spirit
> regen runs); on Forever it is the real pool. The two look the same but mean different things,
> which M6 accepted. The unlock preview is in the accent. The clock tooltip, on the widget and on
> the minimap button, says `Out of mana in 1:20` and `Full again in 3:40 if you stop` as pairs. The
> raw lines (the time with its spread, the net rate, the spend and its CV, the regen terms, the
> mana cooldowns, the pull budget) and the last fight move behind Shift.

**`docs/TESTING.md`**, section 44, under a **Wave C-b** heading (C2 adds its own item; number this
one after it):

> **One clock (C4).** On TBC: `/md unlock` (or Settings -> the clock's Lock box). The clock is a
> dark flat panel with `SpellTuner - drag me` in your class colour over a full bar of the same
> colour. Drag it and lock it. In a fight the text sits centred over a thin bar that fills amber
> after each cast and turns green five seconds later. Say whether the centred text sliding as the
> digits change bothers you (it used to be left-anchored). Hover the clock: `Out of mana in` /
> `Full again in ... if you stop`, then `Left-click` and `Shift`. Hold Shift: the old raw lines
> (spend, CV, regen, Innervate, pull budget) appear without moving the mouse, and go when you
> release it. Hover the minimap button: the same clock lines, then Left-click / Right-click / Drag
> and the hide line.

**`docs/HISTORY.md`**: the wave C-b entry names T82.

## Deviations

1. **The text is centred, not left-anchored.** The old header said the left anchor was deliberate,
   so `OOM` would never slide as the digits change. M6, and the Forever clock it copies, centre the
   text (`.tx{text-align:center}`). The mockup was approved, so it is followed here. TESTING asks
   the author whether the slide bothers him in game.
2. **One extra check in `minimapcheck/tbc`** (6 -> 7, not "golden replaced" only). The plan puts
   the raw lines behind the detail key, and only a test can prove they can still be reached. The
   new check holds the detail golden and the redraw on a Shift press and release.
3. **The widget's hover has a `Shift` hint pair; the minimap's does not.** The minimap tooltip
   keeps M6's lines exactly. Without a hint, Shift would go undiscovered, and the widget's hover is
   not drawn in M6, so it carries one: `Shift: spend, regen and cooldowns`. The words are invented
   and can be adjusted in game (7.1).
4. **The mana cooldowns and the pull budget went behind Shift too.** They live inside `Tip:Mana`
   with the CV and raw lines, and M6's plain tooltip shows only the two clock pairs. The ElvUI
   datatext still shows all of them, because it renders `Tip:Mana` itself.
5. **Not done by this task:** installing the build into the TBC and beta clients, which the user
   asked for alongside the resume. A task worktree is not a release; that is the integrator's
   (`make install` after the wave merges).
