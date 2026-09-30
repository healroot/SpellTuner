# T43 -- Review and replay text under the theme

Status: **built** 2026-09-30 on branch `ui/T43` (base 9c2a26e), awaiting review.

## The row (docs/SPEC-forever-ui.md section 9)

| # | Task | Files | Tests | Needs |
|---|---|---|---|---|
| **T43** | **Review and replay text under the theme** (4.1, 4.4): Review's run line (379) in `accent` and its four `GameFontHighlightSmall` strings in `UI.FONT_SMALL`; the replay's run strip (1432), header (1656, 1903) and `paused` (1852) in `accent`; `MD.Tip`'s `GOLD` from `UI.TEXT.accent`. All gated on `UI.TEXT`. | `UI/Dashboard_Review.lua`, `UI/ReplayWindow.lua`, `UI/Tooltip.lua` | `tools/reviewui.lua` 23 and `tools/replayui.lua` 98 unchanged (tbc); `tools/replayforever.lua` (+2: no `ffcc00` in the header or the run strip under forever) | T29 |

Spec sections: 4.1 (the gold table: the Review, replay and hover-tooltip rows, and "shared files read
colours through `UI.TEXT.<token>` and fall back to their current literals when `UI.TEXT` is nil"),
4.4 (Replay window, Review, Hover tooltips).

## What was built

All three files are shared with TBC. Each reads `UI.TEXT` (set only by `UI/Theme_Forever.lua`, which
the TBC TOC does not list and which the Forever TOCs load before any module file) and falls back to
its old literal when it is nil, so the TBC line takes the same path as before.

| file | change |
|---|---|
| `UI/ReplayWindow.lua` | `local function Hi()` -- `UI.TEXT.accent.hex` under the theme, else `\|cffffcc00`. The four gold openings use it: the run strip's name (`runStrip.label`), the header's `#n`, practice's `paused` hint and the `PRACTICE` header. Read at paint time. The unit frames are untouched (4.4: they are the author's Cell layout). |
| `UI/Dashboard_Review.lua` | File-level `SMALL` (`UI.FONT_SMALL` under the theme, else `"GameFontHighlightSmall"`) for the habits line, the progress line, the run line and every row cell; `RUN_HI` (the accent hex, else `\|cffffcc00`) for the run line. |
| `UI/Tooltip.lua` | `GOLD` (the one gold colour `MD.Tip` uses: the suggested rank's note in `Tip:Row`) is `UI.TEXT.accent`'s r, g, b when the theme is loaded, else `{ 1, 0.82, 0 }`. |
| `tools/replayforever.lua` | +3 (11 -> 14): the header's `#n` opens with the accent hex and carries no `ffcc00` / `ffd100`; the run strip's name likewise (the address `1:1` answered with a synthetic run for the one call, since runs are not recorded on Forever -- the strip paints whatever run it is handed), with the run pull's header checked too; `MD.Tip:Row` on a suggested row colours the note with the accent, not gold. |
| `tools/reviewforever.lua` | +1 (10 -> 11): every font string built on the Review pane or its rows is `UI.FONT_SMALL`, none `GameFontHighlightSmall`. The template is recorded by the script wrapping the stub's `CreateFontString` (not by a stub change). |

## Tests first

Against the base's addon code, with only the tests changed:

```
T43: the header's #n takes the accent, not gold              FAIL - |cffffcc00#2|r  Blood Furnace  03:33  0:30.0   |cffff9966does not replay|r
T43: the run strip's name takes the accent, not gold         FAIL -  label=|cffffcc00Underbog|r  2:00.0, 1 pull(s), 1 drink(s) header=|cffffcc00#1:1|r  Underbog pull 1 - ...
T43: MD.Tip's suggested-rank colour is the accent, not gold  FAIL - 1.000 0.820 0.000
replayforever: 11 ok, 3 failed

T43: the Review pane's small text is UI.FONT_SMALL, not GameFontHighlightSmall  FAIL - FONT_SMALL=0 GameFontHighlightSmall=30 other=
reviewforever: 10 ok, 1 failed
```

After: `|cffff7c0a#2|r ...`, `label=|cffff7c0aUnderbog|r ...`, `1.000 0.490 0.040` (the stub's druid
colour), `FONT_SMALL=30 GameFontHighlightSmall=0`.

## Full check

- The loop in `docs/TOOLS.md` section 1, plus `themecheck` and `tabscheck`: every suite at its base
  count except the two this task extends -- simcheck PASS, reccheck 54, replaycheck 80, replayui 98,
  runcheck 78, reviewui 44, navui 25, dashui 56, regencheck 27, simwindow 8, solvercheck 77,
  timeline 27, spelltip 48, practice 74, practiceui 49, migrate 7, probecheck 86, forevercheck 13,
  modulecheck 14, kitcheck 7, recordcheck 24, scenariocheck 12, gatecheck 9, **replayforever 14**
  (was 11, +3 above), **reviewforever 11** (was 10, +1 above), coachforever 18, practiceforever 20,
  bindscheck 6, parsecheck 12, bookcheck 17, tipcheck 27, clockcheck 17, spellsui 17,
  measurecheck 30, releasecheck 13, themecheck 23, tabscheck 24; adaptercheck 22 / 15, corecheck
  10 / 8, svcheck 6 / 1, consolecheck 14 / 1 (forever / tbc). All pass.
- The TBC suites' **full output** (the sixteen plus the four tbc flavours) diffed before and after:
  identical apart from wall-clock milliseconds, the frame-sliced search's evaluation counts (sliced
  on `debugprofilestop`) and table addresses.
- `python3 tools/apicheck.py`: 0 findings (46 files). `--selftest`: 10 of 10.
  `python3 tools/refcheck.py --selftest`: ok.
- `luac -p` on every changed Lua file: ok.

## Deviations

- The row says `tools/replayforever.lua` +2; it has **+3**: the third holds `MD.Tip`'s `GOLD`, which
  the row changes but no named test covered. `tools/reviewforever.lua` has **+1** the row does not
  name, for Review's four `UI.FONT_SMALL` strings (the stub keeps no font template, so the script
  records it itself rather than touching `tools/wowstub.lua`).
- The row's `tools/reviewui.lua` "23" is 44 at this base (it grew before this task); it is unchanged
  at 44. `tools/replayui.lua` 98 unchanged.
- Review's run line and the replay's run strip cannot be reached on Forever in play today: runs are
  not recorded there (`Recorder_Forever.lua`'s `GetRecording` answers nil for `a:b`). They are themed
  anyway, as the row asks, and the replay test reaches the strip with a synthetic run. `paused` and
  `PRACTICE` (the practice session's hint and header) are changed but not asserted: that path is
  `tools/practiceforever.lua`'s, which other tasks of this wave extend; it still passes at 20.
- `docs/TOOLS.md`'s counts for the two suites are not updated here: docs are T44's.
