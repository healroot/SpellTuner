# T94 -- The style registry (S2 step 1)

Status: **built** 2026-10-01 on branch `next/T94` (base `231525d`). This is wave N2 of
`docs/SPEC-next.md`, alongside T92, T93, T95 and T96. It is waiting for the integrator.

**The branch needs its TOC lines and one rebuilt fixture (below).** `UI/Styles.lua` is new and
has to be listed on the three main TOCs, which the integrator owns. Until those lines are in:

- `stylecheck` and `slashcheck` load `UI/Styles.lua` themselves, where the TOC will put it.
- The other suites run on Flat exactly as before.

The `ui.style` default now lands in `SpellTunerDB`, so `tools/data/import-forever-sv.lua` gains
one line. Until it is rebuilt, `importcheck` fails, with or without the TOC lines.

I made both changes in the working tree only, to run `make check`, and reverted them before
committing.

## The task (docs/SPEC-next.md section 11, row T94; 2.2, 5.1-5.4; R-styles.md 3)

> **Style registry (S2 step 1).** `UI.Styles.Register` / `Validate` / `SetStyle`, applied at
> `CORE_LOGIN`; Flat as data, **its `clock` role included**; `UI.skinned` by role replacing
> `pixelFrames`; `UI.Skin`; the `pixel` and `strips` painters; `{ ref = "accent" }` fills;
> `STYLE_CHANGED`; `db.ui.style` (reported for `defaultscheck`); `/st ui style` through
> `MD:AddSubcommand`; the dump line through `MD:AddDumpLine`; the `UI.STYLE` gate scan.

These are the files the task owns. They are the only files edited, apart from this one:

- `UI/Styles.lua` (new)
- `UI/Theme_Flat.lua`
- `UI/Style.lua`
- `tools/stylecheck.lua` (new)
- `tools/themecheck.lua`
- `tools/slashcheck.lua`

## What was built

### `UI/Style.lua`: the skin registry

- **`UI.skinned[region] = { role, fill, edge, kind }`.** It is weak-keyed and replaces
  `UI.pixelFrames`, which stays as an alias of the same table for its readers (themecheck and
  clockcheck read it).
  - `fill` and `edge` are `UI.PALETTE` keys wherever the caller handed a palette table.
    `UI.PaletteKey` maps the table back to its key.
  - Otherwise they hold the literal the caller handed.
- **`UI.Skin(region, role, fill, edge)`** registers a region by role and paints it with the
  active style's recipe for that role.
  - A `nil` fill or edge takes the recipe's own `fill` / `edge`. For example,
    `UI.Skin(f, "clock")` gives the `bg` fill and the `border` edge.
  - Without `UI.PIXEL` it draws the old 1-unit backdrop and registers nothing.
- **`UI.StylizeFrame(frame, color, border)` keeps its signature.** The 13 outside callers are
  unedited.
  - It registers through `UI.Skin` under the role its fill implies: `bg` / `frame` -> window,
    `header` / `nav` -> header, `pane` -> pane, `field` / `well` -> field, `track` / `thumb` ->
    scroll, `tip` -> tooltip, the button fills -> button. A literal fill is a pane.
  - A `nil` border is the `border` key. It has the same `{0, 0, 0, 1}` as the old literal, and
    now follows a style.
- **Explicit roles where the kit knows them:**
  - `nav` for the nav frame's and nav box's left column;
  - `header` for the movable frame's header;
  - `list` for the dropdown and tree lists;
  - `field` for the edit box and, through `ControlBackdrop`'s new role argument, the check box;
  - `button` for the kit button.

  Under Flat every role is the pixel painter with the colours each call passed, so the paint is
  unchanged.
- **The painters, `UI.PAINTERS`:**
  - `pixel`: the backdrop `StylizeFrame` always drew under `UI.PIXEL`.
  - `strips`: the fill as a backdrop, and the edge as four 1-px textures over it, created lazily
    as `region._skinStrips`. This lets the edge carry its own alpha. `pixel` hides them again.

  A later style adds its painter by kind. T103 adds `atlas`; T108 adds `backdrop`, `plaque`,
  `slice3` and `files`.
- **A recipe's `edgeColor`** replaces a region's edge while that style is on. `rec.edgeByRecipe`
  remembers it, so the next style starts from the region's own edge again.
