extends StaticBody3D
## Máquina de perks. Por ahora: Quick Revive (en solitario te levanta
## sola cuando caes, hasta 3 veces por partida).

const PERKS := {
	"quick_revive": {"name": "Quick Revive", "cost": 500, "color": Color(0.35, 0.75, 1.0)},
}

var perk := "quick_revive"
var jingle_cd := 20.0
var light: OmniLight3D


func _ready() -> void:
	add_to_group("interactables")
	var info: Dictionary = PERKS[perk]
	var c: Color = info["color"]
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(0.95, 2.15, 0.8)
	cs.shape = b
	cs.position.y = 1.075
	add_child(cs)

	var body := _mat(Color(0.82, 0.88, 0.92), 0.35, 0.3)
	var trim := _mat(Color(0.12, 0.13, 0.16), 0.4, 0.7)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = c
	glow.emission_enabled = true
	glow.emission = c
	glow.emission_energy_multiplier = 2.2
	var white_glow := StandardMaterial3D.new()
	white_glow.albedo_color = Color.WHITE
	white_glow.emission_enabled = true
	white_glow.emission = Color(1, 1, 1)
	white_glow.emission_energy_multiplier = 3.0
	var rust := _mat(Color(0.35, 0.2, 0.12), 0.9)

	_part(Vector3(0.9, 1.95, 0.72), Vector3(0, 0.975, 0), body)          # carcasa
	_part(Vector3(0.96, 0.12, 0.78), Vector3(0, 0.06, 0), trim)          # zócalo
	_part(Vector3(0.96, 0.08, 0.78), Vector3(0, 1.99, 0), trim)          # remate
	_part(Vector3(0.78, 0.36, 0.06), Vector3(0, 1.72, 0.36), glow)        # cartel luminoso
	_part(Vector3(0.7, 0.9, 0.04), Vector3(0, 1.0, 0.37), _mat(c.darkened(0.45), 0.3, 0.2))   # panel frontal
	# cruz emblema
	_part(Vector3(0.14, 0.5, 0.03), Vector3(0, 1.05, 0.4), white_glow)
	_part(Vector3(0.5, 0.14, 0.03), Vector3(0, 1.05, 0.4), white_glow)
	_part(Vector3(0.42, 0.14, 0.12), Vector3(0, 0.35, 0.35), trim)        # boca de dispensado
	_part(Vector3(0.06, 0.12, 0.02), Vector3(0.3, 0.62, 0.37), trim)      # ranura de monedas
	# óxido y golpes
	_part(Vector3(0.3, 0.2, 0.01), Vector3(-0.32, 0.25, 0.365), rust)
	_part(Vector3(0.01, 0.4, 0.2), Vector3(0.455, 0.4, 0.1), rust)
	# bombillas del cartel
	var bulb := StandardMaterial3D.new()
	bulb.albedo_color = Color(1, 0.9, 0.6)
	bulb.emission_enabled = true
	bulb.emission = Color(1, 0.85, 0.5)
	bulb.emission_energy_multiplier = 4.0
	for k in 7:
		var sm := SphereMesh.new()
		sm.radius = 0.025
		sm.height = 0.05
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		mi.material_override = bulb
		mi.position = Vector3(-0.36 + k * 0.12, 1.94, 0.38)
		add_child(mi)

	var l := Label3D.new()
	l.text = info["name"].to_upper()
	l.font_size = 56
	l.pixel_size = 0.0042
	l.modulate = Color(1, 1, 1)
	l.outline_modulate = c.darkened(0.6)
	l.outline_size = 10
	l.position = Vector3(0, 1.72, 0.395)
	add_child(l)

	light = OmniLight3D.new()
	light.light_color = c
	light.light_energy = 1.4
	light.omni_range = 4.5
	light.position = Vector3(0, 1.6, 0.9)
	add_child(light)
	Sfx.attach_loop("machine_hum", self, -14.0, 8.0)


func _mat(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
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
	light.light_energy = 1.4 + sin(Time.get_ticks_msec() * 0.003) * 0.15
	jingle_cd -= delta
	if jingle_cd <= 0.0:
		jingle_cd = randf_range(40.0, 80.0)
		var players := get_tree().get_nodes_in_group("player")
		if not players.is_empty() and players[0].global_position.distance_to(global_position) < 14.0:
			Sfx.play3d("perk_jingle", global_position + Vector3(0, 1.5, 0), -6.0, 1.0, 18.0)


func can_interact(player) -> bool:
	var to: Vector3 = player.global_position - global_position
	return to.length() < 2.0 and to.dot(global_transform.basis.z) > 0.0


func get_prompt(player) -> String:
	var info: Dictionary = PERKS[perk]
	if player.has_perk(perk):
		return "Ya tienes %s" % info["name"]
	if perk == "quick_revive" and player.quick_revive_bought >= 3:
		return "%s agotado" % info["name"]
	return "Mantén [F] para comprar %s [Coste: %d]" % [info["name"], info["cost"]]


func is_hold() -> bool:
	return false


func interact(player) -> void:
	var info: Dictionary = PERKS[perk]
	if player.has_perk(perk) or player.busy():
		return
	if perk == "quick_revive" and player.quick_revive_bought >= 3:
		Sfx.play("deny", -6.0)
		return
	if not player.spend_points(info["cost"]):
		Sfx.play("deny", -6.0)
		return
	Sfx.play3d("purchase", global_position, -2.0)
	Sfx.play3d("perk_jingle", global_position + Vector3(0, 1.5, 0), -4.0, 1.0, 18.0)
	jingle_cd = 60.0
	if perk == "quick_revive":
		player.quick_revive_bought += 1
	player.drink_perk(perk)
