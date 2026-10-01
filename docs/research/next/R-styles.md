# R-styles: selectable UI styles for SpellTuner (flat / classic / modern / Ellesmere-like)

Research note, 2026-10-01. Read-only survey of the worktree at `c911339` (0.16.5) plus the
EllesmereUI suite installed in the Forever beta client, Cell, ElvUI and the TBC Anniversary
install. Every claim cites a file and line. A claim this survey could not verify is marked
**VERIFY**, and section 6 says how the probe would check it.

---

## 0. The answer in brief

1. **It is feasible, and the kit is already most of the way there.** SpellTuner has one paint
   vocabulary: `UI.PALETTE` fills, `UI.TEXT` tokens and kit font objects (`UI/Style.lua:113-196`,
   `198-224`). One file writes them at load (`UI/Theme_Flat.lua:29-106`). A style is the next
   step: that file turns into a data table, and a second registry repaints what was already painted.
2. **A style changes paint only, never geometry.** Every style keeps spec 4.3's metrics, `UI.Pitch`
   and the font sizes. This rule keeps the ~1000 layout checks (navui, dashui, spellsui, wincheck)
   valid under every style, keeps decision 13's font cap true, and makes switching without
   `/reload` workable. Ornate borders (classic) are drawn *outside* the frame's rect so the content
   area does not move.
3. **Live switching is realistic for about 85-90% of the surface.** The remainder sets text
   colours at creation (68 `SetTextColor(UI.RGB(...))` sites) and captures the accent at creation
   (about 36 sites). It is handled in three ways:
   - a `STYLE_CHANGED` event that panes re-render on, as the Spells pane already does for
     `FONTS_CHANGED`;
   - converting the frozen accent reads to token reads;
   - an honest "Reload to finish" button for anything left.
4. **Four styles, in order of effort.** The fourth needs an author decision.
   - **Flat**: today's look, the default.
   - **Ellesmere**: a palette and font clone everywhere. On Forever, when EllesmereUI is
     installed, it can also follow EllesmereUI's live accent, panel colour and font through
     EllesmereUI's public skinning API.
   - **Modern (Blizzard dark)**: retail's dark Settings look, made from flat fills. Native atlases
     add to it only where a presence check finds them.
   - **Classic (Blizzard dialog)**: `UI-DialogBox` borders, the gold header plaque, gold labels,
     panel-button art. It costs the most and is the riskiest visually, so it needs mockups first.
5. **Native retail art does not travel well.**
   - EllesmereUI finds that Forever swaps many retail atlas names for its own "-c60" bronze art
     (`EllesmereUI_RetailAtlas.lua:10-17`).
   - EllesmereUI refuses to run on any pre-12.1 client, TBC included (`EllesmereUI_ClientGate.lua:20-35`).
   - So a "retail look" built from atlases would look different on each client. The modern style
     should be flat fills shaped like retail, with atlases added only after a presence check.

---

## 1. What the theme system is today

### 1.1 The tokens and the one theme file

| Piece | Where | What it is |
|---|---|---|
| Accent | `UI/Style.lua:57-76` | Class colour via `MD.API.UnitClass` + `RAID_CLASS_COLORS`, fallback `0.7` grey; `UI.accent`, `UI.accentHex` |
| `UI.THEMED` | `UI/Style.lua:102`, `UI/Theme_Flat.lua:83` | false in the kit, true once the theme runs. After C1 (T80) it is true on **both** lines (`docs/DECISIONS.md:1122-1137`) |
| Text tokens | `UI/Style.lua:104-127` (`Token`, `UI.TEXT`), helpers `UI.Hex/RGB/Fill` `132-145` | `{r,g,b, hex}`; an unknown name paints white |
| Fills | `UI/Style.lua:152-196` (`UI.PALETTE`) | rgba tables; accent-derived fills (`hover`, `selected`, `suggested`, `thumb`, `check`, `checkHover`, `accentFill`, `accentHover`) are **computed once from `accent` at load** (`160-179`) |
| Fonts | `UI/Style.lua:198-224` | global font objects `MANADEMON_FONT_*`; `UI.fontObjects` registry |
| The flat theme | `UI/Theme_Flat.lua:24-44` palette, `60-80` text, `89-118` fonts, `126-145` `ApplyFonts` / `Pitch`, `149-169` `db.ui.fontOffset`, `175-176` `UI.PIXEL`, `UI.LIST_STRATA` | Writes the tables **in place** ("a pane that captured the table keeps reading the theme", `Theme_Flat.lua:21-22`) |
| Load order | `SpellTuner_TBC.toc:45-48`, `SpellTuner_Mainline.toc:21-24` | `UI\Style.lua`, `UI\Theme_Flat.lua`, ..., `UI\Windows.lua` |
| Guard suite | `tools/themecheck.lua` (both flavours, `HARNESS_FLAVOUR = {"forever","tbc"}` at line 41) | Asserts the flat values, `UI.THEMED`, no `UI.TEXT` gate in any UI file, the pixel edges |

There are stale comments. `UI/Style.lua:22-27`, `80-83` and `344-346` still say the theme is
Forever-only and that TBC does not list it, but C1 made it list on both lines. Clean them up when
the file is next touched.

### 1.2 How a window gets painted

- **Backdrops.** `UI.StylizeFrame(frame, color, border)` (`Style.lua:397-409`) sets
  `WHITE8x8` as the bg and edge file. Under `UI.PIXEL` the edge is `UI.px(1)` and the frame is
  recorded in the weak registry `UI.pixelFrames[frame] = {color, border}` (`373`). It has 19 call
  sites in `Style.lua` and 13 in other files (ReplayWindow 4, DebugConsole 2, SpellsPane_Forever 2,
  Clock_Forever, SimWindow, SpellsView_TBC, ContextMenu and Widget 1 each).
- **Controls.** `ControlBackdrop` (`711-722`) and `CreateButton` (`724-822`) store
  `b.color, b.hoverColor = UI.ButtonColors(name)`. These are **references** to `UI.PALETTE`
  tables (`685-704`), so the hover scripts follow a palette that is mutated in place. The
  colour painted *now* does not follow.
- **Selection** (`824-917`): a `selected` fill plus a 2-px accent bar; `hover` is laid over it.
- **Re-snapping.** `UI.RestylePixels()` (`416-443`) re-applies the edge to every registered frame
  and re-runs every `UI.PixelLayout` function (`380-389`). It keeps "the colours it shows now".
  The window manager calls it on scale changes (`UI/Windows.lua:350`, `417`, `423-424`, `677`).
- **Tooltips.** `UI/Tip.lua:184-235` lays the skin on **at each showing** (`Tip:Skin`). The kit's own
  tooltip restyles in its `OnShow` hook (`Style.lua:274-301`). Both therefore follow a style change
  with no extra work.
