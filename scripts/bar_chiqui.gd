extends Node3D
## Bar Restaurante Chiqui (Av. Alejandro Rubio), construido según el plano:
##
##   z = -16 ┌──────────── terraza trasera (instrumentos) ────┬──────┐
##           │                                                │      │
##   z = -12 ├── cocina ─┬──── barra ────┬─── comedor ────────┤pasillo
##           │  aseos    │               │  (zona de inicio)  │lateral
##   z =  -4 ├───────────┴──── terraza delantera (cubierta) ──┤      │
##   z =   0 └──────────────────── [ verja ] ─────────────────┴──────┘
##          x=-6                                              x=4    x=6
##                       Avenida Alejandro Rubio (+Z)
##
## Origen: centro del frente, a ras de suelo. +Z mira a la avenida.

const FACADE_SHADER = preload("res://shaders/facade.gdshader")
const INTERIOR_SHADER = preload("res://shaders/interior_wall.gdshader")
const FLOOR_SHADER = preload("res://shaders/terracotta_floor.gdshader")
const CLOTH_SHADER = preload("res://shaders/tablecloth.gdshader")
const GRILLE_SHADER = preload("res://shaders/grille.gdshader")
const Barricade = preload("res://scripts/barricade.gd")
const BuyDoor = preload("res://scripts/buy_door.gd")
const PerkMachine = preload("res://scripts/perk_machine.gd")
const WallWeapon = preload("res://scripts/wall_weapon.gd")

const XL := -6.0
const XM := 4.0
const XR := 6.0
const Z_TERRACE := -4.0
const Z_BACK := -12.0
const Z_END := -16.0
const ROOF_Y := 2.85
const CEIL_Y := 3.0

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


func build(t) -> void:
	town = t
	rng.seed = 77
	_materials()
	_floors()
	_front_terrace()
	_interior()
	_bar_counter()
	_dining()
	_back_terrace()
	_corridor()
	_upper_floor()
	_gameplay()
	player_start = to_global(Vector3(0.2, 0.05, -7.6))
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
## (t medido en metros desde a).
func _wall(a: Vector2, b: Vector2, y0: float, y1: float, thick: float, mat: Material, holes: Array = []) -> void:
	var L := a.distance_to(b)
	var dir := (b - a) / L
	var rot_y := atan2(-dir.y, dir.x)
	var cuts := [0.0]
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


## Muro bajo de granito + ventanal con reja blanca y marco rojo (terrazas)
func _terrace_wall(a: Vector2, b: Vector2, gate: Array = []) -> void:
	var L := a.distance_to(b)
	var dir := (b - a) / L
	var rot_y := atan2(-dir.y, dir.x)
	var spans: Array = []
	if gate.is_empty():
		spans.append([0.0, L])
	else:
		spans.append([0.0, gate[0]])
		spans.append([gate[1], L])
	for sp in spans:
		var s0: float = sp[0]
		var s1: float = sp[1]
		if s1 - s0 < 0.05:
			continue
		var pa := a + dir * s0
		var pb := a + dir * s1
		_stone_wall(pa, pb, 0.0, 0.9, 0.34)
		# ventanal: reja + cristal, con colisión
		var mid := (pa + pb) * 0.5
		var w := s1 - s0
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
		# montantes rojos
		var n := maxi(1, int(round(w / 1.6)))
		for k in n + 1:
			var p := pa + dir * (w * k / n)
			var post := _box(Vector3(p.x, 1.75, p.y), Vector3(0.12, 1.7, 0.16), m_red, false)
			post.rotation.y = rot_y
	# dintel rojo corrido (también sobre la verja)
	var mid_all := (a + b) * 0.5
	var beam := _box(Vector3(mid_all.x, 2.73, mid_all.y), Vector3(L + 0.1, 0.24, 0.2), m_red, false)
	beam.rotation.y = rot_y


