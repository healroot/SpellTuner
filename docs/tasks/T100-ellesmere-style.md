# T100 -- The Ellesmere style

Status: **built** 2026-10-01 on branch `next/T100`, base `25748e3`. This is wave N3 of
`docs/SPEC-next.md`, alongside T97, T98, T99 and T101. It is waiting for the integrator.

**The branch needs its TOC lines (below).** `UI/Style_Ellesmere.lua` is new and has to be listed
on the three main TOCs, which the integrator owns. Until those lines are in:

- `stylecheck` loads the file itself, where the TOC will put it.
- Every other suite runs as before, since nothing else loads it.

I applied the TOC lines in the working tree only, to run `make check`, and reverted them before
committing.

## The task (docs/SPEC-next.md section 11, row T100; 5.1, 5.5; X1, X4, X5)

> **Ellesmere style (5.1, 5.5)**, with its `clock` role. The clone; token alpha pre-blended into
> hex (X5 noted in the file); the follow (reads `MD.EUISkin` when `apiVersion == 2`, the parent's
> getters, else the clone; repaints on `EUI_LOOKS_CHANGED` and once on `EUI_SKIN_READY`).

These are the files the task owns. They are the only files edited, apart from this one:

- `UI/Style_Ellesmere.lua` (new)
- `UI/Styles.lua`
- `tools/stylecheck.lua`

## What was built

### `UI/Style_Ellesmere.lua` (new): the style, registered as `ellesmere`

**The clone.** It uses EllesmereUI 9.3.4's house values, from 5.1's Ellesmere table and
R-styles 4.2:

- **Panels:**
  - `bg` is `0.05, 0.07, 0.09` at 0.96;
  - `pane` is the same colour at 1;
  - `nav` is the same colour with black at 0.10 over it.
- **Lines and rows:**
  - `border` is white at 0.10;
  - `line` is white at 0.06;
  - `rule` is the accent at 1;
  - `rowAlt` is black at 0.20.
- **Hover and selection:**
  - `hover` is white at 0.08;
  - `selected` is white at 0.04, plus the kit's 2-px accent bar.
- **Controls:**
  - `button` is `0.061, 0.095, 0.120` at 0.6, and `buttonHover` is the same at 0.65;
  - `field` is `0.10, 0.12, 0.16`;
  - `well` is the dropdown fill, `0.075, 0.113, 0.141` at 0.9;
  - `track` is white at 0.10, and `thumb` is white at 0.25;
  - `check` is the accent at 0.75;
  - `tip` is `0.067` at 0.92.
- **Text:**
  - `text` is white;
  - `label` is white at 0.53, and `muted` is white at 0.41, both **pre-blended** (below).
- **Fonts:** Arial Narrow for text and numbers, no outline, shadow (1, -1).
- **Recipes (the strips edges and the edge each control draws):**
  - **Strips:** windows with a white 0.10 edge, panes 0.05, the tooltip 0.18.
  - **Pixel, with these edges:** buttons and tabs white 0.30; fields and lists 0.20; the scroll
    lane and the status bar none.
  - **The `clock` role:** strips with a white 0.10 edge on `bg` (the panel colour).
    - `bar` is the black backing, as Flat's.
    - `barFill` is the accent at 0.75. The layouts (T98, T104) read it.
- **The accent is EllesmereUI's default for the client it runs on:** soft bronze `#DCA77F` on
  Forever and teal `#0CD29D` elsewhere (`EllesmereUI.lua:24-40`). See Deviation 1.

The keys the table leaves out are Flat's: `close`, `go`, `info`, `warn`, `mana`, `good`, `bad`,
`disabled` and `suggested`. They are exempt or unnamed by EllesmereUI's palette.

**X5, the pre-blend, written in the file.** A colour code cannot carry alpha, so `label` and
`muted` are white at 0.53 / 0.41 blended into a hex against this style's own `bg`:

- the clone's `bg` gives `8D9092` / `707376`;
- a followed panel colour gives a blend over that colour.

Over a hovered or selected row the text is a few percent off. That cost is accepted. Regions
keep their real alpha.

**The follow (5.5).** The getters are read fresh at every apply and never cached
(SKINNING_API.md):

