-- The 27 per-category settings (weight, slant type and decoration weight x 9 categories), live,
-- through the plugin's menu, in an EPUB with partial rerendering:
--   - each change shows at once, exactly as after opening the book fresh with it,
--   - it changes only its own category's text, and changing it back restores it exactly,
--   - nothing is written to disk until the book is closed (deferred writes),
--   - after closing, all 27 are on disk, and reopening applies them and shows the same page.
local T = dofile(os.getenv("AT_TESTS") .. "/lib/common.lua")
T.init(true)
local LuaSettings = require("luasettings")
local lfs = require("libs/libkoreader-lfs")
local SETTINGS = G_reader_settings.file
T.useFont("TestSlab")

local LINES = 3 -- per category: upright regular, slanted regular, slanted bold (all underlined + struck)
local kinds = {
    weight = { prop = T.weightProp, default = 400, value = 700, int = true },
    slant = { prop = T.slantProp, default = "Italic", value = "Oblique" },
    decoration = { prop = T.decorationProp, default = 100, value = 300, int = true },
}
local kind_order = { "weight", "slant", "decoration" }
for _, c in ipairs(T.CATEGORIES) do
    for _, k in ipairs(kind_order) do G_reader_settings:saveSetting(kinds[k].prop(c), kinds[k].default) end
end
G_reader_settings:flush()

local paras = {}
for _, c in ipairs(T.CATEGORIES) do
    local ff = c == "base" and "'TestSlab'" or ("'TestSlab', " .. c)
    for _, extra in ipairs({ "", "font-style: italic; ", "font-style: italic; font-weight: bold; " }) do
        table.insert(paras, ('<p style="font-family: %s; %stext-decoration: underline line-through; font-size: 12px; margin: 0.45em 0">%s lorem amet</p>'):format(ff, extra, c))
    end
end
local book = T.writeEpub("live_27_settings", table.concat(paras))

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
local function categoryOf(line) return math.floor((line - 1) / LINES) + 1 end

-- 1. Fresh-open references: all defaults, and each of the 27 changed alone
open()
local base = snapshot()
if not T.check(#lines == #T.CATEGORIES * LINES, ("%d text lines found (%d)"):format(#T.CATEGORIES * LINES, #lines)) then T.finish() end
T.check(readerui.document:isPartialRerenderingEnabled(), "partial rerendering enabled (as in the app)")
local ref = {}
for ci, c in ipairs(T.CATEGORIES) do
    ref[c] = {}
    for _, k in ipairs(kind_order) do
        G_reader_settings:saveSetting(kinds[k].prop(c), kinds[k].value)
        open()
        ref[c][k] = snapshot()
        G_reader_settings:saveSetting(kinds[k].prop(c), kinds[k].default)
        local visible = false
        for i = 1, #lines do if categoryOf(i) == ci and ref[c][k][i] ~= base[i] then visible = true end end
        T.check(visible, ("reference: %s %s change is visible"):format(c, k), true)
    end
end
open()

-- 2. Live changes through the menu
local live_ok = 0
for ci, c in ipairs(T.CATEGORIES) do
    for _, k in ipairs(kind_order) do
        T.menuSet(readerui, c, k, kinds[k].value)
        local now = snapshot()
        local ok = true
        for i = 1, #lines do
            if categoryOf(i) == ci then
                ok = T.check(now[i] == ref[c][k][i], ("%s %s live: line %d not as after a fresh open"):format(c, k, i), true) and ok
            else
                ok = T.check(now[i] == base[i], ("%s %s live: changed line %d (%s)"):format(c, k, i, T.CATEGORIES[categoryOf(i)]), true) and ok
            end
        end
        T.menuSet(readerui, c, k, kinds[k].default)
        local back = snapshot()
        for i = 1, #lines do
            ok = T.check(back[i] == base[i], ("%s %s changed back: line %d not restored"):format(c, k, i), true) and ok
        end
        if ok then live_ok = live_ok + 1 end
    end
end
T.check(live_ok == 27, ("live change, independence and change back: %d/27 settings ok"):format(live_ok))

-- 3. Deferred writes, saving and reloading: all 27 set to different values, live
local mtime_before = lfs.attributes(SETTINGS, "modification")
local target = {}
for ci, c in ipairs(T.CATEGORIES) do
    target[c] = {
        weight = 400 + 25 * ci,
        slant = ({ "Oblique", "synthetic*", "Italic" })[ci % 3 + 1],
        decoration = 100 + 25 * ci,
    }
    for _, k in ipairs(kind_order) do T.menuSet(readerui, c, k, target[c][k]) end
end
local before_close = snapshot()
T.check(lfs.attributes(SETTINGS, "modification") == mtime_before, "settings file not written during the live changes (deferred)")
local in_memory = 0
for _, c in ipairs(T.CATEGORIES) do
    for _, k in ipairs(kind_order) do
        if G_reader_settings:readSetting(kinds[k].prop(c)) == target[c][k] then in_memory = in_memory + 1 end
    end
end
T.check(in_memory == 27, ("all changes kept in memory: %d/27"):format(in_memory))
T.closeReader(readerui); readerui = nil
local on_disk, saved = LuaSettings:open(SETTINGS), 0
for _, c in ipairs(T.CATEGORIES) do
    for _, k in ipairs(kind_order) do
        if on_disk:readSetting(kinds[k].prop(c)) == target[c][k] then saved = saved + 1 end
    end
end
T.check(saved == 27, ("on disk after closing the book: %d/27"):format(saved))
-- Reload as a new session would
G_reader_settings = LuaSettings:open(SETTINGS)
open()
local cdoc, applied = readerui.document._document, 0
for _, c in ipairs(T.CATEGORIES) do
    for _, k in ipairs(kind_order) do
        local p = kinds[k].prop(c)
        local got = kinds[k].int and cdoc:getIntProperty(p) or cdoc:getStringProperty(p)
        if got == target[c][k] then applied = applied + 1 end
    end
end
T.check(applied == 27, ("applied to crengine after reloading: %d/27"):format(applied))
local after, same = snapshot(), 0
for i = 1, #lines do if after[i] == before_close[i] then same = same + 1 end end
T.check(same == #lines, ("page after reloading identical to before closing: %d/%d lines"):format(same, #lines))
T.closeReader(readerui)
T.finish()
