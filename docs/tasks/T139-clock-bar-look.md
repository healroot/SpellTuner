# T139: the clock's bar look -- shape, texture, colours, presets (both lines)

The author, 2026-11-08: "I want more customizable colour select for clock, and also have a texture
select, and shape select (rounded, rectangle and so on) ... I want to be able to mimic that mana bar"
(EllesmereUI's). After the mockup (`tools/.cache/clockbar`, claude.ai artifact GTGjTGVmdTnnjj4jSpFSFz):
"looking good, and I want make this what I've set on screen as default".

## Settings -> Clock -> Bar look (a new tab after Text)

- **Shape:** Rectangle, Rounded, Pill, Thin.
  - Rounded and Pill clip every bar region (fill, back, edge, the five-second-rule strip, veil, line)
    with a left and right mask pair (`Media/RoundL|R`, `PillL|R`, `CLAMPTOWHITE`).
  - Thin is a rectangle that also sets the height to 4 and moves the words above.
- **Texture:**
  - SpellTuner's own: Soft, Flat, Smooth, Gradient, Gloss, Striped, Minimal (`Media/*.tga`, built by
    `tools/buildmedia.py`).
  - The game's: Status bar, Raid bar.
  - The host's LibSharedMedia bars, shown as "name (your UI)" (`Integrations/Media_LSM.lua`; borrowed,
    never shipped). A host bar that is gone draws Flat and the look says why.
  - Forever applies every texture now (T115 kept it to Flat until the probe).
- **Text (the Bar layout's words):** inside the bar, above, below, or off. Outside, the bar's height
  is `bars.bar.height` (3-30, default `CV.BAR_HEIGHT` 6) and the frame grows to fit.
- **Border:** 0-3 physical pixels of the edge colour round each bar.
- **Six colours**, each through the game's colour picker (`ST.API.PickColour`): Fill, Fill end
  (Gradient's left end), Background, Border, 5SR line, After 5SR. Right-click resets one.
- **Presets:** Default, Like EllesmereUI, Soft pill, Thin line. A preset sets its own fields and
  resets every other look field and colour.

## The new defaults (the author's screen)

- Join: the moving line.
- The Bar layout: a 6-px pill in Soft, border 1, the words below, no panel.
- Colours: Fill 396DA7, Fill end 1D4EA6, Background 0A0A0A, Border 000000, 5SR line FFAB33,
  After 5SR 5CCB6E.
- The Bar layout's background and fill are its own under every style. A style's clock role
  (`bar`, `barFill`) still colours the other layouts.
- The author chose the Ellesmere bar texture. It exists only where EllesmereUI is installed, so the
  default is Soft, which shades like it; the Ellesmere texture is in the list if EllesmereUI registers it
  with LibSharedMedia (VERIFY).

## Acceptance

- `tools/clockui.lua` 47, `tools/clockcheck.lua` 37, `tools/clocksettings.lua` 52 / 51,
  `tools/stylecheck.lua` (clock golden re-based), `make check`.
- In game: `docs/TESTING.md` §60. Masks, `SetGradient` and the colour picker are unverified on
  either client.
