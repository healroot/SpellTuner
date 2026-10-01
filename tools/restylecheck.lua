-- tools/run.sh --flavour forever|tbc tools/restylecheck.lua [--print]
--
-- T107 (docs/SPEC-next.md section 11's T107 row, 2.2; R-styles.md 1.3, 6):
-- the live restyle. A style switch (UI.SetStyle) rewrites the palette and the
-- tokens in place and repaints every UI.skinned region (T94); what it did not
-- reach was a colour COPIED out of a token when a region was made -- the ~36
-- creation-time accent reads and the panes' SetTextColor(UI.RGB(...)) sites.
-- This suite opens the window the way a player does and holds, on both lines:
--
--   * the source scan: the files T107 owns carry no creation-time accent read
--     and no colour copied out of a token into a setter -- each became
--     UI.Tint (a registered region) or a read at paint;
--   * UI.Tint / UI.Untint / UI.RepaintTints: a tinted region repaints from its
--     name on STYLE_CHANGED; a region painted by hand afterwards is left alone;
--   * Flat -> Ellesmere, every view re-visited: every visible region of the
--     window's chrome, the Spells view (Overview and a family), Review,
--     Practice and Settings that showed Flat's accent shows Ellesmere's, at the
--     same alpha -- none still shows Flat's; and no region shows a token's or
--     a fill's Flat value that Ellesmere changed, except what UI.Restyle.LEFT
--     declares (measured here region by region: the declaration is exact);
--   * UI.Restyle.Left() / Line(): what Settings' reload line counts -- 0 left
--     for the Spells view and Settings; each LEFT entry measured as left;
--   * Ellesmere -> Flat: every region is BYTE-IDENTICAL to the first paint;
--   * the follow (UI.FollowTokens) never enters a `restyleExempt` subtree, and
--     a colour two tokens shared that now differ is left alone.
--
-- The stub has no GetChildren / GetRegions / GetObjectType / GetTextColor (its
-- fallback answers nothing); this suite installs them on the stub's frame
-- metatable for itself, from the parent links every stub frame keeps, so the
-- follow walks what the client would hand it. No other suite sees them.
HARNESS_FLAVOUR = { "forever", "tbc" }

local here = arg[0]:match("^(.*)/[^/]+$")
local root = arg[1] or "."
local mode = "check"
for i = 2, #arg do if arg[i] == "--print" then mode = "print" end end

local flavour = os.getenv("ST_FLAVOUR")
if flavour == nil or flavour == "" then flavour = "forever" end
if flavour ~= "forever" and flavour ~= "tbc" then
    print("skip: restylecheck.lua runs under forever, tbc only")
    os.exit(3)
end

local T = dofile(here .. "/lib/t.lua")
local function check(name, cond, detail)
    if cond then detail = nil end
    return T.check(name, cond, detail)
end

dofile(here .. "/wowstub.lua")
local S = _G.STUB
S.root = root
S.flavour = flavour

--------------------------------------------------------------------------------
-- The stub, extended for this suite only: where each region was made (for a
-- failure's detail), and the four readers the follow walks with.
--------------------------------------------------------------------------------
local FrameMT = getmetatable(UIParent)
local function Site()
    for lvl = 3, 16 do
        local info = debug.getinfo(lvl, "Sl")
        if not info then break end
        local src = info.short_src or ""
        if not src:find("wowstub", 1, true) and not src:find("restylecheck", 1, true) and (info.currentline or 0) > 0 then
            return (src:match("([^/]+/[^/]+)$") or src) .. ":" .. tostring(info.currentline)
        end
    end
    return "?"
end
do
    local oFS, oTex, oCF = FrameMT.CreateFontString, FrameMT.CreateTexture, CreateFrame
    FrameMT.CreateFontString = function(self, ...) local c = oFS(self, ...); c.site = Site(); return c end
    FrameMT.CreateTexture = function(self, ...) local c = oTex(self, ...); c.site = Site(); return c end
    CreateFrame = function(...) local c = oCF(...); c.site = Site(); return c end
end
local REGION = { FontString = true, Texture = true }
local walked = 0
function FrameMT:GetObjectType() return self.kind end
function FrameMT:GetTextColor()
    local c = self.textColor
    if c then return c[1], c[2], c[3], 1 end
    return 1, 1, 1, 1
end
function FrameMT:GetChildren()
    walked = walked + 1
    local out = {}
    for _, f in ipairs(S.allFrames) do
        if rawget(f, "parentFrame") == self and not REGION[f.kind] then out[#out + 1] = f end
    end
    return unpack(out)
end
function FrameMT:GetRegions()
    local out = {}
    for _, f in ipairs(S.allFrames) do
        if rawget(f, "parentFrame") == self and REGION[f.kind] then out[#out + 1] = f end
    end
    return unpack(out)
end

--------------------------------------------------------------------------------
-- Load the flavour's whole TOC (UI included) and log in
--------------------------------------------------------------------------------
local MD = {}
local toc = "SpellTuner_TBC.toc"
if flavour == "forever" then
    S.UseProfile("forever")
    toc = "SpellTuner_Mainline.toc"
end
local files = S.TocFiles(toc)
S.loadedFiles = files
S.Load(files, "SpellTuner", MD)
local UI = MD.UI
if _G.GetBuildInfo == nil then
    _G.GetBuildInfo = function() return "2.5.5", "65000", "Sep 1 2026", 20506 end
end
local chat = {}
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = m end }
S.Fire("ADDON_LOADED", "SpellTuner")
S.Fire("PLAYER_LOGIN")
S.Fire("PLAYER_ENTERING_WORLD")
if flavour == "forever" then
    MD:SetModule("SpellTuner_Recorder", true)
    MD:SetModule("SpellTuner_Replay", true)
    MD:SetModule("SpellTuner_Practice", true)
end

--------------------------------------------------------------------------------
-- 1. The source scan
--------------------------------------------------------------------------------
T.section("the source scan: no colour copied out of a token in T107's files")

local OWNED = { "UI/Style.lua", "UI/Dashboard_Rows.lua", "UI/SpellsPane_Forever.lua", "UI/SpellsView_TBC.lua",
    "UI/SpellRail.lua", "UI/ReplayWindow.lua", "UI/Dashboard_Simulate.lua", "UI/Options_About.lua",
    "UI/DebugConsole.lua", "UI/Tip_TBC.lua" }
local function Code(rel)
    local fh = io.open(root .. "/" .. rel, "r")
    if not fh then return "" end
    local src = fh:read("*a")
    fh:close()
    src = src:gsub("%-%-%[(=*)%[.-%]%1%]", "")
    return (src:gsub("%-%-[^\n]*", ""))
end
-- A creation-time read is a colour taken out of the accent or a token and
-- handed to a setter (or kept in a table / local that a setter is given later).
local PATTERNS = {
    { "UI%.accent", "UI.accent read (outside the kit)" },
    { "Set%a*Colou?r%a*%(%s*accent%[", "setter given accent[i]" },
    { "Set%a*Colou?r%a*%(%s*a%[1%]", "setter given a captured accent" },
    { "{%s*accent%[1%]", "accent copied into a table" },
    { "Set%a*Colou?r%a*%(%s*UI%.RGB%(", "setter given UI.RGB(...)" },
    { "Set%a*Colou?r%a*%(%s*UI%.Fill%(", "setter given UI.Fill(...)" },
    { "Set%a*Colou?r%a*%(%s*MD%.UI%.Fill%(", "setter given UI.Fill(...)" },
    { "Set%a*Colou?r%a*%(%s*TextRGB%(", "setter given TextRGB(...)" },
    { "{%s*UI%.RGB%(", "a token copied into a table" },
    { "headerColor%s*=%s*UI%.Hex%(", "a code captured for a table header" },
}
-- the kit's own lines that read the accent at paint or define it
local KIT_OK = {
    ["UI/Style.lua"] = {
        "UI.classAccent = { accent[1], accent[2], accent[3] }",
        "hover     = { accent[1], accent[2], accent[3], 0.12 },",
        "selected  = { accent[1], accent[2], accent[3], 0.28 },",
        "suggested = { accent[1], accent[2], accent[3], 0.10 },",
        "thumb       = { accent[1], accent[2], accent[3], 0.8 },",
        "check       = { accent[1], accent[2], accent[3], 0.7 },",
        "checkHover  = { accent[1], accent[2], accent[3], 0.1 },",
        "accentFill  = { accent[1], accent[2], accent[3], 0.3 },",
        "accentHover = { accent[1], accent[2], accent[3], 0.6 },",
        "return { accent[1], accent[2], accent[3], spec.a or 1 }",
    },
}
local function Allowed(rel, line)
    for _, ok in ipairs(KIT_OK[rel] or {}) do
        if line:find(ok, 1, true) then return true end
    end
    return false
end
local found = {}
for _, rel in ipairs(OWNED) do
    local n = 0
    for line in (Code(rel) .. "\n"):gmatch("([^\n]*)\n") do
        for _, p in ipairs(PATTERNS) do
            if line:find(p[1]) and not Allowed(rel, line) then
                n = n + 1
                if mode == "print" then print(rel, p[2], (line:gsub("^%s+", ""))) end
                break
            end
        end
    end
    if n > 0 then found[#found + 1] = rel .. " x" .. n end
end
check("the ten files carry no creation-time colour read (each a UI.Tint or a read at paint)",
    #found == 0, table.concat(found, ", "))

--------------------------------------------------------------------------------
-- 2. The tint itself
--------------------------------------------------------------------------------
T.section("UI.Tint")
check("the kit has UI.Tint, UI.Untint, UI.RepaintTints, UI.FollowTokens and UI.Restyle",
    type(UI.Tint) == "function" and type(UI.Untint) == "function" and type(UI.RepaintTints) == "function"
    and type(UI.FollowTokens) == "function" and type(UI.Restyle) == "table"
    and type(UI.Restyle.Left) == "function" and type(UI.Restyle.Line) == "function")

local function Near(c, r, g, b, a)
    if type(c) ~= "table" then return false end
    local function eq(x, y) return math.abs((x or -1) - (y or -1)) < 1e-6 end
    return eq(c[1], r) and eq(c[2], g) and eq(c[3], b) and (a == nil or eq(c[4], a))
end
local probe = UIParent:CreateFontString()
local tex = UIParent:CreateTexture()
local hand = UIParent:CreateFontString()
if UI.Tint then
    UI.Tint(probe, "text", "muted")
    UI.Tint(tex, "texture", "hover")
    UI.Tint(hand, "text", "label")
    hand:SetTextColor(0.25, 0.5, 0.75) -- painted by hand after the tint
end
local m, h = UI.TEXT.muted, UI.PALETTE.hover
check("a text tint paints the token now (r, g, b only, as SetTextColor(UI.RGB()) did)",
    Near(probe.textColor, m[1], m[2], m[3]) and probe.textColor[4] == nil)
check("a texture tint paints the fill with its own alpha", Near(tex.color, h[1], h[2], h[3], h[4]))

--------------------------------------------------------------------------------
-- 3. The window, visited view by view under Flat
--------------------------------------------------------------------------------
local VIEWS
if flavour == "forever" then
    VIEWS = {
        { "spells", "overview", "spells" }, { "spells", "FAMILY", "spells" },
        { "reports", "review", "review" }, { "simulate", "practice", "practice" },
        { "settings", "general", "settings" }, { "settings", "modules", "settings" },
        { "settings", "about", "settings" },
    }
else
    VIEWS = {
        { "spells", "overview", "spells" }, { "spells", "FAMILY", "spells" },
        { "reports", "Review", "review" }, { "reports", "Waste", "waste" },
        { "simulate", "practice", "practice" }, { "simulate", "build", "simulate" },
        { "settings", "general", "settings" }, { "settings", "about", "settings" },
    }
end
local LISTED = { spells = true, review = true, practice = true, settings = true }

local dash
local function FamilyRow()
    for _, f in ipairs(S.allFrames) do
        local d = rawget(f, "data")
        if f.kind == "Button" and type(d) == "table" and d.text and rawget(f, "id") and not d.fixed
                and type(f.id) == "string" and f.id ~= "overview" and f:IsVisible() then
            return f
        end
    end
end
local function Visit(v)
    if v[2] == "FAMILY" then
        MD:SelectView("spells", "overview")
        local row = FamilyRow()
        local fn = row and row:GetScript("OnClick")
        if fn then fn(row, "LeftButton") end
        return row ~= nil
    end
    local ok, err = pcall(MD.SelectView, MD, v[1], v[2])
    if not ok then print("  select " .. v[1] .. "/" .. tostring(v[2]) .. " raised: " .. tostring(err)) end
    return ok
end
local function Visible()
    local out = {}
    dash = dash or _G.SpellTunerDashboard
    for _, f in ipairs(S.allFrames) do
        if REGION[f.kind] or f.bg or f.border then
            local g, under = f, false
            for _ = 1, 60 do
                if not g then break end
                if rawequal(g, dash) then under = true; break end
                g = rawget(g, "parentFrame")
            end
            if under and f:IsVisible() then out[f] = true end
        end
    end
    return out
end
local function Round()
    local seen = {}
    for i, v in ipairs(VIEWS) do
        local ok = Visit(v)
        seen[i] = ok and Visible() or {}
    end
    return seen
end

MD:ToggleDashboard()
-- twice: a pane's second render settles what its first left (pooled rows,
-- a selection the first visit made), so the paint below is the steady one
Round()
local flatSeen = Round()
-- the chrome: what every view shows
local chrome = {}
for f in pairs(flatSeen[1]) do
    local all = true
    for i = 2, #flatSeen do if not flatSeen[i][f] then all = false; break end end
    if all then chrome[f] = true end
end

-- the first paint, region by region
local function N(v) if type(v) == "number" then return string.format("%.6g", v) end return tostring(v) end
local function C(c)
    if type(c) ~= "table" then return tostring(c) end
    return N(c[1]) .. "," .. N(c[2]) .. "," .. N(c[3]) .. "," .. N(c[4])
end
local function Paint(f)
    return table.concat({ tostring(f.kind), "bg=" .. C(f.bg), "edge=" .. C(f.border), "tex=" .. C(f.color),
        "text=" .. C(f.textColor), "bar=" .. C(f.barColor), "t=" .. tostring(f.text) }, " ")
end
local builtBefore = #S.allFrames
local first = {}
for i = 1, builtBefore do first[i] = Paint(S.allFrames[i]) end

-- Flat's values, and which Ellesmere changes
local function Copy3(t) return { t[1], t[2], t[3], t[4], hex = t.hex } end
local flatAccent = Copy3(UI.accent)
local flatText, flatPal = {}, {}
for k, t in pairs(UI.TEXT) do flatText[k] = Copy3(t) end
for k, c in pairs(UI.PALETTE) do flatPal[k] = Copy3(c) end

--------------------------------------------------------------------------------
-- 4. Flat -> Ellesmere
--------------------------------------------------------------------------------
T.section("Flat -> Ellesmere: every view follows")
local repaints, follows = 0, 0
if UI.RepaintTints then
    local r0, f0 = UI.RepaintTints, UI.FollowTokens
    UI.RepaintTints = function(...) local n = r0(...); repaints = repaints + (n or 0); return n end
    UI.FollowTokens = function(...) local n = f0(...); follows = follows + (n or 0); return n end
end
local okSwitch = UI.SetStyle("ellesmere")
check("the Ellesmere style applies", okSwitch == true and UI.STYLE == "ellesmere")
local E = Copy3(UI.accent)
check("Ellesmere's accent is not Flat's (the suite can tell them apart)",
    not Near(E, flatAccent[1], flatAccent[2], flatAccent[3]))
check("the hand-painted region is left as the hand painted it; the tinted ones follow",
    Near(hand.textColor, 0.25, 0.5, 0.75) and Near(probe.textColor, UI.TEXT.muted[1], UI.TEXT.muted[2], UI.TEXT.muted[3])
    and Near(tex.color, UI.PALETTE.hover[1], UI.PALETTE.hover[2], UI.PALETTE.hover[3], UI.PALETTE.hover[4]))

local function Key(r, g, b) return string.format("%.4f %.4f %.4f", r or -1, g or -1, b or -1) end
local staleText, staleHex, stalePal = {}, {}, {}
for k, o in pairs(flatText) do
    local n = UI.TEXT[k]
    if Key(o[1], o[2], o[3]) ~= Key(n[1], n[2], n[3]) then staleText[Key(o[1], o[2], o[3])] = k end
    if o.hex and n.hex and o.hex:lower() ~= n.hex:lower() then staleHex[o.hex:lower()] = k end
end
for k, o in pairs(flatPal) do
    local n = UI.PALETTE[k]
    local ok_ = Key(o[1], o[2], o[3]) .. " " .. N(o[4] or 1)
    if ok_ ~= Key(n[1], n[2], n[3]) .. " " .. N(n[4] or 1) then stalePal[ok_] = k end
end
local accentKey = Key(flatAccent[1], flatAccent[2], flatAccent[3])

-- what a region still shows of Flat: "accent", or the token / fill it was
local function Stale(f)
    local hits = {}
    local function rgb(c, what)
        if type(c) ~= "table" then return end
        local k = Key(c[1], c[2], c[3])
        if k == accentKey then hits[#hits + 1] = what .. "=accent" ; return end
        if what == "text" and staleText[k] then hits[#hits + 1] = "text=" .. staleText[k]; return end
        if what ~= "text" then
            local kp = k .. " " .. N(c[4] or 1)
            if stalePal[kp] then hits[#hits + 1] = what .. "=" .. stalePal[kp] end
        end
    end
    rgb(f.textColor, "text"); rgb(f.color, "tex"); rgb(f.bg, "bg"); rgb(f.border, "edge"); rgb(f.barColor, "bar")
    if type(f.text) == "string" then
        for code in f.text:gmatch("|c%x%x%x%x%x%x%x%x") do
            local c = code:lower()
            if c == tostring(flatText.accent.hex):lower() then hits[#hits + 1] = "code=accent"
            elseif staleHex[c] then hits[#hits + 1] = "code=" .. staleHex[c] end
        end
    end
    return hits
end
local function IsAccent(h) return h:find("accent", 1, true) ~= nil end

local elSeen = Round()
-- per pane: the stale regions, accent and the rest
local paneOf = {}
local accentLeft, leftBy = {}, {}
for i, v in ipairs(VIEWS) do
    local pane = v[3]
    for f in pairs(elSeen[i]) do
        local where = chrome[f] and "window" or pane
        local hits = Stale(f)
        for _, h in ipairs(hits) do
            local site = (f.site or "?")
            if IsAccent(h) then
                accentLeft[where] = accentLeft[where] or {}
                accentLeft[where][site .. " " .. h] = true
            else
                leftBy[where] = leftBy[where] or {}
                leftBy[where][site .. " " .. h] = true
            end
        end
    end
end
local function Keys(t)
    local out = {}
    for k in pairs(t or {}) do out[#out + 1] = k end
    table.sort(out)
    return out
end
if mode == "print" then
    for _, w in ipairs(Keys(accentLeft)) do for _, k in ipairs(Keys(accentLeft[w])) do print("ACCENT", w, k) end end
    for _, w in ipairs(Keys(leftBy)) do for _, k in ipairs(Keys(leftBy[w])) do print("LEFT", w, k) end end
end

-- every region that showed Flat's accent shows Ellesmere's, at its alpha
local function AccentFollowed(i, pane)
    local bad = {}
    for f in pairs(flatSeen[i]) do
        local idx
        for j = 1, builtBefore do if S.allFrames[j] == f then idx = j; break end end
        if idx and elSeen[i][f] then
            local before = first[idx]
            local function was(c) return type(c) == "table" and Key(c[1], c[2], c[3]) == accentKey end
            -- the paint before is a string; read the colour fields again from it
            for _, field in ipairs({ "textColor", "color", "bg", "border", "barColor" }) do
                local now = f[field]
                local tag = ({ textColor = "text=", color = "tex=", bg = "bg=", border = "edge=", barColor = "bar=" })[field]
                local was_ = before:match(tag .. "([^ ]+)")
                if was_ and was_:find("^" .. N(flatAccent[1]):gsub("%.", "%%.") .. "," .. N(flatAccent[2]):gsub("%.", "%%.")
                        .. "," .. N(flatAccent[3]):gsub("%.", "%%.") .. ",") then
                    local alpha = was_:match(",([^,]+)$")
                    if not (Near(now, E[1], E[2], E[3]) and N(now and now[4]) == alpha) then
                        bad[#bad + 1] = (f.site or "?") .. " " .. field
                    end
                end
            end
            local _ = was
        end
    end
    return bad
end

local checkedPanes = {}
for i, v in ipairs(VIEWS) do
    local pane = v[3]
    if not checkedPanes[pane] and pane ~= "window" then
        checkedPanes[pane] = true
        local bad = {}
        for j, w in ipairs(VIEWS) do
            if w[3] == pane then for _, b in ipairs(AccentFollowed(j, pane)) do bad[#bad + 1] = w[2] .. ": " .. b end end
        end
        for _, k in ipairs(Keys(accentLeft[pane])) do bad[#bad + 1] = k end
        check(string.format("%s: every region in Flat's accent now reads Ellesmere's (same alpha)", pane),
            #bad == 0, table.concat(bad, "; "))
    end
end
check("the window's own chrome follows too (nav, tabs, rules)", accentLeft.window == nil,
    table.concat(Keys(accentLeft.window), "; "))

--------------------------------------------------------------------------------
-- 5. What is left, and the reload line
--------------------------------------------------------------------------------
T.section("what is left: UI.Restyle.LEFT, measured")
local Restyle = UI.Restyle or {}
local declared = {}
for _, e in ipairs(Restyle.LEFT or {}) do
    declared[e.pane] = declared[e.pane] or {}
    for _, s in ipairs(e.sites or {}) do declared[e.pane][s] = true end
end
for _, pane in ipairs({ "window", "spells", "review", "practice", "settings", "waste", "simulate" }) do
    local measured = {}
    for k in pairs(leftBy[pane] or {}) do measured[k:match("^(%S+)")] = true end
    local missing, extra = {}, {}
    for s in pairs(measured) do if not (declared[pane] or {})[s] then missing[#missing + 1] = s end end
    for s in pairs(declared[pane] or {}) do if not measured[s] then extra[#extra + 1] = s end end
    table.sort(missing); table.sort(extra)
    if pane == "spells" or pane == "settings" or pane == "window" then
        check(pane .. ": nothing left (no token or fill of Flat's on any region)",
            next(measured) == nil and declared[pane] == nil, table.concat(Keys(leftBy[pane]), "; "))
    elseif VIEWS and (pane ~= "waste" and pane ~= "simulate" or flavour == "tbc") then
        check(pane .. ": what is left is exactly what UI.Restyle.LEFT declares",
            #missing == 0 and #extra == 0,
            (#missing > 0 and ("not declared: " .. table.concat(missing, ", ") .. " ") or "")
            .. (#extra > 0 and ("declared but not left: " .. table.concat(extra, ", ")) or ""))
    end
end
do
    local n, labels = 0, {}
    if Restyle.Left then n, labels = Restyle.Left() end
    local named = {}
    for _, l in ipairs(labels or {}) do named[l] = true end
    local listedLeft = {}
    for _, e in ipairs(Restyle.LEFT or {}) do
        if (e.pane == "spells" or e.pane == "settings") then listedLeft[#listedLeft + 1] = e.label end
    end
    check("UI.Restyle.Left() counts the LEFT entries by label; none is the Spells view or Settings",
        Restyle.Left ~= nil and n == #(Restyle.LEFT or {}) and #listedLeft == 0,
        tostring(n) .. " " .. table.concat(listedLeft, ", "))
    local line = Restyle.Line and Restyle.Line()
    local okLine = (n == 0 and line == nil) or (type(line) == "string" and T.Ascii(line)
        and line:find(tostring(n), 1, true) ~= nil and line:find("reload", 1, true) ~= nil)
    check("UI.Restyle.Line(): the count and the word reload, ASCII (nil when nothing is left)",
        okLine, tostring(line))
end

--------------------------------------------------------------------------------
-- 6. The follow: exempt subtrees and shared colours
--------------------------------------------------------------------------------
T.section("the follow")
check("STYLE_CHANGED repainted tinted regions and the follow moved untinted font strings",
    repaints > 0 and follows > 0 and walked > 0,
    string.format("repainted %d, followed %d, walked %d", repaints, follows, walked))
local host = CreateFrame("Frame", "STRestyleHost", UIParent, "BackdropTemplate")
UI.StylizeFrame(host)
local free = host:CreateFontString()
free:SetTextColor(UI.RGB("muted"))
free:SetText(UI.Hex("muted") .. "hint|r")
local exempt = CreateFrame("Frame", nil, host)
exempt.restyleExempt = true
local kept = exempt:CreateFontString()
kept:SetTextColor(UI.RGB("muted"))
kept:SetText(UI.Hex("muted") .. "legend|r")
local mutedNow = Copy3(UI.TEXT.muted)
UI.SetStyle("flat")
check("an untinted font string in a SpellTuner window follows its token, colour and code",
    Near(free.textColor, UI.TEXT.muted[1], UI.TEXT.muted[2], UI.TEXT.muted[3])
    and free.text == UI.Hex("muted") .. "hint|r", C(free.textColor) .. " " .. tostring(free.text))
check("a restyleExempt subtree is never entered",
    Near(kept.textColor, mutedNow[1], mutedNow[2], mutedNow[3]) and kept.text:find(mutedNow.hex, 1, true) ~= nil)

--------------------------------------------------------------------------------
-- 7. Ellesmere -> Flat: byte-identical
--------------------------------------------------------------------------------
T.section("Ellesmere -> Flat: byte-identical")
Round()
local diff = {}
for i = 1, builtBefore do
    local p = Paint(S.allFrames[i])
    if p ~= first[i] and S.allFrames[i] ~= probe and S.allFrames[i] ~= tex and S.allFrames[i] ~= hand then
        diff[#diff + 1] = (S.allFrames[i].site or "?") .. ": " .. first[i] .. " -> " .. p
        if mode == "print" then print("DIFF", diff[#diff]) end
    end
end
check("every region the window had is byte-identical to the first Flat paint",
    #diff == 0, #diff .. " differ, first: " .. tostring(diff[1]))

T.done()
