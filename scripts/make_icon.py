"""Generates every app icon from assets/logo_source.png (the 6browser globe
logo on a transparent background):

  assets/logo.png                                   in-app logo (512px)
  windows/runner/resources/app_icon.ico             exe / installer icon
  macos/Runner/Assets.xcassets/AppIcon.appiconset/  macOS app icons
  ios/Runner/Assets.xcassets/AppIcon.appiconset/    iOS app icons (opaque)
  android/app/src/main/res/mipmap-*/                Android launcher icons
                                                    (legacy + adaptive)

Run: python scripts/make_icon.py
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets" / "logo_source.png"
MAC_DIR = ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
IOS_DIR = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
RES_DIR = ROOT / "android" / "app" / "src" / "main" / "res"
BACKGROUND = (255, 255, 255, 255)  # tile color where the platform needs one
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


def on_tile(px, scale):
    """The logo at `scale` of the side, centered on an opaque square tile."""
    tile = Image.new("RGBA", (px, px), BACKGROUND)
    logo = sized(round(px * scale))
    off = (px - logo.width) // 2
    tile.paste(logo, (off, off), logo)
    return tile


# iOS masks the corners itself and rejects icons with an alpha channel.
IOS_ICONS = {
    "20x20@1x": 20, "20x20@2x": 40, "20x20@3x": 60,
    "29x29@1x": 29, "29x29@2x": 58, "29x29@3x": 87,
    "40x40@1x": 40, "40x40@2x": 80, "40x40@3x": 120,
    "60x60@2x": 120, "60x60@3x": 180,
    "76x76@1x": 76, "76x76@2x": 152,
    "83.5x83.5@2x": 167,
    "1024x1024@1x": 1024,
}
for name, px in IOS_ICONS.items():
    on_tile(px, 0.8).convert("RGB").save(IOS_DIR / f"Icon-App-{name}.png")

# Android: legacy icon (pre-8.0) plus an adaptive icon whose foreground keeps
# the logo inside the 66dp safe zone of the 108dp layer.
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
for name, k in DENSITIES.items():
    folder = RES_DIR / f"mipmap-{name}"
    folder.mkdir(exist_ok=True)
    sized(round(48 * k)).save(folder / "ic_launcher.png")
    fg_px = round(108 * k)
    fg = Image.new("RGBA", (fg_px, fg_px), (0, 0, 0, 0))
    logo = sized(round(fg_px * 0.58))
    off = (fg_px - logo.width) // 2
    fg.paste(logo, (off, off), logo)
    fg.save(folder / "ic_launcher_foreground.png")

anydpi = RES_DIR / "mipmap-anydpi-v26"
anydpi.mkdir(exist_ok=True)
(anydpi / "ic_launcher.xml").write_text(
    '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
'''
)
(RES_DIR / "values" / "ic_launcher_background.xml").write_text(
    '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#%02X%02X%02X</color>
</resources>
''' % BACKGROUND[:3]
)
print("wrote assets/logo.png, app_icon.ico, macOS, iOS and Android icons")
