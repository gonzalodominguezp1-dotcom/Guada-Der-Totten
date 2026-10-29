extends RefCounted
## Zonas jugables del mapa (al estilo de los mapas de WaW):
##  - cierra el recorrido con tapias y escombros para que solo se pueda ir
##    por las calles y plazas jugables,
##  - coloca los escombros que se compran para pasar de una zona a otra,
##  - reparte los puntos de aparición de zombies por zona.
## Los datos vienen de town.json (claves "playable", "areas", "zone_doors").

const BuyDoor = preload("res://scripts/buy_door.gd")
const SIDEWALK := 1.6      # de la calzada a la línea de tapias
const STEP := 0.75


static func build(town) -> void:
	if town.playable.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "Cierre"
	town.nav_region.add_child(holder)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	_fence_xf.clear()
	# 1) tapias y escombros a lo largo de las calles jugables
	for pi in town.playable.size():
		var pl: Dictionary = town.playable[pi]
		var pts: PackedVector2Array = pl["points"]
		var off: float = pl["width"] * 0.5 + SIDEWALK
		for side: float in [1.0, -1.0]:
			for i in pts.size() - 1:
				var a := pts[i]
				var b := pts[i + 1]
				var L := a.distance_to(b)
				if L < 0.01:
					continue
				var dir := (b - a) / L
				var n := Vector2(-dir.y, dir.x) * side
				var t0 := -2.5 if i == 0 else 0.0
				var t1 := L + (2.5 if i == pts.size() - 2 else 0.0)
				_line(town, holder, rng, a + n * off, dir, n, t0, t1, pi, -1)
	# 2) bordes de las plazas y plazuelas jugables
	for ai in town.areas.size():
		var poly: PackedVector2Array = town.areas[ai]["points"]
		var c := Vector2.ZERO
		for p in poly:
			c += p
		c /= poly.size()
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			var L := a.distance_to(b)
			if L < 0.5:
				continue
			var dir := (b - a) / L
			var n := Vector2(-dir.y, dir.x)
			if n.dot((a + b) * 0.5 - c) < 0:
				n = -n
			_line(town, holder, rng, a + n * 0.3, dir, n, 0.0, L, -1, ai)
	_build_fence_bars(holder)
	# 3) tapones al final de las calles jugables que siguen sin serlo
	for pi in town.playable.size():
		var pl: Dictionary = town.playable[pi]
		var pts: PackedVector2Array = pl["points"]
		for e in [[pts[0], pts[1]], [pts[pts.size() - 1], pts[pts.size() - 2]]]:
			var p: Vector2 = e[0]
			var dir: Vector2 = (e[0] - e[1]).normalized()
			if _near_playable(town, p, pi, 1.5) or _in_area(town, p, 2.0):
				continue
			if not town.bounds.grow(-1.0).has_point(p):
				continue
			var w: float = pl["width"] + SIDEWALK * 2.0
			_rubble(town, holder, rng, p + dir * 1.0, Vector2(-dir.y, dir.x), w + 0.6)
	# 4) escombros que se compran entre zonas
	for zd in town.zone_doors_data:
		var door := BuyDoor.new()
		door.cost = zd["cost"]
		door.label = zd["label"]
		var w: float = zd["width"] + SIDEWALK * 2.0 + 0.4
		door.size = Vector3(w, 2.8, 1.2)
		door.style = "debris"
		door.zone = zd["zone"]
		town.nav_region.add_child(door)
		var pos: Vector2 = zd["pos"]
		var d: Vector2 = zd["dir"]
		door.position = Vector3(pos.x, 1.4, pos.y)
		door.rotation.y = atan2(-d.x, -d.y)
		door.opened.connect(func(dr): town.open_zone(dr.zone))
		town.zone_doors.append(door)


