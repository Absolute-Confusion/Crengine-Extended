-- Extra font folders: crengine also registers the fonts of the folders set there (subfolders too,
-- unless left out), over several KOReader startups (each a new process), and with the existing
-- caching: adding fonts writes the font cache once, then startups write nothing (also when crengine
-- starts before the plugin is loaded, as when KOReader opens a book at startup); leaving out
-- subfolders or removing a folder rebuilds it, so it keeps only the fonts crengine has; a rebuild
-- includes them. A folder KOReader already reads, or one already in the list, isn't added. The
-- fonts work in KOReader's own font menu, the plugin's Font Face list and slant greying. Changing
-- the list writes no setting until KOReader saves. Slant greying ignores the font cache's records
-- of fonts crengine didn't register.
local T = dofile(os.getenv("AT_TESTS") .. "/lib/common.lua")
T.init(true)
local lfs = require("libs/libkoreader-lfs")
local UIManager = require("ui/uimanager")
local CACHE = require("datastorage"):getDataDir() .. "/cache/fontlist/crengine_fonts.dat"
local SETTING = "advancedtypography_extra_font_folders"
local EXTRA = T.WORK .. "/extra"

lfs.mkdir(EXTRA)
lfs.mkdir(EXTRA .. "/sub")
os.execute(("cp %q %q"):format(T.TESTS .. "/fonts-extra/CacheTest-Regular.ttf", EXTRA .. "/top.ttf"))
os.execute(("cp %q %q"):format(T.TESTS .. "/fonts-extra/FolderTest-Regular.ttf", EXTRA .. "/sub/deep.ttf"))

local n = 0
local function run(script, label, plugin)
    n = n + 1
    local out = ("%s/extra_%d_%s.txt"):format(T.WORK, n, label)
    -- The folders as saved (each process starts with fresh test settings: passed to it)
    local folders = {}
    for _, folder in ipairs(G_reader_settings:readSetting(SETTING) or {}) do
        table.insert(folders, folder.path .. "|" .. (folder.recursive == false and "0" or "1"))
    end
    local ok = os.execute(("AT_EXTRA_FONT_FOLDERS=%q AT_STARTUP_PLUGIN=%s ./luajit %q %q > %q 2>&1"):format(
        table.concat(folders, ";"), plugin or "first", T.TESTS .. "/lib/" .. script, out, out .. ".log"))
    T.check(ok == 0 or ok == true, label .. " ran", true)
    local f = io.open(out)
    local s = f and f:read("*a") or ""
    if f then f:close() end
    return s
end
-- A startup: the families crengine knows
local function startup(label, plugin)
    local s = run("startup.lua", label, plugin)
    local families = {}
    for line in s:gmatch("[^\n]+") do families[line:match("^[^\t]+")] = true end
    return families, s
end
local function inode() return lfs.attributes(CACHE, "ino") end
local function cacheHas(family)
    local f = io.open(CACHE)
    if not f then return false end
    local s = f:read("*a")
    f:close()
    return s:find(family, 1, true) ~= nil
end
local function both(families) return families.CacheTestFamily and families.FolderTestFamily end
local function neither(families) return not families.CacheTestFamily and not families.FolderTestFamily end
local function save() G_reader_settings:flush() end -- as KOReader saves

print("== Without extra folders")
local fonts = startup("base")
T.check(neither(fonts) and lfs.attributes(CACHE, "mode") == "file", "crengine doesn't know the test fonts; font cache created")

print("== A folder added, with its subfolders")
G_reader_settings:saveSetting(SETTING, { { path = EXTRA, recursive = true } })
save()
local ino = inode()
fonts = startup("added")
T.check(both(fonts), "crengine knows the folder's font and its subfolder's")
T.check(inode() ~= ino and cacheHas("CacheTestFamily") and cacheHas("FolderTestFamily"), "the font cache is written once, with them")
ino = inode()
local again, text1 = startup("again")
T.check(both(again) and inode() == ino, "next startup: the same fonts, font cache not written")
local late, text2 = startup("book_first", "last")
T.check(both(late) and text2 == text1 and inode() == ino,
        "crengine started before the plugin (a book opened at startup): the same fonts, font cache not written")

print("== In the reader")
local r = run("extra_fonts_reader.lua", "reader")
T.check(r:find("koreader_font_menu\tFolderTestFamily", 1, true) ~= nil, "KOReader's own font menu accepts an extra folder's font")
T.check(r:find("font_face_list\ttrue", 1, true) ~= nil, "the plugin's Font Face list has them")
T.check(r:find("slant_kinds\ttrue", 1, true) ~= nil, "slant greying knows them (from the font cache)")

