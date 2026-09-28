# T13a — apicheck: an event argument is asked IsSecret before it is compared

Status: **accepted** 2026-09-28 (lead review at the end). M3, first task (`docs/ROADMAP-FOREVER.md` M3: "T13a ... lands before T13, whose
recorder is all event handlers").

## Goal

`python3 tools/apicheck.py` reports every place in a Forever file where an event handler's argument
is compared, used in arithmetic, indexed, measured with `#`, or tested with `type(x) == "number"`
before the same function has asked `IsSecret(x)` about it. On the client a secret number answers
`type(v) == "number"` and raises on the comparison; the stub's secret stand-in is a table, so no
suite can catch the omission -- only reading the source can. For every M3 and M4 file, most of which
are event handlers.

## Facts

- A secret value: arithmetic, comparison, `#`, indexing, use as a table key and calling raise at
  once; storing, passing on, concatenating into a string and `StatusBar:SetValue` do not
  (`FOREVER-PLAN.md` §1.2). `type()` of a secret does not raise and may answer the underlying type
  (`tools/wowstub.lua` header, from EllesmereUI; T9 Review: the tooltip post-call passed an id whose
  `type()` was `"number"` without asking -- the lead's one-line fix).
- The stub's secret stand-in raises on arithmetic, `<`, index, call, concat and `tostring`, but not
  on `==` against a plain value, `#` or table-key use under Lua 5.1 (`CLAUDE.md` file table,
  `Client/Probe.lua` row). So `if unit == "player"` on a secret passes every suite and raises in the
  client.
- The only shapes of handler registration in the Forever files today (lead's grep, 2026-09-28):
  `MD:On("<EVENT>", function(<params>) ... end)` and `MD:On("<EVENT>", <LocalName>)` where
  `<LocalName>` is a `local function <LocalName>(<params>)` in the same file; and the tooltip
  post-call in `Client/API_Forever.lua` (inside `Client/`, exempt). Frame `OnEvent` scripts are not
  used by Forever files outside `Client/`.
- `MD.API.IsSecret(x)` is the shared test; `Client/Probe.lua` has its own local `IsSecret(x)`.

## Files

| file | change | role |
|---|---|---|
| `tools/apicheck.py` | rule 8, below; `--selftest` gains its fixtures | the check |
| `tools/data/apicheck-fixture/` (or wherever the existing selftest fixture lives -- follow it) | one file with four handlers: two that ask first (must pass), two that do not (must be found) | fixture |
| any Forever file rule 8 finds on first run | the one-line `IsSecret` guard, **only** where the finding is real and the fix is a guard before the existing comparison; anything else is a question | fixes |

### Rule 8

For every Forever-TOC file outside `Client/`:
1. Find each handler: an `MD:On(...)` / `MD:On(...)`-shaped call whose second argument is an inline
   `function(<params>)` or a name bound by `local function <name>(<params>)` in the same file.
2. Strip comments and string literals; walk the handler's body to its matching `end` (count
   `function`, `if`, `do` openers -- `for`/`while` contribute their `do` -- and `repeat`/`until`).
3. For each parameter (skip `_`, `self`, `...`), find its first **risky use**: `p ==`, `p ~=`,
   `== p`, `~= p`, `<`, `>`, `<=`, `>=` on either side, `p` next to `+ - * / % ^`, `#p`, `p[`, `p.`,
   `p:`, `p(`, `type(p)`. A use inside the parentheses of a call to a function whose name ends in
   `IsSecret` is a **check**, not a risky use.
4. A finding is a risky use with no check of the same parameter textually before it in the body.
   Reported as `rule 8: <file>:<line> <param> used before IsSecret in the <EVENT> handler`.
5. Known limits, printed by `--report` and written in the docstring: a parameter passed on to
   another function and compared there is not followed; an alias (`local u = unit`) is not
   followed; a check in a branch that does not dominate the use still counts as a check.

## Rules

- `tools/apicheck.py` stays standard-library Python 3; no new dependency.
- Rule 8 applies to Forever-TOC files (the same set the other rules scan, including module TOCs'
  files) and never to `Client/`.
- Tests first: the selftest fixture and its expected two findings before the rule.
- No change to a TBC-only file. A fix in a Forever file is the guard only; say each one in the Report
  with its line before and after.
- **Git:** no `git add`, `stash`, `checkout -- <path>`, `reset`, commit. Do not edit `CLAUDE.md` or
  any `docs/` file except this Report.

## Acceptance

1. `python3 tools/apicheck.py --selftest` ends `9 of 9 findings as expected` (the existing seven plus
   the two rule-8 findings; the two good handlers raise nothing). T13c lands first, so the
   existing count is 8 and this becomes **`10 of 10`**.
2. `python3 tools/apicheck.py` 0 findings on the tree after the fixes; paste the first run's rule-8
   findings (before any fix) in full.
3. Every suite at its count (the lead's baseline when this is handed out: parsecheck 11, bookcheck 15,
   spellsui 15, clockcheck 15, measurecheck 18, probecheck 73, modulecheck 14 (T13c), forevercheck
   13; the TBC sixteen; adaptercheck 19/15, corecheck 10/8, svcheck 6/1, consolecheck 11/1).
4. `luac -p` on any Lua file touched.
5. Paste into the Report: the failing selftest; the selftest and the full run after; the first-run
   findings; each fix; every suite tail; `git status --short`.

## Out of scope

- Following values across functions (a data-flow analysis). The TBC files. `Client/`.
- `CLAUDE.md`, every `docs/` file except this Report. Commits.

## Report

### Files touched

- `tools/apicheck.py` -- added rule 8: `Rule8Finding` (renders `rule 8: <file>:<line> <param>
  used before IsSecret in the <EVENT> handler`), a pair of source-text stripping helpers
  (`strip_comments` keeps string literals so an `MD:On("EVENT", ...)` call's event name and a
  named handler's identifier can still be read; `strip_source` blanks both comments and string
  literals, same length/newlines preserved, for body scanning so `end`/`if`/operator tokens
  inside a comment or a log string are never counted), `find_block_end` (the `function`/`if`/
  `do`/`repeat`/`until`/`end` stack walk from the spec), `param_names`, `check_positions`
  (`IsSecret`-suffixed calls with the param among their comma-split args), `first_risky_use`
  (the ten patterns from the task: `==`/`~=`/`<`/`>`/`<=`/`>=` either side, arithmetic either
  side, `#p`, `p[`, `p.`, `p:`, `p(`, `type(p)`), and `scan_rule8` which finds both handler
  shapes (`MD:On("EVENT", function(...) ... end)` and `MD:On("EVENT", Name)` with `Name` a
  same-file `local function`), skips `Client/`, and reports the first unguarded risky use per
  parameter. Wired into `main()` right after the existing `scan_file` call. Docstring extended
  with rule 8's one-line description and the known limits, verbatim from the task. Selftest's
  `expected` list gained the two rule-8 fixture findings and the `Gone.lua` line number moved
  from 6 to 7 (the new fixture file shifted the TOC by one line).
- `tools/data/apicheck-fixture/Handlers.lua` (new) -- four handlers: `UNIT_HEALTH_GOOD` (inline
  function) and `UNIT_AURA_GOOD` (named, via `local function OnAuraGood`) each ask
  `MD.API.IsSecret(unit)` before `unit == "player"` and raise no finding; `UNIT_HEALTH_BAD` and
  `UNIT_AURA_BAD` (same two shapes) compare `unit == "player"` with no guard and are both found,
  at lines 21 and 27.
- `tools/data/apicheck-fixture/Fixture_Mainline.toc` -- added `Handlers.lua` between `Bad.lua`
  and `Gone.lua`.
- `Core_Forever.lua` -- the one real finding, the one-line guard:
  - before: `    if svHandled or loadedName ~= ADDON_NAME then return end`
  - after: `    if svHandled or MD.API.IsSecret(loadedName) or loadedName ~= ADDON_NAME then return end`

### Failing selftest

Tests first, per the task: I wrote the fixture (`Handlers.lua` + its `Fixture_Mainline.toc`
line) before touching `apicheck.py`'s rule set. Confirmed it fails against the HEAD (007d1d1)
version of the script -- both because rule 8 does not exist yet and because the new fixture
file shifts `Gone.lua` from TOC line 6 to line 7 (run by temporarily copying `git show
HEAD:tools/apicheck.py` into `tools/` so its own path resolution works, then removing it again;
nothing tracked was changed):

```
FAIL Bad.lua:1 GetSpellInfo not in baseline 69893
FAIL Bad.lua:2 os not in the client's Lua
FAIL Bad.lua:3 UnitHealth client call outside Client/
FAIL Bad.lua:4 NewGlobalName new global
FAIL Bad.lua:5 COMBAT_LOG_EVENT_UNFILTERED COMBAT_LOG_EVENT_UNFILTERED named
FAIL Bad.lua:6 C_Spell.NoSuchMember C_ member not in baseline 69893
FAIL Fixture_Mainline.toc:7 Gone.lua missing file
FAIL Modules/Sample/Sample_Mainline.toc:7 Missing.lua missing file
selftest: FAILED
expected: [..., ('Fixture_Mainline.toc', 6, 'Gone.lua', 'missing file'), ...]
actual:   [..., ('Fixture_Mainline.toc', 7, 'Gone.lua', 'missing file'), ...]
```

(the two rule-8 `Handlers.lua` findings are simply absent from `actual` since rule 8 does not
exist in that version -- the diff printed above is the first mismatch found, `Gone.lua`'s line
number, which is enough to fail the run).

### First run's rule-8 findings (before the `Core_Forever.lua` fix), full output

```
$ python3 tools/apicheck.py
rule 8: Core_Forever.lua:45 loadedName used before IsSecret in the ADDON_LOADED handler
apicheck: 8 Forever TOCs, 24 files, 40 distinct globals, 1 findings (baseline 69893)
```

This is the `ADDON_LOADED` guard added by T4/the SavedVariables guard: `loadedName ~=
ADDON_NAME` compared with no `IsSecret` check first. I judged it a real finding (not a
question) -- it is exactly the shape the task describes, the fix is the same one-line
`IsSecret(x) or` guard used everywhere else in the tree (`UI/Clock_Forever.lua`,
`Spells/Book.lua`, `Spells/Measure.lua` all already do this for their `unit`/`spellID`
parameters), and it costs nothing: on a secret `loadedName` the handler now returns without
setting `svHandled`, so the guard is retried on the next `ADDON_LOADED` rather than raising.

Every other `MD:On(...)` handler in the Forever file set (`Core.lua` PLAYER_LEVEL_UP,
`UI/Clock_Forever.lua` UNIT_SPELLCAST_SUCCEEDED, `Spells/Book.lua` UNIT_AURA,
`Spells/Measure.lua`'s three OnCastSucceeded/OnUnitCombat/OnTargetChanged) already guards with
`MD.API.IsSecret(...)` before any comparison, so rule 8 found nothing else.

### Selftest after the fix (10 of 10)

```
$ python3 tools/apicheck.py --selftest
FAIL Bad.lua:1 GetSpellInfo not in baseline 69893
FAIL Bad.lua:2 os not in the client's Lua
FAIL Bad.lua:3 UnitHealth client call outside Client/
FAIL Bad.lua:4 NewGlobalName new global
FAIL Bad.lua:5 COMBAT_LOG_EVENT_UNFILTERED COMBAT_LOG_EVENT_UNFILTERED named
FAIL Bad.lua:6 C_Spell.NoSuchMember C_ member not in baseline 69893
FAIL Fixture_Mainline.toc:7 Gone.lua missing file
rule 8: Handlers.lua:21 unit used before IsSecret in the UNIT_HEALTH_BAD handler
rule 8: Handlers.lua:27 unit used before IsSecret in the UNIT_AURA_BAD handler
FAIL Modules/Sample/Sample_Mainline.toc:7 Missing.lua missing file
selftest: 10 of 10 findings as expected
```

### Full run after the fix (0 findings)

```
$ python3 tools/apicheck.py
apicheck: 8 Forever TOCs, 24 files, 40 distinct globals, 0 findings (baseline 69893)
```

### Every suite (docs/TOOLS.md §1 loop, run in full)

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

The first sixteen of the plain loop above (`simcheck` through `migrate`) are the "TBC sixteen"
named in Acceptance #3 -- every one at 0 failed. Every named count in Acceptance #3 matches
exactly (parsecheck 11, bookcheck 15, spellsui 15, clockcheck 15, measurecheck 18, probecheck
73, modulecheck 14, forevercheck 13; adaptercheck 19/15, corecheck 10/8, svcheck 6/1,
consolecheck 11/1).

### `luac -p` on every file touched

```
$ luac -p Core_Forever.lua && echo OK
OK
$ luac -p tools/data/apicheck-fixture/Handlers.lua && echo OK
OK
```

`tools/apicheck.py` is Python, not Lua; checked with `python3 -c "import py_compile;
py_compile.compile('tools/apicheck.py', doraise=True)"`, which reported no error.

### git status --short

```
 M Core_Forever.lua
 M docs/tasks/HANDOVER.md
 M tools/apicheck.py
 M tools/data/apicheck-fixture/Fixture_Mainline.toc
?? tools/data/apicheck-fixture/Handlers.lua
```

`docs/tasks/HANDOVER.md` is the lead's pre-existing modification from before this task started
(handing the task out) -- I did not touch it.

### Skipped / questions

Nothing skipped; no open question. The one real finding (`Core_Forever.lua:45`) was fixed with
a one-line guard matching the existing pattern used elsewhere in the tree. No other Forever
file outside `Client/` had an unguarded risky use of an event-handler parameter.

## Lead review (2026-09-28)

Accepted as delivered. The lead reran every suite (all at the baseline; apicheck 0 findings,
`--selftest` 10 of 10, refcheck ok) and `luac -p` on the two Lua files. The one real finding and
its guard (`Core_Forever.lua` line 45, `ADDON_LOADED`) are right: a Forever-only file, the guard
before the existing comparison. Known false positive, accepted: a parameter's name used as a field
(`t.unit == x`) matches the word pattern; rename or guard if it ever fires.
