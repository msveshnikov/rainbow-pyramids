extends Node3D
## Game flow: title -> level select -> play -> win. UI is built in code.

var board: Board
var cam: Camera3D
var ui: CanvasLayer
var screen: Control           # current screen root
var state := ""
var level_idx := 0
var level: Dictionary
var solution: Array = []      # Vector2i moves from levels.json
var history: Array = []       # Vector2i moves made by the player
var hints_used := 0
var won := false
var tutorial_step := 0

var lbl_level: Label
var lbl_moves: Label
var toast: Label
var btn_undo: Button
var btn_hint: Button
var _toast_tw: Tween
var _log: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_setup_world()
	ui = CanvasLayer.new()
	add_child(ui)
	get_viewport().size_changed.connect(_on_resize)
	if not (OS.has_feature("web") or OS.has_feature("mobile")):
		get_viewport().msaa_3d = Viewport.MSAA_4X
	if Game.has_arg("--autotest"):
		_autotest()
	elif Game.has_arg("--storeshots"):
		_storeshots()
	elif Game.has_arg("--swatch"):
		_swatch()
	elif Game.has_arg("--playtest"):
		_playtest(int(Game.arg_value("--playtest", "4")) - 1)
	elif Game.has_arg("--level"):
		start_level(int(Game.arg_value("--level", "1")) - 1)
	else:
		show_title()


func _setup_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.6, 0.78)
	env.ambient_light_energy = 0.38
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.1
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52, -32, 0)
	key.light_energy = 0.78
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-18, 150, 0)
	rim.light_energy = 0.5
	rim.light_color = Color(0.75, 0.82, 1.0)
	add_child(rim)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, 40, 0)
	fill.light_energy = 0.22
	fill.light_color = Color(1.0, 0.85, 0.9)
	add_child(fill)
	cam = Camera3D.new()
	cam.fov = 32
	add_child(cam)
	cam.current = true
	board = Board.new()
	board.cam = cam
	add_child(board)
	board.moved.connect(_on_moved)
	board.rejected.connect(_on_rejected)
	board.peg_completed.connect(_on_peg_completed)
	board.won.connect(_on_won)


# ================================================================ camera

func fit_camera(points: Array, pitch_deg: float, top_frac: float, bottom_frac: float, side_frac := 0.04) -> void:
	var vs := get_viewport().get_visible_rect().size
	var basis := Basis.from_euler(Vector3(deg_to_rad(pitch_deg), 0, 0))
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p in points:
		lo = lo.min(p)
		hi = hi.max(p)
	var target := (lo + hi) * 0.5
	var rect := Rect2(vs.x * side_frac, vs.y * top_frac, vs.x * (1.0 - 2.0 * side_frac), vs.y * (1.0 - top_frac - bottom_frac))
	var d := 10.0
	for pass_i in 3:
		var a := 1.0
		var b := 120.0
		for it in 24:
			d = (a + b) * 0.5
			cam.global_transform = Transform3D(basis, target + basis.z * d)
			if _points_inside(points, rect):
				b = d
			else:
				a = d
		d = b
		cam.global_transform = Transform3D(basis, target + basis.z * d)
		var sb := _screen_bounds(points)
		var off := rect.get_center() - sb.get_center()
		var wpp := 2.0 * d * tan(deg_to_rad(cam.fov) * 0.5) / vs.y
		target += -basis.x * off.x * wpp + basis.y * off.y * wpp
	cam.global_transform = Transform3D(basis, target + basis.z * d)


func _points_inside(points: Array, rect: Rect2) -> bool:
	for p in points:
		if cam.is_position_behind(p):
			return false
		if not rect.has_point(cam.unproject_position(p)):
			return false
	return true


func _screen_bounds(points: Array) -> Rect2:
	var r := Rect2(cam.unproject_position(points[0]), Vector2.ZERO)
	for p in points:
		r = r.expand(cam.unproject_position(p))
	return r


func _board_points() -> Array:
	var pts: Array = []
	for p in board.positions:
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				pts.append(p + Vector3(sx * board.base_r, 0, sz * board.base_r))
			pts.append(p + Vector3(sx * board.base_r * 0.9, board.lift_y + 0.35, 0))
	return pts