## Recorre una línea de borde y pone tapia o escombros donde no hay fachada
static func _line(town, holder: Node3D, rng: RandomNumberGenerator, start: Vector2, dir: Vector2, n: Vector2,
		t0: float, t1: float, own_pl: int, own_area: int) -> void:
	var kinds: Array = []
	var t := t0
	while t <= t1:
		var s := start + dir * t
		kinds.append([t, _classify(town, s, n, own_pl, own_area)])
		t += STEP
	# agrupar en tramos
	var i := 0
	while i < kinds.size():
		var k: String = kinds[i][1]
		var j := i
		while j + 1 < kinds.size() and kinds[j + 1][1] == k:
			j += 1
		if k == "fence":
			_fence(town, holder, start + dir * (kinds[i][0] - STEP * 0.5), start + dir * (kinds[j][0] + STEP * 0.5))
		elif k != "open":
			var ta: float = kinds[i][0] - STEP * 0.5
			var tb: float = kinds[j][0] + STEP * 0.5
			var a := start + dir * ta
			var b := start + dir * tb
			if k == "wall":
				_tapia(town, holder, rng, a, b)
			else:
				_rubble(town, holder, rng, (a + b) * 0.5, dir, tb - ta + 0.8)
		i = j + 1


static func _classify(town, s: Vector2, n: Vector2, own_pl: int, own_area: int) -> String:
	if not town.bounds.grow(-0.5).has_point(s):
		return "open"
	# recinto vallado (colegio, instituto): valla verde salvo en las puertas
	if own_area >= 0 and town.areas[own_area].get("fence", false):
		for g in town.areas[own_area].get("gates", []):
			if s.distance_to(g) < 3.2:
				return "open"
		for d in [0.0, 0.6, 1.5]:
			if town._in_any_building(s + n * d, 0.0):
				return "open"
		return "fence"
	# junto a un recinto vallado: su valla ya cierra
	if _near_fenced(town, s, 4.0):
		return "open"
	# fachada o edificio detrás: no hace falta tapia
	for d in [0.0, 0.6, 1.5, 2.6]:
		if town._in_any_building(s + n * d, 0.0):
			return "open"
	# dentro de otra zona jugable (cruce, plaza, plazuela): abierto
	if _in_area(town, s, 0.4, own_area):
		return "open"
	for pi in town.playable.size():
		var pl: Dictionary = town.playable[pi]
		var lim: float = pl["width"] * 0.5 + SIDEWALK - (0.15 if pi == own_pl else -0.2)
		if _dist_poly(s, pl["points"]) < lim:
			return "open"
	# calle no jugable: escombros; si no, tapia
	for st in town.streets:
		if _dist_poly(s, st["points"]) < st["width"] * 0.5 + 0.6:
			return "rubble"
	return "wall"


static func _near_fenced(town, p: Vector2, dist: float) -> bool:
	for ar in town.areas:
		if not ar.get("fence", false):
			continue
		var poly: PackedVector2Array = ar["points"]
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
		for i in poly.size():
			var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
			if q.distance_to(p) < dist:
				return true
	return false


static func _in_area(town, p: Vector2, grow: float, skip := -1) -> bool:
	for ai in town.areas.size():
		if ai == skip:
			continue
		var poly: PackedVector2Array = town.areas[ai]["points"]
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
		if grow > 0.0:
			for i in poly.size():
				var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
				if q.distance_to(p) < grow:
					return true
	return false


static func _near_playable(town, p: Vector2, skip: int, extra: float) -> bool:
	for pi in town.playable.size():
		if pi == skip:
			continue
		var pl: Dictionary = town.playable[pi]
		if _dist_poly(p, pl["points"]) < pl["width"] * 0.5 + SIDEWALK + extra:
			return true
	return false


static func _dist_poly(p: Vector2, pts: PackedVector2Array) -> float:
	var best := INF
	for i in pts.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
		best = minf(best, p.distance_to(q))
	return best


# ---------------------------------------------------------------- piezas

