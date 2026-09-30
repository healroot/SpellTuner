# T60 -- One escaping rule and one set of formatters (plan P16)

Status: **built** 2026-09-30 on branch `plan/P16` (base `8c4cc93`), wave 6 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator.

## The task (docs/PLAN-refactor-ux.md section 5, P16)

Review item (`docs/review/2026-09-30-project-review.md`): A9, the consumers. T55 (P11) defined
`MD.Text = { Esc, EscASCII, EscKeepColours }`, `MD.Util` (`Median`, `Clock`, `K`, `RECORD_GATE`) and
`MD:ModuleStateText` in `Core.lua`; this task moves the local copies in eight files onto them.

- Replace the local `Esc`, `K`, `Clock`, `Median` copies in Dump_Forever, SpellsPane_Forever,
  Dashboard_Review, ReplayWindow, Measure, SpendTracker, Dashboard_Waste, SimWindow with `MD.Text` /
  `MD.Util`, each file keeping the meaning it has today (pipe-doubling vs reversible ASCII; the Waste
  view's 10000 threshold a named argument). The probe keeps its own copy.
- Tests: equal counts `consolecheck`, `measurecheck`, `spellsui`, `reviewui`, `reviewforever`,
  `replayui`, `replayforever`, `simwindow`, `dashui`.
- TBC: shared files, no behaviour change. SpendTracker's even-n median: check whether its
  `math.ceil` median differs from `MD.Util.Median` and keep its own rule if it does.

Owned files (section 4, wave 6): `UI/Dump_Forever.lua`, `UI/SpellsPane_Forever.lua`,
`UI/Dashboard_Review.lua`, `UI/ReplayWindow.lua`, `Spells/Measure.lua`, `Engine/SpendTracker.lua`,
`UI/Dashboard_Waste.lua`, `UI/SimWindow.lua`. Nothing else was touched (this task file apart).

## What was built

| file | before | after |
|---|---|---|
| `UI/Dump_Forever.lua` | own reversible escape (`tostring` on a non-string); own `ModuleStateText` | `local Esc = MD.Text.EscASCII`; `ModuleStateText` calls `MD:ModuleStateText` (Core.lua's comment at its definition says this copy moves "in P16"; the text is identical line for line) |
| `UI/SpellsPane_Forever.lua` | own reversible escape (`""` on a non-string) | `local Esc = MD.Text.EscASCII` |
| `Spells/Measure.lua` | own reversible escape (`""` on a non-string) | `local Esc = MD.Text.EscASCII` |
| `UI/Dashboard_Review.lua` | own pipe-doubling `Esc`, `K` (1000), `Clock` (`m:ss`) | `MD.Text.Esc`, `MD.Util.K`, `MD.Util.Clock` |
| `UI/ReplayWindow.lua` | own pipe-doubling `Esc` (a non-string passed through), `Clock` (`m:ss.t`, negative clamped), `K` (1000) | `MD.Text.Esc`; `Clock(sec)` is `MD.Util.Clock(sec, true)`; `K` is `MD.Util.K` for `n >= 0` and keeps its old rule below zero (see "The one place they part") |
| `UI/SimWindow.lua` | own `K` (1000) | as ReplayWindow's `K` |
| `UI/Dashboard_Waste.lua` | own `K` (10000) and the `Fmt` it alone used | `K(n)` is `MD.Util.K(n, K_FROM)` with `K_FROM = 10000` named; `Fmt` gone |
| `Engine/SpendTracker.lua` | window stats: `(rates[3] + rates[4]) / 2` of six sorted buckets; the pull seed: `table.sort(rates)` then `rates[math.ceil(#rates / 2)]` | window stats: `MD.Util.Median(rates)` (the sort stays for p25 / p75); the seed: `MD.Util.Median(rates, "low")` |

Each file's meaning is kept: the three files that escaped to reversible ASCII (Dump, SpellsPane,
Measure) take `EscASCII`, the two that only doubled pipes because a client name must paint in the
game's own font (Review, ReplayWindow; T16c) take `Esc`. No escaping rule, formatter or threshold
changed; no TOC entry moved (every file already loads after `Core.lua`).

### SpendTracker's two medians

The plan asked whether SpendTracker's median differs from `MD.Util.Median`. It has two:

- `WindowStats` (six buckets, always even): the mean of the middle two -- `MD.Util.Median`'s default
  even-n rule exactly.
- The pull seed (`PLAYER_REGEN_DISABLED`, up to five fights): `rates[math.ceil(n / 2)]` of the sorted
  list -- for an even count the **lower** middle value, which **does** differ from the default (n = 2:
  seed rule 23.7, default 29.20; n = 4: 2.2 against 13.10, from the equivalence run below). It is
  exactly `MD.Util.Median`'s `"low"` mode (T58 moved PullBudget onto the same mode for the same
  reason), so the seed uses the shared function with its own rule and a comment saying so -- the seed
  does not move and no decision is needed.

