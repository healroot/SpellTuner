# T7a — the probe dumps the shapes M2 reads

Status: **done -- lead-accepted 2026-09-28, with one amendment by the lead** (see the Review at the end). M2 (`docs/ROADMAP-FOREVER.md` §2). Not on the roadmap's task line: the
lead split it off T7 because every M2 module reads return *shapes* the probe has only ever checked
for presence. It is the "run the probe for X" task the lead rules require before T7-T11 rest on
those shapes; they are built against the retail documentation meanwhile and say so.

## Goal

`/st probe` gains a `== shapes` section that prints, whole, every client return M2's spellbook
reader, tooltip, dashboard and clock will read: the spellbook's skill lines, each spell's book row,
`C_Spell.GetSpellInfo`, `C_Spell.GetSpellPowerCost`, `C_Spell.GetSpellLevelLearned`,
`C_Spell.GetBaseSpell`, the low-rank flag, the tooltip data lines of one heal and one damage
spell, crit chance per school; the same few read again in the combat snapshot; and a count of
`UNIT_SPELLCAST_SUCCEEDED` with its spell id readable or secret and the cost read at the cast. The
stub learns those shapes (retail 12.x's documented ones, marked unverified) so T7 onwards can be
tested against them. For the author's next probe run (M2's `docs/TESTING.md` section, T12) and for
the lead, who checks T7-T11's assumptions against the first report that carries this section.

## Facts

- Present on build 70009 (first report, `== functions`): `C_Spell.GetSpellInfo`,
  `C_Spell.GetSpellPowerCost`, `C_Spell.GetSpellDescription`, `C_Spell.GetSpellSubtext`,
  `C_Spell.GetSpellLevelLearned`, `C_Spell.GetSpellName`, `C_Spell.GetBaseSpell`,
  `C_SpellBook.GetNumSpellBookSkillLines`, `C_SpellBook.GetSpellBookSkillLineInfo`,
  `C_SpellBook.GetSpellBookItemInfo`, `C_TooltipInfo`, `TooltipDataProcessor.AddTooltipPostCall`,
  `GetSpellCritChance`, `GetSpellBonusHealing`, `Enum.SpellBookSpellBank`.
- `C_SpellBook.IsSpellBookItemLowRank` and `C_TooltipInfo.GetSpellByID` are in the 69893 baseline
  (`tools/data/forever_api.json`, namespaces); presence on 70009 UNKNOWN -- this task reports it.
