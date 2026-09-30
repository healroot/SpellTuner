# Whole-project review, 2026-09-30

A read-only review of the whole tree (both lines, the three modules, `tools/`, `release.sh`), pinned
to commit `92ff5d2` (0.16.3). Two passes:

- **Bugs.** Finders per area, each finding checked by three skeptics told to refute it. **26
  upheld** by at least two of three (24 by all three). They are `B1..B26` below.
- **Architecture, UI/UX and tests.** Area reviewers (kernel, spells, sim, live, modules, UI kit,
  Forever UI, shared UI, tools) under three lenses (architecture, design/UX, test quality). Their
  reports overlap heavily; this record merges them. `A` = architecture, `U` = UI/UX, `Q` = tests
  and tools. The source reports are cited as `[area lens #n]`.

Every area suite was green at `92ff5d2` when run the way `docs/TOOLS.md` section 1 runs it
(apicheck 0 findings). Three suites are green only under that exact loop (Q3, Q4, Q7).

Numbering is stable: the plan (`PLAN-refactor-ux.md`) and later fix tasks cite `B<n>`, `A<n>`,
`U<n>`, `Q<n>`. Paths are repository-relative.

The screenshot folder named in the review brief did not exist, so the UI findings are judged from
the code, `docs/SPEC-forever-ui.md`, `docs/mockups/forever-ui.html` and Cell's `Widgets.lua`.

---

## Part 1. Confirmed bugs

Severity is the skeptics' (medium / low). Line numbers at `92ff5d2`.

### B1 [medium] `Core.lua:131` -- a login or `/reload` in Cat/Bear form turns the whole mana side off for the session (both lines)

**Fixed in** `fbd1e2d` (T52, P8).

