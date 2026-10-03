-- TBC's Settings rows (T119, docs/SPEC-one-ui.md 7, mockup M6): the table
-- UI/Settings.lua builds Settings -> General, Review and About from on this
-- line. It was UI/Options_General.lua -- one General page of four 205-px
-- columns in MD.optionsFrame -- and every control keeps its key, its words, its
-- range and its tooltip; only its place changed:
--
--   OOM Widget  Lock widget ("Lock in place"), Tooltip on the clock, Reset
--               position, Customise...  -> General / MANA CLOCK, with Show now
--               (MD.Widget:Preview, T93's mover seam) beside them
--               Show rest time, Show mana cooldown -> gone from here: Settings
--               -> Clock -> Text holds the same keys since T116
--   Alerts      Mute alerts, Drink reminder -> General / ALERTS
--   Model       Calibration drift alerts -> General / ALERTS; Spend half-life,
--               OOM digits below error, Count Tree of Life aura, Average in
--               Nature's Grace, Reset overheal data -> Review / MODEL
--   Misc        Show minimap button -> General / WINDOWS (the shared "Minimap
--               button", same key); the two tooltip checks -> General / SPELL
--               TOOLTIPS (the shared words, same keys); Debug Console, Verify
--               spell data, Copy profile -> General / TOOLS; Regen test (30s)
--               -> Review / MODEL
--   Fight recording -> Review / RECORDING ("Replay: next pull follows" reads
--               "Next pull follows"), with Coach a fight when it opens and
--               Snapshot ticks on the bars, new on TBC (Engine/SimModel.lua's
--               keys, registered here too; Forever's words)
--   Windows, Integrations -> General / APPEARANCE, WINDOWS, INTEGRATIONS (the
--               shared sections)
--
-- No "Show the mana clock" row: TBC's clock appears by MD.Visibility.Want, and
-- a switch would be a new setting in UI/Widget.lua (docs/DECISIONS.md "One
-- Settings"). No recording note: TBC's recorder is always loaded.
local _, MD = ...

local function Fire(name, ...)
    if MD.Fire then MD:Fire(name, ...) end
end
local function UpdateVisibility()
    if MD.UpdateVisibility then MD:UpdateVisibility() end
end

MD.SettingsLine = {
    -- the words today's About printed beside the version
    client = function() return "TBC Anniversary" end,

    clock = {
        { kind = "check", text = "Lock in place", key = "locked", mark = "clockLockCheck",
          after = UpdateVisibility,
          tips = { "Lock widget", "Uncheck to drag the OOM clock.", "It stays visible while unlocked." } },
        { kind = "check", text = "Tooltip on the clock", key = "widgetTooltip", default = true,
          after = UpdateVisibility,
          tips = { "Tooltip on the floating clock", "Hovering the clock shows the full mana breakdown,",
                   "and left-click opens the dashboard. This needs mouse input on the",
                   "widget, so it also swallows clicks in its own small rectangle.",
                   "Turn it OFF if the clock sits in the middle of the screen: it then",
                   "takes no mouse input at all, and stays draggable while unlocked.",
                   "The minimap button and the ElvUI datatexts keep their tooltips.",
                   "Same as /md tooltip." } },
        { kind = "buttons",
          { text = "Reset position", width = 112, mark = "clockReset",
            onClick = function()
                local d = MD.DEFAULTS.pos
                MD.db.pos = { d[1], d[2], d[3], d[4] }
                if MD.ApplyWidgetPosition then MD:ApplyWidgetPosition() end
                MD:Print("widget position reset.")
            end },
          { text = "Show now", width = 86, mark = "clockShowNow",
            tips = { "Show now", "The clock up for 60 s at any mana level, to see or move it." },
            onClick = function()
                if MD.Widget and MD.Widget.Preview then MD.Widget:Preview() end
            end },
          -- T102 (docs/SPEC-next.md 7.4, mockup M8g): the layout, colours and
          -- bar live in Settings -> Clock
          { text = "Customise...", width = 92, mark = "clockCustomise",
            tips = { "Customise the clock", "Settings -> Clock: the layout, the colours, the bar, with a preview." },
            onClick = function()
                if MD.SelectView then MD:SelectView("settings", "clock") end
            end } },
    },

    alerts = {
        { kind = "check", text = "Mute alerts", key = "muted",
          tips = { "Mute alerts", "Silences the advisor (Innervate / potion timing),",
                   "the rank-shift toast and the drink reminder." } },
        { kind = "check", text = "Drink reminder", key = "drinkReminder",
          tips = { "Drink reminder", "Out of combat, below 90% mana and not drinking: 'Drink.'" } },
        { kind = "check", text = "Calibration drift alerts", key = "calibAlerts", default = true,
          tips = { "Calibration drift alerts", "The model checks itself against every heal you land.",
                   "When a spell drifts more than 3% from it over 30+ events, one chat",
                   "line per session says so. /md calibrate shows the whole table." } },
    },

    tools = {
        { kind = "buttons",
          { text = "Debug Console", width = 104,
            tips = { "Debug Console", "Live log of regen, mana ticks, casts and the clock state.",
                     "Enable logging there; Copy exports it as text." },
            onClick = function() if MD.ToggleDebugConsole then MD:ToggleDebugConsole() end end },
          { text = "Verify spell data", width = 120,
            tips = { "Verify spell data", "Same as /md verify: static TBC spell table vs the live client,",
                     "plus an input snapshot. Output goes to chat and the debug log." },
            onClick = function() if MD.RunVerify then MD:RunVerify() end end },
          { text = "Copy profile", width = 98,
            tips = { "Copy profile", "Same as /md profile: every model input, cost, clock state and",
                     "setting in one copyable box. Paste this into a bug report." },
            onClick = function() if MD.RunProfile then MD:RunProfile() end end } },
    },

    -- Simulation (v0.7). Only the settings a player would actually reach for:
    -- the gate thresholds and the search's internals stay where
    -- Engine/SimModel.lua declares them (MD:RegisterDefaults, T64) with their
    -- provenance comments, because a slider invites tuning and these numbers
    -- are supposed to be argued with, not nudged. The sliders read MD:Setting,
    -- so a fresh database shows the registered default.
    recording = {
        { kind = "check", text = "Record fights", key = "recordFights", default = true,
          tips = { "Keep the full event stream of the last 8 interesting pulls",
                   "so they can be replayed and reviewed (/md -> Review).",
                   "Fight summaries keep working either way." } },
        -- v0.9: runs. Starting one is deliberate (/md run start, or the Review
        -- tab's button); this only says whether that is allowed at all.
        { kind = "check", text = "Allow run recording", key = "recordRuns", default = true,
          tips = { "A whole dungeon as one recording: every pull and the gaps",
                   "between them (drinking, deaths, the clock).",
                   "Runs are always started by hand - /md run start." } },
        { kind = "check", text = "Next pull follows", key = "replayNextPull", default = true,
          tips = { "In a run, playing a pull to the end opens the next one.",
                   "Off: it stops at each pull's end." } },
        { kind = "check", text = "Let Coach change ranks", key = "simAllowRebinds", default = false,
          tips = { "Off: the card suggests thresholds for the ranks you already cast.",
                   "On: it may also suggest binding a different rank.",
                   "Off by default - a card that silently rebinds everything is",
                   "somebody else's strategy, not this fight's." } },
        { kind = "check", text = "Coach a fight when it opens", key = "replayAutoCoach", default = true,
          tips = { "Coach a fight when it opens", "Opening a replay with no plan validates and coaches it.",
                   "Off: open it, then Coach from Review." } },
        { kind = "check", text = "Snapshot ticks on the bars", key = "replayTicks", default = true,
          tips = { "Snapshot ticks on the bars", "The recorder's real health every 5 s, drawn over the",
                   "engine's reconstruction on the left bars." } },
        { kind = "slider", text = "Full health is above (%)", key = "simFullHp", min = 70, max = 99, step = 1,
          scale = 100, percent = true, mark = "fullHpSlider",
          tips = { "A cast on a target at or above this counts as healing nobody.",
                   "0.85 came from the first dungeon log, not from a rulebook." } },
        -- T73 (P29, review U24): since v0.10.3 a recorded fight measures its
        -- own line (the biggest hit, db.simDangerHits) and since T20 a plan
        -- decides on the biggest hit so far; this flat line is what a BUILT
        -- fight (Simulate) is scored and planned on, and a recorded target's
        -- fallback before any hit is known.
        { kind = "slider", text = "Danger line for built fights (%)", key = "simFloor", min = 10, max = 60,
          step = 1, scale = 100, percent = true, mark = "floorSlider",
          tips = { "Fights built in Simulate score seconds a target spends below",
                   "this first, ahead of mana. A recorded fight measures its own line:",
                   "the biggest hit each target took." } },
    },

    model = {
        { kind = "slider", text = "Spend half-life (s)", key = "halfLife", min = 5, max = 60, step = 1,
          default = 15,
          tips = { "Spend half-life", "How fast the spend estimator forgets old casts.",
                   "Shorter reacts faster, longer is steadier. Default 15s." } },
        -- Stored as a fraction (0.3-1.5), shown as a percentage: "print the OOM
        -- digits while the projection's error is under N% of its own value".
        { kind = "slider", text = "OOM digits below error", key = "oomConfidence", min = 30, max = 150, step = 5,
          scale = 100, percent = true, default = 0.7,
          tips = { "How sure the clock must be to print digits",
                   "sigma/net of the projection. Below this the clock shows 'OOM 2:00';",
                   "above it, 'OOM >2:00' (no sooner than). 70% comes from one easy dungeon:",
                   "the hard pull sat at 34-66%, the quiet ones at a median 73%. Retune on raid logs." } },
        { kind = "check", text = "Count Tree of Life aura", key = "treeAura", default = true,
          after = function() Fire("FORM_CHANGED", MD.InTreeForm and MD:InTreeForm()) end,
          tips = { "Tree of Life aura in heal values", "Party members under your Tree of Life aura receive",
                   "25% of your Spirit as extra healing. It is not part of the",
                   "+healing stat, so the dashboard adds it while you are in form." } },
        { kind = "check", text = "Average in Nature's Grace", key = "naturesGrace", default = true,
          after = function() Fire("TALENTS_CHANGED") end,
          tips = { "Nature's Grace in cast times", "A spell crit takes 0.5s off your next cast, so chain-casting",
                   "Healing Touch or Regrowth averages out faster than the tooltip says.",
                   "Marked with a grey * in the dashboard's Cast column." } },
        { kind = "buttons",
          { text = "Reset overheal data", width = 140, color = "red-hover",
            tips = { "Reset overheal data", "The dashboard's 'Effective' numbers come from your own combat log,",
                     "per character. Clear it after a gear jump or a change of content -",
                     "otherwise it forgets on its own over about 150 healing events." },
            onClick = function() if MD.Overheal then MD.Overheal:Reset() end end },
          { text = "Regen test (30s)", width = 120,
            tips = { "Regen test", "Stand idle at partial mana, no drink, no casting, for 30s.",
                     "Compares observed mana gain with GetManaRegen and tells whether",
                     "Dreamstate is included in the API value." },
            onClick = function() if MD.RunRegenTest then MD:RunRegenTest(30) end end } },
    },

    -- the old About tab's last pane, its words unchanged but where the Debug
    -- Console now is
    aboutNote = {
        title = "BEFORE TRUSTING THE NUMBERS",
        text = "1. /md verify - spell costs and cast times against your client.  "
            .. "2. /md regentest - idle 30s: is Dreamstate in GetManaRegen?  "
            .. "3. /md fsrtest - cast once, watch the tick sizes.  "
            .. "Copy everything from the Debug Console (General > Tools).",
    },
}
