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

local Typography = WidgetContainer:extend{
    name = "advancedtypography",
    is_doc_only = true,
}

local CATEGORIES = {"base", "serif", "sans-serif", "cursive", "fantasy", "monospace", "emoji", "fangsong", "math"}

-- "No document cache": crengine keeps no cache file of opened books (see _buildNoDocumentCacheMenu())
local NO_DOCUMENT_CACHE = "advancedtypography_no_document_cache"

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
                self:_buildNoDocumentCacheMenu(),
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

function Typography:onReadSettings(config)
    if not self.ui.document or not self.ui.document._document then return end

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

return Typography
