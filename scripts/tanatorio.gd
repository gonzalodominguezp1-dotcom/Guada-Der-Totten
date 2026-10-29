extends Node3D
## Tanatorio de Guadalix (nivel aparte): se llega por el portal del instituto.
## Ambiente sombrío con niebla; dentro está el Pack-a-Punch.
## El cementerio de al lado NO se modela ni se puede visitar: solo su tapia de
## piedra y unos cipreses detrás, por respeto a los difuntos.
## Coordenadas locales desde el centro del edificio (x = este, z = sur), sacadas
## de data/tanatorio.osm (clave "tanatorio" de town.json).

const L = preload("res://scripts/landmarks.gd")
const Interiors = preload("res://scripts/interiors.gd")
const Portal = preload("res://scripts/portal.gd")
const PackAPunch = preload("res://scripts/pack_a_punch.gd")
const FLOOR_SHADER = preload("res://shaders/terracotta_floor.gdshader")
const INTERIOR_SHADER = preload("res://shaders/interior_wall.gdshader")

const PLAY := Rect2(-36.0, -5.0, 64.0, 57.0)   # zona jugable (x0, z0, ancho, fondo)

var town
var data: Dictionary
var nav: NavigationRegion3D
var portal
var rng := RandomNumberGenerator.new()
var concrete: StandardMaterial3D
var soil: StandardMaterial3D
var granite: StandardMaterial3D


static func create(t, d: Dictionary, origin: Vector3):
	var tn = load("res://scripts/tanatorio.gd").new()
	tn.name = "Tanatorio"
	tn.town = t
	tn.data = d
	t.add_child(tn)
	tn.position = origin
	tn._build()
	return tn


func _build() -> void:
	rng.seed = 404
	nav = NavigationRegion3D.new()
	nav.name = "NavegacionTanatorio"
	add_child(nav)
	concrete = _soft(Color(0.48, 0.47, 0.44), 0.95, 0.35)
	soil = _soft(Color(0.42, 0.28, 0.2), 1.0, 0.15)
	granite = _soft(Color(0.55, 0.55, 0.56), 0.9, 1.5)
	_ground()
	_roads()
	_cemetery_wall()
	_edificio()
	_bounds()
	_greenery()
	_lamps()
	_mist()
	_spawns()
	# portal de vuelta, en el aparcamiento mirando al edificio
	portal = Portal.new()
	portal.label_text = "INSTITUTO"
	portal.town = town
	portal.name = "PortalTanatorio"
	nav.add_child(portal)
	portal.position = Vector3(-6.0, 0.0, 33.0)
	portal.rotation.y = PI
	if town.portal_instituto:
		portal.other = town.portal_instituto
		town.portal_instituto.other = portal
	_bake()


