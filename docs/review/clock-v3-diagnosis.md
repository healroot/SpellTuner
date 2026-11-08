# Clock v3 diagnosis: three in-game bugs after T142-T144

Architect, 2026-11-08. Branch `worktree-forever-talents` at 132da97 (T144 + review S1). The build
was installed on Forever at 15:18. The author's saved variables were written at 15:31:
`_forever_/WTF/Account/124250034#1/SavedVariables/SpellTuner.lua`, read only.

What the author said:
- "you broke most of the settings, they just dont apply"
- "the times shows 10s, 5s, 0s when mana was full"
- "moving line stops working"

Reproduced in the offline harness with a throwaway script. It loads the Forever TOC and puts the
author's own `db.clockLook` into the store. It then plays a fight: one priced spend, regen outrunning
the spend, mana reaching max. Last, it applies settings one at a time and compares what is drawn
before and after. Output excerpts are quoted below. The script is not committed. Its shape is the
model for the end-to-end suite in `docs/SPEC-clock-v3.md` section 4.

## 0. What the author's store holds (the key fact)

```
clockLook = { layout = "bar", v = 2, over = {
  colors.manaBar = {0, 0.55, 1, 1}          -- 008CFF: "Like my EllesmereUI"
  bar.back       = {0.067 x3, 0.75}         -- 111111 at 75 %: same preset
  bars.bar       = { show = "mana", fsr = 2, after = "empty" }
  frame.bar.w    = 260                      -- same preset
  text.bar.time  = "sec"
  text.bar.items = {
    time  = { align right, y 1, size 15, E3E3E3, outline }        -- on (no `on` stored = default true)
    mana  = { y 1, size 14, E3E3E3, outline }                      -- on, inside centre
    mp5   = { on = false, place inside, align left, y 1, size 15, CDD4D0, outline }
    label = { place inside, x 4, y 0, size 10, E3E3E3, outline }   -- on = default false
    pct   = { place inside, x -4, y 0, size 10, E3E3E3, outline }  -- on = default false
    fsr, rest, manaMax: preset fields, all off
  } } }
```

- The store is the "Like my EllesmereUI" preset (`UI/ClockSettings.lua:333-338`, items
  `EUI_ITEMS` 305-314) with the author's edits on top.
- The preset wrote `show = "mana"`, `time.on = false` and `mp5.on = false`.
- The author then turned the time back on and moved it below right. They also edited the regen row
  (place, align, size, colour), but it stayed off. They set `fsr = 2` and `after = "empty"` on the
  Bars tab, but those draw nothing under `show = "mana"`.

**Screenshot 1 is exactly this store.** It shows mana 212 centred inside, the time at the bottom
right, and no regen text. The clock did not ignore the store. The store holds things the author did
not mean to set, plus many edits that draw nothing.

## Bug 1 -- "the settings just don't apply"

**Root cause: two-thirds of the controls on the Bar layout are inert in the state the author is in,
and the pane does not say so.** A preset rewrites about 60 keys at once, including switches the
author never sees on the Bar look tab. Mechanisms, each with file:line:

1. **Edits to a text that is off are stored and never drawn.**
   - `ItemRow` (`UI/ClockSettings.lua:528-574`) keeps every control of an off row clickable.
     `RefreshItems` only dims them to alpha 0.35 (lines 591-593).
   - `CS.SetItem` writes the change (445-451).
   - `METRICS.bar` builds a spec only for `it.on` items (`UI/ClockView.lua:1384-1458`, the
     `if it and it.on` at 1446). So the edit has no effect.
   - The author's regen row (place, align, size, colour) and label / pct rows are exactly this.
2. **The preset turns off the 5SR element, and with it four Bars-tab controls and two colour
   swatches.**
   - `CS.PRESETS.eui.bars.show = "mana"` (`UI/ClockSettings.lua:335`) leads to
     `Element(bars)` = `true, nil` (`UI/ClockView.lua:1068-1080`).
   - From then on, Join, Order, 5SR strip px, After the rule, the "5SR line" colour and the
     "After 5SR" colour change nothing.
   - The Bar look tab, where the preset button is, shows no "Bars" control. That control lives on
     another tab (`TAB.bars`, 216-255), so nothing on screen says the line was switched off.
