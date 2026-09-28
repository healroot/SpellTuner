# T13c — a module carries shared files and works in SpellTuner's namespace

Status: **accepted** 2026-09-28 (lead review below; re-issued once, the first implementer left no changes in the tree). M3 prerequisite, added by the lead 2026-09-28. Every M3/M4 task puts files into
the three LoadOnDemand siblings; today a sibling is one `Module.lua` and has no way to load a file
that lives outside its own folder or to reach `MD`.

## Goal

A sibling module's TOC can list a shared file by its path from the repository root (for example
`Engine\SimModel.lua`), and that file then loads inside the module exactly as it loads in the TBC
addon -- under the name `MD`, reading and writing SpellTuner's own namespace -- in the game (after
`release.sh` copies it into the module's folder), in the offline harness, and past `apicheck`. The
module's first file sets the namespace up; its last file tells the core it loaded, so
`MODULE_LOADED` fires only once everything in it has run. For every M3 and M4 task.

## Facts

- `FOREVER-PLAN.md` §3.1: `SpellTuner_Replay` carries "SimModel, RankMath/SpellKit-from-spellbook,
  planner, solver, ReplayTrace, replay window, coach, Review tab"; `SpellTuner_Recorder` the v3
  recorder; `SpellTuner_Practice` the session and bindings. `docs/ROADMAP-FOREVER.md` §1.1: `Engine/`
  is "pure Lua, listed by BOTH TOCs, identical bytes". Modules live under `Modules/<Name>/`
  (decided 2026-09-28, M1/T2) and `release.sh` builds each from its own TOCs' file lists
  (`release.sh` lines 177-222), copying from `Modules/<Name>/` only.
- The client never loads a file outside an addon's own folder, so a shared file must be **copied
  into** the module's package at release. This is the lead's decision on the mechanism, **confirmed by the
  planner** (`FOREVER-PLAN.md`, rulings above §2.4, item 4): an entry that does not exist under
  `Modules/<Name>/` is resolved at the repository root, and copied to the same relative path in the
  package. Only entries under `Engine/`, `Spells/`, `Data/`, `UI/` may resolve at the root.
- A LoadOnDemand addon's files receive `(addonName, addonTable)` where `addonTable` is **that
  addon's own** fresh table (the stub does the same: `chunk(addonName, {})`, `tools/wowstub.lua`
  `LoadModuleFiles`). Every shared file starts `local _, MD = ...`, so without help `MD` would be the
  module's empty table. `_G.SpellTuner` is SpellTuner's `MD` (`Core.lua` line 11).
- `Core.lua` never uses `self.` / `rawget(self` / `self ==` (lead's grep, 2026-09-28), so a proxy
  table whose `__index` and `__newindex` are `_G.SpellTuner` behaves as `MD` for every core method
  called with `:` -- the method's `self` is the proxy, and every read and write lands on SpellTuner.
  A shared file that iterates `pairs(MD)` or compares `MD ==` would break; none is known.
- Today each sibling TOC lists exactly `Module.lua` and `tools/modulecheck.lua` asserts that
  ("each sibling is a LoadOnDemand Forever addon that depends on SpellTuner").

## Files

| file | change | role |
|---|---|---|
| `Modules/<Name>/Module.lua` (all three) | sets `setmetatable(ns, { __index = _G.SpellTuner, __newindex = _G.SpellTuner })` on the addon table it is handed (only if `_G.SpellTuner` is a table), and **no longer** calls `ModuleLoaded` | the namespace |
| `Modules/<Name>/Ready.lua` (new, all three) | `local name = ...; _G.SpellTuner:ModuleLoaded(name)` (guarded as today) | the handshake, last |
| `Modules/<Name>/<Name>.toc`, `_Mainline.toc` | `Module.lua` first, `Ready.lua` last (nothing between yet); the two copies stay identical | TOCs |
| `release.sh` | a module TOC entry missing under `Modules/<Name>/` is taken from the repository root when it is under `Engine/`, `Spells/`, `Data/` or `UI/` and exists there, copied to the same relative path in the package; anything else missing is the existing error | build |
| `tools/wowstub.lua` | `LoadAddOn` resolves each entry the same way (module folder first, then the root under the same four folders) before loading it | stub |
| `tools/apicheck.py` | a module TOC's entries resolve the same way (rule 7 "a TOC entry with no file on disk" and every scan follow the resolved path); the selftest fixture gains one module TOC that lists a root file | check |
| `tools/modulecheck.lua` | the sibling-TOC assertion's last clause becomes "first entry `Module.lua`, last entry `Ready.lua`" (a deliberate edit, this task's only change to an existing assertion); two new assertions | suite |

