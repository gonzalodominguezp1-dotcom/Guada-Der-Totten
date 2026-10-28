extends Node3D
## Bar Restaurante Chiqui — Av. Alejandro Rubio 14, a la escala del edificio
## de OpenStreetMap (unos 15 m de frente y 22 m de fondo). Todo el bar es la
## zona de inicio; la única salida a la calle es la verja de la terraza
## delantera (se compra). Los zombies entran por las ventanas del perímetro.
##
##   z=-21.5 ┌─────── terraza trasera (charanga) ────────┬──────┐
##           │ W5                     W4                 │      │
##   z=-14   ├─ cocina ─┬─── barra ───┬── comedor ───────┤pasillo
##           │  aseos   │             │  (inicio)    W6→ │lateral
##   z=-5  ┌─┴──────────┴──── terraza delantera ─────────┘      └──┐
##         │ W3                                                     │
##   z=0   └──── W1 ──────────── [ VERJA ] ───────────── W2 ────────┘
##        x=-7.5   -6.5                                4    6      7.5
##                       Avenida Alejandro Rubio (+Z)

const FACADE_SHADER = preload("res://shaders/facade.gdshader")
const INTERIOR_SHADER = preload("res://shaders/interior_wall.gdshader")
const FLOOR_SHADER = preload("res://shaders/terracotta_floor.gdshader")
const CLOTH_SHADER = preload("res://shaders/tablecloth.gdshader")
const GRILLE_SHADER = preload("res://shaders/grille.gdshader")
const Barricade = preload("res://scripts/barricade.gd")
const BuyDoor = preload("res://scripts/buy_door.gd")
const PerkMachine = preload("res://scripts/perk_machine.gd")
const WallWeapon = preload("res://scripts/wall_weapon.gd")

# planta (coordenadas locales, metros)
const FX0 := -7.5      # terraza delantera
const FX1 := 7.5
const MX0 := -6.5      # bloque principal (comedor y terraza trasera)
const MX1 := 4.0
const CX1 := 6.0       # pasillo lateral: de MX1 a CX1
const Z_TERRACE := -5.0
const Z_BACK := -14.0
const Z_END := -21.5
const ROOF_Y := 2.85
const CEIL_Y := 3.0
const SPLIT_X := -3.5  # tabique de cocina y aseos
const COUNTER_X := -2.55

var town
var player_start := Vector3.ZERO
var player_start_yaw := 0.0
var barricades: Array = []
var window_spawners: Array = []   # {pos: Vector3, barricade}
var doors: Array = []
var fans: Array = []
var flicker_lights: Array = []

var m_interior: ShaderMaterial
var m_floor: ShaderMaterial
var m_cloth: ShaderMaterial
var m_grille: ShaderMaterial
var m_facade: ShaderMaterial
var m_red: StandardMaterial3D
var m_wood: StandardMaterial3D
var m_dark_wood: StandardMaterial3D
var m_plaster: StandardMaterial3D
var m_metal: StandardMaterial3D
var m_chrome: StandardMaterial3D
var m_yellow: StandardMaterial3D
var m_clay: StandardMaterial3D
var m_brass: StandardMaterial3D
var m_black: StandardMaterial3D
var m_marble: StandardMaterial3D
var m_glass: StandardMaterial3D
var rng := RandomNumberGenerator.new()

# ventanas con barricada: [nombre, pared a, pared b, t0, t1, normal hacia fuera]
var window_defs := {}


func build(t) -> void:
	town = t
	rng.seed = 77
	_materials()
	_plan_windows()
	_floors()
	_front_terrace()
	_interior()
	_bar_counter()
	_dining()
	_back_terrace()
	_corridor()
	_upper_floor()
	_gameplay()
	player_start = to_global(Vector3(0.2, 0.05, -9.5))
	player_start_yaw = rotation.y + PI


func _process(delta: float) -> void:
	for f in fans:
		f.rotate_y(delta * 3.5)
	for l in flicker_lights:
		var light: OmniLight3D = l["light"]
		light.light_energy = l["base"] * (0.2 if randf() < 0.04 else 1.0)


# ---------------------------------------------------------------- materiales

func _materials() -> void:
	var noise: Texture2D = town.noise_tex
	var soft: Texture2D = town.soft_noise
	m_interior = ShaderMaterial.new()
	m_interior.shader = INTERIOR_SHADER
	m_interior.set_shader_parameter("noise_tex", noise)
	m_floor = ShaderMaterial.new()
	m_floor.shader = FLOOR_SHADER
	m_floor.set_shader_parameter("noise_tex", noise)
	m_cloth = ShaderMaterial.new()
	m_cloth.shader = CLOTH_SHADER
	m_grille = ShaderMaterial.new()
	m_grille.shader = GRILLE_SHADER
	m_facade = ShaderMaterial.new()
	m_facade.shader = FACADE_SHADER
	m_facade.set_shader_parameter("noise_tex", noise)
	m_red = _m(Color(0.55, 0.06, 0.05), 0.5)
	m_wood = _m(Color(0.40, 0.24, 0.13), 0.6, soft, 2.0)
	m_dark_wood = _m(Color(0.20, 0.12, 0.07), 0.7, soft, 2.0)
	m_plaster = _m(Color(0.80, 0.77, 0.70), 0.95, soft, 0.5)
	m_metal = _m(Color(0.55, 0.56, 0.58), 0.4)
	m_metal.metallic = 0.7
	m_chrome = _m(Color(0.85, 0.86, 0.88), 0.15)
	m_chrome.metallic = 1.0
	m_yellow = _m(Color(0.95, 0.70, 0.08), 0.6)
	m_clay = _m(Color(0.62, 0.24, 0.12), 0.8, soft, 1.5)
	m_brass = _m(Color(0.85, 0.65, 0.25), 0.25)
	m_brass.metallic = 1.0
	m_black = _m(Color(0.04, 0.04, 0.045), 0.6)
	m_marble = _m(Color(0.62, 0.60, 0.57), 0.25, soft, 3.0)
	m_glass = StandardMaterial3D.new()
	m_glass.albedo_color = Color(0.7, 0.85, 0.9, 0.18)
	m_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m_glass.roughness = 0.05


