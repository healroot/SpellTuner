# T0d — the probe stops registering the combat log, and Q1 stays answered

Status: **done -- lead-accepted 2026-09-28** (written and implemented the same day; see the Review at the end). Follows T0c (`docs/tasks/T0c-probe-secrets.md`)
and the sixth to ninth reports from build 70009. First task of M1 (`docs/ROADMAP-FOREVER.md` §2):
every M1 suite asserts that nothing on the Forever TOC registers `COMBAT_LOG_EVENT_UNFILTERED`,
and today `/st probe clog` does.

## Goal

`Client/Probe.lua` never registers `COMBAT_LOG_EVENT_UNFILTERED`, on load or on any command:
`/st probe clog` is gone (typing it prints one line saying so and does nothing else), and the
`== events` section says the event is never registered. And the to-do list's Q1 line, once a run
of a build has answered it, stays answered on every later run of that build instead of flipping
back to "to do" when nothing changed between two runs. For the author, who keeps running the probe
on the beta, and for every later Forever suite, which can then assert "no frame ever tried the
combat log" without an exception for the probe.

## Facts

- **Registering `COMBAT_LOG_EVENT_UNFILTERED` on Forever is forbidden.** The `RegisterEvent` call
  returns normally, then the client fires `ADDON_ACTION_FORBIDDEN` (function `UNKNOWN()`) and shows
  the "blocked from an action only available to the Blizzard UI" dialog. Sixth report (in
  `git show ad94b2f^:docs/probe/1.60.1_70009.md`, the file's lines 609-611 and "What the sixth
  report settles"): `ADDON_ACTION_FORBIDDEN phase=ooc during=clog addon=SpellTuner
  function=UNKNOWN() n=2`, and "Rule for Forever: nothing registers `COMBAT_LOG_EVENT_UNFILTERED`,
  not even under pcall." Restated in `docs/FOREVER-PLAN.md` §1.2 ("No Forever file registers it,
  not even under pcall").
- The only registration of it on the Forever TOC is `RegisterClog()` (`Client/Probe.lua:1348-1362`),
  reached from the slash handler's `probe clog` branch (`:1371`). `EventsSummaryLines()`
  (`:413-434`) prints one of three CLEU lines depending on `clogOutcome`. `doing = "clog"` is one of
  the documented `doing` values (`:195`). Read in the code, 2026-09-28.
- **Q1's answer is not sticky.** Ninth report (`docs/probe/1.60.1_70009.md`, the last section):
  "Q1 is judged only against the previous run, so a run with no change flips an answered Q1 back
  to 'to do'; the answer should be sticky (kept per build in SavedVariables, as Q7's stamp is).
  For T0d." In the code: the Q1 line is computed from `q1Info` (`Client/Probe.lua:1095-1118`),
  which `AgainstPreviousLines` fills from the previous record for this build
  (`SpellTunerDB.probe.reports[buildKey]`, `:673-675`); the record saved at `:1178-1186` keeps no
  Q1 answer.
- SavedVariables come back on build 70009 (Q7, answered in every report from the second on), so a
  per-build field in `SpellTunerDB.probe.reports[build]` survives a `/reload`.
- `tools/probecheck.lua` holds 57 assertions today (`57 ok, 0 failed`, run by the lead on
  2026-09-28). Four of them name the clog path: "registering a bad event is caught" (`:355-359`),
  "COMBAT_LOG_EVENT_UNFILTERED is not registered at load, only by clog" (`:514-516`), "a blocked
  action at load names the registration that caused it" (`:518-524`), and "the probe never raises"
  counts `step5ClogOk` (`:301`).
- `tools/wowstub.lua`'s `FrameMT:RegisterEvent` raises `unknown event` under the forever profile
  for any event outside `FOREVER_EVENTS`, unless `S.forbidOnRegister[e]` names it (`:227-247`).

## Files

| file | change | role |
|---|---|---|
| `Client/Probe.lua` | `RegisterClog` and the `clog` branch removed; `clogOutcome` removed; the CLEU line in `== events` fixed; `/st probe clog` prints a one-line notice; Q1 kept per build | the probe |
| `tools/wowstub.lua` | `S.raiseOnRegister` (below) | the stub |
| `tools/probecheck.lua` | the four clog assertions re-pointed, one new assertion, step 5 extended | the probe's suite |

### `Client/Probe.lua`

1. Delete `RegisterClog()` and `clogOutcome`. No code path in the file may pass
   `"COMBAT_LOG_EVENT_UNFILTERED"` to `RegisterEvent`; after this task the exact string constant
   `"COMBAT_LOG_EVENT_UNFILTERED"` appears nowhere in the file outside comments (a longer string
   that contains it, like the report line below, is fine).
2. `EventsSummaryLines()` ends with exactly one line, always:
   `COMBAT_LOG_EVENT_UNFILTERED never registered (forbidden on Forever)`.
3. The slash handler: `probe clog` prints exactly
   `SpellTuner probe: clog is gone - the combat log registration is forbidden on Forever. Type /st probe.`
   and does **not** run the probe (a run saves a record, which would move the "previous run" every
   later comparison reads). The fallback usage line becomes `SpellTuner probe: type /st probe`.
4. Remove `"clog"` from the documented `doing` values comment.
5. **Q1 kept per build.** When this run answers Q1 (today's `Q1 answered: ...` branch), the saved
   record gets `q1 = { at = <this run's SafeDate()>, text = <the line with the leading
   "Q1 answered: " removed> }`. When this run does not answer it, and the previous record for this
   build has a `q1` table whose `at` and `text` are both strings, the to-do line is
   `Q1 answered (kept from <at>): <text>` and the new record carries that same `q1` table forward.
   Otherwise the `Q1 to do: ...` line as today. A record for another build is never consulted.
   `at` and `text` are our own strings read back from SavedVariables: `type(...) == "string"` is
   checked before use, and they are printed as stored (T0c's "escape once").

### `tools/wowstub.lua`

`S.raiseOnRegister`: a table a script may set; under the forever profile, `RegisterEvent(e)` with
`S.raiseOnRegister[e]` true raises `unknown event "<e>"` (checked after `forbidOnRegister`, before
the `FOREVER_EVENTS` check). Default nil; nothing else in the stub changes.

### `tools/probecheck.lua`

- Step 2 sets `S.raiseOnRegister = { UNIT_FLAGS = true }` right after `S.UseProfile("forever")`,
  so "a bad event is caught" has a bad event that is not the combat log.
- Step 2's `Do(SlashCmdList.SPELLTUNER, "probe clog")` stays, between `clogBefore2` and
  `clogAfter2`.
- Step 5: `local clogAfter5 = ClogAttempts(S5)` right after the `step5ClogOk` line. After `reportB`,
  one more run with nothing changed: `local okB2, reportB2 = pcall(MD5.Probe.Run)`; `okB2` joins
  "the probe never raises".

## Rules

T0/T0b/T0c's rules stand: client calls in `Client/` only; no arithmetic, comparison, `#` or table
key on a client value before `IsSecret`; every client call under `pcall`; rendered strings ASCII,
no bare `|`, client strings through `Esc`; the multi-return trap (`a and f() or b` is never
written); no new globals; comments say why, not what.

- **Tests first.** Change `tools/wowstub.lua` and `tools/probecheck.lua` first, run probecheck
  against today's `Client/Probe.lua`, and see the re-pointed and new assertions fail. Say in the
  report which failed. Never weaken an assertion to make it pass.
- If making step 2 raise on `UNIT_FLAGS` breaks an assertion not named below, stop and report
  which, with its output; do not adjust it.
- **Git.** No `git add`, `git stash`, `git checkout -- <path>`, `git reset` or commit. Do not open
  `CLAUDE.md` or any `docs/` file except this one's Report section for writing.

## Acceptance

1. `tools/run.sh tools/probecheck.lua` ends with `58 ok, 0 failed`: the 57 existing names, four of
   them with the conditions below, and one new one.
   - "registering a bad event is caught": report1 has
     `COMBAT_LOG_EVENT_UNFILTERED never registered (forbidden on Forever)`, `ok UNIT_COMBAT` and
     `throws UNIT_FLAGS <error:`; report3 has `throws UNIT_FLAGS <error:` and
     `COMBAT_LOG_EVENT_UNFILTERED never registered (forbidden on Forever)`, and does not contain
     `by /st probe clog`.
   - "COMBAT_LOG_EVENT_UNFILTERED is not registered at load, only by clog" is **renamed**
     "COMBAT_LOG_EVENT_UNFILTERED is never registered, not even by clog": `clogBefore2 == 0`,
     `clogAfter2 == 0`, `clogBefore5 == 0`, `clogAfter5 == 0`; chat2 contains
     `SpellTuner probe: clog is gone - the combat log registration is forbidden on Forever. Type /st probe.`
     and does not contain `registering COMBAT_LOG_EVENT_UNFILTERED`.
   - "a blocked action at load names the registration that caused it": reportB has
     `ADDON_ACTION_FORBIDDEN phase=ooc during=register:UNIT_FLAGS addon=SpellTuner function=Frame:RegisterEvent() n=1`
     and does **not** contain `during=clog`; `probeFrame5.attempts[1] == "ADDON_ACTION_FORBIDDEN"`
     and `attempts[2] == "ADDON_ACTION_BLOCKED"`; chat5 does not contain
     `registered without a Lua error`.
   - "the probe never raises": also `okB2`.
   - **New** "Q1 stays answered on a later run of the same build": reportB has a line starting
     `Q1 answered: `; reportB2 has `Q1 answered (kept from ` followed, after `): `, by exactly the
     text that follows `Q1 answered: ` on reportB's line; reportB2 has no `Q1 to do`;
     `SpellTunerDB.probe.reports["70009"].q1` is a table whose `text` equals that same text.
2. The sixteen TBC suites print exactly the tails they print today: simcheck `... -> PASS`;
   reccheck 54, replaycheck 80, replayui 98, runcheck 78, reviewui 44, navui 25, dashui 56,
   regencheck 27, simwindow 8, solvercheck 70, timeline 27, spelltip 48, practice 74,
   practiceui 49, migrate 7, each `ok, 0 failed` (the loop in `docs/TOOLS.md` §1).
3. `tools/.lua/lua-5.1.5/src/luac -p Client/Probe.lua tools/wowstub.lua tools/probecheck.lua` is
   clean, and `tools/.lua/lua-5.1.5/src/luac -l -p Client/Probe.lua | grep -c '"COMBAT_LOG_EVENT_UNFILTERED"'`
   prints `0`.
4. `git status --short` shows exactly `M Client/Probe.lua`, `M tools/wowstub.lua`,
   `M tools/probecheck.lua` and this task file.
5. Paste into the Report: the full probecheck output; which assertions failed before the probe
   change; the sixteen tails; the two `luac` commands and their output; reportB2's `== to do`
   section; report1's `== events` section; `git status --short`.

## Out of scope

- Every other `Client/Probe.lua` behaviour: the functions list, the secrets and readings sections,
  the damage meter, the per-token `UNIT_COMBAT` counting the seventh report suggested, the
  gross-or-effective HEAL question, `ShouldUnitHealthMaxBeSecret("party1")` (eighth report). They
  are for a later probe task.
- `Client/API.lua`, the TOCs, `Core.lua` and everything on the TBC line.
- `FOREVER_EVENTS` and the stub's default behaviour for the combat log (T5 makes it
  client-faithful).
