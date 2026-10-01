# R-ellesmere: an EllesmereUI integration for SpellTuner

Research only. Nothing in the repository was edited. The EllesmereUI files cited below are under
`/mnt/e/Blizzard/World of Warcraft/_classic_beta_/Interface/AddOns/` (written `EUI:` here). The
installed version is **EllesmereUI 9.3.4, 2026-09-30** (`EUI:EllesmereUI/CHANGELOG.md:3`). SpellTuner
paths are relative to the worktree.

---

## 0. The answer in brief

- **It is Forever-only.** EllesmereUI ships for retail 12.x and WoW Forever only. Every TOC lists
  `## Interface: 120000, 120001, 120005, 120007, 120100, 16001`, and `EllesmereUI_ClientGate.lua`
  switches the whole suite off on any other client (section 1). No TBC copy exists anywhere. On TBC,
  the ElvUI datatext stays as it is.
- **EllesmereUI has no datatext API of its own that a third-party addon can use.** Its DataBars
  module keeps its block registry private (`ns.BlockFactories`). The supported route in is the
  **"Broker Plugin" block**, which shows any **LibDataBroker-1.1** data object. EllesmereUI ships
  LDB itself, in the parent addon (`EUI:EllesmereUI/EllesmereUI.toc` Libs section, and
  `EllesmereUIDataBars.lua:3134-3146`). SpellTuner can publish two data objects, `SpellTuner` (the
  OOM clock) and `SpellTuner Regen` (mp5), without shipping any library. It borrows the copy that
  LibStub already holds. These are the same two names as the ElvUI datatexts.
- **Three more public surfaces are worth using:**
  - `EllesmereUI.RegisterSkin`, the documented skinning API in `SKINNING_API.md`.
  - `EllesmereUI:RegisterUnlockElements`, so the clock gets a mover in EllesmereUI's `/unlock` mode.
  - The minimap-button collector. It already picks up `SpellTunerMinimapButton` by its name. Two
    small fixes make SpellTuner's button behave once it has been collected.
- **What is closed to third-party addons:**
  - The options sidebar. `RegisterModule` only accepts callers on a whitelist of EllesmereUI folders.
  - The profile system. `ADDON_DB_MAP` is a static list.
  - The DataBars internals.
- **Recommended order:**
  - **P1** (the request): the brokers, with an offline stub and suite.
  - **P2**: the unlock-mode element and the minimap fixes.
  - **P3**: an optional "follow EllesmereUI look" mode for the clock. It reads the skin facade's
    getters, and it ties in with the UI-styles and clock-customisation topics.

---

## 1. Where EllesmereUI exists

| Fact | Evidence |
|---|---|
| Interface list: retail 12.x and Forever 16001, never 20506 | every `EUI:EllesmereUI*/*.toc` line 1, e.g. `EllesmereUI.toc:1`, `EllesmereUIDataBars.toc:1` |
| Gate: 16000-19999 sets `EUI_CLIENT_FOREVER`, >= 120100 runs, anything else sets `EUI_CLIENT_BLOCKED` and every file returns at line 1 | `EUI:EllesmereUI/EllesmereUI_ClientGate.lua:22-36`; every suite file starts `if EUI_CLIENT_BLOCKED then return end` |
| `EllesmereUI.IS_FOREVER` is the suite's own flag | `EUI:EllesmereUI/EllesmereUI_Lite.lua:18` |
| No TBC copy | `/home/penek/projects/addons` has Cell, ElvUI*, LibSharedMedia, SpellTuner, WTF, and no Ellesmere folder. `_anniversary_/Interface/AddOns` has ElvUI, ElvUI_BenikUI, SpellTuner and no Ellesmere folder |
| Forever-only module | `EllesmereUIForeverEssentials_Camelot.toc` (`## Interface: 16001`, `## AllowLoadGameType: camelot`) |
| **The author has it switched off today** | `_classic_beta_/WTF/Account/124250034#1/70/Healroot-Deathbloom/AddOns.txt`: every `EllesmereUI*: disabled`, `SpellTuner: enabled`. `SavedVariables/EllesmereUIDataBars.lua` is an empty table (32 bytes) |

**Conclusion:** the integration is **Forever-only**. It goes in the Forever TOCs
(`SpellTuner_Mainline.toc`, `SpellTuner.toc`) and never in `SpellTuner_TBC.toc`. To test in game,
the author has to turn EllesmereUI on (at least the parent, DataBars and Options; Minimap and
BlizzardSkin for P2/P3).

---

## 2. What EllesmereUI offers a third-party addon

### 2.1 DataBars: one way in, the LibDataBroker block

