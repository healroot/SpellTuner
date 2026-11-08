# T142: the Bar layout's texts placed one by one, the game bar frame, the author's look the default (both lines)

The author, 2026-11-08, after the mockup `tools/.cache/clockbar2/index.html`
(https://claude.ai/artifact/Rqh3DjZXVBPFRH3MRhCcnR):
- They want to "replicate that manabar [EllesmereUI's] like for like, with fonts and so on".
- They want "each text be configured separately, so some can be inside bar, some above/below".
- They don't want "text making bar higher".
- Then they picked a look in the mockup and said: "lets set this as default (and override my ingame setting)".

Read the mockup's `bar()` and `PRESETS` (`mine`, `eui`, `below`): they are the visual spec. Where this
file and the mockup disagree, this file wins.

## What EllesmereUI does (read from its code in the author's Forever client, Blizzard style on)

`EllesmereUIResourceBars/EUI_ResourceBars_Style.lua` `ns.ERB_ApplyBlizzBarChrome` and
`EUI_ResourceBars_Groups.lua` `ns.ERB_BlizzBarShadow`:
- **Frame art:** atlas `UI-HUD-CoolDownManager-Bar-BG` on a BACKGROUND -2 texture, anchored TOPLEFT
  (-2, 3) and BOTTOMRIGHT (6, -7) round the bar. Most of that reach is the art's own bottom-right
  shadow; its rim is about 1 px round the fill. `SetSnapToPixelGrid(false)`, `SetTexelSnappingBias(0)`.
- **Mask:** a mask texture with atlas `UI-HUD-CoolDownManager-Bar` set on all points of the bar, added
  to the fill texture and to the background texture. This gives both the stock fill's rounded,
  soft-edged shape.
- **Bevel:** four WHITE8X8 textures at OVERLAY -3 over the bar, each masked by the same mask. For a
  horizontal bar of height h and width w:
  - top: height max(2, floor(h * 0.2)), black, alpha 0.55 at the edge fading to 0;
  - bottom: height max(1, floor(h * 0.1)), alpha 0.30 at the edge fading to 0;
  - left and right ends: width max(2, floor(w * 0.15)), alpha 0.35 at the edge fading to 0.
- An atlas the client lacks: EllesmereUI checks `C_Texture.GetAtlasInfo(name)` first.

## What to build

### 1. Each of the Bar layout's texts placed on its own

The Bar layout gets one item per text kind, replacing its Left / Centre / Right slots and its
`bars.bar.text` (inside / above / below / off). The kinds are:

| Kind | Sample | Notes |
|---|---|---|
| `label` | `OOM` | the face's label word |
| `time` | `1:20 v` | the face's value |
| `mana` | `1020` | |
| `manaMax` | `1020/2400` | |
| `pct` | `42%` | |
| `mp5` | `92 mp5` | |
| `fsr` | `5SR 3.0` | |
| `rest` | `rest 2:10` | |

Each item has these fields:
- `on`;
- `place`: inside / above / below;
- `align`: left / center / right, from the bar's left edge, centre or right edge;
- `x`: -40..40 px, and `y`: -20..20 px, moving the text from that anchor;
- `size`: 6..32;
- `colour`: RGB;
- `outline`: none / outline / thick / shadow.

Rules:
- **Text outside the bar never changes the bar's height or the clock frame's size.** The frame is the
  bar. Above / below texts hang outside it, anchored to its top or bottom edge.
- An inside text that is not centred gets a 2 px pad from its edge, as in the mockup.
- **The Line and Compact layouts are unchanged**, with their slots, `ClockFace.TEXT_*` and size and
  outline settings.
- **Words:**
  - The `~` (modelled) prefix, the arrows and the ASCII-only / no-bare-`|` rules stay as
    `ClockFace` makes them.
  - With `label` off, the time carries the label when the face needs one to be read (follow
    ClockFace's existing rule for a label drawn nowhere). Say in the task report what you chose.
  - `mana` / `pct` still ask `draw.powerText` first, as the slots do today.
- **The store:** `text.bar.items.<kind>.<field>` in `clockLook.over`, sparse like the rest, with
  defaults registered.
  - Validate every field: a bad value falls back to the default, and `look.refused` names it.
  - `CV.Resolve` gives `look.items` (or a name you choose) to the renderer.

### 2. The bar's frame, and its font

- **`bars.<layout>.frame`:** `none` / `border` / `game` (Bar layout only).
  - `border` is today's `border` width (keep the 0-3 width field).
  - `game` draws EllesmereUI's art, mask and bevel exactly as above, round the Bar layout's bar. The
    moving 5SR line stays above the bevel.
  - `game` replaces the border.
  - Without the atlases (TBC, or a client missing them): draw `border` and name why in
    `look.refused`.
  - **The client read (atlas present) goes through `ST.API`** (add a function to `Client/API.lua`,
    with harness stubs). ClockView reads no client value. Setting an atlas or mask on a texture
    ClockView owns is a draw call, which is allowed.
- **`bars.bar.font`:** `eui` (EllesmereUI's font, read live through the same path
  `UI/Style_Ellesmere.lua` already uses; each item's own outline always applies) / `st` (the kit's font). Without EllesmereUI, `eui` draws `st` and says why.

### 3. The default (the author's pick, the mockup's screenshot)

The new `CV.BARS_DEFAULT` / registered defaults for the Bar layout:
- frame `game`, shape `round`, width 200, bar height 8;
- texture `eui:pixels-dark` (without EllesmereUI: `soft`, by the existing fallback rule);
- fill 396DA7, background 0A0A0A at alpha 1, background not textured;
- 5SR: the moving line (join `sweep`, as today);
- font `eui`;
- items:
  - `time`: on, below, left, x 0, y -1, size 11, colour E4E1DC, outline none;
  - `mana`: on, inside, center, x 0, y 0, size 11, colour E4E1DC, outline none;
  - `mp5`: on, below, right, x 0, y -1, size 11, colour 9FD7A9, outline none;
  - every other kind off, keeping the mockup's `mine` values for its other fields.

### 4. Override the saved look once

Add a store version to `db.clockLook`, for example `v = 2`. The first time a store below that is read
(in `CV.Migrate` / `MigrateStored`):
- clear every Bar-layout override (`bars.bar.*`, `text.bar.*`, the Bar layout's frame size, and the
  bar colours `colors.manaBar`, `bar.back`, `colors.fillEnd`, `colors.edge`, `colors.fsrLine`,
  `colors.after` if they are stored as overrides);
- set the version.

Line and Compact overrides and the chosen layout are kept. A dump line names what was reset. This
applies to every beta install, which the author accepted ("override my ingame setting").

### 5. Settings -> Clock -> Bar look (`UI/ClockSettings.lua`)

- **Frame:** None / Border / Game bar frame. Border keeps its width control.
- **Font:** EllesmereUI's / SpellTuner's.
- **Texts table:** one row per kind (Show, Text, Place, Align, X, Y, Size, Colour through
  `ST.API.PickColour`, Outline). Rows that are off are dimmed. Each control writes through
  `ST.ClockView.Set`.
- **Presets, `CS.PRESETS`:**
  - `default` is the new default.
  - `eui` "Like my EllesmereUI": game frame, round, 260 x 8, Pixels Dark, fill 008CFF (live as today),
    background 111111, font `eui`, `mana` inside center x 0 y 2 size 15 E3E3E3 outline, the rest off,
    5SR line off.
  - "Words below" as in the mockup.
  - Keep the existing `pill` and `thin` presets, with their words moved into items.
- Remove the old Text place control and the Bar layout's slot pickers. The Line and Compact text
  controls stay.

## Rules that bind (CLAUDE.md)

- ClockView never shows or hides the frame, and reads no client value or `ST.db` outside its store.
- A colour a style can change is a name or a token read at paint (`tools/restylecheck.lua`). The item
  colours are the player's own values.
- Every frame you style needs `BackdropTemplate`.
- Strings are ASCII only (`tools/textcheck.py`).
- `make check` must be green. Update `tools/data/expected-counts.json` and the golden suites only for
  what this change means. Rebuild `tools/data/import-forever-sv.lua` (`tools/importfixture.lua`)
  because the stored look changes.

## Acceptance

- `tools/clockui.lua` and `tools/clocksettings.lua` cover:
  - the item store and its validation;
  - the migration: an old store is reset once, Line overrides are kept, and a second read changes
    nothing;
  - outside texts leave the frame's size alone;
  - the game frame with and without the atlases;
  - the font fallback;
  - each preset.
- `make check` green.
- `docs/TESTING.md` §63 (in game, Forever, about 5 min): the default looks like the mockup's left
  side; the game frame matches EllesmereUI's bar beside it; each text moves on its own; TBC falls back
  to Border with the reason.
- `docs/HISTORY.md`: a dated entry. `CLAUDE.md`: update the `UI/ClockView.lua` and
  `UI/ClockSettings.lua` rows in a line each.
- Commit on `worktree-forever-talents`, message `T142: ...`, ending with the
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` line.
