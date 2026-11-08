# T144 implementer report: the clock bar after the first in-game look

Task: `docs/tasks/T144-bar-fixes-real-mana.md`. Branch `worktree-forever-talents`. Not installed, pushed
or published.

## What was built, file by file

- **`UI/Style.lua`** (item 1, the shared dropdown, so every long list benefits)
  - `UI.DROPDOWN_ROWS = 12`. The open list shows at most that many rows. When the screen has less
    room above or below the button, it shows fewer (never under 3). The room is measured with the
    same `Box` / `ScreenSize` / `Extent` helpers `UI.ListSide` uses.
  - The mouse wheel on the list scrolls one row a step (`dd:Scroll(delta)`, clamped). A 5-px bar
    in the rail's style (the `track` fill, an `accent` thumb) shows only while the list holds more
    than it shows. The rows give up its width while it shows.
  - On open (`dd:PlaceList`), the selected entry is scrolled into view, in the middle when it can be.
  - `dd.rows[i]` is still item i's row. A row out of view is hidden, not reused, so every
    existing test helper that clicks `dd.rows[i]` still works. `dd.offset`, `dd.visible` and
    `dd.scrollBar` are exposed.
  - The ESC stack, `UI_POPUP` (`WatchPopup`) and the list's side are unchanged. The tree dropdown is
    untouched. There is no header system, because the widget has none.
- **`UI/ClockView.lua`**
  - Item 2: `METRICS.bar` no longer measures any item. The minimum is the bar's own (`chip + 20`),
    so no text, at any size, place or offset, changes the frame's width or height. `ItemSample`,
    the Bar's only user of `CV.KIND_SAMPLE` and `look.labelSample`, is removed. Line and Compact
    keep their samples. Each item's font string gets `SetWordWrap(false)`. With one anchor and no
    width, an inside text wider than the bar runs over the ends on one line.
  - Item 4:
    - `View:Paint` asks `draw.powerText` for `manaMax` when a Mana slot is "of max". Before, it
      asked for `mana`, which with the flag on would have lost the "/max".
    - `View:PaintItems` also asks for the `manaMax` item.
    - Both keep the font strings the line drew in `view.powerFs`.
    - New `View:PaintPowerTexts()` asks `draw.powerText` again for just those font strings. It
      does no layout, no words and no measuring, and returns how many it drew.
- **`Engine/ClockFace.lua`** (item 3): `CF.ItemPieces` strips every `~` from each piece's `text` /
  `labelText` / `valueText`. That covers Forever's modelled marks and TBC's unstable mark, and it
  drops the "label off -> `~` on the time" rule. `CF.Slots`, `Segments` and `LineString` (Line,
  Compact, the feeds) are unchanged.
- **`Client/API_Forever.lua`** (item 4)
  - `ST.API.POWER_TEXT_READS = true`, with a comment naming EllesmereUI's shipped code on the same
    client, 2026-11-08.
  - `DrawPowerText` draws with `fs:SetFormattedText`:
    - `mana`: `"%d"` with `UnitPower`;
    - `manaMax`: `"%d/%d"` with `UnitPower`, then `UnitPowerMax`;
    - `pct`: `"%d%%"` with `UnitPowerPercent(unit, pt, true, CurveConstants.ScaleTo100)`. It
      answers `nil, "absent"` when `CurveConstants` or its `ScaleTo100` is missing.
  - Everything is inside the one pcall, and no value is compared, concatenated or computed on.
  - `POWER_TEXT` is still the names table (`manaMax = "UnitPowerMax"` added), plus a local
    `POWER_FMT`.
  - `CurveConstants` is read with `rawget(_G, ...)`. Only its type is tested. It is not in
    `tools/data/forever_api.json` (the baseline lists functions and namespaces, not constant
    tables), so a bare global read would be flagged by apicheck rule 1.
