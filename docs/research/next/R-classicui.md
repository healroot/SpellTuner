# R-classicui: how the "ClassicUI" addons imitate the classic Blizzard UI, and what T108 takes from them

Research note, 2026-10-01, for task T108 (the Classic style, `docs/SPEC-next.md` 5.1 / 5.2 / 5.3)
and the author's request: "check classicUI addon ... to see how they mimik clasic ui". It reads
the addons' published source (cloned into a scratch folder, nothing copied into this tree),
their CurseForge pages, and Blizzard's own UI source for both of SpellTuner's clients
(`Gethe/wow-ui-source`, branches `classic_anniversary` = 2.5.6 (69795) and `forever` = 1.60.1
(70124)). File ids come from the community listfile (`wowdev/wow-listfile`). A claim this note
could not verify is marked **VERIFY**; section 6 says which probe line answers it.

---

## 0. The answer in brief

1. **There are four addons by that name; one matters most.** `ClassicUI` (millanzarreta) is the
   original, retail-only and about the HUD (action bar, micro menu, minimap); it has no dialog
   or window art. **`ClassicUI Forever` (justawower)** is the one that rebuilds *windows,
   dialogs, buttons, check boxes, menus and tooltips* in 1.x art on the Forever client -- the
   closest analogue to SpellTuner's Classic style. `Forevermore Classic UI` (akiragtx) does the
   same on fewer windows and confirms its numbers. `Classic UI (Forever)` (RealJustinCase) is HUD
   only and has no published source.
2. **They use Blizzard's own files by path, never atlases, for the classic look** -- the same
   files SPEC 5.1 already names (`UI-DialogBox-*`, `UI-Panel-Button-*`, `UI-CheckBox-*`,
   `UI-Panel-MinimizeButton-*`, `UI-Tooltip-Border`, `UI-QuestTitleHighlight`,
   `TargetingFrame\UI-StatusBar`). SPEC's file list is right. Atlases appear only for Forever's
   own pieces they fade out.
3. **Presence is tested two ways**: `texture:SetTexture(path)` returns `false` for a file the
   client lacks (ClassicUI Forever builds its whole fallback on this), and `GetFileIDFromPath`
   (Forevermore). `C_Texture.GetAtlasInfo` is asked before any `SetAtlas`.
4. **Presence is not enough on Forever.** ClassicUI Forever ships bundled copies of the Era
   originals for files "the client ships ... as modern stand-ins under these names" (scroll bar
   knob and arrows, `UI-Background-Rock` / `-Marble`, the quest log quarters, the options tabs,
   the nameplate border, the targeting sheets). Same name, same file id, different picture.
   SpellTuner ships no art, so **the probe must show the art, not only look it up**: `== art`
   needs an art sheet the author screenshots once per build (section 6).
5. **Five concrete changes to T108's recipe** (section 5): the tooltip is *not* `native` on
   Forever (the game's tooltip there is Forever's bronze, under the same atlas names), so Classic
   draws its own `UI-Tooltip-Border` rim on both clients, from stretched cells with no size
   arithmetic; the close button and check box art are drawn **larger than** their buttons
   (32 on 20, 24 on 14) instead of squashed; buttons use Blizzard's own 12/x/12 three-slice with
   the caps scaled to the button height, and a too-narrow button takes a small flat recipe; the
   outset is **12**, not ~8, with an opaque underlay because the dialog background is
   see-through; fields and dropdowns get `Common-Input-Border` (20 px, fits the kit) rather than
   the 64-px `CharacterCreate-LabelFrame`. Gold is a literal `ffd100` token: ClassicUI Forever
   found Forever's normal font colour is not the old gold.
6. **TBC is the easy client.** Its own FrameXML still draws with every one of these files
   (section 3), and none of the four addons targets it -- `Classic UI (Forever)` notes that on a
   classic client "the classic look is already there and does nothing". The risk is Forever.
7. **Licences:** GPLv3 (ClassicUI), "All rights reserved" (ClassicUI Forever, Forevermore). We
   copy no code and no art; Blizzard file paths, Blizzard template texcoords and file ids are
   facts read from Blizzard's own source and the listfile, and T108 takes them from there
   (section 4).

---

## 1. The addons

