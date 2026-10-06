local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local creoptions = require("ui/data/creoptions")
local logger = require("logger")
local FontChooser = require("fontchooser") -- Our custom crash-free font chooser
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local CreDocument = require("document/credocument")
local DataStorage = require("datastorage")
local Event = require("ui/event")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local SlantInfo = require("slantinfo")
local _ = require("gettext")
local N_ = _.ngettext
local T = require("ffi/util").template

local Typography = WidgetContainer:extend{
    name = "advancedtypography",
    is_doc_only = true,
}

local CATEGORIES = {"base", "serif", "sans-serif", "cursive", "fantasy", "monospace", "emoji", "fangsong", "math"}

-- "No document cache": crengine keeps no cache file of opened books (see _buildNoDocumentCacheMenu())
local NO_DOCUMENT_CACHE = "advancedtypography_no_document_cache"

-- "Saving settings": whether KOReader writes its settings file (settings.reader.lua) when a book is
-- opened or closed, and when the device suspends (see _buildSavingSettingsMenu()); KOReader's own
-- autosave interval
local SAVE_ON_BOOK = "advancedtypography_save_on_book"
local SAVE_ON_SUSPEND = "advancedtypography_save_on_suspend"
local AUTOSAVE_MINUTES = "auto_save_settings_interval_minutes"

-- "Extra font folders": folders whose fonts crengine also registers, each { path = <real path>,
-- recursive = <false to leave out its subfolders> } (see _buildExtraFontFoldersMenu())
local EXTRA_FONT_FOLDERS = "advancedtypography_extra_font_folders"

-- Whether a font family is in crengine's font list
local cre_font_faces
local function isCreFontFace(face)
    if not cre_font_faces then
        cre_font_faces = {}
        for _, name in ipairs(require("document/credocument"):engineInit().getFontFaces()) do
            cre_font_faces[name] = true
        end
    end
    return cre_font_faces[face] == true
end

local function slantProp(category)
    return category == "base" and "font.italic.style.default" or ("crengine.generic." .. category .. ".font.italic.style")
end

-- Font used by a category: its own font-family font, or the main font
-- (as last given to crengine, tracked by _patchDocumentFonts())
local function categoryFont(document, category)
    local fonts = document._typography_family_fonts
    if category ~= "base" and fonts and fonts[category] and fonts[category] ~= "" then
        return fonts[category]
    end
    return document._typography_main_font
end

-- A category's slant type must exist in its font (the menu greys out the others):
-- when its font lacks it, switch that category to synthetic*
local function enforceSlantAvailability(document)
    if not document._typography_main_font or not document._typography_family_fonts then
        return -- fonts not all known yet
    end
    for _, category in ipairs(CATEGORIES) do
        local prop_name = slantProp(category)
        local value = G_reader_settings:readSetting(prop_name, "Italic")
        local kinds = SlantInfo.getFamilyKinds(categoryFont(document, category))
        if kinds and ((value == "Italic" and not kinds.italic) or (value == "Oblique" and not kinds.oblique)) then
            G_reader_settings:saveSetting(prop_name, "synthetic*")
            document._document:setStringProperty(prop_name, "synthetic*")
        end
    end
end

function Typography:init()
    self:_patchNativeFontWeight()
    self:_patchReaderFontGlobal()
    self:_patchDocumentFonts()
    self:_patchDeviceExit()
    self.ui.menu:registerToMainMenu(self)
end

function Typography:_patchDeviceExit()
    local Device = require("device")
    if not Device._typography_exit_patched then
        local old_exit = Device.exit
        Device.exit = function(device, ...)
            -- Ensure settings are flushed BEFORE the hardware/SDL teardown happens
            -- This fixes issues where abrupt emulator closure or crashes during teardown
            -- would prevent global settings from persisting reliably.
            if G_reader_settings and G_reader_settings.close then
                G_reader_settings:close()
            end
            if old_exit then
                return old_exit(device, ...)
            end
        end
        Device._typography_exit_patched = true
    end
end

