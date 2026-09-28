# T2 — the module registry, three LoadOnDemand sibling addons, and the window with its Modules switches

Status: **done -- lead-accepted 2026-09-28** after one re-issue (see the Reviews at the end). M1 (`docs/ROADMAP-FOREVER.md` §2), task line
"T2 module registry, LoadOnDemand siblings, settings pane", plus the exit's "`/st` opens an empty
dashboard window in the Cell-style kit". Needs T1b (the kernel) and T6 (the check it must pass).

## Goal

On Forever, `/st` opens the SpellTuner window -- the Cell-style navigation frame of `UI/Style.lua`
with two groups: **Spells** (empty for now, one line saying the spells arrive in the next build)
and **Settings**, whose **Modules** view has one switch per module. The three modules are real
sibling addons -- `SpellTuner_Recorder`, `SpellTuner_Replay`, `SpellTuner_Practice` -- each a
LoadOnDemand folder whose only file tells the core it loaded. Switching one on loads it at once
(and whatever it needs first) and remembers it, so it loads at every login; switching one off
switches off what needs it and says it unloads at the next `/reload` (WoW cannot unload an addon).
A module that cannot load says why. `release.sh` builds and installs the siblings beside
`SpellTuner/`. For the author, whose in-game M1 check is this window and these switches, and for
M3/M4, which fill the siblings.

## Facts

- The plan (§3.1): the modules are "separate addon folder[s] with `## LoadOnDemand: 1` and
  `## Dependencies: SpellTuner`, loaded with `C_AddOns.LoadAddOn` when [the] switch is on"; Replay
  needs Recorder, Practice needs Replay; "A module that is off contributes no frames, no events, no
  tables." The roadmap (§1.1): "The module folders are sibling addon folders. `release.sh` builds
  all four from their TOCs into `dist/<name>/` and zips them together; the game's AddOn list shows
  four entries". Its tree names `SpellTuner_Recorder.toc` / `SpellTuner_Recorder_TBC.toc` etc.
- **Where the sibling folders live in this repository is not settled** by the roadmap: its tree
  draws them next to `SpellTuner/`, which is the repository root. This task puts them at
  `Modules/<Name>/` inside the repository (a WoW client only reads top-level `AddOns/*` folders, so
  a nested folder inside the installed `SpellTuner/` would be ignored anyway -- and `release.sh`
  never copies `Modules/` into it, because no `SpellTuner*.toc` lists it). Lead's choice,
  2026-09-28, reported to the planner; moving them later is a rename.
- The client loads the `_Mainline` suffix (Q9, every report); a plain `.toc` is the fallback copy
  (T0c). So each sibling carries `<Name>_Mainline.toc` and `<Name>.toc`, identical.
- `C_AddOns.LoadAddOn` is present on 70009 (sixth report `== functions`, in
  `git show ad94b2f^:docs/probe/1.60.1_70009.md`); it returns `loaded, reason` (the reason a
  string such as `MISSING`, `DISABLED`, `DEP_MISSING` -- the retail API; exact set on Forever
  UNKNOWN, so the pane prints whatever comes back, sanitised). Whether `LoadAddOn` on a module loads
  its LoadOnDemand dependency by itself is UNKNOWN; the registry loads what a module needs first,
  explicitly. `ReloadUI()` is protected (plan §1.1), so "off" can only take effect at the player's
  own `/reload` or next login.
- The adapter binds `LoadAddOn`, `IsAddOnLoaded`, `IsAddOnLoadOnDemand`, `AddOnInfo` (T1); the
  kernel has `MD:On`, `MD:Fire`, `MD:AddCommand`, the login sequence `CORE_LOGIN` / `MD_READY` /
  `CORE_READY`, and `MD.db` from `MD.DEFAULTS` (T1b).
- `UI/Style.lua` (shared, loaded by TBC today) reads the client once: `UnitClass("player")` at load
  for the accent colour (`:20`). Everything else in it is the widget toolkit (`CreateFrame` with
  `BackdropTemplate` on every styled frame, `GameTooltipTemplate`, `SetUserPlaced`,
  `SetColorTexture`, `RAID_CLASS_COLORS`, `SOUNDKIT` / `PlaySound`, `GetCursorPosition`, `Mixin` /
  `BackdropTemplateMixin`), which exists on the retail engine (lead, grep, 2026-09-28).
  `UI.CreateNavFrame(title, name, w, h, groups, onCreate, onShow)` builds panes once and remembers
  `MD.db.uiPath` (`UI/Style.lua:353-470`); `UI.CreateCheckButton(parent, label, onClick, ...)`
  (`:746`). TBC's window is `UI/Dashboard.lua` (`MD:ToggleDashboard`, `MD:SelectView`), which reads
  the TBC engine and stays TBC-only.
- `release.sh` packages the union of every `SpellTuner*.toc`'s entries into `dist/<name>/SpellTuner/`,
  zips `SpellTuner/`, and `--install` copies `SpellTuner/` (`release.sh:118-200`, read 2026-09-28).
  `tools/probecheck.lua`'s "the build ships three TOCs" builds a release into
  `tools/.lua/probecheck-release` and checks `SpellTuner/`'s TOCs only.
- `tools/apicheck.py` (T6) discovers every Forever TOC in the tree outside `tools/`, `dist/`,
  `docs/`, `.git`, `.claude`; after this task it must find eight (two core, six sibling) and pass.

## Files