func _soft(c: Color, rough: float, scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.albedo_texture = town.soft_noise
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	return m


func _static_box(parent: Node3D, center: Vector3, size: Vector3, mat: Material = null, rot_y := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	body.rotation.y = rot_y
	parent.add_child(body)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	if mat:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = mat
		body.add_child(mi)
	return body


# ---------------------------------------------------------------- suelo y caminos

func _ground() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(300, 300)
	pm.subdivide_width = 12
	pm.subdivide_depth = 12
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = soil
	nav.add_child(mi)
	_static_box(nav, Vector3(0, -0.5, 0), Vector3(300, 1.0, 300))


func _ribbon(st: SurfaceTool, pts: Array, width: float, y: float) -> void:
	for i in pts.size() - 1:
		var a := Vector2(pts[i][0], pts[i][1])
		var b := Vector2(pts[i + 1][0], pts[i + 1][1])
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x) * width * 0.5
		var ext := d * width * 0.5   # solapar en las curvas
		var p0 := a - ext + n
		var p1 := b + ext + n
		var p2 := b + ext - n
		var p3 := a - ext - n
		town._quad(st, Vector3(p3.x, y, p3.y), Vector3(p2.x, y, p2.y), Vector3(p1.x, y, p1.y), Vector3(p0.x, y, p0.y),
			p3, p2, p1, p0, Vector3.UP)


func _roads() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in data.get("roads", []):
		_ribbon(st, r["points"], float(r["width"]), 0.03)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = concrete
	nav.add_child(mi)
	# franjas de adoquín de granito cruzando el camino (como en la foto)
	for r in data.get("roads", []):
		if r["name"] == "":
			continue
		var pts: Array = r["points"]
		for i in pts.size() - 1:
			var a := Vector2(pts[i][0], pts[i][1])
			var b := Vector2(pts[i + 1][0], pts[i + 1][1])
			var Lg := a.distance_to(b)
			var t := 4.0
			while t < Lg:
				var p := a.lerp(b, t / Lg)
				if PLAY.grow(10.0).has_point(p):
					L._box(nav, Vector3(p.x, 0.045, p.y), Vector3(float(r["width"]), 0.02, 0.35), granite,
						false, Vector3(0, atan2(-(b - a).y, (b - a).x), 0))
				t += 9.0
	# aparcamiento
	for poly in data.get("parking", []):
		var pp := PackedVector2Array()
		for p in poly:
			pp.append(Vector2(p[0], p[1]))
		var tris := Geometry2D.triangulate_polygon(pp)
		var ps := SurfaceTool.new()
		ps.begin(Mesh.PRIMITIVE_TRIANGLES)
		for k in range(0, tris.size(), 3):
			var vs := []
			for j in 3:
				vs.append(Vector3(pp[tris[k + j]].x, 0.035, pp[tris[k + j]].y))
			town._tri(ps, vs, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], Vector3.UP, Vector2.ZERO, Color.WHITE)
		if tris.size() >= 3:
			var pmi := MeshInstance3D.new()
			pmi.mesh = ps.commit()
			pmi.material_override = _soft(Color(0.44, 0.43, 0.41), 0.95, 0.3)
			nav.add_child(pmi)
		# líneas de las plazas
		var white := StandardMaterial3D.new()
		white.albedo_color = Color(0.85, 0.85, 0.82)
		for k in 7:
			L._box(nav, Vector3(-10.0 + k * 3.4, 0.05, 41.0), Vector3(0.12, 0.02, 4.5), white)


# ---------------------------------------------------------------- tapia del cementerio

func _stone_wall(a: Vector2, b: Vector2, h: float) -> void:
	var Lg := a.distance_to(b)
	if Lg < 0.3:
		return
	var dir := (b - a) / Lg
	var n := Vector2(-dir.y, dir.x)
	var col := Color(0.82, 0.76, 0.66)
	col.a = float(1 * 64 + 0 * 16 + 5) / 255.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [1.0, -1.0]:
		var o: Vector2 = n * 0.25 * side
		var p0 := a + o
		var p1 := b + o
		town._quad(st, Vector3(p0.x, -0.1, p0.y), Vector3(p1.x, -0.1, p1.y), Vector3(p1.x, h, p1.y), Vector3(p0.x, h, p0.y),
			Vector2(0, -0.1), Vector2(Lg, -0.1), Vector2(Lg, h), Vector2(0, h), Vector3(n.x * side, 0, n.y * side), Vector2(0, h), col)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = town.facade_mat
	nav.add_child(mi)
	var mid := (a + b) * 0.5
	_static_box(nav, Vector3(mid.x, (h + 1.0) * 0.5, mid.y), Vector3(Lg, h + 1.0, 0.5), null, atan2(-dir.y, dir.x))
	L._box(nav, Vector3(mid.x, h + 0.06, mid.y), Vector3(Lg + 0.05, 0.12, 0.62), town.curb_mat, false, Vector3(0, atan2(-dir.y, dir.x), 0))


