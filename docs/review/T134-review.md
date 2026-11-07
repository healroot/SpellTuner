# T134 review -- the launch talents on Forever: Bloom and What if -> Talents

Reviewer: independent adversarial review (Opus 5.5), 2026-11-07.
Diff: uncommitted, `git diff 8e65d28` plus `docs/tasks/T134-forever-launch-talents.md` and
`tools/talentwhatifcheck.lua` (task `docs/tasks/T134-forever-launch-talents.md`).
Verdict: **pass with minors**: no blocker, no major, 11 minors. The numbers are right for the druid
the author asked about. The minors are words that say something the number does not, edges of other
classes, and three tests that pass with the code they guard broken.

Scenarios were run in a scratch copy (`/tmp/T134-rev`) against the real code under `tools/run.sh
--flavour forever`; mutations were made there only. `tools/check.sh` was not run (the brief forbids
it: already running).

## What was verified

- **Direction and order of the What if** (`Spells/WhatIf_Forever.lua` TalentPlan, ScalePart,
  ApplyTalents): every move is live-to-typed. Multipliers are `(1 + typed) / (1 + live)`, a periodic
  scope on `over` / `tick` only, the cast is `cast + live - typed`, cost percents are summed then
  `(100 - typed) / (100 - live)`. The +healing move runs after, on the moved share. Run: Gift of
  Nature 5 typed to 0 takes Healing Touch 210 -> 190.9 and its share 0.7854 -> 0.714.
- **The live book is not written.** ApplyTalents writes only the copy; `e.parsed`, `e.cost` and
  `e.bonus` are copied before they change; `talentwhatifcheck` section 6 asserts it.
- **No Bloom double-add.** `Numbers` derives `value` from `parsed`, never from a previous `value`;
  scans build fresh entries, and a stale copy keeps only `desc` and `parsed`. A talent in two tables
  (Naturalist cast and multiplier, Improved Wrath cast and cost) applies two distinct effects.
- **Nothing downstream reads Bloom by accident.** `Spells/Measure.lua` and
  `Modules/SpellTuner_Replay/Kit_Forever.lua` read no `.value`; the bonus fit reads
  `e.textValue or e.value` (Book.lua MeasureBonus); a Spirit move changes `value`, so `Sig` moves
  the generation.
- **Secrets.** `ST.API.Spirit()` lives in `Client/API_Forever.lua`, `UnitStat`'s second return, with
  plain-or-nil handling; `Book:Spirit` keeps the last plain value; UNIT_AURA, gear and level mark the
  book dirty, so Spirit is re-read out of combat.
- **`Coefficients.FromRow`**: `(share + tickShare * (tf - 1)) * p * m`, the tick factor gated on
  `talentMult.kind == kind`; the coefscheck oracle for Regrowth (0.286 + 0.071 x 7 x 1.10) is right.
- **Generators reproduce the tree.** `python3 -I tools/buildtalents.py` and `tools/buildcoefs.py` on
  `tools/.cache/talentsforever.json`: both diffs empty. Healer talents were compared by hand with the
  sentences: Genesis, Gift of Nature, Moonglow, Naturalist, Tranquil Spirit, Living Spirit, Spiritual
  Healing, Twin Disciplines, Healing Light, Improved Healing, Tidal Focus, Purification, Healing Way.
  Binding Heal and Lightwell are absent from the priest's launch spellbook, so the profile change is right.
- **`docs/TESTING.md` section 56**: rows of steps 1 and 4, the 15% of step 3 and the 0.5 s and 10% of
  step 4 match the tables. Step 2's "Heal rises" holds for the Heal column and for `Total` (the
  over-time-only card line stays at the text's number, and the Bloom row sits under it).
  `CHANGELOG.md` `## Next` is accurate.
- Suite run: `talentwhatifcheck` 28 ok, 0 failed; `spellsui` (forever) 63 ok with my probe added.

## Minor

