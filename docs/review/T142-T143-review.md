# Review: T142 (f24beae) and T143 (20708b3)

Reviewer: independent adversarial review, 2026-11-08. Checkout: `worktree-forever-talents` at 20708b3.
Scope: in-game failure modes the offline harness cannot catch. The full `make check` was not rerun
(reported green, 107 runs).

**Verdict: pass-with-minors.** 0 blockers, 0 should-fix, 6 nits. Two items are in-game watch points
that could not be verified offline.

This is the first review of both units.

## What was checked and found sound

- **Load order and locals.**
  - `Core.lua:48-66`: `local Dispatch` is declared before `ST:OnUnit`, and `function Dispatch` at
    `Core.lua:103` assigns that upvalue rather than a global.
  - `"\0"` is a valid Lua 5.1 escape.
  - `ITEM_OK` (`UI/ClockView.lua:464`) is defined before the `CV.OVER` loop that reads it.
  - `PieceText` (2081) and `HexRGB` (2159) are defined before `PaintItems` (2172).
  - `KindPiece`, `Pieces`, `LabelWord` and `TimeFmt` are defined before `CF.ItemPieces`.
- **Secret values (T143).**
  - `Client/API.lua:333-357`: the pool is still handed to `SetMinMaxValues` / `SetValue` without
    being read.
  - The interpolation probe touches only `Enum`.
  - The `UNIT_POWER_FREQUENT` handler (`UI/Clock_Forever.lua:478`) ignores its arguments.
  - `Dispatch` passes the event's arguments through `xpcall` unread.
- **Per-event cost.** `View:PaintMana` (`UI/ClockView.lua:2262`) on each `UNIT_POWER_FREQUENT` does:
  - one `DrawUnitPower` (two cached `Has` lookups, one closure and one pcall);
  - `SetAlpha` and `SetStatusBarColor`;
  - `ManaColour`, which is constant-time;
  - `Gradient`, which returns at once unless the texture is `gradient`.

  It does no layout, no measuring, no atlas work and no `SetGradient` on the default look. The
  heavier work stays where it was: `Layout`/`METRICS` on the 0.5 s tick, and `PlaceGame` only on
  `Place` / `Snap`.
- **The frame never grows.** `METRICS.bar` (`UI/ClockView.lua:1418-1484`):
  - The frame height is `barH`.
  - `minW` counts only the `inside` items.
  - Above and below texts are anchored outside the holder. Nothing in `View:Place` sizes from them.
- **Mask and atlas use.**
  - Every mask is created on the frame that owns the textures it clips: `g.mask` on `bar` for the
    fill and bevels, `g.backMask` on `p` for `barBack`. This is the T139 pattern.
  - `SetAtlas` on a MaskTexture is what EllesmereUI does.
  - The sublevels are in range (BACKGROUND -2, OVERLAY -3).
  - "Off" restores the masks to WHITE8X8 with CLAMPTOWHITE, which clips nothing.
  - `GameClip` de-dupes the mask per texture.
  - `ST.API.SetGradient` passes `"VERTICAL"` / `"HORIZONTAL"` with `CreateColor` objects. That is the
    signature from 10.0 on, and the alpha rides in the colour.
  - The bevel directions match the spec: the dark edge is at the bar's rim.
- **Fallbacks.**
  - `CV.GameFrameOK` asks `ST.API.HasAtlas`, which goes through `Call`, checks only the answer's
    type, and gives "absent" where `C_Texture` is missing.
  - TBC and an atlas-less client draw the border and record the reason in `refused`.
  - The font falls back to the kit's face with a reason.
- **TBC.**
  - `ST:OnUnit` is defined on both lines, but only `Clock_Forever.lua` calls it.
  - `smooth` is never passed on TBC.
  - No `Enum` is read on TBC.
  - `RegisterUnitEvent` is guarded by a type check.
- **CLAUDE.md rules.**
  - ClockView only shows and hides its own textures and font strings, never the frame.
  - `ST.db` is touched only in `StoredRaw`.
  - The client read for the atlas is `ST.API.HasAtlas`.
  - The new strings are ASCII.
- **Migration: runs once.**
  - `CV.ResetBarLook` (`UI/ClockView.lua:724`) returns early at `v >= 2`, and `v` is saved in
    `db.clockLook`.
  - No in-game code rewrites `db.clockLook` without `v`. `CV.ResetToStyle` replaces only `over`.
  - A fresh store, whose defaults are filled without `v`, resets an empty `over` once: nothing is
    lost and there is no dump line.
- **Migration: what it resets on the author's own store.** Read-only from
  `_forever_/WTF/.../SpellTuner.lua`. It clears exactly these 8 keys:
  - `bars.bar.height`, `bars.bar.shape`, `bars.bar.texture`;
  - `text.bar.left`, `text.bar.size`;
  - `frame.bar.w`;
  - `colors.manaBar`, `bar.back`.

  It keeps `layout = "bar"` and `db.clock.point`, which lives outside `clockLook`.

## Findings

### N1 (nit): the reset also clears colours that Line and Compact share (`UI/ClockView.lua:723`)

