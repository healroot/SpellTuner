# T6 — `tools/apicheck.py`: every global the Forever TOCs touch, checked against the build's baseline and the adapter rule

Status: **done -- lead-accepted 2026-09-28** (written and implemented the same day; see the Review at the end). M1 (`docs/ROADMAP-FOREVER.md` §2), task line
"T6 `apicheck.py`"; the M1 exit requires "`apicheck.py` passes". Taken after T1b, so the tree it
first checks is the one M1 builds on.

## Goal

`python3 tools/apicheck.py` reads every file the Forever TOCs load, lists every global name each one
reads or writes (from `luac -l`, not a regex over source), and fails -- with file, line, name and
reason -- on five things: a name the build does not have; a client call outside `Client/`; a new
global; a Lua library the client does not ship; and the `COMBAT_LOG_EVENT_UNFILTERED` constant
anywhere but the one adapter file that forbids it. It also checks every `C_Namespace.Member` string
the adapter binds against the baseline's namespaces. It runs offline in a second, has a fixture that
trips each rule once, and prints a summary line a reviewer can paste. For the lead, who runs it on
every Forever diff, and for the planner, who re-points it at a newer baseline when the probe
captures one.

## Facts

- The plan (§3.5): "`tools/apicheck.py` scans our code for client calls and diffs them against the
  current build's baseline (the kit's `forever_api.json` now; our own probe's capture later) -- a
  used function that the build no longer has fails the check before anyone logs in."
- The baseline is `tools/data/forever_api.json` (T5): build 69893, keys `functions` (6,045 global
  function names, including Lua's own `pcall`, `select`, `print`, `format` and WoW's `wipe`,
  `tinsert`, `strsplit`, `date`, `time`, `GetTime`, `debugprofilestop`), `frames` (11,417 named
  frames, among them `UIParent`, `DEFAULT_CHAT_FRAME`, `GameTooltip`, `Minimap`, `GameFontNormal`),
  `namespaces` (269 `C_*` names, each a list of member names), `client`. It does **not** capture
  non-function tables or strings: `SlashCmdList`, `Enum`, `RAID_CLASS_COLORS`, `UISpecialFrames`,
  `SOUNDKIT`, `STANDARD_TEXT_FONT`, `BackdropTemplateMixin` are absent from it though the client has
  them (EllesmereUI uses them on 70009 -- plan §1 names it as the working reference) (lead,
  2026-09-28).
- The build the author plays is 70009; the probe found exactly the 8 absences the 69893 baseline
  predicts among the 65 functions it asked about (sixth report `== functions`, in
  `git show ad94b2f^:docs/probe/1.60.1_70009.md`).
