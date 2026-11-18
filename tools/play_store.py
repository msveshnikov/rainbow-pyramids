"""Google Play store graphics -> renders/play/.

python tools/play_store.py [--no-shots]
  icon_512.png            app icon (from assets/ui/icon.png, the owner's pyramid art)
  feature_1024x500.png    feature graphic: black stage, pyramid art, rainbow title (ru) / feature_en_1024x500.png
  ru_N_*.png / en_N_*.png phone screenshots 1080x1920, rendered by the game itself (-- --storeshots)
"""
import glob
import os
import shutil
import subprocess
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "renders", "play")
RAW = os.path.join(OUT, "raw")
GODOT = os.path.expanduser("~/OneDrive/Рабочий стол/Godot_v4.7.2-stable_win64.exe")
FONT = "C:/Windows/Fonts/seguibl.ttf"
RAINBOW = [(242, 20, 27), (255, 96, 0), (255, 217, 26), (140, 240, 30), (28, 182, 255), (58, 44, 255), (178, 53, 255)]


def shots():
    for f in glob.glob(os.path.join(RAW, "*.png")):
        os.remove(f)
    for lang in ("ru", "en"):
        subprocess.run([GODOT, "--path", ROOT, "--resolution", "1080x1920", "--quit-after", "9000",
                        "--", "--storeshots", "--lang", lang], check=False, capture_output=True)
    for f in sorted(glob.glob(os.path.join(RAW, "*.png"))):
        im = Image.open(f)
        assert im.size == (1080, 1920), (f, im.size)
        im.convert("RGB").save(os.path.join(OUT, os.path.basename(f)))
        print("shot", os.path.basename(f))


def icon():
    Image.open(os.path.join(ROOT, "assets", "ui", "icon.png")).convert("RGB").resize((512, 512), Image.LANCZOS) \
        .save(os.path.join(OUT, "icon_512.png"))


def rainbow_text(d, xy, s, size, stroke=6):
    f = ImageFont.truetype(FONT, size)
    x, y = xy
    k = 0
    for ch in s:
        col = (255, 255, 255) if ch == " " else RAINBOW[k % 7]
        d.text((x, y), ch, font=f, fill=col, stroke_width=stroke, stroke_fill=(10, 5, 20))
        x += d.textlength(ch, font=f)
        if ch != " ":
            k += 1


def feature(lang):
    w, h = 1024, 500
    bg = Image.new("RGB", (w, h), (0, 0, 0))
    # soft violet stage glow
    glow = Image.new("L", (w, h), 0)
    ImageDraw.Draw(glow).ellipse((-200, 80, 760, 620), fill=120)
    glow = glow.filter(ImageFilter.GaussianBlur(90))
    bg = Image.composite(Image.new("RGB", (w, h), (40, 18, 70)), bg, glow)
    art = Image.open(os.path.join(ROOT, "assets", "ui", "title.png")).convert("RGB")
    art = art.crop((170, 300, 870, 1060)).resize((424, 460), Image.LANCZOS)
    mask = Image.new("L", art.size, 0)
    ImageDraw.Draw(mask).ellipse((-60, -40, art.size[0] + 60, art.size[1] + 40), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(30))
    bg.paste(art, (20, 24), mask)
    d = ImageDraw.Draw(bg)
    if lang == "ru":
        rainbow_text(d, (440, 110), "Радужные", 76)
        rainbow_text(d, (440, 200), "пирамидки", 76)
        sub = "Головоломка-сортировка колец"
    else:
        rainbow_text(d, (450, 110), "Rainbow", 84)
        rainbow_text(d, (450, 205), "Pyramids", 84)
        sub = "A glossy ring-sorting puzzle"
    f = ImageFont.truetype(FONT, 30)
    d.text((446, 320), sub, font=f, fill=(235, 235, 255), stroke_width=3, stroke_fill=(10, 5, 20))
    f2 = ImageFont.truetype(FONT, 24)
    d.text((446, 372), "50 уровней · без рекламы" if lang == "ru" else "50 levels · no ads",
           font=f2, fill=(255, 210, 80), stroke_width=3, stroke_fill=(10, 5, 20))
    name = "feature_1024x500.png" if lang == "ru" else "feature_en_1024x500.png"
    bg.save(os.path.join(OUT, name))
    print("feature", name)


if __name__ == "__main__":
    os.makedirs(RAW, exist_ok=True)
    icon()
    feature("ru")
    feature("en")
    if "--no-shots" not in sys.argv:
        shots()