- **The block registry is private.**
  - `EllesmereUIDataBars.lua:207-230`: `ns.BLOCK_TYPES` is a local list, and `"ldb"` / "Broker
    Plugin" is at line 228.
  - `:272`: `ns.BlockFactories = {}`, filled by `Blocks\*.lua`.
  - `:19-48`: "API HANDOFF (everything the options file may call; nothing else)". The module's
    `ns` can be reached through `EllesmereUI._ModuleNS[ADDON_NAME] = ns` (`:61`). That is an
    underscore-private registry for EllesmereUI's own load-on-demand options files. **SpellTuner
    must not inject a block type there.** Nothing promises it will stay stable, and on Forever the
    picker even removes types (`:276-286`).
- **The supported route is LDB.** `Blocks/LDB.lua` is "LibDataBroker plugin block factory: one
  block type for every data source". Its contract, cited by line:
  - `:32-41`: three rules.
    1. EllesmereUI never writes to the data object.
    2. Every call into the plugin goes through `pcall` (OnEnter, OnLeave, OnClick, OnTooltipShow,
       OnMouseWheel).
    3. The width is measured live, and there is an optional Max Width clamp.
  - `:58-61`: what triggers a repaint. The keys `text, value, suffix, label, icon, iconR, iconG,
    iconB, iconCoords`, through the per-name callback `LibDataBroker_AttributeChanged_<name>`
    (`:132-145`).
  - `:63-72`, `:202`: **colour codes are stripped by default** (`stripColors = true`,
    `EllesmereUIDataBars.lua:266`). The text takes the block's Text Color, and the accent on hover
    (`:228-236`). A plugin cannot colour its text unless the user turns stripping off.
  - `:74-88`: the text shown is `obj.text`, or else `value .. " " .. suffix`. `label` is prefixed
    only with "Show Label" on (`:196-201`).
  - `:147-159`: **the icon tint `iconR/G/B` is honoured while the user leaves the block's Icon
    Color untouched.** This is the one colour channel a plugin keeps.
  - `:292-355`: tooltips.
    - `OnEnter`/`OnLeave`: the plugin draws its own.
    - Otherwise `OnTooltipShow(GameTooltip)`: EllesmereUI owns, anchors and flips the GameTooltip
      (`:327-345`).
    - Otherwise EllesmereUI's own tooltip shows the name and text.
  - `:367-380`: `OnClick(button, mouseButton)` is forwarded through `pcall`.
  - `:170-184`: a block whose chosen source is not registered **collapses** (width 0, no dead
    slot). Turning SpellTuner off costs the bar nothing.
  - `:386-394`, `:396-409`: a source that registers **later** (a later or load-on-demand addon)
    binds when `LibDataBroker_DataObjectCreated` fires. Load order does not matter.
- **EllesmereUI ships the library itself.** `EllesmereUIDataBars.lua:3134-3146`: "The suite ships
  the library itself (EllesmereUI parent, beside the CallbackHandler it needs) ... every broker we
  read sorts after EllesmereUIDataBars". It is resolved with
  `LibStub:GetLibrary("LibDataBroker-1.1", true)`. The parent TOC loads `Libs\LibStub`,
  `Libs\CallbackHandler-1.0` and `Libs\LibDataBroker-1.1` before any suite file (`EllesmereUI.toc`
  Libraries section).
- **The library writes nothing on an equal value.** `EUI:EllesmereUI/Libs/LibDataBroker-1.1/LibDataBroker-1.1.lua:24`
  is `if attributestorage[self][key] == value then return end`. A 0.5 s write of an unchanged
  string fires no callback and causes no relayout. `NewDataObject` returns nil for a name that
  already exists (`:37`).
- **Placement belongs to the user, inside EllesmereUI's profile.** The block's settings (`source =
  "SpellTuner"`, Max Width, colours) live in `EllesmereUIDataBarsDB`'s profile
  (`EllesmereUIDataBars.lua:292-294`; `ldb` defaults at `:266`). SpellTuner never touches them, and
  they follow EllesmereUI's profile switches, export and import for free (`_G._EDB_Apply`,
  `:3229-3241`).

### 2.2 Skinning API (documented, public, additive)

- `EUI:EllesmereUI/SKINNING_API.md` (whole file):
  - `## OptionalDeps: EllesmereUI`, then `EllesmereUI.RegisterSkin("MyAddon", function(S) ... end)`.
  - The callback runs once per session at `PLAYER_LOGIN`, or at once for a late registration. It
    runs inside `pcall`, and not at all if the user has turned third-party skinning off for that
    addon.
  - Primitives: `S.Shell`, `S.Panel`, `S.Button`, `S.Font`, `S.ApplyBarFill`, ...
  - Getters: `S.GetStyle()`, `S.GetAccentColor()`, `S.GetPanelColor()`, `S.GetFont()`,
    `S.OnLooksChanged(fn)`. `S.apiVersion == 2`.
- Stub that queues registrations: `EUI:EllesmereUI/EllesmereUI_SharedHelpers.lua:48-74`. The first
  registration under a name wins.
