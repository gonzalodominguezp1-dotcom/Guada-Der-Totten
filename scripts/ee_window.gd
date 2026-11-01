extends StaticBody3D
## Ventana de la Calle Artes 22 (easter egg): cuando llevas el Cañón de Zurraspa
## se ilumina; si le das un chorro de zurraspa, suelta el pepino.

const PartPickup = preload("res://scripts/part_pickup.gd")

var dead := false            # para que el cañón la trate como un objetivo más
var done := false
var lit := false
var glass_mat: StandardMaterial3D
var light: OmniLight3D
var t := 0.0


func _ready() -> void:
	add_to_group("ee_window")
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.2, 1.3, 0.3)
	cs.shape = sh
	add_child(cs)
	glass_mat = StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.08, 0.09, 0.1)
	glass_mat.roughness = 0.1
	glass_mat.emission = Color(1.0, 0.85, 0.35)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 1.1, 0.06)
	mi.mesh = bm
	mi.material_override = glass_mat
	add_child(mi)
	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.4)
	light.omni_range = 6.0
	light.light_energy = 0.0
	light.position = Vector3(0, 0, 0.8)
	add_child(light)


func _process(delta: float) -> void:
	t += delta
	if done:
		return
	var p = get_tree().get_first_node_in_group("player")
	var want: bool = p != null and (p.has_weapon("zurraspa") or p.has_weapon("zurraspa_pap"))
	if want != lit:
		lit = want
		glass_mat.emission_enabled = lit
	if lit:
		var e := 2.0 + sin(t * 3.0) * 0.8
		glass_mat.emission_energy_multiplier = e
		light.light_energy = e * 0.6


func take_hit(_dmg: float, _pos: Vector3, attacker, _melee := false) -> void:
	if done or not lit or attacker == null:
		return
	if not (attacker.weapon_id() in ["zurraspa", "zurraspa_pap"]):
		return
	done = true
	glass_mat.emission_enabled = false
	light.light_energy = 0.0
	Sfx.play3d("splat", global_position, 0.0, 0.8)
	var pk := PartPickup.new()
	pk.part = "pepino"
	get_tree().current_scene.add_child(pk)
	pk.global_position = global_transform * Vector3(0, -3.6, 2.2)
	if attacker.hud:
		attacker.hud.announce("¡Algo ha caído de la ventana!")


func apply_slip(_d: float) -> void:
	pass


func apply_dirty(_d: float) -> void:
	pass
