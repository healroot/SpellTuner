-- /st dump (T3): one copyable block for a bug report -- the client and build,
-- the adapter's capability table, the SavedVariables line, the modules and
-- their states, every distinct error with its count and first stack line, and
-- the newest debug-log lines. Forever only (UI/Dashboard_Forever.lua and
-- Core_Forever.lua are its siblings); TBC never loads this file.
local _, MD = ...

local DEBUG_LOG_LINES = 50

-- Reversible ASCII escaping, Client/Probe.lua's rule (\ -> \\, | -> ||, then
-- every byte outside the printable range -> \ddd). Its one copy is
-- MD.Text.EscASCII in Core.lua (T60, P16, review A9); every caller below hands
-- it a string.
local Esc = MD.Text.EscASCII

-- A client scalar that survived MD.API.Call (already secret-filtered) as
-- readable text, or "?" for anything else -- never a raw table.
local function Field(v)
    if type(v) == "string" or type(v) == "number" then return Esc(tostring(v)) end
    return "?"
end

-- The Modules pane's state text, MD:ModuleStateText (Core.lua, T55; this
-- file's own copy moved there in T60, P16, review A9) -- ASCII already, since
-- Core.lua's own CleanReason only ever hands back "[A-Z_]+" or "unknown".
local function ModuleStateText(name) return MD:ModuleStateText(name) end

function MD:BuildDump()
    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    add(string.format("SpellTuner dump %s -- %s", tostring(MD.version), date("%Y-%m-%d %H:%M:%S")))

    -----------------------------------------------------------------------
    add("== client")
    local version, build, _, iface = MD.API.BuildInfo()
    add(string.format("client: %s, build %s %s, interface %s, toc %s",
        Field(MD.API.client), Field(version), Field(build), Field(iface),
        Field(rawget(_G, "SPELLTUNER_TOC"))))
    add(string.format("character: %s level %s %s",
        Field(MD.player and MD.player.class), Field(MD.player and MD.player.level),
        Field(MD.player and MD.player.charKey)))

    -----------------------------------------------------------------------
    local caps = MD.API.Capabilities()
    local absent = 0
    for _, c in ipairs(caps) do
        if not c.present then absent = absent + 1 end
    end
    add(string.format("== capabilities (%d bindings, %d absent)", #caps, absent))
    for _, c in ipairs(caps) do
        add(string.format("%s %s (%s)", c.present and "present" or "absent", Field(c.client), Field(c.name)))
    end

    local forbidden = {}
    for event in pairs(MD.API._forbidden or {}) do forbidden[#forbidden + 1] = Field(event) end
    table.sort(forbidden)
    add("forbidden events: " .. (#forbidden > 0 and table.concat(forbidden, ", ") or "none"))

    if MD.errorHandlerInstalled == true then
        add("error handler: installed")
    else
        add("error handler: not installed (" .. Field(MD.errorHandlerInstalled or "unknown") .. ")")
    end

    -----------------------------------------------------------------------
    add("== saved variables")
    add(MD.SavedVarsLine and MD:SavedVarsLine() or "SavedVariables: unknown")

    -----------------------------------------------------------------------
    add("== modules")
    for _, m in ipairs(MD.modules or {}) do
        add(string.format("%s: %s", Field(m.label), ModuleStateText(m.name)))
    end

    -----------------------------------------------------------------------
    local errs = MD.errors or {}
    local overflow = tonumber(MD.errorOverflow) or 0
    if overflow > 0 then
        add(string.format("== errors (%d distinct, %d total, %d more not kept)", #errs, tonumber(MD.errorTotal) or 0, overflow))
    else
        add(string.format("== errors (%d distinct, %d total)", #errs, tonumber(MD.errorTotal) or 0))
    end
    for _, e in ipairs(errs) do
        add(string.format("%dx %s", tonumber(e.count) or 0, Esc(e.msg or "")))
        if e.stack then
            add("  at " .. Esc(e.stack))
        end
    end

    -----------------------------------------------------------------------
    local tail, total = {}, 0
    if MD.DebugLogTail then tail, total = MD:DebugLogTail(DEBUG_LOG_LINES) end
    add(string.format("== debug log (newest %d of %d lines)", #tail, total))
    for _, l in ipairs(tail) do
        add(Esc(l))
    end

    return table.concat(lines, "\n")
end
