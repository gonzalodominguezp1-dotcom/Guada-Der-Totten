extends RefCounted
## Edificios en los que se puede entrar (y el Ayuntamiento):
##   - "bazar":         bazar chino de Av. Alejandro Rubio 2 (mostrador a la derecha). Pieza: cañón.
##   - "lantica":       restaurante L'Antica, al oeste del aparcamiento. Pieza: la tele.
##   - "polideportivo": pista de fútbol sala, gradas, espalderas y garita. Pieza: calzoncillo.
##   - "ayuntamiento":  fachada de sillería con espadaña y reloj; mesa de trabajo delante.
## Origen local: centro del frente, a ras de suelo; +Z = fuera (calle o plaza).

const L = preload("res://scripts/landmarks.gd")
const BuyDoor = preload("res://scripts/buy_door.gd")
const PartPickup = preload("res://scripts/part_pickup.gd")
const Workbench = preload("res://scripts/workbench.gd")
const INTERIOR_SHADER = preload("res://shaders/interior_wall.gdshader")
const FLOOR_SHADER = preload("res://shaders/terracotta_floor.gdshader")
const COURT_SHADER = preload("res://shaders/court.gdshader")
const GRILLE_SHADER = preload("res://shaders/grille.gdshader")


static func _m(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	return L._m(c, rough, metal)


static func _soft(town, c: Color, rough := 0.8, scale := 1.0) -> StandardMaterial3D:
	var m := _m(c, rough)
	m.albedo_texture = town.soft_noise
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	return m


static func _light(parent: Node3D, pos: Vector3, c: Color, energy: float, rng_m: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = c
	l.light_energy = energy
	l.omni_range = rng_m
	l.omni_attenuation = 1.2
	parent.add_child(l)
	return l


static func _floor(parent: Node3D, center: Vector3, size: Vector2, mat: Material) -> void:
	var pm := PlaneMesh.new()
	pm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = mat
	mi.position = center
	parent.add_child(mi)


## Caja de edificio hueca con huecos de puerta.
## o: {w, d, h, kind, style, tint, seed, windows, doors:[{face, t0, t1, h}],
##     lining (Material o null), ceil_h, roof ("hip" o "none")}
## Caras: front (+Z), right (+X), back (-Z), left (-X); t medido desde el inicio de la cara.
static func shell(root: Node3D, town, o: Dictionary) -> void:
	var w: float = o["w"]
	var d: float = o["d"]
	var h: float = o["h"]
	var xa := -w * 0.5
	var xb := w * 0.5
	var faces := {
		"front": [Vector2(xa, 0), Vector2(xb, 0)],
		"right": [Vector2(xb, 0), Vector2(xb, -d)],
		"back": [Vector2(xb, -d), Vector2(xa, -d)],
		"left": [Vector2(xa, -d), Vector2(xa, 0)],
	}
	var col: Color = o.get("tint", Color(0.9, 0.8, 0.6))
	col.a = float(int(o["kind"]) * 64 + int(o.get("style", 0)) * 16 + int(o.get("seed", 3)) % 16) / 255.0
	var lining: Material = o.get("lining", null)
	var ceil_h: float = o.get("ceil_h", 0.0)
	var thick := 0.3
	for fname in faces:
		var a: Vector2 = faces[fname][0]
		var b: Vector2 = faces[fname][1]
		var Lf := a.distance_to(b)
		var dir := (b - a) / Lf
		var n := Vector2(-dir.y, dir.x)   # hacia fuera
		var holes: Array = []
		for dr in o.get("doors", []):
			if dr["face"] == fname:
				holes.append([dr["t0"], dr["t1"], dr["h"]])
		holes.sort_custom(func(p, q): return p[0] < q[0])
		var pieces: Array = []   # [t0, t1, y0, y1]
		var t := 0.0
		for hl in holes:
			if hl[0] > t:
				pieces.append([t, hl[0], 0.0, h])
			pieces.append([hl[0], hl[1], hl[2], h])
			t = hl[1]
		if t < Lf:
			pieces.append([t, Lf, 0.0, h])
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var uv2 := Vector2(Lf if o.get("windows", true) else 0.0, h)
		for pc in pieces:
			var p0: Vector2 = a + dir * pc[0]
			var p1: Vector2 = a + dir * pc[1]
			var y0: float = pc[2] if pc[2] > 0.0 else -0.2
			var y1: float = pc[3]
			town._quad(st, Vector3(p0.x, y0, p0.y), Vector3(p1.x, y0, p1.y), Vector3(p1.x, y1, p1.y), Vector3(p0.x, y1, p0.y),
				Vector2(pc[0], y0), Vector2(pc[1], y0), Vector2(pc[1], y1), Vector2(pc[0], y1), Vector3(n.x, 0, n.y), uv2, col)
			# colisión de cada trozo
			var mid: Vector2 = (p0 + p1) * 0.5 - n * thick * 0.5
			var body := StaticBody3D.new()
			body.position = Vector3(mid.x, (y0 + y1) * 0.5, mid.y)
			body.rotation.y = atan2(-dir.y, dir.x)
			root.add_child(body)
			var cs := CollisionShape3D.new()
			var sh := BoxShape3D.new()
			sh.size = Vector3(p0.distance_to(p1), y1 - y0, thick)
			cs.shape = sh
			body.add_child(cs)
			# revestimiento interior
			if lining:
				var top := ceil_h if ceil_h > 0.0 else h
				var ly0: float = pc[2]
				if ly0 < top:
					var lm := MeshInstance3D.new()
					var bm := BoxMesh.new()
					bm.size = Vector3(p0.distance_to(p1), top - ly0, 0.02)
					lm.mesh = bm
					lm.material_override = lining
					var lmid: Vector2 = (p0 + p1) * 0.5 - n * (thick + 0.01)
					lm.position = Vector3(lmid.x, (ly0 + top) * 0.5, lmid.y)
					lm.rotation.y = atan2(-dir.y, dir.x)
					root.add_child(lm)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = town.facade_mat
		root.add_child(mi)
	if ceil_h > 0.0:
		L._box(root, Vector3(0, ceil_h + 0.1, -d * 0.5), Vector3(w - 0.62, 0.2, d - 0.62), _soft(town, Color(0.85, 0.84, 0.8), 0.95, 0.5))
	if o.get("roof", "hip") == "hip":
		town._hip_roof(root, PackedVector2Array([Vector2(xa, 0), Vector2(xb, 0), Vector2(xb, -d), Vector2(xa, -d)]), h, false)


# ---------------------------------------------------------------- bazar chino (nº 2)

static func bazar(root: Node3D, town) -> void:
	var w := 14.0
	var d := 11.0
	var door_x := -0.3
	var tile := ShaderMaterial.new()
	tile.shader = FLOOR_SHADER
	tile.set_shader_parameter("noise_tex", town.noise_tex)
	tile.set_shader_parameter("base", Color(0.78, 0.78, 0.76))
	tile.set_shader_parameter("tile", 0.45)
	var lining := _soft(town, Color(0.86, 0.86, 0.83), 0.9, 0.6)
	shell(root, town, {"w": w, "d": d, "h": 9.4, "kind": 2, "style": 2, "tint": Color(0.8, 0.5, 0.35), "seed": 3,
		"doors": [{"face": "front", "t0": w * 0.5 + door_x - 0.75, "t1": w * 0.5 + door_x + 0.75, "h": 2.4}],
		"lining": lining, "ceil_h": 3.0})
	_floor(root, Vector3(0, 0.02, -d * 0.5), Vector2(w - 0.6, d - 0.6), tile)
	# exterior: toldo, carteles, balcones, paso de cebra (como antes)
	var blue := _m(Color(0.08, 0.25, 0.65), 0.5)
	var orange := _m(Color(0.88, 0.38, 0.10), 0.5)
	var white := _m(Color(0.92, 0.92, 0.9), 0.6)
	var iron := _m(Color(0.04, 0.04, 0.05), 0.5, 0.5)
	var slab := _m(Color(0.6, 0.45, 0.35), 0.8)
	L._box(root, Vector3(0, 2.75, 0.18), Vector3(w + 0.1, 0.35, 0.35), blue)
	L._box(root, Vector3(w * 0.5 + 0.18, 2.75, -d * 0.5), Vector3(0.35, 0.35, d + 0.1), blue)
	L._label(root, "TODO PARA EL HOGAR · ROPA Y COMPLEMENTOS", Vector3(-3.6, 2.75, 0.37), 36, Color(0.95, 0.95, 0.9), 0.0045)
	var s1 := L._box(root, Vector3(3.0, 3.35, 0.12), Vector3(3.2, 0.75, 0.08), orange)
	L._label(s1, "ALIMENTACIÓN Y BAZAR", Vector3(0, 0, 0.05), 56, Color(1, 0.95, 0.75), 0.0045, 6, Color(0.5, 0.1, 0.0))
	var s2 := L._box(root, Vector3(door_x, 2.35, 0.22), Vector3(1.0, 0.36, 0.06), _m(Color(0.8, 0.12, 0.1), 0.5))
	L._label(s2, "BAZAR", Vector3(0, 0, 0.04), 48, Color(1, 0.9, 0.3), 0.0045)
	var s3 := L._box(root, Vector3(w * 0.5 + 0.1, 3.35, -3.0), Vector3(0.06, 0.7, 2.2), white)
	L._label(s3, "ZAPATERÍA", Vector3(0.04, 0.05, 0), 52, Color(0.75, 0.1, 0.1), 0.0045, 0, Color.BLACK, Vector3(0, PI * 0.5, 0))
	for fl in [1, 2]:
		var y: float = fl * 3.0 + 0.05
		L._box(root, Vector3(-3.6, y, 0.55), Vector3(4.2, 0.15, 1.1), slab)
		L._box(root, Vector3(-3.6, y + 0.55, 1.08), Vector3(4.2, 0.05, 0.05), iron)
		for k in 15:
			L._box(root, Vector3(-5.6 + k * 0.29, y + 0.3, 1.08), Vector3(0.025, 0.5, 0.025), iron)
		L._box(root, Vector3(3.8, y + 1.45, 0.45), Vector3(3.2, 2.9, 0.9), _m(Color(0.66, 0.36, 0.24), 0.9))
		L._box(root, Vector3(3.8, y + 1.6, 0.92), Vector3(2.4, 1.4, 0.04), _m(Color(0.75, 0.72, 0.64), 0.7))
	var paint := _m(Color(0.85, 0.85, 0.82), 0.7)
	for k in 6:
		L._box(root, Vector3(w * 0.5 + 2.6, 0.03, 2.4 + k * 0.95), Vector3(3.0, 0.02, 0.5), paint)
	L._cyl(root, Vector3(w * 0.5 + 0.5, 1.3, 1.2), 0.035, 0.035, 2.6, _m(Color(0.6, 0.6, 0.62), 0.4, 0.6))
	var sign := L._box(root, Vector3(w * 0.5 + 0.5, 2.65, 1.2), Vector3(0.55, 0.55, 0.03), blue)
	L._label(sign, "▲", Vector3(0, 0, 0.02), 90, Color.WHITE, 0.004)
	# puerta que se compra
	var door := BuyDoor.new()
	door.cost = 750
	door.label = "entrar en el bazar"
	door.size = Vector3(1.5, 2.4, 0.08)
	door.style = "double_glass"
	root.add_child(door)
	door.position = Vector3(door_x, 1.2, 0.0)

	# ---- interior: bazar chino con el mostrador a la derecha según entras
	var shelf_mat := _m(Color(0.75, 0.76, 0.78), 0.4, 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	# estanterías (góndolas) de fondo a fondo
	for gx in [-5.6, -3.2, -0.9]:
		_gondola(root, Vector3(gx, 0, -6.2), 7.0, shelf_mat, rng, gx < -5.0)
	# estantería en la pared del fondo
	_gondola(root, Vector3(1.5, 0, -10.3), 9.0, shelf_mat, rng, true, true)
	# mostrador a la derecha
	var counter_mat := _m(Color(0.80, 0.12, 0.10), 0.5)
	var top_mat := _m(Color(0.9, 0.88, 0.82), 0.3)
	L._box(root, Vector3(4.3, 0.5, -2.6), Vector3(0.7, 1.0, 3.4), counter_mat, true)
	L._box(root, Vector3(5.6, 0.5, -4.1), Vector3(2.0, 1.0, 0.7), counter_mat, true)
	L._box(root, Vector3(4.3, 1.03, -2.6), Vector3(0.8, 0.06, 3.5), top_mat)
	L._box(root, Vector3(5.6, 1.03, -4.1), Vector3(2.1, 0.06, 0.8), top_mat)
	L._box(root, Vector3(4.3, 1.2, -1.6), Vector3(0.4, 0.3, 0.35), _m(Color(0.15, 0.15, 0.17), 0.4))   # caja registradora
	# gato de la suerte dorado
	var gold := _m(Color(0.95, 0.75, 0.2), 0.25, 1.0)
	var cat := Node3D.new()
	cat.position = Vector3(4.3, 1.06, -3.3)
	root.add_child(cat)
	var body := SphereMesh.new()
	body.radius = 0.09
	body.height = 0.2
	L._box(cat, Vector3(0, 0.09, 0), Vector3(0.14, 0.16, 0.11), gold)
	var head_mi := MeshInstance3D.new()
	head_mi.mesh = body
	head_mi.material_override = gold
	head_mi.position = Vector3(0, 0.23, 0)
	cat.add_child(head_mi)
	var paw := L._box(cat, Vector3(0.08, 0.28, 0.0), Vector3(0.04, 0.12, 0.04), gold)
	paw.rotation.z = 0.3
	# farolillos rojos colgando
	var red_lamp := _m(Color(0.85, 0.1, 0.08), 0.6)
	red_lamp.emission_enabled = true
	red_lamp.emission = Color(0.8, 0.1, 0.05)
	red_lamp.emission_energy_multiplier = 0.6
	for p in [Vector3(-4.4, 2.5, -2.2), Vector3(-2.0, 2.5, -4.5), Vector3(2.2, 2.5, -2.5), Vector3(-4.4, 2.5, -8.0), Vector3(0.4, 2.5, -7.5)]:
		var lm := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.2
		sm.height = 0.34
		lm.mesh = sm
		lm.material_override = red_lamp
		lm.position = p
		root.add_child(lm)
		L._box(root, p + Vector3(0, 0.3, 0), Vector3(0.01, 0.3, 0.01), iron)
	# fluorescentes
	var tube := _m(Color(0.95, 0.97, 1.0), 0.5)
	tube.emission_enabled = true
	tube.emission = Color(0.9, 0.95, 1.0)
	tube.emission_energy_multiplier = 2.5
	for p in [Vector3(-3.0, 2.95, -3.0), Vector3(-3.0, 2.95, -7.5), Vector3(2.5, 2.95, -3.0), Vector3(2.5, 2.95, -7.5)]:
		L._box(root, p, Vector3(1.4, 0.05, 0.12), tube)
	_light(root, Vector3(-2.5, 2.6, -3.5), Color(0.85, 0.92, 1.0), 0.9, 7.0)
	var fl_l := _light(root, Vector3(1.5, 2.6, -7.5), Color(0.85, 0.92, 1.0), 0.8, 7.0)
	town.lamps.append({"light": fl_l, "base": 0.8, "mode": "flicker", "speed": 17.0})
	L._label(root, "TODO A 1 €", Vector3(-3.2, 2.35, -2.66), 48, Color(1.0, 0.85, 0.1), 0.005, 6, Color(0.6, 0.0, 0.0))
	# pieza: el cañón, encima del mostrador
	var part := PartPickup.new()
	part.part = "canon"
	root.add_child(part)
	part.position = Vector3(4.3, 1.1, -2.5)


## Góndola de estanterías con productos de colores (MultiMesh)
static func _gondola(root: Node3D, c: Vector3, length: float, mat: Material, rng: RandomNumberGenerator,
		one_side := false, along_x := false) -> void:
	var size := Vector3(0.9 if not one_side else 0.45, 1.9, length)
	if along_x:
		size = Vector3(length, 1.9, 0.45)
	L._box(root, c + Vector3(0, 0.95, 0), size, mat, true)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var bm := BoxMesh.new()
	bm.size = Vector3(1, 1, 1)
	var pm := StandardMaterial3D.new()
	pm.vertex_color_use_as_albedo = true
	pm.roughness = 0.6
	bm.material = pm
	mm.mesh = bm
	var items: Array = []
	var sides := [1.0] if one_side else [1.0, -1.0]
	for lvl in 4:
		var y := 0.25 + lvl * 0.45
		var t := -length * 0.5 + 0.15
		while t < length * 0.5 - 0.15:
			var sz := Vector3(rng.randf_range(0.12, 0.28), rng.randf_range(0.12, 0.35), rng.randf_range(0.12, 0.25))
			for sd in sides:
				var pos: Vector3
				if along_x:
					pos = Vector3(t, y + sz.y * 0.5, size.z * 0.5 * sd + sz.z * 0.5 * sd)
				else:
					pos = Vector3(size.x * 0.5 * sd + sz.z * 0.5 * sd, y + sz.y * 0.5, t)
				var col := Color.from_hsv(rng.randf(), rng.randf_range(0.5, 0.9), rng.randf_range(0.6, 1.0))
				items.append([Transform3D(Basis.from_scale(sz), c + pos), col])
			t += sz.x + 0.03
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, items[i][0])
		mm.set_instance_color(i, items[i][1])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	root.add_child(mmi)


# ---------------------------------------------------------------- L'Antica

static func lantica(root: Node3D, town) -> void:
	var w := 16.0
	var d := 10.0
	var door_t := w * 0.5 + 6.3
	var lining := ShaderMaterial.new()
	lining.shader = INTERIOR_SHADER
	lining.set_shader_parameter("noise_tex", town.noise_tex)
	lining.set_shader_parameter("upper", Color(0.88, 0.80, 0.64))
	lining.set_shader_parameter("lower", Color(0.28, 0.16, 0.08))
	shell(root, town, {"w": w, "d": d, "h": 6.6, "kind": 1, "style": 1, "tint": Color(0.9, 0.8, 0.6), "seed": 7,
		"doors": [{"face": "front", "t0": door_t - 0.8, "t1": door_t + 0.8, "h": 2.6}],
		"lining": lining, "ceil_h": 3.2})
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = FLOOR_SHADER
	floor_mat.set_shader_parameter("noise_tex", town.noise_tex)
	floor_mat.set_shader_parameter("base", Color(0.50, 0.32, 0.20))
	_floor(root, Vector3(0, 0.02, -d * 0.5), Vector2(w - 0.6, d - 0.6), floor_mat)
	var wood := _soft(town, Color(0.30, 0.18, 0.09), 0.6, 2.0)
	var brick := _m(Color(0.62, 0.32, 0.22), 0.9)
	# fachada: esquinas de ladrillo, aleros de madera, cartel, balcón de la esquina
	for x in [-w * 0.5, w * 0.5]:
		L._box(root, Vector3(x, 3.3, 0.02), Vector3(0.5, 6.6, 0.08), brick)
	L._box(root, Vector3(0, 3.25, 0.06), Vector3(w, 0.18, 0.1), brick)
	L._box(root, Vector3(0, 6.6, 0.3), Vector3(w + 0.8, 0.12, 0.7), wood)
	for k in 16:
		L._box(root, Vector3(-w * 0.5 + 0.5 + k, 6.5, 0.3), Vector3(0.1, 0.12, 0.6), wood)
	var board := L._box(root, Vector3(-1.5, 2.85, 0.1), Vector3(5.0, 0.55, 0.08), _m(Color(0.08, 0.08, 0.08), 0.5))
	L._label(board, "L'ANTICA  ·  RISTORANTE", Vector3(0, 0, 0.05), 64, Color(0.95, 0.8, 0.45), 0.005)
	L._box(root, Vector3(w * 0.5 - 1.3, 4.0, 0.5), Vector3(2.0, 0.12, 1.0), wood)
	for k in 9:
		L._box(root, Vector3(w * 0.5 - 2.2 + k * 0.22, 4.45, 0.98), Vector3(0.03, 0.8, 0.03), _m(Color(0.05, 0.05, 0.05), 0.5))
	# verja de forja abierta en la puerta de la esquina
	var gate := L._box(root, Vector3(door_t - w * 0.5 + 0.9, 1.3, 0.75), Vector3(0.05, 2.5, 1.5), _m(Color(0.12, 0.1, 0.08), 0.5, 0.4))
	gate.rotation.y = 0.15
	# pizarra con el menú
	var chalk := L._box(root, Vector3(door_t - w * 0.5 - 1.4, 0.7, 0.5), Vector3(0.6, 1.0, 0.04), _m(Color(0.1, 0.12, 0.1), 0.8))
	L._label(chalk, "MENÚ\nDEL DÍA\n12 €", Vector3(0, 0.05, 0.03), 36, Color(0.95, 0.95, 0.9), 0.004)
	# ---- interior
	var cloth := _m(Color(0.93, 0.92, 0.88), 0.85)
	var napkin := _m(Color(0.7, 0.08, 0.08), 0.8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	for p in [Vector2(-5.5, -2.5), Vector2(-2.5, -2.5), Vector2(0.5, -2.5), Vector2(-5.5, -5.5), Vector2(-2.5, -5.5), Vector2(0.5, -5.5)]:
		var t := StaticBody3D.new()
		t.position = Vector3(p.x, 0, p.y)
		root.add_child(t)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(0.9, 0.8, 0.9)
		cs.shape = sh
		cs.position.y = 0.4
		t.add_child(cs)
		L._box(t, Vector3(0, 0.66, 0), Vector3(1.0, 0.24, 1.0), cloth)
		L._box(t, Vector3(0.2, 0.79, 0.2), Vector3(0.25, 0.01, 0.25), napkin)
		L._cyl(t, Vector3(-0.2, 0.92, -0.1), 0.035, 0.04, 0.3, _m(Color(0.1, 0.25, 0.1, 0.9), 0.1))   # botella de vino
		for k in 4:
			var a := TAU * k / 4.0
			var ch := Node3D.new()
			ch.position = Vector3(sin(a) * 0.72, 0, cos(a) * 0.72)
			ch.rotation.y = a
			t.add_child(ch)
			L._box(ch, Vector3(0, 0.46, 0), Vector3(0.42, 0.05, 0.42), wood)
			L._box(ch, Vector3(0, 0.75, 0.19), Vector3(0.42, 0.55, 0.04), wood)
			for x in [-0.18, 0.18]:
				for z in [-0.18, 0.18]:
					L._box(ch, Vector3(x, 0.23, z), Vector3(0.04, 0.46, 0.04), wood)
	# barra al fondo a la derecha, con la tele encima (pieza)
	L._box(root, Vector3(4.6, 0.55, -7.6), Vector3(5.0, 1.1, 0.7), wood, true)
	L._box(root, Vector3(4.6, 1.13, -7.6), Vector3(5.2, 0.06, 0.85), _m(Color(0.75, 0.73, 0.68), 0.25))
	L._box(root, Vector3(4.6, 1.6, -9.6), Vector3(5.0, 2.0, 0.3), wood)
	for k in 3:
		for b in 14:
			L._cyl(root, Vector3(2.4 + b * 0.32, 1.25 + k * 0.5, -9.4), 0.035, 0.04, 0.3,
				_m(Color.from_hsv(rng.randf_range(0.0, 0.35), 0.7, rng.randf_range(0.2, 0.6), 0.85), 0.1), Vector3.ZERO, 8)
	var part := PartPickup.new()
	part.part = "tele"
	root.add_child(part)
	part.position = Vector3(3.8, 1.18, -7.6)
	# horno de leña en la esquina del fondo
	var dome := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 1.0
	dm.height = 1.2
	dm.is_hemisphere = true
	dome.mesh = dm
	dome.material_override = brick
	dome.position = Vector3(-6.5, 1.0, -8.5)
	root.add_child(dome)
	L._box(root, Vector3(-6.5, 0.5, -8.5), Vector3(2.0, 1.0, 2.0), _m(Color(0.6, 0.58, 0.55), 0.9), true)
	var fire := _m(Color(1.0, 0.5, 0.1), 0.5)
	fire.emission_enabled = true
	fire.emission = Color(1.0, 0.45, 0.1)
	fire.emission_energy_multiplier = 3.0
	L._box(root, Vector3(-6.5, 1.25, -7.55), Vector3(0.6, 0.4, 0.05), fire)
	var fl := _light(root, Vector3(-6.5, 1.3, -7.0), Color(1.0, 0.5, 0.2), 1.4, 5.0)
	town.lamps.append({"light": fl, "base": 1.4, "mode": "flicker", "speed": 7.0})
	# bandera italiana y lámparas
	for k in 3:
		L._box(root, Vector3(-2.0 + k * 0.5, 2.3, -d + 0.34), Vector3(0.5, 0.7, 0.02),
			_m([Color(0.1, 0.5, 0.2), Color(0.95, 0.95, 0.9), Color(0.75, 0.1, 0.1)][k], 0.8))
	for p in [Vector3(-4.0, 2.7, -4.0), Vector3(-0.5, 2.7, -4.0), Vector3(3.5, 2.7, -6.0)]:
		L._cyl(root, p, 0.08, 0.25, 0.2, _m(Color(0.15, 0.1, 0.05), 0.6))
		_light(root, p - Vector3(0, 0.25, 0), Color(1.0, 0.75, 0.45), 0.9, 6.0)


# ---------------------------------------------------------------- polideportivo

static func polideportivo(root: Node3D, town) -> void:
	var w := 46.0
	var d := 30.0
	var h := 8.0
	var hw := w * 0.5
	var doors := [{"face": "front", "t0": hw - 9.0 - 1.1, "t1": hw - 9.0 + 1.1, "h": 2.6},
		{"face": "front", "t0": hw + 9.0 - 1.1, "t1": hw + 9.0 + 1.1, "h": 2.6}]
	shell(root, town, {"w": w, "d": d, "h": h, "kind": 2, "style": 3, "tint": Color(0.8, 0.8, 0.8), "seed": 5,
		"windows": false, "doors": doors, "roof": "none",
		"lining": _soft(town, Color(0.72, 0.72, 0.70), 0.95, 0.4)})
	var yellow := _m(Color(0.95, 0.75, 0.1), 0.5)
	var white := _m(Color(0.92, 0.92, 0.9), 0.7)
	var concrete := _soft(town, Color(0.78, 0.77, 0.74), 0.9, 0.5)
	var metal := _m(Color(0.6, 0.62, 0.64), 0.5, 0.5)
	var glass := _m(Color(0.08, 0.1, 0.12), 0.1)
	# pilastras amarillas, franja blanca y ventanas altas
	for zf in [0.0, -d]:
		var out := 0.15 if zf == 0.0 else -0.15
		var x := -hw + 2.5
		while x < hw:
			L._box(root, Vector3(x, h * 0.5, zf + out), Vector3(0.35, h + 0.2, 0.25), yellow)
			if x + 2.5 < hw:
				L._box(root, Vector3(x + 2.5, 6.7, zf + out * 0.5), Vector3(4.2, 1.0, 0.06), glass)
			x += 5.0
		L._box(root, Vector3(0, h - 0.3, zf + out * 0.6), Vector3(w + 0.2, 0.6, 0.1), white)
	# puertas amarillas abiertas
	for dx in [-9.0, 9.0]:
		for side in [-1.0, 1.0]:
			var leaf := L._box(root, Vector3(dx + side * 1.6, 1.3, 0.6), Vector3(1.1, 2.6, 0.06), yellow)
			leaf.rotation.y = side * 1.35
		L._box(root, Vector3(dx, 2.75, 0.1), Vector3(2.4, 0.3, 0.2), yellow)
	var plaque := L._box(root, Vector3(0, 3.4, 0.08), Vector3(5.5, 0.6, 0.05), _m(Color(0.15, 0.25, 0.55), 0.5))
	L._label(plaque, "POLIDEPORTIVO MUNICIPAL", Vector3(0, 0, 0.04), 64, Color.WHITE, 0.0055)
	# tejado a dos aguas (cumbrera a lo largo)
	var roof_mat := _m(Color(0.55, 0.57, 0.58), 0.5, 0.4)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ridge := h + 2.6
	var o := 0.5
	town._quad(st, Vector3(-hw - o, h, o), Vector3(hw + o, h, o), Vector3(hw + o, ridge, -d * 0.5), Vector3(-hw - o, ridge, -d * 0.5),
		Vector2.ZERO, Vector2(w, 0), Vector2(w, 15), Vector2(0, 15), Vector3(0, 0.98, 0.17))
	town._quad(st, Vector3(hw + o, h, -d - o), Vector3(-hw - o, h, -d - o), Vector3(-hw - o, ridge, -d * 0.5), Vector3(hw + o, ridge, -d * 0.5),
		Vector2.ZERO, Vector2(w, 0), Vector2(w, 15), Vector2(0, 15), Vector3(0, 0.98, -0.17))
	for x in [-hw, hw]:
		var nx := 1.0 if x > 0 else -1.0
		town._tri(st, [Vector3(x, h, 0), Vector3(x, h, -d), Vector3(x, ridge, -d * 0.5)], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO],
			Vector3(nx, 0, 0), Vector2.ZERO, Color.WHITE)
	var roof := MeshInstance3D.new()
	roof.mesh = st.commit()
	roof.material_override = roof_mat
	root.add_child(roof)
	# aletas de hormigón en el testero oeste (local +X)
	for k in 5:
		L._box(root, Vector3(hw + 0.6, (h + 1.5) * 0.5, -6.0 - k * 4.5), Vector3(1.2, h + 1.5, 0.3), concrete)
	# ---- interior
	var court := ShaderMaterial.new()
	court.shader = COURT_SHADER
	court.set_shader_parameter("noise_tex", town.noise_tex)
	court.set_shader_parameter("court", Vector2(40.0, 20.0))
	var pm := PlaneMesh.new()
	pm.size = Vector2(w - 0.6, d - 0.6)
	var cmi := MeshInstance3D.new()
	cmi.mesh = pm
	cmi.material_override = court
	cmi.position = Vector3(0, 0.02, -d * 0.5 + 1.2)
	root.add_child(cmi)
	# porterías
	var net := ShaderMaterial.new()
	net.shader = GRILLE_SHADER
	for gx in [-20.0, 20.0]:
		var s := 1.0 if gx > 0 else -1.0
		var g := Node3D.new()
		g.position = Vector3(gx, 0, -d * 0.5 + 1.2)
		root.add_child(g)
		for z in [-1.5, 1.5]:
			L._box(g, Vector3(0, 1.0, z), Vector3(0.08, 2.0, 0.08), white, true)
		L._box(g, Vector3(0, 2.0, 0), Vector3(0.08, 0.08, 3.08), white)
		L._box(g, Vector3(s * 0.5, 1.0, 0), Vector3(0.02, 2.0, 3.0), net)
		L._box(g, Vector3(s * 0.25, 2.0, 0), Vector3(0.5, 0.02, 3.0), net)
	# gradas en alto al fondo (frente a las puertas), con las espalderas debajo
	var stand_front := -d + 4.2
	# muro bajo las gradas, con el hueco de la puerta de la garita (x 17.3..18.7)
	var wl := -hw + 0.3
	L._box(root, Vector3((wl + 17.2) * 0.5, 1.3, stand_front - 0.15), Vector3(17.2 - wl, 2.6, 0.3), concrete, true)
	L._box(root, Vector3((18.8 + hw - 0.3) * 0.5, 1.3, stand_front - 0.15), Vector3(hw - 0.3 - 18.8, 2.6, 0.3), concrete, true)
	L._box(root, Vector3(18.0, 2.4, stand_front - 0.15), Vector3(1.6, 0.4, 0.3), concrete)
	L._box(root, Vector3(0, 2.75, stand_front - 0.8), Vector3(w - 0.6, 0.3, 1.6), concrete, true)
	var top_z0 := stand_front - 1.6
	var top_z1 := -d + 0.3
	L._box(root, Vector3(0, 3.2, (top_z0 + top_z1) * 0.5), Vector3(w - 0.6, 1.2, top_z0 - top_z1), concrete, true)
	for x in range(-21, 22, 3):
		L._box(root, Vector3(x, 3.4, stand_front + 0.02), Vector3(0.05, 1.0, 0.05), metal)
	L._box(root, Vector3(0, 3.9, stand_front + 0.02), Vector3(w - 0.6, 0.06, 0.06), metal)
	# asientos de colores en las gradas
	var seat_cols := [Color(0.85, 0.1, 0.1), Color(0.1, 0.3, 0.8), Color(0.95, 0.75, 0.1)]
	var x2 := -21.5
	var i := 0
	while x2 < 21.5:
		L._box(root, Vector3(x2, 3.0, stand_front - 0.9), Vector3(0.42, 0.12, 0.38), _m(seat_cols[i % 3], 0.5))
		L._box(root, Vector3(x2, 3.9, (top_z0 + top_z1) * 0.5), Vector3(0.42, 0.12, 0.38), _m(seat_cols[(i + 1) % 3], 0.5))
		x2 += 0.55
		i += 1
	# espalderas de madera bajo las gradas
	var bars := _m(Color(0.62, 0.45, 0.25), 0.6)
	for k in 12:
		var x := -12.0 + k * 1.0
		L._box(root, Vector3(x, 1.25, stand_front + 0.05), Vector3(0.08, 2.5, 0.08), bars)
	for k in 16:
		L._box(root, Vector3(-6.5, 0.15 + k * 0.155, stand_front + 0.12), Vector3(11.0, 0.035, 0.035), bars)
	# garita: debajo de las gradas, a la derecha según entras
	var gx0 := 15.0
	L._box(root, Vector3(gx0, 1.3, (stand_front + -d) * 0.5), Vector3(0.2, 2.6, d - stand_front * -1.0 - 0.1), concrete, true)
	L._box(root, Vector3(17.25, 1.05, stand_front - 1.0), Vector3(0.05, 2.1, 1.3), _m(Color(0.25, 0.3, 0.35), 0.5, 0.3))
	var sign := L._box(root, Vector3(18.0, 2.75, stand_front + 0.02), Vector3(1.2, 0.3, 0.04), white)
	L._label(sign, "CONSERJERÍA", Vector3(0, 0, 0.03), 40, Color(0.1, 0.1, 0.1), 0.004)
	L._box(root, Vector3(20.5, 1.6, stand_front - 0.15), Vector3(1.6, 0.9, 0.34), glass)
	# dentro: mesa, silla, radio, llavero... y el calzoncillo
	var desk := _soft(town, Color(0.5, 0.42, 0.3), 0.7)
	L._box(root, Vector3(20.6, 0.4, -d + 0.65), Vector3(2.0, 0.8, 0.7), desk, true)
	L._box(root, Vector3(19.9, 0.95, -d + 0.6), Vector3(0.3, 0.18, 0.15), _m(Color(0.15, 0.15, 0.15), 0.5))
	L._box(root, Vector3(21.8, 1.6, -d + 0.4), Vector3(0.8, 0.6, 0.04), _m(Color(0.6, 0.45, 0.3), 0.7))
	_light(root, Vector3(19.5, 2.3, -d + 2.4), Color(1.0, 0.9, 0.7), 0.6, 4.0)
	var part := PartPickup.new()
	part.part = "calzoncillo"
	root.add_child(part)
	part.position = Vector3(20.9, 0.85, -d + 0.7)
	# canastas en las paredes laterales
	for hx in [-hw + 0.5, hw - 0.5]:
		var s := 1.0 if hx > 0 else -1.0
		L._box(root, Vector3(hx - s * 0.3, 3.6, -d * 0.5 + 1.2), Vector3(0.6, 0.1, 0.1), metal)
		L._box(root, Vector3(hx - s * 0.6, 3.6, -d * 0.5 + 1.2), Vector3(0.05, 1.05, 1.8), white)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.21
		tm.outer_radius = 0.24
		ring.mesh = tm
		ring.material_override = _m(Color(0.95, 0.4, 0.1), 0.5)
		ring.position = Vector3(hx - s * 0.85, 3.05, -d * 0.5 + 1.2)
		root.add_child(ring)
	# banquillos
	for bx in [-6.0, 6.0]:
		L._box(root, Vector3(bx, 0.25, -1.4), Vector3(3.0, 0.5, 0.45), _m(Color(0.2, 0.35, 0.65), 0.6), true)
	# lámparas colgadas (una parpadea) y salida de emergencia
	var k := 0
	for lx in [-12.0, 12.0]:
		for lz in [-8.0, -20.0]:
			L._cyl(root, Vector3(lx, h - 1.2, lz), 0.15, 0.45, 0.4, metal)
			var l := _light(root, Vector3(lx, h - 1.6, lz), Color(0.9, 0.95, 1.0), 1.0, 16.0)
			if k == 1:
				town.lamps.append({"light": l, "base": 1.0, "mode": "dying", "speed": 10.0})
			k += 1
	var exit_mat := _m(Color(0.1, 0.8, 0.3), 0.5)
	exit_mat.emission_enabled = true
	exit_mat.emission = Color(0.1, 0.9, 0.3)
	for dx in [-9.0, 9.0]:
		var ex := L._box(root, Vector3(dx, 3.2, -0.35), Vector3(0.7, 0.25, 0.05), exit_mat)
		L._label(ex, "SALIDA", Vector3(0, 0, -0.03), 40, Color.WHITE, 0.004, 0, Color.BLACK, Vector3(0, PI, 0))


# ---------------------------------------------------------------- Ayuntamiento y plaza

static func ayuntamiento(root: Node3D, town) -> void:
	var w := 16.0
	var d := 12.4
	var h := 8.6
	shell(root, town, {"w": w, "d": d, "h": h, "kind": 3, "style": 1, "tint": Color(0.8, 0.75, 0.65), "seed": 11})
	var stone := _soft(town, Color(0.75, 0.71, 0.63), 0.85, 1.0)
	var iron := _m(Color(0.05, 0.05, 0.05), 0.5, 0.5)
	var wood := _m(Color(0.30, 0.17, 0.08), 0.6)
	# puerta principal, escalinata e impostas
	L._box(root, Vector3(0, 1.5, 0.05), Vector3(1.7, 3.0, 0.12), wood)
	L._box(root, Vector3(0, 1.5, 0.08), Vector3(2.2, 3.4, 0.06), stone)
	for k in 3:
		L._box(root, Vector3(0, 0.08 + k * 0.16, 1.4 - k * 0.4), Vector3(6.0 - k * 1.2, 0.16, 0.8 + k * 0.0), stone, true)
	L._box(root, Vector3(0, h - 0.25, 0.15), Vector3(w + 0.4, 0.4, 0.4), stone)
	L._box(root, Vector3(0, 3.3, 0.12), Vector3(w, 0.2, 0.25), stone)
	# balcón corrido con barandilla y reposteros con escudos
	L._box(root, Vector3(0, 3.45, 0.55), Vector3(w - 1.0, 0.15, 1.0), stone)
	L._box(root, Vector3(0, 4.45, 1.03), Vector3(w - 1.0, 0.05, 0.05), iron)
	for k in 40:
		L._box(root, Vector3(-w * 0.5 + 0.6 + k * 0.38, 3.95, 1.03), Vector3(0.025, 1.0, 0.025), iron)
	var banner_mat := _m(Color(0.95, 0.93, 0.86), 0.9)
	var shield_cols := [Color(0.85, 0.15, 0.1), Color(0.95, 0.8, 0.1), Color(0.15, 0.35, 0.75), Color(0.2, 0.55, 0.25)]
	for bx in [-4.6, 0.0, 4.6]:
		var ban := L._box(root, Vector3(bx, 3.95, 1.06), Vector3(4.2, 0.9, 0.02), banner_mat)
		if bx == 0.0:
			L._label(ban, "GUADALIX DE LA SIERRA", Vector3(0, 0, 0.02), 44, Color(0.5, 0.1, 0.05), 0.0045)
		else:
			for k in 6:
				L._box(ban, Vector3(-1.75 + k * 0.7, -0.05, 0.015), Vector3(0.38, 0.5, 0.01), _m(shield_cols[(k + int(bx)) % 4], 0.6))
	# banderas
	var flags := [[Color(0.75, 0.1, 0.1), Color(0.95, 0.8, 0.1)], [Color(0.8, 0.1, 0.12), Color(0.8, 0.1, 0.12)], [Color(0.1, 0.2, 0.6), Color(0.1, 0.2, 0.6)]]
	for k in 3:
		var pole := Node3D.new()
		pole.position = Vector3(-1.2 + k * 1.2, 4.4, 0.9)
		pole.rotation.x = 0.7
		root.add_child(pole)
		L._cyl(pole, Vector3(0, 0.9, 0), 0.02, 0.02, 1.8, iron)
		L._box(pole, Vector3(0.0, 1.45, 0.45), Vector3(0.02, 0.6, 0.85), _m(flags[k][0], 0.8))
		L._box(pole, Vector3(0.0, 1.45, 0.45), Vector3(0.03, 0.2, 0.85), _m(flags[k][1], 0.8))
	# espadaña con reloj y campana sobre el tejado
	var bt := Node3D.new()
	bt.position = Vector3(0, h + 0.8, -2.2)
	root.add_child(bt)
	L._box(bt, Vector3(0, 0, 0), Vector3(2.4, 0.4, 2.0), stone)
	for x in [-1.0, 1.0]:
		for z in [-0.8, 0.8]:
			L._box(bt, Vector3(x, 1.4, z), Vector3(0.18, 2.4, 0.18), _m(Color(0.6, 0.15, 0.1), 0.6))
	L._box(bt, Vector3(0, 2.7, 0), Vector3(2.6, 0.25, 2.2), _m(Color(0.6, 0.15, 0.1), 0.6))
	var face := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.5
	fm.bottom_radius = 0.5
	fm.height = 0.06
	face.mesh = fm
	face.material_override = _m(Color(0.95, 0.94, 0.88), 0.5)
	face.rotation.x = PI * 0.5
	face.position = Vector3(0, 1.9, 0.85)
	bt.add_child(face)
	var hand := L._box(bt, Vector3(0.1, 1.98, 0.9), Vector3(0.04, 0.35, 0.01), iron)
	hand.rotation.z = -0.8
	L._box(bt, Vector3(0, 1.8, 0.9), Vector3(0.03, 0.3, 0.01), iron)
	L._cyl(bt, Vector3(0, 0.9, 0), 0.12, 0.38, 0.6, _m(Color(0.55, 0.42, 0.2), 0.3, 1.0))
	# placa y farolas de pared
	var plq := L._box(root, Vector3(0, 3.0, 0.11), Vector3(2.6, 0.32, 0.04), stone)
	L._label(plq, "AYUNTAMIENTO", Vector3(0, 0, 0.03), 44, Color(0.25, 0.2, 0.15), 0.0045)
	for lx in [-3.0, 3.0]:
		var lan := MeshInstance3D.new()
		lan.mesh = town._lantern_mesh()
		lan.position = Vector3(lx, 4.9, 0.6)
		lan.set_surface_override_material(0, town.glass_mat)
		lan.set_surface_override_material(1, iron)
		root.add_child(lan)
		_light(root, Vector3(lx, 4.8, 0.9), Color(1.0, 0.7, 0.4), 1.6, 10.0)
	for px in [-2.2, 2.2]:
		L._cyl(root, Vector3(px, 0.25, 2.3), 0.3, 0.22, 0.5, _m(Color(0.5, 0.25, 0.12), 0.8))
	# mesa de trabajo para montar el Cañón de Zurraspa
	var wb := Workbench.new()
	wb.add_to_group("workbench")
	root.add_child(wb)
	wb.position = Vector3(5.8, 0, 3.2)
	wb.rotation.y = -0.4


## Plaza Consistorial: losas, terrazas con sombrillas, bancos, árboles y banderines
static func plaza_decor(area: Dictionary, town) -> void:
	var poly: PackedVector2Array = area["points"]
	var root := Node3D.new()
	root.name = "Decor_" + str(area["name"]).replace(" ", "_")
	town.nav_region.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	# losas grises
	var tris := Geometry2D.triangulate_polygon(poly)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in range(0, tris.size(), 3):
		var vs := []
		for k in 3:
			var p := poly[tris[t + k]]
			vs.append(Vector3(p.x, 0.014, p.y))
		town._tri(st, vs, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], Vector3.UP, Vector2.ZERO, Color.WHITE)
	var slab_mat := ShaderMaterial.new()
	slab_mat.shader = FLOOR_SHADER
	slab_mat.set_shader_parameter("noise_tex", town.noise_tex)
	slab_mat.set_shader_parameter("base", Color(0.62, 0.62, 0.6))
	slab_mat.set_shader_parameter("tile", 0.6)
	if tris.size() >= 3:
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = slab_mat
		root.add_child(mi)
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	var spots: Array = []
	for k in 60:
		var p := Vector2(rng.randf_range(r.position.x, r.end.x), rng.randf_range(r.position.y, r.end.y))
		if not Geometry2D.is_point_in_polygon(p, poly) or town._in_any_building(p, 3.0):
			continue
		var ok := true
		for q in spots:
			if q.distance_to(p) < 6.0:
				ok = false
		if ok:
			spots.append(p)
	var umbrella_cols := [Color(0.15, 0.4, 0.25), Color(0.92, 0.92, 0.88)]
	var metal := _m(Color(0.5, 0.5, 0.5), 0.4, 0.6)
	var i := 0
	for p in spots:
		var pos := Vector3(p.x, 0, p.y)
		match i % 3:
			0:
				# terraza: mesa con sombrilla y sillas
				var t := L._box(root, pos + Vector3(0, 0.37, 0), Vector3(0.7, 0.74, 0.7), metal, true)
				L._cyl(root, pos + Vector3(0, 1.4, 0), 0.025, 0.025, 2.8, metal)
				var cone := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.05
				cm.bottom_radius = 1.4
				cm.height = 0.5
				cone.mesh = cm
				cone.material_override = _m(umbrella_cols[(i / 3) % 2], 0.8)
				cone.position = pos + Vector3(0, 2.6, 0)
				root.add_child(cone)
				for k in 3:
					var a := TAU * k / 3.0 + rng.randf()
					L._box(root, pos + Vector3(sin(a) * 0.7, 0.45, cos(a) * 0.7), Vector3(0.42, 0.9, 0.42), _m(Color(0.75, 0.6, 0.35), 0.7))
				t.name = "Terraza"
			1:
				# árbol en alcorque
				var body := StaticBody3D.new()
				body.position = pos
				root.add_child(body)
				var tm := MeshInstance3D.new()
				tm.mesh = town._tree_mesh()
				tm.material_override = town.bark_mat
				body.add_child(tm)
				var cs := CollisionShape3D.new()
				var sh := CylinderShape3D.new()
				sh.radius = 0.25
				sh.height = 3.0
				cs.shape = sh
				cs.position.y = 1.5
				body.add_child(cs)
			2:
				# banco
				var b := L._box(root, pos + Vector3(0, 0.22, 0), Vector3(1.9, 0.44, 0.5), _m(Color(0.86, 0.85, 0.82), 0.8), true, Vector3(0, rng.randf() * TAU, 0))
				for k in 4:
					L._box(b, Vector3(0, 0.25, -0.2 + k * 0.13), Vector3(1.8, 0.04, 0.1), _m(Color(0.45, 0.28, 0.15), 0.7))
		i += 1
	# banderines de colores cruzando la plaza
	var bst := SurfaceTool.new()
	bst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := [Color(0.9, 0.2, 0.2), Color(0.2, 0.5, 0.9), Color(0.95, 0.8, 0.1), Color(0.2, 0.75, 0.3), Color(0.85, 0.3, 0.8)]
	for k in 7:
		var a := poly[rng.randi() % poly.size()]
		var b := poly[rng.randi() % poly.size()]
		if a.distance_to(b) < 12.0:
			continue
		var A := Vector3(a.x, 6.5, a.y)
		var B := Vector3(b.x, 6.5, b.y)
		var n := int(A.distance_to(B) / 0.6)
		for j in n:
			var t0 := float(j) / n
			var p := A.lerp(B, t0) - Vector3(0, 1.4 * 4.0 * t0 * (1.0 - t0), 0)
			var dir := (B - A).normalized()
			var c: Color = cols[j % cols.size()]
			bst.set_color(c)
			bst.add_vertex(p)
			bst.set_color(c)
			bst.add_vertex(p + dir * 0.3)
			bst.set_color(c)
			bst.add_vertex(p + dir * 0.15 - Vector3(0, 0.35, 0))
	var bmat := StandardMaterial3D.new()
	bmat.vertex_color_use_as_albedo = true
	bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bmat.roughness = 0.9
	var bm := MeshInstance3D.new()
	bm.mesh = bst.commit()
	bm.material_override = bmat
	root.add_child(bm)