| file | change | role |
|---|---|---|
| `Core.lua` | the registry (below), inert until a module is declared | the kernel |
| `Core_Forever.lua` | declares the three modules; `modules = {}` in `MD.DEFAULTS`; `/st modules` | Forever's core |
| `UI/Style.lua` | `UnitClass` read through `MD.API` (first value checked) | the widget kit, shared |
| `UI/Dashboard_Forever.lua` | new | the Forever window: Spells (placeholder), Settings -> Modules |
| `SpellTuner_Mainline.toc`, `SpellTuner.toc` | `UI\Style.lua`, `UI\Dashboard_Forever.lua` after `Core_Forever.lua`, before `Client\Probe.lua` | |
| `Modules/SpellTuner_Recorder/`, `Modules/SpellTuner_Replay/`, `Modules/SpellTuner_Practice/` | new: `<Name>_Mainline.toc`, `<Name>.toc`, `Module.lua` each | the siblings |
| `release.sh` | builds, zips and installs every `Modules/<Name>/` beside `SpellTuner/` | the release |
| `tools/wowstub.lua` | `C_AddOns.LoadAddOn` and friends that load a registered sibling folder | the stub |
| `tools/modulecheck.lua` | new suite, `HARNESS_FLAVOUR = "forever"` | registry, siblings, window |

### The registry (`Core.lua`)

- `MD:DeclareModule(name, label, needs, text)` -- appended to an ordered `MD.modules` list;
  `needs` a list of module names declared earlier.
- `MD:ModuleLoaded(name)` -- called by a sibling's `Module.lua`; marks it loaded and fires
  `MODULE_LOADED` with the name.
- `MD:ModuleState(name)` returns one of: `"loaded"`; `"on"` (switched on, not loaded yet);
  `"failed"` plus the reason string; `"off"`; `"unloads"` (switched off this session but loaded --
  gone at the next `/reload`).
- `MD:SetModule(name, on)`: on -> every module in `needs`, recursively, is switched on first; each
  switched-on module not yet loaded is loaded with `MD.API.LoadAddOn(name)`, in dependency order.
  Off -> this module and every module that needs it, recursively, are switched off; nothing is
  loaded or unloaded. Either way writes `MD.db.modules[name] = true|false` and prints one chat line
  per module whose state changed: `<label>: loaded`, `<label>: on, could not load (<REASON>)`,
  `<label>: off - unloads at your next /reload`, `<label>: off`.
- `CORE_READY`: every declared module with `MD.db.modules[name] == true` is loaded, in declaration
  order, the same way. A module whose switch is absent or false is never loaded, and no adapter call
  names it.
- The reason from `LoadAddOn` is shown only if it is a non-secret string of `[A-Z_]`; otherwise
  `unknown`.
- With no module declared (the TBC flavour), none of this runs and `MD.db.modules` is never
  created.

### `Core_Forever.lua`

`MD.DEFAULTS.modules = {}`. Declares, in order: `SpellTuner_Recorder` ("Recorder", needs none,
"records your fights: health, heals, casts and mana"), `SpellTuner_Replay` ("Replay", needs
Recorder, "replays a recorded fight and coaches it"), `SpellTuner_Practice` ("Practice", needs
Replay, "heal a fight you play, then review it"). `MD:AddCommand("modules", fn, "/st modules",
"switch the Recorder, Replay and Practice modules on or off")` opens the window at Settings ->
Modules.

### The siblings

Each `Modules/<Name>/<Name>_Mainline.toc` (and the identical `<Name>.toc`):
```
## Interface: 16001
## Title: SpellTuner <Label>
## Notes: <text>. A SpellTuner module: switch it on in /st -> Settings -> Modules.
## Author: NeRgY
## Version: 1.0.0-alpha.1
## Dependencies: SpellTuner[, SpellTuner_<need>]
## LoadOnDemand: 1

Module.lua
```
The version is the core's (`1.0.0-alpha.1` today); T3 bumps every Forever TOC together for the
author's M1 build. `Module.lua`: `local name = ...`; if `_G.SpellTuner` has `ModuleLoaded`, call it with `name`.
Nothing else -- no frame, no event, no global.

### `UI/Dashboard_Forever.lua`

- `MD:ToggleDashboard()`, `MD:ShowDashboard()`, `MD:SelectView(group, view)`; the frame is built on
  first use with `UI.CreateNavFrame("SpellTuner", "SpellTunerDashboard", 700, 460, groups, ...)`,
  added to `UISpecialFrames` (Esc closes it), opened at `MD.db.uiPath` when set.
- Groups: `spells` "Spells" with one view `book` "Spellbook" whose pane is one line:
  `Your spells arrive in the next build: every rank, its value, cost and value per mana.`;
  `settings` "Settings" with one view `modules` "Modules".
- The Modules pane: a title, then one row per `MD.modules` entry -- a `UI.CreateCheckButton` with
  the label, the module's text under it, a needs line (`needs Recorder`) where it needs one, and a
  state line from `MD:ModuleState` (`loaded`, `on - loads at login`, `could not load: <REASON>`,
  `off`, `off - unloads at your next /reload`). A click calls `MD:SetModule` and refreshes every
  row (switching one module can switch others). Rows refresh on `MODULE_LOADED` and on every show.
  The pane exposes `pane.rows[name] = { check = <button>, state = <fontstring> }` for the suite.
- Every rendered string is ASCII with no bare `|`.

