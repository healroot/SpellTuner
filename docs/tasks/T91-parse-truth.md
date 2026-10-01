# T91 -- parse truth: decimals, refusals, targets, cooldowns, lockouts, mana sources

Status: **built** 2026-10-01 on branch `next/T91` (base `e2b13f4`), wave N1, awaiting the integrator.
Owned files only: `Spells/Parse.lua`, `tools/parsecheck.lua`, `tools/data/parse-fixture.lua`. No TOC
change (`Spells/Parse.lua` is already on both Forever TOCs; it reaches TBC only in T111). No
default registered (`defaultscheck` unchanged). `tools/data/expected-counts.json` is
integrator-owned and was **not** edited in the branch: `make check` was run with the line below
applied, then the line reverted.

## The task

`docs/SPEC-next.md` section 11, row T91 (4.2 P0 d and the P1 parser; the two P4 parse shapes
T105 will read). Research: `docs/research/next/R-classes.md` 1.1 (the three misreads, run over all
1796 `spell_desc` rows of the talentsforever export) and section 3 (P0 d, P1, P4).

## What was built (`Spells/Parse.lua`)

**P0 d -- the three misreads:**

- **Decimal amounts.** `NUM` is `%f[%w.,]%d[%d,]*%.?%d*`: a number never starts right after a
  letter, digit, point or comma (so nothing begins inside `0.5` or `1,050`), and an optional
  `.digits` tail reads the decimal. Every text a pattern reads first passes `DetachStops`, which
  moves a full stop that follows a digit one space off it (`55.` -> `55 .`), so a sentence's end is
  never part of a number and blanking an amount never blanks the stop a sentence test looks for.
  Mana Burn's "takes 0.5 Shadow damage" reads `0.5`, never `5`.
- **"N additional damage" refused.** `AddedPerPoint(word)`: the catch-all `DAMAGE_SINGLE` (and
  `DAMAGE_RANGE`) no longer read an amount whose word is `additional` -- Execute's "converting each
  extra point of rage into 15 additional damage" (and Ferocious Bite's energy twin) read nil. An
  "additional" amount that is the cast's own is read by the combined patterns, as before.
- **"Your next X" refused.** `DropFutureClauses`: every sentence holding `your next` is blanked
  before any pattern runs (it describes a later cast). Light's Vigil R1-R3 read nil (they read as a
  325-343 / 684-724 heal plus damage); Holy Nova R2+'s closing "... for your next Holy Nova to cost
  no Mana" is dropped and its own heal and damage still read.

`Prepare(text)` (clean, detach stops, drop future clauses) is the working copy `Description` and
every new reader parse. `SentenceAt` now calls `SentenceBounds` (same answer; the bounds are
shared with `ManaSource`).

**Over the whole export (1796 texts) `Parse.Description` changes on exactly 18 rows and nothing
else:** Mana Burn R1-R5 (`5` -> `0.5`), Execute R1-R5 and Ferocious Bite R1-R5 (a per-point
"additional" amount -> nil), Light's Vigil R1-R3 (heal + damage -> nil). Diffed before and after
with the real parser on every row.

**P1 / P4 -- the new readers** (pure, refuse-unknown, every number in the text or plain arithmetic
on one: a unit into seconds, a percent into a fraction, a count into its jumps):

| function | answers |
|---|---|
| `Parse.Cooldown(rightText)` | a tooltip line's right text `N sec` / `min` / `hour cooldown` (decimals too) as seconds; the whole text must be that phrase, anything else nil. All 634 cooldown lines of the export read; no other right text does. |
| `Parse.Lockout(text)` | `cannot be <verb> again for N <unit>` as seconds (PW:S 15); nil without one. |
| `Parse.ManaSource(text)` | `{ kind = "rate", mana, period, dur }` from "restores / restoring N mana every P sec(onds)" (`dur` = the one "for D <unit>" in the same sentence, nil when none or two); `{ kind = "regen", regenPct, castingPct, dur }` from Innervate's "Increases ... Mana regeneration by N% and allows M% of ... Mana regeneration to continue while casting. Lasts D sec" -- all three required. Anything else nil. Over the export: Innervate, Blessing of Wisdom R1-R6, Greater Blessing of Wisdom R1-R2, Mana Spring Totem R1-R4, Mana Tide Totem R1-R3, nothing else. |
| `Parse.Targets(text)` | `targets = "single" / "party" / "chain" / "selfAndTarget" / "caster"`; party with `from = "target"` (PoH, Wild Growth: "the target and their party", `range` from "Party members must be within N yards of target") or `from = "caster"` (Holy Nova, Tranquility: "all [nearby] party members [within N yards]"); chain with `count`, `jumps = count - 1`, `falloff` (percent / 100), `partyOnly`; plus `belowPct` ("below N% Health"), `charges` ("N charges"), `lockout`. **Refuse-unknown:** a reach word left once every recognised phrase is taken out (party, raid, group, jump, members, allies, nearby, caster, charge(s), total / friendly targets, below N%), or two reaches in one text, answers `nil, "<reason>"` -- never "single". Enemy clauses ("to all enemy targets within 10 yards") are not a reach. |

