extends Node3D
## Ventana con tablas (barricada). Los zombies arrancan las tablas desde
## fuera y entran; el jugador las vuelve a clavar desde dentro (+10 puntos).
## Eje local +Z = hacia fuera.

const MAX_BOARDS := 6
const REPAIR_TIME := 0.65

var width := 1.2
var height := 1.2
var boards: Array = []       # MeshInstance3D (null si está arrancada)
var board_rot: Array = []
var blocker: StaticBody3D
var repair_cd := 0.0
var board_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("barricades")
	board_mat = StandardMaterial3D.new()
	board_mat.albedo_color = Color(0.45, 0.33, 0.2)
	var fn := FastNoiseLite.new()
	fn.frequency = 0.08
	var nt := NoiseTexture2D.new()
	nt.noise = fn
	nt.width = 128
	nt.height = 128
	board_mat.albedo_texture = nt
	board_mat.uv1_scale = Vector3(4, 1, 1)
	board_mat.roughness = 0.9

	# Bloqueo físico del hueco (capa 8: frena jugador y zombies, no las balas)
	blocker = StaticBody3D.new()
	blocker.collision_layer = 8
	blocker.collision_mask = 0
	add_child(blocker)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width + 0.1, height + 0.1, 0.3)
	cs.shape = shape
	blocker.add_child(cs)

	var rng := RandomNumberGenerator.new()
	rng.seed = int(global_position.x * 13.0 + global_position.z * 7.0)
	for i in MAX_BOARDS:
		var bm := BoxMesh.new()
		bm.size = Vector3(width + 0.35, 0.16, 0.035)
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = board_mat
		var y := -height * 0.5 + 0.12 + i * (height - 0.2) / (MAX_BOARDS - 1)
		var rot := rng.randf_range(-0.28, 0.28)
		mi.position = Vector3(0, y, 0.16 + (i % 2) * 0.03)
		mi.rotation.z = rot
		add_child(mi)
		boards.append(mi)
		board_rot.append(Vector3(0, 0, rot))
	# marco de la ventana
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.25, 0.15, 0.08)
	for f in [[Vector3(0, height * 0.5 + 0.04, 0), Vector3(width + 0.16, 0.08, 0.26)],
			[Vector3(0, -height * 0.5 - 0.04, 0), Vector3(width + 0.16, 0.08, 0.3)],
			[Vector3(-width * 0.5 - 0.04, 0, 0), Vector3(0.08, height, 0.26)],
			[Vector3(width * 0.5 + 0.04, 0, 0), Vector3(0.08, height, 0.26)]]:
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = f[1]
		m.mesh = b
		m.material_override = frame
		m.position = f[0]
		add_child(m)


func _process(delta: float) -> void:
	repair_cd -= delta


func boards_left() -> int:
	var n := 0
	for b in boards:
		if b != null:
			n += 1
	return n


func is_open() -> bool:
	return boards_left() == 0


## Punto donde espera el zombie (fuera) y por donde sale (dentro)
func outside_point() -> Vector3:
	var p := to_global(Vector3(0, 0, 0.85))
	return Vector3(p.x, 0.05, p.z)


func inside_point() -> Vector3:
	var p := to_global(Vector3(0, 0, -0.95))
	return Vector3(p.x, 0.05, p.z)


func tear_board() -> bool:
	for i in range(boards.size() - 1, -1, -1):
		var b: MeshInstance3D = boards[i]
		if b == null:
			continue
		boards[i] = null
		var tw := create_tween()
		var target := b.position + Vector3(randf_range(-0.6, 0.6), -randf_range(0.6, 1.2), randf_range(0.9, 1.6))
		tw.tween_property(b, "position", target, 0.35).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(b, "rotation", Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-2, 2)), 0.35)
		tw.tween_interval(3.0)
		tw.tween_callback(b.queue_free)
		Sfx.play3d("board_break", global_position, -2.0)
		return true
	return false


func add_board() -> bool:
	for i in boards.size():
		if boards[i] != null:
			continue
		var bm := BoxMesh.new()
		bm.size = Vector3(width + 0.35, 0.16, 0.035)
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = board_mat
		add_child(mi)
		var y := -height * 0.5 + 0.12 + i * (height - 0.2) / (MAX_BOARDS - 1)
		var final_pos := Vector3(0, y, 0.16 + (i % 2) * 0.03)
		mi.position = final_pos + Vector3(0, 0.3, -1.2)
		mi.rotation = board_rot[i] + Vector3(0.8, 0, 0)
		var tw := create_tween()
		tw.tween_property(mi, "position", final_pos, 0.2).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(mi, "rotation", board_rot[i], 0.2)
		boards[i] = mi
		Sfx.play3d("board_place", global_position, -3.0)
		return true
	return false


# ---------------------------------------------------------------- interacción

func can_interact(player) -> bool:
	if boards_left() >= MAX_BOARDS:
		return false
	var lp := to_local(player.global_position)
	return lp.z < 0.0 and lp.z > -2.2 and absf(lp.x) < width * 0.5 + 1.0


func get_prompt(_player) -> String:
	return "Mantén [F] para reconstruir la barricada"


func is_hold() -> bool:
	return true


func interact(player) -> void:
	if repair_cd > 0.0:
		return
	# no se puede clavar con un zombie arrancando justo delante
	for z in get_tree().get_nodes_in_group("zombies"):
		if z.dead:
			continue
		if z.window == self and z.is_tearing():
			repair_cd = 0.3
			return
	if add_board():
		repair_cd = REPAIR_TIME
		player.add_points(10)
