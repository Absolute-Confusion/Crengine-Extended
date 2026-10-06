-- Links inside Markdown documents lead to their headings: each heading gets the id GitHub and
-- GitLab give it (word characters kept and lowercased, each space a hyphen, repeats numbered,
-- other alphabets), written as md4c writes a link's target; a heading written in HTML keeps its
-- own id. A tap on such a link (KOReader's link handler) goes to the heading. Every internal link
-- of DESIGN.md works. Only Markdown is changed (an HTML book's headings get no id). A book's cache
-- has crengine-extended's own version, and one with an unmodified crengine's version is not used.
local T = dofile(os.getenv("AT_TESTS") .. "/lib/common.lua")
T.init(true)
local lfs = require("libs/libkoreader-lfs")
local CACHEDIR = require("datastorage"):getDataDir() .. "/cache/cr3cache"

-- A link's target as md4c writes it: bytes other than ASCII as %XX (capital hex)
local function escaped(id)
    return (id:gsub("[\128-\255]", function(c) return ("%%%02X"):format(c:byte()) end))
end
local filler = string.rep("Filler paragraph with a few words in it.\n\n", 60)

print("== Heading ids")
-- heading text -> the id GitHub gives it
local cases = {
    { "5. Principles", "5-principles" },
    { "Café au lait", "café-au-lait" },
    { "Hello, World! (draft)", "hello-world-draft" },
    { "Code `x_y` and **bold**", "code-x_y-and-bold" },
    { "Straße", "straße" },
    { "ÉCOLE Été", "école-été" },
    { "Привет мир", "привет-мир" },
    { "日本語の見出し", "日本語の見出し" },
    { "µm & ²", "µm--" },
    { "A — B", "a--b" },
    { "Rocket 🚀", "rocket-" },
    { "Repeat", "repeat" },
    { "Repeat", "repeat-1" },
    { "Repeat 1", "repeat-1-1" },
}
local md = { "# Links\n\n" }
for _, c in ipairs(cases) do table.insert(md, ("- [%s](#%s)\n"):format(c[2], c[2])) end
table.insert(md, "- [custom](#custom-id)\n\n")
for _, c in ipairs(cases) do table.insert(md, filler .. "## " .. c[1] .. "\n\ntext\n\n") end
table.insert(md, filler .. '<h2 id="custom-id">Custom heading</h2>\n\ntext\n')
local readerui = T.openReader(T.writeFile(T.BOOKS .. "/links.md", table.concat(md)))
local doc = readerui.document
local all = true
for _, c in ipairs(cases) do
    local ok = doc:isXPointerInDocument("#" .. escaped(c[2]))
    if not ok then all = false; print(("      no target: %q -> #%s"):format(c[1], c[2])) end
end
T.check(all, ("every heading has GitHub's id (%d cases: punctuation, inline formatting, other alphabets, symbols, repeats)"):format(#cases))
T.check(doc:isXPointerInDocument("#custom-id") and not doc:isXPointerInDocument("#custom-heading"),
        "a heading written in HTML keeps its own id (and gets no other)")
-- The links as crengine has them, followed as a tap does
local links = {}
for _, l in ipairs(doc:getPageLinks() or {}) do
    if l.section and l.section:sub(1, 1) == "#" then table.insert(links, l.section) end
end
local followed = 0
for _, target in ipairs(links) do
    readerui.link:onGotoLink({ xpointer = target }, true)
    local page = readerui.document:getCurrentPage()
    if page > 1 and page == doc:getPageFromXPointer(target) then followed = followed + 1 end
    readerui.rolling:onGotoPage(1)
end
T.check(#links == #cases + 1 and followed == #links,
        ("a tap on each link goes to its heading (%d of %d links)"):format(followed, #links))
T.closeReader(readerui)

print("== A real document: DESIGN.md")
local f = assert(io.open(os.getenv("AT_TESTS") .. "/../DESIGN.md", "rb"))
local source = f:read("*a")
f:close()
local in_source, expected = {}, 0 -- its distinct internal links, from its text
for target in source:gmatch("%]%((#[^)]+)%)") do
    if not in_source[target] then in_source[target] = true; expected = expected + 1 end
end
local design = T.writeFile(T.BOOKS .. "/DESIGN.md", source)
readerui = T.openReader(design)
doc = readerui.document
local seen, total, working = {}, 0, 0
for page = 1, doc:getPageCount() do
    doc:gotoPage(page)
    for _, l in ipairs(doc:getPageLinks() or {}) do
        if l.section and l.section:sub(1, 1) == "#" and not seen[l.section] then
            seen[l.section] = true
            total = total + 1
            if doc:isXPointerInDocument(l.section) then working = working + 1 else print("      no target: " .. l.section) end
        end
    end
end
T.check(expected > 0 and total == expected and working == total,
        ("every internal link of DESIGN.md has its target (%d of %d, %d in its text)"):format(working, total, expected))
T.closeReader(readerui)

print("== Only Markdown")
readerui = T.openReader(T.writeHtml("plain", '<html><body><p><a href="#plain-heading">x</a></p><h2>Plain heading</h2></body></html>'))
T.check(not readerui.document:isXPointerInDocument("#plain-heading"), "an HTML book's headings get no id")
T.closeReader(readerui)

print("== The book cache")
local big = T.writeFile(T.BOOKS .. "/big.md", "# Big\n\n[go](#5-principles)\n\n" .. string.rep(filler, 50) .. "## 5. Principles\n\ntext\n")
local function cacheFile()
    for f in lfs.dir(CACHEDIR) do
        if f:match("^big%.md%..*%.cr3$") then return CACHEDIR .. "/" .. f end
    end
end
local function header(path)
    local f = assert(io.open(path, "rb"))
    local h = f:read(40)
    f:close()
    return h
end
readerui = T.openReader(big)
T.check(readerui.document:hasCacheFile(), "a Markdown book above 64 KB is cached")
T.closeReader(readerui)
local cache = cacheFile()
T.check(cache and header(cache):sub(26, 33) == "3.05.80e",
        "the cache file has crengine-extended's version (" .. (cache and header(cache):sub(1, 39) or "none") .. ")")
readerui = T.openReader(big)
T.check(readerui.document:isXPointerInDocument("#5-principles"), "reopened from its cache, the heading still has its id")
T.closeReader(readerui)
-- The same cache file, as an unmodified crengine (version ...k) would have written it
f = assert(io.open(cache, "r+b"))
f:seek("set", 32)
f:write("k")
f:close()
readerui = T.openReader(big)
T.check(readerui.document:isXPointerInDocument("#5-principles"), "with an unmodified crengine's cache version, the book is laid out again")
T.closeReader(readerui)
T.check(header(cacheFile()):sub(26, 33) == "3.05.80e", "and its cache is rewritten with crengine-extended's version")
T.finish()
