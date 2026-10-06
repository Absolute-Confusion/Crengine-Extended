-- One KOReader session with the plugin loaded at startup, then a book open: whether fonts of the
-- extra font folders work like any other font in the reader. Writes "check<TAB>result" lines to the
-- file given as argument. Run by 17_extra_font_folders.lua, in a new process.
local T = dofile(os.getenv("AT_TESTS") .. "/lib/common.lua")
T.init(false)
T.extraFontFoldersFromEnv()
load_plugin("advancedtypography.koplugin")
local out = assert(io.open(arg[1], "w"))
local readerui = T.openReader(T.writeHtml("extra_fonts", "<html><body><p>x</p></body></html>"))
-- KOReader's own font menu (ReaderFont:onSetFont(), which only knows its own font list's fonts,
-- extended by the plugin to every family crengine lists)
readerui.font:onSetFont("FolderTestFamily")
out:write("koreader_font_menu\t", tostring(readerui.font.font_face), "\n")
-- The plugin's Font Face list
local chooser = require("fontchooser"):new{ title = "x", current_font = "" }
local listed = {}
for _, font in ipairs(chooser.all_fonts) do listed[font] = true end
chooser:onCloseWidget()
out:write("font_face_list\t", tostring(listed["CacheTestFamily"] and listed["FolderTestFamily"]), "\n")
-- Slant greying, read from crengine's font cache (only fonts crengine registered)
local SlantInfo = require("slantinfo")
local kinds = SlantInfo.getFamilyKinds("FolderTestFamily")
out:write("slant_kinds\t", tostring(kinds ~= nil), "\n")
local slab = SlantInfo.getFamilyKinds("TestSlab")
out:write("slant_kinds_testslab\t", tostring(slab ~= nil and slab.italic and slab.oblique), "\n")
out:close()
T.closeReader(readerui)
