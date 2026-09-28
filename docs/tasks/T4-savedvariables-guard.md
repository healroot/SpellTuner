# T4 — the SavedVariables guard: say whether the file came back, and never index a broken one

Status: **done -- lead-accepted 2026-09-28** (written and implemented the same day; see the Review at the end). M1 (`docs/ROADMAP-FOREVER.md` §2), task line
"T4 SavedVariables guard (the kit's seed workaround if Q7 says so)". Q7 says it is not needed, so
this is the minimal guard. Taken before T3, whose `/st dump` prints what this records.

## Goal

At load on Forever the core records, before anything else touches `SpellTunerDB`, whether the
SavedVariables came back: a table from an earlier session (and which session), nothing (a first run
-- or a file the client lost), or a value that is not a table (a broken file, replaced by an empty
table rather than indexed). It stamps the session so the next load can tell, keeps that one line
for `/st dump` (T3) and the debug log, and changes nothing else in the database. No seed
workaround. For the author, whose bug reports then say whether the beta dropped the file, and for
M3, whose recordings live in it.

## Facts

- **Q7 is answered: SavedVariables come back on build 70009.** Every report from the second on reads
  `SpellTunerDB at load: table` with the previous session's stamp (second report onward; the sixth
  and seventh: `previous session stamp: 2026-09-28 09:09:29`, `reports at load: 70009 (...)`, and
  `Q7 answered: SavedVariables came back`), across `/reload`s and relogs -- `docs/probe/1.60.1_70009.md`
  (eighth: `== saved variables (identical to the seventh report)`; seventh via
  `git show ad94b2f:docs/probe/1.60.1_70009.md`). The plan's §1.4 bug ("SavedVariables are not
  always read back at launch", unfixed in 69893; EllesmereUI ships a login notice) has not shown on
  70009. So the kit's workaround (running the saved file as addon code) is **not** built; the
  planner's instruction of 2026-09-28: "T4 does not need the kit's seed workaround; keep the guard
  minimal".
- A first run and a lost file look the same at load (`SpellTunerDB == nil`); nothing on the client
  side can tell them apart without a second witness file. Not built here (Out of scope).
- `Client/Probe.lua` keeps its own stamp in `SpellTunerDB.probe.stamp` and creates `SpellTunerDB`
  at `ADDON_LOADED` if it is not a table (`Client/Probe.lua`, `OnAddonLoaded`). The kernel's event
  frame is created when `Core.lua` loads, before the probe's; `Core_Forever.lua` loads after
  `Core.lua` and before `Client/Probe.lua` (T1b TOC order), so a handler it adds with
  `MD:On("ADDON_LOADED", ...)` runs before the probe's.
- The kernel's `InitDB` (at `PLAYER_LOGIN`) keeps whatever table is in `SpellTunerDB` and fills
  defaults (T1b). The guard must not live in the kernel: `Core.lua` is shared, and a new key in the
  TBC database is a TBC change. `Core_Forever.lua` is Forever-only.
- `date` is a WoW Lua extension (in the 69893 baseline's `functions`; allowed outside `Client/` by
  the reading in T1b / T6).

## Files

| file | change | role |
|---|---|---|
| `Core_Forever.lua` | the guard (below) | Forever's core |
| `tools/svcheck.lua` | new suite, `HARNESS_FLAVOUR = { "forever", "tbc" }` | the guard |

### The guard (`Core_Forever.lua`)

- On `ADDON_LOADED` for this addon's own name (once; later `ADDON_LOADED`s are ignored):
  - `local t = type(SpellTunerDB)`. Record `MD.sv = { atLoad = t }`.
  - `t == "table"`: if `SpellTunerDB.session` is a table whose `stamp` is a string and whose
    `count` is a number, record `MD.sv.prevStamp` and `MD.sv.prevCount`.
  - `t ~= "table"` and `t ~= "nil"`: replace `SpellTunerDB` with `{}` (a broken file is dropped, not
    indexed); `t == "nil"`: `SpellTunerDB = {}`.
  - Then write `SpellTunerDB.session = { stamp = date("%Y-%m-%d %H:%M:%S"), count = (prevCount or 0) + 1 }`.
    Nothing else in `SpellTunerDB` is read or written.
- `MD:SavedVarsLine()` returns exactly one of:
  - `SavedVariables: came back (previous session <prevStamp>, this is session <count>)`
  - `SavedVariables: came back, with no session stamp (first run of this build of SpellTuner)` --
    a table without a usable `session` (a database from the probe alone, or from before this task)
  - `SavedVariables: none at load (a first run, or the client did not read the file back)`
  - `SavedVariables: was a <type>, not a table - replaced with an empty one`
- At `MD_READY`, `MD:Debug("other", "%s", MD:SavedVarsLine())`.

## Rules

- Forever-only: nothing in `Core.lua`, `Core_TBC.lua` or any shared file changes. The TBC database
  gets no `session` key.
- Our own SavedVariables are ours, not client values: `type()` checks before any index are still
  required (a broken file can hold anything), but they need no adapter.