func _m(c: Color, rough: float, tex: Texture2D = null, tri: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if tex:
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * tri
	return m


# ---------------------------------------------------------------- utilidades

func _mesh(mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	(parent if parent else self).add_child(mi)
	return mi


func _box(center: Vector3, size: Vector3, mat: Material, collide := true, parent: Node3D = null) -> Node3D:
	var bm := BoxMesh.new()
	bm.size = size
	if not collide:
		return _mesh(bm, mat, center, Vector3.ZERO, parent)
	var body := StaticBody3D.new()
	body.position = center
	(parent if parent else self).add_child(body)
	_mesh(bm, mat, Vector3.ZERO, Vector3.ZERO, body)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	return body


func _cyl(center: Vector3, r_top: float, r_bot: float, h: float, mat: Material, rot := Vector3.ZERO,
		seg := 16, parent: Node3D = null) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = seg
	cm.rings = 1
	return _mesh(cm, mat, center, rot, parent)


## Pared recta de (a) a (b) en planta [x, z], con huecos [t0, t1, y0, y1]
func _wall(a: Vector2, b: Vector2, y0: float, y1: float, thick: float, mat: Material, holes: Array = []) -> void:
	var L := a.distance_to(b)
	var dir := (b - a) / L
	var rot_y := atan2(-dir.y, dir.x)
	var sorted := holes.duplicate()
	sorted.sort_custom(func(p, q): return p[0] < q[0])
	var pieces: Array = []
	var t := 0.0
	for hl in sorted:
		if hl[0] > t:
			pieces.append([t, hl[0], y0, y1])
		if hl[2] > y0:
			pieces.append([hl[0], hl[1], y0, hl[2]])
		if hl[3] < y1:
			pieces.append([hl[0], hl[1], hl[3], y1])
		t = hl[1]
	if t < L:
		pieces.append([t, L, y0, y1])
	for pc in pieces:
		var mid: Vector2 = a + dir * (pc[0] + pc[1]) * 0.5
		var size := Vector3(pc[1] - pc[0], pc[3] - pc[2], thick)
		if size.x < 0.01 or size.y < 0.01:
			continue
		var body := _box(Vector3(mid.x, (pc[2] + pc[3]) * 0.5, mid.y), size, mat)
		body.rotation.y = rot_y


## Muro de terraza: murete de granito + ventanal con reja y marcos rojos.
## gaps: [[t0, t1, "gate"|"window"], ...] medidos en metros desde a.
func _terrace_wall(a: Vector2, b: Vector2, gaps: Array = []) -> void:
	var L := a.distance_to(b)
	var dir := (b - a) / L
	var rot_y := atan2(-dir.y, dir.x)
	var sorted := gaps.duplicate()
	sorted.sort_custom(func(p, q): return p[0] < q[0])
	var low_spans: Array = []
	var grille_spans: Array = []
	var t := 0.0
	for g in sorted:
		if g[0] > t:
			low_spans.append([t, g[0]])
			grille_spans.append([t, g[0]])
		if g[2] == "window":
			low_spans.append([g[0], g[1]])
		t = g[1]
	if t < L:
		low_spans.append([t, L])
		grille_spans.append([t, L])
	for sp in low_spans:
		if sp[1] - sp[0] > 0.05:
			_stone_wall(a + dir * sp[0], a + dir * sp[1], 0.0, 0.9, 0.34)
	for sp in grille_spans:
		var s0: float = sp[0]
		var s1: float = sp[1]
		var w := s1 - s0
		if w < 0.05:
			continue
		var mid: Vector2 = a + dir * (s0 + s1) * 0.5
		var body := StaticBody3D.new()
		body.position = Vector3(mid.x, 1.75, mid.y)
		body.rotation.y = rot_y
		add_child(body)
		var qm := QuadMesh.new()
		qm.size = Vector2(w, 1.7)
		var g := _mesh(qm, m_grille, Vector3.ZERO, Vector3.ZERO, body)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(w, 1.7, 0.1)
		cs.shape = shape
		body.add_child(cs)
		var n := maxi(1, int(round(w / 1.6)))
		for k in n + 1:
			var p: Vector2 = a + dir * (s0 + w * k / n)
			var post := _box(Vector3(p.x, 1.75, p.y), Vector3(0.12, 1.7, 0.16), m_red, false)
			post.rotation.y = rot_y
	# dintel rojo corrido
	var mid_all := (a + b) * 0.5
	var beam := _box(Vector3(mid_all.x, 2.73, mid_all.y), Vector3(L + 0.1, 0.24, 0.2), m_red, false)
	beam.rotation.y = rot_y


## Muro con el shader de fachada (granito u otro tipo), UV en metros
func _stone_wall(a: Vector2, b: Vector2, y0: float, y1: float, thick: float, kind := 1, windows := false,
		tint := Color(0.9, 0.8, 0.55)) -> void:
	var L := a.distance_to(b)
	var dir := (b - a) / L
	var n := Vector2(-dir.y, dir.x)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := tint
	col.a = float(kind * 64 + 5) / 255.0
	var uv2 := Vector2(L if windows else 0.0, y1)
	var ht := thick * 0.5
	for side in [1.0, -1.0]:
		var o: Vector2 = n * ht * side
		var p0 := a + o
		var p1 := b + o
		var nrm := Vector3(n.x * side, 0, n.y * side)
		town._quad(st, Vector3(p0.x, y0, p0.y), Vector3(p1.x, y0, p1.y), Vector3(p1.x, y1, p1.y), Vector3(p0.x, y1, p0.y),
			Vector2(0, y0), Vector2(L, y0), Vector2(L, y1), Vector2(0, y1), nrm, uv2, col)
	var c0 := a + n * ht
	var c1 := b + n * ht
	var c2 := b - n * ht
	var c3 := a - n * ht
	town._quad(st, Vector3(c0.x, y1, c0.y), Vector3(c1.x, y1, c1.y), Vector3(c2.x, y1, c2.y), Vector3(c3.x, y1, c3.y),
		Vector2(0, 0), Vector2(L, 0), Vector2(L, thick), Vector2(0, thick), Vector3.UP, Vector2.ZERO, col)
	for e in [[a, -1.0], [b, 1.0]]:
		var p: Vector2 = e[0]
		var s: float = e[1]
		var q0 := p + n * ht
		var q1 := p - n * ht
		town._quad(st, Vector3(q0.x, y0, q0.y), Vector3(q1.x, y0, q1.y), Vector3(q1.x, y1, q1.y), Vector3(q0.x, y1, q0.y),
			Vector2(0, y0), Vector2(thick, y0), Vector2(thick, y1), Vector2(0, y1), Vector3(dir.x * s, 0, dir.y * s), Vector2(0, y1), col)
	var mesh := st.commit()
	var body := StaticBody3D.new()
	add_child(body)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m_facade
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_convex_shape() if absf(y1 - y0) < 1.5 else mesh.create_trimesh_shape()
	body.add_child(cs)


func _light(pos: Vector3, color: Color, energy: float, rng_m: float, shadow := false, flicker := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng_m
	l.omni_attenuation = 1.2
	l.shadow_enabled = shadow
	add_child(l)
	if flicker:
		flicker_lights.append({"light": l, "base": energy})
	return l


func _pendant(pos: Vector3, shade: Material, energy: float, rng_m: float, flicker := false) -> void:
	_cyl(Vector3(pos.x, (CEIL_Y + pos.y) * 0.5 + 0.1, pos.z), 0.006, 0.006, CEIL_Y - pos.y - 0.2, m_black, Vector3.ZERO, 4)
	_cyl(pos + Vector3(0, 0.1, 0), 0.06, 0.24, 0.2, shade, Vector3.ZERO, 16)
	var bulb := SphereMesh.new()
	bulb.radius = 0.05
	bulb.height = 0.1
	var bm := StandardMaterial3D.new()
	bm.emission_enabled = true
	bm.emission = Color(1.0, 0.75, 0.45)
	bm.emission_energy_multiplier = 5.0
	_mesh(bulb, bm, pos)
	_light(pos - Vector3(0, 0.15, 0), Color(1.0, 0.72, 0.45), energy, rng_m, false, flicker)


func _label(text: String, pos: Vector3, rot_y: float, size: int, color: Color, px := 0.006, outline := 8) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = px
	l.modulate = color
	l.outline_size = outline
	l.outline_modulate = Color(0, 0, 0, 0.6)
	l.position = pos
	l.rotation.y = rot_y
	l.double_sided = false
	add_child(l)
	return l


## Ventana decorativa (cristal y marco) sobre una pared maciza
func _deco_window(center: Vector3, rot_y: float, w: float, h: float) -> void:
	var f := _box(center, Vector3(w + 0.14, h + 0.14, 0.26), m_dark_wood, false)
	f.rotation.y = rot_y
	_box(Vector3(0, 0, 0), Vector3(w, h, 0.27), _m(Color(0.03, 0.04, 0.05), 0.05), false, f)
	_box(Vector3(0, 0, 0), Vector3(0.05, h, 0.28), m_dark_wood, false, f)


# ---------------------------------------------------------------- ventanas

func _plan_windows() -> void:
	# Ventanas candidatas del perímetro. Se descartan las que dan contra
	# otra casa (no habría sitio por donde lleguen los zombies).
	var cands := {
		"W1": [Vector2(FX0, 0), Vector2(FX1, 0), 2.1, 3.5, Vector3(0, 0, 1)],
		"W2": [Vector2(FX0, 0), Vector2(FX1, 0), 11.1, 12.5, Vector3(0, 0, 1)],
		"W3": [Vector2(FX0, Z_TERRACE), Vector2(FX0, 0), 2.0, 3.4, Vector3(-1, 0, 0)],
		"W4": [Vector2(MX0, Z_END), Vector2(CX1, Z_END), 4.5, 5.9, Vector3(0, 0, -1)],
		"W5": [Vector2(MX0, Z_BACK), Vector2(MX0, Z_END), 3.4, 4.8, Vector3(-1, 0, 0)],
		"W6": [Vector2(CX1, Z_TERRACE), Vector2(CX1, Z_END), 4.6, 6.0, Vector3(1, 0, 0)],
	}
	for k in cands:
		var c: Array = cands[k]
		var a: Vector2 = c[0]
		var b: Vector2 = c[1]
		var dir := (b - a).normalized()
		var mid: Vector2 = a + dir * (c[2] + c[3]) * 0.5
		var out: Vector3 = c[4]
		var ok := true
		for d in [1.0, 2.4]:
			var lp: Vector3 = Vector3(mid.x, 0, mid.y) + out * d
			var gp := to_global(lp)
			if _blocked(Vector2(gp.x, gp.z)):
				ok = false
		if ok:
			window_defs[k] = c


func _blocked(p: Vector2) -> bool:
	if not town.bounds.grow(-1.0).has_point(p):
		return true
	if town.is_inside_building(p, 0.5):
		return true
	for pf in town.prefabs:
		if pf["prefab"] != "bar_chiqui" and Geometry2D.is_point_in_polygon(p, pf["footprint"]):
			return true
	return false


func _gaps_for(a: Vector2, b: Vector2) -> Array:
	var out: Array = []
	for k in window_defs:
		var c: Array = window_defs[k]
		if c[0] == a and c[1] == b:
			out.append([c[2], c[3], "window"])
	return out


# ---------------------------------------------------------------- estructura

func _floors() -> void:
	var parts := [
		[Vector3((FX0 + FX1) * 0.5, 0.025, Z_TERRACE * 0.5), Vector2(FX1 - FX0, -Z_TERRACE)],
		[Vector3((MX0 + MX1) * 0.5, 0.025, (Z_TERRACE + Z_BACK) * 0.5), Vector2(MX1 - MX0, Z_TERRACE - Z_BACK)],
		[Vector3((MX0 + MX1) * 0.5, 0.025, (Z_BACK + Z_END) * 0.5), Vector2(MX1 - MX0, Z_BACK - Z_END)],
		[Vector3((MX1 + CX1) * 0.5, 0.025, (Z_TERRACE + Z_END) * 0.5), Vector2(CX1 - MX1, Z_TERRACE - Z_END)],
	]
	for p in parts:
		var pm := PlaneMesh.new()
		pm.size = p[1]
		_mesh(pm, m_floor, p[0])
	_box(Vector3(0, 0.02, 0.15), Vector3(2.2, 0.04, 0.3), town.curb_mat, false)


func _front_terrace() -> void:
	var front_a := Vector2(FX0, 0)
	var front_b := Vector2(FX1, 0)
	var gaps := _gaps_for(front_a, front_b)
	gaps.append([6.5, 8.5, "gate"])   # verja: x de -1 a 1
	_terrace_wall(front_a, front_b, gaps)
	_terrace_wall(Vector2(FX0, Z_TERRACE), Vector2(FX0, 0), _gaps_for(Vector2(FX0, Z_TERRACE), Vector2(FX0, 0)))
	_terrace_wall(Vector2(FX1, 0), Vector2(FX1, Z_TERRACE))
	# trozos de pared al fondo de la terraza fuera del bloque principal
	_wall(Vector2(FX0, Z_TERRACE), Vector2(MX0, Z_TERRACE), 0.0, ROOF_Y, 0.22, m_interior)
	_wall(Vector2(CX1, Z_TERRACE), Vector2(FX1, Z_TERRACE), 0.0, ROOF_Y, 0.22, m_interior)
	# tejadillo y vigas
	_box(Vector3(0, ROOF_Y + 0.07, Z_TERRACE * 0.5 + 0.1), Vector3(FX1 - FX0 + 0.5, 0.14, -Z_TERRACE + 0.5), m_plaster, false)
	for k in 8:
		var x := FX0 + 0.9 + k * 1.9
		_box(Vector3(x, ROOF_Y - 0.08, Z_TERRACE * 0.5), Vector3(0.12, 0.16, -Z_TERRACE), m_dark_wood, false)
	# letrero amarillo
	var sign_w := FX1 - FX0 + 0.4
	_box(Vector3(0, ROOF_Y + 0.55, 0.22), Vector3(sign_w, 0.95, 0.12), m_yellow, false)
	_box(Vector3(0, ROOF_Y + 0.04, 0.24), Vector3(sign_w, 0.07, 0.16), m_red, false)
	_box(Vector3(0, ROOF_Y + 1.04, 0.24), Vector3(sign_w, 0.07, 0.16), m_red, false)
	_label("BAR RESTAURANTE CHIQUI", Vector3(-1.0, ROOF_Y + 0.68, 0.29), 0.0, 96, Color(0.62, 0.07, 0.05), 0.0072, 0)
	_label("COMIDAS CASERAS · 91 847 10 57", Vector3(-1.0, ROOF_Y + 0.29, 0.29), 0.0, 52, Color(0.55, 0.06, 0.04), 0.0062, 0)
	_light(Vector3(0, ROOF_Y + 0.5, 1.4), Color(1.0, 0.85, 0.6), 1.2, 4.5)
	for x in [-1.55, 1.55]:
		_tinaja(Vector3(x, 0, 0.55))
	for p in [Vector2(-3.2, -3.3), Vector2(2.6, -3.4), Vector2(-5.7, -3.9), Vector2(6.3, -2.9)]:
		_table(Vector3(p.x, 0, p.y), 4)
	_fan(Vector3(-2.5, ROOF_Y - 0.1, -2.5))
	_fan(Vector3(3.8, ROOF_Y - 0.1, -2.5))
	_pendant(Vector3(0.0, 2.35, -2.5), m_red, 0.8, 6.5)
	_tinaja(Vector3(7.0, 0, -4.5), 0.7)


func _interior() -> void:
	# fachada interior (terraza → comedor): puerta abierta y ventana
	_wall(Vector2(MX0, Z_TERRACE), Vector2(MX1, Z_TERRACE), 0.0, CEIL_Y, 0.22, m_interior,
		[[5.9, 7.5, 0.0, 2.3]])
	_deco_window(Vector3(2.7, 1.5, Z_TERRACE), 0.0, 1.3, 1.1)
	_open_door(Vector3(1.0, 0, Z_TERRACE), 1.6, true)
	# pared trasera (comedor → terraza trasera): puerta abierta
	_wall(Vector2(MX0, Z_BACK), Vector2(MX1, Z_BACK), 0.0, CEIL_Y, 0.22, m_interior,
		[[5.9, 7.1, 0.0, 2.3]])
	_deco_window(Vector3(2.4, 1.5, Z_BACK), 0.0, 1.2, 1.1)
	_open_door(Vector3(0.6, 0, Z_BACK), 1.2, false)
	# pared del comedor al pasillo (maciza, con ventana decorativa)
	_wall(Vector2(MX1, Z_TERRACE), Vector2(MX1, Z_BACK), 0.0, CEIL_Y, 0.22, m_interior)
	_deco_window(Vector3(MX1, 1.5, -10.0), PI * 0.5, 1.2, 1.1)
	# medianera izquierda con piel exterior
	_wall(Vector2(MX0, Z_TERRACE), Vector2(MX0, Z_BACK), 0.0, CEIL_Y, 0.22, m_interior)
	_stone_wall(Vector2(MX0 - 0.13, Z_BACK), Vector2(MX0 - 0.13, Z_TERRACE), 0.0, CEIL_Y, 0.04, 0, false)
	# tabique cocina / aseos
	_wall(Vector2(SPLIT_X, Z_TERRACE), Vector2(SPLIT_X, Z_BACK), 0.0, CEIL_Y, 0.15, m_interior)
	_door_panel(Vector3(SPLIT_X + 0.09, 1.05, -5.9), PI * 0.5, 0.8, 2.1, m_dark_wood, "ASEOS")
	_door_panel(Vector3(SPLIT_X + 0.09, 1.05, -12.6), PI * 0.5, 0.9, 2.1, m_wood, "COCINA")
	# techo con vigas
	_box(Vector3((MX0 + MX1) * 0.5, CEIL_Y + 0.08, (Z_TERRACE + Z_BACK) * 0.5), Vector3(MX1 - MX0, 0.16, Z_TERRACE - Z_BACK), m_plaster, false)
	for k in 8:
		var z := Z_TERRACE - 0.6 - k * 1.15
		_box(Vector3((SPLIT_X + MX1) * 0.5, CEIL_Y - 0.09, z), Vector3(MX1 - SPLIT_X, 0.18, 0.14), m_dark_wood, false)
	# cuadros, reloj y tele
	_frame(Vector3(-0.9, 1.9, Z_BACK + 0.13), 0.0, Vector2(0.7, 0.5), Color(0.35, 0.42, 0.25))
	_frame(Vector3(MX1 - 0.14, 1.8, -12.0), -PI * 0.5, Vector2(0.5, 0.65), Color(0.5, 0.35, 0.2))
	_frame(Vector3(-1.2, 2.05, Z_TERRACE - 0.13), PI, Vector2(0.45, 0.35), Color(0.2, 0.25, 0.4))
	_clock(Vector3(1.6, 2.45, Z_BACK + 0.13), 0.0)
	_box(Vector3(MX1 - 0.15, 2.15, -7.2), Vector3(0.08, 0.62, 1.05), m_black, false)
	var screen := StandardMaterial3D.new()
	screen.albedo_color = Color(0.02, 0.03, 0.05)
	screen.emission_enabled = true
	screen.emission = Color(0.15, 0.25, 0.45)
	screen.emission_energy_multiplier = 0.6
	_box(Vector3(MX1 - 0.2, 2.15, -7.2), Vector3(0.01, 0.54, 0.96), screen, false)
	_light(Vector3(MX1 - 0.7, 2.1, -7.2), Color(0.45, 0.6, 1.0), 0.35, 3.0)
	_pendant(Vector3(1.4, 2.4, -7.3), m_red, 0.85, 6.5)
	_pendant(Vector3(1.4, 2.4, -11.5), m_red, 0.75, 6.5, true)


func _open_door(hinge: Vector3, width: float, double: bool) -> void:
	# hojas de puerta abiertas contra la pared (decorado)
	var leaves := 2 if double else 1
	var lw := width / leaves
	for i in leaves:
		var x := hinge.x - (width if i == 0 else 0.0)
		var side := 1.0 if i == 0 else -1.0
		var leaf := _box(Vector3(x - side * 0.05, 1.15, hinge.z - lw * 0.5 - 0.12), Vector3(0.05, 2.25, lw - 0.03),
			m_red if double else m_wood, false)
		if double:
			_box(Vector3(0, 0.25, 0), Vector3(0.06, 1.2, lw - 0.25), m_glass, false, leaf)


func _bar_counter() -> void:
	var z0 := -12.8
	var z1 := -6.6
	var zc := (z0 + z1) * 0.5
	var zl := z1 - z0
	_box(Vector3(COUNTER_X, 0.55, zc), Vector3(0.55, 1.1, zl), m_wood)
	_box(Vector3(COUNTER_X, 1.13, zc), Vector3(0.75, 0.06, zl + 0.1), m_marble, false)
	_box(Vector3(COUNTER_X + 0.28, 0.08, zc), Vector3(0.05, 0.16, zl), m_chrome, false)
	_box(Vector3(COUNTER_X - 0.05, 1.32, zc + 0.3), Vector3(0.5, 0.32, 3.4), m_glass, false)
	var cold := StandardMaterial3D.new()
	cold.albedo_color = Color(0.25, 0.28, 0.32)
	cold.emission_enabled = true
	cold.emission = Color(0.7, 0.85, 1.0)
	cold.emission_energy_multiplier = 0.25
	_box(Vector3(COUNTER_X - 0.05, 1.45, zc + 0.3), Vector3(0.4, 0.015, 3.2), cold, false)
	var tapas := [Color(0.85, 0.65, 0.25), Color(0.75, 0.25, 0.15), Color(0.9, 0.85, 0.7), Color(0.35, 0.5, 0.2)]
	for k in 7:
		_box(Vector3(COUNTER_X - 0.05, 1.2, zc - 1.2 + k * 0.45), Vector3(0.28, 0.04, 0.32), _m(tapas[k % tapas.size()], 0.5), false)
	_cyl(Vector3(COUNTER_X - 0.1, 1.35, -7.2), 0.03, 0.03, 0.4, m_chrome)
	_box(Vector3(COUNTER_X - 0.02, 1.52, -7.2), Vector3(0.16, 0.04, 0.04), m_chrome, false)
	for k in 6:
		var z := z0 + 0.4 + k * 1.1
		_cyl(Vector3(COUNTER_X + 0.75, 0.38, z), 0.025, 0.04, 0.76, m_chrome, Vector3.ZERO, 6)
		_cyl(Vector3(COUNTER_X + 0.75, 0.78, z), 0.19, 0.19, 0.07, m_red, Vector3.ZERO, 14)
	# trasera: mueble bajo, botelleros, cafetera
	var back_x := SPLIT_X + 0.38
	_box(Vector3(back_x, 0.47, -8.7), Vector3(0.6, 0.94, 3.6), m_dark_wood)
	_box(Vector3(back_x, 1.12, -8.0), Vector3(0.45, 0.4, 0.55), m_chrome, false)
	var bottle_cols := [Color(0.1, 0.35, 0.12, 0.8), Color(0.45, 0.25, 0.05, 0.8), Color(0.8, 0.85, 0.85, 0.6),
		Color(0.3, 0.05, 0.05, 0.8), Color(0.9, 0.7, 0.2, 0.7)]
	for shelf_y in [1.45, 1.85, 2.25]:
		var z_a := -11.0
		var z_b := -6.8
		_box(Vector3(SPLIT_X + 0.2, shelf_y, (z_a + z_b) * 0.5), Vector3(0.28, 0.03, z_b - z_a), m_dark_wood, false)
		var z := z_a + 0.12
		while z < z_b - 0.1:
			var c: Color = bottle_cols[rng.randi() % bottle_cols.size()]
			var bm := _m(c, 0.1)
			bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			var bh := rng.randf_range(0.24, 0.34)
			_cyl(Vector3(SPLIT_X + 0.22, shelf_y + bh * 0.5 + 0.015, z), 0.035, 0.04, bh, bm, Vector3.ZERO, 8)
			z += rng.randf_range(0.11, 0.16)
	for z in [-11.6, -9.3, -7.0]:
		_pendant(Vector3(COUNTER_X, 2.25, z), m_red, 0.5, 4.0)


func _dining() -> void:
	for p in [Vector2(1.9, -7.6), Vector2(3.1, -9.9), Vector2(1.9, -12.0)]:
		_table(Vector3(p.x, 0, p.y), 4)


func _back_terrace() -> void:
	var back_a := Vector2(MX0, Z_END)
	var back_b := Vector2(CX1, Z_END)
	_terrace_wall(back_a, back_b, _gaps_for(back_a, back_b))
	var left_a := Vector2(MX0, Z_BACK)
	var left_b := Vector2(MX0, Z_END)
	_terrace_wall(left_a, left_b, _gaps_for(left_a, left_b))
	_box(Vector3((MX0 + CX1) * 0.5, ROOF_Y + 0.07, (Z_BACK + Z_END) * 0.5), Vector3(CX1 - MX0 + 0.4, 0.14, Z_BACK - Z_END + 0.4), m_plaster, false)
	_drum_kit(Vector3(-4.2, 0, -20.2))
	_tuba(Vector3(1.6, 0, -20.7))
	_label("CHARANGA", Vector3(-4.2, 0.55, -19.78), 0.0, 40, Color(0.9, 0.9, 0.85), 0.004, 0)
	for k in 5:
		_chair(Vector3(-5.9, k * 0.09, -14.8), 0.0)
	_box(Vector3(3.0, 0.18, -21.0), Vector3(1.0, 0.36, 0.4), m_black)
	_box(Vector3(3.0, 0.5, -21.0), Vector3(0.8, 0.28, 0.35), m_black, false)
	_box(Vector3(-6.0, 0.35, -16.5), Vector3(0.35, 0.7, 0.6), m_dark_wood)
	_clock(Vector3(-1.0, 2.3, Z_END + 0.25), 0.0)
	_fan(Vector3(-1.0, ROOF_Y - 0.1, -17.7))
	_light(Vector3(-1.0, 2.5, -17.5), Color(0.75, 0.8, 1.0), 0.6, 7.0, false, true)


func _corridor() -> void:
	var out_a := Vector2(CX1, Z_TERRACE)
	var out_b := Vector2(CX1, Z_END)
	_terrace_wall(out_a, out_b, _gaps_for(out_a, out_b))
	_box(Vector3((MX1 + CX1) * 0.5, ROOF_Y - 0.03, (Z_TERRACE + Z_END) * 0.5), Vector3(CX1 - MX1 + 0.3, 0.14, Z_TERRACE - Z_END + 0.2), m_plaster, false)
	_light(Vector3(5.0, 2.45, -10.0), Color(1.0, 0.75, 0.5), 0.6, 6.0)
	_light(Vector3(5.0, 2.45, -17.0), Color(1.0, 0.75, 0.5), 0.45, 5.0, false, true)


func _upper_floor() -> void:
	var x0 := MX0 - 0.1
	var x1 := MX1 + 0.1
	var z0 := Z_BACK - 0.1
	var z1 := Z_TERRACE + 0.1
	var top := 6.1
	var tint := Color(0.93, 0.80, 0.50)
	_stone_wall(Vector2(x0, z1), Vector2(x1, z1), CEIL_Y, top, 0.2, 0, true, tint)
	_stone_wall(Vector2(x1, z0), Vector2(x0, z0), CEIL_Y, top, 0.2, 0, true, tint)
	_stone_wall(Vector2(x0, z0), Vector2(x0, z1), CEIL_Y, top, 0.2, 0, false, tint)
	_stone_wall(Vector2(x1, z1), Vector2(x1, z0), CEIL_Y, top, 0.2, 0, true, tint)
	var pts := PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])
	town._hip_roof(self, pts, top, false)
	_box(Vector3(-4.5, 7.4, -10.5), Vector3(0.7, 2.0, 0.7), _m(Color(0.6, 0.3, 0.2), 0.9, town.soft_noise, 2.0), false)
	_box(Vector3(-4.5, 8.45, -10.5), Vector3(0.9, 0.1, 0.9), m_plaster, false)
	var lantern_pos := Vector3(MX1 - 0.4, 4.3, Z_TERRACE + 0.65)
	_box(lantern_pos + Vector3(0, 0.25, -0.3), Vector3(0.04, 0.04, 0.6), m_black, false)
	var lm: Mesh = town._lantern_mesh()
	var lmi := _mesh(lm, m_black, lantern_pos)
	lmi.set_surface_override_material(0, town.glass_mat)
	lmi.set_surface_override_material(1, m_black)
	_light(lantern_pos - Vector3(0, 0.1, -0.3), Color(1.0, 0.68, 0.38), 1.8, 9.0)


# ---------------------------------------------------------------- mobiliario

func _table(pos: Vector3, chairs: int) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	add_child(body)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.85, 0.8, 0.85)
	cs.shape = shape
	cs.position.y = 0.4
	body.add_child(cs)
	var cloth := BoxMesh.new()
	cloth.size = Vector3(0.95, 0.28, 0.95)
	_mesh(cloth, m_cloth, Vector3(0, 0.64, 0), Vector3(0, rng.randf_range(-0.1, 0.1), 0), body)
	_cyl(Vector3(0, 0.3, 0), 0.04, 0.04, 0.6, m_metal, Vector3.ZERO, 8, body)
	_cyl(Vector3(0, 0.02, 0), 0.25, 0.28, 0.04, m_metal, Vector3.ZERO, 12, body)
	_box(Vector3(0.1, 0.83, 0.05), Vector3(0.1, 0.08, 0.05), m_chrome, false, body)
	_cyl(Vector3(-0.2, 0.84, -0.1), 0.035, 0.03, 0.1, m_glass, Vector3.ZERO, 8, body)
	for k in chairs:
		var a := TAU * k / chairs + rng.randf_range(-0.2, 0.2)
		var cp := pos + Vector3(sin(a) * 0.72, 0, cos(a) * 0.72)
		if rng.randf() < 0.15:
			var c := _chair(cp, a)
			c.rotation.x = PI * 0.5
			c.position.y = 0.22
		else:
			_chair(cp, a)


