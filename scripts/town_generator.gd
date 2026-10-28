extends Node3D
## Genera el pueblo: suelo, calles con bordillo, edificios con tejado,
## postes y cables, árboles, farolas, el Bar Chiqui y la malla de navegación.
## Si existe res://data/town.json (creado con tools/osm_to_json.py desde
## OpenStreetMap) usa el pueblo real; si no, genera un pueblo de prueba.

signal navigation_ready

const FACADE_SHADER = preload("res://shaders/facade.gdshader")
const COBBLE_SHADER = preload("res://shaders/cobble.gdshader")
const ASPHALT_SHADER = preload("res://shaders/asphalt.gdshader")
const PAVER_SHADER = preload("res://shaders/pavers.gdshader")
const ROOF_SHADER = preload("res://shaders/roof_tiles.gdshader")
const BarChiqui = preload("res://scripts/bar_chiqui.gd")

const STUCCO_COLORS := [
	Color(0.88, 0.84, 0.74), Color(0.92, 0.90, 0.85), Color(0.86, 0.76, 0.56),
	Color(0.90, 0.80, 0.60), Color(0.82, 0.78, 0.70), Color(0.94, 0.92, 0.88),
]
const NO_FURNITURE := ["track", "path", "footway", "steps"]
const MAX_LAMPS := 46
const GROUND_TILE := 16.0

enum Kind { STUCCO, GRANITE, BRICK, PLAIN_STONE }

var buildings: Array = []   # {points, height, name, type, rect}
var streets: Array = []     # {points, width, name, type}
var plazas: Array = []      # {points, name}
var prefabs: Array = []
var pois: Array = []
var bounds := Rect2()
var is_test_town := false
var player_start := Vector3.ZERO
var player_start_yaw := 0.0
var spawn_points: Array = []
var lamps: Array = []
var nav_region: NavigationRegion3D
var bar = null               # Bar Chiqui (si está en el mapa)
var exterior_open := true    # sin bar, toda la calle está abierta

var noise_tex: NoiseTexture2D
var soft_noise: NoiseTexture2D   # ruido de poco contraste para materiales estándar
var facade_mat: ShaderMaterial
var roof_mat: ShaderMaterial
var flat_roof_mat: StandardMaterial3D
var cobble_mat: ShaderMaterial
var asphalt_mat: ShaderMaterial
var paver_mat: ShaderMaterial
var curb_mat: StandardMaterial3D
var wood_mat: StandardMaterial3D
var bark_mat: StandardMaterial3D
var iron_mat: StandardMaterial3D
var wire_mat: StandardMaterial3D
var glass_mat: StandardMaterial3D
var rng := RandomNumberGenerator.new()
var _baking := false
var _rebake_pending := false
var _stone_spot := Vector2(INF, INF)


func build(json_path: String) -> void:
	rng.seed = 1234
	_make_materials()
	if FileAccess.file_exists(json_path):
		_load_json(json_path)
	if buildings.is_empty():
		is_test_town = true
		_generate_test_town()
	if bounds.size == Vector2.ZERO:
		_compute_bounds()

	nav_region = NavigationRegion3D.new()
	nav_region.name = "Navegacion"
	add_child(nav_region)
	nav_region.bake_finished.connect(_on_bake_finished)

	_find_stone_spot()
	_build_ground()
	_build_plazas()
	_build_streets()
	_build_curbs()
	_build_buildings()
	_build_prefabs()
	_build_props()
	_build_poles_and_wires()
	_build_trees()
	_build_boundary()
	_compute_spawns()
	_choose_player_start()
	_build_lamps()
	_bake_navigation()


# ---------------------------------------------------------------- materiales

func _make_materials() -> void:
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.02
	fn.fractal_octaves = 5
	noise_tex = NoiseTexture2D.new()
	noise_tex.width = 512
	noise_tex.height = 512
	noise_tex.seamless = true
	noise_tex.generate_mipmaps = true
	noise_tex.noise = fn

	soft_noise = NoiseTexture2D.new()
	soft_noise.width = 512
	soft_noise.height = 512
	soft_noise.seamless = true
	soft_noise.generate_mipmaps = true
	soft_noise.noise = fn
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.78, 0.78, 0.78))
	ramp.set_color(1, Color(1.0, 1.0, 1.0))
	soft_noise.color_ramp = ramp

	facade_mat = _shader_mat(FACADE_SHADER)
	roof_mat = _shader_mat(ROOF_SHADER)
	cobble_mat = _shader_mat(COBBLE_SHADER)
	asphalt_mat = _shader_mat(ASPHALT_SHADER)
	paver_mat = _shader_mat(PAVER_SHADER)

	flat_roof_mat = _std(Color(0.32, 0.31, 0.30), 0.95, soft_noise, 0.2)
	curb_mat = _std(Color(0.42, 0.41, 0.39), 0.9, soft_noise, 0.8)
	wood_mat = _std(Color(0.28, 0.20, 0.14), 0.9, soft_noise, 0.6)
	bark_mat = _std(Color(0.52, 0.49, 0.42), 0.95, soft_noise, 1.2)
	iron_mat = _std(Color(0.035, 0.035, 0.04), 0.45)
	iron_mat.metallic = 0.6
	wire_mat = StandardMaterial3D.new()
	wire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wire_mat.albedo_color = Color(0.02, 0.02, 0.02)
	glass_mat = StandardMaterial3D.new()
	glass_mat.albedo_color = Color(1.0, 0.85, 0.6)
	glass_mat.emission_enabled = true
	glass_mat.emission = Color(1.0, 0.66, 0.32)
	glass_mat.emission_energy_multiplier = 4.0