- Any `docs/` file other than this Report section; `CLAUDE.md`. Commits.

## Report

(Condensed by the lead from the implementer's hand-back; the implementer did not write into this
section.)

Tests first: `tools/wowstub.lua` (`S.raiseOnRegister`) and `tools/probecheck.lua` changed before
the probe; against the unmodified `Client/Probe.lua` probecheck read `54 ok, 4 failed` -- exactly
"registering a bad event is caught", "COMBAT_LOG_EVENT_UNFILTERED is never registered, not even by
clog", "a blocked action at load names the registration that caused it" and "Q1 stays answered on a
later run of the same build". No other assertion was affected by making step 2 raise on
`UNIT_FLAGS`.

`Client/Probe.lua`: `RegisterClog`, `clogOutcome` and the `"clog"` doing-state removed; the
`== events` section ends with `COMBAT_LOG_EVENT_UNFILTERED never registered (forbidden on
Forever)`; `/st probe clog` prints the notice and runs nothing; `PreviousQ1(buildKey)` reads only
this build's record, type-checks `at` / `text`; the to-do line prints `Q1 answered (kept from
<at>): <text>` when this run does not answer and the record does; the saved record carries `q1`.

After: probecheck `58 ok, 0 failed`; the sixteen TBC tails unchanged; `luac -p` clean;
`luac -l -p Client/Probe.lua | grep -c '"COMBAT_LOG_EVENT_UNFILTERED"'` prints `0`. reportB2's
first to-do line: `Q1 answered (kept from 2025-09-04 15:33:20): 1 of 4 spell descriptions changed
when bonus healing went 0 -> 0, bonus damage ... -> ..., level 9 -> 10`.

Surprising: `git diff --stat` failed with `object file .../a3/42ee79... is empty`. See the Review.

## Review (lead, 2026-09-28)

Accepted. Diff read against the T0c versions of the two tools files (a byte-identical copy, since
`git diff` cannot read HEAD's blobs -- below). Every acceptance line checked by rerunning:
probecheck `58 ok, 0 failed`; the sixteen TBC suites print their tails unchanged; both `luac`
commands clean / `0`. No client call added, no global, no non-ASCII rendered string; the kept-Q1
text is our own string, type-checked before use.

**Repository damage found while reviewing (not the implementer's doing; escalated):** twelve loose
objects in the shared store `/home/penek/projects/addons/SpellTuner/.git/objects` are zero-byte
files, dated 2026-09-27 21:32 and 2026-09-28 05:53-05:58. Five are reachable from this branch's
HEAD: the blobs of `SpellTuner.toc` (`2326ffd`) and `SpellTuner_Mainline.toc` (`24e74ee`), the
`tools/` tree (`63a2beb`), and the T0c blobs of `tools/probecheck.lua` (`a342ee7`) and
`tools/wowstub.lua` (`24920d1`). Identical copies exist (git hashes match): the two TOCs in this
worktree, the two tools files in the lead's session scratchpad `pre/tools/`. The lead did not
repair the store (the permission system refused the write); commits on top still work, but
`git diff`/`log -p` against those objects fail until someone restores them.
