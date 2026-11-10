extends RefCounted
## Coches aparcados en un lado de la calle y contenedores de reciclaje
## (verde, amarillo y azul), como en cualquier calle de Guadalix.
## Pocas llamadas de dibujo: un MultiMesh por modelo; colisión con cajas.

const SLOT := 5.6            # hueco por coche
const ROUTE_CLEAR := 6.0     # nada aparcado en las calles por donde pasa el bus
const JUNCTION_CLEAR := 7.0  # ni cerca de los cruces

static var _rng := RandomNumberGenerator.new()


static func build(town) -> void:
	_rng.seed = 4242
	var holder := Node3D.new()
	holder.name = "CochesYContenedores"
	town.nav_region.add_child(holder)
	var car_meshes := [_car_mesh(4.1, 1.7, 1.45, 0.0), _car_mesh(4.4, 1.75, 1.5, 0.35), _car_mesh(3.7, 1.65, 1.5, -0.2)]
	var car_xf := [[], [], []]
	var car_col := [[], [], []]
	var bin_xf := {"verde": [], "amarillo": [], "azul": []}
	var paints := [Color(0.85, 0.85, 0.83), Color(0.12, 0.12, 0.13), Color(0.55, 0.56, 0.58), Color(0.55, 0.08, 0.07),
		Color(0.12, 0.22, 0.45), Color(0.82, 0.8, 0.72), Color(0.25, 0.3, 0.22), Color(0.6, 0.5, 0.35)]
	var placed: Array[Vector2] = []
	var bin_left := 40.0
	for s in town.streets:
		var typ: String = s["type"]
		if not typ in ["residential", "secondary", "tertiary", "primary", "unclassified", "living_street"]:
			continue
		var w: float = s["width"]
		if w < 5.5:
			continue
		var pts: PackedVector2Array = s["points"]
		var side := 1.0 if (hash(s["name"]) + pts.size()) % 2 == 0 else -1.0
		var acc := 3.0
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var seg := a.distance_to(b)
			if seg < SLOT:
				acc = 3.0
				continue
			var dir := (b - a) / seg
			var nrm := Vector2(-dir.y, dir.x) * side
			var t := acc
			while t < seg - 2.5:
				var c := a + dir * t + nrm * (w * 0.5 - 0.95)
				t += SLOT
				if not _ok(town, c, s, placed):
					continue
				bin_left -= SLOT
				if bin_left <= 0.0 and _rng.randf() < 0.5:
					# isla de contenedores: verde, amarillo y azul
					bin_left = _rng.randf_range(45.0, 80.0)
					var kinds := ["verde", "amarillo", "azul"]
					for k in 3:
						var bp := c + dir * (k - 1) * 1.45
						var y: float = town.gy(bp)
						bin_xf[kinds[k]].append(Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.y)), Vector3(bp.x, y, bp.y)))
						_collider(holder, Vector3(bp.x, y + 0.65, bp.y), dir, Vector3(1.3, 1.3, 1.1))
					placed.append(c)
					continue
				if _rng.randf() < 0.42:
					continue
				var m := _rng.randi() % 3
				var ang := atan2(dir.x, dir.y) + _rng.randf_range(-0.03, 0.03)
				var hf: float = town.gy(c + dir * 1.8)
				var hb: float = town.gy(c - dir * 1.8)
				var pitch := atan2(hf - hb, 3.6)
				var basis := Basis(Vector3.UP, ang) * Basis(Vector3.RIGHT, -pitch)
				if _rng.randf() < 0.5:   # aparcado en el otro sentido
					basis = Basis(Vector3.UP, ang + PI) * Basis(Vector3.RIGHT, pitch)
				car_xf[m].append(Transform3D(basis, Vector3(c.x, (hf + hb) * 0.5, c.y)))
				car_col[m].append(paints[_rng.randi() % paints.size()])
				_collider(holder, Vector3(c.x, (hf + hb) * 0.5 + 0.75, c.y), dir, Vector3(1.75, 1.5, 4.2))
				placed.append(c)
			acc = maxf(t - seg, 3.0)
	for m in 3:
		_multimesh(holder, car_meshes[m], car_xf[m], car_col[m])
	var bin_cols := {"verde": Color(0.12, 0.42, 0.16), "amarillo": Color(0.92, 0.75, 0.08), "azul": Color(0.1, 0.3, 0.7)}
	var bin_mesh := _bin_mesh()
	for k in bin_xf:
		var cols := []
		for i in bin_xf[k].size():
			cols.append(bin_cols[k])
		_multimesh(holder, bin_mesh, bin_xf[k], cols)


