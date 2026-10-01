# Critique of SPEC-next.md and mockups-next.html (read against a6a3bcd)

The spec answers all four asks (A: section 4, B: section 5, C: section 6, D: section 7). Its 21 decisions each come with a recommendation. The seams (S1-S4) come first, and each one is byte-identical before any behaviour change. Every wave has at most 6 tasks, and I found no file that two tasks in the same wave both own. The problems below are listed most important first.

1. **Cooldowns are keyed by spell id, but they belong to a family.** `SM.Ready(S, spellID, t)` reads `S.cd[spellID]` (`Engine/SimModel.lua:1203`), and `SimModel.lua:617` writes it the same way. T90 changes this to "entry.cooldown or SPELL_CD[id]", and T101 builds on that. Holy Shock R1-R4 and Riptide's ranks share one cooldown. As written, a plan could cast R4 and then R3 at once. The spec should say: the cooldown is kept per family, and a test checks that a cooldown on one rank blocks the other ranks. There is also a gap in T96's file list. `Engine/ReplayTrace.lua:94,321` reads `SM.SPELL_CD` for the Swiftmend-ready dot, and no task owns that file. `UI/ReplayWindow.lua:812` hard-codes `SPELL_CD[SWIFTMEND] or 15`.

2. **The engine tables cannot come from the active profile.** `MD.Profiles.Select` runs at CORE_LOGIN. `SimModel.lua:93` captures `local HOT_INDEX = SM.HOT_INDEX` when the file loads. `tools/import.lua` replays recordings that may come from another character or class. So the engine's tables must be derived per kit or scenario (`rec.kit`, the recording's class), never from `MD.Profile`. This covers `SM.HOT_INDEX`, `SV.FAMILIES`, `SPELL_CD` and the HoT rows (T96, T101). Two things need fixing in the spec. First, T89's "derived from the profile at load" is only well defined if it uses the druid profile explicitly. Second, the spec should state that the engine reads the kit's profile, not the logged-in player's.

3. **The probe is Forever-only.** `Client/Probe.lua` is listed only in `SpellTuner_Mainline.toc` and `SpellTuner.toc`. Several parts of the spec assume it runs on TBC too:
   - T87 says "== art ... on both clients".
   - T103 and T108 need "`== art` from both clients".
   - In-game check 1 says `/md probe`, which does not exist.

   Some task must own putting the probe on the TBC TOC. That includes `probecheck` under tbc with no `C_Secrets` and the integrator's TOC line. The alternative is a TBC-only art check. Either way, decision 1's Classic gate and Modern's atlas gate depend on it.

4. **The new slash verbs collide with existing ones.** `/st clock` and `/st ui` are already registered in `Core_Forever.lua:279,309`. `MD:AddCommand` replaces a row with the same name. If T94 registers `ui style` from `UI/Styles.lua`, it either overwrites `/st ui reset` or is overwritten, depending on load order, and T94 does not own `Core_Forever.lua`. TBC has neither verb. Adding `/md ui style` in T94 (N2) therefore changes the `slashcheck/tbc` golden, but that golden is only re-based in T102 (N4), so `make check` turns red at the end of N2. Two fixes are needed: a subcommand seam (say `MD:AddSubcommand(verb, sub, fn)`) in its own early task, and the slashcheck re-base moved to the task that adds the verb.

5. **The spec has no risks section, and several risks named in the research were dropped.**
   - EllesmereUI changes along with the beta. Nothing records the version it was tested against (9.3.4) or warns when that changes. Nothing checks `S.apiVersion == 2` before using the getters. `/st dump` does not print the EUI version beside the integration.
   - The unlock-mode API is not in a developer guide. It also silently drops fields outside its whitelist (`R-ellesmere` 5).
   - BlizzardSkin could paint SpellTuner frames, so two painters would fight over them (`R-styles` 9).
   - Pre-blended alpha is slightly wrong over a hovered row (`R-styles` 9).
   - The outset art edge versus pixel snapping is mentioned only as a painter detail.
   - On textures missing from one client, the spec is good (per-role fallback, re-running `== art` per build).
   - On class data verification, the spec is good (VERIFY, WCL fits). It does not name some unknowns: the jump targets and range of Chain Heal and PoH, Renew / Riptide / Wild Growth tick periods (named only as in-game checks), and Light's Vigil removing Holy Shock's cooldown.
   - Forever auras: T105 relies on `ShouldAurasBeSecret = false` from build 70009 (`R-classes` 113), but T87 does not re-probe it.

   Add a "Risks and what each costs" section.