-- Font faces are global for all 9 categories, like their other attributes:
-- KOReader's per-book font_face and font_family_fonts are neither read nor
-- saved, and a face picked in KOReader's own font menus becomes the global one.
function Typography:_patchReaderFontGlobal()
    local ReaderFont = require("apps/reader/modules/readerfont")
    if not ReaderFont._typography_patched then
        local old_onReadSettings = ReaderFont.onReadSettings
        function ReaderFont:onReadSettings(config, ...)
            config:delSetting("font_face")
            config:delSetting("font_family_fonts")
            return old_onReadSettings(self, config, ...)
        end
        local old_onSaveSettings = ReaderFont.onSaveSettings
        function ReaderFont:onSaveSettings(...)
            if old_onSaveSettings then old_onSaveSettings(self, ...) end
            if self.ui and self.ui.doc_settings then
                self.ui.doc_settings:delSetting("font_face")
                self.ui.doc_settings:delSetting("font_family_fonts")
            end
        end
        local old_onSetFont = ReaderFont.onSetFont
        function ReaderFont:onSetFont(face, ...)
            local ret = old_onSetFont(self, face, ...)
            -- KOReader only accepts a font file's own family name: also accept a family
            -- crengine named by width/spacing grouping (eg. "Iosevka Slab Expanded")
            if face and self.font_face ~= face and isCreFontFace(face) then
                self.font_face = face
                self.ui.document:setFontFace(face)
                self.ui:handleEvent(Event:new("UpdatePos"))
            end
            if face and self.font_face == face then
                G_reader_settings:saveSetting("cre_font", face)
            end
            return ret
        end
        local old_updateFontFamilyFonts = ReaderFont.updateFontFamilyFonts
        function ReaderFont:updateFontFamilyFonts(...)
            -- Per-book choices made in KOReader's font-family menu become global ones
            -- (a font sets it, false unsets it)
            if self.font_family_fonts and next(self.font_family_fonts) then
                local family_fonts = G_reader_settings:readSetting("cre_font_family_fonts", {})
                for family, font in pairs(self.font_family_fonts) do
                    family_fonts[family] = font or nil
                end
                G_reader_settings:saveSetting("cre_font_family_fonts", family_fonts)
                self.font_family_fonts = {}
            end
            return old_updateFontFamilyFonts(self, ...)
        end
        ReaderFont._typography_patched = true
    end
end

-- Track the fonts given to crengine (main font, font-family fonts), so each
-- category's font is known, and keep each category's slant type available in it.
-- This wraps this document's own methods: its call cache (CreDocument:setupCallCache())
-- has already copied the class ones into it when it was opened, before plugins load.
function Typography:_patchDocumentFonts()
    local document = self.ui.document
    if not document or not document.setFontFamilyFontFaces then
        return -- not a crengine document
    end
    local old_setFontFace = document.setFontFace
    document.setFontFace = function(doc, new_font_face, ...)
        local ret = old_setFontFace(doc, new_font_face, ...)
        if new_font_face then
            doc._typography_main_font = new_font_face
            enforceSlantAvailability(doc)
        end
        return ret
    end
    local old_setFontFamilyFontFaces = document.setFontFamilyFontFaces
    document.setFontFamilyFontFaces = function(doc, font_family_fonts, ...)
        local ret = old_setFontFamilyFontFaces(doc, font_family_fonts, ...)
        local fonts = {}
        for family, font in pairs(font_family_fonts or {}) do
            fonts[family] = font
        end
        doc._typography_family_fonts = fonts
        enforceSlantAvailability(doc)
        return ret
    end
end



function Typography:_patchNativeFontWeight()
    for _, category in ipairs(creoptions) do
        if category.options then
            for _, option in ipairs(category.options) do
                if option.name == "font_base_weight" then
                    option.show_func = function(...)
                        return false
                    end
                    logger.info("Typography Plugin: Native font_base_weight widget disabled.")
                    break
                end
            end
        end
    end
end

