extends Node3D
## Skatepark (nivel aparte, se llega por el portal de Segundo Guada): arena,
## rampas metálicas, barandilla azul y árboles alrededor (fotos del usuario).
## Easter egg: aquí está "el colega" (NPC que suelta el calzoncillo) y, cuando
## tienes el pepino, aparece la estatua del culo gigante: hay que darle de comer
## 10 zombies con el Cañón de Zurraspa Dorado cerca y luego meterle el pepino [F].

const Portal = preload("res://scripts/portal.gd")
const PLAY := Rect2(-30.0, -24.0, 60.0, 48.0)
const FEED_RADIUS := 10.0
const FEED_NEEDED := 10

var town
var nav: NavigationRegion3D
var portal
var rng := RandomNumberGenerator.new()
var npc_spawned := false
var statue: Node3D
var statue_body: StaticBody3D
var statue_glow: OmniLight3D
var statue_mat: StandardMaterial3D
var fed := 0
var satisfied := false


static func create(t, origin: Vector3):
	var sp = load("res://scripts/skatepark.gd").new()
	sp.name = "Skatepark"
	sp.town = t
	t.add_child(sp)
	sp.position = origin
	sp._build()
	return sp


func _m(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, collide := false, rot := Vector3.ZERO) -> Node3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	if mat == null:
		mi = null
	if not collide:
		mi.position = pos
		mi.rotation = rot
		parent.add_child(mi)
		return mi
	var b := StaticBody3D.new()
	b.position = pos
	b.rotation = rot
	parent.add_child(b)
	if mi:
		b.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	return b