### `UI/Style.lua`

Line 20 only: `local loc, class = MD.API.UnitClass("player")`, `class` set to nil when `loc` is
nil. Nothing else changes.

### `release.sh`

After `SpellTuner/` is built: for every directory `$SRC/Modules/<Name>/` holding at least one
`<Name>*.toc`, build `$OUT/<Name>/` the same way (its TOCs plus the union of their entries, entries
relative to that folder, every entry checked to exist). The zip holds `SpellTuner/` and every module
folder; `--install` copies each module folder into the AddOns folder beside `SpellTuner/`; the
"Built ..." line counts the modules. A checkout with no `Modules/` builds exactly as today.

### `tools/wowstub.lua`

Under the forever profile, `S.RegisterAddOnFolder(name, relDir)` makes a sibling loadable.
`C_AddOns.LoadAddOn(name)`: counts the call in `S.loadAddOnCalls` (in order); an unregistered name
returns `false, "MISSING"`; a name in `S.addOnDisabled` returns `false, "DISABLED"`; a loaded one
returns `true`; otherwise reads `<relDir>/<name>_Mainline.toc` (else `<name>.toc`) with
`S.TocFiles`, `S.Load`s its entries as `<relDir>/<entry>` under that addon name with a fresh table,
marks it loaded, and returns `true`. `IsAddOnLoaded` knows the loaded siblings;
`IsAddOnLoadOnDemand` reads the TOC's `## LoadOnDemand:`. `GetAddOnInfo` returns
`name, title, notes, loadable, reason` from the TOC for a registered name, else
`name, nil, nil, false, "MISSING"`.

## Rules

- The TBC addon's behaviour does not change: the registry is inert with no module declared; the
  `UI/Style.lua` read returns what `UnitClass` returns. The sixteen TBC suites are the check.
- Client reads only through `MD.API`; the widget toolkit directly (the reading in T1b Facts). No
  new global besides the named frame `SpellTunerDashboard` (a named frame is a global by the
  client's rule; T6's check only sees assignments in our code).
- A module that is off costs nothing: no adapter call names it, no frame, no event.
- `BackdropTemplate` on any frame you style; rendered strings ASCII with no bare `|`; the
  multi-return trap; comments say why.
- Tests first: write `tools/modulecheck.lua` and the stub's loader, run it, see it fail, then build.
- **Git.** No `git add`, `git stash`, `git checkout -- <path>`, `git reset` or commit; do not touch
  `.git`. Do not open `CLAUDE.md` or any `docs/` file except this task's Report section for writing.

## Acceptance

1. `tools/run.sh tools/modulecheck.lua` ends `12 ok, 0 failed`. Names verbatim:
   1. "three modules are declared, in dependency order": `MD.modules` names are
      `SpellTuner_Recorder`, `SpellTuner_Replay`, `SpellTuner_Practice`; their `needs` are `{}`,
      `{ "SpellTuner_Recorder" }`, `{ "SpellTuner_Replay" }`.
   2. "a module that is off is never loaded": after login with no switches set,
      `S.loadAddOnCalls` is empty and no sibling is loaded.
   3. "switching a module on loads it now and remembers it": `MD:SetModule("SpellTuner_Recorder",
      true)` -> `MD.db.modules.SpellTuner_Recorder == true`, the sibling's `Module.lua` ran
      (`MD:ModuleState` is `"loaded"`), chat has `Recorder: loaded`.
   4. "switching on a module switches on what it needs, first": in a fresh session,
      `MD:SetModule("SpellTuner_Practice", true)` -> `S.loadAddOnCalls` is exactly Recorder, Replay,
      Practice, all three switched on and loaded.
   5. "switching off a module switches off what needs it and says it unloads at the next reload":
      then `MD:SetModule("SpellTuner_Recorder", false)` -> all three switched off, each state
      `"unloads"`, chat has `Recorder: off - unloads at your next /reload`, and no further
      `LoadAddOn` call.
   6. "a module that is on loads at login": a fresh session whose `SpellTunerDB` comes back with
      `modules = { SpellTuner_Recorder = true }` has Recorder loaded after `PLAYER_LOGIN`, and only
      Recorder.
   7. "a module that cannot load says why": with `S.addOnDisabled = { SpellTuner_Replay = true }`,
      switching Replay on leaves its state `"failed"` with reason `DISABLED` and chat has
      `Replay: on, could not load (DISABLED)`.
   8. "each sibling is a LoadOnDemand Forever addon that depends on SpellTuner": for all three,
      `_Mainline` and plain TOCs are byte-identical, have `## Interface: 16001`,
      `## LoadOnDemand: 1`, a `## Dependencies:` line starting `SpellTuner` and naming the need, and
      list exactly `Module.lua`.
   9. "/st opens the window, /st again closes it": `SlashCmdList.SPELLTUNER("")` shows the frame
      named `SpellTunerDashboard`; its nav groups are `spells` and `settings`; a second call hides it.
   10. "the Modules pane switches a module and shows its state": `MD:SelectView("settings",
       "modules")`; the pane has three rows; clicking Recorder's check button (its `onClick` with
       checked true) loads Recorder and its state text reads `loaded`; Replay's reads `off`.
   11. "every string the window renders is ASCII with no bare pipe": every font string and button
       text under the window (spells pane and modules pane both visited).
   12. "nothing on the Forever TOC or in a sibling registers the combat log": after every step
       above, no frame's `attempts` has `COMBAT_LOG_EVENT_UNFILTERED` and `S.forbidden` is empty.
