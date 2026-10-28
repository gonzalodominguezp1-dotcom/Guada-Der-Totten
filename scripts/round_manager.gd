extends Node
## Rondas al estilo World at War / Black Ops: cada ronda hay más zombies,
## con más vida y, a partir de la ronda 3, algunos corren.
## Los zombies aparecen junto a las ventanas del bar mientras la calle
## está cerrada; al abrir una puerta también salen por las calles.

const ZombieScript = preload("res://scripts/zombie.gd")
const PowerUp = preload("res://scripts/powerup.gd")
const MAX_ALIVE := 24
const MAX_DROPS := 4

var player
var town
var hud
var game
var round_num := 0
var to_spawn := 0
var alive := 0
var spawn_cd := 0.0
var between := true
var drops_this_round := 0


func setup(p, t, h, g = null) -> void:
	player = p
	town = t
	hud = h
	game = g


func start() -> void:
	_next_round()


static func zombie_count(r: int) -> int:
	var early := [6, 8, 13, 18]
	if r <= early.size():
		return early[r - 1]
	return int(24.0 + (r - 5) * 3.5 + 0.08 * r * r)


static func zombie_health(r: int) -> float:
	if r < 10:
		return 150.0 + 100.0 * (r - 1)
	return 950.0 * pow(1.1, r - 9)


func _next_round() -> void:
	between = true
	if round_num > 0:
		Sfx.play("round_end", -4.0)
	round_num += 1
	to_spawn = zombie_count(round_num)
	drops_this_round = 0
	if hud:
		hud.show_round(round_num)
	await get_tree().create_timer(2.5 if round_num == 1 else 8.0).timeout
	if not is_inside_tree():
		return
	Sfx.play("round_start", -6.0)
	await get_tree().create_timer(1.5).timeout
	if not is_inside_tree():
		return
	between = false
	spawn_cd = 0.0


func _process(delta: float) -> void:
	if between or player == null or player.dead:
		return
	spawn_cd -= delta
	if to_spawn > 0 and alive < MAX_ALIVE and spawn_cd <= 0.0:
		if _spawn():
			to_spawn -= 1
		spawn_cd = maxf(0.4, 2.2 - round_num * 0.12)
	if to_spawn == 0 and alive == 0:
		_next_round()


func _pick_spawn() -> Variant:
	var pp: Vector3 = player.global_position
	var window_spots: Array = []
	if town.bar:
		for s in town.bar.window_spawners:
			if pp.distance_to(s["pos"]) > 2.5:
				window_spots.append(s)
	var street_spots: Array = []
	if town.exterior_open:
		for s in town.spawn_points:
			var d := pp.distance_to(s)
			if d > 16.0 and d < 50.0:
				street_spots.append({"pos": s, "barricade": null})
	var inside: bool = town.bar != null and town.bar.is_inside_interior(pp)
	var use_window := not window_spots.is_empty() and (street_spots.is_empty() or (inside and randf() < 0.7))
	if use_window:
		return window_spots[randi() % window_spots.size()]
	if not street_spots.is_empty():
		return street_spots[randi() % street_spots.size()]
	# sin bar (pueblo de prueba): cualquier punto razonable
	var ok: Array = []
	for s in town.spawn_points:
		if pp.distance_to(s) > 12.0:
			ok.append({"pos": s, "barricade": null})
	if ok.is_empty():
		return null
	return ok[randi() % ok.size()]


func _spawn() -> bool:
	var spot = _pick_spawn()
	if spot == null:
		return false
	var z := ZombieScript.new()
	z.player = player
	z.manager = self
	z.window = spot["barricade"]
	z.max_health = zombie_health(round_num)
	var runner_chance := clampf((round_num - 2) * 0.18, 0.0, 0.9)
	z.runner = randf() < runner_chance
	z.speed = randf_range(3.4, 4.3) if z.runner else randf_range(1.1, 1.6)
	get_parent().add_child(z)
	z.global_position = spot["pos"] + Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))
	alive += 1
	return true


func on_zombie_died(z) -> void:
	alive = maxi(alive - 1, 0)
	var last := to_spawn == 0 and alive == 0
	if not last and drops_this_round < MAX_DROPS and randf() < 0.035:
		drops_this_round += 1
		var types := ["max_ammo", "insta_kill", "double_points", "nuke"]
		var pu := PowerUp.new()
		pu.kind = types[randi() % types.size()]
		pu.game = game
		get_parent().add_child(pu)
		pu.global_position = Vector3(z.global_position.x, 1.0, z.global_position.z)


func kill_all() -> int:
	var n := 0
	for z in get_tree().get_nodes_in_group("zombies"):
		if not z.dead:
			z.take_hit(999999.0, z.global_position + Vector3(0, 1.0, 0), null)
			n += 1
	return n