func _fit_for_state() -> void:
	var vs := get_viewport().get_visible_rect().size
	var portrait := vs.y > vs.x
	if state == "title":
		fit_camera(board.showcase_points(), -14, 0.27 if portrait else 0.24, 0.36 if portrait else 0.44, 0.06 if portrait else 0.3)
	elif state == "play" or state == "win":
		var pitch := -42.0 if portrait else -40.0
		fit_camera(_board_points(), pitch, 0.15 if portrait else 0.16, 0.16 if portrait else 0.17, 0.035 if portrait else 0.1)


func _on_resize() -> void:
	if state == "play" or state == "win":
		board.relayout()
	_fit_for_state()


# ================================================================ screens

func _new_screen() -> Control:
	if screen:
		screen.queue_free()
	screen = Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(screen)
	toast = null
	return screen


func _place(c: Control, preset: Control.LayoutPreset, margin := 24) -> void:
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, margin)


func show_title() -> void:
	state = "title"
	won = false
	board.build_showcase()
	_fit_for_state()
	var s := _new_screen()
	# the logo my daughter painted ("Rainbow pyramids"), floating gently; tap it for a jiggle
	var vs := get_viewport().get_visible_rect().size
	var tex: Texture2D = load("res://assets/ui/logo.png")
	var aspect := float(tex.get_width()) / tex.get_height()
	var lw := minf(vs.x * 0.88, vs.y * 0.235 * aspect)
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", -6)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var logo := TextureRect.new()
	logo.texture = tex
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(lw, lw / aspect)
	logo.mouse_filter = Control.MOUSE_FILTER_STOP
	logo.set_meta("logo", true)
	logo.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			Sfx.play("pop", randf_range(0.9, 1.3))
			logo.set_meta("jiggle", 1.0))
	head.add_child(logo)
	if Game.save.lang == "ru":
		head.add_child(UiKit.label(Game.t("title1") + " " + Game.t("title2"), 34, Color(1, 1, 1, 0.85), 8))
	s.add_child(head)
	_place(head, Control.PRESET_CENTER_TOP, int(vs.y * 0.025))
	UiKit.pop_in(logo, 0.1, 0.7)
	# buttons
	var bx := VBoxContainer.new()
	bx.add_theme_constant_override("separation", 22)
	bx.alignment = BoxContainer.ALIGNMENT_CENTER
	var unlocked := int(Game.save.unlocked)
	var play := UiKit.button(Game.t("play") + "  ·  " + str(unlocked), Color("8cf01e"), Vector2(420, 116), 50)
	play.pressed.connect(func():
		Sfx.start_music()
		start_level(unlocked - 1))
	var lv := UiKit.button(Game.t("levels"), Color("1cb6ff"), Vector2(420, 100), 44)
	lv.pressed.connect(func():
		Sfx.start_music()
		show_levels())
	bx.add_child(play)
	bx.add_child(lv)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 26)
	row.add_child(_sound_button(Color("b235ff")))
	row.add_child(_music_button(Color("ff7d12")))
	var lang := UiKit.button(Game.save.lang.to_upper(), Color("ffc41c"), Vector2(96, 96), 36)
	lang.pressed.connect(func():
		Game.save.lang = "en" if Game.save.lang == "ru" else "ru"
		Game.write_save()
		show_title())
	row.add_child(lang)
	bx.add_child(row)
	var stars := HBoxContainer.new()
	stars.alignment = BoxContainer.ALIGNMENT_CENTER
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stars.add_child(UiKit.Star.new(40, true))
	stars.add_child(UiKit.label(" %d / %d" % [Game.total_stars(), Game.level_count() * 3], 32, Color(1, 0.85, 0.3), 8))
	bx.add_child(stars)
	s.add_child(bx)
	_place(bx, Control.PRESET_CENTER_BOTTOM, 92)
	var foot := VBoxContainer.new()
	foot.add_theme_constant_override("separation", 0)
	var pv := LinkButton.new()
	pv.text = Game.t("privacy")
	pv.underline = LinkButton.UNDERLINE_MODE_ALWAYS
	pv.add_theme_font_size_override("font_size", 20)
	pv.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0, 0.8))
	pv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pv.pressed.connect(func(): OS.shell_open("https://maxims.top/pyramids/privacy.html"))
	foot.add_child(pv)
	foot.add_child(UiKit.label(Game.t("credits"), 18, Color(1, 1, 1, 0.45), 4))
	s.add_child(foot)
	_place(foot, Control.PRESET_CENTER_BOTTOM, 10)
	UiKit.pop_in(play, 0.5)
	UiKit.pop_in(lv, 0.62)
	UiKit.pop_in(row, 0.74)


