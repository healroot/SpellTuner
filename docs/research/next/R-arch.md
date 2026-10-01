# R-arch: seams for more classes, UI styles, integrations and a customizable clock

Read-only research on `claude/manademon-folder-continue-41eabc` at `c911339` (SpellTuner 0.16.5),
2026-10-01. Paths are relative to the worktree unless marked otherwise. The author asked for four
things: (1) more spells and classes, (2) two or three UI styles (today's flat look, classic, retail,
EllesmereUI-like), (3) an EllesmereUI integration beside the ElvUI datatext, (4) a better-looking
mana clock that can be customized. This file covers the architecture those need: what exists, what
is hard-wired, the four seams to build first (their files, contracts and tests), and the order to
build them in. Nothing here is a rewrite. Every step is a registry or a split that leaves today's
output byte-identical, and then a second step that adds the new behaviour.

---

## 0. Summary

| # | Seam | New files (first step) | Contract in one line | Proven offline by |
|---|---|---|---|---|
| S1 | **Class profile registry** | `Spells/Profiles.lua`, `Data/Profile_Druid_TBC.lua`, `Data/Profile_Druid_Forever.lua` | `MD.Profiles.Register(classToken, flavourProfile)`; `MD.Profile` is the active one; `MD.Profile:Can(cap)` replaces `MD.player.isDruid` | `tools/profilecheck.lua` (validator, talentsforever cross-check) and every druid suite byte-identical |
| S2 | **Theme registry** | `UI/Themes.lua` (registry), `UI/Theme_Flat.lua` becomes one registration | `UI.Themes.Register(key, theme)`, applied once at `CORE_LOGIN` from `db.ui.theme`; `UI.Skin(frame, role)` | `tools/themecheck.lua` per theme, plus `navui` / `spellsui` / `replayui` run under each theme |
| S3 | **Feeds and surfaces** (integrations) | `UI/Feeds.lua`, `Integrations/Surface_ElvUI.lua`, `Integrations/Surface_LDB.lua`, `Integrations/Skin_EllesmereUI.lua` | a *feed* (`clock`, `regen`) is text, a tooltip and a click; a *surface* (widget, minimap, ElvUI, LDB) displays feeds | `tools/surfacecheck.lua` with a fake ElvUI DT and a fake LibStub / LDB |
| S4 | **Clock: state / format / render split** | `UI/ClockFormat.lua` (pure), `UI/ClockWidget.lua` (one renderer, both lines) | `MD.ClockSource(now) -> state` (one per flavour, through `MD:Provide`); `ClockFormat.Text(state, spec, colours)`; the widget paints a layout preset | `tools/clockfmt.lua` (golden strings for both of today's formats), `ttocheck` and `clockcheck` unchanged |

Order (section 7): first the three behaviour-neutral extractions (S4's formatter, S3's feed
registry with ElvUI moved onto it, S1's registry mirroring today's druid constants). Then the
visible work: the clock renderer and the LDB surface, which covers EllesmereUI's DataBars. Then
themes and the EllesmereUI skin. The second class comes last because it depends on review item A11
(the engine reads the kit, not `MD.SpellData`).

Three facts found while reading change the plan the author might expect:

1. **The way into EllesmereUI is LibDataBroker, not a datatext API.** EllesmereUI has no
   datatext registry. Its DataBars addon has one block type, `ldb`, which shows any
   LibDataBroker-1.1 data object (`EllesmereUIDataBars/Blocks/LDB.lua:29-49`). EllesmereUI ships
   the library itself (`EllesmereUI/Libs/LibDataBroker-1.1`, resolved through
   `LibStub:GetLibrary("LibDataBroker-1.1", true)` at `EllesmereUIDataBars.lua:3141-3146`). ElvUI
   also wraps every LDB object as a datatext named `LDB_<name>`
   (`../ElvUI/Game/Shared/Modules/DataTexts/DataTexts.lua:335-365`). So **one LDB surface covers
   EllesmereUI, ElvUI, Titan Panel and every other broker display**, and SpellTuner still ships no
   library: it uses one only when another addon has loaded it.
2. **The EllesmereUI style can be EllesmereUI itself.** EllesmereUI publishes a skinning API for
   other addons (`EllesmereUI/SKINNING_API.md`): `EllesmereUI.RegisterSkin(name, fn(S))` with
   `S.Shell`, `S.Panel`, `S.Button`, `S.Checkbox`, `S.Dropdown`, `S.ScrollBar`, `S.Tab`,
   `S.CloseButton`, `S.ApplyBarFill`, plus getters `S.GetAccentColor`, `S.GetPanelColor`,
   `S.GetFont` and `S.OnLooksChanged`. An "EllesmereUI" theme on Forever should read those live
   values when EllesmereUI is loaded, rather than copy its teal. Where EllesmereUI is absent (TBC
   always, since its TOC lists only `120000..120100, 16001`) the theme falls back to a built-in
   palette that imitates it.
3. **On Forever the numbers are already class-generic. On TBC and in the engine they are not.**
   `Spells/Book.lua` reads any class's spellbook and decides heal or damage from the spell's own
   text (`Book.lua:372-380`, `484-499`). The tooltip block, the Spells rail and the clock therefore
   already work for a Forever priest. What is druid-only is TBC's static `Data/SpellData.lua`, the
   simulator kit (`Kit_Forever.lua`'s `FAMILY_KEY` / `FAMILY_TYPE`), the engine's three fixed HoT
   slots, the planner's rules, and 30+ `isDruid` gates. A profile on Forever is mostly names, kit
   types and rule choices. It does not carry numbers.

---

## 1. What already exists (the seams these build on)

The refactor plan (`docs/PLAN-refactor-ux.md`, waves 1-17 and C) left a set of patterns. Each new
seam reuses one of them instead of inventing another.

| Pattern | Where | Use it for |
|---|---|---|
| One adapter for client reads | `Client/API.lua` (`MD.API.Has`, `Call`, `Bind`), `Client/API_TBC.lua` / `API_Forever.lua` | host-addon detection (`C_AddOns.IsAddOnLoaded` vs `IsAddOnLoaded`), `SpellTexture` for clock icons |
| A seam filled once, a second provider raises | `MD:Provide(name, fn)`, `Core.lua:459-479`; used for `MinimapLines` (`UI/Clock_Forever.lua:133`, `UI/Tip_TBC.lua:580`) | `MD.ClockSource` (S4), `MD.Profile` selection (S1) |
| Settings declared by the file that reads them | `MD:RegisterDefaults` / `MD:Setting`, `Core.lua:379-396`; first-use migrations under `tools/migrate` (`migrate/tbc: 7`) | `db.ui.theme`, `db.clockStyle`, `db.feeds` |
| A difference between lines is a value the flavour installs (apicheck rule 10) | `PR.policy` (`Engine/Practice.lua:166`), `RC.policy` (`Engine/ReviewCommands.lua:45`), `Tabs.source` (`Spells/Families_TBC.lua:74`) | each flavour's profile file, each flavour's clock source |
| Registries keyed by a version or prefix | `SM.scenarioBuilders[v]` / `SM.validators[v]` (`Engine/SimModel.lua:1466-1472`), `MD.Recordings.Register(prefix, provider)` | `MD.Profiles`, `UI.Themes`, `MD.Feeds` all take this shape |
| One owner for a shape, plus a validator | `Engine/Kit.lua`: `Kit.FIELDS` (46), `Kit.TYPES` (69), `Kit.Validate` (111), `Kit.Check` (181) | `Profiles.Validate` and `Themes.Validate` copy it |
| Rules shared by field map | `Spells/RankRules.lua` (`f.eff`, `f.rate`, `f.value`, `f.eligible`) | already class-neutral; a profile only overrides `MD.Rules.SUGGESTED_FLOOR` if it ever needs to |
| Words with a `style` | `Spells/Words.lua` (`cell` / `card` / `export` / `tip`) | per-family wording hooks from a profile (absorb, chain, eats a HoT) |
| Colour tokens plus one look flag | `UI.TEXT` / `UI.PALETTE` / `UI.Hex` / `UI.RGB` / `UI.Fill` (`UI/Style.lua:102-190`), `UI.THEMED` (`Style.lua:102`, `Theme_Flat.lua:83`) | the theme registry writes the same tables |
| One answer to "should it be visible" | `MD.Visibility.Want(pct, shown, inCombat, unlocked)`, `UI/Visibility.lua:27` | the shared clock renderer, with a `mode` argument added |
| A pure model and a pure projection | `Engine/ManaModel.lua` (`Project` 180, `Text` 280), `Engine/TTO.lua` (`Compute` 52, `GetDisplayString` 345), `MD.Pool` (`Engine/ManaPool_Forever.lua`) | S4's `ClockSource` normalizes the two |

---

## 2. Where "druid" and "one look" are hard-wired today

### 2.1 Class

`grep isDruid` outside `tools/` finds 30 sites in 15 files. The ones that matter:

| Site | What is fixed | Becomes |
|---|---|---|
| `Core.lua:301` `MD.player.isDruid = class == "DRUID"` | the one flag | stays as a fact. Gates move to `MD.Profile:Can(...)` |
| `UI/Dashboard_Review.lua:610, 662, 693, 807, 841-863`, `Engine/ReviewCommands.lua:168`, `UI/ReplayWindow.lua:1755, 1980, 2388`, `UI/PracticePanel.lua:523`, `UI/SimWindow.lua:75, 262` | coach / replay suggested column / practice are "Druid-only in v1" | `Can("coach")`, `Can("practice")`, `Can("simulate")` |
| `Engine/RankMath.lua:555`, `UI/Dashboard.lua:58, 142, 287`, `Spells/Families_TBC.lua:41`, `UI/SpellTooltip.lua:57`, `Data/SpellData.lua:193` | TBC rank table and tooltip from the druid's static table | the TBC profile's `families` (`Can("rankTable")`) |
| `UI/Advisor.lua:58, 85`, `UI/Summary.lua:496` | advisor and summary lines | `Can("advisor")` |
| `Engine/ManaCooldowns.lua` `MC.byClass` (DRUID valued; PRIEST, SHAMAN, PALADIN stubs) | per-class cooldowns | `profile.manaCooldowns` |
| `Engine/RegenModel.lua:155-159` `IN_FSR_TALENT` (DRUID, PRIEST, MAGE) | the in-5SR talent | `profile.regen.inFsrTalent` |
| `Modules/SpellTuner_Replay/Kit_Forever.lua:21-37` `FAMILY_KEY`, `FAMILY_TYPE`; `KitEntry` (111) branches on `family == "HealingTouch"` / `"Rejuvenation"` / `"Regrowth"` | the Forever kit knows five druid families by name | `profile.families[key].kit` (type plus builder) |
| `Modules/SpellTuner_Recorder/Stream_Forever.lua:28-34` `FAMILY_KEY` | a second copy of the same name map | reads the profile |
| `Kit_Forever.lua:98` `MD.API.SpellCritChance(4)` (Nature) | the crit school | `profile.critSchool` (Holy is 2 for priests and paladins) |
| `Engine/SimModel.lua:91-93` `SM.HOT_INDEX = { Rejuvenation = 1, Regrowth = 2, Lifebloom = 3 }`, `:111` `SPELL_CD = { [18562] = 15 }`, `:119-120` `SWIFTMEND_ORDER`, `:331` `for fi = 1, 3`, `:584-588` "hybrid goes to the Regrowth slot, hot to the Rejuvenation slot" | the engine's per-target HoT state has three druid slots | `profile.hotSlots` (an ordered list; the druid's order is kept so traces stay identical) and the kit entry's `cd` |
| `Engine/SimPlanner.lua:39, 87-90` (`HOT_INDEX`, `SP.BINDABLE`, `SP.HOT_RULE`), rules 1-5 by family name (240-440) | the threshold rules are a druid's strategy | `profile.planner = { rules = "druid", bindable = {...} }`. Other classes get the solver only |
| `Engine/SimSolver.lua:279` `SV.FAMILIES` | the solver's candidate list | `profile.planner.families`. The solver itself is generic, built on deposits (`SV.Deposits`, 56) |
| `Engine/Practice.lua:1367-1368`, `UI/ReplayWindow.lua:774-790` | HoT slots read by name for display | read `profile.hotSlots` |
| ~50 reads of `MD.SpellData` in the engine, planner, solver, practice and replay window | the engine indexes the TBC table (on Forever, the module installs a stand-in) | review item A11, "do it when a second class needs it" (`PLAN-refactor-ux.md` section 6) |

### 2.2 Look

- `UI/Theme_Flat.lua` runs **at file load**, before SavedVariables exist. It overwrites `UI.PALETTE`
  and `UI.TEXT` in place, builds fonts, and sets `UI.PIXEL = true`, `UI.LIST_STRATA` and
  `UI.THEMED = true` (`Theme_Flat.lua:24-83, 171-176`). That leaves no room for a choice.
- `UI.THEMED` is read in about 60 places (`Style.lua` 25, `ReplayWindow.lua` 17, `Tip.lua` 6, and
  others). It means "the new structure and look". It must not become a style switch: a classic
  style still wants the rail and the takeover. Section 4 splits *structure* (stays `UI.THEMED`)
  from *skin* (the new registry).
- `UI.StylizeFrame(frame, color, border)` (`Style.lua:397`) receives colours, not roles, so a theme
  cannot swap a flat backdrop for a dialog border. `UI.pixelFrames` (373) already keeps a weak
  registry of styled frames, which is the hook for restyling in place.

### 2.3 Clock and integrations

- Two clocks with two formatters and two settings shapes. TBC: `Engine/TTO.lua`
  `MD:GetDisplayString(valueHex)` (345-415, colour literals `GREY` / `WARN` / `CRIT` / `GOOD` /
  `MANA` at 330-335, latch and arrow) and `UI/Widget.lua` (frame, FSR bar), settings `db.pos`,
  `db.locked`, `db.showRest`, `db.showCooldown`, `db.widgetTooltip` (`Core_TBC.lua:13-26`).
  Forever: `ManaModel.Text` (`ManaModel.lua:280`) and `UI/Clock_Forever.lua` (frame, real-mana bar
  through `MD.API.DrawUnitPower`), settings `db.clock = { shown, locked, point }`
  (`Core_Forever.lua:33`). Both are 180 x 30 with the text over a 160 x 4 bar (T82 unified the
  look, `Widget.lua:1-16`). Size, font, layout and segments are literals.
- `Integrations/ElvUIDatatext.lua` is TBC-only. It is not in `SpellTuner_Mainline.toc` and never
  loads in the harness (`tools/harness.lua:69-72`, `KeepForTbc` drops `Integrations/`). Its regen
  datatext calls `MD.Regen:Current()`, which does not exist on Forever. It is the one surface with
  no test.

---

## 3. S1: the class / spell profile registry

### 3.1 Files

- `Spells/Profiles.lua`: core, pure, in **both** main TOCs right after `Core.lua`'s helpers (before
  `Spells/RankRules.lua`). It is the registry, the validator, the capability query and the
  active-profile choice.
