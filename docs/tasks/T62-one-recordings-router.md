# T62 -- One recordings router (plan P18)

Status: **built** 2026-09-30 on branch `plan/P18` (base `b2d9b90`), wave 7 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator.

## The task (docs/PLAN-refactor-ux.md section 5, P18)

Review items (`docs/review/2026-09-30-project-review.md`): **A5** (shared panes discover the
recordings provider by sniffing `MD.*`; one address grammar exists twice and disagrees) and **B16's
root** (an address the parser cannot read silently meant recording 1).

- `Engine/Recordings.lua` (TBC TOC and the Forever main TOC; pure): `Register(prefix, provider)`,
  `Get(spec)`, `List`, `Pin` (capped at `MAX_PINNED`). Providers: `FightRecorder` (bare `N`), the run
  recorder (`a:b`), Practice (`pN`), `Recorder_Forever` (bare `N` on Forever).
- `MD:GetRecording(spec)` stays as the router's entry point; its callers (`UI/ReplayWindow.lua`,
  `UI/Dashboard_Review.lua`, `Engine/ReviewCommands.lua`, the Replay module's commands) are not
  edited. The two old definitions and `Recorder_Forever`'s `== nil` patches go.
- Both recorders read `MD.Util.RECORD_GATE`. Each provider keeps its own retention; only the address
  and the pin cap are shared.
- **The grammar change:** an address neither shape reads (`foo`, `2x`) is refused (nil) instead of
  meaning recording 1; an empty or nil address still means 1; on Forever `a:b` still answers nil. A
  TBC change: DECISIONS "an address that does not parse is refused". The author's standing answer
  (plan section 8, Q11): refuse it, as planned.
- Tests: new `tools/recordingscheck.lua` (both flavours: the grammar table against each flavour's
  providers; a third pin refused); `practice` +1 (`p1` through the router); equal counts
  `recordcheck`, `runcheck`, `reccheck`, `reviewui`, `reviewforever`, `coachforever`, `replayui`.

Owned files (section 4, wave 7): new `Engine/Recordings.lua`, `Engine/FightRecorder.lua`,
`Engine/RunRecorder.lua`, `Engine/Practice.lua`, `Recorder/Recorder_Forever.lua`,
`tools/recordcheck.lua`, `tools/runcheck.lua`, `tools/practice.lua`, new `tools/recordingscheck.lua`.
Nothing else was touched; `recordcheck` and `runcheck` needed no change (their counts are equal).

## What was built