func _chair(pos: Vector3, yaw: float) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = yaw
	add_child(n)
	_box(Vector3(0, 0.46, 0), Vector3(0.42, 0.04, 0.42), m_metal, false, n)
	_box(Vector3(0, 0.72, 0.19), Vector3(0.42, 0.5, 0.03), m_metal, false, n)
	for x in [-0.18, 0.18]:
		for z in [-0.18, 0.18]:
			_cyl(Vector3(x, 0.23, z), 0.012, 0.012, 0.46, m_metal, Vector3.ZERO, 4, n)
	return n


func _tinaja(pos: Vector3, s := 1.0) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	add_child(body)
	var sm := SphereMesh.new()
	sm.radius = 0.36 * s
	sm.height = 0.95 * s
	_mesh(sm, m_clay, Vector3(0, 0.48 * s, 0), Vector3.ZERO, body)
	_cyl(Vector3(0, 0.97 * s, 0), 0.17 * s, 0.14 * s, 0.12 * s, m_clay, Vector3.ZERO, 14, body)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.36 * s
	shape.height = 1.0 * s
	cs.shape = shape
	cs.position.y = 0.5 * s
	body.add_child(cs)


func _fan(pos: Vector3) -> void:
	_cyl(pos + Vector3(0, 0.05, 0), 0.02, 0.02, 0.15, m_dark_wood)
	var rotor := Node3D.new()
	rotor.position = pos - Vector3(0, 0.08, 0)
	add_child(rotor)
	_cyl(Vector3.ZERO, 0.1, 0.12, 0.1, m_brass, Vector3.ZERO, 12, rotor)
	for k in 4:
		var b := _box(Vector3(cos(TAU * k / 4) * 0.42, 0, sin(TAU * k / 4) * 0.42), Vector3(0.6, 0.012, 0.13), m_dark_wood, false, rotor)
		b.rotation.y = -TAU * k / 4
	fans.append(rotor)