## Muro con el shader de fachada (granito u otro tipo) y UV en metros
func _stone_wall(a: Vector2, b: Vector2, y0: float, y1: float, thick: float, kind := 1, windows := false,
		tint := Color(0.9, 0.8, 0.55)) -> void:
	var L := a.distance_to(b)
	var dir := (b - a) / L
	var n := Vector2(-dir.y, dir.x)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := tint
	col.a = float(kind * 64 + 21) / 255.0
	var uv2 := Vector2(L if windows else 0.0, y1)
	var ht := thick * 0.5
	for side in [1.0, -1.0]:
		var o: Vector2 = n * ht * side
		var p0 := a + o
		var p1 := b + o
		var nrm := Vector3(n.x * side, 0, n.y * side)
		town._quad(st, Vector3(p0.x, y0, p0.y), Vector3(p1.x, y0, p1.y), Vector3(p1.x, y1, p1.y), Vector3(p0.x, y1, p0.y),
			Vector2(0, y0), Vector2(L, y0), Vector2(L, y1), Vector2(0, y1), nrm, uv2, col)
	# coronación
	var c0 := a + n * ht
	var c1 := b + n * ht
	var c2 := b - n * ht
	var c3 := a - n * ht
	town._quad(st, Vector3(c0.x, y1, c0.y), Vector3(c1.x, y1, c1.y), Vector3(c2.x, y1, c2.y), Vector3(c3.x, y1, c3.y),
		Vector2(0, 0), Vector2(L, 0), Vector2(L, thick), Vector2(0, thick), Vector3.UP, Vector2.ZERO, col)
	# testeros
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


# ---------------------------------------------------------------- estructura

func _floors() -> void:
	var parts := [
		[Vector3((XL + XM) * 0.5, 0.025, Z_TERRACE * 0.5), Vector2(XM - XL, -Z_TERRACE)],
		[Vector3((XL + XM) * 0.5, 0.025, (Z_TERRACE + Z_BACK) * 0.5), Vector2(XM - XL, Z_TERRACE - Z_BACK)],
		[Vector3((XL + XM) * 0.5, 0.025, (Z_BACK + Z_END) * 0.5), Vector2(XM - XL, Z_BACK - Z_END)],
		[Vector3((XM + XR) * 0.5, 0.025, Z_END * 0.5), Vector2(XR - XM, -Z_END)],
	]
	for p in parts:
		var pm := PlaneMesh.new()
		pm.size = p[1]
		_mesh(pm, m_floor, p[0])
	# escalón de entrada / umbral de granito
	_box(Vector3(0, 0.02, 0.15), Vector3(1.8, 0.04, 0.3), town.curb_mat, false)


func _front_terrace() -> void:
	_terrace_wall(Vector2(XL, 0), Vector2(XM, 0), [5.1, 6.9])   # verja: x de -0.9 a 0.9
	_terrace_wall(Vector2(XL, Z_TERRACE), Vector2(XL, 0))
	# tejadillo de la terraza
	_box(Vector3((XL + XM) * 0.5 - 0.05, ROOF_Y + 0.07, Z_TERRACE * 0.5 + 0.1), Vector3(XM - XL + 0.5, 0.14, -Z_TERRACE + 0.5), m_plaster, false)
	# vigas de madera vistas
	for k in 6:
		var x := XL + 0.8 + k * 1.75
		_box(Vector3(x, ROOF_Y - 0.08, Z_TERRACE * 0.5), Vector3(0.12, 0.16, -Z_TERRACE), m_dark_wood, false)
	# letrero amarillo
	var sign_w := XM - XL + 0.4
	_box(Vector3((XL + XM) * 0.5, ROOF_Y + 0.55, 0.22), Vector3(sign_w, 0.95, 0.12), m_yellow, false)
	_box(Vector3((XL + XM) * 0.5, ROOF_Y + 0.04, 0.24), Vector3(sign_w, 0.07, 0.16), m_red, false)
	_box(Vector3((XL + XM) * 0.5, ROOF_Y + 1.04, 0.24), Vector3(sign_w, 0.07, 0.16), m_red, false)
	_label("BAR RESTAURANTE CHIQUI", Vector3((XL + XM) * 0.5, ROOF_Y + 0.68, 0.29), 0.0, 84, Color(0.62, 0.07, 0.05), 0.0068, 0)
	_label("COMIDAS CASERAS", Vector3((XL + XM) * 0.5, ROOF_Y + 0.29, 0.29), 0.0, 52, Color(0.55, 0.06, 0.04), 0.0062, 0)
	_light(Vector3((XL + XM) * 0.5, ROOF_Y + 0.5, 1.4), Color(1.0, 0.85, 0.6), 1.2, 4.0)
	# tinajas de barro a la entrada
	for x in [-1.45, 1.45]:
		_tinaja(Vector3(x, 0, 0.55))
	# mesas de la terraza
	for p in [Vector2(-4.4, -2.0), Vector2(-2.5, -2.9), Vector2(3.0, -1.5)]:
		_table(Vector3(p.x, 0, p.y), 4)
	# ventilador de techo y lámpara
	_fan(Vector3(-2.0, ROOF_Y - 0.1, -2.0))
	_pendant(Vector3(1.6, 2.35, -2.2), m_red, 0.8, 6.0)