- `Data/Profile_<Class>_<Flavour>.lua`: one file per class per line, listed by that line's TOC (or
  by the Replay module's TOC for kit-only parts). A flavour difference stays a value the TOC
  installs, so no shared file reads `MD.API.client` (apicheck rule 10).
  - `Data/Profile_Druid_TBC.lua` wraps `Data/SpellData.lua` (`SD.families`, `SD.familyOrder`,
    `SD.alias`), `MC.byClass.DRUID`, `IN_FSR_TALENT.DRUID` and the planner's druid rules.
  - `Data/Profile_Druid_Forever.lua` holds names only: the book-name to family-key map, the kit
    types, the HoT slots without Lifebloom, Swiftmend's eat order, crit school 4.
  - Later `Data/Profile_Priest_Forever.lua`, then Shaman and Paladin. A TBC profile for another
    class needs coefficient rules and values from measurement (CLAUDE.md: `SpellData` values only
    from `/md verify` or a measurement), so it comes after the Forever ones.
- The generic profile (any class, any line): no families, all capabilities false except `clock`,
  `tooltip` and (Forever) `rankTable`, which `Book` already provides. A class with no file gets
  exactly what it gets today.

### 3.2 Contract

```lua
-- Spells/Profiles.lua
MD.Profiles = { byClass = {}, generic = { class = "*", caps = { clock = true, tooltip = true } } }

-- Registered by a Data/Profile_* file; a second registration for one class raises (MD:Provide's rule).
MD.Profiles.Register("DRUID", {
  label       = "Druid",
  critSchool  = 4,                       -- MD.API.SpellCritChance(school); Holy = 2
  caps        = { clock = true, tooltip = true, rankTable = true, advisor = true,
                  simulate = true, coach = true, practice = true },
  -- family key -> how the line names it and how the engine models it
  families = {
    HealingTouch = { names = { "Healing Touch" }, kit = "direct", bindable = true },
    Regrowth     = { names = { "Regrowth" },      kit = "hybrid", hot = "Regrowth", bindable = true },
    Rejuvenation = { names = { "Rejuvenation" },  kit = "hot",    hot = "Rejuvenation", bindable = true },
    Swiftmend    = { names = { "Swiftmend" },     kit = "instant", eats = { "Regrowth", "Rejuvenation" }, cd = 15 },
    Tranquility  = { names = { "Tranquility" },   kit = "channel", exclude = true },
    -- TBC adds Lifebloom = { kit = "lifebloom", hot = "Lifebloom" } and the ids / alias table
  },
  order     = { "HealingTouch", "Regrowth", "Rejuvenation", "Swiftmend" },  -- rail seed, kit order
  hotSlots  = { "Rejuvenation", "Regrowth", "Lifebloom" },  -- SM.HOT_INDEX in this order (traces unchanged)
  planner   = { rules = "druid", families = { "Swiftmend", "Regrowth", "HealingTouch", "Lifebloom", "Rejuvenation" } },
  manaCooldowns = { { key = "innervate", short = "inn", id = 29166, duration = 20, value = "innervate" } },
  regen     = { inFsrTalent = { "Intensity", 0.10 } },
  words     = { Swiftmend = function(entry, style) return "eats a HoT" end },  -- optional, Spells/Words.lua asks
})

MD.Profiles.Validate(p)    -> true | false, problems  -- Kit.Validate's style: declared fields, known kit types
MD.Profiles.Select(class)  -- at CORE_LOGIN, after DetectProfile: MD.Profile = byClass[class] or generic
MD.Profile:Can(cap)        -- boolean; the one replacement for MD.player.isDruid gates
MD.Profile:Family(nameOrKey) -> key, def  -- Book name ("Healing Touch") or key to the family
MD.Profile:HotIndex()      -> { [family] = slot }  -- built once from hotSlots; SM.HOT_INDEX points at it
```

