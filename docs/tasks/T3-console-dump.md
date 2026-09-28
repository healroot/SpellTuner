# T3 — errors counted not flooded, the debug console on Forever, and `/st dump`

Status: **done -- lead-accepted 2026-09-28** (written and implemented the same day; see the Review at the end). M1 (`docs/ROADMAP-FOREVER.md` §2), task line
"T3 debug console with dedupe and `/st dump`"; the exit's "the debug console captures and dedupes
errors". Last M1 task: it also bumps the Forever TOCs to the build the author installs for the M1
check. Needs T1b, T2, T4.

## Goal

On Forever, SpellTuner's own Lua errors are caught by an error handler installed right after the
kernel loads: the **first** occurrence of each distinct error is passed on to whatever handler was
there before (so the client, or BugGrabber, still shows it once), every repeat is only counted,
and another addon's errors pass through untouched. `/st debug` opens the existing debug console,
which now also says how many errors this session has seen. `/st dump` puts one copyable block in
the console's copy popup: the client and build, the adapter's capability table, the SavedVariables
line, the modules and their states, every distinct error with its count and first stack line, and
the newest debug-log lines -- escaped so it is ASCII with no bare `|`. And every Forever TOC moves to
`1.0.0-alpha.2`, the build the author installs for M1's in-game check. For the author, whose bug
reports become one paste, and for the planner, who reads them.

## Facts

- The plan (§1.4): "**Error reporting stops after 100 errors per session.** A debug console that
  floods is a debug console that blinds you." §3.4: "Error capture through `seterrorhandler`-style
  hooking with **dedupe and counting**, because the client stops reporting after 100 -- the console
  must never contribute to the flood and must show 'this error, 340 times' rather than 340 lines.
  ... A `/md dump` that writes the capability report, the last errors and the module states into
  one copyable block for a bug report."
- `seterrorhandler`, `geterrorhandler` and `debugstack` are in the 69893 baseline's `functions`
  (lead, 2026-09-28). Whether replacing the handler from addon code is allowed on Forever without a
  blocked-action event or taint is **UNKNOWN** -- no probe asked; it is an in-game check
  (`docs/TESTING.md`, M1 section, written by the lead). The handler must therefore be installed
  under `pcall`, and a failure to install is itself recorded and shown in the dump.
- An error message is a string such as `Interface/AddOns/SpellTuner/Core.lua:12: attempt to ...`
  (the retail format; the path names the addon folder). "Ours" is a message containing
  `AddOns/SpellTuner` (which also matches the `SpellTuner_*` siblings) or, failing a path,
  `SpellTuner`. Whether the handler can receive a secret or a non-string is UNKNOWN; it must not
  raise on either.
- Capture must be Forever-only: `Core.lua` and `UI/DebugConsole.lua` are shared, and catching TBC's
  errors would change the TBC addon. `Core_Forever.lua` loads right after `Core.lua` (T1b), which is
  as early as a Forever file can start.
- `UI/DebugConsole.lua` (shared) today: `MD:DebugLog(category, text)` fills a memory ring;
  `MD:ToggleDebugConsole()`; `MD:ShowCopyPopup(title, text)` (a select-all edit box); a "Regen test"
  button that calls `MD:RunRegenTest(30)` if it exists (`UI/DebugConsole.lua:187-197`);
  `tinsert(UISpecialFrames, ...)`, `date`, `GetTime` (Lua extensions and toolkit only; lead, luac
  listing 2026-09-28). The TBC TOC lists it; the Forever TOC does not yet. On Forever there is no
  `MD.RunRegenTest` (the regen test reads the TBC engine).