- **`UI.CaptureSkins()` / `UI.RepaintSkins(captured)`.** Before the palette is rewritten, each
  region's shown colour is read back by name:
  - its own fill key;
  - else the key of its `hoverColor`;
  - else `selected`, which is a button group's active button;
  - else the literal it shows.

  The edge is read the same way against its own edge. After the rewrite each region is painted
  with the same names in the new style. A hovered button stays hovered and the active nav group
  stays selected across a switch.
- **`UI.RestylePixels()`** is now `RepaintSkins(CaptureSkins())`. It keeps the old behaviour (a
  new edge, the colours shown now) and the same return count.
- `UI.SkinColour`, `UI.SKIN_ROLES` (the 13 roles of 2.2), and `UI.classAccent` /
  `UI.classAccentHex` (the class colour as read, so "class" can be restored exactly).

### `UI/Theme_Flat.lua`: Flat as data, and the appliers

- **`UI.FLAT`** is 5.1's first table:
  - `accent = "class"`;
  - all 31 palette keys, with the accent fills as `{ ref = "accent", a = n }`. These are
    `rule`, `hover`, `selected`, `suggested`, `thumb`, `check`, `checkHover`, `accentFill` and
    `accentHover`;
  - the ten text tokens;
  - the fonts: Friz, Arial Narrow, no outline, shadow (1, -1);
  - one pixel recipe per role, each with its default fill and edge. **The `clock` role is
    included:** `bg` fill, `border` edge, and a `bar` backing in black for T98's layouts.

  Every key a style may set is in it, so Flat restores whatever another style changed.
- **`UI.STYLE_ALIASES`**: `frame = bg`, `header = nav`, `text2 = label`, `dominated = text`,
  `note = label` and `tipGold = accent`. These are structure, so a style may not set them.
- **`UI.StyleAccent(style)`** returns the accent:
  - "class" gives the class colour;
  - "gold" gives `ffd100`;
  - `{r, g, b}` gives that colour;
  - "follow" gives the class colour until T100.
- **`UI.ApplyStyleTokens(style)`**:
  1. rewrites `UI.accent` **in place** and sets `UI.accentHex`;
  2. writes every fill into `UI.PALETTE` and every token into `UI.TEXT` **in place**, taking any
     key the style leaves out from Flat;
  3. sets the aliases.
- **`UI.ReFaceFonts(style)`** applies the style's faces, flags and shadow to every kit font at its
  current size. A style never changes a size. It also recolours the two class fonts in the
  accent, and fires no `FONTS_CHANGED`. `UI.ApplyFonts` now sizes with the active faces.
- **At load the file applies Flat itself.** That writes the palette, tokens, aliases and fonts it
  wrote before T94, so nothing changes while no other style is chosen.
- **`db.ui.style = "flat"`** is declared here with `MD:RegisterDefaults`, beside `fontOffset`
  (Deviation 2).

### `UI/Styles.lua` (new): the registry

- **`UI.Styles.Validate(style)`** returns `true`, or `false` plus a list of problems. It refuses:
  - a name or hint that is not printable ASCII, or that contains a pipe;
  - an accent that is not class / gold / follow / r,g,b;
  - a palette key Flat lacks, or an alias key;
  - a fill outside 0..1, or a `ref` other than accent;
  - a token that is not six hex digits and not `{ ref = "accent" }`;
  - a malformed font;
  - an unknown role, or a painter `UI.PAINTERS` lacks;
  - a recipe colour that names no palette key;
  - a need that is not `{ role, atlas }` or `{ role, file }`.
- **`Register(key, style)`** raises on an invalid style, a bad key or a key already registered.
  `Get`, `Keys` and `Active` read the registry.
- **`UI.Styles.Recipe(role)`** returns the active style's recipe for a role. It falls back to
  Flat's when the style names none, or when one of the style's `needs` for that role is missing.
- **Presence checks (5.3):**
  - An atlas is present only when `MD.API.AtlasInfo` answers for it.
  - A file is present unless `MD.API.FileID` answers nil.
  - Neither binding exists yet; T103 adds them. With no binding, files are assumed present and
    every atlas is refused.
