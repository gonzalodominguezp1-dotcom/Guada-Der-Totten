extends StaticBody3D
## Pack-a-Punch (provisional, en la plaza del Ayuntamiento): mejora el arma
## que llevas en la mano si tiene versión mejorada ("pap" en weapons.gd).
## Por ahora solo el Cañón de Zurraspa → Cañón de Zurraspa Dorado.
## Eje local +Z = lado desde el que se usa.

const Weapons = preload("res://scripts/weapons.gd")
const COST := 5000

var working := false
var ready_id := ""            # arma mejorada esperando a que la cojas
var shown: Node3D
var light: OmniLight3D
var t := 0.0


func _ready() -> void:
	add_to_group("interactables")
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(1.5, 1.6, 1.0)
	cs.shape = b
	cs.position.y = 0.8
	add_child(cs)
	var dark := _mat(Color(0.12, 0.08, 0.16), 0.5, 0.5)
	var purple := _mat(Color(0.35, 0.12, 0.55), 0.35, 0.4)
	var gold := _mat(Color(0.95, 0.72, 0.2), 0.25, 1.0)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.7, 0.3, 1.0)
	glow.emission_enabled = true
	glow.emission = Color(0.6, 0.25, 1.0)
	glow.emission_energy_multiplier = 2.5
	_part(Vector3(1.5, 1.0, 1.0), Vector3(0, 0.5, 0), dark)              # cuerpo
	_part(Vector3(1.56, 0.08, 1.06), Vector3(0, 0.04, 0), gold)          # zócalo
	_part(Vector3(1.4, 0.5, 0.9), Vector3(0, 1.25, -0.05), purple)       # cabezal
	_part(Vector3(1.0, 0.06, 0.06), Vector3(0, 1.0, 0.5), gold)          # boca
	_part(Vector3(0.9, 0.18, 0.04), Vector3(0, 1.3, 0.41), glow)         # cartel
	_part(Vector3(0.2, 0.2, 0.3), Vector3(-0.55, 1.6, -0.1), gold)       # chimeneas
	_part(Vector3(0.2, 0.3, 0.3), Vector3(0.55, 1.65, -0.1), gold)
	for x in [-0.6, 0.6]:
		_part(Vector3(0.08, 0.9, 0.08), Vector3(x, 0.5, 0.5), gold)
	# rodillos de la cinta
	for k in 5:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.05
		cm.height = 1.2
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = _mat(Color(0.3, 0.3, 0.32), 0.4, 0.8)
		mi.rotation.z = PI * 0.5
		mi.position = Vector3(0, 1.03, 0.15 + k * 0.1)
		add_child(mi)
	var l := Label3D.new()
	l.text = "PACK-A-PUNCH"
	l.font_size = 48
	l.pixel_size = 0.004
	l.modulate = Color(1.0, 0.9, 0.5)
	l.outline_size = 8
	l.outline_modulate = Color(0.2, 0.0, 0.3)
	l.position = Vector3(0, 1.3, 0.44)
	add_child(l)
	light = OmniLight3D.new()
	light.light_color = Color(0.7, 0.35, 1.0)
	light.light_energy = 1.0
	light.omni_range = 4.0
	light.position = Vector3(0, 1.4, 0.8)
	add_child(light)


func _mat(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _part(s: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)


func _process(delta: float) -> void:
	t += delta
	light.light_energy = 1.0 + (sin(t * 12.0) * 0.8 if working else sin(t * 2.0) * 0.2)
	if shown:
		shown.rotation.y += delta * (6.0 if working else 1.0)


func can_interact(player) -> bool:
	return to_local(player.global_position).length() < 2.4 and not working


func get_prompt(player) -> String:
	if ready_id != "":
		return "Pulsa [F] para coger el " + Weapons.data(ready_id)["name"]
	var up: String = player.wdata().get("pap", "")
	if up == "":
		return "Pack-a-Punch: este arma no se puede mejorar"
	return "Pulsa [F] para mejorar el arma [Coste: %d]" % COST


func is_hold() -> bool:
	return false


func interact(player) -> void:
	if ready_id != "":
		player.give_weapon(ready_id)
		if player.hud and ready_id == "zurraspa_pap":
			player.hud.announce("¡De la taza al apocalipsis!")
		ready_id = ""
		if shown:
			shown.queue_free()
			shown = null
		Sfx.play("powerup_grab", -2.0)
		return
	var id: String = player.weapon_id()
	var up: String = player.wdata().get("pap", "")
	if up == "" or not player.spend_points(COST):
		Sfx.play("deny", -8.0)
		return
	Sfx.play("purchase", -4.0)
	# el arma entra en la máquina
	player.take_weapon(id)
	working = true
	shown = Weapons.build_model(id)
	shown.scale = Vector3(2.0, 2.0, 2.0)
	shown.position = Vector3(0, 1.1, 0.3)
	add_child(shown)
	Sfx.play3d("machine_hum", global_position + Vector3.UP, -2.0)
	for k in 5:
		get_tree().create_timer(0.6 * k).timeout.connect(func(): Sfx.play3d("board_place", global_position + Vector3.UP, -4.0, randf_range(0.6, 0.9)))
	await get_tree().create_timer(3.2).timeout
	shown.queue_free()
	shown = Weapons.build_model(up)
	shown.scale = Vector3(2.0, 2.0, 2.0)
	shown.position = Vector3(0, 1.1, 0.3)
	add_child(shown)
	ready_id = up
	working = false
	Sfx.play("perk_jingle", -4.0, 1.4)
