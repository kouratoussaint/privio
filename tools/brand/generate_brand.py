#!/usr/bin/env python3
"""Recréation vectorielle PROVISOIRE du logo PRIVIO (proposition n° 1), à faire valider.

Produit, de façon reproductible :
  - docs/brand/*.svg            : symbole, fond, logo complet (sources vectorielles)
  - apps/mobile/assets/brand/   : PNG utilisés dans l'app (splash)
  - apps/mobile/android/.../res : icône adaptative (avant-plan / fond) + icônes héritées
                                  + icône de notification monochrome

Conforme au guide : bleu nuit + dégradés violet/bleu, bulle en forme de P, trois points,
bouclier + cadenas, mot « Privio » en blanc. Pas de « 72h », rien des concepts 2/3.
Prérequis : rsvg-convert, fontTools, police Inter (apps/mobile/assets/fonts).
"""
from pathlib import Path
import subprocess

from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[2]
FONT = ROOT / "apps/mobile/assets/fonts/Inter-Bold.ttf"
DOCS = ROOT / "docs/brand"
APP_ASSETS = ROOT / "apps/mobile/assets/brand"
RES = ROOT / "apps/mobile/android/app/src/main/res"

NAVY, NAVY_DEEP = "#111A42", "#0C1438"
PURPLE, LILAC, BLUE = "#8A35F2", "#C879FF", "#315BEE"
BUBBLE_A, BUBBLE_B = "#1B2A78", "#2B3FB0"

DEFS = f"""
<defs>
  <linearGradient id="stroke" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="#FFFFFF"/><stop offset="0.55" stop-color="#F1E4FF"/>
    <stop offset="0.8" stop-color="{LILAC}"/><stop offset="1" stop-color="{PURPLE}"/>
  </linearGradient>
  <linearGradient id="bubble" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="{BUBBLE_A}"/><stop offset="1" stop-color="{BUBBLE_B}"/>
  </linearGradient>
  <linearGradient id="shield" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="{PURPLE}"/><stop offset="1" stop-color="#5B1FB8"/>
  </linearGradient>
  <radialGradient id="glowTL" cx="0" cy="0" r="0.75">
    <stop offset="0" stop-color="{PURPLE}" stop-opacity="0.95"/>
    <stop offset="0.45" stop-color="{PURPLE}" stop-opacity="0.35"/>
    <stop offset="1" stop-color="{PURPLE}" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="glowBR" cx="1" cy="1" r="0.7">
    <stop offset="0" stop-color="{PURPLE}" stop-opacity="0.9"/>
    <stop offset="0.4" stop-color="{BLUE}" stop-opacity="0.35"/>
    <stop offset="1" stop-color="{BLUE}" stop-opacity="0"/>
  </radialGradient>
</defs>"""

# Symbole dessiné dans un repère 100 x 100.
SYMBOL = """
<path d="M36 14 H60 C71 14 80 23 80 34 V38 C80 49 71 58 60 58 H38 L24 71 V34 C24 23 27 14 36 14 Z"
      fill="url(#bubble)" stroke="url(#stroke)" stroke-width="6" stroke-linejoin="round"/>
<circle cx="42" cy="36" r="3.8" fill="#FFFFFF"/>
<circle cx="52" cy="36" r="3.8" fill="#FFFFFF"/>
<circle cx="62" cy="36" r="3.8" fill="#FFFFFF"/>
<path d="M75 47 L88 51.5 V61 C88 69.5 82.5 75.5 75 79 C67.5 75.5 62 69.5 62 61 V51.5 Z"
      fill="url(#shield)" stroke="#FFFFFF" stroke-width="2.6" stroke-linejoin="round"/>
<path d="M71.6 62 V59.2 A3.4 3.4 0 0 1 78.4 59.2 V62" fill="none" stroke="#FFFFFF" stroke-width="2.2"/>
<rect x="69.4" y="61.6" width="11.2" height="9" rx="1.8" fill="#FFFFFF"/>
<circle cx="75" cy="65.4" r="1.4" fill="#5B1FB8"/>
"""

# Silhouette monochrome (icône de notification Android : blanc sur transparent).
SYMBOL_MONO = """
<path d="M36 14 H60 C71 14 80 23 80 34 V38 C80 49 71 58 60 58 H38 L24 71 V34 C24 23 27 14 36 14 Z
         M42 32.2 A3.8 3.8 0 1 0 42 39.8 A3.8 3.8 0 1 0 42 32.2 Z
         M52 32.2 A3.8 3.8 0 1 0 52 39.8 A3.8 3.8 0 1 0 52 32.2 Z
         M62 32.2 A3.8 3.8 0 1 0 62 39.8 A3.8 3.8 0 1 0 62 32.2 Z" fill="#FFFFFF" fill-rule="evenodd"/>
<path d="M75 47 L88 51.5 V61 C88 69.5 82.5 75.5 75 79 C67.5 75.5 62 69.5 62 61 V51.5 Z
         M71.6 62 V59.2 A3.4 3.4 0 0 1 78.4 59.2 V62 H80.6 V70.6 H69.4 V62 Z" fill="#FFFFFF" fill-rule="evenodd"/>
"""