1. **`MD.EUISkin` (the skin facade `S`), only while `S.apiVersion == 2`.** The accent is
   `S.GetAccentColor()`. `bg` / `pane` / `nav` come from `S.GetPanelColor()`'s r, g, b, keeping
   the clone's alphas. The face for text and numbers comes from `S.GetFont()`, with its outline
   flag. EllesmereUI draws a shadow only without an outline, so the shadow is (0, 0) when there is
   one.
2. **Any other `apiVersion`** keeps the clone and reads no getter. The dump says
   `skin apiVersion <n>: not followed` (X1).
3. **No facade:** the parent's `GetAccentColor()` and `GetFontPath()`, through `MD.EUIParent`
   (Deviation 2). The panel stays the clone's.
4. **Neither:** the clone.

Each value is checked before it is used:

- a colour must be three numbers in 0..1;
- a font must be a non-empty path with no pipe;
- the flags must be upper-case words, and `NONE` means no outline.

A getter that raises or answers junk leaves that one value at the clone's. Foreign tables are
indexed and called only inside `pcall`.

**Repaints, both through `UI.Styles.Refresh("ellesmere")`.** A repaint fires STYLE_CHANGED once and
leaves `db.ui.style` alone.

- **On `EUI_LOOKS_CHANGED`**, while Ellesmere is the active style. T97's integration fires it
  from `S.OnLooksChanged`.
- **On `EUI_SKIN_READY`, once.** It repaints only when the facade it announces is not the one the
  active paint already decided on (`E.decidedFor`). That covers X4 in both orders:
  - **Arriving after `CORE_LOGIN` applied the style:** one repaint.
  - **Arriving before:** the login's apply already follows it, so the event repaints nothing.
  - **A second ready:** nothing.

SpellTuner's frames are never handed to `S.Shell`, `S.Panel` or `S.Button` (decision 5). Those
fade every texture region of a frame to alpha 0.

**What the file exposes for later tasks:**

- `UI.Ellesmere`:
  - `Source()` gives `skin` / `parent` / `clone` and why, and reads no getter;
  - `Following()` gives what the last apply followed;
  - `Label()` gives the Look dropdown's name, `Ellesmere (following EllesmereUI)` or
    `Ellesmere` (T102);
  - `HouseAccent()`;
  - `TESTED_EUI = "9.3.4"`, `API_VERSION = 2`, and the constants.
- `UI.ELLESMERE`: the registered table. Its `accent` is `"follow"`, 5.1's own word, and it
  carries its `resolve`.

### `UI/Styles.lua`

- **A style may carry `resolve(style) -> style, note`.** `Apply` runs it at every apply.
  - The answer is validated like any style. A resolve that raises, or answers an invalid table,
    applies the registered table, with the note `resolve failed`.
  - The note must be ASCII with no pipe.
  - `Validate` refuses a `resolve` that is not a function.
  - The active entry holds the resolved table, so `Recipe`, the fallbacks and the dump read what
    was applied.
- **`UI.Styles.Refresh(key)`** applies the active style again when it is `key`, and fires
  STYLE_CHANGED once. It returns `false` and does nothing before CORE_LOGIN or under another style.
- **`UI.Styles.Note()`** returns the active resolve's note.
- **The dump line** gains `; <note>` when there is one:
  - `style: ellesmere (accent style) fell back: none; follows EllesmereUI (skin apiVersion 2)`;
  - `...; skin apiVersion 3: not followed`.

  Flat has no resolve, so its line is unchanged.
- **`/st ui style <name>`** adds ` (<note>)` after the style's name when there is a note. Flat's
  `style: flat - Flat` is unchanged, so `slashcheck/tbc`'s golden still holds. That suite loads
  only the kit, the theme and the registry.

## The checks

### `tools/stylecheck.lua` (forever, tbc): +8 per flavour

The suite also loads `UI/Style_Ellesmere.lua` right after `UI/Styles.lua` until the TOCs list
it. Every check runs on both flavours: the clone is a look of its own on TBC, and the follow is
data-driven.

1. **Ellesmere is registered and validates.** So does the clone it resolves to. It has strips on
   windows (white 0.10) and panes (0.05), and its clock role: strips, `bg`, the white 0.10 edge,
   and `barFill` as the accent at 0.75.
2. **The label is white at 0.53 and muted white at 0.41, pre-blended over `bg`.** They read
   `|cff8d9092` and `|cff707376` (X5).