**Scenario.** `/reload` in Cat or Bear form. `UnitPowerType("player")` answers 3 or 1, so
`MD.player.usesMana = false`, and nothing ever re-evaluates it (`DetectProfile` runs only from
`PLAYER_LOGIN`; `Core_TBC`'s `CheckForm` tracks Tree only). For the session: `Engine/TTO.lua:53`
returns no state (`OOM --`), `UI/Widget.lua:153` hides the widget, `UI/Advisor.lua:16,110` is silent,
`Integrations/ElvUIDatatext.lua:73` prints `Regen: --`, `Engine/Targets.lua:56` stops self-assigning
HEALER, `Engine/ManaCooldowns.lua:126` gives nothing.
**Evidence.** The comment at `Core.lua:129-130` assumes login in caster form. `grep usesMana`: seven
readers, one writer.

### B2 [medium] `Core_TBC.lua:123` -- another druid's Tree of Life aura makes the model think YOU are in Tree form

**Fixed in** `fbd1e2d` (T52, P8).

**Scenario.** In caster form in a group with a second resto druid in Tree. `GetShapeshiftFormID()`
answers `nil` in caster form (what the stub models at `tools/wowstub.lua:662`), so `ok and id ~= nil`
fails and the fallback `MD:HasBuff("Tree of Life")` finds the party aura (34123, same name).
`InTreeForm()` is true: `Engine/RankMath.lua:101-103` adds the tree aura and the tree cost/heal
modifiers to every row and the kit, `Engine/FightRecorder.lua:213` records `form="tree"`,
`UI/Summary.lua:143` labels casts tree, `Core_TBC.lua:221` writes it into the profile, and
`FORM_CHANGED` fires every time the other druid shifts or leaves range.
**Evidence.** `Core_TBC.lua:117-126`. The fallback must run only when the function is absent, not when
it answered `nil`. Every offline suite takes the fallback path and none has a second druid.

### B3 [low] `Core_TBC.lua:243, 325, 369`, `Verify.lua:10, 24, 65, 68, 93, 500`, `UI/Advisor.lua:68` -- em and en dashes in chat strings

**Fixed in** `a71cf2a`, `56f85c6` (T47, P3).

**Scenario.** First-run line `first run <U+2014> the widget is unlocked...`, `/md unlock`, `/md window` with a
bad value `(5<U+2013>60 seconds)`, six `/md verify` lines, one `/md fsrtest` line and the Advisor's
gear-change toast (`gear change <U+2014> ...`, added after the first pass) carry U+2014 / U+2013. A
font without the glyph draws a box, and a pasted `/md verify` report carries multibyte bytes.
**Evidence.** `grep -nP "[^\x00-\x7F]"` over the kernel files, comments excluded. The same class: the
kit's own close glyph the U+00D7 multiplication sign at `UI/Style.lua:248` [ux kit #15].

### B4 [medium] `Spells/Parse.lua:300` -- the single-damage catch-all values one tick of a periodic spell as a direct hit

**Fixed in** `40f9557` (T50, P6).

**Scenario.** A periodic clause phrased other than the two recognised shapes falls to `DAMAGE_SINGLE`,
which takes any `N School damage` anywhere. Hellfire (`... 83 Fire damage to all nearby enemies every 1
sec. Lasts 15 sec.`) reads `{min=83,max=83}`, Volley `{50,50}` (wordings from memory, UNVERIFIED on
Forever); Penance from the project's own fixture reads as damage 81 with the 184 heal dropped, so a
heal is filed as a damage family. Book, per mana, per second and Tabs' damage seed follow. Druid texts
are unaffected (Hurricane matches the enemies-every shape); any other class on Forever is.
**Evidence.** Run under the forever harness in a scratch copy. `NotCastDamage` (176-183) refuses
wards and reactive clauses only; the file's contract is "refuse rather than guess". Penance is
`loose = true` in `tools/data/parse-fixture.lua:103`, which is why `parsecheck` passes.

### B5 [medium] `Engine/SimModel.lua:537` -- a HoT eaten by Swiftmend is never traced as ended

**Fixed in** `cb94d8e` (T46, P2).

**Scenario.** Regrowth at 1 s, Swiftmend at 4 s. `LandCast` sets `rg.active = false` with no
`Trace(TK.HOT_END)`, and the later expiry pop sees an inactive slot and emits nothing.
`ReplayTrace`'s `HotEnd` falls to the nominal expiry, so the replay (both columns) and the practice
window keep drawing a Regrowth for 17 s, and the Swiftmend-ready dot (`UI/ReplayWindow.lua:737-749`)
says there is something to eat.
**Evidence.** Reproduced: no `HOT_END` at 4 s; `RT.New(trace, sc):Seek(6):Hot(1, Regrowth)` and at
12 s both live while the engine's `r.ticks` is 0. No suite asserts it.

### B6 [medium] `Engine/SimPlanner.lua:1577` (and `:1961`) -- the search's cache key omits `noDirect`, so the HoTs-only seed is never evaluated

**Fixed in** `cb94d8e` (T46, P2).

**Scenario.** `Key(p)` formats five parameters and not `noDirect`. Seed 2 (`noDirect = true`, line
1616) collides with seed 1 and returns its cached entry; every descended trial copying `noDirect`
collides too. `SP.Search` never runs a `noDirect` plan, so the card's "best (search)" can never be
HoTs-only even when the Coach's own "HoTs only" baseline row beats everything. `SP.SearchRun`
repeats it (1961, 1983). Seeds 1 and 3 (1615, 1618) are byte-identical: the search starts from two
points, not four.
**Evidence.** Instrumented `SP.NewPlan` in a scratch copy: `evals 24, plans built 24, noDirect plans
built 0`.

### B7 [low] `Engine/SimModel.lua:864` -- after a fixed cast preempts a long cast, the plan is not asked again until the cancelled cast's landing time

**Fixed in** `cb94d8e`, `3ddd972` (T46, P2).

**Scenario.** Healing Touch (2.9 s) started at 0; a recorded Moonfire at 0.5 s preempts it
(`busyUntil = 2.0`). The pending `E_DECIDE` sits at 2.925, never hits the busy guard the comment
relies on, and the plan idles from 2.0 to 2.925 with no WAIT event and no `waitTime`. The suggested
column drifts late and the plan's score is charged for idle it never chose.
**Evidence.** Reproduced: Decide asked at 0.00, 2.92, 5.85 (never 2.0); `waitFraction 0`.

### B8 [low] `Engine/SimSolver.lua:356` -- the solver values Swiftmend as eating Rejuvenation first; the engine eats Regrowth first

**Fixed in** `cb94d8e` (T46, P2).

**Scenario.** Both HoTs rolling: `Solver:Best` (356-359, 371) prices Swiftmend against Rejuvenation's
deposits; `LandCast` (537-543) consumes Regrowth (TBC's rule, `RankMath.lua:425-427`). The pick is
scored against the wrong counterfactual. It also writes `swiftmendAmount` onto the shared kit entry,
which `SM.KitSnapshot` copies into practice recordings' `rec.kit`.

### B9 [medium] `Engine/FightRecorder.lua:327` -- any own combat-log event during a hard cast is recorded as a CANCEL

**Fixed in** `61175d8` (T48, P4).

**Scenario.** Lifebloom rolling, a 3 s Healing Touch started: the next own `SPELL_PERIODIC_HEAL` (or
aura applied/removed, Omen of Clarity energize, a `SPELL_CAST_FAILED` from a button pressed mid-cast)
is `isOwn`, not the matching success and not `SPELL_CAST_START`, so `K.CANCEL` is pushed and the
pending cast cleared; the real success then arrives unpaired. Nearly every hard cast under a rolling
HoT is recorded cancelled; the replay's ACTUAL cast bar is cut ~1 s in and a success flash appears
from nowhere. Mirror case: a real cancel followed at once by a different `SPELL_CAST_START` produces no
CANCEL.
**Evidence.** Lines 324-333; `UI/Summary.lua:206` forwards every subevent. `tools/fakepull.lua:74-75`
has nothing between cast start and success; reccheck counts no CANCEL.

### B10 [medium] `UI/Summary.lua:233` -- Lifebloom's bloom (33778) is classified "direct"

**Fixed in** `61175d8` (T48, P4).

**Scenario.** 33778 is an alias (`Data/SpellData.lua:244-248`), not a row, so
`SpellData.spells[33778]` is nil and the kind stays `direct`: (1) calibration never sees the bloom
(`Calibration:Observe` -> `Prediction(33778)` -> `RowFor` nil -> return before any bucket); (2)
Overheal stores `k:33778:direct`, so `RankMath.lua:356`'s kind-scoped bloom fraction never exists and
the Effective Lifebloom row never uses measured bloom overheal; (3) `Overheal.Attribute` skips the
`bloom -> 0` rule and charges the whole Lifebloom cost to "wasted mana" for a fully overhealed bloom,
on top of the ticks that already carry it.
**Evidence.** No `SD:Resolve` at Summary 233; no fixture fires 33778.

### B11 [low] `Engine/RunRecorder.lua:561` (and `Engine/TTO.lua:443`) -- bare pipes in rendered text

**Fixed in** `a71cf2a` (T47, P3: `Engine/TTO.lua`), `61175d8` (T48, P4: `Engine/RunRecorder.lua`).

`MD:Print("usage: /md run start [name] | stop | status")`; TTO's debug line is rendered by the
console's `SetText`. The rule is "never a bare pipe" (`UI/Summary.lua:489` doubles it for this reason).

### B12 [low] `Engine/RunRecorder.lua:217` -- `RR:Start` does not reset `potionCount` and `pullStart`

**Fixed in** `61175d8` (T48, P4).

(a) A potion drunk, banked or sold between runs: run 2's first sample compares with run 1's count and
pushes a false `K.POTION` at t~0, which `ComputeStats` counts. (b) Run 1's last pull started but
ended after the stop, or was skipped for budget (`PullSkipped` never clears `pullStart`): run 2
started mid-pull uses run 1's stale offset as `runT0` (line 406). `runcheck` never runs two runs.

### B13 [low] `Engine/Overheal.lua:96` -- Tranquility waste divided by the whole raid

**Fixed in** `61175d8` (T48, P4).

Waste per tick is `cost / (4 * group)` with `group` = every non-pet in `Targets.byGUID`: 25 in a raid,
while Tranquility heals the caster's party. A 5x understatement in the Waste view and the fight
summary's "into full health" clause; right in a 5-man.

### B14 [medium] `Modules/SpellTuner_Recorder/Recorder_Forever.lua:782` -- a finished pull is silently lost once every stored stream is pinned (Forever)

**Fixed in** `2806606` (T49, P5).

`UI/Dashboard_Review.lua:271` toggles `rec.pinned` directly (the capped `MD.FightRecorder:Pin` at
Recorder_Forever 723 is never called; the tooltip says "at most two", nothing enforces it). After eight
pins `StoreOrDrop` finds no victim and returns with no chat or debug line. TBC's `FightRecorder`
honours only the first `MAX_PINNED` and always stores.

### B15 [medium, 2 of 3] `Modules/SpellTuner_Recorder/Recorder_Forever.lua:143` -- a cross-realm party member's heals all become foreign

**Fixed in** `2806606`, `865acde` (T49, P5).

`UNIT_SPELLCAST_SENT`'s target carries `Name-Realm` on the retail engine; the roster stores
`UnitName`'s first return (`Name`); `ResolveTargetIndex` compares exactly and returns -1.
`Scenario_Forever.lua:122` drops `tgt <= 0`, so gate 8 fails, the meter shortfall trips, the replay
casts at target -1 and the coach thinks the tank was never healed. The probe only saw same-realm
names (`docs/probe/1.60.1_70009.md:834-835`): the suffix case follows the retail convention,
unverified.

### B16 [low] `Modules/SpellTuner_Replay/Commands_Forever.lua:433` -- `/st coach` with an argument the pattern rejects silently coaches recording 1

**Fixed in** `2806606` (T49, P5).

`arg:match("^([pP]?%d*)%s*(%a*)$")` is nil for `2:7`, `1 force now` and similar; `n` becomes `"1"` and
a card for a different fight is printed. `/st validate 2:7` answers "no recording" correctly.

### B17 [medium] `UI/Windows_Forever.lua:344` -- `Win:SetScale` converts saved positions only for windows registered this session

**Fixed in** `18ce073` (T51, P7).

Scale changed to 80 % before the replay (or console) was built this session: `db.ui.win.replay` keeps
1.0-scale units; the next `/st replay` places it 20 % toward the bottom-left and persists the wrong
numbers. The file's own contract (12-14) says a change converts every saved position. The old
`u.scale` is overwritten (343) before anything could convert the unregistered entries.

### B18 [low] `UI/Windows_Forever.lua:297` -- pixel-snapped edges computed before `Register` applies the scale, never restyled

**Fixed in** `18ce073` (T51, P7).

`UI.CreateNavFrame` styles the frame, title bar and nav column at UIParent's scale; `Register` then
`SetScale(0.8)`: those borders draw at 0.8 physical px (1.2 at 120 %), thin or doubled, while panes
built later are crisp. Only `UI_SCALE_CHANGED`, `DISPLAY_SIZE_CHANGED` or a later `Win:SetScale`
restyle. Same path for the console and the replay window.

### B19 [low, 2 of 3] `UI/Clock_Forever.lua:259` -- an opener cast before the combat flag is spent but not counted in the fight

**Fixed in** `40f9557` (T50, P6).

The opener's `UNIT_SPELLCAST_SUCCEEDED` arrives before `PLAYER_REGEN_DISABLED` (review R8's window);
`Spend` with no fight drops the pool, then `StartFight` resets `spent`, `casts` and `unpriced`
(`Engine/ManaModel.lua:116-120`). The pool is right, the spend rate under it is not; the warm-up
lasts one cast longer; an unpriced opener vanishes from the hover.

### B20 [low, 2 of 3] `UI/SpellsPane_Forever.lua:178` -- Export's character line is not escaped

**Fixed in** `40f9557` (T50, P6).

`"character: " .. Str(name) .. " " .. Str(realm) ...` straight from the adapter, while every other
client string in the export goes through `Esc`. A name like `Zoe` with a diaeresis puts raw non-ASCII
bytes in the one format `tools/refcheck.py` and the probe share. `spellsui`'s ASCII assertion runs
with an ASCII stub name.

### B21 [medium] `UI/ReplayWindow.lua:1797` -- run-mode scrubber collapses to one pull's range at the first pull boundary (TBC)

**Fixed in** `18ce073` (T51, P7).

`/md replay run 2`: `OpenRunPlay` sets the scrubber to the run (1817) once; crossing into pull 2
re-enters `MD:OpenReplay`, which sets `(0, pull dur)` unconditionally. `SetValue(runT)` clamps, the
thumb sticks right, and a drag passes a pull-range value to `RunSeek` -- the run jumps back to its
opening seconds. Same on a run-strip click (1435) and `RebuildSuggested` (1633). The stub's
`SetValue` never clamps; `replayui` drives `_runSeek`, not the slider.

### B22 [medium] `UI/ReplayWindow.lua:1095` -- run-mode `OnUpdate` retries a refused `OpenReplay` every frame, flooding chat in combat (TBC)

**Fixed in** `18ce073` (T51, P7).

A run playing, combat starts (nothing hides the replay on TBC); at the next pull boundary
`OpenReplay` refuses and prints "not in combat - it is a review tool", `pullIdx` is unchanged, and the
next frame does it again: ~60 lines a second. A scrubber drag in combat prints per event. Forever
hides the window in combat, so only TBC is exposed.

### B23 [low] `UI/ReplayWindow.lua:457` -- practice: hovering the Swiftmend, defensive or incoming-cast icon drops the key target

**Fixed in** `18ce073` (T51, P7).

The unit frame's `OnLeave` fires when the pointer moves onto a mouse-enabled child (`Icon()` enables
the mouse, 339); these three icons hook only `OnMouseDown`, so `hoverTi` stays nil and a bound key
reports "No target". Conversely no icon hooks `OnLeave`, so leaving outward from an icon keeps
`hoverTi` and a key can heal a unit the pointer no longer covers.

