# T13a — apicheck: an event argument is asked IsSecret before it is compared

Status: **open**. M3, first task (`docs/ROADMAP-FOREVER.md` M3: "T13a ... lands before T13, whose
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

(implementer)
