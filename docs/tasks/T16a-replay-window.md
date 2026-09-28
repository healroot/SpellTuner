# T16a — the replay window plays a Forever recording

Status: **open**, after T14. M3 (`docs/ROADMAP-FOREVER.md` M3, "T16 Review tab and replay window
under the adapter"), split by the lead: T16a the window and its commands, T16b the Review tab.

## Goal

With the Replay module on, `/st replay [n] [force]` opens a v3 recording in the same window the TBC
line has -- the actual column (the recorded casts through the engine), the suggested column (the
plan the coach finds, filled in when the frame-sliced search finishes), the scrubber, the speeds --
with the reconstructed health drawn as the left column's ticks and one line saying what is
reconstructed and what is estimated. `/st validate [n]` prints the gates and `/st coach [n] [force]`
coaches. `UI/ReplayWindow.lua` stays one file for both lines: its client calls move behind the
adapter, and the TBC window behaves exactly as before. For the author's first Forever replays (the
M3 exit: "opens in the replay window with the suggested column").

## Facts

- The window (`UI/ReplayWindow.lua`, 1906 lines) calls the client directly: `GetSpellInfo` (143, 537,
  549), `GetSpellTexture` (545), `InCombatLockdown`, `UnitAffectingCombat`, `UnitName`,
  `IsShiftKeyDown` / `IsAltKeyDown` / `IsControlKeyDown`, plus the toolkit (`CreateFrame`,
  `UIParent`, `RAID_CLASS_COLORS`, `STANDARD_TEXT_FONT`, `UISpecialFrames`, `GetTime`,
  `debugprofilestop`, `date`) which the adapter rule allows anywhere (`FOREVER-PLAN.md` §3.2).
  `python3 tools/apicheck.py` lists every remaining client call once the file is in a Forever TOC.
- It reads `rec.hp` for the real-health ticks (1378-1381) and a max fallback (1733-1734); a v3
  stream has no `hp` -- T13d's `sc.recordedHp` and `targets[i].maxHP` / `maxEstimated` are the
  reconstruction and the (possibly estimated) max.
- It reads `MD.FightRecorder`, `MD:GetRecording` (T13 provides both on Forever), `MD.RunRecorder`
  and `MD.RunTimeline` (run mode; runs are not recorded on Forever), `MD.Practice` (M4),
  `MD.AuraList` (`Data/AuraList.lua`, pure data), `MD.Tip` (`UI/Tooltip.lua`, toolkit only),
  `MD.SimPlanner`, `MD.ReplayTrace`, `MD.SimModel`, `MD.SpellData.maxRank`, `MD.db.replay*`.
- The TBC TOC's order is the load order these files already work in: SimModel, ..., Intuition,
  Foresight, SimSolver, SimPlanner, RunTimeline, ReplayTrace, then UI Style, Tooltip, ...,
  ReplayWindow (`SpellTuner_TBC.toc`). `UI/Style.lua` and `UI/Dashboard_Rows.lua` are already in the
  Forever core TOC.
- The TBC commands (`Core_TBC.lua` 292-295 help lines): `/md replay [n] [force]`, `/md coach`,
  `/md validate`. The kernel's `MD:AddCommand` (T1b) registers a command from any file.
- A v3 recording's party maxima may be estimated (T13d; planner ruling 1: every percentage or danger line drawn from it says "estimated"; the deficit is exact); the window must not present an
  estimated bar as a measured one.
- The TBC replay window's suites: `tools/replayui.lua` 98, `tools/reviewui.lua` 44,
  `tools/practiceui.lua` 49 (all tbc).

## Files

