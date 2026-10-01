-- The ESC stack (docs/SPEC-forever-ui.md 6.5; T33, moved out of the window
-- manager by T80 / C1 of docs/PLAN-refactor-ux.md, review A22): MD.EscStack.
-- Listed by every main TOC after UI/Theme_Flat.lua and before UI/Windows.lua,
-- which hands its windows to it and exposes its calls on MD.Win (Push,
-- Remove, Prune, OnEsc, CloseLists, TopWindow, EscStackOn, SetEscStack,
-- EscLine, .stack, .proxy) for the files that already call them there.
--
-- WoW's CloseSpecialWindows hides EVERY shown frame named in UISpecialFrames
-- in one press, which is why one ESC used to close everything. So one
-- invisible proxy, SpellTunerEscProxy, is the only SpellTuner frame named
-- there; it is shown while the stack holds an entry. The client's ESC hides
-- it; its OnHide runs the top entry's onEsc (default: hide that frame) and
-- re-shows the proxy on the next frame when entries remain. Every pushed
-- frame's OnHide removes its entry, however it hides; the stack emptied by
-- code hides the proxy quietly. db.ui.escStack = false is the fallback: each
-- window's own UISpecialFrames entry, one ESC closing them all.
--
-- The dropdown lists join the stack through the kit's UI_POPUP event (T77,
-- P33, review A31: the kit announces, the stack subscribes).
--
-- No client data is read here: UISpecialFrames and frame visibility are the
-- widget toolkit (CLAUDE.md); the next-frame re-arm goes through MD.API.After.
local _, MD = ...

local Esc = { stack = {} }
MD.EscStack = Esc

-- T80 (C1): the default lives with the file that reads it (MD:RegisterDefaults,
-- T55), so every line that lists the stack has it -- TBC included.
MD:RegisterDefaults({ ui = { escStack = true } })

local function UIdb()
    local db = MD.db
    if type(db) ~= "table" then return nil end
    if type(db.ui) ~= "table" then db.ui = {} end
    return db.ui
end

local hooked = setmetatable({}, { __mode = "k" })     -- frames whose OnHide we hooked
local popups = setmetatable({}, { __mode = "k" })     -- open dropdown lists (UI_POPUP)
local special = {}                                    -- names the fallback put in UISpecialFrames

function Esc:On()
    local u = UIdb()
    return not (u and u.escStack == false)
end

local function FrameName(f)
    local n = f.GetName and f:GetName()
    if type(n) == "string" and n ~= "" then return n end
    return nil
end

local function AddSpecial(name)
    if not name or special[name] then return end
    special[name] = true
    tinsert(UISpecialFrames, name)
end

local function DropSpecials()
    for i = #UISpecialFrames, 1, -1 do
        if special[UISpecialFrames[i]] then table.remove(UISpecialFrames, i) end
    end
    for name in pairs(special) do special[name] = nil end
end

-- Shown, and every parent up to UIParent shown: a list whose window hid is not
-- on screen even if nobody told the stack (UIParent itself is not asked, so
-- Alt+Z hiding the interface does not empty the stack).
local function OnScreen(f)
    local guard = 0
    while f and f ~= UIParent and guard < 50 do
        if not f:IsShown() then return false end
        f = f.GetParent and f:GetParent()
        guard = guard + 1
    end
    return true
end

local proxy = CreateFrame("Frame", "SpellTunerEscProxy", UIParent)
proxy:Hide()
Esc.proxy = proxy
tinsert(UISpecialFrames, "SpellTunerEscProxy")

local function Arm()
    if not proxy:IsShown() then proxy:Show() end
end

-- The stack emptied by code: the proxy goes down quietly, so its OnHide pops
-- nothing (only a hide that ESC caused may).
local function Disarm()
    if proxy:IsShown() then
        proxy.quiet = true
        proxy:Hide()
        proxy.quiet = nil -- a client that skipped OnHide leaves no stale flag
    end
end

local function RemoveEntry(entry)
    for i = #Esc.stack, 1, -1 do
        if Esc.stack[i] == entry then table.remove(Esc.stack, i) end
    end
end

-- What one ESC press did, for /st probe's esc= line (6.5: UNVERIFIED on
-- Forever whether a special frame can re-show itself from its own OnHide in
-- the next frame). Kept in db.ui.escTest, so a /reload does not lose it.
local function RecordPress(rec)
    local u = UIdb()
    if not u then return end
    local closed = rec.before - rec.after
    if closed < 0 then closed = 0 end
    local result
    if closed > 1 then
        result = "all"
    elseif rec.after > 0 and not rec.rearmed then
        result = "stuck"
    else
        result = "stack"
    end
    u.escTest = { result = result, before = rec.before, after = rec.after, rearmed = rec.rearmed }
end

