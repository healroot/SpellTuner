# R-classes: supporting more spells and more classes

Research for the author's request, after 0.16.5: "think of how we can better support more spells and classes".
Read-only pass over worktree `manademon-folder-continue-41eabc` at `c911339`. Line numbers are from that tree.
Two scratch runs back the claims marked **[ran]**. Both are reproducible from `scratchpad/next/work/`:

- `run.lua` runs the real `Spells/Parse.lua` (`Parse.Description`, `Parse.Cost`, `Parse.Cast`) over all 1796 `spell_desc` rows of the cached talentsforever export (`tools/.cache/talentsforever.json`, build 70009). Output is in `all.txt` (every rank) and `top.txt` (top rank per spell).
- `cdtest2.lua` loads the TBC harness and calls `Solver:Decide` with Swiftmend on cooldown.

---

## 0. Summary

1. **On Forever the reading side is already class-agnostic. Everything after it is druid-only.**
   - Generic: `Spells/Book.lua` and `Spells/Parse.lua` read any spellbook. The tooltip block and the Spells pane work for a priest, shaman or paladin today.
   - Druid-only by name: the kit, which decides what the engine, solver, practice and coach can use.
     - `Modules/SpellTuner_Replay/Kit_Forever.lua:21-37` (`FAMILY_KEY` / `FAMILY_TYPE`: Healing Touch, Regrowth, Rejuvenation, Swiftmend, Tranquility).
     - `Modules/SpellTuner_Recorder/Stream_Forever.lua:28-33` repeats the same list.
   - Any other heal family is dropped into `skipped` (`Kit_Forever.lua:81-86`). Wild Growth is the druid's own example.
   - On top of that, 15 UI and command sites hard-gate on `MD.player.isDruid`. They are listed in section 4.
2. **The engine has six entry types, all druid-shaped** (`Engine/Kit.lua:69-77`, `Engine/SimModel.lua:573-600`):
   - It has three fixed HoT slots named after druid spells (`SimModel.lua:91-92`).
   - It has no absorb, no group or bounce heal, and no generic cooldown. `SPELL_CD = { [18562] = 15 }` (`SimModel.lua:111`) is the only cooldown.
   - The `channel` type lands nothing: `LandCast` has no branch for it.
3. **Bug [ran]: the solver ignores spell cooldowns.**
   - `Solver:Best` (`Engine/SimSolver.lua:332-400`) never calls `SM.Ready`, and the engine's `Succeed` (`SimModel.lua:604-630`) does not check it either.
   - With Swiftmend on cooldown until t=20, `plan:Decide(S, 10, ...)` returns 18562.
   - This is a live druid bug and a hard blocker for Holy Shock, Riptide, Prayer of Mending, Power Word: Shield, Penance and Wild Growth.
4. **The parser reads the first target's number on every group or bounce heal and says nothing about the rest.**
   - Prayer of Healing, Chain Heal, Wild Growth, Tranquility, Holy Nova and Binding Heal all parse as one target's heal [ran].
   - Ranks within one family are still compared correctly, because the target count is the same for every rank. Absolute per-mana numbers, cross-family comparisons and the solver are wrong.
   - It refuses, by design, a set of spells that matter to these classes: Penance, Prayer of Mending, Healing Stream Totem, Lightwell, Lay on Hands, the mana totems and Water Shield.
   - It misreads three [ran]:
     - **Light's Vigil** reads as a 684-724 direct heal costing 1340 mana. It is really a buff for the next Holy Shock.
     - **Mana Burn** reads "0.5 Shadow damage" as 5 damage.
     - **Execute** reads "15 additional damage" as its hit.
5. **Recommended order:**
   1. Engine correctness, offline and small.
   2. Forever reading truth for all classes: targets, cooldowns, refusals.
   3. A generic Forever kit with group and chain heals plus cooldowns, coached by the solver only.
   4. Absorbs. This needs probe answers first.
   5. TBC multi-class through tooltip-read base values plus a VERIFY rule table, as `Engine/DamageMath.lua` already does.
   6. Non-healer extras.

---

## 1. Healers: what is there and what is missing

### 1.1 Parse coverage per class (Forever build 70009 texts, `Spells/Parse.lua` as is) [ran]

Counts below are top-rank rows only, from `top.txt`, passives excluded. The power is taken from the cost line.