Rules:

- **Pure data plus small functions. No client calls.** The value models in `manaCooldowns` are
  named (`value = "innervate"`) and resolved by `Engine/ManaCooldowns.lua`, which keeps the
  arithmetic, so a profile file never reads regen.
- **A profile does not carry spell numbers on Forever.** Numbers come from `Book` (the client's
  text). On TBC they stay in `Data/SpellData.lua`, and the TBC profile points at it.
- **`kit` names a type in `Kit.TYPES`** (`Engine/Kit.lua:69`). A new kind of heal adds a type
  there first, with its fields in `Kit.FIELDS`, as the file's header already requires. Kit
  builders then switch on `def.kit`, not on the family name: `KitEntry` (`Kit_Forever.lua:111`)
  becomes `KitEntryFor[def.kit](be, crit, def)`.
- **Capabilities are the only gate.** The druid profile answers true wherever `isDruid` did, so the
  golden transcripts (`slashcheck`, `verifycheck`, `reviewui`, `practiceui`) stay byte-identical.
  The "Druid-only in v1" strings become `"<cap>: not modelled for <label> yet"`. That changes
  output only for non-druids, so it needs a `DECISIONS.md` line.

### 3.3 Kit types a second class needs

From talentsforever's beta descriptions (`tools/.cache/talentsforever.json`, tagged by a quick
regex over `spell_desc`; to be confirmed against a probe dump):

