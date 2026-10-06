-- Live slant type switching, all 9 categories, as in the app: EPUB with partial rerendering,
-- changes made through the plugin's menu. After each change, every category's slanted text
-- (regular and bold) must look exactly as after opening the book fresh with that slant type.
local T = dofile(os.getenv("AT_TESTS") .. "/lib/common.lua")
T.init(true)
T.useFont("TestSlab") -- has both slant kinds, so no category gets switched to synthetic*

local paras = {}
for _, c in ipairs(T.CATEGORIES) do
    local ff = c == "base" and "'TestSlab'" or ("'TestSlab', " .. c)
    for _, bold in ipairs({ "", "font-weight: bold; " }) do
        table.insert(paras, ('<p style="font-family: %s; font-style: italic; %sfont-size: 14px; margin: 0.3em 0">%s lorem amet</p>'):format(ff, bold, c))
    end
end
local book = T.writeEpub("live_slant_nine", table.concat(paras))
local values = { "Italic", "Oblique", "synthetic*" }

local readerui, lines
local function open()
    if readerui then T.closeReader(readerui) end
    readerui = T.openReader(book)
end
local function snapshot()
    local bb = T.paint(readerui)
    lines = lines or T.findLines(bb)
    local h = T.linePrints(bb, lines)
    bb:free()
    return h
end

-- References: all categories on one slant type, fresh open
local ref = {}
for _, v in ipairs(values) do
    for _, c in ipairs(T.CATEGORIES) do G_reader_settings:saveSetting(T.slantProp(c), v) end
    open()
    ref[v] = snapshot()
end
if not T.check(#lines == 18, ("18 text lines found (%d)"):format(#lines)) then T.finish() end
T.check(readerui.document:isPartialRerenderingEnabled(), "partial rerendering enabled (as in the app)")
local distinct = true
for i = 1, 18 do
    if ref.Italic[i] == ref.Oblique[i] or ref.Italic[i] == ref["synthetic*"][i] or ref.Oblique[i] == ref["synthetic*"][i] then distinct = false end
end
T.check(distinct, "the 3 slant types look different on every line")

-- States: all one value, rotations, then each category alone on each value
local states = {}
for _, v in ipairs(values) do local s = {}; for _, c in ipairs(T.CATEGORIES) do s[c] = v end; table.insert(states, s) end
for shift = 0, 2 do local s = {}; for i, c in ipairs(T.CATEGORIES) do s[c] = values[(i + shift) % 3 + 1] end; table.insert(states, s) end
for _, c in ipairs(T.CATEGORIES) do
    for _, v in ipairs(values) do
        local s = {}
        for _, c2 in ipairs(T.CATEGORIES) do s[c2] = (c2 == c) and v or ((v == "Italic") and "Oblique" or "Italic") end
        table.insert(states, s)
    end
end
-- Live changes, no reopening (the book is open with all synthetic*)
local checks, fails = 0, 0
for n, s in ipairs(states) do
    for _, c in ipairs(T.CATEGORIES) do
        if G_reader_settings:readSetting(T.slantProp(c)) ~= s[c] then T.menuSet(readerui, c, "slant", s[c]) end
    end
    local h = snapshot()
    for ci, c in ipairs(T.CATEGORIES) do
        for w = 1, 2 do
            local i = (ci - 1) * 2 + w
            checks = checks + 1
            if h[i] ~= ref[s[c]][i] then
                fails = fails + 1
                local shows = "none"
                for _, v in ipairs(values) do if h[i] == ref[v][i] then shows = v end end
                T.check(false, ("state %d: %s %s set to %s, shows %s"):format(n, c, w == 1 and "regular" or "bold", s[c], shows))
            end
        end
    end
end
T.check(readerui.document:getPartialRerenderingsCount() > 0, "changes were applied by partial rerendering")
T.check(fails == 0, ("%d states, %d checks: each line as after a fresh open"):format(#states, checks))
T.closeReader(readerui)
T.finish()
