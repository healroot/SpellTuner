# T88 -- The clock face (S4 step 1, K1)

Status: **built** 2026-10-01 on branch `next/T88` (base `e2b13f4`), wave N1 batch A of
`docs/SPEC-next.md`, beside T89 and T90. It awaits the integrator.

**The branch needs its TOC lines (below).** `Engine/ClockFace.lua` must go on the three main TOCs,
which are integrator-owned. `Engine/TTO.lua` and `Engine/ManaModel.lua` now word the clock through
it, so without the lines 23 runs fail on the committed tree (listed under "The checks"). The lines
were applied in the working tree only to run the suites, then reverted before the commit.

## The task (docs/SPEC-next.md section 11, row T88; 2.4; R-clock.md 5.1 and 10 K1)

> **Clock face (S4, K1).** `Engine/ClockFace.lua` (pure: face shape with `arrow = "vv"` and
> `mode = "nodata"`, `LineString`, `SAMPLES`); `MD:GetClockFace()` in `Engine/TTO.lua`,
> `ManaModel.Face` in `Engine/ManaModel.lua`, each provided as `ClockFace.Current`;
> `GetDisplayString` and `ManaModel.Text` become wrappers. Byte-identical.

Owned files: `Engine/ClockFace.lua` (new), `Engine/TTO.lua`, `Engine/ManaModel.lua`,
`tools/clockfacecheck.lua` (new). Nothing else was edited (apart from this file).

## What was built

### `Engine/ClockFace.lua` (new, pure)

`MD.ClockFace` holds:

- **The face shape**, documented at the head of the file. It is the spec's 2.4 record: `mode` (with
  `nodata`), `label`, `value` (as shown), `known` (`point` / `bound` / `pending` / `none`),
  `unstable`, `modelled`, `tone`, `arrow` (with `vv`, TBC's crit-band mark), `second`, `fsr`,
  `tick`, `mp5`, `mp5Modelled`, `pct`, `pctModelled` and `combat`. It has two more fields, which
  say how the face's own line words it today (see Deviations 1):
  - `timeFmt`: `"auto"` is TBC's `15s` / `1:20`; `"mss"` is Forever's `0:15`.
  - `mono`: true means no colour codes. The Forever clock paints its whole line in one colour
    until F1.
- **`CF.LineString(face, valueHex)`**, the one place the words and colour codes are assembled. A
  face that is not a table gives `""`. The algorithm is TBC's old branch order, keyed on `known`:
  - `fullnow`: the label alone (`FULL`), in its tone.
  - `pending`: `OOM ...`.
  - `bound`: `OOM >t =`. A nil value, or one past 600 s, reads `>10m`.
  - `point`: in the crit tone, the whole line is red, `OOM 15s vv`. Otherwise the label is muted
    and the value is in `valueHex` or the value's tone. An unstable value is muted with a `~` in
    front. The arrow is coloured by its own tone (`^` good, `v` warn, `=` muted).
  - anything else: `OOM --` / `FULL --`. A missing number is never a 0.
  - Then at most one secondary segment, after two spaces: `inn 2:15` in the mana colour, or
    `rest 6:40` muted.
  - A `modelled` face puts `~` before the label.
- **`CF.Time(sec, fmt)`**: `--` when there is no number, `>10m` past 600 s, then the two formats.
- **`CF.Tone(v)`**: crit under 20 s, warn under 60 s, else normal.
- **`CF.HEX`**: TTO's six literals, moved here. **`CF.ARROW_TONE`**. **`CF.CAP`** = 600.
- **`CF.SAMPLES`**: 14 fixture faces, each `{ key, name, face }`:
  - `oom`, `crit`, `bound`, `hold`, `warmup`, `full`, `rest` and `ooc` (7.4's chips);
  - `fullnow`, `nodata`, `none`, `unstable`, `cd` and `long` (>10m).

  They are TBC-shaped. The suite also draws each one Forever's way (modelled, mono, `mss`, no
  arrow).

The file reads nothing but Lua's own library: no frame, no client call, no `MD.db`, no `GetTime`.

### `Engine/TTO.lua`

- **`MD:GetClockFace(now)`** builds the face from `disp` and `state`, branch for branch and in the
  same order as the old `GetDisplayString`: `fullnow`, `nodata`, `ooc` / `full`, `warmup`, `hold`
  (a bound with `=`), then `oom` (no value, the confidence bound, `v < 20` as crit + `vv`, else a
  point with the band tone, `unstable = not s.stable` and `Arrow(now or GetTime())`). The secondary
  segment uses the same rule as before (the cooldown when it is worth it, else rest by the 25 %
  rule; the two switches), with the same `Quantize` steps. It also fills `combat`, `pct`, `mp5` and
  `fsr` (`RM:FSRRemaining()`).
  - It returns nil when there is no state or no mode.
  - It is provided as `MD.ClockFace.Current` (`MD:Provide`).
- **`MD:GetDisplayString(valueHex)`** returns `CF.LineString(MD:GetClockFace(), valueHex)`, or
  `""` when there is no face.
- The six colour literals and `FmtTime` moved to `Engine/ClockFace.lua`. The latch, the arrow, the
  raw model and the debug log are untouched.

### `Engine/ManaModel.lua`

- **`ManaModel.Face(state, now)`**, pure. It covers every mode the old `Text` worded:
  - `fullnow` gives `~FULL`.
  - `ooc` / `full` give `~FULL t`, or `~FULL --`.
  - `warmup` gives `~OOM ...`; `hold` gives `~OOM --`. Both get the rest segment.
  - `oom` gives `~OOM t`, or `~OOM --` when there is no `tto`.
  - A non-table state, or an unknown mode, gives `~OOM --`.

  The value is the shown one: rounded to 5 s and never below 0, but kept as it is past 600 s, so
  `>10m` reads exactly as before. The rest segment's 25 % rule compares against the raw `tto`, as
  before. The tone is the band of the shown value. There is no arrow, so never `vv`. `pct` and `mp5`
  come from the model (marked modelled), and `combat` is true in the fight modes. `now` is
  accepted and not read yet.
- **`ManaModel.Text(state)`** returns `MD.ClockFace.LineString(ManaModel.Face(state))`.
- **`ClockFace.Current(now)`**, provided here, returns `Face(MD.Pool:Project(now))`. With no `now`
  it uses the model's last tick (`model.t`). Before `MD_READY` it returns the no-state face. It
  makes no client call.
- Both producer files do `MD.ClockFace = MD.ClockFace or {}` before they provide (Deviations 4).

## The checks

### `tools/clockfacecheck.lua` (new, tbc + forever)

**Goldens.** They were captured with `--golden` on `e2b13f4` before either engine file was edited,
pasted at the end of the file, and committed first (`10b485a`):

- **tbc**: 689 lines, each holding `GetDisplayString(nil)` and, where it differs,
  `GetDisplayString("|cff16c3f2")`.
  - **200 lines from a scripted fight.** These are real events and the real latch, every tick:
    Healing Touch rank 5 against a scripted `GetManaRegen`, as in ttocheck. The fight runs:
    1. full;
    2. out of combat at 74 %;
    3. the pull;
    4. a cast every 2 s, then every 3.5 s;
    5. stopping;
    6. regen outrunning the spend;
    7. a cast every second into the crit band;
    8. leaving combat;
    9. slow regen (`FULL >10m`);
    10. no regen (`FULL --`).

    It reaches `FULL`, `FULL 3:05`, `OOM ...  rest`, `~` with each arrow, `OOM 15s vv`,
    `rest >10m` and `FULL 26s` in combat.
  - **489 lines from a grid set straight into TTO's own `disp` / `state` locals** (Deviations 6):
    - A: every mode x 15 values (nil, 0, 15, 19, 20, 45, 59, 60, 61, 90, 125, 600, 601, 605,
      900) x in / out of combat.
    - B: oom x value x bounded x stable x arrow history (none, `=`, `v`, `^`).
    - C: the rest segment's 25 % rule over warmup / hold / oom / oom-bounded x 4 values x 7 rests.
    - D: the `inn` segment over 4 cooldowns x 3 values x bounded x `showCooldown`, plus hold and
      out of combat.
    - E: `showRest` off.

    These include `OOM 15s vv`, `FULL --` (nodata), `OOM --` (oom with no value), `OOM >10m =`
    (hold with no bound) and `OOM ~>10m ^`.
- **forever**: 389 lines of `ManaModel.Text`:
  - fullnow / ooc / full x 16 times (nil, -3, 0, 2.4, 2.6, 10, 19, 59, 62.4, 597.6, 600, 600.4,
    601, 602.6, 1e9, inf);
  - warmup / hold / oom x 16 times x 7 rests (nil, equal, x1.2, x1.3, x0.7, 30, 700);
  - nil, a string, `{}`, a numeric mode and an unknown mode.

**Assertions** (tbc 17, forever 14):

1. `Engine/ClockFace.lua` loads in an environment holding only Lua's library, with an unknown
   global raising (so there is no frame API and no client call), and renders every sample there.
   1b. The flavour's TOC loads it.
2. The golden holds, line for line. 2b. Every transcript string is ASCII with no bare pipe and no
   `nil`. tbc adds one more check: TTO's locals are reachable.
3. **tbc:** `GetClockFace` is provided as `Current`, and:
   - 3a. `OOM 15s vv` is tone crit, arrow `vv`, known point;
   - 3b. nodata is `FULL --`, known none, value nil;
   - 3c. `OOM --` is oom, known none;
   - 3d. the bound is known bound, arrow `=`, with the rest as `second`;
   - 3e. the `inn 2:15` segment;
   - 3f. `LineString(Current())` equals `GetDisplayString` with and without a hex, over five modes;
   - 3g. FULL with no value reads `FULL --` (Deviations 2);
   - 3h. with no state there is no face and the string is `""`.

   **forever:** `Face` is provided as `Current`, and:
   - 3a. `LineString(Face(s)) == Text(s)` over 7 modes x 12 times x 3 rests;
   - 3b. `tto = 12` is tone crit, value 10, no arrow, `~OOM 0:10`;
   - 3c. hold is known none, never a bound;
   - 3d. the no-state face;
   - 3e. `Current(now)` is the face of `MD.Pool:Project(now)`;
   - 3f. `Current()` with no time does not raise.
4. `SAMPLES` has every preview chip. 4b. Each sample, drawn as TBC and as Forever draws it, with
   and without a hex, is ASCII with no bare pipe and no `nil`. A missing value is never a `0s` /
   `0:00`, and a modelled face keeps its `~`. 4c. The crit sample is `OOM 15s vv` and the nodata
   one is `FULL --` in grey.

**Fails first on `e2b13f4`** (the suite committed alone as `10b485a`, before the engine edit):

- tbc `3 ok, 14 failed`: the goldens and the locals hold; no `Engine/ClockFace.lua`, no face API.
- forever `2 ok, 12 failed`.

**Mutations** (each reverted):

| Mutation | Result |
|---|---|
| The secondary separator `"  "` becomes `" "` | tbc golden fails at line 11 and 3d fails; forever golden fails at line 54 and 3c fails |
| `face.unstable = not s.stable` becomes `false` | tbc golden fails at line 21 |
| `Round5` becomes `math.floor` | forever golden fails at line 20 and 3b fails |

### Unchanged

`ttocheck/tbc` **47** and `clockcheck/forever` **29**, with no edits to either. The full
`tools/check.sh` with the TOC lines applied:

| | Before (e2b13f4) | After (with the TOC lines) |
|---|---|---|
| runs | 72, all passed | **74**, all passed |
| counted against expected | 67 of 67 | 69 (the 67 equal; `clockfacecheck/tbc` 17 and `/forever` 14 new) |
| `apicheck` | 0 findings, 8 Forever TOCs, 60 files, 48 globals | 0 findings, 8 Forever TOCs, **61** files, 48 globals |
| `textcheck` | 0 findings, 9 TOCs, 98 files | 0 findings, 9 TOCs, **99** files |
| `defaultscheck` | tbc 49, forever 52 | tbc 49, forever 52 (no new setting) |

Without the TOC lines, 23 runs fail on the committed tree, because `CF.LineString` is nil:

- clockcheck/forever, clockfacecheck (both), corecheck/forever, importcheck, measurecheck,
  minimapcheck/forever, practiceforever, reccheck, recordcheck, recordingscheck/forever,
  replaycheck, replayforever, replayui, restcheck, reviewui, solvercheck, spellsui, ttocheck,
  verifycheck, wincheck (both).

## Integrator lines

**`SpellTuner_TBC.toc`**: one new line, `Engine\ClockFace.lua`, right before `Engine\TTO.lua`
(after `Engine\ManaCooldowns.lua`).

**`SpellTuner_Mainline.toc`** and **`SpellTuner.toc`** (identical): one new line,
`Engine\ClockFace.lua`, right before `Engine\ManaModel.lua` (after `Spells\Tabs.lua`).

No module TOC changes. `tools/data/import-forever-sv.lua` needs no rebuild (importcheck passes with
the lines).

**`tools/data/expected-counts.json`**: add `"clockfacecheck/tbc": 17` and
`"clockfacecheck/forever": 14`. `tools/check.sh` needs nothing: the suite is discovered by name
and declares both flavours.

**`CLAUDE.md`**:

- A new row before `Engine/ManaModel.lua`'s:

  > | `Engine/ClockFace.lua` | **The clock face, both lines** (T88, `docs/SPEC-next.md` 2.4, S4 step 1): `MD.ClockFace` -- the face record (mode incl. `nodata`, label, value as shown, known point / bound / pending / none, unstable, modelled, tone, arrow incl. TBC's crit-band `vv`, at most one `second`, fsr, mp5, pct, combat, and how its line words it: `timeFmt` `auto` / `mss`, `mono`), **`LineString(face, valueHex)` the one place the clock's words and colour codes are assembled**, `Time`, `Tone`, `HEX` (TTO's six literals), `SAMPLES` (the suite's faces and Settings -> Clock's preview chips). Pure: Lua's library only. Each line provides `MD.ClockFace.Current(now)` (TBC `MD:GetClockFace`, Forever the pool's `ManaModel.Face`). Every main TOC, before `Engine/TTO.lua` / `Engine/ManaModel.lua` |

- `Engine/ManaModel.lua`'s row, appended:

  > **T88:** `ManaModel.Face(state, now)` (pure; shown value rounded to 5 s, kept past 600 s; tone by band, no arrow, `modelled`, `mono`, `mss`); `Text(state)` is `ClockFace.LineString(Face(state))`, byte-identical; provides `ClockFace.Current(now)` -- the face of `MD.Pool:Project(now)`, the model's last tick when `now` is omitted

- `Engine/TTO.lua`'s row, appended:

  > **T88:** `MD:GetClockFace(now)` builds the face from `disp` / `state` in the old branch order (the bound's `=`, crit `vv`, `unstable`, the arrow, the `inn` / `rest` segment), provided as `ClockFace.Current`; `MD:GetDisplayString(valueHex)` is `ClockFace.LineString` of it, byte-identical; the colour literals and `FmtTime` moved to `Engine/ClockFace.lua`

- The `tools/` row: after `**`tools/ttocheck.lua`** (T58, tbc): ...`, add:

  > **`tools/clockfacecheck.lua`** (T88, tbc + forever): the clock face -- `Engine/ClockFace.lua` loaded and rendered with Lua's library only; goldens captured on `e2b13f4` before the split (tbc: `GetDisplayString` with and without a hex over a scripted fight and a grid set into TTO's `disp` / `state`; forever: `ManaModel.Text` over every mode x time x rest), the face API (`vv`, `nodata`, `OOM --`, the bound, `inn`, `Current`), `SAMPLES` ASCII with no bare pipe and never a 0 for a missing value; `--print`, `--golden`

**`docs/TOOLS.md`** section 1: a new row after `ttocheck.lua`'s:

> | `clockfacecheck.lua` | **the clock face** (T88, tbc 17 / forever 14): `Engine/ClockFace.lua` loads and renders with Lua's library only; the goldens (tbc 689 lines: `GetDisplayString(nil)` and `("\|cff16c3f2")` over a scripted fight and a grid of display states -- every mode, the bound, the arrows, `vv`, the `inn` / `rest` segments and the 25 % rule, nil, `>10m`, the two switches; forever 389 lines: `ManaModel.Text` over every mode x time x rest), captured on `e2b13f4` before the split; the face API and `ClockFace.Current` on each line; `SAMPLES` ASCII, no bare pipe, nil never `0`. `--golden` prints the blocks to paste |

**`docs/HISTORY.md`**: wave N1's entry names T88. The TBC and Forever clock strings are
byte-identical (two goldens). `Engine/ClockFace.lua` is the face seam S4, which T92 (feeds) and T93
(clock parity) build on.

No `docs/DECISIONS.md` line: nothing visible changes (Deviations 2 is an unreachable state). No
`docs/TESTING.md` item: nothing to check in game.

## Deviations

1. **Two face fields beyond the spec's list: `timeFmt` and `mono`.** The two lines word a time
   differently: TBC writes `15s` under a minute, Forever always writes `0:15`. Forever's line also
   has no colour codes at all. A face that did not carry both could not be byte-identical on both
   lines. They describe how the line looks, not which client it is, so a renderer never branches on
   the client. T93's F1 (tones on Forever) is the place to turn `mono` off.
2. **`FULL 0s` became `FULL --` in one unreachable TBC state.** The old ooc / full branch formatted
   `v or 0`. The latch never reaches that state with no value, because it resets the value only on
   a mode the raw state already holds, and the raw `ooc` / `full` always carry `ttf`. Principle 4
   (`--`, never `0`) and the row's "nil never `0`" ask for `--`. The state is kept out of the
   golden and asserted on its own (3g).
3. **`ClockFace.Current(now)` takes the caller's time.** TBC uses it for the arrow and falls back on
   `GetTime()`. Forever passes it to `Pool:Project`, and uses the model's last tick when it is
   omitted, because `Engine/ManaModel.lua` makes no client call.
4. **Both producers create `MD.ClockFace` if it is absent**, and look `LineString` / `Tone` up at
   call time. `tools/clockcheck.lua`'s T68 check loads a second copy of the core without the face
   file (a hand-written list that T88 does not own), and `MD:Provide` needs the table. With the
   TOCs' order, `Engine/ClockFace.lua` comes first and keeps the table it finds.
5. **Forever's `fsr` and both lines' `tick` are nil for now.** The model's `lastSpend` is not in
   `Project`'s state. T93 (the spark) fills them.
6. **The TBC grid reaches TTO's locals through `debug.getupvalue`** (test only). Some shapes cannot
   be reached through events: `OOM --` (oom with no value), `OOM >10m =` (hold with no bound) and
   the `vv` / bound combinations at chosen values. The search walks `MD.GetClockFace`, then
   `MD.GetDisplayString`, so the same suite finds `disp` / `state` on the parent and after the
   split. The fight half of the golden is real events only.
7. **The TOC lines are not committed** (integrator-owned). They were applied in the working tree to
   run the suites and reverted. See "The checks" for what fails without them.
8. A comment in `Engine/TTO.lua` that held a non-ASCII dash was replaced along with the block it
   described.