func _build() -> void:
	rng.seed = 2626
	nav = NavigationRegion3D.new()
	nav.name = "NavegacionSkate"
	add_child(nav)
	var sand := _m(Color(0.5, 0.44, 0.34), 1.0)
	sand.albedo_texture = town.soft_noise
	sand.uv1_triplanar = true
	sand.uv1_scale = Vector3(0.3, 0.3, 0.3)
	var grass := _m(Color(0.32, 0.38, 0.2), 1.0)
	grass.albedo_texture = town.soft_noise
	grass.uv1_triplanar = true
	grass.uv1_scale = Vector3(0.2, 0.2, 0.2)
	var concrete := _m(Color(0.55, 0.55, 0.53), 0.9)
	concrete.albedo_texture = town.soft_noise
	concrete.uv1_triplanar = true
	var steel := _m(Color(0.55, 0.56, 0.58), 0.35, 0.8)
	var blue := _m(Color(0.2, 0.45, 0.85), 0.5, 0.3)
	var dark := _m(Color(0.12, 0.13, 0.15), 0.6, 0.4)
	# suelo: hierba alrededor, arena en el parque y la losa de hormigón
	var g := PlaneMesh.new()
	g.size = Vector2(260, 260)
	var gm := MeshInstance3D.new()
	gm.mesh = g
	gm.material_override = grass
	nav.add_child(gm)
	_box(nav, Vector3(260, 1.0, 260), Vector3(0, -0.52, 0), grass, true)
	_box(nav, Vector3(PLAY.size.x + 6, 0.04, PLAY.size.y + 6), Vector3(0, 0.0, 0), sand)
	_box(nav, Vector3(26, 0.08, 13), Vector3(2, 0.04, -2), concrete, true, Vector3(0, 0.35, 0))
	# rampa grande de metal con jaula (la de la foto): plataforma, barrotes y bajada
	var big := Node3D.new()
	big.position = Vector3(-12, 0, 6)
	big.rotation.y = 0.35
	nav.add_child(big)
	_box(big, Vector3(4.0, 0.12, 3.0), Vector3(0, 1.3, 0), steel, true)
	for x in [-1.9, 1.9]:
		for z in [-1.4, 1.4]:
			_box(big, Vector3(0.08, 1.3, 0.08), Vector3(x, 0.65, z), steel)
	var xx := -2.0
	while xx <= 2.0:
		_box(big, Vector3(0.04, 1.5, 0.04), Vector3(xx, 2.1, -1.5), steel)
		xx += 0.25
	for side in [-1.0, 1.0]:
		var zz := -1.5
		while zz <= 1.5:
			_box(big, Vector3(0.04, 1.5, 0.04), Vector3(2.0 * side, 2.1, zz), steel)
			zz += 0.25
	_box(big, Vector3(4.1, 0.06, 0.06), Vector3(0, 2.85, -1.5), steel)
	# bajada (rampa inclinada) por delante
	_box(big, Vector3(4.0, 0.1, 3.4), Vector3(0, 0.65, 3.0), dark, true, Vector3(0.4, 0, 0))
	# rampas pequeñas azules, cajón de grind y banco
	for k in 2:
		var r := Node3D.new()
		r.position = Vector3(6 + k * 3.2, 0, -6 - k * 1.5)
		r.rotation.y = 0.35 + k * 0.2
		nav.add_child(r)
		_box(r, Vector3(1.6, 0.06, 1.4), Vector3(0, 0.3, 0), blue, true, Vector3(0.42, 0, 0))
		_box(r, Vector3(1.6, 0.6, 0.06), Vector3(0, 0.3, -0.6), blue)
	_box(nav, Vector3(3.2, 0.45, 0.5), Vector3(0, 0.23, -1), steel, true, Vector3(0, 0.35, 0))
	for k in 3:
		var b := _box(nav, Vector3(1.8, 0.45, 0.5), Vector3(10.0 - k * 9.0, 0.23, 14.0), _m(Color(0.42, 0.26, 0.14)), true)
		b.name = "banco"
	# barandilla azul alrededor (con un hueco en el sur)
	var r0 := PLAY
	var segs := [[Vector2(r0.position.x, r0.position.y), Vector2(r0.end.x, r0.position.y)],
		[Vector2(r0.end.x, r0.position.y), Vector2(r0.end.x, r0.end.y)],
		[Vector2(r0.position.x, r0.end.y), Vector2(r0.position.x, r0.position.y)],
		[Vector2(r0.end.x, r0.end.y), Vector2(4.0, r0.end.y)], [Vector2(-4.0, r0.end.y), Vector2(r0.position.x, r0.end.y)]]
	for sg in segs:
		var a: Vector2 = sg[0]
		var b2: Vector2 = sg[1]
		var L := a.distance_to(b2)
		var mid := (a + b2) * 0.5
		var yaw := atan2(-(b2 - a).y, (b2 - a).x)
		_box(nav, Vector3(L, 0.06, 0.06), Vector3(mid.x, 1.0, mid.y), blue, false, Vector3(0, yaw, 0))
		_box(nav, Vector3(L, 0.05, 0.05), Vector3(mid.x, 0.5, mid.y), blue, false, Vector3(0, yaw, 0))
		var t := 0.0
		while t <= L:
			var p := a.lerp(b2, t / L)
			_box(nav, Vector3(0.06, 1.0, 0.06), Vector3(p.x, 0.5, p.y), blue)
			t += 2.5
	# límites invisibles (un poco más allá de la barandilla, para poder correr)
	var lim := PLAY.grow(8.0)
	for w in [[Vector3(lim.get_center().x, 3, lim.position.y), Vector3(lim.size.x, 6, 1)],
			[Vector3(lim.get_center().x, 3, lim.end.y), Vector3(lim.size.x, 6, 1)],
			[Vector3(lim.position.x, 3, lim.get_center().y), Vector3(1, 6, lim.size.y)],
			[Vector3(lim.end.x, 3, lim.get_center().y), Vector3(1, 6, lim.size.y)]]:
		_box(nav, w[1], w[0], null, true)
	# árboles alrededor y tobogán rosa del parque infantil a lo lejos
	for k in 46:
		var a := rng.randf() * TAU
		var rr := rng.randf_range(42.0, 80.0) if k > 10 else rng.randf_range(31.0, 37.0)
		_tree(Vector3(sin(a) * rr, 0, cos(a) * rr))
	var pink := _m(Color(0.95, 0.4, 0.7), 0.5)
	_box(nav, Vector3(0.6, 0.06, 3.2), Vector3(26, 1.0, -30), pink, false, Vector3(0.6, 0, 0))
	_box(nav, Vector3(1.0, 2.0, 1.0), Vector3(26, 1.0, -32), pink)
	# farolas
	for p in [Vector3(-20, 0, -20), Vector3(20, 0, -20), Vector3(-20, 0, 20), Vector3(20, 0, 20)]:
		_box(nav, Vector3(0.12, 4.0, 0.12), p + Vector3(0, 2.0, 0), dark)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.55)
		l.light_energy = 1.6
		l.omni_range = 18.0
		l.position = p + Vector3(0, 4.0, 0)
		nav.add_child(l)
	# portal de vuelta a Segundo Guada
	portal = Portal.new()
	portal.label_text = "SEGUNDO GUADA"
	portal.town = town
	portal.name = "PortalSkate"
	nav.add_child(portal)
	portal.position = Vector3(0, 0, PLAY.end.y - 3.0)
	portal.rotation.y = PI
	if town.portal_segundo:
		portal.other = town.portal_segundo
		town.portal_segundo.other = portal
	_build_statue()
	# puntos de aparición
	var x := PLAY.position.x + 3.0
	while x < PLAY.end.x - 2.0:
		var z := PLAY.position.y + 3.0
		while z < PLAY.end.y - 2.0:
			town.spawn_points.append(position + Vector3(x, 0.05, z))
			town.spawn_zones.append("skatepark")
			z += 7.0
		x += 7.0
	_bake()