- **`UI.SetStyle(key)`** (also `UI.Styles.SetStyle`):
  - Before CORE_LOGIN it raises.
  - An unknown key returns `false, "unknown style 'x' (styles: flat, ...)"` and changes and fires
    nothing.
  - Otherwise it captures, applies the tokens, re-faces the fonts, repaints, sets `UI.STYLE`,
    saves `db.ui.style`, fires `STYLE_CHANGED` (key) once, and returns `true`.
- **At CORE_LOGIN** the saved style is applied, before `MD_READY` builds the clocks. A saved key
  nobody registered applies Flat for the session and keeps the saved key. That covers a style file
  that did not load.
- **`/st ui style <name>`** is registered with `MD:AddSubcommand("ui", "style", ...)`:
  - `/st ui style` lists the styles;
  - an unknown name prints the refusal.

  On Forever the row reads `/st ui reset / style <name>`. On TBC it creates the `ui` verb:
  `/md ui style <name>`, whose bare verb prints its usage.
- **The dump line** reads `style: <key> (accent <class|style>) fell back: <roles|none>`. It goes
  through `MD:AddDumpLine("style", ...)` and is added the first time a style other than Flat is
  applied or a role falls back (Deviation 1).

## The checks

### `tools/stylecheck.lua` (new, forever + tbc)

The suite loads the flavour's TOC itself, using the harness's own steps without the events, so it
can look between the last file and PLAYER_LOGIN. On TBC it loads the whole TOC, UI included.

**The golden.** Each flavour's first Flat paint of these regions was captured with `--golden` on
the parent `231525d`, before any edit:

- a nav frame (an active group and view tab);
- an `accent-hover` button and a `red` button;
- a ticked check box;
- a rail with a selected row;
- the clock: `SpellTunerClock` on Forever, `SpellTunerWidget` on TBC;
- `UI.PALETTE`, `UI.TEXT`, the aliases, the accent;
- every kit font object.

Each section is stored as a line count and a checksum. The first commit (`51ac716`) holds the
suite alone, golden included.

**Assertions, 26 per flavour:**

1. No styled frame is built before PLAYER_LOGIN. 2. `UI.SetStyle` before CORE_LOGIN raises.
   3. Flat is applied at login once. 4. The regions are registered by role (`window`, `button`,
   `field`, `pane`, the clock), and `UI.pixelFrames` is `UI.skinned`.
2. Flat validates. Flat names all 13 roles with the pixel painter, the clock's `bg` / `border`
   included. **The first Flat paint equals the parent's golden.**
3. Six malformed styles are refused, and `Register` raises (invalid, duplicate).
4. A test style:
   - It registers.
   - Applying it sets `UI.STYLE` and `db.ui.style` and fires `STYLE_CHANGED` once.
   - The `{ref}` fills and the tokens follow its accent.
   - The nav frame repaints: its window with the strips edge, its column, and its selected group
     in the new `selected`.
   - The button, the check box and the rail repaint: the rail's strips and its scroll bar.
   - The clock repaints.
   - The fonts are re-faced at their sizes, with the class fonts in the accent.
5. Back to Flat, with a button hovered at the moment of the switch:
   - `STYLE_CHANGED` fires once and the hover is kept.
   - **The result is byte-identical to the first paint.** That covers every region line, the
     palette, the tokens and the fonts.
   - The strips are hidden.
6. An unknown name is refused, naming the styles, and nothing changes or fires.
7. The dump line. A style whose `needs` atlas is missing falls back to Flat's button recipe and is
   listed. `UI.Skin(f, "clock")` paints the role's fill and edge.
8. `/st ui style <name>`, an unknown name, a bare `/st ui style`, and the help row. `/st ui reset`
   still reaches the window manager in either load order: Forever's real `ui` verb, then the verb
   registered again after the sub, on both lines.

**Fails first on the parent:**

| | Result on 231525d |
|---|---|
| forever | 4 ok, 22 failed |
| tbc | 4 ok, 22 failed |

The 4 that pass on the parent are the golden itself, the vacuous byte-identity round trip, "no
strips shown", and "nothing registered at load". After the commit both flavours give
**26 ok, 0 failed**.

After that first commit three test-side mistakes were fixed (the golden is unchanged):

