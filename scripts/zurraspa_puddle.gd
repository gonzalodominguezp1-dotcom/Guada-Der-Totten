extends Area3D
## Charco de zurraspa (diseño del colega de Gonzalo, adaptado al juego).
## Los zombies que lo pisan resbalan, se "sienten sucios" y reciben daño continuo.
## Lo dejan el Cañón de Zurraspa (al impactar) y su versión mejorada (la avalancha).

const MAX_PUDDLES := 24   # los más viejos desaparecen para no cargar el PC

static var _alive: Array = []
static var _tex: GradientTexture2D

var radius := 1.8
var lifetime := 10.0
var damage_per_second := 15.0
var slip_duration := 2.0
var dirty_duration := 5.0
var color := Color(0.30, 0.16, 0.06, 0.92)
var glow := false          # true en la versión dorada
var shooter = null         # quien se lleva los puntos si el charco mata

var _mat: StandardMaterial3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 4     # zombies
	monitoring = true
	monitorable = false
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 1.5
	shape.shape = cyl
	shape.position.y = 0.75
	add_child(shape)

	if _tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.add_point(0.6, Color(1, 1, 1, 0.95))
		g.add_point(0.85, Color(1, 1, 1, 0.5))
		g.set_color(1, Color(1, 1, 1, 0))
		_tex = GradientTexture2D.new()
		_tex.gradient = g
		_tex.fill = GradientTexture2D.FILL_RADIAL
		_tex.fill_from = Vector2(0.5, 0.5)
		_tex.fill_to = Vector2(0.5, 0.0)
		_tex.width = 128
		_tex.height = 128
	var quad := PlaneMesh.new()
	quad.size = Vector2(radius * 2.0, radius * 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.position.y = 0.03
	mi.rotation.y = randf() * TAU
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = StandardMaterial3D.new()
	_mat.albedo_texture = _tex
	_mat.albedo_color = color
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.roughness = 0.08
	_mat.metallic = 0.3
	if glow:
		_mat.emission_enabled = true
		_mat.emission = Color(color.r, color.g, color.b)
		_mat.emission_energy_multiplier = 1.5
	mi.material_override = _mat
	add_child(mi)

	# aparece creciendo y se desvanece al final de su vida
	scale = Vector3(0.1, 1.0, 0.1)
	create_tween().tween_property(self, "scale", Vector3.ONE, 0.3)
	var life := create_tween()
	life.tween_interval(maxf(lifetime - 1.0, 0.1))
	life.tween_property(_mat, "albedo_color:a", 0.0, 1.0)
	life.tween_callback(queue_free)

	_alive.append(self)
	while _alive.size() > MAX_PUDDLES:
		var old = _alive.pop_front()
		if is_instance_valid(old):
			old.queue_free()


func _exit_tree() -> void:
	_alive.erase(self)


func _physics_process(delta: float) -> void:
	for body in get_overlapping_bodies():
		if not body.is_in_group("zombies") or body.dead:
			continue
		body.apply_slip(slip_duration)
		body.apply_dirty(dirty_duration)
		body.take_damage(damage_per_second * delta, shooter if is_instance_valid(shooter) else null)
