"""Subset MiSans static weights into app-bundled fonts.

Charset: full GB2312 (6763 hanzi + symbols) + printable ASCII + common
Western/CJK punctuation + fullwidth forms. Missing rare glyphs fall back to
the platform system font at runtime, so this keeps coverage for normal
Chinese content while shrinking ~7.9 MB per weight to ~2-3 MB.

Layout features are kept in full (--layout-features='*') so the tabular
figures feature (tnum) used by timers/money keeps working.

Usage: python scripts/subset_misans.py <dir-with-MiSans-TTFs> <out-dir>
"""
import sys
from pathlib import Path

from fontTools import subset

WEIGHTS = ["Regular", "Medium", "Semibold", "Bold"]


def build_charset() -> str:
    chars = set()
    # ASCII printable
    chars.update(chr(c) for c in range(0x20, 0x7F))
    # Full GB2312: rows A1-F7, cells A1-FE
    for row in range(0xA1, 0xF8):
        for cell in range(0xA1, 0xFF):
            try:
                chars.add(bytes([row, cell]).decode("gb2312"))
            except UnicodeDecodeError:
                pass
    # Western punctuation / symbols commonly seen in notes
    chars.update("–—‘’“”…·×÷°±†‡•‰′″€£¥¢©®™§¶")
    # CJK punctuation and fullwidth forms
    for c in range(0x3000, 0x3040):
        chars.add(chr(c))
    for c in range(0xFF01, 0xFF5F):
        chars.add(chr(c))
    for c in range(0xFFE0, 0xFFE7):
        chars.add(chr(c))
    # General CJK extras outside GB2312 that this app renders as fixed copy
    chars.update("桌面学习专注计划生活回顾总结备忘录饮食消费健身番茄钟")
    return "".join(sorted(chars))


def main() -> None:
    src_dir, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)
    text = build_charset()
    text_file = out_dir / "_charset.txt"
    text_file.write_text(text, encoding="utf-8")
    print(f"charset: {len(text)} chars -> {text_file}")

    for weight in WEIGHTS:
        src = src_dir / f"MiSans-{weight}.ttf"
        out = out_dir / f"MiSans-{weight}-subset.ttf"
        args = [
            str(src),
            f"--text-file={text_file}",
            "--layout-features=*",
            "--name-IDs=*",
            "--glyph-names",
            "--recalc-bounds",
            "--recalc-average-width",
            f"--output-file={out}",
        ]
        subset.main(args)
        print(f"{out.name}: {out.stat().st_size / 1e6:.2f} MB")


if __name__ == "__main__":
    main()
