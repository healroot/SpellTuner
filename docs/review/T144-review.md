# T144 review (commit 96aee98, branch worktree-forever-talents)

Reviewer: independent adversarial review (Opus), 2026-11-08. First review of this unit.
Scope: spec `docs/tasks/T144-bar-fixes-real-mana.md`, implementer report
`docs/review/T144-implementer-report.md`; the five in-game failure areas the brief named.
`make check` was not rerun (reported green, 107 runs).

**Verdict: pass-with-minors.** 0 blockers, 1 should-fix, 6 nits.

## What was checked and holds

- **(a) DrawPowerText / secrets** (`Client/API_Forever.lua:107-127`). No Lua-side touch of a
  returned value: each client return goes straight into `fs:SetFormattedText` as an argument
  inside the one pcall. `ScaleTo100()` tests only the presence of `CurveConstants.ScaleTo100` (by
  `type()`), never its value. `"%d"` with a secret number is proven in shipped code on the same
  client: EllesmereUI's `EUI_ResourceBars_Update.lua:2030` (`ct:SetFormattedText("%d%%", pct)`)
  and `:498` (`format("%d", pctRaw)`), both with secret `UnitPowerPercent` returns. So the
  implementer's `"%d"` vs `"%s"` risk is low. A failed SetFormattedText is one C call that leaves
  the font string unchanged, so no half-written text. `View:PaintPowerTexts`
  (`UI/ClockView.lua:2207-2217`) pcalls every entry, so repeated failures never reach the error
  handler. Nothing reads these font strings back: `GetStringWidth` / `GetText` are called only on
  the hidden measuring probe (`UI/ClockView.lua:932-943`) and on `msg`. No frame is anchored to
  an item or slot font string, so a secret extent cannot spread into geometry.
- **(b) Dropdown** (`UI/Style.lua:2596-2760`). `RAIL_BAR_W` (line 1960) and `Box` /
  `ScreenSize` / `Extent` (lines 1793-1815) are upvalues in scope. The divide by `maxOff` runs only
  when `scrolls` (so `maxOff > 0`). An empty list is safe: `vis` = 0, the height is `height`, the
  bar is hidden. ESC and `UI_POPUP` are unchanged: `WatchPopup` is on the same list frame. Nothing
  outside Style.lua reaches into `dd.rows` or `dd.list`; 10 call sites were checked. The rail
  already uses the same thumb and track calls on TBC (`UI/Style.lua:2017`). Nothing is protected,
  so combat is not affected. The tree dropdown is unchanged.
- **(c) Bar metrics** (`UI/ClockView.lua:1398-1455`). The removed locals (`t`, `labelOn`, `need`,
  `Need`) are not referenced in what remains, so no undefined globals. `minW` = chip + 20. Line and
  Compact keep `SlotSample` / `MeasureIn` (lines 1190-1255). `SetWordWrap(false)` is applied only
  in the items branch (line 1747). No frame on the path clips its children.
- **(d) Steady** (`Engine/ManaModel.lua:372-403`). `face.value` is already rounded to 5 s by
  `Shown` (line 251), so 5 s steps stay on the grid. A step happens only when at least 1 s has
  passed since the last change, so the value changes at most once a second. It snaps on a label or
  mode change, on a non-point value (and when the value returns), above 600 s, and at a gap of
  60 s or more. The face is copied, never mutated, and the OOM tone is re-read. The countdown test
  (`tools/clockcheck.lua`) can fail: a lag over one step fails it. The latch is reset on
  `PLAYER_REGEN_DISABLED` / `ENABLED` and on both hide paths (`UI/Clock_Forever.lua:107,117`).
- **(e) TBC.** `Engine/TTO.lua:349-352` gives TBC's face plain mana (`manaModelled=false`), and
  TBC has no `powerText`. `ItemPieces`' `~` stripping changes nothing on TBC. The only shared
  change TBC sees is the dropdown, which uses only calls TBC already makes.

## Findings

