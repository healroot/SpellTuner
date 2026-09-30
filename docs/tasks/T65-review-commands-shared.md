# T65 -- The review commands, shared (plan P21)

Status: **built** 2026-09-30 on branch `plan/P21` (base `3261856`), wave 8 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator. **The branch needs its two TOC lines (below)**:
without them the Replay module no longer has `/st validate` or `/st coach` on Forever (the second
implementation in `Commands_Forever.lua` is gone), and `replayforever` (13 ok, 2 failed),
`coachforever` (17 ok, 4 failed) and `reviewforever` (raises: `MD:ValidationReport` is nil) fail --
checked on the committed tree. Every TBC suite loads and passes without them. The TOC
lines were applied in the working tree only, to run the suites, and reverted before the commit (the
T56 / T63 pattern).

## The task (docs/PLAN-refactor-ux.md section 5, P21)

Review items (`docs/review/2026-09-30-project-review.md`): **A1** (the Forever half) -- `coach` /
`MD:RunCoach` and `MD:ValidationReport` were implemented twice and had drifted (argument pattern, B16,
escaping, copy box, energize line; three names for one function on Forever); **A2** (the commands part)
-- the coach commands go into A1's one shared file, printing through one escape rule.

- `Engine/ReviewCommands.lua` (created by T56 on the TBC TOC) is also listed by the Replay module;
  `Modules/SpellTuner_Replay/Commands_Forever.lua` shrinks to `/st replay` and the module's defaults,
  now through `MD:RegisterDefaults`; `/st rec` stays in `Recorder_Forever.lua`;
  `MD.ValidationReportForever` stays as an alias.
- Where the two differed, the shared file does what the plan's table says (below, "What was built").
- Tests: `verifycheck`'s TBC golden equal; `coachforever`, `reviewforever`, `replayforever` equal with
  their expected strings unchanged; `coachforever` +1 (a zone with a pipe prints escaped on Forever, as
  today); `verifycheck` +1 (the same on TBC, the only TBC change).

Owned files (section 4, wave 8): `Engine/ReviewCommands.lua`, `Replay/Commands_Forever.lua`,
`tools/coachforever.lua`, `tools/reviewforever.lua`, `tools/verifycheck.lua`, `tools/replayforever.lua`.
Committed: the first two, `tools/coachforever.lua`, `tools/verifycheck.lua` and this file.
`reviewforever` and `replayforever` needed no edit (they pass unchanged, same counts).

## What was built

| file | change |
|---|---|
| `Engine/ReviewCommands.lua` | One implementation for both lines. **`MD.ReviewCommands`** (`RC`) with **`RC.policy`**, the T59 pattern (`Engine/Practice.lua`'s practice policy): the TBC value is the file's default (`RC.TBC_POLICY = { copyBox = true, reportVerb = "simreplay", slash = "/md" }`), a flavour replaces it by providing `MD.ReviewPolicy` before the file runs. No client read here (apicheck's rule 8: "a flavour installs a policy"). `MD:ValidationReport(rec, n)` (lines returned raw, the caller escapes), new `MD:RunValidate(arg)` (Forever's `/st validate`), `MD:RunCoach(arg)`, `MD:RunCoachRun(arg)`; every line printed through **`MD:PrintSafe`** (Core.lua's `EscKeepColours`); `RC.CastsAndMana(rec)`, `RC.Slash()`. Registers, at load, only the verbs no core has registered: `validate` where the policy's report verb is `validate`, `coach`, and `coachrun` only where `MD.RunRecorder` exists -- so TBC's own rows (Core_TBC.lua's `coach`, `coachrun`) and Forever's rows (formerly Commands_Forever.lua's) stay exactly as they were. |
| `Modules/SpellTuner_Replay/Commands_Forever.lua` | 211 -> 38 lines: `REPLAY_DEFAULTS` becomes one `MD:RegisterDefaults{...}` (same keys, same values); `MD:Provide("ReviewPolicy", { copyBox = false, reportVerb = "validate", slash = "/st" })`; `MD.ValidationReportForever = function(rec, n) return MD:ValidationReport(rec, n) end`; `/st replay`. Its own `Esc`, `EscKeepColours`, `Print`, `PrintCard`, `CastsAndMana`, `ValidationReport`, `MD:ValidationReport`, `/st validate`, `MD:RunCoach` and `/st coach` are gone. |
| `tools/verifycheck.lua` | tbc 13 -> **14**: after the golden transcript (untouched), `/md coach 1 force` on recording 1 with its zone set to `Blood|Furnace\195\169`: the card's header prints `Blood||Furnace\195\169` (pipe doubled, byte as `\ddd`), no line has a bare pipe or a non-ASCII byte. The footer moved out of `Compare` so the check runs after it. |
| `tools/coachforever.lua` | forever 20 -> **21**: the same zone on the clean fixture: `/st validate 1`'s header and the `/st coach 1 force` card's header both print it escaped, no bare pipe, no non-ASCII byte. |