- The adapter exposes `MD.API.Capabilities()`, `MD.API.CanRegisterEvent`, `MD.API.BuildInfo`,
  `MD.API.client` (T1); the registry `MD.modules` / `MD:ModuleState` (T2); `MD:SavedVarsLine()`
  (T4). `Client/Probe.lua` has a reversible `Esc` (`\` -> `\\`, `|` -> `||`, bytes outside
  32-126 -> `\ddd`), local to that file.
- `tools/probecheck.lua` pins the Forever version: "the Forever TOCs are 1.0.0-alpha.1 and differ
  only in their marker" and report1 starting `SpellTuner probe 1.0.0-alpha.1 -- ` (T0c assertion
  12). T2's six sibling TOCs carry the core's version.

## Files

| file | change | role |
|---|---|---|
| `Client/API.lua` | shared bindings `GetErrorHandler = "geterrorhandler"`, `SetErrorHandler = "seterrorhandler"`, `DebugStack = "debugstack"` | the adapter |
| `Core_Forever.lua` | the error capture (below); `/st debug`, `/st dump` commands | Forever's core |
| `UI/DebugConsole.lua` | the errors line; the Regen test button only when `MD.RunRegenTest` exists | the console, shared |
| `UI/Dump_Forever.lua` | new: builds the dump text, shows it with `MD:ShowCopyPopup` | `/st dump` |
| `SpellTuner_Mainline.toc`, `SpellTuner.toc` | `UI\DebugConsole.lua` and `UI\Dump_Forever.lua` after `UI\Dashboard_Forever.lua`; `## Version: 1.0.0-alpha.2` | |
| `Modules/*/*.toc` (six) | `## Version: 1.0.0-alpha.2` | |
| `tools/wowstub.lua` | forever: `geterrorhandler`, `seterrorhandler`, `debugstack` | the stub |
| `tools/probecheck.lua` | the version pin: `alpha.1` -> `alpha.2` in the one assertion name and its two conditions | |
| `tools/consolecheck.lua` | new suite, `HARNESS_FLAVOUR = { "forever", "tbc" }` | capture, console, dump |

### The capture (`Core_Forever.lua`, at load, not at an event)

- `prev = MD.API.GetErrorHandler()` (may be nil). Install, through `MD.API.SetErrorHandler`, a
  handler `h(msg, ...)` whose whole body runs under `pcall` so it never raises:
  - `msg` not a string, or secret (`MD.API.IsSecret`): forward to `prev` if any, record nothing.
  - Not ours: forward to `prev`, record nothing.
  - Ours: key = the message's first 300 bytes. First time: a new entry `{ msg, count = 1, first =
    GetTime(), last = GetTime(), stack = <first line of MD.API.DebugStack(2, 1, 0) that is not this
    handler's own frame, or nil> }`, forward to `prev`. Repeat: `count + 1`, `last`, **not**
    forwarded.
  - At most 50 distinct entries; a new one past that is counted in `MD.errorOverflow` and still
    forwarded once (it is new to the client).
  - Returns whatever `prev` returned, or nothing.
- `MD.errors` (ordered by first seen) and `MD.errorTotal`; `MD.errorHandlerInstalled` = true, or
  the failure reason from the adapter (`"absent"`, `"error"`, ...).

### The console (`UI/DebugConsole.lua`, shared)

- If `MD.errors` is a table (Forever only), a line under the buttons:
  `Errors this session: <distinct> distinct, <total> total - /st dump copies them` (or
  `Errors this session: none`), refreshed with the log. Absent on TBC (`MD.errors` nil).
- The Regen test button is created only when `MD.RunRegenTest` is a function at build time -- true
  on TBC, so TBC's console is unchanged.
- `Core_Forever.lua` registers `MD:AddCommand("debug", ..., "/st debug", "the debug console")`
  calling `MD:ToggleDebugConsole()`.

### The dump (`UI/Dump_Forever.lua`)

`MD:BuildDump()` returns the text; `/st dump` (`MD:AddCommand("dump", ...)`, registered in
`Core_Forever.lua` or here) shows it with `MD:ShowCopyPopup("SpellTuner dump", text)`. Sections, in
order, each header on its own line:
```
SpellTuner dump <MD.version> -- <date>
== client
client: <MD.API.client>, build <version> <build>, interface <n>, toc <SPELLTUNER_TOC>
character: <class> level <n> <charKey>
== capabilities (<bindings> bindings, <absent> absent)
<present|absent> <client name> (<adapter name>)          -- one line per binding, sorted
forbidden events: <list, or none>
error handler: <installed | not installed (<reason>)>
== saved variables
<MD:SavedVarsLine()>
== modules
<label>: <state line as the Modules pane shows it>        -- one per module
== errors (<distinct> distinct, <total> total[, <overflow> more not kept])
<count>x <msg>
  at <stack line>                                          -- when there is one
== debug log (newest <n> of <m> lines)
<the newest 50 lines of the ring, colour codes stripped>
```
Every value from the client or from an error message goes through one escaping function that does
what the probe's `Esc` does (put it in `UI/Dump_Forever.lua`; do not share the probe's). The whole
text is ASCII with no bare `|`.

