extends RefCounted
## Edificios reconocibles de la Avenida Alejandro Rubio, hechos a mano a
## partir de fotos:
##   - "bazar":       Av. Alejandro Rubio 2, esquina con Calle Caño. Bloque de
##                    ladrillo de 3 plantas con tiendas abajo.
##   - "sala_groove": Av. Alejandro Rubio 6. Casa vieja de enlucido amarillo
##                    desconchado, toldo negro, grafitis y arco metálico al lado.
##   - plazuela:      la acera ensanchada delante de la Casa de la Juventud y
##                    el Hogar del Mayor, con bancos, bolardos y árboles.
## Origen local de cada edificio: centro del frente, a ras de suelo; +Z = calle.


static func build(kind: String, root: Node3D, town) -> void:
	match kind:
		"bazar":
			_bazar(root, town)
		"sala_groove":
			_groove(root, town)


# ---------------------------------------------------------------- utilidades

static func _m(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func _box(parent: Node3D, center: Vector3, size: Vector3, mat: Material, collide := false, rot := Vector3.ZERO) -> Node3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	if not collide:
		mi.position = center
		mi.rotation = rot
		parent.add_child(mi)
		return mi
	var body := StaticBody3D.new()
	body.position = center
	body.rotation = rot
	parent.add_child(body)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	return body


static func _cyl(parent: Node3D, center: Vector3, r_top: float, r_bot: float, h: float, mat: Material, rot := Vector3.ZERO, seg := 12) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = seg
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = mat
	mi.position = center
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func _label(parent: Node3D, text: String, pos: Vector3, size: int, color: Color, px := 0.005,
		outline := 0, outline_col := Color.BLACK, rot := Vector3.ZERO) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = px
	l.modulate = color
	l.outline_size = outline
	l.outline_modulate = outline_col
	l.position = pos
	l.rotation = rot
	l.double_sided = false
	parent.add_child(l)
	return l


## Caja de fachada (x de -w/2 a w/2, z de -d a 0) con el shader del pueblo
static func _facade_box(parent: Node3D, town, w: float, d: float, h: float, kind: int, style: int,
		tint: Color, seed: int, x0 := -INF) -> void:
	var xa := -w * 0.5 if x0 == -INF else x0
	var xb := xa + w
	var pts := [Vector2(xa, 0), Vector2(xb, 0), Vector2(xb, -d), Vector2(xa, -d)]
	var col := tint
	col.a = float(kind * 64 + style * 16 + seed % 16) / 255.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % 4]
		var e := b - a
		var L := e.length()
		var n := Vector2(e.y, -e.x).normalized()
		var poly := PackedVector2Array(pts)
		if Geometry2D.is_point_in_polygon((a + b) * 0.5 + n * 0.05, poly):
			n = -n
		town._quad(st, Vector3(a.x, -0.2, a.y), Vector3(b.x, -0.2, b.y), Vector3(b.x, h, b.y), Vector3(a.x, h, a.y),
			Vector2(0, -0.2), Vector2(L, -0.2), Vector2(L, h), Vector2(0, h), Vector3(n.x, 0, n.y), Vector2(L, h), col)
	var mesh := st.commit()
	var body := StaticBody3D.new()
	parent.add_child(body)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = town.facade_mat
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	town._hip_roof(parent, PackedVector2Array(pts), h, false)


# ---------------------------------------------------------------- bazar (nº 2)

