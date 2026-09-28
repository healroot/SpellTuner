# tools/ — the offline harness

Everything here runs the **real addon files** against a fake WoW client
(`tools/wowstub.lua`), so it catches ordering and arithmetic bugs a syntax check cannot.
Nothing in `tools/` ships: `release.sh` builds from the `.toc`'s own file list.

```bash
bash tools/run.sh tools/<script>.lua [args]
```

`run.sh` builds a real Lua 5.1.5 into `tools/.lua` on first use (gitignored), then runs the
script against this checkout. **`--flavour forever|tbc`** (first, before the script) picks which
client the harness loads (since T5, 2026-09-28): `tools/harness.lua` reads the file list out of
that flavour's TOC (`SpellTuner_Mainline.toc` whole; `SpellTuner_TBC.toc` minus `UI/` other than
`UI/Summary.lua` and minus `Integrations/`), and every tool declares the flavours it runs under
(`HARNESS_FLAVOUR = "tbc"` before it loads the harness; no declaration means forever). Run a tool
under a flavour it does not declare and it prints `skip: <tool> runs under <flavours> only`. The
`forever` profile keeps secrets the way build 70009 does (current health and power always, a party
member's max health always, `GetManaRegen` in combat, auras raise in combat, the combat log
registration fires `ADDON_ACTION_FORBIDDEN`) and removes every global function the 69893 API
baseline (`tools/data/forever_api.json`, the forever-addon-kit's, MIT) does not have. **It passes the checkout root as `arg[1]`**, so a script's own
arguments start at `arg[2]` — the older tools survive reading from `arg[1]` only because
their parsers happen to reject a path.

Python tools run directly with `python3` and need no harness.

**`python3 tools/apicheck.py`** (T6) -- run it on every Forever change. It reads every file the
Forever TOCs load (any `.toc` with an interface in 16000-19999, siblings included), lists every
global each reads or writes from `luac -l` (the harness's own `luac`, built by `run.sh`), and fails
with `FAIL <file>:<line> <name> <reason>` on a name the 69893 baseline lacks, a client call outside
`Client/` (the widget toolkit and WoW's Lua extensions are allowed anywhere -- the two lists are in
the script), a new global, `os` / `io` / `require` and the rest WoW's Lua does not have, the
`COMBAT_LOG_EVENT_UNFILTERED` constant outside `Client/API_Forever.lua`, and a `C_X.Y` string the
baseline does not have. `--report` prints every global per file with its class; `--selftest` runs
the fixture in `tools/data/apicheck-fixture/`, which trips each rule once (10 findings since T13a).
Since **T13c** a module TOC's entry under `Engine/`, `Spells/`, `Data/` or `UI/` that is not in the
module folder is scanned from the repository root. Since **T13a**, rule 8, from the source text:
`rule 8: <file>:<line> <param> used before IsSecret in the <EVENT> handler` for an `MD:On` handler
(inline, or a same-file `local function`) outside `Client/` whose argument is compared, used in
arithmetic, indexed, measured with `#` or `type()`-tested before a call to `...IsSecret(param)`.
It does not follow a value into another function or through an alias, and a check in a branch
that does not dominate the use still counts -- a clean run is necessary, not sufficient.

**`python3 tools/refcheck.py <file>`** (T8b, M2) -- the client's spells against talentsforever.com's
`data.json` (`docs/REFERENCES-FOREVER.md` §1). `<file>` is a probe report (its `== spells` blocks;
several reports in one file, the last block per spell wins) or the Spellbook pane's **Export** (the
same blocks plus `cost:`, `cast:`, `level:`). For each spell: the record `Class|Name|Rank N`, and
every disagreement -- id, description numbers position by position, learn level, cost line, cast
line -- printed with both values and the record's `s` / `src` / `fx` / `asis`; the header says the
client's level against the reference's level 60, because below 60 the numbers are expected to
differ. It reports, never judges. **`--fetch`** downloads `data.json` once into the ignored
`tools/.cache/talentsforever.json` (a second `--fetch` refuses; `--refresh` forces); nothing else
touches the network, and Wowhead is never fetched. `--data <path>` points at another copy;
`--selftest` runs the fixture in `tools/data/refcheck-fixture/`. Data from talentsforever.com
(https://talentsforever.com), CC BY 4.0 -- the attribution is printed on every run.

---

## 1. The test suites

Run all of them before committing anything the engine, the recorder or a tooltip touches.

| suite | what it holds down |
|---|---|
| `simcheck.lua` | the engine's ten self-tests + the BF-1 fixture replay (`--curve` prints the mana curve beside the log's) |
| `reccheck.lua` | a whole scripted pull through the real combat-log handler: the stream, the labels, the summary row |
| `replaycheck.lua` | the trace and the replay state machine; *seek == step*; **the causality invariant** |
| `replayui.lua` | the replay window painted under the stub — the nil-index / argument-order / bare-pipe class of bug |
| `runcheck.lua` | a whole scripted dungeon: pulls, gaps, a drink at a known rate, a death, the budget, auto-stop |
| `reviewui.lua` | the Review tab: rows, buttons, and the `run:pull` address across tab, commands and replay |
| `navui.lua` | the navigation kit: lazy panes, one pane at a time, the remembered path |
| `dashui.lua` | the one window, driven the way a mouse would |
| `regencheck.lua` | `/md regentest` against a scripted mana stream, and **what it stores** |
| `simwindow.lua` | every preset combination's scenario, baselines and search |
| `solvercheck.lua` | the solver: deposits, the gap integral, causality, the four forecasts, the explainer |
| `timeline.lua` | the run's clock: segments, seeks, health across a gap |
| `practice.lua` | a practice session played against a fake clock: the seeded damage, the game's rules, the live trace, and **the recording replaying to exactly what was played** |
| `practiceui.lua` | practice from the screen: panel, Start, presses on frames and keys over them, pause, End, the replay, Review's Practice list |
| `spelltip.lua` | the spell tooltip (v0.14.9): druid only, once per showing, off means off, and **every number on it is the model's own** — the tick and bloom the simulator heals with, the dashboard's heal |
| `migrate.lua` | the rename (2026-09-27): a ManaDemon WTF comes up as SpellTuner's with every setting, recording and practice fight; `/md` still answers |
| `forevercheck.lua` | **the Forever TOC under the Forever profile** (T5, forever): loads clean, loads exactly the TOC's files, never tries the combat log, and the stub keeps secrets and absences as build 70009 does -- so arithmetic on current health trips here as it does in the client |
| `adaptercheck.lua` | **the client adapter** (T1, forever and tbc): every binding in the capability table, absent / error / secret answered as `nil` plus a reason, returns kept whole, nothing secret ever leaving `MD.API`, the combat log forbidden on Forever only |
| `corecheck.lua` | **the shared kernel** (T1b, forever and tbc): events, callbacks, ticker, the forbidden-event guard, the command registry, `Print` through the adapter; on Forever `/st probe` through the kernel and nothing registering the combat log; on TBC its talents, profile, login order and slash chain as before |
| `modulecheck.lua` | **the modules and the Forever window** (T2, forever): the three siblings declared in dependency order, off means never loaded, on loads what it needs first and at every login, off switches off what needs it, a refused load says why, the sibling TOCs, `/st` opening and closing the window, the Modules pane switching, every string on the window ASCII. The stub loads a sibling from `Modules/<Name>/` the way the client loads a LoadOnDemand addon. Since **T13c** (14): a module's files see SpellTuner's `MD`, and a TOC entry under `Engine/`, `Spells/`, `Data/` or `UI/` loads from the repository root |
| `kitcheck.lua` | **the Forever spell kit** (T15, forever): `MD.RankMath:SpellKit()` exists only once the Replay module loads; each known healing rank valued from its own text (3 s tick, UNVERIFIED on Forever); Swiftmend eats the whole HoT; unknown ranks, damage spells and Wild Growth left out (and named in `SpellData.skipped`); the spell index; `SimModel:Run` on the kit; crit as a Nature fraction, never secret |
| `svcheck.lua` | **the SavedVariables guard** (T4, forever and tbc): a first run, a database that came back with its session, one without a stamp, a broken one replaced rather than indexed, the guard running before the probe, the line in the debug log; TBC's database never stamped |
| `consolecheck.lua` | **errors, the console and `/st dump`** (T3, forever and tbc): our error recorded once and counted, shown to the client once; another addon's passed through; a sibling's counted as ours; the handler never raising; the 50-entry cap; the dump's sections in order, escaped to ASCII; `/st debug` with the error count and no Regen test button on Forever; every Forever TOC's version; TBC with no handler and its button kept |
| `parsecheck.lua` | **`Spells/Parse.lua`** (T8, forever): 54 sourced descriptions (`tools/data/parse-fixture.lua`: the probe's own texts and talentsforever's beta texts, every class) read exactly -- or refused -- plus costs, cast lines and ranks; **no number is ever invented**, and nothing raises whatever it is given. Since **T7b** (11): the `\|4singular:plural;` escape expanded, a reflect clause not a cast's damage |
| `bookcheck.lua` | **`Spells/Book.lua`** (T7, forever): the book read through the skill lines or the slot walk, families in rank order, every value from the spell's own text, gaps, the four cost states, per mana / per second / casts to OOM, dominance and the suggested rank, a secret description keeping its last value, **nothing handed out secret**, the cache, `ReadSpell`. Since **T7b** (15): the shapes build 70009 returned -- a free spell, the `\|4` escape, Thorns' reflect |
| `tipcheck.lua` | **the spell tooltip block** (T9/T10/T10b, forever): registered through the adapter for the Spell data type, once per showing, every number the book's, the comparison with the highest rank, the suggested rank, gaps, a secret id or a builder error never reaching the game's tooltip, off means off, the per-second interval named by kind |
| `clockcheck.lua` | **the Forever mana clock** (T11, forever): the pool assumed full at login, a cast's cost at success, the five-second rule across its boundary, the out-of-combat regen rate carried into combat, re-anchoring, warmup / OOM / FULL, `~` in text and hover, unpriced casts counted, **the real pool handed to the bar unread**, visibility. Since **T11b** (15): the TBC clock's thresholds, hysteresis and warm-up wording |
| `spellsui.lua` | **the Spellbook pane** (T10/T10b, forever): every family under Heals / Damage / Other with section titles, each row the book's numbers, dashes never zeros, the clock's pool for casts to OOM, the hover, the export read back by `refcheck.py`, refresh while shown only, no module loaded. Since **T10c** (15): every header, title and note on one line; Other only for spells cast for mana |
| `measurecheck.lua` | **`/st measure`** (T12, forever): nothing registered until asked, a heal on yourself and a Wrath on the target matched and judged (`in range` / `crit range` / `BELOW range`), a HoT's ticks, other units ignored, a secret amount counted and never judged, the dump. Since **T12b** (18): several watches at once, a heal landing before its own cast event, a HoT's ticks kept through another cast, a DoT's through the next casts, an amount that fits two casts `ambiguous`, a damage shortfall a possible resist, a heal shortfall BELOW only with the known deficit behind it, `capped at missing health`, bonus healing from before combat, a recast ending a watch as `refreshed` |
| `probecheck.lua` | **the Forever probe** (T0) under the stub's `forever` profile: never raises, a missing function is "absent" not an error, a secret is "secret" not a sum, a bad event is caught, the report is ASCII with no bare pipe and keyed by build, the sections are in order, the description dump is whole, the TOC that loaded is named; since **T0c** also a blocked action recorded with what the probe was doing, the combat log registered only by `/st probe clog`, the secret readings and restriction state, Q1 by bonus damage or level with was/now lines, Q6 at level 10, and the release carrying exactly three TOCs; since **T7a** the `== shapes` section (every return shape M2 reads, in and out of combat, and `UNIT_SPELLCAST_SUCCEEDED` counted). Since **T13b** (71): a passive's "Health" / "taking damage" not taken for a heal or damage spell, the tooltip lines of a direct heal, a HoT and a damage spell, party1's six readings out of combat and in the snapshot, `UNIT_COMBAT` per token with mirrors. Since **T13e** (73): a status bar handed a secret reports whether it reads back secret, plain, or raises |

```bash
for t in simcheck reccheck replaycheck replayui runcheck reviewui navui dashui \
         regencheck simwindow solvercheck timeline spelltip practice practiceui \
         migrate probecheck forevercheck modulecheck kitcheck \
         parsecheck bookcheck tipcheck clockcheck spellsui measurecheck; do
  printf "%-13s " "$t"; bash tools/run.sh tools/$t.lua 2>&1 | tail -1
done
# the suites that run under both flavours
for t in adaptercheck corecheck svcheck consolecheck; do
  for f in forever tbc; do
    printf "%-13s " "$t/$f"; bash tools/run.sh --flavour $f tools/$t.lua 2>&1 | tail -1
  done
done
python3 tools/apicheck.py | tail -1; python3 tools/apicheck.py --selftest | tail -1
python3 tools/refcheck.py --selftest | tail -1
```

---

## 2. Working with real recordings

### `import.lua` — your own fights, offline

Loads the game's SavedVariables as the addon's database and runs the same engine the Review
tab runs, without the game.

```bash
bash tools/run.sh tools/import.lua list                 # every recording + its verdict
bash tools/run.sh tools/import.lua validate 1           # the eight gates, in full
bash tools/run.sh tools/import.lua replay 1             # every cast, its label and its reason
bash tools/run.sh tools/import.lua coach 1 force        # the search and the card
bash tools/run.sh tools/import.lua spells 1             # where the mana went, by kind
bash tools/run.sh tools/import.lua export 1             # -> .logs/recordings/<id>.txt
bash tools/run.sh tools/import.lua runs                 # stored runs
bash tools/run.sh tools/import.lua validate 3 --run 1   # run 1, pull 3 (the "1:3" address)
```

Options: `--file <path>` (default `$MD_SAVEDVARS`, then `.logs/SpellTuner.lua`, then the
author's install), `--char "Name-Realm"`, `--run K`.

### `reproduce.lua` — does the engine reproduce the recording at all?

```bash
bash tools/run.sh tools/reproduce.lua .logs/wcl-holdout.lua .logs/wcl-holdout-observed.lua
```

Replays a recording's own casts and reports how much of the **recorded healing** the engine
generates from them, split per family and per heal event, with the cast count and the deaths
beside it. Run this before believing any comparison.

With an `observed.lua` the kit is first scaled to what the log says each spell healed, so
spell values are removed from the question and what is left is the engine alone.

Since **v0.14.7** the Malchezaar control reads **95% with no calibration at all**, and the
observed table is worth one point on top of that (95 -> 96) — which is what it should be
worth once the spell data is right. Per family, uncalibrated: Lifebloom 90%, Regrowth 87%,
Rejuvenation 103%, Swiftmend 67%. The old "uncalibrated 46-68%" was not the spell data: the
recorder was writing every own heal down as heal + overheal, so the **log** column was
inflated, not the engine column. A stream recorded before v0.14.7 (`v = 1`) is flagged in the
output and its share is not a statement about the engine. See `docs/SPEC-v0.14.md` §4b, §4c.

The `observed.lua` beside it is written by `wclrules.py --observed`:

```bash
python3 tools/wclrules.py .logs/wcl/waFx9B1kNQJWP3hq-103.json \
        --healer Samwellx --observed .logs/wcl-holdout-observed.lua
```

### `healcheck.lua` — this character's own heals against the model

```bash
bash tools/run.sh tools/healcheck.lua            # finds the SavedVariables the way import.lua does
bash tools/run.sh tools/healcheck.lua .logs/SpellTuner.lua
```

The client-side twin of `wclcheckkit.lua`: every own heal event in every recording, bucketed
by spell and kind, against what the model says that spell heals — with the **profile the
client itself wrote down**, so it is the one fully trusted calibration in the project.

Read it by the **minimum** column. A recorded amount is gross, so a bucket should be one
value; anything above its own minimum is overheal that should not be there. That is how
v0.14.7's recorder bug was found, and it is how the author confirms the fix: on the next
dungeon every bucket should sit on the model and stop running to twice it.

Lifebloom's tick is per-stack, so its bucket is three overlapping ones (1x / 2x / 3x a base);
the 1-stack cluster is printed separately.

### `solvercmp.lua` — the solver against the threshold rules

```bash
bash tools/run.sh tools/solvercmp.lua
bash tools/run.sh tools/solvercmp.lua --file .logs/wcl-all.lua
```

Sweeps `minValue` / `horizon` and prints the frontier against the rules baseline.

### `strategies.lua` — every strategy side by side

```bash
bash tools/run.sh tools/strategies.lua
bash tools/run.sh tools/strategies.lua --file .logs/wcl-all.lua --char "Blohz-Nightslayer"
```

Runs all of `SP.STRATEGY_SET` over every recording, on the same lexicographic tuple, and
marks which ones are causal. **This is the table to look at when choosing a strategy.**

---

## 3. Warcraft Logs

Credentials live in `.logs/wcl.json` (gitignored); the bearer token is cached in
`.logs/wcl.token` and refreshed automatically.

```bash
# 1. download one fight's raw event streams -> .logs/wcl/<report>-<fight>.json
python3 tools/wclfetch.py bdByCxDv6rVQhRMf 145

# 2. turn raw fights into SpellTuner recordings
python3 tools/wclconvert.py .logs/wcl/bdByCxDv6rVQhRMf-145.json --healer Blohz \
                            .logs/wcl/L8NJymzZW9RKtdYQ-27.json  --healer Ghnoy \
                            --out .logs/wcl-records.lua
```

**v0.14.7:** the `spellPower` a TBC log carries is the character sheet's **spell damage**, not
+healing, and the converter now scales it by `SPELLPOWER_TO_HEALING = 3.08` (measured by
`wclcheckkit.lua --fit` over 17 parses: min 2.66, median 3.08, max 3.46). Regenerate any
corpus converted before v0.14.7 — the healers in it are running at a third of their power.

`wclconvert.py` writes **two** files: `<out>.lua` (a SavedVariables-shaped database for the
offline tools) and `<out>-append.lua` (a block to paste at the end of the game's
`SpellTuner.lua` with the client closed, to replay the fights in-game — deleting the block is
the whole undo).

```bash
# 3. what the healer did, and the state of the fight when they did it
python3 tools/wclrules.py .logs/wcl/bdByCxDv6rVQhRMf-145.json --healer Blohz

# 4. what our model says a spell heals, against what the log says it DID
bash tools/run.sh tools/wclcheckkit.lua
#    ...and the other direction: solve each parse for the +healing that reproduces
#    it, one row at a time. Four families agreeing is what verifies Data/SpellData.lua.
bash tools/run.sh tools/wclcheckkit.lua .logs/wcl-records.lua .logs/wcl-observed.lua --fit

# 5. merge many imported fights into the shipped prior
bash tools/run.sh tools/buildintuition.lua .logs/wcl-all.lua
#    -> Data/Intuition_TBC.lua   (GENERATED - do not hand edit)
```

### What is on disk now

| file | what |
|---|---|
| `.logs/wcl/*.json` | 22 raw fights, kept so a conversion bug can be re-run without spending API points |
| `.logs/wcl-all.lua` | all 22 imported fights, 13 encounters — the corpus |
| `.logs/wcl-records.lua` | the two Nightbane parses (rank #1 and #50) |
| `.logs/wcl-*-append.lua` | the in-game paste blocks for each of the above |
| `Data/Intuition_TBC.lua` | the shipped prior built from `wcl-all.lua` |

**Two traps the converter documents, because both are silent:** `classResources`' key names
lie (`amount` is max mana, `type` is current mana, `max` is the cast's cost), and player
health is reported as a **percentage** — max HP is recovered by least squares against the
absolute damage and healing.

---

## 4. Not a tool

`harness.lua` (loads the addon files and returns `MD`), `wowstub.lua` (the fake client) and
`fakepull.lua` (the shared scripted pull) are machinery the suites use. Keep
`harness.lua`'s file list in step with `SpellTuner_TBC.toc`. `wowstub.lua` has two profiles:
`tbc` (the default, what every suite above runs under) and `forever` (what `probecheck.lua`
selects: no combat log, `issecretvalue`, a secret stand-in whose arithmetic raises, `C_Spell` /
`C_SpellBook`, a Forever build string).