func _interior() -> void:
	# fachada interior (terraza → comedor): puerta y ventana A
	_wall(Vector2(XL, Z_TERRACE), Vector2(XM, Z_TERRACE), 0.0, CEIL_Y, 0.22, m_interior,
		[[5.4, 7.0, 0.0, 2.3], [8.0, 9.4, 0.9, 2.1]])
	# pared trasera (comedor → terraza trasera): puerta y ventana C
	_wall(Vector2(XL, Z_BACK), Vector2(XM, Z_BACK), 0.0, CEIL_Y, 0.22, m_interior,
		[[5.4, 6.6, 0.0, 2.3], [7.6, 8.8, 0.9, 2.1]])
	# pared derecha (comedor → pasillo): ventana D
	_wall(Vector2(XM, Z_TERRACE), Vector2(XM, Z_BACK), 0.0, CEIL_Y, 0.22, m_interior,
		[[4.0, 5.2, 0.9, 2.1]])
	# pared izquierda (medianera) con piel exterior de enlucido
	_wall(Vector2(XL, Z_TERRACE), Vector2(XL, Z_BACK), 0.0, CEIL_Y, 0.22, m_interior)
	_stone_wall(Vector2(XL - 0.12, Z_BACK), Vector2(XL - 0.12, Z_TERRACE), 0.0, CEIL_Y, 0.04, 0, false)
	# pared derecha de la terraza delantera (separa del pasillo)
	_wall(Vector2(XM, 0.0), Vector2(XM, Z_TERRACE), 0.0, ROOF_Y, 0.2, m_interior)
	# tabique cocina/aseos (x = -3), con puertas cerradas
	_wall(Vector2(-3.0, Z_TERRACE), Vector2(-3.0, Z_BACK), 0.0, CEIL_Y, 0.15, m_interior)
	_door_panel(Vector3(-2.91, 1.05, -4.8), PI * 0.5, 0.8, 2.1, m_dark_wood, "ASEOS")
	_door_panel(Vector3(-2.91, 1.05, -9.6), PI * 0.5, 0.9, 2.1, m_wood, "COCINA")
	# techo con vigas
	_box(Vector3((XL + XM) * 0.5, CEIL_Y + 0.08, (Z_TERRACE + Z_BACK) * 0.5), Vector3(XM - XL, 0.16, Z_TERRACE - Z_BACK), m_plaster, false)
	for k in 7:
		var z := Z_TERRACE - 0.6 - k * 1.15
		_box(Vector3((-3.0 + XM) * 0.5, CEIL_Y - 0.09, z), Vector3(XM + 3.0, 0.18, 0.14), m_dark_wood, false)
	# cuadros, reloj y tele
	_frame(Vector3(-0.2, 1.9, -11.87), 0.0, Vector2(0.7, 0.5), Color(0.35, 0.42, 0.25))
	_frame(Vector3(3.86, 1.8, -10.4), -PI * 0.5, Vector2(0.5, 0.65), Color(0.5, 0.35, 0.2))
	_frame(Vector3(2.0, 2.05, -4.13), PI, Vector2(0.45, 0.35), Color(0.2, 0.25, 0.4))
	_clock(Vector3(1.0, 2.45, -11.87), 0.0)
	var tv := _box(Vector3(3.85, 2.15, -6.0), Vector3(0.08, 0.62, 1.05), m_black, false)
	var screen := StandardMaterial3D.new()
	screen.albedo_color = Color(0.02, 0.03, 0.05)
	screen.emission_enabled = true
	screen.emission = Color(0.15, 0.25, 0.45)
	screen.emission_energy_multiplier = 0.6
	_box(Vector3(3.80, 2.15, -6.0), Vector3(0.01, 0.54, 0.96), screen, false)
	_light(Vector3(3.3, 2.1, -6.0), Color(0.45, 0.6, 1.0), 0.35, 3.0)
	# luces del comedor (una parpadea)
	_pendant(Vector3(1.6, 2.4, -6.4), m_red, 0.85, 6.5)
	_pendant(Vector3(1.6, 2.4, -9.8), m_red, 0.75, 6.5, true)


