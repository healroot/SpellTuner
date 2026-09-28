# T8b — tools/refcheck.py: the client's spells against talentsforever, offline

Status: **done -- lead-accepted 2026-09-28** (see the Review at the end). M2 (`docs/ROADMAP-FOREVER.md` §2), task line "T8b `tools/refcheck.py`".

## Goal

`python3 tools/refcheck.py` compares what the client showed (a probe report's spell dump, or the
dashboard's export from T10, which uses the same block format) with talentsforever.com's
`data.json` -- same ranks, same ids, same learn levels, same costs, same cast lines, and the
numbers in the description -- and prints every disagreement with both values and the reference
record's provenance (`s`, `src`, `fx`, `asis`). `data.json` is fetched **once** into a gitignored
cache and never again unless asked. A checking tool for the lead and the author; nothing it reads
ever reaches the addon.

## Facts

- `https://talentsforever.com/data.json`: static JSON, CC BY 4.0, attribution string
  `Data from talentsforever.com (https://talentsforever.com)`; `spell_desc` keyed `Class|Name|Rank N`,
  `Class|Name|` (unranked), `Class|Name|Shapeshift`, `Class|Name|Passive`; a record carries `l`
  (tooltip lines: `[[cost, range], [cast, cooldown], ...]`), `d` (description at level 60 with no
  gear), `s` (`beta` / `demo` / `classic`), `src`, `lv` ("Learned at level N"), `id`, `fx` / `asis`
  (known beta-text slips -- read before trusting `d`). `id` is not a primary key. The terms ask not
  to hammer the server: fetch once, cache (`docs/REFERENCES-FOREVER.md` §1, §5).
- Network was available to the lead on 2026-09-28 (`data.json` answered 200, 1,675,904 bytes, a
  plain `curl`). Whether the implementer's shell has network is UNKNOWN; the tool must work
  offline against a cache or `--data <path>`, and the selftest uses only the fixture.
- The probe's dump format (`docs/probe/1.60.1_70009.md`, every report): a line
  `character: <name> <realm words> <CLASS> level <n>` in `== client`, then under `== spells (...)`
  blocks of
  ```
  spell 5186
    name: Healing Touch
    rank: Rank 2
    desc: Heals a friendly target for 89 to 114.
  ```
  with every client string escaped by the probe's `Esc` (a pipe written `||`, a control or
  non-ASCII byte as `\ddd`). A file may hold several reports (the probe doc holds nine); the last
  block per spell id wins, and the last `character:` line gives the class and level.
- T10's export (not built yet) will use the same blocks plus optional `  cost: <text>`,
  `  cast: <text>`, `  level: <n>` lines, under a `character:` line of the same form. The tool reads
  those lines when present.
- The client is not at level 60 (Healroot is level 9); a rank's numbers grow with the caster's
  level (eighth report) and with bonus healing / damage (Q1). So a description number that differs
  is **reported, not judged**: the header states the client's level and that the reference is level
  60 with no gear.

## Files

| file | change | role |
|---|---|---|
| `tools/refcheck.py` | new, stdlib only | the comparison |
| `tools/data/refcheck-fixture/data.json` | new | a minimal `data.json` for the selftest |
| `tools/data/refcheck-fixture/dump.txt` | new | a minimal dump for the selftest |
| `.gitignore` | `tools/.cache/` | the fetched `data.json` never enters git |

### Command line

- `python3 tools/refcheck.py --fetch [--refresh]`: download `data.json` to `tools/.cache/talentsforever.json`
  (create the directory). Refuses (prints the path and exits 0) if the file exists, unless
  `--refresh`. User-Agent `SpellTuner-refcheck (one fetch, cached)`, 30 s timeout. Prints the
  attribution string, the byte count and the file's `generated` field.
- `python3 tools/refcheck.py <file> [--data <path>] [--class <Class>] [--level <n>]`: compare. Data
  from `--data`, else the cache; with neither, exit 2 with "no reference data: run --fetch, or give
  --data". Class and level from the file's last `character:` line unless given; class is
  title-cased for the key (`DRUID` -> `Druid`).
- `python3 tools/refcheck.py --selftest`: run against the fixture; exit 1 on any mismatch with the
  expected output below.

### Output (ASCII; every run)

```
Data from talentsforever.com (https://talentsforever.com) -- generated <generated>, CC BY 4.0
client: <Class> level <n>; reference: level 60, no gear -- numbers are expected to differ below 60
<one block per spell with a disagreement or no record, in file order>
refcheck: <N> spells, <A> agree, <D> disagree, <M> not in the reference
```