print("== The menu")
local readerui = T.openReader(T.writeHtml("extra_menu", "<html><body><p>x</p></body></html>"))
local menu_items = {}
readerui.advancedtypography:addToMainMenu(menu_items)
local entry = menu_items.advanced_typography.sub_item_table_func()[11]
T.check(entry.text == "Extra font folders", "its menu entry, after Font cache")
local items = entry.sub_item_table_func()
T.check(items[1].text == "Add folder…" and items[2].text == EXTRA and #items == 2, "Add folder, then the folder")
local function top() local w = UIManager._window_stack[#UIManager._window_stack]; return w and w.widget end
local function closeTop() local w = top(); if w then UIManager:close(w) end end
-- Adding through the folder chooser (its onConfirm, as when a folder is chosen)
local function add(path)
    items[1].callback()
    local chooser = top()
    chooser.onConfirm(path)
    closeTop() -- the message or restart question
    UIManager:close(chooser)
end
local before = G_reader_settings:readSetting(SETTING)[1].path
add(T.WORK .. "/xdg/fonts")
add(EXTRA)
T.check(#G_reader_settings:readSetting(SETTING) == 1 and before == EXTRA, "a folder KOReader reads, or one already listed, isn't added")
local marker = io.open(G_reader_settings.file):read("*a")
lfs.mkdir(T.WORK .. "/extra2")
add(T.WORK .. "/extra2")
items = entry.sub_item_table_func()
T.check(#G_reader_settings:readSetting(SETTING) == 2 and items[3].text:find("extra2", 1, true) ~= nil, "another folder added, and listed")
T.check(io.open(G_reader_settings.file):read("*a") == marker, "adding writes no setting until KOReader saves (deferred)")
-- (extra2 is empty: it adds no font)

print("== Subfolders left out")
local folder_items = items[2].sub_item_table
T.check(folder_items[1].text == "Include subfolders" and folder_items[1].checked_func(), "Include subfolders, on")
folder_items[1].callback()
closeTop()
T.check(not folder_items[1].checked_func() and lfs.attributes(CACHE, "mode") == nil, "off: the font cache is deleted (rebuilt at the next start)")
save()
fonts = startup("no_subfolders")
T.check(fonts.CacheTestFamily and not fonts.FolderTestFamily, "only the folder's own font")
T.check(cacheHas("CacheTestFamily") and not cacheHas("FolderTestFamily"), "the rebuilt font cache has only the fonts crengine has")
folder_items[1].callback()
closeTop()
T.check(folder_items[1].checked_func() and lfs.attributes(CACHE, "mode") == "file", "on again: the font cache is kept (fonts are only added)")
save()
T.check(both(startup("subfolders_again")), "the subfolder's font again")

print("== A folder removed")
items = entry.sub_item_table_func()
items[2].sub_item_table[2].callback()
local confirm = top()
confirm.ok_callback()
UIManager:close(confirm)
closeTop()
items = entry.sub_item_table_func()
T.check(#items == 2 and items[2].text:find("extra2", 1, true) ~= nil and lfs.attributes(CACHE, "mode") == nil,
        "removed from the list, the font cache deleted")
save()
fonts = startup("removed")
T.check(neither(fonts) and not cacheHas("CacheTestFamily") and not cacheHas("FolderTestFamily"),
        "crengine doesn't know its fonts, and the rebuilt font cache has none of them")

print("== Rebuild with an extra folder")
add(EXTRA)
save()
os.remove(CACHE) -- as the Font cache menu's Rebuild does
fonts = startup("rebuild_book_first", "last")
T.check(both(fonts) and cacheHas("CacheTestFamily") and cacheHas("FolderTestFamily"),
        "rebuilt while crengine starts before the plugin: it has them")
ino = inode()
T.check(both(startup("after_rebuild", "last")) and inode() == ino, "next startup: font cache not written")

print("== Fonts in the cache that crengine didn't register")
-- As after KOReader's system fonts are turned off: the folder no longer set, the font cache kept
-- (with records of its fonts, whose files are still there)
G_reader_settings:delSetting(SETTING)
save()
fonts = startup("unset_cache_kept")
T.check(neither(fonts) and cacheHas("FolderTestFamily"), "crengine doesn't register them, the font cache still has their records")
r = run("extra_fonts_reader.lua", "reader_unset")
T.check(r:find("slant_kinds\tfalse", 1, true) ~= nil, "slant greying leaves them out (only fonts crengine registered)")
T.check(r:find("slant_kinds_testslab\ttrue", 1, true) ~= nil, "registered families keep their slant kinds")
T.closeReader(readerui)
T.finish()
