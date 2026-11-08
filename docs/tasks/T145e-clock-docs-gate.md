# T145e: clock v3 -- the docs and the gate

Unit U5 of `docs/SPEC-clock-v3.md` (section 5), size S. After T145d.

## Goal

- `CLAUDE.md`: the clock rows -- `Engine/ClockWords.lua`, `UI/ClockStore.lua`, `UI/ClockBar.lua` added;
  `UI/ClockView.lua` gone; `UI/ClockSettings.lua`, `Engine/ClockFace.lua`, `UI/Clock_Forever.lua`,
  `UI/Widget.lua` rows say what is true after v3. (The lead's brief for this unit asks for it; it is the
  one exception to "do not edit CLAUDE.md".)
- `docs/TOOLS.md`: the clock suites and their counts; `tools/data/expected-counts.json` matches a green
  `make check`.
- `docs/DECISIONS.md`: D1-D3 and the quiet-pool rule with its VERIFY already recorded (T145a); the clock
  open items closed or restated.
- `docs/TESTING.md` section 66: the in-game test of v3 (Forever about 5 minutes, then TBC 2 minutes),
  including the 3 s quiet-full VERIFY (spec 5, U5).
- `CHANGELOG.md`: the next version's section (the look reset, the line on, Line and Compact gone).
- `docs/HISTORY.md`: a dated entry.
- The import fixture rebuilt if what is stored changed.

## Files

`CLAUDE.md`, `docs/TOOLS.md`, `docs/DECISIONS.md`, `docs/TESTING.md`, `CHANGELOG.md`, `docs/HISTORY.md`,
`tools/data/expected-counts.json`, `tools/data/import-forever-sv.lua` (if needed).

## Acceptance

- `make check` green; `textcheck` clean.
- Every removed `CV` / `CF` name is gone from the docs' file table.

## Report

`docs/review/T145de-implementer-report.md` (with T145d).
