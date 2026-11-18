extends Node
## Global state: level list, save data, settings, UI strings.

const COLORS := [
	Color("f2141b"),  # red
	Color("ff6000"),  # orange
	Color("ffd91a"),  # yellow
	Color("8cf01e"),  # green
	Color("1cb6ff"),  # cyan
	Color("3a2cff"),  # blue
	Color("b235ff"),  # violet
]

## Which palette colours a level with n colours uses: few colours -> far apart hues,
## so e.g. orange and yellow only meet on boards that need six or seven colours.
const PALETTE_FOR := {
	1: [0],
	2: [0, 5],
	3: [0, 2, 5],
	4: [0, 2, 3, 5],
	5: [0, 2, 3, 4, 6],
	6: [0, 1, 2, 3, 5, 6],
	7: [0, 1, 2, 3, 4, 5, 6],
}

const SAVE_PATH := "user://save.json"

var levels: Array = []
var save := {
	"unlocked": 1,
	"stars": {},
	"best": {},
	"sound": true,
	"music": true,
	"lang": "",
}
var args: PackedStringArray = PackedStringArray()

const STR := {
	"title1": ["Радужные", "Rainbow"],
	"title2": ["пирамидки", "Pyramids"],
	"play": ["Играть", "Play"],
	"continue": ["Уровень %d", "Level %d"],
	"levels": ["Уровни", "Levels"],
	"level": ["Уровень %d", "Level %d"],
	"moves": ["Ходы: %d", "Moves: %d"],
	"par": ["цель %d", "target %d"],
	"great": ["Отлично!", "Great!"],
	"perfect": ["Идеально!", "Perfect!"],
	"done": ["Готово!", "Done!"],
	"next": ["Дальше", "Next"],
	"again": ["Ещё раз", "Replay"],
	"menu": ["Меню", "Menu"],
	"back": ["Назад", "Back"],
	"all_done": ["Все уровни пройдены!", "All levels complete!"],
	"tut1": ["Нажми на штифт — возьмёшь верхнее кольцо.\nНажми на другой — положишь его туда.",
		"Tap a peg to pick up its top ring.\nTap another peg to drop it there."],
	"tut2": ["Класть можно на пустой штифт\nили на кольцо того же цвета, но больше.",
		"Drop onto an empty peg, or onto\na bigger ring of the same colour."],
	"goal": ["Собери каждый цвет в пирамидку:\nот большого кольца к маленькому.",
		"Stack every colour into a pyramid:\nbiggest ring at the bottom."],
	"bad_color": ["Только на кольцо того же цвета!", "Same colour only!"],
	"bad_size": ["Сверху — только кольцо поменьше!", "Only a smaller ring can go on top!"],
	"bad_full": ["Штифт заполнен!", "This peg is full!"],
	"hint_undo": ["Отсюда не выбраться — отмени пару ходов", "Stuck here — undo a couple of moves"],
	"stuck": ["Ходов больше нет. Отмени ход или начни заново", "No moves left. Undo or restart"],
	"pyramid": ["Пирамидка!", "Pyramid!"],
	"best": ["рекорд %d", "best %d"],
	"new_best": ["Новый рекорд!", "New best!"],
	"credits": ["Музыка: Suno · Звуки: Kenney, rubberduck, Fupi, farfadet46 (CC0)", "Music: Suno · Sounds: Kenney, rubberduck, Fupi, farfadet46 (CC0)"],
}


func _ready() -> void:
	args = OS.get_cmdline_user_args()
	_load_levels()
	_load_save()
	if save.lang == "":
		save.lang = "ru" if OS.get_locale_language() == "ru" else "en"
	if has_arg("--lang"):
		save.lang = arg_value("--lang", save.lang)


func palette_for(n: int) -> Array:
	return PALETTE_FOR.get(clampi(n, 1, 7), PALETTE_FOR[7])


func t(key: String) -> String:
	var pair: Array = STR.get(key, [key, key])
	return pair[0] if save.lang == "ru" else pair[1]


func has_arg(a: String) -> bool:
	return args.has(a)


func arg_value(a: String, def := "") -> String:
	var i := args.find(a)
	if i >= 0 and i + 1 < args.size():
		return args[i + 1]
	return def


func _load_levels() -> void:
	var f := FileAccess.open("res://assets/levels/levels.json", FileAccess.READ)
	if f == null:
		push_error("levels.json missing")
		return
	var d = JSON.parse_string(f.get_as_text())
	levels = d.levels


func level_count() -> int:
	return levels.size()


func get_level(idx: int) -> Dictionary:
	return levels[clampi(idx, 0, levels.size() - 1)]


func stars_for(id: int) -> int:
	return int(save.stars.get(str(id), 0))


func best_for(id: int) -> int:
	return int(save.best.get(str(id), 0))


func total_stars() -> int:
	var n := 0
	for k in save.stars:
		n += int(save.stars[k])
	return n


func record_win(id: int, moves: int, stars: int) -> bool:
	var key := str(id)
	var new_best := false
	if not save.best.has(key) or moves < int(save.best[key]):
		save.best[key] = moves
		new_best = save.stars.has(key)
	save.stars[key] = maxi(stars, stars_for(id))
	save.unlocked = maxi(int(save.unlocked), mini(id + 1, levels.size()))
	write_save()
	return new_best


static func stars_from(moves: int, par: int) -> int:
	if moves <= par:
		return 3
	if moves <= int(ceil(par * 1.35)) + 1:
		return 2
	return 1


func _load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		for k in d:
			save[k] = d[k]


func write_save() -> void:
	if has_arg("--autotest") or has_arg("--storeshots") or has_arg("--playtest"):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(save))
