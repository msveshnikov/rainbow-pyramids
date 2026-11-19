class_name UiKit
extends RefCounted
## UI built in code: buttons, icon buttons, stars, labels. No .tscn needed.


static func label(text: String, size := 40, color := Color.WHITE, outline := 10) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", outline)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _box(bg: Color, border: Color, radius: int, bw := 4, glow := 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	if glow > 0.0:
		s.shadow_color = Color(border, glow)
		s.shadow_size = 14
	s.content_margin_left = 24
	s.content_margin_right = 24
	return s


static func style_button(b: Button, color: Color, radius: int) -> void:
	b.add_theme_stylebox_override("normal", _box(color.darkened(0.6), color, radius, 4, 0.45))
	b.add_theme_stylebox_override("hover", _box(color.darkened(0.42), color.lightened(0.2), radius, 4, 0.6))
	b.add_theme_stylebox_override("pressed", _box(color.darkened(0.25), color.lightened(0.35), radius, 4, 0.8))
	b.add_theme_stylebox_override("disabled", _box(Color(0.08, 0.08, 0.1), Color(0.25, 0.25, 0.3), radius, 3))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.45, 0.5))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	b.add_theme_constant_override("outline_size", 8)


static func button(text: String, color: Color, size := Vector2(380, 104), font := 44) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.add_theme_font_size_override("font_size", font)
	style_button(b, color, int(size.y * 0.5))
	juice(b)
	return b


## Squash on press, elastic pop on release, click sound.
static func juice(b: Control) -> void:
	b.resized.connect(func(): b.pivot_offset = b.size * 0.5)
	if b is BaseButton:
		var bb: BaseButton = b
		bb.button_down.connect(func():
			var t := b.create_tween()
			t.tween_property(b, "scale", Vector2(0.88, 0.88), 0.06))
		bb.button_up.connect(func():
			var t := b.create_tween()
			t.tween_property(b, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT))
		bb.pressed.connect(func(): Sfx.play("click"))