func _sound_button(c: Color) -> Button:
	var b := UiKit.IconButton.new("sound", c, 96)
	b.off = not Game.save.sound
	b.pressed.connect(func():
		Game.save.sound = not Game.save.sound
		b.off = not Game.save.sound
		b.queue_redraw()
		Game.write_save()
		Sfx.play("toggle"))
	return b


func _music_button(c: Color) -> Button:
	var b := UiKit.IconButton.new("music", c, 96)
	b.off = not Game.save.music
	b.pressed.connect(func():
		Game.save.music = not Game.save.music
		b.off = not Game.save.music
		b.queue_redraw()
		Game.write_save()
		Sfx.start_music())
	return b


func show_levels() -> void:
	state = "levels"
	if not board.showcase:
		board.build_showcase()
		state = "title"
		_fit_for_state()
		state = "levels"
	var s := _new_screen()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	s.add_child(dim)
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.offset_top = 30
	vb.offset_bottom = -30
	vb.offset_left = 20
	vb.offset_right = -20
	vb.add_theme_constant_override("separation", 16)
	s.add_child(vb)
	var head := HBoxContainer.new()
	var back := UiKit.IconButton.new("home", Color("ff2a1c"), 96)
	back.pressed.connect(show_title)
	head.add_child(back)
	var title := UiKit.label(Game.t("levels"), 60, Color("1cb6ff"), 12)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var st := HBoxContainer.new()
	st.add_child(UiKit.Star.new(40, true))
	st.add_child(UiKit.label(str(Game.total_stars()), 34, Color(1, 0.85, 0.3), 8))
	st.custom_minimum_size.x = 96
	head.add_child(st)
	vb.add_child(head)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(center)
	var vs := get_viewport().get_visible_rect().size
	var grid := GridContainer.new()
	grid.columns = 5 if vs.x < vs.y else 10
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	center.add_child(grid)
	var unlocked := int(Game.save.unlocked)
	for i in Game.level_count():
		var lvd: Dictionary = Game.get_level(i)
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		var col: Color = Game.COLORS[(int(lvd.colors) + i) % 7]
		var b := UiKit.button(str(i + 1), col, Vector2(112, 104), 42)
		b.disabled = i + 1 > unlocked
		var idx := i
		b.pressed.connect(func(): start_level(idx))
		cell.add_child(b)
		cell.add_child(UiKit.star_row(Game.stars_for(i + 1), 30))
		grid.add_child(cell)
		UiKit.pop_in(b, 0.02 * i, 0.3)
	await get_tree().process_frame
	# scroll so the newest level is visible
	var target := clampi(unlocked - 1, 0, Game.level_count() - 1)
	if target < grid.get_child_count():
		sc.ensure_control_visible(grid.get_child(target))


# ================================================================ playing

func start_level(idx: int) -> void:
	idx = clampi(idx, 0, Game.level_count() - 1)
	level_idx = idx
	level = Game.get_level(idx)
	solution = []
	for m in level.solution:
		solution.append(Vector2i(int(m[0]), int(m[1])))
	history.clear()
	hints_used = 0
	won = false
	state = "play"
	board.build(Puzzle.from_level(level))
	_fit_for_state()
	_build_hud()
	tutorial_step = 0
	if idx == 0:
		show_toast(Game.t("tut1"), 0)
	elif idx == 1:
		show_toast(Game.t("tut2"), 5.0)
	elif idx == 2:
		show_toast(Game.t("goal"), 5.0)