### S1 (should-fix) -- the Bar's model fallback is now unmarked everywhere; the hover's "model's" note is dead code
`UI/ClockView.lua:2185-2188` (PaintItems), with `Engine/ClockFace.lua:481-488` (`Unmarked`).
`ItemPieces` now strips every `~`, but PaintItems still detects a modelled mana number by
`piece.text:sub(1, 1) == "~"`. That can never be true, so `view.modelledWords` is always nil on the
Bar layout, and the hover's line "<x> is the model's; the game's own number cannot be shown yet"
(`UI/Clock_Forever.lua:232-235`) never appears for the Bar.
**Failure scenario:** the Forever client has no `CurveConstants` (EllesmereUI guards it with
`CurveConstants and ...`, so it may be absent), or `SetFormattedText` raises once. `DrawPowerText`
then answers `nil, "absent"` / `"error"`, and PaintItems draws the model's pct (`54%`) with no
`~`. The hover says nothing about it. The author sees a number that differs from EllesmereUI's,
with no sign that it is the model's. That is exactly the complaint T144 item 4 fixes, and
TESTING §65.3 promises "the hover still says which numbers are modelled".
If the failure is intermittent, the text also flips between the real number
(`UNIT_POWER_FREQUENT`) and the model's number (each 0.5 s tick).
**Fix:** in PaintItems, when `not drawn` and the kind is mana / manaMax / pct, set `modelled` from
the face's flags (`f.manaModelled` / `f.pctModelled`) and the piece's text, not from a `~` prefix.
Add a clockui case: `powerText` returns false on the Bar, then `modelledWords` is non-nil.

### N1 (nit) -- a closure per call on the UNIT_POWER_FREQUENT hot path
`Client/API_Forever.lua:116` (`pcall(function() ... end)`). On the retail engine, `PaintPowerTexts`
runs on every player power event, often several a second while regenerating, and calls this up to
3 times, so up to 3 closures (with 6 upvalues) per event. This is small garbage, not a leak. It
could be a module-level function with the arguments passed to `pcall`.

### N2 (nit) -- the feeds, LDB, minimap and datatexts show the unsteadied time
`Engine/ManaModel.lua:420-423` (`ClockFace.Current` on Forever) builds `ManaModel.Face` without
`Steady`. The clock shows 20 while an EllesmereUI or LDB datatext shows 15 for up to a second
(or more after a big jump). The spec scoped Steady to the clock, so this is only noted.

### N3 (nit) -- the latch is not reset after the preview
`UI/Clock_Forever.lua:387-389`: while `Previewing()`, PaintFace skips Steady, but the latch keeps
its old `shown` / `at`. After the preview it walks one step a second toward the new value from a
stale one, for example OOM 40 before the preview and 20 after: 35, 30, 25, 20 over 3 s. This is
mostly out of combat, where the REGEN resets do not help. Calling `ResetSteady()` in the preview
branch fixes it.

### N4 (nit) -- `View:Message` keeps `powerFs`
`UI/ClockView.lua:2438-2454`. After `Message` (the preview, for example), the next
`UNIT_POWER_FREQUENT` writes the real text into item or slot font strings that `Message` hid. They
stay hidden (SetFormattedText does not Show), so nothing is visible. Clearing `self.powerFs = nil`
there keeps the "only what the last paint drew" contract that `PaintPowerTexts` documents.

### N5 (nit) -- the list's fit can miss by 1-2 px at a high effective scale
`UI/Style.lua:2643-2655` (`Fits`) subtracts `3` (UI units) from a room measured in screen
pixels. `UI.ListSide` then needs `(h + 1) * s`. When the screen limits the rows, the list fits
only while `s <= 1.75`. Above that, `ListSide` finds neither side fits, returns "down", and the
list runs 1-2 px off the screen. This is rare (scale is up to 120% times UIParent's).

### N6 (nit) -- dead code and missing docs
- `CV.BarWordsW` (`UI/ClockView.lua:1352`) has no UI caller left.
- `docs/HISTORY.md` has no T144 entry, which Acceptance requires. The implementer left it to the
  lead, with a suggested entry in their report.
- The CLAUDE.md rows (`DrawPowerText` on, `PaintPowerTexts`, `ManaModel.Steady`,
  `UI.DROPDOWN_ROWS`) and the docs/TOOLS.md counts are still to update (the lead's).

## Note (not a finding)
Steady's first step is immediate when the shown value has been stable for over a second: a 25
held since t = -10 reads 20 at the t = 0 tick and 15 at t = 1.0. The spec's example (20 at 1.0)
assumes the 25 was first seen at t = 0, which is what the test seeds. Both meet "at most once a
second, one step at a time". The author may perceive the first change as a beat early.
