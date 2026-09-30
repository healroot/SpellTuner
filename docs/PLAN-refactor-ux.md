# Plan: fix, refactor, and improve the design (after the review of 2026-09-30)

The author asked for a review "of all project", then a plan to "improve architecture (refactor) and
UI (improve design and UX) even better". The review is `REVIEW-2026-09-30.md` (same folder): 26
confirmed bugs `B1..B26`, architecture `A1..A32`, UI/UX `U1..U31`, tests and tools `Q1..Q16`. This
plan picks from it. It is written like `docs/SPEC-forever-ui.md` section 9: each task `P<n>` is one
implementer's work. This is revision 2; section 10 lists what changed after the critic's pass.

The author also said: **"dont run too much in paralel"**. So a wave has **at most three** tasks, most
have two, several have one, and a wave starts only when the previous one is merged and green.

---

## 1. Goals

1. **Every confirmed bug fixed first**, each with a test that fails on `92ff5d2` (waves 1-3). The
   forever stub stops lying about secrets **before** any Forever bug fix is written (P1 in wave 1),
   and the Forever launch cannot silently turn the addon into "unknown client" (P3 in wave 1).
2. **The test loop tells the truth** before the large refactors: the engine's self-tests can fail
   (wave 1), timers and geometry in the stub behave (wave 4), a skip is not a pass and one command
   (`make check`) runs everything (wave 5). Every later refactor names the suites that prove it
   changed nothing, and those suites must be able to go red.
3. **One owner per rule.** The commands, the escaping rule, the defaults, the combat flag, the rank
   rules, the kit's shape, the v3 stream constants, the mana pool and the colour tokens each end up
   defined once (waves 4-10). These are the refactors that pay: every one of them has already caused
   a bug or a double fix (B6, B8, B14, B16, R41, the `others` drop in A18).
4. **The rest of the window catches up with the Spells group** on Forever (waves 11-17): one
   selection language, one tooltip skin, crisp edges everywhere, Review and the replay that answer
   in the window instead of in chat, settings reachable without typing.
5. **TBC stays as it is** unless the author says otherwise. Every Forever-only look is gated on one
   named flag, `UI.THEMED` (P25), never on a token happening to be set. The TBC improvements (U4,
   U5, U6) are a conditional wave for decision 10.

Non-goals: the big engine splits (A19 `SM:Run`, the full A17 SimPlanner split, the full A11 kit
migration, A25 the replay window split, A26 the SpellsPane split). They are listed in section 6 with
the reason, and several tasks below make them cheaper later.

## 2. Principles (what must not change)

- **TBC behaviour changes only by a documented decision.** A bug fix that changes what TBC shows or
  records gets one `docs/DECISIONS.md` entry in its task (B1, B2, B6-B10, B13, B14, A4, the
  address grammar in P18, the review-command texts in P21, the keyboard in P28). A refactor on a
  shared or TBC file must leave the TBC suites byte-identical (`dashui`, `navui`, `reviewui`,
  `replayui`, `practiceui`, `reccheck`, `replaycheck`, `simcheck`, `runcheck`, `regencheck`,
  `spelltip`, `consolecheck`, `simwindow`, `restcheck`, `solvercheck`, `importcheck`).
- **One switch for the Forever look.** Before P25 the switch is today's `UI.TEXT ~= nil`. P25 adds
  `UI.THEMED` (false in `UI/Style.lua`, true in `UI/Theme_Forever.lua`) and converts every existing
  "is the theme on" test to it, because P25 also makes `UI.TEXT` present on TBC. From P25 on, every
  task that says "Forever only" gates on `UI.THEMED` and names the TBC suites that prove TBC did not
  move. A token read (`UI.TEXT.muted`) is a colour, never a gate.
- **The planner's causality invariant** (pasted at the top of `Engine/SimPlanner.lua`, tested by
  `coachforever.lua:236-256` and `solvercheck`) stays true in every task that touches the engine.
- **The score stays lexicographic** (`deaths, floorSeconds, manaSpent + manaOwed, ...`), never
  blended. B6/B7/B8 change which plan wins, not how plans are compared.
- **Client reads through `MD.API`**, client calls in `Client/` only (the widget toolkit and Lua
  extensions excepted); nothing on a Forever TOC registers `COMBAT_LOG_EVENT_UNFILTERED`;
  `IsSecret` before anything but storing (`type(secret) == "number"` is true on the client, and after
  P1 it is true in the stub too).
- **Rendered text is ASCII and never carries a bare pipe.** Chat, font strings, tooltips, copy boxes.
- **No libraries.** Plain frames, the existing kit.
- **The approved UI decisions (`docs/SPEC-forever-ui.md` section 8.1) hold**: 1 the rail; 2 new heals
  appended with a dot unless removed once; 3 takeover (pair mode unscheduled); 4 hide in combat and
  reopen on the same view; 5 Shift is the detail key; 6 resizable, a size per group; 7 rank-row hover
  is the game's tooltip plus the block; 8 no "Measured" line yet; 9 bindings for spells not in the
  book hidden automatically; 10 TBC does not opt in now; 11 Whole book kept; 12 a macro naming a rank
  decided after T25a's probe; 13 font offset -2..+2. Anything below that departs from the approved
  spec or mockup is marked **needs a mockup** (section 7) and waits for the author. A new surface
  the spec does not have (the minimap button on Forever) is a question (section 8), not a task.
- **Model rules from CLAUDE.md**: calibration never feeds the model; `Data/SpellData.lua` changes only
  from a measurement; the model is event-driven and tickers only accumulate or render; widget
  visibility has one owner per line.

## 3. How every task ends

1. `luac -p` on every changed shipped file.
2. Before P13 lands: the loop in `docs/TOOLS.md` section 1, **checking each suite's exit code**, not
   `tail -1` (Q3/Q5); `tools/run.sh tools/simcheck.lua | grep -c FAIL` = 0 as well until P3 makes
   simcheck exit non-zero. After P13: `make check` green, `python3 tools/apicheck.py` 0 findings.
3. The suite named in the task **fails on the parent commit first** (a bug task: the new assertion;
   a refactor: the task file records the suites and counts before and after, and they are equal
   unless the task says otherwise; a golden transcript is captured before the first edit).
4. **Integrator-owned files.** TOCs (all nine), `CLAUDE.md`, `docs/HISTORY.md`, `docs/TESTING.md`,
   `docs/DECISIONS.md`, `docs/TOOLS.md`, `tools/data/expected-counts.json` are edited only by the
   integrator at the end of a wave; a task states the exact lines it needs (a TOC entry and its
   position, a DECISIONS paragraph, a CLAUDE.md row).
5. **Ownership is per file, per wave.** A task owns every file it creates, edits, or adds an
   assertion to, and the wave table lists all of them; running a suite is not owning it. No file
   appears twice in one wave (the table in section 4 was checked mechanically for this).
6. One task file per task, `docs/tasks/T45-...` onward in wave order (T44 was the last), with the
   before/after suite counts and the failing-first evidence.

## 4. The waves

"Suites" means files under `tools/`. `Replay/` and `Recorder/` are the module folders under
`Modules/SpellTuner_*`.

