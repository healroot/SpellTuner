# SPEC: clock v3 -- one bar, a stable renderer, settings that each do something

Architect, 2026-11-08. Status: **draft for the author's approval**. The settings list is approved
through the mockup `tools/.cache/clockv3/index.html`.

The author's words (2026-11-08, after T142-T144 on Forever):
- "now you broke most of the settings, they just dont apply"
- "the times shows 10s, 5s, 0s when mana was full"
- "moving line stops working"
- "so lets refactor the whole viewer, to make it stable efficient, and you can simplify settings that
  really provide value, as there are lots of colour picker that dont really change anything and
  nobody will ever touch"

The diagnosis of the three bugs is `docs/review/clock-v3-diagnosis.md`. This spec replaces
`UI/ClockView.lua` (2479 lines) and rewrites `UI/ClockSettings.lua` (2005 lines). The hosts
(`UI/Clock_Forever.lua`, `UI/Widget.lua`) keep the frame, visibility, drag and hover.

## 0. Principles (each one answers a bug)

- **P1. Every control visible in the pane changes what the live clock draws, from every state the
  pane can be in.** A control that would be inert is hidden, never only dimmed. This is a test
  (section 4.2), not a guideline. (Bug 1)
- **P2. A preset never switches off the time or the 5SR line, and it can be undone.** (Bugs 1, 3)
- **P3. At full mana the clock says FULL.** It never shows a zero or a lone refill number that
  reads like an OOM countdown. (Bug 2)
- **P4. The moving line has one driver that nothing else turns off.** It is installed once and
  never removed. A rebuild changes its geometry only. (Bug 3)
- **P5. The layout is computed once per look change; a paint only sets text and colour.** There is
  no measuring and no anchoring on the tick, the power event or the frame.
- **P6. Tests run the author's path:** Settings control -> `db` -> `CLOCK_LOOK` -> the live frame,
  with faces made by the real model through a whole fight.

## 1. Product

### 1.1 What the clock is

One bar: the game's own mana fill, with texts placed round it. On it, while the five-second rule
runs, the moving amber line.
- **Forever:** the fill and the mana numbers are drawn by the game, unread
  (`ST.API.DrawUnitPower` / `DrawPowerText`). The time is the model's.
- **TBC:** the same bar, with plain reads through the TBC adapter.

**Decision D1: Line and Compact layouts are dropped. The Bar is the only layout, on both lines.**