### B24 [low] `UI/Dashboard_Review.lua:431` -- the selected row's validate cell and hover are drawn before its validation runs

**Fixed in** `2806606` (T49, P5).

`Render` paints rows from `cache[rec.id]` (431), then runs `Validation(rec)` (495). A newly selected row
reads "not checked" with a hover saying "press Validate" while the buttons on the same paint already
say `Coach*`. TBC heals it on the next 2 s tick; Forever only on the next click.

### B25 [medium] `tools/import.lua:564` -- TBC `export N` writes the header only

**Fixed in** `40f9557` (T50, P6).

`line:match("^# recording %d")` has no capture, so it returns the whole text and the comparison with
`tostring(n)` always fails; every recording flips the phase to `other`. The tool reports
`wrote ... (18 of 136 lines: the header plus recording 1)` and the file has no recording section.
Reproduced with two fakepull recordings. `importcheck` exercises only the Forever export.

### B26 [medium] `tools/refcheck.py:148` -- the probe's `\ddd` escapes are counted as description numbers

**Fixed in** `40f9557` (T50, P6).

`Esc` writes a non-ASCII byte as `\226`...; `numbers_in` runs on the still-escaped text (only `||`
is undone, line 59), so a curly quote adds 226, 128, 156... Reproduced with the bundled fixture:
`desc numbers: client 7, reference 1` for agreeing texts. `\\` is not undone either.

---

## Part 2. Architecture (merged)

### A1. The command layer exists three times, and four commands are implemented twice [arch kernel #1, live #8, modules #7, shared-ui #2]

**Where.** `Core.lua:307-367` has a registry (`MD:AddCommand`, `ShowCommands`) that only Forever
uses. TBC bypasses it: `Core_TBC.lua:226-404` keeps `MD.COMMANDS` (28 rows, read by
`UI/Options_About.lua:35`) and a 100-line `MD.SlashFallback` if-chain. Implemented twice and already
drifted: `coach` / `MD:RunCoach` (`Verify.lua:1374-1429` vs `Modules/SpellTuner_Replay/Commands_Forever.lua:153-203`:
different argument patterns -- B16 --, escaping, copy box, energize line), `MD:ValidationReport`
(`Verify.lua:1299-1330` vs `Commands_Forever.lua:56-131`, three names for one function there),
`practice`, `MD:GetRecording` (`Engine/FightRecorder.lua:640-655` vs `Recorder_Forever.lua:744-752`).
**Why.** A fix to coach lands on one line; nothing asserts `MD.COMMANDS` matches the if-chain, so help
can lie; the shared Review pane's buttons mean different things per line.
**Change.** Every TBC verb registered through `MD:AddCommand` in the file that owns the feature;
`SlashFallback` and `MD.COMMANDS` deleted; `MD:Commands()` for Options_About. One shared commands file
for coach / validate / replay / the strategy hint / the report, listed on the TBC TOC and the Replay
module TOC, printing through one escape rule.

### A2. `Verify.lua` (1429 lines) is five concerns, and one of them writes a model input [kernel #4, live #6]

**Where.** Diagnostics (`RunVerify`, `Snapshot`, `Profile`), export (`DumpRecording`/`Export`),
instruments (`fsrtest`, `regentest` -- the sole writer of `cdb.mp5`, read by `RM:Unreported()` --,
`spamtest`), the engine's shipped self-tests (`RunSimRun`, `RunSimReplay`) and the coach commands.
The "leftover <= what the API reports" bound lives in `Verify:StoreMeasuredMp5` and again in
`RegenModel:MeasuredMp5`.
**Why.** "What writes the measured mp5" is not findable; the coach command could not be shared
because it sat among TBC-only raw calls.
**Change.** Pure moves: `Diagnostics_TBC.lua` (verify, snapshot, profile, export), `Engine/RegenMeasure.lua`
(fsrtest, regentest, spamtest, the `cdb.mp5` shape and bound, one owner), `Engine/SimSelfTest.lua`,
and the coach commands into A1's shared file.

### A3. Settings defaults live in three or four places; a LoadOnDemand module cannot declare its own [kernel #2, modules #6, sim #3e]

**Where.** `Core_TBC.lua:13-89` `DEFAULTS`; `Commands_Forever.lua:13-26` `REPLAY_DEFAULTS` (a copy,
applied after `InitDB` because the module loads late); `SM.GATES[...].default`
(`Engine/SimModel.lua:1409`); inline `MD.db.simFullHp or 0.85`, `simFloor or 0.30`, `replaySpeed or
1` in `UI/Options_General.lua:289-290`, `UI/ReplayWindow.lua:1367,1693` and the engine; two gate
defaults exist only in `Gates_Forever`. `Core_Forever.lua` DEFAULTS lacks keys shared files read.
**Why.** A re-measured threshold lands in one list; the pane, the gate text and the engine can each
show a different number.
**Change.** `MD:RegisterDefaults(tbl)` in `Core.lua`: merges into `MD.DEFAULTS` before login, back-fills
`MD.db` if `InitDB` already ran. Feature files declare their keys; `SM.GATES` reads defaults from it;
inline literals go.

### A4. Event and callback dispatch have no fault isolation [kernel #3]

**Where.** `Core.lua:40-43` (`MD:On`) and `53-57` (`MD:Fire`) call handlers in a bare loop.
`PLAYER_REGEN_ENABLED` has 8 handlers, `PLAYER_REGEN_DISABLED` 7, `UNIT_SPELLCAST_SUCCEEDED` 6.
**Why.** One raise in an early handler stops the recorder closing its stream, the clock re-anchoring
and the run recorder seeing the pull: one bug, four symptoms, and on the beta things raise.
**Change.** Per-handler `xpcall` with the installed error handler as the sink (the error still reaches
BugGrabber once), in both loops. A TBC behaviour change in the failure case only (one DECISIONS line).

### A5. Shared panes discover the recordings provider by sniffing `MD.*`; one address grammar exists twice [kernel #5, live #8, modules #3b]

**Where.** 13 guards in `UI/Dashboard_Review.lua`, 10 in `UI/ReplayWindow.lua`, 7 each in `SimPlanner`
and `SimModel`; Forever fills gaps by conditional patching (`Recorder_Forever.lua:707-752`:
`if MD.FightRecorder.Pin == nil`, `if MD.GetRecording == nil`). The address parser (`"3"`, `"2:7"`,
`"p2"`) exists twice and disagrees; the ring policy exists twice with different victims (TBC:
cheapest not recent; Forever: oldest unpinned) and the Forever pin cap is bypassed (B14).
**Change.** One `Engine/Recordings.lua` on both lines: `Register(prefix, provider)`, `Get(spec)`,
`List`, `Pin` (capped), with each recorder registering its prefix. Features as `MD.features.<name>`
flags rather than method-presence checks, later.

### A6. Flavour branches in shared code [kernel #6, kit #6, shared-ui #3]

**Where.** `MD.API.client == "forever"` in `Engine/Practice.lua` (`OnForever()` 149, used 7 times),
`UI/BindingsWindow.lua:287,299`, `UI/PracticePanel.lua:427`; `if MD.Win ... else UISpecialFrames` and
`UI.TEXT and ... or "|cffffcc00"` at 31 sites across PracticePanel, BindingsWindow, DebugConsole,
ReplayWindow, Review, Rows. PracticePanel's `CreatePractice` is two layouts in one function.
**Why.** CLAUDE.md: a flavour difference is a seam, not a branch in shared code; every new shared
control needs the same two conditionals; a missed guard is a TBC nil index no TBC suite sees.
**Change.** (a) A practice policy the flavour installs (`defaultBinds`, `kitIsLive`) read by the three
files; apicheck forbids `MD.API.client` outside `Client/` and the dump. (b) Tokens always present (A20)
remove the `UI.TEXT and` gates. (c) A generic window manager with a TBC shim removes the `if MD.Win`
branches -- only with the TBC opt-in (U4).

### A7. `Client/API_Forever.lua` carries the macro-tooltip feature and its diagnostics [kernel #7]

Lines 166-452 (~280 of 452): hover record written onto `GameTooltip`, the `/st tooltip why` text, the
`SetAction` hook; five manual `_bindings.X =` writes bypass `Bind`. The adapter's contract ("plain
values or nil plus a reason") now owns UI-facing English. **Change:** primitives in the adapter, the
chain and the why-text in `UI/SpellTip_Forever.lua` (or a `MacroTip_Forever.lua`), a
`MD.API.Register`. **Only after** the author's `macro` probe lines come back (the shapes are
unverified).

### A8. `Client/Probe.lua` (2231 lines) is a second addon, and now names the window manager [kernel #8]

