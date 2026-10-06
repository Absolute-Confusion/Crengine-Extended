-- Font families grouped by width and spacing: a word is added only when a family mixes widths
-- (or spacings), former names stay usable in books but are hidden from the font list, KOReader's
-- font menu accepts grouped names, and the plugin's slantinfo.lua names families as crengine does.
local T = dofile(os.getenv("AT_TESTS") .. "/lib/common.lua")
T.init(true)
local cre = require("document/credocument"):engineInit()

local listed = {}
for _, n in ipairs(cre.getFontFaces()) do listed[n] = true end
local function file(name)
    local f = cre.getFontFaceFilenameAndFaceIndex(name)
    return f and f:match("[^/]+$") or "NOT FOUND"
end

print("== Names in the font list")
T.check(listed["TestSlab"] and listed["UprFam"], "families of one width and spacing keep their name (TestSlab, UprFam)")
T.check(listed["GrpWide"] and listed["GrpWide Expanded"], "mixed widths: GrpWide, GrpWide Expanded")
T.check(listed["GrpCond"] and listed["GrpCond Semi-Condensed"], "mixed widths: GrpCond, GrpCond Semi-Condensed")
T.check(listed["GrpSpace Monospace"] and listed["GrpSpace Proportional"], "mixed spacings: GrpSpace Monospace, GrpSpace Proportional")
T.check(not listed["GrpCond Condensed"] and not listed["GrpSpace"], "former names hidden (GrpCond Condensed, GrpSpace)")

print("== Lookups (as by a book's CSS)")
T.check(file("GrpWide Expanded") == "GrpWide-Extended.ttf", "GrpWide Expanded -> " .. file("GrpWide Expanded"))
T.check(file("GrpWide") == "GrpWide-Regular.ttf", "GrpWide -> " .. file("GrpWide"))
T.check(file("GrpCond Condensed") == "GrpCond-Condensed.ttf", "former name GrpCond Condensed still finds its font: " .. file("GrpCond Condensed"))
T.check(file("GrpSpace") ~= "NOT FOUND", "former name GrpSpace still finds a font: " .. file("GrpSpace"))
T.check(file("GrpSpace Monospace") == "GrpSpace-Mono.ttf" and file("GrpSpace Proportional") == "GrpSpace-Prop.ttf", "spacing groups find their files")

print("== KOReader's font menu with grouped names")
local readerui = T.openReader(T.writeHtml("grouping", "<html><body><p>x</p></body></html>"))
readerui.font:onSetFont("GrpWide Expanded")
T.check(readerui.font.font_face == "GrpWide Expanded", "grouped family accepted as main font: " .. tostring(readerui.font.font_face))
T.check(G_reader_settings:readSetting("cre_font") == "GrpWide Expanded", "saved globally")
T.check(readerui.document._document:getStringProperty("font.face.default") == "GrpWide Expanded", "applied to crengine")
readerui.font:onSetFont("TestSlab")
T.check(readerui.font.font_face == "TestSlab", "an ungrouped family still accepted")
readerui.font:onSetFont("No Such Font")
T.check(readerui.font.font_face == "TestSlab", "an unknown name still rejected")
T.closeReader(readerui)

print("== The plugin's slantinfo.lua knows every family crengine lists")
local SlantInfo = require("slantinfo")
local unknown = {}
for n in pairs(listed) do
    if SlantInfo.getFamilyKinds(n) == nil then table.insert(unknown, n) end
end
table.sort(unknown)
T.check(#unknown == 0, "all listed families found by slantinfo.lua" .. (#unknown > 0 and (": missing " .. table.concat(unknown, ", ")) or ""))
T.finish()