- Facade and dispatch: `EUI:EllesmereUIBlizzardSkin/EllesmereUIBlizzardSkin_SkinAPI.lua:49-115`,
  `:125-178`. The facade exists only when the **Blizz UI Enhanced** child is loaded
  (`if not (EUI and WSkin) then return end`, `:29`).
- **Caution.** `S.Panel` calls `FadeRegions(frame, keep)`
  (`EUI:EllesmereUIBlizzardSkin/EllesmereUIBlizzardSkin_WindowEngine.lua:412-429`), which sets alpha
  0 on **every texture region** of the frame except its own background. On the clock
  (`UI/Clock_Forever.lua:203-256`) that would hide `barBack`, the 1-px black backing under the
  real-mana bar (a texture of the widget, `:248-251`). The clock's own `Snap()` re-runs
  `UI.StylizeFrame` whenever the scale changes (`:195-201`, `:263`), so the two styles would fight.
  **Use the getters, not `S.Panel`/`S.Shell`, on SpellTuner frames** (section 3.5).

### 2.3 Unlock mode (movers): open to any addon

- `EUI:EllesmereUI/EUI_UnlockMode.lua:1-7`: "Elements from any addon register via
  EllesmereUI:RegisterUnlockElements()".
  - `:20-50`: the registry, on the `EllesmereUI` global, with the short aliases
    `savePos/loadPos/clearPos/applyPos`.
  - `:2270-2284` and `:11196-11230`: late registrations are hooked, and they spawn a mover even
    while unlock mode is already open.
- The field whitelist is `EUI:EllesmereUI/EllesmereUI.lua:2280-2377` (`EllesmereUI.MakeUnlockElement`).
  Required: `key, label, group, order, getFrame, getSize, savePos, loadPos, clearPos, applyPos`.
  Optional: `isHidden`, `noResize`, ...
- Saved positions are converted to **CENTER/CENTER on UIParent** before `savePosition` is called
  (`EUI_UnlockMode.lua:5085-5105`). The mover moves the frame with
  `SetPoint(anchor, UIParent, "CENTER", x, y)` (`:5066-5079`). That is the same shape as the
  clock's `db.clock.point = { point, nil, relPoint, x, y }` (`UI/Clock_Forever.lua:179-187`,
  `:217-221`).
- A mover is skipped only when `isHidden()` is true (`EUI_UnlockMode.lua:6857-6872`). A frame that
  exists but is hidden is fine.
- Session listener: `EllesmereUI:RegisterUnlockModeListener(owner, fn)`, called as
  `fn(active, closeAction)` (`EUI_UnlockMode.lua:58-85`). This lets SpellTuner show the clock
  (preview) while the user arranges the UI.
- The user opens it with `/unlock` (`EUI:EllesmereUI/EllesmereUI.lua:3122`).

### 2.4 Minimap button collector (automatic, no API)

- `EUI:EllesmereUIMinimap/EllesmereUIMinimap.lua:1282-1330` (`GatherMinimapButtons`) scans
  `Minimap:GetChildren()`. It takes every **named `Button` whose name does not end in digits and
  is at least 20 px wide**, plus `LibDBIcon10_*`.
- `SpellTunerMinimapButton` (`UI/MinimapButton.lua:73-74`, 31 x 31, parent `Minimap`) qualifies.
  Its flyout label is "SpellTuner" (`:384-387` strips the `MinimapButton` suffix).
- When collected:
  - The button is reparented into the flyout grid, resized, and set to DIALOG strata (`:474-503`).
  - Its "junk" textures are faded (`:290-368`). These are the `MiniMap-TrackingBorder` overlay and
    the `UI-Minimap-ZoomButton-Highlight` highlight, both of which SpellTuner uses
    (`UI/MinimapButton.lua:80-85`).
  - Its icon is re-anchored. The icon is found as `btn.icon`/`btn.Icon`, or else as the first
    shown non-junk texture (`:516-532`).
- Rescans run on every `ADDON_LOADED` (`:4870-4890`).
- **Two things in SpellTuner's button fight the collector:**
  - `Reposition()` re-anchors the button to `Minimap` (`UI/MinimapButton.lua:26-33`). It runs from
    `MD:UpdateMinimapButton()` (`:123-127`), for example when Settings -> Windows toggles the
    button, and that pulls the button out of the flyout.
  - The angle drag (`:100-105`) does the same thing.
- **The button is created at `MD_READY`, which fires at `PLAYER_LOGIN`** (`Core.lua:420-437`).
  That is probably after EllesmereUI's first scan. A later `ADDON_LOADED` (SpellTuner's own
  load-on-demand modules at `CORE_READY`, or any Blizzard load-on-demand addon) picks it up. **This
  has to be checked in game.**
- `hideAddonCompartment = true` by default (`:108-117`). The addon compartment is not a useful
  route.

### 2.5 Closed or internal: do not use