func _cemetery_wall() -> void:
	for poly in data.get("cemetery", []):
		# solo los lados que dan a la zona jugable (sur y el tramo oeste cercano)
		for i in poly.size():
			var a := Vector2(poly[i][0], poly[i][1])
			var b := Vector2(poly[(i + 1) % poly.size()][0], poly[(i + 1) % poly.size()][1])
			if maxf(a.y, b.y) < -40.0:
				continue
			_stone_wall(a, b, 3.0)
		# cipreses detrás de la tapia sur
		var a := Vector2(poly[2][0], poly[2][1])
		var b := Vector2(poly[3][0], poly[3][1])
		var k := 0.04
		while k < 1.0:
			var p := a.lerp(b, k) + Vector2(rng.randf_range(-1, 1), -3.0 - rng.randf() * 2.0)
			_cypress(Vector3(p.x, 0, p.y), rng.randf_range(8.0, 12.0))
			k += 0.09
	# el camino sigue al norte junto al cementerio: cerrado con tapia y una verja
	_stone_wall(Vector2(-37.0, -4.5), Vector2(-28.6, -5.0), 3.0)
	_stone_wall(Vector2(-20.4, -5.4), Vector2(-9.6, -5.6), 3.0)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.06, 0.06, 0.07)
	iron.metallic = 0.6
	iron.roughness = 0.5
	_static_box(nav, Vector3(-24.5, 1.3, -5.2), Vector3(8.4, 2.6, 0.15), null)
	var bar := 0.0
	while bar < 8.2:
		L._box(nav, Vector3(-28.6 + bar, 1.3, -5.2), Vector3(0.04, 2.6, 0.04), iron)
		bar += 0.16
	for y in [0.2, 1.3, 2.5]:
		L._box(nav, Vector3(-24.5, y, -5.2), Vector3(8.2, 0.06, 0.06), iron)


# ---------------------------------------------------------------- edificio del tanatorio