static func _bazar(root: Node3D, town) -> void:
	var w := 14.0
	var d := 11.0
	var h := 9.4
	_facade_box(root, town, w, d, h, 2, 2, Color(0.8, 0.5, 0.35), 3)
	var blue := _m(Color(0.08, 0.25, 0.65), 0.5)
	var orange := _m(Color(0.88, 0.38, 0.10), 0.5)
	var white := _m(Color(0.92, 0.92, 0.9), 0.6)
	var iron := _m(Color(0.04, 0.04, 0.05), 0.5, 0.5)
	var slab := _m(Color(0.6, 0.45, 0.35), 0.8)
	# toldo azul corrido sobre los escaparates (frente y lateral de Calle Caño)
	_box(root, Vector3(0, 2.75, 0.18), Vector3(w + 0.1, 0.35, 0.35), blue)
	_box(root, Vector3(w * 0.5 + 0.18, 2.75, -d * 0.5), Vector3(0.35, 0.35, d + 0.1), blue)
	_label(root, "TODO PARA EL HOGAR · ROPA Y COMPLEMENTOS", Vector3(-3.0, 2.75, 0.37), 36, Color(0.95, 0.95, 0.9), 0.0045)
	# carteles
	var s1 := _box(root, Vector3(2.6, 3.35, 0.12), Vector3(3.2, 0.75, 0.08), orange)
	_label(s1, "ALIMENTACIÓN Y BAZAR", Vector3(0, 0, 0.05), 56, Color(1, 0.95, 0.75), 0.0045, 6, Color(0.5, 0.1, 0.0))
	var s2 := _box(root, Vector3(-0.3, 2.35, 0.2), Vector3(1.0, 0.4, 0.06), _m(Color(0.8, 0.12, 0.1), 0.5))
	_label(s2, "BAZAR", Vector3(0, 0, 0.04), 48, Color(1, 0.9, 0.3), 0.0045)
	var s3 := MeshInstance3D.new()
	var s3m := BoxMesh.new()
	s3m.size = Vector3(0.06, 0.7, 2.2)
	s3.mesh = s3m
	s3.material_override = white
	s3.position = Vector3(w * 0.5 + 0.1, 3.35, -3.0)
	root.add_child(s3)
	_label(s3, "ZAPATERÍA", Vector3(0.04, 0.05, 0), 52, Color(0.75, 0.1, 0.1), 0.0045, 0, Color.BLACK, Vector3(0, PI * 0.5, 0))
	# balcones de ladrillo con barandilla en el frente
	for fl in [1, 2]:
		var y: float = fl * 3.0 + 0.05
		_box(root, Vector3(-3.6, y, 0.55), Vector3(4.2, 0.15, 1.1), slab)
		_box(root, Vector3(-3.6, y + 0.55, 1.08), Vector3(4.2, 0.05, 0.05), iron)
		for k in 15:
			_box(root, Vector3(-5.6 + k * 0.29, y + 0.3, 1.08), Vector3(0.025, 0.5, 0.025), iron)
		# cuerpo volado de ladrillo junto a la esquina
		_box(root, Vector3(3.8, y + 1.45, 0.45), Vector3(3.2, 2.9, 0.9), _m(Color(0.66, 0.36, 0.24), 0.9, 0.0))
		_box(root, Vector3(3.8, y + 1.6, 0.92), Vector3(2.4, 1.4, 0.04), _m(Color(0.75, 0.72, 0.64), 0.7))
	# esquina: paso de cebra, señal y árbol en alcorque
	var paint := _m(Color(0.85, 0.85, 0.82), 0.7)
	for k in 6:
		_box(root, Vector3(w * 0.5 + 2.6, 0.03, 2.4 + k * 0.95), Vector3(3.0, 0.02, 0.5), paint)
	_cyl(root, Vector3(w * 0.5 + 0.5, 1.3, 1.2), 0.035, 0.035, 2.6, _m(Color(0.6, 0.6, 0.62), 0.4, 0.6))
	var sign := _box(root, Vector3(w * 0.5 + 0.5, 2.65, 1.2), Vector3(0.55, 0.55, 0.03), blue)
	_label(sign, "▲", Vector3(0, 0, 0.02), 90, Color.WHITE, 0.004)
	# luz del interior de la tienda
	var l := OmniLight3D.new()
	l.light_color = Color(0.9, 0.95, 1.0)
	l.light_energy = 0.5
	l.omni_range = 5.0
	l.position = Vector3(1.0, 1.6, 0.6)
	root.add_child(l)


# ---------------------------------------------------------------- Sala Groove (nº 6)

