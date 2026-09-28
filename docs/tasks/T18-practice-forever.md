# T18 — Practice on Forever: the session, the panel, the window

Status: **accepted** 2026-09-28 (lead review at the end), after T17. M4 (`docs/ROADMAP-FOREVER.md` M4, "T18 session and panel under the
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

### Files touched

- `Client/API_Forever.lua`: added `BindingCount` (`GetNumBindings`), `Binding` (`GetBinding`),
  `BindingAction` (`GetBindingAction`), `ActionInfo` (`GetActionInfo`), `MacroInfo` (`GetMacroInfo`)
  -- all present on the 69893 baseline (confirmed below). `GetSpecialization` deliberately NOT
  bound here (absent on Forever's baseline); `RealmName` needed no change (already shared in
  `Client/API.lua`).
- `Client/API_TBC.lua`: the same five bindings plus `Specialization` (`GetSpecialization`),
  mirroring `RealZoneText`'s existing per-flavour-duplicate pattern rather than merging into the
  shared `Client/API.lua` list.
- `Engine/Practice.lua`: every raw client call now goes through `MD.API` --
  `MD.API.UnitName` (`PR.DefaultSetup`, `CliqueBinds`), `MD.API.MacroInfo` (`MacroBody`, rewritten
  to drop its own `pcall` since `MD.API.Call` already wraps one), `MD.API.Specialization`
  (`CellList`), `MD.API.RealmName` (`CliqueBinds`), `MD.API.ActionInfo` (`PR.SlotSpell`, rewritten
  to use the shared `MacroBody` helper instead of its own second `pcall`), `MD.API.BindingCount` /
  `MD.API.Binding` / `MD.API.BindingAction` (`PR.ImportKeybinds`, `{ MD.API.Binding(i) }` kept whole
  per the task's own note), `MD.API.UnitPowerMax` (`BuildScenario`). Also added `PR.EnsureKit()`
  (see "Found along the way" below).
- `UI/BindingsWindow.lua`: the modifier-key reads in `Take()` now go through `MD.API.IsAltKeyDown`
  / `MD.API.IsControlKeyDown` / `MD.API.IsShiftKeyDown` (already shared bindings); `SpellItems()`
  now calls `PR.EnsureKit()` first.
- `UI/PracticePanel.lua`: `BindLines()` now calls `PR.EnsureKit()` first. No client calls of its
  own (confirmed by grep before editing).
- `UI/Dashboard_Forever.lua`: added a `simulate` group with one view `practice`, after `reports`;
  `BuildPracticePlaceholder` / `BuildPracticePane` follow the exact placeholder-then-module shape
  `reports -> review` already uses (T16b); a `MODULE_LOADED` handler for `SpellTuner_Practice`
  swaps the placeholder for `MD.DashboardParts.CreatePractice(content, 912)` the same way the
  Review one does for `SpellTuner_Replay`. No window-size change needed: Practice depends on
  Replay (`Core_Forever.lua`'s own `MD:DeclareModule`), so the window is already grown to
  `GROWN_WIDTH`/`GROWN_HEIGHT` by the time a Practice pane can exist.
- `Modules/SpellTuner_Practice/Commands_Forever.lua` (new): `/st practice [start]`, `/st binds`
  and `/st bindings`, TBC's own syntax/help text reimplemented (Core_TBC.lua could not be pulled
  from -- TBC-only, not on this TOC).
- `Modules/SpellTuner_Practice/SpellTuner_Practice.toc` and `..._Mainline.toc`: filled in from the
  placeholder (`Module.lua` / `Ready.lua` only) to list `Engine\Practice.lua`, `UI\PracticePanel.lua`,
  `UI\BindingsWindow.lua`, `Commands_Forever.lua`, matching `SpellTuner_Replay`'s TOC shape exactly
  (both `.toc` files identical, as the Replay module's own pair already are).
- `tools/adaptercheck.lua`: added the five bindings to `FOREVER_ONLY_NAMES` and the six (plus
  `Specialization`) to `TBC_ONLY_NAMES`, duplicating the existing `RealZoneText` pattern.
- `tools/practiceforever.lua` (new): the 8-assertion suite below.

### A bug found along the way (in scope, fixed, not just reported)

`MD.SpellData.maxRank` / `.known` / `.families` / `.all` are built lazily on Forever -- only the
first time something calls `MD.RankMath:SpellKit()` (`Modules/SpellTuner_Replay/Kit_Forever.lua`'s
`SpellKit()` is what actually assigns `SD.spells/families/known/all/maxRank/skipped`; nothing else
does). TBC's own `Data/SpellData.lua` guarantees these are always tables (`SD.maxRank = {}` at file
scope, line 270, populated later by a scan but never nil). `UI/PracticePanel.lua`'s `BindLines()`
and `UI/BindingsWindow.lua`'s `SpellItems()` -- both **shared** files -- index `SD.families` /
`SD.known` / `SD.maxRank` the moment the Practice pane or the bindings window is first shown, with
no dependency on a session ever having started (which is the only other thing that calls
`SpellKit()`). Reproduced with the literal sequence a real player can hit: open Simulate ->
Practice (placeholder), turn the Practice module on from Settings -> Modules, return to Simulate ->
Practice -- `attempt to index field 'maxRank' (a nil value)` inside `PR.SpellFor`, caught by
`MD.API.Call`'s own `pcall` around `LoadAddOn` and reported to the player as
"Practice: on, could not load (unknown)" with the whole module silently dead.

Fixed with `PR.EnsureKit()` in `Engine/Practice.lua` (a new function, not a rewrite of an existing
one): a no-op guarded on `not SD.maxRank`, which is **never true on TBC** (so this changes nothing
there), calling `MD.RankMath:SpellKit({ live = true })` once on Forever the first time something
needs the tables it builds. Called at the top of `BindLines()` and `SpellItems()`. This is the one
place I stepped slightly outside the Files table (`Kit_Forever.lua` itself is untouched; the fix
lives entirely in the task's own three shared files) because without it the task's own acceptance
tests 2/3 cannot pass and the feature is broken for every real Forever player on first use. Flagging
per the task's own instruction rather than silently shipping a workaround: happy to revert this
part specifically if the lead would rather fix `Kit_Forever.lua` itself (eagerly build the index at
module load) or judges this differently.

### Tests first

`tools/practiceforever.lua` was written complete, then run once before any of the `Engine/Practice.lua`
adapter edits existed -- it failed immediately with raw-global errors (`GetSpecialization`/`GetMacroInfo`
etc. still present, so the file loaded, but `PR.EnsureKit` did not exist yet and the bindings/adapter
work was incomplete). After the adapter/Files edits landed, the very first real run hit the
`SD.maxRank` nil-index crash above (not a pipe/ASCII nit) -- confirming the suite caught a real bug,
not just checking the happy path. Failing run (first clean run after the adapter edits, before
`PR.EnsureKit`):

```
the Simulate group has a Practice view, a placeholder until the module is on                    ok - group=simulate view=practice
.../Engine/Practice.lua:167: attempt to index field 'maxRank' (a nil value)
stack traceback:
	.../Engine/Practice.lua:167: in function 'SpellFor'
	.../UI/PracticePanel.lua:272: in function 'BindLines'
	.../UI/PracticePanel.lua:324: in function 'Render'
	.../UI/PracticePanel.lua:346: in function 'OnShow'
	.../tools/wowstub.lua:345: in function 'Show'
	.../tools/practiceforever.lua:98: in main chunk
	[C]: ?
|cff9966ffSpellTuner:|r Recorder: loaded
|cff9966ffSpellTuner:|r Replay: loaded
|cff9966ffSpellTuner:|r Practice: on, could not load (unknown)
/st practice and /st binds exist only with the Practice module on                               ok - beforeOpenNil=true afterOpen=function: 0x602b77a998c0
```

After `PR.EnsureKit()`, two more iterations fixed test assertion bugs in the suite itself (never in
an assertion's *pass condition* -- CLAUDE.md's "never change an assertion to make it pass"): the
ASCII scan's `NonAscii`/`Pipes` helpers needed the same accepted exceptions other suites already
use (the newline inside `BindLines`' multi-line text, the client's own `|n` escape, and
`UI/Style.lua`'s "x" close glyph via the established `CLOSE_GLYPH` constant from
`tools/modulecheck.lua`/`tools/spellsui.lua`) -- none of those loosen what counts as a pass, they
fix the scan to match the codebase's own established, already-reviewed conventions.

### practiceforever.lua, in full (final, passing run)

```
the Simulate group has a Practice view, a placeholder until the module is on                    ok - group=simulate view=practice
|cff9966ffSpellTuner:|r Recorder: loaded
|cff9966ffSpellTuner:|r Replay: loaded
|cff9966ffSpellTuner:|r Practice: loaded
/st practice and /st binds exist only with the Practice module on                               ok - beforeOpenNil=true afterOpen=function: 0x633db8f9ad50
the practice panel builds a fight from the Forever kit's spells                                 ok - rejID=1058 maxRank=1058
a session plays against a fake clock with the Forever kit and records a practice stream         ok - state=done rec=true ownCasts=2 errors=
the recording replays to the health the player saw and every gate passes                        ok - gates:  worst hp diff 0.000
a key bound to a spell casts it; an unbound key propagates                                      ok - hover=1 castsBound=1 castsUnbound=1
|cff9966ffSpellTuner:|r practice: 0:00.8 played, 1 casts, 40 mana, 0 dead - kept as |cffffff00p1|r (Reports -> Review -> Practice, or /md replay p1).
ending the session reopens it as a replay and lists it in Review                                ok - reopened=true listed=true
every string the panel and the bindings window paint is ASCII with no bare pipe                 ok

8 ok, 0 failed
```

### Every other suite's tail (docs/TOOLS.md §1 loop, all baselines matched exactly)

```
simcheck      |cff9966ffSpellTuner:|r   measured mean 1.3%  max 2.8% at 23.0s   (+ 23.1 mana/s energize) -> PASS
reccheck      54 ok, 0 failed
replaycheck   80 ok, 0 failed
replayui      98 ok, 0 failed
runcheck      78 ok, 0 failed
reviewui      44 ok, 0 failed
navui         25 ok, 0 failed
dashui        56 ok, 0 failed
regencheck    27 ok, 0 failed
simwindow     8 ok, 0 failed
solvercheck   70 ok, 0 failed
timeline      27 ok, 0 failed
spelltip      48 ok, 0 failed
practice      74 ok, 0 failed
practiceui    49 ok, 0 failed
migrate       7 ok, 0 failed
probecheck    73 ok, 0 failed
forevercheck  13 ok, 0 failed
modulecheck   14 ok, 0 failed
kitcheck      7 ok, 0 failed
recordcheck   14 ok, 0 failed
scenariocheck 9 ok, 0 failed
gatecheck     8 ok, 0 failed
replayforever 10 ok, 0 failed
reviewforever 8 ok, 0 failed
coachforever  8 ok, 0 failed
parsecheck    11 ok, 0 failed
bookcheck     15 ok, 0 failed
tipcheck      14 ok, 0 failed
clockcheck    15 ok, 0 failed
spellsui      15 ok, 0 failed
measurecheck  18 ok, 0 failed
practiceforever 8 ok, 0 failed
adaptercheck/forever 19 ok, 0 failed
adaptercheck/tbc 15 ok, 0 failed
corecheck/forever 10 ok, 0 failed
corecheck/tbc 8 ok, 0 failed
svcheck/forever 6 ok, 0 failed
svcheck/tbc   1 ok, 0 failed
consolecheck/forever 11 ok, 0 failed
consolecheck/tbc 1 ok, 0 failed
apicheck: 8 Forever TOCs, 44 files, 43 distinct globals, 0 findings (baseline 69893)
selftest: 10 of 10 findings as expected
selftest: ok
```

(`selftest: ok` is `tools/refcheck.py --selftest`, listed in the docs/TOOLS.md §1 loop although not
named in this task's own baseline list; included for completeness, unaffected either way.)

### apicheck: the practice files' client calls, and the baseline

First `python3 tools/apicheck.py --report` after all edits landed (0 findings; excerpt for the
files this task touched -- note none of the `MD.API.*` calls appear here at all, by construction:
`apicheck` tracks raw Lua *globals* (`luac -l`'s GETGLOBAL/SETGLOBAL), and `MD.API.Foo` is a table
index, never a global, which is exactly what "every client call goes through `Client/API.lua`"
buys):

```
Engine/Practice.lua:
  _G lua
  coroutine lua
  ipairs lua
  math lua
  pairs lua
  pcall lua
  setmetatable lua
  table lua
  time lua-extension
  tonumber lua
  tostring lua
  type lua
UI/BindingsWindow.lua:
  CreateFrame toolkit
  UISpecialFrames toolkit
  ipairs lua
  math lua
  string lua
  table lua
  tinsert lua-extension
  tonumber lua
UI/PracticePanel.lua:
  CreateFrame toolkit
  ipairs lua
  math lua
  string lua
  strtrim lua-extension
  table lua
  time lua-extension
  tonumber lua
  tostring lua
Modules/SpellTuner_Practice/Module.lua:
  _G lua
  setmetatable lua
  type lua
Modules/SpellTuner_Practice/Ready.lua:
  _G lua
Modules/SpellTuner_Practice/Commands_Forever.lua: (no globals at all -- only calls MD:AddCommand and local closures)
apicheck: 8 Forever TOCs, 44 files, 43 distinct globals, 0 findings (baseline 69893)
```

The raw client names the Facts section named (before this task's edits), checked against
`tools/data/forever_api.json` (the 69893 baseline), matching the lead's own check exactly:

| name | in 69893 baseline |
|---|---|
| `GetNumBindings` | yes |
| `GetBinding` | yes |
| `GetBindingAction` | yes |
| `GetActionInfo` | yes |
| `GetMacroInfo` | yes |
| `GetSpecialization` | **no** |
| `GetRealmName` | yes |
| `UnitName` | yes |
| `UnitPowerMax` | yes |

`python3 tools/apicheck.py --selftest`: `selftest: 10 of 10 findings as expected` (unchanged from
baseline).

### luac -p, every file touched

```
Client/API.lua: OK (unchanged, checked as a sanity read)
Client/API_Forever.lua: OK
Client/API_TBC.lua: OK
Engine/Practice.lua: OK
UI/BindingsWindow.lua: OK
UI/Dashboard_Forever.lua: OK
UI/PracticePanel.lua: OK
tools/adaptercheck.lua: OK
Modules/SpellTuner_Practice/Commands_Forever.lua: OK
Modules/SpellTuner_Practice/Module.lua: OK
Modules/SpellTuner_Practice/Ready.lua: OK
tools/practiceforever.lua: OK
```

### git status --short

```
 M Client/API_Forever.lua
 M Client/API_TBC.lua
 M Engine/Practice.lua
 M Modules/SpellTuner_Practice/SpellTuner_Practice.toc
 M Modules/SpellTuner_Practice/SpellTuner_Practice_Mainline.toc
 M UI/BindingsWindow.lua
 M UI/Dashboard_Forever.lua
 M UI/PracticePanel.lua
 M docs/tasks/HANDOVER.md
 M tools/adaptercheck.lua
?? Modules/SpellTuner_Practice/Commands_Forever.lua
?? tools/practiceforever.lua
```

`docs/tasks/HANDOVER.md`'s modification is the lead's own, present before this task started (per
the launch instructions' own `git status` snapshot) -- not touched here; `git diff --stat` on it
shows the same 7 insertions/4 deletions it had at the start of this session.

### Skipped / out of scope

- Nothing in the "Out of scope" list (imports' Forever formats, damage model, session rules,
  bindings defaults) was touched.
- `CLAUDE.md` and every `docs/` file except this Report were left alone.
- No `git add`/`stash`/`checkout -- <path>`/`reset`/commit was run.

### Question for the lead

None blocking -- the one judgment call (the `PR.EnsureKit()` fix, slightly outside the literal
Files table but inside the three shared files the task names, versus fixing `Kit_Forever.lua`
itself) is flagged above rather than asked, since leaving it unfixed would ship a broken feature and
the fix is a no-op on TBC by construction (verified: `practice` 74/74 and `practiceui` 49/49
unchanged).

## Lead review (2026-09-28)

Accepted. `PR.EnsureKit` (outside the literal Files, inside the task's own three files) is accepted:
the Forever spell index is built lazily by `SpellKit`, the panel read it first, and the guard
(`not SD.maxRank`) is never true on TBC. The adapter rewrites keep each call's returns as the old
`pcall` form read them (`GetMacroInfo`'s body is its third return either way). The lead reran every
suite (practiceforever 8, practice 74, practiceui 49, everything else at its baseline; apicheck 0
over 44 files, `--selftest` 10 of 10, refcheck ok) and `luac -p`.
