-- Category independence, in crengine: changing one category's weight or decoration weight
-- changes the text of that category only, and changing it back restores it exactly.
-- Covers what counts as Unclassified (no generic family, named fonts only, initial).
local T = dofile(os.getenv("AT_TESTS") .. "/lib/common.lua")
T.init(false)

local W, H = 600, 200
local cases = {
    { "untagged",                "base",       [[<p>%s</p>]] },
    { "named font only",         "base",       [[<p style="font-family: 'No Such Font'">%s</p>]] },
    { "font-family: initial",    "base",       [[<p style="font-family: initial">%s</p>]] },
    { "named font in <pre>",     "base",       [[<pre style="white-space: normal"><span style="font-family: 'No Such Font'">%s</span></pre>]] },
    { "sans-serif",              "sans-serif", [[<p style="font-family: sans-serif">%s</p>]] },
    { "inherited sans-serif",    "sans-serif", [[<div style="font-family: sans-serif"><p>%s</p></div>]] },
    { "named font, sans-serif",  "sans-serif", [[<p style="font-family: 'No Such Font', sans-serif">%s</p>]] },
}
for _, c in ipairs({ "serif", "cursive", "fantasy", "monospace", "emoji", "fangsong", "math" }) do
    table.insert(cases, { c, c, ([[<p style="font-family: %s">%%s</p>]]):format(c) })
end
local text = "The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs."
local html = { "<html><head><style>p,pre,div{page-break-before:always; margin:0} p,span{text-decoration:underline}</style></head><body>" }
for _, c in ipairs(cases) do table.insert(html, c[3]:format(text)) end
table.insert(html, "</body></html>")
local doc = T.openPaged(T.writeHtml("independence", table.concat(html, "\n")), W, H)
local cre = doc._document
T.check(doc:getPageCount() == #cases, ("one page per case (%d pages)"):format(doc:getPageCount()))

local function snapshot()
    T.rerender(doc)
    local t = {}
    for i = 1, #cases do t[i] = T.pagePrint(doc, i, W, H) end
    return t
end
local base = snapshot()
for i, c in ipairs(cases) do T.check(base[i] ~= "BLANK", "page not blank: " .. c[1], true) end

local attributes = {
    { "weight 900", T.weightProp, 900, 400 },
    { "decoration weight 500%", T.decorationProp, 500, 100 },
}
for _, a in ipairs(attributes) do
    for _, cat in ipairs(T.CATEGORIES) do
        cre:setIntProperty(a[2](cat), a[3])
        local now = snapshot()
        local ok = true
        for i, c in ipairs(cases) do
            local changed = now[i] ~= base[i]
            local mine = c[2] == cat
            ok = T.check(changed == mine, ("%s %s: %s (%s) %s"):format(cat, a[1], c[1], c[2],
                changed and "changed" or "unchanged"), true) and ok
        end
        cre:setIntProperty(a[2](cat), a[4])
        local back = snapshot()
        for i, c in ipairs(cases) do
            ok = T.check(back[i] == base[i], ("%s %s, changed back: %s not restored"):format(cat, a[1], c[1]), true) and ok
        end
        T.check(ok, ("%-10s %-24s only its own text changes, and changing back restores it"):format(cat, a[1]))
    end
end
doc:close()
T.finish()
