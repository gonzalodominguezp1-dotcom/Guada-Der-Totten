extends RefCounted
## Armas de pared, caja mágica y perks repartidos por las localizaciones
## principales (como en World at War). Posiciones en coordenadas locales de
## cada edificio/nivel; lo que va en el suelo se ajusta a la altura del terreno.

const PerkMachine = preload("res://scripts/perk_machine.gd")
const WallWeapon = preload("res://scripts/wall_weapon.gd")
const MysteryBox = preload("res://scripts/mystery_box.gd")

## [sitio, tipo, id, posición local, giro (rad), tablón]
## sitio: nombre de prefab (landmark_nodes), "bar", "skatepark" o "tanatorio"
const SPOTS := [
	# Bar Chiqui (zona de inicio): Quick Revive y escopeta ya están en bar_chiqui.gd
	["bar", "box", "Bar Chiqui", Vector3(-1.2, 0, -13.35), 0.0, false],
	# Avenida: bazar chino y L'Antica
	["bazar", "wall", "mp40", Vector3(-6.68, 1.45, -3.2), PI * 0.5, false],
	["lantica", "perk", "speed_cola", Vector3(-7.25, 0, -4.2), PI * 0.5, false],
	["lantica", "wall", "kar98", Vector3(7.68, 1.45, -4.0), -PI * 0.5, false],
	# Polideportivo
	["polideportivo", "perk", "juggernog", Vector3(0.0, 0, -0.85), PI, false],
	["polideportivo", "wall", "stg44", Vector3(-14.0, 1.45, -0.36), PI, false],
	["polideportivo", "box", "el Polideportivo", Vector3(14.0, 0, -1.0), PI, false],
	# Plaza Consistorial (delante del Ayuntamiento)
	["ayuntamiento", "perk", "double_tap", Vector3(-6.4, 0, 2.2), 0.0, false],
	["ayuntamiento", "wall", "thompson", Vector3(5.0, 1.45, 0.06), 0.0, false],
	["ayuntamiento", "box", "la Plaza Consistorial", Vector3(5.6, 0, 1.0), 0.0, false],
	# Instituto (vestíbulo)
	["instituto", "wall", "mp40", Vector3(-8.5, 1.45, -3.6), PI * 0.5, false],
	["instituto", "box", "el Instituto", Vector3(-5.8, 0, -7.9), 0.0, false],
	# Segundo Guada (Calle Artes 22)
	["artes22", "wall", "stg44", Vector3(-2.0, 1.4, -0.14), 0.0, false],
	["artes22", "box", "Segundo Guada", Vector3(-5.6, 0, 2.6), 0.0, false],
	# Skatepark
	["skatepark", "wall", "thompson", Vector3(8.0, 1.45, -15.5), 0.0, true],
	["skatepark", "box", "el Skatepark", Vector3(-12.0, 0.08, -12.0), 0.0, false],
	# Tanatorio (junto al portal)
	["tanatorio", "wall", "kar98", Vector3(-14.0, 1.45, 34.0), PI * 0.5, true],
]


static func build(town) -> void:
	town.loadout_items = []
	for sp in SPOTS:
		var parent: Node3D = _parent(town, sp[0])
		if parent == null:
			continue
		var n: Node3D
		match str(sp[1]):
			"wall":
				var ww := WallWeapon.new()
				ww.weapon_id = sp[2]
				ww.board = sp[5]
				n = ww
			"perk":
				var pm := PerkMachine.new()
				pm.perk = sp[2]
				n = pm
			"box":
				var mb := MysteryBox.new()
				mb.place_name = sp[2]
				mb.start = sp[0] == "bar"
				n = mb
		n.position = sp[3]
		n.rotation.y = sp[4]
		parent.add_child(n)
		# en el pueblo con cuesta: lo que va al suelo, a ras del terreno
		if parent != town.skatepark and parent != town.tanatorio and (sp[1] != "wall" or sp[5]):
			var w: Vector3 = parent.global_transform * sp[3] if parent.is_inside_tree() else _world(parent, sp[3])
			var ground: float = town.gy(Vector2(w.x, w.z))
			n.position.y = sp[3].y + ground - _world(parent, Vector3.ZERO).y
		town.loadout_items.append(n)


static func _parent(town, key: String) -> Node3D:
	match key:
		"bar":
			return town.bar
		"skatepark":
			return town.skatepark
		"tanatorio":
			return town.tanatorio
	return town.landmark_nodes.get(key, null)


static func _world(n: Node3D, p: Vector3) -> Vector3:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur is Node3D:
		t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t * p
