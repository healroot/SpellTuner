-- tools/run.sh --flavour forever|tbc tools/capscheck.lua
--
-- T99 (docs/SPEC-next.md 4.4 and section 11, S1's second step): the capability
-- gates. The 23 `MD.player.isDruid` gates in 10 files became
-- MD.ClassProfile:Can(cap) (Spells/Profiles.lua); this suite holds that:
--
--   * a SOURCE SCAN of every file a TOC ships (both main TOCs and the three
--     modules') finds `isDruid` only in the reads 4.4 keeps (four in three
--     files since T111) -- the
--     allow-list below, each with the reason it stays (comments are not code
--     and are left out of the scan);
--   * the druid's profile grants every capability the gates ask for, and the
--     gated surfaces say today's words to a druid;
--   * a mage (the stub's S.units.player.class, the generic profile) is told
--     "<subject>: not modelled for Mage yet" on Review, the replay, practice
--     and the simulator (and, on TBC, the profile report) -- never "Druid-only"
--     (T106: a mage, a class with no profile on either line; it was a priest
--     until the Forever priest had a profile of its own);
--   * on Forever, Can("coach") asks the Replay module's MD.KitLive: with the
--     module off it answers false, "module" and Review keeps the module's own
--     placeholder (no new words); a live kit that prices no heal answers
--     false, "kit".
HARNESS_FLAVOUR = { "forever", "tbc" }

local here = arg[0]:match("^(.*)/[^/]+$")
local T = dofile(here .. "/lib/t.lua")
-- A detail is printed only for a failure (tools/profilecheck.lua's rule).
local function check(name, cond, detail)
    if cond or detail == "" then detail = nil end
    return T.check(name, cond, detail)
end

local a0 = arg[0]; arg[0] = here .. "/harness.lua"
local MD = dofile(here .. "/harness.lua")
arg[0] = a0

local S = _G.STUB
local forever = S.flavour == "forever"
local P = MD.Profiles
-- The TBC stub has no GetBuildInfo, which /md profile's first line reads
-- (tools/verifycheck.lua answers the same fixed build).
if _G.GetBuildInfo == nil then
    _G.GetBuildInfo = function() return "2.5.5", "65000", "Sep 1 2026", 20506 end
end

local chat = {}
function MD:Print(m) chat[#chat + 1] = tostring(m) end
local function Said(sub)
    for _, m in ipairs(chat) do if m:find(sub, 1, true) then return m end end
    return nil
end

-- A visible font string or button whose text contains `sub` (colour codes off).
local function TextShowing(sub)
    for _, f in ipairs(S.allFrames) do
        if f.GetText and f:IsVisible() then
            local okt, txt = pcall(f.GetText, f)
            if okt and type(txt) == "string" and T.Strip(txt):find(sub, 1, true) then return T.Strip(txt) end
        end
    end
    return nil
end
-- A button by its text, under `root` when one is given (the Forever window
-- builds a Review pane of its own once the module is on).
local function Under(f, root)
    if root == nil then return true end
    local p = f
    while p do
        if p == root then return true end
        p = rawget(p, "parentFrame")
    end
    return false
end
local function Button(text, root)
    for _, f in ipairs(S.allFrames) do
        if f.kind == "Button" and f.text == text and f.shown ~= false and Under(f, root) then return f end
    end
    return nil
end
local function Click(b, button) local fn = b and b:GetScript("OnClick"); if fn then fn(b, button or "LeftButton") end end
local function Enabled(b) return b ~= nil and b.enabled ~= false end

local function LogIn(class)
    S.units.player.class = class
    MD:DetectProfile()
    MD:Fire("CORE_LOGIN")
end

--------------------------------------------------------------------------------
-- 1. The source scan (flavour-free: it reads files)
--------------------------------------------------------------------------------
T.section("the source scan")

-- The reads that stay, file -> count, with the reason (docs/SPEC-next.md 4.4).
local ALLOWED = {
    -- defines MD.player.isDruid at load and at DetectProfile: a fact, not a gate
    ["Core.lua"] = 2,
    -- InTreeForm: Tree of Life is a druid form (the comment above the read says so)
    ["Core_TBC.lua"] = 1,
    -- the druid's own talent cost modifiers on the druid's own static table;
    -- Data/SpellData.lua changes only from a measurement, so it is described
    -- here instead of carrying a comment
    ["Data/SpellData.lua"] = 1,
    -- T111: Engine/RankMath.lua's Compute and Spells/Families_TBC.lua's book
    -- left the list -- both ask MD.ClassProfile:Can("rankTable") and read
    -- RankMath:Source() (SpellData for the druid, Spells/Book_TBC.lua for a
    -- priest, shaman or paladin)
}

local function ReadFile(rel)
    local fh = io.open(S.root .. "/" .. rel, "r")
    if not fh then return nil end
    local src = fh:read("*a")
    fh:close()
    return src
end
local function Exists(rel) local fh = io.open(S.root .. "/" .. rel, "r"); if fh then fh:close() end; return fh ~= nil end

-- Every file a TOC lists: the root TOCs, and each module's TOCs, whose entries
-- are the module's own files or (T13c) the repository's at the same path.
local shipped, order = {}, {}
local function Add(rel)
    if not shipped[rel] then shipped[rel] = true; order[#order + 1] = rel end
end
do
    local tocs = {}
    local p = io.popen('ls "' .. S.root .. '"/*.toc "' .. S.root .. '"/Modules/*/*.toc 2>/dev/null')
    for line in p:lines() do tocs[#tocs + 1] = line:sub(#S.root + 2) end
    p:close()
    for _, toc in ipairs(tocs) do
        local dir = toc:match("^(Modules/[^/]+)/")
        for _, entry in ipairs(S.TocFiles(toc)) do
            if entry:match("%.lua$") then
                if dir and Exists(dir .. "/" .. entry) then Add(dir .. "/" .. entry)
                elseif Exists(entry) then Add(entry) end
            end
        end
    end
    check("the TOCs list the files the scan reads", #order > 60
        and shipped["Core.lua"] and shipped["Core_TBC.lua"] and shipped["UI/Dashboard_Review.lua"]
        and shipped["Modules/SpellTuner_Replay/Kit_Forever.lua"], tostring(#order) .. " files")
end

-- Code only: block comments, then line comments, out.
local function Code(src)
    src = src:gsub("%-%-%[(=*)%[.-%]%1%]", "")
    return (src:gsub("%-%-[^\n]*", ""))
end
local function Count(s, needle)
    local n, at = 0, 1
    while true do
        local i = s:find(needle, at, true)
        if not i then return n end
        n, at = n + 1, i + #needle
    end
end

local found, stray = {}, {}
for _, rel in ipairs(order) do
    local n = Count(Code(ReadFile(rel) or ""), "isDruid")
    if n > 0 then
        found[rel] = n
        if ALLOWED[rel] ~= n then stray[#stray + 1] = rel .. " x" .. n end
    end
end
local missing = {}
for rel, n in pairs(ALLOWED) do
    if found[rel] ~= n then missing[#missing + 1] = rel .. " x" .. tostring(found[rel] or 0) .. " (want " .. n .. ")" end
end
table.sort(stray); table.sort(missing)
check("isDruid is read only in the four reads in three files 4.4 keeps", #stray == 0 and #missing == 0,
    table.concat(stray, ", ") .. ((#missing > 0) and (" missing: " .. table.concat(missing, ", ")) or ""))

-- The ten gate files ask the profile and no longer say "Druid-only".
local GATE_FILES = {
    "UI/Dashboard_Review.lua", "UI/ReplayWindow.lua", "UI/PracticePanel.lua", "Engine/ReviewCommands.lua",
    "UI/SimWindow.lua", "UI/Dashboard.lua", "UI/SpellTooltip.lua", "UI/Advisor.lua", "UI/Summary.lua",
    "Diagnostics_TBC.lua",
}
do
    local noAsk, oldWords = {}, {}
    for _, rel in ipairs(GATE_FILES) do
        local code = Code(ReadFile(rel) or "")
        if not code:find("ClassProfile:Can(", 1, true) then noAsk[#noAsk + 1] = rel end
        if code:lower():find("druid%-only") or code:find("Druid only", 1, true) then oldWords[#oldWords + 1] = rel end
    end
    check("each of the ten gate files asks MD.ClassProfile:Can", #noAsk == 0, table.concat(noAsk, ", "))
    check("no gate file says \"Druid-only\" any more", #oldWords == 0, table.concat(oldWords, ", "))
end
do
    local src = ReadFile("Core_TBC.lua") or ""
    local before = src:match("function MD:InTreeForm%(%)\n(.-)if not MD%.player%.isDruid")
    check("Core_TBC.lua's InTreeForm read carries the comment saying why it stays",
        before ~= nil and before:find("Druid by design", 1, true) ~= nil and before:find("Tree of Life", 1, true) ~= nil)
end

--------------------------------------------------------------------------------
-- 2. The words (pure)
--------------------------------------------------------------------------------
T.section("the words")
check("a class token is named as a sentence names it",
    P.ClassLabel("PRIEST") == "Priest" and P.ClassLabel("SHAMAN") == "Shaman"
    and P.ClassLabel("DEATHKNIGHT") == "Death Knight" and P.ClassLabel("UNKNOWN") == "your class"
    and P.ClassLabel("DRUID") == "Druid")
do
    local all = {
        P.Refusal("coach", "class", "Coaching", "PRIEST"), P.Refusal("coach", "kit", "Coaching"),
        P.Refusal("coach", "module", "coach"), P.RefusalNote("coach", "class"), P.RefusalNote("coach", "module"),
    }
    local bad
    for _, s in ipairs(all) do
        local okA, why = T.Ascii(s, { noColour = true })
        if not okA then bad = s .. ": " .. why end
    end
    check("\"<subject>: not modelled for <Class> yet\"",
        all[1] == "Coaching: not modelled for Priest yet", all[1])
    check("a kit that prices no heal and a module that is off have their own sentences",
        all[2] == "Coaching: no heal in your spellbook is modelled yet"
        and all[3] == "coach: needs the Replay module" and all[4] == "not modelled", all[2] .. " / " .. all[3])
    check("every refusal is ASCII with no pipe", bad == nil, bad)
end

--------------------------------------------------------------------------------
-- 3. The druid's profile grants what the gates ask
--------------------------------------------------------------------------------
T.section("the druid")
local CAPS = forever and { "clock", "tooltip", "rankTable", "simulate", "coach", "practice" }
    or { "clock", "tooltip", "rankTable", "advisor", "simulate", "coach", "practice" }
local function Grants(profile, caps, skip)
    local refused = {}
    for _, cap in ipairs(caps) do
        if cap ~= skip then
            local can, why = profile:Can(cap)
            if can ~= true then refused[#refused + 1] = cap .. "=" .. tostring(why) end
        end
    end
    return refused
end
check("MD.ClassProfile is the druid's at login", MD.ClassProfile == P.Get("DRUID") and MD.player.class == "DRUID")

if forever then
    ----------------------------------------------------------------------------
    -- Forever: the Replay module off, then on
    ----------------------------------------------------------------------------
    local refused = Grants(MD.ClassProfile, CAPS, "coach")
    check("the druid is granted every capability but coach before any module loads", #refused == 0,
        table.concat(refused, ", "))
    local can, why = MD.ClassProfile:Can("coach")
    check("Replay module off: Can(\"coach\") is false, \"module\" (no KitLive provider)",
        can == false and why == "module" and MD.KitLive == nil, tostring(can) .. "/" .. tostring(why))

    if not MD.UI.CreateContextMenu then S.Load({ "UI/ContextMenu.lua" }, "SpellTuner", MD) end
    MD:SelectView("reports", "review")
    check("Replay module off: Review is the module's own placeholder, no new words",
        TextShowing("Review needs the Replay module") ~= nil and TextShowing("not modelled") == nil
        and TextShowing("Druid") == nil)

    MD:SetModule("SpellTuner_Replay", true)
    can, why = MD.ClassProfile:Can("coach")
    check("Replay module on: MD.KitLive is provided and the druid coaches",
        type(MD.KitLive) == "function" and can == true and why == nil, tostring(can) .. "/" .. tostring(why))
    MD:SetModule("SpellTuner_Practice", true)

    local realLive = MD.KitLive
    MD.KitLive = function() return false, "kit" end
    can, why = MD.ClassProfile:Can("coach")
    check("a live kit that prices no heal: Can(\"coach\") is false, \"kit\"", can == false and why == "kit",
        tostring(can) .. "/" .. tostring(why))
    MD.KitLive = function() error("boom") end
    can, why = MD.ClassProfile:Can("coach")
    check("a KitLive that raises answers false, \"kit\" rather than raising", can == false and why == "kit")
    MD.KitLive = realLive
else
    local refused = Grants(MD.ClassProfile, CAPS)
    check("the druid is granted every capability the gates ask", #refused == 0, table.concat(refused, ", "))
    local can, why = MD.ClassProfile:Can("coach")
    check("TBC declares no module and provides no KitLive: the druid coaches", can == true and why == nil
        and #(MD.modules or {}) == 0 and MD.KitLive == nil)
    S.Load({ "UI/Style.lua", "UI/Theme_Flat.lua", "UI/EscStack.lua", "UI/Windows.lua", "UI/ContextMenu.lua",
             "UI/Tip.lua", "UI/Tip_TBC.lua", "UI/Dashboard_Rows.lua", "UI/Dashboard_Review.lua",
             "UI/PracticePanel.lua", "UI/BindingsWindow.lua", "UI/ReplayWindow.lua", "UI/SimWindow.lua" },
        "SpellTuner", MD)
end

--------------------------------------------------------------------------------
-- The surfaces: one fight to review, the Review pane, the practice panel and
-- (TBC) the simulator, built once and read under each class.
--------------------------------------------------------------------------------
if forever then
    local buildFixture = dofile(here .. "/foreverfixture.lua")
    local rec = buildFixture()
    rec.id = 2000000000
    MD.cdb.recordings = { rec }
else
    dofile(here .. "/fakepull.lua")(MD, S)
end
check("one fight to review", #(MD.cdb.recordings or {}) >= 1)

local parent = CreateFrame("Frame")
parent:SetSize(912, 500)
local review = MD.DashboardParts.CreateReview(parent, 912)
review.frame:SetSize(912, 500)
review.frame:Show()
MD.cdb.practice, MD.db.practiceBinds = MD.cdb.practice or {}, MD.db.practiceBinds
local pparent = CreateFrame("Frame")
local practice = MD.DashboardParts.CreatePractice(pparent, 912)
practice.frame:Show()
local sim
if not forever then
    local sparent = CreateFrame("Frame")
    sparent:SetSize(912, 600)
    sim = MD:AdoptSimPanel(sparent)
end

local function CoachHover()
    local coach = Button("Coach", review.frame)
    MD.UI.tooltip.lines = nil
    if MD.Tip then MD.Tip.lastLines = nil end
    local lines = {}
    local realShow = MD.Tip and MD.Tip.Show
    if MD.Tip then MD.Tip.Show = function(_, _, _, ls) lines = ls or {} end end
    local enter = coach and coach:GetScript("OnEnter")
    if enter then enter(coach) end
    if MD.Tip then MD.Tip.Show = realShow end
    local out = {}
    for _, l in ipairs(lines) do out[#out + 1] = T.Strip(l.l or "") end
    return table.concat(out, " / ")
end

local function Drain()
    local n = 0
    while MD.coachSearch and n < 20000 do S.Tick(0.016); n = n + 1 end
end

--------------------------------------------------------------------------------
-- 4. A mage: the not-modelled wording on Review, replay, practice and sim
--------------------------------------------------------------------------------
T.section("a mage")
LogIn("MAGE")
check("a mage is given the generic profile", MD.ClassProfile == P.generic and MD.player.class == "MAGE")
do
    local can, why = MD.ClassProfile:Can("coach")
    check("a mage cannot be coached, for the class's sake (before any module question)",
        can == false and why == "class")
    local lineCaps = forever and { "clock", "tooltip", "rankTable" } or { "clock" }
    check("a mage keeps what a non-druid had: " .. table.concat(lineCaps, ", "),
        #Grants(MD.ClassProfile, lineCaps) == 0)
end

-- Review
chat = {}
review:Render()
local coachBtn = Button("Coach", review.frame)
check("Review: Coach is off for a mage", coachBtn ~= nil and not Enabled(coachBtn))
local hover = CoachHover()
check("Review: Coach's hover says Coaching: not modelled for Mage yet",
    T.Has(hover, "Coaching: not modelled for Mage yet") and not T.Has(hover, "Druid"), hover)
review:Coach(false)
check("Review: a Coach press prints coach: not modelled for Mage yet.",
    Said("coach: not modelled for Mage yet.") ~= nil and MD.coachSearch == nil, chat[#chat])

-- the replay: no suggested column will come, and the hint says why
chat = {}
MD:OpenReplay("1")
local W = MD.Replay._state()
local hint = W.hint and T.Strip(W.hint:GetText() or "") or ""
check("replay: the hint says Coaching: not modelled for Mage yet, and nothing is coached",
    hint == "Coaching: not modelled for Mage yet" and MD.coachSearch == nil and MD.replayCoaching == nil, hint)
if W.frame then W.frame:Hide() end

-- practice
chat = {}
practice:Render()
local pstatus = TextShowing("Practice: not modelled for Mage yet")
check("practice: the panel says Practice: not modelled for Mage yet and Start is off",
    pstatus ~= nil and not Enabled(Button("Start practice")), pstatus)
MD:OpenPractice(MD.cdb.practiceSetup)
check("practice: starting one prints practice: not modelled for Mage yet.",
    Said("practice: not modelled for Mage yet.") ~= nil, chat[#chat])

if not forever then
    -- the simulator
    chat = {}
    MD:RefreshSimHeader()
    local header = TextShowing("(Simulation: not modelled for Mage yet)")
    check("sim: the header says (Simulation: not modelled for Mage yet)", header ~= nil, header)
    Click(Button("Run"))
    local result = TextShowing("Simulation: not modelled for Mage yet.")
    check("sim: Run says Simulation: not modelled for Mage yet.", result ~= nil, result)

    -- coachrun, the profile report, the summary's max-rank part
    chat = {}
    local realGet = MD.RunRecorder.Get
    MD.RunRecorder.Get = function() return { name = "x", pulls = {} } end
    MD:RunCoachRun("1")
    MD.RunRecorder.Get = realGet
    check("coachrun: prints coachrun: not modelled for Mage yet.",
        Said("coachrun: not modelled for Mage yet.") ~= nil and MD.runSearch == nil, chat[#chat])
    local report = table.concat(MD:Profile(), "\n")
    check("the profile report says (rank table: not modelled for Mage yet)",
        T.Has(report, "(rank table: not modelled for Mage yet)") and not T.Has(report, "druid-only"))
end

-- every word a mage was shown is ASCII with no bare pipe
do
    local bad
    for _, m in ipairs(chat) do
        local okA, why = T.Ascii(m)
        if not okA then bad = m .. ": " .. why end
    end
    check("what a mage is told is ASCII with no bare pipe", bad == nil, bad)
end

--------------------------------------------------------------------------------
-- 5. The druid again: today's words, nothing refused
--------------------------------------------------------------------------------
T.section("the druid sees today's")
LogIn("DRUID")
chat = {}
review:Render()
check("Review: Coach is on for the druid", Enabled(Button("Coach", review.frame)))
hover = CoachHover()
check("Review: Coach's hover carries no refusal", not T.Has(hover, "not modelled"), hover)
practice:Render()
local today = TextShowing("damage a second for you to heal")
check("practice: the panel's status is today's (no refusal), Start is on",
    today ~= nil and not T.Has(today, "not modelled") and Enabled(Button("Start practice")), today)
chat = {}
MD:OpenReplay("1")
W = MD.Replay._state()
hint = W.hint and T.Strip(W.hint:GetText() or "") or ""
check("replay: the druid's hint carries no refusal", not T.Has(hint, "not modelled"), hint)
Drain()
if W.frame then W.frame:Hide() end
if not forever then
    MD:RefreshSimHeader()
    local header = TextShowing("people, ")
    check("sim: the druid's header carries no refusal", header ~= nil and not T.Has(header, "not modelled"), header)
    local report = table.concat(MD:Profile(), "\n")
    check("the profile report lists the druid's max-rank costs, as today",
        T.Has(report, "--- costs of known max ranks ---") and not T.Has(report, "not modelled"))
end
check("nothing the druid was told says not modelled", (function()
    for _, m in ipairs(chat) do if m:find("not modelled", 1, true) then return false end end
    return true
end)())

T.done()
