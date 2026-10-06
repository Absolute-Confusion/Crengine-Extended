# Tests

Automated tests for the patched crengine and the Advanced Typography Settings
plugin. They check behaviour (what's drawn on the page, what's saved), so they
stay valid on newer KOReader versions: after porting the patch, they're how to
know it still works.

## Run

You need a KOReader source tree with the patch applied, built with
`./kodev build`, and the plugin installed in its `plugins/` folder.

```sh
./run_tests.sh /path/to/koreader              # all suites (about 10 seconds)
./run_tests.sh /path/to/koreader slant cache  # only suites whose name contains a word
./run_tests.sh --keep /path/to/koreader       # keep the work folder (logs, test books)
AT_FONTS_CACHE=/path/to/crengine_fonts.dat ./run_tests.sh /path/to/koreader fcquery  # suite 12 on another font cache
```

Output:

```
PASS  01_independence                 0s
...
14 passed, 0 failed, 0 skipped, in 12s
```

The exit code is 0 only if no suite failed. A failed suite shows its first
failures, and the work folder with full logs (`logs/<suite>.log`) is kept.

**Your own KOReader is never used or changed.** Each run gets a throwaway
folder for KOReader's data (settings, history, caches), and only KOReader's
bundled fonts plus the test fonts in `fonts/` are installed. It can run while
the emulator is open, but don't build or start KOReader (`./kodev build`,
`./kodev run`) during a run: that reinstalls files the tests read (such as the
default style sheets), and the suites opening books at that moment then fail.

## What the suites check

| Suite | Checks |
|---|---|
| 01_independence | Changing one category's weight or decoration weight changes only that category's text, and changing it back restores it exactly. Includes what counts as Unclassified (no generic family, named fonts only, `initial`) |
| 02_slant_selection | For all 9 categories, slanted regular and bold text uses exactly the face the slant type asks for (or the other kind, then synthetic, when missing), pixel for pixel. Also each category changed alone |
| 03_variable_font | A variable font with a slant axis and no italic: Oblique uses the axis, Italic falls back to it, synthetic* doesn't |
| 04_glyph_fallback | Characters taken from the fallback font follow their category's slant type |
| 05_live_slant_nine | Live slant type changes through the menu, in an EPUB with partial rerendering (as in the app): 33 combinations × 18 lines, each exactly as after reopening the book |
| 06_live_27_settings | All 27 settings live through the menu: shown at once, only in their category, restored when changed back; nothing written to disk until the book is closed; all saved, and reloaded identically |
| 07_live_linearity | Weight and decoration weight: a higher value never gives lighter text, in all 9 categories, other categories unchanged |
| 08_plugin_end_to_end | Greying out of unavailable slant types; global fonts (per-book ones ignored and never saved; KOReader's own font menus made global); switching to synthetic* when a font lacks the chosen kind; a second book |
| 09_family_grouping | Width/spacing words added only on a mix; former names hidden but still found; grouped names accepted by KOReader's font menu; the plugin names families as crengine does |
| 10_menu_and_modules | Coexists with KOReader's Typography module (custom hyphenation available); menu entry right after "Typography rules", Font cache then No document cache last; native weight slider hidden; exit patch; a PDF opens normally |
| 11_font_cache | Over several startups: the same fonts with or without the cache; the cache is really used; it's only rewritten when font files are added, changed or removed, and those changes are seen. The Font cache menu (size, date, count, Clear, Rebuild) |
| 12_slant_vs_fcquery | crengine's slant classification, as recorded in its font cache (which the plugin reads), agrees with `fc-query` on every test and bundled font face; with `AT_FONTS_CACHE`, on another cache, eg. one of all your system fonts (skipped without fontconfig's tools) |
| 13_plugin_portable | The plugin calls no C library function directly: KOReader's Android build doesn't provide most of them |
| 14_no_document_cache | No document cache: turning it on deletes the book caches without writing settings, and opening and closing books (one open at that moment, ones cached before) then leaves no cache file; a live change equals a fresh open; the font cache is kept; turning it off caches books again |

Each check that compares pages first checks that the things it compares
really differ (eg. Italic and Oblique look different), so a test can't pass by
comparing nothing.

## Files

| Path | What |
|---|---|
| `run_tests.sh` | Runs the suites |
| `suites/` | One file per suite |
| `lib/common.lua` | Shared helpers: test books, rendering, menu actions |
| `lib/startup.lua` | One crengine startup (used by the font cache suite) |
| `fonts/`, `fonts-extra/` | Test fonts (SIL Open Font License: see `OFL.txt`) |
| `tools/make_fonts.py` | How the test fonts were made (only needed to change them) |

The test fonts are made from Iosevka Slab, Recursive and Noto Sans, cut down to
ASCII and renamed: TestSlab (all weights 200 to 900, italic and oblique),
single-file reference fonts (Ref…), families missing slant kinds (MixFam,
OblFam, UprFam), one missing Q (NoQFam), width and spacing mixes (Grp…), and a
variable font (TestVar).

## When a test fails after porting

- Read the suite's log first: it says which category, setting and line.
- If KOReader renamed or reworked something the tests use (the reader, the
  menu, document functions), the test may need updating rather than the patch.
  Keep what it checks: only change how it gets there.
- If what a test checks has really broken, fix the port, not the test.
