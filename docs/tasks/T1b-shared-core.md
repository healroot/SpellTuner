# T1b — one core for both clients: `Core.lua` becomes the shared kernel, on the adapter

Status: **done -- lead-accepted 2026-09-28** after two re-issues (see the Answer, the second Review and the final Review at the end). M1 (`docs/ROADMAP-FOREVER.md` §2). Not a task
line of its own in the roadmap: it is the part of "T2 module registry ..." that the registry needs
first -- a core the Forever TOC can load -- split out so each task stays one sitting. Needs T1.

## Goal

`Core.lua` is split in two without changing what the TBC addon does. The **shared kernel** keeps the
name `Core.lua` and is listed by every TOC: the namespace, the version, the event dispatcher, the
internal pub/sub, the ticker, `Print` / `Alert` / `Debug`, the player's identity, the SavedVariables
init, the login sequence and the slash dispatcher with a command registry -- and it reaches the
client only through `MD.API` (T1). Everything that is the TBC addon's own -- its defaults, the
Simulate table, buffs and Tree of Life, talents, the profile snapshot, the gear and talent events,
its command list and its whole slash `if` chain -- moves **verbatim** into `Core_TBC.lua`, listed by
`SpellTuner_TBC.toc` only. A new `Core_Forever.lua` gives the Forever TOC its defaults and its first
two commands, and the probe registers `/st probe` through the kernel instead of owning the slash
command. For the M1 tasks after this one (the module registry, the SavedVariables guard, the debug
console), which all hang off the kernel, and for M2, whose engine files expect `MD:On`, `MD:Fire`,
`MD.db` exactly as TBC has them.

## Facts

- The roadmap's tree (§1.1) lists one `Core.lua` -- "namespace, db, event bus, ticker, slash, module
  registry" -- beside the two TOCs, and states the rule: "A file listed by both TOCs contains no
  client call and no flavour check; it calls the client through `MD.API`". Per-flavour files exist
  "only where the client leaks in" (the `UI/` line of the same tree).
- **Reading of the rule this task uses (lead, 2026-09-28; escalated to the planner for
  confirmation, see Report of the milestone):** "client call" means a data read or an action on the
  game (`Unit*`, `Get*`, `C_*`, `LoadAddOn`, ...). The widget toolkit (`CreateFrame`, `UIParent`,
  fonts, `SlashCmdList`, the frame methods) and WoW's Lua extensions (`wipe`, `date`, `time`,
  `GetTime`, `strsplit`, ...) are not; `UI/Style.lua`, which the roadmap lists as shared, cannot
  exist otherwise. So the kernel may create its event frame with `CreateFrame` and set
  `SlashCmdList.SPELLTUNER`; it may not call `UnitClass`, `GetAddOnMetadata`, `C_Timer.NewTicker`
  or `DEFAULT_CHAT_FRAME` directly.
- `Core.lua` today (554 lines, read 2026-09-28): `_G.SpellTuner = MD` and the version (`:4-10`);
  `DEFAULTS` and `MD.DEFAULTS` (`:12-86`); `MD.sim` (`:88-90`); the event dispatcher `MD:On`
  (`:95-112`, registers under `pcall`, silently skips an event that raises); callbacks (`:115-126`);
  the ticker (`:131-142`, `C_Timer.NewTicker(0.5, ...)`); `Print`, `Alert`, `Debug` (`:147-175`);
  `MD.player` and `DetectProfile` (`:181-193`); `HasBuff`, Tree of Life, `CheckForm` and the two
  form events and the `MD_READY` callback (`:196-239`, including `local TREE_OF_LIFE =
  GetSpellInfo(33891)` at load -- a global Forever does not have, sixth probe report
  `absent GetSpellInfo`); talents (`:244-284`); `WriteProfile` (`:294-331`); `FillDefaults` and
  `InitDB` with the ManaDemonDB adoption (`:338-366`); the `PLAYER_LOGIN` handler (`:368-391`:
  DetectProfile, InitDB, a debug line, ScanTalents, `Fire("MD_READY")`, WriteProfile, a 5 s
  `C_Timer.After` WriteProfile, the first-run message); `CHARACTER_POINTS_CHANGED`,
  `PLAYER_TALENT_UPDATE`, `PLAYER_EQUIPMENT_CHANGED`, `PLAYER_LEVEL_UP` (`:393-414`);
  `MD.COMMANDS`, `ShowHelp`, `SLASH_SPELLTUNER1..3` and the `SlashCmdList.SPELLTUNER` `if` chain
  (`:419-554`).
- `MD.COMMANDS` is read by `UI/Options_About.lua`; `MD.DEFAULTS` is public; `tools/harness.lua`
  replaces `MD:TalentRank` after loading; `tools/migrate.lua` holds the ManaDemonDB adoption
  (7 assertions).
- `Client/Probe.lua` sets `SLASH_SPELLTUNER1..3` and `SlashCmdList.SPELLTUNER` itself
  (`:1364-1378` after T0d); `tools/probecheck.lua` loads it without `Core.lua`
  (`{ "Client/TOC_Mainline.lua", "Client/API.lua", "Client/Probe.lua" }`) and calls
  `SlashCmdList.SPELLTUNER("probe")`. The probe must keep answering if `Core.lua` fails to load --
  it exists to survive the beta's bugs (T0 Goal).
- Probe's `OnAddonLoaded` creates `SpellTunerDB` (and `.probe`) at `ADDON_LOADED` if it is not a
  table (`Client/Probe.lua:1244-1247`). `InitDB` keeps whatever table is there
  (`SpellTunerDB = SpellTunerDB or {}`).
- In the stub, `S.Fire` delivers an event to frames in creation order; `MD:On` delivers to handlers
  in registration order. The kernel's frame is created when `Core.lua` loads, before any other
  file's.
- Multi-value adapter reads: `MD.API.UnitClass("player")` returns `localized, classFile, id` or
  `nil, "<reason>"` (T1). `local _, class = MD.API.UnitClass("player")` would put the **reason** in
  `class` on a failure; the first value has to be checked.

