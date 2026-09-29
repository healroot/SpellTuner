# T26 -- `/st measure` lines stamped with the version and build that wrote them

Status: handed out 2026-09-29.

## Goal

Every line `/st measure` keeps says which addon version and which client build wrote it.
`/st measure dump` shows only the lines the running version wrote and says how many older ones it
left out; `/st measure dump all` shows every kept line with its stamp; `/st measure clear` empties
the list. So a bug report pasted from 0.16.1 can no longer carry alpha.3's lines as if they were
new. For the author, whose 0.16.0 dump reprinted alpha.3's lines verbatim.

## Facts

- The author's report, 2026-09-29, item 3 (via the planner): `/st measure dump` on 0.16.0 printed
  alpha.3's old lines verbatim, nothing marking them.
- `Spells/Measure.lua` 568-576 `RecordLine(line)`: appends the **string** to
  `SpellTunerDB.measures`, keeps the last 100, prints it with `MD:Print`. 878-894 `Measure:Dump()`:
  a header (`build`, character, level, date) from `MD.API.BuildInfo()`'s second return (escaped,
  `?` when not a plain string), then every stored string, then the `unreadable` and `cast at
  another unit` counters.
- `Core_Forever.lua` 253-261: the `measure` command -- `dump` shows `Measure:Dump()` in
  `MD:ShowCopyPopup`, anything else toggles; usage `/st measure [dump]`.
- `MD.API.AddonVersion()` (`Client/API.lua` 383-388): the TOC's `## Version:` through the flavour's
  AddOnMetadata binding, or nil. The TOCs are the version's single source (T22).
- Lines stored before this task are plain strings with no stamp; they must still be readable (the
  author's SavedVariables holds up to 100 of them).
- `tools/measurecheck.lua` (26) reads `SpellTunerDB.measures[i]` as strings in its helpers
  (`LastLine`, `LinesSince`, 31-50) and item 8 (212-219).

## Files

| file | change | role |
|---|---|---|
| `Spells/Measure.lua` | `RecordLine` stores `{ text = line, version = <AddonVersion() or "?">, build = <BuildInfo's build, plain string, else "?"> }` (still last 100, still prints `line` unchanged); `Measure:Dump(all)`: a stored entry is **current** when it is a table whose `version` equals `MD.API.AddonVersion()`; by default only current entries' `text`, then `N older line(s) from earlier versions not shown - /st measure dump all` when N > 0; with `all` every entry, each prefixed `[<version> <build>] ` (a plain string entry `[before 0.16.1] `); the counters as today; `Measure:Clear()` (new) empties the list and returns how many it removed | measure |
| `Core_Forever.lua` | `measure dump all` -> `Dump(true)`; `measure clear` -> `Clear()` then `MD:Print("measure: cleared N line(s)")`; usage `/st measure [dump [all] / clear]`, help text names all three | the command |
| `tools/measurecheck.lua` | helpers read an entry's `text` (a table) or the string itself; the four assertions below | Forever suite |

## Rules

- `CLAUDE.md`: ASCII-only rendered strings, no bare `|` (a version or build string passes the
  file's existing `Esc` before it is printed); no client call outside `Client/API.lua` (version and
  build only through `MD.API`); no arithmetic on a value that could be secret (the build is checked
  plain before use, as `Dump` already does); no new global; the multi-return trap (`BuildInfo`
  returns several values: take the second with `select(2, ...)` or explicit locals).
- The printed chat line of a measurement is unchanged.
- Tests first: the new assertions against today's code, the failures pasted, then the code.
- **Other implementers are working in this tree at the same time** on `Engine/Practice.lua`,
  `UI/PracticePanel.lua`, `UI/BindingsWindow.lua`, `tools/practiceforever.lua` (T24) and
  `Client/API_Forever.lua`, `UI/SpellTip_Forever.lua`, `tools/wowstub.lua`, `tools/tipcheck.lua`
  (T25). Do not edit those; if you need the stub to answer a version or a build differently, set it
  from inside `measurecheck.lua` (for example by replacing `MD.API.AddonVersion` for one case and
  restoring it). If a suite fails in a file you did not touch, wait a minute, re-run it once, and
  report it.
- Git: no `add`, `stash`, `checkout -- <path>`, `reset`, commit. No `docs/` or `CLAUDE.md` edit except
  this Report.

## Acceptance

1. `bash tools/run.sh tools/measurecheck.lua` ends `30 ok, 0 failed` (26 + 4). New assertions,
   names verbatim:
   1. "each kept line carries the version and build that wrote it" -- after a measurement the last
      entry is a table with `text` equal to the printed line, `version` equal to
      `MD.API.AddonVersion()` and `build` the stub's build string.
   2. "the dump shows this version's lines and counts the older ones" -- with two plain-string
      entries and one table stamped `0.0.1` put before the current ones: the default dump contains
      every current entry's text, none of the three older texts, and the line
      `3 older line(s) from earlier versions not shown - /st measure dump all`.
   3. "dump all shows every line with its stamp" -- `Dump(true)` contains all of them, the older
      ones prefixed `[before 0.16.1] ` / `[0.0.1 <build>] `, the current ones
      `[<version> <build>] `; ASCII, no bare pipe.
   4. "/st measure clear empties the list and says how many" -- through the registered command:
      `SpellTunerDB.measures` is empty afterwards and the printed line names the count; a dump
      afterwards has no measurement lines and no "older" line.
   Item 8 keeps its name and still holds.
2. Unchanged: every other suite of the loop in `docs/TOOLS.md` §1 at `docs/tasks/HANDOVER.md`'s
   Baselines (suites T24 / T25 are changing: report their numbers as you find them).
   `python3 tools/apicheck.py` 0 findings, `--selftest` 10 of 10.
3. Paste: the failing run before the change, the passing run after, `luac -p` of the two changed
   shipped files, the loop's last lines.

Note on the literal `before 0.16.1`: it is the version this ships in (the lead bumps every TOC to
0.16.1 after acceptance); write it as a constant in `Measure.lua` with a comment saying so.

## Out of scope

What a measurement judges or how it pairs casts; the 100 cap; the chat line; the TBC addon; the
files T24 and T25 own.

## Report

(implementer)
