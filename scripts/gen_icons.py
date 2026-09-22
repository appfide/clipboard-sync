#!/usr/bin/env python3
"""Generates every app icon from one vector source.

The mark is a clipboard with a sync loop cut out of it, so the same silhouette
works filled (launcher icons) and as an alpha mask (macOS menu-bar template).

Writes the SVG sources to design/icon/ and renders them into the platform
locations under apps/nija/. Rendering needs rsvg-convert and
ImageMagick (`brew install librsvg imagemagick`); the rendered files are
committed, so this only has to run when the artwork changes.

    scripts/gen_icons.py [--check]

--check renders to a temporary directory and fails if anything differs from
what is committed.
"""

from __future__ import annotations

import argparse
import filecmp
import math
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
APP = REPO / "apps" / "nija"
DESIGN = REPO / "design" / "icon"

# apps/nija/lib/ui/app_theme.dart
BLUE_500 = "#3B82F6"
BLUE_700 = "#1D4ED8"
TRAY_BLUE = "#3B82F6"

# The glyph is drawn in a 512x512 box and is centred on (256, 256).
GLYPH_W, GLYPH_H = 304.0, 400.0


def _arrowhead(cx: float, cy: float, r: float, angle: float, half: float, length: float) -> str:
    """Triangle sitting at `angle` on the loop, pointing along the tangent."""
    rad = math.radians(angle)
    radial = (math.cos(rad), math.sin(rad))
    tangent = (-math.sin(rad), math.cos(rad))
    tip = (cx + r * radial[0] + length * tangent[0], cy + r * radial[1] + length * tangent[1])
    inner = (cx + (r - half) * radial[0], cy + (r - half) * radial[1])
    outer = (cx + (r + half) * radial[0], cy + (r + half) * radial[1])
    pts = " ".join(f"{x:.1f},{y:.1f}" for x, y in (tip, outer, inner))
    return f'<polygon points="{pts}"/>'


def glyph(fill: str) -> str:
    """Clipboard with the sync loop knocked out, as a masked <rect>."""
    cx, cy, r, stroke = 256.0, 300.0, 78.0, 34.0
    half = stroke / 2 + 13  # arrowheads overhang the stroke on both sides

    def point(angle: float) -> tuple[float, float]:
        rad = math.radians(angle)
        return cx + r * math.cos(rad), cy + r * math.sin(rad)

    top_start, top_end = point(200), point(340)
    bottom_start, bottom_end = point(20), point(160)
    arcs = (
        f'<path d="M {top_start[0]:.1f} {top_start[1]:.1f} '
        f'A {r} {r} 0 0 1 {top_end[0]:.1f} {top_end[1]:.1f}"/>'
        f'<path d="M {bottom_start[0]:.1f} {bottom_start[1]:.1f} '
        f'A {r} {r} 0 0 1 {bottom_end[0]:.1f} {bottom_end[1]:.1f}"/>'
    )
    head = _arrowhead(cx, cy, r, 340, half, 54)

    return f"""  <defs>
    <mask id="glyph-mask" maskUnits="userSpaceOnUse" x="0" y="0" width="512" height="512">
      <rect x="104" y="104" width="304" height="352" rx="46" fill="#fff"/>
      <rect x="180" y="40" width="152" height="112" rx="42" fill="#000"/>
      <rect x="198" y="58" width="116" height="78" rx="26" fill="#fff"/>
      <g fill="none" stroke="#000" stroke-width="{stroke}" stroke-linecap="butt">{arcs}</g>
      <g fill="#000">{head}{head.replace('<polygon', f'<polygon transform="rotate(180 {cx} {cy})"')}</g>
    </mask>
  </defs>
  <rect x="0" y="0" width="512" height="512" fill="{fill}" mask="url(#glyph-mask)"/>"""


def _scaled_glyph(canvas: float, height: float, fill: str, dy: float = 0.0) -> str:
    """The glyph scaled to `height` px and centred on a `canvas`-sized square."""
    k = height / GLYPH_H
    c = canvas / 2
    return (
        f'  <g transform="translate({c:.1f} {c + dy:.1f}) scale({k:.4f}) translate(-256 -256)">\n'
        f"  {glyph(fill)}\n"
        "  </g>"
    )