3. **Without `S`, the clone for this flavour.**
   - **Accent:** bronze on Forever, teal on TBC.
   - **Panel:** the house panel.
   - **Fonts:** Arial Narrow with shadow (1, -1).
   - **Edges:** the nav frame's strips at white 0.10, and the button's white 0.30 edge.
   - **Clock:** the clock on the panel colour.
   - **The dump line.**
   - **Flat back is byte-identical** to the paint before the switch.
4. **With a fake `S` (apiVersion 2), the accent, panel (`bg`, `pane`, `nav`) and font come from its
   getters.**
   - The label is blended over the followed panel. Expressway is used with `OUTLINE` and a shadow
     of 0.
   - The dump says it follows.
   - `S` is present before the apply, so EUI_SKIN_READY repaints nothing, both under Flat and
     after.
5. **A looks change repaints once with the new accent.** Under Flat it does nothing.
6. **`S` arriving after SetStyle repaints once (X4)**, with its getters. A second ready repaints
   nothing.
7. **`apiVersion = 3` keeps the clone.** None of its getters is read, and the dump says
   `skin apiVersion 3: not followed`.
8. **Without `S`, the parent's getters give the accent and the font.** A getter that raises or
   answers junk gives the clone's value.

The row asked for 7 checks. The eighth is the parent's-getters fallback that the row's text names.

**Failed first on the parent.** The suite alone was committed first (`051b635`). On the parent's
code it gives:

| | Result on 25748e3 |
|---|---|
| forever | 26 ok, **8 failed** |
| tbc | 26 ok, **8 failed** |

After the change both flavours give **34 ok, 0 failed**.

**Mutations** (each reverted):

