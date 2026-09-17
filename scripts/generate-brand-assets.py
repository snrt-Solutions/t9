#!/usr/bin/env python3
"""Generate AeSMS.io mark / favicon / app-icon PNGs from the CI board."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
PRIMARY = (0x0B, 0x0B, 0x0B, 255)
ACCENT = (0x00, 0x66, 0xFF, 255)
WHITE = (255, 255, 255, 255)
TRANSPARENT = (0, 0, 0, 0)


def _thick_line(draw: ImageDraw.ImageDraw, a, b, width: int, fill) -> None:
    """Axis-aligned-ish thick segment via short perpendicular offsets."""
    x0, y0 = a
    x1, y1 = b
    dx, dy = x1 - x0, y1 - y0
    length = (dx * dx + dy * dy) ** 0.5 or 1.0
    nx, ny = -dy / length, dx / length
    half = width / 2.0
    draw.polygon(
        [
            (x0 + nx * half, y0 + ny * half),
            (x1 + nx * half, y1 + ny * half),
            (x1 - nx * half, y1 - ny * half),
            (x0 - nx * half, y0 - ny * half),
        ],
        fill=fill,
    )


def draw_mark(
    size: int,
    *,
    brackets: tuple[int, int, int, int],
    slash: tuple[int, int, int, int],
    bg: tuple[int, int, int, int] | None,
) -> Image.Image:
    """Draw the [/] mark — square brackets with a diagonal accent slash."""
    img = Image.new("RGBA", (size, size), bg if bg is not None else TRANSPARENT)
    draw = ImageDraw.Draw(img)

    stroke = max(3, int(size * 0.09))
    pad = int(size * 0.17)
    top, bottom = pad, size - pad
    left, right = pad, size - pad
    arm = int(size * 0.18)

    # Left [
    _thick_line(draw, (left + arm, top), (left, top), stroke, brackets)
    _thick_line(draw, (left, top), (left, bottom), stroke, brackets)
    _thick_line(draw, (left, bottom), (left + arm, bottom), stroke, brackets)
    # Right ]
    _thick_line(draw, (right - arm, top), (right, top), stroke, brackets)
    _thick_line(draw, (right, top), (right, bottom), stroke, brackets)
    _thick_line(draw, (right, bottom), (right - arm, bottom), stroke, brackets)

    # Forward slash /  (bottom-left → top-right), clearly diagonal
    slash_w = max(3, int(size * 0.10))
    inset = int(size * 0.30)
    _thick_line(
        draw,
        (left + inset, bottom - int(size * 0.06)),
        (right - inset, top + int(size * 0.06)),
        slash_w,
        slash,
    )
    return img


def app_icon(size: int, *, dark: bool) -> Image.Image:
    bg = PRIMARY if dark else WHITE
    brackets = WHITE if dark else PRIMARY
    base = Image.new("RGBA", (size, size), bg)
    mark = draw_mark(size, brackets=brackets, slash=ACCENT, bg=None)
    base.alpha_composite(mark)
    return base


def save(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "PNG")
    print(f"wrote {path.relative_to(ROOT)} ({img.size[0]}x{img.size[1]})")


def main() -> None:
    mark_1024 = draw_mark(1024, brackets=PRIMARY, slash=ACCENT, bg=None)
    save(mark_1024, ROOT / "brand" / "aesms-mark.png")
    save(mark_1024.copy(), ROOT / "brand" / "github-avatar.png")
    save(mark_1024.resize((512, 512), Image.Resampling.LANCZOS), ROOT / "web" / "img" / "aesms-512.png")
    save(mark_1024.resize((512, 512), Image.Resampling.LANCZOS), ROOT / "web" / "img" / "aesms-mark.png")

    for n, name in ((16, "favicon-16.png"), (32, "favicon-32.png"), (48, "favicon.png")):
        save(app_icon(n, dark=True), ROOT / "web" / "img" / name)

    dark_1024 = app_icon(1024, dark=True)
    save(dark_1024, ROOT / "web" / "img" / "apple-touch-icon.png")
    save(dark_1024, ROOT / "ios" / "AeSMS" / "Resources" / "Brand" / "AppIcon-1024.png")
    save(mark_1024, ROOT / "ios" / "AeSMS" / "Resources" / "Brand" / "aesms-mark.png")
    save(dark_1024, ROOT / "brand" / "app-icon-dark.png")
    save(app_icon(1024, dark=False), ROOT / "brand" / "app-icon-light.png")

    # Adaptive icon foreground: white brackets + accent slash on transparent
    fg = draw_mark(432, brackets=WHITE, slash=ACCENT, bg=None)
    save(fg, ROOT / "android" / "app" / "src" / "main" / "res" / "drawable" / "ic_launcher_foreground.png")


if __name__ == "__main__":
    main()
