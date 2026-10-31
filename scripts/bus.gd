extends Node3D
## Autobús interurbano verde de la línea 726 (como el de TranZit): da la vuelta
## al pueblo parando en la Av. Alejandro Rubio, el instituto, la Calle Hadar
## (suroeste), la Calle Encinas (norte) y la Av. Virgen del Espinar (este).
## Ruta y paradas: claves "bus_route" y "bus_stops" de town.json.
## El cuerpo es un AnimatableBody3D en la capa 16: el jugador viaja de pie dentro.
## Mientras va en marcha, el viajero solo choca con el bus (atraviesa tapias y
## barreras con él) y las puertas van cerradas: entre paradas no se baja nadie.
## Eje local: -Z = morro, +X = lado derecho (puertas).

enum State { WAITING, DRIVING }

const LEN := 12.0
const WID := 2.5
const FLOOR_Y := 0.28
const WAIT := 15.0
const CRUISE := 10.0       # m/s dentro de las zonas (36 km/h)
const FAST := 15.0         # m/s entre zonas, en la niebla (54 km/h)
const SLOW := 4.0          # en curvas cerradas
const SIDE_OFF := 1.6      # se circula por la derecha
const DOOR_FRONT := Vector2(-5.0, -3.7)   # z de la puerta delantera (lado derecho)
const DOOR_MID := Vector2(-0.6, 0.7)
const PLAYER_MASK := 1 | 4 | 8 | 16

var town
var game
var path := PackedVector2Array()     # ruta ya desplazada a la derecha (circular)
var acc := PackedFloat32Array()      # longitudes acumuladas
var total := 0.0
var stops: Array = []                # [{name, zone, s}]
var next_stop := 1                   # parada a la que va / la siguiente
var s := 0.0
var v := 0.0
var state := State.WAITING
var wait_t := WAIT
var speed_mult := 1.0                # para las pruebas
var body: AnimatableBody3D
var doors: Array = []                # [CollisionShape3D, MeshInstance3D]
var kill_area: Area3D
var engine: AudioStreamPlayer3D
var side_sign: Label3D
var inside_sign: Label3D
var blinkers: Array = []
var wheels: Array = []
var riders: Array = []               # jugadores que van dentro en marcha
var arrivals := 0
var visited := {}                    # zona -> veces que ha parado
var blink_t := 0.0


static func create(t) -> Node3D:
	var b = load("res://scripts/bus.gd").new()
	b.name = "Autobus726"
	b.town = t
	t.add_child(b)
	b._setup()
	return b


## Barrera "SOLO BUS" (rayas rojas y blancas). Bloquea a pie; el brazo se
## levanta al pasar el autobús (el viajero la atraviesa con él).
static func make_gate(t, pos: Vector2, dir: Vector2, width: float) -> void:
	var g := StaticBody3D.new()
	g.name = "BarreraBus"
	t.nav_region.add_child(g)
	g.position = Vector3(pos.x, 0, pos.y)
	g.rotation.y = atan2(-dir.x, -dir.y)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(width, 3.0, 0.4)
	cs.shape = sh
	cs.position.y = 1.5
	g.add_child(cs)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.85, 0.1, 0.1)
	var wht := StandardMaterial3D.new()
	wht.albedo_color = Color(0.95, 0.95, 0.95)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.5, 0.5, 0.52)
	steel.metallic = 0.7
	steel.roughness = 0.4
	var hw := width * 0.5
	_bx(g, Vector3(0.4, 1.1, 0.4), Vector3(-hw + 0.3, 0.55, 0), steel)
	var arm := Node3D.new()
	arm.position = Vector3(-hw + 0.3, 1.0, 0)
	g.add_child(arm)
	var k := 0
	var x := 0.2
	while x < width - 0.4:
		_bx(arm, Vector3(0.95, 0.12, 0.1), Vector3(x + 0.48, 0, 0), red if k % 2 == 0 else wht)
		x += 1.0
		k += 1
	var n := maxi(int((width - 0.8) / 2.2), 1)
	for i in n:
		_bx(g, Vector3(2.0, 0.9, 0.08), Vector3(-hw + 1.4 + i * 2.2, 0.45, 0.25), wht)
	var plate := _bx(g, Vector3(1.6, 0.4, 0.05), Vector3(0, 1.6, 0.3), steel)
	var l := Label3D.new()
	l.text = "SOLO BUS 726"
	l.font_size = 40
	l.pixel_size = 0.004
	l.modulate = Color(0.1, 0.25, 0.6)
	l.position = Vector3(0, 0, 0.03)
	plate.add_child(l)
	t.bus_gates.append({"arm": arm, "pos": Vector3(pos.x, 0, pos.y)})