- the callback signature (`function(key)`);
- the stub's 3-value text colour;
- the override field's name, `edgeColor`.

**Mutations** (each reverted):

| Mutation | What failed |
|---|---|
| `selected` dropped from the capture | "the nav frame repaints ... its selected group" |
| `HideStrips` a no-op | "the strips Test made are hidden again" |
| Flat's `well` set to `0.16` blue | "the first Flat paint equals the parent's" (palette) |

### `tools/themecheck.lua`

- **forever: 37 -> 38.** The new check is "T94: no UI file outside the style files branches on
  UI.STYLE". It scans `UI/` and the modules for `UI.STYLE ==` / `~=`, `if UI.STYLE`,
  `not UI.STYLE`, `UI.STYLE and` / `or` and `[UI.STYLE]`. The kit, the registry and
  `UI/Style_*.lua` are exempt. The scan is first fed a planted gate, so it is known to see one.
- tbc stays at 9.

### `tools/slashcheck.lua` (tbc)

**Re-based for the new `/md ui style`.** The TBC harness drops `UI/`, so the suite now loads:

- `UI/Style.lua`, `UI/Theme_Flat.lua` and `UI/Styles.lua`, as the TOC lists them;
- CORE_LOGIN again, so the saved style is applied as at a login.

`ui`, `ui style`, `ui style flat`, `ui style Nosuch` and `ui reset` joined VERBS. The help check
moved from 27 to 28 rows.

I compared the transcript with `--print` before and after the edit. The only differences are:

- the new help row in every printed help: `help` and `nosuch`, both passes;
- the ten new `ui` entries;
- the two new About lines.

The count stays at **10 ok, 0 failed**.

### `make check`

These runs include the TOC lines and the rebuilt fixture, applied in the working tree:

| | Before (231525d) | After |
|---|---|---|
| runs | 77, all passed | **79**, all passed |
| counted against expected | 72 of 72 | 74 (the 72 equal or more; `stylecheck/forever` 26, `/tbc` 26 new) |
| `themecheck/forever` | 37 | **38** |
| `slashcheck/tbc` | 10 | 10 (golden re-based) |
| `defaultscheck` | tbc 49, forever 52 | **tbc 49, forever 52** (the scan finds `ui.style` with its default; no count moves) |
| navui / dashui / spellsui / replayui | 46 / 84 / 50 / 107 | 46 / 84 / 50 / 107 |
| consolecheck, corecheck, wincheck, clockcheck | 22+1, 29+29, 66+4, 29 | unchanged |
| `apicheck` | 0 findings, 63 files, 48 globals | 0 findings, **64** files, **49** globals |
| `textcheck` | 0 findings, 9 TOCs, 102 files | 0 findings, **103** files |

On the committed tree, without the TOC lines and the rebuilt fixture, there are 79 runs. Of
those, only `importcheck` fails (20 ok, 1 failed), on the one-line fixture difference, and so
does the counts step that expects it. Everything else passes, `stylecheck` and `slashcheck`
included, because they load `UI/Styles.lua` themselves.

## Integrator lines

- **`SpellTuner_TBC.toc`, `SpellTuner_Mainline.toc`, `SpellTuner.toc`**: add `UI\Styles.lua` right
  after `UI\Theme_Flat.lua`, before `UI\EscStack.lua` / `UI\Windows.lua`. All three are ASCII
  with LF line endings.
- **`tools/data/import-forever-sv.lua`**: rebuild with `bash tools/run.sh tools/importfixture.lua`
  once the TOC lines are in. The diff is one line, `["style"] = "flat",` in `SpellTunerDB.ui`.
  Rebuild once at the wave's end if another N2 task changes stored defaults too.
- **`tools/data/expected-counts.json`**:
  - `"stylecheck/forever": 26`
  - `"stylecheck/tbc": 26`
  - `"themecheck/forever": 38`

  `slashcheck/tbc` (10), `defaultscheck/tbc` (49) and `defaultscheck/forever` (52) are unchanged.
