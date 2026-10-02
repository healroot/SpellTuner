# T114 -- Clock v2: the face's slots and words (C1, the pure half)

Status: **ready** 2026-10-02, the clock v2 round of `docs/SPEC-next.md` section 13 (the author's
answers to `docs/mockups/clock-v2.html`). Runs beside T115 (no shared file); T116 builds on both.

## The task (docs/mockups/clock-v2.html C1; docs/SPEC-next.md 13, 7.3 Text / Show, 2.3, 2.4)

> Every place a layout draws becomes a **slot** filled from one list. The face
> (`Engine/ClockFace.lua`) gains the `pct`, `mana`, `mp5` and `fsr` pieces; `LineString` (the
> datatext and broker string) follows Line's slots. Forever offers Mana % and Mana now as the
> model's `~` values; the real values wait for probe Q-clock-2 behind a seam (the `BAR_READS_MAX`
> pattern).

This task is the **words**: what each slot says, on each line, as plain data -- no frame. Drawing
the slots, the Text tab and the font options are T116's.

Owned files (the only files edited, apart from this one):

- `Engine/ClockFace.lua`
- `Engine/TTO.lua`
- `Engine/ManaModel.lua`
- `UI/Feeds.lua`
- `Integrations/Surface_LDB.lua`
- `Client/API_Forever.lua`
- `tools/clocktextcheck.lua` (new)
- `tools/surfacecheck.lua`
- `tools/euicheck.lua`
- `tools/adaptercheck.lua`

The author's answers used here (`docs/SPEC-next.md` 13):

- **Answer 3:** Line keeps **one** Right slot by default; a second Right slot (`right2`) is a user
  option, off (`none`) by default. Whether the width allows it is the renderer's (T116); here it
  is only a word list that is empty by default.
- **Answer 4:** on Forever, Mana % and Mana are offered now as the **model's** values, marked `~`.
  The real values replace them only after Q-clock-2 -- this task writes the seam, off.