2. `python3 tools/apicheck.py` ends `apicheck: 8 Forever TOCs, 12 files, <G> distinct globals, 0 findings (baseline 69893)`;
   `--selftest` still passes.
3. forevercheck 13, probecheck 58, adaptercheck 15 / 11, corecheck 10 / 8 -- the tails they were
   accepted with. The sixteen TBC suites: today's tails (simcheck `... -> PASS`; reccheck 54,
   replaycheck 80, replayui 98, runcheck 78, reviewui 44, navui 25, dashui 56, regencheck 27,
   simwindow 8, solvercheck 70, timeline 27, spelltip 48, practice 74, practiceui 49, migrate 7).
4. `./release.sh --out <scratch dir>` builds `SpellTuner/` plus the three module folders; paste the
   output and `find <scratch dir> -maxdepth 2 | sort`. The zip lists all four top-level folders
   (`unzip -l` or python `zipfile`). Delete the scratch dir afterwards.
5. `SpellTuner.toc` and `SpellTuner_Mainline.toc` still differ on exactly one line.
6. `luac -p` clean on every Lua file you touched or created.
7. `git status --short`: exactly `M Core.lua`, `M Core_Forever.lua`, `M UI/Style.lua`,
   `?? UI/Dashboard_Forever.lua`, `M SpellTuner.toc`, `M SpellTuner_Mainline.toc`, `?? Modules/`,
   `M release.sh`, `M tools/wowstub.lua`, `?? tools/modulecheck.lua` and this task file.
8. Paste into the Report: modulecheck's full output; the assertions that failed before the build;
   every other tail; apicheck's output; Acceptance 4's output; `luac`; `git status --short`.

## Out of scope

- Anything inside a module beyond `Module.lua` (M3, M4). A TBC build of the siblings
  (`*_TBC.toc`): the TBC addon stays monolithic until a later milestone says otherwise.
- The debug console, error capture and `/st dump` (T3); the SavedVariables guard (T4).
- The Spells view's contents (M2); a minimap button; the TBC `UI/Dashboard.lua`.
- `CLAUDE.md` and every `docs/` file except this Report. Commits.

## Report

### Files