- Rendered strings ASCII, no bare `|`; comments say why.
- Tests first: write `tools/svcheck.lua`, see it fail, then write the guard.
- **Git.** No `git add`, `git stash`, `git checkout -- <path>`, `git reset` or commit; do not touch
  `.git`. Do not open `CLAUDE.md` or any `docs/` file except this task's Report section for writing.

## Acceptance

1. `tools/run.sh --flavour forever tools/svcheck.lua` ends `6 ok, 0 failed`;
   `tools/run.sh --flavour tbc tools/svcheck.lua` ends `1 ok, 0 failed`. Each forever case is a
   fresh load (`dofile` the harness again, with `SpellTunerDB` set in `_G` first, the way the client
   hands it back). Names verbatim:
   1. "a first run says nothing came back and stamps session 1": `SpellTunerDB` nil at load ->
      `MD.sv.atLoad == "nil"`, `MD:SavedVarsLine()` is the `none at load` line,
      `SpellTunerDB.session.count == 1` and `.stamp` a string.
   2. "a returning database names the previous session and keeps everything else": `SpellTunerDB =
      { session = { stamp = "2026-09-27 10:00:00", count = 4 }, char = { ["Penek-Anniversary"] = {
      x = 1 } }, modules = { SpellTuner_Recorder = true }, probe = { stamp = "p", reports = {} } }`
      -> the line reads `SavedVariables: came back (previous session 2026-09-27 10:00:00, this is
      session 5)`; `char`, `modules` and `probe` are the same tables with the same contents; the
      Recorder module is loaded after login (T2).
   3. "a database without a stamp says so": `SpellTunerDB = { probe = { stamp = "p" } }` -> the
      `no session stamp` line, `session.count == 1`.
   4. "a broken database is replaced, not indexed": `SpellTunerDB = "garbage"` -> the harness loads
      without error, the line is `SavedVariables: was a string, not a table - replaced with an empty
      one`, `SpellTunerDB` is a table.
   5. "the guard runs before the probe": in case 1, `SpellTunerDB.probe` exists after load (the
      probe made it) and yet `MD.sv.atLoad == "nil"`.
   6. "the debug log carries the line": in case 3's session, after `MD.db.debug.enabled = true` and
      `MD.DebugLog` replaced by a function that keeps its `(category, text)`, `MD:Fire("MD_READY")`
      delivers `("other", <the no session stamp line>)` exactly once among what it keeps. (The console that normally
      sinks `MD:Debug` arrives on Forever with T3; the harness fires the login events before a
      suite can hook, hence the second `MD_READY`.)
   7. (tbc) "the TBC database gets no session stamp": under the tbc harness `MD.sv` is nil and
      `SpellTunerDB.session` is nil.
2. Every other suite prints the tail it was accepted with (the sixteen TBC suites, probecheck 58,
   forevercheck 13, adaptercheck 15 / 11, corecheck 10 / 8, modulecheck 12); `python3
   tools/apicheck.py` still `0 findings`.
3. `luac -p Core_Forever.lua tools/svcheck.lua` clean.
4. `git status --short`: exactly `M Core_Forever.lua`, `?? tools/svcheck.lua` and this task file.
5. Paste into the Report: both svcheck outputs; the assertions that failed first; the other tails;
   apicheck's last line; `luac`; `git status --short`.

## Out of scope

- The kit's seed workaround, and a second witness file to tell a lost file from a first run: not
  needed while Q7 holds; the planner re-plans if a report shows the file lost.
- Migrating or versioning the database layout; per-character data (M3).
- The probe's own SavedVariables handling.
- `CLAUDE.md` and every `docs/` file except this Report. Commits.

## Report

Implemented as specified; no Facts were false, nothing ambiguous.

**`Core_Forever.lua`**: added the guard right before the `""`/`help`/`modules` command
registrations. `MD:On("ADDON_LOADED", ...)` fires once (a `svHandled` local flag) and only for
`loadedName == ADDON_NAME`. It records `MD.sv = { atLoad = type(SpellTunerDB) }`, then: for a
table with a usable `session` (`stamp` a string, `count` a number) adds `MD.sv.prevStamp` /
`MD.sv.prevCount` and leaves `SpellTunerDB` alone; for anything that is not a table and not nil
replaces `SpellTunerDB` with `{}` (dropped, not indexed); for nil sets `SpellTunerDB = {}`. It
then always writes `SpellTunerDB.session = { stamp = date(...), count = (prevCount or 0) + 1 }`
and touches nothing else in the database. `MD:SavedVarsLine()` renders the four lines verbatim
from the task. A `MD_READY` callback does `MD:Debug("other", "%s", MD:SavedVarsLine())`. Because
`Core.lua`'s event frame (and this handler, registered when `Core_Forever.lua` loads) exists
before `Client/Probe.lua` creates its own frame and registers its own `ADDON_LOADED`, the guard's
`type()` snapshot of `SpellTunerDB` is taken before the probe ever touches
`SpellTunerDB.probe`.

