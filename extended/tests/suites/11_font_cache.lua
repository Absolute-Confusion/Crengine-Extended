-- The font cache (cache/fontlist/crengine_fonts.dat), over several KOReader startups (each a new
-- process): a startup from the cache knows exactly the same fonts as one without it, the cache
-- is only rewritten when font files are added, changed or removed, and those changes are seen.
-- Then the plugin's Font cache menu: size, date, count, Clear and Rebuild.
local T = dofile(os.getenv("AT_TESTS") .. "/lib/common.lua")
T.init(true)
local lfs = require("libs/libkoreader-lfs")
local CACHE = require("datastorage"):getDataDir() .. "/cache/fontlist/crengine_fonts.dat"
local FONTS = os.getenv("XDG_DATA_HOME") .. "/fonts"
local EXTRA = T.TESTS .. "/fonts-extra/CacheTest-Regular.ttf"
local PAST = os.time() - 3600

local function read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end
local n = 0
local function startup(label)
    n = n + 1
    local out = ("%s/startup_%d_%s.txt"):format(T.WORK, n, label)
    local ok = os.execute(("./luajit %q %q > %q 2>&1"):format(T.TESTS .. "/lib/startup.lua", out, out .. ".log"))
    T.check(ok == 0 or ok == true, "startup " .. label .. " ran", true)
    return read(out) or ""
end
local function knows(registry, family) return registry:find("\n" .. family .. "\t", 1, true) ~= nil or registry:sub(1, #family + 1) == family .. "\t" end
local function cacheMtime() return lfs.attributes(CACHE, "modification") end
local function age() lfs.touch(CACHE, PAST, PAST) end

print("== Startups")
os.remove(CACHE)
local cold = startup("without_cache")
T.check(cacheMtime() ~= nil, "cache created at the first startup")
T.check(knows(cold, "TestSlab") and knows(cold, "GrpWide Expanded"), "fonts known")
age()
local warm = startup("from_cache")
T.check(warm == cold, "startup from the cache knows exactly the same fonts (files, faces, former names)")
T.check(cacheMtime() == PAST, "cache not rewritten when no font changed")
-- Proof that startups use the cache: a family renamed in the cache file shows up renamed
local content = read(CACHE)
local edited, count = content:gsub("\tUprFam\tUprFam\tUprFam\t", "\tCachedName\tCachedName\tCachedName\t")
T.writeFile(CACHE, edited)
local from_edited = startup("edited_cache")
T.check(count == 2 and knows(from_edited, "CachedName") and not knows(from_edited, "UprFam"),
        "startups really read the cache (a family renamed in it shows up renamed)")
T.writeFile(CACHE, content)
age()

os.execute(("cp %q %q"):format(EXTRA, FONTS .. "/CacheTest-Regular.ttf"))
local added = startup("font_added")
T.check(knows(added, "CacheTestFamily"), "added font file seen")
T.check(cacheMtime() ~= PAST, "cache rewritten after a font was added")

age()
os.execute(("cp %q %q"):format(FONTS .. "/UprFam-Bold.ttf", FONTS .. "/CacheTest-Regular.ttf"))
local changed = startup("font_changed")
T.check(not knows(changed, "CacheTestFamily"), "changed font file re-read (it's now another font)")
T.check(cacheMtime() ~= PAST, "cache rewritten after a font was changed")

age()
os.remove(FONTS .. "/CacheTest-Regular.ttf")
local removed = startup("font_removed")
T.check(removed == cold, "removed font file gone: same fonts as at first")
T.check(cacheMtime() ~= PAST, "cache rewritten after a font was removed")

os.remove(CACHE)
local rebuilt = startup("rebuilt")
T.check(rebuilt == cold, "a rebuilt cache gives the same fonts")

print("== Font cache menu")
local UIManager = require("ui/uimanager")
local readerui = T.openReader(T.writeHtml("cache_menu", "<html><body><p>x</p></body></html>"))
local menu_items = {}
readerui.advancedtypography:addToMainMenu(menu_items)
local items = menu_items.advanced_typography.sub_item_table_func()
local sub = items[10].sub_item_table -- Font cache
for i = 1, 3 do print("      " .. sub[i].text_func()) end
T.check(sub[1].text_func():find(require("util").getFriendlySize(lfs.attributes(CACHE, "size")), 1, true) ~= nil, "size shown matches the file")
T.check(sub[2].text_func():find(os.date("%Y-%m-%d %H:%M", cacheMtime()), 1, true) ~= nil, "date shown matches the file")
T.check(sub[3].text_func():match("^Fonts: %d+ %(%d+ files%)$") ~= nil, "font count shown")
sub[4].callback(nil)
local dialog = UIManager._window_stack[#UIManager._window_stack].widget
T.check(lfs.attributes(CACHE, "mode") == "file", "Clear: nothing deleted before confirming")
dialog.ok_callback(); UIManager:close(dialog)
T.check(lfs.attributes(CACHE, "mode") == nil, "Clear: cache deleted after confirming")
T.check(sub[1].text_func() == "Size: (not created yet)" and sub[4].enabled_func() == false, "menu then shows no cache, Clear disabled")
T.writeFile(CACHE, "x")
local asked
UIManager.askForRestart = function(_, msg) asked = msg end
sub[5].callback(nil)
T.check(lfs.attributes(CACHE, "mode") == nil and asked ~= nil, "Rebuild: cache deleted and a restart asked for")
T.closeReader(readerui)
T.finish()
