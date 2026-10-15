#!/usr/bin/env python3
"""Mamuthka linux grafikák: háttérkép és boot-logó.

Háttérkép: a mamutos kép (assets/wallpaper-portrait.jpg, fekvőben -landscape).
Boot-logó és ikon: a mamutos rész kivágása az álló képből.
Választható alternatíva: fekete háttér kicsi, piros neon pingvinkörvonallal.

Használat: gen-artwork.py <rootfs> <képernyő-szélesség> <képernyő-magasság>
Függőség: python3-pil (Pillow)
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")


def fit_black(img, w, h):
    """Arányosan a képernyőre méretez, a maradékot feketével tölti ki."""
    scale = min(w / img.width, h / img.height)
    img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    out = Image.new("RGB", (w, h), (0, 0, 0))
    out.paste(img, ((w - img.width) // 2, (h - img.height) // 2))
    return out


def penguin_lines(w, h, cx, cy, s, lw):
    """Pingvin vonalrajz maszkként: egybefüggő sziluett-körvonal + has, szemek, csőr."""
    pw = s * 0.72
    sil = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(sil)
    def box(x0, y0, x1, y1):
        return [cx + x0 * pw, cy + y0 * s, cx + x1 * pw, cy + y1 * s]
    for b in (box(-0.50, -0.25, 0.50, 0.48), box(-0.33, -0.50, 0.33, -0.04),
              box(-0.40, 0.40, 0.00, 0.54), box(0.00, 0.40, 0.40, 0.54)):
        d.ellipse(b, fill=255)
    # körvonal = sziluett mínusz a beljebb húzott sziluett
    inner = sil.filter(ImageFilter.MinFilter(lw * 2 + 1))
    out = Image.new("L", (w, h), 0)
    out.paste(255, mask=sil)
    out.paste(0, mask=inner)
    d = ImageDraw.Draw(out)
    d.ellipse(box(-0.30, 0.00, 0.30, 0.40), outline=255, width=lw)             # has
    for dx in (-0.12, 0.12):                                                   # szemek
        d.ellipse(box(dx - 0.06, -0.36, dx + 0.06, -0.24), outline=255, width=lw)
    d.polygon([(cx - pw * 0.11, cy - s * 0.17), (cx + pw * 0.11, cy - s * 0.17),
               (cx, cy - s * 0.08)], outline=255, width=lw)                    # csőr
    return out


def wallpaper(w, h):
    """Fekete háttér, kicsi pingvinkörvonal élénkpiros derengéssel."""
    s = min(w, h) * 0.20
    lw = max(3, int(s / 80))
    m = penguin_lines(w, h, w / 2, h * 0.45, s, lw)
    glow = m.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(s / 14))
    img = Image.new("RGB", (w, h), (0, 0, 0))
    img.paste((255, 0, 0), mask=Image.eval(glow, lambda v: min(255, int(v * 1.6))))
    img.paste((255, 70, 70), mask=m)
    return img


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

    # Alapértelmezett háttér: a mamutos kép.
    fit_black(portrait, w, h).save(os.path.join(bg, "wallpaper.png"))
    fit_black(landscape, max(w, h), min(w, h)).save(os.path.join(bg, "wallpaper-landscape.png"))
    # A neon pingvin választható alternatíva a Háttérkép-beállításokban.
    wallpaper(w, h).save(os.path.join(bg, "pingvin-neon.png"))
    logo(portrait, min(w, h) * 3 // 4).save(os.path.join(ply, "logo.png"))
    dot(max(8, min(w, h) // 60)).save(os.path.join(ply, "dot.png"))

    # Kis ikon: a mamutfej négyzetes kivágása
    pw, ph = portrait.size
    side = int(pw * 0.62)
    icon = portrait.crop(((pw - side) // 2, int(ph * 0.20), (pw + side) // 2, int(ph * 0.20) + side))
    icon.resize((256, 256), Image.LANCZOS).save(os.path.join(icons, "mamuthka-logo.png"))


if __name__ == "__main__":
    main()