def background(size: int, radius: int) -> str:
    k = size / 1024
    bands = (f'<clipPath id="clip{size}"><rect width="{size}" height="{size}" rx="{radius}"/></clipPath>'
             f'<g clip-path="url(#clip{size})" transform="scale({k:.5f})">'
             f'<path d="M0 420 C70 200 230 60 470 0 L330 0 C170 50 60 160 0 300 Z" fill="{PURPLE}" opacity="0.55"/>'
             f'<path d="M1024 640 C960 830 820 960 600 1024 L760 1024 C900 960 990 860 1024 760 Z" fill="{PURPLE}" opacity="0.6"/>'
             f'<path d="M1024 760 C980 880 900 970 800 1024 L1024 1024 Z" fill="{BLUE}" opacity="0.5"/>'
             f'</g>')
    return (f'<rect width="{size}" height="{size}" rx="{radius}" fill="{NAVY}"/>'
            f'<rect width="{size}" height="{size}" rx="{radius}" fill="url(#glowTL)"/>'
            f'<rect width="{size}" height="{size}" rx="{radius}" fill="url(#glowBR)"/>' + bands)


def wordmark(font_size: float, center_x: float, baseline: float) -> str:
    """« Privio » en Inter Bold, i sans point + points violets (comme le logo retenu)."""
    font = TTFont(FONT)
    upm = font["head"].unitsPerEm
    cmap = font.getBestCmap()
    hmtx = font["hmtx"]
    glyf = font["glyf"]
    scale = font_size / upm
    chars = ["P", "r", "\u0131", "v", "\u0131", "o"]
    widths = [hmtx[cmap[ord(c)]][0] * scale for c in chars]
    x = center_x - sum(widths) / 2
    x_height = font["OS/2"].sxHeight * scale
    parts, dots = [], []
    for c, w in zip(chars, widths):
        if c == "\u0131":
            g = glyf[cmap[ord(c)]]
            g.recalcBounds(glyf)
            cx = x + (g.xMin + g.xMax) / 2 * scale
            dots.append(f'<circle cx="{cx:.1f}" cy="{baseline - x_height - font_size * 0.16:.1f}" '
                        f'r="{font_size * 0.085:.1f}" fill="{PURPLE}"/>')
        x += w
    text = (f'<text x="{center_x}" y="{baseline}" text-anchor="middle" font-family="Inter" '
            f'font-weight="700" font-size="{font_size}" fill="#FFFFFF">Pr\u0131v\u0131o</text>')
    return text + "".join(dots)


def svg(size: int, body: str) -> str:
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
            f'viewBox="0 0 {size} {size}">{DEFS}{body}</svg>')


def render(svg_path: Path, png_path: Path, px: int) -> None:
    png_path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["rsvg-convert", "-w", str(px), "-h", str(px), str(svg_path), "-o", str(png_path)],
                   check=True)


def main() -> None:
    DOCS.mkdir(parents=True, exist_ok=True)
    APP_ASSETS.mkdir(parents=True, exist_ok=True)

    # 1. Symbole seul (transparent).
    (DOCS / "privio_symbole.svg").write_text(svg(100, SYMBOL))
    # 2. Logo complet carré (icône de présentation, splash).
    full = (background(1024, 230)
            + f'<g transform="translate(118 8) scale(7.7)">{SYMBOL}</g>'
            + wordmark(255, 512, 915))
    (DOCS / "privio_logo_complet.svg").write_text(svg(1024, full))
    # 3. Icône adaptative Android : 108 dp, zone sûre = cercle de 66 dp centré.
    fg = f'<g transform="translate(13.7 20.2) scale(0.72)">{SYMBOL}</g>'
    (DOCS / "privio_icone_avant_plan.svg").write_text(svg(108, fg))
    (DOCS / "privio_icone_fond.svg").write_text(svg(108, background(108, 0)))
    legacy = background(108, 24) + f'<g transform="translate(14 14) scale(0.8)">{SYMBOL}</g>'
    (DOCS / "privio_icone_heritee.svg").write_text(svg(108, legacy))
    (DOCS / "privio_notification_mono.svg").write_text(svg(100, SYMBOL_MONO))

    render(DOCS / "privio_logo_complet.svg", APP_ASSETS / "privio_logo_complet.png", 1024)
    render(DOCS / "privio_symbole.svg", APP_ASSETS / "privio_symbole.png", 512)
    render(DOCS / "privio_logo_complet.svg", DOCS / "apercu_logo_complet_512.png", 512)

    densities = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    for name, f in densities.items():
        d = RES / f"mipmap-{name}"
        render(DOCS / "privio_icone_avant_plan.svg", d / "ic_launcher_foreground.png", int(108 * f))
        render(DOCS / "privio_icone_fond.svg", d / "ic_launcher_background.png", int(108 * f))
        render(DOCS / "privio_icone_heritee.svg", d / "ic_launcher.png", int(48 * f))
        render(DOCS / "privio_notification_mono.svg", RES / f"drawable-{name}" / "ic_stat_privio.png",
               int(24 * f))

    anydpi = RES / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@mipmap/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '</adaptive-icon>\n')
    print("Logo provisoire généré.")


if __name__ == "__main__":
    main()
