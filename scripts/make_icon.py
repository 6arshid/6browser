"""Generates every app icon from assets/logo_source.png (the 6browser globe
logo on a transparent background):

  assets/logo.png                                   in-app logo (512px)
  windows/runner/resources/app_icon.ico             exe / installer icon
  macos/Runner/Assets.xcassets/AppIcon.appiconset/  macOS app icons

Run: python scripts/make_icon.py
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets" / "logo_source.png"
MAC_DIR = ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
MARGIN = 0.04  # transparent padding around the logo, as a fraction of the side

src = Image.open(SOURCE).convert("RGBA")

# Drop faint stray pixels, then crop to the logo itself.
alpha = src.getchannel("A")
alpha = alpha.point(lambda v: v if v > 40 else 0)
src.putalpha(alpha)
src = src.crop(alpha.getbbox())

# Center on a transparent square canvas.
side = int(max(src.size) * (1 + 2 * MARGIN))
square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
square.paste(src, ((side - src.width) // 2, (side - src.height) // 2), src)


def sized(px):
    return square.resize((px, px), Image.LANCZOS)


sized(512).save(ROOT / "assets" / "logo.png")
sized(256).save(
    ROOT / "windows" / "runner" / "resources" / "app_icon.ico",
    sizes=[(16, 16), (20, 20), (24, 24), (32, 32), (40, 40), (48, 48), (64, 64), (128, 128), (256, 256)],
)
for px in (16, 32, 64, 128, 256, 512, 1024):
    sized(px).save(MAC_DIR / f"app_icon_{px}.png")
print("wrote assets/logo.png, app_icon.ico and macOS app icons")
