# T124 -- What if: compare like with like, and +Spell damage

Status: **ready** 2026-10-03. This is the author's feedback on 0.17.0's What if, from two in-game screenshots (Forever, a level-10 druid).
Version 0.17.1. It starts on master `0a96373`.

## The author's words

> "When we set up more Heal Power in what if it compare spells with and without stats
> override, as so the comparison is not valid"
>
> "also I need to have +spell damage in what if"

## 1. The footer compares like with like (`WI.Changes`, both lines)

The pane's footer is `WI.Changes(liveFam, whatFam)` (`Spells/WhatIf.lua:281`). Today it says, for example:

    Suggested: Rank 1 -> Rank 2. Rank 1 per mana 1.90 -> 6.83 (+259%).
    No change to the suggestion. Rank 1 per mana 1.28 -> 14.08 (+1000%).

The first number is the live rank and the second is the same rank with the what-if stats.
That is a spell with the override against a spell without it. So when the suggestion moves, the footer never says why the new rank wins.
The accent cells and their live / what-if hovers already show what the stats moved. The footer must not repeat that.

**The rule:** every number the footer prints comes from `whatFam`, the one book priced at the what-if stats. `liveFam` is read only for the live suggested rank's **id and rank number**.

- **The suggestion moved** (live suggested id differs from what-if suggested id). Name both ranks, then compare them, both read from `whatFam`:

      Suggested: Rank 1 -> Rank 2. With these stats Rank 2 gives 7.40 per mana, Rank 1 6.83 (+8%).

  The percentage is `MD.Words.Signed`. If the new rank gives less per mana than the old one, the rule did not pick it on per mana, so the footer adds the reason taken from the what-if entries:
  - the old rank is beaten (`dominatedBy` in `whatFam`): `Rank 1 is beaten by Rank N.`;
  - otherwise it fell under the size floor. Use `MD.Rules.SUGGESTED_FLOOR`, the same rule `Spells/RankRules.lua` uses: `Rank 1 is under 40% of Rank M's heal.` Rank M is `whatFam.maxKnown`, and for a damage family the word is "damage".

  Word it through `Spells/Words.lua` if it has a fitting sentence. Otherwise add a small helper there, so the words live in one place.
- **No change:** `No change to the suggestion.` and nothing more. The strip beside it already compares the suggested rank with the highest known at the same stats (`CompareText(s, fam.maxKnown)` in `UI/SpellsPane.lua`, on the what-if book).
- **Any nil input:** `No change to the suggestion.`, as today.

ASCII only, no bare pipe. Nothing else in the pane changes. Before relying on it, check that the strip, the chip, the cells and the RANKS note do not mix the two books. If one does, fix it by the same rule and say so in the report.

## 2. +Spell damage in What if (both lines)

Add a STATS row `damage`, labelled `+Spell damage`, to `WI.STATS`, right after `heal`. Use the same step and bigStep as heal, the same box with `-` / `+`, the same `Delta` beside it, and the same clear / live semantics. The pane already draws `WI.STATS` in order. Check that the STATS box still fits in the WHAT IF pane at every font offset; `tools/spellsui.lua` has the fit checks.

The typed value is the spell damage the caster would have. **Live** is the bonus of the school of the family on screen when the provider can tell; otherwise it is the first damage family's school (`DM.OrderFor(class)`'s first on TBC, the book's first damage family on Forever); otherwise nil.
The what-if moves **every school by the same delta** (typed minus live), so school-specific gear keeps its difference.
Only damage ranks move. Heal ranks ignore `damage` and damage ranks ignore `heal`.
An either-or family's other half (`altKind`, `entry.alt`) is out of scope: leave it as it is and name it in the report.

### TBC (`Spells/WhatIf_TBC.lua`, `Engine/DamageMath.lua`, `Spells/Book_Model.lua`)

