# Crengine-Extended: design

How and why Crengine-Extended works: the principles behind each change to
crengine and to the Advanced Typography Settings plugin, the variables they use,
how a setting travels from the menu to the page and to disk, and the decisions
and pitfalls that shaped it.

**Who this is for:** anyone (a developer or an AI agent) who changes this
project, or ports it to a newer KOReader, especially when upstream has
reworked code this project depends on and the patch can't simply be merged.
With this document you shouldn't have to rediscover how to make a setting
independent per category, take effect at once, survive a reopen, and so on.

**Scope:** this version, `koreader-2026.07.1-extended` (crengine `b32a88f`).
Paths are relative to the repository root (crengine's own tree), except
`extended/...` (this folder) and KOReader paths, written `koreader:...`.
Code is referred to by file and function, not by line number.

Related documents: [README.md](README.md) (install, test, port),
[CHANGELOG.md](CHANGELOG.md) (what changed), [tests/README.md](tests/README.md).

## Contents

1. [Overview](#1-overview)
2. [Context: crengine and KOReader before](#2-context-crengine-and-koreader-before)
3. [Goals and non-goals](#3-goals-and-non-goals)
4. [Glossary](#4-glossary)
5. [Principles](#5-principles)
6. [Design, change by change](#6-design-change-by-change)
7. [The life of a setting](#7-the-life-of-a-setting)
8. [Why the categories are independent](#8-why-the-categories-are-independent)
9. [Decision records](#9-decision-records)
10. [Pitfalls and failed approaches](#10-pitfalls-and-failed-approaches)
11. [Invariants and tests](#11-invariants-and-tests)
12. [Porting checklist](#12-porting-checklist)

## 1. Overview

A book marks its text with CSS generic font families (`serif`, `monospace`...).
Crengine-Extended treats each of these, plus text with none, as a **category**:
9 in all. Each category gets 4 **attributes**: font face, font weight, slant
type and decoration weight. Each attribute of each category is set on its own,
for all books, and changing one never affects another (36 settings).

Most of the work is in crengine, KOReader's rendering engine: it stores the
settings per category, applies them to the right text, chooses italic or
oblique font files strictly, groups font families by width and spacing, and
caches its font list. A KOReader plugin, Advanced Typography Settings, gives
them a menu, keeps them global, and saves them KOReader's way.

## 2. Context: crengine and KOReader before

What a reader of this document needs to know about upstream before the
changes (crengine `b32a88f`, KOReader 2026.07):

- **Generic families.** crengine's `css_font_family_t` (`crengine/include/cssdef.h`)
  lists the CSS generic families: `css_ff_inherit`, then serif, sans-serif,
  cursive, fantasy, monospace, math, emoji, fangsong. Each element's computed
  style has one (`style->font_family`) and a list of font names
  (`style->font_name`).
- **Per-family fonts already existed.** KOReader's "font-family fonts" let a
  font be picked per generic family. KOReader sends them to crengine as one
  string, "ignore-flag|serif|sans-serif|cursive|fantasy|monospace|math|emoji|fangsong"
  (`koreader:frontend/document/credocument.lua`, `setFontFamilyFontFaces()`).
  When crengine parses a `font-family` value, it replaces the generic family
  name with the font set for it, if any (`crengine/src/lvstsheet.cpp`,
  `LVCssDeclaration::parse()`, `cssd_font_family`).
- **One weight, one italic, one decoration.** There was a single weight setting
  (`font.face.base.weight`, read by `getFont()` in `crengine/src/lvrend.cpp`)
  for all text, an italic flag only (no italic/oblique distinction), and one
  decoration thickness taken from the font.
- **Text with no generic family was sans-serif.** Untagged text, a
  `font-family` naming only specific fonts, and `font-family: initial` all
  became `css_ff_sans_serif` (crengine's default family). So sans-serif
  settings changed text that had no category.
- **Font selection.** `LVFontManager::GetFont()` (`crengine/src/lvfntman.cpp`)
  finds a family by the style's font names, then the user's preferred font,
  then any family of the right generic kind (`LVFontSelector::select()`), and
  picks a face by weight and italic flag (`matchFamily()`, `pickBestWeight()`).
  Missing weights or italics are synthesized (emboldening, slanting).
- **Caches that decide what you see.** A document keeps the fonts it uses in a
  cache that deduplicates fonts considered equal (`_fonts` in
  `crengine/include/lvtinydom.h`; equality from `calcHash(font_ref_t)` in
  `crengine/src/lvstyles.cpp` and `operator==(LVFont)` in `lvfntman.cpp`).
  Rendering results are cached too, and invalidated by a hash of the global
  settings (`calcGlobalSettingsHash()`, `crengine/src/lvtinydom.cpp`).
- **Partial rerendering.** For an EPUB with a cache file, once the book is
  open, KOReader enables partial rerendering: after a settings change, crengine
  restyles and re-lays out only the part being displayed, at drawing time,
  reusing the document's caches.
- **KOReader settings.** Global settings live in `G_reader_settings`
  (`settings.reader.lua`), per-book ones in each book's sidecar (`.sdr`).
  `saveSetting()` only changes memory; KOReader writes to disk when a book is
  closed, on suspend, on exit, and by an autosave every 15 minutes (on a page
  turn), never per change.
- **KOReader's call cache.** When a document opens, `CreDocument:setupCallCache()`
  (`koreader:frontend/document/credocument.lua`) copies many of the
  document class's methods onto the document object, wrapped with caching.
  Patching the class afterwards doesn't affect an open document.

## 3. Goals and non-goals

**Goals**

- 9 categories (Unclassified and the 8 generic families) × 4 attributes, each
  set independently: changing one never changes another category's text.
- The settings are global: the same for every book.
- Every change shows at once, without reopening the book.
- Settings are written to disk only at KOReader's normal saving points
  (deferred writes), and are applied again on reopening and relaunching.
- Italic and oblique are told apart reliably, the way fontconfig (`fc-query`)
  does, on every platform, without fontconfig.
- It works on Linux and Android, from the same code.

**Non-goals (deliberately unchanged)**

- How bold relates to the weight setting: bold text stays 300 heavier than the
  weight set (upstream's offset), see [6.3](#63-font-weight).
- Fonts embedded in books keep crengine's behaviour while KOReader's "Embedded
  fonts" option is on ([ADR-09](#adr-09-embedded-book-fonts-keep-crengines-behaviour-owner)).
- KOReader's other per-book settings (font size, margins...) stay per book.
- No KOReader file is changed: the KOReader side is only the plugin.

## 4. Glossary

| Term | Meaning |
|---|---|
| **Category** | One of the 9: Unclassified, serif, sans-serif, cursive, fantasy, monospace, emoji, fangsong, math. A piece of text's category is its style's `font_family` (inherited like any `font-family`). The plugin and property names call Unclassified **`base`**. |
| **Generic family** | A CSS generic font family (`serif`...). The 8 non-Unclassified categories are exactly these (`css_ff_serif`...`css_ff_fangsong`). |
| **`css_ff_unclassified`** | The new `css_font_family_t` value for text with no generic family. Added last in the enum so existing values don't move. |
| **Attribute** | Font face, font weight, slant type, decoration weight. |
| **Main font** | KOReader's main font (`cre_font`): Unclassified's font face, and the font of any category with no font of its own. |
| **Slant type** | A category's setting for slanted text: `Italic`, `Oblique` or `synthetic*`. In crengine, `LVFONT_SLANT_ITALIC` (100), `LVFONT_SLANT_OBLIQUE` (110) or `LVFONT_SLANT_ROMAN` (0, meaning synthetic). |
| **Face slant** | How a font face is classified: 0 (roman/upright), 100 (italic) or 110 (oblique): fontconfig's `FC_SLANT`, the value `fc-query` reports. Stored in `LVFontFace::slant`. |
| **Kind** | Italic or oblique: the two kinds of slanted face. |
| **Synthetic italic** | An upright face slanted by FreeType (`italicize`). **Synthetic weight**: a face emboldened or lightened to a missing weight. |
| **Installed / embedded font** | An installed font is registered from a font file (`documentId == -1`); an embedded one comes from a book's `@font-face` (`documentId` of that book). |
| **Base family** | A face's FreeType family name (`LVFontFace::base_family`), before width/spacing grouping. |
| **Grouped name** | The family name crengine lists (`LVFontFace::typeface`): the base family, plus a width word and/or a spacing word when the family mixes widths or spacings. |
| **Former name** | The name crengine gave a face before grouping (`legacy_name`, eg. "DejaVu Sans Condensed"), still usable by books. |
| **`fc_width`, `fc_spacing`** | A face's width and spacing as fontconfig reports them (`FC_WIDTH`: 50...200, 100 = normal; `FC_SPACING`: 0 proportional, 90 dual, 100 mono, 110 charcell). |
| **Property** | A crengine document setting, set by name (`setIntProperty()`, `setStringProperty()` in KOReader) and applied by `LVDocView::propsApply()`. |
| **Settings hash** | `calcGlobalSettingsHash()`: a hash of every global setting that affects rendering. When it changes, crengine recomputes styles and rendering. |
| **Font identity** | What makes two font objects "the same" for a document's font cache: `calcHash(font_ref_t)` and `operator==(LVFont)`. |
| **Font instance key** | `LVFontInstanceKey`: the font manager's key for its cache of loaded font instances. |
| **Partial rerendering** | crengine re-laying out only the displayed part of a book after a change, at drawing time (EPUBs with a cache file). |
| **Deferred writes** | Settings changed in memory only, written to disk at KOReader's saving points. |
| **Font cache** | crengine's installed fonts cache, `cache/fontlist/crengine_fonts.dat`: what registering each font file found. Not KOReader's `fontinfo.dat`, which is KOReader's own font list cache. |
| **Call cache** | KOReader's per-document copies of document methods (see [2](#2-context-crengine-and-koreader-before)). |

## 5. Principles

The rules everything follows. Each section of [6](#6-design-change-by-change)
applies them; breaking one is how earlier attempts failed
([10](#10-pitfalls-and-failed-approaches)).

**P1. A category is decided once, from the book's CSS, and belongs to the text.**
Text's category is its style's `font_family`: the generic family named in its
`font-family` value, inherited from its parent like any `font-family` when it
has none of its own, and Unclassified at the document's root. A `font-family`
naming only specific fonts makes the text Unclassified: it doesn't keep its
parent's category. It's decided when styles are computed, and everything else
only reads it.

**P2. Every attribute is stored per category and read by the text's category,
at exactly one place.** Weight is read in `getFont()`, slant type in
`GetFont()`, decoration weight in `renderFinalBlock()`, each with the text's
`style->font_family`. Nothing reads another category's value, so nothing can
leak.

**P3. Whatever changes what's drawn is part of every identity that could reuse
an old result.** Each setting is in the settings hash (so cached rendering is
redone), and each property of a font object that changes its glyphs is in the
font identity and the font instance key (so a cached font isn't reused in its
place).

**P4. Reuse the existing paths; don't invent new ones.** A setting is a
crengine property, applied by `propsApply()`, which requests a re-render. The
plugin redraws with KOReader's own sequence. The tests use the same paths.

**P5. Global settings, deferred writes.** Settings live in KOReader's global
settings, in memory. They're written to disk only at KOReader's own saving
points, and applied to crengine whenever a book opens.

**P6. Classify fonts the way fontconfig does, once, in crengine.** crengine
computes each face's slant, width and spacing as `fc-query` reports them,
without fontconfig, at registration, and records them in its font cache.
Everything else (the plugin included) reads that classification and never
recomputes it.

**P7. Decide the kind before the weight.** For slanted text, the kind of face
(italic, oblique or upright) is chosen for the whole family first, and only
then the weight within that kind, so all weights of a category get the same
kind.

**P8. Change only what's needed.** Behaviour not named in the goals stays as
upstream had it, and existing values (enum values, property names) keep their
meaning.

**P9. Portable code.** The plugin calls no C function directly (FFI): on
Android, KOReader's single native library only provides the functions
KOReader itself uses.

## 6. Design, change by change

Each part follows the same pattern: the principle in plain words, the
variables, how it works step by step, and where it is.

### 6.1 Text categories and Unclassified

**In plain words.** Every piece of text belongs to exactly one category. Like
any `font-family`, a category is inherited: a paragraph inside a serif `<div>`
is serif. Text with no generic family (none in its own `font-family`, nor
inherited, or a `font-family` naming only specific fonts) belongs to
Unclassified, a category of its own, instead of being counted as sans-serif.

**Variables**

- `css_ff_unclassified` (`crengine/include/cssdef.h`): added last to
  `css_font_family_t`.
- `DEFAULT_FONT_FAMILY` (`crengine/src/lvdocview.cpp`): now `css_ff_unclassified`.
- `_preferred_by_css_family[css_ff_unclassified+1]` (`lvfntman.cpp`): sized to
  include the new value.

**How it works**

1. The document root's style gets `font_family = css_ff_unclassified`
   (`ldomDocument::setRenderProps()`, `lvtinydom.cpp`). It used to take the
   default font's family, which, for a shared font instance, could report
   another category.
2. When a `font-family` value is parsed (`lvstsheet.cpp`, `cssd_font_family`),
   its generic family names are replaced by the category fonts (upstream
   behaviour), and the left-most generic family becomes the text's category.
   If there's none, the category is now `css_ff_unclassified` (it used to be
   sans-serif). `font-family: initial` also gives `css_ff_unclassified`.
3. Unclassified text has no category font in KOReader's per-family string (it
   has 8 slots; Unclassified isn't one of them), so its font comes from the
   font names in its `font-family`, else the main font: `GetFont()` with
   `useBias` uses `_preferred_by_css_family[css_ff_unclassified]`, which is
   empty, so the preferred family is the main font.
4. Its attributes are the `base` settings ([6.2](#62-per-category-settings-storage-and-lookup)).
5. Because the classification changed, a constant in the settings hash was
   bumped (`calcGlobalSettingsHash()`, "+ 1"): books cached before are restyled
   once.

### 6.2 Per-category settings: storage and lookup

**In plain words.** Each category has its own three values (weight, slant type,
decoration weight), set through crengine properties. A single lookup function
per attribute turns a text's category into its value; Unclassified (and
anything that isn't one of the 8 generic families) uses the `base` values.

**Properties** (`crengine/include/lvdocviewprops.h`; also the keys in
KOReader's global settings)

| Category | Weight | Slant type | Decoration weight |
|---|---|---|---|
| Unclassified (`base`) | `font.face.base.weight` (upstream) | `font.italic.style.default` | `font.face.decoration.weight` |
| `<c>` = serif, sans-serif, cursive, fantasy, monospace, emoji, fangsong, math | `crengine.generic.<c>.font.weight` | `crengine.generic.<c>.font.italic.style` | `crengine.generic.<c>.font.decoration.weight` |
| Values | 1 to 1000 in crengine (Unclassified: 1 to 999, upstream's setter); the menu: 100 to 1000, by 25; default 400 | `Italic`, `Oblique`, `synthetic*`; default `Italic` | 50 to 500 (%); default 100 |

**Storage** (`crengine/src/lvrend.cpp`)

- Unclassified: `rend_font_base_weight` (upstream), `rend_font_base_italic_style`,
  `rend_font_base_decoration_weight`.
- The 8 generic families: `s_generic_font_family_weights[8]`,
  `s_generic_font_family_italic_styles[8]`,
  `s_generic_font_family_decoration_weights[8]`, indexed by
  `family - css_ff_serif`.
- Setters clamp values: weight 1 to 1000 (Unclassified's, upstream's setter: 1 to 999),
  decoration weight 50 to 500. The weight finally used is clamped to 999 anyway (6.3).

**Lookup by the text's category** (`lvrend.cpp`):
`LVRendGetWeightForFont(family)`, `LVRendGetItalicStyleForFont(family)`,
`LVRendGetDecorationWeightForFont(family)`, `LVRendGetSlantTypeForFont(family)`.
For `css_ff_serif` to `css_ff_fangsong` they return that family's value,
otherwise (Unclassified, `css_ff_inherit`) the `base` value.
`LVRendGetSlantTypeForFont()` maps `Oblique` to 110, `synthetic*` to 0, and
anything else (`Italic`, or unset) to 100.

**How a property is applied** (`LVDocView::propsApply()`, `lvdocview.cpp`):
for each property, if the value differs, call the setter, then
`REQUEST_RENDER` (see [7.1](#71-changing-a-setting)).

**Settings hash** (`calcGlobalSettingsHash()`, `lvtinydom.cpp`): includes the
8 generic families' weight, decoration weight and slant type,
Unclassified's weight (upstream) and slant type. Unclassified's decoration
weight isn't in it: decoration thickness doesn't change the layout, and every
property change clears the formatted paragraphs (see [6.5](#65-decoration-weight-and-several-decorations)),
so it doesn't need to be (tests 06 and 07 check it live and after reopening).

### 6.3 Font weight

**In plain words.** Each category's weight shifts all of its text's weights by
the same amount, as KOReader's single weight setting did for all text. Bold
stays 300 heavier than the weight set.

**How it works** (`getFont()`, `lvrend.cpp`)

1. Take the CSS weight of the text (`style->font_weight`, eg. 400 for normal,
   700 for bold; `bolder`/`lighter` are already resolved to numbers from the
   parent), or 400.
2. Add `LVRendGetWeightForFont(style->font_family) - 400`: the text's
   category's setting. (Upstream added `rend_font_base_weight - 400`, the
   single setting, for all text.)
3. Clamp to 1...999, and ask `GetFont()` for that weight. Missing weights are
   synthesized by the font manager, as before.

Related: the document's default font object is created at weight 400
(`LVDocView::setRenderProps()`), since weights now apply per category; the
upstream list of 16 allowed base weights is gone (`propsUpdateDefaults()`), so
any weight works; the plugin hides KOReader's own weight slider.

### 6.4 Slant type

**In plain words.** Each category says which kind of face its slanted text
uses: italic files, oblique files, or the upright files slanted by the engine.
A family's faces are classified exactly like `fc-query` does. The kind is
decided for the whole family before the weight, so a category's regular and
bold slanted text always get the same kind. If the font lacks the chosen kind,
the other kind is used, then synthetic; the menu prevents choosing a kind the
category's own font lacks.

**Variables**

- `LVFontFace::slant` (`lvfntman.cpp`): the face's slant, 0/100/110.
- `LVFONT_SLANT_ROMAN/ITALIC/OBLIQUE` (`crengine/include/lvfntman.h`).
- The slant type per category ([6.2](#62-per-category-settings-storage-and-lookup)).
- `LVFontMatch::italicize`: -1 = decide as before; 0/1 = decided by the slant type.
- `LVFontInstanceKey::slant_type`: the slant type a font instance was chosen for.

**Classification** (`LVFontGetFcSlant()`, `lvfntman.cpp`), done when a font
file is registered, as fontconfig does:

1. Look at the face's style names in its name table, in fontconfig's order:
   name IDs 22 (WWS subfamily), 17 (typographic subfamily), then 2 (subfamily);
   platforms Windows, Unicode, Mac, then ISO; English names first, then the
   others in table order.
2. The first name containing a slant keyword decides: "italic" or "kursiv" →
   100; otherwise "oblique" → 110. Case and spaces are ignored.
3. Without any such name, FreeType's italic flag decides (100 or 0).

This is checked against `fc-query` on every test font and, on the developer's
system, on 12,389 installed font faces: no difference (test suite 12).

**Selection** (`LVFontSelector::matchFamily()` and `matchBySlantType()`,
`lvfntman.cpp`), for slanted text (`font-style: italic` or `oblique`: both mean
"slanted"; the slant type decides which kind):

1. `GetFont()` gets the text's category, and asks
   `LVRendGetSlantTypeForFont(category)` for its slant type (only for slanted
   text).
2. In each candidate family (see [2](#2-context-crengine-and-koreader-before)
   for the order), the book's embedded faces are tried first, as upstream did.
3. Otherwise, `matchBySlantType()` sorts the family's installed faces into
   three groups: italic (slant 100, or a variable `ital` axis going above 0.5),
   oblique (slant 110, or a variable `slnt` axis going below 0), and upright
   (slant 0).
4. It takes the groups in the slant type's order: Italic → italic, oblique,
   upright; Oblique → oblique, italic, upright; synthetic* → upright, italic,
   oblique. The first group that has faces is used for the whole family.
5. Within that group, the best weight is picked (`pickBestWeight()`); a missing
   weight is synthesized from that face, never taken from the other kind.
6. Upright group → synthetic italic (`italicize = 1`). Italic group with a
   variable face that isn't itself italic → its `ital` axis is set to 1.
   Oblique group likewise → its `slnt` axis is set to -12.
7. `loadAndCache()` uses `italicize` from the match when set.

**Fallback glyphs.** Characters missing from the chosen font come from the
fallback fonts. Font objects now remember the category they were requested
for (`loadAndCache()` passes the requested family, so `getFontFamily()`
returns the category), and `getFallbackFont()` passes it to
`GetFallbackFont()`, which calls `GetFont()` with it: fallback glyphs follow
the text's slant type.

**In the plugin** ([6.9](#69-the-plugin)): kinds the category's font lacks are
greyed out, and a category whose font changes to one lacking its slant type is
switched to `synthetic*`.

### 6.5 Decoration weight, and several decorations

**In plain words.** Underlines, overlines and line-throughs get a thickness
per category (50 % to 500 % of the font's own thickness). A decorated piece of
text uses its own category's decoration weight. CSS can now ask for several
decorations at once.

**Variables**

- `css_text_decoration_t` (`cssdef.h`): now bit flags: none 1, underline 2,
  overline 4, line-through 8, blink 16 (`css_td_inherit` stays 0).
- `formatted_text_fragment_t::decoration_weight` and
  `LFormattedText::m_current_decoration_weight` (`crengine/include/lvtextfm.h`).
- `LFNT_DRAW_DECORATION_WEIGHT_MASK` (`lvfntman.h`): bits 16...24 of a draw
  call's flags.

**How it works**

1. **Parsing** (`lvstsheet.cpp`, `cssd_text_decoration`): several values are
   read and OR-ed (`underline line-through`). `none` and `inherit` stay alone.
2. **Inheritance:** crengine copies a parent's `text_decoration` to children
   that don't set their own (upstream: `UPDATE_STYLE_FIELD(text_decoration...)`
   in `lvrend.cpp`). So every element inside decorated text carries the
   decoration in its own style.
3. **Laying out a paragraph** (`renderFinalBlock()`, `lvrend.cpp`): for an
   element whose style has a decoration, its flags are added to those passed
   down (`none` clears them), and the current decoration weight becomes
   `LVRendGetDecorationWeightForFont(style->font_family)`: that element's own
   category. A scope guard (`WeightRestorer`) restores the previous weight when
   the element ends, so a child's weight never leaks to text after it.
4. Each text fragment added (`AddSourceLine()`, `AddSourceObject()`) records
   the current decoration weight.
5. **Drawing** (`LFormattedText::Draw()`, `lvtextfm.cpp`): the weight goes into
   the draw flags; a decoration is joined with the previous word's only if both
   have the same decorations and weight.
6. **The font draws the line** (`DrawTextString()` in the 3 font classes of
   `lvfntman.cpp`): thickness = the font's thickness × weight / 100, at least
   1 pixel.

Every property change clears the formatted paragraphs (`requestRender()` calls
`clearRendBlockCache()`), so step 3 runs again with the new weight.

### 6.6 Font identity

**In plain words.** Two font objects are "the same" only if they draw the same
glyphs. Otherwise a document's font cache, or the font manager's instance
cache, could hand back an old font after a change.

**How it works**

- **The face's slant is part of a font's identity:** `getFaceSlant()` (new
  virtual in `LVFont`, set from `LVFontFace::slant` in `loadAndCache()`,
  delegated by font wrappers) is in `calcHash(font_ref_t)` (`lvstyles.cpp`) and
  in `operator==(LVFont)` (`lvfntman.cpp`), exactly like upstream's
  `getSynthWeight()`. An italic and an oblique face of the same family, size
  and weight are otherwise identical by every other property.
- **The category is part of it too:** a font reports the category it was
  requested for (`getFontFamily()`), which is already in both.
- **The font instance key** (`LVFontInstanceKey`) includes the requested
  category and slant type, so two categories sharing a family but not a slant
  type get different instances.

Why it matters: see the live Italic ↔ Oblique pitfall in [10](#10-pitfalls-and-failed-approaches).

### 6.7 Width and spacing family grouping

**In plain words.** A font family whose files mix widths (eg. normal and
Expanded) or spacings (proportional and monospace) is split into separate
entries, named by adding a width word and/or a spacing word, but only when the
family mixes them. Old names keep working in books.

**Variables** (`lvfntman.cpp`)

- `LVFontFace::base_family`, `legacy_name`, `fc_width`, `fc_spacing`.
- `kFcWidthWords`: Ultra-Condensed, Extra-Condensed, Condensed, Semi-Condensed,
  (normal: no word), Semi-Expanded, Expanded, Extra-Expanded, Ultra-Expanded;
  `fcWidthIndex()` maps `fc_width` to them (crengine-ng's thresholds).
- `kFcSpacingWords`: Proportional, Duospace, Monospace, Charcell;
  `fcSpacingIndex()`.
- In `LVFontRegistry`: `_installed_masks` (widths and spacings present per base
  family), `_installed_aliases` (replaced names → grouped family),
  `_installed_faces` (registered files, for duplicate checks).

**How it works**

1. **Measuring** (at registration, `RegisterFont()`): `fc_width` from the OS/2
   table's `usWidthClass` (1...9 → 50, 63, 75, 87, 100, 113, 125, 150, 200), as
   fontconfig does (`LVFontGetFcWidth()`); 100 for variable-width fonts.
   `fc_spacing` by fontconfig's method (`LVFontGetFcSpacing()`): the glyph
   advances of the font's charmap, read unscaled: one advance → monospace
   (100), two with one twice the other → dual (90), anything else →
   proportional (0).
2. **Naming** (`registerInstalledFace()`, `installedName()`): the face's base
   family is FreeType's family name. Its masks gain its width and spacing. The
   name is: base family + width word (only if the family has several widths
   and this face isn't normal width) + spacing word (only if it has several
   spacings).
3. **A first collision renames the faces registered before**
   (`regroupInstalledFamily()`).
4. **Former names** (the face's previous name and its base family name, when
   no family has them any more) are kept as hidden aliases to the most regular
   face's group (upright, normal width, weight nearest 400). `findFamily()`
   uses them as a last resort, so books naming "DejaVu Sans Condensed" still
   work; they aren't listed.
5. Fonts embedded in books aren't grouped.

### 6.8 Installed fonts cache

**In plain words.** crengine remembers what it found in each installed font
file, so later startups register fonts without opening the files. A file is
only opened when its font is actually used. The cache is only rewritten when
font files were added, changed or removed.

**Variables** (`LVFreeTypeFontManager`, `lvfntman.cpp`)

- `_fonts_cache`: font file path → `CachedFontFile` (size, modification time,
  seen this session, faces as registered, or none if the file was refused).
- `_fonts_cache_path`, `_fonts_cache_loaded`, `_fonts_cache_dirty`.
- `FONTS_CACHE_MAGIC` ("crengine-extended fonts cache"), `FONTS_CACHE_VERSION`.

**The file** (`cache/fontlist/crengine_fonts.dat`, next to KOReader's
`fontinfo.dat`): its path comes from crengine's document cache directory
(`ldomDocCache::getCacheDir()`, new): when that's `.../cache/cr3cache`, the
sibling `.../cache/fontlist`. Plain text, tab-separated:

- a header: magic, format version, number of files, number of faces;
- per file, `F`, path, size, modification time;
- per face, `S` and 27 fields: face index, italic flag, slant, CSS family,
  typeface, base family, former name, width, spacing, emojis, math, small caps,
  then present/min/max of the `wght`, `opsz`, `ital`, `slnt` and `wdth` axes.

**How it works**

1. **Read** on the first `RegisterFont()` (`loadFontsCache()`). A wrong magic
   or version, or a malformed line, makes it rebuild.
2. **Registering a file** (`RegisterFont()`): if its size and modification
   time match its record, its faces are registered from the record without
   opening it (a refused file stays refused); otherwise it's opened and
   inspected, and its record replaced (the cache becomes dirty).
3. **Written** by `RegularizeRegisteredFontsWeights()`, which KOReader calls
   once all fonts are registered (`saveFontsCache()`): files no longer present
   are dropped, and the file is written only if something changed, through a
   temporary file and a rename.
4. Increase `FONTS_CACHE_VERSION` whenever what is cached, or how it's
   computed, changes: every cache is then rebuilt once. The plugin reads this
   file too (see 6.9); update its reader if the format changes.

### 6.9 The plugin

`extended/plugin/advancedtypography.koplugin`: `main.lua` (menus and KOReader
integration), `slantinfo.lua` (slant kinds per family), `fontchooser.lua` (the
font list).

**Menu.** "Advanced Typography Settings" in the reader's document menu, right
after KOReader's "Typography rules": the plugin inserts its key,
`advanced_typography`, into KOReader's menu order table
(`koreader:frontend/ui/elements/reader_menu_order.lua`, which KOReader keeps
cached so plugins can add to it). Entries: the 9 categories, each with Font
Face, Font Weight, Slant Type and Decoration Weight; then Font cache and No
document cache.

**Module name.** KOReader names a plugin's module after its folder:
`advancedtypography`, not `typography`, which would replace KOReader's own
Typography module (`ui.typography`) and disable custom hyphenation.

**Changing a setting** (the weight, slant type and decoration weight menus):
set the crengine property, save the value in `G_reader_settings`, then redraw
with KOReader's sequence: `resetCallCache()`, `resetBufferCache()`,
`view:recalculate()`, `UIManager:setDirty(nil, "full")`. See [7.1](#71-changing-a-setting).

**Applying settings when a book opens** (`Typography:onReadSettings()`): all
27 values in `G_reader_settings` are set as crengine properties. Plugins are
registered after KOReader's own modules, so this runs after KOReader's
`ReaderFont:onReadSettings()`, which applies the book's own base weight: the
plugin's global value is the one crengine ends with.

**Font faces made global** (`_patchReaderFontGlobal()`, patching KOReader's
`ReaderFont` class):

- `onReadSettings`: the book's `font_face` and `font_family_fonts` are deleted
  before KOReader reads them, so the global `cre_font` and
  `cre_font_family_fonts` apply.
- `onSaveSettings`: they're deleted again, so they're never saved per book.
- `onSetFont`: KOReader's own font menu choice is saved globally (`cre_font`),
  and grouped family names (eg. "Iosevka Slab Expanded"), which KOReader's own
  check rejects since no file has that name, are accepted when crengine lists
  them.
- `updateFontFamilyFonts`: choices made in KOReader's own font-family menu are
  moved into the global `cre_font_family_fonts`.

**Tracking each category's font, and keeping its slant type available**
(`_patchDocumentFonts()`): the open document's own `setFontFace` and
`setFontFamilyFontFaces` are wrapped (not the class's: see the call cache in
[2](#2-context-crengine-and-koreader-before)). They remember the main font and
the family fonts, then `enforceSlantAvailability()`: for each category whose
font lacks its slant type's kind, the slant type becomes `synthetic*` (saved
and applied).

**Greying out** (the Slant Type menu): `SlantInfo.getFamilyKinds(font)` says
which kinds the category's font has; the others are disabled. If unknown,
nothing is disabled.

**`slantinfo.lua`** reads crengine's font cache (6.8) with plain file reading:
each face's slant, `ital`/`slnt` axes, base family, width and spacing; it
rebuilds the grouped names with crengine's rule (6.7) and records, per family,
whether it has italic and oblique faces (as `matchBySlantType()` sorts them).
No FreeType or HarfBuzz call (P9).

**Saving to disk** (`_patchDeviceExit()`): settings are flushed before
KOReader tears the device down on exit (`Device.exit`), then KOReader's own
exit continues. Nothing else is written by the plugin (No document cache
deletes files).

**Other:** KOReader's own weight slider is hidden (`_patchNativeFontWeight()`);
the Font cache menu shows the cache's size, date and counts, with Clear and
Rebuild (which asks for a restart).

**No document cache** (`advancedtypography_no_document_cache`, global, off by
default): when a book opens, `crengine.cache.filesize.min` is set out of
reach, so crengine creates no cache file for it (`cache/cr3cache`); one it
creates anyway, running short of memory, is deleted at the next opening.
Turning it on (after confirming) deletes the book caches and crengine's index
of them, then starts crengine's document cache again
(`CreDocument.cacheInit()`): crengine keeps a list of the books it cached and
would create an empty file when one of them opens. Without a cache file there
is no partial rerendering: a setting change lays out the whole book again, with
the same result (test suite 14). The font cache (6.8) is kept.

## 7. The life of a setting

### 7.1 Changing a setting

Example: Serif's slant type set to Oblique in the menu.

1. **Plugin** (`main.lua`, the Slant Type button):
   `document._document:setStringProperty("crengine.generic.serif.font.italic.style", "Oblique")`.
2. **KOReader's crengine binding** (`koreader:base/cre.cpp`,
   `setStringProperty()`): puts it in a property container and calls
   `LVDocView::propsApply()`.
3. **crengine** (`propsApply()`): the value differs →
   `LVRendSetGenericItalicStyle(css_ff_serif, "Oblique")` →
   `REQUEST_RENDER` → `requestRender()`: the document is marked not rendered,
   and the image and formatted-paragraph caches are cleared.
4. **Plugin:** `G_reader_settings:saveSetting(...)`: in memory only.
5. **Plugin:** `resetCallCache()` and `resetBufferCache()` (KOReader's caches of
   crengine results and page images), `view:recalculate()`, and a full screen
   refresh.
6. **Drawing the page** → `LVDocView::checkRender()` → `Render()`. The settings
   hash differs, so styles are recomputed. With partial rerendering, only the
   displayed part is re-laid out, at drawing time.
7. **Laying out the text:** for each element, `getFont()` → `GetFont()` with
   the text's category: serif text now asks for slant type 110, which selects
   the oblique faces (6.4). The new font has a different face slant, so the
   document's font cache and the instance cache don't hand back the italic one
   (6.6).
8. The page shows serif text in oblique, without reopening. Other categories'
   text is unchanged: nothing they read changed (8).

Weight and decoration weight follow the same steps, with their own properties
and lookups.

### 7.2 Saving

Nothing is written when a setting changes. KOReader writes
`G_reader_settings` to `settings.reader.lua` when:

- a book is closed (`ReaderUI:saveSettings()`, which also writes the book's
  sidecar, now without per-book fonts);
- the device suspends (and on Android, when the app goes to the background);
- KOReader exits (the plugin flushes first, before device teardown);
- the autosave interval has passed (default 15 minutes), on a page turn.

A crash or a forced kill loses changes made since the last save.

### 7.3 Reopening a book

1. KOReader creates the reader: its own modules, then the plugins.
2. The "ReadSettings" event reaches them in that order:
   - `ReaderFont`: the book's own font settings are dropped (6.9), so the
     global main font and family fonts are given to crengine, through the
     wrapped `setFontFace()` and `setFontFamilyFontFaces()`, which also check
     slant types (6.9);
   - `ReaderFont` also applies the book's base weight; then
   - the plugin applies the 27 global values, last.
3. The first render: crengine reuses the book's cached rendering only if the
   settings hash matches; otherwise it restyles.

### 7.4 Relaunching KOReader

1. `G_reader_settings` is read from `settings.reader.lua`.
2. At the first crengine use (`CreDocument:engineInit()`), KOReader registers
   every font in its font list: crengine reads its font cache and registers
   unchanged files without opening them (6.8), then KOReader calls
   `RegularizeRegisteredFontsWeights()`, which writes the cache if anything
   changed.
3. Opening a book continues as in 7.3.

### 7.5 Changing a category's font face

- **Unclassified** (the main font): the plugin saves `cre_font` and sends
  KOReader's `SetFont` event; KOReader's (patched) `ReaderFont` applies it, and
  the wrapped `setFontFace()` checks the slant types.
- **Another category:** the plugin saves `cre_font_family_fonts`, calls
  `ReaderFont:updateFontFamilyFonts()` (which sends the 8 fonts to crengine
  through the wrapped `setFontFamilyFontFaces()`, checking slant types), then
  redraws as in 7.1.

### 7.6 Font files change

At the next start, crengine sees the changed size or date (or a missing file),
re-reads only those files, and rewrites its cache once. The plugin reads the
cache again in the new session.

## 8. Why the categories are independent

A category's setting can only change text whose style has that category,
because each attribute has exactly one reader, keyed by the text's own
category:

| Attribute | Stored in | Read at | Keyed by |
|---|---|---|---|
| Font face | KOReader's family fonts string (8 slots) or main font | `font-family` parsing (`lvstsheet.cpp`); `GetFont()` preferred family | the generic family in the text's CSS |
| Weight | `rend_font_base_weight`, `s_generic_font_family_weights` | `getFont()` (`lvrend.cpp`) | `style->font_family` |
| Slant type | `rend_font_base_italic_style`, `s_generic_font_family_italic_styles` | `GetFont()` via `LVRendGetSlantTypeForFont()` | the category passed to `GetFont()` (= `style->font_family`), also for fallback glyphs |
| Decoration weight | `rend_font_base_decoration_weight`, `s_generic_font_family_decoration_weights` | `renderFinalBlock()` | `style->font_family` of the decorated element |

And nothing shared between categories can carry a value across:

- **Font objects** differ per category and per slant type (category and face
  slant in the font identity, category and slant type in the instance key), so
  one category's font is never reused for another's text.
- **Decoration weights** are stored per text fragment, and restored when an
  element ends.
- **Unclassified** is a category like the others (6.1), so "no category" can't
  fall into sans-serif.
- **All 9 run the same code**: the category only selects which value is read.

The tests check this on rendered pages, pixel by pixel: changing each of the 27
settings changes only its own category's lines (suites 01, 02, 05, 06, 07).

## 9. Decision records

Each record: the context, the decision, and its consequences. "Owner" marks a
choice made by the project's owner.

### ADR-01: Unclassified is a category of its own (owner)
- **Context:** upstream counted text without a generic family as sans-serif,
  so sans-serif settings changed untagged text.
- **Decision:** `css_ff_unclassified` for text with no generic family: at the
  document's root (so untagged text inherits it), for a `font-family` naming
  only specific fonts, and for `initial`. A `font-family` naming only specific
  fonts doesn't keep its parent's category. A generic family is inherited as
  usual.
- **Consequences:** its attributes are the `base` settings; books cached before
  restyle once (hash bump).

### ADR-02: Settings are global, including font faces (owner)
- **Context:** KOReader can save a font per book; the owner wants the 4
  attributes of the 9 categories the same for all books.
- **Decision:** all 36 settings are global; per-book font faces are ignored and
  never saved; KOReader's own font menus set the global values.
- **Consequences:** books that had their own fonts now use the global ones.
  KOReader's other per-book settings are unchanged.

### ADR-03: Deferred writes (owner)
- **Context:** changing a setting many times shouldn't write to disk each time.
- **Decision:** settings change in memory; only KOReader's saving points write
  them (7.2).
- **Consequences:** a crash loses changes since the last save.

### ADR-04: Fonts are classified like fontconfig, without fontconfig (owner)
- **Context:** guessing from file names or a single style string mixes up
  italic and oblique; `fc-query`'s slant value is reliable; KOReader doesn't
  use fontconfig, and Android has none.
- **Decision:** reproduce fontconfig's rule in crengine (`LVFontGetFcSlant()`),
  and likewise its width and spacing measures.
- **Consequences:** identical results on Linux and Android; verified against
  `fc-query`.

### ADR-05: The slant type governs both CSS italic and oblique (owner)
- **Context:** CSS `italic` and `oblique` both mean slanted text in crengine.
- **Decision:** the category's slant type decides the kind for both.

### ADR-06: The kind is chosen per family before the weight
- **Context:** choosing by weight first gave italic regular text and oblique
  bold text in the same category (a failed earlier approach).
- **Decision:** sort the family's faces by kind, take the slant type's kind,
  then the best weight; synthesize missing weights from that kind.

### ADR-07: When the kind is missing (owner)
- **Context:** a font may lack the chosen kind.
- **Decision:** for the category's own font, the menu greys out kinds it
  lacks, and changing to such a font switches the category to `synthetic*`.
  For other installed fonts (named in a book's CSS, or fallback fonts), use the
  other kind, then synthetic.

### ADR-08: Variable fonts' axes count as kinds (owner)
- **Decision:** an `ital` axis counts as italic and a `slnt` axis as oblique;
  `synthetic*` uses neither.

### ADR-09: Embedded book fonts keep crengine's behaviour (owner)
- **Context:** books can embed their own fonts.
- **Decision:** while KOReader's "Embedded fonts" option is on, a book's
  embedded faces are tried first, as upstream did; with it off, embedded fonts
  aren't used, and the slant types govern everything.

### ADR-10: The default slant type is Italic (owner)
- **Consequences:** a category whose own font has only oblique files (eg.
  DejaVu Sans) is switched to `synthetic*` (ADR-07); other fonts with only
  oblique files, named in a book's CSS or used for fallback, use their oblique
  files for slanted text (ADR-07).

### ADR-11: synthetic* slants upright faces
- **Decision:** upright faces slanted by FreeType; a family without upright
  faces uses its slanted faces instead.

### ADR-12: The face slant and the category are part of font identity
- **Context:** the live Italic ↔ Oblique switch didn't show until reopening
  ([10](#10-pitfalls-and-failed-approaches)).
- **Decision:** add `getFaceSlant()` to font identity, as upstream did for
  synthetic weight; key font instances by category and slant type.
- **Consequences:** books cached before re-layout once.

### ADR-13: Redraw through the existing path (owner)
- **Decision:** a setting is a crengine property; the plugin redraws with
  KOReader's own sequence, as the existing weight setting did. No new redraw
  mechanism.

### ADR-14: Width and spacing grouping only on a collision (owner)
- **Context:** crengine-ng groups families by width and spacing, always adding
  words (giving eg. "Asap Condensed Condensed"), and takes the shortest family
  name.
- **Decision:** crengine-ng's words and thresholds, with these differences: a
  word only when the family mixes widths (or spacings); the base name is
  FreeType's family name, not the shortest one; width word before spacing
  word; dual spacing is "Duospace"; variable-width fonts get no width word;
  former names stay usable but hidden.
- **Consequences:** on the owner's fonts, the shortest-name rule would have
  split families by weight (eg. Recursive into 28 entries) and given some
  localized names; with FreeType's name, families split strictly by width and
  spacing. Accepted leftovers: "Antykwa Poltawskiego Light" (the font's own
  name), "Asap Condensed" (its own family).

### ADR-15: A cache of crengine's own font records (owner)
- **Context:** registering ~12,500 fonts opened every file at each start.
  Option A (LxReader's): register only the fonts in use; option B: cache what
  crengine found for every file.
- **Decision:** B: every installed font stays known (so a book's CSS can name
  any installed font), without opening files; next to `fontinfo.dat`; written
  only when fonts change; refused files remembered.
- **Consequences:** startup with ~12,500 fonts went from ~3.8 s to ~0.6 s; the
  cache has a format version to bump.

### ADR-16: The plugin, not KOReader's crengine binding (owner)
- **Context:** greying out needs crengine's classification; a new function in
  KOReader's `cre.cpp` was the other option.
- **Decision:** no KOReader file is changed; the plugin gets the
  classification from crengine's font cache.

### ADR-17: The plugin calls no C function directly
- **Context:** the plugin first classified fonts itself through FreeType and
  HarfBuzz (FFI). On Android those functions don't exist in KOReader's
  library: opening a book failed.
- **Decision:** read crengine's classification from its cache (plain file
  reading); test suite 13 forbids direct calls.

### ADR-18: Decoration thickness per category, bounded
- **Decision:** 50 % to 500 % of the font's thickness, at least 1 pixel; the
  decorated text's own category decides; several decorations can combine; a
  decoration is only joined across words of the same weight.

### ADR-19: Weight per category, bold's offset kept
- **Decision:** each category's weight replaces the single upstream setting for
  its text, with the same "CSS weight + (setting − 400)" rule; the base weight
  is now Unclassified's; KOReader's own slider is hidden.

### ADR-20: The plugin's name and place (owner)
- **Decision:** folder `advancedtypography.koplugin` (module
  `advancedtypography`), menu right after "Typography rules", Font cache then
  No document cache last.

### ADR-21: No document cache (owner)
- **Context:** crengine writes a cache file for each opened book (larger than
  KOReader's 64 KB minimum) and writes to it again when the book closes.
- **Decision:** an option in the plugin, off by default, with no crengine
  change: crengine's existing `crengine.cache.filesize.min`, set out of reach
  when a book opens; turning it on deletes the book caches and resets
  crengine's list of them. The font cache is kept.
- **Consequences:** every book is laid out at each opening (slower for large
  books), and setting changes lay out the whole book. crengine still writes
  its index, `cr3cache.inx` (about 100 bytes), at each start, and a book cache
  when it runs short of memory.

## 10. Pitfalls and failed approaches

What went wrong before, so it isn't repeated.

- **Choosing by weight, then by kind (earlier attempts).** Regular slanted text
  got italic files and bold slanted text oblique ones, in the same category.
  Matching style-name strings ("Italic", "LightOblique"...) didn't fix it.
  Fix: decide the kind for the whole family first (P7, ADR-06).
- **Italic ↔ Oblique needed a reopen.** crengine picked the right file, but
  partial rerendering kept the document's font cache, which found the old
  italic font "equal" to the new oblique one. `synthetic*` and weight changes
  worked, because those differ in the italic flag or weight. Fix: the face
  slant in font identity (P3, ADR-12).
- **Weight changes once needed a page turn (an earlier version).** The working
  version redraws with KOReader's own sequence after setting the property
  (ADR-13), and its weight is part of font identity upstream.
- **"Oblique doesn't use oblique files" (Iosevka Slab).** Its Extended (wider)
  files shared the family name, tied on weight with the normal ones, and the
  first file won. Fix: width grouping (6.7).
- **Unclassified text following sans-serif.** Upstream's default family. Fix:
  `css_ff_unclassified` (6.1), including the root style, which mustn't take the
  default font's family.
- **Patching KOReader's document class.** Bypassed: KOReader's call cache had
  already copied the methods onto the open document. Fix: wrap the open
  document's own methods (6.9).
- **The plugin named `typography`.** Replaced KOReader's Typography module,
  disabling custom hyphenation. Fix: rename the folder (ADR-20).
- **Direct FreeType/HarfBuzz calls in the plugin.** Worked on Linux, crashed on
  Android (missing functions in KOReader's single library), reported only as
  "No reader engine for this file or invalid file". Fix: ADR-17.
- **Testing the wrong path.** Partial rerendering only happens in an EPUB above
  64 KB (with a cache file), opened in the reader, after its event loop has
  run; tests that skipped this missed the font identity bug. The test suites
  now do it (`T.writeEpub()`, `fastforward_ui_events()`), with crengine's
  header (which shows a clock) off.
- **Building or starting KOReader during tests.** Reinstalls the style sheets
  the tests read; suites opening books at that moment fail.

## 11. Invariants and tests

The rules that must stay true, and the test suite (`extended/tests/`) that
checks each one.

| Invariant | Suite |
|---|---|
| Changing a category's weight or decoration weight changes only its text; changing back restores it exactly; Unclassified covers untagged, named-only and `initial` text | 01 |
| Slanted text uses exactly the face its slant type and the family's faces call for, regular and bold, for all 9 categories, each independent | 02 |
| A variable font's axes act as kinds | 03 |
| Fallback glyphs follow the text's slant type | 04 |
| A live slant type change looks exactly like a fresh open, all 9 categories (with partial rerendering) | 05 |
| The 27 settings: live change = fresh open, independence, change back, nothing written until closing, saved, reapplied identically | 06 |
| Weight and decoration weight are monotonic per category; others unchanged; nothing written | 07 |
| Greying out, switching to synthetic*, global font faces, per-book fonts never saved | 08 |
| Grouped names, hidden former names, KOReader's font menu accepting grouped names, the plugin knowing every family crengine lists | 09 |
| The plugin beside KOReader's Typography module and menu; native weight slider hidden; exit flush; PDFs unaffected | 10 |
| The font cache: same fonts with and without it, really used, rewritten only when fonts change, changes seen; its menu | 11 |
| crengine's slant classification equals `fc-query`'s | 12 |
| No direct C calls in the plugin | 13 |
| No document cache: no cache file from opening and closing books (none recreated empty), a live change = a fresh open, nothing written when turning it on, font cache kept, books cached again when off | 14 |

## 12. Porting checklist

Where this project hooks into upstream code. When porting to a newer KOReader
(README section 5), check each hook still exists and still means the same; if
upstream reworked one, re-apply the principle in its section, not just the
old lines.

| Hook | Upstream code | Section |
|---|---|---|
| New enum value, last | `css_font_family_t` (`cssdef.h`) | 6.1 |
| Text's category from `font-family`; `initial` | `LVCssDeclaration::parse()` (`lvstsheet.cpp`) | 6.1 |
| Root style's family | `ldomDocument::setRenderProps()` (`lvtinydom.cpp`) | 6.1 |
| Properties applied | `LVDocView::propsApply()` (`lvdocview.cpp`) | 6.2 |
| Settings hash | `calcGlobalSettingsHash()` (`lvtinydom.cpp`) | 6.2 |
| Weight per category | `getFont()` (`lvrend.cpp`) | 6.3 |
| Slant type and selection | `GetFont()`, `LVFontSelector::select()`, `matchFamily()`, `loadAndCache()` (`lvfntman.cpp`) | 6.4 |
| Fallback fonts' family | `getFallbackFont()`, `GetFallbackFont()` (`lvfntman.cpp`) | 6.4 |
| Decorations | `renderFinalBlock()` (`lvrend.cpp`), `LFormattedText` (`lvtextfm.h/.cpp`), `DrawTextString()` (`lvfntman.cpp`), CSS parsing (`lvstsheet.cpp`) | 6.5 |
| Font identity | `calcHash(font_ref_t)` (`lvstyles.cpp`), `operator==(LVFont)`, `LVFontInstanceKey` (`lvfntman.cpp`) | 6.6 |
| Font registry and aliases | `LVFontRegistry`, `RegisterFont()` (`lvfntman.cpp`) | 6.7 |
| Font cache | `RegisterFont()`, `RegularizeRegisteredFontsWeights()` (`lvfntman.cpp`), `ldomDocCache` (`lvtinydom.cpp`) | 6.8 |
| KOReader side | `ReaderFont`, `CreDocument:setFontFace()`, `setFontFamilyFontFaces()`, call cache, `reader_menu_order`, `Device:exit()` | 6.9 |

Upstream changes already known to conflict (README, "What to expect"): a
`docFragmentIdx` parameter added to `matchFamily()` and `select()` next to
`slant_type`; font alias storage replaced by `LVFontAlias` next to the grouping
data; a comment and parameter added to `getFont()`.
