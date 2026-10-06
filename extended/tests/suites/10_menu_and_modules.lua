-- The plugin coexists with KOReader's own Typography module: distinct module names, KOReader's
-- custom hyphenation still available, and the menu entry right after "Typography rules",
-- with the 9 categories and "Font cache" last. Also: the native weight slider stays hidden,
-- the exit patch flushes settings then exits normally, and a PDF opens normally.
local T = dofile(os.getenv("AT_TESTS") .. "/lib/common.lua")
T.init(true)
G_reader_settings:saveSetting("hyph_user_dict", true)

local readerui = T.openReader(T.writeHtml("menu", "<html><body><p>x</p></body></html>"))
T.check(readerui.typography.name == "readertypography" and readerui.advancedtypography.name == "readeradvancedtypography",
        "distinct modules: " .. tostring(readerui.typography.name) .. " / " .. tostring(readerui.advancedtypography.name))
T.check(readerui.userhyph:isAvailable() == true, "KOReader's custom hyphenation rules available")
readerui.menu:setUpdateItemTable()
local found = false
for _, tab in ipairs(readerui.menu.tab_item_table) do
    local texts = {}
    for _, item in ipairs(tab) do table.insert(texts, item.text or (item.text_func and item.text_func()) or "") end
    local joined = table.concat(texts, " | ")
    if joined:find("Advanced Typography Settings", 1, true) then
        found = true
        T.check(joined:find("Typography rules: [^|]+ | Advanced Typography Settings") ~= nil, "menu entry right after Typography rules")
    end
end
T.check(found, "menu entry present")
local menu_items = {}
readerui.advancedtypography:addToMainMenu(menu_items)
local items = menu_items.advanced_typography.sub_item_table_func()
T.check(#items == 11 and items[10].text == "Font cache" and items[11].text == "No document cache",
        ("9 categories, then Font cache, then No document cache last (%d entries)"):format(#items))
T.closeReader(readerui)

print("== Native weight slider")
local creoptions = require("ui/data/creoptions")
local hidden
for _, category in ipairs(creoptions) do
    for _, option in ipairs(category.options or {}) do
        if option.name == "font_base_weight" then hidden = option.show_func() == false end
    end
end
T.check(hidden == true, "KOReader's own font weight slider hidden (the plugin's weights replace it)")

print("== Exit patch")
local Device = require("device")
local saved_exit, saved_close = Device.exit, G_reader_settings.close
local got_device, got_arg, flushed
Device._typography_exit_patched = nil
Device.exit = function(dev, arg) got_device, got_arg = dev, arg end
G_reader_settings.close = function() flushed = true end
readerui.advancedtypography._patchDeviceExit({})
Device:exit("code")
T.check(got_device == Device and got_arg == "code" and flushed == true, "settings flushed, then the original exit called with the same arguments")
Device.exit, G_reader_settings.close = saved_exit, saved_close

print("== PDF")
G_reader_settings:saveSetting(T.weightProp("serif"), 500)
local pdf = T.BOOKS .. "/sample.pdf"
os.execute(("cp spec/front/unit/data/sample.pdf %q"):format(pdf))
local ok, err = pcall(function() T.closeReader(T.openReader(pdf)) end)
T.check(ok, "a PDF opens and closes normally with the plugin's settings saved" .. (ok and "" or (": " .. tostring(err))))
T.finish()