**`tools/svcheck.lua`**: new suite, `HARNESS_FLAVOUR = { "forever", "tbc" }`. Each of the 7 named
cases (6 under forever, 1 under tbc) gets its own fresh `dofile` of `tools/harness.lua` (the
`NewSession(presetDB)` helper copied from `tools/modulecheck.lua`'s pattern), with `SpellTunerDB`
set in `_G` immediately before the dofile so it is an honest fresh load, matching every name in
the Acceptance section verbatim. One deviation from a first literal reading of the task: case 2's
"`char`, `modules` and `probe` are the same tables with the same contents" is checked as reference
equality plus content for `char`/`modules`, but for `probe` only reference equality and that
`probe.reports` is still a table -- `Client/Probe.lua`'s own `OnAddonLoaded` (out of scope here,
unchanged) unconditionally overwrites `SpellTunerDB.probe.stamp` with its own `SafeDate()` on
every load, so asserting the seeded `probe.stamp == "p"` survives is asserting behaviour this task
does not own and that Probe.lua correctly does not preserve. Written first, run, and seen to fail
(0 ok, 6 failed on forever with the expected `attempt to index field 'sv' (a nil value)` /
`attempt to call method 'SavedVarsLine' (a nil value)` errors, `1 ok, 0 failed` on tbc since
`MD.sv` is legitimately absent without the guard) before writing the guard.

### svcheck output, forever (after the guard)

```
a first run says nothing came back and stamps session 1                  ok
a returning database names the previous session and keeps everything else ok
a database without a stamp says so                                       ok
a broken database is replaced, not indexed                               ok
the guard runs before the probe                                          ok
the debug log carries the line                                           ok - hits=1

6 ok, 0 failed
```

### svcheck output, tbc

```
the TBC database gets no session stamp                                   ok

1 ok, 0 failed
```

### First failing run (before the guard existed), forever

```
a first run says nothing came back and stamps session 1                  FAIL - raised: .../tools/svcheck.lua:46: attempt to index field 'sv' (a nil value)
a returning database names the previous session and keeps everything else FAIL - raised: .../tools/svcheck.lua:65: attempt to call method 'SavedVarsLine' (a nil value)
a database without a stamp says so                                       FAIL - raised: .../tools/svcheck.lua:79: attempt to call method 'SavedVarsLine' (a nil value)
a broken database is replaced, not indexed                               FAIL - raised: .../tools/svcheck.lua:87: attempt to call method 'SavedVarsLine' (a nil value)
the guard runs before the probe                                          FAIL - raised: .../tools/svcheck.lua:95: attempt to index field 'sv' (a nil value)
the debug log carries the line                                           FAIL - hits=0

0 ok, 6 failed
```

(tbc, before the guard existed: `1 ok, 0 failed` already, since `MD.sv` is nil and
`SpellTunerDB.session` is nil with no guard at all -- this case only becomes a real
regression test once the guard exists and must still leave TBC untouched, which it does.)

One assertion I had to correct mid-way: my first draft of case 2 also asserted
`_G.SpellTunerDB.probe.stamp == "p"`, which failed (`c7 false`) because `Client/Probe.lua`
overwrites that field on every load regardless of this guard; I narrowed the assertion to
reference equality of the `probe` table plus `probe.reports` still being a table, which is what
the task's Facts/Rules actually put in this guard's scope.

### Every other suite's tail (unchanged from before this task)

```
simcheck      ... -> PASS
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
probecheck    58 ok, 0 failed
forevercheck  13 ok, 0 failed
modulecheck   12 ok, 0 failed
adaptercheck/forever 15 ok, 0 failed
adaptercheck/tbc     11 ok, 0 failed
corecheck/forever    10 ok, 0 failed
corecheck/tbc        8 ok, 0 failed
```

`python3 tools/apicheck.py`: `apicheck: 8 Forever TOCs, 12 files, 37 distinct globals, 0 findings (baseline 69893)`.
`python3 tools/apicheck.py --selftest`: `selftest: 7 of 7 findings as expected`.

### luac

```
$ ./tools/.lua/lua-5.1.5/src/luac -p Core_Forever.lua tools/svcheck.lua
CLEAN (no output -- syntax OK for both files)
```

### git status --short

```
 M Core_Forever.lua
?? docs/tasks/T3-console-dump.md
?? docs/tasks/T4-savedvariables-guard.md
?? tools/svcheck.lua
```

`docs/tasks/T3-console-dump.md` was already untracked before this task started (per the
conversation's initial git status) and is untouched by this work.

Nothing skipped. No `git add`/`stash`/`checkout --`/`reset`/commit was run; `.git` was not
touched.

## Review (lead, 2026-09-28)

Accepted as delivered. Rerun by the lead: svcheck 6 / 1, every other tail unchanged, apicheck 0
findings. The guard is Forever-only, runs before the probe touches the database, type-checks before
it indexes, and writes nothing but `session`. The implementer's one deviation is right: acceptance
case 2 asked for `probe`'s *contents* to be unchanged, but the probe restamps `probe.stamp` at every
load by design -- the lead's line was too literal; identity of the table and `probe.reports`
surviving is what this guard owes.
