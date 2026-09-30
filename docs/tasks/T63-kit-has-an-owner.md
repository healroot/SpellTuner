# T63 -- The kit has an owner (plan P19)

Status: **built** 2026-09-30 on branch `plan/P19` (base `b2d9b90`), wave 7 of
`docs/PLAN-refactor-ux.md`, awaiting the integrator. **The branch needs its three TOC lines (below) to
load**: without them `Engine/SimModel.lua` stops at `SM.KitSnapshot = MD.Kit.Snapshot` (the same shape
as T56, whose new files also waited for the integrator's TOC lines).

## The task (docs/PLAN-refactor-ux.md section 5, P19)

Review items (`docs/review/2026-09-30-project-review.md`): **A12** -- "the kit shape has no owner":
three producers (`RankMath:SpellKit`, `Kit_Forever.SpellKit` + `KitRestore`, `SM.KitSnapshot`), the
schema only a comment at `RankMath.lua:411-417`, `castBase` remembered by hand in both builders; and
the first step of **A11** -- `Kit_Forever.SpellKit` rebuilt the kit and rewrote `cdb.kit` on every one
of its ten call sites ("make `SpellKit` idempotent per book generation and write `cdb.kit` only when
the kit changed").

- `Engine/Kit.lua` (TBC TOC, and the Replay module before `Kit_Forever.lua`): `Kit.FIELDS` (the comment
  becomes the table), `Kit.Validate(kit)`, `Kit.Snapshot` / `Kit.Restore` moved out of `SimModel` and
  `Kit_Forever` (old names kept as aliases). Both builders end with `Validate`.
- `Spells/Book.lua` gains `Book.generation`, bumped by every scan that changes an entry;
  `Kit_Forever.SpellKit` caches on it, returns the same table while it is unchanged, and writes
  `cdb.kit` only when the kit changed.
- Tests: `kitcheck` +4 (both builders validate; a kit missing `castBase` fails validation; two calls
  with an unchanged book return the same table and write `cdb.kit` once; a rescan that changes one entry
  bumps the generation and rebuilds). Equal counts: `simcheck`, `importcheck` (byte for byte),
  `restcheck`, `practice`, `practiceforever`, `bookcheck`.
- TBC: `RankMath.lua` gains one call; no behaviour change.

Owned files (section 4, wave 7): new `Engine/Kit.lua`, `Engine/SimModel.lua`, `Engine/RankMath.lua`,
`Replay/Kit_Forever.lua`, `Spells/Book.lua`, `tools/kitcheck.lua`. Nothing else was committed (this task
file apart); the three TOC lines were applied in the working tree only, to run the suites.

## What was built

| file | change |
|---|---|
| `Engine/Kit.lua` | New, pure (no client call, no frame), `MD.Kit`. **`Kit.FIELDS`**: every entry field with its Lua type (`family`, `rank`, `type`, `gcd`, `cost`, `cast`, `castBase`, `direct`, `directCrit`, `tick`, `ticks`, `tickPeriod`, `duration`, `bloom`, `swiftmendRejuv`, `swiftmendRegrowth`, `channelTick`, `channelTicks`, `dataMissing`) -- RankMath's old comment, now the table, with the comment kept above it. **`Kit.ALWAYS`** (`family`, `rank`, `type`, `gcd`), **`Kit.TYPES`** (the six types `SimModel` switches on, each with the fields it needs -- `castBase` on `direct` and `hybrid`, the two types `Engine/Practice.lua` reads it for), **`Kit.UNPRICED`** (`Innervate`: carried for its mana and cast only, see TBC below), **`Kit.TOP`** (the kit's own fields). **`Kit.Validate(kit)`** -> `true` or `false, problems` (ASCII sentences naming form, spell id and field): only declared fields of their declared types, numbers finite, a known type, `Kit.ALWAYS`, and -- unless `dataMissing` -- every field the type needs; `crit` a fraction in [0, 1]. **`Kit.Check(kit, who)`** returns the kit when it validates, else raises naming the builder and the first three problems. **`Kit.Snapshot`** -- `SM.KitSnapshot` moved verbatim. **`Kit.Restore(snap, policy)`** -> `kit, index` -- `RM.KitRestore`'s body made flavour-free: the Forever family types, labels and plan exclusions come in as `policy`, and the index is returned rather than written into `MD.SpellData`. |
| `Engine/RankMath.lua` | The schema comment above `SpellKit` points at `Kit.FIELDS`; the builder's last line is `return MD.Kit.Check(kit, "RankMath:SpellKit")` (the one call). |
| `Engine/SimModel.lua` | `SM.KitSnapshot`'s body (and its comment) moved to `Kit.Snapshot`; `SM.KitSnapshot = MD.Kit.Snapshot` stays as the alias. |
| `Modules/SpellTuner_Replay/Kit_Forever.lua` | `SpellKit` split into `Build` (the old body, ending with `Kit.Check`) and a cache keyed on `book.generation` and the crit reading (`crit`, `critMissing` -- the one input that is not in the book); a book table without a generation is never cached. The `MD.SpellData` index is installed by one `InstallIndex` on **every** call, cached or not, so an index `KitRestore` installed meanwhile never outlives the next `SpellKit`. `cdb.kit` is written when the kit was rebuilt, or into a character database it has not been written to yet (`MD.cdb` replaced). `RM.KitSnapshot` calls `Kit.Snapshot`; `RM.KitRestore` is `Kit.Restore` with Forever's policy plus `InstallIndex` (same index as before: `skipped = {}`, the fixed `familyOrder`, no `bloomID`). **One Forever change**: a rank whose cast time the book cannot read (neither `SpellInfo` nor the tooltip data answers) is `dataMissing`, see Deviations. |
| `Spells/Book.lua` | **`Book.generation`** (starts at 0) and `book.generation` on every table `Scan` returns. `Scan` computes each entry's signature after `Rows` (sorted keys, numbers to 17 digits, strings length-prefixed, nested tables included, `casts` -- the casts-to-OOM count against the pool of the moment -- left out) and bumps the counter when an entry was added, removed or differs; the first scan counts as a change. `BOOK_CHANGED` and the 2-second rescan are untouched (A15's part, plan section 6). |
| `tools/kitcheck.lua` | Now `HARNESS_FLAVOUR = { "forever", "tbc" }`. Forever 7 -> **11** (+4), tbc **3** (new run). Below. |