func _edificio() -> void:
	var poly: Array = data.get("building", [])
	var yaw := 0.0
	if poly.size() >= 4:
		var a := Vector2(poly[0][0], poly[0][1])
		var b := Vector2(poly[3][0], poly[3][1])   # lado norte, de oeste a este
		yaw = atan2(-(b - a).y, (b - a).x)
	var ed := Node3D.new()
	ed.name = "Edificio"
	nav.add_child(ed)
	ed.rotation.y = yaw
	var w := 11.3      # de norte a sur
	var d := 17.4      # de oeste a este
	# casco: el frente (puerta y porche) mira al oeste, al camino
	var casco := Node3D.new()
	casco.position = Vector3(-d * 0.5, 0, 0)
	casco.rotation.y = -PI * 0.5
	ed.add_child(casco)
	var lining := ShaderMaterial.new()
	lining.shader = INTERIOR_SHADER
	lining.set_shader_parameter("noise_tex", town.noise_tex)
	lining.set_shader_parameter("upper", Color(0.82, 0.78, 0.7))
	lining.set_shader_parameter("lower", Color(0.3, 0.2, 0.13))
	lining.set_shader_parameter("dado_h", 1.1)
	Interiors.shell(casco, town, {"w": w, "d": d, "h": 4.6, "kind": 0, "style": 1, "tint": Color(0.86, 0.8, 0.68),
		"seed": 2, "windows": false, "lining": lining, "ceil_h": 3.2,
		"doors": [{"face": "front", "t0": w * 0.5 - 1.2, "t1": w * 0.5 + 1.2, "h": 2.7}]})
	var marble := ShaderMaterial.new()
	marble.shader = FLOOR_SHADER
	marble.set_shader_parameter("noise_tex", town.noise_tex)
	marble.set_shader_parameter("base", Color(0.62, 0.6, 0.57))
	marble.set_shader_parameter("tile", 0.6)
	var fm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w - 0.6, d - 0.6)
	fm.mesh = pm
	fm.material_override = marble
	fm.position = Vector3(0, 0.02, -d * 0.5)
	casco.add_child(fm)
	var brown := _soft(Color(0.38, 0.2, 0.12), 0.7, 2.0)
	var stone := _soft(Color(0.7, 0.62, 0.5), 0.9, 1.0)
	# zócalo de piedra y portones marrones al aparcamiento (lado sur = +X del casco)
	for zc in [-3.5, -8.7, -13.9]:
		L._box(casco, Vector3(w * 0.5 + 0.04, 1.35, zc), Vector3(0.08, 2.7, 3.6), brown)
		for k in 6:
			L._box(casco, Vector3(w * 0.5 + 0.09, 0.25 + k * 0.45, zc), Vector3(0.02, 0.03, 3.5), _m(Color(0.28, 0.14, 0.08)))
	L._box(casco, Vector3(w * 0.5 + 0.03, 0.3, -d * 0.5), Vector3(0.06, 0.6, d), stone)
	# porche con columnas y tejado de teja
	var post := _m(Color(0.88, 0.84, 0.75))
	for x in [-w * 0.5 + 0.4, -1.8, 1.8, w * 0.5 - 0.4]:
		_static_box(casco, Vector3(x, 1.5, 4.0), Vector3(0.4, 3.0, 0.4), post)
	L._box(casco, Vector3(0, 3.1, 2.15), Vector3(w + 0.4, 0.25, 4.6), post)
	var roof := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(w + 1.0, 0.18, 5.2)
	roof.mesh = rb
	roof.material_override = town.roof_mat
	roof.position = Vector3(0, 3.55, 2.2)
	roof.rotation.x = 0.22
	casco.add_child(roof)
	_plane(casco, Vector3(0, 0.03, 2.2), Vector2(w, 4.4), marble)
	var plaque := L._box(casco, Vector3(0, 3.0, 0.42), Vector3(2.4, 0.3, 0.05), stone)
	L._label(plaque, "TANATORIO", Vector3(0, 0, 0.03), 44, Color(0.2, 0.15, 0.1), 0.0045)
	# ---- interior: sala sobria, bancos, flores y luz tenue
	var wood := _soft(Color(0.28, 0.17, 0.1), 0.6, 2.0)
	for zc in [-3.0, -6.0, -9.0]:
		for side in [-1.0, 1.0]:
			_static_box(casco, Vector3(side * 3.0, 0.24, zc), Vector3(2.2, 0.48, 0.5), wood)
			L._box(casco, Vector3(side * 3.0, 0.75, zc - 0.22), Vector3(2.2, 0.55, 0.06), wood)
	var flowers := [Color(0.95, 0.95, 0.9), Color(0.85, 0.15, 0.2), Color(0.95, 0.85, 0.3), Color(0.7, 0.4, 0.8)]
	for p in [Vector3(-4.6, 0, -15.8), Vector3(4.6, 0, -15.8), Vector3(-4.8, 0, -1.2), Vector3(4.8, 0, -1.2)]:
		L._cyl(casco, p + Vector3(0, 0.4, 0), 0.22, 0.16, 0.8, _m(Color(0.3, 0.3, 0.32), 0.4, 0.4))
		for k in 7:
			var fl := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.12
			sm.height = 0.22
			fl.mesh = sm
			fl.material_override = _m(flowers[k % flowers.size()], 0.8)
			fl.position = p + Vector3(rng.randf_range(-0.22, 0.22), 0.95 + rng.randf() * 0.3, rng.randf_range(-0.22, 0.22))
			casco.add_child(fl)
	# atril con el libro de firmas
	L._box(casco, Vector3(-3.6, 0.55, -1.6), Vector3(0.1, 1.1, 0.1), wood)
	var book := L._box(casco, Vector3(-3.6, 1.12, -1.6), Vector3(0.5, 0.05, 0.38), _m(Color(0.9, 0.88, 0.82)))
	book.rotation.x = -0.3
	# cortinas granates al fondo
	L._box(casco, Vector3(0, 1.6, -d + 0.36), Vector3(w - 1.0, 3.0, 0.08), _soft(Color(0.32, 0.05, 0.07), 0.95, 3.0))
	for x in [-3.5, 3.5]:
		var sc := L._box(casco, Vector3(x, 2.2, -d + 0.42), Vector3(0.25, 0.3, 0.12), _m(Color(0.95, 0.75, 0.45)))
		sc.name = "aplique"
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.7, 0.4)
		l.light_energy = 0.7
		l.omni_range = 6.0
		l.position = Vector3(x, 2.2, -d + 1.0)
		casco.add_child(l)
	var lc := OmniLight3D.new()
	lc.light_color = Color(0.85, 0.85, 0.95)
	lc.light_energy = 0.45
	lc.omni_range = 9.0
	lc.position = Vector3(0, 2.9, -6.0)
	casco.add_child(lc)
	town.lamps.append({"light": lc, "base": 0.45, "mode": "dying", "speed": 9.0})
	# el Pack-a-Punch, al fondo de la sala
	var pap := PackAPunch.new()
	pap.add_to_group("pack_a_punch")
	casco.add_child(pap)
	pap.position = Vector3(0, 0, -d + 2.0)


