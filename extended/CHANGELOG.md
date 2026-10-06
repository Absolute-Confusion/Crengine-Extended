# Changelog

Changes of Crengine-Extended compared with upstream
[KOReader crengine](https://github.com/koreader/crengine). Each version is
compared with the crengine of its KOReader release, file by file (`git diff`
of the crengine sources), not from memory.

## koreader-2026.07.1-extended (2026-10-07)

For KOReader 2026.07.1 (and 2026.07.2, which uses the same crengine). Based on
crengine `b32a88ffbbf505cf2ea5208c1a49002d70d3609f` (2026-07-02): 13 crengine
source files changed, 1,267 lines added and 71 removed. On the KOReader side,
no KOReader file is changed: the project adds one plugin, Advanced Typography
Settings (version `2026.07.1-extended`).

### Added: settings per font category

Text is grouped into 9 categories by its CSS generic font family:
Unclassified (see below), serif, sans-serif, cursive, fantasy, monospace,
emoji, fangsong and math. Each category now has its own font weight, slant
type and decoration weight, independent of the other categories. Its font face
was already settable per category.

New document properties (`crengine/include/lvdocviewprops.h`), applied by
`LVDocView::propsApply()` (`lvdocview.cpp`), each change rerendering the
document:

| Setting | Unclassified | Other categories (`<c>` = serif, sans-serif, cursive, fantasy, monospace, emoji, fangsong, math) | Values |
|---|---|---|---|
| Font weight | `font.face.base.weight` (existing) | `crengine.generic.<c>.font.weight` | 1 to 1000 (default 400) |
| Slant type | `font.italic.style.default` | `crengine.generic.<c>.font.italic.style` | `Italic`, `Oblique`, `synthetic*` (default `Italic`) |
| Decoration weight | `font.face.decoration.weight` | `crengine.generic.<c>.font.decoration.weight` | 50 to 500, in % (default 100) |

- Getters and setters per category in `lvrend.cpp` / `lvrend.h`:
  `LVRendSet/GetGenericFontWeight()`, `LVRendSet/GetGenericItalicStyle()`,
  `LVRendSet/GetGenericDecorationWeight()`, `LVRendSet/GetBaseDecorationWeight()`,
  `LVRendSet/GetBaseItalicStyle()`, and per text family:
  `LVRendGetWeightForFont()`, `LVRendGetItalicStyleForFont()`,
  `LVRendGetDecorationWeightForFont()`, `LVRendGetSlantTypeForFont()`.
  Values are clamped (weight 1 to 1000, decoration weight 50 to 500).
- All these settings are part of the rendering settings hash
  (`calcGlobalSettingsHash()`, `lvtinydom.cpp`), so cached renderings are
  redone when one changes.

### Added: Unclassified category

- New font family value `css_ff_unclassified`, added last to
  `css_font_family_t` (`cssdef.h`) so the existing values don't change.
- Text with no generic family is now Unclassified instead of sans-serif:
  - text with no `font-family` at all (the document root's default,
    `ldomDocument::setRenderProps()`, and `DEFAULT_FONT_FAMILY` in
    `lvdocview.cpp`);
  - a `font-family` naming only specific fonts (eg. `font-family: 'Georgia'`):
    it no longer inherits its parent's category (`lvstsheet.cpp`);
  - `font-family: initial` (`lvstsheet.cpp`).
- Unclassified text uses the main font and the Unclassified settings, so
  changing sans-serif settings no longer changes it.
- The rendering settings hash gets a constant bump, so documents cached
  before this change are rerendered once with the new classification.

### Added: slant type (italic, oblique or synthetic)

Italic text of each category can use the family's italic faces, its oblique
faces, or upright faces slanted by crengine (`synthetic*`).

- **Face classification, as fontconfig's `fc-query`.** Every installed face
  gets a slant value, `LVFONT_SLANT_ROMAN` (0), `LVFONT_SLANT_ITALIC` (100) or
  `LVFONT_SLANT_OBLIQUE` (110) (`lvfntman.h`), computed by the new
  `LVFontGetFcSlant()` (`lvfntman.cpp`) the way fontconfig does it: the style
  names of the font's name table are checked in fontconfig's order (name IDs
  22, 17, then 2; Windows, Unicode, Mac, then ISO platforms; English names
  first), and the first containing "italic" or "kursiv" (italic) or "oblique"
  (oblique) decides; otherwise FreeType's italic flag. This works without
  fontconfig, which KOReader doesn't use. (Checked against `fc-query` on
  17,294 font faces: no difference.)