### `tools/kitcheck.lua`

Forever (+4, after the seven T15 assertions):

8. **the Forever builder ends with Kit.Check and its kit validates, an unreadable cast as dataMissing**
   -- `Kit.Check` wrapped and counted over one build (a crit the cache has not seen), the kit through
   `Kit.Validate`; then `MD.API.SpellInfo` / `SpellTooltipData` withheld for 5185 (Healing Touch R1)
   and the book rescanned: the entry is `dataMissing` with no `cast` and the kit still validates; back
   to 1.5 s once the reads return.
9. **a kit missing castBase fails validation, naming the entry** -- a copy of the kit with the first
   `direct` entry's `castBase` removed: `false`, and a problem naming `caster[5185]` and `castBase`.
10. **two calls with an unchanged book return the same table and write cdb.kit once** -- `Kit.Snapshot`
    counted; one build, `Book:MarkDirty()` (a real rescan of an unchanged book), a second call: the same
    table, the same generation, one write, `cdb.kit` the same table.
11. **a rescan that changes one entry bumps the generation and rebuilds** -- Regrowth's text moves from
    93-107 to 193-207: generation +1, a new kit, `direct` 100 -> 200, `cdb.kit` rewritten with 200, the
    old kit untouched.

tbc (new run, 3):

1. **RankMath:SpellKit ends with Kit.Check and its kit validates** -- Innervate (29166) included, as
   `Kit.UNPRICED`.
2. **a kit missing castBase fails validation, naming the entry** (5185 again, on the TBC kit).
3. **SM.KitSnapshot is Kit.Snapshot, and a snapshot restores into a kit that validates** (`Kit.Restore`
   with no policy).

## Tests first

**On the parent's shipped files** (`b2d9b90`'s `Engine/RankMath.lua`, `Engine/SimModel.lua`,
`Kit_Forever.lua`, `Spells/Book.lua` and TOCs checked out over the branch, `Engine/Kit.lua` moved away,
the new `tools/kitcheck.lua` kept):