| Wave | Tasks | Owned files (complete) |
|---|---|---|
| 1 | P1, P2, P3 | **P1:** `tools/wowstub.lua`, `tools/adaptercheck.lua`, `tools/clockcheck.lua`, new `tools/costcheck.lua`. **P2:** `Engine/SimModel.lua`, `Engine/SimPlanner.lua`, `Engine/SimSolver.lua`, `Replay/Scenario_Forever.lua`, `Replay/Gates_Forever.lua`, `tools/replaycheck.lua`, `tools/solvercheck.lua`, `tools/coachforever.lua`, `tools/practice.lua`. **P3:** `Client/API.lua`, `release.sh`, `tools/releasecheck.lua`, `tools/apicheck.py`, new `tools/data/flavours.txt`, `tools/forevercheck.lua`, new `tools/textcheck.py` + `tools/data/textcheck-fixture.lua`, `Core_TBC.lua`, `Verify.lua`, `UI/Style.lua`, `UI/Advisor.lua`, `Engine/TTO.lua`, `tools/simcheck.lua` |
| 2 | P4, P5, P6 | **P4:** `Engine/FightRecorder.lua`, `UI/Summary.lua`, `Engine/RunRecorder.lua`, `Engine/Overheal.lua`, `Engine/Targets.lua`, `tools/fakepull.lua`, `tools/reccheck.lua`, `tools/runcheck.lua`. **P5:** `Recorder/Recorder_Forever.lua`, `Replay/Commands_Forever.lua`, `UI/Dashboard_Review.lua`, `tools/recordcheck.lua`, `tools/reviewforever.lua`, `tools/reviewui.lua`, `tools/coachforever.lua`, `tools/scenariocheck.lua`. **P6:** `Spells/Parse.lua`, `UI/Clock_Forever.lua`, `Engine/ManaModel.lua`, `UI/SpellsPane_Forever.lua`, `tools/import.lua`, `tools/refcheck.py`, `tools/data/parse-fixture.lua`, `tools/parsecheck.lua`, `tools/clockcheck.lua`, `tools/spellsui.lua`, `tools/importcheck.lua` |
| 3 | P7, P8, P9 | **P7:** `UI/Windows_Forever.lua`, `UI/ReplayWindow.lua`, `tools/wincheck.lua`, `tools/replayui.lua`, `tools/practiceui.lua`, `tools/practiceforever.lua`. **P8:** `Core.lua`, `Core_TBC.lua`, `Client/API.lua`, `tools/harness.lua`, `tools/corecheck.lua`, `tools/adaptercheck.lua`. **P9:** `UI/Dashboard_Review.lua`, `UI/Dashboard_Waste.lua`, `tools/reviewui.lua`, `tools/dashui.lua` |
| 4 | P10, P11, P12 | **P10:** `tools/wowstub.lua`, `tools/wincheck.lua`, `tools/recordcheck.lua`, `tools/probecheck.lua`, `tools/practiceforever.lua`, `tools/spellsui.lua`, `tools/importfixture.lua`, `tools/importcheck.lua`. **P11:** `Core.lua`, `tools/corecheck.lua`, `tools/consolecheck.lua`. **P12:** `Verify.lua` (deleted), new `Diagnostics_TBC.lua`, new `Engine/RegenMeasure.lua`, new `Engine/SimSelfTest.lua`, new `Engine/ReviewCommands.lua`, `tools/simcheck.lua`, `tools/regencheck.lua`, new `tools/verifycheck.lua` |
| 5 | P13, P14 | **P13:** `tools/harness.lua`, `tools/run.sh`, new `tools/check.sh`, new `tools/lib/t.lua`, `Makefile`, `tools/apicheck.py`, `tools/releasecheck.lua`, `tools/modulecheck.lua`, `tools/reviewui.lua`, `tools/probecheck.lua`, `tools/strategies.lua`, `tools/solvercmp.lua`, `tools/wclcheckkit.lua`, `tools/reproduce.lua`, `tools/healcheck.lua`, `UI/ReplayWindow.lua` (the raw event frame only). **P14:** `Engine/TTO.lua`, `UI/Widget.lua`, `Engine/PullBudget.lua`, `UI/Advisor.lua`, `Core_TBC.lua`, `UI/Clock_Forever.lua`, `tools/wowstub.lua`, new `tools/ttocheck.lua`, `tools/replayui.lua` |
| 6 | P15, P16, P17 | **P15:** `Engine/Practice.lua`, `UI/PracticePanel.lua`, `UI/BindingsWindow.lua`, `Replay/Kit_Forever.lua`, `tools/apicheck.py`, `tools/practice.lua`, `tools/practiceui.lua`, `tools/practiceforever.lua`, `tools/bindscheck.lua`. **P16:** `UI/Dump_Forever.lua`, `UI/SpellsPane_Forever.lua`, `UI/Dashboard_Review.lua`, `UI/ReplayWindow.lua`, `Spells/Measure.lua`, `Engine/SpendTracker.lua`, `UI/Dashboard_Waste.lua`, `UI/SimWindow.lua`. **P17:** `Core_TBC.lua`, `Core.lua`, `UI/Options_About.lua`, `tools/corecheck.lua`, new `tools/slashcheck.lua` |
| 7 | P18, P19 | **P18:** new `Engine/Recordings.lua`, `Engine/FightRecorder.lua`, `Engine/RunRecorder.lua`, `Engine/Practice.lua`, `Recorder/Recorder_Forever.lua`, `tools/recordcheck.lua`, `tools/runcheck.lua`, `tools/practice.lua`, new `tools/recordingscheck.lua`. **P19:** new `Engine/Kit.lua`, `Engine/SimModel.lua`, `Engine/RankMath.lua`, `Replay/Kit_Forever.lua`, `Spells/Book.lua`, `tools/kitcheck.lua` |
| 8 | P20, P21 | **P20:** `Core_TBC.lua`, `Core_Forever.lua`, `Engine/SimModel.lua`, `Engine/SimPlanner.lua`, `Replay/Gates_Forever.lua`, `UI/ReplayWindow.lua`, `UI/Options_General.lua`, new `tools/defaultscheck.lua`. **P21:** `Engine/ReviewCommands.lua`, `Replay/Commands_Forever.lua`, `tools/coachforever.lua`, `tools/reviewforever.lua`, `tools/verifycheck.lua`, `tools/replayforever.lua` |
| 9 | P22, P23 | **P22:** `Engine/SimModel.lua`, `Replay/Scenario_Forever.lua`, `Replay/Gates_Forever.lua`, new `Recorder/Stream_Forever.lua`, `Recorder/Recorder_Forever.lua`, `Engine/ReviewCommands.lua`, `Engine/SimPlanner.lua`, `UI/ReplayWindow.lua`, `tools/gatecheck.lua`, `tools/scenariocheck.lua`, `tools/recordcheck.lua`. **P23:** `Engine/RankMath.lua`, `Spells/Book.lua`, `UI/SpellTip_Forever.lua`, `UI/SpellsPane_Forever.lua`, new `Spells/RankRules.lua`, new `Spells/Words.lua`, `tools/tipcheck.lua`, `tools/spellsui.lua`, `tools/bookcheck.lua` |
| 10 | P24, P25 | **P24:** `UI/Clock_Forever.lua`, new `Engine/ManaPool_Forever.lua`, `Recorder/Recorder_Forever.lua`, `UI/Widget.lua`, new `UI/Visibility.lua`, `Spells/Book.lua`, `tools/clockcheck.lua`, `tools/recordcheck.lua`. **P25:** `UI/Style.lua`, `UI/Theme_Forever.lua`, `UI/Dashboard_Rows.lua`, `UI/Tooltip.lua`, `UI/BindingsWindow.lua`, `UI/PracticePanel.lua`, `UI/SpellsPane_Forever.lua`, `UI/ReplayWindow.lua`, `UI/Dashboard_Review.lua`, `UI/SpellTip_Forever.lua`, `tools/themecheck.lua` |
| 11 | P26, P27, P28 | **P26:** `UI/Dashboard_Forever.lua`, `UI/Clock_Forever.lua`, `tools/wincheck.lua`, `tools/clockcheck.lua`. **P27:** `UI/Dashboard_Review.lua`, `Engine/SimPlanner.lua`, `Engine/SimModel.lua`, `Replay/Gates_Forever.lua`, `UI/Dashboard_Rows.lua`, new `UI/ContextMenu.lua`, `tools/reviewforever.lua`, `tools/reviewui.lua`, `tools/coachforever.lua`, `tools/gatecheck.lua`. **P28:** `UI/ReplayWindow.lua`, `tools/replayforever.lua`, `tools/replayui.lua` |
| 12 | P29 | `UI/Style.lua`, `UI/Dashboard_Forever.lua`, `UI/Windows_Forever.lua`, `UI/Dump_Forever.lua`, `UI/Options_General.lua`, `tools/navui.lua`, `tools/reviewforever.lua`, `tools/practiceforever.lua`, `tools/consolecheck.lua`, `tools/dashui.lua`, `tools/wincheck.lua` |
| 13 | P30 | `UI/Style.lua`, `tools/themecheck.lua`, `tools/navui.lua` |
| 14 | P31 | `UI/Style.lua`, `UI/Windows_Forever.lua`, `tools/themecheck.lua`, `tools/navui.lua`, `tools/wincheck.lua` |
| 15 | P32 | `UI/Style.lua`, `UI/Tooltip.lua` -> new `UI/Tip.lua` + new `UI/Tip_TBC.lua`, `UI/SpellsPane_Forever.lua`, `UI/SpellTip_Forever.lua`, `UI/Clock_Forever.lua`, `UI/Dashboard_Rows.lua`, `tools/tipcheck.lua`, `tools/spelltip.lua`, `tools/reviewforever.lua`, `tools/clockcheck.lua`, `tools/dashui.lua` |
| 16 | P33 (after M4) | `UI/Style.lua`, `UI/SpellsPane_Forever.lua`, `UI/Windows_Forever.lua`, `tools/navui.lua`, `tools/spellsui.lua`, `tools/wincheck.lua` |
| 17 | P34 (after M5) | `UI/Theme_Forever.lua`, `UI/Dashboard_Rows.lua`, `UI/SpellsPane_Forever.lua`, `UI/SpellTip_Forever.lua`, `tools/spellsui.lua`, `tools/tipcheck.lua`, `tools/themecheck.lua` |
| C | C1-C4, only on the author's yes to decision 10 | see section 5.C |

Why this order. The stub's secret lie (Q1) is fixed in wave 1, before P5 and P6 edit
`IsSecret`-guarded code in wave 2, so P1's "stop and file B27" rule fires before those fixes, not
after. Every stub knob that waves 2-3 need (raid roster, realm, power type, slider clamp, mouse
focus, `xpcall` arguments) is added by P1 in wave 1, so no later bug task has to share
`wowstub.lua`. Waves 13-17 are single tasks because `UI/Style.lua` is one file; splitting it (A20's
four kit files) is not taken (section 6), so the kit tasks queue.

---

## 5. The tasks

### Wave 1 -- a stub that tells the truth, the engine, launch safety

**P1. Stub truth** -- Q1, and every stub knob waves 2-4 need.
- *What.* (a) Q1: under the forever profile `type(secret)` answers `"number"` (the stand-in's
  metatable keeps raising on arithmetic, compare, index, call, concat); drop `adaptercheck.lua:227`;
  the stub header lists the gaps Lua 5.1 cannot close (`#secret`, `secret == plain`, secret as a
  table key) as review-only. (b) Knobs, each defaulting to today's answer so no suite moves:
  `S.powerType` behind `UnitPowerType`; `UnitPowerMax(u, t)` answering per power type
  (`S.powerMax[t]`, `S.manaMax` for 0); a raid (`S.raid = true` makes `IsInRaid` true,
  `GetRaidRosterInfo(i)` answer name, rank, subgroup from `S.units["raid"..i]`); `UnitName(u)`
  returning `name, realm` when the unit has a `realm`; `FrameMT:SetValue` clamping to
  `SetMinMaxValues`; `FrameMT:IsMouseOver()` and `GetMouseFocus()` from a settable `S.mouseFocus`;
  an `xpcall` that passes extra arguments to the function, as the WoW client does (Lua 5.1.5's own
  drops them; P11 relies on this, and section 9 check 5 confirms the client). (c) Q15's live-cost
  gap: new `tools/costcheck.lua` (tbc) sets `S.liveCosts` for a druid heal and asserts
  `SD:GetCost` takes the live branch, the static fallback when it is absent, and `/md verify`'s diff
  line for a disagreement.
- *Tests (fail first).* The mutation of review Q1 (the `IsSecret` half removed from
  `Recorder_Forever.lua:458`) turns `recordcheck` red after P1 and was green before; record both runs
  in the task file, then restore the guard. `clockcheck` +1 (the book was never indexed by a secret
  during a fight). `costcheck` new (3; a fresh suite: the task file records a mutated `GetCost`
  turning it red). Every other suite, both flavours: equal counts.
- *If the type override turns a suite red on unmodified code,* that is a real Forever bug: stop, report
  it to the integrator as `B27+`, and fix it in its own task inserted before wave 2 (P1 merges with or
  after that fix). Do not widen the stub to make it green.
- *TBC.* No (test code only).

**P2. Simulation engine** -- B5, B6, B7, B8, and the `others` drop of A18.
- *What.* (a) B5: `LandCast`'s instant branch traces `HOT_END` for the HoT it consumes. (b) B6: one
  `SP.PARAMS` list (name, domain, default) from which `NewPlan`'s defaults, `Params()`, `Key()` and the
  domains are derived, in both `SP.Search` and `SP.SearchRun`, so `noDirect` is in the key by
  construction; the duplicate seed 3 is replaced by a distinct point or dropped (the task records
  which). (c) B7: when a fixed cast preempts, schedule a decision at the new `busyUntil` and let the
  stale one fall to a decision-generation check; keep zero allocation and the heap's tie-break order.
  (d) B8: one `SM.SWIFTMEND_ORDER = { "Regrowth", "Rejuvenation" }` read by `LandCast` and the solver;
  the solver keeps its valuation in a local instead of writing `swiftmendAmount` onto the shared kit
  entry. (e) The `Scenario_Forever` and `Gates_Forever` wrappers forward `...`.
- *Tests (fail first).* `replaycheck` (+2: Regrowth at 1 s, Swiftmend at 4 s -> `HOT_END` at 4 s and
  `Hot()` nil at 6 s; the Swiftmend-ready state false after it); `solvercheck` (+5: a `noDirect` plan is
  built during `SP.Search`; the seeds are distinct keys; with both HoTs rolling the solver's eaten HoT is
  Regrowth; the kit entry has no `swiftmendAmount` after `Best`; B7: Decide asked at 2.0 after a 0.5 s
  preemption of a 2.9 s cast); `coachforever` (+1: `SM.ScenarioFromRecording(rec, kit,
  {other}).targets[2].dangerPrior` equals the value through `cdb`); `practice` (+1: a practice trace
  ends a Swiftmend-eaten HoT).
- *TBC.* Yes: coach cards change for existing recordings (the search can now pick HoTs-only; the
  suggested column no longer idles after a preemption; the solver prices Swiftmend right). DECISIONS
  "Coach fixes 2026-09-30", with the before/after card of one fixture fight.
- *Invariant.* The causality tests in `coachforever` and `solvercheck` stay green; the score order is
  untouched.
- *Proves no other change:* `simcheck`, `restcheck`, `reproduce` on `tools/data/practice/1790701698.lua`
  (95 % reproduced, unchanged), `gatecheck`, `scenariocheck`, `replayforever`.

**P3. Launch safety, one text rule, simcheck's exit** -- A31/A10 (the interface bands), B3, B11 (TTO
half), U31 (the U+00D7 glyph), Q3. Three small items, each under ~40 changed lines.
- *What.* (a) **The client from the TOC, not the interface.** `Client/API.lua` decides `MD.API.client`
  from `SPELLTUNER_TOC`, which `Client/TOC_*.lua` sets as the first file of every main TOC:
  `"TBC"` -> `tbc`, `"Mainline"` / `"Plain"` -> `forever`. The interface band is only the fallback when
  the marker is absent, and its numbers come from `MD.API.BANDS`, which must equal the new
  `tools/data/flavours.txt` (one line per flavour: name, marker file, band). `release.sh` classifies a
  TOC by the marker file in its own file list (a TOC under `Modules/` is forever), warns when the
  interface is outside the table's band, and refuses only a TOC with neither; `apicheck.py:141` and
  `releasecheck.lua:225-230` read the same table. So a launch interface outside 16000-19999 changes
  nothing: `client == "forever"` holds, Practice's `OnForever()` stays true (T24 is not undone) and
  the packages still build. (b) **One text rule.** New `tools/textcheck.py` (its own tool because it
  covers every TOC, TBC included, while apicheck covers the Forever TOCs against the baseline): no
  byte above 127 in any string constant of a shipped file, read from `luac -l` like apicheck's rules;
  `--selftest` against a fixture with an em dash. The tree's eleven sites are fixed in this task:
  `Core_TBC.lua:243, 325, 369`, `Verify.lua:10, 24, 65, 68, 93, 500`, `UI/Advisor.lua:68` (the
  gear-change toast, missed by B3), and the close glyph at `UI/Style.lua:248` becomes `x`.
  `Engine/TTO.lua:443` doubles its pipe. (c) Q3: `RunSimRun` and `RunSimReplay` return their
  verdicts; `tools/simcheck.lua` exits 1 on any failure and prints the standard footer.
