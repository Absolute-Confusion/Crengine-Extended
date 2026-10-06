-- One KOReader startup of crengine (CreDocument:engineInit(): fonts registered, the font cache
-- read and written), then what crengine knows about fonts written to the file given as argument.
-- Run by 11_font_cache.lua, each time in a new process, as a new KOReader session would.
local T = dofile(os.getenv("AT_TESTS") .. "/lib/common.lua")
T.init(false)
local cre = require("document/credocument"):engineInit()
local out = assert(io.open(arg[1], "w"))
local names = cre.getFontFaces()
table.sort(names)
for _, name in ipairs(names) do
    local line = { name }
    for _, v in ipairs({ { false, false }, { true, false }, { false, true }, { true, true } }) do
        local file, index = cre.getFontFaceFilenameAndFaceIndex(name, v[1], v[2])
        table.insert(line, tostring(file) .. "#" .. tostring(index))
    end
    out:write(table.concat(line, "\t"), "\n")
end
for _, name in ipairs({ "GrpCond Condensed", "GrpSpace" }) do
    out:write("former name ", name, "\t", tostring(cre.getFontFaceFilenameAndFaceIndex(name)), "\n")
end
out:close()
