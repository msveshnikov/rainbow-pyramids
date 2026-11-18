extends Node
## Sound effects and music. All files are CC0, see assets/CREDITS.md.

const A := "res://assets/audio/"
const GROUPS := {
	"pop": ["pop.ogg"],
	"lift": ["lift.ogg"],
	"drop": ["drop_1.ogg", "drop_2.ogg", "drop_3.ogg", "drop_4.ogg"],
	"glass": ["glass_1.ogg"],
	"clink": ["glass_2.ogg", "glass_3.ogg", "glass_4.ogg", "glass_5.ogg", "glass_6.ogg"],
	"error": ["error.ogg", "error2.ogg"],
	"cancel": ["cancel.ogg"],
	"click": ["click.ogg"],
	"select": ["select.ogg"],
	"undo": ["undo.ogg"],
	"hint": ["hint.ogg"],
	"complete": ["complete.ogg"],
	"toggle": ["toggle.ogg"],
	"restart": ["restart.ogg"],
	"pluck": ["pluck1.ogg", "pluck2.ogg"],
	"powerup": ["powerup.ogg"],
	"star": ["star.ogg"],
	"sparkle": ["sparkle.ogg"],
	"win": ["win_vibraphone.ogg", "win_steeldrums.ogg", "win_pizzicato.ogg", "win_grandpiano.ogg",
		"win_fantasia.ogg", "win_doot.ogg"],
}

var streams := {}
var players: Array[AudioStreamPlayer] = []
var music: AudioStreamPlayer
var _next := 0
var _music_started := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for g in GROUPS:
		var arr: Array = []
		for f in GROUPS[g]:
			var s = load(A + f)
			if s:
				arr.append(s)
		streams[g] = arr
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	music = AudioStreamPlayer.new()
	add_child(music)
	var m = load(A + "music.mp3")
	if m:
		m.loop = true
		music.stream = m
	music.volume_db = -15.0


func play(name: String, pitch := 1.0, vol := 0.0) -> void:
	if not Game.save.sound:
		return
	var arr: Array = streams.get(name, [])
	if arr.is_empty():
		return
	var p: AudioStreamPlayer = null
	for i in players.size():
		var c := players[(_next + i) % players.size()]
		if not c.playing:
			p = c
			break
	if p == null:
		p = players[_next % players.size()]
	_next += 1
	p.stream = arr.pick_random()
	p.pitch_scale = clampf(pitch, 0.3, 4.0)
	p.volume_db = vol
	p.play()


## Browsers block audio until the first user gesture: call this from a button press.
func start_music() -> void:
	_music_started = true
	update_music()


func update_music() -> void:
	if music.stream == null:
		return
	if Game.save.music and _music_started:
		if not music.playing:
			music.play()
	else:
		music.stop()