| Shape | Examples on Forever | Engine today | Step |
|---|---|---|---|
| direct, single target | Flash Heal, Lesser / Greater Heal, Heal, Healing Wave, Lesser Healing Wave, Holy Light, Flash of Light | `direct` | profile only |
| HoT | Renew | `hot` (but slot 1 is "Rejuvenation") | `hotSlots` from the profile |
| direct + HoT | Regrowth; Riptide (with a cooldown) | `hybrid` plus `SPELL_CD` keyed by id | `cd` as a kit field |
| cooldown direct | Holy Shock (10 s), Penance (channelled, 4 ranks) | none | `cd` field; Penance is a `channel` with `channelTick` |
| absorb | Power Word: Shield; Templar's Bulwark | none | new type `absorb` (a deposit that cancels damage, not health) |
| multi-target | Prayer of Healing (party), Chain Heal (jumps, falloff), Binding Heal (self + target), Holy Nova | none | new type `multi` (`targets`, `falloff`, `scope = "party"/"chain"/"self+target"`) |
| group HoT | Wild Growth, Healing Stream Totem | none (Wild Growth is "skipped" today, `Kit_Forever.lua:83-87`) | `multi` with tick fields |
| damage-triggered bounce | Prayer of Mending | none | leave out; label it "not modelled" (`dataMissing`) |

The solver is already priced in deposits (`SV.Deposits`, `SimSolver.lua:56`), so each new type
means one deposit builder plus one landing branch in `SM:Run`'s `LandCast` (`SimModel.lua:572-600`).
The threshold rules (`SimPlanner.lua`) stay druid-only. Another class gets `planner.rules = nil`
and the solver strategies of `SP.STRATEGY_SET` only. That costs nothing, because the solver
already beat the rules (CLAUDE.md, `SimSolver.lua` header: "44% less").

### 3.4 How it stays testable

- `tools/profilecheck.lua` (new; both flavours). For every registered profile:
  `Profiles.Validate` passes; every `kit` names a `Kit.TYPES` entry; every `hotSlots` member is a
  family with `hot`; the druid profile's derived tables equal today's constants (`SM.HOT_INDEX`,
  `SP.BINDABLE`, `SV.FAMILIES`, `SWIFTMEND_ORDER`, `FAMILY_KEY`, `FAMILY_TYPE`, `MC.byClass.DRUID`).
  The check is assertions that the derived tables are equal to the constants, not to copies of
  them. With the talentsforever cache present, every Forever `names` entry must exist in that
  class's spellbook. With no cache the check reports SKIP, and since T13 a skip is not a pass.
- Harness: `S.class` in `tools/wowstub.lua` already drives `UnitClass`. Add a `--class PRIEST`
  option to `tools/run.sh` / `harness.lua`, and a forever-profile spellbook fixture per class built
  from `tools/data/parse-fixture.lua`-style texts.
- **Byte-identical gate for every step that only moves data**: `dashui`, `replaycheck`, `replayui`,
  `practice`, `practiceui`, `solvercheck`, `restcheck`, `simcheck`, `kitcheck`, `coachforever`,
  `practiceforever`, `slashcheck`, `verifycheck` (the TBC golden transcripts). This is the same
  oracle the refactor plan used (`PLAN-refactor-ux.md` section 2).

---

## 4. S2: the theme registry (several UI styles)

### 4.1 Separate structure from skin

- `UI.THEMED` keeps its meaning: **the new structure is on** (rail, takeover, sheets, new
  tooltips, pitches). After wave C it is true on both lines. No style turns it off.
