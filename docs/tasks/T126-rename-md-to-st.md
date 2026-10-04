# T126: MD -> ST, and /md removed

Author (2026-10-04): "lets move from MD short (from mana demon) to spelltuner
shortcut, as it may confuse". Rulings: **both** the player-facing command and the
code namespace; **/md is removed** (not kept as an alias).

## 1. Player-facing

- `Core.lua` and `Client/Probe.lua`: drop `SLASH_SPELLTUNER3 = "/md"`. `/st` and
  `/spelltuner` stay.
- Every string a player can see that says `/md` says `/st` (chat lines, hints,
  tooltips, Settings/About text, dump lines, locale-like literals): regex
  `/md\b` -> `/st` in shipped Lua. Check `/st` answers every verb `/md` did (one
  handler; confirm no verb is registered under `/md` only).
- Saved-variables adoption of `ManaDemonDB` stays exactly as is (that is data
  migration, not a name players type).

## 2. Code namespace

- The addon table alias `MD` becomes `ST` in every Lua file: shipped files,
  `Modules/*`, and `tools/` (harness, stubs, suites). Word-boundary identifier
  only (`\bMD\b`): `MD_READY` and other event / constant names containing `MD_`
  are NOT renamed in this task. Comments that say `MD.Foo` follow.
- **Collision:** `ST` is today the local alias for SpendTracker
  (`Engine/SpendTracker.lua`, `UI/Summary.lua`, `UI/Dashboard_Waste.lua`,
  `Engine/TTO.lua`, `tools/tbcclasscheck.lua`). Rename that local to `SPEND`
  first, then do the namespace. Check every other `\bST\b` before the switch.
- `_G.SpellTuner` stays the global.
- Strings that are data keys or saved formats are not identifiers: grep for
  `"MD"` / `'MD'` literals and decide one by one (report each).

## 3. Docs

- `CLAUDE.md`: every `MD.` / `MD:` / `/md` -> `ST.` / `ST:` / `/st`; rewrite the
  sentence about the `MD` alias (now `ST`; `/md` removed in T126; `ManaDemonDB`
  still adopted). Keep it short.
- `docs/TESTING.md`, `docs/TOOLS.md`: `/md` -> `/st`, `MD.` -> `ST.`.
- Historical docs (`docs/HISTORY.md`, `DECISIONS.md`, specs, debates, reviews,
  tasks, probe reports, mockups) are NOT rewritten.
- `CHANGELOG.md` under `## 0.17.1`: "/md is gone: use /st (or /spelltuner)."

## 4. Verify

Golden suites regenerated where their text changed (`--golden`), counts in
`tools/data/expected-counts.json` unchanged unless a test was added/removed;
`luac -p` every changed file; grep proves zero `\bMD\b` in `*.lua` and zero
`/md\b` in shipped Lua (outside the ManaDemonDB comment, if any); apicheck 0,
textcheck 0. Full `make check` is run by a gate-runner after.