-- Generator for the 4 variables of a specific font category
function Typography:_buildCategoryMenu(title, category_prefix)
    return {
        text = title,
        sub_item_table = {
            {
                keep_menu_open = true,
                text_func = function()
                    local current_font
                    if category_prefix == "base" then
                        current_font = self.ui.font and self.ui.font.font_face or ""
                        if current_font == "" then current_font = _("main font") end
                    else
                        if self.ui.font and self.ui.font.font_family_fonts and self.ui.font.font_family_fonts[category_prefix] then
                            current_font = self.ui.font.font_family_fonts[category_prefix]
                        else
                            local family_fonts = G_reader_settings:readSetting("cre_font_family_fonts", {})
                            current_font = family_fonts[category_prefix] or _("main font")
                        end
                    end
                    return _("Font Face") .. ": " .. current_font
                end,
                callback = function(touchmenu_instance)
                    local current_font
                    if category_prefix == "base" then
                        current_font = self.ui.font and self.ui.font.font_face or ""
                    else
                        if self.ui.font and self.ui.font.font_family_fonts and self.ui.font.font_family_fonts[category_prefix] then
                            current_font = self.ui.font.font_family_fonts[category_prefix]
                        else
                            local family_fonts = G_reader_settings:readSetting("cre_font_family_fonts", {})
                            current_font = family_fonts[category_prefix] or ""
                        end
                    end
                    UIManager:show(FontChooser:new{
                        title = _("Select Font: ") .. title,
                        current_font = current_font,
                        onConfirm = function(font_name)
                            if category_prefix == "base" then
                                if font_name == "(Use main font)" then
                                    G_reader_settings:delSetting("cre_font")
                                    if self.ui.document and self.ui.document.default_font then
                                        self.ui:handleEvent(require("ui/event"):new("SetFont", self.ui.document.default_font))
                                    end
                                else
                                    G_reader_settings:saveSetting("cre_font", font_name)
                                    self.ui:handleEvent(require("ui/event"):new("SetFont", font_name))
                                end
                            else
                                local family_fonts = G_reader_settings:readSetting("cre_font_family_fonts", {})
                                if font_name == "(Use main font)" then
                                    family_fonts[category_prefix] = nil
                                else
                                    family_fonts[category_prefix] = font_name
                                end
                                G_reader_settings:saveSetting("cre_font_family_fonts", family_fonts)
                                if self.ui.font then
                                    self.ui.font.font_family_fonts[category_prefix] = nil
                                    self.ui.font:updateFontFamilyFonts()
                                end
                                self.ui.document:resetCallCache()
                                self.ui.document:resetBufferCache()
                                self.ui.view:recalculate()
                                UIManager:setDirty(nil, "full")
                            end
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end
                    })
                end,
            },
            {
                keep_menu_open = true,
                text_func = function()
                    local is_legacy = (category_prefix == "base")
                    local prop_name = is_legacy and "font.face.base.weight" or ("crengine.generic." .. category_prefix .. ".font.weight")
                    local current = G_reader_settings:readSetting(prop_name, 400)
                    return _("Font Weight: ") .. tostring(current)
                end,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    local InfoMessage = require("ui/widget/infomessage")
                    local is_legacy = (category_prefix == "base")
                    local prop_name = is_legacy and "font.face.base.weight" or ("crengine.generic." .. category_prefix .. ".font.weight")
                    local current = G_reader_settings:readSetting(prop_name, 400)

                    local widget = SpinWidget:new{
                        title_text = _("Set Font Weight"),
                        info_text = _("Enter exact CSS weight (e.g. 400 = Regular, 700 = Bold)."),
                        value = current,
                        value_min = 100,
                        value_max = 1000,
                        value_step = 25,
                        value_hold_step = 100,
                        callback = function(dialog)
                            local weight = dialog.value; if weight == current then return end
                            if weight >= 100 and weight <= 1000 then
                                self.ui.document._document:setIntProperty(prop_name, weight)
                                G_reader_settings:saveSetting(prop_name, weight)
                                self.ui.document:resetCallCache()
                                self.ui.document:resetBufferCache()
                                self.ui.view:recalculate()
                                UIManager:setDirty(nil, "full")
                                if touchmenu_instance then touchmenu_instance:updateItems() end
                            else
                                UIManager:show(InfoMessage:new{ text = _("Invalid weight. Must be 100-1000.") })
                            end
                        end,
                    }

                    UIManager:show(widget)
                end,
            },
            {
                keep_menu_open = true,
                text_func = function()
                    local current = G_reader_settings:readSetting(slantProp(category_prefix), "Italic")
                    return _("Slant Type: ") .. tostring(current)
                end,
                callback = function(touchmenu_instance)
                    local prop_name = slantProp(category_prefix)
                    local current = G_reader_settings:readSetting(prop_name, "Italic")
                    -- Slant types this category's font doesn't have are greyed out
                    -- (all available if its font is unknown)
                    local kinds = SlantInfo.getFamilyKinds(categoryFont(self.ui.document, category_prefix))
                    local dialog
                    local function choice(text, value, available)
                        return {
                            text = (value == current and "✓ " or "") .. text,
                            enabled = available,
                            callback = function()
                                UIManager:close(dialog)
                                if value == current then return end
                                self.ui.document._document:setStringProperty(prop_name, value)
                                G_reader_settings:saveSetting(prop_name, value)
                                self.ui.document:resetCallCache()
                                self.ui.document:resetBufferCache()
                                self.ui.view:recalculate()
                                UIManager:setDirty(nil, "full")
                                if touchmenu_instance then touchmenu_instance:updateItems() end
                            end,
                        }
                    end
                    dialog = ButtonDialog:new{
                        title = _("Select Slant Type"),
                        buttons = {
                            { choice(_("Italic"), "Italic", not kinds or kinds.italic) },
                            { choice(_("Oblique"), "Oblique", not kinds or kinds.oblique) },
                            { choice(_("synthetic*"), "synthetic*", true) },
                        },
                    }
                    UIManager:show(dialog)
                end,
            },
            {
                keep_menu_open = true,
                text_func = function()
                    local prop_name = category_prefix == "base" and "font.face.decoration.weight" or ("crengine.generic." .. category_prefix .. ".font.decoration.weight")
                    local current = G_reader_settings:readSetting(prop_name, 100)
                    return _("Decoration Weight: ") .. tostring(current)
                end,
                callback = function(touchmenu_instance)
                    local prop_name = category_prefix == "base" and "font.face.decoration.weight" or ("crengine.generic." .. category_prefix .. ".font.decoration.weight")
                    local current = G_reader_settings:readSetting(prop_name, 100)
                    local SpinWidget = require("ui/widget/spinwidget")
                    local InfoMessage = require("ui/widget/infomessage")
                    local widget = SpinWidget:new{
                        title_text = _("Set Decoration Weight"),
                        info_text = _("Percentage value where 100 is default thickness."),
                        value = current,
                        value_min = 50,
                        value_max = 500,
                        value_step = 25,
                        value_hold_step = 100,
                        callback = function(dialog)
                            local val = dialog.value; if val == current then return end
                            if val >= 50 and val <= 500 then
                                self.ui.document._document:setIntProperty(prop_name, val)
                                G_reader_settings:saveSetting(prop_name, val)
                                self.ui.document:resetCallCache()
                                self.ui.document:resetBufferCache()
                                self.ui.view:recalculate()
                                UIManager:setDirty(nil, "full")
                                if touchmenu_instance then touchmenu_instance:updateItems() end
                            else
                                UIManager:show(InfoMessage:new{ text = _("Invalid decoration weight. Must be 50-500.") })
                            end
                        end,
                    }
                    UIManager:show(widget)
                end,
            },
        }
    }
