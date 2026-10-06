-- Slant type with a variable font that has a slnt axis and no italic (TestVar): Oblique uses
-- the axis, Italic falls back to it (the other kind), synthetic* doesn't use it.
local T = dofile(os.getenv("AT_TESTS") .. "/lib/common.lua")
T.init(false)

local W, H = 900, 300
local text = "Haffle quick jumping fox gazes at 0123456789"
local doc = T.openPaged(T.writeHtml("variable_font", ([[<html><head><style>p{page-break-before:always;margin:0;font-size:20px}</style></head><body>
<p style="font-family:'TestVar', serif"><i>%s</i></p>
<p style="font-family:'TestVar', serif">%s</p>
</body></html>]]):format(text, text)), W, H)
local function shot(page)
    T.rerender(doc)
    return T.pagePrint(doc, page, W, H)
end
local r = { upright = shot(2) }
for _, v in ipairs({ "Italic", "Oblique", "synthetic*" }) do
    doc._document:setStringProperty(T.slantProp("serif"), v)
    r[v] = shot(1)
end
T.check(r.upright ~= "BLANK", "TestVar renders")
T.check(r.Oblique ~= r.upright, "Oblique is slanted (differs from upright)")
T.check(r.Italic == r.Oblique, "Italic falls back to the slnt axis (no italic in this family)")
T.check(r["synthetic*"] ~= r.Oblique, "synthetic* doesn't use the slnt axis")
T.check(r["synthetic*"] ~= r.upright, "synthetic* is slanted")
doc:close()
T.finish()
