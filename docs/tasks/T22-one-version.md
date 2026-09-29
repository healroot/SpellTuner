# T22 -- one version for the whole tree: 0.16.0, read from the TOCs, never pinned in a test

Status: **accepted** 2026-09-29 (lead review at the end).

## Goal

Every TOC in the tree -- `SpellTuner_TBC.toc`, `SpellTuner_Mainline.toc`, `SpellTuner.toc` and the
six module TOCs -- carries `## Version: 0.16.0`, and the two suites that pinned the Forever version
as a literal (`tools/probecheck.lua`, `tools/consolecheck.lua`) read it from the TOCs instead, the
way the addon itself does (`GetAddOnMetadata` on the TOC that loaded), and assert that every TOC
agrees. After this task a version bump is nine `## Version:` lines and no test edit; `release.sh`
gains the one-command bump and the build-time refusal in T23. For the author, whose ruling is one
version for both lines.

## Facts

- The ruling (`docs/DECISIONS.md` "One version, two installations (2026-09-29)"): one version for
  the whole tree; `0.16.0` now for both lines; `1.0.0` at the Forever launch.
- **The single source of truth is the TOCs themselves** (lead's design). The client can read a
  version only out of the TOC it loaded (`MD.API.AddonVersion()`, `Client/API.lua` 379-388,
  through `AddOnMetadata`; `Core.lua` 13 `MD.version = MD.API.AddonVersion() or "dev"`; the probe's
  own `Version()`, `Client/Probe.lua` 354-366). A separate `VERSION` file stamped into packaged TOCs
  at release time would make the tree -- what the harness and a development install load -- say
  something other than the package, and would be a tenth copy to keep in step. So the nine TOCs
  are the source, kept equal by a suite (this task), by `release.sh` refusing to build when they
  disagree, and bumped by `release.sh --set-version` (both T23).
- Today's lines (`grep -H '^## Version' *.toc Modules/*/*.toc`): `SpellTuner_TBC.toc` `0.15.4`;
  the other eight `1.0.0-alpha.8`. Each TOC has exactly one `## Version:` line.
- The stub reads the version the way the client does: `tools/wowstub.lua` 56-63 (global
  `GetAddOnMetadata`, from `S.toc`, default `SpellTuner_TBC.toc`) and 1169-1180
  (`C_AddOns.GetAddOnMetadata(name, field)` under the forever profile, from `S.toc` =
  `SpellTuner_Mainline.toc`). So under the forever flavour `MD.version` is the Mainline TOC's line.
- The literals to remove: `tools/consolecheck.lua` 256-284 (case 10, "every Forever TOC is
  1.0.0-alpha.8", a hand-kept list of eight files; runs only under `flavour == "forever"`, line
  101); `tools/probecheck.lua` 669-692 (the `hasVersion` / `hasVersion2` compare against
  `"## Version: 1.0.0-alpha.8"` and `PREFIX = "SpellTuner probe 1.0.0-alpha.8 -- "`, check "the
  Forever TOCs are 1.0.0-alpha.8 and differ only in their marker").
- Already reading from the TOC, not to be changed: `tools/probecheck.lua` 104-118 ("the TBC line
  reads its version from SpellTuner_TBC.toc"), `tools/corecheck.lua` 57-66 (`TocVersion(tocName)`).
- Baselines at 2696187: `probecheck` 82, `consolecheck` 14 (forever) / 1 (tbc), `corecheck` 10 / 8.

## Files

| file | change | role |
|---|---|---|
| `SpellTuner_TBC.toc`, `SpellTuner_Mainline.toc`, `SpellTuner.toc`, `Modules/SpellTuner_Recorder/SpellTuner_Recorder.toc`, `Modules/SpellTuner_Recorder/SpellTuner_Recorder_Mainline.toc`, `Modules/SpellTuner_Replay/SpellTuner_Replay.toc`, `Modules/SpellTuner_Replay/SpellTuner_Replay_Mainline.toc`, `Modules/SpellTuner_Practice/SpellTuner_Practice.toc`, `Modules/SpellTuner_Practice/SpellTuner_Practice_Mainline.toc` | the `## Version:` line becomes `## Version: 0.16.0`; nothing else in the file changes (keep each file's line endings as they are) | the nine copies of the one version |
| `tools/consolecheck.lua` | case 10 rewritten (Acceptance 1b); its header comment and the case's comment line updated | Forever/TBC suite |
| `tools/probecheck.lua` | the release block's version compare rewritten (Acceptance 1a); nothing else in it | Forever suite |

## Rules

- `CLAUDE.md`: no libraries; no new global in shipped code (the tools may use `io.popen`, as
  `tools/probecheck.lua` 629 and 637 already do).
- **No version literal in any test.** After this task
  `grep -nE '0\.16\.0|1\.0\.0-alpha|0\.15\.4' tools/*.lua` prints nothing (comments included).
- Do not touch any `.lua` file that ships: `MD.version` already comes from the TOC; if something
  that prints the version does not show `0.16.0` under the harness, stop and report it rather than
  editing it.
- **Tests first**: rewrite the two assertions, run them against the tree as it is (the TBC TOC at
  0.15.4, the rest at alpha.8), paste the failing lines, then edit the TOCs.
- **Git:** no `git add`, `stash`, `checkout -- <path>`, `reset`, commit. Do not edit `CLAUDE.md` or
  any `docs/` file except this Report.

## Acceptance

1. Assertions (the names verbatim; the counts do not change):
   a. `tools/probecheck.lua`: **"the Forever TOCs carry the one version and differ only in their
      marker"** replaces "the Forever TOCs are 1.0.0-alpha.8 and differ only in their marker". The
      version is read from `SpellTuner.toc`'s `## Version:` line (a local helper beside `ReadLines`;
      nil when absent); the check holds when that version is non-nil, `SpellTuner_Mainline.toc` and
      `SpellTuner_TBC.toc` carry the same version, the existing marker-only diff holds as today,
      and `report1` starts with `"SpellTuner probe " .. version .. " -- "`.
   b. `tools/consolecheck.lua` case 10: **"every TOC carries the version the addon reports"**
      replaces "every Forever TOC is 1.0.0-alpha.8". It lists the TOCs from disk, not by hand --
      every `SpellTuner*.toc` in the root and every `Modules/*/*.toc` (`io.popen` of `ls`) -- and
      holds when exactly 9 are found, each has exactly one `## Version:` line, and every one equals
      `MD.version` of the forever session (the value the addon read through
      `C_AddOns.GetAddOnMetadata`, not a value this test read itself). On failure the detail names
      the first disagreeing file and its value (or the count found).
2. Suites (paste the last line of each):
   - `bash tools/run.sh tools/probecheck.lua` -> `82 ok, 0 failed`
   - `bash tools/run.sh --flavour forever tools/consolecheck.lua` -> `14 ok, 0 failed`;
     `--flavour tbc` -> `1 ok, 0 failed`
   - `bash tools/run.sh --flavour forever tools/corecheck.lua` -> 10 ok; `--flavour tbc` -> 8 ok
   - the whole loop of `docs/TOOLS.md` §1 at the Baselines of `docs/tasks/HANDOVER.md` (every count
     unchanged), `python3 tools/apicheck.py` 0 findings, `--selftest` 10 of 10,
     `python3 tools/refcheck.py --selftest` ok.
3. The negative, pasted: change `Modules/SpellTuner_Practice/SpellTuner_Practice.toc` to
   `## Version: 0.16.1`, run consolecheck under forever and paste its case-10 line (FAIL naming that
   file and `0.16.1`), then put it back to `0.16.0` and run it again (ok). Same for
   `SpellTuner_TBC.toc` against probecheck's assertion 1a.
4. Pasted: `grep -H '^## Version' *.toc Modules/*/*.toc` (nine lines, all `0.16.0`); the empty
   output of the grep in Rules; `git diff --stat`.
5. Pasted: what the harness shows for the version under each flavour --
   `bash tools/run.sh --flavour tbc tools/corecheck.lua` passing proves `MD.version` is the TBC
   TOC's; say whether you saw `0.16.0` in any printed probe header or dump in the suite output.

## Out of scope

`release.sh`, `Makefile` (T23), every shipped `.lua` file, the test fixtures under `tools/data/`
(their `## Version: 1.0.0` lines are fixtures, not ours), every `docs/` file but this Report,
`CLAUDE.md`.

## Report

Done 2026-09-29. Nothing committed.

**Changed.** The `## Version:` line in the nine TOCs is now `0.16.0` (`SpellTuner_TBC.toc` was 0.15.4, the other eight 1.0.0-alpha.8; nothing else in any TOC changed, all ASCII with LF endings). `tools/consolecheck.lua`: case 10 is now "every TOC carries the version the addon reports". It lists TOCs from disk (`io.popen` of `ls SpellTuner*.toc Modules/*/*.toc`), needs exactly 9, exactly one `## Version:` line each, each equal to `MD.version` of the forever session; failure detail names the first bad file and its value (or the count). Header comment updated. `tools/probecheck.lua`: a `TocVersion` helper beside `ReadLines`; the check is now "the Forever TOCs carry the one version and differ only in their marker" (version from `SpellTuner.toc`, non-nil, equal in `SpellTuner_Mainline.toc` and `SpellTuner_TBC.toc`, marker-only diff as before, `report1` starts with `"SpellTuner probe " .. version .. " -- "`). No shipped `.lua` touched. Counts unchanged.

**Tests first (TBC TOC 0.15.4, the rest alpha.8):**
```
the Forever TOCs carry the one version and differ only in their marker   FAIL
81 ok, 1 failed
every TOC carries the version the addon reports                          FAIL - SpellTuner_TBC.toc is 0.15.4, the addon reports 1.0.0-alpha.8
13 ok, 1 failed
```

**Suites after the TOC edit:** probecheck `82 ok, 0 failed`; consolecheck forever `14 ok, 0 failed`, tbc `1 ok, 0 failed`; corecheck forever `10 ok, 0 failed`, tbc `8 ok, 0 failed`. The whole TOOLS.md §1 loop equals the HANDOVER baselines (simcheck PASS, reccheck 54, replaycheck 80, replayui 98, runcheck 78, reviewui 44, navui 25, dashui 56, regencheck 27, simwindow 8, solvercheck 77, timeline 27, spelltip 48, practice 74, practiceui 49, migrate 7, probecheck 82, forevercheck 13, modulecheck 14, kitcheck 7, recordcheck 24, scenariocheck 12, gatecheck 9, replayforever 11, reviewforever 10, coachforever 18, practiceforever 9, bindscheck 6, parsecheck 12, bookcheck 17, tipcheck 17, clockcheck 17, spellsui 17, measurecheck 26; adaptercheck 22/15, corecheck 10/8, svcheck 6/1, consolecheck 14/1). `apicheck: 8 Forever TOCs, 44 files, 45 distinct globals, 0 findings (baseline 69893)`; `selftest: 10 of 10 findings as expected`; `refcheck --selftest`: `selftest: ok`. `luac -p` (the harness's `tools/.lua/lua-5.1.5/src/luac`; no `luac` on PATH) on both edited tools: ok.

**Negatives.** Practice TOC set to 0.16.1:
```
every TOC carries the version the addon reports                          FAIL - Modules/SpellTuner_Practice/SpellTuner_Practice.toc is 0.16.1, the addon reports 0.16.0
13 ok, 1 failed
```
put back to 0.16.0: `every TOC carries the version the addon reports ok` / `14 ok, 0 failed`. TBC TOC set to 0.16.1 against probecheck: `the Forever TOCs carry the one version and differ only in their marker   FAIL` / `81 ok, 1 failed`; put back: `... ok` / `82 ok, 0 failed`. Both files are back at 0.16.0 (0 matches for 0.16.1).

**Greps.** `grep -H '^## Version' *.toc Modules/*/*.toc`: nine lines, every one `## Version: 0.16.0` (SpellTuner_TBC, SpellTuner, SpellTuner_Mainline, and the six module TOCs). `git diff --stat` for the task: nine TOCs at 1 line each, `tools/consolecheck.lua` (59 lines changed), `tools/probecheck.lua` (22); `docs/DECISIONS.md` and `docs/ROADMAP-FOREVER.md` were already modified by the lead before this task.

**The Rules grep is not empty, one hit, not mine to fix:** `tools/practice.lua:309:    -- v0.15.4: an import goes ON TOP of what is there.` -- a historical comment naming the release that changed import behaviour, not a version pin. The task's Files do not list `tools/practice.lua`, so I left it; the lead should either reword it or loosen the grep (`0\.15\.4` matches it). Nothing else in `tools/*.lua` matches.

**Version under each flavour.** `corecheck --flavour tbc` passing (8 ok) proves `MD.version` there is the TBC TOC's (its `TocVersion` reads `SpellTuner_TBC.toc`); under forever `MD.version` came through `C_AddOns.GetAddOnMetadata` from `SpellTuner_Mainline.toc` and consolecheck case 10 held it equal to all nine files. I did not see `0.16.0` printed in any suite output: no suite prints a probe header or dump with the version (grep of probecheck, consolecheck forever and corecheck tbc output for `0.16` was empty); the only place it is checked is the `report1` prefix assertion in probecheck, which passes. Nothing surprised me beyond the `practice.lua` comment.

## Lead review (2026-09-29)

Accepted. Diff read: the nine TOCs change one line each (`## Version: 0.16.0`); consolecheck case 10
lists the TOCs from disk, requires nine, and compares each with the session's `MD.version`;
probecheck's release block reads the version from `SpellTuner.toc` and requires the Mainline and
TBC TOCs to match. The lead re-ran the whole loop: every count at the HANDOVER baselines
(probecheck 82, consolecheck 14 / 1, corecheck 10 / 8, all others unchanged), apicheck 0 findings,
selftest 10 of 10, refcheck selftest ok.

- **The Rules grep was too broad (lead's error).** `tools/practice.lua` 309's `-- v0.15.4: ...` is a
  history marker on a behaviour, not a version pin; the intent -- no test compares against a version
  literal -- holds (`grep -nE '"[^"]*(0\.16\.0|1\.0\.0-alpha)' tools/*.lua` is empty). Left as is.
- **Lead's change (two lines):** the two Forever root TOCs' `## Notes:` said "Forever (alpha)"; now
  "Forever (beta)", per the ruling that Forever beta builds are 0.16.x. Both files change the same
  way, so probecheck's marker-only diff still holds (82 ok); forevercheck 13, modulecheck 14.