### The differences, and what the shared file does (plan section 5, P21's table)

| Difference | Shared behaviour | Line that changes |
|---|---|---|
| Escaping | `MD:PrintSafe` for every line on both lines (Forever's `Print` was `EscASCII`, its card `EscKeepColours`; the same text for every line either printed) | TBC, only for a zone, name, run name or spell with a pipe, backslash or non-ASCII byte (none in the golden transcript) |
| Energize line | printed when `v.energize > 0` (TBC's text) | neither (a v3 validation has no energize) |
| Copy box for a card over 6 lines | `RC.policy.copyBox` -- the TBC default sets it, Forever's provided policy does not | neither |
| Header casts / mana | `rec.ownCasts` / `rec.spent` when either is present, else counted from a **v3** stream's own casts (a v2 stream without the counters reads 0, as on TBC before) | neither in the suites (the fixture has no counters; a real v3 recording has had both since T13f) |
| Command prefix in hints | `MD.SLASH` when a core sets one (none does yet), else the policy's `slash` (`/md` TBC, `/st` Forever) | neither |
| Coach address pattern | `^([pP]?[%d:]*)%s*(%a*)$`; an argument it cannot read is refused (`coach: no recording <arg>.`) | **TBC**, for an argument the pattern cannot read (`/md coach 1 force now`): it used to coach recording 1 -- see TBC below |
| `coachrun` | registered only where `MD.RunRecorder` exists (and no core has registered it) | neither (TBC's row is Core_TBC.lua's, Forever has no runs) |
| "nothing to validate" | `<reportVerb>: nothing to validate.` -- `simreplay:` on TBC, `validate:` on Forever, as each printed it | neither |

`/st help` on Forever, read under the harness with the TOC lines applied, lists `rec`, `replay`,
`validate`, `coach` in the parent's order with the parent's usage and text; `coachrun` is not listed.
TBC's help is `slashcheck`'s golden, unchanged.

## Tests first

On the parent (`3261856`) with only the new assertions added:

```
tools/run.sh tools/verifycheck.lua
/md coach 1 force as on the parent           ok - 33 lines
/md coachrun 1 as on the parent              ok - 12 lines
/md coach: a zone with a pipe prints escaped (T65) FAIL - bare pipe: "|cff9966ffSpellTuner:|r Blood|Furnace\195\169, 15:33 (0:26, 5 targets)   used: you 1.3k   best 1.6k   diff 250"
13 ok, 1 failed

tools/run.sh tools/coachforever.lua
a zone with a pipe prints escaped in /st validate and the coach card (T65)   ok - validate: true ; coach: true
21 ok, 0 failed      (Forever already escaped: the plan's "as today")
```

On the branch (TOC lines applied): `verifycheck` 14 ok, `coachforever` 21 ok.

**Mutation** (`Say` in `ReviewCommands.lua` printing through `MD:Print` instead of `MD:PrintSafe`): both
fail -- `coachforever` 20 ok, 1 failed (`validate: false bare pipe: ... recording 1: Blood|Furnace...`),
`verifycheck` 13 ok, 1 failed (`bare pipe: ... Blood|Furnace\195\169, 15:33 ...`). Restored.

## Suites (`make check` = `tools/check.sh`, exit codes and footers checked)

Before: `3261856`, 64 runs, all passed. After: this branch with the two TOC lines applied in the working
tree, 64 runs, all passed. Every count equal except the two new assertions:

| suite | before | after |
|---|---|---|
| `verifycheck/tbc` | 13 | **14** |
| `coachforever/forever` | 20 | **21** |
| `replayforever/forever` | 15 | 15 |
| `reviewforever/forever` | 13 | 13 |
| `slashcheck/tbc` | 8 | 8 (TBC help, spied and bare verbs unchanged) |
| `modulecheck/forever` | 19 | 19 |
| `reviewui/tbc` / `reccheck/tbc` / `simcheck/tbc` / `importcheck` | 49 / 63 / 13 / 21 | same |
| `gatecheck` / `scenariocheck` / `recordcheck` / `practiceforever` | 9 / 14 / 31 / 28 | same |
| every other suite in `tools/data/expected-counts.json` | as expected | same |
| `apicheck` | 0 findings, 8 Forever TOCs, **50** files, 47 globals | 0 findings, 8 Forever TOCs, **51** files, 47 globals |
| `textcheck` / selftests | 0 findings, 9 TOCs, 87 files / 13, 2, 2 | same |

(A first version read `MD.API.client` in `ReviewCommands.lua` to pick the policy; apicheck's rule 8
refused it -- "a flavour installs a policy" -- and the policy became the T59 pattern above.)

## TBC

Two visible changes, both in the review commands' own lines, none in the golden transcript:

1. Every line `/md coach` and `/md coachrun` print goes through `MD:PrintSafe`: a zone, a player name,
   a run name or a spell with a pipe, a backslash or a non-ASCII byte prints escaped (pipe doubled, the
   byte as `\ddd`), the card's own colour codes kept. Plain ASCII prints as before.
2. `/md coach <an argument the address pattern cannot read>` -- `1 force now`, `3 4` -- is refused with
   `coach: no recording <arg>.` instead of coaching recording 1. This is B16's fix (T49 on Forever),
   and the rule `docs/DECISIONS.md` already states for the router ("an address neither shape reads ...
   is now refused and the command prints its no recording line"); the coach's own argument parse was
   the last TBC path that still fell back to recording 1.

Everything else TBC shows is byte-identical: `verifycheck`'s golden (`coach 1`, `coach 1 force`,
`coachrun 1`, `simreplay 1`), `slashcheck`'s help and verb transcripts.

## Integrator lines

**`Modules/SpellTuner_Replay/SpellTuner_Replay_Mainline.toc`** and
**`Modules/SpellTuner_Replay/SpellTuner_Replay.toc`** (identical) -- one new line right after
`Commands_Forever.lua`, before the blank line and `Ready.lua`:

```
Commands_Forever.lua
Engine\ReviewCommands.lua

Ready.lua
```

(After, not before: `Commands_Forever.lua` provides `MD.ReviewPolicy`, which `ReviewCommands.lua` reads
at load, and registers `replay` first so the help keeps `replay`, `validate`, `coach` in order.) No
other TOC changes; `SpellTuner_TBC.toc` already lists `Engine\ReviewCommands.lua` last.

**CLAUDE.md**, the files table:

- Replace the `Engine/ReviewCommands.lua` row with: `| `Engine/ReviewCommands.lua` | **The review commands, both lines** (T56; **T65, P21, review A1**): `MD:ValidationReport`, `/st validate` (`MD:RunValidate`, Forever), `/md coach` (`MD:RunCoach`), `/md coachrun` (`MD:RunCoachRun`, only where runs are recorded). Every line through `MD:PrintSafe`. What differs by line is `RC.policy` (`copyBox`, `reportVerb`, `slash`): the TBC value is the default, the Replay module's `Commands_Forever.lua` provides `MD.ReviewPolicy`. Registers only the verbs no core registered, so both helps keep their rows. Listed by the TBC TOC and the Replay module's TOCs |`
- `Modules/<Name>/` row: after "**T16a:** and the engine, planner, solver, `ReplayTrace`, `UI/Tooltip.lua`, `UI/ReplayWindow.lua` (shared with TBC, every client call through `MD.API`) and `Commands_Forever.lua` (`/st replay` / `validate` / `coach`)." append: ` **T65:** `Commands_Forever.lua` is `/st replay`, the module's defaults (`MD:RegisterDefaults`) and the review policy; `/st validate` and `/st coach` are the shared `Engine/ReviewCommands.lua`, listed right after it.`

**docs/TOOLS.md** section 1:

- `verifycheck.lua` row: `(T56, tbc, 13)` -> `(T56, tbc, 14)`, and append: ` Since **T65** (14): after the golden, a zone with a pipe and a non-ASCII byte prints escaped in the `/md coach` card (the review commands print through `MD:PrintSafe` on TBC too)`.
- `coachforever.lua` row, append: ` Since **T65** (21): the same zone prints escaped in `/st validate` and the coach card, now from the shared `Engine/ReviewCommands.lua``.

**tools/data/expected-counts.json**: `"verifycheck/tbc": 14`, `"coachforever/forever": 21`. Every other
count unchanged.

**docs/DECISIONS.md** (one paragraph, under the refactor's entries):

> **The review commands are one implementation (T65, P21, review A1).** `/md coach`, `/md coachrun`,
> the validation report and Forever's `/st validate` are `Engine/ReviewCommands.lua` on both lines.
> Every line they print goes through `MD:PrintSafe`, so on TBC a zone, name, run name or spell with a
> pipe, a backslash or a non-ASCII byte now prints escaped, as it already did on Forever; and
> `/md coach` refuses an argument it cannot read (`1 force now`) instead of coaching recording 1 (B16,
> the router's rule, now on the coach's own parse too). What still differs by line is a policy the
> flavour installs: the copy box for a long card (TBC), the report's verb (`simreplay` / `validate`)
> and the slash in hints.

**docs/TESTING.md** (after wave 8): under item 17 (`/md help` and `/st help` list every command; each
works): `On Forever, with Replay on: /st validate 1 and /st coach 1 answer as before; /st help lists
replay, validate, coach and no coachrun.`

**docs/HISTORY.md**: the integrator's wave entry.

## Deviations

- **The policy is the T59 pattern, not "TBC sets it".** The plan says the copy box sits behind
  `ReviewCommands.policy.copyBox` "(TBC sets it)". `Core_TBC.lua` is P20's this wave and apicheck
  forbids reading `MD.API.client` in a shared file, so -- as `Engine/Practice.lua` does -- the TBC
  value is the shared file's default and the Forever module provides its own (`MD.ReviewPolicy`). A
  later owner of `Core_TBC.lua` may provide TBC's explicitly; nothing else would change.
- **Two policy fields the plan's table does not name**: `reportVerb` (TBC's report verb is
  `/md simreplay N`, `Engine/SimSelfTest.lua`, so registering `/md validate` there would have added a
  TBC verb and moved its help; it also keeps each line's "nothing to validate" prefix) and `slash`
  (`MD.SLASH` does not exist in any core yet; the file reads it first, so a core that sets it wins).
- **Verbs are registered only where no core already has them.** TBC's `coach` and `coachrun` rows
  are `Core_TBC.lua`'s (P17) and stay; re-registering would have replaced their usage text and moved
  `slashcheck`'s help golden. The plan's "coachrun registered only when `MD.RunRecorder` exists" holds
  on top of that.
- **The TBC coach now refuses an unreadable argument** (TBC above), which the plan's table lists as
  "neither" for the pattern itself; the refusal comes with taking Forever's (P5's) handling of a failed
  match rather than TBC's `n = "1"`. Stated in the DECISIONS paragraph.
- **The header's stream count reads only a v3 stream** (`rec.v == 3`). The plan says "else counted from
  the stream"; the only stream that can lack the counters and has a known own-cast kind here is v3
  (`SM.K.OWNCAST` is also 3 on v2, but every v2 recording carries `ownCasts` and `spent`, and a v2
  without them read 0 before). P22 replaces the local `V3_OWNCAST = 3` with `MD.StreamV3.K`.
- **`reviewforever` and `replayforever` were not edited**: both pass unchanged with the same counts.
- **Comments elsewhere** still say `Commands_Forever.lua` owns validate/coach: `UI/Dashboard_Review.lua`
  (T16b's notes) and `Core_TBC.lua:429-431`'s neighbourhood. Files this task does not own; the next
  owner can update them.
