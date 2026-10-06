-- One KOReader startup of crengine (CreDocument:engineInit(): fonts registered, the font cache
-- read and written), then what crengine knows about fonts written to the file given as argument.
-- Run by 11_font_cache.lua and 17_extra_font_folders.lua, each time in a new process, as a new
-- KOReader session would. AT_STARTUP_PLUGIN: "first", the plugin loaded before crengine starts
-- (KOReader starting in its file browser); "last", after (KOReader opening a book at startup).
local T = dofile(os.getenv("AT_TESTS") .. "/lib/common.lua")
local plugin = os.getenv("AT_STARTUP_PLUGIN")
T.init(false)
T.extraFontFoldersFromEnv()
if plugin == "first" then load_plugin("advancedtypography.koplugin") end
local cre = require("document/credocument"):engineInit()
if plugin == "last" then load_plugin("advancedtypography.koplugin") end
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