def svg_full_bleed(radius: float) -> str:
    """Launcher icon: blue tile filling the canvas, white mark on top."""
    corner = f'rx="{radius}"' if radius else ""
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0.35" y2="1">
      <stop offset="0" stop-color="{BLUE_500}"/>
      <stop offset="1" stop-color="{BLUE_700}"/>
    </linearGradient>
  </defs>
  <rect x="0" y="0" width="1024" height="1024" {corner} fill="url(#bg)"/>
{_scaled_glyph(1024, 596, "#FFFFFF")}
</svg>
"""


def svg_macos() -> str:
    """macOS wants the art inset in the canvas with a transparent margin."""
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0.35" y2="1">
      <stop offset="0" stop-color="{BLUE_500}"/>
      <stop offset="1" stop-color="{BLUE_700}"/>
    </linearGradient>
  </defs>
  <rect x="100" y="100" width="824" height="824" rx="185" fill="url(#bg)"/>
{_scaled_glyph(1024, 480, "#FFFFFF")}
</svg>
"""


def svg_adaptive_foreground() -> str:
    """Android adaptive foreground: mark only, inside the 72/108dp safe zone."""
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 432 432" width="432" height="432">
{_scaled_glyph(432, 250, "#FFFFFF")}
</svg>
"""


def svg_monochrome() -> str:
    """Android 13 themed icon: the system tints this, only alpha matters."""
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 432 432" width="432" height="432">
{_scaled_glyph(432, 250, "#000000")}
</svg>
"""


def svg_tray() -> str:
    """Tray mark: no tile, so it sits on the menu bar / taskbar background."""
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
{_scaled_glyph(512, 470, TRAY_BLUE)}
</svg>
"""


SOURCES = {
    "icon.svg": lambda: svg_full_bleed(224),
    "icon-square.svg": lambda: svg_full_bleed(0),
    "icon-macos.svg": svg_macos,
    "icon-adaptive-foreground.svg": svg_adaptive_foreground,
    "icon-monochrome.svg": svg_monochrome,
    "tray.svg": svg_tray,
}

ANDROID_DENSITIES = {  # legacy launcher px, adaptive foreground px
    "mdpi": (48, 108),
    "hdpi": (72, 162),
    "xhdpi": (96, 216),
    "xxhdpi": (144, 324),
    "xxxhdpi": (192, 432),
}

IOS_ICONS = [  # (filename, px)
    ("Icon-App-20x20@1x.png", 20),
    ("Icon-App-20x20@2x.png", 40),
    ("Icon-App-20x20@3x.png", 60),
    ("Icon-App-29x29@1x.png", 29),
    ("Icon-App-29x29@2x.png", 58),
    ("Icon-App-29x29@3x.png", 87),
    ("Icon-App-40x40@1x.png", 40),
    ("Icon-App-40x40@2x.png", 80),
    ("Icon-App-40x40@3x.png", 120),
    ("Icon-App-60x60@2x.png", 120),
    ("Icon-App-60x60@3x.png", 180),
    ("Icon-App-76x76@1x.png", 76),
    ("Icon-App-76x76@2x.png", 152),
    ("Icon-App-83.5x83.5@2x.png", 167),
    ("Icon-App-1024x1024@1x.png", 1024),
]

MACOS_ICONS = [16, 32, 64, 128, 256, 512, 1024]
WINDOWS_ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]

ADAPTIVE_XML = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>
</adaptive-icon>
"""

# Matches the gradient the other platforms render into their tile.
BACKGROUND_XML = f"""<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <gradient
        android:type="linear"
        android:angle="270"
        android:startColor="{BLUE_500}"
        android:endColor="{BLUE_700}"/>
</shape>
"""


def require(tool: str) -> str:
    path = shutil.which(tool)
    if not path:
        sys.exit(f"{tool} not found. Install it: brew install librsvg imagemagick")
    return path


def render(svg: Path, png: Path, size: int, *, opaque: bool = False) -> None:
    png.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["rsvg-convert", "-w", str(size), "-h", str(size), "-o", str(png), str(svg)],
        check=True,
    )
    args = ["-strip"]
    if opaque:
        # iOS rejects an alpha channel, so flatten onto the tile's own colour.
        args = ["-background", BLUE_700, "-alpha", "remove", "-alpha", "off", "-strip"]
    subprocess.run(["magick", str(png), *args, str(png)], check=True)


def _bmp_frame(png: Path, tmp: Path) -> bytes:
    """The BMP payload ImageMagick writes for a single-frame .ico."""
    single = tmp / f"{png.stem}-frame.ico"
    subprocess.run(["magick", str(png), "-strip", str(single)], check=True)
    blob = single.read_bytes()
    size, offset = struct.unpack_from("<II", blob, 6 + 8)
    return blob[offset : offset + size]


