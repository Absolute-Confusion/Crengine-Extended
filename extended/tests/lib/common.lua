-- Shared by the test suites. run_tests.sh runs each suite with ./luajit from the KOReader
-- emulator's koreader directory, with KOReader's data in a throwaway folder (KO_HOME) and
-- only KOReader's bundled fonts and the test fonts (XDG_DATA_HOME/fonts) installed.
local T = {}

T.TESTS = assert(os.getenv("AT_TESTS"), "run the suites with run_tests.sh")
T.WORK = assert(os.getenv("AT_WORK"), "run the suites with run_tests.sh")
T.BOOKS = T.WORK .. "/books"

T.CATEGORIES = { "base", "serif", "sans-serif", "cursive", "fantasy", "monospace", "emoji", "fangsong", "math" }
T.GENERIC = { "serif", "sans-serif", "cursive", "fantasy", "monospace", "emoji", "fangsong", "math" }

-- crengine property (and global setting) of each attribute, per category ("base" = Unclassified)
function T.weightProp(c) return c == "base" and "font.face.base.weight" or ("crengine.generic." .. c .. ".font.weight") end
function T.slantProp(c) return c == "base" and "font.italic.style.default" or ("crengine.generic." .. c .. ".font.italic.style") end
function T.decorationProp(c) return c == "base" and "font.face.decoration.weight" or ("crengine.generic." .. c .. ".font.decoration.weight") end

-- KOReader's own unit test setup (fresh settings), with this plugin only, or no plugin
function T.init(with_plugin)
    require("setupkoenv")
    package.path = "spec/front/unit/?.lua;plugins/advancedtypography.koplugin/?.lua;" .. package.path
    require("commonrequire")
    require("logger"):setLevel(require("logger").levels.warn)
    disable_plugins()
    if with_plugin then load_plugin("advancedtypography.koplugin") end
    require("libs/libkoreader-lfs").mkdir(T.BOOKS)
end

-- Main font and all 8 font-family fonts on one family
function T.useFont(family)
    G_reader_settings:saveSetting("cre_font", family)
    local fonts = {}
    for _, c in ipairs(T.GENERIC) do fonts[c] = family end
    G_reader_settings:saveSetting("cre_font_family_fonts", fonts)
end

-- Results
local failures = 0
function T.check(cond, msg, quiet_ok)
    if not cond then
        failures = failures + 1
        print("FAIL  " .. msg)
    elseif not quiet_ok then
        print("ok    " .. msg)
    end
    return cond
end
function T.finish()
    print(("%d failure(s)"):format(failures))
    os.exit(failures == 0 and 0 or 1)
end

-- Test books
function T.writeFile(path, content)
    local f = assert(io.open(path, "wb"))
    f:write(content)
    f:close()
    return path
end
function T.writeHtml(name, html)
    return T.writeFile(T.BOOKS .. "/" .. name .. ".html", html)