```
forever: exit 1
the Forever builder ends with Kit.Check and its kit validates, an unreadable cast as dataMissing FAIL - Kit=false built=true checks=0 valid=false first=nil noCast=false back=1.5
a kit missing castBase fails validation, naming the entry                FAIL - id=nil first=nil
two calls with an unchanged book return the same table and write cdb.kit once FAIL - same=false gen=nil->nil writes=0 cdbSame=false
a rescan that changes one entry bumps the generation and rebuilds        FAIL - gen=nil->nil rebuilt=true direct=100->200 cdb=200
7 ok, 4 failed
tbc: exit 1
tbc: RankMath:SpellKit ends with Kit.Check and its kit validates         FAIL - Kit=false built=true checks=0 valid=false first=nil
tbc: a kit missing castBase fails validation, naming the entry           FAIL - id=nil first=nil
tbc: SM.KitSnapshot is Kit.Snapshot, and a snapshot restores into a kit that validates FAIL - aliased=false restored=false first=nil
0 ok, 3 failed
```

After: `11 ok, 0 failed` / `3 ok, 0 failed`, rc 0.

**Mutations on the finished branch** (one literal replacement each, kitcheck under both flavours,
reverted):

| mutation | result |
|---|---|
| `Kit_Forever`: `Build` returns the kit without `Kit.Check` | forever 10 ok, 1 failed (8) |
| `RankMath`: `return kit` instead of `Kit.Check` | tbc 2 ok, 1 failed (1) |
| `Kit.TYPES.direct` without `castBase` | forever 10 / 1 (9), tbc 2 / 1 (2) |
| `Kit_Forever`: the cache never hits | forever 10 / 1 (10) |
| `Book`: the generation bumps on every scan | forever 10 / 1 (10) |
| `Book`: the generation never bumps | forever 9 / 2 (8, 11) |
| `Kit_Forever`: `cdb.kit` written on every call | forever 10 / 1 (10) |
| `Kit_Forever`: an unreadable cast not marked `dataMissing` | forever 10 / 1 (8: `Kit.Check` raises) |

## Suites (`make check` = `tools/check.sh`, exit codes and footers checked)

Run with the three TOC lines applied in the working tree.

| suite | before (`b2d9b90`) | after |
|---|---|---|
| `kitcheck` (forever / tbc) | 7 / -- | **11 / 3** |
| `simcheck` (tbc) | 13 | 13 |
| `importcheck` | 21 | 21, output byte for byte equal |
| `restcheck` (tbc) | 51 | 51 |
| `practice` (tbc) | 83 | 83 |
| `practiceforever` | 28 | 28 |
| `bookcheck` | 21 | 21 |
| every other suite | adaptercheck 23 / 16, bindscheck 6, clockcheck 23, coachforever 20, consolecheck 20 / 1, corecheck 24 / 24, costcheck 3, dashui 64, forevercheck 16, gatecheck 9, measurecheck 30, migrate 7, modulecheck 19, navui 35, parsecheck 15, practiceui 52, probecheck 88, reccheck 63, recordcheck 31, regencheck 27, releasecheck 21, replaycheck 82, replayforever 15, replayui 103, reviewforever 13, reviewui 49, runcheck 81, scenariocheck 14, simwindow 8, slashcheck 8, solvercheck 84, spellsui 48, spelltip 48, svcheck 6 / 1, tabscheck 24, themecheck 23, timeline 27, tipcheck 37, ttocheck 45, verifycheck 13, wincheck 55, lib/t 12 | all equal, all passing |
| harness-skip, reproduce-smoke, strategies-smoke | ok | ok |
| `apicheck.py` / `--selftest` | 0 findings, 48 files / 13 | 0 findings, **49** files (the Replay module lists `Engine/Kit.lua`) / 13 |
| `textcheck.py` / `--selftest` | 0 findings, 85 files / 2 | 0 findings, **86** files / 2 |
| `refcheck.py --selftest` | 2 | 2 |