func _build_hud() -> void:
	var s := _new_screen()
	var top := VBoxContainer.new()
	top.add_theme_constant_override("separation", -4)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_level = UiKit.label(Game.t("level") % (level_idx + 1), 54, Game.COLORS[level_idx % 7].lightened(0.25), 12)
	lbl_moves = UiKit.label("", 32, Color(1, 1, 1, 0.9), 8)
	top.add_child(lbl_level)
	top.add_child(lbl_moves)
	s.add_child(top)
	_place(top, Control.PRESET_CENTER_TOP, 26)
	var home := UiKit.IconButton.new("home", Color("ff2a1c"), 92)
	home.pressed.connect(show_title)
	s.add_child(home)
	_place(home, Control.PRESET_TOP_LEFT, 22)
	var lv := UiKit.IconButton.new("levels", Color("1cb6ff"), 92)
	lv.pressed.connect(show_levels)
	s.add_child(lv)
	_place(lv, Control.PRESET_TOP_RIGHT, 22)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 34)
	btn_undo = UiKit.IconButton.new("undo", Color("ffc41c"), 118)
	btn_undo.pressed.connect(undo)
	var restart := UiKit.IconButton.new("restart", Color("ff7d12"), 118)
	restart.pressed.connect(func():
		Sfx.play("restart")
		start_level(level_idx))
	btn_hint = UiKit.IconButton.new("hint", Color("8cf01e"), 118)
	btn_hint.pressed.connect(hint)
	bottom.add_child(btn_undo)
	bottom.add_child(restart)
	bottom.add_child(btn_hint)
	bottom.add_child(_sound_button(Color("b235ff")))
	s.add_child(bottom)
	_place(bottom, Control.PRESET_CENTER_BOTTOM, 40)
	toast = UiKit.label("", 30, Color.WHITE, 10)
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s.add_child(toast)
	toast.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	toast.offset_left = 20
	toast.offset_right = -20
	toast.offset_top = -380
	toast.offset_bottom = -190
	toast.modulate.a = 0.0
	_update_hud()
	UiKit.pop_in(top, 0.1)


func _update_hud() -> void:
	if lbl_moves == null:
		return
	lbl_moves.text = (Game.t("moves") % history.size()) + "   ·   " + (Game.t("par") % int(level.par))
	if btn_undo:
		btn_undo.disabled = history.is_empty() or won


