"""Generates the 6browser logo placeholder (an indigo rounded square with a
white "6") as assets/logo.png and windows/runner/resources/app_icon.ico.

Run: python scripts/make_icon.py
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SIZE = 512
INDIGO = (63, 81, 181, 255)


def find_font(size):
    for name in ("arialbd.ttf", "Arial Bold.ttf", "DejaVuSans-Bold.ttf", "segoeuib.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
d.rounded_rectangle((0, 0, SIZE - 1, SIZE - 1), radius=SIZE // 4, fill=INDIGO)
font = find_font(int(SIZE * 0.72))
box = d.textbbox((0, 0), "6", font=font)
w, h = box[2] - box[0], box[3] - box[1]
d.text(((SIZE - w) / 2 - box[0], (SIZE - h) / 2 - box[1]), "6", font=font, fill="white")

(ROOT / "assets").mkdir(exist_ok=True)
img.save(ROOT / "assets" / "logo.png")
img.save(
    ROOT / "windows" / "runner" / "resources" / "app_icon.ico",
    sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
)
print("wrote assets/logo.png and app_icon.ico")
