# T140: EllesmereUI's bar textures, a Centre slot, the real "Like EllesmereUI" (both lines)

The author, 2026-11-08: they set the clock by hand to look like EllesmereUI's mana bar and asked how to
make it exactly the same, then "yes, build T140".

## Measured

The author's screenshot and EllesmereUI's saved profile ("Blizz-Inspired", `EllesmereUIResourceBars`)
give EllesmereUI's mana bar:
- Texture: `general.barTexture = "pixels-dark"`. Read top to bottom, the file is 0.43, peak 1.0, 0.14,
  which matches the screenshot.
- Colour: the mana power colour `MANA = { 0, 0.55, 1 }` (008CFF), through `EllesmereUI.GetPowerColor`.
- Background 111111, height 8, no border, square ends.
- Text: the current mana, centred above, size 15.

EllesmereUI never registers its textures with LibSharedMedia, and its skin API (`S`) has no texture
getter. It does publish the catalogue its own dropdowns read:
`EllesmereUI.BuildBarTextureTables()` -> paths, names, order.

## What changed

- **Textures:** `Integrations/Media_LSM.lua` adds `ST.Media.Ellesmere()`, `FetchEllesmere(key)` and
  `EllesmereMana()`.
  - Every call is under `pcall`, and only a host global is read (apicheck rule 11).
  - Nothing is copied or shipped.
- **Texture keys:** `UI/ClockView.lua` adds `eui:<key>` (`CV.EUI_PREFIX`). Without EllesmereUI the
  bar is drawn Flat and the look says `CV.EUI_MISSING`. The Texture list shows "Name (EllesmereUI)".
- **Centre slot:** `Engine/ClockFace.lua` gives the Bar layout a Centre slot (none / Mana % / Mana /
  Regen / 5SR, default none). It is drawn by the `second` region at the bar's or text row's centre.
  `CV.BarWordsW` keeps it centred: each side is as wide as the wider of Left and Right.
- **Like EllesmereUI preset:**
  - Pixels Dark (Soft without EllesmereUI), Rectangle, border 0, height 8, the text above,
    Centre = Mana.
  - EllesmereUI's live mana colour (008CFF without it) on 111111.
  - Every other preset sets Centre back to none.

## Acceptance

- `tools/clockui.lua` 48, `tools/clocksettings.lua` 53 / 52, `make check`.
- In game: `docs/TESTING.md` §61.
