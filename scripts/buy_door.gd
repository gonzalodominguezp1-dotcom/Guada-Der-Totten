extends StaticBody3D
## Puerta que se compra con puntos. Al abrirse deja de bloquear y avisa
## (señal opened) para recalcular la navegación y activar la nueva zona.

signal opened(door)

var cost := 750
var label := "abrir la puerta"
var size := Vector3(1.4, 2.2, 0.1)
var style := "wood"
var is_open := false
var shape_node: CollisionShape3D
var leaves: Array = []


func _ready() -> void:
	add_to_group("interactables")
	# capa 16: bloquea al jugador y a los zombies, pero no cuenta para la
	# malla de navegación (así no hay que recalcularla al abrir)
	collision_layer = 16
	collision_mask = 0
	shape_node = CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	shape_node.shape = b
	add_child(shape_node)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.32, 0.18, 0.09)
	wood.roughness = 0.6
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.5, 0.06, 0.05)
	red.roughness = 0.5
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.5, 0.6, 0.65, 0.35)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.8, 0.62, 0.25)
	brass.metallic = 1.0
	brass.roughness = 0.3
	var n_leaves := 2 if style == "double_glass" else 1
	var lw := size.x / n_leaves
	for i in n_leaves:
		var hinge := Node3D.new()
		var hx := -size.x * 0.5 if i == 0 else size.x * 0.5
		hinge.position = Vector3(hx, 0, 0)
		add_child(hinge)
		var dir := 1.0 if i == 0 else -1.0
		var leaf := Node3D.new()
		leaf.position = Vector3(dir * lw * 0.5, 0, 0)
		hinge.add_child(leaf)
		_part(leaf, Vector3(lw - 0.02, size.y - 0.02, size.z), Vector3.ZERO, red if style == "double_glass" else wood)
		if style == "double_glass":
			_part(leaf, Vector3(lw - 0.2, size.y * 0.55, size.z + 0.01), Vector3(0, 0.25, 0), glass)
			for k in 3:
				_part(leaf, Vector3(lw - 0.2, 0.025, size.z + 0.02), Vector3(0, 0.25 - size.y * 0.27 + k * size.y * 0.27, 0), red)
		else:
			for k in 4:
				_part(leaf, Vector3(lw - 0.15, 0.03, size.z + 0.02), Vector3(0, -0.8 + k * 0.55, 0), wood)
		_part(leaf, Vector3(0.03, 0.12, 0.06), Vector3(-dir * (lw * 0.5 - 0.1), -0.05, 0.05), brass)
		leaves.append([hinge, dir])


func _part(parent: Node3D, s: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


func can_interact(player) -> bool:
	return not is_open and global_position.distance_to(player.global_position + Vector3(0, 1.0, 0)) < 2.3


func get_prompt(_player) -> String:
	return "Mantén [F] para %s [Coste: %d]" % [label, cost]


func is_hold() -> bool:
	return false


func interact(player) -> void:
	if is_open:
		return
	if not player.spend_points(cost):
		Sfx.play("deny", -6.0)
		return
	open_door()


func open_door() -> void:
	is_open = true
	collision_layer = 0
	shape_node.disabled = true
	remove_child(shape_node)
	shape_node.queue_free()
	remove_from_group("interactables")
	Sfx.play3d("purchase", global_position, -2.0)
	Sfx.play3d("door_open", global_position, 0.0)
	for l in leaves:
		var hinge: Node3D = l[0]
		var dir: float = l[1]
		var tw := create_tween()
		tw.tween_property(hinge, "rotation:y", dir * deg_to_rad(-105), 1.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	opened.emit(self)
