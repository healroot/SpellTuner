# T23 -- two installations from one tree: a TBC package and a Forever package

Status: **accepted** 2026-09-29 (handed out after T22, 6d755f6).

## Goal

`release.sh` builds two packages from the same tree -- a **TBC** package (`SpellTuner/` with only
`SpellTuner_TBC.toc` and the files it lists) and a **Forever** package (`SpellTuner/` with the two
Forever TOCs and their files, plus `SpellTuner_Recorder/`, `SpellTuner_Replay/`,
`SpellTuner_Practice/` beside it) -- zipped as `SpellTuner-tbc-<version>.zip` and
`SpellTuner-forever-<version>.zip`. An install puts exactly one flavour into one client: the flavour
is explicit or detected from the path, an install that cannot tell is refused, and installing a
flavour removes the other flavour's files from that client. The build refuses when the TOCs
disagree on the version, and `--set-version` bumps all of them in one command, so the TOCs stay the
single source of the version (T22). A new suite, `tools/releasecheck.lua`, proves each package holds
exactly its flavour's files. For the author, who plays both clients from one tree.

## Facts

- The ruling (`docs/DECISIONS.md` "One version, two installations (2026-09-29)"): "lets have single
  addon version and just separate installations"; TBC package = `SpellTuner/` with only
  `SpellTuner_TBC.toc` and its files, no Forever TOCs, no Modules; Forever package = `SpellTuner/`
  with `SpellTuner_Mainline.toc` + `SpellTuner.toc` and their files, plus the three module folders.
- The version's source is the TOCs, kept equal (T22, `docs/tasks/T22-one-version.md` Facts, and its
  lead review). T22 set all nine to `0.16.0` and made `consolecheck` case 10 hold them equal.
- `release.sh` today (at 2696187): one package `$OUT/SpellTuner` holding the **union** of every root
  `SpellTuner*.toc`'s files (lines 144-176), the modules at `$OUT/<Name>` (186-248), one zip
  `$OUT/SpellTuner-$VERSION.zip` (262-285, `zip` if present else a `python3` `zipfile` fallback --
  **this machine has no `zip`**, so the fallback is what runs here), the version from
  `SpellTuner_TBC.toc` else `SpellTuner.toc` (79-85), and `--install DIR` / a positional
  path / `$WOW_ADDONS` copying everything into one AddOns folder (116-127, 287-301) -- which is how a
  TBC TOC ended up in the author's beta
  (`/mnt/e/Blizzard/World of Warcraft/_classic_beta_/Interface/AddOns/SpellTuner/SpellTuner_TBC.toc`
  is there today). The worktree machinery (`list_sources`, `resolve_source`, `menu`, `--src`,
  `--list`, `--menu`, `--out`) stays as it is.
- T13c's rule for a module TOC entry (lines 219-236): an entry not in the module folder but under
  `Engine/`, `Spells/`, `Data/` or `UI/` is copied from the repository root to the same relative
  path. Unchanged.
- Interfaces (`grep '^## Interface' *.toc Modules/*/*.toc`): `SpellTuner_TBC.toc` 20506; the two
  root Forever TOCs and all six module TOCs 16001. `tools/apicheck.py` already calls a TOC with an
  interface in 16000-19999 a Forever TOC.
- The author's clients (`ls "/mnt/e/Blizzard/World of Warcraft/"`): `_anniversary_` (TBC),
  `_classic_beta_` (Forever beta), `_classic_era_`, `_retail_`. The two paths the author installs
  into: `.../_anniversary_/Interface/AddOns` (TBC) and `.../_classic_beta_/Interface/AddOns`
  (Forever). The Forever launch client's folder name is **UNKNOWN**, so an unknown path is refused
  and the explicit flag is the way in.
- The only suite that runs `release.sh` today: `tools/probecheck.lua` 623-667 (`release.sh --out
  tools/.lua/probecheck-release`, then check "the build ships three TOCs" on
  `$OUT/SpellTuner/*.toc`). That layout goes away here, so that check changes (Files).