func _door_panel(pos: Vector3, yaw: float, w: float, h: float, mat: Material, text: String) -> void:
	var d := _box(pos, Vector3(w, h, 0.05), mat, false)
	d.rotation.y = yaw
	var knob := _cyl(Vector3(w * 0.38, 0, 0.04), 0.03, 0.03, 0.05, m_brass, Vector3(PI * 0.5, 0, 0), 8, d)
	knob.position.y = -0.05
	var l := Label3D.new()
	l.text = text
	l.font_size = 40
	l.pixel_size = 0.004
	l.modulate = Color(0.9, 0.85, 0.7)
	l.position = Vector3(0, 0.55, 0.035)
	d.add_child(l)


func _frame(pos: Vector3, yaw: float, size: Vector2, c: Color) -> void:
	var f := _box(pos, Vector3(size.x + 0.08, size.y + 0.08, 0.03), m_dark_wood, false)
	f.rotation.y = yaw
	var pic := _m(c, 0.7, town.soft_noise, 4.0)
	_box(Vector3(0, 0, 0.017), Vector3(size.x, size.y, 0.005), pic, false, f)


func _clock(pos: Vector3, yaw: float) -> void:
	var face := _m(Color(0.92, 0.9, 0.82), 0.6)
	_cyl(pos + Vector3(0, 0, 0.01), 0.22, 0.22, 0.05, face, Vector3(PI * 0.5, yaw, 0), 24)
	_cyl(pos, 0.245, 0.245, 0.04, m_dark_wood, Vector3(PI * 0.5, yaw, 0), 24)
	var hand1 := _box(pos + Vector3(0.04, 0.05, 0.04), Vector3(0.02, 0.14, 0.005), m_black, false)
	hand1.rotation.z = -0.6
	var hand2 := _box(pos + Vector3(-0.05, -0.02, 0.04), Vector3(0.015, 0.18, 0.005), m_black, false)
	hand2.rotation.z = 1.9


