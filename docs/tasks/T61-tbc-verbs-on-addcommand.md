# T61 -- The TBC verbs onto `MD:AddCommand` (plan P17)

Status: **built** 2026-09-30 on branch `plan/P17` (base `8c4cc93`), wave 6 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator.

## The task (docs/PLAN-refactor-ux.md section 5, P17)

Review item (`docs/review/2026-09-30-project-review.md`): A1, the TBC half -- "the command layer
exists three times". `Core.lua` had a registry (`MD:AddCommand`, `ShowCommands`) only Forever used;
TBC kept its own `MD.COMMANDS` list (read by `UI/Options_About.lua`) and a 100-line
`MD.SlashFallback` if-chain, and nothing asserted the two agreed. Section 6 also folds A31's "dead
command code" into this task.

- First, before any edit: new `tools/slashcheck.lua` (tbc) runs every TBC verb and alias under the
  stub and records the chat lines and the functions called -- a golden transcript committed on the
  parent commit.
- Then `Core_TBC.lua`'s if-chain becomes `MD:AddCommand` registrations **in `Core_TBC.lua`** (no
  verb moves file), in `MD.COMMANDS`' order so the generated help is byte-identical, aliases
  registered as hidden aliases. `MD.SlashFallback` and `MD.COMMANDS` are deleted; `MD:Commands()`
  (Core.lua) feeds `UI/Options_About.lua` and the unknown-verb help.
- Tests: `slashcheck` equal to its golden; `corecheck` +2 (every registered verb appears in
  `MD:Commands()`; an alias runs its verb and is not listed twice).
- TBC: structure only; byte-identical output.

Owned files (section 4, wave 6): `Core_TBC.lua`, `Core.lua`, `UI/Options_About.lua`,
`tools/corecheck.lua`, new `tools/slashcheck.lua`. Nothing else was touched (this task file apart).

## What was built

| file | change |
|---|---|
| `tools/slashcheck.lua` | New, tbc, 8 assertions. Committed alone first (`b308e29`), passing on the parent's shipped files. Details below. |
| `Core.lua` | The registry is one list of entries `{ name, fn, usage, text, hidden, aliases }` in registration order plus a name/alias -> entry map. `MD:AddCommand(name, fn, usage, text, hidden)` -- `hidden` (new, optional) keeps a verb out of the help and the About tab; registering a name again replaces its function and row **in place** (it used to append a second help row). New `MD:AddAlias(alias, name)` -- a second spelling that runs the verb's function, recorded under the verb, never a row; it raises naming both when the verb is not registered. New `MD:Commands()` -- copies of every entry in order (`name`, `usage`, `text`, `hidden`, `aliases`). `MD:ShowCommands()` prints the non-hidden rows and wraps each usage in `MD.COMMAND_USAGE_COLOR` when a flavour core sets one (nil on Forever: its help prints as before). The dispatcher looks the verb up in the map and otherwise prints the help; the `MD.SlashFallback` branch is gone. |
| `Core_TBC.lua` | `MD.COMMANDS`, `ShowHelp` and `MD.SlashFallback` are gone. In their place, in the same file and in `MD.COMMANDS`' row order: `MD.COMMAND_USAGE_COLOR = "ffffff00"` and 29 `MD:AddCommand` calls, each body the if-chain branch verbatim and each usage/text the old row verbatim. `unlock` (named on lock's row, `/st lock, unlock`) and `help` (never a row) are hidden; `config` / `settings` -> `options`, `bindings` -> `binds`, `tip` -> `tooltip`, `calib` -> `calibrate` are aliases. The file header says so. |
| `UI/Options_About.lua` | The Commands pane reads `MD:Commands()`, skipping hidden entries, `c.usage` / `c.text` in place of `c[1]` / `c[2]`. Same rows, same order, same layout. |
| `tools/corecheck.lua` | +2 under both flavours (22 -> 24 / 22 -> 24), below. |

### `tools/slashcheck.lua`

