-- tools/run.sh tools/replayforever.lua
--
-- T16a (docs/tasks/T16a-replay-window.md): the replay window plays a Forever
-- (v3) recording -- the window's three commands (/st replay, /st coach,
-- /st validate), the actual column against T13d's health reconstruction
-- (Modules/SpellTuner_Replay/Scenario_Forever.lua's SM.RecordedHp, T16a),
-- the ticks it draws, the reconstructed/estimated line, the suggested
-- column once the search finishes, seeking, ASCII/no-bare-pipe on every
-- painted or printed string, and the in-combat refusal. Forever only, on
-- two tools/foreverfixture.lua streams.
HARNESS_FLAVOUR = "forever"

local here = arg[0]:match("^(.*)/[^/]+$")

local ok, fails = 0, {}
local function check(name, cond, detail)
    if cond then ok = ok + 1 else fails[#fails + 1] = name .. (detail and (" - " .. detail) or "") end
    print(string.format("%-95s %s%s", name, cond and "ok" or "FAIL", detail and (" - " .. detail) or ""))
end

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua")
arg[0] = a0

local S = _G.STUB
-- T72 (the review of P28): the stub's opt-in geometry for the whole suite, so
-- the band's and the column titles' anchors are stored from the window's
-- first Build on and measured by the text metric (section T72 below)
S.Geometry(true)
S.crit[4] = 0 -- zero Nature crit: the own-heal amounts the fixture records are the engine's own exact figures

local function CapturedChat(body)
    local lines = {}
    local frame = _G.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) lines[#lines + 1] = m end
    body()
    frame.AddMessage = orig
    return lines
end

--------------------------------------------------------------------------------
-- 1: the replay commands exist only with the Replay module on
--------------------------------------------------------------------------------
-- ToggleReplay (UI/ReplayWindow.lua) is nil until the module loads; the
-- fallback dispatch must not raise on "/st replay 1" before that either.
local beforeIsNil = (MD.ToggleReplay == nil)
CapturedChat(function() SlashCmdList.SPELLTUNER("replay 1") end) -- would have raised, unguarded, if a command existed early

MD:SetModule("SpellTuner_Replay", true) -- loads Recorder (a dependency), Kit/Scenario/Gates, the engine chain, the window and this module's own commands

check("the replay commands exist only with the Replay module on",
    beforeIsNil and type(MD.ToggleReplay) == "function" and MD.SimPlanner ~= nil,
    "beforeIsNil=" .. tostring(beforeIsNil) .. " afterToggle=" .. tostring(MD.ToggleReplay))

local buildFixture = dofile(here .. "/foreverfixture.lua")
local SM, SP = MD.SimModel, MD.SimPlanner
local kit = MD.RankMath:SpellKit()

-- Recording 1 ("good"): the default fixture, own-heal amounts placed at the
-- engine's own exact figures (crit forced to 0), its own meter reading.
local recGood = buildFixture()
recGood.id = 2000000000
-- Recording 2 ("bad"): no damage meter reading at all -- fails foreign
-- healing / model calibrated / heals attributed outright (Gates_Forever.lua).
local recBad = buildFixture({ meterOverridden = true })
recBad.id = 1000000000
MD.cdb.recordings = { recGood, recBad }

--------------------------------------------------------------------------------
-- 2: /st replay opens a v3 recording with one row per tracked target
--------------------------------------------------------------------------------
SlashCmdList.SPELLTUNER("replay 1")
local W = MD.Replay._state()
check("/st replay opens a v3 recording with one row per tracked target",
    W.frame and W.frame:IsShown() and #W.rows == 2, tostring(W.frame and W.frame:IsShown()) .. " " .. tostring(#W.rows))

--------------------------------------------------------------------------------
-- 3: the actual column plays to the end and its bars follow the
--    reconstructed health
--------------------------------------------------------------------------------
local recon = SM.RecordedHp(recGood)
local lastIdx = #recon.hp[2]
local wantFrac = recon.max[2][lastIdx] > 0 and (recon.hp[2][lastIdx] / recon.max[2][lastIdx]) or 0

MD.Replay._setPlaying(true)
local frames = 0
while MD.Replay._state().playing and frames < 4000 do S.Tick(0.1); frames = frames + 1 end
local tankFrac = W.left.frames[2].bar:GetValue()
check("the actual column plays to the end and its bars follow the reconstructed health",
    not MD.Replay._state().playing and math.abs(tankFrac - wantFrac) <= 0.02,
    string.format("played=%s bar=%.3f recon=%.3f", tostring(not MD.Replay._state().playing), tankFrac, wantFrac))

--------------------------------------------------------------------------------
-- 4: the reconstructed health is drawn as the left column's ticks
--------------------------------------------------------------------------------
local ticks = W.rp.ticks
local tickCol = ticks and ticks.hp[2]
local wantTick = recon.hp[2][lastIdx] / recon.max[2][lastIdx]
check("the reconstructed health is drawn as the left column's ticks",
    type(tickCol) == "table" and #tickCol == #recon.t and math.abs(tickCol[lastIdx] - wantTick) < 1e-6,
    string.format("tickCol=%s", tostring(tickCol and tickCol[lastIdx])))

--------------------------------------------------------------------------------
-- R5 (review 2026-09-29): on a v3 stream no health was ever read (UnitHealth
-- is secret), so a tick's hover and the ticks checkbox call it reconstructed
-- -- never "recorded", "real HP" or "the truth mark".
--------------------------------------------------------------------------------
do
    local texts = {}
    local hit = W.left.frames[2] and W.left.frames[2].tickHit
    GameTooltip.lines = nil
    local enter = hit and W.left.frames[2].tickInfo and hit:GetScript("OnEnter")
    if enter then enter(hit) end
    for _, line in ipairs(GameTooltip.lines or {}) do
        texts[#texts + 1] = tostring(line[1]) .. " " .. tostring(line[2])
    end
    local leave = hit and hit:GetScript("OnLeave")
    if leave then leave(hit) end
    local cb = W.frame and W.frame.ticksCB
    for _, t in ipairs(cb and cb.tooltips or {}) do texts[#texts + 1] = tostring(t) end
    local all = table.concat(texts, " / ")
    local claimsReal = all:find("truth mark", 1, true) or all:find("real HP", 1, true)
        or all:find("Recorded health", 1, true)
    check("R5: a v3 tick's hover and the ticks checkbox say reconstructed, not recorded",
        enter ~= nil and #texts > 0 and not claimsReal and all:find("econstructed", 1, true) ~= nil,
        all)
end

--------------------------------------------------------------------------------
-- 5: the window says the health is reconstructed and a party max is
--    estimated (the tank's is secret in the fixture)
--------------------------------------------------------------------------------
-- T72 (P28, mockup M3): under the theme the caveat is one word in the status
-- band, and the rest -- the estimated max included -- is that word's hover.
local reconText = W.reconFS and W.reconFS:GetText() or ""
local reconAll = reconText .. " " .. table.concat(W.reconTip or {}, " ")
check("the window says the health is reconstructed and a party max is estimated",
    reconText:find("reconstructed", 1, true) ~= nil and reconAll:find("estimated", 1, true) ~= nil,
    reconAll)

--------------------------------------------------------------------------------
-- 6: the suggested column fills in when the coach's search finishes
--------------------------------------------------------------------------------
assert(W.right.state == nil, "expected no suggested column before coaching")
SlashCmdList.SPELLTUNER("coach 1 force")
local cframes = 0
while MD.coachSearch and cframes < 20000 do S.Tick(0.016); cframes = cframes + 1 end
assert(MD.coachSearch == nil, "coach search never finished (" .. cframes .. " frames)")
SlashCmdList.SPELLTUNER("replay 1")
W = MD.Replay._state()
check("the suggested column fills in when the coach's search finishes",
    W.right ~= nil and W.right.state ~= nil and W.rp.right ~= nil)

--------------------------------------------------------------------------------
-- 7: seeking gives the same picture as playing to that moment
--------------------------------------------------------------------------------
local dur = W.left.state.dur
local seekT = math.max(0, dur - 4)
MD.Replay._seek(seekT)
local seekFrac = W.left.frames[2].bar:GetValue()
SlashCmdList.SPELLTUNER("replay 1")
W = MD.Replay._state()
MD.Replay._setPlaying(true)
local pframes = 0
while MD.Replay._state().playing and W.left.state.t < seekT - 1e-6 and pframes < 4000 do
    S.Tick(0.1); pframes = pframes + 1
end
MD.Replay._setPlaying(false)
local playedFrac = W.left.frames[2].bar:GetValue()
check("seeking gives the same picture as playing to that moment",
    math.abs(seekFrac - playedFrac) < 0.02,
    string.format("seek=%.3f played=%.3f", seekFrac, playedFrac))

--------------------------------------------------------------------------------
-- 8: /st validate prints the Forever gates and /st coach refuses a failing
--    fight unless forced
--------------------------------------------------------------------------------
local vlines = CapturedChat(function() SlashCmdList.SPELLTUNER("validate 2") end)
local sawVerdict, sawGate = false, false
for _, l in ipairs(vlines) do
    if l:find("verdict:", 1, true) then sawVerdict = true end
    if l:find("foreign healing", 1, true) or l:find("model calibrated", 1, true) then sawGate = true end
end
local clines = CapturedChat(function() SlashCmdList.SPELLTUNER("coach 2") end)
local refused = false
for _, l in ipairs(clines) do
    if l:find("does not replay", 1, true) or l:find("nothing to suggest", 1, true) then refused = true end
end
check("/st validate prints the Forever gates and /st coach refuses a failing fight unless forced",
    sawVerdict and sawGate and refused,
    "validate: " .. table.concat(vlines, " / ") .. "   coach: " .. table.concat(clines, " / "))

--------------------------------------------------------------------------------
-- 9: every string the window paints is ASCII with no bare pipe -- a fixture
--    target named with a non-ASCII byte and a "|" (T14 review)
--------------------------------------------------------------------------------
local recBadName = buildFixture()
recBadName.id = 3000000000
recBadName.roster[2].name = "Tank\195\169|boss" -- an EU-style byte plus a bare pipe
MD.cdb.recordings = { recBadName, recGood, recBad }
SlashCmdList.SPELLTUNER("replay 1")
W = MD.Replay._state()
MD.Replay._setPlaying(true)
local aframes = 0
while MD.Replay._state().playing and aframes < 4000 do S.Tick(0.1); aframes = aframes + 1 end

local function Pipes(s)
    -- a color code, a reset, and Esc's own "||" (a literal pipe, doubled so
    -- the client renders one rather than eating what follows) are all safe;
    -- anything left over is a BARE pipe.
    local stripped = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("||", "")
    return stripped:find("|", 1, true) ~= nil
end
local function NonAscii(s)
    return s:find("[^ -~]") ~= nil
end
-- T16c: a name the client gave paints with its own bytes -- only its "|" is
-- doubled. So the fixture's name is expected to survive intact (pipe
-- doubled) wherever it is painted; everything ELSE this window composes
-- itself must still be plain ASCII once that one known name is removed.
local NAME_PAINTED = "Tank\195\169||boss"
local function StripPlain(s, sub)
    local out, i = {}, 1
    while true do
        local a, b = s:find(sub, i, true)
        if not a then out[#out + 1] = s:sub(i); break end
        out[#out + 1] = s:sub(i, a - 1)
        i = b + 1
    end
    return table.concat(out)
end
local bad, sawName = {}, false
local function Scan(label, s)
    if type(s) ~= "string" then return end
    if Pipes(s) then bad[#bad + 1] = label .. " has a bare pipe: " .. s end
    if s:find(NAME_PAINTED, 1, true) then sawName = true end
    if NonAscii(StripPlain(s, NAME_PAINTED)) then bad[#bad + 1] = label .. " is not ASCII: " .. s end
end
for _, col in ipairs({ W.left, W.right }) do
    if col then
        for ti, f in pairs(col.frames) do
            Scan("name " .. tostring(ti), f.name:GetText())
            Scan("cast " .. tostring(ti), f.cast:GetText())
            Scan("pct " .. tostring(ti), f.pct:GetText())
        end
        if col.strip then
            Scan("score", col.strip.score:GetText())
            Scan("castbar", col.strip.castFS:GetText())
        end
    end
end
Scan("header", W.headerFS:GetText())
Scan("recon", W.reconFS and W.reconFS:GetText())
Scan("hint", W.hint and W.hint:GetText())
Scan("band", W.frame and W.frame.band and W.frame.band.verdict:GetText()) -- T72
for _, l in ipairs(vlines) do Scan("validate line", l) end
for _, l in ipairs(clines) do Scan("coach line", l) end
local detail9 = bad[1]
if not detail9 and not sawName then detail9 = "the fixture name never painted with its own bytes" end
check("every string the window paints is ASCII with no bare pipe", #bad == 0 and sawName, detail9)

--------------------------------------------------------------------------------
-- T43 (docs/SPEC-forever-ui.md 4.1, 4.4): under the Forever theme the
-- window's own text takes UI.TEXT.accent where it was Blizzard gold. The
-- header's "#n" is checked on a single fight; the run strip on a run's pull
-- (runs are not recorded on Forever yet, so the address is answered here
-- for the one call -- the strip paints whatever run it is handed).
--------------------------------------------------------------------------------
local ACCENT = MD.UI.TEXT and MD.UI.TEXT.accent and MD.UI.TEXT.accent.hex or "(no UI.TEXT)"
local function Gold(s)
    s = (s or ""):lower()
    return s:find("ffcc00", 1, true) ~= nil or s:find("ffd100", 1, true) ~= nil
end
do
    SlashCmdList.SPELLTUNER("replay 2")
    local h = MD.Replay._state().headerFS:GetText() or ""
    check("T43: the header's #n takes the accent, not gold",
        not Gold(h) and h:find(ACCENT .. "#2", 1, true) ~= nil, h)
end
do
    local origGet = MD.GetRecording
    local run = { name = "Underbog", stats = { wall = 120, pulls = 1, drinks = 1, deaths = 0 },
                  pulls = { recGood }, ev = {} }
    MD.GetRecording = function(self, spec)
        if tostring(spec) == "1:1" then return recGood, "1:1", run, 1 end
        return origGet(self, spec)
    end
    local okOpen, err = pcall(SlashCmdList.SPELLTUNER, "replay 1:1")
    MD.GetRecording = origGet
    local strip = MD.Replay._runStrip()
    local label = strip and strip.label or ""
    local h = MD.Replay._state().headerFS:GetText() or ""
    check("T43: the run strip's name takes the accent, not gold",
        okOpen and strip and strip.shown and not Gold(label) and not Gold(h)
        and label:find(ACCENT .. "Underbog", 1, true) ~= nil,
        tostring(err or "") .. " label=" .. label .. " header=" .. h)
    SlashCmdList.SPELLTUNER("replay 1") -- back to a single fight: the strip gone
end
do
    -- MD.Tip is the replay's and Review's hover renderer: its one gold colour,
    -- the suggested rank's note, reads the accent. T76 (P32, review A21): the
    -- RankMath-bound builders (MD.Tip:Row among them) are UI/Tip_TBC.lua's, on
    -- the TBC TOC only, so on Forever there is no Row to call; the colour Row
    -- painted is the "tipGold" token, read here as it is on Forever.
    local r, g, b = MD.UI.RGB("tipGold")
    local A = MD.UI.TEXT and MD.UI.TEXT.accent
    check("T43: MD.Tip's suggested-rank colour is the accent, not gold",
        MD.Tip ~= nil and MD.Tip.Row == nil and A ~= nil and r == A[1] and g == A[2] and b == A[3]
        and not (r == 1 and g == 0.82 and b == 0),
        string.format("row=%s %.3f %.3f %.3f", tostring(MD.Tip and MD.Tip.Row), r, g, b))
end

--------------------------------------------------------------------------------
-- T34 (docs/SPEC-forever-ui.md 6.2, 6.3): on Forever the window is the manager's
-- takeover -- registered as "replay", on the ESC stack rather than named in
-- UISpecialFrames, with a "< SpellTuner" back button that a replay opened
-- from chat (the main window hidden) does not show. tools/wincheck.lua
-- section 12 holds the placement and the ways back.
--------------------------------------------------------------------------------
do
    SlashCmdList.SPELLTUNER("replay 1")
    local f = MD.Replay._state().frame
    local special = false
    for _, n in ipairs(UISpecialFrames) do if n == "SpellTunerReplayWindow" then special = true end end
    local w = MD.Win and MD.Win.windows and MD.Win.windows.replay
    local back = f and f.header and f.header.backBtn
    check("T34: the replay is the manager's takeover, on the ESC stack; from chat no back button",
        w ~= nil and w.frame == f and w.role == "takeover" and not special and back ~= nil
        and back.text == "< SpellTuner" and not back:IsShown() and f:IsShown()
        and MD.Win.takeover ~= nil and MD.Win.takeover.kind == "replay" and MD.Win.takeover.path == nil,
        "registered=" .. tostring(w ~= nil) .. " special=" .. tostring(special)
        .. " back=" .. tostring(back and back:IsShown()))
end

--------------------------------------------------------------------------------
-- T72 (P28, review U21, U23, U27; docs/mockups/refactor-ux.html M3): the
-- replay while coaching. Both columns are laid out the moment the auto-coach
-- starts, the right one dimmed and titled with the search's progress, and the
-- width never changes for that fight. A status band under the header carries
-- the verdict in good / bad and a Coach anyway button where a slash command
-- was quoted. The keyboard: Space plays, Left / Right seek 5 s, every other
-- key goes on to the game -- only while the pointer is over the window.
--------------------------------------------------------------------------------
local TWO_COLS = 2 * 460 + 3 * 16 -- ACTUAL and SUGGESTED side by side: 968
local GOOD, BAD = MD.UI.TEXT.good.hex, MD.UI.TEXT.bad.hex
local function FinishSearch()
    local n = 0
    while MD.coachSearch and n < 20000 do S.Tick(0.016); n = n + 1 end
    return MD.coachSearch == nil
end
local function BandVerdict(st)
    local band = st.frame and st.frame.band
    return band and band.verdict and band.verdict:GetText() or ""
end

do
    -- a fight that replays (the gates forced open, as tools/replayui.lua does)
    -- and has no plan: opening it starts the auto-coach
    local realV = SM.Validate
    function SM:Validate(...)
        local v = realV(self, ...)
        if v then v.ok = true end
        return v
    end
    local recNew = buildFixture()
    recNew.id = 3100000000
    MD.cdb.recordings = { recNew, recGood, recBad }
    SP.plans[recNew.id] = nil
    SlashCmdList.SPELLTUNER("replay 1")
    local st = MD.Replay._state()
    local wOpen = st.frame:GetWidth()
    local title = st.right and st.right.title:GetText() or ""
    local rf = st.right and st.right.frames[2]
    check("T72: the auto-coach lays out both columns at open, the right one dimmed and titled",
        MD.replayCoaching == recNew.id and wOpen == TWO_COLS and st.right.title:IsShown()
        and title:find("coaching...", 1, true) ~= nil and title:find("plans", 1, true) ~= nil
        and rf ~= nil and rf:IsShown() and st.right.dimmed == true,
        string.format("coaching=%s width=%s title=%s dimmed=%s", tostring(MD.replayCoaching),
            tostring(wOpen), title, tostring(st.right and st.right.dimmed)))
    local v = BandVerdict(st)
    check("T72: the band's verdict reads replays, in good", v:find(GOOD .. "replays", 1, true) ~= nil, v)

    local done = FinishSearch()
    st = MD.Replay._state()
    local title2 = st.right.title:GetText() or ""
    check("T72: the plan fills the right column in place: same width, the dimming lifted",
        done and st.frame:GetWidth() == wOpen and st.right.state ~= nil and st.right.dimmed ~= true
        and title2:find("coaching", 1, true) == nil,
        string.format("done=%s width=%s title=%s", tostring(done), tostring(st.frame:GetWidth()), title2))
    SM.Validate = realV
end

-- The band and the column titles measured (the review of P28): the stub's
-- geometry (switched on at the top) and its text metric (6 px a character at size 12), the font
-- strings given the font objects their templates name (the stub's
-- CreateFontString drops the template), and a resolver for the horizontal
-- points the window sets, in the window's own x. A font string's box is the
-- width it was given, else its text's.
local function Fonted(st)
    local U = MD.UI
    st.headerFS:SetFontObject(U.fontObjects[U.FONT])
    st.band.verdict:SetFontObject(U.fontObjects[U.FONT])
    st.band.word:SetFontObject(U.fontObjects[U.FONT_SMALL])
    st.right.title:SetFontObject(U.fontObjects[U.FONT_TITLE])
end
local function HSide(p) return p:find("LEFT") and "LEFT" or (p:find("RIGHT") and "RIGHT") or "CENTER" end
local Span
local function Edge(win, r, side)
    local l, rt = Span(win, r)
    if side == "LEFT" then return l elseif side == "RIGHT" then return rt end
    return (l + rt) / 2
end
function Span(win, r)
    if r == win then return 0, win:GetWidth() end
    local l, rt
    for _, pt in ipairs(r.points or {}) do
        local p, rel, rp, x = pt[1], pt[2] or r.parentFrame, pt[3] or pt[1], pt[4] or 0
        local at = Edge(win, rel, HSide(rp)) + x
        if HSide(p) == "LEFT" then l = at elseif HSide(p) == "RIGHT" then rt = at end
    end
    local w = rawget(r, "w")
    if not w then w = (r.kind == "FontString") and r:GetStringWidth() or r:GetWidth() end
    if l and not rt then rt = l + w elseif rt and not l then l = rt - w end
    return l or 0, rt or 0
end
-- where the fight's text ends (the reconstruction word included) and where
-- the verdict begins, in the band
local function BandEdges(st)
    local f, band = st.frame, st.band
    local _, fightR = Span(f, st.headerFS)
    if band.word:IsShown() then _, fightR = Span(f, band.word) end
    local vL, vR = Span(f, band.verdict)
    return fightR, vL, vR
end

do
    -- one column (no Coach anyway: the coach is a druid's) and a long fight
    -- name: the fight is cut short of the verdict rather than drawn under it
    Fonted(MD.Replay._state())
    -- T99 (docs/SPEC-next.md 4.4): the coach gate is the class profile's, so
    -- a non-druid is the generic profile, not a flag
    local druid = MD.ClassProfile
    MD.ClassProfile = MD.Profiles.generic
    local recF = buildFixture({ meterOverridden = true })
    recF.id = 3300000000
    recF.zone = "Hellfire Citadel: The Shattered Halls of the Warchief"
    MD.cdb.recordings = { recF, recGood, recBad }
    SP.plans[recF.id] = nil
    SlashCmdList.SPELLTUNER("replay 1")
    local st = MD.Replay._state()
    local fightR, vL = BandEdges(st)
    local cut = rawget(st.headerFS, "w") or 0
    check("T72: at one column the fight stops short of the verdict (cut, not overdrawn)",
        st.frame:GetWidth() < TWO_COLS and not st.band.coach:IsShown() and st.band.word:IsShown()
        and BandVerdict(st):find(BAD .. "does not replay: ", 1, true) ~= nil
        and fightR < vL and cut < st.headerFS:GetStringWidth(),
        string.format("width=%s fight ends %.1f verdict starts %.1f box %.1f of %.1f", tostring(st.frame:GetWidth()),
            fightR, vL, cut, st.headerFS:GetStringWidth()))
    MD.ClassProfile = druid
end

do
    -- a fight that does not replay: the verdict names the gate in bad, and
    -- Coach anyway takes the place of the quoted "/md replay N force"; mockup
    -- M3 draws that band at the two-column width, the suggested column dimmed
    local recF = buildFixture({ meterOverridden = true })
    recF.id = 3200000000
    MD.cdb.recordings = { recF, recGood, recBad }
    SP.plans[recF.id] = nil
    SlashCmdList.SPELLTUNER("replay 1")
    local st = MD.Replay._state()
    local band = st.frame.band
    local v = BandVerdict(st)
    local hint = st.hint and st.hint:GetText() or ""
    local title0 = st.right.title:GetText() or ""
    check("T72: a fight that does not replay says so in bad, naming the gate, with Coach anyway",
        v:find(BAD .. "does not replay: ", 1, true) ~= nil and band ~= nil and band.coach:IsShown()
        and MD.replayCoaching == nil and st.frame:GetWidth() == TWO_COLS and st.right.dimmed == true
        and title0:find("not coached", 1, true) ~= nil and hint:find("force", 1, true) == nil,
        v .. " / hint=" .. hint .. " / width=" .. tostring(st.frame:GetWidth()) .. " / " .. title0)
    local fightR, vL, vR = BandEdges(st)
    local cL = Span(st.frame, band.coach)
    check("T72: the band's fight ends left of the verdict, the verdict left of Coach anyway",
        fightR < vL and vR <= cL,
        string.format("fight ends %.1f, verdict %.1f-%.1f, Coach anyway from %.1f", fightR, vL, vR, cL))
    MD.Replay._seek(12) -- the reopen keeps the replay's time (RebuildSuggested's)
    local said = CapturedChat(function()
        local click = band and band.coach:GetScript("OnClick")
        if click then click(band.coach) end
    end)
    st = MD.Replay._state()
    local nothing = false
    for _, l in ipairs(said) do if l:find("nothing to force", 1, true) then nothing = true end end
    check("T72: Coach anyway coaches it with both columns laid out at once",
        MD.replayCoaching == recF.id and st.frame:GetWidth() == TWO_COLS and st.right.dimmed == true
        and not (band and band.coach:IsShown()) and not nothing
        and math.abs(st.left.state.t - 12) < 1e-6,
        string.format("coaching=%s width=%s t=%.2f lines=%s", tostring(MD.replayCoaching),
            tostring(st.frame:GetWidth()), st.left.state.t, table.concat(said, " / ")))
    local done = FinishSearch()
    st = MD.Replay._state()
    check("T72: ...and the forced plan is drawn at the same width, the verdict still bad",
        done and st.right.state ~= nil and st.frame:GetWidth() == TWO_COLS
        and BandVerdict(st):find(BAD .. "does not replay", 1, true) ~= nil, BandVerdict(st))
    -- the strategy chooser shares the column titles' line: the forced plan's
    -- title stops short of it, and FORCED is said in the band instead
    local dd = MD.Replay._strategy()
    local title = st.right.title:GetText() or ""
    local _, tR = Span(st.frame, st.right.title)
    local ddL = Span(st.frame, dd)
    local fightR, vL = BandEdges(st)
    check("T72: after Coach anyway the title stops short of the chooser; the band says coached anyway",
        dd:IsShown() and tR < ddL and title:find("FORCED", 1, true) == nil
        and BandVerdict(st):find("coached anyway", 1, true) ~= nil and fightR < vL,
        string.format("title ends %.1f, chooser from %.1f, title=%s / %s", tR, ddL, title, BandVerdict(st)))
end

do
    -- the keyboard, under the pointer only (Space, Left / Right, the rest passed on)
    local st = MD.Replay._state()
    local f = st.frame
    local kb, prop = {}, nil
    f.EnableKeyboard = function(_, on) kb[#kb + 1] = on and true or false end
    f.SetPropagateKeyboardInput = function(_, on) prop = on end
    local function Script(name, ...) local fn = f:GetScript(name); if fn then fn(f, ...) end end
    MD.Replay._setPlaying(false)
    MD.Replay._seek(10)
    S.mouseFocus = f
    Script("OnEnter")
    local onOver = kb[#kb] == true
    Script("OnKeyDown", "SPACE")
    local nowPlaying, spaceProp = MD.Replay._state().playing, prop
    Script("OnKeyDown", "SPACE")
    local stopped = not MD.Replay._state().playing
    check("T72: with the pointer over the replay Space plays and pauses, and stays with the window",
        onOver and nowPlaying == true and stopped and spaceProp == false,
        string.format("kb=%s playing=%s stopped=%s prop=%s", tostring(kb[#kb]), tostring(nowPlaying),
            tostring(stopped), tostring(spaceProp)))
    local t0 = st.left.state.t
    Script("OnKeyDown", "RIGHT")
    local t1 = st.left.state.t
    Script("OnKeyDown", "LEFT")
    local t2 = st.left.state.t
    prop = nil
    Script("OnKeyDown", "W")
    check("T72: Left / Right seek 5 s; an unbound key goes on to the game",
        math.abs(t1 - t0 - 5) < 1e-6 and math.abs(t2 - t0) < 1e-6 and prop == true
        and not MD.Replay._state().playing,
        string.format("t %.2f -> %.2f -> %.2f, W propagates=%s", t0, t1, t2, tostring(prop)))
    S.mouseFocus = nil
    Script("OnLeave")
    check("T72: the keyboard is let go when the pointer leaves the window", kb[#kb] == false,
        tostring(kb[#kb]))
    f.EnableKeyboard, f.SetPropagateKeyboardInput = nil, nil

    -- the reconstruction's marker in the bar's tooltip: hovering the left
    -- button is hovering its bar (mockup M3, frame 2)
    MD.Replay._seek(10)
    local uf = st.left.frames[2]
    GameTooltip.lines = nil
    local enter = uf and uf:GetScript("OnEnter")
    if enter then enter(uf) end
    local first = GameTooltip.lines and GameTooltip.lines[1]
    local lines = {}
    for _, line in ipairs(GameTooltip.lines or {}) do lines[#lines + 1] = tostring(line[1]) .. " " .. tostring(line[2]) end
    local leave = uf and uf:GetScript("OnLeave")
    if leave then leave(uf) end
    check("T72: the left bar's hover names the target and marks the health reconstructed",
        first ~= nil and tostring(first[1]):find("Tank", 1, true) ~= nil
        and tostring(first[2]):find("reconstructed", 1, true) ~= nil,
        table.concat(lines, " / "))
end

--------------------------------------------------------------------------------
-- 10: the window will not open in combat
--------------------------------------------------------------------------------
if W.frame then W.frame:Hide() end
S.inCombat = true
local combatLines = CapturedChat(function() SlashCmdList.SPELLTUNER("replay 1") end)
local refusedCombat = false
for _, l in ipairs(combatLines) do
    if l:find("not in combat", 1, true) then refusedCombat = true end
end
check("the window will not open in combat",
    refusedCombat and not (MD.Replay._state().frame and MD.Replay._state().frame:IsShown()))
S.inCombat = false

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