Own event frame, helpers, `ADDON_LOADED` handler on `SpellTunerDB` ordered against the guard by frame
creation order, own slash fallback, and since T33 calls `MD.Win`. **Change:** split by its `==`
sections into `Client/Probe/`; `MD.Probe.AddSection(name, fn)` so the window manager registers its ESC
line; keep its private frame. Not urgent.

### A9. One escaping rule and a handful of formatters copied 9-11 times [kernel #10, live #5, modules #2, forever-ui #9, shared-ui #8, spells #9]

**Where.** `Esc` in Probe, Dump_Forever, Recorder_Forever, Commands_Forever (+`EscKeepColours`),
SpellsPane_Forever, Dashboard_Review, ReplayWindow, Practice, Measure -- **two different meanings**
(pipe-doubling vs the probe's full reversible ASCII escape). `Median` three times (PullBudget's sorts
the caller's table in place; SpendTracker's is a different median for even n); `K` (1000 vs 10000
thresholds), mm:ss clocks (`%d:%02d` vs `%d:%04.1f`), drink detection four ways, the record gate
(20 s / 5 casts) in two recorders, `GCD = 1.5` / `CRIT_MULT = 1.5` in six files, `ModuleStateText` twice.
**Why.** A project rule (ASCII, never a bare pipe) is enforced by copies and discipline.
**Change.** `MD.Text = { Esc (pipe-doubling), EscASCII (reversible, the probe's), EscKeepColours }`
and `MD:PrintSafe(line)` in `Core.lua`; `MD.Util` (`Median` copying, `Clock`, `K`, `RECORD_GATE`) and
`MD.Rules` (`GCD`, `CRIT_MULT`, `SUGGESTED_FLOOR`) beside it. The probe may keep its own.

### A10. Layout rules coded three or four times; twin TOCs unchecked [kernel #11, #12, modules #10, tools #4]

The "a module TOC entry under `Engine/ Spells/ Data/ UI/` resolves at the root" rule in `release.sh:362`,
`tools/wowstub.lua:1260`, `tools/apicheck.py`; the interface bands in `release.sh`, `apicheck.py`,
`releasecheck.lua`, `Client/API.lua`; `SM.K` re-typed in `tools/wclconvert.py`. `SpellTuner.toc` vs
`SpellTuner_Mainline.toc` differ by one line and each module has an identical pair plus byte-identical
`Module.lua`/`Ready.lua` x3; nothing asserts identity. **Change:** assert identity in
releasecheck/modulecheck (cheap); a shared layout file read by the three tools (later).

### A11. `MD.SpellData` is the engine's ambient spell index with two producers [spells #1, modules #5]

On TBC the static table; on Forever an empty shell that `Kit_Forever.SpellKit` (and `KitRestore`)
overwrite as a side effect of every call (10 call sites), also writing `cdb.kit` each time. ~130
reads across the engine and UI; `PR.EnsureKit` exists only because the index is nil on Forever until
the first build; "is this cast a heal" means "was in the book when the kit was last built".
**Change (long).** Carry the index on the kit and make the engine read the kit. **Now:** make
`SpellKit` idempotent per book generation and write `cdb.kit` only when the kit changed.

### A12. The kit shape has no owner; the druid is hard-wired in six places [spells #2, sim #4]

Three producers (`RankMath:SpellKit`, `Kit_Forever.SpellKit` + `KitRestore`, `SM.KitSnapshot`), schema
in a comment (`RankMath.lua:411-417`); `castBase` had to be remembered in both builders. `HOT_INDEX`
twice, the `e.type` strings and "Swiftmend eats Regrowth then Rejuvenation" re-encoded in SimModel,
SimSolver (B8 is this drift), Practice, Scenario_Forever, Kit_Forever and ReplayWindow; three family
lists. **Change:** `Engine/Kit.lua`: `Kit.FIELDS`, `Kit.Validate`, `Kit.Snapshot`/`Restore`; both
builders end with `Validate`; `e.consumes` on Swiftmend and one `SM.SWIFTMEND_ORDER` read by engine and
solver. Data-driven slots for other classes later.

### A13. The rank rules exist three times; the words four times [spells #3, #9, forever-ui #2, #6]

Pareto dominance and the suggested rank in `RankMath:Compute` 578-608 (literal `0.4`) and `Book:Rows`
568-618 (`SUGGESTED_FLOOR = 0.4`); casts-to-OOM twice; `UI/SpellTip_Forever.lua:185-214` `Dominator`
re-implements what `Book` already writes as `entry.dominatedBy`. The spell "words" (cost, cast,
per-second, crit range, casts) are computed separately in SpellTip and SpellsPane with different
strings for the same fact (`no mana (10 Rage)` / `10 Rage`; `inf` / `never - regen keeps up`); `CRIT_MULT`
(unverified) in two UI files. `SpellTip.lastOutcome` is a second return smuggled through a field, which
the rank-row hover overwrites (`/st tooltip why` then lies).
**Change.** `Spells/RankRules.lua` (pure, both TOCs) for Pareto/Suggested/CastsToOOM; SpellTip reads
`dominatedBy`; `Spells/Words.lua` (Forever) with a `style` argument where the spec wants different
wording; `Lines` returns `lines, outcome`.

### A14. `Engine/RankMath.lua` / `DamageMath.lua` reach the client and `Core_TBC` directly; `RankMath.info` is hidden state [spells #4]

Raw `GetSpellBonusHealing`, `UnitStat`, `MD:TalentRank`, `MD:InTreeForm`; `RankMath.info` is "the
context of the last Compute" read by four UI files (a tooltip can show the Simulate strip's relic).
**Change (later):** inputs through `MD.API` plus a character provider; `Compute` returns `ctx`. This
is what would let the formulas serve `Book.adjust` on Forever (Q6 of the probe).

### A15. `Spells/Book.lua`: two read paths, a cache that does I/O on read, pull-driven refresh [spells #5, forever-ui #8]