### The one place they part: `K` below zero

`MD.Util.K` rounds with `math.floor(n + 0.5)`; the old copies printed `string.format("%d", n + 0.5)`,
which truncates toward zero. The two agree on every `n >= 0` and differ below zero
(`K(-12)`: old `"-11"`, `MD.Util.K` `"-12"`). Where the argument can be negative the old rule is
kept, byte for byte, until a decision says otherwise:

- `UI/ReplayWindow.lua`: the score line's `used` (`State:Used()` = mana at the pull less mana now) and
  `regen` go below zero when a pull starts below full and the pool gains more than it spends.
- `UI/SimWindow.lua`: `SP.ManaUsed` of a synthetic fight whose start mana is the pool less its
  utility mana (`Data/SimPresets.lua`), so a plan that casts little can end above its start.

Both are TBC-visible, and decision 10 is not taken ("nothing here may move the TBC line's look"), so
`-11` stays `-11`. Review's and Waste's `K` only ever see mana, healing or waste sums (non-negative),
so they take `MD.Util.K` directly.

## Verification

### Failing first (a refactor: counts before and after, and the suites can go red)

The golden transcript is the whole suite output of `tools/check.sh` on the parent (`8c4cc93`),
captured before the first edit (the summary and every `tools/.lua/check/*.out`). After the change the
summary is **byte-identical** (60 runs, all passed, the same count on every line), and the per-suite
outputs differ only in table/function addresses and in time-sliced progress (`[sim] search N
evaluations`, `frames=N`, `N ms`), which vary between two runs of the same tree (four runs of
`replayui` on this branch printed 19, 19, 19, 21 evaluations for the same search).

Mutations, each run through `tools/check.sh` and reverted:

| mutation | result |
|---|---|
| Review's `Esc` -> `MD.Text.EscASCII`; SpellsPane's, Measure's and Dump's `Esc` -> `MD.Text.Esc` (the two meanings swapped) | red: `reviewforever` ("the fixture name never painted with its own bytes"), `spellsui` x2 (non-ASCII in the export), `measurecheck` (R33 names escaped), `consolecheck` (the dump is ASCII with no bare pipe) |
| Waste's `K_FROM` 10000 -> 1000 | **green** -- no suite holds the Waste view's threshold |
| the seed's `MD.Util.Median(rates, "low")` -> `MD.Util.Median(rates)` | **green** -- no suite holds the seed's even-n rule |
| Dump's `ModuleStateText` -> a constant | **green** -- no suite reads the dump's modules lines |

The three green mutations are recorded as findings below; their suites (`dashui`, `ttocheck`,
`consolecheck`) are not this task's to edit in wave 6.

### Equivalence run (scratch, not committed)

A standalone Lua 5.1 script loaded `Core.lua`'s `MD.Text` / `MD.Util` block and compared every old
copy (verbatim from `8c4cc93`) with its replacement: both escapes on ten strings (empty, pipes, a
colour code, backslashes, an accented name, control bytes, bytes 127-255, a long mixed string) and
nil; `K` (1000 and 10000), the replay `K`, both clocks on 22 values including 59.94 / 59.96 / 999.5
/ 9999.5 and their negatives; both SpendTracker medians on 2000 random lists of 0-6 values.
**2461 compared, 0 differ.**

