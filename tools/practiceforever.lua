-- tools/run.sh tools/practiceforever.lua
--
-- T18 (docs/tasks/T18-practice-forever.md): Practice on Forever -- the
-- Simulate -> Practice view (a placeholder until the Practice module is on,
-- same shape as Reports -> Review's own), the panel built from the Forever
-- kit's own spells (Kit_Forever.lua/Spells/Book.lua, T15), a session played
-- against a fake clock and recorded (Engine/Practice.lua, one file for both
-- lines), the recording replaying through the same engine with every gate
-- passing, a bound key casting and an unbound one propagating (UI/
-- ReplayWindow.lua's practice mode), ending it reopening as a replay and
-- listing under Review, the commands existing only with the module on, and
-- every painted string ASCII with no bare pipe. Forever only.
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

local function CapturedChat(body)
    local lines = {}
    local frame = _G.DEFAULT_CHAT_FRAME
    local orig = frame.AddMessage
    frame.AddMessage = function(_, m) lines[#lines + 1] = m end
    body()
    frame.AddMessage = orig
    return lines
end

-- IsVisible, not just IsShown (tools/reviewforever.lua's own reasoning): a
-- hidden pane's own children stay .shown = true, only the ancestor's flag
-- flips, so a placeholder swapped for the real pane must be checked the way
-- the eye would see it.
local function TextPresent(text)
    for _, f in ipairs(S.allFrames) do
        if f.GetText and f:IsVisible() then
            local okt, txt = pcall(f.GetText, f)
            if okt and txt == text then return true end
        end
    end
    return false
end
local function Button(text)
    for _, f in ipairs(S.allFrames) do
        if f.kind == "Button" and f.text == text and f.shown ~= false then return f end
    end
    return nil
end
local function Click(b, button) local fn = b and b:GetScript("OnClick"); if fn then fn(b, button or "LeftButton") end end

--------------------------------------------------------------------------------
-- 1: the Simulate group has a Practice view, a placeholder until the module
--    is on
--------------------------------------------------------------------------------
MD:SelectView("simulate", "practice")
local g, v = MD:SelectedView()
check("the Simulate group has a Practice view, a placeholder until the module is on",
    g == "simulate" and v == "practice"
    and TextPresent("Practice needs the Practice module - Settings -> Modules")
    and MD:ModuleState("SpellTuner_Practice") == "off"
    and #S.loadAddOnCalls == 0,
    "group=" .. tostring(g) .. " view=" .. tostring(v))

--------------------------------------------------------------------------------
-- 7: /st practice and /st binds exist only with the Practice module on
--------------------------------------------------------------------------------
local beforeOpenNil = (MD.OpenPractice == nil)
-- would have raised, unguarded, if either command already existed
CapturedChat(function() SlashCmdList.SPELLTUNER("practice") end)
CapturedChat(function() SlashCmdList.SPELLTUNER("binds") end)

MD:SetModule("SpellTuner_Practice", true) -- loads Recorder, Replay (engine/window/review) and this module's own files

check("/st practice and /st binds exist only with the Practice module on",
    beforeOpenNil and type(MD.OpenPractice) == "function" and type(MD.Practice) == "table"
    and type(MD.ToggleBindings) == "function" and MD.SimPlanner ~= nil,
    "beforeOpenNil=" .. tostring(beforeOpenNil) .. " afterOpen=" .. tostring(MD.OpenPractice))

local PR, SD, SM = MD.Practice, MD.SpellData, MD.SimModel

--------------------------------------------------------------------------------
-- 2: the practice panel builds a fight from the Forever kit's own spells --
--    PR.SpellFor resolves through MD.SpellData (Kit_Forever.lua's own read of
--    Spells/Book.lua), not a hand-kept table
--------------------------------------------------------------------------------
MD.player.isDruid = true
MD.cdb.practice, MD.db.practiceBinds = {}, nil
local parent = CreateFrame("Frame")
local panel = MD.DashboardParts.CreatePractice(parent, 912)
panel.frame:Show()
panel:Render()
local rejID = PR.SpellFor({ family = "Rejuvenation" })
check("the practice panel builds a fight from the Forever kit's spells",
    panel.frame ~= nil and MD.cdb.practiceSetup ~= nil and #MD.cdb.practiceSetup.targets == 5
    and rejID ~= nil and rejID == SD.maxRank.Rejuvenation
    and SD.spells[rejID] and SD.spells[rejID].family == "Rejuvenation",
    "rejID=" .. tostring(rejID) .. " maxRank=" .. tostring(SD.maxRank.Rejuvenation))

--------------------------------------------------------------------------------
-- 3: a session plays against a fake clock with the Forever kit and records a
--    practice stream
--------------------------------------------------------------------------------
MD.db.practiceBinds = { { key = "1", family = "Rejuvenation" }, { key = "2", family = "HealingTouch" } }
local setup = PR.DefaultSetup("2", 64) -- healer + tank, small and deterministic
setup.dur, setup.fixedSeed = 20, 9
local errors3 = {}
local s = PR.New(PR.CopySetup(setup), { seed = setup.fixedSeed, noStore = true,
    onError = function(m) errors3[#errors3 + 1] = m end })
assert(s.state == "ready", "expected a new session to be ready, not running, got " .. tostring(s.state))
s:Start()
local script = { { 1.0, SD.maxRank.Rejuvenation, 1 }, { 8.0, SD.maxRank.HealingTouch, 1 } }
local nextI = 1
while s.state == "running" do
    local p = script[nextI]
    if p and s.clock >= p[1] - 1e-9 then
        s:Cast(p[2], p[3])
        nextI = nextI + 1
    end
    s:Update(0.05)
end
local rec = s.rec
check("a session plays against a fake clock with the Forever kit and records a practice stream",
    s.state == "done" and rec ~= nil and rec.v == 2 and (rec.ownCasts or 0) >= 2 and #errors3 == 0,
    "state=" .. tostring(s.state) .. " rec=" .. tostring(rec ~= nil) ..
    " ownCasts=" .. tostring(rec and rec.ownCasts) .. " errors=" .. table.concat(errors3, "; "))

--------------------------------------------------------------------------------
-- R4 (review 2026-09-29): the healer regenerates. MD.Regen is TBC's
-- Engine/RegenModel.lua and is on no Forever TOC, so the regen rates come
-- from the adapter's GetManaRegen (plain out of combat, where practice
-- starts): the scenario, and so the recording, carry them -- not zero.
--------------------------------------------------------------------------------
do
    local wantBase, wantCast = GetManaRegen() -- the stub's plain out-of-combat pair
    local ini = rec and rec.initial or {}
    local mb = rec and rec.mana and rec.mana.base and rec.mana.base[1]
    local mc = rec and rec.mana and rec.mana.cast and rec.mana.cast[1]
    check("R4: a Forever practice session regenerates at the client's own GetManaRegen rates",
        MD.Regen == nil and type(wantBase) == "number" and wantBase > 0
        and ini.apiBase == wantBase and ini.apiCasting == wantCast and mb == wantBase and mc == wantCast,
        string.format("apiBase=%s apiCasting=%s mana.base[1]=%s want %s/%s", tostring(ini.apiBase),
            tostring(ini.apiCasting), tostring(mb), tostring(wantBase), tostring(wantCast)))
end

--------------------------------------------------------------------------------
-- 4: the recording replays to the health the player saw and every gate
--    passes -- the same engine, the Forever kit
--------------------------------------------------------------------------------
local kit = MD.RankMath:SpellKit({ live = true })
local v4 = SM:Validate(rec, kit)
local failed = {}
for _, gate in ipairs(v4.gates) do if not gate.ok then failed[#failed + 1] = gate.name .. ": " .. tostring(gate.text) end end
local sc = SM.ScenarioFromRecording(rec, kit)
local r4 = SM:Run(sc, nil, { critMode = "ev" })
local worst = 0
for i = 1, #rec.tracked do
    local n = #rec.hp.t
    local want = rec.hp.hp[i][n]
    local got = r4.hpCurve[i] and r4.hpCurve[i][#r4.hpCurve[i]]
    if want and got then worst = math.max(worst, math.abs(want - got)) end
end
check("the recording replays to the health the player saw and every gate passes",
    v4.ok and worst < 1,
    "gates: " .. table.concat(failed, "; ") .. " worst hp diff " .. string.format("%.3f", worst))

--------------------------------------------------------------------------------
-- 5: a key bound to a spell casts it; an unbound key propagates
--------------------------------------------------------------------------------
MD.cdb.practiceSetup = PR.CopySetup(setup)
MD.cdb.practiceSetup.dur = 20
MD:OpenPractice(PR.CopySetup(MD.cdb.practiceSetup), 5)
local live5 = MD.Replay._live()
local st5 = MD.Replay._state()
assert(live5 ~= nil and live5.state == "running" and st5.frame and st5.frame:IsShown(),
    "expected practice mode to open the replay window")

local tank5 = st5.left.frames[1]
tank5:GetScript("OnEnter")(tank5)
local _, hov5 = MD.Replay._live()
S.Tick(1.0)
st5.frame:GetScript("OnKeyDown")(st5.frame, "1") -- bound to Rejuvenation
S.Tick(0.3)
local castsBound = #live5.own
st5.frame:GetScript("OnKeyDown")(st5.frame, "9") -- not bound to anything
S.Tick(0.3)
local castsUnbound = #live5.own
check("a key bound to a spell casts it; an unbound key propagates",
    hov5 == 1 and castsBound >= 1 and castsUnbound == castsBound,
    "hover=" .. tostring(hov5) .. " castsBound=" .. tostring(castsBound) .. " castsUnbound=" .. tostring(castsUnbound))

--------------------------------------------------------------------------------
-- 6: ending the session reopens it as a replay and lists it in Review
--------------------------------------------------------------------------------
Click(Button("End"))
local live6 = MD.Replay._live()
local st6 = MD.Replay._state()
local reopened = live6 == nil and MD:GetRecording("p1") ~= nil
    and st6.rp and not st6.rp.live and st6.rp.rec == MD:GetRecording("p1")

local reviewParent = CreateFrame("Frame")
local review = MD.DashboardParts.CreateReview(reviewParent, 912)
review.frame:Show()
review:Render()
Click(Button("Practice"))
review:Render()
local listed = false
for _, f in ipairs(S.allFrames) do
    if type(f.text) == "string" and f.text:find("Practice: Duo") and f.shown ~= false then listed = true end
end
check("ending the session reopens it as a replay and lists it in Review", reopened and listed,
    "reopened=" .. tostring(reopened) .. " listed=" .. tostring(listed))

--------------------------------------------------------------------------------
-- 8: every string the panel and the bindings window paint is ASCII with no
--    bare pipe
--------------------------------------------------------------------------------
MD:ShowBindings()
local function Pipes(str)
    -- a colour code, a reset, the client's own "|n" newline escape and a
    -- doubled pipe (Esc's own "||", a literal pipe) are all safe; anything
    -- else left over is BARE.
    local stripped = str:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", ""):gsub("||", "")
    return stripped:find("|", 1, true) ~= nil
end
-- ASCII (0x20-0x7e), plus the newline the bindings summary joins its lines
-- with (UI/PracticePanel.lua's BindLines, one font string, several lines).
-- ASCII (0x20-0x7e), plus the newline the bindings summary joins its lines
-- with (UI/PracticePanel.lua's BindLines, one font string, several lines).
local function NonAscii(str) return str:find("[^ -~\n]") ~= nil end
-- UI/Style.lua's own header close button ("x", U+00D7, line 166) -- shared by
-- every Cell-style window in the tree (UI.CreateMovableFrame, which the
-- bindings window uses) and already an accepted, named exception in
-- tools/modulecheck.lua's own ASCII walk.
local CLOSE_GLYPH = "\195\151"
local bad = {}
local function Scan(label, str)
    if type(str) ~= "string" or str == "" or str == CLOSE_GLYPH then return end
    if Pipes(str) then bad[#bad + 1] = label .. " has a bare pipe: " .. str end
    if NonAscii(str) then bad[#bad + 1] = label .. " is not ASCII: " .. str end
end
-- only under the panel's own frame and the bindings window (never UI/Style.lua's
-- own chrome, whose close button is a literal "x" close glyph -- the same
-- named exception tools/modulecheck.lua and tools/reviewforever.lua make)
local function Under(f, root)
    if not root then return false end
    local guard = 0
    while f and guard < 50 do
        if f == root then return true end
        f, guard = f.parentFrame, guard + 1
    end
    return false
end
local bindingsFrame = MD.BindingsWindow._frame()
for _, f in ipairs(S.allFrames) do
    if f.GetText and (Under(f, panel.frame) or Under(f, bindingsFrame)) then
        local okt, txt = pcall(f.GetText, f)
        if okt and type(txt) == "string" then Scan("frame text", txt) end
    end
end
check("every string the panel and the bindings window paint is ASCII with no bare pipe", #bad == 0, bad[1])


--------------------------------------------------------------------------------
-- T24 (docs/tasks/T24-practice-own-spells.md): practice offers only the spells
-- in your own spellbook. Nothing bound is the default on Forever; the TBC
-- author's shipped defaults are dropped once; a family the book lacks is said
-- so and casts nothing; the picker and a new row come from the Forever kit.
--------------------------------------------------------------------------------
local FAMILY_NAMES = { "Lifebloom", "Rejuvenation", "Regrowth", "Swiftmend", "HealingTouch", "Healing Touch" }
-- the panel's own bindings text: the visible font string under the panel that
-- carries the bindings summary (the key lines, or the nothing-bound sentence)
local function PanelBindText()
    panel:Render()
    for _, f in ipairs(S.allFrames) do
        if f.GetText and Under(f, panel.frame) and f:IsVisible() then
            local okt, txt = pcall(f.GetText, f)
            if okt and type(txt) == "string"
               and (txt:find("Nothing is bound -", 1, true) or txt:find("Hover a frame and press", 1, true)) then
                return txt
            end
        end
    end
    return nil
end
local function Lines(str)
    local out = {}
    for line in (str or ""):gmatch("[^\n]+") do out[#out + 1] = line end
    return out
end
local function CountOf(str, needle)
    local n, from = 0, 1
    while true do
        local a, b = str:find(needle, from, true)
        if not a then return n end
        n, from = n + 1, b + 1
    end
end

do -- 1
    MD.db.practiceBinds = nil
    local b = PR.Binds()
    local txt = PanelBindText()
    local nameHit
    for _, n in ipairs(FAMILY_NAMES) do if txt and txt:find(n, 1, true) then nameHit = n end end
    check("on Forever nothing is bound until you bind or import",
        type(b) == "table" and #b == 0 and MD.db.practiceBinds == b
        and txt ~= nil and txt:find("Import", 1, true) ~= nil and txt:find("Edit bindings", 1, true) ~= nil
        and nameHit == nil,
        "n=" .. tostring(type(b) == "table" and #b) .. " text=" .. tostring(txt) .. " name=" .. tostring(nameHit))
end

do -- 2
    local function CopyDefaults()
        local out = {}
        for i, d in ipairs(PR.DEFAULT_BINDS) do out[i] = { key = d.key, family = d.family, rank = d.rank } end
        return out
    end
    MD.db.practiceBinds = CopyDefaults()
    local dropped = PR.Binds()
    local droppedOk = type(dropped) == "table" and #dropped == 0 and MD.db.practiceBinds == dropped
    local changed = CopyDefaults()
    changed[3].key = "CTRL-Q"
    MD.db.practiceBinds = changed
    -- T27: "kept whole" is the STORED list (PR.AllBinds); PR.Binds() now
    -- leaves out the three whose families this book lacks (decision 9)
    local kept = PR.AllBinds()
    local keptOk = #kept == #PR.DEFAULT_BINDS and kept[1].key == PR.DEFAULT_BINDS[1].key
        and kept[3].key == "CTRL-Q" and kept[6].family == PR.DEFAULT_BINDS[6].family
    check("the TBC author's defaults saved on Forever are dropped once", droppedOk and keptOk,
        "dropped=" .. tostring(droppedOk) .. " kept=" .. tostring(keptOk) .. " n=" .. tostring(#kept))
end

do -- 3
    -- T27 (decision 9): a bind for a spell not in the book is no longer
    -- listed with "(not in your spellbook)" -- it is not listed at all (T24's
    -- label half of this check became the T27 checks below); the rest holds.
    MD.db.practiceBinds = { { key = "1", family = "Lifebloom" }, { key = "2", family = "Rejuvenation" } }
    local lines = Lines(PanelBindText())
    local lbLine, rejLine
    for _, l in ipairs(lines) do
        if l:find("Lifebloom", 1, true) then lbLine = l end
        if l:find("Rejuvenation", 1, true) then rejLine = l end
    end
    local textOk = lbLine == nil
        and rejLine and rejLine:find("(not in your spellbook)", 1, true) == nil
        and CountOf(table.concat(lines, "\n"), "(not in your spellbook)") == 0
    local nilFor = PR.SpellFor(MD.db.practiceBinds[1]) == nil and PR.SpellFor(MD.db.practiceBinds[2]) ~= nil

    local st3 = PR.CopySetup(setup)
    st3.dur = 20
    MD:OpenPractice(st3, 5)
    local live3, st3w = MD.Replay._live(), MD.Replay._state()
    assert(live3 ~= nil and live3.state == "running" and st3w.frame and st3w.frame:IsShown(),
        "expected practice mode to open the replay window")
    local tank = st3w.left.frames[1]
    tank:GetScript("OnEnter")(tank)
    S.Tick(1.0)
    st3w.frame:GetScript("OnKeyDown")(st3w.frame, "1")
    S.Tick(0.3)
    local afterMissing = #live3.own
    st3w.frame:GetScript("OnKeyDown")(st3w.frame, "2")
    S.Tick(0.3)
    local afterBound = #live3.own
    check("a bind for a spell not in your spellbook is not shown and casts nothing",
        textOk and nilFor and afterMissing == 0 and afterBound >= 1,
        "text=" .. tostring(textOk) .. " nil=" .. tostring(nilFor) .. " missing=" .. tostring(afterMissing)
        .. " bound=" .. tostring(afterBound))
    Click(Button("End"))
end

do -- 4
    MD.db.practiceBinds = { { key = "1", family = "Rejuvenation" } }
    MD:ShowBindings()
    local win = MD.BindingsWindow._rows()
    local items = win[1] and win[1].spell.items or {}
    local bad, n = nil, 0
    for _, it in ipairs(items) do
        local fam = it.id:match("^(%a+):")
        n = n + 1
        if not fam or fam == "Lifebloom" or not (SD.known[fam] and #SD.known[fam] > 0) then bad = it.id end
        for _, c in ipairs(it.children or {}) do
            local cf = c.id:match("^(%a+):")
            if not cf or cf == "Lifebloom" or not (SD.known[cf] and #SD.known[cf] > 0) then bad = c.id end
        end
    end
    check("the spell picker lists only families in your spellbook", n > 0 and bad == nil,
        "items=" .. n .. " bad=" .. tostring(bad))
end

do -- 5
    MD.db.practiceBinds = {}
    MD:ShowBindings()
    Click(Button("+ binding"))
    local b1 = PR.Binds()[1]
    local first = PR.FirstFamily()
    local ok1 = b1 ~= nil and first ~= nil and b1.family == first and SD.known[first] ~= nil and #SD.known[first] > 0

    local savedKnown = SD.known
    SD.known = {}
    MD.db.practiceBinds = {}
    local emptyFirst = PR.FirstFamily()
    local okc, errc = pcall(function() Click(Button("+ binding")) end)
    local b2 = PR.Binds()[1]
    local ok2 = okc and emptyFirst == nil and b2 ~= nil and b2.family == nil
    SD.known = savedKnown
    check("a new binding row picks a spell you have", ok1 and ok2,
        "first=" .. tostring(first) .. " b1=" .. tostring(b1 and b1.family) .. " raised=" .. tostring(not okc and errc)
        .. " b2=" .. tostring(b2 and b2.family))
end

do -- 6
    MD.db.practiceBinds = {}
    panel:Render()
    local startB
    for _, f in ipairs(S.allFrames) do
        if f.kind == "Button" and f.text == "Start practice" and Under(f, panel.frame) then startB = f end
    end
    Click(startB)
    local live6b = MD.Replay._live()
    local said = false
    for _, f in ipairs(S.allFrames) do
        if f.GetText and Under(f, panel.frame) and f:IsVisible() then
            local okt, txt = pcall(f.GetText, f)
            if okt and type(txt) == "string" and txt:find("Nothing is bound yet", 1, true) then said = true end
        end
    end
    check("Start with nothing bound says so and opens nothing", live6b == nil and said,
        "button=" .. tostring(startB ~= nil) .. " live=" .. tostring(live6b ~= nil) .. " said=" .. tostring(said))
end

--------------------------------------------------------------------------------
-- T27 (docs/tasks/T27-practice-hidden-binds.md, decision 9): a binding for a
-- spell not in your spellbook is hidden on Forever -- not listed, not counted,
-- not cast -- but kept in db.practiceBinds, so it comes back when the spell is
-- learned; an import skips such a spell and names it; the bindings sheet's
-- footer counts what it keeps, names it on hover, and Forget deletes it.
--------------------------------------------------------------------------------
local function Contains(list, family)
    for _, b in ipairs(list or {}) do if b.family == family then return true end end
    return false
end
local function VisibleText(needle, root)
    for _, f in ipairs(S.allFrames) do
        if f.GetText and f:IsVisible() and (not root or Under(f, root)) then
            local okt, txt = pcall(f.GetText, f)
            if okt and type(txt) == "string" and txt:find(needle, 1, true) then return f, txt end
        end
    end
    return nil
end
local function ShownRows()
    local n = 0
    for _, r in ipairs(MD.BindingsWindow._rows() or {}) do if r:IsShown() then n = n + 1 end end
    return n
end

do -- T27 1: an import skips a spell not in your spellbook and names it
    MD.db.practiceBinds = { { key = "2", family = "Rejuvenation" } }
    _G.CellCharacterDB = { clickCastings = { useCommon = true, common = {
        { "type5", "spell", "Lifebloom" },
        { "shift-type1", "spell", "Healing Touch" },
    } } }
    MD:ShowBindings()
    Click(Button("Cell"))
    local status = MD.BindingsWindow._status()
    _G.CellCharacterDB = nil
    local a, r, same, skipped = PR.ApplyImport({ { key = "BUTTON5", family = "Lifebloom" } })
    local direct = a == 0 and r == 0 and same == 0 and type(skipped) == "table"
        and #skipped == 1 and skipped[1] == "Lifebloom"
    check("T27: an import skips a spell not in your spellbook and names it",
        status:find("skipped (not in your spellbook): Lifebloom", 1, true) ~= nil
        and not Contains(MD.db.practiceBinds, "Lifebloom") and Contains(MD.db.practiceBinds, "HealingTouch")
        and direct,
        "status=" .. status .. " direct=" .. tostring(direct))
end

do -- T27 2: an existing binding for it is not listed, not counted, not cast
    MD.db.practiceBinds = { { key = "1", family = "Lifebloom" }, { key = "2", family = "Rejuvenation" } }
    local txt = PanelBindText() or ""
    local binds = PR.Binds()
    MD:ShowBindings()
    local rowsShown = ShownRows()
    local bound = PR.BindFor("1")
    check("T27: a binding for a spell not in your spellbook is not listed, not counted, not cast",
        #binds == 1 and binds[1].family == "Rejuvenation" and not txt:find("Lifebloom", 1, true)
        and rowsShown == 1 and bound == nil and PR.BindFor("2") ~= nil,
        "binds=" .. #binds .. " rows=" .. rowsShown .. " bound=" .. tostring(bound) .. " text=" .. txt)
end

do -- T27 3: it is still in db.practiceBinds, even after the sheet edits the rest
    MD.db.practiceBinds = { { key = "1", family = "Lifebloom" }, { key = "2", family = "Rejuvenation" } }
    MD:ShowBindings()
    local win = MD.BindingsWindow._rows()
    Click(win[1] and win[1].del)                -- the one row shown: Rejuvenation
    Click(Button("+ binding"))                  -- a new row, appended
    local db = MD.db.practiceBinds
    check("T27: the hidden binding is still in db.practiceBinds",
        #db == 2 and db[1].family == "Lifebloom" and db[1].key == "1"
        and db[2].family == PR.FirstFamily() and #PR.Binds() == 1 and PR.Binds()[1] == db[2],
        "db=" .. #db .. " first=" .. tostring(db[1] and db[1].family) .. " visible=" .. #PR.Binds())
end

do -- T27 4: Forget deletes it; the footer counted it and named it on hover
    MD.db.practiceBinds = { { key = "1", family = "Lifebloom" }, { key = "2", family = "Rejuvenation" } }
    MD:ShowBindings()
    local bw = MD.BindingsWindow._frame()
    local line = VisibleText("1 binding kept for a spell you have not learned", bw)
    local hovered = false
    local holder = line and line.parentFrame
    local enter = holder and holder:GetScript("OnEnter")
    if enter then
        enter(holder)
        for _, l in ipairs(MD.UI.tooltip.lines or {}) do
            if type(l[1]) == "string" and l[1]:find("Lifebloom", 1, true) then hovered = true end
        end
    end
    local hidden = PR.HiddenBinds and PR.HiddenBinds() or {}
    local forget = Button("Forget")
    Click(forget)
    local db = MD.db.practiceBinds
    local after = VisibleText("kept for a spell", bw)
    check("T27: the sheet's footer names the kept binding and Forget deletes it",
        line ~= nil and hovered and #hidden == 1 and hidden[1].family == "Lifebloom"
        and #db == 1 and db[1].family == "Rejuvenation" and after == nil,
        "line=" .. tostring(line ~= nil) .. " hover=" .. tostring(hovered) .. " hidden=" .. #hidden
        .. " db=" .. #db .. " after=" .. tostring(after ~= nil))
end

do -- T27 5: learning the spell brings the binding back (Regrowth: Forever has
   -- no Lifebloom to learn -- Kit_Forever.lua's FAMILY_KEY has no slot for it)
    MD.db.practiceBinds = { { key = "3", family = "Regrowth" }, { key = "2", family = "Rejuvenation" } }
    local before = PanelBindText() or ""
    local hiddenBefore = #PR.Binds() == 1 and not before:find("Regrowth", 1, true)
    S.AddSpell(90301, "Regrowth", "Rank 1",
        function() return "Heals a friendly target for 93 to 107 and another 98 over 21 sec." end,
        { cast = 2000, cost = 80, level = 1 })
    MD.Book:MarkDirty()
    local after = PanelBindText() or ""
    local _, id = PR.BindFor("3")
    check("T27: learning the spell brings its binding back",
        hiddenBefore and #PR.Binds() == 2 and after:find("Regrowth", 1, true) ~= nil and id == 90301
        and #MD.db.practiceBinds == 2,
        "before=" .. tostring(hiddenBefore) .. " visible=" .. #PR.Binds() .. " id=" .. tostring(id) .. " text=" .. after)
end

print(string.format("\n%d ok, %d failed", ok, #fails))
for _, f in ipairs(fails) do print("  FAIL " .. f) end
if #fails > 0 then os.exit(1) end