| Addon | Author | Clients (TOC) | Licence | Scope | Source | Last update |
|---|---|---|---|---|---|---|
| ClassicUI | millanzarreta | retail only (`## Interface: 120100`) | GPLv3 (`LICENSE.txt`, TOC `X-License`) | pre-Dragonflight HUD: main bar and gryphons, micro menu, bags, XP/rep bars, minimap, chat buttons; an optional classic guild UI module | github.com/millanzarreta/ClassicUI | v3.0.2, 2026-08-18 |
| **ClassicUI Forever** | justawower | Forever and retail (`## Interface: 16001, 120100`) | All rights reserved; forks only to send pull requests (`LICENSE`) | the HUD **and** windows: "the metal window border ... on the character, inspect, merchant, mail, friends, quest, trade, bank and other windows", "game menu and settings as old dialogs, with the old check boxes, sliders and drop downs", 1.x tooltips and menus | github.com/wowaddonmaker/classicuiforever | 0.14.1, 2026-10-01 |
| Forevermore Classic UI | akiragtx (stavroskasidis) | Forever and retail (`## Interface: 120100, 16001`) | `LICENSE` says All Rights Reserved; the TOC says `X-License: MIT` -- read as the stricter | reskin "Blizzard's own frames with the vanilla art": unit frames, cast bars, minimap, bars, game menu, character frame | github.com/stavroskasidis/ForevermoreClassicUI | 2026-09-30 |
| Classic UI (Forever) | RealJustinCase | retail, Forever, Mists, Titan, Era | MIT (CurseForge) | nameplates, cast bars, unit frames, bars, minimap; "no custom textures are shipped" | none published | 0.7.27, 2026-09-28 |

The CurseForge listing "Forever/Retail Classic UI Restoration" (`classic-ui-restoration`)
fetched as Forevermore's page; treated as the same project.

---

## 2. How they do it

### 2.1 Art by path, with a fallback that never leaves a hole

- **ClassicUI Forever** keeps one art table (`Art/TextureData.lua`): each key is
  `"Dir\\File"` (the client's `Interface\Dir\File`, its own copy as the fallback), `"!File"` (its
  copy only), `"=Dir\\File"` (the client's only). `ns.SetTex` (`Art/Textures.lua`) calls
  `texture:SetTexture(primary)`, and when it returns `false` tries the other copy, recording
  `ok` / `fallback` / `missing` per key for `/fcui debug`. A `B.PREFER` list puts its own copy
  first where "the client redrew some files under the old names". `/fcui textures
  builtin|bundled` switches the source wholesale.
- Its red button: `button:SetNormalTexture(UI-Panel-Button-Up) == false` means "old sheet
  missing on this client" and it falls back to the client's template (`UI/Controls.lua`,
  `ns.PanelButton`). Same for the check box (`ns.SkinCheckbox`).
