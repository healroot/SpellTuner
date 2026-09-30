# tools/ — the offline harness

Everything here runs the **real addon files** against a fake WoW client
(`tools/wowstub.lua`), so it catches ordering and arithmetic bugs a syntax check cannot.
Nothing in `tools/` ships: `release.sh` builds each package from its flavour's TOCs' own file lists.

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
| `navui.lua` | the navigation kit: lazy panes, one pane at a time, the remembered path Since **T31** (35, 0.16.2): the old 25 unchanged, plus a rail group with no view row and its content at -8, back to -32 on a view-row group, `SetViews` on a rail group creating no button, the button pool (five `SetViews` on Reports, the same frames), rail rows as views, a reorder reported once, a mask swallowing clicks on its region only, a list in `UI.LIST_STRATA` telling `UI.OnPopup`, the tree's second list above the first |
| `dashui.lua` | the one window, driven the way a mouse would Since **T30** (63, 0.16.2): the old 56 unchanged (an `opts == nil` table is the TBC one, gold included), plus the table options -- font, justify, row height, zebra, full-width rows, the bar cell, `marker = "bar"` with no `ffcc00`, in-place refresh, a bar column's header spanning the column |
| `regencheck.lua` | `/md regentest` against a scripted mana stream, and **what it stores** |
| `simwindow.lua` | every preset combination's scenario, baselines and search |
| `solvercheck.lua` | the solver: deposits, the gap integral, causality, the four forecasts, the explainer. Since **T20 / T20b** (77, review R6): the danger line a plan reads is the biggest hit so far (the scenario's prior, else the floor, before the first), a hit bigger than any before it changes nothing the solver does before it, the score still counts seconds under the whole-fight line, and the prior is the biggest hit that person took in **other** recordings, the exclusion required |
| `timeline.lua` | the run's clock: segments, seeks, health across a gap |
| `restcheck.lua` | **the coach values regen** (2026-09-29, 51): the engine's mana accounting (paid, regenerated and potion mana after the floor and the cap, `manaStart - manaEnd = paid - regen - potion`, the rule's tail and its debt, `manaUsed`); the solver's price in units (`SV.Forfeit`: R x 5 out of the rule, the extension inside it, 0 at a full pool and when base == casting, TBC near the cap); base == casting deciding cast for cast as the regen-blind solver, on a level 10 party and on a TBC recording; the rule state reaching `Decide` by cursor and after the classifier's hook, a rate sample at 30 s changing nothing before it; rule 8 owning a target projected far through the floor, never priced; **the author's practice fight** (`tools/data/practice/1790701698.lua`: every gate, 21 mana at the end, and the coach now regenerating more, ending higher, using less, with no more deaths, danger seconds or owed and the same lowest health) and 180 synthetic level 10 fights; the score ranking mana used (425 spent / 76 left beats 385 / 24 under every objective), the stated owed-term bias, the search's abort past a later Innervate or a recorded potion, the run's rule tail and score, the replay's `used` |
| `practice.lua` | a practice session played against a fake clock: the seeded damage, the game's rules, the live trace, and **the recording replaying to exactly what was played**. Since **2026-09-29** (80): the record carries its kit, client, level and version and replays with that kit to every mana sample the session wrote; `PR.Pin`, a pinned fight surviving eight more, the cap of four pinned |
| `practiceui.lua` | practice from the screen: panel, Start, presses on frames and keys over them, pause, End, the replay, Review's Practice list. Since **2026-09-29** (50): Review's Pin on a practice fight |
| `spelltip.lua` | the spell tooltip (v0.14.9): druid only, once per showing, off means off, and **every number on it is the model's own** — the tick and bloom the simulator heals with, the dashboard's heal |
| `migrate.lua` | the rename (2026-09-27): a ManaDemon WTF comes up as SpellTuner's with every setting, recording and practice fight; `/md` still answers |
| `forevercheck.lua` | **the Forever TOC under the Forever profile** (T5, forever): loads clean, loads exactly the TOC's files, never tries the combat log, and the stub keeps secrets and absences as build 70009 does -- so arithmetic on current health trips here as it does in the client |
| `adaptercheck.lua` | **the client adapter** (T1, forever and tbc): every binding in the capability table, absent / error / secret answered as `nil` plus a reason, returns kept whole, nothing secret ever leaving `MD.API`, the combat log forbidden on Forever only. Since **T17c** (22 / 15): `MD.API.HealthMax` -- off until the probe says so (`BAR_READS_MAX`), a bar that hands back a secret giving `nil, secret`, a plain read-back giving the number, a raising bar `nil, error` |
| `corecheck.lua` | **the shared kernel** (T1b, forever and tbc): events, callbacks, ticker, the forbidden-event guard, the command registry, `Print` through the adapter; on Forever `/st probe` through the kernel and nothing registering the combat log; on TBC its talents, profile, login order and slash chain as before |
| `modulecheck.lua` | **the modules and the Forever window** (T2, forever): the three siblings declared in dependency order, off means never loaded, on loads what it needs first and at every login, off switches off what needs it, a refused load says why, the sibling TOCs, `/st` opening and closing the window, the Modules pane switching, every string on the window ASCII. The stub loads a sibling from `Modules/<Name>/` the way the client loads a LoadOnDemand addon. Since **T13c** (14): a module's files see SpellTuner's `MD`, and a TOC entry under `Engine/`, `Spells/`, `Data/` or `UI/` loads from the repository root |
| `kitcheck.lua` | **the Forever spell kit** (T15, forever): `MD.RankMath:SpellKit()` exists only once the Replay module loads; each known healing rank valued from its own text (3 s tick, UNVERIFIED on Forever); Swiftmend eats the whole HoT; unknown ranks, damage spells and Wild Growth left out (and named in `SpellData.skipped`); the spell index; `SimModel:Run` on the kit; crit as a Nature fraction, never secret |
| `recordcheck.lua` | **the Forever recorder** (T13, forever): nothing registered until the Recorder module is on; a scripted 40 s party pull through the real events -- `UNIT_COMBAT` per tracked token once (mirrors under `target` / `nameplate1` ignored), own casts with their SENT target and book cost, a cancel decided whatever order STOP and SUCCEEDED arrive in, indices kept across a roster swap, party max health `-1`, modelled mana every 2 s, a death, a secret counted not stored, pre-pull HoTs read out of combat only, the keep/drop gate and the ring of 8, the damage meter read after combat, `/st rec` ASCII, `List` / `Get` / `Pin` / `GetRecording`. Since **T17c** (15): with the adapter's status-bar readback on and a bar that reads back plain, a party member's max recorded plain (`maxVia = "bar"`). Since **the 2026-09-29 review** (24): a member dead at the pull not dying in it, the opener at t=0 and a pre-cast HoT in `initial.auras`, an empty or partial meter read as `none`, the healer's own death at the end, no meter read once the next pull started, departed members' tokens dropped (R7-R11, R24, R25) |
| `scenariocheck.lua` | **a v3 stream becomes the engine's scenario** (T13d, forever), on `tools/foreverfixture.lua` (the hand-built v3 stream T14, T16 and T17 reuse): v2 takes the old road; sourceless heals attributed own by direct window and by HoT cadence (both the recast's own and the inherited one, since the client's refresh behaviour is UNKNOWN), everything else foreign; a pre-pull HoT; health as a deficit on a 2 s grid; a party member's max the stated estimate; unpriced casts fixed with their book kind; the engine replaying the scenario to the reconstructed health. Since **the 2026-09-29 review** (12): Swiftmend ends the HoT it eats, a pre-pull HoT's remaining ticks by ceiling with the replay still exact, direct claims matched by size (R28-R30) |
| `gatecheck.lua` | **the eight gates on a v3 recording** (T14, forever), on `tools/foreverfixture.lua`: v3 to the Forever gates, v2 to the old; the mana gates say "modelled pool"; health against the reconstruction, "max estimated"; foreign share and calibration from the damage meter, no reading failing both; spend coverage by the book; gate 8 "heals attributed" failing a shortfall, the long side only once `SM.HEAL_AMOUNT` is effective; every text ASCII. Since **the 2026-09-29 review** (9): an excluded target's line says `max estimated` (R27) |
| `replayforever.lua` | **the replay window on a Forever recording** (T16a, forever): `/st replay`, `/st validate`, `/st coach` only with the Replay module; a v3 stream opened with a row per tracked target, played to the end with bars following the reconstructed health, its ticks drawn, the "health reconstructed ... party max estimated" line, the suggested column after the search, seek == play, the Forever gates printed and a failing fight refused unless forced, every painted string ASCII (a non-ASCII name and a `\|` in the fixture), no opening in combat. Since **the 2026-09-29 review** (11): a v3 tick's hover and the ticks checkbox say reconstructed, not recorded (R5) Since **T43** (14): no `ffcc00` in the replay's header, run strip or `MD.Tip` under the theme. Since **T34** (15): the replay registered as the manager's takeover |
| `reviewforever.lua` | **the Review tab in the Forever window** (T16b, forever): a Reports group with a Review view; with the Replay module off a placeholder that loads nothing, replaced by the tab when the module comes on; a row per v3 recording with its validate result, the tooltip carrying every Forever gate, Coach refusing a failing fight and shift-click coaching it, Play opening the replay window, every painted string ASCII. Since **the 2026-09-29 review** (10): low mana `~N%` as modelled, Export hidden without `MD.RunExport` (R39, R40) Since **T43** (11): Review's run line in the accent and its small strings in `UI.FONT_SMALL` |
| `coachforever.lua` | **the coach and the solver on a v3 recording** (T17, forever): a plan found for a clean fixture, binding only families the player had and never Lifebloom; the card ASCII and naming its gates; every recorded cast labelled; the solver as a strategy on the Forever kit; the causality invariant on a v3 scenario; the zone's marks; the asynchronous coach filling the replay window. Prints one solver-vs-rules line. Since **T17b** (13): the causality assertion runs with the party member's max **secret**, as it always is on Forever, taken from another recording of them; a party max from other recordings of the same name and level, never the one coached; a plain max elsewhere taken as it is; the exclusion required; with no other recording the plan flagged `foresees` and its card saying `NOT causal - sees this fight`, and silent otherwise. Since **the 2026-09-29 review** (16): `/st coach N safe` (or `health`, `cheap`, `regen`) picks a strategy, the card keeps its colour codes, no `solver-corpus` without its prior (R12, R26, R23). Since **T20 / T20b** (18, review R6): a burst above every earlier hit changes nothing the **solver** does before it, and a Forever target's danger prior comes from other recordings of the same name and level |
| `practiceforever.lua` | **practice on Forever** (T18, forever): Simulate -> Practice, a placeholder until the Practice module is on; the panel from the Forever kit's spells; a session against a fake clock recording a practice stream that replays to the health the player saw with every gate passing; a bound key casts, an unbound one propagates; End reopens it as a replay and lists it in Review; `/st practice` / `/st binds` only with the module; every painted string ASCII. Since **the 2026-09-29 review** (9): the scenario and the recording regenerate at `GetManaRegen`'s rates (R4) Since **T24** (15): nothing bound by default on Forever and the panel pointing at Import / Edit bindings, an exact copy of the TBC defaults dropped once (any other list kept whole), a bind for a spell not in the spellbook labelled and casting nothing, the picker only the book's families, a new row a spell you have, Start refusing with nothing bound Since **T27** (20): a binding for a spell not in the book not listed, not counted, not cast and still saved; an import skipping and naming it; learning the spell bringing it back; Forget deleting it. Since **T40** (24): no `ffcc00` in the panel or the bindings sheet, one ESC closing the sheet and not the window, no fight field past the pane's right edge at 900 wide, the summary not counting a hidden binding Since **2026-09-29** (the recordings work, 25 with T40's): the record carries the book's kit and replays with it alone |
| `bindscheck.lua` | **`/st binds check`** (T19, forever): the report's three sections (key bindings, Cell, Clique) in order, ASCII, no bare pipe; absent add-ons said absent with nothing raising; a Cell table in the TBC shape recognised and its first entry shown; an unknown Cell or Clique shape refused with what was expected and what was found; the first binding rows whole and a count of what resolved to a slot, a spell and a macro |
| `svcheck.lua` | **the SavedVariables guard** (T4, forever and tbc): a first run, a database that came back with its session, one without a stamp, a broken one replaced rather than indexed, the guard running before the probe, the line in the debug log; TBC's database never stamped |
| `consolecheck.lua` | **errors, the console and `/st dump`** (T3, forever and tbc): our error recorded once and counted, shown to the client once; another addon's passed through; a sibling's counted as ours; the handler never raising; the 50-entry cap; the dump's sections in order, escaped to ASCII; `/st debug` with the error count and no Regen test button on Forever; every Forever TOC's version; TBC with no handler and its button kept. Since **the 2026-09-29 review** (14 / 1): the Enable box on Forever, the stack line naming the frame that raised, the previous handler called with no frame of ours between (R15, R16, R21, R22) Since **T33** (17 / 1): on Forever the console a `FULLSCREEN` tool with its remembered place and one ESC-stack entry, the copy box `FULLSCREEN_DIALOG` closing open lists; TBC keeps `UISpecialFrames` |
| `parsecheck.lua` | **`Spells/Parse.lua`** (T8, forever): 54 sourced descriptions (`tools/data/parse-fixture.lua`: the probe's own texts and talentsforever's beta texts, every class) read exactly -- or refused -- plus costs, cast lines and ranks; **no number is ever invented**, and nothing raises whatever it is given. Since **T7b** (11): the `\|4singular:plural;` escape expanded, a reflect clause not a cast's damage. Since **the 2026-09-29 review** (12): wards and reactive damage refused (R35) |
| `bookcheck.lua` | **`Spells/Book.lua`** (T7, forever): the book read through the skill lines or the slot walk, families in rank order, every value from the spell's own text, gaps, the four cost states, per mana / per second / casts to OOM, dominance and the suggested rank, a secret description keeping its last value, **nothing handed out secret**, the cache, `ReadSpell`. Since **T7b** (15): the shapes build 70009 returned -- a free spell, the `\|4` escape, Thorns' reflect. Since **the 2026-09-29 review** (17): Rage / Energy / Focus costs not mana, a stale value kept through several unreadable rescans (R13, R41) Since **T38** (21): `Book:Compare`'s numbers for Healing Touch R1 against R2, `shape` per family, `dominatedBy` an id |
| `tipcheck.lua` | **the spell tooltip block** (T9/T10/T10b, forever): registered through the adapter for the Spell data type, once per showing, every number the book's, the comparison with the highest rank, the suggested rank, gaps, a secret id or a builder error never reaching the game's tooltip, off means off, the per-second interval named by kind. Since **the 2026-09-29 review** (17): `Casts to OOM from full`, the crit range `1.5x, unverified`, `no mana (10 Rage)` (R31, R42, R13) Since **T25** (22): a macro's tooltip gets its spell's block from the tooltip data and, failing that, through its action slot (`GetMacroSpell` or a `spell` sub-type, `owner.action` or the `action` attribute), once per showing, nothing and no raise on a macro with no spell, a secret id or a raising owner, and off means off (two Macro post-calls: the probe's own, then the adapter's) Since **T28** (27): a macro's untyped first line giving the block, the `SetAction` path from the slot argument with no owner, Macro plus SetAction on one showing giving it once, `/st tooltip why` naming each step and outcome, a raising owner adding nothing. Since **T37** (37): the new shapes -- ASCII, no bare pipe, at most 5 plain lines fresh and 6 stale with the stale line last, the gap line and the range only with the detail key, an Other spell's two lines and no hint, no block for a free Other spell, the `- macro` marker, the refresh on the key |
| `clockcheck.lua` | **the Forever mana clock** (T11, forever): the pool assumed full at login, a cast's cost at success, the five-second rule across its boundary, the out-of-combat regen rate carried into combat, re-anchoring, warmup / OOM / FULL, `~` in text and hover, unpriced casts counted, **the real pool handed to the bar unread**, visibility. Since **T11b** (15): the TBC clock's thresholds, hysteresis and warm-up wording. Since **the 2026-09-29 review** (17): an Energy cast spends no mana, a login mid-fight starts in combat (R13, R36, R37) Since **T41** (20): the `bg` fill and pixel edge, the 1-px backing behind the bar, re-snapped on a scale change |
| `spellsui.lua` | **the Spellbook pane** (T10/T10b, forever): every family under Heals / Damage / Other with section titles, each row the book's numbers, dashes never zeros, the clock's pool for casts to OOM, the hover, the export read back by `refcheck.py`, refresh while shown only, no module loaded. Since **T10c** (15): every header, title and note on one line; Other only for spells cast for mana. Since **the 2026-09-29 review** (17): the pane never rewrites the book's own casts to OOM, a Rage cost shown as such (R38, R13) **Rewritten for the Forever UI** (T36 34 -> 35 with the picker's ESC entry, T38 43, T39 47): the rail lists the seeded families, a tick adds a view, `/st spell` selects one, a drop adds at the row and leaves the cursor as it was, the rail takes a drop while the picker is open, at offset +2 rail rows 22 tall; one spell's view (header, strip, RANKS, card, the game's tooltip on a row, no `ffcc00` anywhere); Overview's My spells and Whole book (a row per known rank of every family, a gap row, `+` adds), and the Export read back by `refcheck.py` with its format unchanged |
| `measurecheck.lua` | **`/st measure`** (T12, forever): nothing registered until asked, a heal on yourself and a Wrath on the target matched and judged (`in range` / `crit range` / `BELOW range`), a HoT's ticks, other units ignored, a secret amount counted and never judged, the dump. Since **T12b** (18): several watches at once, a heal landing before its own cast event, a HoT's ticks kept through another cast, a DoT's through the next casts, an amount that fits two casts `ambiguous`, a damage shortfall a possible resist, a heal shortfall BELOW only with the known deficit behind it, `capped at missing health`, bonus healing from before combat, a recast ending a watch as `refreshed`. Since **the 2026-09-29 review** (26): the deficit counted in combat only, a cast named at another unit not judged, `target not known`, a HoT crit at 1.5x counted, the lists escaped (R1, R14, R32-R34) Since **T26** (30): each kept line stamped with version and build, the dump showing this version's lines and counting older ones, `dump all` with stamps, `/st measure clear` |
| `probecheck.lua` | **the Forever probe** (T0) under the stub's `forever` profile: never raises, a missing function is "absent" not an error, a secret is "secret" not a sum, a bad event is caught, the report is ASCII with no bare pipe and keyed by build, the sections are in order, the description dump is whole, the TOC that loaded is named; since **T0c** also a blocked action recorded with what the probe was doing, the combat log registered only by `/st probe clog`, the secret readings and restriction state, Q1 by bonus damage or level with was/now lines, Q6 at level 10, and the release carrying exactly three TOCs (since **T23**: the Forever package two, the TBC package one, each `Client/TOC_*.lua` only in its own); since **T7a** the `== shapes` section (every return shape M2 reads, in and out of combat, and `UNIT_SPELLCAST_SUCCEEDED` counted). Since **T13b** (71): a passive's "Health" / "taking damage" not taken for a heal or damage spell, the tooltip lines of a direct heal, a HoT and a damage spell, party1's six readings out of combat and in the snapshot, `UNIT_COMBAT` per token with mirrors. Since **T13e** (73): a status bar handed a secret reports whether it reads back secret, plain, or raises. Since **the 2026-09-29 review** (82): the snapshot only in combat, `SpellTunerDB at load` from the guard, pets their own class, mirrors by GUID, `no cost`, blocked actions of the `SpellTuner_` modules (R2, R3, R17-R20) Since **T25a** (86): the Spell and Macro data types, a macro action's `GetActionInfo`, `GetMacroSpell` and tooltip data whole (a pipe escaped), a hovered macro recorded by the probe's own post-call with its to-do line, nothing raising on a secret or raising client Since **T33** (87): the `== windows` section's `esc=` line |
| `releasecheck.lua` | **the two packages and the installs** (T23; no harness, it only runs `release.sh` into `tools/.lua/releasecheck/scratch tree/`, a path with a space, and never into a real client): the TBC package exactly `SpellTuner_TBC.toc` and its files, the Forever package exactly the two Forever TOCs and theirs plus the three modules each exactly its TOCs' files, no TOC of the other flavour in either, every packaged TOC at the tree's one version, the two zips named by flavour and version holding exactly their package; on a scratch copy of the tree (`git ls-files`, so uncommitted work is in it; a `git archive` export needs a throwaway `git init` of its own): the build refused when two TOCs disagree, `--set-version` rewriting only the version lines (a CRLF TOC keeping every CR) and refusing `1.0`; an install into a `_classic_beta_` folder leaving only the Forever package (a stale TBC TOC and file gone, another addon kept), into an `_anniversary_` folder only the TBC package with the modules removed, an unknown path refused with nothing written, an explicit flavour against the path refused, the explicit flavour into an unknown path installed (13) The disagreeing version it writes is `9.9.9-disagree` since 0.16.1 (it wrote `0.16.1`, which stopped disagreeing the day the tree became 0.16.1) |
| `themecheck.lua` | **the Forever theme** (T29, forever, 23): no gold in `UI.TEXT`, the fonts built, a font offset of +4 clamped to +2, `UI.Pitch(20)` at -2 / 0 / +2, `UI.px` at scales 0.64 / 0.71 / 1, `UI.RestylePixels` giving a registered frame the new edge; nothing of it on TBC |
| `tabscheck.lua` | **the spell list model** (T35, forever, 24): the seed (known heals by learn level; mana-costing damage when there is no heal), the reconcile appending a newly known heal once with its dot and never a removed family or a damage spell, a stale entry kept, a renamed family renamed in place, add / remove / move / undo / reset, `cdb.spellTabs` initialised at login |
| `wincheck.lua` | **the window manager** (T32-T34, T42, forever, 53; the frame geometry is modelled by the suite itself, not the stub): strata by role, a per-group size restored, a group switch keeping the TOPLEFT, the clamp, a scale change converting the saved place, a scale event restyling; the ESC stack (one ESC one entry, the proxy re-armed, a window closed by its x leaving no entry, a code hide popping nothing, practice's entry staying on its first ESC, the console one entry, the `escStack = false` fallback), combat hiding and restoring the path (only the replay coming back during a takeover); the takeover (the main window hidden and given back on its path, no back button from chat, the placement at scales 0.71 and 1, `/st` closing a replay and refused during practice, End opening the replay without the main window, `replayPos` migrated once, practice's ESC pause then end); Settings' controls each writing its `db` field and applying it, reset clearing `db.ui.win` |
| `importcheck.lua` | **the recordings pipeline** (no harness of its own; it runs `tools/import.lua` as the planner does, 19): on `tools/data/import-forever-sv.lua` -- built by `tools/importfixture.lua` with the real Practice and Recorder code: p1 (48 s, a twelve-second window of no casting in the middle) stored with its kit, p2 stored without one as 0.16.1 stored every practice fight, and one v3 pull -- the committed fixture byte for byte what the code writes today; the game storing each fight's kit and the character's last one (`rec.kit`, `cdb.kit`), every one the same lean record (`SM.KitSnapshot`: entries only, no `MD.SpellData` copy) and a practice fight with its client, level and version; the file read as Forever told or not; `list` with kit and verdict; `validate`; `replay pN --strategy`'s YOU column exactly the fight as played (spent, the mana at its end), the 5SR marks, the plan's reasons and waits; p2 replaying exactly from the kit read back off its own heals; the pull without its kit using the last kit, then the stub's book, and saying which; `coach` (the card; a failing pull refused, forced); `coach --strategy` (that strategy's card); an unknown strategy refused; `export` writing an importable file and the text; `report pN` (the replay beside every strategy) on the file and on the author's fight read with `--fixture`; a TBC file still taking the TBC road |