func _tree(p: Vector3) -> void:
	var trunk := _m(Color(0.3, 0.22, 0.15))
	var leaves := _m(Color(0.2, 0.36, 0.14), 0.95)
	var h := rng.randf_range(4.0, 6.5)
	var b := StaticBody3D.new()
	b.position = p
	nav.add_child(b)
	var tm := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.14
	cm.bottom_radius = 0.24
	cm.height = h
	tm.mesh = cm
	tm.material_override = trunk
	tm.position.y = h * 0.5
	b.add_child(tm)
	for k in 5:
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = rng.randf_range(1.4, 2.2)
		sm.height = sm.radius * 1.6
		sm.radial_segments = 10
		sm.rings = 6
		s.mesh = sm
		s.material_override = leaves
		s.position = Vector3(rng.randf_range(-1.2, 1.2), h + rng.randf_range(-0.5, 1.4), rng.randf_range(-1.2, 1.2))
		b.add_child(s)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.3
	sh.height = h
	cs.shape = sh
	cs.position.y = h * 0.5
	b.add_child(cs)


# ---------------------------------------------------------------- estatua del culo

func _build_statue() -> void:
	statue = Node3D.new()
	statue.name = "EstatuaCulo"
	statue.position = Vector3(16, 0, 6)
	statue.rotation.y = -0.6
	statue.visible = false
	add_child(statue)
	var stone := _m(Color(0.6, 0.58, 0.55), 0.9)
	statue_mat = _m(Color(0.95, 0.72, 0.62), 0.55)
	statue_mat.emission = Color(1.0, 0.5, 0.3)
	statue_body = StaticBody3D.new()
	statue.add_child(statue_body)
	statue_body.collision_layer = 0   # no estorba hasta que aparece
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(4.2, 5.5, 3.0)
	cs.shape = sh
	cs.position.y = 2.75
	statue_body.add_child(cs)
	_box(statue, Vector3(4.2, 1.2, 3.0), Vector3(0, 0.6, 0), stone)
	for x in [-0.95, 0.95]:
		var cheek := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.4
		sm.height = 2.8
		cheek.mesh = sm
		cheek.material_override = statue_mat
		cheek.position = Vector3(x, 3.0, 0)
		cheek.scale = Vector3(1.0, 1.05, 0.85)
		statue.add_child(cheek)
	var plate := _box(statue, Vector3(1.6, 0.35, 0.05), Vector3(0, 0.75, 1.53), _m(Color(0.75, 0.6, 0.2), 0.3, 0.8))
	var l := Label3D.new()
	l.text = "TENGO HAMBRE"
	l.font_size = 40
	l.pixel_size = 0.004
	l.modulate = Color(0.2, 0.1, 0.0)
	l.position = Vector3(0, 0, 0.03)
	plate.add_child(l)
	statue_glow = OmniLight3D.new()
	statue_glow.light_color = Color(1.0, 0.55, 0.3)
	statue_glow.light_energy = 0.0
	statue_glow.omni_range = 9.0
	statue_glow.position = Vector3(0, 3.0, 2.0)
	statue.add_child(statue_glow)


func _process(_d: float) -> void:
	if statue and not statue.visible and town.get_parent() and town.get_parent().get("parts") != null:
		var parts: Dictionary = town.get_parent().parts
		if parts.get("pepino", false) or satisfied:
			_show_statue()