func _bar_counter() -> void:
	# mostrador: frente de madera y encimera clara
	_box(Vector3(-1.3, 0.55, -8.3), Vector3(0.55, 1.1, 5.8), m_wood)
	_box(Vector3(-1.3, 1.13, -8.3), Vector3(0.75, 0.06, 5.9), m_marble, false)
	_box(Vector3(-1.02, 0.08, -8.3), Vector3(0.05, 0.16, 5.8), m_chrome, false)
	# vitrina refrigerada con tapas
	_box(Vector3(-1.35, 1.32, -8.0), Vector3(0.5, 0.32, 3.4), m_glass, false)
	var cold := StandardMaterial3D.new()
	cold.albedo_color = Color(0.25, 0.28, 0.32)
	cold.emission_enabled = true
	cold.emission = Color(0.7, 0.85, 1.0)
	cold.emission_energy_multiplier = 0.25
	_box(Vector3(-1.35, 1.45, -8.0), Vector3(0.4, 0.015, 3.2), cold, false)
	var tapas := [Color(0.85, 0.65, 0.25), Color(0.75, 0.25, 0.15), Color(0.9, 0.85, 0.7), Color(0.35, 0.5, 0.2)]
	for k in 7:
		_box(Vector3(-1.35, 1.2, -9.5 + k * 0.45), Vector3(0.3, 0.05, 0.36), _m(tapas[k % tapas.size()], 0.5), false)
	# grifo de cerveza
	_cyl(Vector3(-1.4, 1.35, -6.0), 0.03, 0.03, 0.4, m_chrome)
	_box(Vector3(-1.32, 1.52, -6.0), Vector3(0.16, 0.04, 0.04), m_chrome, false)
	# taburetes
	for k in 5:
		var z := -10.5 + k * 1.1
		_cyl(Vector3(-0.6, 0.38, z), 0.025, 0.04, 0.76, m_chrome, Vector3.ZERO, 6)
		_cyl(Vector3(-0.6, 0.78, z), 0.19, 0.19, 0.07, m_red, Vector3.ZERO, 14)
	# trasera: mueble bajo, botelleros, cafetera
	_box(Vector3(-2.65, 0.47, -7.1), Vector3(0.6, 0.94, 3.0), m_dark_wood)
	_box(Vector3(-2.65, 0.47, -11.1), Vector3(0.6, 0.94, 1.6), m_dark_wood)
	_box(Vector3(-2.65, 1.12, -6.6), Vector3(0.45, 0.4, 0.55), m_chrome, false)
	var bottle_cols := [Color(0.1, 0.35, 0.12, 0.8), Color(0.45, 0.25, 0.05, 0.8), Color(0.8, 0.85, 0.85, 0.6),
		Color(0.3, 0.05, 0.05, 0.8), Color(0.9, 0.7, 0.2, 0.7)]
	for shelf_y in [1.45, 1.85, 2.25]:
		for span in [[-8.6, -5.6], [-11.7, -10.3]]:
			var z0: float = span[0]
			var z1: float = span[1]
			_box(Vector3(-2.82, shelf_y, (z0 + z1) * 0.5), Vector3(0.28, 0.03, z1 - z0), m_dark_wood, false)
			var z := z0 + 0.12
			while z < z1 - 0.1:
				var c: Color = bottle_cols[rng.randi() % bottle_cols.size()]
				var bm := _m(c, 0.1)
				bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				var bh := rng.randf_range(0.24, 0.34)
				_cyl(Vector3(-2.8, shelf_y + bh * 0.5 + 0.015, z), 0.035, 0.04, bh, bm, Vector3.ZERO, 8)
				z += rng.randf_range(0.11, 0.16)
	_pendant(Vector3(-1.3, 2.25, -10.0), m_red, 0.5, 4.0)
	_pendant(Vector3(-1.3, 2.25, -7.6), m_red, 0.5, 4.0)
	_pendant(Vector3(-1.3, 2.25, -5.4), m_red, 0.5, 4.0)


func _dining() -> void:
	for p in [Vector2(1.7, -6.4), Vector2(3.2, -6.7), Vector2(1.75, -9.1)]:
		_table(Vector3(p.x, 0, p.y), 4)


