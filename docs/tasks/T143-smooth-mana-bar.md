# T143: the Forever clock's mana bar follows every power change, eased (Forever)

The author, 2026-11-08: "make the bar more responsive. While the ElvUI bar updates many times per
second, ours updates about twice a second in chunks. That makes sense in TBC, where mana regen has
ticks, but not on Forever, where it regenerates continuously."

## Cause

On Forever the real pool reached the bar only from `Paint` on the 0.5 s `ST:OnTick`:
`UI/Clock_Forever.lua` -> `draw.pool` -> `ST.API.DrawUnitPower`.

## What EllesmereUI does

Read from the author's Forever client, `EllesmereUIResourceBars/EUI_ResourceBars_Events.lua`:
- It repaints its power bar on `UNIT_POWER_FREQUENT`, registered with `RegisterUnitEvent` for
  `"player"`.
- With "smooth bars" on, it passes `Enum.StatusBarInterpolation.ExponentialEaseOut` to `SetValue`.

## Built

- **`Core.lua`: `ST:OnUnit(event, unit, fn)`.** It registers the event for one unit on its own frame,
  with the same refusal as `ST:On` (`ST.API.CanRegisterEvent`). Handlers run through `Dispatch`, so
  they are isolated the same way. This is the only way to register a unit event (apicheck rule 9).
- **`Client/API.lua`: `DrawUnitPower(bar, unit, powerType, smooth)`.** With `smooth`, it passes the
  client's `ExponentialEaseOut` to `SetValue` where the client has it, else it calls `SetValue`
  plainly. The value is still handed over unread.
- **`UI/Clock_Forever.lua`:**
  - `draw.pool` passes `smooth`.
  - `UNIT_POWER_FREQUENT` for the player calls `view:PaintMana()` while the clock is shown.
  - The words and the model keep the tick. The mana number is the model's `~` value until probe
    Q-clock-2.
- **TBC is unchanged:** its regen comes in 2 s ticks.
- **`tools/wowstub.lua`:**
  - `RegisterUnitEvent`, which `S.Fire` delivers only for that unit;
  - `UNIT_POWER_FREQUENT` added to the Forever events;
  - `SetValue` keeps the mode it was handed.
- **`tools/clockcheck.lua`** (37 -> 39 checks): the bar eases only where asked; a player power change
  repaints the bar and another unit's does not.

## In game

`docs/TESTING.md` §64: out of combat after a cast, the clock's bar fills as smoothly as EllesmereUI's,
with no steps every half second.