- A **theme** is the skin: colour tokens, fills, fonts, edges, textures, list strata, and
  optionally a skinner per frame role. Four themes:
  - `flat` (today, the default): `Theme_Flat.lua`'s values exactly.
  - `classic`: Blizzard 2004-2008. `UI-DialogBox-Border` / `UI-Tooltip-Border` edges, the
    parchment-dark fill, `GameFontNormal` gold titles, Friz numbers. It uses only texture paths
    present in both clients; the TBC Anniversary client is a modern engine, but each path must
    still be confirmed through `MD.API.Has` / a probe line.
  - `retail`: modern Blizzard. NineSlice layouts (`NineSliceUtil` on Forever's retail engine)
    with a flat fallback where the client lacks them, which needs a probe line on TBC.
  - `ellesmere`: EllesmereUI's look. When EllesmereUI is loaded it takes its accent, panel colour
    and font from the live getters (`S.GetAccentColor`, `S.GetPanelColor`, `S.GetFont`) and
    re-applies on `S.OnLooksChanged`. Otherwise it uses a built-in palette (teal accent `0cd29f`,
    near-black panels, 1 px borders), which is the flat theme with other numbers. On TBC that
    built-in palette is always the one used.

### 4.2 Files and contract

- `UI/Themes.lua` (new, both main TOCs, right after `UI/Style.lua`): registry and applier.
- `UI/Theme_Flat.lua`: today's file. Its body becomes `UI.Themes.Register("flat", {...})`, and the
  assignments move into the registered table unchanged.
- `UI/Theme_Classic.lua`, `UI/Theme_Retail.lua`, `UI/Theme_Ellesmere.lua`: one registration each.
- `Integrations/Skin_EllesmereUI.lua`: the live source for the `ellesmere` theme
  (`EllesmereUI.RegisterSkin("SpellTuner", fn)`), stores `S`, and calls `S.Shell` on the main
  window, `S.Panel` on panes and `S.Button` on kit buttons when the active theme asks for
  `skinWith = "EllesmereUI"`.

```lua
UI.Themes.Register("flat", {
  label   = "Flat",
  palette = { bg = ..., pane = ..., nav = ..., border = ..., ... },  -- every UI.PALETTE key
  text    = { accent = ..., text = ..., label = ..., muted = ..., ... },  -- every UI.TEXT key
  fonts   = { face = <GameFontNormal's>, num = "Fonts\\ARIALN.TTF", sizes = { FONT = 13, ... } },
  pixel   = true, listStrata = "FULLSCREEN_DIALOG",
  skin    = nil,          -- function(frame, role, colours) or nil = UI.StylizeFrame's flat backdrop
  live    = nil,          -- function() -> partial { palette, text, fonts } (ellesmere: EUI getters)
})
UI.Themes.Validate(theme) -> true | false, problems   -- every token Style.lua defines is present
UI.Themes.Apply(key)      -- writes palette / text / fonts in place (as Theme_Flat does now), sets UI.PIXEL etc.
UI.Skin(frame, role)      -- roles: window, header, nav, pane, sheet, button, field, tooltip, clock, bar
```

- **When a theme applies.** Today the theme applies at file load. The registry applies
  `db.ui.theme` (default `"flat"`, declared with `MD:RegisterDefaults` in `UI/Themes.lua`) at
  `CORE_LOGIN` (`Core.lua:435`), before `MD_READY` builds the clocks. Windows are built on first
  open, so they already see the chosen theme. Two exceptions need a check: any frame built at file
  load, and the font objects, which are built once and resized in place by `UI.ApplyFonts`, so a
  face change works the same way. A theme change after login is **save, then reload** (the ElvUI
  convention). Live recolouring is extra work, offered only by `ellesmere` through
  `S.OnLooksChanged` plus the restyle registry.
- **`UI.Skin(frame, role)` replaces `UI.StylizeFrame(frame, P.x, P.border)` call by call.** The
  default skinner is exactly `StylizeFrame(frame, P[role], P.border)`, so each conversion is
  byte-identical under `flat`. `UI.pixelFrames` becomes `UI.skinned[frame] = role`, so
  `UI.RestylePixels` (`Style.lua:416`) can re-skin by role after a scale change or an Ellesmere
  colour change.
- **The `ellesmere` theme never calls EllesmereUI at load.** EllesmereUI's callback runs at its
  `PLAYER_LOGIN` (SKINNING_API.md "When your callback runs"). The theme reads `S` only once it has
  arrived, and if it never arrives (skinning off for SpellTuner, or EllesmereUI absent) it keeps
  the built-in palette. The global `EllesmereUI` is a host addon's table, not a client call. Allow
  it, `ElvUI` and `LibStub` in `tools/apicheck.py` for `Integrations/` files only, with a new
  allowlist next to `TOOLKIT` (`apicheck.py:80`). Everywhere else they stay findings.

### 4.3 How it stays testable

- `tools/themecheck.lua` (extend it). Each registered theme passes `Themes.Validate`. No UI file
  reads a token name no theme defines (the scan already exists for `UI.TEXT`). `UI.THEMED` is never
  set by a theme. Applying a theme before `CORE_LOGIN` raises. The stub counts `CreateFrame` calls
  made before `PLAYER_LOGIN`, which proves no styled frame is built before the theme applies.
- Run `navui`, `spellsui`, `replayui` and `minimapcheck` once per theme (`HARNESS_THEME`). Under
  `flat` the counts must equal today's. Under the others the suites must not raise, and painted
  text must stay ASCII with no bare pipe.
- Mockups first, as the author asked (memory: "mockups before UI builds"): one frame per theme of
  the Spells view, the Settings pane and the clock, added to `docs/mockups/`.

---

## 5. S3: feeds and surfaces (ElvUI, EllesmereUI, any broker)

### 5.1 Contract

A **feed** is one piece of information to show. A **surface** is a place that shows feeds. Today
the widget, the minimap button and the two ElvUI datatexts each build their own text and tooltip.
The ElvUI file's own comment asks that they "can never say different things"
(`ElvUIDatatext.lua:36-37`). Feeds make that structural.

```lua
-- UI/Feeds.lua (both main TOCs, after UI/Tip.lua; pure apart from reading MD state)
MD.Feeds.Register("clock", {
  label   = "SpellTuner",                      -- the name a host lists
  Text    = function(ctx) end,                 -- ASCII; colour codes allowed; no bare pipe.
                                               -- ctx = { valueHex = <host's value colour> | nil, plain = bool }
  Tooltip = function() end,                    -- UI/Tip.lua's line model ({ l, r, c, rc })
  Click   = function(button, mods) end,        -- default: toggle the window (out of combat on Forever, T70)
  icon    = <texture> | nil,
})
MD.Feeds.Register("regen", {...})              -- current mp5; "(5SR)" while the casting rate applies
MD.Feeds.Get(key), MD.Feeds.List()             -- surfaces iterate these
MD:Fire("FEED_CHANGED", key)                   -- the 0.5 s tick fires it only when Text(ctx) changed
```

- **Feed sources stay with their owners.** `clock` gets its text from S4's `ClockFormat` and its
  tooltip from `MD.MinimapLines` / `Tip:Clock` (the existing provided seam). `regen` takes TBC's
  `MD.Regen:Current()` / `InFSR()` and, on Forever, `MD.Pool:LastRegen()` plus the model's FSR
  state (`ManaModel.lua:161-164`), marked `~` as the clock is. **A feed never formats a secret.**
  In combat on Forever it shows the modelled or last plain value, never the client's live one.
- Later feeds: `budget` (`Engine/PullBudget.lua`'s "N more pulls"), `fight` (the last fight's
  summary line), `suggested` (the suggested rank of the last-cast family).

### 5.2 Surfaces

| Surface | File | Host API | Notes |
|---|---|---|---|
| Floating clock | `UI/ClockWidget.lua` (S4) | own frame | shows `clock`, plus `regen` as an optional second line |
| Minimap button | `UI/MinimapButton.lua` (exists) | own button | its tooltip already reads `MD.MinimapLines`; becomes `Feeds.Get("clock").Tooltip` |
| ElvUI datatexts | `Integrations/Surface_ElvUI.lua` (today's `ElvUIDatatext.lua`, moved) | `DT:RegisterDatatext(name, ..., ApplySettings)` | keeps native theming (`valueHex` from `ApplySettings`, `ElvUIDatatext.lua:53-55`); one datatext per feed |
| Any LDB display (**EllesmereUI DataBars**, ElvUI "Data Broker", Titan, ChocolateBar) | `Integrations/Surface_LDB.lua` | `LibStub:GetLibrary("LibDataBroker-1.1", true):NewDataObject(name, { type = "data source", text, label, icon, OnClick, OnTooltipShow })` | created at `MD_READY` (every addon has loaded by `PLAYER_LOGIN`, so a library from EllesmereUI or ElvUI is present); the object's `text` written on `FEED_CHANGED` only; EllesmereUI's LDB block watches `text`, `value`, `suffix`, `label`, `icon` (`Blocks/LDB.lua:52-55`) and strips colour codes by default (`LDBStripColors`, 60-66), so the text must read well without its colours |

Notes:

- **Duplicates under ElvUI.** With both surfaces on, ElvUI lists "SpellTuner" (native) and
  "LDB: SpellTuner Clock" (wrapped), because `SetupObjectLDB` registers every data source as
  `LDB_<name>`. ElvUI has no way to hide one. Name the LDB objects `SpellTuner Clock` and
  `SpellTuner Regen` so the list reads clearly, and say in Settings that ElvUI users should pick
  the native ones.
- **Load order.** Add `## OptionalDeps: ElvUI, EllesmereUI` to the Forever TOCs (TBC's already
  names ElvUI). The surfaces register at `MD_READY`, not at file load, so the order does not
  decide whether LibStub exists. EllesmereUI's block also listens for
  `LibDataBroker_DataObjectCreated` (`Blocks/LDB.lua:406`), so late creation works.
- **Host detection** goes through the adapter: `MD.API.AddonLoaded(name)` binds
  `C_AddOns.IsAddOnLoaded` (Forever) or `IsAddOnLoaded` (TBC) in `Client/API_*.lua`. A surface
  that finds no host registers nothing and logs one debug line.
- **A setting per surface**, `db.feeds = { elvui = true, ldb = true }`, declared in
  `UI/Feeds.lua` and shown as one INTEGRATIONS pane in Settings -> General, which lists what was
  found ("ElvUI: 2 datatexts", "Broker: 2 objects; shown by EllesmereUI DataBars").

### 5.3 How it stays testable

- Stop excluding `Integrations/` in `tools/harness.lua:69-72`. With no host present the files must
  load and do nothing, which is itself an assertion.
- `tools/fakehosts.lua`: a fake `ElvUI` (`unpack(ElvUI)` gives `E`, and `E:GetModule("DataTexts")`
  records every `RegisterDatatext` call with its arguments), and a fake `LibStub` with a minimal
  LDB-1.1 (`NewDataObject`, `DataObjectIterator`, attribute-changed callbacks).
- `tools/surfacecheck.lua` (both flavours):
  - each feed's `Text` is ASCII with no bare pipe for every clock mode (driven by S4's fixture
    states);
  - ElvUI receives exactly two datatexts and `ApplySettings` recolours the value;
  - LDB objects exist only when the fake library is present, and their `text` changes only on
    `FEED_CHANGED`;
  - `OnTooltipShow` writes the same lines as the minimap tooltip;
  - nothing raises with no host;
  - on Forever, `regen` never reads `MD.Regen`.
- Count it in `tools/data/expected-counts.json` as `surfacecheck/tbc` and `surfacecheck/forever`.

---

## 6. S4: the clock (state -> format -> render), customizable

### 6.1 Three layers

1. **Source** (one per line, through `MD:Provide("ClockSource", fn)`):
   `MD.ClockSource(now) -> state`, a normalized table:
   ```lua
   state = {
     mode = "oom"|"hold"|"full"|"warmup"|"ooc"|"fullnow"|"nodata",
     tto, ttf, rest,              -- seconds or nil (nil renders "--", never 0)
     bound, bounded, stable,      -- TBC's confidence gate (TTO.lua's latch) / Forever: bounded = false
     shownValue, arrow,           -- TBC's latched value and "^" "=" "v" (TTO.lua Arrow, 311); Forever: tto/ttf, nil
     cd = { short, tto } | nil,   -- TBC's mana cooldown segment
     modelled = bool,             -- Forever's "~"
     pct = number|nil,            -- for visibility (Forever: the model's, never the client's secret)
     fsr = { remaining, total },  -- TBC: MD.Regen:FSRRemaining(); Forever: lastSpend + 5 - now (ManaModel.lua:161)
     inCombat, spend, regen,
   }
   ```
   TBC's provider is `Engine/TTO.lua`. It already holds `state` and `disp`, so it exports them;
   the latch and the arrow stay where they are. Forever's provider is
   `Engine/ManaPool_Forever.lua`, a thin wrapper on `Pool:Project` (76).
2. **Format** (pure): `UI/ClockFormat.lua`, both main TOCs.
   `ClockFormat.Text(state, spec, colours) -> string`. The `spec` is the customizable part:
   ```lua
   spec = {
     label   = "word"|"short"|"none",     -- "OOM"/"FULL", "O"/"F", nothing
     time    = "mss"|"seconds"|"auto",    -- 1:20 / 80s / TBC's "1:20 above 60s, 45s below"
     round   = 1|5,                       -- Forever rounds to 5 s (ManaModel.lua Round5)
     arrow   = true, rest = true, cooldown = true,
     tilde   = "modelled",                -- "~" only when state.modelled
     bands   = { crit = 20, warn = 60 },  -- seconds; tokens crit/warn/good/mana/muted from UI.TEXT
   }
   ClockFormat.PRESETS = { tbc = {...}, forever = {...} }   -- today's two outputs, exactly
   ```
   `MD:GetDisplayString(valueHex)` becomes
   `ClockFormat.Text(TTO state, PRESETS.tbc, { value = valueHex })`, and `ManaModel.Text(state)`
   becomes `ClockFormat.Text(state, PRESETS.forever)`. Both keep their names for their readers
   (the ElvUI file, the minimap, `clockcheck`, `ttocheck`). The colour literals at `TTO.lua:330-335`
   become tokens. That needs four new tokens, `crit` / `warn` / `good` / `manaText`, whose TBC
   values are exactly the literals (the T69 pattern for legacy tokens).
3. **Render**: `UI/ClockWidget.lua`, both main TOCs. It replaces the frame code in
   `UI/Widget.lua` and `UI/Clock_Forever.lua`. Those two files keep only their line-specific parts
   (TBC's pulse on the 30 s crossing and the `MD:UpdateVisibility` entry point; Forever's hover
   lines), or are folded in. One frame, one visibility owner (CLAUDE.md "widget visibility has a
   single owner"), asking `MD.Visibility.Want(pct, shown, inCombat, unlocked, mode)` with a new
   optional `mode` (`"auto"` = today's 90/95 band, `"combat"`, `"always"`).

### 6.2 What "customizable" means (one settings record)

```lua
db.clockStyle = {                 -- declared by UI/ClockWidget.lua with MD:RegisterDefaults
  layout   = "line",              -- "line" (today: text over a thin bar), "bar" (text inside a tall bar),
                                  -- "big" (a large time and a small label), "text" (no panel, no bar)
  width = 180, height = 30, scale = 1, fontSize = 13, font = "theme"|"numbers",
  bar      = "fsr"|"mana"|"none", -- TBC default fsr; Forever default mana (MD.API.DrawUnitPower, the one
                                  -- sanctioned secret path); fsr possible on Forever from the model's lastSpend
  panel    = { alpha = 0.96, border = true },
  text     = <ClockFormat spec>,  -- the segments above
  show     = "auto"|"combat"|"always",
  locked = true, point = {...}, tooltip = true, clickOpens = true,
  pulseAt  = 30,                  -- seconds; TBC's one-per-fight flash (Widget.lua:140-147), now a setting
  icon     = true,                -- the mana cooldown's icon beside "inn 2:10" (MD.API.SpellTexture)
}
```

- **Migration** (one-shot, at `CORE_LOGIN`, tested by `tools/migrate`):
  - TBC `db.pos` / `db.locked` / `db.showRest` / `db.showCooldown` / `db.widgetTooltip` move to
    `db.clockStyle.point` / `locked` / `text.rest` / `text.cooldown` / `tooltip`.
  - Forever `db.clock.{shown, locked, point}` move to `show` / `locked` / `point`.
  - The old keys are kept for one version so a downgrade does not lose a position.
- **Settings pane**: MANA CLOCK grows into its own view, Settings -> Clock, with a **live
  preview**. The preview feeds `ClockFormat` and the widget fixed sample states (OOM 1:20 falling,
  OOM 0:15 critical, hold, FULL 0:45, warm-up), which works only because format and render are
  pure functions of a state. Today's preview (`Clock:Preview`, `Clock_Forever.lua:287`;
  `ForceWidgetPreview`, `Widget.lua:178`) becomes "show the widget with sample states for 60 s".
- **Themes reach the clock** through `UI.Skin(widget, "clock")` and `UI.Skin(bar, "bar")`. The
  `ellesmere` theme can hand the bar to `S.ApplyBarFill`.
- **Surfaces share the format.** The ElvUI datatext and the LDB object show
  `ClockFormat.Text(state, db.clockStyle.text, { value = hostHex })`. A user who turns the rest
  segment off sees that on every surface.

### 6.3 How it stays testable

- **Capture the goldens before the first edit**: `tools/clockfmt.lua` (both flavours) records, for
  a fixed table of states, the current output of `MD:GetDisplayString(nil)`,
  `MD:GetDisplayString("|cff16c3f2")` and `ManaModel.Text(state)`. The states cover every mode,
  bounded and confident, stable or not, each arrow, the cooldown segment, the rest segment's 25 %
  rule, `nil` values, and above 10 minutes. After the split the `tbc` and `forever` presets must
  reproduce the goldens byte for byte.
- Property checks over the cross product of spec options: ASCII, no bare pipe, `nil` never prints
  `0`, the `~` only when `modelled`.
- `ttocheck` (TBC latch and arrow) and `clockcheck` (29 on Forever) unchanged.
- `tools/clockui.lua`: each `layout` painted under the stub's geometry (`S.Geometry(true)`, T54),
  checking that the text fits the frame at font offsets -2..+2, the bar is hidden for `bar = "none"`,
  the visibility modes behave, and Show/Hide is called only from the owner (count calls on the
  frame).

---

## 7. Order of work

The author's rule is at most three tasks in parallel, isolated worktrees, one integrator, mockups
before UI. Each wave ends with `make check` green. The integrator edits the TOCs,
`expected-counts.json`, CLAUDE.md, TOOLS.md, DECISIONS.md and TESTING.md
(`PLAN-refactor-ux.md` section 3.4).

| Wave | Task | Behaviour change | Depends on |
|---|---|---|---|
| **N1** (extractions, byte-identical) | **N1a** `UI/ClockFormat.lua` + `ClockSource` providers; `GetDisplayString` / `ManaModel.Text` as wrappers; the four colour tokens; `tools/clockfmt.lua` goldens captured first | none | - |
| | **N1b** `UI/Feeds.lua` (`clock`, `regen`); `ElvUIDatatext.lua` -> `Integrations/Surface_ElvUI.lua` reading feeds; harness loads `Integrations/`; `tools/fakehosts.lua`, `tools/surfacecheck.lua` | none on TBC | - |
| | **N1c** `Spells/Profiles.lua` + the two druid profiles; `SM.HOT_INDEX`, `SP.BINDABLE`, `SV.FAMILIES`, `FAMILY_KEY` / `FAMILY_TYPE` (Kit_Forever and Stream_Forever), `MC.byClass`, `IN_FSR_TALENT`, the crit school all *derived* from the profile; `tools/profilecheck.lua` | none | - |
| **N2** (visible; mockup M7 "clock layouts" and M8 "Settings -> Clock / Integrations" first) | **N2a** `UI/ClockWidget.lua`, one renderer for both lines; `db.clockStyle` + migration; `Visibility.Want` mode; Settings -> Clock with preview | new looks (default = today's) | N1a |
| | **N2b** `Integrations/Surface_LDB.lua`; ElvUI surface on the Forever TOCs (`OptionalDeps`); `MD.API.AddonLoaded`; the apicheck host allowlist for `Integrations/`; INTEGRATIONS pane | EllesmereUI DataBars and any broker display show the clock and regen | N1b |
| | **N2c** `isDruid` gates -> `MD.Profile:Can(cap)`; "Druid-only" texts -> per-capability texts (DECISIONS line) | wording for non-druids only | N1c |
| **N3** (mockup M9 "four themes" first) | **N3a** `UI/Themes.lua`; `Theme_Flat` registered; application at `CORE_LOGIN`; `UI.Skin(frame, role)` with `StylizeFrame` callers converted file by file; `themecheck` per theme | none (flat) | N2a for the clock role |
| | **N3b** `Integrations/Skin_EllesmereUI.lua` + `UI/Theme_Ellesmere.lua` (live getters, built-in fallback) | new theme | N3a |
| | **N3c** engine: `hotSlots` and kit `cd` replace `HOT_INDEX`'s literal and `SPELL_CD`; `KitEntryFor[type]` in `Kit_Forever.lua`; byte-identical on `solvercheck`, `restcheck`, `replaycheck`, `coachforever`, `practiceforever` | none | N1c |
| **N4** | **N4a** `UI/Theme_Classic.lua`, `UI/Theme_Retail.lua` (each texture confirmed by a probe line on both clients) | new themes | N3a |
| | **N4b** `Data/Profile_Priest_Forever.lua`: tooltips and rail already work; the profile adds names, `critSchool = 2`, the kit for direct + Renew; `caps.simulate` only once A11 lands | priest on Forever gets suggested ranks and the kit | N2c, N3c |
| | **N4c** A11: the engine, planner, practice and replay window read the kit (`kit[form][id].family` / `.rank`) instead of `MD.SpellData` (~50 sites); `Kit.Restore`'s index becomes the only `SpellData` stand-in | none | N3c |
| **N5** | new kit types `absorb`, `multi`; `SV.Deposits` and `LandCast` branches; `caps.coach` for priest (solver strategies only); Shaman and Paladin Forever profiles; TBC profiles for other classes only with measured data | coaching for a second class | N4b, N4c |

Why this order:

- N1 changes no output. Each of its three tasks creates its own goldens, so later visible work has
  an oracle.
- The clock and the integrations come before themes because they are what the author asked for by
  name, and they are small.
- Themes touch every UI file (the `StylizeFrame` to `UI.Skin` conversion), so they come once the
  clock widget, which is one of those files, has stopped moving.
- The second class comes last because the engine generalisation (A11) is the largest piece. The
  refactor plan deferred it for exactly this moment ("Do it when a second class or Wild Growth
  needs it", section 6). Until then a Forever priest already gets the clock, tooltips, the rail and
  the integrations, all of which are class-generic today.

---

## 8. Rules each seam must keep (from CLAUDE.md and the plan's section 2)

- **Client reads through `MD.API`.** Host addons (`ElvUI`, `EllesmereUI`, `LibStub`) are reached
  only from `Integrations/`, allowlisted there and nowhere else. Host detection goes through
  `MD.API.AddonLoaded`. Nothing registers `COMBAT_LOG_EVENT_UNFILTERED` on Forever.
- **No libraries shipped.** LDB is used only when present. `release.sh` builds from the TOC lists,
  so nothing new is copied.
- **ASCII, no bare pipe** in every feed text, clock format and theme label (`tools/textcheck.py`
  already covers the string constants; `clockfmt` and `surfacecheck` cover computed strings).
- **No shared file branches on `MD.API.client`** (apicheck rule 10). Flavour differences are
  installed values: the clock source, the profile file, the feed's regen reader.
- **TBC behaviour changes only by a documented decision.** N1 and N3c are byte-identical. Each
  visible TBC change (the clock's new defaults if the author wants them, the per-capability
  wording, the theme picker) gets a DECISIONS entry.
- **The causality invariant** (`Engine/SimPlanner.lua` header; `coachforever`, `solvercheck`)
  holds through N3c and N5. New kit types decide on the present plus trailing damage only.
- **One visibility owner per clock frame.** The shared renderer owns Show/Hide, and the TBC entry
  point `MD:UpdateVisibility` delegates to it.
- **Secrets.** A feed or clock state on Forever never carries a client-secret number. `pct` comes
  from the model, and the bar's real mana is drawn only through `MD.API.DrawUnitPower`.

## 9. Open questions for the author

1. Clock defaults: keep today's look as the default on both lines, with the new layouts opt-in
   (recommended), or switch to a new default?
2. Themes: is "save and reload" acceptable for switching styles (recommended, like ElvUI), or must
   the switch be live?
3. EllesmereUI: should the `ellesmere` theme also hand SpellTuner's windows to EllesmereUI's own
   skinner (`S.Shell` / `S.Button`, which then follow every EllesmereUI theme tweak), or only copy
   its colours and font? The first matches EllesmereUI exactly, but SpellTuner's look then depends
   on EllesmereUI's code.
4. ElvUI users would see the clock twice in ElvUI's datatext list (native and "LDB: ..."). Keep
   both, or turn the LDB surface off by default when ElvUI is loaded?
5. Second class: Priest first on Forever (the most heal shapes, and Forever's new ranked heals), or
   Shaman / Paladin, which need fewer new kit types (Chain Heal aside)?