| Mutation | What failed |
|---|---|
| EUI_SKIN_READY without the "already decided on this facade" guard | checks 4 and 6 (a second repaint) |
| any `apiVersion` followed | check 7 (3 getter reads, the facade's accent) |
| `label` as a plain grey `878787`, not pre-blended | checks 2 and 4 |

### `make check`

These runs include the TOC lines, applied in the working tree:

| | Before (25748e3) | After |
|---|---|---|
| `stylecheck/forever` | 26 | **34** |
| `stylecheck/tbc` | 26 | **34** |
| `themecheck/forever` | 38 | 38 (`UI/Style_*.lua` is exempt; the file gates on nothing) |
| `slashcheck/tbc` | 10 | 10 (golden unchanged) |
| `defaultscheck` tbc / forever | unchanged | unchanged (no default registered) |
| every other suite | | unchanged |
| `apicheck` | 0 findings | 0 findings, **67** files (one more), 49 globals |
| `textcheck` | 0 findings | 0 findings, **106** files (one more) |
| runs | 81 | **81, all passed**; 76 counted against 76 expected |

The counts step reports only the two NOTEs the integrator's expected-counts lines answer:
`stylecheck/forever` and `stylecheck/tbc` are at 34 against the 26 expected.

On the committed tree, without the TOC lines, `stylecheck` still gives 34 + 34, because it loads
the file itself. Every other suite is unchanged, because nothing else loads the file.

## Integrator lines

- **`SpellTuner_TBC.toc`, `SpellTuner_Mainline.toc`, `SpellTuner.toc`:** add `UI\Style_Ellesmere.lua`
  right after `UI\Styles.lua`. All three are ASCII with LF line endings.
- **`tools/data/expected-counts.json`:**
  - `"stylecheck/forever": 34`
  - `"stylecheck/tbc": 34`
- **`tools/check.sh`:** nothing.
- **T97's `Integrations/EllesmereUI_Forever.lua`:** one line when it is merged, where it finds
  `EllesmereUI` (a table): `MD.EUIParent = EllesmereUI`. This is the parent's-getters fallback
  (Deviation 2). Without it, a player with BlizzardSkin off gets the clone, never a wrong colour.
  The file must also fire `MD:Fire("EUI_SKIN_READY")` after storing `MD.EUISkin`, and
  `MD:Fire("EUI_LOOKS_CHANGED")` from `S.OnLooksChanged`, as T97's row says. Those are the two
  event names this file listens to.
- **`docs/DECISIONS.md`:**
  - "T100: the Ellesmere style's clone accent is EllesmereUI's own default for the client it runs
    on, read as EllesmereUI reads it: the interface (`MD.API.BuildInfo`) in `MD.API.BANDS.forever`
    gives bronze `#DCA77F`, anything else teal `#0CD29D`. TBC gets a new, optional look; nothing
    changes until a player picks it (`/md ui style ellesmere`)."
  - "X5 accepted: EllesmereUI's white-at-alpha text is pre-blended into hex against the style's
    `bg`."
- **`CLAUDE.md`, repo table:**
  - **New row**, `UI/Style_Ellesmere.lua`: the Ellesmere style (T100).
    - The clone uses EllesmereUI 9.3.4's values, the strips edges and a pre-blended label (X5).
    - The accent is EllesmereUI's default for this client.
    - The follow uses `MD.EUISkin` (apiVersion 2 only), else `MD.EUIParent`'s getters, else the
      clone.
    - It repaints on `EUI_LOOKS_CHANGED` and once on `EUI_SKIN_READY` through
      `UI.Styles.Refresh`.
    - It exposes `UI.Ellesmere` (`Source`, `Following`, `Label`, `HouseAccent`, `TESTED_EUI`).
    - It never hands a frame to `S.Shell` / `Panel` / `Button`.
    - It is listed right after `UI/Styles.lua` on every main TOC.
  - **`UI/Styles.lua`'s row:** T100 adds a style's optional `resolve(style) -> style, note` (run at
    every apply, validated, falling back to the registered table), `UI.Styles.Refresh(key)`,
    `UI.Styles.Note()`, and the note on the dump line and on `/st ui style`.
- **`docs/TOOLS.md` section 1:** `stylecheck` (forever, tbc) 34 + 34, with the eight Ellesmere
  checks above.
- **`docs/TESTING.md`** (section 46, styles; in-game checks 8 and 12):
  - `/st ui style ellesmere` on Forever **with EllesmereUI's Blizz UI Enhanced on**:
    - the windows take EllesmereUI's accent, panel colour and font;
    - `/st dump` reads `style: ellesmere ... ; follows EllesmereUI (skin apiVersion 2)`;
    - changing EllesmereUI's accent recolours SpellTuner at once.
  - With third-party skinning turned off for SpellTuner, the same command follows EllesmereUI's
    accent and font, once T97 sets `MD.EUIParent`.
  - On TBC, `/md ui style ellesmere` gives the teal clone. `/md ui style flat` returns
    exactly to today's look.

## Deviations

1. **The clone's accent is chosen by the interface band, not by a value the line installs.**
   - 5.1 asks for bronze on Forever and teal on TBC. This task owns no line file, so no line
     can install the value.
   - The file therefore reads the interface through the adapter (`MD.API.BuildInfo`) and compares
     it with the adapter's `MD.API.BANDS.forever`. That is how EllesmereUI picks its own default
     theme (`EUI_CLIENT_FOREVER` from the interface, `EllesmereUI_ClientGate.lua`).
   - It does not read `MD.API.client`, so apicheck rule 10 holds.
   - One consequence: the Mainline TOC on a retail 12.x client gets teal. That is EllesmereUI's
     own default there too.
   - If the integrator prefers a line-installed value, it can replace `E.HouseAccent()`.
2. **The parent's getters come through `MD.EUIParent`, not the `EllesmereUI` global.**
   - Host globals are named only under `Integrations/` (spec principle 1, apicheck rule 11 from
     T97). R-ellesmere 3.1 also says not to dodge that rule with `_G.EllesmereUI`.
   - The integration file is T97's, so it can hand the table over with one line (integrator
     lines above).
   - Until it does, the no-facade case gives the clone.
3. **Eight checks instead of seven.** The eighth is the parent's-getters fallback that the row's
   text names but its count did not.
4. **The style is registered with `accent = "follow"`**, 5.1's own word. Its `resolve` turns that
   into a colour at every apply.
   - The table it resolves to has a concrete accent, so `UI.StyleAccent`'s "follow"-as-class
     placeholder (T94, `UI/Theme_Flat.lua`, not this task's file) is never reached.
   - It is reached only if the resolve fails.
5. **Followed panel alpha.** `S.GetPanelColor()`'s alpha is not used. `bg` keeps the clone's
   0.96 and `pane` its 1, so a translucent EllesmereUI panel cannot make SpellTuner's windows
   see-through.
6. **Not in this task:**
   - the per-state button edge (white 0.30 / 0.45) and the button label alphas (0.55 / 0.70),
     because the kit's buttons have one edge and their label colour is creation-time (T107);
   - "Use my class colour" and the Look dropdown, which are T102's.
