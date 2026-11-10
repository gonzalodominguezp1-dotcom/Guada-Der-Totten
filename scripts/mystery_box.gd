extends StaticBody3D
## Caja mágica (estilo World at War): 950 puntos por un arma al azar.
## Hay varias ubicaciones (grupo "mystery_box"); solo una está activa, marcada
## con un haz de luz azul. Tras unas cuantas tiradas puede salir el osito:
## te devuelve los puntos y la caja se va a otra ubicación.

const Weapons = preload("res://scripts/weapons.gd")
const COST := 950
const ROLL_TIME := 3.6
const TAKE_TIME := 9.0

enum State { HIDDEN, IDLE, ROLLING, READY, LEAVING }

var start := false            # la caja empieza aquí
var place_name := ""
var state := State.HIDDEN
var uses := 0
var bear_after := 4
var result := ""
var timer := 0.0
var cycle_t := 0.0
var shown: Node3D
var visual: Node3D
var lid: Node3D
var beam: MeshInstance3D
var light: OmniLight3D
var cshape: CollisionShape3D
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("mystery_box")
	rng.randomize()
	bear_after = rng.randi_range(4, 8)
	collision_layer = 1
	cshape = CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(1.5, 0.75, 0.7)
	cshape.shape = b
	cshape.position.y = 0.375
	add_child(cshape)
	_build()
	_set_shown(false)
	if start:
		_set_shown(true)
		state = State.IDLE


func _build() -> void:
	visual = Node3D.new()
	add_child(visual)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.32, 0.2, 0.1)
	wood.roughness = 0.8
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.08, 0.05)
	dark.roughness = 0.9
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.3, 0.3, 0.32)
	metal.metallic = 0.6
	metal.roughness = 0.5
	_part(visual, Vector3(1.5, 0.6, 0.7), Vector3(0, 0.3, 0), wood)
	for x in [-0.72, 0.72]:
		_part(visual, Vector3(0.06, 0.62, 0.72), Vector3(x, 0.31, 0), metal)
	_part(visual, Vector3(1.52, 0.05, 0.72), Vector3(0, 0.05, 0), dark)
	for side in [-1.0, 1.0]:
		var q := Label3D.new()
		q.text = "?"
		q.font_size = 160
		q.pixel_size = 0.004
		q.modulate = Color(0.95, 0.85, 0.5)
		q.outline_size = 0
		q.position = Vector3(0, 0.32, 0.355 * side)
		q.rotation.y = 0.0 if side > 0 else PI
		visual.add_child(q)
	# tapa con bisagra atrás
	lid = Node3D.new()
	lid.position = Vector3(0, 0.6, -0.35)
	visual.add_child(lid)
	_part(lid, Vector3(1.52, 0.12, 0.72), Vector3(0, 0.06, 0.36), wood)
	_part(lid, Vector3(1.54, 0.03, 0.08), Vector3(0, 0.12, 0.7), metal)
	# haz de luz azul que marca dónde está la caja
	beam = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5
	cm.bottom_radius = 0.35
	cm.height = 40.0
	cm.cap_top = false
	cm.cap_bottom = false
	beam.mesh = cm
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.albedo_color = Color(0.25, 0.5, 1.0, 0.18)
	bm.disable_fog = true
	beam.material_override = bm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = 20.6
	visual.add_child(beam)
	light = OmniLight3D.new()
	light.light_color = Color(0.4, 0.6, 1.0)
	light.light_energy = 1.2
	light.omni_range = 4.0
	light.position = Vector3(0, 1.2, 0.3)
	visual.add_child(light)