**m1 -- `Spells/WhatIf_Forever.lua:100,252` with `UI/SpellsPane.lua:1718`: a cast talent typed down
to an instant loses its own row.** `w.cast` reaches 0, `castKind` stays `"cast"`, and `classRowsFor`
is asked about the what-if family, where `CastRuleHits` needs `e.cast > 0`. Run, warlock with
Improved Corruption 3 on a 0.8 s Corruption: typed 5 gives cast 0, castKind `cast`, and
`ClassRowsFor` empty while `Get` still says 5. The row vanishes under the cursor, so only Clear takes
it back, and the card says `0.0 s`. A warlock who really has rank 5 reads cast 0 live, so gets no row
and cannot try a lower rank. Improved Ghost Wolf's `{ 1, 3 }` has the same shape (read, not run); no
healer's cast talent reaches 0. Ask `classRowsFor` about the live family, and set `castKind` when the
cast reaches 0.

**m2 -- `Spells/WhatIf_Forever.lua:247`: "amount healed" talents move an absorb, an assumption nobody
wrote down.** Run, priest: typed Spiritual Healing 3 takes Power Word: Shield 100 -> 110, Twin
Disciplines 5 takes it to 105, and the rows appear on that family; the live `talentMult` carries the
same factors into the share words. The sentences say "amount healed" and "damage and healing"; a
shield heals nothing. Neither the task nor `docs/DECISIONS.md` mentions it. If the client does not
apply them, a priest compares a shield 10% too good per mana. Either mark it VERIFY in the words and
the decision log, or leave absorbs out until `docs/TESTING.md` measures it.

**m3 -- `Spells/WhatIf_Forever.lua:246`: Twin Disciplines moves only Holy Nova's heal half.** Its
sentence is "damage and healing of your instant cast spells". Run, priest, typed 5: heal 53 -> 55.65,
`parsed.heal.min` 51.45, while `alt.value` stays 28 and `parsed.damage.min` 26. T133's m3 recorded the
limit for the live share, when no damage multiplier reached these spells; T134's Twin Disciplines is
the first, and here it moves a shown number, so the note no longer covers it.

**m4 -- `Spells/Words.lua:969` with `Spells/WhatIf_Forever.lua:291`: a moved share still reads as
measured.** ApplyTalents appends " (what if talents)" to `why`, but the fit branch of `W.Bonus` never
prints `why` and keeps the range. Run: Genesis typed on a rank measured at 0.80 prints `88% measured
(0.80-0.80, 4 readings, +0..+450), 4 Sep`. Nothing measured 88%, and the range beside it excludes it.

**m5 -- `Spells/WhatIf_Forever.lua:291`: the estimated words name the live talent under the typed
one.** Run: Gift of Nature 5 typed to 0 prints `counts ~71% estimated (71.4% x1.10 Gift of Nature 5
(talentsforever, predicted) (what if talents))`. The 71% is right; the `x1.10 Gift of Nature 5` it
claims is exactly the factor just taken away.

**m6 -- `UI/SpellTip.lua:398`, `Spells/Words.lua:350`, `UI/SpellsPane.lua:327-329`: Bloom is in numbers
that do not say so.** The task requires the assumption "said in the words". The tooltip's Bloom line
is a detail line (behind the key), while the plain block prints Per mana and, on Regrowth, `Total`
with Bloom in them: Hit 176, Over time 154, `Total` 710 at Spirit 380, with nothing naming the other
380. The Heal and Total column header tips still say "from the spell's own text", and for a druid who
has Bloom that column is text + Spirit.

**m7 -- `Spells/WhatIf.lua:119-121`: the class-row path of `Clean` accepts infinity.** The stat path
refuses it two branches above; the row path does not, Spirit has no `max`, and the box hands
`WI:Set` raw text. Run: `WI:Set("spirit", "1e999")` returns true and `Get` gives `inf`; Rejuvenation's
value, per mana and per second become `inf`, the card line reads `+-9223372036854775808 if it runs out
(100% of -9223372036854775808 Spirit)`, and the Summary says `Spirit inf`. Nothing raises.