`tools/check.sh`: 62 runs, all passed, rc 0; its only notes are `kitcheck/forever: 11 assertion(s), 7
expected` and `kitcheck/tbc: 3 assertion(s), not in the expected counts`. Every suite's saved output was
compared with the parent's, with table addresses and millisecond timings normalised: equal except
`kitcheck` (the new lines), `apicheck` / `textcheck` (the file counts), `releasecheck` (the TBC package
has 59 files, was 58) and the `[sim] search N evaluations` debug lines of `replayui` / `reviewui`, which
differ between two runs of the same tree (the search is sliced on `debugprofilestop()`; three runs of
the branch printed 17, 15 and 19 for the same line). `luac -p` passes on every changed file.

## TBC

No behaviour change. `RankMath:SpellKit` returns the same kit through `Kit.Check`; the kit it builds
validates as it is (the builder was not touched otherwise). The one TBC oddity the validator found is
**kept, not fixed**: Innervate (29166) is in `SD.known` with no `SD.families` row, so the builder files
it as type `"direct"` (its default) with a cost and a 1.5 s cast and no heal -- the engine times it as a
cast bar and lands 0. Making it `dataMissing` would make Practice refuse the key ("Not modelled yet"),
and another type would change how the engine times it, so it is declared instead: `Kit.UNPRICED`, a
family carried for its mana and cast only. `SM.KitSnapshot` is the same function under its old name, and
the TBC suites (`simcheck`, `restcheck`, `practice`, `solvercheck`, `replayui`, `reviewui`, `reccheck`,
`replaycheck`, `runcheck`, `simwindow`, `importcheck` ...) are equal. No DECISIONS entry is needed.

## Integrator lines

**`SpellTuner_TBC.toc`** -- a new line `Engine\Kit.lua` **immediately before** `Engine\RankMath.lua`
(after `Engine\TTO.lua`).

**`Modules/SpellTuner_Replay/SpellTuner_Replay.toc`** and
**`Modules/SpellTuner_Replay/SpellTuner_Replay_Mainline.toc`** (both, identical) -- a new line
`Engine\Kit.lua` **between** `Module.lua` and `Kit_Forever.lua`.

No other TOC: `SpellTuner_Mainline.toc` / `SpellTuner.toc` do not load the engine (the Replay module
does), and the Practice module reads the kit through the Replay module it needs.

**tools/data/expected-counts.json**: `"kitcheck/forever": 11` and a new `"kitcheck/tbc": 3`.

**CLAUDE.md** (the repo-structure table):

- New row after `Engine/RankMath.lua`'s: `| `Engine/Kit.lua` | **The kit's shape, one owner** (T63, P19,
  review A12 / A11): `Kit.FIELDS` (every entry field with its type -- RankMath's old schema comment as a
  table), `Kit.ALWAYS`, `Kit.TYPES` (the six entry types `Engine/SimModel.lua` switches on and the fields
  each needs; `castBase` on direct and hybrid), `Kit.UNPRICED` (Innervate: mana and cast only),
  `Kit.Validate(kit)` -> `true` or `false, problems` (declared fields only, of their types, finite; a
  `dataMissing` entry owes only `family / rank / type / gcd`), `Kit.Check(kit, who)` (what both builders
  end with: the kit, or an error naming the builder and the problems), `Kit.Snapshot` (moved from
  `SM.KitSnapshot`, which stays as its alias) and `Kit.Restore(snap, policy)` -> `kit, index` (moved from
  `Kit_Forever`'s `RankMath.KitRestore`, flavour-free: the family types, labels and exclusions come in as
  `policy`). Pure; TBC TOC before `Engine/RankMath.lua`, the Replay module before `Kit_Forever.lua`.
  A new kit field is declared here first |`
- `Engine/RankMath.lua` row, append before the closing ` |`: ` **T63 (P19):** `SpellKit` ends with
  `MD.Kit.Check`; the entry's shape is `Engine/Kit.lua`'s `Kit.FIELDS``
- `Engine/SimModel.lua` row, append before the closing ` |`: ` **T63 (P19):** `SM.KitSnapshot` is an
  alias of `Kit.Snapshot` (`Engine/Kit.lua`)`
- `Spells/Book.lua` row, append before the closing ` |`: ` **T63 (P19, review A11):** `Book.generation`
  (also `book.generation` on each scan's table) -- bumped by every scan in which an entry was added,
  removed or changed (its signature after `Rows`, the pool-dependent `casts` left out; the first scan
  counts); an unchanged rescan leaves it`
- `Modules/<Name>/` row, after the T15 sentence (`... only where no flavour has its own) and
  `Engine\SimModel.lua`.`), insert: ` **T63 (P19):** `Engine\Kit.lua` is listed before `Kit_Forever.lua`;
  the Forever kit is built once per `Book.generation` and crit reading (the same table handed out while
  neither moves, the `MD.SpellData` index reinstalled on every call), ends with `Kit.Check`, writes
  `cdb.kit` only when rebuilt, and marks a rank whose cast time the book cannot read `dataMissing`;
  `RankMath.KitSnapshot` / `KitRestore` are `Kit.Snapshot` / `Kit.Restore` with Forever's policy.`