def build_ico(svg: Path, ico: Path, sizes: list[int], tmp: Path) -> None:
    """Multi-resolution .ico, laid out the way Windows itself ships icons.

    Frames up to 64px are BMP, which every icon reader understands; 128 and
    256 are PNG-compressed, which Windows reads since Vista. Letting
    ImageMagick write the whole container instead costs 256 KB for the 256px
    frame alone, because it stores every frame as an uncompressed BMP.
    """
    frames = []
    for size in sizes:
        frame = tmp / f"{ico.stem}-{size}.png"
        render(svg, frame, size)
        if size >= 128:
            frames.append((size, frame.read_bytes()))
        else:
            frames.append((size, _bmp_frame(frame, tmp)))

    offset = 6 + 16 * len(frames)
    directory, payload = b"", b""
    for size, data in frames:
        directory += struct.pack(
            "<BBBBHHII", size % 256, size % 256, 0, 0, 1, 32, len(data), offset
        )
        payload += data
        offset += len(data)

    ico.parent.mkdir(parents=True, exist_ok=True)
    ico.write_bytes(struct.pack("<HHH", 0, 1, len(frames)) + directory + payload)


def generate(app: Path, design: Path, docs: Path | None = None) -> None:
    design.mkdir(parents=True, exist_ok=True)
    for name, source in SOURCES.items():
        (design / name).write_text(source())

    icon = design / "icon.svg"
    square = design / "icon-square.svg"
    macos = design / "icon-macos.svg"
    foreground = design / "icon-adaptive-foreground.svg"
    monochrome = design / "icon-monochrome.svg"
    tray = design / "tray.svg"

    with tempfile.TemporaryDirectory() as raw:
        tmp = Path(raw)

        # Bundled assets: the Linux .deb/AppImage icon and the tray mark.
        render(icon, app / "assets/icons/app.png", 512)
        render(tray, app / "assets/icons/tray.png", 44)
        build_ico(tray, app / "assets/icons/tray.ico", [16, 24, 32, 48, 64], tmp)

        # Android: legacy square, adaptive foreground, themed monochrome.
        res = app / "android/app/src/main/res"
        for density, (legacy, adaptive) in ANDROID_DENSITIES.items():
            render(icon, res / f"mipmap-{density}/ic_launcher.png", legacy)
            render(foreground, res / f"mipmap-{density}/ic_launcher_foreground.png", adaptive)
            render(monochrome, res / f"mipmap-{density}/ic_launcher_monochrome.png", adaptive)
        (res / "mipmap-anydpi-v26").mkdir(parents=True, exist_ok=True)
        (res / "mipmap-anydpi-v26/ic_launcher.xml").write_text(ADAPTIVE_XML)
        (res / "drawable/ic_launcher_background.xml").write_text(BACKGROUND_XML)

        # iOS: square and opaque, the system applies its own mask.
        ios = app / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
        for name, size in IOS_ICONS:
            render(square, ios / name, size, opaque=True)

        # macOS: inset art, transparent margin.
        mac = app / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
        for size in MACOS_ICONS:
            render(macos, mac / f"app_icon_{size}.png", size)

        # Windows: multi-resolution .ico for the exe and the installer.
        build_ico(icon, app / "windows/runner/resources/app_icon.ico", WINDOWS_ICO_SIZES, tmp)

        # The mark the README shows.
        if docs is not None:
            render(icon, docs / "icon.png", 128)


def check(app: Path) -> int:
    """Regenerate into a scratch copy and diff against what is committed."""
    with tempfile.TemporaryDirectory() as raw:
        scratch = Path(raw)
        shadow = scratch / "apps" / "nija"
        for sub in ("assets/icons", "android", "ios", "macos", "windows"):
            shutil.copytree(app / sub, shadow / sub, dirs_exist_ok=True)
        generate(shadow, scratch / "design" / "icon", scratch / "docs")

        stale = []
        for path in sorted(shadow.rglob("*")):
            if not path.is_file():
                continue
            committed = app / path.relative_to(shadow)
            if not committed.exists() or not filecmp.cmp(path, committed, shallow=False):
                stale.append(str(committed.relative_to(REPO)))
        for name in SOURCES:
            source = DESIGN / name
            generated = scratch / "design" / "icon" / name
            if not source.exists() or source.read_text() != generated.read_text():
                stale.append(str(source.relative_to(REPO)))

        logo = REPO / "docs" / "icon.png"
        if not logo.exists() or not filecmp.cmp(scratch / "docs/icon.png", logo, shallow=False):
            stale.append(str(logo.relative_to(REPO)))

    if stale:
        print("icons are out of date, run scripts/gen_icons.py:", file=sys.stderr)
        for name in stale:
            print(f"  {name}", file=sys.stderr)
        return 1
    print("icons are up to date")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify the committed icons match")
    args = parser.parse_args()

    require("rsvg-convert")
    require("magick")

    if args.check:
        return check(APP)

    generate(APP, DESIGN, REPO / "docs")
    print(f"icons written to {APP.relative_to(REPO)}, {DESIGN.relative_to(REPO)} and docs/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
