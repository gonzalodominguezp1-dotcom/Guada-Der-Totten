extends StaticBody3D
## Puerta que se compra con puntos. Al abrirse deja de bloquear y avisa
## (señal opened) para recalcular la navegación y activar la nueva zona.

signal opened(door)

var cost := 750
var label := "abrir la puerta"
var size := Vector3(1.4, 2.2, 0.1)
var style := "wood"
var zone := ""
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
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.85, 0.85, 0.82)
	white.roughness = 0.45
	white.metallic = 0.3
	if style == "debris":
		_build_debris()
		return
	var n_leaves := 2 if style in ["double_glass", "gate"] else 1
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
		if style == "gate":
			# verja de forja blanca con marco rojo
			_part(leaf, Vector3(lw - 0.02, 0.06, 0.06), Vector3(0, size.y * 0.5 - 0.04, 0), red)
			_part(leaf, Vector3(lw - 0.02, 0.06, 0.06), Vector3(0, -size.y * 0.5 + 0.04, 0), red)
			_part(leaf, Vector3(lw - 0.02, 0.04, 0.04), Vector3(0, 0.0, 0), white)
			_part(leaf, Vector3(0.06, size.y, 0.06), Vector3(-dir * (lw * 0.5 - 0.03), 0, 0), red)
			_part(leaf, Vector3(0.06, size.y, 0.06), Vector3(dir * (lw * 0.5 - 0.03), 0, 0), red)
			var nb := int(lw / 0.11)
			for k in nb:
				_part(leaf, Vector3(0.022, size.y - 0.1, 0.022), Vector3(-lw * 0.5 + 0.08 + k * (lw - 0.16) / maxf(nb - 1, 1), 0, 0), white)
			leaves.append([hinge, dir])
			continue
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


## Montón de escombros con tablones y un cartel de "PELIGRO"
func _build_debris() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(global_position.x * 7.0 + global_position.z * 13.0)
	var root := Node3D.new()
	root.position.y = -size.y * 0.5
	add_child(root)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.45, 0.43, 0.40)
	stone.roughness = 0.95
	var brick := StandardMaterial3D.new()
	brick.albedo_color = Color(0.5, 0.26, 0.18)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.38, 0.27, 0.16)
	var x := -size.x * 0.5 + 0.3
	while x < size.x * 0.5 - 0.2:
		for k in 4:
			var s := Vector3(rng.randf_range(0.4, 1.1), rng.randf_range(0.3, 0.8), rng.randf_range(0.4, 1.0))
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = s
			mi.mesh = bm
			mi.material_override = stone if rng.randf() < 0.7 else brick
			mi.position = Vector3(x + rng.randf_range(-0.3, 0.3), s.y * 0.5 + k * 0.25, rng.randf_range(-0.4, 0.4))
			mi.rotation = Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4))
			root.add_child(mi)
		x += 0.9
	# valla de tablones clavados
	for k in 4:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(size.x, 0.22, 0.05)
		mi.mesh = bm
		mi.material_override = wood
		mi.position = Vector3(0, 1.1 + k * 0.45, 0.45)
		mi.rotation.z = rng.randf_range(-0.06, 0.06)
		root.add_child(mi)
	for xx in [-size.x * 0.5 + 0.2, 0.0, size.x * 0.5 - 0.2]:
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.12, 2.6, 0.12)
		post.mesh = pm
		post.material_override = wood
		post.position = Vector3(xx, 1.3, 0.48)
		root.add_child(post)
	var sign := Label3D.new()
	sign.text = "PELIGRO\nDERRUMBE"
	sign.font_size = 64
	sign.pixel_size = 0.005
	sign.modulate = Color(0.95, 0.8, 0.1)
	sign.outline_size = 12
	sign.position = Vector3(0, 1.9, 0.52)
	root.add_child(sign)
	var sign2 := sign.duplicate()
	sign2.position = Vector3(0, 1.9, -0.52)
	sign2.rotation.y = PI
	root.add_child(sign2)
	leaves.append([root, 0.0])


func _part(parent: Node3D, s: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


func can_interact(player) -> bool:
	if is_open:
		return false
	var lp := to_local(player.global_position)
	return absf(lp.x) < size.x * 0.5 + 0.3 and absf(lp.z) < size.z * 0.5 + 1.6


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
	if style == "debris":
		var root: Node3D = leaves[0][0]
		var tw0 := create_tween()
		tw0.tween_property(root, "position:y", root.position.y - 3.2, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw0.tween_callback(root.queue_free)
		Sfx.play3d("board_break", global_position, 0.0, 0.7)
	else:
		for l in leaves:
			var hinge: Node3D = l[0]
			var dir: float = l[1]
			var tw := create_tween()
			tw.tween_property(hinge, "rotation:y", dir * deg_to_rad(-105), 1.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	opened.emit(self)