func _part(parent: Node3D, s: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _set_shown(on: bool) -> void:
	visual.visible = on
	cshape.disabled = not on


func _process(delta: float) -> void:
	match state:
		State.ROLLING:
			timer -= delta
			cycle_t -= delta
			var k := 1.0 - timer / ROLL_TIME
			if shown:
				shown.position.y = lerpf(0.7, 1.15, k)
			if cycle_t <= 0.0 and timer > 0.4:
				cycle_t = lerpf(0.08, 0.35, k)
				var pool := Weapons.box_pool()
				_show_model(pool[rng.randi() % pool.size()])
			if timer <= 0.0:
				_finish_roll()
		State.READY:
			timer -= delta
			if shown:
				shown.rotation.y += delta * 0.6
				shown.position.y = lerpf(1.15, 0.75, clampf(1.0 - timer / TAKE_TIME, 0.0, 1.0))
			if timer <= 0.0:
				_close()
		State.LEAVING:
			timer -= delta
			visual.position.y += delta * (1.0 + (2.5 - timer) * 3.0)
			visual.rotation.y += delta * 2.0
			if timer <= 0.0:
				visual.position.y = 0.0
				visual.rotation.y = 0.0
				_set_shown(false)
				state = State.HIDDEN
				_move_elsewhere()


func _show_model(id: String) -> void:
	if shown:
		shown.queue_free()
	if id == "osito":
		shown = _teddy()
	else:
		shown = Weapons.build_model(id)
		shown.scale = Vector3(1.8, 1.8, 1.8)
		shown.rotation.y = PI * 0.5
	shown.position = Vector3(0, 0.9, 0)
	add_child(shown)


func _teddy() -> Node3D:
	var t := Node3D.new()
	var fur := StandardMaterial3D.new()
	fur.albedo_color = Color(0.55, 0.38, 0.22)
	fur.roughness = 1.0
	for spec in [[0.16, Vector3(0, 0, 0)], [0.12, Vector3(0, 0.22, 0)], [0.05, Vector3(-0.09, 0.32, 0)], [0.05, Vector3(0.09, 0.32, 0)],
			[0.06, Vector3(-0.14, 0.04, 0.05)], [0.06, Vector3(0.14, 0.04, 0.05)], [0.07, Vector3(-0.08, -0.15, 0.04)], [0.07, Vector3(0.08, -0.15, 0.04)]]:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = spec[0]
		sm.height = spec[0] * 2.0
		mi.mesh = sm
		mi.material_override = fur
		mi.position = spec[1]
		t.add_child(mi)
	return t


func _finish_roll() -> void:
	uses += 1
	var others := _other_spots()
	if uses >= bear_after and not others.is_empty() and rng.randf() < 0.6:
		_show_model("osito")
		shown.position.y = 1.15
		var players := get_tree().get_nodes_in_group("player")
		if not players.is_empty():
			players[0].add_points(COST)
			if players[0].hud:
				players[0].hud.announce("¡LA CAJA SE VA!")
		Sfx.play3d("deny", global_position + Vector3.UP, 2.0, 0.6)
		state = State.LEAVING
		timer = 2.5
		get_tree().create_timer(1.2).timeout.connect(func():
			if shown:
				shown.queue_free()
				shown = null)
		return
	# el arma final: una que no tengas ya
	var players := get_tree().get_nodes_in_group("player")
	var pool := Weapons.box_pool()
	if not players.is_empty():
		pool = pool.filter(func(id): return not players[0].has_weapon(id))
	if pool.is_empty():
		pool = Weapons.box_pool()
	result = pool[rng.randi() % pool.size()]
	_show_model(result)
	shown.position.y = 1.15
	Sfx.play3d("powerup_grab", global_position + Vector3.UP, -2.0)
	state = State.READY
	timer = TAKE_TIME


func _close() -> void:
	if shown:
		shown.queue_free()
		shown = null
	result = ""
	state = State.IDLE
	create_tween().tween_property(lid, "rotation:x", 0.0, 0.4)


func _other_spots() -> Array:
	var out := []
	for b in get_tree().get_nodes_in_group("mystery_box"):
		if b != self:
			out.append(b)
	return out


func _move_elsewhere() -> void:
	var others := _other_spots()
	if others.is_empty():
		_set_shown(true)
		state = State.IDLE
		return
	var nb = others[rng.randi() % others.size()]
	nb.arrive()


func arrive() -> void:
	_set_shown(true)
	lid.rotation.x = 0.0
	state = State.IDLE
	uses = 0
	bear_after = rng.randi_range(4, 8)
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty() and players[0].hud and place_name != "":
		players[0].hud.announce("La caja está ahora en: " + place_name)


func is_active() -> bool:
	return state != State.HIDDEN


func can_interact(player) -> bool:
	if state == State.HIDDEN or state == State.LEAVING or state == State.ROLLING:
		return false
	var to: Vector3 = player.global_position - global_position
	return to.length() < 2.2 and to.dot(global_transform.basis.z) > -0.2


func get_prompt(player) -> String:
	if state == State.READY:
		return "Pulsa [F] para coger: " + str(Weapons.data(result)["name"])
	return "Pulsa [F] para la Caja Mágica [Coste: %d]" % COST


func is_hold() -> bool:
	return false


func interact(player) -> void:
	if player.busy():
		return
	if state == State.READY:
		player.give_weapon(result)
		Sfx.play("purchase", -4.0)
		_close()
		return
	if state != State.IDLE:
		return
	if not player.spend_points(COST):
		Sfx.play("deny", -6.0)
		return
	Sfx.play3d("purchase", global_position, -2.0)
	Sfx.play3d("machine_hum", global_position + Vector3.UP, -2.0, 1.4)
	create_tween().tween_property(lid, "rotation:x", -1.7, 0.35)
	state = State.ROLLING
	timer = ROLL_TIME
	cycle_t = 0.0