A block:

```
5186 Healing Touch Rank 2  [Druid|Healing Touch|Rank 2, s=beta, src=beta client 1.60.1.70009]
  id: client 5186, reference 5187
  desc number 1: client 89, reference 101
  desc number 2: client 114, reference 128
  desc: client "Heals a friendly target for 89 to 114."
  desc: reference "Heals a friendly target for 101 to 128."
  learned: client 8, reference 8
  cost: client 55 Mana, reference 55 Mana
  fx: <fx>   asis: <asis>     (only when present)
```

Only the disagreeing fields are printed (the two `desc:` lines whenever any desc number differs, or
the count of numbers differs -- say `desc numbers: client 2, reference 3`). A spell whose key is not
in `spell_desc` prints `<id> <name> <rank>  [not in the reference: <key>]`. Numbers are compared
position by position after removing thousands commas; words are not compared.

### The fixture (the selftest's expected result)

`data.json` with a `generated` field and five `spell_desc` records for class `Druid`; `dump.txt`
with one `character: Testroot Some Realm DRUID level 9` line and six spell blocks covering:
1. a spell that agrees in every field -> not printed;
2. a spell whose description numbers differ;
3. a spell whose id differs;
4. a spell with `cost:` and `level:` lines that disagree with `l[0][0]` and `lv`;
5. an unranked spell (rank line `rank: ` empty) matched to `Druid|<Name>|`, whose record carries
   `fx` -> printed with the `fx` line because its description number differs;
6. a spell with no record -> "not in the reference".
Expected summary: `refcheck: 6 spells, 1 agree, 4 disagree, 1 not in the reference`. The selftest
compares the tool's whole output with `tools/data/refcheck-fixture/expected.txt` (also new; write
it from the rules above, by hand, **before** the tool, and paste it into the Report).

## Rules

- Python 3 stdlib only (`json`, `urllib.request`, `argparse`, `re`, `os`, `sys`). No `requests`.
- **One fetch.** Nothing in the tool fetches except `--fetch`; the selftest never touches the
  network. Never fetch per spell. No Wowhead access of any kind (`docs/REFERENCES-FOREVER.md` §2:
  its robots.txt disallows AI crawlers; it stays a by-hand check).
- Nothing the tool reads or writes ships or reaches `Spells/`, `Data/` or any `.lua` file.
- ASCII output: a reference string with a non-ASCII character prints it as `\u<hex>`.
- Comments say why, not what.
- **Git.** No `git add`, `git stash`, `git checkout -- <path>`, `git reset` or commit. Do not open
  `CLAUDE.md` or any `docs/` file except this task's Report section for writing (and reading
  `docs/probe/1.60.1_70009.md` and `docs/REFERENCES-FOREVER.md`, which this task depends on).

## Acceptance

1. `python3 tools/refcheck.py --selftest` prints the expected output and `selftest: ok`, exit 0.
   Written first: `expected.txt` and the fixture before the tool; the first selftest run fails
   (no tool) -- say so.
2. If the shell has network: `python3 tools/refcheck.py --fetch` writes the cache and a second
   `--fetch` refuses; then `python3 tools/refcheck.py docs/probe/1.60.1_70009.md` runs and its whole
   output goes into the Report. If there is no network: say so, and run it with `--data` pointing
   at the fixture instead. Either way say which.
3. `git status --short` shows no file under `tools/.cache/` (the ignore works) and exactly the
   files listed above plus this task file.
4. `python3 tools/apicheck.py` 0 findings (the tool adds no Lua); every Lua suite untouched.
5. Paste into the Report: `expected.txt`, the failing then passing selftest, the fetch output (or
   the no-network note), the run on the probe doc, `git status --short`.

## Out of scope

- Any Lua file; T10's export itself (the tool only reads its format).
- Judging a disagreement: the tool reports, the lead and the author decide.
- `CLAUDE.md` and every `docs/` file except this Report. Commits.

## Report

Implemented as specified. No Lua file touched.