end

function Typography:addToMainMenu(menu_items)
    -- Its own menu entry, right after KOReader's "Typography rules" (menu_items.typography)
    -- in the reader menu order (kept cached by KOReader so that plugins can add to it)
    local reader_order = require("ui/elements/reader_menu_order")
    if not util.arrayContains(reader_order.typeset, "advanced_typography") then
        local pos = util.arrayContains(reader_order.typeset, "typography")
        table.insert(reader_order.typeset, pos and pos + 1 or #reader_order.typeset + 1, "advanced_typography")
    end
    menu_items.advanced_typography = {
        text = _("Advanced Typography Settings"),
        sub_item_table_func = function()
            return {
                self:_buildCategoryMenu(_("1. Default (unclassified)"), "base"),
                self:_buildCategoryMenu(_("2. Serif"), "serif"),
                self:_buildCategoryMenu(_("3. Sans-Serif"), "sans-serif"),
                self:_buildCategoryMenu(_("4. Cursive"), "cursive"),
                self:_buildCategoryMenu(_("5. Fantasy"), "fantasy"),
                self:_buildCategoryMenu(_("6. Monospace"), "monospace"),
                self:_buildCategoryMenu(_("7. Emoji"), "emoji"),
                self:_buildCategoryMenu(_("8. Fangsong"), "fangsong"),
                self:_buildCategoryMenu(_("9. Math"), "math"),
                self:_buildFontCacheMenu(),
                self:_buildExtraFontFoldersMenu(),
                self:_buildNoDocumentCacheMenu(),
                self:_buildSavingSettingsMenu(),
            }
        end,
    }
end

-- crengine's installed fonts cache (crengine_fonts.dat, next to KOReader's font list cache),
-- written by crengine at startup only when font files were added, changed or removed
function Typography:_buildFontCacheMenu()
    local path = DataStorage:getDataDir() .. "/cache/fontlist/crengine_fonts.dat"
    local function exists()
        return lfs.attributes(path, "mode") == "file"
    end
    -- Header line: "crengine-extended fonts cache <version> <font files> <fonts>"
    local function counts()
        local f = io.open(path, "r")
        if not f then return end
        local header = f:read("*l")
        f:close()
        local nb_files, nb_fonts = (header or ""):match("^crengine%-extended fonts cache\t%d+\t(%d+)\t(%d+)")
        return tonumber(nb_files), tonumber(nb_fonts)
    end
    return {
        text = _("Font cache"),
        sub_item_table = {
            {
                text_func = function()
                    if not exists() then
                        return _("Size: (not created yet)")
                    end
                    return _("Size: ") .. util.getFriendlySize(lfs.attributes(path, "size"))
                end,
                keep_menu_open = true,
                callback = function() end,
            },
            {
                text_func = function()
                    if not exists() then
                        return _("Last modified: -")
                    end
                    return _("Last modified: ") .. os.date("%Y-%m-%d %H:%M:%S", lfs.attributes(path, "modification"))
                end,
                keep_menu_open = true,
                callback = function() end,
            },
            {
                text_func = function()
                    local nb_files, nb_fonts = counts()
                    if not nb_files then
                        return _("Fonts: -")
                    end
                    return _("Fonts: ") .. nb_fonts .. " (" .. nb_files .. " " .. _("files") .. ")"
                end,
                keep_menu_open = true,
                callback = function() end,
                separator = true,
            },
            {
                text = _("Clear font cache"),
                keep_menu_open = true,
                enabled_func = exists,
                callback = function(touchmenu_instance)
                    UIManager:show(ConfirmBox:new{
                        text = _("Clear the font cache?\n\nIt is rebuilt the next time KOReader starts (that start takes longer)."),
                        ok_text = _("Clear"),
                        ok_callback = function()
                            os.remove(path)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    })
                end,
            },
            {
                text = _("Rebuild font cache"),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    os.remove(path)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                    UIManager:askForRestart(_("The font cache is rebuilt when KOReader restarts."))
                end,
            },
        },
    }