-- After a press: the proxy shown again on the next frame while entries remain.
local function Rearm(rec)
    MD.API.After(0, function()
        if #Esc.stack > 0 then Arm() end
        rec.after = #Esc.stack
        rec.rearmed = (#Esc.stack == 0) or proxy:IsShown()
        RecordPress(rec)
    end)
end

-- One ESC: the client hid the proxy. The top entry leaves the stack first (an
-- onEsc that raises cannot wedge it), the re-arm is scheduled, then its onEsc
-- runs -- default: hide the frame. An onEsc that returns true stays on top.
function Esc:OnEsc()
    self:Prune()
    local rec = { before = #self.stack }
    local e = self.stack[#self.stack]
    Rearm(rec)
    if not e then return end
    table.remove(self.stack)
    local keep
    if e.onEsc then
        keep = e.onEsc(e.frame)
    else
        e.frame:Hide()
    end
    if keep == true and OnScreen(e.frame) then
        RemoveEntry(e)
        self.stack[#self.stack + 1] = e
    end
end

-- Still shown after an OnHide: UIParent hid (Alt+Z, a loading screen), not
-- ESC -- the proxy's IsShown is false only when it was hidden itself. Through
-- MD.Win when it is there, so a suite that wraps Win:OnEsc sees the press.
proxy:SetScript("OnHide", function(self)
    if self.quiet then self.quiet = nil; return end
    if self:IsShown() then return end
    if MD.Win and MD.Win.OnEsc then MD.Win:OnEsc() else Esc:OnEsc() end
end)

-- Every entry whose frame is no longer on screen dropped (a list whose window
-- hid, where the client did not say so to the list); the proxy down when
-- nothing is left.
function Esc:Prune()
    for i = #self.stack, 1, -1 do
        local e = self.stack[i]
        if not OnScreen(e.frame) then table.remove(self.stack, i) end
    end
    if #self.stack == 0 then Disarm() end
end

-- A frame's every entry off the stack (and whatever else left the screen).
function Esc:Remove(frame)
    for i = #self.stack, 1, -1 do
        if self.stack[i].frame == frame then table.remove(self.stack, i) end
    end
    self:Prune()
end

-- A frame shown: on top of the stack, its OnHide hooked once so every close
-- (the x, a combat hide, a takeover, a parent hiding it) takes it off. With
-- the stack off, its name goes into UISpecialFrames instead.
function Esc:Push(frame, onEsc)
    if not frame then return end
    if not self:On() then
        AddSpecial(FrameName(frame))
        return
    end
    if not hooked[frame] then
        hooked[frame] = true
        -- a frame still shown in its own OnHide only lost its parent (UIParent
        -- under Alt+Z keeps it on the stack; a hidden window drops its lists)
        frame:HookScript("OnHide", function(f)
            if f:IsShown() then Esc:Prune() else Esc:Remove(f) end
        end)
    end
    for i = #self.stack, 1, -1 do
        if self.stack[i].frame == frame then table.remove(self.stack, i) end
    end
    self.stack[#self.stack + 1] = { frame = frame, onEsc = onEsc }
    Arm()
end

MD:RegisterCallback("UI_POPUP", function(list, shown)
    if not list then return end
    if shown then
        popups[list] = true
        Esc:Push(list)
    else
        popups[list] = nil
        Esc:Remove(list)
    end
end)

-- Every open list closed (the copy box opening, 6.2).
function Esc:CloseLists()
    local open = {}
    for list in pairs(popups) do open[#open + 1] = list end
    for _, list in ipairs(open) do list:Hide() end
end

-- The frame the copy box centres on: the newest window on the stack that is
-- not a list; nil = the screen.
function Esc:TopWindow(exclude)
    for i = #self.stack, 1, -1 do
        local f = self.stack[i].frame
        if f ~= exclude and not popups[f] and OnScreen(f) then return f end
    end
    return nil
end

-- db.ui.escStack (Settings -> General): on, the stack; off, one
-- UISpecialFrames entry per window. Either way what is open now carries over:
-- `shown` is the windows the caller (the manager) has open, as
-- { frame, onEsc } entries, pushed when the stack comes back on.
function Esc:Set(on, shown)
    local u = UIdb()
    if not u then return end
    on = on and true or false
    if on == self:On() and u.escStack ~= nil then return end
    if on then
        u.escStack = true
        DropSpecials()
        for _, e in ipairs(shown or {}) do self:Push(e.frame, e.onEsc) end
    else
        local open = {}
        for _, e in ipairs(self.stack) do open[#open + 1] = e.frame end
        u.escStack = false
        for i = #self.stack, 1, -1 do self.stack[i] = nil end
        Disarm()
        for _, f in ipairs(open) do AddSpecial(FrameName(f)) end
    end
end

-- /st probe's line (6.5): what the last ESC press did.
function Esc:Line()
    if not self:On() then
        return "esc=off (one UISpecialFrames entry per window: Settings -> General)"
    end
    local u = UIdb()
    local t = u and u.escTest
    if type(t) ~= "table" or type(t.result) ~= "string" or type(t.before) ~= "number"
        or type(t.after) ~= "number" then
        return "esc=untested"
    end
    local closed = t.before - t.after
    if closed < 0 then closed = 0 end
    local tail
    if t.after == 0 then
        tail = "nothing left open"
    elseif t.rearmed then
        tail = "the proxy shown again"
    else
        tail = "the proxy NOT shown again"
    end
    return string.format("esc=%s (last press: %d open, %d closed, %s)", t.result, t.before, closed, tail)
end
