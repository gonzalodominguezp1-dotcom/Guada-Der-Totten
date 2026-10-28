extends CharacterBody3D
## Zombie al estilo World at War:
##  - sale del suelo,
##  - si le toca una ventana, va hacia ella, arranca las tablas y entra,
##  - persigue al jugador por la malla de navegación y ataca,
##  - si caes con Quick Revive, se aleja mientras te levantas.
## Cuerpo procedural articulado; si hay modelos de Mixamo en
## res://assets/zombies/ (walk, run, attack, death, rise) los usa.

enum State { RISING, TO_WINDOW, TEARING, CLIMBING, CHASE, WANDER }

const ATTACK_RANGE := 1.4
const ATTACK_DAMAGE := 50.0
const HEADSHOT_MULT := 4.0
const SKIN_SHADER = preload("res://shaders/zombie_skin.gdshader")
const CLOTH_SHADER = preload("res://shaders/zombie_cloth.gdshader")
const MIXAMO_DIR := "res://assets/zombies/"

static var _noise: NoiseTexture2D
static var _mixamo_checked := false
static var _mixamo_scene: PackedScene
static var _mixamo_anims := {}

var player
var manager
var window = null              # barricada asignada
var max_health := 150.0
var speed := 1.3
var runner := false

var state := State.RISING
var health := 150.0
var dead := false
var agent: NavigationAgent3D
var col_shape: CollisionShape3D

# cuerpo procedural
var visual: Node3D
var hips: Node3D
var spine: Node3D
var head: Node3D
var jaw: Node3D
var shoulder_l: Node3D
var shoulder_r: Node3D
var elbow_l: Node3D
var elbow_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var limp := 0.0
var lost_arm := false
# Mixamo
var anim_player: AnimationPlayer
var cur_anim := ""

var anim_t := 0.0
var attack_cd := 0.0
var attack_anim := 0.0
var tear_cd := 0.0
var repath := 0.0
var moan_cd := 0.0
var head_tilt := 0.0
var stuck_t := 0.0
var last_pos := Vector3.ZERO
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


func _ready() -> void:
	add_to_group("zombies")
	health = max_health
	collision_layer = 4
	collision_mask = 1 | 2 | 4 | 8 | 16
	floor_snap_length = 0.3
	col_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.85
	col_shape.shape = cap
	col_shape.position.y = 0.925
	add_child(col_shape)

	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.6
	agent.target_desired_distance = 0.5
	agent.path_max_distance = 3.0
	add_child(agent)

	_load_mixamo()
	if _mixamo_scene and _mixamo_anims.has("walk"):
		_build_mixamo()
	else:
		_build_body()
	anim_t = randf() * 10.0
	head_tilt = randf_range(-0.35, 0.35)
	moan_cd = randf_range(1.0, 5.0)
	last_pos = global_position
	_rise()


# ---------------------------------------------------------------- aparición

func _rise() -> void:
	state = State.RISING
	visual.position.y = -1.95
	if anim_player and _mixamo_anims.has("rise"):
		_play("rise")
		visual.position.y = 0.0
		get_tree().create_timer(_mixamo_anims["rise"].length * 0.9).timeout.connect(_end_rise)
		return
	var tw := create_tween()
	tw.tween_property(visual, "position:y", 0.0, 1.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_end_rise)
	# tierra que salta
	_dust()


func _end_rise() -> void:
	if dead:
		return
	state = State.TO_WINDOW if window != null else State.CHASE


func _dust() -> void:
	var p := CPUParticles3D.new()
	p.amount = 24
	p.one_shot = true
	p.explosiveness = 0.7
	p.lifetime = 1.2
	p.direction = Vector3.UP
	p.spread = 50.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 2.0
	p.gravity = Vector3(0, -4, 0)
	var m := BoxMesh.new()
	m.size = Vector3(0.05, 0.05, 0.05)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.2, 0.15)
	m.material = mat
	p.mesh = m
	add_child(p)
	p.position.y = 0.1
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)


# ---------------------------------------------------------------- cuerpo procedural

static func _noise_tex() -> NoiseTexture2D:
	if _noise == null:
		var fn := FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.frequency = 0.03
		fn.fractal_octaves = 4
		_noise = NoiseTexture2D.new()
		_noise.width = 256
		_noise.height = 256
		_noise.seamless = true
		_noise.noise = fn
	return _noise