```bash
for t in simcheck reccheck replaycheck replayui runcheck reviewui navui dashui \
         regencheck simwindow solvercheck restcheck timeline spelltip practice practiceui \
         migrate probecheck forevercheck modulecheck kitcheck recordcheck scenariocheck gatecheck replayforever reviewforever coachforever practiceforever bindscheck \
         parsecheck bookcheck tipcheck clockcheck spellsui measurecheck releasecheck importcheck \
         themecheck tabscheck wincheck; do
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
bash tools/run.sh tools/import.lua report p1            # the replay beside every strategy
bash tools/run.sh tools/import.lua --fixture tools/data/practice/1790701698.lua report
bash tools/run.sh tools/import.lua spells 1             # where the mana went, by kind
bash tools/run.sh tools/import.lua export 1             # -> .logs/recordings/<id>.txt
bash tools/run.sh tools/import.lua runs                 # stored runs
bash tools/run.sh tools/import.lua validate 3 --run 1   # run 1, pull 3 (the "1:3" address)
```

Options: `--file <path>` (default `$MD_SAVEDVARS`, then `.logs/SpellTuner.lua`, then the
author's install), `--fixture <path>` (a `{ rec, kit }` file such as
`tools/data/practice/1790701698.lua`, read as practice fight p1), `--char "Name-Realm"`, `--run K`,
`--flavour forever|tbc`. `pN` addresses practice fight N (p1 = newest) wherever a number addresses
a recording.