static func _ok(town, c: Vector2, s: Dictionary, placed: Array[Vector2]) -> bool:
	if not town.in_detail(c, -3.0):
		return false
	if _near_route(town, c, ROUTE_CLEAR):
		return false
	for q in placed:
		if q.distance_to(c) < 4.5:
			return false
	# lejos de cruces (otra calle cerca)
	for o in town.streets:
		if o == s or o["type"] in ["footway", "path", "steps", "track"]:
			continue
		var op: PackedVector2Array = o["points"]
		for i in op.size() - 1:
			if Geometry2D.get_closest_point_to_segment(c, op[i], op[i + 1]).distance_to(c) < o["width"] * 0.5 + JUNCTION_CLEAR:
				return false
	# ni en puertas de zona, ni en plazas o plazuelas, ni dentro de edificios
	for zd in town.zone_doors_data:
		if zd["pos"].distance_to(c) < 10.0:
			return false
	for sp in town.spawn_points:
		if Vector2(sp.x, sp.z).distance_to(c) < 4.0:
			return false
	if town._in_plazuela(c) or town._in_any_building(c, 0.8):
		return false
	for pf in town.prefabs:
		if Geometry2D.is_point_in_polygon(c, Geometry2D.offset_polygon(pf["footprint"], 2.5)[0]):
			return false
	for ar in town.areas:
		if Geometry2D.is_point_in_polygon(c, ar["points"]):
			return false
	return true


static func _near_route(town, p: Vector2, dist: float) -> bool:
	var r: PackedVector2Array = town.bus_route
	for i in r.size() - 1:
		if Geometry2D.get_closest_point_to_segment(p, r[i], r[i + 1]).distance_to(p) < dist:
			return true
	return false