func show_toast(text: String, secs := 2.2) -> void:
	if toast == null or not is_instance_valid(toast):
		return
	toast.text = text
	if _toast_tw:
		_toast_tw.kill()
	toast.pivot_offset = toast.size * 0.5
	toast.scale = Vector2(0.8, 0.8)
	_toast_tw = create_tween()
	_toast_tw.tween_property(toast, "modulate:a", 1.0, 0.15)
	_toast_tw.parallel().tween_property(toast, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if secs > 0:
		_toast_tw.tween_interval(secs)
		_toast_tw.tween_property(toast, "modulate:a", 0.0, 0.4)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		press_at(event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		if state == "play":
			if event.keycode == KEY_Z or event.keycode == KEY_BACKSPACE:
				undo()
			elif event.keycode == KEY_H:
				hint()
			elif event.keycode == KEY_R:
				start_level(level_idx)
			elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
				var i: int = event.keycode - KEY_1
				if i < board.positions.size():
					board.tap(i)


func press_at(pos: Vector2) -> void:
	if state == "title":
		board.showcase_poke(pos)
		return
	if state != "play" or won:
		return
	var i := board.pick(pos)
	if i >= 0:
		board.tap(i)
	elif board.selected >= 0 and not board.busy:
		board.deselect()


func _on_moved(a: int, b: int, record: bool) -> void:
	if record:
		history.append(Vector2i(a, b))
		if level_idx == 0 and tutorial_step == 0:
			tutorial_step = 1
			show_toast(Game.t("tut2"), 4.0)
	_update_hud()
	await get_tree().create_timer(0.6).timeout
	if state == "play" and not won and board.puzzle and not board.puzzle.is_won() and not board.puzzle.has_any_move():
		show_toast(Game.t("stuck"), 3.0)
		_pulse(btn_undo)


func _on_rejected(_peg: int, why: String) -> void:
	match why:
		"color":
			show_toast(Game.t("bad_color"))
		"size":
			show_toast(Game.t("bad_size"))
		"full":
			show_toast(Game.t("bad_full"))


func _on_peg_completed(peg: int) -> void:
	if board.puzzle.is_won():
		return
	show_toast(Game.t("pyramid"), 1.2)
	if toast:
		toast.add_theme_color_override("font_color", board.color_of(board.puzzle.pegs[peg][0] / 10).lightened(0.3))
		get_tree().create_timer(1.6).timeout.connect(func():
			if is_instance_valid(toast):
				toast.add_theme_color_override("font_color", Color.WHITE))


func undo() -> void:
	if history.is_empty() or board.busy or won or state != "play":
		return
	if board.selected >= 0:
		board.deselect()
		await get_tree().create_timer(0.12).timeout
	var m: Vector2i = history.pop_back()
	Sfx.play("undo")
	board.do_move(m.y, m.x, false)
	_update_hud()


func hint() -> void:
	if board.busy or won or state != "play":
		return
	hints_used += 1
	var m := Vector2i(-1, -1)
	var on_path := history.size() < solution.size()
	if on_path:
		for k in history.size():
			if history[k] != solution[k]:
				on_path = false
				break
	if on_path:
		m = solution[history.size()]
	else:
		var sol := board.puzzle.solve(3000, 4.0)
		if sol.is_empty():
			sol = board.puzzle.solve(3000, 9.0)
		if not sol.is_empty():
			m = sol[0]
	if m.x < 0:
		show_toast(Game.t("hint_undo"), 2.5)
		_pulse(btn_undo)
		Sfx.play("error", 0.8, -6)
		return
	board.show_hint(m.x, m.y)


func _pulse(c: Control) -> void:
	if c == null or not is_instance_valid(c):
		return
	c.pivot_offset = c.size * 0.5
	var t := c.create_tween()
	for k in 3:
		t.tween_property(c, "scale", Vector2(1.18, 1.18), 0.12)
		t.tween_property(c, "scale", Vector2.ONE, 0.18)


func _on_won() -> void:
	if won:
		return
	won = true
	state = "win"
	var moves := history.size()
	var stars := Game.stars_from(moves, int(level.par))
	var prev_best := Game.best_for(int(level.id))
	var new_best := Game.record_win(int(level.id), moves, stars)
	_update_hud()
	await get_tree().create_timer(0.9).timeout
	if state != "win":
		return
	_show_win(moves, stars, prev_best, new_best)


func _show_win(moves: int, stars: int, prev_best: int, new_best: bool) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(dim)
	create_tween().tween_property(dim, "color:a", 0.55, 0.4)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.06, 0.12, 0.94)
	sb.border_color = Game.COLORS[level_idx % 7]
	sb.set_border_width_all(5)
	sb.set_corner_radius_all(40)
	sb.shadow_color = Color(sb.border_color, 0.5)
	sb.shadow_size = 24
	sb.content_margin_left = 40
	sb.content_margin_right = 40
	sb.content_margin_top = 30
	sb.content_margin_bottom = 34
	panel.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vb)
	var word := Game.t("perfect") if stars == 3 else (Game.t("great") if stars == 2 else Game.t("done"))
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 0)
	var k := 0
	for ch in word:
		var l := UiKit.label(ch, 72, UiKit.rainbow(k), 14)
		hb.add_child(l)
		l.set_meta("wave", k)
		k += 1
	vb.add_child(hb)
	var srow := HBoxContainer.new()
	srow.alignment = BoxContainer.ALIGNMENT_CENTER
	srow.add_theme_constant_override("separation", 10)
	var star_nodes: Array = []
	for s in 3:
		var st := UiKit.Star.new(116 if s == 1 else 96, s < stars)
		srow.add_child(st)
		star_nodes.append(st)
		st.modulate.a = 0.0
	vb.add_child(srow)
	vb.add_child(UiKit.label(Game.t("moves") % moves + "   ·   " + Game.t("par") % int(level.par), 34, Color.WHITE, 8))
	if new_best:
		vb.add_child(UiKit.label(Game.t("new_best"), 32, Color(1, 0.85, 0.3), 8))
	elif prev_best > 0:
		vb.add_child(UiKit.label(Game.t("best") % mini(prev_best, moves), 28, Color(1, 1, 1, 0.6), 6))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	var again := UiKit.IconButton.new("restart", Color("ff7d12"), 104)
	again.pressed.connect(func(): start_level(level_idx))
	row.add_child(again)
	var last := level_idx + 1 >= Game.level_count()
	var nxt := UiKit.button(Game.t("menu") if last else Game.t("next"), Color("8cf01e"), Vector2(260, 104), 46)
	nxt.pressed.connect(func():
		if last:
			show_title()
		else:
			start_level(level_idx + 1))
	row.add_child(nxt)
	vb.add_child(row)
	if last:
		vb.add_child(UiKit.label(Game.t("all_done"), 30, Color(1, 0.85, 0.3), 8))
	screen.add_child(panel)
	_place(panel, Control.PRESET_CENTER, 0)
	UiKit.pop_in(panel, 0.0, 0.5)
	for s in 3:
		var st: Control = star_nodes[s]
		var t := st.create_tween()
		t.tween_interval(0.45 + s * 0.28)
		t.tween_callback(func():
			st.modulate.a = 1.0
			st.pivot_offset = st.size * 0.5
			st.scale = Vector2(2.2, 2.2)
			if st.filled:
				Sfx.play("star", 1.0 + s * 0.2)
			else:
				Sfx.play("toggle", 0.7, -6))
		t.tween_property(st, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	UiKit.pop_in(row, 1.3, 0.4)


# ================================================================ per frame juice

func _process(_delta: float) -> void:
	if screen == null:
		return
	var tt := Time.get_ticks_msec() / 1000.0
	_wave(screen, tt)


func _wave(n: Node, tt: float) -> void:
	for c in n.get_children():
		if c is TextureRect and c.has_meta("logo"):
			var j: float = c.get_meta("jiggle", 0.0)
			if j > 0.0:
				j = maxf(0.0, j - get_process_delta_time() * 1.6)
				c.set_meta("jiggle", j)
			c.pivot_offset = c.size * 0.5
			c.rotation = sin(tt * 1.3) * 0.025 + sin(tt * 24.0) * 0.08 * j
			if c.get_meta("popped", false):
				c.scale = Vector2.ONE * (1.0 + 0.025 * sin(tt * 2.1) + 0.12 * j)
			elif c.scale.x >= 0.999:
				c.set_meta("popped", true)
		elif c is Label and c.has_meta("wave"):
			var k: int = c.get_meta("wave")
			c.pivot_offset = c.size * 0.5
			c.rotation = sin(tt * 2.2 + k * 0.6) * 0.06
			c.scale = Vector2.ONE * (1.0 + 0.06 * sin(tt * 3.0 + k * 0.7))
		elif c.get_child_count() > 0:
			_wave(c, tt)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if state == "play" or state == "win" or state == "levels":
			show_title()
		else:
			get_tree().quit()


# ================================================================ autotest

func _alog(s: String) -> void:
	var line := "AUTOTEST " + s
	print(line)
	_log.append(line)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img.get_width() > img.get_height():
		name = "land_" + name
	var dir := "res://renders/game/" if OS.has_feature("editor") else "user://shots/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	img.save_png(ProjectSettings.globalize_path(dir + name + ".png"))
	_alog("shot " + name)


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _wait_idle() -> void:
	var n := 0
	while board.busy and n < 300:
		await get_tree().process_frame
		n += 1


func _click_peg(i: int) -> void:
	press_at(board.peg_screen_pos(i))
	await _wait(0.05)


func _autotest() -> void:
	var fails := 0
	var only := Game.arg_value("--only", "")
	await _wait(0.3)
	if Sfx.music.stream == null or Sfx.music.stream.get_length() < 60.0:
		_alog("FAIL music missing")
		fails += 1
	else:
		_alog("music %.1f s, loop=%s" % [Sfx.music.stream.get_length(), str(Sfx.music.stream.loop)])
	show_title()
	await _wait(1.6)
	await _shot("01_title")
	show_levels()
	await _wait(1.0)
	await _shot("02_levels")
	# --- level 1: picking, rejection, full solve by simulated taps
	start_level(0)
	await _wait(1.6)
	await _shot("03_level1_start")
	# pick test
	for i in board.positions.size():
		var got := board.pick(board.peg_screen_pos(i))
		if got != i:
			_alog("FAIL pick peg %d -> %d" % [i, got])
			fails += 1
	# rejection test: find an illegal pair
	var p := board.puzzle
	var bad := Vector2i(-1, -1)
	for a in p.pegs.size():
		for b in p.pegs.size():
			if a != b and not p.pegs[a].is_empty() and p.why_not(a, b) != "" and p.why_not(a, b) != "same":
				bad = Vector2i(a, b)
	if bad.x >= 0:
		await _click_peg(bad.x)
		await _wait(0.3)
		await _click_peg(bad.y)
		await _wait(0.2)
		await _shot("04_reject")
		if board.selected != bad.x:
			_alog("FAIL reject should keep selection")
			fails += 1
		await _click_peg(bad.x)   # put back
		await _wait(0.4)
	await _solve_by_taps()
	await _wait(2.6)
	await _shot("05_level1_win")
	if not won:
		_alog("FAIL level 1 not won")
		fails += 1
	else:
		_alog("level 1 won in %d moves (par %d)" % [history.size(), int(level.par)])
	# --- undo + hint on level 12
	start_level(11)
	await _wait(1.8)
	var before := board.puzzle.key()
	for k in 2:
		var m: Vector2i = solution[k]
		board.do_move(m.x, m.y, true)
		await _wait_idle()
		await _wait(0.15)
	undo()
	await _wait_idle()
	undo()
	await _wait_idle()
	await _wait(0.3)
	if board.puzzle.key() != before:
		_alog("FAIL undo did not restore state")
		fails += 1
	else:
		_alog("undo ok")
	hint()
	await _wait(0.5)
	await _shot("06_hint")
	if board.hint_pegs.is_empty():
		_alog("FAIL no hint shown")
		fails += 1
	# off-path hint uses the solver
	var mm := board.puzzle._moves(board.puzzle.pegs)
	var off: Vector2i = mm[0]
	if off == solution[0] and mm.size() > 1:
		off = mm[1]
	board.do_move(off.x, off.y, true)
	await _wait_idle()
	var t0 := Time.get_ticks_msec()
	hint()
	_alog("off-path hint took %d ms, shown=%s" % [Time.get_ticks_msec() - t0, str(not board.hint_pegs.is_empty())])
	await _wait(0.5)
	# --- every level: solution from json must be legal in the game rules, solve one mid level by taps
	var bad_levels := 0
	for i in Game.level_count():
		var pz := Puzzle.from_level(Game.get_level(i))
		var ok := true
		for m in Game.get_level(i).solution:
			if not pz.can_move(int(m[0]), int(m[1])):
				ok = false
				break
			pz.move(int(m[0]), int(m[1]))
		if not ok or not pz.is_won():
			bad_levels += 1
			_alog("FAIL level %d solution invalid" % (i + 1))
	fails += bad_levels
	_alog("checked %d level solutions" % Game.level_count())
	# --- solver timing on a big board
	var big := Puzzle.from_level(Game.get_level(29))
	t0 = Time.get_ticks_msec()
	var sol := big.solve(3000, 4.0)
	_alog("solver level 30: %d moves in %d ms" % [sol.size(), Time.get_ticks_msec() - t0])
	# --- screenshots of bigger boards
	for li in [9, 24, 44, 49]:
		start_level(li)
		await _wait(2.0)
		await _shot("07_level%02d" % (li + 1))
	# --- win panel on a mid level
	start_level(5)
	await _wait(1.6)
	await _solve_by_taps(true)
	await _wait(3.2)
	await _shot("08_win_panel")
	if not won:
		_alog("FAIL level 6 not won")
		fails += 1
	_alog("DONE fails=%d" % fails)
	var f := FileAccess.open(ProjectSettings.globalize_path("res://renders/autotest.log") if OS.has_feature("editor") else "user://autotest.log", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_log))
	get_tree().quit(1 if fails > 0 else 0)


