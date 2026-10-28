extends Node3D
## Pieza del Cañón de Zurraspa tirada por el mapa. Brilla un poco y gira.

const Weapons = preload("res://scripts/weapons.gd")
const NAMES := {"calzoncillo": "el calzoncillo sucio", "tele": "la tele de tubo", "canon": "el cañón"}

var part := "calzoncillo"
var model: Node3D
var t := 0.0


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("parts")
	model = Weapons.part_model(part, 1.0)
	add_child(model)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.75, 0.35)
	l.light_energy = 0.7
	l.omni_range = 2.2
	l.position.y = 0.4
	add_child(l)
	var p := CPUParticles3D.new()
	p.amount = 10
	p.lifetime = 1.6
	p.direction = Vector3.UP
	p.spread = 30.0
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.3
	p.gravity = Vector3.ZERO
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.25
	var sm := SphereMesh.new()
	sm.radius = 0.008
	sm.height = 0.016
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.4)
	sm.material = mat
	p.mesh = sm
	add_child(p)


func _process(delta: float) -> void:
	t += delta
	model.rotation.y += delta * 0.6
	model.position.y = 0.05 + sin(t * 2.0) * 0.03


func can_interact(player) -> bool:
	return player.global_position.distance_to(global_position) < 1.9


func get_prompt(_player) -> String:
	return "Mantén [F] para coger " + NAMES.get(part, part)


func is_hold() -> bool:
	return false


func interact(player) -> void:
	if player.game:
		player.game.collect_part(part)
	Sfx.play("part_pickup", -2.0)
	queue_free()