static func _collider(holder: Node3D, pos: Vector3, dir: Vector2, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = atan2(dir.x, dir.y)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	holder.add_child(body)


static func _multimesh(holder: Node3D, mesh: Mesh, xfs: Array, cols: Array) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	holder.add_child(mmi)


static func _mat(c: Color, rough: float, metal := 0.0, paint := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	m.vertex_color_use_as_albedo = paint
	return m


## Turismo sencillo: carrocería (color por instancia), lunas, ruedas y faros.
## Mira a +Z. nose > 0 = morro más largo (berlina), < 0 = utilitario.
static func _car_mesh(L: float, W: float, H: float, nose: float) -> ArrayMesh:
	var body := SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glass := SurfaceTool.new()
	glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dark := SurfaceTool.new()
	dark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lights := SurfaceTool.new()
	lights.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := W * 0.5
	var hl := L * 0.5
	var belt := 0.92
	# bajos y carrocería hasta la cintura
	_box(body, Vector3(W, belt - 0.3, L), Vector3(0, 0.3 + (belt - 0.3) * 0.5, 0))
	# capó inclinado delante y maletero detrás
	var cab_f := hl - 1.25 - nose * 0.5
	var cab_b := -hl + 0.75 + maxf(nose, 0.0) * 0.4
	# habitáculo: trapecio (lunas)
	var r0 := belt
	var r1 := H
	var ins := 0.12
	var fz0 := cab_f
	var fz1 := cab_f - 0.55
	var bz0 := cab_b
	var bz1 := cab_b + 0.35
	var q := [
		[Vector3(-hw + 0.04, r0, fz0), Vector3(hw - 0.04, r0, fz0), Vector3(hw - ins, r1, fz1), Vector3(-hw + ins, r1, fz1)],   # parabrisas
		[Vector3(hw - 0.04, r0, bz0), Vector3(-hw + 0.04, r0, bz0), Vector3(-hw + ins, r1, bz1), Vector3(hw - ins, r1, bz1)],   # luneta
		[Vector3(hw - 0.04, r0, fz0), Vector3(hw - 0.04, r0, bz0), Vector3(hw - ins, r1, bz1), Vector3(hw - ins, r1, fz1)],     # lateral der.
		[Vector3(-hw + 0.04, r0, bz0), Vector3(-hw + 0.04, r0, fz0), Vector3(-hw + ins, r1, fz1), Vector3(-hw + ins, r1, bz1)], # lateral izq.
	]
	for f in q:
		_quad(glass, f[0], f[1], f[2], f[3])
	# techo
	_quad(body, Vector3(-hw + ins, r1, fz1), Vector3(hw - ins, r1, fz1), Vector3(hw - ins, r1, bz1), Vector3(-hw + ins, r1, bz1))
	# pilares (marcos de puerta)
	for side in [-1.0, 1.0]:
		var x: float = side * (hw - 0.02)
		_box(body, Vector3(0.06, 0.06, 0.06), Vector3(x, belt + 0.02, (fz0 + bz0) * 0.5))
	# ruedas
	for zx in [[hl - 0.8, hw - 0.12], [hl - 0.8, -hw + 0.12], [-hl + 0.75, hw - 0.12], [-hl + 0.75, -hw + 0.12]]:
		_wheel(dark, Vector3(zx[1], 0.31, zx[0]), 0.31, 0.2)
	# faros y pilotos
	for side in [-1.0, 1.0]:
		_box(lights, Vector3(0.36, 0.12, 0.04), Vector3(side * (hw - 0.3), belt - 0.18, hl + 0.01))
		_box(dark, Vector3(0.34, 0.12, 0.04), Vector3(side * (hw - 0.3), belt - 0.2, -hl - 0.01))
	_box(dark, Vector3(W * 0.5, 0.14, 0.03), Vector3(0, 0.55, hl + 0.01))   # parrilla
	_box(dark, Vector3(W + 0.02, 0.1, L + 0.02), Vector3(0, 0.33, 0))       # faldones
	var mesh := ArrayMesh.new()
	body.commit(mesh)
	glass.commit(mesh)
	dark.commit(mesh)
	lights.commit(mesh)
	mesh.surface_set_material(0, _mat(Color.WHITE, 0.35, 0.3, true))
	mesh.surface_set_material(1, _mat(Color(0.06, 0.08, 0.1), 0.1, 0.4))
	mesh.surface_set_material(2, _mat(Color(0.05, 0.05, 0.05), 0.8))
	var lm := _mat(Color(0.85, 0.85, 0.8), 0.2)
	mesh.surface_set_material(3, lm)
	return mesh


## Contenedor de 1100 l con tapa curva
static func _bin_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(st, Vector3(1.25, 1.1, 1.0), Vector3(0, 0.65, 0))
	_box(st, Vector3(1.3, 0.12, 1.05), Vector3(0, 1.26, 0))
	_box(st, Vector3(1.32, 0.06, 0.12), Vector3(0, 1.0, 0.52))
	var dark := SurfaceTool.new()
	dark.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in [-0.5, 0.5]:
		for z in [-0.38, 0.38]:
			_wheel(dark, Vector3(x, 0.09, z), 0.09, 0.06)
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	dark.commit(mesh)
	mesh.surface_set_material(0, _mat(Color.WHITE, 0.6, 0.0, true))
	mesh.surface_set_material(1, _mat(Color(0.05, 0.05, 0.05), 0.8))
	return mesh


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	for v in [a, c, b, a, d, c]:
		st.set_normal(-n)
		st.set_uv(Vector2.ZERO)
		st.add_vertex(v)
	for v in [a, b, c, a, c, d]:   # doble cara (lunas finas)
		st.set_normal(n)
		st.set_uv(Vector2.ZERO)
		st.add_vertex(v)


static func _box(st: SurfaceTool, s: Vector3, c: Vector3) -> void:
	var bm := BoxMesh.new()
	bm.size = s
	st.append_from(bm, 0, Transform3D(Basis(), c))


static func _wheel(st: SurfaceTool, c: Vector3, r: float, w: float) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = w
	cm.radial_segments = 12
	cm.rings = 1
	st.append_from(cm, 0, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), c))