- **Fonts are already live.** `UI.ApplyFonts` re-sizes the font objects in place
  (`Theme_Flat.lua:126-137`). `Style.lua:35-49` wraps it to fire `FONTS_CHANGED`, and
  `UI/SpellsPane_Forever.lua:1781-1783` re-renders on that event. This is the model for
  `STYLE_CHANGED`.

### 1.3 What a style switch would have to chase (frozen at creation)

| Kind | Count | Examples |
|---|---|---|
| Local `accent` captured in the kit | 22 reads in `Style.lua` | `CreateSeparator` 615; `CreateTitledPane` 649, 670; rail drag line 1529, thumb 1545, bar 1645, dot 1664; sheet edge 2033; `FONT_CLASS*` 215-216 |
| `UI.accent` read outside the kit | ~14 | `Dashboard_Rows.lua:42, 319, 342, 507`; `SpellsPane_Forever.lua:858, 1560`; `SpellsView_TBC.lua:604, 978`; `ReplayWindow.lua:403, 1533`; `Dashboard_Simulate.lua:62`; `Options_About.lua:46`; `DebugConsole.lua:149`; `Tip_TBC.lua:32` |
| `SetTextColor(UI.RGB(..))` at creation | 68 | all panes |
| Literal colours in UI files | per file: `ReplayWindow` 28 hex + 43 rgb, `Dashboard_Review` 16 hex, `PracticePanel` 12, `SimWindow` 11 + 1, `BindingsWindow` 8, `SpellTip_Forever` 8, `Dashboard.lua` 6, `DebugConsole` 5 + 3 | most of these are semantic (family colours, verdicts) or exempt (below) |
| `UI.THEMED` read at creation (`local themed = UI.THEMED`) | `Style.lua` 25 reads, `ReplayWindow` 17, others 1-6 | **Not a problem**: styles do not change `UI.THEMED` (2.2) |

These stay the same under every style (they are not decoration):
- the replay window's unit frames, which are the author's Cell layout (`docs/SPEC-forever-ui.md` 4.4);
- the debug console's category legend (spec 4.1's one exception);
- `good` / `bad` / `mana` semantics;
- cast family colours in the replay.

---

## 2. The references

### 2.1 EllesmereUI (Forever beta install, v9.3.4)

`/mnt/e/Blizzard/World of Warcraft/_classic_beta_/Interface/AddOns/EllesmereUI*`. TOC
`## Interface: 120000, ..., 120100, 16001`, so it targets retail 12.x and Forever.

