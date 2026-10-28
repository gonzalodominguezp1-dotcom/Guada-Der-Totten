extends Node3D
## Proyectil del Cañón de Zurraspa: un pegote de batido de chocolate que
## revienta al chocar y mata a los zombies de alrededor.

var velocity := Vector3.ZERO
var shooter
var damage := 1400.0
var splash := 2.8
var life := 3.0
var exclude: Array = []

static var _splat_tex: GradientTexture2D


func _ready() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.28, 0.15, 0.06)
	m.roughness = 0.15
	m.emission_enabled = true
	m.emission = Color(0.35, 0.18, 0.05)
	m.emission_energy_multiplier = 0.6
	var blob := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.08
	sm.height = 0.16
	blob.mesh = sm
	blob.material_override = m
	blob.scale = Vector3(1, 1, 1.6)
	add_child(blob)
	var trail := CPUParticles3D.new()
	trail.amount = 24
	trail.lifetime = 0.35
	trail.local_coords = false
	trail.direction = Vector3.UP
	trail.spread = 180.0
	trail.initial_velocity_min = 0.2
	trail.initial_velocity_max = 0.8
	trail.gravity = Vector3(0, -6, 0)
	var dm := SphereMesh.new()
	dm.radius = 0.025
	dm.height = 0.05
	dm.material = m
	trail.mesh = dm
	add_child(trail)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.3)
	l.light_energy = 0.8
	l.omni_range = 2.5
	add_child(l)
	if velocity.length() > 0.01:
		look_at(global_position + velocity, Vector3.UP)


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	velocity.y -= 3.0 * delta
	var from := global_position
	var to := from + velocity * delta
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4 | 16, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		global_position = to
		return
	_burst(hit["position"], hit["normal"], hit["collider"])


func _burst(pos: Vector3, normal: Vector3, direct) -> void:
	var hit_ids := {}
	if direct and direct.has_method("take_hit") and not direct.dead:
		direct.take_hit(damage, pos, shooter)
		hit_ids[direct.get_instance_id()] = true
	for z in get_tree().get_nodes_in_group("zombies"):
		if z.dead or hit_ids.has(z.get_instance_id()):
			continue
		var d: float = z.global_position.distance_to(pos)
		if d < splash:
			z.take_hit(damage * (1.0 - d / splash * 0.5), z.global_position + Vector3(0, 1.0, 0), shooter)
	Sfx.play3d("splat", pos, 0.0, randf_range(0.9, 1.1))
	# salpicadura
	var p := CPUParticles3D.new()
	p.amount = 40
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.8
	p.direction = normal
	p.spread = 70.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.26, 0.13, 0.05)
	m.roughness = 0.2
	var dm := SphereMesh.new()
	dm.radius = 0.04
	dm.height = 0.08
	dm.material = m
	p.mesh = dm
	get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)
	# mancha
	if _splat_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(0.22, 0.11, 0.04, 1.0))
		g.add_point(0.55, Color(0.25, 0.13, 0.05, 0.9))
		g.set_color(1, Color(0.25, 0.13, 0.05, 0.0))
		_splat_tex = GradientTexture2D.new()
		_splat_tex.gradient = g
		_splat_tex.fill = GradientTexture2D.FILL_RADIAL
		_splat_tex.fill_from = Vector2(0.5, 0.5)
		_splat_tex.fill_to = Vector2(0.5, 0.0)
	var dec := Decal.new()
	dec.texture_albedo = _splat_tex
	dec.size = Vector3(1.2, 0.6, 1.2)
	dec.cull_mask = 1
	get_tree().current_scene.add_child(dec)
	var n := normal if absf(normal.dot(Vector3.UP)) < 0.999 else (normal + Vector3(0.001, 0, 0)).normalized()
	dec.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, n)).rotated(n, randf() * TAU), pos)
	get_tree().create_timer(25.0).timeout.connect(dec.queue_free)
	queue_free()
