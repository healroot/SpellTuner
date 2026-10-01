# SpellTuner after 0.16.5: more classes, styles you choose, EllesmereUI, a clock you shape -- spec

**This is the document to implement from**, once the author has answered section 9. It is
written like `docs/SPEC-forever-ui.md`: goals, the shape, one section per ask, what stays true,
what reaches which line, decisions, tasks in waves, in-game checks. Five research notes back
it; every file:line claim below is theirs and was read against `c911339` / `a6a3bcd` (0.16.5):
`R-arch.md` (the seams), `R-classes.md` (spells and classes, two scratch runs marked **[ran]**),
`R-styles.md` (UI styles), `R-ellesmere.md` (the EllesmereUI integration), `R-clock.md` (the
clock). They sit beside this file in `scratchpad/next/`; copy them to `docs/research/` when this
spec is adopted.

**Revision 2** answers `CRITIQUE-next.md` (15 points): cooldowns kept per family (4.2, T90); the
engine's tables from the kit's profile, never the logged-in player's (2.1, T89, T96); the probe put
on the TBC TOC (T87, decision 22); a kernel seam for subcommands and dump lines (2.5, T113); a
risks section (10); the face's `vv` and `nodata` (2.4); decision 10 gating N1; the solver's
assumptions for heals that reach several targets (4.5); Innervate's percent shape (T91, T105); the
full `isDruid` list (4.4); the pure face in `Engine/` and only the renderer in `UI/` (2.4); the
missing Needs and suites (11); the clock role per style owned by the style files (T104); the
mockup disagreements (M7c, C4); named batches per wave (decision 21, 11).

Conventions as always: Lua 5.1, no libraries shipped, ASCII-only rendered text and no bare `|`,
every client call through `MD.API` (client calls in `Client/` only), `.toc` order, `make check`
green, TBC behaviour changes only by a `docs/DECISIONS.md` entry, `UI.THEMED` stays the one "new
structure" flag (true on both lines since wave C), the planner's causality invariant holds.

---

## 0. Goals

The author, after 0.16.5 shipped the refactor and the new UI on both lines:

> "think of how we can better support more spells and classes. Also we can make 2-3 versions of
> UI style (what we have now, classic like, retail like, or elesmere ui like). Also I would like
> to have integration with elesmere UI like we have data text for elvui. And I want the oom timer
> look better (idealy customizable)."

Four asks, four sections:

| Ask | Section | One-line answer |
|---|---|---|
| (A) more spells and classes | 4 | Forever already *reads* every class; make what it reads true (cooldowns, group heals, misreads), then a kit built by shape so the solver coaches any healer. Fix the druid's own cooldown bug first. TBC other classes later, from the client's own tooltips. |
| (B) 2-3 UI styles | 5 | A style is paint only (never geometry): a data table of fills, tokens, fonts and per-role recipes. Flat (today) stays default; **Ellesmere-like** and **Modern (retail-like)** first; **Classic** after its mockup and an art probe. |
| (C) EllesmereUI integration | 6 | EllesmereUI has no datatext API; its DataBars show any **LibDataBroker** object. SpellTuner publishes two brokers (clock, regen) by borrowing the host's LDB, adds an `/unlock` mover and plays well with its minimap collector. One LDB surface also covers Titan / ElvUI's broker list on TBC. |
| (D) a better, customizable clock | 7 | Split *what the clock says* (a pure face record) from *how it is drawn* (layouts). Fix six Forever gaps first; add Compact, Bar and Ring layouts, a sparse override store, and Settings -> Clock with a live preview. |

Non-goals here: physical-class rotation math, tank tooling, a SpellTuner page inside
EllesmereUI's own options (closed to third parties, `R-ellesmere` 2.5), shipping any library,
font or texture file.

---

## 1. What is true today (short)

- **Reading is class-generic on Forever; everything after it is druid-only.** `Spells/Book.lua`
  and `Spells/Parse.lua` read any spellbook; the tooltip block, the rail and the clock already
  work for a priest. The kit (`Kit_Forever.lua:21-37` `FAMILY_KEY` / `FAMILY_TYPE`, repeated in
  `Stream_Forever.lua:28-33`), the engine's three druid HoT slots (`SimModel.lua:91-93`), the
  one cooldown (`SPELL_CD = { [18562] = 15 }`, `:111`), the planner's rules and 29 `isDruid`
  reads in 15 files (4.4 lists them) are druid-only. `SimModel.lua:93` captures
  `local HOT_INDEX = SM.HOT_INDEX` when the file loads, and `tools/import.lua` replays recordings
  of any character, so nothing in the engine may depend on who is logged in.
- **Cooldowns are kept per spell id.** `SimModel.lua:617` writes `S.cd[spellID]` and `SM.Ready`
  (`:1203`) reads it the same way; `Engine/ReplayTrace.lua:94` keeps `cdUntil[spellID]` from
  `SM.SPELL_CD`; `UI/ReplayWindow.lua:812` falls back on a literal `15`. Harmless while Swiftmend
  has one rank; wrong for Holy Shock R1-R4 or Riptide's ranks, which share one cooldown.
- **Bug [ran]: the solver ignores spell cooldowns.** `Solver:Best` (`SimSolver.lua:332-400`) never
  calls `SM.Ready`, and the engine's `Succeed` (`SimModel.lua:604-630`) does not check it either:
  with Swiftmend on cooldown until t=20, `plan:Decide(S, 10, ...)` returns 18562. This is live in
  the author's druid coach on both lines.
- **The parser misreads three texts [ran]** (Light's Vigil R3 as a 684-724 heal costing 1340 mana; Mana Burn's "0.5"
  as 5; Execute's "15 additional damage") and reads every group / bounce heal (Prayer of Healing,
  Chain Heal, Wild Growth, Tranquility, Holy Nova, Binding Heal) as one target's heal. Cooldowns
  are not read, so per second and casts-to-OOM assume a cast every GCD (Holy Shock ~6.7x high).
- **One look.** `UI/Theme_Flat.lua` writes `UI.PALETTE` / `UI.TEXT` / fonts in place at file load;
  `UI.StylizeFrame(frame, color, border)` records colours, not roles, in `UI.pixelFrames`.
- **Two clocks, two strings, one look** (T82): TBC `MD:GetDisplayString` (`Engine/TTO.lua:345-411`)
  over `UI/Widget.lua`; Forever `ManaModel.Text` (`Engine/ManaModel.lua:280-295`) over
  `UI/Clock_Forever.lua`. 180 x 30, centred 13-pt text, 160 x 4 bar (5SR on TBC, the real pool on
  Forever). Forever has no colour, no `usesMana` gate, no click-through, no pulse, no rest toggle.
- **One integration** (`Integrations/ElvUIDatatext.lua`), TBC TOC only, never loaded by the
  harness (`tools/harness.lua:69-72`), its Regen datatext calling `MD.Regen`, which Forever lacks.
- **EllesmereUI 9.3.4 is installed on the author's Forever client, every module disabled**
  (`_classic_beta_/WTF/.../AddOns.txt`). It refuses to run below 12.1 except on Forever, so it
  will never load on TBC (`EllesmereUI_ClientGate.lua:20-36`). ElvUI is not installed on Forever;
  its `ElvUI_Mainline.toc` says 120100, so whether it runs there is unknown.
- **The probe is Forever-only.** `Client/Probe.lua` is listed by `SpellTuner_Mainline.toc` and
  `SpellTuner.toc` only; there is no `/md probe`. Every "on both clients" art or clock answer below
  needs T87 to put it on the TBC TOC (decision 22).
- **`/st clock` and `/st ui` already exist** (`Core_Forever.lua:279`, `:309`), each reading its
  whole argument (`/st clock preview` today toggles the clock), and `MD:AddCommand` replaces a
  row of the same name (`Core.lua:652-672`). TBC has neither verb. New subcommands therefore go
  through a kernel seam (2.5), never a second `AddCommand("ui", ...)`.

---

## 2. The shape: five seams first, then the visible work

Nothing here is a rewrite. Every seam is first a **registry or a split that leaves today's output
byte-identical** (proved by the goldens and suites that already exist), then a second step adds
behaviour. This is the refactor plan's pattern (`PLAN-refactor-ux.md` 2-3).

| # | Seam | First step (byte-identical) | Owner files | Contract | Proved by |
|---|---|---|---|---|---|
| S0 | **Kernel seams** (2.5) | subcommands and dump lines registered by the file that owns them; `/st clock` and `/st ui` answer exactly as today | `Core.lua`, `UI/Dump_Forever.lua` | `MD:AddSubcommand(verb, sub, fn, usage)`; `MD:AddDumpLine(key, fn)` | `corecheck` (+4), `consolecheck` and `slashcheck` unchanged |
| S1 | **Class profile registry** | the druid's constants become *derived* from the druid profile, named explicitly (`MD.Profiles.Get("DRUID")`) | `Spells/Profiles.lua`, `Data/Profile_Druid_TBC.lua`, `Data/Profile_Druid_Forever.lua` | `MD.Profiles.Register(class, p)` / `Get(class)`; `MD.Profile` the logged-in player's, read **only** by the UI, the live kit builder and the recorder; the engine reads `kit.profile`; `MD.Profile:Can(cap)` replaces `isDruid` gates | `tools/profilecheck.lua` (derived tables equal today's constants) + every druid suite unchanged |
| S2 | **Style registry (skin by role)** | flat becomes one registered style; `UI.Skin(frame, role)` paints exactly what `StylizeFrame` painted | `UI/Styles.lua`, `UI/Theme_Flat.lua`, `UI/Style.lua` | `UI.Styles.Register(key, style)`; `UI.SetStyle(key)`; `UI.Skin(region, role)` | `tools/stylecheck.lua` (flat round trip byte-identical) + navui / dashui / spellsui / replayui unchanged |
| S3 | **Feeds and surfaces** | the ElvUI datatexts read feeds, same text | `UI/Feeds.lua`, `Integrations/Surface_ElvUI.lua` | a *feed* (`clock`, `regen`) is text + tooltip + click; a *surface* (widget, minimap, ElvUI, LDB) shows feeds | `tools/surfacecheck.lua` with fake hosts |
| S4 | **Clock face** | `GetDisplayString` and `ManaModel.Text` become `ClockFace.LineString(face)` | `Engine/ClockFace.lua` (pure: face, formatter, samples), `Engine/TTO.lua`, `Engine/ManaModel.lua`; the renderer `UI/ClockView.lua` comes in T93 | each line produces a pure `face`; the renderer draws a face in a layout | `tools/clockfacecheck.lua` goldens captured before the first edit; `ttocheck` 47, `clockcheck` 29 unchanged |

Two working rules that make the waves file-disjoint:

- **Stub extensions live in their own files.** `tools/wowstub.lua` (1763 lines) would otherwise be
  every task's file. New fakes go in `tools/stub_hosts.lua` (ElvUI, LibStub, LDB-1.1,
  EllesmereUI), `tools/stub_art.lua` (textures, atlases, `GetFileIDFromPath`, `SetRotation`) and
  `tools/stub_books.lua` (priest / shaman / paladin spellbooks), each loaded only by the suites that
  need it, so no existing count moves.
- **Host addons are reached only from `Integrations/`.** `EllesmereUI`, `ElvUI` and `LibStub` are
  not client API; `tools/apicheck.py` gets **rule 11**: a `FOREIGN` set allowed only under
  `Integrations/` (with a selftest line), a finding anywhere else. Host detection stays on the
  existing `MD.API.IsAddOnLoaded` / `MD.API.AddOnMetadata` (both TOCs already bind them).

### 2.1 S1: the profile

```lua
-- Spells/Profiles.lua (both main TOCs, after Core.lua, before Spells/RankRules.lua). Pure.
MD.Profiles.Register("DRUID", {
  label      = "Druid",
  critSchool = 4,                         -- MD.API.SpellCritChance(school); Holy = 2
  caps       = { clock = true, tooltip = true, rankTable = true, advisor = true,
                 simulate = true, coach = true, practice = true },
  families = {                            -- key -> how the line names it, how the engine models it
    HealingTouch = { names = { "Healing Touch" }, kit = "direct", bindable = true },
    Regrowth     = { names = { "Regrowth" },      kit = "hybrid", hot = true, bindable = true },
    Rejuvenation = { names = { "Rejuvenation" },  kit = "hot",    hot = true, bindable = true },
    Swiftmend    = { names = { "Swiftmend" },     kit = "instant", eats = { "Regrowth", "Rejuvenation" }, cooldown = 15 },
    Tranquility  = { names = { "Tranquility" },   kit = "channel", exclude = true },
  },                                      -- TBC adds Lifebloom = { kit = "lifebloom", hot = true }
  order    = { "HealingTouch", "Regrowth", "Rejuvenation", "Swiftmend" },
  hotSlots = { "Rejuvenation", "Regrowth", "Lifebloom" },   -- SM.HOT_INDEX in THIS order: traces unchanged
  planner  = { rules = "druid", families = { "Swiftmend", "Regrowth", "HealingTouch", "Lifebloom", "Rejuvenation" } },
  manaCooldowns = { { key = "innervate", short = "inn", id = 29166, duration = 20, value = "innervate" } },
  regen    = { inFsrTalent = { "Intensity", 0.10 } },
})
MD.Profiles.Validate(p)   -> true | false, problems   -- Kit.Validate's style; every kit names a Kit.TYPES entry
MD.Profiles.Get(class)    -> the registered profile, or the generic one (never nil)
MD.Profiles.Select(class) -- at CORE_LOGIN: MD.Profile = Get(class) -- the LOGGED-IN player's
MD.Profile:Can(cap)       -> bool, why   -- the one replacement for MD.player.isDruid gates
p:Family(nameOrKey)       -> key, def
p:HotIndex()              -> { [family] = slot }
MD.Profiles.ForKit(kit)   -> Get(kit.profile or "DRUID")   -- what the engine reads
```