func _shader_mat(sh: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("noise_tex", noise_tex)
	return m


func _std(c: Color, rough: float, tex: Texture2D = null, tri_scale: float = 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if tex:
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * tri_scale
	return m


# ---------------------------------------------------------------- datos

func _load_json(path: String) -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("town.json no válido, uso el pueblo de prueba")
		return
	for b in data.get("buildings", []):
		_add_building(_pts(b["points"]), float(b.get("height", 7.0)), str(b.get("name", "")), str(b.get("type", "yes")))
	for s in data.get("streets", []):
		_add_street(_pts(s["points"]), float(s.get("width", 6.0)), str(s.get("name", "")), str(s.get("type", "residential")))
	for p in data.get("plazas", []):
		plazas.append({"points": _pts(p["points"]), "name": str(p.get("name", ""))})
	for p in data.get("prefabs", []):
		prefabs.append({"prefab": str(p["prefab"]), "pos": Vector2(p["pos"][0], p["pos"][1]),
			"yaw": float(p["yaw"]), "footprint": _pts(p["footprint"])})
	for p in data.get("pois", []):
		pois.append({"name": str(p.get("name", "")), "type": str(p.get("type", "")),
			"pos": Vector2(p["pos"][0], p["pos"][1])})
	if data.has("bounds"):
		var bb: Array = data["bounds"]
		bounds = Rect2(Vector2(bb[0], bb[1]), Vector2(bb[2] - bb[0], bb[3] - bb[1]))


func _pts(arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in arr:
		out.append(Vector2(p[0], p[1]))
	return out


func _add_building(pts: PackedVector2Array, height: float, bname: String, btype: String = "yes") -> void:
	var clean := PackedVector2Array()
	for p in pts:
		if clean.is_empty() or clean[clean.size() - 1].distance_to(p) > 0.05:
			clean.append(p)
	if clean.size() > 2 and clean[0].distance_to(clean[clean.size() - 1]) < 0.05:
		clean.remove_at(clean.size() - 1)
	if clean.size() < 3:
		return
	if absf(_area(clean)) < 6.0:
		return
	var r := Rect2(clean[0], Vector2.ZERO)
	for p in clean:
		r = r.expand(p)
	buildings.append({"points": clean, "height": height, "name": bname, "type": btype, "rect": r})


func _area(pts: PackedVector2Array) -> float:
	var area := 0.0
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		area += a.x * b.y - b.x * a.y
	return area * 0.5


func _add_street(pts: PackedVector2Array, width: float, sname: String, stype: String = "residential") -> void:
	var clean := PackedVector2Array()
	for p in pts:
		if clean.is_empty() or clean[clean.size() - 1].distance_to(p) > 0.1:
			clean.append(p)
	if clean.size() < 2:
		return
	# Densificar para trocear la malla (límite de luces por objeto)
	var dense := PackedVector2Array([clean[0]])
	for i in range(1, clean.size()):
		var a := clean[i - 1]
		var b := clean[i]
		var n := int(ceil(a.distance_to(b) / 18.0))
		for k in range(1, n + 1):
			dense.append(a.lerp(b, float(k) / n))
	streets.append({"points": dense, "width": width, "name": sname, "type": stype})


func _compute_bounds() -> void:
	var first := true
	for b in buildings:
		bounds = b["rect"] if first else bounds.merge(b["rect"])
		first = false
	bounds = bounds.grow(6.0)


func _find_stone_spot() -> void:
	# Cruce Calle Caño / Avenida Alejandro Rubio: casas de granito y ladrillo
	var best := INF
	for s1 in streets:
		if not s1["name"].contains("Caño"):
			continue
		for s2 in streets:
			if not s2["name"].contains("Alejandro Rubio"):
				continue
			for p in s1["points"]:
				for q in s2["points"]:
					var d: float = p.distance_to(q)
					if d < best:
						best = d
						_stone_spot = p


# ---------------------------------------------------------------- pueblo de prueba

func _generate_test_town() -> void:
	var lines := [-60.0, -20.0, 20.0, 60.0]
	for c in lines:
		_add_street(PackedVector2Array([Vector2(c, -82), Vector2(c, 82)]), 8.0, "", "residential")
		_add_street(PackedVector2Array([Vector2(-82, c), Vector2(82, c)]), 8.0, "", "residential")
	var ranges := [[-82.0, -64.0], [-56.0, -24.0], [-16.0, 16.0], [24.0, 56.0], [64.0, 82.0]]
	for ix in ranges.size():
		for iz in ranges.size():
			if ix == 2 and iz == 2:
				continue
			if ix == 2 and iz == 1:
				_add_building(_rect_pts(-9, -50, 18, 22), 13.0, "Iglesia", "church")
				_add_building(_rect_pts(-3.5, -31, 7, 7), 25.0, "Torre", "tower")
				continue
			_fill_block(ranges[ix][0], ranges[iz][0], ranges[ix][1], ranges[iz][1])
	pois.append({"name": "Fuente", "type": "fountain", "pos": Vector2(0, 0)})
	pois.append({"name": "Iglesia", "type": "place_of_worship", "pos": Vector2(0, -28)})
	bounds = Rect2(Vector2(-86, -86), Vector2(172, 172))


func _rect_pts(x: float, z: float, w: float, d: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x, z), Vector2(x + w, z), Vector2(x + w, z + d), Vector2(x, z + d)])


func _fill_block(x0: float, z0: float, x1: float, z1: float) -> void:
	var depth := minf(10.0, (minf(x1 - x0, z1 - z0)) * 0.5)
	for side in [0, 1]:
		var x := x0
		while x < x1 - 2.0:
			var w := minf(rng.randf_range(6.0, 10.5), x1 - x)
			var d := depth - rng.randf_range(0.0, 1.5)
			var h := _random_height()
			if side == 0:
				_add_building(_rect_pts(x, z0, w, d), h, "", "fill")
			else:
				_add_building(_rect_pts(x, z1 - d, w, d), h, "", "fill")
			x += w
	if z1 - z0 > depth * 2.0 + 4.0:
		for side in [0, 1]:
			var z := z0 + depth
			while z < z1 - depth - 2.0:
				var w := minf(rng.randf_range(6.0, 10.0), z1 - depth - z)
				var d := depth - rng.randf_range(0.0, 1.5)
				var h := _random_height()
				if side == 0:
					_add_building(_rect_pts(x0, z, d, w), h, "", "fill")
				else:
					_add_building(_rect_pts(x1 - d, z, d, w), h, "", "fill")
				z += w


func _random_height() -> float:
	var floors := 2 if rng.randf() < 0.55 else (3 if rng.randf() < 0.8 else 1)
	return floors * 3.0 + rng.randf_range(0.2, 0.6)


# ---------------------------------------------------------------- geometría

func _tri(st: SurfaceTool, v: Array, uvs: Array, n: Vector3, uv2: Vector2, col: Color) -> void:
	# Godot usa orden horario para las caras frontales
	var order := [0, 1, 2]
	if (v[1] - v[0]).cross(v[2] - v[0]).dot(n) > 0.0:
		order = [0, 2, 1]
	for i in order:
		st.set_normal(n)
		st.set_uv(uvs[i])
		st.set_uv2(uv2)
		st.set_color(col)
		st.add_vertex(v[i])


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uva: Vector2, uvb: Vector2,
		uvc: Vector2, uvd: Vector2, n: Vector3, uv2 := Vector2.ZERO, col := Color.WHITE) -> void:
	_tri(st, [a, b, c], [uva, uvb, uvc], n, uv2, col)
	_tri(st, [a, c, d], [uva, uvc, uvd], n, uv2, col)