### Suites

`tools/check.sh`: **60 runs, all passed** before and after; `apicheck` 0 findings; `textcheck` 0
findings; `luac -p` on all eight files. The named suites, before -> after:

| suite | before | after |
|---|---|---|
| consolecheck/forever | 20 | 20 |
| consolecheck/tbc | 1 | 1 |
| measurecheck/forever | 30 | 30 |
| spellsui/forever | 48 | 48 |
| reviewui/tbc | 49 | 49 |
| reviewforever/forever | 13 | 13 |
| replayui/tbc | 103 | 103 |
| replayforever/forever | 15 | 15 |
| simwindow/tbc | 8 | 8 |
| dashui/tbc | 64 | 64 |
| ttocheck/tbc (SpendTracker's reader) | 45 | 45 |

`tools/data/expected-counts.json` is unchanged (no suite gained or lost an assertion).

## Integrator lines

- **TOCs:** none (no file added, removed or moved).
- **tools/data/expected-counts.json:** none.
- **docs/DECISIONS.md:** none (no behaviour changed). If the author later wants a negative `used` /
  `regen` in the replay score and a negative mana used in the Simulate window to round like every
  other number (`-12` rather than `-11`), that is a one-line change in each of the two `K`s above and
  takes a DECISIONS entry then.
- **docs/TOOLS.md / docs/TESTING.md:** none.
- **CLAUDE.md**, "Conventions and constraints", one new bullet right after the "Lua multi-return
  trap" bullet:
  `- **One escaping rule, one set of formatters** (T55 defined them, T60 moved the consumers):
  `MD.Text.Esc` doubles pipes only (a client name painted in the game's own font), `MD.Text.EscASCII`
  is the probe's reversible ASCII escape (copy boxes, reports, exports), `MD.Text.EscKeepColours` keeps
  well-formed colour codes; `MD.Util.K` / `Clock` / `Median` format numbers. A new file uses these
  instead of a local copy; `Client/Probe.lua` keeps its own (it must run with nothing else loaded).`
- **docs/HISTORY.md:** the wave's entry may say: "T60 (P16): Dump_Forever, SpellsPane_Forever,
  Dashboard_Review, ReplayWindow, Measure, SpendTracker, Dashboard_Waste and SimWindow use `MD.Text`
  / `MD.Util` (and Dump `MD:ModuleStateText`) instead of their own copies; every output identical."

## Deviations and findings

1. **`MD:ModuleStateText` in Dump_Forever** is not in P16's "What" (which names `Esc`, `K`, `Clock`,
   `Median`), but `Core.lua`'s comment at the definition says the Dump copy "moves to this in P16", the
   file is P16's, and the two texts were identical line for line, so it moved. The other copy
   (`UI/Dashboard_Forever.lua`) is not P16's file and stays for the task that owns it (P26 / P29).
2. **`K` keeps its old rule below zero** in ReplayWindow and SimWindow (above). Not a deviation from
   "no behaviour change" but a place where the shared function could not be taken whole.
3. **Findings (no suite holds them; not this task's suites to edit):** the Waste view's 10000
   threshold (`dashui` could assert a 5000-mana row reads `5000`, not `5.0k`); SpendTracker's seed
   median on an even count (`ttocheck` or a spend test could seed from two fights and assert the lower
   rate); the dump's modules lines (`consolecheck` could assert `name: on - loads at login`).
4. **Copies outside P16's files, left alone:** `Esc` in `Modules/SpellTuner_Replay/Commands_Forever.lua`
   (and its `EscKeepColours`), `Engine/Practice.lua`, `Modules/SpellTuner_Recorder/Recorder_Forever.lua`;
   `Median` in `Engine/RunRecorder.lua`; `K` in `Engine/PullBudget.lua` (a different rule: `%d` of `n`,
   no rounding); `Clock` in `Engine/SimPlanner.lua`; `Client/Probe.lua`'s `Esc` stays by design.
