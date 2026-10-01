# R-clock: a better-looking, customisable OOM clock on both lines

Research note, 2026-10-01, written against the worktree at `c911339` (SpellTuner 0.16.5). Read-only:
nothing in the repository was changed. The author's request: "I want the oom timer look better
(ideally customizable)". Every claim below cites a file and a line in this tree. Anything not
verified on a client is marked **UNVERIFIED** and comes with the probe question that would settle it.

---

## 0. The short answer

1. **Separate *what the clock says* from *how it is drawn*.** Today each line bakes words, colours
   and layout into a single string: TBC in `MD:GetDisplayString` (`Engine/TTO.lua:345-411`), and
   Forever in `ManaModel.Text` (`Engine/ManaModel.lua:280-295`). We would add one pure **face
   record** per line (mode, label, value, how the value is known, tone, arrow, secondary segment,
   5SR, mp5, pct, modelled) and one shared **renderer** (`UI/ClockFace.lua`, on both TOCs) that
   draws a face in a chosen **layout**. The two existing strings become the renderer's "line"
   output and stay byte-identical, so the `ttocheck` and `clockcheck` goldens keep holding.
2. **Five layouts:**
   - **Line**, which is today's clock and the default;
   - **Compact**, one big number;
   - **Bar**, a bar with a label and a time on it;
   - **Ring**, a segmented arc built from plain textures, with no media and no library;
   - **Two-line**, opt-in only, because `docs/DECISIONS.md:117` rejected a second line.
3. **One customisation store on both lines.** It would be `db.clockLook`, holding:
   - a layout;
   - a style that follows the UI style (the parallel "2-3 UI styles" topic);
   - a sparse `over` table of the user's overrides.

   Font, colours by tone and state, background and border, bar texture, height and source, the
   segments, show rules, alpha, scale, lock and click-through would all live there.
4. **Settings → Clock**, a new view on both lines, with a **live preview**. A row of state chips
   cycles the preview through oom, the <20 s band, the bound, hold, warmup, FULL and out of
   combat. The panes would be Text / Colours / Frame / Bar / Show / When.
5. **What must stay true:**
   - one visibility owner per line;
   - on Forever the real pool is only ever *drawn* (`MD.API.DrawUnitPower`), never read;
   - ASCII only, no bare `|`, and the two-space separator;
   - the `~`, the `>` bound and the `--` are meaning, not decoration: no layout and no setting can
     remove them;
   - no "decimals" option on the OOM time, because the step ladder is a decision
     (`docs/DECISIONS.md:110`).
6. **Fix six Forever gaps first.** Each is cheap, and each is visible without any customisation
   (section 2).

---

## 1. What exists today

### 1.1 TBC: the face (`Engine/TTO.lua`)

| What | Where |
|---|---|
| The raw state: mode `oom/hold/full/warmup/ooc/fullnow/nodata`, `tto/ttf/bound/rest`, `rel/confident`, `stable`, `cd` | `Compute`, `Engine/TTO.lua:52-132` |
| The display latch: the mode latch (bad news at once, good news after 2 ticks) | `:159-177` |
| The display latch: the precision ladder `{1,5,10,15,30,60}` from sigma | `:183-205` |
| The display latch: the value latch with the 60 s / 20 s severity crossings | `:214-241` |
| The display latch: the confidence gate's own latch | `:257-271` |
| The arrow from the **shown** value over about 10 s, `=` / `v` / `^` | `:311-321` |
| Colours, hard-coded as hex: GREY 999999, WHITE, WARN ffaa33, CRIT ff4444, GOOD 33ff66, MANA 4fa9f0 | `:330-335` |
| Times as `%d:%02d` or `%ds`, `>10m` past 600 s | `FmtTime`, `:337-343` |
| One string per mode: `FULL`, `FULL --`, `FULL 2:10`, `OOM ...`, `OOM >4:00 =`, `OOM --`, `OOM 15s vv` (critical red under 20 s), `OOM ~1:20 v` | `:352-379` |
| At most one secondary segment, in combat only: `inn 2:10` (mana cooldown) or `rest 2:10` (shown when it differs from the primary by 25 % or more), each behind `db.showCooldown` / `db.showRest` | `:393-409` |
| `valueHex` replaces the number's colour for the ElvUI datatext, except in the critical band | `:327-328` |

### 1.2 TBC: the widget (`UI/Widget.lua`), after T82 / C4

- **Frame and panel.** A 180 x 30 `BackdropTemplate` frame on the kit's panel (`UI/Widget.lua:44-72`).
- **Text.** `UI.FONT` (13 pt), **centred** at `TOP 0,-4` (`:53-55`).
- **The 160 x 4 five-second-rule bar** (`:27-29`, `:58-70`). It is amber while it fills and green
  once spirit regen runs (`:153-159`). It is repainted at 10 Hz, and the text at 4 Hz (`:120-141`).
- **Unlock and first-run preview.** `SpellTuner - drag me` in the accent over a full accent bar
  (`:128-135`).
- **Flash.** One pulse per fight, the first time the time to OOM drops under 30 s (`:143-150`).
  `MD:Alert` also pulses the widget (`Core.lua:266`, `UI/Widget.lua:174-176`).
- **The visibility owner** is `MD:UpdateVisibility` (`:189-217`). It hides the widget for a
  non-mana character (`:199`) and otherwise asks `MD.Visibility.Want` (`:210`).
- **Settings** (`Core_TBC.lua:13-28`): `pos` (a 4-tuple), `locked` (true), `showRest`,
  `widgetTooltip` (off means no mouse input at all, `UI/Widget.lua:192-198`), `showCooldown`,
  `oomConfidence`.
- **UI.** The "OOM Widget" pane, 205 x 164 (`UI/Options_General.lua:20-62`): Lock, rest, tooltip,
  cooldown, Reset position.
