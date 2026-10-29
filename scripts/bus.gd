extends Node3D
## Autobús interurbano verde de la línea 726 (como TranZit): va solo entre la
## parada de la Av. Alejandro Rubio y la del instituto, por Eras de Abajo, Eras del
## Medio y la glorieta. Te subes por las puertas de la derecha y te lleva.
## El cuerpo es un AnimatableBody3D: el jugador viaja de pie encima.
## Capa 16 (como las puertas): choca con jugador y zombies, no cuenta en la navmesh.
## Eje local: -Z = morro, +X = lado derecho (puertas).

enum State { WAITING, DRIVING }

const LEN := 12.0
const WID := 2.5
const FLOOR_Y := 0.28
const WAIT := 15.0
const CRUISE := 10.0       # m/s (36 km/h)
const SLOW := 3.5          # en curvas
const SIDE_OFF := 1.6      # se circula por la derecha
const DOOR_FRONT := Vector2(-5.0, -3.7)   # z de la puerta delantera (lado derecho)
const DOOR_MID := Vector2(-0.6, 0.7)
const STOP_NAMES := ["Av. Alejandro Rubio", "Instituto"]

var town
var game
var pts: PackedVector2Array          # ruta (centro de la calle), parada A -> parada B
var paths := []                      # [ida, vuelta] ya desplazadas a la derecha
var lens := []                       # longitudes acumuladas de cada camino
var leg := 0                         # 0 = ida (hacia el instituto), 1 = vuelta
var s := 0.0                         # metros recorridos en el tramo actual
var v := 0.0
var state := State.WAITING
var wait_t := WAIT
var speed_mult := 1.0                # para las pruebas
var body: AnimatableBody3D
var doors: Array = []                # [CollisionShape3D, MeshInstance3D]
var kill_area: Area3D
var barrier: StaticBody3D
var barrier_shape: CollisionShape3D
var barrier_arm: Node3D
var barrier_s := 0.0                 # dónde está la barrera en el camino de ida
var engine: AudioStreamPlayer3D
var sign_label: Label3D
var arrivals := 0


static func create(t) -> Node3D:
	var b = load("res://scripts/bus.gd").new()
	b.name = "Autobus726"
	b.town = t
	b.pts = t.bus_route
	t.add_child(b)
	b._setup()
	return b


func _setup() -> void:
	add_to_group("interactables")
	add_to_group("bus")
	for dir in [1, -1]:
		var src := pts.duplicate()
		if dir < 0:
			src.reverse()
		var out := PackedVector2Array()
		for i in src.size():
			var d := Vector2.ZERO
			if i > 0:
				d += (src[i] - src[i - 1]).normalized()
			if i < src.size() - 1:
				d += (src[i + 1] - src[i]).normalized()
			d = d.normalized()
			out.append(src[i] + Vector2(-d.y, d.x) * SIDE_OFF)
		paths.append(out)
		var acc := PackedFloat32Array([0.0])
		for i in range(1, out.size()):
			acc.append(acc[i - 1] + out[i].distance_to(out[i - 1]))
		lens.append(acc)
	_build_body()
	_build_stops()
	_build_barrier()
	_place(0.0)


# ---------------------------------------------------------------- modelo