3. **Frame = game makes Border (px) and the Border colour inert.**
   - `View:SizeBack` sets `bd = 0` for `frameMode` none or game (`UI/ClockView.lua:1507`).
   - The slider is disabled (`UI/ClockSettings.lua:1876`), but the "Border" swatch stays live
     (`COLOUR_ROWS`, 279-283).
4. **Fill end draws only with the Gradient texture** (`View:Gradient`, `UI/ClockView.lua:1711`).
   The swatch is always offered.
5. **The six tone colours (Colours tab) are inert on the Bar.**
   - `PaintItems` paints every item in its own hex colour (`fs:SetTextColor(r, g, b)`,
     `UI/ClockView.lua:2170-2190`).
   - The tone only reaches a colour code for a label riding the time, or for an arrow. Forever has
     neither (`PieceText`, 2057-2071).
6. **Notes that are now false.**
   - `CS.TEXT_NOTE` (`UI/ClockSettings.lua:1390`) still says the `~` stays and the real mana waits
     for the probe. T144 removed both.
   - The slot lists still append "~ model" (`SlotItems`, 1397-1410).

Harness evidence (the author's store, one setting changed at a time, the drawn texts, points, sweep
and edge compared before and after):

```
setting mp5 size 20 (row off)              visible change: false
setting label place above (row off)        visible change: false
setting bars after green (show=mana)       visible change: false
setting bars fsr 6 (show=mana)             visible change: false
setting bars join stacked (show=mana)      visible change: false
setting 5SR line colour (show=mana)        visible change: false
setting After 5SR colour (show=mana)       visible change: false
setting Border colour (frame=game)         visible change: false
setting border 3 (frame=game)              visible change: false
setting Fill end colour (texture eui)      visible change: false
```

Not the cause, checked and ruled out:
- `CV.Set` -> `CLOCK_LOOK` -> `NewLook` -> `View:SetLook` -> `PaintFace` does rebuild the live
  clock (`UI/Clock_Forever.lua:512-534`).
- The slider callbacks fire only on a user release (`UI/Style.lua:3313-3330`), so a refresh writes
  nothing.
- The preview's `Layout(p)` is the live layout.

**Could the harness catch it?** Yes, and it did not, for two reasons:
- `tools/clocksettings.lua:736-745` asserts `OverBar("show") == "mana"` as the preset's *intended*
  result. The bug is pinned as a feature.
- No suite asks the question the author asks: "does this control, from this state, change what is
  drawn?". The suites check that a control writes its key (store level) or that a hand-made look
  draws (view level). They never check control -> store -> live frame -> a visible difference.
  `docs/SPEC-clock-v3.md` section 4.2 makes that the core test. The v3 product also removes the
  inert combinations, so that test can be total.

## Bug 2 -- "10s, 5s, 0s when mana was full"

**Root cause: three things stack.**

1. **The face has no FULL at zero.**
   - In combat, `ManaModel:Project` reaches mode `full` whenever regen outruns spend
     (`Engine/ManaModel.lua:213-216`), with `ttf = (max - mana) / -net`.
   - `Advance` clamps the mana at max (78), so once the model is full `ttf` is exactly 0. The mode
     stays `full`, and `fullnow` exists only out of combat (226-232).
   - `Face` turns that into `label FULL, value Shown(0) = 0, known "point"` (309-315).
   - The Bar's time reads **"0s" for the rest of the fight**.
   - Out of combat the same happens for the last 2.5 s before `fullnow`: `Shown` rounds any ttf
     under 2.5 to 0 (251-257). The clock is still up there, because it hides only above 95 %.
2. **The Bar's time drops its word.**
   - With the label item off (the default, `CV.ITEMS_DEFAULT.label.on = false`,
     `UI/ClockView.lua:327`), `CF.ItemPieces` gives the time only the value's words "10s"
     (`Engine/ClockFace.lua:488-505`). FULL appears only when there is no value at all.
   - T144 also stripped the `~` (`Unmarked`, 480-486).
   - So a refill countdown "10s, 5s, 0s" looks the same as an OOM countdown. Nothing tells the
     author the clock means "full in 10 s".
