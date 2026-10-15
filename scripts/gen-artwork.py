#!/usr/bin/env python3
"""Mamuthka linux grafikák: sötét pingvines háttérkép és boot-logó.

Használat: gen-artwork.py <rootfs> <képernyő-szélesség> <képernyő-magasság>
Függőség: python3-pil (Pillow), fonts-dejavu-core
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

TITLE = "Mamuthka linux"
FONT_PATHS = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf",
]


def font(size):
    for p in FONT_PATHS:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def penguin(d, cx, cy, s):
    """Egyszerű Tux-szerű pingvin; s = magasság pixelben."""
    w = s * 0.72
    orange = (247, 168, 30)
    # lábak
    for dx in (-0.2, 0.2):
        d.ellipse([cx + dx * w - w * 0.2, cy + s * 0.40, cx + dx * w + w * 0.2, cy + s * 0.52], fill=orange)
    # test
    d.ellipse([cx - w / 2, cy - s * 0.25, cx + w / 2, cy + s * 0.48], fill=(18, 18, 22))
    # has
    d.ellipse([cx - w * 0.34, cy - s * 0.05, cx + w * 0.34, cy + s * 0.45], fill=(238, 238, 238))
    # fej
    d.ellipse([cx - w * 0.33, cy - s * 0.50, cx + w * 0.33, cy - s * 0.04], fill=(18, 18, 22))
    # szemek
    for dx in (-0.12, 0.12):
        ex, ey = cx + dx * w, cy - s * 0.30
        d.ellipse([ex - w * 0.08, ey - s * 0.07, ex + w * 0.08, ey + s * 0.07], fill=(255, 255, 255))
        d.ellipse([ex - w * 0.035, ey - s * 0.02, ex + w * 0.035, ey + s * 0.05], fill=(10, 10, 10))
    # csőr
    d.polygon([(cx - w * 0.12, cy - s * 0.17), (cx + w * 0.12, cy - s * 0.17), (cx, cy - s * 0.07)], fill=orange)


def wallpaper(w, h):
    img = Image.new("RGB", (w, h), (8, 10, 16))
    # finom kék fény a pingvin mögött
    glow = Image.new("L", (w, h), 0)
    gd = ImageDraw.Draw(glow)
    r = min(w, h) * 0.45
    gd.ellipse([w / 2 - r, h * 0.42 - r, w / 2 + r, h * 0.42 + r], fill=90)
    glow = glow.filter(ImageFilter.GaussianBlur(min(w, h) * 0.15))
    img = Image.composite(Image.new("RGB", (w, h), (30, 60, 120)), img, glow)
    d = ImageDraw.Draw(img)
    s = min(w, h) * 0.45
    penguin(d, w / 2, h * 0.42, s)
    f = font(int(min(w, h) * 0.07))
    tw = d.textlength(TITLE, font=f)
    d.text(((w - tw) / 2, h * 0.42 + s * 0.62), TITLE, font=f, fill=(200, 210, 230))
    return img


def logo(size):
    img = Image.new("RGBA", (size, int(size * 1.3)), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    penguin(d, size / 2, size * 0.5, size * 0.85)
    f = font(int(size * 0.12))
    tw = d.textlength(TITLE, font=f)
    d.text(((size - tw) / 2, size * 1.05), TITLE, font=f, fill=(220, 220, 230, 255))
    return img


def dot(size):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(img).ellipse([0, 0, size - 1, size - 1], fill=(200, 210, 230, 255))
    return img


def main():
    root, w, h = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    bg = os.path.join(root, "usr/share/backgrounds/mamuthka")
    ply = os.path.join(root, "usr/share/plymouth/themes/mamuthka")
    icons = os.path.join(root, "usr/share/icons/hicolor/256x256/apps")
    for p in (bg, ply, icons):
        os.makedirs(p, exist_ok=True)
    wallpaper(w, h).save(os.path.join(bg, "wallpaper.png"))
    # fekvő változat külső monitorhoz
    wallpaper(h, w).save(os.path.join(bg, "wallpaper-landscape.png"))
    logo(min(w, h) // 2).save(os.path.join(ply, "logo.png"))
    dot(max(8, min(w, h) // 60)).save(os.path.join(ply, "dot.png"))
    logo(256).save(os.path.join(icons, "mamuthka-logo.png"))


if __name__ == "__main__":
    main()
