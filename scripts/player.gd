extends CharacterBody3D
## Jugador en primera persona: armas, cuchillo, puntos, compras, perks
## y Quick Revive (en solitario te levanta sola si caes).

signal died

const Weapons = preload("res://scripts/weapons.gd")
const Milkshake = preload("res://scripts/milkshake.gd")

const WALK_SPEED := 4.2
const SPRINT_SPEED := 6.6
const JUMP_VELOCITY := 4.4
const MOUSE_SENS := 0.0022
const MAX_DECALS := 40
const KNIFE_DAMAGE := 150.0
const DOWN_TIME := 9.0

var hud
var game                       # escena principal (power-ups)
var head: Node3D
var camera: Camera3D
var weapon_holder: Node3D
var viewmodel: Node3D
var knife_model: Node3D
var muzzle: OmniLight3D

var health := 100.0
var max_health := 100.0
var points := 500
var dead := false
var downed := false
var down_timer := 0.0

var weapons: Array = ["pistola"]
var ammo := {"pistola": {"mag": 8, "reserve": 80}}
var current := 0
var perks: Array = []
var quick_revive_bought := 0

var reloading := false
var drinking := false
var switching := false
var knifing := false
var fire_cd := 0.0
var knife_cd := 0.0
var since_hit := 10.0
var bob := 0.0
var recoil := 0.0
var aim := 0.0
var reload_anim := 0.0
var lower_anim := 0.0
var knife_anim := 0.0
var sway := Vector2.ZERO
var decals: Array = []
var hole_tex: GradientTexture2D
var interact_target = null
var flash: MeshInstance3D
var flash_t := 0.0
var slide: Node3D
var heartbeat_cd := 0.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 4 | 8 | 16
	floor_snap_length = 0.3
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)

	head = Node3D.new()
	head.name = "Cabeza"
	head.position.y = 1.65
	add_child(head)
	camera = Camera3D.new()
	camera.fov = 75.0
	camera.near = 0.02
	camera.current = true
	head.add_child(camera)

	weapon_holder = Node3D.new()
	camera.add_child(weapon_holder)
	muzzle = OmniLight3D.new()
	muzzle.light_color = Color(1.0, 0.7, 0.35)
	muzzle.omni_range = 8.0
	muzzle.light_energy = 0.0
	camera.add_child(muzzle)
	muzzle.position = Vector3(0.1, -0.05, -0.8)
	# luz de relleno muy corta para que el arma se vea de noche
	var fill := OmniLight3D.new()
	fill.position = Vector3(-0.2, 0.25, 0.1)
	fill.light_color = Color(0.75, 0.8, 1.0)
	fill.light_energy = 0.3
	fill.omni_range = 1.1
	fill.light_cull_mask = 1 << 19
	camera.add_child(fill)
	_build_knife()
	_equip(0, false)
	_make_hole_texture()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_hud()
	if hud:
		hud.set_points(points)
		hud.set_health(1.0)


func _build_knife() -> void:
	knife_model = Node3D.new()
	camera.add_child(knife_model)
	var blade := StandardMaterial3D.new()
	blade.albedo_color = Color(0.75, 0.76, 0.78)
	blade.metallic = 1.0
	blade.roughness = 0.25
	var handle := StandardMaterial3D.new()
	handle.albedo_color = Color(0.15, 0.1, 0.06)
	var sleeve := StandardMaterial3D.new()
	sleeve.albedo_color = Color(0.22, 0.24, 0.18)
	for p in [[Vector3(0.015, 0.03, 0.2), Vector3(0, 0, -0.16), blade],
			[Vector3(0.03, 0.035, 0.11), Vector3(0, 0, -0.01), handle],
			[Vector3(0.07, 0.08, 0.32), Vector3(0.02, -0.03, 0.17), sleeve]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = p[0]
		mi.mesh = bm
		mi.position = p[1]
		mi.material_override = p[2]
		mi.layers = 1 | (1 << 19)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		knife_model.add_child(mi)
	knife_model.visible = false


func _make_hole_texture() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.02, 0.02, 1.0))
	g.set_color(1, Color(0.05, 0.05, 0.05, 0.0))
	g.add_point(0.35, Color(0.04, 0.04, 0.04, 0.9))
	hole_tex = GradientTexture2D.new()
	hole_tex.gradient = g
	hole_tex.fill = GradientTexture2D.FILL_RADIAL
	hole_tex.fill_from = Vector2(0.5, 0.5)
	hole_tex.fill_to = Vector2(0.5, 0.0)
	hole_tex.width = 32
	hole_tex.height = 32


# ---------------------------------------------------------------- armas