- Everything else as the mockup recommends (C1's option table).

## What to build

### `Engine/ClockFace.lua` (pure; both lines)

It stays pure: Lua's library only, no frame, no `MD.db`, no client call (`clockfacecheck`'s "loads
with nothing else" check must keep passing).

**The face gains three fields** (documented in the file's face comment beside `pct` / `mp5` /
`fsr`):

- `mana` -- the pool's mana as a number, or nil;
- `manaMax` -- its max, or nil;
- `manaModelled` -- true on Forever (the model's), false on TBC (read plain).

`fsr` (seconds left in the five-second rule, nil after it) is already in the shape; T114 makes
both producers fill it (below).

**The slot kinds** (`CF.KINDS`, in the order a picker lists them):

| kind | words (TBC) | words (Forever) | tone in Main / the time's home | tone elsewhere |
|---|---|---|---|---|
| `label` | `OOM` / `FULL` (or `out` / `full`) | `~OOM` / `~FULL` | as today | as today |
| `time` | `1:20 v`, `>1:50 =`, `...`, `--` (today's value piece) | `0:15` (no arrow) | as today | as today |
| `pct` | `62%` | `~62%` | `mana` | `muted` |
| `mana` | `4210`, with `ofMax` `4210/6800` | `~4210`, `~4210/6800` | `mana` | `muted` |
| `mp5` | `92 mp5` | `~92 mp5` in combat, `92 mp5` out of combat | -- | `muted` |
| `fsr` | `5SR 3.0` while the rule runs; **nothing** after it | the same, from the model's last priced spend | -- | `warn` |
| `rest` | the face's `second` as today (`rest 2:10`, or TBC's `inn 2:10` when the producer chose it) | `rest 2:10` | -- | as today (`muted`, `mana` for `inn`) |
| `cd` | only a cooldown second (`inn 2:10`) | **not offered** (Forever has no mana-cooldown model) | -- | `mana` |
| `none` | nothing | nothing | -- | -- |

- A missing number reads `--` (`--%`, `-- mp5`), never `0` (TTO's rule). `fsr` with no rule
  running is an empty slot, not `--`.
- `fsr` has one decimal, `5SR 3.0`; it updates at the words' own cadence (TBC 0.25 s, Forever
  0.5 s); the smooth fill is T115's strip, not this text.
- **The default `rest` is byte-for-byte today's secondary**, gated by the producer exactly as
  today (TBC: `db.showRest` / `db.showCooldown` in `Engine/TTO.lua`; Forever: `look.show.rest`,
  F6). Nothing about the switches changes here.

**The slots per layout** (`CF.TEXT`, the defaults, and `CF.TEXT_OPTIONS`, the values each slot
accepts):

| layout | slot | values | default |
|---|---|---|---|
| line | `left` | label / pct / mana / none | label |
| line | `main` | time / pct / mana | time |
| line | `right` | rest / pct / mana / mp5 / fsr / cd / none | rest |
| line | `right2` (answer 3) | as `right` | none |
| compact | `top` | label / time / none | label |
| compact | `main` | time / pct / mana | time |
| compact | `bottom` (new) | as line's `right` | none |
| bar | `left` | label / pct / mana / none | label |
| bar | `right` | time / pct / mana / none | time |

And per layout, three word options: `labels` (`caps`: OOM / FULL, the default; `lower`: out /
full -- spec 7.3), `ofMax` (false; `mana` reads `4210/6800`), `time` (`line`: the line's own,
today's -- TBC `15s` / `1:20`, Forever `0:15`; `sec`: `80s`; `msec`: `1m20`, `15s` under a minute).
`>10m` reads the same in every format, and the format changes words only: the precision stays the
face's (Forever's 5-s steps, TBC's step ladder). `CF.Time(sec, fmt)` takes the two new formats;
`auto` / `mss` keep their bytes.

**`CF.ResolveText(stored, layout, facts) -> text, refused`** (pure). `stored` is one layout's
saved text table (sparse), `facts.cd` whether the line offers a cooldown (TBC true, Forever false).

- Every slot and option filled from `CF.TEXT`; a value the slot does not accept is ignored and
  named in `refused` (`text.line.right: cd is not offered on this line`).
- **The time is never lost** (it carries the honesty marks: `>` with `=`, `...`, `--`, `~`). Each
  layout has a *time's home* (line `main`, compact `main`, bar `right`). When the home is not
  `time`:
  - the first slot holding `label` (line `left`, compact `top`, bar `left`) draws the label **with**
    the time -- `OOM 1:20 v`, `~OOM 1:20` -- as the mockup's "Compact, Main = Mana %, Top = time"
    and "Bar, Left = Mana %, Right = time" rows show;
  - compact `top = time` draws the same pair;
  - if no slot can carry it, `main` (or bar `right`) is put back to `time` and the refusal named.
- **Forever's `~` cannot be configured away:** with `left = none` the value reads `~1:20`.

**`CF.Slots(face, text, layout) -> pieces`** (pure): `{ left, main, right, right2, top, bottom }`,
each nil or `{ text, tone, arrow, arrowTone }` in the shape `Segments` already returns (the arrow
only on a piece that carries the time).

**`CF.Segments(face, look)`** keeps its signature and its bytes: with `look.text` nil (or the line
defaults) it returns exactly today's `label` / `value` / `second`. With a `look.text` it returns
`CF.Slots` for Line, plus the old three names as aliases of `left` / `main` / `right` so every
current reader (the renderer, the brokers) keeps working until T116 reads the slots by name.

**`CF.JoinSegments(segs)`** adds `right2` after `right`, two spaces between.

**`CF.LineString(face, valueHex, text)`**: a third, optional argument, Line's resolved text.
Absent or default, it is **byte-identical** (every golden in `clockfacecheck` holds unchanged).
With picks, it words the same pieces in the same colour rules (`mono` still one colour).

Everything stays ASCII with no bare `|`.

### `Engine/TTO.lua` (TBC)

`MD:GetClockFace(now)` adds `mana = s.mana`, `manaMax = s.manaMax`, `manaModelled = false`. Its
`mp5` is checked against the regen feed's number (below) and changed only if they disagree. No
other byte of the face moves (`ttocheck` and `clockfacecheck` unchanged).

### `Engine/ManaModel.lua` (Forever; pure)

`ManaModel.Face(state, now)`:

- `mana = state.mana`, `manaMax = state.max`, `manaModelled = true` (plain numbers: the model's);
- `fsr = lastSpend + 5 - now` while positive, else nil -- from the state the pool hands it (add
  `lastSpend` to what `Project` / the provider passes if it is not there); a free cast never moves
  `lastSpend` (T68's pricing), so it never starts the rule;
- `mp5`: the same number the `regen` feed shows at that moment (the pool's last plain regen, the
  casting rate inside the rule), `mp5Modelled = true`. In combat the slot marks it `~` (the
  reading is the last plain one, as the regen feed's `~` says); out of combat it is plain.

`ManaModel.Text` stays byte-identical.

### `UI/Feeds.lua` (both lines)

The `clock` feed's text follows **Line's** slots: it asks `MD.ClockLook()` when provided (pcall,
as `Integrations/Surface_LDB.lua` does) and hands `look.texts.line` (the contract T116's resolver
fulfils: the resolved text of every layout under `look.texts`, Line's included whatever layout is
on screen) to `CF.LineString` as its third argument. Absent, it passes nil: byte-identical. The
ElvUI datatext (`Integrations/Surface_ElvUI.lua`) reads this feed, so it follows without an edit.

### `Integrations/Surface_LDB.lua` (both lines)

The `SpellTuner` broker's words: `CF.JoinSegments(CF.Segments(face, look))` with `look.text =
look.texts.line` when present. `db.feeds.compact` drops `right` and `right2`.

### `Client/API_Forever.lua` (Forever): the Q-clock-2 seam, off

- `MD.API.POWER_TEXT_READS = false` -- flipped by the integrator only on a Forever probe report
  that answers Q-clock-2 (`fs:SetText(UnitPowerPercent("player", 0))` shows a number), as
  `BAR_READS_MAX` / `BASE_CD_READS`.
- `MD.API.DrawPowerText(fs, unit, powerType, kind)` -- `kind` `"pct"` (`UnitPowerPercent`) or
  `"mana"` (`UnitPower`): the value goes straight into `fs:SetText`, **never read, compared,
  concatenated or formatted** (the sanctioned path, as `DrawUnitPower` for a status bar). Returns
  `true`, or `nil, "secret"` while the flag is false (nothing touched), `nil, "absent"` without
  the function. In `tools/adaptercheck.lua`'s `FOREVER_ONLY_NAMES`.
- Nothing calls it in this task. T116's renderer asks the Forever line's `draw.powerText` for it.

## The checks (fail first on the parent, then green)

The suites are committed alone first and run against the parent (`6fab263` or the round's base);
the new checks fail there.

**`tools/clocktextcheck.lua`** (new; `HARNESS_FLAVOUR = { "tbc", "forever" }`; the flavour's
whole TOC): **13 checks per flavour**, all failing on the parent (no `CF.Slots`).

1. `CF.Time`: `line` unchanged for both `auto` and `mss`; `sec` `80s`; `msec` `1m20` / `2m00` /
   `15s`; `>10m` in all three; nil never `0`.
2. **Defaults are today's:** for every `CF.SAMPLES` face, as this line draws it, with and without a
   value hex: `LineString(face, hex, CF.TEXT.line) == LineString(face, hex)` and
   `JoinSegments(Segments(face, {text = default}))` equals today's.
3. `CF.ResolveText`: the defaults per layout; an unknown value refused and named; `cd` refused on
   Forever, accepted on TBC; `right2` and `bottom` `none` by default.
4. TBC words: `pct` `62%`, `mana` `4210`, `ofMax` `4210/6800`, `mp5` `92 mp5`, `cd` `inn 2:10`.
5. Forever words: `~62%`, `~4210`, `~4210/6800`; `mp5` `~92 mp5` in combat, plain out of combat.
6. `mp5`'s number equals the `regen` feed's (`Feeds.RegenReading`) at the same moment, in and out
   of the rule, both lines.
7. `fsr`: `5SR 3.0` three seconds into nothing (TBC `MD.Regen:FSRRemaining`, Forever the model's
   `lastSpend`); empty after five seconds; a free cast on Forever does not start it.
8. `labels = lower`: `out 1:20 v` / `full 0:45`; Forever `left = none` reads `~1:20`.
9. The time is never lost: Line `main = pct` draws `OOM 1:20 v` on the left and `62%` in main;
   compact `main = mana`, `top = time` draws the pair on top; Line `main = pct`, `left = none` is
   refused and `main` reads the time again.
10. `right2`: `rest 2:10  62%` after two spaces in `JoinSegments` and `LineString`.
11. The pieces of compact (`top` / `main` / `bottom`) and bar (`left` / `right`) for every kind.
12. Every `SAMPLES` face x every kind in every slot of every layout x both time formats: ASCII,
    no bare pipe, never a lone `0` for a missing value (one matrix assertion).
13. The producers: TBC `MD:GetClockFace` carries `mana` / `manaMax` plain and `manaModelled =
    false`; Forever `ManaModel.Face` carries the model's with `manaModelled = true`, and under
    the forever profile no field of the face is a secret.

**`tools/surfacecheck.lua`** (+2 on each flavour: tbc 34 -> **36**, forever 41 -> **43**):

- the `clock` feed with a fake `MD.ClockLook` whose `texts.line.right = "pct"` reads `... 62%`
  (TBC) / `... ~62%` (Forever); with no provider it equals the existing golden;
- the ElvUI datatext follows (same text through `Surface_ElvUI`), and its golden is unchanged by
  default.

**`tools/euicheck.lua`** (forever, +2: 19 -> **21**):

- the `SpellTuner` broker follows Line's slots (`right = mp5` reads `~92 mp5` in combat);
- `db.feeds.compact` drops both `right` and `right2`.

**`tools/adaptercheck.lua`** (+2 forever: 24 -> **26**; +1 tbc: 16 -> **17**):

- forever: `DrawPowerText` is in `FOREVER_ONLY_NAMES`; with `POWER_TEXT_READS = false` it returns
  `nil, "secret"` and touches no font string and no client function (spied);
- tbc: `MD.API.DrawPowerText` is absent.

**Unchanged** (counts and goldens): `clockfacecheck` (both), `ttocheck`, `clockcheck`,
`clockui`, `clocksettings`, `stylecheck`, `minimapcheck`, `slashcheck/tbc`, `defaultscheck`
(no default is registered: the text lives in `db.clockLook.over`, T116's). `make check` green,
`python3 tools/apicheck.py` 0 findings (`UnitPowerPercent` is in the 69893 baseline and named only
under `Client/`), `python3 tools/textcheck.py` 0 findings.

## Integrator lines

- **TOCs:** none.
- **`tools/data/expected-counts.json`:** `"clocktextcheck/tbc": 13`, `"clocktextcheck/forever":
  13`, `"surfacecheck/tbc": 36`, `"surfacecheck/forever": 43`, `"euicheck/forever": 21`,
  `"adaptercheck/forever": 26`, `"adaptercheck/tbc": 17` (the task file states the final numbers
  if a check had to be split).
- **`tools/check.sh`:** nothing (`clocktextcheck` declares its flavours).
- **`CLAUDE.md`:** `Engine/ClockFace.lua`'s row: `**T114:** the face's mana / manaMax /
  manaModelled; the slot kinds (CF.KINDS: label, time, pct, mana, mp5, fsr, rest, cd, none), the
  slots per layout with their defaults and accepted values (CF.TEXT / CF.TEXT_OPTIONS: Line left /
  main / right / right2, Compact top / main / bottom, Bar left / right), the word options (labels,
  ofMax, time line / sec / msec), CF.ResolveText (the time never lost: a label slot carries it
  when its home holds another kind; Forever's ~ kept), CF.Slots; Segments / LineString follow
  Line's slots, byte-identical by default`. `Engine/ManaModel.lua`'s row: `**T114:** the face
  carries the model's mana / manaMax, fsr from the last priced spend, and the regen feed's mp5`.
  `UI/Feeds.lua` and `Integrations/Surface_LDB.lua` rows: `**T114:** the clock words follow Line's
  slots (MD.ClockLook().texts.line)`. `Client/API_Forever.lua`'s binding list: `**T114:**
  DrawPowerText and MD.API.POWER_TEXT_READS = false (Q-clock-2; the BAR_READS_MAX pattern)`. The
  `tools/` row: `**tools/clocktextcheck.lua** (T114, tbc / forever 13): the clock's slots and
  words ...`.
- **`docs/TOOLS.md`** section 1: a `clocktextcheck.lua` row; the `surfacecheck`, `euicheck` and
  `adaptercheck` rows' counts.
- **`docs/DECISIONS.md`:** part of the round's "Clock v2" entry (T116 writes the text, see there):
  Forever's Mana % and Mana are the model's `~` values until Q-clock-2, `POWER_TEXT_READS` off.
- **`docs/HISTORY.md`:** the round's entry names T114.

## Out of scope

- Drawing the slots, the Text tab, the size / outline / shadow / numbers options, Right2's width
  rule (T116).
- The bars, the frame's size and scale, the 5SR strip (T115).
- The real Forever mana text: flipping `POWER_TEXT_READS` waits for a Forever probe report on
  Q-clock-2, and how a real percent is formatted (0..1 or 0..100) is that report's question.
- The Ring layout (T104).