- *Tests (fail first).* `forevercheck` (+3: `Client/API.lua` re-run into a fresh table, as probecheck
  does for its second `MD`, with the Mainline marker and interface 120105 answers `forever`; the TBC
  marker with 20506 answers `tbc`; `MD.API.BANDS` equals `flavours.txt`); `releasecheck` (+3: a
  scratch Forever TOC at 120105 is packaged as forever, a module TOC at 120105 too, a marker-less TOC
  outside every band is refused with its file named); `textcheck --selftest` (2) and `textcheck` on
  the tree reports the eleven sites before the fix and none after; simcheck: a deliberately broken
  `Near` exits 1 (checked once by hand, recorded in the task file).
- *TBC.* Yes: the ten chat strings and the close glyph (text only). DECISIONS: "the client is the
  TOC's, the interface is a fallback".
- *Proves no other change:* `probecheck`, `adaptercheck`, `modulecheck`, `spelltip`, `dashui`,
  `consolecheck`, `regencheck`.

### Wave 2 -- bug fixes (recorders, Review, parse, clock, tools)

**P4. TBC recorders and overheal** -- B9, B10, B11 (RunRecorder half), B12, B13.
- *What.* (a) **B9, what ends a pending cast.** The pending cast is opened by an own
  `SPELL_CAST_START` (as today) and remembers the `castGUID` of the `UNIT_SPELLCAST_START` for
  `player` with the same spell id. It is closed: as a success by the matching `SPELL_CAST_SUCCESS`
  (as today); as a CANCEL by `UNIT_SPELLCAST_INTERRUPTED` for `player` carrying that `castGUID` (by
  spell id when the GUID was not readable); and as a CANCEL of the **old** cast by any own
  `SPELL_CAST_START` while one is pending, the same spell included (the old one ended without a
  success we saw). Nothing else closes it: not a HoT tick, an aura, an energize, and **not a
  `SPELL_CAST_FAILED` or `UNIT_SPELLCAST_FAILED`**, which a spam press of the same button produces
  ("Another action is in progress") for the new attempt while the first cast keeps going. The
  failure reason text is not read (it is localised). The unit events are registered through `MD:On`
  (TBC-only file). (b) **B10, the bloom only.** `UI/Summary.lua` resolves the id through
  `SD:Resolve`, and uses the resolved id **only when the raw id is not a row and the resolved row's
  family is Lifebloom** (33778 -> 33763): the event's kind becomes `bloom`, and both
  `Overheal:Record` and `Calibration:Observe` receive **33763** with kind `bloom`, so RankMath's
  `KindFraction(33763, "bloom")` finds its bucket, calibration gets a bloom observation and waste
  applies the `bloom -> 0` rule. Every other id reaches both calls unchanged, Tranquility's
  44208/44207 included (they stay in `s:44208` / `s:44207` as today; resolving them is a model change
  left to the author). (c) B11: `||` in the usage line. (d) B12: `RR:Start` resets `potionCount` and
  `pullStart`; `PullSkipped` clears `pullStart`. (e) B13: `Targets` records each raid member's
  subgroup from `GetRaidRosterInfo`; Tranquility's waste divides by the caster's party.
- *Tests (fail first).* `tools/fakepull.lua` gains, inside one pull: a Lifebloom tick between a
  Healing Touch's start and success; a **spam press** of the same Healing Touch mid-cast (a
  `SPELL_CAST_FAILED` and a `UNIT_SPELLCAST_FAILED` with a new `castGUID`); a real interrupt
  (`UNIT_SPELLCAST_INTERRUPTED` with the pending `castGUID`); a second Healing Touch start while one
  is pending; a 33778 heal; a 44208 heal. `reccheck` (+8: no CANCEL for the ticked cast; no CANCEL for
  the spam-pressed cast and its success paired; one CANCEL for the interrupted one; one CANCEL for the
  cast replaced by a new start; the bloom stored as `k:33763:bloom`; a calibration bucket for the
  33763 bloom; the 44208 heal still in `s:44208` with the same calibration call as before; a
  25-member raid with the caster in subgroup 3 divides by 5). `runcheck` (+3: two runs back to back,
  no POTION at t~0 in the second, its first pull's `runT0` from its own clock, the usage line has no
  bare pipe).
- *TBC.* Yes, all. DECISIONS: CANCEL's meaning (recordings made before keep their spurious CANCELs;
  not rewritten); the bloom bucket (old `k:33778:direct` entries decay out, 150-event half-life;
  `s:33763` now includes the bloom).
- *In-game check* (section 9, 4): the `castGUID` shape of the unit events on the TBC client.
- *Proves no other change:* `replaycheck`, `simcheck`, `regencheck`, `reviewui`.

**P5. Forever recordings, Review pins and the coach address** -- B14, B15, B16, B24.
- *What.* (a) B14: Review's Pin goes through `MD.FightRecorder:Pin` (capped; a refusal says why in
  one line) on both lines; `StoreOrDrop` honours only the first `MAX_PINNED` pins and always stores,
  as TBC does, with a debug line when it had to. (b) B15: the roster keeps `name` **bare, as today**
  (it is what `SM.PartyMaxFromOthers` and `SM.DangerHitFromOthers` match other recordings on, old
  ones included) and gains a `realm` field from `UnitName`'s second return (through the adapter).
  `ResolveTargetIndex` matches a `Name-Realm` target against `name .. "-" .. realm` exactly, then a
  bare name when it is unique in the roster. (c) B16: the coach pattern accepts `[%d:]`, and an
  argument it cannot read answers `coach: no recording <arg>` as validate does. (d) B24: the selected
  row's validation runs before the rows are painted.
- *Tests (fail first).* `recordcheck` (+4: nine pins, the ninth pull stored; a cross-realm member
  `Healer-OtherRealm` resolved; two same-name members on different realms resolved by the full name;
  the stored `name` is `Healer`, the `realm` `OtherRealm`); `scenariocheck` (+2: an old recording with
  a bare `Tank` and a new one with `name = "Tank", realm = "X"` match in `SM.PartyMaxFromOthers` and in
  `SM.DangerHitFromOthers`); `reviewforever` (+2: a third pin refused with a line; a selected
  unvalidated row paints its verdict on the first render); `coachforever` (+1: `/st coach 2:7` with no
  such recording prints the refusal and no card); `reviewui` (+1: the TBC row paints its verdict on
  the first render).
- *TBC.* Yes: `Dashboard_Review.lua` is shared; a third pin on TBC is now refused with a line instead
  of silently not protecting (DECISIONS one line).