func _box_into(st: SurfaceTool, xf: Transform3D, size: Vector3) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	st.append_from(bm, 0, xf)


func _cyl_into(st: SurfaceTool, xf: Transform3D, r_top: float, r_bot: float, h: float, seg: int = 8) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = seg
	cm.rings = 1
	st.append_from(cm, 0, xf)


func _mesh_node(parent: Node, mesh: Mesh, mat: Material, pos := Vector3.ZERO, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Suelo"
	nav_region.add_child(body)
	var area := bounds.grow(30.0)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(area.size.x, 1.0, area.size.y)
	cs.shape = box
	cs.position = Vector3(area.get_center().x, -0.5, area.get_center().y)
	body.add_child(cs)
	# Suelo troceado: el renderizador de Compatibilidad limita las luces por objeto
	var pm := PlaneMesh.new()
	pm.size = Vector2(GROUND_TILE, GROUND_TILE)
	var holder := Node3D.new()
	holder.name = "Acera"
	add_child(holder)
	var x := area.position.x
	while x < area.end.x:
		var z := area.position.y
		while z < area.end.y:
			var mi := _mesh_node(holder, pm, paver_mat, Vector3(x + GROUND_TILE * 0.5, 0.0, z + GROUND_TILE * 0.5), false)
			mi.name = "t"
			z += GROUND_TILE
		x += GROUND_TILE


func _build_plazas() -> void:
	for pl in plazas:
		var pts: PackedVector2Array = pl["points"]
		if pts.size() < 3:
			continue
		var tris := Geometry2D.triangulate_polygon(pts)
		if tris.is_empty():
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for t in range(0, tris.size(), 3):
			var vs := []
			for k in 3:
				var p := pts[tris[t + k]]
				vs.append(Vector3(p.x, 0.01, p.y))
			_tri(st, vs, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], Vector3.UP, Vector2.ZERO, Color.WHITE)
		_mesh_node(self, st.commit(), cobble_mat, Vector3.ZERO, false)


func _street_edges(s: Dictionary) -> Array:
	var pts: PackedVector2Array = s["points"]
	var w: float = s["width"]
	var lefts: Array = []
	var rights: Array = []
	for i in pts.size():
		var dir: Vector2
		if i == 0:
			dir = (pts[1] - pts[0]).normalized()
		elif i == pts.size() - 1:
			dir = (pts[i] - pts[i - 1]).normalized()
		else:
			dir = ((pts[i] - pts[i - 1]).normalized() + (pts[i + 1] - pts[i]).normalized()).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		var miter := 1.0
		if i > 0 and i < pts.size() - 1:
			var sd := (pts[i] - pts[i - 1]).normalized()
			miter = clampf(1.0 / maxf(nrm.dot(Vector2(-sd.y, sd.x)), 0.3), 1.0, 2.5)
		lefts.append(pts[i] + nrm * w * 0.5 * miter)
		rights.append(pts[i] - nrm * w * 0.5 * miter)
	return [lefts, rights]


func _build_streets() -> void:
	var holder := Node3D.new()
	holder.name = "Calles"
	add_child(holder)
	var k := 0
	for s in streets:
		var pts: PackedVector2Array = s["points"]
		var y := 0.02 + 0.002 * float(k % 6)
		k += 1
		var edges := _street_edges(s)
		var lefts: Array = edges[0]
		var rights: Array = edges[1]
		var mat: Material = asphalt_mat
		if s["type"] in ["track", "path", "footway", "steps", "pedestrian"]:
			mat = cobble_mat
		for i in pts.size() - 1:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var a := Vector3(lefts[i].x, y, lefts[i].y)
			var b := Vector3(rights[i].x, y, rights[i].y)
			var c := Vector3(rights[i + 1].x, y, rights[i + 1].y)
			var d := Vector3(lefts[i + 1].x, y, lefts[i + 1].y)
			_quad(st, a, b, c, d, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector3.UP)
			_mesh_node(holder, st.commit(), mat, Vector3.ZERO, false)


