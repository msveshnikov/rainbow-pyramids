class_name Board
extends Node3D
## The 3D board: pegs, rings, picking, and every animation / effect.

signal moved(a: int, b: int, record: bool)
signal rejected(peg: int, reason: String)
signal landed(peg: int)
signal peg_completed(peg: int)
signal won

const FLAT := 0.95           # rings are squashed tori
const BASE_TOP := 0.1
const STACK := 0.9           # rings nest a little into each other

const RING_SHADER := preload("res://scripts/ring.gdshader")
const OUTLINE_SHADER := preload("res://scripts/outline.gdshader")
const BLOB_SHADER := preload("res://scripts/blob.gdshader")
const NOTES := [1.0, 1.122, 1.26, 1.335, 1.498, 1.682, 1.888, 2.0]

var cam: Camera3D
var puzzle: Puzzle
var content: Node3D
var pegs: Array = []        # Dictionary per peg
var rings: Array = []       # per peg: Array of ring pivots (Node3D), bottom -> top
var positions: Array = []   # Vector3 per peg
var completed := {}
var selected := -1
var busy := false
var pending_taps: Array = []   # taps made while a ring was flying (max 2), replayed on landing
var bob_ready := false
var stick_h := 1.5
var lift_y := 2.0
var base_r := 0.9
var showcase := false
var time := 0.0
var hint_pegs: Array = []
var color_map: Array = [0, 1, 2, 3, 4, 5, 6]   # puzzle colour -> Game.COLORS index
var hint_time := 0.0
var _mesh_cache := {}
var _dot_mat: StandardMaterial3D
var _floor: MeshInstance3D


static func r_out(s: int) -> float:
	return 0.36 + 0.085 * s


static func tube(s: int) -> float:
	return 0.15 + 0.014 * s


static func ring_h(s: int) -> float:
	return 2.0 * tube(s) * FLAT


func color_of(c: int) -> Color:
	return Game.COLORS[color_map[c] if c < color_map.size() else c % Game.COLORS.size()]


func _ready() -> void:
	_dot_mat = StandardMaterial3D.new()
	_dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dot_mat.vertex_color_use_as_albedo = true
	_dot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_floor = MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(40, 40)
	_floor.mesh = q
	var fm := ShaderMaterial.new()
	fm.shader = BLOB_SHADER
	fm.set_shader_parameter("center_color", Color(0.11, 0.06, 0.2, 1.0))
	fm.set_shader_parameter("edge_color", Color(0, 0, 0, 1))
	fm.set_shader_parameter("power", 0.7)
	_floor.material_override = fm
	_floor.position.y = -0.01
	add_child(_floor)


# ---------------------------------------------------------------- building

func clear() -> void:
	if content:
		content.queue_free()
	content = Node3D.new()
	add_child(content)
	pegs.clear()
	rings.clear()
	positions.clear()
	completed.clear()
	hint_pegs.clear()
	selected = -1
	busy = false
	pending_taps.clear()
	bob_ready = false


func build(p: Puzzle, animate := true) -> void:
	clear()
	showcase = false
	puzzle = p
	color_map = Game.palette_for(p.colors)
	var smax := p.sizes
	base_r = r_out(smax) + 0.1
	stick_h = p.cap * ring_h(smax) * STACK + 0.32
	lift_y = BASE_TOP + stick_h + 0.35 + ring_h(smax) * 0.5
	positions = layout_positions(p.pegs.size())
	for i in p.pegs.size():
		pegs.append(_make_peg(i))
	for i in p.pegs.size():
		var arr: Array = []
		for j in p.pegs[i].size():
			var r := make_ring(p.pegs[i][j])
			content.add_child(r)
			r.position = rest_pos(i, j)
			arr.append(r)
		rings.append(arr)
	for i in p.pegs.size():
		if p.peg_complete(i):
			completed[i] = true
			_style_complete(i, false)
	if animate:
		intro()