`Parse.Targets` over every export text that reads a heal or an absorb: the direct heals and HoTs
single (Healing Touch, Regrowth, Rejuvenation, Renew, Heal, Flash Heal, Holy Light, Holy Shock,
Healing Wave, Riptide, Ice Barrier, ...), PoH /
Wild Growth party (target), Holy Nova / Tranquility party (caster), Chain Heal chain 3 / 0.5 /
party-only, Binding Heal self and target, Desperate Prayer caster, Divine Grace `belowPct = 50`,
PW:S `lockout = 15`, and **Contingency Plan refused** (`unrecognised reach: below 35%` -- a
"the next time this ally takes damage" trigger, like Prayer of Mending).

## Tests (`tools/parsecheck.lua`, `tools/data/parse-fixture.lua`)

Fixture: 5 description rows (Mana Burn R1 pinned at 0.5; Execute R5, Light's Vigil R1, R3
`refuse`; Holy Nova R2 pinned with its "your next" paragraph), a `targets` list (12), a
`cooldowns` list (9), a `manaSources` list (7) -- every row a talentsforever beta-client text,
except three marked `synthetic` (a new source tag in the header), each only a refusal's
specification. Checks:

- 2b (existing, per `refuse` row): +3 -- Execute R5, Light's Vigil R1, R3 refused;
- 4 (existing, "never raises"): now names the nine readers and feeds them the new rows;
- 13: +2 -- Mana Burn's decimal; Holy Nova R2 read despite its "your next" sentence;
- 14: +12 -- one per targets row (PoH party 40 yd; Chain Heal 3 targets 50 %; Binding Heal target
  and caster; Holy Nova 10 yd; PW:S lockout 15; Desperate Prayer; Divine Grace below 50 %;
  Tranquility; Wild Growth; Healing Touch single; Contingency Plan and a synthetic raid wording
  refused with a reason);
- 15: +1 -- cooldown lines in seconds (sec, min, hour, decimal), other right texts nil;
- 16: +1 -- the lockout phrase (PW:S 15; Renew, Holy Shock nil);
- 17: +7 -- one per mana-source row (Mana Tide R3 290 / 3 s / 12 s, Mana Spring R4 10 / 2 s / 5 min,
  Blessing of Wisdom R1 12 / 5 s / 1 h, **Innervate 400 % / 100 % / 20 s**; Life Tap, Mana Burn and a
  regeneration increase without its casting clause nil);
- 18: +1 -- Targets and ManaSource invent no number.

## Failing first (the parent's `Spells/Parse.lua`, the new tests in)

```
tools/run.sh tools/parsecheck.lua      # Spells/Parse.lua from e2b13f4
13 ok, 29 failed
  FAIL every pinned description reads exactly its heal, damage and absorb - tf Priest|Mana Burn|Rank 1: ... -> damage {min=5, max=5, school=Shadow}
  FAIL refused, not read as one direct hit: tf Warrior|Execute|Rank 5 - damage {min=15, max=15}
  FAIL refused, not read as one direct hit: tf Paladin|Light's Vigil|Rank 1 - heal {min=325, max=343} damage {min=175, max=189, school=Holy}
  FAIL refused, not read as one direct hit: tf Paladin|Light's Vigil|Rank 3 - heal {min=684, max=724} damage {min=380, max=410, school=Holy}
  FAIL no number is ever invented - tf Priest|Mana Burn|Rank 1: damage has 5 not in text
  FAIL Parse never raises, whatever it is given - Parse.Targets raised on nil
  FAIL T91: a decimal amount is one number (Mana Burn's 0.5, never 5) - ...
  FAIL T91 targets: ... (12)   FAIL T91: cooldown lines ...   FAIL T91: the lockout phrase ...
  FAIL T91 mana source: ... (7)   FAIL T91: Targets and ManaSource invent no number
```

With the change: **42 ok, 0 failed**.

## Suites, before and after

| suite | before | after |
|---|---|---|
| `parsecheck/forever` | 15 | **42** (+27) |
| every other suite | unchanged | unchanged |