**m8 -- `Spells/WhatIf_Forever.lua:464`: the sentence omits what the task says it says.** The task:
"Not moved, and the sentence says so: crit, durations, regen, stat-to-bonus, spells a talent teaches,
procs, Oath of Light." The sentence names crit, durations, regen and taught spells. Failure: a druid
types Spirit 500 and only Bloom moves; nothing says Natural Instinct's Spirit-to-bonus does not. And
on a family no talent touches, `UI/SpellsPane.lua:1755-1769` shows the sentence alone, with no title
and no rows, so "do not move" has no referent. Run: `ClassRowsFor` nil with the note still returned.

**m9 -- `UI/SpellsPane.lua:1780` with `tools/spellsui.lua:3675`: Rejuvenation's rows overflow the
drawer at font +2, and the fit test cannot see it.** Probe, using T125's measured wrapping, Rejuvenation
with all five talents and Spirit typed, a one-sentence footer: contents 504 / 510 / 516 / 543 / **585**
against 560 at offsets -2..+2. The drawer does not scroll, so the footer's end is lost, and a longer
footer makes it worse. T125's rule is "inside the drawer at -2..+2". The T134 test asserts `fit` at
offset 0 only, with nothing typed and the stub's unwrapped height: it reads 315 / 560.

**m10 -- `tools/talentwhatifcheck.lua:145-159` and `:325-331`: two tests pass with what they name
broken.** Mutation 1: MeasureBonus fed `e.value` instead of `e.textValue`: test "3 the bonus fit reads
the text" still gives 0.8, 28 ok, because a constant Spirit only offsets the line and the slope cannot
see it. It needs a Spirit that moves between readings. Mutation 2: the cost percents taken by
`math.max` instead of a sum: 28 ok. Test "5 cost talents add" types one talent, so "add" is never
exercised. The only pair that exists is Improved Wrath + Moonglow on Wrath.

**m11 -- `CLAUDE.md:13`, `docs/TESTING.md:2520`: wrong pointers.** The Current state says the
launch talents are tested in "`docs/TESTING.md` §51", which is the TBC gear and enchant freeze; T134's
section is 56. And section 56 was added after the file's closing `## Reporting` block, unlike its
neighbours' reading order, so the instruction to paste results comes before it.

## Not findings

- Living Spirit typed with a typed Spirit gives Spirit x 1.15: the task's contract and the suite both
  say so, and the card names the resulting Spirit.
- `cost.percent` is not moved: a percent-only rank has no per mana anyway. Whether the launch client
  ever answers percent only was not verifiable here.
- Hybrid under Genesis: the copied share moves by the whole-spell ratio. An approximation the task
  accepts in writing.
- Wrath and Entangling Roots in `tools/coefscheck.lua`: lo and hi set to the want. The comment explains
  why (Naturalist doubled, no measurement yet) and `Near3` still checks the number.
- Light's Vigil's damage oracle 0.429 -> 0.143: the row is the generator's, and the generator
  reproduces the file from the export.
- Bloom's flat amount, its full-duration assumption and its absence from Practice, Coach and replay are
  declared in the task and VERIFY in `docs/TESTING.md`; in-game truth was not checkable here.
- EXPIRY_SHAPE ignoring Bloom's dispel clause (50% of Spirit): noted in Book's comment.
- This is a first review; it contradicts no other review.

## Fixed (2026-11-07, before the first commit of T134)

m1 rows asked of the live family, `castKind` follows the cast. m2 an absorb only by a talent naming the
spell (`Book.MultMatches`; the live multiplier too; `docs/DECISIONS.md`). m3 both halves move, each by
the talents that reach it. m4, m5 `bonus.movedFrom` and its own words. m6 the Bloom line moved from the
detail lines to the plain block, `ST.SpellsLine.valueNote` on the Heal and Total tips; the footer's
"Values come from the spell's own text" stays. m7 infinity refused. m8 the sentence names them all; a
family with no rows says only that. m9 the drawer grows to its contents rather than scroll, tested at
-2..+2. m10 Spirit moves between the fit's readings; the Wrath pair. m11 section 56 before Reporting.