func _dist_to_street(p: Vector2, skip = null) -> float:
	# distancia al borde de la calzada más cercana (negativa = dentro)
	var best := INF
	for s in streets:
		if s == skip or s["type"] in NO_FURNITURE:
			continue
		var pts: PackedVector2Array = s["points"]
		for i in pts.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
			best = minf(best, p.distance_to(q) - s["width"] * 0.5)
	return best


func _build_curbs() -> void:
	var holder := Node3D.new()
	holder.name = "Bordillos"
	add_child(holder)
	for s in streets:
		if s["type"] in NO_FURNITURE or s["type"] == "pedestrian":
			continue
		var edges := _street_edges(s)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var count := 0
		for side in edges:
			for i in side.size() - 1:
				var a: Vector2 = side[i]
				var b: Vector2 = side[i + 1]
				var L := a.distance_to(b)
				var n := maxi(int(L / 1.0), 1)
				for j in n:
					var p0 := a.lerp(b, float(j) / n)
					var p1 := a.lerp(b, float(j + 1) / n)
					var mid := (p0 + p1) * 0.5
					if _dist_to_street(mid, s) < 0.4 or _in_any_building(mid, 0.0):
						continue
					var dir := (p1 - p0).normalized()
					var basis := Basis(Vector3.UP, atan2(-dir.y, dir.x))
					_box_into(st, Transform3D(basis, Vector3(mid.x, 0.06, mid.y)), Vector3(p0.distance_to(p1) + 0.02, 0.12, 0.16))
					count += 1
		if count > 0:
			_mesh_node(holder, st.commit(), curb_mat, Vector3.ZERO, false)


func _in_any_building(p: Vector2, pad: float) -> bool:
	if is_inside_building(p, pad):
		return true
	for pf in prefabs:
		if Geometry2D.is_point_in_polygon(p, pf["footprint"]):
			return true
	return false


func _kind_for(b: Dictionary, idx: int) -> int:
	var t: String = b["type"]
	var n: String = b["name"].to_lower()
	if t in ["church", "cathedral", "tower"] or n.contains("iglesia") or n.contains("torre"):
		return Kind.PLAIN_STONE
	var c: Vector2 = b["rect"].get_center()
	var r := fmod(float(idx) * 0.618034, 1.0)
	if c.distance_to(_stone_spot) < 45.0:
		return Kind.GRANITE if r < 0.5 else (Kind.BRICK if r < 0.72 else Kind.STUCCO)
	if b["name"] != "":
		return Kind.STUCCO
	return Kind.GRANITE if r < 0.25 else (Kind.BRICK if r < 0.4 else Kind.STUCCO)


func _build_buildings() -> void:
	var holder := Node3D.new()
	holder.name = "Edificios"
	nav_region.add_child(holder)
	var idx := 0
	for b in buildings:
		idx += 1
		var pts: PackedVector2Array = b["points"]
		var h: float = b["height"]
		var kind := _kind_for(b, idx)
		var col: Color = STUCCO_COLORS[(idx * 7919) % STUCCO_COLORS.size()]
		col.a = float(kind * 64 + (idx * 37) % 63) / 255.0
		var windows := kind != Kind.PLAIN_STONE
		var quad := pts.size() == 4 and h < 14.0
		var wall_top := h if quad else h + 0.7  # pretil en azoteas

		var walls := SurfaceTool.new()
		walls.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n := pts.size()
		for i in n:
			var a2 := pts[i]
			var b2 := pts[(i + 1) % n]
			var edge := b2 - a2
			var length := edge.length()
			if length < 0.01:
				continue
			var n2 := Vector2(edge.y, -edge.x).normalized()
			var mid := (a2 + b2) * 0.5
			if Geometry2D.is_point_in_polygon(mid + n2 * 0.05, pts):
				n2 = -n2
			var nrm := Vector3(n2.x, 0, n2.y)
			var y0 := -0.2
			var uv2 := Vector2(length if windows else 0.0, wall_top)
			_quad(walls, Vector3(a2.x, y0, a2.y), Vector3(b2.x, y0, b2.y), Vector3(b2.x, wall_top, b2.y), Vector3(a2.x, wall_top, a2.y),
				Vector2(0, y0), Vector2(length, y0), Vector2(length, wall_top), Vector2(0, wall_top), nrm, uv2, col)
		var mesh := walls.commit()
		if mesh.get_surface_count() == 0:
			continue
		mesh.surface_set_material(0, facade_mat)

		var body := StaticBody3D.new()
		body.name = b["name"] if b["name"] != "" else "Casa%d" % idx
		holder.add_child(body)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		cs.shape = mesh.create_trimesh_shape()
		body.add_child(cs)

		if quad:
			_hip_roof(body, pts, h, b["type"] == "tower")
		else:
			var roof := SurfaceTool.new()
			roof.begin(Mesh.PRIMITIVE_TRIANGLES)
			var tris := Geometry2D.triangulate_polygon(pts)
			for t in range(0, tris.size(), 3):
				var p0 := pts[tris[t]]
				var p1 := pts[tris[t + 1]]
				var p2 := pts[tris[t + 2]]
				_tri(roof, [Vector3(p0.x, h, p0.y), Vector3(p1.x, h, p1.y), Vector3(p2.x, h, p2.y)],
					[p0, p1, p2], Vector3.UP, Vector2.ZERO, Color.WHITE)
			if tris.size() >= 3:
				_mesh_node(body, roof.commit(), flat_roof_mat)


