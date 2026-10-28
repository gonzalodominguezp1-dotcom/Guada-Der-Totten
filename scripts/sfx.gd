extends Node
## Sonidos del juego (autoload "Sfx"). Los .wav están en res://assets/sounds,
## generados con tools/make_sounds.py.

const DIR := "res://assets/sounds/"
var cache := {}
var pool_2d: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool_2d.append(p)


func get_stream(sound_name: String) -> AudioStream:
	if cache.has(sound_name):
		return cache[sound_name]
	var path := DIR + sound_name + ".wav"
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	cache[sound_name] = s
	return s


func play(sound_name: String, volume_db := 0.0, pitch := 1.0) -> AudioStreamPlayer:
	var s := get_stream(sound_name)
	if s == null:
		return null
	var player: AudioStreamPlayer = null
	for p in pool_2d:
		if not p.playing:
			player = p
			break
	if player == null:
		player = pool_2d[0]
	player.stream = s
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()
	return player


func play3d(sound_name: String, pos: Vector3, volume_db := 0.0, pitch := 1.0, max_dist := 40.0) -> void:
	var s := get_stream(sound_name)
	if s == null:
		return
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.max_distance = max_dist
	p.unit_size = 6.0
	tree.current_scene.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


## Reproductor 3D en bucle pegado a un nodo (zumbido de máquina, viento...)
func attach_loop(sound_name: String, parent: Node3D, volume_db := 0.0, max_dist := 12.0) -> AudioStreamPlayer3D:
	var s := get_stream(sound_name)
	if s == null:
		return null
	if s is AudioStreamWAV:
		var w: AudioStreamWAV = s.duplicate()
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
		s = w
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = volume_db
	p.max_distance = max_dist
	p.unit_size = 3.0
	parent.add_child(p)
	p.play()
	return p


func loop_2d(sound_name: String, volume_db := 0.0) -> AudioStreamPlayer:
	var s := get_stream(sound_name)
	if s == null:
		return null
	if s is AudioStreamWAV:
		var w: AudioStreamWAV = s.duplicate()
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
		s = w
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = volume_db
	add_child(p)
	p.play()
	return p
