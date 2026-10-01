-- tools/stub_art.lua -- the art and clock fakes (docs/SPEC-next.md 2, T87).
--
-- Not a suite: loaded by the suites that need it (tools/probecheck.lua today;
-- the style and clock suites later), AFTER tools/wowstub.lua and its profile,
-- so no existing suite sees any of it and no expected count moves.
--
--   local A = dofile(here .. "/stub_art.lua")
--   A.Install(S, opts)
--
-- What it installs (each part switched by opts; an absent part is the client
-- answering "no such function", which is itself a probe answer):
--   * textures: Texture:SetTexture(path) records the path and answers true for
--     a file the fake knows (opts.files, path -> file id), false otherwise;
--     GetTexture() answers the file id of a known path, nil otherwise --
--     a stand-in for the retail engine's shape, UNVERIFIED on either client;
--   * GetFileIDFromPath(path) -> the id or nil (opts.fileIDs = false: absent);
--   * C_Texture.GetAtlasInfo(name) -> { file, width, height } or nil
--     (opts.atlases = false: C_Texture absent);
--   * Texture:SetAtlas(name), SetVertexColor / GetVertexColor (recorded, a
--     secret component kept secret on the way back), SetRotation /
--     GetRotation (opts.rotation, default true);
--   * FontString:SetFont(path, size, flags) answering true for a font the fake
--     knows (opts.fonts), still recorded as tools/wowstub.lua records it;
--   * the colour curve (opts.colorCurve): C_CurveUtil.CreateColorCurve, a
--     curve object with SetType / AddPoint, CreateColor, and UnitPowerPercent
--     answering a colour object whose GetRGB returns three secrets when a
--     curve is passed (the stub's forever profile must be on: S.Secret);
--   * ColorPickerFrame (opts.colorPicker): "modern" with
--     SetupColorPickerAndShow, "classic" without it, false / nil: absent.
-- Every name is created before a suite takes its "globals before" snapshot,
-- so tools/probecheck.lua's "the probe adds no global but its own" is unmoved.
local A = {}

-- The files and atlases the fake answers for by default: every plain file the
-- styles name that both clients are believed to carry (docs/research/next/
-- R-styles.md 5.1), the clock's textures and fonts (R-clock.md 8.3), and no
-- atlas at all (TBC's answer). A suite passes its own lists for the rest.
A.FILES = {
    ["Interface\\Buttons\\WHITE8x8"] = 137012,
    ["Interface\\TargetingFrame\\UI-StatusBar"] = 137012 + 1,
    ["Interface\\DialogFrame\\UI-DialogBox-Background"] = 137012 + 2,
    ["Interface\\DialogFrame\\UI-DialogBox-Border"] = 137012 + 3,
    ["Interface\\DialogFrame\\UI-DialogBox-Header"] = 137012 + 4,
    ["Interface\\Tooltips\\UI-Tooltip-Border"] = 137012 + 5,
    ["Interface\\Tooltips\\UI-Tooltip-Background"] = 137012 + 6,
    ["Interface\\Buttons\\UI-Panel-Button-Up"] = 137012 + 7,
}
A.FONTS = {
    ["Fonts\\FRIZQT__.TTF"] = true, ["Fonts\\ARIALN.TTF"] = true,
    ["Fonts\\skurri.ttf"] = true, ["Fonts\\MORPHEUS.ttf"] = true,
}

function A.Install(S, opts)
    opts = opts or {}
    local files = opts.files or A.FILES
    local fonts = opts.fonts or A.FONTS
    local MT = getmetatable(UIParent)
    S.art = { textureSets = {}, rotations = {}, atlasSets = {} }

    function MT:SetTexture(path)
        self.texturePath = path
        S.art.textureSets[#S.art.textureSets + 1] = path
        return files[path] ~= nil
    end
    function MT:GetTexture()
        if self.texturePath == nil then return nil end
        return files[self.texturePath]
    end
    function MT:SetAtlas(name)
        self.atlas = name
        S.art.atlasSets[#S.art.atlasSets + 1] = name
    end
    function MT:SetVertexColor(r, g, b, a) self.vertexColor = { r, g, b, a } end
    function MT:GetVertexColor()
        local c = self.vertexColor
        if not c then return 1, 1, 1, 1 end
        return c[1], c[2], c[3], c[4] or 1
    end
    if opts.rotation ~= false then
        function MT:SetRotation(angle)
            self.rotation = angle
            S.art.rotations[#S.art.rotations + 1] = angle
        end
        function MT:GetRotation() return self.rotation or 0 end
    else
        -- false, not nil: the stub's frames answer every unknown method with a
        -- no-op, so only a non-function value reads as "the client has none"
        MT.SetRotation, MT.GetRotation = false, false
    end
    function MT:SetFont(path, size, flags)
        self.fontPath, self.fontSize, self.fontFlags = path, size, flags
        return fonts[path] == true
    end

    if opts.fileIDs == false then
        _G.GetFileIDFromPath = nil
    else
        function GetFileIDFromPath(path) return files[path] end
    end

    if opts.atlases == false then
        _G.C_Texture = nil
    else
        local atlases = opts.atlases or {}
        _G.C_Texture = {
            GetAtlasInfo = function(name)
                local a = atlases[name]
                if not a then return nil end
                return { file = a.file, width = a.width, height = a.height,
                    leftTexCoord = 0, rightTexCoord = 1, topTexCoord = 0, bottomTexCoord = 1 }
            end,
        }
    end

    if opts.colorCurve then
        local CurveMT = {}
        CurveMT.__index = CurveMT
        function CurveMT:SetType(t) self.type = t end
        function CurveMT:AddPoint(x, color) self.points[#self.points + 1] = { x, color } end
        _G.C_CurveUtil = { CreateColorCurve = function() return setmetatable({ points = {} }, CurveMT) end }
        function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a or 1 } end
        local plainPercent = UnitPowerPercent
        function UnitPowerPercent(u, powerType, usePredicted, curve)
            if type(curve) == "table" and getmetatable(curve) == CurveMT then
                -- a colour whose components are secrets: a bar may take them,
                -- nothing may read them (UNVERIFIED: the question Q-clock-1 asks)
                return { GetRGB = function() return S.Secret(), S.Secret(), S.Secret() end }
            end
            return plainPercent(u, powerType)
        end
    end

    -- a plain table, not a stub frame: a stub frame answers every unknown
    -- method with a no-op, so "classic" could never lack the modern method
    if opts.colorPicker == "modern" then
        _G.ColorPickerFrame = { SetupColorPickerAndShow = function(self, info) self.info = info end }
    elseif opts.colorPicker == "classic" then
        _G.ColorPickerFrame = { SetColorRGB = function(self, r, g, b) self.rgb = { r, g, b } end }
    end
end

return A