func _hip_roof(parent: Node3D, pts: PackedVector2Array, h: float, steep: bool) -> void:
	# Ajusta un rectángulo orientado al edificio y le pone un tejado a cuatro aguas
	var u := (pts[1] - pts[0]).normalized()
	var v := Vector2(-u.y, u.x)
	var umin := INF
	var umax := -INF
	var vmin := INF
	var vmax := -INF
	for p in pts:
		umin = minf(umin, p.dot(u))
		umax = maxf(umax, p.dot(u))
		vmin = minf(vmin, p.dot(v))
		vmax = maxf(vmax, p.dot(v))
	var L := umax - umin
	var W := vmax - vmin
	var c := u * (umin + umax) * 0.5 + v * (vmin + vmax) * 0.5
	if W > L:
		var tmp := u
		u = v
		v = -tmp
		var t2 := L
		L = W
		W = t2
	var o := 0.4
	var rise := W * 0.5 * (1.4 if steep else 0.42)
	var r := maxf(0.0, L * 0.5 - W * 0.5)
	var he := h - 0.05
	var hu := L * 0.5 + o
	var hv := W * 0.5 + o
	var A := _v3(c - u * hu - v * hv, he)
	var B := _v3(c + u * hu - v * hv, he)
	var C := _v3(c + u * hu + v * hv, he)
	var D := _v3(c - u * hu + v * hv, he)
	var R1 := _v3(c - u * r, h + rise)
	var R2 := _v3(c + u * r, h + rise)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_roof_face(st, [A, B, R2, R1])
	_roof_face(st, [C, D, R1, R2])
	_roof_face(st, [D, A, R1])
	_roof_face(st, [B, C, R2])
	_mesh_node(parent, st.commit(), roof_mat)
	# Chimenea
	if rng.randf() < 0.35 and not steep:
		var cp := c + u * rng.randf_range(-r, r) * 0.8 + v * W * 0.18
		var ch := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.6, rise + 1.2, 0.6)
		ch.mesh = bm
		ch.material_override = curb_mat
		ch.position = Vector3(cp.x, h + (rise + 1.2) * 0.5, cp.y)
		parent.add_child(ch)


func _v3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


func _roof_face(st: SurfaceTool, v: Array) -> void:
	var e0: Vector3 = v[0]
	var e1: Vector3 = v[1]
	var eave := (e1 - e0).normalized()
	var n := (e1 - e0).cross(v[2] - e0).normalized()
	if n.y < 0:
		n = -n
	var uvs: Array = []
	for p in v:
		var d: Vector3 = p - e0
		var along := d.dot(eave)
		var up := (d - eave * along).length()
		uvs.append(Vector2(along, up))
	_tri(st, [v[0], v[1], v[2]], [uvs[0], uvs[1], uvs[2]], n, Vector2.ZERO, Color.WHITE)
	if v.size() == 4:
		_tri(st, [v[0], v[2], v[3]], [uvs[0], uvs[2], uvs[3]], n, Vector2.ZERO, Color.WHITE)


func _build_prefabs() -> void:
	for pf in prefabs:
		if pf["prefab"] == "bar_chiqui":
			bar = BarChiqui.new()
			bar.name = "BarChiqui"
			nav_region.add_child(bar)
			bar.position = Vector3(pf["pos"].x, 0.0, pf["pos"].y)
			bar.rotation.y = pf["yaw"]
			bar.build(self)
			exterior_open = false


func _build_props() -> void:
	for p in pois:
		if p["type"] == "fountain":
			_build_fountain(p["pos"])


func _build_fountain(pos: Vector2) -> void:
	var body := StaticBody3D.new()
	body.name = "Fuente"
	body.position = Vector3(pos.x, 0, pos.y)
	nav_region.add_child(body)
	var stone := _std(Color(0.55, 0.52, 0.47), 0.9, noise_tex, 1.0)
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.03, 0.05, 0.05)
	water.roughness = 0.02
	var parts := [[2.6, 2.7, 0.7, 0.35], [0.25, 0.4, 2.2, 1.1], [0.9, 0.3, 0.35, 2.2]]
	for prt in parts:
		var cm := CylinderMesh.new()
		cm.top_radius = prt[0]
		cm.bottom_radius = prt[1]
		cm.height = prt[2]
		cm.radial_segments = 32
		_mesh_node(body, cm, stone, Vector3(0, prt[3], 0))
	var sm := CylinderMesh.new()
	sm.top_radius = 2.35
	sm.bottom_radius = 2.35
	sm.height = 0.02
	_mesh_node(body, sm, water, Vector3(0, 0.66, 0))
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 2.7
	shape.height = 1.5
	cs.shape = shape
	cs.position.y = 0.75
	body.add_child(cs)


# ---------------------------------------------------------------- mobiliario urbano

func _sidewalk_points(spacing: float, offset_extra: float, side_mode: String, start_off: float) -> Array:
	# Devuelve [{pos, dir, street}] a lo largo de las aceras
	var out: Array = []
	for s in streets:
		if s["type"] in NO_FURNITURE:
			continue
		var pts: PackedVector2Array = s["points"]
		var w: float = s["width"]
		var acc := start_off
		var side := 1.0
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var seg := a.distance_to(b)
			if seg < 0.01:
				continue
			var dir := (b - a) / seg
			var nrm := Vector2(-dir.y, dir.x)
			var t := spacing - acc
			while t < seg:
				var sd := side if side_mode == "alt" else 1.0
				var p := a + dir * t + nrm * (w * 0.5 + offset_extra) * sd
				out.append({"pos": p, "dir": dir, "street": s, "side": sd})
				if side_mode == "alt":
					side = -side
				t += spacing
			acc = fmod(acc + seg, spacing)
	return out


