extends RefCounted
## El resto del pueblo, de fondo: calles y casas sencillas fuera de la zona
## jugable, para que entre la niebla se vea Guadalix entero. Sin colisión ni
## interiores. Todo se junta por bloques de BLOCK m (pocas llamadas de dibujo)
## y cada bloque deja de dibujarse a partir de DRAW_DIST (la niebla lo tapa).

const BLOCK := 100.0
const DRAW_DIST := 300.0


static func build(town, data: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Fondo"
	town.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var walls := {}     # bloque -> SurfaceTool
	var roofs := {}
	var roads := {}
	for b in data.get("buildings", []):
		var pts: Array = b["points"]
		if pts.size() < 3:
			continue
		var c := Vector2.ZERO
		for p in pts:
			c += Vector2(p[0], p[1])
		c /= pts.size()
		var key := Vector2i(floori(c.x / BLOCK), floori(c.y / BLOCK))
		if not walls.has(key):
			walls[key] = _st()
			roofs[key] = _st()
		_house(town, walls[key], roofs[key], pts, float(b["height"]), c, rng, _origin(key))
	for s in data.get("streets", []):
		var pts: Array = s["points"]
		var w: float = s["width"]
		for i in pts.size() - 1:
			var a := Vector2(pts[i][0], pts[i][1])
			var bb := Vector2(pts[i + 1][0], pts[i + 1][1])
			var key := Vector2i(floori(a.x / BLOCK), floori(a.y / BLOCK))
			if not roads.has(key):
				roads[key] = _st()
			_ribbon(town, roads[key], a, bb, w, _origin(key))
	for key in walls:
		_node(root, walls[key], town.facade_mat, key)
		_node(root, roofs[key], town.dark_roof_mat if town.dark_roof_mat else town.roof_mat, key)
	for key in roads:
		_node(root, roads[key], town.asphalt_mat, key)
	# suelo de tierra bajo todo el fondo
	var r: Array = data.get("rect", [])
	if r.size() == 2:
		var a := Vector2(r[0][0], r[0][1])
		var bb := Vector2(r[1][0], r[1][1])
		var pm := PlaneMesh.new()
		pm.size = bb - a
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.3, 0.26, 0.22)
		m.roughness = 1.0
		mi.material_override = m
		mi.position = Vector3((a.x + bb.x) * 0.5, -0.06, (a.y + bb.y) * 0.5)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


static func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _origin(key: Vector2i) -> Vector3:
	return Vector3((key.x + 0.5) * BLOCK, 0.0, (key.y + 0.5) * BLOCK)


static func _node(root: Node3D, st: SurfaceTool, mat: Material, key: Vector2i) -> void:
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = _origin(key)
	mi.visibility_range_end = DRAW_DIST
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## Casa: paredes con el shader de fachadas y tejado a cuatro aguas sencillo
static func _house(town, walls: SurfaceTool, roofs: SurfaceTool, pts: Array, h: float, c: Vector2,
		rng: RandomNumberGenerator, o: Vector3) -> void:
	var n := pts.size()
	var r := rng.randf()
	var kind := 0 if r < 0.6 else (1 if r < 0.85 else 2)
	var col: Color = [Color(0.92, 0.88, 0.78), Color(0.88, 0.8, 0.64), Color(0.95, 0.93, 0.88), Color(0.85, 0.72, 0.55)][rng.randi() % 4]
	col.a = float(kind * 64 + rng.randi_range(0, 1) * 16 + rng.randi() % 16) / 255.0
	var cc := Vector3(c.x, 0, c.y) - o
	for i in n:
		var a := Vector3(pts[i][0], 0, pts[i][1]) - o
		var b := Vector3(pts[(i + 1) % n][0], 0, pts[(i + 1) % n][1]) - o
		var e := b - a
		var L := e.length()
		if L < 0.1:
			continue
		var nrm := Vector3(e.z, 0, -e.x).normalized()
		if nrm.dot((a + b) * 0.5 - cc) < 0.0:
			nrm = -nrm
		town._quad(walls, a + Vector3(0, -0.2, 0), b + Vector3(0, -0.2, 0), b + Vector3(0, h, 0), a + Vector3(0, h, 0),
			Vector2(0, -0.2), Vector2(L, -0.2), Vector2(L, h), Vector2(0, h), nrm, Vector2(L, h), col)
		# faldón hasta el centro
		var apex := cc + Vector3(0, h + 1.6, 0)
		var mid := (a + b) * 0.5
		var slope := Vector2((apex - mid).x, (apex - mid).z).length()
		var up := (apex - Vector3(mid.x, h, mid.z))
		var rn := e.cross(up).normalized()
		if rn.y < 0.0:
			rn = -rn
		town._tri(roofs, [a + Vector3(0, h, 0) - nrm * -0.3, b + Vector3(0, h, 0) - nrm * -0.3, apex],
			[Vector2(0, 0), Vector2(L, 0), Vector2(L * 0.5, slope)], rn, Vector2.ZERO, Color.WHITE)


static func _ribbon(town, st: SurfaceTool, a: Vector2, b: Vector2, w: float, o: Vector3) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x) * w * 0.5
	var ext := d * w * 0.4
	var p := [a - ext + n, b + ext + n, b + ext - n, a - ext - n]
	var v := []
	for q in p:
		v.append(Vector3(q.x, 0.01, q.y) - o)
	town._quad(st, v[3], v[2], v[1], v[0], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector3.UP)