- **Forevermore** asks `GetFileIDFromPath(path)` ("answers that without drawing a broken
  texture", `src/Modules/Forever.lua`), and also has `ns.HasTexture` -- a probe texture's
  `SetTexture` result (`src/Core.lua`). It guards every atlas with `C_Texture.GetAtlasInfo`
  ("SetAtlas errors on unknown names").
- **ClassicUI (millanzarreta)** sets client paths directly and ships `-classic` / `-custom` BLPs
  for pieces retail changed (clock background, tracking border, micro buttons).

For SpellTuner: both checks are cheap and need no atlas. SPEC 5.3's `MD.API.FileID` stays; add
the `SetTexture` return as the second check where `GetFileIDFromPath` is absent (TBC VERIFY), and
make the probe prove that a missing path really answers `false` on each client (section 6).

### 2.2 Stand-ins: the reason a presence check is not enough on Forever

ClassicUI Forever's art table names files the Forever client still ships under the old path but
redrew (comments in `Art/TextureData.lua`): the scroll bar knob and arrows ("the client ships
modern stand-ins under these names"), `UI-Background-Marble` / `-Rock` and `_UI-Frame` ("Era art
(the client's are stand-ins)"), the quest log quarters ("near-black stand-ins"), the options
dialog tabs, the nameplate border ("a wider redraw"), the targeting sheets and character tabs,
some micro buttons; Era's dropdown sheet is absent ("this client lacks"). A redraw keeps its file
id, so neither `GetFileIDFromPath` nor `SetTexture` can tell. Only a look can.

None of the files SPEC 5.1 relies on for the window, button, check box, close button, tooltip rim,
list highlight or status bar is on that list; ClassicUI Forever draws all of them from the
client on Forever (`UI/Dress.lua` `ns.ART`, `UI/Dialogs.lua` `ns.BACKDROP`). The scroll knob is,
which confirms SPEC's flat gold scroll thumb.

### 2.3 Windows and dialogs

- **The frame is a backdrop on their own child, never on the client's frame**
  (`ns.DialogBacking`): `BackdropTemplate`, Blizzard's `BACKDROP_DIALOG_32_32` recipe (bg
  `UI-DialogBox-Background` tiled 32, edge `UI-DialogBox-Border` 32, insets 11/12/12/11), at the
  host's frame level. Variants: `-Background-Dark`, the gold border, an 8-inset dialog. This is
  SPEC 5.2's `backdrop` painter.
- **Secret sizes.** Their backdrop frames skip the edge tiling while the size is secret
  (`SafeCoords` wrapping `SetupTextureCoordinates`), and the tooltip/menu rim is "nine pieces ...
  each edge one stretched cell ... no size maths, so a frame of secret size ... draws the same"
  (`ns.TipRim`, `UI/Tooltips.lua`). SpellTuner's own windows have plain sizes, but a
  `GameTooltip` carrying a spell description that is secret in combat on Forever may not: the
  tooltip rim must be built this way (5.2).
- **The header plaque** is `UI-DialogBox-Header`, 256 x 64, anchored TOP to the frame at y +12,
  the title's TOP 14 below the plaque's top -- exactly Blizzard's classic dialogs
  (`ColorPickerFrame.xml`, `ChatConfigFrame.xml`, `DialogTemplates.xml` on the
  `classic_anniversary` branch). ClassicUI Forever widens the one texture to
  `max(256, titleWidth + 160)`; Forevermore cuts it in three (ends 38 px at full size, the middle
  stretched; texcoords x 0.2421875 / 0.390625 / 0.609375 / 0.7578125, y 0-1) so the ends stay
  crisp, width `max(titleWidth + 70, 132)`.
- **The close button** is `UI-Panel-MinimizeButton-Up/Down/Disabled/Highlight` on a 32 x 32
  button. The red square fills only the middle of the 32 x 32 file (margins about 6-7 px each
  side, ClassicUI Forever `UI/WindowLocks.lua`).
- **Red buttons** are `UI-Panel-Button-Up/Down/Disabled/Highlight`, the 80 x 22 face in the
  corner of a 128 x 32 file (texcoords 0-0.625 x 0-0.6875), **stretched as one piece** over 96 x
  22 (ClassicUI Forever) or 80 x 22 / 144 x 21 (Forevermore's game menu). Highlight is ADD.
  Labels: gold `GameFontNormal`, white `GameFontHighlight` on hover, `GameFontDisable`.
- **Check boxes**: `UI-CheckBox-Up/Down/Highlight(ADD)/Check/Check-Disabled`, full texcoords,
  filling the (Blizzard 32 x 32 or their 26 x 26) button.
- **Menus and dropdown lists**: the tooltip rim and fill (`TOOLTIP_DEFAULT_BACKGROUND_COLOR`,
  fallback `0.09, 0.09, 0.19`), `UI-QuestTitleHighlight` for the row hover,
  `UI-TooltipDivider-Transparent` for dividers (`UI/Menus.lua`). Dropdown buttons:
  `CharacterCreate-LabelFrame` three-slice and `UI-ChatIcon-ScrollDown-*` arrow (`UI/Controls.lua`).
- **Settings window** (their 0.3.2 changelog): "the see-through dialog box with its header plate,
  the category list and the page each in a thin-bordered inset, ... white group and section
  headers over the gold rows, the old yellow bar under the chosen category" -- the bar is
  `UI-QuestLogTitleHighlight` (`ns.ART.GOLD_BAR`).
- **Scroll bars**: their own Slider with the bundled Era knob and arrows (16 wide), because the
  client's are stand-ins.

### 2.4 Colours and fonts

- `UI/Colors.lua`: "Game fonts in the old gold, whatever colour the client gives them" -- they
  create their own font objects from `GameFontNormal` and force `1, 0.82, 0`; the changelog
  (0.4.x) says "every red button ... wears the old gold on its label rather than the client's
  bronze". So on Forever **the normal font colour is not to be trusted as the old gold**.
  Blizzard defines it in client data (no Lua assignment on either branch), so the probe reads it.
- Faces stay Blizzard's (they inherit `GameFontNormal` / `GameFontHighlight`); nothing loads a
  font file by path.

### 2.5 Retail engine versus classic clients

- Forever is told by the TOC number (`ns.OnForever`: `GetBuildInfo` toc 16000-16999, "branch on
  this, never on whether a function exists"). SpellTuner already has its TOC marker; nothing to
  take.
- On Forever they fade Forever's pieces (`SetAlpha(0)`, `SetAtlas(nil)` first) and lay their own
  child over them; several pieces are drawn from the `-c60` atlas variants when their own bronze
  theme is on (`Units/RaidManager.lua`). Windows met in combat are skinned after
  `PLAYER_REGEN_ENABLED`.
- None of them loads on TBC Anniversary. The `classic_anniversary` source shows why it is not
  needed: TBC's own templates draw with these files (section 3).

---

## 3. Cross-check against Blizzard's own UI source, both clients

Files referencing each path (`grep -l`, Lua + XML) on each branch, and the listfile id. A
reference means Blizzard's own UI uses the file on that client, so it ships; it does not prove the
picture on Forever is the old one (2.2).

| Art | TBC 2.5.6 refs | Forever 1.60.1 refs | File id |
|---|---|---|---|
| `Interface\DialogFrame\UI-DialogBox-Border` | 3 | 3 | 131072 |
| `...\UI-DialogBox-Background` | 5 | 4 | 131071 |
| `...\UI-DialogBox-Background-Dark` | 5 | 6 | 312922 |
| `...\UI-DialogBox-Header` | 10 | 2 (Classic ColorPicker, QuestTimer) | 131080 |
| `...\UI-DialogBox-Gold-Border` / `-Gold-Background` | 7 | 3 | 131076 / 131075 |
| `Interface\Tooltips\UI-Tooltip-Border` / `-Background` | 1 / 2 | 1 / 2 | 137057 / 137056 |
| `Interface\Buttons\UI-Panel-Button-Up` / `-Down` / `-Disabled` / `-Highlight` | 12 / 8 / 7 / 2 | 10 / 7 / 6 / 2 | 130828 / 130825 / 130824 / 130826 |
| `Interface\Buttons\UI-CheckBox-Up` / `-Down` / `-Highlight` / `-Check` / `-Check-Disabled` | 26 / 25 / 25 / 39 | 27 / 26 / 26 / 36 | 130755 / 130752 / 130753 / 130751 / 130750 |
| `Interface\Buttons\UI-Panel-MinimizeButton-Up` (and Down / Highlight / Disabled) | 7 | **0** | 130832 / 130830 / 130831 / 130829 |
| `Interface\TargetingFrame\UI-StatusBar` | 36 | 30 | 137012 |
| `Interface\QuestFrame\UI-QuestTitleHighlight` | 19 | 18 | 136810 |
| `Interface\QuestFrame\UI-QuestLogTitleHighlight` | 12 | 9 | 136809 |
| `Interface\Buttons\UI-Listbox-Highlight2` | 11 | 1 | 130783 |
| `Interface\Common\Common-Input-Border` | 27 | 19 | 130975 |
| `Interface\ChatFrame\UI-ChatIcon-ScrollDown-Up` / `-Down` | 5 / 5 | 2 / 2 | -- |
| `Interface\Buttons\UI-Common-MouseHilight` | 56 | 54 | 130757 |
| `Interface\Buttons\UI-SliderBar-Border` / `-Background` / `-Button-Horizontal` | 1 each | 1 each | 130859 / -- / 130860 |
| `Interface\Buttons\UI-ScrollBar-Knob` | 5 | 3 | 130849 (Forever: stand-in, 2.2) |
| `Interface\FrameGeneral\UI-Background-Rock` / `-Marble` | 14 / 13 | 16 / 12 | 374155 / 374154 (Forever: stand-ins, 2.2) |
| `Interface\OptionsFrame\UI-OptionsFrame-ActiveTab` / `-InActiveTab` | 1 | 1 | 136500 / 136501 (Forever: suspect, 2.2) |
| `Interface\Common\UI-TooltipDivider-Transparent` | 3 | 4 | 918860 |
| `Fonts\FRIZQT__.TTF`, `Fonts\ARIALN.TTF` | 8, 4 | 9, 4 | -- |

What the templates say, on each branch:

- **`UIPanelButtonNoTooltipTemplate` is the same on both** (`Blizzard_SharedXML/SecureUIPanelTemplates.xml`):
  40 x 22, three textures from `UI-Panel-Button-Up` -- Left 12 x 22 texcoords 0-0.09375, Middle
  0.09375-0.53125, Right 0.53125-0.625, all y 0-0.6875 -- `GameFontNormal` / `GameFontHighlight` /
  `GameFontDisable`. The single-piece `UIPanelButtonUpTexture` (0-0.625 x 0-0.6875) also exists on
  TBC. So R-styles 4.4's three-slice coords are Blizzard's, on both clients.
- **`UICheckButtonArtTemplate` draws `UI-CheckBox-*` files on both** (32 x 32).
- **The close button differs.** TBC's `UIPanelCloseButtonNoScripts` uses
  `UI-Panel-MinimizeButton-*` files; Forever's (`Mainline/SharedUIPanelTemplates.xml`) is 24 x 24
  on the atlases `RedButton-Exit` / `-exit-pressed` / `-Exit-Disabled` / `RedButton-Highlight`.
  On Forever the classic close file is referenced by nothing Blizzard ships: probe it.
- **Backdrop presets are identical** (`Blizzard_SharedXML/Backdrop.lua`, equal apart from line
  endings): `BACKDROP_DIALOG_32_32`, `BACKDROP_DARK_DIALOG_32_32`, `BACKDROP_GOLD_DIALOG_32_32`,
  `BACKDROP_SLIDER_8_8` (bg `UI-SliderBar-Background`, edge `UI-SliderBar-Border`, tile 8, edge 8,
  insets 3/3/6/6).
- **The tooltip's NineSlice uses the same atlas names on both** (`TooltipDefaultLayout`:
  `Tooltip-NineSlice-CornerTopLeft`, `_Tooltip-NineSlice-EdgeTop`, ...). On TBC they draw the
  classic look; on Forever the atlas map draws Forever's art (EllesmereUI `RetailAtlas.lua:10-27`,
  R-styles 2.1; ClassicUI Forever's tooltips keep "Forever's own art" until it lays its 1.x rim
  over them). Hence 5.2.
- **`InputBoxTemplate`**: Forever's moved to `Common-Input-Border-TL/-T/...` pieces; the single
  `Common-Input-Border` three-slice (Left 8 x 20 texcoords 0-0.0625, Middle 0.0625-0.9375, Right
  0.9375-1, y 0-0.625) is still used by `Blizzard_AuthChallengeUI.xml` on both branches.
- **`OptionsSliderTemplate`** is 144 x 17 on both; the classic dropdown (`UIDropDownMenuTemplate`,
  `CharacterCreate-LabelFrame` with x 0-0.1953125 / -0.8046875 / -1) is drawn 64 tall around its
  button.

---

## 4. Licence limits

- **ClassicUI (GPLv3).** Copying its code would make the copied work GPL. Nothing is copied.
- **ClassicUI Forever ("All rights reserved"; forks only to propose changes back).** No code,
  structure or bundled art may be taken. Reading for ideas is what a public repository allows;
  the ideas recorded here (backdrop on a child, `SetTexture` returning `false`, rims without size
  arithmetic, gold forced on Forever) are techniques, not expression.
- **Forevermore (All Rights Reserved in `LICENSE`).** Same. Its header three-slice texcoords
  describe Blizzard's file; T108 should re-measure them from the art sheet (6, line 7) rather
  than cite them.
- **Blizzard's art** is used only by path from the running client, as every addon does; SpellTuner
  bundles no copy (the bundled Era copies in ClassicUI Forever's `media/` are exactly what we may
  not do -- where Forever has a stand-in, Classic falls back instead).
- **Sources T108 cites** for every number: Blizzard's own templates (`Gethe/wow-ui-source`
  `classic_anniversary` / `forever`, the files named in section 3) and the community listfile for
  ids. Neither is an addon.

---

## 5. What to change or add in T108's Classic recipe (`docs/SPEC-next.md` 5.1 / 5.2)

Every role: same recipe on both clients (no flavour branch; apicheck rule 10), art by path, no
atlas anywhere in Classic. A role whose art is missing falls back to Flat's recipe for that role
**keeping Classic's colours**, and is listed in `/st dump` (SPEC 5.2). Sizes are the kit's
(`UI.H = { button = 20, small = 18, row = 20 }`, header 20, close 20 x 20, check 14 x 14,
slider 10 tall, rail lane 5).

### 5.1 The table as it should read

| Role | Classic recipe | Art (id) | Fallback | Change from SPEC 5.1 |
|---|---|---|---|---|
| accent / text | literal tokens: accent and label `ffd100`, text `ffffff`, muted / disabled `808080`, good `1aff1a`, bad `ff1a1a` | -- | -- | say **literal**: never read `NORMAL_FONT_COLOR` or inherit `GameFontNormal`'s colour (2.4) |
| window | `backdrop` on an outset child at frame level -1: `BACKDROP_DIALOG_32_32`'s values (bg tiled 32, edge 32, insets 11/12/12/11). **Outset 12** (= the insets, so the stone ends at the content rect and the fill starts there), its anchors pixel-snapped. Plus an **underlay** inside the content rect, black a 0.55 (VERIFY on the screenshot): the dialog background is see-through ("the see-through dialog box"), and tables of numbers over a busy world need it. `MD.Win` grows the clamp by the style's `outset` so the stone never leaves the screen | `UI-DialogBox-Background` 131071, `-Border` 131072 | Flat window | outset ~8 -> 12; underlay; clamp |
| window (option) | `fill = "dark"`: `UI-DialogBox-Background-Dark` (312922) instead of the underlay | 312922 | the default fill | new, optional; mockup picks |
| header | `plaque`: three textures from `UI-DialogBox-Header` (ends 38 px, middle stretched, at full size; texcoords measured on the art sheet), **at scale 0.75** (48 tall, ends ~28), centred on the window, placed from the existing title so the title's centre sits 15 px below the plaque's top (Blizzard: title TOP 14 below a 64-px plaque's top, a 12-px font). Width `max(132, titleWidth/0.75 + 70) * 0.75`. Header strip fill transparent, title in the gold token. The visible plate (about the upper 39 of 64 px, VERIFY) then spans about 5 px above to 5 px below the 20-px strip: the screenshot decides 0.75 vs 0.65 | 131080 | Flat header strip, gold title | single texture -> three-slice; scale; the title is not moved |
| nav / pane / cards | `backdrop` `UI-Tooltip-Border` edge 16, insets 5, fill 0.15 a 0.9, border 0.4 grey, on an **outset child of 4** (the rim sits in the outer ~5 px of the 16-px cell, so it lands on the pane's edge, not over its content) | 137057 / 137056 | Flat pane | outset 4 named |
| button (>= 2 caps + 8 wide) | `slice3` per state from Blizzard's template: Up / Down / Disabled, caps `round(12 * h / 22)` (11 at 20, 10 at 18), texcoords 0-0.09375 / 0.09375-0.53125 / 0.53125-0.625 x 0-0.6875; Highlight one texture over the whole button, `UI-Panel-Button-Highlight` texcoords 0-0.625 x 0-0.6875, ADD. Label gold, white on hover, `808080` disabled | 130828 / 130825 / 130824 / 130826 | Flat button | caps scaled; highlight as one piece |
| button (narrow: the rail's `^ v x`, icon buttons) | flat: transparent fill, 1-px `0.4` grey edge, gold glyph, white on hover | -- | -- | new: three-slice art below ~30 px is all caps |
| close | `files` `UI-Panel-MinimizeButton-Up/Down/Disabled/Highlight(ADD)` drawn **32 x 32 centred on the 20 x 20 button** (the red square is ~19 px, so it matches the box); hit rect unchanged | 130832 / 130830 / 130829 / 130831 | flat gold `x`, red on hover -- **not** `RedButton-Exit` (Forever's bronze) | 32 on 20, not scaled to 0.6; Forever presence is a probe question (3) |
| check | `files` `UI-CheckBox-Up/Down/Highlight(ADD)/Check/Check-Disabled` drawn **24 x 24 centred on the 14 x 14 box** (the box art is ~60% of the file, so ~14 px visible); hit rect unchanged | 130755 / 130752 / 130753 / 130751 / 130750 | Flat check | size fixed at 24 |
| field / dropdown (new) | `slice3` `Common-Input-Border` (Left 8 x h texcoords 0-0.0625, Middle 0.0625-0.9375, Right 0.9375-1, y 0-0.625) at the kit's 18-20; a dropdown adds `UI-ChatIcon-ScrollDown-Up/Down/Disabled` with `UI-Common-MouseHilight` ADD at the row height on the right | 130975, 130757 | Flat field | new role; **not** `CharacterCreate-LabelFrame` (64 px tall around a 32-px button: it would cover the rows above and below) |
| dropdown list / context menu (new) | the tooltip `rim` (5.2) with `UI-QuestTitleHighlight` ADD on the hovered row | 137057, 136810 | Flat list | new: the 1.x menus wore the tooltip rim |
| list hover / selected | hover `UI-QuestTitleHighlight` ADD; selected `UI-QuestLogTitleHighlight` ADD (the "old yellow bar"), vertex gold a 0.6 (VERIFY), no accent bar | 136810 / 136809 | Flat (accent a 0.12 / a 0.28 in gold) | selected file named (was `UI-Listbox-Highlight2` VERIFY: present on both, 130783, but Forever references it once) |
| tab (the view row) | flat: gold label, white when selected, 2-px gold underline | -- | -- | new; `UI-OptionsFrame-ActiveTab` only if the art sheet shows Forever's copy is the old one |
| scroll | flat, gold-tinted thumb | -- | -- | unchanged; confirmed (Forever's knob is a stand-in) |
| slider | flat track (fill 0.15, edge 0.4 grey) at the kit's 10 px; thumb `UI-SliderBar-Button-Horizontal` drawn 32 x 32 centred on the kit thumb, if the art sheet shows it reads at that size | 130860 | Flat thumb in gold | new; Blizzard's slider is 17 tall (`BACKDROP_SLIDER_8_8`): its track would change geometry |
| statusbar | `Interface\TargetingFrame\UI-StatusBar` | 137012 | WHITE8x8 | unchanged |
| rule | gold a 0.5, 1 px; `UI-TooltipDivider-Transparent` where a divider row exists | 918860 | 1-px gold | named |
| tooltip | **`rim`, not `native`**: `Tip:Skin` paints eight `UI-Tooltip-Border` cells (Blizzard's backdrop cuts, from `Backdrop.lua`'s coordinate setup), each edge one cell **stretched, not tiled**, anchored to the corners -- no `GetWidth` / `GetHeight` arithmetic (a spell description can be secret in combat on Forever) -- over a fill `0.09, 0.09, 0.19` a 1 (`TOOLTIP_DEFAULT_BACKGROUND_COLOR`, read once through the adapter, literal fallback); the game's NineSlice faded as today. Same on both clients | 137057 | Flat skin | **change**: `native` would show Forever's bronze tooltip (3) |
| clock | `backdrop` `UI-Tooltip-Border` edge 12, insets 3, outset 3, fill black a 0.8; bar `UI-StatusBar` | 137057, 137012 | Flat clock | unchanged |
| fonts | Friz by path, Arial Narrow numbers by path (already) | -- | -- | unchanged |

### 5.2 New painter and painter details

- **`rim`** (new kind, or a mode of `backdrop`): eight textures of one edge file, cells by the
  backdrop's own cut, corners fixed-size, edges stretched between corners, no size reads. Used by
  the Classic tooltip and the Classic dropdown list. It is the only safe way to dress
  `GameTooltip` on Forever; the window and pane `backdrop` stays `BackdropTemplate` (own frames,
  plain sizes).
- **`files` with an art size**: `{ kind = "files", size = 32, ... }` -- the state textures are
  drawn at `size` centred on the button, outside its rect, the hit rect untouched. Close (32 on
  20) and check (24 on 14) use it. `stylecheck` asserts the button's size and hit rect are equal
  before and after.
- **`slice3` with a cap rule**: `cap = round(12 * h / 22)`, a `minWidth` below which the role's
  `small` recipe applies (`2 * cap + 8`).
- **`plaque`** takes `scale` and anchors from the title's centre, not from the frame top.
- **Outset anchors** pixel-snapped (`UI.px`), the 32-unit edge not (SPEC X6). For Classic the
  outset is a style value (12 window, 4 pane, 3 clock) that `MD.Win` also reads for its clamp.

### 5.3 Presence (T108's `needs`)

- `needs` lists the paths per role. `UI.SetStyle` asks each once per session through one adapter
  call, `MD.API.HasFile(path)`: `GetFileIDFromPath` where it answers, else a hidden texture's
  `SetTexture(path)` return. When neither answers, a path counts as present only if the style
  marks it `trusted` (drawn by Blizzard's own UI on both clients, section 3). Both checks are
  relied on only after the probe has shown that a missing path answers `absent` / `false` on that
  client (6, line 1).
- Presence is not the look. A picture the author marks wrong on the art sheet is handled by
  leaving that art out of the recipe (the role then uses its flat recipe on both clients), never
  by a per-client branch. The recipe above already avoids every file ClassicUI Forever calls a
  stand-in.

---

## 6. What the in-game `== art` probe must check (T87, both clients)

Every line ASCII and escaped as the probe's other sections; every call under `pcall`; nothing is
drawn on screen except by line 7's explicit command.

1. **The method, and a control.**
   `art api fileid=<present|absent> settexture=<bool|nil|error> texfileid=<present|absent>` (is
   `GetFileIDFromPath` a function; what `SetTexture` returns for a known path; does
   `Texture:GetTextureFileID` exist), then the control
   `file Interface\SpellTuner\NoSuchFile id=<..> set=<..>` -- it must read `id=absent` and
   `set=false`, or neither check can be trusted on that client.
2. **One line per path any style names**, Classic's complete list in section 3 plus
   `UI-SliderBar-Background`, `UI-ChatIcon-ScrollDown-Disabled`, `UI-Panel-Button-Disabled-Down`:
   `file <path> id=<n|absent> set=<true|false|nil> tex=<GetTextureFileID after set> want=<listfile id> <same|DIFF|->`.
   `DIFF` would mean the path resolves to another file on this client.
3. **The tooltip question** (5.1 tooltip row): `atlas Tooltip-NineSlice-CornerTopLeft file=<id> <w>x<h>`
   and `_Tooltip-NineSlice-EdgeTop` on both; differing file ids between the two reports confirm
   Forever draws its own art under the shared names. Also `atlas RedButton-Exit ...` (Forever's
   close, to know what the fallback must *not* be).
4. **Colours** read from the client: `color NORMAL_FONT_COLOR <hex>`,
   `color GameFontNormal <hex>`, `GameFontHighlight`, `GameFontDisable`,
   `color TOOLTIP_DEFAULT_BACKGROUND_COLOR <r g b>`. If Forever's `NORMAL_FONT_COLOR` is not
   `ffd100`, 5.1's literal tokens are proven necessary.
5. **Fonts**: `font Fonts\FRIZQT__.TTF set=<bool>`, `font Fonts\ARIALN.TTF set=<bool>`
   (`FontString:SetFont`'s return on a hidden string).
6. **Backdrop sanity**: `backdrop template=<yes|no> dialog=<ok|error: msg> tooltip16=<ok|...> slider8=<ok|...>`
   -- a hidden `BackdropTemplate` frame of 200 x 100 given each preset's values (copied, not the
   global table) under `pcall`.
7. **The art sheet: the stand-in check.** `/st probe art show` (`/md probe art show` on TBC) opens
   one movable frame drawing every Classic piece twice -- at its native size, and at the size the
   style uses (dialog 300 x 200 with outset 12 and a pane inside, the plaque at 1.0 and 0.75 over
   a 20-px strip, buttons 80 x 22 / 60 x 20 / 40 x 18, close 32-on-20, check 24-on-14, the field
   and dropdown at 20, the list hover and selected bars, the tooltip rim around three lines, the
   clock box with a status bar, the slider thumb) -- each labelled with its path. One screenshot
   per client per build. The `== art` section prints `art sheet: not shown this build` until the
   command ran, and the to-do list asks for the screenshot. This is the only way to catch a
   redrawn file (2.2), and it lets T108 measure the plaque's cut and visible height itself.
8. **The `fell back` list** as `/st dump` will print it: `art classic fellback: <roles|none>`, from
   the same presence checks `UI.SetStyle` will run -- so the report shows exactly what Classic
   would look like on that client before T108 ships.

The `== art` lines for Modern's atlases (SPEC 5.3) sit in the same section; Classic needs none.

---

## 7. For `stylecheck` (T108's +6, and three more)

- the tooltip rim reads no size: under the forever profile, a stub tooltip whose `GetWidth`
  returns the secret stand-in is skinned without raising;
- `files` art larger than its button leaves the button's size and hit rect unchanged (close 20,
  check 14);
- a button narrower than `2 * cap + 8` takes the narrow recipe; a 20-tall button's caps are 11,
  an 18-tall one's 10.

---

## 8. Sources

- ClassicUI (millanzarreta): https://github.com/millanzarreta/ClassicUI (v3.0.2, `037dcf3`),
  https://www.curseforge.com/wow/addons/classicui
- ClassicUI Forever (justawower): https://github.com/wowaddonmaker/classicuiforever (0.14.1,
  `ff0a907`), https://www.curseforge.com/wow/addons/classicui-forever, and Warcraft Tavern's note
  https://www.warcrafttavern.com/forever/news/classicui-forever-addon-makes-wow-forever-truly-feel-like-classic/
- Forevermore Classic UI (akiragtx): https://github.com/stavroskasidis/ForevermoreClassicUI
  (`8132287`), https://www.curseforge.com/wow/addons/forevermore-classic-ui
- Classic UI (Forever) (RealJustinCase): https://www.curseforge.com/wow/addons/classic-ui-for-forever
- Blizzard UI source: https://github.com/Gethe/wow-ui-source, branches `classic_anniversary`
  (`1463c68`, 2.5.6 (69795)) and `forever` (`966519c`, 1.60.1 (70124))
- File ids: https://github.com/wowdev/wow-listfile (`community-listfile.csv`, latest release)