static func _groove(root: Node3D, town) -> void:
	var w := 9.6
	var d := 9.0
	var h := 6.3
	var x0 := -6.5
	_facade_box(root, town, w, d, h, 0, 0, Color(0.86, 0.74, 0.45), 9, x0)
	var cx := x0 + w * 0.5
	var maroon := _m(Color(0.32, 0.12, 0.10), 0.35)
	var black := _m(Color(0.03, 0.03, 0.035), 0.5)
	var iron := _m(Color(0.05, 0.05, 0.05), 0.5, 0.4)
	# zócalo de baldosa granate
	_box(root, Vector3(cx, 0.45, 0.04), Vector3(w + 0.02, 0.9, 0.1), maroon)
	_box(root, Vector3(x0 - 0.04, 0.45, -d * 0.5), Vector3(0.1, 0.9, d), maroon)
	# puerta negra con pintadas
	var door := _box(root, Vector3(cx + 0.6, 1.15, 0.06), Vector3(1.5, 2.3, 0.08), black)
	_label(door, "ROW", Vector3(0.1, -0.8, 0.05), 64, Color(0.9, 0.9, 0.9), 0.005, 4, Color(0.2, 0.2, 0.2))
	_label(door, "sk8", Vector3(-0.3, 0.3, 0.05), 40, Color(0.3, 0.6, 0.9), 0.005)
	# toldo negro triangular con el nombre
	var awn := Node3D.new()
	awn.position = Vector3(cx + 0.6, 2.55, 0.0)
	root.add_child(awn)
	_box(awn, Vector3(-0.85, 0.3, 0.45), Vector3(1.9, 0.06, 1.0), black, false, Vector3(0, 0, 0.55))
	_box(awn, Vector3(0.85, 0.3, 0.45), Vector3(1.9, 0.06, 1.0), black, false, Vector3(0, 0, -0.55))
	_label(awn, "Mc GROOVE", Vector3(0, 0.15, 0.97), 64, Color(0.95, 0.95, 0.95), 0.0045, 6, Color(0.2, 0.2, 0.2))
	# balcón de forja en la primera planta
	_box(root, Vector3(cx - 1.4, 3.05, 0.45), Vector3(1.8, 0.12, 0.9), _m(Color(0.5, 0.45, 0.38)))
	_box(root, Vector3(cx - 1.4, 4.0, 0.88), Vector3(1.8, 0.05, 0.05), iron)
	for k in 12:
		_box(root, Vector3(cx - 2.25 + k * 0.155, 3.55, 0.88), Vector3(0.02, 0.9, 0.02), iron)
	# antena parabólica y farol en la fachada
	var dish := _cyl(root, Vector3(x0 + w - 0.8, 5.3, 0.35), 0.4, 0.4, 0.06, _m(Color(0.8, 0.8, 0.78), 0.5), Vector3(1.2, 0.3, 0))
	dish.name = "Parabolica"
	_cyl(root, Vector3(x0 + w - 0.8, 5.3, 0.15), 0.025, 0.025, 0.4, iron, Vector3(PI * 0.5, 0, 0))
	# pintadas en la fachada
	var tags := [["GROOVE", Vector2(x0 + 1.3, 2.0), Color(0.2, 0.5, 0.9)], ["SKONE", Vector2(cx + 2.4, 1.4), Color(0.2, 0.75, 0.3)],
		["PRC", Vector2(x0 + 3.4, 1.2), Color(0.85, 0.85, 0.85)]]
	for t in tags:
		_label(root, t[0], Vector3(t[1].x, t[1].y, 0.03), 72, t[2], 0.006, 10, Color(0.05, 0.05, 0.05))
	# arco metálico con muro de grafiti al lado (x de 3.1 a 6.5)
	var ax0 := x0 + w + 0.05
	var aw := 6.5 - ax0
	var acx := ax0 + aw * 0.5
	var arch_mat := _m(Color(0.78, 0.76, 0.70), 0.6, 0.3)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 12
	var R := aw * 0.5
	for i in segs:
		var a0 := PI * i / segs
		var a1 := PI * (i + 1) / segs
		var p0 := Vector3(acx + cos(a0) * R, 2.3 + sin(a0) * R * 0.8, 0.6)
		var p1 := Vector3(acx + cos(a1) * R, 2.3 + sin(a1) * R * 0.8, 0.6)
		var q0 := p0 - Vector3(0, 0, 4.5)
		var q1 := p1 - Vector3(0, 0, 4.5)
		var nrm := Vector3(cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5), 0)
		town._quad(st, p0, p1, q1, q0, Vector2(0, 0), Vector2(0.5, 0), Vector2(0.5, 4.5), Vector2(0, 4.5), nrm)
	var arch := MeshInstance3D.new()
	arch.mesh = st.commit()
	arch.material_override = arch_mat
	root.add_child(arch)
	for z in [0.55, -1.6, -3.85]:
		for x in [ax0 + 0.08, ax0 + aw - 0.08]:
			_cyl(root, Vector3(x, 1.15, z), 0.04, 0.04, 2.3, arch_mat)
	var wall := _box(root, Vector3(acx, 1.1, 0.3), Vector3(aw, 2.2, 0.25), _m(Color(0.75, 0.73, 0.68), 0.9), true)
	_label(wall, "SBOR", Vector3(0, 0.1, 0.13), 150, Color(0.25, 0.75, 0.35), 0.006, 18, Color(0.05, 0.08, 0.05))
	_label(wall, "esoof", Vector3(0.3, -0.55, 0.13), 90, Color(0.55, 0.8, 0.95), 0.006, 10, Color(0.1, 0.1, 0.1))
	_box(root, Vector3(acx, 1.1, -4.0), Vector3(aw, 2.2, 0.25), _m(Color(0.7, 0.68, 0.64), 0.9), true)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.7, 0.4)
	l.light_energy = 0.8
	l.omni_range = 5.0
	l.position = Vector3(cx + 0.6, 2.4, 1.3)
	root.add_child(l)


# ---------------------------------------------------------------- plazuela