- **Slash commands.** `/st lock`, `unlock`, `reset`, `rest`, `tooltip` (`Core_TBC.lua:289-328`).

### 1.3 Forever: the clock (`UI/Clock_Forever.lua`) over the pool (`Engine/ManaPool_Forever.lua`, `Engine/ManaModel.lua`)

- **The model is pure** (`Engine/ManaModel.lua:16-229`). It takes the plain max, subtracts each
  priced cast at success, and adds regen under the five-second rule at the rate last read out of
  combat. `Project` returns `mode`, `tto`/`ttf`/`rest`, `spend`, `regen`, `mana` and `max`, and
  every one of those is plain (`:180-229`).
- **The text** is `ManaModel.Text` (`:280-295`): `~FULL`, `~FULL 1:20`, `~OOM ...  rest 0:20`,
  `~OOM --`, `~OOM 1:20  rest 2:10`. Times are rounded to 5 s (`:236-247`). There is **no hold
  bound, no arrow and no colour**: the comment at `:275-277` says the bound "needs sigma ... not
  adopted".
- **The frame** is the same 180 x 30 panel with a 160 x 4 bar (`UI/Clock_Forever.lua:203-256`).
  The bar is **the real pool, drawn by the game** (`:273`, `MD.API.DrawUnitPower`), and its
  readback is secret (`docs/probe/1.60.1_70124.md:55`, `bar UnitPower(player, 0): set ok, read
  secret`). The adapter hands the secret to the bar unread (`Client/API.lua:329-344`).
- **Text colour.** `Paint` sets the whole line to `UI.RGB("text")`, white (`UI/Clock_Forever.lua:270-271`).
- **The visibility owner** is the local `UpdateVisibility` (`:62-74`): `db.clock.shown`, then the
  same `MD.Visibility.Want`.
- **Settings.** `db.clock = { shown = true, locked = false, point = nil }` (`Core_Forever.lua:33`).
  The point is a 5-tuple (`UI/Clock_Forever.lua:217-221`).
- **UI.** The MANA CLOCK section (`UI/Dashboard_Forever.lua:285-331`): Show, Lock, Reset position,
  Show now. **Command:** `/st clock [lock]` (`Core_Forever.lua:279-289`).

### 1.4 Shared, and the integration

- **`UI/Visibility.lua:19-33`** is the pure 90/95 hysteresis. An unlocked or in-combat clock is
  always shown, and a non-number `pct` reads as hidden.