**It already ships the four looks the author named.**
- `EllesmereUI_StyleCards.lua:4-9` and `353-370` list "EllesmereUI Style" ("Flat, clean and
  modern"), "Blizzard Style" ("Blizzard's own frame and button art"), "Classic WoW UI" ("The
  original frames, rings and slots where the game has them") and, on Forever only, "WoW Forever"
  ("Forever's bronze frames, gryphons and round badges").
- This is direct precedent for both the naming and the split.

**Palette.** From `EllesmereUI.lua:152-221` (`STYLE`) and `1338-1345` (`RESKIN`):

| Role | Value |
|---|---|
| Panel bg | `0.05, 0.07, 0.09` (a cool, blue-ish near-black) |
| Border | white at alpha **0.05** (options panel); window engine 1-px border `0.2,0.2,0.2,1` (`EllesmereUIBlizzardSkin_WindowEngine.lua:73`) |
| Text | white; dim = white a 0.53; section header = white a 0.41 |
| Option rows | black overlay a 0.10 / 0.20 alternating |
| Button | bg `0.061,0.095,0.120` a 0.6 (hover 0.65); border white a 0.30 (hover 0.45); label white a 0.55 (hover 0.70) |
| Dropdown | bg `0.075,0.113,0.141` a 0.9 (hover 0.98); border white a 0.20; item hover white a 0.08, selected a 0.04 |
| Checkbox | box `0.10,0.12,0.16`; border a 0.05 / checked 0.15 |
| Slider | track white a 0.16; fill accent a 0.75 |
| Toggle | off `#444` a 0.65, on accent a 0.75, knob white |
| Tooltip | bg `0.067` a 0.92; border white a 0.18, 1 px |
| Window-skin theme | bg `0.08` a 0.92; inset `0.04` a 0.85; border `0.2` (`WindowEngine.lua:66-79`); "Modern" backdrop `#111111` a 0.97 (`112-118`) |

**Accent presets** (`EllesmereUI.lua:24-37`):
- EllesmereUI teal `#0CD29D` (`12,210,157`);
- "EllesmereUI Forever" soft bronze `#DCA77F`, which is the **default on Forever** (`EllesmereUI.lua:38-40`);
- Horde, Alliance, Midnight, Dark (white), Class Colored, Custom.

**Fonts.** Bundled under `media/fonts/`; the default is **Expressway** (`EllesmereUI_Fonts.lua:16-18`,
`249`, `323`). Outline is optional, and the shadow is used only when there is no outline
(`WindowEngine.lua:74-78`).

**Accents in use:**
- a 2-px accent underline on the active tab (`EllesmereUI_Panel.lua:2983-2989`);
- a thin white scroll thumb, white a 0.25 on a white a 0.10 track (`Panel.lua:1970-1985`);
- 1-px white a 0.06 dividers (`Panel.lua:2243`).

**Borders are four strip textures, not backdrops.** `PP.CreateBorder` is used through `AddBorder`
(`WindowEngine.lua:89-110`). The window shell is a painted art backdrop (`media/modern_blizz.png`)
with a 0.62 black overlay and a 25-px black top bar. It is framed by the retail atlas
`AdventureMap_TopBorder`, with a 1-px fallback when `C_Texture.GetAtlasInfo` misses
(`WindowEngine.lua:321-410`).

**It has a public skinning API for other addons.** `SKINNING_API.md`; the stub is
`EllesmereUI_SharedHelpers.lua:57-71`; the facade is `EllesmereUIBlizzardSkin_SkinAPI.lua:49-115`.
- `EllesmereUI.RegisterSkin(name, fn(S))` fires once at `PLAYER_LOGIN` (or at once for a late
  registration), inside a `pcall`.
- `S` offers `Shell`, `Panel`, `Button`, `EditBox`, `Checkbox`, `Dropdown`, `ScrollBar`, `Tab`,
  `CloseButton`, `Font`, `ApplyBarFill`.
- It also offers the getters `S.GetAccentColor()`, `S.GetPanelColor()`, `S.GetFont()`,
  `S.GetStyle()` (`"eui"` or `"modern"`) and `S.OnLooksChanged(fn)` (`SKINNING_API.md:113-122`).
- `apiVersion` is 2, and the API is additive-only (`SkinAPI.lua:50`, `SKINNING_API.md:72-75`).
- The user can turn it off per addon. The callback then never fires (`SkinAPI.lua:34-41`,
  `125-136`), so a fallback is mandatory.
- The primitives "fade" existing regions to alpha 0 (`WindowEngine.lua:132-160`). Handing them
  frames that SpellTuner repaints itself would make two painters fight over the same frame (2.4).

**Not on TBC.** `EllesmereUI_ClientGate.lua:20-35` sets `EUI_CLIENT_BLOCKED` on any client below
12.1 that is not Forever (16000-19999). On TBC Anniversary (20505/20506) every EllesmereUI file
returns at line 1. The "Ellesmere" style is therefore a **clone** on TBC, and can only **follow**
EllesmereUI on Forever.

**What it says about Forever's art:**
- `EllesmereUI_RetailAtlas.lua:10-27`: "WoW Forever swaps many retail atlas names for its own
  '-c60' art, so SetAtlas draws Forever art there, but the retail sheets still ship with that
  client."
- It reaches the retail art by file id and texcoords, and checks presence with
  `GetFileIDFromPath(path) == expectedId` (`159-213`, `230-290`).
- It builds Forever's bronze window ring from the atlas `UI-HUD-ActionBar-Frame` (`35-157`).
- Classic WoW art comes from plain files, e.g. `Interface\CastingBar\UI-CastingBar-Border` as a
  nine-slice (`EllesmereUI_ClassicArt.lua:5-40`), and `Interface\TargetingFrame\UI-StatusBar`,
  `Interface\Buttons\UI-Quickslot`, `Interface\TargetingFrame\UI-TargetingFrame`
  (`StyleCards.lua:19-22`). All of these load on the Forever client.

### 2.2 Cell (the flat look's origin)

- `Cell/Widgets/Widgets.lua:24-27`: the accent is the class colour.
- `142-150`: `Cell.OverrideAccentColor` swaps the accent and re-colours only the two class font
  objects. Everything else picks it up at the next build.
- `Core.lua:67`, `Core_Vanilla.lua:453`: the override is applied **at load**.
- `316-323`: `StylizeFrame`, which is `WHITE8x8` with a `P.Scale(1)` edge.

Precedent: Cell does not live-switch its options look either. A reload for a change of accent is
acceptable to its users.

### 2.3 ElvUI (live re-template precedent)

- `ElvUI/Game/Shared/General/Toolkit.lua:291-370`: `SetTemplate(frame, template, ...)` writes
  `frame.template = 'Default'|'Transparent'` and registers the frame in `E.frames` (weak).
- `Game/Shared/General/Core.lua:552-680`: `E:UpdateFrameTemplates`, `UpdateBorderColors` and
  `UpdateBackdropColors` walk the registry and re-apply **by the role name stored on the frame**,
  in a coroutine.
- This is exactly the change SpellTuner's `UI.pixelFrames` needs: store a *role* rather than
  colour tables.
- `Game/Shared/General/Config.lua:455`: `E.Classic and 'UIDropDownMenuTemplate' or
  'WowStyle1DropdownTemplate'`. The modern dropdown template is absent on classic clients, so do
  not build styles on Blizzard *templates*.
- `Game/Shared/Modules/Bags/Bags.lua:62`, `1726`: `C_Texture.GetAtlasInfo` is guarded
  (`if C_Texture_GetAtlasInfo and ...`) in shared classic code.

### 2.4 Blizzard: classic dialogs versus retail panels

- **Classic (the 2004-2008 dialog family).** A dark tiled background
  (`Interface\DialogFrame\UI-DialogBox-Background`) inside a 32-px stone and gold edge
  (`UI-DialogBox-Border`, edge 32, insets 11/12/12/11), with a gold plaque header
  (`UI-DialogBox-Header`, as DialogHeaderTemplate cuts it).
  - Text: titles and labels in NORMAL_FONT_COLOR gold `1, 0.82, 0`, values in white, hints in
    `0.5` grey.
  - Inner boxes: OptionsBoxTemplate style, i.e. `Interface\Tooltips\UI-Tooltip-Border` edge 16,
    border `0.4` grey, fill `0.15`.
  - Controls: buttons from `UI-Panel-Button-Up/Down/Highlight/Disabled` (red-brown, 3-slice);
    checkboxes from `UI-CheckBox-*`; the close button `UI-Panel-MinimizeButton-*`; list hover from
    `UI-QuestTitleHighlight` / `UI-Listbox-Highlight` (additive).
- **Retail (Dragonflight to Midnight).**
  - Windows: NineSlice layouts (`ButtonFrameTemplateNoPortrait` and others) over atlases.
  - Buttons: `128-RedButton-*` 3-slice.
  - Settings list: `Options_List_Active` / `Options_List_Hover`; `common-dropdown-*`,
    `minimal-scrollbar-*`; close `RedButton-Exit`.
  - Overall: very dark charcoal panels with gold category headers and white text.
  - All of these are **atlas names**, and Forever may redirect them to its -c60 art (2.1).
  - Exact names are **VERIFY** on Forever and absent on TBC.

---

## 3. The proposed architecture

### 3.1 The invariants (what a style may not do)

1. **No geometry.** A style never changes a size, anchor, pitch, font *size*, row height or
   inset. These stay in spec 4.3, `UI.Pitch`, `UI.H` and decision 13's offset cap. Ornate edges
   that need room are drawn on an **outset** child (3.4), so the frame's content rect is the same
   in every style. Payoff: the layout suites hold under every style, and a switch never re-lays a
   window.
2. **No behaviour.** `UI.THEMED` stays the *layout* switch and is true for every style. It already
   means "the new window" on both lines since C1. A style adds a second, paint-only axis,
   `UI.STYLE` (the active key).
3. **No style branches in panes.** A pane never writes `if UI.STYLE == "classic"`. It reads tokens
   and fills, or asks the kit for a role. `tools/themecheck.lua` already fails a `UI.TEXT` gate in
   any UI file; extend the same scan to `UI.STYLE`, allowed only in `UI/Style*.lua` and the style
   files.
4. **Flat is byte-identical.** With `db.ui.style = "flat"` (the default) every existing suite keeps
   its exact expectations. T84 used the same "byte-identical" gate for its refactor.
5. **ASCII, no libraries, client calls through `MD.API`.** Atlas and file presence checks become
   adapter bindings (3.6). EllesmereUI is read the way ElvUI's datatext is: optional, and never a
   dependency.

### 3.2 A style is a data table

One file per style under `UI/Styles/` (or one `UI/Styles.lua`), listed by every main TOC after
`UI/Theme_Flat.lua`. `Theme_Flat.lua` becomes the flat style's data plus the shared appliers. Shape:

```lua
UI.RegisterStyle("classic", {
  name = "Classic",                       -- Settings label, ASCII
  hint = "Blizzard's dialog boxes, gold headers.",
  accent = "gold",                        -- "class" | "gold" | {r,g,b} | "follow" (Ellesmere)
  -- fills: rgba literal, or a reference resolved at apply time so accent
  -- changes recompute them: { ref = "accent", a = 0.12 }
  palette = {
    bg = {0,0,0,0.9}, pane = {0.15,0.15,0.15,0.9}, nav = {0.1,0.1,0.1,0.9},
    border = {0.4,0.4,0.4,1}, rule = {ref="accent", a=0.6}, line = {0.3,0.3,0.3,1},
    rowAlt = {1,1,1,0.03}, hover = {ref="accent", a=0.12}, selected = {ref="accent", a=0.25},
    suggested = {ref="accent", a=0.10}, mask = {0,0,0,0.6}, tip = {0,0,0,0.9},
    button = {0.2,0.05,0.05,1}, buttonHover = {0.35,0.1,0.1,1}, field = {0,0,0,0.6}, ...
  },
  text = { accent = "ffd100", text = "ffffff", label = "ffd100", text2 = "ffffff",
           muted = "808080", disabled = "808080", mana = "4d99ff", good = "1aff1a", bad = "ff1a1a" },
  fonts = { face = "FRIZ", num = "Fonts\\ARIALN.TTF", flags = "", shadow = {1,-1,0,0,0,1} },
  -- one recipe per ROLE; kind picks the painter (3.4); `needs` lists art the
  -- presence check must find, else the role falls back to flat's recipe
  roles = {
    window  = { kind = "backdrop", outset = 8,
                bg = "Interface\\DialogFrame\\UI-DialogBox-Background", tile = 32,
                edge = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 32,
                insets = {11,12,12,11} },
    header  = { kind = "plaque", file = "Interface\\DialogFrame\\UI-DialogBox-Header" },
    pane    = { kind = "backdrop", edge = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
                insets = {5,5,5,5} },
    button  = { kind = "slice3", up = "Interface\\Buttons\\UI-Panel-Button-Up",
                down = "...-Down", hi = "...-Highlight", off = "...-Disabled",
                coords = {0, 0.09375, 0.53125, 0.625, 0, 0.6875} },          -- VERIFY
    check   = { kind = "files", up = "Interface\\Buttons\\UI-CheckBox-Up", ... },
    close   = { kind = "files", up = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up", ... },
    listHover = { kind = "file", file = "Interface\\QuestFrame\\UI-QuestTitleHighlight", blend = "ADD" },
    selection = { bar = "none" },          -- flat: "left"/"bottom" 2-px accent bar
    scroll  = { kind = "flat" },           -- see 4.4: art would change the 5-px lane
    statusbar = "Interface\\TargetingFrame\\UI-StatusBar",
    tooltip = { kind = "native" },         -- leave the game's NineSlice: Tip:Skin off
    clock   = { kind = "backdrop", edge = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
                insets = {3,3,3,3}, outset = 3 },
  },
})
```

Role names come from what the kit paints today:

| Role | Painted today by |
|---|---|
| `window` | `CreateMovableFrame` / `CreateNavFrame` |
| `header` | `CreateMovableFrame` header, 20 px |
| `nav` | the nav's left column |
| `pane` | `CreateNavBox`, rail, sheet, cards |
| `button` | `CreateButton` |
| `tab` | view-row buttons |
| `field` | edit box, check box |
| `list` | dropdown lists |
| `scroll` | scroll frame bar and thumb |
| `tooltip` | `UI.tooltip` and `Tip:Skin` |
| `clock` | `UI/Widget.lua`, `UI/Clock_Forever.lua` |
| `statusbar` | the clock bar, practice bars |
| `rule` | separators, titled-pane rules |

A role a style does not name inherits flat's recipe. That makes a partial style always valid, and
lets the modern and Ellesmere styles stay mostly data.

### 3.3 The skin registry, and applying a style

- **Replace `UI.pixelFrames[frame] = {color, border}`** (`Style.lua:373`, `405`, `719`) with
  `UI.skinned[region] = { role = "button", fill = "button", edge = "border", state = ... }`.
  It stays weak-keyed (ElvUI's `E.frames` with `frame.template`, 2.3).
  - `UI.StylizeFrame(frame, color, border)` keeps its signature for the 13 outside callers.
  - It learns an optional role, `UI.Skin(frame, "pane", "pane", "border")`. When a caller passes
    a `UI.PALETTE` table, it maps the table back to its key (a reverse lookup built at apply time),
    so old call sites register correctly with no edit.
- **`UI.Paint(region)`** runs the active style's recipe for that region's role. It covers:
  - the backdrop (pixel or art edge);
  - the outset child, created lazily and hidden when unused;
  - the 3-slice button textures, created lazily and hidden under flat;
  - the colours from the role's keys.
  - `UI.RestylePixels` becomes "repaint every registered region", which is what it nearly is
    already (`Style.lua:416-443`).
- **`UI.SetStyle(key)`**, which also runs at `CORE_LOGIN` from `db.ui.style`:
  1. resolves the style and its fallbacks (3.6);
  2. writes `UI.PALETTE` and `UI.TEXT` **in place**, recomputing `{ref="accent"}` fills from the
     style's accent;
  3. re-faces the font objects (`ApplyFonts`, generalised from `Theme_Flat.lua:111-137`, with the
     face and flags read from the style; sizes unchanged);
  4. walks `UI.skinned` and calls `UI.Paint`; then the `UI.pixelLayouts` functions;
  5. fires `STYLE_CHANGED`;
  6. saves `db.ui.style`.
- **The two kit font objects that carry the accent** (`FONT_CLASS_TITLE`, `FONT_CLASS`,
  `Style.lua:215-216`) are re-coloured in step 3, as Cell does in `OverrideAccentColor`
  (`Widgets.lua:148-149`).
- **Hover and selection** keep working unchanged. `b.color` and `b.hoverColor` point at
  `UI.PALETTE` tables that were mutated in place. The selection parts (`Style.lua:824-857`) read
  `UI.Fill("hover")` and `UI.RGB("accent")` once at creation, so they register as `rule` and
  `hover` regions.

### 3.4 Recipe kinds (the painters)

| Kind | Painter | Notes |
|---|---|---|
| `pixel` | today's `PixelBackdrop` (`Style.lua:391-395`) | flat, Ellesmere, modern |
| `strips` | four textures, as `Tip.lua:184-195` and EUI's `PP.CreateBorder` do | lets the border alpha differ from the fill: EUI's white a 0.05 edge |
| `backdrop` | `SetBackdrop{bgFile, edgeFile, tile, tileSize, edgeSize, insets}` **on an outset child** at `-outset` all round, frame level -1 | classic: the stone edge sits outside the content rect, so layout does not change. BackdropTemplate's `SetBackdrop` can be called again at runtime (TBC 2.5.x has the mixin, `Style.lua:276-279`) |
| `plaque` | three textures (left, centre, right) centred over the header | classic header; title recoloured to the style's `accent` (gold) |
| `slice3` | left / middle / right textures with texcoords, one set per state, swapped in `OnMouseDown/Up/Enter/Leave` and `OnDisable` | classic buttons; the label colour follows (gold to white on hover) |
| `files` | `SetNormalTexture` / `SetPushedTexture` / `SetHighlightTexture` / `SetCheckedTexture` | classic check box and close button |
| `atlas` | `tex:SetAtlas(name)` only after `MD.API.AtlasInfo(name)` answers | modern's optional pieces |
| `native` | do nothing; give the game's art its alpha back | tooltips under classic and modern: `Tip:Skin` returns false and the NineSlice keeps its alpha (`Tip.lua:229-232` already restores it) |

### 3.5 Settings, command and persistence

- `MD:RegisterDefaults({ ui = { style = "flat" } })` in the style file, the way the theme
  registers `fontOffset` (`Theme_Flat.lua:149`).
- A **Look** dropdown at the top of APPEARANCE, using the existing `UI.CreateDropdown` that the
  combat-mode control already uses (`Options_General.lua:274-277`):
  - Forever: `UI/Dashboard_Forever.lua:199-231` (`BuildAppearanceSection`; its height grows by one
    row);
  - TBC: `UI/Options_General.lua:270-300` (`CreateWindowsPane`).
- Entries:
  - Flat;
  - Classic;
  - Modern;
  - Ellesmere (or "Ellesmere (following EllesmereUI)" while the follow is active);
  - a sub-choice **Accent: class colour / the style's own**.
- Selecting an entry repaints at once, the open Settings window included, which is its own preview.
- `/st ui style <flat|classic|modern|ellesmere>`, registered with `MD:AddCommand` next to
  `/st ui reset`.
- `/st dump` gains one line: the style, plus every role that fell back because its art was missing.

### 3.6 Presence checks and fallbacks (client calls through the adapter)

- **New bindings in `Client/API.lua`**, shared by both TOCs and guarded:
  - `MD.API.AtlasInfo(name)` returns a copy of `C_Texture.GetAtlasInfo` (`file`, `width`,
    `height`), or nil. It is in the 69893 baseline (`C_Texture.GetAtlasInfo`; `GetAtlasExists`
    also exists). On TBC it is **VERIFY**, and ElvUI's shared code guards it (2.3).
  - `MD.API.FileID(path)` returns `GetFileIDFromPath`. It is in the 69893 baseline (`True` in
    `tools/data/forever_api.json`), and EllesmereUI uses it on Forever (`RetailAtlas.lua:213`).
    On TBC it is **VERIFY**.
- **Each style lists its `needs`.** `UI.SetStyle` checks them once. A role whose art is missing
  falls back to flat's recipe for that role and is reported in `/st dump`. If nothing answers
  (the binding is absent on TBC), assume the files in the "both" column of 5.1 exist and refuse
  every atlas.
- **The probe** (`Client/Probe.lua`) gains `== art`: one line per path and atlas the styles name,
  as `file <path> id=<n|absent>` / `atlas <name> file=<id> <w>x<h> | absent`. It runs on both
  clients. This turns every **VERIFY** in section 5 into a report line, the way `== shapes` and
  `== windows` did.

### 3.7 Following EllesmereUI (Forever only)

- **Wiring.** Register once with `EllesmereUI.RegisterSkin("SpellTuner", fn)`. The `EllesmereUI`
  global is touched in one place only, the integration file or a `Client/` binding (apicheck
  rule; the same question the ElvUI datatext raised).
- **Inside the callback**, keep `S` and read:
  - `S.GetAccentColor()` as the style's accent;
  - `S.GetPanelColor()` as `bg` and `pane`;
  - `S.GetFont()` as the face for the text fonts (Expressway by default; the path is
    `Interface\AddOns\EllesmereUI\media\fonts\Expressway.TTF`, so SpellTuner never ships the font);
  - and register `S.OnLooksChanged(function() UI.SetStyle("ellesmere") end)`.
- **SpellTuner's own frames are not handed to `S.Shell`, `S.Panel` or `S.Button`.** Those fade
  every texture region to alpha 0 and paint their own (`WindowEngine.lua:132-160`, `412-431`,
  `460-498`). With SpellTuner's registry also painting, two painters would fight, and switching
  the style back would leave faded regions behind. The getters are the documented path for custom
  drawing (`SKINNING_API.md:126-135`).
- **Fallback.** EllesmereUI absent, skinning off for SpellTuner, or TBC: the callback never fires,
  and the Ellesmere style uses its cloned constants (4.2).
- **One optional extra:** `S.ScrollBar` / `S.Dropdown` on Blizzard-template widgets. SpellTuner
  has none; every kit widget is `BackdropTemplate`. So: none.

### 3.8 Tests

- **`tools/stylecheck.lua`**, a new suite on both flavours:
  - every registered style validates (every palette key flat has, every token shaped, every
    role's kind known, `needs` well-formed, names ASCII);
  - flat, then classic, then modern, then ellesmere, then flat repaints a nav frame, a button, a
    check box, a rail and the clock, and returns **byte-identical** to the first flat paint (colours,
    backdrop tables, texture visibility);
  - a missing atlas falls back per role and is listed;
  - `STYLE_CHANGED` fires once per switch;
  - the Settings dropdown writes `db.ui.style`;
  - `/st ui style` refuses an unknown name.
- **The stub** (`tools/wowstub.lua`) needs `SetAtlas`, a fake `C_Texture.GetAtlasInfo`
  (configurable present/absent), `GetFileIDFromPath`, `SetTexCoord` recording, `SetBlendMode`.
- **`themecheck`** keeps the flat values and adds the `UI.STYLE`-gate scan.
- **Existing suites** stay unchanged under flat. Expected counts move only for the new suite.
- **The probe** adds `== art`; `probecheck` gets its lines.

---

## 4. The styles: what each one sets

All four keep the same layout (3.1). Only the columns below differ.

### 4.1 Flat (the default; today)

Exactly `UI/Theme_Flat.lua`:
- palette `29-44` and text `60-80`;
- Friz text with Arial Narrow numbers, no outline, shadow (1, -1) (`89-106`);
- 1-px black pixel edges;
- the class-colour accent;
- no gold (spec 4.1).

Its file becomes the style table plus the appliers. **Effort:** part of the infrastructure.
**Risk:** low, since it is the byte-identical gate.

### 4.2 Ellesmere (clone everywhere; follow on Forever)

| Token / role | Value (source) |
|---|---|
| accent | `#DCA77F` bronze on Forever, `#0CD29D` teal elsewhere (EllesmereUI's defaults, `EllesmereUI.lua:25-27, 38-40`); "class colour" offered too; live `S.GetAccentColor()` when following |
| bg / pane / nav | `0.05,0.07,0.09` a 0.96 / same a 1 / the same plus black a 0.10 (`STYLE.PANEL_BG`, `ROW_BG_ODD`) |
| border | `strips`, white a 0.05 (options panel); windows white a 0.10. EUI's window engine uses `0.2` grey: offer it as the "edge" variant |
| line / rule | white a 0.06 (`Panel.lua:2243`) / the accent, alpha 1 (tab underline) |
| rowAlt | black a 0.20 on even rows (`ROW_BG_EVEN`) |
| hover / selected | white a 0.08 / white a 0.04 **plus the 2-px accent bar** (EUI's dropdown item alphas; the bar is EUI's tab underline, `Panel.lua:2983-2989`) |
| button / buttonHover | `0.061,0.095,0.120` a 0.6 / a 0.65; edge white a 0.30 / 0.45; label white a 0.55 / 0.70 (`STYLE.BTN_*`) |
| field | `0.10,0.12,0.16` (checkbox) and `0.075,0.113,0.141` a 0.9 (dropdown) |
| track / thumb | white a 0.10 / white a 0.25, 5 px (EUI's scroll bar, `Panel.lua:1970-1979`). It fits SpellTuner's existing 5-px rail bar (`Style.lua:1487`) |
| check / slider | the accent at a 0.75 (`SL_FILL_A`, `TG_ON_A`) |
| tip | `0.067` a 0.92, edge white a 0.18 (`RESKIN`) |
| text | `text` white; `label`/`text2` white a 0.53 (no rgb grey: alpha on white, as EUI does); `muted` white a 0.41 |
| fonts | following: `S.GetFont()` (Expressway). Clone: Arial Narrow (`Fonts\ARIALN.TTF`) for text **and** numbers, the nearest Blizzard-shipped narrow grotesk. Expressway is not shipped by SpellTuner |
| clock | `strips` edge white a 0.10 on panel bg; bar fill = the accent at 0.75 |

**Effort:**
- clone: S, pure data plus the `strips` painter;
- follow: S-M (RegisterSkin, getters, `OnLooksChanged`, a fallback test).

**Risk:** low.
- Text alpha on white needs the `Token` shape to carry alpha. Today `Token` is rgb plus hex
  (`Style.lua:104-111`). The hex form cannot hold alpha, so `UI.Hex` must pre-blend against the
  bg. That is one function plus a test.
- The follow depends on a third-party API that is versioned and additive-only.

### 4.3 Modern (Blizzard retail, dark)

Retail's Settings panel made from fills. Optional atlases are added only where present.

| Token / role | Value |
|---|---|
| accent | gold `1, 0.82, 0` for headers and selection (retail's category gold); "class colour" offered |
| bg | `#111111` a 0.97 (EUI's "Modern" backdrop default, `WindowEngine.lua:112`, which matches retail's dark windows) |
| pane / nav | `#1A1A1A` a 1 / `#151515` |
| border | `0.25` grey 1 px, an outset of 1: retail's thin inner line rather than black |
| header | 24 px black a 0.5 strip inside the top (EUI's shell top bar, `WindowEngine.lua:351-358`), drawn in the existing 20-px header: **no geometry change** |
| hover / selected | white a 0.06 / gold a 0.18 plus a 2-px gold bar on the left; when `Options_List_Active` and `Options_List_Hover` answer `MD.API.AtlasInfo` (**VERIFY on Forever**, absent on TBC), those atlases instead |
| button | `#2A2A2A` / hover `#3A3A3A`, edge `0.35` grey; `128-RedButton-*` 3-slice only if present (VERIFY; on Forever it may draw -c60 art) |
| close | flat `x` in white a 0.8, red on hover; `RedButton-Exit` atlas if present |
| text | `text` white, `label` `#CCCCCC`, `muted` `#8C8C8C`, `accent` gold for pane titles (as retail's Settings categories) |
| fonts | Friz text, Arial Narrow numbers (retail's own faces), no outline |
| tooltip | `native` (the game's tooltip) or flat; one setting |
| clock | flat pixel panel in `#111111` a 0.9 with the 0.25 edge; bar the mana blue |

**Effort:** S-M (data plus the `atlas` painter plus presence checks). **Risk:** low with the
atlases off, medium with them on:
- the atlas names are unverified on Forever, which may redirect them to bronze -c60 art;
- every atlas is optional by construction.

### 4.4 Classic (Blizzard dialog)

| Token / role | Value |
|---|---|
| accent | NORMAL_FONT_COLOR gold `1, 0.82, 0` (`ffd100`). This deliberately reverses spec 4.1's "no gold" for this one style: author decision (8) |
| window | `backdrop` on an outset child: `UI-DialogBox-Background` tiled 32 + `UI-DialogBox-Border` edge 32, insets 11/12/12/11 (Blizzard's `BACKDROP_DIALOG_32_32` recipe), outset ~8 so the stone sits around the content |
| header | `plaque` from `UI-DialogBox-Header` (left / centre / right cuts as DialogHeaderTemplate; texcoords **VERIFY**) centred over the existing 20-px header strip, title in gold; strip fill transparent |
| nav / pane / cards | `backdrop` `UI-Tooltip-Border` edge 16, insets 5, fill `0.15` a 0.9, border `0.4` grey (OptionsBoxTemplate's look) |
| button | `slice3` from `UI-Panel-Button-Up/Down/Highlight(ADD)/Disabled`, coords `0-0.09375 / 0.09375-0.53125 / 0.53125-0.625` x `0-0.6875` (classic UIPanelButtonTemplate, **VERIFY**). Label GameFontNormal gold, white on hover. The art is 22 px tall and kit buttons are 20/18 (`UI.H`): it stretches by 10%, acceptable at 20, poor at 18. Mockup |
| check | `files` `UI-CheckBox-Up/Down/Highlight/Check/Check-Disabled`. The art's box is ~60% of the 32-px file, so a 14x14 kit box would show a ~8-px box. Draw it at 22-24 *inside* the existing click area (T75 already measures it from the label) or keep flat boxes. Mockup |
| close | `files` `UI-Panel-MinimizeButton-Up/Down/Highlight` on the existing 20x20 (art 32: scaled ~0.6, readable) |
| list hover / selected | `UI-QuestTitleHighlight` ADD / `UI-Listbox-Highlight2` (**VERIFY** name), no accent bar |
| scroll | **flat, gold-tinted thumb.** `UIPanelScrollBar` art is 16 wide and the rail's lane is 5 (`Style.lua:1487`): art would change geometry |
| statusbar | `Interface\TargetingFrame\UI-StatusBar` (EUI uses it on Forever, `StyleCards.lua:21`) |
| text | `accent`/`label` gold `ffd100`; `text` white; `muted`/`disabled` `808080`; `good` `1aff1a`; `bad` `ff1a1a` (GREEN/RED_FONT_COLOR) |
| fonts | Friz everywhere, Arial Narrow numbers kept (it is Blizzard's NumberFont face); optional OUTLINE on numbers |
| tooltip | `native`: the game's own tooltip, no SpellTuner skin |
| clock | `backdrop` `UI-Tooltip-Border` edge 12, insets 3, outset 3, fill black a 0.8; UI-StatusBar bar |

**Optional parchment variant.** Card fill `Interface\QuestFrame\QuestBG` or the achievement
parchment, with **dark** text tokens (`text` `#2B1D0E`, `label` `#5A3A12`):
- it only works if every pane reads tokens, which the token work guarantees;
- the achievement parchment is a Wrath file, so it is TBC **VERIFY**;
- recommend deferring it.

**Effort:** L. It needs four new painters (`backdrop` with outset, `plaque`, `slice3`, `files`)
and per-state texture swaps, and every button, check box and close button must carry lazily-made
art regions.

**Risk:** medium-high, and visual rather than functional:
- art scaled into 18-20-px controls;
- the 32-px dialog edge around 860x560 windows;
- the gold plaque over a 20-px header.

Tests can prove the wiring, but only in-game screenshots can prove the look. The author's working
rule is "mockups before UI builds" (memory, `user-works-in-parallel.md`).

### 4.5 The "native" variant (do not build first)

`NineSliceUtil.ApplyLayoutByName(frame, "ButtonFrameTemplateNoPortrait")` would let each client
draw its own window. That means different art on each line:
- classic metal on TBC;
- bronze -c60 on Forever (2.1);
- Midnight metal on retail.

`NineSliceUtil` is a global table not captured by the 69893 baseline (only
`BaseNineSliceDialog_OnCloseClick` is there), so apicheck would need a TOOLKIT entry
(`tools/apicheck.py:78-86`). It is also not "a retail look". Offer it later as "Blizzard (native
art)" if the author likes Forever's bronze; EllesmereUI's "WoW Forever" card is precedent.
**Risk:** high and unpredictable.

---

## 5. Which art exists where

### 5.1 Table

The "evidence" column says why each answer is believed. Anything not already used by SpellTuner
on both lines is confirmed by the probe's `== art` (3.6) before a style depends on it. Until then
it sits behind the per-role fallback.

| Art | TBC 2.5.x | Forever (12.x engine) | Evidence |
|---|---|---|---|
| `Interface\Buttons\WHITE8x8` | yes | yes | in use on both (`Style.lua:51`) |
| `Interface\Buttons\SquareButtonTextures` | yes | yes | chevrons, on both since C1 (`Style.lua:1378`) |
| `Interface\ChatFrame\UI-ChatIM-SizeGrabber-*` | yes | likely | TBC grip before T75 (`Style.lua:595-597`) |
| `Interface\Minimap\MiniMap-TrackingBorder`, `UI-Minimap-ZoomButton-Highlight` | yes | yes | `UI/MinimapButton.lua:80-89`, on both lines (T79) |
| `Interface\LFGFrame\UI-LFG-ICON-PORTRAITROLES` | yes | yes | `UI/ReplayWindow.lua:95`, both |
| `Fonts\FRIZQT__.TTF`, `Fonts\ARIALN.TTF` | yes | yes | `Theme_Flat.lua:89-90`; ARIALN is `NumberFont`'s face |
| `Interface\TargetingFrame\UI-StatusBar` | yes | yes | LSM default bar on both; EUI on Forever (`StyleCards.lua:21`) |
| `Interface\DialogFrame\UI-DialogBox-Border` / `-Background` / `-Background-Dark` / `-Gold-Border` | yes (classic dialogs) | very likely | Blizzard's `BACKDROP_DIALOG_32_32` family (both SharedXMLs); LSM lists them unconditionally on both installs (EUI copy `LibSharedMedia-3.0.lua:65-88`; TBC copy `_anniversary_/.../LibSharedMedia-3.0.lua:65-90`); EUI's border list (`EllesmereUI_PixelPerfect.lua:1184`). **VERIFY** (LSM does not probe) |
| `Interface\DialogFrame\UI-DialogBox-Header` | yes | very likely (DialogHeaderTemplate) | **VERIFY** |
| `Interface\Tooltips\UI-Tooltip-Border` / `-Background` | yes | yes (`BACKDROP_TOOLTIP_16_16_5555`) | LSM both; **VERIFY** cheaply |
| `Interface\Buttons\UI-Panel-Button-Up/Down/Highlight/Disabled` | yes (UIPanelButtonTemplate) | likely: retail templates moved to `128-RedButton` atlases but old files are usually kept | **VERIFY** |
| `Interface\Buttons\UI-CheckBox-*`, `UI-Panel-MinimizeButton-*` | yes | likely | **VERIFY** |
| `Interface\QuestFrame\UI-QuestTitleHighlight`, `Interface\Buttons\UI-Listbox-Highlight(2)` | yes | likely | **VERIFY** |
| `Interface\FrameGeneral\UI-Background-Rock` / `-Marble` | likely | yes (LSM) | **VERIFY** |
| `Interface\CastingBar\UI-CastingBar-Border` | yes | yes | EUI Classic art on Forever (`ClassicArt.lua:32`) |
| `Interface\AchievementFrame\UI-Achievement-Parchment-Horizontal` | **unlikely** (achievements are Wrath+) | yes | LSM lists it unconditionally. Do not use on TBC |
| Atlas `AdventureMap_TopBorder` | no | yes, with fallback | EUI shell border (`WindowEngine.lua:385-405`) |
| Atlas `UI-HUD-ActionBar-Frame` (Forever bronze) | no | yes (Forever art) | `RetailAtlas.lua:35-157` |
| Atlases `128-RedButton-*`, `RedButton-Exit`, `Options_List_Active/Hover`, `common-dropdown-*`, `minimal-scrollbar-*`, `UI-Frame-Metal-*` | no | names exist on the retail engine but **may draw -c60 art** (`RetailAtlas.lua:10-17`) | **VERIFY** each, and look at it |
| Template `WowStyle1DropdownTemplate` | no | yes | ElvUI `Config.lua:455`: reason not to use templates |
| `C_Texture.GetAtlasInfo`, `GetFileIDFromPath` (the checks themselves) | **VERIFY** (ElvUI guards the first) | yes (69893 baseline) | `tools/data/forever_api.json` |
| `NineSliceUtil` | present (the 2.5 tooltip has a NineSlice, `Style.lua:272-276`) but its layouts draw classic art | present, may draw -c60 | not in the baseline's `functions` (a table) |

### 5.2 What the table implies

- **Classic is the most portable Blizzard style.** It rests on plain `Interface\...` files from
  2004, which the retail engine still carries for old addons and `BACKDROP_*` presets.
- **Modern must not rest on atlases**, because Forever redirects them and TBC lacks them. Hence
  4.3's flat fills plus optional pieces.
- **Ellesmere needs no art at all.** It is the safest of the three new styles.

---

## 6. Switching without `/reload`

| Surface | Live? | How |
|---|---|---|
| Kit fonts (face, flags, accent colour) | yes | font objects re-faced in place (as `ApplyFonts` today) |
| Every `StylizeFrame` / `ControlBackdrop` frame | yes | the skin registry (3.3) |
| Button hover / selection after a switch | yes | references to palette tables mutated in place (`Style.lua:735`, `810-816`) |
| Tooltips (kit and `Tip:Skin`) | yes | painted per showing (`Tip.lua:220-235`, `Style.lua:299-300`) |
| Clocks | yes | both already repaint on their own 0.5-s snap (`UI/Widget.lua:36-41`, `Clock_Forever.lua:198`); read the role there |
| Spells pane, rail, tables | yes after conversion | `STYLE_CHANGED`, next to the existing `FONTS_CHANGED` re-render (`SpellsPane_Forever.lua:1781-1783`); rail and rows re-render on refresh |
| Strings with `UI.Hex(...)` codes | at next refresh | built at render time |
| ~36 creation-time accent reads (1.3) | yes after conversion | each becomes a registered `rule` / `bar` region or a `UI.RGB("accent")` read at paint |
| 68 creation-time `SetTextColor(UI.RGB(..))` | partly | the high-traffic panes (Spells, Review, Practice, Settings) subscribe to `STYLE_CHANGED`; the rest (Sim window, bindings sheet, About) say "finishes after a reload" |
| Replay unit frames, debug legend | unchanged by design | exempt (1.3) |

**Recommendation.** Switch live, then show one line under the dropdown, "Some windows finish
changing after a reload", with a `Reload` button, until the conversions reach 100%. That is
honest, and better than Cell's load-time-only accent (2.2). EllesmereUI's own rule is the same:
"skins install at load, so turning OFF is reload-bound" (`SkinAPI.lua:17-20`).

---

## 7. Effort and risk, as tasks

| # | Task | Size | Risk | Gate |
|---|---|---|---|---|
| S0 | **Infrastructure**: `UI.RegisterStyle` / `SetStyle`; the skin registry replacing `pixelFrames` (role, not colours); `{ref="accent"}` fills; `strips` and `backdrop` + outset painters; `STYLE_CHANGED`; `db.ui.style`; the Look dropdown on both Settings panes; `/st ui style`; `/st dump` line; `MD.API.AtlasInfo` / `FileID`; probe `== art`; `stylecheck`; flat expressed as data | L (comparable to T74 + T75: every primitive touched) | medium: flat must stay byte-identical | every existing suite unchanged; `stylecheck` round trip; apicheck 0 |
| S1 | Convert the ~36 frozen accent reads plus the high-traffic panes' text colours to registry or `STYLE_CHANGED` | M | low | `stylecheck` "every registered region repaints"; spellsui, dashui, reviewui unchanged |
| S2 | **Ellesmere** clone (plus `Token` alpha, `UI.Hex` pre-blend) | S | low | `stylecheck` palette; a screenshot |
| S3 | Ellesmere **follow** on Forever (RegisterSkin, getters, `OnLooksChanged`, fallback) | S-M | low-medium | stubbed `EllesmereUI` in the suite: callback fires, never fires, a looks change repaints |
| S4 | **Modern** (data plus optional `atlas` painter) | S-M | low (atlases off) / medium (on) | probe `== art` from both clients before atlases are turned on |
| S5 | **Classic**: mockups first (M-series, as M1-M6), then `plaque` / `slice3` / `files` painters | L | medium-high (visual) | author approves mockups; probe `== art` confirms every file on both clients |
| S6 | (later) native-art variant, parchment variant | M | high | author's call |

**Order:** S0, then S1 and S2 in parallel, then S3 and S4, then S5. Ellesmere and Modern deliver
two new looks cheaply. Classic waits for its mockups and for the probe's art report.

---

## 8. Decisions for the author

1. **How many styles?** The minimum that answers the request is Flat, Ellesmere and Modern (all
   flat-fill, low risk). Classic is the expensive one. Recommendation: build all four, Classic
   last behind mockups.
2. **Classic brings Blizzard gold back.** Spec 4.1 removed gold from every window (an earlier
   decision of yours). A Classic style needs a ruling that the "no gold" rule belongs to the flat
   style, not to the add-on.
3. **Accent per style or global?** Recommendation: each style has its own default (class colour
   for Flat, gold for Modern and Classic, EllesmereUI's for Ellesmere), with one "Use my class
   colour" check that overrides any of them.
4. **Ellesmere on Forever: follow or clone?** Recommendation: follow when EllesmereUI answers,
   clone otherwise. Never hand SpellTuner's frames to EllesmereUI's `Shell` / `Panel` (3.7).
5. **Tooltips under Classic and Modern:** the game's own (native) or SpellTuner's flat skin?
   Recommendation: native for Classic, a setting for Modern.
6. **Reload line:** acceptable to say "some windows finish after a reload" while S1 is partial?
7. **The clock** (the OOM timer request) gets its look from the style's `clock` role by default.
   The clock customisation work (a separate report) should add "follow the window style" as its
   first option, so the two features share one painter set.
8. **DECISIONS.md.** "graphs/animations/themes" are listed out of scope for v1
   (`docs/DECISIONS.md:37`). This work needs a new decision entry that supersedes that line for
   styles.

---

## 9. Open risks

- **Untested art.**
  - The 32-px dialog edge was designed for 300-400-px dialogs, so on an 860x560 window it may look
    heavy.
  - The 22-px panel-button art at the kit's 18-px small buttons will look squashed.
  - Mockups decide both.
- **Pixel snapping versus art.** `UI.px` snaps 1-px edges (`Style.lua:353-367`). Art backdrops must
  not be snapped (an edge of 32 units), but their outset frame's anchors should be, or the stone
  edge shimmers at 0.71 effective scale. The painter must keep both in mind.
- **Forever's moving atlas map.** A probe answer from one build is not a guarantee for the next
  (docs/probe/* show the API moving between 70009 and 70124). Re-run `== art` on each new build,
  as the other probe sections are.
- **`Token` alpha.** EUI's dim text is white at alpha 0.53. SpellTuner's `|cff` codes cannot carry
  alpha, so the hex must be pre-blended against the style's `bg`. The blend is wrong over any other
  fill (a hovered row), slightly. Acceptable; note it.
- **Two painters.** If EllesmereUI's own "Blizzard window skins" ever reach SpellTuner frames
  without `RegisterSkin` (they target Blizzard windows by name; SpellTuner's frames are
  `SpellTuner*`-named), the fade-to-alpha-0 would hide SpellTuner's backdrop. Not observed; worth
  one in-game look with EllesmereUIBlizzardSkin enabled.