- Only these shapes are observed: `C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)`
  answers a table with a readable `spellID` for slots 1-500 (first report, `slots 1-500: 24 with a
  spell`); `GetSpellName` / `GetSpellSubtext` / `GetSpellDescription` answer strings ("Healing
  Touch", "Rank 1", the description). **Every other return shape is UNKNOWN on Forever** -- the
  retail 12.x documentation is the only source, which is why this task exists.
- In combat `ShouldUnitStatsBeSecret` and `ShouldCooldownsBeSecret` turn true (seventh report);
  whether a spell's description, info, cost or crit chance reads secret in combat is UNKNOWN.
- `UNIT_SPELLCAST_SUCCEEDED` registers (first report, `== events`); whether its spell id is
  readable in combat is UNKNOWN (only `UNIT_SPELLCAST_SENT`'s target was counted: 26 of 26
  readable, seventh report).
- The spellbook hides lower ranks unless "show all ranks" is on (`FOREVER-PLAN.md` §1.1, Wowhead
  news 383050); whether the book API still lists them with the option off is UNKNOWN -- the
  low-rank flag and a run with the option off and on answer it.
- The probe's own rules (`CLAUDE.md` file table, `Client/Probe.lua`): every check under `pcall`,
  every result a string, no arithmetic on a client return, `IsSecret` before anything but storing,
  every client string through `Esc`; `Describe(v, depth)` renders a table whole.

## Files

| file | change | role |
|---|---|---|
| `Client/Probe.lua` | a `ShapesLines()` section, `== shapes`, printed between `== talents` and `== readings now`; its combat half added to `TakeCombatSnapshot`; a `UNIT_SPELLCAST_SUCCEEDED` counter beside the existing `UNIT_SPELLCAST_SENT` one | the probe |
| `tools/wowstub.lua` | the forever profile answers the shapes below; `S.AddSpell` takes an optional fifth `opts` | the stub |
| `tools/probecheck.lua` | the eight assertions below | the probe's suite |

### `== shapes` (exact line forms; every value through `Describe`/`Fmt`/`Esc`)

1. `skill lines: <Show of C_SpellBook.GetNumSpellBookSkillLines()>`, then for i = 1 .. that number
   **if it is a plain number between 1 and 20** (else only the first line): `skill line <i> = <Describe(GetSpellBookSkillLineInfo(i), 1)>`.
2. For every spell the walk found (the walk now also remembers each spell's slot), in walk order:
   `book <id> <name> <rank>: info=<Describe(GetSpellInfo(id), 1)>; cost=<Describe(GetSpellPowerCost(id), 2)>; learned=<...>; base=<...>; lowrank=<Show of IsSpellBookItemLowRank(slot, bank)>; row=<Describe(GetSpellBookItemInfo(slot, bank), 1)>`
   -- `<absent>` / `<error: ...>` / `<secret>` as the probe renders them anywhere else.
   (**Amended by the lead after the Report:** the line was first specified as `spell <id> ...`, which
   put a non-healing spell's `spell <id>` into every report and broke the existing assertion "a spell
   that does not heal is not dumped". The leading token is `book`.)
3. For the first spell whose description contains "heal" and the first whose description contains
   "damage" (case-insensitive; each at most once): `tooltip <id> = <n> lines`, then one line per
   data line, `  line <k>: <leftText> | <rightText>` with both through `Esc` (so a pipe in the text
   reads `||`; the separator is ` || `, written as the escaped pipe -- no bare `|` anywhere), from
   `C_TooltipInfo.GetSpellByID(id)`'s `lines`. If `GetSpellByID` is absent: `tooltip = <absent>`.
4. `crit: ` then `School=<Show of GetSpellCritChance(school)>` for schools 1-7 (1 Physical, 2 Holy,
   3 Fire, 4 Nature, 5 Frost, 6 Shadow, 7 Arcane), space-separated.
5. `bonus healing: <Show of GetSpellBonusHealing()>`.
6. `in combat: none this session` or, from the snapshot, `in combat (<stamp>):` then for the first
   healing spell: `  desc=<...>; info=<...>; cost=<...>; crit4=<...>; bonus healing=<...>`.
7. `UNIT_SPELLCAST_SUCCEEDED <phase> n=<n> readable=<r> secret=<s> sample=<first readable id>; cost at cast readable=<r> secret=<s> absent=<a>` -- one line per phase seen (`ooc`, `combat`), or `UNIT_SPELLCAST_SUCCEEDED: none this session`.
   The handler reads the event's third argument (the spell id), counts it by `IsSecret`, and for a
   readable id calls `GetSpellPowerCost(id)` under `pcall` and counts the result the same way. It
   is registered with the other listeners and only for `"player"` casts (first argument `== "player"`
   after `IsSecret` says the unit is not secret).

### The stub (forever profile only; every addition commented "retail 12.x documented shape, NOT observed on Forever -- the probe's == shapes checks it")

- `C_Spell.GetSpellInfo(id)` -> `{ name, iconID = 136041, originalIconID = 136041, castTime = <ms>, minRange = 0, maxRange = 40, spellID = id }` for a known id, nil otherwise.
- `C_Spell.GetSpellPowerCost(id)` -> `{ { type = 0, name = "MANA", cost = c, minCost = c, costPercent = p or 0, costPerSec = 0, requiredAuraID = 0, hasRequiredAura = false } }`, or `{}` for a spell with no cost.
- `C_Spell.GetSpellLevelLearned(id)` -> the level; `C_Spell.GetBaseSpell(id)` -> the family's rank-1 id.
- `C_SpellBook.GetNumSpellBookSkillLines()` -> 2; `GetSpellBookSkillLineInfo(1)` ->
  `{ name = "General", iconID = 1, itemIndexOffset = 0, numSpellBookItems = 0, isGuild = false, shouldHide = false }`;
  `(2)` -> `{ name = "Druid", ..., itemIndexOffset = 0, numSpellBookItems = <highest used slot> }`.
- `C_SpellBook.GetSpellBookItemInfo(slot, bank)` keeps slot 4's raising row and adds
  `name`, `subName`, `itemType = 1`, `isPassive = false`, `isOffSpec = false`, `skillLineIndex = 2`,
  `actionID = spellID`, `iconID` to the others.
- `C_SpellBook.IsSpellBookItemLowRank(slot, bank)` -> false unless `opts.lowRank`.
- `C_TooltipInfo.GetSpellByID(id)` -> `{ type = 1, id = id, lines = { {leftText = name, rightText = rank}, {leftText = "<cost> Mana", rightText = "40 yd range"}, {leftText = "<cast text>", rightText = ""}, {leftText = <description>} } }`, where the cast text is `Instant` for 0 ms, else `"<s> sec cast"`.
- The fixed spells: 774 Rejuvenation R1 (0 ms, 25 mana, level 4, base 774), 1058 Rejuvenation R2
  (0 ms, 40 mana, level 10, base 774), 5185 Healing Touch R1 (1500 ms, 25 mana, level 1, base 5185),
  5176 Wrath R1 (1500 ms, 20 mana, level 1, base 5176). These are stand-ins, not client values; say
  so in the comment.
- `S.AddSpell(id, name, rank, descFn, opts)`: `opts` (optional) `{ cast = ms, cost = n, costPercent = n, level = n, base = id, lowRank = bool, noCost = bool }`.
- `GetSpellCritChance(school)` -> `S.crit[school]` or 5, **secret in combat** (the stub's guess from
  `ShouldUnitStatsBeSecret`, commented as a guess).

## Rules

- `Client/Probe.lua` is the one file that sees raw client values; everything else stands:
  `pcall` round every call, `IsSecret` before anything but storing, no arithmetic / comparison /
  `#` / table key on a client return, every client string through `Esc`, the report ASCII with no
  bare `|`.
- The report stays one copy box; nothing here writes anything new to SavedVariables.
- Registering `UNIT_SPELLCAST_SUCCEEDED` is allowed (first report); nothing registers
  `COMBAT_LOG_EVENT_UNFILTERED`.
- The multi-return trap: never `a and f() or b`.
- Tests first: write the eight assertions, run `probecheck` and see them fail, then write the
  code. Say which failed and how.
- **An existing probecheck assertion is never edited.** If one fails because of the new section or
  the stub's new answers, stop and report which and why.
- Comments say why, not what.
- **Git.** No `git add`, `git stash`, `git checkout -- <path>`, `git reset` or commit. Do not open
  `CLAUDE.md` or any `docs/` file except this task's Report section for writing.

## Acceptance

1. `bash tools/run.sh tools/probecheck.lua` ends `66 ok, 0 failed`. The eight new assertions,
   names verbatim:
   1. "the shapes section sits between the talents and the readings"
   2. "the shapes section lists every skill line whole"
   3. "every spell in the book has one shapes line: info, cost, learned, base, low rank, row"
      (all four fixed spells, and a spell added with `S.AddSpell(..., { lowRank = true })` reads `lowrank=true`)
   4. "a spell's cost is rendered two levels deep" (`cost={1={cost=25, costPerSec=0, costPercent=0, hasRequiredAura=false, minCost=25, name=MANA, requiredAuraID=0, type=0}}` for 774, or the exact rendering `Describe` gives -- paste it)
   5. "the first heal and the first damage spell carry their tooltip lines, pipes escaped"
      (a description containing a `|` reads `||` in its tooltip line)
   6. "a shape function the client lacks reads <absent>" (with `C_TooltipInfo` set to nil before
      a run: `tooltip = <absent>`, and the report still has every header)
   7. "the combat snapshot carries the shapes read in combat" (in combat 5185's desc is `<secret>`
      and `crit4=<secret>`)
   8. "UNIT_SPELLCAST_SUCCEEDED is counted with its id readable or secret, and the cost read at the cast"
      (fire it for `"player"` out of combat with 774 and in combat with a secret id: two lines, the
      right counts; a `"party1"` cast is not counted)
2. Every other suite at today's count: the sixteen TBC suites (simcheck `-> PASS`; reccheck 54,
   replaycheck 80, replayui 98, runcheck 78, reviewui 44, navui 25, dashui 56, regencheck 27,
   simwindow 8, solvercheck 70, timeline 27, spelltip 48, practice 74, practiceui 49, migrate 7),
   forevercheck 13, modulecheck 12, adaptercheck 15/11, corecheck 10/8, svcheck 6/1,
   consolecheck 11/1 (forever/tbc).
3. `python3 tools/apicheck.py` 0 findings; `python3 tools/apicheck.py --selftest` 7 of 7.
4. `tools/.lua/lua-5.1.5/src/luac -p Client/Probe.lua tools/wowstub.lua tools/probecheck.lua` clean.
5. Paste into the Report: the failing run before the code; the full probecheck output; the
   `== shapes` section of one stub report (out of combat) and its `in combat` block; every suite
   tail; apicheck; luac; `git status --short`.

## Out of scope

- Any M2 module (`Spells/`, tooltips, dashboard, clock) -- T7 onwards.
- The probe's `FUNCTIONS` list, its existing sections, its SavedVariables record, the to-do list.
- `Client/API*.lua`, `Core*.lua`, every `UI/` file.
- `CLAUDE.md` and every `docs/` file except this Report. Commits.

## Report

### Files touched

- `Client/Probe.lua`: added `ShowDepth` (Show with a configurable `Describe` depth, for the
  cost table), `PlayerBank` (factored out of `SpellWalk`, reused by the shapes section),
  `TooltipLines`, `FirstHealShapesLine`, `SucceededLines`, `BumpSucceeded`/`OnSpellcastSucceeded`,
  and the `ShapesLines(order)` function assembling all seven items. `SpellWalk`'s per-spell
  entries now also carry `id`, `slot` and `dmg` (the same case-insensitive "damage" substring
  test as the existing `healing` flag). `TakeCombatSnapshot` now also stores
  `shapesFirstHeal = FirstHealShapesLine(knownFirstHeal)` (a module-level cache of the most
  recently found "first spell whose description contains heal", refreshed by every `ShapesLines`
  call, since the combat snapshot runs independently of any `/st probe` and needs a spell id to
  re-read live rather than re-walking the book while secrecy may differ). `Run()` prints
  `"== shapes"` and `ShapesLines(order)` between `"== talents"` and `"== readings now"`.
  `UNIT_SPELLCAST_SUCCEEDED` is registered already (unchanged `EVENTS` list); a handler was added
  and wired into `HANDLERS`.
- `tools/wowstub.lua`: `GetSpellCritChance(school)` in the forever profile now takes a school
  argument (`S.crit[school] or 5`, secret in combat). `C_SpellBook` gained
  `GetNumSpellBookSkillLines` (2), `GetSpellBookSkillLineInfo` (General / Druid, the Druid line's
  `numSpellBookItems` tracking the highest slot in use) and `IsSpellBookItemLowRank`.
  `C_SpellBook.GetSpellBookItemInfo`'s row gained `name`/`subName`/`itemType`/`isPassive`/
  `isOffSpec`/`skillLineIndex`/`actionID`/`iconID`. `C_Spell` gained `GetSpellInfo`,
  `GetSpellPowerCost`, `GetSpellLevelLearned`, `GetBaseSpell`, backed by new per-id tables
  (`SPELL_CAST`, `SPELL_COST`, `SPELL_COST_PERCENT`, `SPELL_NO_COST`, `SPELL_LEVEL`,
  `SPELL_BASE`, `SPELL_LOWRANK`) seeded with this task's Facts for the four fixed spells
  (774/1058/5185/5176). `C_TooltipInfo.GetSpellByID` is new, building its four lines from those
  same tables and `C_Spell.GetSpellDescription` (so 5185's tooltip line 4 goes secret in combat
  exactly as its description does). `S.AddSpell` takes an optional fifth `opts` table
  (`cast`/`cost`/`costPercent`/`level`/`base`/`lowRank`/`noCost`). **`SPELL_SLOTS` was reordered**
  to `{ [1] = 5185, [2] = 774, [3] = 5176, [5] = 1058 }` (5185 and 774 swapped) — see "Conflict
  found" below.
- `tools/probecheck.lua`: the eight new assertions (exact names below), a `LineContaining`
  helper, two scripted `UNIT_SPELLCAST_SUCCEEDED` fires added to Step 2's existing timeline (one
  `"player"` cast out of combat with a readable id, one `"party1"` cast that must not be counted,
  one `"player"` cast in combat with a secret id), and two new steps: Step 7 (a spell added via
  `S.AddSpell(..., { lowRank = true })`, for the "every spell has a shapes line" assertion) and
  Step 8 (a fresh load with `C_TooltipInfo` removed *before* `ADDON_LOADED`, for the "reads
  `<absent>`" assertion — it needs its own fresh `MD.API` table, since `MD.API.Has` caches an
  answer for the life of one API table and Step 7's `MD7` had already cached
  `C_TooltipInfo.GetSpellByID` as present).

### Tests first

Before any code change, `bash tools/run.sh tools/probecheck.lua` was the unmodified baseline:
**58 ok, 0 failed**. The eight new assertions were then added to the bottom of the file (referring
to sections/state that did not exist yet) and run: all eight failed (missing `== shapes` header,
nil report segments, absent counters), confirming they exercised code not yet written. The
`Client/Probe.lua` and `tools/wowstub.lua` changes above were then made until all eight passed.

### Conflict found — stopping to report per the task's own rule

Implementing item 2 exactly as specified (`"spell <id> <name> <rank>: info=...; cost=...;
learned=...; base=...; lowrank=...; row=..."`, printed **"for every spell the walk found"**, not
just the healing ones) makes the substring `"spell 5176"` appear in every report, because Wrath
(5176, a damage spell) is one of the four fixed spellbook rows and the shapes section is
explicitly whole-book, not healing-only (Goal: "each spell's book row" — this is what M2's
spellbook reader will read for every spell, healing or not).

This collides with the **existing, unedited** assertion at line ~406 (now ~410):
`check("a spell that does not heal is not dumped", not Has(report1, "spell 5176"))` — written
against the old `"== spells"` section, which only ever dumped healing spells as bare
`"spell <key>\n  name: ...\n  rank: ...\n  desc: ..."`. `Has` is a plain substring search, so the
new shapes line for 5176 (`"spell 5176 Wrath Rank 1: info=..."`) makes this old assertion fail —
not from a bug, but because the task's own item-2 format necessarily prints `"spell 5176"`
somewhere once every book row is dumped.

Per this task's own rule ("An existing probecheck assertion is never edited. If one fails because
of the new section or the stub's new answers, stop and report which and why.") I did not touch
that assertion, did not change item 2's mandated line format, and did not narrow item 2 to
healing-only spells (which would contradict the Goal/Facts text quoted above). The result:
**`bash tools/run.sh tools/probecheck.lua` ends `65 ok, 1 failed`**, the one failure being
exactly this pre-existing assertion, for exactly this reason. Every other old assertion and all
eight new ones pass. I stopped here rather than guess at a resolution (editing the old assertion,
renaming the new line's label away from `"spell <id>"`, or excluding non-healing spells from item
2) since all three routes were explicitly out of scope or contrary to the spec; the lead should
pick one and I will implement it.

(Separately, and not a conflict: `SPELL_SLOTS`'s order — 5185 now before 774 — was changed
because item 3 needs "the first spell whose description contains heal" to land on a description
that actually has a pipe in it, to exercise the escaping rule end to end; 774 and 5185 are the
only two heals, and only 5185's description has one. I checked every other probecheck assertion
against this reorder — none depends on the relative order of the four fixed spells, only on their
presence/content/counts — and the full suite (below) confirms nothing else broke.)

### Full probecheck output

```
65 ok, 1 failed
  FAIL a spell that does not heal is not dumped
```

The eight new assertions, verbatim, all `ok`:
1. `the shapes section sits between the talents and the readings`
2. `the shapes section lists every skill line whole`
3. `every spell in the book has one shapes line: info, cost, learned, base, low rank, row`
4. `a spell's cost is rendered two levels deep`
5. `the first heal and the first damage spell carry their tooltip lines, pipes escaped`
6. `a shape function the client lacks reads <absent>`
7. `the combat snapshot carries the shapes read in combat`
8. `UNIT_SPELLCAST_SUCCEEDED is counted with its id readable or secret, and the cost read at the cast`

### The `== shapes` section, out of combat (build 70009, no party/combat)

```
skill lines: 2
skill line 1 = {iconID=1, isGuild=false, itemIndexOffset=0, name=General, numSpellBookItems=0, shouldHide=false}
skill line 2 = {iconID=2, isGuild=false, itemIndexOffset=0, name=Druid, numSpellBookItems=5, shouldHide=false}
spell 5185 Healing Touch Rank 1: info={castTime=1500, iconID=136041, maxRange=40, minRange=0, name=Healing Touch, originalIconID=136041, spellID=5185}; cost={1={cost=25, costPerSec=0, costPercent=0, hasRequiredAura=false, minCost=25, name=MANA, requiredAuraID=0, type=0}}; learned=1; base=5185; lowrank=false; row={actionID=5185, iconID=136041, isOffSpec=false, isPassive=false, itemType=1, name=Healing Touch, skillLineIndex=2, spellID=5185, subName=Rank 1}
spell 774 Rejuvenation Rank 1: info={castTime=0, iconID=136041, maxRange=40, minRange=0, name=Rejuvenation, originalIconID=136041, spellID=774}; cost={1={cost=25, costPerSec=0, costPercent=0, hasRequiredAura=false, minCost=25, name=MANA, requiredAuraID=0, type=0}}; learned=4; base=774; lowrank=false; row={actionID=774, iconID=136041, isOffSpec=false, isPassive=false, itemType=1, name=Rejuvenation, skillLineIndex=2, spellID=774, subName=Rank 1}
spell 5176 Wrath Rank 1: info={castTime=1500, iconID=136041, maxRange=40, minRange=0, name=Wrath, originalIconID=136041, spellID=5176}; cost={1={cost=20, costPerSec=0, costPercent=0, hasRequiredAura=false, minCost=20, name=MANA, requiredAuraID=0, type=0}}; learned=1; base=5176; lowrank=false; row={actionID=5176, iconID=136041, isOffSpec=false, isPassive=false, itemType=1, name=Wrath, skillLineIndex=2, spellID=5176, subName=Rank 1}
spell 1058 Rejuvenation Rank 2: info={castTime=0, iconID=136041, maxRange=40, minRange=0, name=Rejuvenation, originalIconID=136041, spellID=1058}; cost={1={cost=40, costPerSec=0, costPercent=0, hasRequiredAura=false, minCost=40, name=MANA, requiredAuraID=0, type=0}}; learned=10; base=774; lowrank=false; row={actionID=1058, iconID=136041, isOffSpec=false, isPassive=false, itemType=1, name=Rejuvenation, skillLineIndex=2, spellID=1058, subName=Rank 2}
tooltip 5185 = 4 lines
  line 1: Healing Touch || Rank 1
  line 2: 25 Mana || 40 yd range
  line 3: 1.5 sec cast || 
  line 4: Heals a friendly target for 40 to 55.||nIt is \226\128\156quoted\226\128\157. || nil
tooltip 5176 = 4 lines
  line 1: Wrath || Rank 1
  line 2: 20 Mana || 40 yd range
  line 3: 1.5 sec cast || 
  line 4: Causes 13 to 16 Nature damage to the target. || nil
crit: Physical=5 Holy=5 Fire=5 Nature=5 Frost=5 Shadow=5 Arcane=5
bonus healing: 0
in combat: none this session
UNIT_SPELLCAST_SUCCEEDED: none this session
```

### The `in combat` block, from the same session's combat snapshot

```
crit: Physical=<secret> Holy=<secret> Fire=<secret> Nature=<secret> Frost=<secret> Shadow=<secret> Arcane=<secret>
bonus healing: 0
in combat (2025-09-04 15:33:20):
  desc=<secret>; info={castTime=1500, iconID=136041, maxRange=40, minRange=0, name=Healing Touch, originalIconID=136041, spellID=5185}; cost={1={cost=25, costPerSec=0, costPercent=0, hasRequiredAura=false, minCost=25, name=MANA, requiredAuraID=0, type=0}}; crit4=<secret>; bonus healing=0
UNIT_SPELLCAST_SUCCEEDED: none this session
```

(`desc`/`crit4` read `<secret>` because the snapshot re-reads 5185 — the spell `knownFirstHeal`
was set to out of combat — live, and only 5185's description is special-cased secret-in-combat in
the stub; `info`/`cost` are unaffected by combat in this stub, matching what item 6 asks for:
whatever secrecy the client actually applies at that moment, not a guess.)

### Every other suite, today's count — all unchanged

```
simcheck        -> PASS
reccheck        54 ok, 0 failed
replaycheck     80 ok, 0 failed
replayui        98 ok, 0 failed
runcheck        78 ok, 0 failed
reviewui        44 ok, 0 failed
navui           25 ok, 0 failed
dashui          56 ok, 0 failed
regencheck      27 ok, 0 failed
simwindow       8 ok, 0 failed
solvercheck     70 ok, 0 failed
timeline        27 ok, 0 failed
spelltip        48 ok, 0 failed
practice        74 ok, 0 failed
practiceui      49 ok, 0 failed
migrate         7 ok, 0 failed
forevercheck    13 ok, 0 failed
modulecheck     12 ok, 0 failed
adaptercheck    15 ok, 0 failed (forever) / 11 ok, 0 failed (tbc)
corecheck       10 ok, 0 failed (forever) / 8 ok, 0 failed (tbc)
svcheck         6 ok, 0 failed (forever) / 1 ok, 0 failed (tbc)
consolecheck    11 ok, 0 failed (forever) / 1 ok, 0 failed (tbc)
```

### apicheck

```
$ python3 tools/apicheck.py
apicheck: 8 Forever TOCs, 15 files, 38 distinct globals, 0 findings (baseline 69893)

$ python3 tools/apicheck.py --selftest
selftest: 7 of 7 findings as expected
```

### luac

```
$ tools/.lua/lua-5.1.5/src/luac -p Client/Probe.lua tools/wowstub.lua tools/probecheck.lua
(clean, no output)
```

### git status --short

```
 M Client/Probe.lua
 M tools/probecheck.lua
 M tools/wowstub.lua
?? docs/tasks/T10-spells-pane.md
?? docs/tasks/T11-clock.md
?? docs/tasks/T12-measure.md
?? docs/tasks/T7-spell-book.md
?? docs/tasks/T7a-probe-shapes.md
?? docs/tasks/T9-spell-tooltip.md
```
(the untracked `docs/tasks/*.md` files above are not mine — I only wrote into this file's Report
section — and T8/T8-adjacent files the other implementers own do not appear because they had not
started writing yet at the time of this run.)

### What I skipped / did not do

- Did not touch `T8-spell-parse.md`, `T8b-refcheck.md`, `tools/data/parse-fixture.lua`, or the
  Forever TOCs — those belong to the two concurrent implementers.
- Did not edit `CLAUDE.md`, `docs/PLAN.md`, `docs/HISTORY.md`, `docs/FOREVER-PLAN.md`, or any other
  `docs/` file.
- Did not resolve the one pre-existing-assertion conflict above; left it failing and documented
  why, per the task's explicit instruction to stop and report rather than guess.

### Question for the lead

How should the item-2/"a spell that does not heal is not dumped" conflict be resolved? Three
options I saw and did not pick unilaterally: (a) accept that the old assertion's assumption (no
non-healing spell's id ever appears as a bare `"spell <id>"` substring) no longer holds now that
the shapes section is whole-book, and adjust that one assertion; (b) give item 2's lines a
different leading token (e.g. `"book row <id> ..."`) so `"spell <id>"` stays healing-only-safe —
this would deviate from the task's literal exact-line-form text; (c) restrict item 2 to healing
spells only — contradicts the Goal's "each spell's book row" and Facts' "every other return shape
is UNKNOWN," which is the whole reason item 2 asks for every spell. I implemented the literal spec
(whole-book, item 2's exact line form) and left the collision for a decision rather than choosing
for you.

## Review (lead, 2026-09-28)

Accepted, with one amendment the task's own spec made necessary. The implementer stopped exactly
where the rules said to: item 2's line form (`spell <id> ...`, the lead's) collided with the
existing assertion "a spell that does not heal is not dumped", whose intent -- the `== spells` dump
lists heals only -- is still right. Ruling: option (b); the lead made the rename itself (six
strings, one token: `Client/Probe.lua` line 905 and five `Has` / `LineContaining` needles in
`tools/probecheck.lua`), since the agent could no longer be messaged. probecheck now `66 ok, 0
failed`; every other suite at its count, apicheck 0, the TOCs untouched.

Read the diff whole: every new client call is under `pcall` through `Show` / `ShowDepth` /
`Field`; `IsSecret` precedes every comparison (`OnSpellcastSucceeded` checks the unit token before
`== "player"`, `BumpSucceeded` the id before `~= nil`); a tooltip row is indexed only after it is
known to be a non-secret table, and every value goes through `Fmt`. The stub's `SPELL_SLOTS`
reorder (5185 first, so the first heal's tooltip carries the pipe) is right and breaks nothing.
The stub's shapes are commented as retail's, unverified -- the next report from the beta checks
them, line by line, against T7's reader.