func weapon_id() -> String:
	return weapons[current]


func wdata() -> Dictionary:
	return Weapons.data(weapon_id())


func has_weapon(id: String) -> bool:
	return id in weapons


func ammo_full(id: String) -> bool:
	var d := Weapons.data(id)
	return ammo[id]["mag"] == d["mag"] and ammo[id]["reserve"] == d["reserve"]


func refill_ammo(id: String) -> void:
	var d := Weapons.data(id)
	ammo[id] = {"mag": d["mag"], "reserve": d["reserve"]}
	_update_hud()


func refill_all_ammo() -> void:
	for id in weapons:
		var d := Weapons.data(id)
		ammo[id]["reserve"] = d["reserve"]
	_update_hud()


func give_weapon(id: String) -> void:
	var d := Weapons.data(id)
	ammo[id] = {"mag": d["mag"], "reserve": d["reserve"]}
	if weapons.size() < 2:
		weapons.append(id)
		_equip(weapons.size() - 1)
	else:
		ammo.erase(weapons[current])
		weapons[current] = id
		_equip(current)


func _equip(idx: int, animate := true) -> void:
	current = idx
	reloading = false
	if viewmodel:
		viewmodel.queue_free()
	viewmodel = Weapons.build_model(weapon_id(), true)
	weapon_holder.add_child(viewmodel)
	slide = viewmodel.get_node_or_null("slide")
	_build_flash()
	_set_layers(viewmodel)
	weapon_holder.position = wdata()["hip"]
	if animate:
		switching = true
		lower_anim = 1.0
		var tw := create_tween()
		tw.tween_property(self, "lower_anim", 0.0, 0.35)
		tw.tween_callback(func(): switching = false)
	_update_hud()


func _build_flash() -> void:
	# fogonazo: dos planos cruzados con brillo aditivo en la boca del cañón
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.65, 0.25, 0.9)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 0.85, 1))
	g.set_color(1, Color(1, 0.4, 0.05, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	m.albedo_texture = gt
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	flash = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.09, 0.09)
	flash.mesh = qm
	flash.material_override = m
	flash.position = wdata()["muzzle"] + Vector3(0, 0, -0.02)
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	viewmodel.add_child(flash)
	var side := MeshInstance3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2(0.05, 0.14)
	side.mesh = sq
	side.material_override = m
	side.rotation = Vector3(PI * 0.5, 0, 0)
	side.position = Vector3(0, 0, -0.05)
	flash.add_child(side)
	flash.visible = false


func _set_layers(n: Node) -> void:
	if n is MeshInstance3D:
		n.layers = 1 | (1 << 19)
	for c in n.get_children():
		_set_layers(c)


func _update_hud() -> void:
	if hud == null:
		return
	var a: Dictionary = ammo[weapon_id()]
	hud.set_ammo(a["mag"], a["reserve"], reloading)
	hud.set_weapon(wdata()["name"])


func busy() -> bool:
	return drinking or downed or dead or knifing


# ---------------------------------------------------------------- entrada

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not dead:
		var s := MOUSE_SENS * lerpf(1.0, 0.6, aim)
		rotate_y(-event.relative.x * s)
		head.rotate_x(-event.relative.y * s)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))
		sway += event.relative * 0.0004
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and not dead \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not busy() and weapons.size() > 1:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_equip((current + 1) % weapons.size())


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	if dead or downed:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var sprinting := Input.is_action_pressed("sprint") and input_dir.y < -0.1 and aim < 0.5 and not reloading and not drinking
	var spd := (SPRINT_SPEED if sprinting else WALK_SPEED) * lerpf(1.0, 0.6, aim) * (0.7 if drinking else 1.0)
	var k := clampf((12.0 if is_on_floor() else 3.0) * delta, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, dir.x * spd, k)
	velocity.z = lerpf(velocity.z, dir.z * spd, k)
	move_and_slide()


