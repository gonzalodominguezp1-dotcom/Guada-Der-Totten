extends StaticBody3D
## Mesa de trabajo de la plaza del Ayuntamiento: con las 3 piezas se monta
## el Cañón de Zurraspa. Eje local +Z = lado desde el que se usa.

const Weapons = preload("res://scripts/weapons.gd")
const PARTS := ["calzoncillo", "tele", "canon"]

var game
var built := false
var taken := false
var building := false
var shown := {}
var weapon_model: Node3D


func _ready() -> void:
	add_to_group("interactables")
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.9, 0.95, 0.9)
	cs.shape = sh
	cs.position.y = 0.475
	add_child(cs)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.40, 0.27, 0.15)
	wood.roughness = 0.8
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.12, 0.13)
	dark.metallic = 0.6
	dark.roughness = 0.4
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.25, 0.4, 0.75)
	_part(Vector3(1.9, 0.08, 0.9), Vector3(0, 0.91, 0), wood)
	for x in [-0.85, 0.85]:
		for z in [-0.38, 0.38]:
			_part(Vector3(0.08, 0.87, 0.08), Vector3(x, 0.435, z), wood)
	_part(Vector3(1.7, 0.04, 0.7), Vector3(0, 0.25, 0), wood)
	_part(Vector3(0.22, 0.14, 0.12), Vector3(0.75, 1.02, -0.3), dark)          # tornillo de banco
	_part(Vector3(0.7, 0.01, 0.5), Vector3(-0.35, 0.955, 0.05), paper)          # plano
	var l := Label3D.new()
	l.text = "PLANO:\nCAÑÓN DE ZURRASPA"
	l.font_size = 36
	l.pixel_size = 0.0035
	l.modulate = Color(0.95, 0.95, 1.0)
	l.rotation.x = -PI * 0.5
	l.position = Vector3(-0.35, 0.962, 0.05)
	add_child(l)
	# martillo y llave inglesa
	_part(Vector3(0.3, 0.025, 0.03), Vector3(0.35, 0.965, 0.25), wood)
	_part(Vector3(0.05, 0.04, 0.1), Vector3(0.5, 0.97, 0.25), dark)
	_part(Vector3(0.25, 0.02, 0.04), Vector3(0.1, 0.96, -0.3), dark)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.85, 0.6)
	lamp.light_energy = 1.0
	lamp.omni_range = 4.0
	lamp.position = Vector3(0, 2.0, 0.3)
	add_child(lamp)


func _part(s: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)


func _process(_d: float) -> void:
	# las piezas conseguidas aparecen encima de la mesa
	if game == null or built:
		return
	var i := 0
	for p in PARTS:
		if game.parts.get(p, false) and not shown.has(p):
			var m := Weapons.part_model(p, 0.8)
			m.position = Vector3(-0.6 + i * 0.6, 1.08, -0.15)
			add_child(m)
			shown[p] = m
		i += 1


func _count() -> int:
	var n := 0
	for p in PARTS:
		if game and game.parts.get(p, false):
			n += 1
	return n


func can_interact(player) -> bool:
	var lp := to_local(player.global_position)
	return lp.length() < 2.3 and not taken and not building


func get_prompt(_player) -> String:
	if built:
		return "Mantén [F] para coger el Cañón de Zurraspa"
	var n := _count()
	if n < PARTS.size():
		return "Mesa de trabajo: te faltan piezas (%d/3)" % n
	return "Mantén [F] para montar el Cañón de Zurraspa"


func is_hold() -> bool:
	return false


func interact(player) -> void:
	if built:
		taken = true
		player.give_weapon("zurraspa")
		if weapon_model:
			weapon_model.queue_free()
		if player.hud:
			player.hud.announce("¡CAÑÓN DE ZURRASPA!")
		Sfx.play("powerup_grab", -2.0)
		return
	if _count() < PARTS.size():
		Sfx.play("deny", -8.0)
		return
	building = true
	for k in 4:
		get_tree().create_timer(0.35 * k).timeout.connect(func(): Sfx.play3d("board_place", global_position + Vector3(0, 1, 0), -2.0, randf_range(0.8, 1.2)))
	await get_tree().create_timer(1.8).timeout
	for p in shown:
		shown[p].queue_free()
	shown.clear()
	weapon_model = Weapons.build_model("zurraspa")
	weapon_model.scale = Vector3(2.2, 2.2, 2.2)
	weapon_model.position = Vector3(0, 1.15, 0)
	weapon_model.rotation.y = PI * 0.5
	add_child(weapon_model)
	built = true
	building = false
	Sfx.play("perk_jingle", -6.0, 1.3)
