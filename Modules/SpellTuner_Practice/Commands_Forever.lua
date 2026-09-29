-- T18 (docs/tasks/T18-practice-forever.md): the practice commands -- TBC's own
-- syntax and help text (Core_TBC.lua:339-350), reimplemented here rather than
-- pulled from that file (TBC-only, not on this TOC). Runs only once this
-- module is on -- this file is that module's own TOC entry.
local _, MD = ...

MD:AddCommand("practice", function(arg)
    -- "/st practice start" plays the saved setup at once (TBC's own v0.15.0
    -- shortcut); anything else opens Simulate -> Practice to build a fight.
    if arg == "start" and MD.OpenPractice and MD.Practice then
        MD.cdb.practiceSetup = MD.cdb.practiceSetup or MD.Practice.DefaultSetup("5")
        MD:OpenPractice(MD.Practice.CopySetup(MD.cdb.practiceSetup), MD.cdb.practiceSetup.fixedSeed)
    elseif MD.SelectView then
        if MD.ShowDashboard then MD:ShowDashboard() end
        MD:SelectView("simulate", "practice")
    end
end, "/st practice [start]", "set up and heal a practice fight; start plays the saved setup at once")

local function ToggleBindings(arg)
    -- T19: "/st binds check" writes one copy-box report of what the three import
    -- sources look like on this client; nothing is imported or stored
    if arg == "check" then
        if MD.Practice and MD.Practice.BindsReport and MD.ShowCopyPopup then
            MD:ShowCopyPopup("SpellTuner binds check", MD.Practice.BindsReport())
        end
        return
    end
    if MD.ToggleBindings then MD:ToggleBindings() end
end
MD:AddCommand("binds", ToggleBindings, "/st binds [check]",
    "what your keys and mouse buttons cast in practice; check writes a report of what the imports see")
MD:AddCommand("bindings", ToggleBindings, "/st bindings", "same as /st binds")