func _back_terrace() -> void:
	_terrace_wall(Vector2(XL, Z_END), Vector2(XM, Z_END))
	_terrace_wall(Vector2(XL, Z_BACK), Vector2(XL, Z_END))
	_box(Vector3((XL + XR) * 0.5, ROOF_Y + 0.07, (Z_BACK + Z_END) * 0.5), Vector3(XR - XL + 0.4, 0.14, Z_BACK - Z_END + 0.4), m_plaster, false)
	# instrumentos de la charanga
	_drum_kit(Vector3(-4.2, 0, -14.6))
	_tuba(Vector3(-2.0, 0, -15.3))
	_label("CHARANGA", Vector3(-4.2, 0.55, -14.18), 0.0, 40, Color(0.9, 0.9, 0.85), 0.004, 0)
	# sillas apiladas y estuches
	for k in 5:
		_chair(Vector3(-5.3, k * 0.09, -12.7), 0.0)
	_box(Vector3(2.4, 0.18, -15.4), Vector3(1.0, 0.36, 0.4), m_black)
	_box(Vector3(2.4, 0.5, -15.4), Vector3(0.8, 0.28, 0.35), m_black, false)
	_box(Vector3(0.8, 0.35, -15.5), Vector3(0.6, 0.7, 0.35), m_dark_wood)
	_clock(Vector3(0.0, 2.3, -15.8), 0.0)
	_light(Vector3(-1.0, 2.5, -14.0), Color(0.75, 0.8, 1.0), 0.55, 6.0, false, true)


func _corridor() -> void:
	_terrace_wall(Vector2(XR, 0.0), Vector2(XR, Z_END))
	_terrace_wall(Vector2(XM, Z_END), Vector2(XR, Z_END))
	_box(Vector3((XM + XR) * 0.5, ROOF_Y - 0.1 + 0.07, Z_END * 0.5), Vector3(XR - XM + 0.3, 0.14, -Z_END + 0.2), m_plaster, false)
	# maceta con planta (en la esquina de la terraza, sin cortar el pasillo)
	_tinaja(Vector3(-5.45, 0, -3.5), 0.7)
	var leaf := _m(Color(0.12, 0.3, 0.1), 0.8)
	for k in 6:
		var a := TAU * k / 6.0
		var sm := SphereMesh.new()
		sm.radius = 0.22
		sm.height = 0.5
		_mesh(sm, leaf, Vector3(-5.45 + cos(a) * 0.15, 1.05 + 0.1 * (k % 2), -3.5 + sin(a) * 0.15))
	_light(Vector3(5.0, 2.45, -7.0), Color(1.0, 0.75, 0.5), 0.6, 5.0)


func _upper_floor() -> void:
	# primera planta sobre el comedor: enlucido crema con ventanas y tejado
	var x0 := XL - 0.1
	var x1 := XM + 0.1
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
	# chimenea de ladrillo
	_box(Vector3(-4.5, 7.4, -9.5), Vector3(0.7, 2.0, 0.7), _m(Color(0.6, 0.3, 0.2), 0.9, town.soft_noise, 2.0), false)
	_box(Vector3(-4.5, 8.45, -9.5), Vector3(0.9, 0.1, 0.9), m_plaster, false)
	# farol en la fachada
	var lantern_pos := Vector3(XM - 0.4, 4.3, Z_TERRACE + 0.65)
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
	# servilletero y vaso
	_box(Vector3(0.1, 0.83, 0.05), Vector3(0.1, 0.08, 0.05), m_chrome, false, body)
	_cyl(Vector3(-0.2, 0.84, -0.1), 0.035, 0.03, 0.1, m_glass, Vector3.ZERO, 8, body)
	for k in chairs:
		var a := TAU * k / chairs + rng.randf_range(-0.2, 0.2)
		var d := 0.72
		var cp := pos + Vector3(sin(a) * d, 0, cos(a) * d)
		if rng.randf() < 0.15:
			# silla tirada
			var c := _chair(cp, a, true)
			c.rotation.x = PI * 0.5
			c.position.y = 0.22
		else:
			_chair(cp, a)