| class | mana spells read as heal / absorb | read as damage | read as nothing (NIL) |
|---|---|---|---|
| Priest | 9 (+3 with no cost line) | 10 | 32 |
| Shaman | 4 | 8 | 36 |
| Paladin | 4 | 7 | 31 |
| Druid | 5 | 6 | 21 mana, 11 rage/energy |

Most NIL rows are buffs, utility and auras; refusing those is correct. The healing-relevant rows are below.

#### Priest

| spell (top rank) | Parse result | what is wrong for a model |
|---|---|---|
| Lesser Heal, Heal, Greater Heal, Flash Heal | `heal {min,max}` | Nothing. These are plain direct heals. |
| Renew R10 | `heal {over=830, dur=15}` | The tick period is not in the text. `Kit_Forever.lua:43` assumes 3 s for every HoT. |
| Power Word: Shield R10 | `absorb=928` | The 4 s cooldown and the "cannot be shielded again for 15 sec" lockout (Weakened Soul) are not read. `Book` treats it as an instant direct heal (`Spells/Book.lua:159-170`, `PartShape` 412-417). |
| Prayer of Healing R5 | `heal {631..667}` | "heals the target and their party". The value is one member's; real value is up to 5x. |
| Binding Heal R6 | `heal {773..909}` | "a friendly target and the caster": up to 2x. |
| Holy Nova R6 | `heal {288..334}` + `damage` | Heals the party within 10 yd (up to 5x), instant, no cooldown. Family kind becomes "heal" (`Book.lua:372-380`), so the damage half is invisible to a shadow or holy-dps priest. |
| Penance R1-R4 | **NIL** (refused on purpose by `PeriodicOrEitherAfter`, `Parse.lua:197-206`) | Channel, "instantly and every 1 sec for 2 sec" = 3 bolts, 12 s cooldown, either damage or heal. R4 is flagged `fx` in the data (beta slip). |
| Prayer of Mending R3 | **NIL** | "heals them for 413 the next time they take damage ... jumps ... up to 5 times", 10 s cooldown. Event-triggered, with an unknown jump target. |
| Desperate Prayer R7 | `heal {1285..1513}` | Self only, no cost line. |
| Divine Grace R1-R7 | `heal` | Only on a target below 50%, 10 min cooldown, removes Weakened Soul. The condition is not read. |
| Contingency Plan | `absorb` only | Its "125 Health over 15 sec" HoT is dropped. It is a conditional ward (triggers at 35%). |
| Lightwell R3 | **NIL** | Clickable charges ("restore 1,600 health over 10 sec"). Not the caster's decision per heal. |
| Vampiric Embrace | NIL | A heal that follows damage dealt. Can only be replayed as recorded. |
| Inner Focus, Power Infusion | NIL | Next-cast modifiers (free + crit, +20%). |

#### Shaman

| spell | Parse | what is wrong |
|---|---|---|
| Healing Wave, Lesser Healing Wave | `heal {min,max}` | Nothing in the text. Healing Way-style target stacking, if present, is not in the caster's text. |
| Chain Heal R3 | `heal {474..538}` | "jumps ... Each jump is 50% as effective ... Heals 3 total targets": 1 + 0.5 + 0.25 = 1.75x when three are hurt. Riptide's "+25% Chain Heal on that target" is not read either. |
| Riptide R3 | `heal {799..883, over=805, dur=15}` | Hybrid shape, parsed right. The 6 s cooldown is not read (it sits in the cooldown line, not the text). |
| Healing Stream Totem R5 | **NIL** | "heals group members within 30 yards for 11 every 2 seconds", 5 min. A party HoT shape `TICK_HEAL` does not match ("every 2 seconds", duration before it). |
| Mana Spring Totem, Mana Tide Totem | NIL | Mana sources ("restores 290 mana every 3 seconds"), not heals. |
| Water Shield | NIL | A mana return on being hit and on a heal crit (2% max mana). |
| Nature's Swiftness | NIL | Next-cast modifier. |

#### Paladin