func layout_positions(n: int) -> Array:
	var vs := get_viewport().get_visible_rect().size
	var aspect := vs.x / maxf(vs.y, 1.0)
	var max_cols := 4 if aspect < 0.75 else (5 if aspect < 1.25 else 7)
	var rows := ceili(float(n) / max_cols)
	var per_row := ceili(float(n) / rows)
	var spacing := base_r * 2.0 + 0.22
	var row_sp := spacing * 0.95 + stick_h * 0.8
	var out: Array = []
	var idx := 0
	for r in rows:
		var cnt := mini(per_row, n - idx)
		for c in cnt:
			var x := (c - (cnt - 1) / 2.0) * spacing
			var z := (r - (rows - 1) / 2.0) * row_sp
			out.append(Vector3(x, 0, z))
			idx += 1
	return out


## Re-arrange pegs for a new screen shape (rotation / window resize).
func relayout() -> void:
	if puzzle == null or showcase:
		return
	var np := layout_positions(puzzle.pegs.size())
	for i in np.size():
		var d: Vector3 = np[i] - positions[i]
		positions[i] = np[i]
		pegs[i].root.position = np[i]
		for r in rings[i]:
			r.position += d


func rest_pos(i: int, j: int) -> Vector3:
	var y := BASE_TOP
	var codes: Array = puzzle.pegs[i]
	for k in j:
		y += ring_h(codes[k] % 10) * STACK
	y += ring_h(codes[j] % 10) * 0.5
	return positions[i] + Vector3(0, y, 0)


func lift_pos(i: int) -> Vector3:
	return positions[i] + Vector3(0, lift_y, 0)


func _ring_mesh(s: int) -> Mesh:
	if not _mesh_cache.has(s):
		var t := TorusMesh.new()
		t.outer_radius = r_out(s)
		t.inner_radius = r_out(s) - 2.0 * tube(s)
		t.rings = 44
		t.ring_segments = 22
		_mesh_cache[s] = t
	return _mesh_cache[s]


func make_ring(code: int) -> Node3D:
	var c := code / 10
	var s := code % 10
	var pivot := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _ring_mesh(s)
	mi.scale = Vector3(1, FLAT, 1)
	var col: Color = color_of(c)
	var m := ShaderMaterial.new()
	m.shader = RING_SHADER
	m.set_shader_parameter("base_color", col)
	var o := ShaderMaterial.new()
	o.shader = OUTLINE_SHADER
	o.set_shader_parameter("outline_color", col.darkened(0.78))
	o.set_shader_parameter("width", 0.018 + 0.002 * s)
	m.next_pass = o
	mi.material_override = m
	pivot.add_child(mi)
	pivot.set_meta("code", code)
	pivot.set_meta("mat", m)
	return pivot


func _make_peg(i: int) -> Dictionary:
	var root := Node3D.new()
	content.add_child(root)
	root.position = positions[i]
	# soft contact shadow
	var sh := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(base_r * 3.0, base_r * 3.0)
	sh.mesh = q
	var sm := ShaderMaterial.new()
	sm.shader = BLOB_SHADER
	sm.set_shader_parameter("center_color", Color(0, 0, 0, 0.85))
	sh.material_override = sm
	sh.position.y = 0.004
	root.add_child(sh)
	# base disc
	var base := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = base_r
	cm.bottom_radius = base_r + 0.04
	cm.height = BASE_TOP
	cm.radial_segments = 48
	base.mesh = cm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.16, 0.15, 0.22)
	bm.roughness = 0.25
	bm.metallic = 0.35
	base.material_override = bm
	base.position.y = BASE_TOP * 0.5
	root.add_child(base)
	# glowing rim (selection / hint / error / done colour)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.outer_radius = base_r + 0.05
	tm.inner_radius = base_r - 0.01
	tm.rings = 64
	tm.ring_segments = 8
	rim.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(0.3, 0.32, 0.48)
	rim.material_override = rm
	rim.position.y = BASE_TOP
	rim.scale = Vector3(1, 0.5, 1)
	root.add_child(rim)
	# stick + tip
	var stick := MeshInstance3D.new()
	var st := CylinderMesh.new()
	st.top_radius = 0.06
	st.bottom_radius = 0.07
	st.height = stick_h
	st.radial_segments = 16
	stick.mesh = st
	var stm := StandardMaterial3D.new()
	stm.albedo_color = Color(0.86, 0.88, 0.95)
	stm.roughness = 0.2
	stm.emission_enabled = true
	stm.emission = Color(0.25, 0.27, 0.35)
	stick.material_override = stm
	stick.position.y = BASE_TOP + stick_h * 0.5
	root.add_child(stick)
	var tip := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.085
	sp.height = 0.17
	tip.mesh = sp
	var tipm := stm.duplicate()
	tip.material_override = tipm
	tip.position.y = BASE_TOP + stick_h
	root.add_child(tip)
	return {"root": root, "rim": rim, "rim_mat": rm, "tip": tip, "tip_mat": tipm, "stick": stick}


