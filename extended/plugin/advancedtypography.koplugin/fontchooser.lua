local WidgetContainer = require("ui/widget/container/widgetcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputText = require("ui/widget/inputtext")
local Button = require("ui/widget/button")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local Size = require("ui/size")
local Font = require("ui/font")
local _ = require("gettext")
local Blitbuffer = require("ffi/blitbuffer")

-- Whether crengine registered a font as monospace: KOReader's own font menu marks these with
-- the same rule (its regular face, else its italic one, for fonts only available in italic)
local function isMonospace(cre, font)
    local is_monospace = select(3, cre.getFontFaceFilenameAndFaceIndex(font))
    if is_monospace == nil then
        is_monospace = select(3, cre.getFontFaceFilenameAndFaceIndex(font, nil, true))
    end
    return is_monospace == true
end

local FontChooser = WidgetContainer:extend{
    -- Taps outside the on-screen keyboard (shown above us while searching) still reach the list,
    -- as in KOReader's InputDialog
    is_always_active = true,
    title = "Select Font",
    current_font = "",
    onConfirm = nil,
}

function FontChooser:init()
    self.cleanup_widgets = {}

    -- Load fonts exactly like KOReader native font chooser
    local cre = require("document/credocument"):engineInit()
    self.all_fonts = cre.getFontFaces()
    self.cre = cre
    self.monospace = {} -- font -> isMonospace(), looked up when the font is shown
    table.sort(self.all_fonts, function(a, b) return string.lower(a) < string.lower(b) end)
    table.insert(self.all_fonts, 1, "(Use main font)")

    -- Real-time filter input
    self.search_input = InputText:new{
        parent = self,
        width = require("device").screen:getWidth() - require("device").screen:scaleBySize(120),
        hint = _("Search font..."),
        edit_callback = function()
            if self.search_input then
                self:filterFonts(self.search_input:getText())
            end
        end,
    }
    table.insert(self.cleanup_widgets, self.search_input)

    local back_button = Button:new{
        icon = "back.top",
        bordersize = 0,
        callback = function()
            UIManager:scheduleIn(0, function() UIManager:close(self) end)
        end,
    }

    local top_bar = HorizontalGroup:new{
        align = "center",
        back_button,
        self.search_input,
    }
    top_bar.getHeight = function(self) return self:getSize().h end
    top_bar.generateVerticalLayout = function(self) return { { back_button, self.search_input } } end

    self.menu = Menu:new{
        item_table = self:getMenuItems(self.all_fonts),
        is_popout = false,
        width = require("device").screen:getWidth(),
        height = require("device").screen:getHeight(),
        custom_title_bar = top_bar,
        show_parent = self,
    }

    self.container = FrameContainer:new{
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        width = require("device").screen:getWidth(),
        height = require("device").screen:getHeight(),
        self.menu,
    }

    self[1] = self.container
end

function FontChooser:filterFonts(query)
    local filtered = {}
    local lower_query = query:lower()
    for _, font in ipairs(self.all_fonts) do
        if font:lower():find(lower_query, 1, true) then
            table.insert(filtered, font)
        end
    end
    -- Dynamically update the menu items
    self.menu:switchItemTable(nil, self:getMenuItems(filtered))
end

function FontChooser:getMenuItems(font_list)
    local items = {}
    for _, font in ipairs(font_list) do
        local is_current = (font == self.current_font)
        table.insert(items, {
            text_func = function()
                local text = font
                if font ~= "(Use main font)" then
                    if self.monospace[font] == nil then
                        self.monospace[font] = isMonospace(self.cre, font)
                    end
                    if self.monospace[font] then
                        text = text .. " \u{1D39}" -- Modified Letter Capital M, as in KOReader's font menu
                    end
                end
                return text .. (is_current and " (Current)" or "")
            end,
            callback = function()
                UIManager:scheduleIn(0, function()
                    if self.onConfirm then
                        self.onConfirm(font)
                    end
                    UIManager:close(self)
                end)
            end
        })
    end
    return items
end

function FontChooser:onCloseWidget()
    -- Close the on-screen keyboard's window before freeing it, as KOReader's InputDialog does
    if self.search_input then
        self.search_input:onCloseKeyboard()
    end
    for _, w in ipairs(self.cleanup_widgets) do
        if w and w.onCloseWidget then
            w:onCloseWidget()
        end
    end
    if self.menu and self.menu.onCloseWidget then
        self.menu:onCloseWidget()
    end

end


function FontChooser:getFocusableWidgetXY(widget)
    return 1, 1, 0, 0
end

function FontChooser:moveFocusTo()
    -- dummy to prevent FocusManager crashes
end

return FontChooser