func _plane(parent: Node3D, center: Vector3, size: Vector2, mat: Material) -> void:
	var pm := PlaneMesh.new()
	pm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = mat
	mi.position = center
	parent.add_child(mi)


func _m(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


# ---------------------------------------------------------------- límites, árboles y farolas

func _bounds() -> void:
	var r := PLAY
	# muros invisibles (más vegetación delante para que no se note)
	_static_box(nav, Vector3(r.position.x - 0.5, 3, r.get_center().y), Vector3(1, 6, r.size.y + 2))
	_static_box(nav, Vector3(r.end.x + 0.5, 3, r.get_center().y), Vector3(1, 6, r.size.y + 2))
	_static_box(nav, Vector3(r.get_center().x, 3, r.end.y + 0.5), Vector3(r.size.x + 2, 6, 1))
	_static_box(nav, Vector3(r.get_center().x, 3, r.position.y - 0.5), Vector3(r.size.x + 2, 6, 1))
	# tapias bajas de piedra a los lados
	_stone_wall(Vector2(r.end.x, -9.0), Vector2(r.end.x, r.end.y), 1.6)
	_stone_wall(Vector2(r.position.x, -4.5), Vector2(r.position.x, r.end.y), 1.6)
	# el camino sigue al sur: coches abandonados
	var rb := StaticBody3D.new()
	rb.position = Vector3(-21.0, 0, r.end.y - 1.0)
	nav.add_child(rb)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(10.0, 3.0, 1.4)
	cs.shape = sh
	cs.position.y = 1.5
	rb.add_child(cs)
	load("res://scripts/zones.gd").build_rubble_visual(rb, rng, 10.0, town)


func _cypress(pos: Vector3, h: float) -> void:
	var dark := _m(Color(0.07, 0.16, 0.08), 0.95)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.9
	cm.height = h
	cm.radial_segments = 8
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = dark
	mi.position = pos + Vector3(0, h * 0.5 + 0.4, 0)
	mi.scale = Vector3(1.0, 1.0, 1.0)
	nav.add_child(mi)


func _leafy(pos: Vector3) -> void:
	var trunk := _m(Color(0.25, 0.18, 0.12), 0.95)
	var leaves := _m(Color(0.16, 0.3, 0.12), 0.95)
	var h := rng.randf_range(3.5, 5.0)
	var body := StaticBody3D.new()
	body.position = pos
	nav.add_child(body)
	L._cyl(body, Vector3(0, h * 0.5, 0), 0.12, 0.2, h, trunk)
	for k in 5:
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = rng.randf_range(1.0, 1.6)
		sm.height = sm.radius * 1.7
		sm.radial_segments = 10
		sm.rings = 6
		s.mesh = sm
		s.material_override = leaves
		s.position = Vector3(rng.randf_range(-0.9, 0.9), h + rng.randf_range(-0.3, 1.2), rng.randf_range(-0.9, 0.9))
		body.add_child(s)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.25
	sh.height = h
	cs.shape = sh
	cs.position.y = h * 0.5
	body.add_child(cs)


func _greenery() -> void:
	# alineación de árboles junto al camino y cipreses en los bordes
	var z := -2.0
	while z < PLAY.end.y:
		_leafy(Vector3(-31.0 + rng.randf_range(-0.5, 0.5), 0, z))
		z += rng.randf_range(6.0, 8.0)
	for p in [Vector3(22.0, 0, 3.0), Vector3(24.0, 0, 18.0), Vector3(21.5, 0, 47.0), Vector3(-15.0, 0, 48.5), Vector3(12.0, 0, 48.0)]:
		_cypress(p, rng.randf_range(6.0, 9.0))
	# fuera de la zona jugable: monte con pinos para cerrar la vista
	for k in 60:
		var a := rng.randf() * TAU
		var r := rng.randf_range(50.0, 110.0)
		var p := Vector3(sin(a) * r, 0, 25.0 + cos(a) * r)
		if p.z < -12.0 and absf(p.x) < 35.0:
			continue   # nada sobre el cementerio
		if rng.randf() < 0.5:
			_cypress(p, rng.randf_range(9.0, 15.0))
		else:
			_leafy(p)
	# arbustos redondos como en la foto
	var shrub := _m(Color(0.14, 0.28, 0.12), 0.95)
	for k in 14:
		var p := Vector3(rng.randf_range(-20.0, 20.0), 0.35, rng.randf_range(9.0, 12.0) if k % 2 == 0 else rng.randf_range(44.0, 46.0))
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.45
		sm.height = 0.8
		s.mesh = sm
		s.material_override = shrub
		s.position = p
		nav.add_child(s)


func _lamps() -> void:
	var iron := _m(Color(0.04, 0.04, 0.05), 0.5, 0.5)
	var i := 0
	for p in [Vector3(-27.0, 0, 4.0), Vector3(-27.0, 0, 26.0), Vector3(-20.0, 0, 44.0), Vector3(16.0, 0, 12.0), Vector3(16.0, 0, 38.0), Vector3(-14.0, 0, 14.0)]:
		L._cyl(nav, p + Vector3(0, 1.9, 0), 0.05, 0.09, 3.8, iron)
		var lan := MeshInstance3D.new()
		lan.mesh = town._lantern_mesh()
		lan.set_surface_override_material(0, town.glass_mat)
		lan.set_surface_override_material(1, iron)
		lan.position = p + Vector3(0, 3.9, 0)
		nav.add_child(lan)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.72, 0.42)
		l.light_energy = 1.3
		l.omni_range = 11.0
		l.position = p + Vector3(0, 3.8, 0)
		nav.add_child(l)
		if i == 2 or i == 4:
			town.lamps.append({"light": l, "base": 1.3, "mode": "flicker" if i == 2 else "dying", "speed": 13.0})
		i += 1