static func _tapia(town, holder: Node3D, rng: RandomNumberGenerator, a: Vector2, b: Vector2) -> void:
	var L := a.distance_to(b)
	if L < 0.3:
		return
	var dir := (b - a) / L
	var n := Vector2(-dir.y, dir.x)
	var h := rng.randf_range(2.3, 2.7)
	var thick := 0.35
	var r := rng.randf()
	var kind := 1 if r < 0.55 else (0 if r < 0.85 else 2)
	var tint := Color(0.86, 0.80, 0.66)
	var col := tint
	col.a = float(kind * 64 + rng.randi() % 16) / 255.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [1.0, -1.0]:
		var o: Vector2 = n * thick * 0.5 * side
		var p0 := a + o
		var p1 := b + o
		town._quad(st, Vector3(p0.x, -0.1, p0.y), Vector3(p1.x, -0.1, p1.y), Vector3(p1.x, h, p1.y), Vector3(p0.x, h, p0.y),
			Vector2(0, -0.1), Vector2(L, -0.1), Vector2(L, h), Vector2(0, h), Vector3(n.x * side, 0, n.y * side), Vector2(0, h), col)
	var mesh := st.commit()
	var body := StaticBody3D.new()
	holder.add_child(body)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = town.facade_mat
	body.add_child(mi)
	# albardilla
	var cap := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(L + 0.05, 0.12, thick + 0.12)
	cap.mesh = cm
	cap.material_override = town.curb_mat
	var mid := (a + b) * 0.5
	cap.position = Vector3(mid.x, h + 0.06, mid.y)
	cap.rotation.y = atan2(-dir.y, dir.x)
	body.add_child(cap)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(L, h + 0.6, thick)
	cs.shape = shape
	cs.position = Vector3(mid.x, (h + 0.6) * 0.5, mid.y)
	cs.rotation.y = atan2(-dir.y, dir.x)
	body.add_child(cs)


## Valla de barrotes verdes (como la del instituto): murete, pasamanos y
## barrotes (todos juntos en un MultiMesh al final). Bloquea el paso, no la vista.
static var _fence_xf: Array = []
static var _fence_mat: StandardMaterial3D


static func _fence(_town, holder: Node3D, a: Vector2, b: Vector2) -> void:
	var L := a.distance_to(b)
	if L < 0.3:
		return
	var dir := (b - a) / L
	var h := 2.0
	var yaw := atan2(-dir.y, dir.x)
	var bas := Basis(Vector3.UP, yaw)
	var mid := (a + b) * 0.5
	_fence_xf.append(Transform3D(bas.scaled(Vector3(L, 0.35, 0.3)), Vector3(mid.x, 0.175, mid.y)))
	for y: float in [0.55, h - 0.05]:
		_fence_xf.append(Transform3D(bas.scaled(Vector3(L, 0.05, 0.05)), Vector3(mid.x, y, mid.y)))
	var t := 0.06
	var k := 0
	while t < L:
		var p := a + dir * t
		var w := 0.08 if k % 20 == 0 else 0.025
		_fence_xf.append(Transform3D(bas.scaled(Vector3(w, h - 0.35, w)), Vector3(p.x, 0.35 + (h - 0.35) * 0.5, p.y)))
		t += 0.13
		k += 1
	var body := StaticBody3D.new()
	holder.add_child(body)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(L, h + 0.6, 0.3)
	cs.shape = shape
	cs.position = Vector3(mid.x, (h + 0.6) * 0.5, mid.y)
	cs.rotation.y = yaw
	body.add_child(cs)


