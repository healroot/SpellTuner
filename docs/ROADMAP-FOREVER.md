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
`tools/forevercheck.lua` 13 ok. **T1** -- 2026-09-28 (`docs/tasks/T1-client-adapter.md`): `MD.API.Call` / `Bind` /
`Capabilities` / `IsSecret` / `CanRegisterEvent` in the shared `Client/API.lua`, the add-on
bindings and the forbidden combat log in `Client/API_Forever.lua`, the classic names in
`Client/API_TBC.lua`; a secret comes back as `nil, "secret"`; `tools/adaptercheck.lua` 14 / 10 ok (15 / 11 after T1b). **T1b** -- 2026-09-28
(`docs/tasks/T1b-shared-core.md`): `Core.lua` is the shared kernel on the adapter (events with the
forbidden-event guard, callbacks, ticker, Print, identity, db init, the login sequence
`CORE_LOGIN` / `MD_READY` / `CORE_READY`, the slash dispatcher with `MD:AddCommand`); the TBC
addon's own core moved verbatim to `Core_TBC.lua`; `Core_Forever.lua` starts Forever's; `/st probe`
goes through the kernel; `tools/corecheck.lua` 10 / 8 ok. **T6** -- 2026-09-28 (`docs/tasks/T6-apicheck.md`): `python3 tools/apicheck.py`
checks every global the Forever TOCs' files touch (from `luac -l`) against the 69893 baseline and
the adapter rule -- absent names, client calls outside `Client/`, new globals, WoW-less Lua
libraries, the combat log named, unknown `C_` members -- with a fixture (`--selftest`); 0 findings. **T2** -- 2026-09-28 (`docs/tasks/T2-modules-window.md`): the module registry in the
kernel (`MD:DeclareModule` / `SetModule` / `ModuleState`, loading what a module needs first,
remembering the switch, "off" meaning "not loaded after the next `/reload`"), the three
LoadOnDemand siblings at `Modules/SpellTuner_Recorder|Replay|Practice/` (one `Module.lua` each that
tells the core it loaded), `release.sh` building and installing them beside `SpellTuner/`, and
`/st` opening the Forever window (`UI/Dashboard_Forever.lua`: Spells placeholder, Settings ->
Modules); `tools/modulecheck.lua` 12 ok. **T4** -- 2026-09-28 (`docs/tasks/T4-savedvariables-guard.md`): the minimal guard
Q7 allows -- `Core_Forever.lua` records at `ADDON_LOADED` whether `SpellTunerDB` came back (and from
which session), was absent, or was not a table (replaced, never indexed), stamps the session, and
keeps one line for the dump; no seed workaround; `tools/svcheck.lua` 6 / 1 ok. **T3** -- 2026-09-28 (`docs/tasks/T3-console-dump.md`): SpellTuner's own errors caught
through the adapter's `seterrorhandler` binding -- the first of each shown to the client, repeats
only counted, other addons' errors passed through, at most 50 kept; `/st debug` on Forever with the
error count; `/st dump`, one escaped block (client, capabilities, SavedVariables, modules, errors,
debug log); every Forever TOC at `1.0.0-alpha.2`; `tools/consolecheck.lua` 11 / 1 ok.

**M1's offline part is done (2026-09-28).** The exit's in-game half -- zero errors at login, `/st`,
the module switches, the error count and the dump on the beta -- is the author's:
`docs/TESTING.md` §36.

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

