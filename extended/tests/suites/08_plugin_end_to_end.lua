-- The plugin end to end: slant kinds per family (greying out), global font faces (per-book
-- ones ignored and never saved, KOReader's own font menus made global), switching a category
-- to synthetic* when its font lacks the chosen kind, the slant type menu, and a second book.
local T = dofile(os.getenv("AT_TESTS") .. "/lib/common.lua")
T.init(true)
local DocSettings = require("docsettings")
local UIManager = require("ui/uimanager")
require("fontlist"):getFontList()

print("== Slant kinds per family (plugin's slantinfo.lua)")
local SlantInfo = require("slantinfo")
local function kinds(family)
    local k = SlantInfo.getFamilyKinds(family)
    return k and ((k.italic and "I" or "-") .. (k.oblique and "O" or "-")) or "nil"
end
T.check(kinds("TestSlab") == "IO", "TestSlab: italic and oblique")
T.check(kinds("MixFam") == "IO", "MixFam: italic and oblique")
T.check(kinds("OblFam") == "-O", "OblFam: oblique only")
T.check(kinds("UprFam") == "--", "UprFam: none")
T.check(kinds("TestVar") == "-O", "TestVar (variable, slnt axis): oblique")
T.check(kinds("Noto Sans") == "I-", "Noto Sans (bundled with KOReader): italic only")
T.check(kinds("No Such Font") == "nil", "unknown family: unknown")

-- Global settings
G_reader_settings:saveSetting("cre_font", "MixFam")
G_reader_settings:saveSetting("cre_font_family_fonts", { serif = "OblFam" })
for _, c in ipairs(T.CATEGORIES) do G_reader_settings:saveSetting(T.slantProp(c), "Italic") end
G_reader_settings:saveSetting(T.slantProp("sans-serif"), "Oblique")
G_reader_settings:saveSetting(T.slantProp("monospace"), "Oblique")

-- Two books, the first one with per-book fonts saved (as KOReader does without the plugin)
local book1 = T.BOOKS .. "/e2e_book1.epub"
local book2 = T.BOOKS .. "/e2e_book2.epub"
os.execute(("cp spec/front/unit/data/juliet.epub %q && cp spec/front/unit/data/leaves.epub %q"):format(book1, book2))
local ds = DocSettings:open(book1)
ds:saveSetting("font_face", "UprFam")
ds:saveSetting("font_family_fonts", { serif = "UprFam" })
ds:flush()

print("== Opening a book that has per-book fonts saved")
local readerui = T.openReader(book1)
local doc = readerui.document
local function prop(c) return doc._document:getStringProperty(T.slantProp(c)) end
T.check(readerui.font.font_face == "MixFam", "per-book main font ignored, global one used: " .. tostring(readerui.font.font_face))
T.check(doc._typography_family_fonts and doc._typography_family_fonts.serif == "OblFam", "per-book serif font ignored, global one used")
T.check(G_reader_settings:readSetting(T.slantProp("serif")) == "synthetic*" and prop("serif") == "synthetic*",
        "serif Italic -> synthetic* (its font OblFam has no italic), saved and applied")
T.check(G_reader_settings:readSetting(T.slantProp("base")) == "Italic" and prop("base") == "Italic", "unclassified stays Italic (MixFam has italic)")
T.check(G_reader_settings:readSetting(T.slantProp("sans-serif")) == "Oblique", "sans-serif stays Oblique (main font MixFam has oblique)")
T.check(G_reader_settings:readSetting(T.slantProp("cursive")) == "Italic", "cursive stays Italic (main font MixFam)")

print("== Changing the main font with KOReader's own font menu")
readerui.font:onSetFont("OblFam")
T.check(G_reader_settings:readSetting("cre_font") == "OblFam", "native font choice saved globally")
T.check(G_reader_settings:readSetting(T.slantProp("base")) == "synthetic*" and prop("base") == "synthetic*",
        "unclassified Italic -> synthetic* (OblFam has no italic)")
T.check(G_reader_settings:readSetting(T.slantProp("cursive")) == "synthetic*", "cursive (uses the main font) Italic -> synthetic*")
T.check(G_reader_settings:readSetting(T.slantProp("sans-serif")) == "Oblique", "sans-serif stays Oblique (OblFam has oblique)")

print("== Changing a font-family font with KOReader's own menu")
readerui.font.font_family_fonts["serif"] = "MixFam"
readerui.font:updateFontFamilyFonts()
local gff = G_reader_settings:readSetting("cre_font_family_fonts")
T.check(gff.serif == "MixFam" and next(readerui.font.font_family_fonts) == nil, "per-book family choice made global")
T.check(doc._typography_family_fonts.serif == "MixFam", "crengine got the new serif font")

print("== Slant type menu (serif, font MixFam)")
local item = T.menuItem(readerui, "serif", 3)
T.check(item.text_func() == "Slant Type: synthetic*", "menu shows the current value: " .. item.text_func())
item.callback(nil)
local dialog = UIManager._window_stack[#UIManager._window_stack].widget
local b = {}
for i, row in ipairs(dialog.buttons) do b[i] = row[1] end
T.check(b[1].enabled and b[2].enabled and b[3].enabled, "MixFam: Italic, Oblique and synthetic* all enabled")
T.check(b[3].text:find("✓", 1, true) ~= nil, "current choice marked")
b[2].callback() -- Oblique
T.check(G_reader_settings:readSetting(T.slantProp("serif")) == "Oblique" and prop("serif") == "Oblique", "picking Oblique saves it and applies it")

print("== Slant type menu (unclassified, font OblFam): greyed out choices")
T.menuItem(readerui, "base", 3).callback(nil)
dialog = UIManager._window_stack[#UIManager._window_stack].widget
b = {}
for i, row in ipairs(dialog.buttons) do b[i] = row[1] end
T.check(b[1].enabled == false, "Italic greyed out (OblFam has no italic)")
T.check(b[2].enabled == true and b[3].enabled == true, "Oblique and synthetic* enabled")
UIManager:close(dialog)

print("== Saving, then opening another book")
readerui:saveSettings()
local saved = DocSettings:open(book1)
T.check(saved:readSetting("font_face") == nil and saved:readSetting("font_family_fonts") == nil, "no per-book fonts saved")
T.closeReader(readerui)
local readerui2 = T.openReader(book2)
T.check(readerui2.font.font_face == "OblFam", "second book uses the global main font")
T.check(readerui2.document._typography_family_fonts.serif == "MixFam", "second book uses the global serif font")
T.check(readerui2.document._document:getStringProperty(T.slantProp("serif")) == "Oblique", "second book: serif slant type applied")
T.check(readerui2.document._document:getStringProperty(T.slantProp("base")) == "synthetic*", "second book: unclassified slant type applied")
T.closeReader(readerui2)
T.finish()