- **`Engine/ManaModel.lua`** (item 5)
  - `ManaModel.Steady(latch, face, now)` with `STEADY_SNAP = 60`, `STEADY_STEP = 5` and
    `STEADY_EVERY = 1.0`.
  - It is pure, and never changes the face in place. A held value comes back in a copy. On an
    OOM point face, that copy's tone band is re-read for the held value.
  - It snaps on:
    - a label or mode change;
    - a value that is not a point (nil, bound, pending), or one coming back from that;
    - a value over 600 s;
    - a gap of 60 s or more.
- **`UI/Clock_Forever.lua`**
  - The latch lives here. `PaintFace` applies `Steady` before `view:Paint`.
  - The latch is emptied on `PLAYER_REGEN_DISABLED`, on `PLAYER_REGEN_ENABLED` (a new handler) and
    whenever the clock hides (both hide paths in `UpdateVisibility`). `Clock:SteadyLatch()` exposes
    it for the test.
  - The `UNIT_POWER_FREQUENT` handler also calls `view:PaintPowerTexts()`.
- **`Client/Probe.lua`**: comment only, at Q-clock-2. It says the question is answered by that
  evidence, and the probe line stays as confirmation.
- **`docs/DECISIONS.md`**: the Q-clock-2 bullet (Clock v2 section) now says it was answered on
  2026-11-08 by EllesmereUI's code, the flag is on, the formats are as above, and a probe
  confirmation is still welcome.
- **`docs/TESTING.md`**: added section 65 (Forever, about 3 min). It covers the list, sizes and places,
  no `~`, mana equal to EllesmereUI's while regenerating, and the 5 s steps at most once a second.

### TBC

TBC's `powerText` is unchanged. TBC's items already show real mana: `ST:GetClockFace`
(`Engine/TTO.lua:349-352`) fills `face.mana` / `manaMax` / `pct` from a plain read, with
`manaModelled` / `pctModelled` false. The new test checks this (4210, 4210/6800, 62% with no
`draw.powerText`). The TBC items now also lose TBC's own "unstable" `~` on the time, because
item 3 says no `~` on any piece.

## Tests (written with the code, then checked to fail on HEAD)

The new and updated tests were run against a `git archive HEAD` copy with the old code:
- clockui: 7 failed on forever, 3 on tbc;
- clocksettings: 1 failed on each flavour;
- clockcheck on forever stopped with an error, since `Steady` did not exist;
- adaptercheck on forever failed.

New checks:
- **clockui** (+3 on each flavour, 56 / 56):
  - every item on, sizes 6 / 11 / 20 / 32 x every place x the x / y ends: the frame stays 200 x 8
    and the minimum stays 20 (36 paints); the width and height controls still work; an inside item
    is one line with one anchor;
  - no `~` on any Bar text for every SAMPLES face, label on and off, while Line keeps its marks on
    Forever;
  - Forever: mana / manaMax / pct go to `SetFormattedText` with the secret unread (`%d`, `%d/%d`,
    `%d%%`); `PaintPowerTexts` draws all three again with zero `Layout` calls; the flag off hands
    nothing; no `CurveConstants` means pct is `absent`;
  - TBC: plain numbers, no `powerText`.
- **clockcheck** (+5, forever 44):
  - the 25 -> 15 sequence: 25 at t 0 and 0.5, 20 at 1.0 and 1.5, 15 at 2.0, and the face is not
    mutated;
  - the snaps: label, mode, nil and back, bound, 60 s;
  - a true countdown never runs more than one step behind;
  - the latch is emptied on both regen events and on hide;
  - `UNIT_POWER_FREQUENT` for the player calls `PaintPowerTexts`, and for another unit it does not.
- **clocksettings** (+1, forever 55 / tbc 54): a 39-entry Texture list opens with at most 12 rows
  and the selected entry in view; the height is rows x 17 + 3; the scroll bar shows; the wheel
  clamps at both ends; a row still picks; a 3-item dropdown is unchanged.
- **adaptercheck** (forever 26 -> 27): see the next section.

Assertions changed because the spec changed them:
- **adaptercheck**:
  - "ships off" became "is on" (item 4 orders the flag flipped);
  - the off test still checks that nothing is touched with the flag off, now by setting the flag
    false explicitly;
  - a new check covers the three formats, the unread secrets, the unknown kind and the missing curve.
