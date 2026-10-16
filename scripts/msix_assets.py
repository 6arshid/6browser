"""Writes the MSIX tile and taskbar images from assets/logo_source.png.

    python scripts/msix_assets.py <output Assets folder>

Images use scale/targetsize qualifiers; build_msix.ps1 indexes them into
resources.pri with makepri so Windows picks the right size.
"""
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
LOGO = Image.open(ROOT / "assets" / "logo_source.png").convert("RGBA")


def fitted(w, h, fill=0.8):
    """Logo centered on a transparent w x h canvas, taking `fill` of the short side."""
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    side = round(min(w, h) * fill)
    lg = LOGO.copy()
    lg.thumbnail((side, side), Image.LANCZOS)
    canvas.alpha_composite(lg, ((w - lg.width) // 2, (h - lg.height) // 2))
    return canvas


def main(out):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    for scale in (100, 125, 150, 200, 400):
        k = scale / 100
        sizes = {
            "Square44x44Logo": (44, 44, 0.9),
            "Square150x150Logo": (150, 150, 0.6),
            "Wide310x150Logo": (310, 150, 0.6),
            "StoreLogo": (50, 50, 0.9),
        }
        for name, (w, h, fill) in sizes.items():
            fitted(round(w * k), round(h * k), fill).save(out / f"{name}.scale-{scale}.png")
    # Taskbar / Start list icons, without the accent-colored plate.
    for t in (16, 20, 24, 30, 32, 36, 40, 48, 60, 64, 72, 80, 96, 256):
        img = fitted(t, t, 1.0)
        img.save(out / f"Square44x44Logo.targetsize-{t}.png")
        img.save(out / f"Square44x44Logo.targetsize-{t}_altform-unplated.png")
        img.save(out / f"Square44x44Logo.targetsize-{t}_altform-lightunplated.png")


if __name__ == "__main__":
    main(sys.argv[1])
