# T7b — the shapes gate: the book reader against what build 70009 returned

Status: **done -- lead-accepted 2026-09-28** (see Review). M2 close-out (`docs/ROADMAP-FOREVER.md` §2 M2, the planner's ruling "the first
probe report carrying `== shapes` is a gate for `beta.1`"). Evidence: `docs/probe/1.60.1_70009-m2.md`.

## Goal

`Spells/Book.lua`, `Spells/Parse.lua` and the stub's Forever spellbook agree with the return shapes
build 70009 actually handed back, line by line, so the Spellbook pane, the tooltip block, the clock
and `/st measure` stand on observed shapes rather than retail documentation. Three things change
because the evidence disagrees with what was built: a spell with no cost returns **nothing** from
`GetSpellPowerCost` (read as free, not unknown); a description can carry the client's unexpanded
grammar escape `|4singular:plural;` (expanded by `Parse.Clean`, so no pipe survives into any
rendered string or export); and a reactive "damage to attackers" clause (Thorns) is not a cast's
damage. The book also keeps each row's `isPassive` so the pane (T10c) can leave passives out. For
the author's `beta.1` gate and every M2 consumer.

## Facts

The lead's line-by-line check of `== shapes` (m2 file lines 247-300) against the reader. "agrees"
means no code change; each disagreement is a Files item below.

| shape observed (m2 line) | reader | verdict |
|---|---|---|
| `GetNumSpellBookSkillLines() = 3` (248); lines 1-3 carry `itemIndexOffset` 0/8/14, `numSpellBookItems` 8/6/8, `isGuild=false` (249-251) | `Book:Enumerate` trusts the lines when every one answers numeric bounds; reads slots 1..22 | agrees. The export lists exactly 22 spells (m2 36-193), the three lines' total |
| rows run on to `skillLineIndex` 4-8 (First Aid, Alchemy, Herbalism, Cooking, Fishing, 274-285), past the 3 skill lines | not read on the skill-line path (bounded by the lines); read on the 1..500 fallback walk | agrees for the path the client takes; the walk fallback is untouched (it only runs when the lines do not answer) |
| row = `{actionID, iconID, isOffSpec, isPassive, itemType=1, name, skillLineIndex, spellID, subName}`; `skillLineIndex` **absent** on General's rows (252-259) | reads `spellID`, `itemType`, `iconID` | agrees; **new:** `isPassive` is kept as `entry.passive` (Files) |
| `itemType=1` on every row, no other value seen (252-285) | skips Flyout / PetAction by `Enum.SpellBookItemType`, FutureSpell's constant for known-ness | agrees; the other enum values are still unobserved (stub says so already) |
| `GetSpellInfo`: `castTime` in **milliseconds** (1500, 2000, 1400, 500, 10000), `minRange`, `maxRange`, `name`, `iconID`, `originalIconID`, `spellID` (252-285) | `info.castTime / 1000` | agrees (War Stomp exports `0.5 sec cast`, m2 191) |
| `GetSpellPowerCost` with a cost: a list of one row `{cost, costPerSec, costPercent, hasRequiredAura, minCost, name=MANA, requiredAuraID, type=0}` (260-273) | mana row by `type == 0`; `cost > 0` -> amount, `costPercent > 0` -> percent | agrees |
| `GetSpellPowerCost` for Attack, Cultivation, War Stomp, the passives, the professions: **`cost=nothing`** -- the probe's `Show` prints `nothing` only when the call returned **no values at all** (`Client/Probe.lua` `Show`, "never confused with a single nil return") (252-259, 274-285) | an empty list `{}` -> free; anything else -> tooltip cost line -> `absent` ("unknown" in the export, m2 113, 120, 127...) | **disagrees.** No row with a cost ever returned nothing; every no-cost spell did (12 of 12 in the book). The stub's `noCost` returns `{}`, a shape never seen. Read "no return, no reason" as free; the stub returns nothing |
| `GetSpellLevelLearned` 0 for Attack, the racials, Armor Proficiency, Languages (252-258) | `entry.level = 0` | agrees (a number); the pane's rendering of 0 is T10c's |
| `GetBaseSpell(id) = id` for **every rank** (Healing Touch R2 `base=5186`, 261) | not read by Book (families are grouped by name) | agrees; recorded here so nothing starts grouping by base spell |
| `IsSpellBookItemLowRank` true on every rank below the highest known (260, 262, 264, 267, 272) and on one profession row (285) | `entry.lowRank`, informational | agrees |
| tooltip data: `lines[i].leftText` / `rightText`, strings (286-295: two passives only) | `TooltipCastInfo` / `TooltipCostInfo` read `leftText` by pattern, as fallbacks after `GetSpellInfo` / `GetSpellPowerCost` | agrees for what was seen. **The heal spells' tooltip lines were not dumped** -- the probe picked Endurance and Plainsrunning because its heal/damage test is a substring match ("Health", "Taking damage"); T13b fixes the probe. UNKNOWN whether a heal's lines carry the cost/cast text; the fallbacks stay fallbacks |
| crit per school `GetSpellCritChance(1..7)` plain (296); `GetSpellBonusHealing()` plain out of combat (297) | read by the tooltip / measure | agrees |
| Mark of the Wild's description: `... for 1 |4hour:hrs;.` (m2 154, 161) | `Parse.Clean` strips colour, texture and `|n` only | **disagrees.** The client's grammar escape is `|4<singular>:<plural>;`, chosen by the number before it. It reaches `entry.desc`, the export and any tooltip line that prints the text |
| the copy box: the probe writes a tooltip line as `left || right` (`Client/Probe.lua` `TooltipLines`) and the author's paste reads `Endurance | ` (m2 287) | -- | the copy box **renders `||` as a single `|`** when copied. An escaped pipe does not survive a paste; the only safe export is one with no pipe in it at all. `tools/refcheck.py` already reads either form (its `replace("||", "|")`) |
| Thorns R1: `Thorns sprout from the friendly target causing 4 Nature damage to attackers when hit. Lasts 10 min.` (m2 91) | `DAMAGE_SINGLE` reads it as a 4-damage cast; the pane shows `Thorns R1 6 35 4 0.11 2.7 inst 10` (m2 31) | **disagrees** with what the pane is for: a reactive aura's per-hit damage is not the cast's value. Refused (Files) |
| Nature's Grasp: `The next 1 melee attack that strikes the caster will afflict the attacker with Entangling Roots (Rank 1). ...` (m2 168) | no amount -> kindless (Other) | agrees |

- Q6 ruling (`FOREVER-PLAN.md` §6 Q6): no talent scan; `Book.adjust` stays empty. Not touched here.
- `|4` semantics: the client's `|4singular:plural;` picks the singular after the number 1 and the
  plural otherwise (WoW's UI escape; its only observed use here is `1 |4hour:hrs;`). With no number
  before it, the plural is taken (UNKNOWN what the client does; the plural is the safe reading for a
  count we cannot see).

## Files

| file | change | role |
|---|---|---|
| `Spells/Parse.lua` | `Parse.Clean` expands `|4a:b;` (number before it == 1 -> `a`, else `b`) before the other strips; `Parse.Description` refuses a damage clause immediately followed by `to attackers` (the reactive aura shape) | the text reader |
| `Spells/Book.lua` | `ResolveCost`: a call that returned no value and no reason (`list == nil and listReason == nil`) is `{free = true}, "free"`, exactly like an empty list; `BuildEntry` keeps `entry.passive = (row.isPassive == true)` and `entry.skillLine = row.skillLineIndex` (a plain number or nil) | the reader |
| `tools/wowstub.lua` | forever profile: `noCost` spells' `GetSpellPowerCost` returns **nothing** (`return` with no values); `S.AddSpell` opts gain `passive` (row `isPassive`); the fixed rows keep `isPassive = false`. A comment on each changed stub function naming the m2 line it now follows | the stub |
| `tools/data/parse-fixture.lua` | three entries sourced `m2`: Mark of the Wild R1 and R2 (`none = true`, and their `Clean` output has no `|`), Thorns R1 (`none = true`) | fixture |
| `tools/parsecheck.lua` | one new assertion (below); the fixture's new rows ride the existing ones | suite |
| `tools/bookcheck.lua` | one new assertion (below) | suite |

## Rules

- No client call outside `Client/`; Book reads only what `MD.API` hands back (copies). No arithmetic
  on a client value the adapter has not cleared.
- ASCII-only rendered strings, no bare `|` -- after this task no description Book holds contains a
  `|` that `Clean` could have removed.
- No new global, no library, the multi-return trap (`gsub` in parentheses when used as a value).
- Tests first: write the two new assertions, run them, paste the failing run, then implement.
- Never change an existing assertion to make it pass. Assertion "cost is an amount, a percentage
  of base mana, free or unknown" in bookcheck must still pass with the stub's `noCost` returning
  nothing (that is the point: nothing is free).
- Comments say why (cite the m2 line), not what.
- **Git:** no `git add`, `stash`, `checkout -- <path>`, `reset`, commit. Do not edit `CLAUDE.md` or
  any `docs/` file except this task's Report.

## Acceptance

1. `bash tools/run.sh tools/parsecheck.lua` ends `11 ok, 0 failed`; the new assertion, verbatim:
   "the client's grammar escape is expanded and a reactive damage clause is not a cast's damage"
   -- `Parse.Clean("Increases the friendly target's armor by 34 for 1 |4hour:hrs;.")` is
   `"Increases the friendly target's armor by 34 for 1 hour."`, `"... for 2 |4hour:hrs;."` ends
   `"for 2 hrs."`, `"|4hour:hrs;"` with no number before it reads `hrs`, and
   `Parse.Description` of Thorns R1's text (m2 91) is nil.
2. `bash tools/run.sh tools/bookcheck.lua` ends `15 ok, 0 failed`; the new assertion, verbatim:
   "a spell whose cost call returns nothing is free, and a passive row is marked passive" -- a spell
   added with `noCost` reads `costState == "free"`, one added with `passive = true` reads
   `entry.passive == true`, a fixed row reads `entry.passive == false`.
3. Every other suite at its baseline count (the lead's baseline 2026-09-28: tipcheck 14, spellsui
   12, clockcheck 13, measurecheck 9, probecheck 66, forevercheck 13, modulecheck 12, the TBC
   sixteen unchanged; adaptercheck 19/15, corecheck 10/8, svcheck 6/1, consolecheck 11/1).
4. `python3 tools/apicheck.py` 0 findings, `--selftest` 7 of 7; `python3 tools/refcheck.py --selftest` ok.
5. `luac -p` clean on every file touched.
6. Paste into the Report: the failing run of the two new assertions; parsecheck and bookcheck in
   full; every other tail; apicheck; luac; `git status --short`.

## Out of scope

- The pane (T10c), the measure (T12b), the clock (T11b), the probe (T13b) -- even though the probe's
  heal/damage pick is wrong, and the pane still shows Thorns until this lands.
- The 1..500 fallback walk; `Book.adjust`; `UI/SpellTip_Forever.lua`.
- `CLAUDE.md`, every `docs/` file except this Report. Commits.

## Report

Tests written first, run to confirm failure, then made to pass.

**Failing run (before implementation):**
```
parsecheck:
a description with no amount reads nil                                   FAIL - m2 Thorns R1: {}
the client's grammar escape is expanded and a reactive damage clause is not a cast's damage FAIL - motw1="Increases the friendly target's armor by 34 for 1 |4hour:hrs;." motw2="Increases the friendly target's armor by 88 for 2 |4hour:hrs;." bare="|4hour:hrs;" thorns={}
9 ok, 2 failed

bookcheck:
a spell whose cost call returns nothing is free, and a passive row is marked passive FAIL - free.costState=free passive.passive=nil fixed.passive=nil
14 ok, 1 failed
```

**Files changed:**

- `Spells/Parse.lua` — added `ExpandGrammar` (a private local, run first inside `Parse.Clean`,
  before the colour/texture strips): `(%d+)(%s+)|4(.-):(.-);` picks the singular when the captured
  number is exactly `1`, else the plural; a second, narrower `gsub` on the remaining `|4a:b;`
  (nothing captured before it) always takes the plural, per the Facts' "UNKNOWN, plural is the safe
  reading" ruling. In `Parse.Description`'s `DAMAGE_SINGLE` branch, a match immediately followed by
  `to attackers` (word-bounded with `%f[%A]`) is refused rather than read as a direct amount — this
  is Thorns' reactive-aura shape, not a cast's own damage; no other damage/heal pattern was touched
  since Facts names only this one shape.
- `Spells/Book.lua` — `ResolveCost` now treats `list == nil and listReason == nil` (a call that
  returned no value and no reason at all) exactly like an empty list: `{free = true}, "free"`. This
  sits before the existing `type(list) == "table"` branch so it never interferes with the "absent"
  case (function missing entirely goes through `Call`'s own `nil, "absent"`, which is a non-nil
  reason and still falls through to the tooltip fallback as before). `BuildEntry` now sets
  `entry.passive = (row.isPassive == true)` and `entry.skillLine = row.skillLineIndex` (kept only
  when it is a plain number, nil otherwise) right after the id/slot are set.
- `tools/wowstub.lua` — forever profile: added a `SPELL_PASSIVE` table (default false); `S.AddSpell`
  now records `opts.passive == true` into it; `GetSpellBookItemInfo`'s row now reads
  `isPassive = SPELL_PASSIVE[id] == true` instead of the hard-coded `false` (so the four fixed slots,
  never passed through `AddSpell`, still answer `false` by falling through the table's own default).
  `GetSpellPowerCost` for a `noCost` spell now does `return` with no values at all instead of
  `return {}` (m2 lines 252-259/274-285: every no-cost spell in the real book returned nothing, a
  shape the stub never produced before). Both changes carry a comment citing the m2 lines. Re-read
  the file immediately before each edit; my two touch points (`GetSpellBookItemInfo`'s table literal
  and `GetSpellPowerCost`) do not overlap the concurrent T12b/T11b/T13b edits visible in `git status`
  (`Engine/ManaModel.lua`, `UI/Clock_Forever.lua`, `tools/clockcheck.lua`).
- `tools/data/parse-fixture.lua` — converted the existing `tf Druid|Thorns|Rank 1` entry (same text,
  m2 line 91) from `loose = true` to `src = "m2 Thorns R1"`, `none = true`; added `m2 Mark of the
  Wild R1` (m2 line 154) and `m2 Mark of the Wild R2` (m2 line 161), both `none = true`, their raw
  text carrying the unexpanded `|4hour:hrs;` escape. These ride the existing fixture-driven checks
  1-4 (checks 2 and 4 now exercise them; check 1/3 pass vacuously since `none = true` entries produce
  no heal/damage to compare).
- `tools/parsecheck.lua` — added check 11 (inserted ahead of the old check 10, so the new one shows
  up before the TOC-order check in the printed order — no existing check's body, text or fixture
  loop was changed), the verbatim assertion from Acceptance item 1, using literal text (not routed
  through the fixture) exactly as the acceptance line spells it out, plus the Thorns m2-line-91 text
  for the `Parse.Description(...) == nil` half.
- `tools/bookcheck.lua` — added `passive = true` to the existing `90040 PassiveSpell` fixture's opts
  (it was already in the file for a different, unrelated reason — item 2/9's "no kind" case — and
  needed a passive marker anyway); added check 15, the verbatim assertion from Acceptance item 2,
  reading `90030 FreeSpell`'s `costState`, `90040`'s `.passive`, and `5185` (a T7a fixed slot,
  never routed through `AddSpell`)'s `.passive == false`.

**parsecheck.lua, full (after):** 11 ok, 0 failed (loose entries unchanged: Penance, Prayer of
Mending, Consecration, Healing Stream Totem, Drain Life — none of these are damage-single shapes
followed by "to attackers", so the new refusal did not touch them).

**bookcheck.lua, full (after):** 15 ok, 0 failed.

**Every other suite** (`bash tools/run.sh tools/<name>.lua`, forever profile unless noted):
```
simcheck      PASS (measured mean 1.3% max 2.8% at 23.0s)
reccheck      54 ok, 0 failed
replaycheck   80 ok, 0 failed
replayui      98 ok, 0 failed
runcheck      78 ok, 0 failed
reviewui      44 ok, 0 failed
navui         25 ok, 0 failed
dashui        56 ok, 0 failed
regencheck    27 ok, 0 failed
simwindow     8 ok, 0 failed
solvercheck   70 ok, 0 failed
timeline      27 ok, 0 failed
spelltip      48 ok, 0 failed
practice      74 ok, 0 failed
practiceui    49 ok, 0 failed
migrate       7 ok, 0 failed
probecheck    66 ok, 0 failed
forevercheck  13 ok, 0 failed
modulecheck   12 ok, 0 failed
tipcheck      14 ok, 0 failed
clockcheck    15 ok, 0 failed   (baseline noted 13 -- T11b is concurrently adding clock checks;
                                  not a regression from this task, which touches none of the clock
                                  or UI files)
spellsui      12 ok, 0 failed

adaptercheck/forever 19 ok, 0 failed
adaptercheck/tbc     15 ok, 0 failed
corecheck/forever    10 ok, 0 failed
corecheck/tbc         8 ok, 0 failed
svcheck/forever       6 ok, 0 failed
svcheck/tbc           1 ok, 0 failed
consolecheck/forever 11 ok, 0 failed
consolecheck/tbc      1 ok, 0 failed
```
All match the lead's 2026-09-28 baseline exactly except `clockcheck` (15 vs baseline 13), which is
explained above and was re-run once as instructed; it was already 15 before any of my edits (T11b's
concurrent work), and this task does not touch `Engine/ManaModel.lua`, `UI/Clock_Forever.lua` or
`tools/clockcheck.lua`.

**apicheck / refcheck:**
```
apicheck: 8 Forever TOCs, 21 files, 40 distinct globals, 0 findings (baseline 69893)
selftest: 7 of 7 findings as expected
refcheck --selftest: ok
```

**luac -p**, every file touched: `Spells/Book.lua`, `Spells/Parse.lua`, `tools/wowstub.lua`,
`tools/data/parse-fixture.lua`, `tools/parsecheck.lua`, `tools/bookcheck.lua` — all clean.

**git status --short** (at hand-off):
```
 M Spells/Book.lua
 M Spells/Parse.lua
 M tools/bookcheck.lua
 M tools/data/parse-fixture.lua
 M tools/parsecheck.lua
 M tools/wowstub.lua
?? docs/tasks/T10c-pane-layout.md
?? docs/tasks/T12b-measure-attribution.md
?? docs/tasks/T13b-probe-m3-items.md
?? docs/tasks/T13c-module-plumbing.md
?? docs/tasks/T7b-shapes-gate.md
```
(the other `?? docs/tasks/*` and `M Engine/ManaModel.lua` / `M UI/Clock_Forever.lua` /
`M tools/clockcheck.lua` entries seen mid-session belong to the concurrent T10c/T11b/T12b/T13b/T13c
implementers, not to this task.)

Nothing skipped; all Acceptance items done. No question — the Facts table and Files list were
unambiguous, and the two ambiguous points it anticipated (plural default with no preceding number;
narrowing the refusal to `DAMAGE_SINGLE` only) were already resolved in the task's own text.

## Review (lead, 2026-09-28)

Read the diff whole; reran parsecheck `11 ok`, bookcheck `15 ok`, tipcheck 14, spellsui 12,
refcheck selftest ok. The no-return cost reads free (`nil` list with no reason); the empty-list path
stays and is now untested, which is harmless. `ExpandGrammar` runs before every other strip; the
reactive refusal is scoped to the single-amount damage shape, which is the only one Thorns matches.
The `passive = true` added to bookcheck's existing 90040 fixture only adds a field its earlier
assertions do not read. The line-by-line shapes check in Facts is the record for the `beta.1` gate.
Accepted.