func _process(delta: float) -> void:
	fire_cd -= delta
	knife_cd -= delta
	since_hit += delta
	if downed:
		_process_downed(delta)
	elif not dead and since_hit > (2.0 if has_perk("quick_revive") else 3.0) and health < max_health:
		health = minf(max_health, health + 50.0 * delta)
		if hud:
			hud.set_health(health / max_health)
	if not dead and not downed and health < 45.0:
		heartbeat_cd -= delta
		if heartbeat_cd <= 0.0:
			heartbeat_cd = 0.9
			Sfx.play("heartbeat", -4.0)
	var want_aim := 1.0 if (Input.is_action_pressed("aim") and not busy() and not reloading and not switching) else 0.0
	aim = move_toward(aim, want_aim, delta * 6.0)
	camera.fov = lerpf(75.0, wdata()["ads_fov"], aim)
	if hud:
		hud.set_crosshair_visible(aim < 0.3 and not dead)
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if not dead and not downed and captured:
		if not busy() and not switching:
			var d := wdata()
			if Input.is_action_just_pressed("shoot") or (d["auto"] and Input.is_action_pressed("shoot")):
				shoot()
			if Input.is_action_just_pressed("reload"):
				reload()
			if Input.is_action_just_pressed("melee"):
				knife()
			if Input.is_action_just_pressed("weapon_1") and current != 0:
				_equip(0)
			if Input.is_action_just_pressed("weapon_2") and weapons.size() > 1 and current != 1:
				_equip(1)
		_process_interact()
	elif hud:
		hud.set_prompt("")
	_animate_gun(delta)


func _process_interact() -> void:
	var best = null
	var best_d := INF
	for it in get_tree().get_nodes_in_group("interactables"):
		if not it.can_interact(self):
			continue
		var d: float = it.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = it
	interact_target = best
	if hud:
		hud.set_prompt(best.get_prompt(self) if best else "")
	if best == null or busy():
		return
	if best.is_hold():
		if Input.is_action_pressed("interact"):
			best.interact(self)
	elif Input.is_action_just_pressed("interact"):
		best.interact(self)


func _animate_gun(delta: float) -> void:
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and hspeed > 0.5:
		bob += delta * hspeed * 1.9
	var bob_amt := lerpf(1.0, 0.15, aim) * clampf(hspeed / WALK_SPEED, 0.0, 1.6)
	var bob_off := Vector3(sin(bob) * 0.011, -absf(cos(bob)) * 0.011, 0) * bob_amt
	sway = sway.lerp(Vector2.ZERO, clampf(delta * 8.0, 0.0, 1.0))
	recoil = move_toward(recoil, 0.0, delta * 7.0)
	reload_anim = move_toward(reload_anim, 1.0 if reloading else 0.0, delta * 5.0)
	knife_anim = move_toward(knife_anim, 0.0, delta * 3.2)
	var low := maxf(lower_anim, 1.0 if (drinking or downed) else 0.0)
	var d := wdata()
	var target: Vector3 = d["hip"].lerp(d["ads"], aim) + bob_off
	target += Vector3(-sway.x, sway.y, 0) * lerpf(1.0, 0.2, aim)
	target += Vector3(0, -0.06 * reload_anim - 0.35 * low - 0.2 * sin(knife_anim * PI), 0.06 * recoil * d["recoil"])
	weapon_holder.position = weapon_holder.position.lerp(target, clampf(delta * 18.0, 0.0, 1.0))
	weapon_holder.rotation = Vector3(recoil * 0.2 * d["recoil"] - reload_anim * 0.7, lerpf(0.1, 0.0, aim), reload_anim * 0.5)
	knife_model.visible = knife_anim > 0.01
	if knife_model.visible:
		var t := 1.0 - knife_anim
		knife_model.position = Vector3(0.25 - t * 0.35, -0.22 + sin(t * PI) * 0.1, -0.3 - sin(t * PI) * 0.25)
		knife_model.rotation = Vector3(0, 0.6 - t * 1.4, -0.4)
	muzzle.light_energy = move_toward(muzzle.light_energy, 0.0, delta * 120.0)
	flash_t -= delta
	if flash:
		flash.visible = flash_t > 0.0


# ---------------------------------------------------------------- disparo