`make check` (with the expected-counts line applied): **72 run(s), all passed**, 67 counted against
67 expected; `apicheck`: 8 Forever TOCs, 60 files, 48 distinct globals, **0 findings**;
`textcheck`: 9 TOCs, 98 files, **0 findings**; `luac -p Spells/Parse.lua` clean. `bookcheck`,
`tipcheck`, `spellsui`, `measurecheck`, `refcheck-selftest` unchanged (their books carry none of the
18 changed texts).

## Integrator lines

**`tools/data/expected-counts.json`:** `"parsecheck/forever": 42,` (was 15).

**CLAUDE.md, the `Spells/Parse.lua` row,** append:

> **T91** (2026-10-01, `docs/SPEC-next.md` 4.2 P0 d / P1 / P4): a decimal amount is one number
> (`NUM` with a frontier and a `.digits` tail; a stop after a digit detached first -- Mana Burn's
> `0.5`, never `5`); "N additional damage" is not a cast's hit (Execute, Ferocious Bite); a "your
> next" sentence is not read (Light's Vigil nil; Holy Nova keeps its own parts). New readers, all
> refuse-unknown: `Parse.Cooldown(rightText)` (`N sec / min / hour cooldown` -> seconds),
> `Parse.Lockout(text)` (`cannot be X again for N sec`), `Parse.ManaSource(text)` (`{ kind = "rate",
> mana, period, dur }` / Innervate's `{ kind = "regen", regenPct, castingPct, dur }`) and
> `Parse.Targets(text)` (`targets = single / party (from target or caster, range) / chain (count,
> jumps, falloff, partyOnly) / selfAndTarget / caster`, plus `belowPct`, `charges`, `lockout`; a
> reach word no shape claims -> `nil, reason`). Over the 1796 export texts `Description` changed
> on 18 rows only.

**`docs/TOOLS.md` section 1, the `parsecheck.lua` row,** append:

> Since **T91** (42): Mana Burn's decimal, Execute's "additional" amount and Light's Vigil's "your
> next" clause (refused), Holy Nova kept; `Parse.Targets` on twelve rows (party, chain, target and
> caster, caster, a lockout, below N %, two refusals), cooldown right texts, the lockout phrase,
> `Parse.ManaSource` on seven rows (Mana Tide, Mana Spring, Blessing of Wisdom, Innervate 400 % /
> 100 %; three nil), and no number invented by the new readers. `synthetic` rows are refusal
> specifications only.

**`docs/HISTORY.md`:** one line in the wave N1 entry -- "T91: `Spells/Parse.lua` reads decimals,
refuses 'additional' and 'your next' amounts; `Parse.Targets` / `Cooldown` / `Lockout` /
`ManaSource` (parsecheck 15 -> 42)."

No DECISIONS line (nothing on TBC changes: `Spells/Parse.lua` is Forever-only until T111), no
TESTING line (nothing visible until T95 reads the new fields), no TOC line, no `check.sh` line.

## Deviations and notes for the next tasks

- **"Mana Spring 290 / 3 s"** in the spec's row is Mana Tide Totem R3's text ("restores 290 mana
  every 3 seconds"); Mana Spring Totem R4 restores 10 every 2 seconds. Both are pinned.
- **Mana Burn reads `damage = 0.5`** as the spec's row asks ("Mana Burn 0.5"); that amount is per
  mana drained ("For each mana drained ..., the target takes 0.5 Shadow damage"), so T95's book
  will value Mana Burn at 0.5 per cast (it valued it at 5). Refusing a "For each ..." clause would be
  a one-line `PeriodicOrEitherAfter`-style test; not done, because the spec pins the reading.
- **Ferocious Bite R1-R5** also read nil now (same "additional" rule; an energy finisher, never a
  mana spell). Not in the spec's list; the corpus diff names it.
- **`Parse.Targets`' shape** is this task's design: `targets` uses the kit's words (`party`,
  `chain`, `selfAndTarget`, plus `single` and `caster`), so T95's book can store `entry.targets =
  t.targets` (bookcheck's `targets = party`) and T101 can map it onto its types. A party heal says
  `from` (target's party or caster's party); 4.5's engine reach treats both as the caster's party.
- **`Parse.Lockout`** is its own reader and also feeds `Targets`' `lockout` field.
- **Contingency Plan** still reads `absorb = 155` in `Description` (unchanged); its `Targets` is
  refused. It is a "the next time ... takes damage" trigger like Prayer of Mending -- a candidate for
  the same "not this cast" treatment in a later reading task.
- **Ice Barrier** ("Instantly shields you") reads `targets = "single"`: "you" is not a reach word
  (it is the subject of most texts). Its target is the caster; nothing in this task needs that.
