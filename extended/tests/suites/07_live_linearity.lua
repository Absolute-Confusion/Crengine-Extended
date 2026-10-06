-- Weight and decoration weight respond monotonically, per category, live through the plugin's
-- menu: a higher value never gives lighter text, and the highest is heavier than the lowest.
-- Other categories' text never changes, changing back restores it, and nothing is written to
-- disk meanwhile. (Not strictly linear on screen: font weights are separate designs, and line
-- thickness is a whole number of pixels.)
local T = dofile(os.getenv("AT_TESTS") .. "/lib/common.lua")
T.init(true)
local lfs = require("libs/libkoreader-lfs")
local SETTINGS = G_reader_settings.file
T.useFont("TestSlab")

local LINES = 3
local kinds = {
    weight = { prop = T.weightProp, default = 400, values = { 200, 300, 400, 500, 600, 700, 800, 900 } },
    decoration = { prop = T.decorationProp, default = 100, values = { 50, 100, 150, 200, 300, 400, 500 } },
}
for _, c in ipairs(T.CATEGORIES) do
    for _, k in pairs(kinds) do G_reader_settings:saveSetting(k.prop(c), k.default) end
    G_reader_settings:saveSetting(T.slantProp(c), "Italic")
end
G_reader_settings:flush()

local paras = {}
for _, c in ipairs(T.CATEGORIES) do
    local ff = c == "base" and "'TestSlab'" or ("'TestSlab', " .. c)
    for _, extra in ipairs({ "", "font-style: italic; ", "font-style: italic; font-weight: bold; " }) do
        table.insert(paras, ('<p style="font-family: %s; %stext-decoration: underline line-through; font-size: 12px; margin: 0.45em 0">%s lorem amet</p>'):format(ff, extra, c))
    end
end
local readerui = T.openReader(T.writeEpub("live_linearity", table.concat(paras)))
local settings_mtime = lfs.attributes(SETTINGS, "modification")

local lines
local function snapshot()
    local bb = T.paint(readerui)
    lines = lines or T.findLines(bb)
    local h, ink = T.linePrints(bb, lines)
    bb:free()
    return h, ink
end
local base = snapshot()
if not T.check(#lines == #T.CATEGORIES * LINES, ("%d text lines found (%d)"):format(#T.CATEGORIES * LINES, #lines)) then T.finish() end

for ci, c in ipairs(T.CATEGORIES) do
    for _, kname in ipairs({ "weight", "decoration" }) do
        local k = kinds[kname]
        local inks, ok = {}, true
        for _, v in ipairs(k.values) do
            T.menuSet(readerui, c, kname, v)
            local h, ink = snapshot()
            local mine = 0
            for i = 1, #lines do
                if math.floor((i - 1) / LINES) + 1 == ci then
                    mine = mine + ink[i]
                else
                    ok = T.check(h[i] == base[i], ("%s %s=%d changed line %d of another category"):format(c, kname, v, i), true) and ok
                end
            end
            table.insert(inks, mine)
        end
        for i = 2, #inks do
            ok = T.check(inks[i] >= inks[i-1], ("%s %s: %d -> %d gives less ink (%d -> %d)"):format(c, kname, k.values[i-1], k.values[i], inks[i-1], inks[i]), true) and ok
        end
        ok = T.check(inks[#inks] > inks[1], ("%s %s: no change from lowest to highest"):format(c, kname), true) and ok
        T.menuSet(readerui, c, kname, k.default)
        local h = snapshot()
        for i = 1, #lines do ok = T.check(h[i] == base[i], ("%s %s changed back: line %d not restored"):format(c, kname, i), true) and ok end
        local steps = 0
        for i = 2, #inks do if inks[i] > inks[i-1] then steps = steps + 1 end end
        T.check(ok, ("%-10s %-10s monotonic, %d of %d steps heavier, others unchanged"):format(c, kname, steps, #inks - 1))
    end
end
T.check(lfs.attributes(SETTINGS, "modification") == settings_mtime, "settings file not written during the changes (deferred)")
T.closeReader(readerui)
T.finish()