func shoot() -> void:
	if reloading or fire_cd > 0.0:
		return
	var id := weapon_id()
	var d := wdata()
	if ammo[id]["mag"] <= 0:
		Sfx.play("dry_fire", -6.0)
		fire_cd = 0.25
		reload()
		return
	ammo[id]["mag"] -= 1
	fire_cd = d["fire_delay"]
	recoil = 1.0
	muzzle.light_energy = 6.0
	flash_t = 0.045
	if flash:
		flash.rotation.z = randf() * TAU
		var fs := randf_range(0.8, 1.25) * (1.6 if id == "escopeta" else 1.0)
		flash.scale = Vector3(fs, fs, fs)
	if slide:
		var tw := create_tween()
		tw.tween_property(slide, "position:z", 0.03, 0.03)
		tw.tween_property(slide, "position:z", 0.0, 0.07)
	head.rotation.x = clampf(head.rotation.x + d["kick"], deg_to_rad(-89), deg_to_rad(89))
	Sfx.play(d["sound"], d["volume"], d["pitch"] * randf_range(0.96, 1.04))
	if ammo[id]["mag"] <= 2 and ammo[id]["mag"] > 0 and d["mag"] > 4:
		Sfx.play("low_ammo", -14.0)

	if d.get("projectile", false):
		_fire_projectile(d)
		_update_hud()
		if ammo[id]["mag"] == 0 and ammo[id]["reserve"] > 0:
			reload()
		return
	var spread: float = lerpf(d["spread_hip"], d["spread_ads"], aim)
	var cb := camera.global_transform.basis
	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var instakill: bool = game != null and game.instakill_active()
	var hits := {}
	for p in d["pellets"]:
		var dirv := -cb.z + cb.x * randf_range(-spread, spread) + cb.y * randf_range(-spread, spread)
		var to: Vector3 = from + dirv.normalized() * float(d["range"])
		var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4 | 16, [get_rid()])
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var col = hit["collider"]
		if col and col.has_method("take_hit"):
			var dist := from.distance_to(hit["position"])
			var dmg: float = d["damage"]
			if dist > d["falloff"]:
				dmg *= clampf(1.0 - (dist - d["falloff"]) / d["falloff"], 0.25, 1.0)
			if instakill:
				dmg = 999999.0
			# las perdigonadas suman en un solo impacto por zombie
			var key: int = col.get_instance_id()
			if hits.has(key):
				hits[key]["dmg"] += dmg
			else:
				hits[key] = {"col": col, "dmg": dmg, "pos": hit["position"]}
		else:
			_impact(hit["position"], hit["normal"])
	for key in hits:
		var h: Dictionary = hits[key]
		if is_instance_valid(h["col"]):
			h["col"].take_hit(h["dmg"], h["pos"], self)
	_update_hud()
	if ammo[id]["mag"] == 0 and ammo[id]["reserve"] > 0:
		reload()


func _fire_projectile(d: Dictionary) -> void:
	var cb := camera.global_transform.basis
	var spread: float = lerpf(d["spread_hip"], d["spread_ads"], aim)
	var aim_dir := (-cb.z + cb.x * randf_range(-spread, spread) + cb.y * randf_range(-spread, spread)).normalized()
	var from := camera.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + aim_dir * 100.0, 1 | 4 | 16, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var target: Vector3 = hit["position"] if not hit.is_empty() else from + aim_dir * 100.0
	var muzzle_pos: Vector3 = viewmodel.to_global(d["muzzle"])
	# si el objetivo está muy cerca, que salga desde la cámara para no atravesar paredes
	if target.distance_to(from) < 1.2:
		muzzle_pos = from
	var shot = Milkshake.new()
	shot.velocity = (target - muzzle_pos).normalized() * float(d["speed"])
	shot.shooter = self
	shot.damage = 999999.0 if (game != null and game.instakill_active()) else float(d["damage"])
	shot.splash = float(d["splash"])
	shot.exclude = [get_rid()]
	get_tree().current_scene.add_child(shot)
	shot.global_position = muzzle_pos


func reload() -> void:
	var id := weapon_id()
	var d := wdata()
	if reloading or ammo[id]["mag"] == d["mag"] or ammo[id]["reserve"] <= 0 or dead or downed:
		return
	reloading = true
	_update_hud()
	Sfx.play("reload", -4.0, 1.5 / d["reload"] if d["reload"] > 1.6 else 1.0)
	await get_tree().create_timer(d["reload"]).timeout
	if dead or not is_inside_tree() or not reloading or weapon_id() != id:
		return
	var take: int = mini(d["mag"] - ammo[id]["mag"], ammo[id]["reserve"])
	ammo[id]["mag"] += take
	ammo[id]["reserve"] -= take
	reloading = false
	_update_hud()


func knife() -> void:
	if knife_cd > 0.0:
		return
	knife_cd = 0.75
	knifing = true
	knife_anim = 1.0
	reloading = false
	Sfx.play("knife", -4.0, randf_range(0.9, 1.1))
	await get_tree().create_timer(0.12).timeout
	if not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	var from := camera.global_position
	var fwd := -camera.global_transform.basis.z
	var best = null
	var best_d := 2.3
	for z in get_tree().get_nodes_in_group("zombies"):
		if z.dead:
			continue
		var to: Vector3 = z.global_position + Vector3(0, 1.1, 0) - from
		var dist := to.length()
		if dist < best_d and to.normalized().dot(fwd) > 0.55:
			var q := PhysicsRayQueryParameters3D.create(from, from + to, 1 | 16, [get_rid()])
			if space.intersect_ray(q).is_empty():
				best = z
				best_d = dist
	if best:
		var dmg := 999999.0 if (game != null and game.instakill_active()) else KNIFE_DAMAGE
		best.take_hit(dmg, best.global_position + Vector3(0, 1.2, 0), self, true)
		Sfx.play("flesh_hit", -2.0)
	await get_tree().create_timer(0.35).timeout
	knifing = false