| Option | For | Against |
|---|---|---|
| Keep all three | Nobody loses a layout | Line/Compact need the slot system, measured minimums, the Right2 fit, per-layout bars/text/frame (most of ClockView's 2479 lines and half the look keys). They triple the test space that already hid inert controls |
| **Bar only** (chosen) | The author uses it on both clients (Forever and TBC stores both say `layout = "bar"`). It has been the default for new installs since T131. A text-only clock already exists as the datatext / LDB / ElvUI feeds (`ClockFace.LineString`) | A beta user with a saved `line` / `compact` gets the Bar with default texts (migration 1.4, named in `/st dump` and the changelog) |

The feeds stop reading Line's slots (`ST.ClockLook().texts.line`). They draw today's default
`LineString`, byte for byte what they drew before any Text-tab change.

### 1.2 What the time says (the FULL rule, P3)

The Time text's words come from one pure function (section 2.2). They are, in order:

| Situation | Words | Colour |
|---|---|---|
| Full: the face's mode `fullnow`; or a filling mode (`full` in a fight, `ooc` out of one) with a shown time under 5 s; or the face's `pct >= 0.995`; or the pool's quiet-full signal (2.4) | `FULL` | the text's colour |
| Filling, a time of 5 s or more | `FULL 0:45` / `FULL 45s` | the text's colour |
| Running out, a time | `1:20` / `80s` (TBC: plus its arrow, `1:20 v`) | the text's colour; with **Warn colours** on, red under 20 s and amber under 60 s |
| Running out, a bound (TBC) | `>1:50 =` | muted |
| Warm-up (not enough casts yet) | `...` | muted |
| Hold / no number | `--` | muted |
| Over ten minutes | `>10m` | the text's colour |

- An OOM time carries no word: a bare number on a mana bar is the time to OOM. This is the
  author's approved look.
- A refill time always carries `FULL`, so it can never be read as an OOM countdown.
- The separate **Label** text is gone: its words now live in the time.
- **Steady** (T144's rule, kept): within one state, the shown time moves at most once a second, one
  5 s step at a time. It snaps on a change of state, a nil, or a gap of 60 s or more. Forever only:
  TBC keeps its own sigma precision and latch (`Engine/TTO.lua`).
- **Entering FULL always snaps**: no steps down to it.

### 1.3 Settings that survive

Every current setting, with its fate. Keep = kept as is. Merge = folded into another setting.
Drop = removed. On a migrated store a dropped key is named in a `/st dump` line.

**The look (`db.clockLook`):**

| Today (key) | Where | v3 | Why |
|---|---|---|---|
| `layout` line / compact / bar | Layout row | **Drop** | D1 |
| `bars.<L>.show` both / mana / fsr / none | Bars tab | **Merge** into **5SR line: On / Off**. The mana bar is always drawn | `mana` is the switch that hid the line (bug 3). `fsr` / `none` make a bar with no mana, which nobody uses |
| `bars.<L>.join` stacked / veil / chip / sweep | Bars tab | **Drop**: the moving line only | The author chose the line (T135, T142 default). The other three are the code that made 5SR settings inert |
| `bars.<L>.order`, `bars.<L>.fsr` (strip px), `bars.<L>.after` green / empty / tick | Bars tab | **Drop** | Only Stacked used them. After the rule the line simply goes away (the author picked `empty`) |
| `bars.<L>.mana` game / model | Bars tab | **Drop**: always the game's pool | The model's bar was a stopgap before `DrawUnitPower` |
| `bars.<L>.texture` | Bar look | **Keep** (minus `gradient`) | It visibly matters; the list scrolls since T144 |
| `bars.<L>.shape` rect / round / pill / thin | Bar look | **Keep** rect / round / pill; `thin` dropped | Thin is just a low Height |
| `bars.<L>.frame` none / border / game | Bar look | **Keep** None / Border / Game frame | The game frame is the author's |
| `bars.<L>.border` 0-3 px | Bar look | **Merge** into Frame = Border (1 physical px, black) | Width is invisible above 1 px on an 8 px bar; 0 is Frame None |
| `bars.<L>.height` | Bar look | **Keep** as Height 3-30 | -- |
| `bars.<L>.font` eui / st | Bar look | **Keep** | The author uses EllesmereUI's |
| `frame.<L>.w` | Frame tab | **Keep** as Width 100-400 | -- |
| `frame.<L>.h` | Frame tab | **Drop** | The Bar's height is the bar's (T142) |
| `frame.<L>.scale` | Frame tab | **Drop** | Width, Height and each text's size cover it; a scale breaks pixel snapping |
| `panel.fill`, `panel.edge`, Background alpha, "none" | Frame tab | **Drop** | The Bar has no panel (T139) |
| `bar.back` | Bar look | **Keep** as **Background**: colour + opacity | -- |
| `colors.manaBar` mana / tone / class / colour | Colours, Bar look | **Keep** as **Fill**: Mana blue / Class colour / Custom | `tone` dropped: the time's Warn colours say urgency |
| `colors.fillEnd` | Bar look | **Drop** | Only Gradient used it |
| `colors.edge` | Bar look | **Drop**: black | Inert under the game frame (bug 1) |
| `colors.fsrLine`, `colors.after` | Bar look | **Drop**: amber, fixed | Meaning colours. Inert under `show = mana` (bug 1) |
| `colors.crit / warn / normal / good / muted / mana` | Colours tab | **Drop** | Inert on the Bar (bug 1). Warn colours use the fixed crit / warn tones |
| `text.<L>.<slot>`, `.ofMax`, `.size`, `.outline`, `.shadow`, `.numbers` | Text tab | **Drop** | Line / Compact only |
| `text.<L>.labels` caps / lower | Text tab | **Drop** | One word left (`FULL`) |
| `text.<L>.time` line / sec / msec | Text tab | **Keep** as **Time as: 1:20 / 80s** (`msec` -> `80s`) | The author picked `sec` |
| `text.bar.items.label.*` | Bar look | **Merge** into the time's words | 1.2 |
| `text.bar.items.<kind>.*`, kinds time / mana / manaMax / pct / mp5 / fsr / rest; fields on / place / align / x / y / size / colour / outline | Bar look | **Keep**, every field | The author asked for them. An off row shows only its switch (P1) |
| -- | -- | **New**: Time -> **Warn colours** (on) | Replaces the six tone swatches with the one place urgency matters |
| Presets: default / eui / below / pill / thin | Bar look | **Two presets: SpellTuner, EllesmereUI. Plus Undo** | P2 |

**The clock's switches (`db.clock`):**

| Today | v3 |
|---|---|
| `shown` (Show the mana clock), `locked` (+ the 60 s preview), `point`, `clickThrough` | **Keep** |
| `showRest` (Forever), `db.showRest` / `db.showCooldown` (TBC) | **Merge**: the Rest text's own switch. The TBC keys stay for the feeds; the clock no longer reads them |

**Count:** today about 75 look keys over 6 tabs and 3 layouts. v3 has **11 bar fields + 7 texts x 8
fields + 2 time options**, on one pane with no tabs.

### 1.4 Presets (P2)

Two presets:
- **SpellTuner**: the default. It is the author's T142 pick:
  - the game frame, rounded, 200 x 8, Pixels Dark (Soft without EllesmereUI), EllesmereUI's font;
  - fill 396DA7 on 0A0A0A;
  - the line on;
  - the time below left, the mana inside centre, the regen below right, every text 11 E4E1DC none
    except the regen, 9FD7A9.
- **EllesmereUI**: EllesmereUI's resource bar:
  - the game frame, round, 260 x 8, Pixels Dark;
  - the fill from EllesmereUI's mana colour when loaded, else 008CFF; background 111111 at 75 %;
  - **the line on**;
  - the mana inside centre (15, outline, y +2), the time below right (11, outline), the regen off.

Rules:
- A preset **replaces the whole look**, not a merge, in one `CLOCK_LOOK`.
- Before it does, the store keeps the previous look as a session-only `undo` snapshot.
- **Undo** puts it back. Undo is offered until the next change or a reload.
- No preset may set `line = false` or `texts.time.on = false`. A test enforces this.

### 1.5 The store and its migration

**Decision D2: the store is dense and versioned.** `db.clockLook = { v = 3, ... }` holds every
field. `Normalize` fills a missing or invalid field from the default and names it. Today's store is
sparse: "nil means default" and "a preset writes nil when equal". That made "what is drawn" depend
on default tables in three files, and made `false` vs `nil` a known trap (`UI/ClockSettings.lua:377`).
The cost of dense is that a future default does not move an existing user's look. For a look the
user tuned, that is wanted.

```
db.clockLook = {
  v = 3,
  width = 200,            -- 100..400
  height = 8,             -- 3..30
  shape = "round",        -- rect | round | pill
  frame = "game",         -- none | border | game
  texture = "eui:pixels-dark", -- own key | "eui:<key>" | "lsm:<name>"
  font = "eui",           -- eui | st
  fill = "mana",          -- mana | class | "RRGGBB"
  back = "0A0A0A", backAlpha = 1.0,
  line = true,            -- the moving 5SR line
  timeFmt = "mss",        -- mss ("1:20") | sec ("80s"); Forever's mss, TBC's auto when "mss"
  warn = true,            -- the time red < 20 s, amber < 60 s while running out
  texts = {               -- kinds in drawing order
    time    = { on, place, align, x, y, size, colour = "RRGGBB", outline },
    mana    = { ... }, manaMax = { ... }, pct = { ... }, mp5 = { ... }, fsr = { ... }, rest = { ... },
  },
}
```

- Ranges and lists are as today's: x -40..40, y -20..20, size 6..32, outline none / outline /
  thick / shadow, place inside / above / below, align left / center / right.
- TBC's `timeFmt = "mss"` means its own `auto` ("15s" under a minute): the face's `timeFmt`,
  as today's `time = "line"`.

**Migration** `ClockStore.Migrate(raw) -> v3, notes`. It is pure and idempotent. It runs once at
`MD_READY`, and the dump line names what was dropped or changed.
- **v1 (0.16.6, `over.bar.source/color/...`)**: today's `CV.Migrate` rules run first, read into v2
  terms. The function moves to `UI/ClockStore.lua` as is.
- **v2, `layout = "bar"`**:
  - `frame.bar.w` -> `width`; `bars.bar.height` -> `height`;
  - `shape`, `frame`, `texture`, `font`: each copied when the new list accepts it. `thin` becomes
    `rect` with height 4 when no height is set. `gradient` becomes `flat`;
  - `bars.bar.frame == "border"` stays `border`, and its `border` px is dropped;
  - `colors.manaBar`: `mana` / `class` kept; a colour becomes hex; `tone` becomes `mana`;
  - `bar.back` becomes hex + `backAlpha`;
  - `text.bar.time`: `sec` / `msec` become `sec`, else `mss`;
  - `text.bar.items.<kind>`: every field over the T142 default for that kind, as `ResolveItems`
    does today. `label` is dropped;
  - **`line = true` always.** This is decision D3.
- **v2, `layout = "line"` / `"compact"`**: the v3 defaults. Each Bar-layout key the store holds is
  migrated as above. The Line/Compact keys are dropped and named.
- **No store / v nil**: the defaults.
- Afterwards `db.clockLook` holds only v3 fields. `over` and `layout` are removed. An older build
  reading a v3 store finds no `over` and draws its own defaults. That is safe and loses only the
  look.

**Decision D3: the migration turns the moving line on** (alternatives below).

| Option | For | Against |
|---|---|---|
| Keep `show = "mana"` as line off | Faithful to the store | The author's complaint is that the line stopped. The off came from a preset that called itself "no 5SR line" in a tooltip only, so it was never a choice the author made knowingly |
| **On, named in the dump and the changelog** (chosen) | Fixes the complaint. One click turns it off, on the same pane as the rest of the look | It overrides a stored value once. The mockup shows it on, so the author approves it there |

The author's live store migrates to:
- width 260, height 8, round, game frame, Pixels Dark, EllesmereUI's font;
- fill 008CFF, back 111111 at 0.75, the line on, time `sec`, warn on;
- texts:
  - time on, below right, 0 / +1, size 15, E3E3E3, outline;
  - mana on, inside centre, 0 / +1, size 14, E3E3E3, outline;
  - regen off (inside left, 0 / +1, 15, CDD4D0, outline: kept for when it is turned on);
  - manaMax off (12, E3E3E3, outline); pct off (inside right, -4 / 0, 10, E3E3E3, outline);
  - 5SR off (below left, 0 / -1, 10, FFAB33, outline); rest off (below right, 0 / -1, 10, 8F8A83,
    outline);
- dropped: `label` (inside left, 4 / 0, 10: "its word is now part of the time"), `after = empty`,
  `fsr = 2`;
- changed: `show = mana` -> the line on.

This exact table is the golden of section 4.5.

## 2. Architecture

### 2.1 Files and owners

| File | Role in v3 | Pure? | Lines (target) |
|---|---|---|---|
| `Engine/ClockWords.lua` **new**, every main TOC, after `Engine/ClockFace.lua` | `ST.ClockWords`: the words each text draws from a face (the FULL rule, Steady, the per-kind words); the quiet-full rule (`QuietFull`) | yes | ~200 |
| `UI/ClockStore.lua` **new**, every main TOC, before the renderer | `ST.ClockStore`: the v3 schema, `Normalize`, `Migrate`, `Look` (a validated copy), `Set` / `SetText` / `ApplyPreset` / `Undo` / `Reset` (each one write and one `CLOCK_LOOK`), `PRESETS`, `DumpLine` | yes (only `ST.db` and `ST:Fire`) | ~350 |
| `UI/ClockBar.lua` **new**, replaces `UI/ClockView.lua` | `ST.ClockBar`: the renderer. `New(host, draw)`, `:Apply(look)`, `:Paint(words)`, `:PaintPower(withMax)`, `:Message(text)`, `:Pulse()`, `:Drawn()` (the test snapshot) | no | ~600 |
| `UI/Clock_Forever.lua` (host, Forever) | Frame, drag, hover, visibility (one owner), the tick: model -> face -> words -> `Paint`; `UNIT_POWER_FREQUENT` -> `PaintPower`; `CLOCK_LOOK` -> `Apply`; the steady latch | no | ~400 (from 557) |
| `UI/Widget.lua` (host, TBC) | The same for TBC: `ST:GetClockFace()` -> words; the power path through TBC's adapter | no | ~300 |
| `UI/ClockSettings.lua` rewritten | One pane, no tabs: preview, Bar, Texts, Presets, When; every control in a **control registry** (`CS.CONTROLS`) the end-to-end test walks | no | ~800 (from 2005) |
| `Engine/ManaPool_Forever.lua` | + the quiet-full anchor (2.4) and `UNIT_POWER_FREQUENT` bookkeeping (it owns the model, so it owns the event's meaning) | -- | +30 |
| `Client/API.lua` | `DrawUnitPower` split: `DrawUnitPowerMax(bar)` (min / max: on a look, the tick, `UNIT_MAXPOWER`) and `DrawUnitPower(bar, smooth)` (the value only). This closes T142-T143 review W1 | -- | +15 |
| `Client/API_TBC.lua` | `ST.API.DrawPowerText` for TBC (plain reads, the same kinds and formats), so both hosts hand the renderer the same `draw` | -- | +25 |
| `UI/ClockView.lua` | **Deleted**. `Engine/ClockFace.lua` loses the slot system (`TEXT_SLOTS`, `TEXT_OPTIONS`, `ResolveText`, `Slots`, `ItemPieces`) and keeps `LineString`, `Segments`, `Time`, `Tone`, `ToneRGB` / `ToneHex`, `SAMPLES` for the feeds, the hover and the tests | -- | -2479, about -250 |

Fixed boundaries:
- **The adapter rule.** No new file outside `Client/` calls the client. The renderer calls frame
  methods (the widget toolkit) and the `draw` callbacks only.
- **Secrets.** `UnitPower`, `UnitPowerMax` and `UnitPowerPercent` reach the renderer only as
  `draw.pool(bar)`, `draw.poolMax(bar)` and `draw.powerText(fs, kind)`. These go into
  `ST.API.DrawUnitPower` / `DrawUnitPowerMax` / `DrawPowerText`, which hand the value to the bar or
  the font string unread. Nothing reads a power text or the bar back: no `GetText`, no
  `GetStringWidth`, no `GetValue` on them, and nothing is anchored to them.
- **Visibility.** The renderer never calls `Show` / `Hide` on the host frame. Only the host's
  `UpdateVisibility` does, through `ST.Visibility.Want`, which is unchanged.
- **A shared file never branches on the line.** A difference is a value the host passes: its
  `draw`, the `steady` latch and the quiet-full answer.

### 2.2 Data flow

```
  CLOCK_LOOK / STYLE_CHANGED / MD_READY                                  (rare: a setting changed)
  db.clockLook --ClockStore.Look()--> look (validated, dense copy)
        |
        v
  ClockBar:Apply(look)     LAYOUT, ONCE: frame size, texture, shape masks, game art, edge, fill
                           colour, every text's font / anchor / justify / shown, the line's
                           height and the bar width the driver reads; then PaintPower(true) and
                           Paint(last words)

  tick, 0.5 s (host)                                                     (cheap)
  model / TTO -> face -> ClockWords.Build(face, look, latch, now, out, quietFull) -> words
        |                                                     (one reused table, no allocation)
        v
  ClockBar:Paint(words)    each shown text: SetText only if its string changed; the time's colour
                           only if its tone changed. No anchors, fonts or measures. Power kinds
                           drawn by the line are skipped
  ClockBar:PaintPower(true)

  UNIT_POWER_FREQUENT (player)                                           (cheap, frequent)
  ClockBar:PaintPower()    draw.pool(bar) [SetValue only]; each shown mana / manaMax / pct text:
                           draw.powerText(fs, kind); a refusal: the model's words from the last
                           Paint, the kind marked modelled
  UNIT_MAXPOWER            ClockBar:PaintPower(true)

  every frame: the line driver (its own frame)                           (one compare when idle)
  e = draw.fsrEnd(); if lineOn and now < e: x = barW * (5 - (e - now)) / 5, SetPoint the line and
  its back, shown; else hide them once
```

**`ClockWords.Build(face, look, latch, now, out, quietFull) -> out`**, pure:
- `out` holds `time`, `mana`, `manaMax`, `pct`, `mp5`, `fsr` and `rest`, each `{ text, tone }`,
  or `text = nil` for nothing to draw.
- `out.full` is true when the FULL rule held. `out.modelled` lists the power kinds that came from
  the model (for the hover).
- `look.timeFmt` picks the time format and `look.warn` the time's tone.
- It uses the T144 Steady rules (moved from `ManaModel.Steady`, which stays as an alias) when
  `latch` is a table. Entering FULL snaps.
- It allocates nothing when `out` is passed. The host keeps one `out`.
- The per-kind words are today's `KindPiece` without the `~`, moved here.

**The FULL rule** (1.2): `ClockWords.IsFull(face, quietFull)` is true when any of these holds:
- `face.mode == "fullnow"`;
- `quietFull` is true;
- `face.pct` is plain and `>= ClockWords.FULL_PCT` (0.995);
- the mode is `full` or `ooc`, and the face's value is a point under 5 s (after rounding: a shown 0).

`FULL_PCT` is a named constant.

### 2.3 The renderer (`UI/ClockBar.lua`)

**Regions and their single owner**: every region is made once in `New`.

| Region | Parent | Written by | Notes |
|---|---|---|---|
| `bar` (StatusBar) | host | `Apply` (texture, colour, size, masks); `PaintPower` (value, via `draw.pool`); `PaintPower(true)` (min / max, via `draw.poolMax`) | holds the secret; nothing anchors to its fill |
| `back`, `edge` (textures) | host | `Apply` only | `edge` shown only for Frame = Border |
| shape masks (a pair on `bar`; pairs on host for `back` and `edge`) | -- | `Apply` only | today's `MaskPair` / `Clip` |
| game art, game masks, four bevels | host / bar | `Apply` only | today's `BuildGame` / `PlaceGame`, moved as is |
| `line`, `lineBack` (textures on `bar`, OVERLAY 1-2, clipped by `bar`'s shape masks) | bar | **the driver only** (position, shown); `Apply` sets their size | a mask must live on the frame of the texture it clips |
| `driver` (a plain 1x1 Frame, no textures) | host | its `OnUpdate`, set **once in `New`, never cleared** | always shown while the host is; holds no secret; not a StatusBar |
| `texts[kind]` (one FontString per kind, 7, on a `holder` frame above `bar`) | holder | `Apply` (font, flags, shadow, anchor, justify, shown); `Paint` (text, time colour); `PaintPower` (power kinds) | an off kind is hidden by `Apply` and skipped by `Paint` |
| `msg` (FontString) | holder | `Message` | the preview's "SpellTuner - drag me"; while it shows, `Paint` writes nothing and the texts are hidden |

**The line driver** (P4):
- Its state is two plain fields on the renderer, `barW` and `lineOn`, both set by `Apply`.
- It reads one callback, `draw.fsrEnd()`, which answers a plain time:
  - Forever: `model.lastSpend + 5`;
  - TBC: `ST.Regen.fsrEnd`;
  - nil: no rule.
- Each frame: if `lineOn` and `now < fsrEnd`, it places the two line textures at
  `barW * (5 - (fsrEnd - now)) / 5` and shows them. Otherwise, if they are shown, it hides them
  once.
- `Apply` changes `barW` and `lineOn` and never touches the script. `Message`, the preview and
  `PaintPower` never touch the line.
- A new spend needs no event: the next frame reads the new `fsrEnd`.
- The only thing that stops it is the host frame hidden, when there is nothing to draw.
- **Why a separate frame:** the old step lived on a StatusBar that the client eases (T143) and that
  holds a secret. It also had two hosts and a `stepping` flag kept in step by hand
  (`docs/review/clock-v3-diagnosis.md`, bug 3).

**`Apply(look)`**:
- It is the only function that anchors, sizes or sets a font, and it runs only on a look change.
- It computes each text's anchor from place, align, x and y against the bar's rect (T142 / T144
  rules). It never measures a string, and no text changes the frame's size.
- It sets the host's hit-rect insets so that hover and drag reach the texts above and below. The
  extent comes from the outside texts' sizes (`size + 2` per side), never from a measure.
- A shape change only sets mask files. `AddMaskTexture` runs once per texture (today's
  `Clip` / `pair.on`).
- After `SetStatusBarTexture` the fill texture is re-clipped, because the client may hand back a new
  texture object (today's `GameClip`).

**`Paint(words)`**:
- For each shown kind not drawn by the power path: `SetText` only when the string differs from the
  last one written (a Lua compare of plain words).
- For the time: `SetTextColor` only when the tone changed.
- No table allocation.

**`PaintPower(withMax)`**:
- `draw.pool(bar)`; with `withMax`, `draw.poolMax(bar)` first.
- For each shown mana / manaMax / pct text: `draw.powerText(fs, kind)`. If it does not answer true,
  the model's words from the last `Paint` are written instead, and the kind is marked modelled for
  the hover (T144 S1).
- The frequent event calls it without `withMax`, so the client only gets `SetValue` and its easing
  is never restarted by `SetMinMaxValues` (review W1).

**`Drawn()`**: a plain snapshot of what the user can see, from the renderer's own write cache, never
read back from a region.
- Per text: shown, words (a power kind reads `<power>`), face, size, flags, shadow, point, colour.
- The bar: shown, size, texture path, colour, alpha.
- `back` and `edge`: colour, shown.
- Mask files; game art shown.
- The line: shown, x.
- `msg`; the host's size.

The tests compare these snapshots (4.2).

### 2.4 FULL on Forever: the quiet pool

The model cannot see drinks, Innervate, potions or Clearcasting, so it lags a full real pool (bug 2,
part 3). No secret may be read. **But an event's arrival is plain: the client fires
`UNIT_POWER_FREQUENT` while the pool changes, and stops when it is full.**

`ClockWords.QuietFull(now, lastPowerEvent, lastSpend, base) -> bool`, pure, is true when all of
these hold:
- `lastPowerEvent` is a number and `now - lastPowerEvent >= QUIET`. QUIET is 3.0 s, **VERIFY**, a
  named constant with provenance;
- `now - (lastSpend + 5) >= QUIET`: the base rate has run through the whole quiet window;
- `base` is plain and `base * QUIET >= 2`: at that rate at least two points would have come in, so
  the silence is not a slow trickle.

In `Engine/ManaPool_Forever.lua`:
- It registers `UNIT_POWER_FREQUENT` (player) itself, keeps `Pool.lastPowerEvent`, and counts for
  the dump: `pool: power events N, quiet-full anchors M`.
- `Pool:QuietFull(now)` is the rule applied to its own fields.
- On each tick, when it holds and `model.mana < model.max`, it calls
  `model:Anchor(now, model.max, "the game's pool stopped moving")`. This applies in and out of
  combat. The assume-full rule stays.
- The flag `Pool.QUIET_FULL` ships **on**.
- `docs/TESTING.md` §66 step 1 has the author confirm that the event fires while regenerating and
  is silent at full.
- If it also goes quiet while regenerating (a batched tick longer than QUIET), QUIET is raised to the
  measured gap. It never becomes a guess.

Not fixed by this: a model *above* the real pool (an under-priced cost). That is recorded as open in
DECISIONS. The hover keeps saying the time is modelled.

### 2.5 The hosts

Forever's tick (the old `PaintFace`):
```
state = ST.Pool:Project(now)
face  = ST.ManaModel.Face(state, now)
words = ST.ClockWords.Build(face, look, steady, now, wordsOut, ST.Pool:QuietFull(now))
bar:Paint(words); bar:PaintPower(true)
```
- The preview (Message), the pulse, the hover and `KeepCentre` stay. The hover's bar sentence is
  worded from `look.line`, not from joins.
- `KeepCentre` is used only for a Width change.
- The steady latch is also reset when a preview ends (T144 N3).

TBC's widget:
- It is the same, with `ST:GetClockFace()`, latch nil and quietFull false.
- TBC reads the real pool, so its face's `pct` is real and `FULL_PCT` covers its in-combat
  `full` / ttf 0.

### 2.6 Failure modes

| Failure | Behaviour |
|---|---|
| `draw.powerText` refuses (no `CurveConstants`, an error) | The model's words, the kind marked modelled, the hover says so (T144 S1, kept) |
| EllesmereUI absent: texture `eui:*`, font `eui` | Soft and SpellTuner's font. The pane names the reason beside the control (`look.notes`) |
| No mask textures on the client | A rectangle, with the reason beside Shape |
| No game atlas | Frame Border, with the reason beside Frame |
| A stored field is invalid (hand edit, older build) | `Normalize` puts the default and the dump names it |
| A `QuietFull` false positive (a batched regen gap over QUIET) | The model reads full while the real pool is not; QUIET is the fix (the VERIFY step) |
| The host frame is hidden | The driver does not run, which is correct. On show, the next frame places the line |
| A `CLOCK_LOOK` mid-rule | `Apply` changes the geometry; the driver moves the line on the next frame (a test) |
| A preset or migration that would hide the time or the line | Refused by `ClockStore` (`ApplyPreset` validates P2) |

## 3. The Settings -> Clock pane

The mockup `tools/.cache/clockv3/index.html` is the approved form. The pane is one sheet with no
tabs, top to bottom:

1. **Preview**: a `ClockBar` instance on a ground strip.
   - Sample states: **In a fight** (`1:20`, the 5SR line running), **Running out** (`0:15`, red with
     Warn colours), **Filling** (`FULL 0:45`), **Full** (`FULL`), and **Live** (the real face).
   - **Show on screen** is `Clock:Preview(60)`.
   - The live clock is the real check; the preview follows every change at once.
2. **Bar**:
   - Width (slider 100-400) and Height (slider 3-30);
   - Shape: Rectangle / Rounded / Pill;
   - Frame: None / Border / Game frame;
   - Texture (the scrolling list);
   - Font: EllesmereUI's / SpellTuner's;
   - Fill: Mana blue / Class colour / Custom (with a swatch while Custom);
   - Background (swatch with opacity);
   - 5SR line: On / Off.
   - A control the client cannot honour shows the reason in muted text beside it ("EllesmereUI is
     not loaded: Soft"). It stays clickable, because the choice is kept for when it can be drawn.
3. **Texts**: one row per kind: Time, Mana, Mana / max, Mana %, Regen, 5SR, Rest.
   - An **on** row shows Place, Align, X, Y, Size, Colour and Outline. The Time row adds
     **Time as** (1:20 / 80s) and **Warn colours**.
   - An **off** row shows only its switch, its name and a sample in muted text. Its fields are
     hidden (P1) and kept in the store.
   - The Place, Align and Outline step buttons stay: no dropdown inside a scrolling list (T142's
     reason).
4. **Presets**: SpellTuner, EllesmereUI, Undo (shown only while an undo is held).
5. **When**: Show the mana clock, Locked, Click-through (the line's own `CLOCK_SWITCHES`, as
   today, minus Rest).

The pane is built from `CS.CONTROLS`, a list where each entry declares:
- `id`;
- `kind` (`buttons` / `slider` / `dropdown` / `swatch` / `check` / `number` / `step`);
- `key` (a store path, e.g. `texts.mana.size`);
- `values`, the test's sample values to cycle;
- `visible(look)`, when the control shows (e.g. an off row's fields: `look.texts.mana.on`);
- `write(value)`, through `ClockStore`.

The end-to-end test walks the same list, so a control cannot exist without being tested.

## 4. Tests

The new suites replace `tools/clockui.lua` (its clock half), `tools/clocksettings.lua` and
`tools/clocktextcheck.lua`. Expected counts are re-based in unit U5. Every suite runs on both
flavours unless it says Forever.

### 4.1 `tools/clockwordscheck.lua` (U1, pure)

- The FULL rule as a table: each face and quiet value gives the words.
  - fullnow -> `FULL`;
  - in a fight, mode `full`, ttf 0 -> `FULL` (**bug 2's case**);
  - ooc ttf 2.4 -> `FULL`;
  - ooc ttf 12 -> `FULL 0:10` / `FULL 10s`;
  - pct 0.996 in a fight with mode `full` and ttf 20 -> `FULL`;
  - oom 80 -> `1:20`, or `80s` with `sec`;
  - oom 15 with warn -> tone crit;
  - warmup -> `...`; hold -> `--`; over 600 -> `>10m`; TBC bound -> `>1:50 =`.
- **No word set ever contains `0s` or `0:00` as a time.** A property check over every mode x
  value 0..12 x fmt.
- Steady sequences (T144's, moved): 25 -> 15 at t = 0 gives 20 at 1.0 and 15 at 2.0, nothing at
  0.5; a label change snaps; nil snaps; a 60 s gap snaps; **entering FULL snaps**.
- `QuietFull`: every boundary (just under and at QUIET; inside the 5SR plus QUIET; base x QUIET just
  under 2), and nil inputs -> false.
- `Build` with `out` passed allocates nothing (`collectgarbage("count")` steady over 1000 calls).

### 4.2 `tools/clocke2e.lua` (U4): the author's path, every control

Load the whole flavour TOC with the stub's geometry. Open Settings -> Clock through the dashboard
(the real pane, `CS.Build`) and run the live clock host (the real `UI/Clock_Forever.lua` /
`UI/Widget.lua`).

- **E1, every control visibly changes the live clock** (P1):
  - From each of three base states (the defaults; the author's migrated store from the fixture of
    4.5; every text on with the line off), for every entry of `CS.CONTROLS` that is visible in that
    state, for every sample value that differs from the current one:
    - take `s0 = ClockBar:Drawn()` of the **live** clock, fire the control's own widget handler (a
      click, a dropdown pick, a checkbox, a number box's Enter), run one 0.5 s tick, take `s1`;
    - assert `s1 ~= s0` on at least one field the control names (`affects`, e.g.
      `texts.mana.size` -> `text.mana.size`).
  - **An empty "inert" list is the pass condition.** There is no exception list.
  - The same for the preview's own `Drawn()`.
- **E2, every hidden control is really hidden**: for each control `visible(look)` says no, its
  widget `IsShown()` is false.
- **E3, a write is one event**: each control fires exactly one `CLOCK_LOOK`, and the store then
  validates (`Normalize` changes nothing).
- **E4, presets**: each preset, from each base state:
  - the time is on and the line is on (P2);
  - the line is drawn mid-rule;
  - Undo restores `s0` exactly (deep compare of the store and of `Drawn()`).
- **E5, a fight end to end, driven by the model** (bug 2): the author's store and the defaults.
  - Login, then a pull. A priced spend at 30 % of max, three casts, then regen outrunning the spend
    until the model is at max, then 20 s more in combat, then leave combat, then 20 s out.
  - Every 0.5 s tick, the live time text is recorded.
  - Assert:
    - it never reads `0s` / `0:00`;
    - it reads `FULL` within one tick of the model reaching max, and stays `FULL` while at max;
    - a refill time always starts with `FULL `;
    - an OOM countdown changes at most once per second, by at most one step.
- **E6, the line** (bug 3), mid-rule:
  - between two ticks, eight 0.03 s frames each move the line right;
  - it keeps moving across each of: a `CLOCK_LOOK` (every Bar control, applied mid-rule), a
    `UNIT_POWER_FREQUENT` burst (20 events), the preview starting and ending, a
    `PLAYER_REGEN_DISABLED` / `ENABLED`, and the host hidden then shown;
  - it is hidden within one frame of the rule's end;
  - the driver's script is the same function object throughout.
- **E7, the quiet pool** (Forever):
  - With the model at 80 % and `UNIT_POWER_FREQUENT` firing every 0.2 s, no anchor.
  - The events stop for QUIET outside the 5SR: the model is anchored at max and the time reads
    `FULL`.
  - The events stop inside the 5SR: no anchor.
  - `base * QUIET < 2`: no anchor.

The stub must behave like the client for E6. **`S.Tick` runs `OnUpdate` only on frames that are
visible**: shown, and every parent shown. This is an opt-in, `S.VisibleOnUpdate(true)`, so that
older suites are untouched. The clock suites turn it on.

### 4.3 `tools/clockbarcheck.lua` (U3): the renderer alone

- Geometry:
  - the frame is `width x height` at any text size, place and offset (T144's check, kept);
  - each text's anchor for every place x align, with x / y;
  - the hit-rect insets cover the outside texts.
- Hot paths, by counting the stub's region calls:
  - `Paint` with unchanged words makes 0 `SetText` calls;
  - `Paint` and `PaintPower` make 0 `SetPoint` / `SetFont` / `SetSize` / `GetStringWidth` calls;
  - an idle driver frame makes 0 region calls;
  - `PaintPower()` without `withMax` makes 0 `SetMinMaxValues` calls.
- **Secrets** (Forever profile): the bar and the power texts receive the stub's secret stand-in and
  nothing reads it back. This is the `DrawUnitPower` pattern, kept.
- Each failure mode of 2.6 gives its fallback and its note.
- TBC: the same, with plain reads.

### 4.4 `tools/clockstorecheck.lua` (U2)

- `Normalize` repairs each invalid field and names it; it is idempotent.
- Every `Set` path is validated; a refused value writes nothing.
- One `CLOCK_LOOK` per write.
- Presets replace, and Undo restores.
- **P2: no preset sets `line = false` or `texts.time.on = false`**, checked over `PRESETS`.

### 4.5 Migration goldens (U2)

- `tools/data/clock-v2-author.lua` is the author's 2026-11-08 store, copied from the saved variables
  and limited to `clockLook`. It migrates to the exact v3 table of section 1.5, and its dump notes
  match.
- Also covered: a v1 store (0.16.6 `bar.source = "model"`), a `line` layout with overrides, a
  `compact` layout, an empty store, a v3 store (unchanged), and a garbage store (defaults, named).
- `tools/data/import-forever-sv.lua` is rebuilt (`tools/importfixture.lua`), as CLAUDE.md requires
  when what is stored changes.

### 4.6 What stays where it is

- `tools/clockcheck.lua`: the model and the face. T144's Steady checks move to 4.1.
- `tools/clockfacecheck.lua`: `LineString` for the feeds. The slot goldens go.
- `tools/stylecheck.lua`: the clock golden is re-based on the new regions.
- `tools/restylecheck.lua` / `themecheck.lua`: the new files obey them. The clock's colours are the
  user's hex, never a style token.

## 5. Units

Order: **U1 and U2 in parallel, then U3, then U4, then U5.** Each unit:
- is one Opus implementer;
- runs only its suites while iterating;
- runs `make check` once at the end, in the background;
- commits on `worktree-forever-talents` as `T145<x>: ...`;
- does not install.

### U1 -- the words and the quiet pool (T145a) -- size M

- **Files:**
  - `Engine/ClockWords.lua` (new);
  - `Engine/ManaModel.lua` (`Steady` moved; an alias kept);
  - `Engine/ManaPool_Forever.lua` (the event, `lastPowerEvent`, `QuietFull`, the anchor, the
    flag, the dump line);
  - every main TOC (`ClockWords` after `Engine/ClockFace.lua`);
  - `tools/clockwordscheck.lua` (new), `tools/data/expected-counts.json`.
- **Scope frozen:** no UI file. `UI/Clock_Forever.lua` may move its `UNIT_POWER_FREQUENT` handler
  to `ST:OnUnit` beside the pool's (both kept) and nothing else.
- **Acceptance:**
  - 4.1 green on both flavours;
  - the bug-2 face (`full`, ttf 0, in a fight) gives `FULL`;
  - E7's rule cases pass as pure checks;
  - `make check` green.

### U2 -- the store, the migration, the presets (T145b) -- size M

- **Files:**
  - `UI/ClockStore.lua` (new, every main TOC before `UI/ClockView.lua`'s slot; in U2 nothing reads
    it yet);
  - `tools/clockstorecheck.lua`, `tools/data/clock-v2-author.lua`.
- **Scope frozen:**
  - `db.clockLook` is not yet rewritten at login. `MigrateStored` exists but is called only by
    tests until U3 wires it.
  - `CV.Migrate`'s v1 rules are copied in, not shared.
- **Acceptance:**
  - 4.4 and 4.5 green;
  - the author's golden matches section 1.5 field for field;
  - the dump notes name every dropped key.

### U3 -- the renderer and the hosts (T145c) -- size L (Fable or Opus high: it is the timing / state unit)

- **Files:**
  - `UI/ClockBar.lua` (new);
  - `UI/Clock_Forever.lua`, `UI/Widget.lua` (rewired);
  - `Client/API.lua` (`DrawUnitPowerMax`, the value-only `DrawUnitPower`), `Client/API_TBC.lua`
    (`DrawPowerText`);
  - `tools/wowstub.lua` (`S.VisibleOnUpdate`, call counters if missing);
  - TOCs: `UI/ClockView.lua` out, `UI/ClockBar.lua` in;
  - `UI/ClockView.lua` deleted;
  - the migration wired at `MD_READY` (`ClockStore.MigrateStored`);
  - `tools/clockbarcheck.lua` (new);
  - `tools/clockui.lua` cut down to the host's visibility, drag and hover checks, or folded into
    `clockbarcheck`;
  - `tools/stylecheck.lua` golden re-based.
- **The Settings pane** keeps working on a minimal shim until U4: `CS.Refresh` reads
  `ClockStore.Look()`, and its preview is a `ClockBar`. Its old controls may write keys that no
  longer exist. U4 replaces the pane, so in U3 the old `clocksettings` suite is **expected red**
  only where it checks removed keys. The implementer lists the failing ids in the report and marks
  them skipped with "U4".
- **Acceptance:**
  - 4.3 green on both flavours;
  - E5 and E6 pass when driven from the host without the pane (the shared helpers live in
    `tools/lib/clockdrive.lua`, which U4 reuses);
  - `apicheck` 0 findings (no client call outside `Client/`);
  - no `UI/ClockView.lua` reference left (`grep`).

### U4 -- the pane and the end-to-end suite (T145d) -- size L

- **Files:**
  - `UI/ClockSettings.lua` (rewritten from the mockup);
  - `UI/Dashboard_Forever.lua` / `UI/Dashboard.lua` (`CLOCK_SWITCHES` minus Rest);
  - `tools/clocke2e.lua` (new), `tools/clocksettings.lua` (retired or cut to the integrations
    section, which stays);
  - `Engine/ClockFace.lua` (the slot system removed);
  - `UI/Feeds.lua` and `Integrations/Surface_LDB.lua` (the `ClockLook` provider gone: the default
    `LineString`).
- **Scope frozen:** the integrations block (`CS.BuildIntegrations`, the LDB / ElvUI / EllesmereUI
  switches) moves unchanged.
- **Acceptance:**
  - 4.2 E1-E7 green on both flavours (E7 Forever);
  - the inert list is empty with no exception list;
  - the pane matches the mockup's controls one to one.

### U5 -- the docs and the gate (T145e) -- size S

- **Files:**
  - `CLAUDE.md` (the clock rows: ClockWords, ClockStore, ClockBar; the ClockView / ClockSettings
    rows replaced);
  - `docs/TOOLS.md` (suites and counts), `tools/data/expected-counts.json`;
  - `docs/DECISIONS.md` (D1-D3 and the quiet-pool rule with its VERIFY; Q-clock open items closed or
    restated);
  - `docs/TESTING.md` §66 (below);
  - `CHANGELOG.md` (a `## 0.17.4` or the next version's section: the look reset, the line on, Line
    and Compact gone);
  - `docs/HISTORY.md`;
  - the import fixture.
- **Acceptance:**
  - `make check` green;
  - `textcheck` clean;
  - every removed CV / CF name is gone from the docs' file table.

`docs/TESTING.md` §66 (Forever, about 5 minutes; then TBC, 2 minutes):
1. `/st dump` shows the `clock:` migration line. Then the quiet pool: drink to full, out of combat.
   The time reads `FULL` within about 3 s of the EllesmereUI bar reaching full, and the dump's
   `pool:` line counts a quiet-full anchor. (Not within 5 s: report the dump's power-event count.)
2. A pull. The moving line crosses the bar after each cast, and keeps moving while you change Width,
   the texture or a text's size during a fight preview.
3. Regen outruns the casting. The time reads `FULL 0:xx`, then `FULL`, and never `0s`.
4. Settings -> Clock: every control you touch changes the clock on screen. An off text shows no
   fields. Each preset keeps the time and the line, and Undo puts your look back.
5. TBC: the same bar, the time `FULL` at full in a fight, the line moving.

## 6. Open risks

- **R1, the quiet-pool rule rests on one client fact not yet seen in our own probe:**
  `UNIT_POWER_FREQUENT` is silent at full and frequent while regenerating. EllesmereUI's smooth bar
  depends on the second half. QUIET is VERIFY, and the §66 step 1 count settles it.
- **R2: a texture on the line's parent StatusBar.** The line textures stay on `bar` so its shape
  masks clip them. If the 12.x client hides the children of a bar holding a secret value, the line
  has to move to its own frame with its own mask pair. That is a contained change inside `Apply`.
- **R3: dropping Line and Compact affects published beta users.** It is named in the changelog and
  the dump. The feeds cover a text-only clock.
- **R4: the dense store freezes each user's look against future default changes.** That is wanted
  for a look the user tuned, and a fresh install gets the defaults.
- **R5: U3 is the largest unit.** If it runs long, split it as U3a (renderer + Forever host) and
  U3b (the TBC host + API_TBC). The interface between them is `draw`.