static func plazuela(pz: Dictionary, town) -> void:
	var pts: PackedVector2Array = pz["points"]
	var dir: Vector2 = pz["dir"]
	var nrm: Vector2 = pz["normal"]      # de la calle hacia el edificio
	var p0 := pts[0]
	var length := pts[0].distance_to(pts[1])
	var depth := pts[0].distance_to(pts[3])
	var root := Node3D.new()
	root.name = "Plazuela_" + str(pz["name"]).replace(" ", "_")
	town.nav_region.add_child(root)
	var granite := _m(Color(0.58, 0.55, 0.50), 0.9)
	granite.albedo_texture = town.soft_noise
	granite.uv1_triplanar = true
	var concrete := _m(Color(0.86, 0.85, 0.82), 0.8)
	var wood := _m(Color(0.32, 0.22, 0.14), 0.7)
	var grey_slab := _m(Color(0.52, 0.52, 0.52), 0.85)
	grey_slab.albedo_texture = town.soft_noise
	grey_slab.uv1_triplanar = true
	var P := func(t: float, s: float) -> Vector3:
		var q := p0 + dir * t + nrm * s
		return Vector3(q.x, 0, q.y)
	var yaw := atan2(-nrm.x, -nrm.y)       # +Z local mirando a la calle
	# losas grises junto a la fachada
	var slab := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(length, minf(2.4, depth * 0.5))
	slab.mesh = pm
	slab.material_override = grey_slab
	slab.position = P.call(length * 0.5, depth - pm.size.y * 0.5) + Vector3(0, 0.012, 0)
	slab.rotation.y = yaw
	root.add_child(slab)
	# bancos: base de hormigón blanco con asiento de listones
	var n_b := maxi(1, int(length / 7.0))
	for i in n_b:
		var t := (i + 0.5) * length / n_b
		var c: Vector3 = P.call(t, depth * 0.45)
		var bench := _box(root, c + Vector3(0, 0.22, 0), Vector3(2.0, 0.44, 0.5), concrete, true, Vector3(0, yaw, 0))
		for k in 4:
			_box(bench, Vector3(0, 0.25, -0.2 + k * 0.13), Vector3(1.9, 0.04, 0.1), wood)
		_box(bench, Vector3(0, 0.55, -0.24), Vector3(1.9, 0.5, 0.05), wood, false, Vector3(-0.2, 0, 0))
	# bolardos de granito con bola, por parejas
	var n_p := maxi(1, int(length / 9.0))
	for i in n_p:
		var t := (i + 0.5) * length / n_p
		for off in [-1.2, 1.2]:
			var c: Vector3 = P.call(t + off, 0.7)
			var post := _box(root, c + Vector3(0, 0.5, 0), Vector3(0.34, 1.0, 0.34), granite, true, Vector3(0, yaw, 0))
			var ball := SphereMesh.new()
			ball.radius = 0.15
			ball.height = 0.3
			var b := MeshInstance3D.new()
			b.mesh = ball
			b.material_override = granite
			b.position = Vector3(0, 0.62, 0)
			post.add_child(b)
	# plátanos podados
	var n_t := maxi(1, int(length / 8.0))
	for i in n_t:
		var t := (i + 0.25) * length / n_t
		var c: Vector3 = P.call(t, depth * 0.22)
		var body := StaticBody3D.new()
		body.position = c
		root.add_child(body)
		var mi := MeshInstance3D.new()
		mi.mesh = town._tree_mesh()
		mi.material_override = town.bark_mat
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 0.25
		sh.height = 3.0
		cs.shape = sh
		cs.position.y = 1.5
		body.add_child(cs)
	# farola fernandina y armario eléctrico
	var lp: Vector3 = P.call(length * 0.5 + 2.0, depth * 0.3)
	_cyl(root, lp + Vector3(0, 0.25, 0), 0.12, 0.16, 0.5, town.iron_mat)
	_cyl(root, lp + Vector3(0, 1.9, 0), 0.045, 0.075, 3.0, town.iron_mat)
	var lan := MeshInstance3D.new()
	lan.mesh = town._lantern_mesh()
	lan.position = lp + Vector3(0, 3.7, 0)
	lan.set_surface_override_material(0, town.glass_mat)
	lan.set_surface_override_material(1, town.iron_mat)
	root.add_child(lan)
	var light := OmniLight3D.new()
	light.position = lp + Vector3(0, 3.6, 0)
	light.light_color = Color(1.0, 0.68, 0.38)
	light.light_energy = 2.0
	light.omni_range = 12.0
	root.add_child(light)
	_box(root, P.call(length * 0.5 - 3.0, depth * 0.3) + Vector3(0, 0.55, 0), Vector3(0.7, 1.1, 0.32), _m(Color(0.6, 0.6, 0.58), 0.6), true, Vector3(0, yaw, 0))