## Niebla baja: grandes copos translúcidos que se arrastran por el suelo
func _mist() -> void:
	var p := CPUParticles3D.new()
	p.amount = 70
	p.lifetime = 14.0
	p.preprocess = 14.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(PLAY.size.x * 0.5 + 6.0, 0.4, PLAY.size.y * 0.5 + 6.0)
	p.position = Vector3(PLAY.get_center().x, 0.8, PLAY.get_center().y)
	p.direction = Vector3(1, 0, 0.3)
	p.spread = 30.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.7
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.4
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = gt
	mat.albedo_color = Color(0.75, 0.8, 0.88, 0.16)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var qm := QuadMesh.new()
	qm.size = Vector2(7.0, 3.0)
	qm.material = mat
	p.mesh = qm
	add_child(p)


# ---------------------------------------------------------------- zombies y navegación

func _spawns() -> void:
	var x := PLAY.position.x + 3.0
	while x < PLAY.end.x - 2.0:
		var z := PLAY.position.y + 4.0
		while z < PLAY.end.y - 2.0:
			var p := Vector2(x, z)
			if not _blocked(p):
				town.spawn_points.append(position + Vector3(p.x, 0.05, p.y))
				town.spawn_zones.append("tanatorio")
			z += 7.0
		x += 7.0


func _blocked(p: Vector2) -> bool:
	# edificio (con porche) y su entorno
	return Rect2(-16.0, -8.0, 27.0, 16.0).has_point(p)


func _bake() -> void:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.25
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nm.geometry_collision_mask = 0xFFFFFFFF & ~16
	nm.filter_baking_aabb = AABB(Vector3(PLAY.position.x - 2.0, -1.5, PLAY.position.y - 2.0),
		Vector3(PLAY.size.x + 4.0, 4.1, PLAY.size.y + 4.0))
	nav.navigation_mesh = nm
	nav.bake_navigation_mesh(false)


## ¿Está este punto (global) dentro del nivel del tanatorio?
func contains(p: Vector3) -> bool:
	var lp := p - position
	return absf(lp.x) < 200.0 and absf(lp.z) < 200.0