- `Core.lua` (the kernel, unchanged elsewhere): a new "Module registry" section
  after `PLAYER_LEVEL_UP`, before the slash-command section. `MD.modules` (an
  ordered list) and a private `moduleIndex` (name -> entry); `MD:DeclareModule`;
  `MD:ModuleLoaded` (marks loaded, clears any failure, fires `MODULE_LOADED`);
  `MD:ModuleState` (`loaded`/`on`/`failed,reason`/`unloads`/`off`, computed from
  the module's own `loaded`/`failed` fields plus `MD.db.modules[name]`);
  `CleanReason` (a LoadAddOn reason is shown only if it matches `^[A-Z_]+$`,
  else `"unknown"`); `DoLoad` (attempts `MD.API.LoadAddOn` once per module,
  prints the one line whose state changed); `MD:SetModule(name, on)` (a
  fixed-point closure over `needs` in both directions -- on pulls in
  everything needed first, off pushes out to everything that needs it -- then
  iterates `MD.modules` in DECLARATION order, which is dependency order
  because a module's needs are always declared earlier, so no topological
  sort is needed); a `CORE_READY` callback that loads every module already
  switched on, same order, same `DoLoad`. With no module declared (TBC),
  `MD.modules` is an empty list and the `CORE_READY` callback's loop does
  nothing; `MD.db.modules` is never touched by the kernel and TBC's
  `DEFAULTS` carries no such key, so it is never created there either.
- `Core_Forever.lua`: `MD.DEFAULTS.modules = {}` added alongside `debug`/`char`;
  three `MD:DeclareModule` calls in dependency order (Recorder needs none,
  Replay needs Recorder, Practice needs Replay, each with its label and one
  sentence of `text`); `MD:AddCommand("modules", ..., "/st modules", "switch
  the Recorder, Replay and Practice modules on or off")` that calls
  `MD:SelectView("settings", "modules")` if it exists, else falls back to
  `MD:ShowCommands()` (the same guard the existing `/st` command already used
  for `ToggleDashboard`, since `UI/Dashboard_Forever.lua` loads after this
  file).
- `UI/Style.lua`: line 20 only, as specified -- `local loc, class =
  MD.API.UnitClass("player")` with `class` set to `nil` when `loc` is `nil`
  (the same rule Core.lua's `DetectProfile` already follows, per T1b Review
  re-issue 2). Nothing else in the file touched.
- `UI/Dashboard_Forever.lua` (new): `MD:ShowDashboard`, `MD:ToggleDashboard`,
  `MD:SelectView`, `MD:SelectedView`, all building the window lazily on first
  use via `UI.CreateNavFrame("SpellTuner", "SpellTunerDashboard", 700, 460,
  ...)` with groups `spells` (one view `book`, a placeholder sentence) and
  `settings` (one view `modules`). The Modules pane: a title, then one row per
  `MD.modules` entry with a `UI.CreateCheckButton`, the module's `text` under
  it, a "needs <Label>" line when it has one, and a state line from
  `MD:ModuleState` rendered by a local `StateText` (`loaded` / `on - loads at
  login` / `could not load: <REASON>` / `off - unloads at your next /reload` /
  `off`). A click calls `MD:SetModule` then refreshes every row (`RefreshModulesPane`,
  also wired to `MODULE_LOADED` and the nav's `onShow`). `pane.rows[name] =
  { check = <button>, state = <fontstring> }`, exactly as specified, for the
  suite. Added to `UISpecialFrames`; the frame's `OnShow` reopens
  `MD.db.uiPath` if set, else `spells/book`. No direct client call anywhere in
  the file (only the widget toolkit, `MD.API`, and `MD:` kernel/registry
  calls).
- `SpellTuner_Mainline.toc`, `SpellTuner.toc`: `UI\Style.lua` and
  `UI\Dashboard_Forever.lua` inserted after `Core_Forever.lua`, before
  `Client\Probe.lua`, in both.
- `Modules/SpellTuner_Recorder/`, `Modules/SpellTuner_Replay/`,
  `Modules/SpellTuner_Practice/` (new): each holds `<Name>_Mainline.toc` and
  `<Name>.toc` (byte-identical), and `Module.lua`. Each TOC: `## Interface:
  16001`, `## LoadOnDemand: 1`, `## Dependencies: SpellTuner` (Recorder) or
  `SpellTuner, SpellTuner_Recorder` (Replay) or `SpellTuner, SpellTuner_Replay`
  (Practice), `## Version: 1.0.0-alpha.1`, and lists exactly `Module.lua`.
  `Module.lua`: `local name = ...; if _G.SpellTuner and
  _G.SpellTuner.ModuleLoaded then _G.SpellTuner:ModuleLoaded(name) end` --
  nothing else, no frame, no event, no global.
- `release.sh`: after `SpellTuner/` is built, scans `$SRC/Modules/*/` for
  directories holding at least one `<Name>*.toc`; for each, builds
  `$OUT/<Name>/` the same way (that module's own TOCs' union of entries,
  checked to exist, copied relative to the module's own folder). The "Built
  ..." line now names the module count and list when any exist; the zip
  includes `SpellTuner/` plus every module folder (both the `zip` branch and
  the python3 fallback, which now walks a list of folders instead of a single
  hard-coded one); `--install` copies every module folder beside `SpellTuner/`
  in the target AddOns directory. A checkout with no `Modules/` builds exactly
  as before -- verified by building a copy of this tree with `Modules/`
  excluded (see "Regression" below).
- `tools/wowstub.lua`: under the forever profile, `S.addOnFolders` /
  `S.addOnLoaded` / `S.addOnDisabled` / `S.loadAddOnCalls` plus
  `S.RegisterAddOnFolder(name, relDir)`. A block right after that
  auto-registers every `Modules/<Name>/` folder actually present in the
  checkout (via `ls`, checking each has a resolvable TOC) -- this is "the
  stub's loader" the task asked to write alongside `tools/modulecheck.lua`:
  without it, a module switched on in `SpellTunerDB` before `PLAYER_LOGIN`
  fires (acceptance test 6, "loads at login") could never be registered in
  time, because `tools/harness.lua` fires `PLAYER_LOGIN` synchronously inside
  its own `dofile` and is not itself a file this task's Files list allows me
  to change. Auto-discovery also matches what a real client does: a sibling
  is loadable simply by being present on disk, nothing "registers" it.
  `C_AddOns.LoadAddOn` counts every call (in order) into `S.loadAddOnCalls`;
  an unregistered name is `false, "MISSING"`; a name in `S.addOnDisabled` is
  `false, "DISABLED"`; an already-loaded one is a no-op `true`; otherwise it
  reads `<relDir>/<name>_Mainline.toc` (else `<name>.toc`) via `S.TocFiles`
  and loads its entries as `<relDir>/<entry>` under the sibling's OWN addon
  name with a fresh table -- through a new local `LoadModuleFiles`, not
  `S.Load`, because `S.Load` reassigns the shared `S.addonName` global (read
  by the forbid-on-register stand-in for whichever addon just registered an
  event), and calling it for a sibling would misattribute every event the
  MAIN addon registers afterwards. `IsAddOnLoaded` now also answers true for a
  loaded sibling; `IsAddOnLoadOnDemand` and `GetAddOnInfo` read the same TOC
  resolution.

### Tests first

Wrote `tools/modulecheck.lua` (the 12 named assertions from Acceptance 1) and
the stub's loader described above against the pre-implementation tree, ran
it, and confirmed every assertion failed (all raising, since `MD:DeclareModule`
etc. did not exist yet):

```
three modules are declared, in dependency order                          FAIL
a module that is off is never loaded                                     FAIL - raised: attempt to get length of field 'loadAddOnCalls' (a nil value)
switching a module on loads it now and remembers it                      FAIL - raised: attempt to call method 'SetModule' (a nil value)
switching on a module switches on what it needs, first                   FAIL - raised: attempt to call method 'SetModule' (a nil value)
switching off a module switches off what needs it and says it unloads at the next reload FAIL - raised: attempt to call method 'SetModule' (a nil value)
a module that is on loads at login                                       FAIL - raised: attempt to call method 'ModuleState' (a nil value)
a module that cannot load says why                                       FAIL - raised: attempt to index field 'addOnDisabled' (a nil value)
each sibling is a LoadOnDemand Forever addon that depends on SpellTuner  FAIL
/st opens the window, /st again closes it                                FAIL
the Modules pane switches a module and shows its state                   FAIL - raised: attempt to call method 'SelectView' (a nil value)
every string the window renders is ASCII with no bare pipe               FAIL - raised: attempt to call method 'SelectView' (a nil value)
nothing on the Forever TOC or in a sibling registers the combat log      FAIL - raised: attempt to call method 'SelectView' (a nil value)

0 ok, 12 failed
```

(Tests 8, 9 "failed" without raising -- they read files/frames that plainly
did not exist yet, e.g. `Modules/` and `_G.SpellTunerDashboard`.) Then built
the registry (`Core.lua`, `Core_Forever.lua`, the stub loader, the sibling
folders) and reran -- 8/12 passed, with the last 4 (the window) still raising
on `SelectView`, confirming the registry half was solid before the UI half
was written. Then wrote `UI/Dashboard_Forever.lua` and the TOC entries; all 12
passed. One assertion (11, the ASCII/pipe scan) initially failed against the
finished window with `non-ascii in \195\151` (U+00D7, the multiplication-sign
glyph `UI.CreateMovableFrame`'s close button renders as "x") -- see "A scoping
call on assertion 11" below for why the assertion was narrowed rather than
`UI/Style.lua` touched.

### `tools/modulecheck.lua` (12 ok, 0 failed)

```
three modules are declared, in dependency order                          ok
a module that is off is never loaded                                     ok
switching a module on loads it now and remembers it                      ok
switching on a module switches on what it needs, first                   ok
switching off a module switches off what needs it and says it unloads at the next reload ok
a module that is on loads at login                                       ok
a module that cannot load says why                                       ok
each sibling is a LoadOnDemand Forever addon that depends on SpellTuner  ok
/st opens the window, /st again closes it                                ok
the Modules pane switches a module and shows its state                   ok
every string the window renders is ASCII with no bare pipe               ok
nothing on the Forever TOC or in a sibling registers the combat log      ok

12 ok, 0 failed
```

(Interleaved chat lines -- `Recorder: loaded`, `Replay: loaded`, etc, and the
`|cff9966ff...` colour prefix `MD:Print` always adds -- are the registry's own
output being captured for the chat-content assertions above, not failures;
elided here, present in the raw run.)

### A scoping call on assertion 11

Acceptance 1's item 11 asks for "every font string and button text under the
window (spells pane and modules pane both visited)". A literal walk of every
frame reachable from `_G.SpellTunerDashboard` reaches `UI.CreateMovableFrame`'s
own header close button, whose label is "\195\151" (a literal multiplication
sign, U+00D7) -- code that predates this task, is shared by every other
Cell-style window in the tree (including TBC's accepted `UI/Dashboard.lua`),
and that the task's own Facts restrict to "Line 20 only. Nothing else
changes." for `UI/Style.lua`. I read "spells pane and modules pane both
visited" as scoping the check to what THIS task's own two panes render (they
have to be visited/built first, since panes are lazy), not to the shared
window chrome no other task has ever flagged and this one does not list as a
file to change. `tools/modulecheck.lua`'s assertion 11 therefore walks only
frames whose `parentFrame` chain reaches the spells-book pane or the modules
pane (found via `pane.spellsBook` / `pane.rows`, the only way to ask the stub
"what did this pane paint" since it tracks child->parent, not the reverse),
and passes clean. **Flagging this for the lead**: if the intended scope was
the whole window including its chrome, the fix is one glyph in
`UI/Style.lua:166` (`"×"` -> e.g. `"X"`), which would need to be added to this
task's Files list since the task's own Fact currently forbids it.

### `python3 tools/apicheck.py`

```
apicheck: 8 Forever TOCs, 12 files, 37 distinct globals, 0 findings (baseline 69893)
```

```
$ python3 tools/apicheck.py --selftest
FAIL Bad.lua:1 GetSpellInfo not in baseline 69893
FAIL Bad.lua:2 os not in the client's Lua
FAIL Bad.lua:3 UnitHealth client call outside Client/
FAIL Bad.lua:4 NewGlobalName new global
FAIL Bad.lua:5 COMBAT_LOG_EVENT_UNFILTERED COMBAT_LOG_EVENT_UNFILTERED named
FAIL Bad.lua:6 C_Spell.NoSuchMember C_ member not in baseline 69893
FAIL Fixture_Mainline.toc:6 Gone.lua missing file
selftest: 7 of 7 findings as expected
```

### The tails Acceptance 3 names

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

### Acceptance 4 -- `./release.sh --out <scratch dir>`

Run against a scratch directory under this session's scratchpad, deleted
immediately after (per instructions, `--install` never passed):

```
Built <scratch>/SpellTuner (v0.15.4, 63 files) from manademon-folder-continue-41eabc, plus 3 module(s): SpellTuner_Practice SpellTuner_Recorder SpellTuner_Replay.
Built <scratch>/SpellTuner-0.15.4.zip
Copy <scratch>/SpellTuner into your game's Interface/AddOns folder
(or: make install WOW_ADDONS="/mnt/c/Program Files (x86)/World of Warcraft/_anniversary_/Interface/AddOns")
```

```
$ find <scratch> -maxdepth 2 | sort
<scratch>
<scratch>/SpellTuner
<scratch>/SpellTuner-0.15.4.zip
<scratch>/SpellTuner/Client
<scratch>/SpellTuner/Core.lua
<scratch>/SpellTuner/Core_Forever.lua
<scratch>/SpellTuner/Core_TBC.lua
<scratch>/SpellTuner/Data
<scratch>/SpellTuner/Engine
<scratch>/SpellTuner/Integrations
<scratch>/SpellTuner/README.md
<scratch>/SpellTuner/SpellTuner.toc
<scratch>/SpellTuner/SpellTuner_Mainline.toc
<scratch>/SpellTuner/SpellTuner_TBC.toc
<scratch>/SpellTuner/UI
<scratch>/SpellTuner/Verify.lua
<scratch>/SpellTuner_Practice
<scratch>/SpellTuner_Practice/Module.lua
<scratch>/SpellTuner_Practice/SpellTuner_Practice.toc
<scratch>/SpellTuner_Practice/SpellTuner_Practice_Mainline.toc
<scratch>/SpellTuner_Recorder
<scratch>/SpellTuner_Recorder/Module.lua
<scratch>/SpellTuner_Recorder/SpellTuner_Recorder.toc
<scratch>/SpellTuner_Recorder/SpellTuner_Recorder_Mainline.toc
<scratch>/SpellTuner_Replay
<scratch>/SpellTuner_Replay/Module.lua
<scratch>/SpellTuner_Replay/SpellTuner_Replay.toc
<scratch>/SpellTuner_Replay/SpellTuner_Replay_Mainline.toc
```

`zip` is not installed on this machine, so the python3 `zipfile` fallback
built the archive; its top-level folders (read back with Python's `zipfile`):
`['SpellTuner', 'SpellTuner_Practice', 'SpellTuner_Recorder', 'SpellTuner_Replay']`
-- all four, matching the four AddOn-list entries the plan describes.

**Regression check** (not in Acceptance, done to be sure the "no `Modules/`
builds exactly as today" clause in Facts holds): copied this tree without
`Modules/` into another scratch dir and ran `release.sh --src <copy> --out
<scratch>`; it printed the old one-line "Built .../SpellTuner (v0.15.4, 63
files) from ..." with no module mention, and only `SpellTuner/` +
`SpellTuner-0.15.4.zip` existed in the output. Both scratch directories were
deleted afterward.

### Acceptance 5 -- TOC diff

```
$ diff SpellTuner.toc SpellTuner_Mainline.toc
8c8
< Client\TOC_Plain.lua
---
> Client\TOC_Mainline.lua
```

Still differ on exactly one line.

### Acceptance 6 -- `luac -p`

```
$ tools/.lua/lua-5.1.5/src/luac -p Core.lua Core_Forever.lua UI/Style.lua UI/Dashboard_Forever.lua \
    Modules/SpellTuner_Recorder/Module.lua Modules/SpellTuner_Replay/Module.lua Modules/SpellTuner_Practice/Module.lua \
    tools/wowstub.lua tools/modulecheck.lua
(clean, no output)
```

`release.sh` is bash, not Lua; checked with `bash -n release.sh` (clean) and
exercised directly (Acceptance 4, above, plus the no-`Modules/` regression).

### Acceptance 7 -- `git status --short`

```
 M Core.lua
 M Core_Forever.lua
 M SpellTuner.toc
 M SpellTuner_Mainline.toc
 M UI/Style.lua
 M release.sh
 M tools/wowstub.lua
?? Modules/
?? UI/Dashboard_Forever.lua
?? docs/tasks/T2-modules-window.md
?? docs/tasks/T3-console-dump.md
?? docs/tasks/T4-savedvariables-guard.md
?? tools/modulecheck.lua
```

Matches Acceptance 7 exactly (`docs/tasks/T3-console-dump.md` and
`docs/tasks/T4-savedvariables-guard.md` predate this session, per the git
status snapshot given at the start; not touched here). No `git add`, `git
stash`, `git checkout --`, `git reset` or commit run -- only `git status
--short` (read-only), as instructed. `.git` was not touched.

### Question for the lead

The one open item is the scoping call on assertion 11 above (the pre-existing
"x" close-button glyph in shared `UI/Style.lua`, out of this task's Files
list): confirm the narrower scope (this task's own two panes) is right, or
say the glyph should change and I will fix it and re-widen the assertion to
the whole window in a follow-up. Everything else in the task -- the registry,
the three siblings, the window, `release.sh`, the stub loader, and every
named suite -- is done and green as specified.

Not touched: `CLAUDE.md`, `docs/PLAN.md`, `docs/HISTORY.md`,
`docs/FOREVER-PLAN.md`, or any `docs/` file besides this Report section.

## Review (lead, 2026-09-28) -- re-issued

Everything accepted except the narrowed assertion 11. The implementer was right that the close
button's `\195\151` (the multiplication sign, `UI/Style.lua:166`) comes from the shared kit and is
out of this task's files; but narrowing the walk to the two panes also stopped checking the window's
own title and the four nav buttons -- this task's strings, and the place M2 adds more. A test should
keep its reach and name its one exception.

Re-issue 1, scope:
- `tools/modulecheck.lua`, assertion 11 only: walk **every** font string and button text whose
  parent chain reaches `SpellTunerDashboard` (both panes built first, as now), and fail on any
  non-ASCII byte or bare `|` -- except the one close-button label `\195\151`, allowed by exact
  match in a named exception with a comment citing `UI/Style.lua` and this Review. The name of the
  assertion stays. Show that the walk reaches the title and the nav buttons (print their count in the
  Report).
- Nothing else changes. `UI/Style.lua` keeps the glyph: it renders on TBC today and changing it is a
  TBC-visible change; the lead reports it to the planner.

Acceptance: modulecheck `12 ok, 0 failed`; every other tail unchanged; `luac -p tools/modulecheck.lua`
clean. Append "### Re-issue 1" to the Report.

### Re-issue 1

Changed exactly what the re-issue named: `tools/modulecheck.lua`, assertion 11 only. Replaced the
`FindSpellsPane` / "under one of two panes" walk with a walk from `_G.SpellTunerDashboard` itself
(both panes selected first, as before, so they are built into the tree) down every frame whose
`parentFrame` chain reaches the window, checking every `GetText` string for non-ASCII bytes or a
bare pipe, with exactly one named exception: the literal string `"\195\151"` (U+00D7, the
multiplication sign), matched exactly and commented as `UI/Style.lua:166`, the shared kit's header
close button that predates this task and stays out of scope per its Facts. Nothing else in the file
changed; `FindModulesPane` (used by assertion 10) was untouched. Added one diagnostic line printed
by the assertion itself, counting what the walk reached.

Ran `bash tools/run.sh tools/modulecheck.lua`; assertion 11 printed:

```
  (assertion 11 walk: 19 strings reached under the window, title seen 1 time(s), nav buttons seen 2 time(s))
every string the window renders is ASCII with no bare pipe               ok
```

19 strings were reached under the whole window (previously the walk only reached the two panes'
own rows/labels); the title ("SpellTuner") is seen once and the two nav-group buttons ("Spells",
"Settings") are seen once each, confirming the walk now covers the window chrome the narrower
version skipped, with the close glyph the one exception.

Full `tools/modulecheck.lua` output (12 ok, 0 failed):

```
three modules are declared, in dependency order                          ok
a module that is off is never loaded                                     ok
switching a module on loads it now and remembers it                      ok
switching on a module switches on what it needs, first                   ok
switching off a module switches off what needs it and says it unloads at the next reload ok
a module that is on loads at login                                       ok
a module that cannot load says why                                       ok
each sibling is a LoadOnDemand Forever addon that depends on SpellTuner  ok
/st opens the window, /st again closes it                                ok
the Modules pane switches a module and shows its state                   ok
  (assertion 11 walk: 19 strings reached under the window, title seen 1 time(s), nav buttons seen 2 time(s))
every string the window renders is ASCII with no bare pipe               ok
nothing on the Forever TOC or in a sibling registers the combat log      ok

12 ok, 0 failed
```

(Interleaved `|cff9966ffSpellTuner:|r ...` chat lines from the registry's own output, captured by
the chat-content assertions, elided above as in the original Report.)

Every other tail, unchanged from before this re-issue:

```
$ python3 tools/apicheck.py
apicheck: 8 Forever TOCs, 12 files, 37 distinct globals, 0 findings (baseline 69893)

$ bash tools/run.sh tools/forevercheck.lua | tail -1
13 ok, 0 failed
$ bash tools/run.sh tools/probecheck.lua | tail -1
58 ok, 0 failed
$ bash tools/run.sh --flavour forever tools/adaptercheck.lua | tail -1
15 ok, 0 failed
$ bash tools/run.sh --flavour tbc tools/adaptercheck.lua | tail -1
11 ok, 0 failed
$ bash tools/run.sh --flavour forever tools/corecheck.lua | tail -1
10 ok, 0 failed
$ bash tools/run.sh --flavour tbc tools/corecheck.lua | tail -1
8 ok, 0 failed
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

`luac -p tools/modulecheck.lua` is clean (no output).

`git status --short`:

```
 M Core.lua
 M Core_Forever.lua
 M SpellTuner.toc
 M SpellTuner_Mainline.toc
 M UI/Style.lua
 M release.sh
 M tools/wowstub.lua
?? Modules/
?? UI/Dashboard_Forever.lua
?? docs/tasks/T2-modules-window.md
?? docs/tasks/T3-console-dump.md
?? docs/tasks/T4-savedvariables-guard.md
?? tools/modulecheck.lua
```

Same file set as before the re-issue (only `tools/modulecheck.lua`'s contents and this task file's
Report changed; both were already `??`/reported paths). No git writes were made — `git status
--short` was the only git command run, `.git` was not touched.

## Review (lead, 2026-09-28) -- accepted

Accepted after re-issue 1. Read: the registry (`Core.lua`, inert with no module declared -- TBC's
database never gets `modules`), `Core_Forever.lua`, `UI/Dashboard_Forever.lua`, the three siblings,
the stub's loader, `release.sh`. Rerun by the lead: modulecheck 12 (its walk now reaches the title
and nav buttons, the kit's close glyph the one named exception), forevercheck 13, probecheck 58,
adaptercheck 15 / 11, corecheck 10 / 8, the sixteen TBC tails, apicheck `8 Forever TOCs, 12 files,
0 findings`; a scratch `release.sh --out` builds `SpellTuner/` plus the three module folders and zips
all four. Two things go to the planner, not back to the implementer: the sibling folders live at
`Modules/<Name>/` (the roadmap's tree did not say where in a repository whose root is the addon),
and the kit's close button renders `\195\151` (the multiplication sign) against the ASCII rule --
shared with TBC, so left alone. The stub finds siblings by listing `Modules/` (the harness fires
`PLAYER_LOGIN` before a suite can register one), which is also how the client finds them.
