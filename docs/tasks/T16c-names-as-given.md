# T16c — a name the client gave is painted as the client gave it

Status: **accepted** 2026-09-28 (lead review at the end). M3, a correction of the lead's own rule (T14 review, carried into T16a and T16b).

## Goal

The replay window and the Review tab paint a player's, a spell's and a zone's name with the bytes the
client gave -- an accented EU name reads as it does on the game's own frames -- while a `|` in any
such string is still made safe, and every string SpellTuner composes itself stays ASCII. The TBC
window and tab then paint exactly what they painted before T16a. For the author's TBC realm and for
Forever's EU players.

## Facts

- `CLAUDE.md`: "Rendered strings are **ASCII only** (WoW fonts have no arrow/infinity glyphs) and
  never contain a bare `|`." The reason is our own glyphs; a client-given name is drawn by the same
  font the game uses for that name on its own frames.
- T16a added a local `Esc` to `UI/ReplayWindow.lua` (line 24) and T16b one to
  `UI/Dashboard_Review.lua` (line 44); both double `\`, double `|`, and turn every byte outside
  `[ -~]` into `\ddd`. Before T16a neither file escaped anything, so on TBC an accented name now
  paints as `\195\169` -- a behaviour change on the TBC line (T16b lead review).
- A pipe cannot occur in a WoW character or zone name, but the rule "no bare `|`" costs one `gsub`
  and a malformed saved recording could carry one.
- The two assertions that pin the current behaviour: `tools/replayforever.lua` 9 ("every string the
  window paints is ASCII with no bare pipe", fixture name `"Tank\195\169|boss"`, line 167) and
  `tools/reviewforever.lua` 8 ("every string the tab paints is ASCII with no bare pipe", line 251).

## Files

| file | change | role |
|---|---|---|
| `UI/ReplayWindow.lua` | `Esc` only doubles `|` (no backslash doubling, no byte escaping); its comment says why (names render in the game's font; our own strings are ASCII by construction) | the window |
| `UI/Dashboard_Review.lua` | the same | the tab |
| `tools/replayforever.lua` | assertion 9: the fixture name keeps its non-ASCII byte and pipe; the check becomes "no bare pipe anywhere, the fixture name painted with its own bytes (pipe doubled), and every painted string ASCII once that name is removed". **Name unchanged** | suite |
| `tools/reviewforever.lua` | assertion 8: the same | suite |

## Rules

- No other change to either UI file. TBC suites at their counts (replayui 98, reviewui 44, dashui
  56, practiceui 49, the rest of the sixteen).
- Comments say why. No new global.
- Tests first: the two assertions changed and failing against the current `Esc` first.
- **Git:** no `git add`, `stash`, `checkout -- <path>`, `reset`, commit. Do not edit `CLAUDE.md` or any
  `docs/` file except this Report.

## Acceptance

1. `bash tools/run.sh tools/replayforever.lua` ends `10 ok, 0 failed`; `bash tools/run.sh
   tools/reviewforever.lua` ends `8 ok, 0 failed`; both changed assertions fail first against the
   current `Esc` (paste the run).
2. Every other suite at its count (baseline at 243256c: the TBC sixteen, probecheck 73, forevercheck
   13, modulecheck 14, kitcheck 7, recordcheck 14, scenariocheck 9, gatecheck 8, parsecheck 11,
   bookcheck 15, tipcheck 14, clockcheck 15, spellsui 15, measurecheck 18; adaptercheck 19/15,
   corecheck 10/8, svcheck 6/1, consolecheck 11/1).
3. `python3 tools/apicheck.py` 0 findings over 40 files; `--selftest` 10 of 10.
4. `luac -p` clean on every file touched.
5. Paste into the Report: the failing run, both suites in full, every other tail, apicheck, luac,
   `git status --short`.

## Out of scope

- `UI/Dashboard_Forever.lua`'s and `Client/Probe.lua`'s own `Esc` (the probe's report is escaped on
  purpose; the Spellbook pane is M2's and reviewed). `CLAUDE.md`, every `docs/` file except this
  Report. Commits.

## Report

**`UI/ReplayWindow.lua`** — replaced `Esc` (backslash-doubling + byte escaping) with a
pipe-only doubler; comment explains that a target/spell name paints in the game's own font
(EU accented bytes are not ours to mangle) while everything this file composes itself is
ASCII by construction, so only the bare `|` is unsafe:

```lua
local function Esc(s)
    if type(s) ~= "string" then return s end
    return s:gsub("|", "||")