func _drum_kit(pos: Vector3) -> void:
	var skin := _m(Color(0.9, 0.88, 0.8), 0.6)
	var shell := _m(Color(0.5, 0.05, 0.08), 0.3)
	_cyl(pos + Vector3(0, 0.3, 0), 0.3, 0.3, 0.4, shell, Vector3(PI * 0.5, 0, 0), 20)
	_cyl(pos + Vector3(0, 0.3, 0.205), 0.29, 0.29, 0.01, skin, Vector3(PI * 0.5, 0, 0), 20)
	_cyl(pos + Vector3(0.5, 0.62, 0.15), 0.18, 0.18, 0.14, shell)
	_cyl(pos + Vector3(-0.15, 0.72, 0.05), 0.14, 0.14, 0.16, shell, Vector3(0.3, 0, 0))
	_cyl(pos + Vector3(-0.6, 0.55, 0.1), 0.22, 0.22, 0.3, shell)
	for p in [Vector3(0.75, 1.05, -0.1), Vector3(-0.55, 1.2, -0.2)]:
		_cyl(pos + Vector3(p.x, p.y * 0.5, p.z), 0.01, 0.01, p.y, m_chrome, Vector3.ZERO, 4)
		_cyl(pos + p, 0.2, 0.2, 0.01, m_brass, Vector3(0.15, 0, 0.1), 20)
	var cs := StaticBody3D.new()
	cs.position = pos + Vector3(0, 0.4, 0)
	add_child(cs)
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(1.6, 0.8, 0.8)
	shape.shape = b
	cs.add_child(shape)