static func _bx(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _setup() -> void:
	add_to_group("interactables")
	add_to_group("bus")
	stops = town.bus_stops
	var src: PackedVector2Array = town.bus_route
	for i in src.size():
		var d := Vector2.ZERO
		if i > 0:
			d += (src[i] - src[i - 1]).normalized()
		if i < src.size() - 1:
			d += (src[i + 1] - src[i]).normalized()
		d = d.normalized()
		path.append(src[i] + Vector2(-d.y, d.x) * SIDE_OFF)
	acc.append(0.0)
	for i in range(1, path.size()):
		acc.append(acc[i - 1] + path[i].distance_to(path[i - 1]))
	total = acc[acc.size() - 1]
	_build_body()
	for k in stops.size():
		_build_stop(k)
	for g in town.bus_gates_data:
		make_gate(town, g["pos"], g["dir"], 9.5)
	_place(0.0)
	_update_signs()


# ---------------------------------------------------------------- modelo

func _mat(c: Color, rough := 0.6, metal := 0.0, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.roughness = rough
	m.metallic = metal
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _glow(c: Color, e := 3.0) -> StandardMaterial3D:
	var m := _mat(c)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m


func _vis(size: Vector3, pos: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	return _bx(parent if parent else body, size, pos, mat)


func _col(size: Vector3, pos: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = pos
	body.add_child(cs)
	return cs


func _label(text: String, pos: Vector3, size: int, c: Color, rot_y := 0.0, px := 0.0045) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = px
	l.modulate = c
	l.position = pos
	l.rotation.y = rot_y
	l.double_sided = false
	body.add_child(l)
	return l


func _build_body() -> void:
	body = AnimatableBody3D.new()
	body.sync_to_physics = false   # se mueve al instante: los viajeros los lleva _carry
	body.collision_layer = 16
	body.collision_mask = 0
	add_child(body)
	var green := _mat(Color(0.42, 0.72, 0.13), 0.4, 0.25)
	var grey := _mat(Color(0.35, 0.36, 0.38), 0.6, 0.3)
	var white := _mat(Color(0.92, 0.93, 0.93), 0.5)
	var glass := _mat(Color(0.05, 0.07, 0.08), 0.06, 0.4, 0.45)
	var dark := _mat(Color(0.04, 0.04, 0.045), 0.8)
	var rubber := _mat(Color(0.03, 0.03, 0.03), 0.95)
	var hl := WID * 0.5
	var hz := LEN * 0.5
	# colisión: suelo, techo, frontal, trasera y laterales (con huecos de puertas)
	_col(Vector3(WID, 0.3, LEN), Vector3(0, FLOOR_Y - 0.15, 0))
	_col(Vector3(WID, 0.2, LEN), Vector3(0, 3.0, 0))
	_col(Vector3(WID, 3.0, 0.2), Vector3(0, 1.6, -hz))
	_col(Vector3(WID, 3.0, 0.2), Vector3(0, 1.6, hz))
	_col(Vector3(0.15, 3.0, LEN), Vector3(-hl, 1.6, 0))
	var cuts := [[-hz, DOOR_FRONT.x], [DOOR_FRONT.y, DOOR_MID.x], [DOOR_MID.y, hz]]
	for c in cuts:
		_col(Vector3(0.15, 3.0, c[1] - c[0]), Vector3(hl, 1.6, (c[0] + c[1]) * 0.5))
	for d in [DOOR_FRONT, DOOR_MID]:
		var ramp := _col(Vector3(1.1, 0.12, d.y - d.x), Vector3(hl + 0.42, FLOOR_Y * 0.5 - 0.04, (d.x + d.y) * 0.5))
		ramp.rotation.z = -0.28
	# carrocería: faldón gris, franja verde, ventanas oscuras, franja alta verde
	for side in [-1.0, 1.0]:
		var x: float = hl * side
		var segs: Array = [[-hz, hz]] if side < 0 else cuts
		for c in segs:
			var zl: float = c[1] - c[0]
			var zc: float = (c[0] + c[1]) * 0.5
			_vis(Vector3(0.06, 0.6, zl), Vector3(x, 0.55, zc), grey)
			_vis(Vector3(0.07, 0.04, zl), Vector3(x * 1.01, 0.86, zc), white)          # filo blanco
			_vis(Vector3(0.06, 0.4, zl), Vector3(x, 1.08, zc), green)
			_vis(Vector3(0.05, 1.45, zl), Vector3(x, 2.0, zc), glass)
			_vis(Vector3(0.06, 0.32, zl), Vector3(x, 2.88, zc), green)
		# montantes de las ventanas
		var zz := -hz + 1.0
		while zz < hz - 0.5:
			if side < 0 or not ((zz > DOOR_FRONT.x - 0.1 and zz < DOOR_FRONT.y + 0.1) or (zz > DOOR_MID.x - 0.1 and zz < DOOR_MID.y + 0.1)):
				_vis(Vector3(0.07, 1.45, 0.08), Vector3(x, 2.0, zz), dark)
			zz += 1.55
		# pasos de rueda y ruedas
		for wz in [-hz + 2.4, hz - 2.8]:
			_vis(Vector3(0.08, 0.35, 1.4), Vector3(x * 1.005, 0.95, wz), dark)
			var w := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.5
			cm.bottom_radius = 0.5
			cm.height = 0.32
			cm.radial_segments = 16
			w.mesh = cm
			w.material_override = rubber
			w.rotation.z = PI * 0.5
			w.position = Vector3(side * (hl - 0.14), 0.5, wz)
			body.add_child(w)
			var hub := _vis(Vector3(0.02, 0.4, 0.4), Vector3(0.17 * side, 0, 0), grey, w)
			hub.rotation.x = PI * 0.25
			wheels.append(w)
	# puertas de cristal (lado derecho): se esconden al abrir
	for d in [DOOR_FRONT, DOOR_MID]:
		var cs := _col(Vector3(0.12, 3.0, d.y - d.x), Vector3(hl, 1.6, (d.x + d.y) * 0.5))
		var holder := Node3D.new()
		body.add_child(holder)
		_vis(Vector3(0.05, 2.5, d.y - d.x - 0.05), Vector3(hl, 1.5, (d.x + d.y) * 0.5), glass, holder)
		_vis(Vector3(0.06, 2.5, 0.05), Vector3(hl, 1.5, (d.x + d.y) * 0.5), dark, holder)
		doors.append([cs, holder])
	# techo blanco con el equipo de aire
	_vis(Vector3(WID, 0.12, LEN + 0.02), Vector3(0, 3.08, 0), white)
	_vis(Vector3(WID - 0.6, 0.35, LEN * 0.35), Vector3(0, 3.3, 1.8), white)
	_vis(Vector3(WID - 0.9, 0.12, 1.2), Vector3(0, 3.2, -3.5), grey)
	# morro: parabrisas inclinado, paragolpes, letrero LED, faros y retrovisores
	_vis(Vector3(WID, 0.95, 0.1), Vector3(0, 0.72, -hz), green)
	_vis(Vector3(WID + 0.04, 0.28, 0.16), Vector3(0, 0.3, -hz - 0.03), grey)
	var ws := _vis(Vector3(WID - 0.08, 1.75, 0.05), Vector3(0, 2.0, -hz - 0.02), glass)
	ws.rotation.x = -0.06
	_vis(Vector3(WID, 0.32, 0.1), Vector3(0, 2.95, -hz), dark)
	_label("726  " + "GUADALIX", Vector3(0, 2.95, -hz - 0.06), 48, Color(1.0, 0.6, 0.1), PI)
	var lamp := _glow(Color(1, 0.96, 0.85))
	for x in [-0.95, 0.95]:
		_vis(Vector3(0.38, 0.16, 0.05), Vector3(x, 0.72, -hz - 0.06), lamp)
		var bl := _vis(Vector3(0.12, 0.08, 0.05), Vector3(x * 1.07, 0.92, -hz - 0.06), _glow(Color(1.0, 0.55, 0.05), 0.2))
		blinkers.append(bl)
		# retrovisor
		var arm := _vis(Vector3(0.45, 0.04, 0.04), Vector3(x * 1.42, 2.5, -hz + 0.1), dark)
		arm.name = "brazo"
		_vis(Vector3(0.06, 0.45, 0.22), Vector3(x * 1.6, 2.25, -hz + 0.1), dark)
	var head := SpotLight3D.new()
	head.light_energy = 2.2
	head.spot_range = 30.0
	head.spot_angle = 38.0
	head.position = Vector3(0, 0.9, -hz - 0.3)
	head.rotation.x = -0.1
	body.add_child(head)
	# trasera: número de línea y pilotos
	_vis(Vector3(WID, 3.0, 0.06), Vector3(0, 1.6, hz), green)
	_vis(Vector3(WID - 0.3, 0.9, 0.04), Vector3(0, 2.3, hz + 0.02), glass)
	_label("726", Vector3(0, 2.6, hz + 0.05), 96, Color(1.0, 0.6, 0.1), 0.0, 0.006)
	var red := _glow(Color(0.9, 0.05, 0.05), 1.5)
	for x in [-1.0, 1.0]:
		_vis(Vector3(0.25, 0.5, 0.05), Vector3(x, 0.9, hz + 0.04), red)
		var bl := _vis(Vector3(0.2, 0.12, 0.05), Vector3(x, 1.25, hz + 0.04), _glow(Color(1.0, 0.55, 0.05), 0.2))
		blinkers.append(bl)
	# letrero lateral de destino (encima de la puerta delantera)
	side_sign = _label("", Vector3(hl + 0.05, 2.88, -4.0), 34, Color(1.0, 0.6, 0.1), PI * 0.5)
	# interior: asientos azules, barras amarillas, pantalla de próxima parada, sin conductor
	var seat := _mat(Color(0.15, 0.25, 0.55), 0.7)
	var bar := _mat(Color(0.95, 0.75, 0.1), 0.4, 0.5)
	var floor_m := _mat(Color(0.25, 0.27, 0.28), 0.9)
	_vis(Vector3(WID - 0.2, 0.02, LEN - 0.2), Vector3(0, FLOOR_Y + 0.01, 0), floor_m)
	var z := -2.8
	while z < hz - 0.6:
		for x in [-0.75, 0.75]:
			if x > 0 and z > DOOR_MID.x - 0.5 and z < DOOR_MID.y + 0.5:
				continue
			_vis(Vector3(0.9, 0.12, 0.45), Vector3(x, FLOOR_Y + 0.45, z), seat)
			_vis(Vector3(0.9, 0.6, 0.08), Vector3(x, FLOOR_Y + 0.78, z + 0.22), seat)
			_vis(Vector3(0.06, 0.45, 0.06), Vector3(x, FLOOR_Y + 0.22, z), bar)
		z += 0.9
	for zz in [-3.2, 1.2, 3.6]:
		_vis(Vector3(0.05, 2.6, 0.05), Vector3(0.2, FLOOR_Y + 1.3, zz), bar)
	_vis(Vector3(0.04, 0.04, LEN - 1.0), Vector3(0.45, 2.55, 0), bar)
	_vis(Vector3(0.04, 0.04, LEN - 1.0), Vector3(-0.45, 2.55, 0), bar)
	_vis(Vector3(0.6, 0.05, 0.3), Vector3(-0.7, 1.2, -hz + 0.7), dark)   # volante
	_vis(Vector3(0.8, 1.0, 0.5), Vector3(-0.75, 0.75, -hz + 1.2), dark)  # puesto vacío
	_vis(Vector3(1.2, 0.3, 0.06), Vector3(0, 2.7, -hz + 0.25), dark)
	inside_sign = _label("", Vector3(0, 2.7, -hz + 0.29), 30, Color(1.0, 0.6, 0.1), 0.0, 0.003)
	for zz in [-2.5, 2.5]:
		var l := OmniLight3D.new()
		l.light_color = Color(0.85, 0.95, 1.0)
		l.light_energy = 0.7
		l.omni_range = 5.0
		l.position = Vector3(0, 2.7, zz)
		body.add_child(l)
		var tube := _vis(Vector3(0.1, 0.03, 2.0), Vector3(0, 2.88, zz), _glow(Color(0.9, 0.95, 1.0), 1.5))
		tube.name = "fluorescente"
	# atropellos
	kill_area = Area3D.new()
	kill_area.collision_layer = 0
	kill_area.collision_mask = 4
	var ks := CollisionShape3D.new()
	var kb := BoxShape3D.new()
	kb.size = Vector3(WID + 0.6, 2.0, 1.6)
	ks.shape = kb
	ks.position = Vector3(0, 1.0, -hz - 0.7)
	kill_area.add_child(ks)
	body.add_child(kill_area)
	_set_doors(true, false)


func _set_doors(open: bool, sound := true) -> void:
	for d in doors:
		d[0].disabled = open
		d[1].visible = not open
	if sound and is_inside_tree():
		Sfx.play3d("bus_doors", body.global_position + Vector3.UP, -4.0)


## Marquesina y poste de cada parada (a la derecha de la ruta)
func _build_stop(k: int) -> void:
	var green := _mat(Color(0.42, 0.72, 0.13), 0.45, 0.2)
	var glass := _mat(Color(0.6, 0.7, 0.75), 0.1, 0.1, 0.3)
	var steel := _mat(Color(0.55, 0.56, 0.58), 0.4, 0.7)
	var sp: float = stops[k]["s"]
	var p := _pos(sp)
	var d := (_pos(sp + 2.0) - _pos(sp - 2.0)).normalized()
	var right := Vector2(-d.y, d.x)
	var c := p + right * 2.6
	var st := StaticBody3D.new()
	st.name = "Parada_" + str(stops[k]["zone"])
	town.nav_region.add_child(st)
	st.position = Vector3(c.x, 0, c.y)
	st.rotation.y = atan2(-d.x, -d.y)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.3, 2.5, 4.0)
	cs.shape = sh
	cs.position = Vector3(0.9, 1.25, 0)
	st.add_child(cs)
	_vis(Vector3(0.05, 2.0, 4.0), Vector3(0.9, 1.3, 0), glass, st)
	_vis(Vector3(1.6, 0.08, 4.4), Vector3(0.3, 2.45, 0), steel, st)
	for z in [-2.0, 2.0]:
		_vis(Vector3(0.08, 2.45, 0.08), Vector3(0.9, 1.22, z), steel, st)
	_vis(Vector3(0.45, 0.06, 2.5), Vector3(0.65, 0.5, 0), steel, st)
	_vis(Vector3(0.08, 2.8, 0.08), Vector3(-0.2, 1.4, 2.6), steel, st)
	var plate := _vis(Vector3(0.05, 0.6, 0.6), Vector3(-0.2, 2.9, 2.6), green, st)
	var l := Label3D.new()
	l.text = "726\n" + str(stops[k]["name"])
	l.font_size = 40
	l.pixel_size = 0.004
	l.position = Vector3(-0.03, 0, 0)
	l.rotation.y = -PI * 0.5
	plate.add_child(l)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(0.85, 0.95, 1.0)
	lamp.light_energy = 0.8
	lamp.omni_range = 6.0
	lamp.position = Vector3(0.4, 2.3, 0)
	st.add_child(lamp)


# ---------------------------------------------------------------- recorrido

func _pos(dist: float) -> Vector2:
	dist = fposmod(dist, total)
	var lo := 0
	var hi := acc.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if acc[mid] < dist:
			lo = mid
		else:
			hi = mid
	var t := (dist - acc[lo]) / maxf(acc[hi] - acc[lo], 0.001)
	return path[lo].lerp(path[hi], t)


func _place(dist: float) -> void:
	var a := _pos(dist - 3.5)
	var b := _pos(dist + 3.5)
	var c := _pos(dist)
	var d := b - a
	body.global_transform = Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.y)), Vector3(c.x, 0.0, c.y))