**`report N|pN`** (both clients; `tools/practicereport.lua`'s until the 2026-09-30 merge, now
`tools/reportlines.lua` under both halves of `import.lua`) puts the fight's own replay beside every
strategy in `SP.STRATEGY_SET` on the same fight: spent, regenerated, **used** (what left the
pool), mana at the end, owed, deaths, seconds one hit from death, lowest health, casts, lowest mana,
with the gates on top and, for a practice fight, the client, level, version and build it was
played on. A wrong kit fails the gates. A fight that carries its kit (`rec.kit`) is replayed with
it on either client. SavedVariables reach the disk only on `/reload` or logout.

### `import.lua` on WoW: Forever -- practice fights and pulls from the beta

The recordings pipeline: the author plays, `/reload`s, and says which fight (docs/TESTING.md §43);
the planner reads it here. The file is the beta's own SavedVariables, read from the author's
install by default (`/mnt/e/Blizzard/World of Warcraft/_classic_beta_/WTF/Account/*/SavedVariables/SpellTuner.lua`);
a file is recognised as Forever without `--flavour` by what only Forever writes (a v3 stream, a
kit, the SavedVariables guard's session stamp, the probe's reports). The Forever half is
`tools/importforever.lua`: the Mainline TOC under the stub's forever profile, the three modules on,
over the file's database -- the same engine, gates, planner and solver the game runs.