func _impact(pos: Vector3, normal: Vector3) -> void:
	var spark := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.025
	sm.height = 0.05
	spark.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.75, 0.4)
	spark.material_override = mat
	get_tree().current_scene.add_child(spark)
	spark.global_position = pos
	get_tree().create_timer(0.06).timeout.connect(spark.queue_free)
	if absf(normal.dot(Vector3.UP)) > 0.999:
		normal = (normal + Vector3(0.001, 0, 0)).normalized()
	var decal := Decal.new()
	decal.texture_albedo = hole_tex
	decal.size = Vector3(0.09, 0.1, 0.09)
	decal.cull_mask = 1
	get_tree().current_scene.add_child(decal)
	decal.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, normal)), pos)
	decals.append(decal)
	if decals.size() > MAX_DECALS:
		var old = decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()


# ---------------------------------------------------------------- puntos

func add_points(n: int) -> void:
	if game != null and game.double_points_active():
		n *= 2
	points += n
	if hud:
		hud.set_points(points)
		hud.popup_points(n)


func spend_points(n: int) -> bool:
	if points < n:
		return false
	points -= n
	if hud:
		hud.set_points(points)
		hud.popup_points(-n)
	return true


func hit_feedback(kill: bool) -> void:
	if hud:
		hud.show_hitmarker(kill)


# ---------------------------------------------------------------- perks

func has_perk(p: String) -> bool:
	return p in perks


func drink_perk(p: String) -> void:
	drinking = true
	reloading = false
	Sfx.play("perk_drink", -3.0)
	var bottle := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.018
	cm.bottom_radius = 0.035
	cm.height = 0.2
	bottle.mesh = cm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.35, 0.75, 1.0)
	bm.emission_enabled = true
	bm.emission = Color(0.2, 0.5, 0.9)
	bottle.material_override = bm
	bottle.layers = 1 | (1 << 19)
	camera.add_child(bottle)
	bottle.position = Vector3(0.05, -0.3, -0.35)
	var tw := create_tween()
	tw.tween_property(bottle, "position", Vector3(0.0, -0.06, -0.22), 0.5)
	tw.parallel().tween_property(bottle, "rotation:x", 1.9, 0.9)
	tw.tween_interval(1.0)
	tw.tween_property(bottle, "position", Vector3(0.1, -0.4, -0.3), 0.4)
	tw.tween_callback(bottle.queue_free)
	await get_tree().create_timer(2.3).timeout
	if not is_inside_tree():
		return
	drinking = false
	if not p in perks:
		perks.append(p)
	if hud:
		hud.set_perks(perks)


# ---------------------------------------------------------------- daño

func take_damage(amount: float) -> void:
	if dead or downed:
		return
	health -= amount
	since_hit = 0.0
	Sfx.play("hurt", -3.0, randf_range(0.9, 1.1))
	if hud:
		hud.set_health(maxf(health, 0.0) / max_health)
	var tw := create_tween()
	tw.tween_property(head, "rotation:z", randf_range(-0.08, 0.08), 0.06)
	tw.tween_property(head, "rotation:z", 0.0, 0.2)
	if health <= 0.0:
		if has_perk("quick_revive"):
			_go_down()
		else:
			_die()


func _go_down() -> void:
	downed = true
	down_timer = DOWN_TIME
	reloading = false
	perks.erase("quick_revive")
	if hud:
		hud.set_perks(perks)
		hud.show_downed(true)
	var tw := create_tween()
	tw.tween_property(head, "position:y", 0.55, 0.5).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(head, "rotation:z", 0.25, 0.5)


func _process_downed(delta: float) -> void:
	down_timer -= delta
	if hud:
		hud.set_downed_progress(1.0 - down_timer / DOWN_TIME)
	if down_timer <= 0.0:
		downed = false
		health = max_health
		since_hit = 10.0
		if hud:
			hud.show_downed(false)
			hud.set_health(1.0)
		var tw := create_tween()
		tw.tween_property(head, "position:y", 1.65, 0.6).set_trans(Tween.TRANS_QUAD)
		tw.parallel().tween_property(head, "rotation:z", 0.0, 0.6)


func _die() -> void:
	dead = true
	health = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	weapon_holder.visible = false
	var tw := create_tween()
	tw.tween_property(head, "position:y", 0.35, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(head, "rotation:z", 0.5, 0.8)
	died.emit()