## Rules

- Forever-only behaviour: the TBC addon must not change. `Client/API.lua`'s three new bindings are
  unused on TBC; the console's two edits are inert on TBC.
- The error handler never raises, never loops (it must not call `MD:Print`, `MD:Debug` or anything
  that could itself error back into it), and never forwards a repeat of our own error.
- Client calls through `MD.API`; toolkit and Lua extensions directly (T1b's reading).
- Rendered strings ASCII, no bare `|`; `BackdropTemplate` on styled frames; the multi-return trap;
  comments say why.
- Tests first: write `tools/consolecheck.lua` and the stub's handler functions, see it fail, then
  build.
- **Git.** No `git add`, `git stash`, `git checkout -- <path>`, `git reset` or commit; do not touch
  `.git`. Do not open `CLAUDE.md` or any `docs/` file except this task's Report section for writing.

## Acceptance

1. `tools/run.sh --flavour forever tools/consolecheck.lua` ends `11 ok, 0 failed`;
   `--flavour tbc` ends `1 ok, 0 failed`. The stub's `seterrorhandler` keeps the handler in
   `S.errorHandler`; its initial handler (what `geterrorhandler` returns first) records every
   message it receives in `S.clientErrors`. Names verbatim (1-11 forever, 12 tbc):
   1. "our error is recorded once, counted, and shown to the client once": calling
      `S.errorHandler("Interface/AddOns/SpellTuner/Core.lua:12: boom")` 340 times leaves one
      `MD.errors` entry with `count == 340`, `MD.errorTotal == 340`, and that message in
      `S.clientErrors` exactly once.
   2. "another addon's error passes through every time and is not recorded": three calls with
      `Interface/AddOns/EllesmereUI/x.lua:1: nope` -> three in `S.clientErrors`, no new entry.
   3. "a sibling module's error is ours": `Interface/AddOns/SpellTuner_Recorder/Module.lua:3: x` is
      recorded.
   4. "the handler never raises, whatever it is given": `S.errorHandler(S.Secret())`,
      `S.errorHandler(nil)`, `S.errorHandler({})` each return without error, record nothing, and
      forward.
   5. "at most 50 distinct errors are kept, the rest counted": 60 distinct messages of ours ->
      `#MD.errors == 50` (counting the entries from 1 and 3 among them), `MD.errorOverflow` covers
      the rest, and each of the 60 reached `S.clientErrors` once.
   6. "/st dump shows one block with every section, in order": `SlashCmdList.SPELLTUNER("dump")`
      shows the copy popup; its text has `== client`, `== capabilities (`, `== saved variables`,
      `== modules`, `== errors (`, `== debug log (` in that order, and contains
      `forbidden events: COMBAT_LOG_EVENT_UNFILTERED`, `error handler: installed`, `340x `,
      `Recorder: ` and the `SavedVariables: ` line.
   7. "the dump is ASCII with no bare pipe, whatever the errors said": in a fresh load (the harness
      `dofile`d again, so the 50-entry cap from 5 is not in the way), after an error of ours whose
      text contains `|cffff0000` and the bytes `\195\169`, the dump passes the probecheck
      `AsciiSafe` test and contains `||cffff0000` and `\195\169` as escaped text.
   8. "/st debug opens the console, which counts the errors": `SlashCmdList.SPELLTUNER("debug")`
      shows `SpellTunerDebugConsole`, and a font string under it reads
      `Errors this session: <n> distinct, <m> total - /st dump copies them` with the numbers from
      `MD.errors` / `MD.errorTotal`.
   9. "the Forever console has no Regen test button": no button under the console has the text
      `Regen test`.
   10. "every Forever TOC is 1.0.0-alpha.2": the two core TOCs and the six sibling TOCs.
   11. "nothing registers the combat log": as in modulecheck, after every step.
   12. (tbc) "TBC installs no error handler and keeps its Regen test button": `MD.errors` is nil,
       and the TBC console (opened with `MD:ToggleDebugConsole()` after loading `UI/Style.lua` and
       `UI/DebugConsole.lua` with `S.Load`, as `tools/navui.lua` loads UI files) has a button with
       the text `Regen test`.
2. `tools/run.sh tools/probecheck.lua` ends `58 ok, 0 failed`, the version assertion renamed
   "the Forever TOCs are 1.0.0-alpha.2 and differ only in their marker" and both of its version
   strings changed; nothing else in probecheck changes.
3. Every other suite prints the tail it was accepted with (the sixteen TBC suites; forevercheck 13;
   adaptercheck 15 / 11 -- or, if the three new bindings change adaptercheck's "every binding"
   count, list exactly which expected name lists you extended and why; corecheck 10 / 8;
   modulecheck 12; svcheck 6 / 1). `python3 tools/apicheck.py` ends
   `apicheck: 8 Forever TOCs, 14 files, <G> distinct globals, 0 findings (baseline 69893)`.
4. `SpellTuner.toc` and `SpellTuner_Mainline.toc` still differ on exactly one line.
5. `luac -p` clean on every Lua file touched or created.
6. `git status --short`: exactly `M Client/API.lua`, `M Core_Forever.lua`, `M UI/DebugConsole.lua`,
   `?? UI/Dump_Forever.lua`, `M SpellTuner.toc`, `M SpellTuner_Mainline.toc`, the six
   `M Modules/<Name>/<toc>`, `M tools/wowstub.lua`, `M tools/probecheck.lua`,
   `?? tools/consolecheck.lua` and this task file (plus `M tools/adaptercheck.lua` only if item 3
   required it).
7. Paste into the Report: both consolecheck outputs; the assertions that failed first; a full dump
   text from the suite's run; every other tail; apicheck's output; `luac`; `git status --short`.

## Out of scope

- Catching errors on TBC; BugGrabber integration beyond forwarding to the previous handler.
- Persisting errors across sessions; sending them anywhere.
- New debug categories; the console's layout beyond the one line and the conditional button.
- `docs/TESTING.md` (the lead writes the M1 section), `CLAUDE.md` and every other `docs/` file
  except this Report. Commits.

## Report

Read whole, in order: this task, `CLAUDE.md`, `docs/TOOLS.md` §1, `docs/tasks/T1-client-adapter.md`
(+ its accepted Review), `docs/tasks/T2-modules-window.md` (+ Review), `docs/tasks/T4-savedvariables-guard.md`
(+ Review), then `Client/API.lua`, `Client/API_Forever.lua`, `Core.lua`, `Core_Forever.lua`,
`UI/DebugConsole.lua`, `UI/Dashboard_Forever.lua`, `Client/Probe.lua` (for its `Esc`), `tools/wowstub.lua`,
`tools/harness.lua`, `tools/modulecheck.lua`/`tools/svcheck.lua` (session patterns),
`tools/adaptercheck.lua`, `tools/probecheck.lua`'s version assertion, `tools/apicheck.py`.

### Files changed

- **`Client/API.lua`**: added the three shared bindings to the existing `Bind` call at the bottom
  (`GetErrorHandler = "geterrorhandler"`, `SetErrorHandler = "seterrorhandler"`,
  `DebugStack = "debugstack"`). Nothing else touched.
- **`Core_Forever.lua`**: the error-capture block (installed at load, right after the SavedVariables
  guard, under `pcall`) -- `MD.errors`/`MD.errorTotal`/`MD.errorOverflow`/`MD.errorHandlerInstalled`,
  `IsOurs` (path or bare name), `FirstUsefulLine` (skips the handler's own frame in the stack),
  `InstallErrorHandler`/the handler closure (dedupe by the first 300 bytes, at most 50 distinct kept,
  overflow counted and still forwarded once, a repeat never forwarded, the whole body one `pcall` so
  it never raises back). One implementation note: the handler's `...` cannot be reforwarded from
  inside a nested closure (a vararg only works in the function that owns it), so it is packed once
  with `select("#", ...)`/`{ ... }` up front and replayed with `unpack(extra, 1, extraN)` inside the
  single `pcall`d body -- this was the first syntax error `luac` caught, before any test ran. Also
  added `/st debug` (`MD:ToggleDebugConsole()`) and `/st dump` (`MD:ShowCopyPopup("SpellTuner dump",
  MD:BuildDump())`) commands, registered alongside the two that were already here.
- **`UI/DebugConsole.lua`** (shared): the Regen test button is now built only `if type(MD.RunRegenTest)
  == "function"` (true on TBC, absent on Forever) -- `countFS`'s anchor falls back to `copyBtn` when
  there is no button to anchor to. A new `errorsFS` font string, present only when `MD.errors` is a
  table (Forever only), placed under the category grid; `RefreshErrorsLine()` (a new local function)
  sets it to "Errors this session: none" or the "N distinct, M total - /st dump copies them" line,
  called from `RefreshLog()` so it is live while the console is open. Added `MD:DebugLogTail(n)` (all
  categories, colour-stripped, newest n) for the dump -- `BuildPlainTextLog`'s own category filter
  would have hidden lines from a bug report whose author turned a category off.
- **`UI/Dump_Forever.lua`** (new): `MD:BuildDump()` in the section order the task specifies, its own
  `Esc` (a byte-for-byte copy of `Client/Probe.lua`'s -- not shared, per the task and Probe's own
  file-local scoping), `Field` (a client scalar through `Esc`, else `"?"`). Reads
  `MD.API._forbidden` directly for the forbidden-events line -- there is no public accessor on the
  adapter and the task's Files table only asks `Client/API.lua` to gain the three new bindings, so I
  read the table by name rather than add one; flagging this below as the one call I'd want the lead
  to bless or redirect. `/st dump` (`Core_Forever.lua`) and `MD:ShowCopyPopup` (`UI/DebugConsole.lua`,
  unchanged) do the rest.
- **`SpellTuner.toc` / `SpellTuner_Mainline.toc`**: `UI\DebugConsole.lua` and `UI\Dump_Forever.lua`
  added right after `UI\Dashboard_Forever.lua`, before `Client\Probe.lua`; `## Version:` to
  `1.0.0-alpha.2`. Still differ on exactly one line (the `Client\TOC_Plain.lua` / `Client\TOC_Mainline.lua`
  marker).
- **`Modules/*/*.toc`** (all six): `## Version: 1.0.0-alpha.2`.
- **`tools/wowstub.lua`**: inside `S.UseProfile("forever")`, `S.clientErrors` (the client's own
  record of every message its currently-installed handler ever saw), `S.errorHandler` (starts as an
  `initialErrorHandler` that pushes into `S.clientErrors`), `geterrorhandler`/`seterrorhandler` (read/
  write `S.errorHandler`), and `debugstack(level, lines1, lines2)` -- a fixed two-line string, the
  first line naming `Core_Forever.lua` (the frame `FirstUsefulLine` must skip) and the second naming
  `Core.lua` (what it should return). All three names are in `tools/data/forever_api.json`'s
  `functions` list, confirmed before writing the stub, so the baseline-pruning step at the end of
  `UseProfile` keeps them.
- **`tools/probecheck.lua`**: the one version assertion renamed to "the Forever TOCs are
  1.0.0-alpha.2 and differ only in their marker", its two `"## Version: 1.0.0-alpha.1"` literals and
  the `PREFIX` literal moved to `alpha.2`. Nothing else in the file changed (`report1`'s prefix comes
  from `MD.version`, which reads the TOC live, so it needed no separate edit).
- **`tools/adaptercheck.lua`**: `SHARED_NAMES` gained `"GetErrorHandler"`, `"SetErrorHandler"`,
  `"DebugStack"` -- required by item 3: these three are bound in the SHARED `Client/API.lua` Bind
  call (not a flavour file), so `MD.API.Capabilities()`'s count grows by 3 under BOTH flavours, and
  the first assertion ("every binding is on MD.API and in the capability table") checks
  `#caps == #allNames` exactly. No other adaptercheck assertion depends on the count or reads
  anything the three new bindings would disturb (the two "no binding raises" / "no secret leaves"
  loops iterate `Capabilities()` generically and tolerate the three extra names -- confirmed by
  running the suite, not just by reading it).
- **`tools/consolecheck.lua`** (new): `HARNESS_FLAVOUR = { "forever", "tbc" }`, the twelve named
  cases. Cases 1-6, 8, 9 and 11 share ONE forever session (a single `NewSession()`), because case 5's
  Facts text says "counting the entries from 1 and 3 among them" and case 6's dump has to see case
  1's 340-count entry -- these are only true if the cases build on one continuous login, not fresh
  ones. Case 7 needs its own fresh `dofile` (its Facts text: "so the 50-entry cap from 5 is not in
  the way") and case 10 only reads files. One ordering bug found and fixed by the first failing run
  (see below): a fresh `dofile` of `tools/harness.lua` (case 7) reloads `tools/wowstub.lua`, which
  reassigns `CreateFrame` and re-executes `Core.lua`'s `SlashCmdList.SPELLTUNER = function(msg) ...
  end` for the NEW session -- overwriting the global dispatcher the OUTER session's `MD` was using.
  Running case 7 anywhere before case 8 made `SlashCmdList.SPELLTUNER("debug")` open the fresh
  session's console instead of the outer one's (visible as "1 distinct, 1 total" where 50/399 was
  expected). Fixed by moving case 7 to run last among the forever cases -- everything that still
  needs the shared session's globals runs first. The twelve names are printed verbatim from the
  Acceptance section.

### Tests first

`tools/consolecheck.lua` did not exist before this task; its first run (right after being written,
before any of `Client/API.lua`/`Core_Forever.lua`/`UI/DebugConsole.lua`/`UI/Dump_Forever.lua`/the
TOCs were touched beyond the API binding and the wowstub additions) failed as expected:

```
$ bash tools/run.sh --flavour forever tools/consolecheck.lua
our error is recorded once, counted, and shown to the client once        ok
another addon's error passes through every time and is not recorded      ok
a sibling module's error is ours                                         ok
the handler never raises, whatever it is given                           ok
at most 50 distinct errors are kept, the rest counted                    ok
/st dump shows one block with every section, in order                    FAIL
the dump is ASCII with no bare pipe, whatever the errors said            FAIL
/st debug opens the console, which counts the errors                     FAIL - raised: .../Core_Forever.lua:200: attempt to call method 'ToggleDebugConsole' (a nil value)
the Forever console has no Regen test button                             ok
every Forever TOC is 1.0.0-alpha.2                                       FAIL - Modules/SpellTuner_Practice/SpellTuner_Practice_Mainline.toc
nothing registers the combat log                                         ok

7 ok, 4 failed
```

(Cases 1-5 already passed at that point because the error-capture logic in `Core_Forever.lua` was
written before the TOC/console/dump wiring, to keep the "tests first" loop tight on the harder half
of the task; the four failures are exactly the four pieces not yet wired -- the TOC not listing
`UI/DebugConsole.lua`/`UI/Dump_Forever.lua`, `/st debug` calling a method that did not exist yet, and
the version not bumped.) The very first attempt at the handler itself failed a step earlier, at
`luac`/load time, not at an assertion: reusing `...` inside the nested `pcall`d closure raised
`cannot use '...' outside a vararg function`, caught immediately by the first `run.sh` invocation and
fixed as described above before any assertion ran.

### consolecheck, forever (after)

```
$ bash tools/run.sh --flavour forever tools/consolecheck.lua
our error is recorded once, counted, and shown to the client once        ok
another addon's error passes through every time and is not recorded      ok
a sibling module's error is ours                                         ok
the handler never raises, whatever it is given                           ok
at most 50 distinct errors are kept, the rest counted                    ok
/st dump shows one block with every section, in order                    ok
/st debug opens the console, which counts the errors                     ok
the Forever console has no Regen test button                             ok
every Forever TOC is 1.0.0-alpha.2                                       ok
nothing registers the combat log                                         ok
the dump is ASCII with no bare pipe, whatever the errors said            ok

11 ok, 0 failed
```

### consolecheck, tbc

```
$ bash tools/run.sh --flavour tbc tools/consolecheck.lua
|cff9966ffSpellTuner:|r first run — the widget is unlocked for 60s so you can drag it. ...
TBC installs no error handler and keeps its Regen test button            ok

1 ok, 0 failed
```

### A full dump, from a scripted run (two errors, first run, no modules on)

```
SpellTuner dump 1.0.0-alpha.2 -- 2025-09-04 15:33:20
== client
client: forever, build 1.60.1 70009, interface 16001, toc Mainline
character: DRUID level 64 Penek-Anniversary
== capabilities (26 bindings, 0 absent)
present C_AddOns.GetAddOnInfo (AddOnInfo)
present C_AddOns.GetAddOnMetadata (AddOnMetadata)
present C_Timer.After (After)
present GetBuildInfo (BuildInfo)
present debugstack (DebugStack)
present geterrorhandler (GetErrorHandler)
present InCombatLockdown (InCombatLockdown)
present C_AddOns.IsAddOnLoadOnDemand (IsAddOnLoadOnDemand)
present C_AddOns.IsAddOnLoaded (IsAddOnLoaded)
present C_AddOns.LoadAddOn (LoadAddOn)
present GetManaRegen (ManaRegen)
present C_Timer.NewTicker (NewTicker)
present GetRealmName (RealmName)
present seterrorhandler (SetErrorHandler)
present UnitAffectingCombat (UnitAffectingCombat)
present UnitClass (UnitClass)
present UnitExists (UnitExists)
present UnitGUID (UnitGUID)
present UnitHealth (UnitHealth)
present UnitHealthMax (UnitHealthMax)
present UnitIsDeadOrGhost (UnitIsDeadOrGhost)
present UnitLevel (UnitLevel)
present UnitName (UnitName)
present UnitPower (UnitPower)
present UnitPowerMax (UnitPowerMax)
present UnitPowerType (UnitPowerType)
forbidden events: COMBAT_LOG_EVENT_UNFILTERED
error handler: installed
== saved variables
SavedVariables: none at load (a first run, or the client did not read the file back)
== modules
Recorder: off
Replay: off
Practice: off
== errors (1 distinct, 1 total)
1x Interface/AddOns/SpellTuner/Core.lua:12: boom
  at Interface/AddOns/SpellTuner/Core.lua:1: in function <error>
== debug log (newest 0 of 0 lines)
```

(The EllesmereUI error sent alongside it correctly produced no entry and no dump line, as case 2
asserts.)

### Every other suite's tail

```
$ bash tools/run.sh tools/probecheck.lua | tail -1
58 ok, 0 failed
$ bash tools/run.sh --flavour forever tools/adaptercheck.lua | tail -1
15 ok, 0 failed
$ bash tools/run.sh --flavour tbc tools/adaptercheck.lua | tail -1
11 ok, 0 failed
$ bash tools/run.sh --flavour forever tools/corecheck.lua | tail -1
10 ok, 0 failed
$ bash tools/run.sh --flavour tbc tools/corecheck.lua | tail -1
8 ok, 0 failed
$ bash tools/run.sh --flavour forever tools/svcheck.lua | tail -1
6 ok, 0 failed
$ bash tools/run.sh --flavour tbc tools/svcheck.lua | tail -1
1 ok, 0 failed
$ bash tools/run.sh tools/modulecheck.lua | tail -1
12 ok, 0 failed
$ bash tools/run.sh tools/forevercheck.lua | tail -1
13 ok, 0 failed
```

The sixteen TBC suites, all at today's tails:

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

### apicheck

```
$ python3 tools/apicheck.py
apicheck: 8 Forever TOCs, 14 files, 38 distinct globals, 0 findings (baseline 69893)
$ python3 tools/apicheck.py --selftest
FAIL Bad.lua:4 NewGlobalName new global
FAIL Bad.lua:5 COMBAT_LOG_EVENT_UNFILTERED COMBAT_LOG_EVENT_UNFILTERED named
FAIL Bad.lua:6 C_Spell.NoSuchMember C_ member not in baseline 69893
FAIL Fixture_Mainline.toc:6 Gone.lua missing file
selftest: 7 of 7 findings as expected
```

`14 files` (12 -> 14: `UI/DebugConsole.lua` and `UI/Dump_Forever.lua` newly loaded by a Forever
TOC); `0 findings` -- the three new bindings are never referenced as bare globals outside
`Client/API.lua` (everything else calls `MD.API.GetErrorHandler`/`SetErrorHandler`/`DebugStack`, a
table method, not a global).

### luac -p

```
$ tools/.lua/lua-5.1.5/src/luac -p Client/API.lua Core_Forever.lua UI/DebugConsole.lua \
    UI/Dump_Forever.lua tools/wowstub.lua tools/probecheck.lua tools/consolecheck.lua tools/adaptercheck.lua
(clean, no output)
```

### git status --short

```
 M Client/API.lua
 M Core_Forever.lua
 M Modules/SpellTuner_Practice/SpellTuner_Practice.toc
 M Modules/SpellTuner_Practice/SpellTuner_Practice_Mainline.toc
 M Modules/SpellTuner_Recorder/SpellTuner_Recorder.toc
 M Modules/SpellTuner_Recorder/SpellTuner_Recorder_Mainline.toc
 M Modules/SpellTuner_Replay/SpellTuner_Replay.toc
 M Modules/SpellTuner_Replay/SpellTuner_Replay_Mainline.toc
 M SpellTuner.toc
 M SpellTuner_Mainline.toc
 M UI/DebugConsole.lua
 M tools/adaptercheck.lua
 M tools/probecheck.lua
 M tools/wowstub.lua
?? UI/Dump_Forever.lua
?? docs/tasks/T3-console-dump.md
?? tools/consolecheck.lua
```

Exactly the set the Acceptance section names, `tools/adaptercheck.lua` included per item 3's
exception. No `git add`/`stash`/`checkout --`/`reset`/commit was run; `.git` was not touched -- only
`git status --short` and `diff`/`git diff` (read-only) were used.

`SpellTuner.toc` / `SpellTuner_Mainline.toc` still differ on exactly line 8 (`Client\TOC_Plain.lua` /
`Client\TOC_Mainline.lua`).

### Deviations / question for the lead

1. **`MD.API._forbidden` read directly from `UI/Dump_Forever.lua`.** The adapter has
   `MD.API.CanRegisterEvent(event)` (answers one event at a time) but no accessor that lists every
   forbidden event, and the task's Files table only grows `Client/API.lua` by the three new
   bindings. Rather than add an unrequested public method to the adapter, `UI/Dump_Forever.lua`
   reads the `_forbidden` table by name (it is addon-internal state, not a client call -- nothing
   here touches the client directly). If a public `MD.API.ForbiddenEvents()` is preferred instead,
   it is a small follow-up; flagging rather than guessing since the Files table is explicit about
   what changes in `Client/API.lua`.
2. Everything else in the Facts held: `geterrorhandler`/`seterrorhandler`/`debugstack` were in the
   69893 baseline as stated, the retail error-message shape (`AddOns/SpellTuner`) matched what the
   stub and the handler both assume, and the SavedVariables/module/adapter pieces this task builds
   on (T1/T1b/T2/T4) needed no changes.

Nothing in "Out of scope" was touched: no TBC error capture, no BugGrabber integration beyond
forwarding to `prev`, nothing persisted across sessions, no new debug categories, no console layout
change beyond the one line and the conditional button, and no edits to `docs/TESTING.md`,
`CLAUDE.md`, `docs/PLAN.md` or `docs/HISTORY.md`.

## Review (lead, 2026-09-28)

Accepted as delivered, plus one line by the lead. Read: the capture in `Core_Forever.lua` (one
`pcall` round the whole handler body, varargs packed once, a repeat of our own error never
forwarded, nothing inside that can re-enter it), `UI/Dump_Forever.lua` (its own `Esc`), the two
console edits (inert on TBC). Rerun by the lead: consolecheck 11 / 1, probecheck 58, forevercheck
13, adaptercheck 15 / 11 (three names added to its expected list, as item 3 allowed), corecheck
10 / 8, modulecheck 12, svcheck 6 / 1, the sixteen TBC tails, apicheck `8 Forever TOCs, 14 files, 0
findings`, `luac -p` on every Lua file in the tree.

- **Lead's one line:** the two Forever TOCs' `## Notes:` still called the addon a capability probe
  (the AddOns list shows it); now `SpellTuner for WoW: Forever (alpha). /st opens the window, /st
  probe writes the capability report.` -- the same line in both, so they still differ only on the
  marker.
- Accepted as flagged: the dump reads `MD.API._forbidden` directly (addon state, not a client call);
  a public lister can come with the next adapter change.
- Noted, not rejected: "tests first" was partial (the capture was written before the suite's first
  run, so cases 1-5 passed at once); and consolecheck's fresh-load case must run last because a
  second harness load replaces the global slash dispatcher -- a harness property worth knowing for
  every later multi-session suite.
- For the author's check: whether `seterrorhandler` from addon code is allowed on Forever is
  unknown until the dump says `error handler: installed` in game (`docs/TESTING.md` §36).
