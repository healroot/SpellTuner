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
six flavours. The suffix Forever's client looks for is **`_Mainline`** — answered by the first
probe report from the beta (`docs/probe/1.60.1_70009.md`, 2026-09-27: `SPELLTUNER_TOC =
Mainline` with the plain, `_Forever` and `_Vanilla` copies all present). So `SpellTuner_Mainline.toc`
is the Forever TOC and the plain `SpellTuner.toc` is kept as an identical fallback copy (its marker
aside) for a client that matches no suffix; the other two copies are gone (T0c).

```
SpellTuner/                         the addon; also the repository root
  SpellTuner_Mainline.toc           Forever  (## Interface: 16001)   -- core module; the suffix Forever loads
  SpellTuner.toc                    the same, as the no-suffix fallback (marker line apart)
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

**The rule that keeps the tree honest:** **client calls live in `Client/` only.** A file listed
by both TOCs contains no client call and no flavour check; it calls the client through `MD.API`
(`Client/API.lua`, which is itself shared and dispatches to `API_Forever.lua` / `API_TBC.lua`).
If a shared file needs a new client fact, the call moves into the adapter and the file stays
shared; if the *shape* differs (a recorder that reads events vs one that reads a log), the file
is per flavour and each TOC lists its own. `Client/Probe.lua` is the one file that sees raw
client values, because seeing them is its job (T0 stated the rule this way; accepted 2026-09-27).

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
27 ok). **T0b** -- done 2026-09-27 (`docs/tasks/T0b-probe-fixes.md`): the five defects and the
nits an independent three-lens review confirmed before the author's run -- the Q1 diff counting
unreadable descriptions as changes, an unescaped client string, a comparison outside the adapter's
pcall, the stub's secret stand-in described backwards, a self-asserting test -- plus
`issecrettable`, the copy box's letter cap, the per-name rank count and the "show all ranks" step;
`probecheck` 41 ok. **T0c** -- done 2026-09-28 (`docs/tasks/T0c-probe-secrets.md`, lead-accepted):
what the first two reports from build 70009 raised -- the blocked-action dialog recorded and named,
the combat log registered only on demand (`/st probe clog`), the secret question measured, bonus
damage and level in Q1, Q6 at level 10, and the Forever flavour cut to `SpellTuner_Mainline.toc`
plus the plain fallback at `1.0.0-alpha.1`; `probecheck` 57 ok. The exit now waits on the author running `/st probe` on the beta
(`docs/TESTING.md` §35).

### M1 — the frame (phase 1)

*Exit:* `SpellTuner.toc` loads on Forever with zero errors on login, `/st` opens an empty
dashboard window in the Cell-style kit, the module switches exist and load/unload the three
sibling addons, the debug console captures and dedupes errors, and `tools/run.sh --flavour
forever` runs a suite that trips on arithmetic with a fake secret. `apicheck.py` passes.

Tasks: T1 Client adapter + capability table · T2 module registry, LoadOnDemand siblings, settings
pane · T3 debug console with dedupe and `/st dump` · T4 SavedVariables guard (the kit's seed
workaround if Q7 says so) · T5 harness `forever` profile + secret type + TOC-driven file list ·
T6 `apicheck.py`.

Order taken by the lead (2026-09-28), each for a dependency: **T0d** first (the probe stops
registering the combat log, which every M1 suite asserts nothing does), **T5** (the adapter's suite
needs the probe-faithful stub), **T1**, **T1b** (the core split off T2: the registry needs a kernel
the Forever TOC can load), **T6** (so it first passes on that kernel), **T2**, **T4** (T3's dump
prints what the guard records), **T3**.

Done: **T0d** -- 2026-09-28 (`docs/tasks/T0d-probe-no-clog.md`, lead-accepted): `/st probe clog`
gone, Q1 kept per build; `probecheck` 58 ok. **T5** -- 2026-09-28 (`docs/tasks/T5-harness-forever.md`):
`tools/run.sh --flavour forever|tbc`, the harness's file list read from the flavour's TOC, every
harness tool declaring its flavour, the stub's Forever profile keeping secrets as build 70009 does
and pruned to the 69893 baseline (`tools/data/forever_api.json`, the kit's, MIT);
`tools/forevercheck.lua` 13 ok.

### M2 — tooltips and the dashboard (phase 2) → `1.0.0-beta.1`

*Exit:* hovering any spell of any class in the **spellbook**, on a bar or in chat shows the
SpellTuner block; the dashboard lists every spell in the book grouped by family with ranks,
value, cost, cast, value per mana, per second, casts to OOM, and the suggested rank; the numbers
match a cast on a dummy within the crit spread for three spells of two classes (Healroot plus
one alt). No module beyond core is loaded to do this.

The shape is decided: Q1 answered **dynamic** on 2026-09-27 (`FOREVER-PLAN.md` §6), so
`Spells/Parse.lua` reads the value out of `C_Spell.GetSpellDescription`'s text and there is
**no coefficient model and no per-school table**. Where a "per +healing" or "per spell power"
line is wanted, the coefficient is measured from the client (the text at two bonus values), never
typed in. The static branch is dropped from the tasks below.

Tasks: T7 `Spells/Book.lua` · T8 `Spells/Parse.lua` (+ the per-school model if static) · T8b
`tools/refcheck.py` — fetch talentsforever's `data.json` **once** into a gitignored cache and
compare a probe dump or an exported dashboard against it (ranks, learn levels, costs, description
numbers), printing disagreements with both values and the record's `src` / `fx` / `asis`; Wowhead
stays a by-hand check (`docs/REFERENCES-FOREVER.md` §2, §5) · T9 tooltip on
`TooltipDataProcessor` · T10 dashboard pane on the shared `UI/Dashboard_Rows.lua` · T11 clock
(TTO) on the adapter · T12 `docs/TESTING.md` for M2 and the dummy measurements, including the
downrank measurement (`FOREVER-PLAN.md` §6 Q10).

Known from the references before any of it is built (`docs/REFERENCES-FOREVER.md` §4): **no
Lifebloom, Tree of Life, Earth Shield or Circle of Healing on Forever**; costs come as `N Mana`
and as `N% of base mana`; rank 1 of a talent-granted spell is in the book with no trainer; the
spellbook hides lower ranks unless "show all ranks" is on; TBC spell ids do not exist.

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