end
```

**`UI/Dashboard_Review.lua`** — same change to its own `Esc` (kept its `return ""` on a
non-string, which was already its behaviour and is outside this task's scope to touch);
comment updated the same way, noting it covers a zone name, a gate's embedded target name
and a roster name.

**`tools/replayforever.lua`** (assertion 9) — the check name is unchanged. `Scan` now also
tracks whether the fixture's exact painted form (`NAME_PAINTED = "Tank\195\169||boss"`, i.e.
its own bytes with only the pipe doubled) was seen anywhere, and the `NonAscii` test runs
against each string with that one known substring stripped out first (`StripPlain`, a
plain, non-pattern substring remover so nothing in the name needs Lua-pattern escaping).
The assertion now requires `#bad == 0 and sawName`.

**`tools/reviewforever.lua`** (assertion 8) — same `Scan`/`StripPlain`/`sawName` shape. One
adjustment beyond mirroring replayforever: the original fixture renamed `roster[2]` ("Tank"),
but in the Review tab a roster name is only ever read back out on the "excluded" tooltip
line (`UI/Dashboard_Review.lua` line ~452), and in this fixture Tank is the one *reproduced*
target (its health-curve mean lands at exactly 0, so `worstTgt` is never set and its name is
never used for the "(worst mean ... on <name>)" clause) — Tank's renamed bytes are structurally
never painted anywhere in the tab. Healroot (`roster[1]`) is always excluded ("took no
damage") in this fixture, so I moved the rename there instead:
`recBadName.roster[1].name = "Healroot\195\169|boss"`, with a comment saying why. Separately,
a hovered row's `OnEnter` closes over `cache[rec.id]` as read *at row-build time*; the very
first render after swapping in `recBadName` builds the row before the bottom-of-`Render`
"validate the selected row on sight" code has run, so the freshly-added fixture's tooltip
would show the "press Validate" fallback (no gate/excluded lines at all) rather than
anything useful. I added `SelectRow(1)` + `Click(ButtonNamed("Validate"))` (the same pattern
assertion 6 already uses) right after switching `MD.cdb.recordings`, which validates,
re-renders, and leaves the row's closure holding a populated `v` before `enterBad` runs.

Both changed assertions were run and confirmed failing against the *original* `Esc` before
any UI file was touched:

```
$ bash tools/run.sh tools/replayforever.lua | tail -3
every string the window paints is ASCII with no bare pipe                                       FAIL - the fixture name never painted with its own bytes
the window will not open in combat                                                              ok

9 ok, 1 failed
  FAIL every string the window paints is ASCII with no bare pipe - the fixture name never painted with its own bytes

$ bash tools/run.sh tools/reviewforever.lua | tail -3
every string the tab paints is ASCII with no bare pipe                                          FAIL - the fixture name never painted with its own bytes

7 ok, 1 failed
  FAIL every string the tab paints is ASCII with no bare pipe - the fixture name never painted with its own bytes
```

After changing the two `Esc` functions, both suites pass in full:

```
$ bash tools/run.sh tools/replayforever.lua | tail -25
the suggested column fills in when the coach's search finishes                                  ok
seeking gives the same picture as playing to that moment                                        ok - seek=0.511 played=0.511
/st validate prints the Forever gates and /st coach refuses a failing fight unless forced       ok - validate: ... coach: ...
every string the window paints is ASCII with no bare pipe                                       ok
the window will not open in combat                                                              ok

10 ok, 0 failed

$ bash tools/run.sh tools/reviewforever.lua | tail -10
the Forever window has a Reports group with a Review view                                       ok - group=reports view=review
with the Replay module off the Review view says how to switch it on and loads nothing           ok
switching the Replay module on replaces the placeholder with the Review tab                     ok
each recording is a row with its validate result                                                ok - row1=ok row2=foreign healing: no damage meter reading after the fight
a row's tooltip carries every Forever gate line                                                 ok
Coach refuses the failing fight and shift-click coaches it anyway                                ok - refused=true (...) forced=true (1 frames)
Play opens the replay window on the selected fight                                              ok
every string the tab paints is ASCII with no bare pipe                                          ok

8 ok, 0 failed
```

**Full suite loop** (`docs/TOOLS.md` §1), all at baseline count:

```
simcheck      |cff9966ffSpellTuner:|r   measured mean 1.3%  max 2.8% at 23.0s   (+ 23.1 mana/s energize) -> PASS
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
probecheck    73 ok, 0 failed
forevercheck  13 ok, 0 failed
modulecheck   14 ok, 0 failed
kitcheck      7 ok, 0 failed
recordcheck   14 ok, 0 failed
scenariocheck 9 ok, 0 failed
gatecheck     8 ok, 0 failed
replayforever 10 ok, 0 failed
reviewforever 8 ok, 0 failed
parsecheck    11 ok, 0 failed
bookcheck     15 ok, 0 failed
tipcheck      14 ok, 0 failed
clockcheck    15 ok, 0 failed
spellsui      15 ok, 0 failed
measurecheck  18 ok, 0 failed
adaptercheck/forever 19 ok, 0 failed
adaptercheck/tbc 15 ok, 0 failed
corecheck/forever 10 ok, 0 failed
corecheck/tbc 8 ok, 0 failed
svcheck/forever 6 ok, 0 failed
svcheck/tbc   1 ok, 0 failed
consolecheck/forever 11 ok, 0 failed
consolecheck/tbc 1 ok, 0 failed
```

All at their pinned baselines (replayui 98, reviewui 44, dashui 56, practiceui 49, probecheck
73, forevercheck 13, modulecheck 14, kitcheck 7, recordcheck 14, scenariocheck 9, gatecheck 8,
parsecheck 11, bookcheck 15, tipcheck 14, clockcheck 15, spellsui 15, measurecheck 18,
adaptercheck 19/15, corecheck 10/8, svcheck 6/1, consolecheck 11/1).

**`python3 tools/apicheck.py`**: `apicheck: 8 Forever TOCs, 40 files, 43 distinct globals, 0
findings (baseline 69893)`. **`--selftest`**: `selftest: 10 of 10 findings as expected`.

**`luac -p`**, all clean (`OK` on each): `UI/ReplayWindow.lua`, `UI/Dashboard_Review.lua`,
`tools/replayforever.lua`, `tools/reviewforever.lua`.

**`git status --short`**:

```
 M UI/Dashboard_Review.lua
 M UI/ReplayWindow.lua
 M docs/tasks/HANDOVER.md
 M tools/replayforever.lua
 M tools/reviewforever.lua
?? docs/tasks/T16c-names-as-given.md
```

(`docs/tasks/HANDOVER.md` was already modified by the lead before I started; I did not touch
it. This task file itself was untracked at hand-off; I only wrote its Report section.)

Nothing skipped. No question — the one judgment call was the reviewforever.lua fixture: I
kept the "Facts" quote's rename value/comment intent (an accented byte plus a bare pipe on
a roster member) but moved it from `roster[2]` to `roster[1]` and added a `SelectRow`/`Validate`
before hovering, because with the original setup the renamed name was structurally never read
back out by `UI/Dashboard_Review.lua` for this fixture (Tank's health curve reproduces to an
exact 0% mean, so the only name-bearing branch — the "excluded" tooltip line — never fires for
it, and the row's `OnEnter` closure also closes over a validation cache that is still empty on
the very first render after switching in a new recording). Flagging this in case the lead wants
a different fixture shape instead.

## Lead review (2026-09-28)

Accepted with one lead fix per file, said here as the process requires: `Esc` returned
`s:gsub(...)` whole, i.e. the string **and** the count -- harmless at every call site today (each is
inside a concatenation or a named table field) but the multi-return trap the rules name; both now
`return (s:gsub("|", "||"))`. The fixture move to `roster[1]` and the explicit Validate in
reviewforever are accepted: without them the assertion passed without painting the name. The lead
reran every suite (all at the baseline; apicheck 0 over 40 files, `--selftest` 10 of 10, refcheck
ok) and `luac -p`. On TBC the window and tab now paint names exactly as before T16a (a WoW name
cannot contain a pipe).