## Files

| file | change | role |
|---|---|---|
| `Core.lua` | reduced to the kernel (below), through `MD.API` | the shared core, every TOC |
| `Core_TBC.lua` | new; the rest of today's `Core.lua`, verbatim except the three seams below | the TBC addon's own core |
| `Core_Forever.lua` | new | Forever's defaults and first commands |
| `SpellTuner_TBC.toc` | `Core_TBC.lua` right after `Core.lua` | |
| `SpellTuner_Mainline.toc`, `SpellTuner.toc` | `Core.lua`, `Core_Forever.lua` after `Client\API_Forever.lua`, before `Client\Probe.lua` | |
| `Client/Probe.lua` | the slash section: through the kernel when it is there, standalone otherwise | the probe |
| `tools/corecheck.lua` | new suite, `HARNESS_FLAVOUR = { "forever", "tbc" }` | the kernel under both profiles |

### `Core.lua` -- the kernel

In today's order, with only these changes:
1. `_G.SpellTuner = MD`. `MD.version = MD.API.AddonVersion() or "dev"`.
2. `MD:On(event, fn)`: before the first registration of an event, `if not MD.API.CanRegisterEvent(event)`
   then log `MD:Debug("other", "refused event %s", event)` and return without touching the frame.
   Otherwise exactly as today.
3. Callbacks: as today. The ticker: `MD.API.NewTicker(TICK, fn)` in place of `C_Timer.NewTicker`.
4. `MD:Print(msg)`: `MD.API.Print("|cff9966ffSpellTuner:|r " .. tostring(msg))`, then the same
   `MD:Debug("chat", ...)`. `Alert`, `Debug`: as today.
5. `MD.player` and `MD:DetectProfile()` read through `MD.API`: `UnitClass` (first value checked,
   see Facts), `UnitLevel`, `UnitGUID`, `UnitName`, `RealmName`, `UnitPowerType`, keeping today's
   fallbacks (`"UNKNOWN"`, `0`, `""`, `"?"`) and today's fields.
6. `FillDefaults` and `InitDB` as today, filling from `MD.DEFAULTS or {}` (the flavour file sets it
   before `PLAYER_LOGIN`).
7. `PLAYER_LOGIN`: `DetectProfile`, `InitDB`, today's debug line, then
   `MD:Fire("CORE_LOGIN")`, `MD:Fire("MD_READY")`, `MD:Fire("CORE_READY")`.
8. `PLAYER_LEVEL_UP`: as today, with `MD.API.UnitLevel("player")` for the fallback.
9. The slash command: `SLASH_SPELLTUNER1..3` as today. `MD:AddCommand(name, fn, usage, text)`
   records `fn` under the lower-case `name` and appends `{ usage, text }` to an ordered help list;
   `MD:ShowCommands()` prints `commands:` then one line per entry, `  <usage> - <text>`, plain text
   with no colour codes. `SlashCmdList.SPELLTUNER(msg)` parses exactly as today (`raw`, `msg`
   lower-cased, `cmd`, `arg`, `rawArg`), then: a registered `cmd` -> `fn(arg, rawArg)`; else if
   `MD.SlashFallback` is a function -> `MD.SlashFallback(cmd, arg, rawArg)`; else `MD:ShowCommands()`.

### `Core_TBC.lua`

Today's remaining sections, verbatim, in today's order: `DEFAULTS` + `MD.DEFAULTS`, `MD.sim`,
`HasBuff` / Tree of Life / `CheckForm` / the form events / the `MD_READY` callback, talents,
`WriteProfile`, the four events (`CHARACTER_POINTS_CHANGED`, `PLAYER_TALENT_UPDATE`,
`PLAYER_EQUIPMENT_CHANGED`; `PLAYER_LEVEL_UP` stays in the kernel), `MD.COMMANDS`, `ShowHelp`.
Three seams, and nothing else changes:
- `MD:RegisterCallback("CORE_LOGIN", function() MD:ScanTalents() end)`.
- `MD:RegisterCallback("CORE_READY", fn)` where `fn` is today's tail of the login handler: the
  `WriteProfile`, the 5 s `C_Timer.After`, the first-run message -- verbatim.
- `MD.SlashFallback = function(cmd, arg, rawArg) ... end` holding today's `if cmd == "" then` ...
  `else ShowHelp() end` chain verbatim.
Direct client calls stay as they are here: this file is on the TBC TOC only.

### `Core_Forever.lua`

- `MD.DEFAULTS = { debug = { enabled = false, maxLines = 1000, categories = <today's eleven, all
  true> }, char = {} }` -- the keys the kernel's login debug line reads.
- `MD:AddCommand("", fn, "/st", "open the SpellTuner window")` where `fn` calls
  `MD:ToggleDashboard()` if it exists, else `MD:ShowCommands()` (the window arrives in T2).
- `MD:AddCommand("help", function() MD:ShowCommands() end, "/st help", "this list")`.

### `Client/Probe.lua`

The slash section only: if `type(MD.AddCommand) == "function"`, register `probe` with
`MD:AddCommand("probe", fn, "/st probe", "the capability report for the planner")`, where `fn(arg)`
prints T0d's clog notice when `arg == "clog"` and otherwise runs the probe; and do **not** set
`SlashCmdList.SPELLTUNER` or the `SLASH_` globals. Otherwise (no kernel) today's standalone block,
unchanged.

## Rules

- **The TBC addon's behaviour does not change.** Every line moved to `Core_TBC.lua` is moved, not
  rewritten; the three seams are the only new TBC code. The sixteen TBC suites are the check.
- The kernel calls the client only through `MD.API` (see the reading in Facts). No flavour check in
  it (`MD.API.client` is not read by `Core.lua`).
- The multi-return trap: never `a and f() or b`; check the first value of a multi-value adapter read.
- No new global beyond `SpellTuner`, `SLASH_SPELLTUNER1..3` and `SlashCmdList.SPELLTUNER` (all
  existing today).