func _spot_free(p: Vector2, pad: float, s = null) -> bool:
	if not bounds.grow(-2.0).has_point(p):
		return false
	if _in_any_building(p, pad):
		return false
	if _dist_to_street(p, null) < 0.3:
		return false
	for pf in prefabs:
		var fp: PackedVector2Array = pf["footprint"]
		var r := Rect2(fp[0], Vector2.ZERO)
		for q in fp:
			r = r.expand(q)
		if r.grow(1.5).has_point(p):
			return false
	return true


func _build_poles_and_wires() -> void:
	var holder := Node3D.new()
	holder.name = "Postes"
	nav_region.add_child(holder)
	var pole_st := SurfaceTool.new()
	pole_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cyl_into(pole_st, Transform3D(Basis(), Vector3(0, 4.0, 0)), 0.11, 0.15, 8.0, 8)
	_box_into(pole_st, Transform3D(Basis(), Vector3(0, 7.3, 0)), Vector3(1.5, 0.1, 0.1))
	for x in [-0.6, 0.0, 0.6]:
		_cyl_into(pole_st, Transform3D(Basis(), Vector3(x, 7.43, 0)), 0.03, 0.04, 0.16, 6)
	var pole_mesh := pole_st.commit()
	var shape := CylinderShape3D.new()
	shape.radius = 0.16
	shape.height = 8.0

	var poles_by_street := {}
	for c in _sidewalk_points(30.0, 0.7, "one", 12.0):
		var p: Vector2 = c["pos"]
		if not _spot_free(p, 0.6):
			continue
		var body := StaticBody3D.new()
		body.position = Vector3(p.x, 0, p.y)
		body.rotation.y = atan2(-c["dir"].y, c["dir"].x) + PI * 0.5
		holder.add_child(body)
		_mesh_node(body, pole_mesh, wood_mat)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position.y = 4.0
		body.add_child(cs)
		var key: int = streets.find(c["street"])
		if not poles_by_street.has(key):
			poles_by_street[key] = []
		poles_by_street[key].append(body)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for key in poles_by_street:
		var list: Array = poles_by_street[key]
		for i in list.size():
			var p0: StaticBody3D = list[i]
			if i + 1 < list.size():
				var p1: StaticBody3D = list[i + 1]
				if p0.position.distance_to(p1.position) < 45.0:
					for x in [-0.6, 0.0, 0.6]:
						var a := p0.position + p0.basis * Vector3(x, 7.45, 0)
						var b := p1.position + p1.basis * Vector3(x, 7.45, 0)
						_wire(st, a, b, 0.7)
			# acometida a una casa cercana
			if rng.randf() < 0.6:
				var target = _nearest_wall(Vector2(p0.position.x, p0.position.z), 14.0)
				if target != null:
					var a2 := p0.position + Vector3(0, 7.0, 0)
					var b2 := Vector3(target["pos"].x, minf(target["height"] - 0.4, 5.5), target["pos"].y)
					_wire(st, a2, b2, 0.5)
	var wires := _mesh_node(self, st.commit(), wire_mat, Vector3.ZERO, false)
	wires.name = "Cables"


func _wire(st: SurfaceTool, a: Vector3, b: Vector3, sag: float) -> void:
	var segs := 8
	var prev := a
	for i in range(1, segs + 1):
		var t := float(i) / segs
		var p := a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)
		var d := p - prev
		var L := d.length()
		if L > 0.001:
			var y := d / L
			var x := y.cross(Vector3.UP)
			if x.length() < 0.01:
				x = Vector3.RIGHT
			x = x.normalized()
			var z := x.cross(y).normalized()
			_box_into(st, Transform3D(Basis(x, y, z), (prev + p) * 0.5), Vector3(0.022, L, 0.022))
		prev = p


func _nearest_wall(p: Vector2, max_d: float):
	var best = null
	var best_d := max_d
	for b in buildings:
		var r: Rect2 = b["rect"]
		if not r.grow(max_d).has_point(p):
			continue
		var pts: PackedVector2Array = b["points"]
		for i in pts.size():
			var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[(i + 1) % pts.size()])
			var d := p.distance_to(q)
			if d < best_d:
				best_d = d
				var e: Vector2 = pts[(i + 1) % pts.size()] - pts[i]
				var n := Vector2(e.y, -e.x).normalized()
				if Geometry2D.is_point_in_polygon(q + n * 0.1, pts):
					n = -n
				best = {"pos": q, "normal": n, "height": b["height"], "dist": d}
	return best


func _build_trees() -> void:
	# Plátanos de sombra podados (desmochados), como en la Avenida Alejandro Rubio
	var holder := Node3D.new()
	holder.name = "Arboles"
	nav_region.add_child(holder)
	var grate := BoxMesh.new()
	grate.size = Vector3(1.2, 0.03, 1.2)
	var trunk_shape := CylinderShape3D.new()
	trunk_shape.radius = 0.25
	trunk_shape.height = 3.0
	var count := 0
	for c in _sidewalk_points(10.5, 1.0, "both", 5.0):
		var s: Dictionary = c["street"]
		if not s["name"].contains("Alejandro Rubio"):
			continue
		var p: Vector2 = c["pos"]
		if not _spot_free(p, 1.2):
			continue
		if _dist_to_street(p, s) < 2.0:
			continue
		if rng.randf() < 0.25:
			continue
		var body := StaticBody3D.new()
		body.position = Vector3(p.x, 0, p.y)
		body.rotation.y = rng.randf() * TAU
		holder.add_child(body)
		_mesh_node(body, _tree_mesh(), bark_mat)
		_mesh_node(body, grate, iron_mat, Vector3(0, 0.015, 0), false)
		var cs := CollisionShape3D.new()
		cs.shape = trunk_shape
		cs.position.y = 1.5
		body.add_child(cs)
		count += 1


