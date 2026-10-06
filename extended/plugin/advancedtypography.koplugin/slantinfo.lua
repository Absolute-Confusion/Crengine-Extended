--[[--
Which slant kinds (italic, oblique) a font family offers, as crengine sees it.

Read from crengine's installed fonts cache (cache/fontlist/crengine_fonts.dat),
where crengine records how it classified each installed font face at startup:
its slant as fontconfig's FC_SLANT (the value fc-query reports): 0 (roman),
100 (italic) or 110 (oblique), and its variable font axes. A variable font's
'ital' axis counts as italic and its 'slnt' axis as oblique, as in crengine's
matchBySlantType(). Plain file reading only: no FreeType or HarfBuzz call, as
those KOReader's Android build doesn't provide.

Faces belong to families named as crengine names installed fonts: their FreeType
family name, with a width word and a spacing word on a collision in that family
(crengine's LVFontRegistry::registerInstalledFace()).
]]

local DataStorage = require("datastorage")

local SlantInfo = {
    ROMAN = 0,
    ITALIC = 100,
    OBLIQUE = 110,
}

-- Width and spacing words, as crengine's kFcWidthWords and kFcSpacingWords (lvfntman.cpp)
local WIDTH_WORDS = { "Ultra-Condensed", "Extra-Condensed", "Condensed", "Semi-Condensed",
                      false, "Semi-Expanded", "Expanded", "Extra-Expanded", "Ultra-Expanded" }
local WIDTH_NORMAL = 5 -- no word
local SPACING_WORDS = { "Proportional", "Duospace", "Monospace", "Charcell", "Proportional" }

-- Index in WIDTH_WORDS of a FC_WIDTH value (crengine's fcWidthIndex())
local function widthIndex(fc_width)
    if fc_width < 60 then return 1 end
    if fc_width < 70 then return 2 end
    if fc_width < 80 then return 3 end
    if fc_width < 95 then return 4 end
    if fc_width <= 105 then return WIDTH_NORMAL end
    if fc_width <= 120 then return 6 end
    if fc_width <= 140 then return 7 end
    if fc_width <= 175 then return 8 end
    return 9
end

-- Index in SPACING_WORDS of a FC_SPACING value (crengine's fcSpacingIndex())
local function spacingIndex(fc_spacing)
    return ({ [0] = 1, [90] = 2, [100] = 3, [110] = 4 })[fc_spacing] or 5
end

--- Path of crengine's installed fonts cache.
function SlantInfo.getFontsCachePath()
    return DataStorage:getDataDir() .. "/cache/fontlist/crengine_fonts.dat"
end

--[[--
The font faces recorded in crengine's installed fonts cache.

@string path the cache file (default: SlantInfo.getFontsCachePath())
@treturn table|nil list of { path, index, slant, base_family, fc_width, fc_spacing,
ital_axis, slnt_axis }, or nil if there is no readable cache
]]
function SlantInfo.readFontsCache(path)
    local f = io.open(path or SlantInfo.getFontsCachePath(), "r")
    if not f then return end
    local header = f:read("*l")
    if not header or not header:match("^crengine%-extended fonts cache\t") then
        f:close()
        return
    end
    local faces, file_path = {}, nil
    for line in f:lines() do
        local fields = {}
        for field in (line .. "\t"):gmatch("([^\t]*)\t") do
            fields[#fields + 1] = field
        end
        if fields[1] == "F" and #fields == 4 then
            file_path = fields[2]
        elseif fields[1] == "S" and #fields == 28 and file_path then
            -- Fields as written by crengine's saveFontsCache(): face index, italic flag,
            -- slant, css family, typeface, base family, former name, width, spacing,
            -- emojis, math, small caps, then has/min/max of the wght, opsz, ital, slnt
            -- and wdth axes
            local has_ital, ital_min, ital_max = fields[20] == "1", tonumber(fields[21]), tonumber(fields[22])
            local has_slnt, slnt_min = fields[23] == "1", tonumber(fields[24])
            faces[#faces + 1] = {
                path = file_path,
                index = tonumber(fields[2]),
                slant = tonumber(fields[4]),
                base_family = fields[7],
                fc_width = tonumber(fields[9]),
                fc_spacing = tonumber(fields[10]),
                -- as crengine's matchBySlantType()
                ital_axis = has_ital and ital_min < ital_max and ital_max > 0.5,
                slnt_axis = has_slnt and slnt_min < 0,
            }
        end
    end
    f:close()
    return faces
end

-- Slant kinds per family (lowercase name), from the cache: built once per session
local kinds_by_family

local function buildKinds()
    local faces = SlantInfo.readFontsCache()
    if not faces then return end
    -- Widths and spacings present in each base family (crengine's _installed_masks)
    local widths, spacings = {}, {}
    for _, face in ipairs(faces) do
        local key = face.base_family:lower()
        widths[key] = widths[key] or {}
        spacings[key] = spacings[key] or {}
        widths[key][widthIndex(face.fc_width)] = true
        spacings[key][spacingIndex(face.fc_spacing)] = true
    end
    local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
    local kinds = {}
    for _, face in ipairs(faces) do
        local key = face.base_family:lower()
        -- Grouped name, as crengine's installedName()
        local name = face.base_family
        local w = widthIndex(face.fc_width)
        if count(widths[key]) > 1 and w ~= WIDTH_NORMAL then
            name = name .. " " .. WIDTH_WORDS[w]
        end
        if count(spacings[key]) > 1 then
            name = name .. " " .. SPACING_WORDS[spacingIndex(face.fc_spacing)]
        end
        local k = kinds[name:lower()] or { italic = false, oblique = false }
        if face.slant == SlantInfo.ITALIC or face.ital_axis then k.italic = true end
        if face.slant == SlantInfo.OBLIQUE or face.slnt_axis then k.oblique = true end
        kinds[name:lower()] = k
    end
    return kinds
end

--[[--
Slant kinds offered by a font family (as named in crengine's font list).

@treturn table|nil { italic = bool, oblique = bool }, or nil if this family isn't
in crengine's font cache (so availability is unknown)
]]
function SlantInfo.getFamilyKinds(family)
    if not family or family == "" then return end
    if not kinds_by_family then
        kinds_by_family = buildKinds() -- nil without a cache: tried again next time
    end
    if not kinds_by_family then return end
    local k = kinds_by_family[family:lower()]
    return k and { italic = k.italic, oblique = k.oblique } or nil
end

return SlantInfo
