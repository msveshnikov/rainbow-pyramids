extends SceneTree
## Packs concept/fonts/build/glossy_atlas.png + glossy.json (from tools/cut_font.py) into
## assets/fonts/glossy.res, a bitmap FontFile that scales to any font_size.
##   "$G" --headless --path . --script tools/build_font.gd

const SRC := "res://concept/fonts/build/"
const DST := "res://assets/fonts/glossy.res"
## em size in atlas pixels: cap height (84) is ~0.84 em, so the round letters match the old UI text in size
const EM := 100


func _init() -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SRC + "glossy.json"))
	var img := Image.load_from_file(ProjectSettings.globalize_path(SRC + "glossy_atlas.png"))
	img.convert(Image.FORMAT_RGBA8)
	var f := FontFile.new()
	f.fixed_size = EM
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	f.generate_mipmaps = true
	f.font_name = "Glossy Pyramids"
	var sz := Vector2i(EM, 0)
	f.set_cache_ascent(0, EM, meta.ascent)
	f.set_cache_descent(0, EM, meta.descent)
	f.set_texture_image(0, sz, 0, img)
	for key in meta.glyphs:
		var g: Array = meta.glyphs[key]
		var cp := int(key)
		f.set_glyph_advance(0, EM, cp, Vector2(g[6], 0))
		f.set_glyph_offset(0, sz, cp, Vector2(g[4], g[5]))
		f.set_glyph_size(0, sz, cp, Vector2(g[2], g[3]))
		f.set_glyph_uv_rect(0, sz, cp, Rect2(g[0], g[1], g[2], g[3]))
		f.set_glyph_texture_idx(0, sz, cp, 0)
	f.set_glyph_advance(0, EM, 32, Vector2(meta.space, 0))
	f.set_glyph_advance(0, EM, 0xA0, Vector2(meta.space, 0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/fonts"))
	var err := ResourceSaver.save(f, DST, ResourceSaver.FLAG_COMPRESS)
	print("saved %s: %d glyphs, err %d" % [DST, meta.glyphs.size(), err])
	quit(err)
