extends SceneTree
## Armas de pared, perks, caja mágica y armas nuevas (con su Pack-a-Punch):
##   godot --headless --path . -s tests/loadout_test.gd --fixed-fps 60
const Weapons = preload("res://scripts/weapons.gd")
var main
var f := 0
var fails := 0
var box = null


func _initialize():
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main


func check(ok: bool, what: String) -> void:
	print(("OK    " if ok else "FALLO ") + what)
	if not ok:
		fails += 1


func _process(_d):
	f += 1
	var t = main.town
	var p = main.player
	if f == 3:
		p.max_health = 1e9
		p.health = 1e9
		main.rounds.set_process(false)
		p.points = 1000000
	if f == 10:
		var walls := 0
		var perks := []
		var boxes := 0
		for it in t.loadout_items:
			var sc: String = it.get_script().resource_path.get_file()
			if sc == "wall_weapon.gd":
				walls += 1
				var id: String = it.weapon_id
				it.interact(p)
				check(p.has_weapon(id), "arma de pared: " + id)
			elif sc == "perk_machine.gd":
				perks.append(it.perk)
			elif sc == "mystery_box.gd":
				boxes += 1
				if it.is_active():
					box = it
		check(walls >= 8, "armas de pared repartidas (%d)" % walls)
		check(perks.size() == 3, "Juggernog, Speed Cola y Double Tap en el mapa")
		check(boxes >= 5, "ubicaciones de la caja (%d)" % boxes)
		check(box != null, "hay una caja activa al empezar")
	# cada perk tarda 2,3 s en beberse; se compran de uno en uno
	if f in [20, 200, 380]:
		for it in t.loadout_items:
			if it.get_script().resource_path.get_file() == "perk_machine.gd" and not p.has_perk(it.perk) and not p.busy():
				it.interact(p)
				break
	if f == 560:
		check(p.has_perk("juggernog") and p.max_health >= 250.0, "Juggernog sube la vida")
		check(p.has_perk("speed_cola") and p.has_perk("double_tap"), "Speed Cola y Double Tap")
		if box:
			var before: int = p.points
			box.interact(p)
			check(p.points == before - 950, "la caja cobra 950")
	if f == 560 + 260 and box:
		var st: int = box.state
		if st == box.State.READY:
			var id: String = box.result
			box.interact(p)
			check(p.has_weapon(id), "la caja da un arma: " + id)
		else:
			check(box.state == box.State.LEAVING or box.state == box.State.HIDDEN, "la caja da arma o se va con el osito")
	if f == 900:
		# todas las armas nuevas y su Pack-a-Punch se construyen y disparan
		for id in ["kar98", "mp40", "thompson", "stg44", "mg42", "raygun"]:
			for vid in [id, id + "_pap"]:
				var d: Dictionary = Weapons.data(vid)
				var m: Node3D = Weapons.build_model(vid, true)
				check(m.get_child_count() > 3 and d["damage"] > 0.0, "modelo y datos: " + vid)
				m.free()
				p.give_weapon(vid)
				p.fire_cd = 0.0
				p.reloading = false
				var mag: int = p.ammo[vid]["mag"]
				p.shoot()
				check(p.ammo[vid]["mag"] == mag - 1, "dispara: " + vid)
		check(Weapons.data("mp40")["pap"] == "mp40_pap", "las armas normales tienen Pack-a-Punch")
		print("RESULTADO: " + ("OK" if fails == 0 else "%d FALLOS" % fails))
		return true
	return false