| Surface | Why not | Evidence |
|---|---|---|
| A SpellTuner page in the EllesmereUI options | `RegisterModule` reads the caller's folder from `debugstack` and returns silently unless it is on a hard-coded `ALLOWED` list of Ellesmere folders | `EUI:EllesmereUI/EllesmereUI_Panel.lua:3842-3880` |
| Taking part in EllesmereUI profiles | `ADDON_DB_MAP` is a local static table | `EUI:EllesmereUI/EllesmereUI_Profiles.lua:39-71` |
| Partner installer API | For installer packs that import whole EllesmereUI profiles, not for us | `EllesmereUI_Profiles.lua:4878-4920`, `:5031-5044` |
| Injecting a DataBars block type | Private `ns`, see 2.1 | `EllesmereUIDataBars.lua:19-48`, `:61`, `:272` |
| The ManaRegenSpark engine on SpellTuner's bar | `EllesmereUI.ManaRegenSpark.Attach(key, bar, ticks)` / `SetMana(key, isMana)` is reachable, but its doc names only two hosts (`"erb"`, `"uf"`). It is an internal contract, and it also registers events on our behalf | `EUI:EllesmereUI/EllesmereUI_ManaRegenSpark.lua:1-33`, `:214-277` |

**Overlap the author should know about:** on Forever, EllesmereUI already draws a **five-second-rule
spark** (`EllesmereUI_ManaRegenSpark.lua`, "WoW FOREVER ONLY", using the same "mana is SECRET, never
compare it" discipline as SpellTuner) and a **spell-cost prediction** segment
(`EllesmereUI_SpellCostPrediction.lua:1-31`) on its Resource Bars and Unit Frames mana bars. Neither
projects time to OOM. SpellTuner's clock adds something EllesmereUI lacks, and the broker text
appears next to EllesmereUI's own spark without either drawing over the other.

---

## 3. Proposal: how SpellTuner integrates

### 3.1 One file, Forever TOCs only, inert without EllesmereUI

- **New file:** `Integrations/EllesmereUI_Forever.lua`, listed in **both** `SpellTuner_Mainline.toc`
  and `SpellTuner.toc` right after `UI\MinimapButton.lua`. It needs `MD.Pool`, `MD.Clock`, `MD.Tip`,
  `MD.ManaModel`, `MD:ToggleDashboard` and `MD:OpenDashboardSettings`, and all of these are loaded
  by then (`SpellTuner_Mainline.toc:18-35`). Because its `MD:OnTick` handler is registered after
  `Engine/ManaPool_Forever.lua`'s and `UI/Clock_Forever.lua`'s, it reads the pool after the pool's
  own tick.
- **TOC header:** `## OptionalDeps: EllesmereUI` in both Forever TOCs. This is the pattern the
  skinning guide asks for (`SKINNING_API.md:10-14`). It makes the parent's LibStub, LDB,
  `RegisterSkin` stub and unlock registry exist before our files run, and changes nothing when
  EllesmereUI is absent. The children (DataBars, Minimap, BlizzardSkin) do not need listing: the
  LDB block binds late (2.1), and RegisterSkin queues (2.2).
- **Gate:** the whole file is inert unless `type(EllesmereUI) == "table"` (for the unlock and skin
  parts), or `LibStub` answers `LibDataBroker-1.1` (for the brokers). Every foreign call goes
  through `pcall`. Nothing is written to any EllesmereUI table or SavedVariables.
- **The brokers are published whenever LDB is present.** EllesmereUI's DataBars is the display we
  target, but any LDB display on Forever (a Titan-like bar, if one appears) shows them for free.
- **The "no libraries" rule holds.** SpellTuner ships no LibStub or LDB. It borrows the instance
  the host already loaded, and with no host there is nothing to publish to. This is worth one line
  in `docs/DECISIONS.md`.
- **The adapter rule.** `EllesmereUI` and `LibStub` are not client API. Under `tools/apicheck.py`
  rule 1 they would be reported as "unknown" in any Forever file. Proposed **rule 11**: a
  `FOREIGN = {"EllesmereUI", "LibStub"}` set, allowed only under `Integrations/` (with a selftest
  fixture line). Do not dodge the check with `_G.EllesmereUI`. Client reads (the addon's loaded
  state and version for the dump) stay on `MD.API.IsAddOnLoaded` / `MD.API.AddOnMetadata`
  (`Client/API_Forever.lua:10-14`).

### 3.2 What the brokers show

| Object | `type` | `text` (ASCII, never a bare pipe) | `icon` / tint | Click |
|---|---|---|---|---|
| `SpellTuner` | `data source` | exactly the clock's string: `MD.ManaModel.Text(MD.Pool:Project(now))` (`Engine/ManaModel.lua:280-295`), e.g. `~OOM 1:20  rest 2:10`, `~FULL 0:45`, `~FULL`, `~OOM ...` | `Interface\Icons\Spell_Shadow_Manaburn` (the minimap button's, `UI/MinimapButton.lua:89`). The tint carries the state, because colour codes in the text are stripped (2.1): `fullnow/ooc/full` the `mana` token, `warmup/hold` muted, `oom` with `tto > 60` amber, `oom` with `tto <= 60` red. The thresholds are presentation only; the model is untouched | Left: `MD:ToggleDashboard()`. Right: `MD:OpenDashboardSettings()`. **Refused in combat**, as the clock refuses (`UI/Clock_Forever.lua:224-232`), because the window hides in combat (decision 4) |
| `SpellTuner Regen` | `data source` | `Regen 123` out of combat. In combat `Regen ~123`, because `ManaRegen()` is secret in combat and the pool keeps the last plain reading (`Engine/ManaPool_Forever.lua:16-18`, `:85-89`, `:158`). ` (5SR)` while `now < model.lastSpend + 5` (`Engine/ManaModel.lua:22`, `:92`). The rate is `casting` inside the rule and `base` outside, times 5 (`m.base`/`m.casting` are per second, as the clock's `Rate` shows, `UI/Clock_Forever.lua:95-98`). `Regen --` before the first reading | same icon; tint amber inside the 5SR | same |

- **Quick-open** is the click on either block. A third, icon-only `launcher` object
  (`SpellTuner Window`) is cheap to add for users who want a button without text. LDB.lua shows an
  object with no text as its icon alone (`:186-204`, `:206-223`). This is optional.
- **Updating.** In `MD:OnTick` (0.5 s), assign `text` and `iconR/G/B`. The library drops equal
  writes (`LibDataBroker-1.1.lua:24`), so DataBars repaints only on a real change. Do not add a
  ticker of our own.
- **Tooltip.** Use `OnTooltipShow(tt)`, so DataBars anchors and flips the GameTooltip (LDB.lua
  `:327-345`) and EllesmereUI's tooltip reskin applies. Fill it with
  `MD.Tip:Render(tt, lines)` (`UI/Tip.lua:65-82`), where the lines are
  `MD.Clock:HoverLines(GetTime())` (`UI/Clock_Forever.lua:145-168`) with its last pair replaced by
  `Left-click: open the window` / `Right-click: Settings` / `(not in combat)`. `Render` does not
  call `Tip:Skin`, so EllesmereUI's tooltip skin and SpellTuner's flat skin cannot both draw on it.
  Do **not** use `OnEnter`: DataBars would then hand the tooltip entirely to us (`:322-326`).
- **Width.** Broker text has no fixed width, and DataBars measures it live (LDB.lua `:39-41`,
  `:272-281`). The clock string changes length between `~FULL` and `~OOM 1:20  rest 2:10`. TESTING
  should tell the user to set the block's **Max Width** (about 110-120 px at the default font), or
  offer a "short" variant without the rest segment (`db.eui.short`). That variant ties in with the
  clock-customisation topic: the brokers must call **the same formatter** the clock calls, so any
  format option reaches all three surfaces.
- **One string, three places.** The floating clock, the broker and the minimap tooltip must never
  disagree. The tooltip already shares `Clock:SummaryLines` (`UI/Clock_Forever.lua:102-141`). The
  broker uses `ManaModel.Text` too, and the suite asserts it (4.2).

### 3.3 Unlock mode: the clock gets an EllesmereUI mover (P2)

```lua
-- Integrations/EllesmereUI_Forever.lua (sketch, ASCII only)
local _, MD = ...
local function EUI() return type(EllesmereUI) == "table" and EllesmereUI or nil end

local function RegisterClockMover()
    local E = EUI()
    if not (E and E.RegisterUnlockElements and E.MakeUnlockElement and MD.Clock.frame) then return end
    E:RegisterUnlockElements({ E.MakeUnlockElement({
        key = "SpellTuner_Clock", label = "SpellTuner clock", group = "SpellTuner", order = 900,
        getFrame = function() return MD.Clock.frame end,
        getSize  = function() local f = MD.Clock.frame; if f then return f:GetSize() end; return 0, 0 end,
        savePos  = function(_, pt, rpt, x, y) MD.db.clock.point = { pt, nil, rpt, x, y } end,
        loadPos  = function() local p = MD.db.clock.point
                       if p and p[1] then return { point = p[1], relPoint = p[3] or p[1], x = p[4] or 0, y = p[5] or 0 } end end,
        clearPos = function() MD.Clock:ResetPosition() end,
        applyPos = function() MD.Clock:ApplyPoint() end,      -- today a local (Clock_Forever.lua:179); expose it
        isHidden = function() return not (MD.db.clock and MD.db.clock.shown) end,
        noResize = true,
    }) }, "SpellTuner")
    if E.RegisterUnlockModeListener then
        E:RegisterUnlockModeListener("SpellTuner", function(active)
            if active then MD.Clock:Preview(3600) else MD.Clock:SetLocked(MD.db.clock.locked) end
        end)
    end
end
MD:RegisterCallback("MD_READY", function() if MD.db.eui.unlock then pcall(RegisterClockMover) end end)
```

- The clock is shown while unlock mode is open, using its own 60 s preview path
  (`UI/Clock_Forever.lua:284-307`). Without that, a clock hidden at full mana could only be placed
  as an empty mover.
- **Gaps that need a decision:**
  - EllesmereUI's anchors and size matches are stored in its own profile layout
    (`EllesmereUIDB.unlockAnchors`), and its export filters the layout down to `ADDON_DB_MAP`
    folders (`EllesmereUI_Profiles.lua:405-520`). An anchor from the SpellTuner clock to an
    EllesmereUI element may therefore be dropped by an EllesmereUI profile export. That is
    acceptable; the position itself lives in `SpellTunerDB`.
  - With EllesmereUI absent, nothing changes: SpellTuner's own unlock and drag
    (`/st clock lock`) stays the only way to move the clock.

### 3.4 Minimap button compatibility (P2, a few lines in a shared file)

The changes are in `UI/MinimapButton.lua`. That file is on both lines, but every change is a no-op
when EllesmereUI is absent.
1. `Reposition()` returns when `btn:GetParent() ~= Minimap` (the button has been collected), and
   the angle drag is disabled in the same case.
2. Keep the icon as `btn.icon = icon` and anchor it CENTER. The collector then finds it by name
   rather than by region order (`EllesmereUIMinimap.lua:516-532`), and its snapshot and restore
   paths (`:325-337`) work.
3. If the in-game check shows the button is not collected (created after EllesmereUI's scans,
   2.4), create the frame at SpellTuner's own `ADDON_LOADED` (SavedVariables are there) and only
   apply the hide setting and position at `MD_READY`.

TBC behaviour is unchanged by construction. `tools/minimapcheck.lua`'s TBC golden must stay
byte-identical.

### 3.5 Following EllesmereUI's look (P3, optional, default off)

What follows EllesmereUI **automatically**, with no code:
- The broker blocks. DataBars draws them in its font, colour, accent hover and bar theme
  (`EllesmereUIDataBars.lua:323-347`, LDB.lua `:228-238`).
- Their tooltips, through EllesmereUI's GameTooltip reskin
  (`EllesmereUIBlizzardSkin.lua:1149-1162`).
- The collected minimap button (2.4).

What could follow **on request**: the floating clock and SpellTuner's own windows.
- **Recommended mechanism.** Register once, and keep `S` for later:

  ```lua
  if EUI() and EllesmereUI.RegisterSkin then
      EllesmereUI.RegisterSkin("SpellTuner", function(S) MD.EUISkin = S
          if S.OnLooksChanged then S.OnLooksChanged(function() MD:Fire("EUI_LOOKS_CHANGED") end) end
      end)
  end
  ```

  The callback runs in BlizzardSkin's `PLAYER_LOGIN` handler, before SpellTuner's `MD_READY`
  (load order). It therefore only stores `S`. The clock's `Snap()` and `Paint()` read
  `S.GetPanelColor()` for the fill, `S.GetFont()` for the text and `S.GetAccentColor()` for the
  preview and accent when `db.eui.look == "ellesmere"`, and repaint on `EUI_LOOKS_CHANGED`. That is
  the "custom elements via getters" route the guide allows (`SKINNING_API.md:113-133`).
- **No `S.Panel` / `S.Shell` on the clock**, because of the FadeRegions problem in 2.2. The main
  window keeps SpellTuner's own flat theme. An "EllesmereUI" UI style, if the styles topic adopts
  one, would be a palette the theme installs from these getters (`UI.PALETTE` / `UI.TEXT`,
  `UI/Theme_Flat.lua:24-61`), not EllesmereUI painting our frames.
- Registering is free and shows SpellTuner in EllesmereUI's "Third-Party Addons" list, where the
  user can switch it off (`SKINNING_API.md:139-145`).
- If BlizzardSkin is off, `S` never arrives. In that case, fall back to the parent's getters
  `EllesmereUI.GetAccentColor()` (`EllesmereUI_UICore.lua:294-296`) and
  `EllesmereUI.GetFontPath()` (`EllesmereUI_Fonts.lua:311`), guarded by `type(...) == "function"`,
  or simply keep SpellTuner's look.

### 3.6 Settings, dump, docs

- **Defaults**, declared by the file that reads them (P20's rule):
  `MD:RegisterDefaults({ eui = { brokers = true, unlock = true, look = "own", short = false } })`.
- **Settings -> General:** an ELLESMEREUI pane, built only when `MD.API.IsAddOnLoaded("EllesmereUI")`
  answers true, with the brokers check, the mover check and the "Follow EllesmereUI look" check.
- **`/st dump`:** one line, `integrations: EllesmereUI 9.3.4 (DataBars on), brokers SpellTuner +
  SpellTuner Regen, mover SpellTuner_Clock, skin apiVersion 2`. The version comes through
  `MD.API.AddOnMetadata`.
- **Docs:**
  - CLAUDE.md: a file-map row for the new file and a TOC note.
  - `docs/TOOLS.md`: the new suite.
  - `docs/TESTING.md`: the in-game section in 4.3.
  - `docs/DECISIONS.md`: "LDB borrowed from the host, never shipped" and "Forever-only".
- **Version:** the new file adds strings, so `tools/textcheck.py` runs over it. `release.sh`
  already builds from the TOC lists, so the Forever package gets the file and the TBC package does
  not. `releasecheck` should assert both.

### 3.7 What it never does

- It never reads or writes `EllesmereUI._ModuleNS`, `EllesmereUIDataBarsDB` or `EllesmereUIDB`.
- It never calls `RegisterModule`.
- It never attaches to `ManaRegenSpark`.
- It never registers events on a frame of its own: the tick and the callbacks go through `MD:On` /
  `MD:OnTick` (apicheck rule 9).
- It never touches EllesmereUI frames in combat. The only frames it moves are its own, and only
  through the mover EllesmereUI drives out of combat.
- It never puts a colour code in broker text (it would be stripped anyway), a non-ASCII glyph, or a
  bare pipe.

---

## 4. Testing

### 4.1 The stub (tools/wowstub.lua, forever profile)

Add `S.Ellesmere(opts)`, installed only by the new suite, so no other suite sees it and the
expected counts are unchanged. It provides:
- `LibStub`: a callable table with `GetLibrary(name, silent)` and `NewLibrary`.
- A **50-line LDB-1.1 stand-in** with the semantics cited above:
  - `NewDataObject` returns nil for a duplicate name.
  - Attribute writes through a metatable; **an equal write fires nothing**.
  - It fires `LibDataBroker_DataObjectCreated` and `LibDataBroker_AttributeChanged_<name>`.
  - It records every fire in `S.ldbFires`.
  - `GetDataObjectByName` and `DataObjectIterator`.
- `EllesmereUI = { IS_FOREVER = true, RegisterSkin, MakeUnlockElement, RegisterUnlockElements,
  RegisterUnlockModeListener, _NotifyUnlockModeListeners }`. Each records its calls.
  `MakeUnlockElement` copies the whitelist fields as EllesmereUI does (`EllesmereUI.lua:2324-2377`).
- A fake skin facade `S` (`apiVersion = 2`, `GetAccentColor`, `GetPanelColor`, `GetFont`,
  `OnLooksChanged`), dispatched on the stub's `PLAYER_LOGIN`, as
  `EllesmereUIBlizzardSkin_SkinAPI.lua:171-178` does.
- A **reader**: `S.LdbBlockText(name)` and `S.LdbTooltip(name)`. These reproduce LDB.lua's display
  rules: `LDBDisplayText` (`:76-88`), `LDBStripColors` (`:66-72`), and the OnTooltipShow path into
  the stub's GameTooltip (`:327-345`). The suite then asserts what the user would actually see.

The vendored LDB copy is not loaded: it lives outside the repository, and `make check` must not
depend on the author's install path.

### 4.2 The suite: tools/euicheck.lua (HARNESS_FLAVOUR = "forever")

Each check is written red-first against the base commit:
1. **Absent host.** No `EllesmereUI`, no `LibStub`: the Mainline TOC loads, `MD_READY` and 20 ticks
   run, no error is raised, no global is written, and no LDB object exists. Every existing Forever
   suite's count is unchanged.
2. **Half install.** `LibStub` is present but `LibDataBroker-1.1` is absent: still quiet.
3. **Brokers.** With the stub, after `MD_READY`: both objects exist, `type == "data source"`, and
   the icon is the button's.
4. **One string.** After a scripted fight (casts through `S.Cast`, the pool spending), the reader's
   `SpellTuner` text equals `MD.ManaModel.Text(MD.Pool:Project(now))` and `MD.Clock.text:GetText()`
   on every tick. It covers `~FULL`, `~FULL 0:45`, `~OOM ...`, `~OOM 1:20  rest 2:10` and `~OOM --`.
5. **ASCII only, no bare pipe**, in every text, label and tooltip line (the probe's rule).
6. **Equal writes.** Ten ticks with nothing changing add zero `AttributeChanged` fires; one spend
   adds exactly one `text` fire.
7. **Tint.** The `iconR/G/B` state map for fullnow, ooc, warmup, hold, oom > 60 and oom <= 60.
8. **Regen.** The text out of combat (`Regen N`), in combat (`Regen ~N`), `(5SR)` for 5 s after a
   priced cast, and `Regen --` before a reading. N equals `floor(rate * 5 + 0.5)` from
   `MD.Pool:LastRegen()`.
9. **Clicks.** Left opens and closes the main window, and right opens Settings -> General (as
   minimapcheck 3/4 do). Both are refused while `MD.inCombat`.
10. **Tooltip.** It holds the clock's `SummaryLines` and the two hint pairs, and the tooltip is
    shown by the reader, not by us.
11. **Late host.** LDB arrives after `MD_READY` (a reader created later): the existing object is
    found by `GetDataObjectByName`, and a duplicate `NewDataObject` is never attempted.
12. **Unlock.** One element `SpellTuner_Clock` is registered with folder `SpellTuner`.
    - `savePos("CENTER", "CENTER", 10, -20)` writes `db.clock.point = { "CENTER", nil, "CENTER", 10, -20 }`.
    - `applyPos` puts the frame there, and `clearPos` restores the default point.
    - `isHidden` follows `db.clock.shown`.
    - The listener (`true`) starts the preview, and (`false`) ends it.
13. **Settings off.** `db.eui.brokers = false` publishes nothing, and `db.eui.unlock = false`
    registers nothing.
14. **Skin.** `RegisterSkin("SpellTuner", fn)` is called once. With `look = "own"` the clock's
    colours are unchanged. With `look = "ellesmere"` the fill, font and accent come from the
    facade's getters, and an `OnLooksChanged` callback repaints.
15. **Minimap (in tools/minimapcheck.lua).** A button reparented to a fake flyout frame is not
    pulled back by `MD:UpdateMinimapButton()`, and `btn.icon` is set. The TBC golden is unchanged.

Also:
- `python3 tools/apicheck.py`: 0 findings, with rule 11 added and its selftest fixture.
- `python3 tools/textcheck.py` stays green.
- `tools/releasecheck.lua`: the Forever package lists `Integrations/EllesmereUI_Forever.lua` and the
  TOC carries `OptionalDeps: EllesmereUI`; the TBC package carries neither.
- `tools/data/expected-counts.json` gets the new suite.

### 4.3 In game (Forever beta)

1. Enable EllesmereUI, EllesmereUIOptions, EllesmereUIDataBars, EllesmereUIMinimap and
   EllesmereUIBlizzardSkin on Healroot-Deathbloom. They are all disabled today (AddOns.txt).
   `/reload`.
2. `/eui` -> DataBars -> add a block of type **Broker Plugin** and pick **SpellTuner**, then
   another block for **SpellTuner Regen**. Set Max Width to about 120.
3. At full mana the block reads `~FULL`, and it is identical to the floating clock (`/st clock`
   shows it). Cast heals in a fight and watch both on every change. Note the tint.
4. Hover: the tooltip sits above or below the bar depending on the bar's edge, in EllesmereUI's
   tooltip skin, with no second border. Left-click opens SpellTuner and right-click opens Settings.
   In combat, both do nothing.
5. Regen block: `Regen N` at rest, `(5SR)` for 5 s after a cast, `~` in combat.
6. Disable SpellTuner and `/reload`: both blocks collapse, with no empty slot. Re-enable.
7. Switch the EllesmereUI profile and switch back: the blocks keep their source.
8. `/unlock`: a "SpellTuner clock" mover appears with the clock shown (preview). Drag it, Save and
   Exit, then `/reload`: the clock is where it was left. `/st clock` and `/st ui reset` still work.
9. Minimap: the SpellTuner button sits in EllesmereUI's button flyout with its icon centred. Toggle
   it from Settings -> General -> Windows: it stays in the flyout.
10. `/st dump` shows the integrations line. `/st probe`'s blocked-action section names no SpellTuner
    action during any of the above.

---

## 5. Risks and open questions

- **The minimap collection timing (2.4)** is unverified until step 9. The fix is in 3.4 item 3.
- **The unlock-mode API** is commented "from any addon" but is not in a developer guide the way
  `SKINNING_API.md` is. Its whitelist comment warns that fields outside it are dropped silently
  (`EllesmereUI.lua:2321-2322`). The integration must keep to the required fields and survive a
  missing function (every call guarded).
- **Width churn.** If the author dislikes the block resizing, the "short" variant or a fixed Max
  Width is the answer. This is decided by the clock-format work, not here.
- **The `~` glyph** is ASCII and present in EllesmereUI's fonts. This was checked only by reading,
  not in game.
- **A future EllesmereUI on the TBC Anniversary client** is not announced. The gate would block it
  (`ClientGate.lua:30-36`). If it ever ships, the same file would need only a TBC TOC entry and a
  `Pool`-free text source (`MD:GetDisplayString`, as `Integrations/ElvUIDatatext.lua:58-62` uses).

## 6. Phasing and size

| Phase | Content | Size |
|---|---|---|
| P1 | brokers (3.1, 3.2), defaults, dump line, apicheck rule 11, stub + `euicheck` 1-11, 13, TOC lines, docs | 1 task, about 150 lines of Lua plus about 250 lines of test |
| P2 | unlock element + listener (3.3), `Clock:ApplyPoint` exposed, minimap guard (3.4), checks 12, 15 | 1 small task |
| P3 | look-follow via `RegisterSkin` getters (3.5), check 14; to land with the UI-styles / clock-customisation decisions | after those topics |