# ---------------------------------------------------------------- picking

func pick(screen: Vector2) -> int:
	if cam == null:
		return -1
	var best := -1
	var bd := INF
	for i in positions.size():
		var p0 := cam.unproject_position(positions[i])
		var p1 := cam.unproject_position(lift_pos(i))
		var rad := cam.unproject_position(positions[i] + cam.global_basis.x * base_r).distance_to(p0)
		p0 += (p0 - p1).normalized() * rad * 0.4
		var d := Geometry2D.get_closest_point_to_segment(screen, p0, p1).distance_to(screen)
		if d < rad * 1.15 and d < bd:
			bd = d
			best = i
	return best


func peg_screen_pos(i: int) -> Vector2:
	return cam.unproject_position(positions[i] + Vector3(0, stick_h * 0.5, 0))


# ---------------------------------------------------------------- player actions

func tap(i: int) -> void:
	if Game.has_arg("--taplog"):
		print("TAP %d busy=%s sel=%d q=%s" % [i, str(busy), selected, str(pending_taps)])
	if showcase or puzzle == null:
		return
	if busy:
		if pending_taps.size() < 2:
			pending_taps.append(i)
		return
	if selected == -1:
		if puzzle.pegs[i].is_empty():
			_wobble(pegs[i].root, 0.08)
			Sfx.play("toggle", 0.8, -6)
			return
		_select(i)
	elif i == selected:
		deselect()
	else:
		var why := puzzle.why_not(selected, i)
		if why == "":
			do_move(selected, i, true)
		else:
			_reject(i, why)


func _select(i: int) -> void:
	selected = i
	bob_ready = false
	var r: Node3D = rings[i].back()
	var s: int = r.get_meta("code") % 10
	Sfx.play("pop", 1.35 - s * 0.07)
	_set_rim(i, Color(1, 1, 1))
	var tw := create_tween()
	tw.tween_property(r, "position", lift_pos(i), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(r, "scale", Vector3(1.08, 1.08, 1.08), 0.2)
	tw.tween_callback(func(): bob_ready = true)


func deselect() -> void:
	if selected < 0:
		return
	var i := selected
	selected = -1
	bob_ready = false
	_refresh_rim(i)
	var r: Node3D = rings[i].back()
	Sfx.play("cancel", 1.1, -4)
	var tw := create_tween()
	tw.tween_property(r, "rotation", Vector3.ZERO, 0.1)
	tw.parallel().tween_property(r, "scale", Vector3.ONE, 0.2)
	tw.parallel().tween_property(r, "position", rest_pos(i, rings[i].size() - 1), 0.32).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _reject(i: int, why: String) -> void:
	var r: Node3D = rings[selected].back()
	Sfx.play("error", 1.0, -3)
	_flash_rim(i, Color(1, 0.15, 0.1))
	var base: Vector3 = lift_pos(selected)
	bob_ready = false
	var tw := create_tween()
	var dir := cam.global_basis.x if cam else Vector3.RIGHT
	for k in 4:
		var amp := 0.16 * (1.0 - k * 0.22)
		tw.tween_property(r, "position", base + dir * amp, 0.045)
		tw.tween_property(r, "position", base - dir * amp, 0.045)
	tw.tween_property(r, "position", base, 0.05)
	tw.tween_callback(func(): bob_ready = selected >= 0)
	_wobble(pegs[i].root, 0.12)
	rejected.emit(i, why)


## Animates a ring from peg a to peg b. `record` = false for undo.
func do_move(a: int, b: int, record := true) -> void:
	var ring: Node3D = rings[a].pop_back()
	puzzle.move(a, b)
	rings[b].append(ring)
	if selected >= 0:
		var old := selected
		selected = -1
		_refresh_rim(old)
	if completed.has(a) and not puzzle.peg_complete(a):
		completed.erase(a)
		_style_normal(a)
	bob_ready = false
	busy = true
	hint_pegs.clear()
	_refresh_rim(a)
	_refresh_rim(b)
	moved.emit(a, b, record)
	var j: int = rings[b].size() - 1
	var final := rest_pos(b, j)
	var start := ring.position
	if not record:
		start = ring.position
	var above := lift_pos(b)
	var dist := start.distance_to(above)
	var tilt := signf(above.x - start.x) * -0.5
	var s: int = ring.get_meta("code") % 10
	Sfx.play("lift", 1.25 - s * 0.05, -9)
	var tw := create_tween()
	tw.tween_method(_arc_step.bind(ring, start, above, 0.35 + dist * 0.12, tilt), 0.0, 1.0, 0.16 + dist * 0.03) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(ring, "scale", Vector3.ONE, 0.15)
	tw.tween_property(ring, "position", final, 0.11 + (above.y - final.y) * 0.04).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_on_landed.bind(b, ring))


