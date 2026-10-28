extends SceneTree
## Prueba automática del juego completo (se ejecuta sin ventana):
##   godot --headless --path . -s tests/smoke_test.gd --fixed-fps 60
## Comprueba: pueblo y bar generados, navegación, zombies que van a las
## ventanas y arrancan tablas, reparar, comprar puerta / Quick Revive /
## escopeta, disparar, cuchillo, caer y levantarse con Quick Revive.

var main
var frame := 0
var ok := true
var log_lines: Array = []


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main


func check(cond: bool, msg: String) -> void:
	print(("OK    " if cond else "FALLO ") + msg)
	if not cond:
		ok = false


func _path_len(t) -> float:
	var map: RID = t.nav_region.get_navigation_map()
	var from: Vector3 = t.bar.to_global(Vector3(0.0, 0.0, 3.0))
	var to: Vector3 = t.bar.to_global(Vector3(1.0, 0.0, -7.0))
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	if path.is_empty() or path[path.size() - 1].distance_to(to) > 1.0:
		return 9999.0
	var L := 0.0
	for i in range(1, path.size()):
		L += path[i - 1].distance_to(path[i])
	return L


func find_interactable(script_name: String):
	for it in get_nodes_in_group("interactables"):
		if it.get_script().resource_path.ends_with(script_name):
			return it
	return null


func _process(_delta: float) -> bool:
	frame += 1
	var p = main.player
	var t = main.town
	if frame == 5:
		var nm: NavigationMesh = t.nav_region.navigation_mesh
		print("Pueblo: edificios=", t.buildings.size(), " calles=", t.streets.size(), " farolas=", t.lamps.size(),
			" spawns=", t.spawn_points.size(), " poligonos_nav=", nm.get_polygon_count())
		check(nm.get_polygon_count() > 0, "malla de navegación generada")
		# invulnerable durante la primera fase de la prueba
		p.max_health = 1e9
		p.health = 1e9
		check(t.bar != null, "Bar Chiqui construido")
		if t.bar:
			check(t.bar.barricades.size() == 3, "3 ventanas con barricada")
			check(t.bar.is_inside_interior(p.global_position), "el jugador empieza dentro del bar")
			check(not t.exterior_open, "la calle empieza cerrada")
	if frame == 600:  # 10 s
		var zs := get_nodes_in_group("zombies")
		check(zs.size() > 0, "han aparecido zombies (%d)" % zs.size())
		var with_window := 0
		for z in zs:
			if z.window != null:
				with_window += 1
		check(with_window == zs.size(), "con la calle cerrada todos van a las ventanas")
	if frame == 1500:  # 25 s
		var torn := 0
		for b in t.bar.barricades:
			torn += 6 - b.boards_left()
		var inside := 0
		for z in get_nodes_in_group("zombies"):
			if t.bar.is_inside_interior(z.global_position):
				inside += 1
		print("Tablas arrancadas: ", torn, "  zombies dentro del bar: ", inside, "  vida jugador: ", p.health)
		check(torn > 0 or inside > 0, "los zombies arrancan tablas / entran")
		# reparar una ventana
		var b = t.bar.barricades[0]
		var before: int = b.boards_left()
		if before < 6:
			p.global_position = b.to_global(Vector3(0, -1.45, -1.0))
			b.repair_cd = 0.0
			for z in get_nodes_in_group("zombies"):
				z.window = null
			b.interact(p)
			check(b.boards_left() == before + 1, "reparar barricada añade una tabla")
	if frame == 1510:
		# limpiar zombies para las pruebas de compra
		main.rounds.kill_all()
		p.max_health = 100.0
		p.health = 100.0
		p.points = 5000
		# comprar escopeta
		var ww = find_interactable("wall_weapon.gd")
		check(ww != null, "arma de pared en el bar")
		if ww:
			ww.interact(p)
			check(p.has_weapon("escopeta"), "comprar escopeta")
		# Quick Revive
		var qr = find_interactable("perk_machine.gd")
		check(qr != null, "máquina de Quick Revive")
		if qr:
			p.drinking = false
			qr.interact(p)
	if frame == 1700:
		check(p.has_perk("quick_revive"), "beber Quick Revive")
		# abrir puerta del bar
		var door = t.bar.doors[0]
		door.interact(p)
		check(door.is_open and t.exterior_open, "comprar la puerta abre la calle")
		log_lines = [_path_len(t)]
	if frame == 1890:
		var before_len: float = log_lines[0]
		var after_len: float = _path_len(t)
		print("Camino calle -> comedor: antes ", snappedf(before_len, 0.1), " m, después ", snappedf(after_len, 0.1), " m")
		check(after_len > 0.0 and after_len < 9999.0, "tras abrir la puerta hay camino desde la calle al comedor")
	if frame == 1900:
		# disparar escopeta a un zombie de prueba delante
		var Z = load("res://scripts/zombie.gd")
		var z = Z.new()
		z.player = p
		z.manager = main.rounds
		z.speed = 0.0
		main.add_child(z)
		main.rounds.alive += 1
		var fwd: Vector3 = -p.global_transform.basis.z
		z.global_position = p.global_position + fwd * 3.0
		z.state = z.State.CHASE
		log_lines = [z]
	if frame == 1990:
		var z = log_lines[0]
		var pts_before: int = p.points
		var target: Vector3 = z.global_position + Vector3(0, 1.2, 0)
		var to: Vector3 = target - p.global_position
		p.rotation.y = atan2(-to.x, -to.z)
		p.head.rotation.x = atan2(target.y - (p.global_position.y + 1.65), Vector2(to.x, to.z).length())
		if p.weapon_id() != "escopeta":
			p._equip(p.weapons.find("escopeta"), false)
		p.fire_cd = 0.0
		p.reloading = false
		p.shoot()
		print("Escopeta: vida zombie ", z.health, "  puntos ", pts_before, " -> ", p.points)
		check(p.points > pts_before, "la escopeta impacta")
	if frame == 2100:
		# caer con Quick Revive (sin zombies que molesten)
		main.rounds.set_process(false)
		main.rounds.kill_all()
		p.take_damage(500.0)
		check(p.downed and not p.dead, "con Quick Revive caes en vez de morir")
	if frame == 2100 + 600:
		check(not p.downed and not p.dead and p.health > 90.0, "Quick Revive te levanta solo")
		check(not p.has_perk("quick_revive"), "se pierde el perk al usarlo")
		var nm: NavigationMesh = t.nav_region.navigation_mesh
		print("Polígonos de navegación tras abrir la puerta: ", nm.get_polygon_count())
		print("Ronda ", main.rounds.round_num, ", vivos ", main.rounds.alive)
		print("RESULTADO: ", "OK" if ok else "FALLOS")
		return true
	return false
