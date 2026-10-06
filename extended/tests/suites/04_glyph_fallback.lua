-- Glyph fallback follows the slant type of the text's category: NoQFam has no Q, so slanted
-- serif "Q"s come from the fallback font (TestSlab) in the serif category's slant type, not in
-- another category's.
local T = dofile(os.getenv("AT_TESTS") .. "/lib/common.lua")
T.init(false)

local W, H = 900, 300
local Q = "QQQ qqq QQQ"
local doc = T.openPaged(T.writeHtml("glyph_fallback", ([[<html><head><style>p{page-break-before:always;margin:0;font-size:20px}</style></head><body>
<p style="font-family:'NoQFam', serif"><i>%s</i></p>
<p style="font-family:'RefItalic'">%s</p>
<p style="font-family:'RefOblique'">%s</p>
<p style="font-family:'RefRegular'"><i>%s</i></p>
</body></html>]]):format(Q, Q, Q, Q)), W, H)
local cre = doc._document
cre:setStringProperty("crengine.font.fallback.faces", "TestSlab")
cre:setIntProperty("crengine.font.fallback.sizes.adjusted", 0)
local function shot(page)
    T.rerender(doc)
    return T.pagePrint(doc, page, W, H)
end
T.check(cre:getStringProperty("crengine.font.fallback.faces") == "TestSlab", "fallback font is TestSlab")
local refs = { Italic = shot(2), Oblique = shot(3), ["synthetic*"] = shot(4) }
T.check(refs.Italic ~= refs.Oblique and refs.Italic ~= refs["synthetic*"], "references differ")
-- sans-serif stays at another value, so following it would be caught
cre:setStringProperty(T.slantProp("sans-serif"), "Oblique")
for _, v in ipairs({ "Italic", "synthetic*", "Oblique" }) do
    cre:setStringProperty(T.slantProp("serif"), v)
    local got = shot(1)
    local which = "none"
    for k, r in pairs(refs) do if r == got then which = k end end
    T.check(which == v, ("serif %s: fallback Q glyphs are %s"):format(v, which))
end
doc:close()
T.finish()
