-- crengine's slant classification, as recorded in its installed fonts cache (which the plugin's
-- slantinfo.lua reads), agrees with fontconfig's (fc-query's slant value) on every face of the
-- test fonts and of KOReader's bundled fonts.
-- With AT_FONTS_CACHE=/path/to/crengine_fonts.dat, checks that cache instead (eg. the one of a
-- KOReader using all your system fonts), against fontconfig's values for the same files.
-- Skipped if fontconfig's tools aren't installed.
local T = dofile(os.getenv("AT_TESTS") .. "/lib/common.lua")
T.init(false)
local SlantInfo = require("slantinfo")
local lfs = require("libs/libkoreader-lfs")

local function lines(cmd)
    local p = io.popen(cmd)
    local t = {}
    for l in p:lines() do table.insert(t, l) end
    p:close()
    return t
end
if #lines("command -v fc-query") == 0 then
    print("SKIP  fc-query not installed")
    T.finish()
end

local cache = os.getenv("AT_FONTS_CACHE")
if not cache then
    require("document/credocument"):engineInit() -- registers the fonts: crengine writes its cache
    cache = SlantInfo.getFontsCachePath()
end
local faces = SlantInfo.readFontsCache(cache)
if not T.check(faces ~= nil and #faces > 0, "crengine's font cache read: " .. cache) then T.finish() end

-- fontconfig's slant of each face ("path\tindex" -> slant); variable font named instances
-- (index >= 65536) aren't faces of their own for crengine
local fc = {}
local function add(out)
    for _, l in ipairs(out) do
        local path, index, slant = l:match("^(.-)\t(%d+)\t(%d+)$")
        if path and tonumber(index) < 65536 then fc[path .. "\t" .. index] = tonumber(slant) end
    end
end
for _, dir in ipairs({ os.getenv("XDG_DATA_HOME") .. "/fonts", "./fonts" }) do
    add(lines(("find -L %q -type f \\( -iname '*.ttf' -o -iname '*.otf' -o -iname '*.ttc' \\) -exec fc-query -f '%%{file}\\t%%{index}\\t%%{slant}\\n' {} \\; 2>/dev/null"):format(dir)))
end
if os.getenv("AT_FONTS_CACHE") then
    add(lines("fc-list -f '%{file}\\t%{index}\\t%{slant}\\n' 2>/dev/null"))
end

local cwd = lfs.currentdir()
local compared, unknown, mismatches = 0, 0, 0
for _, face in ipairs(faces) do
    -- crengine records bundled fonts relative to KOReader's directory ("./fonts/...")
    local want = fc[face.path .. "\t" .. face.index] or fc[face.path:gsub("^%.", cwd, 1) .. "\t" .. face.index]
    if want == nil then
        unknown = unknown + 1
    else
        compared = compared + 1
        if face.slant ~= want then
            mismatches = mismatches + 1
            T.check(false, ("%s [%d]: fc-query slant %d, crengine %d"):format(face.path, face.index, want, face.slant))
        end
    end
end
T.check(compared > 50, ("faces compared: %d (%d not known to fontconfig, ignored)"):format(compared, unknown))
T.check(mismatches == 0, ("%d faces compared, %d mismatches"):format(compared, mismatches))
T.finish()
