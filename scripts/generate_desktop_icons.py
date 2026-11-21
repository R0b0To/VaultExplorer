#!/usr/bin/env python3
"""Generates the desktop (Windows + Linux) app icons from assets/images/app_icon.png.

    python3 scripts/generate_desktop_icons.py          (needs Pillow: pip install pillow)

The source PNG is the Android adaptive-icon foreground, so the artwork only fills about two thirds of the
canvas (the rest is the launcher's safe zone). On a desktop taskbar that looks undersized, so the artwork is
cropped to its visible bounds and centred on a square canvas with a small margin before every size is made.

Outputs (all committed, so CI does not need to run this):
  windows/runner/resources/app_icon.ico                          multi-size icon embedded in vaultexplorer.exe
  linux/runner/app_icon.png                                      window icon, installed to <bundle>/data/app_icon.png
  packaging/linux/icons/hicolor/<N>x<N>/apps/<app-id>.png        icon theme entries used by the .deb / .desktop file
"""
import io
import struct
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets" / "images" / "app_icon.png"
APP_ID = "com.aeidolon.vaultexplorer"  # must match APPLICATION_ID in linux/CMakeLists.txt

MARGIN = 0.05  # empty border on each side, as a fraction of the square canvas
ICO_SIZES = [16, 20, 24, 32, 40, 48, 64, 128, 256]
HICOLOR_SIZES = [16, 24, 32, 48, 64, 128, 256, 512]
LINUX_WINDOW_ICON_SIZE = 512


def load_square_artwork() -> Image.Image:
    """The source artwork cropped to its visible pixels, centred on a transparent square with a margin."""
    img = Image.open(SOURCE).convert("RGBA")
    bounds = img.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    if bounds is None:
        sys.exit(f"{SOURCE} is fully transparent")
    art = img.crop(bounds)
    side = round(max(art.size) / (1 - 2 * MARGIN))
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.alpha_composite(art, ((side - art.width) // 2, (side - art.height) // 2))
    return canvas


def resized(art: Image.Image, size: int) -> Image.Image:
    return art.resize((size, size), Image.Resampling.LANCZOS)


def png_bytes(img: Image.Image) -> bytes:
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def write_ico(art: Image.Image, path: Path) -> None:
    """Writes an .ico with one PNG-compressed frame per size (each resized from the full-size artwork,
    which Pillow's own ICO writer would not do). PNG frames are supported by Windows Vista and later and by
    the resource compiler in every current Windows SDK."""
    frames = [(size, png_bytes(resized(art, size))) for size in ICO_SIZES]
    header = struct.pack("<HHH", 0, 1, len(frames))  # reserved, type = icon, image count
    offset = len(header) + 16 * len(frames)
    entries, blobs = b"", b""
    for size, data in frames:
        dim = 0 if size >= 256 else size  # 0 means 256 in the directory entry
        entries += struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(data), offset)
        blobs += data
        offset += len(data)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(header + entries + blobs)


def write_png(art: Image.Image, size: int, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png_bytes(resized(art, size)))


def main() -> None:
    art = load_square_artwork()
    write_ico(art, ROOT / "windows" / "runner" / "resources" / "app_icon.ico")
    write_png(art, LINUX_WINDOW_ICON_SIZE, ROOT / "linux" / "runner" / "app_icon.png")
    for size in HICOLOR_SIZES:
        write_png(art, size, ROOT / "packaging" / "linux" / "icons" / "hicolor" / f"{size}x{size}" / "apps" / f"{APP_ID}.png")
    print(f"icons generated from {SOURCE.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