end
-- An EPUB above 64 KB (with stored, incompressible padding): KOReader then keeps a cache file
-- for it and, once the book is open, partial rerendering gets enabled, as with real books
function T.writeEpub(name, body)
    local path = T.BOOKS .. "/" .. name .. ".epub"
    os.remove(path)
    local function xhtml(b)
        return '<?xml version="1.0" encoding="utf-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>t</title></head><body>'
            .. b .. "</body></html>"
    end
    local padding, x = {}, 12345
    for i = 1, 100000 do
        x = (x * 1103515245 + 12345) % 2147483648
        padding[i] = string.char(math.floor(x / 65536) % 256)
    end
    local epub = require("ffi/archiver").Writer:new{}
    assert(epub:open(path, "zip"))
    epub:setZipCompression("store")
    epub:addFileFromMemory("mimetype", "application/epub+zip")
    epub:addFileFromMemory("OEBPS/padding.bin", table.concat(padding))
    epub:setZipCompression("deflate")
    epub:addFileFromMemory("META-INF/container.xml", '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
    epub:addFileFromMemory("OEBPS/content.opf", '<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>' .. name .. '</dc:title><dc:identifier id="id">' .. name .. '</dc:identifier><dc:language>en</dc:language></metadata><manifest><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/><item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c1"/><itemref idref="c2"/></spine></package>')
    epub:addFileFromMemory("OEBPS/c1.xhtml", xhtml(body))
    epub:addFileFromMemory("OEBPS/c2.xhtml", xhtml("<p>second section</p>"))
    epub:close()
    return path
end

-- Low-level document (no reader UI): one paragraph per page, no header (it has a clock)
function T.openPaged(path, w, h)
    local Geom = require("ui/geometry")
    local doc = require("document/documentregistry"):openDocument(path)
    doc:setViewMode("page")
    doc:setViewDimen(Geom:new{ w = w, h = h })
    doc:loadDocument()
    doc:setStatusLineProp(1)
    doc:setVisiblePageCount(1)
    doc:render()
    return doc
end
-- Rerender after property changes, as the plugin does
function T.rerender(doc)
    doc:resetCallCache(); doc:resetBufferCache()
    doc:render()
end
-- Fingerprint (hash and amount of ink) of a page of a low-level document
function T.pagePrint(doc, page, w, h)
    local bit = require("bit")
    local Blitbuffer = require("ffi/blitbuffer")
    local Geom = require("ui/geometry")
    local bb = Blitbuffer.new(w, h, Blitbuffer.TYPE_BB8)
    bb:fill(Blitbuffer.COLOR_WHITE)
    doc:drawCurrentViewByPage(bb, 0, 0, Geom:new{ x = 0, y = 0, w = w, h = h }, page)
    local hash, ink = 0, 0
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local v = 255 - bb:getPixel(x, y):getColor8().a
            if v ~= 0 then
                ink = ink + v
                hash = bit.tobit(hash * 31 + v + x * 7 + y * 131)
            end
        end
    end
    bb:free()
    return ink == 0 and "BLANK" or (hash .. ":" .. ink), ink
end

-- Reader UI (as in the live app)
function T.openReader(path)
    local readerui = require("apps/reader/readerui"):new{
        dimen = require("device").screen:getSize(),
        document = require("document/documentregistry"):openDocument(path),
    }
    fastforward_ui_events() -- partial rerendering gets enabled, as in the live app
    return readerui
end
function T.closeReader(readerui)
    readerui:closeDocument()
    readerui:onClose()
end
function T.paint(readerui)
    local Blitbuffer = require("ffi/blitbuffer")
    local Screen = require("device").screen
    local bb = Blitbuffer.new(Screen:getWidth(), Screen:getHeight(), Blitbuffer.TYPE_BB8)
    bb:fill(Blitbuffer.COLOR_WHITE)
    readerui.view:paintTo(bb, 0, 0)
    return bb
end
-- Text lines on screen: rows with ink, separated by at most 5 blank rows (so a line's
-- underline and strike-through stay with it), without the status bar
function T.findLines(bb)
    local rows, inrow, y0 = {}, false, 0
    for y = 0, bb:getHeight() - 1 do
        local ink = false
        for x = 0, bb:getWidth() - 1 do
            if bb:getPixel(x, y):getColor8().a < 255 then ink = true; break end
        end
        if ink and not inrow then inrow = true; y0 = y end
        if not ink and inrow then inrow = false; table.insert(rows, { y0, y - 1 }) end
    end
    local lines = {}
    for _, r in ipairs(rows) do
        local last = lines[#lines]
        if last and r[1] - last[2] <= 5 then last[2] = r[2] else table.insert(lines, { r[1], r[2] }) end
    end
    while #lines > 0 and lines[#lines][1] > bb:getHeight() - 30 do table.remove(lines) end
    return lines
end
-- Per line: a hash and the amount of ink, over the line's area up to halfway to its neighbours
-- (so thicker decorations or bolder glyphs stay inside it)
function T.linePrints(bb, lines)
    local bit = require("bit")
    local hashes, inks = {}, {}
    for i, b in ipairs(lines) do
        local top = i > 1 and math.floor((lines[i-1][2] + b[1]) / 2) + 1 or math.max(0, b[1] - 6)
        local bottom = i < #lines and math.floor((b[2] + lines[i+1][1]) / 2) or math.min(bb:getHeight() - 31, b[2] + 6)
        local h, s = 0, 0
        for y = top, bottom do
            for x = 0, bb:getWidth() - 1 do
                local v = 255 - bb:getPixel(x, y):getColor8().a
                s = s + v
                h = bit.tobit(h * 31 + v)
            end
        end
        hashes[i], inks[i] = h, s
    end
    return hashes, inks
end

-- Plugin menu: the category submenu item n (1 face, 2 weight, 3 slant type, 4 decoration weight)
function T.menuItem(readerui, category, n)
    return readerui.advancedtypography:_buildCategoryMenu("x", category).sub_item_table[n]
end
-- Change a setting exactly as the plugin menu does: number dialog OK, or a slant type button
-- (refusing greyed out ones)
function T.menuSet(readerui, category, kind, value)
    local UIManager = require("ui/uimanager")
    local n = ({ weight = 2, slant = 3, decoration = 4 })[kind]
    T.menuItem(readerui, category, n).callback(nil)
    local w = UIManager._window_stack[#UIManager._window_stack].widget
    if kind == "slant" then
        local found = false
        for _, row in ipairs(w.buttons) do
            if row[1].text:gsub("^✓ ", "") == value then
                assert(row[1].enabled ~= false, "test error: '" .. value .. "' is greyed out for " .. category)
                found = true
                row[1].callback()
            end
        end
        assert(found, "no slant type button " .. value)
    else
        w.value = value
        w.callback(w) -- what SpinWidget does on OK
    end
    local top = UIManager._window_stack[#UIManager._window_stack]
    if top and top.widget == w then UIManager:close(w) end
    fastforward_ui_events()
end

return T