**Two readers, two profiles.** `MD.Profile` is the logged-in player's and is read only by the
UI (gates, words), the live kit builder (`Kit_Forever.lua`, `RankMath:SpellKit`) and the recorders,
each of which **stamps** `kit.profile` / `rec.profile` with its key. Everything that runs on a kit
-- `Engine/SimModel.lua`, `Engine/SimSolver.lua`, `Engine/SimPlanner.lua`, `Engine/ReplayTrace.lua`,
`Scenario_Forever.lua`, `Engine/Practice.lua`, `UI/ReplayWindow.lua` -- reads
`MD.Profiles.ForKit(kit)` and derives its tables **per run** (`S.hotIndex`, `S.cdFamily`, the
solver's families), so `tools/import.lua` replays a priest's recording correctly on a druid's
machine and the other way round. Every recording and kit snapshot made before this spec has no
`profile` and is the druid's (the only class ever recorded), which is what `ForKit`'s default says.
Module-level constants that stay (`SM.HOT_INDEX`, `SM.SPELL_CD`, `SV.FAMILIES`, T89's derived
tables) are derived at file load from `MD.Profiles.Get("DRUID")` **by name**, never from
`MD.Profile` (which does not exist yet at file load: `Select` runs at `CORE_LOGIN`); after T96 the
engine reads them only as the fallback for a kit with no profile.

- **A profile carries names, kit types and rule choices, never spell numbers on Forever** (numbers
  come from the client's text through `Book`). On TBC the druid profile points at
  `Data/SpellData.lua`, which stays the verified source.
- **The generic profile** (any class with no file): `caps = { clock, tooltip, rankTable (Forever) }`
  -- exactly what a non-druid gets today.
- **Capability, not class, is the gate.** On Forever `Can("coach")` is also "the live kit prices at
  least one heal" (`PR.policy.kitIsLive`'s idea), so a class becomes coachable when its kit is
  valid, not when someone flips a flag. The live kit is built in the LoadOnDemand Replay module
  while `Spells/Profiles.lua` is in the main TOC, so `Kit_Forever.lua` provides the answer through
  `MD:Provide("KitLive", fn)` (T96); with the module off there is no provider and `Can("coach")`
  is `false, "module"` -- the caller shows the module's existing placeholder (`Reports -> Review`'s
  "the Replay module is off" line), so no new wording appears.

### 2.2 S2: a style (section 5 has the values)

```lua
UI.Styles.Register("flat", {
  name = "Flat", hint = "SpellTuner's own look.",          -- ASCII
  accent = "class",                                        -- "class" | "gold" | {r,g,b} | "follow"
  palette = { bg = {..}, pane = {..}, ..., hover = { ref = "accent", a = 0.12 }, ... },
  text    = { accent = "<class>", text = "FFFFFF", label = "B3B3B3", ... },
  fonts   = { face = "FRIZ", num = "Fonts\\ARIALN.TTF", flags = "", shadow = { 1, -1 } },
  roles   = { window = { kind = "pixel" }, ..., clock = { kind = "pixel" } },  -- a missing role = flat's
  needs   = {},                                            -- art the presence check must find
})
UI.Styles.Validate(s) -> true | false, problems
UI.SetStyle(key)      -- palette/text written IN PLACE, fonts re-faced (sizes unchanged), every
                      -- registered region repainted, STYLE_CHANGED fired, db.ui.style saved
UI.Skin(region, role) -- roles: window header nav pane button tab field list scroll tooltip clock statusbar rule
```

- **Structure vs skin.** `UI.THEMED` keeps meaning "the new window" and is true under every style.
  A style is a second, paint-only axis, `UI.STYLE` (its key). No pane writes
  `if UI.STYLE == ...`: `tools/themecheck.lua`'s existing gate scan is extended to `UI.STYLE`,
  allowed only in `UI/Style*.lua` / `UI/Styles.lua`.
- **No geometry.** A style never changes a size, anchor, pitch, font size, row height or inset.
  Ornate edges (Classic) are drawn on an **outset child** outside the content rect. Payoff: the
  ~1000 layout assertions hold under every style, decision 13's font cap stays true, and a switch
  never re-lays a window.
- **`UI.pixelFrames[frame] = {color, border}` becomes `UI.skinned[region] = { role, fill, edge }`**
  (weak keys, ElvUI's `E.frames` + `frame.template` pattern). `UI.StylizeFrame` keeps its
  signature; a passed `UI.PALETTE` table is mapped back to its key, so the 13 outside callers
  register correctly with no edit. `UI.RestylePixels` becomes "repaint every registered region".
- **Applied at `CORE_LOGIN`** from `db.ui.style` (default `"flat"`, declared with
  `MD:RegisterDefaults` in `UI/Styles.lua`), before `MD_READY` builds the clocks. Windows are built
  on first open and see the chosen style. **Switching later is live** for every registered region,
  tooltip and font; the ~68 creation-time `SetTextColor(UI.RGB(..))` sites and ~36 frozen accent
  reads follow on `STYLE_CHANGED` once converted (task T107); until then Settings shows one line,
  `Some windows finish changing after a reload  [Reload]` (decision 4).

### 2.3 S3: feeds and surfaces

```lua
-- UI/Feeds.lua (both main TOCs, after UI/Tip.lua)
MD.Feeds.Register("clock", {
  label   = "SpellTuner",
  Text    = function(ctx) end,   -- ASCII; colour codes allowed; ctx = { valueHex, plain, compact }
  Face    = function() end,      -- the clock face (S4), for a surface that colours by tone
  Tooltip = function() end,      -- UI/Tip.lua line model, the minimap tooltip's lines
  Click   = function(button) end,-- left: the window, right: Settings; out of combat only (decision 17)
  icon    = "Interface\\Icons\\Spell_Shadow_Manaburn",
})
MD.Feeds.Register("regen", {...})   -- "Regen 123", " (5SR)" in the rule, "Regen ~123" when modelled
MD:Fire("FEED_CHANGED", key)        -- from the 0.5 s tick, only when Text changed
```

- **One string, every place.** The floating clock, the minimap tooltip, ElvUI, the brokers all
  render the same face through the same formatter with the user's clock settings, so turning the
  rest segment off turns it off everywhere. The regen feed reads the face's `mp5` / `fsr` fields
  (S4), so Forever's regen is the pool's (`MD.Pool:LastRegen()`), never `MD.Regen`, and **never a
  secret**.
- **Surfaces:** the widget (S4), the minimap button (exists), `Integrations/Surface_ElvUI.lua`
  (today's file moved, native datatexts, `valueHex` from `ApplySettings` kept), and
  `Integrations/Surface_LDB.lua` (section 6).

### 2.4 S4: the clock face (section 7 has the layouts)

```lua
face = {
  mode     = "oom"|"hold"|"full"|"warmup"|"ooc"|"fullnow"|"nodata",
  label    = "OOM"|"FULL",
  value    = <seconds> | nil,                 -- what is SHOWN (TBC: latched)
  known    = "point"|"bound"|"pending"|"none",-- ">" bound, "..." warm-up, "--"
  unstable = bool,                            -- TBC "~": CV over CV_STABLE (TTO.lua:374)
  modelled = bool,                            -- Forever "~": always true
  tone     = "crit"|"warn"|"normal"|"good"|"muted",
  arrow    = "v"|"vv"|"^"|"="|nil,            -- nil in FULL and out of combat (DECISIONS:113);
                                              -- "vv" is TBC's crit-band mark (TTO.lua:370: under
                                              -- 20 s, whatever the trend), not a trend; Forever
                                              -- never sets an arrow, so never "vv"
  second   = { kind = "rest"|"cd", label = "rest"|"inn", value = <s> } | nil,
  fsr      = <seconds left in the 5SR>, tick = <s into the 2 s tick> | nil,
  mp5      = <n> | nil, mp5Modelled = bool,
  pct      = <0..1> | nil, pctModelled = bool,-- Forever: the model's, never the client's
  combat   = bool,
}
MD:GetClockFace()              -- TBC, Engine/TTO.lua, from `disp` and `state` exactly as GetDisplayString branches
MD.ManaModel.Face(state, now)  -- Forever, pure
ClockFace.LineString(face, valueHex)   -- the ONE place words and colour codes are assembled
ClockFace.Segments(face, look) -- label / value+arrow / secondary strings for a layout (T93)
ClockFace.SAMPLES              -- fixture faces: the suite AND the Settings preview chips
```

Every `mode` renders as today, byte for byte, including the two "no number" cases that look alike:
`mode = "nodata"` (TBC: no state yet) renders **`FULL --`** in grey (`TTO.lua:355`), while
`mode = "oom"` with `value = nil` renders `OOM --` (`TTO.lua:365`); Forever has only the second
(`~OOM --`). `clockfacecheck` has a golden for each.

**Layering.** `Engine/ClockFace.lua` is pure (no frame, no client call, no `MD.db` read beyond the
look table passed in): the face shape, `LineString`, `Segments`, `SAMPLES`. It is listed by both
main TOCs before `Engine/TTO.lua` / `Engine/ManaModel.lua`, so the offline tools and the Replay
module never depend on a UI file. The renderer -- frames, layouts, the preview -- is
`UI/ClockView.lua` (`MD.ClockView.Build(parent, look)`, created by T93). Each line provides its
producer through `MD:Provide("ClockFace.Current", fn)` (a second provider raises), so the renderer,
the feeds and the preview never branch on the client.

### 2.5 S0: subcommands and dump lines (the kernel)

```lua
-- Core.lua (T113). Byte-identical while nothing registers.
MD:AddSubcommand(verb, sub, fn, usage)   -- `/st <verb> <sub> <rest>` runs fn(rest); else the verb's own fn
MD:AddDumpLine(key, fn)                  -- /st dump calls fn() -> one ASCII line, in registration order
```

- **A sub is matched first** (the argument's first word, case-insensitive); anything else reaches
  the verb's own function exactly as today, so `/st clock`, `/st clock lock` and `/st ui reset` do
  not change. `MD:AddCommand` on a name that already has subs keeps them (it replaces only the
  verb's function and texts), so the order Core_Forever.lua and a later file load in does not
  matter.
- **A sub on a verb no core registered** creates the verb with a function that prints its usage
  list. On TBC this is how `/md ui style` (T94) and `/md clock layout|look|preview` (T102) appear:
  a new verb in the help, so **the task that adds it re-bases `slashcheck/tbc`** (and records the
  DECISIONS line); no other task touches that golden in the same wave.
- **The verb's help row** gains the sub's usage (`/st ui reset|style <name>`) -- one row per verb,
  as today; `corecheck` holds the dispatch, the kept subs and the row.
- **Dump lines** let `UI/Styles.lua` (style, accent, fell back), `Integrations/` (integrations,
  EllesmereUI version, skin `apiVersion`) and `UI/ClockView.lua` (layout, overrides count) add their
  line without owning `UI/Dump_Forever.lua`. With none registered the dump is byte-identical
  (`consolecheck`).

---

## 3. What stays true (the principles)

1. **Client reads through `MD.API`; host addons only from `Integrations/`** (apicheck rule 11).
   Nothing on a Forever TOC registers `COMBAT_LOG_EVENT_UNFILTERED`. `IsSecret` before anything
   but storing.
2. **No libraries shipped.** LibDataBroker and LibStub are **borrowed** from a host that loaded
   them (EllesmereUI ships both; so do ElvUI and Titan) and never copied into the package.
   `release.sh` builds from the TOC lists, so no media or library rule is added. No font file, no
   texture file: the ring is built from `UI.whiteTexture`; Expressway is used only when
   EllesmereUI hands us its path.
3. **ASCII, no bare pipe, two-space separator** in every clock string, feed text, broker text,
   style name and tooltip line. `tools/textcheck.py` covers constants; `clockfacecheck`,
   `surfacecheck` and `euicheck` cover computed strings.
4. **The clock's honesty marks cannot be configured away:** Forever's `~`, TBC's `~` (unstable),
   the `>` bound and `=`, `--` (never `0`), `...` in warm-up. **Precision belongs to the model**:
   formats only, no decimals on OOM / FULL / rest (DECISIONS:110); the one decimal allowed is the
   5SR countdown, a timer read exactly. Tone thresholds move together with the latch's instant
   crossings (`TTO.lua:223`).
5. **One visibility owner per clock frame** (`MD:UpdateVisibility` on TBC, the Forever clock's own
   `UpdateVisibility`), both asking `MD.Visibility.Want`. The renderer, the preview and the
   EllesmereUI mover never call `Show` / `Hide` on the widget.
6. **Forever secrets.** The real pool is only ever *drawn* (`MD.API.DrawUnitPower`), never read.
   No text, ring, colour or show rule uses it; `pct` and every feed on Forever are the model's.
7. **A style is paint only** (no geometry, no behaviour); Flat stays byte-identical; `UI.THEMED`
   is never set by a style.
8. **The causality invariant** (`Engine/SimPlanner.lua` header; `coachforever`, `solvercheck`)
   holds through every engine task. New kit types decide on the present plus trailing damage; a
   heal the plan cannot choose (totem ticks, Lightwell, Vampiric Embrace, Prayer of Mending's jumps)
   is replayed **as recorded**, like a foreign heal.
9. **No value from memory.** `Data/SpellData.lua` changes only from a measurement. A new class's
   numbers come from the client's own text (Forever: always; TBC: the static tooltip, as
   `Engine/DamageMath.lua` already does); rules (coefficients, tick periods, falloff, target
   counts) are marked VERIFY until a measurement or a WCL fit confirms them. Calibration never
   feeds the model.
10. **TBC behaviour changes only by a documented decision.** S0-S4's first steps are
    byte-identical on TBC. Each visible TBC change (the cooldown fix in the coach, the clock's fixed
    segments, the left-click rule, the style picker) gets a DECISIONS entry in its task.
11. **The score stays lexicographic**; the cooldown fix changes which plan wins, not how plans are
    compared.
12. **Approved UI decisions hold** (`SPEC-forever-ui.md` 8.1, `PLAN-refactor-ux.md` 8.1, DECISIONS
    T73-T85). Anything visible waits for its mockup (M7-M9, task T86: drawn, adopted by the integrator).

---

## 4. (A) More spells and more classes

### 4.1 What a healer of each class gets today and needs (Forever, build 70009 texts) [ran]

| class | read as heal / absorb | misread or wrong for a model | refused by design (correct) |
|---|---|---|---|
| Priest | Lesser Heal, Heal, Greater Heal, Flash Heal, Renew, PW:S (absorb), PoH, Binding Heal, Holy Nova, Desperate Prayer | PoH = one member's (x up to 5); Binding Heal x2; Holy Nova's damage half hidden; PW:S priced as a 1.5-s direct heal (4 s cooldown and 15 s Weakened Soul not read); Renew's tick period assumed 3 s | Penance, Prayer of Mending, Lightwell, Vampiric Embrace, Inner Focus, Power Infusion |
| Shaman | Healing Wave, Lesser Healing Wave, Chain Heal, Riptide | Chain Heal = first target (1 + 0.5 + 0.25 = 1.75x when three are hurt); Riptide's 6 s cooldown not read | Healing Stream Totem, Mana Spring / Mana Tide, Water Shield, Nature's Swiftness |
| Paladin | Holy Light, Flash of Light, Holy Shock | **Light's Vigil misread** as a direct heal: R3 (level 60) 684-724 costing 1340, R1 (level 40) 325-343 costing 730 (it is a buff: the next Holy Shock on that target heals their party and triggers no cooldown); Holy Shock's 10 s cooldown not read (~6.7x per second); Blessing of Light is target-side, not in the caster's text | Lay on Hands, Divine Favor |
| Druid | HT, Regrowth, Rejuvenation, Tranquility, Wild Growth all parse | Tranquility in the kit as `channel` but `LandCast` has no channel branch (heals nothing); Wild Growth skipped (1 s ticks, front-loaded); Innervate unmodelled on Forever (the clock reads low for 20 s) | -- |
| Casters / physical | Mage 15 of ~51, Warlock 16 of 59, Hunter 6 of 45 mana spells read; Warrior 2 of 29, Rogue 2 of 22 | Mana Burn "0.5" read as 5; Execute's "15 additional damage" read as its hit | AP-scaled text (correct: the number is not in the text) |

Within one family the rank verdicts (dominance, the suggested rank) stay right for group and
cooldown spells, because the multiplier is the same on every rank. What is wrong is the absolute
"Per mana" / "Per sec" / "Casts", the Overview's cross-family list, and any solver choice between
families.

### 4.2 Phases, by value

| Phase | What | Offline-verifiable | Needs the game |
|---|---|---|---|
| **P0 Engine correctness** (wave N1) | the solver respects cooldowns (`SM.Ready` in `Solver:Best` and rule 8); the engine refuses and traces a **plan** cast on cooldown, while a **recorded** cast (the replay's script, a fixed cast) is never refused -- the recording is the truth (a Light's Vigil'd Holy Shock, a reset talent); **cooldowns kept per family** (`S.cd[family]`, `ReplayTrace`'s `cdUntil[family]`), so one rank's cast blocks every rank of it; an optional `cooldown` kit field (declared in `Kit.FIELDS` first); parse misreads fixed (decimals, "N additional damage", a "your next X" clause refused) | all: `solvercheck` (Swiftmend on cooldown never picked; `R-classes` `cdtest2.lua` as a case; a two-rank family on cooldown after R2 refuses R1), `restcheck` numbers recorded before/after (DECISIONS), `replaycheck` (the Swiftmend-ready dot unchanged), `parsecheck` rows for Mana Burn / Execute / Light's Vigil | none |
| **P1 Reading truth, every class** (N1 parser, N2 display) | `Parse.Targets(text)` (party; target and their party; the caster; target and the caster; jumps + falloff; charges; "below N% Health"; "cannot be X again for N sec"), refusing what it does not recognise; the cooldown read from the tooltip line's right text by default, from `GetSpellBaseCooldown` only once T87's Forever report shows it answers plain (`MD.API.BASE_CD_READS`); `Book` entries carry `targets`, `cooldown`, `lockout`; `IntervalFor = max(cast, GCD, cooldown)`; words: `x up to 5 targets`, `every 10 s`, `up to 1.75x if 3 are hurt` stated as an upper bound, **never multiplied silently** (decision 12) | parse / book / tip suites on committed priest, shaman and paladin books (`tools/data/books/*`, extracts of the CC BY talentsforever export with attribution); a per-class coverage count in `expected-counts.json` | the cooldown line shape and `GetSpellBaseCooldown` on Forever (T87's probe); tick periods of Renew / Riptide / Wild Growth via `/st measure` on an alt |
| **P2 A generic Forever kit** (N2 seams, N3 kit) | families from the book by **shape**, not name (`FAMILY_KEY` derived; `Stream_Forever` reads the same derivation); HoT slots by the kit's profile (2.1), never the logged-in player's; `KitEntryFor[type]`; new types `group` (`targets = "party"`), `chain` (`jumps`, `falloff`), `selfAndTarget`; `channel` lands its ticks; Wild Growth in with uniform ticks marked VERIFY (never an invented curve); the solver over the kit's families with group sums under 4.5's stated assumptions; scenario attribution accepting N same-instant claims; the threshold rules stay the druid's, every other class gets the solver strategies (which beat the rules: 44% less mana for the same deaths) | `kitcheck` (a paladin / shaman / priest book becomes a valid kit), `solvercheck` properties (PoH beats Greater Heal only with 3+ hurt; Chain Heal's falloff; causality unchanged), `scenariocheck` (group claims), `practiceforever` with a non-druid kit, a new `classcoach` suite (a synthetic fight per class through the eight gates) | one recorded pull from a non-druid healer through the gates (gate 8 "heals attributed" tells whether group attribution is right) |
| **P3 Absorbs** (N5, after the probe) | a shield state per target eaten first in `Damage`, expiry, the Weakened Soul lockout (`S.lock[ti][family]`); the recorder storing the absorbed part per hit (TBC keeps CLEU's `absorbed`; Forever: what `UNIT_COMBAT` shows is unknown) | `reccheck` (a partial absorb recorded), `solvercheck` (a shield before a predicted hit) | **probe first**: `UNIT_COMBAT` on a hit into a shield, `UnitGetTotalAbsorbs` secret or not. Without an answer a PW:S replay is not trustworthy and the gates must say so |
| **P4 Mana sources and returns** (N4) | an aura-driven source table (Innervate, Mana Tide, Mana Spring, Blessing of Wisdom) with rates from the spell's own text (two parse shapes: "restores N mana every P sec"; Innervate's "increases ... Mana regeneration by N%" applied to the pool's last plain regen reading) feeding `Engine/ManaModel.lua`. **The aura on the player is the source, whoever cast it**: an Innervate from another druid counts exactly like a self-cast; a self-cast on someone else costs its mana and adds nothing to our pool -- **the druid's Forever clock stops reading low during Innervate**; expected-value refunds (Illumination, Water Shield, Clearcasting) labelled "assumed"; TBC's `ManaCooldowns` priest / shaman / paladin stubs valued from text | `clockcheck`, `parsecheck`, a new `manasources` suite | Forever: `UnitPower` is secret, so a refund cannot be measured directly; it stays "assumed" until a long-fight drift test against the drawn bar |
| **P5 TBC other classes** (N5, decision 8) | base values read from the TBC client's static tooltips through `Spells/Parse.lua` (put on the TBC TOC), a per-class VERIFY rule table (coefficients by shape, talents), the kit through the same `Kit.Check`; the druid keeps `Data/SpellData.lua` | WCL fits on public TBC Anniversary parses (`tools/wclconvert.py` / `wclcheckkit.lua --fit` with a class argument): if three families of one class agree on one +healing, the rules hold | `/md verify`, `/md regentest`, `/md calibrate` by someone of that class |
| **P6 Non-healer extras** (N5) | either-or spells keep both halves (Holy Shock, Holy Nova, Penance) and show the one matching the player's role; the list seed by role (a shadow priest no longer starts with heals, `Tabs.lua:170-176`); caster mana sources on the clock (Evocation, mana gems, Life Tap) | `tabscheck`, `bookcheck`, `tipcheck` | none required |

### 4.3 Class order (decision 7)

The kit is built **by shape**, so every class gets what its shapes allow at once; a class is
granted `coach` / `practice` when its committed book fixture passes `classcoach`. Fixture order:
**Paladin** (direct heals plus a cooldown: nothing new), **Shaman** (adds `chain`), **Priest**
(adds `group` and `selfAndTarget`; PW:S waits for P3, so a priest is coached without shields and
the card says so). The druid gains Tranquility and Wild Growth in P2.

### 4.4 Gates (S1's second step, task T99)

`isDruid` is read 29 times in 15 shipped files (`grep -rn isDruid --include=*.lua`, tools left
out): 23 capability gates in 10 files and six reads in five files that stay. They split three
ways.

| Kind | Files (line of the first read) | What happens |
|---|---|---|
| **Capability gates** (T99) | `UI/Dashboard_Review.lua` 610-863, `UI/ReplayWindow.lua` 1755 / 1980 / 2388, `UI/PracticePanel.lua` 523, `Engine/ReviewCommands.lua` 168, `UI/SimWindow.lua` 75 / 262, `UI/Dashboard.lua` 58 / 142 / 287, `UI/SpellTooltip.lua` 57, `UI/Advisor.lua` 58 / 85, `UI/Summary.lua` 496, `Diagnostics_TBC.lua` 227 | `MD.Profile:Can(cap)`; the druid answers true wherever it did |
| **Druid by design** (stay, each with a one-line comment saying why; no task edits their logic) | `Core.lua` (defines `MD.player.isDruid`: a fact), `Core_TBC.lua:99` (`InTreeForm`: Tree of Life is a druid form), `Data/SpellData.lua:193` (druid talent cost modifiers on the druid's own table; `SpellData` changes only from a measurement) | unchanged; the comment lands with T99 only in `Core_TBC.lua` (SpellData's line is described in `capscheck`'s allow-list instead, so the frozen file is not touched) |
| **Druid until TBC other classes** (T111) | `Engine/RankMath.lua:555` (`Compute` over the druid's `SpellData`), `Spells/Families_TBC.lua:41` (TBC's book from `SpellData`) | stay until T111, which owns both and turns them into `Can("rankTable")` with a TBC profile's own source |

`capscheck` scans the shipped sources and fails on any `isDruid` read outside the six listed as
staying (`Core.lua`'s two included). The druid answers true wherever it did, so `slashcheck`, `verifycheck`, `reviewui` and
`practiceui` stay byte-identical. "Coaching is Druid-only in v1." becomes
`Coaching: not modelled for <Class> yet` -- a wording change for non-druids only (DECISIONS line).
On Forever `Can("coach")` asks the `KitLive` provider (2.1); with the Replay module off it answers
`false, "module"` and the caller keeps the module's existing placeholder.

### 4.5 What the solver assumes for heals that reach several targets

No positions are recorded on either line (the recorder keeps health, not coordinates), so a group
or bounce heal's reach is an assumption. Every one below is **optimistic** (it can only overstate
the heal), marked **VERIFY** in the profile, and stated on the coach card whenever the plan or the
recording casts such a spell: `group heals assume everyone in range (no positions recorded): an
upper bound`.

| Spell shape | Who it reaches in the engine | Why this is causal |
|---|---|---|
| `group` (Prayer of Healing, Holy Nova, Tranquility, Wild Growth) | every **living tracked member of the caster's party** (the five-man party; in a raid, the caster's recorded subgroup), each healed by the text's amount; Holy Nova's 10 yd and Wild Growth's "up to 5 / 6" are treated as "all of them" | the set is the roster at the cast, known in the present |
| `chain` (Chain Heal) | the primary target, then up to `jumps` more: **the most injured tracked members at the cast moment** (missing health now, ties by roster order), each `falloff` times the last (1, 0.5, 0.25) | reads only health now; no future damage, no positions |
| `selfAndTarget` (Binding Heal) | the target and the caster | fixed by the cast |
| replayed as recorded (Prayer of Mending, Lightwell, totems, Vampiric Embrace) | whoever the recording says | the plan cannot choose them (principle 8) |

Gate 8 ("heals attributed") is the only measurement of these assumptions: a non-druid recording
whose group heals the gate cannot attribute is reported, never coached silently (in-game check 11).
The client's real jump rule (`R-classes` 142: "the next most-injured tracked member", unverified)
and every range stay VERIFY until a recording shows otherwise; no range number is typed in.

---

## 5. (B) UI styles

### 5.1 The styles and their values

All four keep spec 4.3's metrics, `UI.Pitch`, the font sizes and every layout. Only the columns
below differ. The replay's unit frames (the author's Cell layout), the debug console's category
legend, `good` / `bad` / `mana` meaning and the cast family colours are exempt under every style.

**Flat** (default; today's `UI/Theme_Flat.lua` exactly)

| Token / role | Value |
|---|---|
| accent | the class colour |
| bg / pane / nav | `#161616` a 0.96 / `#1C1C1C` / `#1D1D1D` |
| border / line / rule | black 1 px (`UI.px`) / `#2A2A2A` / accent a 0.6 |
| rowAlt / hover / selected / suggested | white a 0.03 / accent a 0.12 / accent a 0.28 + 2-px bar / accent a 0.10 + 2-px bar |
| text / label / muted / disabled | `FFFFFF` / `B3B3B3` / `7A7A7A` / `4D4D4D`; mana `4D99FF`, good `5CCB6E`, bad `E0605A` |
| fonts | Friz text, Arial Narrow numbers, no outline, shadow (1, -1) |
| tooltip / clock | SpellTuner's flat skin / `bg` fill + 1-px black edge, 4-px bar on black |

**Ellesmere** (clone everywhere; *follows* EllesmereUI on Forever when it is loaded)

| Token / role | Value (source `R-styles` 4.2, EllesmereUI 9.3.4) |
|---|---|
| accent | following: `S.GetAccentColor()`; clone: bronze `#DCA77F` on Forever, teal `#0CD29D` on TBC (EllesmereUI's defaults); "Use my class colour" offered |
| bg / pane / nav | `0.05, 0.07, 0.09` a 0.96 / same a 1 / same + black a 0.10 (following: `S.GetPanelColor()`) |
| border | `strips` painter: white a 0.05 on panes, a 0.10 on windows |
| line / rule | white a 0.06 / the accent a 1 |
| rowAlt / hover / selected | black a 0.20 / white a 0.08 / white a 0.04 + the 2-px accent bar |
| button | `0.061, 0.095, 0.120` a 0.6 (hover 0.65); edge white a 0.30 (0.45); label white a 0.55 (0.70) |
| field | `0.10, 0.12, 0.16`; dropdown `0.075, 0.113, 0.141` a 0.9 |
| scroll | track white a 0.10, thumb white a 0.25, 5 px (fits the rail's 5-px lane) |
| check / slider fill | accent a 0.75 |
| text | `text` white; `label` white a 0.53; `muted` white a 0.41 -- alpha on white, **pre-blended** into hex against `bg` (tokens carry rgb + hex; a code cannot hold alpha) |
| fonts | following: `S.GetFont()` (Expressway, EllesmereUI's file; SpellTuner ships none); clone: Arial Narrow for text and numbers |
| tooltip | `0.067` a 0.92, edge white a 0.18, 1 px |
| clock | `strips` edge white a 0.10 on the panel colour; bar fill accent a 0.75 |

**Modern** (retail-like, dark; flat fills shaped like retail's Settings, atlases optional)

| Token / role | Value |
|---|---|
| accent | gold `1, 0.82, 0` for titles and selection (retail's category gold); "Use my class colour" offered |
| bg / pane / nav | `#111111` a 0.97 / `#1A1A1A` / `#151515` |
| border | `0.25` grey, 1 px |
| header | black a 0.5 strip inside the existing 20-px header (no geometry change) |
| hover / selected | white a 0.06 / gold a 0.18 + a 2-px gold bar on the left; `Options_List_Hover` / `_Active` atlases only where `MD.API.AtlasInfo` answers (Forever VERIFY, absent on TBC) |
| button | `#2A2A2A` / hover `#3A3A3A`, edge `0.35` grey; `128-RedButton-*` 3-slice only if present (Forever may draw its bronze -c60 art instead: off until seen) |
| close | flat `x` white a 0.8, red on hover |
| text | `text` white, `label` `CCCCCC`, `muted` `8C8C8C`, `accent` gold |
| fonts | Friz text, Arial Narrow numbers, no outline |
| tooltip | SpellTuner's skin by default, "the game's own" as a setting (decision 6) |
| clock | `#111111` a 0.9 with the 0.25 edge; bar the mana blue |

**Classic** (Blizzard 2004-2008 dialog; last, behind mockup M7 and the art probe)

| Token / role | Value |
|---|---|
| accent | `NORMAL_FONT_COLOR` gold `ffd100` (decision 2: "no gold" is the Flat style's rule) |
| window | `backdrop` on an outset child (~8): `UI-DialogBox-Background` tiled 32 + `UI-DialogBox-Border` edge 32, insets 11/12/12/11 |
| header | `plaque` from `UI-DialogBox-Header` centred over the 20-px header strip, gold title |
| nav / pane / cards | `UI-Tooltip-Border` edge 16, insets 5, fill `0.15` a 0.9, border `0.4` grey |
| button | `slice3` from `UI-Panel-Button-Up/Down/Highlight/Disabled` (texcoords VERIFY); gold label, white on hover; at 18-px small buttons the 22-px art squashes: mockup decides |
| check / close | `UI-CheckBox-*` drawn 22-24 inside the existing click area / `UI-Panel-MinimizeButton-*` |
| list hover | `UI-QuestTitleHighlight` ADD; no accent bar |
| scroll | flat, gold-tinted thumb (the 16-px art would change the 5-px lane) |
| statusbar | `Interface\TargetingFrame\UI-StatusBar` |
| text | accent / label gold `ffd100`, text white, muted / disabled `808080`, good `1aff1a`, bad `ff1a1a` |
| fonts | Friz everywhere, Arial Narrow numbers |
| tooltip | the game's own (`Tip:Skin` returns false and the NineSlice keeps its alpha) |
| clock | `UI-Tooltip-Border` edge 12, insets 3, outset 3, fill black a 0.8; `UI-StatusBar` bar |

Deferred: a parchment variant of Classic (dark text on `QuestBG`; the achievement parchment is a
Wrath file, absent on TBC) and a "Blizzard native art" variant (`NineSliceUtil` layouts draw
classic metal on TBC and bronze -c60 on Forever: not a retail look, and unpredictable).

### 5.2 Painters (recipe kinds)

| Kind | What | Used by |
|---|---|---|
| `pixel` | today's `PixelBackdrop` | Flat, Modern, Ellesmere |
| `strips` | four textures, so the edge alpha differs from the fill (as `Tip.lua:184-195`) | Ellesmere |
| `atlas` | `SetAtlas(name)` only after `MD.API.AtlasInfo(name)` answers | Modern's optional pieces |
| `backdrop` | `SetBackdrop{...}` on an outset child at frame level -1, its anchors pixel-snapped, its 32-unit edge not | Classic |
| `plaque`, `slice3`, `files` | three header textures; three-slice buttons swapped per state; Normal/Pushed/Highlight/Checked files | Classic |
| `native` | do nothing; give the game's art its alpha back | Classic tooltips, Modern's "game tooltip" setting |

A role whose `needs` art is missing **falls back to Flat's recipe for that role** and is listed in
`/st dump` (`style: classic; fell back: button (UI-Panel-Button-Up absent)`).

### 5.3 Presence checks (adapter) and the probe

- `MD.API.AtlasInfo(name)` -> a copy of `C_Texture.GetAtlasInfo` (`file`, `width`, `height`) or
  nil; `MD.API.FileID(path)` -> `GetFileIDFromPath`. Both in the 69893 baseline; on TBC both
  VERIFY (ElvUI guards the first). With no answer, assume the plain `Interface\...` files Blizzard's
  own `BACKDROP_*` presets use exist, and refuse every atlas.
- The probe gains `== art`: one line per path and atlas any style names
  (`file <path> id=<n|absent>`, `atlas <name> file=<id> <w>x<h> | absent`), **on both clients**
  -- which needs the probe on the TBC TOC, a change T87 makes (decision 22: `/md probe` and
  `/st probe` on TBC, `probecheck` run under the tbc profile with no `C_Secrets`, every
  Forever-only section reporting itself `absent`). Every VERIFY above becomes a report line, re-run
  on each Forever build (the atlas map moves).

### 5.4 Settings and command

- A **Look** dropdown at the top of APPEARANCE (Forever `UI/Dashboard_Forever.lua`
  `BuildAppearanceSection`; TBC `UI/Options_General.lua` `CreateWindowsPane`): Flat / Ellesmere
  (`Ellesmere (following EllesmereUI)` while following) / Modern / Classic, and one check **Use my
  class colour** that overrides any style's accent. Selecting repaints at once; the open Settings
  window is its own preview.
- `/st ui style <flat|ellesmere|modern|classic>` registered with `MD:AddSubcommand("ui", "style",
  ...)` by `UI/Styles.lua` (2.5), so `/st ui reset` keeps working whatever the load order; on TBC
  this creates `/md ui style` and T94 re-bases `slashcheck/tbc`. An unknown name is refused with the
  list.
- `/st dump` gains `style: <key> (accent <class|style>) fell back: <roles>` through
  `MD:AddDumpLine("style", ...)` (Forever; TBC has no dump).

### 5.5 Following EllesmereUI (Forever only)

- `Integrations/EllesmereUI_Forever.lua` registers once with
  `EllesmereUI.RegisterSkin("SpellTuner", function(S) MD.EUISkin = S; S.OnLooksChanged(...) end)`.
  The callback runs at EllesmereUI's `PLAYER_LOGIN` inside a `pcall`, or never (the user turned
  third-party skinning off for SpellTuner, BlizzardSkin is disabled, or EllesmereUI is absent).
- The Ellesmere style reads `S.GetAccentColor()`, `S.GetPanelColor()`, `S.GetFont()` and repaints on
  `EUI_LOOKS_CHANGED`. Without `S` it tries the parent's `EllesmereUI.GetAccentColor()` /
  `GetFontPath()` (guarded by `type(...) == "function"`), else the clone.
- **SpellTuner's frames are never handed to `S.Shell` / `S.Panel` / `S.Button`**: those fade every
  texture region to alpha 0 (`WindowEngine.lua:412-429`), which would hide the clock's bar backing,
  and two painters would fight over one frame (decision 5).

---

## 6. (C) The EllesmereUI integration

### 6.1 What EllesmereUI offers, and what it does not

| Surface | Use | Evidence |
|---|---|---|
| DataBars' **Broker Plugin** block (`ldb`): shows any LibDataBroker-1.1 data object | **yes**: the clock and regen brokers | `EllesmereUIDataBars/Blocks/LDB.lua:29-409`; the suite ships LDB in its parent (`EllesmereUIDataBars.lua:3134-3146`) |
| `EllesmereUI.RegisterSkin` + getters | **yes**: the Ellesmere style's follow (5.5) | `SKINNING_API.md`, apiVersion 2, additive-only |
| `EllesmereUI:RegisterUnlockElements` | **yes**: a mover for the clock in `/unlock` | `EUI_UnlockMode.lua:1-85`, whitelist `EllesmereUI.lua:2280-2377` |
| Minimap button collector | **compatible**: it already takes `SpellTunerMinimapButton`; two fixes so it stays collected | `EllesmereUIMinimap.lua:1282-1330`, `:474-532` |
| DataBars block registry, options sidebar (`RegisterModule` whitelist), profiles (`ADDON_DB_MAP`), `ManaRegenSpark` | **no**: private or whitelisted; never read or written | `R-ellesmere` 2.5 |

EllesmereUI already draws a 5SR spark and a cost-prediction segment on its own mana bars; neither
projects time to OOM, so the broker adds what EllesmereUI lacks without drawing over it.

### 6.2 The brokers (`Integrations/Surface_LDB.lua`, both main TOCs)

| Object | `type` | `text` (ASCII) | `icon` / tint | Click |
|---|---|---|---|---|
| `SpellTuner` | data source | the clock feed's text with the user's clock settings, e.g. `~OOM 1:20  rest 2:10` (Forever), `OOM 1:20 v` (TBC); `compact` setting drops the label/rest | `Spell_Shadow_Manaburn` (the minimap button's); **`iconR/G/B` carries the tone** because DataBars strips colour codes by default: `mana` for full / ooc, muted for warm-up / hold, warn amber over 60 s... crit red at or under 20 s | left: the window; right: Settings; out of combat only |
| `SpellTuner Regen` | data source | `Regen 123`, `Regen 123 (5SR)`; on Forever in combat `Regen ~123` (the pool's last plain reading); `Regen --` before a reading | same icon; amber inside the 5SR | same |

- **Created at `MD_READY`** when `LibStub` answers `LibDataBroker-1.1` (every addon has loaded by
  `PLAYER_LOGIN`); EllesmereUI's block also binds a late object through
  `LibDataBroker_DataObjectCreated`, so order does not matter. `NewDataObject` returns nil for a
  duplicate, so a late reader finds the existing object with `GetDataObjectByName`.
- **Updated from `MD:OnTick`** (no ticker of our own); the library drops equal writes, so DataBars
  repaints only on a real change. **The text must read well without colour** -- it does, because
  the clock's meaning is in its words and marks.
- **Tooltip through `OnTooltipShow(tt)`** (DataBars anchors and flips it; EllesmereUI's tooltip
  skin applies), filled by `MD.Tip:Render` with the clock feed's lines plus `Left-click: open the
  window` / `Right-click: Settings` / `(not in combat)`. Never `OnEnter`.
- **Width:** broker text has no fixed width; TESTING tells the user to set the block's Max Width
  (~120 px), and the `compact` option exists for a narrow bar.
- **On TBC the same file** publishes to whatever broker display is there (Titan Panel,
  ChocolateBar, ElvUI's own "Data Broker" list). With ElvUI loaded, ElvUI lists both its native
  `SpellTuner` datatext and the wrapped `LDB: SpellTuner`; Settings says to pick the native one
  (decision 19).
- **ElvUI's native surface stays TBC-only** until ElvUI is seen running on Forever (its
  `ElvUI_Mainline.toc` says 120100; not installed on the author's Forever client). The broker covers
  ElvUI on Forever anyway.

### 6.3 The mover and the minimap button (`Integrations/EllesmereUI_Forever.lua`, Forever TOCs only)

- One element `SpellTuner_Clock` (label "SpellTuner clock", group "SpellTuner"), with `getFrame`,
  `getSize`, `savePos` writing the clock's own stored point (EllesmereUI hands CENTER/CENTER on
  UIParent, the same shape as `db.clock.point`), `loadPos`, `clearPos` (the clock's reset),
  `applyPos` (the clock's `ApplyPoint`, exposed by T93), `isHidden` (the clock switched off),
  `noResize`. A `RegisterUnlockModeListener` shows the clock's 60-s preview while `/unlock` is open
  (a clock hidden at full mana could otherwise only be placed as an empty mover) and ends it after.
  The mover never calls `Show` / `Hide` -- the preview goes through the clock's own owner.
- `UI/MinimapButton.lua` (shared; no-ops without EllesmereUI): `Reposition()` and the angle drag
  return when the button's parent is no longer `Minimap` (collected), and the icon is kept as
  `btn.icon`, anchored CENTER, so the collector finds it by name. If the in-game check shows the
  button is created after EllesmereUI's scans, the frame moves to SpellTuner's own `ADDON_LOADED`
  and only its hide setting and position wait for `MD_READY`. `minimapcheck`'s TBC golden stays
  byte-identical.
- Defaults declared by the file that reads them:
  `MD:RegisterDefaults({ feeds = { ldb = true, elvui = true, compact = false }, eui = { unlock = true } })`.
- **Settings -> General -> INTEGRATIONS** (both lines): what was found, one line each
  (`EllesmereUI 9.3.4: brokers SpellTuner + SpellTuner Regen; mover SpellTuner clock`,
  `ElvUI: 2 datatexts`, `Broker: 2 objects`, `none found`), the broker check, the compact check, the
  mover check (Forever, EllesmereUI loaded). `/st dump` gets the same line through
  `MD:AddDumpLine("integrations", ...)`, with the EllesmereUI version read from its TOC
  (`MD.API.AddOnMetadata`) and the skin facade's `apiVersion`:
  `integrations: EllesmereUI 9.3.4 (tested 9.3.4), skin apiVersion 2, brokers SpellTuner +
  SpellTuner Regen, mover SpellTuner_Clock`.
- **Version guard.** The integration records the version it was built against
  (`TESTED_EUI = "9.3.4"`). Another version still runs (every call is guarded), but the
  INTEGRATIONS line and the dump say `(tested 9.3.4)` beside it so a report shows the drift. The
  skin follow uses the getters only when `S.apiVersion == 2` (the documented, additive-only
  contract); any other value falls back to the clone and says `skin apiVersion <n>: not followed`.
- **Unlock fields.** The mover passes only fields on EllesmereUI's whitelist
  (`EllesmereUI.lua:2280-2377`; anything else is dropped silently, `R-ellesmere` 5) and checks each
  function it calls with `type(...) == "function"`; a missing `RegisterUnlockElements` leaves the
  clock movable by its own drag and says `mover: not offered by this EllesmereUI`.
- `## OptionalDeps: EllesmereUI` on both Forever TOCs (TBC's keeps `ElvUI`).

### 6.4 It never

reads or writes `EllesmereUI._ModuleNS`, `EllesmereUIDataBarsDB` or `EllesmereUIDB`; calls
`RegisterModule`; attaches to `ManaRegenSpark`; registers events on a frame of its own (the tick
and the callbacks go through `MD:On` / `MD:OnTick`, apicheck rule 9); moves a frame in combat; puts
a colour code, a non-ASCII glyph or a bare pipe in broker text.

---

## 7. (D) The clock

### 7.1 First, six Forever gaps (visible without any customisation)

| # | Gap | Fix |
|---|---|---|
| F1 | The Forever clock is monochrome: `~OOM 0:10` is white | tones from the face on both lines (crit under 20 s, warn under 60 s, on the 5-s-rounded value) |
| F2 | T82 centred the text, against DECISIONS:116 ("centred text slides when the digit count changes") | three font strings -- label, value + arrow, secondary -- at fixed positions; only the value's own digits move; the value in the kit's number font (decision 14) |
| F3 | A Forever warrior or rogue sees `~OOM ...` in every fight (no `usesMana` test) | `manaUsersOnly` in the shared show rule |
| F4 | The Forever clock always takes the mouse | `clickThrough` on both lines (TBC's `widgetTooltip == false`, extended) |
| F5 | Alerts and the <30 s moment never pulse the Forever clock | the renderer owns the pulse; both lines expose `MD:PulseWidget` |
| F6 | The rest segment cannot be turned off on Forever | `show.rest` on both lines |

### 7.2 Layouts (all draw the same face)

```
L1 Line (default; today's, steadier)        L2 Compact               L3 Bar
+--------------------------------+          +-----------+            +---------------------------------------+
| OOM  1:20 v   rest 2:10        |          | OOM       |            | OOM [##################......] 1:20 v |
|  [=========.......]            |          |   1:20 v  |            +---------------------------------------+
+--------------------------------+          +-----------+              ^ spark: 5SR (yellow, 5 s), then the 2 s tick
  180 x 30                                    72 x 36, value 20-24 pt    200 x 18, text inside the bar

L4 Ring (wave N4)                           L5 Two lines (only on the author's yes, decision 13)
     . - - .                                +------------------------------+
  .'  OOM   '.   56-96 px, 24 segments      |  OOM 1:20 v                  |
 :   1:20 v   :  of UI.whiteTexture         |  rest 2:10   5SR 3.1   92mp5 |
  '.        .'   (SetRotation, no media)    +------------------------------+
     ' - - '
```

- **Bar sources** (L1 / L3 / L4): `pool` (TBC plain; Forever drawn through `DrawUnitPower`, never
  read -- **not available for the ring on Forever**), `model` (Forever, `~`, plain), `time`
  (`tto / horizon`, 180 s default), `fsr` (TBC today's; Forever from the model's last priced
  spend), `none`. The **spark** (`fsr`: ElvUI's yellow 5-s countdown, then the white 2-s tick)
  can sit on any source, so "pool + spark" means the same on both lines (decision 15). On Forever's
  `pool` the bar's colour is the *modelled* tone -- the colour says what the model thinks, the fill
  shows what the game has.
- **Text in a layout** comes from `ClockFace` per-segment helpers; `LineString` stays the L1 /
  datatext string. The ring needs `SetRotation` on both clients (UNVERIFIED; segments at least
  3 px, the stub gets a recording no-op).
- **Style presets**: the active UI style's `clock` role is the default look (Flat today's panel;
  Ellesmere strips + accent bar; Modern dark panel + mana blue; Classic tooltip border +
  `UI-StatusBar`). A "Text only" preset (L2, 20 pt, thick outline, no panel) is the WeakAuras look.

### 7.3 The customization surface

**Storage, sparse** (`MD:RegisterDefaults` fills every leaf, so a default that "follows the style"
cannot be a registered leaf):

```lua
db.clockLook = { layout = "line", over = {} }   -- declared by UI/ClockView.lua on both TOCs
-- resolved look = layout defaults <- the style's clock role <- over ; "Reset to style" wipes `over`
```

`over` is read only through the resolver, never as `MD.db.clockLook.over.<key>` in a pane, so
`tools/defaultscheck.lua`'s source scan (its check 4) finds `clockLook`, which has its default;
the new top-level keys of this spec (`ui.style`, `clockLook`, `feeds`, `eui`) each move
`defaultscheck`'s counts on both flavours, reported by the task that registers them (11).

Existing keys stay where they are in phase 1 and are read through the resolved look (TBC
`db.pos`, `locked`, `showRest`, `showCooldown`, `widgetTooltip`, `oomConfidence`; Forever
`db.clock.{shown, locked, point}`). Unifying position / lock storage (one `UI/Clock.lua`, a
one-time adoption like `ManaDemonDB`) is a later, not-scheduled step.

| Group | Settings (default) |
|---|---|
| Text | font face (kit / Friz / Arial Narrow / Skurri / Morpheus: built-in only), size 8-32 (13 L1, 22 L2), outline none / outline / thick / monochrome (Cell's tuple), shadow (on), numbers same face / number face, align (left), time `1:20` / `80s` / `1m20` (format only; the step ladder decides precision), labels `OOM`/`FULL` / `out`/`full` / none (off by default; Forever keeps its `~` even with no label) |
| Colours | tones crit `ff4444`, warn `ffaa33`, normal white, good `33ff66`, muted `999999`, mana `4fa9f0` (today's `TTO.lua:330-335`; Forever adopts them), per-state overrides (full, warm-up, hold, ooc), thresholds warn 60 s / crit 20 s (moving the latch's crossings with them), bar colour by tone / class / fixed, bar background, border |
| Frame | background on/off + colour + alpha, border on/off + colour, width / height (layout minimums), the clock's own scale 50-200 %, alpha in combat / out of combat, strata LOW / MEDIUM |
| Bar | source, spark, texture (flat / `UI-StatusBar` / `Raid-Bar-Hp-Fill`: Forever VERIFY), height 2-24 (4), position below / above / behind, horizon 60-600 s, reverse fill |
| Show | segments: rest (both), cd `inn 2:10` (TBC), arrow (TBC; Forever off until an optional render-only latch), mp5 (Forever `~`), pct (Forever `~78%`, model only), 5SR `5SR 3.1`; L1 keeps "at most one secondary segment" |
| When | in combat always / never; out of combat low (under 90 %, hidden over 95 %: today's) / always / never; mana users only (on); flash under 30 s once per fight (on); locked; click-through; tooltip; left-click opens the window (out of combat only on both lines, decision 17) |

`MD.Visibility.Want(pct, shown, inCombat, unlocked, rule)` takes the rule; with the default rule
it is exactly today's (`UI/Visibility.lua:27-33`).

Colours: phase 1 is a swatch row (the tones, the style's tokens, the class colour, 8 fixed
colours; no client call). "Custom..." through `MD.API.PickColor` (`ColorPickerFrame`) waits for
probe Q-clock-3 on both clients.

### 7.4 Settings -> Clock (both lines), with a live preview

```
+-- Settings > Clock -------------------------------------------------------------+
| PREVIEW                                                      ground: [dark][light]|
|   +------------------------------------------------------------------------+     |
|   |                     OOM  1:20 v   rest 2:10                            |     |
|   |                    [==============........]                            |     |
|   +------------------------------------------------------------------------+     |
|   state: (Live) [OOM] [OOM <20s] [bound] [hold] [warm-up] [FULL] [rest] [ooc]     |
|                                                                                  |
| LAYOUT   [ Line ] [ Compact ] [ Bar ] [ Ring ]                  [Reset to style]  |
|                                                                                  |
| +-[Text]-[Colours]-[Frame]-[Bar]-[Show]-[When]---------------------------------+ |
| | Font      [Kit font        v]   Size [--o------] 13   Outline [None v]         | |
| | Shadow    [x]                   Numbers [Number face v]   Align [Left v]       | |
| | Time      [1:20 v]              Labels [OOM / FULL v]                          | |
| +------------------------------------------------------------------------------+ |
|                                    [Show on screen 60 s]   [Lock]  [Reset place] |
+----------------------------------------------------------------------------------+
```

- A new view `clock` in the Settings group: TBC `general, clock, about`; Forever
  `general, clock, modules, about`. TBC's "OOM Widget" pane and Forever's MANA CLOCK keep the
  everyday switches (Show, Lock, Reset position, Show now) and gain `Customise...`.
- **The preview is a separate frame** built by `MD.ClockView.Build` inside the pane, never the widget,
  so it never touches the single visibility owner. *Live* paints the real face each tick; the chips
  paint `ClockFace.SAMPLES`, **the same table the suite renders**, so what the author sees is what
  is tested. The level-3 box is `UI.CreateNavBox`; every control exists in the kit except the
  swatch row (local to `UI/ClockSettings.lua`).
- A control writes `db.clockLook.over.<key>` and fires `CLOCK_LOOK`; the widget and the preview
  rebuild; scale applies on mouse-up.
- Commands: `/st clock layout line|compact|bar|ring`, `/st clock look reset`,
  `/st clock preview`, each `MD:AddSubcommand("clock", ...)` from `UI/ClockSettings.lua` (2.5), so
  Forever's `/st clock` and `/st clock lock` keep their meaning. TBC has no `clock` verb today: the
  subs create `/md clock ...` and T102 re-bases `slashcheck/tbc` with a DECISIONS line.

### 7.5 Probe questions for the clock

| ID | Question | Why |
|---|---|---|
| Q-clock-1 | Does `UnitPowerPercent("player", 0, false, C_CurveUtil.CreateColorCurve(...))` return a colour `SetVertexColor` accepts, plain or secret? | colour the real-pool bar by its real level without reading it |
| Q-clock-2 | Does `fs:SetText(UnitPowerPercent("player", 0))` display a number, and does `GetText()` read back secret? | a real `%` as text on Forever (off until answered) |
| Q-clock-3 | Does `ColorPickerFrame:SetupColorPickerAndShow` exist on TBC 20506 and Forever? | the Custom... colour |
| Q-clock-4 | Do `UI-StatusBar`, `Raid-Bar-Hp-Fill` and the four `Fonts\*` load on Forever; does `Texture:SetRotation` work on both? | bar textures, fonts, the ring |

---

## 8. Forever-only, both lines, TBC

| Change | Forever | TBC | Note |
|---|---|---|---|
| S1 profiles, capability gates | yes | yes | byte-identical for the druid; wording for non-druids only |
| Solver cooldown fix, cooldowns per family | yes | yes | changes the druid coach (Swiftmend): DECISIONS |
| The probe | yes (today) | yes, from T87 (`/md probe`) | decision 22; TBC's report has only the sections that answer there |
| Subcommands, dump lines (S0) | yes | subcommands yes (new `/md ui`, `/md clock`); no dump on TBC | |
| Parse fixes, targets, cooldowns in the book / tooltip / Spells view | yes | no (TBC's tooltip is druid-only from `SpellData`) | `Spells/Parse.lua` reaches TBC only in P5 |
| Generic kit, new kit types, non-druid coaching | yes | engine code shared; no TBC non-druid kit until P5 | |
| Channel landing (Tranquility) | yes | yes | changes replays with a Tranquility: DECISIONS |
| Absorbs | after the probe | CLEU `absorbed` recorded | |
| Mana sources (Innervate in the modelled pool) | yes | stubs valued from text | |
| Styles: Flat, Ellesmere (clone), Modern, Classic | yes | yes | Ellesmere **follows** only on Forever |
| Feeds, ElvUI surface | feeds yes; ElvUI native only once seen running | yes | |
| LDB brokers | yes (EllesmereUI DataBars) | yes (Titan, ElvUI's broker list) | borrowed library |
| EllesmereUI mover, skin follow, minimap collector fixes | yes | never (EllesmereUI refuses TBC) | the minimap fixes are no-ops there |
| Clock face, F2, layouts, Settings -> Clock | yes | yes | F2 and the left-click rule change TBC: DECISIONS |
| Clock F1, F3-F6 | yes (gaps) | already true | |

---

## 9. DECISIONS FOR THE AUTHOR

Each has a recommendation; the tasks implement the recommendation unless you say otherwise.

1. **Which styles first.** (a) Flat + Ellesmere + Modern now, Classic after its mockup and the art
   probe; (b) all four at once; (c) Flat + one new style only. *Recommend (a)*: Ellesmere and Modern
   are flat fills (low risk, one data file each); Classic needs four new painters and is the one
   whose look only a screenshot can judge.
2. **Gold.** Spec 4.1 removed Blizzard gold from every window. *Recommend*: "no gold" becomes the
   **Flat** style's rule; Modern and Classic use gold as their accent.
3. **Accent per style.** *Recommend*: each style has its own default accent (class colour for Flat,
   gold for Modern and Classic, EllesmereUI's for Ellesmere) and one **Use my class colour** check
   overrides any of them. Alternative: always the class colour.
4. **Switching styles.** *Recommend live* (registered regions, fonts, tooltips repaint at once) with
   `Some windows finish changing after a reload [Reload]` until T107's conversions reach 100 %.
   Alternative: save and reload only (ElvUI's and Cell's convention; less work).
5. **Ellesmere on Forever.** *Recommend*: follow EllesmereUI's accent, panel colour and font through
   its documented getters when it is loaded; clone otherwise; **never** hand SpellTuner's frames to
   its `Shell` / `Panel` / `Button` (they fade our textures).
6. **Tooltips under Classic / Modern.** *Recommend*: the game's own tooltip under Classic; a setting
   under Modern, defaulting to SpellTuner's skin.
7. **Classes, and in which order.** *Recommend*: the reading fixes for every class at once (P1);
   the kit by shape, coaching granted per class as its fixture passes, **Paladin -> Shaman -> Priest**
   (Priest without shields until the absorb probe). Alternative: Priest first (the most common
   healer, but it needs `group`, `selfAndTarget` and shields).
8. **TBC and other classes.** (a) Never; (b) rank tables and tooltips only, from the client's own
   tooltips + VERIFY rules + WCL fits, after the Forever kit; (c) full coaching too. *Recommend (b)*,
   scheduled last (N5), and only coaching on TBC for the druid.
9. **Non-healers.** *Recommend*: tooltip, rail and clock only (they work today), plus the misread
   fixes, either-or damage halves, seeding the list by role and caster mana sources (Evocation,
   gems, Life Tap). No physical rotation math, no tank tooling.
10. **The cooldown fix changes your coach.** Swiftmend will no longer be suggested while on
    cooldown; the solver's numbers on your recordings move. *Recommend*: accept as a bug fix, with
    the before/after strategies report in DECISIONS. **Needed before wave N1's first batch** (T90
    lands it there); the rest of N1 changes nothing you can see.
11. **Tranquility heals in the engine** (`channel` lands its ticks). Replays and coach cards of
    fights with a Tranquility change. *Recommend yes*, with a DECISIONS entry; Tranquility stays out
    of plans (`exclude`).
12. **Group and bounce heals in the tooltip and the solver.** *Recommend*: state the upper bound
    as words (`x up to 5 targets`, `up to 1.75x if 3 are hurt`) and never multiply a number
    silently. In the solver, with no positions recorded, use 4.5's assumptions: a group heal reaches
    every living tracked member of the caster's party, Chain Heal jumps to the most injured members
    at the cast; both optimistic, VERIFY, and said on the coach card. Alternative: refuse to coach
    a fight with a group heal until positions can be read (no class but the paladin would be
    coachable).
13. **Clock layouts.** *Recommend*: Line (default), Compact and Bar first; Ring in the next wave;
    **Two lines only if you overturn** DECISIONS "second line rejected (one-second glance test)".
14. **Clock text alignment.** (a) Fixed segments (label, value, secondary at fixed places;
    DECISIONS:116 restored); (b) keep T82's centring. *Recommend (a)*.
15. **Clock bar default.** (a) Keep each line's meaning (5SR on TBC, pool on Forever) with the
    spark optional; (b) pool + 5SR spark on both lines by default. *Recommend (a)* for now, (b)
    offered as one click in Settings -> Clock.
16. **Clock colours.** *Recommend*: the Forever clock gets TBC's tones (red under 20 s, amber under
    60 s); under Flat the tones keep TTO's literals on both lines; a style may re-tint them. In the
    crit band TBC paints the whole line red, label included, with its `vv` mark (`TTO.lua:370`);
    that stays TBC's. Forever's crit band is red too but shows no arrow (it has no trend latch), so
    no `vv` -- the face carries `arrow = nil` there.
17. **Left-click in combat on TBC.** Forever opens the window out of combat only (T70) and TBC's
    window now hides in combat too (C1). *Recommend*: the same rule on TBC.
18. **Forever clock gaps F3-F6** (warriors get no clock, click-through, the pulse, a rest toggle).
    *Recommend all*.
19. **Brokers.** Names `SpellTuner` and `SpellTuner Regen`; published whenever a host has LDB, on
    both lines, **on by default even with ElvUI** (ElvUI then lists the clock twice; Settings says
    to pick the native one). Alternative: off by default when ElvUI is loaded.
20. **EllesmereUI extras.** The `/unlock` mover and the minimap-collector fixes. *Recommend yes.*
    For the in-game test you will need to enable EllesmereUI, its Options, DataBars, Minimap and
    BlizzardSkin on Healroot (all disabled today).
21. **Wave size.** This spec's waves hold up to six file-disjoint tasks; your rule is about three
    agents at once. *Recommend*: each wave runs in at most two **named** batches of three (section
    11 lists them: tasks sharing an upstream dependency go together), one integrator, the first
    batch merged and green before the second starts, the wave merged and green before the next.
22. **The probe on TBC.** The art (Classic, Modern), clock (Q-clock-3/4) and cooldown answers are
    wanted from both clients, but `Client/Probe.lua` is Forever-only today. *Recommend*: put it on
    the TBC TOC (`/md probe`, T87), every Forever-only section reporting `absent`, the report saved
    in `SpellTunerDB.probe` keyed by build as on Forever. Alternative: a small TBC-only
    `/md artcheck` (less to test, a second report format).

---

## 10. Risks and what each costs

Each risk names where it lives, what it costs if it happens, and what this spec does about it. The
research notes' own risk lists (`R-ellesmere` 5, `R-styles` 9, `R-classes` 5-6) are folded in.

| # | Risk | Cost if it happens | What the spec does |
|---|---|---|---|
| X1 | **EllesmereUI moves with the beta.** Tested against 9.3.4 (2026-09-30); its skin API is apiVersion 2, "additive only"; the rest (DataBars' LDB block, the unlock mode, the minimap collector) is not a published contract. | A broker block, the mover or the follow stops working after an EllesmereUI update; SpellTuner itself keeps running. | Every call guarded by `type(...) == "function"` and `pcall`; `TESTED_EUI = "9.3.4"` printed beside the running version in INTEGRATIONS and `/st dump`; the follow only when `S.apiVersion == 2`, else the clone with `skin apiVersion <n>: not followed` (6.3, T97, T100). In-game checks 5-6 re-run on each EllesmereUI update. |
| X2 | **The unlock-mode API is undocumented** ("from any addon" in a comment, not in a developer guide) and **drops fields outside its whitelist silently** (`EllesmereUI.lua:2321-2322`). | A mover that saves nothing, or a position applied wrong. | Only whitelisted fields passed; `euicheck`'s fake `MakeUnlockElement` drops the rest as EllesmereUI does, so a field we rely on outside the list fails offline; without the function the clock keeps its own drag and says `mover: not offered by this EllesmereUI` (T97). |
| X3 | **BlizzardSkin as a second painter.** EllesmereUI's Blizzard-window skins fade a skinned frame's textures to alpha 0 (`WindowEngine.lua:412-429`). They target Blizzard frames by name and SpellTuner's are `SpellTuner*`; not observed. | SpellTuner's backdrop or the clock's bar backing vanishes. | SpellTuner's frames are never handed to `S.Shell` / `S.Panel` / `S.Button` (decision 5); in-game check 8 is run with EllesmereUIBlizzardSkin **enabled**; if it is ever seen, `UI.Skin` re-applies its own alpha on `STYLE_CHANGED` and the dump names the frame. |
| X4 | **The skin facade arrives after the style is applied.** The style is applied at `CORE_LOGIN`; EllesmereUI hands `S` to `RegisterSkin`'s callback at its own `PLAYER_LOGIN`, in an order between addons nobody controls. | The Ellesmere style shows the clone's colours until the next change. | `Integrations/EllesmereUI_Forever.lua` fires `EUI_SKIN_READY` when it stores `MD.EUISkin`; the Ellesmere style repaints on it (once); `stylecheck` runs both orders (T97, T100). |
| X5 | **Pre-blended alpha.** A `|cff` code cannot carry alpha, so EllesmereUI's white-at-0.53 label is blended into a hex against the style's `bg`. | Over any other fill (a hovered or selected row) the text is a few percent off. Cosmetic. | Accepted and written in `UI/Style_Ellesmere.lua`; regions (not text) keep real alpha. |
| X6 | **The outset art edge against pixel snapping.** `UI.px` snaps 1-px edges; a 32-unit dialog edge must not be snapped, but the outset child's anchors must be, or the stone shimmers at 0.71 effective scale. The 22-px button art squashes at 18 px. | A shimmering or squashed Classic window. | Classic is last (N5), after its mockup and screenshots; T108 snaps the outset anchors only; `stylecheck` asserts the content rect is unchanged; in-game check 12 is a screenshot on both clients. |
| X7 | **Art missing on one client** (the Forever atlas map moves between builds). | A role painted with nothing. | Per-role fallback to Flat, listed in `/st dump`; `== art` re-run on every Forever build (5.2-5.3). Handled. |
| X8 | **Forever auras turn secret.** T105 relies on `ShouldAurasBeSecret` answering false in combat on build 70009 (`R-classes` 113). | Innervate and the other mana sources cannot be read in combat. | T87's `== auras` re-asks it on the current build and reads a mana-source aura's fields; T105 treats a secret aura as "no source", counts it, and the clock stays exactly as low as today (never a guess). |
| X9 | **Class data nobody has measured.** Chain Heal / Prayer of Healing / Holy Nova targets and range (4.5); Renew, Riptide and Wild Growth tick periods (3 s assumed, Wild Growth uniform 1 s); **Light's Vigil removes Holy Shock's next cooldown** (its text, `R-classes` 99), which the solver does not model. | Non-druid coach numbers off: group heals overstated (optimistic), a Vigil paladin's Holy Shock understated. | VERIFY on every rule in the profile; the card states the group assumption; Holy Shock keeps its 10 s in plans (pessimistic) while a **recorded** Holy Shock inside its cooldown is replayed as recorded, never refused (T90); gate 8 measures attribution; in-game check 3 measures the tick periods. The rules (coefficients, periods) are VERIFY until a WCL fit or `/st measure` confirms them (principle 9). Handled for the static data. |
| X10 | **The probe on TBC** is a Forever-shaped file on a 20506 client. | A raise in one section of one report. | Every check under `pcall`, Forever-only sections report `absent`, `probecheck` runs under the tbc profile with no `C_Secrets` (T87). Nothing in play depends on it. |
| X11 | **The cooldown fix moves the author's coach** (decision 10) and Tranquility's ticks move replays (decision 11). | Cards the author remembers read differently. | The strategies report before / after in DECISIONS, in the task that makes the change (T90, T96). |
| X12 | **Group attribution on real fights** (gate 8) may fail for a priest's or shaman's group heals. | That class is not coachable from its real pulls. | The class still gets tooltip, rail, clock and practice; the gate names the reason; in-game check 11. |
| X13 | **`Texture:SetRotation` and the bar textures on Forever** (Q-clock-4). | No ring; a flat bar instead of `UI-StatusBar`. | The ring waits for the answer (T104); a missing texture falls back to the flat fill. |

---

## 11. Implementation tasks, in waves

Every task ends as `PLAN-refactor-ux.md` section 3 says: `luac -p`; the suite named **fails on the
parent commit first** (a refactor: goldens captured before the first edit and equal after); `make
check` green, apicheck 0 findings, textcheck green; one task file `docs/tasks/T<n>-*.md` with the
before/after counts. **Integrator-owned files** (edited only at a wave's end, from the lines each
task states): all TOCs, `CLAUDE.md`, `docs/HISTORY.md`, `docs/TESTING.md`, `docs/DECISIONS.md`,
`docs/TOOLS.md`, `tools/data/expected-counts.json`, `tools/check.sh` (new suites and flavours).
**No file appears twice in one wave.** A task that registers a default (`MD:RegisterDefaults`)
reports `defaultscheck`'s new counts on both flavours for the integrator; `tools/defaultscheck.lua`
itself is not edited (its source scan finds the new keys). A task that adds a slash verb on TBC owns
`tools/slashcheck.lua` in its wave and re-bases `slashcheck/tbc` with a DECISIONS line (2.5).

**Batches (decision 21).** Each wave runs as at most two batches of three agents; the first batch
is merged and green before the second starts. Tasks that share an upstream dependency go together.

| Wave | Batch A | Batch B | Starts after |
|---|---|---|---|
| N1 | T88, T89, T90 (the face and the engine) | T87, T91, T113 (probe, parser, kernel) | decision 10 (A), decision 22 (B); T86 is integrator work at the wave's start |
| N2 | T92, T93, T94 (surfaces, clock, styles: the N1 face and kernel seams) | T95, T96 (reading truth, engine seams: N1's parser, profiles and cooldowns) | decisions 1-6, 11, 13-18; M7 and M8 approved |
| N3 | T97, T98, T100 (EllesmereUI, layouts, the Ellesmere style) | T99, T101 (gates and the generic kit: both on T96) | decisions 7, 12, 19, 20; M9 approved |
| N4 | T102, T104, T105 (the clock: settings, ring, mana sources) | T103, T106, T107 (Modern, classes, live restyle) | T87's reports from both clients (T103, T104, T105) |
| N5 | T108, T109, T110 | T111, T112 | each task's own condition |

### Wave N1 -- seams that change nothing, the cooldown bug, the probe

**T86, the mockups M7-M9, is integrator work**: they are drawn (`mockups-next.html`, beside this
file); the integrator copies them to `docs/mockups/next-ui.html` at the wave's start, and the author
approves M7 / M8 / M9 before the waves that need them. N1 has six agent tasks.

| # | Task | Owned files | Tests that fail first | Needs |
|---|---|---|---|---|
| **T88** | **Clock face (S4, K1).** `Engine/ClockFace.lua` (pure: face shape with `arrow = "vv"` and `mode = "nodata"`, `LineString`, `SAMPLES`); `MD:GetClockFace()` in `Engine/TTO.lua`, `ManaModel.Face` in `Engine/ManaModel.lua`, each provided as `ClockFace.Current`; `GetDisplayString` and `ManaModel.Text` become wrappers. Byte-identical. Integrator: `Engine\ClockFace.lua` on the three main TOCs before `Engine\TTO.lua` / `Engine\ManaModel.lua`. | `Engine/ClockFace.lua` (new), `Engine/TTO.lua`, `Engine/ManaModel.lua`, `tools/clockfacecheck.lua` (new) | `clockfacecheck` (both flavours): goldens of `GetDisplayString(nil)`, `GetDisplayString("\|cff16c3f2")` and `ManaModel.Text` over every mode / bound / arrow / cd / rest-25 % / nil / >10 m, captured before the edit, **including `OOM 15s vv` (crit band) and `FULL --` (`nodata`) beside `OOM --` (oom, no value)**; ASCII, no bare pipe, nil never `0`; `Engine/ClockFace.lua` loads with no frame API (the stub's frames removed); `ttocheck` 47 and `clockcheck` 29 unchanged | -- |
| **T89** | **Profiles (S1 step 1).** The registry, validator, `Get`, `ForKit`, `Select`, `Can`; the two druid profiles; `FAMILY_KEY` / `FAMILY_TYPE` (`Kit_Forever`, `Stream_Forever`), `SP.BINDABLE` / `SP.HOT_RULE`, `MC.byClass.DRUID`, `IN_FSR_TALENT` derived at file load from `MD.Profiles.Get("DRUID")` **by name**. Byte-identical. Integrator: `Spells\Profiles.lua` then the flavour's `Data\Profile_Druid_*.lua` right after `Core.lua` / the flavour core on every main TOC. | `Spells/Profiles.lua` (new), `Data/Profile_Druid_TBC.lua` (new), `Data/Profile_Druid_Forever.lua` (new), `Modules/SpellTuner_Replay/Kit_Forever.lua`, `Modules/SpellTuner_Recorder/Stream_Forever.lua`, `Engine/SimPlanner.lua`, `Engine/ManaCooldowns.lua`, `Engine/RegenModel.lua`, `tools/profilecheck.lua` (new) | `profilecheck` (both): every profile validates; every `kit` names a `Kit.TYPES` entry; derived tables `==`-equal today's constants (asserted against the constants, not copies) **also when the stub logs in a priest** (the derivation never reads `MD.Profile`); `ForKit` of a kit with no `profile` is the druid's; a second registration raises; the generic profile's caps; with the talentsforever cache, every Forever `names` entry exists in that class's book (else SKIP, counted as not passed) | -- |
| **T90** | **Engine correctness (P0 a-b).** `SM.Ready` in `Solver:Best` and rule 8; the engine refuses and traces a **plan** cast on cooldown and never refuses a recorded one; `Kit.FIELDS.cooldown` (optional); **cooldowns per family**: `SM.CooldownOf(S, spellID)` -> family, seconds (`entry.cooldown`, else `SPELL_CD[id]`), `S.cd[family]`, `SM.Ready(S, spellID, t)` keeps its signature; `ReplayTrace`'s `cdUntil` keyed the same way (`State:CooldownUntil(spellID)` keeps its signature); `ReplayWindow.lua:812` reads the cooldown through `SM.CooldownOf` instead of the literal `15`. | `Engine/SimSolver.lua`, `Engine/SimModel.lua`, `Engine/Kit.lua`, `Engine/ReplayTrace.lua`, `UI/ReplayWindow.lua`, `tools/solvercheck.lua`, `tools/restcheck.lua` | `solvercheck` (+5: Swiftmend on cooldown never picked by `Best` or rule 8; a cooldown-blocked plan cast refused and traced; **a two-rank family: R2 cast at t blocks R1 until t + cd**; a recorded cast inside its cooldown replayed as recorded; causality unchanged); `restcheck` numbers recorded before / after and re-based; byte-identical `replaycheck`, `replayui` (the Swiftmend-ready dot); DECISIONS line (decision 10) with the strategies report on the author's recordings | decision 10 |
| **T87** | **Probe, on both clients.** On TBC: the probe loads from the TBC TOC, registers `/md probe` (`/st probe`) as a hidden row (TBC's `help` and `unlock` already are), every Forever-only section reports `absent`. New sections: `== art` (every path and atlas a style names), `== hosts` (EllesmereUI / ElvUI / LibStub / LDB presence and versions, `RegisterSkin` present), `== clock` (Q-clock-1..4), `== cooldowns` (`GetSpellBaseCooldown` on two spells, a cooldown spell's tooltip lines whole, `UnitGetTotalAbsorbs` secret or not, a `UNIT_COMBAT` hit into a shield counted by action), `== auras` (`ShouldAurasBeSecret` out of and in combat; a mana-source aura's id, name, duration and source, readable or secret). Every check under `pcall`, strings only. Integrator: `Client\Probe.lua` on `SpellTuner_TBC.toc` at the place the Forever TOCs give it; `probecheck` under `tbc` in `check.sh`; DECISIONS line (decision 22). | `Client/Probe.lua`, `tools/probecheck.lua`, `tools/stub_art.lua` (new), `tools/slashcheck.lua` | `probecheck/forever` (+7: each section present, absent functions reported absent, ASCII, no bare pipe); **`probecheck/tbc` (new: loads under the tbc profile with no `C_Secrets`, no section raises, Forever-only sections `absent`, `== art` lines for the TBC paths)**; `slashcheck/tbc` re-based only if the hidden row moves it (the help and About rows must not) | decision 22 |
| **T91** | **Parse truth (P0 d, P1 parser).** Decimal amounts (`NUM`); the "N additional damage" catch-all refused; a "your next X" clause refused; `Parse.Targets(text)`, `Parse.Cooldown(rightText)`, the lockout phrase; two mana-source shapes: "restores N mana every P sec" and Innervate's "increases ... Mana regeneration by N% ... allows M% ... while casting" -> `{ regenPct, castingPct, dur }`; refuse-unknown throughout. | `Spells/Parse.lua`, `tools/parsecheck.lua`, `tools/data/parse-fixture.lua` | `parsecheck` (+~13 sourced rows: Mana Burn 0.5, Execute, Light's Vigil refused; PoH party, Chain Heal 3 targets 50 %, Binding Heal target+caster, Holy Nova 10 yd, PW:S lockout 15, Mana Spring 290 / 3 s, **Innervate 400 % / 100 %** from its Forever text; an unknown phrase refused) | -- |
| **T113** | **Kernel seams (S0, 2.5).** `MD:AddSubcommand` (a sub matched first, the verb's own function otherwise, kept across `AddCommand`, a sub on an unknown verb creating it with a usage printer, the help row gaining the sub's usage); `MD:AddDumpLine`. Byte-identical while nothing registers. | `Core.lua`, `UI/Dump_Forever.lua`, `tools/corecheck.lua`, `tools/consolecheck.lua` | `corecheck` (both, +5: a sub runs before the verb; any other argument reaches the verb unchanged (`/st clock`, `/st clock lock`, `/st ui reset`); `AddCommand` after `AddSubcommand` keeps the subs, both load orders; an unknown verb created with its usage printer; the help row); `consolecheck` (+2: a dump line appears once, in order, ASCII; with none the dump is byte-identical); `slashcheck/tbc` unchanged | -- |

### Wave N2 -- the surfaces, the clock's gaps, the style registry, reading truth, the engine's seams

| # | Task | Owned files | Tests that fail first | Needs |
|---|---|---|---|---|
| **T92** | **Feeds + ElvUI surface (S3 step 1).** `MD.Feeds` (`clock`, `regen` from the face); `Integrations/ElvUIDatatext.lua` moved to `Integrations/Surface_ElvUI.lua` reading feeds (TBC text byte-identical); the harness stops dropping `Integrations/`. Integrator: `UI\Feeds.lua` on the main TOCs, the moved file's TBC TOC line. | `UI/Feeds.lua` (new), `Integrations/ElvUIDatatext.lua` -> `Integrations/Surface_ElvUI.lua`, `tools/harness.lua`, `tools/stub_hosts.lua` (new: fake ElvUI DT, LibStub, LDB-1.1 with equal-write suppression), `tools/surfacecheck.lua` (new) | `surfacecheck` (both): no host -> nothing registered, nothing raises; ElvUI gets exactly two datatexts; `ApplySettings` recolours the value; TBC datatext strings equal the pre-move goldens; Forever's regen feed never reads `MD.Regen` and never a secret; `FEED_CHANGED` only on a change. **Unchanged with `Integrations/` now loaded on TBC** (counts compared before / after): every `tbc` entry of `expected-counts.json`, and by name the goldens `slashcheck/tbc`, `verifycheck`, `minimapcheck`, `ttocheck`, `defaultscheck/tbc`, `reviewui`, `practiceui`, `replayui` | T88 |
| **T93** | **Clock parity (K2).** F1 tones on Forever; F2 fixed segments on both (`ClockFace.Segments`); F3 `manaUsersOnly`; F4 click-through; F5 pulse; F6 rest toggle; `Visibility.Want(..., rule)` with today's default; the renderer `UI/ClockView.lua`; the mover seam (`ApplyPoint`, `ResetPosition`, `Preview`) exposed on both clocks. New `db.clock` / TBC keys reported for `defaultscheck`. Integrator: `UI\ClockView.lua` before `UI\Widget.lua` / `UI\Clock_Forever.lua`. | `Engine/ClockFace.lua`, `UI/ClockView.lua` (new), `UI/Widget.lua`, `UI/Clock_Forever.lua`, `UI/Visibility.lua`, `tools/clockcheck.lua`, `tools/ttocheck.lua`, `tools/clockfacecheck.lua` | `clockcheck` (+5: `~OOM 0:10` crit-toned with no arrow; a Forever warrior has no clock in combat; click-through takes no mouse; a pulse under 30 s once per fight; rest off); `ttocheck` (+2: segments' x positions fixed across `59s`->`1:00`->`>10m`; text bytes unchanged, `vv` included); `clockfacecheck` (+3: `Want` default rule == today on a table of cases; `ooc = "never"`; `manaUsersOnly`). DECISIONS lines (decisions 14, 16-18) | T88 |
| **T94** | **Style registry (S2 step 1).** `UI.Styles.Register` / `Validate` / `SetStyle`, applied at `CORE_LOGIN`; Flat as data, **its `clock` role included**; `UI.skinned` by role replacing `pixelFrames`; `UI.Skin`; the `pixel` and `strips` painters; `{ ref = "accent" }` fills; `STYLE_CHANGED`; `db.ui.style` (reported for `defaultscheck`); `/st ui style` through `MD:AddSubcommand`; the dump line through `MD:AddDumpLine`; the `UI.STYLE` gate scan. | `UI/Styles.lua` (new), `UI/Theme_Flat.lua`, `UI/Style.lua`, `tools/stylecheck.lua` (new), `tools/themecheck.lua`, `tools/slashcheck.lua` | `stylecheck` (both): Flat validates; Flat -> a test style -> Flat repaints a nav frame, a button, a check box, a rail and the clock and returns **byte-identical** to the first paint; `STYLE_CHANGED` once per switch; an unknown name refused; applying before `CORE_LOGIN` raises; no styled frame built before `PLAYER_LOGIN`; `/st ui reset` still resets with `ui style` registered in either order. `themecheck` (+1: `UI.STYLE` gated nowhere outside the style files). `slashcheck/tbc` **re-based** for the new `/md ui style` (DECISIONS). navui, dashui, spellsui, replayui counts unchanged | T113; M7 approved |
| **T95** | **Reading truth, display (P1).** `Book` entries carry `targets`, `cooldown`, `lockout`; `IntervalFor = max(cast, GCD, cooldown)`; the cooldown from the tooltip line's right text (`Parse.Cooldown`) **by default**, and `MD.API.BaseCooldown` (Forever binding) bound but read only when `MD.API.BASE_CD_READS` is true -- false until T87's Forever report shows it answers plain (the `BAR_READS_MAX` pattern; the integrator flips it); the words of 4.2's P1 (upper bounds stated); the tooltip block and the Spells view show them; the damage half kept for either-or families (shown by role in T110). | `Spells/Book.lua`, `Spells/Words.lua`, `UI/SpellTip_Forever.lua`, `UI/SpellsPane_Forever.lua`, `Client/API_Forever.lua`, `tools/adaptercheck.lua`, `tools/bookcheck.lua`, `tools/tipcheck.lua`, `tools/spellsui.lua`, `tools/stub_books.lua` (new), `tools/data/books/{priest,shaman,paladin}_forever.lua` (new, attributed extracts) | `bookcheck` (+7: Holy Shock per sec over 10 s; PoH `targets = party`; Chain Heal falloff; PW:S lockout; Light's Vigil has no value; a class coverage count; `BASE_CD_READS = false` reads the tooltip line); `tipcheck` (+3: `x up to 5 targets`; `every 10 s`; nothing multiplied); `spellsui` (+2); `adaptercheck` (+1: the binding is in `FOREVER_ONLY_NAMES`) | T91; T87's Forever report (to flip `BASE_CD_READS`; not to start) |
| **T96** | **Engine seams (S1 step 2).** The kit carries its profile: `RankMath:SpellKit` and `Kit_Forever` stamp `kit.profile`, `Kit.Snapshot` / `Restore` carry it (none -> `"DRUID"`); the engine derives **per run** from `MD.Profiles.ForKit(kit)`: `S.hotIndex` (from `hotSlots`), the solver's families, the cooldown table (`kit` entries' `cooldown`; RankMath emits Swiftmend's); `SM.HOT_INDEX` / `SM.SPELL_CD` / `SV.FAMILIES` stay as the druid's fallback; `KitEntryFor[def.kit]` in `Kit_Forever`; `MD:Provide("KitLive", fn)` for `Can("coach")`; the HoT reads in Practice, `ReplayTrace` and the replay window from the kit's profile; `Scenario_Forever`'s hot map; **`channel` lands its ticks** (decision 11). | `Engine/SimModel.lua`, `Engine/SimSolver.lua`, `Engine/Kit.lua`, `Engine/RankMath.lua`, `Engine/ReplayTrace.lua`, `Modules/SpellTuner_Replay/Kit_Forever.lua`, `Modules/SpellTuner_Replay/Scenario_Forever.lua`, `Engine/Practice.lua`, `UI/ReplayWindow.lua`, `tools/kitcheck.lua`, `tools/scenariocheck.lua` | `kitcheck` (+4: `KitEntryFor` per type; Swiftmend's `cooldown` = 15; `kit.profile` stamped and round-tripped by `Snapshot` / `Restore`; a snapshot without one restores as the druid's); `scenariocheck` (+3: a recorded Tranquility lands ticks; hot map from the kit's profile; **a kit whose profile is a test class replays with that class's slots while the logged-in profile is the druid's**); byte-identical: `replaycheck`, `replayui`, `practice`, `practiceui`, `solvercheck`, `restcheck`, `simcheck`, `coachforever`, `practiceforever`, `importcheck` -- except the Tranquility fights, listed in DECISIONS | T89, T90; decision 11 |

### Wave N3 -- EllesmereUI, the layouts, the gates, the Ellesmere style, the generic kit

| # | Task | Owned files | Tests that fail first | Needs |
|---|---|---|---|---|
| **T97** | **Brokers + EllesmereUI (6.2-6.3).** `Integrations/Surface_LDB.lua` (both TOCs); `Integrations/EllesmereUI_Forever.lua` (Forever TOCs: the mover with whitelisted fields only, the unlock listener, `RegisterSkin` storing `MD.EUISkin` and firing `EUI_SKIN_READY`, `TESTED_EUI`, the `apiVersion` check); the INTEGRATIONS / dump line through `MD:AddDumpLine`; the minimap-collector fixes; apicheck rule 11; `db.feeds` / `db.eui` defaults (reported for `defaultscheck`). | `Integrations/Surface_LDB.lua` (new), `Integrations/EllesmereUI_Forever.lua` (new), `UI/MinimapButton.lua`, `tools/apicheck.py`, `tools/data/apicheck-fixture-foreign.lua` (new), `tools/stub_hosts.lua`, `tools/euicheck.lua` (new), `tools/surfacecheck.lua`, `tools/minimapcheck.lua` | `euicheck` (forever, `R-ellesmere` 4.2's 14 checks + 4): absent host quiet; half install quiet; two objects; the broker text equals the clock's on every tick; ASCII; equal writes fire nothing; tint per tone; regen text in and out of combat and in the 5SR; clicks refused in combat; the tooltip; a late reader; the mover saves / applies / clears / hides and its listener previews; settings off publish nothing; `RegisterSkin` once; **+ a fake `MakeUnlockElement` that drops non-whitelisted fields still saves and applies; an EllesmereUI version other than 9.3.4 runs and the line says `(tested 9.3.4)`; `apiVersion = 3` leaves the getters unread; `EUI_SKIN_READY` fired once**. `surfacecheck` (+2: LDB on TBC). `minimapcheck` (+1: a collected button is not pulled back; TBC golden unchanged). apicheck selftest (+1: `EllesmereUI` outside `Integrations/` is a finding) | T92, T93, T113 |
| **T98** | **Clock layouts (K3).** Compact and Bar; `db.clockLook = { layout, over }` (declared here; reported for `defaultscheck`) resolved over the style's `clock` role, which each style file defines; bar sources; the spark; `UI.Skin(widget, "clock")`; the clock's dump line. | `UI/ClockView.lua`, `UI/Widget.lua`, `UI/Clock_Forever.lua`, `tools/clockui.lua` (new), `tools/clockfacecheck.lua` | `clockui` (both, `S.Geometry(true)`): each layout x each `SAMPLES` face fits its frame at font offsets -2..+2; `bar = "none"` hides the bar; a layout switch leaves the frame's shown state alone; Show/Hide only from the owner (counted); under the forever profile nothing touches a secret; `pool` refused for the ring on Forever. `clockfacecheck` (+2: `over` wins over the style; Reset to style wipes `over`) | T93, T94 |
| **T100** | **Ellesmere style (5.1, 5.5)**, with its `clock` role. The clone; token alpha pre-blended into hex (X5 noted in the file); the follow (reads `MD.EUISkin` when `apiVersion == 2`, the parent's getters, else the clone; repaints on `EUI_LOOKS_CHANGED` and once on `EUI_SKIN_READY`). | `UI/Style_Ellesmere.lua` (new), `UI/Styles.lua`, `tools/stylecheck.lua` | `stylecheck` (+7: Ellesmere validates; label pre-blend `0.53` over `bg`; with a fake `S` the accent, panel and font come from its getters; a looks change repaints once; without `S` the clone on both flavours; **`S` arriving after `SetStyle` repaints once (X4); `apiVersion = 3` keeps the clone**) | T94 |
| **T99** | **Capability gates (4.4).** The 23 gate reads in 10 files to `MD.Profile:Can(cap)`; "Druid-only in v1" -> `<cap>: not modelled for <Class> yet`; on Forever `Can("coach")` asks `MD.KitLive` and answers `false, "module"` with the Replay module off; the comment at `Core_TBC.lua:99` saying why it stays. | `Spells/Profiles.lua`, `UI/Dashboard_Review.lua`, `UI/ReplayWindow.lua`, `UI/PracticePanel.lua`, `Engine/ReviewCommands.lua`, `UI/SimWindow.lua`, `UI/Dashboard.lua`, `UI/SpellTooltip.lua`, `UI/Advisor.lua`, `UI/Summary.lua`, `Diagnostics_TBC.lua`, `Core_TBC.lua`, `tools/capscheck.lua` (new) | `capscheck` (both): a priest (stub `S.class`) sees the not-modelled wording on Review / replay / practice / sim; a druid sees today's; the Replay module off -> the module placeholder, no new words; **a source scan finds `isDruid` only in the six reads 4.4 keeps** (`Core.lua` x2, `Core_TBC.lua:99`, `Data/SpellData.lua:193`, `Engine/RankMath.lua:555`, `Spells/Families_TBC.lua:41`); byte-identical `slashcheck`, `verifycheck`, `reviewui`, `practiceui`, `simwindow`. DECISIONS line | T89, T96 |
| **T101** | **Generic Forever kit (P2).** Types `group`, `chain`, `selfAndTarget` (fields declared in `Kit.FIELDS` first); families by shape; the solver over the kit's families with group sums, cooldowns and **4.5's reach** (party members alive; Chain Heal to the most injured now); `LandCast` multi-target; attribution of N same-instant claims; an own heal no kit entry claims replayed as recorded; the card's group-assumption line; Practice's family names from the kit; Wild Growth in (uniform ticks, VERIFY). | `Engine/Kit.lua`, `Engine/SimModel.lua`, `Engine/SimSolver.lua`, `Engine/SimPlanner.lua`, `Modules/SpellTuner_Replay/Kit_Forever.lua`, `Modules/SpellTuner_Replay/Scenario_Forever.lua`, `Modules/SpellTuner_Replay/Gates_Forever.lua`, `Engine/Practice.lua`, `tools/kitcheck.lua`, `tools/solvercheck.lua`, `tools/scenariocheck.lua`, `tools/practiceforever.lua`, `tools/stub_books.lua` | `kitcheck` (+3: a paladin, shaman, priest book become valid kits); `solvercheck` (+6: PoH beats Greater Heal only with 3+ hurt; Chain Heal's jumps go to the most injured **at the cast** (a later burst elsewhere does not move them); the falloff; a group cast sums over living party members only; the card carries the assumption line; causality unchanged); `scenariocheck` (+2: three same-instant claims for one PoH; an unclaimed own heal is replayed as recorded); `practiceforever` (+2: a paladin binds Holy Light, Holy Shock on cooldown refused). The druid's suites byte-identical except Wild Growth fights | T95, T96 |

### Wave N4 -- Settings -> Clock, Modern, the ring, mana sources, the first classes, live restyle

| # | Task | Owned files | Tests that fail first | Needs |
|---|---|---|---|---|
| **T102** | **Settings: Clock view, Look dropdown, INTEGRATIONS pane** (5.4, 6.3, 7.4). The clock view with the preview (`MD.ClockView.Build`) and chips; the swatch row; `Customise...` on both everyday panes; the Look dropdown and the class-colour check; the clock subcommands through `MD:AddSubcommand("clock", ...)` from `UI/ClockSettings.lua` (no core file touched). | `UI/ClockSettings.lua` (new), `UI/Dashboard.lua`, `UI/Dashboard_Forever.lua`, `UI/Options_General.lua`, `tools/clocksettings.lua` (new), `tools/slashcheck.lua` | `clocksettings` (both): the view exists in Settings; each chip paints its `SAMPLES` face into the preview, never the widget; a control writes `db.clockLook.over` and the widget rebuilds; the Look dropdown writes `db.ui.style` and repaints; `/st clock layout ring` / `look reset`; **`/st clock` and `/st clock lock` unchanged on Forever**; the integrations lines; `slashcheck/tbc` **re-based** for the new `/md clock` verb (DECISIONS) | T97, T98, T100 |
| **T104** | **Ring layout (K5).** The ring renderer only; its look comes from each style's `clock` role (optional `ring` fields, else the layout's defaults), which T94 / T100 / T103 / T108 own in their style files. | `UI/ClockView.lua`, `tools/clockui.lua` | `clockui` (+5: 24 segments placed on a circle and lit by fraction; `model` / `time` / `fsr` sources; `pool` refused on Forever; ring sizes 56-96; a style role with no `ring` fields uses the defaults) | T98; Q-clock-4 from both clients (T87) |
| **T105** | **Mana sources and returns (P4).** An aura-driven source table from the spell's own text (Innervate by `regenPct` / `castingPct`, Mana Tide, Mana Spring, Blessing of Wisdom by "N mana every P sec") into the modelled pool through the existing `MD.API.AuraByIndex`; **the player's aura is the source, whoever cast it**; a self-cast on another target only costs its mana; a secret aura is no source (counted, X8); refunds as "assumed" expected values; TBC `ManaCooldowns` stubs valued from text. | `Engine/ManaModel.lua`, `Engine/ManaPool_Forever.lua`, `Engine/ManaCooldowns.lua`, `tools/manasources.lua` (new), `tools/clockcheck.lua` | `manasources` (both: an Innervate aura from another unit raises the modelled regen for its duration by its text's percent of the pool's last plain regen; a self-cast Innervate on a party member changes nothing but the mana spent; a secret aura changes nothing; a Mana Spring rate from its text; refunds labelled assumed); `clockcheck` (+2: `~OOM` during Innervate longer than without) | T91, T93; T87's `== auras` answer |
| **T103** | **Modern style** (5.1-5.3), with its `clock` role. The data; the `atlas` painter; `MD.API.AtlasInfo` / `FileID` (both TOCs); per-role fallback listed in the dump. | `UI/Style_Modern.lua` (new), `UI/Styles.lua`, `Client/API.lua`, `tools/adaptercheck.lua`, `tools/stylecheck.lua`, `tools/stub_art.lua` | `stylecheck` (+4: Modern validates; with atlases absent every role is a fill; with `Options_List_Hover` present the hover uses it; the fallback list in the dump); `adaptercheck` (+2) | T94; T87's `== art` from both clients |
| **T106** | **Class profiles: Paladin, Shaman, Priest (Forever).** Names, `critSchool`, families and kit types, `hotSlots`, every rule VERIFY; `coach` / `practice` granted when the fixture passes; Priest without PW:S until T109. | `Data/Profile_Paladin_Forever.lua`, `Data/Profile_Shaman_Forever.lua`, `Data/Profile_Priest_Forever.lua` (all new), `tools/profilecheck.lua`, `tools/classcoach.lua` (new) | `classcoach` (forever, per class): the book fixture -> a valid kit stamped with the class's profile -> a synthetic fight replays through the eight gates -> the solver coaches it -> practice runs it -> the causality test holds; the card names the unmodelled spells and, for Shaman and Priest, the group assumption | T99, T101 |
| **T107** | **Live restyle conversions.** The ~36 creation-time accent reads and the high-traffic panes' text colours become registered regions or `STYLE_CHANGED` re-renders; the "Reload to finish" line counts what is left. | `UI/Style.lua`, `UI/Dashboard_Rows.lua`, `UI/SpellsPane_Forever.lua`, `UI/SpellsView_TBC.lua`, `UI/SpellRail.lua`, `UI/ReplayWindow.lua`, `UI/Dashboard_Simulate.lua`, `UI/Options_About.lua`, `UI/DebugConsole.lua`, `UI/Tip_TBC.lua`, `tools/restylecheck.lua` (new) | `restylecheck` (both): after Flat -> Ellesmere every region of the Spells view, Review, Practice and Settings reads the new accent; Flat back is byte-identical; the left-over count is 0 for the listed panes | T100 |

### Wave N5 -- conditional and last

| # | Task | Owned files | Tests that fail first | Needs |
|---|---|---|---|---|
| **T108** | **Classic style**, with its `clock` role. Data; the `backdrop`-outset (anchors snapped, the 32-unit edge not: X6), `plaque`, `slice3`, `files` painters; lazy art regions on buttons, checks and the close button. | `UI/Style_Classic.lua` (new), `UI/Styles.lua`, `UI/Style.lua`, `tools/stylecheck.lua` | `stylecheck` (+6: Classic validates; the outset child leaves the content rect equal; its anchors pixel-snapped; `slice3` swaps per state; a missing art file falls back per role; Classic -> Flat leaves no art region shown) | M7's Classic approved, `== art` from both clients, T107 |
| **T109** | **Absorbs (P3).** Shield state, expiry, the lockout; recorders keep the absorbed part; PW:S in the priest profile. | `Engine/Kit.lua`, `Engine/SimModel.lua`, `Engine/SimSolver.lua`, `Engine/FightRecorder.lua`, `Modules/SpellTuner_Recorder/Recorder_Forever.lua`, `Data/Profile_Priest_Forever.lua`, `tools/reccheck.lua`, `tools/recordcheck.lua`, `tools/solvercheck.lua` | `reccheck` (+2: a partial absorb recorded), `recordcheck` (+1), `solvercheck` (+2: a shield before a predicted hit; Weakened Soul blocks a second) | T87's absorb answers, T106 |
| **T110** | **Non-healer extras (P6).** Either-or halves by role; the list seeded by role; caster mana sources (Evocation, gems, Life Tap). | `Spells/Tabs.lua`, `Spells/Book.lua`, `Spells/Words.lua`, `UI/SpellTip_Forever.lua`, `Engine/ManaCooldowns.lua`, `tools/tabscheck.lua`, `tools/bookcheck.lua`, `tools/tipcheck.lua` | `tabscheck` (+2: a shadow priest seeds damage); `bookcheck` (+2: Holy Shock keeps both halves); `tipcheck` (+1) | T95, T105 |
| **T111** | **TBC other classes (P5)**, only on decision 8 (b) / (c). Tooltip-read bases; per-class VERIFY rules; WCL fit with a class argument; `Spells/Parse.lua` on the TBC TOC; the two "druid until T111" reads (4.4) become `Can("rankTable")`. | `Spells/Book_TBC.lua` (new), `Engine/RankMath.lua`, `Spells/Families_TBC.lua`, `Client/API_TBC.lua`, `tools/adaptercheck.lua`, `tools/capscheck.lua`, `Data/Profile_{Priest,Shaman,Paladin}_TBC.lua` (new), `tools/wclconvert.py`, `tools/wclcheckkit.lua`, `tools/tbcclasscheck.lua` (new) | `tbcclasscheck` (a TBC priest's tooltip texts -> bases -> a kit through `Kit.Check`); `wclcheckkit --fit` on public parses: three families agree; `capscheck`'s kept list down to four reads in three files; the druid's `verifycheck` goldens unchanged | T101, T106, decision 8 |
| **T112** | **Two-line layout**, only on decision 13's yes. | `UI/ClockView.lua`, `tools/clockui.lua` | `clockui` (+2) | T104, decision 13 |

*(not scheduled)*: one `UI/Clock.lua` for both lines with storage adopted once (K8); a "Measured"
line (spec decision 8); Classic's parchment and the native-art variant; a look export string.

**Parallel tracks.** In N1, batch A is the face (T88) and the engine (T89 derives what T90 then
fixes beside it, in different files); batch B is the probe, the parser and the kernel, none needing
another. In N2, T92 and T93 need T88; T94 needs T113; T95 needs T91; T96 needs T89 and T90. In N3,
T97 joins the surfaces and the clock seam; T98 joins the clock and the styles; T99 and T101 both
build on T96's `kit.profile` and `KitLive`. N4's T102 is the Settings join point. The clock role of
each style lives in that style's file (T94 Flat, T100 Ellesmere, T103 Modern, T108 Classic); the
clock tasks (T98, T104, T112) only read it.

---

## 12. In-game checks (for `docs/TESTING.md` section 46)

On each client named, out of combat unless a step says otherwise. Paste back as in section 45.

1. **Probe (T87), both clients.** `/st probe` (on TBC `/md probe`, new with T87): paste `== art`,
   `== hosts`, `== clock`, `== cooldowns`, `== auras` (Forever: once out of combat and once with an
   Innervate or Mana Spring on you in combat). On Forever do it once with EllesmereUI enabled, once
   without, and once on a priest, shaman or paladin alt of level 10+ with a cooldown heal in the
   book. On TBC the Forever-only sections read `absent`; nothing raises.
2. **Coach (T90), both.** `/st coach N` on a recording with a Swiftmend: the suggested column
   never casts Swiftmend inside 15 s of the last one, and the Swiftmend-ready dot in the replay is
   unchanged. Note how the card's numbers moved. `/st clock`, `/st clock lock` and `/st ui reset`
   behave as before (T113).
3. **Tooltips for other classes (T91, T95), Forever alt.** Hover Holy Shock / Riptide / Prayer of
   Healing / Chain Heal / Light's Vigil: the cooldown and `x up to N targets` lines appear; Light's
   Vigil shows no heal value; Per sec is over the cooldown. `/st measure` on Renew or Riptide:
   paste the tick period.
4. **Clock (T93), both.** Spend to under 20 s: Forever's clock turns red (amber under 60 s). Watch
   `59s` -> `1:00`: the label does not move. On a Forever warrior: no clock in combat. Click-through
   on: a click passes to the world. Under 30 s the clock pulses once.
5. **Brokers (T97), Forever with EllesmereUI.** Enable EllesmereUI, Options, DataBars, Minimap,
   BlizzardSkin; `/reload`. `/eui` -> DataBars -> add a Broker Plugin block for **SpellTuner** and
   one for **SpellTuner Regen**, Max Width ~120. The block equals the floating clock on every change;
   the icon tint goes amber then red. Hover: one tooltip, EllesmereUI's skin, no second border.
   Left-click opens SpellTuner, right-click Settings, neither in combat. Regen reads `(5SR)` for 5 s
   after a cast and `~` in combat. Disable SpellTuner and `/reload`: both blocks collapse.
   `/st dump`: the integrations line names EllesmereUI's version beside `(tested 9.3.4)` and
   `skin apiVersion 2`.
6. **Mover and minimap (T97).** `/unlock`: a "SpellTuner clock" mover with the clock previewed; drag,
   save, `/reload`: the clock stays. The SpellTuner button sits in EllesmereUI's flyout with its icon
   centred; toggle it in Settings -> Windows: it stays there. `/st probe`: no blocked action names
   SpellTuner.
7. **Brokers on TBC (T97).** With ElvUI: its datatext list shows `SpellTuner` and `LDB: SpellTuner`;
   both read the same.
8. **Styles (T94, T100, T103, T107), both.** Settings -> General -> Look: Ellesmere, then Modern,
   then Flat. Each repaints the open window at once; nothing moves or resizes; Flat looks exactly
   as before. On Forever with EllesmereUI **and EllesmereUIBlizzardSkin enabled** (X3): the label
   says "following EllesmereUI", changing EllesmereUI's accent repaints SpellTuner, and no
   SpellTuner window or the clock's bar backing has gone transparent. `/reload` with the Ellesmere
   style chosen: the first paint already follows EllesmereUI (X4). Note any window that only
   finished after `/reload`.
9. **Settings -> Clock (T98, T102, T104), both.** Click each state chip: the preview changes, the
   real clock does not. Switch to Compact, Bar, Ring: the clock rebuilds in place. Change the font
   size and a tone colour; `Reset to style`: back to the style's look. `/reload`: the layout is kept.
10. **Mana sources (T105), Forever druid.** Innervate yourself in a fight: `~OOM` jumps out for
    20 s and comes back; the clock no longer reads low during it. If another druid is there, an
    Innervate from them does the same; your Innervate on someone else does not.
11. **Other healers (T101, T106), Forever alt.** Record one pull (`/st rec`); `/st validate N` (paste
    gate 8); `/st coach N` (with a Prayer of Healing or Chain Heal in it the card carries the
    group-assumption line, 4.5); start a practice session with two bindings.
12. **Classic (T108), both, after M7.** Settings -> Look -> Classic: stone edges outside the window,
    gold plaque, panel buttons. Screenshot both clients.
