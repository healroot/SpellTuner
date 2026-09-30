-- tools/svwrite.lua -- a Lua value written the way the client writes a
-- SavedVariables file: `Name = { ["key"] = value, ... }`, one entry a line.
-- Keys are sorted (numbers first, in order; then strings), so the same table
-- always writes the same bytes -- tools/importcheck.lua compares a freshly
-- built fixture with the committed one byte for byte.
--
--   local W = dofile("tools/svwrite.lua")
--   W.Write(path, { SpellTunerDB = db })     -- one or more globals
--   W.Value(v)                               -- one value as a string
--
-- Numbers are written with %.17g so a float reads back exactly; a table seen
-- twice (the client duplicates a shared table too) is written twice; a
-- function, userdata or thread raises -- a SavedVariables file cannot hold one.
local W = {}

local function Key(k)
    if type(k) == "number" then return "[" .. W.Number(k) .. "]" end
    return "[" .. string.format("%q", k) .. "]"
end

function W.Number(n)
    if n ~= n then return "0/0" end
    if n == math.huge then return "math.huge" end
    if n == -math.huge then return "-math.huge" end
    if n == math.floor(n) and math.abs(n) < 2 ^ 53 then return string.format("%d", n) end
    return string.format("%.17g", n)
end

local function SortedKeys(t)
    local nums, strs = {}, {}
    for k in pairs(t) do
        if type(k) == "number" then nums[#nums + 1] = k
        elseif type(k) == "string" then strs[#strs + 1] = k
        else error("svwrite: a " .. type(k) .. " key cannot be saved") end
    end
    table.sort(nums)
    table.sort(strs)
    for _, s in ipairs(strs) do nums[#nums + 1] = s end
    return nums
end

local function Emit(out, v, indent, path)
    local tv = type(v)
    if tv == "number" then out[#out + 1] = W.Number(v)
    elseif tv == "string" then out[#out + 1] = string.format("%q", v)
    elseif tv == "boolean" then out[#out + 1] = tostring(v)
    elseif tv == "table" then
        local keys = SortedKeys(v)
        if #keys == 0 then out[#out + 1] = "{}"; return end
        out[#out + 1] = "{\n"
        local pad = indent .. "\t"
        for _, k in ipairs(keys) do
            out[#out + 1] = pad .. Key(k) .. " = "
            Emit(out, v[k], pad, path .. "." .. tostring(k))
            out[#out + 1] = ",\n"
        end
        out[#out + 1] = indent .. "}"
    else
        error("svwrite: " .. path .. " is a " .. tv .. ", which a SavedVariables file cannot hold")
    end
end

function W.Value(v)
    local out = {}
    Emit(out, v, "", "value")
    return table.concat(out)
end

-- globals: { Name = value, ... }, written in name order
function W.Write(path, globals)
    local names = {}
    for name in pairs(globals) do names[#names + 1] = name end
    table.sort(names)
    local out = {}
    for _, name in ipairs(names) do
        out[#out + 1] = "\n" .. name .. " = "
        Emit(out, globals[name], "", name)
        out[#out + 1] = "\n"
    end
    local f = assert(io.open(path, "w"))
    f:write(table.concat(out))
    f:close()
end

return W