func _chair(pos: Vector3, yaw: float, fallen := false) -> Node3D:
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
	var c := _cyl(pos, 0.22, 0.22, 0.05, face, Vector3(PI * 0.5, yaw, 0), 24)
	_cyl(pos + Vector3(0, 0, 0.0), 0.245, 0.245, 0.04, m_dark_wood, Vector3(PI * 0.5, yaw, 0), 24)
	c.position.z += 0.01
	var hand1 := _box(pos + Vector3(0.04, 0.05, 0.04), Vector3(0.02, 0.14, 0.005), m_black, false)
	hand1.rotation.z = -0.6
	var hand2 := _box(pos + Vector3(-0.05, -0.02, 0.04), Vector3(0.015, 0.18, 0.005), m_black, false)
	hand2.rotation.z = 1.9


func _drum_kit(pos: Vector3) -> void:
	var skin := _m(Color(0.9, 0.88, 0.8), 0.6)
	var shell := _m(Color(0.5, 0.05, 0.08), 0.3)
	# bombo
	_cyl(pos + Vector3(0, 0.3, 0), 0.3, 0.3, 0.4, shell, Vector3(PI * 0.5, 0, 0), 20)
	_cyl(pos + Vector3(0, 0.3, 0.205), 0.29, 0.29, 0.01, skin, Vector3(PI * 0.5, 0, 0), 20)
	# caja y timbales
	_cyl(pos + Vector3(0.5, 0.62, 0.15), 0.18, 0.18, 0.14, shell)
	_cyl(pos + Vector3(-0.15, 0.72, 0.05), 0.14, 0.14, 0.16, shell, Vector3(0.3, 0, 0))
	_cyl(pos + Vector3(-0.6, 0.55, 0.1), 0.22, 0.22, 0.3, shell)
	# platillos
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
	# Barricadas (ventanas por las que entran los zombies)
	var A: Node3D = _add_barricade(Vector3(2.7, 1.5, Z_TERRACE), Vector3(0, 0, 1), 1.4)
	var C: Node3D = _add_barricade(Vector3(2.2, 1.5, Z_BACK), Vector3(0, 0, -1), 1.2)
	var D: Node3D = _add_barricade(Vector3(XM, 1.5, -8.6), Vector3(1, 0, 0), 1.2)
	for s in [[A, Vector3(1.8, 0.05, -1.4)], [A, Vector3(-3.4, 0.05, -1.0)],
			[C, Vector3(1.5, 0.05, -14.6)], [C, Vector3(-0.6, 0.05, -14.2)],
			[D, Vector3(5.0, 0.05, -12.6)], [D, Vector3(5.0, 0.05, -4.2)]]:
		window_spawners.append({"pos": to_global(s[1]), "barricade": s[0]})

	# Puertas que se compran
	var d1 := BuyDoor.new()
	d1.cost = 750
	d1.label = "abrir la puerta del bar"
	d1.size = Vector3(1.6, 2.3, 0.1)
	d1.style = "double_glass"
	add_child(d1)
	d1.position = Vector3(0.2, 1.15, Z_TERRACE)
	d1.opened.connect(_on_door_opened)
	doors.append(d1)
	var d2 := BuyDoor.new()
	d2.cost = 1000
	d2.label = "abrir la terraza trasera"
	d2.size = Vector3(1.2, 2.3, 0.1)
	d2.style = "wood"
	add_child(d2)
	d2.position = Vector3(0.0, 1.15, Z_BACK)
	d2.opened.connect(_on_door_opened)
	doors.append(d2)

	# Quick Revive, junto a la pared derecha del comedor
	var qr := PerkMachine.new()
	qr.perk = "quick_revive"
	add_child(qr)
	qr.position = Vector3(3.45, 0.0, -11.1)
	qr.rotation.y = -PI * 0.5

	# Escopeta en la pared, junto a la entrada
	var ww := WallWeapon.new()
	ww.weapon_id = "escopeta"
	add_child(ww)
	ww.position = Vector3(-1.95, 1.45, Z_TERRACE - 0.12)
	ww.rotation.y = PI


func _add_barricade(center: Vector3, outward: Vector3, width: float):
	var b := Barricade.new()
	b.width = width
	b.height = 1.2
	add_child(b)
	b.position = center
	b.rotation.y = atan2(outward.x, outward.z)
	barricades.append(b)
	return b


func _on_door_opened(_door) -> void:
	town.open_exterior()


func is_inside_interior(world_pos: Vector3) -> bool:
	var p := to_local(world_pos)
	return p.x > -3.0 and p.x < XM and p.z > Z_BACK and p.z < Z_TERRACE