func _arc_step(t: float, ring: Node3D, p0: Vector3, p1: Vector3, h: float, tilt: float) -> void:
	var p := p0.lerp(p1, t)
	p.y += sin(t * PI) * h
	ring.position = p
	ring.rotation = Vector3(0, 0, sin(t * PI) * tilt)


func _flush_pending() -> void:
	while not pending_taps.is_empty() and not busy:
		tap(pending_taps.pop_front())


func _on_landed(b: int, ring: Node3D) -> void:
	busy = false
	ring.rotation = Vector3.ZERO
	var s: int = ring.get_meta("code") % 10
	var c: int = ring.get_meta("code") / 10
	Sfx.play("drop", 1.3 - s * 0.08, -2)
	Sfx.play("clink", 1.6 - s * 0.1, -14)
	var tw := create_tween()
	tw.tween_property(ring, "scale", Vector3(1.2, 0.68, 1.2), 0.05)
	tw.tween_property(ring, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	# rings underneath feel the impact
	var arr: Array = rings[b]
	for k in range(arr.size() - 2, -1, -1):
		var below: Node3D = arr[k]
		var d := (arr.size() - 1 - k) * 0.035
		var amt := 0.07 / (arr.size() - k)
		var t2 := create_tween()
		t2.tween_interval(d)
		t2.tween_property(below, "scale", Vector3(1 + amt, 1 - amt * 1.5, 1 + amt), 0.05)
		t2.tween_property(below, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	burst(ring.position + Vector3(0, -ring_h(s) * 0.3, 0), color_of(c), 14, 2.2, 0.06)
	landed.emit(b)
	if puzzle.peg_complete(b) and not completed.has(b):
		completed[b] = true
		celebrate_peg(b)
		peg_completed.emit(b)
		if puzzle.is_won():
			var t3 := create_tween()
			t3.tween_interval(0.75)
			t3.tween_callback(celebrate_win)
			t3.tween_interval(0.4)
			t3.tween_callback(func(): won.emit())
	if puzzle.is_won():
		pending_taps.clear()
	else:
		_flush_pending.call_deferred()


func show_hint(a: int, b: int) -> void:
	hint_pegs = [a, b]
	hint_time = 0.0
	Sfx.play("hint")
	if selected >= 0 and selected != a:
		deselect()
	if not rings[a].is_empty():
		var r: Node3D = rings[a].back()
		if selected != a:
			var tw := create_tween()
			var p := r.position
			tw.tween_property(r, "position", p + Vector3(0, 0.35, 0), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(r, "position", p, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------- rim / peg styling

func _set_rim(i: int, c: Color) -> void:
	pegs[i].rim_mat.albedo_color = c


func _refresh_rim(i: int) -> void:
	if i < 0 or i >= pegs.size():
		return
	if i == selected:
		_set_rim(i, Color(1, 1, 1))
	elif completed.has(i):
		_set_rim(i, color_of(puzzle.pegs[i][0] / 10))
	else:
		_set_rim(i, Color(0.3, 0.32, 0.48))


func _flash_rim(i: int, c: Color) -> void:
	_set_rim(i, c)
	var tw := create_tween()
	tw.tween_interval(0.35)
	tw.tween_callback(_refresh_rim.bind(i))


func _style_complete(i: int, anim := true) -> void:
	var col: Color = color_of(puzzle.pegs[i][0] / 10)
	var tm: StandardMaterial3D = pegs[i].tip_mat
	tm.albedo_color = Color(1, 0.85, 0.3)
	tm.emission = Color(1.0, 0.75, 0.2) * 1.6
	_refresh_rim(i)
	if anim:
		var tip: Node3D = pegs[i].tip
		tip.scale = Vector3.ONE * 0.2
		var tw := create_tween()
		tw.tween_property(tip, "scale", Vector3.ONE * 1.7, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(tip, "scale", Vector3.ONE * 1.25, 0.3)
	else:
		pegs[i].tip.scale = Vector3.ONE * 1.25
	pegs[i].rim_mat.albedo_color = col


func _style_normal(i: int) -> void:
	var tm: StandardMaterial3D = pegs[i].tip_mat
	tm.albedo_color = Color(0.86, 0.88, 0.95)
	tm.emission = Color(0.25, 0.27, 0.35)
	pegs[i].tip.scale = Vector3.ONE
	_refresh_rim(i)


# ---------------------------------------------------------------- celebrations

func celebrate_peg(i: int) -> void:
	_style_complete(i)
	var arr: Array = rings[i]
	var col: Color = color_of(puzzle.pegs[i][0] / 10)
	for j in arr.size():
		var r: Node3D = arr[j]
		var y0 := rest_pos(i, j).y
		var tw := create_tween()
		tw.tween_interval(0.08 + j * 0.075)
		tw.tween_callback(Sfx.play.bind("glass", NOTES[j % NOTES.size()] * 0.9, -4))
		tw.tween_property(r, "position:y", y0 + 0.45, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(r, "position:y", y0, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		var m: ShaderMaterial = r.get_meta("mat")
		var tf := create_tween()
		tf.tween_interval(0.08 + j * 0.075)
		tf.tween_method(func(v): m.set_shader_parameter("flash", v), 0.9, 0.0, 0.5)
	var t2 := create_tween()
	t2.tween_interval(0.12 + arr.size() * 0.075)
	t2.tween_callback(Sfx.play.bind("powerup", 1.0, -6))
	t2.tween_callback(burst.bind(positions[i] + Vector3(0, BASE_TOP + stick_h + 0.2, 0), col, 40, 4.5, 0.09, true))
	_halo(i, col)


func _halo(i: int, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.outer_radius = base_r
	tm.inner_radius = base_r - 0.07
	tm.rings = 48
	tm.ring_segments = 8
	mi.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(col.lightened(0.4), 0.9)
	mi.material_override = m
	content.add_child(mi)
	mi.position = positions[i] + Vector3(0, BASE_TOP, 0)
	var tw := create_tween().set_parallel()
	tw.tween_property(mi, "position:y", BASE_TOP + stick_h + 0.6, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "scale", Vector3(0.3, 1, 0.3), 0.8)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.8).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


func celebrate_win() -> void:
	Sfx.play("win")
	for i in rings.size():
		var arr: Array = rings[i]
		for j in arr.size():
			var r: Node3D = arr[j]
			var y0 := rest_pos(i, j).y
			var tw := create_tween()
			tw.tween_interval(i * 0.07 + j * 0.05)
			tw.tween_property(r, "position:y", y0 + 0.7 + j * 0.08, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(r, "rotation:y", TAU, 0.5)
			tw.tween_property(r, "position:y", y0, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			tw.tween_callback(func(): r.rotation = Vector3.ZERO)
	confetti()


func confetti() -> void:
	var p := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 0.02, 0.07)
	p.mesh = bm
	p.material_override = _dot_mat
	p.amount = 160
	p.lifetime = 3.2
	p.one_shot = true
	p.explosiveness = 0.85
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	var ext := Vector3(4, 0.2, 3)
	for q in positions:
		ext.x = maxf(ext.x, absf(q.x) + 1.5)
		ext.z = maxf(ext.z, absf(q.z) + 1.5)
	p.emission_box_extents = ext
	p.direction = Vector3(0, 1, 0)
	p.spread = 35
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 7.0
	p.gravity = Vector3(0, -5.5, 0)
	p.angular_velocity_min = -400
	p.angular_velocity_max = 400
	p.particle_flag_rotate_y = true
	p.angle_min = 0
	p.angle_max = 360
	p.damping_min = 0.5
	p.damping_max = 1.5
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.17, 0.34, 0.5, 0.67, 0.84, 1.0])
	g.colors = PackedColorArray(Game.COLORS)
	p.color_initial_ramp = g
	p.position = Vector3(0, lift_y * 0.5, 0)
	content.add_child(p)
	p.emitting = true
	get_tree().create_timer(3.6).timeout.connect(p.queue_free)


func burst(at: Vector3, col: Color, amount := 16, speed := 2.5, sz := 0.07, upward := false) -> void:
	if content == null:
		return
	var p := CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = sz
	sm.height = sz * 2.0
	sm.radial_segments = 8
	sm.rings = 4
	p.mesh = sm
	p.material_override = _dot_mat
	p.amount = amount
	p.lifetime = 0.9 if upward else 0.55
	p.one_shot = true
	p.explosiveness = 0.95
	p.direction = Vector3(0, 1, 0)
	p.spread = 50.0 if upward else 90.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -6.0 if upward else -3.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var cr := Gradient.new()
	cr.colors = PackedColorArray([Color(col.lightened(0.5), 1.0), Color(col, 0.0)])
	p.color_ramp = cr
	p.position = at
	content.add_child(p)
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.3).timeout.connect(p.queue_free)


func _wobble(n: Node3D, amt: float) -> void:
	var tw := create_tween()
	tw.tween_property(n, "scale", Vector3(1 + amt, 1 - amt, 1 + amt), 0.06)
	tw.tween_property(n, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func intro() -> void:
	busy = true
	Sfx.play("sparkle", 1.0, -8)
	var longest := 0.0
	for i in pegs.size():
		var root: Node3D = pegs[i].root
		root.scale = Vector3(0.01, 0.01, 0.01)
		var tw := create_tween()
		tw.tween_interval(i * 0.05)
		tw.tween_property(root, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		for j in rings[i].size():
			var r: Node3D = rings[i][j]
			var fin := r.position
			r.position = fin + Vector3(0, 6.0 + j * 0.8, 0)
			var d: float = 0.25 + i * 0.06 + j * 0.07
			var t2 := create_tween()
			t2.tween_interval(d)
			t2.tween_property(r, "position", fin, 0.55).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			if j == 0:
				t2.parallel().tween_callback(Sfx.play.bind("clink", 1.2 + i * 0.05, -16)).set_delay(0.3)
			longest = maxf(longest, d + 0.55)
	var tw2 := create_tween()
	tw2.tween_interval(minf(longest, 1.2))
	tw2.tween_callback(func():
		busy = false
		_flush_pending())


# ---------------------------------------------------------------- title showcase

func build_showcase() -> void:
	clear()
	showcase = true
	color_map = [0, 1, 2, 3, 4, 5, 6]
	puzzle = Puzzle.showcase(7, 7)
	var p := Puzzle.new()
	p.colors = 1
	p.sizes = 7
	p.cap = 7
	# bottom ring = violet (largest), top = red (smallest), like the concept art
	var arr: Array = []
	for k in 7:
		var c := 6 - k
		arr.append(c * 10 + (7 - k))
	p.pegs = [arr]
	puzzle = p
	base_r = r_out(7) + 0.1
	stick_h = 7 * ring_h(7) * STACK * 0.8
	lift_y = stick_h + 0.6
	positions = [Vector3.ZERO]
	var stack: Array = []
	for j in arr.size():
		var r := make_ring(arr[j])
		content.add_child(r)
		r.position = rest_pos(0, j)
		r.set_meta("y0", r.position.y)
		stack.append(r)
	rings = [stack]
	# floating loose rings around the pyramid
	for k in 7:
		var r := make_ring(k * 10 + 3 + (k % 3))
		content.add_child(r)
		r.set_meta("orbit", k)
		r.scale = Vector3.ONE * 0.75
	for j in stack.size():
		var r: Node3D = stack[j]
		var fin := r.position
		r.position = fin + Vector3(0, 8 + j, 0)
		var tw := create_tween()
		tw.tween_interval(0.15 + (stack.size() - j) * 0.0 + j * 0.09)
		tw.tween_property(r, "position", fin, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func showcase_points() -> Array:
	var pts: Array = []
	var top := rest_pos(0, 6).y + 0.4
	for a in 8:
		var ang := a * TAU / 8.0
		pts.append(Vector3(cos(ang) * 2.6, 0, sin(ang) * 2.6))
		pts.append(Vector3(cos(ang) * 1.2, top, sin(ang) * 1.2))
	return pts


func showcase_poke(screen: Vector2) -> bool:
	if not showcase or cam == null:
		return false
	var best: Node3D = null
	var bd := 1e9
	for r in content.get_children():
		if not (r is Node3D) or not r.has_meta("code"):
			continue
		var sp := cam.unproject_position(r.global_position)
		var d := sp.distance_to(screen)
		if d < bd:
			bd = d
			best = r
	if best and bd < 90.0:
		var s: int = best.get_meta("code") % 10
		Sfx.play("pop", 1.5 - s * 0.08)
		burst(best.global_position, color_of(best.get_meta("code") / 10), 12, 2.0, 0.05)
		best.set_meta("hop", 1.0)
		return true
	return false


# ---------------------------------------------------------------- per-frame

func _process(delta: float) -> void:
	time += delta
	if showcase and content:
		_animate_showcase(delta)
		return
	if selected >= 0 and bob_ready and not busy and not rings[selected].is_empty():
		var r: Node3D = rings[selected].back()
		r.position = lift_pos(selected) + Vector3(0, sin(time * 5.0) * 0.07, 0)
		r.rotation = Vector3(sin(time * 3.1) * 0.07, 0, sin(time * 2.3) * 0.09)
	if not hint_pegs.is_empty():
		hint_time += delta
		var k := 0.5 + 0.5 * sin(hint_time * 9.0)
		for i in hint_pegs:
			if i != selected:
				_set_rim(i, Color(1, 0.85, 0.2).lerp(Color(0.35, 0.3, 0.1), k))
		if hint_time > 3.0:
			var old := hint_pegs
			hint_pegs = []
			for i in old:
				_refresh_rim(i)


func _animate_showcase(delta: float) -> void:
	var stack: Array = rings[0] if not rings.is_empty() else []
	for j in stack.size():
		var r: Node3D = stack[j]
		if not r.has_meta("y0"):
			continue
		var hop: float = r.get_meta("hop", 0.0)
		if hop > 0.0:
			hop = maxf(0.0, hop - delta * 2.2)
			r.set_meta("hop", hop)
		r.rotation.y += delta * (0.4 + j * 0.05)
	for r in content.get_children():
		if r is Node3D and r.has_meta("orbit"):
			var k: int = r.get_meta("orbit")
			var hop: float = r.get_meta("hop", 0.0)
			if hop > 0.0:
				hop = maxf(0.0, hop - delta * 1.8)
				r.set_meta("hop", hop)
			var ang := time * 0.35 + k * TAU / 7.0
			var rad := 3.3 + sin(time * 0.7 + k) * 0.25
			r.position = Vector3(cos(ang) * rad, 1.2 + sin(time * 1.3 + k * 1.7) * 0.9 + sin(hop * PI) * 1.2, sin(ang) * rad * 0.8)
			r.rotation = Vector3(sin(time + k) * 0.6, ang, cos(time * 0.8 + k) * 0.5)
	# stack rings that were poked hop up
	for j in stack.size():
		var r: Node3D = stack[j]
		var hop: float = r.get_meta("hop", 0.0)
		if hop > 0.0 and r.has_meta("y0"):
			r.position.y = r.get_meta("y0") + sin(hop * PI) * 0.8
