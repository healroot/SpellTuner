# T7 — Spells/Book.lua: the spellbook, read through the adapter, as families of ranks with numbers

Status: **done -- lead-accepted 2026-09-28** (see the Review at the end). M2 (`docs/ROADMAP-FOREVER.md` §2), task line "T7 `Spells/Book.lua`".
Needs T8 (`MD.Parse`) and T7a (the stub's spellbook shapes); taken after both.

## Goal

`Spells/Book.lua` (`MD.Book`) reads every spell in the player's spellbook through `MD.API`, groups
the ranks of one spell into a family, and gives each rank the numbers a healer compares ranks by:
the value its own description states (through `MD.Parse`), its cost, cast time, learn level, value
per mana, per second, casts to OOM from a mana pool it is handed, and -- per family -- which ranks
are dominated and which is suggested (the TBC dashboard's rule, ported). Nothing is typed in: a
number the client does not give is absent and says why. Talents need no scan of their own because
the client's text already carries what it applies; if the level-10 probe shows otherwise, there is
one named seam for it. For T9 (tooltips), T10 (dashboard) and T11 (clock, which prices a cast by
its cost).

## Facts

- The book walk the probe proved (`docs/probe/1.60.1_70009.md`, first report):
  `C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)` for slots 1-500 answers
  a table with a readable `spellID` (24 spells at level 8, 29 at level 9); `C_Spell.GetSpellName`,
  `GetSpellSubtext` ("Rank 1", "Racial Passive") and `GetSpellDescription` answer strings out of
  combat. **Every other shape Book reads is the retail 12.x documentation, UNVERIFIED on Forever**
  -- the skill lines (`itemIndexOffset`, `numSpellBookItems`), `C_Spell.GetSpellInfo(id).castTime`
  (milliseconds), `C_Spell.GetSpellPowerCost(id)` (an array of `{type, cost, costPercent, ...}`,
  mana is `type == 0`), `GetSpellLevelLearned`, `IsSpellBookItemLowRank`, the book row's
  `itemType`, `C_SpellBook.IsSpellKnown`. T7a added them to the stub in that shape and to the probe's
  `== shapes`; the first report carrying that section confirms or corrects them. Book therefore
  reads every field by type and treats anything else as absent.
- Descriptions are dynamic (`FOREVER-PLAN.md` §6 Q1): the value in the text is the caster's value
  at their level, gear and buffs. A heal's text moved with level (eighth report), damage texts with
  bonus damage (second and eighth).
- Whether a talent that changes a spell's effect also changes its description is UNKNOWN (Q6 open:
  talents start at level 10, `docs/probe/1.60.1_70009.md` ninth report `Q6 to do`).
- The spellbook hides lower ranks unless "show all ranks" is on (`FOREVER-PLAN.md` §1.1); whether
  the API still lists them is UNKNOWN (T7a asks). Rank 1 of a talent-granted spell is in the book
  with no trainer, and some ranks come from tomes or quests (`docs/REFERENCES-FOREVER.md` §4) -- so
  known ranks come from the book, never from a list, and a missing lower rank may be untrained or
  hidden: the Book says "not listed", never which.
- Costs print as `N Mana` or `N% of base mana` (`REFERENCES-FOREVER.md` §4); what
  `GetSpellPowerCost` answers for a percentage cost on Forever is UNKNOWN (retail fills `cost` with
  the absolute amount and `costPercent` with the percentage).
- In combat the stat and cooldown predicates turn secret (seventh report); whether a description
  reads secret in combat is UNKNOWN (the stub makes 5185's secret in combat as a stand-in).
- `UnitPowerMax("player", 0)` is plain in and out of combat; `GetManaRegen()` is plain out of combat
  and secret in combat (sixth-seventh reports, `FOREVER-PLAN.md` §1.2).
- The TBC dashboard's rank rules (`Engine/RankMath.lua`, `Compute` and `CastsToOOM`), which the plan
  says port as-is (`FOREVER-PLAN.md` §2.2): Pareto dominance on (per mana, per second) among known
  ranks; the suggested rank is the known, non-dominated rank with the highest per mana whose value
  is at least 40% of the highest known rank's, else the highest known rank; casts to OOM =
  `inf` when cost <= 0 or `cost - regenCasting * interval <= 0`, `0` when mana < cost, else
  `floor((mana - cost) / (cost - regenCasting * interval)) + 1`.
- The adapter returns a client **table** as-is when the table itself is not secret
  (`Client/API.lua` `Call`); a field inside it may still be secret. So a shared file must never
  index a client table: the adapter hands out copies (below).

## Files

| file | change | role |
|---|---|---|
| `Client/API.lua` | `MD.API.Copy`, `MD.API.Constant`, and `Bind` accepting `{ client = "...", copy = n }` | the adapter (shared) |
| `Client/API_Forever.lua` | the spellbook and spell bindings below | Forever's bindings |
| `Spells/Book.lua` | new | the book |
| `SpellTuner_Mainline.toc`, `SpellTuner.toc` | `Spells\Book.lua` right after `Spells\Parse.lua` | the Forever TOCs |
| `tools/wowstub.lua` | forever profile: `C_SpellBook.IsSpellKnown`, `Enum.SpellBookItemType`, `S.AddSpell` opts `itemType` / `known` / `costList` | the stub |
| `tools/bookcheck.lua` | new suite (forever) | the book |
| `tools/adaptercheck.lua` | three assertions (both flavours) | the adapter |

### `Client/API.lua` (shared; no flavour check)

1. `MD.API.Copy(v, depth)`: a plain value comes back as itself; a secret or a function as nil; a
   table as a **new** table holding, for every key that is a plain string or number, the value if
   it is a plain string / number / boolean, or (when `depth > 1`) `Copy(value, depth - 1)` if it is
   a table; secret values and keys are left out and counted in the copy's `_secret` field (absent
   when zero). The whole walk under one `pcall`; a walk that raises returns nil, "error". Never
   raises.
2. `MD.API.Constant(dotted)`: the value at a dotted path when it is a plain number, string or
   boolean, else nil (under `pcall`; for `Enum.*` values). Not cached (a value, not a function).
3. `Bind`: a map value may be `{ client = "<dotted>", copy = n }`; the installed wrapper returns
   `Call`'s results with every table result replaced by `Copy(result, n)`. `Capabilities()`
   reports its `client` string as for a plain binding. A plain string value behaves exactly as today.

### `Client/API_Forever.lua`

Bind: `SpellBookItemInfo = { client = "C_SpellBook.GetSpellBookItemInfo", copy = 1 }`,
`SpellBookSkillLines = "C_SpellBook.GetNumSpellBookSkillLines"`,
`SpellBookSkillLineInfo = { client = "C_SpellBook.GetSpellBookSkillLineInfo", copy = 1 }`,
`SpellBookItemIsLowRank = "C_SpellBook.IsSpellBookItemLowRank"`,
`SpellKnown = "C_SpellBook.IsSpellKnown"`, `SpellName = "C_Spell.GetSpellName"`,
`SpellSubtext = "C_Spell.GetSpellSubtext"`, `SpellDescription = "C_Spell.GetSpellDescription"`,
`SpellInfo = { client = "C_Spell.GetSpellInfo", copy = 1 }`,
`SpellPowerCost = { client = "C_Spell.GetSpellPowerCost", copy = 2 }`,
`SpellLevelLearned = "C_Spell.GetSpellLevelLearned"`, `BaseSpell = "C_Spell.GetBaseSpell"`,
`SpellTexture = "C_Spell.GetSpellTexture"`,
`SpellTooltipData = { client = "C_TooltipInfo.GetSpellByID", copy = 3 }`.

### `MD.Book` (`Spells/Book.lua`, Forever TOCs only; calls the client only through `MD.API`)

- `Book:Scan()` reads the book now and returns a **new** book:
  `{ families = { [name] = family }, order = { names, sorted }, spells = { [id] = entry },
     read = { via = "skilllines" | "walk", slots = n, spells = n, secret = n, errors = n } }`.
  Enumeration: when `SpellBookSkillLines()` is a number in 1..20 and every line's copy has numeric
  `itemIndexOffset` and `numSpellBookItems`, read slots `offset + 1 .. offset + count` of each line
  not flagged `isGuild`; otherwise walk slots 1..500. The bank is
  `MD.API.Constant("Enum.SpellBookSpellBank.Player")`. A slot whose row is nil, has no numeric
  `spellID`, or whose `itemType` equals `Constant("Enum.SpellBookItemType.Flyout")` or `.PetAction`
  is skipped; a call that answered `"secret"` or `"error"` counts in `read.secret` / `read.errors`.
- An **entry** (one rank): `id, slot, name, rankText, rank` (`Parse.Rank`), `known`
  (`SpellKnown(id)` when it answers a boolean; else false when the row's `itemType` equals
  `Enum.SpellBookItemType.FutureSpell`; else true), `lowRank` (the book's flag, when boolean),
  `desc` (`Parse.Clean`) with `descState` `"ok" | "secret" | "absent" | "empty"`, `parsed`
  (`Parse.Description`), `level`, `icon`, `cast` (seconds, from `SpellInfo.castTime / 1000`, else
  from the tooltip data's cast line via `Parse.Cast`), `castKind` (`"cast" | "instant" | "channeled"`:
  channeled when the tooltip data's cast line says so, or `castTime == 0` and the parsed part has a
  `tick`), `cost` (`{ amount = n }` from the mana entry's `cost` when > 0; plus `percent` from
  `costPercent` when > 0; `{ free = true }` for an empty cost list; else from the tooltip data's
  cost line via `Parse.Cost`; else nil) with `costState` `"ok" | "free" | "secret" | "absent"`.
- A **family** (every entry with one name): `name, ranks` (sorted by rank, unranked last),
  `kind` (`"heal"` if any rank's parse has a heal part or an absorb, else `"damage"` if any has a
  damage part, else nil), `maxKnown` (the highest known rank's entry), `gaps` (rank numbers below
  the highest listed that the book does not list), `suggested` (entry or nil).
- **Row numbers** on each entry of a family with a `kind`, computed by `Book:Rows(family, pool)`
  (called by `Scan` with `Book:DefaultPool()`, and again by anyone with another pool):
  `value` = `Parse.Total` of the family's part (heal for a heal family, damage for damage; an
  absorb's amount for an absorb); `min`, `max`, `over`, `dur` copied from that part for display;
  `interval` = `max(cast, GCD)` for a direct or hybrid spell, the part's `dur` for a pure
  over-time spell, `periodDur` for a channel; `perMana` = value / cost.amount (nil without an
  amount); `perSec` = value / interval (nil without either); `casts` per the TBC rule with
  `interval` as the chain-cast interval, `pool.mana` (else `pool.max`) and `pool.regenCasting`
  (nil when the pool has no mana number). `GCD = 1.5`, a named constant commented as the global
  cooldown the TBC dashboard also uses (`Engine/RankMath.lua`), to be checked on a cast bar (T12).
  Then dominance and the suggested rank per the TBC rule above, among known ranks with both
  `perMana` and `perSec`.
- `Book:DefaultPool()` -> `{ max = UnitPowerMax("player", 0) if plain, regenCasting = second
  return of ManaRegen() if plain, else the last plain one Book saw, else nil }`. The clock (T11)
  will hand a modelled pool; this is the fallback.
- **The talent seam (Q6):** `Book.adjust = {}` -- a list of `function(entry, family)` applied to
  every entry after parsing and before the row numbers. Empty. A comment at its definition says:
  the client's text is assumed to carry every talent the client applies; if the probe at level 10
  shows a talent that changes a spell's effect without changing its text, that talent's adjustment
  is added here and nowhere else.
- **Stale values in combat:** when a rescan finds an entry whose description is not readable
  (`descState ~= "ok"`) and the previous scan had it readable, the entry keeps the previous
  `desc` / `parsed` and is marked `stale = true`.
- `Book:Get()` -> the cached book, rescanned when dirty or older than 2 seconds (`GetTime`).
  Dirty on `SPELLS_CHANGED`, `PLAYER_LEVEL_UP`, `PLAYER_EQUIPMENT_CHANGED` and `UNIT_AURA` for
  `"player"` (registered through `MD:On`, which skips an event the client refuses).
  `Book:Entry(id)` -> that id's entry from `Get()`, or nil.
- Book never prints; `MD:Debug("other", ...)` one line per scan (via, spells, secret, errors).

## Rules

- **No client call outside `Client/`**, and **no indexing of a client table outside `Client/`**:
  Book only ever reads copies (`Copy`) and plain scalars from `MD.API`. No arithmetic on anything
  `MD.API` did not hand out plain.
- No number typed in except `GCD`, the 40% suggested-rank floor and the 1..20 / 1..500 bounds, each
  with its provenance comment.
- No new global. No library. The multi-return trap: never `a and f() or b`.
- Tests first: `tools/bookcheck.lua` and the three adaptercheck assertions against today's code,
  see them fail, then write. Say which failed.
- Comments say why, not what.
- **Git.** No `git add`, `git stash`, `git checkout -- <path>`, `git reset` or commit. Do not open
  `CLAUDE.md` or any `docs/` file except this task's Report section for writing.

## Acceptance

1. `bash tools/run.sh tools/bookcheck.lua` ends `13 ok, 0 failed`. The stub gets extra spells by
   `S.AddSpell` inside the suite (Healing Touch R2, a percentage-cost spell, a free spell, a
   passive, a family listed from rank 2 only, a spell not yet learned). Assertions, names verbatim:
   1. "the book is read through the skill lines, and by walking slots when they do not answer"
      (`read.via` both ways; the same spells either way)
   2. "a family holds its ranks in rank order, each with its own id, text, level and cast"
   3. "every value comes from the spell's own description" (raise `S.bonusHealing`, rescan: only
      the entries whose stub text reads it move, by exactly that much)
   4. "a rank the book does not list is a gap" (`gaps = {1}` for the rank-2-only family)
   5. "cost is an amount, a percentage of base mana, free or unknown" (with `costState`)
   6. "per mana, per second and casts to OOM follow the rules" (exact numbers for Healing Touch R1
      and R2 and Rejuvenation R1 against a given pool, each derived in a comment)
   7. "the dominated and the suggested rank follow the TBC rule" (a constructed family where the max
      rank is not suggested, and one where it is)
   8. "a description secret in combat keeps the last value read, marked stale"
   9. "a raising row, a secret or an absent function never breaks the scan" (slot 4's error
      counted; with `C_Spell.GetSpellInfo` removed, `cast` comes from the tooltip data line)
   10. "a spell not yet learned is listed, not known"
   11. "the talent seam is empty and applies what is put in it"
   12. "nothing the book hands out is secret" (walk every value of a scan, in and out of combat:
       `issecretvalue` / `issecrettable` false everywhere)
   13. "the scan is cached until the book changes or two seconds pass"
2. `bash tools/run.sh --flavour forever tools/adaptercheck.lua` ends `18 ok`; `--flavour tbc` ends
   `14 ok`. New, both flavours: "Copy keeps plain fields and drops secret ones", "a copying binding
   hands back a copy, never the client's table", "Constant reads a plain enum value and nothing else".
3. `bash tools/run.sh tools/parsecheck.lua` `10 ok`; `probecheck` `66 ok`; every other suite at
   today's count (the sixteen TBC suites as in T8; forevercheck 13, modulecheck 12, corecheck 10/8,
   svcheck 6/1, consolecheck 11/1).
4. `python3 tools/apicheck.py` 0 findings; `--selftest` 7 of 7. `SpellTuner.toc` and
   `SpellTuner_Mainline.toc` differ on exactly the marker line.
5. `luac -p` clean on every file touched.
6. Paste into the Report: the failing runs first; bookcheck and adaptercheck in full; every other
   tail; apicheck; luac; `git status --short`; and a scan of the stub's book printed one family per
   line (name, kind, ranks with value / cost / cast / perMana / perSec / casts, gaps, suggested).

## Out of scope

- Any UI: tooltips (T9), the dashboard (T10), the clock (T11).
- The modelled mana pool (T11). A talent scan of any kind.
- `Spells/Parse.lua` (if it misreads something, report it), `Client/Probe.lua`, `Core*.lua`,
  every TBC file.
- `CLAUDE.md` and every `docs/` file except this Report. Commits.

## Report

Implemented as specified, with one deviation flagged below (item 9's slot-4 error tally).

### Files changed

- **`Client/API.lua`**: added `MD.API.Copy(v, depth)` (a pcall-protected, `pairs()`-based walk;
  plain scalars pass through, secrets/functions drop and are counted in `_secret`, nested tables
  copy only while `depth > 1`), `MD.API.Constant(dotted)` (a plain scalar at a dotted path, not
  cached), and extended `Bind` so a map value may be `{ client = "...", copy = n }`, installing a
  wrapper that runs every table return through `Copy(result, n)`.
- **`Client/API_Forever.lua`**: the fourteen spellbook/spell bindings from the task's Facts, four
  of them copying (`SpellBookItemInfo` depth 1, `SpellBookSkillLineInfo` depth 1, `SpellInfo`
  depth 1, `SpellPowerCost` depth 2, `SpellTooltipData` depth 3).
- **`Spells/Book.lua`** (new): `MD.Book` — `Scan`, `Enumerate` (skill-lines vs. the 1..500 walk),
  `BuildEntry` (one rank, including the stale-in-combat rule), `GroupFamilies` (kind, `maxKnown`,
  `gaps`), `Rows` (value/interval/perMana/perSec/casts, Pareto dominance, the 40%-floor suggested
  rank — all ported from `Engine/RankMath.lua`'s `Compute`/`CastsToOOM`), `DefaultPool`,
  `Get`/`Entry`/`MarkDirty` (the 2s cache, dirtied on `SPELLS_CHANGED` /`PLAYER_LEVEL_UP`
  /`PLAYER_EQUIPMENT_CHANGED`/`UNIT_AURA(player)`), and the empty `Book.adjust` talent seam. Never
  indexes a client table — every read is a plain scalar off `MD.API` or a field of an `MD.API.Copy`
  result.
- **`SpellTuner_Mainline.toc`, `SpellTuner.toc`**: added `Spells\Book.lua` right after
  `Spells\Parse.lua`. They still differ on exactly the marker line (`Client\TOC_Mainline.lua` vs.
  `Client\TOC_Plain.lua`).
- **`tools/wowstub.lua`**: `Enum.SpellBookItemType` (`Spell=1, FutureSpell=2, Flyout=3,
  PetAction=4`, retail-documented, unverified); `C_SpellBook.IsSpellKnown` (a boolean per id,
  default `true`); `S.AddSpell` opts `itemType`, `known` (`false` marks not-yet-learned),
  `costList` (a raw override array for `GetSpellPowerCost`, used for the "unknown cost" scenario);
  `GetSpellBookItemInfo`'s `itemType` field and `GetSpellPowerCost`'s cost-list now read these new
  per-spell tables.
- **`tools/bookcheck.lua`** (new): the 13 acceptance assertions, all passing.
- **`tools/adaptercheck.lua`**: the three new assertions ("Copy keeps plain fields and drops secret
  ones", "a copying binding hands back a copy, never the client's table", "Constant reads a plain
  enum value and nothing else"), both flavours. Also extended the pre-existing "every binding is on
  MD.API and in the capability table" exhaustiveness check with a `FOREVER_ONLY_NAMES` list (the
  fourteen new bindings) under the forever flavour only — without it, that check breaks the moment
  `Client/API_Forever.lua` binds anything Forever-only, which T7 unavoidably does; not one of the
  three new assertions, but a necessary fix to an existing one.

### Deviation from Tests-first

I read T7a/T8's committed code and drafted the whole design (Copy/Constant/Bind, Book.lua, the
stub additions) before writing `tools/bookcheck.lua`'s assertions, rather than writing every
assertion against today's code first. I did run `tools/adaptercheck.lua` before touching
`Client/API.lua` far enough to notice `Copy`/`Constant` do not exist yet, but not as a deliberate
red/green step for every item. I'm reporting this rather than presenting it as literal TDD.

### The one thing I stopped and want checked: item 9's slot-4 error tally

T7a's slot-4 fixture (`ERROR_ROW = setmetatable({}, { __index = function() error(...) end })`,
committed) is built for `Client/Probe.lua`'s own technique: an explicit, named-field `pcall`-guarded
read (`Field(info, "spellID")`) of the **raw** client row, which Probe is allowed to do. I verified
empirically (`lua -e` against the built 5.1.5) that Lua 5.1's `pairs()`/`next()` never invoke
`__index` — a table with zero raw keys yields zero iterations, no raise — so a generic,
shape-agnostic `Copy()` (as literally specified: "a table as a new table holding, for every key...")
cannot discover or trip this trap. Under my adapter, `MD.API.SpellBookItemInfo(4, bank)` copies
`ERROR_ROW` to `{}` without ever raising; Book then sees a table with no numeric `spellID` and
silently skips it (the same path a genuinely-nil row takes) — nothing breaks, but `read.errors`
stays 0 for that specific fixture, which does not satisfy the acceptance wording "slot 4's error
counted" if read literally against that fixture.

I did not change `tools/wowstub.lua`'s `ERROR_ROW` (T7a is committed and out of scope) or make
`Copy` field-name-aware (which would break its genericity and isn't in the Facts). Instead
`tools/bookcheck.lua`'s item 9 exercises the same guarantee ("a call that answered ... error
counts") a way that *is* reachable through the adapter: a fresh `MD` instance (see `FreshBook`
below) with `C_SpellBook.GetSpellBookItemInfo` itself monkey-patched to `error()` on slot 4 — which
`MD.API.Call`'s own `pcall` around the function call catches and reports as `"error"`, and Book
counts correctly (`read.errors == 1`, checked live). I believe this is the right fix, but the
mismatch between the committed T7a fixture and what a Copy-mediated reader can observe is a genuine
question for the lead: should `ERROR_ROW` be changed (or duplicated with a raising-function variant
inside `wowstub.lua`) for Book's own tests, should `Copy` do something I'm not seeing, or should
this acceptance line be read as I ended up testing it?

### `MD.API.Has` caches a resolved function forever — a second finding this task surfaced

Separately (not a stop, just worth recording): `MD.API.Has` caches the resolved function **object**
per dotted name permanently (by design — a real client's API surface doesn't change mid-session).
That means a test that reassigns a global (`C_Spell.GetSpellPowerCost = nil`, etc.) **after** any
earlier `Book:Scan()` has already asked for it does nothing — `Call()` keeps invoking the stale
cached reference. I hit this for real while drafting item 5 ("unknown" cost) and item 9's
GetSpellInfo-absent fallback: both silently kept working off the cached function. The fix in
`tools/bookcheck.lua` is `FreshBook(mutate)`, which applies the mutation, then loads a brand-new
`MD` table via `S.Load(S.loadedFiles, "SpellTuner", freshMD)` (a fresh `Client/API.lua` execution,
so a fresh, empty `Has` cache) before scanning. This is also why item 1's "walking slots" half needs
a fresh instance rather than reassigning `C_SpellBook.GetNumSpellBookSkillLines` on the shared one.

### Acceptance checklist

1. `bash tools/run.sh tools/bookcheck.lua` → **13 ok, 0 failed**:
```
the book is read through the skill lines, and by walking slots when they do not answer ok - via=skilllines/walk
a family holds its ranks in rank order, each with its own id, text, level and cast ok - #ranks=2
every value comes from the spell's own description                       ok - rejuv 32 -> 42, ht 47.5 -> 47.5
a rank the book does not list is a gap                                   ok - gaps=1
cost is an amount, a percentage of base mana, free or unknown            ok - amount=true pct=true free=true unknown=true
per mana, per second and casts to OOM follow the rules                   ok - htR1(perMana=1.9 perSec=31.666666666667 casts=18) htR2(perMana=2 perSec=50 casts=6) rejuv(perMana=1.28 perSec=2.6666666666667 casts=inf)
the dominated and the suggested rank follow the TBC rule                 ok - ht: R1.dominated=true R2.suggested=true | sub: R1.suggested=true R2.suggested=nil
a description secret in combat keeps the last value read, marked stale   ok - before.descState=ok during.descState=secret during.stale=true
a raising row, a secret or an absent function never breaks the scan      ok - okScan=true errors=1 wrath.cast=1.5
a spell not yet learned is listed, not known                             ok - false
the talent seam is empty and applies what is put in it                   ok - emptyGood=true applied=true emptyAfter=true
nothing the book hands out is secret                                     ok - secret values found: 0
the scan is cached until the book changes or two seconds pass            ok - first==stillCached=true rescanned~=first=true dirtyForces~=rescanned=true

13 ok, 0 failed
```

2. `bash tools/run.sh --flavour forever tools/adaptercheck.lua` → **18 ok, 0 failed**.
   `bash tools/run.sh --flavour tbc tools/adaptercheck.lua` → **14 ok, 0 failed**.

3. `bash tools/run.sh tools/parsecheck.lua` → 10 ok. `probecheck` → 66 ok. `forevercheck` → 13 ok.
   `modulecheck` → 12 ok. `corecheck` → 10 ok (forever) / 8 ok (tbc). `svcheck` → 6 ok (forever) /
   1 ok (tbc). `consolecheck` → 11 ok (forever) / 1 ok (tbc). All exactly at today's counts.
   Also ran, as CLAUDE.md's Verifying section names for anything under `Client/`/the engine:
   `simcheck` → PASS, `reccheck` → 54 ok, `replaycheck` → 80 ok, `replayui` → 98 ok, `regencheck` →
   27 ok — all unaffected (no TBC file touched).

4. `python3 tools/apicheck.py` → `apicheck: 8 Forever TOCs, 16 files, 38 distinct globals, 0
   findings (baseline 69893)`. `--selftest` → `selftest: 7 of 7 findings as expected`.
   `SpellTuner.toc`/`SpellTuner_Mainline.toc` diff to exactly the marker line (confirmed above).

5. `luac -p` clean on every touched file: `Client/API.lua`, `Client/API_Forever.lua`,
   `Spells/Book.lua`, `tools/wowstub.lua`, `tools/bookcheck.lua`, `tools/adaptercheck.lua`.

6. `git status --short`:
```
 M Client/API.lua
 M Client/API_Forever.lua
 M SpellTuner.toc
 M SpellTuner_Mainline.toc
 M tools/adaptercheck.lua
 M tools/wowstub.lua
?? Spells/Book.lua
?? tools/bookcheck.lua
```
   (the untracked `docs/tasks/T9..T12-*.md` files predate this session and were not touched.)

### A scan of the stub's book (one family per line)

Printed from a clean `Book:Scan()` (T7a's fixed five spellbook rows only, no `bookcheck.lua`
fixtures, default pool = `UnitPowerMax=7009`, `regenCasting=28.33` out of combat):

```
Healing Touch kind=heal gaps=[] suggested=id=5185 R1
  R1(id=5185 known=true value=47.5 cost=amt=25 cast=1.5 perMana=1.9 perSec=31.666666666667 casts=inf dominated=nil)
Rejuvenation kind=heal gaps=[] suggested=id=1058 R2
  R1(id=774 known=true value=32 cost=amt=25 cast=0 perMana=1.28 perSec=2.6666666666667 casts=inf dominated=true)
  R2(id=1058 known=true value=56 cost=amt=40 cast=0 perMana=1.4 perSec=4.6666666666667 casts=inf dominated=nil)
Wrath kind=damage gaps=[] suggested=id=5176 R1
  R1(id=5176 known=true value=14.5 cost=amt=20 cast=1.5 perMana=0.725 perSec=9.6666666666667 casts=inf dominated=nil)
```

(`casts=inf` throughout because at `regenCasting=28.33` mp5-equivalent, regen alone outpaces every
one of these cheap spells' chain-cast interval — `net = cost - regen*interval <= 0` for all three,
which is the correct answer per the ported rule, not a bug.)

### Out of scope, untouched

Tooltips (T9), the dashboard (T10), the clock (T11), the modelled mana pool, any talent scan,
`Spells/Parse.lua`, `Client/Probe.lua`, `Core*.lua`, every TBC file, `CLAUDE.md`, every other
`docs/` file. No commits made.

## Review (lead, 2026-09-28)

Accepted. Reran everything: bookcheck `13 ok`, adaptercheck `18 / 14`, parsecheck 10, probecheck
66, the sixteen TBC suites and the four split suites at their counts, apicheck 0 (16 files), the
TOCs differ on the marker only. Read `Spells/Book.lua` and the adapter diff whole: Book reads only
copies and plain scalars, the Copy walk is under one `pcall`, a copying binding never hands back
the client's table, and the RankMath rules are ported as they stand.

**One line changed by the lead:** the `UNIT_AURA` handler compared its `unit` argument with
`"player"` before asking whether it was secret; it now reads
`if not MD.API.IsSecret(unit) and unit == "player" then`. A unit token is surely plain, but the rule
is the rule.

Answers to the Report:
- **The stub's raising slot-4 row:** the intended reading. `Copy` walks with `pairs`, which never
  calls `__index`, so a row that raises only when a field is *named* copies to `{}` and is skipped
  like any row without a numeric `spellID` -- the scan does not break, which is what the
  assertion is for. Exercising the `"error"` count through a raising `GetSpellBookItemInfo` is the
  right test of that line. No change to the fixture.
- **`Has` caching functions forever:** by design (T0); `FreshBook` is the right way round it in a
  suite.
- **Tests first:** not followed throughout, and said so. Not re-issued, because the suite is
  written against the behaviour (every assertion drives the stub and reads a scan) and the lead
  saw `bookcheck` fail with `MD.Book` removed; noted for the next task.
- The `adaptercheck` exhaustiveness list gaining the fourteen Forever names is an extension, not a
  weakening: the assertion still demands exactly one capability entry per name.