func _solve_by_taps(mid_shot := false) -> void:
	var k := 0
	for m in solution:
		await _wait_idle()
		await _click_peg(m.x)
		await _wait(0.22)
		if mid_shot and k == 2:
			await _shot("08a_selected")
		await _click_peg(m.y)
		await _wait(0.1)
		await _wait_idle()
		k += 1
		if won:
			break


## Plays a level like a person: taps the top ring of the source stack and the top of the
## destination stack (not the peg centre), screenshots every step, logs what was picked.
func _playtest(idx: int) -> void:
	await _wait(0.3)
	start_level(idx)
	await _wait(1.8)
	await _shot("pt_%02d_00" % (idx + 1))
	var step := 0
	for m in solution:
		step += 1
		await _wait_idle()
		var src := _human_point(m.x)
		var got := board.pick(src)
		press_at(src)
		await _wait(0.3)
		await _shot("pt_%02d_%02da" % [idx + 1, step])
		var dst := _human_point(m.y)
		var got2 := board.pick(dst)
		press_at(dst)
		await _wait(0.12)
		await _wait_idle()
		await _wait(0.5)
		await _shot("pt_%02d_%02db" % [idx + 1, step])
		_alog("step %d move %d->%d picked %d->%d hist=%d sel=%d" % [step, m.x, m.y, got, got2, history.size(), board.selected])
	await _wait(3.0)
	await _shot("pt_%02d_end" % (idx + 1))
	# fast player: tap source+destination of the next move while the previous ring still flies
	start_level(idx)
	await _wait(1.8)
	var k := 0
	for m in solution:
		press_at(_human_point(m.x))
		await _wait(0.25)
		press_at(_human_point(m.y))
		await _wait(0.25)
		k += 1
	await _wait(2.0)
	_alog("fast taps: history=%d of %d won=%s" % [history.size(), solution.size(), str(won)])
	_alog("won=%s moves=%d" % [str(won), history.size()])
	get_tree().quit()