func _skin_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SKIN_SHADER
	m.set_shader_parameter("noise_tex", _noise_tex())
	var tints := [Color(0.38, 0.40, 0.32), Color(0.42, 0.38, 0.34), Color(0.34, 0.37, 0.33), Color(0.44, 0.41, 0.36)]
	m.set_shader_parameter("tint", tints[randi() % tints.size()])
	m.set_shader_parameter("blood", randf_range(0.25, 0.6))
	m.set_shader_parameter("seed", randf() * 10.0)
	return m


func _cloth_mat(c: Color, tear: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CLOTH_SHADER
	m.set_shader_parameter("noise_tex", _noise_tex())
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("tear", tear)
	m.set_shader_parameter("blood", randf_range(0.2, 0.6))
	m.set_shader_parameter("seed", randf() * 10.0)
	return m


func _joint(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _cap(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material, scl := Vector3.ONE) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = maxf(h, r * 2.0)
	m.radial_segments = 12
	m.rings = 4
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.scale = scl
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _boxm(parent: Node3D, s: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = s
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _build_body() -> void:
	var skin := _skin_mat()
	var shirts := [Color(0.42, 0.40, 0.36), Color(0.25, 0.28, 0.35), Color(0.45, 0.35, 0.25),
		Color(0.30, 0.22, 0.20), Color(0.20, 0.27, 0.22), Color(0.55, 0.52, 0.48), Color(0.35, 0.12, 0.10)]
	var pants_c := [Color(0.13, 0.14, 0.18), Color(0.25, 0.22, 0.17), Color(0.18, 0.2, 0.25), Color(0.1, 0.1, 0.1)]
	var shirt := _cloth_mat(shirts[randi() % shirts.size()], randf_range(0.2, 0.6))
	var pants := _cloth_mat(pants_c[randi() % pants_c.size()], randf_range(0.1, 0.4))
	var shoe := StandardMaterial3D.new()
	shoe.albedo_color = Color(0.08, 0.07, 0.06)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.03, 0.01, 0.01)
	var blood := StandardMaterial3D.new()
	blood.albedo_color = Color(0.3, 0.02, 0.02)
	blood.roughness = 0.3
	var eye := StandardMaterial3D.new()
	eye.albedo_color = Color(1.0, 0.6, 0.1)
	eye.emission_enabled = true
	eye.emission = Color(1.0, 0.5, 0.05)
	eye.emission_energy_multiplier = 5.0
	var hair := StandardMaterial3D.new()
	hair.albedo_color = [Color(0.08, 0.06, 0.05), Color(0.3, 0.28, 0.25), Color(0.18, 0.12, 0.08)][randi() % 3]
	hair.roughness = 1.0
	var teeth := StandardMaterial3D.new()
	teeth.albedo_color = Color(0.7, 0.65, 0.45)

	visual = Node3D.new()
	visual.name = "Cuerpo"
	add_child(visual)
	var s := randf_range(0.94, 1.06)
	visual.scale = Vector3(s, s, s)
	limp = randf_range(0.0, 0.5) if randf() < 0.4 else 0.0
	lost_arm = randf() < 0.12

	hips = _joint(visual, Vector3(0, 0.95, 0))
	_cap(hips, 0.15, 0.32, Vector3(0, 0.0, 0), pants, Vector3(1.2, 0.7, 0.85))
	for side in [-1.0, 1.0]:
		var leg := _joint(hips, Vector3(0.1 * side, -0.03, 0))
		_cap(leg, 0.075, 0.5, Vector3(0, -0.22, 0), pants)
		var knee := _joint(leg, Vector3(0, -0.45, 0))
		_cap(knee, 0.06, 0.48, Vector3(0, -0.22, 0), pants)
		_boxm(knee, Vector3(0.1, 0.07, 0.25), Vector3(0, -0.46, -0.05), shoe)
		if side < 0:
			leg_l = leg
			knee_l = knee
		else:
			leg_r = leg
			knee_r = knee

	spine = _joint(hips, Vector3(0, 0.08, 0))
	_cap(spine, 0.16, 0.42, Vector3(0, 0.12, 0), shirt, Vector3(1.15, 1.0, 0.8))     # vientre
	_cap(spine, 0.18, 0.4, Vector3(0, 0.36, 0), shirt, Vector3(1.3, 1.0, 0.78))     # pecho
	_cap(spine, 0.13, 0.3, Vector3(0, 0.3, 0.0), skin, Vector3(1.1, 1.0, 0.7))      # piel bajo la camisa
	_cap(spine, 0.055, 0.16, Vector3(0, 0.6, 0.01), skin)                           # cuello
	_boxm(spine, Vector3(0.16, 0.14, 0.02), Vector3(randf_range(-0.08, 0.08), randf_range(0.2, 0.45), -0.14), blood)

	head = _joint(spine, Vector3(0, 0.68, 0.0))
	var skull := SphereMesh.new()
	skull.radius = 0.12
	skull.height = 0.26
	skull.radial_segments = 16
	skull.rings = 8
	var sk := MeshInstance3D.new()
	sk.mesh = skull
	sk.material_override = skin
	sk.position = Vector3(0, 0.1, 0)
	sk.scale = Vector3(0.92, 1.08, 1.0)
	head.add_child(sk)
	if randf() < 0.7:
		var cap_m := SphereMesh.new()
		cap_m.radius = 0.125
		cap_m.height = 0.16
		cap_m.is_hemisphere = true
		var hc := MeshInstance3D.new()
		hc.mesh = cap_m
		hc.material_override = hair
		hc.position = Vector3(0, 0.15, 0.02)
		hc.scale = Vector3(0.98, 0.7, 1.04)
		head.add_child(hc)
	for side in [-1.0, 1.0]:
		var sock := SphereMesh.new()
		sock.radius = 0.028
		sock.height = 0.05
		var so := MeshInstance3D.new()
		so.mesh = sock
		so.material_override = dark
		so.position = Vector3(0.042 * side, 0.12, -0.1)
		head.add_child(so)
		var e := SphereMesh.new()
		e.radius = 0.014
		e.height = 0.028
		var eo := MeshInstance3D.new()
		eo.mesh = e
		eo.material_override = eye
		eo.position = Vector3(0.042 * side, 0.12, -0.115)
		head.add_child(eo)
	_boxm(head, Vector3(0.03, 0.05, 0.03), Vector3(0, 0.08, -0.12), skin)          # nariz
	jaw = _joint(head, Vector3(0, 0.03, -0.03))
	_boxm(jaw, Vector3(0.13, 0.045, 0.1), Vector3(0, -0.02, -0.05), skin)
	_boxm(jaw, Vector3(0.1, 0.015, 0.02), Vector3(0, 0.005, -0.095), teeth)
	_boxm(head, Vector3(0.1, 0.015, 0.02), Vector3(0, 0.035, -0.105), teeth)

	for side in [-1.0, 1.0]:
		var sh := _joint(spine, Vector3(0.23 * side, 0.5, 0))
		_cap(sh, 0.065, 0.2, Vector3(0, -0.02, 0), shirt)                            # hombro
		var upper := _cap(sh, 0.052, 0.34, Vector3(0, -0.16, 0), skin)
		var elbow := _joint(sh, Vector3(0, -0.31, 0))
		var fore := _cap(elbow, 0.046, 0.32, Vector3(0, -0.15, 0), skin)
		var hand := _boxm(elbow, Vector3(0.07, 0.11, 0.04), Vector3(0, -0.34, 0), skin)
		_cap(sh, 0.06, 0.2, Vector3(0, -0.08, 0), shirt)                              # manga
		if side < 0:
			shoulder_l = sh
			elbow_l = elbow
			if lost_arm:
				fore.visible = false
				hand.visible = false
				_boxm(elbow, Vector3(0.08, 0.05, 0.08), Vector3(0, -0.02, 0), blood)
		else:
			shoulder_r = sh
			elbow_r = elbow
		upper.name = "brazo"

	if runner:
		spine.rotation.x = -0.35


# ---------------------------------------------------------------- Mixamo

static func _find_file(base: String) -> String:
	for ext in ["fbx", "glb", "gltf"]:
		var p: String = MIXAMO_DIR + base + "." + str(ext)
		if ResourceLoader.exists(p):
			return p
	return ""


static func _load_mixamo() -> void:
	if _mixamo_checked:
		return
	_mixamo_checked = true
	for anim_name in ["walk", "run", "attack", "death", "rise"]:
		var path := _find_file(anim_name)
		if path == "":
			continue
		var scene = load(path)
		if not scene is PackedScene:
			continue
		if _mixamo_scene == null:
			_mixamo_scene = scene
		var inst: Node = scene.instantiate()
		var ap := _find_anim_player(inst)
		if ap:
			for n in ap.get_animation_list():
				if n == "RESET":
					continue
				var a: Animation = ap.get_animation(n).duplicate()
				a.loop_mode = Animation.LOOP_LINEAR if anim_name in ["walk", "run"] else Animation.LOOP_NONE
				_mixamo_anims[anim_name] = a
				break
		inst.free()
	if not _mixamo_anims.is_empty():
		print("Zombies de Mixamo cargados: ", _mixamo_anims.keys())


static func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim_player(c)
		if r:
			return r
	return null


func _build_mixamo() -> void:
	visual = Node3D.new()
	visual.name = "Cuerpo"
	add_child(visual)
	var model: Node3D = _mixamo_scene.instantiate()
	visual.add_child(model)
	model.rotation.y = PI   # Mixamo mira a +Z
	# escalar a ~1.8 m
	var aabb := _merged_aabb(model, Transform3D())
	if aabb.size.y > 0.01:
		var s := 1.8 / aabb.size.y * randf_range(0.95, 1.05)
		model.scale = Vector3(s, s, s)
		model.position.y = -aabb.position.y * s
	anim_player = _find_anim_player(model)
	if anim_player == null:
		return
	var lib := AnimationLibrary.new()
	for k in _mixamo_anims:
		lib.add_animation(k, _mixamo_anims[k])
	anim_player.add_animation_library("z", lib)
	_play("walk")
	anim_player.seek(randf() * 1.0, true)


func _merged_aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var t := xf
	if n is Node3D:
		t = xf * n.transform
	if n is MeshInstance3D and n.mesh:
		var a: AABB = t * n.get_aabb()
		out = a
		first = false
	for c in n.get_children():
		var ca := _merged_aabb(c, t)
		if ca.size != Vector3.ZERO:
			out = ca if first else out.merge(ca)
			first = false
	return out


func _play(anim_name: String, blend := 0.25) -> void:
	if anim_player == null or not _mixamo_anims.has(anim_name) or cur_anim == anim_name:
		return
	cur_anim = anim_name
	anim_player.play("z/" + anim_name, blend)


# ---------------------------------------------------------------- comportamiento

func _physics_process(delta: float) -> void:
	if not is_on_floor() and state != State.CLIMBING:
		velocity.y -= gravity * delta
	elif state != State.CLIMBING:
		velocity.y = 0.0
	if dead or player == null or state == State.RISING or state == State.CLIMBING:
		velocity.x = 0.0
		velocity.z = 0.0
		if not dead and state != State.CLIMBING:
			move_and_slide()
		return

	attack_cd -= delta
	tear_cd -= delta
	var move_dir := Vector3.ZERO
	var spd := speed
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()

	if player.downed and state == State.CHASE:
		state = State.WANDER
	elif not player.downed and state == State.WANDER:
		state = State.CHASE

	match state:
		State.TO_WINDOW:
			# si el jugador ya no está dentro del bar, ir directamente a por él
			if not _player_inside_bar() and manager and manager.town.exterior_open:
				state = State.CHASE
			else:
				var target: Vector3 = window.outside_point()
				var d := Vector2(target.x - global_position.x, target.z - global_position.z).length()
				if d < 0.45:
					state = State.TEARING
					tear_cd = randf_range(0.6, 1.2)
				else:
					move_dir = _nav_dir(target, delta)
		State.TEARING:
			var inward: Vector3 = -window.global_transform.basis.z
			_face(inward, delta)
			# empujar contra la ventana
			var target: Vector3 = window.outside_point()
			var off := Vector3(target.x - global_position.x, 0, target.z - global_position.z)
			if off.length() > 0.15:
				move_dir = off.normalized()
				spd = 1.0
			if dist < ATTACK_RANGE + 0.4 and not player.downed and not player.dead:
				_try_attack()
			elif window.is_open():
				_climb()
			elif tear_cd <= 0.0:
				tear_cd = maxf(0.7, 1.5 - manager.round_num * 0.05) if manager else 1.3
				attack_anim = 1.0
				window.tear_board()
		State.CHASE:
			if dist < ATTACK_RANGE and not player.dead:
				_try_attack()
				_face(to_player, delta)
			else:
				move_dir = _nav_dir(player.global_position, delta)
				if dist < 2.2:
					move_dir = to_player.normalized()
		State.WANDER:
			var away := -to_player.normalized() if dist > 0.1 else Vector3.FORWARD
			if dist < 14.0:
				move_dir = _nav_dir(global_position + away * 6.0, delta)
				spd = speed * 0.8

	if move_dir.length() > 0.01 and state != State.TEARING:
		_face(move_dir, delta)
	velocity.x = move_dir.x * spd
	velocity.z = move_dir.z * spd
	move_and_slide()


func _nav_dir(target: Vector3, delta: float) -> Vector3:
	repath -= delta
	if repath <= 0.0:
		agent.target_position = target
		repath = 0.25 + randf() * 0.15
	var d := agent.get_next_path_position() - global_position
	d.y = 0.0
	if d.length() < 0.05:
		d = target - global_position
		d.y = 0.0
	return d.normalized()


func is_tearing() -> bool:
	return state == State.TEARING


func _player_inside_bar() -> bool:
	if manager == null or manager.town.bar == null:
		return true
	return manager.town.bar.is_inside_interior(player.global_position)


func _try_attack() -> void:
	if attack_cd > 0.0 or player.downed or player.dead:
		return
	attack_cd = 1.1
	attack_anim = 1.0
	Sfx.play3d("zombie_attack_%d" % (randi() % 3), global_position + Vector3(0, 1.5, 0), -2.0, randf_range(0.85, 1.15))
	_play("attack", 0.1)
	# el golpe llega un poco después del gesto
	await get_tree().create_timer(0.25).timeout
	if dead or not is_inside_tree() or player.downed or player.dead:
		return
	var d := Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length()
	if d < ATTACK_RANGE + 0.5:
		player.take_damage(ATTACK_DAMAGE)


func _climb() -> void:
	state = State.CLIMBING
	col_shape.disabled = true
	var a := global_position
	var b: Vector3 = window.inside_point()
	var mid := (a + b) * 0.5 + Vector3(0, 0.9, 0)
	_face(b - a, 1.0)
	var tw := create_tween()
	tw.tween_property(self, "global_position", mid, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "global_position", b, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		col_shape.disabled = false
		window = null
		if not dead:
			state = State.CHASE)


func _face(dir: Vector3, delta: float) -> void:
	if dir.length() < 0.01:
		return
	var yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, yaw, clampf(delta * 8.0, 0.0, 1.0))


# ---------------------------------------------------------------- animación

func _process(delta: float) -> void:
	if dead or visual == null:
		return
	moan_cd -= delta
	if moan_cd <= 0.0:
		moan_cd = randf_range(3.0, 8.0)
		Sfx.play3d("zombie_moan_%d" % (randi() % 6), global_position + Vector3(0, 1.6, 0), -5.0, randf_range(0.8, 1.15), 30.0)
	var moving := Vector2(velocity.x, velocity.z).length()
	attack_anim = move_toward(attack_anim, 0.0, delta * 2.2)
	if anim_player:
		if state == State.RISING:
			return
		if attack_anim > 0.6:
			return
		_play("run" if runner and _mixamo_anims.has("run") else "walk")
		anim_player.speed_scale = clampf(moving / (3.8 if runner else 1.3), 0.4, 1.6) if moving > 0.1 else 0.35
		return
	anim_t += delta * (2.2 + moving * 2.6)
	var sw := sin(anim_t)
	var amp := clampf(moving * (0.3 if runner else 0.42), 0.0, 0.8)
	var limp_l := 1.0 - limp
	leg_l.rotation.x = sw * amp * limp_l
	leg_r.rotation.x = -sw * amp
	knee_l.rotation.x = -maxf(0.0, -sw) * amp * 1.4 * limp_l - 0.08
	knee_r.rotation.x = -maxf(0.0, sw) * amp * 1.4 - 0.08
	var swipe := sin(attack_anim * PI) * 1.2
	if runner and state == State.CHASE:
		shoulder_l.rotation.x = -sw * 1.0 + swipe
		shoulder_r.rotation.x = sw * 1.0 + swipe
		elbow_l.rotation.x = 1.3
		elbow_r.rotation.x = 1.3
		spine.rotation.x = -0.35
	else:
		var reach := 1.35 if state != State.TEARING else 1.1 + sin(anim_t * 2.0) * 0.35
		shoulder_l.rotation.x = reach + sin(anim_t * 0.5) * 0.12 + swipe
		shoulder_r.rotation.x = reach - 0.1 + sin(anim_t * 0.5 + 1.0) * 0.12 + swipe
		elbow_l.rotation.x = 0.25 + swipe * 0.3
		elbow_r.rotation.x = 0.35 + swipe * 0.3
		spine.rotation.x = -0.12 - limp * 0.15
		shoulder_l.rotation.z = -0.15
		shoulder_r.rotation.z = 0.15
	spine.rotation.z = sin(anim_t * 0.5) * 0.08 + limp * 0.12
	hips.position.y = 0.95 - absf(sw) * 0.03 * clampf(moving, 0.0, 1.0) - limp * absf(sw) * 0.06
	head.rotation.z = head_tilt + sin(anim_t * 0.3) * 0.1
	head.rotation.x = 0.15 + sin(anim_t * 0.7) * 0.05
	jaw.rotation.x = 0.25 + 0.2 * absf(sin(anim_t * 1.3))


# ---------------------------------------------------------------- daño

func head_height() -> float:
	if head:
		return head.global_position.y + 0.05
	return global_position.y + 1.62


func take_hit(dmg: float, pos: Vector3, attacker, melee := false) -> void:
	if dead:
		return
	var headshot := not melee and pos.y > head_height() - 0.1
	health -= dmg * (HEADSHOT_MULT if headshot else 1.0)
	_blood(pos, 10)
	var killed := health <= 0.0
	if attacker:
		if killed:
			attacker.add_points(130 if melee else (100 if headshot else 60))
		else:
			attacker.add_points(10)
		attacker.hit_feedback(killed)
	if killed:
		_die(headshot)
	elif not melee:
		# retroceso al recibir el disparo
		if spine:
			var tw := create_tween()
			tw.tween_property(spine, "rotation:x", spine.rotation.x + 0.3, 0.05)


func _blood(pos: Vector3, amount: int) -> void:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = 0.6
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.5
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var m := SphereMesh.new()
	m.radius = 0.025
	m.height = 0.05
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.0, 0.0)
	mat.roughness = 0.3
	m.material = mat
	p.mesh = m
	get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)


