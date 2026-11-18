"""Cut the hand-drawn UI icons in concept/icons/ into square PNGs in assets/ui/.

Each source already has a transparent background: crop to the visible pixels,
pad to a square with a small margin, and scale to 256 px.
"""
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "concept", "icons")
DST = os.path.join(ROOT, "assets", "ui")
ICONS = {
    "star.webp": "icon_star.png",
    "sound.webp": "icon_sound.png",
    "music.webp": "icon_music.png",
    "globe.png": "icon_globe.png",
    "slash.webp": "icon_slash.png",
}
SIZE = 256
MARGIN = 0.06

for src, dst in ICONS.items():
    im = Image.open(os.path.join(SRC, src)).convert("RGBA")
    alpha = im.getchannel("A").point(lambda a: 255 if a > 8 else 0)
    im = im.crop(alpha.getbbox())
    side = round(max(im.size) * (1 + 2 * MARGIN))
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.alpha_composite(im, ((side - im.width) // 2, (side - im.height) // 2))
    sq = sq.resize((SIZE, SIZE), Image.LANCZOS)
    sq.save(os.path.join(DST, dst), optimize=True)
    print(dst, im.size)
