extends Node3D
## Portal (como los de Zombies in Spaceland): une el instituto con el tanatorio.
## El del instituto se activa pagando; a partir de ahí los dos funcionan y basta
## con meterse en el vórtice. Eje local +Z = lado por el que se entra y se sale.

signal activated

const SHADER = preload("res://shaders/portal.gdshader")
const COST := 1500
const COOLDOWN := 3.0

var town
var game
var other                   # el portal del otro lado
var label_text := ""        # adónde lleva (cartel de encima)
var master := false         # el del instituto: es el que se compra
var active := false
var cd := 0.0
var disc_mat: ShaderMaterial
var light: OmniLight3D
var hum: AudioStreamPlayer3D
var area: Area3D


func _ready() -> void:
	add_to_group("portals")
	if master:
		add_to_group("interactables")
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.2, 0.2, 0.23)
	metal.metallic = 0.8
	metal.roughness = 0.35
	var neon_a := _neon(Color(1.0, 0.25, 0.75))
	var neon_b := _neon(Color(0.2, 0.9, 1.0))
	# anillo, tubos de neón y peana
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.32
	tm.outer_radius = 1.6
	tm.rings = 48
	ring.mesh = tm
	ring.material_override = metal
	ring.rotation.x = PI * 0.5
	ring.position.y = 1.75
	add_child(ring)
	for k in 2:
		var t := MeshInstance3D.new()
		var tt := TorusMesh.new()
		tt.inner_radius = 1.6 if k == 0 else 1.26
		tt.outer_radius = 1.66 if k == 0 else 1.32
		tt.rings = 48
		t.mesh = tt
		t.material_override = neon_a if k == 0 else neon_b
		t.rotation.x = PI * 0.5
		t.position = Vector3(0, 1.75, 0.08)
		add_child(t)
	_box(Vector3(2.6, 0.25, 1.2), Vector3(0, 0.125, 0), metal)
	for x in [-1.25, 1.25]:
		_box(Vector3(0.3, 1.0, 0.5), Vector3(x, 0.6, 0), metal)
		_box(Vector3(0.06, 0.8, 0.06), Vector3(x, 0.65, 0.27), neon_b)
	# vórtice
	disc_mat = ShaderMaterial.new()
	disc_mat.shader = SHADER
	var disc := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2.7, 2.7)
	disc.mesh = qm
	disc.material_override = disc_mat
	disc.position.y = 1.75
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	# cartel de destino
	if label_text != "":
		var l := Label3D.new()
		l.text = label_text
		l.font_size = 64
		l.pixel_size = 0.006
		l.modulate = Color(0.4, 1.0, 0.95)
		l.outline_size = 10
		l.outline_modulate = Color(0.4, 0.0, 0.5)
		l.position = Vector3(0, 3.75, 0.1)
		l.double_sided = false
		add_child(l)
	light = OmniLight3D.new()
	light.light_color = Color(0.7, 0.4, 1.0)
	light.omni_range = 7.0
	light.position = Vector3(0, 1.75, 1.0)
	add_child(light)
	# zona de entrada
	area = Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	area.monitoring = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 2.6, 0.8)
	cs.shape = box
	cs.position = Vector3(0, 1.4, 0.1)
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_body)
	_set_power(false)


func _neon(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 2.5
	return m


func _box(s: Vector3, pos: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	add_child(body)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	mi.material_override = mat
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = s
	cs.shape = sh
	body.add_child(cs)


func _set_power(on: bool) -> void:
	active = on
	disc_mat.set_shader_parameter("power", 1.0 if on else 0.0)
	light.light_energy = 2.0 if on else 0.3
	if on and hum == null:
		hum = Sfx.attach_loop("machine_hum", self, -6.0, 10.0)


func _process(delta: float) -> void:
	cd -= delta
	if active:
		light.light_energy = 1.8 + sin(Time.get_ticks_msec() * 0.006) * 0.5


func activate() -> void:
	if active:
		return
	_set_power(true)
	if other:
		other._set_power(true)
	if town:
		town.open_zone("tanatorio")
	activated.emit()


# ---------------------------------------------------------------- interacción (solo el del instituto)

func can_interact(player) -> bool:
	return master and not active and to_local(player.global_position).length() < 3.2


func get_prompt(_player) -> String:
	return "Pulsa [F] para encender el portal [Coste: %d]" % COST


func is_hold() -> bool:
	return false


func interact(player) -> void:
	if active or not player.spend_points(COST):
		Sfx.play("deny", -8.0)
		return
	Sfx.play("purchase", -4.0)
	Sfx.play("portal", -2.0)
	activate()
	if player.hud:
		player.hud.announce("¡PORTAL ENCENDIDO!")


# ---------------------------------------------------------------- viaje

func _on_body(body) -> void:
	if active and cd <= 0.0 and other and body.has_method("take_weapon") and not body.dead and not body.downed:
		teleport(body)


## Lleva al jugador al otro portal y trae a los zombies que se quedaron lejos.
func teleport(player) -> void:
	cd = COOLDOWN
	other.cd = COOLDOWN
	var exit: Vector3 = other.global_transform * Vector3(0, 0.1, 2.6)
	player.global_position = exit
	player.velocity = Vector3.ZERO
	var fwd: Vector3 = other.global_transform.basis.z
	player.rotation.y = atan2(fwd.x, fwd.z) + PI
	player.head.rotation.x = 0.0
	Sfx.play("portal", -2.0)
	if player.hud:
		player.hud.flash(Color(0.7, 0.4, 1.0))
	if game and game.rounds:
		game.rounds.relocate_zombies()