| spell | Parse | what is wrong |
|---|---|---|
| Holy Light R9, Flash of Light R6 | `heal {min,max}` | Blessing of Light ("increasing the effects of Holy Light ... by up to 400") is a **target-side** bonus. It is not in the caster's text. |
| Holy Shock R4 | `heal {307..333}` + `damage` | 10 s cooldown not read, so per second is computed over 1.5 s (`Book.lua:163-165`): about 6.7x too high. |
| **Light's Vigil R1-R3** | `heal {684..724}` + `damage` **(MISREAD)** | A buff: "Your next Holy Shock ... heal their party for 684 to 724". The Book values it as a 1340-mana direct heal. |
| Lay on Hands | NIL | Amount = caster's max health, 20 min cooldown. |
| Divine Favor | NIL | Next-cast 100% crit. |
| Illumination / Reverence (talents) | not spells | Mana back on a crit or from Spirit. `REFERENCES-FOREVER.md` §4 records them as changed on Forever. |

#### Druid's own gaps

- Healing Touch, Regrowth (every rank 1-9, hybrid), Rejuvenation (1-11), Tranquility (tick shape) and Wild Growth (`over/dur`) **all parse** [ran]. The gaps are in the model.
  - **Regrowth** is a modelled hybrid at every rank on both lines: `Kit_Forever.lua:140-151` and TBC `RankMath.lua:254-292`. Nothing is missing there.
  - **Tranquility** is in the kit as `channel` (`Kit_Forever.lua:152-161`), but `SimModel.LandCast` has no `channel` branch (`SimModel.lua:578-599`). It is also excluded from plans (`Kit_Forever.lua:62`, `SP.BINDABLE`, `SimPlanner.lua:84-87`). A recorded Tranquility costs mana in a replay and heals nothing in the engine.
  - **Wild Growth** is skipped (`Kit_Forever.lua:81-86`). It is a party HoT whose ticks are "applied quickly at first, and slow down". `TICK_PERIOD = 3` (`Kit_Forever.lua:43`) is wrong for its 1 s ticks, and the front-loaded shape is not in the text.
  - **Innervate** is `Kit.UNPRICED` on TBC (`Engine/Kit.lua:84`) and valued in `Engine/ManaCooldowns.lua:29-37`. On Forever nothing models it:
    - `Engine/ManaPool_Forever.lua` regenerates at the rate last read out of combat, and `GetManaRegen` is secret in combat.
    - So the modelled pool under-counts for the whole 20 s of an Innervate, and the clock reads too low.
    - The Innervate aura is plain on Forever (`ShouldAurasBeSecret = false`, `docs/probe/1.60.1_70009.md:97`) and its text gives "400%". A Forever mana-source table could carry it, and Mana Tide likewise.

### 1.2 What the rank rules and the tooltip say wrongly

`Spells/RankRules.lua` compares ranks **within one family** on per mana and per second (`Book:Rows`, `Book.lua:552-590`).

1. **Group and bounce heals: the within-family verdicts stay right.** The target count (PoH's party, Chain Heal's 1 + 0.5 + 0.25) is the same multiplier on every rank, so dominance and the suggested rank do not change. What is wrong:
   - The absolute "Per mana" and "Per sec" in the tooltip (`UI/SpellTip_Forever.lua:323-330`).
   - The Overview's cross-family list.
   - Any future solver choice between families: PoH at 0.6/mana per member against Greater Heal at 2.8/mana.
2. **Cooldown spells: the interval is wrong.** `IntervalFor` (`Book.lua:159-170`) is `max(cast, GCD)`, so per second and casts to OOM assume a cast every 1.5 s. Affected: Holy Shock (10 s), Riptide (6 s), PoM (10 s), Penance (12 s), PW:S (4 s cooldown, plus 15 s per target), Wild Growth (6 s), Swiftmend (15 s), Divine Grace (10 min).
   - Pareto between ranks is unaffected (same cooldown on every rank).
   - The "Per sec" line and "Casts to OOM" are wrong.
