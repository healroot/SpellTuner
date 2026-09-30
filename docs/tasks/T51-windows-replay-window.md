# T51 -- The window manager and the replay window (plan P7)

Status: **built** 2026-09-30 on branch `plan/P7` (base `4702b5c`), wave 3 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator.

## The task (docs/PLAN-refactor-ux.md section 5, P7)

Review items (`docs/review/2026-09-30-project-review.md`): B17, B18, B21, B22, B23.

- **(a) B17.** `Win:SetScale` wrote `db.ui.scale` and then converted only the saved places of the
  windows registered this session, each by its frame's own scale. A scale change made before the
  replay (or the console) was built left `db.ui.win.replay` in the old units, and the next
  `/st replay` opened 20 % toward the bottom-left and saved the wrong numbers.
- **(b) B18.** `UI.CreateNavFrame` (and the console's and the replay's own styling) snap the 1-px
  edges at UIParent's scale; `Win:Register` then applied the window scale and never re-snapped, so
  those edges drew at 0.8 (or 1.2) physical pixels until a UI-scale event or a later scale change.
- **(c) B21 (TBC-visible).** `/md replay run N`: crossing into the second pull re-entered
  `MD:OpenReplay`, which set the scrubber to that one pull's range. The run clock was clamped into
  it, the thumb stuck at the right, and a drag handed a pull-range value to the run's seek -- the
  run jumped back to its opening seconds.
- **(d) B22 (TBC-visible).** A run playing when combat starts (nothing hides the replay on TBC): at
  the next pull boundary `OpenReplay` refused and printed, `pullIdx` stayed, and the next frame
  asked again -- about 60 lines a second. A scrubber drag in combat printed per event.
- **(e) B23 (TBC-visible, practice).** A unit frame's `OnLeave` fires when the pointer moves onto
  one of its mouse-enabled icons; the Swiftmend, defensive and incoming-cast icons hooked only
  `OnMouseDown`, so a key over them reported "No target". No icon hooked `OnLeave`, so leaving a
  HoT or debuff icon outward kept the frame as the key's target.

Owned files (section 4, wave 3): `UI/Windows_Forever.lua`, `UI/ReplayWindow.lua`,
`tools/wincheck.lua`, `tools/replayui.lua`, `tools/practiceui.lua`, `tools/practiceforever.lua`.
Nothing else was touched.

## What was built