`CV.RESET_COLOURS` lists `colors.manaBar`, `bar.back`, `colors.fillEnd`, `colors.edge`,
`colors.fsrLine` and `colors.after`.

- These overrides are global. `CV.Resolve` reads `colors.*` and `bar.back` for every layout
  (`UI/ClockView.lua:566-578`, the two-part key branch).
- So the reset changes the Line and Compact looks too.
- The task asks for this, so it is spec-conformant. But the implementer report says "Line and
  Compact overrides are kept", which is not true for these six.

Scenario: a player with a custom fill colour on the Line layout loses it at the first login after
the update. The dump line does name it.

Fix: correct the report, and mention this in TESTING §63 so the author is not surprised.

### N2 (nit): the reset clears `frame.bar.scale` (`UI/ClockView.lua:737-740`)

The `frame` area clears all of `over.frame.bar`, which includes `scale`. The task asked for the Bar
layout's "frame size".

Scenario:
- A player has `frame.bar.scale = 120` and a saved `db.clock.point`.
- The point offsets are in the frame's scaled units.
- After the reset the scale is 100, so the clock lands at a different place on screen.

The author's store has no scale, so this does not affect the install at hand. Fix: keep
`frame.bar.scale`, or note it in the report.

### N3 (nit): presets on Line or Compact now reset that layout's width and change the Bar's texts

At `UI/ClockSettings.lua` (`CS.ApplyPreset`), `Put("frame." .. L .. ".w", pre.width, ...)` runs for
whatever layout is drawn. The preset buttons are not hidden off the Bar layout (`CS.Refresh` hides
only frame, font, the items table and height).

Scenario:
- The player is on the Line layout with `frame.line.w = 300` and clicks "SpellTuner default". The
  Line width goes back to 180.
- The player is on Compact and clicks "Like my EllesmereUI". This writes `frame.compact.w = 260` and
  `bars.compact.show = "mana"`, and rewrites all `text.bar.items.*`.

Fix: hide the presets off the Bar layout, or skip the width and items when `L ~= "bar"`.

### N4 (nit): the clock's mouse target is now the 8-px bar (`UI/ClockView.lua:1450`, `m.h = barH`)

The task requires this ("the frame is the bar"). Its in-game consequences:
- the hover tooltip, the click and the drag work only on an 8-px strip;
- the unlock or preview message "SpellTuner - drag me" is centred in an 8-px frame;
- `SetClampedToScreen` (`UI/Clock_Forever.lua:321`) clamps only the bar, so texts below the bar and
  the art's 7-px shadow can go off-screen near an edge.

Fix: say so in TESTING §63. Optionally, widen the hit rect with negative `SetHitRectInsets` on the
line's side when outside texts are on.

### N5 (nit): a number box writes and rebuilds the clock even when nothing changed (`UI/ClockSettings.lua:1131-1141`)

`OnEditFocusLost` commits every time. Pressing Enter commits twice: once in `OnEnterPressed`, then
again in `ClearFocus`, which triggers `OnEditFocusLost`.

Scenario: clicking into the X box and out again fires `CLOCK_LOOK`. That runs a full `SetLook`:
EllesmereUI's font is asked again, the atlases are set again and the fonts are reapplied.

The cost is small, but it is a rebuild per focus change. Fix: commit only when the clamped number
differs from `it[field]`.

### N6 (nit): the font handed over by `E.FontPath` can be stale once (`UI/Style_Ellesmere.lua:259-273`)

`lastFont` is kept from the last `Resolve` until some caller of `E.FontPath` consumes it.

Scenario:
- The Ellesmere style was active.
- The player switches to Flat, then changes EllesmereUI's font. No `Resolve` runs.
- The next clock rebuild gets the old path once.

The report already says that an EllesmereUI font change waits for the next rebuild. Fix: drop
`lastFont` on `STYLE_CHANGED` away from Ellesmere, or accept it.

## In-game watch points (not verifiable offline; not findings)

- **W1 (T143). `Client/API.lua:351-354` calls `SetMinMaxValues(0, max)` on every call (up to the
  `UNIT_POWER_FREQUENT` rate), and then `SetValue(cur, ExponentialEaseOut)`.**
  - EllesmereUI sets the min and max only when the max changes.
  - If the 12.x client snaps or restarts the interpolation on each `SetMinMaxValues`, the bar will
    still step or stutter.
  - Watch TESTING §64 for this.
  - If it shows: set the min and max only from `UNIT_MAXPOWER` and the tick. A secret max cannot be
    compared, so a "changed?" test is not possible. Splitting the call so that `PaintMana` does only
    `SetValue` on the frequent event is the safe shape.
- **W2 (T143). An eased bar, shown again after being hidden, animates from its stale value.**
  - This happens out of combat above 95% mana, when the clock is hidden.
  - On re-show you may see one sweep instead of a jump.
  - It is cosmetic.

## Not re-verified

- The suites' internals beyond the T143 checks. `tools/clockcheck.lua`'s two new checks can fail as
  written: the mode is asserted, and the other unit's event is counted.
- Visual parity with EllesmereUI. That is TESTING §63, in game.
