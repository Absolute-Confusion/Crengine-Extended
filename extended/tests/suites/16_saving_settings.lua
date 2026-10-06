-- "Saving settings": KOReader writes its settings file (settings.reader.lua) when a book is opened
-- from the file browser or closed, and when the device suspends; each can be turned off, and then
-- that write is skipped (the settings stay in memory) while the book's own file is still written.
-- At exit, and with KOReader's explicit "Save book metadata", the settings are always written.
-- The autosave interval is KOReader's own setting. Turning the options on or off writes nothing.
local T = dofile(os.getenv("AT_TESTS") .. "/lib/common.lua")
T.init(true)
local lfs = require("libs/libkoreader-lfs")
local SAVE_ON_BOOK = "advancedtypography_save_on_book"
local SAVE_ON_SUSPEND = "advancedtypography_save_on_suspend"
local Device = require("device")

-- Whether the settings file on disk has the marker value (a setting changed in memory only)
local marker = 0
local function mark()
    marker = marker + 1
    G_reader_settings:saveSetting("at_test_marker", marker)
end
local function onDisk()
    local f = io.open(G_reader_settings.file, "rb")
    local s = f and f:read("*a") or ""
    if f then f:close() end
    return s:find('%["at_test_marker"%] = ' .. marker .. ',') ~= nil
end
local book = T.writeHtml("saving", "<html><body><p>Saving settings test.</p></body></html>")
local sidecar = require("docsettings"):getSidecarDir(book) .. "/metadata.html.lua" -- the book's own file
local UIManager = require("ui/uimanager")

print("== The menu")
local readerui = T.openReader(book)
readerui.menu:setUpdateItemTable() -- KOReader's menu, as when it's opened: it sets its autosave default
local menu_items = {}
readerui.advancedtypography:addToMainMenu(menu_items)
local entry = menu_items.advanced_typography.sub_item_table_func()[13]
local sub = entry.sub_item_table
T.check(entry.text == "Saving settings" and sub[1].text == "Save when opening or closing a book"
        and sub[2].text == "Save when suspending" and sub[4].text == "Always saved when KOReader exits",
        "Saving settings, last: book, suspend, autosave, and a note that exit always saves")
T.check(sub[1].checked_func() and sub[2].checked_func() and sub[3].text_func() == "Autosave: Every 15 minutes",
        "by default KOReader's behaviour: both on, autosave every 15 minutes (" .. sub[3].text_func() .. ")")
G_reader_settings:flush()
mark()
sub[1].callback(); sub[2].callback()
T.check(not sub[1].checked_func() and not sub[2].checked_func(), "both turned off")
local autosave = sub[3].sub_item_table
autosave[7].callback()
T.check(G_reader_settings:readSetting("auto_save_settings_interval_minutes") == 240 and sub[3].text_func() == "Autosave: Every 4 hours",
        "autosave every 4 hours sets KOReader's own setting (240 minutes)")
autosave[1].callback()
T.check(G_reader_settings:readSetting("auto_save_settings_interval_minutes") == false and sub[3].text_func() == "Autosave: Off",
        "autosave off sets KOReader's own setting (false: only on close and suspend, in its words)")
T.check(not onDisk(), "turning them on or off writes nothing (deferred)")

print("== Closing a book")
mark()
os.remove(sidecar)
T.closeReader(readerui)
T.check(not onDisk(), "off: closing a book doesn't write the settings file")
T.check(lfs.attributes(sidecar, "mode") == "file", "the book's own file is still written")
G_reader_settings:delSetting(SAVE_ON_BOOK)
readerui = T.openReader(book)
mark()
T.closeReader(readerui)
T.check(onDisk(), "on (default): closing a book writes it, as KOReader does")

print("== Opening a book from the file browser")
local FileManager = require("apps/filemanager/filemanager")
G_reader_settings:makeFalse(SAVE_ON_BOOK)
FileManager:showFiles(T.BOOKS)
mark()
FileManager.instance:onClose()
T.check(not onDisk(), "off: leaving the file browser to open a book doesn't write it")
G_reader_settings:delSetting(SAVE_ON_BOOK)
FileManager:showFiles(T.BOOKS)
mark()
FileManager.instance:onClose()
T.check(onDisk(), "on: it writes it, as KOReader does")

print("== Suspending")
readerui = T.openReader(book)
UIManager:show(readerui) -- a suspend notifies the windows shown
G_reader_settings:makeFalse(SAVE_ON_SUSPEND)
mark()
os.remove(sidecar)
Device:_beforeSuspend(false)
Device:_afterResume(false)
T.check(not onDisk(), "off: suspending doesn't write it")
T.check(lfs.attributes(sidecar, "mode") == "file", "the book's own file is still written")
G_reader_settings:delSetting(SAVE_ON_SUSPEND)
mark()
Device:_beforeSuspend(false)
Device:_afterResume(false)
T.check(onDisk(), "on: suspending writes it, as KOReader does")

print("== Always written")
G_reader_settings:makeFalse(SAVE_ON_BOOK)
G_reader_settings:makeFalse(SAVE_ON_SUSPEND)
mark()
readerui:onFlushSettings(true)
T.check(onDisk(), "both off: KOReader's \"Save book metadata\" action still writes it")
mark()
local saved_exit = Device.exit
Device._typography_exit_patched = nil
Device.exit = function() end -- the device's own teardown, not run here
readerui.advancedtypography._patchDeviceExit({})
Device:exit()
T.check(onDisk(), "both off: exiting KOReader still writes it")
Device.exit = saved_exit
G_reader_settings:delSetting(SAVE_ON_BOOK)
G_reader_settings:delSetting(SAVE_ON_SUSPEND)
T.closeReader(readerui)
T.finish()