Order taken by the lead (2026-09-28): **T7a** (added: the probe dumps every return shape M2 reads,
because only presence had been probed), **T8** and **T8b** beside it, then **T7** (needs the parser
and the stub's shapes), **T9**, **T11** (the dashboard reads the clock's pool), **T10**, **T10b**
(T10's two review follow-ups) beside **T12**. T12 was split: the instrument (`/st measure`) is the
implementer's, the `docs/TESTING.md` section the lead's.

Done (all 2026-09-28, each lead-accepted in its task file):
**T8b** (`fb18fa5`, `docs/tasks/T8b-refcheck.md`) -- `python3 tools/refcheck.py`: a probe dump or the
pane's export against talentsforever's `data.json`, fetched once into the ignored `tools/.cache/`;
`--selftest` against a fixture. **T8** (`cc35daa`) -- `Spells/Parse.lua`: descriptions, cost, cast and
rank texts into numbers, refusing a sentence it does not recognise; `parsecheck` 10 against 54
sourced texts. **T7a** (`309efc1`) -- the probe's `== shapes` (book rows, `GetSpellInfo`,
`GetSpellPowerCost`, learn level, base spell, low-rank flag, tooltip data lines, crit per school,
the same in combat, `UNIT_SPELLCAST_SUCCEEDED` counted); `probecheck` 66. **T7** (`645f83b`) --
`Spells/Book.lua`: the book through the adapter (`MD.API.Copy` / `Constant`, copying bindings),
families of ranks with value, cost, cast, per mana, per second, casts to OOM, dominance and the
suggested rank; the Q6 seam `Book.adjust` (empty); `bookcheck` 13 (14 after T9). **T9** (`fecb3f2`)
-- the block on every spell tooltip through `TooltipDataProcessor`; `tipcheck` 12 (14 after T10b).
**T11** (`2e49ae5`) -- the clock on a modelled pool (`Engine/ManaModel.lua`), marked `~`, the real
pool drawn beside it by `MD.API.DrawUnitPower`; `clockcheck` 13. **T10** (`182f414`) and **T10b**
(`319cc5f`) -- the Spellbook pane on the now-shared `UI/Dashboard_Rows.lua`, sections, export;
`spellsui` 12, `dashui` still 56. **T12** (`0f56662`) -- `/st measure`, one line per cast against its
own text (`in range` / `crit range` / `BELOW range`); `measurecheck` 9. Every Forever TOC at
`1.0.0-alpha.3` (`bf54cbe`).

**M2's offline part is done (2026-09-28).** The exit's in-game half -- the block in the spellbook,
on a bar and in chat, the pane against the real book, and three spells of two classes measured
within the crit spread -- is the author's: `docs/TESTING.md` §37. `1.0.0-beta.1` is cut when that
passes.

**The M2 re-check (2026-09-28, after the author's first M2 run, `docs/probe/1.60.1_70009-m2.md`),
each lead-accepted in its task file:** **T7b** (`0983a4b`) -- the shapes gate: the book reader against
what build 70009 returned (a free spell is free, `|4` expanded, Thorns' reflect not a cast's damage,
`isPassive` kept); `bookcheck` 15, `parsecheck` 11. **T11b** (`04a8747`) -- the clock appears, hides and
words its states as the TBC clock does; `clockcheck` 15. **T10c** (`2a0cba0`) -- the pane's names on one
line, Other only for spells cast for mana; `spellsui` 15. **T12b** (`b7e55b7`) -- `/st measure` pairs
each amount with its own cast (several watches open, a direct amount looked for 0.3 s before its
cast event, ticks by cadence, a two-pass contest), never BELOW on an amount it cannot pin;
`measurecheck` 18. **T13b** (`6e4d69b`, `3054101`) -- pulled forward from M3: the probe dumps a real
heal's, HoT's and damage spell's tooltip lines, reads party1's GUID / name / level / class / role /
max-health predicate, and counts `UNIT_COMBAT` per token with mirrors; `probecheck` 71. Every Forever
TOC at `1.0.0-alpha.4` (`8a1f451`). The in-game half is `docs/TESTING.md` §38 (six sessions: the
re-check, the measurements with overlapping spells and gross-or-effective, the party probe, a talent
that changes a value, Q10 at level 20, the second class). `beta.1` is still gated on §38.1-38.2 and
38.6 passing.

**Planner ruling (2026-09-28) on the order M2 was built in:** the spell readers were written from
retail's documentation before any beta report showed the return *shapes* (`GetSpellInfo.castTime`,
the `GetSpellPowerCost` rows, the skill-line bounds, the tooltip data lines,
`Enum.TooltipDataType.Spell`, `IsSpellKnown`, the book row's `itemType`, and whether
`TooltipDataProcessor` fires in the spellbook, on bars and in chat). Accepted, because the author
asked for M2 in the same session -- on one condition: **the first probe report carrying `== shapes`
(T7a) is a gate for `beta.1`**, checked line by line against `Spells/Book.lua`'s reader by the
lead before §37's result counts.

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
coach and the solver re-measured on Forever recordings. **T13a** (added 2026-09-28 from the M2
review): a static check in `tools/apicheck.py` that no event-handler argument reaches
`type(...) == "number"` or any comparison without `IsSecret` first -- on the client a secret number
answers `type(v) == "number"`, the stub's stand-in is a table, so no suite can catch the omission
(T9 had exactly this gap). It lands before T13, whose recorder is all event handlers. **T13b**, the
probe items M1 left: `ShouldUnitHealthMaxBeSecret("party1")`, `UNIT_COMBAT` counted per token, and
the HEAL amount's gross-or-effective question if §37's full-health Healing Touch has not settled it.