func _tuba(pos: Vector3) -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = 0.2
	tm.outer_radius = 0.3
	_mesh(tm, m_brass, pos + Vector3(0, 0.55, 0), Vector3(PI * 0.5, 0.3, 0))
	_cyl(pos + Vector3(0.1, 1.0, 0), 0.24, 0.07, 0.5, m_brass, Vector3(0, 0, -0.2), 20)
	_cyl(pos + Vector3(0, 0.25, 0), 0.12, 0.12, 0.5, m_black, Vector3.ZERO, 8)


# ---------------------------------------------------------------- jugabilidad

func _gameplay() -> void:
	for k in window_defs:
		var c: Array = window_defs[k]
		var a: Vector2 = c[0]
		var b: Vector2 = c[1]
		var dir := (b - a).normalized()
		var mid: Vector2 = a + dir * (c[2] + c[3]) * 0.5
		var out: Vector3 = c[4]
		var bar_c: Node3D = _add_barricade(Vector3(mid.x, 1.75, mid.y), out, c[3] - c[2])
		var side := Vector3(-out.z, 0, out.x)
		for s in [[2.3, 0.0], [3.6, 1.2], [3.6, -1.2]]:
			var lp: Vector3 = Vector3(mid.x, 0.05, mid.y) + out * s[0] + side * s[1]
			var gp := to_global(lp)
			if not _blocked(Vector2(gp.x, gp.z)):
				window_spawners.append({"pos": gp, "barricade": bar_c})
	# Verja a la avenida (la única salida)
	var gate := BuyDoor.new()
	gate.cost = 750
	gate.label = "abrir la verja del bar"
	gate.size = Vector3(2.0, 2.5, 0.08)
	gate.style = "gate"
	add_child(gate)
	gate.position = Vector3(0.0, 1.25, 0.0)
	gate.opened.connect(_on_door_opened)
	doors.append(gate)
	# Quick Revive, al fondo del comedor
	var qr := PerkMachine.new()
	qr.perk = "quick_revive"
	add_child(qr)
	qr.position = Vector3(MX1 - 0.55, 0.0, -12.9)
	qr.rotation.y = -PI * 0.5
	# Escopeta en la pared, junto a la entrada del comedor
	var ww := WallWeapon.new()
	ww.weapon_id = "escopeta"
	add_child(ww)
	ww.position = Vector3(-2.4, 1.45, Z_TERRACE - 0.12)
	ww.rotation.y = PI


func _add_barricade(center: Vector3, outward: Vector3, width: float):
	var b := Barricade.new()
	b.width = width
	b.height = 1.6
	add_child(b)
	b.position = center
	b.rotation.y = atan2(outward.x, outward.z)
	barricades.append(b)
	return b


func _on_door_opened(_door) -> void:
	town.open_exterior()


func is_inside_interior(world_pos: Vector3) -> bool:
	# todo el bar (terrazas, comedor y pasillo) cuenta como interior
	var p := to_local(world_pos)
	if p.z <= 0.0 and p.z >= Z_TERRACE and p.x >= FX0 and p.x <= FX1:
		return true
	return p.z < Z_TERRACE and p.z >= Z_END and p.x >= MX0 and p.x <= CX1