3. **The model lags the real pool, and now the real pool is on screen.**
   - Since T144 the mana text and the bar are the game's own (`DrawPowerText`, `DrawUnitPower`).
   - The time is still the model's. The model cannot see drinks, Innervate, potions, Clearcasting
     (free casts it still charges, `Engine/ManaPool_Forever.lua:120-134`) or cost reductions.
   - So the real pool reads full while the model still counts 10, 5, 0.
   - `ManaModel.Steady` (`Engine/ManaModel.lua:372-403`) then walks those last steps one a
     second, which makes the lag visible for longer.
   - The only re-anchor is the assume-full rule. It needs `max / base` seconds since the last
     spend, out of combat (`Engine/ManaPool_Forever.lua:163-172`): tens of seconds.

Harness evidence (the author's store, `time = "sec"`, in combat):

```
t= 30.0 mode=oom  ttf=nil mana=6779/7009: time='>10m'
t= 33.5 mode=full ttf=0   mana=7009/7009: time='0s'
10 s more at full, in combat: mode=full ttf=0:  time='0s'
```

**Could the harness catch it?** Yes, it reproduces with the shipped model and the shipped painter.
It did not, because:
- the model tests (`tools/clockcheck.lua`) check `Project` and `Face` apart;
- the paint tests (`tools/clockui.lua`) draw the hand-made `CF.SAMPLES` faces, never a face the
  model produced at full;
- the Steady tests feed hand-made faces;
- no test runs model -> face -> steady -> paint through a fight that ends full, or asserts "at
  full the clock says FULL".

Part 3 (the model's lag against the real pool) needs the client. The harness can only test the
rule that corrects it (SPEC-clock-v3 section 2.4, the quiet-pool rule).

## Bug 3 -- "moving line stops working"

**Root cause: the "Like my EllesmereUI" preset switches the 5SR element off.**
- `CS.PRESETS[2].bars.show = "mana"` (`UI/ClockSettings.lua:335`), described as "no 5SR line".
- `CS.ApplyPreset` writes it as `bars.bar.show` (381-389).
- `Element()` then gives `el = nil` (`UI/ClockView.lua:1071`), so `PaintFSR` draws nothing and
  installs no `OnUpdate` (2288-2391).
- The live store confirms `bars.bar.show = "mana"`.
- No control on the tab where the preset sits shows the switch, so to the author the line simply
  stopped.

Harness evidence (the author's store, mid-rule):

```
in fight, 5SR running (author store): el=nil manaOn=true sweepShown=false barOnUpdate=false
```

**The step mechanism itself was checked and holds in the harness:**
- `StepOff` on every `SetLook`; reinstalled by the next `PaintFSR` (`stepping` false).
- One function per view (`v.step`).
- The host is the mana bar for the sweep. It is shown whenever `manaOn`.

It is still fragile, and v3 replaces it:
- Two hosts and a `stepping` flag are kept in step by hand (2379-2390).
- A host change while `stepping` is true clears the old host and never installs the new one. Only
  `SetLook`'s `StepOff` hides that path today.
- The `OnUpdate` lives on a StatusBar that the client also animates (T143's eased `SetValue`) and
  that holds a secret value. In the 12.x client that is untested ground: the harness's `S.Tick`
  runs every frame's `OnUpdate`, shown or not, so it cannot see a client that does not.
- `View:FillBar` (preview) and `View:Message` add two more paths that stop or skip it.

**Could the harness catch it?** The preset part, yes: the same pinned-as-intended assertion
(`tools/clocksettings.lua:741`). A "the moving line is drawn mid-rule after every preset" check would
have failed. The client-only part (an `OnUpdate` on a hidden or secret-holding bar) cannot be caught
by the stub. v3 moves the line's driver to a frame of its own that holds nothing secret and is
always shown while the clock is (SPEC-clock-v3 section 2.3).

## Cross-cutting: why the suites stayed green

- **They test layers, not the path the author uses.** About 190 checks per flavour (clockui 57,
  clocksettings 55, clockcheck 44, clockfacecheck 21, clocktextcheck 13) pin store keys, resolved
  looks, metrics and hand-made faces. None runs the chain the author runs: Settings control ->
  `db` -> `CLOCK_LOOK` -> the live frame -> what is drawn, with faces the model makes.
- **Assertions encode the implementation's choices** (the preset's `show = "mana"`, the inert
  swatches counted as `#colourButtons == 6`), not the product's promises.
- **The look space is a product of about 40 independent options.** Most combinations make some
  other option inert. Testing every combination for "visibly changes" is not tractable, which is
  the strongest argument for a smaller look (SPEC-clock-v3 section 1).
