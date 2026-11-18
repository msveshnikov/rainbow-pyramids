class_name Puzzle
extends RefCounted
## Pure game rules. A ring is an int code: colour * 10 + size (size 1 = smallest).
## Each peg is an Array of codes, bottom -> top.

var pegs: Array = []
var colors := 3
var sizes := 3
var cap := 3


static func from_level(lv: Dictionary) -> Puzzle:
	var p := Puzzle.new()
	p.colors = int(lv.colors)
	p.sizes = int(lv.sizes)
	p.cap = int(lv.cap)
	for peg in lv.pegs:
		var arr: Array = []
		for r in peg:
			arr.append(int(r[0]) * 10 + int(r[1]))
		p.pegs.append(arr)
	return p


## A solved board with one pyramid of every colour (used for the title screen).
static func showcase(n_colors: int, n_sizes: int) -> Puzzle:
	var p := Puzzle.new()
	p.colors = n_colors
	p.sizes = n_sizes
	p.cap = n_sizes
	for c in n_colors:
		var arr: Array = []
		for s in range(n_sizes, 0, -1):
			arr.append(c * 10 + s)
		p.pegs.append(arr)
	return p


func duplicate_puzzle() -> Puzzle:
	var p := Puzzle.new()
	p.colors = colors
	p.sizes = sizes
	p.cap = cap
	p.pegs = _copy(pegs)
	return p


static func col(r: int) -> int:
	return r / 10


static func size_of(r: int) -> int:
	return r % 10


## "" when the move is legal, otherwise the reason: "full", "color", "size", "same", "empty".
func why_not(a: int, b: int) -> String:
	if a == b:
		return "same"
	if pegs[a].is_empty():
		return "empty"
	var dst: Array = pegs[b]
	if dst.size() >= cap:
		return "full"
	if dst.is_empty():
		return ""
	var r: int = pegs[a].back()
	var t: int = dst.back()
	if t / 10 != r / 10:
		return "color"
	if t % 10 <= r % 10:
		return "size"
	return ""


func can_move(a: int, b: int) -> bool:
	return why_not(a, b) == ""


func move(a: int, b: int) -> int:
	var r: int = pegs[a].pop_back()
	pegs[b].append(r)
	return r


func peg_complete(i: int) -> bool:
	return pegs[i].size() == sizes and _settled(pegs[i], sizes) == sizes


func is_won() -> bool:
	return _h(pegs) == 0


func has_any_move() -> bool:
	return not _moves(pegs).is_empty()


func key() -> String:
	return _key(pegs)


# ---------------------------------------------------------------- solver

static func _copy(s: Array) -> Array:
	var out: Array = []
	for p in s:
		out.append(p.duplicate())
	return out


static func _settled(peg: Array, n_sizes: int) -> int:
	if peg.is_empty():
		return 0
	var c: int = peg[0] / 10
	var n := 0
	for i in peg.size():
		var r: int = peg[i]
		if r / 10 == c and r % 10 == n_sizes - i:
			n += 1
		else:
			break
	return n


func _h(s: Array) -> int:
	var settled := 0
	for p in s:
		settled += _settled(p, sizes)
	return colors * sizes - settled


static func _key(s: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for p in s:
		parts.append(str(p))
	parts.sort()
	return "|".join(parts)


func _moves(s: Array) -> Array:
	var out: Array = []
	for a in s.size():
		var A: Array = s[a]
		if A.is_empty():
			continue
		var r: int = A.back()
		var to_empty := false
		for b in s.size():
			if a == b:
				continue
			var B: Array = s[b]
			if B.size() >= cap:
				continue
			if B.is_empty():
				if to_empty or A.size() == 1:
					continue
				to_empty = true
				out.append(Vector2i(a, b))
				continue
			var t: int = B.back()
			if t / 10 == r / 10 and t % 10 > r % 10:
				out.append(Vector2i(a, b))
	return out


static func _apply(s: Array, m: Vector2i) -> Array:
	var n := _copy(s)
	n[m.y].append(n[m.x].pop_back())
	return n


## Weighted A*. Returns an Array of Vector2i moves, or [] when nothing was found within budget.
func solve(budget := 6000, weight := 2.0) -> Array:
	var start := _copy(pegs)
	if _h(start) == 0:
		return []
	var heap: Array = []
	var parent := {}
	var best_g := {}
	var sk := _key(start)
	best_g[sk] = 0
	var counter := 0
	_hpush(heap, [float(_h(start)) * weight, counter, 0, start, sk])
	var expanded := 0
	while not heap.is_empty():
		var e: Array = _hpop(heap)
		var g: int = e[2]
		var s: Array = e[3]
		var k: String = e[4]
		if int(best_g.get(k, 1 << 30)) < g:
			continue
		expanded += 1
		if expanded > budget:
			return []
		for m in _moves(s):
			var n := _apply(s, m)
			var nk := _key(n)
			var ng := g + 1
			if ng >= int(best_g.get(nk, 1 << 30)):
				continue
			best_g[nk] = ng
			parent[nk] = [k, m]
			var hn := _h(n)
			if hn == 0:
				var path: Array = [m]
				var kk := k
				while parent.has(kk):
					path.append(parent[kk][1])
					kk = parent[kk][0]
				path.reverse()
				return path
			counter += 1
			_hpush(heap, [ng + hn * weight, counter, ng, n, nk])
	return []


static func _less(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return a[0] < b[0]
	return a[1] < b[1]


static func _hpush(h: Array, e: Array) -> void:
	h.append(e)
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if _less(h[i], h[p]):
			var tmp = h[i]
			h[i] = h[p]
			h[p] = tmp
			i = p
		else:
			break


static func _hpop(h: Array) -> Array:
	var top: Array = h[0]
	var last: Array = h.pop_back()
	if h.is_empty():
		return top
	h[0] = last
	var i := 0
	var n := h.size()
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var m := i
		if l < n and _less(h[l], h[m]):
			m = l
		if r < n and _less(h[r], h[m]):
			m = r
		if m == i:
			break
		var tmp = h[i]
		h[i] = h[m]
		h[m] = tmp
		i = m
	return top