func _die(headshot: bool) -> void:
	dead = true
	collision_layer = 0
	collision_mask = 1
	col_shape.disabled = state == State.CLIMBING
	if manager:
		manager.on_zombie_died(self)
	if headshot and head:
		_blood(head.global_position + Vector3(0, 0.1, 0), 28)
		head.visible = false
	if anim_player:
		if _mixamo_anims.has("death"):
			_play("death", 0.1)
		var tw0 := create_tween()
		tw0.tween_interval(5.0)
		tw0.tween_property(visual, "position:y", -0.8, 1.5)
		tw0.tween_callback(queue_free)
		return
	var dir := 1.0 if randf() < 0.6 else -1.0
	var tw := create_tween()
	tw.tween_property(visual, "rotation:x", deg_to_rad(86) * dir, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(visual, "position:y", 0.12, 0.55)
	tw.parallel().tween_property(shoulder_l, "rotation:x", 2.6, 0.5)
	tw.parallel().tween_property(shoulder_r, "rotation:x", 2.2, 0.5)
	tw.parallel().tween_property(knee_l, "rotation:x", -0.6, 0.4)
	tw.parallel().tween_property(leg_r, "rotation:x", 0.4, 0.4)
	tw.tween_interval(4.0)
	tw.tween_property(visual, "position:y", -0.7, 1.5)
	tw.tween_callback(queue_free)