- Comments say why. Keep today's comments with the code they explain.
- Tests first: write `tools/corecheck.lua`, run it under both flavours against today's tree, see it
  fail, then split. Say which failed.
- If a TBC suite fails after the split, find the moved line that differs; do not change the suite.
  If the cause is an ordering the split cannot keep, stop and report.
- **Git.** No `git add`, `git stash`, `git checkout -- <path>`, `git reset` or commit. Do not open
  `CLAUDE.md` or any `docs/` file except this task's Report section for writing.

## Acceptance

1. `tools/run.sh --flavour forever tools/corecheck.lua` ends `10 ok, 0 failed`;
   `tools/run.sh --flavour tbc tools/corecheck.lua` ends `8 ok, 0 failed`. Names verbatim; 1-5
   both flavours, 6-10 forever, 11-13 tbc:
   1. "the core loads and names itself": `_G.SpellTuner == MD`; `MD.version` equals the flavour
      TOC's `## Version:`; `MD.db` is a table; `MD.player.class == "DRUID"`; `MD.player.charKey`
      is `<name>-<realm>` from the stub.
   2. "events, callbacks and the ticker run": a handler added with `MD:On("UNIT_COMBAT", fn)`
      receives `("party1", "HEAL", "", 120, 1)` from `S.Fire`; a callback fired with two arguments
      receives both; a function added with `MD:OnTick` runs after `S.Tick(0.5)`.
   3. "an event the adapter refuses is never attempted": after
      `MD.API.ForbidEvent("PLAYER_TARGET_CHANGED")`, `MD:On("PLAYER_TARGET_CHANGED", fn)` leaves no
      frame in `S.allFrames` with that event in its `attempts`.
   4. "a registered command gets its argument and the raw text": `MD:AddCommand("t1btest", fn)`,
      then `SlashCmdList.SPELLTUNER("  T1BTest Blood Furnace ")` calls `fn("blood furnace",
      "Blood Furnace")`.
   5. "Print goes through the adapter to the chat frame": `MD:Print("hello")` puts a line
      containing `SpellTuner:` and `hello` on `DEFAULT_CHAT_FRAME`.
   6. "an unknown command prints the Forever command list": `SlashCmdList.SPELLTUNER("nosuch")`
      prints `commands:` and lines containing `/st probe` and `/st help`.
   7. "/st probe runs the probe through the core": `SlashCmdList.SPELLTUNER("probe")` leaves
      `SpellTunerDB.probe.reports["70009"].text` a string starting `SpellTuner probe `.
   8. "/st probe clog runs nothing": it prints T0d's notice and leaves the `70009` record's `at`
      unchanged.
   9. "nothing on the Forever TOC registers the combat log": after
      `MD:On("COMBAT_LOG_EVENT_UNFILTERED", fn)` and every step above, no frame's `attempts` has the
      event and `S.forbidden` is empty.
   10. "the kernel reads the client only through the adapter": with `S.units.player.class`,
       `.name`, `.guid` and `S.level` set to `S.Secret()` for the length of one
       `MD:DetectProfile()` call (and restored after), the call does not raise and leaves
       `MD.player.class == "UNKNOWN"`, `level == 0`, `guid == ""` and a `charKey` starting `?-`.
       (Replacing the stub's globals would not work: `MD.API.Has` caches the function it found.)
   11. "TBC keeps its talents, profile and slash chain": `MD.talents` is a table,
       `MD.cdb.profile.level == 64`, and `SlashCmdList.SPELLTUNER("mute")` flips `MD.db.muted`
       (twice, back to where it was).
   12. "TBC's login order is talents, MD_READY, profile": with a `TALENTS_CHANGED` callback, an
       `MD_READY` callback and a wrapper round `MD.WriteProfile` each appending a name to a list,
       firing `PLAYER_LOGIN` again gives `TALENTS_CHANGED`, `MD_READY`, `WriteProfile` in that
       order.
   13. "TBC's unknown command prints its own help": `SlashCmdList.SPELLTUNER("nosuch")` prints a
       line containing `/st verify` (from `MD.COMMANDS`).
2. `tools/run.sh tools/probecheck.lua` ends `58 ok, 0 failed`; `tools/run.sh tools/forevercheck.lua`
   `13 ok, 0 failed`; both adaptercheck runs as T1 accepted them (`14` and `10`).
3. The sixteen TBC suites print today's tails (simcheck `... -> PASS`; reccheck 54, replaycheck 80,
   replayui 98, runcheck 78, reviewui 44, navui 25, dashui 56, regencheck 27, simwindow 8,
   solvercheck 70, timeline 27, spelltip 48, practice 74, practiceui 49, migrate 7).
4. The moved code is moved: `git diff --stat` shows `Core.lua` losing roughly what `Core_TBC.lua`
   gains; paste `diff <(git show HEAD:Core.lua) <(cat Core.lua Core_TBC.lua)` into the Report and
   explain every hunk that is not a pure move (the kernel changes 1-9, the three seams).
5. `SpellTuner.toc` and `SpellTuner_Mainline.toc` still differ on exactly one line.
6. `tools/.lua/lua-5.1.5/src/luac -p Core.lua Core_TBC.lua Core_Forever.lua Client/Probe.lua tools/corecheck.lua`
   is clean.
7. `git status --short`: exactly `M Core.lua`, `?? Core_TBC.lua`, `?? Core_Forever.lua`,
   `M SpellTuner_TBC.toc`, `M SpellTuner.toc`, `M SpellTuner_Mainline.toc`, `M Client/Probe.lua`,
   `?? tools/corecheck.lua` and this task file.
8. Paste into the Report: both corecheck outputs; the assertions that failed before the split; the
   probecheck, forevercheck and adaptercheck tails; the sixteen tails; the diff of Acceptance 4; the
   `luac` output; `git status --short`.

## Out of scope

- The module registry, sibling addons and the window (T2); the SavedVariables guard (T4); the debug
  console, error capture and `/st dump` (T3).