- **The adapter rule as M1 reads it** (T1b Facts; escalated to the planner for confirmation):
  data reads and actions on the game go through `Client/`; the widget toolkit and WoW's Lua
  extensions do not have to. Its two lists, fixed here:
  - *Lua extensions* (allowed in any file; each must be in the baseline's `functions`): `wipe`,
    `tinsert`, `tremove`, `strsplit`, `strtrim`, `strjoin`, `format`, `date`, `time`, `GetTime`,
    `debugprofilestop`.
  - *Widget toolkit* (allowed in any file): `CreateFrame`, `CreateFont`, `UIParent`, `GameTooltip`,
    `GameFontNormal`, `GameFontNormalSmall`, `GameFontHighlightSmall`, `Minimap`,
    `UISpecialFrames`, `RAID_CLASS_COLORS`, `SOUNDKIT`, `PlaySound`, `GetCursorPosition`, `Mixin`,
    `BackdropTemplateMixin`, `SlashCmdList`, `STANDARD_TEXT_FONT`. The ones the baseline does not
    capture are listed in the report as `toolkit, not in baseline`, never failed.
- **Our own globals** (the only names a Forever file may assign): `SpellTuner`, `SpellTunerDB`,
  `ManaDemonDB`, `SPELLTUNER_TOC`, `SLASH_SPELLTUNER1`, `SLASH_SPELLTUNER2`, `SLASH_SPELLTUNER3`.
  (`SlashCmdList.SPELLTUNER = ...` is a table write, not a global assignment.)
- **The combat log**: nothing on the Forever TOC registers `COMBAT_LOG_EVENT_UNFILTERED`
  (`docs/FOREVER-PLAN.md` §1.2). After T0d/T1 the exact string constant appears only in
  `Client/API_Forever.lua` (`MD.API.ForbidEvent`).
- **WoW's Lua has no** `os`, `io`, `require`, `dofile`, `loadfile`, `package`, `module`, `debug`
  (none is in the baseline's `functions`, and they are not client tables; lead, 2026-09-28).
- `luac -l -p <file>` from the harness's own build (`tools/.lua/lua-5.1.5/src/luac`, built by
  `tools/run.sh` on first use) prints one instruction per line as
  `<tab><pc><tab>[<line>]<tab><OP><tab><args><tab>; <comment>`; `GETGLOBAL` / `SETGLOBAL` carry the
  global's name as the comment, `LOADK` and constant operands carry `"<string>"`. Nested functions
  are listed after their parent with their own headers.
- `Client/Probe.lua` names absent functions **as strings** on purpose (`"GetSpellInfo"`,
  `"C_Spell.GetSpellDescription"`, ...): they are questions to the client, not calls. The
  `C_Namespace.Member` string check therefore skips `Client/Probe.lua`.
- TOCs: `SpellTuner_Mainline.toc` and `SpellTuner.toc` are the Forever TOCs (`## Interface: 16001`);
  `SpellTuner_TBC.toc` is `20506`. T2 will add sibling addon folders with their own Forever TOCs;
  where they live is T2's to decide, so the discovery below must find a Forever TOC anywhere in the
  tree outside the excluded folders.

## Files

| file | change | role |
|---|---|---|
| `tools/apicheck.py` | new, Python 3 standard library only | the check |
| `tools/data/apicheck-fixture/` | new: a Forever TOC and two Lua files that trip each rule once | the check's own test |

### `tools/apicheck.py`

- Options: `--root DIR` (default: the checkout, i.e. the parent of `tools/`), `--baseline FILE`
  (default `tools/data/forever_api.json` under the checkout), `--luac FILE` (default the harness's;
  if missing, print `apicheck: no luac at <path> - run any suite once with tools/run.sh to build it`
  and exit 2), `--report` (also print every distinct global per file with its class),
  `--selftest` (run on the fixture and compare with the expected findings below; exit 0 only if
  they match exactly).
- **Discovery**: every `*.toc` under `--root`, recursively, skipping directories named `tools`,
  `dist`, `.git`, `.claude`, `docs`. A TOC is Forever when any number on its `## Interface:` line
  (comma-separated) is in 16000-19999. The files checked are the union of those TOCs' `.lua` entries
  (CR stripped, blank and `#` lines skipped, `\` -> `/`), resolved relative to the TOC's own folder;
  a listed file that does not exist is a finding `missing file`.
- **Classification** of each `GETGLOBAL` name: `lua` (Lua 5.1's base names that WoW keeps --
  `_G assert error getmetatable setmetatable ipairs pairs next pcall xpcall rawequal rawget rawset
  select tonumber tostring type unpack getfenv setfenv loadstring collectgarbage gcinfo print math
  string table coroutine`), `ours`, `lua-extension`, `toolkit`, `client` (in the baseline's
  `functions`, `frames` or `namespaces`, and none of the above), `not-in-client` (the list in Facts),
  `unknown` (anything else).
- **Findings** (each printed `FAIL <path>:<line> <name> <reason>`, path relative to `--root`):
  1. `not in baseline <build>` -- class `unknown`.
  2. `not in the client's Lua` -- class `not-in-client`.
  3. `client call outside Client/` -- class `client`, file not under a `Client/` folder.
  4. `new global` -- any `SETGLOBAL` of a name not in `ours`.
  5. `COMBAT_LOG_EVENT_UNFILTERED named` -- the exact constant `"COMBAT_LOG_EVENT_UNFILTERED"` in
     any checked file other than `Client/API_Forever.lua`.
  6. `C_ member not in baseline <build>` -- a string constant matching
     `^C_[A-Za-z0-9_]+\.[A-Za-z0-9_]+$` whose namespace or member is not in the baseline's
     `namespaces`, in any checked file except `Client/Probe.lua`.
  7. `missing file` -- a TOC entry with no file.
- **Summary**, always the last line:
  `apicheck: <T> Forever TOCs, <F> files, <G> distinct globals, <N> findings (baseline <build>)`.
  Exit 0 when `N == 0`, 1 otherwise.

### `tools/data/apicheck-fixture/`

- `Fixture_Mainline.toc`: `## Interface: 16001`, then `Client\Ok.lua`, `Bad.lua`, `Gone.lua`.
- `Client/Ok.lua`: reads `UnitHealth` and `C_Timer`, and has the string `"C_Timer.After"` -- no
  finding (a client call inside `Client/`, a real member).
- `Bad.lua`, one line per rule, each on its own line: a read of `GetSpellInfo` (rule 1); `os.time()`
  (rule 2); `UnitHealth("player")` (rule 3); `NewGlobalName = 1` (rule 4); the string
  `"COMBAT_LOG_EVENT_UNFILTERED"` (rule 5); the string `"C_Spell.NoSuchMember"` (rule 6); and one
  allowed read each of `wipe`, `CreateFrame`, `SlashCmdList`, `SpellTunerDB` (no finding).
- `Gone.lua` is not created (rule 7).
- The expected `--selftest` findings are exactly those seven, with their line numbers.

## Rules

- Python 3 standard library only; no network at run time.
- The checker reads `luac`'s listing; it never guesses from source text. Line numbers come from the
  listing's `[<line>]`.
- Tests first: write the fixture and `--selftest`'s expected list, then the checker.
- Do not change any addon file to make the check pass. If `apicheck.py` finds something on the real
  tree, stop and report it with the finding lines -- the lead decides whether the code or the list
  is wrong.
- **Git.** No `git add`, `git stash`, `git checkout -- <path>`, `git reset` or commit. Do not open
  `CLAUDE.md` or any `docs/` file except this task's Report section for writing.

## Acceptance

1. `python3 tools/apicheck.py --selftest` exits 0 and prints the seven fixture findings, one per
   rule, then `selftest: 7 of 7 findings as expected`.
2. `python3 tools/apicheck.py` on the tree exits 0 and ends with
   `apicheck: 2 Forever TOCs, 7 files, <G> distinct globals, 0 findings (baseline 69893)` (the seven
   files: `Client/TOC_Mainline.lua`, `Client/TOC_Plain.lua`, `Client/API.lua`,
   `Client/API_Forever.lua`, `Core.lua`, `Core_Forever.lua`, `Client/Probe.lua`).
3. `python3 tools/apicheck.py --report` lists, for `Core.lua`, `CreateFrame` and `SlashCmdList` as
   `toolkit` and no `client` name.
4. A deliberate break is caught: with a scratch copy of the checkout's Forever files (not the tree
   itself) in which `Core.lua` gains the line `local x = UnitHealth("player")`,
   `python3 tools/apicheck.py --root <copy>` exits 1 with
   `FAIL Core.lua:<n> UnitHealth client call outside Client/`. Describe how you made the copy.
5. The sixteen TBC suites, probecheck, forevercheck, both adaptercheck and both corecheck runs print
   the tails T1b was accepted with (no addon file changed).
6. `git status --short`: exactly `?? tools/apicheck.py`, `?? tools/data/apicheck-fixture/` and this
   task file.
7. Paste into the Report: the `--selftest` output; the tree run's full output; the `--report`
   section for `Core.lua` and `Client/API.lua`; Acceptance 4's output; the tails; `git status
   --short`.

## Out of scope

- Checking the TBC TOC (it is exempt until its files move onto the adapter).
- Member access other than `C_X.Y` strings (e.g. `C_Timer.After` written as code in a UI file is
  already a `client` read of `C_Timer`, caught by rule 3).
- Fetching a newer baseline; the probe's own capture (later).
- Every addon file; `CLAUDE.md`; `docs/` except this Report. Commits.

## Report

Implemented `tools/apicheck.py` and its fixture, tests first as the task asked.

**Files**
- `tools/apicheck.py` (new): reads every `*.toc` under `--root` (default the checkout), skipping
  `tools/dist/.git/.claude/docs`; a TOC is Forever when any comma-separated number on its
  `## Interface:` line falls in 16000-19999; unions the referenced `.lua` files (CR stripped,
  blank/`#` skipped, `\` -> `/`, resolved relative to the TOC's own folder, deduped by resolved
  path); for each file runs `luac -l -p` and parses `GETGLOBAL`/`SETGLOBAL`/`LOADK` lines with the
  regex `^\t\d+\t\[(\d+)\]\t(\S+)\s*\t([^\t]*)(?:\t; (.*))?$` (verified against real `luac -l -p`
  output first). Classification order: `lua` base names, `ours`, `lua-extension`, `toolkit`,
  `not-in-client`, then the baseline's `functions`/`frames`/`namespaces` (`client`), else `unknown`.
  Findings 1-4 come off `GETGLOBAL`/`SETGLOBAL` instructions, 5-6 off `LOADK` string constants
  (quote-delimited, so number/bool constants are never mistaken for strings), 7 off a TOC entry
  whose resolved path is not a file. `--report` prints every distinct global per file with its
  class; `--selftest` re-points root at the fixture and diffs the exact 7 findings by
  `(path, line, name, reason)`; default `--baseline`/`--luac` always resolve under the real
  checkout (the script's own directory), never under `--root`, so the fixture run still checks
  against the real baseline and the real prebuilt `luac`.
- `tools/data/apicheck-fixture/` (new): `Fixture_Mainline.toc` (`## Interface: 16001`, then
  `Client\Ok.lua`, `Bad.lua`, `Gone.lua`), `Client/Ok.lua` (reads `UnitHealth` and `C_Timer`, has
  the string `"C_Timer.After"` -- no finding), `Bad.lua` (one line per rule 1-6, then one allowed
  read each of `wipe`, `CreateFrame`, `SlashCmdList`, `SpellTunerDB`), `Gone.lua` not created.

