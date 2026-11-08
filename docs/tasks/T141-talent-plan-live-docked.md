# T141: the talent plan applies at once, beside the window (Forever)

The author, 2026-11-08: "I would like talent part to not have 'Use in what if' but instead each talent
change applies right away. And also make it to the side, not on top of dashboard, so I can see the change
of value in dashboard when we change talents".

## What changed (`UI/TalentPlanner.lua`)

- **No Use in What if.** Each click, Clear and My talents goes into the What if at once (`TPL.Apply` ->
  `TP:Apply`, one `WHATIF_CHANGED`). The Spells pane follows each click.
- **x and ESC close the panel and keep the plan in the What if.** The What if's own Clear clears it,
  and the plan follows that.
- **Docked beside the main window**, not over it:
  - It sits to the window's right when the screen has room, else to its left.
  - It is clamped to the screen, moves with the window and hides with it.
  - It is the window's own child, so moving between spells in the rail keeps it open.
- **`UI.CreateSheet(..., { docked = true })`** (`UI/Style.lua`): a sheet with no mask that is never
  "the one open sheet", so other sheets neither hide it nor are hidden by it.
- **Resync:** the panel's resync on `WHATIF_CHANGED` sees its own values come back and moves nothing.

## Acceptance

- `tools/talentplancheck.lua` 27, `make check`.
- In game: `docs/TESTING.md` §62.