func _tree_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk_h := rng.randf_range(2.8, 3.6)
	var lean := Basis(Vector3.RIGHT, rng.randf_range(-0.06, 0.06))
	_cyl_into(st, Transform3D(lean, lean * Vector3(0, trunk_h * 0.5, 0)), 0.17, 0.24, trunk_h, 10)
	var top := lean * Vector3(0, trunk_h, 0)
	var limbs := rng.randi_range(3, 5)
	for i in limbs:
		var ang := TAU * i / limbs + rng.randf_range(-0.4, 0.4)
		var tilt := rng.randf_range(0.35, 0.75)
		var length := rng.randf_range(1.2, 2.2)
		var bs := Basis(Vector3.UP, ang) * Basis(Vector3.RIGHT, tilt)
		var center := top + bs * Vector3(0, length * 0.5, 0)
		_cyl_into(st, Transform3D(bs, center), 0.08, 0.13, length, 7)
		var tip := top + bs * Vector3(0, length, 0)
		var knob := SphereMesh.new()
		knob.radius = 0.15
		knob.height = 0.32
		knob.radial_segments = 8
		knob.rings = 4
		st.append_from(knob, 0, Transform3D(Basis(), tip))
		for k in rng.randi_range(3, 6):
			var tb := bs * Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(0.1, 0.6))
			var tl := rng.randf_range(0.5, 1.3)
			_cyl_into(st, Transform3D(tb, tip + tb * Vector3(0, tl * 0.5, 0)), 0.012, 0.03, tl, 4)
	return st.commit()


func _build_boundary() -> void:
	var body := StaticBody3D.new()
	body.name = "LimiteMapa"
	nav_region.add_child(body)
	var r := bounds
	var c := r.get_center()
	var walls := [
		[Vector3(c.x, 3, r.position.y), Vector3(r.size.x + 2, 6, 1)],
		[Vector3(c.x, 3, r.end.y), Vector3(r.size.x + 2, 6, 1)],
		[Vector3(r.position.x, 3, c.y), Vector3(1, 6, r.size.y + 2)],
		[Vector3(r.end.x, 3, c.y), Vector3(1, 6, r.size.y + 2)],
	]
	for w in walls:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = w[1]
		cs.shape = box
		cs.position = w[0]
		body.add_child(cs)


# ---------------------------------------------------------------- jugabilidad

func is_inside_building(p: Vector2, pad: float = 0.0) -> bool:
	for b in buildings:
		var r: Rect2 = b["rect"]
		if not r.grow(pad).has_point(p):
			continue
		if Geometry2D.is_point_in_polygon(p, b["points"]):
			return true
		if pad > 0.0:
			for o in [Vector2(pad, 0), Vector2(-pad, 0), Vector2(0, pad), Vector2(0, -pad)]:
				if Geometry2D.is_point_in_polygon(p + o, b["points"]):
					return true
	return false


func _compute_spawns() -> void:
	var inner := bounds.grow(-3.0)
	for s in streets:
		var pts: PackedVector2Array = s["points"]
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var steps := maxi(int(a.distance_to(b) / 7.0), 1)
			for j in steps + 1:
				var p := a.lerp(b, float(j) / steps)
				if inner.has_point(p) and not _in_any_building(p, 0.9):
					spawn_points.append(Vector3(p.x, 0.05, p.y))
	for p in pois:
		if p["type"] == "fountain":
			spawn_points = spawn_points.filter(func(sp): return Vector2(sp.x, sp.z).distance_to(p["pos"]) > 4.0)


func _choose_player_start() -> void:
	if bar:
		player_start = bar.player_start
		player_start_yaw = bar.player_start_yaw
		return
	var target := bounds.get_center()
	for p in pois:
		if p["type"] == "fountain":
			target = p["pos"] + Vector2(0, 7)
	if is_test_town:
		player_start = Vector3(target.x, 0.05, target.y)
		player_start_yaw = 0.0
		return
	var look_at_pos = null
	for p in pois:
		if p["type"] == "start":
			target = p["pos"]
		elif p["type"] == "place_of_worship" and look_at_pos == null:
			look_at_pos = p["pos"]
	var tries := 0
	while tries < 40 and (is_inside_building(target, 0.8) or _near_fountain(target)):
		target += Vector2(1.5, 0).rotated(tries * 2.4) * (1.0 + tries * 0.25)
		tries += 1
	player_start = Vector3(target.x, 0.05, target.y)
	if look_at_pos != null:
		var to: Vector2 = look_at_pos - target
		player_start_yaw = atan2(-to.x, -to.y)


func _near_fountain(p: Vector2) -> bool:
	for f in pois:
		if f["type"] == "fountain" and f["pos"].distance_to(p) < 4.0:
			return true
	return false