func _stop_s(k: int) -> float:
	var ss: float = stops[k]["s"]
	return total if k == 0 and s > 1.0 else ss


## Velocidad objetivo: más rápido en la niebla, frena en curvas y al llegar
func _target_speed() -> float:
	var here := _pos(s)
	var tgt := CRUISE if town.in_detail(here, 20.0) else FAST
	var to_stop := _stop_s(next_stop) - s
	if to_stop < 25.0:
		tgt = minf(tgt, lerpf(1.5, CRUISE, to_stop / 25.0))
	var d0 := (_pos(s + 2.0) - _pos(s - 2.0)).normalized()
	for ahead in [6.0, 12.0, 18.0]:
		var d1 := (_pos(s + ahead + 2.0) - _pos(s + ahead - 2.0)).normalized()
		var turn := absf(d0.angle_to(d1))
		if turn > 0.3:
			tgt = minf(tgt, SLOW + ahead * 0.25 + (1.0 - clampf(turn / 1.4, 0.0, 1.0)) * 4.0)
	return tgt


func _physics_process(delta: float) -> void:
	var dt := delta * speed_mult
	blink_t += delta
	match state:
		State.WAITING:
			v = 0.0
			if town.exterior_open or speed_mult > 1.0:
				wait_t -= dt
				if wait_t <= 0.0:
					_depart()
		State.DRIVING:
			var tgt := _target_speed()
			v = move_toward(v, tgt, (2.2 if tgt > v else 4.5) * dt)
			s += v * dt
			var t0 := body.global_transform
			var arrived := false
			if s >= _stop_s(next_stop):
				s = _stop_s(next_stop)
				arrived = true
			_place(s)
			_carry(t0, body.global_transform)
			if arrived:
				_arrive()
			for z in kill_area.get_overlapping_bodies():
				if z.is_in_group("zombies") and not z.dead and v > 2.0:
					z.take_hit(999999.0, z.global_position + Vector3.UP, null)
			for w in wheels:
				w.rotate_object_local(Vector3.UP, -v * dt / 0.5)
	# barreras: se levantan al acercarse
	var bp := body.global_position
	for g in town.bus_gates:
		var near: bool = state == State.DRIVING and bp.distance_to(g["pos"]) < 18.0
		var arm: Node3D = g["arm"]
		arm.rotation.z = move_toward(arm.rotation.z, PI * 0.45 if near else 0.0, delta * 1.5)
	# intermitentes encendidos en las paradas
	var on := state == State.WAITING and fmod(blink_t, 0.8) < 0.4
	for bl in blinkers:
		bl.material_override.emission_energy_multiplier = 3.0 if on else 0.15
	if engine:
		engine.pitch_scale = 0.7 + v * 0.04