**P6. Parse, clock, export and the offline tools** -- B4, B19, B20, B25, B26.
- *What.* (a) B4: `DAMAGE_SINGLE` is refused when the same sentence continues with a period phrase
  after the amount (`every`, `each second`, `per second`, `Lasts`) or offers `or N healing`; the file's
  contract (refuse rather than guess) extended, no new shape guessed. (b) B19: the model remembers the
  last cast's time, cost and pricing; `StartFight` folds a cast spent within 0.5 s before the flag into
  the fight (R8's window). (c) B20: `Esc` on the name and realm. (d) B25: `^# recording (%d+)`.
  (e) B26: refcheck undoes `\ddd` and `\\` before counting numbers.
- *Tests (fail first).* `parse-fixture.lua`: Hellfire and Volley added as UNVERIFIED wordings expecting
  refusal; Penance's entry changes from `loose` to an expected refusal; `parsecheck` +3, and
  `bookcheck`, `tabscheck`, `tipcheck` unchanged (druid texts untouched). `clockcheck` (+2: an opener
  0.3 s before the flag counts in `fight.casts` and `spent`; an unpriced opener stays in the hover
  count). `spellsui` (+1: a non-ASCII stub character name exports ASCII). `importcheck` (+1: TBC
  `export 1` against a `svwrite`-built SavedVariables holds a `# recording` section). `refcheck.py
  --selftest` (+1: an escaped curly quote agrees with its reference).
- *TBC.* No (Parse is Forever-only by TOC; the tools are tools).

### Wave 3 -- the windows, the character, TBC lists

**P7. Window manager and the replay window** -- B17, B18, B21, B22, B23.
- *What.* (a) B17: `Win:SetScale` reads the old scale before writing and converts every entry in
  `db.ui.win`, registered or not. (b) B18: `Win:Register` restyles the frame's pixel edges after
  `SetScale`. (c) B21: `OpenReplay` leaves the scrubber's range alone in run mode; a drag maps to run
  time. (d) B22: `OpenReplay` returns whether it opened; run-mode `OnUpdate` pauses on a refusal and
  the refusal prints once per combat. (e) B23: the three icons hook `OnEnter` to set the parent's
  `hoverTi`; every icon's `OnLeave` clears it unless the parent frame is still under the mouse
  (`IsMouseOver`, stubbed by P1).
- *Tests (fail first).* `wincheck` (+2: a saved `replay` entry is converted by a scale change made
  before any replay opened; a frame registered at 0.8 has `edgeSize == px(1)` at 0.8); `replayui` (+3:
  after a pull crossing the scrubber's max is the run's length, using P1's clamping `SetValue`; a drag
  to 300 s lands at 300 s; entering combat at a pull boundary prints one line in 120 frames);
  `practiceui` / `practiceforever` (+2: a key pressed with the pointer on the Swiftmend icon heals that
  frame's unit; after leaving an icon outward the key reports "No target").
- *TBC.* Yes: `ReplayWindow.lua` is shared (B21-B23 are TBC-visible fixes). No DECISIONS entry needed:
  the window did the wrong thing, not a different thing.

**P8. Kernel: the character, and two test seams** -- B1, B2, A31 (`PLAYER_LEVEL_UP`), Q15
(`MD.API.Invalidate`, `MD:SetTalents`).
- *What.* (a) B1: `usesMana` answered **from data**: `MD.API.UnitPowerMax("player", 0)` read plain and
  greater than 0 (a druid in Cat or Bear form still has a mana pool; a warrior or rogue has none; the
  answer does not depend on which classes use mana on which client, which a class list would guess
  at on Forever's retail engine). Only when that read is absent, secret or raised does the code fall
  back to today's `UnitPowerType == 0`. (b) B2: `InTreeForm` falls back to the buff scan **only when
  `GetShapeshiftFormID` is absent or raised**, never when it answered `nil`. (c) `PLAYER_LEVEL_UP`:
  `tonumber(level)` only after `MD.API.IsSecret(level)` is false; else the adapter's `UnitLevel`.
  (d) `MD.API.Invalidate(name)` clears one `Has` cache entry (for tests); `MD:SetTalents(tbl)` in
  `Core_TBC.lua` sets the talent ranks, and `tools/harness.lua` uses it instead of overriding
  `MD:TalentRank` after load.
- *Tests (fail first).* `corecheck` (+5: `S.powerType = 3` at login with a mana max leaves `usesMana`
  true for a druid; a warrior (`S.powerMax[0] = 0`) stays false; a secret max falls back to the power
  type; `GetShapeshiftFormID` defined by the test to answer nil with a "Tree of Life" buff present ->
  `InTreeForm()` false, the function absent -> true; a secret level does not raise); `adaptercheck`
  (+1: `Invalidate` makes a later `Has` see a new global).
- *TBC.* Yes: B1 (shared file), B2. DECISIONS: "usesMana is whether the player has a mana pool" and
  "Tree form: the buff scan is a fallback for a missing API only".
- *Proves no other change:* `reccheck`, `replaycheck`, `regencheck`, `spelltip`, `dashui`,
  `forevercheck`, `consolecheck`, every suite that used the `TalentRank` override (equal counts).

**P9. TBC lists say what they hide** -- U25 (the TBC half; the Forever list gets a scroll frame in
P27).
- *What.* Review and Waste stop at the pane's height today and say nothing (a 36-pull run shows ~30).
  When rows are cut, the last visible row becomes a grey `... and N more (scroll: not yet)` line, and
  in Review the selected row is always kept visible (the list starts at it when it would fall off).
  No layout, font or colour change.
- *Tests (fail first).* `reviewui` (+2: a 36-pull run lists the tail line with the right N; selecting
  pull 36 shows it); `dashui` (+1: a Waste list longer than the pane ends with the tail line).
- *TBC.* Yes, a text line only. DECISIONS not needed (it was a silent truncation).

### Wave 4 -- stub timers, kernel seams, Verify split

**P10. Stub timers, geometry and the import fixture** -- Q8, Q12, Q6, and Q4's importcheck half.
- *What.* (a) Q8: `C_Timer.After` keeps a due time and `S.Tick` fires what is due; the five
  hand-flushing suites (`recordcheck`, `probecheck`, `practiceforever`, `spellsui`, `importfixture`)
  assert "nothing left due" instead of flushing. (b) Q12: the stub's opt-in `S.Geometry(true)` with a
  deterministic text metric (chars x 6 px scaled by font size); wincheck's geometry uses it.
  (c) Q6: `importfixture.lua` stamps a fixed version token; importcheck runs every subprocess through
  one environment-scrubbing helper.
- *Tests (fail first).* `recordcheck`'s R10 death re-poll asserts it runs at `+1 s`, not at the flush
  (red before: it runs at the flush); `importcheck` green under `--flavour tbc` too; wincheck equal
  count on the new geometry.
- *TBC.* No.

**P11. Kernel seams** -- A4, A9 (definitions), A3 (the mechanism), A28 (the flag), A16 (`MD:Provide`).
- *What, all in `Core.lua`; consumers move in P14, P16, P18, P20, P23.* `MD.Text = { Esc, EscASCII,
  EscKeepColours }` (the two meanings named apart: pipe-doubling and the probe's reversible escape)
  and `MD:PrintSafe(line)`; `MD.Util` (`Median` copying, `Clock`, `K`, `RECORD_GATE = { sec = 20,
  casts = 5 }`) and `MD.Rules.SUGGESTED_FLOOR` (the only rule constant with a planned consumer, P23;
  GCD and the crit multiplier are not defined here, see section 6); `MD:RegisterDefaults(tbl)`
  (merges before login, back-fills `MD.db` after) and `MD:Setting(key)` (the db value, else the
  registered default); `MD.inCombat` set by the two regen events and seeded at `MD_READY` through
  `MD.API.UnitAffectingCombat`; `MD:Provide(name, fn)` raising on a second provider;
  `MD:ModuleStateText(name)`.
- **A4, fault isolation, stated precisely.** `MD:On`'s and `MD:Fire`'s loops call each handler as
  `xpcall(handler, MD.ErrorSink, ...)`, where `MD.ErrorSink` calls whatever `geterrorhandler()`
  answers at that moment (BugGrabber, Core_Forever's capture, or the default). Three things this must
  hold:
  1. *Arguments.* The WoW client's `xpcall` passes the extra arguments; Lua 5.1.5's drops them. The
     shipped code uses the client's form, and the stub's `xpcall` (P1) passes them too, so the suites
     and the client run the same code. Section 9 check 5 confirms both clients. If either client does
     not pass them, the fallback is a fixed-arity trampoline (up to ten arguments stashed in upvalues,
     no table, no closure per event); an event with more than ten arguments keeps the bare loop.
  2. *Cost.* One extra C call per handler per event. On TBC the combat-log path is
     `COMBAT_LOG_EVENT_UNFILTERED` -> `MD:On` -> one handler (`UI/Summary.lua`), which reads its payload
     from `CombatLogGetCurrentEventInfo` (no event arguments). The task records a stub micro-benchmark
     (1e6 dispatches, bare loop against `xpcall`, `os.clock`) in the task file; if the overhead is over
     1 microsecond per dispatch, the combat-log event is dispatched inside one `xpcall` around its whole
     loop (isolation per event, not per handler) and every other event per handler.
  3. *The error path R21/R22 fixed.* The handler now runs under `xpcall` from `Core.lua`, not under the
     client's script call. `Core_Forever.lua:138-160` skips the capture's own frames and forwards to the
     previous handler as a tail call; this task proves both again under the new dispatch.
- *Tests (fail first).* `corecheck` (+7: a raising first handler does not stop the second and the error
  reaches the handler once; `Fire` the same; `RegisterDefaults` after `InitDB` back-fills without
  overwriting a user value; `inCombat` seeded true when the adapter says so; `Provide` twice raises;
  `Esc`/`EscASCII` on `a|b` and a non-ASCII byte; `PrintSafe` keeps a well-formed colour code);
  `consolecheck` (+3: a handler raising inside `MD:On` under the Forever capture yields a stack line
  naming the raising handler's file and line, not `Core.lua`'s loop, `Client/API.lua` or `[C]`; the
  previous handler receives the message exactly once; the handler receives the event's arguments).
- *TBC.* `Core.lua` is shared; only A4 changes behaviour, and only when a handler raises (the other
  handlers still run). DECISIONS one line.

**P12. Split `Verify.lua`** -- A2.
- *What.* Pure moves, names kept, no call changed: `Diagnostics_TBC.lua` (verify, snapshot, profile,
  export, calibrate), `Engine/RegenMeasure.lua` (fsrtest, regentest, spamtest, the `cdb.mp5` shape),
  `Engine/SimSelfTest.lua` (`RunSimRun`, the fixture replay), and `Engine/ReviewCommands.lua`
  (`ValidationReport`, `RunCoach`, `RunCoachRun` -- their final home, TBC TOC only until P21 adds the
  Replay module). `RegenModel:MeasuredMp5` keeps its own "leftover <= reported" check and its
  once-only refusal message; sharing that bound with `RegenMeasure` is a later change (section 6),
  because it could move when the message fires. TOC order preserved (integrator: the four lines
  replace `Verify.lua`).
- *Tests.* New `tools/verifycheck.lua` (tbc): a golden transcript of `/md verify`, `/md profile`,
  `/md calibrate`, `/md coach 1`, `/md coachrun 1` and `/md simrun` under the stub, captured on the
  parent commit before the first edit and equal after. Equal counts: `simcheck`, `regencheck`,
  `reccheck`, `importcheck`, `restcheck`.
- *TBC.* Yes (file layout only). No behaviour change.

### Wave 5 -- one command, one combat flag

**P13. One honest command** -- Q2 (aliases, `RegisterEvent`), Q4, Q5, Q7, Q9 (library only), Q15
(checksum, usage lines, smoke runs, reviewui's wait), A10 (identity checks).
- *What.* (a) apicheck rule 8 follows `local NAME = <param>` aliases; a rule forbids `RegisterEvent(`
  outside `Client/` and `Core.lua`, and this task moves the one offender, `UI/ReplayWindow.lua:1993`'s
  raw `PLAYER_REGEN_DISABLED` frame, onto `MD:On` (no allow-list). (b) Q4: the harness exits with a
  distinct skip code (3) instead of 0; the `HARNESS_FLAVOUR` global stays as it is, so none of the 52
  suites is edited; probecheck adapted to the code. (c) Q5: `tools/check.sh` / `make check` -- every
  suite under each declared flavour, rc and footer required, a `FAIL` or a skip under a requested
  flavour is a failure, apicheck, textcheck and both python selftests, counts compared with
  `tools/data/expected-counts.json` (a decrease fails); `make release` and `make install` depend on it
  (`NO_CHECK=1` overrides). (d) Q7: releasecheck asserts its scratch copy first, falls back to `find`,
  splits the folded check into four; the twin TOCs are asserted identical but for the marker line, and
  modulecheck asserts the three `Module.lua`/`Ready.lua` pairs and each module's two TOCs identical.
  (e) `tools/lib/t.lua` (`check`, `section`, `done`, `Ascii`, `Strip`, `CapturedChat`) -- used by new
  suites from here on; no mass migration. (f) Q15: `run.sh` pins the Lua 5.1.5 sha256; `strategies`,
  `solvercmp`, `wclcheckkit`, `reproduce`, `healcheck` print a usage line when their default file is
  absent, and `check.sh` smoke-runs `reproduce` and `strategies` on `tools/data/practice/1790701698.lua`;
  `reviewui.lua:266` asserts `MD.coachSearch == nil` right after the click.
- *Tests.* apicheck selftest +2 (alias case, raw `RegisterEvent`); `check.sh` run once with a
  deliberately failing suite and once with a suite mis-declared as tbc-only (both must fail); `replayui`
  equal count (the regen frame now on `MD:On`).
- *Integrator.* `expected-counts.json` generated once at the end of wave 5; TOOLS.md section 1 becomes
  "run `make check`"; CLAUDE.md's hand-kept counts go.
- *TBC.* `ReplayWindow.lua`'s combat hook dispatches through `MD:On` (same event, same handler).

**P14. One combat flag and a TTO test** -- A28 (consumers), A9 (PullBudget's in-place sort).
- *What.* `TTO.Compute`, `Widget.UpdateVisibility`, `PullBudget:Lines`, the Advisor's two checks,
  `Core_TBC`'s gear reminder and `Clock_Forever` read `MD.inCombat` (P11); the TBC stub's
  `UnitAffectingCombat`/`InCombatLockdown` answer the fired regen events instead of `false`; `replayui`
  drops its adapter patch. PullBudget's median stops sorting the caller's table. New
  `tools/ttocheck.lua`: a scripted spend and regen stream through `Compute` and the display latch --
  warmup -> oom, the confidence gate (digits vs bound), `hold`, the rest segment, the arrow.
- *Tests.* `ttocheck` new (a fresh suite: it cannot fail first; the task file records a mutated
  confidence gate turning it red). Equal counts: `regencheck`, `reccheck`, `runcheck`, `clockcheck`,
  `replayui`.
- *TBC.* Yes: a `/reload` mid-fight now starts TBC in combat (the R36 fix Forever already has).
  DECISIONS one line.

### Wave 6 -- practice policy, escaping, the TBC verbs

**P15. Practice policy seam** -- A6a, A30 (the practice writer's missing fields).
- *What.* `MD.Practice.policy = { defaultBinds, kitIsLive }`; the TBC value (the author's Cell binds,
  `kitIsLive = false`) is the default inside `Engine/Practice.lua`; `Kit_Forever.lua` installs
  `{ defaultBinds = {}, kitIsLive = true }`. `OnForever()` and the three `MD.API.client` checks in
  PracticePanel and BindingsWindow read the policy. apicheck forbids `MD.API.client` outside `Client/`
  and `UI/Dump_Forever.lua`. Practice's own `Esc` copy goes to `MD.Text.EscASCII`. A30:
  `Practice.Session:Finish` writes `names` and `threatOn` as `FightRecorder` does (empty `threatOn`:
  practice has no threat).
- *Tests.* `practice` (+2: a finished session's stream has `names` for every roster index and a
  `threatOn` table); equal counts `practiceui`, `practiceforever`, `bindscheck`; apicheck selftest +1.
- *TBC.* Shared files; the two new stream fields only.

**P16. One escaping rule and one set of formatters** -- A9 (consumers).
- *What.* Replace the local `Esc`, `K`, `Clock`, `Median` copies in Dump_Forever, SpellsPane_Forever,
  Dashboard_Review, ReplayWindow, Measure, SpendTracker, Dashboard_Waste, SimWindow with `MD.Text` /
  `MD.Util`, each file keeping the meaning it has today (pipe-doubling vs reversible ASCII; the Waste
  view's 10000 threshold stays a named argument). The probe keeps its own copy.
- *Tests.* Equal counts: `consolecheck`, `measurecheck`, `spellsui`, `reviewui`, `reviewforever`,
  `replayui`, `replayforever`, `simwindow`, `dashui`.
- *TBC.* Shared files, no behaviour change (SpendTracker's even-n median: the task checks whether its
  `math.ceil` median differs from `MD.Util.Median` on the fixtures and keeps its own rule if it does,
  with a comment; a change there is a model change and needs a decision).

**P17. The TBC verbs onto `MD:AddCommand`** -- A1 (the TBC half).
- *What.* First, before any edit: new `tools/slashcheck.lua` (tbc) runs **every** TBC verb and alias
  (`""`, help, options/config/settings, lock, unlock, reset, mute, drink, rest, practice [start],
  binds/bindings, spelltip, tooltip/tip, window [valid, invalid], verify, profile, export,
  calibrate/calib, fsrtest, regentest, spamtest, simrun, simreplay, coach, sim, replay, run, coachrun,
  debug, an unknown verb) under the stub and records the chat lines and the functions called; this
  golden transcript is committed on the parent commit. Then `Core_TBC.lua`'s `if` chain becomes
  `MD:AddCommand` registrations **in `Core_TBC.lua`, where they are today** (no verb moves file; moving
  one next to its owner happens when that file is next touched), registered in `MD.COMMANDS`' order
  so the generated help is byte-identical; aliases registered as hidden aliases. `MD.SlashFallback`
  and `MD.COMMANDS` are deleted; `MD:Commands()` (Core.lua) feeds `UI/Options_About.lua` and the
  unknown-verb help.
- *Tests.* `slashcheck` equal to its golden transcript; `corecheck` +2 (every registered verb appears
  in `MD:Commands()`; an alias runs its verb and is not listed twice).
- *TBC.* Structure only; byte-identical output (the golden transcript proves it).

### Wave 7 -- the recordings router, the kit's owner

**P18. One recordings router** -- A5, B16's root.
- *What.* `Engine/Recordings.lua` (TBC TOC and the Forever main TOC; pure):
  `Register(prefix, provider)`, `Get(spec)`, `List`, `Pin` (capped at `MAX_PINNED`). Providers:
  `FightRecorder` (bare `N`), the run recorder (`a:b`), Practice (`pN`), `Recorder_Forever` (bare `N`
  on Forever). `MD:GetRecording(spec)` stays as the router's entry point, so its callers
  (`UI/ReplayWindow.lua`, `UI/Dashboard_Review.lua`, `Engine/ReviewCommands.lua`, the Replay module's
  commands) are **not** edited in this task; the two old definitions and `Recorder_Forever`'s
  `== nil` patches go. Both recorders read `MD.Util.RECORD_GATE`. Each provider keeps its own
  retention policy (which recording is dropped); only the address and the pin cap are shared.
- **The grammar change, decided here.** Today an address neither parser reads (`foo`, `2x`) silently
  means recording 1 on both lines (`tonumber(spec) or 1`), which is how B16 printed a card for the
  wrong fight. The router answers nil for it, so every caller prints its existing "no recording"
  line. An empty or nil address still means 1. On Forever `a:b` still answers nil (no run provider).
  This changes TBC (`/md replay foo` refuses instead of opening recording 1): DECISIONS "an address
  that does not parse is refused".
- *Tests.* New `tools/recordingscheck.lua` (both flavours: the grammar table -- `""`, `1`, `3`,
  `p2`, `2:7`, `foo`, `2x`, `p`, `:7` -- against each flavour's providers; a third pin refused);
  `practice` (+1: `p1` reaches the practice provider through the router); equal counts `recordcheck`,
  `runcheck`, `reccheck`, `reviewui`, `reviewforever`, `coachforever`, `replayui`.
- *TBC.* Yes: the unparsable-address refusal (above); nothing else.

**P19. The kit has an owner** -- A12, A11 (first step).
- *What.* `Engine/Kit.lua` (TBC TOC, and the Replay module before `Kit_Forever.lua`): `Kit.FIELDS`
  (the comment at `RankMath.lua:411-417` becomes the table), `Kit.Validate(kit)`, `Kit.Snapshot` /
  `Kit.Restore` moved out of `SimModel` and `Kit_Forever` (old names kept as aliases). Both builders
  end with `Validate`. `Spells/Book.lua` gains `Book.generation`, a counter bumped by every scan that
  changes an entry (no counter exists today); `Kit_Forever.SpellKit` caches on it, returns the same
  table while it is unchanged, and writes `cdb.kit` only when the kit changed.
- *Tests.* `kitcheck` (+4: both builders validate; a kit missing `castBase` fails validation; two calls
  with an unchanged book return the same table and write `cdb.kit` once; a rescan that changes one
  entry bumps the generation and rebuilds). Equal counts: `simcheck`, `importcheck` (byte-for-byte),
  `restcheck`, `practice`, `practiceforever`, `bookcheck`.
- *TBC.* `RankMath.lua` gains one call; no behaviour change.

### Wave 8 -- defaults declared once, the review commands shared

**P20. Defaults declared once** -- A3 (consumers).
- *What.* The engine's settings are declared once, by the file that owns the rule:
  `Engine/SimModel.lua` calls `MD:RegisterDefaults{ simFullHp = 0.85, simFloor = 0.30, simBigHit =
  0.15, simReaction = 0.5, replaySpeed = 1, ... }` with every key it and the planner read, and
  `SM.GATES[...]`'s defaults are registered there too (`SM.GATES` keeps the setting name; its
  `default` field reads the registry). `Replay/Gates_Forever.lua` registers its two gate defaults.
  The inline literals go: `SimModel.lua:228, 229, 306, 1398, 1670`, `SimPlanner.lua:891, 1007, 1838`,
  `ReplayWindow.lua:1367, 1693`, `Options_General.lua:289-290`, all through `MD:Setting(key)`.
  `Core_TBC.lua`'s `DEFAULTS` loses the keys now registered (values identical); `Core_Forever.lua`'s
  `DEFAULTS` needs no hand-copied keys (the registry back-fills them when the Replay module loads).
  The Replay module's own `REPLAY_DEFAULTS` move in P21 (it owns that file this wave).
- *Tests.* New `tools/defaultscheck.lua` (both flavours: every registered default equals the old
  literal; every `MD.db.<key>` read in a file on the flavour's TOCs, found by scanning the sources, has
  a default after all modules load, `REPLAY_DEFAULTS` counted as declared until P21 lands; on a fresh
  db the Options sliders show 85 and 30). Equal counts: `simcheck`, `solvercheck`, `coachforever`,
  `gatecheck`, `replayui`, `simwindow`.
- *TBC.* No behaviour change (same values, one place).

**P21. The review commands, shared** -- A1 (the Forever half), A2 (the commands part).
- *What.* `Engine/ReviewCommands.lua` (created by P12 on TBC) is also listed by the Replay module
  (integrator), and `Replay/Commands_Forever.lua` shrinks to `/st replay` and its module defaults (now
  `MD:RegisterDefaults`); `/st rec` stays in `Recorder_Forever`. `MD.ValidationReportForever` stays as
  an alias for `replayforever`. Where the two implementations differ today, the shared one does this:

  | Difference | Shared behaviour | Line that changes |
  |---|---|---|
  | Escaping | `MD:PrintSafe` (Forever's `EscKeepColours`) for every line on both lines | TBC, only for a zone, name or spell with a pipe, backslash or non-ASCII byte (none in the golden transcript) |
  | Energize line | printed when `v.energize > 0` (TBC's text) | neither (a v3 validation has no energize) |
  | Copy box for a card over 6 lines | TBC only, behind `ReviewCommands.policy.copyBox` (TBC sets it) | neither |
  | Header casts / mana | `rec.ownCasts` / `rec.spent` when present, else counted from the stream | neither |
  | Command prefix in hints | `MD.SLASH` (`/md` or `/st`) | neither |
  | Coach address pattern | `^([pP]?[%d:]*)%s*(%a*)$` | neither (P5 already fixed Forever) |
  | `coachrun` | registered only when `MD.RunRecorder` exists | neither |

- *Tests.* `verifycheck`'s TBC golden transcript equal (the coach and coachrun lines);
  `coachforever` and `reviewforever` equal counts with their expected strings unchanged;
  `replayforever` equal; `coachforever` +1 (a zone name with a pipe prints escaped on Forever, as
  today) and `verifycheck` +1 (the same on TBC, the only TBC change).
- *TBC.* One DECISIONS line: coach and validate output is escaped on both lines.

### Wave 9 -- the v3 road, the rank rules

**P22. Stream registry and v3 constants** -- A18 (rest).
- *What.* `SM.scenarioBuilders[v]` / `SM.validators[v]` in SimModel (v2 its own; unknown version
  raises); `Scenario_Forever` and `Gates_Forever` register v3 instead of wrapping; `SM.Threshold` /
  `SM.MeanMax` exported and Gates' copies deleted; gates 1, 2, 4, 7 shared as primitives; one
  `ReconstructHp` (the copy inside `ScenarioV3` goes); the attribution set carried on the scenario so
  gate 8 does not attribute twice; `Modules/SpellTuner_Recorder/Stream_Forever.lua` publishes
  `MD.StreamV3 = { K, FAMILY_KEY }` used by the recorder, the scenario, the gates and
  `ReviewCommands`' casts-and-mana count, with the Replay module asserting at load that no `SM.K`
  value equals `StreamV3.K.HEAL`. SimPlanner and ReplayWindow stop testing `rec.v == 3` (a scenario
  flag instead).
- *Tests.* Equal counts and outputs: `gatecheck`, `scenariocheck` (its "v2 takes the old road"),
  `simcheck`, `replayforever`, `coachforever`, `importcheck` (byte-for-byte), `recordcheck`. New: a
  recording with `v = 9` raises a named error (`gatecheck` +1).
- *TBC.* SimModel is shared: dispatch by table with the v2 default; byte-identical outputs.

**P23. The rank rules and the spell words, once** -- A13, A15 (the R41 gap only).
- *What.* `Spells/RankRules.lua` (TBC TOC and Forever main TOC, pure): `Pareto`, `Suggested`,
  `CastsToOOM`; `RankMath:Compute` and `Book:Rows` call it (`MD.Rules.SUGGESTED_FLOOR`). SpellTip reads
  `entry.dominatedBy` and loses `Dominator`. `Spells/Words.lua` (Forever): cost, cast, per-second,
  value parts, casts, with a `style` argument where spec 3.5 and 5.x want different wording; SpellTip
  and SpellsPane render from it. `SpellTip.Lines` returns `lines, outcome` (no `lastOutcome` field),
  so a rank-row hover no longer overwrites `/st tooltip why`. A15's visible half: `Book:ReadSpell`
  carries the last readable value through a secret description exactly as `BuildEntry` does (R41), so
  a spell outside the book no longer goes blank in combat; the two read paths are not merged here.
- *Tests.* Equal strings: `tipcheck`, `spellsui`, `bookcheck`, `dashui`, `spelltip` (TBC rank table
  and tooltips byte-identical). New: `tipcheck` +1 (`why` after a rank-row hover still names the last
  macro hover); `bookcheck` +1 (`ReadSpell` of a spell outside the book keeps its value and says
  "read before combat" when its description turns secret).
- *TBC.* `RankMath.lua` shared rules; identical results (dashui proves).

### Wave 10 -- the mana pool, the tokens and the theme flag

**P24. The mana pool leaves the widget** -- A29.
- *What.* `Engine/ManaPool_Forever.lua` (`MD.Pool`): the model instance, the cast/regen events,
  `CostFor`, the assume-full rule, `Sample()` (`mana, base, casting, max`), `Pool()`, `Project(now)`.
  `UI/Clock_Forever.lua` paints; `MD.Clock:Pool()` stays as an alias. `Recorder_Forever` samples
  `MD.Pool:Sample()` (no more `MD.Clock.model`). `Book:DefaultPool`'s cached regen reading moves to the
  pool. One pure `MD.Visibility.Want(pct, shown, inCombat, unlocked)` (`UI/Visibility.lua`, both TOCs)
  used by `Widget.UpdateVisibility` and the clock; the line-number citations in `ManaModel` become
  function names.
- *Tests.* `clockcheck` repointed (equal count) and +1 (a cast priced with no clock frame built);
  `recordcheck` (the mana track unchanged on the fixture); equal counts `regencheck`, `reccheck`,
  `spellsui`, `tipcheck`.
- *TBC.* `Widget.lua` calls a pure function with the same thresholds; no change.

**P25. Colour tokens always present, one theme flag** -- A20 (tokens and helpers), the fallbacks of
U31.
- *What.* (a) `UI/Style.lua` defines `UI.THEMED = false`, `UI.PALETTE` and `UI.TEXT` with today's TBC
  literals; `UI/Theme_Forever.lua` sets `UI.THEMED = true` and overwrites the tables.
  (b) **Every existing "is the theme on" test becomes `UI.THEMED`**, because `UI.TEXT` is no longer
  nil on TBC: `Dashboard_Review.lua:28` (the small font), `PracticePanel.lua:102` (`themed`), the
  waiting-key look in `BindingsWindow.lua`, `SpellTip_Forever.lua:46`, `Style.lua:772`,
  `Dashboard_Rows.lua:64`'s option colours, and any other `UI.TEXT and` / `UI.TEXT ~= nil` whose
  branch changes a font, a size, a layout or a behaviour. (c) A `UI.TEXT and` that only picks a colour
  becomes a token read (`UI.Hex/RGB/Fill(token)`, replacing the nine private helpers in
  BindingsWindow, PracticePanel, SpellsPane, Dashboard_Rows, Tooltip, ReplayWindow, Review), with TBC's
  token holding the old literal: `Dashboard_Review.lua:29`, `ReplayWindow.lua:34`, `Tooltip.lua:26`.
  Where TBC files disagree today (three greys for `muted`) the default table keeps each value under a
  named legacy token; unifying them is P34's question to the author.
- *Tests.* `themecheck` (+4: `UI.THEMED` false on TBC and true on Forever; TBC's tokens equal the old
  literals; Review's small font on TBC is `GameFontHighlightSmall`; no `UI.TEXT and` left in a UI file,
  checked by scanning); equal counts `dashui`, `navui`, `reviewui`, `replayui`, `practiceui` (TBC
  colours and fonts by value) and `spellsui`, `practiceforever`, `replayforever` (no `ffcc00` under the
  theme).
- *TBC.* Shared files, no visible change.

### Wave 11 -- Forever settings, Review and the replay

**P26. Settings you can reach** -- U18, U24 (Forever part), U15.
- *What.* Settings -> General in two columns. A **MANA CLOCK** pane: show, lock (unticking shows the
  clock for 60 s, as TBC does), reset position, and a left-click on the clock opens the window
  (`UI/Clock_Forever.lua`). A **REVIEW** pane: auto-coach on open, next pull follows, snapshot ticks,
  let Coach change ranks, full-health %. A **TOOLS** pane: debug console, copy `/st dump`, measure
  on/off. An **About** view listing `MD:Commands()`. The APPEARANCE knobs named by effect ("Text
  size", "Window size") with one sentence each. All in `UI/Dashboard_Forever.lua`; Forever-only files.
- *Needs a mockup* (M1). *Tests.* `wincheck` (+5: each new control writes and applies its key; Reset
  clears the clock position); `clockcheck` (+2: unticking Lock shows a full-mana clock for 60 s and
  hides it after; a left-click calls `MD:ToggleDashboard`).
- *TBC.* No.

**P27. Review answers in the window** -- U20, U22, U25 (Forever), U17 (Review's list), A17
(`SP.CardLines`), A31 (`g.short`).
- *What.* `SP.CardLines(...)` returns structured lines (`{ text, tone }`); `SP.Card` joins them into
  exactly today's chat text. Gates carry a `short` verdict so the pane stops parsing prose. **Under
  `UI.THEMED` only:** Review's list on `CreateTable` with T30's options and a scroll frame (T30's table
  gains scrolling and a double-click callback in `UI/Dashboard_Rows.lua`, off unless asked for); a
  **result area** under the list showing the last card or validation as lines and the coach's
  progress; chat keeps one line; double-click plays; a right-click row menu (Play, Coach, Coach anyway,
  Validate, Pin, Export) from new `UI/ContextMenu.lua` (both main TOCs; built on the dropdown's list
  look, a new file so this task does not touch `UI/Style.lua`). The `Coach*` star and shift-click stay
  until the author rules (U22).
- *Needs a mockup* (M2). *Tests.* `reviewforever` (+5: the card lines equal the chat card; the result
  area shows the validation after Validate; double-click opens the replay; the menu's Coach anyway
  forces; 36 rows scroll and the last is reachable); `reviewui` equal counts and the chat card
  byte-identical (TBC keeps P9's tail line); `coachforever`, `gatecheck` (+1: every gate has a
  `short`); `dashui` equal (the table's new options are off by default).
- *TBC.* Shared files; nothing TBC shows changes (gated on `UI.THEMED`).

**P28. The replay: stable layout, a readable verdict, the keys it promises** -- U21, U23, U27.
- *What.* **Under `UI.THEMED`:** when auto-coach starts, both columns are laid out at once, the right
  one dimmed and titled `SUGGESTED  coaching... N plans`; the size never changes for that fight. A
  status band under the header: the fight on the left, the verdict on the right in `good`/`bad`, a
  **Coach anyway** button where the slash command is quoted today; the reconstruction caveat as one
  word in the band and a marker in the bars' tooltip. **The keyboard, on both lines** (the TBC
  tooltip already promises Space): Space toggles, Left/Right seek 5 s, every other key propagates
  (practice's pattern). Because Space and Left/Right are jump and turn by default and TBC does not
  hide the replay in combat, the keyboard is enabled **only while the pointer is over the window and
  never in combat**: `EnableKeyboard(false)` on `PLAYER_REGEN_DISABLED`, on `OnLeave` and on hide;
  `EnableKeyboard(true)` only on `OnEnter` out of combat. So a failed `SetPropagateKeyboardInput`
  (it is only `pcall`'d) can swallow keys at most while the player is pointing at the window out of
  combat. Practice keeps its own rules (it ends in combat).
- *Needs a mockup* (M3). *Tests.* `replayforever` (+4: the window width at open equals the coached
  width while coaching; the band's verdict text; Space toggles playing; an unbound key propagates);
  `replayui` (+4 on TBC: Space toggles with the pointer over the window; the keyboard is off with the
  pointer elsewhere; `PLAYER_REGEN_DISABLED` turns it off with the pointer over the window and it
  stays off until the pointer re-enters after combat; the layout and band are unchanged on TBC);
  `practiceforever` (practice keys unchanged).
- *TBC.* The keyboard with its two guards (DECISIONS one line); the band and the fixed layout not.

### Wave 12 -- no dead ends

**P29. No dead ends** -- U11, U19, A24 (`nav:ReplacePane`), U24 (the TBC label).
- *What.* `nav:ReplacePane(group, view, pane)` in `UI/Style.lua` (a real API instead of `nav.panes`
  internals). The Review/Practice placeholders from one `MODULE_VIEWS` table in
  `UI/Dashboard_Forever.lua` through it, each with a **Turn on** button (per the author, section 8.6)
  and a **Reload UI** button where a module unloads at reload. One chat line the first time the window
  hides for combat (`UI/Windows_Forever.lua`). `/st dump` ordered client, saved variables, modules,
  errors, one capabilities summary, then the table and the log (`UI/Dump_Forever.lua`). The TBC label
  "Danger below (%)" becomes "Danger line for built fights (%)" with a true tooltip
  (`UI/Options_General.lua`; the only TBC change here, a text fix).
- *Needs a mockup* (M1's placeholder frame). *Tests.* `navui` (+1 `ReplacePane`); `reviewforever` /
  `practiceforever` (the swap through `ReplacePane`; the Turn on button's action per the author);
  `wincheck` (+1: the combat line printed once); `consolecheck` (dump order); `dashui` (the label).
- *TBC.* The label only.

### Waves 13-16 -- the kit

**P30. Kit primitives: pixel edges and one selection language** -- A20 (primitives), U1 (nav), U3.
This is the part spec 4.3 and the approved mockup already show.
- *What.* `CreateButton`, `CreateCheckButton`, `CreateEditBox`, `CreateSlider`, `CreateScrollFrame`,
  the movable frame's header read tokens (`BUTTON_COLORS` derived from the palette; on TBC the tokens
  hold the old literals, so the colours are equal); their edges and insets through `UI.px` and
  registered for `RestylePixels`; rules and bars at `UI.px(1)`/`px(2)` (`UI.px` returns `n` on TBC).
  **Under `UI.THEMED` only:** the button group's active style = `selected` fill + 2-px accent bar (left
  on nav buttons, bottom on view tabs), hover kept on the active button.
- *Tests (fail first).* `themecheck` (+3: a button under `UI.PIXEL` has `edgeSize == px(1)`; the active
  nav fill differs from hover and shows a bar under the theme; `RestylePixels` restyles a button);
  `navui` (+1: on TBC the active style is today's); `dashui`, `navui`, `reviewui` byte-identical on TBC.
- *TBC.* No visible change (tokens equal the literals, `px` is identity, the selection style is gated).

**P31. Kit layout and sizes** -- U14, U26, U30, U31 (layout parts).
- *What, all under `UI.THEMED`; TBC keeps every current size and position:* view-button widths from
  `GetStringWidth()` (TBC keeps `#v.text * 8 + 16` at `UI/Style.lua:593`); check hit rects from the
  label's width; the header title between back and `x`; nav and view rows aligned; sheets get the 20x20
  `x`; the grip drawn as three 1-px lines and hidden where a group's minimum equals its size
  (`UI/Windows_Forever.lua`). Ungated because they are additive: `UI.H = { button = 20, small = 18, row
  = 20, toolbar = 22 }` and the two ARIALN fonts defined in Style (panes adopt them when touched);
  `CreateMask` takes an optional line of text (no caller on TBC passes one).
- *Tests (fail first).* `navui` (+3 under `S.Geometry`: widths from text under the theme; nav and view
  rows share a top under the theme; on TBC the widths are `#text * 8 + 16`); `wincheck` (grip hidden on
  Spells); `themecheck` (+1: `UI.H` present); `dashui`, `navui`, `reviewui` byte-identical on TBC.
- *TBC.* No visible change.

**P32. One tooltip** -- A21, U2, U13, U28, U10 (the mechanism), U9 (the Forever clock hover).
- *What.* `UI/Tip.lua` (both main TOCs): one line model `{ l, r, c, rc, wrap }` with token names, one
  renderer, `Show(owner, lines, { anchor = "beside", flip = true })` (SpellsPane's `Place` moved in),
  per-call anchors. **Under `UI.THEMED` only:** `SetMotionScriptsWhileDisabled` on kit buttons so a
  disabled button explains itself (TBC's disabled buttons stay silent, as today); `MD.Tip:Show` renders
  into the kit tooltip; the game's own spell tooltip on a rank row keeps its content (decision 7) in
  the same skin. `UI.SetTooltips` becomes sugar over it; `SpellTip:Render` accepts the new shape (the
  positional arrays for one release). The RankMath-bound builders move to `UI/Tip_TBC.lua` (TBC TOC);
  the Replay module stops listing `UI/Tooltip.lua`. Header hover on the generic table shows
  `col.tooltip` (the mechanism; the words are P34's; TBC columns have none). The Forever clock hover as
  label/value pairs without "secret" or "anchored".
- *In-game check needed:* whether the Spell post-call fires for `SetSpellByID` on the kit tooltip; if
  not, the rank row keeps `GameTooltip`, restyled while a SpellTuner frame owns it.
- *Tests.* `tipcheck`, `spelltip` (TBC tooltips byte-identical, `GameTooltip` still used on TBC),
  `reviewforever` (row tooltip beside the row, flipped at the right edge under `S.Geometry`),
  `clockcheck` (the hover lines), `dashui` (header hover on the generic path; a disabled TBC button
  has no motion scripts while disabled).
- *TBC.* Shared files; TBC keeps `GameTooltip` and its behaviour until decision 10.

**P33. Kit behaviours: lists, the rail, font events** -- U12, U8, U16, A31 (events).
- *What.* Dropdown lists flip up when they would leave the screen, sub-lists flip left (both lines: a
  list off-screen is a bug; DECISIONS one line); chevrons as 8x8 textures with the letters as
  fallback, **under `UI.THEMED` only**. The rail: a row tooltip ("Suggested: Rank 1 of 2 known"),
  controls resized and `x` separated (the exact layout per mockup M4), rows in a scroll frame when they
  outgrow the rail. `UI.ApplyFonts` fires `FONTS_CHANGED` and the kit fires `UI_POPUP`; SpellsPane
  subscribes instead of wrapping `ApplyFonts`, and `UI/Windows_Forever.lua` instead of assigning
  `UI.OnPopup`.
- *Needs a mockup* (M4, the rail controls). *Tests.* `navui` (+3 under `S.Geometry`: a list near the
  bottom opens upward; a sub-list near the right opens left; 25 rail rows scroll and the footer stays),
  `spellsui` (the re-pitch on `FONTS_CHANGED`), `wincheck` (ESC closes an open list; the popup event
  reaches the manager), `dashui`/`navui` TBC equal but for the flip.
- *TBC.* The flips only.

### Wave 17 -- words and tones (after mockup M5 and the author)

**P34. Words and tones** -- U7, U9, U10 (words), U1 (table selection), the TBC grey unification of P25.
- *What.* One vocabulary on Forever ("Per mana", "Per sec", "Casts" with header tip "chain casts from
  a full pool"; the tooltip "Casts to OOM: 6 from full, ~5 now"); the Suggested line as
  "Rank 1 (+2% per mana)"; the `dominated` tag renamed or explained (the author's word); header and tag
  tooltips, one sentence each from the spec's definitions. `disabled` only for inert controls and the
  numbers of a not-learned or gap row; the explanations in `muted`, the tag in `label`, headers 12 px in
  `label`; `text2`/`label` merged. A selected rank row marked by an outline or a white left bar, fill
  reserved for the suggested one.
- *Needs a mockup* (M5) and the author's word on `dominated`. *Tests.* `spellsui`, `tipcheck`,
  `themecheck` updated to the new strings (a string change is the point, so the counts stay and the
  expected strings change, listed in the task file).
- *TBC.* No, unless the author also takes the TBC grey unification.

### P35. Docs (integrator, at every wave end)

CLAUDE.md rows for new files (`Engine/Recordings.lua`, `Engine/ReviewCommands.lua`, `Engine/Kit.lua`,
`Engine/RegenMeasure.lua`, `Engine/SimSelfTest.lua`, `Diagnostics_TBC.lua`, `Spells/RankRules.lua`,
`Spells/Words.lua`, `Engine/ManaPool_Forever.lua`, `UI/Visibility.lua`, `UI/ContextMenu.lua`,
`UI/Tip.lua`, `UI/Tip_TBC.lua`, `Stream_Forever.lua`, `tools/check.sh`, `tools/lib/t.lua`,
`tools/textcheck.py`, `tools/data/flavours.txt`, and the new suites `costcheck`, `ttocheck`,
`verifycheck`, `slashcheck`, `recordingscheck`, `defaultscheck`), and the missing `Spells/Tabs.lua` and
`Data/DruidSpells.lua` rows; the "keep harness.lua's list in step" sentence removed; counts removed
from prose; DECISIONS entries named in the tasks; HISTORY per wave; TESTING section 44 (section 9
below); `docs/review/2026-09-30-review.md` from `REVIEW-2026-09-30.md` with a "Fixed in" line per B.

### 5.C Conditional wave -- only on the author's yes to decision 10 (TBC opt-in)

Put to the author with U4's list: gold everywhere and the suggestion said three times; 10-pt
left-justified numbers; four prose lines above the table; a see-through window; HIGH-strata windows
interleaving; one ESC closing everything; nothing hides in combat; a separate bindings window; two
clock looks. On a yes, `SpellTuner_TBC.toc` lists the theme and `UI.THEMED` becomes true there, which
is what turns on everything P27-P33 gated.
- **C1. Window manager on TBC** (A22, A6c): the manager takes its knowledge from the dashboard at
  `Register`; the ESC stack becomes `UI/EscStack.lua`; theme (renamed `UI/Theme_Flat.lua`) and manager
  (`UI/Windows.lua`) listed on `SpellTuner_TBC.toc`; the `if MD.Win` else-branches deleted; positions
  migrated with `Win:Adopt`. Tests: all TBC suites, `wincheck` under tbc.
- **C2. TBC tables** (U5, A23): the TBC rank table, Review and Waste as `opts` sets on the one generic
  table (right-justified numbers, 20-px rows, zebra, header rule, the bar marker and a Tag column
  instead of the gold note); the second `Render` deleted. `dashui` rewritten to the new bytes.
- **C3. TBC Spells view** (U6): the Forever structure (header, chip + one comparison line, table)
  with TBC's numbers; "Effective" as "After overheal"; the Simulate strip folded. *Needs a mockup* (M6).
- **C4. One clock look** (U4): the TBC widget on the kit's font and backdrop, the unlock text in the
  accent. *Needs a mockup* (small; M6's second frame).

---

## 6. Review items not taken, and why

| Item | Why not now |
|---|---|
| A7 macro chain out of the adapter | The macro shapes are unverified; wait for the author's `macro` probe lines (T25a), then move it. |
| A8 split the probe | It works and is well covered (probecheck 87); a split buys little until the probe changes again. |
| A10 one layout file for the module-path rule | P3 shares the interface bands (the launch risk) and P13 asserts the twin TOCs; the "module entry under `Engine/` resolves at the root" rule in three tools has never disagreed. With the next layout change. |
| A11 the engine reads the kit, not `MD.SpellData` (~130 sites) | Wide and mechanical; P19 gives the kit an owner and a validator first, which is what makes the migration safe. Do it when a second class or Wild Growth needs it. |
| A14 RankMath behind the adapter, `RankMath.info` dropped | Medium risk on 20 files for a gain that arrives only when Forever needs talent-aware formulas (probe Q6 open). |
| A15 Book: one read path, owns its scan tick, `Get()` cache-only | P23 takes the visible part (R41 in `ReadSpell`) and P19 adds the generation counter; the merge of the two read paths and the scan tick change when `BOOK_CHANGED` fires, which the Spells pane's refresh depends on. With A26. |
| A16 family table, one parser, `Data/` cleaned | Needs a second class to pay; `MD:Provide` (P11) removes the risky part (the `== nil` seams) -- adopted by P18/P22 where they touch those seams. |
| A17 full SimPlanner split | P2 (one `SP.PARAMS`) and P27 (`SP.CardLines`) take the two parts that caused bugs or block the UI. The rest is 2240 lines of churn with medium risk. |
| A19 `SM:Run` extraction | High risk (zero allocation and tie-break order are load-bearing), no bug traced to its shape. After A17/A18, with the full suite as oracle. |
| One GCD and one crit multiplier (`MD.Rules.GCD`, `CRIT_MULT`) | Six engine and UI files each carry their own; moving them is part of A19/A17. P11 does not define constants no task consumes. |
| `RegenModel:MeasuredMp5` sharing `RegenMeasure`'s bound | Could change when the once-only refusal message fires; P12 is a pure move. Take it with the next `/md regentest` change, with a test on the message. |
| A25 replay window split | Needs Q11's `Inspect()` first or ~200 assertions are rewritten; P7/P28 fix what users see. |
| A26 SpellsPane split | P23 and P24 thin it first; split when the next Spells feature lands. |
| A27 Summary split (TBC) | Moderate blast radius on the TBC line for layering only; P4 fixes its bugs. Revisit with a TBC feature. |
| A30 one stream constructor | Touches the persisted format through three writers; P22 takes the v3 constants (the silent-corruption risk) and P15 the practice writer's two missing fields. |
| A31 accessors, SimWindow `Describe`, setting registry, dead code | Folded into tasks that touch those files where cheap (P17 removes the dead command code, P26/P29 the Forever settings, P3 the interface bands, P8 the level read); the rest when touched. |
| Moving each TBC verb next to its owner file | P17 puts every verb on `AddCommand` in `Core_TBC.lua` with a golden transcript; moving them is a 12-file change for no behaviour, done as each file is next touched. |
| Removing the `MD.* == nil` guards in callers | P18 keeps `MD:GetRecording` as the router's entry so callers stay untouched; each file drops its guards when next touched. |
| Q10 split the stub | Do it when the next large stand-in is added; P1 and P10 fix its lies first. |
| Q11 stable widget ids, `Inspect()` | Adopt per UI task (P26-P33 may add ids for the widgets they build); no bulk migration. |
| Q13 research-tools library | Research tools, one user; P6 fixes the TBC export and P13 adds usage lines and two smoke runs. |
| Q14 baseline refresh | Needs a probe dump of the globals from the author's client first. |
| U17 one window size for every group | Departs from decision 6 (a size per group). The author's call; P27 fixes the look of Review, which is the larger half of the complaint. |
| U29 SimWindow's table | Low traffic; demote or rebuild when Practice supersedes it. |
| The minimap button on Forever | Not in spec 8.1 or mockup M1; a new surface. The author's call (section 8.10). |
| Style.lua split into four kit files (A20) | Mechanical; it would let kit tasks run in parallel, which the author asked not to do anyway. Revisit if the kit keeps growing. |

## 7. Visual changes that need a mockup

Each is a short addition to `docs/mockups/forever-ui.html` (same palette and fonts) for the author to
approve before its task starts.

- **M1 (P26, P29). Settings -> General in two columns**: left SPELL TOOLTIPS, APPEARANCE ("Text size",
  "Window size" with a sentence each), WINDOWS; right MANA CLOCK (Show, Lock in place, Reset position,
  "Show now"), REVIEW (five checkboxes/sliders), TOOLS (Debug console, Copy dump, Measure). Plus the
  About view (the command list in `FONT_NUM` columns) and, for P29, a module placeholder with its Turn
  on / Reload UI buttons centred in the pane.
- **M2 (P27). Review with a result area**: the list (20-px rows, zebra, right-aligned numbers, a
  scroll bar) on top, a titled RESULT pane below it showing a validation report (label/value lines,
  failing gate in `bad`) and, in a second frame, a coach card with its progress line; the right-click
  row menu open on one row.
- **M3 (P28). The replay while coaching**: both columns at 968, the right one dimmed with
  `SUGGESTED  coaching... 120 plans`; the status band under the header (`#3  Underbog  today 21:14  1:52`
  left; `does not replay: health` in `bad` and a `Coach anyway` button right); a second frame with a
  fight that replays (`replays` in `good`).
- **M4 (P33). Rail rows on hover**: the `R1` tag kept, `^ v` at 18 px, `x` 8 px apart (or `x` only,
  reorder by drag); the row tooltip; a 25-row rail scrolling above the fixed footer.
- **M5 (P34). The rank table's tones and words**: a gap row and a not-learned row in the new tones next
  to today's; a selected row (outline or white bar) next to the suggested row (fill + bar); the header
  tooltip for "Casts"; the tag renamed.
- **M6 (C3, C4, only with decision 10). TBC Spells view** in the Forever structure with TBC numbers,
  and the TBC widget in the kit's look.

### 7.1 Mockups approved (2026-09-30)

`docs/mockups/refactor-ux.html` (M1-M6) approved by the author ("Approve, build it"), with three
choices: **TBC gets the spell rail too** (a task C5 in wave C: the Forever rail, Overview first, the TBC
druid families seeded -- M6's view tabs are replaced by the rail); **rail hover is layout B** (one `x`,
Move up / Move down / Remove in a right-click menu, drag still reorders); **the selected rank row is a
white 2-px bar** (the suggested row keeps its fill + bar). The page's other readings (its closing list)
are accepted; invented wording is adjusted in game.

## 8. For the author

1. **Decision 10 again** (TBC opt-in): section 5.C lists what it would fix on the client you play
   until launch. Nothing in waves 1-17 depends on the answer.
2. **Coach results change (P2).** B6, B7 and B8 make the search reach HoTs-only plans, stop the
   suggested column idling after a Moonfire, and price Swiftmend the way the engine lands it. Cards for
   fights you have already coached will differ. The task shows one before/after card.
3. **Old TBC recordings keep their false CANCELs (P4)**: a cast under a rolling HoT, or one you
   spam-pressed, looks cut short in the ACTUAL column. Fixing old data is not possible cleanly (the
   pending cast was dropped); say if the replay should hide a CANCEL followed by the same spell's
   success.
4. **A third pin (P5)** is now refused with a line on both lines, instead of silently not protecting on
   TBC and losing recordings on Forever.
5. **Review conventions (P27):** keep `Coach*` + shift-click, or replace them with the row menu's
   "Coach anyway" only?
6. **Placeholders (P29):** should "Turn on" switch the module on itself, or only open Settings ->
   Modules (today's rule: a placeholder never loads a module)?
7. **Words (P34):** `dominated` -> `beaten`, or keep it with a tooltip? And unify TBC's three greys?
8. **One window size (U17)** is not planned because decision 6 chose a size per group; say if the jump
   from Spells to Reports bothers you enough to revisit.
9. **Cross-realm targets (B15)** follow the retail convention but were never seen on the beta; the fix
   accepts both spellings. A party with a connected-realm member would confirm it.
10. **The minimap button on Forever**: TBC has one; Forever's spec and mockup do not. Add it (a task
    after P29), or leave Forever with `/st` and the clock's click (P26)?
11. **An unreadable address is refused (P18)**: `/md replay foo` stops opening your newest fight. Say
    if you relied on that.
12. **Replay keys (P28)** work only while the pointer is over the replay and never in combat, so Space
    and the arrow keys keep moving your character everywhere else.

### 8.1 The author's answers (2026-09-30)

1. **Decision 10: yes** -- "I would like to have updated UI on TBC as well once its ready". Wave C
   (C1-C4) runs after wave 17; mockup M6 goes to the author with M1-M5. The author also retired
   ManaDemon: SpellTuner replaces it on both clients (the TBC install and the saved data carried over,
   2026-09-30).
2. Coach cards may change (P2) -- **accepted**.
3. Old TBC recordings keep their false CANCELs (P4) -- **accepted**, the replay does not hide them.
4. A third pin is refused with a line (P5) -- **accepted**.
5. Review conventions (P27): **the row menu's "Coach anyway"**; the Coach* star and shift-click go.
6. Placeholders (P29): **"Turn on" switches the module on** (Settings -> Modules stays the way off).
7. Words (P34): **`dominated` -> `beaten`**, with a tooltip naming the rank that beats it; TBC's three
   greys unify with the theme (follows from decision 10).
8. Window size (U17): **keep a size per group** (decision 6 stands).
9. Cross-realm targets (B15): an in-game check, not a decision -- stays in section 9.
10. **Minimap button on Forever: yes** -- the same button on both lines (left-click opens the window
    on the last view, right-click Settings, drag round the minimap, a setting to hide it); a task after
    P29.
11. An unreadable address is refused (P18) -- **accepted**.
12. Replay keys (P28): **only while the pointer is over the replay, never in combat.**

## 9. In-game checks (for `docs/TESTING.md` section 44)

Paste back as in section 41. Out of combat unless a step says otherwise.

**After waves 1-3 (TBC, 0.16.4).**
1. **Cat form reload (B1).** Shift to Cat, `/reload`. The clock and the Advisor work in caster form
   afterwards; `/md profile` says `usesMana true`. Also paste
   `/run print(UnitPowerMax("player", 0))` while in Cat form (expected: your mana max, not 0).
2. **Tree aura (B2).** With a second resto druid in Tree of Life in your party, stay in caster form and
   open `/md`: no Tree label in the header, the numbers do not flip when they shift or leave range.
3. **Text (B3).** `/md verify`, `/md unlock`, `/md window 99`, and a gear change that moves an efficient
   rank: no boxes; paste the verify block.
4. **Casts under a rolling HoT (B9).** Keep Lifebloom rolling on the tank and hard-cast Healing Touch
   three times in one pull, **pressing the Healing Touch button again two or three times during one of
   the casts**; then move to cancel one cast. `/md replay 1`: three full cast bars, one cut. Also paste
   `/run local f=CreateFrame("Frame") f:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED") f:SetScript("OnEvent",function(_,e,...) print(e,...) end)`
   and then move during a cast: the line shows `player`, a cast GUID and the spell id.
5. **`xpcall` passes arguments (P11).** `/run print(xpcall(function(a, b) return a + b end, print, 2, 3))`
   on TBC and on Forever: expected `true 5` on both. Paste both lines.
6. **Bloom (B10).** After a dungeon with Lifebloom, `/md calibrate` lists a bloom line; the Waste view
   has a Lifebloom bloom row.
7. **Run replay (B21, B22).** `/md replay run 1`, let it cross into pull 2, drag the scrubber to the
   middle: the run jumps there. Pull a mob while the run is playing: at most one chat line.
8. **Two runs (B12).** Stop a run, drink a potion, start a run: `/md run status` shows no potion.
9. **Long lists (P9).** Open Review on a run with more than 30 pulls: the list ends with
   `... and N more`.

**After waves 1-3 (Forever, 0.16.4).**
10. **Pins (B14).** Pin three fights in Review: the third is refused with a line. Pull nine times: the
    ninth is listed.
11. **Scale before replay (B17, B18).** `/reload`, set Window size to 80 % before opening a replay, then
    `/st replay 1`: it opens where you last left it; the window borders are one crisp pixel.
12. **Practice icons (B23).** In practice, point at a tank's Swiftmend icon and press a bound key: it
    heals the tank.
13. **Opener (B19).** Pre-cast Rejuvenation on the pull: the clock's hover counts it in this fight.
14. **Coach address (B16).** `/st coach 2:7`: a refusal, no card.
15. **Client (P3).** `/st dump`: the first line says `forever`.

**After waves 4-10.** Nothing visible should change; any difference is a regression, except the
three listed. 16. `/reload` mid-fight on TBC: the clock shows the in-combat projection at once (P14).
17. `/md help` and `/st help` list every command; each works (P17, P21). 18. `/md replay foo`: a
refusal (P18). 19. `/st dump`: errors appear before the capability table (P29 lands this later; skip
until then).

**After waves 11-16 (Forever unless said).**
20. **Settings (P26).** Settings -> General: move the clock at full mana with Lock unticked (it shows
    for 60 s), Reset it; click the clock: the window opens.
21. **Placeholders (P29).** Reports on a fresh install: the placeholder's button.
22. **Review (P27).** Validate a fight: the report appears under the list, chat has one line.
    Double-click a row: it plays. Right-click: the menu. A 30+ pull run scrolls.
23. **Replay (P28).** Open an uncoached fight: the window opens at full width and the right column
    fills in place. With the pointer over it, Space pauses and Left/Right seek; with the pointer away,
    Space jumps. **On TBC too:** open a replay, pull a mob with the pointer over the replay: you can
    still jump and turn.
24. **Kit (P30-P33).** Hover down the nav column: only the selected group keeps the bar. Every button
    and checkbox border is one crisp pixel at 0.71. Every SpellTuner tooltip, Review's rows and the
    replay's icons included, has the flat skin; a disabled Coach button explains itself on hover. Hover
    a rank row: the game's Healing Touch text with the block, in the flat skin (report if the block is
    missing). A Settings dropdown near the bottom of the screen opens upward. **On TBC:** the window,
    its buttons and its tooltips look exactly as before.

## 10. Revision 2: what changed after the critic

- **Theme flag.** `UI.THEMED` (P25) replaces "gated on `UI.TEXT`"; every existing theme test is
  converted in P25 and every later Forever-only change names it. P31's widths, alignment and header
  move, and P32's `SetMotionScriptsWhileDisabled`, are now gated; TBC keeps `#text * 8 + 16`.
- **Launch.** New P3 in wave 1: the client from the `SPELLTUNER_TOC` marker, one band table for
  `release.sh`, `apicheck.py` and `releasecheck.lua`.
- **Ownership.** Every stub knob for waves 2-4 (raid roster, realm, power type and max, slider clamp,
  mouse focus, `xpcall` arguments) is in P1; Q1 moved into P1 in wave 1, ahead of the Forever fixes.
  The ASCII rule is its own `textcheck.py` and P3 fixes all eleven sites, `UI/Advisor.lua:68`
  included. The harness keeps `HARNESS_FLAVOUR` (no 52-suite edit). `RegisterEvent` is fixed by P13
  itself (no allow-list). P5 owns `coachforever` in wave 2 only. The Review, settings and placeholder
  work is split across waves 11 and 12 so no two tasks add to `reviewforever`; P27 owns
  `Dashboard_Rows.lua` and a new `UI/ContextMenu.lua`; P26 owns `Clock_Forever.lua`; P19 owns
  `Spells/Book.lua` for the generation counter. The section 4 table lists every file a task edits or
  adds an assertion to, and no file appears twice in one wave.
- **Splits.** Old P14 is now P17 (the TBC verbs, golden transcript first, no file moves), P18 (the
  router, callers untouched, the grammar change decided) and P21 (the shared review commands, with a
  table saying which text wins). Old P20 is now P26 (settings) and P29 (dead ends). Old P23 is now P30
  (pixel and selection, approved) and P31 (layout and sizes, gated). Old P1 is now P1 (stub), P3
  (launch, text, simcheck) and P8 (kernel character, wave 3).
- **B9** ends a pending cast only on `UNIT_SPELLCAST_INTERRUPTED` for its cast GUID or on a new own
  start (same spell included); a spam press's `SPELL_CAST_FAILED` is ignored; reccheck has a spam press.
- **B10** resolves the bloom only and states which id reaches `Record` and `Calibration`; Tranquility's
  aliases are asserted unchanged.
- **B15** keeps `name` bare and adds `realm`; a cross-recording match test in `scenariocheck`.
- **A4** states the `xpcall` argument handling (client form plus a stub shim, a trampoline fallback),
  the per-event cost and its measurement, and proves R21/R22 again in `consolecheck`.
- **Replay keyboard** only with the pointer over the window and never in combat, tested on TBC.
- **Dropped items now taken:** A15's R41 gap (P23), A3's consumers (P20), U25 on TBC (P9), Q15's live
  cost (P1), `Invalidate`/`SetTalents` (P8) and the smoke runs (P13), A30's `names`/`threatOn` (P15).
- **Smaller.** B1 answered from `UnitPowerMax(..., 0)`, not a class list. P12 is a real pure move:
  `MeasuredMp5` untouched, coach and validate go straight to their final file. P11 no longer defines
  `GCD`/`CRIT_MULT` (section 6). The minimap button on Forever is a question (8.10), not a task.