func _mat(c: Color, rough := 0.6, metal := 0.0, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.roughness = rough
	m.metallic = metal
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _vis(size: Vector3, pos: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	(parent if parent else body).add_child(mi)
	return mi


func _col(size: Vector3, pos: Vector3, rot_x := 0.0) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = pos
	cs.rotation.x = rot_x
	body.add_child(cs)
	return cs


func _build_body() -> void:
	body = AnimatableBody3D.new()
	body.sync_to_physics = true
	body.collision_layer = 16
	body.collision_mask = 0
	add_child(body)
	var green := _mat(Color(0.42, 0.72, 0.13), 0.45, 0.2)
	var grey := _mat(Color(0.35, 0.36, 0.38), 0.6, 0.3)
	var white := _mat(Color(0.92, 0.93, 0.93), 0.5)
	var glass := _mat(Color(0.05, 0.07, 0.08), 0.08, 0.3, 0.45)
	var dark := _mat(Color(0.05, 0.05, 0.05), 0.8)
	var hl := WID * 0.5
	var hz := LEN * 0.5
	# suelo, techo, frontal y trasera (colisión)
	_col(Vector3(WID, 0.3, LEN), Vector3(0, FLOOR_Y - 0.15, 0))
	_col(Vector3(WID, 0.2, LEN), Vector3(0, 3.0, 0))
	_col(Vector3(WID, 3.0, 0.2), Vector3(0, 1.6, -hz))
	_col(Vector3(WID, 3.0, 0.2), Vector3(0, 1.6, hz))
	_col(Vector3(0.15, 3.0, LEN), Vector3(-hl, 1.6, 0))
	# lado derecho con los huecos de las puertas
	var cuts := [[-hz, DOOR_FRONT.x], [DOOR_FRONT.y, DOOR_MID.x], [DOOR_MID.y, hz]]
	for c in cuts:
		_col(Vector3(0.15, 3.0, c[1] - c[0]), Vector3(hl, 1.6, (c[0] + c[1]) * 0.5))
	# rampas para subir desde la acera (piso bajo)
	for d in [DOOR_FRONT, DOOR_MID]:
		_col(Vector3(1.1, 0.12, d.y - d.x), Vector3(hl + 0.42, FLOOR_Y * 0.5 - 0.04, (d.x + d.y) * 0.5)).rotation.z = -0.28
	# carrocería
	for side in [-1.0, 1.0]:
		var x: float = hl * side
		var segs: Array = [[-hz, hz]] if side < 0 else cuts
		for c in segs:
			var zl: float = c[1] - c[0]
			var zc: float = (c[0] + c[1]) * 0.5
			_vis(Vector3(0.06, 0.55, zl), Vector3(x, 0.55, zc), grey)          # faldón gris
			_vis(Vector3(0.06, 0.45, zl), Vector3(x, 1.05, zc), green)
			_vis(Vector3(0.05, 1.45, zl), Vector3(x, 2.0, zc), glass)          # ventanas
			_vis(Vector3(0.06, 0.32, zl), Vector3(x, 2.88, zc), green)
	for d in [DOOR_FRONT, DOOR_MID]:
		var cs := _col(Vector3(0.12, 3.0, d.y - d.x), Vector3(hl, 1.6, (d.x + d.y) * 0.5))
		var mi := _vis(Vector3(0.05, 2.5, d.y - d.x - 0.05), Vector3(hl, 1.5, (d.x + d.y) * 0.5), glass)
		doors.append([cs, mi])
	_vis(Vector3(WID, 0.12, LEN + 0.02), Vector3(0, 3.08, 0), white)        # techo blanco
	_vis(Vector3(WID - 0.6, 0.35, LEN * 0.4), Vector3(0, 3.3, 1.5), white)  # equipo de aire
	# morro: parabrisas, faldón, letrero LED y faros
	_vis(Vector3(WID, 0.9, 0.08), Vector3(0, 0.75, -hz), grey)
	_vis(Vector3(WID - 0.1, 1.6, 0.05), Vector3(0, 2.0, -hz - 0.02), glass)
	_vis(Vector3(WID, 0.3, 0.08), Vector3(0, 2.95, -hz), dark)
	sign_label = Label3D.new()
	sign_label.text = "726  GUADALIX"
	sign_label.font_size = 48
	sign_label.pixel_size = 0.0045
	sign_label.modulate = Color(1.0, 0.55, 0.1)
	sign_label.position = Vector3(0, 2.95, -hz - 0.05)
	sign_label.rotation.y = PI
	sign_label.double_sided = false
	body.add_child(sign_label)
	var lamp := _mat(Color(1, 1, 0.9))
	lamp.emission_enabled = true
	lamp.emission = Color(1, 0.95, 0.8)
	lamp.emission_energy_multiplier = 3.0
	for x in [-0.9, 0.9]:
		_vis(Vector3(0.35, 0.15, 0.05), Vector3(x, 0.75, -hz - 0.05), lamp)
	var head := SpotLight3D.new()
	head.light_energy = 2.0
	head.spot_range = 28.0
	head.spot_angle = 35.0
	head.position = Vector3(0, 0.9, -hz - 0.2)
	head.rotation.x = -0.12
	body.add_child(head)
	# trasera con número de línea
	_vis(Vector3(WID, 3.0, 0.06), Vector3(0, 1.6, hz), green)
	var back := Label3D.new()
	back.text = "726"
	back.font_size = 96
	back.pixel_size = 0.006
	back.modulate = Color(1.0, 0.55, 0.1)
	back.position = Vector3(0, 2.5, hz + 0.04)
	back.double_sided = false
	body.add_child(back)
	# ruedas
	for z in [-hz + 2.4, hz - 2.8]:
		for side in [-1.0, 1.0]:
			var w := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.5
			cm.bottom_radius = 0.5
			cm.height = 0.3
			w.mesh = cm
			w.material_override = dark
			w.rotation.z = PI * 0.5
			w.position = Vector3(side * (hl - 0.12), 0.5, z)
			body.add_child(w)
	# interior: asientos azules y barras amarillas, sin conductor (mal rollo)
	var seat := _mat(Color(0.15, 0.25, 0.55), 0.7)
	var bar := _mat(Color(0.95, 0.75, 0.1), 0.4, 0.5)
	var z := -2.8
	while z < hz - 0.6:
		for x in [-0.75, 0.75]:
			if x > 0 and z > DOOR_MID.x - 0.5 and z < DOOR_MID.y + 0.5:
				continue
			_vis(Vector3(0.9, 0.12, 0.45), Vector3(x, FLOOR_Y + 0.45, z), seat)
			_vis(Vector3(0.9, 0.55, 0.08), Vector3(x, FLOOR_Y + 0.75, z + 0.22), seat)
		z += 0.9
	for zz in [-3.2, 1.2, 3.6]:
		_vis(Vector3(0.05, 2.6, 0.05), Vector3(0.2, FLOOR_Y + 1.3, zz), bar)
	_vis(Vector3(0.6, 0.05, 0.3), Vector3(-0.7, 1.2, -hz + 0.7), dark)   # volante
	for zz in [-2.5, 2.5]:
		var l := OmniLight3D.new()
		l.light_color = Color(0.85, 0.95, 1.0)
		l.light_energy = 0.7
		l.omni_range = 5.0
		l.position = Vector3(0, 2.7, zz)
		body.add_child(l)
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
	_set_doors(true)


func _set_doors(open: bool) -> void:
	for d in doors:
		d[0].disabled = open
		d[1].visible = not open


## Marquesinas de las dos paradas
func _build_stops() -> void:
	var green := _mat(Color(0.42, 0.72, 0.13), 0.45, 0.2)
	var glass := _mat(Color(0.6, 0.7, 0.75), 0.1, 0.1, 0.3)
	var steel := _mat(Color(0.55, 0.56, 0.58), 0.4, 0.7)
	for k in 2:
		var path: PackedVector2Array = paths[0] if k == 0 else paths[1]
		var p := path[0]
		var d := (path[1] - path[0]).normalized()
		var right := Vector2(-d.y, d.x)
		var c := p + right * 2.6
		var st := StaticBody3D.new()
		st.name = "Parada" + str(k)
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
		var poste := _vis(Vector3(0.08, 2.8, 0.08), Vector3(-0.2, 1.4, 2.6), steel, st)
		poste.name = "poste"
		var plate := _vis(Vector3(0.05, 0.6, 0.6), Vector3(-0.2, 2.9, 2.6), green, st)
		var l := Label3D.new()
		l.text = "726\n" + STOP_NAMES[k]
		l.font_size = 40
		l.pixel_size = 0.004
		l.position = Vector3(-0.03, 0, 0)
		l.rotation.y = -PI * 0.5
		plate.add_child(l)


## Barrera en Eras de Abajo, junto a la avenida: solo se levanta para el autobús
func _build_barrier() -> void:
	var path: PackedVector2Array = paths[0]
	var acc: PackedFloat32Array = lens[0]
	# la barrera va 14 m después del cruce con Eras de Abajo (3er punto de la ruta)
	barrier_s = acc[2] + 14.0
	var p := _pos(0, barrier_s)
	var p2 := _pos(0, barrier_s + 1.0)
	var d := (p2 - p).normalized()
	var mid := p + Vector2(-d.y, d.x) * -SIDE_OFF   # centro de la calle
	barrier = StaticBody3D.new()
	barrier.name = "BarreraBus"
	town.nav_region.add_child(barrier)
	barrier.position = Vector3(mid.x, 0, mid.y)
	barrier.rotation.y = atan2(-d.x, -d.y)
	barrier_shape = CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(9.5, 3.0, 0.4)
	barrier_shape.shape = sh
	barrier_shape.position.y = 1.5
	barrier.add_child(barrier_shape)
	var red := _mat(Color(0.85, 0.1, 0.1), 0.5)
	var wht := _mat(Color(0.95, 0.95, 0.95), 0.5)
	var steel := _mat(Color(0.5, 0.5, 0.52), 0.4, 0.7)
	_vis(Vector3(0.4, 1.1, 0.4), Vector3(-4.6, 0.55, 0), steel, barrier)
	barrier_arm = Node3D.new()
	barrier_arm.position = Vector3(-4.6, 1.0, 0)
	barrier.add_child(barrier_arm)
	for k in 9:
		_vis(Vector3(0.95, 0.12, 0.1), Vector3(0.5 + k, 0, 0), red if k % 2 == 0 else wht, barrier_arm)
	# valla de obra baja debajo del brazo (que no se cuele nadie por debajo)
	for k in 4:
		_vis(Vector3(2.0, 0.9, 0.08), Vector3(-3.2 + k * 2.2, 0.45, 0.25), wht, barrier)
	var plate := _vis(Vector3(1.6, 0.4, 0.05), Vector3(0, 1.6, 0.3), _mat(Color(0.1, 0.25, 0.6)), barrier)
	var l := Label3D.new()
	l.text = "SOLO BUS 726"
	l.font_size = 40
	l.pixel_size = 0.004
	l.position = Vector3(0, 0, 0.03)
	plate.add_child(l)


# ---------------------------------------------------------------- recorrido

func _pos(which: int, dist: float) -> Vector2:
	var path: PackedVector2Array = paths[which]
	var acc: PackedFloat32Array = lens[which]
	dist = clampf(dist, 0.0, acc[acc.size() - 1])
	var i := 1
	while i < acc.size() - 1 and acc[i] < dist:
		i += 1
	var t := (dist - acc[i - 1]) / maxf(acc[i] - acc[i - 1], 0.001)
	return path[i - 1].lerp(path[i], t)


func _place(dist: float) -> void:
	var a := _pos(leg, dist - 3.0)
	var b := _pos(leg, dist + 3.0)
	var c := _pos(leg, dist)
	var d := b - a
	var xf := Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.y)), Vector3(c.x, 0.0, c.y))
	body.global_transform = xf


