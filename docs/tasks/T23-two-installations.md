# T23 -- two installations from one tree: a TBC package and a Forever package

Status: **handed out** 2026-09-29 (T22 accepted in 6d755f6).

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

What you changed, file by file; the failing runs from "tests first"; every paste Acceptance asks
for; anything that surprised you (a file one TOC lists that another flavour also needs, a module
entry resolved from the root, a path the detection gets wrong).
