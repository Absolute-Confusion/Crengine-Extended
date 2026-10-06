-- The plugin coexists with KOReader's own Typography module: distinct module names, KOReader's
-- custom hyphenation still available, and the menu entry right after "Typography rules",
-- with the 9 categories and "Font cache" last; applying a category's setting leaves the menu
-- open (KOReader's own menu code); the font chooser tags monospace fonts as KOReader's font menu
-- does, and with the on-screen keyboard open, tapping a font still selects it. Also: the
-- native weight slider stays hidden,
-- the exit patch flushes settings then exits normally, and a PDF and a DjVu open normally, with no
-- plugin error logged.
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

print("== The menu stays open after applying a category's setting")
local UIManager = require("ui/uimanager")
local TouchMenu = require("ui/widget/touchmenu")
local closed = 0
local tab = { icon = "appbar.typeset" }
for i = 1, 9 do tab[i] = items[i] end
local touchmenu = TouchMenu:new{ width = 600, tab_item_table = { tab }, close_callback = function() closed = closed + 1 end }
local function top()
    local w = UIManager._window_stack[#UIManager._window_stack]
    return w and w.widget
end
-- Taps an attribute, then applies value through the dialog it shows (nil: only closes it)
local function tapAndApply(sub, k, value)
    touchmenu:onMenuSelect(sub[k])
    local dialog = top()
    if k == 3 then -- Slant Type: a button per kind
        for _, row in ipairs(dialog.buttons) do
            if value and row[1].text:find(value, 1, true) then row[1].callback() end
        end
        if top() == dialog then UIManager:close(dialog) end
    else -- Font Face: font chooser; Font Weight, Decoration Weight: number dialogs
        if value then
            dialog.value = value
            dialog.callback(dialog) -- what SpinWidget does on OK
        end
        UIManager:close(dialog)
    end
end
local stays_open, shows_value = true, true
for i = 1, 9 do
    touchmenu:onMenuSelect(items[i])
    local sub = touchmenu.item_table
    tapAndApply(sub, 1, nil)
    for k, v in pairs({ [2] = { 625, 400 }, [3] = { "synthetic*", "Italic" }, [4] = { 250, 100 } }) do
        tapAndApply(sub, k, v[1])
        if not sub[k].text_func():find(tostring(v[1]), 1, true) then shows_value = false end
        tapAndApply(sub, k, v[2]) -- back to the default
    end
    if closed > 0 then stays_open = false end
    touchmenu:backToUpperMenu()
end
T.check(stays_open and closed == 0, "all 9 categories, all 4 settings: the menu stays open after applying")
T.check(shows_value, "the menu shows the applied value")

print("== Font chooser: monospace fonts tagged as in KOReader's font menu")
local cre = require("document/credocument"):engineInit()
local lookup = cre.getFontFaceFilenameAndFaceIndex
local lookups = 0
cre.getFontFaceFilenameAndFaceIndex = function(...) lookups = lookups + 1; return lookup(...) end
local chooser = require("fontchooser"):new{ title = "x", current_font = "Droid Sans Mono" }
T.check(lookups <= 2 * chooser.menu.perpage, ("opening it looks up only the fonts shown (%d lookups, %d fonts)"):format(lookups, #chooser.all_fonts))
cre.getFontFaceFilenameAndFaceIndex = lookup
local M = "\u{1D39}"
local same, mono, proportional = true, 0, 0
for _, item in ipairs(chooser:getMenuItems(chooser.all_fonts)) do
    local font = item.text_func():gsub(" " .. M, ""):gsub(" %(Current%)$", "")
    -- KOReader's rule (readerfont.lua): the regular face, else the italic one
    local _, _, is_monospace = lookup(font)
    if is_monospace == nil then _, _, is_monospace = lookup(font, nil, true) end
    local tagged = item.text_func():find(M, 1, true) ~= nil
    if font ~= "(Use main font)" then
        if tagged ~= (is_monospace == true) then same = false; print("      differs: " .. font) end
        if tagged then mono = mono + 1 else proportional = proportional + 1 end
    elseif tagged then same = false
    end
end
T.check(same and mono > 0 and proportional > 0, ("tags match KOReader's rule for every font (%d monospace, %d not)"):format(mono, proportional))
chooser:filterFonts("droid sans mono")
T.check(chooser.menu.item_table[1].text_func() == "Droid Sans Mono " .. M .. " (Current)", "a search keeps the tag: " .. chooser.menu.item_table[1].text_func())
chooser:onCloseWidget()

print("== Font chooser with the on-screen keyboard open (touch devices)")
G_reader_settings:makeTrue("virtual_keyboard_enabled")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local time = require("ui/time")
local function tap(x, y)
    UIManager:sendEvent(Event:new("Gesture", { ges = "tap", pos = Geom:new{ x = x, y = y, w = 0, h = 0 }, time = time.now() }))
    fastforward_ui_events()
end
local function inStack(w)
    for _, win in ipairs(UIManager._window_stack) do if win.widget == w then return true end end
    return false
end
-- Opens the chooser and its keyboard, as a tap in the search field does
local function openWithKeyboard()
    local c = { picked = nil }
    c.chooser = require("fontchooser"):new{ title = "x", current_font = "", onConfirm = function(f) c.picked = f end }
    UIManager:show(c.chooser)
    UIManager:forceRePaint()
    c.chooser.search_input:onShowKeyboard()
    UIManager:forceRePaint()
    c.keyboard = c.chooser.search_input.keyboard
    return c
end
local c = openWithKeyboard()
T.check(c.keyboard and top() == c.keyboard, "the keyboard is shown above the font list")
local kd = c.keyboard.dimen
tap(kd.x + math.floor(kd.w / 2), kd.y + math.floor(kd.h / 3))
T.check(c.picked == nil and inStack(c.chooser) and c.chooser.search_input:getText() ~= "",
        "a tap on the keyboard types (" .. c.chooser.search_input:getText() .. "), it selects no font")
c.chooser.search_input:setText("")
c.chooser:filterFonts("")
UIManager:forceRePaint()
local row = c.chooser.menu.item_group[3].dimen
tap(row.x + 20, row.y + math.floor(row.h / 2))
T.check(c.picked ~= nil, "a tap on a font with the keyboard open selects it (" .. tostring(c.picked) .. ")")
T.check(not inStack(c.chooser) and not inStack(c.keyboard), "the font list and its keyboard are both closed")
c = openWithKeyboard()
local back = c.chooser.menu.custom_title_bar[1].dimen
tap(back.x + math.floor(back.w / 2), back.y + math.floor(back.h / 2))
T.check(c.picked == nil and not inStack(c.chooser) and not inStack(c.keyboard), "Back with the keyboard open closes both, selecting nothing")
G_reader_settings:delSetting("virtual_keyboard_enabled")
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

print("== PDF, DjVu")
G_reader_settings:saveSetting(T.weightProp("serif"), 500)
G_reader_settings:makeTrue("advancedtypography_no_document_cache")
-- KOReader logs (and otherwise ignores) an error in a plugin's handler: none from the plugin
local logger = require("logger")
local log_err = logger.err
local plugin_errors = {}
logger.err = function(...)
    local msg = table.concat({ ... }, " ")
    if msg:find("advancedtypography", 1, true) then table.insert(plugin_errors, msg) end
    return log_err(...)
end
for _, file in ipairs({ "sample.pdf", "djvu3spec.djvu" }) do
    local book = T.BOOKS .. "/" .. file
    os.execute(("cp spec/front/unit/data/%s %q"):format(file, book))
    local ok, err = pcall(function() T.closeReader(T.openReader(book)) end)
    T.check(ok, file .. " opens and closes normally with the plugin's settings saved" .. (ok and "" or (": " .. tostring(err))))
end
logger.err = log_err
T.check(#plugin_errors == 0, ("no plugin error logged (%d)%s"):format(#plugin_errors, plugin_errors[1] and (": " .. plugin_errors[1]) or ""))
T.finish()
