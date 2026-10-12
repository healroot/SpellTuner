# T130b: review fixes for T130 (every feature for every TBC class)

Review: `/home/penek/.claude/jobs/3d41dc31/tmp/T130-review.md` (read it first). Branch
`tbc-priest-fixes`, on top of a5f5616. The druid's behaviour must not change on either line.

## M1. Coach refuses a real non-druid fight (spend-coverage gate)

`ST:ClassifyCast` (`Data/DruidSpells.lua:66-92`) knows only druid spells (SpellData, `DS.byName`),
so a priest's Power Word: Shield / Prayer of Mending / Dispel, a shaman's totems, a paladin's
Cleanse / Judgement / Blessings classify `unknown`; above 10% of a fight's mana
`SM.GateSpend` (`Engine/SimModel.lua:2183-2205`) fails and Review/Coach refuse.

- On TBC, when the class has its own book (`RankMath:IsClassBook()`), ClassifyCast also
  recognises: the class book's spells (`ST.BookTBC`, heal), the profile's unmodelled names,
  damage families, and a per-class utility list in the class's TBC profile (names, kind
  `utility` / `damage` / `cc`, each row `-- VERIFY` as in `Data/DruidSpells.lua`: a wrong row
  costs a label, never a number). No heal value, no formula.
- The druid's classification is unchanged (DS.byName first for the druid).
- Test (`tools/tbcclasscheck.lua`): for each of Priest, Shaman, Paladin, give the
  unmodelled cast a real cost (~15% of the fight's mana, as the reviewer's repro) and
  assert the spend-coverage gate passes and Coach runs; also one cast of a name on the
  utility list.

## M2. Replay strategy chooser offers druid rules strategies to a solver-only kit

`UI/ReplayWindow.lua:2244` lists `rules` / `rules-hots`; the callback at `:1479-1500` builds
rule plans whose `Plan:Decide` reads druid binds only. When `SP.SolverOnly(rp.kit)` is true,
skip entries with `kind == "rules"` and guard the callback the same way (fall back to the
default solver strategy). Applies on both lines (correct for Forever non-druids too). Druid
unchanged; `tools/replayui.lua` counts unchanged; add a check where a suite already
drives the replay with a non-druid kit (tbcclasscheck or classcoach) that no `rules` entry is
offered.

## Minors

- m1: the Simulate "no druid binds" check (`tools/tbcclasscheck.lua:1321-1338`) cannot fail;
  make it assert every plan bind key belongs to the class's own families.
- m2: add a recorded (not practice) non-druid fight with a foreign healer and casts outside
  the class kit through the gates (can share M1's test).
- m3: an empty hot slot filled with druid names (Regrowth, Lifebloom) for a priest: fix it if
  it is a small, contained change; else name the file and line in your report.

## Acceptance

`make check` green, `tools/data/expected-counts.json` updated for changed suites, no druid
check changed in meaning. A one-line addition to the HISTORY T130 paragraph. Commit on the
branch, message ending with:
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
