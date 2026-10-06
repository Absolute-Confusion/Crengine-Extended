#!/usr/bin/env python3
"""Makes the test fonts in ../fonts and ../fonts-extra (already made: only needed to change them).

Needs fontTools (pip install fonttools) and the source fonts, all under the SIL Open Font
License 1.1 (see ../fonts/OFL.txt):
  - Iosevka Slab 34.8.0 TTF  (https://github.com/be5invis/Iosevka/releases, PkgTTF-IosevkaSlab)
  - Recursive 1.085           (https://github.com/arrowtype/recursive/releases, Recursive_VF_1.085.ttf)
  - Noto Sans Regular         (bundled with KOReader: resources/fonts/noto/NotoSans-Regular.ttf)

Usage: make_fonts.py IOSEVKA_SLAB_DIR RECURSIVE_VF_TTF NOTO_SANS_REGULAR_TTF

Every font is cut down to ASCII and renamed, so it can't be mistaken for the original.
"""
import os
import sys

from fontTools import subset
from fontTools.ttLib import TTFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "fonts")
OUT_EXTRA = os.path.join(HERE, "..", "fonts-extra")
ASCII = list(range(0x20, 0x7F))


def cut(font, unicodes):
    opts = subset.Options()
    opts.name_IDs = ["*"]
    opts.name_languages = ["*"]
    opts.notdef_outline = True
    opts.hinting = False  # rendering is compared between test fonts, never with the originals
    sub = subset.Subsetter(opts)
    sub.populate(unicodes=unicodes)
    sub.subset(font)


def rename(font, family, style, italic, bold, width_class=None):
    name = font["name"]
    name.names = [r for r in name.names if r.nameID not in (1, 2, 3, 4, 6, 16, 17, 21, 22, 25)]
    psname = family.replace(" ", "") + "-" + style.replace(" ", "")
    for nid, s in ((1, family), (2, style), (3, psname), (4, family + " " + style), (6, psname)):
        name.setName(s, nid, 3, 1, 0x409)
        name.setName(s, nid, 1, 0, 0)
    head, os2 = font["head"], font["OS/2"]
    head.macStyle = (head.macStyle & ~3) | (2 if italic else 0) | (1 if bold else 0)
    sel = os2.fsSelection & ~(1 | 0x20 | 0x40 | 0x200)
    if italic:
        sel |= 1
    if bold:
        sel |= 0x20
    if not italic and not bold:
        sel |= 0x40
    os2.fsSelection = sel
    if width_class is not None:
        os2.usWidthClass = width_class


def make(src, out, family, style, italic, bold, width_class=None, unicodes=ASCII):
    font = TTFont(src)
    cut(font, unicodes)
    rename(font, family, style, italic, bold, width_class)
    font.save(out)


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    slab, recursive, noto = sys.argv[1:]
    S = lambda st: os.path.join(slab, "IosevkaSlab-" + st + ".ttf")
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(OUT_EXTRA, exist_ok=True)
    o = lambda f: os.path.join(OUT, f)

    # TestSlab: a full family, with both slant kinds (italic and oblique), in every weight from
    # 200 to 900 (so weight settings use real faces, not synthetic weights)
    for w in ("ExtraLight", "Light", "", "Medium", "SemiBold", "Bold", "ExtraBold", "Heavy"):
        for sl in ("", "Italic", "Oblique"):
            st = " ".join(s for s in (w, sl) if s) or "Regular"
            src = (w + sl) or "Regular"
            make(S(src), o("TestSlab-" + src + ".ttf"), "TestSlab", st, sl != "", w == "Bold")
    # References: each one a single upright file, so upright text in it shows exactly that file's glyphs
    for st in ("Regular", "Italic", "Oblique", "Bold", "BoldItalic", "BoldOblique"):
        bold = st.startswith("Bold")
        make(S(st), o("Ref" + st + ".ttf"), "Ref" + st, "Bold" if bold else "Regular", False, bold)
    # MixFam: regular upright, regular italic and bold oblique only
    make(S("Regular"), o("MixFam-Regular.ttf"), "MixFam", "Regular", False, False)
    make(S("Italic"), o("MixFam-Italic.ttf"), "MixFam", "Italic", True, False)
    make(S("BoldOblique"), o("MixFam-BoldOblique.ttf"), "MixFam", "Bold Oblique", True, True)
    # OblFam: oblique only (like DejaVu Sans)
    make(S("Regular"), o("OblFam-Regular.ttf"), "OblFam", "Regular", False, False)
    make(S("Oblique"), o("OblFam-Oblique.ttf"), "OblFam", "Oblique", True, False)
    # UprFam: no slanted file at all
    make(S("Regular"), o("UprFam-Regular.ttf"), "UprFam", "Regular", False, False)
    make(S("Bold"), o("UprFam-Bold.ttf"), "UprFam", "Bold", False, True)
    # NoQFam: no Q and q, for glyph fallback
    make(S("Regular"), o("NoQFam-Regular.ttf"), "NoQFam", "Regular", False, False,
         unicodes=[c for c in ASCII if c not in (ord("Q"), ord("q"))])
    # Width and spacing grouping
    make(S("Regular"), o("GrpWide-Regular.ttf"), "GrpWide", "Regular", False, False, 5)
    make(S("Extended"), o("GrpWide-Extended.ttf"), "GrpWide", "Extended", False, False, 7)
    make(S("Regular"), o("GrpCond-Regular.ttf"), "GrpCond", "Regular", False, False, 5)
    make(S("Regular"), o("GrpCond-Condensed.ttf"), "GrpCond", "Condensed", False, False, 4)
    make(S("Regular"), o("GrpSpace-Mono.ttf"), "GrpSpace", "Regular", False, False)
    make(noto, o("GrpSpace-Prop.ttf"), "GrpSpace", "Regular", False, False)
    # TestVar: variable font with a slnt axis and no italic
    make(recursive, o("TestVar-VF.ttf"), "TestVar", "Regular", False, False)
    # Not installed by default: the font cache test adds and removes it
    make(S("Regular"), os.path.join(OUT_EXTRA, "CacheTest-Regular.ttf"), "CacheTestFamily", "Regular", False, False)


if __name__ == "__main__":
    main()