3. **Absorbs.** `PartShape` calls an absorb `direct` (`Book.lua:417`), so it gets a direct heal's interval and words. The block shows "Absorbs N" and no crit (`Spells/Words.lua:201, 226`), which is right. Per second is still over 1.5 s, which ignores the 4 s cooldown and the 15 s Weakened Soul lockout.
4. **HoT tick period.** The Forever kit divides every HoT into 3 s ticks (`Kit_Forever.lua:43`, 134-137). The text gives total and duration only. Rejuvenation, Renew and Riptide are probably 3 s but unverified; Wild Growth is 1 s per the reference site (`REFERENCES-FOREVER.md` §4). `/st measure` already infers the period from cadence in game (CLAUDE.md, `Spells/Measure.lua`, T12b).
5. **Crit school (minor).** `Kit_Forever.lua:98` reads `SpellCritChance(4)` (Nature) for the whole kit. On Forever "hit and crit are merged" and the 70124 probe shows the same crit for every school (`docs/probe/1.60.1_70124.md`, "crit: every school 4.9994"), so it is harmless today. Make it the family's school.
6. **Holy Nova and Holy Shock lose their damage half.** Family kind is heal-first (`Book.lua:372-380`, 484-499), so a holy or retribution damage user never sees the damage numbers.
7. **The seed picks heals for every hybrid class.** `Tabs:SeedList` (`Spells/Tabs.lua:170-176`) seeds heals whenever any heal exists, so a shadow priest, retribution paladin or elemental shaman starts with a heal list.

### 1.3 Kit types and engine mechanics that are missing

The kit's shape is `Engine/Kit.lua:46-77`. The engine's dispatch is `SimModel.lua:573-600`. The solver's candidate loop is `SimSolver.lua:332-400` and its danger rule is 440-500.

| mechanic | needed for | today | what it takes |
|---|---|---|---|
| **Cooldown per spell** | Holy Shock, Riptide, PoM, Penance, PW:S, WG, Swiftmend, Divine Grace | Only `SPELL_CD[18562]` (`SimModel.lua:111`). The **solver never checks it** [ran: Swiftmend picked while `SM.Ready` is false]. Only the threshold rule 1 (`SimPlanner.lua:244`) and Practice (`Practice.lua:1364`) check. | A `cooldown` kit field (`Kit.FIELDS` first). `SPELL_CD` built from the kit. `SM.Ready` in `Solver:Best` and in rule 8. The engine refusing (and tracing) a plan cast on cooldown. |
| **Per-target lockout** | PW:S / Weakened Soul 15 s | none | A `lockout` kit field and an `S.lock[ti][family]` table, read by `SM.Ready(S, id, t, ti)`. |
| **Absorb** | PW:S, Contingency Plan, Templar's Bulwark | `Damage()` (`SimModel.lua:468-482`) subtracts health directly. | A shield state per target eaten first in `Damage`, with expiry. **Replay hazard:** recorded damage is after absorbs. TBC's recorder keeps only *full* absorbs (`Engine/FightRecorder.lua:363-372`, `K.ABSORB`) and drops a partial `absorbed` field (344-360). Replaying "no shield" on that stream understates the danger. The recorder must store the absorbed part per hit, and on Forever whether `UNIT_COMBAT` shows it is unknown (probe question). |
| **Group heal** | PoH, Holy Nova, WG, Tranquility, Healing Stream Totem | Every `Land` is one target. `Scenario_Forever` attributes a heal to the cast's one target (`Scenario_Forever.lua:141-145`). | A `targets = "party"` field. `LandCast` loops over the tracked members of the caster's group (`Engine/Targets.lua` has `subgroup`, T48). The solver sums `saved` over the affected targets. Attribution accepts N same-instant claims. |
| **Bounce / smart heal** | Chain Heal | none | `jumps`, `falloff`. The engine picks the next most-injured tracked member (VERIFY the client's rule). Value = sum of the falloff series over the targets picked. |
| **Self + target** | Binding Heal, Desperate Prayer (self only) | none | `alsoSelf = true` / `selfOnly`. |
| **Channel heal** | Tranquility, Penance (heal side) | `channel` type has no landing branch. | Land `channelTick` x `channelTicks` on the period, cancel on preemption. |
| **Front-loaded HoT** | Wild Growth | uniform ticks | Keep uniform ticks marked VERIFY until `/st measure` gives the per-tick curve. Never invent a curve. |
| **Generic HoT slots** | Renew, Riptide, WG, any HoT | `HOT_INDEX = {Rejuvenation=1, Regrowth=2, Lifebloom=3}`. `hot` always goes to slot 1 and `hybrid` to slot 2 (`SimModel.lua:581-586`). `Scenario_Forever.lua:73-77` maps them the same way. | Slots keyed by family, assigned when the kit loads. `SM.HOT_NAME` built from it. Swiftmend's order stays a druid table. |
| **Charges / event-triggered heal** | Prayer of Mending, Lightwell | none | Defer. PoM's jump target is not knowable causally. Replay it as recorded (see below). |
| **Mana returns (procs)** | Illumination, Water Shield, Inner Focus, Clearcasting (Omen) | Cost is a constant. | An expected-value field (`refundOnCrit`, as a fraction of cost) the price and the mana model read, labelled "assumed", the same way `directCrit` is expected-value already (`SimModel.lua:563-571`). |
| **Mana sources** | Mana Tide, Mana Spring, Innervate (Forever), Blessing of Wisdom | TBC: `ManaCooldowns.byClass` has priest, shaman and paladin **stubs** without a value function (`Engine/ManaCooldowns.lua:47-53`). Forever: nothing. | An aura-driven table: a buff seen means a rate read from the spell's own text ("290 mana every 3 seconds"). This is a parse shape to add, and it feeds `Engine/ManaModel.lua`. |
| **Heals the plan does not choose** | Totems' ticks, Lightwell, Vampiric Embrace, Judgement-type effects | Unclaimed own heals become foreign healing (the gate's "foreign share"). | Make it explicit: an own heal no kit entry claims is replayed **as recorded**, like foreign heals (`K.FHEAL`). This keeps the causality invariant and needs no model. |

