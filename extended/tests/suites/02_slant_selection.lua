-- Slant type, in crengine: for each category, slanted text (regular and bold) uses exactly the
-- face the slant type asks for (Italic, Oblique or synthetic*), falling back to the other kind,
-- then to synthetic, when the family lacks it. Pixel-exact: each case is compared with a
-- reference page showing that one font file upright. Also checks category independence.
local T = dofile(os.getenv("AT_TESTS") .. "/lib/common.lua")
T.init(false)

local W, H = 900, 300
local text = "Haffle quick jumping fox gazes at 0123456789 &amp; {[(@)]}"
local function ff(fam, cat)
    if cat == "base" then return ("'%s'"):format(fam) end
    return ("'%s', %s"):format(fam, cat)
end
local pages, order = {}, {}
local function page(id, fam, cat, b, i)
    local inner = text
    if i then inner = "<i>" .. inner .. "</i>" end
    if b then inner = "<b>" .. inner .. "</b>" end
    pages[id] = ([[<p style="font-family: %s">%s</p>]]):format(ff(fam, cat), inner)
    table.insert(order, id)
end
-- References (R_): upright text in single-file families, possibly with synthetic bold/italic
page("R_italic", "RefItalic", "base")
page("R_oblique", "RefOblique", "base")
page("R_synth", "RefRegular", "base", false, true)
page("R_bolditalic", "RefBoldItalic", "base", true)
page("R_boldoblique", "RefBoldOblique", "base", true)
page("R_synthbold", "RefBold", "base", true, true)
page("R_italic_synthbold", "RefItalic", "base", true)
page("R_oblique_synthbold", "RefOblique", "base", true)
page("R_boldoblique_synthlight", "RefBoldOblique", "base")
page("R_regular_synthbold_synthitalic", "RefRegular", "base", true, true)
-- Cases, per category: TestSlab (italic + oblique), MixFam (italic, bold oblique), OblFam (oblique), UprFam (none)
for _, cat in ipairs(T.CATEGORIES) do
    page("T_" .. cat .. "_reg", "TestSlab", cat, false, true)
    page("T_" .. cat .. "_bold", "TestSlab", cat, true, true)
    page("M_" .. cat .. "_reg", "MixFam", cat, false, true)
    page("M_" .. cat .. "_bold", "MixFam", cat, true, true)
    page("O_" .. cat .. "_reg", "OblFam", cat, false, true)
    page("O_" .. cat .. "_bold", "OblFam", cat, true, true)
    page("U_" .. cat .. "_reg", "UprFam", cat, false, true)
end
local html = { "<html><head><style>p{page-break-before:always; margin:0; font-size:20px}</style></head><body>" }
local page_of = {}
for n, id in ipairs(order) do table.insert(html, pages[id]); page_of[id] = n end
table.insert(html, "</body></html>")
local doc = T.openPaged(T.writeHtml("slant_selection", table.concat(html, "\n")), W, H)
local cdoc = doc._document
T.check(doc:getPageCount() == #order, ("one page per case (%d pages)"):format(doc:getPageCount()))

local function snapshot()
    T.rerender(doc)
    local t = {}
    for id, n in pairs(page_of) do t[id] = T.pagePrint(doc, n, W, H) end
    return t
end

local expected = {
    Italic = { T_reg = "R_italic", T_bold = "R_bolditalic",
               M_reg = "R_italic", M_bold = "R_italic_synthbold",
               O_reg = "R_oblique", O_bold = "R_oblique_synthbold", U_reg = "R_synth" },
    Oblique = { T_reg = "R_oblique", T_bold = "R_boldoblique",
                M_reg = "R_boldoblique_synthlight", M_bold = "R_boldoblique",
                O_reg = "R_oblique", O_bold = "R_oblique_synthbold", U_reg = "R_synth" },
    ["synthetic*"] = { T_reg = "R_synth", T_bold = "R_synthbold",
                       M_reg = "R_synth", M_bold = "R_regular_synthbold_synthitalic",
                       O_reg = "R_synth", O_bold = "R_regular_synthbold_synthitalic", U_reg = "R_synth" },
}
local kinds = { "T_reg", "T_bold", "M_reg", "M_bold", "O_reg", "O_bold", "U_reg" }

-- References must be distinct and not blank, or the test proves nothing
local base = snapshot()
local seen = {}
for id in pairs(page_of) do
    if id:sub(1, 2) == "R_" then
        T.check(base[id] ~= "BLANK", "reference not blank: " .. id, true)
        T.check(not seen[base[id]], "references differ: " .. id .. " / " .. tostring(seen[base[id]]), true)
        seen[base[id]] = id
    end
end

local function check(state, label)
    local snap = snapshot()
    local ok = true
    for _, cat in ipairs(T.CATEGORIES) do
        for _, k in ipairs(kinds) do
            local id = k:sub(1, 2) .. cat .. k:sub(2)
            local want = expected[state[cat]][k]
            if snap[id] ~= snap[want] then
                local got = "?"
                for rid in pairs(page_of) do if rid:sub(1, 2) == "R_" and snap[rid] == snap[id] then got = rid end end
                ok = T.check(false, ("[%s] %s with slant type %s: want %s, got %s"):format(label, id, state[cat], want, got))
            end
        end
    end
    for id in pairs(page_of) do
        if id:sub(1, 2) == "R_" and snap[id] ~= base[id] then
            ok = T.check(false, ("[%s] reference changed: %s"):format(label, id))
        end
    end
    T.check(ok, label)
end
local function setSlant(cat, v) cdoc:setStringProperty(T.slantProp(cat), v) end

-- Default: Italic everywhere
local state = {}
for _, cat in ipairs(T.CATEGORIES) do state[cat] = "Italic" end
check(state, "default: all categories Italic")
-- Each slant type everywhere
for _, v in ipairs({ "Oblique", "synthetic*", "Italic" }) do
    for _, cat in ipairs(T.CATEGORIES) do setSlant(cat, v); state[cat] = v end
    check(state, "all categories " .. v)
end
-- Independence: mixed values, then each category changed alone
local values = { "Italic", "Oblique", "synthetic*" }
for i, cat in ipairs(T.CATEGORIES) do setSlant(cat, values[(i % 3) + 1]); state[cat] = values[(i % 3) + 1] end
check(state, "mixed values per category")
for _, cat in ipairs(T.CATEGORIES) do
    for _, v in ipairs(values) do
        if v ~= state[cat] then
            setSlant(cat, v); state[cat] = v
            check(state, ("only %s changed, to %s"):format(cat, v))
        end
    end
end
doc:close()
T.finish()
