# SpellTuner on WoW: Forever — repository structure and roadmap

Companion to `docs/FOREVER-PLAN.md` (the architecture and the facts it rests on). This is the
*how and in what order*: where files live, which branch carries what, the milestones with their
exit criteria, and how the planner / lead / implementer pipeline moves a milestone forward.
Decided with the author on 2026-09-27: same repository, the name **SpellTuner**, one code line
with per-client TOCs, branches for release lines only.

## 1. Repository structure

### 1.1 One tree, two clients

A WoW client loads the TOC whose suffix matches it and ignores the others. That is the
mechanism by which one folder serves both clients, and it is how the author's Cell fork ships
six flavours. The suffix Forever's client looks for is **unconfirmed** (probe question 9); until
it is, the plain `SpellTuner.toc` is the Forever one, because the newest client is the default.

```
SpellTuner/                         the addon; also the repository root
  SpellTuner.toc                    Forever  (## Interface: 16001)   -- core module
  SpellTuner_TBC.toc                TBC      (## Interface: 20506)   -- the whole TBC addon, as today
  Core.lua                          namespace, db, event bus, ticker, slash, module registry
  Client/
    API.lua                         the ONE file that calls the client; loaded by every TOC
    API_Forever.lua                 the Forever bindings behind MD.API (C_*, secrets -> nil)
    API_TBC.lua                     the TBC bindings behind MD.API (the classic globals)
    Probe.lua                       /st probe: capabilities, per build, diffed
  Engine/                           pure Lua, listed by BOTH TOCs, identical bytes
    SimModel.lua  SimSolver.lua  SimPlanner.lua  ReplayTrace.lua  RunTimeline.lua
    RankMath.lua  Practice.lua  RegenModel.lua  SpendTracker.lua  TTO.lua ...
  Spells/
    Book.lua                        the spellbook read through MD.API: families, ranks, values
    Parse.lua                       description -> numbers (heal, damage, over N sec, every N sec)
    Table_TBC.lua                   the verified TBC table (Data/SpellData.lua today), TBC TOC only
  UI/                               Style.lua and the panes; per-flavour files only where the client leaks in
  Data/                             AuraList, Intuition_TBC, presets (TBC TOC), DruidSpells
  Verify.lua

SpellTuner_Recorder/                LoadOnDemand, Dependencies: SpellTuner
  SpellTuner_Recorder.toc           Forever: the v3 stream (health events, UNIT_COMBAT, own casts, damage meter)
  SpellTuner_Recorder_TBC.toc       TBC: today's FightRecorder / RunRecorder / Summary / Overheal / Calibration
SpellTuner_Replay/                  LoadOnDemand, Dependencies: SpellTuner, SpellTuner_Recorder
  ...                               engine wiring, gates, coach, Review tab, replay window
SpellTuner_Practice/                LoadOnDemand, Dependencies: SpellTuner, SpellTuner_Replay
  ...                               session UI, panel, bindings window, imports

tools/                              the offline harness
  wowstub.lua                       two profiles: `tbc` (today's) and `forever` (C_*, secrets, no combat log)
  harness.lua                       loads the flavour's file list from ITS TOC, not a hand-kept list
  apicheck.py                       our client calls vs the build's baseline (data/forever_api.json now)
  <suites>.lua                      each declares which profiles it runs under
docs/
  FOREVER-PLAN.md  ROADMAP-FOREVER.md  probe/<build>.md  tasks/T<n>-<slug>.md
  SPEC-*.md  DECISIONS.md  HISTORY.md  PLAN.md  TOOLS.md  TESTING.md   (continuing)
```

**The module folders are sibling addon folders.** `release.sh` builds all four from their TOCs
into `dist/<name>/` and zips them together; the game's AddOn list shows four entries, and the
in-game module switches call `C_AddOns.LoadAddOn`. A module the user has never enabled costs
nothing — not a frame, not an event, not a table.

**The rule that keeps the tree honest:** a file listed by both TOCs contains no client call and
no flavour check. If it needs one, the call moves into `Client/API.lua` and the file stays
shared; if the *shape* differs (a recorder that reads events vs one that reads a log), the file
is per flavour and each TOC lists its own.

### 1.2 Branches and tags

| ref | carries |
|---|---|
| `master` | both flavours; every release is cut from here |
| `manademon-final` (tag) | the last state under the old name, v0.15.4 + the plan |
| `tbc-v*` (tags) | TBC releases after the split, cut from master |
| `forever-v*` (tags) | Forever releases |
| `tbc` (branch, **only if needed**) | created the day a TBC fix cannot live in shared code; until then it does not exist |

Version lines: the TBC flavour continues `0.15.x` → `0.16` as it lands changes; the Forever
flavour starts at **`1.0.0-beta.1`** with milestone M2 and becomes `1.0.0` at the first release
that records and replays a fight on the launch client. One `## Version:` per TOC.

### 1.3 The harness serves both

`tools/harness.lua` reads the file list out of the flavour's TOC (`--flavour forever|tbc`, default
forever), so the harness file list can no longer drift from the TOC — a rule `CLAUDE.md` has
asked humans to keep by hand until now. `wowstub.lua`'s `forever` profile fakes what §1.3 of the
plan says exists and **nothing that does not**: no `CombatLogGetCurrentEventInfo`, no `UnitAura`;
`C_Spell`, `C_SpellBook`, `C_UnitAuras`, `C_DamageMeter`, `TooltipDataProcessor`, `UNIT_COMBAT`;
and a **secret value type** — a table whose metatable raises on `__add`, `__sub`, `__lt`, `__le`,
`__eq`, `__len`, `__index`, `__call`, answers `issecretvalue`, and is returned by the stub for
enemy health, enemy damage and own auras while `S.inCombat`. Every suite that runs under the
`forever` profile runs with secrets on.