func _build_lamps() -> void:
	# Farolas fernandinas: en la pared si hay fachada cerca, si no sobre poste
	var holder := Node3D.new()
	holder.name = "Farolas"
	add_child(holder)
	var lantern := _lantern_mesh()
	var bracket := _bracket_mesh()
	var post_st := SurfaceTool.new()
	post_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cyl_into(post_st, Transform3D(Basis(), Vector3(0, 0.25, 0)), 0.12, 0.16, 0.5, 10)
	_cyl_into(post_st, Transform3D(Basis(), Vector3(0, 1.9, 0)), 0.045, 0.075, 3.0, 8)
	_cyl_into(post_st, Transform3D(Basis(), Vector3(0, 3.45, 0)), 0.09, 0.05, 0.15, 8)
	var post_mesh := post_st.commit()

	var candidates: Array = []
	for c in _sidewalk_points(20.0, 0.6, "alt", 6.0):
		candidates.append(c["pos"])
	if is_test_town:
		for c in [Vector2(-13, -13), Vector2(13, -13), Vector2(-13, 13), Vector2(13, 13)]:
			candidates.push_front(c)
	var placed: Array = []
	for p in candidates:
		if lamps.size() >= MAX_LAMPS:
			break
		if not bounds.grow(-2.0).has_point(p) or _in_any_building(p, 0.3):
			continue
		var too_close := false
		for q in placed:
			if q.distance_to(p) < 12.0:
				too_close = true
				break
		if too_close:
			continue
		placed.append(p)
		var lamp := Node3D.new()
		holder.add_child(lamp)
		var head_y := 3.7
		var wall = _nearest_wall(p, 3.2)
		if wall != null and wall["height"] > 4.5:
			var wp: Vector2 = wall["pos"] + wall["normal"] * 0.55
			lamp.position = Vector3(wp.x, 0, wp.y)
			lamp.rotation.y = atan2(wall["normal"].x, wall["normal"].y)
			head_y = 3.9
			_mesh_node(lamp, bracket, iron_mat, Vector3(0, head_y + 0.35, 0))
		else:
			lamp.position = Vector3(p.x, 0, p.y)
			_mesh_node(lamp, post_mesh, iron_mat)
		var r := rng.randf()
		var mode := "ok"
		if r < 0.1:
			mode = "broken"
		elif r < 0.24:
			mode = "flicker"
		elif r < 0.3:
			mode = "dying"
		var head := _mesh_node(lamp, lantern, iron_mat, Vector3(0, head_y, 0))
		head.set_surface_override_material(0, glass_mat if mode != "broken" else iron_mat)
		head.set_surface_override_material(1, iron_mat)
		if mode == "broken":
			continue
		var light := OmniLight3D.new()
		light.position.y = head_y - 0.1
		light.light_color = Color(1.0, 0.68, 0.38)
		light.light_energy = 2.2
		light.omni_range = 13.0
		light.omni_attenuation = 1.1
		light.light_volumetric_fog_energy = 1.6
		light.shadow_enabled = lamps.size() < 6
		lamp.add_child(light)
		lamps.append({"light": light, "base": light.light_energy, "mode": mode,
			"speed": rng.randf_range(9.0, 23.0)})


func _lantern_mesh() -> ArrayMesh:
	# Superficie 0: cristal; superficie 1: armazón de hierro
	var glass := CylinderMesh.new()
	glass.top_radius = 0.2
	glass.bottom_radius = 0.13
	glass.height = 0.42
	glass.radial_segments = 4
	glass.rings = 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(glass, 0, Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 0.0, 0)))
	var mesh := st.commit()
	var fr := SurfaceTool.new()
	fr.begin(Mesh.PRIMITIVE_TRIANGLES)
	var b45 := Basis(Vector3.UP, PI * 0.25)
	_cyl_into(fr, Transform3D(b45, Vector3(0, 0.29, 0)), 0.05, 0.27, 0.16, 4)
	_cyl_into(fr, Transform3D(b45, Vector3(0, 0.215, 0)), 0.235, 0.235, 0.03, 4)
	_cyl_into(fr, Transform3D(b45, Vector3(0, -0.235, 0)), 0.15, 0.08, 0.06, 4)
	_cyl_into(fr, Transform3D(Basis(), Vector3(0, 0.42, 0)), 0.015, 0.04, 0.12, 6)
	for k in 4:
		var a := PI * 0.5 * k
		var off := Vector3(cos(a), 0, sin(a)) * 0.165
		_box_into(fr, Transform3D(Basis(Vector3.UP, a), off), Vector3(0.02, 0.44, 0.02))
	fr.commit(mesh)
	return mesh


func _bracket_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box_into(st, Transform3D(Basis(), Vector3(0, 0.1, -0.3)), Vector3(0.04, 0.04, 0.62))
	_box_into(st, Transform3D(Basis(Vector3.RIGHT, 0.75), Vector3(0, -0.12, -0.42)), Vector3(0.03, 0.03, 0.5))
	_box_into(st, Transform3D(Basis(), Vector3(0, -0.05, -0.6)), Vector3(0.14, 0.4, 0.03))
	_cyl_into(st, Transform3D(Basis(), Vector3(0, 0.06, 0)), 0.02, 0.02, 0.1, 6)
	return st.commit()


# ---------------------------------------------------------------- navegación

func _bake_navigation() -> void:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.25
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nm.geometry_collision_mask = 0xFFFFFFFF & ~16   # las puertas que se compran no cuentan
	# Sólo hasta 2.6 m de altura: así no se generan zonas en tejados ni terrazas
	nm.filter_baking_aabb = AABB(Vector3(bounds.position.x, -1.5, bounds.position.y),
		Vector3(bounds.size.x, 4.1, bounds.size.y))
	nav_region.navigation_mesh = nm
	_baking = true
	nav_region.bake_navigation_mesh(false)


func request_rebake() -> void:
	# Al abrir una puerta: recalcular la navegación en segundo plano
	if _baking:
		_rebake_pending = true
		return
	_baking = true
	nav_region.bake_navigation_mesh(true)


func _on_bake_finished() -> void:
	_baking = false
	if _rebake_pending:
		_rebake_pending = false
		request_rebake()
	navigation_ready.emit()


func open_exterior() -> void:
	exterior_open = true