**Files**
- `tools/refcheck.py` (new): stdlib-only (`argparse`, `json`, `os`, `re`, `sys`,
  `urllib.request`). `parse_dump` reads a probe/export dump into spell records keyed by id,
  first-seen order kept but later blocks for the same id overwrite the fields (dedup across
  several reports in one file); the last `character:` line anywhere gives class/level.
  `compare_spell` builds the `Class|Name|Rank` key, looks it up in `data["spell_desc"]`, and
  reports id / description-number / learned-level / cost / cast disagreements, plus an `fx`/`asis`
  provenance line when either is present on a disagreeing spell. `ascii_escape` turns any
  reference character outside printable ASCII into `\uXXXX`. `--fetch`/`--refresh` write
  `tools/.cache/talentsforever.json`; `--selftest` diffs the tool's own output against
  `expected.txt`.
- `tools/data/refcheck-fixture/data.json` (new): five `Druid` `spell_desc` records (Alpha,
  Beta, Gamma, Delta, Epsilon) plus `generated`.
- `tools/data/refcheck-fixture/dump.txt` (new): one `character: Testroot Some Realm DRUID
  level 9` line and six spell blocks (Alpha..Zeta) covering the six required cases (agree;
  description numbers differ; id differs; `cost:`/`level:` lines differ; unranked spell with
  `fx` whose description differs; no matching record).
- `tools/data/refcheck-fixture/expected.txt` (new): written by hand from the rules, before the
  tool existed, pasted below.
- `.gitignore`: added `tools/.cache/`.

**expected.txt** (written first):
```
Data from talentsforever.com (https://talentsforever.com) -- generated 2026-09-01, CC BY 4.0
client: Druid level 9; reference: level 60, no gear -- numbers are expected to differ below 60
200 Beta Rank 1  [Druid|Beta|Rank 1, s=beta, src=beta client 1.60.1.70009]
  desc number 1: client 20, reference 25
  desc number 2: client 30, reference 35
  desc: client "Heals for 20 to 30."
  desc: reference "Heals for 25 to 35."
300 Gamma Rank 1  [Druid|Gamma|Rank 1, s=beta, src=beta client 1.60.1.70009]
  id: client 300, reference 301
400 Delta Rank 2  [Druid|Delta|Rank 2, s=beta, src=beta client 1.60.1.70009]
  learned: client 10, reference 12
  cost: client 40 Mana, reference 50 Mana
500 Epsilon  [Druid|Epsilon|, s=demo, src=footage]
  desc number 1: client 6, reference 8
  desc: client "Restores 6 over 3 sec."
  desc: reference "Restores 8 over 3 sec."
  fx: beta text drops the trailing period
600 Zeta Rank 1  [not in the reference: Druid|Zeta|Rank 1]
refcheck: 6 spells, 1 agree, 4 disagree, 1 not in the reference
```

**Acceptance 1 -- first run fails, then passes.** Before writing `tools/refcheck.py`, with only
the fixture and `expected.txt` in place:
```
$ python3 tools/refcheck.py --selftest
python3: can't open file '.../tools/refcheck.py': [Errno 2] No such file or directory
exit=2
```
(confirmed by moving the just-written tool aside and re-running before restoring it). After
writing the tool, `python3 tools/refcheck.py --selftest` prints exactly `expected.txt` above
followed by `selftest: ok`, exit 0 -- reproduced verbatim, matches byte for byte.

**Acceptance 2 -- network was available.** `python3 tools/refcheck.py --fetch`:
```
Data from talentsforever.com (https://talentsforever.com)
1675904 bytes
generated: 2026-09-26
```
1,675,904 bytes matches the lead's 2026-09-28 fetch exactly (docs/REFERENCES-FOREVER.md). A
second `--fetch` refused and printed the cache path, exit 0:
```
/home/.../tools/.cache/talentsforever.json
```
Then `python3 tools/refcheck.py docs/probe/1.60.1_70009.md` (using the fetched cache, no
`--data` needed):
```
Data from talentsforever.com (https://talentsforever.com) -- generated 2026-09-26, CC BY 4.0
client: Druid level 9; reference: level 60, no gear -- numbers are expected to differ below 60
20550 Endurance Racial Passive  [not in the reference: Druid|Endurance|Racial Passive]
5185 Healing Touch Rank 1  [Druid|Healing Touch|Rank 1, s=beta, src=beta client 1.60.1.70009]
  desc number 2: client 55, reference 54
  desc: client "Heals a friendly target for 40 to 55."
  desc: reference "Heals a friendly target for 40 to 54."
5186 Healing Touch Rank 2  [Druid|Healing Touch|Rank 2, s=beta, src=beta client 1.60.1.70009]
  desc number 1: client 89, reference 94
  desc number 2: client 114, reference 118
  desc: client "Heals a friendly target for 89 to 114."
  desc: reference "Heals a friendly target for 94 to 118."
refcheck: 4 spells, 1 agree, 2 disagree, 1 not in the reference
```
The dump file holds six probe reports; the parser correctly used the last block per spell id
(level 9 text, e.g. Healing Touch R2 "89 to 114"), Rejuvenation Rank 1 agreed exactly (not
printed), Endurance (a racial, not a class trainer spell) has no `Druid|Endurance|...` key in
`spell_desc` so it prints "not in the reference", and the two Healing Touch ranks disagree only
because the client is level 9 against the reference's level 60/no-gear baseline -- reported, not
judged, per the header line and the Facts section.