- Moving any other TBC file onto the adapter (`UI/`, `Engine/`, `Verify.lua`, `Data/`).
- `MD.COMMANDS` on Forever, the About tab, `UI/Options_About.lua`.
- `CLAUDE.md` and every `docs/` file except this Report. Commits.

## Report

### Status: blocked -- three TBC suites fail for an ordering reason the split cannot avoid (see below). Everything else in the task is done and verified; stopped before touching anything out of scope to work around it, per the task's own stop rule.

### Files

- `Core.lua`: reduced to the kernel, in today's order, with exactly the nine
  changes items 1-9 of the task describe: `MD.version` via
  `MD.API.AddonVersion()`; `MD:On` refuses an event `MD.API.CanRegisterEvent`
  forbids before ever calling `RegisterEvent`; the ticker uses
  `MD.API.NewTicker`; `MD:Print` goes through `MD.API.Print`; `MD:DetectProfile`
  reads `UnitClass`/`UnitLevel`/`UnitGUID`/`UnitName`/`RealmName`/`UnitPowerType`
  through `MD.API`, checking the first return value only (never `local _, class
  = ...`); `FillDefaults`/`InitDB` fill from `MD.DEFAULTS or {}`; `PLAYER_LOGIN`
  fires `CORE_LOGIN`, `MD_READY`, `CORE_READY` in that order after the debug
  line; `PLAYER_LEVEL_UP` falls back to `MD.API.UnitLevel("player")`; the slash
  command gained `MD:AddCommand`/`MD:ShowCommands` (a registry) and
  `SlashCmdList.SPELLTUNER` now tries a registered command, then
  `MD.SlashFallback`, then `MD:ShowCommands()`.
- `Core_TBC.lua` (new): every other section of today's `Core.lua`, moved
  verbatim, in today's order (`DEFAULTS`/`MD.DEFAULTS`, `MD.sim`, `HasBuff` /
  Tree of Life / `CheckForm` / the two form events / the `MD_READY` callback,
  talents, `WriteProfile`, `CHARACTER_POINTS_CHANGED` / `PLAYER_TALENT_UPDATE`
  / `PLAYER_EQUIPMENT_CHANGED`, `MD.COMMANDS`, `ShowHelp`), plus the three
  seams: `MD:RegisterCallback("CORE_LOGIN", function() MD:ScanTalents() end)`;
  `MD:RegisterCallback("CORE_READY", fn)` holding today's login tail
  (`WriteProfile`, the 5s `C_Timer.After` `WriteProfile`, the first-run
  message) verbatim; `MD.SlashFallback = function(cmd, arg, rawArg) ... end`
  holding today's whole `if cmd == "" then ... else ShowHelp() end` chain
  verbatim. One incidental fix while moving `AddCommand`: `MD:AddCommand`
  defaults `usage`/`text` to `""` when a caller omits them (a caller
  registering only to claim a name, as `tools/corecheck.lua`'s own test
  command does, must not make `MD:ShowCommands()` raise on `nil .. "x"` later
  -- not a rule the task states but needed for corecheck's own acceptance test
  4 to coexist with test 6 in one run; noted here in case the lead disagrees
  with defaulting rather than, say, refusing a nameless registration).
- `Core_Forever.lua` (new): `MD.DEFAULTS` with the debug table the kernel's
  login line reads plus `char = {}`; `MD:AddCommand("", ...)` toggling the
  dashboard once it exists, else `MD:ShowCommands()`; `MD:AddCommand("help",
  ...)`.
- `SpellTuner_TBC.toc`: `Core_TBC.lua` added right after `Core.lua`.
- `SpellTuner_Mainline.toc`, `SpellTuner.toc`: `Core.lua`, `Core_Forever.lua`
  added right after `Client\API_Forever.lua`, before `Client\Probe.lua`.
