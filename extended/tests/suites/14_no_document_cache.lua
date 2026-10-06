-- "No document cache": with it on, opening and closing a book writes no cache file (and
-- settings changes still apply at once, without partial rerendering); turning it on deletes the
-- existing book caches (a book open at that moment leaves none when it closes, and crengine
-- recreates none for books it had cached), writing no setting to disk; turning it off caches books
-- again. crengine's font cache keeps working either way.
local T = dofile(os.getenv("AT_TESTS") .. "/lib/common.lua")
T.init(true)
local lfs = require("libs/libkoreader-lfs")
local UIManager = require("ui/uimanager")
local DataStorage = require("datastorage")
local SETTINGS = G_reader_settings.file
local CACHEDIR = DataStorage:getDataDir() .. "/cache/cr3cache"
local SETTING = "advancedtypography_no_document_cache"
T.useFont("TestSlab")

-- Cache files of this suite's books (other suites' books share the folder)
local function bookCaches()
    local n = 0
    if lfs.attributes(CACHEDIR, "mode") == "directory" then
        for f in lfs.dir(CACHEDIR) do
            if f:match("^no_cache_.*%.cr3$") then n = n + 1 end
        end
    end
    return n
end
local function allBookCaches()
    local n = 0
    for f in lfs.dir(CACHEDIR) do
        if f:match("%.cr3$") then n = n + 1 end
    end
    return n
end
local paras = {}
for _, c in ipairs(T.CATEGORIES) do
    local ff = c == "base" and "'TestSlab'" or ("'TestSlab', " .. c)
    table.insert(paras, ('<p style="font-family: %s; font-size: 14px">%s lorem amet</p>'):format(ff, c))
end
local book1 = T.writeEpub("no_cache_1", table.concat(paras))
local book2 = T.writeEpub("no_cache_2", table.concat(paras))
local function menuEntry(readerui)
    local menu_items = {}
    readerui.advancedtypography:addToMainMenu(menu_items)
    local items = menu_items.advanced_typography.sub_item_table_func()
    return items[#items]
end

print("== Off (default): books are cached")
local readerui = T.openReader(book1)
T.check(readerui.document:hasCacheFile(), "the book has a cache file")
T.closeReader(readerui)
T.check(bookCaches() == 1, ("one book cache in cache/cr3cache (%d)"):format(bookCaches()))

print("== Turning it on, from the menu")
readerui = T.openReader(book1)
local entry = menuEntry(readerui)
T.check(entry.text == "No document cache" and entry.checked_func() == false, "last menu entry, unchecked")
G_reader_settings:flush()
local mtime = lfs.attributes(SETTINGS, "modification")
entry.callback(nil)
local dialog = UIManager._window_stack[#UIManager._window_stack].widget
T.check(G_reader_settings:isTrue(SETTING) == false, "nothing changed before confirming")
dialog.ok_callback(); UIManager:close(dialog)
T.check(G_reader_settings:isTrue(SETTING) and entry.checked_func() == true, "on after confirming, shown checked")
T.check(allBookCaches() == 0 and lfs.attributes(CACHEDIR, "mode") == "directory", "all existing book caches deleted (folder kept)")
T.check(lfs.attributes(SETTINGS, "modification") == mtime, "settings file not written by turning it on (deferred)")
T.closeReader(readerui)
T.check(bookCaches() == 0, ("the book open when turning it on leaves no cache when it closes (%d)"):format(bookCaches()))

print("== On: opening and closing books writes no cache")
local font_cache = DataStorage:getDataDir() .. "/cache/fontlist/crengine_fonts.dat"
readerui = T.openReader(book2)
T.check(not readerui.document:hasCacheFile(), "the book has no cache file")
T.check(not readerui.document:isPartialRerenderingEnabled(), "partial rerendering off (it needs a cache file)")
-- A live change still applies at once, as after a fresh open
local lines
local function snapshot(ui)
    local bb = T.paint(ui)
    lines = lines or T.findLines(bb)
    local h = T.linePrints(bb, lines)
    bb:free()
    return h
end
local before = snapshot(readerui)
T.menuSet(readerui, "serif", "weight", 800)
local live = snapshot(readerui)
T.closeReader(readerui)
readerui = T.openReader(book2)
local fresh = snapshot(readerui)
local serif_line = 2 -- base, serif, ...
T.check(live[serif_line] ~= before[serif_line] and live[serif_line] == fresh[serif_line], "a live weight change applies at once, as after a fresh open")
local others = true
for i = 1, #lines do if i ~= serif_line and live[i] ~= before[i] then others = false end end
T.check(others, "other categories unchanged")
T.menuSet(readerui, "serif", "weight", 400)
T.closeReader(readerui)
readerui = T.openReader(book1)
T.closeReader(readerui)
T.check(bookCaches() == 0, ("no book cache after opening and closing books (%d)"):format(bookCaches()))
T.check(lfs.attributes(font_cache, "mode") == "file", "crengine's font cache still there")

print("== Turning it off")
readerui = T.openReader(book1)
entry = menuEntry(readerui)
entry.callback(nil)
T.check(G_reader_settings:readSetting(SETTING) == nil and entry.checked_func() == false, "off: setting removed, shown unchecked")
T.closeReader(readerui)
readerui = T.openReader(book2)
T.check(readerui.document:hasCacheFile(), "books are cached again")
T.closeReader(readerui)
T.check(bookCaches() == 1, ("a book cache again (%d)"):format(bookCaches()))
T.finish()