end

-- Deletes the cache files of books (cache/cr3cache/*.cr3) and crengine's index of them, then has
-- crengine start again from an empty index: a book it still listed would get an empty cache file
-- when it opens. Only when there are cache files to delete, unless always: nothing is written
-- otherwise
local function deleteBookCaches(always)
    local cachedir = DataStorage:getDataDir() .. "/cache/cr3cache"
    if lfs.attributes(cachedir, "mode") ~= "directory" then return end
    local found = always
    for f in lfs.dir(cachedir) do
        if f:match("%.cr3$") then
            os.remove(cachedir .. "/" .. f)
            found = true
        end
    end
    if found then
        os.remove(cachedir .. "/cr3cache.inx")
        CreDocument.cacheInit() -- safe with a book open: it keeps its own (now deleted) file
    end
end

-- crengine's cache of opened books (cache/cr3cache): with "No document cache", no cache file is
-- created for books (crengine only caches books larger than crengine.cache.filesize.min, set
-- out of reach when a book opens, in onReadSettings()). Turning it on deletes the existing ones;
-- any crengine creates anyway (running short of memory) is deleted when a book next opens.
function Typography:_buildNoDocumentCacheMenu()
    return {
        text = _("No document cache"),
        help_text = _("Don't keep a cache file of opened books, so opening and closing a book writes no cache. Every book is then laid out again each time it is opened (slower for large books), and changing a setting lays out the whole book again. Very large books may still need a cache when memory runs short."),
        checked_func = function()
            return G_reader_settings:isTrue(NO_DOCUMENT_CACHE)
        end,
        callback = function(touchmenu_instance)
            if G_reader_settings:isTrue(NO_DOCUMENT_CACHE) then
                G_reader_settings:delSetting(NO_DOCUMENT_CACHE)
                if touchmenu_instance then touchmenu_instance:updateItems() end
                return
            end
            UIManager:show(ConfirmBox:new{
                text = _("Stop keeping a cache of opened books?\n\nBooks will be laid out again each time they are opened (slower for large books), and changing a setting lays out the whole book again.\n\nThe existing book caches are deleted. This applies to books opened from now on."),
                ok_text = _("Stop caching"),
                ok_callback = function()
                    G_reader_settings:makeTrue(NO_DOCUMENT_CACHE)
                    deleteBookCaches(true)
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
        end,
    }
end

-- KOReader's own font folders (FontList's: its fonts folder, then FontSettings' folders, or
-- EXT_FONT_DIR's without system fonts), as real paths: it reads all their subfolders itself
local function koreaderFontDirs()
    local realpath = require("ffi/util").realpath
    local dirs = { require("fontlist").fontdir }
    local others
    if require("document/canvascontext"):hasSystemFonts() then
        others = require("ui/elements/font_settings"):getPath()
    else
        others = os.getenv("EXT_FONT_DIR")
    end
    for dir in string.gmatch(others or "", "[^;]+") do table.insert(dirs, dir) end
    local real = {}
    for _, dir in ipairs(dirs) do
        local r = realpath(dir)
        if r then table.insert(real, r) end
    end
    return real
end

-- Whether a real path is one of the folders, or inside one
local function isInside(real, folders)
    for _, folder in ipairs(folders) do
        if real == folder or real:sub(1, #folder + 1) == folder .. "/" then return true end
    end
    return false
end

-- Extra font folders: the folders set there whose fonts crengine also registers. Adding one only
-- adds fonts; removing one, or leaving out its subfolders, deletes crengine's font cache (as the
-- Font cache menu's Rebuild does), so that the cache, which the plugin reads (slantinfo.lua), keeps
-- only fonts crengine has. Each takes effect when KOReader restarts (addExtraFontFolders())
function Typography:_buildExtraFontFoldersMenu()
    local realpath = require("ffi/util").realpath
    local InfoMessage = require("ui/widget/infomessage")
    local items = {}
    local function folders()
        return G_reader_settings:readSetting(EXTRA_FONT_FOLDERS) or {}
    end
    local function removesFonts(new_folders)
        G_reader_settings:saveSetting(EXTRA_FONT_FOLDERS, new_folders)
        os.remove(SlantInfo.getFontsCachePath())
        UIManager:askForRestart(_("The font cache is rebuilt, without these fonts, when KOReader restarts."))
    end
    local fill
    fill = function(menu)
        for i = #items, 1, -1 do items[i] = nil end
        table.insert(items, {
            text = _("Add folder…"),
            keep_menu_open = true,
            callback = function(menu)
                local PathChooser = require("ui/widget/pathchooser")
                UIManager:show(PathChooser:new{
                    select_directory = true,
                    select_file = false,
                    path = G_reader_settings:readSetting("home_dir") or require("device").home_dir or "/",
                    onConfirm = function(path)
                        local real = realpath(path) or path
                        for _i, folder in ipairs(folders()) do
                            if folder.path == real then
                                UIManager:show(InfoMessage:new{ text = T(_("%1 is already in the list."), real) })
                                return
                            end
                        end
                        if isInside(real, koreaderFontDirs()) then
                            UIManager:show(InfoMessage:new{ text = T(_("KOReader already reads the fonts in %1."), real) })
                            return
                        end
                        local new_folders = folders()
                        table.insert(new_folders, { path = real, recursive = true })
                        G_reader_settings:saveSetting(EXTRA_FONT_FOLDERS, new_folders)
                        fill(menu)
                        UIManager:askForRestart(_("The fonts of the added folder are available when KOReader restarts."))
                    end,
                })
            end,
            separator = true,
        })
        for index, folder in ipairs(folders()) do
            table.insert(items, {
                text = folder.path,
                sub_item_table = {
                    {
                        text = _("Include subfolders"),
                        checked_func = function() return folders()[index].recursive ~= false end,
                        callback = function()
                            local new_folders = folders()
                            if new_folders[index].recursive ~= false then
                                new_folders[index].recursive = false
                                removesFonts(new_folders)
                            else
                                new_folders[index].recursive = true
                                G_reader_settings:saveSetting(EXTRA_FONT_FOLDERS, new_folders)
                                UIManager:askForRestart(_("The fonts of its subfolders are available when KOReader restarts."))
                            end
                        end,
                    },
                    {
                        text = _("Remove folder"),
                        keep_menu_open = true,
                        callback = function(menu)
                            UIManager:show(ConfirmBox:new{
                                text = T(_("Remove %1 from the extra font folders?\n\nIts fonts are no longer available after KOReader restarts (the font cache is rebuilt then)."), folder.path),
                                ok_text = _("Remove"),
                                ok_callback = function()
                                    local new_folders = folders()
                                    table.remove(new_folders, index)
                                    if menu then menu:backToUpperMenu() end
                                    fill(menu)
                                    removesFonts(new_folders)
                                end,
                            })
                        end,
                    },
                },
            })
        end
        if menu then menu:updateItems() end
    end
    fill()
    return {
        text = _("Extra font folders"),
        help_text = _("Folders whose fonts crengine also uses for books, besides KOReader's own font folders (with their subfolders, unless turned off). Changes take effect when KOReader restarts."),
        sub_item_table_func = function()
            fill()
            return items
        end,
    }
end

-- When KOReader writes its settings file, besides at exit (always). Turning these off only skips
-- writing settings.reader.lua then (installSavingPatches()): each book's own file (position,
-- highlights, bookmarks) is still written, and the settings are written at the next moment that
-- is on, and at exit
function Typography:_buildSavingSettingsMenu()
    local function toggle(setting, text, help_text)
        return {
            text = text,
            help_text = help_text,
            checked_func = function() return G_reader_settings:nilOrTrue(setting) end,
            callback = function()
                if G_reader_settings:nilOrTrue(setting) then
                    G_reader_settings:makeFalse(setting)
                else
                    G_reader_settings:delSetting(setting)
                end
            end,
        }
    end
    local function autosaveText(minutes)
        if not minutes then return _("Off") end
        if minutes % 60 == 0 then
            return T(N_("Every hour", "Every %1 hours", minutes / 60), minutes / 60)
        end
        return T(N_("Every minute", "Every %1 minutes", minutes), minutes)
    end
    local autosave_items = {}
    for _, minutes in ipairs({ false, 5, 15, 30, 60, 120, 240 }) do
        table.insert(autosave_items, {
            text = autosaveText(minutes),
            checked_func = function()
                return (G_reader_settings:readSetting(AUTOSAVE_MINUTES) or false) == minutes
            end,
            radio = true,
            callback = function()
                G_reader_settings:saveSetting(AUTOSAVE_MINUTES, minutes)
            end,
        })
    end
    return {
        text = _("Saving settings"),
        sub_item_table = {
            toggle(SAVE_ON_BOOK, _("Save when opening or closing a book"),
                _("KOReader writes its settings file (all its settings, these included) when a book is opened from the file browser and when a book is closed. When off, the settings are written at the next of the moments below that is on, and always when KOReader exits. The book's own data (reading position, highlights, bookmarks) is still saved when it is closed. A crash loses the settings changed since they were last written.")),
            toggle(SAVE_ON_SUSPEND, _("Save when suspending"),
                _("KOReader writes its settings file when the device suspends, and on Android when KOReader goes to the background. When off, the settings are written at the next of the other moments that is on, and always when KOReader exits. The book's own data is still saved. Android can close an app in the background without notice: the settings changed since they were last written are then lost.")),
            {
                text_func = function()
                    return T(_("Autosave: %1"), autosaveText(G_reader_settings:readSetting(AUTOSAVE_MINUTES) or false))
                end,
                help_text = _("KOReader's own autosave (also in its Settings > Document menu): while reading, on a page turn once this time has passed, it saves the book's data and the settings."),
                sub_item_table = autosave_items,
            },
            {
                text = _("Always saved when KOReader exits"),
                keep_menu_open = true,
                callback = function() end,
            },
        },
    }
end

function Typography:onReadSettings(config)
    -- Only documents crengine renders (not PDF, DjVu...: their engines have none of these settings)
    if not self.ui.document or self.ui.document.provider ~= "crengine" or not self.ui.document._document then return end

    if G_reader_settings:isTrue(NO_DOCUMENT_CACHE) then
        -- Before the book is loaded and laid out: no cache file gets created for it, and none
        -- left from before (or by crengine running short of memory) gets used
        self.ui.document._document:setIntProperty("crengine.cache.filesize.min", 0x7FFFFFFF)
        deleteBookCaches()
    end

    local function applyProp(prop_name, val_type)
        local val = G_reader_settings:readSetting(prop_name)
        if val ~= nil then
            if val_type == "int" then
                self.ui.document._document:setIntProperty(prop_name, val)
            else
                self.ui.document._document:setStringProperty(prop_name, val)
            end
        end
    end

    local categories = {"base", "serif", "sans-serif", "cursive", "fantasy", "monospace", "emoji", "fangsong", "math"}
    for _, category in ipairs(categories) do
        local weight_prop = category == "base" and "font.face.base.weight" or ("crengine.generic." .. category .. ".font.weight")
        applyProp(weight_prop, "int")

        local italic_prop = category == "base" and "font.italic.style.default" or ("crengine.generic." .. category .. ".font.italic.style")
        applyProp(italic_prop, "string")

        local dec_prop = category == "base" and "font.face.decoration.weight" or ("crengine.generic." .. category .. ".font.decoration.weight")
        applyProp(dec_prop, "int")
    end
end

-- "Saving settings" (_buildSavingSettingsMenu()): KOReader writes its settings file through
-- G_reader_settings:flush(); during a book's opening or closing (FileManager:onClose(),
-- ReaderUI:onClose()) or a suspend (Device:_beforeSuspend(), and the device's own events, such as
-- Android going to the background), that write is skipped when its option is off. Anything else,
-- KOReader's exit included (Device:exit() through _patchDeviceExit()), writes as before. Installed
-- when KOReader loads the plugin (at startup, before any book is opened)
local save_moment -- "book", "suspend" or nil
local function installSavingPatches()
    if G_reader_settings._advancedtypography_flush then return end
    local flush = G_reader_settings.flush
    G_reader_settings._advancedtypography_flush = flush
    G_reader_settings.flush = function(settings, ...)
        if (save_moment == "book" and G_reader_settings:isFalse(SAVE_ON_BOOK))
                or (save_moment == "suspend" and G_reader_settings:isFalse(SAVE_ON_SUSPEND)) then
            logger.dbg("AdvancedTypography: settings file not written at this", save_moment, "(Saving settings)")
            return settings
        end
        return flush(settings, ...)
    end
    -- Wraps owner[name] so that it runs as a moment of that kind
    local function asMoment(owner, name, moment)
        local original = owner and owner[name]
        if type(original) ~= "function" then return end
        owner[name] = function(...)
            local previous = save_moment
            save_moment = moment
            local function finish(ok, ...)
                save_moment = previous
                if not ok then error((...), 0) end
                return ...
            end
            return finish(pcall(original, ...))
        end
    end
    asMoment(require("apps/reader/readerui"), "onClose", "book")
    asMoment(require("apps/filemanager/filemanager"), "onClose", "book")
    local Device = require("device")
    asMoment(Device, "_beforeSuspend", "suspend")
    asMoment(Device.input, "handleMiscEv", "suspend")
end
installSavingPatches()

-- "Extra font folders" (_buildExtraFontFoldersMenu()): their font files (KOReader's file types,
-- not hidden; in subfolders too unless left out; not those of KOReader's own font folders, nor any
-- already listed) are added to KOReader's font list, which CreDocument:engineInit() registers with
-- crengine, so crengine's font cache records them as any other. Run when KOReader loads the
-- plugin; if crengine had started already (KOReader opened a book at startup), they're registered
-- as engineInit() does (their font cache records, kept for files that exist, are used then)
local FONT_EXTS = { ttf = true, ttc = true, cff = true, otf = true, woff = true, woff2 = true } -- fontlist.lua's
local function addExtraFontFolders()
    local folders = G_reader_settings:readSetting(EXTRA_FONT_FOLDERS)
    if not folders or not folders[1] then return end
    local realpath = require("ffi/util").realpath
    local koreader_dirs = koreaderFontDirs()
    local visited = {} -- real paths of the folders read (and symbolic link loops)
    local files = {}
    local function read(dir, recursive)
        local real = realpath(dir)
        if not real or visited[real] or isInside(real, koreader_dirs) then return end
        visited[real] = true
        local ok, iter, dir_obj = pcall(lfs.dir, real)
        if not ok then return end
        for f in iter, dir_obj do
            local path = real .. "/" .. f
            local mode = lfs.attributes(path, "mode")
            if mode == "directory" then
                if recursive and f ~= "." and f ~= ".." then read(path, true) end
            elseif mode == "file" and f:sub(1, 1) ~= "." and FONT_EXTS[(f:lower():match("%.([^.]+)$") or "")] then
                table.insert(files, path)
            end
        end
    end
    for _, folder in ipairs(folders) do read(folder.path, folder.recursive ~= false) end
    if not files[1] then return end
    local list = require("fontlist"):getFontList()
    local listed = {}
    for _, path in ipairs(list) do listed[path] = true end
    local added = {}
    for _, path in ipairs(files) do
        if not listed[path] then
            listed[path] = true
            table.insert(list, path)
            table.insert(added, path)
        end
    end
    local cre = package.loaded["libs/libkoreader-cre"]
    if cre and added[1] then
        for _, path in ipairs(added) do
            if not path:find("/urw/") and not path:find("/nerdfonts/symbols.ttf") then
                local ok, err = pcall(cre.registerFont, path)
                if not ok then logger.err("AdvancedTypography: failed to register crengine font:", err) end
            end
        end
        cre.regularizeRegisteredFontsWeights(false)
    end
end
addExtraFontFolders()

return Typography
