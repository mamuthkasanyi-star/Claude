#!/usr/bin/env python3
"""Mamuthka linux grafikák: háttérkép és boot-logó.

A forrásképek az assets/ mappában vannak (wallpaper-portrait.jpg,
wallpaper-landscape.jpg). A boot-logó a mamutos rész kivágása az álló képből.

Használat: gen-artwork.py <rootfs> <képernyő-szélesség> <képernyő-magasság>
Függőség: python3-pil (Pillow)
"""
import os
import sys

from PIL import Image, ImageDraw

ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")


def fit_black(img, w, h):
    """Arányosan a képernyőre méretez, a maradékot feketével tölti ki."""
    scale = min(w / img.width, h / img.height)
    img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    out = Image.new("RGB", (w, h), (0, 0, 0))
    out.paste(img, ((w - img.width) // 2, (h - img.height) // 2))
    return out


def logo(portrait, width):
    """A mamut + MAMUTHKA LINUX felirat kivágása (az álló kép 21–61%-a)."""
    w, h = portrait.size
    box = (0, int(h * 0.21), w, int(h * 0.61))
    crop = portrait.crop(box)
    scale = width / crop.width
    return crop.resize((width, round(crop.height * scale)), Image.LANCZOS)


def dot(size):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(img).ellipse([0, 0, size - 1, size - 1], fill=(230, 40, 40, 255))
    return img


def main():
    root, w, h = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    bg = os.path.join(root, "usr/share/backgrounds/mamuthka")
    ply = os.path.join(root, "usr/share/plymouth/themes/mamuthka")
    icons = os.path.join(root, "usr/share/icons/hicolor/256x256/apps")
    for p in (bg, ply, icons):
        os.makedirs(p, exist_ok=True)

    portrait = Image.open(os.path.join(ASSETS, "wallpaper-portrait.jpg")).convert("RGB")
    landscape = Image.open(os.path.join(ASSETS, "wallpaper-landscape.jpg")).convert("RGB")

    fit_black(portrait, w, h).save(os.path.join(bg, "wallpaper.png"))
    fit_black(landscape, max(w, h), min(w, h)).save(os.path.join(bg, "wallpaper-landscape.png"))
    logo(portrait, min(w, h) * 3 // 4).save(os.path.join(ply, "logo.png"))
    dot(max(8, min(w, h) // 60)).save(os.path.join(ply, "dot.png"))

    # Kis ikon: a mamutfej négyzetes kivágása
    pw, ph = portrait.size
    side = int(pw * 0.62)
    icon = portrait.crop(((pw - side) // 2, int(ph * 0.20), (pw + side) // 2, int(ph * 0.20) + side))
    icon.resize((256, 256), Image.LANCZOS).save(os.path.join(icons, "mamuthka-logo.png"))


if __name__ == "__main__":
    main()