## Lleva a los viajeros "atornillados" al bus: se les aplica el mismo
## movimiento y giro que al autobús (sin depender de la física de plataformas,
## que en las curvas los lanzaba fuera). Si aun así se salen, vuelven dentro.
func _carry(t0: Transform3D, t1: Transform3D) -> void:
	var dyaw := t1.basis.get_euler().y - t0.basis.get_euler().y
	for p in riders:
		if not is_instance_valid(p):
			continue
		var local: Vector3 = t0.affine_inverse() * p.global_position
		local.x = clampf(local.x, -WID * 0.5 + 0.35, WID * 0.5 - 0.35)
		local.z = clampf(local.z, -LEN * 0.5 + 0.9, LEN * 0.5 - 0.5)
		local.y = clampf(local.y, FLOOR_Y, 2.0)
		p.global_position = t1 * local
		p.rotation.y += wrapf(dyaw, -PI, PI)


func _inside(p: Vector3) -> bool:
	var lp := body.to_local(p)
	return absf(lp.x) < WID * 0.5 and absf(lp.z) < LEN * 0.5 and lp.y > -0.5 and lp.y < 3.0


func _depart() -> void:
	state = State.DRIVING
	_set_doors(false)
	Sfx.play3d("bus_horn", body.global_position, 0.0)
	if engine == null:
		engine = Sfx.attach_loop("bus_engine", body, 0.0, 35.0)
	# los que van dentro viajan "pegados" al bus: solo chocan con él
	riders.clear()
	for p in get_tree().get_nodes_in_group("player"):
		if _inside(p.global_position):
			riders.append(p)
			p.collision_mask = 16
			p.platform_floor_layers = 0    # sin velocidad de plataforma: lo lleva _carry
	_update_signs()