The threshold-rule planner is druid tactics through and through: `SP.BINDABLE`, `SP.HOT_RULE`, Lifebloom anchor and Swiftmend line (`Engine/SimPlanner.lua:84-90`, 240-440). Do not generalise it. The **solver** is the class-neutral coach: a spell is a list of deposits (`SimSolver.lua:56-90`) and the choice is health-seconds per mana. It needs three changes:

1. The family list comes from the kit instead of `SV.FAMILIES` (`SimSolver.lua:279`).
2. Cooldowns are respected.
3. A group cast sums its gaps over the targets it reaches.

The `fixed` mechanism (`SimModel.lua:717-930`, SPEC-v0.10) already keeps every non-heal cast at its recorded time and cost. A priest's Inner Focus or a shaman's totem drop is therefore handled today without modelling.

---

## 2. Non-healers

### What a damage dealer or a tank gets today

- **Forever.** The Book reads damage families. `Spells/Parse.lua` covers direct, DoT, hybrid, channel and "enemies every N sec", and `Engine/DamageMath.lua` is TBC only. The tooltip block (`UI/SpellTip_Forever.lua:285-345`) shows the value, crit range, per mana, per second and the comparison with the top rank. Casts to OOM is shown for mana costs only (line 328).
  - A Rage, Energy or Focus cost is read as no mana (`Book.lua` R13, the `free` cost state): "no mana (10 Rage)".
  - Coverage [ran]: Mage 15 of about 51 mana spells read, Warlock 16 of 59, Hunter 6 of 45.
  - Physical classes read almost nothing. Warrior reads 2 of 29 rage spells (Rend, and Execute misread), Rogue 2 of 22, feral druid 5 of 16. Most text is "weapon damage plus N" or scales with attack power, which the text does not state.
- **The mana clock** is class-generic on both lines. It is gated by `MD.player.usesMana` (`Core.lua`, T52), so mages, warlocks, hunters and casters get it; warriors and rogues correctly do not.
- **TBC.** The spell tooltip is druid-only (`UI/SpellTooltip.lua:57`), and `DamageMath` covers druid Balance spells only (`Engine/DamageMath.lua:36-42`). The clock, widget, ElvUI datatexts and Waste view work for any class (DECISIONS item 13). Summary extras are druid-only (`UI/Summary.lua:496`).

### Worth adding, in order