func _human_point(i: int) -> Vector2:
	if board.rings[i].is_empty():
		return cam.unproject_position(board.positions[i] + Vector3(0, Board.BASE_TOP, 0))
	var j: int = board.puzzle.pegs[i].size() - 1
	var code: int = board.puzzle.pegs[i][j]
	return cam.unproject_position(board.rest_pos(i, j) + Vector3(0, Board.ring_h(code % 10) * 0.5, 0))


## Debug: every colour as a 3-ring pyramid, for checking the palette.
func _swatch() -> void:
	await _wait(0.3)
	state = "play"
	level = {"par": 0, "id": 0, "colors": 7, "sizes": 3, "solution": []}
	board.build(Puzzle.showcase(7, 3), false)
	_fit_for_state()
	await _wait(0.6)
	await _shot("swatch_" + Game.arg_value("--swatch", "x"))
	get_tree().quit()


## Google Play screenshots: python tools/play_store.py runs this at 1080x1920 for ru and en.
func _storeshots() -> void:
	var tag: String = Game.save.lang
	var dir := "res://renders/play/raw/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var snap := func(name: String) -> void:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(dir + tag + "_" + name + ".png"))
		_alog("store shot " + name)
	var want := Vector2i(1080, 1920)
	get_window().borderless = true
	get_window().position = Vector2i(0, 0)
	get_window().size = want
	await _wait(0.3)
	_alog("store window %s viewport %s" % [str(get_window().size), str(get_viewport().get_visible_rect().size)])
	# fake progress so the level list and title look lived-in (never saved)
	Game.save.unlocked = 14
	Game.save.stars = {}
	Game.save.best = {}
	for i in 13:
		Game.save.stars[str(i + 1)] = 3 if i % 4 != 2 else 2
	await _wait(0.3)
	show_title()
	await _wait(2.4)
	await snap.call("1_title")
	# a big colourful board with a ring lifted
	start_level(25)
	await _wait(2.2)
	board.tap(solution[0].x)
	await _wait(0.6)
	await snap.call("2_board")
	# a pyramid being completed: play level 12 until the first peg completes
	start_level(11)
	await _wait(2.0)
	var done := false
	for m in solution:
		board.do_move(m.x, m.y, true)
		await _wait_idle()
		if not board.completed.is_empty():
			await _wait(0.22)
			await snap.call("3_pyramid")
			done = true
			break
		await _wait(0.1)
	if not done:
		await snap.call("3_pyramid")
	# hint on a mid level
	start_level(17)
	await _wait(2.0)
	hint()
	await _wait(0.35)
	await snap.call("4_hint")
	# the hardest board
	start_level(47)
	await _wait(2.4)
	await snap.call("5_big")
	# a win with three stars
	start_level(8)
	await _wait(1.8)
	for m in solution:
		board.do_move(m.x, m.y, true)
		await _wait_idle()
		await _wait(0.05)
	await _wait(3.4)
	await snap.call("6_win")
	show_levels()
	await _wait(1.6)
	await snap.call("7_levels")
	get_tree().quit()