static func _build_fence_bars(holder: Node3D) -> void:
	if _fence_xf.is_empty():
		return
	if _fence_mat == null:
		_fence_mat = StandardMaterial3D.new()
		_fence_mat.albedo_color = Color(0.13, 0.42, 0.33)
		_fence_mat.roughness = 0.5
		_fence_mat.metallic = 0.3
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	mm.mesh = bm
	mm.instance_count = _fence_xf.size()
	for i in _fence_xf.size():
		mm.set_instance_transform(i, _fence_xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _fence_mat
	holder.add_child(mmi)
	_fence_xf.clear()


## Barricada de escombros y coches destrozados atravesando una calle
static func _rubble(town, holder: Node3D, rng: RandomNumberGenerator, c: Vector2, dir: Vector2, length: float) -> void:
	var body := StaticBody3D.new()
	body.position = Vector3(c.x, 0, c.y)
	body.rotation.y = atan2(-dir.y, dir.x)
	holder.add_child(body)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(length, 3.0, 1.4)
	cs.shape = shape
	cs.position.y = 1.5
	body.add_child(cs)
	build_rubble_visual(body, rng, length, town)


static func build_rubble_visual(parent: Node3D, rng: RandomNumberGenerator, length: float, town = null) -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.45, 0.43, 0.40)
	stone.roughness = 0.95
	if town:
		stone.albedo_texture = town.soft_noise
		stone.uv1_triplanar = true
	var brick := StandardMaterial3D.new()
	brick.albedo_color = Color(0.5, 0.26, 0.18)
	brick.roughness = 0.9
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.32, 0.22, 0.13)
	wood.roughness = 0.9
	var rust := StandardMaterial3D.new()
	var car_cols := [Color(0.35, 0.18, 0.12), Color(0.22, 0.24, 0.26), Color(0.4, 0.38, 0.33), Color(0.15, 0.2, 0.3)]
	rust.albedo_color = car_cols[rng.randi() % car_cols.size()]
	rust.roughness = 0.8
	rust.metallic = 0.3
	if town:
		rust.albedo_texture = town.noise_tex
		rust.uv1_triplanar = true
		rust.uv1_scale = Vector3(0.6, 0.6, 0.6)
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.04, 0.04, 0.04)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.05, 0.06, 0.07)
	glass.roughness = 0.1
	var x := -length * 0.5 + 0.4
	while x < length * 0.5 - 0.3:
		if rng.randf() < 0.45 and length * 0.5 - x > 3.8:
			# coche destrozado
			var car := Node3D.new()
			car.position = Vector3(x + 2.0, 0, rng.randf_range(-0.3, 0.3))
			car.rotation = Vector3(rng.randf_range(-0.08, 0.08), rng.randf_range(-0.35, 0.35), rng.randf_range(-0.1, 0.1))
			parent.add_child(car)
			_b(car, Vector3(3.9, 0.7, 1.7), Vector3(0, 0.6, 0), rust)
			_b(car, Vector3(2.0, 0.55, 1.5), Vector3(-0.2, 1.22, 0), rust)
			_b(car, Vector3(1.9, 0.45, 1.52), Vector3(-0.2, 1.22, 0), glass)
			for wx in [-1.3, 1.3]:
				for wz in [-0.85, 0.85]:
					var wh := MeshInstance3D.new()
					var cm := CylinderMesh.new()
					cm.top_radius = 0.33
					cm.bottom_radius = 0.33
					cm.height = 0.22
					wh.mesh = cm
					wh.material_override = black
					wh.position = Vector3(wx, 0.33, wz)
					wh.rotation.x = PI * 0.5
					car.add_child(wh)
			x += 4.2
		else:
			var n := rng.randi_range(3, 6)
			for k in n:
				var s := Vector3(rng.randf_range(0.3, 1.1), rng.randf_range(0.25, 0.9), rng.randf_range(0.3, 1.0))
				var m: Material = [stone, stone, brick, wood][rng.randi() % 4]
				var bx := _b(parent, s, Vector3(x + rng.randf_range(-0.4, 0.6), s.y * 0.5 + k * 0.18, rng.randf_range(-0.5, 0.5)), m)
				bx.rotation = Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4))
			# tablón cruzado
			var pl := _b(parent, Vector3(2.2, 0.05, 0.22), Vector3(x + 0.6, 0.9, 0.0), wood)
			pl.rotation = Vector3(0, rng.randf_range(-0.4, 0.4), rng.randf_range(-0.5, 0.5))
			x += 1.3


static func _b(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


# ---------------------------------------------------------------- aparición

static func compute_spawns(town) -> void:
	var inner: Rect2 = town.bounds.grow(-3.0)
	for pl in town.playable:
		var pts: PackedVector2Array = pl["points"]
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var steps := maxi(int(a.distance_to(b) / 7.0), 1)
			for j in steps + 1:
				var p := a.lerp(b, float(j) / steps)
				if inner.has_point(p) and not town._in_any_building(p, 0.9):
					town.spawn_points.append(Vector3(p.x, 0.05, p.y))
					town.spawn_zones.append(pl["zone"])
	for ar in town.areas:
		var poly: PackedVector2Array = ar["points"]
		var r := Rect2(poly[0], Vector2.ZERO)
		for p in poly:
			r = r.expand(p)
		var x := r.position.x + 3.0
		while x < r.end.x:
			var z := r.position.y + 3.0
			while z < r.end.y:
				var p := Vector2(x, z)
				if Geometry2D.is_point_in_polygon(p, poly) and not town._in_any_building(p, 1.0):
					town.spawn_points.append(Vector3(p.x, 0.05, p.y))
					town.spawn_zones.append(ar["zone"])
				z += 7.0
			x += 7.0