1. **Fix the three misreads**, which matter to everyone:
   - Decimal amounts (`NUM = "%d[%d,]*"`, `Parse.lua:15`, matches the "5" of "0.5": Mana Burn).
   - The "N additional damage" catch-all (Execute: "converting each extra point of rage into 15 additional damage").
   - A future-tense "your next X" clause (Light's Vigil).
2. **Damage half of either-or spells.** Give a family both parts (Holy Shock, Holy Nova, Penance once read), and show the half matching the player's role. Read the role from spec or talent points, else from the seeded list's kind.
3. **Caster mana sources** on the clock: Evocation, mana gems, Life Tap (health to mana; `Engine/Targets.lua` already counts Life Taps per member on TBC). These are ManaCooldowns rows with values from the client's own text. A mage's clock is as real as a healer's; the downranking question (is Frostbolt R1 worth it for a slow) is the same rank dashboard.
4. **Not worth it now:** physical rotation math (attack power scaling is not in the text, so every number would be a model from memory) and tank tooling. A tank gets the recorder's damage-taken stream in Review already. Anything more is a different addon.

---

## 3. TBC: what priest, shaman and paladin support takes

### What is druid-only today

- `Data/SpellData.lua`: the static druid table, heals verified against 17 WCL parses (header 1-19). `SD.families` 31-38.
- `Engine/RankMath.lua`: druid talent multipliers (`Context`: Gift of Nature, Empowered Touch/Rejuvenation, Improved Rejuvenation, Naturalist, Improved Regrowth, Nature's Grace at lines 137-160; Tree of Life). Coefficient rules for direct (`RowFor` 220-247), hot (249-262), hybrid (264-292) and lifebloom (294-330).
- `Core_TBC.lua:99` (`InTreeForm`), the talent scan and `MD.RELEVANT_TALENTS` (122+).
- `Data/DruidSpells.lua` (non-heal casts), `Spells/Families_TBC.lua` (rail from SpellData), `Engine/DamageMath.lua` (Balance), `UI/SpellTooltip.lua:57`, `UI/Advisor.lua:58`.
- The WCL pipeline: `tools/wclconvert.py:51` `HEAL_FAMILIES` and its druid talents at 422-428. `"class": "DRUID"` is written at 488.

### Two ways to get values, under the rule "no value from memory" (CLAUDE.md, `Data/SpellData.lua` header)

| | static tables per class (Phase 2 of `docs/PLAN.md:412-430`) | read the TBC client's own tooltips (DamageMath's pattern) |
|---|---|---|
| base values | Typed in, so they must each be checked by `/md verify` (costs only, `Diagnostics_TBC.lua`) and by WCL fits. From memory until then. | **From the client.** TBC tooltips are static: they print each rank's base before bonus healing (`Engine/DamageMath.lua:6-14`). Read with the shared `Spells/Parse.lua`, which is pure and loadable on TBC (today it is only on the Forever TOC: `SpellTuner_Mainline.toc:13`, absent from `SpellTuner_TBC.toc`). |
| unlearned ranks | in the table | Need the rank's spell id. The spellbook lists known ranks only; ids of unlearned ranks are facts, checkable by `GetSpellInfo(id)` name and rank in `/md verify`, but still a list. |
| coefficients, talents, downrank penalty | rules + talent table, VERIFY | **The same.** The coefficient rules (cast/3.5, duration/15, the amount-weighted hybrid split, `Penalty` `RankMath.lua:40-49`) are shape rules, not per-spell numbers. Group heals' coefficient split is a new rule (VERIFY). Talents per class are a table from memory either way. |
| cost, cast | live (`GetSpellPowerCost`, verified on 2.5.x 2026-09-03; cast from `GetSpellInfo`) | live |
| verification | `/md verify` + `/md calibrate` (CLEU exists on TBC, so `Engine/Calibration.lua` compares every landed heal with the prediction) + WCL fit | the same |

**Recommendation for TBC:** read base values from the client's tooltip (`GetSpellDescription(id)` if the 2.5.x client has it, else a hidden tooltip scan via `SetHyperlink("spell:id")`), parsed by `Spells/Parse.lua`. Keep a per-class rule table that is coefficients by shape plus talent multipliers, every row marked VERIFY.

- **Keep `Data/SpellData.lua` for the druid.** It is verified, and replacing it changes TBC behaviour, which needs a documented decision.
- The first priest number then comes from the client, and the only from-memory parts are the rules. That is exactly the status `Engine/DamageMath.lua` already has, and it is labelled on Shift.
- **Offline verification before anyone plays a priest:**
  - Extend `tools/wclconvert.py` / `tools/wclcheckkit.lua --fit` to a class argument (spell families from the log's own ability names) and run it on public TBC Anniversary parses of priests, shamans and paladins.
  - The fit solves each parse for the +healing that reproduces it. If three families of one class agree on one value, the coefficient rules for that class are confirmed (the method of v0.14.7, `docs/TOOLS.md` §3).
  - This is the only way to verify a class the author does not play without asking a guildmate.
- **In game (a guildmate, per `docs/PLAN.md:430`):** `/md verify`, `/md regentest` (class regen talents: Meditation, Unrelenting Storm, Illumination) and `/md calibrate` after a dungeon.
- The engine and solver work of section 1.3 is shared: `Engine/SimModel.lua` and `Engine/SimSolver.lua` load on both lines.

---

## 4. Druid-only gates to replace with "the kit can price this player's heals"

| file:line | gate |
|---|---|
| `Core.lua:301` | `MD.player.isDruid` defined |
| `UI/Dashboard_Review.lua:610, 662, 694, 701, 807, 841-845, 863` | Coach / coachrun / validate-on-select / "Coaching is Druid-only in v1." |
| `UI/ReplayWindow.lua:1755, 1980, 2388` | Coach offered, coach-on-open, practice |
| `UI/PracticePanel.lua:523-528` | Practice Start |
| `Engine/ReviewCommands.lua:168` | `/coachrun` |
| `UI/SimWindow.lua:75, 262` | Simulate |
| `UI/Dashboard.lua:58, 142, 287` | TBC Spells group |
| `UI/SpellTooltip.lua:57`, `UI/Advisor.lua:58, 85`, `UI/Summary.lua:496`, `Diagnostics_TBC.lua:227`, `Core_TBC.lua:99` | TBC druid surfaces |

On Forever the right test is "`RM:SpellKit()` holds at least one priced heal entry". The kit is already built from the live book, and `PR.policy.kitIsLive` (`Engine/Practice.lua`, T59) is the same idea for Practice. On TBC, `isDruid` stays until a class's kit exists.

---

## 5. Phased path, highest value first

| # | what | files | verify offline | verify in game |
|---|---|---|---|---|
| **P0** | **Engine correctness.** (a) The solver respects cooldowns (`SM.Ready` in `Solver:Best` and rule 8; the engine refuses or traces a plan cast on cooldown). (b) `SPELL_CD` from a kit `cooldown` field. (c) Make `channel` land or refuse it explicitly. (d) Parse misreads: decimals, "N additional damage", "your next X" refusal. | `SimSolver.lua:332-400, 440-500`; `SimModel.lua:111, 578-617, 1010-1030`; `Kit.lua:46-77`; `Parse.lua:15, 197-206, 323-335` | `solvercheck` (Swiftmend on cooldown never picked; `cdtest2.lua` as a case), `restcheck`, `parsecheck` fixture rows from talentsforever (CC BY, attributed) for Mana Burn, Execute and Light's Vigil. Re-run the strategies report on the author's recordings: cooldown-correct Swiftmend changes the solver's numbers, so record it in DECISIONS. | none |
| **P1** | **Forever reading truth for every class.** `Parse.Targets(text)` (pure, refuse-unknown): party / "target and their party" / "the caster" / "target and the caster" / jumps + falloff / charges / "below N% Health" / "cannot be X again for N sec". Read the cooldown from the tooltip line's right text (shape unverified on Forever; probe first). `Book` entries carry `targets`, `cooldown`, `lockout`; `IntervalFor` uses `max(cast, GCD, cooldown)`. Words: "x up to 5 targets", "every 10 s", "1.75x if 3 are hurt" as a stated upper bound, never silently multiplied. The damage half shown for either-or spells. A per-class coverage report in `tools/` over the cached `data.json`. | `Spells/Parse.lua`, `Spells/Book.lua:159-184, 360-400`, `Spells/Words.lua`, `UI/SpellTip_Forever.lua`, `UI/SpellsPane_Forever.lua`, `Client/Probe.lua` (`== shapes`: one cooldown spell's tooltip lines) | `parsecheck` / `bookcheck` / `tipcheck` with priest, shaman and paladin books in `wowstub` (from talentsforever level 60 texts); a coverage count asserted in `tools/data/expected-counts.json` | Probe on a priest, shaman or paladin alt (level 10+): cooldown line shape, Weakened Soul aura readable on party; `/st measure` on self (Renew and Riptide tick period, Flash Heal range); damage meter per-spell rows (`docs/probe/1.60.1_70124.md`: "HT R2 3326, Rejuv R1 2528") for PoH and Chain Heal total / casts against the 5x and 1.75x upper bounds. |
| **P2** | **A generic Forever kit.** Families from the book by shape, not by name (`FAMILY_KEY` derived; `Stream_Forever.lua:28-33` reads the same derivation). HoT slots by family. New types `group`, `chain`, `selfAndTarget`; `channel` landing; Wild Growth in. The solver over the kit's families with group sums. Gates in section 4 switched to "kit prices a heal". The threshold rules stay druid-only, and a non-druid's strategy set is the solver's. | `Kit_Forever.lua:21-90, 111-167`, `Kit.lua`, `SimModel.lua:91-130, 497-600`, `SimSolver.lua:56-90, 279-400`, `Scenario_Forever.lua:73-77, 136-330`, `Practice.lua` (family names 283-347), the UI gates | `kitcheck` (a priest book becomes a valid kit), `solvercheck` properties (PoH beats Greater Heal only when 3+ are hurt; Chain Heal jump falloff; the causality test unchanged), `scenariocheck` (group claims), `gatecheck`, `practiceforever` with a priest kit, `importcheck` fixture rebuilt | One recorded pull from a non-druid healer through the eight gates (gate 8 "heals attributed" is the one that tells whether group attribution is right) |
| **P3** | **Absorbs.** Shield state, Weakened Soul lockout, the recorder storing absorbed amounts. | `SimModel.lua:468-482`, `FightRecorder.lua:344-372` (TBC: keep the CLEU `absorbed` field), `Recorder_Forever.lua` | `reccheck` (partial absorb recorded), `solvercheck` (shield before a predicted hit) | **Probe first:** what `UNIT_COMBAT` reports for a hit into a shield on Forever (action and amount), whether `UnitGetTotalAbsorbs` is secret. Without an answer a PW:S replay is not trustworthy, and the gates must say so. |
| **P4** | **Mana returns and sources.** EV refunds (Illumination, Water Shield, Clearcasting) on the cost; an aura-driven source table (Innervate, Mana Tide, Mana Spring, Blessing of Wisdom) with rates from the spell's own text, for the Forever modelled pool and TBC `ManaCooldowns` stubs. | `Engine/ManaModel.lua`, `Engine/ManaPool_Forever.lua`, `Engine/ManaCooldowns.lua:47-53`, `Spells/Parse.lua` (a "restores N mana every P sec" shape) | `clockcheck`, `restcheck` | Forever: `UnitPower` is always secret, so a refund **cannot be measured directly**. It stays "assumed" until a long-fight drift test against the bar (`MD.API.DrawUnitPower` draws the real pool; the eye compares). TBC: `/md regentest`. |
| **P5** | **TBC other classes.** Tooltip-read bases + a per-class VERIFY rule table; kit through the same `Kit.Check`; WCL fit per class. | new `Spells/Book_TBC.lua` (or a TBC reader feeding `Spells/Book.lua`'s shape), `Engine/RankMath.lua` rules split by shape, `tools/wclconvert.py` / `wclcheckkit.lua` class argument | WCL fits on public parses; `verifycheck` golden transcripts unchanged for the druid | `/md verify` + `/md calibrate` by someone of that class |
| **P6** | **Non-healer extras.** Either-or damage halves, caster mana sources, seed by role. | `Spells/Tabs.lua:170-176`, `Engine/ManaCooldowns.lua` | `tabscheck`, `parsecheck` | none required |

### Why this order

- **P0** fixes a correctness bug the author's own coach already has (Swiftmend), and nothing after it is sound without it.
- **P1** costs no engine work and makes the tooltip and Spells pane, which every class already sees on Forever, stop overstating cooldown spells and understating group heals. It also produces the probe questions P2 and P3 need.
- **P2** is the step that lets a priest, shaman or paladin be coached at all, using the solver the author already trusts most.
- **P3** is the hardest, because the data source may not exist on Forever, so it waits for the probe.
- **P5** is the largest build and the least verifiable for the author personally. The WCL fit is what makes it honest.

### What can never be verified offline

- Forever's cooldown line shape.
- Tick periods (Renew, Riptide, Wild Growth's curve).
- Whether `UNIT_COMBAT` shows absorbs.
- Chain Heal's jump-target rule.
- Refund procs on a secret mana bar.
- Any talent that changes a value without changing the text (`Book.adjust`, `Spells/Book.lua`, the Q6 seam; e.g. Blessing of Light, which is target-side).

Everything else (parse shapes, kit validity, engine properties, the causality invariant, attribution of synthetic group heals, TBC coefficient rules against WCL logs) is testable under `tools/check.sh` with fixtures built from the CC BY talentsforever export and public logs.