- **clockui test 8**: it now checks that the default is on and that `SetFormattedText` is handed
  the secret. The off half (`~62%`, no call) is kept, with the flag set false explicitly.
- **clockui T142 tests** (the task says to update them):
  - the expected words drop `~`;
  - Forever's mana in the default Bar is the game's own, so it is left out of `view:Text()`;
  - Forever's Mana / max is checked as handed to `powerText`.
- The T142 test "outside texts never change the frame" was left as it is. It still passes, and
  the new T144 test is the stronger one.
- **stylecheck**: the clock golden was re-based on both flavours, 37 -> 36 regions. With `--print`
  diffed against HEAD, the only difference is one hidden FontString: the Bar's measuring probe,
  which is no longer made because the Bar no longer measures. Every other line and section is
  byte-identical.

`tools/data/expected-counts.json`: adaptercheck/forever 27, clockcheck/forever 44, clocksettings
55 / 54, clockui 56 / 56. The import fixture was not rebuilt: nothing stored changed.

## Suite output

The affected suites, last lines: clockui 56 ok / 0 failed (forever) and 56 / 0 (tbc); clockcheck
44 / 0; clocksettings 55 / 0 and 54 / 0; adaptercheck 27 / 0 and 19 / 0; stylecheck 34 / 0 on both.
`luac -p` passes on every touched Lua file.

The first `make check` failed only on stylecheck's golden (forever and tbc) and the counts that
follow from it. After the re-base, the final `make check`, last lines:

```
  counted 102 run(s) against 102 expected

check: 107 run(s), all passed
exit 0
```

## Choices where the task left one

- The scroll bar is a thin track and thumb, the rail's own look. It shows the position; it does
  not drag. Wheel only.
- On open, the selected row is centred when possible.
- The steady latch also snaps above 600 s (">10m": no steps there).
- A held OOM value re-reads its tone band, so the colour matches the number shown.
- `PaintPowerTexts` redraws only the font strings the last tick gave to the game. A Bar text the
  game refused that tick (for example pct with no `CurveConstants`) stays on the face's words until
  the next tick.

## Not done / for the lead

- **`docs/HISTORY.md` was not edited**: the agent rules reserve it for the lead, although the
  task's Acceptance asks for it. Suggested entry:
  "2026-11-08 T144: the Texture list scrolls (12 rows, wheel, the selected one in view; every
  dropdown); no text changes the Bar's size; no `~` on the Bar's texts; Forever's mana texts are
  the game's own (`POWER_TEXT_READS` on, from EllesmereUI's in-game evidence; `SetFormattedText`;
  redrawn on `UNIT_POWER_FREQUENT`); the time steps 5 s at most once a second (`ManaModel.Steady`).
  TESTING section 65."
- **CLAUDE.md rows** (lead):
  - `Client/API_Forever.lua`: `DrawPowerText` on, `SetFormattedText`, mana / manaMax / pct;
  - `UI/ClockView.lua`: no text sizes the Bar, `PaintPowerTexts`;
  - `Engine/ManaModel.lua`: `Steady`;
  - `UI/Style.lua`: the dropdown scrolls, `UI.DROPDOWN_ROWS`.
- **docs/TOOLS.md** suite counts were not updated.
- **In-game risks, for section 65:**
  - **`CurveConstants`.** If the client has no `CurveConstants`, Mana % on the Bar falls back to
    the model's number, now without `~`. EllesmereUI's code guards it the same way
    (`CurveConstants and ...`), so it may be absent on some builds.
  - **`"%d"` and the format.** EllesmereUI formats the current value with `"%s"`, not `"%d"`.
    The task specifies `"%d"`. If the client's formatter raises on `"%d"` with a secret,
    the pcall catches it, `DrawPowerText` answers `nil, "error"` and the text falls back to the
    model's number (unmarked on the Bar). section 65 step 4 asks the author to report any mismatch, blank
    or `%d`.
- The other Q-clock-2 mentions in `docs/SPEC-next.md` and `docs/TOOLS.md` still say "off". They
  are spec history and were left unchanged.