func _arrive() -> void:
	arrivals += 1
	state = State.WAITING
	wait_t = WAIT
	v = 0.0
	var st: Dictionary = stops[next_stop]
	visited[st["zone"]] = visited.get(st["zone"], 0) + 1
	_set_doors(true)
	Sfx.play3d("bus_chime", body.global_position + Vector3.UP * 2.0, -2.0)
	if town:
		town.open_zone(st["zone"])   # el bus te deja allí: ya salen zombies
	for p in riders:
		if is_instance_valid(p):
			p.collision_mask = PLAYER_MASK
			p.platform_floor_layers = 0xFFFFFFFF
			if p.hud:
				p.hud.announce(str(st["name"]).to_upper())
	if not riders.is_empty() and game and game.rounds:
		game.rounds.relocate_zombies()
	riders.clear()
	if next_stop == 0:
		s = 0.0
	next_stop = (next_stop + 1) % stops.size()
	_update_signs()


func _update_signs() -> void:
	var nxt: String = stops[next_stop]["name"]
	side_sign.text = "726 → " + nxt
	inside_sign.text = ("PRÓXIMA PARADA\n" if state == State.DRIVING else "SALIDA HACIA\n") + nxt


func current_stop() -> String:
	return str(stops[(next_stop - 1 + stops.size()) % stops.size()]["name"])


# ---------------------------------------------------------------- interacción

func can_interact(player) -> bool:
	return body.to_local(player.global_position).length() < 7.5


func get_prompt(_player) -> String:
	var nxt: String = stops[next_stop]["name"]
	if state == State.WAITING:
		if not town.exterior_open:
			return "Autobús 726: fuera de servicio (abre la verja del bar)"
		return "Autobús 726 → %s · sale en %d s   [F] pitar" % [nxt, ceili(wait_t)]
	return "Autobús 726 → %s" % nxt


func is_hold() -> bool:
	return false


func interact(_player) -> void:
	Sfx.play3d("bus_horn", body.global_position, -2.0)