| file | change |
|---|---|
| `UI/Windows_Forever.lua` | `Win:SetScale(s)` reads `old = self:Scale()` before writing `db.ui.scale`, converts **every** `db.ui.win[key]` with a numeric `x` / `y` by `old / s` (registered or not, once each), then for each registered window converts this session's `w.pos` by its frame's scale, sets the scale and re-places it, as before. `Win:Register` calls `UI.RestylePixels()` right after `frame:SetScale(self:Scale())`. The header's list of restyle triggers names Register. |
| `UI/ReplayWindow.lua` | **B22:** `MD:OpenReplay` returns `true` when it opened and `false` on every refusal (not loaded, combat, no recording, could not build; the `run N` form answers what `OpenRunPlay` did); `MD:OpenRunPlay` returns `true` / `false` too. A local `OpenPull(spec)` is the window's own re-open (a run crossing into its next pull, `RunSeek` from a drag or the timeline, a run-strip click, the next pull following on its own, `RebuildSuggested`): its combat refusal prints **once per combat** (`refusedInCombat`, cleared by the next successful open and by the existing `PLAYER_REGEN_DISABLED` guard frame -- no new event registered); a refusal asked for by hand (`/md replay`, Review's Play) still prints every time. On a refusal the run-mode `OnUpdate` and `RunSeek` put the run clock back where it was, pause and paint; the next-pull path only resumes when the open succeeded. `if not rp` now comes before `rp.right` is read. **B21:** `OpenReplay` sets the scrubber's range and value only outside run mode; `OpenRunPlay` sets the run's range once (under `settingValue`). A run-strip block clicked in run mode seeks the run clock to that pull (`RunTimeline.PullSeg(...).from`) instead of opening the pull under the old run time. An open by hand (anything but `OpenPull`) leaves run mode -- what the comment at that line always said -- and `run N` asked for by hand while a run plays starts that run afresh. **B23:** every icon of a unit frame (Swiftmend, defensive, incoming cast, the three HoTs, the debuffs) hooks `OnMouseDown` (press), `OnEnter` (the frame becomes the mouseover) and `OnLeave` (the mouseover cleared unless `f:IsMouseOver()`, i.e. the pointer went back onto the frame's body). |
| `tools/wincheck.lua` | +2 (below): in section 6 and a new block before section 8. |
| `tools/replayui.lua` | +5 (below): a new block after the v0.14.0 run tests, on a run of two copies of the fixture's pull (`runT0` 10 and 76.5, run 420 s, gap health and `stats.wall` so the strip paints). |
| `tools/practiceui.lua` | +2 (below), a practice session of its own (seed 8) after "entering combat ends practice" (which is now followed by `PLAYER_REGEN_ENABLED`). |
| `tools/practiceforever.lua` | +2 (below), the same on Forever: a session of its own (seed 9) with `1` bound to Rejuvenation, at the end of the file. |

## Tests first (the parent's code, the new tests)

Run with `UI/Windows_Forever.lua` and `UI/ReplayWindow.lua` checked out from `4702b5c` and this
branch's tests.

`tools/wincheck.lua` (rc 1):

```
T51: a scale change converts a saved place whose window is not registered yet  FAIL - registered=false 100.00,700.00
T51: a frame registered at 0.8 has its 1-px edge snapped at 0.8                FAIL - 1.00 -> 1.00 want 1.25
53 ok, 2 failed
```

After: `125.00,875.00` and `1.00 -> 1.25 want 1.25`, 55 ok.

`tools/replayui.lua` (rc 1):

```
T51: after a pull crossing the scrubber's max is the run's length FAIL - crossed=true max=26.5 run=420
T51: a scrubber drag to 300 s lands at 300 s of the run FAIL - 26.5 s
T51: a run-strip click in run mode moves the run clock to that pull FAIL - t=81.5 seg=pull k=2 pull=1
T51: combat at a pull boundary prints one line in 120 frames and pauses FAIL - 102 lines, playing=true
T51: a fight opened by hand after a run plays on its own clock and range FAIL - run=true max=26.5 dur=26.5
98 ok, 5 failed
```

After: `max=420 run=420`, `300.0 s`, `t=10.0 seg=pull k=1 pull=1`, `1 lines, playing=false`,
`run=false max=26.5 dur=26.5`; 103 ok.

`tools/practiceui.lua` (rc 1):

```
T51: a key with the pointer on the Swiftmend icon heals that frame FAIL - casts 0 -> 0
T51: after leaving an icon outward a key reports No target FAIL - hover=1 hint=hover a frame and press a binding   |cff888888space pauses, End keeps it|r
50 ok, 2 failed
```

`tools/practiceforever.lua` (rc 1):

```
T51: a key with the pointer on the Swiftmend icon heals that frame  FAIL - casts 0 -> 0
T51: after leaving an icon outward a key reports No target          FAIL - hover=1 casts 0/0/1 hint=hover a frame and press a binding   |cff888888space pauses, End keeps it|r
25 ok, 2 failed
```

After: the key on the Swiftmend icon casts on unit 1; after leaving a HoT icon outward the hover is
nil, nothing is cast and the hint reads `No target`; 52 and 27 ok.

How the pointer is modelled: the stub's `S.mouseFocus` (P1) is where the pointer is and
`IsMouseOver` answers from it; the suites fire what the client fires -- moving from a frame onto its
icon, the frame's `OnLeave` then the icon's `OnEnter`; leaving the icon outward, the icon's `OnLeave`
only. The scrubber drag uses P1's clamping `SetValue`: the value is set to 300, clamped to the range
the window gave it, and `OnValueChanged` is handed what the slider holds.

## Suites (exit codes checked; the loop in docs/TOOLS.md section 1)

Before: this branch's base `4702b5c`. After: this branch. Every suite rc 0 after.

| suite | before (4702b5c) | after |
|---|---|---|
| `wincheck` | 53 | **55** |
| `replayui` | 98 | **103** |
| `practiceui` | 50 | **52** |
| `practiceforever` | 25 | **27** |
| every other suite | simcheck 13, reccheck 63, replaycheck 82, runcheck 81, reviewui 46, navui 35, dashui 63, regencheck 27, simwindow 8, solvercheck 84, restcheck 51, timeline 27, spelltip 48, costcheck 3, practice 81, migrate 7, probecheck 87, forevercheck 16, modulecheck 14, kitcheck 7, recordcheck 29, scenariocheck 14, gatecheck 9, replayforever 15, reviewforever 13, coachforever 20, bindscheck 6, parsecheck 15, bookcheck 21, tipcheck 37, clockcheck 23, spellsui 48, measurecheck 30, releasecheck 16, importcheck 20, themecheck 23, tabscheck 24, adaptercheck 22 / 15, corecheck 10 / 8, svcheck 6 / 1, consolecheck 17 / 1 | all equal, all rc 0 |
| `apicheck.py` / `--selftest` | 0 findings / 10 of 10 | same |
| `textcheck.py` / `--selftest` | 0 findings / 2 of 2 | same |
| `refcheck.py --selftest` | 2 of 2 | same |

`luac -p` passes on every changed `.lua`.

## TBC

Yes, as the plan says: `UI/ReplayWindow.lua` is shared, and B21-B23 are TBC-visible fixes (the
window did the wrong thing, not a different thing), so no DECISIONS entry. What a TBC user sees
differently:

- a run played with `/md replay run N` keeps the run on its scrubber across every pull, and a drag
  goes where it is dropped;
- combat during a run pauses it at the next pull with one chat line (asked for by hand, the refusal
  still prints each time);
- in practice, the icons on a frame no longer drop or keep the key's target wrongly;
- the two run-mode repairs listed under Deviations.

The TBC suites that cover the shared window (`replayui`, `practiceui`, `reviewui`) and every other
TBC suite pass; `reviewui` (46) is unchanged. `UI/Windows_Forever.lua` is Forever-only by TOC.

## Deviations

1. **Two more run-mode repairs in `UI/ReplayWindow.lua`, with one assertion each in `replayui`
   (+5 there, the plan said +3).** Keeping the scrubber on the run's range in run mode (B21) would
   have made an older bug worse: `runMode` was never turned off except by practice, so after a run
   had been played in the session `/md replay 3` opened fight 3 on the old run's clock -- and with
   B21's fix, on the run's scrubber range too. The line's own comment said "opening a single pull by
   hand leaves run mode"; it now does (any open but the window's own `OpenPull`), and `run N` asked
   for by hand during a run starts that run afresh instead of opening its first pull on the old
   run's clock. The run strip's block, clicked in run mode, opened its pull under the old run time,
   so the next frame of play re-opened the pull the run clock was in; it now seeks the run clock to
   that pull. Neither is a review item; both are in the code B21 names (the strip click at
   `ReplayWindow.lua:1435`).
2. **B23 is tested in both practice suites (+2 each; the plan's "+2" is read per suite).** The
   "leave outward" case uses a HoT icon: on the parent the Swiftmend icon never set the hover, so
   leaving it outward could not show the stale target, while the HoT icons did set it on enter.
3. `MD:OpenReplay`'s combat refusal: once per combat for the window's own re-opens only (the plan's
   "the refusal prints once per combat"); a command typed by hand still prints each time, since a
   silent `/md replay` is worse than a repeated line. `PLAYER_REGEN_DISABLED` on the practice guard
   frame that already existed resets the once-per-combat flag; P13 owns that frame's conversion in
   wave 5 and should carry the line.

## Integrator lines

**docs/TOOLS.md section 1** (append to each row's text):

- `replayui.lua`: ` Since **T51** (103): a run of two pulls -- after crossing into the second the scrubber's range is still the run's, a drag to 300 s lands at 300 s of the run, a run-strip click moves the run clock to that pull, combat at a pull boundary prints one line in 120 frames and pauses, a fight opened by hand after a run plays on its own clock and range (B21, B22)`
- `practiceui.lua`: ` Since **T51** (52): a key with the pointer on a frame's Swiftmend icon casts on that frame; after leaving a HoT icon outward a key reports No target (B23)`
- `practiceforever.lua`: ` Since **T51** (27): the same two on Forever (B23)`
- `wincheck.lua`: replace `(T32-T34, T42, forever, 53;` with `(T32-T34, T42, T51, forever, 55;` and append ` Since **T51**: a scale change converts a saved place whose window is not registered yet; a frame registered at 0.8 has its 1-px edge snapped at 0.8 (B17, B18)`

**CLAUDE.md**, the `UI/Windows_Forever.lua` row, append:

> **T51 (P7):** a scale change converts every saved place in `db.ui.win`, registered this session
> or not, from the old scale read before the new one is written; `Register` re-snaps the pixel edges
> after applying the window scale (B17, B18).

**CLAUDE.md**, the `UI/ReplayWindow.lua` row, append:

> **T51 (P7):** `MD:OpenReplay` / `MD:OpenRunPlay` answer whether they opened; the window's own
> re-opens (`OpenPull`) keep a run on its clock and its scrubber range, pause on a combat refusal
> and say it once per combat; an open by hand leaves run mode; a run-strip click in run mode seeks
> the run clock; every icon on a unit frame takes the practice hover on enter and gives it up on
> leave unless the frame is still under the pointer (B21, B22, B23).

**docs/HISTORY.md / docs/TESTING.md / docs/DECISIONS.md**: nothing required (no DECISIONS entry: the
plan rules these are the window doing the wrong thing). For TESTING.md, if the integrator keeps a
per-wave in-game list: "`/md replay run N` on TBC: drag the scrubber after the second pull; enter
combat while it plays -- one line, paused. Practice: hover a frame's Swiftmend icon and press a
bound key. Forever: change the window scale in Settings before ever opening a replay, then
`/st replay` -- it opens where it was."

**TOCs**: no change (no file added or moved).

**tools/data/expected-counts.json** (when it exists): `wincheck` 55, `replayui` 103, `practiceui` 52,
`practiceforever` 27.