func _show_statue() -> void:
	statue.visible = true
	statue_body.collision_layer = 1
	statue_mat.emission_enabled = true
	statue_mat.emission_energy_multiplier = 0.2
	statue_glow.light_energy = 0.4
	if not get_tree().get_nodes_in_group("statue_feeder").is_empty():
		return
	var feeder := StatueFeeder.new()
	feeder.sp = self
	feeder.add_to_group("statue_feeder")
	feeder.add_to_group("interactables")
	statue.add_child(feeder)


## Cada zombie que muere cerca con el arma mejorada "alimenta" a la estatua
func on_zombie_killed(z, player) -> void:
	if not statue or not statue.visible or satisfied or fed >= FEED_NEEDED or z.special != "":
		return
	if player == null or player.weapon_id() != "zurraspa_pap":
		return
	if z.global_position.distance_to(statue.global_position) > FEED_RADIUS:
		return
	fed += 1
	_soul(z.global_position)
	statue_mat.emission_energy_multiplier = 0.2 + fed * 0.25
	statue_glow.light_energy = 0.4 + fed * 0.25
	if player.hud:
		player.hud.announce("El culo come... (%d/%d)" % [fed, FEED_NEEDED] if fed < FEED_NEEDED else "¡El culo está lleno! Dale el pepino [F]")


func _soul(from: Vector3) -> void:
	var s := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.2
	sm.height = 0.4
	s.mesh = sm
	var m := _m(Color(1.0, 0.8, 0.4))
	m.emission_enabled = true
	m.emission = Color(1.0, 0.7, 0.3)
	m.emission_energy_multiplier = 3.0
	s.material_override = m
	get_tree().current_scene.add_child(s)
	s.global_position = from + Vector3.UP
	var tw := s.create_tween()
	tw.tween_property(s, "global_position", statue.global_position + Vector3(0, 3, 0), 0.8).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(s.queue_free)


func feed_pepino(player) -> void:
	satisfied = true
	var parts: Dictionary = town.get_parent().parts
	parts.erase("pepino")
	Sfx.play("nuclear", 0.0, 1.3)
	statue_mat.emission_energy_multiplier = 4.0
	statue_glow.light_energy = 4.0
	var tw := statue.create_tween()
	for k in 6:
		tw.tween_property(statue, "rotation:z", 0.06 if k % 2 == 0 else -0.06, 0.08)
	tw.tween_property(statue, "rotation:z", 0.0, 0.1)
	if player.hud:
		player.hud.flash(Color(1.0, 0.75, 0.5))
		player.hud.announce("¡EL CULO ESTÁ SATISFECHO!")


## Al entrar en el skatepark por primera vez aparece el colega
func on_enter() -> void:
	if npc_spawned:
		return
	var scene = get_tree().current_scene
	if scene and scene.get("rounds"):
		npc_spawned = true
		scene.rounds.spawn_special("npc", to_global(Vector3(-6, 0.1, -10)))


func contains(p: Vector3) -> bool:
	var lp := p - position
	return absf(lp.x) < 200.0 and absf(lp.z) < 200.0


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
	var lim := PLAY.grow(7.0)
	nm.filter_baking_aabb = AABB(Vector3(lim.position.x, -1.5, lim.position.y), Vector3(lim.size.x, 4.1, lim.size.y))
	nav.navigation_mesh = nm
	nav.bake_navigation_mesh(false)


## Interactuar con la estatua: meterle el pepino cuando está llena
class StatueFeeder extends Node3D:
	var sp

	func can_interact(player) -> bool:
		return not sp.satisfied and player.global_position.distance_to(sp.statue.global_position) < 4.5

	func get_prompt(_player) -> String:
		if sp.fed < sp.FEED_NEEDED:
			return "La estatua tiene hambre: mata zombies cerca con el Cañón Dorado (%d/%d)" % [sp.fed, sp.FEED_NEEDED]
		if not sp.town.get_parent().parts.get("pepino", false):
			return "Le falta algo..."
		return "Pulsa [F] para meterle el pepino"

	func is_hold() -> bool:
		return false

	func interact(player) -> void:
		if sp.fed >= sp.FEED_NEEDED and sp.town.get_parent().parts.get("pepino", false):
			sp.feed_pepino(player)