*Landed:* **T13c** (`bdbc40a`) -- a module TOC may list a shared file (`Engine\...`, `Spells\...`,
`Data\...`, `UI\...`) that release copies into the package; `Module.lua` makes the module's files
see SpellTuner's `MD`, `Ready.lua` (last) fires `MODULE_LOADED`; `modulecheck` 14. **T13e** (`007d1d1`) -- the
probe asks whether a status bar hands back a secret it was given (planner ruling 1): three `bar ...`
readings and `UnitHealthMissing(party1)`, out of combat and in the snapshot; `probecheck` 73.
**T13a** (`797ef17`) -- `apicheck.py` rule 8: an `MD:On` handler's argument compared, indexed, measured or
`type()`-tested before `IsSecret` asks about it is a finding; the one it found (`Core_Forever.lua`,
`ADDON_LOADED`) is guarded; `apicheck --selftest` 10 of 10.
**T15** (`9876615`) -- the Replay module carries `Kit_Forever.lua` and `Engine\SimModel.lua`: `MD.RankMath:SpellKit()`
and `MD.SpellData` built from `MD.Book` (Healing Touch, Regrowth, Rejuvenation, Swiftmend eating the
whole HoT, Tranquility excluded; Wild Growth skipped and named); the engine's four spell-name
lookups go through `MD.API.SpellName`; `kitcheck` 7.
**T13** (`6624d58`) -- the Recorder module carries `Recorder_Forever.lua`: every pull a **v3 stream** in
`MD.cdb.recordings` (8 kept) -- `UNIT_COMBAT` WOUND / HEAL per tracked token (HEAL = 15, source
unknown), own casts with SENT target and book cost, cancels decided whatever order STOP and
SUCCEEDED arrive in (UNKNOWN on the client), party max health `-1`, the clock's modelled mana,
deaths, pre-pull HoTs read out of combat, restriction brackets, the damage meter's totals read 1 s
after combat; `/st rec [clear]`; `recordcheck` 14.
**T13d** (`9f2488b`) -- the Replay module carries `Scenario_Forever.lua`: `SM.ScenarioFromRecording` sends a v3
stream to `SM.ScenarioV3` (v2 untouched); `SM.AttributeHeals` (planner ruling 2) splits the
sourceless heals into own and foreign; `SM.EstimateMaxHP` (ruling 1) stands in for a party member's
max, marked estimated; health reconstructed as a deficit on a 2 s grid; pre-pull HoTs placed by the
recorder's new aura `tgt`; `tools/foreverfixture.lua`; `scenariocheck` 9.
**T14** (`6887cdf`) -- `Gates_Forever.lua`: `SM:Validate` sends a v3 stream to `SM:ValidateV3` -- the mana gates
against the modelled pool (said so, ruling 3), health against the reconstruction, foreign share and
calibration from the damage meter, spend coverage by the book, and gate 8 "heals attributed"
(ruling 2; one-sided until `SM.HEAL_AMOUNT` is known to be effective); `gatecheck` 8.
**T16a** -- the Replay module carries the engine, the planner and solver, `ReplayTrace`, `UI/Tooltip.lua`
and `UI/ReplayWindow.lua` (every client call now through the adapter, names escaped at paint time,
the TBC window unchanged) and `Commands_Forever.lua` (`/st replay`, `/st validate`, `/st coach`); a
v3 recording plays with its reconstructed health as the left column's ticks and says it is
reconstructed and estimated; `SM.RecordedHp`; `replayforever` 10. `SP.Card`'s stray global `kit`
(always nil) made an explicit local, TBC output unchanged.

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