## Rules

- No change to any file under `Engine/`, `Spells/`, `Data/`, `UI/`, to `Core.lua`, or to either
  SpellTuner TOC. The TBC line must not change.
- No new global (the proxy is a metatable on the module's own table). No library.
- A module that is off still costs nothing: nothing new runs at SpellTuner's load.
- Tests first: the two new assertions written and failing first.
- Comments say why.
- **Git:** no `git add`, `stash`, `checkout -- <path>`, `reset`, commit. Do not edit `CLAUDE.md` or
  any `docs/` file except this Report.

## Acceptance

1. `bash tools/run.sh tools/modulecheck.lua` ends `14 ok, 0 failed`. New names, verbatim:
   - "a module file reads and writes SpellTuner's namespace as MD" -- a scratch sibling built by the
     suite under a temporary `Modules/` root (or a suite-only folder the stub registers; say which)
     whose TOC lists `Module.lua`, a test file that does `local _, MD = ...; MD.T13cProbe =
     MD.API.client; MD:RegisterCallback("T13C", "t13c", function() MD.T13cFired = true end)`, and
     `Ready.lua`: after `LoadAddOn`, `_G.SpellTuner.T13cProbe == "forever"`, `MD:Fire("T13C")` sets
     `_G.SpellTuner.T13cFired`, and `MODULE_LOADED` fired after the test file ran.
   - "a module TOC entry outside the module folder loads from the repository root" -- the scratch
     sibling lists `Engine\ReplayTrace.lua` (pure, no client call): it loads, and `MD.ReplayTrace`
     (or whatever that file publishes on `MD`) is present on `_G.SpellTuner` afterwards.
2. `bash release.sh` (non-interactive, `SRC=` this worktree's name if the script needs one -- read
   it; if it cannot run offline, say so and why) with a temporary entry `Engine\ReplayTrace.lua` in
   the Replay module's TOCs builds a package whose `SpellTuner_Replay/Engine/ReplayTrace.lua` is
   byte-identical to the root file; the temporary entry is then removed again. Paste the tree.
3. `python3 tools/apicheck.py` 0 findings; `--selftest` 8 of 8 (the new fixture case counts).
4. Every other suite at its count (baseline at 8a1f451: parsecheck 11, bookcheck 15,
   spellsui 15, clockcheck 15, measurecheck 18, probecheck 71, forevercheck 13; the TBC sixteen;
   adaptercheck 19/15, corecheck 10/8, svcheck 6/1, consolecheck 11/1).
5. `luac -p` clean on every Lua file touched; `bash -n release.sh`.
6. Paste into the Report: the failing run; modulecheck in full; the release tree; every other tail;
   apicheck and its selftest; luac; `git status --short` (no stray scratch folder left behind).

## Out of scope

- Putting any real engine file into a module (T13, T15, T16 do that). `Makefile`. Per-flavour
  packaging (M5).
- `CLAUDE.md`, every `docs/` file except this Report. Commits.

## Report

**Note on the shared worktree:** while this task was in progress, other work landed in this same
tree concurrently (new commits `9712fe9`, `b7e55b7`, `8a1f451`, `4303c71`; task docs T13e/T17/T18/T19
appeared; `Modules/*/*.toc` version bumped to `1.0.0-alpha.4`; `Client/Probe.lua` changed under
someone else's hand). Several of the files this task also had to touch (`release.sh`,
`tools/apicheck.py`, and the `Ready.lua` addition already present in the committed
`SpellTuner_Replay*.toc`) were found already carrying exactly the T13c change described below
partway through -- I verified each against the task's Rules/Files/Acceptance text, kept what was
already correct, and finished what was missing (the two new `modulecheck.lua` assertions and their
fixtures, and the `Module.lua`/`Ready.lua` file pair for all three siblings, which were still on the
old single-file shape when I started). I never ran `git add`/`stash`/`checkout`/`reset`/commit.

**Files changed:**

- `Modules/SpellTuner_Recorder/Module.lua`, `Modules/SpellTuner_Replay/Module.lua`,
  `Modules/SpellTuner_Practice/Module.lua` -- rewritten: `local _, ns = ...` then, only if
  `_G.SpellTuner` is a table, `setmetatable(ns, { __index = _G.SpellTuner, __newindex =
  _G.SpellTuner })`. No longer call `ModuleLoaded`.
- `Modules/SpellTuner_Recorder/Ready.lua`, `Modules/SpellTuner_Replay/Ready.lua`,
  `Modules/SpellTuner_Practice/Ready.lua` -- new, identical in shape to the old `Module.lua`:
  `local name = ...; if _G.SpellTuner and _G.SpellTuner.ModuleLoaded then
  _G.SpellTuner:ModuleLoaded(name) end`.
- `Modules/<Name>/<Name>.toc` and `<Name>_Mainline.toc` (all three, both copies each) -- entries
  now `Module.lua` blank line `Ready.lua`, nothing between; the two copies of each module stayed
  identical.
- `tools/wowstub.lua` -- two changes, both inside the `C_AddOns` block:
  1. `LoadModuleFiles` now creates **one** fresh table per `LoadAddOn` call (`local ns = {}`
     outside the file loop) instead of one per file. This was a real gap, not just a resolution
     change: with every sibling TOC listing exactly one file until today, "fresh per file" and
     "fresh per addon" were indistinguishable, but the Facts' claim that "addonTable is that
     addon's own fresh table" only becomes true with this fix -- otherwise `Module.lua`'s
     `setmetatable` would land on a table `Ready.lua` (or the test file) never sees, since each
     would get its own separate empty table. `S.Load` (the main addon's own loader) already
     passes one shared table through its whole file loop, so this brings `LoadModuleFiles` in
     line with it.
  2. A new `ResolveModuleFile(relDir, f)` helper (module folder first, else the repository root
     under `Engine/`, `Spells/`, `Data/`, `UI/` if it exists there, else the module path
     unchanged so a genuinely missing file still fails inside `loadfile`), called from
     `LoadAddOn` before `LoadModuleFiles`.
- `release.sh` -- already present when I read it (see the worktree note above); I verified it
  matches the rule exactly: a module TOC entry missing under `Modules/<Name>/` is taken from
  the repository root when it starts with `Engine/`, `Spells/`, `Data/` or `UI/` and exists
  there, tracked in a parallel `msrc[]` array, and copied from the resolved source to the
  package's same relative path; anything else missing is still the existing `ERROR:` + exit 1.
- `tools/apicheck.py` -- already present when I read it; verified against the rule: `collect()`
  now also tries, for an entry missing under a TOC that lives under `Modules/`, the same path at
  the repository root under the same four prefixes (`MODULE_ROOT_PREFIXES`), before falling
  back to the existing "missing file" finding.
- `tools/data/apicheck-fixture/Modules/Sample/{Module.lua,Sample_Mainline.toc}` and
  `tools/data/apicheck-fixture/Engine/Ok.lua` -- already present; the new selftest fixture case:
  a module TOC listing `Engine\Ok.lua` (resolves at the fixture root, zero findings) and
  `Missing.lua` (resolves nowhere, one "missing file" finding) -- I confirmed the finding's line
  number (7, not the 8 briefly present in `apicheck.py`'s own `expected` list mid-session,
  self-corrected by the concurrent work before my next check) matches the actual TOC.
- `tools/modulecheck.lua` -- assertion 8's last clause changed from "exactly one entry,
  `Module.lua`" to "first entry `Module.lua`, last entry `Ready.lua`"; two new assertions added
  (#13, #14) per the task's exact names, using a suite-only fixture folder
  (`tools/data/modulecheck-fixture/`, registered at runtime with `S.RegisterAddOnFolder`, never
  under the real `Modules/`).
- `tools/data/modulecheck-fixture/T13CScratch/{Module.lua,T13cTest.lua,Ready.lua,
  T13CScratch_Mainline.toc}` -- new, for assertion 13.
- `tools/data/modulecheck-fixture/T13CRoot/{Module.lua,Ready.lua,T13CRoot_Mainline.toc}` -- new,
  for assertion 14 (lists `Engine\ReplayTrace.lua`).

**A Fact that did not hold, fixed rather than blocking:** the task's Acceptance text quotes the
scratch module's test file verbatim as `MD:RegisterCallback("T13C", "t13c", function() ... end)`
(three arguments: event, a handler id, the function). This codebase's actual
`MD:RegisterCallback(name, fn)` (`Core.lua:48`) takes only two -- no handler-id argument; that
3-arg convention belongs to Cell, a different addon described elsewhere in these instructions,
not SpellTuner. Called as quoted, the id string ends up where the function should be, and calling
it as a function later raises `attempt to call field '?' (a string value)` (confirmed by running
it before fixing). I dropped the stray id argument
(`MD:RegisterCallback("T13C", function() MD.T13cFired = true end)`) and did the same in
`tools/modulecheck.lua`'s own `MD:RegisterCallback("MODULE_LOADED", ...)` call, which had the
same bug. Everything else about the fixture (probe value, `MD:Fire`, ordering) is unchanged from
the task's text. I also had to call `MD:DeclareModule("T13CScratch", ...)` before `LoadAddOn` in
that assertion: `MD:ModuleLoaded` (Core.lua) is a no-op for a name `DeclareModule` never
registered, so `MODULE_LOADED` would otherwise never fire for an undeclared scratch module and
the "fired after the test file ran" half of the assertion could never be exercised.

**Tests first:** both new `modulecheck.lua` assertions were written and run against the
not-yet-created fixtures first and failed (`12 ok, 2 failed`), then the fixtures were added and
the `RegisterCallback`/`DeclareModule` fixes applied until they passed.

### Acceptance 1 -- `bash tools/run.sh tools/modulecheck.lua`

Failing run (fixtures not yet present):
```
a module file reads and writes SpellTuner's namespace as MD              FAIL
a module TOC entry outside the module folder loads from the repository root FAIL

12 ok, 2 failed
  FAIL a module file reads and writes SpellTuner's namespace as MD
  FAIL a module TOC entry outside the module folder loads from the repository root
```

Full passing run:
```
three modules are declared, in dependency order                          ok
a module that is off is never loaded                                     ok
switching a module on loads it now and remembers it                      ok
|cff9966ffSpellTuner:|r Recorder: loaded
|cff9966ffSpellTuner:|r Replay: loaded
|cff9966ffSpellTuner:|r Practice: loaded
switching on a module switches on what it needs, first                   ok
|cff9966ffSpellTuner:|r Recorder: loaded
|cff9966ffSpellTuner:|r Replay: loaded
|cff9966ffSpellTuner:|r Practice: loaded
switching off a module switches off what needs it and says it unloads at the next reload ok
|cff9966ffSpellTuner:|r Recorder: loaded
a module that is on loads at login                                       ok
a module that cannot load says why                                       ok
each sibling is a LoadOnDemand Forever addon that depends on SpellTuner  ok
/st opens the window, /st again closes it                                ok
|cff9966ffSpellTuner:|r Recorder: loaded
the Modules pane switches a module and shows its state                   ok
  (assertion 11 walk: 72 strings reached under the window, title seen 1 time(s), nav buttons seen 2 time(s))
every string the window renders is ASCII with no bare pipe               ok
|cff9966ffSpellTuner:|r Recorder: loaded
|cff9966ffSpellTuner:|r Replay: loaded
|cff9966ffSpellTuner:|r Practice: loaded
nothing on the Forever TOC or in a sibling registers the combat log      ok
a module file reads and writes SpellTuner's namespace as MD              ok
a module TOC entry outside the module folder loads from the repository root ok

14 ok, 0 failed
```

### Acceptance 2 -- `bash release.sh`

Temporarily added `Engine\ReplayTrace.lua` between `Module.lua` and `Ready.lua` in both
`Modules/SpellTuner_Replay/SpellTuner_Replay.toc` and `..._Mainline.toc`, ran:

```
bash release.sh --out <scratchpad>/relout
```
(`SRC` not needed -- it defaults to `$HERE`, this worktree, when omitted; no `--src` value was
required since we want to build this checkout.)

```
Built <scratchpad>/relout/SpellTuner (v0.15.4, 70 files) from manademon-folder-continue-41eabc, plus 3 module(s): SpellTuner_Practice SpellTuner_Recorder SpellTuner_Replay.
Built <scratchpad>/relout/SpellTuner-0.15.4.zip
Copy <scratchpad>/relout/SpellTuner into your game's Interface/AddOns folder
(or: make install WOW_ADDONS="/mnt/c/Program Files (x86)/World of Warcraft/_anniversary_/Interface/AddOns")
```
(the install hint is just `release.sh`'s normal printed suggestion -- `WOW_ADDONS` was unset, so
nothing was actually installed anywhere outside the scratch `--out` directory.)

Tree built:
```
relout/
  SpellTuner/                     (70 files: Client/, Core*.lua, Data/, Engine/, Integrations/,
                                    README.md, SpellTuner*.toc, Spells/, UI/, Verify.lua)
  SpellTuner-0.15.4.zip
  SpellTuner_Practice/{Module.lua, Ready.lua, SpellTuner_Practice.toc, SpellTuner_Practice_Mainline.toc}
  SpellTuner_Recorder/{Module.lua, Ready.lua, SpellTuner_Recorder.toc, SpellTuner_Recorder_Mainline.toc}
  SpellTuner_Replay/{Engine/ReplayTrace.lua, Module.lua, Ready.lua,
                      SpellTuner_Replay.toc, SpellTuner_Replay_Mainline.toc}
```

`diff -q relout/SpellTuner_Replay/Engine/ReplayTrace.lua Engine/ReplayTrace.lua` -> identical
(no output, exit 0) -- byte-identical, confirmed.

The temporary entry was then removed from both TOCs (confirmed by `git diff` against the two
files showing no change from the tree's current state afterwards), and the scratch `relout/`
directory was deleted (`rm -rf`) -- nothing was left under `/tmp` or under `dist/`.

### Acceptance 3 -- apicheck

```
$ python3 tools/apicheck.py
apicheck: 8 Forever TOCs, 24 files, 40 distinct globals, 0 findings (baseline 69893)

$ python3 tools/apicheck.py --selftest
FAIL Bad.lua:1 GetSpellInfo not in baseline 69893
FAIL Bad.lua:2 os not in the client's Lua
FAIL Bad.lua:3 UnitHealth client call outside Client/
FAIL Bad.lua:4 NewGlobalName new global
FAIL Bad.lua:5 COMBAT_LOG_EVENT_UNFILTERED COMBAT_LOG_EVENT_UNFILTERED named
FAIL Bad.lua:6 C_Spell.NoSuchMember C_ member not in baseline 69893
FAIL Fixture_Mainline.toc:6 Gone.lua missing file
FAIL Modules/Sample/Sample_Mainline.toc:7 Missing.lua missing file
selftest: 8 of 8 findings as expected
```

### Acceptance 4 -- every other suite

The TBC sixteen:
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
```
Forever suites:
```
probecheck    71 ok, 0 failed
forevercheck  13 ok, 0 failed
modulecheck   14 ok, 0 failed
parsecheck    11 ok, 0 failed
bookcheck     15 ok, 0 failed
tipcheck      14 ok, 0 failed
clockcheck    15 ok, 0 failed
spellsui      15 ok, 0 failed
measurecheck  18 ok, 0 failed
adaptercheck/forever 19 ok, 0 failed
adaptercheck/tbc 15 ok, 0 failed
corecheck/forever 10 ok, 0 failed
corecheck/tbc 8 ok, 0 failed
svcheck/forever 6 ok, 0 failed
svcheck/tbc   1 ok, 0 failed
consolecheck/forever 11 ok, 0 failed
consolecheck/tbc 1 ok, 0 failed
```
Every count matches the task's stated baseline (`adaptercheck` 19/15, `corecheck` 10/8, `svcheck`
6/1, `consolecheck` 11/1, `parsecheck` 11, `bookcheck` 15, `spellsui` 15, `clockcheck` 15,
`measurecheck` 18 -- confirming Phase A and T12b have both landed) **except `probecheck`, which
is 71, not the task's stated 70**: `docs/TOOLS.md`'s own suite table already documents T13b
(landed before this task started, commit `3054101`) as bringing `probecheck` to 71 assertions.
The task's Acceptance baseline of 70 predates that commit; 71 is correct for the current tree, not
a regression I introduced.

### luac / bash -n

```
$ tools/.lua/lua-5.1.5/src/luac -p Modules/SpellTuner_Practice/Module.lua && echo OK
OK
$ tools/.lua/lua-5.1.5/src/luac -p Modules/SpellTuner_Recorder/Module.lua && echo OK
OK
$ tools/.lua/lua-5.1.5/src/luac -p Modules/SpellTuner_Replay/Module.lua && echo OK
OK
$ tools/.lua/lua-5.1.5/src/luac -p Modules/SpellTuner_Practice/Ready.lua && echo OK
OK
$ tools/.lua/lua-5.1.5/src/luac -p Modules/SpellTuner_Recorder/Ready.lua && echo OK
OK
$ tools/.lua/lua-5.1.5/src/luac -p Modules/SpellTuner_Replay/Ready.lua && echo OK
OK
$ tools/.lua/lua-5.1.5/src/luac -p tools/wowstub.lua && echo OK
OK
$ tools/.lua/lua-5.1.5/src/luac -p tools/modulecheck.lua && echo OK
OK
$ tools/.lua/lua-5.1.5/src/luac -p tools/data/modulecheck-fixture/T13CScratch/Module.lua && echo OK
OK
$ tools/.lua/lua-5.1.5/src/luac -p tools/data/modulecheck-fixture/T13CScratch/T13cTest.lua && echo OK
OK
$ tools/.lua/lua-5.1.5/src/luac -p tools/data/modulecheck-fixture/T13CScratch/Ready.lua && echo OK
OK
$ tools/.lua/lua-5.1.5/src/luac -p tools/data/modulecheck-fixture/T13CRoot/Module.lua && echo OK
OK
$ tools/.lua/lua-5.1.5/src/luac -p tools/data/modulecheck-fixture/T13CRoot/Ready.lua && echo OK
OK
$ tools/.lua/lua-5.1.5/src/luac -p tools/data/apicheck-fixture/Modules/Sample/Module.lua && echo OK
OK
$ tools/.lua/lua-5.1.5/src/luac -p tools/data/apicheck-fixture/Engine/Ok.lua && echo OK
OK
$ bash -n release.sh && echo "release.sh: bash -n OK"
release.sh: bash -n OK
```
`tools/apicheck.py` has no `luac`-equivalent syntax check of its own; it is a Python script and
was exercised directly (0 findings, selftest 8/8 above) rather than `luac -p`'d.

### Final `git status --short`

```
 M Client/Probe.lua
 M Modules/SpellTuner_Practice/Module.lua
 M Modules/SpellTuner_Recorder/Module.lua
 M Modules/SpellTuner_Replay/Module.lua
 M release.sh
 M tools/apicheck.py
 M tools/modulecheck.lua
 M tools/wowstub.lua
?? Modules/SpellTuner_Practice/Ready.lua
?? Modules/SpellTuner_Recorder/Ready.lua
?? Modules/SpellTuner_Practice/Ready.lua
?? docs/tasks/T13c-module-plumbing.md
?? tools/data/apicheck-fixture/Engine/
?? tools/data/apicheck-fixture/Modules/
?? tools/data/modulecheck-fixture/
```
`Client/Probe.lua` is not mine -- I never opened or edited it; it was modified by other work in
this shared tree. No stray scratch folder was left behind; the release-build scratch directory
was removed after the byte-identity check.

### Out of scope, as instructed

No real engine file was put into a module's permanent TOC (T13/T15/T16's job); `Makefile` and
per-flavour packaging (M5) untouched; `CLAUDE.md` and every `docs/` file besides this Report were
left alone; no `git add`/`stash`/`checkout -- <path>`/`reset`/commit was run.

## Lead review (2026-09-28)

Accepted. Every suite rerun by the lead: modulecheck 14, apicheck 0 findings, `--selftest` 8 of 8,
refcheck selftest ok, every other suite at its baseline. Release checked by the lead: a temporary
`Engine\ReplayTrace.lua` in both Replay TOCs builds `SpellTuner_Replay/Engine/ReplayTrace.lua`
byte-identical to the root file (`cmp`); TOCs restored. The implementer's correction of the task
text is right: `MD:RegisterCallback(name, fn)` takes two arguments (`Core.lua`), the three-argument
form in Acceptance 1 was the lead's error. `DeclareModule` for the scratch sibling is needed and
correct. Two T13c hunks were committed early by the previous lead run: the module TOCs' `Ready.lua`
line (in 8a1f451) and the stub's resolver (in b7e55b7); this commit completes them.