- **The ElvUI datatext** (`Integrations/ElvUIDatatext.lua:58-62`) renders
  `MD:GetDisplayString(hex)`. The second datatext is `Regen: 123 (5SR)` (`:70-80`). It is TBC
  only: `Integrations\` is not on `SpellTuner_Mainline.toc`.

---

## 2. Findings: what is wrong or uneven before any customisation

| # | Finding | Evidence | Fix |
|---|---|---|---|
| F1 | **The Forever clock is monochrome.** `~OOM 0:10` is white, so the critical band TBC paints red (`Engine/TTO.lua:369-370`) and the warn band (`:372`) do not exist on Forever. | `UI/Clock_Forever.lua:270-271`; `ManaModel.Text` returns no colour codes | The face record carries a **tone** and the renderer colours by tone on both lines. On Forever, ManaModel's 5 s rounding stands in for the latch. |
| F2 | **T82 centred the text, against a recorded decision.** `docs/DECISIONS.md:116`: "Widget text left-anchored ... Centred text slides when the digit count changes". With `OOM 59s` → `OOM 1:00` → `OOM >10m` the whole line shifts on every change of width. | `UI/Widget.lua:54`, `UI/Clock_Forever.lua:235` (`TOP`, 0, -4) | The renderer draws **label, value and secondary as separate font strings**, with fixed justification (section 5.1), so only the value's own digits move. |
| F3 | **The Forever clock does not check `usesMana`.** A warrior or rogue on Forever gets `~OOM ...` in every fight: `Want` returns true in combat before it looks at `pct` (`UI/Visibility.lua:29`), and the max is 0. | `UI/Clock_Forever.lua:62-74` has no `MD.player.usesMana` test; TBC has one at `UI/Widget.lua:199`. `usesMana` is shared (`Core.lua:307-319`). | One line in the Forever owner. Better, the gate moves into the shared show rule (section 6.6). |
| F4 | **The Forever clock always takes the mouse.** No setting makes it click-through, unlike TBC's `widgetTooltip`. | `UI/Clock_Forever.lua:209` (`EnableMouse(true)`); TBC `UI/Widget.lua:192-198` | `look.clickThrough` on both lines. |
| F5 | **On Forever, alerts and the <30 s moment never pulse the clock.** | `MD:PulseWidget` exists only in `UI/Widget.lua:174`; `Core.lua:266` calls it if present. The once-per-fight flash is `UI/Widget.lua:143-150` only. | The renderer owns the pulse animation, and both widgets expose `PulseWidget`. |
| F6 | **The rest segment cannot be turned off on Forever, and its wording differs.** | `Engine/ManaModel.lua:257-263` has no setting; TBC gates it on `db.showRest` (`Engine/TTO.lua:400`) | `look.show.rest` on both lines. |
| F7 | **The bar means different things.** It is the 5SR on TBC and the real pool on Forever. M6 accepted this (`docs/DECISIONS.md:1154-1160`, mockup `refactor-ux.html:964`), but nothing on screen tells the two apart. | `UI/Widget.lua:8`, `UI/Clock_Forever.lua:273` | Make the bar **source** a setting. Draw the 5SR as an ElvUI-style **spark** over any bar (section 3.1), so both lines can show mana *and* the 5SR on one bar. |
| F8 | **Position and lock are stored differently on each line, with different defaults.** | TBC `db.pos` 4-tuple and `db.locked = true` (`Core_TBC.lua:13-14`); Forever `db.clock.point` 5-tuple and `locked = false` (`Core_Forever.lua:33`) | Leave the storage alone in phase 1. Unify in the phase-2 merge, with a one-time adoption like `ManaDemonDB` (`Core.lua:398-404`). |
| F9 | **The clock has no scale or alpha.** The window manager never touches the clock (`UI/Clock_Forever.lua:189-194`), so `db.ui.scale` does not reach it. | | `look.scale` and `look.alpha` belong to the clock itself. The existing `Snap()` already re-snaps the 1-px edge when `UI.px(1)` moves (`UI/Widget.lua:126`, `UI/Clock_Forever.lua:263`). |

F1 to F6 are Forever behaviour changes, or a TBC fix that restores a decision (F2). Each one is
small enough to be its own task (section 10, K2).

---

## 3. Survey: what good mana and timer displays do

### 3.1 ElvUI (vendored at `../ElvUI`, read-only)

- **Datatext options.** Each datatext gets `NoLabel`, a custom `Label` and `decimalLength`
  (`ElvUI/Game/Shared/Modules/DataTexts/ManaRegen.lua:29-48`). The combat timer has a
  `TimeFull` format switch (`.../CombatTime.lua:54`). The value takes the theme's `hex`, which
  SpellTuner already honours (`Engine/TTO.lua:327-328`).
- **The five-second-rule spark.** `oUF_EnergyManaRegen` puts a 2-px additive spark on the
  player's power bar (`ElvUI/Game/Shared/Modules/UnitFrames/Elements/ClassBars.lua:679-701`). The
  spark is **yellow and counts down 5 s** after a spend, then **white and sweeps the 2 s regen
  tick** (`ElvUI_Libraries/Game/Shared/oUF_Plugins/oUF_EnergyManaRegen.lua:73-85`). It is the
  nicest known way to show the 5SR without a second bar, and it is what fixes F7.
- **Takeaway.** Label on/off and a custom label, a value colour from the theme, a time format,
  and a 5SR spark on top of a mana bar.

### 3.2 Cell (the author's fork, `../Cell`)

- **Font settings as one tuple:** face, size, outline `None/Outline/Monochrome`, and shadow
  (`Cell/Indicators/Base.lua:44-75`, `I.SetFont`).
- **The bar indicator's colour model** (`Base.lua:1781-1793`, `1880-1881`): a normal colour, a
  colour below *N %* remaining, a colour below *N seconds*, a border colour and a background
  colour. That is exactly the shape the clock's tones need: normal, warn at 60 s, crit at 20 s,
  plus border and background. Orientation and reverse fill: `Base.lua:1901-1908`.
- **Colour picker.** Cell does **not** use Blizzard's `ColorPickerFrame`; it ships its own
  (`Cell/Widgets/ColorPicker.lua`, about 460 lines). It is a reference for a later kit picker,
  not code to copy wholesale.
- **Takeaway.** The font tuple, threshold colours that count in seconds, and separate border and
  background colours. The author already sets these in Cell, so the words should match Cell's.

### 3.3 WeakAuras-style displays (general knowledge; WeakAuras is not in this tree)

- **Progress bar.** Icon, left text, right text, a spark, a texture, background and border, and
  a "time remaining" fill.
- **Progress texture.** A radial ring, built from two rotated half textures and a shipped ring
  texture.
- **Text-only.** A big number with an outline and no backdrop.
- **Load conditions.** In combat, in a group, or by power percentage, with alpha in and out of
  combat.
- **Takeaway.** The layouts in section 4 are WeakAuras' three shapes (text, bar, ring). The show
  rules and alpha in/out of combat are its load conditions.

### 3.4 EllesmereUI (not in this tree; known through `docs/tasks/T0c-probe-secrets.md:79-82`)

EllesmereUI reads mana in a secret-safe way through
`UnitPowerPercent("player", Enum.PowerType.Mana, false, curve)`. The Forever API baseline has
`UnitPowerPercent` and `C_CurveUtil.CreateColorCurve` (`tools/data/forever_api.json`).

- **UNVERIFIED:** whether a colour curve lets a bar be **coloured by the real level** without
  SpellTuner ever reading the level.
- **UNVERIFIED:** whether a FontString **displays** a secret it is handed. Probe 70124 shows a
  StatusBar *takes* a secret but reads it back secret; it does not answer whether a font string
  shows one.

Two probe questions, Q-clock-1 and Q-clock-2, are in section 8.3. Until they are answered, the
Forever clock can show the real level only as a drawn bar fill.

---

## 4. Layouts

All five layouts draw the **same face record** (section 5.1). The ASCII sketches show default
sizes. `[====]` is a bar, and `|` in a sketch is a frame edge, never rendered text.

### L1 Line, the default: today's clock, made steadier

```
+--------------------------------+
|   OOM  1:20 v   rest 2:10      |   TBC
|  [=========......] 5SR / pool  |   (Forever: ~OOM  1:20   rest 2:10)
+--------------------------------+   180 x 30
```

- **What it shows.** The same words as `GetDisplayString` / `ManaModel.Text`. The datatext keeps
  calling the string API, unchanged.
- **The one visual change, F2.** Three font strings (label, value plus arrow, secondary) anchored
  from a fixed left edge, as `docs/DECISIONS.md:116` asked. Optionally the value uses the kit's
  number font (`UI.FONT_NUM`, ARIALN, `UI/Style.lua:223`), whose digits are close to tabular.
- **Default.** Byte-identical text and today's bar meaning on each line (5SR on TBC, pool on
  Forever).

### L2 Compact: one number

```
+-----------+
| OOM       |   label 9 pt, muted, top-left
|   1:20 v  |   value 20-24 pt, tone-coloured
+-----------+   72 x 36; no rest, no bar by default
```

- **What it is for.** A clock parked beside the player frame or the Cell party frames, read at a
  glance. The rest segment moves to the tooltip, which already carries `Full again in 3:40 if
  you stop` (`UI/Tip_TBC.lua:512` onward, `UI/Clock_Forever.lua:107-129`).
- **Forever.** The label is `~OOM`. The `~` must stay, either glued to the label or as a small
  prefix.
- **Optional.** A 2-px strip under the number for the 5SR or the pool, the same sources as L3.
- **Datatext.** "Compact" is also a datatext mode: the ElvUI and EllesmereUI datatexts can render
  `1:20 v` with no label, which is ElvUI's `NoLabel`.

### L3 Bar: a bar with the time on it

```
+------------------------------------------+
| OOM [#########################.....] 1:20 v|   200 x 18, text inside the bar
+------------------------------------------+
     ^ spark: 5SR (yellow, counting 5 s), then the 2 s tick (white)
           ^ thin marker: where "rest" would put you (time-fill source only)
```

The bar source is a setting:

| Source | TBC | Forever |
|---|---|---|
| `pool`: real mana | `UnitPower` / `UnitPowerMax`, plain | `MD.API.DrawUnitPower(bar, "player", 0)`, **drawn, never read** |
| `model`: modelled mana | n/a (TBC has the real one) | `Pool:Sample()` mana / max, plain, drawn with a `~` hatch or tint |
| `time`: time to OOM | fill = `tto / horizon`, horizon 180 s by default and set by the user, draining like a WeakAuras countdown | the same, from `Project().tto` |
| `fsr`: the five-second rule | today's TBC bar (`UI/Widget.lua:153-159`) | `model.lastSpend + 5 - now`, plain (priced casts only; an unpriced cast does not restart it, `Engine/ManaModel.lua:106-114`) |

- **Spark.** `look.bar.spark = "fsr"` draws ElvUI's 5SR / tick spark (section 3.1) on top of
  whichever source is chosen. This is how "the bar means the same on both lines" becomes
  possible (F7): pool plus spark on both. The default keeps each line's meaning.
- **Colour.** The bar takes the face's tone. On Forever's `pool` source the tone comes from the
  *modelled* state, because the drawn pool cannot be read. That is honest: the colour says what
  the model thinks, and the fill shows what the game has.
- **Text.** Inside the bar, left / right / both, or above or below it.

### L4 Ring: a segmented arc, no library and no media

```
      . - - .
   .'  OOM   '.        56 x 56 (up to 96)
  :   1:20 v   :       24 segments, lit = fraction
   '.        .'        gap at the bottom (a 300-degree arc)
      ' - - '
```

- **How it is built.** N (24 or 36) small textures of `UI.whiteTexture`, each placed on a circle
  and turned with `Texture:SetRotation(angle)`. A segment is lit or dimmed by fraction. This
  needs no shipped ring texture, which matters because `release.sh` builds packages from the TOCs'
  file lists and there is no media path today. It is about 40 lines and pure geometry.
- **The fraction source** is the same as L3, but **`pool` is not available on Forever**: no known
  widget draws a secret radially. The ring offers `model` (marked `~`), `time` or `fsr` there.
  TBC can use `pool`.
- **Inner ring (optional).** A second, smaller ring of 12 segments for the 5SR (5 s, then the
  2 s tick).
- **Alternative.** A `Cooldown` frame's swipe (`SetCooldown(now - (H - t), H)`) draws a smooth
  pie with no textures, but it is a pie, not a ring. Its secrecy does not matter here, because our
  inputs are plain. The probe already reads `ShouldCooldownsBeSecret = false`
  (`docs/tasks/T0c-probe-secrets.md:70`).
- **UNVERIFIED on both clients:** `SetRotation` on a texture inside a pixel-snapped frame. Rotated
  1-px edges blur, so segments should be at least 3 px thick. The stub needs a no-op
  `SetRotation` (`tools/wowstub.lua`'s frame methods).

### L5 Two lines: opt-in, needs the author's ruling

```
+------------------------------+
|  OOM 1:20 v                  |   13-16 pt
|  rest 2:10   5SR 3.1   92mp5 |   11 pt, muted
+------------------------------+
```

- **This reopens a decision.** `docs/DECISIONS.md:117`: "Rejected: ... second line ... A readout
  the player must be taught fails the one-second glance test." So it ships **off**, and is listed
  last.
- **What its second line is for.** It answers "why", which the hover already answers. Its one
  advantage is that it needs no mouse in combat. If the author wants it, record a DECISIONS
  paragraph ("Two-line clock, opt-in") and keep L1 the default.

### Presets ("looks") rather than more layouts

These four are presets, not new layouts. They are where this topic meets the "2-3 UI styles"
topic:

| Preset | Layout | Font | Panel | Bar |
|---|---|---|---|---|
| **Flat** (today, `UI/Theme_Flat.lua`) | L1 | kit 13 pt, shadow | `bg` + 1-px black | 4-px flat |
| **Classic** | L1 or L3 | FRIZQT, outline | tooltip-style border, gold title | `Interface\TargetingFrame\UI-StatusBar` |
| **Retail-like** | L3 | kit font | none | 12-px Blizzard bar, spark |
| **Text only** (WeakAuras look) | L2 | 20 pt, thick outline | none | none |

A preset fills defaults only. The user's own overrides sit on top (section 6.1).

---

## 5. Architecture

### 5.1 The face record (pure, produced per line)

```
face = {
  mode     = "oom"|"hold"|"full"|"warmup"|"ooc"|"fullnow"|"nodata",
  label    = "OOM"|"FULL",
  value    = <seconds> | nil,          -- what is SHOWN (latched on TBC)
  known    = "point"|"bound"|"pending"|"none",   -- ">" bound, "..." warmup, "--"
  unstable = bool,                     -- TBC "~": CV over CV_STABLE (TTO.lua:374)
  modelled = bool,                     -- Forever "~": always true
  tone     = "crit"|"warn"|"normal"|"good"|"muted",
  arrow    = "v"|"^"|"="|nil,          -- nil out of oom and out of combat (DECISIONS:113)
  second   = { kind = "rest"|"cd", label = "rest"|"inn", value = <s> } | nil,
  fsr      = <seconds left in the 5SR> | 0,
  tick     = <seconds into the 2 s regen tick> | nil,
  mp5      = <number> | nil, mp5Modelled = bool,
  pct      = <0..1> | nil, pctModelled = bool,   -- Forever: model only
  combat   = bool,
}
```

- **TBC producer.** `MD:GetClockFace()` in `Engine/TTO.lua`, built from `disp` and `state`
  exactly as `GetDisplayString` branches today (`:352-409`). It moves the tone rules out of the
  hex constants (`:330-335`): crit when the value is under 20 s, warn under 60 s, muted for grey.
  `GetDisplayString(valueHex)` becomes `ClockFace.LineString(face, valueHex)`. The `ttocheck`
  golden (`tools/ttocheck.lua:101`, `Shown()`) proves the result is the same bytes.
- **Forever producer.** `ManaModel.Face(state, now, model)` in `Engine/ManaModel.lua`, pure. It
  takes `fsr` from `lastSpend` and `mp5` from `state.regen * 5`, both marked modelled.
  `ManaModel.Text` becomes `LineString(Face(...))`, and the 12 or so `clockcheck` string cases
  (`tools/clockcheck.lua:118-144`) hold it.
- **Forever arrow (optional, a behaviour change).** ManaModel keeps no history of shown values,
  so Forever has no arrow. A small render-only latch, with a fixed 5 s step because there is no
  sigma, could compute TBC's `Arrow` (`Engine/TTO.lua:311-321`) the same way. Ship it off until
  the author asks.
- **What the record buys.** The datatexts on ElvUI and the planned EllesmereUI read the same
  record, so a "compact" datatext costs nothing.

### 5.2 The renderer: `UI/ClockFace.lua` (both TOCs, after `UI/Theme_Flat.lua`, before the widgets)

- `ClockFace.Build(frame, look)` creates or reuses regions for the layout. The regions are kept
  in a per-frame pool, so a layout switch does not leak frames.
- `ClockFace.Paint(frame, face, look, draw)` is paint only. `draw.pool(bar)` is a callback the
  **line** supplies:
  - TBC: `bar:SetMinMaxValues(0, max); bar:SetValue(UnitPower(...))`;
  - Forever: `MD.API.DrawUnitPower(bar, "player", 0)`.

  The renderer never names `UnitPower`. That keeps `apicheck.py` rule 10 and the adapter rule
  intact (no client call outside `Client/` on Forever).
- `ClockFace.LineString(face, valueHex)` is the one place the words and colour codes are
  assembled. It is ASCII only, uses two spaces and never a pipe.
- Pulse and flash animations live here, so both lines get `PulseWidget` (F5).

### 5.3 Widgets: phase 1 keeps two owners, phase 2 has one clock

- **Phase 1.** `UI/Widget.lua` and `UI/Clock_Forever.lua` keep their frame, drag, hover and
  **their own visibility owner**. They hand each tick's face to `ClockFace.Paint`.
- **Phase 2.** One `UI/Clock.lua` on both TOCs, with a per-line source installed as a value: the
  T59 / T65 policy pattern (`MD.PracticePolicy`, `MD.ReviewPolicy`), for example
  `MD:Provide("ClockSource", { Face = ..., DrawPool = ..., PlainPct = ... })`. This leaves a
  **single owner on both lines**. CLAUDE.md's "Widget visibility has a single owner" row is
  rewritten to name it, and the position and lock storage is adopted once (F8).

---

## 6. The customisation surface

### 6.1 Storage

- **The defaults problem.** `MD:RegisterDefaults` fills **every leaf** into `MD.db`, recursively
  (`Core.lua:328-337`, `379-386`). A default that "follows the UI style" therefore cannot be a
  registered leaf: once filled, it is indistinguishable from a user's choice.
- **Proposal.** Register only the following, in `UI/ClockFace.lua` on both TOCs:

  ```
  db.clockLook = { layout = "line", preset = nil, over = {} }
  ```

  Every key of `over` is a sparse user override. The look is resolved as layout defaults ←
  preset (or the active UI style) ← `over`. "Reset to style" wipes `over`.
- **Existing keys stay where they are** and are read through the resolved look: `db.showRest`,
  `db.showCooldown`, `db.widgetTooltip` and `db.oomConfidence` on TBC, and `db.clock.*` on
  Forever. Nobody's settings move in phase 1.

### 6.2 Text

| Setting | Values | Default | Notes |
|---|---|---|---|
| `font.face` | kit font, `Fonts\FRIZQT__.TTF`, `ARIALN.TTF`, `skurri.ttf`, `MORPHEUS.ttf` | kit (`UI.FONT`) | Built-in faces only (no libraries). LibSharedMedia, if another addon loaded it, could later be offered through an adapter binding. It is optional and off; `../LibSharedMedia-3.0` exists in the author's AddOns. |
| `font.size` | 8-32 | 13 (L1), 22 (L2) | |
| `font.outline` | none / outline / thick / monochrome | none | Cell's tuple (`Base.lua:47-54`) |
| `font.shadow` | on / off | on | Turning the background off defaults the outline to "outline" |
| `font.numbers` | same face / number face (ARIALN) | same | Steadier digits (F2) |
| `align` | left / centre / right | left | Fixed segments; `DECISIONS.md:116` |
| `time.format` | `1:20` / `80s` / `1m20` | `1:20` (with `%ds` under a minute, as `FmtTime`) | **Format only.** The step ladder still decides the precision (`DECISIONS.md:110`). No decimals on OOM, FULL or rest. |
| `labels` | `OOM`/`FULL` / `out`/`full` / none | `OOM`/`FULL` | `none` keeps the tone colour as the only sign, so it is off by default and the hover says so. On Forever the `~` stays even with no label. |

### 6.3 Colours: by tone, with a per-state override

- **Tones:** `crit` (ff4444), `warn` (ffaa33), `normal` (white), `good` (33ff66), `muted`
  (999999), `mana` (4fa9f0), `accent` (class). Defaults are today's constants
  (`Engine/TTO.lua:330-335`). Under the flat theme `good`, `muted` and `mana` could read
  `UI.TEXT` tokens instead (`UI/Theme_Flat.lua`: `good` 5CCB6E, `muted` 7A7A7A, `mana` 4D99FF),
  but on TBC that only happens with the author's say: it changes the TBC look.
- **Per-state overrides:** `colors.state.full`, `.warmup`, `.hold`, `.ooc`.
- **Thresholds.** `warnAt` = 60 s and `critAt` = 20 s. **They must move together with the value
  latch's instant crossings** (`Engine/TTO.lua:223`, `cur >= 60 and q < 60 or cur >= 20 and q <
  20`). The crossing exists so that the colour change is never delayed, so a user-moved threshold
  must move the crossing too. Defaults are identical, so behaviour is unchanged unless the user
  changes them.
- **Bar colours.** `bar.color` = "by tone" / "class" / a fixed colour. `bar.background` and
  `bar.border` are Cell's 4th and 5th colours.
- **Picker.**
  - **Phase 1:** a swatch row. A new kit widget, `UI.CreateSwatches`, offers the tones, the theme
    tokens, the class colour and 8 fixed colours. It makes no client call.
  - **Phase 2:** "Custom..." opens `ColorPickerFrame` through a new adapter binding,
    `MD.API.PickColor(r, g, b, a, onChange)`. `ColorPickerFrame` is in the Forever baseline
    frames list (`tools/data/forever_api.json`). The method (`SetupColorPickerAndShow`) on the
    TBC Anniversary client is **UNVERIFIED** (probe question Q-clock-3).

### 6.4 Frame

`background` on/off, colour and alpha (default `PALETTE.bg`); `border` on/off and colour (1 px,
snapped); `width` / `height` (layout minimums); `scale` 50-200 %, the clock's own (F9); `alpha` in
combat (1.0) and out of combat (1.0); `strata` LOW / MEDIUM (MEDIUM, `UI/Widget.lua:47`).

### 6.5 Bar

| Setting | Values |
|---|---|
| `bar.source` | `pool` / `model` (Forever only) / `time` / `fsr` / `none`. The default is each line's current meaning. |
| `bar.spark` | `none` / `fsr` (ElvUI's yellow 5 s then white 2 s tick) |
| `bar.texture` | flat (`UI.whiteTexture`) / Blizzard (`Interface\TargetingFrame\UI-StatusBar`) / raid (`Interface\RaidFrame\Raid-Bar-Hp-Fill`). **UNVERIFIED on Forever:** a missing path draws solid green; the probe can `SetTexture` each and read `GetTexture`. |
| `bar.height` | 2-24 (4) |
| `bar.position` | below / above / behind the text (L3) |
| `bar.horizon` | for the `time` source: 60-600 s (180) |
| `bar.reverse` | fill direction (Cell's `SetReverseFill`, `Base.lua:1907`) |

### 6.6 What to show, and when

**Segments**

- **OOM / FULL time:** always shown.
- **`rest`:** both lines (today it is TBC-only through `db.showRest`; fixes F6).
- **`cd`:** the `inn 2:10` segment, TBC only, because ManaCooldowns is not on Forever.
- **`arrow`:** TBC, and Forever once 5.1's latch exists.
- **`mp5`:** TBC `RM:Current() * 5`; Forever `~` from `state.regen`. In combat GetManaRegen is
  secret, so Forever falls back to the model's rate.
- **`pct`:** TBC real; Forever **modelled only, `~78%`**.
- **`fsr`:** `5SR 3.1`. This is the **only** place one decimal is allowed, because it is a timer
  read exactly.

L1 keeps "at most one secondary segment" (`Engine/TTO.lua:381-392`). Extra segments are L5's or
the tooltip's.

**Flash** when the time to OOM first drops under 30 s, once per fight (on / off), and on alerts.

**Show rules**, implemented by making `Visibility.Want` take a `rule`:

```
Visibility.Want(pct, shown, inCombat, unlocked, rule)
rule = { combat = "always"|"never",
         ooc = "low"|"always"|"never", showBelow = 0.90, hideAbove = 0.95,
         manaUsersOnly = true }
```

- `Want` stays pure, and the default rule is exactly today's (`UI/Visibility.lua:27-33`).
- `manaUsersOnly` moves TBC's gate (`UI/Widget.lua:199`) into the shared rule and fixes F3.
- On Forever, `pct` is the **modelled** fraction, as it is today (`UI/Clock_Forever.lua:71`).

**Interaction:**

- `locked`;
- `clickThrough`: TBC's `widgetTooltip == false`, extended to Forever (F4);
- `tooltip` on/off;
- left-click opens the window. Forever only does this out of combat (`docs/DECISIONS.md:1063-1065`).
  TBC opens it in combat too (`UI/Widget.lua:97-101`); a "same on both lines" design would adopt
  Forever's rule on TBC only by decision.

---

## 7. The settings UI: Settings → Clock

### 7.1 Where it goes

A new view, "Clock", in the Settings group on both lines:

- TBC: `UI/Dashboard.lua:245-246` (`general`, `about`), giving `general`, `clock`, `about`;
- Forever: `UI/Dashboard_Forever.lua:45-49` (`general`, `modules`, `about`), giving `general`,
  `clock`, `modules`, `about`.

The existing panes keep the everyday switches: TBC's "OOM Widget" (`UI/Options_General.lua:20-62`)
and Forever's MANA CLOCK (`UI/Dashboard_Forever.lua:285-331`), that is Show, Lock, Reset
position, Show now. Each gains one `Customise...` button → `MD:SelectView("settings", "clock")`.
Same words on both lines.

### 7.2 Mockup

```
+-- Settings > Clock -------------------------------------------------------------+
| PREVIEW                                                      ground: [dark][light]|
|   +------------------------------------------------------------------------+     |
|   |                     OOM  1:20 v   rest 2:10                            |     |
|   |                    [==============........]                            |     |
|   +------------------------------------------------------------------------+     |
|   state: (Live) [OOM] [OOM <20s] [bound] [hold] [warm-up] [FULL] [rest] [ooc]     |
|                                                                                  |
| LAYOUT   [ Line ] [ Compact ] [ Bar ] [ Ring ] [ Two lines* ]   style: [Flat v]   |
|          *off: decision DECISIONS:117                         [Reset to style]   |
|                                                                                  |
| +-[Text]-[Colours]-[Frame]-[Bar]-[Show]-[When]---------------------------------+ |
| | Font      [Kit font        v]   Size [--o------] 13   Outline [None v]         | |
| | Shadow    [x]                   Numbers [Number face v]   Align [Left v]       | |
| | Time      [1:20 v]              Labels [OOM / FULL v]                          | |
| +------------------------------------------------------------------------------+ |
|                                    [Show on screen 60 s]   [Lock]  [Reset place] |
+----------------------------------------------------------------------------------+
```

### 7.3 How it works

- **The preview** is a **separate frame** built by `ClockFace.Build` inside the pane. It is not
  the widget, so it never touches the widget's single visibility owner.
  - **Live** paints the real face each tick: TBC `MD:GetClockFace()`, Forever
    `ManaModel.Face(Pool:Project(now))`. On Forever the preview's `pool` bar is drawn through the
    same `DrawUnitPower`.
  - **The chips** paint **scripted faces** from a fixture table (`ClockFace.SAMPLES`). The same
    table feeds the new suite, so what the author sees in Settings is exactly what is tested.
- **The level-3 box** is `UI.CreateNavBox` (`UI/Style.lua:1209`), the existing "deeper levels in
  a box" rule (SPEC-v0.11).
- **Kit widgets.** All controls already exist: `CreateDropdown` (`:2104`), `CreateSlider`
  (`:2663`), `CreateCheckButton` (`:2355`), `CreateButtonGroup` (`:859`) for the layout picker.
  The only new one is `UI.CreateSwatches`.
- **Live apply.** A control writes `db.clockLook.over.<key>` and calls `MD:Fire("CLOCK_LOOK")`,
  and both the widget and the preview rebuild. Like the window-scale slider
  (`UI/Dashboard_Forever.lua:74-76` comment), the clock's scale applies on mouse-up.
- **Show on screen** is the existing preview: TBC `MD:ForceWidgetPreview(60)`
  (`UI/Widget.lua:178`), Forever `Clock:Preview()` (`UI/Clock_Forever.lua:287`).
- **Slash commands:** `/st clock layout line|compact|bar|ring`, `/st clock look reset`,
  `/st clock preview`.
- **Later:** a look as a short ASCII string (`/st clock look export`), with no library. The
  `MD.Text.EscASCII` rule applies.

---

## 8. What must stay true

### 8.1 Invariants

1. **One visibility owner per line** (CLAUDE.md "Widget visibility has a single owner"). Only
   `MD:UpdateVisibility` (`UI/Widget.lua:189`) and Forever's `UpdateVisibility`
   (`UI/Clock_Forever.lua:62`) call `Show`/`Hide` on the clock. Neither the renderer nor the
   preview frame does. A layout switch rebuilds regions *inside* the frame and never hides the
   frame.
2. **Forever secrets.** The real pool is handed to a bar by `MD.API.DrawUnitPower`
   (`Client/API.lua:329-344`) and never read.
   - No text, no ring, no colour and no show rule uses it.
   - `pct` on Forever is the model's.
   - Any future "real % as text" goes through a new adapter function that hands the secret to a
     font string unread, mirroring `DrawUnitPower`. It stays **off** until probe Q-clock-2 says a
     font string displays it.
3. **ASCII, no bare pipe, two-space separator** (`docs/DECISIONS.md:107`). All words come from
   `ClockFace.LineString` or the per-segment helpers. `tools/textcheck.py` covers the constants;
   the new suite covers what gets rendered.
4. **Honesty marks cannot be configured away:**
   - the `~` on Forever (`Engine/ManaModel.lua:265-267`);
   - TBC's `~` for an unstable estimate (`Engine/TTO.lua:374`);
   - the `>` bound and `=` (`:361-368`);
   - `--` and never `0` (`:365`, `DECISIONS.md:290`);
   - `...` for warmup.

   If both lines ever show `~` in one layout, the hover keeps saying which `~` means what, because
   the two lines use it differently.
5. **Precision belongs to the model.** No "decimals" on OOM, FULL or rest; formats only
   (`DECISIONS.md:110`). Tone thresholds move together with the latch's crossings (6.3).
6. **The arrow follows its rules:** it is derived from the shown value, and it never appears in
   FULL or out of combat (`DECISIONS.md:113`).
7. **The engine and recordings are untouched.** The face record is render-only. `MD:GetManaState()`
   (`Engine/TTO.lua:139`) and `Pool:Project` stay what every other module reads.
8. **No libraries and no media files** unless `release.sh` gains a media rule. The ring is built
   from `UI.whiteTexture`.
9. **TBC behaviour changes only by documented decision.** L1 with no overrides must equal
   today's TBC clock, byte for byte and pixel position for pixel position, *except* the F2
   alignment fix. F2 restores `DECISIONS.md:116` but reverses T82's centring, so it needs a
   one-line DECISIONS note. Each Forever parity fix (F1, F3-F6) gets its own line.

### 8.2 Tests

- **New `tools/clockfacecheck.lua`, on both flavours.**
  - It renders every layout against every sample face (`ClockFace.SAMPLES`): ASCII, no bare pipe,
    no `nil`, no `0` for a missing value.
  - L1's string equals `GetDisplayString` / `ManaModel.Text` for the same state.
  - Under the stub's `forever` profile, whose secret stand-in raises on arithmetic and
    comparison, the renderer and the preview never touch a secret.
  - A layout switch leaves the frame's shown state alone.
- **`ttocheck/tbc` (47)** and **`clockcheck/forever` (29)** stay green unchanged in K1. They gain
  the F-fix checks in K2: F1's tones, F3's warrior on Forever stays hidden in combat, F4's
  click-through.
- **`Visibility.Want` with a `rule` argument:** default equals today's on a table of cases. The
  extra cases cover `ooc = "never"`, `manaUsersOnly` and `combat = "never"`.
- **Stub additions:** `Texture:SetRotation` and `SetReverseFill`, recorded so the ring's geometry
  can be read back.

### 8.3 Probe questions

| ID | Question | Why |
|---|---|---|
| Q-clock-1 | Does `UnitPowerPercent("player", 0, false, C_CurveUtil.CreateColorCurve(...))` return a colour the bar texture's `SetVertexColor` accepts, plain or secret? | Colour the real-pool bar by its real level without reading it |
| Q-clock-2 | Does `fs:SetText(UnitPowerPercent("player", 0))` *display* a number, and does `fs:GetText()` read back secret? | A real `%` as text on Forever |
| Q-clock-3 | Does `ColorPickerFrame:SetupColorPickerAndShow` exist on both clients (TBC 20506 and Forever)? | The "Custom..." colour button |
| Q-clock-4 | Do `Interface\TargetingFrame\UI-StatusBar`, `Interface\RaidFrame\Raid-Bar-Hp-Fill` and the four `Fonts\*` paths load on Forever? | Bar textures and fonts |

---

## 9. The same design on both lines

| Face field / feature | TBC source | Forever source |
|---|---|---|
| mode, value, known | TTO display latch (`Engine/TTO.lua:243-306`) | `Pool:Project` and ManaModel's 5 s rounding |
| tone | value band 20 / 60 s | the same bands on the rounded value (new, F1) |
| unstable / modelled `~` | `not s.stable` | always modelled |
| arrow | `Arrow()` | none (optional latch, 5.1) |
| second: rest | `s.rest`, 25 % rule | `state.rest`, the same 25 % rule (`Engine/ManaModel.lua:257-263`) |
| second: cd (`inn`) | ManaCooldowns | n/a |
| fsr / tick | `RM:FSRRemaining()`; tick from the regen events | `model.lastSpend + 5 - now` (priced casts); tick n/a |
| mp5 | `RM:Current() * 5` | `~ state.regen * 5` |
| pct | `UnitPower/UnitPowerMax` | `~ model.mana/model.max` |
| bar `pool` | plain `SetValue` | `MD.API.DrawUnitPower`, drawn only |
| visibility | `MD:UpdateVisibility` + `Want(rule)` | `UpdateVisibility` + `Want(rule)` |
| settings view | Settings → Clock | Settings → Clock |
| datatexts | ElvUI (and the EllesmereUI topic) read `LineString` or a compact face | (when an integration exists on Forever) the same |

---

## 10. Suggested task split

| Task | What | Visible change | Files |
|---|---|---|---|
| **K1** | The face record and `LineString`. `GetDisplayString` and `ManaModel.Text` reimplemented on it. | None (goldens) | `Engine/TTO.lua`, `Engine/ManaModel.lua`, new `UI/ClockFace.lua` (both TOCs), new `tools/clockfacecheck.lua` |
| **K2** | Forever parity: tones (F1), the usesMana gate (F3), click-through (F4), pulse and <30 s flash (F5), rest toggle (F6). F2 fixed segments on both lines. | Forever: colours, warriors no clock. Both lines: steadier text. | `UI/Clock_Forever.lua`, `UI/Widget.lua`, `UI/Visibility.lua`; DECISIONS lines |
| **K3** | The renderer with L1, L2 and L3, `db.clockLook` with `over`, the spark, bar sources. | Opt-in | `UI/ClockFace.lua`, both widgets |
| **K4** | Settings → Clock with the live preview and swatches. Mockup first (the author's rule: mockups before UI builds). | New view | `UI/Dashboard.lua`, `UI/Dashboard_Forever.lua`, a new `UI/ClockSettings.lua` (shared), `UI/Style.lua` (`CreateSwatches`) |
| **K5** | L4 Ring | Opt-in | `UI/ClockFace.lua`, stub |
| **K6** | L5 Two lines, only after the author rules on `DECISIONS.md:117` | Opt-in | |
| **K7** | Presets tied to the UI-style topic; the datatexts' compact mode; the probe questions Q-clock-1 to 4 | | `Client/Probe.lua`, `Integrations/*` |
| **K8** | Phase 2: one `UI/Clock.lua` with a per-line source; positions and locks adopted once | None intended | both widgets → one |

### 10.1 Decisions the author has to make

1. **F2 alignment.** Left-anchored (`DECISIONS.md:116`) or keep T82's centring? The recommendation
   is left, with fixed segments.
2. **Two-line layout.** Allow it as opt-in, against `DECISIONS.md:117`?
3. **Bar meaning.** Keep "the TBC bar is the 5SR, the Forever bar is the pool", or make the
   default "pool plus 5SR spark" on both lines (F7)?
4. **TBC colours under the flat theme.** Should the TBC tones follow the theme tokens (`good`
   5CCB6E, `muted` 7A7A7A), or keep TTO's literals?
5. **Left-click in combat.** Should TBC adopt Forever's out-of-combat-only rule
   (`DECISIONS.md:1063`)?