- **`tools/check.sh`**: nothing. `stylecheck` is found by its `HARNESS_FLAVOUR` line.
- **`docs/DECISIONS.md`**: "T94: `/md ui style <name>` on TBC (decision 1 as answered: four
  styles; 5.4)".
  - The TBC line gains a `ui` verb, created by `UI/Styles.lua` through `MD:AddSubcommand`. Its help
    row and About row read `/st ui style <name> - the look of SpellTuner's windows (no name: list
    the styles)`.
  - `slashcheck/tbc`'s golden was re-based for it: the row, the five `ui` lines and the two About
    lines; every other line equals the 8c4cc93 golden.
  - With only Flat registered, nothing else a TBC player sees changes. Flat stays byte-identical:
    `stylecheck`'s golden is the parent's paint.
- **`CLAUDE.md`, repo table**:
  - **New row**, `UI/Styles.lua`: the style registry (T94). It holds `UI.Styles.Register` /
    `Validate` / `Get` / `Keys` / `Recipe`, and `UI.SetStyle` (capture, tokens in place, re-face,
    repaint, `UI.STYLE`, `db.ui.style`, `STYLE_CHANGED`; raises before CORE_LOGIN). It applies
    the saved style at CORE_LOGIN, registers `/st ui style` through `MD:AddSubcommand` and the
    lazy `style:` dump line, and does the presence checks for `needs`. It is listed right after
    `UI/Theme_Flat.lua` on every main TOC.
  - **Additions to `UI/Theme_Flat.lua`'s row**: T94: `UI.FLAT` (Flat as data, its `clock` role
    included), `UI.STYLE_ALIASES`, `UI.StyleAccent`, `UI.ApplyStyleTokens` (in place),
    `UI.ReFaceFonts`, `db.ui.style`.
  - **Additions to `UI/Style.lua`'s row**: T94: `UI.skinned` by role (`UI.pixelFrames` its old
    name), `UI.Skin(region, role, fill, edge)`, `UI.PAINTERS` (`pixel`, `strips`),
    `UI.CaptureSkins` / `RepaintSkins`, `UI.PaletteKey`, `UI.SKIN_ROLES`, `UI.classAccent`.
  - **Convention line**: "A style is paint only; no pane branches on `UI.STYLE` (themecheck)".
- **`docs/TOOLS.md` section 1**: `stylecheck` (forever, tbc), 26 + 26, as described above.
- **`docs/TESTING.md`**: nothing new to test by hand until a second style ships (T100). The one
  possible check is `/st ui style` (and `/md ui style` on TBC), which lists `flat`.

## Deviations

1. **The dump line is added the first time a style other than Flat is applied** (or a role falls
   back), not at load.
   - `consolecheck/forever`'s T113 case 22 asserts the dump's client section is its two lines
     "with nothing registered". It reads a session where only the TOC's files ran.
   - A line registered at load would break that check, and `consolecheck` is not this task's
     file.
   - A player who never left Flat therefore gets the dump they had. Once another style has been
     applied the line stays, and reads `style: flat (accent class) fell back: none` after a
     return to Flat.
2. **`db.ui.style`'s default is declared in `UI/Theme_Flat.lua`**, beside `fontOffset`, not in
   `UI/Styles.lua` (2.2 names the latter).
   - `defaultscheck/tbc` asserts that the files declaring `db.ui` are exactly the theme, the ESC
     stack and the window manager. `defaultscheck` is not edited by tasks (section 11).
   - The value and the reader are as the spec says.
3. **A recipe's override is `edgeColor`.** Its `fill` / `edge` are the defaults `UI.Skin` takes
   when the caller names none.
   - If `edge` were an override, Flat's recipes would force every pane's edge to `border`. The
     sheet's accent edge would then be lost.
   - The strips edges of 5.1 (Ellesmere's white at 0.05 / 0.10) are `edgeColor`s.
4. **The clock registers as `window`**, the role its `bg` fill implies, because `UI/Widget.lua` and
   `UI/Clock_Forever.lua` (T93's this wave, T98's next) call `UI.StylizeFrame`. It repaints with
   every style. `UI.Skin(widget, "clock")` is T98's line; Flat's `clock` role is ready for it.
5. **"Use my class colour"** (5.4) is not here. It is T102's control. `UI.StyleAccent` is where its
   override will sit.
6. The task touched `tools/data/import-forever-sv.lua` only in the working tree. The rebuild is an
   integrator line above.
