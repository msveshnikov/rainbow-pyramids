"""Cut my daughter's glossy letter sheets into a bitmap-font atlas.

Input  : concept/fonts/silver.png (Latin, digits, signs) and concept/fonts/silver_ru.png (Cyrillic),
         each a 10x10 grid of glossy letters on a transparent background.
Output : concept/fonts/build/glossy_atlas.png + glossy.json (metrics in atlas pixels),
         concept/fonts/build/preview.png (sample lines, to eyeball spacing and baselines).
Then   : tools/build_font.gd turns them into assets/fonts/glossy.res (a Godot FontFile).

    python tools/cut_font.py
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "concept", "fonts")
OUT = os.path.join(SRC, "build")

CAP = 84          # cap height in the atlas, px
PAD = 8           # transparent gutter around every glyph (mipmaps)
ATLAS_W = 1024

# cell contents, row by row; the Cyrillic sheet goes first so its punctuation wins
# (its row 7 has brackets next to real letters, so their baseline is measured, not guessed)
SHEETS = [
	("silver_ru.png", [
		"АБВГДЕЁЖЗИ", "ЙКЛМНОПРСТ", "УФХЦЧШЩЪЫЬ", "ЭЮЯ?!%&:.,",
		"абвгдеёжзи", "йклмнопрст", "уфхцчшщъыь", "эюя;()<>\\/",
		"[](){}<>\\/", "+-~=±#$€£¢"]),
	("silver.png", [
		"ABCDEFGHIJ", "KLMNOPQRST", "UVWXYZ?!%&", "abcdefghij",
		"klmnopqrst", "uvwxyz:;.,", "0123456789", "+-~=±#$€£¢",
		"[](){}<>\\/", "'\"*™@©®_|•"]),
]
# letters whose bottom is the baseline (no descenders, no floating marks)
FLAT = set("ABCDEFGHIKLMNOPRSTUVWXZ0123456789abcdehiklmnorstuvwxz"
		"АБВГЕЁЖЗИЙКЛМНОПРСТХЧШЪЫЬЭЮЯабвгеёжзийклмнопрстхчшъыьэюя?!%&")
CAP_REF = set("EHIKLMNTXZЕНИКМНТШЖ")
AXIS_REF = "<>+=-•"   # glyphs centred on the maths axis, for rows without letters


def bands(profile, th=2, merge=25):
	out = []
	start = None
	for i, v in enumerate(profile):
		if v > th and start is None:
			start = i
		elif v <= th and start is not None:
			out.append([start, i])
			start = None
	if start is not None:
		out.append([start, len(profile)])
	merged = []
	for b in out:
		if merged and b[0] - merged[-1][1] < merge:
			merged[-1][1] = b[1]
		else:
			merged.append(b)
	return merged


def cut_sheet(name, rows):
	im = Image.open(os.path.join(SRC, name)).convert("RGBA")
	arr = np.array(im)
	alpha = arr[..., 3]
	solid = alpha > 100
	rb = bands(solid.sum(1))
	cb = bands(solid.sum(0))
	if len(rb) != len(rows) or len(cb) != 10:
		sys.exit(f"{name}: expected {len(rows)}x10 grid, found {len(rb)}x{len(cb)}")
	glyphs = []
	for r, chars in enumerate(rows):
		y0, y1 = rb[r]
		for c, ch in enumerate(chars):
			x0, x1 = cb[c]
			a = alpha[y0:y1, x0:x1] > 8
			ys, xs = np.nonzero(a)
			if len(ys) == 0:
				sys.exit(f"{name}: empty cell for {ch!r}")
			top, bot = y0 + ys.min(), y0 + ys.max() + 1
			left, right = x0 + xs.min(), x0 + xs.max() + 1
			glyphs.append(dict(ch=ch, row=r, top=top, bot=bot, left=left, right=right,
					img=im.crop((left, top, right, bot))))
	# baselines: median bottom of flat letters in the row
	base = {}
	for r in range(len(rows)):
		bots = [g["bot"] for g in glyphs if g["row"] == r and g["ch"] in FLAT]
		if len(bots) >= 3:
			base[r] = float(np.median(bots))
	cap = float(np.median([g["bot"] - g["top"] for g in glyphs if g["ch"] in CAP_REF]))
	return glyphs, base, cap


def clean(img):
	"""Zero the junk colour under transparent pixels and bleed glyph colour outwards,
	so bilinear filtering and mipmaps never pull dark or stray colours into the edges."""
	a = np.array(img).astype(np.float32)
	alpha = a[..., 3:4] / 255.0
	alpha[alpha < 8 / 255.0] = 0.0
	rgb = a[..., :3]
	pm = rgb * alpha
	fill_rgb = np.zeros_like(rgb)
	have = np.zeros(alpha.shape, np.float32)
	for radius in (1, 2, 4, 8, 16):
		pmi = Image.fromarray(np.clip(pm, 0, 255).astype(np.uint8))
		ai = Image.fromarray((alpha[..., 0] * 255).astype(np.uint8))
		bp = np.array(pmi.filter(ImageFilter.BoxBlur(radius))).astype(np.float32)
		ba = np.array(ai.filter(ImageFilter.BoxBlur(radius))).astype(np.float32)[..., None] / 255.0
		ok = (ba > 0.01) & (have < 0.5)
		fill_rgb = np.where(ok, bp / np.maximum(ba, 1e-4), fill_rgb)
		have = np.maximum(have, ok.astype(np.float32))
	out_rgb = np.where(alpha > 0.6, rgb, np.where(alpha > 0, rgb * alpha + fill_rgb * (1 - alpha), fill_rgb))
	out = np.concatenate([np.clip(out_rgb, 0, 255), alpha * 255], axis=2).astype(np.uint8)
	return Image.fromarray(out, "RGBA")


def scaled(img, s, sx=None):
	w = max(1, round(img.width * (sx if sx else s)))
	h = max(1, round(img.height * s))
	return img.convert("RGBa").resize((w, h), Image.LANCZOS).convert("RGBA")


def main():
	os.makedirs(OUT, exist_ok=True)
	table = {}   # ch -> dict(img, oy) in atlas scale, oy = top relative to baseline
	axis = None  # height of the maths axis above the baseline, in CAP units
	sheets = [cut_sheet(n, rows) for n, rows in SHEETS]
	# the maths axis, measured where '<' shares a row with letters (Cyrillic row 7)
	for glyphs, base, cap in sheets:
		for g in glyphs:
			if g["ch"] == "<" and g["row"] in base:
				axis = (base[g["row"]] - (g["top"] + g["bot"]) * 0.5) / cap
				break
		if axis is not None:
			break
	print(f"maths axis {axis:.3f} cap")
	for (name, _), (glyphs, base, cap) in zip(SHEETS, sheets):
		s = CAP / cap
		print(f"{name}: cap {cap:.0f}px -> scale {s:.3f}, measured baselines in rows {sorted(base)}")
		for r in range(10):
			if r in base:
				continue
			ref = next((g for k in AXIS_REF for g in glyphs if g["row"] == r and g["ch"] == k), None)
			base[r] = (ref["top"] + ref["bot"]) * 0.5 + axis * cap
		for g in glyphs:
			if g["ch"] in table:
				continue
			table[g["ch"]] = dict(img=clean(scaled(g["img"], s)), oy=(g["top"] - base[g["row"]]) * s)

	# the Latin template has g p q y j sitting on the baseline, which reads as capitals ("jumPs");
	# drop them so the bowl lines up with the x-height and the tail hangs below the line
	for ch in "gpqy":
		table[ch]["oy"] = table["o"]["oy"]
	table["j"]["oy"] = table["i"]["oy"]

	# derived glyphs
	dot = table["•"]
	table["·"] = dict(img=scaled(dot["img"], 0.75), oy=-axis * CAP - dot["img"].height * 0.75 * 0.5)
	dash = table["-"]
	for ch, k in (("–", 1.35), ("—", 1.9)):
		table[ch] = dict(img=scaled(dash["img"], 1.0, k), oy=dash["oy"])

	# pack (shelf packer, tallest first)
	order = sorted(table, key=lambda ch: -table[ch]["img"].height)
	x = y = PAD
	shelf = 0
	for ch in order:
		g = table[ch]
		w, h = g["img"].size
		if x + w + PAD > ATLAS_W:
			x = PAD
			y += shelf + PAD
			shelf = 0
		g["x"], g["y"] = x, y
		x += w + PAD
		shelf = max(shelf, h)
	atlas_h = (y + shelf + PAD + 3) // 4 * 4
	atlas = Image.new("RGBA", (ATLAS_W, atlas_h), (0, 0, 0, 0))
	for ch, g in table.items():
		atlas.paste(g["img"], (g["x"], g["y"]))
	atlas.save(os.path.join(OUT, "glossy_atlas.png"), optimize=True)

	track = round(CAP * 0.05)
	ascent = round(max(-g["oy"] for g in table.values()))
	descent = round(max(g["oy"] + g["img"].height for g in table.values()))
	meta = dict(cap=CAP, ascent=ascent, descent=descent, space=round(CAP * 0.36), glyphs={})
	for ch, g in table.items():
		w, h = g["img"].size
		meta["glyphs"][str(ord(ch))] = [g["x"], g["y"], w, h, 0, round(g["oy"]), w + track]
	with open(os.path.join(OUT, "glossy.json"), "w", encoding="utf-8") as f:
		json.dump(meta, f)
	print(f"{len(table)} glyphs, atlas {ATLAS_W}x{atlas_h}, ascent {ascent}, descent {descent}")
	preview(atlas, meta)


def preview(atlas, meta, lines=(
		"Радужные пирамидки", "Уровень 12 · Ходы: 34", "Отлично! Идеально! Ещё раз",
		"Съешь же ещё этих мягких французских булок, да выпей чаю",
		"Rainbow Pyramids — Level 7", "The quick brown fox jumps over the lazy dog?")):
	lh = meta["ascent"] + meta["descent"] + 10
	W = 2400
	img = Image.new("RGBA", (W, lh * len(lines) + 20), (28, 40, 80, 255))
	for i, text in enumerate(lines):
		pen = 20
		base = 10 + i * lh + meta["ascent"]
		for ch in text:
			if ch == " ":
				pen += meta["space"]
				continue
			x, y, w, h, ox, oy, adv = meta["glyphs"][str(ord(ch))]
			img.alpha_composite(atlas.crop((x, y, x + w, y + h)), (pen + ox, base + oy))
			pen += adv
	img.save(os.path.join(OUT, "preview.png"))


if __name__ == "__main__":
	main()
