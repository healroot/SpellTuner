-- /st dump (T3): one copyable block for a bug report -- the client and build
-- (with every line another file added through ST:AddDumpLine, T113),
-- then the SavedVariables line, the modules and their states, every distinct error
-- with its count and first stack line, one capabilities summary (what is
-- absent, what is forbidden), then the adapter's whole capability table and
-- the newest debug-log lines (T73, P29, review U19: that order). Forever only (UI/Dashboard_Forever.lua and
-- Core_Forever.lua are its siblings); TBC never loads this file.
local _, ST = ...

local DEBUG_LOG_LINES = 50

-- Reversible ASCII escaping, Client/Probe.lua's rule (\ -> \\, | -> ||, then
-- every byte outside the printable range -> \ddd). Its one copy is
-- ST.Text.EscASCII in Core.lua (T60, P16, review A9); every caller below hands
-- it a string.
local Esc = ST.Text.EscASCII

-- A client scalar that survived ST.API.Call (already secret-filtered) as
-- readable text, or "?" for anything else -- never a raw table.
local function Field(v)
    if type(v) == "string" or type(v) == "number" then return Esc(tostring(v)) end
    return "?"
end

-- The Modules pane's state text, ST:ModuleStateText (Core.lua, T55; this
-- file's own copy moved there in T60, P16, review A9) -- ASCII already, since
-- Core.lua's own CleanReason only ever hands back "[A-Z_]+" or "unknown".
local function ModuleStateText(name) return ST:ModuleStateText(name) end

function ST:BuildDump()
    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    add(string.format("SpellTuner dump %s -- %s", tostring(ST.version), date("%Y-%m-%d %H:%M:%S")))

    -----------------------------------------------------------------------
    add("== client")
    local version, build, _, iface = ST.API.BuildInfo()
    add(string.format("client: %s, build %s %s, interface %s, toc %s",
        Field(ST.API.client), Field(version), Field(build), Field(iface),
        Field(rawget(_G, "SPELLTUNER_TOC"))))
    add(string.format("character: %s level %s %s",
        Field(ST.player and ST.player.class), Field(ST.player and ST.player.level),
        Field(ST.player and ST.player.charKey)))
    -- T113 (docs/SPEC-next.md 2.5): the lines other files registered with
    -- ST:AddDumpLine, in registration order, each escaped to one ASCII line.
    -- A provider that raises costs its own line, never the dump. None
    -- registered: nothing added.
    for _, d in ipairs(ST.DumpLines and ST:DumpLines() or {}) do
        local okLine, line = pcall(d.fn)
        if not okLine then
            add(Esc(d.key .. ": error " .. tostring(line)))
        elseif type(line) == "string" or type(line) == "number" then
            add(Esc(tostring(line)))
        else
            add(Esc(d.key .. ": no line"))
        end
    end

    -----------------------------------------------------------------------
    -- T73 (P29, review U19): what a bug report is read for comes first --
    -- the saved variables, the modules, the errors -- then one summary of the
    -- capabilities, and the long tables (every binding, the debug log) last.
    add("== saved variables")
    add(ST.SavedVarsLine and ST:SavedVarsLine() or "SavedVariables: unknown")

    -----------------------------------------------------------------------
    add("== modules")
    for _, m in ipairs(ST.modules or {}) do
        add(string.format("%s: %s", Field(m.label), ModuleStateText(m.name)))
    end

    -----------------------------------------------------------------------
    local errs = ST.errors or {}
    local overflow = tonumber(ST.errorOverflow) or 0
    if overflow > 0 then
        add(string.format("== errors (%d distinct, %d total, %d more not kept)", #errs, tonumber(ST.errorTotal) or 0, overflow))
    else
        add(string.format("== errors (%d distinct, %d total)", #errs, tonumber(ST.errorTotal) or 0))
    end
    if ST.errorHandlerInstalled == true then
        add("error handler: installed")
    else
        add("error handler: not installed (" .. Field(ST.errorHandlerInstalled or "unknown") .. ")")
    end
    for _, e in ipairs(errs) do
        add(string.format("%dx %s", tonumber(e.count) or 0, Esc(e.msg or "")))
        if e.stack then
            add("  at " .. Esc(e.stack))
        end
    end

    -----------------------------------------------------------------------
    -- one summary: the counts, the absent names, the forbidden events
    local caps = ST.API.Capabilities()
    local absent = {}
    for _, c in ipairs(caps) do
        if not c.present then absent[#absent + 1] = Field(c.client) end
    end
    add(string.format("== capabilities (%d bindings, %d absent)", #caps, #absent))
    add("absent: " .. (#absent > 0 and table.concat(absent, ", ") or "none"))

    local forbidden = {}
    for event in pairs(ST.API._forbidden or {}) do forbidden[#forbidden + 1] = Field(event) end
    table.sort(forbidden)
    add("forbidden events: " .. (#forbidden > 0 and table.concat(forbidden, ", ") or "none"))

    -----------------------------------------------------------------------
    add(string.format("== capability table (%d)", #caps))
    for _, c in ipairs(caps) do
        add(string.format("%s %s (%s)", c.present and "present" or "absent", Field(c.client), Field(c.name)))
    end

    -----------------------------------------------------------------------
    local tail, total = {}, 0
    if ST.DebugLogTail then tail, total = ST:DebugLogTail(DEBUG_LOG_LINES) end
    add(string.format("== debug log (newest %d of %d lines)", #tail, total))
    for _, l in ipairs(tail) do
        add(Esc(l))
    end

    return table.concat(lines, "\n")
end