| file | change | role |
|---|---|---|
| `Client/API.lua` (shared `Bind`) | `IsShiftKeyDown`, `IsAltKeyDown`, `IsControlKeyDown` (same global on both clients) | bindings |
| `Client/API_TBC.lua` | `SpellTexture = "GetSpellTexture"` (Forever's is T7's `C_Spell.GetSpellTexture`) | binding |
| `UI/ReplayWindow.lua` | every client call through `MD.API` (the icon fallback that read `GetSpellInfo`'s third return reads `select(3, MD.API.SpellName(id))`, which is nil on Forever -- fine); `hp = rec.hp or (rec.v == 3 and SM.RecordedHp and SM.RecordedHp(rec)) or {}` at both sites; every `MD.RunRecorder` / `MD.Practice` / `MD.RunTimeline` use guarded for nil; when `rec.v == 3` one grey line under the header: `health reconstructed from UNIT_COMBAT; party max estimated` (the second half only when a target's max is estimated) | the window |
| `Modules/SpellTuner_Replay/Scenario_Forever.lua` | `SM.RecordedHp(rec, kit)`: T13d's reconstruction in v2's `rec.hp` shape `{t, hp = {[i] = {...}}, max = {[i] = {...}}}` | helper |
| `Modules/SpellTuner_Replay/Commands_Forever.lua` (new) | `MD:AddCommand("replay", ...)`, `"coach"`, `"validate"` with TBC's syntax and help text; the replay settings' defaults (`replaySpeed = 1`, `replayTicks = true`, `replayNextPull = true`, `replayAutoCoach = true`, the `sim*` values the engine reads with fallbacks) set on `MD.db` at module load when absent | commands |
| `Modules/SpellTuner_Replay/*.toc` | add, in TBC's relative order: `Data\AuraList.lua`, `Engine\Intuition.lua`, `Engine\Foresight.lua`, `Engine\SimSolver.lua`, `Engine\SimPlanner.lua`, `Engine\RunTimeline.lua`, `Engine\ReplayTrace.lua`, `UI\Tooltip.lua`, `UI\ReplayWindow.lua`, `Commands_Forever.lua` -- before `Ready.lua` | TOCs |
| `tools/adaptercheck.lua` | the new binding names (T12 precedent) | suite |
| `tools/replayforever.lua` (new, forever) | the suite below | suite |

## Rules

- No client call outside `Client/` in any Forever-TOC file (apicheck 0, rule 8 included) -- which now
  covers every shared file the Replay module lists.
- The TBC line must not change behaviour: replayui 98, reviewui 44, practiceui 49, and every other
  TBC suite at its count. A behaviour change on TBC is a question, not an edit.
- Nothing in the window reads a party member's max as measured when `maxEstimated` says it is not.
- ASCII, no bare `|` in anything painted or printed. **Lead, 2026-09-28 (T14 review):** gate texts and target names carry player and spell names as the client gave them (an EU name can be non-ASCII); escape every such string at paint time, and the ASCII assertion's fixture includes a target named with a non-ASCII byte and a `|`. No new global; no library; the multi-return trap
  (`MD.API.SpellName(id) or id` is fine; `a and MD.API.X() or b` is not).
- Tests first: replayforever written and failing first.
- **Git:** no `git add`, `stash`, `checkout -- <path>`, `reset`, commit. Do not edit `CLAUDE.md` or
  any `docs/` file except this Report.

## Acceptance

1. `bash tools/run.sh tools/replayforever.lua` ends `10 ok, 0 failed`, on two `tools/foreverfixture.lua`
   streams in `MD.cdb.recordings`. Names, verbatim:
   1. "the replay commands exist only with the Replay module on"
   2. "/st replay opens a v3 recording with one row per tracked target"
   3. "the actual column plays to the end and its bars follow the reconstructed health"
   4. "the reconstructed health is drawn as the left column's ticks"
   5. "the window says the health is reconstructed and a party max is estimated"
   6. "the suggested column fills in when the coach's search finishes"
   7. "seeking gives the same picture as playing to that moment"
   8. "/st validate prints the Forever gates and /st coach refuses a failing fight unless forced"
   9. "every string the window paints is ASCII with no bare pipe"
   10. "the window will not open in combat"
2. TBC: replayui 98, reviewui 44, practiceui 49, and the rest of the sixteen at their counts; the
   Forever suites at theirs; adaptercheck at its count.
3. `python3 tools/apicheck.py` 0 findings; `--selftest` as after T13a/T13c.
4. `luac -p` clean on every Lua file touched.
5. Paste into the Report: the failing run; replayforever in full; the first apicheck run listing the
   window's client calls before the move; every other tail; apicheck; luac; `git status --short`.

## Out of scope

- The Review tab (T16b); runs and run mode on Forever (not recorded yet -- guarded, not ported);
  practice mode in the window (T18); the Cell layout table itself.
- `CLAUDE.md`, every `docs/` file except this Report. Commits.

## Report

(implementer)