## 2. Milestones

Each milestone has an exit criterion that is a measurement, not a feeling. The lead writes the
tasks; nothing in a milestone starts on a fact the probe has not confirmed for the current build.

### M0 — the probe (phase 0)

*Exit:* `docs/probe/70009.md` (or the current build) exists, written from Healroot, and answers
the nine questions in `FOREVER-PLAN.md` §6 plus TOC suffix. `tools/probecheck.lua` green.

Tasks: **T0** -- done 2026-09-27 (`docs/tasks/T0-probe.md`, lead-accepted; `tools/probecheck.lua`
27 ok). The exit now waits on the author running `/st probe` on the beta.

### M1 — the frame (phase 1)

*Exit:* `SpellTuner.toc` loads on Forever with zero errors on login, `/st` opens an empty
dashboard window in the Cell-style kit, the module switches exist and load/unload the three
sibling addons, the debug console captures and dedupes errors, and `tools/run.sh --flavour
forever` runs a suite that trips on arithmetic with a fake secret. `apicheck.py` passes.

Tasks: T1 Client adapter + capability table · T2 module registry, LoadOnDemand siblings, settings
pane · T3 debug console with dedupe and `/st dump` · T4 SavedVariables guard (the kit's seed
workaround if Q7 says so) · T5 harness `forever` profile + secret type + TOC-driven file list ·
T6 `apicheck.py`.

### M2 — tooltips and the dashboard (phase 2) → `1.0.0-beta.1`

*Exit:* hovering any spell of any class in the **spellbook**, on a bar or in chat shows the
SpellTuner block; the dashboard lists every spell in the book grouped by family with ranks,
value, cost, cast, value per mana, per second, casts to OOM, and the suggested rank; the numbers
match a cast on a dummy within the crit spread for three spells of two classes (Healroot plus
one alt). No module beyond core is loaded to do this.

The shape depends on Q1: **dynamic descriptions** → `Spells/Parse.lua` over
`C_Spell.GetSpellDescription`, no coefficient model; **static** → `Spells/Parse.lua` for the base
plus a coefficient model per school, druid first, others VERIFY.

Tasks: T7 `Spells/Book.lua` · T8 `Spells/Parse.lua` (+ the per-school model if static) · T9
tooltip on `TooltipDataProcessor` · T10 dashboard pane on the shared `UI/Dashboard_Rows.lua` ·
T11 clock (TTO) on the adapter · T12 `docs/TESTING.md` for M2 and the dummy measurements.

### M3 — recorder v3 and replay (phase 3) → `1.0.0-beta.2`

*Exit:* a dungeon pull on Forever is recorded (health at event resolution, landed amounts,
own casts with targets, own mana, deaths, the damage meter's totals), replays through the
unchanged engine with every gate passing on a clean pull, and opens in the replay window with
the suggested column. `tools/reproduce.lua` on that recording reads ≥ 90% of the damage meter's
own-healing total.

Depends on Q2–Q5. Tasks: T13 stream v3 + `ScenarioFromRecording` v3 · T14 gates re-founded
(calibration and foreign share from `C_DamageMeter`; enemy-cast and threat inputs removed) ·
T15 `SpellKit` from `Spells/Book.lua` · T16 Review tab and replay window under the adapter · T17
coach and the solver re-measured on Forever recordings.

### M4 — practice (phase 4) → `1.0.0-beta.3`

*Exit:* a practice fight plays, records, replays and coaches on Forever; Cell / Clique /
keybinding import works against the Forever builds of those addons (re-checked, not assumed).

Tasks: T18 session and panel under the adapter · T19 bindings + imports re-verified.

### M5 — launch (phase 5) → `1.0.0`

*Exit:* on the launch client (2026-11-04), level 60 values measured on a dummy for the healing
spells of at least two classes; the solver's margin over the rules re-measured on ≥ 5 Forever
recordings; `docs/TESTING.md` rewritten for Forever.

## 3. The pipeline

- **Planner (this session, Fable)** owns `FOREVER-PLAN.md` and this roadmap, answers
  architecture questions the lead escalates, and re-plans when a probe report contradicts a fact.
- **Lead (Opus, `.claude/agents/lead.md`)** turns a milestone's task line into
  `docs/tasks/T<n>-<slug>.md` with the seven sections, hands it to the implementer, reviews the
  diff against the acceptance lines and the suites, and either accepts (commits, ticks the task in
  this file) or re-issues with the failing line named.
- **Implementer (Sonnet, `.claude/agents/implementer.md`)** does the task and only the task, runs
  `luac` and the suites, and reports; stops and asks on any ambiguity or falsified fact.
- **The author** runs the probe and the in-game checks in `docs/TESTING.md`, and makes the calls
  listed as theirs.

A task is accepted only with its suites green under the flavour it targets, and a milestone is
exited only with its exit measurement in `docs/HISTORY.md`.

## 4. What is not planned

Feral / melee abilities on the tooltip (they scale with weapon and attack power); any feature
that reads enemy health, enemy damage or threat (secret by policy); the TBC flavour gaining
Forever-only features; a second repository.