- `Makefile`: `install` passes `--install "$(WOW_ADDONS)"`; `.RECIPEPREFIX := >`.
- `tools/.lua/` and `dist/` are gitignored; `tools/run.sh` passes the root as `arg[1]`.

## Files

| file | change | role |
|---|---|---|
| `release.sh` | rewritten build and install (below); header comment rewritten to match | the one release script |
| `Makefile` | `install` takes an optional `FLAVOUR=tbc\|forever` (`--install-$(FLAVOUR)` when set, else `--install`, which detects); usage comment updated | wrapper |
| `tools/releasecheck.lua` | **new** suite (Acceptance 1) | proves the packages and the installs |
| `tools/probecheck.lua` | the release check follows the new layout (Acceptance 2); nothing else | Forever suite |

`release.sh`, precisely:

1. **Classify the TOCs** of the source: every root `SpellTuner*.toc` and every `Modules/<Name>/<Name>*.toc`
   by its `## Interface:` line(s) -- every value in 20000-29999 is `tbc`, every value in 16000-19999
   is `forever`; anything else (or a mix, or a module TOC that is not `forever`) is an
   `ERROR: <file> has interface <v>: neither tbc nor forever` and exit 1 before any output is touched.
2. **One version.** Read every TOC's `## Version:` line; if they are not all equal, print
   `ERROR: the TOCs disagree on the version:` and one `  <relative path>: <version>` line per TOC, and
   exit 1 before any output is touched. `--list` / `--menu` show that version, or `mixed`.
3. **Build** `--flavour tbc|forever|both` (default `both`; an install builds at least what it
   installs): `$OUT/tbc/SpellTuner/` = `README.md` + the tbc root TOC(s) + the union of their entries;
   `$OUT/forever/SpellTuner/` = `README.md` + the forever root TOCs + the union of their entries, and
   `$OUT/forever/<Name>/` per module exactly as today. Every listed file must exist (the existing
   error). Before writing, remove the flavour folder being rebuilt and the **old-layout** folders
   `$OUT/SpellTuner` and `$OUT/SpellTuner_*` if present (a mixed package must not linger where
   someone would copy it). Zips: `$OUT/SpellTuner-tbc-<v>.zip` holding `SpellTuner/`;
   `$OUT/SpellTuner-forever-<v>.zip` holding `SpellTuner/` and the module folders (paths inside the
   zip relative to the flavour folder; the existing zip / python3 fallback). One summary line per
   flavour: `Built <rel>/<flavour>/SpellTuner (v<v>, <n> files) from <name>[, plus <k> module(s): ...]`.
4. **Install.** `--install-tbc DIR`, `--install-forever DIR` (both may be given, for two different
   directories), and `--install DIR` / the positional path / `$WOW_ADDONS`, which **detect**: a path
   containing `/_classic_beta_/` is forever, one containing `/_anniversary_/` is tbc, anything else
   is refused with `ERROR: cannot tell which client <DIR> belongs to; use --install-tbc or
   --install-forever` and exit 1. An explicit flag whose path detects as the **other** flavour is
   refused (`ERROR: <DIR> looks like a <x> client; refusing to install <y> there`). `DIR` must exist
   and its last component must be `AddOns`, else refused. Every refusal happens before anything is
   built or written. Installing **forever**: replace `DIR/SpellTuner` and each `DIR/<Module>` with the
   package's. Installing **tbc**: replace `DIR/SpellTuner` with the TBC package's, and remove
   `DIR/<Module>` for every module name in the tree's `Modules/`, printing
   `Removed stale DIR/<Module> (Forever only)` for each one that was there. Replacing the whole
   `SpellTuner` folder is what removes a stale TOC of the other flavour (and any file a previous
   build had). Final line: `Installed <flavour> v<v> into <DIR>`.
5. **`--set-version X`**: X must match `^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$` (else `ERROR` and exit 1,
   nothing written); rewrites the `## Version:` line of every TOC of step 1 in the source (preserving
   a CR at the line end if the file has one; nothing else in any file changes), prints each file,
   builds nothing, exits 0. **`--version`**: prints the one version, or the step-2 error.