**Tests first.** Before writing the scan logic, I stubbed `scan_file` to return `[]` and ran
`--selftest` against the finished fixture -- it failed, printing only the rule-7 (missing file)
finding, proving the comparison itself catches an under-implemented checker:
```
FAIL Fixture_Mainline.toc:6 Gone.lua missing file
selftest: FAILED
expected: [('Bad.lua', 1, 'GetSpellInfo', 'not in baseline 69893'), ('Bad.lua', 2, 'os', "not in the client's Lua"), ('Bad.lua', 3, 'UnitHealth', 'client call outside Client/'), ('Bad.lua', 4, 'NewGlobalName', 'new global'), ('Bad.lua', 5, 'COMBAT_LOG_EVENT_UNFILTERED', 'COMBAT_LOG_EVENT_UNFILTERED named'), ('Bad.lua', 6, 'C_Spell.NoSuchMember', 'C_ member not in baseline 69893'), ('Fixture_Mainline.toc', 6, 'Gone.lua', 'missing file')]
actual:   [('Fixture_Mainline.toc', 6, 'Gone.lua', 'missing file')]
exit 1
```
Then I restored the real `scan_file` and ran it for real.

**Acceptance 1 -- `--selftest`:**
```
FAIL Bad.lua:1 GetSpellInfo not in baseline 69893
FAIL Bad.lua:2 os not in the client's Lua
FAIL Bad.lua:3 UnitHealth client call outside Client/
FAIL Bad.lua:4 NewGlobalName new global
FAIL Bad.lua:5 COMBAT_LOG_EVENT_UNFILTERED COMBAT_LOG_EVENT_UNFILTERED named
FAIL Bad.lua:6 C_Spell.NoSuchMember C_ member not in baseline 69893
FAIL Fixture_Mainline.toc:6 Gone.lua missing file
selftest: 7 of 7 findings as expected
```
exit 0.