| file | change |
|---|---|
| `Engine/Recordings.lua` (new) | `MD.Recordings`: `Register(prefix, provider)` for the three shapes `""` (bare N), `"p"` and `":"` -- a second provider for a shape raises, as `MD:Provide` does; `Provider(prefix)`; `Parse(spec)` (the grammar alone); `Get(spec)` -> recording, label, run, pullIndex (the old `MD:GetRecording` contract); `List(prefix)` (a shape's recordings, newest first); `PinRecord(prefix, rec, on)` and `Pin(spec, on)` -- the cap checked here with the provider's `pinCap` (`MAX_PINNED = 2` for single fights on both lines, `PR.MAX_PINNED = 4` for practice), `on == nil` toggles, a fight already pinned is not another pin, a run's pull and an unreadable address are refused. `MD:GetRecording` is provided once, through `MD:Provide` (T55), so a second definition raises. No frames, no client calls. |
| `Engine/FightRecorder.lua` | The TBC `MD:GetRecording` is gone; bare N is registered with the router. New `FR:Pin(n, on)` (the router's cap and line) -- TBC had none, the Review tab kept a copy of the cap (T49); the Review's `if FR.Pin` branch now takes it, with the same line. Retention reads `MD.Recordings.MAX_PINNED`; the keep gate reads `MD.Util.RECORD_GATE` (its debug line prints the gate's numbers). |
| `Engine/RunRecorder.lua` | Registers `":"` (`RR:GetPull`, `RR:List`), no pin cap: a run is pinned whole on the Review tab, never a pull through an address. |
| `Engine/Practice.lua` | Registers `"p"` (`PR.Get`, `PR.List`, `pinCap = PR.MAX_PINNED`, its own refusal line kept word for word: `N practice fights are pinned already - unpin one first`). `PR.Pin` delegates to `MD.Recordings.PinRecord("p", ...)`; `PR.List` / `PR.Get` unchanged. |
| `Modules/SpellTuner_Recorder/Recorder_Forever.lua` | `MD.FightRecorder` is defined outright (`List`, `Get`, `Pin`) -- the `if MD.FightRecorder.X == nil` and `if MD.GetRecording == nil` patches are gone (Engine/FightRecorder.lua is on the TBC TOC only, so nothing else defines them on Forever) -- and bare N is registered with the router. `Pin` goes through the router (same line as before). The local `MAX_PINNED` copy is gone (retention reads `MD.Recordings.MAX_PINNED`); the keep gate reads `MD.Util.RECORD_GATE`. |
| `tools/recordingscheck.lua` (new, tbc + forever, 32 each) | Below. |
| `tools/practice.lua` | +1: `p1` reaches the practice provider through the router (`MD.Recordings.Provider("p").List == PR.List`, `Get("p1")`, `List("p")[1]`). |

### The grammar, decided

| address | before (both lines) | now |
|---|---|---|
| nil, `""`, blanks | recording 1 | recording 1 |
| `"3"`, `" 3 "`, `"03"`, the number 3 | recording 3 (label `3`) | the same |
| `"9"` with 8 kept | nil | nil |
| `"p2"`, `"P2"` | practice fight 2 (label `p2`) | the same |
| `"2:7"` | TBC: run 2 pull 7; Forever: nil | the same |
| `"foo"`, `"2x"`, `"p"`, `":7"` | **recording 1** | **nil** (refused) |
| `"0x2"` | **recording 2** (`tonumber` reads hex) | **nil** (refused) |
| `"1.5"`, `"-1"` | nil (no such index) | nil |

Blanks around an address are ignored because `tonumber` ignored them. Every caller that receives nil
prints its existing line: `/md replay foo` -> `replay: no recording foo.`, `/md simreplay foo` ->
`simreplay: no recording foo (try /md simreplay fixture).`, `/st validate foo` -> `validate: no
recording foo.`

## Failing first

The first commit (`207ae7b`) is the tests alone on the parent's code.

**`recordingscheck` on the parent** (both flavours rc 1, 16 ok, 6 failed; the grammar table still runs
through `MD:GetRecording` without the router, so what the old parsers answer is on record):

```
Engine/Recordings.lua is loaded: MD.Recordings with Register, Get, List, Pin FAIL - nil
"foo"          -> refused      FAIL - got #103 label=1 run=nil pull=nil
"2x"           -> refused      FAIL - got #103 label=1 run=nil pull=nil
"p"            -> refused      FAIL - got #103 label=1 run=nil pull=nil
":7"           -> refused      FAIL - got #103 label=1 run=nil pull=nil
"0x2"          -> refused      FAIL - got #102 label=2 run=nil pull=nil
16 ok, 6 failed
```

**`practice` on the parent:** rc 1, 83 ok, 1 failed -- `...through the router's practice provider
FAIL - no MD.Recordings`.

**After** (TOC lines below applied in the working tree): `recordingscheck` 32 ok / 32 ok, `practice`
84 ok.

**Mutations** (each reverted afterwards):

- `Engine/FightRecorder.lua` and `Recorder_Forever.lua` back to their literal `20` / `5`:
  `the TBC recorder keeps a pull by MD.Util.RECORD_GATE FAIL - shipped gate: 0 kept, lowered: 0 kept`
  and the same for the Forever recorder -- the gate test drives a 10 s, 3-cast pull through each
  recorder (TBC: `FR:Start` / `FR:Finish`; Forever: the real events and the stub's clock) under the
  shipped gate and under a lowered one.
- `Recordings.Parse`'s refusal replaced by `tonumber(s) or 1`: the five grammar rows above fail
  again on both flavours.

### What recordingscheck asserts (32 per flavour)

- the router is loaded; each flavour's shapes registered (`+'' +'p' +':'` on TBC, `+'' +'p' -':'` on
  Forever with the Practice module on); a second provider for a shape raises, naming it (3);
- 21 grammar rows (the table above plus `"p9"`, `"1:1"`), each through `MD:GetRecording` and
  `MD.Recordings.Get`, checking recording, label, run and pull index; `List` newest first (22);
- the pin cap: two fights pin, a third is refused with `at most 2 fights can be pinned - unpin one
  first.`; the recorder's own `Pin` (what the Review tab calls) refuses it the same way; re-pinning a
  pinned fight is not a third pin; unpin one and the third pins; `foo` and `2:7` never pin; a
  practice fight pins through the router under practice's own cap (6);
- the recording gate, per flavour's recorder (1).

## Suites

`tools/check.sh` (= `make check`), exit codes checked, on `b2d9b90` (before) and on this branch with
the three TOC lines below applied in the working tree (after). Both runs exit 0, `all passed`.

| suite | before | after |
|---|---|---|
| `practice/tbc` | 83 | **84** |
| `recordingscheck/tbc` / `/forever` (new) | -- | **32 / 32** |
| `recordcheck/forever` / `runcheck/tbc` / `reccheck/tbc` | 31 / 81 / 63 | same |
| `reviewui/tbc` / `reviewforever/forever` / `coachforever/forever` / `replayui/tbc` | 49 / 13 / 20 / 103 | same |
| `practiceui/tbc` / `practiceforever/forever` / `replayforever/forever` / `verifycheck/tbc` | 52 / 28 / 15 / 13 | same |
| `importcheck` / `modulecheck/forever` / `wincheck/forever` / `slashcheck/tbc` | 21 / 19 / 55 / 8 | same |
| every other suite (adaptercheck 23/16, bindscheck 6, bookcheck 21, clockcheck 23, consolecheck 20/1, corecheck 24/24, costcheck 3, dashui 64, forevercheck 16, gatecheck 9, kitcheck 7, measurecheck 30, migrate 7, navui 35, parsecheck 15, probecheck 88, regencheck 27, releasecheck 21, replaycheck 82, restcheck 51, scenariocheck 14, simcheck 13, simwindow 8, solvercheck 84, spellsui 48, spelltip 48, svcheck 6/1, tabscheck 24, themecheck 23, timeline 27, tipcheck 37, ttocheck 45, lib/t 12) | as listed | same |
| harness skip, reproduce / strategies smoke | pass | pass |
| `apicheck` / `--selftest` | 0 findings, 48 files / 13 | 0 findings, **49** files / 13 |
| `textcheck` / `--selftest` | 0 findings, 85 files / 2 | 0 findings, **86** files / 2 |
| `refcheck --selftest` | 2 | 2 |

`check.sh` notes `practice/tbc: 84, 83 expected` and the two new `recordingscheck` runs as not in the
expected counts -- the integrator's line below.

Without the TOC lines the branch does not load (`Engine/FightRecorder.lua` calls
`MD.Recordings.Register` at load), which is the expected state until they land -- as T56's split.

## Integrator lines

**`SpellTuner_TBC.toc`** -- one line before `Engine\FightRecorder.lua` (after `Engine\SimModel.lua`):

```
Engine\Recordings.lua
```

**`SpellTuner_Mainline.toc` and `SpellTuner.toc`** (the twins) -- one line after
`Engine\ManaModel.lua` (before `Spells\Measure.lua`), so the router exists before any module loads:

```
Engine\Recordings.lua
```

No module TOC changes (`Recorder_Forever.lua` and the Practice module's `Engine\Practice.lua` find
the router already loaded by the main addon).

**docs/DECISIONS.md** -- new section:

> ## An address that does not parse is refused (2026-09-30, T62)
>
> Every recording is addressed by one grammar, `Engine/Recordings.lua` on both lines: nothing (or
> blanks) is the newest single fight, `N` a single fight, `pN` a practice fight, `a:b` pull b of run a
> (TBC; Forever records no runs and answers nil). An address neither shape reads -- `foo`, `2x`, `p`,
> `:7`, `0x2` -- is now refused and the command prints its "no recording" line; it used to mean
> recording 1 (`0x2` recording 2), which is how `/st coach` printed a card for the wrong fight (B16).
> This changes TBC: `/md replay foo` no longer opens the newest fight. Each recorder still decides
> which recording it drops; the pin cap is the router's -- two single fights on both lines (TBC now
> has a `Pin` of its own with the Review tab's line, `at most 2 fights can be pinned - unpin one
> first.`), four practice fights. Both recorders keep a pull by `MD.Util.RECORD_GATE` (20 s, 5 casts),
> unchanged.

**CLAUDE.md**:

- New row after `Engine/FightRecorder.lua`'s (before `Engine/RunRecorder.lua`): `| `Engine/Recordings.lua` |
  **One recordings router, both lines** (T62, P18, review A5): `MD.Recordings.Register(prefix,
  provider)` for the three address shapes -- bare `N` (`Engine/FightRecorder.lua` on TBC,
  `Recorder_Forever.lua` on Forever), `pN` (`Engine/Practice.lua`), `a:b` (`Engine/RunRecorder.lua`,
  TBC only) -- a second provider raising; `Get(spec)` (recording, label, run, pull), `List(prefix)`,
  `Pin(spec, on)` / `PinRecord(prefix, rec, on)` with the shared cap (`MAX_PINNED = 2` single fights,
  practice its own 4). `MD:GetRecording` is its entry point, provided once through `MD:Provide`. **An
  address that does not parse is refused** (nil), never recording 1. Pure |`
- `Engine/FightRecorder.lua` row, append before the closing ` |`: ` **T62 (P18):** bare `N` answered
  through `Engine/Recordings.lua` (the old `MD:GetRecording` moved there), `FR:Pin` capped by the
  router, the keep gate `MD.Util.RECORD_GATE``
- `Modules/<Name>/` row, after the `T13:` sentence about `Recorder_Forever.lua`: ` **T62:** it defines
  `MD.FightRecorder` (`List` / `Get` / `Pin`) outright and answers bare `N` through
  `Engine/Recordings.lua` -- no `== nil` patches; the gate is `MD.Util.RECORD_GATE`.`

**docs/TOOLS.md** section 1:

- New row after `recordcheck.lua`: `| `recordingscheck.lua` | **the recordings router** (T62, tbc +
  forever, 32 / 32): each flavour's providers registered (`''`, `p`, and `:` on TBC only), a second
  provider raising; 21 addresses through `MD:GetRecording` and `MD.Recordings.Get` -- nil, blanks,
  `1`, `3`, `03`, `p2`, `P2`, `2:7`, `1:1`, and `foo`, `2x`, `p`, `:7`, `0x2` refused; the pin cap
  (a third fight refused with a line, through the router and the recorder's `Pin`; a pull and an
  unreadable address never pinned; practice's own cap); both recorders keep a pull by
  `MD.Util.RECORD_GATE` |`
- `practice.lua` row, append: ` Since **T62** (84): `p1` reaches the practice provider through
  `Engine/Recordings.lua`.`

**docs/TESTING.md** section 44 -- the header's wave list gains ", and wave 7 (T62-T63) adds 18", and
under **TBC**, after item 17:

```
18. **An unreadable address (P18).** `/md replay foo`: `replay: no recording foo.` and no window
   (it used to open your newest fight). `/md replay 1` and `/md replay p1` still open.
```

**tools/data/expected-counts.json**: `"practice/tbc": 84`, and new `"recordingscheck/forever": 32`,
`"recordingscheck/tbc": 32`.

## Deviations and findings

- **The pin cap is shared as a mechanism, not as one number.** The plan says "`Pin` (capped at
  `MAX_PINNED`)" and "only the address and the pin cap are shared". Single fights share
  `MD.Recordings.MAX_PINNED = 2` on both lines; practice keeps its own cap of 4 and its own refusal
  line, checked by the router (`pinCap` / `Refusal` on its provider) -- lowering it to 2 would be a TBC
  change the plan does not decide. Runs have no cap through the router: the Review tab pins a run
  whole (`run.pinned`), and `MAX_PINNED_RUNS` stays in `RunRecorder`'s retention.
- **Blanks are ignored** (`" 3 "` is 3), because `tonumber` ignored them; not in the plan's table.
- **`/md coach foo` and `/st coach foo` still coach recording 1** -- not the router's doing: both
  callers' own pattern (`^([pP]?[%d:]*)%s*(%a*)$`, `Engine/ReviewCommands.lua:102` and
  `Modules/SpellTuner_Replay/Commands_Forever.lua:166`) reads `foo` as an empty address plus the
  word `foo`, and turns the empty address into `"1"` before calling `MD:GetRecording`; `2x` becomes
  address `2` plus the word `x`. Confirmed under both flavours with an empty ring: `MD:RunCoach("foo")`
  prints `coach: no recording 1.`, `"2x"` prints `coach: no recording 2.` Callers are not edited in
  P18; P21 (wave 8) owns both files and should refuse an argument whose trailing word is not a
  strategy or `force`. `/md replay`, `/md simreplay` and `/st validate` hand the address through
  unchanged and refuse it now.
- **`UI/Dashboard_Review.lua`'s `PinFight` fallback copy of the cap is now dead on both lines**
  (`FR.Pin` exists on TBC too), and its comment ("TBC's Engine/FightRecorder.lua has no Pin yet")
  is stale; not this task's file -- whichever task next owns it (P25 / P27) can drop the copy.
- `Core.lua`'s `MD:Provide` comment names `MD.FightRecorder.Pin` as a seam to provide; `Recorder_Forever`
  now defines the whole `MD.FightRecorder` table it owns instead (nothing else defines it on
  Forever), so `Provide` is used for `GetRecording` only.