6. **The face contract is missing the crit arrow.** `Engine/TTO.lua:370` renders `OOM 15s vv` in the crit band. The face's `arrow` enum is `"v"|"^"|"="|nil`. T88's goldens would catch the omission, but the contract in 2.4 is wrong, and so is decision 16's "tones" text. The mockup does show `vv`. Also state that `nodata` renders `FULL --`.

7. **Decisions are gated on the wrong wave.** T90 (N1) implements decision 10, which changes the author's druid coach. N1 is marked as needing no answers, while N2 waits on decision 10. Move decision 10 into N1's gate, or move T90 to N2.

8. **Group and bounce heals in the solver need stated assumptions.** No positions are recorded, so the following must be explicit:
   - who Chain Heal jumps to and in what order (for example, "the most injured tracked member now", which keeps the plan causal);
   - who is "in range" for PoH and Holy Nova;
   - that both are optimistic upper bounds, marked VERIFY, with the coach card saying so.

   Gate 8 is the only in-game check of this.

9. **The Innervate parse shape is missing.** Innervate's text is "Increases the target's Mana regeneration by 400% and allows 100% ... while casting". There is no "N mana every P sec" in it. T91's parse list covers only the "restores N mana every P sec" shape, yet T105 says Innervate's rate comes "from the spell's own text". Add a percent-of-regen shape to T91. Also say how T105 handles an Innervate cast on the player by another druid (seen as an aura) versus a self-cast.

10. **T99's gate list is incomplete.** Section 1 says ~30 `isDruid` gates in 15 files, but T99 lists 11 files. It leaves out `Core_TBC.lua:99`, `Engine/RankMath.lua:555`, `Spells/Families_TBC.lua:41` and `Data/SpellData.lua:193`. The spec should say which of these stay druid by design. Also, on Forever, `Can("coach")` is meant to "ask the live kit", but the kit lives in the LoadOnDemand Replay module while `Spells/Profiles.lua` is in the main TOC. It needs an `MD:Provide` hook and a defined answer for when the module is off.

11. **Layering.** T88 makes `Engine/ManaModel.lua` (pure, used offline) and `Engine/TTO.lua` wrappers over `UI/ClockFace.lua`. The pure face and the `LineString` formatter belong in `Engine/` (for example `Engine/ClockFace.lua`), and only the renderer belongs in `UI/`. Otherwise the offline tools and the Replay module depend on a UI file.

12. **Missing `Needs` entries and test-count gaps.**
    - T95 binds `MD.API.BaseCooldown` "VERIFY by T87" but lists only T91 under Needs. Add "T87's Forever report", or state that the tooltip right-text fallback is the default until that report arrives.
    - New `MD:RegisterDefaults` keys move `defaultscheck` counts, and no task lists `defaultscheck`. The keys are `db.ui.style`, `db.clockLook`, `db.feeds` and `db.eui`.
    - T92 makes the harness load `Integrations/` for every TBC suite. Name the goldens that must stay unchanged.

13. **Ownership gaps.** T104 owns "the clock role per style" but owns only `UI/ClockFace.lua`. Each style's `clock` role lives in `UI/Style_*.lua`, which T100, T103 and T108 own. Either say those roles are defined there, or give T104 the files.

14. **Mockup and spec disagree in a few places.**
    - In M7c, the tooltip shows `Casts to OOM 6 full, ~5 now` while M7a's pool is 364/364. The current rule (T37) shows `~N now` only below max.
    - Light's Vigil appears as "684-724 costing 1340" in spec 1 and 4.1 (R3) but as "325-343 costing 730" in mockup C4 (R1). Name the rank in both.
    - The mockups otherwise match the spec, including the decision index, the five layouts, the brokers, the mover and the class panels.

15. **Wave size against the author's three-agent rule.** Decision 21 says "two batches of three" but does not say which tasks go together. Name the batches per wave, putting tasks with shared upstream dependencies in the same batch (for example N1: T88+T89+T90, then T86+T87+T91).