**Acceptance 2 -- tree run:**
```
apicheck: 2 Forever TOCs, 7 files, 26 distinct globals, 0 findings (baseline 69893)
```
exit 0. Nothing on the real tree tripped a finding, so there was nothing to escalate to the lead.

**Acceptance 3 -- `--report`, `Client/API.lua` and `Core.lua` sections:**
```
Client/API.lua:
  _G lua
  pairs lua
  pcall lua
  rawget lua
  select lua
  table lua
  type lua
  unpack lua
Core.lua:
  CreateFrame toolkit
  ManaDemonDB ours
  SLASH_SPELLTUNER1 ours
  SLASH_SPELLTUNER2 ours
  SLASH_SPELLTUNER3 ours
  SlashCmdList toolkit
  SpellTunerDB ours
  _G lua
  ipairs lua
  pairs lua
  pcall lua
  select lua
  string lua
  table lua
  tonumber lua
  tostring lua
  type lua
```
`CreateFrame` and `SlashCmdList` are `toolkit`; no `client` name appears for either file.

**Acceptance 4 -- deliberate break.** Made a scratch copy (not the tree) at
`<scratchpad>/apicheck-break/`: copied `SpellTuner.toc`, `SpellTuner_Mainline.toc`, `Core.lua`,
`Core_Forever.lua`, and `Client/{TOC_Mainline.lua,TOC_Plain.lua,API.lua,API_Forever.lua,Probe.lua}`
into it (same relative layout, the exact 7 Forever files), appended `local x =
UnitHealth("player")` to the copy's `Core.lua`, then ran `python3 tools/apicheck.py --root
<copy>`:
```
FAIL Core.lua:234 UnitHealth client call outside Client/
apicheck: 2 Forever TOCs, 7 files, 27 distinct globals, 1 findings (baseline 69893)
```
exit 1. The scratch copy was removed afterward (it lived only under the scratchpad directory, not
under version control).

**Acceptance 5 -- the tails T1b was accepted with**, unchanged, no addon file touched:
```
simcheck      ... -> PASS
reccheck      54 ok, 0 failed
replaycheck   80 ok, 0 failed
replayui      98 ok, 0 failed
runcheck      78 ok, 0 failed
reviewui      44 ok, 0 failed
navui         25 ok, 0 failed
dashui        56 ok, 0 failed
regencheck    27 ok, 0 failed
simwindow     8 ok, 0 failed
solvercheck   70 ok, 0 failed
timeline      27 ok, 0 failed
spelltip      48 ok, 0 failed
practice      74 ok, 0 failed
practiceui    49 ok, 0 failed
migrate       7 ok, 0 failed
probecheck    58 ok, 0 failed
forevercheck  13 ok, 0 failed
adaptercheck/forever 15 ok, 0 failed
adaptercheck/tbc     11 ok, 0 failed
corecheck/forever    10 ok, 0 failed
corecheck/tbc        8 ok, 0 failed
```

**Acceptance 6 -- `git status --short`:**
```
?? docs/tasks/T2-modules-window.md
?? docs/tasks/T3-console-dump.md
?? docs/tasks/T4-savedvariables-guard.md
?? docs/tasks/T6-apicheck.md
?? tools/apicheck.py
?? tools/data/apicheck-fixture/
```
Note: `T2-modules-window.md`, `T3-console-dump.md` and `T4-savedvariables-guard.md` were already
untracked at the start of this session (they are in the conversation's opening `git status`
snapshot, before I touched anything) -- I did not create or edit them. The status is not the exact
three entries Acceptance 6 names because of these pre-existing files, not because of anything this
task added; flagging it rather than silently calling it a match.

`luac -p` on the one file touched: n/a in the traditional sense (`tools/apicheck.py` is Python,
not Lua); the fixture's two new Lua files pass under `luac -l -p` as shown above (that's what the
checker itself runs on them), and no addon `.lua` file was edited.

No files outside `tools/apicheck.py` and `tools/data/apicheck-fixture/` were changed. No git
writes were made (no add/stash/checkout/reset/commit); `.git` was not touched.

## Review (lead, 2026-09-28)

Accepted as delivered. Rerun by the lead: `--selftest` 7 of 7, exit 0; the tree `2 Forever TOCs, 7
files, 26 distinct globals, 0 findings (baseline 69893)`, exit 0; `--report` shows the kernel's
`CreateFrame` / `SlashCmdList` as toolkit and no client name outside `Client/`. The checker reads
`luac`'s listing, not source text; the deliberate break (a copy, not the tree) was caught with the
right line. The extra untracked task files in `git status` were the lead's, not the implementer's.