- `WhatIf_TBC`'s `Sync` writes `MD.sim.damage`, the typed value, through the KEYS list. The file stays `MD.sim`'s only writer (whatifcheck's source scan).
- `Live()` gives `damage`.
- The what-if book's damage families must read it. Today `DM.Compute` reads `DM.Bonus(school)` live.
  - Add a way for the what-if build to price damage at `live(school) + delta`. For example, an optional context or override argument on `DM.Compute`, passed only by `Book:Build(true)`.
  - `DM.Compute` must never read `MD.sim` itself: the clock, the tooltip block (`Book:Get()`) and the live book stay on live numbers.
  - The live damage numbers stay byte-identical: `tools/bookshapecheck.lua`'s golden digests must not move.

### Forever (`Client/API_Forever.lua`, `Spells/Book.lua`, `Spells/WhatIf_Forever.lua`)

- Bind `SpellBonusDamage = "GetSpellBonusDamage"` on Forever; it is in `tools/data/forever_api.json`. Add it to `tools/adaptercheck.lua`'s `FOREVER_ONLY_NAMES` if that list needs it; `Client/API_TBC.lua` may already bind it. Treat a secret answer as unreadable, as `SpellBonusHealing` is treated.
- `Book:Bonus("damage", school)`:
  - read plain out of combat and kept per school;
  - in combat, or when the read is secret, return the last plain value per school, with `stale = true`;
  - nil before any reading.

  This mirrors the heal branch. `school` may be a number or the school's name; map names the way `Spells/Book_Model.lua`'s `Book:Bonus` does since `0a96373`. Then the Spells header's `+Damage` line shows on Forever too. Check `UI/SpellsPane.lua`'s header still reads right, and that `tools/spellsui.lua` agrees.
- `WhatIf_Forever`'s `CopyEntry` moves a `kind == "damage"` rank by `entry.bonus.counts x dDamage`, the same way it moves a heal: `ShiftPart` on `parsed.damage`, then `Book.Numbers(w, "damage")`.
  - This needs `entry.bonus` on damage entries. `ApplyBonus(v, "damage", ...)` (`Spells/Book.lua:816`) already estimates one. If `amount` / `of` need the damage bonus, fill them from `Book:Bonus("damage", school)`.
  - Leave `MeasureBonus` heal-only (a measured damage share is a later task) and say so.
- `ranksNote` counts the ranks of the kind the active stat moves.

## Owned files

- `Spells/WhatIf.lua`, `Spells/WhatIf_TBC.lua`, `Spells/WhatIf_Forever.lua`
- `Spells/Words.lua`, only if a footer sentence goes there
- `Engine/DamageMath.lua`, `Spells/Book_Model.lua`, `Spells/Book.lua`
- `Client/API_Forever.lua`
- `UI/SpellsPane.lua`, only if a mixed comparison or the box's fit needs it
- tests: `tools/whatifcheck.lua`, `tools/spellsui.lua`, `tools/bookcheck.lua`, `tools/bookshapecheck.lua`, `tools/adaptercheck.lua`

**Not yours** (the integrator writes them): TOCs, CLAUDE.md, docs/HISTORY.md, docs/TESTING.md, docs/DECISIONS.md, docs/TOOLS.md, CHANGELOG.md, `tools/data/expected-counts.json`, `tools/check.sh`.
For those, say in your report what each one needs: new counts per suite and flavour, and TESTING lines.

## Tests first

Commit the failing tests first, then the code that makes them pass.

1. `whatifcheck` section 8, rewritten:
   - The moved case prints both ranks' **what-if** per mana. Give the live family a deliberately different per mana for the same id, so a live number would show.
   - A test where the new rank's per mana is lower names the floor.
   - A test where the old rank is beaten names the beater.
   - The no-change case is exactly `No change to the suggestion.`
   - No digit of a `liveFam` per mana appears in any footer.
2. `whatifcheck`: the `damage` row is in `WI.STATS` right after `heal`, and set / clear behave like `heal`.
   - TBC: `MD.sim.damage` follows it, and Clear empties it.
   - TBC: a damage rank in `Get({ whatIf = true })` moves by coefficient x delta, and `Get()` does not.
   - Forever: the same through the provider.
   - Heal ranks do not move on `damage`, and damage ranks do not move on `heal`.
3. `bookcheck/forever`: `Book:Bonus("damage", school)` plain, stale in combat, secret -> last, nil before any, and a school name accepted.
4. `bookshapecheck/tbc`: the golden digests unchanged, which proves the live damage did not move.
5. `spellsui`, both flavours:
   - the STATS box with the new row fits at offsets -2..+2;
   - the footer equals `WI.Changes(liveFam, whatFam)` with the new words;
   - Forever's header shows `+Damage` once a reading exists.

Run the suites you touch, under both flavours where they have both: `tools/run.sh --flavour <f> tools/<suite>.lua`. Then run `make check` once at the end and report its result.
`luac` is `tools/.lua/lua-5.1.5/src/luac`.

## Report

Write `docs/tasks/T124-report.md` with:
- what changed, by file;
- the commits;
- each suite's count per flavour, before and after;
- the `make check` result;
- the deviations;
- the TESTING / CHANGELOG lines you propose.

Return about 2 KB and that path.
