#!/usr/bin/env python3
"""Autocollants Privio (lot 7.3a) : 24 dessins originaux de « Bulle », la mascotte de Privio.

Dessinés entièrement par ce script (aucune image tierce), à 4× puis réduits pour un tracé
lisse, enregistrés en WebP transparent dans apps/mobile/assets/stickers/privio/.

Usage : python3 tools/autocollants/generer_autocollants.py
"""
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "apps/mobile/assets/stickers/privio"
FONT = ROOT / "apps/mobile/assets/fonts/Inter-Bold.ttf"

S = 4  # sur-échantillonnage
SIZE = 384
W = SIZE * S

PURPLE = (138, 53, 242)
LILAC = (200, 121, 255)
BLUE = (49, 91, 238)
NAVY = (17, 26, 66)
WHITE = (255, 255, 255)
PINK = (255, 133, 170)
RED = (230, 57, 70)
GOLD = (255, 196, 61)
GREEN = (19, 134, 107)


def p(v):
    """Coordonnée du dessin (0–384) vers le canevas sur-échantillonné."""
    return int(v * S)


def gradient(size, top, bottom):
    g = Image.new("RGB", (1, 256))
    for y in range(256):
        t = y / 255
        g.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return g.resize(size)


def bubble_mask(box, tail=True):
    """Corps de Bulle : bulle arrondie avec une petite queue en bas à gauche."""
    m = Image.new("L", (W, W), 0)
    d = ImageDraw.Draw(m)
    x0, y0, x1, y1 = box
    d.rounded_rectangle([p(x0), p(y0), p(x1), p(y1)], radius=p(70), fill=255)
    if tail:
        d.polygon([(p(x0 + 40), p(y1 - 30)), (p(x0 + 10), p(y1 + 34)), (p(x0 + 100), p(y1 - 6))],
                  fill=255)
    return m


