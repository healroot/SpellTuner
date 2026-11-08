# T142 implementer report: the Bar layout's texts, the game frame, the font

Task: `docs/tasks/T142-bar-texts-game-frame.md`. Branch `worktree-forever-talents`. Not installed,
pushed or published.

## What was built, file by file

- **`UI/ClockView.lua`**
  - The Bar layout's look is now `bars.bar = { frame = "game", font = "eui", shape = "round",
    texture = "eui:pixels-dark", height = 8 }`, with `textureFallback = "soft"`. `CV.BarsDefault(layout)`
    merges a layout's own defaults over `CV.BARS_DEFAULT`, which no longer has `text`.
  - Texts are items. `CV.ITEM_KINDS` holds label, time, mana, manaMax, pct, mp5, fsr and rest. Each
    item has on, place (inside / above / below), align, x (+-40), y (+-20), size (6..32), colour (a
    6-digit hex) and outline (none / outline / thick / shadow). They are stored sparse at
    `text.bar.items.<kind>.<field>` and validated by `ITEM_OK`. A refused value falls back to the
    default and is named in `refused`. `CV.ResolveItems` builds `look.items`.
  - `ITEMS_DEFAULT` is the author's pick:
    - time: below left, y -1;
    - mana: inside, centre;
    - mp5: below right, 9FD7A9;
    - the rest: off, carrying the mockup's values.
  - Outside texts never size the frame. The frame is the bar (h = `bars.height`). Only inside texts,
    plus the chip, set a minimum width.
  - Anchors: an inside text that is not centred gets a 2-px pad. Above and below use a 1-px gap plus
    the border's width when the frame is the border.
  - The game frame:
    - `CV.GAME_ATLAS` = `UI-HUD-CoolDownManager-Bar-BG` for the art and `UI-HUD-CoolDownManager-Bar`
      for the mask.
    - The art is drawn at BACKGROUND -2, the masks are applied, and 4 bevels are drawn at OVERLAY -3
      with `SetGradient`.
    - `CV.GameFrameOK` asks `ST.API.HasAtlas`. If the atlas is missing (TBC), the frame falls back to
      the border and `refused["bars.bar.frame"]` carries the reason.
  - The font: `CV.BarFont` uses EllesmereUI's font (`UI.Ellesmere.FontPath`) when the store asks for
    it, else the kit's face with the reason. The face is cached once per `SetLook`.
  - The reset: `CV.ResetBarLook` runs once, from `MigrateStored`. It clears `bars.bar`, `text.bar`,
    `frame.bar` and the bar colours (`colors.manaBar`, `bar.back`, `colors.fillEnd`, `colors.edge`,
    `colors.fsrLine`, `colors.after`), then sets `v = 2`. The dump line reads
    `clock: T142 reset the Bar look, N overrides (...)`. A fresh store starts at `v = 2`. Line and
    Compact overrides are kept.
  - `CV.SetMany(list)` writes many overrides and fires CLOCK_LOOK once.
  - Text paint goes through `PaintItems`. The old label and value aliases point at the label and time
    items. `CV.REGION.bar` is removed.
- **`Engine/ClockFace.lua`**: added `CF.ItemPieces(face, text, look, labelOn)`, which gives each item's
  words.
- **`Client/API.lua`**:
  - `SetGradient` takes an optional 10th argument, the orientation.
  - New `ST.API.HasAtlas(name)`, which calls `C_Texture.GetAtlasInfo` through `Call` and checks only
    the type of the answer.
- **`UI/Style_Ellesmere.lua`**: new `E.FontPath()`, which reads the same way `Resolve` does (the skin's
  `GetFont`, else the parent's `GetFontPath`) and returns nil plus a reason otherwise.
  - The font that `Resolve` just read is handed once to the next `E.FontPath` call. Without this, the
    clock's rebuild on STYLE_CHANGED asked EllesmereUI for the font a second time, and
    `tools/stylecheck.lua`'s read count failed (3 reads instead of 2).
  - The assertion was not changed. The extra read was removed instead.
- **`UI/ClockSettings.lua`**: the Bar look tab was rebuilt.
  - At the top: Shape and Texture.
  - Then two rows of buttons, Bar layout only:
    - Frame (none / border / game). A refused game frame names its reason in the tooltip.
    - Font (SpellTuner / EllesmereUI), with the reason in the tooltip.
  - Below that, a scroll frame holds:
    - the height and border sliders (border is enabled only when the frame is the border);
    - the 6 colour swatches;
    - the texts table: one row per item, with on, place, align and outline step buttons
      (right-click steps back), x / y / size number boxes (clamped) and a colour swatch. Rows that
      are off are dimmed;
    - the presets: default, eui, below, pill, thin, applied in one `SetMany`.
  - On Bar, the Text tab hides the slot pickers, size, outline, numbers, shadow and of-max controls,
    and shows a note pointing to the texts table.
- **`tools/wowstub.lua`**:
  - Added `SetAtlas`, the texture layer and sublevel, shadow offsets, and SetAlpha / GetAlpha.
  - `S.UseAtlases()` installs `C_Texture` with known atlases. It is opt-in, so probecheck's
    forever-profile expectations hold.
- **`tools/clockui.lua`** (53 checks):
  - New T142 section: the default bar, the item store and its validation, outside texts that never
    resize the frame, anchors, words, the game frame with and without atlases, the font, and the
    migration.
  - Older bar tests were pinned to a legacy look, or limited to Line and Compact where the slots
    apply.
- **`tools/clocksettings.lua`** (54 forever / 53 tbc): Bar look controls, each control writes, the
  texts table, each preset, the EllesmereUI font button, and TBC's refused game frame with its reason.
- **`tools/stylecheck.lua`**: the clock golden section was re-based (37 regions; forever 694687313,
  tbc 301186103), with a comment in the style of T131 and T139. Every other section is unchanged.
- **`tools/data/expected-counts.json`**: clockui 53/53, clocksettings 54/53.
- **`tools/data/import-forever-sv.lua`**: rebuilt with `tools/importfixture.lua`; it now carries
  `v = 2`.
- **`docs/TESTING.md`**: added §63: the default, a side-by-side with EllesmereUI, the texts table,
  frame and font, TBC's fallback, and the presets.

## Decisions where the task left a choice

- **Label off.** When the label item is off, the time item follows `CF.Slots`' existing rule for a
  label drawn nowhere:
  - a modelled time keeps its `~` and direction word;
  - with no value, the time shows the label's word in its place (FULL, OOM --), so the bar never goes
    blank.
  - Label and time may both be off, because the eui preset (mana only) needs that.
- **Item colour** is a 6-digit hex string, the player's own value. It is not a style token, so
  restylecheck does not apply.
- **The eui preset's** back alpha is 0.75, read off the mockup. It sets 260 wide, mana only, back
  111111, the live mana colour and the Soft texture fallback.
- **No dropdowns** in the texts table. Step buttons keep a table of 8 rows usable inside a scroll
  frame.
- **Stale `bars.line.text` keys** from T139 stores are left in place. They are harmless and not read.
- **Font changes:** the EllesmereUI font is cached per look build. A font change in EllesmereUI
  reaches the clock at the next look rebuild (any CLOCK_LOOK or STYLE_CHANGED), not on
  EUI_LOOKS_CHANGED alone.

## Suites

The iteration runs were clockui (53/53) and clocksettings (54 forever / 53 tbc), on both flavours.

The final `make check` passed. Its last lines:

```
  ok    textcheck                  textcheck: 9 TOCs, 124 files, 0 findings
counts
  counted 102 run(s) against 102 expected
check: 107 run(s), all passed
exit 0
```

An earlier `make check` failed euicheck (the clock reading EllesmereUI's font on every paint, so I
cached it per look), probecheck (the stub's atlases, now opt-in) and stylecheck (the golden and the
read count, see above). All three are fixed.

## Not done

- `docs/HISTORY.md` and `CLAUDE.md` (the `UI/ClockView.lua` and `UI/ClockSettings.lua` rows) were not
  edited: the agent rules reserve them for the lead. Suggested CLAUDE.md wording:
  - ClockView row, append: "T142: the Bar layout's texts are items (`text.bar.items.<kind>`: on,
    place, align, x, y, size, colour, outline), the game frame (atlas, mask, bevel; border when
    refused), the EllesmereUI font, the one-time Bar reset (`v = 2`)".
  - ClockSettings row, append: "T142: Frame / Font, the texts table, presets default / eui / below /
    pill / thin".
- CHANGELOG.md was not touched (no version bump in this task).
- In-game checks (§63) are the author's to run.