**docs/TOOLS.md** section 1, the `kitcheck.lua` row: `(T15, forever)` becomes `(T15; forever, and tbc
since T63)`, and append before the closing ` |`: `. Since **T63** (P19; forever 11, tbc 3): both builders
end with `Kit.Check` and their kits validate (Innervate as `Kit.UNPRICED` on tbc; a Forever rank with
no readable cast as `dataMissing`); a kit missing `castBase` fails `Kit.Validate`, naming the entry;
two `SpellKit` calls around an unchanged rescan return the same table and write `cdb.kit` once; a
rescan that changes one entry bumps `Book.generation` and rebuilds; `SM.KitSnapshot` is `Kit.Snapshot`
and a snapshot restores into a kit that validates`

**docs/TESTING.md**: under the Forever checks for the plan (section 9, the P19 line): "With the Replay
module on, `/st replay`, `/st coach N` and a practice fight behave as before; after `/reload` the
character's `SpellTunerDB` still carries `kit` (written when the kit was first built this session and
again only when the spellbook or crit changed). TBC: `/md coach N` and `/md practice start` as before."

**docs/DECISIONS.md**: none required (TBC unchanged). Optionally, one line under the Forever port's
notes: "A Forever kit rank whose cast time the book cannot read is `dataMissing` (Practice refuses it)
rather than carrying a `nil` cast into the engine (T63)."

**docs/HISTORY.md**: the integrator's wave entry.

## Deviations

- **Forever: an unreadable cast is `dataMissing`.** `Kit.Validate` asks every type for a `cast`, and the
  Forever builder copied `be.cast` even when the book had none (neither `SpellInfo` nor the tooltip data
  answering -- not seen in any probe report, but nothing prevents it in combat). Before, such an entry
  carried a `nil` cast into the engine; now it is marked like every other missing value, so it validates
  and Practice refuses it. No fixture has such a rank, so no suite output moved; kitcheck 8 holds it.
- **`Kit.UNPRICED`** is not in the plan: the TBC kit's Innervate entry (above) is the one real entry that
  does not fit its type, and declaring it was the only way to validate the TBC kit without moving TBC.
- **`Kit.Check` raises** rather than logging: a kit that fails is a builder's bug once missing values are
  `dataMissing`, and every suite builds kits, so a regression is red at the boundary.
- **The cache key includes the crit reading**, not only `Book.generation`: `kit.crit` and every entry's
  `directCrit` come from `SpellCritChance`, which the book does not hold (kitcheck 7 moves it between
  calls). In combat, where the reading is secret, the last plain value is used, as before -- so the key
  does not churn.
- **`cdb.kit` is also written when `MD.cdb` is a table the cache has not written to**, not only when the
  kit changed: a replaced character database would otherwise never receive the kit.
- **`Kit.Restore` returns the index instead of writing `MD.SpellData`**, and takes the flavour's families
  as `policy`; `Kit_Forever`'s `RankMath.KitRestore` installs it, so its callers see what they saw.
  Restore does not validate: a snapshot is replayed as it was recorded.
- **`Book.generation` counts every entry change, not only those the kit reads** (a description going
  stale in combat moves it too); the kit is then rebuilt with the same numbers. It never moves for the
  pool (`casts`), which changes with max mana and regen.
- **kitcheck gained a tbc run** (3 assertions): "both builders validate" needs the TBC builder, which
  loads only under the TBC harness.
- **The branch does not load without its TOC lines** (as T56): the TOCs are integrator-owned. The suites
  above were run with the three lines applied in the working tree and not committed.