6. The closing hint when nothing was installed names both commands:
   `./release.sh --install-tbc ".../_anniversary_/Interface/AddOns"` and
   `./release.sh --install-forever ".../_classic_beta_/Interface/AddOns"` (and the `make install`
   form).

## Rules

- `CLAUDE.md`: `release.sh` builds from the TOCs' own file lists, so the package can never drift
  from what the client loads; dev files are excluded by construction. Keep both properties.
- **Nothing in the real clients.** No test and no manual run of yours may write under
  `/mnt/e/` or any real `Interface/AddOns`; every install in the suite goes into a scratch tree under
  `tools/.lua/releasecheck/` (for example `tools/.lua/releasecheck/_classic_beta_/Interface/AddOns`).
  The lead installs into the author's beta after acceptance.
- `bash` only as `release.sh` already uses it (`set -euo pipefail`, no new dependency; the python3
  zip fallback stays). Quote every path: the author's paths contain spaces
  (`World of Warcraft`), so the suite's scratch paths must contain a space too.
- **Tests first**: write `tools/releasecheck.lua` and the probecheck change, run them against
  today's `release.sh`, paste the failures, then change `release.sh`.
- `tools/releasecheck.lua` loads no harness (it only runs `release.sh` and reads files); it starts
  with the usual `check` / summary shape (`<n> ok, <m> failed`, exit 1 on a failure) and cleans its
  scratch tree at the start of a run, not at the end (so a failure can be inspected).
- **Git:** no `git add`, `stash`, `checkout -- <path>`, `reset`, commit. Do not edit `CLAUDE.md` or
  any `docs/` file except this Report. Do not change any TOC or any `.lua` file that ships.

## Acceptance

1. `bash tools/run.sh tools/releasecheck.lua` ends `13 ok, 0 failed`. Assertions, names verbatim:
   1. "the TBC package holds exactly the TBC TOC's files" -- the set of files under
      `<out>/tbc/SpellTuner` equals `README.md`, `SpellTuner_TBC.toc` and its entries (backslashes as
      slashes), and `<out>/tbc` holds nothing but `SpellTuner/`.
   2. "the Forever package holds exactly the Forever TOCs' files" -- the same for
      `<out>/forever/SpellTuner` against `README.md`, `SpellTuner_Mainline.toc`, `SpellTuner.toc` and
      the union of their entries.
   3. "the Forever package carries the three modules, each exactly its TOCs' files" -- `<out>/forever`
      holds `SpellTuner/` and one folder per `Modules/<Name>/`, nothing else; each module folder's
      files equal its TOCs plus their entries.
   4. "no TOC of the other flavour is in either package" -- no `.toc` anywhere under `<out>/tbc` has
      an interface outside 20000-29999; none under `<out>/forever` has one outside 16000-19999.
   5. "every packaged TOC carries the tree's one version" -- each packaged TOC's `## Version:` equals
      the tree's `SpellTuner_TBC.toc` line (read by this suite).
   6. "each zip is named by flavour and version and holds exactly its package" -- the two zips exist
      under those names and their member lists (read with `python3 -c` and `zipfile`) equal the
      flavour folders' file lists.
   7. "the build refuses when two TOCs disagree on the version" -- on a scratch copy of the tree
      (`git ls-files -co --exclude-standard` piped through `tar`, so uncommitted work is included)
      with one module TOC's version changed: exit status non-zero, the output names that file and
      both versions, and the scratch `--out` folder has no `tbc/` or `forever/`.
   8. "--set-version rewrites every TOC's version line and nothing else" -- on the scratch copy:
      `--set-version 0.16.9` exits 0, every TOC then reads `0.16.9`, every TOC equals its original with
      only that line changed, no other file changed; `--set-version 1.0` exits non-zero and changes
      nothing.
   9. "an install into a Forever client puts only the Forever package there" -- a scratch
      `.../_classic_beta_/Interface/AddOns` pre-seeded with `SpellTuner/SpellTuner_TBC.toc`,
      `SpellTuner/Stale.lua` and an unrelated `OtherAddon/x.lua`: after `--install DIR` the
      `SpellTuner` and module folders equal the Forever package exactly, and `OtherAddon/x.lua` is
      still there.
   10. "an install into a TBC client puts only the TBC package there and removes the modules" -- a
       scratch `.../_anniversary_/Interface/AddOns` pre-seeded with
       `SpellTuner/SpellTuner_Mainline.toc`, `SpellTuner_Recorder/SpellTuner_Recorder.toc` and
       `OtherAddon/x.lua`: after `--install DIR` `SpellTuner` equals the TBC package, no module folder
       exists, the output says `Removed stale`, `OtherAddon/x.lua` is still there.
   11. "an install into a path of unknown flavour is refused and writes nothing" -- `--install` into a
       scratch `.../somewhere/Interface/AddOns` holding a sentinel file: non-zero exit, the output
       names `--install-tbc` and `--install-forever`, the folder holds only the sentinel.
   12. "an explicit flavour that contradicts the path is refused" -- `--install-tbc` into the
       scratch `_classic_beta_` folder: non-zero exit, that folder unchanged (compare its file list
       before and after).
   13. "the explicit flavour installs into a path it cannot detect" -- `--install-forever` into the
       scratch `somewhere` folder installs the Forever package there.
