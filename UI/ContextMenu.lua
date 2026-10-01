-- A right-click menu (T71, P27, review U22; docs/mockups/refactor-ux.html M2):
-- a title line and a column of items, in the dropdown lists' look -- the
-- `header` fill, a 1-px edge, 18-px rows, the lists' strata (UI.LIST_STRATA,
-- DIALOG when unset) -- and announced to the window manager's popup hook
-- (UI.OnPopup), so ESC closes the menu first and only the menu.
--
-- A file of its own, both main TOCs, so the menu needs no change to
-- UI/Style.lua (one file the kit tasks queue on). Reads no client data;
-- nothing in it branches on a flavour.
--
-- UI.CreateContextMenu(parent, width) -> menu   (hidden)
--   menu:Open(anchor, title, items)  shows it at the pointer (under
--       `anchor`'s bottom left when there is no cursor to read), relabelled; items = { { text = ..., note = ..., disabled = bool,
--       onClick = fn, tooltip = ... }, ... } -- `note` sits right-aligned in
--       the row, muted ("double-click", "does not replay"); a disabled item
--       is drawn in the `disabled` tone and its click does nothing. A click
--       on an enabled item hides the menu first, then calls onClick.
--   menu:Close()
--   menu.frame         the list frame
--   menu.rows[i]       the item buttons (row.note the note's font string)
--   menu.titleText     the title font string
local _, MD = ...
local UI = MD.UI

local ROW_H = 18

local function Popup(list, shown)
    if UI.OnPopup then UI.OnPopup(list, shown) end
end

function UI.CreateContextMenu(parent, width)
    width = width or 170
    local menu = { rows = {} }
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetFrameStrata(UI.LIST_STRATA or "DIALOG")
    frame:SetWidth(width)
    local P = UI.PALETTE or {}
    UI.StylizeFrame(frame, P.header or { 0.115, 0.115, 0.115, 1 })
    frame:EnableMouse(true)
    frame:Hide()
    frame:SetScript("OnShow", function(self) Popup(self, true) end)
    frame:SetScript("OnHide", function(self) Popup(self, false) end)
    menu.frame = frame

    local title = frame:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -4)
    title:SetWidth(width - 16)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetTextColor(UI.RGB("muted"))
    menu.titleText = title

    function menu:Close() frame:Hide() end

    function menu:Open(anchor, text, items)
        items = items or {}
        title:SetText(text or "")
        local top = text and text ~= "" and 20 or 2
        for _, r in ipairs(menu.rows) do r:Hide() end
        for i, it in ipairs(items) do
            local r = menu.rows[i]
            if not r then
                r = UI.CreateButton(frame, "", "accent-hover", { width - 2, ROW_H }, true, false,
                    UI.FONT_SMALL, UI.FONT_SMALL)
                local note = r:CreateFontString(nil, "OVERLAY", UI.FONT_SMALL)
                note:SetPoint("RIGHT", r, "RIGHT", -6, 0)
                note:SetJustifyH("RIGHT")
                note:SetTextColor(UI.RGB("muted"))
                r.note = note
                menu.rows[i] = r
            end
            r.item = it
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -top - (i - 1) * (ROW_H - 1))
            local fs = r.GetFontString and r:GetFontString()
            if fs then
                fs:ClearAllPoints()
                fs:SetPoint("LEFT", r, "LEFT", 8, 0)
                fs:SetJustifyH("LEFT")
            end
            r:SetText(it.text or "")
            r.note:SetText(it.note or "")
            if it.disabled then r:Disable() else r:Enable() end
            if fs then fs:SetTextColor(UI.RGB(it.disabled and "disabled" or "text")) end
            if it.tooltip then UI.SetTooltips(r, "ANCHOR_RIGHT", 0, 0, it.text, it.tooltip) end
            r:SetScript("OnClick", function(self)
                local item = self.item
                if not item or item.disabled then return end
                frame:Hide()
                if item.onClick then item.onClick() end
            end)
            r:Show()
        end
        frame:SetHeight(top + #items * (ROW_H - 1) + 3)
        frame:ClearAllPoints()
        -- at the pointer, as a right-click menu opens; under `anchor` when the
        -- toolkit has no cursor to read
        local cx, cy
        if GetCursorPosition then cx, cy = GetCursorPosition() end
        local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
        if type(cx) == "number" and type(cy) == "number" and scale and scale > 0 then
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / scale + 2, cy / scale - 2)
        elseif anchor then
            frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 8, 1)
        else
            frame:SetPoint("CENTER", parent, "CENTER", 0, 0)
        end
        frame:Show()
        frame:Raise()
    end

    function menu:IsShown() return frame:IsShown() end

    return menu
end
