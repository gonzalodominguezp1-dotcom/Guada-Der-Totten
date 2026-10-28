extends Node3D
## Arma de pared (como las de tiza de WaW): compra el arma o su munición.
## Eje local +Z = hacia fuera de la pared.

const Weapons = preload("res://scripts/weapons.gd")

var weapon_id := "escopeta"


func _ready() -> void:
	add_to_group("interactables")
	var info := Weapons.data(weapon_id)
	# silueta de tiza
	var chalk := StandardMaterial3D.new()
	chalk.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	chalk.albedo_color = Color(0.92, 0.92, 0.88, 0.85)
	chalk.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var outline := Weapons.build_model(weapon_id)
	outline.rotation = Vector3(0, PI * 0.5, 0)
	outline.scale = Vector3(1.0, 1.12, 1.12)
	outline.position = Vector3(0, 0, 0.005)
	add_child(outline)
	_set_mat(outline, chalk)
	outline.scale.x = 0.05
	# el arma de verdad, colgada delante de la tiza
	var model := Weapons.build_model(weapon_id)
	model.rotation = Vector3(0, PI * 0.5, 0)
	model.position = Vector3(0, -0.02, 0.06)
	add_child(model)
	var l := Label3D.new()
	l.text = "%s\n%d" % [info["name"].to_upper(), info["cost"]]
	l.font_size = 36
	l.pixel_size = 0.004
	l.modulate = Color(0.92, 0.92, 0.88)
	l.outline_size = 0
	l.position = Vector3(0, -0.24, 0.01)
	add_child(l)


func _set_mat(n: Node, m: Material) -> void:
	if n is MeshInstance3D:
		n.material_override = m
	for c in n.get_children():
		_set_mat(c, m)


func can_interact(player) -> bool:
	var to: Vector3 = player.global_position + Vector3(0, 1.2, 0) - global_position
	return to.length() < 1.9 and to.dot(global_transform.basis.z) > 0.0


func _ammo_cost() -> int:
	return int(Weapons.data(weapon_id)["cost"] / 2)


func get_prompt(player) -> String:
	var info := Weapons.data(weapon_id)
	if player.has_weapon(weapon_id):
		return "Mantén [F] para comprar munición de %s [Coste: %d]" % [info["name"], _ammo_cost()]
	return "Mantén [F] para comprar %s [Coste: %d]" % [info["name"], info["cost"]]


func is_hold() -> bool:
	return false


func interact(player) -> void:
	if player.busy():
		return
	var info := Weapons.data(weapon_id)
	if player.has_weapon(weapon_id):
		if player.ammo_full(weapon_id):
			return
		if not player.spend_points(_ammo_cost()):
			Sfx.play("deny", -6.0)
			return
		player.refill_ammo(weapon_id)
	else:
		if not player.spend_points(info["cost"]):
			Sfx.play("deny", -6.0)
			return
		player.give_weapon(weapon_id)
	Sfx.play("purchase", -4.0)