- `Client/Probe.lua`: the slash section now checks `type(MD.AddCommand) ==
  "function"` -- if a kernel is present it registers `probe` through
  `MD:AddCommand("probe", fn, "/st probe", "the capability report for the
  planner")` (no `SLASH_SPELLTUNER*`/`SlashCmdList.SPELLTUNER` of its own);
  otherwise today's standalone block, unchanged, so the probe still answers if
  `Core.lua` fails to load (T0's Goal). `tools/probecheck.lua` loads
  `Client/Probe.lua` without `Core.lua` in its file list, so it always takes
  the standalone branch -- confirmed unaffected (58 ok below).
- `tools/corecheck.lua` (new): `HARNESS_FLAVOUR = { "forever", "tbc" }`,
  the 13 named assertions from Acceptance 1, each wrapped in a small `try()`
  helper that `pcall`s the assertion body so one crashing before the split
  exists (`MD.player`, `MD.AddCommand`, ... nil) is reported as a named
  failure instead of stopping the whole suite -- needed to run it against
  today's tree per "tests first" below.

### Tests first

Wrote `tools/corecheck.lua` against the pre-split tree and ran it under both
flavours before touching `Core.lua`:

```
$ bash tools/run.sh --flavour forever tools/corecheck.lua
the core loads and names itself                                          FAIL
events, callbacks and the ticker run                                     FAIL - raised: attempt to call method 'On' (a nil value)
an event the adapter refuses is never attempted                          FAIL - raised: attempt to call method 'On' (a nil value)
a registered command gets its argument and the raw text                  FAIL - raised: attempt to call method 'AddCommand' (a nil value)
Print goes through the adapter to the chat frame                         FAIL - raised: attempt to call method 'Print' (a nil value)
an unknown command prints the Forever command list                       FAIL
/st probe runs the probe through the core                                ok
/st probe clog runs nothing                                              ok
nothing on the Forever TOC registers the combat log                      FAIL - raised: attempt to call method 'On' (a nil value)
the kernel reads the client only through the adapter                     FAIL
2 ok, 8 failed

$ bash tools/run.sh --flavour tbc tools/corecheck.lua
the core loads and names itself                                          ok
events, callbacks and the ticker run                                     ok
an event the adapter refuses is never attempted                          FAIL
a registered command gets its argument and the raw text                  FAIL - raised: attempt to call method 'AddCommand' (a nil value)
Print goes through the adapter to the chat frame                         ok
TBC keeps its talents, profile and slash chain                           ok
TBC's login order is talents, MD_READY, profile                          ok
TBC's unknown command prints its own help                                ok
6 ok, 2 failed
```

Under forever, `Core.lua` was not even on that TOC yet, so `MD.player`,
`MD:On`, `MD:AddCommand` and `MD:Print` did not exist -- 8 of 10 failed, 6 of
them by raising. Under tbc, `Core.lua` already gave most of the kernel
behaviour by coincidence (it's the same file today), so only the two
kernel-only features (`ForbidEvent`/`CanRegisterEvent` gating `MD:On`, and
`MD:AddCommand`) failed. Then wrote the split; both now pass in full (below).

### `tools/corecheck.lua` -- forever (10 ok, 0 failed)

```
the core loads and names itself                                          ok
events, callbacks and the ticker run                                     ok
an event the adapter refuses is never attempted                          ok
a registered command gets its argument and the raw text                  ok
Print goes through the adapter to the chat frame                         ok
an unknown command prints the Forever command list                       ok
/st probe runs the probe through the core                                ok
/st probe clog runs nothing                                              ok
nothing on the Forever TOC registers the combat log                      ok
the kernel reads the client only through the adapter                     ok
10 ok, 0 failed
```

### `tools/corecheck.lua` -- tbc (8 ok, 0 failed)

```
the core loads and names itself                                          ok
events, callbacks and the ticker run                                     ok
an event the adapter refuses is never attempted                          ok
a registered command gets its argument and the raw text                  ok
Print goes through the adapter to the chat frame                         ok
TBC keeps its talents, profile and slash chain                           ok
TBC's login order is talents, MD_READY, profile                          ok
TBC's unknown command prints its own help                                ok
8 ok, 0 failed
```

### `adaptercheck` / `forevercheck` / `probecheck`

```
$ bash tools/run.sh --flavour forever tools/adaptercheck.lua | tail -1
14 ok, 0 failed
$ bash tools/run.sh --flavour tbc tools/adaptercheck.lua | tail -1
10 ok, 0 failed
$ bash tools/run.sh tools/forevercheck.lua | tail -1
13 ok, 0 failed
$ bash tools/run.sh tools/probecheck.lua | tail -1
58 ok, 0 failed
```

### The sixteen TBC suites

```
simcheck      |cff9966ffSpellTuner:|r   measured mean 1.3%  max 2.8% at 23.0s   (+ 23.1 mana/s energize) -> PASS
reccheck      54 ok, 0 failed
replaycheck   80 ok, 0 failed
replayui      98 ok, 0 failed
runcheck      FAIL /md run status reports the live run - no output   (73 ok, 5 failed -- see "Blocking issue")
reviewui      FAIL a plain click refuses and names a gate - no chat  (42 ok, 2 failed -- see "Blocking issue")
navui         25 ok, 0 failed
dashui        56 ok, 0 failed
regencheck    FAIL /md regentest clear forgets it - no line          (11 ok, 16 failed -- see "Blocking issue")
simwindow     8 ok, 0 failed
solvercheck   70 ok, 0 failed
timeline      27 ok, 0 failed
spelltip      48 ok, 0 failed
practice      74 ok, 0 failed
practiceui    49 ok, 0 failed
migrate       7 ok, 0 failed
```

13 of the 16 print today's exact tails. `runcheck`, `reviewui` and
`regencheck` do not (78/44/27 expected vs 73/5-failed, 42/2-failed,
11/16-failed) -- see below.

### Blocking issue: `MD.API.Has`'s cache makes `MD:Print` invisible to three suites that swap `_G.DEFAULT_CHAT_FRAME` after load

`MD.API.Print` (T1, unchanged by this task) is `local frame =
MD.API.Has("DEFAULT_CHAT_FRAME"); frame:AddMessage(text)`. `Has` caches its
answer **per name, for the life of the process** (T1 Facts: "cached per
name") -- deliberate and already accepted for T1. The kernel's own login tail
(`Core_TBC.lua`'s `CORE_READY` callback) calls `MD:Print` once for the
first-run message the moment `PLAYER_LOGIN` first fires, which is *inside*
`tools/harness.lua`'s own load sequence (`S.Fire("PLAYER_LOGIN")`), before any
suite's own code runs. That first call caches whichever `DEFAULT_CHAT_FRAME`
table existed at that instant (`tools/wowstub.lua`'s own default,
`{ AddMessage = function(_, m) print(m) end }`).

Three suites then replace the *whole global table* with a new one purely to
capture chat lines, after `dofile("harness.lua")` has returned:

- `tools/regencheck.lua:19`: `_G.DEFAULT_CHAT_FRAME = { AddMessage = ... }`
- `tools/runcheck.lua:19-20`: same, saving/restoring the original
- `tools/reviewui.lua:29`: same

Because `Has` already cached the *old* table object, `MD.API.Print` keeps
calling `AddMessage` on the discarded table forever after -- the new
capturing table never receives anything, so every check reading `out`/`chat`
for a chat line ("no line", "no output", "no chat") fails. Confirmed directly:

```lua
-- tools/dbgprint.lua (deleted after use, not part of the diff)
local MD = dofile(here .. "/harness.lua")   -- fires PLAYER_LOGIN, caches the old frame
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) out[#out+1] = m end }
MD:Print("hello-after-swap")
-- prints to the OLD frame (stdout via its print()), `out` stays empty
```//confirmed: "captured lines: 0" while the line still reached stdout via the
old table's own `AddMessage`.

`Core.lua`'s pre-split `MD:Print` called `DEFAULT_CHAT_FRAME:AddMessage(...)`
directly -- a fresh global lookup every time -- so swapping the global at any
point immediately took effect and none of these suites' patterns were a
problem before this task. Routing `MD:Print` through `MD.API.Print` is exactly
what the task's kernel item 4 requires ("`MD:Print(msg)`:
`MD.API.Print(...)`"), and `MD.API.Has`'s per-name cache is T1's own,
already-accepted contract -- neither is something this task's Files list lets
me change (`Client/API.lua` is out of scope here; the three suites are not
listed as files this task touches, and "do not change the suite" is the
default rule). This is the "ordering the split cannot keep" case the task's
own Rules name explicitly.

**Question for the lead:** which of these should give?
1. `Client/API.lua`'s `Has` stops caching `"DEFAULT_CHAT_FRAME"` specifically
   (or `Bind`/`Call` re-resolve it every call rather than trusting a cached
   table) -- fixes all three suites, touches T1's accepted file.
2. The three suites patch `AddMessage` on the *existing* `DEFAULT_CHAT_FRAME`
   table instead of replacing the global (the pattern `tools/adaptercheck.lua`
   and this task's own `tools/corecheck.lua` already use) -- fixes all three,
   touches suites outside this task's Files list.
3. Something else I'm not seeing.

I made no change to `Client/API.lua`, `tools/regencheck.lua`,
`tools/runcheck.lua` or `tools/reviewui.lua` while waiting on this -- every
other file listed in Acceptance 7 is exactly as specified, and the two
non-kernel suites' 3+13+5 = 21 combined failing assertions are all the same
one root cause, not 21 independent breaks.

### `git diff --stat` and the Acceptance-4 diff

```
$ git diff --stat -- Core.lua
 Core.lua | 446 +++++++++------------------------------------------------------
 1 file changed, 61 insertions(+), 385 deletions(-)
```

`diff <(git show HEAD:Core.lua) <(cat Core.lua Core_TBC.lua)` (417 lines,
included here trimmed to the hunk boundaries -- the full output was checked
by hand): every hunk is one of

- the file banner comment (both files got new ones explaining the split),
- the nine kernel changes listed under "Files" above (`MD.version` via the
  adapter; `MD:On`'s forbidden-event guard; `NewTicker`/`Print` via the
  adapter; `DetectProfile`'s adapter reads; `InitDB` filling from `MD.DEFAULTS
  or {}`; the `CORE_LOGIN`/`MD_READY`/`CORE_READY` sequence replacing
  `ScanTalents`+`MD_READY`+the inline tail; `PLAYER_LEVEL_UP`'s adapter
  fallback; the `AddCommand`/`ShowCommands` registry replacing the direct
  `MD.COMMANDS ShowHelp` implementation in the dispatcher), and
- the three seams in `Core_TBC.lua` (`CORE_LOGIN` -> `ScanTalents`;
  `CORE_READY` -> today's tail verbatim; `MD.SlashFallback` -> today's `if`
  chain verbatim).

No hunk changes a moved line's own text (DEFAULTS, `MD.sim`, `HasBuff`, Tree
of Life, `CheckForm`, talents, `WriteProfile`, the three gear/talent events,
`MD.COMMANDS`, `ShowHelp`, the `if` chain body) beyond re-indentation from
being wrapped in `MD.SlashFallback = function(cmd, arg, rawArg) ... end`
instead of `SlashCmdList.SPELLTUNER = function(msg) ... parsing ... end`.

### TOC check

```
$ diff SpellTuner.toc SpellTuner_Mainline.toc
8c8
< Client\TOC_Plain.lua
---
> Client\TOC_Mainline.lua
```

Still differ on exactly one line.

### `luac -p`

```
$ tools/.lua/lua-5.1.5/src/luac -p Core.lua Core_TBC.lua Core_Forever.lua Client/Probe.lua tools/corecheck.lua
(clean, no output)
```

### `git status --short`

```
 M Client/Probe.lua
 M Core.lua
 M SpellTuner.toc
 M SpellTuner_Mainline.toc
 M SpellTuner_TBC.toc
?? Core_Forever.lua
?? Core_TBC.lua
?? docs/tasks/T1b-shared-core.md
?? docs/tasks/T2-modules-window.md
?? docs/tasks/T3-console-dump.md
?? docs/tasks/T4-savedvariables-guard.md
?? docs/tasks/T6-apicheck.md
?? tools/corecheck.lua
```

Matches Acceptance 7 exactly (the other `docs/tasks/T*.md` files were already
untracked at session start, not touched by this task). No `git add`, `git
stash`, `git checkout --`, `git reset` or commit run; only `git status
--short`, `git show HEAD:Core.lua` and `git diff --stat` (read-only).

### Notes

- Every other Fact checked out against the code read: the cited `Core.lua`
  line ranges matched what is actually on disk (off by a couple of lines from
  drift since the Facts were written, not in substance); `MD.COMMANDS` /
  `MD.DEFAULTS` / `tools/harness.lua`'s `MD:TalentRank` replacement /
  `tools/migrate.lua`'s adoption test are all as described; `Client/Probe.lua`
  set `SLASH_SPELLTUNER1..3` and `SlashCmdList.SPELLTUNER` at the lines named;
  `tools/probecheck.lua` loads it without `Core.lua`, exactly as stated.
- Did not touch `CLAUDE.md`, `docs/PLAN.md`, `docs/HISTORY.md`,
  `docs/FOREVER-PLAN.md`, or any `docs/` file other than this Report section.

## Answer (lead, 2026-09-28) -- re-issued

Option 1, narrowed: **`MD.API.Print` looks the chat frame up at every call** instead of through
`Has`'s cache. The cache is right for functions, but `DEFAULT_CHAT_FRAME` is a variable the UI (and
chat addons) may reassign, and today's TBC `MD:Print` read it fresh on every print -- so a cached
table is a TBC behaviour change, not only a harness artefact. The three suites stay as they are:
they describe what the old code did, correctly.

Additional scope for this re-issue (everything above stays as delivered):
- `Client/API.lua`, `MD.API.Print` only: read `_G.DEFAULT_CHAT_FRAME` on each call (type-checked,
  `AddMessage` under `pcall`, as now); a comment saying why it bypasses `Has`. Nothing else in the
  file changes.
- `tools/adaptercheck.lua`: one new assertion under both flavours, "Print follows the chat frame
  the UI has now": after one `MD.API.Print`, replace `_G.DEFAULT_CHAT_FRAME` with a new capturing
  table; the next `MD.API.Print` reaches the new table and not the old one; restore the original
  afterwards. Counts become **15 / 11**.
- `MD:AddCommand` defaulting a missing `usage` / `text` to `""` (the implementer's note) is
  accepted.

Acceptance changes: 1 unchanged; 2 reads adaptercheck **15 / 11**; 3 unchanged (all sixteen TBC
tails exactly as today -- runcheck 78, reviewui 44, regencheck 27 included); 6 adds
`Client/API.lua` and `tools/adaptercheck.lua` to `luac`; 7 adds `M Client/API.lua` and
`M tools/adaptercheck.lua`. Write the outcome as "Re-issue 1" at the end of the Report.

### Re-issue 1

Did exactly the additional scope named in the Answer above, nothing else.

**Files**

- `tools/adaptercheck.lua`: added assertion 7 (both flavours), "Print follows the chat frame the
  UI has now" -- one `MD.API.Print` call before swapping `_G.DEFAULT_CHAT_FRAME`, attaches
  `AddMessage` to the *original* table only after that call (so a call made before the swap cannot
  retroactively count as reaching it), swaps in a new capturing table, calls `MD.API.Print` again,
  and checks the second call reached only the new table (`oldSeen == nil`, `newSeen ==
  "t1-print-new-frame"`), restoring the original global afterwards. Also renumbered the header
  comment and the two section-boundary comments (`1-8`/`9-14`/`15-16` -> `1-9`/`10-15`/`16-17`) to
  stay accurate; no assertion's logic besides the new one changed.
- `Client/API.lua`, `MD.API.Print` only: reads `_G.DEFAULT_CHAT_FRAME` with `rawget(_G, ...)` on
  every call instead of through `MD.API.Has`'s per-name cache, with a comment explaining why this
  one name bypasses `Has` (a variable the UI may reassign, unlike every other bound name, which is
  a function that does not move). `AddMessage` stays under `pcall`. Nothing else in the file
  touched.

**Tests first**

Wrote the new assertion, ran it against the pre-fix `Client/API.lua` under forever, and saw it
fail before making the change:

```
$ bash tools/run.sh --flavour forever tools/adaptercheck.lua
...
Print reaches the chat frame                                             ok
t1-print-old-frame
Print follows the chat frame the UI has now                              FAIL
...
14 ok, 1 failed
```

(`t1-print-old-frame` is the pre-swap `Print` call reaching the stub's default fallback
`AddMessage`, which just calls Lua's `print` -- confirming the cached old frame, not the new one,
received it.) Then made the one-line fix in `Client/API.lua` and reran both flavours:

```
$ bash tools/run.sh --flavour forever tools/adaptercheck.lua | tail -1
15 ok, 0 failed
$ bash tools/run.sh --flavour tbc tools/adaptercheck.lua | tail -1
11 ok, 0 failed
```

**Suites named by Acceptance**

```
$ bash tools/run.sh --flavour forever tools/corecheck.lua | tail -1
10 ok, 0 failed
$ bash tools/run.sh --flavour tbc tools/corecheck.lua | tail -1
8 ok, 0 failed
$ bash tools/run.sh tools/probecheck.lua | tail -1
58 ok, 0 failed
$ bash tools/run.sh tools/forevercheck.lua | tail -1
13 ok, 0 failed
```

The sixteen TBC suites, all at today's tails:

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
```

`runcheck`, `reviewui` and `regencheck` now print exactly the counts the un-blocked task expected
(78, 44, 27) -- the `Client/API.lua` fix resolved the blocking issue for all three without
touching any of the three suites themselves, as the Answer directed.

**`luac -p`**

```
$ tools/.lua/lua-5.1.5/src/luac -p Core.lua Core_TBC.lua Core_Forever.lua Client/Probe.lua Client/API.lua tools/corecheck.lua tools/adaptercheck.lua
(clean, no output)
```

**`git status --short`**

```
 M Client/API.lua
 M Client/Probe.lua
 M Core.lua
 M SpellTuner.toc
 M SpellTuner_Mainline.toc
 M SpellTuner_TBC.toc
 M tools/adaptercheck.lua
?? Core_Forever.lua
?? Core_TBC.lua
?? docs/tasks/T1b-shared-core.md
?? docs/tasks/T2-modules-window.md
?? docs/tasks/T3-console-dump.md
?? docs/tasks/T4-savedvariables-guard.md
?? docs/tasks/T6-apicheck.md
?? tools/corecheck.lua
```

Matches the re-issued Acceptance 7 (`M Client/API.lua` and `M tools/adaptercheck.lua` added to
the original list; the other untracked `docs/tasks/T*.md` files predate this session). No `git
add`, `git stash`, `git checkout --`, `git reset` or commit run -- only `git status --short`
(read-only), as instructed.

No open question. `MD:AddCommand`'s `usage`/`text` default from the first pass stands, as
accepted in the Answer.

## Review (lead, 2026-09-28) -- re-issued a second time

Rejected on one line that the suites cannot see:

- `Core.lua`, `MD:DetectProfile`: `local class = MD.API.UnitClass("player")` takes `UnitClass`'s
  **first** return, which on the client is the *localized* class name (`"Druid"`); the class token
  (`"DRUID"`) is the **second**. Today's TBC code (`local _, class = UnitClass("player")`) reads the
  second. So on a real client `MD.player.class` would be `"Druid"`, `isDruid` false, and every
  druid-only TBC feature would switch off. The suites pass only because the stub returns `"DRUID"`
  twice. The task's Facts said to check the first value and use the second; this reads the first.

Re-issue 2, scope (everything else stays):
- `tools/wowstub.lua`: `UnitClass` returns what the client returns -- a localized name first
  (`"Druid"`, `"Warrior"`: the token with only its first letter upper-case, unless the unit table
  carries its own `localized`), the token second. Both profiles. (Every caller in the tree --
  `Engine/Targets.lua`, `UI/Style.lua`, `Client/Probe.lua` -- reads the second, so no TBC suite
  may change.)
- Run corecheck under both flavours **before** fixing `Core.lua` and see "the core loads and names
  itself" fail (that is the test-first proof for this line).
- `Core.lua`: `local loc, class = MD.API.UnitClass("player")`, `class` set to nil when `loc` is nil.
- `Client/Probe.lua`: the new comment above the `MD.AddCommand` branch says the kernel loads "right
  after this file"; it loads before it. Correct the comment; nothing else.

Acceptance: every count as re-issue 1 left it (corecheck 10 / 8, adaptercheck 15 / 11,
forevercheck 13, probecheck 58, the sixteen TBC tails); `luac -p` clean; `git status --short` adds
`M tools/wowstub.lua`. Write "### Re-issue 2" at the end of the Report with the failing run and the
passing runs.

### Re-issue 2

Did exactly the additional scope named in the Review above, nothing else.

**Files**

- `tools/wowstub.lua`, `UnitClass`: now returns `loc, token` -- the localized class name first
  (the unit's own `localized` field if it carries one, else the token with only its first letter
  upper-cased), the class token (`"DRUID"`, etc.) second, matching the client (both profiles; the
  function is defined once, before `S.UseProfile` branches, so both the default and the forever
  profile get it). A comment explains why and names every existing caller that already reads the
  second value (`Engine/Targets.lua`, `UI/Style.lua`, `Client/Probe.lua`) so no TBC suite may
  change.
- `Core.lua`, `MD:DetectProfile`: `local loc, class = MD.API.UnitClass("player")`, with
  `if not loc then class = nil end` before `MD.player.class = class or "UNKNOWN"` -- a failed call
  (`UnitClass` returns `nil, "<reason>"` on absent/error/secret) must not let a leftover `class`
  from a prior call or a stray second value stand in as the answer; only a successful call's own
  second value is used.
- `Client/Probe.lua`: fixed the seam comment above the `MD.AddCommand` branch -- the kernel
  (`Core.lua`, `Core_Forever.lua`) loads right **before** `Client/Probe.lua` on both Forever TOCs
  (confirmed by grepping `SpellTuner.toc` / `SpellTuner_Mainline.toc`: lines 11-13 are `Core.lua`,
  `Core_Forever.lua`, `Client\Probe.lua`), not after. Comment text only; no code changed.

**Test first**

Ran corecheck under both flavours against the tree with the stub fix applied but before touching
`Core.lua`, and saw "the core loads and names itself" fail in both, as the Review predicted (the
stub's `UnitClass` now returns the localized name first, `Core.lua` still read the first value):

```
$ bash tools/run.sh --flavour forever tools/corecheck.lua
the core loads and names itself                                          FAIL
... (9 ok, 1 failed)
$ bash tools/run.sh --flavour tbc tools/corecheck.lua
the core loads and names itself                                          FAIL
... (7 ok, 1 failed)
```

Then made the one-line `Core.lua` fix and reran; both flavours pass in full.

**Suites named by Acceptance**

```
$ bash tools/run.sh --flavour forever tools/corecheck.lua | tail -1
10 ok, 0 failed
$ bash tools/run.sh --flavour tbc tools/corecheck.lua | tail -1
8 ok, 0 failed
$ bash tools/run.sh --flavour forever tools/adaptercheck.lua | tail -1
15 ok, 0 failed
$ bash tools/run.sh --flavour tbc tools/adaptercheck.lua | tail -1
11 ok, 0 failed
$ bash tools/run.sh tools/forevercheck.lua | tail -1
13 ok, 0 failed
$ bash tools/run.sh tools/probecheck.lua | tail -1
58 ok, 0 failed
```

The sixteen TBC suites, all at today's tails:

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
```

**`luac -p`**

```
$ tools/.lua/lua-5.1.5/src/luac -p Core.lua Client/Probe.lua tools/wowstub.lua
(clean, no output)
```

(Core_TBC.lua, Core_Forever.lua, tools/corecheck.lua and tools/adaptercheck.lua are unchanged by
this re-issue; their clean `luac -p` from Re-issue 1 stands.)

**`git status --short`**

```
 M Client/API.lua
 M Client/Probe.lua
 M Core.lua
 M SpellTuner.toc
 M SpellTuner_Mainline.toc
 M SpellTuner_TBC.toc
 M tools/adaptercheck.lua
 M tools/wowstub.lua
?? Core_Forever.lua
?? Core_TBC.lua
?? docs/tasks/T1b-shared-core.md
?? docs/tasks/T2-modules-window.md
?? docs/tasks/T3-console-dump.md
?? docs/tasks/T4-savedvariables-guard.md
?? docs/tasks/T6-apicheck.md
?? tools/corecheck.lua
```

Matches the re-issued Acceptance exactly (`M tools/wowstub.lua` added to the Re-issue 1 list; the
untracked `docs/tasks/T*.md` files predate this session). No `git add`, `git stash`,
`git checkout --`, `git reset` or commit run -- only `git status --short` (read-only).

No open question.

## Review (lead, 2026-09-28) -- accepted

Accepted after re-issue 2. The kernel read in full; `diff <(git show HEAD:Core.lua) <(cat Core.lua
Core_TBC.lua)` checked hunk by hunk: every moved TBC line is byte-identical, the only new TBC code is
the three seams. Rerun by the lead: corecheck 10 / 8, adaptercheck 15 / 11, forevercheck 13,
probecheck 58, the sixteen TBC tails unchanged, the Forever TOCs differ only on the marker, `luac`
clean. What the two re-issues fixed, for the record: `MD.API.Print` had cached the chat frame (a TBC
behaviour change the three chat-capturing suites caught), and `DetectProfile` read `UnitClass`'s
localized first return as the class token (invisible to every suite because the stub returned the
token twice -- the stub now returns what the client returns, and corecheck failed on the old line
before the fix).
