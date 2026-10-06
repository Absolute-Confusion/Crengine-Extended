-- The plugin calls no C library function directly (FFI): KOReader's Android build packs its
-- libraries into one that only provides the functions KOReader itself uses, so a direct call
-- that works on Linux can fail on Android ("undefined symbol"). The plugin uses KOReader's own
-- Lua modules instead, and reads crengine's font classification from its font cache.
local T = dofile(os.getenv("AT_TESTS") .. "/lib/common.lua")
T.init(false)

local dir = "plugins/advancedtypography.koplugin"
local patterns = {
    { 'require%(%s*"ffi"%s*%)', 'require("ffi")' },
    { "ffi%.cdef", "ffi.cdef" },
    { "ffi%.load", "ffi.load / ffi.loadlib" },
    { "ffi%.C[%.%[]", "ffi.C" },
}
local files = 0
for file in require("libs/libkoreader-lfs").dir(dir) do
    if file:match("%.lua$") then
        files = files + 1
        local f = assert(io.open(dir .. "/" .. file))
        local n = 0
        for line in f:lines() do
            n = n + 1
            for _, p in ipairs(patterns) do
                if line:match(p[1]) and not line:match("^%s*%-%-") then
                    T.check(false, ("%s:%d uses %s"):format(file, n, p[2]))
                end
            end
        end
        f:close()
    end
end
T.check(files >= 4, ("plugin files checked: %d"):format(files))
T.check(true, "no direct C library calls in the plugin")
T.finish()