## Velocidad objetivo: frena antes de las curvas y al llegar
func _target_speed() -> float:
	var path: PackedVector2Array = paths[leg]
	var acc: PackedFloat32Array = lens[leg]
	var total: float = acc[acc.size() - 1]
	var tgt := CRUISE
	if total - s < 20.0:
		tgt = lerpf(1.5, CRUISE, (total - s) / 20.0)
	for i in range(1, path.size() - 1):
		var ahead: float = acc[i] - s
		if ahead < -6.0 or ahead > 18.0:
			continue
		var turn := absf((path[i] - path[i - 1]).angle_to(path[i + 1] - path[i]))
		if turn > 0.35:
			tgt = minf(tgt, SLOW + clampf(ahead, 0.0, 18.0) * 0.3)
	return tgt


func _physics_process(delta: float) -> void:
	var dt := delta * speed_mult
	match state:
		State.WAITING:
			v = 0.0
			if town.exterior_open or speed_mult > 1.0:
				wait_t -= dt
				if wait_t <= 0.0:
					_depart()
		State.DRIVING:
			var tgt := _target_speed()
			v = move_toward(v, tgt, (2.0 if tgt > v else 4.0) * dt)
			s += v * dt
			var total: float = lens[leg][lens[leg].size() - 1]
			if s >= total:
				s = total
				_arrive()
			_place(s)
			for z in kill_area.get_overlapping_bodies():
				if z.is_in_group("zombies") and not z.dead and v > 2.0:
					z.take_hit(999999.0, z.global_position + Vector3.UP, null)
			_update_barrier()
	if engine:
		engine.pitch_scale = 0.6 + v * 0.05