## Pops a control in from zero size.
static func pop_in(c: Control, delay := 0.0, dur := 0.45) -> void:
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(0.01, 0.01)
	var t := c.create_tween()
	t.tween_interval(delay)
	t.tween_callback(func(): c.pivot_offset = c.size * 0.5)
	t.tween_property(c, "scale", Vector2.ONE, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func rainbow(i: int) -> Color:
	return Game.COLORS[i % Game.COLORS.size()]


# ------------------------------------------------------------- icon button

## Hand-drawn glossy icons by the owner's daughter (cut by tools/cut_icons.py).
const ICON_TEX := {
	"sound": preload("res://assets/ui/icon_sound.png"),
	"music": preload("res://assets/ui/icon_music.png"),
	"lang": preload("res://assets/ui/icon_globe.png"),
}
const SLASH_TEX := preload("res://assets/ui/icon_slash.png")
const STAR_TEX := preload("res://assets/ui/icon_star.png")


class IconButton extends Button:
	var kind := "undo"
	var off := false
	var tint := Color.WHITE
	var caption := ""

	func _init(k: String, color: Color, d := 108.0) -> void:
		kind = k
		tint = color
		custom_minimum_size = Vector2(d, d)
		# stay a circle: never let a row or column stretch it
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UiKit.style_button(self, color, int(d * 0.5))
		UiKit.juice(self)

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.24
		var w := maxf(4.0, r * 0.22)
		var col := Color(1, 1, 1, 0.45) if disabled else Color.WHITE
		if UiKit.ICON_TEX.has(kind):
			_draw_picture(c)
			return
		match kind:
			"undo":
				draw_arc(c + Vector2(r * 0.15, 0), r, -PI * 0.75, PI * 0.6, 24, col, w, true)
				var a := c + Vector2(r * 0.15, 0) + Vector2(cos(-PI * 0.75), sin(-PI * 0.75)) * r
				draw_colored_polygon(PackedVector2Array([a + Vector2(-r * 0.55, -r * 0.05), a + Vector2(r * 0.25, -r * 0.45), a + Vector2(r * 0.15, r * 0.45)]), col)
			"restart":
				draw_arc(c, r, -PI * 0.35, PI * 1.45, 28, col, w, true)
				var a := c + Vector2(cos(-PI * 0.35), sin(-PI * 0.35)) * r
				draw_colored_polygon(PackedVector2Array([a + Vector2(-r * 0.45, -r * 0.3), a + Vector2(r * 0.45, -r * 0.35), a + Vector2(0.1 * r, r * 0.45)]), col)
			"hint":
				draw_circle(c + Vector2(0, -r * 0.25), r * 0.72, col)
				draw_rect(Rect2(c + Vector2(-r * 0.36, r * 0.35), Vector2(r * 0.72, r * 0.5)), col)
				draw_line(c + Vector2(-r * 0.3, r * 0.62), c + Vector2(r * 0.3, r * 0.62), Color(0, 0, 0, 0.6), 3)
				draw_rect(Rect2(c + Vector2(-r * 0.22, r * 0.9), Vector2(r * 0.44, r * 0.22)), col)
				draw_arc(c + Vector2(0, -r * 0.25), r * 0.4, PI * 1.1, PI * 1.6, 8, Color(0, 0, 0, 0.35), 3)
			"home":
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 1.05), c + Vector2(r * 1.1, -r * 0.05), c + Vector2(-r * 1.1, -r * 0.05)]), col)
				draw_rect(Rect2(c + Vector2(-r * 0.75, -r * 0.1), Vector2(r * 1.5, r * 1.0)), col)
				draw_rect(Rect2(c + Vector2(-r * 0.22, r * 0.3), Vector2(r * 0.44, r * 0.6)), tint.darkened(0.6))
			"levels":
				for yy in 3:
					for xx in 3:
						draw_rect(Rect2(c + Vector2((xx - 1.5) * r * 0.72 + r * 0.06, (yy - 1.5) * r * 0.72 + r * 0.06), Vector2(r * 0.55, r * 0.55)), col)
			"sound", "music":
				if kind == "sound":
					draw_colored_polygon(PackedVector2Array([c + Vector2(-r, -r * 0.35), c + Vector2(-r * 0.45, -r * 0.35), c + Vector2(r * 0.1, -r * 0.9), c + Vector2(r * 0.1, r * 0.9), c + Vector2(-r * 0.45, r * 0.35), c + Vector2(-r, r * 0.35)]), col)
					if not off:
						draw_arc(c + Vector2(r * 0.1, 0), r * 0.5, -PI * 0.3, PI * 0.3, 10, col, w * 0.7, true)
						draw_arc(c + Vector2(r * 0.1, 0), r * 0.95, -PI * 0.3, PI * 0.3, 12, col, w * 0.7, true)
				else:
					draw_circle(c + Vector2(-r * 0.45, r * 0.6), r * 0.33, col)
					draw_circle(c + Vector2(r * 0.55, r * 0.4), r * 0.33, col)
					draw_line(c + Vector2(-r * 0.15, r * 0.6), c + Vector2(-r * 0.15, -r * 0.8), col, w * 0.7)
					draw_line(c + Vector2(r * 0.85, r * 0.4), c + Vector2(r * 0.85, -r * 1.0), col, w * 0.7)
					draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.15, -r * 0.8), c + Vector2(r * 0.85, -r * 1.0), c + Vector2(r * 0.85, -r * 0.6), c + Vector2(-r * 0.15, -r * 0.4)]), col)
				if off:
					draw_line(c + Vector2(-r * 1.1, -r * 1.1), c + Vector2(r * 1.1, r * 1.1), Color(1, 0.3, 0.3), w)

	func _draw_picture(c: Vector2) -> void:
		var d := minf(size.x, size.y)
		var k := 0.56 if caption != "" else 0.66
		var rect := Rect2(c - Vector2(d, d) * k * 0.5, Vector2(d, d) * k)
		if caption != "":
			rect.position.y -= d * 0.1
		var mod := Color(0.55, 0.55, 0.6, 0.75) if off else Color.WHITE
		draw_texture_rect(UiKit.ICON_TEX[kind], rect, false, mod)
		if off:
			draw_texture_rect(UiKit.SLASH_TEX, rect.grow(d * 0.04), false)
		if caption != "":
			var font := get_theme_default_font()
			var fs := int(d * 0.26)
			var tw := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var pos := Vector2(c.x - tw * 0.5, c.y + d * 0.38)
			draw_string_outline(font, pos, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.85))
			draw_string(font, pos, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


# ------------------------------------------------------------- star

class Star extends Control:
	var filled := true
	var col := Color(1, 0.8, 0.15)

	func _init(d := 64.0, f := true) -> void:
		custom_minimum_size = Vector2(d, d)
		filled = f
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		# the glossy star my daughter drew; an empty slot is the same star, dark
		var mod := Color.WHITE if filled else Color(0.2, 0.18, 0.32, 0.92)
		var d := minf(size.x, size.y)
		draw_texture_rect(UiKit.STAR_TEX, Rect2((size - Vector2(d, d)) * 0.5, Vector2(d, d)), false, mod)


static func star_row(n: int, d := 30.0) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 2)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in 3:
		h.add_child(Star.new(d, k < n))
	return h