- **Selection** (`LVFontSelector::matchBySlantType()`, `lvfntman.cpp`): for
  italic text in installed fonts, the slant type picks the kind of face for
  the whole family, before the weight is chosen:
  - `Italic`: italic faces (or an `ital` variation axis); if the family has
    none, its oblique faces; if none either, upright faces with synthetic
    italic.
  - `Oblique`: oblique faces (or a `slnt` variation axis); if none, italic
    faces; then synthetic.
  - `synthetic*`: upright faces with synthetic italic (slanted faces only if
    the family has no upright face).

  All weights of a category's italic text thus use the same kind of face.
  Missing weights are synthesized from the chosen kind.
- **Embedded fonts** (from a book's `@font-face`) keep crengine's behaviour:
  they're tried first, and the slant type applies only to installed fonts.
- **Glyph fallback**: characters taken from the fallback fonts follow the slant
  type of the text's category (`GetFallbackFont()` gets the text's family).

### Added: width and spacing family grouping

Installed font families that mix widths or spacings are split into separate
families, as crengine-ng does, but only when they mix them
(`LVFontRegistry::registerInstalledFace()`, `lvfntman.cpp`):

- Width and spacing of each face are computed like fontconfig's `FC_WIDTH`
  (from the OS/2 `usWidthClass`, `LVFontGetFcWidth()`) and `FC_SPACING` (from
  the glyph advances, `LVFontGetFcSpacing()`), read without fontconfig.
  Variable-width fonts count as normal width.
- Within a family (FreeType's family name), a face gets a width word
  (`Ultra-Condensed` … `Ultra-Expanded`) only if the family has faces of
  several widths, and a spacing word (`Proportional`, `Duospace`, `Monospace`,
  `Charcell`) only if it has faces of several spacings, in that order. For
  example "Iosevka Slab" and "Iosevka Slab Expanded", or "CMU Typewriter Text
  Monospace" and "CMU Typewriter Text Proportional". Families of a single width
  and spacing keep their name.
- The names this replaces (crengine's former names, such as
  "DejaVu Sans Condensed", and family names no family has anymore) still find
  a font, the most regular one of the group, when a book asks for them; they
  aren't listed (`findFamily()`).
- Duplicate installed faces are detected with a hash table instead of a scan.

### Added: installed fonts cache

Startup registers installed fonts without opening their files, from a cache
(`lvfntman.cpp`):

- `cache/fontlist/crengine_fonts.dat`, next to KOReader's own font list cache
  (in crengine's document cache directory when it isn't named `cr3cache`). The
  new `ldomDocCache::getCacheDir()` (`lvtinydom.cpp`) gives that directory.
- A plain text file: a header (`crengine-extended fonts cache`, format version,
  numbers of files and faces), then per font file its path, size and
  modification time, and per face everything registration found (slant,
  width, spacing, names, variation axes...). Files that couldn't be registered
  are remembered too.
- A file whose size and modification time are unchanged is registered from the
  cache; a font file is only opened when a font is used. Added, changed and
  removed files are detected.
- Read at the first font registration; written by
  `RegularizeRegisteredFontsWeights()` (called once all fonts are registered),
  only if something changed, through a temporary file and a rename. An invalid
  cache is rebuilt.
- `FONTS_CACHE_VERSION` is to be increased whenever what is cached, or how it
  is computed, changes: existing caches are then rebuilt once.

### Changed: text decorations

- **Several decorations at once.** `text-decoration` values are now bit flags
  (`css_text_decoration_t`, `cssdef.h`: underline 2, overline 4, line-through
  8, blink 16), and the CSS parser reads several values
  (`text-decoration: underline line-through`) (`lvstsheet.cpp`).
- A decoration declared on an element adds to those of its ancestors, and
  `text-decoration: none` removes them (`renderFinalBlock()`, `lvrend.cpp`).
- **Decoration weight.** The thickness of underlines, overlines and
  line-throughs is scaled by the decoration weight of the decorated text's own
  category (50 % to 500 %, at least 1 pixel), in all 3 font
  drawing paths of `lvfntman.cpp`. The weight is stored per text fragment
  (`decoration_weight`, `lvtextfm.h` / `lvtextfm.cpp`) and passed to drawing in
  the flags (`LFNT_DRAW_DECORATION_WEIGHT_MASK`).
- When drawing, a decoration is joined with the previous word's only if both
  have the same decorations and weight (`LFormattedText::Draw()`).

### Changed: font weight

- The weight setting applying to a text is its category's
  (`getFont()`, `lvrend.cpp`): the existing base weight now applies to
  Unclassified text only.
- The base weight setting is no longer limited to upstream's 16 values
  (`propsUpdateDefaults()`, `lvdocview.cpp`).
- The document's default font object is created at weight 400
  (`LVDocView::setRenderProps()`); weights are applied per category.

### Changed: font identity (live changes)

So that changing a setting shows at once, also when a book is rerendered
partially:

- Font instances are cached per category and slant type: the instance key
  includes the requested family and slant type (`LVFontInstanceKey`), and a
  font reports the category it was requested for (`getFontFamily()`).
- A font's face slant (`getFaceSlant()`, `lvfntman.h`) is part of its identity
  (`calcHash()`, `lvstyles.cpp`, and `operator==`, `lvfntman.cpp`), so italic
  and oblique fonts are never confused by the document's font cache.

### Added: Advanced Typography Settings plugin (KOReader)

`advancedtypography.koplugin`: a menu for all of the above, in the reader's
document (typeset) menu, right after KOReader's "Typography rules".

- For each of the 9 categories (1. Default (unclassified) … 9. Math):
  - **Font Face**: a searchable list of crengine's fonts, or "(Use main font)".
  - **Font Weight**: 100 to 1000, by 25.
  - **Slant Type**: Italic, Oblique or synthetic\*. A kind the category's font
    doesn't have is greyed out, and if the current one isn't available it is
    switched to synthetic\*. The font kinds come from crengine's own
    classification, read from its font cache (`slantinfo.lua`).
  - **Decoration Weight**: 50 % to 500 %, by 25.
- **Font cache**: size, date and number of fonts of the cache, with Clear and
  Rebuild.
- All settings, font faces included, are global (the same for all books):
  KOReader's per-book font choices are ignored and no longer saved, and fonts
  picked in KOReader's own font menus become the global ones. Grouped family
  names (eg. "Iosevka Slab Expanded") are accepted there.
- Changes apply at once. Settings are kept in memory and written to disk with
  KOReader's own saving (closing a book, suspend, exit), never on each change.
  Settings are also flushed before KOReader exits.
- KOReader's own font weight slider is hidden (the per-category weights
  replace it).