func _update_barrier() -> void:
	# distancia del bus a la barrera, en el camino del tramo actual
	var total: float = lens[0][lens[0].size() - 1]
	var bs := barrier_s if leg == 0 else total - barrier_s
	var near := absf(s - bs) < 16.0
	barrier_shape.disabled = near
	barrier_arm.rotation.z = move_toward(barrier_arm.rotation.z, PI * 0.45 if near else 0.0, 0.05)


func _depart() -> void:
	state = State.DRIVING
	s = 0.0
	_set_doors(false)
	Sfx.play3d("bus_horn", body.global_position, 0.0)
	if engine == null:
		engine = Sfx.attach_loop("machine_hum", body, 2.0, 30.0)


func _arrive() -> void:
	arrivals += 1
	state = State.WAITING
	wait_t = WAIT
	v = 0.0
	_set_doors(true)
	Sfx.play3d("bus_horn", body.global_position, -4.0, 1.1)
	if leg == 0 and town:
		town.open_zone("instituto")   # el bus te ha dejado allí: ya salen zombies
	leg = 1 - leg
	s = 0.0
	barrier_shape.disabled = false


func stop_index() -> int:
	return leg   # en espera: 0 = avenida, 1 = instituto


# ---------------------------------------------------------------- interacción

func can_interact(player) -> bool:
	return body.to_local(player.global_position).length() < 7.5


func get_prompt(_player) -> String:
	var dest: String = STOP_NAMES[1 - leg] if state == State.WAITING else STOP_NAMES[1 - leg]
	if state == State.WAITING:
		if not town.exterior_open:
			return "Autobús 726: fuera de servicio (abre la verja del bar)"
		return "Autobús 726 → %s · sale en %d s   [F] pitar" % [dest, ceili(wait_t)]
	return "Autobús 726 → %s" % STOP_NAMES[1 - leg]


func is_hold() -> bool:
	return false


func interact(_player) -> void:
	Sfx.play3d("bus_horn", body.global_position, -2.0)
