# T18 — Practice on Forever: the session, the panel, the window

Status: **open**, after T17. M4 (`docs/ROADMAP-FOREVER.md` M4, "T18 session and panel under the
adapter").

## Goal

With the Practice module on, the Forever window's **Simulate -> Practice** view is the TBC practice
panel: build a fight, press Start, heal it in the replay window's practice mode with your own
bindings, and when it ends it reopens as an ordinary replay and appears in Review -- all priced from
the Forever kit (T15). `Engine/Practice.lua`, `UI/PracticePanel.lua` and `UI/BindingsWindow.lua`
stay one file each for both lines, their client calls behind the adapter. For the author: practice
is the one feature that works at level 10-20 without a group.

## Facts

- `Engine/Practice.lua` calls the client directly: `UnitName` (94, 323), `GetMacroInfo` (235-236,
  428-429), `GetSpecialization` (277), `GetRealmName` (323), `GetActionInfo` (419-420),
  `GetNumBindings` / `GetBinding` / `GetBindingAction` (443-457), `UnitPowerMax` (637); and reads
  other add-ons' globals `_G.CellCharacterDB` (273), `_G.Clique`, `_G.CliqueDB3` / `CliqueDB`
  (316-323), and action-button frames by name (`_G[name]`, 388). Add-on globals and frames are not
  client calls; the rest are (plan §3.2). Which of the client names exist on Forever:
  `GetBinding`, `GetActionInfo`, `GetMacroInfo` survive (plan §1.3); `GetNumBindings`,
  `GetBindingAction`, `GetSpecialization`, `GetRealmName` -- `python3 tools/apicheck.py` answers
  against the 69893 baseline once the file is in a Forever TOC.
- The panel (`UI/PracticePanel.lua`: `MD.DashboardParts.CreatePractice(parent, width)`) and the
  bindings window (`UI/BindingsWindow.lua`, `/md binds`) touch the client through
  `IsAltKeyDown` / `IsControlKeyDown` / `IsShiftKeyDown` (T16a's bindings) plus the toolkit.
- Practice runs `Engine/SimModel.lua`'s loop in a coroutine paced to its own clock, writes a
  practice stream (`rec.practice = true`, the v2 event format) into `MD.cdb.practice` (newest 8),
  addressed `p1`; `rec.practice` relaxes the death and foreign-healing gates (`CLAUDE.md`
  Practice row). A practice stream is v2-shaped, so the TBC `Validate` path judges it -- which on
  Forever must work with the Forever kit and without `MD.Calibration` (guarded already:
  `MD.Calibration and ...`).
- The replay window's practice mode (`MD:OpenPractice`, `MD:StopPractice`, `MD:PracticePress`) is in
  `UI/ReplayWindow.lua`, loaded by the Replay module (T16a).
- The TBC window hosts Practice as `simulate` -> `practice` (`UI/Dashboard.lua` 217-218, 246-250);
  the TBC commands `/md practice [start]`, `/md binds` (`Core_TBC.lua` 339-350).
- TBC suites: `tools/practice.lua` 74, `tools/practiceui.lua` 49.

## Files

| file | change | role |
|---|---|---|
| `Client/API.lua` / `API_Forever.lua` / `API_TBC.lua` | bindings for the practice client calls that exist on each client (`BindingCount`, `Binding`, `BindingAction`, `ActionInfo`, `MacroInfo`, `Specialization`, `RealmName` exists already) -- a name absent on a client is simply not bound there, and the caller treats it as absent | bindings |
| `Engine/Practice.lua`, `UI/PracticePanel.lua`, `UI/BindingsWindow.lua` | every client call through `MD.API` (multi-return calls like `GetBinding(i)` kept whole: `{ MD.API.Binding(i) }` is fine -- `MD.API.Call` keeps every return); nothing else | shared files |
| `UI/Dashboard_Forever.lua` | a `simulate` group (`Simulate`) with one view `practice` (`Practice`), after Reports: `MD.DashboardParts.CreatePractice(content, 912)` when it exists (Practice module), else a placeholder `Practice needs the Practice module - Settings -> Modules`, replaced on `MODULE_LOADED` as T16b does | the window |
| `Modules/SpellTuner_Practice/Commands_Forever.lua` (new) | `/st practice [start]`, `/st binds` with TBC's syntax and help | commands |
| `Modules/SpellTuner_Practice/*.toc` | `Module.lua`, `Engine\Practice.lua`, `UI\PracticePanel.lua`, `UI\BindingsWindow.lua`, `Commands_Forever.lua`, `Ready.lua` | TOCs |
| `tools/adaptercheck.lua` | the new binding names | suite |
| `tools/practiceforever.lua` (new, forever) | the suite below | suite |

## Rules

- No client call outside `Client/` (apicheck 0, rule 8). The TBC line unchanged: practice 74,
  practiceui 49, and the rest of the sixteen.
- A key press a practice session does not bind propagates (TBC behaviour); the practice window never
  opens in combat.
- ASCII, no bare `|`. No new global; no library; the multi-return trap.
- Tests first: practiceforever written and failing first.
- **Git:** no `git add`, `stash`, `checkout -- <path>`, `reset`, commit. Do not edit `CLAUDE.md` or
  any `docs/` file except this Report.

## Acceptance

1. `bash tools/run.sh tools/practiceforever.lua` ends `8 ok, 0 failed`. Names, verbatim:
   1. "the Simulate group has a Practice view, a placeholder until the module is on"
   2. "the practice panel builds a fight from the Forever kit's spells"
   3. "a session plays against a fake clock with the Forever kit and records a practice stream"
   4. "the recording replays to the health the player saw and every gate passes"
   5. "a key bound to a spell casts it; an unbound key propagates"
   6. "ending the session reopens it as a replay and lists it in Review"
   7. "/st practice and /st binds exist only with the Practice module on"
   8. "every string the panel and the bindings window paint is ASCII with no bare pipe"
2. TBC: practice 74, practiceui 49, and the rest of the sixteen; the Forever suites at their counts.
3. `python3 tools/apicheck.py` 0 findings; `--selftest` as before. Paste the first apicheck run
   listing the practice files' client calls, and say for each name whether the 69893 baseline has it.
4. `luac -p` clean.
5. Paste into the Report: the failing run; practiceforever in full; every other tail; apicheck;
   luac; `git status --short`.

## Out of scope

- The imports' Forever formats (T19). The damage model, the session rules, the bindings' defaults.
- `CLAUDE.md`, every `docs/` file except this Report. Commits.

## Report

(implementer)