2. `bash tools/run.sh tools/probecheck.lua` ends `82 ok, 0 failed`; its check "the build ships three
   TOCs" becomes **"the Forever package ships two TOCs and the TBC package one"**: `--out
   tools/.lua/probecheck-release` then `<out>/forever/SpellTuner/*.toc` is exactly `SpellTuner.toc`,
   `SpellTuner_Mainline.toc`; `<out>/tbc/SpellTuner/*.toc` is exactly `SpellTuner_TBC.toc`;
   `Client/TOC_Mainline.lua` and `Client/TOC_Plain.lua` are in the Forever package and not in the
   TBC one; `Client/TOC_TBC.lua` in the TBC package and not in the Forever one; the four
   `not FileExists` clauses for retired TOCs kept.
3. Every other suite unchanged: the whole loop of `docs/TOOLS.md` §1 at `docs/tasks/HANDOVER.md`'s
   Baselines (with T22's lead review), `python3 tools/apicheck.py` 0 findings, `--selftest` 10 of 10,
   `python3 tools/refcheck.py --selftest` ok. Paste the last line of each.
4. Pasted: `bash release.sh --out <scratch with a space>` output; `find <out> -name '*.toc' | sort`;
   the file counts per package; `bash -n release.sh`; `make -n install WOW_ADDONS=/x/_classic_beta_/Interface/AddOns`
   and `make -n install WOW_ADDONS=/x/y/Interface/AddOns FLAVOUR=tbc` (showing the release.sh
   command each would run); `./release.sh --version`; `./release.sh --list`.

## Out of scope

Every TOC and every shipped `.lua` file (a TOC that looks wrong is reported, not edited); the
worktree source selection (`--src`, `--menu`, `--list`) beyond showing the one version; the author's
real AddOns folders; `docs/` and `CLAUDE.md` (the lead updates TESTING, TOOLS, CLAUDE.md and
HISTORY after acceptance).

## Report

**Implementer's report (2026-09-29).** Everything Acceptance asks for holds; one thing needs the
lead's eyes first.

**Read this first: a second writer.** At 16:34:05 something other than me overwrote
`tools/releasecheck.lua` (4 s after I wrote `release.sh`; my 13-assertion suite, written at ~16:31,
was replaced by a different 440-line suite with the same 13 names, scratch root
`tools/.lua/releasecheck/scratch tree`). It looks like a second implementer on the same task. I
did not fight it: I kept the file as found and made one change to it -- its `sh()` ran
`"cmd 2>&1"` after callers' own `2>/dev/null`, so the stderr of `ls`/`find` on a missing folder
leaked into `DirNames()` and failed assertions 7, 10 and 11 (10 ok, 3 failed against my
`release.sh`); wrapping the command in parentheses fixed it (13 ok). If that other writer is not
yours, the file's provenance is worth a look; if it is, `release.sh`, `Makefile` and `probecheck.lua`
are mine and unchanged by it as far as I can see (mtimes and contents). That suite does not check a
CRLF TOC; I checked it by hand (below). My own suite is not in the tree.

**Files.**
- `release.sh`: rewritten (header included). Classifies every root `SpellTuner*.toc` and
  `Modules/<Name>/<Name>*.toc` by `## Interface:` (20000-29999 tbc, 16000-19999 forever, a mix or
  anything else, or a module that is not forever: `ERROR: <file> has interface <v>: neither tbc nor
  forever`); reads every TOC's version and refuses on disagreement (`ERROR: the TOCs disagree on the
  version:` + one `  <path>: <version>` per TOC) before touching the output; `--version`,
  `--set-version X` (regex checked first, `sed` on the version line only, the CR of a CRLF file
  kept, builds nothing), `--flavour tbc|forever|both`, `--install-tbc`, `--install-forever`,
  `--install` / positional / `$WOW_ADDONS` (env only when no install option was given) which detect
  from `/_classic_beta_/` and `/_anniversary_/`. Every install refusal (missing dir, last component
  not `AddOns`, unknown or ambiguous path, explicit flavour against the path's) comes before anything
  is built. Build: `$OUT/tbc/SpellTuner`, `$OUT/forever/SpellTuner` + `$OUT/forever/<Module>`, old
  layout `$OUT/SpellTuner` and `$OUT/SpellTuner_*` removed, `SpellTuner-tbc-<v>.zip` and
  `SpellTuner-forever-<v>.zip` (python3 fallback here, no `zip`). All files verified before
  anything is written. Install replaces `DIR/SpellTuner` whole; forever also replaces the modules;
  tbc removes `DIR/<Module>` with `Removed stale ... (Forever only)`. The worktree machinery is as
  before; `--list` / `--menu` show the version or `mixed`. Two small additions the task did not spell
  out: an unknown `-option` is now an error (it used to become the install path), and `--help` prints
  the whole header.
- `Makefile`: `FLAVOUR ?=`; `install` passes `--install-$(FLAVOUR)` when set, else `--install`; a
  bogus FLAVOUR is refused by make; usage comments updated.
- `tools/releasecheck.lua`: new, 13 ok (see the provenance note above).
- `tools/probecheck.lua`: the release check is now "the Forever package ships two TOCs and the TBC
  package one" with the clauses of Acceptance 2 (`TocsIn` replaces `releaseTocs`); nothing else.

**Tests first.** My suite (13 assertions, before I had a new `release.sh`) against the old script:
`0 ok, 13 failed` (e.g. `the TBC package holds exactly the TBC TOC's files FAIL - missing set`,
`the build refuses when two TOCs disagree on the version FAIL - exit 0: Built ...`, `an install into a
path of unknown flavour is refused and writes nothing FAIL - exit 0 Built ...`). probecheck against
the old script: `81 ok, 1 failed` -- `FAIL the Forever package ships two TOCs and the TBC package one`.
Side effect of that run to know about: the old script, given a scratch tree without `--out`, wrote
`dist/tree8` into the **main checkout's** `dist/` (`ROOT` is the git common dir); I deleted it. Nothing
was written under `/mnt/e` or any real AddOns folder; every install went into
`tools/.lua/releasecheck/` or `tools/.lua/manual check/`.

**Suites (last lines).** `tools/run.sh tools/releasecheck.lua`: `13 ok, 0 failed`.
`probecheck`: `82 ok, 0 failed`. The whole `docs/TOOLS.md` section 1 loop, at HANDOVER's baselines:
simcheck `-> PASS`, reccheck 54, replaycheck 80, replayui 98, runcheck 78, reviewui 44, navui 25,
dashui 56, regencheck 27, simwindow 8, solvercheck 77, timeline 27, spelltip 48, practice 74,
practiceui 49, migrate 7, forevercheck 13, modulecheck 14, kitcheck 7, recordcheck 24, scenariocheck
12, gatecheck 9, replayforever 11, reviewforever 10, coachforever 18, practiceforever 9, bindscheck 6,
parsecheck 12, bookcheck 17, tipcheck 17, clockcheck 17, spellsui 17, measurecheck 26 (all `0 failed`);
adaptercheck 22/15, corecheck 10/8, svcheck 6/1, consolecheck 14/1 (forever/tbc);
`apicheck: 8 Forever TOCs, 44 files, 45 distinct globals, 0 findings (baseline 69893)`;
`selftest: 10 of 10 findings as expected`; `selftest: ok` (refcheck). `luac -p` on `releasecheck.lua`
and `probecheck.lua`: clean. `bash -n release.sh`: clean.

**Acceptance 4 pastes** (`--out "<worktree>/tools/.lua/manual check/out"`, a path with a space):
```
Built .../out/tbc/SpellTuner (v0.16.0, 55 files) from manademon-folder-continue-41eabc.
Built .../out/SpellTuner-tbc-0.16.0.zip
Built .../out/forever/SpellTuner (v0.16.0, 21 files) from manademon-folder-continue-41eabc, plus 3 module(s): SpellTuner_Practice SpellTuner_Recorder SpellTuner_Replay.
Built .../out/SpellTuner-forever-0.16.0.zip
Copy .../out/<flavour>/SpellTuner (and, for Forever, its siblings) into the matching client's Interface/AddOns folder, or:
  ./release.sh --install-tbc "/mnt/c/Program Files (x86)/World of Warcraft/_anniversary_/Interface/AddOns"
  ./release.sh --install-forever "/mnt/c/Program Files (x86)/World of Warcraft/_classic_beta_/Interface/AddOns"
(or: make install WOW_ADDONS="<AddOns folder>" [FLAVOUR=tbc|forever])
```
(the out folder had a pre-seeded `SpellTuner/old.toc` and `SpellTuner_Old/`; both were gone.)
`find <out> -name '*.toc' | sort` (paths relative to out): `forever/SpellTuner/SpellTuner.toc`,
`forever/SpellTuner/SpellTuner_Mainline.toc`, `forever/SpellTuner_Practice/SpellTuner_Practice.toc`,
`.../SpellTuner_Practice_Mainline.toc`, the same two for `SpellTuner_Recorder` and `SpellTuner_Replay`,
`tbc/SpellTuner/SpellTuner_TBC.toc` -- nine, none of the other flavour. File counts: TBC package 55
files; Forever `SpellTuner/` 21 files, all of `forever/` 53 (three modules 32). `bash -n release.sh`
clean. `./release.sh --version`: `0.16.0`. `./release.sh --list`:
```
  1) main                   vmixed   master  (/home/penek/projects/addons/SpellTuner)
  2) combat-log-design-arch-ffb907 vmixed   claude/combat-log-design-arch-ffb907  (...)
  3) manademon-folder-continue-41eabc v0.16.0  claude/manademon-folder-continue-41eabc  (...)
```
(the two `mixed` are other checkouts whose TOCs really disagree or predate the layout).
```
make -n install WOW_ADDONS=/x/_classic_beta_/Interface/AddOns
  -> ./release.sh --menu --install "/x/_classic_beta_/Interface/AddOns"
make -n install WOW_ADDONS=/x/y/Interface/AddOns FLAVOUR=tbc
  -> ./release.sh --menu --install-tbc "/x/y/Interface/AddOns"
```
(each preceded by the two `test` guard lines; `--menu` is the existing behaviour without `SRC=`.)

Hand checks in scratch: `--install` into a scratch `_classic_beta_` and `_anniversary_` AddOns
(`Installed forever v0.16.0 into ...`; `Removed stale .../SpellTuner_Replay (Forever only)` then
`Installed tbc v0.16.0 into ...`); `--install` into `.../x/Interface/Other` refused (not an AddOns
folder); `--install-tbc` into the `_classic_beta_` folder: `ERROR: ... looks like a forever client;
refusing to install tbc there`; a nonexistent folder refused; a CRLF `SpellTuner_TBC.toc` through
`--set-version 1.2.3-rc.1` changed only `## Version: ...^M$`.

**Surprises.** (1) The second writer above. (2) `tools/data/modulecheck-fixture/T13CScratch/` holds
`.toc` files; anything that finds TOCs by `find -name '*.toc'` over the tree (as my first suite did)
sees them, so both `release.sh` (root and `Modules/*/` only) and the suite (which excludes
`./tools/*`) must not. (3) A main checkout on `master` and one other worktree read `mixed` in
`--list`; nothing to fix, but it will show. (4) Nothing a TBC TOC lists is missing from a Forever
package or vice versa; the two packages overlap only in shared files (Client/API.lua, Core.lua, ...),
each carrying its own copy. (5) No module entry needed the root-resolution rule differently from
before.

## Lead review (2026-09-29)

Accepted. **Two implementers were on this task at once** (cause in HANDOVER's lessons). The one
whose report is above (session a8fb5831) wrote `release.sh`, `Makefile` and the probecheck change.
The "second writer" it names at 16:34:05 was the lead's own re-dispatch (agent a688ec09). That agent
found the file already on disk when its `Write` reported "updated", stopped, and changed nothing
else. So the `tools/releasecheck.lua` in this commit is the re-dispatched agent's suite (its python
edit to assertion 9 included), with this report's `sh()` fix (the command parenthesised so a
caller's `2>/dev/null` stays inside). The first implementer's own suite is lost. The lead reviewed
the suite on disk as if nobody vouched for it.

- **Diff read.** `release.sh` against every numbered point of Files:
  - classification by interface (module TOCs must be forever);
  - one version, refused before the output is touched;
  - `--flavour`, the two packages, the old layout removed, and the zips named by flavour and version;
  - `--install-tbc` / `--install-forever` / `--install` / the positional form / `$WOW_ADDONS`
    (the last only when no install option was given). Detection runs on the resolved path, and
    every refusal comes before the build;
  - installing tbc removes the modules with `Removed stale`;
  - `--set-version` checks its argument before touching anything, and its `sed` keeps a trailing CR
    in `\2`;
  - the closing hint names both commands.

  `Makefile` refuses a bogus `FLAVOUR`. probecheck changes only the release check, to the
  Acceptance 2 clauses.
- **Suite read assertion by assertion.** Each of the 13 tests what its name says:
  - 1 also requires `tbc/` to hold only `SpellTuner/`;
  - 7 requires no `tbc/` or `forever/` in the refused `--out`;
  - 11 requires the refused `--out` to be empty;
  - 12 compares the file list and checksums before and after;
  - every install goes under `tools/.lua/releasecheck/scratch tree/`;
  - `WOW_ADDONS` is unset for every run.
- **Lead's change (the planner's request): a CRLF TOC under `--set-version`.** Assertion 8 now turns
  the scratch copy's `SpellTuner_TBC.toc` into CRLF before the snapshot. It requires that file to come
  back byte-for-byte except the version line, with every LF still a CRLF and
  `## Version: 0.16.9\r\n` present. Mutation check: a `release.sh` whose `--set-version` pipes
  through `tr -d "\r"` fails it (`12 ok, 1 failed -- SpellTuner_TBC.toc differs beyond its version
  line`). `release.sh` was restored byte-for-byte afterwards.
- **Re-run by the lead.** releasecheck 13, probecheck 82, and every other suite at HANDOVER's
  baselines. apicheck 0 findings over 44 files, selftest 10 of 10, refcheck selftest ok. `bash -n
  release.sh` clean, and `luac -p` clean on both suites. `make -n install` prints
  `./release.sh --menu --install "/x/_classic_beta_/Interface/AddOns"` and
  `./release.sh --menu --install-tbc "/x/y/Interface/AddOns"`. `./release.sh --version` prints
  `0.16.0`.
- Noted, not changed: `rm -rf "$OUT"/SpellTuner_*` removes the old layout as the task asked. An
  `--out` pointed at a real AddOns folder would lose the modules there, which is no worse than the
  old script's own `rm -rf "$OUT/SpellTuner"`.
