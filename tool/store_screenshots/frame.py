"""Builds the store images from the raw screenshots.

Run after store_screenshots_test.dart:
    python tool/store_screenshots/frame.py

Writes to store_listing/:
  screenshots/android/*.png   1080x1920 framed phone shots (Google Play)
  screenshots/windows/*.png   1920x1080 framed desktop shots (Microsoft Store)
  graphics/                   Play icon + feature graphic, Microsoft Store art
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "store_listing"
RAW = OUT / "screenshots" / "raw"
LOGO = ROOT / "assets" / "logo_source.png"
FONT_BOLD = "C:/Windows/Fonts/segoeuib.ttf"
FONT = "C:/Windows/Fonts/segoeui.ttf"

TOP = (10, 34, 92)  # deep navy
BOTTOM = (16, 98, 214)  # logo blue

ANDROID = {
    "01-new-tab": ("Fast from the first tap", "A clean New Tab with your favorite sites"),
    "02-article": ("Pages load fast", "A modern web engine with zero clutter"),
    "03-tabs": ("Switch tabs in a flash", "All your tabs in one simple grid"),
    "04-menu": ("Everything one tap away", "Bookmarks, history, themes and more"),
    "05-private": ("Private tabs", "Browse without saving history"),
    "06-dark": ("Easy on the eyes", "Dark mode for day and night"),
    "07-bookmarks": ("Bookmarks made simple", "Save any page with a single tap"),
    "08-appearance": ("Make it yours", "Accent colors, dark mode and Chrome themes"),
}
WINDOWS = {
    "01-new-tab": ("A fast, clean browser for Windows", "Chromium engine, lightweight interface"),
    "02-article": ("Built for speed", "Tabs, bookmarks bar and a smart address bar"),
    "03-menu": ("Everything one click away", "With keyboard shortcuts for every action"),
    "04-context-menu": ("A right-click menu that just works", "Open links in new or private tabs, copy, inspect"),
    "05-dark": ("Dark mode and accent colors", "Pick the look that suits you"),
    "06-private": ("Private browsing", "Private tabs leave no history behind"),
    "07-history": ("Find anything you visited", "Searchable history, delete one page or all"),
    "08-downloads": ("A real downloads manager", "Track progress, open files and folders"),
    "09-appearance": ("Install Chrome themes", "From the Chrome Web Store, a .crx or a folder"),
    "10-settings": ("Simple settings", "Search engine, home page, theme and import"),
}


def gradient(w, h, top=TOP, bottom=BOTTOM):
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(1, h - 1)
        d.line([(0, y), (w, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return img


def rounded(img, r):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.width - 1, img.height - 1], r, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def paste_shadow(bg, fg, xy, r, blur=40, alpha=110):
    sh = Image.new("RGBA", (fg.width + blur * 4, fg.height + blur * 4), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(
        [blur * 2, blur * 2 + blur // 2, blur * 2 + fg.width, blur * 2 + fg.height + blur // 2],
        r, fill=(0, 0, 0, alpha))
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    bg.alpha_composite(sh, (xy[0] - blur * 2, xy[1] - blur * 2))
    bg.alpha_composite(fg, xy)


def centered(d, text, y, font, w, fill):
    tw = d.textlength(text, font=font)
    d.text(((w - tw) / 2, y), text, font=font, fill=fill)


def fit_font(d, text, path, size, max_w):
    while size > 10:
        f = ImageFont.truetype(path, size)
        if d.textlength(text, font=f) <= max_w:
            return f
        size -= 2
    return ImageFont.truetype(path, size)


def android(name, title, sub):
    W, H = 1080, 1920
    bg = gradient(W, H).convert("RGBA")
    d = ImageDraw.Draw(bg)
    tf = fit_font(d, title, FONT_BOLD, 84, W - 120)
    centered(d, title, 110, tf, W, "white")
    sf = fit_font(d, sub, FONT, 44, W - 120)
    centered(d, sub, 230, sf, W, (205, 222, 255))
    shot = Image.open(RAW / f"android-{name}.png").convert("RGB")
    sw = 760
    sh = round(shot.height * sw / shot.width)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    bezel = 22
    phone = Image.new("RGB", (sw + bezel * 2, sh + bezel * 2), (18, 20, 26))
    phone.paste(shot, (bezel, bezel))
    phone = rounded(phone, 70)
    # inner rounding of the screen
    inner = rounded(shot, 50)
    phone.alpha_composite(inner, (bezel, bezel))
    x = (W - phone.width) // 2
    paste_shadow(bg, phone, (x, 360), 70)
    bg.convert("RGB").save(OUT / "screenshots" / "android" / f"{name}.png")


def windows(name, title, sub):
    W, H = 1920, 1080
    bg = gradient(W, H).convert("RGBA")
    d = ImageDraw.Draw(bg)
    tf = fit_font(d, title, FONT_BOLD, 72, W - 200)
    centered(d, title, 46, tf, W, "white")
    sf = fit_font(d, sub, FONT, 38, W - 200)
    centered(d, sub, 148, sf, W, (205, 222, 255))
    shot = Image.open(RAW / f"windows-{name}.png").convert("RGB")
    sw = 1500
    sh = round(shot.height * sw / shot.width)
    shot = rounded(shot.resize((sw, sh), Image.LANCZOS), 18)
    x = (W - sw) // 2
    paste_shadow(bg, shot, (x, 236), 18, blur=36, alpha=130)
    bg.convert("RGB").save(OUT / "screenshots" / "windows" / f"{name}.png")


def logo(size):
    lg = Image.open(LOGO).convert("RGBA")
    lg.thumbnail((size, size), Image.LANCZOS)
    return lg


def graphics():
    g = OUT / "graphics"
    g.mkdir(parents=True, exist_ok=True)

    # Google Play hi-res icon: 512x512, full square (Play applies the mask).
    icon = Image.new("RGBA", (512, 512), "white")
    lg = logo(400)
    icon.alpha_composite(lg, ((512 - lg.width) // 2, (512 - lg.height) // 2))
    icon.save(g / "play-icon-512.png")

    # Google Play feature graphic: 1024x500, no alpha.
    fg = gradient(1024, 500).convert("RGBA")
    d = ImageDraw.Draw(fg)
    disc = Image.new("RGBA", (300, 300), (0, 0, 0, 0))
    ImageDraw.Draw(disc).ellipse([0, 0, 299, 299], fill="white")
    lg = logo(230)
    disc.alpha_composite(lg, ((300 - lg.width) // 2, (300 - lg.height) // 2))
    fg.alpha_composite(disc, (70, 100))
    d.text((420, 120), "6browser", font=ImageFont.truetype(FONT_BOLD, 96), fill="white")
    d.text((424, 250), "Fast. Clean. Private.", font=ImageFont.truetype(FONT, 46), fill=(205, 222, 255))
    d.text((424, 320), "A lightweight web browser", font=ImageFont.truetype(FONT, 34), fill=(170, 195, 240))
    fg.convert("RGB").save(g / "play-feature-graphic-1024x500.png")

    # Microsoft Store: 1:1 box art and 2:3 poster art (shown in the listing).
    for w, h, fname in [(2160, 2160, "msstore-box-art-2160x2160.png"),
                        (1440, 2160, "msstore-poster-art-1440x2160.png")]:
        art = gradient(w, h).convert("RGBA")
        d = ImageDraw.Draw(art)
        s = int(w * 0.5)
        disc = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        ImageDraw.Draw(disc).ellipse([0, 0, s - 1, s - 1], fill="white")
        lg = logo(int(s * 0.78))
        disc.alpha_composite(lg, ((s - lg.width) // 2, (s - lg.height) // 2))
        y = int(h * 0.2)
        art.alpha_composite(disc, ((w - s) // 2, y))
        centered(d, "6browser", y + s + int(h * 0.05), ImageFont.truetype(FONT_BOLD, int(w * 0.11)), w, "white")
        centered(d, "Fast. Clean. Private.", y + s + int(h * 0.05) + int(w * 0.16),
                 ImageFont.truetype(FONT, int(w * 0.05)), w, (205, 222, 255))
        art.convert("RGB").save(g / fname)

    # Microsoft Store 16:9 hero art (optional): 1920x1080, no text near edges.
    hero = gradient(1920, 1080).convert("RGBA")
    shot = Image.open(RAW / "windows-02-article.png").convert("RGB")
    shot = rounded(shot.resize((1200, 675), Image.LANCZOS), 16)
    paste_shadow(hero, shot, (620, 200), 16)
    d = ImageDraw.Draw(hero)
    lg = logo(150)
    hero.alpha_composite(lg, (120, 330))
    d.text((120, 500), "6browser", font=ImageFont.truetype(FONT_BOLD, 96), fill="white")
    d.text((124, 630), "Fast. Clean. Private.", font=ImageFont.truetype(FONT, 44), fill=(205, 222, 255))
    hero.convert("RGB").save(g / "msstore-hero-art-1920x1080.png")


def main():
    for sub in ("android", "windows"):
        (OUT / "screenshots" / sub).mkdir(parents=True, exist_ok=True)
    for name, (t, s) in ANDROID.items():
        android(name, t, s)
    for name, (t, s) in WINDOWS.items():
        windows(name, t, s)
    graphics()
    print("done")


if __name__ == "__main__":
    main()
