extends Area3D
## Avalancha del Cañón de Zurraspa Dorado (diseño del colega de Gonzalo,
## adaptado al juego): una ola dorada que avanza por el suelo, atraviesa a
## todos los zombies que pilla y va dejando charcos. Se para contra las paredes.

var shooter
var data: Dictionary
var direction := Vector3.FORWARD
var instakill := false

var _travelled := 0.0
var _since_puddle := 0.0
var _hit := {}
var _size := Vector3(5.0, 3.0, 1.5)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 4   # zombies
	monitoring = true
	monitorable = false
	_size = Vector3(data["wave_width"], data["wave_height"], 1.5)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = _size
	shape.shape = box
	shape.position.y = _size.y * 0.5
	add_child(shape)

	var gold := Color(1.0, 0.78, 0.18)
	# cresta de la ola: espuma dorada + gotas
	var foam := CPUParticles3D.new()
	foam.amount = 90
	foam.lifetime = 0.7
	foam.local_coords = false
	foam.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	foam.emission_box_extents = Vector3(_size.x * 0.5, 0.2, 0.4)
	foam.position.y = 0.3
	foam.direction = Vector3(0, 1, -0.6)
	foam.spread = 25.0
	foam.initial_velocity_min = 2.5
	foam.initial_velocity_max = 5.0
	foam.gravity = Vector3(0, -9.8, 0)
	foam.scale_amount_min = 0.7
	foam.scale_amount_max = 2.2
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	sm.radial_segments = 6
	sm.rings = 3
	var fm := StandardMaterial3D.new()
	fm.albedo_color = gold
	fm.roughness = 0.15
	fm.metallic = 0.4
	fm.emission_enabled = true
	fm.emission = gold
	fm.emission_energy_multiplier = 0.8
	sm.material = fm
	foam.mesh = sm
	add_child(foam)
	# cuerpo de la ola: un rulo semitransparente
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.7
	cm.bottom_radius = 0.7
	cm.height = _size.x
	cm.radial_segments = 12
	body.mesh = cm
	body.rotation.z = PI * 0.5
	body.position = Vector3(0, 0.55, 0)
	body.scale = Vector3(1.0, 1.0, 1.0)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(gold.r, gold.g * 0.85, gold.b, 0.55)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.emission_enabled = true
	bm.emission = gold
	bm.emission_energy_multiplier = 1.0
	bm.roughness = 0.1
	body.material_override = bm
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body)
	var l := OmniLight3D.new()
	l.light_color = gold
	l.light_energy = 1.5
	l.omni_range = 5.0
	l.position.y = 1.0
	add_child(l)


func _physics_process(delta: float) -> void:
	var step: float = float(data["wave_speed"]) * delta
	# ¿pared delante? (a media altura, para que bordillos y escalones no la paren)
	var from := global_position + Vector3.UP * 1.0
	var q := PhysicsRayQueryParameters3D.create(from, from + direction * (step + 0.8), 1 | 16)
	var wall := get_world_3d().direct_space_state.intersect_ray(q)
	global_position += direction * step
	_travelled += step
	_since_puddle += step

	for body in get_overlapping_bodies():
		if _hit.has(body) or not body.is_in_group("zombies") or body.dead:
			continue
		_hit[body] = true
		if is_instance_valid(shooter):
			shooter.zurraspa_hit(body, 999999.0 if instakill else float(data["damage"]),
				body.global_position + Vector3.UP * 1.0, data)

	if _since_puddle >= float(data["wave_spacing"]) and is_instance_valid(shooter):
		_since_puddle = 0.0
		shooter.spawn_puddle(global_position, data, true)

	if not wall.is_empty() or _travelled >= float(data["range"]):
		set_physics_process(false)
		monitoring = false
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector3(1.0, 0.05, 1.0), 0.3)
		tw.tween_callback(queue_free)
