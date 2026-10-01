# T106 -- class profiles: Paladin, Shaman, Priest (Forever)

Status: **built** 2026-10-01 on branch `next/T106` (base `319f6cb`), wave N4, waiting for the
integrator.

Spec:
- `docs/SPEC-next.md` section 11 row T106.
- 2.1, the profile.
- 4.2 P2: every class but the druid gets the solver strategies.
- 4.3, decision 7: Paladin -> Shaman -> Priest. Coach and practice are granted when the class's
  fixture passes. The priest has no Power Word: Shield until T109.
- 4.5, the group assumption.
- Section 3, principles 8 (heals a plan cannot choose are kept as recorded), 9 (no value from
  memory; every rule VERIFY) and 10 (TBC changes only by decision).
- 9.1, the author's answers.

Research: `docs/research/next/R-classes.md` 1.1 (what each class reads), 1.3 and 4.

Needs T99 (the capability gates) and T101 (the kit by shape). Both are in the base.

**The branch needs its TOC lines (below) to load in the game.** The TOCs are integrator-owned and
were **not** edited in a commit. Until the TOCs list the three profiles:
- `tools/classcoach.lua` and `tools/profilecheck.lua` load them where the TOC will put them, so
  their counts are the same with or without the TOC lines.
- Every suite was also run with the TOC lines applied in the working tree. The TOCs were then
  restored, as T89 and T100 did.

**Three files outside the row's owned list were changed** (deviation 1): `Engine/SimPlanner.lua`,
`Spells/Profiles.lua` and `tools/capscheck.lua`. No other wave-N4 task owns any of them (the
section 11 table). They are isolated in commit 2, `bfb637f`. The profiles in commit 3 depend on
it: they use the new `unmodelled` field.

## What was built

### The three profiles (`Data/Profile_{Paladin,Shaman,Priest}_Forever.lua`, new)

Each profile carries names, kit types and rule choices only, never a spell number. Every number
comes from the client's own text through `Spells/Book.lua`: the heal, the cost, the cast, Chain
Heal's jumps and falloff, and the cooldowns from the tooltip line (Holy Shock 10 s, Riptide 6 s,
T95).

The families each profile names are the ones T101's kit would already build by shape. Naming
them fixes their keys, order, kit types and HoT slots, so a later change in reading cannot move
them silently.

Every rule is commented VERIFY: the kit types, the 4.5 reach, the 3 s HoT ticks and the crit
school.

| class | crit school | families (kit type) | HoT slots | `unmodelled` |
|---|---|---|---|---|
| PALADIN | 2 (Holy) | HolyLight, FlashOfLight, HolyShock (all `direct`) | none | Light's Vigil, Lay on Hands, Divine Favor |
| SHAMAN | 4 (Nature) | HealingWave, LesserHealingWave (`direct`), ChainHeal (`chain`), Riptide (`hybrid`) | Riptide | Healing Stream Totem, Nature's Swiftness |
| PRIEST | 2 (Holy) | LesserHeal, Heal, GreaterHeal, FlashHeal (`direct`), Renew (`hot`), PrayerOfHealing, HolyNova (`group`), BindingHeal (`selfAndTarget`) | Renew | Power Word: Shield, Contingency Plan, Desperate Prayer, Divine Grace, Penance, Prayer of Mending, Lightwell, Vampiric Embrace, Inner Focus, Power Infusion |

What every profile shares:
- **Caps:** `clock`, `tooltip`, `rankTable`, `coach` and `practice`. The profiles have no
  `simulate`: that is the TBC Simulate window, which no Forever TOC asks for. On Forever,
  `coach` also asks `MD.KitLive` (T99): a book whose kit prices no heal is still refused, and the
  kit gives the reason.
- **Planner:** each profile has a `families` list only. There is no `rules`, `bindable` or
  `hotRule`, so the solver coaches these classes. The threshold rules are the druid's tactics;
  every one of them names a druid family.
- **No Power Word: Shield family for the priest** until T109. The kit also skips the shield by
  name (an absorb). A fight that casts it keeps the cast and its mana as recorded, and the card
  names it.

### Outside the row (commit 2): what the classes need from the coach

The row's test asks that the solver coaches each class's fight and that the card names the spells
the kit does not model. At the base, neither could happen:

1. **The card raised when its best plan was the solver's.** `SP.CardLines` read the threshold
   fields of the best plan. A solver plan has none, so the card failed at line 1214 with
   `attempt to compare number with nil` (`best.rollStacks > 0`).
2. **The coach never tried the solver.** `SP.Coach` and `SP.CoachAsync` compared and searched the
   druid's threshold rules only. Every rule names a druid family, so for a paladin each one casts
   nothing and lets the party die. The rows read `0 used ... lowest 0%`.
3. **Nothing on the card named an unmodelled spell.**

The changes:

- **`Engine/SimPlanner.lua`**
  - `SP.SolverOnly(kit)` is true when the kit's profile (`MD.Profiles.ForKit`, never the
    logged-in player's) names no rule set.
  - For such a kit:
    - `SP.SolverCandidates(rec, kit)` returns the solver's causal strategies (`SP.SOLVER_COACH`:
      `solver-blind`, `solver-frugal`, `solver-near`), with rows named solver, frugal and
      reactive.
    - `SP.Coach` compares those strategies in place of the rules' baselines.
    - `SP.CoachAsync` runs `SP.Coach` on the next frame instead of the rules search. It returns a
      cancellable handle, as a search does.
  - A solver best is written as three lines:
    1. `Anyone falling through the danger line: the cheapest heal that holds them above it`
    2. `Otherwise the heal that saves the most health-seconds per mana, if at least <minValue>`
    3. `Otherwise wait - N% of the fight`
  - `SP.Unmodelled(rec, kit)` names the heals a fight cast that the kit does not model, in the
    order they were first cast. It draws on the kit's `MD.SpellData.skipped` and on the kit
    profile's `unmodelled` list. The card line is `not modelled, kept as recorded: Power Word:
    Shield, Desperate Prayer`.
  - The druid's profiles name their rules (`"druid"`) and no `unmodelled`, and TBC's kit has no
    skipped list. So **a druid's coach and card are unchanged on both lines** (checked below).
- **`Spells/Profiles.lua`:** the optional `unmodelled` field, a list of the spellbook's names.
  `Validate` refuses a name that is also one of the profile's family names, because a named
  family is modelled.
- **`tools/capscheck.lua`:** the non-druid who logs in is now a **mage**, a class with no profile
  on either line. With the priest profile listed, the old suite fails 8 of its 32 Forever
  assertions ("a priest is given the generic profile" and the seven not-modelled wordings). The
  new one passes 32 of 32. The counts are unchanged (forever 32, tbc 34); only the wording moves
  from "Priest" to "Mage".

## Tests

### Failing first (commit `4a4a485`: the tests on the parent's code)

| suite | on `319f6cb` | after |
|---|---|---|
| `classcoach/forever` (new) | 0 ok, 3 failed (no profile file for any class) | **39 ok** |
| `profilecheck/forever` | 46 ok, 7 failed (`unmodelled` undeclared; three profiles missing) | **59 ok** (64 with the talentsforever cache) |
| `profilecheck/tbc` | 44 ok, 1 failed (`unmodelled` undeclared) | **45 ok** |
| `capscheck/forever` with the TOC lines | 24 ok, 8 failed (a priest now has a profile) | **32 ok** (count unchanged) |

During the build, with the profiles in place and the parent's planner, `classcoach` failed on
every card check for all three classes: the card raised at `SimPlanner.lua:1214`.

### `tools/classcoach.lua` (new, forever, 13 assertions per class)

For Paladin, Shaman and Priest in decision 7's order, each with its level 60 book from
`tools/stub_books.lua`, the suite checks:

1. **The profile.** The class logs in with its own profile and is granted coach and practice
   (`Can` true, with the Replay module on).
2. **The kit.** The book becomes a valid kit (`Kit.Validate`) stamped with the class.
   `ForKit(kit)` is the class's profile. Every family the profile names is in the kit index with
   the profile's kit type and a priced top rank. `MD.SpellData.familyOrder` starts with the
   profile's order. `SM.HotSlots(kit)` puts the profile's HoTs in slots 1..n. The unmodelled
   spells are not in the kit.
3. **The fight.** A synthetic five-man v3 fight passes all eight gates. The fight is 60 s: the
   tank is hit every 2 s, two group-wide hits land, and a few hits land on the damage dealers.
   The class casts its heals, including Holy Shock, Chain Heal and Riptide, and for the priest
   Prayer of Healing, Binding Heal and Holy Nova. It also casts one or two unmodelled spells:
   Divine Favor, Nature's Swiftness, or Power Word: Shield with a Desperate Prayer whose heal is
   kept as recorded. The fight is made consistent the way `coachforever` does it: own heals sit
   where the engine lands them, and the modelled mana and the meter's own total are the engine's.
4. **The coach.**
   - The solver coaches it: its plan casts at least two of the class's families and nobody dies.
   - `SP.Coach`'s best is a solver plan, with no threshold-rule rows.
   - The card is ASCII with no bare pipe.
   - The card names the class's unmodelled spells.
   - The live `/st coach 1` leaves a solver plan for the replay and prints the solver's lines and
     the unmodelled line.
   - The group assumption line appears for Shaman and Priest and not for the Paladin.
5. **Practice.**
   - Practice binds every profile family.
   - A 40 s party session against the fake clock records at least 6 casts with
     `rec.kit.profile == class`.
   - That practice recording passes its gates.
6. **Causality.** With the solver plan on this kit, a burst at 45 s changes nothing cast before
   it.

### `tools/profilecheck.lua` (+13 forever, +1 tbc)

- The three profiles validate against `Kit.TYPES` in the registry loop (+6).
- `Validate` refuses an `unmodelled` name that is also a family name (+1, both flavours).
- Per class (+6):
  - Every name the profile carries is in its committed book fixture (`tools/data/books`). This
    covers the family names and the `unmodelled` names, and it is a real check without the
    talentsforever cache.
  - The caps are exactly `clock coach practice rankTable tooltip`.
  - The planner has no rules (solver only).
  - The crit school is Holy 2, Nature 4 and Holy 2.
  - The priest has no Power Word: Shield family.
- The derivation check ("never reads `MD.ClassProfile`") now logs in a **mage** with a test mage
  profile. It was a priest, whose profile now ships. With `tools/.cache/talentsforever.json`
  present, the cache check also passes for PALADIN, SHAMAN and PRIEST, families and `unmodelled`
  alike (64 ok).

### Everything else

`tools/check.sh` on the committed tree, without the TOC lines:
- **87 run(s), all passed.** 82 counted against 81 expected.
- Three NOTEs, which the counts lines below answer.
- apicheck **0 findings** (69 files); textcheck **0 findings** (108 files).

With the TOC lines applied in the working tree:
- 87 run(s), all passed, with the same three NOTEs.
- apicheck 0 findings over **72** files; textcheck 0 findings over **111** files (the three
  profiles are included).
- `releasecheck`'s Forever package has 47 files instead of 44.

`luac -p` is clean on every changed file. No default was registered: `defaultscheck` is unchanged
(forever 52, tbc 49).

**Compared byte for byte with the base's own run** (`319f6cb`, `tools/check.sh` in this worktree
before the first edit), every suite output is identical except:
- The four suites above.
- Lines that differ between two runs of the base itself: table and function addresses, the
  `[sim] search N evaluations`, `replay ... N ms` and `search finished ... ms` timing lines,
  `releasecheck`'s file count, and the apicheck and textcheck file counts with the TOC lines.
- `simcheck/tbc`'s run-cost line reads `3.58 KB/run with 1500 events` where the base read
  `3.57`. That is a 10-byte difference in a heap measurement. The engine is untouched: putting
  the base's `SimPlanner.lua` back gives 3.57 again, so it comes from the file's size. The
  assertion ("run cost is flat") passes either way, and T101 reported this same line as
  "3.57 / 3.58".

**The author's recordings were compared before and after**, from copies of both live
SavedVariables files taken 2026-10-01:
- Healroot's Forever file: `tools/import.lua list`, then `report` and `coach N force` for 1..8 and
  p1..p4.
- The anniversary file: `tools/strategies.lua --file`, then `tools/import.lua coach 1..3 force`
  under tbc.
- Everything is **identical** except the `(the search ran across N stub frames)` timing line on
  two Forever cards and one TBC card. No druid card gains a line.

## Integrator lines

**`SpellTuner_Mainline.toc` and `SpellTuner.toc`** (identical): after `Data\Profile_Druid_Forever.lua`,
add the three lines

```
Data\Profile_Paladin_Forever.lua
Data\Profile_Shaman_Forever.lua
Data\Profile_Priest_Forever.lua
```

No TBC TOC change and no module TOC change. The profiles are read through `MD.Profiles` at
`CORE_LOGIN` and by the Replay module's kit, and nothing derives from them at file load.

**`tools/data/expected-counts.json`:**
- `"classcoach/forever": 39,` (new)
- `"profilecheck/forever": 59,` (was 46)
- `"profilecheck/tbc": 45,` (was 44)

`capscheck` is unchanged (forever 32, tbc 34). **`tools/check.sh`:** no change, because
`classcoach.lua` is a suite and is picked up by the glob.

**`docs/DECISIONS.md`**, a new entry:

> ## Paladin, Shaman and Priest coached on Forever; the coach's solver for every class but the druid (2026-10-01, T106, decision 7)
>
> On Forever the paladin, the shaman and the priest each have a profile
> (`Data/Profile_<Class>_Forever.lua`). It names the families the kit models, their kit types,
> the HoT slots and the class's healing spells the engine does not model. Every rule is VERIFY.
> Each is granted coach and practice, because `tools/classcoach.lua` passes on its level 60 book
> fixture: a valid kit, a synthetic party fight through the eight gates, the solver's coach,
> practice, and causality. The priest is coached without Power Word: Shield until T109; a shield
> cast is kept as recorded and named on the card.
>
> The threshold rules are the druid's tactics. Every rule names a druid family, so for another
> class they cast nothing. A kit whose profile names no rule set is therefore coached on the
> solver's three causal strategies (no intuition, frugal, reactive). `SP.Coach` compares those
> instead of the rules' baselines, and `/st coach` runs that comparison instead of the rules
> search. The card states the solver's own three steps (the danger line, health-seconds per
> mana, wait) where the rules' five thresholds were.
>
> The card also names the heals a fight cast that the kit does not model: `not modelled, kept as
> recorded: ...`. These come from the kit's skipped heals and the profile's `unmodelled` list.
>
> The druid's profiles name their rules and no unmodelled spells, and TBC's kit skips none. A
> druid's coach and card are unchanged on both lines: every suite, Healroot's twelve Forever
> reports and coach cards, and the author's TBC strategies report and coach cards are identical
> before and after. `capscheck` now uses a mage as its class with no profile; the wording on its
> test lines moves from "Priest" to "Mage".

**`CLAUDE.md`:**
- New rows, after `Data/Profile_Druid_Forever.lua`'s row:

  > | `Data/Profile_Paladin_Forever.lua` / `Data/Profile_Shaman_Forever.lua` / `Data/Profile_Priest_Forever.lua` | **The first three classes after the druid** (T106, `docs/SPEC-next.md` 4.3, decision 7; Forever main TOCs after the druid's). Names, crit school, families and kit types (Paladin: Holy Light, Flash of Light, Holy Shock `direct`; Shaman: Healing Wave, Lesser Healing Wave `direct`, Chain Heal `chain`, Riptide `hybrid`; Priest: Lesser Heal, Heal, Greater Heal, Flash Heal `direct`, Renew `hot`, Prayer of Healing and Holy Nova `group`, Binding Heal `selfAndTarget`), HoT slots, the solver only (no `rules`), `unmodelled` (the healing spells the card names when cast), every rule VERIFY; coach and practice granted because `tools/classcoach.lua` passes on each book fixture; no Power Word: Shield until T109. No numbers |

- Append to `Spells/Profiles.lua`'s row: "**T106:** the optional `unmodelled` field: the class's
  healing spells the engine does not model, by name, never a family's (`Validate` refuses one)."
- Append to `Engine/SimPlanner.lua`'s row: "**T106:** `SP.SolverOnly(kit)` (the kit's profile
  names no rule set) -> `SP.SolverCandidates` (`SP.SOLVER_COACH`: `solver-blind` / `-frugal` /
  `-near` as solver / frugal / reactive) replace the rules' baselines in `SP.Coach`, and
  `SP.CoachAsync` compares them on the next frame instead of the rules search; the card writes a
  solver best as its three steps; `SP.Unmodelled(rec, kit)` -> the card's `not modelled, kept as
  recorded: ...` (the kit's skipped heals and the profile's `unmodelled`). A druid's coach and
  card unchanged."
- In the `tools/` row, after `tools/profilecheck.lua`'s sentence: "**`tools/classcoach.lua`**
  (T106, forever): per class (Paladin, Shaman, Priest) the book fixture -> a kit stamped with the
  class's profile -> a synthetic party fight through the eight gates -> the solver's coach (`SP.Coach`
  and `/st coach`), the card naming the unmodelled spells and the group assumption -> practice
  -> causality."

**`docs/TOOLS.md`** section 1:
- `classcoach.lua` (new, forever, 39): the row above.
- `profilecheck.lua`: "Since **T106** (forever 59, tbc 45): the three Forever class profiles
  against their book fixtures (`tools/data/books`), solver only, their caps and crit schools;
  `Validate` refuses an unmodelled name that is a family's; the derivation is proven with a mage
  logged in."
- `capscheck.lua`: "Since **T106** the class with no profile is a mage (counts unchanged)."

**`docs/TESTING.md`** (section 46, in-game check 11 "Other healers"): add these steps.
- On a Forever paladin, shaman or priest alt, Reports -> Review's Coach is on. `/st coach N` on a
  pull that passes its gates prints a card whose rows are `solver`, `frugal` and `reactive`, and
  whose steps start `1. Anyone falling through the danger line`.
- A pull with a Power Word: Shield, Desperate Prayer, Healing Stream Totem, Lay on Hands or
  Divine Favor in it carries `not modelled, kept as recorded: <names>`.
- A pull with a Prayer of Healing, Holy Nova, Binding Heal or Chain Heal carries the group line.
- Simulate -> Practice binds the class's heals without an import.

**`docs/HISTORY.md`**: the integrator's wave entry ("T106: Paladin, Shaman and Priest profiles
on Forever, coach and practice granted by `tools/classcoach.lua`; the coach uses the solver for
every class but the druid, the card names unmodelled heals; classcoach 39 (new), profilecheck
46 -> 59 / 44 -> 45").

## Deviations and notes

1. **Files outside the row: `Engine/SimPlanner.lua`, `Spells/Profiles.lua` and
   `tools/capscheck.lua`.**
   - The row's own test cannot pass without the first two. The card raised on a solver best, the
     coach never tried the solver, and nothing named an unmodelled spell (see "Outside the row"
     above).
   - `capscheck` fails as soon as the priest profile is listed, because it logged in a priest as
     its class with no profile.
   - No wave-N4 task owns any of the three files. They are isolated in commit `bfb637f`. The
     profiles commit depends on it (the `unmodelled` field), so take both or neither.
2. **`unmodelled`, a new profile field.**
   - Only the priest's kit skips healing spells by name (`MD.SpellData.skipped`: the shield,
     Desperate Prayer, Divine Grace, Contingency Plan).
   - The paladin's and shaman's heals that are not modelled (Lay on Hands, Light's Vigil, Healing
     Stream Totem) are kindless: the parser refuses their texts, so nothing could name them as
     heals. The profile now names them.
   - The card names only spells the fight actually cast.
   - The spec lists a profile's contents as "names, critSchool, families and kit types,
     hotSlots". `unmodelled` is names.
3. **No `simulate` capability.** The druid's Forever profile has it, but it is the TBC Simulate
   window and nothing on the Forever TOCs asks for it. The three new profiles grant only what is
   tested.
4. **No cooldown in a profile.** Holy Shock's 10 s and Riptide's 6 s come from the book's tooltip
   line (T95), as T101's kit already reads them. The profile would override the book, and a
   typed number would be a value from memory.
5. **Holy Shock under Light's Vigil** keeps its 10 s cooldown in plans, which is pessimistic. A
   recorded Holy Shock inside the cooldown is replayed as recorded (T90). This is unchanged from
   X9 in the spec.
6. **Wild Growth stays a by-shape family on the druid's kit** (T101). The druid's profiles are
   unchanged, so the druid names no `unmodelled` and its card gains no line.
7. **The rules search no longer runs for a non-druid's `/st coach`.** `SP.strategies[rec.id]`
   therefore stays empty for such a fight. `/st coach N safe` / `health` / `cheap` / `regen`
   then says to coach first, as before a search. Offering the solver strategies under those four
   objective names is left for later.
8. **Not owned and not changed: `Stream_Forever.lua`'s `FAMILY_KEY`** (a recording's
   `initial.known`). It still holds the druid's names, so `MaxRankBinds(known)` binds a class's
   family only when the fight cast it (T101's note 7). The classes' coach reads
   `BindsFromRecording`, which is not affected.