`BuildEntry` / `ReadSpell` are a 50-line copy, and R41 (stale carry-through) was applied to one only:
a spell outside the book goes blank in combat. `Book:Get()` rescans synchronously in whichever caller
asks first (a tooltip hover, the recorder's per-cast cost); `BOOK_CHANGED` fires only inside a scan,
and the two SpellsPane ticks call `Get()` to make it fire -- a model update gated on a UI being open.
Entries are new tables each scan. **Change:** one `ReadCommon`; `Book` owns a throttled scan tick;
`Get()` is cache-only; entries updated in place.

### A16. Family identity has three spellings [spells #6]; two text parsers [spells #7]; `Data/` holds code, a fixture and two `ClassifyCast`s [spells #8, live #10, modules #9]

Family keys `"Healing Touch"` / `"HealingTouch"` / `FAMILY_KEY` maps in two files. `DM.Parse` (TBC) has
no refusal rules. `Data/DruidSpells.lua` defines `MD:ClassifyCast` and writes SavedVariables;
`Scenario_Forever.lua:757` defines a second one under `if == nil` with a different return convention;
`Data/SimFixture_BF1.lua` ships. The `== nil` "only if no flavour defined it" guards always pass on
Forever and would hide a load-order mistake. **Change now:** `MD:Provide(name, fn)` raising on a second
provider, replacing the `== nil` seams. The rest waits for a second class.

### A17. `Engine/SimPlanner.lua` (2240 lines) is five modules; the coach's state is global; plan parameters have four schemas [sim #1]

Plan rules, scoring, classifier, card text (engine emitting chat markup, which Forever re-parses with
`EscKeepColours`), and orchestration with two near-identical frame-sliced searches. `SP.plans`,
`SP.forced`, `SP.strategyPick`, `MD.coachSearch` are indexed from ReplayWindow (11 sites), Verify (9),
Commands_Forever (9). Plan parameters: `NewPlan` defaults, `Params()`, `SP.DOMAINS`/`PARAM_ORDER` and
`Key(p)` -- B6 is the drift. The result snapshot (because `SM:Run` aliases a pool slot) exists five
times. **Change now:** one `SP.PARAMS` table deriving defaults, `Params`, `Key` and domains; one
`SM.Snapshot(r)`; `SP.CardLines(...)` returning structured lines that `SP.Card` joins into today's
exact chat text. The full split later.

### A18. The v2/v3 pipeline is wired by monkey-patching, and one signature is already broken [sim #2, modules #1, #2, #4, #8]

**Where.** `Scenario_Forever.lua:741-745` and `Gates_Forever.lua:318-322` replace
`SM.ScenarioFromRecording` / `SM.Validate` with wrappers dispatching on `rec.v == 3`. The Scenario
wrapper is `(rec, kit)` and **drops the third `others` argument** T20b added: on Forever with Replay
loaded, a curated leave-one-out store is ignored on both roads (demonstrated by the modules reviewer:
`dangerPrior` nil with the store passed, 0.473 through `cdb`; not skeptic-checked, but a run, not a
reading). Gates 1, 2, 4, 7 and `Threshold`/`MeanMax` are copied (~120 lines); `ReconstructHp`'s grid
loop is duplicated inside `ScenarioV3` (681-710 vs 501-531); `AttributeHeals` runs twice per
validation (scenario and gate 8). The v3 kind `HEAL = 15` and `FAMILY_KEY` are hand-copied in four or
five module files; nothing asserts `HEAL` never collides with `SM.K`. SimPlanner and ReplayWindow test
`rec.v == 3` by name.
**Change.** A registry in SimModel (`SM.scenarioBuilders[v]`, `SM.validators[v]`, forwarding `...`,
unknown version raises); export `SM.Threshold`/`SM.MeanMax`; one `ReconstructHp`; the attribution set
on the scenario for gate 8; `Stream_Forever.lua` in the Recorder module publishing the v3 kinds and the
family keys, with a collision assertion in the Replay module.

### A19. `SM:Run` is an 860-line closure that reads `MD.db` and `MD.SpellData` [sim #3, live #9]

~30 upvalues; scheduler, heal model, regen, score, trace, samplers, pacing in one body; reads settings
and the spell index inside a function called "pure"; `ScenarioFromRecording` reads `MD.Regen:Unreported()`
and `MD.cdb.recordings`. **Change (not now):** mechanical extraction behind the same signature, after
A17/A18, with simcheck/replaycheck/restcheck/solvercheck/reproduce as the oracle. Zero-allocation and
tie-break order are load-bearing: high risk for the gain today.

### A20. The theme is a half-seam [kit #1, #3; shared-ui #3a]

`UI.PALETTE` / `UI.TEXT` reach the newer widgets but not the primitives written first: 17 literal
`0.115`s and ~27 other colours in `CreateButton`, `CreateCheckButton`, `CreateEditBox`, `CreateSlider`,
`CreateScrollFrame`, `CreateMovableFrame`'s header; `BUTTON_COLORS` frozen at load; `P.close` unread.
Nine private copies of "read `UI.TEXT` if there, else a literal" (`Hex`, `Tok`, `TextHex`, `FillColor`,
`Hi`, `GOLD`...) with disagreeing literals (`muted` is 0.48 in Style, `888888` in Rows/Practice,
`8a8a8a` for "dominated"; `disabled` 0.3 vs `555555`).
**Change.** `Style.lua` always defines `UI.PALETTE`/`UI.TEXT` with today's TBC values; the theme
overwrites; `UI.Hex/RGB/Fill(token)` replace the nine copies; primitives read tokens. Where the TBC
files disagree today, one literal per token is a documented choice.

### A21. Four tooltip line formats, three tooltip frames; placement lives in a pane; `UI/Tooltip.lua` is on the wrong TOC [kit #2, #8]

`MD.Tip` `{l, r, c, rc}` into `GameTooltip`; `UI.SetTooltips` varargs into the private flat tooltip
(line 1 default colour, lines 2+ forced white, anchor frozen at first call); `SpellTip:Render` positional
arrays; SpellsPane's `KitTip`/`GameTip`/`Place` with the only screen-edge flip; Clock_Forever's raw
`AddLine`. `UI/Tooltip.lua` is listed by the Replay module's TOC, not the Forever main TOC, and most of
it is TBC content (`Tip:Mana` dereferences `MD.Regen` unguarded).
**Change.** One line model (token names) and one renderer with `Show(owner, lines, {anchor, flip})`
in `UI/Tip.lua` on both main TOCs; the RankMath-bound builders to `UI/Tip_TBC.lua`; `SetTooltips` as
sugar over it; SpellTip emits the shared shape (accepting both during migration).

### A22. `UI/Windows_Forever.lua` knows the dashboard's groups and practice rule [kit #4]

`Win.SIZES` keyed by the dashboard's groups, `Win.DEFAULT_GROUP`, `Win.PRACTICE_PATH`,
`PRACTICE_REFUSED`, the key `"main"` special-cased four times; calls `MD:SelectedView`/`OpenMainWindow`
defined later in `Dashboard_Forever.lua`, which calls back. Four concerns in one file (placement/scale,
takeover, ESC stack, combat). **Change:** the dashboard hands its knowledge in at `Register`; the ESC
stack becomes `UI/EscStack.lua`. Prerequisite for listing the manager on TBC.

### A23. `UI/Dashboard_Rows.CreateTable` is two tables in one closure [kit #5, forever-ui #10, shared-ui #10]

`opts == nil` is the TBC rank table (its own `Render`), `opts.render` the generic one; 46 `opts`
branches. Every Forever table feature is a diff in a TBC-loaded file. **Change:** express the TBC table
as an `opts` set (dashui's byte-for-byte assertions verify) and delete the second `Render` -- with the
TBC opt-in, since that is when TBC would use the options.

### A24. Two dashboards hand-copied; TBC's `Refresh` drives unrelated panes [kit #7, shared-ui #4]

`UI/Dashboard.lua` and `UI/Dashboard_Forever.lua` each define `Groups`, the path restore, `SelectView`,
`SelectedView`, `ToggleDashboard`. TBC's `Refresh()` (39-170) mixes the stats line (built by `gsub`
surgery), per-view callouts and the Review render, every 2 s. The Forever host swaps placeholders by
reaching into `nav.panes`/`nav.group` (kit internals), twice, copy-pasted [forever-ui #4].
**Change now:** `nav:ReplacePane(group, view, pane)` and one `MODULE_VIEWS` table in Dashboard_Forever.
A shared host: later.

### A25. `UI/ReplayWindow.lua` (2027 lines) is three windows and a coach orchestrator [sim #5, shared-ui #1]

Replay, run mode and practice mode over ~19 module-scope state locals; `MD:CoachOnOpen` and the
strategy chooser (which builds a scenario and a plan) live in the "only paints" file; `MD:OpenReplay`
is re-entered from `OnUpdate` at every pull boundary (the root of B21 and B22); test seams hand out raw
closure locals (`MD.Replay._state`). **Change:** a `Session` object and an `Inspect()` for tests first
(Q11), then split painter/run/practice. Not now beyond the bug fixes.

### A26. `UI/SpellsPane_Forever.lua` (2215 lines) is four modules; `liveFull` is a hidden argument [forever-ui #1, kit #11]

Rail+picker, one family's view (~950 lines), Overview, wiring; two ticks, two signatures, two per-pitch
caches; `SpellsPane.liveFull` set before `UpdateCells()` and cleared after, because `UpdateCells` takes
no argument; `preview` written in 14 places; the export writer belongs beside `Book`. **Change:** after
A13 (words) and A29 (pool) thin it, split along its section headers with `UpdateCells(ctx)`.

### A27. `UI/Summary.lua` is the TBC combat-log hub, fight lifecycle and cast/roster recorder [live #1, kernel #9]

The one `CLEU` unpack and dispatch, the fight state that starts/finishes `FightRecorder`, `MD.Recorder`
(the roster index every stream is keyed on), `fightHistory`, the labels -- and the chat line. The
engine (`FightRecorder`, loaded earlier) depends on a UI file; the TBC harness must load this one UI
file. **Change (later):** `Engine/CombatLog.lua`, `Engine/CastRing.lua`, `Engine/FightSummary.lua`,
`UI/Summary.lua` renders. reccheck/replaycheck cover the path.

### A28. "In combat" is decided two ways and the stub lies about one, so the TTO's in-combat path has no offline test [live #4]

Event-driven flags in six files, polled `UnitAffectingCombat` in five; the TBC stub hard-codes
`UnitAffectingCombat() == false`; `regencheck` drives a whole fight while TTO believes it is out of
combat; `replayui` patches the adapter. The warmup -> oom machine, the confidence latch, the bound and
the rest segment -- the most log-debugged code in the project -- are verified only in-game. TBC has the
same mid-fight-reload hole Forever fixed (R36).
**Change.** `MD.inCombat` owned by `Core.lua` (the two events, seeded at `MD_READY` through the
adapter); pollers read it; the stub stops lying; a new `tools/ttocheck.lua`.

### A29. Two clocks share one spec written as line-number citations; the mana model is owned by a widget [live #2, forever-ui #3, modules #3a, shared-ui #5]

`Engine/ManaModel.lua` and `UI/Clock_Forever.lua` cite `TTO.lua` / `Widget.lua` by line numbers that
are already wrong; the 90/95 hysteresis exists twice. `UI/Clock_Forever.lua` owns the model instance,
the pricing, the events and the assume-full rule; `Recorder_Forever.lua:373, 588-593` reads
`MD.Clock.model.mana/.base/.casting` -- a v3 recording's mana track depends on a widget's private field.
`Book._lastRegenCasting` is the same pattern the other way.
**Change.** `Engine/ManaPool_Forever.lua` (`MD.Pool`: model, events, `CostFor`, assume-full,
`Sample()`, `Pool()`); the clock paints; the recorder samples `MD.Pool`; one pure `WantShown` for the
hysteresis used by both widgets; citations become function names. Merging the two clocks: not now
(TTO's latch layer is log-tuned).

### A30. Stream schema: three writers, no declared fields [live #3, sim #6]

The v2 table is built by `FightRecorder`, `Practice.Session:Finish` (which misses `names`, `threatOn`)
and v3 by `Recorder_Forever`; `Push` with truncation three times; retention policy four ways. **Change
(later):** `Engine/Stream.lua` on both base TOCs with `New`/`Push`/`Keep` and the field table in its
header; `importcheck`'s byte equality guards the persisted shape. The v3 constants part is in A18.

### A31. Smaller architecture items [kernel #13, live #7, #10, spells #10-#12, forever-ui #5, #7, #11, kit #10, shared-ui #5, #6, #9, #11]

- `Recorder_Forever.lua` (852) mixes roster, pull state machine, meter read, list/pin/address, command
  [modules #3c]. `Scenario_Forever.lua` (767) mixes attribution, party max, reconstruction [modules #4].
- Cross-module bare fields: `ST.combat` consumed by Summary, `MD.Regen.*` read raw by seven files,
  `fightHistory`'s implicit contract [live #7]. Accessors later.
- UI computing model numbers: Review's `LowestMana`, `Habits`, `ValidateCell` parsing gate prose;
  PracticePanel re-deriving damage/s; the replay strip reading planner internals [shared-ui #5].
  `g.short` on gates is the cheap step.
- `UI/SimWindow.lua` reads the threshold plan's field names (the shape that crashed `Classify` in
  v0.13.10) [shared-ui #6].
- Settings: no setting object; Forever General pane and `/st tooltip`/`/st clock` write the same keys
  with different normalisation; TBC Options panes hand-sync 20 widgets [forever-ui #5, shared-ui #9].
- Extension by wrapping: SpellsPane wraps `UI.ApplyFonts`; `UI.OnPopup` assigned [forever-ui #11].
  Events (`FONTS_CHANGED`, `UI_POPUP`) instead.
- Test-only markers in shipped code (`spellsBook`, `lastRows`, `refreshCount`, `_state`) [forever-ui #7].
- Dead or superseded: `UI.CreateNavBox`, `UI.CreateSeparator`, `MD:OpenDashboardSettings`,
  `Parse.Duration`, `Book:Entry`, `SD.relics[].perTick`, `ST:WindowStats`, `Targets:IsSelf`,
  `OH:Target`, `(x and "" or "")` no-ops in Review 369 / Waste 160, `Measure.BEFORE_STAMPS` hand-kept,
  `MD:HasBuff`'s `C_UnitAuras` branch in a TBC-only file, CLAUDE.md's "keep harness.lua's file list in
  step" (obsolete since T5), `Spells/Tabs.lua` and `Data/DruidSpells.lua` missing from CLAUDE.md's table.
- `Core.lua`'s `PLAYER_LEVEL_UP` calls `tonumber(level)` on an event argument with no `IsSecret`, in a
  file on the Forever TOC [kernel #13] -- look once.
- `release.sh` classifies TOCs by interface band; Forever's interface leaving 16xxx at launch breaks it
  in four places [tools #4].

### A32. Accepted seams (not to refactor)

Two window shells chosen by TOC, two clock widgets, `ManaModel.Text` rendering inside Engine, the
module proxy (`Module.lua`/`Ready.lua`), `Client/API.lua`'s Has/Call/Copy discipline, the
`CORE_LOGIN -> MD_READY -> CORE_READY` seam, `Core.lua` itself, the pure ReplayTrace/RunTimeline/
Foresight/Intuition files [kernel, sim, forever-ui #12].

---

## Part 3. UI and UX (merged)

Ranked by value to the healer (how often seen x how many surfaces).

### U1. The nav's selected state is its hover state; three selection languages in one window [ux kit #1, forever ux #9]

`CreateButtonGroup` (`Style.lua:418-441`) gives the active button the hover colour (accent 0.6) and
drops its hover scripts, so moving down the nav lights every button like the selected one. The rail
marks selection with 0.28 + bar, the rank table 0.10/0.28 + bar, the nav 0.6 solid. Spec 4.3 promised
"selected: accent 0.3 fill plus a 2-px accent bar" and the approved mockup draws it (`.nb.on`); the code
never got it. In the rank table, a selected row and the suggested row are two intensities of one hue.
**Change.** Active = `selected` fill + 2-px bar (left on nav, bottom on view tabs), hover = `hover`
everywhere, hover kept on the active button; gated on `UI.TEXT`. Selection in the table as an outline
or white bar, fill reserved for suggested (the latter departs from the mockup: needs a mockup).

### U2. Two tooltip skins in one window [ux kit #2, forever ux #5, shared ux #5]

Kit controls use the flat `SpellTunerTooltip`; `MD.Tip:Show`, the clock, Review rows, every replay
hover, the minimap button and the widget use the stock `GameTooltip`. Hover a Review button, then its
row: two designs 20 px apart. **Change.** `Tip:Show` renders into `UI.tooltip` when the theme is on; the
game's own spell tooltip on rank rows (decision 7) keeps its content in the same skin.

### U3. One crisp pixel only for frames styled by `StylizeFrame` [ux kit #3, forever ux #10]

`CreateButton` (375), `CreateCheckButton` (1526), rules and bars use `edgeSize = 1` / `SetHeight(1)`,
so at the author's 0.71 scale every button and check border is soft next to a crisp window edge. The
resize grip is Blizzard's chat-frame grabber on a flat skin. **Change:** edges and insets through
`UI.px`, registered for `RestylePixels`; the grip as three 1-px lines (the mockup's `.grip`). Zero cost
on TBC (`UI.px` returns `n`).

### U4. TBC now looks a generation older than Forever [ux kit #4, forever ux #4, shared ux #2, #15, #17]

On the client the author plays until 2026-11-04: gold everywhere and the suggestion stated three times
(gold row, `*`, "efficient rank" note); 10-pt cells on 16-px rows; four lines of prose over the table;
0.9-alpha window; family tabs that neither wrap nor scroll; HIGH-strata windows interleaving; one ESC
closing every window; no combat rule; a text-block bindings list and a separate bindings window; the
widget in 14-pt OUTLINE with no panel beside a flat Forever clock. Most of it is a TOC line away
(decision 10, "not now", revisit after a few weeks on Forever). **Change:** put decision 10 back to the
author with this list.

### U5. TBC tables: left-justified numbers in a 10-pt Blizzard font [shared ux #3]

`Dashboard_Rows.lua` COLS, Review (32-42) and Waste (19-42) left-align numbers in
`GameFontHighlightSmall` on 16-px rows: `25`/`55`, `1.5s`/`inst`, `1.2k`/`980` do not line up -- the
complaint the spec made of the old Forever pane. T30's options exist. Alignment is arguably not "the
look", but it is a TBC visible change: with decision 10.

### U6. The TBC Spells view has four lines of prose above the table [shared ux #4]

Simulate strip, a five-colour stats line, a gold callout and a glossary hint repeated every 2 s; the
table starts at -104. **Change:** the Forever spell-view structure (header, chip + one comparison line,
table with a bar marker and tags) with TBC's numbers; "Effective" becomes "After overheal" beside the
chip. Needs a mockup; with decision 10.

### U7. Legibility: `disabled` grey carries information; four greys within 100 levels [ux kit #5, forever ux #3]

`#4D4D4D` on `#161616` is about 2:1. It colours the gap row's explanation ("not in your spellbook -
untrained, or hidden by ..."), not-learned rows and their `learn at 14` tag, the tooltip's `Shift` hint,
the picker placeholder. `text2` #B3B3B3 and `label` #9D9D9D are indistinguishable through the shadow;
`muted` at 11 px is ~8 physical px at 0.71. **Change:** `disabled` only for inert controls and the
numbers of a not-learned/gap row; explanations in `muted`; tag in `label`; headers 12 px in `label`.
Departs from the spec's palette usage: needs a mockup.

### U8. The rail's hover controls are 14-px targets, the destructive one 2 px from a benign one, and they hide the rank [ux kit #6, forever ux #7]

`^ v x` replace the `R1` tag on hover (`Style.lua:883-896, 955-966`); at 0.71 each is ~10 physical px;
non-stale rows have no tooltip, so `R1` is never explained. **Change:** keep the tag, give the row a
tooltip ("Suggested: Rank 1 of 2 known"), controls 18 px with `x` separated by 8 px (or `x` only, reorder
by drag and the right-click menu). Departs from spec 3.2: needs a mockup.

### U9. Vocabulary: two per line, and a statistician's clock tooltip [ux kit #7, forever ux #6, #11, shared ux #11]

TBC `Heal/cast / HPM / HPS` vs Forever `Value / Per mana / Per s`; `Per s` (table) vs `Per second`
(tooltip); `To OOM` / `Casts to OOM` / `casts from full`; `dominated` (a Pareto term) as a tag. The
clock hovers read like model dumps: TBC `Time to OOM (raw) 80s +- 12s`, `CV 0.22`, `mp5 added, not in the
API`; Forever "the real pool is secret on this client", "Anchored 1:20 ago". Review headers `dur`,
`tgts`; the replay score as one string. **Change:** one vocabulary; clock hovers as label/value pairs in
healer language with sigma/CV behind the detail key; `dominated` -> an author's call (`beaten`, or keep
the word with a tag tooltip).

### U10. No column glossary on Forever; tags unexplained [ux kit #8, forever ux #6]

The generic table returns early on header hover (`Dashboard_Rows.lua:237`); TBC has `Tip:Columns`.
**Change:** `col.tooltip` rendered on header hover, and a tag-cell tooltip naming the rule. One sentence
each, from the spec's definitions.

### U11. Dead ends: module placeholders, a silent combat hide, empty searches [ux kit #9, forever ux #8]

"Review needs the Replay module - Settings -> Modules" as plain text (four clicks); modules that
"unload at your next /reload" with no Reload button; the window vanishing at the pull with no word; an
empty picker search shows a blank list and the search box has no focus. **Change:** a `Turn on` button
on the placeholder (it selects Settings -> Modules; the rule that a placeholder never loads a module
itself is kept -- or it calls `MD:SetModule`, the author's call), `Reload UI` where needed, a one-time
chat line on the first combat hide, "Nothing in your spellbook matches 'x'", focus on open.

### U12. Dropdown lists open off-screen; arrows are the letter `v` [ux kit #10, shared ux #18]

Lists anchor below with no flip (`Style.lua:1312, 1404`), sub-lists always right (1457); chevrons are
`v` and `>`. **Change:** flip up / left when the list would leave the screen; 8x8 textures for the
chevrons (letters as fallback).

### U13. `UI.SetTooltips` limits every kit tooltip [ux kit #11]

Anchor frozen at the first call; lines 2+ forced white (a muted hint is impossible); disabled buttons
show nothing because `SetMotionScriptsWhileDisabled` is never set, so a disabled Coach or Start cannot
say why. **Change:** folds into A21's renderer.

### U14. A resize grip on windows that cannot shrink [ux kit #12]

Spells/Settings `minW == w == 860`; the table and card are fixed 540. **Change:** hide the grip where
min equals default and nothing reflows, or let the table take the width.

### U15. Two size knobs; tooltips do not follow the window scale [ux kit #13]

"Font offset" and "Window scale" both enlarge; tooltips stay at UI scale, so at 90 % they are larger
than the rows beside them. **Change:** name by effect ("Text size", "Window size") with one sentence
each; scale `UI.tooltip` with the window.

### U16. The rail has no overflow [ux kit #14]

At level 60-70 with heals, damage and utilities (20+ rows x 19 px) rows run under `+ Add`. **Change:**
rows in a scroll frame when their extent exceeds the rail. Low now, certain later.

### U17. Two design generations in one Forever window; a nav click resizes the window [forever ux #1]

Spells and Settings are new; Review (16-px rows, 18-px buttons, TBC header) and Practice are the old
panes recoloured; Reports jumps the window from 860x560 to 1036x646 (`Win.SIZES`). **Change:** Review's
list on `CreateTable` with T30's options (on Forever); one size for every group departs from decision 6
(per-group sizes): the author's call.

### U18. The Forever clock cannot be placed at full mana [forever ux #2]

Shown only in combat or under 90 %, draggable only while shown; no lock/reset/preview in Settings (only
`/st clock lock`); no click action. TBC has "Lock widget" with a 60-s preview and "Reset position".
**Change:** a MANA CLOCK pane: show, lock (unticking previews for 60 s), reset, a click opens the window.

### U19. `/st dump` buries the errors under ~60 capability lines [forever ux #12]

**Change:** client, saved variables, modules, errors, then one capabilities summary line, the full
table and the debug log last.

### U20. The window's buttons answer in chat [shared ux #1]

Validate, Coach, Coach pull/run, the auto-coach and Settings' Verify / Regen test print to chat, where
the card scrolls away under party chat. **Change:** a result area inside Review (the last card or
validation, as lines; the coach's progress). Chat keeps one line. Needs a mockup.

### U21. The replay grows a second column under the healer's eyes [shared ux #6]

One column (492) opens; the auto-coach finishes and `RebuildSuggested` reopens at 968, re-centred. The
only warning is a 0.5-grey footer hint. **Change:** when auto-coach starts, lay out both columns at once
with the right one dimmed and titled `SUGGESTED  coaching... N plans`. Needs a mockup.

### U22. Playing a fight: four clicks and two hidden conventions [shared ux #7]

Row, then Play; no double-click, no row menu; `Coach*` means "shift-click to force", explained only in
the hover; forcing otherwise is a slash command quoted in a tooltip. **Change:** double-click plays; a
right-click menu (Play / Coach / Coach anyway / Validate / Pin / Export); the star goes. The shift-click
convention is a v0.9.8 decision on both lines: the author's call.

### U23. The replay's verdict is its faintest text [shared ux #8]

"does not replay (gate)", "no plan yet", "coaching", the practice error line: 0.5-grey 11-px footer; the
header packs six facts in one 11-px line; the v3 "reconstructed" caveat is another grey line. **Change:**
a status band under the header (the fight left, the verdict right in `good`/`bad`, a `Coach anyway`
button). Needs a mockup.

### U24. Settings parity on Forever; one wrong label on TBC [shared ux #9]

Forever reads `replayAutoCoach`, `replayNextPull`, `replayTicks`, `simAllowRebinds`, `simFullHp` with no
control for any; console, dump, measure and probe are slash-only; no About/commands view; the minimap
button is TBC-only, so the window is reachable only by typing. TBC: "Danger below (%)" is, since T20, a
fallback for built fights only, but its label and tooltip present it as the scoring line (a model
misstatement in the UI). **Change:** REVIEW and TOOLS panes and an About view on Forever; the minimap
button on both TOCs; TBC label "Danger line for built fights (%)" with a true tooltip.

### U25. Review and Waste lists silently truncate [shared ux #10]

Rows stop at the pane's height; a 36-pull run shows ~30 and nothing says so. **Change:** a scroll frame
(Practice and Bindings already do), or at least `... and 6 more`.

### U26. No size scale [shared ux #12]

Six button heights (16-26), three row heights, `GameFontHighlightSmall` beside the kit fonts; the
number font exists only in the theme. **Change:** `UI.H.button/small/row/toolbar` constants in Style;
the two ARIALN fonts moved to Style (they carry no colour). Panes adopt them as they are touched.

### U27. Space does not play the replay, though the button says it does [shared ux #13]

The play button's tooltip promises Space; the keyboard is enabled only in practice. **Change:** enable
the keyboard for replays with practice's propagate pattern (Space, Left/Right 5 s), or delete the
sentence. A stated affordance that fails.

### U28. Tooltip anchoring on wide rows [shared ux #14, kit #2]

Review's 852-px rows use `ANCHOR_RIGHT`, so the gate tooltip appears at the far edge and off-screen.
Spec 3.5's "beside, flip at the edge" exists only in SpellsPane. **Change:** one `Beside(row)` in the
tooltip renderer (A21).

### U29. Build a fight (SimWindow) aligns columns with `%-12s` in a proportional font [shared ux #16]

Low traffic; demote or rebuild on the table when touched.

### U30. Font offset does not reach measurements [shared ux #19, ux kit #15]

Check-button hit rects measured once; view-button widths from `#text * 8 + 16`; at +2 labels outgrow
their rects. **Change:** measure with `GetStringWidth()` after `SetText`; `FONTS_CHANGED` re-measures.

### U31. Small consistency items [ux kit #15, forever ux #8]

Header title centred on the whole header while a back button takes 84 px; sheets have no `x`; the mask
is mute (Cell's carries a line of text); nav buttons 22 tall and view tabs 20, both at -2 (2-px
misalignment); palette fallbacks duplicated (`pane` 0.13 vs 0.11 vs `0x1C`); Modules pane heading not a
titled pane; General's right half empty; the U+00D7 close glyph (B3).

---

## Part 4. Tests and tools (merged)

### Q1. The forever stub's secret is a table, so every `IsSecret` guard on an event payload is untested [tests #1, tools #6a, modules #11] -- confirmed by mutation

`S.Secret()` is a table, so `type(secret) == "table"` under the stub and `"number"` on the client.
Handlers are written `if MD.API.IsSecret(x) or type(x) ~= "number"`; under the stub the second clause
alone rejects the secret. Removing the `IsSecret` half from seven guards
(`Recorder_Forever.lua:458, 485, 498, 567, 568`, `Spells/Measure.lua:796`, `UI/Clock_Forever.lua:247`)
left recordcheck, measurecheck, clockcheck, scenariocheck, gatecheck, coachforever, forevercheck and
adaptercheck green: "a secret argument is counted and never stored" passes for the wrong reason.
**Change.** In `UseProfile("forever")`, wrap `type` so a secret answers `"number"` (3 lines; verified to
turn the same mutation red). Follow-ups: clockcheck must assert the book was never indexed by a secret
(Lua 5.1 cannot trap `t[secret]`); drop `adaptercheck.lua:227` (a table keyed by a secret cannot exist
on the client). Write the residual gaps (`#secret`, `secret == plain`, secret as key) in the stub header
and TOOLS.md as review-only.

### Q2. `apicheck.py` rule 8 misses aliases -- the recorder's own idiom [tests #2]

On the mutated tree rule 8 caught 5 of 7; it missed `Recorder_Forever.lua:485, 498`, which do
`local sid = spellID` first. **Change:** follow `local NAME = <param>` aliases; add the case to the
selftest fixture. Also: a rule "no `RegisterEvent(` outside `Client/` and `Core.lua`"
(`UI/ReplayWindow.lua:1993` registers on a raw frame, bypassing `MD:On`'s forbidden-event guard); and a
rule "no non-ASCII byte in a string constant" over all three lines' files (would have caught B3).
apicheck covers only the Forever TOCs; the "client calls in `Client/`" rule is unenforced on TBC, which
is by design, but the ASCII rule should cover both.

### Q3. `tools/simcheck.lua` exits 0 whatever the engine's self-tests say [tests #3] -- confirmed

It never reads `RunSimRun`/`RunSimReplay`'s verdicts; breaking `Near` gives 5 `FAIL` lines, rc 0, and
the loop's `tail -1` shows the replay's `-> PASS`. The ten engine self-tests are unmonitored.
`wclcheckkit.lua` has no exit code either. **Change:** return the counts, `os.exit(1)`, standard footer.

### Q4. The flavour skip exits 0, so a mis-declared suite is a silent pass [tools #3]

`tools/harness.lua:32` exits 0 with `skip:`. `probecheck` re-dofiles the harness under two flavours and
only runs unflavoured; `importcheck` spawns `importfixture.lua` without scrubbing `ST_FLAVOUR` and fails
18/19 under `--flavour tbc`. An obvious `for f in forever tbc` runner gets false greens and a false red.
**Change:** the harness returns a skip and the tool decides (a skip after the first assertion is a
failure); every subprocess through one environment-scrubbing helper.

### Q5. No runner; the loop is prose; counts are kept by hand in three documents [tools #8, tests #8, #10]

`docs/TOOLS.md` section 1 is a copy-paste block whose verdict is `tail -1` per suite (it shows Q3's
PASS and treats `skip:` as a result); no `make check`; `release`/`install` gate on nothing. CLAUDE.md
quotes navui 25, reviewui 23, replayui 50, practice 45; actual 35, 44, 98, 80. **Change:**
`tools/check.sh` / `make check`: every suite under each declared flavour, rc and footer required,
`FAIL`/`skip:` as failure where the flavour was requested, apicheck and both python selftests; counts
compared with `tools/data/expected-counts.json` (a decrease fails); release/install depend on it with
`--no-check`. Counts leave the prose.

### Q6. The importcheck fixture embeds the addon version [tests #4]

Byte-for-byte comparison plus `["version"] = "0.16.3"`: every `--set-version` fails importcheck until
the fixture is regenerated, and the regenerated diff hides a genuine storage change. **Change:** stamp a
fixed token in `importfixture.lua`, as it already does for dates and builds.

### Q7. `releasecheck.lua` needs a git checkout and blames the wrong thing [tests #5, tools #9]

Outside a repository the scratch copy is empty and one folded check reports `lost its CRLF: 0 of 0`.
**Change:** assert the copy first with its own message, fall back to `find`, split the folded check into
four. `release.sh`'s two TOC collectors duplicate one loop and its section comments run 1, 5, 2, 4, 3.

### Q8. `C_Timer.After` in the stub ignores its delay and never fires from `S.Tick` [tests #6]

Suites flush by hand at moments they choose (`recordcheck.lua:92-94`, `probecheck.lua:193`,
`practiceforever.lua:657-661`, `spellsui.lua:391-399`, `importfixture.lua:168`), so the R10 death
re-poll (`Recorder_Forever.lua:798`, `After(1, ...)`, whose point is when it runs) and
`Core_TBC.lua:239` (`After(5, WriteProfile)`) are tested "immediately" or never. **Change:** due times
fired at the end of `S.Tick`; hand flushes become "nothing left due" assertions.

### Q9. Suite boilerplate copied 36-51 times, with drift [tools #2]

`check()` in 36 files, the `arg[0]` dance in 51, `CapturedChat` in 6, the ASCII/no-bare-pipe rule
implemented seven ways (`AsciiSafe` permits `\n`, `AsciiClean` may not), colour stripping six ways,
frame geometry in five suites. The three big suites are sequential scripts sharing state. **Change:**
`tools/lib/t.lua` (check, section, done, Ascii, Strip, CapturedChat, NewSession); new and touched suites
adopt it; no mass migration.

### Q10. `tools/wowstub.lua` is one file with two clients; Forever is one 899-line closure [tools #1, #11]

Every Forever UI task added stand-ins to the same closure; the header ("nothing draws") is no longer
true; the only fresh session is re-dofiling the stub. `harness.lua` silently makes every TBC suite "the
BF-1 druid". **Change (later):** split by responsibility with `S.New{flavour}`; do it when the next
large stand-in is added, not before Q1/Q8.

### Q11. Shipped UI carries test hooks; suites find widgets by painted text [tools #7, forever-ui #7, shared-ui #7]

~40 lines of markers and counters for named suites; `MD.Replay._state()` hands out closure locals;
suites scan `S.allFrames` comparing `GetText()` (dashui 16 scans...). A redesign breaks tests by string
match. **Change:** kit frames carry a stable `id`, the stub gets `S.Find(id)`, windows an `Inspect()`;
migrate one suite per UI task, never in bulk.

### Q12. The stub has no geometry; layout code is tested as "does not crash" [kit #9, shared-ui #7]

`GetLeft` 0, `GetStringWidth` 40, `GetEffectiveScale` 1; wincheck installs its own geometry privately.
`UI.px`, clamping, the rail's drop slot, the tooltip flip, dropdown flips (U12), rail overflow (U16) are
unassertable. **Change:** promote wincheck's geometry into the stub as opt-in (`S.Geometry(true)`) with
a deterministic text metric.

### Q13. Research tools each re-implement "load SavedVariables, impersonate the character"; the TBC import half is untested [tools #5]

Seven copies of the SV location, six of the profile snapshot/restore hack and `ApplyProfile`, four of
the author's install path; `import.lua` and `importforever.lua` diverged. B25 is the symptom.
**Change (later):** `tools/lib/savedvars.lua`, `profile.lua`, `kit.lua`; a TBC mode for
`importfixture` so importcheck covers both roads (the TBC mode is taken now, with B25).

### Q14. The API baseline is build 69893; the client is at 70058 [tools #10]

`apicheck`'s allow-lists name eight globals the stub does not define. **Change (later):** `/st probe api`
dumps the globals; a script turns a report into the baseline; a stub self-check over the allow-lists.

### Q15. Smaller [tests #7, #9, #11, tools #6c, #11]

- `tools/reviewui.lua:266` waits a fixed 200 frames and asserts "no plan"; assert `MD.coachSearch == nil`
  right after the click instead.
- Measurement tools (`strategies`, `solvercmp`, `wclcheckkit`, `reproduce`, `healcheck`) die with a
  traceback when the gitignored default file is absent and are outside the loop: usage lines, and one
  smoke run of `reproduce`/`strategies` against `tools/data/practice/1790701698.lua`.
- TBC stub: `GetSpellPowerCost` nil, so `SD:GetCost`'s live branch (the one the client takes) never runs;
  `UnitAffectingCombat` always false (A28).
- `run.sh` downloads Lua 5.1.5 with no checksum -- the harness's trust root.
- `MD.API.Has` caches forever, so the stub grew ~30 settable fields to route around it; an
  `MD.API.Invalidate(name)` for tests; `MD:SetTalents(tbl)` so the harness stops overriding
  `MD:TalentRank` after load.

### Q16. What is sound and should be kept [tests, tools]

Assertion quality is good (one literal-condition check in 1,600+; bookcheck's expected numbers
hand-derived with the arithmetic in comments); the causality invariant is genuinely tested
(`coachforever.lua:236-256`, `solvercheck`); `parse-fixture.lua` carries provenance; apicheck and
refcheck self-test; releasecheck runs the real `release.sh` into a path with a space; TOC-driven load
lists everywhere; the whole loop takes ~12 s serially.