### Added: release packages

- A Linux AppImage of KOReader with Crengine-Extended, built in KOReader's
  AppImage container.
- Android APKs of **KOReader Extended**: a separate app (its own app ID,
  `io.github.absoluteconfusion.koreader`, and name) that installs next to the
  official KOReader, with KOReader's in-app updater off. Built by
  `android/build_apk.sh` in KOReader's Android container, with a Gradle init
  script (`android/init.gradle`): no KOReader file is changed.

### Added (2026-10-08)

- Plugin: **No document cache**, the menu's last entry (off by default). When
  on, crengine keeps no cache file of opened books (`cache/cr3cache`): turning
  it on deletes the existing ones, and opening or closing a book writes none.
  Books are laid out again at each opening (slower for large books), and a
  setting change lays out the whole book. The font cache is kept. A new test,
  suite 14, checks it. No crengine change.

### Fixed (2026-10-08)

- Android: opening a book failed with "No reader engine for this file or
  invalid file." The plugin classified fonts itself by calling FreeType and
  HarfBuzz functions directly, which KOReader's Android build doesn't provide.
  It now reads crengine's classification from crengine's font cache, with no
  direct library calls (a new test, suite 13, checks this). The Android APK of
  this version was rebuilt.

### Files changed (crengine)

| File | Added | Removed |
|---|---:|---:|
| `crengine/include/cssdef.h` | 8 | 5 |
| `crengine/include/lvdocviewprops.h` | 37 | 0 |
| `crengine/include/lvfntman.h` | 13 | 1 |
| `crengine/include/lvrend.h` | 18 | 0 |
| `crengine/include/lvtextfm.h` | 7 | 1 |
| `crengine/include/lvtinydom.h` | 2 | 0 |
| `crengine/src/lvdocview.cpp` | 158 | 5 |
| `crengine/src/lvfntman.cpp` | 753 | 31 |
| `crengine/src/lvrend.cpp` | 212 | 11 |
| `crengine/src/lvstsheet.cpp` | 18 | 7 |
| `crengine/src/lvstyles.cpp` | 1 | 0 |
| `crengine/src/lvtextfm.cpp` | 21 | 9 |
| `crengine/src/lvtinydom.cpp` | 19 | 1 |
| **13 files** | **1,267** | **71** |
