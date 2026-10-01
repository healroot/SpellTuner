# T99 -- capability gates: `isDruid` becomes `MD.ClassProfile:Can(cap)`

Status: **built** 2026-10-01 on branch `next/T99` (base `25748e3`), wave N3, awaiting the
integrator. Spec: `docs/SPEC-next.md` section 11 row T99; 2.1 (the profile, `Can`, the
`KitLive` provider and the "module" answer); 4.4 (the three kinds of `isDruid` read); section 3
(principles 1, 3, 10); 9.1 (every other decision as recommended). Research:
`docs/research/next/R-arch.md` 2 (the `isDruid` table), `CRITIQUE-next.md` point 10 (the full list,
the provider and the module-off answer). Needs T89 (profiles, `Can`) and T96 (`MD.KitLive`), both
in the base. Integrator-owned files were **not** edited; their lines are below. No TOC change:
every file touched is already listed, and `tools/capscheck.lua` is found by `tools/check.sh` on its
own (it declares `HARNESS_FLAVOUR = { "forever", "tbc" }`).

## What was built

- **`Spells/Profiles.lua`**
  - `Profile:Can(cap)` -> `true` | `false, why`, where `why` is `"class"` (the profile does not
    grant it -- checked first, so a class that is not modelled is told so whether or not a module
    is on), `"kit"` or `"module"`.
  - `P.LIVE = { coach = { provider = "KitLive", module = "SpellTuner_Replay" } }`: a capability that
    also needs a live answer. `coach` asks `MD.KitLive()` (T96, Kit_Forever.lua in the Replay
    module) when it is provided -- `false` (or a raise, caught) is `false, "kit"`. With no
    provider, the capability is the class's alone **unless the line declared the module** that
    provides it (`MD.modules`, filled only by `Core_Forever.lua`'s `MD:DeclareModule` -- a value
    the flavour installs, never a client check, apicheck rule 10), in which case the answer is
    `false, "module"`. So on TBC (no module declared, no provider) the druid coaches exactly as
    before; on Forever with the Replay module off `Can("coach")` is `false, "module"`.
  - The words: `P.ClassLabel(class)` (a registered profile's label, else the token title-cased --
    `PRIEST` -> `Priest`, `DEATHKNIGHT` -> `Death Knight` --, else `your class`; default the
    logged-in player's class); `P.Refusal(cap, why, subject, class)` -> `<subject>: not modelled
    for <Class> yet` (class), `<subject>: no heal in your spellbook is modelled yet` (kit),
    `<subject>: needs the Replay module` (module: the module placeholder's own words, the module's
    label from `MD.modules`); `P.RefusalNote(cap, why)` -> `not modelled` for a menu row. ASCII, no
    pipe, no full stop (a chat caller adds it).
- **The 23 gates in 10 files**, each now `MD.ClassProfile:Can(cap)`; a druid answers true wherever
  it did, so every druid surface is unchanged:

  | File | Line(s) at the base | Capability | A non-druid now sees |
  |---|---|---|---|
  | `UI/Dashboard_Review.lua` | 610 (Coach) | `coach` | chat `coach: not modelled for Priest yet.` |
  | | 662 (Coach run) | `coach` | chat `coachrun: not modelled for Priest yet.` |
  | | 693 (row menu notes) | `coach` | note `not modelled` (was `Druid only`) |
  | | 807 (validate on sight), 841, 843, 845 (buttons) | `coach` (asked once a paint: `canCoach`) | Coach / Coach pull off, as before |
  | | 863 (Coach's hover) | `coach` | `Coaching: not modelled for Priest yet` |
  | `UI/ReplayWindow.lua` | 1758 (`CoachOffered`), 1983 (`CoachOnOpen`) | `coach` | no Coach anyway, no automatic coach, as before |
  | | 2391 (`OpenPractice`) | `practice` | chat `practice: not modelled for Priest yet.` |
  | | (new, `OpenReplay`'s hint) | `coach` | hint `Coaching: not modelled for Priest yet` (was `no plan yet`) |
  | `UI/PracticePanel.lua` | 523 | `practice` | `Practice: not modelled for Priest yet`, Start off |
  | `Engine/ReviewCommands.lua` | 168 (`/md coachrun`) | `coach` | `coachrun: not modelled for Priest yet.` |
  | `UI/SimWindow.lua` | 75 (Run) | `simulate` | `Simulation: not modelled for Priest yet.` |
  | | 262 (header) | `simulate` | `  (Simulation: not modelled for Priest yet)` |
  | `UI/Dashboard.lua` | 58, 142, 287 | `rankTable` | `Rank analysis: not modelled for Priest yet - the OOM widget, datatext and advisor still work for your class.` |
  | `UI/SpellTooltip.lua` | 57 | `tooltip` | nothing appended, as before |
  | `UI/Advisor.lua` | 58, 85 | `advisor` | no rank toast, as before |
  | `UI/Summary.lua` | 496 (max-rank casts %) | `rankTable` | part left out, as before |
  | `Diagnostics_TBC.lua` | 227 (max-rank costs) | `rankTable` | `(rank table: not modelled for Priest yet)` (was `(druid-only)`) |

  `Summary.lua`'s max-rank share and the profile report's max-rank costs are **`rankTable`**, not
  `advisor` (R-arch grouped Summary with the advisor): both read Data/SpellData.lua's rank table
  (`SD:IsMaxKnownRank`, `SD.maxRank`), the capability T111 will grant a TBC class with a table of
  its own.
- **`UI/SimWindow.lua`**'s "engine not loaded" fallback (SP or SM missing, never on TBC) no longer
  says "Druid-only": `Simulation needs the engine, which is not loaded.`
- **`Core_TBC.lua:99`** (`InTreeForm`) keeps its read, with the comment saying why: Tree of Life is
  a druid form, a fact about the class rather than a capability. The other reads that stay
  (`Core.lua` x2, `Data/SpellData.lua:193`, `Engine/RankMath.lua:571`, `Spells/Families_TBC.lua:41`)
  are untouched; SpellData's is described in `capscheck`'s allow-list instead of a comment (the
  file changes only from a measurement), RankMath's and Families_TBC's are T111's.
- **`tools/capscheck.lua`** (new; forever and tbc), below.

## Failing first (the parent `25748e3` with the new suite, `git archive` export)

Both flavours: 1 ok, 4 FAIL, then a raise at the first `P.ClassLabel` (absent on the parent):

- `isDruid is read only in the six reads 4.4 keeps` -- FAIL: `Diagnostics_TBC.lua x1,
  Engine/ReviewCommands.lua x1, UI/Advisor.lua x2, UI/Dashboard.lua x3, UI/Dashboard_Review.lua
  x8, UI/PracticePanel.lua x1, UI/ReplayWindow.lua x3, UI/SimWindow.lua x2, UI/SpellTooltip.lua
  x1, UI/Summary.lua x1` (the 23);
- `each of the ten gate files asks MD.ClassProfile:Can` -- FAIL, all ten;
- `no gate file says "Druid-only" any more` -- FAIL, seven files;
- `Core_TBC.lua's InTreeForm read carries the comment saying why it stays` -- FAIL.

## The new assertions (`capscheck`: forever 32, tbc 34)

- **The source scan** (both): every `.lua` a TOC ships (the root TOCs and the three modules', 105
  files), comments left out, reads `isDruid` exactly in `Core.lua` x2, `Core_TBC.lua` x1,
  `Data/SpellData.lua` x1, `Engine/RankMath.lua` x1, `Spells/Families_TBC.lua` x1 -- no more, no
  fewer; each of the ten gate files asks `MD.ClassProfile:Can(`; none says "Druid-only" / "Druid
  only"; `InTreeForm`'s read carries the comment.
- **The words** (both): `ClassLabel`; `Coaching: not modelled for Priest yet`; the kit and module
  sentences; every refusal ASCII with no pipe.
- **The druid** -- tbc: every capability the gates ask (clock, tooltip, rankTable, advisor,
  simulate, coach, practice) granted, no module declared, no `KitLive`, the druid coaches.
  forever: every capability but coach granted before a module loads; **Replay module off:
  `Can("coach")` is `false, "module"`** and Review is the module's own placeholder (`Review needs
  the Replay module`), with no `not modelled` and no `Druid` on screen; Replay on: `MD.KitLive`
  provided and the druid coaches; a `KitLive` answering `false, "kit"` -> `false, "kit"`; one that
  raises -> `false, "kit"`, not a raise.
- **A priest** (`S.units.player.class = "PRIEST"`, `DetectProfile`, `CORE_LOGIN`: the generic
  profile): coach refused for the class's sake; keeps clock (and tooltip, rankTable on Forever);
  Review's Coach off, its hover `Coaching: not modelled for Priest yet`, a Coach press
  `coach: not modelled for Priest yet.` with no search; the replay's hint `Coaching: not modelled
  for Priest yet` and nothing coached; the practice panel `Practice: not modelled for Priest yet`
  with Start off, and `MD:OpenPractice` `practice: not modelled for Priest yet.`; tbc also the
  simulator's header and Run, `/md coachrun`, and the profile report; every line ASCII.
- **The druid again** sees today's: Coach on and its hover without a refusal, the practice status
  `about N damage a second ...` with Start on, the replay hint without a refusal; tbc the sim
  header and the profile report's max-rank costs; nothing printed says `not modelled`.

## Suites, before and after

`make check` green on the branch: 83 runs, all passed (the base: 81; +2 are capscheck's),
apicheck 0 findings, textcheck 0 findings, selftests green. Every count unchanged but the new
suite's:

| Suite | Before | After |
|---|---|---|
| `capscheck/forever` | -- | 32 |
| `capscheck/tbc` | -- | 34 |
| every other suite / flavour (76 runs) | n | n (unchanged) |

**Byte-identical**: every suite's output (`tools/.lua/check/*.out`) was captured on the base
before the first edit and compared after: `slashcheck`, `verifycheck`, `reviewui`, `practiceui`,
`simwindow` (the five the row names) and every other suite are identical except lines that carry a
frame-sliced search's evaluation / frame / millisecond counts or a table address (`coachforever`,
`kitcheck`, `practice`, `practiceforever`, `reccheck`, `recordcheck`, `replayforever`, `replayui`,
`reviewui`, `simwindow`, `solvercheck`: 0 other lines differ -- the run-to-run noise T96 already
names: a search sliced on `debugprofilestop()` moves by wall clock, an address by allocation). `slashcheck` and `verifycheck` compare against their own committed goldens and pass.

## Integrator lines

**`tools/data/expected-counts.json`:** add `"capscheck/forever": 32,` and `"capscheck/tbc": 34,`.

**`tools/check.sh`:** no change (capscheck is a suite by default and declares both flavours).

**`docs/DECISIONS.md`**, a new entry:

> ## Capability gates: "not modelled for <Class> yet" (2026-10-01, T99, docs/SPEC-next.md 4.4)
>
> The 23 `MD.player.isDruid` gates in 10 files ask the logged-in player's class profile instead,
> `MD.ClassProfile:Can(cap)` (coach, practice, simulate, rankTable, tooltip, advisor). The
> druid's profiles grant every capability a druid had, so nothing changes for a druid on TBC. A
> non-druid's wording changes: "Coaching is Druid-only in v1.", "Practice is Druid-only, like the
> rest of the healing model.", "(Druid-only in v1)", "Rank analysis is Druid-only in v1",
> "(druid-only)" and the menu note "Druid only" become `<subject>: not modelled for <Class> yet`
> (`Coaching: not modelled for Priest yet`, the menu note `not modelled`), and the replay's hint
> says it instead of `no plan yet`. On Forever `Can("coach")` also asks the Replay module's live kit
> (`MD.KitLive`, T96): with the module off it answers `false, "module"` and the module's own
> placeholder stays (no new words); a druid whose live kit prices no heal is refused coaching with
> `Coaching: no heal in your spellbook is modelled yet` -- the one change a druid can see, and
> only on Forever. The summary's `max-rank casts N%` and the profile report's max-rank costs are
> the `rankTable` capability (they read Data/SpellData.lua's rank table). Reads that stay druid by
> design: `Core.lua` (the fact), `Core_TBC.lua`'s `InTreeForm` (Tree of Life is a druid form),
> `Data/SpellData.lua:193` (the druid's own cost talents on its own table); until TBC other
> classes (T111): `Engine/RankMath.lua`'s `Compute`, `Spells/Families_TBC.lua`. `tools/capscheck.lua`
> fails on any other `isDruid` read in a shipped file.

**`CLAUDE.md`**, append to these rows:

- `Spells/Profiles.lua` (or the `Data/Profile_*` rows where T89's integrator put the profile
  registry): **T99 (4.4):** `Can(cap)` -> `true` | `false, why` (`"class"` first, then the live
  half: `P.LIVE.coach` asks `MD.KitLive` -- `false` or a raise is `"kit"` -- and, with no provider
  on a line that declared `SpellTuner_Replay`, `"module"`); `P.ClassLabel`, `P.Refusal(cap, why,
  subject)` (`<subject>: not modelled for <Class> yet`, `... no heal in your spellbook is modelled
  yet`, `... needs the Replay module`), `P.RefusalNote`. Every gate that read `MD.player.isDruid`
  asks `MD.ClassProfile:Can`; `isDruid` stays only in `Core.lua`, `Core_TBC.lua`'s `InTreeForm`,
  `Data/SpellData.lua:193`, `Engine/RankMath.lua`'s `Compute`, `Spells/Families_TBC.lua`
  (`tools/capscheck.lua`).
- `UI/Dashboard_Review.lua`: **T99:** Coach / Coach run / the row menu / the buttons / Coach's
  hover ask `MD.ClassProfile:Can("coach")` (once a paint); a non-druid is told `Coaching: not
  modelled for <Class> yet`.
- `UI/ReplayWindow.lua`: **T99:** `CoachOffered` / `CoachOnOpen` ask `Can("coach")`,
  `OpenPractice` `Can("practice")`; a non-druid's hint says why no suggested column will come.
- `UI/PracticePanel.lua`: **T99:** Start and the status ask `Can("practice")`.
- `UI/SimWindow.lua`: **T99:** Run and the header ask `Can("simulate")`.
- `UI/Dashboard.lua`, `UI/Summary.lua`, `Diagnostics_TBC.lua`: **T99:** the rank table, the
  summary's max-rank share and the profile report's max-rank costs ask `Can("rankTable")`.
- `UI/SpellTooltip.lua`: **T99:** `Can("tooltip")`. `UI/Advisor.lua`: **T99:** the rank toast
  `Can("advisor")`. `Engine/ReviewCommands.lua`: **T99:** `/md coachrun` `Can("coach")`.
- the `tools/` row: `tools/capscheck.lua` (T99, forever / tbc): the source scan (`isDruid` only in
  the six reads 4.4 keeps), the gates' words for a priest and a druid, the Replay module off ->
  `false, "module"` and the placeholder.

**`docs/TOOLS.md`**, section 1, a new row: "`capscheck.lua` (forever 32, tbc 34; **T99**) -- the
capability gates: a scan of every file a TOC ships finds `isDruid` only in the six reads
docs/SPEC-next.md 4.4 keeps (allow-list with reasons; comments left out); the druid is granted
what the gates ask; a priest (stub `S.units.player.class`) is told `<subject>: not modelled for
Priest yet` on Review, the replay, practice and (tbc) the simulator, `/md coachrun` and the
profile report; the druid sees today's; on Forever the Replay module off answers `false,
"module"` with the module's placeholder, a live kit pricing no heal `false, "kit"`."

**`docs/TESTING.md`** (section 46, optional): on a non-druid alt (either client), open Reports ->
Review and a replay (`/st replay 1` on Forever with the Replay module on): the Coach button is
off, its hover and the replay's hint read `Coaching: not modelled for <your class> yet`;
Simulate -> Practice reads `Practice: not modelled for <your class> yet`. On the druid nothing
changed.

**`docs/HISTORY.md`**: the integrator's wave entry. No TOC, `tools/check.sh` or
`tools/defaultscheck.lua` change; no default registered.

## Deviations from the spec

1. **Two suites outside the row's owned files were edited, minimally:** `tools/spelltip.lua`
   (tbc, "a non-druid gets nothing") and `tools/replayforever.lua` (forever, the one-column T72
   check) simulated a non-druid by setting `MD.player.isDruid = false`. The gates no longer read
   that flag, so both would have failed; each now swaps `MD.ClassProfile` for
   `MD.Profiles.generic` around the same check and puts it back. Same assertions, same counts
   (spelltip 49, replayforever 28), outputs identical but addresses. Neither file is owned by any
   other wave N3 task (T101 owns `practiceforever.lua`, which only sets the flag to `true` and
   needed no change). Other tools that set the flag (`import.lua`, `reviewui.lua`, `wincheck.lua`,
   `practiceui.lua`, `practiceforever.lua`, `importforever.lua`, the research tools) set it to the
   druid the stub already is, so their behaviour is unchanged; they now set a flag nothing gates on.
2. **The replay's hint gained a refusal line** for a non-druid (`OpenReplay`, not one of the 23
   reads): the row asks that a priest "sees the not-modelled wording on ... replay", and before
   T99 the replay said only `no plan yet` to a non-druid. A druid never reaches the branch.
3. **`Summary.lua` and `Diagnostics_TBC.lua` ask `rankTable`**, not `advisor` (the research note's
   grouping) -- both read Data/SpellData.lua's rank table; the spec names no capability for them.
4. **`MD.ClassProfile:Can` is called directly** (no nil guard) everywhere but `SpellTooltip.lua`,
   which kept its `MD.player and` guard's shape: every gate runs after `CORE_LOGIN`, where
   `MD.Profiles.Select` sets it.