```bash
bash tools/run.sh tools/import.lua --flavour forever list          # every pull (1..) and practice fight (p1..), kit, verdict
bash tools/run.sh tools/import.lua --flavour forever validate p1    # the Forever gates, as /st validate
bash tools/run.sh tools/import.lua --flavour forever replay p1      # both columns as text (the search first, as the window does)
bash tools/run.sh tools/import.lua --flavour forever replay p1 --strategy solver-frugal   # the chooser's pick
bash tools/run.sh tools/import.lua --flavour forever coach p1       # the search and the card, as /st coach
bash tools/run.sh tools/import.lua --flavour forever coach p1 --strategy solver-frugal    # that strategy's card
bash tools/run.sh tools/import.lua --flavour forever coach 1 force  # a pull that fails its gates, anyway
bash tools/run.sh tools/import.lua --flavour forever report p1      # the replay beside every strategy
bash tools/run.sh tools/import.lua --flavour forever export p1      # -> .logs/forever/p1-<id>.lua + .txt
```

`replay` prints what the replay window shows at the end of the fight for each column -- spent,
regen, overheal, lowest, dead, mana at the end -- plus **seconds outside the five-second rule**; the
mana every 2 s side by side with `*` where that column was regenerating at the full rate; every cast
of yours with the classifier's label and why; the plan's casts with the rule's own sentence and
every wait of 2 s or more. `--strategy` is the window's chooser: a planner (`rules`, `rules-hots`,
`solver-blind`, `solver-prior`, `solver-sight`, `solver-frugal`, `solver-near`, built on demand) or a
reading of the search (`safe`, `health`, `cheap`, `regen`). `export` writes the fight alone as a
SavedVariables file (`--file` imports it again) and the replay text beside it; `--out <dir>` moves it.

**The kit.** On Forever the spells are read from the live spellbook, which offline is the stub's
(Healing Touch R1, Rejuvenation R1-R2). So since the recordings pipeline every fight is stored with
the kit it was played with (`rec.kit`, on practice fights and Recorder pulls with the Replay
module on), and every kit the game builds is kept as the character's last (`cdb.kit`). All three
are one record, `SM.KitSnapshot` (Engine/SimModel.lua, both clients): each form's entries with
their plain fields, the crit, the time and the level -- a kit as it stands, with no copy of the
`MD.SpellData` index; `RM.KitRestore` (Kit_Forever.lua) rebuilds the part of the index a replay
reads from the entries. The tool replays each fight with, in order: its own kit (`recorded`); for a
practice fight stored before that, the kit read back off its own heals (`inferred` -- exact for every
spell the fight cast, crit folded into each heal, nothing for a spell it did not cast); the
character's last kit (`last`); the stub's book (`STUB` -- the numbers are not the author's). `list`
has a kit column and every report a `kit:` line.

`bash tools/run.sh tools/importfixture.lua` rebuilds `tools/data/import-forever-sv.lua` (the
fixture `importcheck.lua` runs every command on) whenever what the code stores changes;
`importcheck` fails until it is.

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