`tools/run.sh tools/slashcheck.lua [--print | --golden]`. Loads the TBC harness and drives
`SlashCmdList.SPELLTUNER` with 60 inputs: `""`, `help`, `options` / `config` / `settings`, `lock`,
`unlock`, `reset`, `mute` x2, `drink` x2, `rest` x2, `practice`, `practice start`, `practice Start`,
`binds` / `bindings`, `spelltip` x2, `tooltip` / `tip`, `window 30 / 5 / 60 / 4 / 61 / abc / (none)`,
`verify`, `profile`, `export`, `calibrate` / `calib`, `fsrtest`, `regentest` (none, `45`, `clear`),
`spamtest`, `simrun`, `simreplay` (none, `fixture`, `2`), `coach` (none, `1 force`, `cancel`), `sim`,
`replay` (none, `2:7 force`, `run 2`), `run start Blood Furnace`, `run status`, `run stop`,
`coachrun` (none, `1`), `debug`, an unknown verb, `  MUTE  `, `Mute`, `RUN Start The Underbog`
(the raw tail's case kept).

Per input it records every chat line (the version replaced by `{version}`), every call into the 24
functions the verbs reach (the dashboard, options, widget, practice, bindings, the diagnostics, the
simulator, the replay, the run recorder, the debug console) as `call MD:Name(args)` -- they are
spies; `tools/verifycheck.lua` runs the diagnostics for real -- and every watched setting it changed
as `db.key: before -> after` (plus `cdb.practiceSetup` appearing). Two passes: **spied**, then
**bare** with all 24 functions absent (each verb's `if MD.X` guard). Then it loads `UI/Style.lua` and
`UI/Options_About.lua`, fires `ShowOptionsTab("about")` and reads back the command rows the pane
painted. 123 entries in all, compared line for line with the golden captured on `8c4cc93` with
`--golden` and pasted in.

Assertions: the golden has every entry; the spied pass, the bare pass and the About rows each equal
the golden (one assertion per group, naming the first differing verb and line); no verb raised; every
verb but the bare one says or does something with the spies in place; every chat line and About row
is ASCII with no bare pipe; the help is its heading and 27 rows.

### `tools/corecheck.lua` (+2, both flavours)

- **every verb is in MD:Commands() and the help is its listed rows (A1)** -- each flavour's verb set,
  typed in the suite (tbc: 29 names and the five aliases; forever: `debug`, `dump`, `""`, `help`,
  `tooltip`, `clock`, `measure`, `ui`, `spell`, `modules`, `probe`), is in `MD:Commands()` both ways
  (nothing missing, nothing unexpected but corecheck's own `t1btest`), no name twice, each alias under
  its verb; the non-hidden entries, in order, are exactly the rows `/st help` prints; on tbc
  `MD.COMMANDS` and `MD.SlashFallback` are nil.
- **an alias runs its verb and is not listed twice (A1)** -- `MD:AddAlias("t1balias", "t1btest")`,
  then `/st T1BAlias Blood Furnace` reaches t1btest's function with `blood furnace` / `Blood Furnace`,
  `MD:Commands()` has one `t1btest` entry and none named `t1balias` (t1btest is registered a second
  time here, so this also holds the in-place replacement); on tbc `/md calib` runs `RunCalibrate` once
  and the help mentions calibrate on one row only.

## Tests first

1. **The golden, on the parent.** `tools/slashcheck.lua` was written and its golden captured with the
   parent's `Core.lua`, `Core_TBC.lua` and `UI/Options_About.lua` untouched, then committed on its own
   (`b308e29`): `8 ok, 0 failed`, rc 0. It passes on the parent by construction; that it can go red
   was shown on the finished branch by two mutations of `Core_TBC.lua`, each reverted:
   - `MD:AddAlias("calib", "calibrate")` removed: `6 ok, 2 failed` -- `spied /md calib: line 1 of 28
     (golden 1): now "... commands:", golden "call MD:RunCalibrate()"`, and the bare pass likewise.
   - `unlock` registered with a row (`"/st unlock", "x"`) instead of hidden: `4 ok, 4 failed` -- the
     help (`line 5 of 29 (golden 28)`), both passes, the About rows (`line 7 of 56 (golden 54)`) and
     the 27-row count.
2. **corecheck on the parent's shipped files** (the new assertions, before the first edit to
   `Core.lua`): both flavours `22 ok, 2 failed`, rc 1 --
   `attempt to call method 'Commands' (a nil value)` and `attempt to call method 'AddAlias' (a nil
   value)`. After: `24 ok, 0 failed` under both, rc 0.

## Suites (`make check` = `tools/check.sh`, exit codes and footers checked)

| suite | before (8c4cc93 + slashcheck) | after |
|---|---|---|
| `slashcheck` (tbc) | **8** (new) | **8**, equal to the golden |
| `corecheck` (forever / tbc) | 22 / 22 | **24 / 24** |
| every other suite | adaptercheck 23 / 16, bindscheck 6, bookcheck 21, clockcheck 23, coachforever 20, consolecheck 20 / 1, costcheck 3, dashui 64, forevercheck 16, gatecheck 9, importcheck 21, kitcheck 7, measurecheck 30, migrate 7, modulecheck 19, navui 35, parsecheck 15, practice 81, practiceforever 28, practiceui 52, probecheck 88, reccheck 63, recordcheck 31, regencheck 27, releasecheck 21, replaycheck 82, replayforever 15, replayui 103, restcheck 51, reviewforever 13, reviewui 49, runcheck 81, scenariocheck 14, simcheck 13, simwindow 8, solvercheck 84, spellsui 48, spelltip 48, svcheck 6 / 1, tabscheck 24, themecheck 23, timeline 27, tipcheck 37, ttocheck 45, verifycheck 13, wincheck 55, lib/t 12 | all equal, all passing |
| harness-skip, reproduce-smoke, strategies-smoke | ok | ok |
| `apicheck.py` / `--selftest` | 0 findings (47 globals) / 12 of 12 | same |
| `textcheck.py` / `--selftest` | 0 findings / 2 of 2 | same |
| `refcheck.py --selftest` | 2 of 2 | same |

`tools/check.sh`: 61 runs, all passed, rc 0 (its only notes: the corecheck counts and slashcheck,
which the expected counts do not have yet). `luac -p` passes on `Core.lua`, `Core_TBC.lua`,
`UI/Options_About.lua`, `tools/corecheck.lua`, `tools/slashcheck.lua`.

## TBC

Structure only. `tools/slashcheck.lua` holds every verb's chat output, every call and every setting
change, with and without the UI present, and the About tab's rows, byte for byte against the parent.
Forever's help is unchanged too (no colour set there, same rows; its `corecheck` and every Forever
suite equal). The one kernel behaviour that moved is not reachable from either line today: a name
registered twice now replaces its row instead of appending a second one (nothing in the tree
registers a name twice), and an unknown verb is still answered by the help. No DECISIONS entry is
needed.

## Integrator lines

**CLAUDE.md**:

- `Core.lua` row: `the slash dispatcher (`MD:AddCommand`, then `MD.SlashFallback`, then the command
  list)` becomes `the slash dispatcher (`MD:AddCommand`, else the command list)`, and append before
  the closing ` |`: ` **T61 (P17, review A1):** one command registry for both lines --
  `MD:AddCommand(name, fn, usage, text, hidden)` (a second registration replaces the row in place),
  `MD:AddAlias(alias, name)` (runs the verb, never a row of its own), `MD:Commands()` (copies, in
  order, with `hidden` and `aliases`: the help, TBC's About tab and the tests read it),
  `MD.COMMAND_USAGE_COLOR` (TBC's yellow usages; nil on Forever); `MD.SlashFallback` is gone`
- `Core_TBC.lua` row: `the gear/talent events, `MD.COMMANDS` and the whole slash `if` chain as
  `MD.SlashFallback`` becomes `the gear/talent events, and every TBC slash verb as an `MD:AddCommand`
  registration (T61, P17: in the old list's order, `help` and `unlock` hidden, `config` / `settings` /
  `bindings` / `tip` / `calib` aliases; `MD.COMMANDS` and `MD.SlashFallback` deleted -- a verb moves
  next to its owner when that file is next touched)`.
- `tools/` row, after the `tools/probecheck.lua` sentence: ` **`tools/slashcheck.lua`** (T61, tbc): a
  golden transcript of every TBC slash verb and alias -- chat lines, the calls into 24 spied functions,
  the settings each changed -- with the UI present and absent, plus the About tab's command rows,
  captured on `8c4cc93` before the verbs moved onto `MD:AddCommand` (`--print`, `--golden`).`

**docs/TOOLS.md** section 1:

- New row after `verifycheck.lua`: `| `slashcheck.lua` | **every TBC slash verb, word for word** (T61,
  tbc, 8): 60 inputs -- every verb and alias, the arguments each branch reads, mixed case and padding --
  each input's chat lines, its calls into the 24 functions the verbs reach (spies) and the settings it
  changed, once with the spies and once with those functions absent, plus the About tab's command rows
  painted under the stub, all equal line for line to the golden captured on `8c4cc93` before
  `Core_TBC.lua`'s if-chain became `MD:AddCommand` registrations. `--print` shows the transcript,
  `--golden` prints a new golden to paste over the table |`
- `corecheck.lua` row, append: ` Since **T61** (24 / 24): every verb the flavour registers is in
  `MD:Commands()` and the help is exactly its listed rows (on tbc `MD.COMMANDS` / `MD.SlashFallback`
  gone); an alias runs its verb and is not a second row (A1)`

**docs/TESTING.md**: plan section 9, check 17 (TBC half): "`/md help` lists the same 27 rows as
before and the About tab the same commands; `/md config`, `/md settings`, `/md bindings`, `/md tip`
and `/md calib` still do what `/md options`, `binds`, `tooltip` and `calibrate` do (P17)."

**tools/data/expected-counts.json**: `"corecheck/forever": 24`, `"corecheck/tbc": 24`, and a new
`"slashcheck/tbc": 8`.

**docs/DECISIONS.md**: none (structure only, byte-identical output).

No TOC changes (`tools/slashcheck.lua` is not shipped; no shipped file was added or removed).

## Deviations

- **The golden lives inside `tools/slashcheck.lua`**, as `tools/verifycheck.lua`'s does, rather than
  in a data file: the plan's ownership lists only the suite, and the golden and its comparison stay
  together.
- **The golden records more than the plan names**: the settings each verb changed, a second pass with
  every callee absent, and the About tab's rows. The first two are what the if-chain's `if MD.X`
  guards and toggles do; the third is `MD.COMMANDS`' other reader, which the plan moves to
  `MD:Commands()`.
- **`hidden` is a fifth argument of `MD:AddCommand`**, and `MD:AddAlias` a new kernel function. The
  plan says "aliases registered as hidden aliases"; TBC also has two verbs that are not aliases and
  have no row of their own (`help`, and `unlock`, which shares lock's row), so both shapes were needed.
- **A second registration of a name replaces it in place** instead of appending a second help row.
  Needed for "not listed twice"; no file registers a name twice, so no output moves.
- **The TBC help's yellow usages are a kernel knob** (`MD.COMMAND_USAGE_COLOR`, set by `Core_TBC.lua`)
  so both lines keep their help byte for byte; Forever's stays plain.
- **Finding, not reproduced:** the saved output of the first of two `tools/check.sh` runs on the finished
  branch showed `FAIL importcheck ... the committed fixture is what tools/importfixture.lua writes
  today`, followed by a truncated `output:` line running into `ok probecheck/tbc` -- with the ten
  suites between them missing from the file -- yet the same run ended `check: 61 run(s), all passed`,
  rc 0, and its count comparison (which names a suite that did not pass) named none. So the saved
  stream looks garbled rather than the run failing. `importcheck` passed on its own and in the next
  full run (the one quoted above), on the same files. Noted for whoever next owns `tools/check.sh`.