def body(img, tint=(PURPLE, BLUE), box=(62, 40, 322, 270), tilt=0):
    mask = bubble_mask(box)
    if tilt:
        mask = mask.rotate(tilt, resample=Image.BICUBIC, center=(W // 2, p(160)))
    # Ombre douce, contour blanc épais (style autocollant), dégradé.
    shadow = mask.filter(ImageFilter.GaussianBlur(p(8)))
    img.paste(Image.new("RGBA", (W, W), (17, 26, 66, 70)), (p(4), p(10)), shadow)
    outline = mask.filter(ImageFilter.MaxFilter(p(9) | 1))
    img.paste(Image.new("RGBA", (W, W), WHITE + (255,)), (0, 0), outline)
    img.paste(gradient((W, W), tint[0], tint[1]).convert("RGBA"), (0, 0), mask)
    # Reflet.
    gloss = Image.new("L", (W, W), 0)
    ImageDraw.Draw(gloss).rounded_rectangle(
        [p(box[0] + 26), p(box[1] + 16), p(box[0] + 120), p(box[1] + 40)], radius=p(12), fill=70)
    img.paste(Image.new("RGBA", (W, W), WHITE + (255,)), (0, 0), gloss.filter(ImageFilter.GaussianBlur(p(3))))


def ellipse(d, cx, cy, rx, ry, fill, width=0, outline=None):
    d.ellipse([p(cx - rx), p(cy - ry), p(cx + rx), p(cy + ry)], fill=fill, outline=outline,
              width=p(width) if width else 0)


def arc(d, cx, cy, rx, ry, start, end, width, fill=NAVY):
    d.arc([p(cx - rx), p(cy - ry), p(cx + rx), p(cy + ry)], start, end, fill=fill, width=p(width))


def eyes(d, style, cx=192, cy=140, gap=48):
    for side in (-1, 1):
        x = cx + side * gap
        if style == "normal":
            ellipse(d, x, cy, 15, 21, NAVY)
            ellipse(d, x + 5, cy - 8, 5, 6, WHITE)
        elif style == "big":
            ellipse(d, x, cy, 22, 27, WHITE)
            ellipse(d, x, cy + 3, 13, 16, NAVY)
            ellipse(d, x + 5, cy - 4, 5, 5, WHITE)
        elif style == "happy":
            arc(d, x, cy + 8, 17, 15, 200, 340, 7)
        elif style == "closed":
            arc(d, x, cy - 4, 16, 12, 20, 160, 7)
        elif style == "heart":
            heart(d, x, cy, 24, RED)
        elif style == "star":
            star(d, x, cy, 22, GOLD)
        elif style == "wink":
            if side == -1:
                ellipse(d, x, cy, 15, 21, NAVY)
                ellipse(d, x + 5, cy - 8, 5, 6, WHITE)
            else:
                arc(d, x, cy + 8, 17, 15, 200, 340, 7)
        elif style == "sad":
            ellipse(d, x, cy + 4, 14, 18, NAVY)
            ellipse(d, x + 4, cy - 3, 5, 5, WHITE)
            d.line([(p(x - 18), p(cy - 18 - side * 6)), (p(x + 18), p(cy - 18 + side * 6))],
                   fill=NAVY, width=p(6))
        elif style == "angry":
            ellipse(d, x, cy + 6, 13, 15, NAVY)
            d.line([(p(x - 20), p(cy - 22 + side * 8)), (p(x + 20), p(cy - 10 - side * 8))],
                   fill=NAVY, width=p(8))
        elif style == "sleepy":
            d.line([(p(x - 16), p(cy + 4)), (p(x + 16), p(cy + 4))], fill=NAVY, width=p(7))
        elif style == "droopy":
            d.pieslice([p(x - 16), p(cy - 12), p(x + 16), p(cy + 22)], 0, 180, fill=NAVY)
            d.line([(p(x - 18), p(cy - 2)), (p(x + 18), p(cy - 2))], fill=NAVY, width=p(5))
        elif style == "determined":
            ellipse(d, x, cy + 4, 14, 18, NAVY)
            ellipse(d, x + 5, cy - 4, 5, 5, WHITE)
            d.line([(p(x - 20), p(cy - 22 + side * 6)), (p(x + 20), p(cy - 14 - side * 6))],
                   fill=NAVY, width=p(7))
        elif style == "curious":
            ellipse(d, x, cy, 15, 21 if side == -1 else 17, NAVY)
            ellipse(d, x + 5, cy - 7, 5, 6, WHITE)
            if side == 1:
                arc(d, x, cy - 30, 20, 10, 200, 340, 6)


def mouth(d, style, cx=192, cy=192):
    if style == "smile":
        arc(d, cx, cy - 12, 30, 22, 20, 160, 7)
    elif style == "big":
        d.chord([p(cx - 38), p(cy - 30), p(cx + 38), p(cy + 26)], 0, 180, fill=NAVY)
        d.chord([p(cx - 20), p(cy + 2), p(cx + 20), p(cy + 26)], 180, 360, fill=PINK)
    elif style == "o":
        ellipse(d, cx, cy, 14, 18, NAVY)
    elif style == "small_o":
        ellipse(d, cx, cy, 9, 11, NAVY)
    elif style == "frown":
        arc(d, cx, cy + 16, 26, 18, 200, 340, 7)
    elif style == "flat":
        d.line([(p(cx - 22), p(cy)), (p(cx + 22), p(cy))], fill=NAVY, width=p(7))
    elif style == "wavy":
        pts = [(p(cx - 26 + i * 2), p(cy + 5 * math.sin(i / 3))) for i in range(27)]
        d.line(pts, fill=NAVY, width=p(6))
    elif style == "tongue":
        d.chord([p(cx - 32), p(cy - 24), p(cx + 32), p(cy + 22)], 0, 180, fill=NAVY)
        ellipse(d, cx + 8, cy + 16, 13, 12, PINK)
    elif style == "grin":
        d.chord([p(cx - 40), p(cy - 28), p(cx + 40), p(cy + 24)], 0, 180, fill=WHITE,
                outline=NAVY, width=p(6))


def cheeks(d, cy=170, color=PINK):
    for x in (122, 262):
        ellipse(d, x, cy, 16, 9, color + (150,))


def heart(d, cx, cy, s, color):
    r = s * 0.55
    ellipse(d, cx - r * 0.55, cy - r * 0.3, r * 0.6, r * 0.6, color)
    ellipse(d, cx + r * 0.55, cy - r * 0.3, r * 0.6, r * 0.6, color)
    d.polygon([(p(cx - s * 0.62), p(cy - r * 0.05)), (p(cx + s * 0.62), p(cy - r * 0.05)),
               (p(cx), p(cy + s * 0.75))], fill=color)


def star(d, cx, cy, r, color, points=5):
    pts = []
    for i in range(points * 2):
        rr = r if i % 2 == 0 else r * 0.45
        a = -math.pi / 2 + i * math.pi / points
        pts.append((p(cx + rr * math.cos(a)), p(cy + rr * math.sin(a))))
    d.polygon(pts, fill=color)


def sparkle(d, cx, cy, r, color=GOLD):
    d.polygon([(p(cx), p(cy - r)), (p(cx + r * 0.25), p(cy - r * 0.25)), (p(cx + r), p(cy)),
               (p(cx + r * 0.25), p(cy + r * 0.25)), (p(cx), p(cy + r)),
               (p(cx - r * 0.25), p(cy + r * 0.25)), (p(cx - r), p(cy)),
               (p(cx - r * 0.25), p(cy - r * 0.25))], fill=color)


def drop(d, cx, cy, r, color=(120, 190, 255)):
    ellipse(d, cx, cy + r * 0.4, r * 0.75, r * 0.75, color)
    d.polygon([(p(cx - r * 0.65), p(cy + r * 0.2)), (p(cx + r * 0.65), p(cy + r * 0.2)),
               (p(cx), p(cy - r))], fill=color)


def text(d, xy, s, size, fill=NAVY, anchor="mm", stroke=0):
    f = ImageFont.truetype(str(FONT), p(size))
    d.text((p(xy[0]), p(xy[1])), s, font=f, fill=fill, anchor=anchor,
           stroke_width=p(stroke), stroke_fill=WHITE)


def label(img, s):
    """Étiquette blanche arrondie sous Bulle."""
    d = ImageDraw.Draw(img)
    size = 40
    f = ImageFont.truetype(str(FONT), p(size))
    while d.textlength(s, font=f) > p(330) and size > 22:
        size -= 2
        f = ImageFont.truetype(str(FONT), p(size))
    w = d.textlength(s, font=f) / S
    x0, x1 = 192 - w / 2 - 22, 192 + w / 2 + 22
    sh = Image.new("L", (W, W), 0)
    ImageDraw.Draw(sh).rounded_rectangle([p(x0), p(300), p(x1), p(362)], radius=p(31), fill=90)
    img.paste(Image.new("RGBA", (W, W), NAVY + (255,)), (p(2), p(6)),
              sh.filter(ImageFilter.GaussianBlur(p(6))))
    d.rounded_rectangle([p(x0), p(300), p(x1), p(362)], radius=p(31), fill=WHITE,
                        outline=PURPLE, width=p(4))
    d.text((p(192), p(331)), s, font=f, fill=NAVY, anchor="mm")


def confetti(d, seed=3, n=26):
    rnd = random.Random(seed)
    colors = [GOLD, PINK, LILAC, (99, 210, 255), GREEN]
    for _ in range(n):
        x, y = rnd.uniform(20, 364), rnd.uniform(14, 120)
        if 70 < x < 314 and y > 40:
            continue
        c = rnd.choice(colors)
        a = rnd.uniform(0, math.pi)
        dx, dy = 7 * math.cos(a), 7 * math.sin(a)
        d.line([(p(x - dx), p(y - dy)), (p(x + dx), p(y + dy))], fill=c, width=p(5))


# ---------------------------------------------------------------------------------------
# Les 24 autocollants (nom de fichier, étiquette, dessin)
# ---------------------------------------------------------------------------------------
def draw(name, caption, eyes_style, mouth_style, extras=None, tint=(PURPLE, BLUE), blush=False,
         tilt=0):
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    body(img, tint=tint, tilt=tilt)
    d = ImageDraw.Draw(img, "RGBA")
    if blush:
        cheeks(d)
    eyes(d, eyes_style)
    mouth(d, mouth_style)
    if extras:
        extras(d, img)
    label(img, caption)
    out = img.resize((SIZE, SIZE), Image.LANCZOS)
    OUT.mkdir(parents=True, exist_ok=True)
    out.save(OUT / f"{name}.webp", "WEBP", quality=86, method=6)


def x_hearts(d, _):
    heart(d, 330, 70, 34, RED)
    heart(d, 52, 110, 22, PINK)


def x_stars(d, _):
    star(d, 40, 60, 26, GOLD)
    star(d, 344, 90, 20, GOLD)
    sparkle(d, 320, 40, 16)


def x_courage(d, _):
    sparkle(d, 40, 70, 22)
    sparkle(d, 345, 60, 18)
    text(d, (338, 150), "!", 70, fill=GOLD, stroke=3)


def x_tear(d, _):
    drop(d, 150, 172, 13)


def x_wave(d, _):
    for i, r in enumerate((24, 38, 52)):
        arc(d, 330, 120, r, r, 300, 60, 5, fill=LILAC)
    heart(d, 46, 70, 22, PINK)


def x_question(d, _):
    text(d, (338, 70), "?", 86, fill=GOLD, stroke=4)


def x_heart_small(d, _):
    heart(d, 336, 72, 30, PINK)


def x_party(d, img):
    confetti(d)
    d.polygon([(p(230), p(52)), (p(300), p(46)), (p(278), p(-8))], fill=GOLD)
    ellipse(d, 278, -6, 9, 9, PINK)


def x_phone(d, _):
    d.rounded_rectangle([p(300), p(40), p(352), p(128)], radius=p(10), fill=NAVY,
                        outline=WHITE, width=p(4))
    d.rectangle([p(308), p(54), p(344), p(110)], fill=(99, 210, 255))
    for i, r in enumerate((16, 28)):
        arc(d, 290, 60, r, r, 180, 270, 4, fill=GOLD)


def x_wink(d, _):
    sparkle(d, 336, 60, 20)


def x_sun(d, _):
    for i in range(10):
        a = i * math.pi / 5
        d.line([(p(52 + 26 * math.cos(a)), p(52 + 26 * math.sin(a))),
                (p(52 + 40 * math.cos(a)), p(52 + 40 * math.sin(a)))], fill=GOLD, width=p(6))
    ellipse(d, 52, 52, 20, 20, GOLD)


def x_night(d, _):
    ellipse(d, 52, 56, 30, 30, GOLD)
    ellipse(d, 66, 46, 28, 28, (0, 0, 0, 0))
    text(d, (330, 70), "z", 34, fill=LILAC, stroke=3)
    text(d, (352, 40), "z", 26, fill=LILAC, stroke=3)


def x_laugh(d, _):
    drop(d, 128, 150, 11)
    drop(d, 256, 150, 11)
    text(d, (340, 64), "Ha", 34, fill=GOLD, stroke=3)


def x_love(d, _):
    heart(d, 330, 60, 30, RED)
    heart(d, 56, 76, 20, PINK)


def x_ok(d, _):
    ellipse(d, 334, 70, 34, 34, GREEN)
    d.line([(p(316), p(70)), (p(330), p(86)), (p(354), p(56))], fill=WHITE, width=p(9),
           joint="curve")


def x_no(d, _):
    ellipse(d, 334, 70, 34, 34, RED)
    d.line([(p(318), p(54)), (p(350), p(86))], fill=WHITE, width=p(9))
    d.line([(p(350), p(54)), (p(318), p(86))], fill=WHITE, width=p(9))


def x_oops(d, _):
    drop(d, 300, 80, 16)


def x_wow(d, _):
    sparkle(d, 36, 60, 24)
    sparkle(d, 348, 50, 20)
    sparkle(d, 330, 120, 12, color=WHITE)


def x_onmyway(d, _):
    for i, y in enumerate((110, 150, 190)):
        d.line([(p(8 + i * 10), p(y)), (p(50 + i * 10), p(y))], fill=LILAC, width=p(7))


def x_wait(d, _):
    for i in range(3):
        ellipse(d, 300 + i * 22, 72, 8, 8, LILAC)


def x_congrats(d, _):
    confetti(d, seed=11, n=34)
    star(d, 46, 56, 22, GOLD)


def x_food(d, _):
    d.chord([p(286), p(70), p(370), p(150)], 0, 180, fill=WHITE)
    for i in range(3):
        x = 306 + i * 20
        d.line([(p(x), p(96)), (p(x + 6), p(78)), (p(x), p(60))], fill=WHITE, width=p(4))


def x_tired(d, _):
    drop(d, 300, 78, 14)
    text(d, (64, 64), "…", 40, fill=LILAC, stroke=3)


def x_angry(d, _):
    for x in (322, 350):
        d.line([(p(x), p(70)), (p(x - 8), p(46)), (p(x + 4), p(30))], fill=(200, 210, 230),
               width=p(6))


STICKERS = [
    ("merci", "Merci !", "happy", "smile", x_hearts, (PURPLE, BLUE), True),
    ("bravo", "Bravo !", "star", "big", x_stars, (PURPLE, BLUE), False),
    ("courage", "Courage !", "determined", "smile", x_courage, (PURPLE, BLUE), False),
    ("desole", "Désolé", "sad", "frown", x_tear, ((120, 110, 230), BLUE), False),
    ("bonne_arrivee", "Bonne arrivée", "happy", "big", x_wave, (PURPLE, BLUE), True),
    ("on_dit_quoi", "On dit quoi ?", "curious", "small_o", x_question, (PURPLE, BLUE), False),
    ("ca_va_aller", "Ça va aller", "closed", "smile", x_heart_small, (LILAC, PURPLE), True),
    ("bonne_fete", "Bonne fête !", "happy", "big", x_party, (PURPLE, BLUE), True),
    ("je_t_appelle", "Je t’appelle", "normal", "smile", x_phone, (PURPLE, BLUE), False),
    ("a_tout", "À tout’ !", "wink", "tongue", x_wink, (PURPLE, BLUE), False),
    ("bonjour", "Bonjour !", "happy", "big", x_sun, (LILAC, PURPLE), True),
    ("bonne_nuit", "Bonne nuit", "closed", "small_o", x_night, ((120, 110, 225), (70, 70, 175)), False),
    ("mdr", "Mdr", "happy", "big", x_laugh, (PURPLE, BLUE), True),
    ("je_t_aime", "Je t’aime", "heart", "smile", x_love, (LILAC, PURPLE), True),
    ("d_accord", "D’accord", "normal", "smile", x_ok, (PURPLE, BLUE), False),
    ("non", "Non !", "angry", "frown", x_no, (PURPLE, BLUE), False),
    ("oups", "Oups", "big", "o", x_oops, (PURPLE, BLUE), False),
    ("waouh", "Waouh !", "big", "o", x_wow, (PURPLE, BLUE), False),
    ("j_arrive", "J’arrive !", "determined", "grin", x_onmyway, (PURPLE, BLUE), False),
    ("attends", "Attends…", "normal", "flat", x_wait, (PURPLE, BLUE), False),
    ("felicitations", "Félicitations !", "star", "big", x_congrats, (PURPLE, BLUE), True),
    ("bon_appetit", "Bon appétit !", "happy", "tongue", x_food, (PURPLE, BLUE), True),
    ("fatigue", "Fatigué", "droopy", "wavy", x_tired, ((110, 100, 200), (70, 80, 170)), False),
    ("fache", "Fâché !", "angry", "frown", x_angry, ((220, 70, 110), (160, 40, 160)), False),
]


if __name__ == "__main__":
    for name, caption, e, m, extra, tint, blush in STICKERS:
        draw(name, caption, e, m, extra, tint=tint, blush=blush)
    total = sum(f.stat().st_size for f in OUT.glob("*.webp"))
    print(f"{len(STICKERS)} autocollants, {total // 1024} Ko au total → {OUT}")