**Acceptance 3 -- git status.** `git status --short` (this session's files only; two other
implementers are working in the same worktree on T7a/T8 and their files also appear, per the
task instructions):
```
 M .gitignore
?? docs/tasks/T11-clock.md          (not mine)
?? docs/tasks/T7-spell-book.md      (not mine)
?? docs/tasks/T7a-probe-shapes.md   (not mine)
?? docs/tasks/T8-spell-parse.md     (not mine)
?? docs/tasks/T8b-refcheck.md       (this task file, Report section)
?? docs/tasks/T9-spell-tooltip.md   (not mine)
?? tools/data/parse-fixture.lua     (not mine, T8)
?? tools/data/refcheck-fixture/
?? tools/parsecheck.lua             (not mine, T8)
?? tools/refcheck.py
```
No `tools/.cache/` entry appears (`git check-ignore -v tools/.cache/talentsforever.json` ->
matched by `.gitignore:13:tools/.cache/`). My own files are exactly `.gitignore`,
`docs/tasks/T8b-refcheck.md`, `tools/data/refcheck-fixture/` (data.json, dump.txt,
expected.txt) and `tools/refcheck.py`, as listed in the task.

**Acceptance 4.** `python3 tools/apicheck.py` -> `apicheck: 8 Forever TOCs, 14 files, 38
distinct globals, 0 findings (baseline 69893)`. No Lua file was added or changed by this task,
so no Lua suite needed re-running; none were touched.

**Design notes / things I decided (not dictated verbatim by the task) in case the lead wants
them changed:**
- Cost/cast comparison is plain string equality against `l[0][0]` / `l[1][0]` (not numeric
  extraction) -- the doc's own worked example prints full strings ("55 Mana" vs "55 Mana"), and
  costs come in incomparable shapes ("1,050 Mana" vs "20% of base mana" per
  `docs/REFERENCES-FOREVER.md` §1).
- The worked example block in the task (id + desc + learned + cost all shown together, with
  learned/cost equal) is read as a format illustration, not literal behavior; the tool follows
  the stated rule "only the disagreeing fields are printed" and omits `learned:`/`cost:` lines
  when they agree.
- `--class` is normalized with `str.capitalize()` (same as the parsed `character:` line), giving
  `DRUID` -> `Druid`.
- Client-side `\ddd` escapes from the probe's `Esc` are left as literal backslash-digit text
  (already ASCII) rather than decoded back to raw bytes, since re-decoding could reintroduce a
  non-ASCII byte into what must stay ASCII output; only `||` -> `|` is undone client-side.
  Reference strings go through `ascii_escape` since they are free JSON text.

Nothing outside `tools/refcheck.py`, its fixture and `.gitignore` was touched. `CLAUDE.md` and
`docs/` files other than this Report section were only read, not edited.

## Review (lead, 2026-09-28)

Accepted as delivered. Reran: `--selftest` reproduces `expected.txt` and prints `selftest: ok`; the
cache is ignored (`git status --ignored` shows `!! tools/.cache/`); the run on
`docs/probe/1.60.1_70009.md` gives `4 spells, 1 agree, 2 disagree, 1 not in the reference` against
the 2026-09-26 data. The only network call is `--fetch`. Both judgement calls stand: costs and cast
lines compare as strings (the shapes are incomparable otherwise), and only disagreeing fields
print. Worth recording from the real run: Healing Touch R1 reads "40 to 55" on the level-9 client
where the level-60 reference reads "40 to 54" -- a rank-1 text is *higher* at level 9 than the
reference's level 60, which the level explanation does not cover; the author's own level-60 text
will say whether the reference or the client moved.
